// Port of jxl-color `tf/rec2408.rs`: Rec. ITU-R BT.2408 EETF.

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

///|
/// Constants of the Rec. 2408 EETF shared by all samples of a run.
priv struct Rec2408Params {
  lb : Float
  source_pq_diff : Float
  ks : Float
  b : Float
  one_sub_ks : Float
  max_luminance : Float
}

///|
fn Rec2408Params::new(
  intensity_target : Float,
  from_luminance_range : (Float, Float),
  to_luminance_range : (Float, Float),
) -> Rec2408Params {
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
  let source_pq_diff = lw - lb
  let min_luminance = (lmin - lb) / source_pq_diff
  let max_luminance = (lmax - lb) / source_pq_diff
  let ks = (1.5 : Float) * max_luminance - 0.5
  {
    lb,
    source_pq_diff,
    ks,
    b: min_luminance,
    one_sub_ks: 1.0 - ks,
    max_luminance,
  }
}

///|
/// One lane of `rec2408_eetf_x86_64_avx2` / `rec2408_eetf_x86_64_fma`.
///
/// `SimdVector::muladd` is a separate multiply and add here: upstream selects
/// the fused version only with the compile-time `target_feature = "fma"`,
/// which a default x86_64 build does not have.
fn rec2408_eetf_simd(from_pq_sample : Float, p : Rec2408Params) -> Float {
  // Step 1
  let normalized_source_pq_sample = (from_pq_sample - p.lb) / p.source_pq_diff
  // Step 4
  let t = (normalized_source_pq_sample - p.ks) / p.one_sub_ks
  let t_p2 = t * t
  let t_p3 = t_p2 * t
  let a = t_p3 * 2.0 + (t_p2 * -3.0 + 1.0)
  let c = t_p2 * -2.0 + (t_p3 + t)
  let d = p.max_luminance * (t_p3 * -2.0 + t_p2 * 3.0)
  let compressed_pq_sample = p.ks * a + (p.one_sub_ks * c + d)
  // Step 3
  let compressed_pq_sample = if normalized_source_pq_sample < p.ks {
    normalized_source_pq_sample
  } else {
    compressed_pq_sample
  }
  let one_sub_compressed_p4 = {
    let x : Float = 1.0 - compressed_pq_sample
    let x2 = x * x
    x2 * x2
  }
  let normalized_target_pq_sample = p.b * one_sub_compressed_p4 +
    compressed_pq_sample
  // Step 5
  normalized_target_pq_sample * p.source_pq_diff + p.lb
}
