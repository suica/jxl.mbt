// Port of jxl-oxide-tests/tests/decode/mod.rs: jxl-oxide's own decode test
// data, compared with 16-bit reference renders (`output.buf`, decompressed
// from `output.buf.zst` by scripts/fetch_fixtures.sh).

///|
/// `(f * 65535.0 + 0.5) as u16` (Rust saturating float-to-int cast).
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
pub fn run_decode(name : String) -> Unit raise Error {
  let dir = @harness.decode_testcases_dir() + "/" + name
  guard @harness.read_fixture(dir + "/input.jxl") is Some(data) else { return }
  guard @harness.read_fixture(dir + "/output.buf") is Some(expected) else {
    return
  }
  let expected = @harness.FixtureReader::new(expected)
  let fixture_header = expected.header()
  let image = @jxl.JxlImage::builder().read(data)
  let image_header = image.image_header().metadata
  let bit_depth = image_header.bit_depth.bits_per_sample()
  for idx in 0..<image.num_loaded_keyframes() {
    let frame = image.render_frame(idx)
    let marker = expected.marker()
    if marker != 0 {
      fail(
        "\{name}: keyframe #\{idx}: fixture has no more keyframes (marker \{marker})",
      )
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
      let expected_buf = expected.plane(grid.width() * grid.height())
      let mut bad = 0
      let mut max_diff = 0
      for i in 0..<buf.length() {
        let actual = to_u16(buf[i])
        let diff = (actual - expected_buf[i]).abs()
        if diff > max_diff {
          max_diff = diff
        }
        if !(diff < peak_error_threshold) {
          bad += 1
        }
      }
      if bad > 0 {
        fail(
          "\{name}: keyframe #\{idx} channel \{c}: \{bad} sample(s) off by >= \{peak_error_threshold} (max diff \{max_diff})",
        )
      }
    }
  }
  // the fixture's keyframe list ends with a 0xff marker
  let end = expected.marker()
  if end != 0xff {
    fail(
      "\{name}: fewer keyframes decoded (\{image.num_loaded_keyframes()}) than in the fixture",
    )
  }
}
