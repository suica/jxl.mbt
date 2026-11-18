// One test per libjxl conformance testcase (all of testcases/).

///|
test "conformance_suite/alpha_nonpremultiplied" {
  run_conformance("alpha_nonpremultiplied")
}

///|
test "conformance_suite/alpha_premultiplied" {
  // Expected failure by test.json (as in tests/render_conformance): jxl-oxide
  // renders premultiplied samples where the reference is unpremultiplied; it
  // passes jxl-oxide's own tolerances (tests/tests/conformance).
  let failed = try {
    run_conformance("alpha_premultiplied")
    false
  } catch {
    _ => true
  }
  assert_true(failed, msg="alpha_premultiplied unexpectedly passes test.json")
}

///|
test "conformance_suite/alpha_triangles" {
  run_conformance("alpha_triangles")
}

///|
test "conformance_suite/animation_icos4d" {
  run_conformance("animation_icos4d")
}

///|
test "conformance_suite/animation_icos4d_5" {
  run_conformance("animation_icos4d_5")
}

///|
test "conformance_suite/animation_newtons_cradle" {
  run_conformance("animation_newtons_cradle")
}

///|
test "conformance_suite/animation_spline" {
  run_conformance("animation_spline")
}

///|
test "conformance_suite/animation_spline_5" {
  run_conformance("animation_spline_5")
}

///|
test "conformance_suite/bench_oriented_brg" {
  run_conformance("bench_oriented_brg")
}

///|
test "conformance_suite/bench_oriented_brg_5" {
  run_conformance("bench_oriented_brg_5")
}

///|
test "conformance_suite/bicycles" {
  run_conformance("bicycles")
}

///|
test "conformance_suite/bike" {
  run_conformance("bike")
}

///|
test "conformance_suite/bike_5" {
  run_conformance("bike_5")
}

///|
test "conformance_suite/blendmodes" {
  run_conformance("blendmodes")
}

///|
test "conformance_suite/blendmodes_5" {
  run_conformance("blendmodes_5")
}

///|
test "conformance_suite/cafe" {
  run_conformance("cafe")
}

///|
test "conformance_suite/cafe_5" {
  run_conformance("cafe_5")
}

///|
test "conformance_suite/cmyk_layers" {
  run_conformance("cmyk_layers")
}

///|
test "conformance_suite/delta_palette" {
  run_conformance("delta_palette")
}

///|
test "conformance_suite/grayscale" {
  run_conformance("grayscale")
}

///|
test "conformance_suite/grayscale_5" {
  run_conformance("grayscale_5")
}

///|
test "conformance_suite/grayscale_jpeg" {
  run_conformance("grayscale_jpeg")
}

///|
test "conformance_suite/grayscale_jpeg_5" {
  run_conformance("grayscale_jpeg_5")
}

///|
test "conformance_suite/grayscale_public_university" {
  run_conformance("grayscale_public_university")
}

///|
test "conformance_suite/lossless_pfm" {
  run_conformance("lossless_pfm")
}

///|
test "conformance_suite/lz77_flower" {
  run_conformance("lz77_flower")
}

///|
test "conformance_suite/mul_no_extra_channels" {
  run_conformance("mul_no_extra_channels")
}

///|
test "conformance_suite/noise" {
  run_conformance("noise")
}

///|
test "conformance_suite/noise_5" {
  run_conformance("noise_5")
}

///|
test "conformance_suite/opsin_inverse" {
  run_conformance("opsin_inverse")
}

///|
test "conformance_suite/opsin_inverse_5" {
  run_conformance("opsin_inverse_5")
}

///|
test "conformance_suite/patches" {
  run_conformance("patches")
}

///|
test "conformance_suite/patches_5" {
  run_conformance("patches_5")
}

///|
test "conformance_suite/patches_lossless" {
  run_conformance("patches_lossless")
}

///|
test "conformance_suite/progressive" {
  run_conformance("progressive")
}

///|
test "conformance_suite/progressive_5" {
  run_conformance("progressive_5")
}

///|
test "conformance_suite/spot" {
  run_conformance("spot")
}

///|
test "conformance_suite/sunset_logo" {
  run_conformance("sunset_logo")
}

///|
test "conformance_suite/upsampling" {
  run_conformance("upsampling")
}

///|
test "conformance_suite/upsampling_5" {
  run_conformance("upsampling_5")
}
