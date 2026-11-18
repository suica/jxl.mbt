// Ported from pxfm 0.1.30 (https://github.com/awxkee/pxfm),
// Copyright (c) Radzivon Bartoshyk. All rights reserved.
// BSD-3-Clause OR Apache-2.0 (see upstream LICENSE.md / LICENSE-APACHE.md).
//
// Port of `exponents/exp.rs` and the `ExpfBackend` operations it uses
// (`exponents/expf.rs`).
//
// On x86_64, `f_exp`, `f_exp10` and `f_exp2` choose at run time between
// `GenericExpfBackend` and `FmaBackend` (`is_x86_feature_detected!("avx")
// && is_x86_feature_detected!("fma")`). The `fma` flag selects the backend;
// the public functions use the FMA backend, which is what every x86_64 CPU
// with AVX and FMA (Haswell and later) runs.

///|
/// `ExpfBackend::fma`.
fn be_fma(fma : Bool, x : Double, y : Double, z : Double) -> Double {
  if fma {
    fma_f64(x, y, z)
  } else {
    f_fmla(x, y, z)
  }
}

///|
/// `ExpfBackend::quick_mult`.
fn be_quick_mult(
  fma : Bool,
  x : DoubleDouble,
  y : DoubleDouble,
) -> DoubleDouble {
  if fma {
    DoubleDouble::quick_mult_fma(x, y)
  } else {
    DoubleDouble::quick_mult(x, y)
  }
}

///|
fn exp_poly_dd(z : DoubleDouble) -> DoubleDouble {
  let c = exp_poly_dd_c
  let mut r = DoubleDouble::quick_mul_add(
    DoubleDouble::from_table(c, 6),
    z,
    DoubleDouble::from_table(c, 5),
  )
  r = DoubleDouble::quick_mul_add(r, z, DoubleDouble::from_table(c, 4))
  r = DoubleDouble::quick_mul_add(r, z, DoubleDouble::from_table(c, 3))
  r = DoubleDouble::quick_mul_add(r, z, DoubleDouble::from_table(c, 2))
  r = DoubleDouble::quick_mul_add(r, z, DoubleDouble::from_table(c, 1))
  DoubleDouble::quick_mul_add_f64(r, z, fb(0x3ff0000000000000UL))
}

///|
let exp_poly_dd_c : FixedArray[UInt64] = [
  0x0000000000000000UL, 0x3ff0000000000000UL, 0x39c712f72ecec2cfUL, 0x3fe0000000000000UL,
  0x3c65555555554d07UL, 0x3fc5555555555555UL, 0x3c455194d28275daUL, 0x3fa5555555555555UL,
  0x3c012faa0e1c0f7bUL, 0x3f81111111111111UL, 0xbbf4ba45ab25d2a3UL, 0x3f56c16c16da6973UL,
  0xbbc9091d845ecd36UL, 0x3f2a01a019eb7f31UL,
]

///|
fn as_exp_accurate(
  x : Double,
  t : Double,
  tz : DoubleDouble,
  ie : Int64,
) -> Double {
  let mut ix = tb(x)
  if ((ix >> 52) & 0x7ffUL) < 0x3c9UL {
    return 1.0 + x
  }
  // Use Cody-Waite argument reduction: since |x| < 745, we have |t| < 2^23,
  // thus since l2h is exactly representable on 29 bits, l2h*t is exact.
  let l2 = DoubleDouble::new(fb(0x3d0718432a1b0e26UL), fb(0x3f262e42ff000000UL))
  let l2ll = fb(0x3999ff0342542fc3UL)
  let dx = f_fmla(-l2.hi, t, x)
  let dx_dd = DoubleDouble::quick_mult_f64(DoubleDouble::new(l2ll, l2.lo), t)
  let dz = DoubleDouble::full_add_f64(dx_dd, dx)
  let mut f = exp_poly_dd(dz)
  f = DoubleDouble::quick_mult(dz, f)
  if ix > 0xc086232bdd7abcd2UL {
    // x < -708.396
    ix = (1L - ie).reinterpret_as_uint64() << 52
    f = DoubleDouble::quick_mult(f, tz)
    f = DoubleDouble::add(tz, f)
    let new_f = DoubleDouble::from_exact_add(fb(ix), f.hi)
    let f_lo = f.lo + new_f.lo
    to_denormal(f.hi + f_lo)
  } else {
    if tz.hi == 1.0 {
      let fhe = DoubleDouble::from_exact_add(tz.hi, f.hi)
      let fhl = DoubleDouble::from_exact_add(fhe.lo, f.lo)
      let mut f_lo = fhl.hi
      ix = tb(f_lo)
      if (ix & 0x000fffffffffffffUL) == 0UL {
        let v = tb(fhl.lo)
        let d = ((ix.reinterpret_as_int64() >> 63) ^
          (v.reinterpret_as_int64() >> 63)).reinterpret_as_uint64() <<
          1
        ix = ix + (d + 1UL)
        f_lo = fb(ix)
      }
      f = DoubleDouble::new(f_lo, fhe.hi)
    } else {
      f = DoubleDouble::quick_mult(f, tz)
      f = DoubleDouble::add(tz, f)
    }
    f = DoubleDouble::from_exact_add(f.hi, f.lo)
    fast_ldexp(f.hi, ie.to_int())
  }
}

///|
/// `exp_gen::<B>`; `fma` selects `FmaBackend` over `GenericExpfBackend`.
fn exp_gen(x : Double, fma : Bool) -> Double {
  let mut ix = tb(x)
  let aix = ix & 0x7fffffffffffffffUL
  // exp(x) rounds to 1 to nearest for |x| <= 5.55112e-17
  if aix <= 0x3c90000000000000UL {
    // |x| <= 5.55112e-17
    return 1.0 + x
  }
  if aix >= 0x40862e42fefa39f0UL {
    // |x| >= 709.783
    if aix > 0x7ff0000000000000UL {
      return x + x
    } // nan
    if aix == 0x7ff0000000000000UL {
      // |x| = inf
      return if ix >> 63 != 0UL { 0.0 } else { x }
    }
    if ix >> 63 == 0UL {
      // x >= 709.783
      let z = fb(0x7fe0000000000000UL)
      return z * z
    }
    if aix >= 0x40874910d52d3052UL {
      // x <= -745.133
      return fb(0x18000000000000UL) * fb(0x3c80000000000000UL)
    }
  }
  let s = fb(0x40b71547652b82feUL)
  let t = round_f64(x * s)
  let jt = to_int_unchecked_i64(t)
  let i0 = ((jt >> 6) & 0x3fL).to_int()
  let i1 = (jt & 0x3fL).to_int()
  let ie = jt >> 12
  let t0 = DoubleDouble::from_table(exp_reduce_t0, i0)
  let t1 = DoubleDouble::from_table(exp_reduce_t1, i1)
  let tz = be_quick_mult(fma, t0, t1)
  let l2 = DoubleDouble::new(fb(0x3d0718432a1b0e26UL), fb(0x3f262e42ff000000UL))
  // Use Cody-Waite argument reduction: since |x| < 745, we have |t| < 2^23,
  // thus since l2h is exactly representable on 29 bits, l2h*t is exact.
  let dx = be_fma(fma, l2.lo, t, be_fma(fma, -l2.hi, t, x))
  let dx2 = dx * dx
  let pw0 = be_fma(fma, dx, fb(0x3fa55555553a12f4UL), fb(0x3fc55555557e54ffUL))
  let pw1 = be_fma(fma, dx, fb(0x3fe0000000000000UL), fb(0x3ff0000000000000UL))
  let p = be_fma(fma, dx2, pw0, pw1)
  let mut f = DoubleDouble::new(be_fma(fma, tz.hi * dx, p, tz.lo), tz.hi)
  let eps = fb(0x3c0833beace2b6feUL)
  if ix > 0xc086232bdd7abcd2UL {
    // subnormal case: x < -708.396
    ix = (1UL - ie.reinterpret_as_uint64()) << 52
    let sums = DoubleDouble::from_exact_add(fb(ix), f.hi)
    f = DoubleDouble::new(f.lo + sums.lo, sums.hi)
    let ub = f.hi + (f.lo + eps)
    let lb = f.hi + (f.lo - eps)
    if ub != lb {
      return as_exp_accurate(x, t, tz, ie)
    }
    to_denormal(lb)
  } else {
    let ub = f.hi + (f.lo + eps)
    let lb = f.hi + (f.lo - eps)
    if ub != lb {
      return as_exp_accurate(x, t, tz, ie)
    }
    fast_ldexp(lb, ie.to_int())
  }
}

///|
/// Computes exponent.
///
/// Max found ULP 0.5. Port of pxfm `f_exp` as it runs on x86_64 with AVX and
/// FMA (`FmaBackend`).
pub fn f_exp(x : Double) -> Double {
  exp_gen(x, true)
}
