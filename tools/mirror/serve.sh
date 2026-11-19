#!/bin/sh
# Forced command for the router's mirror key: it can ONLY read xray.gz and xray.gz.sha256.
# (the router asks for "cat <path>/xray.gz"; we ignore <path> and serve from /srv/xguard)
case "$SSH_ORIGINAL_COMMAND" in
	"cat "*xray.gz.sha256) exec cat /srv/xguard/xray.gz.sha256 ;;
	"cat "*xray.gz)        exec cat /srv/xguard/xray.gz ;;
	*) echo "denied" >&2; exit 1 ;;
esac
