///|
/// Self-correcting (weighted) predictor parameters.
#derive(Debug, Eq)
pub(all) struct WpHeader {
  default_wp : Bool
  wp_p1 : Int32
  wp_p2 : Int32
  wp_p3a : Int32
  wp_p3b : Int32
  wp_p3c : Int32
  wp_p3d : Int32
  wp_p3e : Int32
  wp_w0 : Int32
  wp_w1 : Int32
  wp_w2 : Int32
  wp_w3 : Int32
}

///|
pub fn WpHeader::default() -> WpHeader {
  {
    default_wp: true,
    wp_p1: 16,
    wp_p2: 10,
    wp_p3a: 7,
    wp_p3b: 7,
    wp_p3c: 7,
    wp_p3d: 0,
    wp_p3e: 0,
    wp_w0: 13,
    wp_w1: 12,
    wp_w2: 12,
    wp_w3: 12,
  }
}

///|
pub fn WpHeader::parse(
  bs : @bitstream.Bitstream,
) -> WpHeader raise @bitstream.JxlError {
  let default_wp = bs.read_bool()
  if default_wp {
    return WpHeader::default()
  }
  let wp_p1 = bs.read_bits_int(5)
  let wp_p2 = bs.read_bits_int(5)
  let wp_p3a = bs.read_bits_int(5)
  let wp_p3b = bs.read_bits_int(5)
  let wp_p3c = bs.read_bits_int(5)
  let wp_p3d = bs.read_bits_int(5)
  let wp_p3e = bs.read_bits_int(5)
  let wp_w0 = bs.read_bits_int(4)
  let wp_w1 = bs.read_bits_int(4)
  let wp_w2 = bs.read_bits_int(4)
  let wp_w3 = bs.read_bits_int(4)
  {
    default_wp,
    wp_p1,
    wp_p2,
    wp_p3a,
    wp_p3b,
    wp_p3c,
    wp_p3d,
    wp_p3e,
    wp_w0,
    wp_w1,
    wp_w2,
    wp_w3,
  }
}

///|
#derive(Debug, Eq)
pub(all) enum Predictor {
  Zero
  West
  North
  AvgWestAndNorth
  Select
  Gradient
  SelfCorrecting
  NorthEast
  NorthWest
  WestWest
  AvgWestAndNorthWest
  AvgNorthAndNorthWest
  AvgNorthAndNorthEast
  AvgAll
}

///|
/// `Predictor::try_from(u32)`.
pub fn Predictor::try_from(
  value : UInt32,
) -> Predictor raise @bitstream.JxlError {
  match value {
    0 => Zero
    1 => West
    2 => North
    3 => AvgWestAndNorth
    4 => Select
    5 => Gradient
    6 => SelfCorrecting
    7 => NorthEast
    8 => NorthWest
    9 => WestWest
    10 => AvgWestAndNorthWest
    11 => AvgNorthAndNorthWest
    12 => AvgNorthAndNorthEast
    13 => AvgAll
    _ => raise @bitstream.InvalidEnum("MaProperty", value)
  }
}

///|
/// Predicts the current sample from the properties computed by
/// `PredictorState::properties` (upstream `Predictor::predict::<EDGE = true>`;
/// the non-edge specialisation computes the same values).
pub fn Predictor::predict(self : Predictor, state : PredictorState) -> Int32 {
  match self {
    Zero => 0
    West => state.w
    North => state.n
    AvgWestAndNorth => ((state.w.to_int64() + state.n.to_int64()) / 2L).to_int()
    Select => {
      let n = state.n
      let w = state.w
      let nw = state.nw
      if abs_diff_i32(n, nw) < abs_diff_i32(w, nw) {
        w
      } else {
        n
      }
    }
    Gradient => grad_clamped(state.n, state.w, state.nw)
    SelfCorrecting => {
      guard state.sc_valid else {
        abort("predict_non_sc called with SelfCorrecting predictor")
      }
      ((state.sc_prediction + 3L) >> 3).to_int()
    }
    NorthEast => state.ne()
    NorthWest => state.nw
    WestWest => state.ww()
    AvgWestAndNorthWest =>
      ((state.w.to_int64() + state.nw.to_int64()) / 2L).to_int()
    AvgNorthAndNorthWest =>
      ((state.n.to_int64() + state.nw.to_int64()) / 2L).to_int()
    AvgNorthAndNorthEast =>
      ((state.n.to_int64() + state.ne().to_int64()) / 2L).to_int()
    AvgAll => {
      let n = state.n.to_int64()
      let w = state.w.to_int64()
      let nn = state.nn().to_int64()
      let ww = state.ww().to_int64()
      let nee = state.nee().to_int64()
      let ne = state.ne().to_int64()
      ((6L * n - 2L * nn + 7L * w + ww + nee + 3L * ne + 8L) / 16L).to_int()
    }
  }
}

///|
let div_lookup : FixedArray[UInt32] = {
  let out = FixedArray::make(65, 0U)
  for i in 1..<=64 {
    out[i] = ((1 << 24) / i).reinterpret_as_uint()
  }
  out
}

///|
/// Predictor state of a channel being decoded.
///
/// Upstream splits this into `PredictorState` and a short-lived `Properties`
/// value per sample. To avoid a per-sample allocation, the `Properties` data
/// (property cache and the self-correcting prediction) lives here:
/// `properties()` computes it, `get_property()` reads it (`Properties::get`)
/// and `record()` consumes it (`Properties::record`).
pub struct PredictorState {
  priv mut width : Int32
  priv mut prev_row : FixedArray[Int32]
  priv mut curr_row : FixedArray[Int32]
  priv mut prev_channels_rev : Array[@grid.SubGrid[Int32]]
  priv mut self_correcting : SelfCorrectingPredictor?
  priv sc_cache : SelfCorrectingPredictor
  priv mut y : Int32
  priv mut x : Int32
  priv mut w : Int32
  priv mut n : Int32
  priv mut nw : Int32
  priv mut prev_grad : Int32
  // Properties
  priv prop_cache : FixedArray[Int32]
  priv mut sc_valid : Bool
  priv mut sc_prediction : Int64
  priv mut sc_max_error : Int32
  priv sc_subpred : FixedArray[Int64]
}

///|
pub fn PredictorState::new() -> PredictorState {
  {
    width: 0,
    prev_row: FixedArray::make(0, 0),
    curr_row: FixedArray::make(0, 0),
    prev_channels_rev: [],
    self_correcting: None,
    sc_cache: SelfCorrectingPredictor::new(),
    y: 0,
    x: 0,
    w: 0,
    n: 0,
    nw: 0,
    prev_grad: 0,
    prop_cache: FixedArray::make(16, 0),
    sc_valid: false,
    sc_prediction: 0L,
    sc_max_error: 0,
    sc_subpred: FixedArray::make(4, 0L),
  }
}

///|
pub fn PredictorState::reset(
  self : PredictorState,
  width : Int32,
  prev_channels_rev : ArrayView[@grid.SubGrid[Int32]],
  wp_header : WpHeader?,
) -> Unit {
  self.self_correcting = match wp_header {
    Some(wp) => {
      self.sc_cache.reset(width, wp)
      Some(self.sc_cache)
    }
    None => None
  }
  if self.prev_row.length() < width {
    self.prev_row = FixedArray::make(width, 0)
  }
  if self.curr_row.length() < width {
    self.curr_row = FixedArray::make(width, 0)
  }
  self.prev_channels_rev = prev_channels_rev.to_owned()
  self.width = width
  self.y = 0
  self.x = 0
  self.w = 0
  self.n = 0
  self.nw = 0
  self.prev_grad = 0
  self.sc_valid = false
}

///|
/// `curr_row.get(x).unwrap_or(n)`: the row two above exists from `y >= 2`.
#inline
fn PredictorState::nn(self : PredictorState) -> Int32 {
  if self.y >= 2 {
    self.curr_row[self.x]
  } else {
    self.n
  }
}

///|
#inline
fn PredictorState::ne(self : PredictorState) -> Int32 {
  let x = self.x
  if self.y == 0 || x + 1 >= self.width {
    self.n
  } else {
    self.prev_row[x + 1]
  }
}

///|
#inline
fn PredictorState::nee(self : PredictorState) -> Int32 {
  let x = self.x
  if self.y == 0 || x + 2 >= self.width {
    self.ne()
  } else {
    self.prev_row[x + 2]
  }
}

///|
#inline
fn PredictorState::ww(self : PredictorState) -> Int32 {
  let x = self.x
  if x >= 2 {
    self.curr_row[x - 2]
  } else {
    self.w
  }
}

///|
/// Computes the properties of the current sample (upstream
/// `PredictorState::properties`), including the self-correcting prediction
/// if enabled.
pub fn PredictorState::properties(self : PredictorState) -> Unit {
  let ne = self.ne()
  match self.self_correcting {
    Some(sc) => {
      sc.predict(self, self.n, self.nw, ne, self.w, self.nn())
      self.sc_valid = true
    }
    None => self.sc_valid = false
  }
  let w_nw = self.w - self.nw
  let c = self.prop_cache
  c[0] = 0
  c[1] = 0
  c[2] = self.y
  c[3] = self.x
  c[4] = wrapping_abs(self.n)
  c[5] = wrapping_abs(self.w)
  c[6] = self.n
  c[7] = self.w
  c[8] = self.w - self.prev_grad
  c[9] = w_nw + self.n
  c[10] = w_nw
  c[11] = self.nw - self.n
  c[12] = self.n - ne
  c[13] = self.n - self.nn()
  c[14] = self.w - self.ww()
  c[15] = if self.sc_valid { self.sc_max_error } else { 0 }
}

///|
fn PredictorState::get_extra(
  self : PredictorState,
  prop_extra : Int32,
) -> Int32 {
  let prev_channel_idx = prop_extra / 4
  let prop_idx = prop_extra % 4
  if prev_channel_idx >= self.prev_channels_rev.length() {
    return 0
  }
  let prev_channel = self.prev_channels_rev[prev_channel_idx]
  let x = self.x
  let y = self.y
  let c = prev_channel.get(x, y)
  if prop_idx == 0 {
    wrapping_abs(c)
  } else if prop_idx == 1 {
    c
  } else {
    let g = if x == 0 && y == 0 {
      0
    } else if x == 0 {
      prev_channel.get(0, y - 1)
    } else if y == 0 {
      prev_channel.get(x - 1, 0)
    } else {
      let nw = prev_channel.get(x - 1, y - 1)
      let n = prev_channel.get(x, y - 1)
      let w = prev_channel.get(x - 1, y)
      grad_clamped(n, w, nw)
    }
    if prop_idx == 2 {
      abs_diff_i32(c, g).to_int()
    } else {
      c - g
    }
  }
}

///|
/// `Properties::get`.
#inline
pub fn PredictorState::get_property(
  self : PredictorState,
  property : Int32,
) -> Int32 {
  if property >= 16 {
    self.get_extra(property - 16)
  } else {
    self.prop_cache[property]
  }
}

///|
/// `Properties::record`: stores the decoded sample and advances.
pub fn PredictorState::record(self : PredictorState, sample : Int32) -> Unit {
  if self.sc_valid {
    match self.self_correcting {
      Some(sc) => sc.record(self, sample)
      None => ()
    }
  }
  self.curr_row[self.x] = sample
  self.x += 1
  if self.x >= self.width {
    self.y += 1
    self.x = 0
    let tmp = self.prev_row
    self.prev_row = self.curr_row
    self.curr_row = tmp
    self.prev_grad = 0
    let n = self.prev_row[0]
    self.n = n
    self.w = n
    self.nw = n
  } else {
    self.prev_grad = self.prop_cache[9]
    self.w = sample
    if self.y == 0 {
      self.nw = sample
      self.n = sample
    } else {
      self.nw = self.n
      self.n = self.prev_row[self.x]
    }
  }
}

///|
priv struct SelfCorrectingPredictor {
  mut width : Int32
  mut x : Int32
  mut y : Int32
  mut true_err_row : FixedArray[Int32]
  /// `[u32; 4]` per column, flattened.
  mut subpred_err_row : FixedArray[UInt32]
  mut wp : WpHeader
  mut true_err_w : Int32
  mut true_err_nw : Int32
  mut true_err_n : Int32
  mut true_err_ne : Int32
  subpred_err_nw_ww : FixedArray[UInt32]
  subpred_err_n_w : FixedArray[UInt32]
  subpred_err_ne : FixedArray[UInt32]
  // scratch
  weight : FixedArray[UInt32]
  subpred_err : FixedArray[UInt32]
}

///|
fn SelfCorrectingPredictor::new() -> SelfCorrectingPredictor {
  {
    width: 0,
    x: 0,
    y: 0,
    true_err_row: FixedArray::make(0, 0),
    subpred_err_row: FixedArray::make(0, 0),
    wp: WpHeader::default(),
    true_err_w: 0,
    true_err_nw: 0,
    true_err_n: 0,
    true_err_ne: 0,
    subpred_err_nw_ww: FixedArray::make(4, 0),
    subpred_err_n_w: FixedArray::make(4, 0),
    subpred_err_ne: FixedArray::make(4, 0),
    weight: FixedArray::make(4, 0),
    subpred_err: FixedArray::make(4, 0),
  }
}

///|
/// `SelfCorrectingPredictor::new(width, wp_header)`, reusing buffers.
fn SelfCorrectingPredictor::reset(
  self : SelfCorrectingPredictor,
  width : Int32,
  wp : WpHeader,
) -> Unit {
  if self.true_err_row.length() < width {
    self.true_err_row = FixedArray::make(width, 0)
    self.subpred_err_row = FixedArray::make(width * 4, 0)
  } else {
    self.true_err_row.fill(0)
    self.subpred_err_row.fill(0)
  }
  self.width = width
  self.x = 0
  self.y = 0
  self.wp = wp
  self.true_err_w = 0
  self.true_err_nw = 0
  self.true_err_n = 0
  self.true_err_ne = 0
  for i in 0..<4 {
    self.subpred_err_nw_ww[i] = 0
    self.subpred_err_n_w[i] = 0
    self.subpred_err_ne[i] = 0
  }
}

///|
/// `u64::ilog2`, for `v > 0`.
#inline
fn ilog2_u64(v : UInt64) -> Int32 {
  63 - v.clz()
}

///|
/// Computes the prediction; results go to `out.sc_*` (`PredictionResult`).
fn SelfCorrectingPredictor::predict(
  self : SelfCorrectingPredictor,
  out : PredictorState,
  n : Int32,
  nw : Int32,
  ne : Int32,
  w : Int32,
  nn : Int32,
) -> Unit {
  let wp = self.wp
  let true_err_w = self.true_err_w.to_int64()
  let true_err_nw = self.true_err_nw.to_int64()
  let true_err_n = self.true_err_n.to_int64()
  let true_err_ne = self.true_err_ne.to_int64()
  let n3 = n.to_int64() << 3
  let nw3 = nw.to_int64() << 3
  let ne3 = ne.to_int64() << 3
  let w3 = w.to_int64() << 3
  let nn3 = nn.to_int64() << 3
  let subpred = out.sc_subpred
  subpred[0] = w3 + ne3 - n3
  subpred[1] = n3 -
    (((true_err_w + true_err_n + true_err_ne) * wp.wp_p1.to_int64()) >> 5)
  subpred[2] = w3 -
    (((true_err_w + true_err_n + true_err_nw) * wp.wp_p2.to_int64()) >> 5)
  subpred[3] = n3 -
    (
      (
        true_err_nw * wp.wp_p3a.to_int64() +
        true_err_n * wp.wp_p3b.to_int64() +
        true_err_ne * wp.wp_p3c.to_int64() +
        (nn3 - n3) * wp.wp_p3d.to_int64() +
        (nw3 - w3) * wp.wp_p3e.to_int64()
      ) >>
      5
    )
  let weight = self.weight
  for i in 0..<4 {
    let err_sum = self.subpred_err_nw_ww[i] +
      self.subpred_err_n_w[i] +
      self.subpred_err_ne[i]
    let maxweight = match i {
      0 => wp.wp_w0
      1 => wp.wp_w1
      2 => wp.wp_w2
      _ => wp.wp_w3
    }
    let t = (err_sum.to_uint64() + 1UL) >> 5
    let shift = if t == 0UL { 0 } else { ilog2_u64(t) }
    weight[i] = 4U +
      (
        (
          maxweight.reinterpret_as_uint() *
          div_lookup[(err_sum >> shift).reinterpret_as_int() + 1]
        ) >>
        shift
      )
  }
  let sum_weights = weight[0] + weight[1] + weight[2] + weight[3]
  let log_weight = ilog2_u64(sum_weights.to_uint64() >> 4)
  for i in 0..<4 {
    weight[i] = weight[i] >> log_weight
  }
  let sum_weights = weight[0] + weight[1] + weight[2] + weight[3]
  let mut s = (sum_weights.to_int64() >> 1) - 1L
  for i in 0..<4 {
    s += subpred[i] * weight[i].to_int64()
  }
  let mut prediction = (
      s * div_lookup[sum_weights.reinterpret_as_int()].to_int64()
    ) >>
    24
  if ((true_err_n ^ true_err_w) | (true_err_n ^ true_err_nw)) <= 0L {
    let min = @cmp.minimum(@cmp.minimum(n3, w3), ne3)
    let max = @cmp.maximum(@cmp.maximum(n3, w3), ne3)
    prediction = if prediction < min {
      min
    } else if prediction > max {
      max
    } else {
      prediction
    }
  }
  let mut max_error = true_err_w
  if true_err_n.abs() > max_error.abs() {
    max_error = true_err_n
  }
  if true_err_nw.abs() > max_error.abs() {
    max_error = true_err_nw
  }
  if true_err_ne.abs() > max_error.abs() {
    max_error = true_err_ne
  }
  out.sc_prediction = prediction
  out.sc_max_error = max_error.to_int()
}

///|
fn SelfCorrectingPredictor::record(
  self : SelfCorrectingPredictor,
  pred : PredictorState,
  sample : Int32,
) -> Unit {
  let sample = sample.to_int64() << 3
  let true_err = pred.sc_prediction - sample
  let subpred_err = self.subpred_err
  for i in 0..<4 {
    let sp = pred.sc_subpred[i]
    let diff = if sp >= sample {
      (sp - sample).reinterpret_as_uint64()
    } else {
      (sample - sp).reinterpret_as_uint64()
    }
    subpred_err[i] = ((diff + 3UL) >> 3).to_uint()
  }
  let x = self.x
  self.true_err_row[x] = true_err.to_int()
  for i in 0..<4 {
    self.subpred_err_row[x * 4 + i] = subpred_err[i]
  }
  self.x += 1
  if self.x >= self.width {
    self.y += 1
    self.x = 0
    self.true_err_w = 0
    self.true_err_n = self.true_err_row[0]
    self.true_err_nw = self.true_err_n
    for i in 0..<4 {
      self.subpred_err_n_w[i] = self.subpred_err_row[i]
      self.subpred_err_nw_ww[i] = self.subpred_err_n_w[i]
    }
    if self.width <= 1 {
      self.true_err_ne = self.true_err_n
      for i in 0..<4 {
        self.subpred_err_ne[i] = self.subpred_err_n_w[i]
      }
    } else {
      self.true_err_ne = self.true_err_row[1]
      for i in 0..<4 {
        self.subpred_err_ne[i] = self.subpred_err_row[4 + i]
      }
    }
  } else {
    self.true_err_w = true_err.to_int()
    self.true_err_nw = self.true_err_n
    self.true_err_n = self.true_err_ne
    for i in 0..<4 {
      self.subpred_err_nw_ww[i] = self.subpred_err_n_w[i]
      self.subpred_err_n_w[i] = self.subpred_err_ne[i] + subpred_err[i]
    }
    if self.x + 1 >= self.width {
      self.true_err_ne = self.true_err_n
      for i in 0..<4 {
        self.subpred_err_ne[i] = self.subpred_err_n_w[i]
      }
    } else if self.y != 0 {
      let x = self.x
      self.true_err_ne = self.true_err_row[x + 1]
      for i in 0..<4 {
        self.subpred_err_ne[i] = self.subpred_err_row[(x + 1) * 4 + i]
      }
    }
  }
}
