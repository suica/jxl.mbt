///|
fn upstream_case_transform(name : String) -> ColorTransform raise {
  let e = ColorEncodingWithProfile::new
  let gray_pq = { ..EnumColourEncoding::gray_srgb(Relative), tf: Pq, }
  let (from, to, it, detect_peak, from_pq) = match name {
    "xyb_srgb" =>
      (
        EnumColourEncoding::xyb(Relative),
        EnumColourEncoding::srgb(Relative),
        255.0,
        false,
        false,
      )
    "xyb_p3_perc" =>
      (
        EnumColourEncoding::xyb(Perceptual),
        EnumColourEncoding::display_p3(Perceptual),
        255.0,
        false,
        false,
      )
    "xyb_gray" =>
      (
        EnumColourEncoding::xyb(Relative),
        EnumColourEncoding::gray_srgb(Relative),
        255.0,
        false,
        false,
      )
    "xyb_pq" =>
      (
        EnumColourEncoding::xyb(Relative),
        EnumColourEncoding::bt2100_pq(Relative),
        4000.0,
        false,
        false,
      )
    "xyb_hlg" =>
      (
        EnumColourEncoding::xyb(Relative),
        EnumColourEncoding::bt2100_hlg(Relative),
        1000.0,
        false,
        false,
      )
    "xyb_hdr_srgb" =>
      (
        EnumColourEncoding::xyb(Perceptual),
        EnumColourEncoding::srgb(Perceptual),
        4000.0,
        false,
        false,
      )
    "xyb_hdr_srgb_peak" =>
      (
        EnumColourEncoding::xyb(Relative),
        EnumColourEncoding::srgb(Relative),
        4000.0,
        true,
        false,
      )
    "srgb_linear" =>
      (
        EnumColourEncoding::srgb(Relative),
        EnumColourEncoding::srgb_linear(Relative),
        255.0,
        false,
        false,
      )
    "linear_srgb" =>
      (
        EnumColourEncoding::srgb_linear(Relative),
        EnumColourEncoding::srgb(Relative),
        255.0,
        false,
        false,
      )
    "bt709_g22" =>
      (
        EnumColourEncoding::bt709(Relative),
        EnumColourEncoding::srgb_gamma22(Relative),
        255.0,
        false,
        false,
      )
    "g22_bt709" =>
      (
        EnumColourEncoding::srgb_gamma22(Relative),
        EnumColourEncoding::bt709(Relative),
        255.0,
        false,
        false,
      )
    "dcip3_srgb" =>
      (
        EnumColourEncoding::dci_p3(Relative),
        EnumColourEncoding::srgb(Relative),
        255.0,
        false,
        false,
      )
    "srgb_dcip3_abs" =>
      (
        EnumColourEncoding::srgb(Absolute),
        EnumColourEncoding::dci_p3(Absolute),
        255.0,
        false,
        false,
      )
    "pq_srgb" =>
      (
        EnumColourEncoding::bt2100_pq(Perceptual),
        EnumColourEncoding::srgb(Perceptual),
        10000.0,
        false,
        false,
      )
    "pq_srgb_peak" =>
      (
        EnumColourEncoding::bt2100_pq(Relative),
        EnumColourEncoding::srgb(Relative),
        1000.0,
        true,
        false,
      )
    "pq_hlg" =>
      (
        EnumColourEncoding::bt2100_pq(Perceptual),
        EnumColourEncoding::bt2100_hlg(Perceptual),
        4000.0,
        false,
        true,
      )
    "hlg_srgb" =>
      (
        EnumColourEncoding::bt2100_hlg(Relative),
        EnumColourEncoding::srgb(Relative),
        1000.0,
        false,
        false,
      )
    "hlg_pq" =>
      (
        EnumColourEncoding::bt2100_hlg(Relative),
        EnumColourEncoding::bt2100_pq(Relative),
        1000.0,
        false,
        false,
      )
    "gray_pq_gray" =>
      (gray_pq, EnumColourEncoding::gray_srgb(Relative), 4000.0, false, false)
    "gray_pq_gray_peak" =>
      (gray_pq, EnumColourEncoding::gray_gamma22(Relative), 4000.0, true, false)
    "gray_srgb_rgb" =>
      (
        EnumColourEncoding::gray_srgb(Relative),
        EnumColourEncoding::display_p3(Relative),
        255.0,
        false,
        false,
      )
    _ => fail("unknown case \{name}")
  }
  let tm = {
    ..ToneMapping::default(),
    intensity_target: Float::from_double(it),
  }
  ColorTransform::builder()
  .set_detect_peak(detect_peak)
  .from_pq(from_pq)
  .build(e(from), e(to), OpsinInverseMatrix::default(), tm, NullCms::{ })
}

///|
test "ColorTransform::run matches upstream bit for bit" {
  let mut mismatches = 0
  let mut first = ""
  for c in upstream_case_transform_cache() {
    let (case, t) = c
    let channels = case.input.map(ch => ch.map(Float::reinterpret_from_uint))
    let out = t.run(Array::from_fixed_array(channels))
    assert_eq(out, case.out_channels)
    for k in 0..<channels.length() {
      for i in 0..<case.n {
        if channels[k][i].reinterpret_as_uint() != case.output[k][i] {
          println(
            "\{case.name} n=\{case.n} ch=\{k} i=\{i}: got \{channels[k][i]} expected \{Float::reinterpret_from_uint(case.output[k][i])} in \{Float::reinterpret_from_uint(case.input[k][i])}",
          )
          if mismatches == 0 {
            first = "\{case.name} n=\{case.n} ch=\{k} i=\{i}: got \{channels[k][i]} expected \{Float::reinterpret_from_uint(case.output[k][i])}"
          }
          mismatches += 1
        }
      }
    }
  }
  if mismatches > 0 {
    fail("\{mismatches} mismatching samples; first: \{first}")
  }
}

///|
fn upstream_case_transform_cache() -> Array[(UpstreamCase, ColorTransform)] raise {
  let out = []
  for c in upstream_cases {
    out.push((c, upstream_case_transform(c.name)))
  }
  out
}
