# Agent notes

## Repo shape

- This is a Garry's Mod addon, not a conventional app/library build. Runtime entrypoint is `lua/autorun/splashsweps_includes.lua`.
- New shared/client library files are wired through `lua/splashsweps/shared/autorun.lua`, `lua/splashsweps/client/autorun.lua`, or `lua/splashsweps/server/autorun.lua`. Follow that pattern instead of adding ad-hoc mid-file includes.
- `SplashSWEPs` is the shared namespace. `lua/splashsweps/server/autorun.lua` and `lua/splashsweps/client/autorun.lua` establish different realm state before loading shared code.

## High-value paths

- `lua/weapons/weapon_splashsweps_test.lua` is the fastest in-game smoke-test surface. It defines the spawnable `Inkling base` weapon mentioned in `README.md`.
- Map paint/cache generation is driven from `lua/splashsweps/server/autorun.lua` and consumed from `lua/splashsweps/client/autorun.lua`. Debug map-cache issues against `data/splashsweps/<map>.json`, `<map>_ldr.json`, and `<map>_hdr.json`.
- The README's cache-file note is stale: current code writes compressed JSON caches named `*.json`, `*_ldr.json`, and `*_hdr.json`, not `<map>.txt`.
- Ink types are loaded by `ss.LoadInkTypes()` from `materials/splashsweps/inktypes/**/*.vmt`, not from a separate JSON content directory.
- Shader sources live in `shaders/src/*.hlsl`; compiled `.vcs` output lives under `shaders/fxc/splashsweps/`; the matching material stubs are in `materials/splashsweps/shaders/`.

## Runtime and debugging gotchas

- Large maps are a real stress case. `README.md` explicitly warns that 32-bit GMOD can crash on some large maps; do not treat those reports as ordinary logic regressions until you rule out build/VRAM limits.
- If paint stops working after map load, check generated cache artifacts before touching gameplay code. Server cache rebuild is gated by BSP CRC in `lua/splashsweps/server/autorun.lua` and `server/mapcache/cachebuilder.lua`.
- The client chooses HDR vs LDR surface data at runtime in `lua/splashsweps/client/autorun.lua`; lighting or surface mismatches can be cache-selection issues, not shader math bugs.
- Multiplayer testing has an asset-distribution constraint from `README.md`: all players need the addon assets. Missing materials on one client can look like a code bug.
- Client readiness is explicit networking state, not just player spawn. `ss.PlayersReady` is filled only after the client sends `SplashSWEPs: PlayerInitialSpawn` in `client/autorun.lua` and `server/playerconnection.lua`.

## Code conventions that matter here

- Shared typed data is built with `ss.struct "TypeName" { ... }` and instantiated with `ss.new "TypeName"`; follow that pattern when adding new structured shared data.
- LuaLS annotations are pervasive in `lua/splashsweps/**`. Mirror `---@class` and `---@type` usage, especially for structured tables and empty table initializers, to keep realm-specific diagnostics useful.

## Verification and tooling

- There is no repo test suite or CI lint/typecheck workflow. `.github/workflows/actions.yml` only uploads a `git archive` zip on pushes to `master`.
- Use the correct LuaLS realm config for edits: `.luarc.server.json` treats `lua/autorun/client` and `lua/splashsweps/client` as ignored, while `.luarc.client.json` ignores the server equivalents.
- `lua/types/` is gitignored/generated but referenced by both `.luarc.*.json` files as workspace library input. Diagnostics in a clean clone may differ until those types exist.
- Do not assume `stylua .` will touch Lua files here: `.styluaignore` currently excludes `*.lua` and `**/*.lua`.

## Exact commands worth knowing

- Compile a shader with the repo's wrapper: `pwsh -ExecutionPolicy Bypass -File "shaders/src/build.ps1" "shaders/src/debug_vs30.hlsl"`
- `shaders/src/build.ps1` compiles both shader stages for the base name, updates `materials/splashsweps/shaders/*.vmt`, writes `shaders/fxc/splashsweps/*.vcs`, and bumps `.vscode/refresh_count_{vs,ps}.txt` for hot reload when GMOD is running.
- For shader-input debugging, the client debug harness in `lua/splashsweps/client/debug_mesh.lua` registers `ss_debug_mesh_probe`, `ss_debug_mesh_probe_spawn`, and `ss_debug_mesh_probe_skin`.
