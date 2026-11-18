// Ported from pxfm 0.1.30 (https://github.com/awxkee/pxfm),
// Copyright (c) Radzivon Bartoshyk. All rights reserved.
// BSD-3-Clause OR Apache-2.0 (see upstream LICENSE.md / LICENSE-APACHE.md).
//
// Port of `logs/log10.rs` (`f_log10`), `logs/log10dd.rs` (`log10_dd`) and
// `logs/log10td.rs` (`log10_td`).

///|
/// Logarithm of base 10.
///
/// Max found ULP 0.5.
pub fn f_log10(x : Double) -> Double {
  let mut x_u = tb(x)
  let mut x_e = -1023L
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
    x_e -= 52L
  }
  let shifted = (x_u >> 45).reinterpret_as_int64()
  let index = (shifted & 0x7FL).to_int()
  let r = fb(log_range_reduction_table[index])
  x_e = x_e + ((x_u + (1UL << 45)) >> 52).reinterpret_as_int64()
  let e_x = x_e.to_double()
  let log_2_hi = fb(0x3fe62e42fefa3800UL)
  let log_2_lo = fb(0x3d2ef35793c76730UL)
  // hi is exact
  let hi = f_fmla(e_x, log_2_hi, fb(log_r_dd[2 * index + 1]))
  let lo = f_fmla(e_x, log_2_lo, fb(log_r_dd[2 * index]))
  // Set m = 1.mantissa.
  let x_m = (x_u & 0x000F_FFFF_FFFF_FFFFUL) | 0x3FF0_0000_0000_0000UL
  let u = log_reduce_u(x_m, index, r)
  let u_sq = u * u
  // Degree-7 minimax polynomial
  let p0 = f_fmla(u, fb(log_coeffs[1]), fb(log_coeffs[0]))
  let p1 = f_fmla(u, fb(log_coeffs[3]), fb(log_coeffs[2]))
  let p2 = f_fmla(u, fb(log_coeffs[5]), fb(log_coeffs[4]))
  let p = f_polyeval4(u_sq, lo, p0, p1, p2)
  // Exact sum:
  //   r1.hi + r1.lo = e_x * log(2)_hi - log(r)_hi + u
  let r1a = DoubleDouble::from_exact_add(hi, u)
  let r1 = DoubleDouble::new(r1a.lo + p, r1a.hi)
  // Quick double-double multiplication:
  //   r2.hi + r2.lo ~ r1 * log10(e),
  let log10_e = DoubleDouble::new(
    fb(0x3c695355baaafad3UL),
    fb(0x3fdbcb7b1526e50eUL),
  )
  let r2 = DoubleDouble::quick_mult(r1, log10_e)
  let hi_err = fb(0x3aa0000000000000UL)
  // Extra errors from P is from using x^2 to reduce evaluation latency.
  let p_err = fb(0x3cc0000000000000UL)
  let err = f_fmla(u_sq, p_err, hi_err)
  // Lower bound from the result
  let left = r2.hi + (r2.lo - err)
  // Upper bound from the result
  let right = r2.hi + (r2.lo + err)
  // Ziv's test if fast pass is accurate enough.
  if left == right {
    return left
  }
  log10_dd_accurate(x)
}

///|
fn log10_dd_accurate(x : Double) -> Double {
  let r = log10_dd(x)
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
  log10_dd_accurate_slow(x)
}

///|
fn log10_dd_accurate_slow(x : Double) -> Double {
  log10_td(x).to_f64()
}

///|
fn log10_dd_poly(z : Double) -> DoubleDouble {
  let p = log10_dd_poly_p
  let mut t = DoubleDouble::quick_mul_f64_add(
    DoubleDouble::from_table(p, 9),
    z,
    DoubleDouble::from_table(p, 8),
  )
  t = DoubleDouble::quick_mul_f64_add(t, z, DoubleDouble::from_table(p, 7))
  t = DoubleDouble::quick_mul_f64_add(t, z, DoubleDouble::from_table(p, 6))
  t = DoubleDouble::quick_mul_f64_add(t, z, DoubleDouble::from_table(p, 5))
  t = DoubleDouble::quick_mul_f64_add(t, z, DoubleDouble::from_table(p, 4))
  t = DoubleDouble::quick_mul_f64_add(t, z, DoubleDouble::from_table(p, 3))
  t = DoubleDouble::quick_mul_f64_add(t, z, DoubleDouble::from_table(p, 2))
  t = DoubleDouble::quick_mul_f64_add(t, z, DoubleDouble::from_table(p, 1))
  t = DoubleDouble::quick_mul_f64_add(t, z, DoubleDouble::from_table(p, 0))
  DoubleDouble::quick_mult_f64(t, z)
}

///|
/// `log10_dd`.
fn log10_dd(x : Double) -> DoubleDouble {
  let (be, t, idx) = log_reduce_inverse(x)
  let r = fb(pow_inverse[idx])
  let log10_r = DoubleDouble::from_table(log10_neg_dd, idx)
  let z = fma_f64(r, t, -1.0)
  let log10_2_dd = DoubleDouble::new(
    fb(0xbc49dc1da994fd21UL),
    fb(0x3fd34413509f79ffUL),
  )
  let v = DoubleDouble::mul_f64_add(log10_2_dd, be.to_double(), log10_r)
  let p = log10_dd_poly(z)
  DoubleDouble::f64_add(v.hi, DoubleDouble::new(v.lo + p.lo, p.hi))
}

///|
fn log10_td_poly(z : Double) -> TripleDouble {
  let p = log10_td_poly_p
  let mut t = TripleDouble::f64_mul_add(
    z,
    TripleDouble::from_table(p, 9),
    TripleDouble::from_table(p, 8),
  )
  t = TripleDouble::f64_mul_add(z, t, TripleDouble::from_table(p, 7))
  t = TripleDouble::f64_mul_add(z, t, TripleDouble::from_table(p, 6))
  t = TripleDouble::f64_mul_add(z, t, TripleDouble::from_table(p, 5))
  t = TripleDouble::f64_mul_add(z, t, TripleDouble::from_table(p, 4))
  t = TripleDouble::f64_mul_add(z, t, TripleDouble::from_table(p, 3))
  t = TripleDouble::f64_mul_add(z, t, TripleDouble::from_table(p, 2))
  t = TripleDouble::f64_mul_add(z, t, TripleDouble::from_table(p, 1))
  t = TripleDouble::f64_mul_add(z, t, TripleDouble::from_table(p, 0))
  TripleDouble::quick_mult_f64(t, z)
}

///|
/// `log10_td`.
fn log10_td(x : Double) -> TripleDouble {
  let (be, t, idx) = log_reduce_inverse(x)
  let r = fb(pow_inverse[idx])
  let log10_r = TripleDouble::from_table(log10_neg_td, idx)
  let z = fma_f64(r, t, -1.0)
  let log10_2_dd = DoubleDouble::new(
    fb(0xbc49dc1da994fd21UL),
    fb(0x3fd34413509f79ffUL),
  )
  let v = TripleDouble::f64_mul_dd_add(be.to_double(), log10_2_dd, log10_r)
  let p = log10_td_poly(z)
  TripleDouble::add_f64(
    v.hi,
    TripleDouble::new(v.lo + p.lo, v.mid + p.mid, p.hi),
  )
}
