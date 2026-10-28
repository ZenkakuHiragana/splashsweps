
-- Places the paintable surfaces in the ink map by their rectangles of the map cache.

---@class ss
local ss = SplashSWEPs
local PaintableSurface = ss.import "splashsweps/shared/paint/paintablesurface"
local RenderTargets    = ss.import "splashsweps/client/render/rendertargets"

---@class ss.InkMapLayoutModule
local InkMapLayout = ss.module "splashsweps/client/mapload/inkmaplayout"

---Where a paintable surface is in the ink map.
---
---```text
---UV origin
--- +------------------------------> V
--- |        minV                maxV
--- |   minU +--------------------+
--- |        |  +--> y            |
--- |        |  |  paint grid     |
--- |        |  v                 |
--- |        |  x                 |
--- |   maxU +--------------------+
--- v
--- U
---```
---
---The paint grid (x, y) starts at ss.MARGIN_HAMMER_UNITS inside the rectangle of the surface in the ink map,
---and the UV range is the rectangle without the bilinear guard along its edges.
---A rotated rectangle has (x, y) along (-V, U).
---@class ss.InkMapLayout.Placement
---@field WorldToUVRow1 number[] The first row of the transform from the world into the ink map in hammer units, which gives U.
---@field WorldToUVRow2 number[] The second row of the transform from the world into the ink map in hammer units, which gives V.
---@field UVRange       [number, number, number, number] (minU, minV, maxU, maxV) of the surface in the ink map, where the paints are drawn.

---@class ss.InkMapLayoutModule.State
---@field Placements ss.InkMapLayout.Placement[] Indexed by ss.PaintableSurface.Index.
local state = ss.state("splashsweps/client/mapload/inkmaplayout", { Placements = {} }) ---@type ss.InkMapLayoutModule.State

---Where each paintable surface is in the ink map, indexed by ss.PaintableSurface.Index.
InkMapLayout.Placements = state.Placements

---Places the paintable surfaces in the ink map,
---after PaintableSurface.Setup and PaintableSurface.SetupStaticProps create them.
---@param surfaces    ss.PrecachedData.Surface[]?    The surfaces given to PaintableSurface.Setup.
---@param staticProps ss.PrecachedData.StaticProp[]? The static props given to PaintableSurface.SetupStaticProps.
function InkMapLayout.Setup(surfaces, staticProps)
    table.Empty(state.Placements)
    local scale  = RenderTargets.GetHammerUnitsToUV()
    local guard  = ss.RT_BILINEAR_GUARD_PIXELS / RenderTargets.InkMaps.InkMap:Width()
    local margin = ss.MARGIN_HAMMER_UNITS

    ---Places a surface whose rectangle in the ink map is at (offsetU, offsetV) of the size in hammer units.
    ---@param index   integer
    ---@param row1    number[]
    ---@param row2    number[]
    ---@param offsetU number
    ---@param offsetV number
    ---@param width   number
    ---@param height  number
    local function place(index, row1, row2, offsetU, offsetV, width, height)
        local minU = offsetU * scale + guard
        local minV = offsetV * scale + guard
        state.Placements[index] = {
            WorldToUVRow1 = row1,
            WorldToUVRow2 = row2,
            UVRange = { minU, minV, minU + (width * scale - 2 * guard), minV + (height * scale - 2 * guard) },
        }
    end

    for i, surf in ipairs(surfaces or {}) do
        local g = PaintableSurface.Surfaces[i].WorldToLocalGrid
        local rectangle = surf.InkMapRectangle
        local row1, row2 ---@type number[], number[]
        if rectangle.IsRotated then
            row1 = {  g[5],  g[6],  g[7],  g[8] + rectangle.OffsetU + margin }
            row2 = { -g[1], -g[2], -g[3], -g[4] + rectangle.OffsetV + rectangle.Height - margin }
        else
            row1 = { g[1], g[2], g[3], g[4] + rectangle.OffsetU + margin }
            row2 = { g[5], g[6], g[7], g[8] + rectangle.OffsetV + margin }
        end

        place(i, row1, row2, rectangle.OffsetU, rectangle.OffsetV, rectangle.Width, rectangle.Height)
    end

    local index = surfaces and #surfaces or 0
    for _, prop in ipairs(staticProps or {}) do
        -- The rectangle of the prop in the ink map, rotated by 90 degrees if IsRotated.
        --   +--------> v                +--------> v
        --   | model local uv space      |   v'
        --   |   +---> v'                |   ^
        --   v   |                       v   +---> u'
        --   u   u'                      u    \__model local uv space
        local box = PaintableSurface.GetStaticPropBox(prop)
        local rectangle = prop.InkMapRectangle
        local isRotated = rectangle.IsRotated
        local modelUVOriginU = rectangle.OffsetU + (isRotated and rectangle.Width or 0)
        local modelUVOriginV = rectangle.OffsetV
        for _, face in ipairs(box.Faces) do
            index = index + 1

            -- +-------------> v
            -- |\ <--- modelUVOrigin
            -- | +----> v'
            -- | | \ <--- faceUVOrigin
            -- | V  @==> y, v" --+
            -- | u' |            |
            -- V    V------------+
            -- u    x, u"
            --
            -- (x , y ) face local system converted from the world, the paint grid
            -- (u , v ) absolute UV in the render target texture
            -- (u', v') model local UV from the rectangle of the prop
            -- (u", v") face local UV
            -- The cell of the face in the model local UV starts at the margin inside it.
            local boxFace = face.BoxFace
            local localU = (box.SizeX + 2 * margin) * boxFace.UVOffsetX
                         + (box.SizeY + 2 * margin) * boxFace.UVOffsetY + margin
            local localV = (box.SizeZ + 2 * margin) * boxFace.UVOffsetZ + margin
            local grid = PaintableSurface.Surfaces[index].WorldToLocalGrid
            local faceSizeU, faceSizeV, faceUVOriginU, faceUVOriginV ---@type number, number, number, number
            local row1, row2 ---@type number[], number[]
            if isRotated then -- (u, v) = (-v', u') from the model local UV origin
                faceSizeU, faceSizeV = face.SizeY, face.SizeX
                faceUVOriginU, faceUVOriginV = modelUVOriginU - localV, modelUVOriginV + localU
                row1 = { -grid[5], -grid[6], -grid[7], -grid[8] + faceUVOriginU }
                row2 = {  grid[1],  grid[2],  grid[3],  grid[4] + faceUVOriginV }
                faceUVOriginU = faceUVOriginU - faceSizeU
            else
                faceSizeU, faceSizeV = face.SizeX, face.SizeY
                faceUVOriginU, faceUVOriginV = modelUVOriginU + localU, modelUVOriginV + localV
                row1 = { grid[1], grid[2], grid[3], grid[4] + faceUVOriginU }
                row2 = { grid[5], grid[6], grid[7], grid[8] + faceUVOriginV }
            end

            place(index, row1, row2, faceUVOriginU - margin, faceUVOriginV - margin,
                faceSizeU + 2 * margin, faceSizeV + 2 * margin)
        end
    end
end

return InkMapLayout
