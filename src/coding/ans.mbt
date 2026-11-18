// Port of jxl-coding/src/ans.rs

///|
/// An ANS distribution of one cluster (`ans::Histogram`), stored as an alias
/// table.
///
/// Ported from libjxl. log_alphabet_size <= 8 and log_bucket_size <= 7, so 8
/// bits are sufficient for symbols and cutoffs. alias_dist_xor allows
/// branchless dist computation for alias symbol.
///
/// Each bucket is packed into a `UInt64` with the same layout as the Rust
/// `#[repr(C)] struct Bucket` read as a little-endian `u64`:
/// `alias_symbol | alias_cutoff << 8 | dist << 16 | alias_offset << 32 | alias_dist_xor << 48`.
priv struct AnsHistogram {
  buckets : FixedArray[UInt64]
  log_bucket_size : Int32
  bucket_mask : UInt32
  /// The single symbol, or -1 (`None`).
  single_symbol : Int32
}

///|
fn pack_bucket(
  alias_symbol : Int32,
  alias_cutoff : Int32,
  dist : Int32,
  alias_offset : Int32,
  alias_dist_xor : Int32,
) -> UInt64 {
  (alias_symbol & 0xff).to_uint64() |
  ((alias_cutoff & 0xff).to_uint64() << 8) |
  ((dist & 0xffff).to_uint64() << 16) |
  ((alias_offset & 0xffff).to_uint64() << 32) |
  ((alias_dist_xor & 0xffff).to_uint64() << 48)
}

///|
/// log_alphabet_size: 5 + u(2)
fn AnsHistogram::parse(
  bitstream : @bitstream.Bitstream,
  log_alphabet_size : Int32,
) -> AnsHistogram raise @bitstream.JxlError {
  let table_size = 1 << log_alphabet_size
  // 4 <= log_bucket_size <= 7
  let log_bucket_size = 12 - log_alphabet_size
  let bucket_size = 1 << log_bucket_size
  let mut alphabet_size = 0
  let dist = FixedArray::make(table_size, 0)
  if bitstream.read_bool() {
    if bitstream.read_bool() {
      // binary
      let v0 = ans_read_u8(bitstream)
      let v1 = ans_read_u8(bitstream)
      if v0 == v1 {
        raise coding_error("InvalidAnsHistogram")
      }
      alphabet_size = (if v0 > v1 { v0 } else { v1 }) + 1
      if alphabet_size > table_size {
        raise coding_error("InvalidAnsHistogram")
      }
      let prob = bitstream.read_bits_int(12)
      dist[v0] = prob
      dist[v1] = (1 << 12) - prob
    } else {
      // unary
      let val = ans_read_u8(bitstream)
      alphabet_size = val + 1
      if alphabet_size > table_size {
        raise coding_error("InvalidAnsHistogram")
      }
      dist[val] = 1 << 12
    }
  } else if bitstream.read_bool() {
    // evenly distributed
    alphabet_size = ans_read_u8(bitstream) + 1
    if alphabet_size > table_size {
      raise coding_error("InvalidAnsHistogram")
    }
    let base = (1 << 12) / alphabet_size
    let leftover = (1 << 12) % alphabet_size
    for i in 0..<leftover {
      dist[i] = base + 1
    }
    for i in leftover..<alphabet_size {
      dist[i] = base
    }
  } else {
    // compressed distribution info
    let mut len = 0
    while len < 3 {
      if bitstream.read_bool() {
        len += 1
      } else {
        break
      }
    }
    let shift = bitstream.read_bits_int(len) + (1 << len) - 1
    if shift > 13 {
      raise coding_error("InvalidAnsHistogram")
    }
    alphabet_size = ans_read_u8(bitstream) + 3
    if alphabet_size > table_size {
      raise coding_error("InvalidAnsHistogram")
    }
    // (start, end) pairs
    let repeat_ranges : Array[Int32] = []
    let mut omit_log = 0
    let mut omit_pos = -1
    let mut idx = 0
    while idx < alphabet_size {
      dist[idx] = ans_read_prefix(bitstream)
      if dist[idx] == 13 {
        let repeat_count = ans_read_u8(bitstream) + 4
        if idx + repeat_count > alphabet_size {
          raise coding_error("InvalidAnsHistogram")
        }
        repeat_ranges.push(idx)
        repeat_ranges.push(idx + repeat_count)
        idx += repeat_count
        continue
      }
      if omit_pos >= 0 {
        if dist[idx] > omit_log {
          omit_log = dist[idx]
          omit_pos = idx
        }
      } else {
        omit_log = dist[idx]
        omit_pos = idx
      }
      idx += 1
    }
    if omit_pos < 0 {
      raise coding_error("InvalidAnsHistogram")
    }
    if omit_pos + 1 < table_size && dist[omit_pos + 1] == 13 {
      raise coding_error("InvalidAnsHistogram")
    }
    let num_ranges = repeat_ranges.length() / 2
    let mut repeat_range_idx = 0
    let mut acc = 0
    let mut prev_dist = 0
    for idx in 0..<table_size {
      if repeat_range_idx < num_ranges &&
        repeat_ranges[2 * repeat_range_idx] <= idx {
        if repeat_ranges[2 * repeat_range_idx + 1] == idx {
          repeat_range_idx += 1
        } else {
          dist[idx] = prev_dist
          acc += prev_dist
          if acc > 1 << 12 {
            raise coding_error("InvalidAnsHistogram")
          }
          continue
        }
      }
      let code = dist[idx]
      if code == 0 {
        prev_dist = 0
        continue
      }
      if idx == omit_pos {
        prev_dist = 0
        continue
      }
      let code = if code > 1 {
        let zeros = code - 1
        let mut bitcount = shift - ((12 - zeros) >> 1)
        if bitcount < 0 {
          bitcount = 0
        }
        if bitcount > zeros {
          bitcount = zeros
        }
        let v = (1 << zeros) +
          (bitstream.read_bits_int(bitcount) << (zeros - bitcount))
        v & 0xffff
      } else {
        code
      }
      dist[idx] = code
      prev_dist = code
      acc += code
      if acc > 1 << 12 {
        raise coding_error("InvalidAnsHistogram")
      }
    }
    dist[omit_pos] = (1 << 12) - acc
  }
  let mut single_sym_idx = -1
  for i in 0..<table_size {
    if dist[i] == 1 << 12 {
      single_sym_idx = i
      break
    }
  }
  if single_sym_idx >= 0 {
    let buckets = FixedArray::make(table_size, 0UL)
    for i in 0..<table_size {
      let d = dist[i]
      buckets[i] = pack_bucket(
        single_sym_idx,
        0,
        d,
        bucket_size * i,
        d ^ (1 << 12),
      )
    }
    return {
      buckets,
      log_bucket_size,
      bucket_mask: ((1 << log_bucket_size) - 1).reinterpret_as_uint(),
      single_symbol: single_sym_idx,
    }
  }

  // Working buckets
  let alias_symbol = FixedArray::make(table_size, 0)
  let alias_offset = FixedArray::make(table_size, 0)
  let alias_cutoff = FixedArray::make(table_size, 0)
  for i in 0..<table_size {
    alias_symbol[i] = if i < alphabet_size { i } else { 0 }
    alias_cutoff[i] = dist[i]
  }
  let underfull : Array[Int32] = []
  let overfull : Array[Int32] = []
  for idx in 0..<table_size {
    let d = dist[idx]
    if d < bucket_size {
      underfull.push(idx)
    } else if d > bucket_size {
      overfull.push(idx)
    }
  }
  while true {
    // Mirrors `while let (Some(o), Some(u)) = (overfull.pop(), underfull.pop())`
    let o = overfull.pop()
    let u = underfull.pop()
    guard o is Some(o) && u is Some(u) else { break }
    let by = bucket_size - alias_cutoff[u]
    alias_cutoff[o] = (alias_cutoff[o] - by) & 0xffff
    alias_symbol[u] = o
    alias_offset[u] = alias_cutoff[o]
    let c = alias_cutoff[o]
    if c < bucket_size {
      underfull.push(o)
    } else if c > bucket_size {
      overfull.push(o)
    }
  }
  let buckets = FixedArray::make(table_size, 0UL)
  for idx in 0..<table_size {
    buckets[idx] = if alias_cutoff[idx] == bucket_size {
      pack_bucket(idx, 0, dist[idx], 0, 0)
    } else {
      let sym = alias_symbol[idx]
      pack_bucket(
        sym,
        alias_cutoff[idx],
        dist[idx],
        alias_offset[idx] - alias_cutoff[idx],
        dist[idx] ^ dist[sym],
      )
    }
  }
  {
    buckets,
    log_bucket_size,
    bucket_mask: ((1 << log_bucket_size) - 1).reinterpret_as_uint(),
    single_symbol: -1,
  }
}

///|
fn ans_read_u8(
  bitstream : @bitstream.Bitstream,
) -> Int32 raise @bitstream.JxlError {
  if bitstream.read_bool() {
    let n = bitstream.read_bits_int(3)
    ((1 << n) + bitstream.read_bits_int(n)) & 0xff
  } else {
    0
  }
}

///|
/// Reads a symbol, updating the ANS `state`. Returns the symbol.
/// (`ans::Histogram::read_symbol`; the state lives in [AnsCoder].)
fn AnsCoder::read_symbol_from(
  self : AnsCoder,
  hist : AnsHistogram,
  bitstream : @bitstream.Bitstream,
) -> Int32 raise @bitstream.JxlError {
  let state = self.state
  let idx = state & 0xfff
  let i = (idx >> hist.log_bucket_size).reinterpret_as_int()
  let pos = idx & hist.bucket_mask
  let bucket = hist.buckets[i]
  let alias_symbol = (bucket & 0xff).to_int()
  let alias_cutoff = ((bucket >> 8) & 0xff).to_uint()
  let dist = ((bucket >> 16) & 0xffff).to_uint()
  let map_to_alias = pos >= alias_cutoff
  let cond_bucket = if map_to_alias { bucket } else { 0 }
  let offset = (cond_bucket >> 32).to_uint() & 0xffff
  let dist_xor = (cond_bucket >> 48).to_uint()
  let dist = dist ^ dist_xor
  let symbol = if map_to_alias { alias_symbol } else { i }
  let offset = offset + pos
  let next_state = (state >> 12) * dist + offset
  let appended_state = (next_state << 16) | bitstream.peek_bits(16)
  if next_state < 0x10000 {
    self.state = appended_state
    bitstream.consume_bits(16)
  } else {
    self.state = next_state
  }
  symbol
}

///|
fn ans_read_prefix(
  bitstream : @bitstream.Bitstream,
) -> Int32 raise @bitstream.JxlError {
  match bitstream.read_bits(3) {
    0 => 10
    1 => {
      if bitstream.read_bool() {
        return 4
      }
      if bitstream.read_bool() {
        return 0
      }
      if bitstream.read_bool() {
        return 11
      }
      if bitstream.read_bool() {
        return 13
      }
      12
    }
    2 => 7
    3 => if bitstream.read_bool() { 1 } else { 3 }
    4 => 6
    5 => 8
    6 => 9
    _ => if bitstream.read_bool() { 2 } else { 5 }
  }
}
