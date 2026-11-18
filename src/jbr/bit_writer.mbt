// Port of jxl-jbr/src/bit_writer.rs.

///|
/// MSB-first bit writer for JPEG entropy-coded segments, with 0xFF byte
/// stuffing.
pub struct BitWriter {
  priv output : Array[Byte]
  priv mut buf : UInt64
  priv mut valid_buf_bits : Int32
}

///|
pub fn BitWriter::new() -> BitWriter {
  { output: [], buf: 0, valid_buf_bits: 0, }
}

///|
fn BitWriter::flush_buf(self : BitWriter, next_buf : UInt64) -> Unit {
  let out = self.buf
  self.valid_buf_bits -= 64
  self.buf = next_buf
  if !has_ff_byte(out) {
    for idx in 0..<8 {
      let shift = (7 - idx) * 8
      self.output.push((out >> shift).to_byte())
    }
    return
  }
  for idx in 0..<8 {
    let shift = (7 - idx) * 8
    self.emit_byte((out >> shift).to_byte())
  }
}

///|
fn BitWriter::emit_byte(self : BitWriter, b : Byte) -> Unit {
  self.output.push(b)
  if b == b'\xff' {
    self.output.push(b'\x00')
  }
}

///|
/// Writes the `len` most significant bits of `bits`.
pub fn BitWriter::write_huffman(
  self : BitWriter,
  bits : UInt64,
  len : Int32,
) -> Unit {
  let shifted = bits >> self.valid_buf_bits
  self.buf = self.buf | shifted
  self.valid_buf_bits += len
  let extra = self.valid_buf_bits - 64
  if extra >= 0 {
    self.flush_buf(bits << (len - extra))
  }
}

///|
/// Writes the `len` least significant bits of `bits`.
pub fn BitWriter::write_raw(
  self : BitWriter,
  bits : UInt64,
  len : Int32,
) -> Unit {
  if len == 0 {
    return
  }
  self.write_huffman(bits << (64 - len), len)
}

///|
pub fn BitWriter::padding_bits(self : BitWriter) -> Int32 {
  (8 - self.valid_buf_bits % 8) % 8
}

///|
pub fn BitWriter::finalize(self : BitWriter) -> Array[Byte] {
  let out = self.buf
  let valid_bytes = (self.valid_buf_bits + 7) / 8
  if valid_bytes == 0 {
    return self.output
  }
  if !has_ff_byte(out) {
    for idx in 0..<valid_bytes {
      let shift = (7 - idx) * 8
      self.output.push((out >> shift).to_byte())
    }
    return self.output
  }
  for idx in 0..<valid_bytes {
    let shift = (7 - idx) * 8
    self.emit_byte((out >> shift).to_byte())
  }
  self.output
}

///|
fn has_ff_byte(val : UInt64) -> Bool {
  ((val.lnot() - 0x0101010101010101UL) & val & 0x8080808080808080UL) != 0
}
