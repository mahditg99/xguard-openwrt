# Third-party software / نرم‌افزارهای ثالث

xguard's own code (everything under `files/`, `tools/`, `tests/`, `docs/`) is MIT licensed (see `LICENSE`).

The **release images and downloads** bundle or fetch software under their own licenses:

| Component | License | Where it comes from |
|---|---|---|
| [OpenWrt](https://openwrt.org) 24.10.x (kernel, busybox, nftables, dnsmasq, dropbear, uhttpd, rpcd, ucode, …) | GPL-2.0 and others (per package) | Official OpenWrt ImageBuilder and package feeds, unmodified |
| OpenSSH client, OpenSSL, sshpass | BSD / Apache-2.0 / GPL-2.0 | OpenWrt package feed |
| [Xray-core](https://github.com/XTLS/Xray-core) | MPL-2.0 | The **unmodified official binary** from the Xray-core release, repacked as gzip. Source: <https://github.com/XTLS/Xray-core> |

The exact package list of each image is attached to the release as `xguard-<tag>-package-manifest.txt`.
Corresponding OpenWrt sources are available from <https://downloads.openwrt.org/> and <https://git.openwrt.org/>.

xguard is an independent project and is not affiliated with OpenWrt, Xray-core/XTLS, Xiaomi or the passwall project.
