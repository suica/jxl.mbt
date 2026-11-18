///|
test "image/decode_u8" {
  check_decode("lz77_flower", Rgb8, 834, 244)
}

///|
test "image/decode_u16" {
  check_decode("sunset_logo", Rgba16, 924, 1386)
}

///|
test "image/decode_f32" {
  check_decode("lossless_pfm", Rgb32F, 500, 500)
}

///|
test "image/decode_gray_xyb" {
  check_decode("grayscale", L8, 200, 200)
}

///|
test "image/decode_gray_modular" {
  check_decode("grayscale_public_university", L8, 2880, 1620)
}

///|
test "image/decode_cmyk" {
  check_decode("cmyk_layers", Rgba8, 512, 512)
}

///|
test "image/icc_profile" {
  guard open_decoder("grayscale") is Some(decoder) else { return }
  let icc = decoder.icc_profile().unwrap()
  let expected = @harness.read_file(
    @harness.data_dir() + "/image/grayscale.icc",
  )
  assert_eq(icc, expected)
}

///|
test "image/with_reference_frame" {
  guard open_decoder("patches") is Some(decoder) else { return }
  decoder.read_image() |> ignore
  assert_eq(decoder.dimensions(), (1600, 1096))
}
