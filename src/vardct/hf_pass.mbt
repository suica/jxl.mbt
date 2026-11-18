// Port of jxl-vardct `hf_pass.rs`.
//
// Coefficient coordinates `(x, y)` (upstream `(u16, u16)`) are packed into one
// `Int` as `x | (y << 16)`.

///|
/// Parameters for decoding `HfPass`.
pub struct HfPassParams {
  priv hf_block_ctx : HfBlockContext
  priv num_hf_presets : Int32
}

///|
pub fn HfPassParams::new(
  hf_block_ctx : HfBlockContext,
  num_hf_presets : Int32,
) -> HfPassParams {
  { hf_block_ctx, num_hf_presets, }
}

///|
/// HF coefficient decoder configuration.
///
/// Includes distribution for the entropy decoder and the order of HF coefficients. This struct is
/// passed as a parameter when [decoding HF coefficients][write_hf_coeff].
pub struct HfPass {
  priv permutation : FixedArray[FixedArray[FixedArray[Int32]]]
  priv hf_dist : @coding.Decoder
}

///|
pub fn HfPass::parse(
  bitstream : @bitstream.Bitstream,
  params : HfPassParams,
) -> HfPass raise @bitstream.JxlError {
  let mut used_orders = bitstream.read_u32(
    @bitstream.c(0x5F),
    @bitstream.c(0x13),
    @bitstream.c(0x00),
    @bitstream.u(13),
  )
  let permutation = FixedArray::makei(13, _ => {
    FixedArray::make(3, FixedArray::make(0, 0))
  })
  if used_orders != 0 {
    let decoder = @coding.Decoder::parse(bitstream, 8)
    for idx in 0..<13 {
      let (bw, bh) = block_sizes[idx]
      if (used_orders & 1) != 0 {
        let size = bw * bh
        let skip = size / 64
        for c in 0..<3 {
          let perm = @coding.read_permutation(bitstream, decoder, size, skip)
          let nat = natural_order_lazy(idx)
          permutation[idx][c] = FixedArray::makei(perm.length(), i => {
            nat[perm[i]]
          })
        }
      }
      used_orders = used_orders >> 1
    }
    decoder.finalize()
  }
  let hf_dist = @coding.Decoder::parse(
    bitstream,
    495 * params.num_hf_presets * params.hf_block_ctx.num_block_clusters,
  )
  { permutation, hf_dist, }
}

///|
fn HfPass::clone_decoder(self : HfPass) -> @coding.Decoder {
  self.hf_dist.clone()
}

///|
/// Coefficient order (packed `x | (y << 16)`) for the order ID and channel.
fn HfPass::order(
  self : HfPass,
  order_id : Int32,
  channel : Int32,
) -> FixedArray[Int32] {
  let permutation = self.permutation[order_id][channel]
  if permutation.length() == 0 {
    natural_order_lazy(order_id)
  } else {
    permutation
  }
}

///|
let block_sizes : FixedArray[(Int32, Int32)] = [
  (8, 8),
  (8, 8),
  (16, 16),
  (32, 32),
  (16, 8),
  (32, 8),
  (32, 16),
  (64, 64),
  (64, 32),
  (128, 128),
  (128, 64),
  (256, 256),
  (256, 128),
]

///|
let natural_order_cache : FixedArray[FixedArray[Int32]?] = FixedArray::make(
  13,
  None,
)

///|
fn natural_order_lazy(idx : Int32) -> FixedArray[Int32] {
  guard idx < 13 else { abort("Order ID out of bounds") }
  match natural_order_cache[idx] {
    Some(order) => order
    None => {
      let (bw, bh) = block_sizes[idx]
      let order = FixedArray::make(bw * bh, 0)
      fill_natural_order(bw, bh, order)
      natural_order_cache[idx] = Some(order)
      order
    }
  }
}

///|
fn fill_natural_order(
  bw : Int32,
  bh : Int32,
  output : FixedArray[Int32],
) -> Unit {
  let y_scale = bw / bh
  let mut idx = 0
  let lbw = bw / 8
  let lbh = bh / 8
  while idx < lbw * lbh {
    let x = idx % lbw
    let y = idx / lbw
    output[idx] = x | (y << 16)
    idx += 1
  }
  for dist in 1..<(2 * bw) {
    let margin = if dist > bw { dist - bw } else { 0 }
    for order in margin..<(dist - margin) {
      let (x, y) = if dist % 2 == 1 {
        (order, dist - 1 - order)
      } else {
        (dist - 1 - order, order)
      }
      if x < lbw && y < lbw {
        continue
      }
      if y % y_scale != 0 {
        continue
      }
      output[idx] = x | ((y / y_scale) << 16)
      idx += 1
    }
  }
}

///|
/// The natural coefficient order of DCT8, as `(x, y)` pairs
/// (upstream `DCT8_NATURAL_ORDER`).
pub let dct8_natural_order : FixedArray[(Int32, Int32)] = {
  let order = natural_order_lazy(0)
  FixedArray::makei(order.length(), i => (order[i] & 0xffff, order[i] >> 16))
}
