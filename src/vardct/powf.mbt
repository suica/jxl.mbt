// `powf` as used by jxl-oxide through Rust's `f32::powf`, which calls the
// system libm. On x86_64 glibc (>= 2.27) with FMA this is the Arm
// optimized-routines `powf` (MIT, Copyright (c) 2017-2018 Arm Limited)
// compiled with FMA contraction. It is ported here, with an exact `fma`
// emulation, so that dequantization matrices match jxl-oxide bit-exactly.

///|
fn d(bits : UInt64) -> Double {
  bits.reinterpret_as_double()
}

///|
let powf_invc : FixedArray[Double] = [
  d(0x3FF661EC79F8F3BEUL),
  d(0x3FF571ED4AAF883DUL),
  d(0x3FF49539F0F010B0UL),
  d(0x3FF3C995B0B80385UL),
  d(0x3FF30D190C8864A5UL),
  d(0x3FF25E227B0B8EA0UL),
  d(0x3FF1BB4A4A1A343FUL),
  d(0x3FF12358F08AE5BAUL),
  d(0x3FF0953F419900A7UL),
  d(0x3FF0000000000000UL),
  d(0x3FEE608CFD9A47ACUL),
  d(0x3FECA4B31F026AA0UL),
  d(0x3FEB2036576AFCE6UL),
  d(0x3FE9C2D163A1AA2DUL),
  d(0x3FE886E6037841EDUL),
  d(0x3FE767DCF5534862UL),
]

///|
let powf_logc : FixedArray[Double] = [
  d(0xBFDEFEC65B963019UL),
  d(0xBFDB0B6832D4FCA4UL),
  d(0xBFD7418B0A1FB77BUL),
  d(0xBFD39DE91A6DCF7BUL),
  d(0xBFD01D9BF3F2B631UL),
  d(0xBFC97C1D1B3B7AF0UL),
  d(0xBFC2F9E393AF3C9FUL),
  d(0xBFB960CBBF788D5CUL),
  d(0xBFAA6F9DB6475FCEUL),
  d(0x0000000000000000UL),
  d(0x3FB338CA9F24F53DUL),
  d(0x3FC476A9543891BAUL),
  d(0x3FCE840B4AC4E4D2UL),
  d(0x3FD40645F0C6651CUL),
  d(0x3FD88E9C2C1B9FF8UL),
  d(0x3FDCE0A44EB17BCCUL),
]

///|
let powf_poly : FixedArray[Double] = [
  d(0x3FD27616C9496E0BUL),
  d(0xBFD71969A075C67AUL),
  d(0x3FDEC70A6CA7BADDUL),
  d(0xBFE7154748BEF6C8UL),
  d(0x3FF71547652AB82BUL),
]

///|
let exp2f_tab : FixedArray[UInt64] = [
  0x3ff0000000000000UL, 0x3fefd9b0d3158574UL, 0x3fefb5586cf9890fUL, 0x3fef9301d0125b51UL,
  0x3fef72b83c7d517bUL, 0x3fef54873168b9aaUL, 0x3fef387a6e756238UL, 0x3fef1e9df51fdee1UL,
  0x3fef06fe0a31b715UL, 0x3feef1a7373aa9cbUL, 0x3feedea64c123422UL, 0x3feece086061892dUL,
  0x3feebfdad5362a27UL, 0x3feeb42b569d4f82UL, 0x3feeab07dd485429UL, 0x3feea47eb03a5585UL,
  0x3feea09e667f3bcdUL, 0x3fee9f75e8ec5f74UL, 0x3feea11473eb0187UL, 0x3feea589994cce13UL,
  0x3feeace5422aa0dbUL, 0x3feeb737b0cdc5e5UL, 0x3feec49182a3f090UL, 0x3feed503b23e255dUL,
  0x3feee89f995ad3adUL, 0x3feeff76f2fb5e47UL, 0x3fef199bdd85529cUL, 0x3fef3720dcef9069UL,
  0x3fef5818dcfba487UL, 0x3fef7c97337b9b5fUL, 0x3fefa4afa2a490daUL, 0x3fefd0765b6e4540UL,
]

///|
let exp2f_poly : FixedArray[Double] = [
  d(0x3FAC6AF84B912394UL),
  d(0x3FCEBFCE50FAC4F3UL),
  d(0x3FE62E42FF0C52D6UL),
]

///|
/// `0x1.8p+52 / 32`
let exp2f_shift_scaled : Double = d(0x42E8000000000000UL)

///|
/// `0x1.fffffffd1d571p+6`
let powf_oflow_bound : Double = d(0x405FFFFFFFD1D571UL)

///|
fn two_sum(a : Double, b : Double) -> (Double, Double) {
  let s = a + b
  let bb = s - a
  (s, a - (s - bb) + (b - bb))
}

///|
fn veltkamp_split(a : Double) -> (Double, Double) {
  let c = 134217729.0 * a
  let hi = c - (c - a)
  (hi, a - hi)
}

///|
fn two_prod(a : Double, b : Double) -> (Double, Double) {
  let p = a * b
  let (ah, al) = veltkamp_split(a)
  let (bh, bl) = veltkamp_split(b)
  (p, ah * bh - p + ah * bl + al * bh + al * bl)
}

///|
/// `a + b` rounded to odd.
fn add_round_to_odd(a : Double, b : Double) -> Double {
  let (s, err) = two_sum(a, b)
  if err == 0.0 {
    return s
  }
  let bits = s.reinterpret_as_uint64()
  if (bits & 1UL) != 0UL {
    return s
  }
  let nb = if (err > 0.0) == (s > 0.0) { bits + 1UL } else { bits - 1UL }
  nb.reinterpret_as_double()
}

///|
/// Fused multiply-add on doubles: `a * b + c` rounded once (Boldo-Melquiond
/// emulation via rounding to odd). Valid without overflow/underflow, which
/// holds for the arguments used by `powf`.
fn fma_f64(a : Double, b : Double, c : Double) -> Double {
  let (uh, ul) = two_prod(a, b)
  let (th, tl) = two_sum(c, uh)
  th + add_round_to_odd(tl, ul)
}

///|
fn powf_log2_inline(ix : UInt32) -> Double {
  let tmp = ix - 0x3f330000U
  let i = ((tmp >> 19) % 16U).reinterpret_as_int()
  let top = tmp & 0xff800000U
  let iz = ix - top
  let k = top.reinterpret_as_int() >> 23
  let invc = powf_invc[i]
  let logc = powf_logc[i]
  let z = Float::reinterpret_from_uint(iz).to_double()
  let r = fma_f64(z, invc, -1.0)
  let y0 = logc + k.to_double()
  let r2 = r * r
  let y = fma_f64(powf_poly[0], r, powf_poly[1])
  let p = fma_f64(powf_poly[2], r, powf_poly[3])
  let r4 = r2 * r2
  let q = fma_f64(powf_poly[4], r, y0)
  let q = fma_f64(p, r2, q)
  fma_f64(y, r4, q)
}

///|
fn powf_exp2_inline(xd : Double, sign_bias : UInt64) -> Float {
  let kd = xd + exp2f_shift_scaled
  let ki = kd.reinterpret_as_uint64()
  let kd = kd - exp2f_shift_scaled
  let r = xd - kd
  let t = exp2f_tab[(ki % 32UL).to_int()]
  let ski = ki + sign_bias
  let t = t + (ski << 47)
  let s = t.reinterpret_as_double()
  let z = fma_f64(exp2f_poly[0], r, exp2f_poly[1])
  let r2 = r * r
  let y = fma_f64(exp2f_poly[2], r, 1.0)
  let y = fma_f64(z, r2, y)
  let y = y * s
  Float::from_double(y)
}

///|
/// Returns 0 if not int, 1 if odd int, 2 if even int.
fn powf_checkint(iy : UInt32) -> Int32 {
  let e = ((iy >> 23) & 0xffU).reinterpret_as_int()
  if e < 0x7f {
    return 0
  }
  if e > 0x7f + 23 {
    return 2
  }
  if (iy & ((1U << (0x7f + 23 - e)) - 1U)) != 0U {
    return 0
  }
  if (iy & (1U << (0x7f + 23 - e))) != 0U {
    return 1
  }
  2
}

///|
fn powf_zeroinfnan(ix : UInt32) -> Bool {
  2U * ix - 1U >= 2U * 0x7f800000U - 1U
}

///|
/// `powf(x, y)`, bit-compatible with glibc's x86_64 FMA implementation.
fn powf(x : Float, y : Float) -> Float {
  let mut sign_bias = 0UL
  let mut ix = x.reinterpret_as_uint()
  let iy = y.reinterpret_as_uint()
  if ix - 0x00800000U >= 0x7f800000U - 0x00800000U || powf_zeroinfnan(iy) {
    if powf_zeroinfnan(iy) {
      if 2U * iy == 0U {
        return 1.0
      }
      if ix == 0x3f800000U {
        return 1.0
      }
      if 2U * ix > 2U * 0x7f800000U || 2U * iy > 2U * 0x7f800000U {
        return x + y
      }
      if 2U * ix == 2U * 0x3f800000U {
        return 1.0
      }
      if (2U * ix < 2U * 0x3f800000U) == ((iy & 0x80000000U) == 0U) {
        return 0.0
      }
      return y * y
    }
    if powf_zeroinfnan(ix) {
      let mut x2 = x * x
      if (ix & 0x80000000U) != 0U && powf_checkint(iy) == 1 {
        x2 = -x2
      }
      return if (iy & 0x80000000U) != 0U { 1.0 / x2 } else { x2 }
    }
    // x and y are non-zero finite.
    if (ix & 0x80000000U) != 0U {
      let yint = powf_checkint(iy)
      if yint == 0 {
        return (x - x) / (x - x)
      }
      if yint == 1 {
        sign_bias = 1UL << (5 + 11)
      }
      ix = ix & 0x7fffffffU
    }
    if ix < 0x00800000U {
      // Normalize subnormal x so exponent becomes negative.
      ix = (x * 8388608.0).reinterpret_as_uint()
      ix = ix & 0x7fffffffU
      ix = ix - (23U << 23)
    }
  }
  let logx = powf_log2_inline(ix)
  let ylogx = y.to_double() * logx
  if ((ylogx.reinterpret_as_uint64() >> 47) & 0xffffUL) >=
    (126.0 : Double).reinterpret_as_uint64() >> 47 {
    let neg = sign_bias != 0UL
    if ylogx > powf_oflow_bound {
      let inf = Float::reinterpret_from_uint(0x7f800000U)
      return if neg { -inf } else { inf }
    }
    if ylogx <= -150.0 {
      return if neg { -0.0 } else { 0.0 }
    }
  }
  powf_exp2_inline(ylogx, sign_bias)
}
