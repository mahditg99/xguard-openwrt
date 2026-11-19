# راهنمای نصب

🇮🇷 فارسی · 🇬🇧 [English](INSTALL.md) · [← README](../README.fa.md)

## ۰. پیش‌نیازها

| | |
|---|---|
| روتر | **Xiaomi Mi Router 4A Gigabit** (`xiaomi,mi-router-4a-gigabit`، MT7621، ۱۲۸ مگابایت RAM، ۱۶ مگابایت فلش). بردهای دیگر: [BUILD.fa.md](BUILD.fa.md). |
| فریمور فعلی | باید از قبل **OpenWrt** داشته باشد (فایل Release یک ایمیج *sysupgrade* است). اگر روتر هنوز فریمور اصلی شیائومی را دارد، اول OpenWrt را طبق [صفحهٔ دستگاه در OpenWrt](https://openwrt.org/toh/xiaomi/mir4a_gigabit) نصب کنید و بعد اینجا ادامه دهید. |
| کامپیوتر | کلاینت `ssh` (لینوکس/مک/ویندوز ۱۰ به بالا) که به روتر دسترسی دارد. |
| یک نود VPN | لینک `vless://` / `vmess://` / `trojan://` / `ss://`، یا JSON خام outbound در xray، یا یک سرور SSH. |

> ⚠️ فلش کردن کل فریمور را عوض می‌کند. پشتیبان داشته باشید و هنگام فلش برق را قطع نکنید.

## ۱. دانلود و بررسی

از [آخرین Release](../../../releases/latest) این‌ها را بگیرید:

- `xguard-<tag>-openwrt-<ver>-xiaomi_mi-router-4a-gigabit-sysupgrade.bin` — فریمور
- `xray.gz` و `xray.gz.sha256` — Xray-core برای RAM روتر
- `SHA256SUMS`

```sh
sha256sum -c SHA256SUMS                    # لینوکس/مک
Get-FileHash <file> -Algorithm SHA256      # ویندوز PowerShell، با چشم مقایسه کنید
```

## ۲. پشتیبان‌گیری (روی روتری که الان OpenWrt دارد)

```sh
ssh root@<router> 'sysupgrade -b /tmp/backup.tar.gz && cat /tmp/backup.tar.gz' > router-config-backup.tar.gz
ssh root@<router> 'cat /dev/mtd3ro' > factory-mtd3.bin     # کالیبراسیون Wi-Fi (۶۴ کیلوبایت)
```
فایل `router-config-backup.tar.gz` رمز Wi‑Fi شما را دارد — خصوصی نگه دارید. `sysupgrade` به پارتیشن کالیبراسیون دست نمی‌زند، ولی نسخه‌اش را نگه دارید.

## ۳. فلش (نصب تمیز)

فریمور حاضر نمی‌شود تنظیمات نسخه‌های قدیمی OpenWrt را منتقل کند، پس **بدون نگه‌داشتن تنظیمات** فلش کنید:

```sh
ssh root@<router> 'cat > /tmp/fw.bin' < xguard-*-sysupgrade.bin
ssh root@<router> 'sysupgrade -T /tmp/fw.bin && sysupgrade -n /tmp/fw.bin'
```
(`-T` فقط ایمیج را آزمایش می‌کند، `-n` تنظیمات را پاک می‌کند.) با LuCI: *System ← Backup / Flash Firmware ← Flash image…* و تیک **Keep settings** را بردارید.

روتر خودش ری‌استارت می‌شود (حدود ۲ دقیقه). خاموشش نکنید.

## ۴. اولین بوت

- آدرس پیش‌فرض **`192.168.1.1`** است. اگر شبکهٔ بالادستی شما هم `192.168.1.0/24` است، **فقط یک کابل LAN به کامپیوتر** بزنید و تا برگرداندن/تغییر تنظیمات، کابل WAN را وصل نکنید.
- بلافاصله رمز root بگذارید: `ssh root@192.168.1.1` و بعد `passwd`.
- *(اختیاری)* تنظیمات قدیمی شبکه/Wi‑Fi را برگردانید:
  ```sh
  ssh root@192.168.1.1 'cat > /tmp/b.tar.gz' < router-config-backup.tar.gz
  ssh root@192.168.1.1 'sysupgrade -r /tmp/b.tar.gz && reboot'
  ```
  بازگردانی، `/etc/config/system` قدیمی را هم برمی‌گرداند و zram به اندازهٔ پیش‌فرض خودش (نصف RAM) برمی‌گردد که کار می‌کند. برای ثابت‌کردن: `uci set system.@system[0].zram_size_mb=48; uci commit system`.

## ۵. گذاشتن xray-core در RAM روتر

xray (۳۳ مگابایت بعد از باز شدن) روی فلش **جا نمی‌شود** و هرگز آنجا ذخیره نمی‌شود. در `/tmp/xguard/xray` است و بعد از هر بوت باید دوباره فراهم شود. یکی را انتخاب کنید:

### الف) از کامپیوتر push کنید (ساده‌ترین، دستی)

```sh
cat xray.gz | ssh root@<router> "xguardctl push-xray $(cut -d' ' -f1 xray.gz.sha256)"
```
ویندوز (از یک clone این مخزن، بعد از گذاشتن فایل‌های Release در `dist\`):
```powershell
powershell -File tools\push-xray.ps1 -Router <router>
```
روتر xray در حال اجرا را متوقف می‌کند (RAM جای دو نسخه ندارد)، نسخهٔ جدید را باز می‌کند، SHA-256 را بررسی می‌کند و ناظر آن را اجرا می‌کند.

### ب) روتر بعد از هر بوت خودش دانلود کند (پیشنهادی)

یک یا چند **منبع** بدهید (صفحهٔ وب ← *تنظیمات*، یا UCI). به ترتیب امتحان می‌شوند و تا بی‌نهایت با backoff تکرار می‌شوند:

```sh
uci add_list xguard.main.source='https://example.com/xguard/xray.gz'   # xray.gz.sha256 باید کنارش باشد
uci commit xguard
```
انواع منبع:
- `https://host/path/xray.gz` — هر میزبان ایستا (کنار آن `xray.gz.sha256`، یعنی همان آدرس + `.sha256`).
- `ssh://user@host[:port]/path/xray.gz` — سرور خودتان با SSH (کلید `/etc/xguard/id_ed25519` که با `xguardctl genkey` ساخته می‌شود)؛ یک ابزار قفل‌شده در [`tools/mirror/`](../tools/mirror) هست (`setup-mirror.sh`).
- فایل‌های Release در GitHub (`https://github.com/<owner>/<repo>/releases/download/<tag>/xray.gz`) هم ممکن است کار کنند اگر GitHub از روتر شما در دسترس باشد — به CDN ریدایرکت می‌شوند، پس با `xguardctl update-xray` و `xguardctl logs` امتحان کنید.

چرا zip رسمی نه؟ روتر `unzip` ندارد و باز کردن zip هم‌زمان ۱۰ + ۳۳ مگابایت RAM می‌خواهد. gzip مستقیم از `gunzip` رد می‌شود و سر جایش قرار می‌گیرد.

بررسی: `xguardctl status` مقدار `xray_version=…` و `status=…` را نشان می‌دهد.

## ۶. پیکربندی (صفحهٔ وب)

**`http://<router>/xguard/`** را باز کنید و با `root` وارد شوید.

1. **نودها** ← *افزودن نود*: لینک را بچسبانید (با *بررسی لینک*)، یا *JSON خام xray* / *SSH tunnel* را انتخاب کنید. یک نود را «اصلی» کنید؛ بقیه به ترتیب لیست failover هستند.
2. **شبکه** ← هر اینترفیس را **VPN**، **مستقیم** یا **مسدود** کنید. اینترفیس WAN را اینجا هرگز عوض نکنید. نام‌ها همان نام کرنل‌اند (`phy0-ap0` = Wi‑Fi ۲.۴ گیگ، `phy1-ap0` = ۵ گیگ، `lan1`، `lan2`، …).
3. *(اختیاری)* استثنای دستگاه‌ها، مقصدهایی که از VPN رد نمی‌شوند، **محدودیت سرعت**، **تنظیمات** (منابع، سقف حافظه، DNS، آدرس تست سلامت).
4. **فعال** (بالا) را روشن کنید. از این لحظه kill-switch برای همهٔ اینترفیس‌های VPN/مسدود فعال است.

معادل خط فرمان: [CONFIGURATION.fa.md](CONFIGURATION.fa.md).

## ۷. بررسی

```sh
xguardctl status        # status=running, alive=1, delay=…
```
- از یک کلاینت روی اینترفیس VPN: IP عمومی باید IP VPN باشد (مثلاً `curl https://ifconfig.me`).
- **آزمایش kill-switch:** روی روتر `touch /tmp/xguard/hold; killall xray` را بزنید. کلاینت باید کاملاً بدون اینترنت شود و `status` برابر `updating` می‌شود. بعد `rm /tmp/xguard/hold` — خودش برمی‌گردد.
- مصرف حافظه را در طول زمان ببینید: `xguardctl status` (`rss_kb`، `avail_kb`) و `free -m`.

## ۸. به‌روزرسانی

- **xray-core:** `xray.gz` جدید را بگیرید/بسازید و push کنید (۵الف) یا `xguardctl update-xray` بزنید (۵ب).
- **xguard/فریمور:** ایمیج Release جدید را فلش کنید. در همان سری OpenWrt می‌توانید `-n` را نزنید تا تنظیمات بماند (`/etc/config/xguard` حفظ می‌شود)؛ اول پشتیبان بگیرید. بعد از ریبوت xray باید دوباره فراهم شود.

## ۹. خاموش اضطراری / حذف

```sh
xguardctl disable                 # kill-switch و تنظیم DNS تا حدود ۵ ثانیه حذف می‌شوند
# یا حتی اگر ناظر مرده باشد:
/usr/sbin/xguardd unguard
```
برای برگشت به OpenWrt ساده، یک ایمیج رسمی OpenWrt را با `sysupgrade -n` فلش کنید.

## ۱۰. روش جایگزین: نصب به‌صورت بسته (بدون فلش)

برای روتری که **از قبل OpenWrt 24.10 (با opkg)** دارد و فضای فلش کافی دارد، Release یک فایل `xguard_<version>_all.ipk` (حدود ۳۰ کیلوبایت، مستقل از معماری) هم دارد. به‌جای جایگزین کردن سیستم، xguard را روی سیستم فعلی شما نصب می‌کند.

- وابستگی‌ها از feedهای OpenWrt می‌آیند (`ucode*`، `rpcd`، `rpcd-mod-ucode`، `uhttpd`، `uhttpd-mod-ubus`، `ip-full`، `kmod-nft-tproxy`، `kmod-zram`، `zram-swap`)، پس روتر برای `opkg update` اینترنت و ساعت درست لازم دارد. بسته‌های `kmod-*` باید با کرنل در حال اجرا یکی باشند.
- **فضای فلش:** وابستگی‌ها حدود ۱ مگابایت (تخمین) لازم دارند و برای نودهای SSH حدود ۱.۸ مگابایت بیشتر. اول `df -h /overlay` را ببینید. روی Xiaomi 4A Gigabit با ایمیج معمولی (حدود ۱ مگابایت خالی) **جا نمی‌شود** — از ایمیج فریمور استفاده کنید.
- OpenWrt 25.12 به بعد `apk` دارد؛ این `.ipk` برای `opkg` (نسخهٔ 24.10 و قدیمی‌تر) است.

```sh
ssh root@<router> 'cat > /tmp/xguard.ipk' < xguard_*_all.ipk
ssh root@<router> 'opkg update && opkg install /tmp/xguard.ipk'
ssh root@<router> 'opkg install openssh-client openssh-keygen sshpass'     # فقط برای نودهای SSH
```
بعد مراحل ۵ تا ۷ بالا را ادامه دهید (xray در RAM، صفحهٔ وب، بررسی). بسته xray-core را همراه ندارد. فایل `/etc/config/xguard` در آپدیت‌ها می‌ماند؛ `opkg remove xguard` kill-switch، تنظیم DNS و قانون مسیریابی را هم برمی‌دارد.

> فرمت بسته با parser خود `opkg` بررسی شده و چیدمان فایل‌ها با ایمیج فریمور یکی است، ولی نصب کامل روی یک روتر زنده هنوز آزمایش نشده است.
