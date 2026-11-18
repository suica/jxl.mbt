// End-to-end test of the render pipeline (RenderContext) on libjxl
// conformance test cases: decodes the codestream frame by frame with
// `RenderContext`, renders every keyframe to float buffers and compares them
// with `reference_image.npy` (f32, shape frames x H x W x C, values in the
// target colour space) using the per-frame peak/RMS tolerances of
// `test.json`.
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
fn extract_codestream(data : Bytes) -> Bytes {
  if data.length() >= 2 && data[0] == b'\xff' && data[1] == b'\x0a' {
    return data
  }
  let out : Array[Byte] = []
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
/// Reference image: (frames, height, width, channels, samples).
fn read_npy(
  path : String,
) -> (Int32, Int32, Int32, Int32, FixedArray[Float]) raise {
  let b = @fs.read_file_to_bytes(path)
  let header_len = b[8].to_int() | (b[9].to_int() << 8)
  let dims : Array[Int32] = []
  let mut i = 10
  let end = 10 + header_len
  while i + 10 < end && b[i:i + 10].to_owned() != b"'shape': (" {
    i += 1
  }
  i += 10
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
  let n = dims[0] * dims[1] * dims[2] * dims[3]
  let out = FixedArray::make(n, (0.0 : Float))
  for k in 0..<n {
    let o = end + k * 4
    let bits = b[o].to_uint() |
      (b[o + 1].to_uint() << 8) |
      (b[o + 2].to_uint() << 16) |
      (b[o + 3].to_uint() << 24)
    out[k] = Float::reinterpret_from_uint(bits)
  }
  (dims[0], dims[1], dims[2], dims[3], out)
}

///|
/// Decodes `codestream` and returns the render context with all frames
/// loaded.
fn load_image(
  codestream : Bytes,
  target_icc? : Bytes,
) -> (@render.RenderContext, @image.ImageHeader) raise {
  let bs = @bitstream.Bitstream::new(codestream)
  let image_header = @image.ImageHeader::parse(bs)
  let embedded_icc = if image_header.metadata.colour_encoding.want_icc() {
    @color.decode_icc(@color.read_icc(bs))
  } else {
    b""
  }
  bs.zero_pad_to_byte()
  let ctx = @render.RenderContext::builder()
    .embedded_icc(embedded_icc)
    .build(image_header)
  // As jxl-oxide's conformance tests: an ICC-capable CMS, and the
  // reference colour space requested as the output encoding.
  ctx.set_cms(@cms.MoonCms::{ })
  if target_icc is Some(icc) {
    ctx.request_color_encoding(@color.ColorEncodingWithProfile::with_icc(icc))
  }
  if image_header.metadata.have_preview {
    // Skip the preview frame.
    fail("preview frames are not supported by this test")
  }
  let mut pos = bs.num_read_bits() / 8
  while pos < codestream.length() {
    let fbs = @bitstream.Bitstream::new_range(
      codestream,
      pos,
      codestream.length() - pos,
    )
    let frame = ctx.load_frame_header(fbs)
    pos += fbs.num_read_bits() / 8
    let rest = codestream[pos:]
    let left = frame.feed_bytes(rest)
    pos += rest.length() - left.length()
    if !frame.is_loading_done() {
      abort("frame data is truncated")
    }
    let is_last = frame.header().is_last
    ctx.finalize_current_frame()
    if is_last {
      break
    }
  }
  (ctx, image_header)
}

///|
fn read_target_icc(dir : String) -> Bytes? raise {
  let path = dir + "/reference.icc"
  if @fs.path_exists(path) {
    Some(@fs.read_file_to_bytes(path))
  } else {
    None
  }
}

///|
/// Compares a rendered keyframe with frame `frame_idx` of the reference
/// (oriented, `height` x `width` x `channels`); returns per-channel
/// (peak error, rms error).
fn compare_frame(
  image : @render.ImageWithRegion,
  ref_ : FixedArray[Float],
  frame_idx : Int32,
  height : Int32,
  width : Int32,
  channels : Int32,
  header : @image.ImageHeader,
  frame_x0 : Int32,
  frame_y0 : Int32,
) -> Array[(Double, Double)] {
  let bit_depth = []
  for _ in 0..<image.color_channels() {
    bit_depth.push(header.metadata.bit_depth)
  }
  for ec in header.metadata.ec_info {
    bit_depth.push(ec.bit_depth)
  }
  let regions = image.regions_and_shifts()
  let buffers = image.buffer()
  let iw = header.size.width
  let ih = header.size.height
  let out = []
  for c in 0..<channels {
    // Integer (modular) buffers are scaled with the channel bit depth, as
    // the public API does.
    let g = match buffers[c] {
      F32(g) => g
      I32(g) => {
        let out = @grid.Grid::new(g.width(), g.height(), (0.0 : Float))
        for i in 0..<(g.width() * g.height()) {
          out.buf()[i] = bit_depth[c].parse_integer_sample(g.buf()[i])
        }
        out
      }
    }
    let (region, _) = regions[c]
    let mut peak = 0.0
    let mut sum_sq = 0.0
    for y in 0..<ih {
      for x in 0..<iw {
        // Regions are in frame coordinates.
        let gx = x - frame_x0 - region.left
        let gy = y - frame_y0 - region.top
        let v = if gx >= 0 && gy >= 0 && gx < g.width() && gy < g.height() {
          g.get(gx, gy).to_double()
        } else {
          0.0
        }
        // Image coordinates to oriented (reference) coordinates.
        let (_, _, ox, oy) = header.metadata.apply_orientation(
          iw, ih, x, y, false,
        )
        let r = ref_[((frame_idx * height + oy) * width + ox) * channels + c].to_double()
        let d = (v - r).abs()
        if d > peak {
          peak = d
        }
        sum_sq += d * d
      }
    }
    out.push((peak, (sum_sq / (iw * ih).to_double()).sqrt()))
  }
  out
}

///|
/// Peak/RMS tolerances of each frame from `test.json`.
fn tolerances(dir : String) -> Array[(Double, Double)] raise {
  let j = @json.parse(@fs.read_file_to_string(dir + "/test.json"))
  guard j is { "frames": Array(frames), .. } else { fail("bad test.json") }
  frames.map(f => {
    guard f is { "peak_error": Number(p, ..), "rms_error": Number(r, ..), .. } else {
      abort("bad frame tolerance")
    }
    (p, r)
  })
}

///|
/// Decodes and renders test case `name`, comparing every keyframe with the
/// reference. Returns whether all channels are within tolerance, and a
/// report line.
fn check_case(name : String) -> (Bool, String) raise {
  let dir = conformance_dir() + "/" + name
  let tol = tolerances(dir)
  let data = @fs.read_file_to_bytes(dir + "/input.jxl")
  let (ctx, header) = load_image(
    extract_codestream(data),
    target_icc?=read_target_icc(dir),
  )
  let (frames, height, width, channels, ref_) = read_npy(
    dir + "/reference_image.npy",
  )
  let mut all_ok = ctx.loaded_keyframes() == frames
  let mut msg = "frames \{ctx.loaded_keyframes()}/\{frames}"
  for k in 0..<frames {
    let image = ctx.render_keyframe(k)
    let fh = ctx.keyframe(k).unwrap().header()
    if image.channels() < channels {
      all_ok = false
      msg += " | f\{k}: \{image.channels()} channels < \{channels}"
      continue
    }
    let errors = compare_frame(
      image,
      ref_,
      k,
      height,
      width,
      channels,
      header,
      fh.x0,
      fh.y0,
    )
    // As libjxl's conformance script: peak and RMS error over all samples
    // of the frame, against the frame's tolerances in test.json.
    let mut peak = 0.0
    let mut sum_sq = 0.0
    for e in errors {
      peak = if e.0 > peak { e.0 } else { peak }
      sum_sq += e.1 * e.1
    }
    let rms = (sum_sq / errors.length().to_double()).sqrt()
    let (tp, tr) = tol[k]
    let ok = peak <= tp && rms <= tr
    if !ok {
      all_ok = false
    }
    if !ok || k == 0 || (frames > 1 && k == frames - 1) {
      msg += " | \{if ok { "ok" } else { "FAIL" }} f\{k} peak \{fmt(peak)} (max \{fmt(tp)}) rms \{fmt(rms)} (max \{fmt(tr)})"
    }
  }
  (all_ok, msg)
}

///|
fn fmt(x : Double) -> String {
  if x == 0.0 {
    return "0"
  }
  // 3 significant digits in scientific notation
  let mut e = 0
  let mut m = x
  while m >= 10.0 {
    m /= 10.0
    e += 1
  }
  while m < 1.0 {
    m *= 10.0
    e -= 1
  }
  let r = (m * 100.0).round() / 100.0
  "\{r}e\{e}"
}

///|
/// Renders every conformance test case with a reference image, printing one
/// line per case; fails if any case fails.
test "render conformance: all cases" {
  let root = conformance_dir()
  if !@fs.path_exists(root) {
    println("conformance testcases not found at \{root}; skipped")
    return
  }
  let names = @fs.read_dir(root).iter().collect()
  names.sort()
  let failed = []
  for name in names {
    if !@fs.path_exists(root + "/" + name + "/reference_image.npy") {
      continue
    }
    try check_case(name) catch {
      e => {
        failed.push(name)
        println("\{name}: ERROR \{@debug.to_string(e)}")
      }
    } noraise {
      (ok, msg) => {
        if !ok {
          failed.push(name)
        }
        println("\{if ok { "PASS" } else { "FAIL" }} \{name}: \{msg}")
      }
    }
  }
  println("failed (\{failed.length()}): \{@debug.to_string(failed)}")
  assert_true(failed.is_empty())
}
