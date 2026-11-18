// Not part of jxl-oxide-tests: every libjxl conformance testcase (level 10
// and the `_5` level-5 variants of main_level5.txt), judged as the suite's
// conformance.py judges it, by its own test.json (per-frame peak/RMS, all
// channels), through the public `JxlImage` API with the `Lcms2` CMS. One test
// per case. jxl-oxide's own table is tests/tests/conformance.

///|
/// Decodes `testcases/<name>/input.jxl` and compares every keyframe with
/// `reference_image.npy` (rendered to `reference.icc`, spot colours not
/// rendered). Skips (or fails with `JXL_TESTS_REQUIRE_FIXTURES`) when the
/// fixture is missing.
pub fn run_conformance(name : String) -> Unit raise Error {
  let dir = @harness.conformance_case_dir(name)
  let npy_buf = @harness.read_fixture(dir + "/reference_image.npy")
  let input = @harness.read_fixture(dir + "/input.jxl")
  let target_icc = @harness.read_fixture(dir + "/reference.icc")
  let expected = @harness.read_npy(npy_buf)
  guard expected.shape.length() == 4 else {
    fail("\{name}: unexpected npy shape \{shape_str(expected.shape)}")
  }
  let num_frames = expected.shape[0]
  let channels = expected.shape[3]
  let frame_len = expected.frame_len()
  let json_tol = @harness.test_json_frame_tolerances(
    @harness.read_text(dir + "/test.json"),
  )
  let tolerance_of = fn(keyframe_idx : Int32) -> Array[@harness.Tolerance] {
    let t = if keyframe_idx < json_tol.length() {
      json_tol[keyframe_idx]
    } else {
      json_tol[0]
    }
    Array::make(channels, t)
  }
  let debug = @harness.debug_enabled()
  let image = @jxl.JxlImage::builder().read(@jxl.Cursor::new(input))
  image.set_cms(@jxl.Lcms2::{ })
  image.set_render_spot_color(false) |> ignore
  image.request_icc(target_icc)
  let num_keyframes = image.num_loaded_keyframes()
  let failures = []
  for idx in 0..<num_keyframes {
    let render = image.render_frame(idx)
    let keyframe_idx = render.keyframe_index()
    if keyframe_idx >= num_frames {
      fail(
        "\{name}: keyframe #\{keyframe_idx} not in reference (\{num_frames} frames)",
      )
    }
    let fb = render.image_all_channels()
    let buf = fb.buf()
    if buf.length() != frame_len {
      fail(
        "\{name}: keyframe #\{keyframe_idx}: \{fb.width()}x\{fb.height()}x\{fb.channels()} rendered, reference \{shape_str(expected.shape)}",
      )
    }
    let err = @harness.channel_errors(
      expected.data,
      keyframe_idx * frame_len,
      buf,
      fb.width(),
      fb.height(),
      fb.channels(),
    )
    let violations = @harness.check_errors(err, tolerance_of(keyframe_idx))
    if debug || violations.length() > 0 {
      println(
        "\{name}: keyframe #\{keyframe_idx}\n\{@harness.format_errors(err)}",
      )
    }
    for v in violations {
      failures.push("keyframe #\{keyframe_idx}: \{v}")
    }
  }
  if failures.length() > 0 {
    fail("\{name}: \{failures.length()} tolerance violation(s): \{failures}")
  }
  if num_frames != num_keyframes {
    fail(
      "\{name}: \{num_keyframes} keyframes decoded, reference has \{num_frames}",
    )
  }
  if !image.is_loading_done() {
    fail("\{name}: image loading not done")
  }
}

///|
fn shape_str(shape : Array[Int32]) -> String {
  "(" + shape.map(fn(d) { d.to_string() }).join(", ") + ")"
}
