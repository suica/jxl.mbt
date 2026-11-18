// Port of jxl-oxide-tests/tests/cms/mod.rs (helpers).

///|
/// `PathBuf::from(env!("CARGO_MANIFEST_DIR")).push("tests/cms/cmyk_layers.jxl")`,
/// opened as `JxlImage::builder().open(&path)`.
pub fn open_cmyk_layers() -> @jxl.JxlImage raise Error {
  let path = @harness.manifest_dir() + "/tests/cms/cmyk_layers.jxl"
  @jxl.JxlImage::builder().read(@jxl.Cursor::new(@harness.read_file(path)))
}

///|
/// `EnumColourEncoding { tf: TransferFunction::Linear, ..srgb(Relative) }`
pub fn linear_srgb() -> @image.EnumColourEncoding {
  let encoding = @image.EnumColourEncoding::srgb(
    @image.RenderingIntent::Relative,
  )
  encoding.tf = Linear
  encoding
}

///|
/// Renders frame 0 and interleaves its three colour channels
/// (`render.color_channels()`, `as_float().unwrap().buf()`).
pub fn render_frame_rgb(image : @jxl.JxlImage) -> FixedArray[Float] raise Error {
  let width = image.width()
  let height = image.height()
  let render = image.render_frame(0)
  let channels = render.color_channels()
  guard channels.length() == 3 else { abort("unreachable") }
  let planes = channels.map(fn(x) { x.as_float().unwrap().buf() })
  let frame = FixedArray::make(width * height * 3, (0.0 : Float))
  for i in 0..<(width * height) {
    frame[i * 3] = planes[0][i]
    frame[i * 3 + 1] = planes[1][i]
    frame[i * 3 + 2] = planes[2][i]
  }
  frame
}
