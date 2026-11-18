// Port of jxl-oxide-tests/tests/fuzz_findings/mod.rs: inputs found by fuzzing
// must decode or fail with an error, without crashing or hanging.

///|
fn fuzz_decode(data : Bytes) -> Unit {
  let image = try
    @jxl.JxlImage::builder()
    .alloc_tracker(@grid.AllocTracker::with_limit(128L * 1024L * 1024L)) // 128 MiB
    .read(@jxl.Cursor::new(data))
    |> Some
  catch {
    _ => None
  }
  if image is Some(image) {
    let _ = image.image_header()
    for keyframe_idx in 0..<image.num_loaded_keyframes() {
      (image.render_frame(keyframe_idx) |> ignore) catch {
        _ => ()
      }
    }
  }
}

///|
/// `test_by_include!`: the file `tests/fuzz_findings/<name>.fuzz`
/// (`include_bytes!` upstream).
fn test_by_include(name : String) -> Unit raise Error {
  let data = @harness.read_file(
    @harness.manifest_dir() + "/tests/fuzz_findings/" + name + ".fuzz",
  )
  fuzz_decode(data)
}
