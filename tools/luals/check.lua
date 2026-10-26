-- Run through check.ps1: real Neovim, normal user config, isolated state, real LuaLS.
local root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p"))))
local baseline = vim.env.SPLASHSWEPS_LSP_BASELINE == "1"
local work = root .. "/.opencode/work/nvim-lsp-simple/" .. (baseline and "baseline-" or "check-") .. os.date("%Y%m%d-%H%M%S")
-- Persistent undo remains enabled; only its storage is moved beside our fixtures
-- to avoid Windows path limits from encoding the full path under isolated state.
vim.o.undodir = "."
vim.fn.mkdir(work, "p")
local snapshots, scope_uris, created, timings = {}, {}, {}, {}
local observations = assert(io.open(work .. "/observations.jsonl", "w"))
local function record(event, data)
    observations:write(vim.json.encode({ event = event, data = data }) .. "\n")
    observations:flush()
end
-- Same comparison key as path_key in .nvim-example.lua.
local function key(uri)
    local path = vim.fs.normalize(vim.uri_to_fname(uri))
    return vim.o.fileignorecase and path:lower() or path
end
local function observe(client)
    local old = client._simple_check
    if not old then
        record("client", { name = client.name, id = client.id, root = tostring(client.root_dir),
            root_type = type(client.root_dir), cmd = client.config.cmd })
    end
    local current = client.handlers["textDocument/publishDiagnostics"] or vim.lsp.handlers["textDocument/publishDiagnostics"]
    if not old or old.diagnostics ~= current then
        local wrapper = function(err, result, ctx, config)
            if result then
                snapshots[client.name] = snapshots[client.name] or {}
                snapshots[client.name][key(result.uri)] = result.diagnostics
                record("diagnostics", { client = client.name, result = result })
            end
            return current(err, result, ctx, config)
        end
        client.handlers["textDocument/publishDiagnostics"] = wrapper
        client._simple_check = { diagnostics = wrapper }
    end
    local handler = client.handlers["workspace/configuration"] or vim.lsp.handlers["workspace/configuration"]
    if client._simple_check.configuration ~= handler then
        local wrapper = function(err, params, ctx, config)
            local response = handler(err, params, ctx, config)
            for _, item in ipairs(params.items or {}) do
                if item.scopeUri then
                    scope_uris[client.name] = item.scopeUri
                end
            end
            record("configuration", { client = client.name, params = params, response = response })
            return response
        end
        client.handlers["workspace/configuration"] = wrapper
        client._simple_check.configuration = wrapper
    end
end
vim.api.nvim_create_autocmd({ "LspAttach", "LspNotify" }, {
    callback = function(event)
        local client = event.data.client_id and vim.lsp.get_client_by_id(event.data.client_id)
        if client and client.name:find("lua") then
            observe(client)
        end
    end,
})
local function wait_for(description, predicate, timeout)
    assert(vim.wait(timeout or 45000, predicate, 25), "timeout: " .. description)
end
local function fixture(relative, text)
    local path = root .. "/" .. relative
    assert(not vim.uv.fs_stat(path), "refusing to overwrite " .. path)
    local undo = vim.fn.undofile(path)
    assert(not vim.uv.fs_stat(undo), "refusing to overwrite " .. undo)
    created[#created + 1] = undo
    vim.fn.writefile(vim.split(text, "\n", { plain = true }), path)
    created[#created + 1] = path
    return path
end
local function open(path)
    vim.cmd.edit(vim.fn.fnameescape(path))
    return vim.api.nvim_get_current_buf()
end
local function client_for(realm)
    local clients = vim.tbl_filter(function(client) return not client:is_stopped() end,
        vim.lsp.get_clients { name = "lua_ls_gmod_" .. realm })
    assert(#clients == 1, "expected one " .. realm .. " client, got " .. #clients)
    return clients[1]
end
local function diagnostics(name, path)
    return (snapshots[name] or {})[key(vim.uri_from_fname(path))] or {}
end
local function contains(name, path, needle)
    for _, diagnostic in ipairs(diagnostics(name, path)) do
        if diagnostic.message:find(needle, 1, true) or diagnostic.code == needle then
            return true
        end
    end
    return false
end
local function expect(name, path, needle, present)
    assert(contains(name, path, needle) == present, name .. " " .. needle .. " expected " .. tostring(present)
        .. "\n" .. vim.inspect(diagnostics(name, path)))
end
local function names(bufnr)
    local clients = vim.tbl_filter(function(client) return not client:is_stopped() end,
        vim.lsp.get_clients { bufnr = bufnr })
    local result = vim.tbl_map(function(client) return client.name end, clients)
    table.sort(result)
    return table.concat(result, ",")
end
local function request(client, method, params, bufnr)
    local response = client:request_sync(method, params, 10000, bufnr)
    record("response", { client = client.name, method = method, params = params, response = response })
    assert(response and not response.err, "failed request " .. method .. ": " .. vim.inspect(response))
    return response.result
end
local function location(bufnr, needle)
    for row, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)) do
        local column = line:find(needle, 1, true)
        if column then
            return row - 1, column - 1
        end
    end
    error("missing token " .. needle)
end
local function check_position(name, path, bufnr, needle)
    local row, column = location(bufnr, needle)
    local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, true)[1]
    local expected = vim.str_utfindex(line, "utf-16", column)
    for _, diagnostic in ipairs(diagnostics(name, path)) do
        if diagnostic.message:find(needle, 1, true) then
            assert(diagnostic.range.start.line == row and diagnostic.range.start.character == expected,
                "wrong original position: " .. vim.inspect(diagnostic))
            return
        end
    end
    error("no position for " .. needle)
end

local function run()
    assert(vim.o.exrc, "normal configuration must enable exrc")
    assert(vim.fn.exists(":GLuaLsp") == 2, "project exrc did not load automatically")
    -- Open game Lua first: do not pre-load LazyVim's normal Lua configuration.
    for _, name in ipairs { "lua_ls_gmod_server", "lua_ls_gmod_client" } do
        local config = vim.lsp.config[name]
        assert(config, "missing configuration " .. name)
        local cmd = vim.deepcopy(config.cmd)
        cmd[#cmd + 1] = "--logpath=" .. work .. "/" .. name
        local changes = { cmd = cmd }
        if baseline and name ~= "lua_ls" then
            changes.settings = { Lua = { runtime = { plugin = {}, pluginArgs = {} } } }
        end
        vim.lsp.config(name, changes)
    end
    record("startup", { version = tostring(vim.version()), baseline = baseline, root = root })
    -- This file is deliberately never opened: workspace reads must be transformed too.
    local unopened = fixture("lua/splashsweps/shared/__lsp_simple_unopened.lua", ([[
if SERVER then return end
function LspSimpleProbe.Action() return 2 end]]):gsub("\n", "\r\n"))
    local server_path = fixture("lua/splashsweps/server/__lsp_simple_server.lua", [[
function LspSimpleProbe.Action() return 1 end
function LspSimpleProbe.Clash() end
function LspSimpleProbe.Clash() end
LspServerFileMarker()]])
    local client_path = fixture("lua/splashsweps/client/__lsp_simple_client.lua", [[
surface.SetDrawColor(255, 255, 255)
LspClientFileMarker()]])
    local text = [[---@class LspSimpleProbe
LspSimpleProbe = {}
LspLiveMarker0()
if SERVER then
    AddCSLuaFile()
    LspServerOnlyMissing()
else
    surface.SetDrawColor(255, 255, 255)
    LspClientOnlyMissing()
end
---@return number
local function chosen()
    if SERVER then return 1 else return 2 end
end
---@return number
local function genuinelyMissing()
    if LspRuntimeCondition() then return 1 end
end
print(chosen(), genuinelyMissing())
do
    local SERVER = false
    if SERVER then LspShadowMissing() end
end
if LspNestedCondition() then
    if SERVER then return end
    LspNestedClientMissing()
end
LspAfterNestedMissing()
if SERVER then
    local function nested() return 1 end
    print(nested())
end
LspAfterFunctionMissing()
if not SERVER then LspNegatedMissing() end
if SERVER and LspComplexCondition() then LspComplexBodyMissing() end
local value = SERVER and LspExpressionMissing() or 0
print(value)
if SERVER then local a = 1; print(a) else local b = 2; print(b) end
if SERVER then
    LspFirstArmMissing()
elseif LspElseifCondition() then
    LspElseifBodyMissing()
else
    LspElseMissing()
end
local caption = "日本語"; LspUnicodeMissing()
print(caption)
local label = "日本語"; function LspSimpleProbe.SharedOnly() return 3 end; print(label)
local sharedValue = LspSimpleProbe.SharedOnly(); print(sharedValue)
local actionValue = LspSimpleProbe.Action(); print(actionValue)
for n = 1, 2 do
    if n == 1 then continue end
    print(n)
end
]]
    local shared_path = fixture("lua/splashsweps/shared/__lsp_simple_shared.lua", text)
    local shared = open(shared_path)
    wait_for("both shared connections", function()
        return names(shared) == "lua_ls_gmod_client,lua_ls_gmod_server"
    end)
    local server = open(server_path)
    local client = open(client_path)
    wait_for("realm-specific connections", function()
        return names(server) == "lua_ls_gmod_server" and names(client) == "lua_ls_gmod_client"
    end)
    local shared_names = { "lua_ls_gmod_server", "lua_ls_gmod_client" }
    wait_for("initial real diagnostics", function()
        return contains(shared_names[1], shared_path, "LspLiveMarker0")
            and contains(shared_names[2], shared_path, "LspLiveMarker0")
            and contains(shared_names[1], server_path, "LspServerFileMarker")
            and contains(shared_names[2], client_path, "LspClientFileMarker")
    end)
    for _, name in ipairs(shared_names) do
        expect(name, shared_path, "LspServerOnlyMissing", baseline or name == shared_names[1])
        expect(name, shared_path, "LspClientOnlyMissing", baseline or name == shared_names[2])
        expect(name, shared_path, "LspNestedClientMissing", baseline or name == shared_names[2])
        for _, marker in ipairs { "LspShadowMissing", "LspAfterNestedMissing", "LspAfterFunctionMissing",
            "LspNegatedMissing", "LspComplexBodyMissing", "LspExpressionMissing", "LspUnicodeMissing" } do
            expect(name, shared_path, marker, true)
        end
        expect(name, shared_path, "missing-return", true)
        expect(name, shared_path, "trailing-space", false)
        check_position(name, shared_path, shared, "LspUnicodeMissing")
        -- Only the deliberately incomplete function may have missing-return.
        local count = 0
        for _, diagnostic in ipairs(diagnostics(name, shared_path)) do
            if diagnostic.code == "missing-return" then count = count + 1 end
        end
        assert(count == 1, "false missing-return: " .. vim.inspect(diagnostics(name, shared_path)))
        if not baseline then
            expect(name, shared_path, "LspFirstArmMissing", name == shared_names[1])
            expect(name, shared_path, "LspElseifBodyMissing", name == shared_names[2])
            expect(name, shared_path, "LspElseifCondition", name == shared_names[2])
        end
    end
    expect(shared_names[1], shared_path, "Undefined field `SetDrawColor`.", baseline)
    -- The supplied definitions expose AddCSLuaFile in both realms.
    expect(shared_names[2], shared_path, "Undefined global `AddCSLuaFile`.", false)
    expect(shared_names[1], server_path, "Duplicate field `Clash`.", true)
    expect(shared_names[1], server_path, "Duplicate field `Action`.", baseline)
    local function check_definition(realm, field, expected_path, expected_text)
        local c = client_for(realm)
        local row = location(shared, "local " .. (field == "SharedOnly" and "sharedValue" or "actionValue"))
        local line = vim.api.nvim_buf_get_lines(shared, row, row + 1, true)[1]
        local column = assert(line:find(field, 1, true)) - 1
        local definitions = request(c, "textDocument/definition", {
            textDocument = { uri = vim.uri_from_fname(shared_path) },
            position = { line = row, character = vim.str_utfindex(line, "utf-16", column) },
        }, shared)
        assert(definitions and #definitions == 1, "definition missing or duplicated: " .. vim.inspect(definitions))
        local target = definitions[1]
        assert(key(target.targetUri or target.uri) == key(vim.uri_from_fname(expected_path)), "wrong definition file")
        for target_row, target_line in ipairs(vim.split(expected_text, "\n", { plain = true })) do
            local start = target_line:find("function LspSimpleProbe." .. field, 1, true)
            if start then
                local name_offset = start - 1 + #"function LspSimpleProbe."
                local target_column = vim.str_utfindex(target_line, "utf-16", name_offset)
                local range = target.targetSelectionRange or target.range
                assert(range.start.line == target_row - 1 and range.start.character == target_column
                    and range["end"].line == target_row - 1 and range["end"].character == target_column + #field,
                    "definition moved away from original source: " .. vim.inspect(target))
                return
            end
        end
        error("expected definition absent from test input")
    end
    for _, realm in ipairs { "server", "client" } do
        check_definition(realm, "SharedOnly", shared_path, text)
        if realm == "client" or not baseline then
            local expected = realm == "client" and unopened or server_path
            check_definition(realm, "Action", expected, table.concat(vim.fn.readfile(expected), "\n"))
        end
    end
    record("initial-pass", { unopened = unopened })

    -- Real buffer edits; the changing marker prevents stale diagnostics passing.
    vim.api.nvim_set_current_buf(shared)
    for index = 1, 8 do
        local previous = "LspLiveMarker" .. (index - 1)
        local next_marker = "LspLiveMarker" .. index
        local start = vim.uv.hrtime()
        local lines = vim.api.nvim_buf_get_lines(shared, 0, -1, true)
        for row, line in ipairs(lines) do lines[row] = line:gsub(previous, next_marker) end
        vim.api.nvim_buf_set_lines(shared, 0, -1, true, lines)
        wait_for("edited diagnostics " .. index, function()
            return contains(shared_names[1], shared_path, next_marker) and contains(shared_names[2], shared_path, next_marker)
        end, 15000)
        timings[#timings + 1] = (vim.uv.hrtime() - start) / 1e6
        for _, name in ipairs(shared_names) do check_position(name, shared_path, shared, "LspUnicodeMissing") end
    end
    if not baseline then
        local function branch_is_swapped(swapped)
            for _, name in ipairs(shared_names) do
                local server_arm = (name == shared_names[1]) ~= swapped
                if contains(name, shared_path, "LspServerOnlyMissing") ~= server_arm
                    or contains(name, shared_path, "LspClientOnlyMissing") == server_arm then
                    return false
                end
            end
            return true
        end
        vim.api.nvim_feedkeys(vim.keycode("i<C-G>u<Esc>"), "nx", false)
        local row = location(shared, "if SERVER then")
        vim.api.nvim_win_set_cursor(0, { row + 1, 3 })
        vim.cmd("normal! ciwCLIENT")
        wait_for("edited realm condition", function() return branch_is_swapped(true) end)
        vim.cmd.undo()
        wait_for("undo realm condition", function() return branch_is_swapped(false) end)
        vim.cmd.redo()
        wait_for("redo realm condition", function() return branch_is_swapped(true) end)
        vim.cmd.undo()
        wait_for("restore realm condition", function() return branch_is_swapped(false) end)
        -- A missing end is an original syntax error, not something to hide.
        local end_row
        for index, line in ipairs(vim.api.nvim_buf_get_lines(shared, 0, -1, true)) do
            if line == "end" then end_row = index; break end
        end
        assert(end_row, "no closing if end")
        vim.api.nvim_win_set_cursor(0, { end_row, 0 })
        vim.cmd("normal! dd")
        local function has_syntax_error(name)
            for _, diagnostic in ipairs(diagnostics(name, shared_path)) do
                if diagnostic.severity == 1 then return true end
            end
            return false
        end
        wait_for("original syntax errors", function()
            return has_syntax_error(shared_names[1]) and has_syntax_error(shared_names[2])
        end)
        vim.cmd.undo()
        wait_for("syntax repair", function()
            return not has_syntax_error(shared_names[1]) and not has_syntax_error(shared_names[2])
                and branch_is_swapped(false)
        end)
        assert(table.concat(vim.fn.readfile(shared_path), "\n") == text,
            "analysis modified the source file on disk")
        vim.cmd.GLuaServer()
        wait_for("force server", function() return names(shared) == "lua_ls_gmod_server" end)
        vim.cmd.GLuaAutoRealm()
        wait_for("restore both realms", function() return names(shared) == "lua_ls_gmod_client,lua_ls_gmod_server" end)
        -- Reload also refreshes the LuaLS plugin. No stale clients or handlers.
        local function shader_template_count()
            local templates
            require("overseer.template").list({ dir = root }, function(result) templates = result end)
            wait_for("Overseer template enumeration", function() return templates ~= nil end)
            local count = 0
            for _, template in ipairs(templates) do
                if template.name == "ShaderCompile" then count = count + 1 end
            end
            return count
        end
        assert(shader_template_count() == 1, "initial ShaderCompile registration is missing or duplicated")
        vim.cmd.luafile(root .. "/.nvim.lua")
        assert(shader_template_count() == 1, "ShaderCompile duplicated after reload")
        wait_for("reload both realms", function()
            return names(shared) == "lua_ls_gmod_client,lua_ls_gmod_server"
                and #vim.lsp.get_clients { name = "lua_ls_gmod_server" } == 1
                and #vim.lsp.get_clients { name = "lua_ls_gmod_client" } == 1
        end)
        -- Rename across the realm boundary, then outside game Lua, then edit.
        local renamed = root .. "/lua/splashsweps/client/__lsp_simple_renamed.lua"
        assert(not vim.uv.fs_stat(renamed))
        created[#created + 1] = renamed
        assert(not vim.uv.fs_stat(vim.fn.undofile(renamed)))
        created[#created + 1] = vim.fn.undofile(renamed)
        vim.api.nvim_set_current_buf(server)
        vim.cmd("saveas! " .. vim.fn.fnameescape(renamed))
        wait_for("server to client rename", function() return names(server) == "lua_ls_gmod_client" end)
        local outside = root .. "/__lsp_simple_native.lua"
        assert(not vim.uv.fs_stat(outside))
        created[#created + 1] = outside
        assert(not vim.uv.fs_stat(vim.fn.undofile(outside)))
        created[#created + 1] = vim.fn.undofile(outside)
        vim.cmd("saveas! " .. vim.fn.fnameescape(outside))
        vim.api.nvim_buf_set_lines(server, 0, -1, true, { "surface.SetDrawColor(1, 2, 3)", "LspNativeMissing()", "LspSimpleProbe.SharedOnly()" })
        wait_for("native only", function() return names(server) == "lua_ls" end)
        wait_for("native game API is undefined", function()
            return contains("lua_ls", outside, "surface") and contains("lua_ls", outside, "LspNativeMissing") and contains("lua_ls", outside, "LspSimpleProbe")
        end)
        local native = vim.lsp.get_clients { name = "lua_ls" }[1]
        wait_for("actual configuration scope URI", function() return scope_uris.lua_ls ~= nil end)
        local library = request(native, "workspace/executeCommand", {
            command = "lua.getConfig", arguments = { { uri = scope_uris.lua_ls, key = "Lua.workspace.library" } },
        }, server)
        assert(type(library) == "table" and vim.islist(library) and #library > 0,
            "missing effective library: " .. vim.inspect(library))
        for _, path in ipairs(library) do
            assert(not key(vim.uri_from_fname(path)):find("/splashsweps/lua", 1, true), "game library leaked: " .. path)
        end
        for _, realm in ipairs { "server", "client" } do
            local symbols = request(client_for(realm), "textDocument/documentSymbol", {
                textDocument = { uri = vim.uri_from_fname(outside) },
            }, server)
            assert(symbols == vim.NIL or symbols == nil or #symbols == 0, "outside definitions leaked into game workspace")
        end
        -- Reverse direction must restore game-only connections.
        vim.cmd("saveas! " .. vim.fn.fnameescape(renamed))
        wait_for("native back to client", function() return names(server) == "lua_ls_gmod_client" end)
    end
    assert(vim.v.errmsg == "", "editor callback error: " .. vim.v.errmsg)
    table.sort(timings)
    local middle = math.floor(#timings / 2)
    local median = #timings % 2 == 0 and (timings[middle] + timings[middle + 1]) / 2 or timings[middle + 1]
    record("pass", { edit_ms = timings, median_ms = median, max_ms = timings[#timings] })
    print("PASS " .. (baseline and "baseline" or "check") .. " edit median/max ms "
        .. string.format("%.1f/%.1f", median, timings[#timings]))
end
local function main()
    local ok, err = xpcall(run, debug.traceback)
    if not ok then record("failure", { message = err }); io.stderr:write(err .. "\n") end
    for _, client in ipairs(vim.lsp.get_clients()) do client:stop() end
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.tbl_contains(created, vim.api.nvim_buf_get_name(bufnr)) then
            pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
        end
    end
    vim.wait(3000, function() return #vim.lsp.get_clients() == 0 end, 25)
    for _, path in ipairs(created) do
        local removed = vim.wait(2000, function()
            vim.fn.delete(path)
            return not vim.uv.fs_stat(path)
        end, 25)
        if not removed then
            ok = false
            io.stderr:write("fixture cleanup failed: " .. path .. "\n")
            record("cleanup-failure", { path = path })
        end
    end
    observations:close()
    vim.cmd(ok and "qa!" or "cq!")
end
if vim.v.vim_did_enter == 1 then
    vim.schedule(main)
else
    vim.api.nvim_create_autocmd("VimEnter", { once = true, callback = function() vim.schedule(main) end })
end
