// Port of jxl-oxide/src/integration/image.rs: `JxlDecoder`, the decoder of
// the `image` crate integration (`image::ImageDecoder` and
// `image::ImageDecoderRect`).
//
// There is no `image` crate in MoonBit, so the trait methods are methods of
// `JxlDecoder`, `image::ColorType` is `ColorType` and `image::Limits` is
// `Limits`. Output buffers are bytes, samples in native (little-endian)
// order as `bytemuck` casts them. `register_image_decoding_hook` has no
// counterpart (it registers the decoder with the `image` crate).

///|
/// Colour type of decoded images (the variants of `image::ColorType` used).
#derive(Debug, Eq)
pub(all) enum ColorType {
  L8
  La8
  Rgb8
  Rgba8
  L16
  La16
  Rgb16
  Rgba16
  Rgb32F
  Rgba32F
}

///|
/// Bytes per pixel (`ColorType::bytes_per_pixel`).
pub fn ColorType::bytes_per_pixel(self : ColorType) -> Int {
  match self {
    L8 => 1
    La8 => 2
    Rgb8 => 3
    Rgba8 => 4
    L16 => 2
    La16 => 4
    Rgb16 => 6
    Rgba16 => 8
    Rgb32F => 12
    Rgba32F => 16
  }
}

///|
/// `image::Limits`: `None` means no limit.
#derive(Debug, Default)
pub(all) struct Limits {
  max_image_width : Int?
  max_image_height : Int?
  max_alloc : Int64?
}

///|
/// JPEG XL decoder which implements the `image` crate's decoder interface.
///
/// Supported features:
/// - Returning images of 8-bit, 16-bit integer and 32-bit float samples
/// - RGB or luma-only images, with or without alpha
/// - Returning ICC profiles via `icc_profile`
/// - Returning Exif metadata via `exif_metadata`
/// - Setting decoder limits (caveat: memory limits are not strict)
/// - Cropped decoding with `read_rect`
/// - (When a CMS is set) Converting CMYK images to sRGB color space
///
/// Not implemented (as upstream): decoding animations.
///
/// `JxlDecoder` doesn't do color management by itself (except for CMYK
/// images). Consumers should apply appropriate color transforms using the
/// ICC profile returned by `icc_profile()`.
pub struct JxlDecoder {
  priv reader : &Read
  priv image : JxlImage
  priv mut current_crop : CropInfo
  priv mut current_memory_limit : Int64
  priv buf : FixedArray[Byte]
  priv mut buf_valid : Int
}

///|
let usize_max : Int64 = 0x7fffffffffffffffL

///|
/// Initializes a decoder which reads from given image stream.
///
/// Decoder will be initialized with default thread pool.
pub fn JxlDecoder::new(reader : &Read) -> JxlDecoder raise @bitstream.JxlError {
  let builder = JxlImage::builder().alloc_tracker(
    @grid.AllocTracker::with_limit(usize_max),
  )
  JxlDecoder::init(builder, reader)
}

///|
/// Initializes a decoder which reads from given image stream, with custom
/// thread pool.
pub fn JxlDecoder::with_thread_pool(
  reader : &Read,
  pool : @threadpool.JxlThreadPool,
) -> JxlDecoder raise @bitstream.JxlError {
  let builder = JxlImage::builder()
    .pool(pool)
    .alloc_tracker(@grid.AllocTracker::with_limit(usize_max))
  JxlDecoder::init(builder, reader)
}

///|
fn JxlDecoder::init(
  builder : JxlImageBuilder,
  reader : &Read,
) -> JxlDecoder raise @bitstream.JxlError {
  let buf = FixedArray::make(4096, b'\x00')
  let (image, buf_valid) = JxlDecoder::init_image(builder, reader, buf)
  let crop = { width: image.width(), height: image.height(), left: 0, top: 0 }
  let decoder = {
    reader,
    image,
    current_memory_limit: usize_max,
    current_crop: crop,
    buf,
    buf_valid,
  }
  // Convert CMYK to sRGB
  if decoder.image.pixel_format().has_black() {
    decoder.image.request_color_encoding(
      @image.EnumColourEncoding::srgb(@image.RenderingIntent::Relative),
    )
  }
  decoder
}

///|
fn JxlDecoder::init_image(
  builder : JxlImageBuilder,
  reader : &Read,
  buf : FixedArray[Byte],
) -> (JxlImage, Int) raise @bitstream.JxlError {
  let mut uninit = builder.build_uninit()
  let mut buf_valid = 0
  while true {
    let count = reader.read(buf, buf_valid, buf.length())
    if count == 0 {
      raise @bitstream.Io(
        "UnexpectedEof: reader ended before parsing image header",
      )
    }
    buf_valid += count
    let consumed = uninit.feed_bytes(Bytes::from_array(buf[:buf_valid])[:])
    copy_to_front(buf, consumed, buf_valid)
    buf_valid -= consumed
    match uninit.try_init() {
      NeedMoreData(x) => uninit = x
      Initialized(x) => return (x, buf_valid)
    }
  }
  abort("unreachable")
}

///|
fn JxlDecoder::load_until_condition(
  self : JxlDecoder,
  predicate : (JxlImage) -> Bool raise @bitstream.JxlError,
) -> Unit raise @bitstream.JxlError {
  while !predicate(self.image) {
    let count = self.reader.read(self.buf, self.buf_valid, self.buf.length())
    if count == 0 {
      break
    }
    self.buf_valid += count
    let consumed = self.image.feed_bytes(
      Bytes::from_array(self.buf[:self.buf_valid])[:],
    )
    copy_to_front(self.buf, consumed, self.buf_valid)
    self.buf_valid -= consumed
  }
}

///|
fn JxlDecoder::load_until_first_keyframe(
  self : JxlDecoder,
) -> Unit raise @bitstream.JxlError {
  self.load_until_condition(fn(image) { image.ctx.loaded_keyframes() > 0 })
  if self.image.frame_by_keyframe(0) is None {
    raise @bitstream.Io(
      "UnexpectedEof: reader ended before parsing first frame",
    )
  }
}

///|
fn JxlDecoder::load_until_exif(self : JxlDecoder) -> Unit raise @bitstream.JxlError {
  self.load_until_condition(fn(image) raise @bitstream.JxlError {
    !image.aux_boxes().first_exif().is_decoding()
  })
}

///|
fn JxlDecoder::is_float(self : JxlDecoder) -> Bool {
  match self.image.image_header().metadata.bit_depth {
    FloatSample(..) => true
    IntegerSample(bits_per_sample~) => bits_per_sample >= 17
  }
}

///|
fn JxlDecoder::need_16bit(self : JxlDecoder) -> Bool {
  self.image.image_header().metadata.bit_depth.bits_per_sample() > 8
}

///|
fn JxlDecoder::read_image_inner(
  self : JxlDecoder,
  crop : CropInfo,
  buf : FixedArray[Byte],
  buf_stride : Int?,
) -> Unit raise @bitstream.JxlError {
  if self.current_crop != crop {
    self.image.set_image_region(crop) |> ignore
    self.current_crop = crop
  }
  self.load_until_first_keyframe()
  let render = if self.image.num_loaded_keyframes() > 0 {
    self.image.render_frame(0)
  } else {
    self.image.render_loading_frame()
  }
  let stream = render.stream()
  let stride_base = stream.width() * stream.channels()
  if self.is_float() && !self.image.pixel_format().is_grayscale() {
    let stride = buf_stride.unwrap_or(stride_base * 4)
    stream_to_buf(stream, buf, stride, (0.0 : Float))
  } else if self.need_16bit() {
    let stride = buf_stride.unwrap_or(stride_base * 2)
    stream_to_buf(stream, buf, stride, (0 : UInt16))
  } else {
    let stride = buf_stride.unwrap_or(stride_base)
    stream_to_buf(stream, buf, stride, b'\x00')
  }
}

///|
/// `image::ImageDecoder::dimensions`.
pub fn JxlDecoder::dimensions(self : JxlDecoder) -> (Int, Int) {
  (self.image.width(), self.image.height())
}

///|
/// `image::ImageDecoder::color_type`.
pub fn JxlDecoder::color_type(self : JxlDecoder) -> ColorType {
  let pixel_format = self.image.pixel_format()
  match
    (
      pixel_format.is_grayscale(),
      pixel_format.has_alpha(),
      self.is_float(),
      self.need_16bit(),
    ) {
    (false, false, false, false) => Rgb8
    (false, false, false, true) => Rgb16
    (false, false, true, _) => Rgb32F
    (false, true, false, false) => Rgba8
    (false, true, false, true) => Rgba16
    (false, true, true, _) => Rgba32F
    (true, false, _, false) => L8
    (true, false, _, true) => L16
    (true, true, _, false) => La8
    (true, true, _, true) => La16
  }
}

///|
/// `image::ImageDecoder::total_bytes`.
pub fn JxlDecoder::total_bytes(self : JxlDecoder) -> Int64 {
  let (w, h) = self.dimensions()
  w.to_int64() * h.to_int64() * self.color_type().bytes_per_pixel().to_int64()
}

///|
/// `image::ImageDecoder::read_image`: `buf` has `total_bytes()` bytes.
pub fn JxlDecoder::read_image(
  self : JxlDecoder,
  buf : FixedArray[Byte],
) -> Unit raise @bitstream.JxlError {
  let crop = {
    width: self.image.width(),
    height: self.image.height(),
    left: 0,
    top: 0,
  }
  self.read_image_inner(crop, buf, None)
}

///|
/// `image::ImageDecoder::icc_profile`.
pub fn JxlDecoder::icc_profile(self : JxlDecoder) -> Bytes? {
  Some(self.image.rendered_icc())
}

///|
/// `image::ImageDecoder::exif_metadata`.
pub fn JxlDecoder::exif_metadata(
  self : JxlDecoder,
) -> Bytes? raise @bitstream.JxlError {
  self.load_until_exif()
  let aux_boxes = self.image.aux_boxes()
  guard aux_boxes.first_exif() is Data(exif) else { return None }
  Some(exif.payload().to_owned())
}

///|
/// `image::ImageDecoder::set_limits`.
pub fn JxlDecoder::set_limits(
  self : JxlDecoder,
  limits : Limits,
) -> Unit raise @bitstream.JxlError {
  if limits.max_image_width is Some(max_width) && self.image.width() > max_width {
    raise @bitstream.ValidationFailed("Limits: DimensionError")
  }
  if limits.max_image_height is Some(max_height) &&
    self.image.height() > max_height {
    raise @bitstream.ValidationFailed("Limits: DimensionError")
  }
  match (self.image.ctx.alloc_tracker(), limits.max_alloc) {
    (Some(tracker), max_alloc) => {
      let new_memory_limit = max_alloc.unwrap_or(usize_max)
      if new_memory_limit > self.current_memory_limit {
        tracker.expand_limit(new_memory_limit - self.current_memory_limit)
      } else {
        tracker.shrink_limit(self.current_memory_limit - new_memory_limit) catch {
          _ => raise @bitstream.OutOfMemory(0)
        }
      }
      self.current_memory_limit = new_memory_limit
    }
    (None, None) => ()
    (None, Some(_)) => raise @bitstream.NotSupported("Limits: Unsupported")
  }
}

///|
/// `image::ImageDecoderRect::read_rect`.
pub fn JxlDecoder::read_rect(
  self : JxlDecoder,
  x : Int,
  y : Int,
  width : Int,
  height : Int,
  buf : FixedArray[Byte],
  row_pitch : Int,
) -> Unit raise @bitstream.JxlError {
  let crop = { width, height, left: x, top: y }
  self.read_image_inner(crop, buf, Some(row_pitch))
}

///|
/// Stores samples as their native bytes (`bytemuck::cast_slice`).
priv trait SampleBytes: FrameBufferSample {
  size() -> Int
  put(Self, FixedArray[Byte], Int) -> Unit
}

///|
impl SampleBytes for Float with size() {
  4
}

///|
impl SampleBytes for Float with put(self, buf, at) {
  let u = self.reinterpret_as_uint()
  buf[at] = u.to_byte()
  buf[at + 1] = (u >> 8).to_byte()
  buf[at + 2] = (u >> 16).to_byte()
  buf[at + 3] = (u >> 24).to_byte()
}

///|
impl SampleBytes for UInt16 with size() {
  2
}

///|
impl SampleBytes for UInt16 with put(self, buf, at) {
  buf[at] = self.to_byte()
  buf[at + 1] = (self >> 8).to_byte()
}

///|
impl SampleBytes for Byte with size() {
  1
}

///|
impl SampleBytes for Byte with put(self, buf, at) {
  buf[at] = self
}

///|
fn[S : SampleBytes] stream_to_buf(
  stream : ImageStream,
  buf : FixedArray[Byte],
  buf_stride : Int,
  zero : S,
) -> Unit {
  let size = S::size()
  let stride = stream.width() * stream.channels() * size
  guard buf_stride >= stride else {
    abort("assertion failed: buf_stride >= stride")
  }
  guard buf.length() == buf_stride * stream.height() else {
    abort("assertion failed: buf.len() == buf_stride * height")
  }
  // write row by row through a sample buffer, then copy the bytes
  let row = FixedArray::make(stream.width() * stream.channels(), zero)
  for y in 0..<stream.height() {
    stream.write_to_buffer(row) |> ignore
    let base = y * buf_stride
    for i, v in row {
      v.put(buf, base + i * size)
    }
  }
}
