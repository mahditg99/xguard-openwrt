'use strict';

// Share-link (vless:// vmess:// trojan:// ss:// socks://) -> xray outbound converter.
// Pure functions, no I/O.

function d(v, def) {
	return (v == null || v === '') ? def : v;
}

function urldecode(s) {
	if (s == null)
		return '';
	return replace(s, /%([0-9a-fA-F]{2})/g, (m, h) => chr(hex(h)));
}

function b64(s) {
	s = replace(replace(replace(s, /-/g, '+'), /_/g, '/'), /[\r\n ]/g, '');
	while (length(s) % 4)
		s += '=';
	return b64dec(s);
}

function parse_query(q) {
	let r = {};
	for (let kv in split(q, '&')) {
		if (kv == '')
			continue;
		let i = index(kv, '=');
		if (i < 0)
			r[urldecode(kv)] = '';
		else
			r[urldecode(substr(kv, 0, i))] = urldecode(replace(substr(kv, i + 1), /\+/g, ' '));
	}
	return r;
}

// userinfo@host:port?query#fragment
function parse_url(s) {
	let r = { query: {}, user: null, host: '', port: 0, frag: '' };
	let i = index(s, '#');
	if (i >= 0) {
		r.frag = urldecode(substr(s, i + 1));
		s = substr(s, 0, i);
	}
	i = index(s, '?');
	if (i >= 0) {
		r.query = parse_query(substr(s, i + 1));
		s = substr(s, 0, i);
	}
	i = rindex(s, '@');
	if (i >= 0) {
		r.user = substr(s, 0, i);
		s = substr(s, i + 1);
	}
	let m = match(s, /^\[([^\]]+)\]:?([0-9]*)/);
	if (!m)
		m = match(s, /^([^:\/]+):?([0-9]*)/);
	if (!m)
		die('cannot parse host/port');
	r.host = m[1];
	r.port = (m[2] != '') ? int(m[2]) : 0;
	return r;
}

function csv(v) {
	return v ? filter(split(v, ','), (x) => x != '') : null;
}

// Build xray streamSettings from a flat parameter set (as used in share links).
function stream(p) {
	let net = lc(d(p.type, 'tcp'));
	let sec = lc(d(p.security, 'none'));
	let host = d(p.host, null);
	let path = d(p.path, null);
	let s = {};

	if (net == 'h2' || net == 'http')
		net = 'xhttp';
	s.network = net;

	switch (net) {
	case 'ws':
		s.wsSettings = { path: d(path, '/') };
		if (host)
			s.wsSettings.host = host;
		break;
	case 'httpupgrade':
		s.httpupgradeSettings = { path: d(path, '/') };
		if (host)
			s.httpupgradeSettings.host = host;
		break;
	case 'xhttp':
	case 'splithttp':
		s.network = 'xhttp';
		s.xhttpSettings = { path: d(path, '/') };
		if (host)
			s.xhttpSettings.host = host;
		if (p.mode)
			s.xhttpSettings.mode = p.mode;
		if (p.extra) {
			try { s.xhttpSettings.extra = json(p.extra); } catch (e) {}
		}
		break;
	case 'grpc':
		s.grpcSettings = { serviceName: d(p.serviceName, d(path, '')), multiMode: (p.mode == 'multi') };
		if (p.authority)
			s.grpcSettings.authority = p.authority;
		break;
	case 'kcp':
	case 'mkcp':
		s.network = 'kcp';
		s.kcpSettings = { header: { type: d(p.headerType, 'none') } };
		if (p.seed)
			s.kcpSettings.seed = p.seed;
		break;
	case 'tcp':
	case 'raw':
		s.network = 'tcp';
		if (p.headerType == 'http') {
			s.tcpSettings = { header: { type: 'http', request: {
				path: [ d(path, '/') ],
				headers: { Host: csv(d(host, '')) || [] }
			} } };
		}
		break;
	}

	if (sec == 'tls') {
		s.security = 'tls';
		s.tlsSettings = { serverName: d(p.sni, d(host, null)), fingerprint: d(p.fp, 'chrome') };
		let alpn = csv(p.alpn);
		if (alpn)
			s.tlsSettings.alpn = alpn;
		if (p.allowInsecure == '1' || p.insecure == '1')
			s.tlsSettings.allowInsecure = true;
		if (!s.tlsSettings.serverName)
			delete s.tlsSettings.serverName;
	} else if (sec == 'reality') {
		s.security = 'reality';
		s.realitySettings = {
			serverName: d(p.sni, ''),
			fingerprint: d(p.fp, 'chrome'),
			publicKey: d(p.pbk, ''),
			shortId: d(p.sid, ''),
			spiderX: d(p.spx, '')
		};
	}

	return s;
}

function parse_vless(u) {
	let p = u.query;
	let st = stream(p);
	return {
		protocol: 'vless',
		settings: {
			address: u.host,
			port: u.port,
			id: urldecode(u.user),
			encryption: d(p.encryption, 'none'),
			flow: d(p.flow, '')
		},
		streamSettings: st
	};
}

function parse_vmess(rest) {
	let j = json(b64(rest));
	let p = {
		type: d(j.net, 'tcp'), host: j.host, path: j.path, sni: j.sni, fp: j.fp, alpn: j.alpn,
		security: (j.tls == 'tls' || j.tls == '1') ? 'tls' : 'none',
		headerType: j.type, serviceName: j.path, mode: j.mode
	};
	return {
		name: j.ps,
		outbound: {
			protocol: 'vmess',
			settings: {
				address: j.add,
				port: int(j.port),
				id: j.id,
				security: d(j.scy, 'auto')
			},
			streamSettings: stream(p)
		}
	};
}

function parse_trojan(u) {
	let p = u.query;
	if (!p.security)
		p.security = 'tls';
	return {
		protocol: 'trojan',
		settings: { address: u.host, port: u.port, password: urldecode(u.user), flow: d(p.flow, '') },
		streamSettings: stream(p)
	};
}

function parse_ss(rest) {
	// ss://BASE64(method:password)@host:port?plugin=...#name   (SIP002)
	// ss://BASE64(method:password@host:port)#name              (legacy)
	// ss://method:password@host:port#name                      (plain)
	let frag = '';
	let i = index(rest, '#');
	if (i >= 0) {
		frag = urldecode(substr(rest, i + 1));
		rest = substr(rest, 0, i);
	}
	let q = {};
	i = index(rest, '?');
	if (i >= 0) {
		q = parse_query(substr(rest, i + 1));
		rest = substr(rest, 0, i);
	}
	let userinfo, hostport;
	i = rindex(rest, '@');
	if (i >= 0) {
		userinfo = substr(rest, 0, i);
		hostport = substr(rest, i + 1);
		if (index(userinfo, ':') < 0)
			userinfo = b64(userinfo);
		else
			userinfo = urldecode(userinfo);
	} else {
		let dec = b64(rest);
		let k = rindex(dec, '@');
		if (k < 0)
			die('bad ss link');
		userinfo = substr(dec, 0, k);
		hostport = substr(dec, k + 1);
	}
	let c = index(userinfo, ':');
	let hp = parse_url(hostport);
	let ob = {
		protocol: 'shadowsocks',
		settings: { address: hp.host, port: hp.port, method: substr(userinfo, 0, c), password: substr(userinfo, c + 1) }
	};
	if (q.plugin)
		ob.__warning = 'ss plugin ignored: ' + q.plugin;
	return { name: frag, outbound: ob };
}

function parse_socks(u) {
	let ob = { protocol: 'socks', settings: { address: u.host, port: u.port } };
	if (u.user != null) {
		let a = split(urldecode(u.user), ':', 2);
		ob.settings.user = a[0];
		ob.settings.pass = a[1] || '';
	}
	return ob;
}

// -> { name, outbound }  (dies with a message on unsupported/invalid input)
function parse_link(link) {
	link = trim(link);
	let m = match(link, /^([A-Za-z0-9]+):\/\/(.*)$/);
	if (!m)
		die('not a share link');
	let scheme = lc(m[1]);
	let rest = m[2];

	switch (scheme) {
	case 'vmess':
		return parse_vmess(rest);
	case 'ss':
		return parse_ss(rest);
	case 'vless': {
		let u = parse_url(rest);
		return { name: u.frag, outbound: parse_vless(u) };
	}
	case 'trojan': {
		let u = parse_url(rest);
		return { name: u.frag, outbound: parse_trojan(u) };
	}
	case 'socks':
	case 'socks5': {
		let u = parse_url(rest);
		return { name: u.frag, outbound: parse_socks(u) };
	}
	}
	die('unsupported scheme: ' + scheme + ' (use a raw xray JSON node instead)');
}

export { parse_link };
