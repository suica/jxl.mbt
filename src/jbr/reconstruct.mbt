// Port of jxl-jbr/src/reconstruct.rs (writer part; frame decoding lives in
// `reconstruct_frame.mbt`).

///|
/// JPEG bitstream reconstruction context.
pub struct JpegBitstreamReconstructor {
  priv parsed : ParsedFrameData
  priv info : JpegFrameInfo
  priv mut is_progressive : Bool
  priv mut restart_interval : Int32?
  priv dc_tables : FixedArray[BuiltHuffmanTable?]
  priv ac_tables : FixedArray[BuiltHuffmanTable?]
  priv header : JpegBitstreamHeader
  priv data : Bytes
  priv mut marker_ptr : Int32
  priv mut app_marker_ptr : Int32
  priv mut next_icc_marker : Int32
  priv mut icc_marker_offset : Int32
  priv num_icc_markers : Int32
  /// Current position / end of the APP data section in `data`.
  priv mut app_data : Int32
  priv app_data_end : Int32
  priv mut com_length : Int32
  priv mut com_data : Int32
  priv com_data_end : Int32
  priv mut intermarker_length : Int32
  priv mut intermarker_data : Int32
  priv intermarker_data_end : Int32
  priv mut huffman_code_ptr : Int32
  priv mut quant_ptr : Int32
  priv mut last_quant_val : FixedArray[Int32]?
  priv padding_bitstream : @bitstream.Bitstream?
  priv mut scan_info_ptr : Int32
  priv tail_data : Int32
  priv icc_profile : Bytes
  priv exif : Bytes
  priv xmp : Bytes
}

///|
/// Creates a reconstruction context from already decoded frame data.
///
/// `data` is the decompressed data section of the jbrd box
/// (`JpegBitstreamData::data`). `icc_profile`, `exif` or `xmp` can be empty
/// if no corresponding metadata was found.
pub fn JpegBitstreamReconstructor::from_parsed(
  header : JpegBitstreamHeader,
  data : Bytes,
  info : JpegFrameInfo,
  parsed : ParsedFrameData,
  icc_profile : Bytes,
  exif : Bytes,
  xmp : Bytes,
) -> JpegBitstreamReconstructor raise @bitstream.JxlError {
  check_metadata_lengths(header, icc_profile, exif, xmp)
  let com_data_start = header.app_data_len()
  let intermarker_data_start = com_data_start + header.com_data_len()
  let tail_data_start = intermarker_data_start + header.intermarker_data_len()
  if data.length() < tail_data_start {
    raise err_invalid_data()
  }
  let mut num_icc_markers = 0
  for am in header.app_markers {
    if am.ty == 1 {
      num_icc_markers += 1
    }
  }
  {
    parsed,
    info,
    is_progressive: false,
    restart_interval: None,
    dc_tables: [None, None, None, None],
    ac_tables: [None, None, None, None],
    header,
    data,
    marker_ptr: 0,
    app_marker_ptr: 0,
    next_icc_marker: 0,
    icc_marker_offset: 0,
    num_icc_markers,
    app_data: 0,
    app_data_end: com_data_start,
    com_length: 0,
    com_data: com_data_start,
    com_data_end: intermarker_data_start,
    intermarker_length: 0,
    intermarker_data: intermarker_data_start,
    intermarker_data_end: tail_data_start,
    huffman_code_ptr: 0,
    quant_ptr: 0,
    last_quant_val: None,
    padding_bitstream: header.padding_bits.map(fn(padding) {
      @bitstream.Bitstream::new(Bytes::from_array(padding.bits))
    }),
    scan_info_ptr: 0,
    tail_data: tail_data_start,
    icc_profile,
    exif,
    xmp,
  }
}

///|
fn check_metadata_lengths(
  header : JpegBitstreamHeader,
  icc_profile : Bytes,
  exif : Bytes,
  xmp : Bytes,
) -> Unit raise @bitstream.JxlError {
  let expected_icc_len = header.expected_icc_len()
  let expected_exif_len = header.expected_exif_len()
  let expected_xmp_len = header.expected_xmp_len()
  if expected_icc_len > 0 && expected_icc_len != icc_profile.length() {
    // ICC profile length doesn't match expected length
    raise err_invalid_data()
  }
  if expected_exif_len > 0 && expected_exif_len != exif.length() {
    // Exif metadata length doesn't match expected length
    raise err_invalid_data()
  }
  if expected_xmp_len > 0 && expected_xmp_len != xmp.length() {
    // XMP metadata length doesn't match expected length
    raise err_invalid_data()
  }
}

///|
/// Writes reconstructed JPEG bitstream to the writer.
pub fn JpegBitstreamReconstructor::write(
  self : JpegBitstreamReconstructor,
  writer : @buffer.Buffer,
) -> Unit raise @bitstream.JxlError {
  writer.write_byte(b'\xff')
  writer.write_byte(b'\xd8')
  while self.marker_ptr < self.header.markers.length() {
    self.process_next(writer)
    self.marker_ptr += 1
  }
}

///|
/// Reconstructs the JPEG file and returns its bytes.
pub fn JpegBitstreamReconstructor::to_bytes(
  self : JpegBitstreamReconstructor,
) -> Bytes raise @bitstream.JxlError {
  let buf = Buffer()
  self.write(buf)
  buf.to_bytes()
}

///|
fn write_u16_be(writer : @buffer.Buffer, v : Int32) -> Unit {
  writer.write_byte(((v >> 8) & 0xff).to_byte())
  writer.write_byte((v & 0xff).to_byte())
}

///|
fn write_slice(
  writer : @buffer.Buffer,
  data : Bytes,
  start : Int32,
  len : Int32,
) -> Unit {
  writer.write_bytesview(data[start:start + len])
}

///|
fn JpegBitstreamReconstructor::process_next(
  self : JpegBitstreamReconstructor,
  writer : @buffer.Buffer,
) -> Unit raise @bitstream.JxlError {
  let marker = self.header.markers[self.marker_ptr]
  match marker {
    // SOF
    0xc0 | 0xc1 | 0xc2 | 0xc9 | 0xca => {
      self.is_progressive = marker == 0xc2 || marker == 0xca
      let width = self.info.image_width
      let height = self.info.image_height
      let num_comps = self.header.components.length()
      let encoded_len = 8 + num_comps * 3
      writer.write_byte(b'\xff')
      writer.write_byte(marker.to_byte())
      write_u16_be(writer, encoded_len)
      writer.write_byte(b'\x08')
      write_u16_be(writer, height)
      write_u16_be(writer, width)
      writer.write_byte(num_comps.to_byte())
      let jpeg_upsampling_ycbcr = self.info.jpeg_upsampling_ycbcr()
      for idx, comp in self.header.components {
        let sampling_factor = if idx < jpeg_upsampling_ycbcr.length() {
          jpeg_upsampling_ycbcr[idx]
        } else {
          0
        }
        let sampling_val = match sampling_factor {
          0 => 0b01_0001
          1 => 0b10_0010
          2 => 0b10_0001
          3 => 0b01_0010
          _ => 0b01_0001
        }
        writer.write_byte(comp.id.to_byte())
        writer.write_byte(sampling_val.to_byte())
        writer.write_byte(comp.q_idx.to_byte())
      }
    }

    // DHT
    0xc4 => {
      let codes = self.header.huffman_codes
      let start = self.huffman_code_ptr
      let mut last_idx = start
      while last_idx < codes.length() && !codes[last_idx].is_last {
        last_idx += 1
      }
      if last_idx >= codes.length() {
        abort("is_last not found")
      }
      let end = last_idx + 1
      self.huffman_code_ptr = end
      let mut encoded_len = 2
      for i in start..<end {
        encoded_len += codes[i].encoded_len()
      }
      writer.write_byte(b'\xff')
      writer.write_byte(b'\xc4')
      write_u16_be(writer, encoded_len)
      for i in start..<end {
        let hc = codes[i]
        let id_and_counts = FixedArray::make(17, 0)
        id_and_counts[0] = hc.id | (if hc.is_ac { 0x10 } else { 0 })
        for k in 1..<17 {
          id_and_counts[k] = hc.counts[k]
        }
        for k = 16; k >= 1; k = k - 1 {
          if id_and_counts[k] != 0 {
            id_and_counts[k] -= 1
            break
          }
        }
        for v in id_and_counts {
          writer.write_byte(v.to_byte())
        }
        for k in 0..<(hc.values.length() - 1) {
          writer.write_byte(hc.values[k].to_byte())
        }
        let table = hc.build()
        if hc.is_ac {
          self.ac_tables[hc.id] = Some(table)
        } else {
          self.dc_tables[hc.id] = Some(table)
        }
      }
    }

    // RSTn
    0xd0..<=0xd7 => {
      writer.write_byte(b'\xff')
      writer.write_byte(marker.to_byte())
    }

    // EOI
    0xd9 => {
      writer.write_byte(b'\xff')
      writer.write_byte(b'\xd9')
      write_slice(
        writer,
        self.data,
        self.tail_data,
        self.data.length() - self.tail_data,
      )
    }

    // SOS
    0xda => {
      let info = self.info
      let idx = self.scan_info_ptr
      let si = self.header.scan_info[idx]
      let smi = self.header.scan_more_info[idx]
      self.scan_info_ptr += 1
      if si.component_info.is_empty() {
        // No component in SOS marker
        raise err_invalid_data()
      }
      let num_comps = si.num_comps()
      writer.write_byte(b'\xff')
      writer.write_byte(b'\xda')
      write_u16_be(writer, 6 + 2 * num_comps)
      writer.write_byte(num_comps.to_byte())
      let comps = si.component_info
      for c in comps {
        let id = self.header.components[c.comp_idx].id
        let table = (c.dc_tbl_idx << 4) | c.ac_tbl_idx
        writer.write_byte(id.to_byte())
        writer.write_byte(table.to_byte())
      }
      writer.write_byte(si.ss.to_byte())
      writer.write_byte(si.se.to_byte())
      writer.write_byte(((si.ah << 4) | si.al).to_byte())
      let jpeg_upsampling_ycbcr = info.jpeg_upsampling_ycbcr()
      let upsampling_shifts_ycbcr = FixedArray::makei(3, fn(idx) {
        ChannelShift::from_jpeg_upsampling(jpeg_upsampling_ycbcr, idx)
      })
      let mut hsamples = comps.map(fn(c) {
        [1, 2, 2, 1][jpeg_upsampling_ycbcr[c.comp_idx]]
      })
      let mut vsamples = comps.map(fn(c) {
        [1, 2, 1, 2][jpeg_upsampling_ycbcr[c.comp_idx]]
      })
      let mut max_h = 0
      for h in hsamples {
        if h > max_h {
          max_h = h
        }
      }
      let mut max_v = 0
      for v in vsamples {
        if v > max_v {
          max_v = v
        }
      }
      let mut max_hsample = max_h.ctz()
      let mut max_vsample = max_v.ctz()
      let mut w8 = (div_ceil(info.width, 8) + max_hsample) >> max_hsample
      let mut h8 = (div_ceil(info.height, 8) + max_vsample) >> max_vsample
      if num_comps == 1 {
        let full_w8 = div_ceil(info.width, 8)
        let full_h8 = div_ceil(info.height, 8)
        if 1 << max_hsample == hsamples[0] {
          w8 = full_w8
          max_hsample = 0
        }
        if 1 << max_vsample == vsamples[0] {
          h8 = full_h8
          max_vsample = 0
        }
        hsamples = [1]
        vsamples = [1]
      }
      let params : ScanParams = {
        si,
        smi,
        upsampling_shifts_ycbcr,
        hsamples,
        vsamples,
        max_hsample,
        max_vsample,
        w8,
        h8,
      }
      if !self.is_progressive {
        if si.ss != 0 || si.se != 0x3f || si.al != 0 || si.ah != 0 {
          // Progressive parameter set for sequential JPEG
          raise err_invalid_data()
        }
        self.process_scan(0, params, writer)
      } else if si.ah == 0 {
        self.process_scan(1, params, writer)
      } else {
        self.process_scan(2, params, writer)
      }
    }

    // DQT
    0xdb => {
      let do_ycbcr = self.info.do_ycbcr
      let qts_all = self.header.quant_tables
      let start = self.quant_ptr
      let mut last_idx = start
      while last_idx < qts_all.length() && !qts_all[last_idx].is_last {
        last_idx += 1
      }
      if last_idx >= qts_all.length() {
        abort("is_last not found")
      }
      let end = last_idx + 1
      let num_tables = end - start
      self.quant_ptr = end
      let mut num_precise = 0
      for i in start..<end {
        if qts_all[i].precision != 0 {
          num_precise += 1
        }
      }
      let encoded_len = 2 + 65 * num_tables + 64 * num_precise
      writer.write_byte(b'\xff')
      writer.write_byte(b'\xdb')
      write_u16_be(writer, encoded_len)
      for i in start..<end {
        let qt = qts_all[i]
        let mut channel = -1
        for ci, c in self.header.components {
          if c.q_idx == qt.index {
            channel = ci
            break
          }
        }
        let q = if channel < 0 {
          None
        } else {
          let ch = if do_ycbcr && channel <= 1 { channel ^ 1 } else { channel }
          self.parsed.jpeg_quant_values_of(ch)
        }
        if q is Some(q) {
          let q_val = match self.last_quant_val {
            Some(v) => v
            None => {
              let v = FixedArray::make(64, 0)
              self.last_quant_val = Some(v)
              v
            }
          }
          // Transposed for DCT8
          for k in 0..<64 {
            let yx = dct8_natural_order[k]
            let y = yx & 0xff
            let x = yx >> 8
            q_val[k] = q[x + 8 * y] & 0xffff
          }
        }
        let q_val = match self.last_quant_val {
          Some(v) => v
          None => raise err_invalid_data()
        }
        if qt.precision == 0 {
          writer.write_byte(qt.index.to_byte())
          for k in 0..<64 {
            writer.write_byte((q_val[k] & 0xff).to_byte())
          }
        } else {
          writer.write_byte((qt.index | (qt.precision << 4)).to_byte())
          for k in 0..<64 {
            write_u16_be(writer, q_val[k])
          }
        }
      }
    }

    // DRI
    0xdd => {
      let interval = self.header.restart_interval & 0xffff
      writer.write_byte(b'\xff')
      writer.write_byte(b'\xdd')
      writer.write_byte(b'\x00')
      writer.write_byte(b'\x04')
      write_u16_be(writer, interval)
      if self.header.restart_interval != 0 {
        self.restart_interval = Some(self.header.restart_interval)
      }
    }

    // APPn
    0xe0..<=0xef => {
      let am = self.header.app_markers[self.app_marker_ptr]
      self.app_marker_ptr += 1
      let encoded_len = (am.length - 1) & 0xffff
      match am.ty {
        0 => {
          writer.write_byte(b'\xff')
          if self.app_data + am.length > self.app_data_end {
            abort("app data out of range")
          }
          write_slice(writer, self.data, self.app_data, am.length)
          self.app_data += am.length
        }
        1 => {
          writer.write_byte(b'\xff')
          writer.write_byte(b'\xe2')
          write_u16_be(writer, encoded_len)
          writer.write_bytes(header_icc)
          let curr = self.next_icc_marker + 1
          let total = self.num_icc_markers
          writer.write_byte(curr.to_byte())
          writer.write_byte(total.to_byte())
          let from = self.icc_marker_offset
          let len = am.length - 5 - header_icc.length()
          self.next_icc_marker += 1
          self.icc_marker_offset += len
          write_slice(writer, self.icc_profile, from, len)
        }
        2 => {
          writer.write_byte(b'\xff')
          writer.write_byte(b'\xe1')
          write_u16_be(writer, encoded_len)
          writer.write_bytes(header_exif)
          writer.write_bytes(self.exif)
        }
        3 => {
          writer.write_byte(b'\xff')
          writer.write_byte(b'\xe1')
          write_u16_be(writer, encoded_len)
          writer.write_bytes(header_xmp)
          writer.write_bytes(self.xmp)
        }
        _ => abort("unreachable")
      }
    }

    // COM
    0xfe => {
      let length = self.header.com_lengths[self.com_length]
      self.com_length += 1
      if self.com_data + length > self.com_data_end {
        abort("com data out of range")
      }
      writer.write_byte(b'\xff')
      writer.write_byte(b'\xfe')
      write_slice(writer, self.data, self.com_data, length)
      self.com_data += length
    }

    // Unrecognized
    0xff => {
      let length = self.header.intermarker_lengths[self.intermarker_length]
      self.intermarker_length += 1
      if self.intermarker_data + length > self.intermarker_data_end {
        abort("intermarker data out of range")
      }
      write_slice(writer, self.data, self.intermarker_data, length)
      self.intermarker_data += length
    }
    _ =>
      // Unknown marker
      raise err_invalid_data()
  }
}
