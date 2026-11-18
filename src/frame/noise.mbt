///|
#derive(Debug)
pub(all) struct NoiseParameters {
  lut : FixedArray[Float]
}

///|
pub fn NoiseParameters::parse(
  bs : @bitstream.Bitstream,
) -> NoiseParameters raise @bitstream.JxlError {
  let lut = FixedArray::make(8, (0.0 : Float))
  for i in 0..<8 {
    lut[i] = Float::from_uint(bs.read_bits(10)) / Float::from_int(1 << 10)
  }
  { lut, }
}
