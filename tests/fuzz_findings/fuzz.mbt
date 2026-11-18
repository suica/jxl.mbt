// Port of jxl-oxide-tests/tests/fuzz_findings/mod.rs: inputs found by fuzzing
// must decode or fail with an error, without crashing or hanging. The files
// are committed in `data/fuzz_findings/`.

///|
pub fn fuzz_decode(name : String) -> Unit raise Error {
  let data = @harness.read_file(
    @harness.data_dir() + "/fuzz_findings/" + name + ".fuzz",
  )
  let image = @jxl.JxlImage::builder()
    .alloc_tracker(@grid.AllocTracker::with_limit(128L * 1024L * 1024L)) // 128 MiB
    .read(data) catch {
    _ => return
  }
  image.image_header() |> ignore
  for keyframe_idx in 0..<image.num_loaded_keyframes() {
    (image.render_frame(keyframe_idx) |> ignore) catch {
      _ => ()
    }
  }
}
