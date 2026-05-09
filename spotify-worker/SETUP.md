# Spotify Now Playing - Setup (one-time, ~10 min)

End result: bottom-right widget on `https://adamkropacek.github.io/claude-counter-demo/` shows whatever you (Adam) are currently playing on Spotify, refreshed every 15s.

## Prereqs

- Spotify account (any tier - free works for currently-playing)
- Cloudflare account (free) - you already have `.wrangler/` set up
- Python 3 (Windows: already installed)
- Node + `npx wrangler` available

## Step 1 - Create Spotify app

1. Go to https://developer.spotify.com/dashboard
2. Click **Create app**
3. Fields:
   - **App name**: `Adam Now Playing` (anything)
   - **App description**: anything
   - **Website**: `https://adamkropacek.github.io/claude-counter-demo/`
   - **Redirect URI**: `http://127.0.0.1:8765/callback` (EXACTLY this)
   - Tick: **Web API**
4. Save. Open the new app -> **Settings** -> copy **Client ID** and **Client secret**.

## Step 2 - Get refresh_token (one-time)

```bash
cd personal/claude-counter/spotify-worker
python get-refresh-token.py <CLIENT_ID> <CLIENT_SECRET>
```

- Browser opens with Spotify login. Log in. Click **Agree**.
- Script captures the code and prints `REFRESH_TOKEN: <long-string>`.
- **Save the refresh_token** (text file, password manager - whatever). It does not expire unless you revoke access.

## Step 3 - Deploy Cloudflare Worker

```bash
cd personal/claude-counter/spotify-worker

# 3a) Login to Cloudflare (browser opens once)
npx wrangler login

# 3b) Set secrets - paste the values when prompted
npx wrangler secret put SPOTIFY_CLIENT_ID
npx wrangler secret put SPOTIFY_CLIENT_SECRET
npx wrangler secret put SPOTIFY_REFRESH_TOKEN

# 3c) Deploy
npx wrangler deploy
```

You will see: `Published spotify-now-playing (... ms) https://spotify-now-playing.<account>.workers.dev`

Copy that URL.

## Step 4 - Wire URL into the page

Edit `personal/claude-counter/index.html`, find:

```js
const SPOTIFY_PROXY_URL = '';
```

Replace with:

```js
const SPOTIFY_PROXY_URL = 'https://spotify-now-playing.<account>.workers.dev';
```

Then:

```bash
git -C personal/claude-counter add -A
git -C personal/claude-counter commit -m "feat: wire Spotify Worker URL"
git -C personal/claude-counter push
```

GH Pages rebuilds in ~15s. Open https://adamkropacek.github.io/claude-counter-demo/ in incognito (or hard-refresh) - widget shows current Spotify track.

## Verify

- Play a song on Spotify (any device).
- Within 15s the widget updates with cover art + track + artist + progress bar.
- Click the widget -> opens the track on Spotify.

## Troubleshooting

| Symptom | Likely cause | Fix |
|--|--|--|
| Widget says "Spotify offline / setup pending" | `SPOTIFY_PROXY_URL` empty | Step 4 |
| Widget always shows "Nothing playing" even when playing | Spotify Connect device not actively reporting | Open Spotify desktop/mobile app and play (web player sometimes does not register) |
| Worker returns 401 | refresh_token revoked | Re-run Step 2, update secret |
| Worker returns 500 misconfigured | secret missing | Re-run `wrangler secret put` for the missing one |
| CORS error in browser | Origin mismatch | Edit `wrangler.toml` `ALLOWED_ORIGIN` to match your GH Pages origin, redeploy |

## Limits / cost

- Cloudflare Workers free tier: 100k requests/day. At one poll per 15s = 5760 req/day -> well within free tier.
- Spotify API: no documented rate limit issue at 4 req/min for currently-playing.
- No ongoing cost. No credit card needed for free tier.

## Security notes

- Worker secrets are encrypted at rest in Cloudflare.
- `refresh_token` is the only persistent credential; revocable from https://www.spotify.com/account/apps/
- CORS lock is `Allowed-Origin: https://adamkropacek.github.io` so other sites cannot use your worker.
- Worker returns ONLY currently-playing track metadata (no email, no playlists, no library).
