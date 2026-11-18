// Ported from pxfm 0.1.30 (https://github.com/awxkee/pxfm),
// Copyright (c) Radzivon Bartoshyk. All rights reserved.
// BSD-3-Clause OR Apache-2.0 (see upstream LICENSE.md / LICENSE-APACHE.md).
//
// Port of the `polyeval.rs` evaluators reached by the ported functions.
// `f_*` use `f_fmla` (unfused without `target_feature = "fma"`), `d_*` and
// `*_fma` use `f64::mul_add` (`fma_f64`).

///|
/// `f_polyeval3::<f64>`.
fn f_polyeval3(x : Double, a0 : Double, a1 : Double, a2 : Double) -> Double {
  f_fmla(x, f_fmla(x, a2, a1), a0)
}

///|
/// `d_polyeval3`.
fn d_polyeval3(x : Double, a0 : Double, a1 : Double, a2 : Double) -> Double {
  fma_f64(x, fma_f64(x, a2, a1), a0)
}

///|
/// `f_polyeval4::<f64>`.
fn f_polyeval4(
  x : Double,
  a0 : Double,
  a1 : Double,
  a2 : Double,
  a3 : Double,
) -> Double {
  let t2 = f_fmla(x, a3, a2)
  let t5 = f_fmla(x, t2, a1)
  f_fmla(x, t5, a0)
}

///|
/// `dd_quick_polyeval6` (`fma = false`) / `dd_quick_polyeval6_fma`.
fn dd_quick_polyeval6(
  x : DoubleDouble,
  a0 : DoubleDouble,
  a1 : DoubleDouble,
  a2 : DoubleDouble,
  a3 : DoubleDouble,
  a4 : DoubleDouble,
  a5 : DoubleDouble,
  fma : Bool,
) -> DoubleDouble {
  if fma {
    let x2 = DoubleDouble::quick_mult_fma(x, x)
    let u0 = DoubleDouble::quick_mul_add_fma(x, a5, a4)
    let u1 = DoubleDouble::quick_mul_add_fma(x, a3, a2)
    let u2 = DoubleDouble::quick_mul_add_fma(x, a1, a0)
    let v0 = DoubleDouble::quick_mul_add_fma(x2, u0, u1)
    DoubleDouble::quick_mul_add_fma(x2, v0, u2)
  } else {
    let x2 = DoubleDouble::quick_mult(x, x)
    let u0 = DoubleDouble::quick_mul_add(x, a5, a4)
    let u1 = DoubleDouble::quick_mul_add(x, a3, a2)
    let u2 = DoubleDouble::quick_mul_add(x, a1, a0)
    let v0 = DoubleDouble::quick_mul_add(x2, u0, u1)
    DoubleDouble::quick_mul_add(x2, v0, u2)
  }
}

///|
/// `dd_quick_polyeval10` (`fma = false`) / `dd_quick_polyeval10_fma`.
/// `a` holds the ten coefficients.
fn dd_quick_polyeval10(
  x : DoubleDouble,
  a : FixedArray[DoubleDouble],
  fma : Bool,
) -> DoubleDouble {
  if fma {
    let x2 = DoubleDouble::quick_mult_fma(x, x)
    let x4 = DoubleDouble::quick_mult_fma(x2, x2)
    let x8 = DoubleDouble::quick_mult_fma(x4, x4)
    let p0 = DoubleDouble::quick_mul_add_fma(x, a[1], a[0])
    let p1 = DoubleDouble::quick_mul_add_fma(x, a[3], a[2])
    let p2 = DoubleDouble::quick_mul_add_fma(x, a[5], a[4])
    let p3 = DoubleDouble::quick_mul_add_fma(x, a[7], a[6])
    let p4 = DoubleDouble::quick_mul_add_fma(x, a[9], a[8])
    let q0 = DoubleDouble::quick_mul_add_fma(x2, p1, p0)
    let q1 = DoubleDouble::quick_mul_add_fma(x2, p3, p2)
    let r0 = DoubleDouble::quick_mul_add_fma(x4, q1, q0)
    DoubleDouble::quick_mul_add_fma(x8, p4, r0)
  } else {
    let x2 = DoubleDouble::quick_mult(x, x)
    let x4 = DoubleDouble::quick_mult(x2, x2)
    let x8 = DoubleDouble::quick_mult(x4, x4)
    let p0 = DoubleDouble::quick_mul_add(x, a[1], a[0])
    let p1 = DoubleDouble::quick_mul_add(x, a[3], a[2])
    let p2 = DoubleDouble::quick_mul_add(x, a[5], a[4])
    let p3 = DoubleDouble::quick_mul_add(x, a[7], a[6])
    let p4 = DoubleDouble::quick_mul_add(x, a[9], a[8])
    let q0 = DoubleDouble::quick_mul_add(x2, p1, p0)
    let q1 = DoubleDouble::quick_mul_add(x2, p3, p2)
    let r0 = DoubleDouble::quick_mul_add(x4, q1, q0)
    DoubleDouble::quick_mul_add(x8, p4, r0)
  }
}
