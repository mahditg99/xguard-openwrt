#!/bin/sh
# Run as root on YOUR server: serves xray.gz over HTTPS on a dedicated port, with a self-signed
# certificate that the router pins (use this when SSH to the server is filtered on your network).
#
#   ./setup-https-mirror.sh <server-ip-or-name> [port]        (default port 8444; pick a free one)
#   then put xray.gz, xray.gz.sha256 (and xray.version) into /srv/xguard/pub/
#   copy /srv/xguard/tls/cert.pem to the router as /etc/xguard/pin/<server-ip-or-name>.crt
#   and on the router add:   list source 'https://<server>:<port>/xray.gz'
set -eu
HOST="${1:?usage: setup-https-mirror.sh <server-ip-or-name> [port]}"
PORT="${2:-8444}"
HERE="$(cd "$(dirname "$0")" && pwd)"

id xguard-mirror >/dev/null 2>&1 || useradd -r -m -d /srv/xguard -s /usr/sbin/nologin xguard-mirror
mkdir -p /srv/xguard/pub /srv/xguard/tls
install -m 755 "$HERE/serve_https.py" /srv/xguard/serve_https.py

if [ ! -s /srv/xguard/tls/key.pem ]; then
	case "$HOST" in
		*[!0-9.]*) SAN="DNS:$HOST" ;;
		*)         SAN="DNS:$HOST,IP:$HOST" ;;
	esac
	openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 3650 \
		-subj "/CN=$HOST" -addext "subjectAltName=$SAN" \
		-keyout /srv/xguard/tls/key.pem -out /srv/xguard/tls/cert.pem 2>/dev/null
fi
chown -R root:xguard-mirror /srv/xguard/tls
chmod 750 /srv/xguard/tls
chmod 640 /srv/xguard/tls/key.pem
chmod 644 /srv/xguard/tls/cert.pem

cat > /etc/systemd/system/xguard-mirror.service <<UNIT
[Unit]
Description=xguard xray mirror (read-only HTTPS, 3 files)
After=network-online.target

[Service]
User=xguard-mirror
ExecStart=/usr/bin/python3 /srv/xguard/serve_https.py $PORT /srv/xguard/pub /srv/xguard/tls/cert.pem /srv/xguard/tls/key.pem
Restart=always
RestartSec=3
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ReadOnlyPaths=/srv/xguard

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now xguard-mirror.service
echo "mirror up on https://$HOST:$PORT/  (put the files into /srv/xguard/pub/)"
echo "certificate to pin on the router: /srv/xguard/tls/cert.pem"
