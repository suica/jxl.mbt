///|
fn b64decode(s : String) -> Bytes {
  let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  let lut = FixedArray::make(128, -1)
  for i, c in alphabet {
    lut[c.to_int()] = i
  }
  let out : Array[Byte] = []
  let mut acc = 0
  let mut nbits = 0
  for c in s {
    let code = c.to_int()
    if code >= 128 || lut[code] < 0 {
      continue
    }
    acc = (acc << 6) | lut[code]
    nbits += 6
    if nbits >= 8 {
      nbits -= 8
      out.push(((acc >> nbits) & 0xFF).to_byte())
    }
  }
  Bytes::from_array(out)
}

///|
fn intent_of(i : Int32) -> @cms.RenderingIntent {
  match i {
    0 => Perceptual
    1 => Relative
    2 => Saturation
    _ => Absolute
  }
}

///|
test "transforms match Little CMS 2.19 float transforms" {
  let mut worst = 0.0
  for case_ in fixture_cases {
    let (src, dst, intent, input_bits, expected_bits) = case_
    let t = @cms.Transform::from_icc(
      fixture_profile(src),
      fixture_profile(dst),
      intent_of(intent),
    )
    let n = input_bits.length() / t.num_input_channels
    let input = FixedArray::make(input_bits.length(), Float::from_double(0.0))
    for i, b in input_bits {
      input[i] = Float::reinterpret_from_uint(b)
    }
    let output = FixedArray::make(
      n * t.num_output_channels,
      Float::from_double(0.0),
    )
    t.transform_interleaved(input, output, n)
    assert_eq(output.length(), expected_bits.length())
    for i, b in expected_bits {
      let e = Float::reinterpret_from_uint(b).to_double()
      let d = (output[i].to_double() - e).abs()
      if d > worst {
        worst = d
      }
      if d > 1.0e-6 {
        fail(
          "\{src} -> \{dst} intent \{intent} value \{i}: got \{output[i]}, expected \{e}",
        )
      }
    }
  }
  // Bit-exact on native; allow for libm differences elsewhere.
  assert_true(worst <= 1.0e-6)
}

///|
test "profile header parsing" {
  let p = @cms.Profile::parse(fixture_profile("cmyk_v2_lut"))
  assert_true(p.is_cmyk())
  assert_eq(p.num_channels(), 4)
  assert_eq(p.version, 0x02100000U)
  assert_eq(p.rendering_intent, 1U)
  let g = @cms.Profile::parse(fixture_profile("gray_linear_v4"))
  assert_true(g.is_gray())
  assert_eq(g.num_channels(), 1)
  assert_eq(@cms.Profile::parse(fixture_profile("mch5_v4")).num_channels(), 5)
}

///|
test "invalid profiles are rejected" {
  let r = Some(@cms.Profile::parse(b"\x00\x01")) catch { _ => None }
  assert_true(r is None)
  let bad = fixture_profile("srgb_v4_rel").to_array()
  bad[36] = b'x'
  let r2 = Some(@cms.Profile::parse(Bytes::from_array(bad))) catch { _ => None }
  assert_true(r2 is None)
}

///|
test "planar transform equals interleaved" {
  let t = @cms.Transform::from_icc(
    fixture_profile("cmyk_v2_lut"),
    fixture_profile("srgb_linear_v4_rel"),
    Relative,
  )
  assert_eq(t.num_input_channels, 4)
  assert_eq(t.num_output_channels, 3)
  let n = 7
  let planes : Array[FixedArray[Float]] = []
  for c in 0..<4 {
    let p = FixedArray::make(n, Float::from_double(0.0))
    for i in 0..<n {
      p[i] = Float::from_double(((i * 3 + c * 5) % 11).to_double() / 10.0)
    }
    planes.push(p)
  }
  let inter = FixedArray::make(n * 4, Float::from_double(0.0))
  for i in 0..<n {
    for c in 0..<4 {
      inter[i * 4 + c] = planes[c][i]
    }
  }
  let out = FixedArray::make(n * 3, Float::from_double(0.0))
  t.transform_interleaved(inter, out, n)
  t.transform_planar(planes)
  for i in 0..<n {
    for c in 0..<3 {
      assert_eq(planes[c][i], out[i * 3 + c])
    }
  }
}

///|
test "MoonCms implements the colour CMS trait" {
  let cms : &@color.ColorManagementSystem = @cms.MoonCms::{ }
  assert_true(cms.supports_linear_tf())
  let t = cms.prepare_transform(
    fixture_profile("cmyk_v2_lut"),
    fixture_profile("srgb_v4_rel"),
    @image.RenderingIntent::Relative,
  )
  assert_eq(t.num_input_channels(), 4)
  assert_eq(t.num_output_channels(), 3)
  let planes : Array[FixedArray[Float]] = []
  for c in 0..<4 {
    planes.push(FixedArray::make(4, Float::from_double(c.to_double() / 4.0)))
  }
  let direct = @cms.Transform::from_icc(
    fixture_profile("cmyk_v2_lut"),
    fixture_profile("srgb_v4_rel"),
    Relative,
  )
  let px = FixedArray::make(4, Float::from_double(0.0))
  for c in 0..<4 {
    px[c] = planes[c][0]
  }
  let expected = FixedArray::make(3, Float::from_double(0.0))
  direct.transform_pixel(px, expected)
  t.transform(planes, 1, 2)
  for c in 0..<3 {
    assert_eq(planes[c][1], expected[c])
    assert_eq(planes[c][2], expected[c])
  }
  // Samples outside start..start+len are left alone.
  assert_eq(planes[0][0], Float::from_double(0.0))
  assert_eq(planes[0][3], Float::from_double(0.0))
  let bad = Some(
    cms.prepare_transform(b"x", fixture_profile("srgb_v4_rel"), Relative),
  ) catch {
    _ => None
  }
  assert_true(bad is None)
}

///|
test "synthesized jxl profiles link with LUT profiles" {
  // CMYK -> linear sRGB as jxl-oxide's cms test does, through the ICC
  // profile synthesized by @color for the requested encoding.
  let lin = @color.colour_encoding_to_icc(
    @image.EnumColourEncoding::srgb_linear(@image.RenderingIntent::Relative),
  )
  let t = @cms.Transform::from_icc(
    fixture_profile("cmyk_v2_lut"),
    lin,
    Relative,
  )
  let reference = @cms.Transform::from_icc(
    fixture_profile("cmyk_v2_lut"),
    fixture_profile("srgb_linear_v4_rel"),
    Relative,
  )
  let px : FixedArray[Float] = [
    Float::from_double(0.1),
    Float::from_double(0.6),
    Float::from_double(0.3),
    Float::from_double(0.2),
  ]
  let a = FixedArray::make(3, Float::from_double(0.0))
  let b = FixedArray::make(3, Float::from_double(0.0))
  t.transform_pixel(px, a)
  reference.transform_pixel(px, b)
  for c in 0..<3 {
    assert_true((a[c] - b[c]).abs() < Float::from_double(1.0e-4))
  }
  // Perceptual from a v4 synthesized profile forces BPC (both blacks zero).
  let srgb = @color.colour_encoding_to_icc(
    @image.EnumColourEncoding::srgb(@image.RenderingIntent::Perceptual),
  )
  let t2 = @cms.Transform::from_icc(lin, srgb, Perceptual)
  let black = FixedArray::make(3, Float::from_double(0.0))
  t2.transform_pixel(FixedArray::make(3, Float::from_double(0.0)), black)
  assert_true(black[0].abs() < Float::from_double(1.0e-6))
}
