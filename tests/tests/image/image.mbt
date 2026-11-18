// Port of jxl-oxide-tests/tests/image/mod.rs, with `JxlDecoder` and
// `DynamicImage::from_decoder` (which reads the whole image).

///|
pub fn decoder_for(name : String) -> @jxl.JxlDecoder raise Error {
  let path = @harness.conformance_path(name)
  // `File::open(path).unwrap()`
  let file = @jxl.Cursor::new(@harness.read_file(path))
  @jxl.JxlDecoder::new(file)
}

///|
/// `DynamicImage::from_decoder(decoder)`: reads `total_bytes()` bytes.
pub fn from_decoder(
  decoder : @jxl.JxlDecoder,
) -> (@jxl.ColorType, Int32, Int32) raise Error {
  let (width, height) = decoder.dimensions()
  let color = decoder.color_type()
  let buf = FixedArray::make(decoder.total_bytes().to_int(), b'\x00')
  decoder.read_image(buf)
  (color, width, height)
}
