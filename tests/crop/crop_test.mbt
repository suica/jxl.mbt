///|
test "crop/bicycles" {
  run_random_crops("bicycles")
}

///|
test "crop/bike" {
  run_random_crops("bike")
}

///|
test "crop/alpha_triangles" {
  run_random_crops("alpha_triangles")
}

///|
test "crop/lz77_flower" {
  run_random_crops("lz77_flower")
}

///|
test "crop/sunset_logo" {
  run_random_crops("sunset_logo")
}

///|
test "crop/blendmodes" {
  run_random_crops("blendmodes")
}

///|
test "crop/progressive" {
  run_random_crops("progressive")
}

///|
test "crop/animation_icos4d" {
  run_random_crops("animation_icos4d")
}

///|
test "crop/animation_spline" {
  run_random_crops("animation_spline")
}

///|
test "crop/animation_newtons_cradle" {
  run_random_crops("animation_newtons_cradle")
}

///|
test "crop/lossless_pfm" {
  run_random_crops("lossless_pfm")
}

///|
test "crop/noise" {
  run_random_crops("noise")
}

///|
test "crop/cafe" {
  run_random_crops("cafe")
}

///|
test "crop/upsampling" {
  run_random_crops("upsampling")
}

///|
test "crop/delta_palette" {
  run_random_crops("delta_palette")
}

///|
test "crop/patches_lossless" {
  run_random_crops("patches_lossless")
}

///|
test "crop/grayscale" {
  run_random_crops("grayscale")
}

///|
test "crop/grayscale_jpeg" {
  run_random_crops("grayscale_jpeg")
}

///|
test "crop/grayscale_public_university" {
  run_random_crops("grayscale_public_university")
}

///|
test "crop/spot" {
  run_random_crops("spot")
}

///|
test "crop/crop_sunset_logo_0" {
  run_crops("sunset_logo", [
    { width: 179, height: 258, left: 527, top: 298 },
  ])
}

///|
test "crop/crop_progressive_0" {
  run_crops("progressive", [
    { width: 315, height: 571, left: 1711, top: 800 },
  ])
}

///|
test "crop/crop_progressive_1" {
  run_crops("progressive", [
    { width: 1159, height: 359, left: 776, top: 1745 },
  ])
}

///|
test "crop/crop_noise_0" {
  run_crops("noise", [
    { width: 195, height: 162, left: 169, top: 194 },
  ])
}

///|
test "crop/crop_blendmodes_0" {
  run_crops("blendmodes", [
    { width: 242, height: 163, left: 81, top: 302 },
  ])
}

///|
test "crop/crop_alpha_triangles_triple" {
  run_crops("alpha_triangles", [
    { width: 460, height: 325, left: 468, top: 356 },
    { width: 361, height: 147, left: 524, top: 475 },
  ])
}

///|
test "crop/crop_progressive_triple" {
  run_crops("progressive", [
    { width: 941, height: 659, left: 1893, top: 35 },
    { width: 1847, height: 1220, left: 850, top: 929 },
    { width: 1421, height: 814, left: 1568, top: 1460 },
  ])
}

///|
test "crop/crop_bike_0" {
  run_crops("bike", [
    { width: 936, height: 137, left: 877, top: 2353 },
  ])
}

///|
test "crop/crop_upsampling_0" {
  // upstream: #[ignore = "fails only on CI with emulated aarch64"]
  run_crops("upsampling", [
    { width: 368, height: 128, left: 90, top: 460 },
  ])
}
