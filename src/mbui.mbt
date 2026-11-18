// The adapter in the shape of mbui's picture decoders (`decode_png`,
// `decode_jpeg`, `decode_webp` in `pixels/`): a JPEG XL file to its width,
// height and RGBA bytes.

///|
/// The image's width, height and RGBA bytes (8 bits per sample, straight
/// alpha, rows top to bottom, 4 bytes a pixel, sRGB), None where it is not a
/// JPEG XL image this reads.
///
/// The first keyframe of an animation; turned as its orientation says;
/// grayscale spread to R, G and B; alpha 255 where the image has none,
/// premultiplied alpha undone; colours
/// converted to sRGB (CMYK and ICC-profiled images through the CMS).
pub fn decode_jxl(b : Bytes) -> (Int, Int, FixedArray[Byte])? {
  if !is_jxl(b) {
    return None
  }
  decode_jxl_rgba8(b) catch {
    _ => None
  }
}

///|
fn decode_jxl_rgba8(
  b : Bytes,
) -> (Int, Int, FixedArray[Byte])? raise @bitstream.JxlError {
  // Bound what one picture may allocate: room for a few float planes per
  // pixel of the size its header gives, so crafted sizes fail cleanly.
  guard jxl_size(b) is Some((w, h)) else { return None }
  let limit = 256L * 1024L * 1024L + w.to_int64() * h.to_int64() * 96L
  let limit = if limit > 4L * 1024L * 1024L * 1024L {
    4L * 1024L * 1024L * 1024L
  } else {
    limit
  }
  let image = JxlImage::builder()
    .alloc_tracker(@grid.AllocTracker::with_limit(limit))
    .read(b)
  if image.num_loaded_keyframes() == 0 {
    return None
  }
  let pixel_format = image.pixel_format()
  // Render in sRGB (gray images in sRGB gray: spread to RGB below).
  let is_gray = pixel_format.is_grayscale()
  if is_gray {
    image.request_color_encoding(
      @color.EnumColourEncoding::gray_srgb(@color.RenderingIntent::Relative),
    )
  } else {
    image.request_color_encoding(
      @color.EnumColourEncoding::srgb(@color.RenderingIntent::Relative),
    )
  }
  // Whether the alpha channel the stream picks (the first one) is
  // premultiplied: the output is straight alpha.
  let mut premultiplied = false
  for ec in image.image_header().metadata.ec_info {
    if ec.is_alpha() {
      premultiplied = ec.alpha_associated() is Some(true)
      break
    }
  }
  let render = image.render_frame(0)
  let stream = render.stream()
  let width = stream.width()
  let height = stream.height()
  let channels = stream.channels()
  let n = width * height
  let samples = FixedArray::make(n * channels, (0.0 : Float))
  stream.write_to_buffer_f32(samples) |> ignore
  let color = if is_gray { 1 } else { 3 }
  let has_alpha = channels > color
  let out = FixedArray::make(n * 4, b'\xff')
  for i in 0..<n {
    let s = i * channels
    let d = i * 4
    let a = if has_alpha { samples[s + channels - 1] } else { 1.0 }
    let unpremultiply = fn(v : Float) -> Float {
      if premultiplied && a > 0.0 && a < 1.0 {
        v / a
      } else {
        v
      }
    }
    if is_gray {
      let v = sample_f32_to_u8(unpremultiply(samples[s])).to_byte()
      out[d] = v
      out[d + 1] = v
      out[d + 2] = v
    } else {
      out[d] = sample_f32_to_u8(unpremultiply(samples[s])).to_byte()
      out[d + 1] = sample_f32_to_u8(unpremultiply(samples[s + 1])).to_byte()
      out[d + 2] = sample_f32_to_u8(unpremultiply(samples[s + 2])).to_byte()
    }
    if has_alpha {
      out[d + 3] = sample_f32_to_u8(a).to_byte()
    }
  }
  Some((width, height, out))
}
