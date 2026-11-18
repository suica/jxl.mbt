// End-to-end test on real files: replays entropy decoder operations recorded
// from upstream jxl-oxide while it decoded conformance / jxl-oxide test images
// (ICC stream, MA trees, modular channels incl. LZ77 and fast-lossless RLE,
// VarDCT coefficients, TOC permutations), checking every decoded value and the
// exact bit position after each operation.

///|
fn replay_one(name : String, log : String) -> Unit raise {
  let snaps : Map[Int32, (Bytes, Int32)] = Map([])
  let decs : Map[Int32, @coding.Decoder] = Map([])
  let open_bs = fn(sid : Int32, rel : Int32) raise {
    let (bytes, pad) = snaps.get(sid).unwrap()
    let bs = @bitstream.Bitstream::new(bytes)
    bs.skip_bits(pad + rel)
    (bs, pad)
  }
  let check_pos = fn(
    line : StringView,
    bs : @bitstream.Bitstream,
    pad : Int32,
    rel_after : Int32,
  ) raise {
    if bs.num_read_bits() - pad != rel_after {
      fail(
        "\{name}: `\{line}`: position \{bs.num_read_bits() - pad} != \{rel_after}",
      )
    }
  }
  for line in log.split("\n") {
    if line.is_empty() {
      continue
    }
    let f = line.split(" ").collect()
    let int = fn(i : Int32) raise { @string.parse_int(f[i]) }
    match f[0] {
      "S" => snaps.set(int(1), (hex_to_bytes(f[3].to_owned()), int(2)))
      "P" => {
        let (bs, pad) = open_bs(int(2), int(3))
        let dec = @coding.Decoder::parse(bs, int(4))
        check_pos(line, bs, pad, int(5))
        decs.set(int(1), dec)
      }
      "C" => decs.set(int(2), decs.get(int(1)).unwrap().clone())
      "B" => {
        let (bs, pad) = open_bs(int(2), int(3))
        let ok = try decs.get(int(1)).unwrap().begin(bs) catch {
          _ => false
        } noraise {
          _ => true
        }
        if ok != (int(4) == 1) {
          fail("\{name}: `\{line}`: begin result differs")
        }
        if ok {
          check_pos(line, bs, pad, int(5))
        }
      }
      "F" => {
        let ok = try decs.get(int(1)).unwrap().finalize() catch {
          _ => false
        } noraise {
          _ => true
        }
        if ok != (int(2) == 1) {
          fail("\{name}: `\{line}`: finalize result differs")
        }
      }
      "R" => {
        let dec = decs.get(int(1)).unwrap()
        let (bs, pad) = open_bs(int(2), int(3))
        let kind = int(4)
        let cluster = int(5)
        let mult = int(6)
        let got = try {
          if kind == 2 {
            match dec.as_rle().unwrap().read_varint_clustered(bs, cluster) {
              Value(v) => v.to_string()
              Repeat(v) => "r\{v}"
            }
          } else {
            dec
            .read_varint_with_multiplier_clustered(bs, cluster, mult)
            .to_string()
          }
        } catch {
          _ => "E"
        }
        if got != f[7].to_owned() {
          fail("\{name}: `\{line}`: got \{got}")
        }
        if got != "E" {
          check_pos(line, bs, pad, int(8))
        }
      }
      _ => fail("bad line \{line}")
    }
  }
}

///|
test "replay recorded upstream decoder operations on real files" {
  for case in replay_logs {
    let (name, log) = case
    replay_one(name, log)
  }
}
