// `std::io::Read` as used by jxl-oxide: `JxlImageBuilder::read` and
// `integration::JxlDecoder` take any reader.

///|
/// A source of bytes (the subset of `std::io::Read` jxl-oxide uses).
pub(open) trait Read {
  /// Reads into `buf[start:end]`, returning how many bytes were read; 0 means
  /// the end of the stream (or an empty `buf[start:end]`).
  read(Self, buf : FixedArray[Byte], start : Int, end : Int) -> Int raise @bitstream.JxlError
}

///|
/// `std::io::Cursor<&[u8]>`: a reader over bytes in memory.
pub struct Cursor {
  priv data : Bytes
  priv mut pos : Int
}

///|
pub fn Cursor::new(data : Bytes) -> Cursor {
  { data, pos: 0 }
}

///|
/// Current position in the data.
pub fn Cursor::position(self : Cursor) -> Int {
  self.pos
}

///|
pub impl Read for Cursor with read(self, buf, start, end) {
  let n = @cmp.minimum(end - start, self.data.length() - self.pos)
  if n <= 0 {
    return 0
  }
  for i in 0..<n {
    buf[start + i] = self.data[self.pos + i]
  }
  self.pos += n
  n
}
