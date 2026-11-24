#!/bin/sh
# Accounting test: runs the REAL acctlib.uc / acct.uc / core.uc generators in a sandbox under /tmp/xgacct with a stub
# nft (canned `nft list` output), a canned dnsmasq query log and a fake clock. Touches nothing outside /tmp/xgacct.
#
#   tar cf - -C xguard/files/usr/lib/xguard . | ssh root@router 'rm -rf /tmp/xgacct && mkdir -p /tmp/xgacct/lib && tar xf - -C /tmp/xgacct/lib'
#   ssh root@router 'sh -s' < xguard/tests/test-acct.sh
#
# Needs ucode (+ ucode-mod-fs, ucode-mod-uci), zcat/gzip (busybox) on the box.

SIM=/tmp/xgacct
RUN=$SIM/run
ETC=$SIM/etc
D=$SIM/canned
pass=0; fail=0
ok()  { echo "PASS  $*"; pass=$((pass+1)); }
bad() { echo "FAIL  $*"; fail=$((fail+1)); }
eq()  { # eq "desc" expected actual
	if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi
}

rm -rf $RUN $ETC $SIM/conf $SIM/bin $D $SIM/nft.calls $SIM/last-load.nft
mkdir -p $RUN $ETC $SIM/conf $SIM/bin $D

export XGUARD_RUN=$RUN XGUARD_ETC=$ETC XGUARD_CONFDIR=$SIM/conf XGUARD_NFT=$SIM/bin/nft XGUARD_DNSLOG=$RUN/dns.log
A="ucode $SIM/lib/acct.uc"
export XGUARD_ADDRS=$SIM/addrs XGUARD_NEIGH=$SIM/neigh XGUARD_LEASES=$SIM/leases
cat > $SIM/addrs <<'EOF'
1: lo    inet 127.0.0.1/8 scope host lo
2: wan    inet 192.168.1.69/24 brd 192.168.1.255 scope global wan
5: phy0-ap0    inet 192.168.5.1/24 brd 192.168.5.255 scope global phy0-ap0
6: phy1-ap0    inet 192.168.4.1/24 scope global phy1-ap0
EOF
: > $SIM/neigh
: > $SIM/leases

cat > $SIM/conf/xguard <<'EOF'
config main 'main'
	option enabled '1'
	list wan_if 'wan'
	option acct_days '2'
config quota
	option name 'kid'
	option ip '192.168.5.60'
	option wl_mb '500'
	option wl_kbps '128'
	option vpn_mb '100'
	option vpn_kbps '0'
EOF

# ---- stub nft ---------------------------------------------------------------
cat > $SIM/bin/nft <<'EOF'
#!/bin/sh
D=/tmp/xgacct/canned
case "$*" in
	"list set inet xguard cli_w") cat $D/cli_w;;
	"list set inet xguard cli_v") cat $D/cli_v;;
	"list set inet xguard pair_w") cat $D/pair_w;;
	"list set inet xguard pair_v") cat $D/pair_v;;
	"list counters table inet xguard") cat $D/counters;;
	"list quotas table inet xguard") cat $D/quotas;;
	-f*) echo "$*" >> /tmp/xgacct/nft.calls; cp "$2" /tmp/xgacct/last-load.nft;;
	"list set inet xguard bypass_dyn") cat $D/bypass_dyn 2>/dev/null;;
	"add element"*) echo "$*" >> /tmp/xgacct/nft.calls;;
	*) exit 1;;
esac
EOF
chmod +x $SIM/bin/nft

# canned nft output in the real format
setfile() { # setfile <name> <elements-text...> (set listing) ; $1 = file, $2 = set name, $3 = type, $4 = elements
	cat > $D/$1 <<EOF
table inet xguard {
	set $2 {
		type $3
		size 4096
		flags dynamic,timeout
		counter
		timeout 5m
		elements = { $4 }
	}
}
EOF
}
mkstate() { # mkstate <cw-bytes> <cv-bytes> <qw-used "N unit"> <qv-used "N unit">
	cat > $D/counters <<EOF
table inet xguard {
	counter cw1 {
		packets 12 bytes $1
	}
	counter cv1 {
		packets 9 bytes $2
	}
}
EOF
	cat > $D/quotas <<EOF
table inet xguard {
	quota qw1 {
		over 500 mbytes used $3
	}
	quota qv1 {
		over 100 mbytes used $4
	}
}
EOF
}

# a tiny query log in dnsmasq's --log-queries=extra format (CNAME chain + cache hit + noise)
cat > $RUN/dns.log <<'EOF'
Nov 23 21:30:01 dnsmasq[1234]: started, version 2.93 cachesize 1000
Nov 23 21:30:02 dnsmasq[1234]: 1 192.168.5.60/50321 query[A] www.instagram.com from 192.168.5.60
Nov 23 21:30:02 dnsmasq[1234]: 1 192.168.5.60/50321 forwarded www.instagram.com to 127.0.0.1
Nov 23 21:30:02 dnsmasq[1234]: 1 192.168.5.60/50321 reply www.instagram.com is <CNAME>
Nov 23 21:30:02 dnsmasq[1234]: 1 192.168.5.60/50321 reply z-p42-instagram.c10r.facebook.com is 1.2.3.4
Nov 23 21:30:03 dnsmasq[1234]: 2 192.168.5.60/50322 query[AAAA] www.instagram.com from 192.168.5.60
Nov 23 21:30:03 dnsmasq[1234]: 2 192.168.5.60/50322 reply z-p42-instagram.c10r.facebook.com is 2a03:2880::1
Nov 23 21:30:04 dnsmasq[1234]: 3 192.168.5.61/40000 query[A] static.digikala.com from 192.168.5.61
Nov 23 21:30:04 dnsmasq[1234]: 3 192.168.5.61/40000 cached static.digikala.com is 5.6.7.8
Nov 23 21:30:05 dnsmasq[1234]: 4 192.168.5.61/40001 query[A] shop.example.co.uk from 192.168.5.61
Nov 23 21:30:05 dnsmasq[1234]: 4 192.168.5.61/40001 reply shop.example.co.uk is 9.9.9.9
Nov 23 21:30:06 dnsmasq[1234]: 5 192.168.5.61/40002 query[PTR] 4.3.2.1.in-addr.arpa from 192.168.5.61
Nov 23 21:30:06 dnsmasq[1234]: 5 192.168.5.61/40002 reply 4.3.2.1.in-addr.arpa is NXDOMAIN
EOF

t0=1795468595				# Mon 2026-11-23 21:16:35 UTC  = 2026-11-24 00:46 Tehran (UTC+3:30)

# ---- 1. pure parsers / helpers -------------------------------------------------------
cat > $SIM/t1.uc <<'EOF'
import { parse_pairs, parse_clients, parse_counters, parse_quotas, site_of_name, ip_site, day_of, next_reset, day_params } from './lib/acctlib.uc';
let r = [];
push(r, site_of_name('www.instagram.com'), site_of_name('a.b.example.co.uk'), site_of_name('digikala.com'), site_of_name('x.sch.ir'), site_of_name('cdn.divar.ir'));
push(r, ip_site('149.154.167.91'), ip_site('8.8.8.8'));
let pq = parse_pairs('elements = { 10.0.0.1 . 1.2.3.4 counter packets 3 bytes 120 timeout 5m expires 4m,\n 10.0.0.1 . 5.6.7.8 counter packets 1 bytes 60 timeout 5m expires 1m }');
push(r, length(pq), pq[1][1], pq[1][2]);
push(r, parse_clients('elements = { 10.0.0.1 counter packets 3 bytes 4096 expires 1h }')[0][1]);
push(r, parse_counters('counter cw1 {\n packets 1 bytes 777\n }\n counter cv2 {\n packets 2 bytes 5 }')['cw1']);
let q = parse_quotas('quota qw1 {\n over 500 mbytes used 12 mbytes\n }\n quota qv1 {\n over 1 mbytes used 300 bytes }');
push(r, q.qw1.over, q.qw1.used, q.qv1.over, q.qv1.used);
let p = day_params({});
push(r, day_of(1795468595, p), day_of(1795468595 - 3000, p));
let p2 = day_params({ tz_offset: '0', reset_time: '03:00' });
push(r, day_of(1795468595, p2), day_of(1795468595 - 70000, p2));
push(r, next_reset(1795468595, p) - 1795468595);
print(join(',', r), '\n');
EOF
out=$(cd $SIM && ucode $SIM/t1.uc 2>&1)
eq "parsers, site names, day boundaries" \
	"instagram.com,example.co.uk,digikala.com,x.sch.ir,divar.ir,telegram.org,8.8.8.8,2,5.6.7.8,60,4096,777,524288000,12582912,1048576,300,20261124,20261123,20261123,20261122,83605" "$out"   # 83605 s = 00:46:35 local -> next midnight

# ---- 2. first harvest: dns names + sets + users ------------------------------------------
setfile cli_w cli_w ipv4_addr "192.168.5.60 counter packets 50 bytes 6000 expires 59m, 192.168.5.61 counter packets 20 bytes 2000 expires 59m"
setfile cli_v cli_v ipv4_addr "192.168.5.60 counter packets 70 bytes 9000 expires 59m"
setfile pair_w pair_w "ipv4_addr . ipv4_addr" "192.168.5.61 . 5.6.7.8 counter packets 10 bytes 1500 expires 4m, 192.168.5.61 . 9.9.9.9 counter packets 2 bytes 400 expires 4m, 192.168.5.60 . 7.7.7.7 counter packets 4 bytes 600 expires 4m"
setfile pair_v pair_v "ipv4_addr . ipv4_addr" "192.168.5.60 . 1.2.3.4 counter packets 60 bytes 8000 expires 4m, 192.168.5.60 . 149.154.167.91 counter packets 5 bytes 700 expires 4m"
mkstate 6000 9000 "6000 bytes" "9000 bytes"
XGUARD_NOW=$t0 $A harvest 2>$SIM/err1
[ -s $SIM/err1 ] && { echo "stderr:"; cat $SIM/err1; }
cat > $SIM/q.uc <<'EOF'
import { readfile } from 'fs';
let j = json(readfile(ARGV[0]));
for (let k in split(ARGV[1], '/')) j = (j == null) ? null : j[k];
print((type(j) == 'array') ? join(',', j) : j, '\n');
EOF
q() { ucode $SIM/q.uc $RUN/acct/today.json "$1" | sed 's/^null$//'; }
eq "client totals (cli_w/cli_v)" "6000,9000" "$(q clients/192.168.5.60/w),$(q clients/192.168.5.60/v)"
eq "site from DNS CNAME chain (asked name wins)" "0,8000" "$(q clients/192.168.5.60/s/instagram.com)"
eq "site from DNS cache hit" "1500" "$(q clients/192.168.5.61/s/digikala.com | cut -d, -f1)"
eq "co.uk site" "400" "$(q clients/192.168.5.61/s/example.co.uk | cut -d, -f1)"
eq "IP without DNS name stays an IP" "600" "$(q clients/192.168.5.60/s/7.7.7.7 | cut -d, -f1)"
eq "telegram by address range" "700" "$(q clients/192.168.5.60/s/telegram.org | cut -d, -f2)"
eq "quota user usage from counters" "6000,9000" "$(q users/ip:192.168.5.60/w),$(q users/ip:192.168.5.60/v)"
eq "not throttled yet" "0,0" "$(q users/ip:192.168.5.60/tw),$(q users/ip:192.168.5.60/tv)"
eq "day id" "20261124" "$(q day)"

# ---- 3. second harvest: only the DELTA is added ----------------------------------------
setfile cli_w cli_w ipv4_addr "192.168.5.60 counter packets 55 bytes 6500 expires 59m, 192.168.5.61 counter packets 20 bytes 2000 expires 59m"
setfile pair_w pair_w "ipv4_addr . ipv4_addr" "192.168.5.61 . 5.6.7.8 counter packets 10 bytes 1500 expires 4m, 192.168.5.60 . 7.7.7.7 counter packets 5 bytes 1100 expires 4m"
# quota of the VPN class reached
mkstate 6500 9100 "6500 bytes" "100 mbytes"
XGUARD_NOW=$((t0+30)) $A harvest 2>$SIM/err2
eq "delta added once (client)" "6500" "$(q clients/192.168.5.60/w)"
eq "delta added once (site)" "1100" "$(q clients/192.168.5.60/s/7.7.7.7 | cut -d, -f1)"
eq "unchanged element adds nothing" "1500" "$(q clients/192.168.5.61/s/digikala.com | cut -d, -f1)"
eq "throttled flag from the quota object" "0,1" "$(q users/ip:192.168.5.60/tw),$(q users/ip:192.168.5.60/tv)"

# ---- 4. element re-created (counter went down) counts from zero ------------------------------
setfile pair_w pair_w "ipv4_addr . ipv4_addr" "192.168.5.61 . 5.6.7.8 counter packets 1 bytes 100 expires 4m"
XGUARD_NOW=$((t0+60)) $A harvest 2>/dev/null
eq "re-created element: +100, not negative" "1600" "$(q clients/192.168.5.61/s/digikala.com | cut -d, -f1)"

# ---- 5. flash persistence + restart ----------------------------------------------------------
XGUARD_NOW=$((t0+700)) $A harvest 2>/dev/null		# >600 s since start -> day file written
[ -s $ETC/acct/day-20261124.json.gz ] && ok "day file on flash" || bad "day file on flash"
rm -rf $RUN/acct
for s in w v; do setfile cli_$s cli_$s ipv4_addr ""; setfile pair_$s pair_$s "ipv4_addr . ipv4_addr" ""; done
XGUARD_NOW=$((t0+720)) $A harvest 2>/dev/null
eq "after reboot (RAM gone) the day continues from flash" "6500" "$(q clients/192.168.5.60/w)"
cp $ETC/acct/day-20261124.json.gz $SIM/flash-copy.gz

# ---- 6. seeds go into the generated ruleset ------------------------------------------------------
seed=$(ucode $SIM/lib/gen.uc nft seed)
echo "$seed" | grep -q 'counter cw1 { packets 0 bytes 6500 }' && ok "seed: counter cw1 restored" || bad "seed: counter cw1"
echo "$seed" | grep -q 'quota qv1 { over 104857600 bytes used 104857600 bytes }' && ok "seed: throttled quota stays throttled" || bad "seed: quota qv1"
tpl=$(ucode $SIM/lib/gen.uc nft)
echo "$tpl" | grep -q 'counter cw1 { packets 0 bytes 0 }' && ok "template (change detection) has no usage in it" || bad "template has zeros"

# raising the allowance frees a throttled user (the flag only holds for the limit it was reached with)
sed -i "s/option vpn_mb '100'/option vpn_mb '200'/" $SIM/conf/xguard
ucode $SIM/lib/gen.uc nft seed | grep -q 'quota qv1 { over 209715200 bytes used 9100 bytes }' && ok "raised allowance is not seeded as used up" || bad "raised allowance"
sed -i "s/option vpn_mb '200'/option vpn_mb '100'/" $SIM/conf/xguard

# ---- 7. clock behind the last save must NOT start a new day --------------------------------------
XGUARD_NOW=$((t0-86400*3)) $A harvest 2>/dev/null
eq "old clock: still the same day" "20261124" "$(q day)"
rm -f $SIM/nft.calls

# ---- 8. day rollover: finished day saved, usage zeroed, ruleset reloaded with zero seeds ------------
XGUARD_NOW=$((t0+86400)) $A harvest 2>/dev/null
eq "new day id" "20261125" "$(q day)"
eq "usage reset" "0,0" "$(q users/ip:192.168.5.60/w),$(q users/ip:192.168.5.60/v)"
eq "throttle flag cleared" "0,0" "$(q users/ip:192.168.5.60/tw),$(q users/ip:192.168.5.60/tv)"
eq "per-site numbers cleared" "" "$(q clients/192.168.5.60/s/7.7.7.7)"
[ -s $ETC/acct/day-20261124.json.gz ] && ok "yesterday kept on flash" || bad "yesterday kept"
grep -q 'counter cw1 { packets 0 bytes 0 }' $SIM/last-load.nft 2>/dev/null && ok "ruleset reloaded with zero counters" || bad "ruleset reload at rollover"
XGUARD_NOW=$((t0+86400)) ucode $SIM/lib/acct.uc report 20261124 > $SIM/rep.json
eq "history report of the finished day" "6500" "$(ucode $SIM/q.uc $SIM/rep.json clients/192.168.5.60/w)"

mkstate 0 0 "0 bytes" "0 bytes"

# ---- 9. retention (acct_days=2) ------------------------------------------------------------------
XGUARD_NOW=$((t0+86400*2)) $A harvest 2>/dev/null
XGUARD_NOW=$((t0+86400*3)) $A harvest 2>/dev/null
n=$(ls $ETC/acct | grep -c '^day-')
eq "only acct_days day files kept" "2" "$n"

# ---- 10. manual reset of one user ----------------------------------------------------------------------
setfile cli_w cli_w ipv4_addr "192.168.5.60 counter packets 1 bytes 10 expires 59m"
mkstate 800 900 "800 bytes" "900 bytes"
XGUARD_NOW=$((t0+86400*3+30)) $A harvest 2>/dev/null
eq "usage visible" "800,900" "$(q users/ip:192.168.5.60/w),$(q users/ip:192.168.5.60/v)"
XGUARD_NOW=$((t0+86400*3+40)) $A reset ip:192.168.5.60 >/dev/null 2>&1
eq "manual reset zeroes the user" "0,0" "$(q users/ip:192.168.5.60/w),$(q users/ip:192.168.5.60/v)"

# ---- 11. a quota removed from the configuration disappears --------------------------------------------
printf "config main main
	option enabled 1
	list wan_if wan
" > $SIM/conf/xguard
rm -f $RUN/acct/map.json
XGUARD_NOW=$((t0+86400*3+60)) $A harvest 2>/dev/null
eq "removed quota user is gone" "" "$(q users/ip:192.168.5.60/w)"

# ---- 12. exempted domains: bypass_dyn from the query log and across reloads ------------------------------
rm -rf $RUN $ETC $SIM/nft.calls; mkdir -p $RUN $ETC
for x in w v; do setfile cli_$x cli_$x ipv4_addr ""; setfile pair_$x pair_$x "ipv4_addr . ipv4_addr" ""; done
printf "config main main\n\toption enabled 1\n\tlist wan_if wan\nconfig bypass\n\tlist cidr Aparat.com\n\tlist cidr '*.ir'\n\tlist cidr 10.0.0.0/8\n" > $SIM/conf/xguard
cat > $RUN/dns.log <<'EOF'
Nov 24 10:00:00 dnsmasq[1]: 1 192.168.4.101/5 query[A] www.aparat.com from 192.168.4.101
Nov 24 10:00:00 dnsmasq[1]: 1 192.168.4.101/5 cached www.aparat.com is 185.147.179.11
Nov 24 10:00:01 dnsmasq[1]: 2 192.168.4.101/6 query[A] a.b.test.ir from 192.168.4.101
Nov 24 10:00:01 dnsmasq[1]: 2 192.168.4.101/6 reply a.b.test.ir is 2.2.2.2
Nov 24 10:00:02 dnsmasq[1]: 3 192.168.4.101/7 query[A] notaparat.com from 192.168.4.101
Nov 24 10:00:02 dnsmasq[1]: 3 192.168.4.101/7 reply notaparat.com is 3.3.3.3
EOF
XGUARD_NOW=$t0 $A harvest 2>$SIM/err3
[ -s $SIM/err3 ] && cat $SIM/err3
added=$(grep "add element inet xguard bypass_dyn" $SIM/nft.calls 2>/dev/null)
case "$added" in *185.147.179.11*) ok "cached answer of an exempted domain is added";; *) bad "cached aparat address added ($added)";; esac
case "$added" in *2.2.2.2*) ok "suffix rule (*.ir) matches";; *) bad "*.ir match";; esac
case "$added" in *3.3.3.3*) bad "notaparat.com must not match";; *) ok "similar name is not matched";; esac
setfile bypass_dyn bypass_dyn ipv4_addr "185.147.179.11 expires 11h, 2.2.2.2 timeout 12h expires 5h"
ucode $SIM/lib/gen.uc nft seed | grep -q 'elements = { 185.147.179.11, 2.2.2.2 }' && ok "exempted addresses survive a reload" || bad "bypass_dyn seeding"
ucode $SIM/lib/gen.uc nft | grep -q 'elements = { 185.147' && bad "template must not contain addresses" || ok "template has no addresses"

# ---- 13. default allowance and its exceptions -----------------------------------------------------------
rm -rf $RUN $ETC; mkdir -p $RUN $ETC; rm -f $D/bypass_dyn
cat > $SIM/neigh <<'EOF'
192.168.5.104 dev phy0-ap0 lladdr 7a:61:4a:86:97:51 STALE
192.168.5.50 dev phy0-ap0 lladdr aa:bb:cc:00:00:50 REACHABLE
192.168.4.101 dev phy1-ap0 lladdr aa:bb:cc:00:00:01 REACHABLE
192.168.5.77 dev phy0-ap0 lladdr aa:bb:cc:00:00:99 REACHABLE
192.168.1.1 dev wan lladdr 30:a2:20:cf:a4:8c REACHABLE
192.168.5.200 dev phy0-ap0  FAILED
EOF
cat > $SIM/conf/xguard <<'EOF'
config main 'main'
	option enabled '1'
	option def_wl_mb '100'
	option def_wl_kbps '32'
	option def_vpn_mb '50'
	list wan_if 'wan'
config device
	option ip '192.168.4.101'
	option mode 'vpn'
config device
	option mac 'aa:bb:cc:00:00:99'
	option mode 'vpn'
config quota
	option name 'own'
	option ip '192.168.5.50'
	option wl_mb '10'
EOF
mkstate 0 0 "0 bytes" "0 bytes"
setfile cli_w cli_w ipv4_addr "192.168.5.104 counter packets 5 bytes 5000 expires 1h, 192.168.1.69 counter packets 5 bytes 700 expires 1h"
XGUARD_NOW=$t0 $A harvest 2>$SIM/err4
[ -s $SIM/err4 ] && cat $SIM/err4
eq "known clients: LAN only, no FAILED, no WAN side" "192.168.4.101 192.168.5.50 192.168.5.77 192.168.5.104" "$(awk '{print $1}' $RUN/acct/known | tr '\n' ' ' | sed 's/ $//')"
eq "the router's own address is not a client" "" "$(q clients/192.168.1.69/w)"
N=$(ucode $SIM/lib/gen.uc nft seed)
echo "$N" | grep -q 'ip saddr 192.168.5.104 quota name "qw2"' && ok "default allowance for an ordinary client" || bad "default rule"
echo "$N" | grep -q 'quota qw2 { over 104857600 bytes used 5000 bytes }' && ok "starts with what the client already used" || bad "default seed"
echo "$N" | grep -q 'saddr 192.168.4.101 quota' && bad "exception (ip) must have no default" || ok "exception by IP has no default"
echo "$N" | grep -q 'saddr 192.168.5.77 quota' && bad "exception (mac) must have no default" || ok "exception by MAC has no default"
echo "$N" | grep -q 'quota qv2' && bad "direct mode: no vpn default" || ok "direct mode: whitelist allowance only"
eq "own quota wins over the default" "1" "$(echo "$N" | grep -c 'saddr 192.168.5.50 quota')"
# default_mode vpn: exceptions are the direct devices, both allowances apply
sed -i "s/option def_wl_mb '100'/option def_wl_mb '100'\n\toption default_mode 'vpn'/; s/option mode 'vpn'/option mode 'direct'/" $SIM/conf/xguard
sed -i "0,/aa:bb:cc:00:00:99/s//aa:bb:cc:00:00:99/" $SIM/conf/xguard
V=$(ucode $SIM/lib/gen.uc nft)
echo "$V" | grep -q 'ip saddr 192.168.5.104 quota name "qv' && ok "vpn mode: vpn default too" || bad "vpn default"
echo "$V" | grep -q 'saddr 192.168.4.101 quota' && bad "vpn mode: direct device excepted" || ok "vpn mode: direct device has no default"
printf "config main main\n\toption enabled 1\n\tlist wan_if wan\n" > $SIM/conf/xguard
XGUARD_NOW=$((t0+30)) $A harvest 2>/dev/null
rm -f $RUN/acct/map.json; XGUARD_NOW=$((t0+60)) $A harvest 2>/dev/null
eq "default switched off: its users are gone" "" "$(q users/ip:192.168.5.104/w)"

echo
echo "passed=$pass failed=$fail"
[ $fail = 0 ]
