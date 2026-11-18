// Port of jxl-oxide/src/integration/image.rs (the `image` crate decoder):
// choosing the output sample type (u8 / u16 / f32) and colour type of a
// decoded image, and writing the first keyframe into one interleaved buffer.
// There is no `image` crate here; `ColorType` mirrors `image::ColorType` and
// the decoded samples are returned in their own types.

///|
/// Colour type of decoded images (the subset of `image::ColorType` used).
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
/// Interleaved samples of a decoded image.
pub(all) enum DecodedSamples {
  U8(FixedArray[Byte])
  U16(FixedArray[Int])
  F32(FixedArray[Float])
}

///|
/// JPEG XL decoder in the role of jxl-oxide's `integration::JxlDecoder`.
///
/// Supports:
/// - returning images of 8-bit, 16-bit integer and 32-bit float samples
/// - RGB or luma-only images, with or without alpha
/// - returning ICC profiles via `icc_profile`
/// - returning Exif metadata via `exif_metadata`
/// - cropped decoding with `read_rect`
/// - converting CMYK images to sRGB colour space
///
/// It does no colour management by itself otherwise (consumers apply the
/// returned ICC profile). Animations: only the first keyframe is returned.
pub struct JxlDecoder {
  priv image : JxlImage
  priv mut current_crop : CropInfo
}

///|
/// Initializes a decoder which reads the given image.
pub fn JxlDecoder::new(data : Bytes) -> JxlDecoder raise @bitstream.JxlError {
  let builder = JxlImage::builder().alloc_tracker(
    @grid.AllocTracker::with_limit(0x7fffffffffffffffL),
  )
  let image = builder.read(data)
  let crop = { width: image.width(), height: image.height(), left: 0, top: 0 }
  let decoder = { image, current_crop: crop }
  // Convert CMYK to sRGB
  if decoder.image.pixel_format().has_black() {
    decoder.image.request_color_encoding(
      @color.EnumColourEncoding::srgb(@color.RenderingIntent::Relative),
    )
  }
  decoder
}

///|
/// The underlying image.
pub fn JxlDecoder::image(self : JxlDecoder) -> JxlImage {
  self.image
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
/// Width and height with orientation applied.
pub fn JxlDecoder::dimensions(self : JxlDecoder) -> (Int, Int) {
  (self.image.width(), self.image.height())
}

///|
/// Colour type of `read_image`'s output.
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
/// ICC profile of `read_image`'s output (always present).
pub fn JxlDecoder::icc_profile(self : JxlDecoder) -> Bytes? {
  Some(self.image.rendered_icc())
}

///|
/// The first Exif box's payload, if any.
pub fn JxlDecoder::exif_metadata(
  self : JxlDecoder,
) -> Bytes? raise @bitstream.JxlError {
  match self.image.aux_boxes().first_exif() {
    Data(exif) => Some(exif.payload().to_owned())
    _ => None
  }
}

///|
/// Decodes the first keyframe into interleaved samples of `color_type()`.
pub fn JxlDecoder::read_image(
  self : JxlDecoder,
) -> DecodedSamples raise @bitstream.JxlError {
  let crop = {
    width: self.image.width(),
    height: self.image.height(),
    left: 0,
    top: 0,
  }
  self.read_image_inner(crop)
}

///|
/// Decodes a region of the first keyframe (`image::ImageDecoderRect`), rows
/// packed without padding.
pub fn JxlDecoder::read_rect(
  self : JxlDecoder,
  x : Int,
  y : Int,
  width : Int,
  height : Int,
) -> DecodedSamples raise @bitstream.JxlError {
  self.read_image_inner({ width, height, left: x, top: y })
}

///|
fn JxlDecoder::read_image_inner(
  self : JxlDecoder,
  crop : CropInfo,
) -> DecodedSamples raise @bitstream.JxlError {
  if self.current_crop != crop {
    self.image.set_image_region(crop) |> ignore
    self.current_crop = crop
  }
  if self.image.frame_by_keyframe(0) is None &&
    self.image.num_loaded_keyframes() == 0 &&
    self.image.is_loading_done() {
    raise @bitstream.Io("UnexpectedEof: reader ended before parsing first frame")
  }
  let render = if self.image.num_loaded_keyframes() > 0 {
    self.image.render_frame(0)
  } else {
    self.image.render_loading_frame()
  }
  let stream = render.stream()
  let len = stream.width() * stream.height() * stream.channels()
  if self.is_float() && !self.image.pixel_format().is_grayscale() {
    let buf = FixedArray::make(len, (0.0 : Float))
    stream.write_to_buffer_f32(buf) |> ignore
    F32(buf)
  } else if self.need_16bit() {
    let buf = FixedArray::make(len, 0)
    stream.write_to_buffer_u16(buf) |> ignore
    U16(buf)
  } else {
    let buf = FixedArray::make(len, b'\x00')
    stream.write_to_buffer_u8(buf) |> ignore
    U8(buf)
  }
}
