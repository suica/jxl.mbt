// Matrix shaper executors for `f32` (`conversions/rgbxyz.rs`,
// `conversions/rgbxyz_fixed.rs`, `conversions/rgb_xyz_factory.rs`).
//
// Upstream dispatches at run time; on x86_64 with AVX2 and FMA (the reference
// platform) it picks:
// - all TRCs the same, `prefer_fixed_point` (the default):
//   `TransformShaperRgbQ2_13OptAvx` (`conversions/avx/rgb_xyz_q2_13_opt.rs`),
//   Q2.13 fixed point with `_mm256_madd_epi16`;
// - otherwise `TransformShaperRgbAvx` (`conversions/avx/rgb_xyz.rs`), f32
//   with `_mm256_fmadd_ps`.
// Both are ported lane by lane below; the arithmetic is the one those SIMD
// routines perform.

///|
const FIXED_POINT_SCALE : Int32 = 13

///|
priv struct TransformMatrixShaper {
  r_linear : FixedArray[Float]
  g_linear : FixedArray[Float]
  b_linear : FixedArray[Float]
  r_gamma : FixedArray[Float]
  g_gamma : FixedArray[Float]
  b_gamma : FixedArray[Float]
  adaptation_matrix : Matrix3f
}

///|
priv struct TransformMatrixShaperOptimized {
  linear : FixedArray[Float]
  gamma : FixedArray[Float]
  adaptation_matrix : Matrix3f
}

///|
fn is_rgb_layout_pair(src_layout : Layout, dst_layout : Layout) -> Bool {
  (src_layout == Rgb || src_layout == Rgba) &&
  (dst_layout == Rgb || dst_layout == Rgba)
}

///|
/// `_mm_max_ps(v, 0)`: the second operand when either is NaN or both are
/// zero.
fn sse_max_zero(v : Float) -> Float {
  if v > 0.0 {
    v
  } else {
    0.0
  }
}

///|
/// `_mm_min_ps(a, b)`: `a < b ? a : b`.
fn sse_min(a : Float, b : Float) -> Float {
  if a < b {
    a
  } else {
    b
  }
}

///|
/// `_mm_cvtps_epi32` (round to nearest even; out of range gives i32::MIN).
fn cvtps_epi32(v : Float) -> Int32 {
  if v.is_nan() {
    return -2147483648
  }
  let d = v.to_double()
  if d >= 2147483648.0 || d < -2147483648.0 {
    return -2147483648
  }
  let t = d.floor()
  let diff = d - t
  let r = if diff > 0.5 {
    t + 1.0
  } else if diff < 0.5 {
    t
  } else if t % 2.0 == 0.0 {
    t
  } else {
    t + 1.0
  }
  r.to_int()
}

///|
/// `TransformShaperRgbAvx::transform_impl::<true>`.
fn make_rgb_xyz_rgb_transform_avx2(
  src_layout : Layout,
  dst_layout : Layout,
  profile : TransformMatrixShaper,
  gamma_lut : Int32,
  bit_depth : Int32,
) -> TransformF32Executor raise CmsError {
  if !is_rgb_layout_pair(src_layout, dst_layout) {
    raise UnsupportedProfileConnection
  }
  let src_channels = src_layout.channels()
  let dst_channels = dst_layout.channels()
  let t = profile.adaptation_matrix.transpose()
  let scale = Float::from_int(gamma_lut - 1)
  let max_colors = Float::from_int((1 << bit_depth) - 1)
  let m0 = t.v[0]
  let m1 = t.v[1]
  let m2 = t.v[2]
  {
    exec: fn(src, src_len, dst, dst_len) {
      check_lanes(src_len, src_channels, dst_len, dst_channels)
      let n = pixel_count(src_len, src_channels, dst_len, dst_channels)
      for p in 0..<n {
        let s = p * src_channels
        let d = p * dst_channels
        let r = profile.r_linear[f32_as_usize(src[s])]
        let g = profile.g_linear[f32_as_usize(src[s + 1])]
        let b = profile.b_linear[f32_as_usize(src[s + 2])]
        let a = if src_channels == 4 { src[s + 3] } else { max_colors }
        let idx = FixedArray::make(3, 0)
        for k in 0..<3 {
          let v0 = r * m0[k]
          let v1 = fma_f32(g, m1[k], v0)
          let mut v = fma_f32(b, m2[k], v1)
          v = sse_max_zero(v)
          v = v * scale
          v = sse_min(v, scale)
          idx[k] = cvtps_epi32(v) & 0xFFFF
        }
        dst[d] = profile.r_gamma[idx[0]]
        dst[d + 1] = profile.g_gamma[idx[1]]
        dst[d + 2] = profile.b_gamma[idx[2]]
        if dst_channels == 4 {
          dst[d + 3] = a
        }
      }
    },
  }
}

///|
/// `TransformMatrixShaperOptimized::to_q2_13_i::<i32, PRECISION>` followed by
/// `TransformShaperRgbQ2_13OptAvx::transform_avx2`.
fn make_rgb_xyz_q2_13_transform_avx2_opt(
  src_layout : Layout,
  dst_layout : Layout,
  profile : TransformMatrixShaperOptimized,
  gamma_lut : Int32,
  bit_depth : Int32,
) -> TransformF32Executor raise CmsError {
  let precision = FIXED_POINT_SCALE
  // to_q2_13_i (T::FINITE == false)
  let lut_scale = Float::from_int(gamma_lut - 1) /
    Float::from_int(NOT_FINITE_LINEAR_TABLE_SIZE - 1)
  let linear_scale = Float::from_int(NOT_FINITE_LINEAR_TABLE_SIZE - 1) *
    lut_scale
  let linear = FixedArray::make(profile.linear.length(), 0)
  for i in 0..<linear.length() {
    linear[i] = f2i(fround(profile.linear[i] * linear_scale))
  }
  let scale = Float::from_int(1 << precision)
  let am = FixedArray::make(9, 0)
  for i in 0..<3 {
    for j in 0..<3 {
      am[i * 3 + j] = f2i16(profile.adaptation_matrix.v[i][j] * scale)
    }
  }
  let gamma = profile.gamma
  if !is_rgb_layout_pair(src_layout, dst_layout) {
    raise UnsupportedProfileConnection
  }
  let src_channels = src_layout.channels()
  let dst_channels = dst_layout.channels()
  let max_colors = Float::from_int((1 << bit_depth) - 1)
  // rnd lane: (1 << (PRECISION - 1)) as i16 in the high half of each i32.
  let rnd = ((1 << (precision - 1)) & 0xFFFF) << 16
  let v_max_value = gamma_lut - 1
  {
    exec: fn(src, src_len, dst, dst_len) {
      check_lanes(src_len, src_channels, dst_len, dst_channels)
      let n = pixel_count(src_len, src_channels, dst_len, dst_channels)
      for p in 0..<n {
        let s = p * src_channels
        let d = p * dst_channels
        let r = linear[f32_as_usize(src[s])]
        let g = linear[f32_as_usize(src[s + 1])]
        let b = linear[f32_as_usize(src[s + 2])]
        let a = if src_channels == 4 { src[s + 3] } else { max_colors }
        let zrg = r | (g << 16)
        let zbz = b | rnd
        let idx = FixedArray::make(3, 0)
        for k in 0..<3 {
          // t = transpose(m): m0 lane k holds (t[0][k], t[1][k]),
          // m2 lane k holds (t[2][k], 1).
          let va0 = madd_epi16(zrg, am[k * 3], am[k * 3 + 1])
          let va1 = madd_epi16(zbz, am[k * 3 + 2], 1)
          let mut v = va0 + va1
          v = v >> precision
          if v < 0 {
            v = 0
          }
          if v > v_max_value {
            v = v_max_value
          }
          idx[k] = v & 0xFFFF
        }
        dst[d] = gamma[idx[0]]
        dst[d + 1] = gamma[idx[1]]
        dst[d + 2] = gamma[idx[2]]
        if dst_channels == 4 {
          dst[d + 3] = a
        }
      }
    },
  }
}

///|
/// One 32-bit lane of `_mm_madd_epi16`: the low and high signed 16-bit
/// halves of `lane` times `lo` and `hi`, summed with i32 wrap-around.
fn madd_epi16(lane : Int32, lo : Int32, hi : Int32) -> Int32 {
  let l = lane << 16 >> 16
  let h = lane >> 16
  l * lo + h * hi
}

///|
/// `make_rgb_xyz_rgb_transform_opt` on x86_64 with default features
/// (`TransformMatrixShaperOptScalar`). Only reached when
/// `prefer_fixed_point` is off, which jxl-oxide never does.
fn make_rgb_xyz_rgb_transform_opt(
  src_layout : Layout,
  dst_layout : Layout,
  profile : TransformMatrixShaperOptimized,
  gamma_lut : Int32,
  bit_depth : Int32,
) -> TransformF32Executor raise CmsError {
  if !is_rgb_layout_pair(src_layout, dst_layout) {
    raise UnsupportedProfileConnection
  }
  let src_channels = src_layout.channels()
  let dst_channels = dst_layout.channels()
  let m = profile.adaptation_matrix.v
  let scale = Float::from_int(gamma_lut - 1)
  let max_colors = Float::from_int((1 << bit_depth) - 1)
  let linear = profile.linear
  let gamma = profile.gamma
  {
    exec: fn(src, src_len, dst, dst_len) {
      check_lanes(src_len, src_channels, dst_len, dst_channels)
      let n = pixel_count(src_len, src_channels, dst_len, dst_channels)
      for p in 0..<n {
        let s = p * src_channels
        let d = p * dst_channels
        let r = linear[f32_as_usize(src[s])]
        let g = linear[f32_as_usize(src[s + 1])]
        let b = linear[f32_as_usize(src[s + 2])]
        let a = if src_channels == 4 { src[s + 3] } else { max_colors }
        for k in 0..<3 {
          let v = fmin(fmax(r * m[k][0] + g * m[k][1] + b * m[k][2], 0.0), 1.0)
          let nv : Float = 0.5 + v * scale
          dst[d + k] = gamma[f2u16(nv)]
        }
        if dst_channels == 4 {
          dst[d + 3] = a
        }
      }
    },
  }
}
