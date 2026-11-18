// Tests of the mbui adapter (`decode_jxl`, `jxl_size`, `is_jxl`) on the
// conformance images.

///|
/// Reads `input.jxl` of a conformance case and its reference image (the
/// object named in `test.json`'s `sha256sums`, from the cache as upstream's
/// conformance test reads it; or the testcase's own file when test.json
/// names none).
pub fn load_case(name : String) -> (Bytes, @harness.Npy) raise Error {
  let dir = @harness.conformance_case_dir(name)
  let input = @harness.read_file(dir + "/input.jxl")
  let json = @json.parse(@harness.read_text(dir + "/test.json"))
  let npy = if json is Object(obj) &&
    obj.get("sha256sums") is Some(Object(sums)) &&
    sums.get("reference_image.npy") is Some(String(hash)) {
    @harness.download_object_with_cache(hash, "npy")
  } else {
    // committed in the testcase directory (mul_no_extra_channels)
    @harness.read_file(dir + "/reference_image.npy")
  }
  (input, @harness.read_npy(npy))
}

///|
/// `decode_jxl` gives the reference's size, and `jxl_size` the same.
pub fn check_size(name : String) -> Unit raise Error {
  let (input, npy) = load_case(name)
  let (h, w) = (npy.shape[1], npy.shape[2])
  assert_true(@jxl.is_jxl(input))
  assert_eq(@jxl.jxl_size(input), Some((w, h)))
}

///|
/// Compares `decode_jxl` with the first frame of the reference (an sRGB
/// render), allowing `max_diff` in 8-bit units.
pub fn check_pixels(name : String, max_diff : Int32) -> Unit raise Error {
  let (input, npy) = load_case(name)
  let (h, w, c) = (npy.shape[1], npy.shape[2], npy.shape[3])
  guard @jxl.decode_jxl(input) is Some((dw, dh, rgba)) else {
    fail("\{name}: decode_jxl returned None")
  }
  assert_eq((dw, dh), (w, h))
  assert_eq(rgba.length(), w * h * 4)
  let mut worst = 0
  for i in 0..<(w * h) {
    for k in 0..<4 {
      let expected = if c == 1 {
        if k < 3 {
          npy.data[i]
        } else {
          1.0
        }
      } else if k < c {
        npy.data[i * c + k]
      } else {
        1.0
      }
      let e = @jxl.sample_f32_to_u8(expected)
      let d = (rgba[i * 4 + k].to_int() - e).abs()
      if d > worst {
        worst = d
      }
    }
  }
  if worst > max_diff {
    fail("\{name}: max difference \{worst} > \{max_diff}")
  }
}

///|
/// A reader that returns at most `step` bytes per call.
priv struct Trickle {
  data : Bytes
  step : Int32
  mut pos : Int32
}

///|
impl @jxl.Read for Trickle with fn read(self, buf, start, end) {
  let n = @cmp.minimum(
    @cmp.minimum(end - start, self.step),
    self.data.length() - self.pos,
  )
  if n <= 0 {
    return 0
  }
  for i in 0..<n {
    buf[start + i] = self.data[self.pos + i]
  }
  self.pos += n
  n
}

///|
/// Decodes `name` through a reader returning `step` bytes a call and through
/// a `Cursor`; the renders must be the same.
pub fn check_trickle(name : String, step : Int32) -> Unit raise Error {
  let (input, _) = load_case(name)
  let a = @jxl.JxlImage::builder().read({ data: input, step, pos: 0, })
  let b = @jxl.JxlImage::builder().read(@jxl.Cursor::new(input))
  assert_eq(a.num_loaded_keyframes(), b.num_loaded_keyframes())
  assert_true(a.is_loading_done())
  let fa = a.render_frame(0).image_all_channels().buf()
  let fb = b.render_frame(0).image_all_channels().buf()
  assert_true(fa == fb, msg="\{name}: trickled render differs")
}
