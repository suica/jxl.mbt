// Ported from pxfm 0.1.30 (https://github.com/awxkee/pxfm),
// Copyright (c) Radzivon Bartoshyk. All rights reserved.
// BSD-3-Clause OR Apache-2.0 (see upstream LICENSE.md / LICENSE-APACHE.md).
//
// Port of `common.rs`, `bits.rs` and the helpers of `rounding/*.rs` that the
// ported functions reach.
//
// Reference build: x86_64 with default target features, i.e. neither
// `target_feature = "fma"` nor `target_feature = "sse4.1"`. Every `cfg` below
// follows the "not fma" / "not sse4.1" branch. The runtime-dispatched
// AVX+FMA implementations call `f64::mul_add` / `f32::mul_add`, emulated by
// `fma_f64` / `fmaf_f32`.

///|
/// `f64::from_bits`.
fn fb(bits : UInt64) -> Double {
  bits.reinterpret_as_double()
}

///|
/// `f64::to_bits`.
fn tb(x : Double) -> UInt64 {
  x.reinterpret_as_uint64()
}

///|
/// `f32::from_bits`.
fn fbf(bits : UInt32) -> Float {
  Float::reinterpret_from_uint(bits)
}

///|
/// `f32::to_bits`.
fn tbf(x : Float) -> UInt32 {
  x.reinterpret_as_uint()
}

///|
/// `f64::is_sign_negative`.
fn is_sign_negative(x : Double) -> Bool {
  tb(x) >> 63 != 0UL
}

///|
/// `f64::is_nan`.
fn is_nan(x : Double) -> Bool {
  x != x
}

///|
/// `f64::abs`.
fn abs_f64(x : Double) -> Double {
  fb(tb(x) & 0x7fff_ffff_ffff_ffffUL)
}

///|
/// `f64::copysign`.
fn copysign_f64(x : Double, y : Double) -> Double {
  fb((tb(x) & 0x7fff_ffff_ffff_ffffUL) | (tb(y) & 0x8000_0000_0000_0000UL))
}

///|
/// `f_fmla` without `target_feature = "fma"`: plain `a * b + c`.
fn f_fmla(a : Double, b : Double, c : Double) -> Double {
  a * b + c
}

///|
/// `f_fmlaf` without `target_feature = "fma"`: plain `a * b + c`.
fn f_fmlaf(a : Float, b : Float, c : Float) -> Float {
  a * b + c
}

///|
/// `dd_fmla` without `target_feature = "fma"`: Dekker/Veltkamp emulation
/// (`DoubleDouble::dd_f64_mul_add`).
fn dd_fmla(a : Double, b : Double, c : Double) -> Double {
  DoubleDouble::dd_f64_mul_add(a, b, c)
}

///|
/// Rust's `f64::mul_add`: the correctly rounded fused multiply-add
/// (round to nearest, ties to even).
///
/// pxfm calls `f64::mul_add` directly in `log_dd`, `log_td`, `log10_dd`,
/// `log10_td`, and every `FmaBackend` / `FmaPowfBackend` operation goes
/// through it. Without hardware FMA this is the musl `fma` algorithm
/// (exact 128-bit product and sum, one final rounding), ported verbatim
/// minus the floating-point exception plumbing.
fn fma_f64(x : Double, y : Double, z : Double) -> Double {
  let nx = fma_normalize(x)
  let ny = fma_normalize(y)
  let nz = fma_normalize(z)
  let zeroinfnan = 0x7ff - 0x3ff - 52 - 1
  if nx.e >= zeroinfnan || ny.e >= zeroinfnan {
    return x * y + z
  }
  if nz.e >= zeroinfnan {
    if nz.e > zeroinfnan {
      // z == 0
      return x * y + z
    }
    return z
  }
  // mul: r = x*y
  let (rhi0, rlo0) = mul_wide_u64(nx.m, ny.m)
  let mut rhi = rhi0
  let mut rlo = rlo0
  let mut zhi = 0UL
  let mut zlo = 0UL
  // align exponents
  let mut e = nx.e + ny.e
  let mut d = nz.e - e
  // shift bits z<<=kz, r>>=kr, so kz+kr == d, set e = e+kr (== ez-kz)
  if d > 0 {
    if d < 64 {
      zlo = nz.m << d
      zhi = nz.m >> (64 - d)
    } else {
      zlo = 0UL
      zhi = nz.m
      e = nz.e - 64
      d -= 64
      if d == 0 {
        ()
      } else if d < 64 {
        let sticky = if rlo << (64 - d) != 0UL { 1UL } else { 0UL }
        rlo = (rhi << (64 - d)) | (rlo >> d) | sticky
        rhi = rhi >> d
      } else {
        rlo = 1UL
        rhi = 0UL
      }
    }
  } else {
    zhi = 0UL
    d = -d
    if d == 0 {
      zlo = nz.m
    } else if d < 64 {
      let sticky = if nz.m << (64 - d) != 0UL { 1UL } else { 0UL }
      zlo = (nz.m >> d) | sticky
    } else {
      zlo = 1UL
    }
  }
  // add
  let mut sign = nx.sign != ny.sign
  let samesign = sign == nz.sign
  let mut nonzero = true
  if samesign {
    // r += z
    rlo = rlo + zlo
    rhi = rhi + zhi + (if rlo < zlo { 1UL } else { 0UL })
  } else {
    // r -= z
    let t = rlo
    rlo = rlo - zlo
    rhi = rhi - zhi - (if t < rlo { 1UL } else { 0UL })
    if rhi >> 63 != 0UL {
      rlo = 0UL - rlo
      rhi = 0UL - rhi - (if rlo != 0UL { 1UL } else { 0UL })
      sign = !sign
    }
    nonzero = rhi != 0UL
  }
  // set rhi to top 63bit of the result (last bit is sticky)
  if nonzero {
    e += 64
    d = rhi.clz() - 1
    // note: d > 0
    let sticky = if rlo << d != 0UL { 1UL } else { 0UL }
    rhi = (rhi << d) | (rlo >> (64 - d)) | sticky
  } else if rlo != 0UL {
    d = rlo.clz() - 1
    if d < 0 {
      rhi = (rlo >> 1) | (rlo & 1UL)
    } else {
      rhi = rlo << d
    }
  } else {
    // exact +-0
    return x * y + z
  }
  e -= d
  // convert to double
  let mut i = rhi.reinterpret_as_int64() // i is in [1<<62,(1<<63)-1]
  if sign {
    i = -i
  }
  let mut r = i.to_double() // |r| is in [0x1p62,0x1p63]
  if e < -1022 - 62 {
    // result is subnormal before rounding
    if e == -1022 - 63 {
      let c = if sign {
        -fb(0x43e0000000000000UL)
      } else {
        fb(0x43e0000000000000UL)
      }
      if r == c {
        // min normal after rounding
        return if sign {
          fb(0x8010000000000000UL)
        } else {
          fb(0x0010000000000000UL)
        }
      }
      // one bit is lost when scaled, add another top bit to only round once
      // at conversion if it is inexact
      if rhi << 53 != 0UL {
        i = ((rhi >> 1) | (rhi & 1UL) | (1UL << 62)).reinterpret_as_int64()
        if sign {
          i = -i
        }
        r = i.to_double()
        r = 2.0 * r - c // remove top bit
      }
    } else {
      // only round once when scaled
      let dd = 10
      let sticky = if rhi << (64 - dd) != 0UL { 1UL } else { 0UL }
      i = (((rhi >> dd) | sticky) << dd).reinterpret_as_int64()
      if sign {
        i = -i
      }
      r = i.to_double()
    }
  }
  scalbn_f64(r, e)
}

///|
/// Unpacked operand of `fma_f64` (musl `struct num`).
priv struct FmaNum {
  m : UInt64
  e : Int32
  sign : Bool
}

///|
/// musl `normalize`: top 10 bits and last bit of `m` are 0.
fn fma_normalize(x : Double) -> FmaNum {
  let mut ix = tb(x)
  let mut e = (ix >> 52).to_int()
  let sign = (e & 0x800) != 0
  e = e & 0x7ff
  if e == 0 {
    ix = tb(x * fb(0x43e0000000000000UL)) // 0x1p63
    e = (ix >> 52).to_int() & 0x7ff
    e = if e != 0 { e - 63 } else { 0x800 }
  }
  ix = ix & ((1UL << 52) - 1UL)
  ix = ix | (1UL << 52)
  ix = ix << 1
  e -= 0x3ff + 52 + 1
  { m: ix, e, sign, }
}

///|
/// musl `scalbn`.
fn scalbn_f64(x : Double, n : Int32) -> Double {
  let mut y = x
  let mut n = n
  if n > 1023 {
    y = y * fb(0x7fe0000000000000UL)
    n -= 1023
    if n > 1023 {
      y = y * fb(0x7fe0000000000000UL)
      n -= 1023
      if n > 1023 {
        n = 1023
      }
    }
  } else if n < -1022 {
    // make sure final n < -53 to avoid double rounding in the subnormal range
    y = y * (fb(0x0010000000000000UL) * fb(0x4340000000000000UL))
    n += 1022 - 53
    if n < -1022 {
      y = y * (fb(0x0010000000000000UL) * fb(0x4340000000000000UL))
      n += 1022 - 53
      if n < -1022 {
        n = -1022
      }
    }
  }
  y * fb((0x3ff + n).to_uint64() << 52)
}

///|
/// Full 64x64 -> 128-bit product `(hi, lo)`.
fn mul_wide_u64(a : UInt64, b : UInt64) -> (UInt64, UInt64) {
  let a_lo = a & 0xffff_ffffUL
  let a_hi = a >> 32
  let b_lo = b & 0xffff_ffffUL
  let b_hi = b >> 32
  let t1 = a_lo * b_lo
  let t2a = a_lo * b_hi
  let t2b = a_hi * b_lo
  let t3 = a_hi * b_hi
  let mid = (t1 >> 32) + (t2a & 0xffff_ffffUL) + (t2b & 0xffff_ffffUL)
  let lo = (mid << 32) | (t1 & 0xffff_ffffUL)
  let hi = t3 + (t2a >> 32) + (t2b >> 32) + (mid >> 32)
  (hi, lo)
}

///|
/// Rust's `f32::mul_add`: correctly rounded `x * y + z` in f32.
///
/// `x * y` is exact in f64 and `TwoSum` gives the exact sum as `hi + lo`
/// (all exponents stay well inside the f64 range); rounding `hi` to odd when
/// `lo != 0` and then to f32 rounds the exact value only once.
fn fmaf_f32(x : Float, y : Float, z : Float) -> Float {
  let p = x.to_double() * y.to_double()
  let zd = z.to_double()
  let s = DoubleDouble::from_full_exact_add(p, zd)
  let hb = tb(s.hi)
  if s.lo == 0.0 ||
    s.hi != s.hi ||
    (hb & 0x7ff0000000000000UL) == 0x7ff0000000000000UL {
    return Float::from_double(s.hi)
  }
  if (hb & 1UL) != 0UL {
    return Float::from_double(s.hi)
  }
  // Inexact with an even last bit: move one ulp towards the exact value.
  let adj = if (s.lo > 0.0) == (s.hi > 0.0) { hb + 1UL } else { hb - 1UL }
  Float::from_double(fb(adj))
}

///|
/// `f64::to_int_unchecked::<i64>()` as x86-64 executes it (`cvttsd2si`):
/// truncation, and `i64::MIN` for NaN or out-of-range values.
fn to_int_unchecked_i64(x : Double) -> Int64 {
  if x != x || x >= 9223372036854775808.0 || x < -9223372036854775808.0 {
    -9223372036854775807L - 1L
  } else {
    x.to_int64()
  }
}

///|
/// `f32::round_ties_even` (`roundf_ties_even` in pxfm, same semantics).
fn round_ties_even_f32(x : Float) -> Float {
  let mut ix = tbf(x)
  let ux = ix & 0x7fffffffU
  let bias = 0x7f
  let mant_dig = 24
  let max_exp = 2 * bias + 1
  let exponent = (ux >> (mant_dig - 1)).reinterpret_as_int()
  if exponent >= bias + mant_dig - 1 {
    return if exponent == max_exp { x + x } else { x }
  } else if exponent >= bias {
    let int_pos = bias + mant_dig - 1 - exponent
    let half_pos = int_pos - 1
    let half_bit = 1U << half_pos
    let int_bit = 1U << int_pos
    if (ix & (int_bit | (half_bit - 1U))) != 0U {
      ix = ix + half_bit
    }
    ix = ix & (int_bit - 1U).lnot()
  } else if exponent == bias - 1 && ux > 0x3f000000U {
    ix = (ix & 0x80000000U) | 0x3f800000U
  } else {
    ix = ix & 0x80000000U
  }
  fbf(ix)
}

///|
/// `f64::NAN` (0x7ff8000000000000).
let nan_f64 : Double = fb(0x7ff8000000000000UL)

///|
/// `f32::NAN` (0x7fc00000).
let nan_f32 : Float = fbf(0x7fc00000U)

///|
/// `f64::INFINITY`.
let inf_f64 : Double = fb(0x7ff0000000000000UL)

///|
/// `f32::INFINITY`.
let inf_f32 : Float = fbf(0x7f800000U)

///|
/// `is_integerf` (not sse4.1 branch).
fn is_integerf(x : Float) -> Bool {
  let x_u = tbf(x)
  let x_e = (x_u & exp_mask_f32) >> 23
  let lsb = (x_u | exp_mask_f32).ctz().reinterpret_as_uint()
  let unit_exponent : UInt32 = 127U + 23U
  x_e + lsb >= unit_exponent
}

///|
/// `is_odd_integerf` (not aarch64 branch).
fn is_odd_integerf(x : Float) -> Bool {
  let x_u = tbf(x)
  let x_e = (x_u & exp_mask_f32) >> 23
  let lsb = (x_u | exp_mask_f32).ctz().reinterpret_as_uint()
  let unit_exponent : UInt32 = 127U + 23U
  x_e + lsb == unit_exponent
}

///|
/// `is_integer` (not sse4.1 branch).
fn is_integer(n : Double) -> Bool {
  let x_u = tb(n)
  let x_e = (x_u & exp_mask) >> 52
  let lsb = (x_u | exp_mask).ctz().to_uint64()
  let unit_exponent : UInt64 = 1023UL + 52UL
  x_e + lsb >= unit_exponent
}

///|
/// `is_odd_integer` (not sse4.1 branch).
fn is_odd_integer(x : Double) -> Bool {
  let x_u = tb(x)
  let x_e = (x_u & exp_mask) >> 52
  let lsb = (x_u | exp_mask).ctz().to_uint64()
  let unit_exponent : UInt64 = 1023UL + 52UL
  x_e + lsb == unit_exponent
}

///|
/// `pow2if`.
fn pow2if(q : Int32) -> Float {
  fbf((q + 0x7f).reinterpret_as_uint() << 23)
}

///|
/// `min_normal_f64`.
fn min_normal_f64() -> Double {
  fb(1UL << 52)
}

///|
let exp_mask_f32 : UInt32 = 0xffU << 23

///|
let exp_mask : UInt64 = 0x7ffUL << 52

///|
/// `get_exponent_f64`.
fn get_exponent_f64(x : Double) -> Int64 {
  ((tb(x) & exp_mask) >> 52).reinterpret_as_int64() - 1023L
}

///|
/// `biased_exponent_f64`.
fn biased_exponent_f64(x : Double) -> Int64 {
  ((tb(x) & exp_mask) >> 52).reinterpret_as_int64()
}

///|
/// `f64_from_parts` (dyadic_float.rs).
fn f64_from_parts(neg : Bool, exp : UInt64, mantissa : UInt64) -> Double {
  let r_sign = if neg { 1UL << 63 } else { 0UL }
  let r_exp = exp << 52
  fb(r_sign | r_exp | mantissa)
}

///|
/// `fast_ldexp` (exponents/auxiliary.rs).
fn fast_ldexp(d : Double, i : Int32) -> Double {
  let u = tb(d) + (i.to_int64().reinterpret_as_uint64() << 52)
  fb(u)
}

///|
/// `to_denormal` (exponents/exp.rs): sets the exponent field to 0.
fn to_denormal(x : Double) -> Double {
  fb(tb(x) & 0x000fffffffffffffUL)
}

///|
/// `rounding::round` (glibc style, half away from zero), used by
/// `fround_finite` / `cpu_round` without sse4.1.
fn round_f64(x : Double) -> Double {
  let mut i0 = tb(x).reinterpret_as_int64()
  let j0 = (((i0 >> 52) & 0x7ffL) - 0x3ffL).to_int()
  if j0 < 52 {
    if j0 < 0 {
      i0 = i0 & 0x8000000000000000UL.reinterpret_as_int64()
      if j0 == -1 {
        i0 = i0 | 0x3ff0000000000000L
      }
    } else {
      let i = (0x000fffffffffffffUL >> j0).reinterpret_as_int64()
      if (i0 & i) == 0L {
        // X is integral.
        return x
      }
      i0 = i0 + (0x0008000000000000UL >> j0).reinterpret_as_int64()
      i0 = i0 & i.lnot()
    }
  } else {
    return if j0 == 0x400 { x + x } else { x }
  }
  fb(i0.reinterpret_as_uint64())
}

///|
/// `rounding::round_ties_even`, used by `cpu_round_ties_even` without
/// sse4.1.
fn round_ties_even_f64(x : Double) -> Double {
  let mut ix = tb(x)
  let ux = ix & 0x7fffffffffffffffUL
  let bias = 0x3ff
  let mant_dig = 53
  let max_exp = 2 * bias + 1
  let exponent = (ux >> (mant_dig - 1)).to_int()
  if exponent >= bias + mant_dig - 1 {
    // Integer, infinity or NaN.
    return if exponent == max_exp { x + x } else { x }
  } else if exponent >= bias {
    let int_pos = bias + mant_dig - 1 - exponent
    let half_pos = int_pos - 1
    let half_bit = 1UL << half_pos
    let int_bit = 1UL << int_pos
    if (ix & (int_bit | (half_bit - 1UL))) != 0UL {
      ix = ix + half_bit
    }
    ix = ix & (int_bit - 1UL).lnot()
  } else if exponent == bias - 1 && ux > 0x3fe0000000000000UL {
    // Interval (0.5, 1).
    ix = (ix & 0x8000000000000000UL) | 0x3ff0000000000000UL
  } else {
    // Rounds to 0.
    ix = ix & 0x8000000000000000UL
  }
  fb(ix)
}
