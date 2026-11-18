// Ported from pxfm 0.1.30 (https://github.com/awxkee/pxfm),
// Copyright (c) Radzivon Bartoshyk. All rights reserved.
// BSD-3-Clause OR Apache-2.0 (see upstream LICENSE.md / LICENSE-APACHE.md).
//
// Port of `logs/log_dd.rs` (`log_dd`).

///|
/// The common range reduction of `log_dd`, `log_td`, `log10_dd`, `log10_td`
/// and `pow_log_1`: returns `(be, t, i - 181)` with `|x| = 2^be * t`,
/// `1/sqrt(2) < t < sqrt(2)` and `i/2^8 <= t < (i+1)/2^8` (before halving).
fn log_reduce_inverse(x : Double) -> (Int64, Double, Int32) {
  let x_u = tb(x)
  let mut m = x_u & 0xfffffffffffffUL
  let mut e = ((x_u >> 52) & 0x7ffUL).reinterpret_as_int64()
  let t_bits = if e != 0L {
    let t = m | (0x3ffUL << 52)
    m = m + (1UL << 52)
    e -= 0x3ffL
    t
  } else {
    // x is a subnormal double
    let k = m.clz() - 11
    e = -0x3feL - k.to_int64()
    m = m << k
    m | (0x3ffUL << 52)
  }
  // now |x| = 2^_e*_t = 2^(_e-52)*m with 1 <= _t < 2,
  // and 2^52 <= _m < 2^53
  let mut t = fb(t_bits)
  // If m > sqrt(2) we divide it by 2 so ensure 1/sqrt(2) < t < sqrt(2)
  let c = m >= 0x16a09e667f3bcdUL
  if c {
    e += 1L
  }
  let i = if c { m >> 45 } else { m >> 44 }
  if c {
    t = t * 0.5
  }
  (e, t, (i - 181UL).to_int())
}

///|
fn log_poly(z : Double) -> DoubleDouble {
  let p = log_dd_poly_p
  let x2 = DoubleDouble::from_exact_mult(z, z)
  let mut t = DoubleDouble::quick_mul_f64_add(
    DoubleDouble::from_table(p, 8),
    z,
    DoubleDouble::from_table(p, 7),
  )
  t = DoubleDouble::quick_mul_f64_add(t, z, DoubleDouble::from_table(p, 6))
  t = DoubleDouble::quick_mul_f64_add(t, z, DoubleDouble::from_table(p, 5))
  t = DoubleDouble::quick_mul_f64_add(t, z, DoubleDouble::from_table(p, 4))
  t = DoubleDouble::quick_mul_f64_add(t, z, DoubleDouble::from_table(p, 3))
  t = DoubleDouble::quick_mul_f64_add(t, z, DoubleDouble::from_table(p, 2))
  t = DoubleDouble::quick_mul_f64_add(t, z, DoubleDouble::from_table(p, 1))
  t = DoubleDouble::quick_mul_f64_add(t, z, DoubleDouble::from_table(p, 0))
  t = DoubleDouble::quick_mult(t, x2)
  t = DoubleDouble::quick_mult_f64(t, z)
  DoubleDouble::mul_f64_add(x2, -0.5, t)
}

///|
/// `log_dd`.
fn log_dd(x : Double) -> DoubleDouble {
  let (be, t, idx) = log_reduce_inverse(x)
  let r = fb(pow_inverse[idx])
  let log_r = DoubleDouble::from_table(log_neg_dd, idx)
  let z = fma_f64(r, t, -1.0)
  let log2_dd = DoubleDouble::new(
    fb(0x3c7abc9e3b39803fUL),
    fb(0x3fe62e42fefa39efUL),
  )
  let tt = DoubleDouble::mul_f64_add(log2_dd, be.to_double(), log_r)
  let v = DoubleDouble::full_add_f64(tt, z)
  let p = log_poly(z)
  DoubleDouble::f64_add(v.hi, DoubleDouble::new(v.lo + p.lo, p.hi))
}
