// Port of jxl-color/src/gamut.rs: map out-of-gamut RGB samples, ported from libjxl.
// Only the generic (scalar) implementation is ported.

///|
/// Rust `f32::max`: returns the other operand if one is NaN.
fn f32_max(a : Float, b : Float) -> Float {
  if a.is_nan() {
    b
  } else if b.is_nan() {
    a
  } else if a > b {
    a
  } else {
    b
  }
}

///|
/// Rust `f32::clamp`.
fn f32_clamp(v : Float, min : Float, max : Float) -> Float {
  let mut x = v
  if x < min {
    x = min
  }
  if x > max {
    x = max
  }
  x
}

///|
fn map_gamut_generic(
  rgb : FixedArray[Float],
  luminance : FixedArray[Float],
  saturation_factor : Float,
) -> FixedArray[Float] {
  let r = rgb[0]
  let g = rgb[1]
  let b = rgb[2]
  let lr = luminance[0]
  let lg = luminance[1]
  let lb = luminance[2]
  let y = r * lr + g * lg + b * lb
  let mut gray_saturation : Float = 0.0
  let mut gray_luminance : Float = 0.0
  for i in 0..<3 {
    let v = rgb[i]
    let v_sub_y = v - y
    let inv_v_sub_y = (1.0 : Float) /
      (if v_sub_y == 0.0 { (1.0 : Float) } else { v_sub_y })
    let v_over_v_sub_y = v * inv_v_sub_y
    gray_saturation = if v_sub_y >= 0.0 {
      gray_saturation
    } else {
      f32_max(gray_saturation, v_over_v_sub_y)
    }
    gray_luminance = f32_max(
      if v_sub_y <= 0.0 {
        gray_saturation
      } else {
        v_over_v_sub_y - inv_v_sub_y
      },
      gray_luminance,
    )
  }
  let gray_mix = f32_clamp(
    saturation_factor * (gray_saturation - gray_luminance) + gray_luminance,
    0.0,
    1.0,
  )
  let mut max_color_val : Float = 1.0
  for i in 0..<3 {
    max_color_val = f32_max(rgb[i], max_color_val)
  }
  FixedArray::makei(3, i => {
    let v = rgb[i]
    (gray_mix * (y - v) + v) / max_color_val
  })
}
