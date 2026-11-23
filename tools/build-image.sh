#!/bin/bash
# Builds a minimal OpenWrt image (xiaomi_mi-router-4a-gigabit) containing xguard, using the official
# ImageBuilder. Run on a Linux box (needs: make zstd rsync xz-utils wget gawk python3 unzip file).
#
#   ./build-image.sh [openwrt-version]        expects ./xguard-files.tar next to it (the rootfs overlay)
#
# Output: ./out/*.bin  (use the *-squashfs-sysupgrade.bin)
set -eu

VER="${1:-24.10.8}"
BASE="https://downloads.openwrt.org/releases/$VER/targets/ramips/mt7621"
IB="openwrt-imagebuilder-$VER-ramips-mt7621.Linux-x86_64"
PROFILE=xiaomi_mi-router-4a-gigabit
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

if [ ! -d "$IB" ]; then
	echo ">> downloading ImageBuilder $VER"
	wget -q "$BASE/$IB.tar.zst"
	wget -q -O sha256sums "$BASE/sha256sums"
	grep " \*\?$IB.tar.zst\$" sha256sums | sed 's/ \*/  /' | sha256sum -c -
	tar --zstd -xf "$IB.tar.zst"
	rm -f "$IB.tar.zst"
fi

# a failed earlier run (e.g. missing perl) leaves an empty profile list behind
[ -s "$IB/.profiles.mk" ] || rm -f "$IB/.profiles.mk"

echo ">> preparing rootfs overlay"
rm -rf files out
mkdir files
tar xf xguard-files.tar -C files
chmod 755 files/etc/init.d/xguard files/etc/uci-defaults/90-xguard files/usr/sbin/xguardd files/usr/sbin/xguardctl files/usr/sbin/xguardacct\
          files/usr/libexec/xguard/fetch
chmod 600 files/etc/config/xguard
chmod 644 files/usr/lib/xguard/*.uc files/usr/share/rpcd/ucode/xguard.uc files/usr/share/rpcd/acl.d/xguard.json
find files -type d -exec chmod 755 {} +

# remove what a VPN router does not need (ppp, pppoe, ipv6 daemons), add what xguard needs
PKGS="-ppp -ppp-mod-pppoe -odhcp6c -odhcpd-ipv6only -dnsmasq dnsmasq-full \
 ucode ucode-mod-fs ucode-mod-uci ucode-mod-ubus \
 rpcd rpcd-mod-ucode uhttpd uhttpd-mod-ubus \
 kmod-nft-tproxy ip-full \
 kmod-zram zram-swap \
 openssh-client openssh-keygen sshpass"

echo ">> building image"
nice -n 19 make -C "$IB" image PROFILE="$PROFILE" PACKAGES="$PKGS" FILES="$HERE/files" BIN_DIR="$HERE/out"

ls -l out/*.bin
echo ">> manifest (size of what is inside):"
grep -c . out/*.manifest || true
