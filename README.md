# xguard

**Whole-router VPN with a fail-closed kill-switch for OpenWrt, powered by xray-core running from RAM.**

🇮🇷 [فارسی](README.fa.md) · 🇬🇧 English

xguard is a lightweight alternative to passwall for small routers. It turns an OpenWrt router into a VPN gateway: choose which Wi‑Fi networks / LAN ports go through the tunnel and which don't, and if the tunnel drops, those clients get **no internet at all** instead of silently falling back to your ISP connection.

It targets the **Xiaomi Mi Router 4A Gigabit** (MT7621, 128 MB RAM, 16 MB flash, OpenWrt 24.10), where the biggest problem is memory: the latest xray-core binary is **33 MB uncompressed** (the "9 MB" you see in downloads is the compressed size), flash has only ~1 MB free with a stock-sized image, and a full passwall stack eventually filled RAM. xguard is designed around those limits.

> **Status: 1.0 stable.** Verified on a real Xiaomi Mi Router 4A Gigabit (OpenWrt 24.10, installed as the `.ipk`): VPN per interface/device, the default policy, exempted IPs/domains and the web UI work with live traffic; config generation, the kill-switch rule set, the supervisor and the API are also covered by automated checks (see [Testing](#testing)). The `sysupgrade` image passes `sysupgrade -T` but has not been flashed on hardware yet, and RAM is tight on this router (watch `xguardctl status`) — please report results.

## Features

- **VPN per interface**: each network device (Wi‑Fi radio, LAN port, …) is `vpn`, `direct` or `block`; per-device (MAC/IP) exceptions.
- **Real kill-switch (fail-closed)**: nftables rules are loaded *before* the network comes up and stay in place across xray restarts, node switches and crashes. Clients on a VPN interface can never be forwarded to the WAN.
- **Retries forever**: procd respawn without limit, xray restart with capped backoff, automatic failover to the next node, endless binary download retry, SSH keepalive.
- **Everything xray supports**: `vless://`, `vmess://`, `trojan://`, `ss://`, `socks://` links (TCP, WS, gRPC, HTTPUpgrade, XHTTP, mKCP, TLS, Reality, Vision) **plus raw xray outbound JSON** for anything else (WireGuard, Hysteria, `dialerProxy` chains, …).
- **SSH tunnel** as an outbound (`ssh -D` → xray socks outbound). xray itself has no SSH support.
- **Per-user speed limits** (IP, MAC or interface; download and upload separately; nftables policing).
- **Usage report per client IP** (which sites/apps, how many bytes, whitelist vs VPN) and **daily quotas per user with two separate allowances** (whitelist traffic and VPN traffic): when one is used up, its speed drops to a number you choose; it resets every day and survives reboots.
- **No DNS leaks**: dnsmasq resolves only through the tunnel.
- **Built for 128 MB**: xray lives only in RAM (never on flash), zram swap, `GOMEMLIMIT`, RSS cap with automatic restart, bounded conntrack, no geoip/geosite, tiny rotating logs.
- **Web UI** (Persian, RTL) at `http://<router>/xguard/`, and a CLI (`xguardctl`).

## Quick start

You need a router that already runs OpenWrt (to use `sysupgrade`) and a PC with `ssh`.

1. Download from the [latest release](../../releases/latest): the `…-sysupgrade.bin`, `xray.gz`, `xray.gz.sha256`, `SHA256SUMS`. Verify with `sha256sum -c SHA256SUMS`.
2. **Back up first** (`sysupgrade -b /tmp/backup.tar.gz`, and `cat /dev/mtd3ro > factory.bin` for the Wi‑Fi calibration), then flash **without keeping settings**:
   ```sh
   scp -O xguard-*-sysupgrade.bin root@192.168.1.1:/tmp/fw.bin
   ssh root@192.168.1.1 sysupgrade -n /tmp/fw.bin
   ```
3. Set a root password (`passwd`), restore your network/Wi‑Fi backup if you want it.
4. Put xray into the router's RAM (needed again after every reboot unless you configure a download source):
   ```sh
   cat xray.gz | ssh root@<router> "xguardctl push-xray $(cut -d' ' -f1 xray.gz.sha256)"
   ```
   Windows: `powershell -File tools\push-xray.ps1 -Router <router>`.
5. Open `http://<router>/xguard/` → **Nodes**: paste a link → **Network**: mark interfaces `VPN` → switch **Enabled** on.

Already on OpenWrt 24.10 with enough free flash? The release also has an `.ipk` (`opkg install`) — see [INSTALL §10](docs/INSTALL.md).

Details: **[docs/INSTALL.md](docs/INSTALL.md)** · [Configuration](docs/CONFIGURATION.md) · [Troubleshooting](docs/TROUBLESHOOTING.md) · [Building & releases](docs/BUILD.md)

## How it works

```
 clients ─► nftables (own table, runs before fw4) ─► xray-core (RAM only)
              │ REDIRECT (tcp) / TPROXY (udp)           ├─ vless / vmess / trojan / ss / wireguard …
              │ kill-switch, speed limits               └─ socks ◄─ ssh -D   (SSH tunnel)
              ▼
        xguardd supervisor (ash): health checks, failover, memory watchdog, clock fix,
                                  endless retries, xray download into tmpfs
```

- `files/` is the root-filesystem overlay baked into the image (init script, supervisor, ucode generators, rpcd API, web UI).
- The image is built with the official OpenWrt ImageBuilder (no LuCI, no ppp/odhcp6c) and adds `kmod-nft-tproxy`, `zram-swap`, `openssh-client`, `rpcd`/`uhttpd`, `ip-full`.
- xray-core is the **unmodified official binary** (`xray_softfloat`, repacked as gzip). It is downloaded/pushed into tmpfs and verified by SHA-256.

## Limits you should know

- **IPv4 only.** IPv6 from VPN/blocked interfaces is dropped by the kill-switch, not tunnelled.
- The router's **own** traffic (opkg, NTP, …) is not proxied.
- DNS for **all** clients (even `direct` interfaces) goes through the tunnel; if xray is down, DNS is down (on purpose, to avoid leaks).
- Speed limits are **policing** (excess packets are dropped), not smooth shaping.
- SSH nodes carry TCP only (no UDP; QUIC is blocked so browsers fall back to TCP).
- `hysteria2://`-style share links are not parsed yet — use a raw JSON node.
- Throughput is bounded by the MT7621 CPU (no AES acceleration); expect tens of Mbps, not hundreds. Measurements welcome.
- Only the Xiaomi Mi Router 4A Gigabit is supported/tested; see [docs/BUILD.md](docs/BUILD.md) for other boards.

## Testing

```
tests/sim-supervisor.sh   real xguardd + real ucode generators in a sandbox (stubbed nft/ip/uci, fake xray): 33 checks
CI                        shell/JS/JSON syntax checks
manual (done)             generated configs validated with `xray run -test`; ruleset validated with `nft -c`;
                          image validated with `sysupgrade -T`
```
Not covered by automation: live traffic, kill-switch during a real outage, throughput, multi-day RAM behaviour, the web UI against a live rpcd.

## Security notes

- OpenWrt ships with **no root password** — set one. The web UI and SSH both use it.
- The web UI is plain HTTP on port 80 of every router interface (fw4's default policy rejects it from the WAN side). Do not expose it to untrusted networks.
- SSH-node passwords are stored in `/etc/config/xguard` (mode 600). Prefer keys (`xguardctl genkey`).
- Never publish router backups (`sysupgrade -b`): they contain Wi‑Fi keys.

## License

MIT for xguard's own code (see [LICENSE](LICENSE)). Releases bundle OpenWrt and the unmodified Xray-core binary under their own licenses — see [NOTICE.md](NOTICE.md). Not affiliated with OpenWrt, XTLS/Xray, Xiaomi or passwall.
