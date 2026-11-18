// Ported from pxfm 0.1.30 (https://github.com/awxkee/pxfm),
// Copyright (c) Radzivon Bartoshyk. All rights reserved.
// BSD-3-Clause OR Apache-2.0 (see upstream LICENSE.md / LICENSE-APACHE.md).
//
// Port of `exponents/exp10.rs`.

///|
let exp10_poly_dd_c : FixedArray[UInt64] = [
  0xbcaf48ad494ea102UL, 0x40026bb1bbb55516UL, 0xbcae2bfab318d399UL, 0x40053524c73cea69UL,
  0x3ca81f50779e162bUL, 0x4000470591de2ca4UL, 0x3c931a5cc5d3d313UL, 0x3ff2bd7609fd98c4UL,
  0x3c8910de8c68a0c2UL, 0x3fe1429ffd336aa3UL, 0xbc605e703d496537UL, 0x3fca7ed7086882b4UL,
]

///|
fn exp10_poly_dd(z : DoubleDouble) -> DoubleDouble {
  let c = exp10_poly_dd_c
  let mut r = DoubleDouble::quick_mul_add(
    DoubleDouble::from_table(c, 5),
    z,
    DoubleDouble::from_table(c, 4),
  )
  r = DoubleDouble::quick_mul_add(r, z, DoubleDouble::from_table(c, 3))
  r = DoubleDouble::quick_mul_add(r, z, DoubleDouble::from_table(c, 2))
  r = DoubleDouble::quick_mul_add(r, z, DoubleDouble::from_table(c, 1))
  DoubleDouble::quick_mul_add(r, z, DoubleDouble::from_table(c, 0))
}

///|
fn as_exp10_accurate(x : Double) -> Double {
  let mut ix = tb(x)
  let t = round_ties_even_f64(fb(0x40ca934f0979a371UL) * x)
  let jt = to_int_unchecked_i64(t)
  let i1 = (jt & 0x3fL).to_int()
  let i0 = ((jt >> 6) & 0x3fL).to_int()
  let ie = jt >> 12
  let t0 = DoubleDouble::from_table(exp_reduce_t0, i0)
  let t1 = DoubleDouble::from_table(exp_reduce_t1, i1)
  let dt = DoubleDouble::quick_mult(t0, t1)
  let l0 = fb(0x3f13441350800000UL)
  let l1 = fb(0xbd1f79fef311f12bUL)
  let l2 = fb(0xb9aac0b7c917826bUL)
  let dx = x - l0 * t
  let dx_dd = DoubleDouble::quick_mult_f64(DoubleDouble::new(l2, l1), t)
  let dz = DoubleDouble::full_add_f64(dx_dd, dx)
  let mut f = exp10_poly_dd(dz)
  f = DoubleDouble::quick_mult(dz, f)
  let mut zfh : Double = 0.0
  if ix < 0xc0733a7146f72a42UL {
    if (jt & 0xfffL) == 0L {
      f = DoubleDouble::from_exact_add(f.hi, f.lo)
      let zt = DoubleDouble::from_exact_add(dt.hi, f.hi)
      f = DoubleDouble::new(f.lo, zt.lo)
      f = DoubleDouble::from_exact_add(f.hi, f.lo)
      ix = tb(f.hi)
      if ix << 12 == 0UL {
        let l = tb(f.lo)
        let sfh = (ix.reinterpret_as_int64() >> 63) ^
          (l.reinterpret_as_int64() >> 63)
        ix = ix + ((1L << 51) ^ sfh).reinterpret_as_uint64()
      }
      zfh = zt.hi + fb(ix)
    } else {
      f = DoubleDouble::quick_mult(f, dt)
      f = DoubleDouble::add(dt, f)
      f = DoubleDouble::from_exact_add(f.hi, f.lo)
      zfh = f.hi
    }
    zfh = fast_ldexp(zfh, ie.to_int())
  } else {
    ix = (1UL - ie.reinterpret_as_uint64()) << 52
    f = DoubleDouble::quick_mult(f, dt)
    f = DoubleDouble::add(dt, f)
    let zt = DoubleDouble::from_exact_add(fb(ix), f.hi)
    f = DoubleDouble::new(f.lo + zt.lo, zt.hi)
    zfh = to_denormal(f.to_f64())
  }
  zfh
}

///|
/// `exp10_gen::<B>`; `fma` selects `FmaBackend` over `GenericExpfBackend`.
fn exp10_gen(x : Double, fma : Bool) -> Double {
  let mut ix = tb(x)
  let aix = ix & 0x7fff_ffff_ffff_ffffUL
  if aix > 0x40734413509f79feUL {
    // |x| > 0x40734413509f79fe
    if aix > 0x7ff0000000000000UL {
      return x + x
    } // nan
    if aix == 0x7ff0000000000000UL {
      return if ix >> 63 != 0UL { 0.0 } else { x }
    }
    if ix >> 63 == 0UL {
      return fb(0x7fe0000000000000UL) * 2.0 // x > 308.255
    }
    if aix > 0x407439b746e36b52UL {
      // x < -323.607
      return fb(0x0018000000000000UL) * fb(0x3c80000000000000UL)
    }
  }
  // check x integer to avoid a spurious inexact exception
  if ix << 16 == 0UL && aix >> 48 <= 0x4036UL {
    let kx = round_ties_even_f64(x)
    if kx == x {
      let k = kx.to_int64()
      if k >= 0L {
        let mut r = 1.0
        let mut i = 0L
        while i < k {
          r = r * 10.0
          i += 1L
        }
        return r
      }
    }
  }
  // avoid spurious underflow: for |x| <= 2.41082e-17
  // exp10(x) rounds to 1 to nearest
  if aix <= 0x3c7bcb7b1526e50eUL {
    return 1.0 + x // |x| <= 2.41082e-17
  }
  let t = round_ties_even_f64(fb(0x40ca934f0979a371UL) * x)
  let jt = to_int_unchecked_i64(t)
  let i1 = (jt & 0x3fL).to_int()
  let i0 = ((jt >> 6) & 0x3fL).to_int()
  let ie = jt >> 12
  let t0 = DoubleDouble::from_table(exp_reduce_t0, i0)
  let t1 = DoubleDouble::from_table(exp_reduce_t1, i1)
  let mut tz = be_quick_mult(fma, t0, t1)
  let l0 = fb(0x3f13441350800000UL)
  let l1 = fb(0x3d1f79fef311f12bUL)
  let dx = be_fma(fma, -l1, t, be_fma(fma, -l0, t, x))
  let dx2 = dx * dx
  let p0 = be_fma(fma, dx, fb(0x40053524c73cea69UL), fb(0x40026bb1bbb55516UL))
  let p1 = be_fma(fma, dx, fb(0x3ff2bd760a1f32a5UL), fb(0x4000470591fd74e1UL))
  let p = be_fma(fma, dx2, p1, p0)
  let mut fh = tz.hi
  let fx = tz.hi * dx
  let mut fl = be_fma(fma, fx, p, tz.lo)
  let eps = fb(0x3c080df744ce99c7UL) // 1.63e-19
  if ix < 0xc0733a7146f72a42UL {
    // x > -307.653
    let ub = fh + (fl + eps)
    let lb = fh + (fl - eps)
    if lb != ub {
      return as_exp10_accurate(x)
    }
    fh = fast_ldexp(fh + fl, ie.to_int())
  } else {
    // x <= -307.653: exp10(x) < 2^-1022
    ix = (1UL - ie.reinterpret_as_uint64()) << 52
    tz = DoubleDouble::from_exact_add(fb(ix), fh)
    fl = fl + tz.lo
    let ub = fh + (fl + eps)
    let lb = fh + (fl - eps)
    if lb != ub {
      return as_exp10_accurate(x)
    }
    fh = to_denormal(fh + fl)
  }
  fh
}

///|
/// Computes exp10.
///
/// Max found ULP 0.5. Port of pxfm `f_exp10` as it runs on x86_64 with AVX
/// and FMA (`FmaBackend`).
pub fn f_exp10(x : Double) -> Double {
  exp10_gen(x, true)
}
