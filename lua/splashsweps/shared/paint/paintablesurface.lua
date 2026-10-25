
-- Paintable surfaces of the map: brush faces, displacements, and the faces of static prop bounding boxes.

---@class ss
local ss = SplashSWEPs
local PaintableGrid = ss.import "splashsweps/shared/paint/paintablegrid"
local Util          = ss.import "splashsweps/shared/util"

---@class ss.PaintableSurfaceModule
local PaintableSurface = ss.module "splashsweps/shared/paint/paintablesurface"

---Classes containing the oriented minimum bounding box.
---@class ss.IHasMBB
---@field MBBAngles Angle  The angle of minimum (oriented) bounding box.
---@field MBBOrigin Vector The origin of minimum (oriented) bounding box.
---@field MBBSize   Vector The size of minimum (oriented) bounding box in their local coordinates.

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
--- +-------------+--> V              WorldToUVMatrix
--- |             ^                     :GetInverseTR()
--- |             |                     :GetTranslation()
--- |          OffsetU                        |
--- |             |    |<----UVHeight--->|    |
--- |             v    |                 |    |
--- +<----OffsetV-+--->+--------------<==@ <--+
--- |             ^    |                 $
--- v             |    |                 v
--- U          UVWidth |                 |
---               |    |                 |
---               v    |                 |
---              -+----+-----------------+
---```
---@class ss.PaintableSurface : ss.IHasMBB
---@field AABBMax                Vector           AABB maximum of this surface in world coordinates.
---@field AABBMin                Vector           AABB minimum of this surface in world coordinates.
---@field Normal                 Vector           Normal vector of this surface.
---@field Grid                   ss.PaintableGrid Represents serverside "canvas" for this surface to manage collision detection against painted ink.
---@field StaticPropUnwrapIndex  integer?         Determines how this static prop surfaces are unwrapped.
---@field TriangleHash           table<integer, integer[]>? Hash table to lookup triangles of a displacement.
---@field Triangles              ss.DisplacementTriangle[]? Array of triangles of a displacement.
---@field WorldToLocalGridMatrix VMatrix The transformation matrix to convert world coordinates into local coordinates. This does not modify scales.
---@field WorldToUVRow1          number[] The first row of transformation matrox to convert world position into UV space without scaling.
---@field WorldToUVRow2          number[] The second row of transformation matrox to convert world position into UV space without scaling.
---@field OffsetU                number  The u-coordinate of left-top corner of this surface in UV space.
---@field OffsetV                number  The v-coordinate of left-top corner of this surface in UV space.
---@field UVWidth                number  The width of this surface in UV space.
---@field UVHeight               number  The height of this surface in UV space.
---@field Index                  integer The index of this surface in PaintableSurface.Surfaces used for debug purpose.

---Vertices and some other info of a triangle in a displacement.
---@class ss.DisplacementTriangle : ss.IHasMBB
---@field [1]       Vector The positions of this triangle.
---@field [2]       Vector The positions of this triangle.
---@field [3]       Vector The positions of this triangle.
---@field [4]       Vector Paint reference position corresponding to this triangle vertex.
---@field [5]       Vector Paint reference position corresponding to this triangle vertex.
---@field [6]       Vector Paint reference position corresponding to this triangle vertex.
---@field BarycentricDot1 Vector Parameter to calculate barycentric coordinates v.
---@field BarycentricDot2 Vector Parameter to calculate barycentric coordinates w.
---@field BarycentricAdd1 number Parameter to calculate barycentric coordinates v.
---@field BarycentricAdd2 number Parameter to calculate barycentric coordinates w.
---@field WorldToLocalRotation VMatrix Rotation matrix to convert world coordinates into local coordinates.

---@class ss.PaintableSurfaceModule.State
---@field Surfaces           ss.PaintableSurface[]              Paintable surfaces of the world and static props.
---@field BrushModelSurfaces table<integer, ss.PaintableSurface[]> Brush model index --> its paintable surfaces.
---@field ModelIndexBits     integer                            Required bits to transfer a brush model index as an unsigned integer.
local state = ss.state("splashsweps/shared/paint/paintablesurface", {
    Surfaces = {},
    BrushModelSurfaces = {},
}) ---@type ss.PaintableSurfaceModule.State

---Paintable surfaces of the world and static props.
PaintableSurface.Surfaces = state.Surfaces

---Paintable surfaces of brush entities, which are not registered to ss.SurfaceHash
---because they can move away from where the map compiler put them.
--- `= { [model index] = { surface, ... }, ... }`
---where the model index is 1-based index of the BSP model lump (`*N` model name refers to N + 1),
---and the surfaces are in the model's local coordinate system.
PaintableSurface.BrushModelSurfaces = state.BrushModelSurfaces

---Returns the required bits to transfer a brush model index as an unsigned integer.
---@return integer
function PaintableSurface.GetModelIndexBits()
    return state.ModelIndexBits
end

---Creates a paintable surface with an empty grid.
---@param index      integer
---@param gridWidth  integer
---@param gridHeight integer
---@return ss.PaintableSurface
local function newSurface(index, gridWidth, gridHeight)
    return {
        Index = index,
        AABBMax = Vector(),
        AABBMin = Vector(),
        Normal = Vector(),
        Grid = PaintableGrid.new(gridWidth, gridHeight),
        WorldToLocalGridMatrix = Matrix(),
        OffsetU = 0,
        OffsetV = 0,
        UVWidth = 0,
        UVHeight = 0,
        MBBAngles = Angle(),
        MBBOrigin = Vector(),
        MBBSize = Vector(),
    }
end

---Returns barycentric coordinates (1 - u - v, u, v) from given triangle.
---@param triangle ss.DisplacementTriangle
---@param query Vector
---@return Vector barycentric The coordinates which may be outside of the triangle.
function PaintableSurface.BarycentricCoordinates(triangle, query)
    local u = query:Dot(triangle.BarycentricDot1) + triangle.BarycentricAdd1
    local v = query:Dot(triangle.BarycentricDot2) + triangle.BarycentricAdd2
    return Vector(1 - u - v, u, v)
end

---Reads a surface list from a file and stores them for later use.
---@param surfaces  ss.PrecachedData.Surface[]?
---@param numModels integer Number of entries in the BSP model lump.
function PaintableSurface.Setup(surfaces, numModels)
    if not surfaces then return end
    state.ModelIndexBits = math.max(select(2, math.frexp(numModels - 1)), 1)
    table.Empty(state.BrushModelSurfaces)
    local tempMatrix = Matrix()
    for i, surf in ipairs(surfaces) do
        local ps = newSurface(i, surf.PaintGridWidth, surf.PaintGridHeight)
        ps.AABBMax = surf.AABBMax
        ps.AABBMin = surf.AABBMin
        ps.WorldToLocalGridMatrix:SetAngles(surf.TransformPaintGrid.Angle)
        ps.WorldToLocalGridMatrix:SetTranslation(surf.TransformPaintGrid.Translation)
        ps.Normal = surf.MBBAngles:Up()
        ps.MBBAngles = surf.MBBAngles
        ps.MBBOrigin = surf.MBBOrigin
        ps.MBBSize = surf.MBBSize
        ps.TriangleHash = surf.TriangleHash
        ps.Triangles = surf.Triangles and {}
        for j, t in ipairs(surf.Triangles or {}) do
            local v1, v2, v3 = surf.Vertices[t.Index], surf.Vertices[t.Index + 1], surf.Vertices[t.Index + 2]
            local worldToLocal = Matrix()
            worldToLocal:SetAngles(t.WorldToLocalGridRotation)
            ps.Triangles[j] = {
                v1.Translation,
                v2.Translation,
                v3.Translation,
                v1.DispPaintOrigin,
                v2.DispPaintOrigin,
                v3.DispPaintOrigin,
                BarycentricDot1      = t.BarycentricDot1,
                BarycentricDot2      = t.BarycentricDot2,
                BarycentricAdd1      = -v1.Translation:Dot(t.BarycentricDot1),
                BarycentricAdd2      = -v1.Translation:Dot(t.BarycentricDot2),
                MBBAngles            = t.MBBAngles,
                MBBOrigin            = t.MBBOrigin,
                MBBSize              = t.MBBSize,
                WorldToLocalRotation = worldToLocal,
            }
        end
        if CLIENT then
            local rtIndex = #ss.RenderTarget.Resolutions
            local rtSize = ss.RenderTarget.Resolutions[rtIndex]
            local uvInfo = surf.UVInfo[rtIndex]
            tempMatrix:SetAngles(uvInfo.Angle)
            tempMatrix:SetTranslation(uvInfo.Translation)
            ps.WorldToUVRow1 = {
                tempMatrix:GetField(1, 1),
                tempMatrix:GetField(1, 2),
                tempMatrix:GetField(1, 3),
                tempMatrix:GetField(1, 4),
            }
            ps.WorldToUVRow2 = {
                tempMatrix:GetField(2, 1),
                tempMatrix:GetField(2, 2),
                tempMatrix:GetField(2, 3),
                tempMatrix:GetField(2, 4),
            }
            local bilinearGuard = ss.RT_BILINEAR_GUARD_PIXELS / rtSize
            ps.OffsetU  = uvInfo.OffsetU + bilinearGuard
            ps.OffsetV  = uvInfo.OffsetV + bilinearGuard
            ps.UVWidth  = uvInfo.Width  - 2 * bilinearGuard
            ps.UVHeight = uvInfo.Height - 2 * bilinearGuard
        end
        state.Surfaces[i] = ps
        if surf.ModelIndex > 1 then
            state.BrushModelSurfaces[surf.ModelIndex]
            = table.ForceInsert(state.BrushModelSurfaces[surf.ModelIndex], ps)
        end
    end
end

---Reads a list of static props and stores them for later use.
---
---Each static prop has its own oriented bounding box (OBB).
---We project the vertices of the prop onto one of the surfaces of the OBB.
---Then, unwrap the OBB to the UV space.
---
---First, we set up a coordinate system on the surface
---where its X axis will be the U coordinates in UV space
---and its Y axis will be the V coordinates.
---
---```text
---.      v
---. z   /
---. ^  y
---. | /
---. |/
---. *--__
---.      ''-->_x
---.            ''-->_u
---```
---
---The coordinate system will be determined as follows.
---
---Let `X`, `Y`, and `Z` be the basis of the OBB
---and `S = (sx, sy, sz)` be the size of the OBB along each basis.
---
---- Orientation of the coordinate system for each surface:
---  - Normal = `localNormals = { X, Y, Z, -X, -Y, -Z }`
---  - Tangent = `normalToTangent * localNormals[i]` which means the following replacement:
---    - `X` -> `-Y`
---    - `Y` ->  `X`
---    - `Z` -> `-Y`
---  - Binormal = `tangent:AngleEx(normal)`
---- Origin of the coordinate system = `S * localOriginCoefficients` (element-wise multiplication)
---- Offset in UV space: `mul = S * uvOffsetCoefficients` (element-wise multiplication)
---  - u = `mul.x + mul.y`
---  - v = `mul.z`
---
---The following figure visualizes how the corrdinate systems of the OBB surfaces are placed:
---
---```text
---.                             z
---.                            /
---.                        z  A''-> x
---.                        ^ /|  #2(X, -Z, Y)
---.                        |/ V
---.                        |  y
---.                       /|''---___
---.                      / /''--> y '''---___
---.                     / / #3(-Y, X, Z)    /|
---. #4(Y, -Z, -X)      / x                 / |
---.          x        /                   / A''--> z
---. z <--___/        /                   / /|| #1(-Y, -Z, X)
---.         |''--__ /                   / x ||
---.         V      |'''---___          /    V|
---.         y                '''---___/     y|
---.                Z          x <--_._|___   |
---.                ^               /| |  |   /
---.                |   Y          / V |  |  /
---.                |  /          z  y |  +-/-- #5(-X, -Z, -Y)
---.       Model    | /                |   /
---.        local   |/                 |  /
---.         origin *'''---__, X       | /
---.                | x       '''---___|/
---.                |/
---.                |''-> y
---.                V #6(Y, X, -Z)
---.                z
---```
---
---Unwrapped OBB in UV space is shown in this figure.
---+/- X,Y,Z indicates corresponding normal vectors of the OBB surfaces.
---
---```text
---.      sz   sx
---.    +----+----+---> v
---. sx | -Y |    |
---.    +----+----+
---. sy | -X | -Z |
---.    +----+----+
---. sx | +Y |    |
---.    +----+----+
---. sy | +X | +Z |
---.    +----+----+
---.    |
---.    V
---.    u
---```
---
---Each cell above additionally has `m = ss.MARGIN_HAMMER_UNITS` on both sides like the other surfaces,
---so the cell of a face with `uvOffsetCoefficients = (a, b, c)` starts at
---`u = a * (sx + 2m) + b * (sy + 2m)` and `v = c * (sz + 2m)`, and its face starts at `m` inside the cell.
---
---The area of total wasted space is `2 * sx * sx`, so if `sx` is not the shortest,
---We swap the basis of the OBB as follows:
---
---- `sx` is the smallest: (X, Y, Z) -> (X, Y, Z)
---- `sy` is the smallest: (X, Y, Z) -> (Y, Z, X)
---- `sz` is the smallest: (X, Y, Z) -> (Z, X, Y)
---@param staticPropInfo ss.PrecachedData.StaticProp[]
---@param uvInfo ss.PrecachedData.StaticProp.UVInfo[][]
function PaintableSurface.SetupStaticProps(staticPropInfo, uvInfo)
    local numSurfaces = #state.Surfaces
    local vec = Vector
    local localNormals = {
        vec( 1, 0, 0), vec(0,  1, 0), vec(0, 0,  1),
        vec(-1, 0, 0), vec(0, -1, 0), vec(0, 0, -1),
    }
    -- [  0  1   0 ]
    -- [ -1  0  -1 ] * localNormals = (X, Y, Z) -> (-Y, X, -Y)
    -- [  0  0   0 ]
    local localForwards = {
        localNormals[5], localNormals[1], localNormals[5],
        localNormals[2], localNormals[4], localNormals[2],
    }
    -- Matrix(X, Y, Z) * xyzTyzx = (Y, Z, X)
    local xyzTyzx = Matrix {
        { 0, 0, 1, 0 },
        { 1, 0, 0, 0 },
        { 0, 1, 0, 0 },
        { 0, 0, 0, 1 },
    }
    -- xyzTzxy = xyzTyzx * xyzTyzx
    -- xyzTzxy * Vector(X, Y, Z) = (Y, Z, X)
    local xyzTzxy = xyzTyzx:GetTransposed()
    local faceLocalOriginCoefficients = {
        vec(1, 1, 1), vec(0, 1, 1), vec(0, 1, 1),
        vec(0, 0, 1), vec(1, 0, 1), vec(0, 0, 0),
    }
    local uvOffsetCoefficients = {
        vec(2, 1, 0), vec(1, 1, 0), vec(2, 1, 1),
        vec(1, 0, 0), vec(0, 0, 0), vec(1, 0, 1),
    }
    local marginPerSide = ss.MARGIN_HAMMER_UNITS
    local bothSidesMargin = Util.vector_one * 2 * marginPerSide
    local worldTmodel = Matrix()
    local absoluteuvRlocaluv = Matrix()
    local modelUVOriginInAbsoluteUV = Vector()
    local worldToUV = Matrix()
    for i, prop in ipairs(staticPropInfo or {}) do
        local boundingBoxSize = prop.BoundsMax - prop.BoundsMin
        worldTmodel:SetAngles(prop.Angles)
        worldTmodel:SetTranslation(prop.Position)
        worldTmodel:SetTranslation(worldTmodel * prop.BoundsMin)
        if prop.UnwrapIndex == 2 then
            worldTmodel:Mul(xyzTyzx)
            boundingBoxSize:Mul(xyzTzxy) -- xyzTyzx:GetTransposed()
        elseif prop.UnwrapIndex == 3 then
            worldTmodel:Mul(xyzTzxy)
            boundingBoxSize:Mul(xyzTyzx) -- xyzTzxy:GetTransposed()
        end

        local modelTworld = worldTmodel:GetInverseTR()
        local aabbMin, aabbMax = Util.TransformAABB(worldTmodel, vector_origin, boundingBoxSize)
        local uvScale ---@type number
        local bilinearGuard ---@type number
        local isRotated ---@type boolean
        if CLIENT then
            local rtIndex = #ss.RenderTarget.Resolutions
            local rtSize = ss.RenderTarget.Resolutions[rtIndex]
            local uv = uvInfo[i][rtIndex]
            uvScale = ss.RenderTarget.HammerUnitsToUV
            bilinearGuard = ss.RT_BILINEAR_GUARD_PIXELS / rtSize
            isRotated = uv.Offset.z > 0
            if isRotated then
                -- +--------> v
                -- |   v'
                -- |   ^
                -- v   +---> u'
                -- u    \__model local uv space
                absoluteuvRlocaluv:SetUnpacked(
                    0, -1, 0, 0,
                    1,  0, 0, 0,
                    0,  0, 1, 0,
                    0,  0, 0, 1)
                modelUVOriginInAbsoluteUV:SetUnpacked(
                    uv.Offset.x + uv.Width, uv.Offset.y, 0)
            else
                -- +--------> v
                -- | model local uv space
                -- |   +---> v'
                -- v   |
                -- u   u'
                absoluteuvRlocaluv:Identity()
                modelUVOriginInAbsoluteUV:SetUnpacked(
                    uv.Offset.x, uv.Offset.y, 0)
            end
        end
        for j, faceNormalInModelSystem in ipairs(localNormals) do
            local index = numSurfaces + 6 * (i - 1) + j
            local faceForwardInModelSystem = localForwards[j]
            local faceAngleInModelSystem = faceForwardInModelSystem:AngleEx(faceNormalInModelSystem)
            local faceOriginInModelSystem = boundingBoxSize * faceLocalOriginCoefficients[j]
            local faceSizeInModelSystem = Vector(
                math.abs(boundingBoxSize:Dot(faceForwardInModelSystem)),
                math.abs(boundingBoxSize:Dot(faceAngleInModelSystem:Right())))
            local ps = newSurface(index,
                math.ceil(faceSizeInModelSystem.x / ss.InkGridCellSize),
                math.ceil(faceSizeInModelSystem.y / ss.InkGridCellSize))
            ps.AABBMax = aabbMax
            ps.AABBMin = aabbMin
            ps.WorldToLocalGridMatrix:SetAngles(faceAngleInModelSystem)
            ps.WorldToLocalGridMatrix:SetTranslation(faceOriginInModelSystem) -- modelTface
            ps.WorldToLocalGridMatrix:InvertTR()                              -- faceTmodel
            ps.WorldToLocalGridMatrix:Mul(modelTworld)                        -- faceTworld
            ps.Normal = Vector(faceNormalInModelSystem)
            ps.Normal:Rotate(worldTmodel:GetAngles())
            ps.StaticPropUnwrapIndex = prop.UnwrapIndex
            ps.MBBAngles = worldTmodel:GetAngles()
            ps.MBBOrigin = worldTmodel:GetTranslation()
            ps.MBBSize   = boundingBoxSize
            if CLIENT then
                -- +-------------> v
                -- |\ <--- modelUVOriginInAbsoluteUV
                -- | +----> v'
                -- | | \ <--- faceUVOriginInModelSystem
                -- | V  @==> y, v" --+
                -- | u' |            |
                -- V    V------------+
                -- u    x, u"

                --         modelUVOriginInAbsoluteUV
                --         + absoluteuvRlocaluv * faceUVOrigin (in model system)
                --                    |
                -- +-------------> v  |    ,--- faceUVOrigin (the clip range adds the margin around it)
                -- |\\                |   /
                -- | \ \             /   @=====> v" ----+ (x , y )
                -- |  \  \          /    |              |    face local system
                -- |   \   \       /     V              |    converted from the world
                -- |    \    \    /      u"             | (u , v )
                -- V     \     \ /       |              |    absolute UV
                -- u      \      \       |              |    in the render target texture
                --         \       \     y              | (u', v')
                --          \        \   ^              |    model local UV
                --           \         \ |              |    from static prop UV info
                --            \          X=====> x -----+ (u", v")
                --            /\  v'    /                    face local UV
                --           /  \ ^   /                      WorldToUVRow1/2 maps the world to (u, v)
                --          /    \| / <--- faceUVOrigin (in model system)
                --         |      *-----> u'
                --         |
                --      modelUVOriginInAbsoluteUV
                local faceSizeInAbsoluteUV = absoluteuvRlocaluv * faceSizeInModelSystem
                faceSizeInAbsoluteUV:SetUnpacked(
                    math.abs(faceSizeInAbsoluteUV.x),
                    math.abs(faceSizeInAbsoluteUV.y), 0)
                local faceUVOrigin = (boundingBoxSize + bothSidesMargin) * uvOffsetCoefficients[j]
                faceUVOrigin:SetUnpacked(
                    faceUVOrigin.x + faceUVOrigin.y + marginPerSide,
                    faceUVOrigin.z + marginPerSide, 0) -- in model local UV
                faceUVOrigin:Rotate(absoluteuvRlocaluv:GetAngles())
                faceUVOrigin:Add(modelUVOriginInAbsoluteUV) -- in absolute UV
                worldToUV:Set(absoluteuvRlocaluv)
                worldToUV:SetField(1, 4, faceUVOrigin.x)
                worldToUV:SetField(2, 4, faceUVOrigin.y)
                faceUVOrigin.x = faceUVOrigin.x - (isRotated and faceSizeInAbsoluteUV.x or 0)
                worldToUV:Mul(ps.WorldToLocalGridMatrix) -- absoluteuvTlocaluv * faceTworld
                ps.WorldToUVRow1 = {
                    worldToUV:GetField(1, 1),
                    worldToUV:GetField(1, 2),
                    worldToUV:GetField(1, 3),
                    worldToUV:GetField(1, 4),
                }
                ps.WorldToUVRow2 = {
                    worldToUV:GetField(2, 1),
                    worldToUV:GetField(2, 2),
                    worldToUV:GetField(2, 3),
                    worldToUV:GetField(2, 4),
                }
                ps.OffsetU  = (faceUVOrigin.x - marginPerSide) * uvScale + bilinearGuard
                ps.OffsetV  = (faceUVOrigin.y - marginPerSide) * uvScale + bilinearGuard
                ps.UVWidth  = (faceSizeInAbsoluteUV.x + 2 * marginPerSide) * uvScale - 2 * bilinearGuard
                ps.UVHeight = (faceSizeInAbsoluteUV.y + 2 * marginPerSide) * uvScale - 2 * bilinearGuard
            end
            state.Surfaces[index] = ps
        end
    end
end

return PaintableSurface
