// Port of jxl-color `convert/tone_map.rs`.
//
// `tone_map`, `tone_map_luma` and `detect_peak_luminance` follow the x86_64
// AVX2 + FMA dispatch of upstream (8-wide AVX2 chunks, 4-wide FMA chunks,
// then the generic code), see `fastmath.mbt`.

///|
fn tone_map(
  r : FixedArray[Float],
  g : FixedArray[Float],
  b : FixedArray[Float],
  hdr_params : HdrParams,
  target_display_luminance : Float,
  detect_peak : Bool,
  start : Int32,
  len : Int32,
) -> Unit {
  let luminances = hdr_params.luminances
  let intensity_target = hdr_params.intensity_target
  let min_nits = hdr_params.min_nits
  let detected_peak_luminance = if detect_peak {
    detect_peak_luminance(r, g, b, luminances, start, len) * intensity_target
  } else {
    intensity_target
  }
  let peak_luminance = intensity_target.min(detected_peak_luminance)
  let from_luminance_range = (min_nits, peak_luminance)
  let to_luminance_range = ((0.0 : Float), target_display_luminance)
  // tone_map_x86_64_avx2 -> tone_map_x86_64_fma -> tone_map_generic
  let end = start + len
  let avx2_end = start + len / 8 * 8
  let fma_end = avx2_end + (end - avx2_end) / 4 * 4
  let params = Rec2408Params::new(
    intensity_target, from_luminance_range, to_luminance_range,
  )
  tone_map_simd(
    r, g, b, luminances, intensity_target, to_luminance_range, params, start, avx2_end,
    true,
  )
  tone_map_simd(
    r, g, b, luminances, intensity_target, to_luminance_range, params, avx2_end,
    fma_end, false,
  )
  tone_map_generic(
    r,
    g,
    b,
    luminances,
    intensity_target,
    from_luminance_range,
    to_luminance_range,
    fma_end,
    end - fma_end,
  )
}

///|
/// Lanes `start..end` of `tone_map_x86_64_avx2` (`avx2 = true`) or
/// `tone_map_x86_64_fma`.
fn tone_map_simd(
  r : FixedArray[Float],
  g : FixedArray[Float],
  b : FixedArray[Float],
  luminances : FixedArray[Float],
  intensity_target : Float,
  to_luminance_range : (Float, Float),
  params : Rec2408Params,
  start : Int32,
  end : Int32,
  avx2 : Bool,
) -> Unit {
  let scale = intensity_target / to_luminance_range.1
  let lr = luminances[0]
  let lg = luminances[1]
  let lb = luminances[2]
  for i in start..<end {
    let vr = r[i]
    let vg = g[i]
    let vb = b[i]
    let vy = mul_add_f32(vb, lb, mul_add_f32(vg, lg, vr * lr))
    let vy_pq = linear_to_pq_simd(vy, intensity_target, avx2)
    let vy_mapped = rec2408_eetf_simd(vy_pq, params)
    let vy_mapped = pq_to_linear_simd(vy_mapped, intensity_target)
    let vy : Float = if vy.abs() < 1.0e-7 { 1.0 } else { vy }
    let ratio = vy_mapped * scale / vy
    r[i] = vr * ratio
    g[i] = vg * ratio
    b[i] = vb * ratio
  }
}

///|
fn tone_map_luma(
  luma : FixedArray[Float],
  hdr_params : HdrParams,
  target_display_luminance : Float,
  detect_peak : Bool,
  start : Int32,
  len : Int32,
) -> Unit {
  let intensity_target = hdr_params.intensity_target
  let min_nits = hdr_params.min_nits
  let detected_peak_luminance = if detect_peak {
    let mut max_luma : Float = 0.0
    for i in start..<(start + len) {
      max_luma = max_luma.max(luma[i])
    }
    if max_luma == 0.0 {
      intensity_target
    } else {
      max_luma * intensity_target
    }
  } else {
    intensity_target
  }
  let peak_luminance = intensity_target.min(detected_peak_luminance)
  let from_luminance_range = (min_nits, peak_luminance)
  let to_luminance_range = ((0.0 : Float), target_display_luminance)
  // tone_map_luma_x86_64_avx2 -> tone_map_luma_x86_64_fma -> generic
  let end = start + len
  let avx2_end = start + len / 8 * 8
  let fma_end = avx2_end + (end - avx2_end) / 4 * 4
  let params = Rec2408Params::new(
    intensity_target, from_luminance_range, to_luminance_range,
  )
  let scale = intensity_target / to_luminance_range.1
  for i in start..<fma_end {
    let vy_pq = linear_to_pq_simd(luma[i], intensity_target, i < avx2_end)
    let vy_mapped = rec2408_eetf_simd(vy_pq, params)
    let vy_mapped = pq_to_linear_simd(vy_mapped, intensity_target)
    luma[i] = vy_mapped * scale
  }
  tone_map_luma_generic(
    luma,
    intensity_target,
    from_luminance_range,
    to_luminance_range,
    fma_end,
    end - fma_end,
  )
}

///|
fn tone_map_generic(
  r : FixedArray[Float],
  g : FixedArray[Float],
  b : FixedArray[Float],
  luminances : FixedArray[Float],
  intensity_target : Float,
  from_luminance_range : (Float, Float),
  to_luminance_range : (Float, Float),
  start : Int32,
  len : Int32,
) -> Unit {
  let scale = intensity_target / to_luminance_range.1
  let lr = luminances[0]
  let lg = luminances[1]
  let lb = luminances[2]
  for i in start..<(start + len) {
    let rv = r[i]
    let gv = g[i]
    let bv = b[i]
    let y = rv * lr + gv * lg + bv * lb
    let y_pq = linear_to_pq_generic(y, intensity_target)
    let y_mapped = rec2408_eetf_generic(
      y_pq, intensity_target, from_luminance_range, to_luminance_range,
    )
    let y_mapped = pq_to_linear_generic(y_mapped, intensity_target)
    let ratio = if y.abs() <= 1.0e-7 {
      y_mapped * scale
    } else {
      y_mapped / y * scale
    }
    r[i] = rv * ratio
    g[i] = gv * ratio
    b[i] = bv * ratio
  }
}

///|
fn tone_map_luma_generic(
  luma : FixedArray[Float],
  intensity_target : Float,
  from_luminance_range : (Float, Float),
  to_luminance_range : (Float, Float),
  start : Int32,
  len : Int32,
) -> Unit {
  let scale = intensity_target / to_luminance_range.1
  for i in start..<(start + len) {
    let y_pq = linear_to_pq_generic(luma[i], intensity_target)
    let y_mapped = rec2408_eetf_generic(
      y_pq, intensity_target, from_luminance_range, to_luminance_range,
    )
    let y_mapped = pq_to_linear_generic(y_mapped, intensity_target)
    luma[i] = y_mapped * scale
  }
}

///|
/// `detect_peak_luminance` on x86_64 with AVX2 + FMA
/// (`detect_peak_luminance_avx2`).
fn detect_peak_luminance(
  r : FixedArray[Float],
  g : FixedArray[Float],
  b : FixedArray[Float],
  luminances : FixedArray[Float],
  start : Int32,
  len : Int32,
) -> Float {
  let lr = luminances[0]
  let lg = luminances[1]
  let lb = luminances[2]
  let end = start + len
  let avx2_end = start + len / 8 * 8
  // 8 lanes of `_mm256_max_ps`
  let peak8 : FixedArray[Float] = FixedArray::make(8, 0.0)
  for i in start..<avx2_end {
    let vy = mul_add_f32(b[i], lb, mul_add_f32(g[i], lg, r[i] * lr))
    let lane = (i - start) % 8
    peak8[lane] = max_ps(peak8[lane], vy)
  }
  let peak4 = FixedArray::makei(4, j => max_ps(peak8[j], peak8[j + 4]))
  let mut rest = avx2_end
  if end - avx2_end >= 4 {
    for j in 0..<4 {
      let i = avx2_end + j
      let vy = mul_add_f32(b[i], lb, mul_add_f32(g[i], lg, r[i] * lr))
      peak4[j] = max_ps(peak4[j], vy)
    }
    rest = avx2_end + 4
  }
  let mut peak_luminance : Float = 0.0
  for v in peak4 {
    peak_luminance = peak_luminance.max(v)
  }
  for i in rest..<end {
    let y = mul_add_f32(b[i], lb, mul_add_f32(g[i], lg, r[i] * lr))
    peak_luminance = peak_luminance.max(y)
  }
  if peak_luminance <= 0.0 {
    1.0
  } else {
    peak_luminance
  }
}
