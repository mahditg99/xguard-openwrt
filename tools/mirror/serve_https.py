#!/usr/bin/env python3
"""Tiny read-only HTTPS file server for the router's xray mirror (no third-party modules).

Serves ONLY /xray.gz, /xray.gz.sha256 and /xray.version from the directory next to the
certificate (default /srv/xguard/pub). The router pins this server's certificate, so a
self-signed one is fine.

  serve_https.py <port> <pubdir> <cert.pem> <key.pem>
"""
import http.server
import os
import socket
import ssl
import sys

port, pubdir, cert, key = int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
ALLOWED = {"/xray.gz", "/xray.gz.sha256", "/xray.version"}

ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.minimum_version = ssl.TLSVersion.TLSv1_2
ctx.load_cert_chain(cert, key)


class Handler(http.server.SimpleHTTPRequestHandler):
    timeout = 60

    def __init__(self, *a, **k):
        super().__init__(*a, directory=pubdir, **k)

    def do_GET(self):
        if self.path.split("?")[0] not in ALLOWED:
            self.send_error(404)
            return
        super().do_GET()

    def do_HEAD(self):
        if self.path.split("?")[0] not in ALLOWED:
            self.send_error(404)
            return
        super().do_HEAD()

    def log_message(self, *a):
        pass


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True

    def get_request(self):
        sock, addr = self.socket.accept()
        sock.settimeout(60)
        # handshake happens in the handler thread, so a stalled client cannot block accept()
        return ctx.wrap_socket(sock, server_side=True, do_handshake_on_connect=False), addr

    def handle_error(self, request, client_address):
        pass


Server(("0.0.0.0", port), Handler).serve_forever()
