// Ported from pxfm 0.1.30 (https://github.com/awxkee/pxfm),
// Copyright (c) Radzivon Bartoshyk. All rights reserved.
// BSD-3-Clause OR Apache-2.0 (see upstream LICENSE.md / LICENSE-APACHE.md).
//
// Port of `logs/log_range_reduction.rs`. The `i128` arithmetic is emulated
// with two's-complement `(hi, lo)` pairs of `UInt64`, wrapping like Rust's
// `wrapping_*` operations.

///|
priv struct I128 {
  hi : UInt64
  lo : UInt64
}

///|
fn I128::from_i64(x : Int64) -> I128 {
  { hi: (x >> 63).reinterpret_as_uint64(), lo: x.reinterpret_as_uint64(), }
}

///|
fn I128::add(self : I128, b : I128) -> I128 {
  let lo = self.lo + b.lo
  let c = if lo < self.lo { 1UL } else { 0UL }
  { hi: self.hi + b.hi + c, lo, }
}

///|
/// `wrapping_shl` for `0 <= n < 128`.
fn I128::shl(self : I128, n : Int32) -> I128 {
  let (hi, lo) = shl128(self.hi, self.lo, n)
  { hi, lo, }
}

///|
/// Arithmetic `>>` for `0 < n < 128`.
fn I128::sar(self : I128, n : Int32) -> I128 {
  let shi = self.hi.reinterpret_as_int64()
  if n < 64 {
    {
      hi: (shi >> n).reinterpret_as_uint64(),
      lo: (self.lo >> n) | (self.hi << (64 - n)),
    }
  } else {
    let s = shi >> 63
    {
      hi: s.reinterpret_as_uint64(),
      lo: (shi >> (n - 64)).reinterpret_as_uint64(),
    }
  }
}

///|
/// Wrapping `i128 * i128` (low 128 bits of the product).
fn I128::mul(self : I128, b : I128) -> I128 {
  let (h, l) = mul_wide_u64(self.lo, b.lo)
  { hi: h + self.lo * b.hi + self.hi * b.lo, lo: l, }
}

///|
fn I128::is_neg(self : I128) -> Bool {
  self.hi >> 63 != 0UL
}

///|
/// Wrapping negation.
fn I128::neg(self : I128) -> I128 {
  let lo = 0UL - self.lo
  let hi = 0UL - self.hi - (if self.lo != 0UL { 1UL } else { 0UL })
  { hi, lo, }
}

///|
/// Perform logarithm range reduction steps 2-4.
///
/// Inputs from the first step of range reduction:
///   m_x : the reduced argument after the first step of range reduction
///         satisfying  -2^-8 <= m_x < 2^-7  and  ulp(m_x) >= 2^-60.
/// Outputs of the extra range reduction steps:
///   sum: adding -log(r1) - log(r2) - log(r3) - log(r4) to the resulted sum.
///   return value: the reduced argument v satisfying:
///                 -0x1.0002143p-29 <= v < 0x1p-29,  and  ulp(v) >= 2^(-125).
///
/// The `log_table` argument of upstream is always
/// `[LOG_STEP_1, LOG_STEP_2, LOG_STEP_3, LOG_STEP_4]` here.
fn log_range_reduction(
  m_x : Double,
  sum : DyadicFloat128,
) -> (DyadicFloat128, DyadicFloat128) {
  let v = (m_x * fb(0x43b0000000000000UL)).to_int64() // ulp = 2^-60
  // Range reduction - Step 2
  // Output range: vv2 in [-0x1.3ffcp-15, 0x1.3e3dp-15].
  // idx2 = trunc(2^14 * (v + 2^-8 + 2^-15))
  let idx2 = ((v + 0x10_2000_0000_0000L) >> 46).to_int()
  let z0 = log_step_2[idx2]
  let mut sum = sum + z0
  let s2 = log_rr_s2[idx2].to_int64() // |s| <= 2^-7, ulp = 2^-16
  let sv2 = s2 * v // |s*v| < 2^-14, ulp = 2^(-60-16) = 2^-76
  let spv2 = (s2 << 44) + v // |s + v| < 2^-14, ulp = 2^-60
  let vv2 = (spv2 << 16) + sv2 // |vv2| < 2^-14, ulp = 2^-76
  // Range reduction - Step 3
  // Output range: vv3 in [-0x1.01928p-22 , 0x1p-22]
  // idx3 = trunc(2^21 * (v + 80*2^-21 + 2^-22))
  let idx3 = ((vv2 + 0x2840_0000_0000_0000L) >> 55).to_int()
  sum = sum + log_step_3[idx3]
  let s3 = log_rr_s3[idx3].to_int64() // |s| < 2^-13, ulp = 2^-21
  let spv3 = (s3 << 55) + vv2 // |s + v| < 2^-21, ulp = 2^-76
  // |s*v| < 2^-27, ulp = 2^(-76-21) = 2^-97
  let sv3 = I128::from_i64(s3).mul(I128::from_i64(vv2))
  // |vv3| < 2^-21, ulp = 2^-97
  let vv3 = I128::from_i64(spv3).shl(21).add(sv3)
  // Range reduction - Step 4
  // Output range: vv4 in [-0x1.0002143p-29 , 0x1p-29]
  // idx4 = trunc(2^21 * (v + 65*2^-28 + 2^-29))
  let idx4 = (vv3.sar(68).lo.to_int() + 131) >> 1
  let z4 = log_step_4[idx4]
  sum = sum + z4
  let s4 = I128::from_i64(log_rr_s4[idx4].to_int64()) // |s| < 2^-21, ulp = 2^-28
  // |s + v| < 2^-28, ulp = 2^-97
  let spv4 = s4.shl(69).add(vv3)
  // |s*v| < 2^-42, ulp = 2^(-97-28) = 2^-125
  let sv4 = s4.mul(vv3)
  // |vv4| < 2^-28, ulp = 2^-125
  let vv4 = spv4.shl(28).add(sv4)
  let z = if vv4.is_neg() {
    let n = vv4.neg()
    DyadicFloat128::new(true, -125, n.hi, n.lo)
  } else {
    DyadicFloat128::new(false, -125, vv4.hi, vv4.lo)
  }
  (z, sum)
}
