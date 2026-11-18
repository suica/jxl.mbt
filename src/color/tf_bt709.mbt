// Port of jxl-color `tf/bt709.rs`.

///|
/// Converts the linear samples with the BT.709 transfer curve.
pub fn linear_to_bt709(
  samples : FixedArray[Float],
  start~ : Int32 = 0,
  len~ : Int32 = samples.length() - start,
) -> Unit {
  // x86_64 AVX2 + FMA path: 8-wide chunks, then one 4-wide FMA chunk, then
  // the generic code for the last (< 4) samples.
  let end = start + len
  let simd_end = start + len / 8 * 8 + (if len % 8 >= 4 { 4 } else { 0 })
  for i in start..<simd_end {
    let a = samples[i]
    samples[i] = if a <= 0.018 {
      a * 4.5
    } else {
      mul_add_f32(fast_powf_fma(a, 0.45), 1.099, -0.099)
    }
  }
  for i in simd_end..<end {
    samples[i] = linear_to_bt709_generic(samples[i])
  }
}

///|
/// The generic loop body of `linear_to_bt709`.
fn linear_to_bt709_generic(a : Float) -> Float {
  if a <= 0.018 {
    4.5 * a
  } else {
    mul_add_f32(fast_powf_generic(a, 0.45), 1.099, -0.099)
  }
}

///|
/// Converts samples in BT.709 transfer curve to linear.
pub fn bt709_to_linear(
  samples : FixedArray[Float],
  start~ : Int32 = 0,
  len~ : Int32 = samples.length() - start,
) -> Unit {
  for i in start..<(start + len) {
    let a = samples[i]
    samples[i] = if a <= 0.081 {
      a / 4.5
    } else {
      fast_powf_generic(mul_add_f32(a, 1.0 / 1.099, 0.099 / 1.099), 1.0 / 0.45)
    }
  }
}
