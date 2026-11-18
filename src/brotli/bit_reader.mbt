///|
/// LSB-first bit reader over the whole compressed input (port of the role of
/// `BrotliBitReader` in Google's C decoder `c/dec/bit_reader.h`).
///
/// Bytes are loaded whole into a 64-bit accumulator, so the number of
/// buffered bits modulo 8 is always the number of unread bits of the current
/// byte.
priv struct BitReader {
  data : Bytes
  mut pos : Int32
  mut buf : UInt64
  mut bits : Int32
}

///|
fn BitReader::new(data : Bytes) -> BitReader {
  { data, pos: 0, buf: 0, bits: 0, }
}

///|
fn BitReader::fill(self : BitReader) -> Unit {
  while self.bits <= 56 && self.pos < self.data.length() {
    self.buf = self.buf | (self.data[self.pos].to_uint64() << self.bits)
    self.bits += 8
    self.pos += 1
  }
}

///|
/// Peeks `n` (<= 32) bits; missing bits past the end of input read as zero.
fn BitReader::peek(self : BitReader, n : Int32) -> Int32 {
  if self.bits < n {
    self.fill()
  }
  (self.buf & ((1UL << n) - 1)).to_int()
}

///|
fn BitReader::drop_bits(
  self : BitReader,
  n : Int32,
) -> Unit raise @bitstream.JxlError {
  if n > self.bits {
    raise @bitstream.JxlError::Eof
  }
  self.buf = self.buf >> n
  self.bits -= n
}

///|
/// Reads `n` (0..=32) bits.
fn BitReader::read(
  self : BitReader,
  n : Int32,
) -> Int32 raise @bitstream.JxlError {
  if n == 0 {
    return 0
  }
  let v = self.peek(n)
  self.drop_bits(n)
  v
}

///|
/// `BrotliJumpToByteBoundary`: skips to the byte boundary; the skipped bits
/// must be zero.
fn BitReader::jump_to_byte_boundary(self : BitReader) -> Bool {
  let pad = self.bits & 7
  if pad == 0 {
    return true
  }
  let v = (self.buf & ((1UL << pad) - 1)).to_int()
  self.buf = self.buf >> pad
  self.bits -= pad
  v == 0
}

///|
/// Number of whole bytes not yet consumed (buffered bytes included).
fn BitReader::remaining_bytes(self : BitReader) -> Int32 {
  (self.bits >> 3) + (self.data.length() - self.pos)
}

///|
/// Reads one byte; must be at a byte boundary.
fn BitReader::read_byte(self : BitReader) -> Int32 raise @bitstream.JxlError {
  if self.bits >= 8 {
    let v = (self.buf & 0xff).to_int()
    self.buf = self.buf >> 8
    self.bits -= 8
    return v
  }
  if self.pos >= self.data.length() {
    raise @bitstream.JxlError::Eof
  }
  let v = self.data[self.pos].to_int()
  self.pos += 1
  v
}

///|
/// Skips `n` whole bytes; must be at a byte boundary.
fn BitReader::skip_bytes(
  self : BitReader,
  n : Int32,
) -> Unit raise @bitstream.JxlError {
  let mut n = n
  while n > 0 && self.bits >= 8 {
    self.buf = self.buf >> 8
    self.bits -= 8
    n -= 1
  }
  if n > self.data.length() - self.pos {
    self.pos = self.data.length()
    raise @bitstream.JxlError::Eof
  }
  self.pos += n
}
