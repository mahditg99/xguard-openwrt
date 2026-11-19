# ساخت و انتشار

🇮🇷 فارسی · 🇬🇧 [English](BUILD.md) · [← README](../README.fa.md)

## ساختار مخزن

```
files/    overlay سیستم‌فایل که داخل ایمیج می‌رود (آنچه روی روتر اجرا می‌شود)
tools/    build-xray.{sh,ps1}  build-image.sh  build-release.sh  push-xray.ps1  mirror/
tests/    sim-supervisor.sh (شبیه‌سازی در sandbox)  xguard.sample (نمونهٔ تنظیمات)
docs/     همین مستندات (انگلیسی + فارسی)
.github/  workflowها: ci (بررسی نحو)، release (با تگ، Release می‌سازد و منتشر می‌کند)
```

## انتشار Release در GitHub (کار نگه‌دارنده)

1. مخزن را بسازید و کد را push کنید (`main`). اگر از **ویندوز** commit می‌کنید، برای کاربران لینوکس اسکریپت‌ها را اجرایی نگه دارید: بعد از `git add -A` این را بزنید:
   `git update-index --chmod=+x tools/*.sh tools/mirror/*.sh tests/*.sh files/usr/sbin/xguardd files/usr/sbin/xguardctl files/usr/libexec/xguard/fetch files/etc/init.d/xguard files/etc/uci-defaults/90-xguard`
   (اسکریپت‌های Release به‌صورت `bash tools/…` هم کار می‌کنند و دسترسی‌ها را داخل ایمیج خودشان تنظیم می‌کنند).
2. تگ بسازید و push کنید:
   ```sh
   git tag v0.1.0
   git push origin v0.1.0
   ```
3. workflow به نام **release** روی runner گیت‌هاب ایمیج و `xray.gz` را می‌سازد و Release را با این فایل‌ها ایجاد می‌کند:
   `xguard-<tag>-openwrt-<ver>-xiaomi_mi-router-4a-gigabit-sysupgrade.bin`، `xray.gz`، `xray.gz.sha256`، `xray.version`، `xguard-<tag>-package-manifest.txt`، `SHA256SUMS`.
   تگ‌هایی که با `v0.` شروع شوند *pre-release* علامت می‌خورند.
4. ساخت با نسخه‌های دیگر بدون تگ: *Actions ← release ← Run workflow* (ورودی‌ها: `tag`، `openwrt`، `xray`).

پیش‌فرض‌ها (OpenWrt `24.10.8`، Xray-core `v26.11.9`) در `.github/workflows/release.yml` و `tools/build-release.sh` هستند. آگاهانه عوضشان کنید: نسخهٔ جدید Xray-core را با `xray run -test` روی کانفیگ‌های تولیدی بررسی کنید (پایین را ببینید).

یادداشت Release نام مخزن را خودکار از `$GITHUB_REPOSITORY` برمی‌دارد. قبل از اولین Release مجوز `LICENSE` (پیش‌فرض MIT) و `NOTICE.md` را مرور کنید.

## ساخت محلی

### xray.gz

```sh
tools/build-xray.sh v26.11.9            # لینوکس/مک/Git Bash ← dist/xray.gz (+ .sha256, .version)
powershell -File tools\build-xray.ps1   # معادل ویندوز
```
فایل رسمی `Xray-linux-mips32le.zip` را می‌گیرد، با `.dgst` خود پروژه تأیید می‌کند، `xray_softfloat` را بیرون می‌آورد (فضای کاربر MT7621 soft-float است) و `xray.gz` و sha256 باینری **باز‌شده** را می‌نویسد.

### ایمیج فریمور

x86_64 لینوکس با این ابزارها: `make zstd rsync xz-utils file wget gawk perl patch bzip2 python3 unzip curl` (هنگام ساخت حدود ۱.۲ گیگابایت دیسک).

```sh
tools/build-release.sh v0.1.0 24.10.8       # همه‌چیز، داخل ./release
# یا فقط ایمیج (انتظار دارد tools/xguard-files.tar = tar از files/ باشد):
tar cf tools/xguard-files.tar -C files . && tools/build-image.sh 24.10.8
```
`build-image.sh` ImageBuilder رسمی را می‌گیرد، `ppp`، `ppp-mod-pppoe`، `odhcp6c`، `odhcpd-ipv6only` را حذف می‌کند، بسته‌های فهرست‌شده در اسکریپت را اضافه می‌کند و `files/` را روی آن می‌ریزد. در ویندوز از WSL یا یک ماشین/سرور لینوکس استفاده کنید.

## آزمون‌هایی که می‌توانید اجرا کنید

```sh
sh -n files/usr/sbin/xguardd          # نحو هر اسکریپت shell (CI همه را انجام می‌دهد)
tests/sim-supervisor.sh               # یک روتر (یا هر دستگاه OpenWrt/ucode) لازم دارد: ابتدای فایل را ببینید
```
`sim-supervisor.sh` همان `xguardd`، `core.uc` و `gen.uc` واقعی را در sandbox زیر `/tmp/xgsim` با `nft`، `ip`، `uci`، `nc`، `date`، `uclient-fetch` جعلی و یک xray جعلی اجرا می‌کند — به تنظیمات شبکه دست نمی‌زند.

کانفیگ‌های تولیدی xray را با باینری واقعی بررسی کنید (هر پلتفرم):
```sh
XGUARD_CONFDIR=<پوشه‌ای که فایلی به نام "xguard" دارد> ucode files/usr/lib/xguard/gen.uc xray <node-id> > cfg.json   # روی دستگاه دارای ucode
xray run -test -c cfg.json
```
`tests/xguard.sample` نمونهٔ `/etc/config/xguard` با یک نود از هر نوع است.

## بردهای دیگر

فقط `xiaomi_mi-router-4a-gigabit` ساخته و آزمایش شده. برای برد MT7621 دیگری با ≥۱۲۸ مگابایت RAM مقدار `PROFILE` را در `tools/build-image.sh` عوض کنید (فهرست: `make info` داخل ImageBuilder) و مطمئن شوید target برابر `ramips/mt7621` است. معماری CPU دیگر هم ImageBuilder مناسب **و** zip مناسب Xray-core را می‌خواهد (`build-xray.sh` مقدار `mips32le` / `xray_softfloat` را ثابت دارد). کمتر از ۱۲۸ مگابایت RAM توصیه نمی‌شود؛ فضای فلش هم باید ایمیج را بگیرد (پارتیشن 4A برابر ۱۴.۵ مگابایت است؛ ایمیج حدود ۸.۳ مگابایت).

## اجزا چگونه به هم وصل‌اند (برای مشارکت‌کنندگان)

- `gen.uc xray|nft|lockdown|…` (ucode) فایل `/etc/config/xguard` را به کانفیگ JSON xray و ruleset nftables تبدیل می‌کند؛ `links.uc` لینک‌های اشتراک را parse می‌کند.
- `xguardd` (POSIX sh، busybox ash) ناظر است؛ `files/etc/init.d/xguard` (procd) آن را با respawn بی‌پایان اجرا می‌کند. busybox این target **ندارد**: `pkill`، `nc -w`، `sleep` اعشاری، `unzip`؛ و `kill -0` روی zombie موفق می‌شود — از `pid_alive` استفاده کنید.
- ماژول‌های ucode از لیست `export { … };` و importهای نسبی (`./core.uc`) استفاده می‌کنند.
- صفحهٔ وب یک فایل ایستاست که از طریق `/ubus` با `rpcd` (پلاگین `xguard.uc`) حرف می‌زند.
