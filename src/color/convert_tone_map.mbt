// Port of jxl-color `convert/tone_map.rs` (generic implementation).

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
  tone_map_generic(
    r, g, b, luminances, intensity_target, from_luminance_range, to_luminance_range,
    start, len,
  )
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
  tone_map_luma_generic(
    luma, intensity_target, from_luminance_range, to_luminance_range, start, len,
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
  let mut peak_luminance : Float = 0.0
  for i in start..<(start + len) {
    let y = r[i] * lr + g[i] * lg + b[i] * lb
    peak_luminance = if peak_luminance < y { y } else { peak_luminance }
  }
  if peak_luminance <= 0.0 {
    1.0
  } else {
    peak_luminance
  }
}
