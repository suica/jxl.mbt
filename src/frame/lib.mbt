///|
/// This package provides types related to JPEG XL frames.
///
/// A JPEG XL image contains one or more frames. A frame represents single unit of image that can
/// be displayed or referenced by other frames.
///
/// A frame consists of a few components:
/// - Frame header (`FrameHeader`).
/// - Table of contents (TOC, `Toc`).
/// - Actual frame data, in the following order, potentially permuted as specified in the TOC:
///   - one `LfGlobal`,
///   - `num_lf_groups` `LfGroup`'s, in raster order,
///   - one `HfGlobal`, potentially empty for Modular frames, and
///   - `num_passes` times `num_groups` pass groups (`decode_pass_group`), in raster order.

///|
/// JPEG XL frame.
///
/// A frame represents a single unit of image that can be displayed or referenced by other frames.
pub struct Frame {
  priv pool : @threadpool.JxlThreadPool
  priv tracker : @grid.AllocTracker?
  priv image_header : @image.ImageHeader
  priv header : FrameHeader
  priv toc : Toc
  priv data : Array[GroupData]
  priv all_group_offsets : AllGroupOffsets
  priv mut reading_data_index : Int32
  priv pass_shifts : @sorted_map.SortedMap[Int32, (Int32, Int32)]
}

///|
priv struct AllGroupOffsets {
  mut lf_group : Int32
  mut hf_global : Int32
  mut pass_group : Int32
  mut has_error : Int32
}

///|
/// Bytes of one TOC group. Data fed in one piece is referenced without copying;
/// data fed in several pieces is accumulated in a buffer.
priv struct GroupData {
  toc_group : TocGroup
  mut view : BytesView
  mut buf : Buffer?
  mut allocated : Bool
}

///|
fn GroupData::from_toc_group(value : TocGroup) -> GroupData {
  { toc_group: value, view: b""[:], buf: None, allocated: false, }
}

///|
fn GroupData::len(self : GroupData) -> Int32 {
  self.view.length()
}

///|
fn GroupData::ensure_allocated(
  self : GroupData,
  tracker : @grid.AllocTracker?,
) -> Unit raise @bitstream.JxlError {
  if tracker is Some(tracker) {
    if self.allocated {
      return
    }
    tracker.alloc(self.toc_group.size, 1)
    self.allocated = true
  }
}

///|
fn GroupData::append(self : GroupData, chunk : BytesView) -> Unit {
  if chunk.length() == 0 {
    return
  }
  if self.view.length() == 0 && self.buf is None {
    self.view = chunk
    return
  }
  let buf = match self.buf {
    Some(buf) => buf
    None => {
      let buf = Buffer(capacity=self.toc_group.size)
      buf.write_bytesview(self.view)
      self.buf = Some(buf)
      buf
    }
  }
  buf.write_bytesview(chunk)
  self.view = buf.to_bytes()[:]
}

///|
fn bitstream_of(view : BytesView) -> @bitstream.Bitstream {
  @bitstream.Bitstream::new_range(
    view.data(),
    view.start_offset(),
    view.length(),
  )
}

///|
pub(all) struct FrameContext {
  image_header : @image.ImageHeader
  tracker : @grid.AllocTracker?
  pool : @threadpool.JxlThreadPool
}

///|
/// `Bundle<FrameContext>::parse`.
pub fn Frame::parse(
  bs : @bitstream.Bitstream,
  ctx : FrameContext,
) -> Frame raise @bitstream.JxlError {
  let { image_header, tracker, pool, } = ctx
  bs.zero_pad_to_byte()
  let base_offset = (bs.num_read_bits() / 8).to_int64()
  let header = FrameHeader::parse(bs, image_header)
  let width = header.width.reinterpret_as_uint().to_uint64()
  let height = header.height.reinterpret_as_uint().to_uint64()
  if width > 1UL << 30 {
    raise ProfileConformance("frame width too large")
  }
  if height > 1UL << 30 {
    raise ProfileConformance("frame height too large")
  }
  if width * height > 1UL << 40 {
    raise ProfileConformance("frame area too large")
  }
  let has_extra = !header.ec_blending_info.is_empty()
  let all_blending = [header.blending_info, ..header.ec_blending_info]
  for blending_info in all_blending {
    if blending_info.mode.use_alpha() && has_extra {
      let alpha_idx = blending_info.alpha_channel
      guard alpha_idx >= 0 && alpha_idx < image_header.metadata.ec_info.length() else {
        raise ValidationFailed("blending_info.alpha_channel out of range")
      }
      let alpha_ec_info = image_header.metadata.ec_info[alpha_idx]
      if !alpha_ec_info.is_alpha() {
        raise ValidationFailed(
          "blending_info.alpha_channel is not the type of Alpha",
        )
      }
    }
  }
  if header.flags.use_lf_frame() && header.lf_level >= 4 {
    raise ValidationFailed("lf_level out of range")
  }
  let color_upsampling_shift = header.upsampling.ctz()
  let n = @cmp.minimum(
    header.ec_upsampling.length(),
    image_header.metadata.ec_info.length(),
  )
  for i in 0..<n {
    let ec_upsampling = header.ec_upsampling[i]
    let ec_info = image_header.metadata.ec_info[i]
    let ec_upsampling_shift = ec_upsampling.ctz()
    let dim_shift = ec_info.dim_shift
    if ec_upsampling_shift + dim_shift < color_upsampling_shift {
      raise ValidationFailed(
        "EC upsampling < color upsampling, which is invalid",
      )
    }
    if ec_upsampling_shift + dim_shift > 6 {
      raise ValidationFailed("cumulative EC upsampling factor is too large")
    }
    let actual_dim_shift = ec_upsampling_shift +
      dim_shift -
      color_upsampling_shift
    if actual_dim_shift > 7 + header.group_size_shift {
      raise ValidationFailed("dim_shift too large")
    }
  }
  if header.width == 0 || header.height == 0 {
    raise ValidationFailed(
      "Invalid crop dimensions for frame: zero width or height",
    )
  }
  let toc = Toc::parse(bs, header)
  toc.adjust_offsets(base_offset)
  let data = toc
    .iter_bitstream_order()
    .map(GroupData::from_toc_group)
    .to_array()
  let passes = header.passes
  let pass_shifts = @sorted_map.SortedMap([])
  let mut maxshift = 3
  for
    i in 0..<@cmp.minimum(passes.downsample.length(), passes.last_pass.length()) {
    let downsample = passes.downsample[i]
    let last_pass = passes.last_pass[i]
    let minshift = downsample.ctz()
    pass_shifts.set(last_pass, (minshift, maxshift))
    maxshift = minshift
  }
  pass_shifts.set(header.passes.num_passes - 1, (0, maxshift))
  {
    pool,
    tracker,
    image_header,
    header,
    toc,
    data,
    all_group_offsets: {
      lf_group: 0,
      hf_global: 0,
      pass_group: 0,
      has_error: 0,
    },
    reading_data_index: 0,
    pass_shifts,
  }
}

///|
pub fn Frame::alloc_tracker(self : Frame) -> @grid.AllocTracker? {
  self.tracker
}

///|
pub fn Frame::image_header(self : Frame) -> @image.ImageHeader {
  self.image_header
}

///|
/// `Arc::clone` of the image header; headers are immutable, so this is the same value.
pub fn Frame::clone_image_header(self : Frame) -> @image.ImageHeader {
  self.image_header
}

///|
/// Returns the frame header.
pub fn Frame::header(self : Frame) -> FrameHeader {
  self.header
}

///|
/// Returns the TOC.
pub fn Frame::toc(self : Frame) -> Toc {
  self.toc
}

///|
pub fn Frame::pass_shifts(
  self : Frame,
) -> @sorted_map.SortedMap[Int32, (Int32, Int32)] {
  self.pass_shifts
}

///|
pub fn Frame::data(self : Frame, group : TocGroupKind) -> BytesView? {
  let idx = self.toc.group_index_bitstream_order(group)
  if idx >= 0 && idx < self.data.length() {
    Some(self.data[idx].view)
  } else {
    None
  }
}

///|
/// Feeds frame data; returns the bytes not consumed by this frame.
pub fn Frame::feed_bytes(
  self : Frame,
  buf : BytesView,
) -> BytesView raise @bitstream.JxlError {
  let mut buf = buf
  while self.reading_data_index < self.data.length() {
    let group_data = self.data[self.reading_data_index]
    group_data.ensure_allocated(self.tracker)
    let bytes_left = group_data.toc_group.size - group_data.len()
    if buf.length() < bytes_left {
      group_data.append(buf)
      return buf[buf.length():]
    }
    group_data.append(buf[:bytes_left])
    buf = buf[bytes_left:]
    self.reading_data_index += 1
  }
  buf
}

///|
pub fn Frame::current_loading_group(self : Frame) -> TocGroup? {
  self.toc.iter_bitstream_order().nth(self.reading_data_index)
}

///|
pub fn Frame::is_loading_done(self : Frame) -> Bool {
  self.reading_data_index >= self.data.length()
}

///|
/// Adjusts the cropping region of the image to the actual decoding region of the frame.
///
/// The cropping region of the *image* needs to be adjusted to be used in a *frame*, for a few
/// reasons:
/// - A frame may be blended to the canvas with offset, which makes the image and the frame
///   have different coordinates.
/// - Some filters reference other samples, which requires padding to the region.
///
/// This method takes care of those and adjusts the given region appropriately.
pub fn Frame::adjust_region(
  self : Frame,
  region : Ref[(Int32, Int32, Int32, Int32)],
) -> Unit {
  let (left, top, width, height) = region.val
  let mut left = left.reinterpret_as_uint()
  let mut top = top.reinterpret_as_uint()
  let mut width = width.reinterpret_as_uint()
  let mut height = height.reinterpret_as_uint()
  if self.header.have_crop {
    left = saturating_add_signed(left, -self.header.x0)
    top = saturating_add_signed(top, -self.header.y0)
  }
  let mut padding = 0U
  if self.header.restoration_filter.gab.enabled() {
    // Gabor-like filter requires padding of 1 pixel
    padding = 1
  }
  if self.header.restoration_filter.epf.enabled() {
    // Edge-preserving filter requires padding of 3 pixels
    padding = 3
  }
  if padding > 0 {
    let delta_w = if left < padding { left } else { padding }
    let delta_h = if top < padding { top } else { padding }
    left -= delta_w
    top -= delta_h
    width += delta_w + padding
    height += delta_h + padding
  }
  region.val = (
    left.reinterpret_as_int(),
    top.reinterpret_as_int(),
    width.reinterpret_as_int(),
    height.reinterpret_as_int(),
  )
}

///|
/// `u32::saturating_add_signed`.
fn saturating_add_signed(a : UInt32, b : Int32) -> UInt32 {
  let r = a.to_uint64().reinterpret_as_int64() + b.to_int64()
  if r < 0L {
    0
  } else if r > 0xffffffffL {
    0xffffffffU
  } else {
    r.to_uint()
  }
}
