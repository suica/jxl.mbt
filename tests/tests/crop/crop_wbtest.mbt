///|
test "crop/bicycles" {
  testcase("bicycles")
}

///|
test "crop/bike" {
  testcase("bike")
}

///|
test "crop/alpha_triangles" {
  testcase("alpha_triangles")
}

///|
test "crop/lz77_flower" {
  testcase("lz77_flower")
}

///|
test "crop/sunset_logo" {
  testcase("sunset_logo")
}

///|
test "crop/blendmodes" {
  testcase("blendmodes")
}

///|
test "crop/progressive" {
  testcase("progressive")
}

///|
test "crop/animation_icos4d" {
  testcase("animation_icos4d")
}

///|
test "crop/animation_spline" {
  testcase("animation_spline")
}

///|
test "crop/animation_newtons_cradle" {
  testcase("animation_newtons_cradle")
}

///|
test "crop/lossless_pfm" {
  testcase("lossless_pfm")
}

///|
test "crop/noise" {
  testcase("noise")
}

///|
test "crop/cafe" {
  testcase("cafe")
}

///|
test "crop/upsampling" {
  testcase("upsampling")
}

///|
test "crop/delta_palette" {
  testcase("delta_palette")
}

///|
test "crop/patches_lossless" {
  testcase("patches_lossless")
}

///|
test "crop/grayscale" {
  testcase("grayscale")
}

///|
test "crop/grayscale_jpeg" {
  testcase("grayscale_jpeg")
}

///|
test "crop/grayscale_public_university" {
  testcase("grayscale_public_university")
}

///|
test "crop/spot" {
  testcase("spot")
}

///|
test "crop/crop_sunset_logo_0" {
  testcase_with_crop("crop_sunset_logo_0", "sunset_logo", [{ width: 179, height: 258, left: 527, top: 298, }])
}

///|
test "crop/crop_progressive_0" {
  testcase_with_crop("crop_progressive_0", "progressive", [{ width: 315, height: 571, left: 1711, top: 800, }])
}

///|
test "crop/crop_progressive_1" {
  testcase_with_crop("crop_progressive_1", "progressive", [{ width: 1159, height: 359, left: 776, top: 1745, }])
}

///|
test "crop/crop_noise_0" {
  testcase_with_crop("crop_noise_0", "noise", [{ width: 195, height: 162, left: 169, top: 194, }])
}

///|
test "crop/crop_blendmodes_0" {
  testcase_with_crop("crop_blendmodes_0", "blendmodes", [{ width: 242, height: 163, left: 81, top: 302, }])
}

///|
test "crop/crop_alpha_triangles_triple" {
  testcase_with_crop("crop_alpha_triangles_triple", "alpha_triangles", [
    { width: 460, height: 325, left: 468, top: 356, },
    { width: 361, height: 147, left: 524, top: 475, },
  ])
}

///|
test "crop/crop_progressive_triple" {
  testcase_with_crop("crop_progressive_triple", "progressive", [
    { width: 941, height: 659, left: 1893, top: 35, },
    { width: 1847, height: 1220, left: 850, top: 929, },
    { width: 1421, height: 814, left: 1568, top: 1460, },
  ])
}

///|
test "crop/crop_bike_0" {
  testcase_with_crop("crop_bike_0", "bike", [{ width: 936, height: 137, left: 877, top: 2353, }])
}

///|
#skip("fails only on CI with emulated aarch64")
test "crop/crop_upsampling_0" {
  testcase_with_crop("crop_upsampling_0", "upsampling", [{ width: 368, height: 128, left: 90, top: 460, }])
}
