// Rust float semantics used by the port (`f32::min`, `f32::max`, `clamp`,
// `round`, saturating `as` casts).

///|
/// `f32::min`: if one operand is NaN the other is returned.
fn fmin(a : Float, b : Float) -> Float {
  if a.is_nan() {
    b
  } else if b.is_nan() {
    a
  } else if b < a {
    b
  } else {
    a
  }
}

///|
/// `f32::max`: if one operand is NaN the other is returned.
fn fmax(a : Float, b : Float) -> Float {
  if a.is_nan() {
    b
  } else if b.is_nan() {
    a
  } else if b > a {
    b
  } else {
    a
  }
}

///|
fn dmin(a : Double, b : Double) -> Double {
  if a.is_nan() {
    b
  } else if b.is_nan() {
    a
  } else if b < a {
    b
  } else {
    a
  }
}

///|
fn dmax(a : Double, b : Double) -> Double {
  if a.is_nan() {
    b
  } else if b.is_nan() {
    a
  } else if b > a {
    b
  } else {
    a
  }
}

///|
/// `f32::clamp` (NaN stays NaN).
fn fclamp(x : Float, lo : Float, hi : Float) -> Float {
  let mut x = x
  if x < lo {
    x = lo
  }
  if x > hi {
    x = hi
  }
  x
}

///|
fn dclamp(x : Double, lo : Double, hi : Double) -> Double {
  let mut x = x
  if x < lo {
    x = lo
  }
  if x > hi {
    x = hi
  }
  x
}

///|
fn fabs(x : Float) -> Float {
  Float::reinterpret_from_uint(x.reinterpret_as_uint() & 0x7FFFFFFFU)
}

///|
fn dabs(x : Double) -> Double {
  (x.reinterpret_as_uint64() & 0x7FFFFFFFFFFFFFFFUL).reinterpret_as_double()
}

///|
fn ftrunc(x : Float) -> Float {
  Float::from_double(x.to_double().trunc())
}

///|
fn ffloor(x : Float) -> Float {
  Float::from_double(x.to_double().floor())
}

///|
fn fceil(x : Float) -> Float {
  Float::from_double(x.to_double().ceil())
}

///|
/// `f32::round`: half away from zero.
fn fround(x : Float) -> Float {
  if x.is_nan() || x.is_inf() {
    return x
  }
  let t = ftrunc(x)
  let diff = fabs(x - t)
  if diff >= 0.5 {
    if x < 0.0 {
      t - 1.0
    } else {
      t + 1.0
    }
  } else {
    t
  }
}

///|
/// `f64::round`: half away from zero.
fn dround(x : Double) -> Double {
  if x.is_nan() || x.is_inf() {
    return x
  }
  let t = x.trunc()
  let diff = dabs(x - t)
  if diff >= 0.5 {
    if x < 0.0 {
      t - 1.0
    } else {
      t + 1.0
    }
  } else {
    t
  }
}

///|
/// `f32 as i32` (saturating, NaN to 0).
fn f2i(x : Float) -> Int32 {
  d2i(x.to_double())
}

///|
/// `f64 as i32` (saturating, NaN to 0).
fn d2i(x : Double) -> Int32 {
  if x.is_nan() {
    0
  } else if x >= 2147483647.0 {
    2147483647
  } else if x <= -2147483648.0 {
    -2147483648
  } else {
    x.trunc().to_int()
  }
}

///|
/// `f64 as u16` (saturating, NaN to 0).
fn d2u16(x : Double) -> Int32 {
  if x.is_nan() || x <= 0.0 {
    0
  } else if x >= 65535.0 {
    65535
  } else {
    x.trunc().to_int()
  }
}

///|
/// `f32 as u16`.
fn f2u16(x : Float) -> Int32 {
  d2u16(x.to_double())
}

///|
/// `f32 as i16` (saturating).
fn f2i16(x : Float) -> Int32 {
  let v = f2i(x)
  if v > 32767 {
    32767
  } else if v < -32768 {
    -32768
  } else {
    v
  }
}

///|
/// `PointeeSizeExpressible::_as_usize` for `f32` (14-bit index).
fn f32_as_usize(x : Float) -> Int32 {
  let max14 : Float = 16383.0
  f2u16(fmin(fmax(x * max14, 0.0), max14))
}

///|
/// `f32::mul_add` / `_mm_fmadd_ps` lane: `a * b + c` with one rounding.
fn fma_f32(a : Float, b : Float, c : Float) -> Float {
  let p = a.to_double() * b.to_double() // exact
  let z = c.to_double()
  let s = p + z
  if s.is_nan() || s.is_inf() || p.is_inf() || z.is_inf() {
    return Float::from_double(s)
  }
  // Error of the double sum (TwoSum).
  let bb = s - p
  let err = p - (s - bb) + (z - bb)
  let f = Float::from_double(s)
  if err == 0.0 || f.is_inf() {
    return f
  }
  let fd = f.to_double()
  if fd == s {
    return f
  }
  // Neighbour of `f` on the other side of `s`.
  let fb = f.reinterpret_as_uint()
  let g = if (fd < s) == (f >= 0.0) {
    // move away from zero
    Float::reinterpret_from_uint(fb + 1U)
  } else if (fb & 0x7FFFFFFFU) == 0U {
    // f is a zero: neighbour is the smallest subnormal of the sign of s
    Float::reinterpret_from_uint(
      if s < 0.0 {
        0x80000001U
      } else {
        0x00000001U
      },
    )
  } else {
    Float::reinterpret_from_uint(fb - 1U)
  }
  let mid = (fd + g.to_double()) * 0.5
  if mid != s {
    return f
  }
  // `s` is exactly halfway: the exact value lies on the side of `err`.
  let exact_above = err > 0.0
  let (lo, hi) = if fd < g.to_double() { (f, g) } else { (g, f) }
  if exact_above {
    hi
  } else {
    lo
  }
}
