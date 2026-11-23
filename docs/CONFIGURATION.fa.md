# مرجع پیکربندی

🇮🇷 فارسی · 🇬🇧 [English](CONFIGURATION.md) · [← README](../README.fa.md)

همه‌چیز در `/etc/config/xguard` (UCI) است و با صفحهٔ وب یا دستی ویرایش می‌شود:

```sh
uci set xguard.main.enabled=1 ; uci commit xguard      # ناظر تا حدود ۵ ثانیه متوجه می‌شود
```
ناظر (`xguardd`) این فایل (و `/tmp/dhcp.leases`) را زیر نظر دارد و با هر تغییر، قوانین فایروال را دوباره اعمال یا xray را ری‌استارت می‌کند.

## `config main 'main'`

| گزینه | پیش‌فرض | معنی |
|---|---|---|
| `enabled` | `0` | `1` kill-switch، تنظیم DNS و xray را فعال می‌کند. با `0` چیزی مسدود یا پروکسی نمی‌شود. |
| `node` | *(خالی)* | نود ترجیحی (نام section). failover بقیهٔ نودهای فعال را به ترتیب فایل می‌رود. |
| `source` (لیست) | – | جایی که روتر بعد از هر بوت `xray.gz` را می‌گیرد (`https://…/xray.gz`، `ssh://user@host[:port]/path/xray.gz`). `xray.gz.sha256` = sha256 باینری **باز‌شده**، با همان آدرس + `.sha256`. |
| `bootstrap_dns` | `1.1.1.1 8.8.8.8` | سرورهای DNS ساده که **مستقیم** (نه از تونل) و فقط برای resolve کردن نام میزبانِ `source`ها زمانی که xray هنوز اجرا نیست استفاده می‌شوند. اگر در شبکهٔ شما بسته‌اند عوضشان کنید. |
| `wan_if` (لیست) | `wan` | اینترفیس(های) رو به اینترنت؛ ترافیک فورواردشدهٔ اینترفیس‌های `vpn`/`block` به سمت آن‌ها دور ریخته می‌شود. |
| `default_mode` | `direct` | سیاست سراسری برای **همهٔ** دستگاه‌ها، حتی آن‌هایی که در جایی تعریف نشده‌اند: `direct` = هیچ‌کس از VPN نمی‌گذرد مگر اینترفیس/دستگاهی را `vpn` کنید؛ `vpn` = همه (هر چه از `wan_if` نیاید) از VPN می‌گذرد و با قطع تونل اینترنت ندارد، مگر اینترفیس/دستگاهی را `direct` کنید. اینترفیس‌های `block` همیشه قطع‌اند. دسترسی به خود روتر (صفحهٔ وب، SSH، DNS، DHCP) هرگز تحت‌تأثیر نیست. |
| `dns_remote` | `tcp://1.1.1.1` | DNS که **از داخل تونل** استفاده می‌شود (برای نود SSH باید `tcp://` باشد). |
| `dns_bypass` | *(خالی = DNS بالادست WAN، وگرنه `bootstrap_dns`)* | سرور DNS اختیاری (مثلاً `178.22.122.100`) که **مستقیم و بیرون از تونل** و فقط برای دامنه‌های لیست `bypass` استفاده می‌شود (geo-DNS: سایت‌های داخلی به IP داخلی resolve شوند). خالی = این دامنه‌ها هم مثل بقیه از تونل resolve می‌شوند. |
| `probe_url` | `https://www.gstatic.com/generate_204` | آدرسی که observatory در xray از داخل تونل می‌گیرد تا «زنده بودن» را تشخیص دهد. |
| `probe_interval` | `10` | فاصلهٔ تست‌ها (ثانیه). |
| `fail_threshold` | `3` | تعداد تست مردهٔ پشت‌سرهم تا تعویض نود (`fail_threshold × probe_interval` ثانیه). |
| `mem_limit` | `28` | `GOMEMLIMIT` برای xray، به MiB (سقف نرم؛ GC نزدیک آن شدیدتر کار می‌کند). |
| `rss_kill` | `46` | اگر RSS پروسهٔ xray از این مقدار (MiB) بیشتر شود ری‌استارت می‌شود؛ kill-switch در این مدت فعال می‌ماند. |
| `log_level` | `warning` | سطح لاگ xray (`debug`، `info`، `warning`، `error`، `none`)؛ لاگ یک فایل چرخشی کوچک در RAM است. |
| `sniffing` | `0` | sniffing در xray. وقتی لیست `bypass` دامنه دارد **خودکار** روشن می‌شود؛ با `1` اجباری روشن می‌ماند. کمی CPU/RAM بیشتر. |
| `block_quic` | `1` | UDP/443 را دور می‌ریزد تا مرورگر به TCP برگردد (برای نود SSH همیشه فعال). |
| `time_hosts` | `1.1.1.1 neverssl.com` | میزبان‌هایی که با HTTP ساده (پورت ۸۰) هدر `Date:` از آن‌ها خوانده می‌شود تا ساعت روتر درست شود (RTC ندارد؛ NTP ممکن است بسته باشد). |
| `redir_port`، `tproxy_port`، `dns_port`، `socks_port`، `ssh_socks_port`، `metrics_port` | `12345`، `12346`، `15353`، `10808`، `10809`، `11111` | پورت‌های محلی inboundهای xray / SOCKS کمکی SSH / endpoint متریک. فقط هنگام تداخل تغییر دهید. |

## `config node '<id>'`

| گزینه | معنی |
|---|---|
| `name` | برچسب در صفحهٔ وب. |
| `enabled` | `0` نود را از failover حذف می‌کند. |
| `type` | `link` (لینک اشتراک)، `json` (outbound خام xray)، `ssh` (تونل SSH). |
| `link` | `vless://`، `vmess://` (JSON base64)، `trojan://`، `ss://` (SIP002 / قدیمی / ساده)، `socks://`. |
| `json` | یک آبجکت outbound در xray، **یا آرایه = زنجیره**: عنصر ۰ خروجی نهایی است و هر عنصر بعدی upstream قبلی (`dialerProxy` خودکار تنظیم می‌شود). tagها را خود xguard می‌دهد. |
| `host`، `port`، `user` | سرور SSH (نوع `ssh`). |
| `password` | رمز SSH (با `sshpass`). خالی ← احراز هویت با کلید. |
| `keyfile` | مسیر کلید خصوصی، پیش‌فرض `/etc/xguard/id_ed25519` (`xguardctl genkey`). |

پارامترهای لینک که فهمیده می‌شوند: `type` (tcp/raw، ws، grpc، httpupgrade، xhttp/splithttp، kcp)، `security` (none/tls/reality)، `sni`، `host`، `path`، `serviceName`، `mode`، `alpn`، `fp`، `flow`، `encryption`، `pbk`، `sid`، `spx`، `headerType`، `seed`، `allowInsecure`، `extra` (xhttp). برای هر چیز دیگر از نود `json` استفاده کنید.

نمونه‌ها:
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
	option name 'phy0-ap0'     # نام دستگاه در کرنل: ls /sys/class/net
	option mode 'vpn'          # vpn | direct | block
```
- `vpn`: TCP ← xray (REDIRECT)، UDP ← xray (TPROXY)؛ هر چیزی که قرار بود به WAN فوروارد شود دور ریخته می‌شود.
- `direct`: دست‌نخورده (ولی DNS آن هم از تونل می‌گذرد).
- `block`: هیچ‌چیز نباید به WAN برسد.
- اینترفیس‌های ذکرنشده دست‌نخورده‌اند. ترافیک به شبکه‌های خصوصی (10/8، 172.16/12، 192.168/16، 169.254/16، 224/4، …) و به خود روتر هرگز از VPN فرستاده نمی‌شود.

## ویرایش نود (fragment، fingerprint، MTU و …)

در صفحهٔ وب (*نودها ← ویرایش*) هر نود به‌صورت **فرم** باز می‌شود و هر بخش کادر جدا دارد: *اتصال* (آدرس، پورت، UUID/رمز، flow، encryption)، *انتقال* (TCP، WebSocket، gRPC، HTTPUpgrade، XHTTP، mKCP با path/host/serviceName/mode/header/seed/**MTU**/TTI)، *امنیت* (none، TLS، REALITY با SNI، **fingerprint**، ALPN، public key، short ID، SpiderX، allowInsecure) و *پیشرفته* (**Fragment**، Mux، TCP Fast Open). گزینه‌ها لیست کشویی با مقدارهای معتبرند. ذخیره، نود را به‌صورت outbound معادل xray نگه می‌دارد (لینک اصلی نگه داشته نمی‌شود). پروتکل‌های بدون فرم (مثل WireGuard) به‌صورت JSON خام ویرایش می‌شوند. آرایهٔ JSON یک زنجیره است: عضو اول خروجی نهایی و بقیه hopهای dialer؛ گزینهٔ Fragment خودکار چنین hopی (یک outbound از نوع `freedom`) اضافه می‌کند.

## `config device` — استثنا برای هر دستگاه

```
config device
	option mac 'aa:bb:cc:dd:ee:ff'     # یا: option ip '192.168.5.50'
	option mode 'direct'               # direct | vpn
```
`direct` حتی روی اینترفیس `vpn` از VPN رد نمی‌شود؛ `vpn` روی اینترفیس `direct` VPN را اجبار می‌کند.

## `config bypass`

```
config bypass
	list cidr '203.0.113.0/24'
	list cidr '8.8.8.8'
	list cidr 'example.ir'              # دامنه + همهٔ زیردامنه‌ها
	list cidr '*.ir'                    # همهٔ سایت‌های با پسوند ir
	list cidr 'full:www.bank.example'   # دقیقاً همین میزبان
	list cidr 'keyword:shaparak'        # هر میزبانی که این کلمه را دارد
```
مقصدهایی که دستگاه‌های روی اینترفیس `vpn` می‌توانند **مستقیم** و خارج از تونل به آن‌ها بروند. اینترفیس‌های حالت `block` تأثیر نمی‌گیرند. دو نوع ورودی دارد (نام گزینه به دلایل تاریخی `cidr` است):

| ورودی | کار چه کسی | رفتار |
|---|---|---|
| IPv4 یا CIDR (`203.0.113.0/24`) | nftables | هرگز به xray نمی‌رسد و از kill-switch معاف است؛ پس **حتی وقتی xray/تونل قطع است** هم باز می‌ماند. فقط IPv4. |
| دامنه (`example.ir`، `*.ir`، `domain:example.ir`، `full:www.example.ir`، `keyword:bank`) | قانون مسیریابی xray ← `direct` | با نامی که xray از TLS SNI / هدر Host / QUIC تشخیص می‌دهد تطبیق داده می‌شود (sniffing خودکار روشن می‌شود). `example.ir` ساده یعنی دامنه **و زیردامنه‌هایش**؛ `*.ir` (یا `.ir`) یعنی **همهٔ سایت‌های زیر آن پسوند** (یک TLD کامل مثل `*.ir` یا `*.co.uk`). فقط `*.` در ابتدا wildcard است: `a*.ir`، `*` و `ir` ساده رد می‌شوند. ترافیک هنوز از xray می‌گذرد، پس وقتی xray خاموش است این دامنه‌ها هم **مثل بقیه قطع می‌شوند** (kill-switch برقرار می‌ماند). |

- `geosite:` / `geoip:` **پشتیبانی نمی‌شود** (فایل‌های `.dat` همراه نیستند و xray بالا نمی‌آید)، و کلمهٔ ساده‌ای مثل `localhost` هم نه. ورودی نامعتبر را صفحهٔ وب رد می‌کند؛ در کانفیگ دستی نادیده گرفته و در `xguardctl logs` با عنوان `config warning` ثبت می‌شود.
- قانون دامنه ترافیکی را که نام ندارد نمی‌بیند (IP خالی، SNI رمزشده/ECH)؛ چنین ترافیکی از VPN می‌رود.
- برای resolve کردن این دامنه‌ها هم بیرون از تونل، `dns_bypass` را تنظیم کنید (بالا).
- **کار کردن حتی با xray خاموش:** ورودی‌های `domain:`/`full:` به dnsmasq هم به‌صورت upstream مستقیم داده می‌شوند (`server=/domain/ip`، با dnsmasq معمولی کار می‌کند) و **اگر dnsmasq با nftset ساخته شده باشد (بستهٔ `dnsmasq-full`)**، IPهای resolve‌شدهٔ آن‌ها در مجموعهٔ nft به نام `bypass_dyn` می‌روند که kill-switch و redirect آن را رد می‌کنند، دقیقاً مثل ورودی IP. با dnsmasq معمولی (`dnsmasq --version` عبارت `no-nftset` را نشان می‌دهد) دامنه‌ها تا وقتی xray روشن است کار می‌کنند، که حالا نود مرده را هم شامل می‌شود (برای یک نود، xray دیگر ری‌استارت نمی‌شود). ورودی `keyword:` فقط با قانون xray کار می‌کند.
- کم استفاده کنید: هر ورودی عمداً در VPN (نه در kill-switch) سوراخ ایجاد می‌کند.

## `config limit`

```
config limit
	option name 'kid'
	option ip '192.168.5.60'       # یا: option mac '…' / option iface 'phy1-ap0'
	option down '4000'             # kbit/s، ۰ یا خالی = نامحدود
	option up '1000'
```
با **policer** نرخ بایتی در nftables پیاده شده: بسته‌های اضافه دور ریخته می‌شوند و TCP کند می‌شود. محدودیت `mac` برای آپلود با MAC و برای دانلود با IPهای موجود در `/tmp/dhcp.leases` اعمال می‌شود.

## گزارش مصرف و سهمیهٔ روزانه (`config quota`)

xguard ترافیک **هر IP کلاینت** را در دو دسته می‌شمارد و می‌تواند برای کاربران انتخابی **سهمیهٔ روزانهٔ جداگانه برای هر دسته** بگذارد. وقتی کاربری یک دسته را تمام کند، فقط سرعت همان دسته تا پایان روز کم (یا قطع) می‌شود.

| دسته | چیست | کجا شمرده می‌شود |
|---|---|---|
| **لیست سفید** (`wl`) | هر چیزی که **وارد تونل نمی‌شود**: مقصدهایی که با IP/CIDR یا دامنه استثنا کرده‌اید (آدرس دامنه‌های استثنا در `bypass_dyn` می‌رود) و کلاینت/اینترفیس‌هایی که روی `direct` هستند. | hook مربوط به forward، بین کلاینت LAN و `wan_if` |
| **وی‌پی‌ان** (`vpn`) | اتصال‌هایی که xguard به xray هدایت کرده (با `ct mark 0x58……` علامت می‌خورند). | input (کلاینت ← xray) و output (xray ← کلاینت) |

دامنه‌ای که **فقط** با قانون xray استثنا شده (`keyword:…` یا نامی که هرگز از dnsmasq روتر resolve نشده) هنوز وارد xray می‌شود و جزو `vpn` شمرده می‌شود.

```
config quota
	option name 'ali'
	option ip '192.168.5.60'      # یا: option mac 'aa:bb:cc:dd:ee:ff' (همهٔ IPهای DHCP آن)
	option wl_mb '2048'           # سهمیهٔ روزانهٔ لیست سفید به MiB؛ ۰ یا خالی = نامحدود (فقط شمارش)
	option wl_kbps '128'          # سرعت لیست سفید (kbit/s، هر دو جهت) پس از تمام شدن سهمیه؛ ۰ = قطع
	option vpn_mb '512'           # سهمیهٔ روزانهٔ VPN به MiB
	option vpn_kbps '64'          # سرعت VPN پس از تمام شدن سهمیه؛ ۰ = قطع
```

- اعمال سهمیه **داخل کرنل** است (اشیای `quota` و `limit` در nftables)؛ پس کاهش سرعت دقیقاً از همان بایت شروع می‌شود، نه در نظرسنجی بعدی.
- **ریست**: هر روز در `reset_time` (ساعت محلی روتر = UTC + `tz_offset` دقیقه؛ پیش‌فرض `00:00` و `210` = تهران). روزِ تمام‌شده به‌عنوان گزارش می‌ماند. `xguardctl usage-reset [ip:1.2.3.4|mac:aa:…]` یا دکمهٔ **ریست** مصرف یک کاربر را هر زمان صفر می‌کند.
- **ریستارت روتر آمار را پاک نمی‌کند**: مصرف هر `acct_save` ثانیه (پیش‌فرض ۶۰۰) و هنگام خاموشی روی فلش نوشته می‌شود (`/etc/xguard/acct/day-YYYYMMDD.json.gz`، چند کیلوبایت در روز) و هنگام بوت دوباره داخل ruleset ریخته می‌شود. قطع ناگهانی برق حداکثر `acct_save` ثانیهٔ آخر را از بین می‌برد. روتر RTC ندارد: ساعتی که از آخرین زمان ذخیره عقب‌تر باشد هرگز روز جدید شروع نمی‌کند.
- کاربر محدودشده کار می‌کند (کند)؛ چیزی قطع نمی‌شود مگر سرعت را `0` بگذارید.

**گزارش** (صفحهٔ وب ← *مصرف*، یا `xguardctl usage [YYYYMMDD]` به‌صورت JSON): برای هر IP، بایت‌های هر دو دسته و ریز مصرف هر **سایت / برنامه**. نام سایت‌ها از لاگ پرسمان dnsmasq می‌آید (فقط در RAM، `/tmp/xguard/dns.log`، حداکثر حدود ۲۵۶ کیلوبایت): نامی که کلاینت *پرسیده* استفاده می‌شود، پس `www.instagram.com` پشت نام CDN پنهان نمی‌شود. صفحهٔ وب سایت‌ها را با یک فهرست داخلی در برنامه‌ها (یوتیوب، اینستاگرام، تلگرام، …) گروه می‌کند. بازهٔ آدرس‌های تلگرام بدون DNS شناخته می‌شود. ترافیکی که نامش قابل‌دانستن نیست (DoH/DoT، IP ثابت) با IP نشان داده می‌شود.

گزینه‌های `config main`:

| گزینه | پیش‌فرض | معنی |
|---|---|---|
| `accounting` | `1` | شمارش، گزارش و سهمیه. با `0` قواعد شمارش برداشته و تنظیمات لاگ خود dnsmasq برگردانده می‌شود. |
| `reset_time` | `00:00` | شروع «روز» برای شمارش (ساعت محلی روتر). |
| `tz_offset` | `210` | اختلاف دقیقه‌ای ساعت محلی با UTC (تهران = ۲۱۰؛ خود روتر ممکن است روی UTC باشد). |
| `acct_days` | `7` | تعداد گزارش‌های روزانهٔ نگه‌داری‌شده روی فلش. |
| `acct_save` | `600` | فاصلهٔ ثانیه‌ای نوشتن روی فلش (فرسایش فلش: یک نوشتن کوچک در هر فاصله). |
| `acct_interval` | `30` | فاصلهٔ ثانیه‌ای خواندن شمارنده‌های کرنل. |

محدودیت‌ها و نکته‌ها:
- فقط IPv4. *flow offloading* فایروال باید خاموش باشد (پیش‌فرض OpenWrt)؛ جریان‌های offload‌شده از nftables رد می‌شوند و شمرده نمی‌شوند.
- هر دسته تا ۴۰۹۶ جفت (کلاینت، IP مقصد) را ۵ دقیقه در کرنل نگه می‌دارد؛ اگر کلاینتی بیش از آن باز کند (مثلاً BitTorrent) بایت‌های اضافه در مجموع کلاینت هست ولی «بدون تفکیک» نشان داده می‌شود.
- دقت نمای هر سایت به اندازهٔ DNS است: چند سایت روی یک آدرس CDN به آخرین نامِ resolve‌شده نسبت داده می‌شود.
- گزارش هر کلاینتی را که از روتر ترافیک فرستاده نشان می‌دهد و فایل‌های روزانهٔ ذخیره‌شده سایت‌های بازدیدشدهٔ افراد را دارند. با **پاک کردن گزارش‌ها** / `xguardctl usage-clear` پاک می‌شوند.
- شمارش فقط وقتی xguard روشن است کار می‌کند (شمارنده‌ها در جدول nftables خودش هستند).

## CLI: `xguardctl`

| دستور | |
|---|---|
| `status` | وضعیت ناظر (`status`، `node`، `alive`، `delay`، `rss_kb`، `avail_kb`، `restarts`، `xray_version`، …) |
| `logs` | آخرین خطوط لاگ `xguardd`، xray و ssh |
| `restart` / `next` | ری‌استارت xray / رفتن به نود بعدی |
| `update-xray` | xray داخل RAM را دور بریز و دوباره از `source` بگیر |
| `push-xray [sha256]` | `xray.gz` را از stdin داخل RAM بخوان ([INSTALL.fa.md](INSTALL.fa.md)) |
| `enable` / `disable` | تنظیم `main.enabled` |
| `usage [YYYYMMDD]` | گزارش به‌صورت JSON: برای هر IP بایت‌های هر دو دسته و ریز هر سایت؛ کاربران دارای سهمیه |
| `usage-reset [key]` | مصرف روزانهٔ یک کاربر (`ip:1.2.3.4`، `mac:aa:…`) یا همه را صفر می‌کند |
| `usage-clear` | گزارش‌های ذخیره‌شده را پاک می‌کند |
| `genkey` | ساخت `/etc/xguard/id_ed25519` و چاپ کلید عمومی |
| `test-config <node>` | اجرای `xray run -test` روی کانفیگ تولیدی |

مقدارهای status: `running`، `degraded` (تونل قطع، kill-switch فعال)، `starting`، `restarting`، `fetching-xray`، `need-xray`، `updating`، `no-node`، `disabled`، `error`.
