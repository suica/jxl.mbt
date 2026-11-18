# jxl.mbt

A JPEG XL decoder written in pure MoonBit.

This is a port of [jxl-oxide](https://github.com/tirr-c/jxl-oxide) by Wonwoo Choi
and contributors (ported from jxl-oxide 0.12.6, commit `c0cc4c7ea57c`).
The structure of the packages follows jxl-oxide's crates.

**Status: work in progress.**

## License

Like jxl-oxide, this project is dual-licensed under either of

- MIT license ([LICENSE-MIT](LICENSE-MIT))
- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE))

at your option. The copyright of the original jxl-oxide code belongs to
Wonwoo Choi and the jxl-oxide contributors.

### Third-party code

- `src/brotli` is a port of Google's Brotli C decoder
  ([google/brotli](https://github.com/google/brotli) v1.1.0, `c/dec` and `c/common`),
  Copyright 2013 Google Inc., MIT License. Its test vectors come from google/brotli
  `tests/testdata` (MIT).
