// Port of moxcms 0.9.0 `conversions/gray2rgb.rs` and
// `conversions/rgb2gray.rs` for `f32`.

///|
fn is_gray_layout(l : Layout) -> Bool {
  l == Gray || l == GrayAlpha
}

///|
/// `make_gray_to_x` (`TransformGray2RgbFusedExecutor`).
fn make_gray_to_x(
  src_layout : Layout,
  dst_layout : Layout,
  gray_linear : FixedArray[Float],
  gray_gamma : FixedArray[Float],
  bit_depth : Int32,
  gamma_lut : Int32,
) -> TransformF32Executor raise CmsError {
  if !is_gray_layout(src_layout) {
    raise UnsupportedProfileConnection
  }
  let fused_gamma = FixedArray::make(65536, (0.0 : Float))
  let max_lut_size = Float::from_int(gamma_lut - 1)
  let max_lut_u32 = f2u32(max_lut_size)
  for i in 0..<gray_linear.length().min(65536) {
    let src = gray_linear[i]
    let v = f2u32(fround(src * max_lut_size))
    let possible_value = (if v < max_lut_u32 { v } else { max_lut_u32 }).reinterpret_as_int() &
      0xFFFF
    fused_gamma[i] = gray_gamma[possible_value]
  }
  match dst_layout {
    Rgb | Rgba | Gray | GrayAlpha => ()
    _ => raise UnsupportedProfileConnection
  }
  let src_channels = src_layout.channels()
  let dst_channels = dst_layout.channels()
  let is_gray_alpha = src_layout == GrayAlpha
  let max_value = Float::from_uint((1U << bit_depth) - 1U)
  {
    exec: fn(src, src_len, dst, dst_len) {
      check_lanes(src_len, src_channels, dst_len, dst_channels)
      let n = pixel_count(src_len, src_channels, dst_len, dst_channels)
      for p in 0..<n {
        let s = p * src_channels
        let d = p * dst_channels
        let g = fused_gamma[f32_as_usize(src[s])]
        let a = if is_gray_alpha { src[s + 1] } else { max_value }
        dst[d] = g
        if dst_layout == GrayAlpha {
          dst[d + 1] = a
        } else if dst_layout == Rgb {
          dst[d + 1] = g
          dst[d + 2] = g
        } else if dst_layout == Rgba {
          dst[d + 1] = g
          dst[d + 2] = g
          dst[d + 3] = a
        }
      }
    },
  }
}

///|
/// `f32 as u32` (saturating, NaN to 0).
fn f2u32(x : Float) -> UInt32 {
  let d = x.to_double()
  if d.is_nan() || d <= 0.0 {
    0
  } else if d >= 4294967295.0 {
    4294967295
  } else {
    d.trunc().to_uint()
  }
}

///|
/// `make_gray_to_unfused` (`TransformGrayToRgbExecutor`).
fn make_gray_to_unfused(
  src_layout : Layout,
  dst_layout : Layout,
  gray_linear : FixedArray[Float],
  red_gamma : FixedArray[Float],
  green_gamma : FixedArray[Float],
  blue_gamma : FixedArray[Float],
  bit_depth : Int32,
  gamma_lut : Int32,
) -> TransformF32Executor raise CmsError {
  if !is_gray_layout(src_layout) {
    raise UnsupportedProfileConnection
  }
  if dst_layout != Rgb && dst_layout != Rgba {
    raise UnsupportedProfileConnection
  }
  let src_channels = src_layout.channels()
  let dst_channels = dst_layout.channels()
  let is_gray_alpha = src_layout == GrayAlpha
  let max_value = Float::from_uint((1U << bit_depth) - 1U)
  let max_lut_size = Float::from_int(gamma_lut - 1)
  {
    exec: fn(src, src_len, dst, dst_len) {
      check_lanes(src_len, src_channels, dst_len, dst_channels)
      let n = pixel_count(src_len, src_channels, dst_len, dst_channels)
      for p in 0..<n {
        let s = p * src_channels
        let d = p * dst_channels
        let g = gray_linear[f32_as_usize(src[s])]
        let a = if is_gray_alpha { src[s + 1] } else { max_value }
        let possible_value = f2u16(fround(g * max_lut_size))
        dst[d] = red_gamma[possible_value]
        dst[d + 1] = green_gamma[possible_value]
        dst[d + 2] = blue_gamma[possible_value]
        if dst_layout == Rgba {
          dst[d + 3] = a
        }
      }
    },
  }
}

///|
/// `make_rgb_to_gray` (`TransformRgbToGrayExecutor`).
fn make_rgb_to_gray(
  src_layout : Layout,
  dst_layout : Layout,
  r_linear : FixedArray[Float],
  g_linear : FixedArray[Float],
  b_linear : FixedArray[Float],
  gray_gamma : FixedArray[Float],
  weights : Vector3f,
  gamma_lut : Int32,
  bit_depth : Int32,
) -> TransformF32Executor raise CmsError {
  match (src_layout, dst_layout) {
    (Rgb | Rgba, Gray | GrayAlpha) => ()
    _ => raise UnsupportedProfileConnection
  }
  let src_channels = src_layout.channels()
  let dst_channels = dst_layout.channels()
  let scale_value = Float::from_int(gamma_lut - 1)
  let max_value = Float::from_uint((1U << bit_depth) - 1U)
  let w = weights.v
  {
    exec: fn(src, src_len, dst, dst_len) {
      check_lanes(src_len, src_channels, dst_len, dst_channels)
      let n = pixel_count(src_len, src_channels, dst_len, dst_channels)
      for p in 0..<n {
        let s = p * src_channels
        let d = p * dst_channels
        let r = r_linear[f32_as_usize(src[s])]
        let g = g_linear[f32_as_usize(src[s + 1])]
        let b = b_linear[f32_as_usize(src[s + 2])]
        let a = if src_channels == 4 { src[s + 3] } else { max_value }
        let mixed = fmax(fmin(w[0] * r + w[1] * g + w[2] * b, 1.0), 0.0)
        let grey : Float = 0.5 + mixed * scale_value
        dst[d] = gray_gamma[f2u16(grey)]
        if dst_channels == 2 {
          dst[d + 1] = a
        }
      }
    },
  }
}
