-- Debug mesh visualization for SplashSWEPs
-- Run: lua_run_cl include("splashsweps/debug_mesh.lua")
--
-- ss_debug_mesh          : Toggle debug mode ON/OFF
-- ss_debug_layer_wire    : Toggle wireframe layer (triangles color-coded by type)
-- ss_debug_layer_mbr     : Toggle MBR/MBB bounding box layer
-- ss_debug_layer_normal  : Toggle normal/tangent/binormal vectors layer
-- ss_debug_layer_uv      : Toggle UV mapping overlay on HUD
-- ss_debug_layer_edge    : Toggle edge classification layer (side mesh vs coplanar)
-- ss_debug_layer_info    : Toggle text information overlay
-- ss_debug_radius <n>    : Set search radius in Hammer units (default 128)
--
-- Usage: Left-click to select surfaces near the aimed position.

---@class ss
local ss = SplashSWEPs
if not ss then return end
if not ss.RenderBatches then return end
if not ss.RenderBatches[1] then return end

local ps = file.Find("shaders/fxc/splashsweps/*_inkmesh_ps30.vcs", "GAME", "datedesc")
local vs = file.Find("shaders/fxc/splashsweps/*_inkmesh_vs30.vcs", "GAME", "datedesc")
if ps and vs then
    for _, v in ipairs(ss.RenderBatches[1]) do
        v.Material:SetString("$pixshader",    "splashsweps/" .. ps[1]:gsub(".vcs", ""))
        v.Material:SetString("$vertexshader", "splashsweps/" .. vs[1]:gsub(".vcs", ""))
        -- v.Material:SetInt("$c0_w", 0)
        v.Material:Recompute()
    end
end

ss.ClearAllInk()

-- State
local enabled = false
local searchRadius = 128 -- Hammer units

---@class ss.DebugMesh.SelectedSurfaceData
---@field surf ss.PaintableSurface
---@field vertices ss.SurfaceBuilder.MeshVertexPack[]

local selectedSurfaces = {} ---@type ss.DebugMesh.SelectedSurfaceData[]

-- Layer toggles (all ON by default)
local layers = {
    wire   = true,
    mbr    = true,
    normal = true,
    uv     = true,
    edge   = true,
    info   = true,
}

-- UV overlay display settings
local uvDisplaySize = 512
local uvDisplayX = 16
local uvDisplayY = 16

-- In client/surfacebuilder.lua: Lift = math.Remap(MetaData or 2, 0, 4, 0, 1)
-- TRI_CEIL=0 -> 0.0, TRI_DEPTH=1 -> 0.25, TRI_BASE=2 -> 0.5,
-- TRI_SIDE_IN=3 -> 0.75, TRI_SIDE_OUT=4 -> 1.0
local ROLE_CEIL = 0
local ROLE_DEPTH = 1
local ROLE_BASE = 2
local ROLE_SIDE_IN = 3
local ROLE_SIDE_OUT = 4
local ROLE_MAX = 4

local COLOR_BASE  = Color(0,   200, 0,   255) -- Green
local COLOR_CEIL  = Color(60,  120, 255, 255) -- Blue
local COLOR_SIDE_IN  = Color(255, 220, 0,   255) -- Yellow
local COLOR_SIDE_OUT = Color(255, 140, 0,   255) -- Orange
local COLOR_DEPTH = Color(255, 50,  50,  255) -- Red
local COLOR_UNKNOWN = Color(180, 180, 180, 255)

local COLOR_NORMAL   = Color(80,  80,  255, 255) -- Blue for normals
local COLOR_TANGENT  = Color(255, 80,  80,  255) -- Red for tangents
local COLOR_BINORMAL = Color(80,  255, 80,  255) -- Green for binormals

local COLOR_EDGE_SIDE     = Color(0,   255, 0,   255) -- Green = has side mesh
local COLOR_EDGE_COPLANAR = Color(255, 60,  60,  200) -- Red = no side mesh (coplanar)

local COLOR_MBB = Color(255, 160, 0, 255) -- Orange for MBB wireframe

---@param lift number
---@return integer
local function DecodeRole(lift)
    return math.Clamp(math.floor(lift * ROLE_MAX + 0.5), 0, ROLE_MAX)
end

---Returns the triangle type name based on Lift value.
---@param lift number
---@return string
local function LiftToName(lift)
    local role = DecodeRole(lift)
    if     role == ROLE_BASE     then return "BASE"
    elseif role == ROLE_CEIL     then return "CEIL"
    elseif role == ROLE_SIDE_IN  then return "SIDE_IN"
    elseif role == ROLE_SIDE_OUT then return "SIDE_OUT"
    elseif role == ROLE_DEPTH    then return "DEPTH"
    else                              return "?"
    end
end

---@param v1 ss.SurfaceBuilder.MeshVertexPack
---@param v2 ss.SurfaceBuilder.MeshVertexPack
---@param v3 ss.SurfaceBuilder.MeshVertexPack
---@return string
local function ClassifyTriangle(v1, v2, v3)
    local r1 = DecodeRole(v1.Lift)
    local r2 = DecodeRole(v2.Lift)
    local r3 = DecodeRole(v3.Lift)
    if r1 == ROLE_CEIL and r2 == ROLE_CEIL and r3 == ROLE_CEIL then
        return "CEIL"
    end
    if r1 == ROLE_SIDE_OUT or r2 == ROLE_SIDE_OUT or r3 == ROLE_SIDE_OUT then
        return "SIDE_OUT"
    end
    if r1 == ROLE_SIDE_IN or r2 == ROLE_SIDE_IN or r3 == ROLE_SIDE_IN then
        return "SIDE_IN"
    end
    if r1 == ROLE_DEPTH or r2 == ROLE_DEPTH or r3 == ROLE_DEPTH then
        return "DEPTH"
    end
    return "BASE"
end

---@param name string
---@return Color
local function TriangleNameToColor(name)
    if     name == "BASE"     then return COLOR_BASE
    elseif name == "CEIL"     then return COLOR_CEIL
    elseif name == "SIDE_IN"  then return COLOR_SIDE_IN
    elseif name == "SIDE_OUT" then return COLOR_SIDE_OUT
    elseif name == "DEPTH"    then return COLOR_DEPTH
    else                           return COLOR_UNKNOWN
    end
end

---Collects mesh vertex data for a given surface object from DebugMeshData.
---@param surf ss.PaintableSurface
---@return ss.SurfaceBuilder.MeshVertexPack[] vertices Array of vertex packs belonging to this surface.
local function CollectVerticesForSurface(surf)
    local result = {} ---@type ss.SurfaceBuilder.MeshVertexPack[]
    if not ss.DebugMeshData then return result end
    for _, meshTable in ipairs(ss.DebugMeshData) do
        for _, v in ipairs(meshTable) do
            if v.SurfaceIndex == surf.Index then
                result[#result + 1] = v
            end
        end
    end
    return result
end

---Selects all surfaces near a world position using ss.CollectSurfaces.
---@param worldPos Vector The center of the search.
---@param worldNormal Vector The normal of hit trace.
local function SelectSurfacesNear(worldPos, worldNormal)
    selectedSurfaces = {}
    local radiusVec = Vector(searchRadius, searchRadius, searchRadius)
    local mins = worldPos - radiusVec
    local maxs = worldPos + radiusVec
    for surf in ss.CollectSurfaces(mins, maxs) do
        if worldNormal:Dot(surf.Normal) > 0.7 then
            local vertices = CollectVerticesForSurface(surf)
            selectedSurfaces[#selectedSurfaces + 1] = {
                surf = surf,
                vertices = vertices,
            }
        end
    end
end

-- 3D drawing utilities
local VECTOR_LEN = 8 -- Length of normal/tangent vectors in HU
local COLOR_AABB = Color(255, 160, 0, 80)

---Draws a wireframe box from origin, angles, and size.
---@param origin Vector
---@param angles Angle
---@param size Vector
---@param col Color
local function DrawWireframeOBB(origin, angles, size, col)
    -- 8 corners of the box
    local corners = {} ---@type Vector[]
    for iz = 0, 1 do
        for iy = 0, 1 do
            for ix = 0, 1 do
                local localPos = Vector(ix * size.x, iy * size.y, iz * size.z)
                local worldPos = LocalToWorld(localPos, angle_zero, origin, angles)
                corners[#corners + 1] = worldPos
            end
        end
    end
    -- 12 edges
    local edges = {
        {1,2}, {1,3}, {1,5},
        {2,4}, {2,6},
        {3,4}, {3,7},
        {4,8},
        {5,6}, {5,7},
        {6,8}, {7,8},
    }
    for _, e in ipairs(edges) do
        render.DrawLine(corners[e[1]], corners[e[2]], col, false)
    end
end

---Draws a wireframe AABB.
---@param mn Vector
---@param mx Vector
---@param col Color
local function DrawWireframeAABB(mn, mx, col)
    -- X edges
    render.DrawLine(Vector(mn.x, mn.y, mn.z), Vector(mx.x, mn.y, mn.z), col, false)
    render.DrawLine(Vector(mn.x, mx.y, mn.z), Vector(mx.x, mx.y, mn.z), col, false)
    render.DrawLine(Vector(mn.x, mn.y, mx.z), Vector(mx.x, mn.y, mx.z), col, false)
    render.DrawLine(Vector(mn.x, mx.y, mx.z), Vector(mx.x, mx.y, mx.z), col, false)
    -- Y edges
    render.DrawLine(Vector(mn.x, mn.y, mn.z), Vector(mn.x, mx.y, mn.z), col, false)
    render.DrawLine(Vector(mx.x, mn.y, mn.z), Vector(mx.x, mx.y, mn.z), col, false)
    render.DrawLine(Vector(mn.x, mn.y, mx.z), Vector(mn.x, mx.y, mx.z), col, false)
    render.DrawLine(Vector(mx.x, mn.y, mx.z), Vector(mx.x, mx.y, mx.z), col, false)
    -- Z edges
    render.DrawLine(Vector(mn.x, mn.y, mn.z), Vector(mn.x, mn.y, mx.z), col, false)
    render.DrawLine(Vector(mx.x, mn.y, mn.z), Vector(mx.x, mn.y, mx.z), col, false)
    render.DrawLine(Vector(mn.x, mx.y, mn.z), Vector(mn.x, mx.y, mx.z), col, false)
    render.DrawLine(Vector(mx.x, mx.y, mn.z), Vector(mx.x, mx.y, mx.z), col, false)
end

---Draws 3D debug visuals for all selected surfaces.
local function Draw3DOverlays()
    if not enabled or #selectedSurfaces == 0 then return end

    for _, data in ipairs(selectedSurfaces) do
        local surf = data.surf
        local vertices = data.vertices

        -- Layer: Wireframe (triangles with color-coded types)
        if layers.wire and #vertices >= 3 then
            for i = 1, #vertices, 3 do
                local v1 = vertices[i]
                local v2 = vertices[i + 1]
                local v3 = vertices[i + 2]
                if v1 and v2 and v3 then
                    local col = TriangleNameToColor(ClassifyTriangle(v1, v2, v3))
                    render.DrawLine(v1.Position, v2.Position, col, false)
                    render.DrawLine(v2.Position, v3.Position, col, false)
                    render.DrawLine(v3.Position, v1.Position, col, false)
                end
            end
        end

        -- Layer: MBR/MBB bounding box
        if layers.mbr and surf.MBBOrigin and surf.MBBSize then
            DrawWireframeOBB(surf.MBBOrigin, surf.MBBAngles, surf.MBBSize, COLOR_MBB)
            DrawWireframeAABB(surf.AABBMin, surf.AABBMax, COLOR_AABB)
        end

        -- Layer: Normal / Tangent / Binormal vectors
        if layers.normal and #vertices > 0 then
            local step = math.max(1, math.floor(#vertices / 120))
            for i = 1, #vertices, step do
                local v = vertices[i]
                if v then
                    local p = v.Position
                    render.DrawLine(p, p + v.Normal   * VECTOR_LEN, COLOR_NORMAL,   false)
                    render.DrawLine(p, p + v.TangentS * VECTOR_LEN, COLOR_TANGENT,  false)
                    render.DrawLine(p, p + v.TangentT * VECTOR_LEN, COLOR_BINORMAL, false)
                end
            end
        end

        -- Layer: Edge classification (side mesh present or not)
        if layers.edge and #vertices >= 3 then
            for i = 1, #vertices, 3 do
                local v1 = vertices[i]
                local v2 = vertices[i + 1]
                local v3 = vertices[i + 2]
                if v1 and v2 and v3 then
                    local triName = ClassifyTriangle(v1, v2, v3)
                    local isSideTri = triName == "SIDE_IN"
                        or triName == "SIDE_OUT"
                        or triName == "DEPTH"
                    if isSideTri then
                        local normal = v1.Normal * 32.0
                        render.DrawLine(v1.Position + normal, v2.Position + normal, COLOR_EDGE_SIDE, false)
                        render.DrawLine(v2.Position + normal, v3.Position + normal, COLOR_EDGE_SIDE, false)
                        render.DrawLine(v3.Position + normal, v1.Position + normal, COLOR_EDGE_SIDE, false)
                        render.DrawLine(v1.Position - normal, v2.Position - normal, COLOR_EDGE_SIDE, false)
                        render.DrawLine(v2.Position - normal, v3.Position - normal, COLOR_EDGE_SIDE, false)
                        render.DrawLine(v3.Position - normal, v1.Position - normal, COLOR_EDGE_SIDE, false)
                    end
                end
            end
        end
    end
end

--- UV (u, v) to screen XY
---@param u number
---@param v number
---@return number x
---@return number y
local function UVToScreenXY(u, v)
    return uvDisplayX + v * uvDisplaySize,
           uvDisplayY + u * uvDisplaySize
end

---Draws HUD overlays (UV panel and info text).
local function DrawHUDOverlays()
    if not enabled then return end

    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    if input.IsMouseDown(MOUSE_LEFT) then
        local tr = ply:GetEyeTrace()
        if tr.Hit then
            SelectSurfacesNear(tr.HitPos, tr.HitNormal)
        else
            selectedSurfaces = {}
        end
    end

    if #selectedSurfaces == 0 then
        draw.SimpleText("Aim at a surface and left-click to inspect", "DermaDefaultBold",
            uvDisplayX, uvDisplayY, Color(255, 255, 255, 128))
        return
    end

    -- Layer: UV mapping overlay (show all surfaces)
    if layers.uv then
        local rt = ss.RenderTarget and ss.RenderTarget.StaticTextures
            and ss.RenderTarget.StaticTextures.InkMap
        local copy = Material "pp/copy"

        -- Background
        surface.SetDrawColor(0, 0, 0, 200)
        surface.DrawRect(uvDisplayX, uvDisplayY, uvDisplaySize, uvDisplaySize)

        -- Draw InkMap RT
        if rt then
            copy:SetTexture("$basetexture", rt)
            surface.SetDrawColor(255, 255, 255, 255)
            surface.SetMaterial(copy)
            surface.DrawTexturedRectUV(
                uvDisplayX, uvDisplayY, uvDisplaySize, uvDisplaySize,
                0, 0, 0.5, 0.5)
        end

        for si, data in ipairs(selectedSurfaces) do
            local surf = data.surf
            local vertices = data.vertices

            -- Highlight surface's UV region with unique color per surface
            local h = (si * 137.508) % 360
            local regionColor = HSVToColor(h, 0.9, 1)
            local ou = surf.OffsetU or 0
            local ov = surf.OffsetV or 0
            local uw = surf.UVWidth or 0
            local uh = surf.UVHeight or 0
            local rx, ry = UVToScreenXY(ou, ov)
            local rw, rh = uh * uvDisplaySize, uw * uvDisplaySize
            surface.SetDrawColor(regionColor.r, regionColor.g, regionColor.b, 255)
            surface.DrawOutlinedRect(math.floor(rx), math.floor(ry),
                math.ceil(rw), math.ceil(rh), 1)

            -- Draw triangles in UV space
            if #vertices >= 3 then
                for i = 1, #vertices, 3 do
                    local v1 = vertices[i]
                    local v2 = vertices[i + 1]
                    local v3 = vertices[i + 2]
                    if v1 and v2 and v3 and v1.Lift == 0 and v2.Lift == 0 and v3.Lift == 0 then
                        local col = TriangleNameToColor(ClassifyTriangle(v1, v2, v3))
                        local x1, y1 = UVToScreenXY(v1.V[1], v1.U[1])
                        local x2, y2 = UVToScreenXY(v2.V[1], v2.U[1])
                        local x3, y3 = UVToScreenXY(v3.V[1], v3.U[1])
                        surface.SetDrawColor(col)
                        surface.DrawLine(x1, y1, x2, y2)
                        surface.DrawLine(x2, y2, x3, y3)
                        surface.DrawLine(x3, y3, x1, y1)
                    end
                end
            end
        end
    end

    -- Layer: Info text
    if layers.info then
        local textX = uvDisplayX + (layers.uv and uvDisplaySize + 16 or 0)
        local textY = uvDisplayY
        local lineH = 16

        local function InfoLine(text, col)
            draw.SimpleText(text, "DermaDefault", textX, textY, col or color_white)
            textY = textY + lineH
        end

        InfoLine(string.format("Selected: %d surfaces (radius: %d HU)",
            #selectedSurfaces, searchRadius), Color(255, 255, 0))

        -- Aggregate stats
        local totalVertices = 0
        local totalTriangles = 0
        local triCounts = { BASE = 0, CEIL = 0, SIDE_IN = 0, SIDE_OUT = 0, DEPTH = 0, ["?"] = 0 }
        for _, data in ipairs(selectedSurfaces) do
            local vertices = data.vertices
            totalVertices = totalVertices + #vertices
            totalTriangles = totalTriangles + math.floor(#vertices / 3)
            for i = 1, #vertices, 3 do
                local v = vertices[i]
                if v then
                    local v2 = vertices[i + 1]
                    local v3 = vertices[i + 2]
                    local name = v2 and v3 and ClassifyTriangle(v, v2, v3) or LiftToName(v.Lift)
                    triCounts[name] = (triCounts[name] or 0) + 1
                end
            end
        end

        InfoLine(string.format("Total vertices: %d  Triangles: %d  (DebugMeshData: %s)",
            totalVertices, totalTriangles,
            ss.DebugMeshData and #ss.DebugMeshData .. " meshes" or "nil"))
        InfoLine(string.format("  BASE: %d  CEIL: %d  SIDE_IN: %d  SIDE_OUT: %d  DEPTH: %d",
            triCounts.BASE, triCounts.CEIL, triCounts.SIDE_IN, triCounts.SIDE_OUT, triCounts.DEPTH))

        textY = textY + 8

        -- Per-surface details
        for si, data in ipairs(selectedSurfaces) do
            local surf = data.surf
            local vertices = data.vertices
            local h = (si * 137.508) % 360
            local surfColor = HSVToColor(h, 0.9, 1)

            InfoLine(string.format("Surface #%d (%d verts)",
                surf.Index, #vertices), Color(surfColor.r, surfColor.g, surfColor.b))

            if surf.AABBMin and surf.AABBMax then
                InfoLine(string.format("  AABB: (%.0f,%.0f,%.0f)-(%.0f,%.0f,%.0f)",
                    surf.AABBMin.x, surf.AABBMin.y, surf.AABBMin.z,
                    surf.AABBMax.x, surf.AABBMax.y, surf.AABBMax.z))
            end

            if surf.MBBOrigin and surf.MBBSize then
                InfoLine(string.format("  MBB size: (%.0f,%.0f,%.0f)",
                    surf.MBBSize.x, surf.MBBSize.y, surf.MBBSize.z))
            end

            InfoLine(string.format("  UV: off(%.4f,%.4f) size(%.4f,%.4f)",
                surf.OffsetU or 0, surf.OffsetV or 0,
                surf.UVWidth or 0, surf.UVHeight or 0))

            if surf.Normal then
                InfoLine(string.format("  Normal: (%.3f,%.3f,%.3f)",
                    surf.Normal.x, surf.Normal.y, surf.Normal.z))
            end

            if surf.Grid then
                InfoLine(string.format("  Grid: %dx%d",
                    surf.Grid.Width or 0, surf.Grid.Height or 0))
            end

            if surf.StaticPropUnwrapIndex then
                InfoLine(string.format("  Static prop (unwrap: %d)",
                    surf.StaticPropUnwrapIndex), Color(180, 255, 180))
            end

            if surf.Triangles then
                InfoLine(string.format("  Displacement (%d triangles)",
                    #surf.Triangles), Color(180, 180, 255))
            end
        end

        textY = textY + 8
        InfoLine("Layers:", Color(180, 180, 180))
        for name, on in pairs(layers) do
            InfoLine(string.format("  %s: %s", name, on and "ON" or "OFF"),
                on and Color(100, 255, 100) or Color(255, 100, 100))
        end

        textY = textY + 8
        InfoLine("Left-click to update selection", Color(128, 128, 128))
    end
end

-- Hook management
local HOOK_3D  = "SplashSWEPs: Debug Mesh 3D"
local HOOK_HUD = "SplashSWEPs: Debug Mesh HUD"

local function Enable()
    enabled = true
    selectedSurfaces = {}
    hook.Add("PostDrawOpaqueRenderables", HOOK_3D, Draw3DOverlays)
    hook.Add("HUDPaint", HOOK_HUD, DrawHUDOverlays)
    print("[SplashSWEPs] Debug mesh: ON")
end

local function Disable()
    enabled = false
    selectedSurfaces = {}
    hook.Remove("PostDrawOpaqueRenderables", HOOK_3D)
    hook.Remove("HUDPaint", HOOK_HUD)
    print("[SplashSWEPs] Debug mesh: OFF")
end

-- ConCommands
concommand.Add("ss_debug_mesh", function()
    if enabled then Disable() else Enable() end
end)

local function MakeLayerToggle(name)
    concommand.Add("ss_debug_layer_" .. name, function()
        layers[name] = not layers[name]
        print(string.format("[SplashSWEPs] Layer '%s': %s", name, layers[name] and "ON" or "OFF"))
    end)
end

MakeLayerToggle("wire")
MakeLayerToggle("mbr")
MakeLayerToggle("normal")
MakeLayerToggle("uv")
MakeLayerToggle("edge")
MakeLayerToggle("info")

concommand.Add("ss_debug_radius", function(_, _, args)
    local r = tonumber(args[1])
    if r and r > 0 then
        searchRadius = r
        print(string.format("[SplashSWEPs] Debug search radius: %d HU", searchRadius))
    else
        print(string.format("[SplashSWEPs] Current radius: %d HU. Usage: ss_debug_radius <number>", searchRadius))
    end
end)

Enable()

print("[SplashSWEPs] Debug mesh loaded. Use 'ss_debug_mesh' to toggle.")
print("  Layers: ss_debug_layer_wire, ss_debug_layer_mbr, ss_debug_layer_normal,")
print("          ss_debug_layer_uv, ss_debug_layer_edge, ss_debug_layer_info")
print("  Radius: ss_debug_radius <HU>  (current: " .. searchRadius .. ")")
