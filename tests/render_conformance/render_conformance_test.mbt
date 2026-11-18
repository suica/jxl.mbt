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
fn be32(b : Bytes, i : Int) -> Int {
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
  let out = Array::new()
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
fn read_npy(path : String) -> (Int, Int, Int, Int, FixedArray[Float]) raise {
  let b = @fs.read_file_to_bytes(path)
  let header_len = b[8].to_int() | (b[9].to_int() << 8)
  let dims : Array[Int] = []
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
    out[k] = bits.reinterpret_as_float()
  }
  (dims[0], dims[1], dims[2], dims[3], out)
}

///|
/// Decodes `codestream` and returns the render context with all frames
/// loaded.
fn load_image(codestream : Bytes) -> @render.RenderContext raise {
  let bs = @bitstream.Bitstream::new(codestream)
  let image_header = @image.ImageHeader::parse(bs)
  let embedded_icc = if image_header.metadata.colour_encoding.want_icc() {
    @color.read_icc(bs)
  } else {
    b""
  }
  bs.zero_pad_to_byte()
  let ctx = @render.RenderContext::builder()
    .embedded_icc(embedded_icc)
    .build(image_header)
  if image_header.metadata.have_preview {
    // Skip the preview frame.
    let preview = @render.RenderContext::builder().build(image_header)
    ignore(preview)
    abort("preview frames are not supported by this test")
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
  ctx
}

///|
/// Compares rendered keyframe `idx` against the reference; returns
/// (peak error, rms error).
fn compare_frame(
  image : @render.ImageWithRegion,
  ref_ : FixedArray[Float],
  frame_idx : Int,
  height : Int,
  width : Int,
  channels : Int,
) -> (Double, Double) {
  let mut peak = 0.0
  let mut sum_sq = 0.0
  let regions = image.regions_and_shifts()
  let buffers = image.buffer()
  for c in 0..<channels {
    guard buffers[c] is F32(g) else { abort("channel \{c} is not float") }
    let (region, _) = regions[c]
    for y in 0..<height {
      for x in 0..<width {
        let gx = x - region.left
        let gy = y - region.top
        let v = if gx >= 0 && gy >= 0 && gx < g.width() && gy < g.height() {
          g.get(gx, gy).to_double()
        } else {
          0.0
        }
        let r = ref_[((frame_idx * height + y) * width + x) * channels + c].to_double()
        let d = (v - r).abs()
        if d > peak {
          peak = d
        }
        sum_sq += d * d
      }
    }
  }
  (peak, (sum_sq / (width * height * channels).to_double()).sqrt())
}

///|
fn run_case(name : String) -> Unit raise {
  let dir = conformance_dir() + "/" + name
  let npy = dir + "/reference_image.npy"
  if !@fs.path_exists(npy) {
    println("\{name}: reference not found; skipped")
    return
  }
  let data = @fs.read_file_to_bytes(dir + "/input.jxl")
  let ctx = load_image(extract_codestream(data))
  let (frames, height, width, channels, ref_) = read_npy(npy)
  assert_eq(ctx.loaded_keyframes(), frames)
  for k in 0..<frames {
    let image = ctx.render_keyframe(k)
    let (peak, rms) = compare_frame(image, ref_, k, height, width, channels)
    println("\{name} frame \{k}: peak \{peak} rms \{rms}")
    // Tolerances of test.json for these cases.
    assert_true(peak <= 0.000976562 + 1.0e-6, msg="\{name}: peak error \{peak}")
    assert_true(rms <= 0.000976562 + 1.0e-6, msg="\{name}: rms error \{rms}")
  }
}

///|
test "render modular conformance: delta_palette" {
  if !@fs.path_exists(conformance_dir()) {
    println("conformance testcases not found; skipped")
    return
  }
  run_case("delta_palette")
}

///|
test "render modular conformance: lz77_flower" {
  if !@fs.path_exists(conformance_dir()) {
    println("conformance testcases not found; skipped")
    return
  }
  run_case("lz77_flower")
}
