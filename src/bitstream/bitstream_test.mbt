///|
test "read bits lsb first" {
  let bs = @bitstream.Bitstream::new(
    b"\xb5\x01\xff\xff\xff\xff\xff\xff\xff\x7f",
  )
  assert_eq(bs.read_bits(1), 1)
  assert_eq(bs.read_bits(2), 2)
  assert_eq(bs.read_bits(5), 0x16)
  assert_eq(bs.read_bits(8), 1)
  assert_eq(bs.num_read_bits(), 16)
  assert_eq(bs.read_bits(32), 0xffffffff)
  bs.skip_bits(20)
  assert_eq(bs.read_bits(12), 0x7ff)
  let r : Result[UInt32, @bitstream.JxlError] = Ok(bs.read_bits(1)) catch {
    e => Err(e)
  }
  assert_true(r is Err(@bitstream.Eof))
}

///|
test "u32 and signed" {
  // selector 2 -> 2 + u(4); bits: 01 (sel=2 lsb first is 0b10) then 4 bits 0b0011
  let bs = @bitstream.Bitstream::new(b"\x0e")
  let v = bs.read_u32(
    @bitstream.c(0),
    @bitstream.c(1),
    @bitstream.cu(2, 4),
    @bitstream.cu(18, 6),
  )
  assert_eq(v, 5)
  assert_eq(@bitstream.unpack_signed(0), 0)
  assert_eq(@bitstream.unpack_signed(1), -1)
  assert_eq(@bitstream.unpack_signed(4), 2)
  assert_eq(@bitstream.unpack_signed(0xffffffff), -2147483648)
}

///|
test "f16" {
  let bs = @bitstream.Bitstream::new(b"\x00\x3c\x00\xc0")
  assert_eq(bs.read_f16_as_f32(), 1.0)
  assert_eq(bs.read_f16_as_f32(), -2.0)
}
