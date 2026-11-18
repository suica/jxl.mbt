// Ported from pxfm 0.1.30 (https://github.com/awxkee/pxfm),
// Copyright (c) Radzivon Bartoshyk. All rights reserved.
// BSD-3-Clause OR Apache-2.0 (see upstream LICENSE.md / LICENSE-APACHE.md).
//
// Port of `dyadic_float.rs` (the parts reached by the ported functions).
// The `u128` mantissa is a `(hi, lo)` pair of `UInt64`; `i16` exponents are
// kept in `Int` and wrapped to 16 bits wherever Rust (release build, no
// overflow checks) would wrap.

///|
/// `DyadicFloat128 { sign, exponent, mantissa }`, value
/// `(-1)^neg * mantissa * 2^exponent`, mantissa `(hi << 64) | lo`.
priv struct DyadicFloat128 {
  neg : Bool
  exponent : Int32
  hi : UInt64
  lo : UInt64
}

///|
/// A table / constant entry (`DyadicFloat128 { .. }` literal, not normalized).
fn dyadic_const(
  neg : Bool,
  exponent : Int32,
  hi : UInt64,
  lo : UInt64,
) -> DyadicFloat128 {
  { neg, exponent, hi, lo, }
}

///|
/// Wraps to `i16`.
fn w16(x : Int32) -> Int32 {
  x << 16 >> 16
}

// ---- u128 helpers -----------------------------------------------------------

///|
fn clz128(hi : UInt64, lo : UInt64) -> Int32 {
  if hi != 0UL {
    hi.clz()
  } else {
    64 + lo.clz()
  }
}

///|
/// `u128 << n` for `0 <= n < 128`.
fn shl128(hi : UInt64, lo : UInt64, n : Int32) -> (UInt64, UInt64) {
  if n == 0 {
    (hi, lo)
  } else if n < 64 {
    ((hi << n) | (lo >> (64 - n)), lo << n)
  } else {
    (lo << (n - 64), 0UL)
  }
}

///|
/// `u128 >> n` for `0 <= n < 128`.
fn shr128(hi : UInt64, lo : UInt64, n : Int32) -> (UInt64, UInt64) {
  if n == 0 {
    (hi, lo)
  } else if n < 64 {
    (hi >> n, (lo >> n) | (hi << (64 - n)))
  } else {
    (0UL, hi >> (n - 64))
  }
}

///|
/// `mulhi_u128`.
fn mulhi_u128(
  a_hi : UInt64,
  a_lo : UInt64,
  b_hi : UInt64,
  b_lo : UInt64,
) -> (UInt64, UInt64) {
  let (ll_h, _) = mul_wide_u64(a_lo, b_lo)
  let (lh_h, lh_l) = mul_wide_u64(a_lo, b_hi)
  let (hl_h, hl_l) = mul_wide_u64(a_hi, b_lo)
  let (hh_h, hh_l) = mul_wide_u64(a_hi, b_hi)
  // carry = (lo_lo >> 64) + (lo_hi & MASK) + (hi_lo & MASK)
  let s1 = ll_h + lh_l
  let c1 = if s1 < ll_h { 1UL } else { 0UL }
  let s2 = s1 + hl_l
  let c2 = if s2 < s1 { 1UL } else { 0UL }
  let carry_hi = c1 + c2
  // mid = (lo_hi >> 64) + (hi_lo >> 64) + (carry >> 64)
  let m1 = lh_h + hl_h
  let cm1 = if m1 < lh_h { 1UL } else { 0UL }
  let m2 = m1 + carry_hi
  let cm2 = if m2 < m1 { 1UL } else { 0UL }
  let mid_hi = cm1 + cm2
  // hi_hi + mid
  let lo = hh_l + m2
  let c = if lo < hh_l { 1UL } else { 0UL }
  (hh_h + mid_hi + c, lo)
}

// ---- DyadicFloat128 ---------------------------------------------------------

///|
fn DyadicFloat128::zero() -> DyadicFloat128 {
  { neg: false, exponent: 0, hi: 0UL, lo: 0UL, }
}

///|
fn DyadicFloat128::is_zero(self : DyadicFloat128) -> Bool {
  self.hi == 0UL && self.lo == 0UL
}

///|
/// `normalize`.
fn DyadicFloat128::normalize(self : DyadicFloat128) -> DyadicFloat128 {
  if self.is_zero() {
    return self
  }
  let s = clz128(self.hi, self.lo)
  let (hi, lo) = shl128(self.hi, self.lo, s)
  { neg: self.neg, exponent: w16(self.exponent - s), hi, lo, }
}

///|
/// `DyadicFloat128::new` (normalizes).
fn DyadicFloat128::new(
  neg : Bool,
  exponent : Int32,
  hi : UInt64,
  lo : UInt64,
) -> DyadicFloat128 {
  { neg, exponent: w16(exponent), hi, lo, }.normalize()
}

///|
/// `shift_right`.
fn DyadicFloat128::shift_right(
  self : DyadicFloat128,
  amount : Int32,
) -> DyadicFloat128 {
  if amount < 128 {
    let (hi, lo) = shr128(self.hi, self.lo, amount)
    { neg: self.neg, exponent: w16(self.exponent + amount), hi, lo, }
  } else {
    { neg: self.neg, exponent: 0, hi: 0UL, lo: 0UL, }
  }
}

///|
/// `shift_left`.
fn DyadicFloat128::shift_left(
  self : DyadicFloat128,
  amount : Int32,
) -> DyadicFloat128 {
  if amount < 128 {
    let (hi, lo) = shl128(self.hi, self.lo, amount)
    { neg: self.neg, exponent: w16(self.exponent - amount), hi, lo, }
  } else {
    { neg: self.neg, exponent: 0, hi: 0UL, lo: 0UL, }
  }
}

///|
/// `explicit_exponent`.
fn explicit_exponent(x : Double) -> Int32 {
  let e = ((tb(x) >> 52) & 0x7ffUL).to_int() - 1023
  if x == 0.0 {
    0
  } else if is_subnormal_f64(x) {
    1 - 1023
  } else {
    e
  }
}

///|
/// `explicit_mantissa`.
fn explicit_mantissa(x : Double) -> UInt64 {
  let sig_bits = tb(x) & ((1UL << 52) - 1UL)
  if is_subnormal_f64(x) || x == 0.0 {
    sig_bits
  } else {
    (1UL << 52) | sig_bits
  }
}

///|
/// `f64::is_subnormal`.
fn is_subnormal_f64(x : Double) -> Bool {
  let b = tb(x)
  (b & 0x7ff0000000000000UL) == 0UL && (b & 0x000fffffffffffffUL) != 0UL
}

///|
/// `new_from_f64`.
fn DyadicFloat128::new_from_f64(x : Double) -> DyadicFloat128 {
  let neg = is_sign_negative(x)
  let exponent = w16(explicit_exponent(x) - 52)
  { neg, exponent, hi: 0UL, lo: explicit_mantissa(x), }.normalize()
}

///|
/// `mul_int64`.
fn DyadicFloat128::mul_int64(
  self : DyadicFloat128,
  b : Int64,
) -> DyadicFloat128 {
  if b == 0L {
    return DyadicFloat128::zero()
  }
  let abs_b = if b < 0L {
    (0L - b).reinterpret_as_uint64()
  } else {
    b.reinterpret_as_uint64()
  }
  let neg = (b < 0L) != self.neg
  let (hp_hi0, hp_lo0) = mul_wide_u64(self.hi, abs_b)
  let m = clz128(hp_hi0, hp_lo0)
  // `hi_prod <<= m` (release build: the shift amount is masked)
  let (hp_hi, hp_lo) = shl128(hp_hi0, hp_lo0, m & 127)
  let (lp_hi0, lp_lo0) = mul_wide_u64(self.lo, abs_b)
  // `(lo_prod << (m - 1)) >> 63`, `m - 1` wrapping in u32 then masked
  let (lp_hi1, lp_lo1) = shl128(lp_hi0, lp_lo0, (m - 1) & 127)
  let (lp_hi, lp_lo) = shr128(lp_hi1, lp_lo1, 63)
  // overflowing_add
  let p_lo = hp_lo + lp_lo
  let c = if p_lo < hp_lo { 1UL } else { 0UL }
  let p_hi_partial = hp_hi + lp_hi
  let o1 = p_hi_partial < hp_hi
  let p_hi = p_hi_partial + c
  let o2 = p_hi < p_hi_partial
  let overflow = o1 || o2
  let mut result : DyadicFloat128 = {
    neg,
    exponent: w16(self.exponent + 64 - m),
    hi: p_hi,
    lo: p_lo,
  }
  if overflow {
    // product += product & 0x1 (wrapping)
    let add = p_lo & 1UL
    let q_lo = p_lo + add
    let q_hi = p_hi + (if q_lo < p_lo { 1UL } else { 0UL })
    let (s_hi, s_lo) = shr128(q_hi, q_lo, 1)
    result = {
      neg,
      exponent: result.exponent,
      hi: s_hi | 0x8000_0000_0000_0000UL,
      lo: s_lo,
    }
    result = result.shift_right(1)
  }
  result.normalize()
}

///|
/// `quick_add`.
fn DyadicFloat128::quick_add(
  self : DyadicFloat128,
  rhs : DyadicFloat128,
) -> DyadicFloat128 {
  if self.is_zero() {
    return rhs
  }
  if rhs.is_zero() {
    return self
  }
  let mut a = self
  let mut b = rhs
  let exp_diff = w16(a.exponent - b.exponent)
  // i16::abs wraps for i16::MIN in a release build
  let abs_diff = if exp_diff < 0 { w16(-exp_diff) } else { exp_diff }
  if abs_diff >= 128 {
    return if a.exponent > b.exponent { a } else { b }
  }
  // Align exponents
  if a.exponent > b.exponent {
    b = b.shift_right(w16(a.exponent - b.exponent))
  } else if b.exponent > a.exponent {
    a = a.shift_right(w16(b.exponent - a.exponent))
  }
  if a.neg == b.neg {
    // Addition
    let lo = a.lo + b.lo
    let c = if lo < a.lo { 1UL } else { 0UL }
    let hi_partial = a.hi + b.hi
    let o1 = hi_partial < a.hi
    let hi = hi_partial + c
    let o2 = hi < hi_partial
    let result : DyadicFloat128 = { neg: a.neg, exponent: a.exponent, hi, lo, }
    if o1 || o2 {
      // Mantissa addition overflow.
      let r = result.shift_right(1)
      return {
        neg: r.neg,
        exponent: r.exponent,
        hi: r.hi | 0x8000_0000_0000_0000UL,
        lo: r.lo,
      }
    }
    return result
  }
  // Subtraction
  let a_ge_b = a.hi > b.hi || (a.hi == b.hi && a.lo >= b.lo)
  let result : DyadicFloat128 = if a_ge_b {
    let lo = a.lo - b.lo
    let br = if a.lo < b.lo { 1UL } else { 0UL }
    { neg: a.neg, exponent: a.exponent, hi: a.hi - b.hi - br, lo, }
  } else {
    let lo = b.lo - a.lo
    let br = if b.lo < a.lo { 1UL } else { 0UL }
    { neg: b.neg, exponent: b.exponent, hi: b.hi - a.hi - br, lo, }
  }
  result.normalize()
}

///|
/// `quick_mul`.
fn DyadicFloat128::quick_mul(
  self : DyadicFloat128,
  rhs : DyadicFloat128,
) -> DyadicFloat128 {
  let neg = self.neg != rhs.neg
  let exponent = w16(self.exponent + rhs.exponent + 128)
  if self.is_zero() || rhs.is_zero() {
    return { neg, exponent, hi: 0UL, lo: 0UL, }
  }
  let (hi, lo) = mulhi_u128(self.hi, self.lo, rhs.hi, rhs.lo)
  let result : DyadicFloat128 = { neg, exponent, hi, lo, }
  if hi >> 63 == 0UL {
    result.shift_left(1)
  } else {
    result
  }
}

///|
impl Add for DyadicFloat128 with fn add(self, rhs) {
  self.quick_add(rhs)
}

///|
impl Mul for DyadicFloat128 with fn mul(self, rhs) {
  self.quick_mul(rhs)
}

///|
/// `fast_as_f64`.
fn DyadicFloat128::fast_as_f64(self : DyadicFloat128) -> Double {
  if self.is_zero() {
    return if self.neg { -0.0 } else { 0.0 }
  }
  // Assume that it is normalized, and output is also normal.
  let precision = 53
  let exp_bias = 1023
  // IMPLICIT_MASK = SIG_MASK - FRACTION_MASK = 0
  let sig_mask = (1UL << 52) - 1UL
  let mut exp_hi = self.exponent + (127 + exp_bias)
  if exp_hi > 2 * exp_bias {
    // Results overflow.
    let d_hi = f64_from_parts(self.neg, (2 * exp_bias).to_uint64(), 0UL)
    return 2.0 * d_hi
  }
  let mut denorm = false
  let mut shift = 128 - precision
  if exp_hi <= 0 {
    // Output is denormal.
    denorm = true
    shift = 128 - precision + (1 - exp_hi)
    exp_hi = exp_bias
  }
  let exp_lo = exp_hi - precision - 1
  let m_hi_lo64 = if shift >= 128 {
    0UL
  } else {
    let (_, l) = shr128(self.hi, self.lo, shift)
    l
  }
  let d_hi = f64_from_parts(self.neg, exp_hi.to_uint64(), m_hi_lo64 & sig_mask)
  // round_mask = 1 << (shift - 1), or 0 when shift > 128
  let (rm_hi, rm_lo) = if shift > 128 {
    (0UL, 0UL)
  } else {
    shl128(0UL, 1UL, (shift - 1) & 127)
  }
  // sticky_mask = round_mask - 1 (wrapping)
  let sm_lo = rm_lo - 1UL
  let sm_hi = rm_hi - (if rm_lo == 0UL { 1UL } else { 0UL })
  let round_bit = (self.hi & rm_hi) != 0UL || (self.lo & rm_lo) != 0UL
  let sticky_bit = (self.hi & sm_hi) != 0UL || (self.lo & sm_lo) != 0UL
  let round_and_sticky = (if round_bit { 2 } else { 0 }) +
    (if sticky_bit { 1 } else { 0 })
  if exp_lo <= 0 {
    // d_lo is denormal, but the output is normal.
    let scale_up_exponent = 1 - exp_lo
    let scale_up_factor = f64_from_parts(
      false,
      (exp_bias + scale_up_exponent).to_uint64(),
      0UL,
    )
    let scale_down_factor = f64_from_parts(
      false,
      exp_bias.to_uint64() - scale_up_exponent.to_uint64(),
      0UL,
    )
    let d_lo = f64_from_parts(
      self.neg,
      (exp_lo + scale_up_exponent).to_uint64(),
      0UL,
    )
    return f_fmla(d_lo, round_and_sticky.to_double(), d_hi * scale_up_factor) *
      scale_down_factor
  }
  let d_lo = f64_from_parts(self.neg, exp_lo.to_uint64(), 0UL)
  // Still correct without FMA instructions if `d_lo` is not underflow.
  let r = f_fmla(d_lo, round_and_sticky.to_double(), d_hi)
  if denorm {
    // Exponent before rounding is in denormal range, simply clear the
    // exponent field.
    let clear_exp = exp_hi.to_uint64() << 52
    let r_bits = tb(r) - clear_exp
    // (`r_bits -= IMPLICIT_MASK` with IMPLICIT_MASK = 0 is a no-op)
    return fb(r_bits)
  }
  r
}

///|
/// `trunc_to_i64`.
fn DyadicFloat128::trunc_to_i64(self : DyadicFloat128) -> Int64 {
  if self.exponent <= -128 {
    return 0L
  }
  let norm_exp = w16(self.exponent + 127)
  if norm_exp > 63 {
    return if self.neg {
      -9223372036854775807L - 1L
    } else {
      9223372036854775807L
    }
  }
  let r = (self.hi >> (63 - norm_exp)).reinterpret_as_int64()
  if self.neg {
    0L - r
  } else {
    r
  }
}
