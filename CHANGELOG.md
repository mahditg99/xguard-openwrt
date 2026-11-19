# Changelog / تاریخچهٔ تغییرات

## 0.1.0-rc6

**EN**
- Exempt domains: dnsmasq gets a direct upstream per domain (works with stock dnsmasq) and, with `dnsmasq-full` (nftset), the resolved IPs are added to the nft set `bypass_dyn`, which the kill-switch skips, so the domains work even with xray down.
- Fix (important): when the node address is a host name, xray resolved it through the router's resolver, which forwards to xray itself, so the tunnel could never come up once xguard was enabled ("node is dead"). xray now resolves the node's name itself via the bootstrap DNS, outside the tunnel.
- Exempt (bypass) domains are now resolved outside the tunnel by default (the WAN's upstream resolver, else bootstrap DNS). A single dead node no longer restarts xray every 30 s (which also cut the exempt domains): xray keeps running and keeps probing.
- UI: the per-device mode selector was removed (a special device is always the opposite of the default policy).
- New global policy `default_mode` (`direct` | `vpn`): either everybody is direct and only chosen interfaces/devices use the VPN, or everybody uses the VPN (fail-closed) and only chosen ones are exempt. Also covers devices that are not listed anywhere. Interface mode `direct` now works in `vpn` policy.
- Web UI: nodes are edited in a sectioned form (connection, transport, security, advanced: fingerprint, fragment, mux, MTU, ALPN, REALITY keys, ...) with drop-downs; raw JSON only for protocols without a form.
- Fix: drop-down menus always showed their last option as selected. Warning card when no interface is set to VPN.
- Fix: `push-xray` raced with the supervisor's retry sleep, which then deleted the freshly pushed binary. The supervisor now wakes for operator commands.
- Fix: the xray version shown is read from the binary (was stale while idle).
- Mirror helpers for HTTPS with a pinned self-signed certificate (`tools/mirror/setup-https-mirror.sh`, `/etc/xguard/pin/<host>.crt`).

**FA**
- دامنه‌های استثنا: dnsmasq برای هر دامنه upstream مستقیم می‌گیرد (با dnsmasq معمولی هم کار می‌کند) و با `dnsmasq-full` (nftset) IPهای resolve‌شده در مجموعهٔ nft به نام `bypass_dyn` می‌روند که kill-switch آن را رد می‌کند؛ پس دامنه‌ها حتی با xray خاموش کار می‌کنند.
- رفع باگ (مهم): وقتی آدرس نود یک نام میزبان بود، xray آن را از resolver روتر می‌پرسید که خودش به xray می‌رفت؛ پس بعد از روشن شدن xguard تونل هرگز بالا نمی‌آمد («node is dead»). حالا xray نام نود را خودش و با DNS بوت‌استرپ، بیرون از تونل resolve می‌کند.
- دامنه‌های استثنا (bypass) حالا به‌طور پیش‌فرض بیرون از تونل resolve می‌شوند (DNS بالادست WAN، وگرنه DNS بوت‌استرپ). یک نود مرده دیگر هر ۳۰ ثانیه xray را ری‌استارت نمی‌کند (که دامنه‌های استثنا را هم قطع می‌کرد): xray روشن می‌ماند و پروب ادامه دارد.
- رابط: انتخاب «حالت» هر دستگاه حذف شد (دستگاه ویژه همیشه برعکس سیاست پیش‌فرض است).
- سیاست سراسری جدید `default_mode` (`direct` | `vpn`): یا همه مستقیم‌اند و فقط اینترفیس/دستگاه‌های انتخابی VPN می‌شوند، یا همه از VPN می‌گذرند (fail-closed) و فقط انتخابی‌ها مستثنا هستند. دستگاه‌های تعریف‌نشده را هم پوشش می‌دهد. حالت `direct` اینترفیس حالا در سیاست `vpn` کار می‌کند.
- صفحهٔ وب: نودها در فرم بخش‌بندی‌شده ویرایش می‌شوند (اتصال، انتقال، امنیت، پیشرفته: fingerprint، fragment، mux، MTU، ALPN، کلیدهای REALITY و …) با لیست کشویی؛ JSON خام فقط برای پروتکل‌های بدون فرم.
- رفع باگ: لیست‌های کشویی همیشه آخرین گزینه را انتخاب‌شده نشان می‌دادند. کارت هشدار وقتی هیچ اینترفیسی روی VPN نیست.
- رفع باگ: `push-xray` با خواب تلاش دوبارهٔ ناظر ناهم‌زمان می‌شد و ناظر باینری تازه‌فرستاده را پاک می‌کرد. حالا ناظر برای فرمان اپراتور زود بیدار می‌شود.
- رفع باگ: نسخهٔ xray از خود باینری خوانده می‌شود (در حالت بیکار کهنه بود).
- ابزار mirror برای HTTPS با گواهی self-signed پین‌شده (`tools/mirror/setup-https-mirror.sh`، `/etc/xguard/pin/<host>.crt`).

## 0.1.0-rc5

**EN**
- Bypass wildcard: `*.ir` / `.ir` = every site under that suffix (also `*.co.uk`, `*.example.ir`).
- LuCI: new menu entry **Services → xguard VPN** (embeds the xguard UI, reuses the LuCI session, no second login).

**FA**
- wildcard در bypass: `*.ir` / `.ir` یعنی همهٔ سایت‌های زیر آن پسوند (و `*.co.uk` و `*.example.ir`).
- LuCI: منوی جدید **Services ← xguard VPN** (رابط xguard را داخل خودش نشان می‌دهد، از نشست LuCI استفاده می‌کند و ورود دوباره نمی‌خواهد).

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
