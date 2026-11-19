# Troubleshooting

🇮🇷 [فارسی](TROUBLESHOOTING.fa.md) · 🇬🇧 English · [← README](../README.md)

Start here:

```sh
xguardctl status      # what the supervisor thinks
xguardctl logs        # xguardd / xray / ssh logs
logread | grep -E 'xguard|xray'
```

## Emergency: get plain internet back

```sh
xguardctl disable            # kill-switch + DNS hook removed within ~5 s
/usr/sbin/xguardd unguard    # same, immediately, even if the supervisor is dead
nft delete table inet xguard # just the firewall part
```
If DNS is still broken afterwards, `xguardd unguard` restores dnsmasq's original upstreams from `/etc/xguard/dnsmasq.orig`.

## Status values

| `status` | Meaning / what to do |
|---|---|
| `need-xray` | No xray in RAM and no `source` configured → [push it](INSTALL.md#5-put-xray-core-into-the-routers-ram) or add a source. |
| `fetching-xray` | Downloading. If it never finishes: `xguardctl logs`, check the URL, that `xray.gz.sha256` exists next to it, the router clock, and `bootstrap_dns`. |
| `no-node` | Enabled but no enabled node → add one in the UI. The kill-switch is already active. |
| `starting` / `restarting` | Normal for a few seconds. |
| `degraded` | xray runs but the tunnel does not pass traffic. VPN clients have **no** internet (by design). It retries forever and, with several nodes, moves to the next one after `fail_threshold × probe_interval` s. Check the node, the server, `probe_url`, the clock. |
| `updating` | A `/tmp/xguard/hold` file exists or `push-xray` is running. |
| `error` | The kill-switch could not be applied — look at `xguardctl logs` (`nft.err`, `gen.err` in `/tmp/xguard/`). |
| `disabled` | `enabled` is `0`. |

## Common problems

**Clients on a VPN interface have no internet and `status=running`.**
Check the client's DNS (it must use the router), `nslookup example.com <router>` on the router, and whether the interface name in *Network* matches the real device (`ls /sys/class/net`). Wi‑Fi names are `phy0-ap0`, `phy1-ap0` (not `wlan0`). A client whose interface is `block` never has internet.

**Everything on `direct` interfaces lost DNS.**
By design all clients resolve through the tunnel. While xray is down DNS is down too. Use `xguardctl disable` if you want plain DNS back.

**HTTPS fails / "certificate is not yet valid" on the router, or the tunnel is `degraded` right after boot.**
The router has no battery clock. xguard fixes the time from the HTTP `Date:` header of `time_hosts` (default `1.1.1.1`, port 80) before downloading xray and then hourly. If port 80 to those hosts is blocked, set `time_hosts` to something reachable, or `date -u -s "YYYY-MM-DD HH:MM:SS"` manually.

**xray was killed again and again ("RSS … above … restarting").**
Lower the load or raise `rss_kill`/`mem_limit` (defaults 46/28 MiB suit a 128 MB router). Check `free -m` and that zram is on (`cat /proc/swaps`). Fewer simultaneous connections, no sniffing, `log_level warning` help.

**Slow.**
The MT7621 has no AES acceleration. Prefer nodes without double encryption; Reality/Vision or chacha20-based ciphers are cheaper than AES-GCM in software. `top` shows whether xray saturates the CPU. Speed limits (policers) also cap speed deliberately.

**QUIC / UDP apps don't work.**
`block_quic=1` drops UDP/443 on purpose. SSH nodes cannot carry UDP at all. VLESS/VMess/Trojan/SS nodes can (unless the server disallows it).

**IPv6.**
Not supported: VPN/block clients' IPv6 is dropped by the kill-switch.

**The web UI shows "access denied" / won't log in.**
Log in with the root password (empty if none was set — please set one). rpcd must run: `/etc/init.d/rpcd restart`. SSH always works as a fallback.

**xguard's firewall rules vanished after `/etc/init.d/firewall reload`.**
They should not: they live in their own table `inet xguard`, which fw4 does not touch. `nft list table inet xguard` to check; `xguardctl restart` re-applies.

**Wi‑Fi clients are not redirected although the interface is `vpn`.**
Check the device exception list (a `direct` device on that interface bypasses the VPN) and the bypass list.

**`ssh` node does not connect.**
`xguardctl logs` shows the `ssh` stderr. With a password the node uses `sshpass`; otherwise a key at `/etc/xguard/id_ed25519` (`xguardctl genkey`, then append the printed public key to the server's `authorized_keys`). The host key is trusted on first use and stored in `/etc/xguard/known_hosts` (delete the line if the server was reinstalled). Passwords containing `|` are not supported.

## Testing the kill-switch yourself

```sh
touch /tmp/xguard/hold; killall xray     # a VPN client must now have NO internet at all
rm /tmp/xguard/hold                      # xray comes back, internet returns
```

## Reporting bugs

Please include: router model, OpenWrt/xguard versions (`cat /etc/xguard.version`), `xguardctl status`, `xguardctl logs`, `nft list table inet xguard`, `free -m`. **Remove node links, passwords and UUIDs** from anything you paste.
