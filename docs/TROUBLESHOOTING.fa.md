# عیب‌یابی

🇮🇷 فارسی · 🇬🇧 [English](TROUBLESHOOTING.md) · [← README](../README.fa.md)

از اینجا شروع کنید:

```sh
xguardctl status      # ناظر چه وضعیتی را می‌بیند
xguardctl logs        # لاگ xguardd / xray / ssh
logread | grep -E 'xguard|xray'
```

## اضطراری: اینترنت ساده را برگردانید

```sh
xguardctl disable            # kill-switch و تنظیم DNS تا حدود ۵ ثانیه حذف می‌شوند
/usr/sbin/xguardd unguard    # همان، فوری، حتی اگر ناظر مرده باشد
nft delete table inet xguard # فقط بخش فایروال
```
اگر بعد از آن DNS هنوز خراب بود، `xguardd unguard` upstreamهای اصلی dnsmasq را از `/etc/xguard/dnsmasq.orig` برمی‌گرداند.

## مقدارهای status

| `status` | معنی / کار لازم |
|---|---|
| `need-xray` | xray در RAM نیست و `source` هم نیست ← [push کنید](INSTALL.fa.md) یا منبع بدهید. |
| `fetching-xray` | در حال دانلود. اگر تمام نمی‌شود: `xguardctl logs`، آدرس، وجود `xray.gz.sha256` کنار فایل، ساعت روتر و `bootstrap_dns` را ببینید. |
| `no-node` | فعال است ولی نود فعالی نیست ← در صفحهٔ وب اضافه کنید. kill-switch از قبل فعال است. |
| `starting` / `restarting` | برای چند ثانیه عادی است. |
| `degraded` | xray اجراست ولی تونل ترافیک نمی‌گذراند. دستگاه‌های VPN **اینترنت ندارند** (طراحی‌شده). تا بی‌نهایت تلاش می‌کند و با چند نود، بعد از `fail_threshold × probe_interval` ثانیه به نود بعدی می‌رود. نود، سرور، `probe_url` و ساعت را بررسی کنید. |
| `updating` | فایل `/tmp/xguard/hold` وجود دارد یا `push-xray` در حال اجراست. |
| `error` | kill-switch اعمال نشد — `xguardctl logs` را ببینید (`nft.err` و `gen.err` در `/tmp/xguard/`). |
| `disabled` | `enabled` برابر `0` است. |

## مشکلات رایج

**دستگاه‌های روی اینترفیس VPN اینترنت ندارند ولی `status=running`.**
DNS کلاینت را بررسی کنید (باید خود روتر باشد)، روی روتر `nslookup example.com <router>` بزنید، و ببینید نام اینترفیس در *شبکه* با دستگاه واقعی یکی است (`ls /sys/class/net`). نام Wi‑Fiها `phy0-ap0` و `phy1-ap0` است (نه `wlan0`). کلاینتی که اینترفیسش `block` است هیچ‌وقت اینترنت ندارد.

**دستگاه‌های اینترفیس `direct` هم DNS را از دست دادند.**
طبق طراحی همهٔ کلاینت‌ها از تونل resolve می‌کنند. وقتی xray قطع است DNS هم قطع است. اگر DNS ساده می‌خواهید `xguardctl disable` بزنید.

**HTTPS روی روتر خطا می‌دهد / «certificate is not yet valid»، یا تونل بلافاصله بعد از بوت `degraded` است.**
روتر ساعت باتری‌دار ندارد. xguard قبل از دانلود xray و بعد هر ساعت، ساعت را از هدر `Date:` در HTTP ساده (پورت ۸۰) میزبان‌های `time_hosts` (پیش‌فرض `1.1.1.1`) درست می‌کند. اگر پورت ۸۰ به آن‌ها بسته است `time_hosts` را عوض کنید، یا دستی `date -u -s "YYYY-MM-DD HH:MM:SS"` بزنید.

**xray مدام کشته می‌شود («RSS … above … restarting»).**
بار را کم کنید یا `rss_kill`/`mem_limit` را بالا ببرید (پیش‌فرض ۴۶/۲۸ مگابایت برای روتر ۱۲۸ مگابایتی مناسب است). `free -m` و فعال بودن zram (`cat /proc/swaps`) را ببینید. اتصال‌های هم‌زمان کمتر، بدون sniffing و `log_level warning` کمک می‌کند.

**کند است.**
MT7621 شتاب AES ندارد. نودهای بدون رمزگذاری دوبل را ترجیح دهید؛ Reality/Vision یا رمزهای مبتنی بر chacha20 در نرم‌افزار ارزان‌تر از AES-GCM هستند. `top` نشان می‌دهد xray CPU را پر کرده یا نه. محدودیت‌های سرعت (policer) هم عمداً سرعت را سقف می‌زنند.

**QUIC / برنامه‌های UDP کار نمی‌کنند.**
`block_quic=1` عمداً UDP/443 را دور می‌ریزد. نودهای SSH اصلاً UDP حمل نمی‌کنند. نودهای VLESS/VMess/Trojan/SS می‌توانند (مگر سرور اجازه ندهد).

**IPv6.**
پشتیبانی نمی‌شود: IPv6 دستگاه‌های VPN/مسدود توسط kill-switch دور ریخته می‌شود.

**صفحهٔ وب «access denied» می‌دهد / وارد نمی‌شود.**
با رمز root وارد شوید (اگر رمزی نگذاشته‌اید خالی — لطفاً بگذارید). rpcd باید اجرا باشد: `/etc/init.d/rpcd restart`. SSH همیشه جایگزین است.

**بعد از `/etc/init.d/firewall reload` قوانین xguard ناپدید شدند.**
نباید بشوند: در جدول جدا `inet xguard` هستند که fw4 به آن دست نمی‌زند. با `nft list table inet xguard` بررسی کنید؛ `xguardctl restart` دوباره اعمالشان می‌کند.

**دستگاه‌های Wi‑Fi ریدایرکت نمی‌شوند با اینکه اینترفیس `vpn` است.**
لیست استثنای دستگاه‌ها (دستگاه `direct` روی آن اینترفیس از VPN رد نمی‌شود) و لیست bypass را بررسی کنید.

**نود `ssh` وصل نمی‌شود.**
`xguardctl logs` خروجی خطای `ssh` را نشان می‌دهد. با رمز، نود از `sshpass` استفاده می‌کند؛ وگرنه کلید `/etc/xguard/id_ed25519` (با `xguardctl genkey` بسازید و کلید عمومی چاپ‌شده را به `authorized_keys` سرور اضافه کنید). کلید میزبان در اولین اتصال پذیرفته و در `/etc/xguard/known_hosts` ذخیره می‌شود (اگر سرور دوباره نصب شد خطش را پاک کنید). رمزهایی که `|` دارند پشتیبانی نمی‌شوند.

## خودتان kill-switch را آزمایش کنید

```sh
touch /tmp/xguard/hold; killall xray     # حالا دستگاه VPN باید کاملاً بدون اینترنت باشد
rm /tmp/xguard/hold                      # xray برمی‌گردد و اینترنت هم
```

## گزارش باگ

لطفاً این‌ها را بگذارید: مدل روتر، نسخهٔ OpenWrt/xguard (`cat /etc/xguard.version`)، `xguardctl status`، `xguardctl logs`، `nft list table inet xguard`، `free -m`. **لینک نودها، رمزها و UUIDها را** از متنی که می‌گذارید حذف کنید.
