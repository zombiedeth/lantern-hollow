# Lantern Hollow — Browser Export

Drop these files into any static web host (GitHub Pages, Netlify, a phone-local server, etc.) and open `index.html` in a mobile browser to play.

## Quick phone test (local)

```bash
cd build/web
python3 -m http.server 8000
# On your phone (same Wi-Fi), navigate to http://<your-mac-local-ip>:8000/
```

Mac local IP: `ipconfig getifaddr en0`

## GitHub Pages

Push this `build/web/` directory to a `gh-pages` branch (or set the Pages source to the `/build/web` folder) — your game will be live at `https://<user>.github.io/<repo>/`.

## Files

- `index.html` — entry point
- `index.js` + `index.wasm` — Godot runtime (~40MB)
- `index.pck` — packed game assets
- `*.worklet.js` — audio worklets for sound

## Tap-to-play

This is a touch-first game. Tap the dirt plots to plant, tap bloomed flowers to harvest, tap seed cards at the bottom to select what to plant.
