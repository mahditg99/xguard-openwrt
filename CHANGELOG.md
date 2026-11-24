# Changelog / تاریخچهٔ تغییرات

## 1.2.0 — default allowance, exempted domains actually exempted / سقف پیش‌فرض و رفع استثنای دامنه‌ای

**EN**
- New **blacklist** (`config block`, tab *Network and devices*): domains / IPv4 / CIDR nobody may reach; ready-made lists for background updates; **block** button in the usage report.
- Usage report keeps **full host names** (random per-connection labels collapsed to `*.site`), shown two-level: app or site, then hosts. Windows / Apple / Google Play / Xiaomi updates are grouped separately.
- Fix (important, present since 0.1.0): addresses of exempted **domains** never reached the nft set `bypass_dyn`: xguard wrote an option OpenWrt's dnsmasq ignores. Those sites therefore still went through xray, were counted as **VPN**, were slowed when the VPN allowance ran out, and stopped working when the tunnel was down. It now uses a `config ipset` section (`dhcp.xguard_bypass`).
- Also: cached DNS answers of exempted domains are added from the query log, addresses stay while in use and survive ruleset reloads; removing a domain flushes the set.
- Fix: raising the allowance of a throttled user did not free them.
- New **default allowance** (`def_wl_mb`, `def_wl_kbps`, `def_vpn_mb`, `def_vpn_kbps`): per-device daily quota for everybody without an own quota who is not excepted from `default_mode`. In `direct` mode it is the whitelist allowance only; in `vpn` mode both.
- Fix: with an empty `dhcp.leases` (after a reboot) MAC-based quotas found no address; the ARP table is used as well.

**FA**
- **لیست سیاه** جدید (`config block`، تب *شبکه و دستگاه‌ها*): دامنه / IPv4 / CIDR که هیچ‌کس به آن‌ها نمی‌رسد؛ لیست آماده برای به‌روزرسانی‌های پس‌زمینه؛ دکمهٔ **مسدود** در گزارش مصرف.
- گزارش مصرف **نام کامل میزبان‌ها** را نگه می‌دارد (برچسب‌های تصادفی هر اتصال به `*.site` جمع می‌شود) و دو سطحی نشان می‌دهد: برنامه یا سایت، بعد میزبان‌ها. آپدیت‌های ویندوز / اپل / Google Play / شیائومی جدا گروه می‌شوند.
- رفع باگ (مهم، از 0.1.0): آدرس **دامنه‌های** استثنا هرگز به مجموعهٔ `bypass_dyn` نمی‌رسید چون xguard گزینه‌ای می‌نوشت که dnsmasq در OpenWrt نادیده می‌گیرد. پس آن سایت‌ها همچنان از xray رد می‌شدند، **VPN** شمرده می‌شدند، با تمام شدن سقف VPN کند می‌شدند و با قطع تونل از کار می‌افتادند. حالا از بخش `config ipset` (`dhcp.xguard_bypass`) استفاده می‌شود.
- همچنین پاسخ‌های کش‌شدهٔ DNS دامنه‌های استثنا از لاگ پرسمان اضافه می‌شوند، آدرس‌ها تا وقتی استفاده می‌شوند می‌مانند و با بارگذاری مجدد قواعد پاک نمی‌شوند؛ حذف دامنه مجموعه را خالی می‌کند.
- رفع باگ: بالا بردن سقف کاربرِ محدودشده او را آزاد نمی‌کرد.
- **سقف پیش‌فرض** جدید (`def_wl_mb`، `def_wl_kbps`، `def_vpn_mb`، `def_vpn_kbps`): سهمیهٔ روزانهٔ هر دستگاه برای همهٔ کسانی که سهمیهٔ جدا ندارند و از `default_mode` استثنا نشده‌اند. در حالت `direct` فقط سقف لیست سفید، در حالت `vpn` هر دو.
- رفع باگ: با خالی بودن `dhcp.leases` (بعد از ریستارت) سهمیه‌های مبتنی بر MAC آدرسی پیدا نمی‌کردند؛ حالا جدول ARP هم استفاده می‌شود.

## 1.1.1 — shutdown flush fix / رفع ذخیره‌نشدن آمار هنگام ریستارت

**EN**
- Fix: usage was not written to flash at reboot (only every `acct_save` seconds), so a reboot lost up to 10 minutes of numbers. Cause: the init script stopped at `STOP=99`, which procd runs after `K90umount` (file systems already unmounted). It now stops at `STOP=05` and flushes synchronously; the upgrade removes the stale `K99xguard` link. Verified on a real reboot (flush at shutdown, flash file updated).
- Verified on hardware: xray is fetched automatically after every boot from an `ssh://` mirror (`list source 'ssh://xguard-mirror@HOST/xray.gz'`, forced-command key, `tools/mirror/setup-mirror.sh`) in about 25 s.

**FA**
- رفع باگ: آمار هنگام ریستارت روی فلش نوشته نمی‌شد (فقط هر `acct_save` ثانیه)، پس ریستارت تا ۱۰ دقیقه از اعداد را از بین می‌برد. علت: اسکریپت init با `STOP=99` متوقف می‌شد که procd بعد از `K90umount` (فایل‌سیستم‌ها قبلاً unmount شده‌اند) اجرا می‌کند. حالا با `STOP=05` و ذخیرهٔ همگام متوقف می‌شود؛ ارتقا لینک قدیمی `K99xguard` را پاک می‌کند. روی ریستارت واقعی تأیید شد.
- روی سخت‌افزار تأیید شد: xray بعد از هر بوت خودکار از میرور `ssh://` (کلید با forced-command، `tools/mirror/setup-mirror.sh`) در حدود ۲۵ ثانیه گرفته می‌شود.

## 1.1.0 — usage report and daily quotas / گزارش مصرف و سهمیهٔ روزانه

**EN**
- **Usage report** (web UI tab *Usage*, `xguardctl usage`): per client IP, bytes in two classes — *whitelist* (traffic that does not enter the tunnel) and *VPN* — and per site / app. Sites are named from dnsmasq's query log (RAM only); the web UI groups them into apps.
- **Daily quotas** (`config quota`, tab *Limits and quotas*): every user gets two separate allowances (whitelist and VPN). When one is used up, only that class is slowed down to a speed you choose (or cut off with `0`). Enforced in the kernel with nftables `quota` + `limit` objects. Resets daily at `reset_time` (default 00:00, Tehran time via `tz_offset`), manual reset per user.
- Usage is written to flash (gzip, a few KB per day, every `acct_save` = 600 s and at shutdown) and re-seeded into the ruleset at boot, so a **reboot does not lose the numbers**. A clock that is behind the last saved time never starts a new day (no RTC).
- New `xguardacct` procd instance does the periodic harvest, separate from the supervisor so it can never stall the kill-switch. New `acctlib.uc` / `acct.uc`; the ruleset gains the sets `pair_w/pair_v/cli_w/cli_v`, the chains `acct_fwd/acct_in/acct_out` and a conntrack mark on VPN connections.
- `xguardd` enables dnsmasq's `logqueries` (log in `/tmp/xguard/dns.log`, ≤ 256 KB) while accounting is on and restores your own settings when it is off.
- Tests: `tests/test-acct.sh` (31 checks: parsers, deltas, persistence, rollover, retention, reset); also verified live on a Xiaomi 4A with real traffic in an isolated copy of the ruleset (per-site counting through REDIRECT, whitelist counting, throttle to the configured speed).
- Known: IPv4 only; firewall flow offloading must stay off; accounting runs only while xguard is enabled.

**FA**
- **گزارش مصرف** (تب *مصرف* در صفحهٔ وب، `xguardctl usage`): برای هر IP بایت‌ها در دو دسته — *لیست سفید* (ترافیکی که وارد تونل نمی‌شود) و *VPN* — و به‌تفکیک سایت / برنامه. نام سایت‌ها از لاگ پرسمان dnsmasq (فقط RAM) می‌آید و صفحهٔ وب آن‌ها را در برنامه‌ها گروه می‌کند.
- **سهمیهٔ روزانه** (`config quota`، تب *محدودیت و سهمیه*): هر کاربر دو سقف جدا دارد (لیست سفید و VPN). وقتی یکی تمام شود فقط سرعت همان بخش به عددی که تعیین کرده‌اید کم می‌شود (یا با `0` قطع). اعمال آن در کرنل با اشیای `quota` و `limit` در nftables است. هر روز در `reset_time` ریست می‌شود (پیش‌فرض ۰۰:۰۰ به وقت تهران با `tz_offset`) و ریست دستی برای هر کاربر هست.
- مصرف روی فلش نوشته می‌شود (gzip، چند کیلوبایت در روز، هر `acct_save` = ۶۰۰ ثانیه و هنگام خاموشی) و هنگام بوت دوباره داخل ruleset ریخته می‌شود؛ پس **ریستارت روتر آمار را پاک نمی‌کند**. ساعتی که از آخرین زمان ذخیره عقب‌تر باشد هرگز روز جدید شروع نمی‌کند (RTC نداریم).
- یک instance جدید procd به نام `xguardacct` خواندن دوره‌ای را انجام می‌دهد؛ جدا از ناظر است تا هرگز kill-switch را متوقف نکند. فایل‌های جدید `acctlib.uc` / `acct.uc`؛ ruleset مجموعه‌های `pair_w/pair_v/cli_w/cli_v`، زنجیره‌های `acct_fwd/acct_in/acct_out` و یک mark در conntrack برای اتصال‌های VPN می‌گیرد.
- `xguardd` تا وقتی شمارش روشن است `logqueries` در dnsmasq را روشن می‌کند (لاگ در `/tmp/xguard/dns.log`، حداکثر ۲۵۶ کیلوبایت) و با خاموش شدن، تنظیمات خودتان را برمی‌گرداند.
- تست‌ها: `tests/test-acct.sh` (۳۱ بررسی: پارسرها، دلتا، ماندگاری، تغییر روز، نگه‌داری، ریست)؛ همچنین روی Xiaomi 4A با ترافیک واقعی در یک کپی ایزوله از ruleset سنجیده شد (شمارش هر سایت از مسیر REDIRECT، شمارش لیست سفید، کاهش سرعت تا عدد تعیین‌شده).
- محدودیت‌ها: فقط IPv4؛ flow offloading فایروال باید خاموش بماند؛ شمارش فقط وقتی xguard روشن است کار می‌کند.

## 1.0.1 — UI polish / ظاهر جدید

**EN**
- Refreshed web UI (CSS only, +3.6 KB): teal palette for light/dark, pill-style tabs, status dot (pulses when connected), toggle switch for enable, stat tiles on the Status tab, clearer focus and hover states, softer cards.

**FA**
- ظاهر جدید رابط وب (فقط CSS، حدود ۳٫۶ کیلوبایت بیشتر): پالت تیل برای حالت روشن و تیره، تب‌های قرصی، نقطهٔ وضعیت (هنگام اتصال پالس می‌زند)، کلید فعال‌سازی، کاشی‌های آمار در تب وضعیت، فوکوس و hover واضح‌تر و کارت‌های نرم‌تر.

## 1.0.0 — stable / پایدار

First stable release (the 0.1.0-rc* entries below were the pre-releases). / اولین انتشار پایدار (موارد 0.1.0-rc* پایین‌تر پیش‌انتشار بودند).

**EN**
- `dnsmasq-full` is now a mandatory dependency of the ipk and part of the image (needed for `nftset`).
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
- `dnsmasq-full` حالا وابستگی اجباری ipk و بخشی از ایمیج است (برای `nftset` لازم است).
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
