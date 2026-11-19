'use strict';

// xguard core: UCI loading, xray config generation, nftables ruleset generation.
// Pure-ish: only reads UCI, /tmp/dhcp.leases and /tmp/xguard/* and returns strings/objects.

import { cursor } from 'uci';
import { readfile } from 'fs';
import { parse_link } from './links.uc';

const RUN = '/tmp/xguard';
const MARK = '0x58000000';

function isnan(x) {
	return type(x) == 'double' && x != x;
}

function arr(v) {
	if (v == null || v === '')
		return [];
	return (type(v) == 'array') ? v : [ v ];
}

function mget(m, k, def) {
	let v = m[k];
	return (v == null || v === '') ? def : v;
}

function mint(m, k, def) {
	let n = int(mget(m, k, def));
	return isnan(n) ? def : n;
}

const RE_IFACE = /^[A-Za-z0-9_.@:+-]{1,15}$/;
const RE_IP = /^[0-9]{1,3}(\.[0-9]{1,3}){3}(\/[0-9]{1,2})?$/;
const RE_MAC = /^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$/;

function sid(s) {
	return s['.name'];
}

// bypass entries are either an IPv4/CIDR (handled by nftables, never reaches xray) or a domain
// (handled by an xray routing rule -> "direct"). geosite:/geoip: are refused: the .dat files are not shipped.
const RE_HOST = /^([A-Za-z0-9_-]+\.)*[A-Za-z0-9_-]+$/;

// -> { kind: 'ip'|'domain', value } or null when the entry is not valid
function classify_bypass(entry) {
	let e = trim('' + entry);
	if (match(e, RE_IP)) {
		let ok = true;
		for (let o in split(split(e, '/')[0], '.'))
			if (int(o) > 255)
				ok = false;
		let bits = split(e, '/')[1];
		if (bits != null && int(bits) > 32)
			ok = false;
		return ok ? { kind: 'ip', value: e } : null;
	}
	let pfx = 'domain';
	let wild = false;
	let m = match(e, /^(domain|full|keyword):(.+)$/);
	if (m) {
		pfx = m[1];
		e = m[2];
	}
	// "*.ir" / ".ir" / "*.example.ir" = that suffix and everything below it (xray: domain:ir)
	let w = (pfx == 'domain') ? match(e, /^\*?\.(.+)$/) : null;
	if (w) {
		wild = true;
		e = w[1];
	}
	e = lc(e);
	if (length(e) > 253 || !match(e, RE_HOST))
		return null;
	if (pfx != 'keyword') {
		if (wild && index(e, '.') < 0) {
			if (!match(e, /^[a-z][a-z0-9-]*$/))		// a bare top-level domain such as "ir"
				return null;
		} else if (index(e, '.') < 0 || match(e, /\.[0-9]+$/))
			return null;		// a bare word / "1.2.3" is almost always a typo; use keyword: on purpose
	}
	return { kind: 'domain', value: pfx + ':' + e };
}

function bypass_split(list) {
	let r = { ips: [], domains: [], bad: [] };
	for (let b in list) {
		let c = classify_bypass(b);
		if (!c)
			push(r.bad, b);
		else
			push(c.kind == 'ip' ? r.ips : r.domains, c.value);
	}
	return r;
}

function load_config() {
	let dir = getenv('XGUARD_CONFDIR');	// test hook
	let c = dir ? cursor(dir, dir + '/.save') : cursor();
	let cfg = { main: {}, nodes: [], ifaces: [], devices: [], bypass: [], limits: [] };

	c.foreach('xguard', 'main', (s) => { cfg.main = s; });
	c.foreach('xguard', 'node', (s) => { if (s.enabled != '0') push(cfg.nodes, s); });
	c.foreach('xguard', 'iface', (s) => { if (match(s.name || '', RE_IFACE)) push(cfg.ifaces, s); });
	c.foreach('xguard', 'device', (s) => { push(cfg.devices, s); });
	c.foreach('xguard', 'bypass', (s) => { for (let x in arr(s.cidr)) push(cfg.bypass, x); });
	c.foreach('xguard', 'limit', (s) => { push(cfg.limits, s); });

	cfg.main.enabled = (mget(cfg.main, 'enabled', '0') == '1');
	return cfg;
}

// preferred node first, then the other enabled nodes in config order
function ordered_nodes(cfg) {
	let pref = mget(cfg.main, 'node', '');
	let first = [], rest = [];
	for (let n in cfg.nodes)
		push((sid(n) == pref) ? first : rest, n);
	return [ ...first, ...rest ];
}

function node_by_id(cfg, id) {
	for (let n in cfg.nodes)
		if (sid(n) == id)
			return n;
	return null;
}

// ---------------------------------------------------------------- xray config

function ensure(o, k) {
	if (type(o[k]) != 'object')
		o[k] = {};
	return o[k];
}

function node_chain(node, main) {
	let chain;

	switch (mget(node, 'type', 'link')) {
	case 'ssh':
		chain = [ { protocol: 'socks', settings: { address: '127.0.0.1', port: mint(main, 'ssh_socks_port', 10809) } } ];
		break;
	case 'json': {
		let j = json(node.json);
		chain = (type(j) == 'array') ? j : [ j ];
		break;
	}
	default: {
		let r = parse_link(node.link);
		chain = [ r.outbound ];
		break;
	}
	}

	for (let i = 0; i < length(chain); i++) {
		delete chain[i].__warning;
		chain[i].tag = (i == 0) ? 'proxy' : 'hop-' + i;
		if (i > 0)
			ensure(ensure(chain[i - 1], 'streamSettings'), 'sockopt').dialerProxy = chain[i].tag;
	}
	return chain;
}

// plain IPv4 resolver outside the tunnel: the WAN's upstream (resolv.conf.auto), else bootstrap_dns
function local_dns(m) {
	for (let f in [ '/tmp/resolv.conf.d/resolv.conf.auto', '/tmp/resolv.conf.auto' ]) {
		for (let line in split(readfile(f) || '', '\n')) {
			let r = match(trim(line), /^nameserver[ 	]+([0-9.]+)$/);
			if (r && match(r[1], RE_IP) && !match(r[1], /^127\./))
				return r[1];
		}
	}
	for (let ip in split(trim(mget(m, 'bootstrap_dns', '1.1.1.1 8.8.8.8')), /[ ,]+/))
		if (match(ip, RE_IP))
			return ip;
	return '';
}

function gen_xray(cfg, node) {
	let m = cfg.main;
	let bp = bypass_split(cfg.bypass);
	for (let b in bp.bad)
		warn(sprintf('xguard: ignoring invalid bypass entry "%s" (use IPv4/CIDR or a domain like example.com)\n', b));
	// domain rules can only match when xray sniffs the TLS SNI / HTTP Host / QUIC, so it is switched on for them
	let sniff = (mget(m, 'sniffing', '0') == '1') || length(bp.domains) > 0;
	let sn = (protos) => sniff ? { enabled: true, destOverride: protos, routeOnly: true } : { enabled: false };
	let is_ssh = (mget(node, 'type', 'link') == 'ssh');
	let dns_bypass = trim(mget(m, 'dns_bypass', ''));

	let chain = node_chain(node, m);

	// The node's own host name must be resolved OUTSIDE the tunnel. While xguard is on, the router's resolver
	// (dnsmasq) forwards to xray, and xray would need the tunnel to look up the very host the tunnel runs on.
	// So: xray resolves these names itself, through a plain bootstrap DNS server that is routed 'direct'.
	let boot_hosts = [];
	let addr_of = (o) => {
		let st = o.settings || {};
		let list = [ st.address ];
		for (let v in (type(st.vnext) == 'array' ? st.vnext : []))
			push(list, v.address);
		for (let v in (type(st.servers) == 'array' ? st.servers : []))
			push(list, v.address);
		return filter(list, (a) => type(a) == 'string' && a != '' && !match(a, RE_IP) && index(a, ':') < 0);
	};
	for (let o in chain) {
		let names = addr_of(o);
		if (!length(names))
			continue;
		for (let a in names)
			push(boot_hosts, 'full:' + lc(a));
		ensure(ensure(o, 'streamSettings'), 'sockopt').domainStrategy = 'UseIPv4';
	}

	let rules = [
		{ type: 'field', inboundTag: [ 'dns-in' ], outboundTag: 'dns-out' }
	];
	let dns_servers = [];
	if (length(boot_hosts)) {
		let boot_ips = filter(split(trim(mget(m, 'bootstrap_dns', '1.1.1.1 8.8.8.8')), /[ ,]+/), (x) => match(x, RE_IP));
		let tags = [];
		let k = 0;
		for (let ip in boot_ips) {
			let tag = 'dns-boot' + (k++);
			push(tags, tag);
			push(dns_servers, { tag: tag, address: ip, domains: boot_hosts, skipFallback: true });
		}
		if (length(tags))
			push(rules, { type: 'field', inboundTag: tags, outboundTag: 'direct' });
	}
	if (length(bp.domains)) {
		// bypassed domains must also be resolved outside the tunnel (geo-DNS), if the user gave a resolver for it
		// default: the router's own upstream (ISP) resolver, else the bootstrap DNS, so these domains keep
		// resolving - and working - even while the tunnel is down
		if (dns_bypass == '')
			dns_bypass = local_dns(m);
		if (dns_bypass != '') {
			push(dns_servers, { tag: 'dns-bypass', address: dns_bypass, domains: bp.domains, skipFallback: true });
			push(rules, { type: 'field', inboundTag: [ 'dns-bypass' ], outboundTag: 'direct' });
		}
		push(rules, { type: 'field', domain: bp.domains, outboundTag: 'direct' });
	}
	push(dns_servers, mget(m, 'dns_remote', 'tcp://1.1.1.1'));
	// drop QUIC so browsers fall back to TCP quickly (always for nodes without UDP, i.e. ssh)
	if (is_ssh || mget(m, 'block_quic', '1') == '1')
		push(rules, { type: 'field', network: 'udp', port: '443', outboundTag: 'block' });

	let conf = {
		log: { loglevel: mget(m, 'log_level', 'warning'), access: 'none', error: RUN + '/xray.log' },
		stats: {},
		metrics: { tag: 'metrics', listen: '127.0.0.1:' + mint(m, 'metrics_port', 11111) },
		policy: {
			levels: { '0': {
				handshake: 4, connIdle: 120, uplinkOnly: 2, downlinkOnly: 4, bufferSize: 32
			} },
			system: { statsOutboundUplink: true, statsOutboundDownlink: true }
		},
		dns: { servers: dns_servers, queryStrategy: 'UseIPv4' },
		inbounds: [
			{
				tag: 'redir', listen: '0.0.0.0', port: mint(m, 'redir_port', 12345),
				protocol: 'dokodemo-door',
				settings: { network: 'tcp', followRedirect: true },
				sniffing: sn([ 'http', 'tls' ])
			},
			{
				tag: 'tproxy', listen: '0.0.0.0', port: mint(m, 'tproxy_port', 12346),
				protocol: 'dokodemo-door',
				settings: { network: 'udp', followRedirect: true },
				streamSettings: { sockopt: { tproxy: 'tproxy' } },
				sniffing: sn([ 'quic' ])
			},
			{
				tag: 'dns-in', listen: '127.0.0.1', port: mint(m, 'dns_port', 15353),
				protocol: 'dokodemo-door',
				settings: { address: '1.1.1.1', port: 53, network: 'tcp,udp' }
			},
			{
				tag: 'socks-in', listen: '127.0.0.1', port: mint(m, 'socks_port', 10808),
				protocol: 'socks', settings: { auth: 'noauth', udp: true }
			}
		],
		outbounds: [
			...chain,
			{ tag: 'direct', protocol: 'freedom' },
			{ tag: 'block', protocol: 'blackhole' },
			{ tag: 'dns-out', protocol: 'dns' }
		],
		routing: { domainStrategy: 'AsIs', rules: rules },
		observatory: {
			subjectSelector: [ 'proxy' ],
			probeUrl: mget(m, 'probe_url', 'https://www.gstatic.com/generate_204'),
			probeInterval: mint(m, 'probe_interval', 10) + 's'
		}
	};

	return sprintf('%J', conf);
}

// ------------------------------------------------------------------ nftables

const DEFAULT_BYPASS = [
	'0.0.0.0/8', '10.0.0.0/8', '100.64.0.0/10', '127.0.0.0/8', '169.254.0.0/16',
	'172.16.0.0/12', '192.168.0.0/16', '224.0.0.0/4', '240.0.0.0/4'
];

function qlist(list) {
	return join(', ', map(list, (x) => sprintf('"%s"', x)));
}

function set_decl(name, typ, items, flags) {
	let s = '\tset ' + name + ' {\n\t\ttype ' + typ + '\n';
	if (flags)
		s += '\t\tflags ' + flags + '\n';
	if (length(items))
		s += '\t\telements = { ' + join(', ', items) + ' }\n';
	return s + '\t}\n';
}

function lease_ips(mac) {
	let ips = [];
	let txt = readfile('/tmp/dhcp.leases');
	mac = lc(mac);
	for (let line in split(txt || '', '\n')) {
		let f = split(line, ' ');
		if (length(f) >= 3 && lc(f[1]) == mac && match(f[2], RE_IP))
			push(ips, f[2]);
	}
	return ips;
}

function gen_nft(cfg) {
	let m = cfg.main;

	if (!cfg.main.enabled)
		return null;

	let vpn_if = [], block_if = [], direct_if = [], direct_ip = [], direct_mac = [], vpn_ip = [], vpn_mac = [];
	// global policy: 'direct' = nothing is proxied unless chosen (vpn interfaces / vpn devices);
	//                'vpn'    = every client (everything not coming from WAN) is proxied unless exempted (direct interfaces / direct devices)
	let dmode = (mget(m, 'default_mode', 'direct') == 'vpn') ? 'vpn' : 'direct';
	let wan = filter(arr(m.wan_if), (x) => match(x, RE_IFACE));
	if (!length(wan))
		wan = [ 'wan' ];

	for (let i in cfg.ifaces) {
		if (i.mode == 'vpn')
			push(vpn_if, i.name);
		else if (i.mode == 'block')
			push(block_if, i.name);
		else if (i.mode == 'direct')
			push(direct_if, i.name);
	}
	for (let dv in cfg.devices) {
		let list = (dv.mode == 'direct') ? [ direct_ip, direct_mac ] : [ vpn_ip, vpn_mac ];
		if (dv.mac && match(dv.mac, RE_MAC))
			push(list[1], lc(dv.mac));
		else if (dv.ip && match(dv.ip, RE_IP))
			push(list[0], dv.ip);
	}

	let user_bypass = bypass_split(cfg.bypass).ips;		// domains are handled by xray, see gen_xray()
	let bypass = [ ...DEFAULT_BYPASS, ...user_bypass ];

	let rp = mint(m, 'redir_port', 12345);
	let tp = mint(m, 'tproxy_port', 12346);

	let o = 'table inet xguard\ndelete table inet xguard\ntable inet xguard {\n';
	o += set_decl('vpn_ifs', 'ifname', map(vpn_if, (x) => sprintf('"%s"', x)));
	o += set_decl('block_ifs', 'ifname', map(block_if, (x) => sprintf('"%s"', x)));
	o += set_decl('direct_ifs', 'ifname', map(direct_if, (x) => sprintf('"%s"', x)));
	o += set_decl('wan_ifs', 'ifname', map(wan, (x) => sprintf('"%s"', x)));
	o += set_decl('direct_ips', 'ipv4_addr', direct_ip, 'interval');
	o += set_decl('direct_macs', 'ether_addr', direct_mac);
	o += set_decl('vpn_ips', 'ipv4_addr', vpn_ip, 'interval');
	o += set_decl('vpn_macs', 'ether_addr', vpn_mac);
	o += set_decl('bypass4', 'ipv4_addr', bypass, 'interval\n\t\tauto-merge');
	o += set_decl('bypass_user', 'ipv4_addr', user_bypass, 'interval\n\t\tauto-merge');

	// per-user speed limits (policers: drop what exceeds the rate)
	let up_rules = '', down_rules = '', objs = '';
	let n = 0;
	for (let l in cfg.limits) {
		n++;
		let kb = (v) => { let r = int(v); return isnan(r) ? 0 : int(r / 8); };
		let up = kb(l.up), dn = kb(l.down);
		let up_m = [], dn_m = [];
		if (l.ip && match(l.ip, RE_IP)) {
			push(up_m, 'ip saddr ' + l.ip);
			push(dn_m, 'ip daddr ' + l.ip);
		} else if (l.mac && match(l.mac, RE_MAC)) {
			push(up_m, 'ether saddr ' + lc(l.mac));
			for (let ip in lease_ips(l.mac))
				push(dn_m, 'ip daddr ' + ip);
		} else if (l.iface && match(l.iface, RE_IFACE)) {
			push(up_m, sprintf('iifname "%s"', l.iface));
			push(dn_m, sprintf('oifname "%s"', l.iface));
		} else
			continue;

		if (up > 0) {
			objs += sprintf('\tlimit up%d {\n\t\trate over %d kbytes/second burst %d kbytes\n\t}\n', n, up, up < 64 ? 32 : int(up / 2));
			for (let x in up_m)
				up_rules += sprintf('\t\t%s limit name "up%d" counter drop\n', x, n);
		}
		if (dn > 0) {
			objs += sprintf('\tlimit down%d {\n\t\trate over %d kbytes/second burst %d kbytes\n\t}\n', n, dn, dn < 64 ? 32 : int(dn / 2));
			for (let x in dn_m)
				down_rules += sprintf('\t\t%s limit name "down%d" counter drop\n', x, n);
		}
	}
	o += objs;

	let skip = '\t\tiifname @direct_ifs return\n\t\tip saddr @direct_ips return\n\t\tether saddr @direct_macs return\n';
	let vpn_match = (dmode == 'vpn') ? [ 'iifname != @wan_ifs' ] : [
		'iifname @vpn_ifs', 'ip saddr @vpn_ips', 'ether saddr @vpn_macs'
	];
	// blocked interfaces are never proxied: their traffic must reach the forward-hook drop untouched
	let noproxy = '\t\tiifname @block_ifs return\n';

	// kill-switch: anything from vpn/block clients that reaches FORWARD towards a wan interface is a leak
	o += '\tchain guard_fwd {\n\t\ttype filter hook forward priority -10; policy accept;\n' + skip;
	o += '\t\tiifname @block_ifs oifname @wan_ifs counter drop\n';
	// destinations the user explicitly exempted from the VPN are allowed to go out directly
	o += '\t\tip daddr @bypass_user return\n';
	for (let v in vpn_match)
		o += '\t\t' + v + ' oifname @wan_ifs counter drop\n';
	o += '\t}\n';

	// TCP -> xray (redirect)
	o += '\tchain redir_tcp {\n\t\ttype nat hook prerouting priority -105; policy accept;\n' + skip;
	o += noproxy + '\t\tfib daddr type local return\n\t\tip daddr @bypass4 return\n';
	for (let v in vpn_match)
		o += sprintf('\t\t%s meta l4proto tcp meta mark set %s redirect to :%d\n', v, MARK, rp);
	o += '\t}\n';

	// UDP -> xray (tproxy)
	o += '\tchain tproxy_udp {\n\t\ttype filter hook prerouting priority -150; policy accept;\n' + skip;
	o += noproxy + '\t\tfib daddr type local return\n\t\tip daddr @bypass4 return\n';
	for (let v in vpn_match)
		o += sprintf('\t\t%s meta nfproto ipv4 meta l4proto udp meta mark set %s tproxy ip to :%d accept\n', v, MARK, tp);
	o += '\t}\n';

	o += '\tchain lim_up {\n\t\ttype filter hook prerouting priority -160; policy accept;\n' + up_rules + '\t}\n';
	o += '\tchain lim_down {\n\t\ttype filter hook postrouting priority 0; policy accept;\n' + down_rules + '\t}\n';
	o += '}\n';
	return o;
}

// Minimal ruleset used when the full one cannot be loaded (e.g. missing kernel module):
// keeps the kill-switch (drop vpn/block clients towards wan) and nothing else.
function gen_lockdown(cfg) {
	if (!cfg.main.enabled)
		return null;

	let vpn_if = [], block_if = [], direct_if = [], vpn_ip = [], vpn_mac = [], direct_ip = [], direct_mac = [];
	let dmode = (mget(cfg.main, 'default_mode', 'direct') == 'vpn') ? 'vpn' : 'direct';
	let wan = filter(arr(cfg.main.wan_if), (x) => match(x, RE_IFACE));
	if (!length(wan))
		wan = [ 'wan' ];
	for (let i in cfg.ifaces) {
		if (i.mode == 'vpn')
			push(vpn_if, sprintf('"%s"', i.name));
		else if (i.mode == 'block')
			push(block_if, sprintf('"%s"', i.name));
		else if (i.mode == 'direct')
			push(direct_if, sprintf('"%s"', i.name));
	}
	for (let dv in cfg.devices) {
		let list = (dv.mode == 'direct') ? [ direct_ip, direct_mac ] : [ vpn_ip, vpn_mac ];
		if (dv.mac && match(dv.mac, RE_MAC))
			push(list[1], lc(dv.mac));
		else if (dv.ip && match(dv.ip, RE_IP))
			push(list[0], dv.ip);
	}

	let o = 'table inet xguard\ndelete table inet xguard\ntable inet xguard {\n';
	o += set_decl('direct_ifs', 'ifname', direct_if);
	o += set_decl('vpn_ifs', 'ifname', vpn_if);
	o += set_decl('block_ifs', 'ifname', block_if);
	o += set_decl('wan_ifs', 'ifname', map(wan, (x) => sprintf('"%s"', x)));
	o += set_decl('direct_ips', 'ipv4_addr', direct_ip, 'interval');
	o += set_decl('direct_macs', 'ether_addr', direct_mac);
	o += set_decl('vpn_ips', 'ipv4_addr', vpn_ip, 'interval');
	o += set_decl('vpn_macs', 'ether_addr', vpn_mac);
	o += '\tchain guard_fwd {\n\t\ttype filter hook forward priority -10; policy accept;\n';
	o += '\t\tiifname @direct_ifs return\n\t\tip saddr @direct_ips return\n\t\tether saddr @direct_macs return\n';
	o += '\t\tiifname @block_ifs oifname @wan_ifs counter drop\n';
	o += (dmode == 'vpn') ? '\t\tiifname != @wan_ifs oifname @wan_ifs counter drop\n' : '\t\tiifname @vpn_ifs oifname @wan_ifs counter drop\n';
	o += '\t\tip saddr @vpn_ips oifname @wan_ifs counter drop\n';
	o += '\t\tether saddr @vpn_macs oifname @wan_ifs counter drop\n';
	o += '\t}\n}\n';
	return o;
}

// ------------------------------------------------------------------- health

// text of http://127.0.0.1:<metrics>/debug/vars  ->  { known, alive, delay, up, down }
// xray (26.x) exposes:  observatory.<tag> = { delay, outbound_tag, last_error_reason, [alive:true] }
//                       stats.outbound.<tag> = { uplink, downlink }
// A dead outbound has NO "alive" key and delay 99999999.
function parse_vars(txt) {
	let r = { known: false, alive: false, delay: 0, up: 0, down: 0 };
	let j;
	try { j = json(txt); } catch (e) { return r; }
	if (type(j) != 'object')
		return r;

	let obs = j.observatory;
	if (type(obs) == 'object' && type(obs.proxy) == 'object') {
		r.known = true;
		r.alive = (obs.proxy.alive == true);
		r.delay = r.alive ? (obs.proxy.delay || 0) : 0;
	}
	let st = j.stats;
	if (type(st) == 'object' && type(st.outbound) == 'object' && type(st.outbound.proxy) == 'object') {
		r.up = st.outbound.proxy.uplink || 0;
		r.down = st.outbound.proxy.downlink || 0;
	}
	return r;
}

export { classify_bypass, bypass_split, load_config, ordered_nodes, node_by_id, node_chain, gen_xray, gen_nft, gen_lockdown, parse_vars };
