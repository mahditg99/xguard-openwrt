'use strict';

// rpcd plugin: ubus object "xguard" used by the web UI (/www/xguard) via uhttpd's /ubus endpoint.
// Authentication/ACL is handled by rpcd (root login, see /usr/share/rpcd/acl.d/xguard.json).

import { cursor } from 'uci';
import { readfile, writefile, lsdir, stat, popen } from 'fs';
import { parse_link } from '/usr/lib/xguard/links.uc';
import { load_config, classify_bypass } from '/usr/lib/xguard/core.uc';

const RUN = '/tmp/xguard';

function cur() {
	let dir = getenv('XGUARD_CONFDIR');	// test hook
	return dir ? cursor(dir, dir + '/.save') : cursor();
}
const MAIN_KEYS = [
	'enabled', 'node', 'log_level', 'dns_remote', 'probe_url', 'probe_interval', 'fail_threshold',
	'mem_limit', 'rss_kill', 'sniffing', 'block_quic', 'dns_bypass', 'default_mode'
];
const MAIN_LISTS = [ 'source', 'wan_if' ];
const NODE_TYPES = [ 'link', 'json', 'ssh' ];
const IFACE_MODES = [ 'vpn', 'direct', 'block' ];

function kv(path) {
	let r = {};
	for (let line in split(readfile(path) || '', '\n')) {
		let i = index(line, '=');
		if (i > 0)
			r[substr(line, 0, i)] = substr(line, i + 1);
	}
	return r;
}

function num(v) {
	let n = int(v);
	return (type(n) == 'double' && n != n) ? 0 : n;
}

function meminfo() {
	let r = {};
	for (let line in split(readfile('/proc/meminfo') || '', '\n')) {
		let f = match(line, /^([A-Za-z_()]+):\s+([0-9]+)/);
		if (f)
			r[f[1]] = num(f[2]);
	}
	return r;
}

function status() {
	let st = kv(RUN + '/state');
	let mi = meminfo();
	let cfg = load_config();
	let nodes = [];
	for (let n in cfg.nodes)
		push(nodes, { id: n['.name'], name: n.name || n['.name'], type: n.type || 'link' });
	let xray = stat(RUN + '/xray');
	if (xray) {
		// the state file is stale while the supervisor is idle, so ask the binary itself
		let p = popen(RUN + '/xray version 2>/dev/null | head -n1');
		if (p) {
			let v = trim(p.read('all') || '');
			p.close();
			if (v != '')
				st.xray_version = v;
		}
	}
	return {
		state: st,
		running: (st.status != null && st.status != 'disabled'),
		enabled: cfg.main.enabled,
		preferred: cfg.main.node || '',
		nodes: nodes,
		xray_present: (xray != null),
		xray_size: xray ? xray.size : 0,
		mem_total_kb: mi.MemTotal || 0,
		mem_avail_kb: mi.MemAvailable || 0,
		swap_total_kb: mi.SwapTotal || 0,
		swap_free_kb: mi.SwapFree || 0,
		tmp_used_kb: 0,
		loadavg: trim(readfile('/proc/loadavg') || ''),
		time: time()
	};
}

function get_config() {
	let c = cur();
	let out = { main: {}, nodes: [], ifaces: [], devices: [], bypass: [], limits: [] };
	c.foreach('xguard', 'main', (s) => {
		for (let k in MAIN_KEYS)
			if (s[k] != null)
				out.main[k] = s[k];
		for (let k in MAIN_LISTS)
			out.main[k] = (type(s[k]) == 'array') ? s[k] : (s[k] ? [ s[k] ] : []);
	});
	c.foreach('xguard', 'node', (s) => {
		push(out.nodes, {
			id: s['.name'], name: s.name || '', type: s.type || 'link', enabled: s.enabled != '0',
			link: s.link || '', json: s.json || '', host: s.host || '', port: s.port || '22',
			user: s.user || 'root', password: s.password || ''
		});
	});
	c.foreach('xguard', 'iface', (s) => { push(out.ifaces, { name: s.name, mode: s.mode }); });
	c.foreach('xguard', 'device', (s) => { push(out.devices, { mac: s.mac || '', ip: s.ip || '', mode: s.mode || 'direct' }); });
	c.foreach('xguard', 'bypass', (s) => {
		for (let x in (type(s.cidr) == 'array' ? s.cidr : (s.cidr ? [ s.cidr ] : [])))
			push(out.bypass, x);
	});
	c.foreach('xguard', 'limit', (s) => {
		push(out.limits, { name: s.name || '', ip: s.ip || '', mac: s.mac || '', iface: s.iface || '', down: s.down || '0', up: s.up || '0' });
	});
	return out;
}

function clean_sections(c, typ) {
	let ids = [];
	c.foreach('xguard', typ, (s) => { push(ids, s['.name']); });
	for (let id in ids)
		c.delete('xguard', id);
}

function validate_node(n) {
	let t = n.type || 'link';
	if (!(t in NODE_TYPES))
		die('node type must be link, json or ssh');
	if (t == 'link') {
		let r = parse_link(n.link || '');
		return r.name;
	}
	if (t == 'json') {
		let j = json(n.json || '');
		if (type(j) != 'object' && type(j) != 'array')
			die('json node must be an xray outbound object or an array of them');
	}
	if (t == 'ssh' && (!n.host || !n.user))
		die('ssh node needs host and user');
	return null;
}

function save_config(req) {
	let d = req.args.config;
	if (type(d) != 'object')
		return { error: 'config object required' };

	try {
		// validate everything first, write afterwards
		for (let n in (d.nodes || [])) {
			try { validate_node(n); }
			catch (e) { die(sprintf('node "%s": %s', n.name || n.id || '?', e)); }
		}
		for (let i in (d.ifaces || []))
			if (!match(i.name || '', /^[A-Za-z0-9_.@:+-]{1,15}$/) || !(i.mode in IFACE_MODES))
				die('bad interface entry: ' + i.name);
		for (let v in (d.devices || []))
			if (!match(v.mac || '', /^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$/) && !match(v.ip || '', /^[0-9.]+(\/[0-9]+)?$/))
				die('device needs a valid mac or ip');
		for (let b in (d.bypass || []))
			if (!classify_bypass(b))
				die('bad bypass entry: ' + b + ' (IPv4/CIDR or a domain such as example.com)');
		if (d.main && d.main.default_mode && !(d.main.default_mode in [ 'vpn', 'direct' ]))
			die('default_mode must be vpn or direct');
		if (d.main && d.main.dns_bypass && !match(trim('' + d.main.dns_bypass), /^[A-Za-z0-9.:\/_-]+$/))
			die('bad dns_bypass: ' + d.main.dns_bypass);

		let c = cur();
		if (!c.get('xguard', 'main'))
			c.set('xguard', 'main', 'main');

		for (let k in MAIN_KEYS)
			if (d.main && d.main[k] != null)
				c.set('xguard', 'main', k, '' + d.main[k]);
		for (let k in MAIN_LISTS) {
			if (d.main && type(d.main[k]) == 'array') {
				if (length(d.main[k]))
					c.set('xguard', 'main', k, filter(d.main[k], (x) => x != ''));
				else
					c.delete('xguard', 'main', k);
			}
		}

		if (d.nodes != null) {
			clean_sections(c, 'node');
			let n_i = 0;
			for (let n in d.nodes) {
				let id = match(n.id || '', /^[A-Za-z0-9_]+$/) ? n.id : sprintf('n%d_%d', time(), n_i++);
				c.set('xguard', id, 'node');
				c.set('xguard', id, 'type', n.type || 'link');
				c.set('xguard', id, 'enabled', (n.enabled === false) ? '0' : '1');
				let nm = n.name;
				if (!nm && (n.type || 'link') == 'link') {
					try { nm = parse_link(n.link).name; } catch (e) {}
				}
				c.set('xguard', id, 'name', nm || id);
				for (let k in [ 'link', 'json', 'host', 'port', 'user', 'password' ])
					if (n[k] != null && n[k] !== '')
						c.set('xguard', id, k, '' + n[k]);
			}
		}
		if (d.ifaces != null) {
			clean_sections(c, 'iface');
			for (let i in d.ifaces) {
				let id = c.add('xguard', 'iface');
				c.set('xguard', id, 'name', i.name);
				c.set('xguard', id, 'mode', i.mode);
			}
		}
		if (d.devices != null) {
			clean_sections(c, 'device');
			for (let v in d.devices) {
				let id = c.add('xguard', 'device');
				if (v.mac)
					c.set('xguard', id, 'mac', lc(v.mac));
				else
					c.set('xguard', id, 'ip', v.ip);
				c.set('xguard', id, 'mode', v.mode == 'vpn' ? 'vpn' : 'direct');
			}
		}
		if (d.bypass != null) {
			clean_sections(c, 'bypass');
			if (length(d.bypass)) {
				let id = c.add('xguard', 'bypass');
				c.set('xguard', id, 'cidr', d.bypass);
			}
		}
		if (d.limits != null) {
			clean_sections(c, 'limit');
			for (let l in d.limits) {
				let id = c.add('xguard', 'limit');
				for (let k in [ 'name', 'ip', 'mac', 'iface', 'down', 'up' ])
					if (l[k] != null && l[k] !== '')
						c.set('xguard', id, k, '' + l[k]);
			}
		}
		c.save('xguard');
		c.commit('xguard');
	} catch (e) {
		return { error: '' + e };
	}
	return { ok: true };
}

function sh_read(path, lines) {
	let t = readfile(path) || '';
	let a = split(t, '\n');
	return join('\n', slice(a, -lines));
}

const methods = {
	status: {
		call: function() {
			return status();
		}
	},
	get_config: {
		call: function() {
			return get_config();
		}
	},
	save_config: {
		args: { config: {} },
		call: function(req) {
			return save_config(req);
		}
	},
	command: {
		args: { cmd: 'restart' },
		call: function(req) {
			if (!(req.args.cmd in [ 'restart', 'next', 'update-xray' ]))
				return { error: 'unknown command' };
			writefile(RUN + '/cmd', req.args.cmd);
			return { ok: true };
		}
	},
	test_link: {
		args: { link: '' },
		call: function(req) {
			try {
				let r = parse_link(req.args.link);
				return { ok: true, name: r.name, protocol: r.outbound.protocol,
					address: r.outbound.settings.address, port: r.outbound.settings.port,
					network: r.outbound.streamSettings ? r.outbound.streamSettings.network : 'tcp',
					security: r.outbound.streamSettings ? (r.outbound.streamSettings.security || 'none') : 'none' };
			} catch (e) {
				return { error: '' + e };
			}
		}
	},
	// turn a share link into the equivalent raw xray outbound (to edit fragment, fingerprint, mtu, ...)
	link_to_json: {
		args: { link: '' },
		call: function(req) {
			try {
				let r = parse_link(req.args.link);
				delete r.outbound.__warning;
				return { ok: true, name: r.name, json: sprintf('%.2J', r.outbound) };
			} catch (e) {
				return { error: '' + e };
			}
		}
	},
	logs: {
		call: function() {
			return {
				xguardd: sh_read(RUN + '/xguardd.log', 60),
				xray: sh_read(RUN + '/xray.log', 60),
				ssh: sh_read(RUN + '/ssh.err', 20)
			};
		}
	},
	devices: {
		call: function() {
			let nets = [];
			for (let n in (lsdir('/sys/class/net') || []))
				if (n != 'lo' && !match(n, /^(ifb|ip6|sit|gre|erspan|bonding)/))
					push(nets, n);
			let leases = [];
			for (let line in split(readfile('/tmp/dhcp.leases') || '', '\n')) {
				let f = split(line, ' ');
				if (length(f) >= 4)
					push(leases, { mac: f[1], ip: f[2], name: f[3] });
			}
			return { interfaces: nets, leases: leases };
		}
	}
};

return { xguard: methods };
