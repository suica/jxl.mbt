// Ported from pxfm 0.1.30 (https://github.com/awxkee/pxfm),
// Copyright (c) Radzivon Bartoshyk. All rights reserved.
// BSD-3-Clause OR Apache-2.0 (see upstream LICENSE.md / LICENSE-APACHE.md).
//
// Port of `double_double.rs` (the methods reached by the ported functions).
// Every `cfg(target_feature = "fma")` takes the not-fma branch; the `*_fma`
// methods (used by the runtime-dispatched FMA backends) call `fma_f64`.

///|
/// Double-double number `hi + lo`.
priv struct DoubleDouble {
  lo : Double
  hi : Double
}

///|
fn DoubleDouble::new(lo : Double, hi : Double) -> DoubleDouble {
  { lo, hi, }
}

///|
/// `from_bit_pair(TABLE[i])` for a flattened `[(u64, u64)]` table.
fn DoubleDouble::from_table(t : FixedArray[UInt64], i : Int32) -> DoubleDouble {
  { lo: fb(t[2 * i]), hi: fb(t[2 * i + 1]), }
}

///|
/// Veltkamp split (non FMA helper).
fn DoubleDouble::split(a : Double) -> DoubleDouble {
  let c = 134217728.0 + 1.0
  let t1 = c * a
  let t2 = a - t1
  let r_hi = t1 + t2
  let r_lo = a - r_hi
  DoubleDouble::new(r_lo, r_hi)
}

///|
fn DoubleDouble::from_exact_mult_impl_non_fma(
  asz : DoubleDouble,
  a : Double,
  b : Double,
) -> DoubleDouble {
  let bs = DoubleDouble::split(b)
  let r_hi = a * b
  let t1 = asz.hi * bs.hi - r_hi
  let t2 = asz.hi * bs.lo + t1
  let t3 = asz.lo * bs.hi + t2
  let r_lo = asz.lo * bs.lo + t3
  DoubleDouble::new(r_lo, r_hi)
}

///|
/// Fast2Sum, valid only for |a| > |b|.
fn DoubleDouble::from_exact_add(a : Double, b : Double) -> DoubleDouble {
  let r_hi = a + b
  let t = r_hi - a
  let r_lo = b - t
  DoubleDouble::new(r_lo, r_hi)
}

///|
/// TwoSum.
fn DoubleDouble::from_full_exact_add(a : Double, b : Double) -> DoubleDouble {
  let r_hi = a + b
  let t1 = r_hi - a
  let t2 = r_hi - t1
  let t3 = b - t1
  let t4 = a - t2
  let r_lo = t3 + t4
  DoubleDouble::new(r_lo, r_hi)
}

///|
fn DoubleDouble::dd_f64_mul_add(a : Double, b : Double, c : Double) -> Double {
  let ddx2 = DoubleDouble::from_exact_mult(a, b)
  let zv = DoubleDouble::full_add_f64(ddx2, c)
  zv.to_f64()
}

///|
fn DoubleDouble::add(a : DoubleDouble, b : DoubleDouble) -> DoubleDouble {
  let s = a.hi + b.hi
  let d = s - a.hi
  let l = b.hi - d + (a.hi + (d - s)) + (a.lo + b.lo)
  DoubleDouble::new(l, s)
}

///|
/// Accurate reciprocal `1 / self` (not-fma branch).
fn DoubleDouble::recip(self : DoubleDouble) -> DoubleDouble {
  let y = 1.0 / self.hi
  let { hi: p1, lo: err1, } = DoubleDouble::from_exact_mult(self.hi, y)
  let e1 = 1.0 - p1 - err1
  let { hi: p2, lo: err2, } = DoubleDouble::from_exact_mult(self.lo, y)
  let e2 = e1 - p2 - err2
  let e = y * e2
  DoubleDouble::new(e, y)
}

///|
/// Exact product (not-fma branch: Dekker).
fn DoubleDouble::from_exact_mult(a : Double, b : Double) -> DoubleDouble {
  let splat = DoubleDouble::split(a)
  DoubleDouble::from_exact_mult_impl_non_fma(splat, a, b)
}

///|
/// `a * b + c`, `b` an `f64`.
fn DoubleDouble::mul_f64_add(
  a : DoubleDouble,
  b : Double,
  c : DoubleDouble,
) -> DoubleDouble {
  let { hi: h, lo: r, } = DoubleDouble::quick_mult_f64(a, b)
  let { hi: p, lo: q, } = DoubleDouble::full_add_f64(c, h)
  DoubleDouble::new(r + q, p)
}

///|
/// `a * b + c`, valid for |c.hi| > |a.hi * b|.
fn DoubleDouble::quick_mul_f64_add(
  a : DoubleDouble,
  b : Double,
  c : DoubleDouble,
) -> DoubleDouble {
  let { hi: h, lo: r, } = DoubleDouble::quick_mult_f64(a, b)
  let { hi: p, lo: q, } = DoubleDouble::add_f64(c, h)
  DoubleDouble::new(r + q, p)
}

///|
/// `a * b + c`, valid for |c.hi| > |a.hi * b.hi|.
fn DoubleDouble::quick_mul_add(
  a : DoubleDouble,
  b : DoubleDouble,
  c : DoubleDouble,
) -> DoubleDouble {
  let { hi: h, lo: r, } = DoubleDouble::quick_mult(a, b)
  let { hi: p, lo: q, } = DoubleDouble::add_f64(c, h)
  DoubleDouble::new(r + q, p)
}

///|
/// `a * b + c` with `c` an `f64`.
fn DoubleDouble::quick_mul_add_f64(
  a : DoubleDouble,
  b : DoubleDouble,
  c : Double,
) -> DoubleDouble {
  let { hi: h, lo: r, } = DoubleDouble::quick_mult(a, b)
  let { hi: p, lo: q, } = DoubleDouble::from_exact_add(c, h)
  DoubleDouble::new(r + q, p)
}

///|
/// Not-fma branch.
fn DoubleDouble::quick_mult(a : DoubleDouble, b : DoubleDouble) -> DoubleDouble {
  let { hi: ch, lo: cl1, } = DoubleDouble::from_exact_mult(a.hi, b.hi)
  let tl1 = a.hi * b.lo
  let tl2 = a.lo * b.hi
  let cl2 = tl1 + tl2
  let cl3 = cl1 + cl2
  DoubleDouble::new(cl3, ch)
}

///|
/// Not-fma branch.
fn DoubleDouble::mult(a : DoubleDouble, b : DoubleDouble) -> DoubleDouble {
  let { hi: ch, lo: cl1, } = DoubleDouble::from_exact_mult(a.hi, b.hi)
  let tl1 = a.hi * b.lo
  let tl2 = a.lo * b.hi
  let cl2 = tl1 + tl2
  let cl3 = cl1 + cl2
  DoubleDouble::from_exact_add(ch, cl3)
}

///|
/// Not-fma branch.
fn DoubleDouble::quick_mult_f64(a : DoubleDouble, b : Double) -> DoubleDouble {
  let { hi: ch, lo: cl1, } = DoubleDouble::from_exact_mult(a.hi, b)
  let cl2 = a.lo * b
  let cl3 = cl1 + cl2
  DoubleDouble::new(cl3, ch)
}

///|
/// Valid only |a.hi| > |b|.
fn DoubleDouble::add_f64(a : DoubleDouble, b : Double) -> DoubleDouble {
  let t = DoubleDouble::from_exact_add(a.hi, b)
  let l = a.lo + t.lo
  { lo: l, hi: t.hi, }
}

///|
fn DoubleDouble::full_add_f64(a : DoubleDouble, b : Double) -> DoubleDouble {
  let t = DoubleDouble::from_full_exact_add(a.hi, b)
  let l = a.lo + t.lo
  { lo: l, hi: t.hi, }
}

///|
/// Valid only |b| > |a.hi|.
fn DoubleDouble::f64_add(b : Double, a : DoubleDouble) -> DoubleDouble {
  let t = DoubleDouble::from_exact_add(b, a.hi)
  let l = a.lo + t.lo
  { lo: l, hi: t.hi, }
}

///|
fn DoubleDouble::to_f64(self : DoubleDouble) -> Double {
  self.lo + self.hi
}

///|
/// `from_exact_mult_fma`.
fn DoubleDouble::from_exact_mult_fma(a : Double, b : Double) -> DoubleDouble {
  let r_hi = a * b
  let r_lo = fma_f64(a, b, -r_hi)
  DoubleDouble::new(r_lo, r_hi)
}

///|
/// `quick_mult_fma`.
fn DoubleDouble::quick_mult_fma(
  a : DoubleDouble,
  b : DoubleDouble,
) -> DoubleDouble {
  let r = DoubleDouble::from_exact_mult_fma(a.hi, b.hi)
  let t1 = fma_f64(a.hi, b.lo, r.lo)
  let t2 = fma_f64(a.lo, b.hi, t1)
  DoubleDouble::new(t2, r.hi)
}

///|
/// `quick_mult_f64_fma`.
fn DoubleDouble::quick_mult_f64_fma(
  a : DoubleDouble,
  b : Double,
) -> DoubleDouble {
  let h = b * a.hi
  let l = fma_f64(b, a.lo, fma_f64(b, a.hi, -h))
  DoubleDouble::new(l, h)
}

///|
/// `quick_mul_add_fma`.
fn DoubleDouble::quick_mul_add_fma(
  a : DoubleDouble,
  b : DoubleDouble,
  c : DoubleDouble,
) -> DoubleDouble {
  let { hi: h, lo: r, } = DoubleDouble::quick_mult_fma(a, b)
  let { hi: p, lo: q, } = DoubleDouble::add_f64(c, h)
  DoubleDouble::new(r + q, p)
}
