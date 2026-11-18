// Port of jxl-oxide-tests/tests/cms/mod.rs. Upstream renders cmyk_layers.jxl
// to linear sRGB with Little CMS 2 and with moxcms and requires a
// SSIMULACRA2 score of at least 90 between the two. Here the image is
// rendered with the MoonBit CMS (`@cms`, the default) and compared with both
// of upstream's renders (fixtures from `scripts/fetch_fixtures.sh cms`;
// lcms2 vs moxcms itself scores 92.86).

///|
fn render_linear_srgb() -> (FixedArray[Float], Int, Int) raise Error {
  let data = @harness.read_file(@harness.data_dir() + "/cms/cmyk_layers.jxl")
  let image = @jxl.JxlImage::builder().read(data)
  let width = image.width()
  let height = image.height()
  let encoding = @image.EnumColourEncoding::srgb(@image.RenderingIntent::Relative)
  encoding.tf = Linear
  image.request_color_encoding(encoding)
  let render = image.render_frame(0)
  let channels = render.color_channels()
  guard channels.length() == 3 else {
    fail("expected 3 color channels, got \{channels.length()}")
  }
  let planes = channels.map(fn(c) {
    match c.as_float() {
      Some(g) => g.buf()
      None => abort("color channel is not float")
    }
  })
  let frame = FixedArray::make(width * height * 3, (0.0 : Float))
  for i in 0..<(width * height) {
    frame[i * 3] = planes[0][i]
    frame[i * 3 + 1] = planes[1][i]
    frame[i * 3 + 2] = planes[2][i]
  }
  (frame, width, height)
}

///|
fn check_against(reference : String) -> Unit raise Error {
  let path = @harness.cache_dir() + "/cms/cmyk_layers." + reference + ".npy"
  guard @harness.read_fixture(path) is Some(buf) else { return }
  let expected = @harness.read_npy(buf)
  let (frame, width, height) = render_linear_srgb()
  let c = expected.shape[3]
  assert_eq((expected.shape[2], expected.shape[1]), (width, height))
  let reference_frame = FixedArray::makei(width * height * 3, fn(i) {
    expected.data[i / 3 * c + i % 3]
  })
  let score = @harness.compute_frame_ssimulacra2(
    reference_frame,
    frame,
    width,
    height,
  )
  if !(score >= 90.0) {
    fail("SSIMULACRA2 score too low (score < 90.0), score = \{score}")
  }
}

///|
test "cms/cmyk_vs_lcms2" {
  check_against("lcms2")
}

///|
test "cms/cmyk_vs_moxcms" {
  check_against("moxcms")
}
