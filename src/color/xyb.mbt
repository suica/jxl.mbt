// Port of jxl-color `xyb.rs` (generic implementation).

///|
/// Converts XYB samples to (scaled) linear mixed LMS samples, in place.
///
/// `ob` is the opsin bias. Panics if the channel lengths differ.
fn xyb_run(
  x : FixedArray[Float],
  y : FixedArray[Float],
  b : FixedArray[Float],
  ob : FixedArray[Float],
  intensity_target : Float,
  start~ : Int32 = 0,
  len~ : Int32 = x.length() - start,
) -> Unit {
  let itscale = (255.0 : Float) / intensity_target
  if x.length() != y.length() || y.length() != b.length() {
    abort("Grid size mismatch")
  }
  let ob0 = ob[0]
  let ob1 = ob[1]
  let ob2 = ob[2]
  let cbrt_ob0 = @math.cbrtf(ob0)
  let cbrt_ob1 = @math.cbrtf(ob1)
  let cbrt_ob2 = @math.cbrtf(ob2)
  for i in start..<(start + len) {
    let xv = x[i]
    let yv = y[i]
    // matrix: [1, 1, 0, -1, 1, 0, 0, 0, 1]
    let g_l = yv + xv
    let g_m = yv - xv
    let g_s = b[i]

    // bias: -cbrt_ob
    let g_l = g_l - cbrt_ob0
    let g_m = g_m - cbrt_ob1
    let g_s = g_s - cbrt_ob2

    // inverse tf: gamma3, bias: ob, matrix: id * itscale
    x[i] = mul_add_f32(g_l * g_l, g_l, ob0) * itscale
    y[i] = mul_add_f32(g_m * g_m, g_m, ob1) * itscale
    b[i] = mul_add_f32(g_s * g_s, g_s, ob2) * itscale
  }
}
