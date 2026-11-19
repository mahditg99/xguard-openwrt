'use strict';

// CLI used by xguardd and the init script.
//   gen.uc xray <node-id>     print xray config for that node
//   gen.uc nft                print nftables ruleset (nothing if disabled)
//   gen.uc order              print enabled node ids, preferred first
//   gen.uc nodeinfo <node-id> print: type|name|host|port|user|password|keyfile (for ssh nodes)
//   gen.uc vars               read /debug/vars json on stdin, print: known alive delay up down
//   gen.uc get <key> [def]    print a main option
//   gen.uc ifaces             print vpn interface names (for sysctl/ipv6 handling)
//   gen.uc sources            print xray download sources, one per line

import { load_config, ordered_nodes, node_by_id, gen_xray, gen_nft, gen_lockdown, parse_vars, bypass_split, local_dns } from './core.uc';
import { stdin } from 'fs';

function out(s) {
	print(s);
}

let cmd = ARGV[0];
let cfg = load_config();

switch (cmd) {
case 'xray': {
	let n = node_by_id(cfg, ARGV[1]);
	if (!n)
		die('unknown or disabled node: ' + ARGV[1]);
	out(gen_xray(cfg, n) + '\n');
	break;
}
case 'nft': {
	let t = gen_nft(cfg);
	if (t)
		out(t);
	break;
}
case 'lockdown': {
	let t = gen_lockdown(cfg);
	if (t)
		out(t);
	break;
}
case 'order':
	for (let n in ordered_nodes(cfg))
		out(n['.name'] + '\n');
	break;
case 'nodeinfo': {
	let n = node_by_id(cfg, ARGV[1]);
	if (!n)
		die('unknown node');
	out(join('|', [ n.type || 'link', n.name || n['.name'], n.host || '', n.port || '22', n.user || 'root', n.password || '', n.keyfile || '' ]) + '\n');
	break;
}
case 'vars': {
	let r = parse_vars(stdin.read('all'));
	out(sprintf('%d %d %d %d %d\n', r.known ? 1 : 0, r.alive ? 1 : 0, r.delay, r.up, r.down));
	break;
}
case 'get': {
	let v = cfg.main[ARGV[1]];
	if (type(v) == 'bool')
		v = v ? '1' : '0';
	out((v == null || v === '' ? (ARGV[2] || '') : v) + '\n');
	break;
}
case 'ifaces':
	for (let i in cfg.ifaces)
		if (i.mode == 'vpn' || i.mode == 'block')
			out(i.name + '\n');
	break;
case 'bypassdns': {
	// line 1: resolver used outside the tunnel; then one domain per line (domain:/full: entries; keyword: cannot be a dnsmasq rule)
	let bp = bypass_split(cfg.bypass);
	let dns = trim(cfg.main.dns_bypass || '');
	out((dns != '' ? dns : local_dns(cfg.main)) + '\n');
	for (let d in bp.domains) {
		let m = match(d, /^(domain|full):(.+)$/);
		if (m)
			out(m[2] + '\n');
	}
	break;
}
case 'sources':
	for (let s in (type(cfg.main.source) == 'array' ? cfg.main.source : (cfg.main.source ? [ cfg.main.source ] : [])))
		out(s + '\n');
	break;
default:
	die('usage: gen.uc xray|nft|lockdown|order|nodeinfo|vars|get|ifaces|sources|bypassdns');
}
