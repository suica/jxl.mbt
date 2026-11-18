// Port of jxl-color `fastmath/powf.rs` (generic implementation).

///|
let pow2f_numer_coeffs : FixedArray[Float] = [
  1.01749063e1, 4.88687798e1, 9.85506591e1,
]

///|
let pow2f_denom_coeffs : FixedArray[Float] = [
  2.10242958e-1, -2.22328856e-2, -1.94414990e1, 9.85506633e1,
]

///|
fn fast_pow2f_generic(x : Float) -> Float {
  let x_floor = x.floor()
  let exp = Float::reinterpret_from_uint(
    (x_floor.to_int() + 127).reinterpret_as_uint() << 23,
  )
  let frac = x - x_floor
  let num = frac + pow2f_numer_coeffs[0]
  let num = num * frac + pow2f_numer_coeffs[1]
  let num = num * frac + pow2f_numer_coeffs[2]
  let num = num * exp
  let den = pow2f_denom_coeffs[0] * frac + pow2f_denom_coeffs[1]
  let den = den * frac + pow2f_denom_coeffs[2]
  let den = den * frac + pow2f_denom_coeffs[3]
  num / den
}

///|
let log2f_p : FixedArray[Float] = [
  -1.8503833400518310e-6, 1.4287160470083755, 7.4245873327820566e-1,
]

///|
let log2f_q : FixedArray[Float] = [
  9.9032814277590719e-1, 1.0096718572241148, 1.7409343003366853e-1,
]

///|
fn fast_log2f_generic(x : Float) -> Float {
  let x_bits = x.reinterpret_as_int()
  let exp_bits = x_bits - 0x3f2aaaab
  let exp_shifted = exp_bits >> 23
  let mantissa = Float::reinterpret_from_int(x_bits - (exp_shifted << 23))
  let exp_val = Float::from_int(exp_shifted)
  let x = mantissa - 1.0
  rational_poly_eval_generic(x, log2f_p, log2f_q) + exp_val
}

///|
/// Approximates `base.powf(exp)` (libjxl `FastPowf`).
pub fn fast_powf_generic(base : Float, exp : Float) -> Float {
  fast_pow2f_generic(fast_log2f_generic(base) * exp)
}

///|
/// One lane of `fast_pow2f_x86_64_fma` / `fast_pow2f_x86_64_avx2`.
fn fast_pow2f_fma(x : Float) -> Float {
  let x_floor = x.floor()
  let exp = Float::reinterpret_from_uint(
    (cvtps_epi32_integral(x_floor) + 127).reinterpret_as_uint() << 23,
  )
  let frac = x - x_floor
  let num = pow2f_numer_coeffs[0] + frac
  let num = mul_add_f32(frac, num, pow2f_numer_coeffs[1])
  let num = mul_add_f32(frac, num, pow2f_numer_coeffs[2])
  let num = exp * num
  let den = mul_add_f32(frac, pow2f_denom_coeffs[0], pow2f_denom_coeffs[1])
  let den = mul_add_f32(frac, den, pow2f_denom_coeffs[2])
  let den = mul_add_f32(frac, den, pow2f_denom_coeffs[3])
  num / den
}

///|
/// One lane of `fast_log2f_x86_64_fma` / `fast_log2f_x86_64_avx2`.
fn fast_log2f_fma(x : Float) -> Float {
  let x_bits = x.reinterpret_as_int()
  let exp_bits = x_bits - 0x3f2aaaab
  let exp_shifted = exp_bits >> 23
  let mantissa = Float::reinterpret_from_int(x_bits - (exp_shifted << 23))
  let exp_val = Float::from_int(exp_shifted)
  let x = mantissa - 1.0
  rational_poly_eval_fma(x, log2f_p, log2f_q) + exp_val
}

///|
/// One lane of `fast_powf_x86_64_fma` / `fast_powf_x86_64_avx2`.
fn fast_powf_fma(base : Float, exp : Float) -> Float {
  fast_pow2f_fma(fast_log2f_fma(base) * exp)
}
