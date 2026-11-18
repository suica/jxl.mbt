// Port of jxl-color `convert/gamut_map.rs`.
//
// Follows the x86_64 AVX2 + FMA dispatch of upstream: 8-wide chunks through
// `map_gamut_x86_64_avx2`, the remainder through `map_gamut_generic`.

///|
fn gamut_map(
  r : FixedArray[Float],
  g : FixedArray[Float],
  b : FixedArray[Float],
  luminances : FixedArray[Float],
  saturation_factor : Float,
  start : Int32,
  len : Int32,
) -> Unit {
  let end = start + len
  let avx2_end = start + len / 8 * 8
  for i in start..<avx2_end {
    map_gamut_avx2_lane(r, g, b, i, luminances, saturation_factor)
  }
  let rgb : FixedArray[Float] = FixedArray::make(3, 0.0)
  for i in avx2_end..<end {
    rgb[0] = r[i]
    rgb[1] = g[i]
    rgb[2] = b[i]
    let mapped = map_gamut_generic(rgb, luminances, saturation_factor)
    r[i] = mapped[0]
    g[i] = mapped[1]
    b[i] = mapped[2]
  }
}

///|
/// One lane of `gamut::map_gamut_x86_64_avx2`, applied in place to sample
/// `i`. `SimdVector::muladd` is an unfused multiply and add (see
/// `rec2408_eetf_simd`).
fn map_gamut_avx2_lane(
  r : FixedArray[Float],
  g : FixedArray[Float],
  b : FixedArray[Float],
  i : Int32,
  luminance : FixedArray[Float],
  saturation_factor : Float,
) -> Unit {
  let vr = r[i]
  let vg = g[i]
  let vb = b[i]
  let y = mul_add_f32(
    vb,
    luminance[2],
    mul_add_f32(vg, luminance[1], vr * luminance[0]),
  )
  let mut gray_saturation : Float = 0.0
  let mut gray_luminance : Float = 0.0
  for k in 0..<3 {
    let v = if k == 0 { vr } else if k == 1 { vg } else { vb }
    let v_sub_y = v - y
    let inv_v_sub_y = (1.0 : Float) /
      (if v_sub_y == 0.0 { 1.0 } else { v_sub_y })
    let v_over_v_sub_y = v * inv_v_sub_y
    gray_saturation = if v_sub_y >= 0.0 {
      gray_saturation
    } else {
      max_ps(gray_saturation, v_over_v_sub_y)
    }
    gray_luminance = max_ps(
      if v_sub_y <= 0.0 {
        gray_saturation
      } else {
        v_over_v_sub_y - inv_v_sub_y
      },
      gray_luminance,
    )
  }
  let gray_mix = (gray_saturation - gray_luminance) * saturation_factor +
    gray_luminance
  let gray_mix = max_ps(0.0, min_ps(1.0, gray_mix))
  let max_color_val = max_ps(max_ps(max_ps(1.0, vr), vg), vb)
  r[i] = (gray_mix * (y - vr) + vr) / max_color_val
  g[i] = (gray_mix * (y - vg) + vg) / max_color_val
  b[i] = (gray_mix * (y - vb) + vb) / max_color_val
}
