# Autonomous Render Test Setup for Coding Agents

This document describes how to set up render-test execution so a coding agent can drive Garry's Mod validation without typing commands into the in-game developer console. The target use case is the deferred ink renderer work, where correctness depends on render targets, depth ownership, SortID routing, substrate resolve output, and final compositing artifacts.

## Core Decision

Do not make the in-game console command the primary automation interface.

The Garry's Mod developer console is an interactive UI normally opened by a human player. A coding agent running in a terminal cannot reliably type into that UI. The test runner should therefore expose a normal Lua function as the real entry point, with console commands only as manual wrappers.

Use this split:

- Agent-driven path: terminal writes a request file, Garry's Mod Lua reads it, runs the test function, and writes result artifacts.
- Manual path: a developer may still run a console command that calls the same Lua function.

The test function must be the shared implementation. The console command must not contain unique test logic.

## Recommended Architecture

Add a client-side render-test module:

```text
lua/splashsweps/client/render_tests.lua
```

Load it from the existing client autorun path:

```text
lua/splashsweps/client/autorun.lua
```

The module should define a stable function:

```lua
function SplashSWEPs.RenderTests.Run(request)
    -- Run one case or all cases.
    -- Write JSON and capture artifacts under data/splashsweps/render_tests/.
end
```

The manual console command should only adapt console arguments into a request:

```lua
concommand.Add("ss_render_test_run", function(_, _, args)
    SplashSWEPs.RenderTests.Run({
        source = "console",
        case = args[1] or "all",
    })
end)
```

The autonomous path should call `SplashSWEPs.RenderTests.Run` directly from Lua after reading a request file.

## Request File Protocol

Use a request file under Garry's Mod's `DATA` area:

```text
data/splashsweps/render_tests/request.json
```

The coding agent writes this file from the terminal side. Garry's Mod reads it with `file.Read(..., "DATA")`, parses it with `util.JSONToTable`, and schedules execution when the client is ready.

Example request:

```json
{
  "request_id": "2026-06-17T12-00-00Z-inkprep",
  "case": "all",
  "map": "gm_construct",
  "resolution": [1024, 1024],
  "timeout_seconds": 120,
  "close_after_run": true,
  "capture_png": true,
  "write_metrics": true
}
```

The request file should be treated as a one-shot job. After Garry's Mod accepts it, the runner should either move it to a run directory or write an accepted status that includes the active `request_id`. This prevents accidental re-running after a map reload.

## Result Artifact Protocol

Each run should write a directory under:

```text
data/splashsweps/render_tests/runs/<request_id>/
```

Minimum artifacts:

```text
result.json
status.json
logs.txt
captures/
```

`status.json` is for polling while the game is still running. `result.json` is the final contract. The coding agent should consider the run complete only after `result.json` exists and contains a terminal status.

Example `status.json`:

```json
{
  "request_id": "2026-06-17T12-00-00Z-inkprep",
  "state": "running",
  "case": "mrt_slots",
  "updated_at": 12.75
}
```

Example `result.json`:

```json
{
  "request_id": "2026-06-17T12-00-00Z-inkprep",
  "status": "pass",
  "map": "gm_construct",
  "hdr": false,
  "resolution": [1024, 1024],
  "cases": {
    "mrt_slots": {
      "status": "pass",
      "metrics": {
        "bad_pixel_ratio": 0.0
      },
      "captures": [
        "captures/mrt_color0.png",
        "captures/mrt_color1.png",
        "captures/mrt_color2.png",
        "captures/mrt_color3.png"
      ],
      "failures": []
    }
  },
  "failures": []
}
```

Use `status: "fail"` for completed runs with failed checks, and `status: "error"` for harness errors, Lua exceptions, missing render targets, unsupported formats, timeout handling, or capture failures.

## Agent-Side Driver

The coding agent should drive the run from the terminal by using files, not the in-game console.

The driver flow is:

1. Write `data/splashsweps/render_tests/request.json`.
2. Start Garry's Mod with a deterministic map and rendering setup, or wait for an already running instance.
3. Poll `data/splashsweps/render_tests/runs/<request_id>/status.json`.
4. Wait for `result.json`.
5. Parse `result.json`.
6. Inspect PNG captures only when metrics fail or when visual diagnosis is needed.
7. Treat missing `result.json` before the timeout as a harness failure.

Launching Garry's Mod may require user approval from the agent environment because it opens a GUI application. Once the game is running, the validation loop should remain file-based.

The repository wrapper for this flow is:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "tools/run-render-test.ps1" -Case all
```

Use this wrapper instead of ad-hoc terminal commands so the approval prefix can remain stable across repeated render-test runs. Useful options:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "tools/run-render-test.ps1" -Case readiness -NoLaunch
pwsh -NoProfile -ExecutionPolicy Bypass -File "tools/run-render-test.ps1" -Case sortid_pack -TimeoutSeconds 60
pwsh -NoProfile -ExecutionPolicy Bypass -File "tools/run-render-test.ps1" -Case all -CloseAfterRun
```

Useful public Garry's Mod references:

- Command-line parameters: <https://wiki.facepunch.com/gmod/Command_Line_Parameters>
- `file.Read`: <https://wiki.facepunch.com/gmod/file.Read>
- `file.Write`: <https://wiki.facepunch.com/gmod/file.Write>
- `util.JSONToTable`: <https://wiki.facepunch.com/gmod/util.JSONToTable>
- `util.TableToJSON`: <https://wiki.facepunch.com/gmod/util.TableToJSON>

## Game-Side Readiness

The render-test module must not run immediately when the Lua file loads. It should wait until the renderer has the data needed for real tests.

The readiness gate should include:

- client autorun has completed;
- map cache data has loaded;
- render targets have been created;
- `SplashSWEPs.RenderBatches` has been built;
- screen size and HDR/LDR mode have been recorded;
- at least one render hook tick has passed if the case needs framebuffer state.

The existing client initialization path loads cache data and calls setup functions from `InitPostEntity`. The render-test watcher should therefore start polling after initialization, but only run a job after the above readiness checks pass.

## Manual Console Entry Point

Keep this for humans:

```text
ss_render_test_run all
ss_render_test_run mrt_slots
```

This is only a convenience wrapper. The coding-agent setup must not depend on a human opening the developer console, pasting text, or pressing Enter.

If Lua code needs to trigger the same command internally, `RunConsoleCommand` exists, but it is still a game-side Lua API. It is not a terminal-side control channel for the agent. Prefer calling `SplashSWEPs.RenderTests.Run(request)` directly.

Reference:

- `RunConsoleCommand`: <https://wiki.facepunch.com/gmod/Global.RunConsoleCommand>

## Render Validation Cases

The autonomous harness should be able to run these cases independently:

- `mrt_slots`: prove that `COLOR0..3` receive the intended render targets.
- `depth_multi_imesh`: prove that multiple IMesh draw calls share and preserve the correct depth buffer.
- `sortid_pack`: prove that SortID packing through vertex color RGB is decoded exactly.
- `brush_entity_matrix`: prove that brush entity model matrices preserve InkPrep coordinates and depth.
- `inkprep_fields`: validate InkPrep UVs, normals, height, roughness, mask, W, and SortID ranges.
- `substrate_one_sortid`: resolve one SortID in screen space and verify masked writes.
- `substrate_all_sortids`: resolve every SortID and verify that no valid ink pixel remains unresolved.
- `scissor_equivalence`: compare fullscreen resolve against scissored SortID resolve.
- `final_no_ssr`: compare deferred Phong and rim output without SSR.
- `final_with_ssr`: validate final composite with SSR and stitching enabled.

Each case should produce JSON metrics that decide pass or fail. PNG captures are supporting evidence for diagnosis, not the pass condition.

## Render Artifact Requirements

Use `render.Capture` to export diagnostic PNG files from the relevant render targets. The PNGs should have stable names and be listed in `result.json`.

References:

- `render.Capture`: <https://wiki.facepunch.com/gmod/render.Capture>
- `render.SetRenderTargetEx`: <https://wiki.facepunch.com/gmod/render.SetRenderTargetEx>
- `GetRenderTargetEx`: <https://wiki.facepunch.com/gmod/Global.GetRenderTargetEx>
- `IMAGE_FORMAT`: <https://wiki.facepunch.com/gmod/Enums/IMAGE_FORMAT>
- `render.ClearDepth`: <https://wiki.facepunch.com/gmod/render.ClearDepth>
- `render.OverrideDepthEnable`: <https://wiki.facepunch.com/gmod/render.OverrideDepthEnable>
- `render.SetScissorRect`: <https://wiki.facepunch.com/gmod/render.SetScissorRect>

The runner should write both successful and failed captures when possible. A failed metric without a capture should include a clear failure reason in JSON.

## Closing the Game After a Run

If the run is launched specifically for automation, the request may include:

```json
{
  "close_after_run": true
}
```

The game-side runner can then close the session after writing `result.json`, if the launch mode allows it. Garry's Mod documents `-allowquit` and `-systemtest` command-line parameters, and `engine.CloseServer` is documented with restrictions around test mode.

References:

- Command-line parameters: <https://wiki.facepunch.com/gmod/Command_Line_Parameters>
- `engine.CloseServer`: <https://wiki.facepunch.com/gmod/engine.CloseServer>

If closing is unavailable, the terminal-side driver should still treat `result.json` as the end of the test. Process shutdown is useful, but it must not be required for validating the render output.

## Failure Handling

The runner should distinguish these failure classes:

- `fail`: a render metric completed and did not meet the threshold.
- `error`: the harness could not complete the case.
- `timeout`: the agent did not observe a terminal result before the requested timeout.
- `unsupported`: the current Garry's Mod state cannot run the requested case.

Every failure should include:

- case name;
- pass name;
- render target or artifact name when relevant;
- metric name;
- expected value or threshold;
- observed value;
- diagnostic capture path when available.

Example failure:

```json
{
  "case": "depth_multi_imesh",
  "pass": "InkPrep",
  "target": "InkPrepDepth",
  "metric": "front_owner_mismatch_pixels",
  "expected": 0,
  "observed": 37,
  "capture": "captures/depth_multi_imesh_owner.png"
}
```

## Minimum Acceptance Criteria

An autonomous render-test setup is ready when all of the following are true:

- The real runner is callable as a Lua function.
- The console command is only a manual wrapper.
- A request file can start a run without human console input.
- The runner waits for renderer readiness before executing.
- The run writes `status.json` while active and `result.json` when complete.
- `result.json` contains terminal pass, fail, error, timeout, or unsupported state.
- Every render correctness case produces metrics.
- PNG captures are available for diagnosis.
- The coding agent can decide success or failure by reading files from `data/splashsweps/render_tests/`.

This setup makes autonomous validation possible even though Garry's Mod itself remains an interactive graphical application.
