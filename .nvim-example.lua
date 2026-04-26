-- GMOD LuaLS configuration for Neovim 0.12+
-- Copy to .nvim.lua and trust with :trust. Requires vim.o.exrc = true.
--
-- Neovim loads current-directory exrc during startup, before plugins and before
-- the first file's FileType/LSP activation are fully settled. Therefore this
-- file registers lightweight hooks immediately, then performs LSP setup at
-- VimEnter when LazyVim/Mason/LSP configs are available.

local root = vim.fs.dirname(vim.fs.normalize(debug.getinfo(1, "S").source:sub(2)))
local normalized_root = vim.fs.normalize(root):gsub("\\", "/")
local lua_prefix = normalized_root .. "/lua/"
local group = vim.api.nvim_create_augroup("splashsweps_gmod_lsp", { clear = true })

local function normalize(path)
    return vim.fs.normalize(path or ""):gsub("\\", "/")
end

local function is_gmod(path)
    path = normalize(path)
    return path ~= "" and path:sub(1, #lua_prefix) == lua_prefix
end

local function is_nvim_exrc(path)
    local name = vim.fs.basename(path or "")
    return name == ".nvim.lua" or name == ".nvim-example.lua"
end

local function get_realm(path)
    path = normalize(path)
    if
        path:match "/lua/autorun/client/"
        or path:match "/lua/splashsweps/client/"
        or path:match "/cl_[^/]*%.lua$"
        or path:match "/cl_init%.lua$"
    then
        return "client"
    end
  return "server"
end

local forced_realms = {}

local function normalize_bufnr(bufnr)
    if not bufnr or bufnr == 0 then
        return vim.api.nvim_get_current_buf()
    end
    return bufnr
end

local initialized = false

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
        })
    end

    initialized = true
    return true
end

local function has_client(bufnr, name)
    for _, client in ipairs(vim.lsp.get_clients { bufnr = bufnr }) do
        if client.name == name then
            return true
        end
    end
    return false
end

local function detach_client(bufnr, name)
    for _, client in ipairs(vim.lsp.get_clients { bufnr = bufnr }) do
        if client.name == name then
            vim.lsp.buf_detach_client(bufnr, client.id)
        end
    end
end

local function neovim_runtime_library()
    local library = vim.api.nvim_get_runtime_file("lua/vim/**/*.lua", true)

    for _, plugin in ipairs { "lazy.nvim", "LazyVim", "lazydev.nvim", "snacks.nvim", "nvim-lspconfig" } do
        local lua_dir = vim.fn.stdpath "data" .. "/lazy/" .. plugin .. "/lua"
        if vim.uv.fs_stat(lua_dir) then
            library[#library + 1] = lua_dir
        end
    end

    return library
end

local function start_nvim_lua_ls(bufnr)
    if not vim.api.nvim_buf_is_loaded(bufnr) then
        return
    end
    local path = vim.api.nvim_buf_get_name(bufnr)
    if not is_nvim_exrc(path) or not vim.lsp.config.lua_ls then
        return
    end

    local needs_restart = true
    for _, client in ipairs(vim.lsp.get_clients { bufnr = bufnr }) do
        if
            client.name == "lua_ls"
            and client.config
            and client.config.settings
            and vim.tbl_get(client.config.settings, "Lua", "workspace", "library")
        then
            needs_restart = false
        end
    end
    if not needs_restart then
        return
    end

    detach_client(bufnr, "lua_ls")

    local cfg = vim.deepcopy(vim.lsp.config.lua_ls) or {}
    cfg.name = "lua_ls"
    cfg.root_dir = root
    cfg.settings = vim.tbl_deep_extend("force", cfg.settings or {}, {
        Lua = {
            runtime = { version = "LuaJIT" },
            workspace = {
                checkThirdParty = false,
                library = neovim_runtime_library(),
            },
        },
    })

    vim.lsp.start(cfg, { bufnr = bufnr })
end

local function start_gmod(bufnr)
    bufnr = normalize_bufnr(bufnr)

    if not vim.api.nvim_buf_is_loaded(bufnr) then
        return
    end

    local path = vim.api.nvim_buf_get_name(bufnr)
    if not is_gmod(path) then
        return
    end
    if not ensure_gmod_configs() then
        return
    end

  local name = "lua_ls_gmod_" .. (forced_realms[bufnr] or get_realm(path))
    detach_client(bufnr, "lua_ls")

    local seen_gmod = false
    for _, client in ipairs(vim.lsp.get_clients { bufnr = bufnr }) do
        if client.name:match "^lua_ls_gmod_" and client.name ~= name then
            vim.lsp.buf_detach_client(bufnr, client.id)
        elseif client.name == name then
            if seen_gmod then
                vim.lsp.buf_detach_client(bufnr, client.id)
            else
                seen_gmod = true
            end
        end
    end

    if not seen_gmod then
        vim.lsp.start(vim.lsp.config[name], { bufnr = bufnr })
    end
end

local function force_gmod_realm(bufnr, realm)
  bufnr = normalize_bufnr(bufnr)

  local path = vim.api.nvim_buf_get_name(bufnr)
  if not is_gmod(path) then
    vim.notify("Current buffer is not a GMOD lua/ file", vim.log.levels.WARN)
    return
  end

  forced_realms[bufnr] = realm
  start_gmod(bufnr)
end

local function toggle_gmod_realm(bufnr)
  bufnr = normalize_bufnr(bufnr)

  local path = vim.api.nvim_buf_get_name(bufnr)
  if not is_gmod(path) then
    vim.notify("Current buffer is not a GMOD lua/ file", vim.log.levels.WARN)
    return
  end

  local current = forced_realms[bufnr]
  if not current then
    for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
      if client.name == "lua_ls_gmod_client" then
        current = "client"
      elseif client.name == "lua_ls_gmod_server" then
        current = "server"
      end
    end
  end

  force_gmod_realm(bufnr, current == "client" and "server" or "client")
end

local function reconcile(bufnr)
    if vim.bo[bufnr].filetype ~= "lua" then
        return
    end
    local path = vim.api.nvim_buf_get_name(bufnr)
    if is_gmod(path) then
        start_gmod(bufnr)
    elseif is_nvim_exrc(path) then
        start_nvim_lua_ls(bufnr)
    end
end

vim.api.nvim_create_autocmd("VimEnter", {
    group = group,
    callback = function()
        ensure_gmod_configs()

        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_loaded(bufnr) then
                reconcile(bufnr)
            end
        end
    end,
})

vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "lua",
    callback = function(args)
        vim.schedule(function()
            reconcile(args.buf)
        end)
    end,
})

vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    pattern = "*.lua",
    callback = function(args)
        vim.schedule(function()
            reconcile(args.buf)
        end)
    end,
})

vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(args)
        if is_gmod(vim.api.nvim_buf_get_name(args.buf)) then
            vim.schedule(function()
                start_gmod(args.buf)
            end)
        end
    end,
})

-- Diagnostic command: :GmodLsp
vim.api.nvim_create_user_command("GmodLsp", function()
    local lines = {
        "root: " .. root,
        "lua_prefix: " .. lua_prefix,
        "initialized: " .. tostring(initialized),
        "",
    }

    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].filetype == "lua" then
            local path = vim.api.nvim_buf_get_name(bufnr)
            local names = vim.tbl_map(function(client)
                return client.name
            end, vim.lsp.get_clients { bufnr = bufnr })
      lines[#lines + 1] = string.format(
        "buf%d: %s [%s] gmod=%s realm=%s forced=%s",
        bufnr,
        vim.fn.fnamemodify(path, ":t"),
        table.concat(names, ","),
        tostring(is_gmod(path)),
        is_gmod(path) and get_realm(path) or "n/a",
        forced_realms[bufnr] or "n/a"
      )
        end
    end

  vim.notify(table.concat(lines, "\n"))
end, {})

vim.api.nvim_create_user_command("GmodLuaForceClient", function()
  force_gmod_realm(0, "client")
end, {})

vim.api.nvim_create_user_command("GmodLuaForceServer", function()
  force_gmod_realm(0, "server")
end, {})

vim.api.nvim_create_user_command("GmodLuaToggleRealm", function()
  toggle_gmod_realm(0)
end, {})

vim.api.nvim_create_user_command("GmodLuaAutoRealm", function()
  local bufnr = normalize_bufnr(0)
  forced_realms[bufnr] = nil
  start_gmod(bufnr)
end, {})
