// Port of jxl-oxide/src/fb.rs: frame buffers and image streams.

///|
/// Frame buffer representing a decoded image.
pub struct FrameBuffer {
  priv width : Int32
  priv height : Int32
  priv channels : Int32
  priv buf : FixedArray[Float]
}

///|
/// Creates a new framebuffer with given dimension.
///
/// Note that framebuffer allocations are not tracked.
pub fn FrameBuffer::new(
  width : Int32,
  height : Int32,
  channels : Int32,
) -> FrameBuffer {
  let len = FrameBuffer::buffer_len(width, height, channels)
  { width, height, channels, buf: FixedArray::make(len, 0.0), }
}

///|
fn FrameBuffer::buffer_len(
  width : Int32,
  height : Int32,
  channels : Int32,
) -> Int32 {
  let len = width.to_int64() * height.to_int64() * channels.to_int64()
  if width < 0 || height < 0 || channels < 0 || len > 0x7fffffffL {
    abort("framebuffer dimensions overflow")
  }
  len.to_int()
}

///|
/// Reads the sample at (x, y) as a float, 0 when out of the grid
/// (upstream `try_get_ref(..).unwrap_or(0)` followed by
/// `parse_integer_sample` for integer buffers).
fn sample_f32(
  g : @render.ImageBuffer,
  x : Int32,
  y : Int32,
  bit_depth : @image.BitDepth,
) -> Float {
  match g {
    F32(g) => if x < g.width() && y < g.height() { g.get(x, y) } else { 0.0 }
    I32(g) => {
      let v = if x < g.width() && y < g.height() { g.get(x, y) } else { 0 }
      bit_depth.parse_integer_sample(v)
    }
  }
}

///|
/// For internal use only.
pub fn FrameBuffer::from_grids(
  grids : ArrayView[@render.ImageBuffer],
  bit_depth : ArrayView[@image.BitDepth],
  grid_regions : ArrayView[@render.Region],
  copy_region : @render.Region,
  orientation : Int32,
) -> FrameBuffer {
  let channels = grids.length()
  if channels == 0 {
    abort("framebuffer should have channels")
  }
  if orientation < 1 || orientation > 8 {
    abort("Invalid orientation \{orientation}")
  }
  let { left, top, width, height, } = copy_region
  let (outw, outh) = if orientation <= 4 {
    (width, height)
  } else {
    (height, width)
  }
  let out = FrameBuffer::new(outw, outh, channels)
  let buf = out.buf
  // zip over grids and regions stops at the shortest
  let nch = if grid_regions.length() < channels {
    grid_regions.length()
  } else {
    channels
  }
  for y in 0..<height {
    for x in 0..<width {
      let (outx, outy) = match orientation {
        1 => (x, y)
        2 => (width - x - 1, y)
        3 => (width - x - 1, height - y - 1)
        4 => (x, height - y - 1)
        5 => (y, x)
        6 => (height - y - 1, x)
        7 => (height - y - 1, width - x - 1)
        _ => (y, width - x - 1)
      }
      let base = (outx + outy * outw) * channels
      for c in 0..<nch {
        let g = grids[c]
        let region = grid_regions[c]
        let idx = c + base
        let sx = x + (left - region.left)
        let sy = y + (top - region.top)
        if sx < 0 || sy < 0 || sx >= region.width || sy >= region.height {
          buf[idx] = 0.0
          continue
        }
        buf[idx] = sample_f32(g, sx, sy, bit_depth[c])
      }
    }
  }
  out
}

///|
/// Returns the width of the frame buffer.
pub fn FrameBuffer::width(self : FrameBuffer) -> Int32 {
  self.width
}

///|
/// Returns the height of the frame buffer.
pub fn FrameBuffer::height(self : FrameBuffer) -> Int32 {
  self.height
}

///|
/// Returns the number of channels of the frame buffer.
pub fn FrameBuffer::channels(self : FrameBuffer) -> Int32 {
  self.channels
}

///|
/// Returns the contents of frame buffer.
///
/// The buffer has length of `width * height * channels`, where
/// `n * channels + c`-th sample belongs to the `c`-th channel. The array is
/// shared with the frame buffer (upstream `buf` and `buf_mut`).
pub fn FrameBuffer::buf(self : FrameBuffer) -> FixedArray[Float] {
  self.buf
}

///|
/// Returns the mutable contents of frame buffer (same array as `buf`).
pub fn FrameBuffer::buf_mut(self : FrameBuffer) -> FixedArray[Float] {
  self.buf
}

///|
/// Returns the contents of frame buffer, grouped by pixels.
///
/// Panics if `n != self.channels()`.
pub fn FrameBuffer::buf_grouped(
  self : FrameBuffer,
  n : Int32,
) -> Array[FixedArray[Float]] {
  guard self.channels == n else { abort("assertion failed: channels == \{n}") }
  let grouped_len = FrameBuffer::buffer_len(self.width, self.height, 1)
  Array::makei(grouped_len, fn(i) {
    FixedArray::makei(n, fn(c) { self.buf[i * n + c] })
  })
}

///|
/// Image stream that writes to a caller's buffer.
pub struct ImageStream {
  priv orientation : Int32
  priv width : Int32
  priv height : Int32
  priv grids : Array[@render.ImageBuffer]
  priv start_offset_xy : Array[(Int32, Int32)]
  priv bit_depth : Array[@image.BitDepth]
  priv spot_colors : Array[ImageStreamSpotColor]
  priv mut y : Int32
  priv mut x : Int32
  priv mut c : Int32
}

///|
priv struct ImageStreamSpotColor {
  grid : @render.ImageBuffer
  start_offset_xy : (Int32, Int32)
  bit_depth : @image.BitDepth
  rgb : (Float, Float, Float)
  solidity : Float
}

///|
fn ImageStream::from_render(render : Render, skip_alpha : Bool) -> ImageStream {
  let orientation = render.orientation
  guard orientation >= 1 && orientation <= 8 else {
    abort("Invalid orientation \{orientation}")
  }
  let { left, top, width, height, } = render.target_frame_region
  let (width, height) = if orientation >= 5 {
    (height, width)
  } else {
    (width, height)
  }
  let fb = render.image.buffer()
  let color_channels = render.image.color_channels
  let regions_and_shifts = render.image.regions_and_shifts()
  let grids = Array::from_iter(render.color_channels().iter())
  let bit_depth = Array::make(grids.length(), render.color_bit_depth)
  let start_offset_xy = []
  for i in 0..<color_channels {
    let (region, _) = regions_and_shifts[i]
    start_offset_xy.push((left - region.left, top - region.top))
  }
  let num_ec = @cmp.minimum(
    render.extra_channels.length(),
    regions_and_shifts.length() - color_channels,
  )

  // Find black
  if render.is_cmyk {
    for ec_idx in 0..<num_ec {
      let ec = render.extra_channels[ec_idx]
      let (region, _) = regions_and_shifts[color_channels + ec_idx]
      if ec.is_black() {
        grids.push(fb[color_channels + ec_idx])
        bit_depth.push(ec.bit_depth)
        start_offset_xy.push((left - region.left, top - region.top))
        break
      }
    }
  }

  // Find alpha
  if !skip_alpha {
    for ec_idx in 0..<num_ec {
      let ec = render.extra_channels[ec_idx]
      let (region, _) = regions_and_shifts[color_channels + ec_idx]
      if ec.is_alpha() {
        grids.push(fb[color_channels + ec_idx])
        bit_depth.push(ec.bit_depth)
        start_offset_xy.push((left - region.left, top - region.top))
        break
      }
    }
  }
  let spot_colors = []
  if render.render_spot_color && color_channels == 3 {
    for ec_idx in 0..<num_ec {
      let ec = render.extra_channels[ec_idx]
      let (region, _) = regions_and_shifts[color_channels + ec_idx]
      if ec.ty is SpotColour(red~, green~, blue~, solidity~) {
        spot_colors.push({
          grid: fb[color_channels + ec_idx],
          start_offset_xy: (left - region.left, top - region.top),
          bit_depth: ec.bit_depth,
          rgb: (red, green, blue),
          solidity,
        })
      }
    }
  }
  {
    orientation,
    width,
    height,
    grids,
    bit_depth,
    start_offset_xy,
    spot_colors,
    y: 0,
    x: 0,
    c: 0,
  }
}

///|
/// Returns width of the image.
pub fn ImageStream::width(self : ImageStream) -> Int32 {
  self.width
}

///|
/// Returns height of the image.
pub fn ImageStream::height(self : ImageStream) -> Int32 {
  self.height
}

///|
/// Returns the number of channels of the image.
pub fn ImageStream::channels(self : ImageStream) -> Int32 {
  self.grids.length()
}

///|
/// Output sample type of `ImageStream::write_to_buffer` (upstream sealed trait
/// `FrameBufferSample`, implemented by `f32`, `u16` and `u8`).
#derive(Debug, Eq)
pub(all) enum SampleKind {
  /// 32-bit float samples, with nominal range of `[0, 1]`.
  F32
  /// 16-bit unsigned integer samples.
  U16
  /// 8-bit unsigned integer samples.
  U8
}

///|
/// `f32 as u16` conversion of `(val * 65535 + 0.5).clamp(0, 65535)`.
pub fn sample_f32_to_u16(val : Float) -> Int32 {
  let v = val * 65535.0 + 0.5
  clamp_float_to_int(v, 65535.0)
}

///|
/// `f32 as u8` conversion of `(val * 255 + 0.5).clamp(0, 255)`.
pub fn sample_f32_to_u8(val : Float) -> Int32 {
  let v = val * 255.0 + 0.5
  clamp_float_to_int(v, 255.0)
}

///|
/// `v.clamp(0, max) as uN`: NaN maps to 0 like Rust's saturating cast.
fn clamp_float_to_int(v : Float, max : Float) -> Int32 {
  if v.is_nan() || v <= 0.0 {
    0
  } else if v >= max {
    max.to_int()
  } else {
    v.to_int()
  }
}

///|
/// Upstream `Sealed::copy_from_grid` for `u16` (result in 0..=65535).
fn copy_u16_from_grid(
  grid : @render.ImageBuffer,
  x : Int32,
  y : Int32,
  bit_depth : @image.BitDepth,
) -> Int32 {
  if bit_depth is IntegerSample(bits_per_sample=16) {
    match grid {
      F32(g) => {
        let v = if x < g.width() && y < g.height() { g.get(x, y) } else { 0.0 }
        clamp_float_to_int(v * 65535.0 + 0.5, 65535.0)
      }
      I32(g) => {
        let v = if x < g.width() && y < g.height() { g.get(x, y) } else { 0 }
        if v < 0 {
          0
        } else if v > 65535 {
          65535
        } else {
          v
        }
      }
    }
  } else {
    sample_f32_to_u16(sample_f32(grid, x, y, bit_depth))
  }
}

///|
/// Upstream `Sealed::copy_from_grid` for `u8` (result in 0..=255).
fn copy_u8_from_grid(
  grid : @render.ImageBuffer,
  x : Int32,
  y : Int32,
  bit_depth : @image.BitDepth,
) -> Int32 {
  if bit_depth is IntegerSample(bits_per_sample=8) {
    match grid {
      F32(g) => {
        let v = if x < g.width() && y < g.height() { g.get(x, y) } else { 0.0 }
        clamp_float_to_int(v * 255.0 + 0.5, 255.0)
      }
      I32(g) => {
        let v = if x < g.width() && y < g.height() { g.get(x, y) } else { 0 }
        if v < 0 {
          0
        } else if v > 255 {
          255
        } else {
          v
        }
      }
    }
  } else {
    sample_f32_to_u8(sample_f32(grid, x, y, bit_depth))
  }
}

///|
/// Writes next samples as `f32` to `buf[start:]`, returning how many samples
/// are written.
pub fn ImageStream::write_to_buffer_f32(
  self : ImageStream,
  buf : FixedArray[Float],
  start~ : Int32 = 0,
) -> Int32 {
  self.write_samples(
    buf.length() - start,
    fn(i, grid, x, y, bit_depth) {
      buf[start + i] = sample_f32(grid, x, y, bit_depth)
    },
    fn(i, v) { buf[start + i] = v },
    fn(i) { buf[start + i] = 0.0 },
  )
}

///|
/// Writes next samples as `u16` (stored in `Int`) to `buf[start:]`, returning
/// how many samples are written.
pub fn ImageStream::write_to_buffer_u16(
  self : ImageStream,
  buf : FixedArray[Int32],
  start~ : Int32 = 0,
) -> Int32 {
  self.write_samples(
    buf.length() - start,
    fn(i, grid, x, y, bit_depth) {
      buf[start + i] = copy_u16_from_grid(grid, x, y, bit_depth)
    },
    fn(i, v) { buf[start + i] = sample_f32_to_u16(v) },
    fn(i) { buf[start + i] = 0 },
  )
}

///|
/// Writes next samples as `u8` to `buf[start:]`, returning how many samples are
/// written.
pub fn ImageStream::write_to_buffer_u8(
  self : ImageStream,
  buf : FixedArray[Byte],
  start~ : Int32 = 0,
) -> Int32 {
  self.write_samples(
    buf.length() - start,
    fn(i, grid, x, y, bit_depth) {
      buf[start + i] = copy_u8_from_grid(grid, x, y, bit_depth).to_byte()
    },
    fn(i, v) { buf[start + i] = sample_f32_to_u8(v).to_byte() },
    fn(i) { buf[start + i] = b'\x00' },
  )
}

///|
/// Body of upstream `write_to_buffer`, generic over the output through
/// `from_grid` (copy a grid sample), `from_f32` (store a float) and
/// `default` (store the zero sample) callbacks indexed by output position.
fn ImageStream::write_samples(
  self : ImageStream,
  capacity : Int32,
  from_grid : (Int32, @render.ImageBuffer, Int32, Int32, @image.BitDepth) -> Unit,
  from_f32 : (Int32, Float) -> Unit,
  default : (Int32) -> Unit,
) -> Int32 {
  let channels = self.grids.length()
  let mut count = 0
  while self.y < self.height {
    while self.x < self.width {
      while self.c < channels {
        if count >= capacity {
          return count
        }
        let (start_x, start_y) = self.start_offset_xy[self.c]
        let (orig_x, orig_y) = self.to_original_coord(self.x, self.y)
        let x = orig_x + start_x
        let y = orig_y + start_y
        if x < 0 || y < 0 {
          default(count)
          count += 1
          self.c += 1
          continue
        }
        let grid = self.grids[self.c]
        let bit_depth = self.bit_depth[self.c]
        if self.c >= 3 || self.spot_colors.is_empty() {
          from_grid(count, grid, x, y, bit_depth)
        } else {
          let mut tmp_sample = sample_f32(grid, x, y, bit_depth)
          for spot in self.spot_colors {
            let (start_x, start_y) = spot.start_offset_xy
            let (r, g, b) = spot.rgb
            let color = match self.c {
              0 => r
              1 => g
              _ => b
            }
            let sx = orig_x + start_x
            let sy = orig_y + start_y
            let mix = if sx >= 0 && sy >= 0 {
              sample_f32(spot.grid, sx, sy, spot.bit_depth) * spot.solidity
            } else {
              0.0
            }
            tmp_sample = color * mix + tmp_sample * (1.0 - mix)
          }
          from_f32(count, tmp_sample)
        }
        count += 1
        self.c += 1
      }
      self.c = 0
      self.x += 1
    }
    self.x = 0
    self.y += 1
  }
  count
}

///|
fn ImageStream::to_original_coord(
  self : ImageStream,
  x : Int32,
  y : Int32,
) -> (Int32, Int32) {
  let width = self.width
  let height = self.height
  match self.orientation {
    1 => (x, y)
    2 => (width - x - 1, y)
    3 => (width - x - 1, height - y - 1)
    4 => (x, height - y - 1)
    5 => (y, x)
    6 => (y, width - x - 1)
    7 => (height - y - 1, width - x - 1)
    _ => (height - y - 1, x)
  }
}
