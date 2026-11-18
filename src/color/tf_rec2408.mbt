// Port of jxl-color `tf/rec2408.rs`: Rec. ITU-R BT.2408 EETF (generic implementation).

///|
fn rec2408_eetf_generic(
  from_pq_sample : Float,
  intensity_target : Float,
  from_luminance_range : (Float, Float),
  to_luminance_range : (Float, Float),
) -> Float {
  // Lb, Lw, Lmin, Lmax
  let lb = linear_to_pq_generic(
    from_luminance_range.0 / intensity_target,
    intensity_target,
  )
  let lw = linear_to_pq_generic(
    from_luminance_range.1 / intensity_target,
    intensity_target,
  )
  let lmin = linear_to_pq_generic(
    to_luminance_range.0 / intensity_target,
    intensity_target,
  )
  let lmax = linear_to_pq_generic(
    to_luminance_range.1 / intensity_target,
    intensity_target,
  )

  // Step 1
  let source_pq_diff = lw - lb
  let normalized_source_pq_sample = (from_pq_sample - lb) / source_pq_diff
  let min_luminance = (lmin - lb) / source_pq_diff
  let max_luminance = (lmax - lb) / source_pq_diff

  // Step 2
  let ks = (1.5 : Float) * max_luminance - 0.5
  let b = min_luminance

  // Step 3
  let compressed_pq_sample = if normalized_source_pq_sample < ks {
    normalized_source_pq_sample
  } else {
    // Step 4
    let one_sub_ks = (1.0 : Float) - ks
    let t = (normalized_source_pq_sample - ks) / one_sub_ks
    let t_p2 = t * t
    let t_p3 = t_p2 * t
    ((2.0 : Float) * t_p3 - 3.0 * t_p2 + 1.0) * ks +
    (t_p3 - (2.0 : Float) * t_p2 + t) * one_sub_ks +
    ((-2.0 : Float) * t_p3 + (3.0 : Float) * t_p2) * max_luminance
  }
  let one_sub_compressed_p4 = {
    let x : Float = 1.0 - compressed_pq_sample
    x * x * x * x
  }
  let normalized_target_pq_sample = one_sub_compressed_p4 * b +
    compressed_pq_sample

  // Step 5
  normalized_target_pq_sample * source_pq_diff + lb
}
