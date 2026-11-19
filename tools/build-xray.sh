#!/bin/bash
# Linux/macOS/CI equivalent of build-xray.ps1.
#
# Downloads the official Xray-core release for MIPS little-endian (MT7621 = mipsel_24kc, soft-float),
# verifies the zip against the .dgst published by the Xray project and writes, into ./dist (or $2):
#   xray.gz          gzip -9 of the UNCOMPRESSED binary (the router streams it straight into RAM)
#   xray.gz.sha256   sha256 of the UNCOMPRESSED binary (what the router verifies)
#   xray.version
#
#   tools/build-xray.sh [vX.Y.Z|latest] [outdir]
set -eu

VERSION="${1:-latest}"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${2:-$HERE/../dist}"
mkdir -p "$OUT"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ "$VERSION" = latest ]; then
	VERSION="$(curl -fsSL https://api.github.com/repos/XTLS/Xray-core/releases/latest | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1)"
	[ -n "$VERSION" ] || { echo "cannot determine latest Xray-core version" >&2; exit 1; }
fi
echo "Xray-core $VERSION (linux mips32le)"
BASE="https://github.com/XTLS/Xray-core/releases/download/$VERSION"

curl -fsSL -o "$WORK/xray.zip" "$BASE/Xray-linux-mips32le.zip"
WANT="$(curl -fsSL "$BASE/Xray-linux-mips32le.zip.dgst" | tr -d '\r' | sed -n 's/^SHA2-256= *\([0-9a-f]\{64\}\).*/\1/p' | head -n1)"
[ -n "$WANT" ] || { echo "no SHA2-256 line in the .dgst file" >&2; exit 1; }
GOT="$(sha256sum "$WORK/xray.zip" | cut -d' ' -f1)"
[ "$GOT" = "$WANT" ] || { echo "zip checksum mismatch: $GOT != $WANT" >&2; exit 1; }
echo "zip sha256 OK ($GOT)"

# the MT7621 userland is soft-float: use the softfloat build
unzip -p "$WORK/xray.zip" xray_softfloat > "$WORK/xray"
SHA="$(sha256sum "$WORK/xray" | cut -d' ' -f1)"
gzip -9 -n -c "$WORK/xray" > "$OUT/xray.gz"
echo "$SHA  xray" > "$OUT/xray.gz.sha256"
echo "$VERSION" > "$OUT/xray.version"
echo "binary $(du -h "$WORK/xray" | cut -f1), xray.gz $(du -h "$OUT/xray.gz" | cut -f1), sha256(binary) $SHA"
