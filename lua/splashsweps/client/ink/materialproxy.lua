
-- Reads the proxy block of a VMT file as Source does.

---@class ss
local ss = SplashSWEPs

---@class ss.MaterialProxyModule
local MaterialProxy = ss.module "splashsweps/client/ink/materialproxy"

---@class ss.MaterialProxyKey
---@field Key string
---@field Value string|number|ss.MaterialProxyKey[]

---Finds the first named entry in an ordered KeyValues list.
---@param entries ss.MaterialProxyKey[]
---@param name string
---@return ss.MaterialProxyKey?
local function FindMaterialProxyKey(entries, name)
    for _, entry in ipairs(entries) do
        if entry.Key == name then return entry end
    end
end

---Merges ordered proxy keys using Source's insert/replace rules.
---@param destination ss.MaterialProxyKey[]
---@param source ss.MaterialProxyKey[]
---@param existingOnly boolean
local function MergeMaterialProxyKeys(destination, source, existingOnly)
    for _, entry in ipairs(source) do
        local target = FindMaterialProxyKey(destination, entry.Key)
        if target or not existingOnly then
            if not target then
                target = { Key = entry.Key, Value = {} }
                destination[#destination + 1] = target
            end
            if istable(entry.Value) then
                if not istable(target.Value) then target.Value = {} end
                local targetValues, sourceValues = target.Value, entry.Value
                    ---@cast targetValues ss.MaterialProxyKey[]
                    ---@cast sourceValues ss.MaterialProxyKey[]
                MergeMaterialProxyKeys(targetValues, sourceValues, existingOnly)
            else
                target.Value = entry.Value
            end
        end
    end
    if existingOnly then
        for _, target in ipairs(destination) do
            local entry = FindMaterialProxyKey(source, target.Key)
            if istable(target.Value) and entry and istable(entry.Value) then
                local targetValues, sourceValues = target.Value, entry.Value
                    ---@cast targetValues ss.MaterialProxyKey[]
                    ---@cast sourceValues ss.MaterialProxyKey[]
                MergeMaterialProxyKeys(targetValues, sourceValues, true)
            end
        end
    end
end

---Reads the proxy block after resolving Source's Patch include chain.
---@param path string
---@return ss.MaterialProxyKey[]
function MaterialProxy.Read(path)
    local inserts, replaces ---@type ss.MaterialProxyKey[]?, ss.MaterialProxyKey[]?
    -- Source accumulates patches from outermost to innermost, up to ten includes.
    for _ = 0, 10 do
        local vmt = file.Read(path, "GAME")
        if not vmt then return {} end
        local root = util.KeyValuesToTablePreserveOrder('"vmt" {\n' .. vmt .. '\n}')[1]
            ---@cast root ss.MaterialProxyKey
        local entries = root.Value ---@cast entries ss.MaterialProxyKey[]
        if root.Key ~= "patch" then
            local proxies = FindMaterialProxyKey(entries, "proxies")
            local values  = proxies and proxies.Value ---@cast values ss.MaterialProxyKey[]?
            if inserts then
                values = values or {}
                MergeMaterialProxyKeys(values, inserts, false)
            end
            if values and replaces then MergeMaterialProxyKeys(values, replaces, true) end
            return values or {}
        end
        for _, action in ipairs { "insert", "replace" } do
            local section       = FindMaterialProxyKey(entries, action)
            local sectionValues = section and section.Value
                ---@cast sectionValues ss.MaterialProxyKey[]?
            local proxies = sectionValues and FindMaterialProxyKey(sectionValues, "proxies")
            if proxies then
                local values = proxies.Value ---@cast values ss.MaterialProxyKey[]
                if action == "insert" then
                    inserts = inserts or {}
                    MergeMaterialProxyKeys(inserts, values, false)
                else
                    replaces = replaces or {}
                    MergeMaterialProxyKeys(replaces, values, false)
                end
            end
        end
        local include = FindMaterialProxyKey(entries, "include")
        if not include then return {} end
        local includePath = include.Value ---@cast includePath string
        path = includePath
    end
    return {}
end

return MaterialProxy
