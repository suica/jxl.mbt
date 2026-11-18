#!/usr/bin/env bash
# Prepare test fixtures for the `suica/jxl_tests` module in fixtures/cache/
# (gitignored), using only system tools (git, curl, zstd).
#
#   fixtures/cache/conformance/<case>/{input.jxl,reference_image.npy,reference.icc,test.json}
#       libjxl conformance testcases (incl. the *_5 level-5 variants)
#   fixtures/cache/decode/<case>/{input.jxl,output.buf}
#       jxl-oxide decode test data; output.buf is the decompressed output.buf.zst
#
# Sources (override with environment variables):
#   CONFORMANCE_DIR   existing checkout of https://github.com/libjxl/conformance
#                     whose reference objects are already downloaded and
#                     symlinked (scripts/download_and_symlink*.sh). It is linked,
#                     not copied. If unset, the repo is cloned into
#                     fixtures/cache/conformance-repo and its download script runs.
#   DECODE_DIR        existing checkout of https://github.com/tirr-c/jxl-oxide-testdata
#                     (jxl-oxide's crates/jxl-oxide-tests/decode). If unset, it is
#                     cloned into fixtures/cache/jxl-oxide-testdata.
#
# Usage: scripts/fetch_fixtures.sh [conformance|decode|all]   (default: all)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="$ROOT/fixtures/cache"
mkdir -p "$CACHE"
what="${1:-all}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "error: $1 not found" >&2; exit 1; }; }

fetch_conformance() {
  local src
  if [ -n "${CONFORMANCE_DIR:-}" ]; then
    src="$(cd "$CONFORMANCE_DIR" && pwd)"
  else
    need git; need curl
    src="$CACHE/conformance-repo"
    if [ ! -d "$src/.git" ]; then
      git clone --depth 1 https://github.com/libjxl/conformance.git "$src"
    fi
    (cd "$src" && bash scripts/download_and_symlink_using_curl.sh)
  fi
  [ -d "$src/testcases" ] || { echo "error: $src/testcases not found" >&2; exit 1; }
  ln -sfn "$src/testcases" "$CACHE/conformance"
  local missing=0
  for d in "$CACHE"/conformance/*/; do
    [ -f "$d/test.json" ] || continue
    for f in input.jxl reference_image.npy reference.icc; do
      if [ ! -e "$d/$f" ]; then
        echo "warning: missing $(basename "$d")/$f" >&2
        missing=1
      fi
    done
  done
  echo "conformance: $CACHE/conformance -> $src/testcases (missing files: $missing)"
}

fetch_decode() {
  need zstd
  local src
  if [ -n "${DECODE_DIR:-}" ]; then
    src="$(cd "$DECODE_DIR" && pwd)"
  else
    need git
    src="$CACHE/jxl-oxide-testdata"
    if [ ! -d "$src/.git" ]; then
      git clone --depth 1 https://github.com/tirr-c/jxl-oxide-testdata.git "$src"
    fi
  fi
  local out="$CACHE/decode"
  mkdir -p "$out" "$CACHE/downloads"
  for d in "$src"/*/; do
    local name
    name="$(basename "$d")"
    [ -f "$d/input.jxl" ] || continue
    mkdir -p "$out/$name"
    ln -sfn "$d/input.jxl" "$out/$name/input.jxl"
    local zst=""
    if [ -f "$d/output.buf.zst" ]; then
      zst="$d/output.buf.zst"
    elif [ -f "$d/output.buf.zst.url" ]; then
      need curl
      zst="$CACHE/downloads/$name.buf.zst"
      if [ ! -s "$zst" ]; then
        local url
        url="$(tr -d '[:space:]' < "$d/output.buf.zst.url")"
        echo "downloading $url"
        curl -fsSL -o "$zst.part" "$url"
        mv "$zst.part" "$zst"
      fi
    fi
    if [ -n "$zst" ] && { [ ! -s "$out/$name/output.buf" ] || [ "$zst" -nt "$out/$name/output.buf" ]; }; then
      zstd -q -d -f -o "$out/$name/output.buf" "$zst"
    fi
    echo "decode: $name$([ -s "$out/$name/output.buf" ] && echo ' (output.buf)')"
  done
}

case "$what" in
  conformance) fetch_conformance ;;
  decode) fetch_decode ;;
  all) fetch_conformance; fetch_decode ;;
  *) echo "usage: $0 [conformance|decode|all]" >&2; exit 2 ;;
esac
