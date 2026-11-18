// Port of jxl-oxide-tests/tests/conformance/mod.rs: every libjxl conformance
// test case (level 10 and the `_5` level 5 variants), one test each.
//
// Tolerances: jxl-oxide's per-channel table for the cases it lists (named
// `upstream`), else the suite's `test.json` (per frame, all channels).
// jxl-oxide's second run with `Moxcms` is not repeated: there is one CMS here
// (`@cms`, the default of every image).

///|
test "conformance/alpha_nonpremultiplied" {
  run_conformance("alpha_nonpremultiplied", Upstream(Uniform({ peak: 0.000061035, rmse: 0.000061035 })))
}

///|
test "conformance/alpha_premultiplied" {
  run_conformance("alpha_premultiplied", Upstream(PerChannel([
      { peak: 0.004, rmse: 0.0001 },
      { peak: 0.004, rmse: 0.0001 },
      { peak: 0.004, rmse: 0.0001 },
      { peak: 0.000003815, rmse: 0.000003815 },
    ])))
}

///|
test "conformance/alpha_triangles" {
  run_conformance("alpha_triangles", Upstream(Uniform({ peak: 0.001953125, rmse: 0.001953125 })))
}

///|
test "conformance/animation_icos4d" {
  run_conformance("animation_icos4d", Upstream(PerChannel([
      { peak: 0.005, rmse: 0.0001 },
      { peak: 0.005, rmse: 0.0001 },
      { peak: 0.005, rmse: 0.0001 },
      { peak: 0.000976562, rmse: 0.000976562 },
    ])))
}

///|
test "conformance/animation_icos4d_5" {
  run_conformance("animation_icos4d_5", TestJson)
}

///|
test "conformance/animation_newtons_cradle" {
  run_conformance("animation_newtons_cradle", Upstream(Uniform({ peak: 0.000976562, rmse: 0.000976562 })))
}

///|
test "conformance/animation_spline" {
  run_conformance("animation_spline", Upstream(Uniform({ peak: 0.004, rmse: 0.0001 })))
}

///|
test "conformance/animation_spline_5" {
  run_conformance("animation_spline_5", TestJson)
}

///|
test "conformance/bench_oriented_brg" {
  run_conformance("bench_oriented_brg", Upstream(Uniform({ peak: 0.004, rmse: 0.00001 })))
}

///|
test "conformance/bench_oriented_brg_5" {
  run_conformance("bench_oriented_brg_5", TestJson)
}

///|
test "conformance/bicycles" {
  run_conformance("bicycles", Upstream(Uniform({ peak: 0.000976562, rmse: 0.000976562 })))
}

///|
test "conformance/bike" {
  run_conformance("bike", Upstream(Uniform({ peak: 0.007, rmse: 0.0001 })))
}

///|
test "conformance/bike_5" {
  run_conformance("bike_5", TestJson)
}

///|
test "conformance/blendmodes" {
  run_conformance("blendmodes", Upstream(Uniform({ peak: 0.004, rmse: 0.0001 })))
}

///|
test "conformance/blendmodes_5" {
  run_conformance("blendmodes_5", TestJson)
}

///|
test "conformance/cafe" {
  run_conformance("cafe", Upstream(Uniform({ peak: 0.004, rmse: 0.00001 })))
}

///|
test "conformance/cafe_5" {
  run_conformance("cafe_5", TestJson)
}

///|
test "conformance/cmyk_layers" {
  run_conformance("cmyk_layers", Upstream(Uniform({ peak: 0.000976562, rmse: 0.000976562 })))
}

///|
test "conformance/delta_palette" {
  run_conformance("delta_palette", Upstream(Uniform({ peak: 0.000976562, rmse: 0.000976562 })))
}

///|
test "conformance/grayscale" {
  run_conformance("grayscale", Upstream(Uniform({ peak: 0.004, rmse: 0.0001 })))
}

///|
test "conformance/grayscale_5" {
  run_conformance("grayscale_5", TestJson)
}

///|
test "conformance/grayscale_jpeg" {
  run_conformance("grayscale_jpeg", Upstream(Uniform({ peak: 0.004, rmse: 0.00001 })))
}

///|
test "conformance/grayscale_jpeg_5" {
  run_conformance("grayscale_jpeg_5", TestJson)
}

///|
test "conformance/grayscale_public_university" {
  run_conformance("grayscale_public_university", Upstream(Uniform({ peak: 0.000976562, rmse: 0.000976562 })))
}

///|
test "conformance/lossless_pfm" {
  run_conformance("lossless_pfm", Upstream(Uniform({ peak: 0.0, rmse: 0.0 })))
}

///|
test "conformance/lz77_flower" {
  run_conformance("lz77_flower", Upstream(Uniform({ peak: 0.000976562, rmse: 0.000976562 })))
}

///|
test "conformance/mul_no_extra_channels" {
  run_conformance("mul_no_extra_channels", TestJson)
}

///|
test "conformance/noise" {
  run_conformance("noise", Upstream(Uniform({ peak: 0.004, rmse: 0.0001 })))
}

///|
test "conformance/noise_5" {
  run_conformance("noise_5", TestJson)
}

///|
test "conformance/opsin_inverse" {
  run_conformance("opsin_inverse", Upstream(Uniform({ peak: 0.004, rmse: 0.0001 })))
}

///|
test "conformance/opsin_inverse_5" {
  run_conformance("opsin_inverse_5", TestJson)
}

///|
test "conformance/patches" {
  run_conformance("patches", Upstream(PerChannel([
      { peak: 0.004, rmse: 0.0001 },
      { peak: 0.004, rmse: 0.0001 },
      { peak: 0.004, rmse: 0.0001 },
      { peak: 0.000976562, rmse: 0.000976562 },
    ])))
}

///|
test "conformance/patches_5" {
  run_conformance("patches_5", TestJson)
}

///|
test "conformance/patches_lossless" {
  run_conformance("patches_lossless", Upstream(Uniform({ peak: 0.000976562, rmse: 0.000976562 })))
}

///|
test "conformance/progressive" {
  run_conformance("progressive", Upstream(Uniform({ peak: 0.02, rmse: 0.0001 })))
}

///|
test "conformance/progressive_5" {
  run_conformance("progressive_5", TestJson)
}

///|
test "conformance/spot" {
  run_conformance("spot", Upstream(Uniform({ peak: 0.000003815, rmse: 0.000003815 })))
}

///|
test "conformance/sunset_logo" {
  run_conformance("sunset_logo", Upstream(Uniform({ peak: 0.000244141, rmse: 0.000244141 })))
}

///|
test "conformance/upsampling" {
  run_conformance("upsampling", Upstream(Uniform({ peak: 0.004, rmse: 0.0001 })))
}

///|
test "conformance/upsampling_5" {
  run_conformance("upsampling_5", TestJson)
}
