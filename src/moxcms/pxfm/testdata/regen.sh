#!/bin/sh
# Regenerates the pxfm port's tables and test data from pxfm 0.1.30.
#
#   regen.sh <work dir> [tables|fixtures|digests|all] [mine_per_variant]
#
# Needs cargo with pxfm 0.1.30 in the registry (crates.io) and python3; run on
# x86_64 Linux with an AVX+FMA CPU (that is the reference the fixtures encode).
# Nothing is written inside the repository except the generated .mbt files.
#   tables   : *_tables.mbt from the pxfm sources (gen_tables.py)
#   fixtures : fixtures_data_wbtest.mbt (specials, regular samples and inputs
#              that take each slow path, mined over <mine_per_variant> inputs)
#   digests  : fuzz_data_wbtest.mbt (per-chunk digests of the fuzz streams;
#              `PXFM_FUZZ_FULL=1 moon test -p suica/jxl/moxcms/pxfm` runs all)
set -eu
WORK=$1
WHAT=${2:-all}
MINE=${3:-4000000000}
HERE=$(cd "$(dirname "$0")" && pwd)
PKG=$(dirname "$HERE")
PXFM=$(ls -d "${CARGO_HOME:-$HOME/.cargo}"/registry/src/*/pxfm-0.1.30 | head -n 1)
mkdir -p "$WORK/vendor" "$WORK/fixgen"
if [ "$WHAT" = tables ] || [ "$WHAT" = all ]; then
  python3 "$HERE/gen_tables.py" "$PXFM/src" "$PKG"
fi
python3 "$HERE/vendor.py" "$PXFM" "$WORK/vendor"
cp -r "$HERE/fixgen/Cargo.toml" "$HERE/fixgen/src" "$WORK/fixgen/"
(cd "$WORK/fixgen" && cargo build --release)
BIN=$WORK/fixgen/target/release/pxfm-fixgen
if [ "$WHAT" = fixtures ] || [ "$WHAT" = all ]; then
  "$BIN" fixtures "$WORK/fixtures.txt" "$MINE" 80 400
  python3 "$HERE/fixtures_to_mbt.py" "$WORK/fixtures.txt" "$PKG/fixtures_data_wbtest.mbt"
fi
if [ "$WHAT" = digests ] || [ "$WHAT" = all ]; then
  "$BIN" digests "$PKG/fuzz_data_wbtest.mbt" 16
fi
