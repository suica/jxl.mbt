// Port of jxl-color `tf/srgb.rs`.

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
  // x86_64 AVX2 + FMA path (`linear_to_srgb_avx2`): 8-wide chunks, then the
  // scalar FMA remainder loop.
  let end = start + len
  let avx2_end = start + len / 8 * 8
  for i in start..<avx2_end {
    samples[i] = linear_to_srgb_avx2_lane(samples[i])
  }
  for i in avx2_end..<end {
    samples[i] = linear_to_srgb_fma_scalar(samples[i])
  }
}

///|
/// One lane of the 8-wide loop of `linear_to_srgb_avx2`.
fn linear_to_srgb_avx2_lane(s : Float) -> Float {
  let bits = s.reinterpret_as_uint()
  let v = bits & 0x7fff_ffffU
  let v_adj = Float::reinterpret_from_uint((v | 0x3e80_0000U) & 0x3eff_ffffU)
  let pow : Float = 0.059914046
  let pow = mul_add_f32(pow, v_adj, -0.10889456)
  let pow = mul_add_f32(pow, v_adj, 0.107963754)
  let pow = mul_add_f32(pow, v_adj, 0.018092343)
  // `_mm256_shuffle_epi8` on `(v >> 23) - 118`: the low byte selects the
  // table entry, a set high bit selects zero; the upper bytes of the lane are
  // 0x00 or 0xff and select zero as well (both tables start with 0).
  let exp_idx = (v >> 23).reinterpret_as_int() - 118
  let byte0 = exp_idx & 0xff
  let (upper, lower) = if (byte0 & 0x80) != 0 {
    (0U, 0U)
  } else {
    (srgb_powtable_upper[byte0 & 0xf], srgb_powtable_lower[byte0 & 0xf])
  }
  let mul = (upper << 18) | (lower << 10) | 0x4000_0000U
  let v = Float::reinterpret_from_uint(v)
  let small = v * 12.92
  let acc = mul_add_f32(pow, Float::reinterpret_from_uint(mul), -0.055)
  let ret = if v <= 0.0031308 { small } else { acc }
  Float::reinterpret_from_uint(
    ret.reinterpret_as_uint() | (bits & 0x8000_0000U),
  )
}

///|
/// The scalar remainder loop of `linear_to_srgb_avx2` (uses `mul_add`).
fn linear_to_srgb_fma_scalar(s : Float) -> Float {
  let v = s.reinterpret_as_uint() & 0x7fff_ffffU
  let v_adj = Float::reinterpret_from_uint((v | 0x3e80_0000U) & 0x3eff_ffffU)
  let pow : Float = 0.059914046
  let pow = mul_add_f32(pow, v_adj, -0.10889456)
  let pow = mul_add_f32(pow, v_adj, 0.107963754)
  let pow = mul_add_f32(pow, v_adj, 0.018092343)
  let idx = ((v >> 23) - 118U).reinterpret_as_int() & 0xf
  let mul = 0x4000_0000U |
    (srgb_powtable_upper[idx] << 18) |
    (srgb_powtable_lower[idx] << 10)
  let v = Float::reinterpret_from_uint(v)
  let small = v * 12.92
  let acc = mul_add_f32(pow, Float::reinterpret_from_uint(mul), -0.055)
  copysign_f32(if v <= 0.0031308 { small } else { acc }, s)
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
  // Upstream has only the generic implementation of this function.
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
