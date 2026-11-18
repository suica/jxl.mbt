///|
/// Mirrors `brotli_decompressor::DecompressorWriter<Vec<u8>>` as used by
/// jxl-oxide: compressed bytes are written in pieces, the decompressed bytes
/// are read back with `get_ref`.
///
/// Input is buffered and decoded on demand: `flush` / `get_ref` decode the
/// input seen so far (a truncated stream yields the output decoded so far),
/// `close` additionally requires the stream to be complete.
pub struct DecompressorWriter {
  priv input : Array[Byte]
  priv mut decoded_len : Int32
  priv mut output : Bytes
}

///|
pub fn DecompressorWriter::new() -> DecompressorWriter {
  { input: [], decoded_len: -1, output: b"", }
}

///|
/// Feeds compressed bytes.
pub fn DecompressorWriter::write_all(
  self : DecompressorWriter,
  data : Bytes,
) -> Unit {
  for b in data {
    self.input.push(b)
  }
}

///|
fn DecompressorWriter::decode(
  self : DecompressorWriter,
  allow_partial : Bool,
) -> Unit raise @bitstream.JxlError {
  if self.decoded_len == self.input.length() && allow_partial {
    return
  }
  let data = Bytes::from_array(self.input)
  self.output = if allow_partial {
    decompress_partial(data)
  } else {
    decompress(data)
  }
  self.decoded_len = self.input.length()
}

///|
/// Decodes the input written so far; invalid data raises.
pub fn DecompressorWriter::flush(
  self : DecompressorWriter,
) -> Unit raise @bitstream.JxlError {
  self.decode(true)
}

///|
/// Finishes the stream; raises if it is invalid or incomplete.
pub fn DecompressorWriter::close(
  self : DecompressorWriter,
) -> Unit raise @bitstream.JxlError {
  self.decode(false)
}

///|
/// The decompressed bytes as of the last `flush`/`close`.
pub fn DecompressorWriter::get_ref(self : DecompressorWriter) -> Bytes {
  self.output
}
