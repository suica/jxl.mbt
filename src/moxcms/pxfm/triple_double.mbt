// Ported from pxfm 0.1.30 (https://github.com/awxkee/pxfm),
// Copyright (c) Radzivon Bartoshyk. All rights reserved.
// BSD-3-Clause OR Apache-2.0 (see upstream LICENSE.md / LICENSE-APACHE.md).
//
// Port of `triple_double.rs` (the methods reached by the ported
// functions; `f_fmla` is the unfused `a * b + c`).

///|
/// Triple-double number `hi + mid + lo`.
priv struct TripleDouble {
  hi : Double
  mid : Double
  lo : Double
}

///|
fn TripleDouble::new(lo : Double, mid : Double, hi : Double) -> TripleDouble {
  { hi, mid, lo, }
}

///|
/// `from_bit_pair(TABLE[i])` for a flattened `[(u64, u64, u64)]` table:
/// `.0` is `lo`, `.1` is `mid`, `.2` is `hi`.
fn TripleDouble::from_table(t : FixedArray[UInt64], i : Int32) -> TripleDouble {
  { hi: fb(t[3 * i + 2]), mid: fb(t[3 * i + 1]), lo: fb(t[3 * i]), }
}

///|
fn TripleDouble::neg(self : TripleDouble) -> TripleDouble {
  TripleDouble::new(-self.lo, -self.mid, -self.hi)
}

///|
fn add12(a : Double, b : Double) -> DoubleDouble {
  DoubleDouble::from_full_exact_add(a, b)
}

///|
fn mul12(a : Double, b : Double) -> DoubleDouble {
  DoubleDouble::from_exact_mult(a, b)
}

///|
fn add22(a : DoubleDouble, b : DoubleDouble) -> DoubleDouble {
  let { hi: v1, lo: v2, } = DoubleDouble::from_full_exact_add(a.hi, b.hi)
  let v3 = a.lo + b.lo
  let v4 = v2 + v3
  DoubleDouble::from_full_exact_add(v1, v4)
}

///|
fn TripleDouble::f64_mul_dd_add(
  p0 : Double,
  p1 : DoubleDouble,
  p2 : TripleDouble,
) -> TripleDouble {
  let q0 = TripleDouble::from_quick_mult_dd_f64(p1, p0)
  TripleDouble::add(q0, p2)
}

///|
fn TripleDouble::f64_mul_add(
  p0 : Double,
  p1 : TripleDouble,
  p2 : TripleDouble,
) -> TripleDouble {
  let q0 = TripleDouble::quick_mult_f64(p1, p0)
  TripleDouble::add(q0, p2)
}

///|
fn TripleDouble::from_quick_mult_dd_f64(
  a : DoubleDouble,
  b : Double,
) -> TripleDouble {
  let { hi: rh, lo: t1, } = mul12(a.hi, b)
  let { hi: t2, lo: t3, } = mul12(a.lo, b)
  let { hi: t5, lo: t4, } = add12(t1, t2)
  let t6 = t3 + t4
  let { hi: rm, lo: rl, } = add12(t5, t6)
  TripleDouble::new(rl, rm, rh)
}

///|
fn TripleDouble::quick_mult_f64(a : TripleDouble, b : Double) -> TripleDouble {
  let { hi: rh, lo: t2, } = mul12(a.hi, b)
  let { hi: t3, lo: t4, } = mul12(a.mid, b)
  let { hi: t9, lo: t7, } = add12(t2, t3)
  let t8 = f_fmla(a.lo, b, t4)
  let t10 = t7 + t8
  let { hi: rm, lo: rl, } = add12(t9, t10)
  TripleDouble::new(rl, rm, rh)
}

///|
fn TripleDouble::quick_mult(b : TripleDouble, a : TripleDouble) -> TripleDouble {
  let { hi: rh, lo: t1, } = DoubleDouble::from_exact_mult(a.hi, b.hi)
  let { hi: t2, lo: t3, } = DoubleDouble::from_exact_mult(a.hi, b.mid)
  let { hi: t4, lo: t5, } = DoubleDouble::from_exact_mult(a.mid, b.hi)
  let { hi: t6, lo: t7, } = DoubleDouble::from_exact_mult(a.mid, b.mid)
  let t12 = f_fmla(a.hi, b.lo, a.lo * b.hi)
  let t13 = f_fmla(a.mid, b.lo, a.lo * b.mid)
  let { hi: t14, lo: t15, } = add12(t1, t6)
  let t16 = t7 + t15
  let t17 = t12 + t13
  let t18 = t16 + t17
  let { hi: t19, lo: t20, } = add12(t14, t18)
  let { hi: t21, lo: t22, } = add22(
    DoubleDouble::new(t3, t2),
    DoubleDouble::new(t4, t5),
  )
  let { hi: rm, lo: rl, } = add22(
    DoubleDouble::new(t22, t21),
    DoubleDouble::new(t20, t19),
  )
  TripleDouble::new(rl, rm, rh)
}

///|
fn TripleDouble::quick_mult_dd(
  b : TripleDouble,
  a : DoubleDouble,
) -> TripleDouble {
  let { hi: rh, lo: t1, } = mul12(a.hi, b.hi)
  let { hi: t2, lo: t3, } = mul12(a.hi, b.mid)
  let { hi: t4, lo: t5, } = mul12(a.hi, b.lo)
  let { hi: t6, lo: t7, } = mul12(a.lo, b.hi)
  let { hi: t8, lo: t9, } = mul12(a.lo, b.mid)
  let t10 = a.lo * b.lo
  let z0 = add22(DoubleDouble::new(t3, t2), DoubleDouble::new(t4, t5))
  let z1 = add22(DoubleDouble::new(t6, t7), DoubleDouble::new(t8, t9))
  let q0 = add22(z0, z1)
  let q1 = add12(t1, t10)
  let { hi: rm, lo: rl, } = add22(q1, q0)
  { hi: rh, mid: rm, lo: rl, }
}

///|
fn TripleDouble::add(a : TripleDouble, b : TripleDouble) -> TripleDouble {
  let { hi: rh, lo: t1, } = add12(a.hi, b.hi)
  let { hi: t2, lo: t3, } = add12(a.mid, b.mid)
  let t6 = a.lo + b.lo
  let { hi: t7, lo: t4, } = add12(t1, t2)
  let t5 = t3 + t4
  let t8 = t5 + t6
  let { hi: rm, lo: rl, } = add12(t7, t8)
  { hi: rh, mid: rm, lo: rl, }
}

///|
fn TripleDouble::add_f64(a : Double, b : TripleDouble) -> TripleDouble {
  let { hi: rh, lo: t1, } = add12(a, b.hi)
  let { hi: t2, lo: t3, } = add12(t1, b.mid)
  let t4 = t3 + b.lo
  let { hi: rm, lo: rl, } = add12(t2, t4)
  TripleDouble::new(rl, rm, rh)
}

///|
fn TripleDouble::to_f64(self : TripleDouble) -> Double {
  let { hi: t1, lo: t2, } = add12(self.hi, self.mid)
  let t3 = t2 + self.lo
  t1 + t3
}

///|
fn TripleDouble::renormalize(self : TripleDouble) -> TripleDouble {
  let { hi: t1h, lo: t1l, } = DoubleDouble::from_exact_add(self.mid, self.lo)
  let { hi: rh, lo: t2l, } = DoubleDouble::from_exact_add(self.hi, t1h)
  let zml = DoubleDouble::from_exact_add(t2l, t1l)
  TripleDouble::new(zml.lo, zml.hi, rh)
}

///|
fn TripleDouble::recip(self : TripleDouble) -> TripleDouble {
  let r1 = 1.0 / self.hi
  let { hi: rec_t1, lo: rec_t2, } = DoubleDouble::from_exact_mult(r1, self.hi)
  let rec_t3 = rec_t1 - 1.0
  let { hi: rec_t4, lo: rec_t5, } = add12(rec_t3, rec_t2)
  let { hi: rec_t6, lo: rec_t7, } = mul12(r1, self.mid)
  let { hi: rec_t8, lo: rec_t9, } = add12(-1.0, rec_t6)
  let rec_t10 = rec_t9 + rec_t7
  let r1 = -r1
  let { hi: rec_t11, lo: rec_t12, } = add12(rec_t8, rec_t10)
  let z0 = add22(
    DoubleDouble::new(rec_t5, rec_t4),
    DoubleDouble::new(rec_t12, rec_t11),
  )
  let r2hl = DoubleDouble::quick_mult_f64(z0, r1)
  let rec15_16_17 = TripleDouble::quick_mult_dd(self, r2hl)
  let rec18_19_20 = rec15_16_17.renormalize()
  let rec_t18 = -1.0
  let rec_21_22_23 = TripleDouble::quick_mult_dd(
    TripleDouble::new(rec18_19_20.lo, rec18_19_20.mid, rec_t18),
    r2hl,
  ).neg()
  rec_21_22_23.renormalize()
}
