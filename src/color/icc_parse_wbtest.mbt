// Tests ported from jxl-color/src/icc/parse.rs.

///|
test "srgb_rel" {
  let profile = parse_icc(profile_srgb_rel)
  assert_true(
    profile
    is {
      colour_space: Rgb,
      white_point: D65,
      primaries: Srgb,
      tf: Srgb,
      rendering_intent: Relative,
    },
  )
}

///|
test "srgb_bt709_per" {
  let profile = parse_icc(profile_srgb_bt709_per)
  assert_true(
    profile
    is {
      colour_space: Rgb,
      white_point: D65,
      primaries: Srgb,
      tf: Bt709,
      rendering_intent: Perceptual,
    },
  )
}

///|
test "srgb_gamma22_per" {
  // gamma of the profile is 0x23332 (0.4545500), not 0x23333 (0.4545455)
  let profile = parse_icc(profile_srgb_gamma22_rel)
  assert_true(
    profile
    is {
      colour_space: Rgb,
      white_point: D65,
      primaries: Srgb,
      tf: Gamma(g=21999000..<=22001000, inverted=false),
      rendering_intent: Relative,
    },
  )
}

///|
test "srgb_linear_per" {
  let profile = parse_icc(profile_srgb_linear_rel)
  assert_true(
    profile
    is {
      colour_space: Rgb,
      white_point: D65,
      primaries: Srgb,
      tf: Linear,
      rendering_intent: Relative,
    },
  )
}

///|
test "gray_d65_srgb_rel" {
  let profile = parse_icc(profile_gray_d65_srgb_rel)
  assert_true(
    profile
    is {
      colour_space: Grey,
      white_point: D65,
      tf: Srgb,
      rendering_intent: Relative,
      ..
    },
  )
}

///|
test "gray_d65_linear_rel" {
  let profile = parse_icc(profile_gray_d65_linear_rel)
  assert_true(
    profile
    is {
      colour_space: Grey,
      white_point: D65,
      tf: Linear,
      rendering_intent: Relative,
      ..
    },
  )
}

///|
test "prophoto gamma 1.8 is custom" {
  let profile = parse_icc(profile_prophoto_gamma18_rel)
  assert_true(profile.colour_space is Rgb)
  assert_true(profile.primaries is Custom(..))
  assert_true(profile.tf is Gamma(inverted=false, ..))
  assert_eq(icc_tf(profile_prophoto_gamma18_rel), Some(profile.tf))
}

///|
test "synthesize then parse round trip" {
  let encodings = [
    @image.EnumColourEncoding::srgb(Relative),
    @image.EnumColourEncoding::srgb(Perceptual),
    @image.EnumColourEncoding::srgb_linear(Relative),
    @image.EnumColourEncoding::srgb_gamma22(Relative),
    @image.EnumColourEncoding::bt709(Saturation),
    @image.EnumColourEncoding::display_p3(Relative),
    @image.EnumColourEncoding::dci_p3(Absolute),
    @image.EnumColourEncoding::gray_srgb(Relative),
    @image.EnumColourEncoding::gray_gamma22(Relative),
    {
      colour_space: Rgb,
      white_point: E,
      primaries: Bt2100,
      tf: Linear,
      rendering_intent: Relative,
    },
  ]
  for enc in encodings {
    let icc = colour_encoding_to_icc(enc)
    // header and size field
    assert_eq(icc[36:40].to_bytes(), b"acsp")
    let size = (icc[0].to_int() << 24) |
      (icc[1].to_int() << 16) |
      (icc[2].to_int() << 8) |
      icc[3].to_int()
    assert_eq(size, icc.length())
    let parsed = parse_icc(icc)
    assert_eq(parsed.colour_space, enc.colour_space)
    assert_eq(parsed.white_point, enc.white_point)
    assert_eq(parsed.rendering_intent, enc.rendering_intent)
    if enc.colour_space is Rgb {
      assert_eq(parsed.primaries, enc.primaries)
    }
    match (parsed.tf, enc.tf) {
      (Gamma(g=a, inverted=false), Gamma(g=b, inverted=false)) =>
        assert_true((a - b).abs() < 2000)
      (Gamma(g=a, inverted=false), Dci) =>
        assert_true((a - 26000000).abs() < 2000)
      (a, b) => assert_eq(a, b)
    }
  }
}

///|
test "synthesize desc uses Rust debug formatting" {
  let enc : EnumColourEncoding = {
    colour_space: Rgb,
    white_point: Custom({ x: 312700, y: 329000, }),
    primaries: Custom(
      red={ x: 640000, y: 330000, },
      green={ x: 300000, y: 600000, },
      blue={ x: 150000, y: 60000, },
    ),
    tf: Gamma(g=4545455, inverted=true),
    rendering_intent: Relative,
  }
  let desc = "Rgb_Relative_Custom(Customxy { x: 312700, y: 329000 })_Custom { red: Customxy { x: 640000, y: 330000 }, green: Customxy { x: 300000, y: 600000 }, blue: Customxy { x: 150000, y: 60000 } }_Gamma { g: 4545455, inverted: true }"
  let icc = colour_encoding_to_icc(enc)
  let mluc = create_mluc(b"enUS", [desc])
  // the desc tag is the first tag in the data area
  let data_start = 128 + 4 + 12 * 10
  for i in 0..<mluc.length() {
    assert_eq(icc[data_start + i], mluc[i])
  }
  let parsed = parse_icc(icc)
  assert_true(parsed.white_point is D65)
  assert_true(parsed.tf is Gamma(inverted=false, ..))
}
