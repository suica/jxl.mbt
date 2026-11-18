// Ported from pxfm 0.1.30 (https://github.com/awxkee/pxfm),
// Copyright (c) Radzivon Bartoshyk. All rights reserved.
// BSD-3-Clause OR Apache-2.0 (see upstream LICENSE.md / LICENSE-APACHE.md).
//
// Port of `cube_roots/cbrtf.rs` (`f_cbrtf`). On x86_64 `f_cbrtf` chooses at
// run time between `GenericCbrtBackend` (`halley_refine_d`) and
// `FmaCbrtBackend` (`halley_refine_d_fma`); `fma` selects the backend and the
// public function uses the FMA one (x86_64 CPUs with AVX and FMA).

///|
/// `halley_refine_d` / `halley_refine_d_fma`.
fn halley_refine_d(x : Double, a : Double, fma : Bool) -> Double {
  let tx = x * x * x
  if fma {
    x * fma_f64(2.0, a, tx) / fma_f64(2.0, tx, a)
  } else {
    x * f_fmla(2.0, a, tx) / f_fmla(2.0, tx, a)
  }
}

///|
/// `cbrtf_gen_impl::<B>`.
fn cbrtf_gen(x : Float, fma : Bool) -> Float {
  let u = tbf(x)
  let au = u << 1
  if au < 1U << 24 || au >= 0xffU << 24 {
    if au >= 0xffU << 24 {
      return x + x // inf, nan
    }
    if au == 0U {
      return x // +-0
    }
  }
  let mut ui = tbf(x)
  let mut hx = ui & 0x7fffffffU
  if hx < 0x00800000U {
    // zero or subnormal?
    if hx == 0U {
      return x // cbrt(+-0) is itself
    }
    ui = tbf(x * fbf(0x4b800000U)) // 2^24
    hx = ui & 0x7fffffffU
    hx = hx / 3U + 642849266U
  } else {
    hx = hx / 3U + 709958130U
  }
  ui = ui & 0x80000000U
  ui = ui | hx
  let mut t = fbf(ui).to_double()
  let dx = x.to_double()
  t = halley_refine_d(t, dx, fma)
  Float::from_double(halley_refine_d(t, dx, fma))
}

///|
/// Computes cube root.
///
/// Peak ULP on 64 bit = 0.49999577. Port of pxfm `f_cbrtf` with
/// `FmaCbrtBackend`.
pub fn f_cbrtf(x : Float) -> Float {
  cbrtf_gen(x, true)
}
