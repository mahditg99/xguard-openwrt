## xguard @TAG@ — Xiaomi Mi Router 4A Gigabit (OpenWrt @OPENWRT@)

> **Pre-release / پیش‌انتشار:** this build passes its automated checks but has not yet been verified on every device.
> Read the install guide and keep your own backup. / این نسخه آزمایش‌های خودکار را می‌گذراند ولی هنوز روی همهٔ دستگاه‌ها تأیید نشده؛ راهنمای نصب را بخوانید و پشتیبان بگیرید.

### Download / دانلود
| File | What it is / چیست |
|---|---|
| `xguard-@TAG@-openwrt-@OPENWRT@-xiaomi_mi-router-4a-gigabit-sysupgrade.bin` | Full OpenWrt firmware with xguard, **flash this** / فریمور کامل، همین را فلش کنید |
| `xray.gz` + `xray.gz.sha256` | Xray-core @XRAY@ (official `xray_softfloat`, gzip). Lives in the router's **RAM**, not on flash / فقط در RAM روتر |
| `xguard-@TAG@-package-manifest.txt` | Exact package list of the image / فهرست بسته‌های ایمیج |
| `SHA256SUMS` | Checksums / چک‌سام‌ها |

### Quick install / نصب سریع
1. Verify: `sha256sum -c SHA256SUMS` (or `Get-FileHash` on Windows).
2. Flash **without keeping settings**: `scp -O <image>.bin root@<router>:/tmp/fw.bin` then `sysupgrade -n /tmp/fw.bin`.
3. Put xray in RAM: `cat xray.gz | ssh root@<router> "xguardctl push-xray $(cut -d' ' -f1 xray.gz.sha256)"`
4. Open `http://<router>/xguard/`, add a node, choose which interfaces use the VPN, enable.

Full guide / راهنمای کامل: [docs/INSTALL.md](https://github.com/OWNER/REPO/blob/@TAG@/docs/INSTALL.md) · [docs/INSTALL.fa.md](https://github.com/OWNER/REPO/blob/@TAG@/docs/INSTALL.fa.md)

Contains OpenWrt (GPL-2.0 and others) and the unmodified Xray-core (MPL-2.0) binary — see `NOTICE.md`.
