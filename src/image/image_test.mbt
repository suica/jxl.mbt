///|
test "size header ratio" {
  // div8 = 1, h_div8 = 1 + u(5) = 4 (raw 3), ratio = 1 → width = height = 32
  // bits (LSB first): 1, 00011, 100
  let bs = @bitstream.Bitstream::new(b"\x47\x00")
  let size = @image.SizeHeader::parse(bs)
  assert_eq(size.height, 32)
  assert_eq(size.width, 32)
}

///|
test "bit depth float sample" {
  let bd : @image.BitDepth = FloatSample(bits_per_sample=16, exp_bits=5)
  // 0x3c00 is 1.0 in half precision
  assert_eq(bd.parse_integer_sample(0x3c00), 1.0)
  assert_eq(bd.parse_integer_sample(0xc000), -2.0)
  let bd : @image.BitDepth = IntegerSample(bits_per_sample=8)
  assert_eq(bd.parse_integer_sample(255), 1.0)
}

///|
test "default metadata" {
  let m = @image.ImageMetadata::default()
  assert_eq(m.up2_weight.length(), 15)
  assert_eq(m.up8_weight.length(), 210)
  assert_true(m.colour_encoding.is_srgb())
  assert_eq(m.apply_orientation(10, 20, 0, 0, false), (10, 20, 0, 0))
}
