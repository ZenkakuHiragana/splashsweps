-- Real native LuaLS starts before the project exrc; no user plugins are loaded.
local root = vim.fs.normalize(vim.fn.getcwd())
local work = root .. "/.opencode/work/nvim-lsp-simple/reload-" .. os.date("%Y%m%d-%H%M%S")
vim.fn.mkdir(work, "p")
local path = root .. "/__lsp_simple_reload.lua"
-- Same comparison as path_key in .nvim-example.lua.
local function same_path(a, b)
    a, b = vim.fs.normalize(a), vim.fs.normalize(b)
    if vim.o.fileignorecase then
        a, b = a:lower(), b:lower()
    end
    return a == b
end
local client, bufnr, scope, latest
local created = false
local events = {}
local function record(event, data)
    events[#events + 1] = { event = event, data = data }
end
local function wait_for(description, predicate)
    assert(vim.wait(45000, predicate, 25), "timeout: " .. description)
end
local function has(needle)
    for _, diagnostic in ipairs(latest and latest.diagnostics or {}) do
        if diagnostic.message:find(needle, 1, true) then return true end
    end
    return false
end
local function effective_library()
    local response = client:request_sync("workspace/executeCommand", {
        command = "lua.getConfig", arguments = { { uri = scope, key = "Lua.workspace.library" } },
    }, 10000, bufnr)
    record("effective-library", response)
    assert(response and not response.err and type(response.result) == "table" and vim.islist(response.result),
        "invalid effective library response: " .. vim.inspect(response))
    return response.result
end
local function run()
    assert(not vim.uv.fs_stat(path), "refusing to overwrite " .. path)
    vim.fn.writefile({ "local saved = surface", "print(saved)", "LspReloadMarker0()" }, path)
    created = true
    vim.cmd.edit(vim.fn.fnameescape(path))
    bufnr = vim.api.nvim_get_current_buf()
    vim.bo[bufnr].filetype = "lua"
    local configuration = vim.lsp.handlers["workspace/configuration"]
    local diagnostics = vim.lsp.handlers["textDocument/publishDiagnostics"]
    vim.lsp.config("lua_ls", {
        cmd = { vim.fn.exepath("lua-language-server"), "--logpath=" .. work .. "/native" },
        root_dir = root,
        filetypes = { "lua" },
        settings = { Lua = { workspace = {
            checkThirdParty = false,
            ignoreDir = { root .. "/lua" },
            library = { root .. "/lua/types/types" },
        } } },
        handlers = {
            ["workspace/configuration"] = function(err, params, ctx, config)
                for _, item in ipairs(params.items or {}) do scope = item.scopeUri or scope end
                local response = configuration(err, params, ctx, config)
                record("configuration", { params = params, response = response })
                return response
            end,
            ["textDocument/publishDiagnostics"] = function(err, result, ctx, config)
                if result and same_path(vim.uri_to_fname(result.uri), path) then
                    latest = result
                    record("diagnostics", result)
                end
                return diagnostics(err, result, ctx, config)
            end,
        },
    })
    local id = assert(vim.lsp.start(vim.deepcopy(vim.lsp.config.lua_ls), { bufnr = bufnr }))
    client = assert(vim.lsp.get_client_by_id(id))
    wait_for("old game library loaded", function() return scope ~= nil and has("LspReloadMarker0") end)
    local before = effective_library()
    assert(#before == 1 and not has("Undefined global `surface`."), "initial game library was not loaded")
    vim.cmd.luafile(root .. "/.nvim.lua")
    vim.api.nvim_buf_set_lines(bufnr, 2, 3, true, { "LspReloadMarker1()" })
    wait_for("native realm separation after applying exrc", function()
        return has("LspReloadMarker1") and has("Undefined global `surface`.")
    end)
    local after = effective_library()
    assert(#after == 0, "game library remains in the running server")
    assert(not client:is_stopped() and vim.lsp.get_client_by_id(id) == client, "native client was replaced")
    assert(vim.v.errmsg == "", "editor callback error: " .. vim.v.errmsg)
    record("pass", { client_id = id, before = before, after = after })
    print("PASS native reload; same client, game library removed")
end
local function main()
    local ok, err = xpcall(run, debug.traceback)
    if not ok then record("failure", { message = err }); io.stderr:write(err .. "\n") end
    -- Teardown must not let buffer switches start another managed client.
    pcall(vim.api.nvim_del_augroup_by_name, "splashsweps_gmod_lsp")
    for _, c in ipairs(vim.lsp.get_clients { _uninitialized = true }) do c:stop() end
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then vim.api.nvim_buf_delete(bufnr, { force = true }) end
    vim.wait(3000, function() return #vim.lsp.get_clients { _uninitialized = true } == 0 end, 25)
    if created then
        local removed = vim.wait(2000, function()
            vim.fn.delete(path)
            return not vim.uv.fs_stat(path)
        end, 25)
        if not removed then ok = false; record("cleanup-failure", { path = path }) end
    end
    local lines = vim.tbl_map(vim.json.encode, events)
    vim.fn.writefile(lines, work .. "/observations.jsonl")
    vim.cmd(ok and "qa!" or "cq!")
end
vim.api.nvim_create_autocmd("VimEnter", { once = true, callback = function() vim.schedule(main) end })
