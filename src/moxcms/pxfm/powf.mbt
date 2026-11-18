// Ported from pxfm 0.1.30 (https://github.com/awxkee/pxfm),
// Copyright (c) Radzivon Bartoshyk. All rights reserved.
// BSD-3-Clause OR Apache-2.0 (see upstream LICENSE.md / LICENSE-APACHE.md).
//
// Port of `powf.rs` (`f_powf`, `dirty_powf`) with `dirty_log2f`
// (`logs/log2f.rs`) and `dirty_exp2f` (`exponents/exp2f.rs`).
//
// `f_powf` chooses at run time between `GenPowfBackend` and `FmaPowfBackend`
// on x86_64; the `fma` flag selects the backend and the public function uses
// `FmaPowfBackend` (x86_64 CPUs with AVX and FMA). `GenPowfBackend` is the
// not-fma build: `HAS_FMA = false`, `ERR = 128`.

///|
fn pbe_fma(fma : Bool, x : Double, y : Double, z : Double) -> Double {
  if fma {
    fma_f64(x, y, z)
  } else {
    f_fmla(x, y, z)
  }
}

///|
fn pbe_polyeval3(
  fma : Bool,
  x : Double,
  a0 : Double,
  a1 : Double,
  a2 : Double,
) -> Double {
  if fma {
    d_polyeval3(x, a0, a1, a2)
  } else {
    f_polyeval3(x, a0, a1, a2)
  }
}

///|
fn pbe_integerf(fma : Bool, x : Float) -> Bool {
  if fma {
    round_ties_even_f32(x) == x
  } else {
    is_integerf(x)
  }
}

///|
fn pbe_quick_mult_f64(fma : Bool, x : DoubleDouble, y : Double) -> DoubleDouble {
  if fma {
    DoubleDouble::quick_mult_f64_fma(x, y)
  } else {
    DoubleDouble::quick_mult_f64(x, y)
  }
}

///|
/// `larger_exponent`.
fn larger_exponent(a : Double, b : Double) -> Bool {
  biased_exponent_f64(a) >= biased_exponent_f64(b)
}

///|
let powf_dd_coeffs : FixedArray[UInt64] = [
  0x3c7777d0ffda25e0UL, 0x3ff71547652b82feUL, 0xbc6777d101cf0a84UL, 0xbfe71547652b82feUL,
  0x3c7ce04b5140d867UL, 0x3fdec709dc3a03fdUL, 0x3c7137b47e635be5UL, 0xbfd71547652b82fbUL,
  0xbc5b5a30b3bdb318UL, 0x3fd2776c516a92a2UL, 0x3c62d2fbd081e657UL, 0xbfcec70af1929ca6UL,
]

///|
let powf_dd_exp2_coeffs : FixedArray[DoubleDouble] = {
  let c : FixedArray[UInt64] = [
    0x0000000000000000UL, 0x3ff0000000000000UL, 0x3c1abc9e3b398024UL, 0x3f862e42fefa39efUL,
    0xbba5e43a5429bddbUL, 0x3f0ebfbdff82c58fUL, 0xbb2d33162491268fUL, 0x3e8c6b08d704a0c0UL,
    0x3a94fb32d240a14eUL, 0x3e03b2ab6fba4e77UL, 0x39ee84e916be83e0UL, 0x3d75d87fe78a6731UL,
    0xb989a447bfddc5e6UL, 0x3ce430912f86bfb8UL, 0xb8e31a55719de47fUL, 0x3c4ffcbfc588ded9UL,
    0xb850ba57164eb36bUL, 0x3bb62c034beb8339UL, 0xb7b8483eabd9642dUL, 0x3b1b5251ff97bee1UL,
  ]
  FixedArray::makei(10, fn(i) { DoubleDouble::from_table(c, i) })
}

///|
/// Calculate 2^(y * log2(x)) in double-double precision.
/// At this point we can reuse the following values:
///   idx_x: index for extra precision of log2 for the middle part of log2(x).
///   dx: the reduced argument for log2(x)
///   y6: 2^6 * y.
///   lo6_hi: the high part of 2^6 * (y - (hi + mid))
///   exp2_hi_mid: high part of 2^(hi + mid)
fn powf_dd(
  idx_x : Int32,
  dx : Double,
  y6 : Double,
  lo6_hi : Double,
  exp2_hi_mid : DoubleDouble,
  fma : Bool,
) -> Double {
  // Perform a second range reduction step:
  //   idx2 = round(2^14 * (dx  + 2^-8)) = round ( dx * 2^14 + 2^6)
  //   dx2 = (1 + dx) * r2 - 1
  // Output range:
  //   -0x1.3ffcp-15 <= dx2 <= 0x1.3e3dp-15
  // `as usize`: saturating, negative values and NaN give 0
  let idx2_f = round_f64(
    pbe_fma(fma, dx, fb(0x40d0000000000000UL), fb(0x4050000000000000UL)),
  )
  let idx2 = if idx2_f > 0.0 { idx2_f.to_int() } else { 0 }
  let dx2 = pbe_fma(fma, 1.0 + dx, fb(powf_r2[idx2]), -1.0) // Exact
  let c = powf_dd_coeffs
  let dx_dd = DoubleDouble::new(0.0, dx2)
  let p = dd_quick_polyeval6(
    dx_dd,
    DoubleDouble::from_table(c, 0),
    DoubleDouble::from_table(c, 1),
    DoubleDouble::from_table(c, 2),
    DoubleDouble::from_table(c, 3),
    DoubleDouble::from_table(c, 4),
    DoubleDouble::from_table(c, 5),
    fma,
  )
  // log2(1 + dx2) ~ dx2 * P(dx2)
  let log2_x_lo = pbe_quick_mult_f64(fma, p, dx2)
  // Lower parts of (e_x - log2(r1)) of the first range reduction constant
  let log2_x_mid = DoubleDouble::new(
    fb(log2_r_td[3 * idx_x]),
    fb(log2_r_td[3 * idx_x + 1]),
  )
  // -log2(r2) + lower part of (e_x - log2(r1))
  let log2_x_m = DoubleDouble::add(
    DoubleDouble::from_table(log2_r2_dd, idx2),
    log2_x_mid,
  )
  // log2(1 + dx2) - log2(r2) + lower part of (e_x - log2(r1))
  // Since we don't know which one has larger exponent to apply Fast2Sum
  // algorithm, we need to check them before calling double-double addition.
  let log2_x = if larger_exponent(log2_x_m.hi, log2_x_lo.hi) {
    DoubleDouble::add(log2_x_m, log2_x_lo)
  } else {
    DoubleDouble::add(log2_x_lo, log2_x_m)
  }
  let lo6_hi_dd = DoubleDouble::new(0.0, lo6_hi)
  // 2^6 * y * (log2(1 + dx2) - log2(r2) + lower part of (e_x - log2(r1)))
  let prod = pbe_quick_mult_f64(fma, log2_x, y6)
  // 2^6 * (y * log2(x) - (hi + mid)) = 2^6 * lo
  let lo6 = if larger_exponent(prod.hi, lo6_hi) {
    DoubleDouble::add(prod, lo6_hi_dd)
  } else {
    DoubleDouble::add(lo6_hi_dd, prod)
  }
  let pp = dd_quick_polyeval10(lo6, powf_dd_exp2_coeffs, fma)
  let rr = be_quick_mult(fma, exp2_hi_mid, pp)
  // Make sure the sum is normalized:
  let r = DoubleDouble::from_exact_add(rr.hi, rr.lo)
  let fraction_mask = (1UL << 52) - 1UL
  let mut r_bits = tb(r.hi)
  if (r_bits & 0xfff_ffffUL) == 0UL && r.lo != 0.0 {
    let hi_sign = tb(r.hi) >> 63
    let lo_sign = tb(r.lo) >> 63
    if hi_sign == lo_sign {
      r_bits = r_bits + 1UL
    } else if (r_bits & fraction_mask) > 0UL {
      r_bits = r_bits - 1UL
    }
  }
  fb(r_bits)
}

///|
/// `powf_gen::<B>`; `fma` selects `FmaPowfBackend` over `GenPowfBackend`.
fn powf_gen(x : Float, y : Float, fma : Bool) -> Float {
  let mut x_u = tbf(x)
  let x_abs = x_u & 0x7fff_ffffU
  let mut y = y
  let y_u = tbf(y)
  let y_abs = y_u & 0x7fff_ffffU
  let mut x = x
  if (y_abs & 0x0007_ffffU) == 0U || y_abs > 0x4f170000U {
    // y is signaling NaN
    if x != x || y != y {
      if fbf(y_abs) == 0.0 {
        return 1.0
      }
      if x == 1.0 {
        return 1.0
      }
      return nan_f32
    }
    // Exceptional exponents.
    if y == 0.0 {
      return 1.0
    }
    match y_abs {
      0x7f80_0000U => {
        if x_abs > 0x7f80_0000U {
          // pow(NaN, +-Inf) = NaN
          return x
        }
        if x_abs == 0x3f80_0000U {
          // pow(+-1, +-Inf) = 1.0f
          return 1.0
        }
        if x == 0.0 && y_u == 0xff80_0000U {
          // pow(+-0, -Inf) = +inf and raise FE_DIVBYZERO
          return inf_f32
        }
        // pow (|x| < 1, -inf) = +inf
        // pow (|x| < 1, +inf) = 0.0f
        // pow (|x| > 1, -inf) = 0.0f
        // pow (|x| > 1, +inf) = +inf
        return if (x_abs < 0x3f80_0000U) == (y_u == 0xff80_0000U) {
          inf_f32
        } else {
          0.0
        }
      }
      _ =>
        match y_u {
          0x3f00_0000U => {
            // pow(x, 1/2) = sqrt(x)
            if x == 0.0 || x_u == 0xff80_0000U {
              // pow(-0, 1/2) = +0
              // pow(-inf, 1/2) = +inf
              // Make sure it is correct for FTZ/DAZ.
              return x * x
            }
            let r = x.sqrt()
            return if tbf(r) != 0x8000_0000U { r } else { 0.0 }
          }
          0x3f80_0000U => return x // y = 1.0f
          0x4000_0000U => return x * x // y = 2.0f
          _ => {
            let is_int = pbe_integerf(fma, y)
            if is_int && y_u > 0x4000_0000U && y_u <= 0x41c0_0000U {
              // Check for exact cases when 2 < y < 25 and y is an integer.
              let mut msb = if x_abs == 0U { 32 - 2 } else { x_abs.clz() }
              msb = if msb > 8 { msb } else { 8 }
              let mut lsb = if x_abs == 0U { 0 } else { x_abs.ctz() }
              lsb = if lsb > 23 { 23 } else { lsb }
              let extra_bits = 32 - 2 - lsb - msb
              let iter = y.to_int()
              if extra_bits * iter <= 23 + 2 {
                // The result is either exact or exactly half-way.
                // But it is exactly representable in double precision.
                let x_d = x.to_double()
                let mut result = x_d
                for _ in 1..<iter {
                  result = result * x_d
                }
                return Float::from_double(result)
              }
            }
            if y_abs > 0x4f17_0000U {
              // if y is NaN
              if y_abs > 0x7f80_0000U {
                if x_u == 0x3f80_0000U {
                  // x = 1.0f
                  // pow(1, NaN) = 1
                  return 1.0
                }
                // pow(x, NaN) = NaN
                return y
              }
              // x^y will be overflow / underflow in single precision.  Set y to a
              // large enough exponent but not too large, so that the computations
              // won't be overflow in double precision.
              y = fbf((y_u & 0x8000_0000U) + 0x4f800000U)
            }
          }
        }
    }
  }
  let mut ex = -127
  let mut sign = 0UL
  if (x_u & 0x801f_ffffU) == 0U || x_u >= 0x7f80_0000U || x_u < 0x0080_0000U {
    if x != x {
      return nan_f32
    }
    if x_u == 0x3f80_0000U {
      return 1.0
    }
    let x_is_neg = tbf(x) > 0x8000_0000U
    if x == 0.0 {
      let out_is_neg = x_is_neg && is_odd_integerf(fbf(y_u))
      if y_u > 0x8000_0000U {
        // pow(0, negative number) = inf
        return if x_is_neg { -inf_f32 } else { inf_f32 }
      }
      // pow(0, positive number) = 0
      return if out_is_neg { -0.0 } else { 0.0 }
    }
    if x_abs == 0x7f80_0000U {
      // x = +-Inf
      let out_is_neg = x_is_neg && is_odd_integerf(fbf(y_u))
      if y_u >= 0x7fff_ffffU {
        return if out_is_neg { -0.0 } else { 0.0 }
      }
      return if out_is_neg { -inf_f32 } else { inf_f32 }
    }
    if x_abs > 0x7f80_0000U {
      // x is NaN.
      // pow (aNaN, 0) is already taken care above.
      return x
    }
    // Normalize denormal inputs.
    if x_abs < 0x0080_0000U {
      ex = ex - 64
      x = x * fbf(0x5f800000U)
    }
    // x is finite and negative, and y is a finite integer.
    if tbf(x) >> 31 != 0U {
      if pbe_integerf(fma, y) {
        x = -x
        if is_odd_integerf(y) {
          sign = 0x8000_0000_0000_0000UL
        }
      } else {
        // pow( negative, non-integer ) = NaN
        return nan_f32
      }
    }
  }
  // x^y = 2^( y * log2(x) )
  //     = 2^( y * ( e_x + log2(m_x) ) )
  // First we compute log2(x) = e_x + log2(m_x)
  x_u = tbf(x)
  // Extract exponent field of x.
  ex = ex + (x_u >> 23).reinterpret_as_int()
  let e_x = ex.to_double()
  // Use the highest 7 fractional bits of m_x as the index for look up tables.
  let x_mant = x_u & ((1U << 23) - 1U)
  let idx_x = (x_mant >> (23 - 7)).reinterpret_as_int()
  // Add the hidden bit to the mantissa.
  // 1 <= m_x < 2
  let m_x = fbf(x_mant | 0x3f800000U)
  // Reduced argument for log2(m_x):
  //   dx = r * m_x - 1.
  // The computation is exact, and -2^-8 <= dx < 2^-7.
  let dx = if fma {
    fmaf_f32(m_x, fbf(log_reduction_f32[idx_x]), -1.0).to_double() // Exact.
  } else {
    f_fmla(m_x.to_double(), fb(log_range_reduction_table[idx_x]), -1.0) // Exact
  }
  // Degree-5 polynomial approximation:
  //   dx * P(dx) ~ log2(1 + dx)
  let dx2 = dx * dx // Exact
  let c0 = pbe_fma(fma, dx, fb(0xbfe71547652b7a07UL), fb(0x3ff71547652b82feUL))
  let c1 = pbe_fma(fma, dx, fb(0xbfd715479c2266c9UL), fb(0x3fdec709dc458db1UL))
  let c2 = pbe_fma(fma, dx, fb(0xbfce7b2178870157UL), fb(0x3fd2776ae1ddf8f0UL))
  let p = pbe_polyeval3(fma, dx2, c0, c1, c2)
  // s = e_x - log2(r) + dx * P(dx)
  let s = pbe_fma(fma, dx, p, fb(log2_r[idx_x]) + e_x)
  // In the following computations:
  //   y6  = 2^6 * y
  //   hm  = 2^6 * (hi + mid) = round(2^6 * y * log2(x)) ~ round(y6 * s)
  //   lo6 = 2^6 * lo = 2^6 * (y - (hi + mid)) = y6 * log2(x) - hm.
  let y6 = (y * fbf(0x42800000U)).to_double() // Exact.
  let hm = round_f64(s * y6)
  // lo6 = 2^6 * lo.
  let lo6_hi = pbe_fma(fma, y6, e_x + fb(log2_r_td[3 * idx_x + 2]), -hm) // Exact
  // Error bounds:
  //   | (y*log2(x) - hm * 2^-6 - lo) / y| < err(dx * p) + err(LOG2_R_DD.lo)
  //                                       < 2^-51 + 2^-75
  let lo6 = pbe_fma(
    fma,
    y6,
    pbe_fma(fma, dx, p, fb(log2_r_td[3 * idx_x + 1])),
    lo6_hi,
  )
  // |2^(hi + mid) - exp2_hi_mid| <= ulp(exp2_hi_mid) / 2
  // Clamp the exponent part into smaller range that fits double precision.
  let mut hm_i = to_int_unchecked_i64(hm)
  hm_i = if hm_i > 1L << 15 {
    1L << 15
  } else if hm_i < -(1L << 15) {
    -(1L << 15)
  } else {
    hm_i
  }
  let idx_y = (hm_i & 0x3fL).to_int()
  // 2^hi
  let exp_hi_i = hm_i >> 6 << 52
  // 2^mid
  let exp_mid_i = exp2_mid1[2 * idx_y + 1]
  // (-1)^sign * 2^hi * 2^mid
  // Error <= 2^hi * 2^-53
  let exp2_hi_mid_i = (exp_hi_i + exp_mid_i.reinterpret_as_int64()).reinterpret_as_uint64() +
    sign
  let exp2_hi_mid = fb(exp2_hi_mid_i)
  // Degree-5 polynomial approximation P(lo6) ~ 2^(lo6 / 2^6) = 2^(lo).
  let lo6_sqr = lo6 * lo6
  let d0 = pbe_fma(fma, lo6, fb(0x3f862e42fefa39efUL), fb(0x3ff0000000000000UL))
  let d1 = pbe_fma(fma, lo6, fb(0x3e8c6b08d7076268UL), fb(0x3f0ebfbdff82a23aUL))
  let d2 = pbe_fma(fma, lo6, fb(0x3d75d870c4d84445UL), fb(0x3e03b2ad33f8b48bUL))
  let pp = pbe_polyeval3(fma, lo6_sqr, d0, d1, d2)
  let r = pp * exp2_hi_mid
  let r_u = tb(r)
  let err = if fma { 64UL } else { 128UL }
  let r_upper = Float::from_double(fb(r_u + err))
  let r_lower = Float::from_double(fb(r_u - err))
  if r_upper == r_lower {
    return r_upper
  }
  // Scale lower part of 2^(hi + mid)
  let exp2_hi_mid_dd = DoubleDouble::new(
    if idx_y != 0 {
      fb(exp_hi_i.reinterpret_as_uint64() + exp2_mid1[2 * idx_y])
    } else {
      0.0
    },
    exp2_hi_mid,
  )
  let r_dd = powf_dd(idx_x, dx, y6, lo6_hi, exp2_hi_mid_dd, fma)
  Float::from_double(r_dd)
}

///|
/// Power function.
///
/// Max found ULP 0.5. Port of pxfm `f_powf` with `FmaPowfBackend`, which is
/// what runs on x86_64 CPUs with AVX and FMA.
pub fn f_powf(x : Float, y : Float) -> Float {
  powf_gen(x, y, true)
}

///|
/// `dirty_log2f` (`logs/log2f.rs`; `f_fmlaf` is the unfused `a * b + c`).
fn dirty_log2f(d : Float) -> Float {
  let mut ix = tbf(d)
  // reduce x into [sqrt(2)/2, sqrt(2)]
  ix = ix + (0x3f800000U - 0x3f3504f3U)
  let n = (ix >> 23).reinterpret_as_int() - 0x7f
  ix = (ix & 0x007fffffU) + 0x3f3504f3U
  let a = fbf(ix)
  let x = (a - 1.0) / (a + 1.0)
  let x2 = x * x
  let mut u = fbf(0x3ed30bb1U) // 0.4121985850084821691e+0
  u = f_fmlaf(u, x2, fbf(0x3f13bb63U)) // 0.5770780163490337802e+0
  u = f_fmlaf(u, x2, fbf(0x3f76384fU)) // 0.9617966939259845749e+0
  f_fmlaf(
    x2 * x,
    u,
    f_fmlaf(x, fbf(0x4038aa3bU), Float::from_int(n)), // 0.2885390081777926802e+1
  )
}

///|
/// `dirty_exp2f` (`exponents/exp2f.rs`).
fn dirty_exp2f(d : Float) -> Float {
  let tblsize = 64U
  let redux = fbf(0x4b400000U) / Float::from_uint(tblsize)
  let ui = tbf(d + redux)
  let mut i0 = ui
  i0 = i0 + tblsize / 2U
  let k = i0 / tblsize
  i0 = i0 & (tblsize - 1U)
  let mut uf = fbf(ui)
  uf = uf - redux
  let z0 = fbf(exp2ft[2 * i0.reinterpret_as_int()])
  let f = d - uf
  let mut u = fbf(0x3e75fdf0U) // 0.24022650695908768
  u = f_fmlaf(u, f, fbf(0x3f317218U)) // 0.69314718055994973
  u = u * f
  let i2 = pow2if(k.reinterpret_as_int())
  f_fmlaf(u, z0, z0) * i2
}

///|
/// Dirty fast pow.
pub fn dirty_powf(d : Float, n : Float) -> Float {
  let value = fbf(tbf(d) & 0x7fff_ffffU)
  let lg = dirty_log2f(value)
  let c = dirty_exp2f(n * lg)
  if d < 0.0 {
    let y = n.to_int()
    if y % 2 == 0 {
      c
    } else {
      -c
    }
  } else {
    c
  }
}
