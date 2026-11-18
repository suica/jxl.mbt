// Runner of the conformance tests (port of `run_test` in jxl-oxide-tests
// conformance/mod.rs).

///|
pub(all) enum UpstreamTolerance {
  Uniform(@harness.Tolerance)
  PerChannel(Array[@harness.Tolerance])
}

///|
pub(all) enum ToleranceSource {
  /// jxl-oxide's table
  Upstream(UpstreamTolerance)
  /// `test.json` of the testcase
  TestJson
}

///|
/// Decodes `testcases/<name>/input.jxl` and compares every keyframe with
/// `reference_image.npy` (rendered to `reference.icc`, spot colours not
/// rendered). Skips (or fails with `JXL_TESTS_REQUIRE_FIXTURES`) when the
/// fixture is missing.
pub fn run_conformance(
  name : String,
  source : ToleranceSource,
) -> Unit raise Error {
  let dir = @harness.conformance_case_dir(name)
  guard @harness.read_fixture(dir + "/reference_image.npy") is Some(npy_buf) else {
    return
  }
  guard @harness.read_fixture(dir + "/input.jxl") is Some(input) else { return }
  guard @harness.read_fixture(dir + "/reference.icc") is Some(target_icc) else {
    return
  }
  let expected = @harness.read_npy(npy_buf)
  guard expected.shape.length() == 4 else {
    fail("\{name}: unexpected npy shape \{expected.shape}")
  }
  let num_frames = expected.shape[0]
  let channels = expected.shape[3]
  let frame_len = expected.frame_len()
  let json_tol = @harness.test_json_frame_tolerances(
    @harness.read_text(dir + "/test.json"),
  )
  let tolerance_of = fn(keyframe_idx : Int) -> Array[@harness.Tolerance] {
    match source {
      Upstream(Uniform(t)) => Array::make(channels, t)
      Upstream(PerChannel(ts)) => ts
      TestJson => {
        let t = if keyframe_idx < json_tol.length() {
          json_tol[keyframe_idx]
        } else {
          json_tol[0]
        }
        Array::make(channels, t)
      }
    }
  }
  let debug = @harness.debug_enabled()
  let image = @jxl.JxlImage::builder().read(input)
  image.set_render_spot_color(false) |> ignore
  image.request_icc(target_icc)
  let num_keyframes = image.num_loaded_keyframes()
  let failures = []
  for idx in 0..<num_keyframes {
    let render = image.render_frame(idx)
    let keyframe_idx = render.keyframe_index()
    if keyframe_idx >= num_frames {
      fail("\{name}: keyframe #\{keyframe_idx} not in reference (\{num_frames} frames)")
    }
    let fb = render.image_all_channels()
    let buf = fb.buf()
    if buf.length() != frame_len {
      fail(
        "\{name}: keyframe #\{keyframe_idx}: \{fb.width()}x\{fb.height()}x\{fb.channels()} rendered, reference \{expected.shape}",
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
    fail("\{name}: \{num_keyframes} keyframes decoded, reference has \{num_frames}")
  }
  if !image.is_loading_done() {
    fail("\{name}: image loading not done")
  }
}
