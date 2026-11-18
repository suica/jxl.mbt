Generators for the test vectors in src/coding/*_test.mbt (not part of the MoonBit module).
They run upstream jxl-oxide (Rust) and need a jxl-oxide checkout; paths assume the
session layout (worktree next to ../jxl-oxide); adjust Cargo.toml paths as needed.

fuzzgen/  `cargo run --release -- 400 12345 > src/coding/fuzz_cases_test.mbt`
          (differential cases on pseudo-random input)
          `cargo run --release --bin lz77case` (values in src/coding/lz77_test.mbt)
rec/      copy jxl-oxide, apply recorder.patch (adds a recorder to jxl-coding and
          Bitstream::debug_state), point Cargo.toml at the copy, then per file:
          `REC_CAP=200 REC_TOTAL=1000 target/release/rec input.jxl > rec_out/<name>.txt`
          and `python3 gen_mbt.py rec_out/*.txt > src/coding/replay_cases_test.mbt`.
          Files used: conformance grayscale, grayscale_jpeg, lz77_flower, sunset_logo,
          cmyk_layers, animation_icos4d, delta_palette, bike, progressive and
          jxl-oxide-tests benchmark-data/srgb.d0-e1.jxl (fast-lossless RLE).
