///|
/// Parameters for decoding a Modular image (jxl-modular `ModularParams`).
pub(all) struct ModularParams {
  group_dim : Int32
  bit_depth : Int32
  channels : Array[ModularChannelParams]
  ma_config : MaConfig?
  tracker : @grid.AllocTracker?
  mut narrow_buffer : Bool
}

///|
pub fn ModularParams::new(
  width : Int32,
  height : Int32,
  group_dim : Int32,
  bit_depth : Int32,
  channel_shifts : Array[ChannelShift],
  ma_config : MaConfig?,
  tracker : @grid.AllocTracker?,
) -> ModularParams {
  let channels = channel_shifts.map(fn(shift) { { width, height, shift, } })
  ModularParams::with_channels(
    group_dim, bit_depth, channels, ma_config, tracker,
  )
}

///|
pub fn ModularParams::with_channels(
  group_dim : Int32,
  bit_depth : Int32,
  channels : Array[ModularChannelParams],
  ma_config : MaConfig?,
  tracker : @grid.AllocTracker?,
) -> ModularParams {
  { group_dim, bit_depth, channels, ma_config, tracker, narrow_buffer: false, }
}

///|
#derive(Debug)
pub(all) struct ModularChannelParams {
  width : Int32
  height : Int32
  shift : ChannelShift
}

///|
pub fn ModularChannelParams::new(
  width : Int32,
  height : Int32,
) -> ModularChannelParams {
  { width, height, shift: ChannelShift::from_shift(0), }
}

///|
pub fn ModularChannelParams::jpeg(
  width : Int32,
  height : Int32,
  jpeg_upsampling : FixedArray[Int32],
  idx : Int32,
) -> ModularChannelParams {
  {
    width,
    height,
    shift: ChannelShift::from_jpeg_upsampling(jpeg_upsampling, idx),
  }
}

///|
pub fn ModularChannelParams::with_shift(
  width : Int32,
  height : Int32,
  shift : ChannelShift,
) -> ModularChannelParams {
  { width, height, shift, }
}

///|
#derive(Debug, Eq)
pub(all) enum ChannelShift {
  JpegUpsampling(
    has_h_subsample~ : Bool,
    h_subsample~ : Bool,
    has_v_subsample~ : Bool,
    v_subsample~ : Bool,
  )
  Shifts(Int32)
  Raw(Int32, Int32)
}

///|
pub fn ChannelShift::from_shift(shift : Int32) -> ChannelShift {
  Shifts(shift)
}

///|
pub fn ChannelShift::from_jpeg_upsampling(
  jpeg_upsampling : FixedArray[Int32],
  idx : Int32,
) -> ChannelShift {
  let upsampling = jpeg_upsampling[idx]
  let mut hscale = false
  let mut vscale = false
  for v in jpeg_upsampling {
    if v == 1 || v == 2 {
      hscale = true
    }
    if v == 1 || v == 3 {
      vscale = true
    }
  }
  let (h, v) = match upsampling {
    0 => (hscale, vscale)
    1 => (false, false)
    2 => (false, vscale)
    3 => (hscale, false)
    _ => abort("Invalid jpeg_upsampling value of \{upsampling}")
  }
  JpegUpsampling(
    has_h_subsample=hscale,
    h_subsample=h,
    has_v_subsample=vscale,
    v_subsample=v,
  )
}

///|
pub fn ChannelShift::hshift(self : ChannelShift) -> Int32 {
  match self {
    JpegUpsampling(h_subsample~, ..) => if h_subsample { 1 } else { 0 }
    Shifts(s) => s
    Raw(h, _) => h
  }
}

///|
pub fn ChannelShift::vshift(self : ChannelShift) -> Int32 {
  match self {
    JpegUpsampling(v_subsample~, ..) => if v_subsample { 1 } else { 0 }
    Shifts(s) => s
    Raw(_, v) => v
  }
}

///|
pub fn ChannelShift::shift_size(
  self : ChannelShift,
  size : (Int32, Int32),
) -> (Int32, Int32) {
  let (width, height) = size
  match self {
    JpegUpsampling(
      has_h_subsample~,
      has_v_subsample~,
      h_subsample~,
      v_subsample~,
    ) => {
      let width = if has_h_subsample {
        let size = div_ceil(width, 2)
        if h_subsample {
          size
        } else {
          size * 2
        }
      } else {
        width
      }
      let height = if has_v_subsample {
        let size = div_ceil(height, 2)
        if v_subsample {
          size
        } else {
          size * 2
        }
      } else {
        height
      }
      (width, height)
    }
    Shifts(s) => {
      let add = (1 << s) - 1
      (shr_u(width + add, s), shr_u(height + add, s))
    }
    Raw(h, v) => {
      let add_h = (1 << h) - 1
      let add_v = (1 << v) - 1
      (shr_u(width + add_h, h), shr_u(height + add_v, v))
    }
  }
}

///|
/// `u32::div_ceil` for non-negative `a` and positive `b`.
fn div_ceil(a : Int32, b : Int32) -> Int32 {
  let q = a / b
  if a % b != 0 {
    q + 1
  } else {
    q
  }
}

///|
/// Logical right shift (`u32 >> s`).
fn shr_u(a : Int32, s : Int32) -> Int32 {
  (a.reinterpret_as_uint() >> s).reinterpret_as_int()
}
