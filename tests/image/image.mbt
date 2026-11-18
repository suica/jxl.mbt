// Port of jxl-oxide-tests/tests/image/mod.rs: output sample types and colour
// types chosen as the `image` crate integration does (`@jxl.JxlDecoder`).

///|
pub fn open_decoder(name : String) -> @jxl.JxlDecoder? raise Error {
  guard @harness.read_fixture(@harness.conformance_path(name)) is Some(data) else {
    return None
  }
  Some(@jxl.JxlDecoder::new(data))
}

///|
/// Decodes the image and checks its colour type, size and sample count.
pub fn check_decode(
  name : String,
  color : @jxl.ColorType,
  width : Int32,
  height : Int32,
) -> Unit raise Error {
  guard open_decoder(name) is Some(decoder) else { return }
  assert_eq(decoder.color_type(), color)
  assert_eq(decoder.dimensions(), (width, height))
  let channels = match color {
    L8 | L16 => 1
    La8 | La16 => 2
    Rgb8 | Rgb16 | Rgb32F => 3
    Rgba8 | Rgba16 | Rgba32F => 4
  }
  let len = width * height * channels
  match (decoder.read_image(), color) {
    (U8(buf), L8 | La8 | Rgb8 | Rgba8) => assert_eq(buf.length(), len)
    (U16(buf), L16 | La16 | Rgb16 | Rgba16) => {
      assert_eq(buf.length(), len)
      for v in buf {
        guard v >= 0 && v <= 65535 else {
          fail("u16 sample out of range: \{v}")
        }
      }
    }
    (F32(buf), Rgb32F | Rgba32F) => assert_eq(buf.length(), len)
    _ => fail("sample type does not match colour type of \{name}")
  }
}
