// Port of jxl-oxide-tests/tests/crop/mod.rs: a cropped render must equal the
// same region of the full render (within 1e-6).
//
// Upstream draws its random regions from an OS-seeded RNG; here they come
// from a xorshift64* generator seeded by the test name, so runs repeat
// (set JXL_CROP_SEED to draw other regions).

///|
priv struct Rng {
  mut state : UInt64
}

///|
fn Rng::new(name : String) -> Rng {
  // FNV-1a of the name (and of JXL_CROP_SEED when set)
  let seed = match @env.get_env_var("JXL_CROP_SEED") {
    Some(s) => name + "/" + s
    None => name
  }
  let mut h = 0xcbf29ce484222325UL
  for i in 0..<seed.length() {
    h = (h ^ seed.code_unit_at(i).to_int().to_uint64()) * 0x100000001b3UL
  }
  { state: if h == 0UL { 1UL } else { h } }
}

///|
fn Rng::next(self : Rng) -> UInt64 {
  let mut x = self.state
  x = x ^ (x >> 12)
  x = x ^ (x << 25)
  x = x ^ (x >> 27)
  self.state = x
  x * 0x2545F4914F6CDD1DUL
}

///|
/// Uniform in `lo..=hi`.
fn Rng::range_inclusive(self : Rng, lo : Int, hi : Int) -> Int {
  let n = (hi - lo + 1).to_uint64()
  lo + (self.next() % n).to_int()
}

///|
pub fn run_random_crops(name : String) -> Unit raise Error {
  guard @harness.read_fixture(@harness.conformance_path(name)) is Some(buf) else {
    return
  }
  let rng = Rng::new(name)
  let image = @jxl.JxlImage::builder().read(buf)
  let width = image.width()
  let height = image.height()
  let max_w = if width / 2 > 128 { width / 2 } else { 128 }
  let max_h = if height / 2 > 128 { height / 2 } else { 128 }
  let tester_image = @jxl.JxlImage::builder().read(buf)
  for _ in 0..<4 {
    let crop_width = rng.range_inclusive(128, max_w)
    let crop_height = rng.range_inclusive(128, max_h)
    let crop_left = rng.range_inclusive(0, width - crop_width)
    let crop_top = rng.range_inclusive(0, height - crop_height)
    let crop : @jxl.CropInfo = {
      left: crop_left,
      top: crop_top,
      width: crop_width,
      height: crop_height,
    }
    tester_image.set_image_region(crop) |> ignore
    test_crop_region(image, tester_image, crop, name)
  }
}

///|
pub fn run_crops(name : String, regions : Array[@jxl.CropInfo]) -> Unit raise Error {
  guard @harness.read_fixture(@harness.conformance_path(name)) is Some(buf) else {
    return
  }
  let image = @jxl.JxlImage::builder().read(buf)
  let tester_image = @jxl.JxlImage::builder().read(buf)
  for region in regions {
    tester_image.set_image_region(region) |> ignore
    test_crop_region(image, tester_image, region, name)
  }
}

///|
fn test_crop_region(
  image : @jxl.JxlImage,
  tester_image : @jxl.JxlImage,
  crop : @jxl.CropInfo,
  name : String,
) -> Unit raise Error {
  let debug = @harness.debug_enabled()
  if debug {
    println("Testing crop region \{crop}")
  }
  let { width: crop_width, left: crop_left, top: crop_top, .. } = crop
  let width = image.width()
  let num_frames = image.num_loaded_keyframes()
  for idx in 0..<num_frames {
    let full_render = image.render_frame(idx)
    let cropped_render = tester_image.render_frame_cropped(idx)
    let full = full_render.image_planar()
    let cropped = cropped_render.image_planar()
    let nch = if full.length() < cropped.length() {
      full.length()
    } else {
      cropped.length()
    }
    for c in 0..<nch {
      let expected = full[c].buf()
      let actual = cropped[c].buf()
      // rows of the full image from crop_top, zipped with the cropped rows
      let rows_full = expected.length() / width - crop_top
      let rows_crop = actual.length() / crop_width
      let rows = if rows_full < rows_crop { rows_full } else { rows_crop }
      for y in 0..<rows {
        let erow = (crop_top + y) * width + crop_left
        let arow = y * crop_width
        for x in 0..<crop_width {
          let e = expected[erow + x]
          let a = actual[arow + x]
          if (e - a).abs() > 1.0e-6 || (e - a).is_nan() {
            let artifact = write_artifacts(name, full_render, cropped_render)
            fail(
              "\{name}: \{crop}: frame #\{idx}: test failed at c=\{c}, x=\{x}, y=\{y} (expected=\{e}, actual=\{a})\{artifact}",
            )
          }
        }
      }
    }
  }
}

///|
/// Writes both renders as .npy under `_build/crop-artifacts/` (upstream
/// `tests/.artifact/`) for inspection; returns a note for the failure message.
fn write_artifacts(
  name : String,
  full_render : @jxl.Render,
  cropped_render : @jxl.Render,
) -> String {
  let dir = "_build/crop-artifacts"
  let write = fn(render : @jxl.Render, path : String) raise {
    let fb = render.image_all_channels()
    @fs.write_bytes_to_file(
      path,
      @harness.write_npy_bytes(
        [1, fb.height(), fb.width(), fb.channels()],
        fb.buf(),
      ),
    )
  }
  try {
    if !@fs.path_exists(dir) {
      @fs.create_dir(dir)
    }
    write(full_render, dir + "/" + name + "-full.npy")
    write(cropped_render, dir + "/" + name + "-cropped.npy")
    " (renders written to tests/\{dir}/\{name}-{full,cropped}.npy)"
  } catch {
    _ => ""
  }
}
