// Fixed point helpers from lcms2_internal.h and cmsintrp.c.
// MoonBit `Int` arithmetic wraps on overflow, matching the two's complement
// behaviour lcms2 relies on in its interpolation routines.

///|
/// `_cmsQuickFloor`: adds 1.5 * 2^36 so that the low 32 bits of the double
/// hold the value as 16.16 fixed point (rounded to nearest even), then shifts.
fn quick_floor(val : Double) -> Int32 {
  let temp = val + 103079215104.0
  temp.reinterpret_as_int64().to_int() >> 16
}

///|
/// `_cmsQuickFloorWord`
fn quick_floor_word(d : Double) -> Int32 {
  ((quick_floor(d - 32767.0) & 0xFFFF) + 32767) & 0xFFFF
}

///|
/// `_cmsQuickSaturateWord`: round and saturate to 0..0xffff.
fn quick_saturate_word(d0 : Double) -> Int32 {
  let d = d0 + 0.5
  if d <= 0.0 {
    0
  } else if d >= 65535.0 {
    0xFFFF
  } else {
    quick_floor_word(d)
  }
}

///|
/// `_cmsToFixedDomain`
fn to_fixed_domain(a : Int32) -> Int32 {
  a + (a + 0x7fff) / 0xffff
}

///|
/// `ROUND_FIXED_TO_INT`
fn round_fixed_to_int(x : Int32) -> Int32 {
  (x + 0x8000) >> 16
}

///|
/// `LinearInterp` (fixed point, unsigned 32-bit arithmetic).
fn linear_interp(a : Int32, l : Int32, h : Int32) -> Int32 {
  let dif = (h - l).reinterpret_as_uint() * a.reinterpret_as_uint() + 0x8000U
  ((dif >> 16).reinterpret_as_int() + l) & 0xFFFF
}

///|
/// `FROM_8_TO_16`
fn from_8_to_16(v : Int32) -> Int32 {
  (v << 8) | v
}
