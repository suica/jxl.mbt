///|
let delta_palette : FixedArray[Int32] = [
  0, 0, 0, 4, 4, 4, 11, 0, 0, 0, 0, -13, 0, -12, 0, -10, -10, -10, -18, -18, -18,
  -27, -27, -27, -18, -18, 0, 0, 0, -32, -32, 0, 0, -37, -37, -37, 0, -32, -32, 24,
  24, 45, 50, 50, 50, -45, -24, -24, -24, -45, -45, 0, -24, -24, -34, -34, 0, -24,
  0, -24, -45, -45, -24, 64, 64, 64, -32, 0, -32, 0, -32, 0, -32, 0, 32, -24, -45,
  -24, 45, 24, 45, 24, -24, -45, -45, -24, 24, 80, 80, 80, 64, 0, 0, 0, 0, -64, 0,
  -64, -64, -24, -24, 45, 96, 96, 96, 64, 64, 0, 45, -24, -24, 34, -34, 0, 112, 112,
  112, 24, -45, -45, 45, 45, -24, 0, -32, 32, 24, -24, 45, 0, 96, 96, 45, -24, 24,
  24, -45, -24, -24, -45, 24, 0, -64, 0, 96, 0, 0, 128, 128, 128, 64, 0, 64, 144,
  144, 144, 96, 96, 0, -36, -36, 36, 45, -24, -45, 45, -45, -24, 0, 0, -96, 0, 128,
  128, 0, 96, 0, 45, 24, -45, -128, 0, 0, 24, -45, 24, -45, 24, -45, 64, 0, -64,
  64, -64, -64, 96, 0, 96, 45, -45, 24, 24, 45, -45, 64, 64, -64, 128, 128, 0, 0,
  0, -128, -24, 45, -45,
]

///|
fn Palette::inverse_inner(
  self : Palette,
  palette : @grid.SubGrid[Int32],
  targets : Array[@grid.SubGrid[Int32]],
  bit_depth : Int32,
  sample : Sample,
) -> Unit {
  let narrow = sample is I16
  let nb_deltas = self.nb_deltas
  let nb_colors = self.nb_colours
  let index_grid = targets[0]
  let width = index_grid.width
  let height = index_grid.height
  let is_simple = for y in 0..<height {
    let off = index_grid.row_offset(y)
    let buf = index_grid.buf
    let mut ok = true
    for x in 0..<width {
      let index = buf[off + x]
      if index < 0 || index >= nb_colors {
        ok = false
        break
      }
    }
    if !ok {
      break false
    }
  } nobreak {
    true
  }
  if is_simple {
    return inverse_simple(palette, targets)
  }
  let need_delta : Array[(Int32, Int32)] = []
  let channels = targets.length()
  guard channels == palette.height else {
    abort("assertion failed: palette channel count")
  }
  // `(1i32 << bit_depth) - 1` and `1i32 << bit_depth.saturating_sub(3)`
  let max_value = (1 << (bit_depth & 31)) - 1
  let delta_shift = if bit_depth > 8 {
    (if bit_depth < 24 { bit_depth } else { 24 }) - 8
  } else {
    0
  }
  let base_offset = 1 << ((if bit_depth > 3 { bit_depth - 3 } else { 0 }) & 31)
  for y in 0..<height {
    for x in 0..<width {
      let index = index_grid.get(x, y)
      if index < nb_deltas {
        need_delta.push((x, y))
      }
      if index >= 0 && index < nb_colors {
        for c in 0..<channels {
          targets[c].set(x, y, palette.get(index, c))
        }
      } else if index >= nb_colors {
        let index = index - nb_colors
        if index < 64 {
          for c in 0..<channels {
            targets[c].set(
              x,
              y,
              wrap_s(
                narrow,
                (index >> ((2 * c) & 31)) % 4 * max_value / 4 + base_offset,
              ),
            )
          }
        } else {
          let mut index = index - 64
          for c in 0..<channels {
            targets[c].set(x, y, wrap_s(narrow, index % 5 * max_value / 4))
            index = index / 5
          }
        }
      } else {
        for c in 0..<channels {
          if c >= 3 {
            targets[c].set(x, y, 0)
            continue
          }
          let index = -(index + 1)
          let index = index % 143
          let mut temp_sample = delta_palette[((index + 1) >> 1) * 3 + c]
          if (index & 1) == 0 {
            temp_sample = -temp_sample
          }
          if bit_depth > 8 {
            temp_sample = temp_sample << delta_shift
          }
          targets[c].set(x, y, wrap_s(narrow, temp_sample))
        }
      }
    }
  }
  if need_delta.is_empty() {
    return
  }
  let d_pred = self.d_pred
  let wp_header = if d_pred == SelfCorrecting { self.wp_header } else { None }
  let predictor = PredictorState::new()
  for grid in targets {
    predictor.reset(width, [], wp_header)
    let mut idx = 0
    let buf = grid.buf
    let mut done = false
    for y in 0..<height {
      let off = grid.row_offset(y)
      for x in 0..<width {
        predictor.properties()
        let mut sample_value = buf[off + x]
        let (dx, dy) = need_delta[idx]
        if dx == x && dy == y {
          let diff = d_pred.predict(predictor)
          sample_value = sample_value + diff
          // `*sample = S::from_i32(sample_value)`; the untruncated value is
          // what gets recorded below, as upstream does.
          buf[off + x] = wrap_s(narrow, sample_value)
          idx += 1
          if idx >= need_delta.length() {
            done = true
            break
          }
        }
        predictor.record(sample_value)
      }
      if done {
        break
      }
    }
  }
}

///|
fn inverse_simple(
  palette : @grid.SubGrid[Int32],
  targets : Array[@grid.SubGrid[Int32]],
) -> Unit {
  let index_grid = targets[0]
  let height = index_grid.height
  let width = index_grid.width
  let channels = targets.length()
  guard channels == palette.height else {
    abort("assertion failed: palette channel count")
  }
  let ibuf = index_grid.buf
  let pbuf = palette.buf
  for c in 1..<channels {
    let grid = targets[c]
    let poff = palette.row_offset(c)
    let gbuf = grid.buf
    for y in 0..<height {
      let ioff = index_grid.row_offset(y)
      let goff = grid.row_offset(y)
      for x in 0..<width {
        gbuf[goff + x] = pbuf[poff + ibuf[ioff + x]]
      }
    }
  }
  let poff = palette.row_offset(0)
  for y in 0..<height {
    let ioff = index_grid.row_offset(y)
    for x in 0..<width {
      ibuf[ioff + x] = pbuf[poff + ibuf[ioff + x]]
    }
  }
}
