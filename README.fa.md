# xguard

**VPN برای کل روتر با kill-switch واقعی (fail-closed) روی OpenWrt، با xray-core که فقط در RAM اجرا می‌شود.**

🇮🇷 فارسی · 🇬🇧 [English](README.md)

xguard یک جایگزین سبک برای passwall روی روترهای کوچک است. روتر OpenWrt را به یک دروازهٔ VPN تبدیل می‌کند: مشخص می‌کنید کدام Wi‑Fi یا پورت LAN از تونل رد شود و کدام نه، و اگر تونل قطع شود، آن دستگاه‌ها **هیچ اینترنتی ندارند** (به‌جای اینکه بی‌صدا از اینترنت مستقیم استفاده کنند).

هدف اصلی **Xiaomi Mi Router 4A Gigabit** است (MT7621، ۱۲۸ مگابایت RAM، ۱۶ مگابایت فلش، OpenWrt 24.10). مشکل اصلی این روتر حافظه است: باینری آخرین xray-core بعد از باز شدن **۳۳ مگابایت** است («۹ مگابایت» حجم فشردهٔ دانلود است)، فلش با ایمیج معمولی حدود ۱ مگابایت جای خالی دارد و passwall کامل کم‌کم RAM را پر می‌کرد. xguard دور همین محدودیت‌ها طراحی شده است.

> **وضعیت: پیش‌انتشار 0.x.** تولید کانفیگ، قوانین kill-switch، ناظر و API با آزمون‌های خودکار پوشش داده شده‌اند ([آزمون‌ها](#آزمون‌ها)). رفتار با ترافیک واقعی (سرعت، RAM در چند روز، قطعی واقعی) هنوز روی سخت‌افزار در حال بررسی است — لطفاً نتایج را گزارش کنید.

## امکانات

- **VPN برای هر اینترفیس:** هر دستگاه شبکه (Wi‑Fi، پورت LAN، …) یکی از `vpn` / `direct` / `block` است؛ استثنای هر دستگاه (MAC/IP) هم دارد.
- **kill-switch واقعی (fail-closed):** قوانین nftables *قبل از* بالا آمدن شبکه لود می‌شوند و در ری‌استارت xray، تعویض نود و کرش برقرار می‌مانند. دستگاه‌های روی اینترفیس VPN هرگز به WAN فوروارد نمی‌شوند.
- **تلاش مجدد تا بی‌نهایت:** respawn بدون سقف procd، ری‌استارت xray با backoff، تعویض خودکار به نود بعدی، دانلود مجدد باینری، SSH با keepalive.
- **هر چیزی که xray پشتیبانی می‌کند:** لینک‌های `vless://`، `vmess://`، `trojan://`، `ss://`، `socks://` (TCP، WS، gRPC، HTTPUpgrade، XHTTP، mKCP، TLS، Reality، Vision) **و JSON خام outbound** برای بقیه (WireGuard، Hysteria، زنجیرهٔ `dialerProxy`، …).
- **SSH tunnel** به‌صورت outbound (`ssh -D` ← outbound از نوع socks در xray). خود xray SSH ندارد.
- **محدودیت سرعت** برای هر دستگاه (IP، MAC یا اینترفیس؛ دانلود و آپلود جدا؛ policing با nftables).
- **بدون نشت DNS:** dnsmasq فقط از داخل تونل resolve می‌کند.
- **ساخته‌شده برای ۱۲۸ مگابایت:** xray فقط در RAM (هرگز روی فلش)، zram swap، `GOMEMLIMIT`، سقف RSS با ری‌استارت خودکار، conntrack محدود، بدون geoip/geosite، لاگ‌های چرخشی کوچک.
- **صفحهٔ وب** (فارسی، راست‌به‌چپ) در `http://<router>/xguard/` و CLI به نام `xguardctl`.

## نصب سریع

روتری لازم دارید که از قبل OpenWrt دارد (برای `sysupgrade`) و یک PC با `ssh`.

1. از [آخرین Release](../../releases/latest) این فایل‌ها را بگیرید: `…-sysupgrade.bin`، `xray.gz`، `xray.gz.sha256`، `SHA256SUMS`. با `sha256sum -c SHA256SUMS` بررسی کنید.
2. **اول پشتیبان بگیرید** (`sysupgrade -b /tmp/backup.tar.gz` و برای کالیبراسیون Wi‑Fi: `cat /dev/mtd3ro > factory.bin`)، بعد **بدون نگه‌داشتن تنظیمات** فلش کنید:
   ```sh
   scp -O xguard-*-sysupgrade.bin root@192.168.1.1:/tmp/fw.bin
   ssh root@192.168.1.1 sysupgrade -n /tmp/fw.bin
   ```
3. رمز root بگذارید (`passwd`) و اگر خواستید پشتیبان تنظیمات شبکه/Wi‑Fi را برگردانید.
4. xray را در RAM روتر بگذارید (بعد از هر ریبوت دوباره لازم است، مگر منبع دانلود تنظیم کنید):
   ```sh
   cat xray.gz | ssh root@<router> "xguardctl push-xray $(cut -d' ' -f1 xray.gz.sha256)"
   ```
   ویندوز: `powershell -File tools\push-xray.ps1 -Router <router>`.
5. `http://<router>/xguard/` را باز کنید ← **نودها**: لینک را بچسبانید ← **شبکه**: اینترفیس‌ها را `VPN` کنید ← **فعال** را روشن کنید.

جزئیات: **[docs/INSTALL.fa.md](docs/INSTALL.fa.md)** · [پیکربندی](docs/CONFIGURATION.fa.md) · [عیب‌یابی](docs/TROUBLESHOOTING.fa.md) · [ساخت و Release](docs/BUILD.fa.md)

## چگونه کار می‌کند

```
 کلاینت‌ها ─► nftables (جدول مستقل، قبل از fw4) ─► xray-core (فقط RAM)
                │ REDIRECT (tcp) / TPROXY (udp)         ├─ vless / vmess / trojan / ss / wireguard …
                │ kill-switch، محدودیت سرعت             └─ socks ◄─ ssh -D   (SSH tunnel)
                ▼
          ناظر xguardd (ash): تست سلامت، failover، نگهبان حافظه، تنظیم ساعت،
                              تلاش بی‌پایان، دانلود xray داخل tmpfs
```

- `files/` همان overlay سیستم‌فایل است که داخل ایمیج می‌رود (init، ناظر، مولدهای ucode، API، صفحهٔ وب).
- ایمیج با ImageBuilder رسمی OpenWrt ساخته می‌شود (بدون LuCI و ppp/odhcp6c) و `kmod-nft-tproxy`، `zram-swap`، `openssh-client`، `rpcd`/`uhttpd`، `ip-full` اضافه دارد.
- xray-core **باینری رسمی بدون تغییر** است (`xray_softfloat` که gzip شده). داخل tmpfs دانلود/push می‌شود و با SHA-256 تأیید می‌شود.

## محدودیت‌هایی که باید بدانید

- **فقط IPv4.** IPv6 دستگاه‌های VPN/مسدود توسط kill-switch دور ریخته می‌شود (تونل نمی‌شود).
- ترافیک **خود روتر** (opkg، NTP، …) پروکسی نمی‌شود.
- DNS **همهٔ** دستگاه‌ها (حتی اینترفیس‌های `direct`) از تونل می‌گذرد؛ اگر xray قطع باشد DNS هم قطع است (عمداً، برای جلوگیری از نشت).
- محدودیت سرعت از نوع **policing** است (بسته‌های اضافه دور ریخته می‌شوند)، نه shaping نرم.
- نودهای SSH فقط TCP حمل می‌کنند (UDP نه؛ QUIC بسته می‌شود تا مرورگر به TCP برگردد).
- لینک‌های `hysteria2://` هنوز parse نمی‌شوند — از نود JSON خام استفاده کنید.
- سرعت به CPU مدل MT7621 محدود است (بدون شتاب AES)؛ انتظار چند ده Mbps داشته باشید نه صدها. اندازه‌گیری‌های شما ارزشمند است.
- فقط Xiaomi Mi Router 4A Gigabit پشتیبانی/آزمایش شده؛ برای بردهای دیگر [docs/BUILD.fa.md](docs/BUILD.fa.md) را ببینید.

## آزمون‌ها

```
tests/sim-supervisor.sh   xguardd واقعی + مولدهای ucode واقعی در sandbox (nft/ip/uci جعلی، xray جعلی): ۳۳ بررسی
CI                        بررسی نحو shell/JS/JSON
دستی (انجام‌شده)          کانفیگ‌های تولیدی با `xray run -test`؛ ruleset با `nft -c`؛ ایمیج با `sysupgrade -T`
```
پوشش خودکار ندارد: ترافیک زنده، kill-switch در قطعی واقعی، سرعت، رفتار RAM در چند روز، صفحهٔ وب روی rpcd زنده.

## نکات امنیتی

- OpenWrt **بدون رمز root** می‌آید — رمز بگذارید. صفحهٔ وب و SSH هر دو از آن استفاده می‌کنند.
- صفحهٔ وب HTTP ساده روی پورت ۸۰ همهٔ اینترفیس‌هاست (سیاست پیش‌فرض fw4 آن را از سمت WAN رد می‌کند). به شبکه‌های نامطمئن در معرض قرار ندهید.
- رمز نودهای SSH در `/etc/config/xguard` (دسترسی 600) ذخیره می‌شود. کلید ترجیح دارد (`xguardctl genkey`).
- پشتیبان روتر (`sysupgrade -b`) را هرگز منتشر نکنید: رمز Wi‑Fi دارد.

## مجوز

MIT برای کد خود xguard ([LICENSE](LICENSE)). Releaseها OpenWrt و باینری بدون تغییر Xray-core را با مجوز خودشان همراه دارند — [NOTICE.md](NOTICE.md). وابسته به OpenWrt، XTLS/Xray، Xiaomi یا passwall نیست.
