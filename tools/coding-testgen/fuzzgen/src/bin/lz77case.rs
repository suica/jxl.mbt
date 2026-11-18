// Builds an LZ77 + prefix-code stream exercising special distances and
// prints it with upstream's decoded values for several dist multipliers.
use jxl_bitstream::Bitstream;
use jxl_coding::Decoder;

struct W { bytes: Vec<u8>, n: usize }
impl W {
    fn bit(&mut self, b: u32) {
        if self.n % 8 == 0 { self.bytes.push(0); }
        if b & 1 == 1 { *self.bytes.last_mut().unwrap() |= 1 << (self.n % 8); }
        self.n += 1;
    }
    fn bits(&mut self, v: u32, n: usize) { for i in 0..n { self.bit(v >> i); } }
    // canonical prefix code, MSB first
    fn code(&mut self, c: u32, len: usize) { for i in (0..len).rev() { self.bit(c >> i); } }
}

fn main() {
    let mut w = W { bytes: vec![], n: 0 };
    w.bit(1); // lz77 enabled
    w.bits(0, 2); // min_symbol 224
    w.bits(0, 2); // min_length 3
    w.bits(8, 4); // lz_len_conf split_exponent 8
    // clusters for num_dist 2: simple, nbits 1, [0, 1]
    w.bit(1); w.bits(1, 2); w.bits(0, 1); w.bits(1, 1);
    w.bit(1); // prefix code
    w.bits(15, 4); w.bits(15, 4); // configs
    // counts: 257, 129
    w.bit(1); w.bits(8, 4); w.bits(0, 8);
    w.bit(1); w.bits(7, 4); w.bits(0, 7);
    // cluster 0: simple, 4 syms of len 2: 5, 7, 224, 225 (alphabet bits 9)
    w.bits(1, 2); w.bits(3, 2); for s in [5, 7, 224, 225] { w.bits(s, 9); } w.bit(0);
    // cluster 1: 1, 3, 119, 125 (alphabet bits 8)
    w.bits(1, 2); w.bits(3, 2); for s in [1, 3, 119, 125] { w.bits(s, 8); } w.bit(0);
    let header_bits = w.n;
    // body: literals then copies
    let lit = |w: &mut W, i: u32| w.code(i, 2); // 0 => 5, 1 => 7
    let mut x = 1u32;
    for _ in 0..40 { x = x.wrapping_mul(1103515245).wrapping_add(12345); lit(&mut w, (x >> 16) & 1); }
    for k in 0..24u32 {
        // copy: token 224 (len 3) or 225 (len 3 + 1 extra bit? token 225 >= split 256? no: 225-224=1 < 256 -> len 1+3)
        w.code(2 + (k & 1), 2);
        w.code((k / 2) % 4, 2);
        lit(&mut w, k & 1);
    }
    for _ in 0..8 { w.bits(0, 8); }
    let hex: String = w.bytes.iter().map(|b| format!("{b:02x}")).collect();
    println!("hex {hex} header_bits {header_bits}");
    for mult in [0u32, 1, 5, 64] {
        let mut bs = Bitstream::new(&w.bytes);
        let mut dec = Decoder::parse(&mut bs, 1).unwrap();
        let mut out = vec![];
        for _ in 0..200 {
            match dec.read_varint_with_multiplier(&mut bs, 0, mult) {
                Ok(v) => out.push(v),
                Err(_) => break,
            }
        }
        println!("mult {mult} n {} bits {} vals {:?}", out.len(), bs.num_read_bits(), out);
    }
}
