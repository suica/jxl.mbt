// Parses the image header of every libjxl conformance test case and checks it against the
// reference: image size from the reference image (PNG/APNG IHDR, GIF screen descriptor or
// NPY shape) and bit depth, extra channel types and tone mapping from `test.json`.
//
// Conformance directory: `JXL_OXIDE_CONFORMANCE_TESTCASES`, default
// `../fixtures/cache/conformance` (relative to `tests/`).

///|
fn conformance_dir() -> String {
  match @env.get_env_var("JXL_OXIDE_CONFORMANCE_TESTCASES") {
    Some(v) if v != "" => v
    _ => "../fixtures/cache/conformance"
  }
}

///|
fn be32(b : Bytes, i : Int32) -> Int32 {
  (b[i].to_int() << 24) |
  (b[i + 1].to_int() << 16) |
  (b[i + 2].to_int() << 8) |
  b[i + 3].to_int()
}

///|
/// Extracts the codestream: the file itself if it is a bare codestream, otherwise the
/// `jxlc` box contents or the concatenated `jxlp` box contents (without their index).
fn extract_codestream(data : Bytes) -> Bytes {
  if data.length() >= 2 && data[0] == b'\xff' && data[1] == b'\x0a' {
    return data
  }
  let out = Array()
  let mut pos = 0
  while pos + 8 <= data.length() {
    let mut size = be32(data, pos).reinterpret_as_uint().to_int64()
    let ty = data[pos + 4:pos + 8].to_owned()
    let mut header = 8
    if size == 1L {
      size = (be32(data, pos + 8).to_int64() << 32) |
        be32(data, pos + 12).reinterpret_as_uint().to_int64()
      header = 16
    } else if size == 0L {
      size = (data.length() - pos).to_int64()
    }
    let end = pos + size.to_int()
    if ty == b"jxlc" {
      for i in (pos + header)..<end {
        out.push(data[i])
      }
    } else if ty == b"jxlp" {
      for i in (pos + header + 4)..<end {
        out.push(data[i])
      }
    }
    pos = end
  }
  Bytes::from_array(out)
}

///|
/// Reference (width, height) of the decoded image, if a reference with a readable size exists.
fn reference_size(dir : String) -> (Int32, Int32)? raise {
  for name in ["ref.png", "ref.apng"] {
    let path = dir + "/" + name
    if @fs.path_exists(path) {
      let b = @fs.read_file_to_bytes(path)
      // 8-byte signature, IHDR chunk: length, "IHDR", width, height
      assert_eq(b[12:16].to_owned(), b"IHDR")
      return Some((be32(b, 16), be32(b, 20)))
    }
  }
  let gif = dir + "/ref.gif"
  if @fs.path_exists(gif) {
    let b = @fs.read_file_to_bytes(gif)
    return Some(
      (
        b[6].to_int() | (b[7].to_int() << 8),
        b[8].to_int() | (b[9].to_int() << 8),
      ),
    )
  }
  let npy = dir + "/reference_image.npy"
  if @fs.path_exists(npy) {
    // shape is (frames, height, width, channels)
    let b = @fs.read_file_to_bytes(npy)
    let header_len = b[8].to_int() | (b[9].to_int() << 8)
    // parse the integers after "'shape': (" in the ASCII header
    let dims : Array[Int32] = []
    let mut i = 10
    let end = 10 + header_len
    while i + 9 < end && b[i:i + 9].to_owned() != b"'shape':" + b" (" {
      i += 1
    }
    i += 9
    let mut cur = -1
    while i < end && b[i] != b')' {
      let ch = b[i].to_int()
      if ch >= 48 && ch <= 57 {
        cur = (if cur < 0 { 0 } else { cur }) * 10 + (ch - 48)
      } else if cur >= 0 {
        dims.push(cur)
        cur = -1
      }
      i += 1
    }
    if cur >= 0 {
      dims.push(cur)
    }
    return Some((dims[2], dims[1]))
  }
  None
}

///|
fn json_str(j : Json) -> String {
  match j {
    String(s) => s
    _ => abort("expected string")
  }
}

///|
fn json_num(j : Json) -> Double {
  match j {
    Number(n, ..) => n
    _ => abort("expected number")
  }
}

///|
test "conformance image headers" {
  let root = conformance_dir()
  if !@fs.path_exists(root) {
    println("conformance testcases not found at \{root}; skipped")
    return
  }
  let names = @fs.read_dir(root).iter().collect()
  names.sort()
  let mut checked = 0
  for name in names {
    let dir = root + "/" + name
    let input = dir + "/input.jxl"
    if !@fs.path_exists(input) {
      continue
    }
    let codestream = extract_codestream(@fs.read_file_to_bytes(input))
    let header = @image.ImageHeader::parse(
      @bitstream.Bitstream::new(codestream),
    )
    let metadata = header.metadata
    let width = header.width_with_orientation()
    let height = header.height_with_orientation()
    match reference_size(dir) {
      Some((w, h)) => {
        assert_eq((name, width, height), (name, w, h))
        checked += 1
      }
      None => println("\{name}: no reference size")
    }
    let test_json = @json.parse(@fs.read_file_to_string(dir + "/test.json"))
    guard test_json is Object(obj) else { fail("bad test.json") }
    guard obj.get("bits_per_sample") is Some(Array(bps)) else {
      fail("no bits_per_sample")
    }
    guard obj.get("exp_bits_per_sample") is Some(Array(exp_bits)) else {
      fail("no exp_bits_per_sample")
    }
    guard obj.get("extra_channel_type") is Some(Array(ec_types)) else {
      fail("no extra_channel_type")
    }
    let depths = [metadata.bit_depth]
    for ec in metadata.ec_info {
      depths.push(ec.bit_depth)
    }
    assert_eq((name, depths.length()), (name, bps.length()))
    for i, depth in depths {
      let exp = match depth {
        IntegerSample(..) => 0
        FloatSample(exp_bits~, ..) => exp_bits
      }
      assert_eq(
        (name, i, depth.bits_per_sample(), exp),
        (name, i, json_num(bps[i]).to_int(), json_num(exp_bits[i]).to_int()),
      )
    }
    for i, ec in metadata.ec_info {
      let ty = match ec.ty {
        Alpha(..) => "Alpha"
        SpotColour(..) => "SpotColor"
        Black => "Black"
        Depth => "Depth"
        SelectionMask => "SelectionMask"
        Cfa(..) => "CFA"
        Thermal => "Thermal"
        NonOptional => "NonOptional"
        Optional => "Optional"
      }
      assert_eq((name, i, ty), (name, i, json_str(ec_types[i])))
    }
    let tm = metadata.tone_mapping
    assert_eq(
      (name, tm.intensity_target.to_double(), tm.min_nits.to_double()),
      (
        name,
        json_num(obj.get("intensity_target").unwrap()),
        json_num(obj.get("min_nits").unwrap()),
      ),
    )
  }
  println("checked image size of \{checked} conformance test cases")
  assert_true(checked > 0)
}
