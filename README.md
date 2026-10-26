# Molecules

A falling-atoms puzzle game for Godot 4 (GDScript): place atoms on a square or hex board, build molecules, clear them for points, play solo or 1v1 online.
**Web is the primary target**: the game is exported as a single-threaded Godot web build and served from `docs/` by GitHub Pages.

Play it: <https://olesch.github.io/Molecules-Godot/>

## Requirements

- [Godot 4.7.2](https://godotengine.org/download) (the version the project is built and tested with; other 4.x releases are untested) with the **Web export templates** installed for exactly that version
  (Godot editor: *Editor -> Manage Export Templates -> Download and Install*; or put `web_nothreads_release.zip` etc. into `%APPDATA%\Godot\export_templates\4.7.2.stable\`).
- Python 3 (standard library only), only to regenerate the audio assets.
- Node.js is **not** needed.

## Run it

```bash
godot --path .          # opens the game in a window (for development)
godot --editor --path . # opens the editor
```

## Build the web version

The export preset "Web" (in `export_presets.cfg`) writes to `docs/`:

```bash
godot --headless --path . --export-release Web docs/index.html
```

It is exported **without thread support** on purpose: GitHub Pages cannot send the cross-origin-isolation headers that a threaded build needs.
Commit and push `docs/` to publish. GitHub Pages is set to serve branch `main`, folder `/docs`
(*Settings -> Pages*). The first load downloads about 40 MB (the `.wasm` engine).

To try the build locally, serve `docs/` over HTTP (browsers do not run `.wasm` from `file://`):

```bash
python -m http.server 8080 --directory docs   # then open http://localhost:8080
```

## Online play

1v1 goes through a small WebSocket relay (a Cloudflare Worker shared with the author's TTA project; it only forwards messages and keeps no game state),
so it works in the browser and needs no port forwarding. **Host online game** shows a 6-letter room code; the other player types it into the join box.
The relay address is `RelayTransport.DEFAULT_URL` in [scripts/net/relay_transport.gd](scripts/net/relay_transport.gd). To run your own,
deploy the relay Worker (protocol v1, described in TTA's `relay/README.md`) on Cloudflare's free plan and change that constant.

## Tests

```bash
godot --headless --import --path .                                    # once, so new script classes are registered
godot --headless --path . --script res://tests/run_all.gd             # all unit tests
godot --headless --path . --script res://tests/relay_net_test.gd      # host + guest through the live relay (needs internet)
```

`tests/balance_sim.gd`, `fun_sim.gd` and `tests/sim/` are balance simulations (see the header of each file), the `*_shot.gd` scripts take screenshots,
`net_test.gd` / `versus_test.gd` are two-process tests of the older ENet LAN transport.

## Project layout

- `scripts/core/` - game rules, no UI: board, atoms, hex/square topologies, scoring, danger/incoming strays, cards, progression, config
- `scripts/view/` - drawing and UI: playfield, menu, setup screen, card overlay
- `scripts/net/` - `NetSession` (1v1 protocol) and `RelayTransport` (relay WebSocket client)
- `scripts/audio/` - music mixer; `assets/` - generated sound effects and music
- `tools/` - Python generators for the audio (`python tools/generate_sfx.py`, `generate_music.py`, `generate_layers.py`)
- `docs/` - the web build served by GitHub Pages (generated, do not edit)
