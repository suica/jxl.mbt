// End-to-end checks of the jxl-vardct bundles on real VarDCT frames: the
// sections (LfGlobal, LfGroup 0, HfGlobal, pass 0 of group 0) are decoded with
// this package (plus the few LfGlobal fields owned by jxl-frame) and compared
// with values dumped from jxl-oxide (`sections_*_wbtest.mbt` are generated).

///|
priv struct SectionRef {
  lf_global_end : Int32
  lf_group_start : Int32
  lf_group_end : Int32
  hf_global_start : Int32
  hf_global_end : Int32
  pass_group_start : Int32
  pass_group_end : Int32
  node_limit : Int32
  bits_per_sample : Int32
  lf_width : Int32
  lf_height : Int32
  jpeg_upsampling : FixedArray[Int32]
  epf : (Float, FixedArray[Float])?
  num_groups : Int32
  num_lf_groups : Int32
  group_dim : Int32
  num_passes : Int32
  coeff_shift : Int32
  lf_dequant : FixedArray[UInt32]
  quantizer : (Int32, Int32)
  num_block_clusters : Int32
  block_ctx_map_hash : UInt32
  qf_thresholds : Array[Int32]
  lf_thresholds : Array[Array[Int32]]
  lf_chan_corr : (Int32, UInt32, UInt32, Int32, Int32)
  has_global_tree : Bool
  extra_precision : Int32
  lf_quant_hashes : FixedArray[UInt32]
  x_from_y_hash : UInt32
  b_from_y_hash : UInt32
  block_info_hash : UInt32
  epf_sigma_hash : UInt32
  dequant_hash : UInt32
  num_hf_presets : Int32
  hf_coeff_hashes : FixedArray[UInt32]
  block_w : Int32
  block_h : Int32
}

///|
fn hex_to_bytes(s : String) -> Bytes {
  let digits = []
  for ch in s {
    let v = match ch {
      '0'..<='9' => ch.to_int() - '0'.to_int()
      'a'..<='f' => ch.to_int() - 'a'.to_int() + 10
      _ => continue
    }
    digits.push(v)
  }
  Bytes::makei(digits.length() / 2, i => {
    (digits[2 * i] * 16 + digits[2 * i + 1]).to_byte()
  })
}

///|
fn hash_ints(v : FixedArray[Int32]) -> UInt32 {
  let mut h = 2166136261U
  for x in v {
    h = h ^ x.reinterpret_as_uint()
    h = h * 16777619U
  }
  h
}

///|
fn check_sections(
  lf_global : Bytes,
  lf_group : Bytes,
  hf_global : Bytes,
  pass_group : Bytes,
  r : SectionRef,
) -> Unit raise {
  // LfGlobal (no patches, splines or noise in the test frames)
  let bs = @bitstream.Bitstream::new(lf_global)
  let lf_dequant = LfChannelDequantization::parse(bs)
  assert_eq(lf_dequant.m_x_lf.reinterpret_as_uint(), r.lf_dequant[0])
  assert_eq(lf_dequant.m_y_lf.reinterpret_as_uint(), r.lf_dequant[1])
  assert_eq(lf_dequant.m_b_lf.reinterpret_as_uint(), r.lf_dequant[2])
  let quantizer = Quantizer::parse(bs)
  assert_eq((quantizer.global_scale, quantizer.quant_lf), r.quantizer)
  let hf_block_ctx = HfBlockContext::parse(bs)
  assert_eq(hf_block_ctx.num_block_clusters, r.num_block_clusters)
  assert_eq(hash_ints(hf_block_ctx.block_ctx_map), r.block_ctx_map_hash)
  assert_eq(hf_block_ctx.qf_thresholds, r.qf_thresholds)
  for c in 0..<3 {
    assert_eq(hf_block_ctx.lf_thresholds[c], r.lf_thresholds[c])
  }
  let cc = LfChannelCorrelation::parse(bs)
  assert_eq(
    (
      cc.colour_factor,
      cc.base_correlation_x.reinterpret_as_uint(),
      cc.base_correlation_b.reinterpret_as_uint(),
      cc.x_factor_lf,
      cc.b_factor_lf,
    ),
    r.lf_chan_corr,
  )
  let ma = if bs.read_bool() {
    Some(
      @modular.MaConfig::parse(bs, {
        tracker: None,
        node_limit: r.node_limit,
        depth_limit: 2048,
      }),
    )
  } else {
    None
  }
  assert_eq(ma is Some(_), r.has_global_tree)
  assert_eq(bs.num_read_bits(), r.lf_global_end)

  // LfGroup 0
  let bs = @bitstream.Bitstream::new(lf_group)
  bs.skip_bits(r.lf_group_start)
  let lf_coeff = LfCoeff::parse(bs, {
    lf_group_idx: 0,
    lf_width: r.lf_width,
    lf_height: r.lf_height,
    jpeg_upsampling: r.jpeg_upsampling,
    bits_per_sample: r.bits_per_sample,
    global_ma_config: ma,
    allow_partial: false,
    tracker: None,
  })
  assert_eq(lf_coeff.extra_precision, r.extra_precision)
  assert_eq(lf_coeff.partial, false)
  let lf_quant_channels = lf_coeff.lf_quant.image().unwrap().image_channels()
  for c in 0..<3 {
    assert_eq(hash_ints(lf_quant_channels[c].buf()), r.lf_quant_hashes[c])
  }
  let hf_meta = HfMetadata::parse(bs, {
    num_lf_groups: r.num_lf_groups,
    lf_group_idx: 0,
    lf_width: r.lf_width,
    lf_height: r.lf_height,
    jpeg_upsampling: r.jpeg_upsampling,
    bits_per_sample: r.bits_per_sample,
    global_ma_config: ma,
    epf: r.epf,
    quantizer_global_scale: quantizer.global_scale,
    tracker: None,
  })
  assert_eq(bs.num_read_bits(), r.lf_group_end)
  assert_eq(hash_ints(hf_meta.x_from_y.buf()), r.x_from_y_hash)
  assert_eq(hash_ints(hf_meta.b_from_y.buf()), r.b_from_y_hash)
  let bi = hf_meta.block_info
    .buf()
    .map(b => {
      match b {
        Uninit => -1
        Occupied => -2
        Data(dct_select~, hf_mul~) => dct_select.to_int() * 65536 + hf_mul
      }
    })
  assert_eq(hash_ints(bi), r.block_info_hash)
  assert_eq(hash_floats(hf_meta.epf_sigma.buf()), r.epf_sigma_hash)

  // HfGlobal
  let bs = @bitstream.Bitstream::new(hf_global)
  bs.skip_bits(r.hf_global_start)
  let dequant_matrices = DequantMatrixSet::parse(
    bs,
    DequantMatrixSetParams::new(r.bits_per_sample, r.num_lf_groups, ma, None),
  )
  let mut dq = 2166136261U
  for ty in dct_select_list {
    for c in 0..<3 {
      dq = dq ^ hash_floats(dequant_matrices.get(c, ty))
      dq = dq * 16777619U
    }
  }
  assert_eq(dq, r.dequant_hash)
  let num_hf_presets = bs
    .read_bits(ceil_log2(r.num_groups))
    .reinterpret_as_int() +
    1
  assert_eq(num_hf_presets, r.num_hf_presets)
  let hf_passes = Array::makei(r.num_passes, _ => {
    HfPass::parse(bs, HfPassParams::new(hf_block_ctx, num_hf_presets))
  })
  assert_eq(bs.num_read_bits(), r.hf_global_end)

  // Pass 0 of group 0
  assert_true(r.block_w <= r.group_dim / 8 && r.block_h <= r.group_dim / 8)
  let bs = @bitstream.Bitstream::new(pass_group)
  bs.skip_bits(r.pass_group_start)
  let block_info = hf_meta.block_info
    .as_subgrid()
    .subgrid(0, 0, r.block_w, r.block_h)
  let shifts = FixedArray::makei(3, idx => {
    @modular.ChannelShift::from_jpeg_upsampling(r.jpeg_upsampling, idx)
  })
  let channel_map : FixedArray[Int32] = [1, 0, 2]
  let lf_quant = FixedArray::makei(3, idx => {
    let (w, h) = shifts[idx].shift_size((r.block_w, r.block_h))
    lf_quant_channels[channel_map[idx]].as_subgrid().subgrid(0, 0, w, h)
  })
  let grids = FixedArray::makei(3, idx => {
    let (w, h) = shifts[idx].shift_size((r.block_w, r.block_h))
    @grid.Grid::new(w * 8, h * 8, 0)
  })
  write_hf_coeff(
    bs,
    {
      num_hf_presets,
      hf_block_ctx,
      block_info,
      jpeg_upsampling: r.jpeg_upsampling,
      lf_quant: Some(lf_quant),
      hf_pass: hf_passes[0],
      coeff_shift: r.coeff_shift,
      tracker: None,
    },
    FixedArray::makei(3, c => grids[c].as_subgrid()),
  )
  assert_eq(bs.num_read_bits(), r.pass_group_end)
  for c in 0..<3 {
    assert_eq(
      hash_ints(grids[c].buf()),
      r.hf_coeff_hashes[c],
      msg="channel \{c}",
    )
  }
}
