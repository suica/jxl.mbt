///|
test "TransformType round-trips and rejects invalid values" {
  for v in 0..<27 {
    assert_eq(@vardct.TransformType::try_from(v).to_int(), v)
  }
  try @vardct.TransformType::try_from(27) catch {
    e => assert_eq(e, @bitstream.InvalidEnum("TransformType", 27))
  } noraise {
    _ => fail("expected InvalidEnum")
  }
  assert_eq(@vardct.TransformType::Dct16x8.dct_select_size(), (1, 2))
  assert_true(@vardct.TransformType::Dct16x8.need_transpose())
  assert_false(@vardct.TransformType::Dct8x16.need_transpose())
  assert_true(@vardct.TransformType::Dct16.need_transpose())
  assert_false(@vardct.TransformType::Afv2.need_transpose())
}

///|
test "DCT8 natural order" {
  let order = @vardct.dct8_natural_order
  assert_eq(order.length(), 64)
  debug_inspect(
    order[0:8].to_owned(),
    content=(
      #|[(0, 0), (1, 0), (0, 1), (0, 2), (1, 1), (2, 0), (3, 0), (2, 1)]
    ),
  )
  assert_eq(order[63], (7, 7))
}

///|
test "default bundles" {
  let bs = @bitstream.Bitstream::new(b"\xff\xff\xff\xff\xff\xff\xff\xff")
  let lf_dequant = @vardct.LfChannelDequantization::parse(bs)
  assert_eq(lf_dequant.m_x_lf, 1.0 / 32.0)
  assert_eq(lf_dequant.m_x_lf_unscaled(), 1.0 / 32.0 / 128.0)
  let cc = @vardct.LfChannelCorrelation::parse(bs)
  assert_eq(cc.colour_factor, 84)
  assert_eq(cc.base_correlation_b, 1.0)
  let ctx = @vardct.HfBlockContext::parse(bs)
  assert_eq(ctx.num_block_clusters, 15)
  assert_eq(ctx.block_ctx_map.length(), 39)
  assert_eq(bs.num_read_bits(), 3)
}
