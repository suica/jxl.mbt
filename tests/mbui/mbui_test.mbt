///|
test "mbui/jxl_size/alpha_nonpremultiplied" {
  check_size("alpha_nonpremultiplied")
}

///|
test "mbui/jxl_size/alpha_premultiplied" {
  check_size("alpha_premultiplied")
}

///|
test "mbui/jxl_size/alpha_triangles" {
  check_size("alpha_triangles")
}

///|
test "mbui/jxl_size/animation_icos4d" {
  check_size("animation_icos4d")
}

///|
test "mbui/jxl_size/animation_newtons_cradle" {
  check_size("animation_newtons_cradle")
}

///|
test "mbui/jxl_size/animation_spline" {
  check_size("animation_spline")
}

///|
test "mbui/jxl_size/bench_oriented_brg" {
  check_size("bench_oriented_brg")
}

///|
test "mbui/jxl_size/bicycles" {
  check_size("bicycles")
}

///|
test "mbui/jxl_size/bike" {
  check_size("bike")
}

///|
test "mbui/jxl_size/blendmodes" {
  check_size("blendmodes")
}

///|
test "mbui/jxl_size/cafe" {
  check_size("cafe")
}

///|
test "mbui/jxl_size/cmyk_layers" {
  check_size("cmyk_layers")
}

///|
test "mbui/jxl_size/delta_palette" {
  check_size("delta_palette")
}

///|
test "mbui/jxl_size/grayscale" {
  check_size("grayscale")
}

///|
test "mbui/jxl_size/grayscale_jpeg" {
  check_size("grayscale_jpeg")
}

///|
test "mbui/jxl_size/grayscale_public_university" {
  check_size("grayscale_public_university")
}

///|
test "mbui/jxl_size/lossless_pfm" {
  check_size("lossless_pfm")
}

///|
test "mbui/jxl_size/lz77_flower" {
  check_size("lz77_flower")
}

///|
test "mbui/jxl_size/mul_no_extra_channels" {
  check_size("mul_no_extra_channels")
}

///|
test "mbui/jxl_size/noise" {
  check_size("noise")
}

///|
test "mbui/jxl_size/opsin_inverse" {
  check_size("opsin_inverse")
}

///|
test "mbui/jxl_size/patches" {
  check_size("patches")
}

///|
test "mbui/jxl_size/patches_lossless" {
  check_size("patches_lossless")
}

///|
test "mbui/jxl_size/progressive" {
  check_size("progressive")
}

///|
test "mbui/jxl_size/spot" {
  check_size("spot")
}

///|
test "mbui/jxl_size/sunset_logo" {
  check_size("sunset_logo")
}

///|
test "mbui/jxl_size/upsampling" {
  check_size("upsampling")
}

///|
test "mbui/decode_jxl/alpha_nonpremultiplied" {
  check_pixels("alpha_nonpremultiplied", 1)
}

///|
test "mbui/decode_jxl/sunset_logo" {
  check_pixels("sunset_logo", 1)
}

///|
test "mbui/decode_jxl/alpha_triangles" {
  check_pixels("alpha_triangles", 1)
}

///|
test "mbui/decode_jxl/blendmodes" {
  check_pixels("blendmodes", 2)
}

///|
test "mbui/decode_jxl/animation_icos4d" {
  check_pixels("animation_icos4d", 2)
}

///|
test "mbui/decode_jxl/noise" {
  check_pixels("noise", 2)
}

///|
test "mbui/decode_jxl/upsampling" {
  check_pixels("upsampling", 2)
}

///|
test "mbui/decode_jxl/bicycles" {
  check_pixels("bicycles", 1)
}

///|
test "mbui/decode_jxl/delta_palette" {
  check_pixels("delta_palette", 1)
}

///|
test "mbui/decode_jxl/animation_newtons_cradle" {
  check_pixels("animation_newtons_cradle", 1)
}

///|
test "mbui/decode_jxl/opsin_inverse" {
  check_pixels("opsin_inverse", 2)
}

///|
test "mbui/decode_jxl/gray spread to rgb" {
  guard load_case("grayscale") is Some((input, npy)) else { return }
  guard @jxl.decode_jxl(input) is Some((w, h, rgba)) else {
    fail("decode_jxl returned None")
  }
  assert_eq((w, h), (npy.shape[2], npy.shape[1]))
  for i in 0..<(w * h) {
    assert_eq(rgba[i * 4], rgba[i * 4 + 1])
    assert_eq(rgba[i * 4], rgba[i * 4 + 2])
    assert_eq(rgba[i * 4 + 3], b'\xff')
  }
}

///|
test "mbui/decode_jxl/orientation and cmyk" {
  for name in ["bench_oriented_brg", "cmyk_layers", "lossless_pfm", "spot"] {
    guard load_case(name) is Some((input, npy)) else { return }
    guard @jxl.decode_jxl(input) is Some((w, h, rgba)) else {
      fail("\{name}: decode_jxl returned None")
    }
    assert_eq((w, h), (npy.shape[2], npy.shape[1]))
    assert_eq(rgba.length(), w * h * 4)
  }
}

///|
test "mbui/decode_jxl/not jxl" {
  assert_eq(@jxl.decode_jxl(b"\x89PNG\r\n\x1a\n"), None)
  assert_eq(@jxl.decode_jxl(b""), None)
  assert_eq(@jxl.decode_jxl(b"\xff\x0a"), None)
  assert_eq(@jxl.decode_jxl(b"\xff\x0a\xff\xff\xff\xff\xff\xff"), None)
  assert_eq(@jxl.jxl_size(b"\xff\xd8\xff\xe0"), None)
  assert_false(@jxl.is_jxl(b"GIF89a"))
}

///|
test "mbui/decode_jxl/truncated" {
  guard load_case("sunset_logo") is Some((input, _)) else { return }
  for len in [12, 40, 200, input.length() / 2] {
    // must not crash; a cut image fails (or decodes what it can)
    @jxl.decode_jxl(input[0:len].to_owned()) |> ignore
  }
  // size is known from the first bytes
  assert_true(@jxl.jxl_size(input[0:64].to_owned()) is Some(_))
}

///|
test "mbui/decode_jxl/fuzz findings do not crash" {
  for name in ["large_output_size", "icc_parse_oob", "container_small_jxlp", "timeout_dim_shift"] {
    let data = @harness.read_file(@harness.data_dir() + "/fuzz_findings/" + name + ".fuzz")
    @jxl.decode_jxl(data) |> ignore
  }
}
