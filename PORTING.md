# Porting conventions (jxl-oxide → MoonBit)

Upstream: jxl-oxide 0.12.6, commit `c0cc4c7ea57c1207f38ff2970d94757470613be4`.
A checkout lives at `../jxl-oxide` next to the main working copy (session workspace).

## Package map

| jxl-oxide crate / module            | MoonBit package (`suica/jxl/...`) | directory          |
|-------------------------------------|-----------------------------------|--------------------|
| jxl-bitstream (bitstream, error), jxl-oxide-common | `bitstream`        | `src/bitstream`    |
| jxl-bitstream `container`           | `container`                       | `src/container`    |
| jxl-grid                            | `grid`                            | `src/grid`         |
| jxl-coding                          | `coding`                          | `src/coding`       |
| jxl-color (headers, icc, tf, convert, xyb, ycbcr, cms trait) | `color`  | `src/color`        |
| jxl-image                           | `image`                           | `src/image`        |
| jxl-modular                         | `modular`                         | `src/modular`      |
| jxl-frame                           | `frame`                           | `src/frame`        |
| jxl-vardct                          | `vardct`                          | `src/vardct`       |
| jxl-render                          | `render`                          | `src/render`       |
| jxl-jbr                             | `jbr`                             | `src/jbr`          |
| brotli-decompressor (dependency)    | `brotli`                          | `src/brotli`       |
| an ICC CMS (moxcms/lcms2 role)      | `cms`                             | `src/cms`          |
| jxl-oxide (public API)              | root package `suica/jxl`          | `src`              |
| mbui adapter `decode_jxl`           | root package                      | `src`              |
| jxl-oxide-tests                     | separate module `suica/jxl_tests` | `tests/`           |

The published module `suica/jxl` has **no dependencies** besides `moonbitlang/core`.
Test-only dependencies (e.g. `moonbitlang/x/fs`) live in the `tests/` module.

## Naming and types

- Keep upstream names: Rust `Foo::bar(&self, ..)` → MoonBit `Foo::bar(self, ..)`;
  free fns keep snake_case names; struct fields keep their names; enum variants keep their names.
  A dependent package written before its dependency is merged codes against these mirrored names.
- Data structs are `pub(all) struct` (fields readable by other packages); mutable state uses `mut` fields.
- `u8/u16/u32/i32/usize/isize` → `Int` unless unsigned 32-bit wrap/shift semantics matter (then `UInt`).
  `u64` → `UInt64`, `i64` → `Int64`. `f32` → `Float` (keep f32 precision for sample data), `f64` → `Double`.
- `Option<T>` → `T?`. `Result<T, E>` → `T raise @bitstream.JxlError` (one error type for the whole decoder;
  pick the closest variant, put upstream's variant name in the String payload, e.g. `Decoder("InvalidAnsHistogram")`).
- `Bundle::parse(bitstream, ctx)` → `Type::parse(bs : @bitstream.Bitstream, ctx..) -> Type raise JxlError`
  (a static function; ctx as extra positional args). `default_with_context` → `Type::default(..)`.
  `read_bits!(bs, U32(0, u(4), 16 + u(5), 48 + u(10)))` →
  `bs.read_u32(@bitstream.c(0), @bitstream.u(4), @bitstream.cu(16, 5), @bitstream.cu(48, 10))`.
  `Enum(T)` → `bs.read_enum_raw()` then map, raising `InvalidEnum("T", v)`.
- `AlignedGrid<T>` → `@grid.Grid[T]`; `SharedSubgrid`/`MutableSubgrid` → `@grid.SubGrid[T]` (views share the
  buffer). Rust code that reinterprets an f32 grid as i32 must use a separate `Grid[Int]` (or explicit conversion).
- Threads/rayon/threadpool: run sequentially. SIMD: port only the generic (scalar) implementation.
- `tracing` logs: drop.

## Code style

- MoonBit blocks separated by `///|`. Run `moon fmt` and `moon info` before committing; commit the
  `pkg.generated.mbti`.
- Hot loops: `FixedArray`, plain `for`/`while`, no closures per sample. Tests must run on both
  `--target wasm-gc` and `--target native` with identical results.
- Keep the upstream file split where practical (`ans.mbt`, `prefix.mbt`, ...), so a reader can diff
  against the Rust file. Copy upstream doc comments where they explain behavior.
- Unit tests: port upstream `#[cfg(test)]` tests of the module; add small tests of your own.

## Toolchain

```sh
export MOON_HOME=<session workspace>/moonhome PATH=<session workspace>/moonhome/bin:$PATH
moon check --target native && moon test --target native && moon test --target wasm-gc
```
