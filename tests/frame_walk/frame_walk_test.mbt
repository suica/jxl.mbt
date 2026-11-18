// Walks every frame of every libjxl conformance input: parses the image header,
// skips the embedded ICC profile, then parses each frame header and TOC, skipping
// the frame data by the TOC's total size. Checks that the last frame ends exactly at
// the end of the codestream and that the number of keyframes equals the number of
// frames listed in `test.json`.
//
// Conformance directory: `JXL_OXIDE_CONFORMANCE_TESTCASES` (the `testcases` directory),
// or `conformance/testcases` next to the repository checkout.

///|
fn testcases_dir() -> String? {
  let candidates = []
  if @env.get_env_var("JXL_OXIDE_CONFORMANCE_TESTCASES") is Some(d) && d != "" {
    candidates.push(d)
  }
  candidates.push("../fixtures/cache/conformance")
  candidates.push("../../conformance/testcases")
  candidates.push("../../../conformance/testcases")
  for d in candidates {
    if @fs.path_exists(d + "/cafe") {
      return Some(d)
    }
  }
  None
}

///|
fn extract_codestream(data : Bytes) -> Bytes raise {
  let parser = @container.ContainerParser::new()
  let events = parser.feed_bytes(data)
  let cs = Buffer()
  while events.next() is Some(ev) {
    if ev is Codestream(b) {
      cs.write_bytesview(b)
    }
  }
  cs.to_bytes()
}

///|
/// Context of the ICC stream decoder (jxl-color `get_icc_ctx`).
fn get_icc_ctx(idx : Int32, b1 : Int32, b2 : Int32) -> Int32 {
  if idx <= 128 {
    return 0
  }
  let p1 = if (b1 >= 'a' && b1 <= 'z') || (b1 >= 'A' && b1 <= 'Z') {
    0
  } else if (b1 >= '0' && b1 <= '9') || b1 == '.' || b1 == ',' {
    1
  } else if b1 <= 1 {
    2 + b1
  } else if b1 <= 15 {
    4
  } else if b1 >= 241 && b1 <= 254 {
    5
  } else if b1 == 255 {
    6
  } else {
    7
  }
  let p2 = if (b2 >= 'a' && b2 <= 'z') || (b2 >= 'A' && b2 <= 'Z') {
    0
  } else if (b2 >= '0' && b2 <= '9') || b2 == '.' || b2 == ',' {
    1
  } else if b2 <= 15 {
    2
  } else if b2 >= 241 {
    3
  } else {
    4
  }
  1 + p1 + 8 * p2
}

///|
/// Skips the encoded ICC stream (as `jxl_color::icc::read_icc` reads it).
fn skip_icc(bs : @bitstream.Bitstream) -> Int32 raise {
  let enc_size = bs.read_u64()
  assert_true(enc_size <= 1UL << 28)
  let enc_size = enc_size.to_int()
  let decoder = @coding.Decoder::parse(bs, 41)
  decoder.begin(bs)
  let mut b1 = 0
  let mut b2 = 0
  for idx in 0..<enc_size {
    let sym = decoder.read_varint(bs, get_icc_ctx(idx, b1, b2))
    assert_true(sym < 256)
    b2 = b1
    b1 = sym.reinterpret_as_int()
  }
  decoder.finalize()
  enc_size
}

///|
priv struct FrameInfo {
  header : @frame.FrameHeader
  toc : @frame.Toc
}

///|
/// Parses all frames; returns (preview frame?, frames, bytes left after the last frame).
fn walk(
  cs : Bytes,
) -> (@image.ImageHeader, FrameInfo?, Array[FrameInfo], Int32) raise {
  let bs = @bitstream.Bitstream::new(cs)
  let image_header = @image.ImageHeader::parse(bs)
  if image_header.metadata.colour_encoding.want_icc() {
    skip_icc(bs) |> ignore
  }
  bs.zero_pad_to_byte()
  let mut pos = bs.num_read_bits() / 8
  let mut preview = None
  if image_header.metadata.preview is Some(_) {
    let bs = @bitstream.Bitstream::new_range(cs, pos, cs.length() - pos)
    let frame = @frame.Frame::parse(bs, image_header)
    preview = Some({ header: frame.header(), toc: frame.toc(), })
    pos += bs.num_read_bits() / 8 + frame.toc().total_byte_size()
  }
  let frames = []
  while true {
    let bs = @bitstream.Bitstream::new_range(cs, pos, cs.length() - pos)
    let frame = @frame.Frame::parse(bs, image_header)
    let header = frame.header()
    let toc = frame.toc()
    // Data starts right after the TOC.
    let data_start = bs.num_read_bits() / 8
    assert_eq(toc.bookmark(), data_start)
    // Feed the frame data and check every group is complete.
    let rest = frame.feed_bytes(
      cs[pos + data_start:@cmp.minimum(
        cs.length(),
        pos + data_start + toc.total_byte_size(),
      )],
    )
    assert_eq(rest.length(), 0)
    assert_true(frame.is_loading_done())
    frames.push({ header, toc, })
    pos += data_start + toc.total_byte_size()
    if header.is_last {
      break
    }
  }
  (image_header, preview, frames, cs.length() - pos)
}

///|
test "conformance frame walk" {
  guard testcases_dir() is Some(dir) else {
    println("conformance suite not found; skipping")
    return
  }
  let cases = @fs.read_dir(dir).to_owned()
  cases.sort()
  let lines = []
  let mut n = 0
  for name in cases {
    let path = dir + "/" + name + "/input.jxl"
    if !@fs.path_exists(path) {
      continue
    }
    let cs = extract_codestream(@fs.read_file_to_bytes(path))
    let (image_header, preview, frames, left) = walk(cs) catch {
      e => fail("\{name}: \{e}")
    }
    assert_eq(left, 0)
    let num_keyframes = frames.filter(f => f.header.is_keyframe()).length()
    let json = @json.parse(
      @fs.read_file_to_string(dir + "/" + name + "/test.json"),
    )
    guard json is { "frames": Array(expected), .. } else {
      fail("\{name}: test.json has no frames")
    }
    if num_keyframes != expected.length() {
      fail(
        "\{name}: \{num_keyframes} keyframes, test.json lists \{expected.length()}",
      )
    }
    let descr = frames.map(f => {
      let h = f.header
      let enc = if h.encoding == VarDct { "D" } else { "M" }
      let ty = match h.frame_type {
        RegularFrame => "R"
        LfFrame => "L\{h.lf_level}"
        ReferenceOnly => "Ref"
        SkipProgressive => "S"
      }
      let toc = if f.toc.is_single_entry() { "1" } else { "n" }
      "\{ty}\{enc}\{h.width}x\{h.height}p\{h.passes.num_passes}t\{toc}"
    })
    let pv = if preview is Some(_) { " +preview" } else { "" }
    let _ = image_header
    lines.push(
      "\{name}: \{frames.length()} frames, \{num_keyframes} keyframes\{pv} [\{descr.join(" ")}]",
    )
    n += 1
  }
  println(lines.join("\n"))
  assert_true(n >= 40)
}
