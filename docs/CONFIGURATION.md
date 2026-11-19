# Configuration reference

🇮🇷 [فارسی](CONFIGURATION.fa.md) · 🇬🇧 English · [← README](../README.md)

Everything lives in `/etc/config/xguard` (UCI) and is edited by the web UI, or by hand:

```sh
uci set xguard.main.enabled=1 ; uci commit xguard      # the supervisor notices within ~5 s
```
The supervisor (`xguardd`) watches the file (and `/tmp/dhcp.leases`) and re-applies firewall rules / restarts xray when something changes.

## `config main 'main'`

| Option | Default | Meaning |
|---|---|---|
| `enabled` | `0` | `1` activates the kill-switch, DNS hook and xray. With `0` nothing is blocked or proxied. |
| `node` | *(empty)* | Preferred node (section name). Failover walks the other enabled nodes in file order. |
| `source` (list) | – | Where the router fetches `xray.gz` from after each boot (`https://…/xray.gz`, `ssh://user@host[:port]/path/xray.gz`). `xray.gz.sha256` = sha256 of the **uncompressed** binary, at the same URL + `.sha256`. |
| `bootstrap_dns` | `1.1.1.1 8.8.8.8` | Plain DNS servers used **directly** (not through the tunnel) only to resolve the host names of `source` entries while xray is not running yet. Change them if they are blocked on your network. |
| `wan_if` (list) | `wan` | Interface(s) facing the internet; forwarded traffic from `vpn`/`block` interfaces towards them is dropped. |
| `dns_remote` | `tcp://1.1.1.1` | DNS server used **through the tunnel** (`tcp://` is required for SSH nodes). |
| `dns_bypass` | *(empty)* | Optional resolver (e.g. `178.22.122.100`) used **directly, outside the tunnel**, only for the domains in your `bypass` list (geo-DNS: local sites resolve to local IPs). Empty = those domains are resolved through the tunnel like everything else. |
| `probe_url` | `https://www.gstatic.com/generate_204` | URL xray's observatory fetches through the tunnel to decide "alive". |
| `probe_interval` | `10` | Seconds between probes. |
| `fail_threshold` | `3` | Dead probes in a row before switching to the next node (`fail_threshold × probe_interval` seconds). |
| `mem_limit` | `28` | `GOMEMLIMIT` for xray, MiB (soft limit; Go's GC works harder near it). |
| `rss_kill` | `46` | If xray's RSS exceeds this (MiB) it is restarted; the kill-switch stays active meanwhile. |
| `log_level` | `warning` | xray log level (`debug`, `info`, `warning`, `error`, `none`); the log is a tiny rotating file in RAM. |
| `sniffing` | `0` | xray sniffing. Switched on **automatically** while your `bypass` list contains a domain; set `1` to force it on. Costs a little CPU/RAM. |
| `block_quic` | `1` | Drop UDP/443 so browsers fall back to TCP (always on for SSH nodes). |
| `time_hosts` | `1.1.1.1 neverssl.com` | Hosts queried over plain HTTP (port 80) for the `Date:` header, used to fix the router clock (no RTC; NTP may be blocked). |
| `redir_port`, `tproxy_port`, `dns_port`, `socks_port`, `ssh_socks_port`, `metrics_port` | `12345`, `12346`, `15353`, `10808`, `10809`, `11111` | Local ports of xray's inbounds / the SSH SOCKS helper / the metrics endpoint. Change only on conflicts. |

## `config node '<id>'`

| Option | Meaning |
|---|---|
| `name` | Label shown in the UI. |
| `enabled` | `0` excludes the node from failover. |
| `type` | `link` (share link), `json` (raw xray outbound), `ssh` (SSH tunnel). |
| `link` | `vless://`, `vmess://` (base64 JSON), `trojan://`, `ss://` (SIP002 / legacy / plain), `socks://`. |
| `json` | One xray outbound object, **or an array = chain**: element 0 is the exit, each next element is its upstream (`dialerProxy` is set automatically). Tags are assigned by xguard. |
| `host`, `port`, `user` | SSH server (type `ssh`). |
| `password` | SSH password (uses `sshpass`). Empty → key authentication. |
| `keyfile` | Private key path, default `/etc/xguard/id_ed25519` (`xguardctl genkey`). |

Link parameters understood: `type` (tcp/raw, ws, grpc, httpupgrade, xhttp/splithttp, kcp), `security` (none/tls/reality), `sni`, `host`, `path`, `serviceName`, `mode`, `alpn`, `fp`, `flow`, `encryption`, `pbk`, `sid`, `spx`, `headerType`, `seed`, `allowInsecure`, `extra` (xhttp). Anything else: use a `json` node.

Examples:
```
config node 'home'
	option name 'VLESS Reality'
	option type 'link'
	option link 'vless://UUID@1.2.3.4:443?type=tcp&security=reality&sni=www.example.com&fp=chrome&pbk=KEY&sid=ab12&flow=xtls-rprx-vision#reality'

config node 'wg'
	option name 'WireGuard'
	option type 'json'
	option json '{"protocol":"wireguard","settings":{"secretKey":"…","address":["10.0.0.2/32"],"peers":[{"publicKey":"…","endpoint":"1.2.3.4:51820"}]}}'

config node 'ssh1'
	option name 'my server'
	option type 'ssh'
	option host '203.0.113.20'
	option user 'root'
	option password 'secret'
```

## `config iface`

```
config iface
	option name 'phy0-ap0'     # kernel device name: ls /sys/class/net
	option mode 'vpn'          # vpn | direct | block
```
- `vpn`: TCP → xray (REDIRECT), UDP → xray (TPROXY); anything that would be forwarded to the WAN is dropped.
- `direct`: untouched (but its DNS still goes through the tunnel).
- `block`: nothing may reach the WAN.
- Interfaces not listed are untouched. Traffic to private ranges (10/8, 172.16/12, 192.168/16, 169.254/16, 224/4, …) and to the router itself is never sent through the VPN.

## Editing a node (fragment, fingerprint, MTU, …)

In the web UI (*Nodes → Edit*) every node opens as a **form**, one box per area: *Connection* (address, port, UUID/password, flow, encryption), *Transport* (TCP, WebSocket, gRPC, HTTPUpgrade, XHTTP, mKCP with path/host/serviceName/mode/header/seed/**MTU**/TTI), *Security* (none, TLS, REALITY with SNI, **fingerprint**, ALPN, public key, short ID, SpiderX, allowInsecure) and *Advanced* (**Fragment**, Mux, TCP Fast Open). Choices are drop-downs with the valid values. Saving stores the node as the equivalent xray outbound (the original link is not kept). Protocols without a form (e.g. WireGuard) are edited as raw JSON. A JSON array is a chain: the first element is the exit, later ones are dialer hops; the Fragment option adds such a hop (a `freedom` outbound) automatically.

## `config device` — per-device override

```
config device
	option mac 'aa:bb:cc:dd:ee:ff'     # or: option ip '192.168.5.50'
	option mode 'direct'               # direct | vpn
```
`direct` skips the VPN even on a `vpn` interface; `vpn` forces the VPN on a `direct` interface.

## `config bypass`

```
config bypass
	list cidr '203.0.113.0/24'
	list cidr '8.8.8.8'
	list cidr 'example.ir'              # domain + all its sub-domains
	list cidr '*.ir'                    # every site under the .ir suffix
	list cidr 'full:www.bank.example'   # exactly this host
	list cidr 'keyword:shaparak'        # any host containing the word
```
Destinations that clients on `vpn` interfaces may reach **directly**, outside the tunnel. Interfaces in `block` mode are not affected. Two kinds of entries (the option is called `cidr` for historical reasons):

| Entry | Handled by | Behaviour |
|---|---|---|
| IPv4 or CIDR (`203.0.113.0/24`) | nftables | Never reaches xray and is exempt from the kill-switch, so it stays reachable **even while xray/the tunnel is down**. IPv4 only. |
| Domain (`example.ir`, `*.ir`, `domain:example.ir`, `full:www.example.ir`, `keyword:bank`) | xray routing rule → `direct` | Matched by the TLS SNI / HTTP Host / QUIC name that xray sniffs (sniffing is enabled automatically). A bare `example.ir` means the domain **and its sub-domains**; `*.ir` (or `.ir`) means **every site under that suffix** (a whole TLD such as `*.ir`, or `*.co.uk`). Only a leading `*.` is a wildcard: `a*.ir`, `*` and a bare `ir` are rejected. The traffic still passes through xray, so while xray is down these domains are **cut off like everything else** (the kill-switch holds). |

- `geosite:` / `geoip:` are **not supported** (the `.dat` files are not shipped and xray would refuse to start), neither is a bare word like `localhost`. Invalid entries are rejected by the web UI; in a hand-edited config they are ignored and written to `xguardctl logs` as `config warning`.
- A domain rule cannot see traffic that carries no name (plain IP, encrypted SNI/ECH); such traffic simply goes through the VPN.
- To also resolve these domains outside the tunnel set `dns_bypass` (see above).
- Use sparingly: every entry deliberately punches a hole in the VPN (not in the kill-switch).

## `config limit`

```
config limit
	option name 'kid'
	option ip '192.168.5.60'       # or: option mac '…' / option iface 'phy1-ap0'
	option down '4000'             # kbit/s, 0 or empty = unlimited
	option up '1000'
```
Implemented as nftables byte-rate **policers**: excess packets are dropped and TCP slows down. `mac` limits are applied to uploads by MAC and to downloads by the IPs found in `/tmp/dhcp.leases`.

## CLI: `xguardctl`

| Command | |
|---|---|
| `status` | Supervisor state (`status`, `node`, `alive`, `delay`, `rss_kb`, `avail_kb`, `restarts`, `xray_version`, …) |
| `logs` | Last lines of the `xguardd`, xray and ssh logs |
| `restart` / `next` | Restart xray / switch to the next node |
| `update-xray` | Drop the xray in RAM and fetch it again from `source` |
| `push-xray [sha256]` | Read `xray.gz` from stdin into RAM (see [INSTALL.md](INSTALL.md)) |
| `enable` / `disable` | Set `main.enabled` |
| `genkey` | Create `/etc/xguard/id_ed25519` and print the public key |
| `test-config <node>` | Run `xray run -test` on the generated config |

Status values: `running`, `degraded` (tunnel down, kill-switch active), `starting`, `restarting`, `fetching-xray`, `need-xray`, `updating`, `no-node`, `disabled`, `error`.
