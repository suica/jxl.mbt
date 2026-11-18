// JPEG bitstream reconstruction of the jbrd test images (jxl-oxide's jbrd test):
// the reconstructed JPEG must equal the original byte for byte (hence also by
// SHA-256). Exercises container parsing, ICC decoding, frame decoding and jbr.
//
// Data: `@harness.conformance_testcases_dir()` and
// `@harness.decode_testcases_dir()` (jxl-oxide test data with `ref.jpg`).

///|
priv struct Parsed {
  codestream : Bytes
  jbrd : Bytes
  exif : Bytes
  xml : Bytes
}

///|
fn parse_container(data : Bytes) -> Parsed raise {
  let parser = @container.ContainerParser::new()
  let events = parser.feed_bytes(data)
  let cs = Buffer()
  let jbrd = Buffer()
  let exif = Buffer()
  let xml = Buffer()
  while events.next() is Some(ev) {
    match ev {
      Codestream(b) => cs.write_bytesview(b)
      AuxBoxData(ty, b) =>
        if ty == @container.ContainerBoxType::jpeg_reconstruction() {
          jbrd.write_bytesview(b)
        } else if ty == @container.ContainerBoxType::exif() {
          exif.write_bytesview(b)
        } else if ty == @container.ContainerBoxType::xml() {
          xml.write_bytesview(b)
        }
      _ => ()
    }
  }
  let exif = exif.to_bytes()
  // Exif box: 4-byte TIFF header offset, then the payload.
  let exif = if exif.length() >= 4 { exif[4:].to_owned() } else { exif }
  {
    codestream: cs.to_bytes(),
    jbrd: jbrd.to_bytes(),
    exif,
    xml: xml.to_bytes(),
  }
}

///|
fn reconstruct(path : String) -> Bytes raise {
  let p = parse_container(@fs.read_file_to_bytes(path))
  let cs = p.codestream
  let bs = @bitstream.Bitstream::new(cs)
  let image_header = @image.ImageHeader::parse(bs)
  let icc = if image_header.metadata.colour_encoding.want_icc() {
    @color.decode_icc(@color.read_icc(bs))
  } else {
    b""
  }
  bs.zero_pad_to_byte()
  let mut pos = bs.num_read_bits() / 8
  if image_header.metadata.preview is Some(_) {
    let bs = @bitstream.Bitstream::new_range(cs, pos, cs.length() - pos)
    let frame = @frame.Frame::parse(bs, image_header)
    pos += bs.num_read_bits() / 8 + frame.toc().total_byte_size()
  }
  let bs = @bitstream.Bitstream::new_range(cs, pos, cs.length() - pos)
  let frame = @frame.Frame::parse(bs, image_header)
  let data_start = pos + bs.num_read_bits() / 8
  let end = data_start + frame.toc().total_byte_size()
  let _ = frame.feed_bytes(
    cs[data_start:if end < cs.length() { end } else { cs.length() }],
  )
  assert_true(frame.is_loading_done())
  let jbrd = @jbr.JpegBitstreamData::try_parse(p.jbrd).unwrap()
  jbrd.finalize()
  let out = Buffer()
  jbrd.reconstruct(frame, icc, p.exif, p.xml).write(out)
  out.to_bytes()
}

///|
fn check(input : String, expected : String) -> Unit raise {
  let got = reconstruct(input)
  let want = @fs.read_file_to_bytes(expected)
  assert_eq(got.length(), want.length())
  assert_true(got == want)
}

///|
test "jbrd conformance" {
  let dir = @harness.fixture_dir(
    @harness.conformance_testcases_dir(),
    "cafe/reconstructed.jpg",
  )
  for name in ["bench_oriented_brg", "cafe", "grayscale_jpeg"] {
    check(
      dir + "/" + name + "/input.jxl",
      dir + "/" + name + "/reconstructed.jpg",
    )
  }
}

///|
test "jbrd jxl-oxide test images" {
  let dir = @harness.fixture_dir(
    @harness.decode_testcases_dir(),
    "issue_425/ref.jpg",
  )
  for name in ["genshin_ycbcr_420", "issue_425", "starrail_jpegli_xyb"] {
    check(dir + "/" + name + "/input.jxl", dir + "/" + name + "/ref.jpg")
  }
}
