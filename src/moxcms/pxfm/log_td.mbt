// Ported from pxfm 0.1.30 (https://github.com/awxkee/pxfm),
// Copyright (c) Radzivon Bartoshyk. All rights reserved.
// BSD-3-Clause OR Apache-2.0 (see upstream LICENSE.md / LICENSE-APACHE.md).
//
// Port of `logs/log_td.rs` (`log_td`).

///|
fn log_td_poly(z : Double) -> TripleDouble {
  let p = log_td_poly_p
  let x2 = DoubleDouble::from_exact_mult(z, z)
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
  t = TripleDouble::quick_mult_dd(t, x2)
  t = TripleDouble::quick_mult_f64(t, z)
  TripleDouble::f64_mul_dd_add(-0.5, x2, t)
}

///|
/// `log_td`.
fn log_td(x : Double) -> TripleDouble {
  let (be, t, idx) = log_reduce_inverse(x)
  let r = fb(pow_inverse[idx])
  let log_r = TripleDouble::from_table(log_neg_td, idx)
  let z = fma_f64(r, t, -1.0)
  let log2_dd = TripleDouble::new(
    fb(0x3907b57a079a1934UL),
    fb(0x3c7abc9e3b39803fUL),
    fb(0x3fe62e42fefa39efUL),
  )
  let tt = TripleDouble::f64_mul_add(be.to_double(), log2_dd, log_r)
  let v = TripleDouble::add_f64(z, tt)
  let p = log_td_poly(z)
  TripleDouble::add_f64(
    v.hi,
    TripleDouble::new(v.lo + p.lo, v.mid + p.mid, p.hi),
  )
}
