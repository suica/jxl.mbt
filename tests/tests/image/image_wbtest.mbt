///|
test "image/decode_u8" {
  let decoder = decoder_for("lz77_flower")
  let (color, width, height) = from_decoder(decoder)
  assert_eq(color, Rgb8)
  assert_eq(width, 834)
  assert_eq(height, 244)
}

///|
test "image/decode_u16" {
  let decoder = decoder_for("sunset_logo")
  let (color, width, height) = from_decoder(decoder)
  assert_eq(color, Rgba16)
  assert_eq(width, 924)
  assert_eq(height, 1386)
}

///|
test "image/decode_f32" {
  let decoder = decoder_for("lossless_pfm")
  let (color, width, height) = from_decoder(decoder)
  assert_eq(color, Rgb32F)
  assert_eq(width, 500)
  assert_eq(height, 500)
}

///|
test "image/decode_gray_xyb" {
  let decoder = decoder_for("grayscale")
  let (color, width, height) = from_decoder(decoder)
  assert_eq(color, L8)
  assert_eq(width, 200)
  assert_eq(height, 200)
}

///|
test "image/decode_gray_modular" {
  let decoder = decoder_for("grayscale_public_university")
  let (color, width, height) = from_decoder(decoder)
  assert_eq(color, L8)
  assert_eq(width, 2880)
  assert_eq(height, 1620)
}

///|
test "image/decode_cmyk" {
  let decoder = decoder_for("cmyk_layers")
  let (color, width, height) = from_decoder(decoder)
  assert_eq(color, Rgba8)
  assert_eq(width, 512)
  assert_eq(height, 512)
}

///|
test "image/icc_profile" {
  let decoder = decoder_for("grayscale")
  let icc = decoder.icc_profile().unwrap()
  // `include_bytes!("./grayscale.icc")`
  let expected = @harness.read_file(
    @harness.manifest_dir() + "/tests/image/grayscale.icc",
  )
  assert_eq(icc, expected)
}

///|
test "image/with_reference_frame" {
  let decoder = decoder_for("patches")
  let (_, width, height) = from_decoder(decoder)
  assert_eq(width, 1600)
  assert_eq(height, 1096)
}
