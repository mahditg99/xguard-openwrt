'use strict';

// xguard accounting library: per-client / per-site traffic, daily quotas, persistence.
//
// The kernel does the counting (nft sets pair_w/pair_v/cli_w/cli_v and the counter/quota objects, see core.uc).
// This library, run every few seconds by xguardd through acct.uc, turns those cumulative counters into per-day
// statistics:
//   * deltas of the dynamic sets (no "reset" is used: set-element resets are unreliable on 32-bit MIPS)
//   * remote IP -> site name from dnsmasq's query log (--log-queries=extra), so the report names sites, not IPs
//   * usage of quota users = absolute value of their named counters (re-seeded into the ruleset after every reload)
//   * a day file on flash (gzip) every few minutes and at shutdown, so a reboot does not lose the day's numbers
//
// Everything is overridable through the environment for the sandbox tests:
//   XGUARD_RUN XGUARD_ETC XGUARD_NFT XGUARD_TABLE XGUARD_NOW XGUARD_DNSLOG

import { open, popen, readfile, writefile, rename, unlink, stat, mkdir, lsdir } from 'fs';
import { load_config, gen_nft, quota_targets, num } from './core.uc';

const RUN = getenv('XGUARD_RUN') || '/tmp/xguard';
const ETC = getenv('XGUARD_ETC') || '/etc/xguard';
const NFT = getenv('XGUARD_NFT') || 'nft';
const TBL = getenv('XGUARD_TABLE') || 'xguard';	// tests load a renamed copy of the ruleset next to the live one
const AD = RUN + '/acct';			// RAM
const FD = ETC + '/acct';			// flash
const DNSLOG = getenv('XGUARD_DNSLOG') || RUN + '/dns.log';
const MAX_SITES = 200;
const MAX_CLIENTS = 128;

function now() {
	let n = getenv('XGUARD_NOW');
	return n ? int(n) : time();
}

function mget(m, k, def) {
	let v = m[k];
	return (v == null || v === '') ? def : v;
}

function ensure_dirs() {
	mkdir(RUN);
	mkdir(AD);
}

// ------------------------------------------------------------------ time / day

// 'YYYYMMDD' of the accounting day that contains ts: local time = UTC + tz_offset (minutes, default Tehran +03:30),
// the day starts at reset_time (HH:MM, default 00:00)
function day_params(main) {
	let off = int(mget(main, 'tz_offset', '210'));
	if (off == null || off != off)
		off = 210;
	let rm = 0;
	let t = match('' + mget(main, 'reset_time', '00:00'), /^([0-9]{1,2}):([0-9]{2})$/);
	if (t)
		rm = int(t[1]) * 60 + int(t[2]);
	if (rm >= 1440)
		rm = 0;
	return { off: off, rm: rm };
}

function day_of(ts, p) {
	let g = gmtime(ts + (p.off - p.rm) * 60);
	return sprintf('%04d%02d%02d', g.year, g.mon, g.mday);
}

// epoch of the next daily reset after ts
function next_reset(ts, p) {
	let local = ts + p.off * 60;
	let secs = local % 86400;
	let d = p.rm * 60 - secs;
	if (d <= 0)
		d += 86400;
	return ts + d;
}

// ------------------------------------------------------------------ nft access

function nft_text(args) {
	let p = popen(NFT + ' ' + args + ' 2>/dev/null', 'r');
	if (!p)
		return null;
	let t = p.read('all');
	let rc = p.close();
	return (rc == 0 && t) ? t : null;
}

const UNIT = { bytes: 1, byte: 1, kbytes: 1024, mbytes: 1048576, gbytes: 1073741824 };

// "<ip> . <ip> counter packets N bytes M"
function parse_pairs(txt) {
	let r = [];
	for (let m in match(txt || '', /([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+) \. ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+) counter packets [0-9]+ bytes ([0-9]+)/g))
		push(r, [ m[1], m[2], int(m[3]) ]);
	return r;
}

function parse_clients(txt) {
	let r = [];
	for (let m in match(txt || '', /([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+) counter packets [0-9]+ bytes ([0-9]+)/g))
		push(r, [ m[1], int(m[2]) ]);
	return r;
}

// counter cw1 { packets 0 bytes 123 }  ->  { cw1: 123 }
function parse_counters(txt) {
	let r = {};
	for (let m in match(txt || '', /counter (c[wv][0-9]+) \{[^}]*bytes ([0-9]+)/g))
		r[m[1]] = int(m[2]);
	return r;
}

// quota qw1 { over 500 mbytes used 12 mbytes }  ->  { qw1: { over, used } } in bytes
function parse_quotas(txt) {
	let r = {};
	for (let m in match(txt || '', /quota (q[wv][0-9]+) \{[^}]*over ([0-9]+) ([a-z]+) used ([0-9]+) ([a-z]+)/g))
		r[m[1]] = { over: int(m[2]) * (UNIT[m[3]] || 1), used: int(m[4]) * (UNIT[m[5]] || 1) };
	return r;
}

// ---------------------------------------------------------------- site names

const SLD = { co: 1, com: 1, org: 1, net: 1, gov: 1, edu: 1, ac: 1, or: 1, ne: 1, go: 1, sch: 1, id: 1, mil: 1, info: 1, biz: 1, ltd: 1, plc: 1 };

// www.a.example.co.uk -> example.co.uk ; cdn.example.com -> example.com
function site_of_name(n) {
	let l = split(n, '.');
	let k = length(l);
	if (k <= 2)
		return n;
	if (length(l[k - 1]) == 2 && SLD[l[k - 2]])
		return join('.', slice(l, -3));
	return join('.', slice(l, -2));
}

function ip2int(ip) {
	let o = split(ip, '.');
	return int(o[0]) * 16777216 + int(o[1]) * 65536 + int(o[2]) * 256 + int(o[3]);
}

// addresses that are used without any DNS name (Telegram's MTProto servers)
const IPSITES = [
	[ '91.108.4.0', 22, 'telegram.org' ], [ '91.108.8.0', 22, 'telegram.org' ], [ '91.108.12.0', 22, 'telegram.org' ],
	[ '91.108.16.0', 22, 'telegram.org' ], [ '91.108.20.0', 22, 'telegram.org' ], [ '91.108.56.0', 22, 'telegram.org' ],
	[ '95.161.64.0', 20, 'telegram.org' ], [ '149.154.160.0', 20, 'telegram.org' ], [ '185.76.151.0', 24, 'telegram.org' ]
];

function ip_site(ip) {
	let v = ip2int(ip);
	for (let r in IPSITES) {
		let sz = 1;
		for (let i = 0; i < 32 - r[1]; i++)
			sz *= 2;
		let base = ip2int(r[0]);
		if (v >= base && v < base + sz)
			return r[2];
	}
	return ip;
}

function load_names() {
	let names = {};
	for (let line in split(readfile(AD + '/names.tsv') || '', '\n')) {
		let i = index(line, '\t');
		if (i > 0)
			names[substr(line, 0, i)] = substr(line, i + 1);
	}
	return names;
}

// reads the new part of dnsmasq's query log and appends "ip<TAB>site" lines to names.tsv
function read_dns(st) {
	let sz = stat(DNSLOG);
	if (!sz)
		return 0;
	sz = sz.size;
	let off = st.dnsoff || 0;
	if (off > sz)
		off = 0;
	if (sz - off > 1048576)
		off = sz - 1048576;
	if (sz == off)
		return 0;
	let f = open(DNSLOG, 'r');
	if (!f)
		return 0;
	f.seek(off);
	let txt = f.read(sz - off);
	f.close();
	if (!txt)
		return 0;
	// never process half a line: the rest is read next time
	let nl = rindex(txt, '\n');
	if (nl < 0)
		return 0;
	st.dnsoff = off + nl + 1;
	txt = substr(txt, 0, nl);

	let q = {};
	let nq = 0;
	let out = '';
	let count = 0;
	for (let line in split(txt, '\n')) {
		let m = match(line, / ([0-9]+) ([0-9.]+)\/[0-9]+ query\[[A-Za-z0-9]+\] ([^ ]+) from /);
		if (m) {
			if (nq > 4000) {
				q = {};
				nq = 0;
			}
			q[m[1] + '|' + m[2]] = lc(m[3]);
			nq++;
			continue;
		}
		m = match(line, / ([0-9]+) ([0-9.]+)\/[0-9]+ (reply|cached|cached-stale) ([^ ]+) is ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)$/);
		if (!m)
			continue;
		// the name the client asked for (not the CNAME target), so cdn hosts do not hide the real site
		let nm = lc(q[m[1] + '|' + m[2]] || m[4]);
		if (!match(nm, /^[a-z0-9._-]+$/) || match(nm, /\.(arpa|lan|local|localdomain)$/))
			continue;
		out += m[5] + '\t' + site_of_name(rtrim(nm, '.')) + '\n';
		count++;
	}
	if (count) {
		let nf = open(AD + '/names.tsv', 'a');
		if (nf) {
			nf.write(out);
			nf.close();
		}
		let s = stat(AD + '/names.tsv');
		if (s && s.size > 700000) {
			let lines = split(readfile(AD + '/names.tsv') || '', '\n');
			writefile(AD + '/names.tsv', join('\n', slice(lines, -8000)) + '\n');
		}
	}
	// keep the file small: dnsmasq runs in a jail (no rename + SIGUSR2 reopen) but appends (O_APPEND), so truncating is safe
	if (sz > 262144) {
		writefile(DNSLOG, '');
		st.dnsoff = 0;
	}
	return count;
}

// ------------------------------------------------------------------ state

function new_state(ts, p) {
	return { v: 1, day: day_of(ts, p), saved: ts, flashed: 0, dnsoff: 0, users: {}, clients: {} };
}

function read_gz(path) {
	if (!stat(path))
		return null;
	let p = popen("zcat '" + path + "' 2>/dev/null", 'r');
	if (!p)
		return null;
	let t = p.read('all');
	p.close();
	try {
		let j = json(t);
		return (type(j) == 'object') ? j : null;
	} catch (e) {
		return null;
	}
}

function list_days() {
	let r = [];
	for (let f in (lsdir(FD) || [])) {
		let m = match(f, /^day-([0-9]{8})\.json\.gz$/);
		if (m)
			push(r, m[1]);
	}
	return sort(r);
}

function load_state(ts, p) {
	let j;
	try {
		j = json(readfile(AD + '/today.json') || '');
	} catch (e) {
		j = null;
	}
	if (type(j) == 'object' && type(j.clients) == 'object' && type(j.users) == 'object')
		return j;
	// after a reboot: continue with the newest day file on flash
	let days = list_days();
	if (length(days)) {
		j = read_gz(FD + '/day-' + days[length(days) - 1] + '.json.gz');
		if (j && type(j.clients) == 'object' && type(j.users) == 'object') {
			j.dnsoff = 0;
			j.flashed = j.saved || 0;
			return j;
		}
	}
	return new_state(ts, p);
}

function save_ram(st) {
	ensure_dirs();
	writefile(AD + '/today.json.new', sprintf('%J', st));
	rename(AD + '/today.json.new', AD + '/today.json');
}

function save_flash(st, days_keep) {
	mkdir(ETC);
	mkdir(FD);
	let path = FD + '/day-' + st.day + '.json.gz';
	let p = popen("gzip -c > '" + path + ".new'", 'w');
	if (!p)
		return false;
	p.write(sprintf('%J', st));
	if (p.close() != 0) {
		unlink(path + '.new');
		return false;
	}
	rename(path + '.new', path);
	let days = list_days();
	while (length(days) > days_keep) {
		unlink(FD + '/day-' + days[0] + '.json.gz');
		shift(days);
	}
	st.flashed = now();
	return true;
}

// ----------------------------------------------------------------- harvest

function add_site(c, site, w, v) {
	if (!c.s[site])
		c.s[site] = [ 0, 0 ];
	c.s[site][0] += w;
	c.s[site][1] += v;
}

function trim_sites(c) {
	let ks = keys(c.s);
	if (length(ks) <= MAX_SITES + 60)
		return;
	let arr = sort(ks, (a, b) => (c.s[a][0] + c.s[a][1]) - (c.s[b][0] + c.s[b][1]));
	let drop = length(arr) - MAX_SITES;
	for (let i = 0; i < drop; i++) {
		if (arr[i] != '~other')
			add_site(c, '~other', c.s[arr[i]][0], c.s[arr[i]][1]);
		delete c.s[arr[i]];
	}
}

function client_of(st, ip) {
	let c = st.clients[ip];
	if (!c) {
		if (length(st.clients) >= MAX_CLIENTS)
			ip = '~other';
		c = st.clients[ip] = { w: 0, v: 0, s: {} };
	}
	return c;
}

// dynamic sets -> deltas -> per-client / per-site bytes
function collect_sets(st) {
	let prev = {};
	for (let line in split(readfile(AD + '/prev.tsv') || '', '\n')) {
		let i = index(line, ' ');
		if (i > 0)
			prev[substr(line, 0, i)] = int(substr(line, i + 1));
	}
	let cur = '';
	let names = null;
	let got = false;
	let delta = (k, b) => {
		let d = b - (prev[k] || 0);
		if (d < 0)		// element was re-created
			d = b;
		return d;
	};

	for (let cls in [ 'w', 'v' ]) {
		let txt = nft_text('list set inet ' + TBL + ' cli_' + cls);
		if (txt == null)
			continue;
		got = true;
		for (let e in parse_clients(txt)) {
			let k = 'c' + cls + ',' + e[0];
			cur += k + ' ' + e[1] + '\n';
			let d = delta(k, e[1]);
			if (d > 0)
				client_of(st, e[0])[cls] += d;
		}
		txt = nft_text('list set inet ' + TBL + ' pair_' + cls);
		if (txt == null)
			continue;
		for (let e in parse_pairs(txt)) {
			let k = 'p' + cls + ',' + e[0] + ',' + e[1];
			cur += k + ' ' + e[2] + '\n';
			let d = delta(k, e[2]);
			if (d <= 0)
				continue;
			if (names == null)
				names = load_names();
			let site = names[e[1]] || ip_site(e[1]);
			let c = client_of(st, e[0]);
			add_site(c, site, cls == 'w' ? d : 0, cls == 'v' ? d : 0);
		}
	}
	if (got)
		writefile(AD + '/prev.tsv', cur);
	for (let ip in keys(st.clients))
		trim_sites(st.clients[ip]);
	return got;
}

function read_map() {
	try {
		let j = json(readfile(AD + '/map.json') || '');
		if (type(j) == 'array')
			return j;
	} catch (e) {}
	return null;
}

// named counters/quotas -> usage + "throttled" flags of the quota users
function collect_users(st, cfg) {
	let ctr = parse_counters(nft_text('list counters table inet ' + TBL));
	let qta = parse_quotas(nft_text('list quotas table inet ' + TBL));
	let map = read_map();
	if (map == null) {
		map = [];
		for (let q in quota_targets(cfg))
			push(map, { idx: q.idx, key: q.key, name: q.name });
	}
	for (let q in map) {
		let u = st.users[q.key];
		if (!u)
			u = st.users[q.key] = { name: q.name, w: 0, v: 0, tw: 0, tv: 0 };
		u.name = q.name;
		for (let c in [ 'w', 'v' ]) {
			let b = ctr['c' + c + q.idx];
			if (b != null && b > u[c])
				u[c] = b;
			let qq = qta['q' + c + q.idx];
			if (qq)
				u['t' + c] = (qq.used >= qq.over) ? 1 : 0;
		}
	}
}

function write_map(qs) {
	ensure_dirs();
	let m = [];
	for (let q in qs)
		push(m, { idx: q.idx, key: q.key, name: q.name });
	writefile(AD + '/map.json', sprintf('%J', m));
}

// seeds for gen_nft(): today's usage, from RAM or (after a reboot) from the newest day file
function seeds() {
	let cfg = load_config();
	let p = day_params(cfg.main);
	let st = load_state(now(), p);
	return { users: st.users };
}

// load (generate + nft -f) the ruleset with the current usage seeded into the counters/quotas
function reload_rules(cfg, st) {
	let txt = gen_nft(cfg, { users: st.users });
	if (!txt)
		return false;
	ensure_dirs();
	write_map(quota_targets(cfg));
	if (TBL != 'xguard')
		txt = replace(txt, 'table inet xguard', 'table inet ' + TBL);
	writefile(AD + '/reload.nft', txt);
	let rc = system(NFT + " -f '" + AD + "/reload.nft' 2>" + RUN + '/acct.nft.err');
	unlink(AD + '/prev.tsv');		// the new sets start from zero
	return rc == 0;
}

// one pass; force = write the day file to flash now; returns the state
function harvest(force) {
	ensure_dirs();
	let cfg = load_config();
	let p = day_params(cfg.main);
	let ts = now();
	let st = load_state(ts, p);
	let keep = int(mget(cfg.main, 'acct_days', '7'));
	if (keep == null || keep != keep || keep < 1)
		keep = 7;
	let every = int(mget(cfg.main, 'acct_save', '600'));
	if (every == null || every != every || every < 60)
		every = 600;

	let live = cfg.main.enabled && (mget(cfg.main, 'accounting', '1') == '1');
	if (live) {
		read_dns(st);
		collect_sets(st);
		collect_users(st, cfg);
	}

	let today = day_of(ts, p);
	// a clock that is behind the last saved time (no RTC, not yet corrected) must not start a new day
	if (st.day != today && ts >= st.saved) {
		save_flash(st, keep);			// close the finished day
		let users = {};
		for (let k in keys(st.users))
			users[k] = { name: st.users[k].name, w: 0, v: 0, tw: 0, tv: 0 };
		st = new_state(ts, p);
		st.users = users;
		if (live)
			reload_rules(cfg, st);		// counters and quotas start from zero
		save_flash(st, keep);
	} else if (ts >= st.saved)
		st.saved = ts;

	if (live && (force || ts - (st.flashed || 0) >= every))
		save_flash(st, keep);
	save_ram(st);
	return st;
}

// zero the usage of one quota user ('all' = everybody) and re-seed the ruleset
function reset_user(key) {
	let cfg = load_config();
	let p = day_params(cfg.main);
	harvest(false);
	let st = load_state(now(), p);
	let hit = 0;
	for (let k in keys(st.users)) {
		if (key == 'all' || k == key) {
			st.users[k].w = 0;
			st.users[k].v = 0;
			st.users[k].tw = 0;
			st.users[k].tv = 0;
			hit++;
		}
	}
	save_ram(st);
	if (cfg.main.enabled)
		reload_rules(cfg, st);
	return hit;
}

// forget the reports (flash day files and today's per-site numbers); quota usage is kept
function clear_stats() {
	let cfg = load_config();
	let p = day_params(cfg.main);
	let st = load_state(now(), p);
	for (let d in list_days())
		unlink(FD + '/day-' + d + '.json.gz');
	st.clients = {};
	unlink(AD + '/prev.tsv');
	unlink(AD + '/names.tsv');
	save_ram(st);
	if (cfg.main.enabled)
		save_flash(st, 1);
}

// --------------------------------------------------------------- reporting

// for the web UI: today's state plus the configured allowances
function report(day) {
	let cfg = load_config();
	let p = day_params(cfg.main);
	let ts = now();
	let st;
	if (day && day != day_of(ts, p)) {
		st = read_gz(FD + '/day-' + day + '.json.gz');
		if (!st)
			return { error: 'no data for ' + day };
	} else
		st = load_state(ts, p);
	let lim = {};
	for (let q in quota_targets(cfg))
		lim[q.key] = q;
	let users = [];
	for (let k in keys(st.users)) {
		let u = st.users[k];
		let l = lim[k] || {};
		push(users, {
			key: k, name: u.name || k, w: u.w, v: u.v, tw: u.tw ? true : false, tv: u.tv ? true : false,
			w_mb: l.w_mb || 0, w_kbps: (l.w_kbps == null ? 0 : l.w_kbps), v_mb: l.v_mb || 0, v_kbps: (l.v_kbps == null ? 0 : l.v_kbps)
		});
	}
	// keep the answer small: top sites per client, the tail is folded into ~other
	let clients = {};
	for (let ip in keys(st.clients)) {
		let c = st.clients[ip];
		let ks = sort(keys(c.s || {}), (a, b) => (c.s[b][0] + c.s[b][1]) - (c.s[a][0] + c.s[a][1]));
		let s = {};
		let i = 0;
		for (let k in ks) {
			if (i++ < 80 || k == '~other')
				s[k] = c.s[k];
			else {
				if (!s['~other'])
					s['~other'] = [ 0, 0 ];
				s['~other'][0] += c.s[k][0];
				s['~other'][1] += c.s[k][1];
			}
		}
		clients[ip] = { w: c.w, v: c.v, s: s };
	}
	return {
		day: st.day, today: day_of(ts, p), saved: st.saved, next_reset: next_reset(ts, p),
		accounting: cfg.main.enabled && (mget(cfg.main, 'accounting', '1') == '1'),
		tz_offset: p.off, reset_time: mget(cfg.main, 'reset_time', '00:00'),
		days: list_days(), users: users, clients: clients, time: ts
	};
}

export { RUN, ETC, now, day_params, day_of, next_reset, parse_pairs, parse_clients, parse_counters, parse_quotas,
	site_of_name, ip_site, load_state, save_ram, save_flash, list_days, harvest, reset_user, clear_stats, report,
	seeds, write_map, reload_rules, read_dns, collect_sets, read_gz };
