# Building and releasing

🇮🇷 [فارسی](BUILD.fa.md) · 🇬🇧 English · [← README](../README.md)

## Repository layout

```
files/    root-filesystem overlay baked into the image (what runs on the router)
tools/    build-xray.{sh,ps1}  build-image.sh  build-release.sh  push-xray.ps1  mirror/
tests/    sim-supervisor.sh (sandbox simulation)  xguard.sample (example config)
docs/     this documentation (English + Persian)
.github/  workflows: ci (syntax checks), release (builds and publishes a Release on a tag)
```

## Publishing a release on GitHub (what the maintainer does)

1. Create the repository, push the code (`main`). When committing from **Windows**, keep the scripts executable for Linux users: after `git add -A` run
   `git update-index --chmod=+x tools/*.sh tools/mirror/*.sh tests/*.sh files/usr/sbin/xguardd files/usr/sbin/xguardctl files/usr/libexec/xguard/fetch files/etc/init.d/xguard files/etc/uci-defaults/90-xguard`
   (the release scripts also work as `bash tools/…` and set the modes inside the image themselves).
2. Create a tag and push it:
   ```sh
   git tag v0.1.0
   git push origin v0.1.0
   ```
3. The **release** workflow builds the image and `xray.gz` on a GitHub runner and creates the Release with:
   `xguard-<tag>-openwrt-<ver>-xiaomi_mi-router-4a-gigabit-sysupgrade.bin`, `xray.gz`, `xray.gz.sha256`, `xray.version`, `xguard-<tag>-package-manifest.txt`, `SHA256SUMS`.
   Tags starting with `v0.` are marked *pre-release*.
4. Rebuild with other versions without a tag: *Actions → release → Run workflow* (inputs: `tag`, `openwrt`, `xray`).

Defaults (OpenWrt `24.10.8`, Xray-core `v26.11.9`) are set in `.github/workflows/release.yml` and `tools/build-release.sh`. Bump them deliberately: a new Xray-core version should be checked with `xray run -test` against the generated configs (see below).

Release notes pick up the repository name from `$GITHUB_REPOSITORY` automatically. Review `LICENSE` (MIT by default) and `NOTICE.md` before the first release.

## Building locally

### xray.gz

```sh
tools/build-xray.sh v26.11.9            # Linux/macOS/Git Bash → dist/xray.gz (+ .sha256, .version)
powershell -File tools\build-xray.ps1   # Windows equivalent
```
Downloads the official `Xray-linux-mips32le.zip`, verifies it against the project's `.dgst`, extracts `xray_softfloat` (the MT7621 userland is soft-float), writes `xray.gz` and the sha256 of the **uncompressed** binary.

### Firmware image

Needs x86_64 Linux with: `make zstd rsync xz-utils file wget gawk perl patch bzip2 python3 unzip curl` (about 1.2 GB of disk while building).

```sh
tools/build-release.sh v0.1.0 24.10.8       # everything, into ./release
# or only the image (expects tools/xguard-files.tar = tar of files/):
tar cf tools/xguard-files.tar -C files . && tools/build-image.sh 24.10.8
```
`build-image.sh` downloads the official ImageBuilder, removes `ppp`, `ppp-mod-pppoe`, `odhcp6c`, `odhcpd-ipv6only`, adds the packages listed in the script and overlays `files/`. On Windows use WSL or a Linux VM/server.

## Tests you can run

```sh
sh -n files/usr/sbin/xguardd          # syntax of every shell script (CI does all of them)
tests/sim-supervisor.sh               # needs a router (or any OpenWrt/ucode box): see the header of the file
```
`sim-supervisor.sh` runs the real `xguardd`, `core.uc`, `gen.uc` in a sandbox under `/tmp/xgsim` with stubbed `nft`, `ip`, `uci`, `nc`, `date`, `uclient-fetch` and a fake xray — it never touches the network configuration.

Validate generated xray configs with the real binary (any platform):
```sh
XGUARD_CONFDIR=<dir containing a file named "xguard"> ucode files/usr/lib/xguard/gen.uc xray <node-id> > cfg.json   # on a box with ucode
xray run -test -c cfg.json
```
`tests/xguard.sample` is an example `/etc/config/xguard` with one node of every kind.

## Other boards

Only `xiaomi_mi-router-4a-gigabit` is built and tested. For another MT7621 board with ≥128 MB RAM change `PROFILE` in `tools/build-image.sh` (list: `make info` inside the ImageBuilder) and make sure that the target is `ramips/mt7621`. Another CPU architecture needs the matching ImageBuilder **and** the matching Xray-core zip (`build-xray.sh` hard-codes `mips32le` / `xray_softfloat`). Less RAM than 128 MB is not recommended; flash space must also hold the image (the 4A's partition is 14.5 MB; the image uses ≈ 8.3 MB).

## How the pieces fit (for contributors)

- `gen.uc xray|nft|lockdown|…` (ucode) turns `/etc/config/xguard` into the xray JSON config and the nftables ruleset; `links.uc` parses share links.
- `xguardd` (POSIX sh, busybox ash) is the supervisor; `files/etc/init.d/xguard` (procd) starts it with unlimited respawn. Busybox on this target has **no** `pkill`, `nc -w`, fractional `sleep`, `unzip`; `kill -0` succeeds on zombies — use `pid_alive`.
- ucode modules use `export { … };` lists and relative imports (`./core.uc`).
- The web UI is a single static file talking to `rpcd` (`xguard.uc` plugin) through `/ubus`.
