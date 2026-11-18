// Tolerances of conformance tests: from jxl-oxide's conformance/mod.rs where
// it lists the case, else from the suite's test.json.

///|
/// Per-channel (peak error, max RMSE).
#derive(Debug, Eq)
pub(all) struct Tolerance {
  peak : Float
  rmse : Float
}

///|
/// Tolerance of each frame listed in a conformance `test.json`
/// (`frames[i].peak_error`, `frames[i].rms_error`).
pub fn test_json_frame_tolerances(
  text : String,
) -> Array[Tolerance] raise Failure {
  let json = @json.parse(text) catch { e => fail("test.json: \{e}") }
  guard json is Object(obj) && obj.get("frames") is Some(Array(frames)) else {
    fail("test.json: no frames")
  }
  frames.map(fn(f) raise Failure {
    guard f is Object(fo) &&
      fo.get("peak_error") is Some(Number(peak, ..)) &&
      fo.get("rms_error") is Some(Number(rms, ..)) else {
      fail("test.json: bad frame entry")
    }
    { peak: Float::from_double(peak), rmse: Float::from_double(rms), }
  })
}
