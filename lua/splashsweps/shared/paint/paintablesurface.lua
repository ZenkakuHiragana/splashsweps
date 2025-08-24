
---@class ss
local ss = SplashSWEPs
if not ss then return end

---This class holds information around serverside paintings and conversion to UV coordinates.
---```text
---World origin
---  +--> x
---  |
---  v   WorldToLocalGridMatrix:GetInverseTR():GetTranslation()
---  y      +--> X
---         |
---         v   * (Xi, Yi) = WorldToLocalGridMatrix * (xi, yi)
---         Y
---```
---
---The surface is placed in UV coordinates like this:
---
---```text
---UV origin
--- +--------------+--> U             WorldToUVMatrix
--- |              ^                    :GetInverseTR()
--- |              |                    :GetTranslation()
--- |           OffsetV                       |
--- |              |   |<----UVWidth---->|    |
--- |              v   |                 |    |
--- +<----OffsetU--+-->+--------------<==@ <--+
--- |              ^   |                 $
--- v              |   |                 V
--- V         UVHeight |                 |
---                |   |                 |
---                v   |                 |
---              --+---+-----------------+
---```
---@class ss.PaintableSurface
---@field AABBMax                Vector  AABB maximum of this surface in world coordinates.
---@field AABBMin                Vector  AABB minimum of this surface in world coordinates.
---@field Normal                 Vector  Normal vector of this surface.
---@field Grid          ss.PaintableGrid Represents serverside "canvas" for this surface to manage collision detection against painted ink.
---@field WorldToLocalGridMatrix VMatrix The transformation matrix to convert world coordinates into local coordinates. This does not modify scales.
---@field WorldToUVMatrix        VMatrix The transformation matrix to convert world coordinates into UV coordinates. This does not modify scales.
---@field OffsetU                number  The u-coordinate of left-top corner of this surface in UV space in pixels.
---@field OffsetV                number  The v-coordinate of left-top corner of this surface in UV space in pixels.
---@field UVWidth                number  The width of this surface in UV space in pixels.
---@field UVHeight               number  The height of this surface in UV space in pixels.
ss.struct "PaintableSurface" {
    AABBMax = Vector(),
    AABBMin = Vector(),
    Normal = Vector(),
    Grid = ss.new "PaintableGrid",
    WorldToLocalGridMatrix = Matrix(),
    WorldToUVMatrix = Matrix(),
    OffsetU = 0,
    OffsetV = 0,
    UVWidth = 0,
    UVHeight = 0,
}

---Reads a surface list from a file and stores them for later use.
function ss.SetupSurfaces()
    ---@diagnostic disable-next-line: undefined-field
    local dynamicRange = CLIENT and render.GetHDREnabled() and "hdr" or "ldr"
    local surfacesPath = string.format("splashsweps/%s_%s.json", game.GetMap(), dynamicRange)
    local surfaces = util.JSONToTable(file.Read(surfacesPath) or "", true) ---@type ss.PrecachedData.SurfaceInfo?
    if not surfaces then return end
    for i, surf in ipairs(surfaces) do
        local ps = ss.new "PaintableSurface"
        ps.AABBMax = surf.AABBMax
        ps.AABBMin = surf.AABBMin
        ps.WorldToLocalGridMatrix:SetAngles(surf.TransformPaintGrid.Angle)
        ps.WorldToLocalGridMatrix:SetTranslation(surf.TransformPaintGrid.Translation)
        ps.Normal = ps.WorldToLocalGridMatrix:GetInverseTR():GetUp()
        ps.Grid.Width = surf.PaintGridWidth
        ps.Grid.Height = surf.PaintGridHeight
        if CLIENT then
            local rtIndex = #ss.RenderTarget.Resolutions
            local rtSize = ss.RenderTarget.Resolutions[rtIndex]
            local uvInfo = surf.UVInfo[rtIndex]
            ps.WorldToUVMatrix:SetAngles(uvInfo.Angle)
            ps.WorldToUVMatrix:SetTranslation(uvInfo.Translation)
            ps.OffsetU = uvInfo.OffsetU * rtSize
            ps.OffsetV = uvInfo.OffsetV * rtSize
            ps.UVWidth = uvInfo.Width * rtSize
            ps.UVHeight = uvInfo.Height * rtSize
        end
        ss.SurfaceArray[i] = ps
    end
end
