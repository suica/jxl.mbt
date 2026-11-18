///|
/// A Modular encoded image.
///
/// Modular image decoding is done in two steps:
/// 1. Construct a value of `Modular` by either:
///    - reading a Modular header from the bitstream, or
///    - creating a subimage of existing image.
/// 2. Decode pixels.
///
/// Upstream's type parameter `S: Sample` is the `sample` argument of
/// `parse` (`Modular::<i16>::parse` is `Modular::parse(.., sample=I16)`).
pub struct Modular {
  priv inner : ModularImageDestination?
}

///|
pub fn Modular::parse(
  bs : @bitstream.Bitstream,
  params : ModularParams,
  sample~ : Sample = I32,
) -> Modular raise @bitstream.JxlError {
  let inner = if params.channels.is_empty() {
    None
  } else {
    let channels = ModularChannels::from_params(params)
    let (header, ma_ctx) = read_and_validate_local_modular_header(
      bs,
      channels,
      params.ma_config,
      params.tracker,
    )
    Some(
      ModularImageDestination::new(
        header,
        ma_ctx,
        params.group_dim,
        params.bit_depth,
        channels,
        params.tracker,
        sample,
      ),
    )
  }
  { inner, }
}

///|
/// Creates an empty Modular image.
pub fn Modular::empty() -> Modular {
  { inner: None, }
}

///|
pub fn Modular::try_clone(self : Modular) -> Modular raise @bitstream.JxlError {
  let inner = match self.inner {
    Some(image) => Some(image.try_clone())
    None => None
  }
  { inner, }
}

///|
pub fn Modular::has_palette(self : Modular) -> Bool {
  match self.inner {
    Some(image) => image.has_palette()
    None => false
  }
}

///|
pub fn Modular::has_squeeze(self : Modular) -> Bool {
  match self.inner {
    Some(image) => image.has_squeeze()
    None => false
  }
}

///|
pub fn Modular::image(self : Modular) -> ModularImageDestination? {
  self.inner
}

///|
/// Same as `image` (MoonBit values are shared references).
pub fn Modular::image_mut(self : Modular) -> ModularImageDestination? {
  self.inner
}

///|
pub fn Modular::into_image(self : Modular) -> ModularImageDestination? {
  self.inner
}

///|
priv struct ModularHeader {
  use_global_tree : Bool
  wp_params : WpHeader
  nb_transforms : Int32
  transform : Array[TransformInfo]
}

///|
fn ModularHeader::parse(
  bs : @bitstream.Bitstream,
) -> ModularHeader raise @bitstream.JxlError {
  let use_global_tree = bs.read_bool()
  let wp_params = WpHeader::parse(bs)
  let nb_transforms = bs
    .read_u32(
      @bitstream.c(0),
      @bitstream.c(1),
      @bitstream.cu(2, 4),
      @bitstream.cu(18, 8),
    )
    .reinterpret_as_int()
  let transform = []
  for _ in 0..<nb_transforms {
    transform.push(TransformInfo::parse(bs, wp_params))
  }
  { use_global_tree, wp_params, nb_transforms, transform, }
}

///|
priv struct ModularChannels {
  info : Array[ModularChannelInfo]
  mut nb_meta_channels : Int32
}

///|
fn ModularChannels::from_params(params : ModularParams) -> ModularChannels {
  let info = params.channels.map(fn(ch) {
    ModularChannelInfo::new(ch.width, ch.height, ch.shift)
  })
  { info, nb_meta_channels: 0, }
}

///|
fn ModularChannels::clone(self : ModularChannels) -> ModularChannels {
  { info: self.info.copy(), nb_meta_channels: self.nb_meta_channels, }
}

///|
/// Channel information. Values are immutable; transforms replace them.
#derive(Debug)
pub struct ModularChannelInfo {
  width : Int32
  height : Int32
  original_width : Int32
  original_height : Int32
  hshift : Int32
  vshift : Int32
  original_shift : ChannelShift
}

///|
fn ModularChannelInfo::new(
  original_width : Int32,
  original_height : Int32,
  shift : ChannelShift,
) -> ModularChannelInfo {
  let (width, height) = shift.shift_size((original_width, original_height))
  {
    width,
    height,
    original_width,
    original_height,
    hshift: shift.hshift(),
    vshift: shift.vshift(),
    original_shift: shift,
  }
}

///|
fn ModularChannelInfo::new_unshiftable(
  width : Int32,
  height : Int32,
) -> ModularChannelInfo {
  {
    width,
    height,
    original_width: width,
    original_height: height,
    hshift: -1,
    vshift: -1,
    original_shift: ChannelShift::from_shift(0),
  }
}

///|
pub fn ModularChannelInfo::shift(self : ModularChannelInfo) -> ChannelShift {
  self.original_shift
}

///|
pub fn ModularChannelInfo::original_size(
  self : ModularChannelInfo,
) -> (Int32, Int32) {
  (self.original_width, self.original_height)
}

///|
fn read_and_validate_local_modular_header(
  bs : @bitstream.Bitstream,
  channels : ModularChannels,
  global_ma_config : MaConfig?,
  tracker : @grid.AllocTracker?,
) -> (ModularHeader, MaConfig) raise @bitstream.JxlError {
  let header = ModularHeader::parse(bs)
  if header.nb_transforms > 512 {
    raise @bitstream.ProfileConformance("nb_transforms too large")
  }
  let tr_channels = channels.clone()
  for tr in header.transform {
    tr.prepare_transform_info(tr_channels)
  }
  let nb_channels_tr = tr_channels.info.length()
  if nb_channels_tr > 1 << 16 {
    raise @bitstream.ProfileConformance("nb_channels_tr too large")
  }
  let ma_ctx = if header.use_global_tree {
    match global_ma_config {
      Some(config) => config
      None => raise modular_error("GlobalMaTreeNotAvailable")
    }
  } else {
    let mut local_samples = 0UL
    for ch in tr_channels.info {
      local_samples = local_samples +
        ch.width.reinterpret_as_uint().to_uint64() *
        ch.height.reinterpret_as_uint().to_uint64()
    }
    let limit = 1024UL + local_samples
    let node_limit = if limit < 1UL << 20 { limit.to_int() } else { 1 << 20 }
    MaConfig::parse(bs, { tracker, node_limit, depth_limit: 2048, })
  }
  (header, ma_ctx)
}
