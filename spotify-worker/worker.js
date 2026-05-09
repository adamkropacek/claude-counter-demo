/**
 * Cloudflare Worker - Spotify "Now Playing" proxy
 *
 * Required Worker secrets (set via `wrangler secret put`):
 *   - SPOTIFY_CLIENT_ID
 *   - SPOTIFY_CLIENT_SECRET
 *   - SPOTIFY_REFRESH_TOKEN
 *
 * Optional environment vars (set in wrangler.toml [vars]):
 *   - ALLOWED_ORIGIN  (default: https://adamkropacek.github.io)
 *
 * Returns JSON shape:
 *   { is_playing: bool, track_name, artist_name, album_name,
 *     album_art_url, duration_ms, progress_ms, track_url }
 *
 * 204 from Spotify (nothing playing) -> { is_playing: false }
 */

export default {
  async fetch(request, env) {
    const allowedOrigin = env.ALLOWED_ORIGIN || 'https://adamkropacek.github.io';

    const corsHeaders = {
      'Access-Control-Allow-Origin': allowedOrigin,
      'Access-Control-Allow-Methods': 'GET, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
      'Cache-Control': 'no-store, max-age=0',
      'Vary': 'Origin',
    };

    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }

    if (request.method !== 'GET') {
      return jsonResponse({ error: 'method not allowed' }, 405, corsHeaders);
    }

    if (!env.SPOTIFY_CLIENT_ID || !env.SPOTIFY_CLIENT_SECRET || !env.SPOTIFY_REFRESH_TOKEN) {
      return jsonResponse({ error: 'worker misconfigured: missing secrets' }, 500, corsHeaders);
    }

    try {
      const accessToken = await refreshAccessToken(env);
      const playing = await getCurrentlyPlaying(accessToken);
      return jsonResponse(playing, 200, corsHeaders);
    } catch (err) {
      return jsonResponse({ error: err.message || String(err) }, 502, corsHeaders);
    }
  },
};

function jsonResponse(body, status, extraHeaders) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      ...extraHeaders,
    },
  });
}

async function refreshAccessToken(env) {
  const credentials = btoa(env.SPOTIFY_CLIENT_ID + ':' + env.SPOTIFY_CLIENT_SECRET);
  const res = await fetch('https://accounts.spotify.com/api/token', {
    method: 'POST',
    headers: {
      'Authorization': 'Basic ' + credentials,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams({
      grant_type: 'refresh_token',
      refresh_token: env.SPOTIFY_REFRESH_TOKEN,
    }),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error('token refresh failed (' + res.status + '): ' + text.slice(0, 200));
  }

  const data = await res.json();
  if (!data.access_token) throw new Error('token refresh: no access_token in response');
  return data.access_token;
}

async function getCurrentlyPlaying(accessToken) {
  const res = await fetch('https://api.spotify.com/v1/me/player/currently-playing', {
    headers: { 'Authorization': 'Bearer ' + accessToken },
  });

  if (res.status === 204) return { is_playing: false };
  if (res.status === 401) throw new Error('spotify auth: 401 (refresh token may be revoked)');
  if (!res.ok) {
    const text = await res.text();
    throw new Error('spotify api ' + res.status + ': ' + text.slice(0, 200));
  }

  const data = await res.json();
  if (!data || !data.item) return { is_playing: false };

  const artists = Array.isArray(data.item.artists)
    ? data.item.artists.map(a => a.name).filter(Boolean).join(', ')
    : '';
  const albumArt = data.item.album && Array.isArray(data.item.album.images) && data.item.album.images[0]
    ? data.item.album.images[0].url
    : null;

  return {
    is_playing: !!data.is_playing,
    track_name: data.item.name || '',
    artist_name: artists,
    album_name: data.item.album ? (data.item.album.name || '') : '',
    album_art_url: albumArt,
    duration_ms: data.item.duration_ms || 0,
    progress_ms: data.progress_ms != null ? data.progress_ms : 0,
    track_url: data.item.external_urls && data.item.external_urls.spotify || null,
  };
}
