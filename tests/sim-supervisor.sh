#!/bin/sh
# Supervisor simulation: runs the REAL xguardd + REAL ucode generators inside a sandbox under
# /tmp/xgsim, with stubbed nft/ip/uci/uclient-fetch and a fake xray. Touches nothing outside /tmp.
#
#   tar cf - -C xguard/files/usr/lib/xguard . -C ../../sbin xguardd | ssh root@router 'mkdir -p /tmp/xgsim/lib && tar xf - -C /tmp/xgsim/lib'
#   ssh root@router 'sh -s' < tests/sim-supervisor.sh
#
# Expects /tmp/xgsim/lib/{core.uc,links.uc,gen.uc,xguardd} to be present.

SIM=/tmp/xgsim
RUN=$SIM/run
pass=0; fail=0
ok()   { echo "PASS  $*"; pass=$((pass+1)); }
bad()  { echo "FAIL  $*"; fail=$((fail+1)); }
check() { # check "desc" cmd...
	local d="$1"; shift
	if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi
}
state() { sed -n "s/^$1=//p" $RUN/state 2>/dev/null; }
xr() { pgrep -f "$RUN/[x]ray run"; }
noxr() { ! xr; }
gone() { [ ! -e $RUN/xray ] && noxr; }

rm -rf $SIM/run $SIM/bin $SIM/etc $SIM/conf $SIM/calls.log
mkdir -p $SIM/bin $SIM/etc $SIM/conf $RUN
cp $SIM/lib/xguardd $SIM/xguardd 2>/dev/null; chmod +x $SIM/xguardd

# ---- stubs (log every call) ---------------------------------------------------------------
cat > $SIM/bin/nc <<'EOF2'
#!/bin/sh
# canned plain-HTTP answer (the real nc would contact the internet)
cat >/dev/null
echo "HTTP/1.1 301 Moved"
echo "Date: Thu, 19 Nov 2026 18:14:50 GMT"
echo "Server: stub"
echo
EOF2
cat > $SIM/bin/date <<'EOF2'
#!/bin/sh
# never set the router's real clock: log "-s" calls, pass everything else through
case " $* " in *" -s "*) echo "date $*" >> /tmp/xgsim/calls.log; exit 0;; esac
exec /bin/date "$@"
EOF2
for c in nft ip uci logger; do
cat > $SIM/bin/$c <<EOF
#!/bin/sh
echo "$c \$*" >> $SIM/calls.log
case "$c \$1" in
	"nft list") exit 0;;
	"nft -f") cp "\$2" $SIM/last-nft.rules 2>/dev/null; exit 0;;
esac
exit 0
EOF
done
cat > $SIM/bin/uclient-fetch <<EOF
#!/bin/sh
# serves the fake /debug/vars document
[ -f $RUN/fake_vars ] && cat $RUN/fake_vars || exit 1
EOF
cat > $SIM/bin/dnsmasq-init <<EOF
#!/bin/sh
echo "dnsmasq-init \$*" >> $SIM/calls.log
EOF
cat > $RUN/xray <<'EOF'
#!/bin/sh
case "$1" in
	version) echo "Xray 0.0.0 (fake)"; echo "built for sim";;
	run) while :; do sleep 1; done;;
esac
EOF
chmod +x $SIM/bin/* $RUN/xray

cat > $SIM/conf/xguard <<'EOF'
config main 'main'
	option enabled '1'
	option node 'n_a'
	option fail_threshold '1'
	option dns_bypass '178.22.122.100'
	option probe_interval '3'
	list wan_if 'wan'

config node 'n_a'
	option type 'link'
	option link 'vless://11111111-2222-3333-4444-555555555555@example.com:443?type=ws&security=tls&sni=example.com&path=%2Fws#a'

config node 'n_b'
	option type 'link'
	option link 'vless://11111111-2222-3333-4444-555555555555@203.0.113.7:443?type=tcp&security=reality&sni=www.microsoft.com&pbk=AAAA&sid=ab12&flow=xtls-rprx-vision#b'

config iface
	option name 'phy0-ap0'
	option mode 'vpn'

config bypass
	list cidr '203.0.113.0/24'
	list cidr 'example.ir'
	list cidr 'geosite:ir'
EOF

ALIVE='{"observatory":{"proxy":{"alive":true,"delay":80,"outbound_tag":"proxy"}},"stats":{"outbound":{"proxy":{"uplink":10,"downlink":20}}}}'
DEAD='{"observatory":{"proxy":{"delay":99999999,"outbound_tag":"proxy","last_error_reason":"dead"}}}'

export PATH=$SIM/bin:$PATH
export XGUARD_RUN=$RUN XGUARD_LIB=$SIM/lib XGUARD_CONF=$SIM/conf/xguard XGUARD_CONFDIR=$SIM/conf
export XGUARD_ETC=$SIM/etc XGUARD_DNSMASQ_INIT=$SIM/bin/dnsmasq-init XGUARD_TICK=1

echo "== one-shot guard"
sh $SIM/xguardd guard
check "guard applied the ruleset via nft -f"        grep -q '^nft -f' $SIM/calls.log
check "ruleset has the kill-switch drop"            grep -q 'iifname @vpn_ifs oifname @wan_ifs counter drop' $SIM/last-nft.rules
check "user bypass is exempt from the kill-switch (after block, before vpn drops)" sh -c "awk '/chain guard_fwd/,/}/' $SIM/last-nft.rules | grep -n -E 'block_ifs|bypass_user|vpn_ifs' | tr '
' ' ' | grep -q 'block_ifs.*bypass_user.*vpn_ifs'"
check "policy routing rule installed"               grep -q 'ip rule add fwmark 0x58000000/0xff000000 lookup 100' $SIM/calls.log
check "dnsmasq pointed at xray DNS inbound"         grep -q 'add_list dhcp.@dnsmasq\[0\].server=127.0.0.1#15353' $SIM/calls.log

echo "== supervisor run"
sh $SIM/xguardd > $SIM/daemon.out 2>&1 &
DPID=$!
sleep 4
check "xray started with node n_a"                  [ "$(state node)" = n_a ]
check "xray process exists"                         xr
check "config.json generated for n_a"               grep -q 'example.com' $RUN/config.json
check "GOMEMLIMIT not leaking into file but process runs" kill -0 $DPID
check "bypass domains become an xray direct rule"    grep -q '"domain:example.ir"' $RUN/config.json
check "bypass domains turn sniffing on"             grep -q '"routeOnly": true' $RUN/config.json
check "domain DNS server gets its own tag + direct route" grep -q '"dns-bypass"' $RUN/config.json
check "domains never reach the nft sets"            sh -c "! grep -q 'example.ir' $SIM/last-nft.rules"
check "invalid bypass entries are logged, not fatal" grep -q 'config warning: .*geosite:ir' $RUN/xguardd.log
echo "$ALIVE" > $RUN/fake_vars
sleep 3
check "status becomes running when tunnel alive"    [ "$(state status)" = running ]
check "delay and traffic reported"                  [ "$(state delay)" = 80 ] && [ "$(state up_bytes)" = 10 ]

check "clock fixed from the HTTP Date header"       grep -q "date -u -s 2026-11-19 18:14:50" $SIM/calls.log

echo "== dead tunnel -> failover (kill-switch stays: no nft delete)"
echo "$DEAD" > $RUN/fake_vars
sleep 9
check "switched to next node n_b"                   [ "$(state node)" = n_b ]
check "config.json now for n_b (reality)"           grep -q reality $RUN/config.json
check "xray restarted (restarts>=2)"                [ "$(state restarts)" -ge 2 ]
check "ruleset was never deleted during failover"   sh -c "! grep -q '^nft delete' $SIM/calls.log"
echo "$ALIVE" > $RUN/fake_vars
sleep 3
check "running again on n_b"                        [ "$(state status)" = running ]

echo "== xray crash -> auto restart"
OLD=$(xr | head -n1)
kill -9 $OLD
sleep 6
NEW=$(xr | head -n1)
check "xray respawned with a new pid"               [ -n "$NEW" ] && [ "$NEW" != "$OLD" ]

echo "== operator command: next"
echo next > $RUN/cmd
sleep 6
check "next -> back to n_a"                         [ "$(state node)" = n_a ]

echo "== config change (preferred node + new iface) is picked up without restart of the daemon"
cat >> $SIM/conf/xguard <<'EOF'

config iface
	option name 'lan2'
	option mode 'block'
EOF
sleep 4
check "ruleset re-applied with the new block iface" grep -q '"lan2"' $SIM/last-nft.rules

echo "== documented kill-switch test: hold file + kill xray (guard must stay, xray must not restart)"
CALLS_BEFORE=$(grep -c '^nft delete' $SIM/calls.log)
touch $RUN/hold
for p in $(xr); do kill $p 2>/dev/null; done
sleep 7
check "status updating while held"                  [ "$(state status)" = updating ]
check "xray not restarted while held"               noxr
check "ruleset still loaded (no nft delete)"        [ "$(grep -c '^nft delete' $SIM/calls.log)" = "$CALLS_BEFORE" ]
rm -f $RUN/hold
sleep 6
check "xray comes back after hold removed"          xr

echo "== xray binary replacement (hold)"
touch $RUN/hold; echo update-xray > $RUN/cmd
sleep 4
check "xray stopped and binary removed while held"  gone
check "status reports updating"                     [ "$(state status)" = updating ]
cat > $RUN/xray <<'EOF'
#!/bin/sh
case "$1" in
	version) echo "Xray 9.9.9 (fake2)";;
	run) while :; do sleep 1; done;;
esac
EOF
chmod +x $RUN/xray; rm -f $RUN/hold
sleep 5
check "xray started again after hold is released"   xr
check "new binary version reported"                 grep -q 9.9.9 $RUN/xray.version

echo "== disable -> everything torn down"
sed -i "s/option enabled '1'/option enabled '0'/" $SIM/conf/xguard
sleep 5
check "status disabled"                             [ "$(state status)" = disabled ]
check "xray stopped"                                noxr
check "ruleset deleted (nft delete table)"          grep -q 'nft delete table inet xguard' $SIM/calls.log

echo "== graceful stop kills children"
sed -i "s/option enabled '0'/option enabled '1'/" $SIM/conf/xguard
sleep 6
check "xray running again after re-enable"          xr
kill -TERM $DPID; sleep 2
check "daemon exited on TERM"                       sh -c "! kill -0 $DPID 2>/dev/null"
check "no orphan xray after TERM"                   noxr

for p in $(xr); do kill $p 2>/dev/null; done
echo
echo "RESULT: $pass passed, $fail failed"
echo "--- daemon log tail"; tail -n 25 $RUN/xguardd.log
