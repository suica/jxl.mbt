///|
test "is_jxl" {
  assert_true(@jxl.is_jxl(b"\xff\x0a\x00"))
  assert_true(@jxl.is_jxl(b"\x00\x00\x00\x0cJXL \x0d\x0a\x87\x0a\x00\x00"))
  assert_false(@jxl.is_jxl(b"\xff\xd8\xff"))
  assert_false(@jxl.is_jxl(b"\xff"))
  assert_false(@jxl.is_jxl(b""))
}

///|
test "jxl_size/bare codestream" {
  // the 1x1 image from jxl-oxide's lib.rs docs example (bare codestream)
  let b = b"\xff\x0a\x30\x54\x10\x09\x08\x06\x01\x00\x78\x00\x4b\x38\x41\x3c\xb6\x3a\x51\xfe"
  assert_true(@jxl.jxl_size(b) is Some(_))
  assert_eq(@jxl.jxl_size(b"\xff\x0a"), None)
  assert_eq(@jxl.jxl_size(b"\x89PNG"), None)
}

///|
test "jxl_size/div8 and ratio" {
  // div8=1, height=(0b00111+1)*8=64, ratio=1 (1:1), all_default=1
  // bits LSB first: 1, 00111 (7 -> 11100 LSB-first), 100 (ratio 1), 1
  // byte0 bits: [1][1 1 1 0 0][1 0] -> 0b01_00111_1 read LSB first
  let bits = [1, 1, 1, 1, 0, 0, 1, 0, 0, 1]
  let bytes = FixedArray::make(4, b'\x00')
  bytes[0] = b'\xff'
  bytes[1] = b'\x0a'
  for i, bit in bits {
    if bit == 1 {
      let p = 2 + i / 8
      bytes[p] = (bytes[p].to_int() | (1 << (i % 8))).to_byte()
    }
  }
  assert_eq(@jxl.jxl_size(Bytes::from_array(bytes[:])), Some((64, 64)))
}

///|
test "jxl_size/orientation swaps sides" {
  // div8=1 height=8 (00000), ratio=7 (2:1) -> width 16; all_default=0,
  // extra_fields=1, orientation-1=5 (101) -> orientation 6
  let bits = [1, 0, 0, 0, 0, 0, 1, 1, 1, 0, 1, 1, 0, 1]
  let bytes = FixedArray::make(5, b'\x00')
  bytes[0] = b'\xff'
  bytes[1] = b'\x0a'
  for i, bit in bits {
    if bit == 1 {
      let p = 2 + i / 8
      bytes[p] = (bytes[p].to_int() | (1 << (i % 8))).to_byte()
    }
  }
  let cs = Bytes::from_array(bytes[:])
  assert_eq(@jxl.jxl_size(cs), Some((8, 16)))
  // same codestream split into two jxlp boxes in a container
  let c = Buffer()
  c.write_bytes(b"\x00\x00\x00\x0cJXL \x0d\x0a\x87\x0a")
  c.write_bytes(b"\x00\x00\x00\x14ftypjxl \x00\x00\x00\x00jxl ")
  c.write_bytes(b"\x00\x00\x00\x0ejxlp\x00\x00\x00\x00")
  c.write_bytesview(cs[0:2])
  c.write_bytes(b"\x00\x00\x00\x0fjxlp\x80\x00\x00\x01")
  c.write_bytesview(cs[2:5])
  assert_eq(@jxl.jxl_size(c.to_bytes()), Some((8, 16)))
}
