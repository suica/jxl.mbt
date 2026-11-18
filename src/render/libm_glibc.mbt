// `f32::cos` and `f32::powf` as upstream computes them.
//
// jxl-oxide calls the C library's `cosf`/`powf` (Rust lowers `f32::cos` and
// `f32::powf` to them). The upstream binary runs on x86_64 Linux, where glibc
// (2.27+) selects, through an ifunc, its FMA build of the ARM
// optimized-routines code on CPUs with FMA and AVX2: sysdeps/ieee754/flt-32/
// s_cosf.c, s_sincosf.h, sincosf_poly.h, s_sincosf_data.c, e_powf.c,
// e_powf_log2_data.c and e_exp2f_data.c compiled with `-mfma -mavx2`, where
// GCC contracts every `a * b + c` into a fused multiply-add. This is a port
// of that code with the contractions written out as `glibc_fma`. It was
// checked bit for bit against glibc 2.35's `cosf` on every float in
// [0, 120) and against `powf(x, 0.25)` on every positive finite float.
//
// MoonBit has no fused multiply-add, so `glibc_fma` is a port of musl's
// software `fma` (src/math/fma.c), correctly rounded like the hardware
// instruction.

///|
priv struct GlibcFmaNum {
  m : UInt64
  e : Int32
  sign : Int32
}

///|
fn glibc_fma_normalize(x : Double) -> GlibcFmaNum {
  let mut ix = x.reinterpret_as_uint64()
  let mut e = (ix >> 52).to_int()
  let sign = e & 0x800
  e = e & 0x7ff
  if e == 0 {
    ix = (x * 0x1.0p63).reinterpret_as_uint64()
    e = (ix >> 52).to_int() & 0x7ff
    e = if e != 0 { e - 63 } else { 0x800 }
  }
  ix = ix & ((1UL << 52) - 1UL)
  ix = ix | (1UL << 52)
  ix = ix << 1
  e = e - (0x3ff + 52 + 1)
  { m: ix, e, sign, }
}

///|
/// `fma(x, y, z)`: `x * y + z` rounded once (musl src/math/fma.c).
fn glibc_fma(x : Double, y : Double, z : Double) -> Double {
  let zeroinfnan = 0x7ff - 0x3ff - 52 - 1
  // normalize so top 10bits and last bit are 0
  let nx = glibc_fma_normalize(x)
  let ny = glibc_fma_normalize(y)
  let nz = glibc_fma_normalize(z)
  if nx.e >= zeroinfnan || ny.e >= zeroinfnan {
    return x * y + z
  }
  if nz.e >= zeroinfnan {
    if nz.e > zeroinfnan {
      // z == 0
      return x * y
    }
    return z
  }

  // mul: r = x*y
  let xlo = nx.m & 0xffffffffUL
  let xhi = nx.m >> 32
  let ylo = ny.m & 0xffffffffUL
  let yhi = ny.m >> 32
  let t1 = xlo * ylo
  let t2 = xlo * yhi + xhi * ylo
  let t3 = xhi * yhi
  let mut rlo = t1 + (t2 << 32)
  let mut rhi = t3 + (t2 >> 32) + (if t1 > rlo { 1UL } else { 0UL })
  // either top 20 or 21 bits of rhi and last 2 bits of rlo are 0

  // align exponents
  let mut e = nx.e + ny.e
  let mut d = nz.e - e
  let mut zhi = 0UL
  let mut zlo = 0UL
  // shift bits z<<=kz, r>>=kr, so kz+kr == d, set e = e+kr (== ez-kz)
  if d > 0 {
    if d < 64 {
      zlo = nz.m << d
      zhi = nz.m >> (64 - d)
    } else {
      zlo = 0UL
      zhi = nz.m
      e = nz.e - 64
      d = d - 64
      if d == 0 {
        ()
      } else if d < 64 {
        rlo = (rhi << (64 - d)) |
          (rlo >> d) |
          (if rlo << (64 - d) != 0UL { 1UL } else { 0UL })
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
      zlo = (nz.m >> d) | (if nz.m << (64 - d) != 0UL { 1UL } else { 0UL })
    } else {
      zlo = 1UL
    }
  }

  // add
  let mut sign = nx.sign ^ ny.sign
  let samesign = (sign ^ nz.sign) == 0
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
      sign = if sign != 0 { 0 } else { 1 }
    }
    nonzero = rhi != 0UL
  }

  // set rhi to top 63bit of the result (last bit is sticky)
  if nonzero {
    e = e + 64
    d = rhi.clz() - 1
    // note: d > 0
    rhi = (rhi << d) |
      (rlo >> (64 - d)) |
      (if rlo << d != 0UL { 1UL } else { 0UL })
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
  e = e - d

  // convert to double
  let mut i = rhi.reinterpret_as_int64() // i is in [1<<62,(1<<63)-1]
  if sign != 0 {
    i = -i
  }
  let mut r = i.to_double() // |r| is in [0x1p62,0x1p63]
  if e < -1022 - 62 {
    // result is subnormal before rounding
    if e == -1022 - 63 {
      let c = if sign != 0 { -0x1.0p63 } else { 0x1.0p63 }
      if r == c {
        // min normal after rounding, underflow depends on arch behaviour
        // which can be imitated by a double to float conversion
        let flt_min : Float = 0x1.0p-126
        let fltmin = Float::from_double(
          0x0.ffffff8p-63 * flt_min.to_double() * r,
        )
        return 0x1.0p-1022 / flt_min.to_double() * fltmin.to_double()
      }
      // one bit is lost when scaled, add another top bit to only round
      // once at conversion if it is inexact
      if rhi << 53 != 0UL {
        i = ((rhi >> 1) | (rhi & 1UL) | (1UL << 62)).reinterpret_as_int64()
        if sign != 0 {
          i = -i
        }
        r = i.to_double()
        r = 2.0 * r - c // remove top bit
      }
    } else {
      // only round once when scaled
      let d = 10
      i = (((rhi >> d) | (if rhi << (64 - d) != 0UL { 1UL } else { 0UL })) << d).reinterpret_as_int64()
      if sign != 0 {
        i = -i
      }
      r = i.to_double()
    }
  }
  @math.scalbn(r, e)
}

///|
/// `sincos_t` of s_sincosf_data.c (`TOINT_INTRINSICS` is 0 on x86_64).
priv struct GlibcSincos {
  sign : FixedArray[Double]
  hpi_inv : Double
  hpi : Double
  c0 : Double
  c1 : Double
  c2 : Double
  c3 : Double
  c4 : Double
  s1 : Double
  s2 : Double
  s3 : Double
}

///|
/// `__sincosf_table`: the 2nd entry computes -cos (x) rather than cos (x).
let glibc_sincosf_table : FixedArray[GlibcSincos] = [
  {
    sign: [1.0, -1.0, -1.0, 1.0],
    hpi_inv: 0x1.45F306DC9C883p+23,
    hpi: 0x1.921FB54442D18p0,
    c0: 1.0,
    c1: -0x1.ffffffd0c621cp-2,
    c2: 0x1.55553e1068f19p-5,
    c3: -0x1.6c087e89a359dp-10,
    c4: 0x1.99343027bf8c3p-16,
    s1: -0x1.555545995a603p-3,
    s2: 0x1.1107605230bc4p-7,
    s3: -0x1.994eb3774cf24p-13,
  },
  {
    sign: [1.0, -1.0, -1.0, 1.0],
    hpi_inv: 0x1.45F306DC9C883p+23,
    hpi: 0x1.921FB54442D18p0,
    c0: -1.0,
    c1: 0x1.ffffffd0c621cp-2,
    c2: -0x1.55553e1068f19p-5,
    c3: 0x1.6c087e89a359dp-10,
    c4: -0x1.99343027bf8c3p-16,
    s1: -0x1.555545995a603p-3,
    s2: 0x1.1107605230bc4p-7,
    s3: -0x1.994eb3774cf24p-13,
  },
]

///|
/// `__inv_pio4`: 4/PI to 192 bit precision, 8 new bits per entry.
let glibc_inv_pio4 : FixedArray[UInt32] = [
  0xa2, 0xa2f9, 0xa2f983, 0xa2f9836e, 0xf9836e4e, 0x836e4e44, 0x6e4e4415, 0x4e441529,
  0x441529fc, 0x1529fc27, 0x29fc2757, 0xfc2757d1, 0x2757d1f5, 0x57d1f534, 0xd1f534dd,
  0xf534ddc0, 0x34ddc0db, 0xddc0db62, 0xc0db6295, 0xdb629599, 0x6295993c, 0x95993c43,
  0x993c4390, 0x3c439041,
]

///|
/// Top 12 bits of the float representation with the sign bit cleared.
fn glibc_abstop12(x : Float) -> UInt32 {
  (x.reinterpret_as_uint() >> 20) & 0x7ff
}

///|
/// `sinf_poly`: the sine of X (X2 = X squared) with polynomial `p`; if `n`
/// is odd the cosine polynomial is used.
fn glibc_sinf_poly(
  x : Double,
  x2 : Double,
  p : GlibcSincos,
  n : Int32,
) -> Float {
  if (n & 1) == 0 {
    let x3 = x * x2
    let s1 = glibc_fma(x2, p.s3, p.s2)
    let x7 = x3 * x2
    let s = glibc_fma(x3, p.s1, x)
    Float::from_double(glibc_fma(x7, s1, s))
  } else {
    let x4 = x2 * x2
    let c2 = glibc_fma(x2, p.c4, p.c3)
    let c1 = glibc_fma(x2, p.c1, p.c0)
    let x6 = x4 * x2
    let c = glibc_fma(x4, p.c2, c1)
    Float::from_double(glibc_fma(x6, c2, c))
  }
}

///|
/// `reduce_large`: reduces XI (a reinterpreted float >= 2.0f, sign ignored)
/// to a multiple of PI/2; returns the modulo in [-PI/4, PI/4] and the
/// quadrant.
fn glibc_reduce_large(xi : UInt32) -> (Double, Int32) {
  let pi63 = 0x1.921FB54442D18p-62
  let base = ((xi >> 26) & 15).reinterpret_as_int()
  let shift = ((xi >> 23) & 7).reinterpret_as_int()
  let xi = ((xi & 0xffffff) | 0x800000) << shift
  let mut res0 = (xi * glibc_inv_pio4[base]).to_uint64()
  let res1 = xi.to_uint64() * glibc_inv_pio4[base + 4].to_uint64()
  let res2 = xi.to_uint64() * glibc_inv_pio4[base + 8].to_uint64()
  res0 = (res2 >> 32) | (res0 << 32)
  res0 = res0 + res1
  let n = (res0 + (1UL << 61)) >> 62
  res0 = res0 - (n << 62)
  let x = res0.reinterpret_as_int64().to_double()
  (x * pi63, n.to_int())
}

///|
/// glibc `cosf` (s_cosf.c, FMA build).
fn glibc_cosf(y : Float) -> Float {
  let x = y.to_double()
  let p = glibc_sincosf_table[0]
  let pio4 : Float = 0x1.921FB6p-1
  if glibc_abstop12(y) < glibc_abstop12(pio4) {
    let x2 = x * x
    if glibc_abstop12(y) < glibc_abstop12(0x1.0p-12) {
      return 1.0
    }
    glibc_sinf_poly(x, x2, p, 1)
  } else if glibc_abstop12(y) < glibc_abstop12(120.0) {
    // reduce_fast
    let r = x * p.hpi_inv
    let n = (r.to_int() + 0x800000) >> 24
    let x = glibc_fma(-n.to_double(), p.hpi, x)
    // Setup the signs for sin and cos.
    let s = p.sign[n & 3]
    let p = if (n & 2) != 0 { glibc_sincosf_table[1] } else { p }
    glibc_sinf_poly(x * s, x * x, p, n ^ 1)
  } else if glibc_abstop12(y) < glibc_abstop12(@float.infinity) {
    let xi = y.reinterpret_as_uint()
    let sign = (xi >> 31).reinterpret_as_int()
    let (x, n) = glibc_reduce_large(xi)
    // Setup signs for sin and cos - include original sign.
    let s = p.sign[(n + sign) & 3]
    let p = if ((n + sign) & 2) != 0 { glibc_sincosf_table[1] } else { p }
    glibc_sinf_poly(x * s, x * x, p, n ^ 1)
  } else {
    // __math_invalidf
    (y - y) / (y - y)
  }
}

///|
/// `__powf_log2_data.tab` as (invc, logc) pairs (POWF_SCALE is 1).
let glibc_powf_log2_tab : FixedArray[Double] = [
  0x1.661ec79f8f3bep+0, -0x1.efec65b963019p-2, 0x1.571ed4aaf883dp+0, -0x1.b0b6832d4fca4p-2,
  0x1.49539f0f010bp+0, -0x1.7418b0a1fb77bp-2, 0x1.3c995b0b80385p+0, -0x1.39de91a6dcf7bp-2,
  0x1.30d190c8864a5p+0, -0x1.01d9bf3f2b631p-2, 0x1.25e227b0b8eap+0, -0x1.97c1d1b3b7afp-3,
  0x1.1bb4a4a1a343fp+0, -0x1.2f9e393af3c9fp-3, 0x1.12358f08ae5bap+0, -0x1.960cbbf788d5cp-4,
  0x1.0953f419900a7p+0, -0x1.a6f9db6475fcep-5, 1.0, 0.0, 0x1.e608cfd9a47acp-1, 0x1.338ca9f24f53dp-4,
  0x1.ca4b31f026aap-1, 0x1.476a9543891bap-3, 0x1.b2036576afce6p-1, 0x1.e840b4ac4e4d2p-3,
  0x1.9c2d163a1aa2dp-1, 0x1.40645f0c6651cp-2, 0x1.886e6037841edp-1, 0x1.88e9c2c1b9ff8p-2,
  0x1.767dcf5534862p-1, 0x1.ce0a44eb17bccp-2,
]

///|
let glibc_powf_log2_poly : FixedArray[Double] = [
  0x1.27616c9496e0bp-2, -0x1.71969a075c67ap-2, 0x1.ec70a6ca7baddp-2, -0x1.7154748bef6c8p-1,
  0x1.71547652ab82bp0,
]

///|
/// `__exp2f_data.tab`: uint(2^(i/N)) - (i << 52-BITS).
let glibc_exp2f_tab : FixedArray[UInt64] = [
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
let glibc_exp2f_poly : FixedArray[Double] = [
  0x1.c6af84b912394p-5, 0x1.ebfce50fac4f3p-3, 0x1.62e42ff0c52d6p-1,
]

///|
/// `log2_inline` of e_powf.c.
fn glibc_powf_log2_inline(ix : UInt32) -> Double {
  let off = 0x3f330000U
  // x = 2^k z; where z is in range [OFF,2*OFF] and exact.
  let tmp = ix - off
  let i = ((tmp >> (23 - 4)) % 16).reinterpret_as_int()
  let top = tmp & 0xff800000
  let iz = ix - top
  let k = top.reinterpret_as_int() >> 23 // arithmetic shift
  let invc = glibc_powf_log2_tab[2 * i]
  let logc = glibc_powf_log2_tab[2 * i + 1]
  let z = Float::reinterpret_from_uint(iz).to_double()
  let a = glibc_powf_log2_poly
  // log2(x) = log1p(z/c-1)/ln2 + log2(c) + k
  let r = glibc_fma(z, invc, -1.0)
  let y0 = logc + k.to_double()
  // Pipelined polynomial evaluation to approximate log1p(r)/ln2.
  let r2 = r * r
  let y = glibc_fma(a[0], r, a[1])
  let p = glibc_fma(a[2], r, a[3])
  let r4 = r2 * r2
  let q = glibc_fma(a[4], r, y0)
  let q = glibc_fma(p, r2, q)
  glibc_fma(y, r4, q)
}

///|
/// `exp2_inline` of e_powf.c (TOINT_INTRINSICS is 0).
fn glibc_powf_exp2_inline(xd : Double, sign_bias : UInt64) -> Double {
  let shift = 0x1.8p+52 / 32.0
  // x = k/N + r with r in [-1/(2N), 1/(2N)]
  let kd = xd + shift // Rounding to double precision is required.
  let ki = kd.reinterpret_as_uint64()
  let kd = kd - shift // k/N
  let r = xd - kd
  // exp2(x) = 2^(k/N) * 2^r ~= s * (C0*r^3 + C1*r^2 + C2*r + 1)
  let mut t = glibc_exp2f_tab[(ki % 32UL).to_int()]
  let ski = ki + sign_bias
  t = t + (ski << (52 - 5))
  let s = t.reinterpret_as_double()
  let c = glibc_exp2f_poly
  let z = glibc_fma(c[0], r, c[1])
  let r2 = r * r
  let y = glibc_fma(c[2], r, 1.0)
  let y = glibc_fma(z, r2, y)
  y * s
}

///|
/// Returns 0 if not int, 1 if odd int, 2 if even int. The argument is the
/// bit representation of a non-zero finite floating-point value.
fn glibc_powf_checkint(iy : UInt32) -> Int32 {
  let e = ((iy >> 23) & 0xff).reinterpret_as_int()
  if e < 0x7f {
    return 0
  }
  if e > 0x7f + 23 {
    return 2
  }
  if (iy & ((1U << (0x7f + 23 - e)) - 1)) != 0 {
    return 0
  }
  if (iy & (1U << (0x7f + 23 - e))) != 0 {
    return 1
  }
  2
}

///|
fn glibc_zeroinfnan(ix : UInt32) -> Bool {
  2U * ix - 1U >= 2U * 0x7f800000U - 1U
}

///|
fn glibc_issignalingf(x : Float) -> Bool {
  let ix = x.reinterpret_as_uint()
  2U * (ix ^ 0x00400000) > 2U * 0x7fc00000U
}

///|
/// `__math_xflowf`.
fn glibc_xflowf(sign : Bool, y : Float) -> Float {
  (if sign { -y } else { y }) * y
}

///|
/// glibc `powf` (e_powf.c, FMA build).
fn glibc_powf(x : Float, y : Float) -> Float {
  let mut sign_bias = 0UL
  let mut ix = x.reinterpret_as_uint()
  let iy = y.reinterpret_as_uint()
  if ix - 0x00800000U >= 0x7f800000U - 0x00800000U || glibc_zeroinfnan(iy) {
    // Either (x < 0x1p-126 or inf or nan) or (y is 0 or inf or nan).
    if glibc_zeroinfnan(iy) {
      if 2U * iy == 0U {
        return if glibc_issignalingf(x) { x + y } else { 1.0 }
      }
      if ix == 0x3f800000U {
        return if glibc_issignalingf(y) { x + y } else { 1.0 }
      }
      if 2U * ix > 2U * 0x7f800000U || 2U * iy > 2U * 0x7f800000U {
        return x + y
      }
      if 2U * ix == 2U * 0x3f800000U {
        return 1.0
      }
      if (2U * ix < 2U * 0x3f800000U) == ((iy & 0x80000000U) == 0U) {
        return 0.0 // |x|<1 && y==inf or |x|>1 && y==-inf.
      }
      return y * y
    }
    if glibc_zeroinfnan(ix) {
      let mut x2 = x * x
      let mut neg = false
      if (ix & 0x80000000U) != 0U && glibc_powf_checkint(iy) == 1 {
        x2 = -x2
        neg = true
      }
      if 2U * ix == 0U && (iy & 0x80000000U) != 0U {
        // __math_divzerof
        return (if neg { -1.0 } else { 1.0 } : Float) / 0.0
      }
      return if (iy & 0x80000000U) != 0U { 1.0 / x2 } else { x2 }
    }
    // x and y are non-zero finite.
    if (ix & 0x80000000U) != 0U {
      // Finite x < 0.
      let yint = glibc_powf_checkint(iy)
      if yint == 0 {
        // __math_invalidf
        return (x - x) / (x - x)
      }
      if yint == 1 {
        sign_bias = 1UL << (5 + 11)
      }
      ix = ix & 0x7fffffffU
    }
    if ix < 0x00800000U {
      // Normalize subnormal x so exponent becomes negative.
      let scale : Float = 0x1.0p23
      ix = (x * scale).reinterpret_as_uint()
      ix = ix & 0x7fffffffU
      ix = ix - (23U << 23)
    }
  }
  let logx = glibc_powf_log2_inline(ix)
  let ylogx = y.to_double() * logx // Note: cannot overflow, y is single prec.
  let neg = sign_bias != 0UL
  if ((ylogx.reinterpret_as_uint64() >> 47) & 0xffffUL) >=
    (126.0 : Double).reinterpret_as_uint64() >> 47 {
    // |y*log(x)| >= 126.
    if ylogx > 0x1.fffffffd1d571p+6 {
      // |x^y| > 0x1.ffffffp127. (__math_oflowf)
      return glibc_xflowf(neg, 0x1.0p97)
    }
    // (the round-away-from-zero check only matters outside round-to-nearest)
    if ylogx <= -150.0 {
      // __math_uflowf
      return glibc_xflowf(neg, 0x1.0p-95)
    }
    if ylogx < -149.0 {
      // __math_may_uflowf
      return glibc_xflowf(neg, 0x1.4p-75)
    }
  }
  Float::from_double(glibc_powf_exp2_inline(ylogx, sign_bias))
}
