# Installation guide

🇮🇷 [فارسی](INSTALL.fa.md) · 🇬🇧 English · [← README](../README.md)

## 0. Requirements

| | |
|---|---|
| Router | **Xiaomi Mi Router 4A Gigabit** (`xiaomi,mi-router-4a-gigabit`, MT7621, 128 MB RAM, 16 MB flash). Other boards: see [BUILD.md](BUILD.md). |
| Current firmware | Must already run **OpenWrt** (the release file is a *sysupgrade* image). If the router still has Xiaomi's stock firmware, first install OpenWrt following the [OpenWrt device page](https://openwrt.org/toh/xiaomi/mir4a_gigabit), then continue here. |
| PC | `ssh` client (Linux/macOS/Windows 10+), able to reach the router. |
| A VPN node | A `vless://` / `vmess://` / `trojan://` / `ss://` link, a raw xray outbound JSON, or an SSH server. |

> ⚠️ Flashing replaces the whole firmware. Keep a backup and do not interrupt power while flashing.

## 1. Download and verify

From the [latest release](../../../releases/latest) download:

- `xguard-<tag>-openwrt-<ver>-xiaomi_mi-router-4a-gigabit-sysupgrade.bin` — the firmware
- `xray.gz`, `xray.gz.sha256` — Xray-core for the router's RAM
- `SHA256SUMS`

```sh
sha256sum -c SHA256SUMS          # Linux/macOS
Get-FileHash <file> -Algorithm SHA256   # Windows PowerShell, compare by eye
```

## 2. Back up (on the router that currently runs OpenWrt)

```sh
ssh root@<router> 'sysupgrade -b /tmp/backup.tar.gz && cat /tmp/backup.tar.gz' > router-config-backup.tar.gz
ssh root@<router> 'cat /dev/mtd3ro' > factory-mtd3.bin     # Wi-Fi calibration (64 KiB)
```
`router-config-backup.tar.gz` contains your Wi‑Fi passwords — keep it private. `sysupgrade` does not touch the calibration partition, but keep the copy anyway.

## 3. Flash (clean install)

The firmware refuses to carry old settings over from older OpenWrt versions, so flash **without keeping settings**:

```sh
ssh root@<router> 'cat > /tmp/fw.bin' < xguard-*-sysupgrade.bin
ssh root@<router> 'sysupgrade -T /tmp/fw.bin && sysupgrade -n /tmp/fw.bin'
```
(`-T` only tests the image; `-n` wipes the settings.) With LuCI: *System → Backup / Flash Firmware → Flash image…* and **untick "Keep settings"**.

The router reboots by itself (about 2 minutes). Do not power it off.

## 4. First boot

- The default address is **`192.168.1.1`**. If your upstream network is also `192.168.1.0/24`, connect **only a LAN cable to the PC**, leave the WAN port unplugged until you've restored/changed the settings.
- Set a root password right away: `ssh root@192.168.1.1` then `passwd`.
- *(Optional)* restore your old network/Wi‑Fi settings:
  ```sh
  ssh root@192.168.1.1 'cat > /tmp/b.tar.gz' < router-config-backup.tar.gz
  ssh root@192.168.1.1 'sysupgrade -r /tmp/b.tar.gz && reboot'
  ```
  The restore also brings back your old `/etc/config/system`; zram then falls back to its default size (half of the RAM), which works. To pin it: `uci set system.@system[0].zram_size_mb=48; uci commit system`.

## 5. Put xray-core into the router's RAM

xray (33 MB unpacked) does **not** fit on flash and is never stored there. It lives in `/tmp/xguard/xray` and must be provided after every boot. Choose one:

### a) Push it from your PC (simplest, manual)

```sh
cat xray.gz | ssh root@<router> "xguardctl push-xray $(cut -d' ' -f1 xray.gz.sha256)"
```
Windows (from a clone of this repo, after downloading the release files into `dist\`):
```powershell
powershell -File tools\push-xray.ps1 -Router <router>
```
The router stops any running xray (RAM cannot hold two copies), unpacks the new one, checks the SHA-256 and the supervisor starts it.

By hand, without the helper: `gunzip -c xray.gz | ssh root@<router> 'cat > /tmp/xguard/xray && chmod 755 /tmp/xguard/xray'` (stop xray first if it is running; the path must be exactly `/tmp/xguard/xray`).

> ⚠️ Do **not** install OpenWrt's `xray-core` package (not even with `opkg -d ram`): xguard only looks at `/tmp/xguard/xray`, and the feed's version (25.1.30 on 24.10) is too old for the configs xguard generates (`VLESS settings: "vnext" is empty`). Use the `xray.gz` from the release.

### b) Let the router download it by itself after every boot (recommended)

Give it one or more **sources** (UI → *Settings*, or UCI). It tries them in order, retrying forever with backoff:

```sh
uci add_list xguard.main.source='https://example.com/xguard/xray.gz'   # xray.gz.sha256 must sit next to it
uci commit xguard
```
Source types:
- `https://host/path/xray.gz` — any static host (needs `xray.gz.sha256` at the same URL + `.sha256`).
- `ssh://user@host[:port]/path/xray.gz` — your own server over SSH (key `/etc/xguard/id_ed25519`, create with `xguardctl genkey`); a locked-down helper is in [`tools/mirror/`](../tools/mirror) (`setup-mirror.sh`).
- GitHub release assets (`https://github.com/<owner>/<repo>/releases/download/<tag>/xray.gz`) may also work if GitHub is reachable from your router — they redirect to a CDN, so test with `xguardctl update-xray` and `xguardctl logs`.

Why not the official zip? The router has no `unzip`, and unpacking a zip would need 10 MB + 33 MB of RAM at once. The gzip is streamed through `gunzip` straight into place.

Check: `xguardctl status` shows `xray_version=…` and `status=…`.

## 6. Configure (web UI)

Open **`http://<router>/xguard/`** and log in as `root`. If LuCI is installed, the same page is also available as **Services → xguard VPN** (it reuses your LuCI login).

1. **Nodes** → *Add node*: paste a link (use *Check link*), or choose *Raw xray JSON* / *SSH tunnel*. Mark one node as *main*; others are failover (in list order).
2. **Network** → set each interface to **VPN**, **Direct** or **Block**. Never touch the WAN interface here. Device names are shown as the kernel knows them (`phy0-ap0` = 2.4 GHz Wi‑Fi AP, `phy1-ap0` = 5 GHz, `lan1`, `lan2`, …).
3. *(Optional)* device exceptions, destinations that bypass the VPN, **Speed limits**, **Settings** (sources, memory limits, DNS, probe URL).
4. Switch **Enabled** (top right). From this moment the kill-switch is active for every VPN/Block interface.

Command-line equivalent: see [CONFIGURATION.md](CONFIGURATION.md).

## 7. Verify

```sh
xguardctl status        # status=running, alive=1, delay=…
```
- From a client on a VPN interface: your public IP must be the VPN's (e.g. `curl https://ifconfig.me`).
- **Test the kill-switch:** on the router run `touch /tmp/xguard/hold; killall xray`. The client must lose internet completely and `status` becomes `updating`. Then `rm /tmp/xguard/hold` — it recovers by itself.
- Watch memory over time: `xguardctl status` (`rss_kb`, `avail_kb`) and `free -m`.

## 8. Updating

- **xray-core:** build/download a new `xray.gz`, then push it (5a) or run `xguardctl update-xray` (5b).
- **xguard/firmware:** flash the new release image. Within the same OpenWrt series you may omit `-n` to keep your settings (`/etc/config/xguard` is preserved); take a backup first. xray must be provided again after the reboot.

## 9. Emergency off / uninstall

```sh
xguardctl disable                 # kill-switch and DNS hook removed within ~5 s
# or, even if the supervisor is dead:
/usr/sbin/xguardd unguard
```
To go back to plain OpenWrt, flash an official OpenWrt image with `sysupgrade -n`.

## 10. Alternative: install as a package (no re-flash)

For a router that **already runs OpenWrt 24.10 (opkg)** and has enough free flash, the release also contains `xguard_<version>_all.ipk` (≈ 30 KB, architecture independent). It installs xguard on top of your existing system instead of replacing it.

- `opkg` installs **every package xguard needs by itself**, as dependencies from the OpenWrt feeds: `dnsmasq-full`, `ucode`, `ucode-mod-fs/uci/ubus`, `rpcd`, `rpcd-mod-ucode`, `uhttpd`, `uhttpd-mod-ubus`, `ip-full`, `firewall4`, `uclient-fetch`, `ca-bundle`, `kmod-nft-tproxy`, `kmod-zram`, `zram-swap`, `openssh-client`, `openssh-keygen`, `sshpass`. Packages you already have are not touched. **`dnsmasq-full` is mandatory** (the stock `dnsmasq` has no `nftset`, which exempted domains need to work while xray is down); if your router still has the stock `dnsmasq` as an installed package, run `opkg remove dnsmasq` first (DNS/DHCP are down for a few seconds), then install the package. So the router needs a working internet connection and a correct clock for `opkg update`, and the `kmod-*` packages must match your running kernel.
- **Flash space:** the new dependencies are small except OpenSSH (`openssh-client` + `libopenssl3`, about 4.6 MB unpacked, roughly 2 MB of flash). Check `df -h /overlay` first (≈ 5 MB free is comfortable). On a Xiaomi 4A Gigabit that still carries old packages (≈ 1 MB free) it will **not** fit — clean the router or use the firmware image.
- OpenWrt 25.12 and newer use `apk`; this `.ipk` is for `opkg` (24.10 and older).

```sh
ssh root@<router> 'cat > /tmp/xguard.ipk' < xguard_*_all.ipk
ssh root@<router> 'opkg update && opkg install /tmp/xguard.ipk'
```
Then continue with steps 5–7 above (xray into RAM, web UI, verify). The only thing the package does not ship is xray-core itself (33 MB, lives in RAM). Your `/etc/config/xguard` survives upgrades; `opkg remove xguard` also removes the kill-switch, DNS hook and routing rule.

> The package format has been verified with `opkg`'s own parser and the file layout is identical to the firmware image, and it has been installed on a live Xiaomi 4A Gigabit running OpenWrt 24.10 (offline, with its dependencies). Traffic through the tunnel has not been verified yet.
