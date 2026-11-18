// Reader for jxl-oxide decode fixtures (`output.buf`, the decompressed
// `output.buf.zst`): a 12-byte header (width, height, channels as u32 LE),
// then per keyframe a zero marker byte followed by `channels` planes of
// width*height u16 LE samples. A 0xff marker byte ends the keyframe list.

///|
#derive(Debug, Eq)
pub(all) struct FixtureHeader {
  width : Int32
  height : Int32
  channels : Int32
}

///|
pub struct FixtureReader {
  buf : Bytes
  mut pos : Int32
}

///|
pub fn FixtureReader::new(buf : Bytes) -> FixtureReader {
  { buf, pos: 0, }
}

///|
pub fn FixtureReader::header(
  self : FixtureReader,
) -> FixtureHeader raise Failure {
  if self.pos + 12 > self.buf.length() {
    fail("fixture: truncated header")
  }
  let width = read_u32_le(self.buf, self.pos)
  let height = read_u32_le(self.buf, self.pos + 4)
  let channels = read_u32_le(self.buf, self.pos + 8)
  self.pos += 12
  { width, height, channels, }
}

///|
pub fn FixtureReader::marker(self : FixtureReader) -> Int32 raise Failure {
  if self.pos >= self.buf.length() {
    fail("fixture: missing frame marker")
  }
  let m = self.buf[self.pos].to_int()
  self.pos += 1
  m
}

///|
/// Reads one plane of `len` u16 samples.
pub fn FixtureReader::plane(
  self : FixtureReader,
  len : Int32,
) -> FixedArray[Int32] raise Failure {
  if self.pos + len * 2 > self.buf.length() {
    fail("fixture: truncated plane")
  }
  let out = FixedArray::make(len, 0)
  let buf = self.buf
  let base = self.pos
  for i in 0..<len {
    out[i] = buf[base + 2 * i].to_int() | (buf[base + 2 * i + 1].to_int() << 8)
  }
  self.pos += len * 2
  out
}

///|
pub fn FixtureReader::at_end(self : FixtureReader) -> Bool {
  self.pos >= self.buf.length()
}
