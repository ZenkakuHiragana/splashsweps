
## Project summary

(TBD)

## Shader test harness

- With `luals` and `luajit` available on the `$PATH`, lint the whole codebase by the following commands:
  - For serverside: `luals --check="$PWD/lua" --configpath="$PWD/luals.check.server.lua"`
  - For clientside: `luals --check="$PWD/lua" --configpath="$PWD/luals.check.client.lua"`
  - `--check_format` and `--checklevel` are optional, but `--checklevel` must be above `Warning` level (which is the default).
- To compile a pair of vertex shader and pixel shader, run `shaders/src/build.ps1 path/to/my_shader.hlsl`.
  - It compiles both shaders and generates `shaders/fxc/splashsweps/my_shader.vcs` and `shaders/fxc/splashsweps/X_my_shader.vcs`,
    where `X` is an ever-increasing number and is required to hot-reload the shaders.
  - If `materials/splashsweps/shaders/my_shader.vmt` exists,
    `build.ps1` also edits it to change `$pixshader` and `$vertexshader` to the path to the `X` prefixed VCS files
    in order to automatically reload the shaders.
- To test the shader, you have to `touch lua/splashsweps/client/tests/*.lua`
  to trigger auto-refresh the Lua file and run desired tests in-game.
- Test results should be written as a file under `../../data/splashsweps/render-tests/report.json`.
  You must always `Read` the result after running tests.
