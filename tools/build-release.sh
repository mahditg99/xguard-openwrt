#!/bin/bash
# Builds everything that goes into a GitHub release into ./release (used by the release workflow,
# also fine to run by hand on any x86_64 Linux box with the ImageBuilder prerequisites:
#   make zstd rsync xz-utils file wget gawk perl patch bzip2 python3 unzip curl).
#
#   tools/build-release.sh <tag> [openwrt-version]        e.g.  tools/build-release.sh v0.1.0 24.10.8
#   XRAY_VERSION=v26.11.9 tools/build-release.sh v0.1.0   (Xray-core version, default below)
set -eu

TAG="${1:?usage: build-release.sh <tag> [openwrt-version]}"
OWRT="${2:-24.10.8}"
XRAY="${XRAY_VERSION:-v26.11.9}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
OUT="$ROOT/release"
BOARD=xiaomi_mi-router-4a-gigabit

rm -rf "$OUT"
mkdir -p "$OUT"

echo "== xray-core $XRAY"
bash "$HERE/build-xray.sh" "$XRAY" "$OUT"

echo "== rootfs overlay (stamped with the release tag)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -r "$ROOT/files/." "$STAGE/"
echo "xguard $TAG (OpenWrt $OWRT, Xray-core $XRAY)" > "$STAGE/etc/xguard.version"
tar cf "$HERE/xguard-files.tar" -C "$STAGE" .

echo "== OpenWrt $OWRT image"
bash "$HERE/build-image.sh" "$OWRT"
cp "$HERE/out/openwrt-$OWRT-ramips-mt7621-$BOARD-squashfs-sysupgrade.bin" \
   "$OUT/xguard-$TAG-openwrt-$OWRT-$BOARD-sysupgrade.bin"
cp "$HERE/out/openwrt-$OWRT-ramips-mt7621-$BOARD.manifest" "$OUT/xguard-$TAG-package-manifest.txt"

(cd "$OUT" && sha256sum xguard-* xray.gz xray.gz.sha256 xray.version > SHA256SUMS)
echo "== release assets:"
ls -l "$OUT"
