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
/// Fused multiply-add on `Double` (`f64::mul_add`), computed with an exact
/// product (Dekker's algorithm) followed by a compensated sum.
///
/// This is not correctly rounded in every case, but it is within one ulp of
/// the exact result and exact for all non-pathological inputs.
fn mul_add_f64(a : Double, b : Double, c : Double) -> Double {
  let p = a * b
  if p.is_inf() || p.is_nan() || c.is_inf() || c.is_nan() {
    return p + c
  }
  // Dekker split
  let split = 134217729.0 // 2^27 + 1
  let ta = split * a
  let ahi = ta - (ta - a)
  let alo = a - ahi
  let tb = split * b
  let bhi = tb - (tb - b)
  let blo = b - bhi
  let perr = ahi * bhi - p + ahi * blo + alo * bhi + alo * blo
  // two-sum of p and c
  let s = p + c
  let bb = s - p
  let serr = p - (s - bb) + (c - bb)
  s + (perr + serr)
}

///|
/// `f32::copysign`: magnitude of `mag` with the sign of `sign`.
fn copysign_f32(mag : Float, sign : Float) -> Float {
  let m = mag.reinterpret_as_uint() & 0x7fff_ffffU
  let s = sign.reinterpret_as_uint() & 0x8000_0000U
  Float::reinterpret_from_uint(m | s)
}

///|
/// `f32::log2`, computed in f64 and rounded.
fn log2_f32(x : Float) -> Float {
  Float::from_double(@math.log2(x.to_double()))
}
