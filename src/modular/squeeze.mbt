///|
/// Inverse horizontal squeeze. The left half (rounded up) of each row holds
/// the averages and the right half the residuals.
fn inverse_h(merged : @grid.SubGrid[Int32]) -> Unit {
  let height = merged.height
  let width = merged.width
  if width == 0 {
    return
  }
  let buf = merged.buf
  let scratch = FixedArray::make(width, 0)
  let avg_width = div_ceil(width, 2)
  let pairs = width / 2
  for y in 0..<height {
    let off = merged.row_offset(y)
    FixedArray::blit_to(buf, scratch, len=width, src_offset=off)
    let mut avg = scratch[0]
    let mut left = avg
    for x in 0..<pairs {
      let residu = scratch[avg_width + x]
      let next_avg = if x + 1 < avg_width { scratch[x + 1] } else { avg }
      let diff = residu + tendency_i32(left, avg, next_avg)
      let first = avg + diff / 2
      let second = first - diff
      buf[off + 2 * x] = first
      buf[off + 2 * x + 1] = second
      avg = next_avg
      left = second
    }
    if width % 2 == 1 {
      buf[off + width - 1] = scratch[avg_width - 1]
    }
  }
}

///|
/// Inverse vertical squeeze. The top half (rounded up) holds the averages and
/// the bottom half the residuals.
fn inverse_v(merged : @grid.SubGrid[Int32]) -> Unit {
  let width = merged.width
  let height = merged.height
  if height == 0 {
    return
  }
  let buf = merged.buf
  let stride = merged.stride
  let avg_height = div_ceil(height, 2)
  let residu_height = height / 2
  // Process whole rows at a time (same result as upstream's column loop).
  let scratch = FixedArray::make(height * width, 0)
  for y in 0..<height {
    FixedArray::blit_to(
      buf,
      scratch,
      len=width,
      src_offset=merged.row_offset(y),
      dst_offset=y * width,
    )
  }
  let avg = FixedArray::make(width, 0)
  let top = FixedArray::make(width, 0)
  for x in 0..<width {
    avg[x] = scratch[x]
    top[x] = scratch[x]
  }
  let base = merged.offset
  for y in 0..<residu_height {
    let residu_off = (avg_height + y) * width
    let has_next = y + 1 < avg_height
    let next_off = (y + 1) * width
    let out0 = base + 2 * y * stride
    let out1 = out0 + stride
    for x in 0..<width {
      let a = avg[x]
      let next_avg = if has_next { scratch[next_off + x] } else { a }
      let diff = scratch[residu_off + x] + tendency_i32(top[x], a, next_avg)
      let first = a + diff / 2
      let second = first - diff
      buf[out0 + x] = first
      buf[out1 + x] = second
      avg[x] = next_avg
      top[x] = second
    }
  }
  if height % 2 == 1 {
    let src = (avg_height - 1) * width
    let dst = merged.row_offset(height - 1)
    for x in 0..<width {
      buf[dst + x] = scratch[src + x]
    }
  }
}

///|
#inline
fn tendency_i32(a : Int32, b : Int32, c : Int32) -> Int32 {
  if a >= b && b >= c {
    let mut x = (4 * a - 3 * c - b + 6) / 12
    if x - (x & 1) > 2 * (a - b) {
      x = 2 * (a - b) + 1
    }
    if x + (x & 1) > 2 * (b - c) {
      x = 2 * (b - c)
    }
    x
  } else if a <= b && b <= c {
    let mut x = (4 * a - 3 * c - b - 6) / 12
    if x + (x & 1) < 2 * (a - b) {
      x = 2 * (a - b) - 1
    }
    if x - (x & 1) < 2 * (b - c) {
      x = 2 * (b - c)
    }
    x
  } else {
    0
  }
}
