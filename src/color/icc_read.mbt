// Port of `read_icc` from jxl-color/src/icc/decode.rs (needs the entropy decoder).

///|
/// Reads the encoded ICC profile stream from the given bitstream.
pub fn read_icc(bs : @bitstream.Bitstream) -> Bytes raise @bitstream.JxlError {
  let enc_size = bs.read_u64()
  if enc_size > 1UL << 28 {
    // Avoids allocating too much memory (>256MiB)
    // Maximum ICC output_size for Level 10
    raise @bitstream.ProfileConformance("Too large encoded ICC profile")
  }
  let decoder = @coding.Decoder::parse(bs, 41)
  let max_size_header_len = (if enc_size < 18UL { enc_size } else { 18UL }).to_int()
  let encoded_icc : Array[Byte] = Array::make(max_size_header_len, 0)
  let mut b1 : Byte = 0
  let mut b2 : Byte = 0
  decoder.begin(bs)
  for idx in 0..<max_size_header_len {
    let sym = decoder.read_varint(bs, get_icc_ctx(idx, b1, b2))
    if sym >= 256 {
      raise invalid_icc_stream("decoded value out of range")
    }
    let b = sym.to_byte()
    encoded_icc[idx] = b
    b2 = b1
    b1 = b
  }
  let tmp_cursor = Cursor::new(Bytes::from_array(encoded_icc)[:])
  let output_size = varint(tmp_cursor)
  let commands_size = varint(tmp_cursor)
  let stream_offset = tmp_cursor.pos.to_uint64()
  if commands_size > enc_size || stream_offset + commands_size > enc_size {
    raise invalid_icc_stream("invalid commands_size")
  }
  if output_size > 1UL << 28 {
    raise @bitstream.ProfileConformance("ICC output_size too large")
  }
  if output_size + 65536 < enc_size {
    raise invalid_icc_stream(
      "reported output_size is far smaller than enc_size",
    )
  }

  // Read remaining data
  let enc_size = enc_size.to_int()
  for idx in max_size_header_len..<enc_size {
    let sym = decoder.read_varint(bs, get_icc_ctx(idx, b1, b2))
    if sym >= 256 {
      raise invalid_icc_stream("decoded value out of range")
    }
    let b = sym.to_byte()
    encoded_icc.push(b)
    b2 = b1
    b1 = b
  }
  decoder.finalize()
  Bytes::from_array(encoded_icc)
}

///|
fn get_icc_ctx(idx : Int32, b1 : Byte, b2 : Byte) -> Int32 {
  if idx <= 128 {
    return 0
  }
  let p1 = match b1 {
    b'a'..<=b'z' | b'A'..<=b'Z' => 0
    b'0'..<=b'9' | b'.' | b',' => 1
    0..<=1 => 2 + b1.to_int()
    2..<=15 => 4
    241..<=254 => 5
    255 => 6
    _ => 7
  }
  let p2 = match b2 {
    b'a'..<=b'z' | b'A'..<=b'Z' => 0
    b'0'..<=b'9' | b'.' | b',' => 1
    0..<=15 => 2
    241..<=255 => 3
    _ => 4
  }
  1 + p1 + 8 * p2
}
