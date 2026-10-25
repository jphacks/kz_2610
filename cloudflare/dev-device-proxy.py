#!/usr/bin/env python3
"""Forward app API requests on a trusted development LAN to loopback Wrangler.

Usage: python3 cloudflare/dev-device-proxy.py --bind <Mac Wi-Fi IPv4>
Wrangler and its Local Explorer remain bound to localhost:8787.
"""
import argparse
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

MAX_BYTES = 6 * 1024 * 1024


class AppAPIProxy(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass  # Never log credentials, requests, profile handles or bodies.

    def forward(self):
        path = urlsplit(self.path)
        if (path.scheme or path.netloc or '%' in path.path or '..' in path.path
                or '\\' in path.path or not (path.path == '/health' or path.path.startswith('/v1/'))):
            self.send_error(404)
            return
        if self.headers.get('Transfer-Encoding'):
            self.send_error(400)
            return
        try:
            size = int(self.headers.get('Content-Length', '0'))
        except ValueError:
            self.send_error(400)
            return
        if size < 0 or size > MAX_BYTES:
            self.send_error(413)
            return
        self.connection.settimeout(30)
        upstream = http.client.HTTPConnection('127.0.0.1', 8787, timeout=30)
        try:
            payload = self.rfile.read(size) if size else None
            headers = {key: self.headers[key] for key in ('Authorization', 'Content-Type', 'Accept') if key in self.headers}
            upstream.request(self.command, self.path, body=payload, headers=headers)
            response = upstream.getresponse()
            data = response.read(MAX_BYTES + 1)
            if len(data) > MAX_BYTES:
                self.send_error(502)
                return
            self.send_response(response.status)
            for key in ('Content-Type', 'Cache-Control', 'X-Content-Type-Options'):
                if response.getheader(key):
                    self.send_header(key, response.getheader(key))
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except (OSError, http.client.HTTPException):
            self.send_error(502)
        finally:
            upstream.close()

    do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = forward


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bind', required=True, help='Mac Wi-Fi address to listen on')
    parser.add_argument('--port', type=int, default=8788)
    args = parser.parse_args()
    server = ThreadingHTTPServer((args.bind, args.port), AppAPIProxy)
    print(f'App API proxy ready on {args.bind}:{args.port}', flush=True)
    server.serve_forever()
