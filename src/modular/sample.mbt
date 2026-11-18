///|
/// Type of Modular image samples (upstream trait `Sample`, implemented by
/// `i32` and `i16`).
///
/// MoonBit grids always hold `Int`; with `I16` every stored sample is kept
/// as a sign-extended 16-bit value and all sample arithmetic wraps at 16
/// bits exactly like upstream's `i16` instantiation, so the stored values
/// are the same as upstream's. Allocation tracking counts 2 bytes per `I16`
/// sample.
#derive(Debug, Eq)
pub(all) enum Sample {
  I32
  I16
}

///|
/// `size_of::<S>()`.
pub fn Sample::size(self : Sample) -> Int32 {
  match self {
    I32 => 4
    I16 => 2
  }
}

///|
/// `S::from_i32` (`value as i16` truncates).
pub fn Sample::from_i32(self : Sample, value : Int32) -> Int32 {
  match self {
    I32 => value
    I16 => wrap_i16(value)
  }
}

///|
/// `S::from_u32` (`value as i32` / `value as i16`).
pub fn Sample::from_u32(self : Sample, value : UInt32) -> Int32 {
  self.from_i32(value.reinterpret_as_int())
}

///|
/// `value as i16 as i32`.
#inline
fn wrap_i16(value : Int32) -> Int32 {
  value << 16 >> 16
}

///|
/// Wraps to 16 bits when `narrow` (`i16`), identity otherwise (`i32`).
#inline
fn wrap_s(narrow : Bool, value : Int32) -> Int32 {
  if narrow {
    value << 16 >> 16
  } else {
    value
  }
}

///|
/// `Sealed::unpack_signed_u32` for `i32` (the `i16` version is this value
/// truncated to 16 bits).
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
