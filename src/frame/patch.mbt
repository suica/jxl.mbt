///|
#derive(Debug)
pub(all) struct Patches {
  patches : Array[PatchRef]
}

///|
#derive(Debug)
pub(all) struct PatchRef {
  ref_idx : Int32
  x0 : Int32
  y0 : Int32
  width : Int32
  height : Int32
  patch_targets : Array[PatchTarget]
}

///|
#derive(Debug)
pub(all) struct PatchTarget {
  x : Int32
  y : Int32
  blending : Array[BlendingModeInformation]
}

///|
#derive(Debug)
pub(all) struct BlendingModeInformation {
  mode : PatchBlendMode
  alpha_channel : Int32
  clamp : Bool
}

///|
#derive(Debug, Eq)
pub(all) enum PatchBlendMode {
  None
  Replace
  Add
  Mul
  BlendAbove
  BlendBelow
  MulAddAbove
  MulAddBelow
}

///|
pub fn PatchBlendMode::try_from(
  value : UInt32,
) -> PatchBlendMode raise @bitstream.JxlError {
  match value {
    0 => None
    1 => Replace
    2 => Add
    3 => Mul
    4 => BlendAbove
    5 => BlendBelow
    6 => MulAddAbove
    7 => MulAddBelow
    _ => raise InvalidEnum("PatchBlendMode", value)
  }
}

///|
pub fn PatchBlendMode::use_alpha(self : PatchBlendMode) -> Bool {
  self is (BlendAbove | BlendBelow | MulAddAbove | MulAddBelow)
}

///|
pub fn Patches::parse(
  bs : @bitstream.Bitstream,
  image_header : @image.ImageHeader,
  frame_header : FrameHeader,
) -> Patches raise @bitstream.JxlError {
  let num_extra = image_header.metadata.ec_info.length()
  let alpha_channel_indices : Array[UInt32] = []
  for idx, info in image_header.metadata.ec_info {
    if info.is_alpha() {
      alpha_channel_indices.push(idx.reinterpret_as_uint())
    }
  }
  let decoder = @coding.Decoder::parse(bs, 10)
  decoder.begin(bs)
  let frame_width = frame_header.width
  let frame_height = frame_header.height
  // `(1 << 24).min((w as u64 * h as u64 / 16) as u32)`
  let area_16 = (frame_width.to_uint64() * frame_height.to_uint64() / 16).to_uint()
  let max_num_patch_refs = if area_16 < 1U << 24 { area_16 } else { 1U << 24 }
  let max_num_patches = max_num_patch_refs * 4 // from libjxl limits
  let num_patch_refs = decoder.read_varint(bs, 0)
  if num_patch_refs > max_num_patch_refs {
    raise ProfileConformance("too many patches")
  }
  let mut total_patches = 0U
  let patches = []
  for _ in 0U..<num_patch_refs {
    let ref_idx = decoder.read_varint(bs, 1)
    if ref_idx >= 4 {
      raise ValidationFailed("PatchRef index out of bounds")
    }
    let x0 = decoder.read_varint(bs, 3)
    let y0 = decoder.read_varint(bs, 3)
    let width = decoder.read_varint(bs, 2) + 1
    let height = decoder.read_varint(bs, 2) + 1
    let count = decoder.read_varint(bs, 7) + 1
    // u32 addition; wraps as in upstream release builds.
    total_patches += count
    if total_patches > max_num_patches {
      raise ProfileConformance("too many patches")
    }
    let mut prev_xy : (Int32, Int32)? = None
    let patch_targets = []
    for _ in 0U..<count {
      let (x, y) = match prev_xy {
        Some((px, py)) => {
          let dx = decoder.read_varint(bs, 6)
          let dy = decoder.read_varint(bs, 6)
          let dx = @bitstream.unpack_signed(dx)
          let dy = @bitstream.unpack_signed(dy)
          let x = dx.to_int64() + px.to_int64()
          let y = dy.to_int64() + py.to_int64()
          if x < -2147483648L ||
            x > 2147483647L ||
            y < -2147483648L ||
            y > 2147483647L {
            raise ValidationFailed("patch coord overflow")
          }
          (x.to_int(), y.to_int())
        }
        None =>
          (
            decoder.read_varint(bs, 4).reinterpret_as_int(),
            decoder.read_varint(bs, 4).reinterpret_as_int(),
          )
      }
      prev_xy = Some((x, y))
      let blending = []
      for _ in 0..<(num_extra + 1) {
        let raw_mode = decoder.read_varint(bs, 5)
        let mode = PatchBlendMode::try_from(raw_mode)
        let alpha_channel = if raw_mode >= 4 &&
          alpha_channel_indices.length() >= 2 {
          decoder.read_varint(bs, 8)
        } else if alpha_channel_indices.is_empty() {
          0
        } else {
          alpha_channel_indices[0]
        }
        let clamp = if raw_mode >= 3 {
          decoder.read_varint(bs, 9) != 0
        } else {
          false
        }
        blending.push({
          mode,
          alpha_channel: alpha_channel.reinterpret_as_int(),
          clamp,
        })
      }
      patch_targets.push({ x, y, blending, })
    }
    patches.push({
      ref_idx: ref_idx.reinterpret_as_int(),
      x0: x0.reinterpret_as_int(),
      y0: y0.reinterpret_as_int(),
      width: width.reinterpret_as_int(),
      height: height.reinterpret_as_int(),
      patch_targets,
    })
  }
  decoder.finalize()
  { patches, }
}
