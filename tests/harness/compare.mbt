// Pixel comparison of conformance tests (port of `run_test` in jxl-oxide-tests
// conformance/mod.rs). Arithmetic is f32 like upstream.

///|
pub(all) struct ChannelError {
  peak : Array[Float]
  rmse : Array[Float]
}

///|
/// Compares interleaved `actual` to interleaved `expected` (starting at
/// `expected_offset`), `channels` samples per pixel.
pub fn channel_errors(
  expected : FixedArray[Float],
  expected_offset : Int32,
  actual : FixedArray[Float],
  width : Int32,
  height : Int32,
  channels : Int32,
) -> ChannelError {
  let sum_se = FixedArray::make(channels, (0.0 : Float))
  let peak = FixedArray::make(channels, (0.0 : Float))
  let n = width * height
  for i in 0..<n {
    let base = i * channels
    for c in 0..<channels {
      let reference = expected[expected_offset + base + c]
      let output = actual[base + c]
      let abs_error = (output - reference).abs()
      // f32::max: NaN-ignoring
      if abs_error > peak[c] || peak[c].is_nan() {
        peak[c] = abs_error
      }
      sum_se[c] = sum_se[c] + abs_error * abs_error
    }
  }
  let peak_arr = []
  let rmse_arr = []
  for c in 0..<channels {
    peak_arr.push(peak[c])
    rmse_arr.push((sum_se[c] / Float::from_int(n)).sqrt())
  }
  { peak: peak_arr, rmse: rmse_arr, }
}

///|
/// Checks errors against per-channel tolerances; returns a description of each
/// violation (empty if all pass). NaN errors count as violations.
pub fn check_errors(
  err : ChannelError,
  tol : Array[Tolerance],
) -> Array[String] {
  let out = []
  for c in 0..<err.peak.length() {
    let t = tol[c]
    if !(err.peak[c] <= t.peak) {
      out.push("channel \{c}: peak_error \{err.peak[c]} > \{t.peak}")
    }
    if !(err.rmse[c] <= t.rmse) {
      out.push("channel \{c}: rmse \{err.rmse[c]} > \{t.rmse}")
    }
  }
  out
}

///|
pub fn format_errors(err : ChannelError) -> String {
  let sb = StringBuilder()
  for c in 0..<err.peak.length() {
    sb.write_string(
      "  channel \{c}: peak_error = \{err.peak[c]}, rmse = \{err.rmse[c]}\n",
    )
  }
  sb.to_string()
}
