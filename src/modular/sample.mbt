///|
/// Sample type of Modular images.
///
/// Upstream `Sample` is generic over `i32` and `i16`; this port always uses
/// `Int` (32-bit, wrapping), which is what the `i32` instantiation does.
/// The helpers below mirror the `Sealed` trait methods for `i32`.

///|
/// `Sealed::unpack_signed_u32` for `i32`.
#inline
fn unpack_signed_u32(value : UInt32) -> Int32 {
  (value >> 1).reinterpret_as_int() ^ -(value & 1).reinterpret_as_int()
}

///|
/// `Sealed::wrapping_muladd_i32` for `i32`: `self * mul + add`, wrapping.
#inline
fn wrapping_muladd_i32(self_ : Int32, mul : Int32, add : Int32) -> Int32 {
  self_ * mul + add
}

///|
/// Clamped gradient, `(n + w - nw).clamp(w.min(n), w.max(n))`, computed in
/// 64 bits like upstream's `i32` implementation.
#inline
fn grad_clamped(n : Int32, w : Int32, nw : Int32) -> Int32 {
  let (n, w) = if w > n {
    (w.to_int64(), n.to_int64())
  } else {
    (n.to_int64(), w.to_int64())
  }
  // here n is the max and w the min
  let v = w + n - nw.to_int64()
  (if v < w { w } else if v > n { n } else { v }).to_int()
}

///|
/// `i32::unsigned_abs() as i32` / wrapping `i32::abs()`.
#inline
fn wrapping_abs(v : Int32) -> Int32 {
  if v < 0 {
    -v
  } else {
    v
  }
}

///|
/// `a.abs_diff(b)` as `u64` (here as a non-negative `Int64`) for `i32`s.
#inline
fn abs_diff_i32(a : Int32, b : Int32) -> Int64 {
  let d = a.to_int64() - b.to_int64()
  if d < 0L {
    -d
  } else {
    d
  }
}
