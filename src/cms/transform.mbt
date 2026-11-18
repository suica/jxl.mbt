// Public transform API: an ICC-to-ICC float transform equivalent to
// lcms2's `cmsCreateTransform(src, FLT, dst, FLT, intent, cmsFLAGS_NOCACHE)`
// with channel-count-only pixel formats, which is how jxl-oxide drives
// Little CMS 2 (`jxl-oxide/src/lcms2.rs`).

///|
/// A prepared colour transform between two ICC profiles.
pub struct Transform {
  priv lut : Pipeline
  /// Number of input channels (of the source profile's colour space).
  num_input_channels : Int32
  /// Number of output channels (of the destination profile's colour space).
  num_output_channels : Int32
  priv buf_in : FixedArray[Float]
  priv buf_out : FixedArray[Float]
  priv buf0 : FixedArray[Float]
  priv buf1 : FixedArray[Float]
  priv scratch : EvalScratch
}

///|
/// Creates a transform from `src` to `dst` with the given intent. Black
/// point compensation is not requested (lcms2 still forces it for v4
/// profiles with perceptual or saturation intents, as here).
pub fn Transform::new(
  src : Profile,
  dst : Profile,
  intent : RenderingIntent,
) -> Transform raise @bitstream.JxlError {
  let code = intent.code()
  let (lut, entry, exit) = create_pipeline([Icc(src), Icc(dst)], [code, code], [
    false, false,
  ])
  let num_input_channels = channels_of_color_space(entry)
  let num_output_channels = channels_of_color_space(exit)
  let zero = Float::from_double(0.0)
  {
    lut,
    num_input_channels,
    num_output_channels,
    buf_in: FixedArray::make(MAX_STAGE_CHANNELS, zero),
    buf_out: FixedArray::make(MAX_STAGE_CHANNELS, zero),
    buf0: FixedArray::make(MAX_STAGE_CHANNELS, zero),
    buf1: FixedArray::make(MAX_STAGE_CHANNELS, zero),
    scratch: EvalScratch::new(),
  }
}

///|
/// Creates a transform from raw ICC profile bytes.
pub fn Transform::from_icc(
  src : Bytes,
  dst : Bytes,
  intent : RenderingIntent,
) -> Transform raise @bitstream.JxlError {
  Transform::new(Profile::parse(src), Profile::parse(dst), intent)
}

///|
/// Transforms one pixel: `input` holds `num_input_channels` values, the
/// result is written to the first `num_output_channels` values of `output`.
pub fn Transform::transform_pixel(
  self : Transform,
  input : FixedArray[Float],
  output : FixedArray[Float],
) -> Unit {
  self.lut.eval_float(input, output, self.buf0, self.buf1, self.scratch)
}

///|
/// Transforms `num_pixels` interleaved pixels from `input` to `output`.
pub fn Transform::transform_interleaved(
  self : Transform,
  input : FixedArray[Float],
  output : FixedArray[Float],
  num_pixels : Int32,
) -> Unit {
  let nin = self.num_input_channels
  let nout = self.num_output_channels
  for i in 0..<num_pixels {
    for c in 0..<nin {
      self.buf_in[c] = input[i * nin + c]
    }
    self.lut.eval_float(
      self.buf_in,
      self.buf_out,
      self.buf0,
      self.buf1,
      self.scratch,
    )
    for c in 0..<nout {
      output[i * nout + c] = self.buf_out[c]
    }
  }
}

///|
/// Transforms planar channels in place, like jxl-oxide's
/// `PreparedTransform::transform`: reads the first `num_input_channels`
/// planes and writes the first `num_output_channels` planes. The number of
/// samples is the minimum length of the given planes.
pub fn Transform::transform_planar(
  self : Transform,
  channels : Array[FixedArray[Float]],
) -> Unit {
  let nin = self.num_input_channels
  let nout = self.num_output_channels
  let mut len = -1
  for ch in channels {
    if len < 0 || ch.length() < len {
      len = ch.length()
    }
  }
  if len <= 0 {
    return
  }
  for i in 0..<len {
    for c in 0..<nin {
      self.buf_in[c] = channels[c][i]
    }
    self.lut.eval_float(
      self.buf_in,
      self.buf_out,
      self.buf0,
      self.buf1,
      self.scratch,
    )
    for c in 0..<nout {
      channels[c][i] = self.buf_out[c]
    }
  }
}

///|
/// Transforms samples `start..start + len` of planar channels in place (the
/// `@color.PreparedTransform::transform` contract).
pub fn Transform::transform_planar_range(
  self : Transform,
  channels : Array[FixedArray[Float]],
  start : Int32,
  len : Int32,
) -> Unit {
  let nin = self.num_input_channels
  let nout = self.num_output_channels
  for i in start..<(start + len) {
    for c in 0..<nin {
      self.buf_in[c] = channels[c][i]
    }
    self.lut.eval_float(
      self.buf_in,
      self.buf_out,
      self.buf0,
      self.buf1,
      self.scratch,
    )
    for c in 0..<nout {
      channels[c][i] = self.buf_out[c]
    }
  }
}
