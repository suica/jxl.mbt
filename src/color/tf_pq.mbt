// Port of jxl-color `tf/pq.rs`: approximation of perceptual quantizer transfer
// functions, ported from libjxl.

///|
let pq_eotf_p : FixedArray[Float] = [
  2.6297566e-4, -6.235531e-3, 7.386023e-1, 2.6455317, 5.500349e-1,
]

///|
let pq_eotf_q : FixedArray[Float] = [
  4.213501e2, -4.2873682e2, 1.7436467e2, -3.3907887e1, 2.6771877,
]

///|
let pq_inv_eotf_p : FixedArray[Float] = [
  1.351392e-2, -1.095778, 5.522776e1, 1.492516e2, 4.838434e1,
]

///|
let pq_inv_eotf_q : FixedArray[Float] = [
  1.012416, 2.016708e1, 9.26371e1, 1.120607e2, 2.590418e1,
]

///|
let pq_inv_eotf_p_small : FixedArray[Float] = [
  9.863406e-6, 3.881234e-1, 1.352821e2, 6.889862e4, -2.864824e5,
]

///|
let pq_inv_eotf_q_small : FixedArray[Float] = [
  3.371868e1, 1.477719e3, 1.608477e4, -4.389884e4, -2.072546e5,
]

///|
/// Converts the linear samples with the PQ transfer function, where linear sample value of 1.0
/// represents `intensity_target` nits (PQ inverse EOTF).
pub fn linear_to_pq(
  samples : FixedArray[Float],
  intensity_target : Float,
  start~ : Int32 = 0,
  len~ : Int32 = samples.length() - start,
) -> Unit {
  // x86_64 AVX2 + FMA path: 8-wide AVX2 chunks, 4-wide FMA chunks, then the
  // generic code for the remainder.
  let end = start + len
  let avx2_end = start + len / 8 * 8
  let fma_end = avx2_end + (end - avx2_end) / 4 * 4
  for i in start..<avx2_end {
    samples[i] = linear_to_pq_simd(samples[i], intensity_target, true)
  }
  for i in avx2_end..<fma_end {
    samples[i] = linear_to_pq_simd(samples[i], intensity_target, false)
  }
  for i in fma_end..<end {
    samples[i] = linear_to_pq_generic(samples[i], intensity_target)
  }
}

///|
/// One lane of `linear_to_pq_x86_64_avx2` (`avx2 = true`, small-value test
/// `a <= 1e-4`) or `linear_to_pq_x86_64_fma` (`a < 1e-4`).
fn linear_to_pq_simd(v : Float, intensity_target : Float, avx2 : Bool) -> Float {
  let y_mult = intensity_target / 10000.0
  let a = v.abs()
  let a_scaled = a * y_mult
  let a_1_4 = a_scaled.sqrt().sqrt()
  let v_small = rational_poly_eval_fma(
    a_1_4, pq_inv_eotf_p_small, pq_inv_eotf_q_small,
  )
  let v_large = rational_poly_eval_fma(a_1_4, pq_inv_eotf_p, pq_inv_eotf_q)
  let is_small = if avx2 { a <= 1.0e-4 } else { a < 1.0e-4 }
  or_sign(if is_small { v_small } else { v_large }, v)
}

///|
fn linear_to_pq_generic(s : Float, intensity_target : Float) -> Float {
  let y_mult = intensity_target / 10000.0
  let a = s.abs()
  let a_scaled = a * y_mult
  let a_1_4 = a_scaled.sqrt().sqrt()
  let y = if a < 1.0e-4 {
    rational_poly_eval_generic(a_1_4, pq_inv_eotf_p_small, pq_inv_eotf_q_small)
  } else {
    rational_poly_eval_generic(a_1_4, pq_inv_eotf_p, pq_inv_eotf_q)
  }
  copysign_f32(y, s)
}

///|
/// Converts non-linear PQ signals to linear display luminance values, where luminance value of 1.0
/// represents `intensity_target` nits (PQ EOTF).
pub fn pq_to_linear(
  samples : FixedArray[Float],
  intensity_target : Float,
  start~ : Int32 = 0,
  len~ : Int32 = samples.length() - start,
) -> Unit {
  // x86_64 AVX2 + FMA path: 8-wide AVX2 chunks, 4-wide FMA chunks, then the
  // generic code for the remainder.
  let end = start + len
  let simd_end = start + len / 4 * 4
  for i in start..<simd_end {
    samples[i] = pq_to_linear_simd(samples[i], intensity_target)
  }
  for i in simd_end..<end {
    samples[i] = pq_to_linear_generic(samples[i], intensity_target)
  }
}

///|
/// One lane of `pq_to_linear_x86_64_avx2` / `pq_to_linear_x86_64_fma`.
fn pq_to_linear_simd(v : Float, intensity_target : Float) -> Float {
  let y_mult = (10000.0 : Float) / intensity_target
  let a = v.abs()
  let x = mul_add_f32(a, a, a)
  let y = rational_poly_eval_fma(x, pq_eotf_p, pq_eotf_q)
  or_sign(y * y_mult, v)
}

///|
fn pq_to_linear_generic(s : Float, intensity_target : Float) -> Float {
  let y_mult = (10000.0 : Float) / intensity_target
  let a = s.abs()
  let x = mul_add_f32(a, a, a)
  let y = rational_poly_eval_generic(x, pq_eotf_p, pq_eotf_q)
  copysign_f32(y * y_mult, s)
}

///|
/// Lookup table of the PQ EOTF with `n` entries, scaled to `0..=65535`
/// (used for ICC profile synthesis).
pub fn pq_table(n : Int32) -> Array[Int32] {
  let m1_recip_f64 = 8192.0 / 1305.0
  let m2_recip_f64 = 32.0 / 2523.0
  let c1_f64 = 107.0 / 128.0
  let c2_f64 = 2413.0 / 128.0
  let c3_f64 = 2392.0 / 128.0
  let out = Array::make(n, 0)
  for idx in 0..<n {
    let e = idx.to_double() / (n - 1).to_double()
    let e_pow = @math.pow(e, m2_recip_f64)
    let numerator = (e_pow - c1_f64).max(0.0)
    let denominator = mul_add_f64(e_pow, -c3_f64, c2_f64)
    let d = @math.pow(numerator / denominator, m1_recip_f64)
    out[idx] = f64_to_u16_saturating(d * 65535.0) // clamped
  }
  out
}
