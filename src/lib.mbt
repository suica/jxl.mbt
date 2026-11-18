// Port of jxl-oxide/src/lib.rs: the public decoder API.
//
// jxl-oxide is a JPEG XL decoder written in pure Rust. It's internally organized
// into a few small crates; this package acts as a blanket and provides a simple
// interface made from those packages to decode the actual image.
//
// # Decoding an image
//
// Create a builder with `JxlImage::builder()` and feed the whole file with
// `read`:
//
//   let image = JxlImage::builder().read(bytes)
//   for keyframe_idx in 0..<image.num_loaded_keyframes() {
//     let render = image.render_frame(keyframe_idx)
//     ...
//   }
//
// When bytes arrive over time, create an image with *uninitialized state* using
// `build_uninit`, and call `feed_bytes` and `try_init` (upstream's incremental
// API shape; a reader-based `read`/`open` takes `Bytes` here, there is no
// `std::io::Read` or file system in the published module).
//
// # Differences from upstream
// - Threads: there is no thread pool; everything runs sequentially (builder
//   `pool` and `JxlImage::pool` are not ported).
// - Errors: every fallible function raises `@bitstream.JxlError`.
// - Default CMS: the pure MoonBit `@cms` package plays the role of the `lcms2`
//   feature (it is set on every new image); `set_cms(@color.NullCms::new())`
//   disables it as upstream.

///|
/// JPEG XL image decoder builder.
pub struct JxlImageBuilder {
  priv mut tracker : @grid.AllocTracker?
  priv mut force_wide_buffers : Bool
}

///|
pub fn JxlImageBuilder::default() -> JxlImageBuilder {
  { tracker: None, force_wide_buffers: false, }
}

///|
/// Sets an allocation tracker.
pub fn JxlImageBuilder::alloc_tracker(
  self : JxlImageBuilder,
  tracker : @grid.AllocTracker,
) -> JxlImageBuilder {
  self.tracker = Some(tracker)
  self
}

///|
/// Force 32-bit Modular buffers when decoding.
pub fn JxlImageBuilder::force_wide_buffers(
  self : JxlImageBuilder,
  force_wide_buffers : Bool,
) -> JxlImageBuilder {
  self.force_wide_buffers = force_wide_buffers
  self
}

///|
/// Consumes the builder, and creates an empty, uninitialized JPEG XL image
/// decoder.
pub fn JxlImageBuilder::build_uninit(
  self : JxlImageBuilder,
) -> UninitializedJxlImage {
  {
    tracker: self.tracker,
    reader: @container.ContainerParser::new(),
    buffer: Buffer(),
    aux_boxes: AuxBoxList::new(),
    force_wide_buffers: self.force_wide_buffers,
  }
}

///|
/// Consumes the builder, and creates a JPEG XL image decoder by reading the
/// whole image from `data` (upstream `read`, with the reader's contents given
/// at once).
pub fn JxlImageBuilder::read(
  self : JxlImageBuilder,
  data : Bytes,
) -> JxlImage raise @bitstream.JxlError {
  let mut uninit = self.build_uninit()
  let len = data.length()
  let mut pos = 0
  let mut initialized : JxlImage? = None
  while initialized is None {
    // The whole input is available at once; the container parser keeps what
    // it cannot use yet, which is fed again with the rest.
    let consumed = uninit.feed_bytes(data[pos:])
    pos += consumed
    match uninit.try_init() {
      NeedMoreData(x) => {
        uninit = x
        if consumed == 0 || pos >= len {
          raise @bitstream.Io(
            "UnexpectedEof: reader ended before parsing image header",
          )
        }
      }
      Initialized(x) => initialized = Some(x)
    }
  }
  let image = initialized.unwrap()
  while !image.inner.end_of_image && pos < len {
    let consumed = image.feed_bytes(data[pos:])
    if consumed == 0 {
      break
    }
    pos += consumed
  }
  image.finalize()
  image
}

///|
/// Empty, uninitialized JPEG XL image.
///
/// ```text
/// let mut uninit_image = JxlImage::builder().build_uninit()
/// let image = for {
///   let buf = read_bytes()
///   uninit_image.feed_bytes(buf) |> ignore
///   match uninit_image.try_init() {
///     NeedMoreData(uninit) => uninit_image = uninit
///     Initialized(image) => break image
///   }
/// }
/// ```
pub struct UninitializedJxlImage {
  priv tracker : @grid.AllocTracker?
  priv reader : @container.ContainerParser
  priv buffer : Buffer
  priv aux_boxes : AuxBoxList
  priv force_wide_buffers : Bool
}

///|
/// Feeds more data into the decoder.
///
/// Returns total consumed bytes from the buffer.
pub fn UninitializedJxlImage::feed_bytes(
  self : UninitializedJxlImage,
  buf : BytesView,
) -> Int32 raise @bitstream.JxlError {
  let events = self.reader.feed_bytes(buf)
  while events.next() is Some(event) {
    match event {
      BitstreamKind(_) => ()
      Codestream(buf) => self.buffer.write_bytesview(buf)
      aux_box_event => self.aux_boxes.handle_event(aux_box_event)
    }
  }
  self.reader.previous_consumed_bytes()
}

///|
/// Returns the internal reader.
pub fn UninitializedJxlImage::reader(
  self : UninitializedJxlImage,
) -> @container.ContainerParser {
  self.reader
}

///|
/// Initialization result from `UninitializedJxlImage::try_init`.
pub enum InitializeResult {
  /// The data was not enough. Feed more data into the returned image.
  NeedMoreData(UninitializedJxlImage)
  /// The image is successfully initialized.
  Initialized(JxlImage)
}

///|
/// Try to initialize an image with the data fed into so far.
///
/// Returns
/// - `Initialized(_)` if the initialization was successful,
/// - `NeedMoreData(_)` if the data was not enough, and
/// - raises if there was a decode error during the initialization, meaning
///   invalid bitstream was given.
pub fn UninitializedJxlImage::try_init(
  self : UninitializedJxlImage,
) -> InitializeResult raise @bitstream.JxlError {
  let buffer = self.buffer.to_bytes()
  let bitstream = @bitstream.Bitstream::new(buffer)
  let image_header = @image.ImageHeader::parse(bitstream) catch {
    e if e.unexpected_eof() => return NeedMoreData(self)
    e => raise e
  }
  let embedded_icc = if image_header.metadata.colour_encoding.want_icc() {
    let icc = @color.read_icc(bitstream) catch {
      e if e.unexpected_eof() => return NeedMoreData(self)
      e => raise e
    }
    Some(@color.decode_icc(icc))
  } else {
    None
  }
  bitstream.zero_pad_to_byte()
  let skip_bytes = if image_header.metadata.preview is Some(_) {
    let frame = @frame.Frame::parse(
      bitstream,
      image_header,
      tracker=self.tracker,
    ) catch {
      e if e.unexpected_eof() => return NeedMoreData(self)
      e => raise e
    }
    let bytes_read = bitstream.num_read_bits() / 8
    let x = frame.toc().total_byte_size()
    if buffer.length() < bytes_read + x {
      return NeedMoreData(self)
    }
    x
  } else {
    0
  }
  let bytes_read = bitstream.num_read_bits() / 8 + skip_bytes
  let rest = buffer[bytes_read:]
  let render_spot_color = !image_header.metadata.grayscale()
  let mut builder = @render.RenderContext::builder()
  if embedded_icc is Some(icc) {
    builder = builder.embedded_icc(icc)
  }
  if self.tracker is Some(tracker) {
    builder = builder.alloc_tracker(tracker)
  }
  builder = builder.force_wide_buffers(self.force_wide_buffers)
  let ctx = builder.build(image_header)
  ctx.set_cms(default_cms())
  let image : JxlImage = {
    reader: self.reader,
    image_header,
    ctx,
    render_spot_color,
    inner: {
      end_of_image: false,
      buffer: b"",
      buffer_offset: bytes_read,
      frame_offsets: [],
      aux_boxes: self.aux_boxes,
    },
  }
  image.inner.feed_bytes_inner(image.ctx, rest)
  Initialized(image)
}

///|
/// The CMS set on new images (upstream: `Lcms2` with the `lcms2` feature).
fn default_cms() -> &@color.ColorManagementSystem {
  @cms.MoonCms::{ }
}

///|
/// JPEG XL image.
pub struct JxlImage {
  priv reader : @container.ContainerParser
  priv image_header : @image.ImageHeader
  priv ctx : @render.RenderContext
  priv mut render_spot_color : Bool
  priv inner : JxlImageInner
}

// # Constructors and data-feeding methods

///|
/// Creates a decoder builder with default options.
pub fn JxlImage::builder() -> JxlImageBuilder {
  JxlImageBuilder::default()
}

///|
/// Reads an image from the bytes with default options.
pub fn JxlImage::read_with_defaults(
  data : Bytes,
) -> JxlImage raise @bitstream.JxlError {
  JxlImage::builder().read(data)
}

///|
/// Feeds more data into the decoder.
///
/// Returns total consumed bytes from the buffer.
pub fn JxlImage::feed_bytes(
  self : JxlImage,
  buf : BytesView,
) -> Int32 raise @bitstream.JxlError {
  let events = self.reader.feed_bytes(buf)
  while events.next() is Some(event) {
    match event {
      BitstreamKind(_) => ()
      Codestream(buf) => self.inner.feed_bytes_inner(self.ctx, buf)
      aux_box_event => self.inner.aux_boxes.handle_event(aux_box_event)
    }
  }
  self.reader.previous_consumed_bytes()
}

///|
/// Signals the end of bitstream.
///
/// This is automatically done if `read()` is used to decode the image.
pub fn JxlImage::finalize(self : JxlImage) -> Unit raise @bitstream.JxlError {
  self.inner.aux_boxes.eof()
}

// # Image and decoder metadata accessors

///|
/// Returns the image header.
pub fn JxlImage::image_header(self : JxlImage) -> @image.ImageHeader {
  self.image_header
}

///|
/// Returns the image width with orientation applied.
pub fn JxlImage::width(self : JxlImage) -> Int32 {
  self.image_header.width_with_orientation()
}

///|
/// Returns the image height with orientation applied.
pub fn JxlImage::height(self : JxlImage) -> Int32 {
  self.image_header.height_with_orientation()
}

///|
/// Returns the *original* ICC profile embedded in the image.
pub fn JxlImage::original_icc(self : JxlImage) -> Bytes? {
  self.ctx.embedded_icc()
}

///|
/// Returns the ICC profile that describes rendered images.
///
/// The returned profile will change if different color encoding is specified
/// using `request_icc` or `request_color_encoding`.
pub fn JxlImage::rendered_icc(self : JxlImage) -> Bytes {
  let encoding = self.ctx.requested_color_encoding()
  match encoding.encoding() {
    Enum(encoding) => @color.colour_encoding_to_icc(encoding)
    IccProfile(_) => encoding.icc_profile()
  }
}

///|
/// Returns the CICP tag of the color encoding of rendered images, if there's
/// any.
pub fn JxlImage::rendered_cicp(self : JxlImage) -> FixedArray[Int32]? {
  let encoding = self.ctx.requested_color_encoding()
  encoding.encoding().cicp()
}

///|
/// Returns the pixel format of the rendered image.
pub fn JxlImage::pixel_format(self : JxlImage) -> PixelFormat {
  let encoding = self.ctx.requested_color_encoding()
  let is_grayscale = encoding.is_grayscale()
  let has_black = encoding.is_cmyk()
  let mut has_alpha = false
  for ec_info in self.image_header.metadata.ec_info {
    if ec_info.is_alpha() {
      has_alpha = true
    }
  }
  match (is_grayscale, has_black, has_alpha) {
    (false, false, false) => Rgb
    (false, false, true) => Rgba
    (false, true, false) => Cmyk
    (false, true, true) => Cmyka
    (true, _, false) => Gray
    (true, _, true) => Graya
  }
}

///|
/// Returns what HDR transfer function the image uses, if there's any.
///
/// Returns `None` if the image is not HDR one.
pub fn JxlImage::hdr_type(self : JxlImage) -> HdrType? {
  match self.ctx.suggested_hdr_tf() {
    Some(Pq) => Some(HdrType::Pq)
    Some(Hlg) => Some(HdrType::Hlg)
    _ => None
  }
}

///|
/// Returns whether the spot color channels will be rendered.
pub fn JxlImage::render_spot_color(self : JxlImage) -> Bool {
  self.render_spot_color
}

///|
/// Sets whether the spot colour channels will be rendered.
pub fn JxlImage::set_render_spot_color(
  self : JxlImage,
  render_spot_color : Bool,
) -> JxlImage {
  if render_spot_color && self.image_header.metadata.grayscale() {
    // Spot colour channels are not rendered on grayscale images
    return self
  }
  self.render_spot_color = render_spot_color
  self
}

///|
/// Returns the list of auxiliary boxes in the JPEG XL container.
///
/// The list may contain Exif and XMP metadata.
pub fn JxlImage::aux_boxes(self : JxlImage) -> AuxBoxList {
  self.inner.aux_boxes
}

///|
/// Returns the number of currently loaded keyframes.
pub fn JxlImage::num_loaded_keyframes(self : JxlImage) -> Int32 {
  self.ctx.loaded_keyframes()
}

///|
/// Returns the number of currently loaded frames, including frames that are
/// not displayed directly.
pub fn JxlImage::num_loaded_frames(self : JxlImage) -> Int32 {
  self.ctx.loaded_frames()
}

///|
/// Returns whether the image is loaded completely, without missing animation
/// keyframes or partially loaded frames.
pub fn JxlImage::is_loading_done(self : JxlImage) -> Bool {
  self.inner.end_of_image
}

///|
/// Returns frame data by keyframe index.
pub fn JxlImage::frame_by_keyframe(
  self : JxlImage,
  keyframe_index : Int32,
) -> @render.IndexedFrame? {
  self.ctx.keyframe(keyframe_index)
}

///|
/// Returns the frame header for the given keyframe index, or `None` if the
/// keyframe does not exist.
pub fn JxlImage::frame_header(
  self : JxlImage,
  keyframe_index : Int32,
) -> @frame.FrameHeader? {
  guard self.ctx.keyframe(keyframe_index) is Some(frame) else { return None }
  Some(frame.header())
}

///|
/// Returns frame data by frame index, including frames that are not displayed
/// directly.
///
/// There are some situations where a frame is not displayed directly:
/// - It may be marked as reference only, and meant to be only used by other
///   frames.
/// - It may contain LF image (which is 8x downsampled version) of another
///   VarDCT frame.
/// - Zero duration frame that is not the last frame of image is blended with
///   following frames and displayed together.
pub fn JxlImage::frame(
  self : JxlImage,
  frame_idx : Int32,
) -> @render.IndexedFrame? {
  self.ctx.frame(frame_idx)
}

///|
/// Returns the offset of frame within codestream, in bytes.
pub fn JxlImage::frame_offset(self : JxlImage, frame_index : Int32) -> Int32? {
  self.inner.frame_offsets.get(frame_index)
}

///|
/// Returns the internal reader.
pub fn JxlImage::reader(self : JxlImage) -> @container.ContainerParser {
  self.reader
}

// # Color management methods

///|
/// Sets color management system implementation to be used by the renderer.
pub fn JxlImage::set_cms(
  self : JxlImage,
  cms : &@color.ColorManagementSystem,
) -> Unit {
  self.ctx.set_cms(cms)
}

///|
/// Requests the decoder to render in specific color encoding, described by an
/// ICC profile.
///
/// Raises if it cannot parse the ICC profile.
pub fn JxlImage::request_icc(
  self : JxlImage,
  icc_profile : Bytes,
) -> Unit raise @bitstream.JxlError {
  self.ctx.request_color_encoding(
    @color.ColorEncodingWithProfile::with_icc(icc_profile),
  )
}

///|
/// Requests the decoder to render in specific color encoding, described by
/// `EnumColourEncoding`.
pub fn JxlImage::request_color_encoding(
  self : JxlImage,
  color_encoding : @image.EnumColourEncoding,
) -> Unit {
  self.ctx.request_color_encoding(
    @color.ColorEncodingWithProfile::new(color_encoding),
  )
}

// # Rendering to image buffers

///|
/// Renders the given keyframe.
pub fn JxlImage::render_frame(
  self : JxlImage,
  keyframe_index : Int32,
) -> Render raise @bitstream.JxlError {
  self.render_frame_cropped(keyframe_index)
}

///|
/// Renders the given keyframe with optional cropping region.
pub fn JxlImage::render_frame_cropped(
  self : JxlImage,
  keyframe_index : Int32,
) -> Render raise @bitstream.JxlError {
  let image = self.ctx.render_keyframe(keyframe_index)
  let image_region = self.ctx
    .image_region()
    .apply_orientation(self.image_header)
  let frame = self.ctx.keyframe(keyframe_index).unwrap()
  let frame_header = frame.header()
  let target_frame_region = image_region.translate(
    -frame_header.x0,
    -frame_header.y0,
  )
  let is_cmyk = self.ctx.requested_color_encoding().is_cmyk()
  {
    keyframe_index,
    name: frame_header.name,
    duration: frame_header.duration,
    orientation: self.image_header.metadata.orientation,
    image,
    extra_channels: self.convert_ec_info(),
    target_frame_region,
    color_bit_depth: self.image_header.metadata.bit_depth,
    is_cmyk,
    render_spot_color: self.render_spot_color,
  }
}

///|
/// Renders the currently loading keyframe.
pub fn JxlImage::render_loading_frame(
  self : JxlImage,
) -> Render raise @bitstream.JxlError {
  self.render_loading_frame_cropped()
}

///|
/// Renders the currently loading keyframe with optional cropping region.
pub fn JxlImage::render_loading_frame_cropped(
  self : JxlImage,
) -> Render raise @bitstream.JxlError {
  let (frame, image) = self.ctx.render_loading_keyframe()
  let frame_header = frame.header()
  let name = frame_header.name
  let duration = frame_header.duration
  let image_region = self.ctx
    .image_region()
    .apply_orientation(self.image_header)
  let frame = match self.ctx.frame(self.ctx.loaded_frames()) {
    Some(f) => f
    None => self.ctx.frame(self.ctx.loaded_frames() - 1).unwrap()
  }
  let frame_header = frame.header()
  let target_frame_region = image_region.translate(
    -frame_header.x0,
    -frame_header.y0,
  )
  let is_cmyk = self.ctx.requested_color_encoding().is_cmyk()
  {
    keyframe_index: self.ctx.loaded_keyframes(),
    name,
    duration,
    orientation: self.image_header.metadata.orientation,
    image,
    extra_channels: self.convert_ec_info(),
    target_frame_region,
    color_bit_depth: self.image_header.metadata.bit_depth,
    is_cmyk,
    render_spot_color: self.render_spot_color,
  }
}

///|
/// Returns current cropping region (region of interest).
pub fn JxlImage::current_image_region(self : JxlImage) -> CropInfo {
  CropInfo::from_region(self.ctx.image_region())
}

///|
/// Sets the cropping region (region of interest).
///
/// Subsequent rendering methods will crop the image buffer according to the
/// region.
pub fn JxlImage::set_image_region(
  self : JxlImage,
  region : CropInfo,
) -> JxlImage {
  self.ctx.request_image_region(region.to_region())
  self
}

// # JPEG bitstream reconstruction

///|
/// Returns availability and validity of JPEG bitstream reconstruction data.
pub fn JxlImage::jpeg_reconstruction_status(
  self : JxlImage,
) -> JpegReconstructionStatus {
  match self.inner.aux_boxes.jbrd() {
    Data(jbrd) => {
      let header = jbrd.header()
      let exif = self.inner.aux_boxes.first_exif() catch { _ => return Invalid }
      let xml = self.inner.aux_boxes.first_xml()
      if header.expected_icc_len() > 0 {
        if !self.image_header.metadata.colour_encoding.want_icc() {
          return Invalid
        } else if self.original_icc() is None {
          return NeedMoreData
        }
      }
      if header.expected_exif_len() > 0 {
        if exif.is_decoding() {
          return NeedMoreData
        } else if exif.is_not_found() {
          return Invalid
        }
      }
      if header.expected_xmp_len() > 0 {
        if xml.is_decoding() {
          return NeedMoreData
        } else if xml.is_not_found() {
          return Invalid
        }
      }
      Available
    }
    Decoding => {
      if self.num_loaded_frames() >= 2 {
        return Invalid
      }
      guard self.frame(0) is Some(frame) else { return NeedMoreData }
      let frame_header = frame.header()
      if !(frame_header.encoding is VarDct) {
        return Invalid
      }
      if !frame_header.frame_type.is_normal_frame() {
        return Invalid
      }
      NeedMoreData
    }
    NotFound => Unavailable
  }
}

///|
/// Reconstructs JPEG bitstream and returns the JPEG file.
///
/// Raises if the reconstruction data is not available, incomplete or invalid.
///
/// Note that reconstruction may fail even if `jpeg_reconstruction_status`
/// returned `Available`.
pub fn JxlImage::reconstruct_jpeg(
  self : JxlImage,
) -> Bytes raise @bitstream.JxlError {
  let aux_boxes = self.inner.aux_boxes
  let jbrd = match aux_boxes.jbrd() {
    Data(jbrd) => jbrd
    Decoding => raise @bitstream.Jbr("ReconstructionDataIncomplete")
    NotFound => raise @bitstream.Jbr("ReconstructionUnavailable")
  }
  if self.num_loaded_frames() == 0 {
    raise @bitstream.Jbr("FrameDataIncomplete")
  }
  let jbrd_header = jbrd.header()
  let expected_icc_len = jbrd_header.expected_icc_len()
  let expected_exif_len = jbrd_header.expected_exif_len()
  let expected_xmp_len = jbrd_header.expected_xmp_len()
  let icc = if expected_icc_len > 0 {
    self.original_icc().unwrap_or(b"")
  } else {
    b""
  }
  let exif = if expected_exif_len > 0 {
    match aux_boxes.first_exif() {
      Data(x) => x.payload().to_owned()
      _ => b""
    }
  } else {
    b""
  }
  let xmp = if expected_xmp_len > 0 {
    aux_boxes.first_xml().unwrap_or(b"")
  } else {
    b""
  }
  let frame = self.frame(0).unwrap()
  let out = Buffer()
  jbrd.reconstruct(frame.frame(), icc, exif, xmp).write(out)
  out.to_bytes()
}

// # Private methods

///|
fn JxlImage::convert_ec_info(self : JxlImage) -> Array[ExtraChannel] {
  self.image_header.metadata.ec_info.map(fn(ec_info) {
    { ty: ec_info.ty, name: ec_info.name, bit_depth: ec_info.bit_depth, }
  })
}

///|
priv struct JxlImageInner {
  mut end_of_image : Bool
  mut buffer : Bytes
  mut buffer_offset : Int32
  frame_offsets : Array[Int32]
  aux_boxes : AuxBoxList
}

///|
fn JxlImageInner::feed_bytes_inner(
  self : JxlImageInner,
  ctx : @render.RenderContext,
  buf : BytesView,
) -> Unit raise @bitstream.JxlError {
  let mut buf = buf
  if buf.length() == 0 {
    return
  }
  if self.end_of_image {
    self.buffer = concat_bytes(self.buffer, buf)
    return
  }
  if ctx.current_loading_frame() is Some(loading_frame) {
    let len = buf.length()
    buf = loading_frame.feed_bytes(buf)
    let count = len - buf.length()
    self.buffer_offset += count
    if loading_frame.is_loading_done() {
      let is_last = loading_frame.header().is_last
      ctx.finalize_current_frame()
      if is_last {
        self.end_of_image = true
        self.buffer = buf.to_owned()
        return
      }
    }
    if buf.length() == 0 {
      return
    }
  }
  self.buffer = concat_bytes(self.buffer, buf)
  let mut buf = self.buffer[:]
  while buf.length() > 0 {
    let bitstream = @bitstream.Bitstream::new(buf.to_owned())
    let frame = ctx.load_frame_header(bitstream) catch {
      e if e.unexpected_eof() => {
        self.buffer = buf.to_owned()
        return
      }
      e => raise e
    }
    let frame_index = frame.index()
    guard! self.frame_offsets.length() == frame_index
    self.frame_offsets.push(self.buffer_offset)
    let read_bytes = bitstream.num_read_bits() / 8
    buf = buf[read_bytes:]
    let len = buf.length()
    buf = frame.feed_bytes(buf)
    let read_bytes = read_bytes + (len - buf.length())
    self.buffer_offset += read_bytes
    if frame.is_loading_done() {
      let is_last = frame.header().is_last
      ctx.finalize_current_frame()
      if is_last {
        self.end_of_image = true
        self.buffer = buf.to_owned()
        return
      }
    }
  }
  self.buffer = b""
}

///|
fn concat_bytes(a : Bytes, b : BytesView) -> Bytes {
  if a.length() == 0 {
    return b.to_owned()
  }
  let out = Buffer()
  out.write_bytes(a)
  out.write_bytesview(b)
  out.to_bytes()
}

///|
/// Pixel format of the rendered image.
#derive(Debug, Eq, Hash)
pub(all) enum PixelFormat {
  /// Grayscale, single channel
  Gray
  /// Grayscale with alpha, two channels
  Graya
  /// RGB, three channels
  Rgb
  /// RGB with alpha, four channels
  Rgba
  /// CMYK, four channels
  Cmyk
  /// CMYK with alpha, five channels
  Cmyka
}

///|
/// Returns the number of channels of the image.
pub fn PixelFormat::channels(self : PixelFormat) -> Int32 {
  match self {
    Gray => 1
    Graya => 2
    Rgb => 3
    Rgba => 4
    Cmyk => 4
    Cmyka => 5
  }
}

///|
/// Returns whether the image is grayscale.
pub fn PixelFormat::is_grayscale(self : PixelFormat) -> Bool {
  self is (Gray | Graya)
}

///|
/// Returns whether the image has an alpha channel.
pub fn PixelFormat::has_alpha(self : PixelFormat) -> Bool {
  self is (Graya | Rgba | Cmyka)
}

///|
/// Returns whether the image has a black channel.
pub fn PixelFormat::has_black(self : PixelFormat) -> Bool {
  self is (Cmyk | Cmyka)
}

///|
/// HDR transfer function type, returned by `JxlImage::hdr_type`.
#derive(Debug, Eq)
pub(all) enum HdrType {
  /// Perceptual quantizer.
  Pq
  /// Hybrid log-gamma.
  Hlg
}

///|
/// The result of loading the keyframe.
#derive(Debug)
pub(all) enum LoadResult {
  /// The frame is loaded with the given keyframe index.
  Done(Int32)
  /// More data is needed to fully load the frame.
  NeedMoreData
  /// No more frames are present.
  NoMoreFrames
}

///|
/// The result of loading and rendering the keyframe.
pub(all) enum RenderResult {
  /// The frame is rendered.
  Done(Render)
  /// More data is needed to fully render the frame.
  NeedMoreData
  /// No more frames are present.
  NoMoreFrames
}

///|
/// The result of rendering a keyframe.
pub struct Render {
  priv keyframe_index : Int32
  priv name : String
  priv duration : UInt32
  priv orientation : Int32
  priv image : @render.ImageWithRegion
  priv extra_channels : Array[ExtraChannel]
  priv target_frame_region : @render.Region
  priv color_bit_depth : @image.BitDepth
  priv is_cmyk : Bool
  priv render_spot_color : Bool
}

///|
/// Returns the keyframe index.
pub fn Render::keyframe_index(self : Render) -> Int32 {
  self.keyframe_index
}

///|
/// Returns the name of the frame.
pub fn Render::name(self : Render) -> String {
  self.name
}

///|
/// Returns how many ticks this frame is presented.
pub fn Render::duration(self : Render) -> UInt32 {
  self.duration
}

///|
/// Returns the orientation of the image.
pub fn Render::orientation(self : Render) -> Int32 {
  self.orientation
}

///|
/// Creates a stream that writes to a buffer.
///
/// The stream will include black and alpha channels, if exist, in addition to
/// color channels. Orientation is applied.
pub fn Render::stream(self : Render) -> ImageStream {
  ImageStream::from_render(self, false)
}

///|
/// Creates a stream that writes to a buffer.
///
/// The stream will include black channels if exist, but not alpha channels.
/// Orientation is applied.
pub fn Render::stream_no_alpha(self : Render) -> ImageStream {
  ImageStream::from_render(self, true)
}

///|
/// Creates a buffer with interleaved channels, with orientation applied.
///
/// All extra channels are included. Use `stream` if only color, black and
/// alpha channels are needed.
pub fn Render::image_all_channels(self : Render) -> FrameBuffer {
  let fb = self.image.buffer()
  let bit_depth = Array::make(self.image.color_channels, self.color_bit_depth)
  for ec in self.extra_channels {
    bit_depth.push(ec.bit_depth)
  }
  let regions = self.image.regions_and_shifts().map(fn(rs) { rs.0 })
  FrameBuffer::from_grids(
    fb,
    bit_depth,
    regions,
    self.target_frame_region,
    self.orientation,
  )
}

///|
/// Creates a separate buffer by channel, with orientation applied.
///
/// All extra channels are included.
pub fn Render::image_planar(self : Render) -> Array[FrameBuffer] {
  let grids = self.image.buffer()
  let color_channels = self.image.color_channels
  let regions = self.image.regions_and_shifts()
  let out = []
  for c, grid in grids {
    let bit_depth = if c < color_channels {
      self.color_bit_depth
    } else if c - color_channels < self.extra_channels.length() {
      self.extra_channels[c - color_channels].bit_depth
    } else {
      // zip stops at the shortest iterator
      break
    }
    if c >= regions.length() {
      break
    }
    out.push(
      FrameBuffer::from_grids(
        [grid],
        [bit_depth],
        [regions[c].0],
        self.target_frame_region,
        self.orientation,
      ),
    )
  }
  out
}

///|
/// Returns the color channels.
///
/// Orientation is not applied.
pub fn Render::color_channels(self : Render) -> ArrayView[@render.ImageBuffer] {
  let color_channels = self.image.color_channels
  self.image.buffer()[:color_channels]
}

///|
/// Returns the extra channels, potentially including alpha and black channels.
///
/// Orientation is not applied.
pub fn Render::extra_channels(
  self : Render,
) -> (Array[ExtraChannel], ArrayView[@render.ImageBuffer]) {
  let color_channels = self.image.color_channels
  (self.extra_channels, self.image.buffer()[color_channels:])
}

///|
/// Extra channel of the image.
pub struct ExtraChannel {
  priv ty : @image.ExtraChannelType
  priv name : String
  priv bit_depth : @image.BitDepth
}

///|
/// Returns the type of the extra channel.
pub fn ExtraChannel::ty(self : ExtraChannel) -> @image.ExtraChannelType {
  self.ty
}

///|
/// Returns the name of the channel.
pub fn ExtraChannel::name(self : ExtraChannel) -> String {
  self.name
}

///|
/// Returns the bit depth of the channel.
pub fn ExtraChannel::bit_depth(self : ExtraChannel) -> @image.BitDepth {
  self.bit_depth
}

///|
/// Returns `true` if the channel is a black channel of CMYK image.
pub fn ExtraChannel::is_black(self : ExtraChannel) -> Bool {
  self.ty is Black
}

///|
/// Returns `true` if the channel is an alpha channel.
pub fn ExtraChannel::is_alpha(self : ExtraChannel) -> Bool {
  self.ty is Alpha(..)
}

///|
/// Returns `true` if the channel is a spot colour channel.
pub fn ExtraChannel::is_spot_colour(self : ExtraChannel) -> Bool {
  self.ty is SpotColour(..)
}

///|
/// Cropping region information.
#derive(Debug, Default, Eq)
pub(all) struct CropInfo {
  width : Int32
  height : Int32
  left : Int32
  top : Int32
}

///|
/// `impl From<CropInfo> for Region`.
pub fn CropInfo::to_region(self : CropInfo) -> @render.Region {
  { left: self.left, top: self.top, width: self.width, height: self.height, }
}

///|
/// `impl From<Region> for CropInfo`.
pub fn CropInfo::from_region(value : @render.Region) -> CropInfo {
  {
    left: if value.left < 0 {
      0
    } else {
      value.left
    },
    top: if value.top < 0 {
      0
    } else {
      value.top
    },
    width: value.width,
    height: value.height,
  }
}

///|
/// Availability and validity of JPEG bitstream reconstruction data.
#derive(Debug, Eq)
pub(all) enum JpegReconstructionStatus {
  /// JPEG bitstream reconstruction data is found. Actual reconstruction may or
  /// may not succeed.
  Available
  /// Either JPEG bitstream reconstruction data or JPEG XL image data is
  /// invalid and cannot be used for actual reconstruction.
  Invalid
  /// JPEG bitstream reconstruction data is not found. Result will *not*
  /// change.
  Unavailable
  /// JPEG bitstream reconstruction data is not found. Result may change with
  /// more data.
  NeedMoreData
}
