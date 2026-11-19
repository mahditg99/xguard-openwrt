# Changelog / تاریخچهٔ تغییرات

## 0.1.0-rc4

**EN**
- `config bypass` now accepts **domains** besides IPv4/CIDR: `example.ir` (with sub-domains), `full:host`, `keyword:word`. Domains become an xray `direct` routing rule (sniffing is switched on automatically); IPs/CIDRs still use nftables. New optional `dns_bypass` resolver for those domains.
- Invalid bypass entries are rejected by the web UI and logged as `config warning` instead of being silently dropped.
- Verified with `xray run -test`, a live xray run (split DNS + SNI routing on a test host) and 39 supervisor-simulation checks.

**FA**
- `config bypass` علاوه بر IPv4/CIDR حالا **دامنه** هم می‌پذیرد: `example.ir` (با زیردامنه‌ها)، `full:host` و `keyword:word`. دامنه‌ها به قانون مسیریابی `direct` در xray تبدیل می‌شوند (sniffing خودکار روشن می‌شود)؛ IP/CIDR همچنان با nftables است. گزینهٔ اختیاری جدید `dns_bypass` برای resolve این دامنه‌ها.
- ورودی نامعتبر bypass حالا در صفحهٔ وب رد می‌شود و در لاگ با `config warning` ثبت می‌شود؛ دیگر بی‌صدا حذف نمی‌شود.
- با `xray run -test`، اجرای واقعی xray (DNS جداگانه + مسیریابی SNI روی یک میزبان آزمایشی) و ۳۹ بررسی شبیه‌ساز ناظر تأیید شد.

## 0.1.0 — first public pre-release / اولین پیش‌انتشار

**EN**
- Kill-switch (fail-closed) per interface (`vpn` / `direct` / `block`), per-device exceptions, user bypass list.
- xray-core (official `xray_softfloat`, v26.11.9) running only from RAM; downloaded/pushed into tmpfs and verified by SHA-256; direct bootstrap DNS so the first download works while the tunnel is down.
- Supervisor with endless retries, node failover, memory watchdog (RSS and `MemAvailable`), clock fix from the HTTP `Date:` header.
- Share links (`vless`, `vmess`, `trojan`, `ss`, `socks`) + raw JSON outbounds/chains + SSH tunnel (`ssh -D`).
- Per-IP/MAC/interface speed limits (nftables policing), DNS through the tunnel only.
- Persian web UI (`/xguard/`), `xguardctl` CLI, rpcd API.
- `xguard_<ver>_all.ipk` for installing on an existing OpenWrt (opkg).
- OpenWrt 24.10.8 image for the Xiaomi Mi Router 4A Gigabit (no LuCI, zram swap, `kmod-nft-tproxy`, openssh-client).
- Tested: generated configs with `xray run -test`, ruleset with `nft -c`, supervisor sandbox simulation (34 checks), image with `sysupgrade -T`.
- **Not yet verified on live traffic:** throughput, multi-day RAM behaviour, kill-switch during a real outage, web UI against a live rpcd.

**FA**
- kill-switch (fail-closed) برای هر اینترفیس (`vpn` / `direct` / `block`)، استثنای هر دستگاه و لیست bypass.
- xray-core (نسخهٔ رسمی `xray_softfloat`، v26.11.9) فقط از RAM؛ داخل tmpfs دانلود/push و با SHA-256 تأیید می‌شود؛ DNS بوت‌استرپ مستقیم برای اینکه اولین دانلود با تونل قطع هم کار کند.
- ناظر با تلاش بی‌پایان، failover نودها، نگهبان حافظه (RSS و `MemAvailable`) و اصلاح ساعت از هدر `Date:` در HTTP.
- لینک‌های اشتراک (`vless`، `vmess`، `trojan`، `ss`، `socks`) + outbound/زنجیرهٔ JSON خام + SSH tunnel (`ssh -D`).
- محدودیت سرعت هر IP/MAC/اینترفیس (policing با nftables)، DNS فقط از تونل.
- صفحهٔ وب فارسی (`/xguard/`)، CLI به نام `xguardctl`، API روی rpcd.
- بستهٔ `xguard_<ver>_all.ipk` برای نصب روی OpenWrt موجود (opkg).
- ایمیج OpenWrt 24.10.8 برای Xiaomi Mi Router 4A Gigabit (بدون LuCI، zram swap، `kmod-nft-tproxy`، openssh-client).
- آزمایش‌شده: کانفیگ‌های تولیدی با `xray run -test`، ruleset با `nft -c`، شبیه‌سازی ناظر در sandbox (۳۴ بررسی)، ایمیج با `sysupgrade -T`.
- **هنوز روی ترافیک زنده تأیید نشده:** سرعت، رفتار RAM در چند روز، kill-switch در قطعی واقعی، صفحهٔ وب روی rpcd زنده.
