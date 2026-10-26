-- Project-local LuaLS configuration for Neovim 0.12+.
-- Copy to .nvim.lua (or symlink it), enable 'exrc', and :trust the file.
-- Game Lua uses separate server/client workspaces; other Lua keeps lua_ls.

-- A project reached through a symlinked directory has two spellings. LuaLS
-- must only see the resolved one: its own file watcher reports changes under a
-- symlinked workspace by their resolved paths, which then load as extra files
-- outside the workspace, without libraries, and break the workspace's types.
-- Lua buffers named through the link are therefore reopened by resolved path.
local source_root = vim.fs.normalize(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")))
local root = vim.fs.normalize(vim.uv.fs_realpath(source_root) or source_root)
local group = vim.api.nvim_create_augroup("splashsweps_gmod_lsp", { clear = true })
local forced_realms = {}
local buffer_uris = {}
local initialized = false
local native_root_wrapper
local native_generation = {}

-- Comparison key of a path. vim.fs.normalize unifies separators and the drive
-- letter; case is folded only where Neovim itself treats file names that way.
local function path_key(path)
    path = vim.fs.normalize(path or "")
    return vim.o.fileignorecase and path:lower() or path
end

local root_key = path_key(root)
local source_key = path_key(source_root)

-- Paths spelled through the unresolved project directory (configured libraries,
-- the current directory) name the same files as the resolved root. Only the
-- project prefix is mapped: links inside it, such as lua/types, stay as spelled.
local function normalize(path)
    path = path_key(path)
    if source_key ~= root_key
        and (path == source_key or path:sub(1, #source_key + 1) == source_key .. "/") then
        path = root_key .. path:sub(#source_key + 1)
    end
    return path
end
local lua_root = root_key .. "/lua"

local function within(path, directory)
    path = normalize(path)
    return path == directory or path:sub(1, #directory + 1) == directory .. "/"
end

local function is_gmod(path)
    return within(path, lua_root)
end

-- The resolved path of a project file named through the symlinked spelling.
local function resolved_alias(path)
    local key = path_key(path)
    if source_key ~= root_key and (key == source_key or key:sub(1, #source_key + 1) == source_key .. "/") then
        return root .. vim.fs.normalize(path):sub(#source_root + 1)
    end
end

-- Renames a buffer named through the link to its resolved path, as
-- `:edit lua/...` names it already. Neovim identifies both spellings as one
-- file, so the buffer itself is renamed rather than another one opened.
local function reopen_resolved(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end
    local path = resolved_alias(vim.api.nvim_buf_get_name(bufnr))
    if not path then
        return
    end
    if vim.bo[bufnr].modified then
        vim.notify("Unsaved buffer named through a symlink gets no LSP; reopen it as " .. path, vim.log.levels.WARN)
        return
    end
    vim.api.nvim_buf_set_name(bufnr, path)
    -- A renamed buffer counts as not edited, so :write would refuse it.
    -- Reading it again under the new name clears that.
    vim.api.nvim_buf_call(bufnr, function()
        vim.cmd "silent keepalt keepjumps edit"
    end)
end

local function is_project_client(client)
    return type(client.root_dir) == "string" and normalize(client.root_dir) == root_key
end

local function is_managed(client)
    return client.name == "lua_ls"
        or client.name == "lua_ls_gmod_server"
        or client.name == "lua_ls_gmod_client"
end

-- These exclusions are also used by the corresponding .luarc files. Read them
-- instead of keeping another list of server/client directories in this file.
local realm_exclusions = {}
for _, realm in ipairs { "server", "client" } do
    local path = root .. "/.luarc." .. realm .. ".json"
    local config = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
    realm_exclusions[realm] = config["workspace.ignoreDir"] or {}
end

local function realms_for(bufnr)
    if forced_realms[bufnr] then
        return { forced_realms[bufnr] }
    end
    local path = vim.api.nvim_buf_get_name(bufnr)
    local realms = {}
    for _, realm in ipairs { "server", "client" } do
        local excluded = false
        for _, entry in ipairs(realm_exclusions[realm]) do
            -- The project's ignoreDir entries are literal relative paths.
            if within(path, normalize(root .. "/" .. entry)) then
                excluded = true
                break
            end
        end
        if not excluded then
            realms[#realms + 1] = realm
        end
    end
    return realms
end

local function stabilize_gmod_highlight(bufnr)
    if vim.treesitter and vim.treesitter.stop then
        pcall(vim.treesitter.stop, bufnr)
    end
    vim.bo[bufnr].syntax = "lua"
end

local function native_workspace(workspace)
    workspace = vim.deepcopy(workspace or {})
    workspace.ignoreDir = workspace.ignoreDir or {}
    local ignored = root .. "/lua"
    if not vim.tbl_contains(workspace.ignoreDir, ignored) then
        table.insert(workspace.ignoreDir, ignored)
    end
    workspace.library = vim.tbl_filter(function(path)
        local absolute = vim.fs.abspath(path)
        return not is_gmod(absolute)
    end, workspace.library or {})
    return workspace
end

local function native_settings(settings)
    settings = vim.deepcopy(settings or {})
    settings.Lua = settings.Lua or {}
    settings.Lua.workspace = native_workspace(settings.Lua.workspace)
    return settings
end

local function refresh_native_configuration(client, guard)
    if client.initialized and not client:is_stopped() and not guard.notified then
        -- LspNotify also invokes our guard; this notification must not repeat.
        guard.notified = true
        client:notify("workspace/didChangeConfiguration", { settings = { Lua = {} } })
    end
end

local function guard_native_configuration(client, notification_pending)
    if client.name ~= "lua_ls" or not is_project_client(client) then
        return
    end
    client.settings = native_settings(client.settings)
    local current = client.handlers["workspace/configuration"] or vim.lsp.handlers["workspace/configuration"]
    local previous = client._splashsweps_configuration
    if previous and current == previous.wrapper then
        if previous.generation == native_generation then
            previous.notified = previous.notified or notification_pending
            refresh_native_configuration(client, previous)
            return
        end
        current = previous.original
    end
    local wrapper = function(err, params, ctx, config)
        local response = current(err, params, ctx, config)
        if err or not response then
            return response
        end
        response = vim.deepcopy(response)
        for index, item in ipairs(params.items or {}) do
            local value = response[index]
            if item.section == "Lua" then
                value = value ~= vim.NIL and value or {}
                value.workspace = native_workspace(value.workspace)
                response[index] = value
            elseif item.section == "Lua.workspace" then
                response[index] = native_workspace(value ~= vim.NIL and value or {})
            elseif item.section == "Lua.workspace.library" then
                response[index] = native_workspace({ library = value ~= vim.NIL and value or {} }).library
            elseif item.section == "Lua.workspace.ignoreDir" then
                response[index] = native_workspace({ ignoreDir = value ~= vim.NIL and value or {} }).ignoreDir
            end
        end
        return response
    end
    client.handlers["workspace/configuration"] = wrapper
    local guard = { wrapper = wrapper, original = current, generation = native_generation, notified = notification_pending or false }
    client._splashsweps_configuration = guard
    refresh_native_configuration(client, guard)
end

local function configure_native()
    local config = vim.lsp.config.lua_ls
    if not config then
        return
    end
    -- Keep the user's normal root discovery everywhere except game Lua. Store
    -- the original callback so sourcing this exrc again does not nest wrappers.
    local previous = config._splashsweps_native
    local original = config.root_dir
    if native_root_wrapper and original == native_root_wrapper then
        for _, client in ipairs(vim.lsp.get_clients { name = "lua_ls", _uninitialized = true }) do
            guard_native_configuration(client)
        end
        return
    end
    if previous and original == previous.wrapper then
        original = previous.original
    end
    local wrapper = function(bufnr, on_dir)
        local name = vim.api.nvim_buf_get_name(bufnr)
        if not is_gmod(name) and not resolved_alias(name) then
            if type(original) == "function" then
                original(bufnr, function(directory)
                    if not is_gmod(vim.api.nvim_buf_get_name(bufnr)) then
                        on_dir(directory or (within(vim.api.nvim_buf_get_name(bufnr), root_key) and root or nil))
                    end
                end)
            elseif type(original) == "string" then
                on_dir(original)
            else
                on_dir(vim.fs.root(bufnr, config.root_markers or { ".git" }) or root)
            end
        end
    end
    native_root_wrapper = wrapper
    vim.lsp.config("lua_ls", {
        root_dir = wrapper,
        settings = native_settings(config.settings),
        _splashsweps_native = { original = original, wrapper = wrapper },
    })
    for _, client in ipairs(vim.lsp.get_clients { name = "lua_ls", _uninitialized = true }) do
        guard_native_configuration(client)
    end
end

local function ensure_gmod_configs()
    if initialized then
        return true
    end
    local luals = vim.fn.exepath "lua-language-server"
    if luals == "" then
        return false
    end
    for _, realm in ipairs { "server", "client" } do
        vim.lsp.config("lua_ls_gmod_" .. realm, {
            cmd = { luals, "--configpath=" .. root .. "/.luarc." .. realm .. ".json" },
            filetypes = { "lua" },
            root_dir = root,
            -- The trusted project exrc selects this project's plugin explicitly.
            init_options = { trustByClient = true },
            settings = {
                Lua = {
                    runtime = {
                        plugin = root .. "/tools/luals/realm.lua",
                        pluginArgs = { realm },
                    },
                },
            },
        })
    end
    initialized = true
    return true
end

local function reconcile(bufnr)
    if not vim.api.nvim_buf_is_loaded(bufnr) or vim.bo[bufnr].filetype ~= "lua"
        or vim.bo[bufnr].buftype ~= "" or vim.api.nvim_buf_get_name(bufnr) == "" then
        return
    end
    -- Before the built-in vim.lsp.enable callback can start lua_ls for this buffer.
    configure_native()
    if resolved_alias(vim.api.nvim_buf_get_name(bufnr)) then
        -- Not while an autocommand may still be loading this buffer.
        vim.schedule(function()
            reopen_resolved(bufnr)
        end)
        return
    end
    local game = is_gmod(vim.api.nvim_buf_get_name(bufnr))
    local expected = {}
    if game then
        stabilize_gmod_highlight(bufnr)
        if not ensure_gmod_configs() then
            return
        end
        for _, realm in ipairs(realms_for(bufnr)) do
            expected["lua_ls_gmod_" .. realm] = true
        end
    else
        expected.lua_ls = true
    end
    for _, client in ipairs(vim.lsp.get_clients { bufnr = bufnr, _uninitialized = true }) do
        if is_managed(client) then
            if client:is_stopped() or not expected[client.name] then
                -- Close the old URI before a saveas rename can notify the
                -- previous realm (including an untransformed outside file).
                client:notify("textDocument/didClose", {
                    textDocument = { uri = buffer_uris[bufnr] or vim.uri_from_bufnr(bufnr) },
                })
                vim.lsp.buf_detach_client(bufnr, client.id)
            else
                expected[client.name] = nil
            end
        end
    end
    buffer_uris[bufnr] = vim.uri_from_bufnr(bufnr)
    for name in pairs(expected) do
        local config = vim.lsp.config[name]
        if config and type(config.root_dir) == "function" then
            config.root_dir(bufnr, function(directory)
                if vim.api.nvim_buf_is_loaded(bufnr) and not is_gmod(vim.api.nvim_buf_get_name(bufnr)) then
                    local resolved = vim.deepcopy(config)
                    resolved.root_dir = directory or (within(vim.api.nvim_buf_get_name(bufnr), root_key) and root or nil)
                    vim.lsp.start(resolved, { bufnr = bufnr })
                end
            end)
        elseif config then
            local resolved = vim.deepcopy(config)
            resolved.root_dir = resolved.root_dir or vim.fs.root(bufnr, resolved.root_markers or { ".git" }) or root
            vim.lsp.start(resolved, { bufnr = bufnr })
        end
    end
end

local function force_gmod_realm(realm)
    local bufnr = vim.api.nvim_get_current_buf()
    if not is_gmod(vim.api.nvim_buf_get_name(bufnr)) then
        vim.notify("Current buffer is not a GMOD lua/ file", vim.log.levels.WARN)
        return
    end
    forced_realms[bufnr] = realm
    reconcile(bufnr)
end

local function register_overseer_templates()
    local registered = vim.g.splashsweps_shader_compile_roots or {}
    if registered[root_key] then
        return
    end
    local ok, overseer = pcall(require, "overseer")
    if not ok then
        return
    end
    local cwd = vim.fs.joinpath(root, "shaders", "src")
    local build_script = vim.fs.joinpath(cwd, "build.ps1")
    overseer.register_template {
        name = "ShaderCompile",
        desc = "Compile the current shader source file",
        condition = { dir = root },
        builder = function()
            local file = vim.api.nvim_buf_get_name(0)
            return {
                name = "ShaderCompile",
                cmd = { "pwsh" },
                cwd = cwd,
                args = { "-ExecutionPolicy", "Bypass", "-File", build_script, file },
                components = { "default" },
            }
        end,
    }
    registered[root_key] = true
    vim.g.splashsweps_shader_compile_roots = registered
end

-- Reload the plugin as well as the exrc: a running LuaLS otherwise keeps its
-- old plugin code even after the file on disk has changed. Only clients that
-- exist while this file is being sourced belong to a previous load; stopping
-- later (at VimEnter) would kill and restart the instances this load started.
for _, client in ipairs(vim.lsp.get_clients { _uninitialized = true }) do
    if is_project_client(client) and client.name:match "^lua_ls_gmod_" then
        client:stop(true)
    end
end

local function setup()
    configure_native()
    register_overseer_templates()
    ensure_gmod_configs()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        reconcile(bufnr)
    end
end

vim.api.nvim_create_autocmd("VimEnter", { group = group, callback = setup })
if vim.v.vim_did_enter == 1 then
    setup()
end

vim.api.nvim_create_autocmd({ "FileType", "BufEnter", "BufFilePost" }, {
    group = group,
    callback = function(args)
        reconcile(args.buf)
    end,
})

vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(args)
        local client = vim.lsp.get_client_by_id(args.data.client_id)
        if client and is_managed(client) then
            guard_native_configuration(client)
            vim.schedule(function()
                reconcile(args.buf)
            end)
        end
    end,
})

-- lazydev may replace its configuration handler after attaching, and its
-- workspace settings can re-add lua/ as a library. Filter the actual replies.
vim.api.nvim_create_autocmd("LspNotify", {
    group = group,
    callback = function(args)
        if args.data.method == "workspace/didChangeConfiguration" then
            local client = vim.lsp.get_client_by_id(args.data.client_id)
            if client then
                guard_native_configuration(client, true)
            end
        end
    end,
})

vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(args)
        forced_realms[args.buf] = nil
        buffer_uris[args.buf] = nil
    end,
})

vim.api.nvim_create_user_command("GLuaLsp", function()
    local lines = { "root: " .. root }
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].filetype == "lua" then
            local names = vim.tbl_map(function(client)
                return client.name
            end, vim.lsp.get_clients { bufnr = bufnr })
            lines[#lines + 1] = string.format("buf%d: %s [%s] forced=%s", bufnr,
                vim.api.nvim_buf_get_name(bufnr), table.concat(names, ","), forced_realms[bufnr] or "auto")
        end
    end
    vim.notify(table.concat(lines, "\n"))
end, { force = true })
vim.api.nvim_create_user_command("GLuaClient", function()
    force_gmod_realm("client")
end, { force = true })
vim.api.nvim_create_user_command("GLuaServer", function()
    force_gmod_realm("server")
end, { force = true })
vim.api.nvim_create_user_command("GLuaAutoRealm", function()
    force_gmod_realm(nil)
end, { force = true })
vim.api.nvim_create_user_command("GLuaToggle", function()
    local bufnr = vim.api.nvim_get_current_buf()
    local realms = realms_for(bufnr)
    force_gmod_realm(#realms == 1 and realms[1] == "client" and "server" or "client")
end, { force = true })
