// Port of jxl-color `tf/srgb.rs` (generic implementation).

///|
let srgb_powtable_upper : FixedArray[UInt32] = [
  0x00, 0x0a, 0x19, 0x26, 0x32, 0x41, 0x4d, 0x5c, 0x68, 0x75, 0x83, 0x8f, 0xa0, 0xaa,
  0xb9, 0xc6,
]

///|
let srgb_powtable_lower : FixedArray[UInt32] = [
  0x00, 0xb7, 0x04, 0x0d, 0xcb, 0xe7, 0x41, 0x68, 0x51, 0xd1, 0xeb, 0xf2, 0x00, 0xb7,
  0x04, 0x0d,
]

///|
/// Converts the linear samples with the sRGB transfer curve.
///
/// Fast linear to sRGB conversion, ported from libjxl.
pub fn linear_to_srgb(
  samples : FixedArray[Float],
  start~ : Int32 = 0,
  len~ : Int32 = samples.length() - start,
) -> Unit {
  for i in start..<(start + len) {
    let s = samples[i]
    let v = s.reinterpret_as_uint() & 0x7fff_ffffU
    let v_adj = Float::reinterpret_from_uint((v | 0x3e80_0000U) & 0x3eff_ffffU)
    let pow : Float = 0.059914046
    let pow = pow * v_adj - 0.10889456
    let pow = pow * v_adj + 0.107963754
    let pow = pow * v_adj + 0.018092343

    // `mul` won't be used when `v` is small.
    let idx = ((v >> 23) - 118U).reinterpret_as_int() & 0xf
    let mul = 0x4000_0000U |
      (srgb_powtable_upper[idx] << 18) |
      (srgb_powtable_lower[idx] << 10)
    let v = Float::reinterpret_from_uint(v)
    let small = v * 12.92
    let acc = pow * Float::reinterpret_from_uint(mul) - 0.055
    samples[i] = copysign_f32(if v <= 0.0031308 { small } else { acc }, s)
  }
}

///|
let srgb_to_linear_p : FixedArray[Float] = [
  2.200248328e-4, 1.043637593e-2, 1.624820318e-1, 7.961564959e-1, 8.210152774e-1,
]

///|
let srgb_to_linear_q : FixedArray[Float] = [
  2.631846970e-1, 1.076976492, 4.987528350e-1, -5.512498495e-2, 6.521209011e-3,
]

///|
/// Converts samples in sRGB transfer curve to linear. Inverse of `linear_to_srgb`.
pub fn srgb_to_linear(
  samples : FixedArray[Float],
  start~ : Int32 = 0,
  len~ : Int32 = samples.length() - start,
) -> Unit {
  for i in start..<(start + len) {
    let x = samples[i]
    let a = x.abs()
    let v = if a <= 0.04045 {
      a / 12.92
    } else {
      rational_poly_eval_generic(a, srgb_to_linear_p, srgb_to_linear_q)
    }
    samples[i] = copysign_f32(v, x)
  }
}
