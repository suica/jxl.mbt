// Ported from pxfm 0.1.30 (https://github.com/awxkee/pxfm),
// Copyright (c) Radzivon Bartoshyk. All rights reserved.
// BSD-3-Clause OR Apache-2.0 (see upstream LICENSE.md / LICENSE-APACHE.md).
//
// Port of `pow.rs` (`f_pow`). `f_pow` itself has no runtime dispatch; the
// not-fma branches run. Its `x == 2` / `x == 10` shortcuts call `f_exp2` /
// `f_exp10`, which do dispatch (see exp.mbt): `fma` selects their backend.

///|
fn f_powi(x : Double, y : Double) -> Double {
  let mut iter_count = to_int_unchecked_i64(abs_f64(y))
  let mut s = DoubleDouble::new(0.0, x)
  // exponentiation by squaring: O(log(y)) complexity
  let mut acc = if iter_count % 2L != 0L {
    s
  } else {
    DoubleDouble::new(0.0, 1.0)
  }
  while true {
    iter_count = iter_count >> 1
    if iter_count == 0L {
      break
    }
    s = DoubleDouble::mult(s, s)
    if iter_count % 2L != 0L {
      acc = DoubleDouble::mult(acc, s)
    }
  }
  let dz = if is_sign_negative(y) { acc.recip() } else { acc }
  let ub = dz.hi + f_fmla(fb(0x3c40000000000000UL), -dz.hi, dz.lo) // 2^-59
  let lb = dz.hi + f_fmla(fb(0x3c40000000000000UL), dz.hi, dz.lo) // 2^-59
  if ub == lb {
    return dz.to_f64()
  }
  f_powi_hard(x, y)
}

///|
fn f_powi_hard(x : Double, y : Double) -> Double {
  let mut iter_count = to_int_unchecked_i64(abs_f64(y))
  let mut s = TripleDouble::new(0.0, 0.0, x)
  // exponentiation by squaring: O(log(y)) complexity
  let mut acc = if iter_count % 2L != 0L {
    s
  } else {
    TripleDouble::new(0.0, 0.0, 1.0)
  }
  while true {
    iter_count = iter_count >> 1
    if iter_count == 0L {
      break
    }
    s = TripleDouble::quick_mult(s, s)
    if iter_count % 2L != 0L {
      acc = TripleDouble::quick_mult(acc, s)
    }
  }
  let dz = if is_sign_negative(y) { acc.recip() } else { acc }
  dz.to_f64()
}

///|
/// `f_pow`; `fma` selects the backend of the `f_exp2` / `f_exp10` fallbacks.
fn pow_impl(x : Double, y : Double, fma : Bool) -> Double {
  let mut y = y
  let x_sign = is_sign_negative(x)
  let y_sign = is_sign_negative(y)
  let x_abs = tb(x) & 0x7fff_ffff_ffff_ffffUL
  let y_abs = tb(y) & 0x7fff_ffff_ffff_ffffUL
  let mantissa_mask = (1UL << 52) - 1UL
  let y_mant = tb(y) & mantissa_mask
  let x_u = tb(x)
  let x_a = x_abs
  let y_a = y_abs
  let mut x = x
  // If x or y is signaling NaN
  if is_nan(x) || is_nan(y) {
    return nan_f64
  }
  let mut s = 1.0
  // The double precision number that is closest to 1 is (1 - 2^-53), which has
  //   log2(1 - 2^-53) ~ -1.715...p-53.
  // So if |y| > |1075 / log2(1 - 2^-53)|, and x is finite:
  //   |y * log2(x)| = 0 or > 1075.
  // Hence, x^y will either overflow or underflow if x is not zero.
  if y_mant == 0UL ||
    y_a > 0x43d7_4910_d52d_3052UL ||
    x_u == tb(1.0) ||
    x_u >= 0x7ff0000000000000UL ||
    x_u < 0xffefffffffffffffUL {
    // Exceptional exponents.
    if y == 0.0 {
      return 1.0
    }
    match y_a {
      0x3fe0_0000_0000_0000UL => {
        if x == 0.0 || x_u == 0xfff0000000000000UL {
          // pow(-0, 1/2) = +0
          // pow(-inf, 1/2) = +inf
          return if y_sign { 1.0 / (x * x) } else { x * x }
        }
        return if y_sign {
          if x == inf_f64 || x == -inf_f64 {
            return if !is_sign_negative(x) { 0.0 } else { nan_f64 }
          }
          let r = x.sqrt() / x
          let d2x = DoubleDouble::from_exact_mult(r, x)
          let { hi: h, lo: pr, } = DoubleDouble::quick_mult_f64(d2x, r)
          let { hi: p, lo: q, } = DoubleDouble::from_full_exact_add(-1.0, h)
          let h = DoubleDouble::from_exact_add(p, pr + q)
          let dr = DoubleDouble::quick_mult_f64(h, r * 0.5)
          r - dr.hi - dr.lo
        } else {
          x.sqrt()
        }
      }
      0x3ff0_0000_0000_0000UL => return if y_sign { 1.0 / x } else { x }
      0x4000_0000_0000_0000UL => {
        let x_e = get_exponent_f64(x)
        if x_e > 511L {
          return if y_sign { 0.0 } else { inf_f64 }
        }
        // not enough precision to make 0.5 ULP for subnormals
        let a_xe = x_e & 0x7fff_ffff_ffff_ffffL
        if a_xe < 70L {
          let x_sqr = DoubleDouble::from_exact_mult(x, x)
          return if y_sign {
            let recip = x_sqr.recip()
            recip.to_f64()
          } else {
            x_sqr.to_f64()
          }
        }
      }
      _ => ()
    }
    // |y| > |1075 / log2(1 - 2^-53)|.
    if y_a > 0x43d7_4910_d52d_3052UL {
      if y_a >= 0x7ff0_0000_0000_0000UL {
        // y is inf or nan
        if y_mant != 0UL {
          // y is NaN
          // pow(1, NaN) = 1
          // pow(x, NaN) = NaN
          return if x_u == tb(1.0) { 1.0 } else { y }
        }
        // Now y is +-Inf
        if is_nan(fb(x_abs)) {
          // pow(NaN, +-Inf) = NaN
          return x
        }
        if x_a == 0x3ff0_0000_0000_0000UL {
          // pow(+-1, +-Inf) = 1.0
          return 1.0
        }
        if x == 0.0 && y_sign {
          // pow(+-0, -Inf) = +inf and raise FE_DIVBYZERO
          return inf_f64
        }
        // pow (|x| < 1, -inf) = +inf
        // pow (|x| < 1, +inf) = 0.0
        // pow (|x| > 1, -inf) = 0.0
        // pow (|x| > 1, +inf) = +inf
        return if (x_a < tb(1.0)) == y_sign { inf_f64 } else { 0.0 }
      }
      // x^y will overflow / underflow in double precision.  Set y to a
      // large enough exponent but not too large, so that the computations
      // won't overflow in double precision.
      y = if y_sign {
        fb(0xc630000000000000UL)
      } else {
        fb(0x4630000000000000UL)
      }
    }
    // y is finite and non-zero.
    if x_u == tb(1.0) {
      // pow(1, y) = 1
      return 1.0
    }
    if x == 0.0 {
      let out_is_neg = x_sign && is_odd_integer(y)
      if y_sign {
        // pow(0, negative number) = inf
        return if out_is_neg { -inf_f64 } else { inf_f64 }
      }
      // pow(0, positive number) = 0
      return if out_is_neg { -0.0 } else { 0.0 }
    } else if x == 2.0 {
      return exp2_gen(y, fma)
    } else if x == 10.0 {
      return exp10_gen(y, fma)
    }
    if x_a == 0x7ff0000000000000UL {
      let out_is_neg = x_sign && is_odd_integer(y)
      if y_sign {
        return if out_is_neg { -0.0 } else { 0.0 }
      }
      return if out_is_neg { -inf_f64 } else { inf_f64 }
    }
    if x_a > 0x7ff0000000000000UL {
      // x is NaN.
      // pow (aNaN, 0) is already taken care above.
      return x
    }
    // x is finite and negative, and y is a finite integer.
    let is_y_integer = is_integer(y)
    // y is integer and in [-102;102] and |x|<2^10
    // this is correct only for positive exponent number without FMA,
    // otherwise reciprocal may overflow.
    if is_y_integer &&
      y_a <= 0x4059800000000000UL &&
      x_a <= 0x4090000000000000UL &&
      x_a > 0x3cc0_0000_0000_0000UL &&
      !is_sign_negative(y) {
      return f_powi(x, y)
    }
    if x_sign {
      if is_y_integer {
        x = -x
        if is_odd_integer(y) {
          // set sign to 1 for y even, to -1 for y odd
          let y_parity = if abs_f64(y) >= fb(0x4340000000000000UL) {
            0
          } else {
            (y.to_int64() & 1L).to_int()
          }
          s = if y_parity == 0 { 1.0 } else { -1.0 }
        }
      } else {
        // pow( negative, non-integer ) = NaN
        return nan_f64
      }
    }
    // y is finite and non-zero.
    if x_u == tb(1.0) {
      // pow(1, y) = 1
      return 1.0
    }
    if x == 0.0 {
      let out_is_neg = x_sign && is_odd_integer(y)
      if y_sign {
        // pow(0, negative number) = inf
        return if out_is_neg { -inf_f64 } else { inf_f64 }
      }
      // pow(0, positive number) = 0
      return if out_is_neg { -0.0 } else { 0.0 }
    }
    if x_a == 0x7ff0000000000000UL {
      let out_is_neg = x_sign && is_odd_integer(y)
      if y_sign {
        return if out_is_neg { -0.0 } else { 0.0 }
      }
      return if out_is_neg { -inf_f64 } else { inf_f64 }
    }
    if x_a > 0x7ff0000000000000UL {
      // x is NaN.
      return x
    }
  }
  // approximate log(x)
  let (l0, cancel) = pow_log_1(x)
  let mut l = l0
  // We should avoid a spurious underflow/overflow in y*log(x).
  // Underflow: for x<>1, the smallest absolute value of log(x) is obtained
  // for x=1-2^-53, with |log(x)| ~ 2^-53. Thus to avoid a spurious underflow
  // we require |y| >= 2^-969.
  // Overflow: the largest absolute value of log(x) is obtained for x=2^-1074,
  // with |log(x)| < 745. Thus to avoid a spurious overflow we require
  // |y| < 2^1014.
  let ey = ((tb(y) >> 52) & 0x7ffUL).to_int()
  if ey < 0x36 || ey >= 0x7f5 {
    l = DoubleDouble::new(nan_f64, nan_f64)
  }
  let r = DoubleDouble::quick_mult_f64(l, y)
  let res = pow_exp_1(r, s)
  let err = if cancel {
    fb(0x3c55700000000000UL)
  } else {
    fb(0x3bf2700000000000UL)
  }
  let res_min = res.hi + f_fmla(err, -res.hi, res.lo)
  let res_max = res.hi + f_fmla(err, res.hi, res.lo)
  if res_min == res_max {
    return res_max
  }
  pow_rational128(x, y, s)
}

///|
fn pow_rational128(x : Double, y : Double, s : Double) -> Double {
  let f_y = DyadicFloat128::new_from_f64(y)
  let r = log_dyadic(x) * f_y
  let result = exp_dyadic(r)
  // 2^R.ex <= R < 2^(R.ex+1)
  { neg: s == -1.0, exponent: result.exponent, hi: result.hi, lo: result.lo, }.fast_as_f64()
}

///|
/// Power function.
///
/// Max found ULP 0.5. Port of pxfm `f_pow`; the `x == 2` / `x == 10` cases
/// go through `f_exp2` / `f_exp10` with the FMA backend, as on x86_64 CPUs
/// with AVX and FMA.
pub fn f_pow(x : Double, y : Double) -> Double {
  pow_impl(x, y, true)
}
