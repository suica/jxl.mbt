///|
fn default_oim() -> OpsinInverseMatrix {
  OpsinInverseMatrix::default()
}

///|
fn default_tone_mapping(intensity_target : Float) -> ToneMapping {
  // `all_default` is private (as upstream); set the public field only.
  let tone_mapping = ToneMapping::default()
  tone_mapping.intensity_target = intensity_target
  tone_mapping
}

///|
/// XYB sample for a gray of linear value `v` (intensity target 255).
fn xyb_gray(v : Float) -> Float {
  let ob : Float = -0.0037930732552754493
  @math.cbrtf(v - ob) + @math.cbrtf(ob)
}

///|
fn op_names(t : ColorTransform) -> Array[String] {
  t.ops.map(op => {
    match op {
      XybToMixedLms(..) => "XybToMixedLms"
      LumaToXyz(..) => "LumaToXyz"
      XyzToLuma => "XyzToLuma"
      Matrix(_) => "Matrix"
      TransferFunction(inverse~, ..) =>
        if inverse {
          "InvTransferFunction"
        } else {
          "TransferFunction"
        }
      HlgInverseOotf(_) => "HlgInverseOotf"
      ToneMapRec2408(..) => "ToneMapRec2408"
      ToneMapLumaRec2408(..) => "ToneMapLumaRec2408"
      GamutMap(..) => "GamutMap"
      Clip => "Clip"
      IccToIcc(_) => "IccToIcc"
    }
  })
}

///|
test "xyb to srgb" {
  let t = ColorTransform::xyb_to_enum(
    Relative,
    EnumColourEncoding::srgb(Relative),
    default_oim(),
    default_tone_mapping(255.0),
  )
  assert_eq(op_names(t), ["XybToMixedLms", "Matrix", "TransferFunction"])
  assert_eq(t.input_channels(), 3)
  assert_eq(t.output_channels(), 3)
  let y = xyb_gray(0.18)
  let channels : Array[FixedArray[Float]] = [[0.0, 0.0], [y, 0.0], [y, 0.0]]
  let n = t.run(channels)
  assert_eq(n, 3)
  // sRGB of linear 0.18 is ~0.4613
  for c in 0..<3 {
    assert_true((channels[c][0] - 0.46135613).abs() < 1.0e-3)
  }
}

///|
test "xyb to linear srgb is matrix only" {
  let t = ColorTransform::xyb_to_enum(
    Relative,
    EnumColourEncoding::srgb_linear(Relative),
    default_oim(),
    default_tone_mapping(255.0),
  )
  assert_eq(op_names(t), ["XybToMixedLms", "Matrix"])
  let y = xyb_gray(0.5)
  let channels : Array[FixedArray[Float]] = [[0.0], [y], [y]]
  let _ = t.run_with_threads(channels)
  for c in 0..<3 {
    assert_true((channels[c][0] - 0.5).abs() < 1.0e-4)
  }
}

///|
test "equivalent encodings are noop" {
  let t = ColorTransform::new(
    ColorEncodingWithProfile::new(EnumColourEncoding::srgb(Relative)),
    ColorEncodingWithProfile::new(EnumColourEncoding::srgb(Relative)),
    default_oim(),
    default_tone_mapping(255.0),
    NullCms::{ },
  )
  assert_true(t.is_noop())
  assert_eq(t.output_channels(), 3)
}

///|
test "srgb to linear srgb" {
  let t = ColorTransform::new(
    ColorEncodingWithProfile::new(EnumColourEncoding::srgb(Relative)),
    ColorEncodingWithProfile::new(EnumColourEncoding::srgb_linear(Relative)),
    default_oim(),
    default_tone_mapping(255.0),
    NullCms::{ },
  )
  assert_eq(op_names(t), ["InvTransferFunction"])
  let channels : Array[FixedArray[Float]] = [[0.5], [1.0], [0.0]]
  let _ = t.run(channels)
  assert_true((channels[0][0] - 0.21404114).abs() < 1.0e-5)
  assert_true((channels[1][0] - 1.0).abs() < 1.0e-5)
  assert_eq(channels[2][0], 0.0)
}

///|
test "srgb to bt2100 pq with gamut conversion" {
  let target : EnumColourEncoding = {
    colour_space: Rgb,
    white_point: D65,
    primaries: Bt2100,
    tf: Pq,
    rendering_intent: Relative,
  }
  let t = ColorTransform::new(
    ColorEncodingWithProfile::new(EnumColourEncoding::srgb(Relative)),
    ColorEncodingWithProfile::new(target),
    default_oim(),
    default_tone_mapping(255.0),
    NullCms::{ },
  )
  // RGB->XYZ, adaptation (identity) and XYZ->RGB are merged into one matrix.
  assert_eq(op_names(t), [
    "InvTransferFunction", "Clip", "Matrix", "TransferFunction",
  ])
  // white stays white
  let channels : Array[FixedArray[Float]] = [[1.0], [1.0], [1.0]]
  let _ = t.run(channels)
  let expected = linear_to_pq_generic(1.0, 255.0)
  for c in 0..<3 {
    assert_true((channels[c][0] - expected).abs() < 1.0e-4)
  }
}

///|
test "hdr to sdr tone maps" {
  let source : EnumColourEncoding = {
    colour_space: Rgb,
    white_point: D65,
    primaries: Bt2100,
    tf: Pq,
    rendering_intent: Perceptual,
  }
  let t = ColorTransform::new(
    ColorEncodingWithProfile::new(source),
    ColorEncodingWithProfile::new(EnumColourEncoding::srgb(Perceptual)),
    default_oim(),
    default_tone_mapping(10000.0),
    NullCms::{ },
  )
  assert_eq(op_names(t), [
    "InvTransferFunction", "GamutMap", "Matrix", "ToneMapRec2408", "GamutMap", "TransferFunction",
  ])
}

///|
test "rgb to grey" {
  let t = ColorTransform::new(
    ColorEncodingWithProfile::new(EnumColourEncoding::srgb_linear(Relative)),
    ColorEncodingWithProfile::new({
      colour_space: Grey,
      white_point: D65,
      primaries: Srgb,
      tf: Linear,
      rendering_intent: Relative,
    }),
    default_oim(),
    default_tone_mapping(255.0),
    NullCms::{ },
  )
  assert_eq(op_names(t), ["InvTransferFunction", "Clip", "Matrix", "XyzToLuma"])
  assert_eq(t.output_channels(), 1)
  let channels : Array[FixedArray[Float]] = [[0.5], [0.5], [0.5]]
  assert_eq(t.run(channels), 1)
  assert_true((channels[0][0] - 0.5).abs() < 1.0e-5)
}

///|
test "grey to rgb" {
  let t = ColorTransform::new(
    ColorEncodingWithProfile::new({
      colour_space: Grey,
      white_point: D65,
      primaries: Srgb,
      tf: Linear,
      rendering_intent: Relative,
    }),
    ColorEncodingWithProfile::new(EnumColourEncoding::srgb_linear(Relative)),
    default_oim(),
    default_tone_mapping(255.0),
    NullCms::{ },
  )
  assert_eq(t.input_channels(), 1)
  assert_eq(op_names(t), ["InvTransferFunction", "Clip", "LumaToXyz", "Matrix"])
  assert_eq(t.output_channels(), 3)
  let channels : Array[FixedArray[Float]] = [[0.25], [0.0], [0.0]]
  assert_eq(t.run(channels), 3)
  for c in 0..<3 {
    assert_true((channels[c][0] - 0.25).abs() < 1.0e-4)
  }
}

///|
/// A header-only RGB ICC profile (no TRC tags, so it is not representable as
/// an enum colour encoding). `marker` goes into an unused header byte.
fn fake_rgb_icc(marker : Byte) -> Bytes {
  Bytes::makei(128, i => {
    match i {
      3 => b'\x80' // size = 128
      0x10 => b'R'
      0x11 => b'G'
      0x12 => b'B'
      0x13 => b' '
      0x64 => marker
      _ => b'\x00'
    }
  })
}

///|
test "icc target requires cms" {
  let to = ColorEncodingWithProfile::with_icc(fake_rgb_icc(b'\x00'))
  assert_true(to.encoding().want_icc())
  let result = Ok(
    ColorTransform::new(
      ColorEncodingWithProfile::new(EnumColourEncoding::srgb(Relative)),
      to,
      default_oim(),
      default_tone_mapping(255.0),
      NullCms::{ },
    ),
  ) catch {
    e => Err(e)
  }
  guard result is Err(@bitstream.Color("CmsNotAvailable")) else {
    fail("expected CmsNotAvailable")
  }
}

///|
priv struct TestCms {}

///|
priv struct SwapTransform {}

///|
impl PreparedTransform for SwapTransform with fn num_input_channels(_) {
  3
}

///|
impl PreparedTransform for SwapTransform with fn num_output_channels(_) {
  3
}

///|
impl PreparedTransform for SwapTransform with fn transform(
  _,
  channels,
  start,
  len,
) {
  for i in start..<(start + len) {
    let t = channels[0][i]
    channels[0][i] = channels[2][i]
    channels[2][i] = t
  }
}

///|
impl ColorManagementSystem for TestCms with fn prepare_transform(_, _, _, _) {
  SwapTransform::{ }
}

///|
test "icc to icc uses cms" {
  let from = ColorEncodingWithProfile::with_icc(fake_rgb_icc(b'\x00'))
  let to = ColorEncodingWithProfile::with_icc(fake_rgb_icc(b'\x01'))
  assert_true(!from.is_grayscale())
  assert_true(!from.is_cmyk())
  let t = ColorTransform::new(
    from,
    to,
    default_oim(),
    default_tone_mapping(255.0),
    TestCms::{ },
  )
  assert_eq(op_names(t), ["IccToIcc"])
  let channels : Array[FixedArray[Float]] = [[1.0, 2.0], [0.0, 0.0], [3.0, 4.0]]
  assert_eq(t.run(channels, start=1, len=1), 3)
  assert_eq(channels[0][0], 1.0)
  assert_eq(channels[0][1], 4.0)
  assert_eq(channels[2][1], 2.0)
  assert_true(ColorManagementSystem::supports_linear_tf(TestCms::{ }))
}
