// Port of jxl-render features/noise.rs (noise synthesis).

///|
/// Padding for 5x5 kernel convolution step
let noise_padding : Int32 = 2

///|
/// `features::render_noise`: adds noise to the colour channels of `grid`.
fn render_noise(
  header : @frame.FrameHeader,
  visible_frames_num : Int32,
  invisible_frames_num : Int32,
  base_correlations_xb : (Float, Float)?,
  grid : ImageWithRegion,
  params : @frame.NoiseParameters,
  pool~ : @threadpool.JxlThreadPool = @threadpool.JxlThreadPool::none(),
) -> Unit raise @bitstream.JxlError {
  let (region, shift) = grid.regions_and_shifts()[0]
  let tracker = grid.alloc_tracker()
  let xyb = grid.as_color_floats_mut()
  let full_frame_region = Region::with_size(header.width, header.height)
  let actual_region = region
    .intersection(full_frame_region)
    .downsample_with_shift(shift)
  render_noise_raw(
    header.width,
    header.height,
    header.group_dim(),
    visible_frames_num,
    invisible_frames_num,
    base_correlations_xb,
    xyb[0],
    xyb[1],
    xyb[2],
    actual_region.left,
    actual_region.top,
    actual_region.width,
    actual_region.height,
    params.lut,
    tracker,
    pool,
  )
}

///|
/// `render_noise` on plain values.
///
/// - `frame_width`/`frame_height`/`group_dim`: from the frame header (the
///   dimensions after upsampling, see `init_noise`).
/// - `grid_x`/`grid_y`/`grid_b`: the colour channels of the image, whose
///   sample (0, 0) is frame pixel (`left`, `top`).
/// - `left`/`top`/`width`/`height`: `actual_region`, i.e. the image region
///   intersected with the frame and downsampled with the channel shift.
/// - `lut`: `NoiseParameters::lut` (8 values).
fn render_noise_raw(
  frame_width : Int32,
  frame_height : Int32,
  group_dim : Int32,
  visible_frames_num : Int32,
  invisible_frames_num : Int32,
  base_correlations_xb : (Float, Float)?,
  grid_x : @grid.Grid[Float],
  grid_y : @grid.Grid[Float],
  grid_b : @grid.Grid[Float],
  left : Int32,
  top : Int32,
  width : Int32,
  height : Int32,
  lut : FixedArray[Float],
  tracker : @grid.AllocTracker?,
  pool : @threadpool.JxlThreadPool,
) -> Unit raise @bitstream.JxlError {
  let (corr_x, corr_b) = match base_correlations_xb {
    Some(v) => v
    None => ((0.0 : Float), (1.0 : Float))
  }
  let noise_buffer = init_noise(
    visible_frames_num, invisible_frames_num, frame_width, frame_height, group_dim,
    tracker, pool,
  )
  let lut9 = FixedArray::make(9, (0.0 : Float))
  for i in 0..<8 {
    lut9[i] = lut[i]
  }
  lut9[8] = lut[7]
  let bx = grid_x.buf
  let by = grid_y.buf
  let bb = grid_b.buf
  let nxb = noise_buffer[0].buf
  let nyb = noise_buffer[1].buf
  let nbb = noise_buffer[2].buf
  let nstride = noise_buffer[0].width
  for fy in 0..<height {
    let y = fy + top
    let row_x = fy * grid_x.width
    let row_y = fy * grid_y.width
    let row_b = fy * grid_b.width
    let row_noise = y * nstride
    for fx in 0..<width {
      let x = fx + left
      let gx = bx[row_x + fx]
      let gy = by[row_y + fx]
      let noise_x = nxb[row_noise + x]
      let noise_y = nyb[row_noise + x]
      let noise_b = nbb[row_noise + x]
      let in_x = gx + gy
      let in_y = gy - gx
      let in_scaled_x = noise_fmax0(in_x * 3.0)
      let in_scaled_y = noise_fmax0(in_y * 3.0)
      let in_x_int = noise_min7(in_scaled_x.to_int())
      let in_x_frac = in_scaled_x - Float::from_int(in_x_int)
      let in_y_int = noise_min7(in_scaled_y.to_int())
      let in_y_frac = in_scaled_y - Float::from_int(in_y_int)
      let sx = (lut9[in_x_int + 1] - lut9[in_x_int]) * in_x_frac +
        lut9[in_x_int]
      let sy = (lut9[in_y_int + 1] - lut9[in_y_int]) * in_y_frac +
        lut9[in_y_int]
      let nx : Float = 0.22 * sx * (0.0078125 * noise_x + 0.9921875 * noise_b)
      let ny : Float = 0.22 * sy * (0.0078125 * noise_y + 0.9921875 * noise_b)
      bx[row_x + fx] = bx[row_x + fx] + (corr_x * (nx + ny) + nx - ny)
      by[row_y + fx] = by[row_y + fx] + (nx + ny)
      bb[row_b + fx] = bb[row_b + fx] + corr_b * (nx + ny)
    }
  }
  if tracker is Some(t) {
    for g in noise_buffer {
      t.free(g.width * g.height, 4)
    }
  }
}

///|
/// `f32::max(0.0, v)` (NaN yields 0.0).
fn noise_fmax0(v : Float) -> Float {
  if v > 0.0 {
    v
  } else {
    0.0
  }
}

///|
fn noise_min7(v : Int32) -> Int32 {
  if v < 7 {
    v
  } else {
    7
  }
}

///|
/// Generates the convolved noise images of the whole frame, one per channel.
fn init_noise(
  visible_frames : Int32,
  invisible_frames : Int32,
  frame_width : Int32,
  frame_height : Int32,
  group_dim : Int32,
  tracker : @grid.AllocTracker?,
  pool : @threadpool.JxlThreadPool,
) -> Array[@grid.Grid[Float]] raise @bitstream.JxlError {
  let seed0 = rng_seed0(visible_frames, invisible_frames)

  // We use header.width and header.height because
  // these are the dimensions after upsampling (the "actual" frame size),
  // and noise synthesis is done after upsampling.
  let width = frame_width
  let height = frame_height
  let groups_per_row = (width + group_dim - 1) / group_dim
  let num_groups = groups_per_row * ((height + group_dim - 1) / group_dim)
  let noise_groups : Array[NoiseGroup] = []
  for group_idx in 0..<num_groups {
    let group_x = group_idx % groups_per_row
    let group_y = group_idx / groups_per_row
    let x0 = group_x * group_dim
    let y0 = group_y * group_dim
    let seed1 = rng_seed1(x0, y0)
    let group_width = if group_dim < width - x0 {
      group_dim
    } else {
      width - x0
    }
    let group_height = if group_dim < height - y0 {
      group_dim
    } else {
      height - y0
    }
    noise_groups.push(
      NoiseGroup::new(group_width, group_height, seed0, seed1, tracker),
    )
  }
  let convolved = [
    @grid.Grid::with_alloc_tracker(width, height, (0.0 : Float), tracker),
    @grid.Grid::with_alloc_tracker(width, height, (0.0 : Float), tracker),
    @grid.Grid::with_alloc_tracker(width, height, (0.0 : Float), tracker),
  ]

  // Each channel is convolved by the 5×5 kernel
  let jobs : Array[(@grid.SubGrid[Float], FixedArray[@grid.SubGrid[Float]?])] = []
  for channel_idx in 0..<3 {
    let out = convolved[channel_idx]
    let groups = out.as_subgrid().into_groups(group_dim, group_dim)
    for group_idx, out_subgrid in groups {
      let group_x = group_idx % groups_per_row
      let group_y = group_idx / groups_per_row
      // `adjacent_groups[4] == this`
      let adjacent_groups : FixedArray[@grid.SubGrid[Float]?] = FixedArray::make(
        9,
        None,
      )
      for idx in 0..<9 {
        let x = group_x + idx % 3 - 1
        let y = group_y + idx / 3 - 1
        if x >= 0 && y >= 0 && x < groups_per_row {
          let gi = y * groups_per_row + x
          if gi < noise_groups.length() {
            adjacent_groups[idx] = Some(
              noise_groups[gi].as_subgrid(channel_idx),
            )
          }
        }
      }
      jobs.push((out_subgrid, adjacent_groups))
    }
  }
  // Every job runs; the error of a failed job is kept (the last one wins).
  let mut result : @bitstream.JxlError? = None
  pool.for_each_vec(jobs, job => {
    let (out_subgrid, adjacent_groups) = job
    convolve_fill(out_subgrid, adjacent_groups, tracker) catch {
      e => result = Some(e)
    }
  })
  // The noise groups are dropped here upstream, returning their memory.
  if tracker is Some(t) {
    for g in noise_groups {
      t.free(g.stride * g.height * 3, 4)
    }
  }
  if result is Some(e) {
    raise e
  }
  convolved
}

///|
/// Seed for `XorShift128Plus` from the number of ‘visible’ frames decoded so far
/// and the number of ‘invisible’ frames since the previous visible frame.
fn rng_seed0(visible_frames : Int32, invisible_frames : Int32) -> UInt64 {
  (visible_frames.to_uint64() << 32) + invisible_frames.to_uint64()
}

///|
/// Seed for `XorShift128Plus` from the coordinates of the top-left pixel of the
/// group within the frame.
fn rng_seed1(x0 : Int32, y0 : Int32) -> UInt64 {
  (x0.to_uint64() << 32) + y0.to_uint64()
}

///|
priv struct NoiseGroup {
  buf : FixedArray[FixedArray[Float]]
  width : Int32
  height : Int32
  stride : Int32
}

///|
fn NoiseGroup::new(
  width : Int32,
  height : Int32,
  seed0 : UInt64,
  seed1 : UInt64,
  tracker : @grid.AllocTracker?,
) -> NoiseGroup raise @bitstream.JxlError {
  let width_n2 = (width + noise_n * 2 - 1) / (noise_n * 2)
  let stride = width_n2 * noise_n * 2
  let elems = stride * height * 3
  if tracker is Some(t) {
    t.alloc(elems, 4)
  }
  let rng = XorShift128Plus::new(seed0, seed1)
  let buf : FixedArray[FixedArray[Float]] = FixedArray::make(3, [])
  let num_iters = width_n2 * height
  let bits = FixedArray::make(noise_n * 2, (0 : UInt32))
  for c in 0..<3 {
    let b = FixedArray::make(num_iters * noise_n * 2, (0.0 : Float))
    for i in 0..<num_iters {
      rng.get_u32_bits(bits)
      for j in 0..<(noise_n * 2) {
        b[i * noise_n * 2 + j] = Float::reinterpret_from_uint(
          (bits[j] >> 9) | 0x3f800000,
        )
      }
    }
    buf[c] = b
  }
  { buf, width, height, stride, }
}

///|
fn NoiseGroup::as_subgrid(
  self : NoiseGroup,
  channel_idx : Int32,
) -> @grid.SubGrid[Float] {
  @grid.SubGrid::from_buf(
    self.buf[channel_idx],
    0,
    self.width,
    self.height,
    self.stride,
  )
}

///|
/// Offset of row `y` of `g` in its buffer.
fn noise_row(g : @grid.SubGrid[Float], y : Int32) -> Int32 {
  guard y >= 0 && y < g.height else { abort("noise: row out of bounds") }
  g.offset + y * g.stride
}

///|
fn convolve_fill(
  out : @grid.SubGrid[Float],
  adjacent_groups : FixedArray[@grid.SubGrid[Float]?],
  tracker : @grid.AllocTracker?,
) -> Unit raise @bitstream.JxlError {
  let this = adjacent_groups[4].unwrap()
  let width = out.width
  let height = out.height
  guard this.width == width && this.height == height else {
    abort("noise: group size mismatch")
  }
  let rows = @grid.Grid::with_alloc_tracker(
    width + noise_padding * 2,
    1 + noise_padding * 2,
    (0.0 : Float),
    tracker,
  )
  let input_width = rows.width
  let rbuf = rows.buf
  if adjacent_groups[1] is Some(c) {
    let l = adjacent_groups[0]
    let r = adjacent_groups[2]
    for offset_y in -2..<0 {
      fill_padded_row(
        rbuf,
        (2 + offset_y) * input_width,
        input_width,
        c,
        c.height + offset_y,
        l.map(fn(l) { (l, l.height + offset_y) }),
        r.map(fn(r) { (r, r.height + offset_y) }),
      )
    }
  } else if height >= 2 {
    let c = this
    let l = adjacent_groups[3]
    let r = adjacent_groups[5]
    for offset_y in -2..<0 {
      let y = -(offset_y + 1)
      fill_padded_row(
        rbuf,
        (2 + offset_y) * input_width,
        input_width,
        c,
        y,
        l.map(fn(l) { (l, y) }),
        r.map(fn(r) { (r, y) }),
      )
    }
  } else {
    let c = this
    let l = adjacent_groups[3]
    let r = adjacent_groups[5]
    for y in 0..<2 {
      fill_padded_row(
        rbuf,
        y * input_width,
        input_width,
        c,
        0,
        l.map(fn(l) { (l, 0) }),
        r.map(fn(r) { (r, 0) }),
      )
    }
  }
  for y in 0..<3 {
    fill_once(rbuf, (2 + y) * input_width, input_width, y, adjacent_groups)
  }
  let obuf = out.buf
  for y in 0..<height {
    let center_y = (y + 2) % 5
    let orow = out.offset + y * out.stride
    for x in 0..<width {
      let mut sum : Float = 0.0
      for dy in 0..<5 {
        let input_row = dy * input_width
        for dx in 0..<5 {
          sum = sum + rbuf[input_row + x + dx] * 0.16
        }
      }
      obuf[orow + x] = sum - rbuf[center_y * input_width + x + 2] * 4.0
    }
    if y != height - 1 {
      let next_y = y + 3
      let fill_y = (next_y + 2) % 5
      fill_once(
        rbuf,
        fill_y * input_width,
        input_width,
        next_y,
        adjacent_groups,
      )
    }
  }
  if tracker is Some(t) {
    t.free(rows.width * rows.height, 4)
  }
}

///|
fn fill_once(
  out : FixedArray[Float],
  out_off : Int32,
  out_len : Int32,
  fill_y : Int32,
  adjacent_groups : FixedArray[@grid.SubGrid[Float]?],
) -> Unit {
  let this = adjacent_groups[4].unwrap()
  let height = this.height
  let (source_y, c, l, r) = if fill_y >= height {
    (
      fill_y - height,
      adjacent_groups[7],
      adjacent_groups[6],
      adjacent_groups[8],
    )
  } else {
    (fill_y, adjacent_groups[4], adjacent_groups[3], adjacent_groups[5])
  }
  let (source_y, c, l, r) = match c {
    Some(c) => (source_y, c, l, r)
    None =>
      if source_y <= height - 1 {
        (height - 1 - source_y, this, adjacent_groups[3], adjacent_groups[5])
      } else {
        let dy = source_y - height + 1
        match adjacent_groups[1] {
          Some(c) => (c.height - dy, c, adjacent_groups[0], adjacent_groups[2])
          None => (0, this, adjacent_groups[3], adjacent_groups[5])
        }
      }
  }
  fill_padded_row(
    out,
    out_off,
    out_len,
    c,
    source_y,
    l.map(fn(l) { (l, source_y) }),
    r.map(fn(r) { (r, source_y) }),
  )
}

///|
/// `fill_padded_row`: `this`, `left` and `right` are rows given as a grid and
/// a row index.
fn fill_padded_row(
  out : FixedArray[Float],
  out_off : Int32,
  out_len : Int32,
  this : @grid.SubGrid[Float],
  this_y : Int32,
  left : (@grid.SubGrid[Float], Int32)?,
  right : (@grid.SubGrid[Float], Int32)?,
) -> Unit {
  let this_len = this.width
  guard out_len == this_len + noise_padding * 2 else {
    abort("noise: padded row length mismatch")
  }
  let tb = this.buf
  let trow = noise_row(this, this_y)
  match left {
    Some((l, ly)) => {
      let lrow = noise_row(l, ly)
      out[out_off] = l.buf[lrow + l.width - 2]
      out[out_off + 1] = l.buf[lrow + l.width - 1]
    }
    None =>
      if this_len >= noise_padding {
        out[out_off] = tb[trow + 1]
        out[out_off + 1] = tb[trow]
      } else {
        out[out_off] = tb[trow]
        out[out_off + 1] = tb[trow]
      }
  }
  for i in 0..<this_len {
    out[out_off + 2 + i] = tb[trow + i]
  }
  match right {
    Some((r, ry)) => {
      let rrow = noise_row(r, ry)
      if r.width >= noise_padding {
        out[out_off + out_len - 2] = r.buf[rrow]
        out[out_off + out_len - 1] = r.buf[rrow + 1]
      } else {
        out[out_off + out_len - 2] = r.buf[rrow]
        out[out_off + out_len - 1] = r.buf[rrow]
      }
    }
    None => {
      out[out_off + out_len - 2] = out[out_off + out_len - 3]
      out[out_off + out_len - 1] = out[out_off + out_len - 4]
    }
  }
}

///|
let noise_n : Int32 = 8

///|
/// Shift-register pseudo-random number generator
priv struct XorShift128Plus {
  s0 : FixedArray[UInt64]
  s1 : FixedArray[UInt64]
}

///|
/// Initialize a new XorShift128+ PRNG.
fn XorShift128Plus::new(seed0 : UInt64, seed1 : UInt64) -> XorShift128Plus {
  let s0 = FixedArray::make(noise_n, 0UL)
  let s1 = FixedArray::make(noise_n, 0UL)
  s0[0] = split_mix_64(seed0 + 0x9E3779B97F4A7C15UL)
  s1[0] = split_mix_64(seed1 + 0x9E3779B97F4A7C15UL)
  for i in 1..<noise_n {
    s0[i] = split_mix_64(s0[i - 1])
    s1[i] = split_mix_64(s1[i - 1])
  }
  { s0, s1, }
}

///|
/// Writes N * 2 `u32` pseudorandom numbers into `out` (the little-endian
/// halves of each `u64` of the batch, low half first).
fn XorShift128Plus::get_u32_bits(
  self : XorShift128Plus,
  out : FixedArray[UInt32],
) -> Unit {
  for i in 0..<noise_n {
    let v = self.next_u64(i)
    out[2 * i] = v.to_uint()
    out[2 * i + 1] = (v >> 32).to_uint()
  }
}

///|
/// One lane of `fill_batch`.
fn XorShift128Plus::next_u64(self : XorShift128Plus, i : Int32) -> UInt64 {
  let mut s1 = self.s0[i]
  let s0 = self.s1[i]
  let ret = s1 + s0
  self.s0[i] = s0
  s1 = s1 ^ (s1 << 23)
  self.s1[i] = s1 ^ (s0 ^ (s1 >> 18) ^ (s0 >> 5))
  ret
}

///|
/// Pseudo-random number generator used to calculate initial state of
/// `XorShift128Plus`
fn split_mix_64(z : UInt64) -> UInt64 {
  let z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL
  let z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL
  z ^ (z >> 31)
}
