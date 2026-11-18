// Port of jxl-oxide-tests/tests/decode/mod.rs (interim: until `src/zstd`
// lands, the fixture is read already decompressed, `{name}.buf` next to the
// `.zst` in the cache, written by scripts/fetch_fixtures.sh; decode.mbt.pending
// is the version that decompresses output.buf.zst itself).

///|
priv struct FixtureHeader {
  width : Int32
  height : Int32
  channels : Int32
}

///|
fn u32_le(b : Bytes, at : Int32) -> Int32 {
  b[at].to_int() |
  (b[at + 1].to_int() << 8) |
  (b[at + 2].to_int() << 16) |
  (b[at + 3].to_int() << 24)
}

///|
/// A `Read` over the decompressed fixture, with `read_exact`.
priv struct Expected {
  buf : Bytes
  mut pos : Int32
}

///|
fn Expected::read_exact(self : Expected, len : Int32) -> BytesView {
  if self.pos + len > self.buf.length() {
    abort(
      "called `Result::unwrap()` on an `Err` value: failed to fill whole buffer",
    )
  }
  let v = self.buf[self.pos:self.pos + len]
  self.pos += len
  v
}

///|
fn FixtureHeader::from_bytes(buf : BytesView) -> FixtureHeader {
  let b = buf.to_owned()
  { width: u32_le(b, 0), height: u32_le(b, 4), channels: u32_le(b, 8), }
}

///|
/// `(f * 65535.0 + 0.5) as u16`, a saturating cast.
fn to_u16(f : Float) -> Int32 {
  let v = f * 65535.0 + 0.5
  if v.is_nan() || v <= 0.0 {
    0
  } else if v >= 65535.0 {
    65535
  } else {
    v.to_int()
  }
}

///|
/// `1u16 << 14u32.saturating_sub(bits)`
fn modular_threshold(bits : Int32) -> Int32 {
  let shift = 14 - bits
  1 << (if shift < 0 { 0 } else { shift })
}

///|
fn decode(data : Bytes, expected : Expected) -> Unit raise Error {
  let fixture_header = FixtureHeader::from_bytes(expected.read_exact(12))
  let image = @jxl.JxlImage::builder().read(@jxl.Cursor::new(data))
  let image_header = image.image_header().metadata
  let bit_depth = image_header.bit_depth.bits_per_sample()
  for idx in 0..<image.num_loaded_keyframes() {
    let frame = image.render_frame(idx)
    let marker = expected.read_exact(1)[0]
    if marker != 0 {
      abort("explicit panic")
    }
    let num_color_channels = frame.color_channels().length()
    let image_planar = frame.image_planar()
    assert_eq(fixture_header.channels, image_planar.length())

    // Peak error threshold of Level 10 tests, from 18181-3
    let frame_header = image.frame_header(idx).unwrap()
    let color_peak_error_threshold = match frame_header.encoding {
      VarDct => (0.004 * 65535.0).to_int()
      Modular => modular_threshold(bit_depth)
    }
    let thresholds = Array::make(num_color_channels, color_peak_error_threshold)
    for ec in image_header.ec_info {
      thresholds.push(modular_threshold(ec.bit_depth.bits_per_sample()))
    }
    for c, grid in image_planar {
      if c >= thresholds.length() {
        break
      }
      let peak_error_threshold = thresholds[c]
      assert_eq(fixture_header.width, grid.width())
      assert_eq(fixture_header.height, grid.height())
      let buf = grid.buf()
      let expected_buf = expected.read_exact(grid.width() * grid.height() * 2)
      for i in 0..<buf.length() {
        let expected = expected_buf[2 * i].to_int() |
          (expected_buf[2 * i + 1].to_int() << 8)
        let actual = to_u16(buf[i])
        let diff = (actual - expected).abs()
        assert_true(
          diff < peak_error_threshold,
          msg="assertion failed: diff < peak_error_threshold (\{diff} >= \{peak_error_threshold})",
        )
      }
    }
  }
}

///|
/// The body of a `test!` test (interim, see above).
pub fn run(name : String) -> Unit raise Error {
  let path = @harness.decode_testcases_dir() + "/" + name
  let input = @harness.read_file(path + "/input.jxl")
  let expected = @harness.download_url_with_cache(
    "(decompressed by scripts/fetch_fixtures.sh)",
    name + ".buf",
  )
  decode(input, { buf: expected, pos: 0, })
}
