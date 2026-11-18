///|
test "open/native file" {
  // cwd is the module root when testing
  let image = @jxl.JxlImage::builder().open("tests/tests/cms/cmyk_layers.jxl")
  assert_eq((image.width(), image.height()), (512, 512))
  assert_true(image.is_loading_done())
}

///|
test "open/missing file raises Io" {
  let r = try {
    @jxl.JxlImage::open_with_defaults("does/not/exist.jxl") |> ignore
    None
  } catch {
    e => Some(e)
  }
  assert_true(r is Some(@bitstream.Io(_)))
}
