// Fast math routines, ported from libjxl (jxl-color `fastmath.rs`).
//
// Also holds small f32 helpers that Rust's `f32` provides natively
// (`mul_add`, `copysign`, `log2`).

///|
/// Fused multiply-add on `Float`: computes `a * b + c` with a single rounding,
/// like Rust's `f32::mul_add`.
///
/// The product of two f32 values is exact in f64, so only the final addition
/// can introduce double rounding (f64 then f32); that case is detected and
/// corrected as in musl's `fmaf`.
fn mul_add_f32(a : Float, b : Float, c : Float) -> Float {
  let xy = a.to_double() * b.to_double()
  let z = c.to_double()
  let result = xy + z
  let bits = result.reinterpret_as_uint64()
  let e = ((bits >> 52) & 0x7ffUL).to_int()
  // Common case: the double precision result is fine.
  if (bits & 0x1fffffffUL) != 0x10000000UL ||
    e == 0x7ff ||
    (result - xy == z && result - z == xy) {
    return Float::from_double(result)
  }
  // `result` is exactly halfway between two floats and inexact: nudge it
  // towards the exact value so that the f32 rounding goes the right way.
  let neg = bits >> 63 != 0UL
  let err = if neg == (z > xy) { xy - result + z } else { z - result + xy }
  let adjusted = if neg == (err < 0.0) { bits + 1UL } else { bits - 1UL }
  Float::from_double(adjusted.reinterpret_as_double())
}

///|
/// Fused multiply-add on `Double` (`f64::mul_add`): `a * b + c` rounded once.
///
/// Exact product (Dekker), exact sum (Knuth's TwoSum) and a round-to-odd
/// correction (Boldo and Melquiond, "Emulation of FMA and correctly rounded
/// sums: proved algorithms using rounding to odd"). Exact unless the product
/// or the sum overflows or underflows.
fn mul_add_f64(a : Double, b : Double, c : Double) -> Double {
  let p = a * b
  if p.is_inf() || p.is_nan() || c.is_inf() || c.is_nan() || p == 0.0 {
    return p + c
  }
  // Dekker split: a * b == p + perr exactly
  let split = 134217729.0 // 2^27 + 1
  let ta = split * a
  let ahi = ta - (ta - a)
  let alo = a - ahi
  let tb = split * b
  let bhi = tb - (tb - b)
  let blo = b - bhi
  let perr = alo * blo - (p - ahi * bhi - alo * bhi - ahi * blo)
  // TwoSum: c + p == th + tl exactly
  let th = c + p
  let bb = th - c
  let tl = c - (th - bb) + (p - bb)
  // v = round_to_odd(tl + perr)
  let v = tl + perr
  let vb = v - tl
  let verr = tl - (v - vb) + (perr - vb)
  let v = if verr != 0.0 && (v.reinterpret_as_uint64() & 1UL) == 0UL {
    let bits = v.reinterpret_as_uint64()
    // move |v| towards the exact value: up if err has the same sign as v
    if (verr > 0.0) == (v > 0.0) {
      (bits + 1UL).reinterpret_as_double()
    } else {
      (bits - 1UL).reinterpret_as_double()
    }
  } else {
    v
  }
  th + v
}

///|
/// glibc's `powf` (sysdeps/ieee754/flt-32/e_powf.c, from ARM's optimized
/// routines), which Rust's `f32::powf` calls on x86_64 Linux. This is the
/// FMA variant that glibc selects on CPUs with FMA (built with `-mfma`, so
/// GCC contracts `a * b + c` into fused multiply-adds). Tables are those of
/// `__powf_log2_data` and `__exp2f_data`.
fn powf_glibc(x : Float, y : Float) -> Float {
  let mut sign_bias = 0UL
  let mut ix = x.reinterpret_as_uint()
  let iy = y.reinterpret_as_uint()
  if ix - 0x00800000U >= 0x7f800000U - 0x00800000U || zeroinfnan_f32(iy) {
    // Either (x < 0x1p-126 or inf or nan) or (y is 0 or inf or nan).
    if zeroinfnan_f32(iy) {
      if iy * 2 == 0 {
        return if is_signaling_f32(x) { x + y } else { 1.0 }
      }
      if ix == 0x3f800000U {
        return if is_signaling_f32(y) { x + y } else { 1.0 }
      }
      if ix * 2 > 0x7f800000U * 2 || iy * 2 > 0x7f800000U * 2 {
        return x + y
      }
      if ix * 2 == 0x3f800000U * 2 {
        return 1.0
      }
      if (ix * 2 < 0x3f800000U * 2) == ((iy & 0x80000000U) == 0) {
        return 0.0 // |x|<1 && y==inf or |x|>1 && y==-inf.
      }
      return y * y
    }
    if zeroinfnan_f32(ix) {
      let mut x2 = x * x
      if (ix & 0x80000000U) != 0 && checkint_f32(iy) == 1 {
        x2 = -x2
      }
      return if (iy & 0x80000000U) != 0 { (1.0 : Float) / x2 } else { x2 }
    }
    // x and y are non-zero finite.
    if (ix & 0x80000000U) != 0 {
      // Finite x < 0.
      let yint = checkint_f32(iy)
      if yint == 0 {
        return (x - x) / (x - x)
      }
      if yint == 1 {
        sign_bias = 1UL << 16
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
  let ylogx = y.to_double() * logx // Note: cannot overflow, y is single prec.
  if ((ylogx.reinterpret_as_uint64() >> 47) & 0xffffUL) >=
    (126.0 : Double).reinterpret_as_uint64() >> 47 {
    // |y*log(x)| >= 126.
    if ylogx > 0x1.fffffffd1d571p+6 {
      // __math_oflowf
      let v : Float = if sign_bias != 0UL { -0x1.0p97 } else { 0x1.0p97 }
      return v * 0x1.0p97
    }
    if ylogx <= -150.0 {
      // __math_uflowf
      let v : Float = if sign_bias != 0UL { -0x1.0p-95 } else { 0x1.0p-95 }
      return v * 0x1.0p-95
    }
  }
  powf_exp2_inline(ylogx, sign_bias)
}

///|
fn zeroinfnan_f32(ix : UInt32) -> Bool {
  ix * 2 - 1 >= 0x7f800000U * 2 - 1
}

///|
fn is_signaling_f32(x : Float) -> Bool {
  let ix = x.reinterpret_as_uint()
  (ix & 0x7fc00000U) == 0x7f800000U && (ix & 0x003fffffU) != 0
}

///|
/// Returns 0 if not int, 1 if odd int, 2 if even int. The argument is the
/// bit representation of a non-zero finite floating-point value.
fn checkint_f32(iy : UInt32) -> Int32 {
  let e = ((iy >> 23) & 0xffU).reinterpret_as_int()
  if e < 0x7f {
    return 0
  }
  if e > 0x7f + 23 {
    return 2
  }
  if (iy & ((1U << (0x7f + 23 - e)) - 1U)) != 0 {
    return 0
  }
  if (iy & (1U << (0x7f + 23 - e))) != 0 {
    return 1
  }
  2
}

///|
let powf_log2_invc : FixedArray[Double] = [
  0x1.661ec79f8f3bep+0, 0x1.571ed4aaf883dp+0, 0x1.49539f0f010b0p+0, 0x1.3c995b0b80385p+0,
  0x1.30d190c8864a5p+0, 0x1.25e227b0b8ea0p+0, 0x1.1bb4a4a1a343fp+0, 0x1.12358f08ae5bap+0,
  0x1.0953f419900a7p+0, 0x1.0000000000000p+0, 0x1.e608cfd9a47acp-1, 0x1.ca4b31f026aa0p-1,
  0x1.b2036576afce6p-1, 0x1.9c2d163a1aa2dp-1, 0x1.886e6037841edp-1, 0x1.767dcf5534862p-1,
]

///|
let powf_log2_logc : FixedArray[Double] = [
  -0x1.efec65b963019p-2, -0x1.b0b6832d4fca4p-2, -0x1.7418b0a1fb77bp-2, -0x1.39de91a6dcf7bp-2,
  -0x1.01d9bf3f2b631p-2, -0x1.97c1d1b3b7af0p-3, -0x1.2f9e393af3c9fp-3, -0x1.960cbbf788d5cp-4,
  -0x1.a6f9db6475fcep-5, 0.0, 0x1.338ca9f24f53dp-4, 0x1.476a9543891bap-3, 0x1.e840b4ac4e4d2p-3,
  0x1.40645f0c6651cp-2, 0x1.88e9c2c1b9ff8p-2, 0x1.ce0a44eb17bccp-2,
]

///|
let powf_log2_poly : FixedArray[Double] = [
  0x1.27616c9496e0bp-2, -0x1.71969a075c67ap-2, 0x1.ec70a6ca7baddp-2, -0x1.7154748bef6c8p-1,
  0x1.71547652ab82bp+0,
]

///|
/// Subnormal input is normalized so ix has negative biased exponent.
/// Output is log2(x) (in double precision).
fn powf_log2_inline(ix : UInt32) -> Double {
  let tmp = ix - 0x3f330000U
  let i = ((tmp >> 19) % 16U).reinterpret_as_int()
  let top = tmp & 0xff800000U
  let iz = ix - top
  let k = top.reinterpret_as_int() >> 23
  let invc = powf_log2_invc[i]
  let logc = powf_log2_logc[i]
  let z = Float::reinterpret_from_uint(iz).to_double()
  // log2(x) = log1p(z/c-1)/ln2 + log2(c) + k
  let r = mul_add_f64(z, invc, -1.0)
  let y0 = logc + k.to_double()
  // Pipelined polynomial evaluation to approximate log1p(r)/ln2.
  let r2 = r * r
  let a = powf_log2_poly
  let y = mul_add_f64(a[0], r, a[1])
  let p = mul_add_f64(a[2], r, a[3])
  let r4 = r2 * r2
  let q = mul_add_f64(a[4], r, y0)
  let q = mul_add_f64(p, r2, q)
  mul_add_f64(y, r4, q)
}

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
fn powf_exp2_inline(xd : Double, sign_bias : UInt64) -> Float {
  let shift = 0x1.8p+47 // 0x1.8p+52 / N
  // x = k/N + r, with int k and r in [-1/2N, 1/2N]
  let kd = xd + shift
  let ki = kd.reinterpret_as_uint64()
  let kd = kd - shift // k/N
  let r = xd - kd
  // exp2(x) = 2^(k/N) * 2^r ~= s * (C0*r^3 + C1*r^2 + C2*r + 1)
  let t = exp2f_tab[(ki % 32UL).to_int()]
  let ski = ki + sign_bias
  let t = t + (ski << (52 - 5))
  let s = t.reinterpret_as_double()
  let z = mul_add_f64(0x1.c6af84b912394p-5, r, 0x1.ebfce50fac4f3p-3)
  let r2 = r * r
  let y = mul_add_f64(0x1.62e42ff0c52d6p-1, r, 1.0)
  let y = mul_add_f64(z, r2, y)
  let y = y * s
  Float::from_double(y)
}

///|
/// `f32::copysign`: magnitude of `mag` with the sign of `sign`.
fn copysign_f32(mag : Float, sign : Float) -> Float {
  let m = mag.reinterpret_as_uint() & 0x7fff_ffffU
  let s = sign.reinterpret_as_uint() & 0x8000_0000U
  Float::reinterpret_from_uint(m | s)
}

///|
let log2f_invc : FixedArray[Double] = [
  0x1.661ec79f8f3bep+0, 0x1.571ed4aaf883dp+0, 0x1.49539f0f010b0p+0, 0x1.3c995b0b80385p+0,
  0x1.30d190c8864a5p+0, 0x1.25e227b0b8ea0p+0, 0x1.1bb4a4a1a343fp+0, 0x1.12358f08ae5bap+0,
  0x1.0953f419900a7p+0, 0x1.0000000000000p+0, 0x1.e608cfd9a47acp-1, 0x1.ca4b31f026aa0p-1,
  0x1.b2036576afce6p-1, 0x1.9c2d163a1aa2dp-1, 0x1.886e6037841edp-1, 0x1.767dcf5534862p-1,
]

///|
let log2f_logc : FixedArray[Double] = [
  -0x1.efec65b963019p-2, -0x1.b0b6832d4fca4p-2, -0x1.7418b0a1fb77bp-2, -0x1.39de91a6dcf7bp-2,
  -0x1.01d9bf3f2b631p-2, -0x1.97c1d1b3b7af0p-3, -0x1.2f9e393af3c9fp-3, -0x1.960cbbf788d5cp-4,
  -0x1.a6f9db6475fcep-5, 0.0, 0x1.338ca9f24f53dp-4, 0x1.476a9543891bap-3, 0x1.e840b4ac4e4d2p-3,
  0x1.40645f0c6651cp-2, 0x1.88e9c2c1b9ff8p-2, 0x1.ce0a44eb17bccp-2,
]

///|
let log2f_poly : FixedArray[Double] = [
  -0x1.712b6f70a7e4dp-2, 0x1.ecabf496832e0p-2, -0x1.715479ffae3dep-1, 0x1.715475f35c8b8p+0,
]

///|
/// `f32::log2`: glibc's `log2f` (sysdeps/ieee754/flt-32/e_log2f.c), FMA
/// variant as selected by glibc on x86_64 CPUs with FMA. Tables are those of
/// `__log2f_data`.
fn log2_f32(x : Float) -> Float {
  let mut ix = x.reinterpret_as_uint()
  // Fix sign of zero with downward rounding when x==1.
  if ix == 0x3f800000U {
    return 0.0
  }
  if ix - 0x00800000U >= 0x7f800000U - 0x00800000U {
    // x < 0x1p-126 or inf or nan.
    if ix * 2 == 0 {
      return Float::reinterpret_from_uint(0xff800000U) // __math_divzerof(1)
    }
    if ix == 0x7f800000U {
      return x // log2(inf) == inf.
    }
    if (ix & 0x80000000U) != 0 || ix * 2 >= 0xff000000U {
      return (x - x) / (x - x) // __math_invalidf
    }
    // x is subnormal, normalize it.
    ix = (x * 8388608.0).reinterpret_as_uint()
    ix = ix - (23U << 23)
  }
  let tmp = ix - 0x3f330000U
  let i = ((tmp >> 19) % 16U).reinterpret_as_int()
  let top = tmp & 0xff800000U
  let iz = ix - top
  let k = tmp.reinterpret_as_int() >> 23 // arithmetic shift
  let invc = log2f_invc[i]
  let logc = log2f_logc[i]
  let z = Float::reinterpret_from_uint(iz).to_double()
  // log2(x) = log1p(z/c-1)/ln2 + log2(c) + k
  let r = mul_add_f64(z, invc, -1.0)
  let y0 = logc + k.to_double()
  // Pipelined polynomial evaluation to approximate log1p(r)/ln2.
  let r2 = r * r
  let a = log2f_poly
  let y = mul_add_f64(a[1], r, a[2])
  let y = mul_add_f64(a[0], r2, y)
  let p = mul_add_f64(a[3], r, y0)
  Float::from_double(mul_add_f64(y, r2, p))
}

// ---------------------------------------------------------------------------
// x86_64 SIMD lane semantics.
//
// Upstream picks a SIMD code path at run time (`is_x86_feature_detected!`).
// This port reproduces, lane by lane in scalar code, the path taken on an
// x86_64 CPU with AVX2 + FMA (the reference machine), including which samples
// go through the 8-wide, 4-wide and scalar remainder code. The helpers below
// give the exact semantics of the intrinsics used.

///|
/// `_mm_max_ps(a, b)` / `_mm256_max_ps`: `a > b ? a : b` (returns `b` when
/// either operand is NaN).
fn max_ps(a : Float, b : Float) -> Float {
  if a > b {
    a
  } else {
    b
  }
}

///|
/// `_mm_min_ps(a, b)` / `_mm256_min_ps`: `a < b ? a : b`.
fn min_ps(a : Float, b : Float) -> Float {
  if a < b {
    a
  } else {
    b
  }
}

///|
/// `_mm_cvtps_epi32` on an integral value: out-of-range and NaN give
/// `i32::MIN` (the "integer indefinite" value).
fn cvtps_epi32_integral(x : Float) -> Int32 {
  if x != x || x >= 2147483648.0 || x < -2147483648.0 {
    -2147483648
  } else {
    x.to_int()
  }
}

///|
/// Sign bit of `v` OR-ed into `|r|` (`_mm_or_ps(_mm_andnot_ps(sign_mask, r), sign)`).
fn or_sign(r : Float, v : Float) -> Float {
  Float::reinterpret_from_uint(
    (r.reinterpret_as_uint() & 0x7fff_ffffU) |
    (v.reinterpret_as_uint() & 0x8000_0000U),
  )
}
