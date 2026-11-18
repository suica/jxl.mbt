// Port of jxl-jbr/src/reconstruct/scan.rs.

///|
priv struct ScanParams {
  si : ScanInfo
  smi : ScanMoreInfo
  upsampling_shifts_ycbcr : FixedArray[ChannelShift]
  hsamples : Array[Int32]
  vsamples : Array[Int32]
  max_hsample : Int32
  max_vsample : Int32
  w8 : Int32
  h8 : Int32
}

///|
priv struct ScanState {
  mut bit_writer : BitWriter
  dc_pred : FixedArray[Int32]
  mut eobrun : Int32
  mut last_ac_table : BuiltHuffmanTable?
  refinement_bitlen : Array[Int32]
  refinement_bits : Array[UInt64]
  mut rst_m : Int32
}

///|
fn ScanState::new(num_comps : Int32) -> ScanState {
  {
    bit_writer: BitWriter::new(),
    dc_pred: FixedArray::make(num_comps, 0),
    eobrun: 0,
    last_ac_table: None,
    refinement_bitlen: [],
    refinement_bits: [],
    rst_m: 0,
  }
}

///|
fn ScanState::try_init_ac_table(
  self : ScanState,
  ac_table : BuiltHuffmanTable,
) -> Unit {
  if self.last_ac_table is None {
    self.last_ac_table = Some(ac_table)
  }
}

///|
fn ScanState::update_ac_table(
  self : ScanState,
  ac_table : BuiltHuffmanTable,
) -> Unit {
  self.last_ac_table = Some(ac_table)
}

///|
/// Wraps to the `i16` range.
fn to_i16(x : Int32) -> Int32 {
  x << 16 >> 16
}

///|
fn ScanState::update_dc_pred(
  self : ScanState,
  comp_idx : Int32,
  coeff : Int32,
) -> Int32 {
  let diff = to_i16(coeff - self.dc_pred[comp_idx])
  self.dc_pred[comp_idx] = coeff
  diff
}

///|
fn ScanState::buffer_refinement_bits(
  self : ScanState,
  bits : UInt64,
  bitlen : Int32,
) -> Unit {
  self.refinement_bits.push(bits)
  self.refinement_bitlen.push(bitlen)
}

///|
/// Sign-extending conversion, as Rust's `i16 as u64`.
fn sx(x : Int32) -> UInt64 {
  x.to_int64().reinterpret_as_uint64()
}

///|
/// `16 - x.leading_zeros()` for a non-negative `i16` value.
fn bit_length16(x : Int32) -> Int32 {
  16 - (x & 0xffff).to_uint16().clz()
}

///|
fn ScanState::emit_eobrun(self : ScanState) -> Unit raise @bitstream.JxlError {
  if self.eobrun == 0 {
    return
  }
  let ac_table = match self.last_ac_table {
    Some(t) => t
    None => abort("last_ac_table not initialized")
  }
  let eobn = 31 - self.eobrun.clz()
  let (len, bits) = ac_table.lookup((eobn << 4) & 0xff)
  self.bit_writer.write_huffman(bits, len)
  let mask = (1 << eobn) - 1
  self.bit_writer.write_raw((self.eobrun & mask).to_uint64(), eobn)
  self.eobrun = 0
  for i in 0..<self.refinement_bits.length() {
    self.bit_writer.write_raw(
      self.refinement_bits[i],
      self.refinement_bitlen[i],
    )
  }
  self.refinement_bits.clear()
  self.refinement_bitlen.clear()
}

///|
fn ScanState::flush_bit_writer(
  self : ScanState,
  padding_bitstream : @bitstream.Bitstream?,
  writer : @buffer.Buffer,
) -> Unit raise @bitstream.JxlError {
  self.emit_eobrun()
  let bit_writer = self.bit_writer
  self.bit_writer = BitWriter::new()
  let padding_needed = bit_writer.padding_bits()
  if padding_needed != 0 {
    let bits = match padding_bitstream {
      Some(padding_bitstream) =>
        padding_bitstream.read_bits(padding_needed) catch {
          _ => raise err_invalid_data()
        }
      None => 0xFFFFFFFFU
    }
    bit_writer.write_raw(bits.to_uint64(), padding_needed)
  }
  let bytes = bit_writer.finalize()
  for b in bytes {
    writer.write_byte(b)
  }
}

///|
fn ScanState::restart(
  self : ScanState,
  padding_bitstream : @bitstream.Bitstream?,
  writer : @buffer.Buffer,
) -> Unit raise @bitstream.JxlError {
  self.dc_pred.fill(0)
  self.flush_bit_writer(padding_bitstream, writer)
  writer.write_byte(b'\xff')
  writer.write_byte((0xd0 + self.rst_m).to_byte())
  self.rst_m = (self.rst_m + 1) % 8
}

///|
/// Writes a (DC difference or AC) value: returns (raw bits, bit length).
fn encode_value(coeff : Int32) -> (UInt64, Int32) {
  if coeff < 0 {
    let coeff = to_i16(-coeff)
    (sx(coeff.lnot()), bit_length16(coeff))
  } else {
    (sx(coeff), bit_length16(coeff))
  }
}

///|
fn write_dc_diff(
  state : ScanState,
  dc_table : BuiltHuffmanTable,
  diff : Int32,
) -> Unit raise @bitstream.JxlError {
  let is_neg = diff < 0
  let bits = if is_neg { to_i16(-diff) } else { diff }
  let bitlen = bit_length16(bits)
  let raw_bits = if is_neg { to_i16(-bits - 1) } else { bits }
  let (len, code) = dc_table.lookup(bitlen)
  state.bit_writer.write_huffman(code, len)
  state.bit_writer.write_raw(sx(raw_bits), bitlen)
}

///|
fn process_sequential(
  state : ScanState,
  component_idx : Int32,
  dc_table : BuiltHuffmanTable,
  ac_table : BuiltHuffmanTable,
  dc : Int32,
  ac : FixedArray[Int32],
  extra_zero_runs : Int32?,
) -> Unit raise @bitstream.JxlError {
  let diff = state.update_dc_pred(component_idx, dc)
  write_dc_diff(state, dc_table, diff)
  let mut start = 0
  while true {
    let mut pos = start
    while pos < ac.length() && ac[pos] == 0 {
      pos += 1
    }
    if pos >= ac.length() {
      break
    }
    let mut nonzero_idx = pos - start
    let coeff = ac[pos]
    start = pos + 1
    while nonzero_idx >= 16 {
      let (len, bits) = ac_table.lookup(0xf0)
      state.bit_writer.write_huffman(bits, len)
      nonzero_idx -= 16
    }
    let (raw_bits, bitlen) = encode_value(coeff)
    let sym = ((nonzero_idx << 4) | bitlen) & 0xff
    let (len, bits) = ac_table.lookup(sym)
    state.bit_writer.write_huffman(bits, len)
    state.bit_writer.write_raw(raw_bits, bitlen)
  }
  let mut num_zeros = ac.length() - start
  if extra_zero_runs is Some(ezr) {
    let (len, bits) = ac_table.lookup(0xf0)
    for _ in 0..<ezr {
      state.bit_writer.write_huffman(bits, len)
    }
    num_zeros -= ezr * 16
  }
  if num_zeros > 0 {
    let (len, bits) = ac_table.lookup(0)
    state.bit_writer.write_huffman(bits, len)
  }
}

///|
fn process_progressive_first(
  state : ScanState,
  component_idx : Int32,
  dc_table : BuiltHuffmanTable,
  ac_table : BuiltHuffmanTable,
  dc : Int32?,
  ac : FixedArray[Int32],
  extra_zero_runs : Int32?,
) -> Unit raise @bitstream.JxlError {
  if dc is Some(dc) {
    let diff = state.update_dc_pred(component_idx, dc)
    state.emit_eobrun()
    write_dc_diff(state, dc_table, diff)
  }
  let mut start = 0
  while true {
    let mut pos = start
    while pos < ac.length() && ac[pos] == 0 {
      pos += 1
    }
    if pos >= ac.length() {
      break
    }
    state.emit_eobrun()
    let mut nonzero_idx = pos - start
    let coeff = ac[pos]
    start = pos + 1
    while nonzero_idx >= 16 {
      let (len, bits) = ac_table.lookup(0xf0)
      state.bit_writer.write_huffman(bits, len)
      nonzero_idx -= 16
    }
    let (raw_bits, bitlen) = encode_value(coeff)
    let sym = ((nonzero_idx << 4) | bitlen) & 0xff
    let (len, bits) = ac_table.lookup(sym)
    state.bit_writer.write_huffman(bits, len)
    state.bit_writer.write_raw(raw_bits, bitlen)
  }
  let mut num_zeros = ac.length() - start
  if extra_zero_runs is Some(ezr) {
    state.emit_eobrun()
    let (len, bits) = ac_table.lookup(0xf0)
    for _ in 0..<ezr {
      state.bit_writer.write_huffman(bits, len)
    }
    num_zeros -= ezr * 16
  }
  if state.eobrun == 0 {
    state.update_ac_table(ac_table)
  }
  if num_zeros > 0 {
    state.eobrun += 1
    if state.eobrun >= 32767 {
      state.emit_eobrun()
    }
  }
}

///|
fn process_progressive_refinement(
  state : ScanState,
  ac_table : BuiltHuffmanTable,
  dc : Int32?,
  ac : FixedArray[Int32],
  extra_zero_runs : Int32?,
) -> Unit raise @bitstream.JxlError {
  if dc is Some(dc) {
    state.emit_eobrun()
    state.bit_writer.write_raw(sx(dc), 1)
  }
  let mut start = 0
  while true {
    let mut pos = start
    while pos < ac.length() && ac[pos] != 1 && ac[pos] != -1 {
      pos += 1
    }
    if pos >= ac.length() {
      break
    }
    state.emit_eobrun()
    let mut zero_runs = 0
    let mut refinement_bitlen = 0
    let mut refinement_bits = 0UL
    for i in start..<pos {
      let coeff = ac[i]
      if coeff == 0 {
        zero_runs += 1
        if zero_runs == 16 {
          let (len, bits) = ac_table.lookup(0xf0)
          state.bit_writer.write_huffman(bits, len)
          state.bit_writer.write_raw(refinement_bits, refinement_bitlen)
          zero_runs = 0
          refinement_bitlen = 0
        }
      } else {
        refinement_bits = (refinement_bits << 1) | (coeff & 1).to_uint64()
        refinement_bitlen += 1
      }
    }
    let coeff = ac[pos]
    start = pos + 1
    let bit = if coeff == 1 { 1UL } else { 0UL }
    let sym = ((zero_runs << 4) | 1) & 0xff
    let (len, bits) = ac_table.lookup(sym)
    state.bit_writer.write_huffman(bits, len)
    state.bit_writer.write_raw(bit, 1)
    state.bit_writer.write_raw(refinement_bits, refinement_bitlen)
  }
  let mut remaining_zrl = match extra_zero_runs {
    Some(x) => x
    None => 0
  }
  if remaining_zrl > 0 {
    state.emit_eobrun()
  }
  let (zrl_len, zrl_bits) = if remaining_zrl > 0 {
    ac_table.lookup(0xf0)
  } else {
    (0, 0UL)
  }
  let mut zero_runs = 0
  let mut refinement_bitlen = 0
  let mut refinement_bits = 0UL
  for i in start..<ac.length() {
    let coeff = ac[i]
    if coeff == 0 {
      zero_runs += 1
      if remaining_zrl > 0 && zero_runs == 16 {
        state.bit_writer.write_huffman(zrl_bits, zrl_len)
        state.bit_writer.write_raw(refinement_bits, refinement_bitlen)
        zero_runs = 0
        refinement_bitlen = 0
        remaining_zrl -= 1
      }
    } else {
      refinement_bits = (refinement_bits << 1) | (coeff & 1).to_uint64()
      refinement_bitlen += 1
    }
  }
  for _ in 0..<remaining_zrl {
    state.bit_writer.write_huffman(zrl_bits, zrl_len)
    state.bit_writer.write_raw(refinement_bits, refinement_bitlen)
    zero_runs = 0
    refinement_bitlen = 0
  }
  if state.eobrun == 0 {
    state.update_ac_table(ac_table)
  }
  if zero_runs > 0 || refinement_bitlen > 0 {
    state.eobrun += 1
    state.buffer_refinement_bits(refinement_bits, refinement_bitlen)
    if state.eobrun >= 32767 {
      state.emit_eobrun()
    }
  }
}

///|
/// `process_scan::<TYPE>`: TYPE 0 = sequential, 1 = progressive first scan,
/// 2 = progressive refinement scan.
fn JpegBitstreamReconstructor::process_scan(
  self : JpegBitstreamReconstructor,
  ty : Int32,
  params : ScanParams,
  writer : @buffer.Buffer,
) -> Unit raise @bitstream.JxlError {
  guard ty < 3 else { abort("invalid scan type") }
  let {
    si,
    smi,
    upsampling_shifts_ycbcr,
    hsamples,
    vsamples,
    max_hsample,
    max_vsample,
    w8,
    h8,
  } = params
  let comps = si.component_info
  let info = self.info
  let dc_offset = self.parsed.dc_offset
  let ss = if si.ss > 1 { si.ss } else { 1 }
  let se = si.se + 1
  let al = si.al
  let group_dim = info.group_dim()
  let state = ScanState::new(comps.length())
  let mut block_idx = 0
  let ac_len = if se > ss { se - ss } else { 0 }
  for y8 in 0..<h8 {
    for x8 in 0..<w8 {
      let mcu_idx = x8 + w8 * y8
      if self.restart_interval is Some(restart_interval) &&
        mcu_idx != 0 &&
        mcu_idx % restart_interval == 0 {
        state.restart(self.padding_bitstream, writer)
      }
      let group_idx = match
        info.group_idx_from_coord(
          x8 << (3 + max_hsample),
          y8 << (3 + max_vsample),
        ) {
        Some(g) => g
        None => raise err_invalid_data()
      }
      let lf_group_idx = info.lf_group_idx_from_group_idx(group_idx)
      let hf_coeffs = self.parsed.pass_groups[group_idx]
      let lf_quants = self.parsed.lf_quant[lf_group_idx]
      for cidx in 0..<comps.length() {
        let c = comps[cidx]
        let hs = hsamples[cidx]
        let vs = vsamples[cidx]
        let dc_table = match self.dc_tables[c.dc_tbl_idx] {
          Some(t) => t
          None => empty_table
        }
        let ac_table = match self.ac_tables[c.ac_tbl_idx] {
          Some(t) => t
          None => empty_table
        }
        state.try_init_ac_table(ac_table)
        let idx = if info.do_ycbcr { c.comp_idx } else { [1, 0, 2][c.comp_idx] }
        let lf_quant = lf_quants[idx]
        let hf_coeff = hf_coeffs[idx]
        let dc_offset = dc_offset[idx]
        let shift = upsampling_shifts_ycbcr[idx]
        let (group_width, group_height) = shift.shift_size(group_dim, group_dim)
        let group_width_mask = group_width - 1
        let group_height_mask = group_height - 1
        for dy8 in 0..<vs {
          let y_dc = y8 * vs + dy8
          let y_ac_start = y_dc * 8
          let y_dc = y_dc & group_height_mask
          let y_ac_start = y_ac_start & group_height_mask
          for dx8 in 0..<hs {
            let x_dc = x8 * hs + dx8
            let x_ac_start = x_dc * 8
            let x_dc = x_dc & group_width_mask
            let x_ac_start = x_ac_start & group_width_mask
            let dc_coeff = if si.ss == 0 {
              let mut d = lf_quant.get(x_dc, y_dc) - dc_offset
              if d < -2047 {
                d = -2047
              } else if d > 2047 {
                d = 2047
              }
              Some(d >> al)
            } else {
              None
            }
            let ac_coeffs = FixedArray::make(ac_len, 0)
            for k in 0..<ac_len {
              let xy = dct8_natural_order[ss + k]
              let x = xy & 0xff
              let y = xy >> 8
              let coeff = to_i16(hf_coeff.get(x_ac_start + x, y_ac_start + y))
              ac_coeffs[k] = if coeff < 0 {
                -(to_i16(-coeff) >> al)
              } else {
                coeff >> al
              }
            }
            let extra_zero_runs = smi.extra_zero_runs.get(block_idx)
            if smi.reset_points.contains(block_idx) {
              state.emit_eobrun()
            }
            match ty {
              0 =>
                process_sequential(
                  state,
                  cidx,
                  dc_table,
                  ac_table,
                  dc_coeff.unwrap(),
                  ac_coeffs,
                  extra_zero_runs,
                )
              1 =>
                process_progressive_first(
                  state, cidx, dc_table, ac_table, dc_coeff, ac_coeffs, extra_zero_runs,
                )
              _ =>
                process_progressive_refinement(
                  state, ac_table, dc_coeff, ac_coeffs, extra_zero_runs,
                )
            }
            block_idx += 1
          }
        }
      }
    }
  }
  state.flush_bit_writer(self.padding_bitstream, writer)
}
