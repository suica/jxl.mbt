#!/usr/bin/env python3
"""Make instrumented copies of pxfm 0.1.30 for fixture generation.

Usage: vendor.py <pxfm-0.1.30 dir> <out dir>

Creates
  <out>/pxfm_instr   : pxfm with runtime FMA dispatch intact, slow paths flagged
  <out>/pxfm_generic : same, but the runtime dispatch never picks the FMA
                       implementation (what a CPU without AVX+FMA runs)
Each copy exports `hits() -> u32` / `reset_hits()`: a bit per slow path taken.
"""
import os, re, shutil, sys

SRC, OUT = sys.argv[1], sys.argv[2]

# (file, fn name, bit)
HOOKS = [
    ('pow.rs', 'f_powi', 0),
    ('pow.rs', 'f_powi_hard', 1),
    ('pow.rs', 'pow_rational128', 2),
    ('pow.rs', 'pow_exp2_fallback', 3),
    ('pow.rs', 'pow_exp10_fallback', 4),
    ('exponents/exp.rs', 'as_exp_accurate', 5),
    ('exponents/exp10.rs', 'as_exp10_accurate', 6),
    ('exponents/exp2.rs', 'exp2_accurate', 7),
    ('logs/log.rs', 'log_accurate_slow', 8),
    ('logs/log.rs', 'log_accurate_slow_td', 9),
    ('logs/log10.rs', 'log10_dd_accurate', 10),
    ('logs/log10.rs', 'log10_dd_accurate_slow', 11),
    ('powf.rs', 'powf_dd', 12),
    ('logs/log.rs', 'log_accurate', 13),
]

HELPER = '''
thread_local! {
    static PXFM_HITS: core::cell::Cell<u32> = const { core::cell::Cell::new(0) };
}
#[inline(never)]
pub(crate) fn hit(bit: u32) {
    PXFM_HITS.with(|h| h.set(h.get() | (1 << bit)));
}
/// Slow-path bits taken since the last reset.
pub fn hits() -> u32 {
    PXFM_HITS.with(|h| h.get())
}
pub fn reset_hits() {
    PXFM_HITS.with(|h| h.set(0));
}
'''

def make(name, generic):
    dst = os.path.join(OUT, name)
    if os.path.exists(dst):
        shutil.rmtree(dst)
    shutil.copytree(SRC, dst)
    cargo = open(os.path.join(dst, 'Cargo.toml')).read()
    cargo = cargo.replace('name = "pxfm"', 'name = "%s"' % name)
    open(os.path.join(dst, 'Cargo.toml'), 'w').write(cargo)
    os.remove(os.path.join(dst, 'Cargo.toml.orig'))
    srcd = os.path.join(dst, 'src')
    lib = os.path.join(srcd, 'lib.rs')
    open(lib, 'a').write(HELPER)
    for f, fn, bit in HOOKS:
        p = os.path.join(srcd, f)
        s = open(p).read()
        m = re.search(r'\bfn ' + fn + r'\b[^{]*\{', s)
        assert m, (f, fn)
        s = s[:m.end()] + '\n    crate::hit(%d);' % bit + s[m.end():]
        open(p, 'w').write(s)
    if generic:
        n = 0
        for root, _, files in os.walk(srcd):
            for fl in files:
                p = os.path.join(root, fl)
                s = open(p).read()
                t = s.replace('std::arch::is_x86_feature_detected!("fma")', 'false')
                if t != s:
                    n += 1
                    open(p, 'w').write(t)
        print(name, 'patched dispatch in', n, 'files')

make('pxfm_instr', False)
make('pxfm_generic', True)
