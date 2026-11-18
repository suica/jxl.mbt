// Ported from pxfm 0.1.30 (https://github.com/awxkee/pxfm),
// Copyright (c) Radzivon Bartoshyk. All rights reserved.
// BSD-3-Clause OR Apache-2.0 (see upstream LICENSE.md / LICENSE-APACHE.md).
//
// Port of `exponents/exp2.rs` (reached from `f_pow(2, y)`).

///|
let exp2_poly_dd_c : FixedArray[UInt64] = [
  0x3bbabc9e3b39873eUL, 0x3f262e42fefa39efUL, 0xbae5e43a53e44950UL, 0x3e4ebfbdff82c58fUL,
  0xba0d3a15710d3d83UL, 0x3d6c6b08d704a0c0UL, 0x3914dd5d2a5e025aUL, 0x3c83b2ab6fba4e77UL,
  0xb83dc47e47beb9ddUL, 0x3b95d87fe7a66459UL, 0xb744fcd51fcb7640UL, 0x3aa430912f9fb79dUL,
]

///|
fn exp2_poly_dd(z : Double) -> DoubleDouble {
  let c = exp2_poly_dd_c
  let mut r = DoubleDouble::quick_mul_f64_add(
    DoubleDouble::from_table(c, 5),
    z,
    DoubleDouble::from_table(c, 4),
  )
  r = DoubleDouble::quick_mul_f64_add(r, z, DoubleDouble::from_table(c, 3))
  r = DoubleDouble::quick_mul_f64_add(r, z, DoubleDouble::from_table(c, 2))
  r = DoubleDouble::quick_mul_f64_add(r, z, DoubleDouble::from_table(c, 1))
  DoubleDouble::quick_mul_f64_add(r, z, DoubleDouble::from_table(c, 0))
}

///|
fn exp2_accurate(x : Double) -> Double {
  let mut ix = tb(x)
  let sx = 4096.0 * x
  let fx = round_ties_even_f64(sx)
  let z = sx - fx
  let k = to_int_unchecked_i64(fx)
  let i1 = (k & 0x3fL).to_int()
  let i0 = ((k >> 6) & 0x3fL).to_int()
  let ie = k >> 12
  let t0 = DoubleDouble::from_table(exp_reduce_t0, i0)
  let t1 = DoubleDouble::from_table(exp_reduce_t1, i1)
  let dt = DoubleDouble::quick_mult(t0, t1)
  let mut f = exp2_poly_dd(z)
  f = DoubleDouble::quick_mult_f64(f, z)
  if ix <= 0xc08ff00000000000UL {
    // x >= -1022
    // for -0x1.71547652b82fep-54 <= x <= 0x1.71547652b82fdp-53,
    // exp2(x) round to x to nearest
    if fb(0xbc971547652b82feUL) <= x && x <= fb(0x3ca71547652b82fdUL) {
      return dd_fmla(x, 0.5, 1.0)
    } else if (k & 0xfffL) == 0L {
      // 4096*x rounds to 4096*integer
      let zf = DoubleDouble::from_exact_add(dt.hi, f.hi)
      let zfl = DoubleDouble::from_exact_add(zf.lo, f.lo)
      let mut f_lo = zfl.hi
      ix = tb(zfl.hi)
      if (ix & 0x000fffffffffffffUL) == 0UL {
        // fl is a power of 2
        if ((ix >> 52) & 0x7ffUL) != 0UL {
          // |fl| is Inf
          let v = tb(zfl.lo)
          let d = (
              ((ix.reinterpret_as_int64() >> 63) ^
              (v.reinterpret_as_int64() >> 63)).reinterpret_as_uint64() <<
              1
            ) +
            1UL
          ix = ix + d
          f_lo = fb(ix)
        }
      }
      f = DoubleDouble::new(f_lo, zf.hi)
    } else {
      f = DoubleDouble::quick_mult(f, dt)
      f = DoubleDouble::add(dt, f)
    }
    let hf = DoubleDouble::from_exact_add(f.hi, f.lo)
    fast_ldexp(hf.hi, ie.to_int())
  } else {
    ix = (1UL - ie.reinterpret_as_uint64()) << 52
    f = DoubleDouble::quick_mult(f, dt)
    f = DoubleDouble::add(dt, f)
    let zve = DoubleDouble::from_exact_add(fb(ix), f.hi)
    f = DoubleDouble::new(f.lo + zve.lo, zve.hi)
    to_denormal(f.to_f64())
  }
}

///|
/// `exp2_gen::<B>`; `fma` selects `FmaBackend` over `GenericExpfBackend`.
fn exp2_gen(x : Double, fma : Bool) -> Double {
  let mut ix = tb(x)
  let ax = ix << 1
  if ax == 0UL {
    return 1.0
  }
  if ax >= 0x8120000000000000UL {
    // |x| >= 1024
    if ax > 0xffe0000000000000UL {
      return x + x // nan
    }
    if ax == 0xffe0000000000000UL {
      return if ix >> 63 != 0UL { 0.0 } else { x }
    }
    // +/-inf
    if ix >> 63 != 0UL {
      // x <= -1024
      if ix >= 0xc090cc0000000000UL {
        // x <= -1075
        let z = fb(0x0010000000000000UL)
        return z * z
      }
    } else {
      // x >= 1024
      return fb(0x7fe0000000000000UL) * x
    }
  }
  // for |x| <= 0x1.71547652b82fep-54, 2^x rounds to 1 to nearest
  // this avoids a spurious underflow in z*z below
  if ax <= 0x792e2a8eca5705fcUL {
    return 1.0 + copysign_f64(fb(0x3c90000000000000UL), x)
  }
  let m = ix << 12
  let ex = (ax >> 53) - 0x3ffUL
  let frac = (ex >> 63) | (m << (ex & 63UL).to_int())
  let sx = 4096.0 * x
  let fx = round_ties_even_f64(sx)
  let z = sx - fx
  let z2 = z * z
  let k = to_int_unchecked_i64(fx)
  let i1 = (k & 0x3fL).to_int()
  let i0 = ((k >> 6) & 0x3fL).to_int()
  let ie = k >> 12
  let t0 = DoubleDouble::from_table(exp_reduce_t0, i0)
  let t1 = DoubleDouble::from_table(exp_reduce_t1, i1)
  let ti0 = be_quick_mult(fma, t0, t1)
  let tz = ti0.hi * z
  let mut fh = ti0.hi
  let p0 = be_fma(fma, z, fb(0x3e4ebfbdff82c58fUL), fb(0x3f262e42fefa39efUL))
  let p1 = be_fma(fma, z, fb(0x3c83b2ab6fdda001UL), fb(0x3d6c6b08d73b3e01UL))
  let p2 = be_fma(fma, z2, p1, p0)
  let mut fl = be_fma(fma, tz, p2, ti0.lo)
  let eps = fb(0x3c0833beace2b6feUL)
  if ix <= 0xc08ff00000000000UL {
    // x >= -1022
    if frac != 0UL {
      let ub = fh + (fl + eps)
      fh = fh + (fl - eps)
      if ub != fh {
        return exp2_accurate(x)
      }
    }
    fh = fast_ldexp(fh, ie.to_int())
  } else {
    // subnormal case
    ix = (1UL - ie.reinterpret_as_uint64()) << 52
    let rs = DoubleDouble::from_exact_add(fb(ix), fh)
    fl = fl + rs.lo
    fh = rs.hi
    if frac != 0UL {
      let ub = fh + (fl + eps)
      fh = fh + (fl - eps)
      if ub != fh {
        return exp2_accurate(x)
      }
    }
    // when 2^x is exact, no underflow should be raised
    fh = to_denormal(fh)
  }
  fh
}

///|
/// Computes exp2.
///
/// Max found ULP 0.5. Port of pxfm `f_exp2` as it runs on x86_64 with AVX
/// and FMA (`FmaBackend`); also reached by `f_pow(2, y)`.
pub fn f_exp2(x : Double) -> Double {
  exp2_gen(x, true)
}
