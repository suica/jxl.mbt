///|
/// Inverse RCT of type `ty` (0..=6) followed by the inverse channel
/// permutation, in place on three equally sized grids.
fn inverse_rct(
  ty : Int32,
  permutation : Int32,
  ga : @grid.SubGrid[Int32],
  gb : @grid.SubGrid[Int32],
  gc : @grid.SubGrid[Int32],
) -> Unit {
  let width = ga.width
  let height = ga.height
  guard width == gb.width &&
    width == gc.width &&
    height == gb.height &&
    height == gc.height else {
    abort("assertion failed: RCT grid size mismatch")
  }
  if width == 0 || height == 0 {
    return
  }
  let ba = ga.buf
  let bb = gb.buf
  let bc = gc.buf
  for y in 0..<height {
    let oa = ga.row_offset(y)
    let ob = gb.row_offset(y)
    let oc = gc.row_offset(y)
    for x in 0..<width {
      let a = ba[oa + x]
      let b = bb[ob + x]
      let c = bc[oc + x]
      let mut d = 0
      let mut e = 0
      let mut f = 0
      if ty == 6 {
        let tmp = a - (c >> 1)
        e = c + tmp
        f = tmp - (b >> 1)
        d = f + b
      } else {
        d = a
        f = if (ty & 1) != 0 { c + a } else { c }
        e = if ty >> 1 == 1 {
          b + a
        } else if ty >> 1 == 2 {
          b + ((a + f) >> 1)
        } else {
          b
        }
      }
      // inverse_permute
      let (ra, rb, rc) = match permutation {
        1 => (f, d, e)
        2 => (e, f, d)
        3 => (d, f, e)
        4 => (e, d, f)
        5 => (f, e, d)
        _ => (d, e, f)
      }
      ba[oa + x] = ra
      bb[ob + x] = rb
      bc[oc + x] = rc
    }
  }
}
