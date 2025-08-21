
---@class ss
local ss = SplashSWEPs
if not ss then return end

---This class holds information around paintable surfaces to lookup UV coordinates.
---@class ss.PaintableSurface
---@field AABBMax  Vector AABB maximum of this surface in world coordinates.
---@field AABBMin  Vector AABB minimum of this surface in world coordinates.
---@field WorldToUVMatrix VMatrix The transformation matrix to convert world coordinates into UV coordinates. This does not modify scales.
---@field Normal   Vector Normal vector of this surface.
---@field OffsetU  number The u-coordinate of left-top corner of this surface in UV space.
---@field OffsetV  number The v-coordinate of left-top corner of this surface in UV space.
---@field UVWidth  number The width of this surface in UV space.
---@field UVHeight number The height of this surface in UV space.
ss.struct "PaintableSurface" {
    AABBMax = Vector(),
    AABBMin = Vector(),
    WorldToUVMatrix = Matrix(),
    Normal = Vector(),
    OffsetU = 0,
    OffsetV = 0,
    UVWidth = 0,
    UVHeight = 0,
}

---Reads a surface list from a file and stores them for later use.
function ss.SetupSurfaces()
    local dynamicRange = render.GetHDREnabled() and "hdr" or "ldr"
    local surfacesPath = string.format("splashsweps/%s_%s.json", game.GetMap(), dynamicRange)
    local surfaces = util.JSONToTable(file.Read(surfacesPath) or "", true) ---@type ss.PrecachedData.SurfaceInfo?
    if not surfaces then return end
    for i, surf in ipairs(surfaces) do
        local uvInfo = surf.UVInfo[#surf.UVInfo]
        local ps = ss.new "PaintableSurface"
        ps.AABBMax = surf.AABBMax
        ps.AABBMin = surf.AABBMin
        ps.WorldToUVMatrix:SetAngles(uvInfo.Angle)
        ps.WorldToUVMatrix:SetTranslation(uvInfo.Translation)
        ps.Normal  = ps.WorldToUVMatrix:GetInverseTR():GetUp()
        ps.OffsetU = uvInfo.OffsetU
        ps.OffsetV = uvInfo.OffsetV
        ps.UVWidth = uvInfo.Width
        ps.UVHeight = uvInfo.Height
        ss.SurfaceArray[i] = ps
    end
end
