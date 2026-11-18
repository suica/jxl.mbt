// `std::io::Read` as used by jxl-oxide: `JxlImageBuilder::read` and
// `integration::JxlDecoder` take any reader.

///|
/// A source of bytes (the subset of `std::io::Read` jxl-oxide uses).
pub(open) trait Read {
  /// Reads into `buf[start:end]`, returning how many bytes were read; 0 means
  /// the end of the stream (or an empty `buf[start:end]`).
  fn read(Self, buf : FixedArray[Byte], start : Int32, end : Int32) -> Int32 raise @bitstream.JxlError
}

///|
/// `std::io::Cursor<&[u8]>`: a reader over bytes in memory.
pub struct Cursor {
  priv data : Bytes
  priv mut pos : Int32
}

///|
pub fn Cursor::new(data : Bytes) -> Cursor {
  { data, pos: 0, }
}

///|
/// Current position in the data.
pub fn Cursor::position(self : Cursor) -> Int32 {
  self.pos
}

///|
pub impl Read for Cursor with fn read(self, buf, start, end) {
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

///|
/// `std::io::Write` as used by jxl-oxide (`JxlImage::reconstruct_jpeg`).
pub(open) trait Write {
  fn write_all(Self, BytesView) -> Unit raise @bitstream.JxlError
}

///|
/// `Vec<u8>` as a writer.
pub impl Write for Buffer with fn write_all(self, data) {
  self.write_bytesview(data)
}
