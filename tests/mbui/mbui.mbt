// Tests of the mbui adapter (`decode_jxl`, `jxl_size`, `is_jxl`) on the
// conformance images.

///|
/// Reads `input.jxl` and `reference_image.npy` of a conformance case.
pub fn load_case(name : String) -> (Bytes, @harness.Npy)? raise Error {
  let dir = @harness.conformance_case_dir(name)
  guard @harness.read_fixture(dir + "/input.jxl") is Some(input) else {
    return None
  }
  guard @harness.read_fixture(dir + "/reference_image.npy") is Some(npy) else {
    return None
  }
  Some((input, @harness.read_npy(npy)))
}

///|
/// `decode_jxl` gives the reference's size, and `jxl_size` the same.
pub fn check_size(name : String) -> Unit raise Error {
  guard load_case(name) is Some((input, npy)) else { return }
  let (h, w) = (npy.shape[1], npy.shape[2])
  assert_true(@jxl.is_jxl(input))
  assert_eq(@jxl.jxl_size(input), Some((w, h)))
}

///|
/// Compares `decode_jxl` with the first frame of the reference (an sRGB
/// render), allowing `max_diff` in 8-bit units.
pub fn check_pixels(name : String, max_diff : Int) -> Unit raise Error {
  guard load_case(name) is Some((input, npy)) else { return }
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
