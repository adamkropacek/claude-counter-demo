#!/usr/bin/env python3
"""
One-time helper: get a Spotify refresh_token for the Worker.

Usage:
  1. Create Spotify Dev app at https://developer.spotify.com/dashboard
     - In app settings, add Redirect URI EXACTLY: http://127.0.0.1:8765/callback
  2. Run:   python get-refresh-token.py <CLIENT_ID> <CLIENT_SECRET>
  3. Browser opens -> log in with your Spotify account -> click "Agree"
  4. Script prints the refresh_token. Save it.
  5. Set Worker secrets:
       wrangler secret put SPOTIFY_CLIENT_ID
       wrangler secret put SPOTIFY_CLIENT_SECRET
       wrangler secret put SPOTIFY_REFRESH_TOKEN

The refresh_token does not expire unless you revoke access in Spotify settings.
"""

import base64
import http.server
import secrets
import sys
import threading
import urllib.parse
import urllib.request
import webbrowser
from urllib.parse import urlencode, parse_qs, urlparse

REDIRECT_URI = "http://127.0.0.1:8765/callback"
SCOPES = "user-read-currently-playing user-read-playback-state"
PORT = 8765

state_token = secrets.token_urlsafe(16)
captured = {"code": None, "state": None}


class CallbackHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path != "/callback":
            self.send_response(404)
            self.end_headers()
            return
        qs = parse_qs(parsed.query)
        captured["code"] = (qs.get("code") or [None])[0]
        captured["state"] = (qs.get("state") or [None])[0]
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        ok = "<h2>OK - you can close this tab.</h2>"
        err = "<h2>Error - check the terminal.</h2>"
        msg = ok if captured["code"] else err
        self.wfile.write(msg.encode("utf-8"))

    def log_message(self, *_):
        pass  # silence


def exchange_code_for_tokens(client_id: str, client_secret: str, code: str) -> dict:
    creds = base64.b64encode(f"{client_id}:{client_secret}".encode()).decode()
    body = urlencode({
        "grant_type": "authorization_code",
        "code": code,
        "redirect_uri": REDIRECT_URI,
    }).encode()
    req = urllib.request.Request(
        "https://accounts.spotify.com/api/token",
        data=body,
        headers={
            "Authorization": f"Basic {creds}",
            "Content-Type": "application/x-www-form-urlencoded",
        },
    )
    with urllib.request.urlopen(req) as r:
        import json
        return json.loads(r.read().decode())


def main():
    if len(sys.argv) != 3:
        print("usage: python get-refresh-token.py <CLIENT_ID> <CLIENT_SECRET>")
        sys.exit(2)
    client_id, client_secret = sys.argv[1], sys.argv[2]

    auth_url = "https://accounts.spotify.com/authorize?" + urlencode({
        "client_id": client_id,
        "response_type": "code",
        "redirect_uri": REDIRECT_URI,
        "scope": SCOPES,
        "state": state_token,
    })

    server = http.server.HTTPServer(("127.0.0.1", PORT), CallbackHandler)
    t = threading.Thread(target=server.serve_forever, daemon=True)
    t.start()

    print(f"Opening browser: {auth_url}")
    webbrowser.open(auth_url)
    print(f"Waiting for callback on {REDIRECT_URI} ...")

    while captured["code"] is None:
        try:
            t.join(timeout=0.5)
        except KeyboardInterrupt:
            print("\naborted")
            sys.exit(1)

    server.shutdown()

    if captured["state"] != state_token:
        print("STATE MISMATCH - aborting (CSRF protection).")
        sys.exit(1)

    print("Got authorization code, exchanging for tokens...")
    tokens = exchange_code_for_tokens(client_id, client_secret, captured["code"])

    print()
    print("=" * 60)
    print("ACCESS_TOKEN  (short-lived, ignore):")
    print(tokens.get("access_token", "")[:40] + "...")
    print()
    print("REFRESH_TOKEN (THIS is what you need):")
    print(tokens.get("refresh_token", ""))
    print("=" * 60)
    print()
    print("Next: set it as a Cloudflare Worker secret:")
    print("  cd spotify-worker")
    print("  npx wrangler secret put SPOTIFY_REFRESH_TOKEN")
    print("  (paste the refresh_token above when prompted)")


if __name__ == "__main__":
    main()
