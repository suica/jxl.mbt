// Port of moxcms 0.9.0 `transform.rs`: `ColorProfile::create_transform_f32`
// and `create_transform_nbit::<f32, 1, 65536, 32768>`.

///|
const F32_BIT_DEPTH : Int32 = 1

///|
const F32_LINEAR_CAP : Int32 = 65536

///|
const F32_GAMMA_CAP : Int32 = 32768

///|
/// Creates a transform between this (source) profile and `dst_pr`.
///
/// Data has to be normalized into [0, 1] range; `f32` is treated as 14-bit
/// values.
pub fn ColorProfile::create_transform_f32(
  self : ColorProfile,
  src_layout : Layout,
  dst_pr : ColorProfile,
  dst_layout : Layout,
  options : TransformOptions,
) -> TransformF32Executor raise CmsError {
  let core_src_layout = if src_layout == Cmyka { Rgba } else { src_layout }
  let core_dst_layout = if dst_layout == Cmyka { Rgba } else { dst_layout }
  let handle = self.create_transform_nbit(
    core_src_layout, dst_pr, core_dst_layout, options,
  )
  // Upstream compares the *core* layouts with `Cmyka` here, which can never
  // match, so the CMYKA interceptors are never installed.
  handle
}

///|
fn ColorProfile::create_transform_nbit(
  self : ColorProfile,
  src_layout : Layout,
  dst_pr : ColorProfile,
  dst_layout : Layout,
  options : TransformOptions,
) -> TransformF32Executor raise CmsError {
  let bit_depth = F32_BIT_DEPTH
  let linear_cap = F32_LINEAR_CAP
  let gamma_cap = F32_GAMMA_CAP
  let use_cicp = options.allow_use_cicp_transfer
  if self.color_space == Rgb &&
    dst_pr.pcs == Xyz &&
    dst_pr.color_space == Rgb &&
    self.pcs == Xyz &&
    self.is_matrix_shaper() &&
    dst_pr.is_matrix_shaper() {
    if src_layout == Gray || src_layout == GrayAlpha {
      raise InvalidLayout
    }
    if dst_layout == Gray || dst_layout == GrayAlpha {
      raise InvalidLayout
    }
    if self.has_device_to_pcs_lut() || dst_pr.has_pcs_to_device_lut() {
      return make_lut_transform(src_layout, self, dst_layout, dst_pr, options)
    }
    let transform = self.transform_matrix(dst_pr)
    if self.are_all_trc_the_same() && dst_pr.are_all_trc_the_same() {
      let linear = self.build_r_linearize_table(linear_cap, use_cicp)
      let gamma = dst_pr.build_gamma_table(
        dst_pr.red_trc,
        65536,
        gamma_cap,
        bit_depth,
        use_cicp,
      )
      let profile_transform = TransformMatrixShaperOptimized::{
        linear,
        gamma,
        adaptation_matrix: transform.to_f32(),
      }
      // `RgbXyzFactoryOpt<f32>`: `prefer_fixed_point` and AVX2 select the
      // Q2.13 AVX2 executor; otherwise `make_rgb_xyz_rgb_transform_opt`
      // (AVX2+FMA `TransformShaperRgbOptAvx` is behind the non-default
      // `avx_shaper_optimized_paths` feature, so the SSE4.1 optimized path
      // is also absent and the scalar executor runs).
      if options.prefer_fixed_point {
        return make_rgb_xyz_q2_13_transform_avx2_opt(
          src_layout, dst_layout, profile_transform, gamma_cap, bit_depth,
        )
      }
      return make_rgb_xyz_rgb_transform_opt(
        src_layout, dst_layout, profile_transform, gamma_cap, bit_depth,
      )
    }
    let lin_r = self.build_r_linearize_table(linear_cap, use_cicp)
    let lin_g = self.build_g_linearize_table(linear_cap, use_cicp)
    let lin_b = self.build_b_linearize_table(linear_cap, use_cicp)
    let gamma_r = dst_pr.build_gamma_table(
      dst_pr.red_trc,
      65536,
      gamma_cap,
      bit_depth,
      use_cicp,
    )
    let gamma_g = dst_pr.build_gamma_table(
      dst_pr.green_trc,
      65536,
      gamma_cap,
      bit_depth,
      use_cicp,
    )
    let gamma_b = dst_pr.build_gamma_table(
      dst_pr.blue_trc,
      65536,
      gamma_cap,
      bit_depth,
      use_cicp,
    )
    let profile_transform = TransformMatrixShaper::{
      r_linear: lin_r,
      g_linear: lin_g,
      b_linear: lin_b,
      r_gamma: gamma_r,
      g_gamma: gamma_g,
      b_gamma: gamma_b,
      adaptation_matrix: transform.to_f32(),
    }
    // `RgbXyzFactory<f32>` -> `make_rgb_xyz_rgb_transform`: AVX2 + FMA.
    make_rgb_xyz_rgb_transform_avx2(
      src_layout, dst_layout, profile_transform, gamma_cap, bit_depth,
    )
  } else if self.color_space == Gray &&
    self.gray_trc is Some(_) &&
    (
      dst_pr.color_space == Rgb ||
      (dst_pr.color_space == Gray && dst_pr.gray_trc is Some(_))
    ) &&
    self.pcs == Xyz &&
    dst_pr.pcs == Xyz {
    if src_layout != GrayAlpha && src_layout != Gray {
      raise InvalidLayout
    }
    if self.has_device_to_pcs_lut() || dst_pr.has_pcs_to_device_lut() {
      return make_lut_transform(src_layout, self, dst_layout, dst_pr, options)
    }
    let gray_linear = self.build_gray_linearize_table(linear_cap)
    if dst_pr.color_space == Gray {
      // Gray -> Gray case
      let gray_gamma = dst_pr.build_gamma_table(
        dst_pr.gray_trc,
        65536,
        gamma_cap,
        bit_depth,
        use_cicp,
      )
      make_gray_to_x(
        src_layout, dst_layout, gray_linear, gray_gamma, bit_depth, gamma_cap,
      )
    } else if dst_pr.are_all_trc_the_same() {
      // Gray -> RGB where all TRC is the same
      let rgb_gamma = dst_pr.build_gamma_table(
        dst_pr.red_trc,
        65536,
        gamma_cap,
        bit_depth,
        use_cicp,
      )
      make_gray_to_x(
        src_layout, dst_layout, gray_linear, rgb_gamma, bit_depth, gamma_cap,
      )
    } else {
      // Gray -> RGB where all TRC is NOT the same
      let red_gamma = dst_pr.build_gamma_table(
        dst_pr.red_trc,
        65536,
        gamma_cap,
        bit_depth,
        use_cicp,
      )
      let green_gamma = dst_pr.build_gamma_table(
        dst_pr.green_trc,
        65536,
        gamma_cap,
        bit_depth,
        use_cicp,
      )
      let blue_gamma = dst_pr.build_gamma_table(
        dst_pr.blue_trc,
        65536,
        gamma_cap,
        bit_depth,
        use_cicp,
      )
      let gray_linear2 = FixedArray::make(65536, (0.0 : Float))
      for i in 0..<gray_linear.length().min(65536) {
        gray_linear2[i] = gray_linear[i]
      }
      make_gray_to_unfused(
        src_layout, dst_layout, gray_linear2, red_gamma, green_gamma, blue_gamma,
        bit_depth, gamma_cap,
      )
    }
  } else if self.color_space == Rgb &&
    dst_pr.color_space == Gray &&
    dst_pr.gray_trc is Some(_) &&
    dst_pr.pcs == Xyz &&
    self.pcs == Xyz {
    if src_layout == Gray || src_layout == GrayAlpha {
      raise InvalidLayout
    }
    if dst_layout != Gray && dst_layout != GrayAlpha {
      raise InvalidLayout
    }
    if self.has_device_to_pcs_lut() || dst_pr.has_pcs_to_device_lut() {
      return make_lut_transform(src_layout, self, dst_layout, dst_pr, options)
    }
    let transform = self.transform_matrix(dst_pr).to_f32()
    let vector = Vector3f::{
      v: [transform.v[1][0], transform.v[1][1], transform.v[1][2]],
    }
    let lin_r = self.build_r_linearize_table(linear_cap, use_cicp)
    let lin_g = self.build_g_linearize_table(linear_cap, use_cicp)
    let lin_b = self.build_b_linearize_table(linear_cap, use_cicp)
    let gray_linear = dst_pr.build_gamma_table(
      dst_pr.gray_trc,
      65536,
      gamma_cap,
      bit_depth,
      use_cicp,
    )
    make_rgb_to_gray(
      src_layout, dst_layout, lin_r, lin_g, lin_b, gray_linear, vector, gamma_cap,
      bit_depth,
    )
  } else if (
      self.color_space.is_three_channels() ||
      self.color_space == Cmyk ||
      self.color_space == Color4
    ) &&
    (
      dst_pr.color_space.is_three_channels() ||
      dst_pr.color_space == Cmyk ||
      dst_pr.color_space == Color4
    ) &&
    (dst_pr.pcs == Xyz || dst_pr.pcs == Lab) &&
    (self.pcs == Xyz || self.pcs == Lab) {
    if src_layout == Gray || src_layout == GrayAlpha {
      raise InvalidLayout
    }
    if dst_layout == Gray || dst_layout == GrayAlpha {
      raise InvalidLayout
    }
    make_lut_transform(src_layout, self, dst_layout, dst_pr, options)
  } else {
    make_lut_transform(src_layout, self, dst_layout, dst_pr, options)
  }
}

///|
// TEMPORARY until the LUT pipeline lands.
fn make_lut_transform(
  _src_layout : Layout,
  _source : ColorProfile,
  _dst_layout : Layout,
  _dest : ColorProfile,
  _options : TransformOptions,
) -> TransformF32Executor raise CmsError {
  raise UnsupportedProfileConnection
}
