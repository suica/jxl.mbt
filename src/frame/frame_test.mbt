///|
/// LSB-first bit writer for crafting test bitstreams.
priv struct BitWriter {
  bytes : Array[Byte]
  mut cur : Int32
  mut nbits : Int32
}

///|
fn BitWriter::new() -> BitWriter {
  { bytes: [], cur: 0, nbits: 0, }
}

///|
fn BitWriter::put(self : BitWriter, value : Int32, n : Int32) -> BitWriter {
  for i in 0..<n {
    self.cur = self.cur | (((value >> i) & 1) << self.nbits)
    self.nbits += 1
    if self.nbits == 8 {
      self.bytes.push(self.cur.to_byte())
      self.cur = 0
      self.nbits = 0
    }
  }
  self
}

///|
fn BitWriter::finish(self : BitWriter) -> @bitstream.Bitstream {
  if self.nbits > 0 {
    self.bytes.push(self.cur.to_byte())
  }
  // Padding so that over-reads show up as wrong values rather than EOF.
  for _ in 0..<8 {
    self.bytes.push(0)
  }
  @bitstream.Bitstream::new(Bytes::from_array(self.bytes))
}

///|
fn image_header(width : Int32, height : Int32) -> @image.ImageHeader {
  // SizeHeader's div8/ratio fields are private (as upstream); set width/height only.
  let size = @image.SizeHeader::default()
  size.width = width
  size.height = height
  { size, metadata: @image.ImageMetadata::default(), }
}

///|
test "all-default frame header" {
  let ih = image_header(1000, 600)
  let h = @frame.FrameHeader::default(ih)
  assert_true(h.all_default)
  assert_true(h.frame_type == RegularFrame)
  assert_true(h.encoding == VarDct)
  assert_true(h.is_last)
  assert_true(h.is_keyframe())
  assert_true(h.resets_canvas)
  assert_false(h.save_before_ct)
  assert_eq(h.width, 1000)
  assert_eq(h.height, 600)
  assert_eq(h.upsampling, 1)
  assert_eq(h.group_size_shift, 1)
  assert_eq(h.group_dim(), 256)
  assert_eq(h.num_groups(), 4 * 3)
  assert_eq(h.num_lf_groups(), 1)
  assert_eq(h.groups_per_row(), 4)
  assert_eq(h.group_size_for(3), (1000 - 768, 256))
  assert_eq(h.group_size_for(11), (1000 - 768, 600 - 512))
  assert_eq(h.lf_group_size_for(0), (1000, 600))
  assert_eq(h.lf_group_idx_from_group_idx(11), 0)
  assert_eq(h.group_idx_from_coord(999, 599), Some(11))
  assert_eq(h.group_idx_from_coord(1024, 0), None)
  assert_true(h.is_group_collides_region(5, (300, 300, 10, 10)))
  assert_false(h.is_group_collides_region(0, (300, 300, 10, 10)))
  assert_eq(h.encoded_color_channels(), 3)
  // xyb_encoded is true by default, VarDCT → x_qm_scale default 3.
  assert_eq(h.x_qm_scale, 3)
  assert_eq(h.b_qm_scale, 2)
  assert_true(h.restoration_filter.gab.enabled())
  assert_true(h.restoration_filter.epf.enabled())
  assert_eq(h.passes.num_passes, 1)
  assert_eq(h.ec_blending_info.length(), 0)
}

///|
test "filter defaults" {
  guard @frame.Gabor::default() is Enabled(w) else { fail("gabor") }
  assert_eq(w[2][0], 0.115169525)
  assert_eq(w[1][1], 0.061248592)
  guard @frame.EdgePreservingFilter::default() is Enabled(p) else {
    fail("epf")
  }
  assert_eq(p.iters, 2)
  assert_eq(p.sharp_lut[1], (1.0 : Float) / 7.0)
  assert_eq(p.sharp_lut[7], 1.0)
  assert_eq(p.channel_scale[2], 3.5)
  assert_eq(p.sigma.quant_mul, 0.46)
  assert_eq(p.sigma.border_sad_mul, (2.0 : Float) / 3.0)
}

///|
test "restoration filter parse" {
  // all_default = 0, gab_enabled = 0, epf iters = 0, extensions = 0 (U64 selector 0).
  let bs = BitWriter::new().put(0, 1).put(0, 1).put(0, 2).put(0, 2).finish()
  let rf = @frame.RestorationFilter::parse(bs, Modular)
  assert_false(rf.gab.enabled())
  assert_false(rf.epf.enabled())
  assert_eq(bs.num_read_bits(), 6)
  // Modular EPF: iters=1, weight_custom=0, sigma_custom=0, sigma_for_modular f16(1.5)=0x3e00
  let bs = BitWriter::new()
    .put(1, 2)
    .put(0, 1)
    .put(0, 1)
    .put(0x3e00, 16)
    .finish()
  guard @frame.EdgePreservingFilter::parse(bs, Modular) is Enabled(p) else {
    fail("epf")
  }
  assert_eq(p.iters, 1)
  assert_eq(p.sigma_for_modular, 1.5)
  assert_eq(p.sigma.quant_mul, 0.46)
}

///|
test "blend mode and passes" {
  // U32(0, 1, 2, 3 + u(2)): selector 3, value 1 → 4 = Mul
  let bs = BitWriter::new().put(3, 2).put(1, 2).finish()
  assert_true(@frame.BlendMode::parse(bs) == Mul)
  let bs = BitWriter::new().put(3, 2).put(2, 2).finish()
  let r = try {
    @frame.BlendMode::parse(bs) |> ignore
    None
  } catch {
    e => Some(e)
  }
  assert_true(r is Some(InvalidEnum("BlendMode", 5)))
  // num_passes = 2 (selector 1), num_ds = 1 (selector 1), shift[0] = 2,
  // downsample[0] = 4 (selector 2), last_pass[0] = 0 (selector 0)
  let bs = BitWriter::new()
    .put(1, 2)
    .put(1, 2)
    .put(2, 2)
    .put(2, 2)
    .put(0, 2)
    .finish()
  let p = @frame.Passes::parse(bs)
  assert_eq(p.num_passes, 2)
  assert_eq(p.num_ds, 1)
  assert_eq(p.shift, [2])
  assert_eq(p.downsample, [4])
  assert_eq(p.last_pass, [0])
}

///|
test "toc group kind ordering" {
  let kinds : Array[@frame.TocGroupKind] = [
    GroupPass(pass_idx=1, group_idx=0),
    HfGlobal,
    GroupPass(pass_idx=0, group_idx=5),
    LfGroup(2),
    All,
    LfGroup(0),
    LfGlobal,
  ]
  kinds.sort()
  inspect(
    kinds.map(k => "\{k}").join(", "),
    content="All, LfGlobal, LfGroup(0), LfGroup(2), HfGlobal, GroupPass { pass_idx: 0, group_idx: 5 }, GroupPass { pass_idx: 1, group_idx: 0 }",
  )
}

///|
test "toc parse single entry" {
  let h = @frame.FrameHeader::default(image_header(100, 100))
  // permutated = 0, pad to byte, size U32 selector 0 u(10) = 123, pad.
  let bs = BitWriter::new().put(0, 1).put(0, 7).put(0, 2).put(123, 10).finish()
  let toc = @frame.Toc::parse(bs, h)
  assert_true(toc.is_single_entry())
  assert_eq(toc.total_byte_size(), 123)
  assert_eq(toc.bookmark(), 3)
  assert_eq(toc.group_index_bitstream_order(All), 0)
  let groups = toc.iter_bitstream_order()
  assert_eq(groups.length(), 1)
  assert_true(groups[0].kind == All)
}

///|
test "toc parse multi entry" {
  // 300x100 → 2 groups of 256, 1 LF group: entries = 1 + 1 + 1 + 2 = 5.
  let h = @frame.FrameHeader::default(image_header(300, 100))
  let w = BitWriter::new().put(0, 1).put(0, 7)
  for s in [10, 20, 30, 40, 50] {
    w.put(0, 2).put(s, 10) |> ignore
  }
  let bs = w.finish()
  let toc = @frame.Toc::parse(bs, h)
  assert_false(toc.is_single_entry())
  assert_eq(toc.total_byte_size(), 150)
  let groups = toc.iter_bitstream_order()
  inspect(
    groups.map(g => "\{g.kind}@\{g.offset}+\{g.size}").join(", "),
    content="LfGlobal@9+10, LfGroup(0)@19+20, HfGlobal@39+30, GroupPass { pass_idx: 0, group_idx: 0 }@69+40, GroupPass { pass_idx: 0, group_idx: 1 }@109+50",
  )
  assert_eq(
    toc.group_index_bitstream_order(GroupPass(pass_idx=0, group_idx=1)),
    4,
  )
}

///|
test "noise parameters" {
  let w = BitWriter::new()
  for i in 0..<8 {
    w.put(i * 128, 10) |> ignore
  }
  let noise = @frame.NoiseParameters::parse(w.finish())
  assert_eq(noise.lut[0], 0.0)
  assert_eq(noise.lut[4], 0.5)
  assert_eq(noise.lut[7], 0.875)
}
