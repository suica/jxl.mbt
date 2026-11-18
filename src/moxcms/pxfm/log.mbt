// Ported from pxfm 0.1.30 (https://github.com/awxkee/pxfm),
// Copyright (c) Radzivon Bartoshyk. All rights reserved.
// BSD-3-Clause OR Apache-2.0 (see upstream LICENSE.md / LICENSE-APACHE.md).
//
// Port of `logs/log.rs` (`f_log`, `log_dyadic`, `log_accurate`).

///|
/// `u = r * m - 1` (exact) via the not-fma branch:
/// `f_fmla(r, m - c, LOG_CD[index])` with `c = m & 0x3FFF_E000_0000_0000`.
fn log_reduce_u(x_m : UInt64, index : Int32, r : Double) -> Double {
  let m = fb(x_m)
  let c_m = x_m & 0x3FFF_E000_0000_0000UL
  let c = fb(c_m)
  f_fmla(r, m - c, fb(log_cd[index]))
}

///|
let log_accurate_big_coeffs : FixedArray[DyadicFloat128] = [
  dyadic_const(true, -129, 0x8000_0000_0006_a710UL, 0xb59c_58e5_554d_581cUL),
  dyadic_const(false, -129, 0xaaaa_aaaa_aaaa_aabdUL, 0xde05_c7c9_4ae9_cbaeUL),
  dyadic_const(true, -128, 0x8000_0000_0000_0000UL, 0x0000_0000_0000_0000UL),
]

///|
let log_accurate_log_2 : DyadicFloat128 = dyadic_const(
  false, -128, 0xb17217f7_d1cf79abUL, 0xc9e3b398_03f2f6afUL,
)

///|
/// Assumes that NaN and infinities, negatives were filtered out.
fn log_dyadic(x : Double) -> DyadicFloat128 {
  let mut x_u = tb(x)
  let mut x_e = -1023
  if x_u == tb(1.0) {
    // log2(1.0) = +0.0
    return dyadic_const(false, 0, 0UL, 0UL)
  }
  if x_u < tb(min_normal_f64()) || x_u > 0x7fefffffffffffffUL {
    // Normalize denormal inputs.
    x_u = tb(x * fb(0x4330000000000000UL))
    x_e -= 52
  }
  // Range reduction for log2(x_m):
  // For each x_m, we would like to find r such that:
  //   -2^-8 <= r * x_m - 1 < 2^-7
  let shifted = (x_u >> 45).to_int()
  let index = shifted & 0x7F
  let r = fb(log_range_reduction_table[index])
  // Add unbiased exponent. Add an extra 1 if the 8 leading fractional bits are
  // all 1's.
  x_e = x_e + ((x_u + (1UL << 45)) >> 52).to_int()
  // Set m = 1.mantissa.
  let x_m = (x_u & 0x000F_FFFF_FFFF_FFFFUL) | 0x3FF0_0000_0000_0000UL
  let u = log_reduce_u(x_m, index, r)
  log_accurate(x_e, index, u)
}

///|
/// Reuse the output of the fast pass range reduction.
/// -2^-8 <= m_x < 2^-7
fn log_accurate(e_x : Int32, index : Int32, m_x : Double) -> DyadicFloat128 {
  let e_x_f128 = DyadicFloat128::new_from_f64(e_x.to_double())
  let mut sum = log_accurate_log_2 * e_x_f128
  sum = sum + log_step_1[index]
  let (v_f128, sum1) = log_range_reduction(m_x, sum)
  sum = sum1 + v_f128
  // Polynomial approximation
  let mut p = v_f128 * log_accurate_big_coeffs[0]
  p = v_f128 * (p + log_accurate_big_coeffs[1])
  p = v_f128 * (p + log_accurate_big_coeffs[2])
  p = v_f128 * p
  sum + p
}

///|
/// Natural logarithm.
///
/// Max found ULP 0.5.
pub fn f_log(x : Double) -> Double {
  let mut x_u = tb(x)
  let mut x_e = -1023
  if x_u == tb(1.0) {
    // log2(1.0) = +0.0
    return 0.0
  }
  if x_u < tb(min_normal_f64()) || x_u > 0x7fefffffffffffffUL {
    if x == 0.0 {
      return -inf_f64
    }
    if x < 0.0 || is_nan(x) {
      return nan_f64
    }
    if x == inf_f64 {
      return x + x
    }
    // Normalize denormal inputs.
    x_u = tb(x * fb(0x4330000000000000UL))
    x_e -= 52
  }
  let shifted = (x_u >> 45).to_int()
  let index = shifted & 0x7F
  let r = fb(log_range_reduction_table[index])
  x_e = x_e + ((x_u + (1UL << 45)) >> 52).to_int()
  let e_x = x_e.to_double()
  let log_2_hi = fb(0x3fe62e42fefa3800UL)
  let log_2_lo = fb(0x3d2ef35793c76730UL)
  // hi is exact
  let hi = f_fmla(e_x, log_2_hi, fb(log_r_dd[2 * index + 1]))
  // lo errors ~ e_x * LSB(LOG_2_LO) + LSB(LOG_R[index].lo) + rounding err
  //           <= 2 * (e_x * LSB(LOG_2_LO) + LSB(LOG_R[index].lo))
  let lo = f_fmla(e_x, log_2_lo, fb(log_r_dd[2 * index]))
  // Set m = 1.mantissa.
  let x_m = (x_u & 0x000F_FFFF_FFFF_FFFFUL) | 0x3FF0_0000_0000_0000UL
  let u = log_reduce_u(x_m, index, r)
  let r1 = DoubleDouble::from_exact_add(hi, u)
  let u_sq = u * u
  // Degree-7 minimax polynomial
  let p0 = f_fmla(u, fb(log_coeffs[1]), fb(log_coeffs[0]))
  let p1 = f_fmla(u, fb(log_coeffs[3]), fb(log_coeffs[2]))
  let p2 = f_fmla(u, fb(log_coeffs[5]), fb(log_coeffs[4]))
  let p = f_polyeval4(u_sq, lo + r1.lo, p0, p1, p2)
  let hi_err = fb(0x3aa0000000000000UL)
  // Extra errors from P is from using x^2 to reduce evaluation latency.
  let p_err = fb(0x3cd0000000000000UL)
  let err = f_fmla(u_sq, p_err, hi_err)
  // Lower bound from the result
  let left = r1.hi + (p - err)
  // Upper bound from the result
  let right = r1.hi + (p + err)
  // Ziv's test if fast pass is accurate enough.
  if left == right {
    return left
  }
  log_accurate_slow(x)
}

///|
fn log_accurate_slow(x : Double) -> Double {
  let r = log_dd(x)
  let err = f_fmla(
    r.hi,
    fb(0x3b50000000000000UL), // 2^-74
    fb(0x3990000000000000UL), // 2^-102
  )
  let ub = r.hi + (r.lo + err)
  let lb = r.hi + (r.lo - err)
  if ub == lb {
    return r.to_f64()
  }
  log_accurate_slow_td(x)
}

///|
fn log_accurate_slow_td(x : Double) -> Double {
  log_td(x).to_f64()
}
