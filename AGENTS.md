# Agent notes

## Repo shape

- This is a Garry's Mod addon, not a conventional app/library build. Runtime entrypoint is `lua/autorun/splashsweps_includes.lua`.
- Module files are loaded by `ss.import "<path under lua/ without .lua>"` at the top of each file that uses them, not by `autorun.lua`. See `lua/splashsweps/shared/import.lua`. Other library files are still wired through `lua/splashsweps/shared/autorun.lua`, `lua/splashsweps/client/autorun.lua`, or `lua/splashsweps/server/autorun.lua`; do not add ad-hoc mid-file includes.
- `lua/autorun/splashsweps_includes.lua` sends every Lua file under `splashsweps/shared/` and `splashsweps/client/`, including subdirectories, to clients.
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

## Runtime access via MCP bridge

- A running Garry's Mod instance can be controlled and observed through the MCP bridge. `gmod_`-prefixed tools cover host launch and close, console execution, Lua execution, cvar state, screenshots, and debug hooks in both client and server realms.
- MCP-driven sessions run with the game window unfocused. Frame-rate limiters that apply while unfocused (such as `fps_max_nofocus`) are readable through `gmod_cvar_state_cl`, but their values are environment-dependent. Do not assume or document a fixed value.

## Code conventions that matter here

- A module file starts with `local M = ss.module "<its import path>"` and ends with `return M`. Keep state that must survive hot reload in `ss.state("<its import path>", { ... })`, not `ss.Locals`. A class-like module is its own metatable (`M.__index = M`, constructor `M.new`, methods `function M:Method()`), as in `client/rbtree.lua`. Do not copy fields of an imported module into locals when the file is loaded; hot reload replaces them in the module table.
- Shared typed data is built with `ss.struct "TypeName" { ... }` and instantiated with `ss.new "TypeName"`; follow that pattern when adding new structured shared data.
- LuaLS annotations are pervasive in `lua/splashsweps/**`. Mirror `---@class` and `---@type` usage, especially for structured tables and empty table initializers, to keep realm-specific diagnostics useful.
- Do not define `SplashSWEPs` namespace state from shared realm files. Realm-specific state belongs to that realm's autorun bootstrap or a file-local `ss.Locals` table.
- Prefer designs where one file owns one responsibility. If state is file-local, define `ss.Locals.<short role>` at the top of that file, mirror existing annotations, alias the local table, and keep fields under that table.
- If `SplashSWEPs` state must be shared across files in a realm, define it in the `SplashSWEPs` bootstrap block in that realm's `autorun.lua`.
- `autorun.lua` and `ss.Locals` table guards are the hot-reload boundary. Do not add per-field `or {}` reinitialization guards for namespace state.

## Verification and tooling

- There is no repo test suite or CI lint/typecheck workflow. `.github/workflows/actions.yml` only uploads a `git archive` zip on pushes to `master`.
- Use the correct LuaLS realm config for edits, and check through warnings, not only errors. `.luarc.server.json` treats `lua/autorun/client` and `lua/splashsweps/client` as ignored, while `.luarc.client.json` ignores the server equivalents.
- Run LuaLS checks from the repo root and keep `--check=.` as the workspace when using the repo configs. The relative `workspace.ignoreDir` and `workspace.library` entries in `.luarc.client.json` and `.luarc.server.json` are written for that workspace shape.
- Gate-style LuaLS commands: `lua-language-server --check=. --configpath=.luarc.client.json --checklevel=Error --check_format=pretty` and `lua-language-server --check=. --configpath=.luarc.server.json --checklevel=Error --check_format=pretty`.
- For warning review, rerun the same realm command without narrowing to `--checklevel=Error`, then separate real code warnings from environment noise caused by missing generated type libraries.
- `lua/types/` is gitignored/generated but referenced by both `.luarc.*.json` files as workspace library input. Diagnostics in a clean clone may differ until those types exist.
- Do not assume `stylua .` will touch Lua files here: `.styluaignore` currently excludes `*.lua` and `**/*.lua`.
- Do not "clean up" or revert build-script side effects just because they look like generated churn. First check this file, the build script behavior, and whether the change is required for the current runtime workflow.
- Before reverting any modified file, distinguish repo-irrelevant accidental edits from user/runtime-required edits. If the reason to revert is not explicitly grounded in project rules or the user's request, leave it alone.
- Treat edits to `lua/weapons/weapon_splashsweps_test.lua` as possible in-game smoke-test controls, not disposable noise. Preserve radius, ink type, or debug behavior tweaks unless the current task explicitly says to reset them.

## Exact commands worth knowing

- Compile a shader with the repo's wrapper: `pwsh -ExecutionPolicy Bypass -File "shaders/src/build.ps1" "shaders/src/debug_vs30.hlsl"`
- `shaders/src/build.ps1` compiles only the given shader files, in the given order
  (for example `build.ps1 inkmesh_vs30.hlsl inkmesh_ps30.hlsl`), rewrites every `materials/splashsweps/shaders/*.vmt`
  whose `$vertexshader` or `$pixshader` refers to a built shader, writes `shaders/fxc/splashsweps/*.vcs`,
  and bumps `.vscode/refresh_count_{vs,ps}.txt` for hot reload when GMOD is running.
  It does not build the other stage; build both when the data passed from the vertex shader to the pixel shader changes.
- Do not revert the shader names that `shaders/src/build.ps1` writes into `materials/splashsweps/shaders/*.vmt`. Numbered names such as `splashsweps/2_inkmesh_ps30` are intentional hot-reload targets while GMOD is running, not accidental churn.
- GMOD loads a shader file into memory only the first time that shader name is read.
  `build.ps1` hot reload works for material stubs because it writes new numbered shader names
  into every VMT that refers to the shader.
  Materials created through `CreateMaterial` do not get that VMT rewrite automatically;
  after compiling, update those live `IMaterial`s with `SetString("$vertexshader", "splashsweps/<numbered>_..._vs30")`,
  `SetString("$pixshader", "splashsweps/<numbered>_..._ps30")`, then `Recompute()`.
- When validating shader changes, run the wrapper from `shaders/src` if the direct repo-root invocation cannot find sibling shader sources. Preserve the wrapper's resulting VMT shader names and `.vcs` outputs unless the user explicitly asks otherwise.
- Do not run multiple `shaders/src/build.ps1` shader compiles in parallel;
  the wrapper uses shared intermediate/output paths and can race with itself.
  List several shader files in one invocation instead; it compiles them in order.
- Do not normalize shader material stubs after debugging just because values look temporary. Sampler bindings such as `$texture7 "shadertest/cubemap"` may be intentional shader-input probes; keep them unless the current task or user says to restore defaults.
