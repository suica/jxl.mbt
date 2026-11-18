// Port of jxl-oxide-tests/tests/conformance/mod.rs: `read_numpy`, `run_test`
// and the body of the `conformance_test!` macro.

///|
/// `read_numpy`: checks the magic, skips the header, reads little-endian
/// f32 samples `channels` at a time and splits them into `frames` chunks.
fn read_numpy(buf : Bytes, frames : Int, channels : Int) -> Array[Array[Float]] {
  guard buf.length() >= 10 else { abort("failed to fill whole buffer") }
  let magic = buf[0:6]
  let meta_len = buf[8].to_int() | (buf[9].to_int() << 8)
  assert_eq_magic(magic)
  let mut pos = 10 + meta_len
  let fb : Array[Float] = []
  let chunk = channels * 4
  while pos + chunk <= buf.length() {
    for c in 0..<channels {
      let o = pos + c * 4
      let x = buf[o].to_uint() |
        (buf[o + 1].to_uint() << 8) |
        (buf[o + 2].to_uint() << 16) |
        (buf[o + 3].to_uint() << 24)
      fb.push(Float::reinterpret_from_uint(x))
    }
    pos += chunk
  }
  let chunk_size = fb.length() / frames
  let out = []
  for f in 0..<frames {
    out.push(fb[f * chunk_size:(f + 1) * chunk_size].to_array())
  }
  out
}

///|
fn assert_eq_magic(magic : BytesView) -> Unit {
  guard magic == b"\x93NUMPY"[:] else {
    abort("assertion `left == right` failed: npy magic")
  }
}

///|
fn run_test(
  image : @jxl.JxlImage,
  target_icc : Bytes?,
  expected : Array[Array[Float]],
  expected_error_list : Array[(Float, Float)],
) -> Unit raise Error {
  let debug = @harness.debug_enabled()
  image.set_render_spot_color(false) |> ignore
  if target_icc is Some(target_icc) {
    image.request_icc(target_icc)
  }
  let num_keyframes = image.num_loaded_keyframes()
  for idx in 0..<num_keyframes {
    let render = image.render_frame(idx)
    let keyframe_idx = render.keyframe_index()
    let expected = expected[keyframe_idx]
    println("Testing keyframe #\{keyframe_idx}")
    let fb = render.image_all_channels()
    let interleaved_buffer = fb.buf()
    assert_eq(expected.length(), interleaved_buffer.length())
    let width = fb.width()
    let height = fb.height()
    let channels = fb.channels()
    let sum_se = FixedArray::make(channels, (0.0 : Float))
    let peak_error = FixedArray::make(channels, (0.0 : Float))
    for y in 0..<height {
      for x in 0..<width {
        for c in 0..<channels {
          let expected_peak_error = expected_error_list[c].0
          let reference = expected[c + (x + y * width) * channels]
          let output = interleaved_buffer[c + (x + y * width) * channels]
          let abs_error = (output - reference).abs()
          if debug && abs_error >= expected_peak_error {
            println(
              "abs_error is larger than max peak_error, at (x=\{x}, y=\{y}, c=\{c}), reference=\{reference}, actual=\{output}",
            )
          }
          // f32::max ignores NaN
          if abs_error > peak_error[c] || peak_error[c].is_nan() {
            peak_error[c] = abs_error
          }
          sum_se[c] = sum_se[c] + abs_error * abs_error
        }
      }
    }
    let rmse = FixedArray::makei(channels, fn(c) {
      (sum_se[c] / Float::from_int(width * height)).sqrt()
    })
    for c in 0..<channels {
      println("Channel \{c}:")
      println("  peak_error = \{peak_error[c]}")
      println("  rmse = \{rmse[c]}")
    }
    for c in 0..<channels {
      assert_true(
        peak_error[c] <= expected_error_list[c].0,
        msg="assertion failed: peak_error[\{c}] <= expected_error_list[\{c}].0 (\{peak_error[c]} > \{expected_error_list[c].0})",
      )
      assert_true(
        rmse[c] <= expected_error_list[c].1,
        msg="assertion failed: rmse[\{c}] <= expected_error_list[\{c}].1 (\{rmse[c]} > \{expected_error_list[c].1})",
      )
    }
  }
  assert_eq(expected.length(), num_keyframes)
  assert_true(image.is_loading_done())
}

///|
/// The body of a `conformance_test!` test.
fn conformance_test(
  cms : &@jxl.ColorManagementSystem,
  name : String,
  npy_hash~ : String,
  icc_hash~ : String,
  frames~ : Int,
  channels~ : Int,
  error_list : Array[(Float, Float)],
) -> Unit raise Error {
  let perform_ct = icc_hash != "skip"
  let buf = @harness.download_object_with_cache(npy_hash, "npy")
  let target_icc = if perform_ct {
    Some(@harness.download_object_with_cache(icc_hash, "icc"))
  } else {
    None
  }
  let expected = read_numpy(buf, frames, channels)
  let path = @harness.conformance_path(name)
  // `JxlImage::builder().open(path)`: the file read through a reader
  // (`open` is native-only)
  let image = @jxl.JxlImage::builder().read(
    @jxl.Cursor::new(@harness.read_file(path)),
  )
  image.set_cms(cms)
  run_test(image, target_icc, expected, error_list)
}
