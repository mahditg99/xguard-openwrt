#!/bin/bash
# Builds xguard_<version>_all.ipk (architecture independent: shell + ucode + html only) without the
# OpenWrt SDK. Works with opkg (OpenWrt 24.10 and older). OpenWrt 25.12+ uses apk and needs a different package.
#
#   tools/build-ipk.sh <tag> [outdir]        e.g.  tools/build-ipk.sh v0.1.0 release
#
# Needs: bash, GNU tar, gzip, find, du.
set -eu

TAG="${1:?usage: build-ipk.sh <tag> [outdir]}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
OUT="${2:-$ROOT/release}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

# v0.1.0 -> 0.1.0 ; v0.1.0-rc1 -> 0.1.0~rc1 (opkg sorts '~' before the final release)
VER="${TAG#v}"
VER="${VER/-rc/~rc}"
REL=1
PKG="xguard_${VER}-${REL}_all.ipk"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
DATA="$STAGE/data"
CTRL="$STAGE/control"
mkdir -p "$DATA" "$CTRL"

cp -r "$ROOT/files/." "$DATA/"
# /www/index.html only exists for the stand-alone image (no LuCI); never overwrite a router's own index page
rm -f "$DATA/www/index.html"
echo "xguard $TAG (package)" > "$DATA/etc/xguard.version"

find "$DATA" -type d -exec chmod 755 {} +
find "$DATA" -type f -exec chmod 644 {} +
chmod 755 "$DATA/etc/init.d/xguard" "$DATA/etc/uci-defaults/90-xguard" "$DATA/usr/sbin/xguardd" \
          "$DATA/usr/sbin/xguardctl" "$DATA/usr/sbin/xguardacct" "$DATA/usr/libexec/xguard/fetch"
chmod 600 "$DATA/etc/config/xguard"

SIZE="$(du -sb "$DATA" | cut -f1)"

cat > "$CTRL/control" <<EOF
Package: xguard
Version: ${VER}-${REL}
Depends: libc, dnsmasq-full, ucode, ucode-mod-fs, ucode-mod-uci, ucode-mod-ubus, rpcd, rpcd-mod-ucode, uhttpd, uhttpd-mod-ubus, ip-full, firewall4, uclient-fetch, ca-bundle, kmod-nft-tproxy, kmod-zram, zram-swap, openssh-client, openssh-keygen, sshpass
Section: net
Maintainer: xguard contributors
Architecture: all
Installed-Size: ${SIZE}
Description: Whole-router VPN with a fail-closed kill-switch (xray-core running from RAM).
 Web UI at /xguard/, CLI xguardctl. xray-core itself is NOT included: put it into RAM with
 'xguardctl push-xray' or configure a download source. All other required packages (dnsmasq-full, ucode, rpcd,
 uhttpd, ip-full, kmod-nft-tproxy, zram-swap, openssh-client, sshpass, ...) are installed as dependencies.
EOF

echo "/etc/config/xguard" > "$CTRL/conffiles"

cat > "$CTRL/postinst" <<'EOF'
#!/bin/sh
[ "${IPKG_NO_SCRIPT}" = "1" ] && exit 0
[ -s "${IPKG_INSTROOT}/lib/functions.sh" ] || exit 0
. "${IPKG_INSTROOT}/lib/functions.sh"
default_postinst "$0" "$@"
ret=$?
# rpcd loads its ucode plugins (our API) and ACL files at start
[ -z "${IPKG_INSTROOT}" ] && {
	/etc/init.d/rpcd restart >/dev/null 2>&1
	rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache    # LuCI rebuilds its menu (Services -> xguard VPN)
}
exit $ret
EOF

cat > "$CTRL/prerm" <<'EOF'
#!/bin/sh
[ -s "${IPKG_INSTROOT}/lib/functions.sh" ] || exit 0
. "${IPKG_INSTROOT}/lib/functions.sh"
default_prerm "$0" "$@"
ret=$?
# a real removal (not an upgrade) must also drop the kill-switch, the DNS hook and the routing rule
if [ -z "${IPKG_INSTROOT}" ] && [ "${PKG_UPGRADE}" != "1" ]; then
	/usr/sbin/xguardd unguard >/dev/null 2>&1
	killall xray >/dev/null 2>&1
fi
rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache
exit $ret
EOF
chmod 755 "$CTRL/postinst" "$CTRL/prerm"

TAROPTS=(--owner=0 --group=0 --numeric-owner)
(cd "$DATA" && tar "${TAROPTS[@]}" -cf - . | gzip -9n > "$STAGE/data.tar.gz")
(cd "$CTRL" && tar "${TAROPTS[@]}" -cf - . | gzip -9n > "$STAGE/control.tar.gz")
echo "2.0" > "$STAGE/debian-binary"
(cd "$STAGE" && tar "${TAROPTS[@]}" -cf - ./debian-binary ./data.tar.gz ./control.tar.gz | gzip -9n > "$OUT/$PKG")

echo "built $OUT/$PKG ($(du -h "$OUT/$PKG" | cut -f1), installed size ${SIZE} bytes)"
