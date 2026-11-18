// Port of jxl-oxide-tests/tests/crop/mod.rs: a cropped render must equal the
// same region of the full render (within 1e-6).
//
// Random regions as upstream (`rand::make_rng()`, seeded from the OS): the
// seed comes from `@env.rand` (the OS RNG) and is printed, so a failing run
// can be repeated with `JXL_CROP_SEED=<seed>`. The generator is xorshift64*
// instead of rand's SmallRng; widths, heights and offsets are uniform in the
// same inclusive ranges.

///|
priv struct Rng {
  mut state : UInt64
}

///|
fn Rng::new(name : String) -> Rng {
  let seed = match @env.get_env_var("JXL_CROP_SEED") {
    Some(s) =>
      @string.parse_uint64(s) catch {
        _ => abort("JXL_CROP_SEED must be an unsigned integer")
      }
    None =>
      match @env.rand(8) {
        Some(b) => {
          let mut x = 0UL
          for byte in b {
            x = (x << 8) | byte.to_uint64()
          }
          x
        }
        None => @env.now()
      }
  }
  println("\{name}: crop RNG seed \{seed} (JXL_CROP_SEED=\{seed} repeats it)")
  { state: if seed == 0UL { 1UL } else { seed } }
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
fn Rng::range_inclusive(self : Rng, lo : Int32, hi : Int32) -> Int32 {
  let n = (hi - lo + 1).to_uint64()
  lo + (self.next() % n).to_int()
}

///|
/// `run_test`.
pub fn run_test(buf : Bytes, name : String) -> Unit raise Error {
  let rng = Rng::new(name)
  let image = @jxl.JxlImage::builder().read(@jxl.Cursor::new(buf))
  let width = image.width()
  let height = image.height()
  let max_w = if width / 2 > 128 { width / 2 } else { 128 }
  let max_h = if height / 2 > 128 { height / 2 } else { 128 }
  let tester_image = @jxl.JxlImage::builder().read(@jxl.Cursor::new(buf))
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
pub fn testcase_with_crop(
  name : String,
  testimage : String,
  regions : Array[@jxl.CropInfo],
) -> Unit raise Error {
  let path = @harness.conformance_path(testimage)
  let buf = @harness.read_file(path)
  let image = @jxl.JxlImage::builder().read(@jxl.Cursor::new(buf))
  let tester_image = @jxl.JxlImage::builder().read(@jxl.Cursor::new(buf))
  for region in regions {
    tester_image.set_image_region(region) |> ignore
    test_crop_region(image, tester_image, region, name)
  }
}

///|
fn crop_debug(crop : @jxl.CropInfo) -> String {
  "CropInfo { width: \{crop.width}, height: \{crop.height}, left: \{crop.left}, top: \{crop.top} }"
}

///|
fn test_crop_region(
  image : @jxl.JxlImage,
  tester_image : @jxl.JxlImage,
  crop : @jxl.CropInfo,
  name : String,
) -> Unit raise Error {
  println("Testing crop region \{crop_debug(crop)}")
  let { width: crop_width, left: crop_left, top: crop_top, .. } = crop
  let width = image.width()
  let num_frames = image.num_loaded_keyframes()
  for idx in 0..<num_frames {
    println("Testing frame #\{idx}")
    let full_render = image.render_frame(idx)
    let cropped_render = tester_image.render_frame_cropped(idx)
    let full = full_render.image_planar()
    let cropped = cropped_render.image_planar()
    let nch = @cmp.minimum(full.length(), cropped.length())
    for c in 0..<nch {
      let expected = full[c].buf()
      let actual = cropped[c].buf()
      // `expected.chunks_exact(width).skip(crop_top).zip(actual.chunks_exact(crop_width))`
      let rows = @cmp.minimum(
        expected.length() / width - crop_top,
        actual.length() / crop_width,
      )
      for y in 0..<rows {
        let erow = (crop_top + y) * width + crop_left
        let arow = y * crop_width
        for x in 0..<crop_width {
          let expected = expected[erow + x]
          let actual = actual[arow + x]
          if (expected - actual).abs() > 1.0e-6 {
            println(
              "Test failed at c=\{c}, x=\{x}, y=\{y} (expected=\{expected}, actual=\{actual})",
            )
            let path = @harness.manifest_dir() + "/tests/.artifact"
            @harness.create_dir_all(path)
            let full = path + "/\{name}-full.npy"
            write_npy(full_render, full)
            println("Full frame data written at \{full}")
            let cropped = path + "/\{name}-cropped.npy"
            write_npy(cropped_render, cropped)
            println("Cropped frame data written at \{cropped}")
            fail(
              "Test failed at c=\{c}, x=\{x}, y=\{y} (expected=\{expected}, actual=\{actual})",
            )
          }
        }
      }
    }
    println("Frame #\{idx} OK")
  }
  println("Crop region \{crop_debug(crop)} OK")
  println("")
}

///|
fn write_npy(render : @jxl.Render, path : String) -> Unit raise Error {
  let out = Buffer()
  out.write_bytes(b"\x93NUMPY\x01\x00")
  let image = render.image_all_channels()
  let num_channels = image.channels()
  let width = image.width()
  let height = image.height()
  let header_string = "{'descr': '<f4', 'fortran_order': False, 'shape': (1, \{height}, \{width}, \{num_channels}), }\n"
  println("width=\{width}, height=\{height}, num_channels=\{num_channels}")
  let header_len = header_string.length()
  out.write_byte(header_len.to_byte())
  out.write_byte((header_len >> 8).to_byte())
  for i in 0..<header_len {
    out.write_byte(header_string.code_unit_at(i).to_int().to_byte())
  }
  for f in image.buf() {
    let b = f.reinterpret_as_uint()
    out.write_byte(b.to_byte())
    out.write_byte((b >> 8).to_byte())
    out.write_byte((b >> 16).to_byte())
    out.write_byte((b >> 24).to_byte())
  }
  @harness.write_file(path, out.to_bytes())
}

///|
/// The body of a `testcase!` test.
pub fn testcase(name : String) -> Unit raise Error {
  let path = @harness.conformance_path(name)
  let buf = @harness.read_file(path)
  run_test(buf, name)
}
