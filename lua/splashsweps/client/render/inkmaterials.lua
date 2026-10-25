
-- Ink materials of the world and static props, kept in sync with the materials they are drawn on.

---@class ss
local ss = SplashSWEPs
local Util = ss.import "splashsweps/shared/util"

---@class ss.InkMaterialsModule
local InkMaterials = ss.module "splashsweps/client/render/inkmaterials"

---@class ss.InkMaterials.WatchState
---@field Interval integer Index of adaptive interval array to check this parameter.
---@field LastTime number  CurTime()-based last check time for this parameter.
---@field Value    string  Last observed value.

---@class ss.InkMaterials.WatchEntry
---@field Material IMaterial The material to watch the changes.
---@field Fields   table<string, ss.InkMaterials.WatchState>

---@class ss.InkMaterialsModule.State
---@field World            table<IMaterial, IMaterial> Ink material of the world ink meshes --> bound geometry material.
---@field StaticProp       table<IMaterial, IMaterial> Ink material of the static props --> bound model material.
---@field WatchList        ss.InkMaterials.WatchEntry[]
---@field LastSunDirection Vector
local state = ss.state("splashsweps/client/render/inkmaterials", {
    World = {},
    StaticProp = {},
    WatchList = {},
    LastSunDirection = Vector(),
}) ---@type ss.InkMaterialsModule.State

-- Ink materials are registered by the kind of the geometry, as the shader constants they share
-- with the material under the ink differ by the kind:
--
--   kind           follows the material under the ink                  sun direction in $c0_xyz
--   -------------  --------------------------------------------------  ------------------------
--   world          transforms, $color, $color2, and $detail* to blend  yes
--   static prop    transforms, $color, and $color2                     no, $c0_x has another use

---Registers an ink material of the world ink meshes to keep it in sync with the material under the ink.
---@param mat IMaterial Ink material
---@param source IMaterial Material of the surfaces the ink is drawn on
function InkMaterials.AddWorld(mat, source)
    state.World[mat] = source
end

---Registers an ink material of a static prop to keep it in sync with the material under the ink.
---@param mat IMaterial Ink material
---@param source IMaterial Material of the model the ink is drawn on
function InkMaterials.AddStaticProp(mat, source)
    state.StaticProp[mat] = source
end

---Envmap the engine falls back to when a material has no cubemap to use.
InkMaterials.DEFAULT_ENVMAP = "editor/cubemap" .. (render.GetHDREnabled() and ".hdr" or "")

local InkWaterMaterial = Material "splashsweps/shaders/inkmesh"
local MaterialWatchInterval   = { 0, 0.05, 0.5, 1, 2, 5, math.huge }
local MaterialWatchParameters = {
    ["$basetexturetransform"] = "Matrix",
    ["$bumptransform"]        = "Matrix",
    ["$detailblendfactor"]    = "Float",
    ["$detailblendmode"]      = "Int",
    ["$detailscale"]          = "Vector",
    ["$detailtint"]           = "Vector",
    ["$color"]                = "Vector",
    ["$color2"]               = "Vector",
}

---Reflects a changed parameter of the source material to the ink material.
---
---  RefreshInkMaterial        world and static props   transforms, $color, $color2
---  RefreshWorldInkMaterial   world                    the above and $detail*
---@type table<string, fun(mat: IMaterial, src: IMaterial, value: any)>
local RefreshInkMaterial = {
    ---@param mat IMaterial
    ---@param _   IMaterial
    ---@param value VMatrix
    ["$basetexturetransform"] = function(mat, _, value)
        local m = mat:GetMatrix "$viewprojmat"
        m:SetField(1, 1, value:GetField(1, 1))
        m:SetField(1, 2, value:GetField(1, 2))
        m:SetField(1, 3, value:GetField(1, 4))
        m:SetField(2, 1, value:GetField(2, 1))
        m:SetField(2, 2, value:GetField(2, 2))
        m:SetField(2, 3, value:GetField(2, 4))
        mat:SetMatrix("$viewprojmat", m)
    end,
    ---@param mat IMaterial
    ---@param _   IMaterial
    ---@param value VMatrix
    ["$bumptransform"] = function(mat, _, value)
        local m = mat:GetMatrix "$viewprojmat"
        m:SetField(3, 1, value:GetField(1, 1))
        m:SetField(3, 2, value:GetField(1, 2))
        m:SetField(3, 3, value:GetField(1, 4))
        m:SetField(4, 1, value:GetField(2, 1))
        m:SetField(4, 2, value:GetField(2, 2))
        m:SetField(4, 3, value:GetField(2, 4))
        mat:SetMatrix("$viewprojmat", m)
    end,
    ---@param mat IMaterial
    ---@param src IMaterial
    ---@param value Vector
    ["$color"] = function(mat, src, value)
        local color = value * (src:GetVector "$color2" or Util.vector_one)
        mat:SetFloat("$c3_x", color.x)
        mat:SetFloat("$c3_y", color.y)
        mat:SetFloat("$c3_z", color.z)
    end,
    ---@param mat IMaterial
    ---@param src IMaterial
    ---@param value Vector
    ["$color2"] = function(mat, src, value)
        local color = value * (src:GetVector "$color" or Util.vector_one)
        mat:SetFloat("$c3_x", color.x)
        mat:SetFloat("$c3_y", color.y)
        mat:SetFloat("$c3_z", color.z)
    end,
}

---@type table<string, fun(mat: IMaterial, src: IMaterial, value: any)>
local RefreshWorldInkMaterial = table.Merge({
    ---@param mat IMaterial
    ---@param _   IMaterial
    ---@param value number
    ["$detailblendfactor"] = function(mat, _, value)
        local m = mat:GetMatrix "$viewprojmat"
        m:SetField(4, 4, value)
        mat:SetMatrix("$viewprojmat", m)
    end,
    ---@param mat IMaterial
    ---@param _   IMaterial
    ---@param value integer
    ["$detailblendmode"] = function(mat, _, value)
        mat:SetInt("$linearread_texture5", value == 1 and 0 or 1)
        mat:SetInt("$c0_w", value)
    end,
    ---@param mat IMaterial
    ---@param _   IMaterial
    ---@param value Vector
    ["$detailscale"] = function(mat, _, value)
        mat:SetFloat("$c2_z", value.x)
        mat:SetFloat("$c2_w", value.y)
    end,
    ---@param mat IMaterial
    ---@param _   IMaterial
    ---@param value Vector
    ["$detailtint"] = function(mat, _, value)
        local m = mat:GetMatrix "$viewprojmat"
        m:SetField(1, 4, value.x)
        m:SetField(2, 4, value.y)
        m:SetField(3, 4, value.z)
        mat:SetMatrix("$viewprojmat", m)
    end,
}, RefreshInkMaterial)

---Reflects the changed parameters of the source materials to their ink materials.
---@param materials table<IMaterial, IMaterial> Ink material --> source material.
---@param refreshers table<string, fun(mat: IMaterial, src: IMaterial, value: any)> RefreshInkMaterial or RefreshWorldInkMaterial.
---@param refreshList table<IMaterial, string[]> Source material --> changed parameters.
local function RefreshInkMaterials(materials, refreshers, refreshList)
    for renderMaterial, geometryMaterial in pairs(materials) do
        for _, key in ipairs(refreshList[geometryMaterial] or {}) do
            local refresh = refreshers[key]
            ---@type fun(self: IMaterial, key: string): number|Vector|VMatrix
            local get = geometryMaterial["Get" .. (MaterialWatchParameters[key] or "???")]
            if refresh and get then
                refresh(renderMaterial, geometryMaterial, get(geometryMaterial, key))
            end
        end
    end
end

hook.Add("PreRender", "SplashSWEPs: Refresh material parameters", function()
    local now = CurTime()
    local refreshList = {} ---@type table<IMaterial, string[]>
    for _, entry in ipairs(state.WatchList) do
        local keys = {} ---@type string[]
        for key, field in pairs(entry.Fields) do
            if now > field.LastTime + MaterialWatchInterval[field.Interval] then
                field.LastTime = now
                local value = entry.Material:GetString(key)
                if value == field.Value then
                    field.Interval = field.Interval + 1
                else
                    field.Interval = 1
                    field.Value = value
                    keys[#keys + 1] = key
                end
            end
        end

        if #keys > 0 then
            refreshList[entry.Material] = keys
        end
    end

    RefreshInkMaterials(state.World, RefreshWorldInkMaterial, refreshList)
    RefreshInkMaterials(state.StaticProp, RefreshInkMaterial, refreshList)

    local sunInfo = util.GetSunInfo()
    local sunDir = sunInfo and sunInfo.direction or Vector(0, 0.3, 0.954)
    if not state.LastSunDirection:IsEqualTol(sunDir, Util.eps) then
        state.LastSunDirection = sunDir
        InkWaterMaterial:SetFloat("$c0_x", sunDir.x)
        InkWaterMaterial:SetFloat("$c0_y", sunDir.y)
        InkWaterMaterial:SetFloat("$c0_z", sunDir.z)
        -- Only the world part reads it. The static prop part uses the four lights instead.
        for m in pairs(state.World) do
            m:SetFloat("$c0_x", sunDir.x)
            m:SetFloat("$c0_y", sunDir.y)
            m:SetFloat("$c0_z", sunDir.z)
        end
    end
end)

---Checks material proxied to be checked in the given list of materials
---and registers them to the watch list to be refreshed.
---@param mats table<integer, { Material: IMaterial }> Materials, such as sparse enumeration-ID-indexed ss.MapMaterials.MaterialInfo.
function InkMaterials.Watch(mats)
    for _, m in pairs(mats) do
        local mat = m.Material
        local vmt = string.format("materials/%s.vmt", mat:GetName())
        local vmtkv = file.Read(vmt, "GAME")
        if vmtkv and vmtkv ~= "" then
            local params = util.KeyValuesToTablePreserveOrder(vmtkv)
            local proxies ---@type KeyValue[]?
            for _, kv in ipairs(params) do
                if kv.Key == "proxies" then
                    proxies = kv.Value
                    break
                end
            end

            local states = nil ---@type ss.InkMaterials.WatchEntry
            for _, entry in ipairs(proxies or {}) do
                local contents = entry.Value ---@cast contents { Key: string, Value: string }[]
                local kv = table.CollapseKeyValue(contents)
                local resultvar = kv.resultvar and kv.resultvar:lower()
                if resultvar then
                    states = states or {
                        Material = mat,
                        Fields = {},
                    }
                    states.Fields[resultvar] = {
                        Interval = 1,
                        LastTime = CurTime(),
                        Value = "",
                    }
                end
            end

            if states then
                state.WatchList[#state.WatchList + 1] = states
            end
        end
    end
end

return InkMaterials
