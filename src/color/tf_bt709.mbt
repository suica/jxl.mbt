// Port of jxl-color `tf/bt709.rs` (generic implementation).

///|
/// Converts the linear samples with the BT.709 transfer curve.
pub fn linear_to_bt709(
  samples : FixedArray[Float],
  start~ : Int32 = 0,
  len~ : Int32 = samples.length() - start,
) -> Unit {
  for i in start..<(start + len) {
    let a = samples[i]
    samples[i] = if a <= 0.018 {
      4.5 * a
    } else {
      mul_add_f32(fast_powf_generic(a, 0.45), 1.099, -0.099)
    }
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
