// Port of jxl-coding/src/prefix.rs: prefix code based on Brotli

///|
const MAX_PREFIX_BITS : Int32 = 15

///|
const MAX_TOPLEVEL_BITS : Int32 = 10

///|
/// A prefix code of one cluster (`prefix::Histogram`).
///
/// Entries are packed into an `Int`:
/// `symbol_or_offset | bits_or_mask << 16 | nested << 24`.
#derive(Debug)
priv struct PrefixHistogram {
  toplevel_bits : Int32
  toplevel_mask : UInt32
  toplevel_entries : FixedArray[Int32]
  second_level_entries : FixedArray[Int32]
}

///|
fn prefix_entry(
  nested : Bool,
  bits_or_mask : Int32,
  symbol_or_offset : Int32,
) -> Int32 {
  (symbol_or_offset & 0xffff) |
  ((bits_or_mask & 0xff) << 16) |
  (if nested { 1 << 24 } else { 0 })
}

///|
fn PrefixHistogram::with_code_lengths(
  code_lengths : FixedArray[Int32],
) -> PrefixHistogram raise @bitstream.JxlError {
  let syms_for_length : Array[Array[Int32]] = []
  for sym, len in code_lengths {
    if len > 0 {
      while syms_for_length.length() < len {
        syms_for_length.push([])
      }
      syms_for_length[len - 1].push(sym)
    }
  }
  let num_lengths = syms_for_length.length()
  let toplevel_bits = if num_lengths < MAX_TOPLEVEL_BITS {
    num_lengths
  } else {
    MAX_TOPLEVEL_BITS
  }
  let toplevel_size = 1 << toplevel_bits
  let entries = FixedArray::make(toplevel_size, 0)
  let mut current_bits = 0
  for idx in 0..<toplevel_bits {
    let shifts = toplevel_bits - 1 - idx
    for sym in syms_for_length[idx] {
      let entry = prefix_entry(false, idx + 1, sym)
      let n = 1 << shifts
      if current_bits + n > toplevel_size {
        // Upstream panics on the out-of-bounds slice here (unreachable for codes that passed the Kraft checks).
        abort("prefix code table index out of bounds")
      }
      for i in current_bits..<(current_bits + n) {
        entries[i] = entry
      }
      current_bits += n
    }
  }
  let second_level_entries : Array[Int32] = []
  if toplevel_bits < num_lengths {
    let mut remaining_entries : Array[Int32] = []
    let mut remaining_entry_bits = 0
    for idx in toplevel_bits..<num_lengths {
      let syms = syms_for_length[idx]
      if syms.is_empty() {
        continue
      }
      let chunk_size_bits = idx + 1 - toplevel_bits
      let chunk_size = 1 << chunk_size_bits
      let mut chunk : Array[Int32] = Array(capacity=chunk_size)
      if !remaining_entries.is_empty() {
        let mult = 1 << (chunk_size_bits - remaining_entry_bits)
        for entry in remaining_entries {
          for _ in 0..<mult {
            chunk.push(entry)
          }
        }
      }
      for sym in syms {
        chunk.push(prefix_entry(false, idx + 1, sym))
        if chunk.length() == chunk_size {
          if current_bits >= toplevel_size {
            // Upstream panics on the out-of-bounds index here (unreachable for codes that passed the Kraft checks).
            abort("prefix code table index out of bounds")
          }
          entries[current_bits] = prefix_entry(
            true,
            chunk_size - 1,
            second_level_entries.length(),
          )
          vec_reverse_bits(chunk[:], second_level_entries)
          current_bits += 1
          chunk = Array(capacity=chunk_size)
        }
      }
      remaining_entries = chunk
      remaining_entry_bits = chunk_size_bits
    }
    if !remaining_entries.is_empty() {
      raise coding_error(InvalidPrefixHistogram)
    }
  }
  if current_bits == toplevel_size {
    let toplevel_entries : Array[Int32] = Array(capacity=toplevel_size)
    vec_reverse_bits(entries[:], toplevel_entries)
    {
      toplevel_bits,
      toplevel_mask: (toplevel_size - 1).reinterpret_as_uint(),
      toplevel_entries: FixedArray::from_array(toplevel_entries),
      second_level_entries: FixedArray::from_array(second_level_entries),
    }
  } else {
    raise coding_error(InvalidPrefixHistogram)
  }
}

///|
fn PrefixHistogram::with_single_symbol(symbol : Int32) -> PrefixHistogram {
  {
    toplevel_bits: 0,
    toplevel_mask: 0,
    toplevel_entries: [prefix_entry(false, 0, symbol)],
    second_level_entries: [],
  }
}

///|
fn PrefixHistogram::parse(
  bitstream : @bitstream.Bitstream,
  alphabet_size : Int32,
) -> PrefixHistogram raise @bitstream.JxlError {
  if alphabet_size == 1 {
    return PrefixHistogram::with_single_symbol(0)
  }
  if alphabet_size > 1 << MAX_PREFIX_BITS {
    raise coding_error(PrefixSymbolTooLarge(alphabet_size))
  }
  let hskip = bitstream.read_bits_int(2)
  if hskip == 1 {
    PrefixHistogram::parse_simple(bitstream, alphabet_size)
  } else {
    PrefixHistogram::parse_complex(bitstream, alphabet_size, hskip)
  }
}

///|
fn PrefixHistogram::parse_simple(
  bitstream : @bitstream.Bitstream,
  alphabet_size : Int32,
) -> PrefixHistogram raise @bitstream.JxlError {
  // alphabet_size.next_power_of_two().trailing_zeros()
  let mut alphabet_bits = 0
  while 1 << alphabet_bits < alphabet_size {
    alphabet_bits += 1
  }
  let nsym = bitstream.read_bits_int(2) + 1
  let syms = FixedArray::make(4, 0)
  let lens = FixedArray::make(4, 0)
  match nsym {
    1 => {
      let sym = bitstream.read_bits_int(alphabet_bits)
      if sym >= alphabet_size {
        raise coding_error(InvalidPrefixHistogram)
      }
      return PrefixHistogram::with_single_symbol(sym)
    }
    2 => {
      syms[2] = bitstream.read_bits_int(alphabet_bits)
      syms[3] = bitstream.read_bits_int(alphabet_bits)
      lens[2] = 1
      lens[3] = 1
    }
    3 => {
      syms[1] = bitstream.read_bits_int(alphabet_bits)
      syms[2] = bitstream.read_bits_int(alphabet_bits)
      syms[3] = bitstream.read_bits_int(alphabet_bits)
      lens[1] = 1
      lens[2] = 2
      lens[3] = 2
    }
    _ => {
      for i in 0..<4 {
        syms[i] = bitstream.read_bits_int(alphabet_bits)
      }
      let tree_selector = bitstream.read_bool()
      if tree_selector {
        lens[0] = 1
        lens[1] = 2
        lens[2] = 3
        lens[3] = 3
      } else {
        lens[0] = 2
        lens[1] = 2
        lens[2] = 2
        lens[3] = 2
      }
    }
  }
  let code_lengths = FixedArray::make(alphabet_size, 0)
  for i in 0..<4 {
    let sym = syms[i]
    if sym < alphabet_size {
      code_lengths[sym] = lens[i]
    } else {
      raise coding_error(InvalidPrefixHistogram)
    }
  }
  PrefixHistogram::with_code_lengths(code_lengths)
}

///|
let code_length_order : FixedArray[Int32] = [
  1, 2, 3, 4, 0, 5, 17, 6, 16, 7, 8, 9, 10, 11, 12, 13, 14, 15,
]

///|
fn PrefixHistogram::parse_complex(
  bitstream : @bitstream.Bitstream,
  alphabet_size : Int32,
  hskip : Int32,
) -> PrefixHistogram raise @bitstream.JxlError {
  let code_length_code_lengths = FixedArray::make(18, 0)
  let mut bitacc = 0
  let mut nonzero_count = 0
  let mut nonzero_sym = 0
  for i in hskip..<18 {
    let idx = code_length_order[i]
    // Read single code length code.
    let base = bitstream
      .read_u32(
        @bitstream.c(0),
        @bitstream.c(4),
        @bitstream.c(3),
        @bitstream.c(8),
      )
      .reinterpret_as_int()
    let len = if base == 8 {
      if bitstream.read_bool() {
        if bitstream.read_bool() {
          // 1111
          5
        } else {
          // 0111
          1
        }
      } else {
        // 011
        2
      }
    } else {
      base
    }
    code_length_code_lengths[idx] = len
    if len != 0 {
      nonzero_count += 1
      nonzero_sym = idx
      bitacc += 32 >> len
      if bitacc == 32 {
        break
      } else if bitacc > 32 {
        raise coding_error(InvalidPrefixHistogram)
      }
    }
  }
  let code_length_histogram = if nonzero_count == 1 {
    PrefixHistogram::with_single_symbol(nonzero_sym)
  } else if bitacc != 32 {
    raise coding_error(InvalidPrefixHistogram)
  } else {
    PrefixHistogram::with_code_lengths(code_length_code_lengths)
  }
  let code_lengths = FixedArray::make(alphabet_size, 0)
  let mut bitacc = 0
  let mut prev_sym = 8
  let mut last_nonzero_sym = 8
  let mut last_repeat_count = 0
  let mut repeat_count = 0
  let mut repeat_sym = 0
  for i in 0..<alphabet_size {
    if repeat_count > 0 {
      code_lengths[i] = repeat_sym
      repeat_count -= 1
    } else {
      let sym = code_length_histogram.read_symbol(bitstream) & 0xff
      match sym {
        0 => ()
        16 => {
          repeat_count = bitstream.peek_bits_prefilled(2).reinterpret_as_int() +
            3
          bitstream.consume_bits(2)
          if prev_sym == 16 {
            repeat_count += last_repeat_count * 3 - 8
            last_repeat_count += repeat_count
          } else {
            last_repeat_count = repeat_count
          }
          repeat_sym = last_nonzero_sym
          code_lengths[i] = repeat_sym
          repeat_count -= 1
        }
        17 => {
          repeat_count = bitstream.peek_bits_prefilled(3).reinterpret_as_int() +
            3
          bitstream.consume_bits(3)
          if prev_sym == 17 {
            repeat_count += last_repeat_count * 7 - 16
            last_repeat_count += repeat_count
          } else {
            last_repeat_count = repeat_count
          }
          repeat_sym = 0
          code_lengths[i] = repeat_sym
          repeat_count -= 1
        }
        _ => {
          // 1..=15
          code_lengths[i] = sym
          last_nonzero_sym = sym
        }
      }
      prev_sym = sym
    }
    let len = code_lengths[i]
    if len != 0 {
      bitacc += 1 <<
        (if len >= MAX_PREFIX_BITS { 0 } else { MAX_PREFIX_BITS - len })
      if bitacc > 1 << MAX_PREFIX_BITS {
        raise coding_error(PrefixSymbolTooLarge(bitacc))
      } else if bitacc == 1 << MAX_PREFIX_BITS && repeat_count == 0 {
        break
      }
    }
  }
  if bitacc != 1 << MAX_PREFIX_BITS || repeat_count > 0 {
    raise coding_error(InvalidPrefixHistogram)
  }
  PrefixHistogram::with_code_lengths(code_lengths)
}

///|
#inline
fn PrefixHistogram::read_symbol(
  self : PrefixHistogram,
  bitstream : @bitstream.Bitstream,
) -> Int32 raise @bitstream.JxlError {
  let peeked = bitstream.peek_bits(MAX_PREFIX_BITS)
  let toplevel_offset = (peeked & self.toplevel_mask).reinterpret_as_int()
  let toplevel_entry = self.toplevel_entries[toplevel_offset]
  if toplevel_entry >= 1 << 24 {
    let chunk_offset = (peeked.reinterpret_as_int() >> self.toplevel_bits) &
      ((toplevel_entry >> 16) & 0xff)
    let second_level_offset = (toplevel_entry & 0xffff) + chunk_offset
    let second_level_entry = self.second_level_entries[second_level_offset]
    bitstream.consume_bits((second_level_entry >> 16) & 0xff)
    second_level_entry & 0xffff
  } else {
    bitstream.consume_bits((toplevel_entry >> 16) & 0xff)
    toplevel_entry & 0xffff
  }
}

///|
/// The single symbol if this code always emits one symbol without reading
/// bits, or -1.
fn PrefixHistogram::single_symbol(self : PrefixHistogram) -> Int32 {
  if self.toplevel_entries.length() == 1 {
    let e = self.toplevel_entries[0]
    if e >> 16 == 0 {
      return e & 0xffff
    }
  }
  -1
}

///|
fn vec_reverse_bits(v : ArrayView[Int32], out : Array[Int32]) -> Unit {
  let len = v.length()
  // len is a power of two
  let mut bits = 0
  while 1 << bits < len {
    bits += 1
  }
  for idx in 0..<len {
    let mut rev_idx = 0
    for b in 0..<bits {
      rev_idx = rev_idx | (((idx >> b) & 1) << (bits - 1 - b))
    }
    out.push(v[rev_idx])
  }
}
