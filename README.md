# jxl.mbt

A JPEG XL decoder written in pure MoonBit.

This is a port of [jxl-oxide](https://github.com/tirr-c/jxl-oxide) by Wonwoo Choi
and contributors (ported from jxl-oxide 0.12.6, commit `c0cc4c7ea57c`).
The structure of the packages follows jxl-oxide's crates.

**Status: work in progress.**

## Not supported

The colour management system in `src/cms` (a port of Little CMS 2.19's float
transform path) does not support:

- floating-point profile tags (`mpet`, `D2Bx`/`B2Dx`); profiles relying on them
  are rejected with `NotSupported`;
- named-colour, device-link and abstract profiles as transform endpoints;
- black-preserving rendering intents (10–15);
- partial chromatic adaptation (the adaptation state is fixed at 1.0).

None of these occur in the libjxl conformance suite or jxl-oxide's test images.

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
