param([switch]$Baseline)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$oldState = $env:XDG_STATE_HOME
$oldBaseline = $env:SPLASHSWEPS_LSP_BASELINE
try {
    Push-Location $root
    # Keep trust and editor state inside the ignored work directory, not the
    # user's real trust database. Normal user plugins/configuration still load.
    $env:XDG_STATE_HOME = Join-Path $root '.opencode/work/nvim-lsp-simple/state'
    $env:SPLASHSWEPS_LSP_BASELINE = if ($Baseline) { '1' } else { '0' }
    & nvim --headless -u NONE -i NONE -n -c "lua vim.fn.mkdir(vim.fn.stdpath('state'), 'p'); assert(vim.secure.trust({action='allow',path='.nvim.lua'}))" -c 'qa!'
    if ($LASTEXITCODE -ne 0) { throw 'Could not trust the project exrc in isolated editor state' }
    if (-not $Baseline) {
        $luals = (Get-Command lua-language-server -CommandType Application | Select-Object -First 1).Source
        & $luals -e "dofile('tools/luals/realm-check.lua')"
        if ($LASTEXITCODE -ne 0) { throw 'LuaLS parser regression check failed' }
        & nvim --headless -u NONE -i NONE -n -c 'luafile tools/luals/reload-check.lua'
        if ($LASTEXITCODE -ne 0) { throw 'Running native LuaLS configuration check failed' }
    }
    & nvim --headless -i NONE -n -c 'luafile tools/luals/check.lua'
    if ($LASTEXITCODE -ne 0) { throw 'LuaLS integration check failed; see .opencode/work/nvim-lsp-simple' }
} finally {
    Pop-Location
    $env:XDG_STATE_HOME = $oldState
    $env:SPLASHSWEPS_LSP_BASELINE = $oldBaseline
}
