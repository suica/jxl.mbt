// Tests of the filter and feature ports. Reference values in
// filters_ref_data_wbtest.mbt come from an independent implementation of the
// same formulas (filters_ref_gen.py, numpy float32):
// `python3 filters_ref_gen.py > filters_ref_data_wbtest.mbt`.

///|
fn test_hash_subgrid(g : @grid.SubGrid[Float]) -> UInt64 {
  let mut h = 0UL
  for y in 0..<g.height {
    for x in 0..<g.width {
      h = h * 1000003UL + g.get(x, y).reinterpret_as_uint().to_uint64()
    }
  }
  h
}

///|
test "xorshift128+ output" {
  let rng = XorShift128Plus::new((3UL << 32) + 1UL, (256UL << 32) + 512UL)
  let bits = FixedArray::make(16, (0 : UInt32))
  rng.get_u32_bits(bits)
  for i in 0..<16 {
    assert_eq(bits[i], ref_rng_u32[i])
  }
  rng.get_u32_bits(bits)
  for i in 0..<16 {
    assert_eq(bits[i], ref_rng_u32[16 + i])
  }
}

///|
test "rng seeds" {
  assert_eq(rng_seed0(3, 1), (3UL << 32) + 1UL)
  assert_eq(rng_seed1(256, 512), (256UL << 32) + 512UL)
}

///|
test "noise convolution over groups" {
  let conv = init_noise(
    2,
    1,
    257,
    130,
    128,
    None,
    @threadpool.JxlThreadPool::none(),
  )
  assert_eq(test_hash_subgrid(conv[0].as_subgrid()), ref_noise_conv_hash_0)
  assert_eq(test_hash_subgrid(conv[1].as_subgrid()), ref_noise_conv_hash_1)
  assert_eq(test_hash_subgrid(conv[2].as_subgrid()), ref_noise_conv_hash_2)
}

///|
fn noise_test_img(x : Int32, y : Int32, c : Int32) -> Float {
  Float::from_int((x * 7 + y * 13 + c * 29) % 61) / 64.0
}

///|
test "render noise with lut" {
  let grids = Array::makei(3, fn(c) {
    let g = @grid.Grid::new(40, 30, (0.0 : Float))
    for y in 0..<30 {
      for x in 0..<40 {
        g.set(x, y, noise_test_img(x, y, c))
      }
    }
    g
  })
  let lut : FixedArray[Float] = [0.0, 0.05, 0.1, 0.4, 0.2, 0.3, 0.6, 0.25]
  let tracker = @grid.AllocTracker::with_limit(100000000L)
  render_noise_raw(
    257,
    130,
    128,
    2,
    1,
    Some((0.125, 0.875)),
    grids[0],
    grids[1],
    grids[2],
    5,
    3,
    40,
    30,
    lut,
    Some(tracker),
    @threadpool.JxlThreadPool::none(),
  )
  assert_eq(test_hash_subgrid(grids[0].as_subgrid()), ref_noise_render_hash_0)
  assert_eq(test_hash_subgrid(grids[1].as_subgrid()), ref_noise_render_hash_1)
  assert_eq(test_hash_subgrid(grids[2].as_subgrid()), ref_noise_render_hash_2)
  // every temporary buffer was returned to the tracker
  assert_eq(tracker.bytes_left, 100000000L)
}

///|
fn epf_test_in(x : Int32, y : Int32, c : Int32) -> Float {
  Float::from_int((x * x + 3 * y + 7 * c) % 13) / 4093.0
}

///|
fn epf_test_sigma(bx : Int32, by : Int32) -> Float {
  Float::from_int((bx * 3 + by * 5) % 7) * 0.1 + 0.25
}

///|
fn run_epf_test(
  iters : Int32,
  use_grid : Bool,
) -> FixedArray[UInt64] raise Error {
  let w = 21
  let h = 19
  // colour planes are views into larger buffers, at (2, 1)
  let fb = FixedArray::makei(3, fn(c) {
    let big = @grid.Grid::new(w + 5, h + 3, (-1.0 : Float))
    let sub = big.as_subgrid().subgrid(2, 1, w, h)
    for y in 0..<h {
      for x in 0..<w {
        sub.set(x, y, epf_test_in(x, y, c))
      }
    }
    sub
  })
  let scratch = FixedArray::makei(3, fn(_) {
    @grid.Grid::new(w, h, (0.0 : Float))
  })
  let sigma_grid = @grid.Grid::new(8, 8, (0.0 : Float))
  for by in 0..<8 {
    for bx in 0..<8 {
      sigma_grid.set(bx, by, epf_test_sigma(bx, by))
    }
  }
  let params : @frame.EpfParams = {
    iters,
    sharp_lut: FixedArray::make(8, 0.0),
    channel_scale: [40.0, 5.0, 3.5],
    sigma: {
      quant_mul: 0.46,
      pass0_sigma_scale: 0.9,
      pass2_sigma_scale: 6.5,
      border_sad_mul: (2.0 : Float) / 3.0,
    },
    sigma_for_modular: 1.0,
  }
  let in_scratch = apply_epf_views(
    fb,
    scratch,
    { left: 8, top: 16, width: w, height: h, },
    128,
    1,
    [if use_grid { Some(sigma_grid) } else { None }],
    params,
    @threadpool.JxlThreadPool::none(),
  )
  assert_eq(in_scratch, iters == 1 || iters == 3)
  FixedArray::makei(3, fn(c) {
    if in_scratch {
      test_hash_subgrid(scratch[c].as_subgrid())
    } else {
      test_hash_subgrid(fb[c])
    }
  })
}

///|
test "epf matches reference (sigma grid)" {
  assert_eq(run_epf_test(1, true), ref_epf_grid_1)
  assert_eq(run_epf_test(2, true), ref_epf_grid_2)
  assert_eq(run_epf_test(3, true), ref_epf_grid_3)
}

///|
test "epf matches reference (modular sigma)" {
  assert_eq(run_epf_test(1, false), ref_epf_modular_1)
  assert_eq(run_epf_test(2, false), ref_epf_modular_2)
  assert_eq(run_epf_test(3, false), ref_epf_modular_3)
}

///|
test "util mirror" {
  assert_eq(mirror(-1, 5), 0)
  assert_eq(mirror(-3, 5), 2)
  assert_eq(mirror(5, 5), 4)
  assert_eq(mirror(7, 5), 2)
  assert_eq(mirror(2, 1), 0)
  assert_eq(mirror(-2, 1), 0)
}

///|
/// Gaborish written directly from the convolution formula, with mirrored
/// edges.
fn gabor_reference(
  input : @grid.Grid[Float],
  w0 : Float,
  w1 : Float,
) -> @grid.Grid[Float] {
  let w = input.width
  let h = input.height
  let out = @grid.Grid::new(w, h, (0.0 : Float))
  let at = fn(x : Int32, y : Int32) { input.get(mirror(x, w), mirror(y, h)) }
  for y in 0..<h {
    for x in 0..<w {
      let side = at(x, y - 1) + at(x - 1, y) + at(x + 1, y) + at(x, y + 1)
      let diag = at(x - 1, y - 1) +
        at(x + 1, y - 1) +
        at(x - 1, y + 1) +
        at(x + 1, y + 1)
      let v = (at(x, y) + side * w0 + diag * w1) / (1.0 + w0 * 4.0 + w1 * 4.0)
      out.set(x, y, v)
    }
  }
  out
}

///|
fn gabor_test_case(w : Int32, h : Int32) -> Unit raise Error {
  let weights : FixedArray[FixedArray[Float]] = [
    [0.115169525, 0.061248592],
    [0.2, 0.05],
    [0.0, 0.3],
  ]
  let inputs = Array::makei(3, fn(c) {
    let g = @grid.Grid::new(w, h, (0.0 : Float))
    for y in 0..<h {
      for x in 0..<w {
        g.set(x, y, Float::from_int((x * 5 + y * 11 + c * 3) % 17) / 16.0)
      }
    }
    g
  })
  let scratch = Array::makei(3, fn(_) { @grid.Grid::new(w, h, (0.0 : Float)) })
  impls_apply_gabor_like(
    FixedArray::makei(3, c => inputs[c].as_subgrid()),
    FixedArray::makei(3, c => scratch[c]),
    weights,
    @threadpool.JxlThreadPool::none(),
  )
  for c in 0..<3 {
    let r = gabor_reference(inputs[c], weights[c][0], weights[c][1])
    for y in 0..<h {
      for x in 0..<w {
        let d = (r.get(x, y) - scratch[c].get(x, y)).abs()
        if d > 1.0e-6 {
          fail(
            "gabor \{w}x\{h} c=\{c} (\{x},\{y}): \{scratch[c].get(x, y)} vs \{r.get(x, y)}",
          )
        }
      }
    }
  }
}

///|
test "gabor matches reference" {
  gabor_test_case(9, 7)
  gabor_test_case(1, 5)
  gabor_test_case(6, 2)
  gabor_test_case(1, 2)
}

///|
test "gabor single row follows upstream" {
  // Upstream's single-row path uses `1.0 + 2.0 + w0` as the centre weight,
  // which is not the mirrored convolution; keep upstream's numbers.
  let w0 : Float = 0.2
  let w1 : Float = 0.05
  let input = @grid.Grid::from_buf(3, 1, ([1.0, 2.0, 4.0] : FixedArray[Float]))
  let out = @grid.Grid::new(3, 1, (0.0 : Float))
  impls_apply_gabor_like(
    [input.as_subgrid(), input.as_subgrid(), input.as_subgrid()],
    [out, @grid.Grid::new(3, 1, 0.0), @grid.Grid::new(3, 1, 0.0)],
    [[w0, w1], [w0, w1], [w0, w1]],
    @threadpool.JxlThreadPool::none(),
  )
  let gw : Float = 1.0 / (1.0 + w0 * 4.0 + w1 * 4.0)
  let mw0 : Float = 1.0 + 2.0 + w0
  let mw1 : Float = w0 + 2.0 * w1
  assert_eq(out.get(1, 0), ((2.0 : Float) * mw0 + (1.0 + 4.0) * mw1) * gw)
  assert_eq(out.get(0, 0), ((1.0 : Float) * (mw0 + mw1) + 2.0 * mw1) * gw)
  // a 1x1 image is copied
  let one = @grid.Grid::from_buf(1, 1, ([3.5] : FixedArray[Float]))
  let out1 = @grid.Grid::new(1, 1, (0.0 : Float))
  impls_apply_gabor_like(
    [one.as_subgrid(), one.as_subgrid(), one.as_subgrid()],
    [out1, @grid.Grid::new(1, 1, 0.0), @grid.Grid::new(1, 1, 0.0)],
    [[w0, w1], [w0, w1], [w0, w1]],
    @threadpool.JxlThreadPool::none(),
  )
  assert_eq(out1.get(0, 0), 3.5)
}

///|
/// Non-separable upsampling from the spec formula: the weight matrix is the
/// symmetric 5N x 5N matrix whose upper triangle is listed row by row; every
/// output pixel mirrors the kernel of its quadrant.
fn upsample_reference(
  input : @grid.Grid[Float],
  k : Int32,
  weights : FixedArray[Float],
) -> @grid.Grid[Float] {
  let n = k / 2
  let dim = 5 * n
  let mat = FixedArray::make(dim * dim, (0.0 : Float))
  let mut idx = 0
  for r in 0..<dim {
    for c in r..<dim {
      mat[r * dim + c] = weights[idx]
      mat[c * dim + r] = weights[idx]
      idx += 1
    }
  }
  let w = input.width
  let h = input.height
  let out = @grid.Grid::new(w * k, h * k, (0.0 : Float))
  for y in 0..<(h * k) {
    for x in 0..<(w * k) {
      let sy = y % k
      let sx = x % k
      let my = if sy < n { sy } else { k - 1 - sy }
      let mx = if sx < n { sx } else { k - 1 - sx }
      let mut sum : Float = 0.0
      let mut lo : Float = @float.infinity
      let mut hi : Float = @float.neg_infinity
      for iy in 0..<5 {
        for ix in 0..<5 {
          let ky = if sy < n { iy } else { 4 - iy }
          let kx = if sx < n { ix } else { 4 - ix }
          let v = input.get(
            mirror(x / k + ix - 2, w),
            mirror(y / k + iy - 2, h),
          )
          sum = sum + mat[(my * 5 + ky) * dim + mx * 5 + kx] * v
          lo = lo.min(v)
          hi = hi.max(v)
        }
      }
      out.set(x, y, sum.clamp(min=lo, max=hi))
    }
  }
  out
}

///|
fn upsample_test_weights(n : Int32) -> FixedArray[Float] {
  FixedArray::makei(n, fn(i) { Float::from_int((i * 7 + 3) % 19 - 6) / 64.0 })
}

///|
test "upsampling 2x/4x/8x matches reference" {
  let w = 5
  let h = 4
  let input = @grid.Grid::new(w, h, (0.0 : Float))
  for y in 0..<h {
    for x in 0..<w {
      input.set(x, y, Float::from_int((x * 3 + y * 7) % 11) / 10.0)
    }
  }
  let up2 = upsample_test_weights(15)
  let up4 = upsample_test_weights(55)
  let up8 = upsample_test_weights(210)
  let tracker = @grid.AllocTracker::with_limit(10000000L)
  for factor in 1..<=3 {
    let (k, wts) = match factor {
      1 => (2, up2)
      2 => (4, up4)
      _ => (8, up8)
    }
    let got = upsample_raw(
      input.as_subgrid(),
      up2,
      up4,
      up8,
      factor,
      Some(tracker),
    ).unwrap()
    let want = upsample_reference(input, k, wts)
    assert_eq(got.width, w * k)
    assert_eq(got.height, h * k)
    for i in 0..<(got.width * got.height) {
      assert_eq(got.buf[i], want.buf[i])
    }
  }
  // factor 0 does nothing; factor 4 is 8x then 2x
  assert_true(upsample_raw(input.as_subgrid(), up2, up4, up8, 0, None) is None)
  let got = upsample_raw(input.as_subgrid(), up2, up4, up8, 4, None).unwrap()
  let want = upsample_reference(upsample_reference(input, 8, up8), 2, up2)
  assert_eq(got.width, w * 16)
  for i in 0..<(got.width * got.height) {
    assert_eq(got.buf[i], want.buf[i])
  }
}

///|
test "upsampling keeps NaN when all samples are NaN" {
  let input = @grid.Grid::new(2, 2, @float.not_a_number)
  let up2 = upsample_test_weights(15)
  let got = upsample_raw(input.as_subgrid(), up2, up2, up2, 1, None).unwrap()
  assert_true(got.get(1, 1).is_nan())
}

///|
test "jpeg chroma upsampling" {
  // 3x2 samples, upsampled horizontally and vertically to 5x4
  let g = @grid.Grid::from_buf(
    3,
    2,
    ([0.0, 4.0, 8.0, 16.0, 20.0, 24.0] : FixedArray[Float]),
  )
  let out = apply_jpeg_upsampling_single_raw(g.as_subgrid(), 1, 1, 5, 4, None)
  // horizontal pass, row 0: [0, 1, 3, 5, 7] (row 1 adds 16)
  // vertical pass: top row = 0.75 * r0 + 0.25 * r0, then 0.25 * r1 + 0.75 * r0 ...
  let r0 : FixedArray[Float] = [0.0, 1.0, 3.0, 5.0, 7.0]
  let r1 : FixedArray[Float] = [16.0, 17.0, 19.0, 21.0, 23.0]
  for x in 0..<5 {
    assert_eq(out.get(x, 0), 0.75 * r0[x] + 0.25 * r0[x])
    assert_eq(out.get(x, 1), 0.25 * r1[x] + 0.75 * r0[x])
    assert_eq(out.get(x, 2), 0.75 * r1[x] + 0.25 * r0[x])
    assert_eq(out.get(x, 3), 0.25 * r1[x] + 0.75 * r1[x])
  }
  // only horizontal (vshift 0); hshift 0 copies
  let out_h = apply_jpeg_upsampling_single_raw(g.as_subgrid(), 1, 0, 6, 2, None)
  let want : FixedArray[Float] = [0.0, 1.0, 3.0, 5.0, 7.0, 8.0]
  for x in 0..<6 {
    assert_eq(out_h.get(x, 0), want[x])
  }
  let out_c = apply_jpeg_upsampling_single_raw(g.as_subgrid(), 0, 0, 3, 2, None)
  assert_eq(out_c.buf, g.buf)
}

///|
test "spot colour" {
  let chans = Array::makei(3, fn(c) {
    @grid.Grid::from_buf(
      2,
      1,
      ([Float::from_int(c) * 0.25, 1.0] : FixedArray[Float]),
    )
  })
  let ec = @grid.Grid::from_buf(2, 1, ([1.0, 0.5] : FixedArray[Float]))
  render_spot_color_raw(chans, ec, 1.0, 0.5, 0.0, 0.5)
  // mix = s * solidity; out = mix * colour + (1 - mix) * in
  assert_eq(chans[0].get(0, 0), 0.5 * 1.0 + 0.5 * 0.0)
  assert_eq(chans[1].get(0, 0), 0.5 * 0.5 + 0.5 * 0.25)
  assert_eq(chans[2].get(1, 0), 0.25 * 0.0 + 0.75 * 1.0)
}

///|
test "spline erf" {
  assert_eq(spline_erf(0.0), 0.0)
  assert_true((spline_erf(1.0) - 0.8427008).abs() < 7.0e-4)
  assert_true((spline_erf(-0.5) + 0.5204999).abs() < 7.0e-4)
  assert_true((spline_erf(3.0) - 0.9999779).abs() < 7.0e-4)
}

///|
test "spline arc length sampling" {
  // A straight horizontal spline of length 10 gives 11 unit samples and a
  // final partial arc.
  let spline : Spline = {
    points: [SplinePoint::new(0.0, 0.0), SplinePoint::new(10.0, 0.0)],
    xyb_dct: FixedArray::makei(3, fn(_) { FixedArray::make(32, 0.0) }),
    sigma_dct: FixedArray::make(32, 0.0),
  }
  let up = spline.get_upsampled_points()
  assert_eq(up.length(), 17)
  for i, p in up {
    assert_true((p.x - Float::from_int(i) * 10.0 / 16.0).abs() < 1.0e-4)
    assert_eq(p.y, 0.0)
  }
  let samples = spline.get_samples()
  // first sample, then one sample per unit length, then the rest
  assert_true(samples.length() >= 11 && samples.length() <= 12)
  for i in 0..<11 {
    assert_true((samples[i].point.x - Float::from_int(i)).abs() < 1.0e-4)
  }
  // single point spline
  let one : Spline = { ..spline, points: [SplinePoint::new(3.0, 4.0)], }
  let s1 = one.get_samples()
  assert_eq(s1.length(), 2)
  assert_eq(s1[1].length, 0.0)
}

///|
test "spline dequant and render" {
  let xyb = FixedArray::makei(3, fn(c) {
    FixedArray::makei(32, fn(i) { if i == 0 { 10 * (c + 1) } else { 0 } })
  })
  let sigma = FixedArray::makei(32, fn(i) { if i == 0 { 4 } else { 0 } })
  let spline = Spline::dequant(
    [(2L, 3L), (12L, 3L)],
    xyb,
    sigma,
    0,
    Some((0.5, 1.0)),
  )
  // dequantized: X = 10 * 0.0042 + 0.5 * Y, Y = 20 * 0.075, B = 30 * 0.07 + Y
  assert_eq(spline.xyb_dct[1][0], (20.0 : Float) * 0.075 * 1.0)
  assert_eq(
    spline.xyb_dct[0][0],
    (10.0 : Float) * 0.0042 * 1.0 + 0.5 * spline.xyb_dct[1][0],
  )
  assert_eq(spline.sigma_dct[0], (4.0 : Float) * 0.3333 * 1.0)
  // quant_adjust < 0 scales up
  let s2 = Spline::dequant([(0L, 0L)], xyb, sigma, -8, None)
  assert_eq(s2.xyb_dct[1][0], (20.0 : Float) * 0.075 * 2.0)
  let chans = Array::makei(3, fn(_) { @grid.Grid::new(16, 8, (0.0 : Float)) })
  render_spline_raw(
    16,
    8,
    chans,
    0,
    0,
    [(2L, 3L), (12L, 3L)],
    xyb,
    sigma,
    0,
    None,
  )
  // the spline is brightest along its path and symmetric around y = 3
  let on = chans[1].get(7, 3)
  assert_true(on > 0.0)
  assert_true(on > chans[1].get(7, 5))
  assert_eq(chans[1].get(7, 2), chans[1].get(7, 4))
  // rendering with a region offset touches the same frame pixels
  let part = Array::makei(3, fn(_) { @grid.Grid::new(6, 4, (0.0 : Float)) })
  render_spline_raw(
    16,
    8,
    part,
    4,
    1,
    [(2L, 3L), (12L, 3L)],
    xyb,
    sigma,
    0,
    None,
  )
  assert_eq(part[1].get(3, 2), on)
}
