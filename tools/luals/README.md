# Project-local Neovim / LuaLS configuration

Load `.nvim-example.lua` as `.nvim.lua`, either by copying it or creating a symlink. Requires Neovim 0.12 or later, `lua-language-server`, and the existing type definitions under `lua/types`. Configure the normal `lua_ls` in your own Neovim configuration.

Enable `exrc` and use `:trust` for the project file when prompted. To apply configuration changes to a running Neovim session, run this from the project root:

```vim
:luafile .nvim.lua
```

This restarts the game LuaLS instances so they also reload the plugin. It does not save buffer contents to disk. The existing `ShaderCompile` task template is still registered.

## Client attachment and analysis scope

- Files under `lua/` are analyzed by `lua_ls_gmod_server` and/or `lua_ls_gmod_client`.
- Files used in both realms attach to both instances. Realm-specific exclusions come from `workspace.ignoreDir` in each `.luarc.*.json`. Client selection currently handles the literal relative paths used by these settings.
- `lua/types` is loaded as a type library, without the text transformation applied to game code.
- Lua files outside `lua/` use the normal `lua_ls`. Their definitions are excluded from the game instances, and this project's game files and libraries are excluded from the normal instance. This also filters library settings supplied later by `lazydev.nvim`.
- When the project directory is reached through a symlink, every LuaLS instance uses the resolved directory as its workspace, and a Lua buffer named through the link is renamed to its resolved path before any LuaLS attaches. LuaLS's own file watcher reports changes under a symlinked workspace by resolved paths and loads them as extra files without the workspace libraries.

Use `:GLuaLsp` to inspect attachments. For the current game Lua buffer, use `:GLuaServer` or `:GLuaClient` to select one realm, `:GLuaAutoRealm` to restore automatic selection, or `:GLuaToggle` to switch between realms.

## Realm-specific text transformation

`realm.lua` runs as a LuaLS `runtime.plugin` and returns analysis-text diffs from `OnSetText`. It does not rewrite the source executed by the game.

Only `if` statements whose condition is a standalone reference to the global `SERVER` or `CLIENT` are transformed. The selected branch becomes a `do` block to preserve local scope; unselected code is removed. References in the removed code to locals declared outside it are kept in place as `local _ = { name };` (one statement per removed range, placed after the `do` block when the first branch is selected), so a local used only by the other realm is not reported as unused. If the selected branch ends with a direct `return` statement, subsequent statements in the block containing that `if` are also removed, keeping their references the same way. LuaLS does not report code after a returning `do` block as unreachable.

```lua
if SERVER then return end
-- The server instance excludes the rest of this containing block from analysis.
```

If a false condition is followed by an `elseif`, the remaining chain is retained as a regular `if`; the transformer does not evaluate its condition. Compound conditions, `not SERVER`, `SERVER and ... or ...`, and references to same-named local variables are left unchanged. Text with syntax errors is also left unchanged so LuaLS reports the original errors. Realm-related false positives in unsupported forms remain outside the scope of this transformation.

The plugin depends on LuaLS internals: the `parser` module, AST structure, and diff position mapping. Run the checks below when updating LuaLS.

## Checks with real Neovim and LuaLS

The checks use your normal Neovim configuration with `lua_ls` and `overseer.nvim` installed, because they also verify registration of the existing `ShaderCompile` task template. The LSP configuration itself works without Overseer.

Run from the project root:

```powershell
pwsh -NoProfile -File tools/luals/check.ps1 -Baseline
pwsh -NoProfile -File tools/luals/check.ps1
```

`-Baseline` analyzes the same fixtures without text transformation for comparison. A normal run first uses a separate Neovim instance without user plugins to apply the configuration to an already-running normal LuaLS that has loaded game type definitions, verifying that its effective libraries and diagnostics update. It then uses your normal Neovim configuration to check realm-specific attachments, transformation of unopened files, diagnostics from both branches, genuine and false duplicate definitions, return diagnostics, original source positions, condition edits and undo/redo, syntax errors and repair, configuration reload, renames across realm boundaries, and separation from normal Lua. It also includes regression checks using the real LuaLS parser for shared AST nodes and statement boundaries, and verifies that reloading does not duplicate the build task template. The time from an edit notification to updated diagnostics from both LuaLS instances is recorded as well.

The integration check uses your normal Neovim configuration and verifies automatic loading of `.nvim.lua`. Trust records and editor state are isolated under `.opencode/work/nvim-lsp-simple/state`; your normal trust records are not modified. To avoid Windows path length limits, test undo history is stored beside the fixture files.

Fixture sources and undo files are created only after checking that the paths do not already exist, and are deleted at the end. Received diagnostics, configuration responses, definition locations, and results are saved in per-run directories under `.opencode/work/nvim-lsp-simple/`. The checks do not operate on your already-running Neovim session or game.
