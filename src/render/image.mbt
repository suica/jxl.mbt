///|
/// A sample buffer of one channel (jxl-render `ImageBuffer`).
///
/// Upstream also has an `I16` variant for "narrow" (16-bit) modular buffers;
/// modular buffers are always `Int` in this port, so only `F32` and `I32`
/// exist.
pub(all) enum ImageBuffer {
  F32(@grid.Grid[Float])
  I32(@grid.Grid[Int])
}

///|
pub fn ImageBuffer::from_modular_channel(g : @grid.Grid[Int]) -> ImageBuffer {
  I32(g)
}

///|
pub fn ImageBuffer::zeroed_f32(
  width : Int,
  height : Int,
  tracker : @grid.AllocTracker?,
) -> ImageBuffer raise @bitstream.JxlError {
  F32(@grid.Grid::with_alloc_tracker(width, height, (0.0 : Float), tracker))
}

///|
pub fn ImageBuffer::try_clone(
  self : ImageBuffer,
) -> ImageBuffer raise @bitstream.JxlError {
  match self {
    F32(g) => F32(g.clone())
    I32(g) => I32(g.clone())
  }
}

///|
pub fn ImageBuffer::width(self : ImageBuffer) -> Int {
  match self {
    F32(g) => g.width()
    I32(g) => g.width()
  }
}

///|
pub fn ImageBuffer::height(self : ImageBuffer) -> Int {
  match self {
    F32(g) => g.height()
    I32(g) => g.height()
  }
}

///|
pub fn ImageBuffer::as_float(self : ImageBuffer) -> @grid.Grid[Float]? {
  match self {
    F32(g) => Some(g)
    _ => None
  }
}

///|
/// Returns the float grid, panicking if the buffer is not `F32`
/// (`as_float().unwrap()`).
pub fn ImageBuffer::float(self : ImageBuffer) -> @grid.Grid[Float] {
  match self {
    F32(g) => g
    _ => abort("buffer is not F32")
  }
}

///|
/// Converts integer modular samples to float using `bit_depth`.
///
/// Upstream mutates the buffer in place; here the converted grid is returned
/// and the caller stores `F32(grid)` back (see
/// `ImageWithRegion::convert_channel_to_float_modular`). Returns the
/// original grid if already float.
pub fn ImageBuffer::convert_to_float_modular(
  self : ImageBuffer,
  bit_depth : @image.BitDepth,
) -> @grid.Grid[Float] raise @bitstream.JxlError {
  match self {
    F32(g) => g
    I32(g) => {
      let out = @grid.Grid::new(g.width(), g.height(), (0.0 : Float))
      let src = g.buf()
      let dst = out.buf()
      let n = g.width() * g.height()
      for i in 0..<n {
        dst[i] = bit_depth.parse_integer_sample(src[i])
      }
      out
    }
  }
}

///|
/// Casts integer samples to float without scaling.
pub fn ImageBuffer::cast_to_float(
  self : ImageBuffer,
) -> @grid.Grid[Float] raise @bitstream.JxlError {
  match self {
    F32(g) => g
    I32(g) => {
      let out = @grid.Grid::new(g.width(), g.height(), (0.0 : Float))
      let src = g.buf()
      let dst = out.buf()
      let n = g.width() * g.height()
      for i in 0..<n {
        dst[i] = Float::from_int(src[i])
      }
      out
    }
  }
}

///|
fn saturating_add_i32(a : Int, b : Int) -> Int {
  let r = a.to_int64() + b.to_int64()
  if r > 0x7fffffffL {
    0x7fffffff
  } else if r < -0x80000000L {
    -0x80000000
  } else {
    r.to_int()
  }
}

///|
/// Dequantizes XYB-encoded modular channels (given in Y, X, B order) into
/// float X, Y, B values. Returns the float grids `[y, x, b]` positions, which
/// now hold X, Y, B respectively.
pub fn ImageBuffer::convert_to_float_modular_xyb(
  yxb : FixedArray[ImageBuffer],
  lf_dequant : @vardct.LfChannelDequantization,
) -> FixedArray[@grid.Grid[Float]] raise @bitstream.JxlError {
  match (yxb[0], yxb[1], yxb[2]) {
    (F32(_), F32(_), F32(_)) => abort("channels are already converted")
    (I32(y), I32(_), I32(b)) => {
      let bb = b.buf()
      let yb = y.buf()
      let n = b.width() * b.height()
      for i in 0..<n {
        bb[i] = saturating_add_i32(bb[i], yb[i])
      }
    }
    _ => abort("mismatched channel types")
  }
  let y = yxb[0].cast_to_float()
  let x = yxb[1].cast_to_float()
  let b = yxb[2].cast_to_float()
  let buf_y = y.buf()
  let buf_x = x.buf()
  let buf_b = b.buf()
  let m_x_lf = lf_dequant.m_x_lf_unscaled()
  let m_y_lf = lf_dequant.m_y_lf_unscaled()
  let m_b_lf = lf_dequant.m_b_lf_unscaled()
  let n = y.width() * y.height()
  for i in 0..<n {
    let py = buf_y[i]
    let px = buf_x[i]
    buf_y[i] = px * m_x_lf
    buf_x[i] = py * m_y_lf
    buf_b[i] = buf_b[i] * m_b_lf
  }
  [y, x, b]
}

///|
fn[S] upsample_nn_inner(
  original : FixedArray[S],
  target : FixedArray[S],
  width : Int,
  height : Int,
  factor : Int,
) -> Unit {
  let step = 1 << factor
  let stride = width << factor
  for y in 0..<height {
    let obase = y * width
    let tbase = y * step * stride
    for x in 0..<width {
      let value = original[obase + x]
      for k in 0..<step {
        target[tbase + x * step + k] = value
      }
    }
    for row in 1..<step {
      FixedArray::blit_to(
        target,
        target,
        len=stride,
        src_offset=tbase,
        dst_offset=tbase + stride * row,
      )
    }
  }
}

///|
pub fn ImageBuffer::upsample_nn(
  self : ImageBuffer,
  factor : Int,
  tracker : @grid.AllocTracker?,
) -> ImageBuffer raise @bitstream.JxlError {
  if factor == 0 {
    return self.try_clone()
  }
  let width = self.width()
  let height = self.height()
  let up_width = width << factor
  let up_height = height << factor
  match self {
    F32(g) => {
      let out = @grid.Grid::with_alloc_tracker(
        up_width,
        up_height,
        (0.0 : Float),
        tracker,
      )
      upsample_nn_inner(g.buf(), out.buf(), width, height, factor)
      F32(out)
    }
    I32(g) => {
      let out = @grid.Grid::with_alloc_tracker(up_width, up_height, 0, tracker)
      upsample_nn_inner(g.buf(), out.buf(), width, height, factor)
      I32(out)
    }
  }
}

///|
/// Rendered image: one buffer per channel, each with the region (in frame
/// coordinates) it covers and its channel shift (jxl-render
/// `ImageWithRegion`).
pub struct ImageWithRegion {
  buffer : Array[ImageBuffer]
  regions : Array[(Region, @modular.ChannelShift)]
  mut color_channels : Int
  mut ct_done : Bool
  mut blend_done : Bool
  tracker : @grid.AllocTracker?
}

///|
pub fn ImageWithRegion::new(
  color_channels : Int,
  tracker : @grid.AllocTracker?,
) -> ImageWithRegion {
  {
    buffer: [],
    regions: [],
    color_channels,
    ct_done: false,
    blend_done: false,
    tracker,
  }
}

///|
pub fn ImageWithRegion::try_clone(
  self : ImageWithRegion,
) -> ImageWithRegion raise @bitstream.JxlError {
  let buffer = []
  for b in self.buffer {
    buffer.push(b.try_clone())
  }
  {
    buffer,
    regions: self.regions.copy(),
    color_channels: self.color_channels,
    ct_done: self.ct_done,
    blend_done: false,
    tracker: self.tracker,
  }
}

///|
pub fn ImageWithRegion::alloc_tracker(
  self : ImageWithRegion,
) -> @grid.AllocTracker? {
  self.tracker
}

///|
pub fn ImageWithRegion::channels(self : ImageWithRegion) -> Int {
  self.buffer.length()
}

///|
/// The channel buffers. The array is shared: assigning an element replaces
/// the channel (upstream `buffer_mut`).
pub fn ImageWithRegion::buffer(self : ImageWithRegion) -> Array[ImageBuffer] {
  self.buffer
}

///|
pub fn ImageWithRegion::buffer_mut(
  self : ImageWithRegion,
) -> Array[ImageBuffer] {
  self.buffer
}

///|
pub fn ImageWithRegion::take_buffer(
  self : ImageWithRegion,
) -> Array[ImageBuffer] {
  let out = self.buffer.copy()
  self.buffer.clear()
  out
}

///|
pub fn ImageWithRegion::regions_and_shifts(
  self : ImageWithRegion,
) -> Array[(Region, @modular.ChannelShift)] {
  self.regions
}

///|
pub fn ImageWithRegion::append_channel(
  self : ImageWithRegion,
  buffer : ImageBuffer,
  region : Region,
) -> Unit {
  guard buffer.width() == region.width && buffer.height() == region.height else {
    abort("append_channel: buffer size mismatch")
  }
  self.buffer.push(buffer)
  self.regions.push((region, @modular.ChannelShift::from_shift(0)))
}

///|
pub fn ImageWithRegion::append_channel_shifted(
  self : ImageWithRegion,
  buffer : ImageBuffer,
  original_region : Region,
  shift : @modular.ChannelShift,
) -> Unit {
  let (width, height) = shift.shift_size((
    original_region.width,
    original_region.height,
  ))
  guard buffer.width() == width && buffer.height() == height else {
    abort("append_channel_shifted: buffer size mismatch")
  }
  self.buffer.push(buffer)
  self.regions.push((original_region, shift))
}

///|
pub fn ImageWithRegion::replace_channel(
  self : ImageWithRegion,
  index : Int,
  buffer : ImageBuffer,
  region : Region,
) -> Unit {
  guard buffer.width() == region.width && buffer.height() == region.height else {
    abort("replace_channel: buffer size mismatch")
  }
  self.buffer[index] = buffer
  self.regions[index] = (region, @modular.ChannelShift::from_shift(0))
}

///|
pub fn ImageWithRegion::replace_channel_shifted(
  self : ImageWithRegion,
  index : Int,
  buffer : ImageBuffer,
  original_region : Region,
  shift : @modular.ChannelShift,
) -> Unit {
  let (width, height) = shift.shift_size((
    original_region.width,
    original_region.height,
  ))
  guard buffer.width() == width && buffer.height() == height else {
    abort("replace_channel_shifted: buffer size mismatch")
  }
  self.buffer[index] = buffer
  self.regions[index] = (original_region, shift)
}

///|
/// Swaps the F32 buffer of channel `index` with `buffer`; returns the old
/// buffer (upstream swaps through `&mut`).
pub fn ImageWithRegion::swap_channel_f32(
  self : ImageWithRegion,
  index : Int,
  buffer : @grid.Grid[Float],
  region : Region,
) -> @grid.Grid[Float] {
  guard buffer.width() == region.width && buffer.height() == region.height else {
    abort("swap_channel_f32: buffer size mismatch")
  }
  guard self.buffer[index] is F32(original) else {
    abort("original buffer is not F32")
  }
  self.buffer[index] = F32(buffer)
  self.regions[index] = (region, @modular.ChannelShift::from_shift(0))
  original
}

///|
/// Converts channel `index` to float with `bit_depth`, stores it back and
/// returns the float grid (upstream `buffer_mut()[index]
/// .convert_to_float_modular(bit_depth)`).
pub fn ImageWithRegion::convert_channel_to_float_modular(
  self : ImageWithRegion,
  index : Int,
  bit_depth : @image.BitDepth,
) -> @grid.Grid[Float] raise @bitstream.JxlError {
  let g = self.buffer[index].convert_to_float_modular(bit_depth)
  self.buffer[index] = F32(g)
  g
}

///|
/// Appends the channels of a decoded GlobalModular image.
pub fn ImageWithRegion::extend_from_gmodular(
  self : ImageWithRegion,
  gmodular : @frame.GlobalModular,
) -> Unit {
  guard gmodular.modular.into_image() is Some(image) else { return }
  for item in image.into_image_channels_with_info() {
    let (g, info) = item
    let (width, height) = info.original_size()
    let shift = info.shift()
    let original_region = Region::with_size(width, height)
    let buffer = ImageBuffer::from_modular_channel(g)
    self.append_channel_shifted(buffer, original_region, shift)
  }
}

///|
pub fn ImageWithRegion::clone_gray(
  self : ImageWithRegion,
) -> Unit raise @bitstream.JxlError {
  guard self.color_channels == 1 else { abort("clone_gray: not grayscale") }
  let gray = self.buffer[0].try_clone()
  let region = self.regions[0]
  self.buffer.insert(1, gray.try_clone())
  self.regions.insert(1, region)
  self.buffer.insert(2, gray)
  self.regions.insert(2, region)
  self.color_channels = 3
}

///|
pub fn ImageWithRegion::convert_modular_color(
  self : ImageWithRegion,
  bit_depth : @image.BitDepth,
) -> Unit raise @bitstream.JxlError {
  guard self.buffer.length() >= self.color_channels else {
    abort("convert_modular_color: missing color channels")
  }
  for i in 0..<self.color_channels {
    ignore(self.convert_channel_to_float_modular(i, bit_depth))
  }
}

///|
pub fn ImageWithRegion::convert_modular_xyb(
  self : ImageWithRegion,
  lf_dequant : @vardct.LfChannelDequantization,
) -> Unit raise @bitstream.JxlError {
  guard self.color_channels == 3 && self.buffer.length() >= 3 else {
    abort("convert_modular_xyb: not a 3-channel image")
  }
  let out = ImageBuffer::convert_to_float_modular_xyb(
    [self.buffer[0], self.buffer[1], self.buffer[2]],
    lf_dequant,
  )
  for i in 0..<3 {
    self.buffer[i] = F32(out[i])
  }
}

///|
pub fn ImageWithRegion::upsample_lf(
  self : ImageWithRegion,
  lf_level : Int,
) -> ImageWithRegion raise @bitstream.JxlError {
  let factor = lf_level * 3
  let out = ImageWithRegion::new(self.color_channels, self.tracker)
  for i, rs in self.regions {
    let (region, shift) = rs
    let up_region = region.upsample(factor)
    let buffer = self.buffer[i].upsample_nn(factor, self.tracker)
    out.append_channel_shifted(buffer, up_region, shift)
  }
  out
}

///|
pub fn ImageWithRegion::upsample_jpeg(
  self : ImageWithRegion,
  valid_region : Region,
  bit_depth : @image.BitDepth,
) -> Unit raise @bitstream.JxlError {
  guard self.color_channels == 3 else { abort("upsample_jpeg: not 3 channels") }
  self.convert_modular_color(bit_depth)
  for idx in 0..<3 {
    let (region, shift) = self.regions[idx]
    let downsampled_image_region = region.downsample_with_shift(shift)
    let downsampled_valid_region = valid_region.downsample_with_shift(shift)
    let left = abs_diff(
      downsampled_valid_region.left,
      downsampled_image_region.left,
    )
    let top = abs_diff(downsampled_valid_region.top, downsampled_image_region.top)
    let width = downsampled_valid_region.width
    let height = downsampled_valid_region.height
    let subgrid = self.buffer[idx]
      .float()
      .as_subgrid()
      .subgrid(left, top, width, height)
    let out = apply_jpeg_upsampling_single(
      subgrid,
      shift,
      valid_region,
      self.tracker,
    )
    self.buffer[idx] = F32(out)
    self.regions[idx] = (valid_region, @modular.ChannelShift::from_shift(0))
  }
}

///|
pub fn ImageWithRegion::upsample_nonseparable(
  self : ImageWithRegion,
  image_header : @image.ImageHeader,
  frame_header : @frame.FrameHeader,
  upsampled_valid_region : Region,
  ec_to_color_only : Bool,
) -> Unit raise @bitstream.JxlError {
  let color_channels = self.color_channels
  let color_shift = frame_header.upsampling.ctz()
  for idx in 0..<self.regions.length() {
    let (region, shift) = self.regions[idx]
    let tracker = self.tracker
    guard shift is Shifts(upsampling_factor) else {
      abort("invalid channel shift for upsampling")
    }
    let bit_depth = if idx >= color_channels {
      image_header.metadata.ec_info[idx - color_channels].bit_depth
    } else {
      image_header.metadata.bit_depth
    }
    let target_factor = if ec_to_color_only { color_shift } else { 0 }
    if upsampling_factor == target_factor {
      continue
    }
    let grid = self.convert_channel_to_float_modular(idx, bit_depth)
    let downsampled_image_region = region.downsample(upsampling_factor)
    let downsampled_valid_region = upsampled_valid_region.downsample(
      upsampling_factor,
    )
    let left = abs_diff(
      downsampled_valid_region.left,
      downsampled_image_region.left,
    )
    let top = abs_diff(downsampled_valid_region.top, downsampled_image_region.top)
    let width = downsampled_valid_region.width
    let height = downsampled_valid_region.height
    let subgrid = grid.as_subgrid().subgrid(left, top, width, height)
    let out_region = Ref::new(downsampled_valid_region)
    let out = upsample(
      subgrid,
      out_region,
      image_header,
      upsampling_factor - target_factor,
      tracker,
    )
    if out is Some(out) {
      self.buffer[idx] = F32(out)
    }
    self.regions[idx] = (
      out_region.val,
      @modular.ChannelShift::from_shift(target_factor),
    )
  }
}

///|
pub fn ImageWithRegion::prepare_color_upsampling(
  self : ImageWithRegion,
  frame_header : @frame.FrameHeader,
) -> Unit {
  let upsampling_factor = frame_header.upsampling.ctz()
  for idx in 0..<self.regions.length() {
    let (region, shift) = self.regions[idx]
    let new_shift : @modular.ChannelShift = match shift {
      Raw(h, v) =>
        if h < 0 || v < 0 {
          continue
        } else {
          Raw(h + upsampling_factor, v + upsampling_factor)
        }
      Shifts(s) => Shifts(s + upsampling_factor)
      JpegUpsampling(
        has_h_subsample=false,
        h_subsample=false,
        has_v_subsample=false,
        v_subsample=false
      ) => Shifts(upsampling_factor)
      JpegUpsampling(..) => abort("unexpected chroma subsampling")
    }
    self.regions[idx] = (region.upsample(upsampling_factor), new_shift)
  }
}

///|
pub fn ImageWithRegion::remove_color_channels(
  self : ImageWithRegion,
  count : Int,
) -> Unit {
  guard self.color_channels >= count else {
    abort("remove_color_channels: too many")
  }
  let n = self.color_channels - count
  for _ in 0..<n {
    ignore(self.buffer.remove(count))
    ignore(self.regions.remove(count))
  }
  self.color_channels = count
}

///|
pub fn ImageWithRegion::fill_opaque_alpha(
  self : ImageWithRegion,
  ec_info : Array[@image.ExtraChannelInfo],
) -> Unit {
  for ec_idx, info in ec_info {
    guard info.ty is Alpha(..) else { continue }
    let opaque_int : Int = match info.bit_depth {
      IntegerSample(bits_per_sample~) =>
        ((1U << bits_per_sample) - 1).reinterpret_as_int()
      FloatSample(bits_per_sample~, exp_bits~) => {
        let mantissa_bits = bits_per_sample - exp_bits - 1
        (((1U << (exp_bits - 1)) - 1) << mantissa_bits).reinterpret_as_int()
      }
    }
    match self.buffer[self.color_channels + ec_idx] {
      I32(g) => g.buf().fill(opaque_int)
      F32(g) => g.buf().fill(1.0)
    }
  }
}

///|
pub fn ImageWithRegion::color_channels(self : ImageWithRegion) -> Int {
  self.color_channels
}

///|
pub fn ImageWithRegion::ct_done(self : ImageWithRegion) -> Bool {
  self.ct_done
}

///|
pub fn ImageWithRegion::set_ct_done(
  self : ImageWithRegion,
  ct_done : Bool,
) -> Unit {
  self.ct_done = ct_done
}

///|
pub fn ImageWithRegion::blend_done(self : ImageWithRegion) -> Bool {
  self.blend_done
}

///|
pub fn ImageWithRegion::set_blend_done(
  self : ImageWithRegion,
  blend_done : Bool,
) -> Unit {
  self.blend_done = blend_done
}

///|
/// The three color channels as float grids (panics if not converted).
pub fn ImageWithRegion::as_color_floats(
  self : ImageWithRegion,
) -> FixedArray[@grid.Grid[Float]] {
  guard self.color_channels == 3 else { abort("as_color_floats: not 3 ch") }
  [self.buffer[0].float(), self.buffer[1].float(), self.buffer[2].float()]
}

///|
pub fn ImageWithRegion::as_color_floats_mut(
  self : ImageWithRegion,
) -> FixedArray[@grid.Grid[Float]] {
  self.as_color_floats()
}

///|
/// Splits the color channels into groups and returns each group with its
/// group index in the frame.
pub fn ImageWithRegion::color_groups_with_group_id(
  self : ImageWithRegion,
  frame_header : @frame.FrameHeader,
) -> Array[(Int, FixedArray[@grid.SubGrid[Float]])] {
  guard self.color_channels == 3 else {
    abort("color_groups_with_group_id: not 3 ch")
  }
  let group_dim = frame_header.group_dim()
  let base_group_x = self.regions[0].0.left / group_dim
  let base_group_y = self.regions[0].0.top / group_dim
  let width = self.regions[0].0.width
  let frame_groups_per_row = frame_header.groups_per_row()
  let groups_per_row = (width + group_dim - 1) / group_dim
  let groups = FixedArray::makei(3, idx => {
    let fb = self.buffer[idx].float().as_subgrid()
    let hshift = self.regions[idx].1.hshift()
    let vshift = self.regions[idx].1.vshift()
    fb.into_groups(group_dim >> hshift, group_dim >> vshift)
  })
  let n = min_int(
    groups[0].length(),
    min_int(groups[1].length(), groups[2].length()),
  )
  let out = []
  for idx in 0..<n {
    let group_x = base_group_x + idx % groups_per_row
    let group_y = base_group_y + idx / groups_per_row
    let group_idx = group_y * frame_groups_per_row + group_x
    out.push((
      group_idx,
      ([groups[0][idx], groups[1][idx], groups[2][idx]] : FixedArray[_]),
    ))
  }
  out
}

///|
/// A rendered (but possibly not yet blended) frame (jxl-render
/// `RenderedImage`).
pub struct RenderedImage {
  image : FrameRenderHandle
}

///|
pub fn RenderedImage::new(image : FrameRenderHandle) -> RenderedImage {
  { image, }
}

///|
/// Composites the rendered frame onto its references, caching the result.
pub fn RenderedImage::blend(
  self : RenderedImage,
  oriented_image_region : Region?,
) -> ImageWithRegion raise @bitstream.JxlError {
  let image_header = self.image.frame.image_header()
  let image_region = self.image.image_region
  let oriented_image_region = match oriented_image_region {
    Some(r) => r
    None => apply_orientation_to_image_region(image_header, image_region)
  }
  self.image.wait_until_render()
  if self.image.render is Blended(image) {
    return image
  }
  let render = self.image.render
  self.image.render = ErrTaken
  guard render is Done(grid) else { abort("RenderedImage::blend: not done") }
  let skip_composition = composite_preprocess(self.image.frame, grid)
  if skip_composition {
    self.image.render = Blended(grid)
    return grid
  }
  self.image.render = Rendering
  let grid = composite(
    self.image.frame,
    grid,
    self.image.refs,
    oriented_image_region,
  )
  self.image.done_render(Blended(grid))
  grid
}

///|
/// Upstream takes the blended image out of the handle when no one else holds
/// it (`Arc::into_inner`). The call sites always hold another reference, so
/// it never succeeds; without reference counting this always returns `None`.
pub fn RenderedImage::try_take_blended(
  _self : RenderedImage,
) -> ImageWithRegion? {
  None
}

///|
/// Preprocesses image before composition.
///
/// Returns `true` if no actual composition is needed.
fn composite_preprocess(
  frame : IndexedFrame,
  grid : ImageWithRegion,
) -> Bool raise @bitstream.JxlError {
  let image_header = frame.image_header()
  let frame_header = frame.header()
  if frame_header.can_reference() {
    let n = grid.buffer.length()
    for i in 0..<n {
      let bit_depth = if i < grid.color_channels {
        image_header.metadata.bit_depth
      } else if i - grid.color_channels < image_header.metadata.ec_info.length() {
        image_header.metadata.ec_info[i - grid.color_channels].bit_depth
      } else {
        break
      }
      ignore(grid.convert_channel_to_float_modular(i, bit_depth))
    }
  }
  let skip_blending = !frame_header.frame_type.is_normal_frame() ||
    frame_header.resets_canvas
  if !(
      grid.ct_done() ||
      frame_header.save_before_ct ||
      (skip_blending && frame_header.is_last)
    ) {
    convert_color_for_record(image_header, frame_header.do_ycbcr, grid)
  }
  if skip_blending {
    grid.blend_done = true
  }
  skip_blending
}

///|
fn composite(
  frame : IndexedFrame,
  grid : ImageWithRegion,
  refs : FixedArray[Reference?],
  oriented_image_region : Region,
) -> ImageWithRegion raise @bitstream.JxlError {
  let image_header = frame.image_header()
  let frame_header = frame.header()
  let frame_region = oriented_image_region
    .translate(-frame_header.x0, -frame_header.y0)
    .downsample(frame_header.lf_level * 3)
  let frame_region = pad_lf_region(frame_header, frame_region)
  let frame_region = pad_color_region(image_header, frame_header, frame_region)
  let frame_region = frame_region.upsample(frame_header.upsampling.ctz())
  let frame_region = if frame_header.frame_type.is_normal_frame() {
    let full_image_region_in_frame = Region::with_size(
      image_header.size.width,
      image_header.size.height,
    ).translate(-frame_header.x0, -frame_header.y0)
    frame_region.intersection(full_image_region_in_frame)
  } else {
    frame_region
  }
  blend(image_header, refs, frame, grid, frame_region)
}
