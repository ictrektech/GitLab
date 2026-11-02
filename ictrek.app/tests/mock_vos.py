#!/usr/bin/env python3
"""Isolated VOS contract fixture. Never use this server as a real identity provider."""
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import time
from urllib.parse import parse_qs


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        body = parse_qs(self.rfile.read(int(self.headers.get('Content-Length', '0'))).decode())
        token = body.get('token', [''])[0]
        sub = 'subject-b' if token == 'bob' else 'subject-a'
        data = {'active': token in ('alice', 'bob', 'renamed', 'disabled', 'wrong-aud', 'expired', 'wrong-scope'),
                'client_id': 'com.ictrek.gitlab', 'aud': 'com.ictrek.gitlab', 'token_type': 'Bearer',
                'scope': 'openid profile email', 'sub': sub, 'exp': int(time.time()) + 3600}
        if token == 'wrong-aud':
            data['aud'] = 'com.ictrek.other'
        if token == 'expired':
            data['exp'] = 0
        if token == 'wrong-scope':
            data['scope'] = 'profile'
        self.respond(data)

    def do_GET(self):
        token = self.headers.get('Authorization', '').removeprefix('Bearer ')
        self.respond({'sub': 'subject-b' if token == 'bob' else 'subject-a',
                      'preferred_username': 'Renamed' if token == 'renamed' else 'Same display name',
                      'enable': 0 if token == 'disabled' else 1})

    def respond(self, data):
        encoded = json.dumps(data).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)


if __name__ == '__main__':
    ThreadingHTTPServer(('0.0.0.0', 27681), Handler).serve_forever()
