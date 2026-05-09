#!/usr/bin/env bash
# All-in-one: OAuth -> refresh_token -> set wrangler secrets -> deploy -> wire URL -> commit -> push.
# Adam clicks "Agree" once when browser opens. Everything else automated.
#
# Usage:  bash deploy-now.sh <CLIENT_ID> <CLIENT_SECRET>

set -euo pipefail

if [ $# -ne 2 ]; then
  echo "usage: bash deploy-now.sh <CLIENT_ID> <CLIENT_SECRET>"
  exit 2
fi

CLIENT_ID="$1"
CLIENT_SECRET="$2"
HERE="$(cd "$(dirname "$0")" && pwd)"
COUNTER_DIR="$(cd "$HERE/.." && pwd)"
INDEX_HTML="$COUNTER_DIR/index.html"

echo ""
echo "=================================================="
echo "STEP 1/5 - OAuth flow (browser will open)"
echo "=================================================="
echo "Click 'Agree' in the browser when it opens."
echo ""

# Run get-refresh-token.py and capture refresh_token from stdout.
TMP_LOG="$(mktemp)"
python "$HERE/get-refresh-token.py" "$CLIENT_ID" "$CLIENT_SECRET" | tee "$TMP_LOG"

# Extract REFRESH_TOKEN line. The script prints:
#   REFRESH_TOKEN (THIS is what you need):
#   <token-string>
REFRESH_TOKEN="$(awk '/REFRESH_TOKEN \(THIS is what you need\):/{getline; print; exit}' "$TMP_LOG")"
rm -f "$TMP_LOG"

if [ -z "$REFRESH_TOKEN" ] || [ "${#REFRESH_TOKEN}" -lt 40 ]; then
  echo ""
  echo "ERROR: refresh_token not captured. Check the OAuth flow."
  exit 1
fi
echo ""
echo "captured refresh_token (length=${#REFRESH_TOKEN})"

echo ""
echo "=================================================="
echo "STEP 2/5 - set Cloudflare Worker secrets"
echo "=================================================="
cd "$HERE"

# Wrangler secret put reads from stdin when piped.
echo "$CLIENT_ID"     | npx --yes wrangler secret put SPOTIFY_CLIENT_ID 2>&1     | tail -3
echo "$CLIENT_SECRET" | npx --yes wrangler secret put SPOTIFY_CLIENT_SECRET 2>&1 | tail -3
echo "$REFRESH_TOKEN" | npx --yes wrangler secret put SPOTIFY_REFRESH_TOKEN 2>&1 | tail -3

echo ""
echo "=================================================="
echo "STEP 3/5 - deploy worker"
echo "=================================================="
DEPLOY_OUT="$(npx --yes wrangler deploy 2>&1)"
echo "$DEPLOY_OUT"

# Extract worker URL from "Published" line. Wrangler v4 prints something like:
#   Uploaded spotify-now-playing (... ms)
#   Deployed spotify-now-playing triggers (... ms)
#     https://spotify-now-playing.<account>.workers.dev
WORKER_URL="$(echo "$DEPLOY_OUT" | grep -oE 'https://[a-zA-Z0-9.-]+\.workers\.dev' | head -1)"
if [ -z "$WORKER_URL" ]; then
  echo ""
  echo "ERROR: could not extract worker URL from deploy output."
  exit 1
fi
echo ""
echo "worker URL: $WORKER_URL"

echo ""
echo "=================================================="
echo "STEP 4/5 - wire URL into index.html"
echo "=================================================="
# Replace the SPOTIFY_PROXY_URL = '' line. Use python for safe in-place edit (cross-platform).
python - "$INDEX_HTML" "$WORKER_URL" <<'PY'
import sys, re, pathlib
path = pathlib.Path(sys.argv[1])
url = sys.argv[2]
src = path.read_text(encoding="utf-8")
new = re.sub(
    r"const SPOTIFY_PROXY_URL = '[^']*';",
    f"const SPOTIFY_PROXY_URL = '{url}';",
    src,
    count=1,
)
if new == src:
    print("WARN: SPOTIFY_PROXY_URL marker not found in index.html")
    sys.exit(1)
path.write_text(new, encoding="utf-8")
print(f"updated {path} -> SPOTIFY_PROXY_URL = '{url}'")
PY

echo ""
echo "=================================================="
echo "STEP 5/5 - commit + push"
echo "=================================================="
cd "$COUNTER_DIR"
git add index.html
git -c user.email=adamkropacek12@gmail.com -c user.name=Adam \
  commit -m "feat: wire spotify worker URL ($WORKER_URL)"
git push origin main

echo ""
echo "=================================================="
echo "DONE"
echo "=================================================="
echo ""
echo "Worker URL : $WORKER_URL"
echo "Live site  : https://adamkropacek.github.io/claude-counter-demo/"
echo ""
echo "GH Pages rebuilds in ~15-25s. Open the live URL in incognito."
echo "Play a song on Spotify - widget updates within 15s."
