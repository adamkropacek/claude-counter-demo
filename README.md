# Claude Counter (Demo)

Fake "Global Credit Pool" dashboard - vizualni demo, vsechna cisla jsou nahodne generovana. Inspirovano Anthropic-stylem displayu.

## Co to je

Single-page web (`index.html`, zero build) ktery zobrazuje:

- velky counter `$58,793` ktery v case klesa (simulovany pool)
- "spent across the network today" counter co roste
- live burn rate, active sessions, tokens/min, models online

Cisla nejsou skutecna. Demo only.

## Lokalni preview

Otevri `index.html` primo v browseru, nebo:

```bash
cd personal/claude-counter
python -m http.server 8000
# http://localhost:8000
```

## Deploy

Hostovano na GitHub Pages. URL po setupu: `https://adamkropacek.github.io/<repo-name>/`.

## Stack

- HTML + CSS + vanilla JS
- Google Fonts: Inter Tight
- Zero dependencies, zero build

## Spotify Now Playing widget

Bottom-right widget zobrazuje real-time Spotify track Adama. Vyžaduje one-time setup
(Spotify Dev App + Cloudflare Worker proxy) - viz `spotify-worker/SETUP.md`.

Bez setupu se widget zobrazi v "Spotify offline / setup pending" stavu (ne-rušivý).
