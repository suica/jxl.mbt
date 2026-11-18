// Port of jxl-color `ycbcr.rs` (generic implementation).

///|
/// Applies transform from YCbCr to RGB.
///
/// Channels are expected to be in CbYCr order; after the call they hold R, G, B.
/// Panics if the channel lengths differ.
pub fn ycbcr_to_rgb(
  cb : FixedArray[Float],
  y : FixedArray[Float],
  cr : FixedArray[Float],
  start~ : Int32 = 0,
  len~ : Int32 = cb.length() - start,
) -> Unit {
  if cb.length() != y.length() || y.length() != cr.length() {
    abort("Grid size mismatch")
  }
  let y_bias : Float = 128.0 / 255.0
  let g_cb : Float = -0.114 * 1.772 / 0.587
  let g_cr : Float = -0.299 * 1.402 / 0.587
  for i in start..<(start + len) {
    let cbv = cb[i]
    let yv = y[i] + y_bias
    let crv = cr[i]
    cb[i] = mul_add_f32(crv, 1.402, yv)
    y[i] = mul_add_f32(cbv, g_cb, mul_add_f32(crv, g_cr, yv))
    cr[i] = mul_add_f32(cbv, 1.772, yv)
  }
}
