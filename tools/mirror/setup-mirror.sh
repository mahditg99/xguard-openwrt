#!/bin/sh
# Run as root on YOUR server (optional): turns it into a private xray mirror for the router.
#
#   ./setup-mirror.sh "<router public key>"        (get it on the router: xguardctl genkey)
#   then copy dist/xray.gz and dist/xray.gz.sha256 to /srv/xguard/
#   and on the router add:   list source 'ssh://xguard-mirror@YOUR_SERVER/xray.gz'
#
# Creates a locked-down user "xguard-mirror"; its key can run only serve.sh (read two files).
set -eu
PUB="${1:?usage: setup-mirror.sh \"<ssh public key line>\"}"

id xguard-mirror >/dev/null 2>&1 || useradd -r -m -d /srv/xguard -s /bin/sh xguard-mirror
mkdir -p /srv/xguard/.ssh
cp "$(dirname "$0")/serve.sh" /srv/xguard/serve.sh
chmod 755 /srv/xguard/serve.sh
printf 'restrict,command="/srv/xguard/serve.sh" %s\n' "$PUB" > /srv/xguard/.ssh/authorized_keys
chown -R xguard-mirror: /srv/xguard/.ssh
chmod 700 /srv/xguard/.ssh
chmod 600 /srv/xguard/.ssh/authorized_keys
chown root:root /srv/xguard/serve.sh
echo "mirror ready: put xray.gz and xray.gz.sha256 into /srv/xguard/"
