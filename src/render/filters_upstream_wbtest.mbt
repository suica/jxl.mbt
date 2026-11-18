// Parity with upstream: the hashes below were printed by jxl-oxide 0.12.6
// itself (jxl-render built on x86_64 with a test module calling
// `filter::apply_gabor_like`, `impls::epf` / `impls::generic::epf`,
// `features::render_noise`, `features::upsample` and
// `features::render_spline` on the same inputs). Hash: h = h * 1000003 +
// bits, row by row.

///|
fn up_hash_grid(g : @grid.Grid[Float]) -> UInt64 {
  let mut h = 0UL
  for y in 0..<g.height() {
    for x in 0..<g.width() {
      h = h * 1000003UL + g.get(x, y).reinterpret_as_uint().to_uint64()
    }
  }
  h
}

///|
fn up_frame_header(width : Int32, height : Int32) -> @frame.FrameHeader {
  let ih : @image.ImageHeader = {
    size: { div8: false, h_div8: 0, height, ratio: 0, w_div8: 0, width, },
    metadata: @image.ImageMetadata::default(),
  }
  { ..@frame.FrameHeader::default(ih), width, height, group_size_shift: 0, }
}

///|
fn up_image(
  w : Int32,
  h : Int32,
  left : Int32,
  top : Int32,
  f : (Int32, Int32, Int32) -> Float,
) -> ImageWithRegion {
  let img = ImageWithRegion::new(3, None)
  for c in 0..<3 {
    let g = @grid.Grid::new(w, h, (0.0 : Float))
    for y in 0..<h {
      for x in 0..<w {
        g.set(x, y, f(x, y, c))
      }
    }
    img.append_channel(F32(g), { left, top, width: w, height: h, })
  }
  img
}

///|
fn up_hashes(img : ImageWithRegion) -> FixedArray[UInt64] {
  img.as_color_floats().map(up_hash_grid)
}

///|
test "gaborish matches upstream" {
  let weights : FixedArray[FixedArray[Float]] = [
    [0.115169525, 0.061248592],
    [0.2, 0.05],
    [0.0, 0.3],
  ]
  let cases : Array[(Int32, Int32, FixedArray[UInt64])] = [
    (9, 7, [5613800310561641015, 14655219304327587588, 17272966899317378047]),
    (1, 5, [1845651658589106563, 7509760391755586672, 17128649358972678488]),
    (6, 2, [7702873573555042501, 17865742638529903088, 12363304275333118413]),
    (1, 2, [1035515483453161, 1049369724860703, 1048804476730412]),
    (3, 1, [11458898058346762416, 1461306899124336022, 9769222496585939010]),
    (1, 1, [0, 1043641525, 1052030133]),
    (37, 20, [538877755156629830, 14229759926732870989, 3903228970787201746]),
  ]
  for case in cases {
    let (w, h, want) = case
    let img = up_image(w, h, 0, 0, (x, y, c) => {
      Float::from_int((x * 5 + y * 11 + c * 3) % 17) / 17.0
    })
    let scratch = FixedArray::makei(3, _ => @grid.Grid::new(w, h, (0.0 : Float)))
    apply_gabor_like(
      img,
      { left: 0, top: 0, width: w, height: h, },
      scratch,
      weights,
    )
    assert_eq(up_hashes(img), want)
  }
}

///|
test "epf matches upstream (SIMD and generic order)" {
  // run_epf_test uses the inputs of the upstream test; it follows the SIMD
  // order, as upstream on x86_64 (SSE4.1), aarch64 and wasm32+simd128.
  assert_eq(run_epf_test(1, true), [
    9944670924706631273, 4649029745901898151, 7918314164449885944,
  ])
  assert_eq(run_epf_test(2, true), [
    4418693226648462384, 4456375398648051019, 6006199015827296625,
  ])
  assert_eq(run_epf_test(3, true), [
    14925239348495727585, 3499181676583098699, 18377770737808784211,
  ])
  assert_eq(run_epf_test(1, false), [
    13712497948524980106, 8634539095060825182, 951363846857402003,
  ])
  assert_eq(run_epf_test(2, false), [
    10980923051587669156, 7079782726236506677, 18165877620793967372,
  ])
  assert_eq(run_epf_test(3, false), [
    7177867933567019613, 7698532665576061357, 16220332132719697667,
  ])
}

///|
test "noise matches upstream" {
  let fh = up_frame_header(257, 130)
  let img = up_image(40, 30, 5, 3, (x, y, c) => {
    Float::from_int((x * 7 + y * 13 + c * 29) % 61) / 64.0
  })
  let params : @frame.NoiseParameters = {
    lut: [0.0, 0.05, 0.1, 0.4, 0.2, 0.3, 0.6, 0.25],
  }
  render_noise(fh, 2, 1, Some((0.125, 0.875)), img, params)
  assert_eq(up_hashes(img), [
    12811748862706221817, 3743215537282052153, 10186817492766521742,
  ])
}

///|
test "upsampling matches upstream" {
  let wts = (n : Int32) => {
    FixedArray::makei(n, i => (Float::from_int((i * 7 + 3) % 19) - 6.0) / 64.0)
  }
  let base : @image.ImageHeader = {
    size: {
      div8: false,
      h_div8: 0,
      height: 64,
      ratio: 0,
      w_div8: 0,
      width: 64,
    },
    metadata: @image.ImageMetadata::default(),
  }
  let ih : @image.ImageHeader = {
    ..base,
    metadata: {
      ..base.metadata,
      up2_weight: wts(15),
      up4_weight: wts(55),
      up8_weight: wts(210),
    },
  }
  let g = @grid.Grid::new(5, 4, (0.0 : Float))
  for y in 0..<4 {
    for x in 0..<5 {
      g.set(x, y, Float::from_int((x * 3 + y * 7) % 11) / 10.0)
    }
  }
  let want : FixedArray[UInt64] = [
    11078104215879074466, 2752395298505153818, 12709158193156712394, 5213801376994147758,
  ]
  for factor in 1..<=4 {
    let region = Ref(({ left: 0, top: 0, width: 5, height: 4, } : Region))
    let out = upsample(g.as_subgrid(), region, ih, factor, None).unwrap()
    assert_eq(up_hash_grid(out), want[factor - 1])
    assert_eq(region.val, {
      left: 0,
      top: 0,
      width: 5 << factor,
      height: 4 << factor,
    })
  }
}

///|
test "splines match upstream" {
  let fh = up_frame_header(16, 8)
  let s1 : @frame.QuantSpline = {
    quant_points: [(2, 3), (12, 3)],
    manhattan_distance: 0,
    xyb_dct: FixedArray::makei(3, c => {
      FixedArray::makei(32, i => if i == 0 { 10 * (c + 1) } else { 0 })
    }),
    sigma_dct: FixedArray::makei(32, i => if i == 0 { 4 } else { 0 }),
  }
  let s2 : @frame.QuantSpline = {
    quant_points: [(1, 1), (10, 6), (14, 2), (3, 7)],
    manhattan_distance: 0,
    xyb_dct: FixedArray::makei(3, c => {
      FixedArray::makei(32, i => (i * 7 + c * 3) % 11 - 5)
    }),
    sigma_dct: FixedArray::makei(32, i => if i == 0 { 3 } else { i % 3 - 1 }),
  }
  let cases : Array[
    (
      @frame.Splines,
      (Float, Float)?,
      Int32,
      Int32,
      Int32,
      Int32,
      FixedArray[UInt64],
    ),
  ] = [
    (
      { quant_splines: [s1], quant_adjust: 0, },
      None,
      0,
      0,
      16,
      8,
      [6675643513601258171, 3044578343206008524, 3286102708174420167],
    ),
    (
      { quant_splines: [s1, s2], quant_adjust: 3, },
      Some((0.5, 1.0)),
      0,
      0,
      16,
      8,
      [17597677360052560830, 1470760319905763984, 16032155816516116367],
    ),
    (
      { quant_splines: [s2], quant_adjust: -5, },
      Some((0.25, 0.75)),
      4,
      1,
      6,
      4,
      [13678848446388562216, 17385004024668350331, 2594052657495335277],
    ),
  ]
  for case in cases {
    let (splines, corr, left, top, w, h, want) = case
    let img = up_image(w, h, left, top, (_, _, _) => 0.0)
    render_spline(fh, img, splines, corr)
    assert_eq(up_hashes(img), want)
  }
}
