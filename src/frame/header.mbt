///|
/// Frame header.
#derive(Debug)
pub struct FrameHeader {
  priv all_default : Bool
  frame_type : FrameType
  encoding : Encoding
  flags : FrameFlags
  do_ycbcr : Bool
  priv encoded_color_channels : Int32
  jpeg_upsampling : FixedArray[Int32]
  upsampling : Int32
  ec_upsampling : Array[Int32]
  group_size_shift : Int32
  x_qm_scale : Int32
  b_qm_scale : Int32
  passes : Passes
  lf_level : Int32
  have_crop : Bool
  x0 : Int32
  y0 : Int32
  width : Int32
  height : Int32
  blending_info : BlendingInfo
  ec_blending_info : Array[BlendingInfo]
  duration : UInt32
  timecode : UInt32
  is_last : Bool
  save_as_reference : Int32
  resets_canvas : Bool
  save_before_ct : Bool
  name : String
  restoration_filter : RestorationFilter
  extensions : @image.Extensions
  bit_depth : @image.BitDepth
}

///|
#derive(Debug)
pub(all) struct Passes {
  num_passes : Int32
  num_ds : Int32
  shift : Array[Int32]
  downsample : Array[Int32]
  last_pass : Array[Int32]
}

///|
#derive(Debug)
pub(all) struct BlendingInfo {
  mode : BlendMode
  alpha_channel : Int32
  clamp : Bool
  source : Int32
}

///|
#derive(Debug)
pub struct RestorationFilter {
  priv all_default : Bool
  gab : Gabor
  epf : EdgePreservingFilter
  extensions : @image.Extensions
}

///|
priv struct CanvasSizeParams {
  have_crop : Bool
  x0 : Int32
  y0 : Int32
  width : Int32
  height : Int32
  size : @image.SizeHeader
}

///|
fn read_u32_int(
  bs : @bitstream.Bitstream,
  a : @bitstream.U32Spec,
  b : @bitstream.U32Spec,
  c : @bitstream.U32Spec,
  d : @bitstream.U32Spec,
) -> Int32 raise @bitstream.JxlError {
  bs.read_u32(a, b, c, d).reinterpret_as_int()
}

///|
fn read_upsampling(
  bs : @bitstream.Bitstream,
) -> Int32 raise @bitstream.JxlError {
  read_u32_int(
    bs,
    @bitstream.c(1),
    @bitstream.c(2),
    @bitstream.c(4),
    @bitstream.c(8),
  )
}

///|
fn read_crop_u32(bs : @bitstream.Bitstream) -> UInt32 raise @bitstream.JxlError {
  bs.read_u32(
    @bitstream.u(8),
    @bitstream.cu(256, 11),
    @bitstream.cu(2304, 14),
    @bitstream.cu(18688, 30),
  )
}

///|
pub fn FrameHeader::parse(
  bs : @bitstream.Bitstream,
  headers : @image.ImageHeader,
) -> FrameHeader raise @bitstream.JxlError {
  let metadata = headers.metadata
  let num_ec = metadata.ec_info.length()
  let all_default = bs.read_bool()
  let frame_type = if !all_default {
    FrameType::parse(bs)
  } else {
    RegularFrame
  }
  let encoding = if !all_default { Encoding::parse(bs) } else { VarDct }
  let flags = if !all_default { FrameFlags::parse(bs) } else { FrameFlags(0) }
  let do_ycbcr = if !all_default && !metadata.xyb_encoded {
    bs.read_bool()
  } else {
    false
  }
  let encoded_color_channels = {
    let acutally_grayscale = encoding == Modular &&
      !do_ycbcr &&
      !metadata.xyb_encoded &&
      metadata.grayscale()
    if acutally_grayscale {
      1
    } else {
      3
    }
  }
  let jpeg_upsampling = FixedArray::make(3, 0)
  if do_ycbcr && !flags.use_lf_frame() {
    for i in 0..<3 {
      jpeg_upsampling[i] = bs.read_bits_int(2)
    }
  }
  let upsampling = if !all_default && !flags.use_lf_frame() {
    read_upsampling(bs)
  } else {
    1
  }
  let ec_upsampling = if !all_default && !flags.use_lf_frame() {
    let v = []
    for _ in 0..<num_ec {
      v.push(read_upsampling(bs))
    }
    v
  } else {
    Array::make(num_ec, 1)
  }
  let group_size_shift = if encoding == Modular {
    bs.read_bits_int(2)
  } else {
    1
  }
  let x_qm_scale = if !all_default && metadata.xyb_encoded && encoding == VarDct {
    bs.read_bits_int(3)
  } else {
    FrameHeader::compute_default_xqms(encoding, metadata.xyb_encoded)
  }
  let b_qm_scale = if !all_default && metadata.xyb_encoded && encoding == VarDct {
    bs.read_bits_int(3)
  } else {
    2
  }
  let passes = if !all_default && frame_type != ReferenceOnly {
    Passes::parse(bs)
  } else {
    Passes::default()
  }
  let lf_level = if frame_type == LfFrame { 1 + bs.read_bits_int(2) } else { 0 }
  let have_crop = if !all_default && frame_type != LfFrame {
    bs.read_bool()
  } else {
    false
  }
  let x0 = if have_crop && frame_type != ReferenceOnly {
    @bitstream.unpack_signed(read_crop_u32(bs))
  } else {
    0
  }
  let y0 = if have_crop && frame_type != ReferenceOnly {
    @bitstream.unpack_signed(read_crop_u32(bs))
  } else {
    0
  }
  let width = if have_crop {
    read_crop_u32(bs).reinterpret_as_int()
  } else {
    headers.size.width
  }
  let height = if have_crop {
    read_crop_u32(bs).reinterpret_as_int()
  } else {
    headers.size.height
  }
  let canvas = { have_crop, x0, y0, width, height, size: headers.size, }
  let has_ec = num_ec != 0
  let blending_info = if !all_default && frame_type.is_normal_frame() {
    BlendingInfo::parse(bs, has_ec, None, canvas)
  } else {
    BlendingInfo::default()
  }
  let ec_blending_info = if !all_default && frame_type.is_normal_frame() {
    let v = []
    for _ in 0..<num_ec {
      v.push(BlendingInfo::parse(bs, has_ec, Some(blending_info.mode), canvas))
    }
    v
  } else {
    []
  }
  let duration = if !all_default &&
    frame_type.is_normal_frame() &&
    metadata.animation is Some(_) {
    bs.read_u32(
      @bitstream.c(0),
      @bitstream.c(1),
      @bitstream.u(8),
      @bitstream.u(32),
    )
  } else {
    0
  }
  let have_timecodes = match metadata.animation {
    Some(a) => a.have_timecodes
    None => false
  }
  let timecode = if !all_default &&
    frame_type.is_normal_frame() &&
    have_timecodes {
    bs.read_bits(32)
  } else {
    0
  }
  let is_last = if !all_default && frame_type.is_normal_frame() {
    bs.read_bool()
  } else {
    frame_type == RegularFrame
  }
  let save_as_reference = if !all_default && frame_type != LfFrame && !is_last {
    bs.read_bits_int(2)
  } else {
    0
  }
  let resets_canvas = FrameHeader::resets_canvas_(blending_info.mode, canvas)
  let save_before_ct = if !all_default &&
    (
      frame_type == ReferenceOnly ||
      (
        resets_canvas &&
        !is_last &&
        (duration == 0 || save_as_reference != 0) &&
        frame_type != LfFrame
      )
    ) {
    bs.read_bool()
  } else {
    !frame_type.is_normal_frame()
  }
  let name = if !all_default { @bitstream.read_name(bs) } else { "" }
  let restoration_filter = if !all_default {
    RestorationFilter::parse(bs, encoding)
  } else {
    RestorationFilter::default()
  }
  let extensions = if !all_default {
    @image.Extensions::parse(bs)
  } else {
    @image.Extensions::default()
  }
  let bit_depth = metadata.bit_depth
  {
    all_default,
    frame_type,
    encoding,
    flags,
    do_ycbcr,
    encoded_color_channels,
    jpeg_upsampling,
    upsampling,
    ec_upsampling,
    group_size_shift,
    x_qm_scale,
    b_qm_scale,
    passes,
    lf_level,
    have_crop,
    x0,
    y0,
    width,
    height,
    blending_info,
    ec_blending_info,
    duration,
    timecode,
    is_last,
    save_as_reference,
    resets_canvas,
    save_before_ct,
    name,
    restoration_filter,
    extensions,
    bit_depth,
  }
}

///|
/// `FrameHeader::default_with_context(headers)`: the header of an all-default frame.
pub fn FrameHeader::default(headers : @image.ImageHeader) -> FrameHeader {
  FrameHeader::parse(@bitstream.Bitstream::new(b"\xff"), headers) catch {
    _ => abort("all_default frame header cannot fail")
  }
}

///|
pub fn Passes::default() -> Passes {
  { num_passes: 1, num_ds: 0, shift: [], downsample: [], last_pass: [], }
}

///|
pub fn Passes::parse(
  bs : @bitstream.Bitstream,
) -> Passes raise @bitstream.JxlError {
  let num_passes = read_u32_int(
    bs,
    @bitstream.c(1),
    @bitstream.c(2),
    @bitstream.c(3),
    @bitstream.cu(4, 3),
  )
  let num_ds = if num_passes != 1 {
    read_u32_int(
      bs,
      @bitstream.c(0),
      @bitstream.c(1),
      @bitstream.c(2),
      @bitstream.cu(3, 1),
    )
  } else {
    0
  }
  let shift = []
  let downsample = []
  let last_pass = []
  if num_passes != 1 {
    for _ in 0..<(num_passes - 1) {
      shift.push(bs.read_bits_int(2))
    }
    for _ in 0..<num_ds {
      downsample.push(read_upsampling(bs))
    }
    for _ in 0..<num_ds {
      last_pass.push(
        read_u32_int(
          bs,
          @bitstream.c(0),
          @bitstream.c(1),
          @bitstream.c(2),
          @bitstream.u(3),
        ),
      )
    }
  } else {
    // `vec![0; num_passes - 1]` etc. with num_passes == 1, num_ds == 0.
    ()
  }
  { num_passes, num_ds, shift, downsample, last_pass, }
}

///|
pub fn BlendingInfo::default() -> BlendingInfo {
  { mode: Replace, alpha_channel: 0, clamp: false, source: 0, }
}

///|
fn BlendingInfo::parse(
  bs : @bitstream.Bitstream,
  has_ec : Bool,
  base_mode : BlendMode?,
  canvas : CanvasSizeParams,
) -> BlendingInfo raise @bitstream.JxlError {
  let mode = BlendMode::parse(bs)
  let alpha_channel = if has_ec && (mode == Blend || mode == MulAdd) {
    read_u32_int(
      bs,
      @bitstream.c(0),
      @bitstream.c(1),
      @bitstream.c(2),
      @bitstream.cu(3, 3),
    )
  } else {
    0
  }
  let clamp = if (has_ec && (mode == Blend || mode == MulAdd)) || mode == Mul {
    bs.read_bool()
  } else {
    false
  }
  let mode_for_reset = match base_mode {
    Some(m) => m
    None => mode
  }
  let source = if !FrameHeader::resets_canvas_(mode_for_reset, canvas) {
    bs.read_bits_int(2)
  } else {
    0
  }
  { mode, alpha_channel, clamp, source, }
}

///|
pub fn RestorationFilter::default() -> RestorationFilter {
  {
    all_default: true,
    gab: Gabor::default(),
    epf: EdgePreservingFilter::default(),
    extensions: @image.Extensions::default(),
  }
}

///|
pub fn RestorationFilter::parse(
  bs : @bitstream.Bitstream,
  encoding : Encoding,
) -> RestorationFilter raise @bitstream.JxlError {
  let all_default = bs.read_bool()
  let gab = if !all_default { Gabor::parse(bs) } else { Gabor::default() }
  let epf = if !all_default {
    EdgePreservingFilter::parse(bs, encoding)
  } else {
    EdgePreservingFilter::default()
  }
  let extensions = if !all_default {
    @image.Extensions::parse(bs)
  } else {
    @image.Extensions::default()
  }
  { all_default, gab, epf, extensions, }
}

///|
fn FrameHeader::test_full_image(canvas_size : CanvasSizeParams) -> Bool {
  let { x0, y0, width, height, size, .. } = canvas_size
  if x0 > 0 || y0 > 0 {
    return false
  }
  let right = x0.to_int64() + width.to_int64()
  let bottom = y0.to_int64() + height.to_int64()
  right >= size.width.to_int64() && bottom >= size.height.to_int64()
}

///|
fn FrameHeader::resets_canvas_(
  blending_mode : BlendMode,
  canvas_size : CanvasSizeParams,
) -> Bool {
  blending_mode == Replace &&
  (!canvas_size.have_crop || FrameHeader::test_full_image(canvas_size))
}

///|
fn FrameHeader::compute_default_xqms(
  encoding : Encoding,
  xyb_encoded : Bool,
) -> Int32 {
  if xyb_encoded && encoding == VarDct {
    3
  } else {
    2
  }
}

///|
/// Returns whether this frame is a keyframe that should be displayed.
pub fn FrameHeader::is_keyframe(self : FrameHeader) -> Bool {
  self.frame_type.is_normal_frame() && (self.is_last || self.duration != 0)
}

///|
pub fn FrameHeader::can_reference(self : FrameHeader) -> Bool {
  !self.is_last &&
  (self.duration == 0 || self.save_as_reference != 0) &&
  self.frame_type != LfFrame
}

///|
fn div_ceil(a : Int32, b : Int32) -> Int32 {
  // Unsigned semantics: operands are non-negative u32 values in upstream.
  ((a.reinterpret_as_uint() + b.reinterpret_as_uint() - 1) /
  b.reinterpret_as_uint()).reinterpret_as_int()
}

///|
pub fn FrameHeader::sample_width(
  self : FrameHeader,
  upsampling : Int32,
) -> Int32 {
  let mut width = self.width
  let lf_level = self.lf_level
  if upsampling > 1 {
    width = div_ceil(width, upsampling)
  }
  if lf_level > 0 {
    let div = 1 << (3 * lf_level)
    width = (width + div - 1) >> (3 * lf_level)
  }
  width
}

///|
pub fn FrameHeader::sample_height(
  self : FrameHeader,
  upsampling : Int32,
) -> Int32 {
  let mut height = self.height
  let lf_level = self.lf_level
  if upsampling > 1 {
    height = div_ceil(height, upsampling)
  }
  if lf_level > 0 {
    let div = 1 << (3 * lf_level)
    height = (height + div - 1) >> (3 * lf_level)
  }
  height
}

///|
pub fn FrameHeader::color_sample_width(self : FrameHeader) -> Int32 {
  self.sample_width(self.upsampling)
}

///|
pub fn FrameHeader::color_sample_height(self : FrameHeader) -> Int32 {
  self.sample_height(self.upsampling)
}

///|
/// Returns the number of channels actually encoded in the frame.
pub fn FrameHeader::encoded_color_channels(self : FrameHeader) -> Int32 {
  self.encoded_color_channels
}

///|
pub fn FrameHeader::num_groups(self : FrameHeader) -> Int32 {
  let width = self.color_sample_width()
  let height = self.color_sample_height()
  let group_dim = self.group_dim()
  let hgroups = div_ceil(width, group_dim)
  let vgroups = div_ceil(height, group_dim)
  hgroups * vgroups
}

///|
pub fn FrameHeader::num_lf_groups(self : FrameHeader) -> Int32 {
  let width = self.color_sample_width()
  let height = self.color_sample_height()
  let lf_group_dim = self.lf_group_dim()
  let hgroups = div_ceil(width, lf_group_dim)
  let vgroups = div_ceil(height, lf_group_dim)
  hgroups * vgroups
}

///|
pub fn FrameHeader::group_dim(self : FrameHeader) -> Int32 {
  128 << self.group_size_shift
}

///|
pub fn FrameHeader::groups_per_row(self : FrameHeader) -> Int32 {
  div_ceil(self.color_sample_width(), self.group_dim())
}

///|
pub fn FrameHeader::lf_group_dim(self : FrameHeader) -> Int32 {
  self.group_dim() * 8
}

///|
pub fn FrameHeader::lf_groups_per_row(self : FrameHeader) -> Int32 {
  div_ceil(self.color_sample_width(), self.lf_group_dim())
}

///|
pub fn FrameHeader::group_size_for(
  self : FrameHeader,
  group_idx : Int32,
) -> (Int32, Int32) {
  self.size_for(self.group_dim(), group_idx)
}

///|
pub fn FrameHeader::lf_group_size_for(
  self : FrameHeader,
  lf_group_idx : Int32,
) -> (Int32, Int32) {
  self.size_for(self.lf_group_dim(), lf_group_idx)
}

///|
fn FrameHeader::size_for(
  self : FrameHeader,
  group_dim : Int32,
  group_idx : Int32,
) -> (Int32, Int32) {
  let width = self.color_sample_width()
  let height = self.color_sample_height()
  let full_rows = height / group_dim
  let rows_remainder = height % group_dim
  let full_cols = width / group_dim
  let cols_remainder = width % group_dim
  let stride = full_cols + (if cols_remainder > 0 { 1 } else { 0 })
  let row = group_idx / stride
  let col = group_idx % stride
  let group_width = if col >= full_cols { cols_remainder } else { group_dim }
  let group_height = if row >= full_rows { rows_remainder } else { group_dim }
  (group_width, group_height)
}

///|
pub fn FrameHeader::lf_group_idx_from_group_idx(
  self : FrameHeader,
  group_idx : Int32,
) -> Int32 {
  let groups_per_row = self.groups_per_row()
  let lf_group_col = group_idx % groups_per_row / 8
  let lf_group_row = group_idx / groups_per_row / 8
  lf_group_col + lf_group_row * self.lf_groups_per_row()
}

///|
pub fn FrameHeader::group_idx_from_coord(
  self : FrameHeader,
  x : Int32,
  y : Int32,
) -> Int32? {
  let shift = 7 + self.group_size_shift
  let group_x = x.reinterpret_as_uint() >> shift
  let group_y = y.reinterpret_as_uint() >> shift
  let groups_per_row = self.groups_per_row().reinterpret_as_uint()
  let group_idx = group_y * groups_per_row + group_x
  if group_x >= groups_per_row ||
    group_idx >= self.num_groups().reinterpret_as_uint() {
    None
  } else {
    Some(group_idx.reinterpret_as_int())
  }
}

///|
pub fn FrameHeader::is_group_collides_region(
  self : FrameHeader,
  group_idx : Int32,
  region : (Int32, Int32, Int32, Int32),
) -> Bool {
  let group_dim = self.group_dim()
  let group_per_row = self.groups_per_row()
  let group_left = group_idx % group_per_row * group_dim
  let group_top = group_idx / group_per_row * group_dim
  is_aabb_collides(region, (group_left, group_top, group_dim, group_dim))
}

///|
pub fn FrameHeader::is_lf_group_collides_region(
  self : FrameHeader,
  lf_group_idx : Int32,
  region : (Int32, Int32, Int32, Int32),
) -> Bool {
  let lf_group_dim = self.lf_group_dim()
  let lf_group_per_row = self.lf_groups_per_row()
  let group_left = lf_group_idx % lf_group_per_row * lf_group_dim
  let group_top = lf_group_idx / lf_group_per_row * lf_group_dim
  is_aabb_collides(region, (group_left, group_top, lf_group_dim, lf_group_dim))
}

///|
#derive(Eq, Debug)
pub(all) enum FrameType {
  RegularFrame
  LfFrame
  ReferenceOnly
  SkipProgressive
}

///|
pub fn FrameType::default() -> FrameType {
  RegularFrame
}

///|
pub fn FrameType::parse(
  bs : @bitstream.Bitstream,
) -> FrameType raise @bitstream.JxlError {
  match bs.read_bits(2) {
    0 => RegularFrame
    1 => LfFrame
    2 => ReferenceOnly
    _ => SkipProgressive
  }
}

///|
pub fn FrameType::is_normal_frame(self : FrameType) -> Bool {
  self is (RegularFrame | SkipProgressive)
}

///|
pub fn FrameType::is_progressive_frame(self : FrameType) -> Bool {
  self is (RegularFrame | LfFrame)
}

///|
#derive(Eq, Debug)
pub(all) enum Encoding {
  VarDct
  Modular
}

///|
pub fn Encoding::default() -> Encoding {
  VarDct
}

///|
pub fn Encoding::parse(
  bs : @bitstream.Bitstream,
) -> Encoding raise @bitstream.JxlError {
  if bs.read_bits(1) == 0 {
    VarDct
  } else {
    Modular
  }
}

///|
#derive(Eq, Debug)
pub(all) struct FrameFlags(UInt64)

///|
let flag_noise : UInt64 = 0x1

///|
let flag_patches : UInt64 = 0x2

///|
let flag_splines : UInt64 = 0x10

///|
let flag_use_lf_frame : UInt64 = 0x20

///|
let flag_skip_adaptive_lf_smoothing : UInt64 = 0x80

///|
pub fn FrameFlags::noise(self : FrameFlags) -> Bool {
  (self.0 & flag_noise) != 0
}

///|
pub fn FrameFlags::patches(self : FrameFlags) -> Bool {
  (self.0 & flag_patches) != 0
}

///|
pub fn FrameFlags::splines(self : FrameFlags) -> Bool {
  (self.0 & flag_splines) != 0
}

///|
pub fn FrameFlags::use_lf_frame(self : FrameFlags) -> Bool {
  (self.0 & flag_use_lf_frame) != 0
}

///|
pub fn FrameFlags::skip_adaptive_lf_smoothing(self : FrameFlags) -> Bool {
  (self.0 & flag_skip_adaptive_lf_smoothing) != 0
}

///|
pub fn FrameFlags::parse(
  bs : @bitstream.Bitstream,
) -> FrameFlags raise @bitstream.JxlError {
  FrameFlags(bs.read_u64())
}

///|
#derive(Eq, Debug)
pub(all) enum BlendMode {
  Replace
  Add
  Blend
  MulAdd
  Mul
}

///|
pub fn BlendMode::default() -> BlendMode {
  Replace
}

///|
pub fn BlendMode::parse(
  bs : @bitstream.Bitstream,
) -> BlendMode raise @bitstream.JxlError {
  match
    bs.read_u32(
      @bitstream.c(0),
      @bitstream.c(1),
      @bitstream.c(2),
      @bitstream.cu(3, 2),
    ) {
    0 => Replace
    1 => Add
    2 => Blend
    3 => MulAdd
    4 => Mul
    value => raise InvalidEnum("BlendMode", value)
  }
}

///|
pub fn BlendMode::use_alpha(self : BlendMode) -> Bool {
  self is (Blend | MulAdd)
}

///|
fn is_aabb_collides(
  rect0 : (Int32, Int32, Int32, Int32),
  rect1 : (Int32, Int32, Int32, Int32),
) -> Bool {
  let (x0, y0, w0, h0) = rect0
  let (x1, y1, w1, h1) = rect1
  // u32 arithmetic in upstream.
  let x0 = x0.reinterpret_as_uint()
  let y0 = y0.reinterpret_as_uint()
  let w0 = w0.reinterpret_as_uint()
  let h0 = h0.reinterpret_as_uint()
  let x1 = x1.reinterpret_as_uint()
  let y1 = y1.reinterpret_as_uint()
  let w1 = w1.reinterpret_as_uint()
  let h1 = h1.reinterpret_as_uint()
  x0 < x1 + w1 && x0 + w0 > x1 && y0 < y1 + h1 && y0 + h0 > y1
}
