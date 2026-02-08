
---@class ss
local ss = SplashSWEPs
if not ss then return end

---Classes containing the oriented minimum bounding box.
---@class ss.IHasMBB
---@field MBBAngles Angle  The angle of minimum (oriented) bounding box.
---@field MBBOrigin Vector The origin of minimum (oriented) bounding box.
---@field MBBSize   Vector The size of minimum (oriented) bounding box in their local coordinates.
ss.struct "IHasMBB" {
    MBBAngles = Angle(),
    MBBOrigin = Vector(),
    MBBSize   = Vector(),
}

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
ss.struct "PaintableSurface" "IHasMBB" {
    AABBMax = Vector(),
    AABBMin = Vector(),
    Normal = Vector(),
    Grid = ss.new "PaintableGrid",
    StaticPropUnwrapIndex = nil,
    TriangleHash = nil,
    Triangles = nil,
    WorldToLocalGridMatrix = Matrix(),
    WorldToUVRow1 = nil,
    WorldToUVRow2 = nil,
    OffsetU = 0,
    OffsetV = 0,
    UVWidth = 0,
    UVHeight = 0,
}

---Vertices and some other info of a triangle in a displacement.
---@class ss.DisplacementTriangle : ss.IHasMBB
---@field [1]       Vector The positions of this triangle.
---@field [2]       Vector The positions of this triangle.
---@field [3]       Vector The positions of this triangle.
---@field [4]       Vector The position that the corresponding vertex originally was located at.
---@field [5]       Vector The position that the corresponding vertex originally was located at.
---@field [6]       Vector The position that the corresponding vertex originally was located at.
---@field BarycentricDot1 Vector Parameter to calculate barycentric coordinates v.
---@field BarycentricDot2 Vector Parameter to calculate barycentric coordinates w.
---@field BarycentricAdd1 number Parameter to calculate barycentric coordinates v.
---@field BarycentricAdd2 number Parameter to calculate barycentric coordinates w.
---@field WorldToLocalRotation VMatrix Rotation matrix to convert world coordinates into local coordinates.
ss.struct "DisplacementTriangle" "IHasMBB" {
    [1] = Vector(),
    [2] = Vector(),
    [3] = Vector(),
    [4] = Vector(),
    [5] = Vector(),
    [6] = Vector(),
    BarycentricDot1 = Vector(),
    BarycentricDot2 = Vector(),
    BarycentricAdd1 = 0,
    BarycentricAdd2 = 0,
    WorldToLocalRotation = Matrix(),
}

---Returns barycentric coordinates (1 - u - v, u, v) from given triangle.
---@param triangle ss.DisplacementTriangle
---@param query Vector
---@return Vector barycentric The coordinates which may be outside of the triangle.
function ss.BarycentricCoordinates(triangle, query)
    local u = query:Dot(triangle.BarycentricDot1) + triangle.BarycentricAdd1
    local v = query:Dot(triangle.BarycentricDot2) + triangle.BarycentricAdd2
    return Vector(1 - u - v, u, v)
end

---Reads a surface list from a file and stores them for later use.
---@param surfaces ss.PrecachedData.Surface[]?
function ss.SetupSurfaces(surfaces)
    if not surfaces then return end
    local SurfaceMeta = getmetatable(ss.new "PrecachedData.Surface")
    local MatrixMeta = getmetatable(ss.new "PrecachedData.MatrixTransform")
    local TriangleMeta = getmetatable(ss.new "PrecachedData.DisplacementTriangle")
    local VertexMeta = getmetatable(ss.new "PrecachedData.Vertex")
    local UVInfoMeta = getmetatable(ss.new "PrecachedData.UVInfo")
    local tempMatrix = Matrix()
    for i, surf in ipairs(surfaces) do
        setmetatable(surf, SurfaceMeta)
        setmetatable(surf.TransformPaintGrid, MatrixMeta)
        local ps = ss.new "PaintableSurface"
        ps.AABBMax = surf.AABBMax
        ps.AABBMin = surf.AABBMin
        ps.WorldToLocalGridMatrix:SetAngles(surf.TransformPaintGrid.Angle)
        ps.WorldToLocalGridMatrix:SetTranslation(surf.TransformPaintGrid.Translation)
        ps.Normal = surf.MBBAngles:Up()
        ps.Grid.Width = surf.PaintGridWidth
        ps.Grid.Height = surf.PaintGridHeight
        ps.MBBAngles = surf.MBBAngles
        ps.MBBOrigin = surf.MBBOrigin
        ps.MBBSize = surf.MBBSize
        ps.TriangleHash = surf.TriangleHash
        ps.Triangles = surf.Triangles and {}
        for _, v in ipairs(surf.Vertices) do setmetatable(v, VertexMeta) end
        for j, t in ipairs(surf.Triangles or {}) do
            setmetatable(t, TriangleMeta)
            ps.Triangles[j] = ss.new "DisplacementTriangle"
            ps.Triangles[j][1] = surf.Vertices[t.Index].Translation
            ps.Triangles[j][2] = surf.Vertices[t.Index + 1].Translation
            ps.Triangles[j][3] = surf.Vertices[t.Index + 2].Translation
            ps.Triangles[j][4] = surf.Vertices[t.Index].DisplacementOrigin
            ps.Triangles[j][5] = surf.Vertices[t.Index + 1].DisplacementOrigin
            ps.Triangles[j][6] = surf.Vertices[t.Index + 2].DisplacementOrigin
            ps.Triangles[j].BarycentricDot1 = t.BarycentricDot1
            ps.Triangles[j].BarycentricDot2 = t.BarycentricDot2
            ps.Triangles[j].BarycentricAdd1 = -ps.Triangles[j][1]:Dot(ps.Triangles[j].BarycentricDot1)
            ps.Triangles[j].BarycentricAdd2 = -ps.Triangles[j][1]:Dot(ps.Triangles[j].BarycentricDot2)
            ps.Triangles[j].MBBAngles       = t.MBBAngles
            ps.Triangles[j].MBBOrigin       = t.MBBOrigin
            ps.Triangles[j].MBBSize         = t.MBBSize
            ps.Triangles[j].WorldToLocalRotation:SetAngles(t.WorldToLocalGridRotation)
        end
        if CLIENT then
            local rtIndex = #ss.RenderTarget.Resolutions
            local rtSize = ss.RenderTarget.Resolutions[rtIndex]
            local uvInfo = setmetatable(surf.UVInfo[rtIndex], UVInfoMeta)
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
            ps.OffsetU  = uvInfo.OffsetU - ss.RT_MARGIN_PIXELS / rtSize / 2
            ps.OffsetV  = uvInfo.OffsetV - ss.RT_MARGIN_PIXELS / rtSize / 2
            ps.UVWidth  = uvInfo.Width   + ss.RT_MARGIN_PIXELS / rtSize
            ps.UVHeight = uvInfo.Height  + ss.RT_MARGIN_PIXELS / rtSize
        end
        ss.SurfaceArray[i] = ps
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
---The area of total wasted space is `2 * sx * sx`, so if `sx` is not the shortest,
---We swap the basis of the OBB as follows:
---
---- `sx` is the smallest: (X, Y, Z) -> (X, Y, Z)
---- `sy` is the smallest: (X, Y, Z) -> (Y, Z, X)
---- `sz` is the smallest: (X, Y, Z) -> (Z, X, Y)
---@param staticPropInfo ss.PrecachedData.StaticProp[]
---@param uvInfo ss.PrecachedData.StaticProp.UVInfo[][]
function ss.SetupSurfacesStaticProp(staticPropInfo, uvInfo)
    local StaticPropMeta = getmetatable(ss.new "PrecachedData.StaticProp")
    local StaticPropUVMeta = getmetatable(ss.new "PrecachedData.StaticProp.UVInfo")
    local numSurfaces = #ss.SurfaceArray
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
    local worldTmodel = Matrix()
    local absoluteuvRlocaluv = Matrix()
    local modelUVOriginInAbsoluteUV = Vector()
    local worldToUV = Matrix()
    for i, prop in ipairs(staticPropInfo or {}) do
        setmetatable(prop, StaticPropMeta)
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
        local obbHalfExtent = boundingBoxSize / 2
        local aabbCenter = worldTmodel * obbHalfExtent
        local aabbHalfExtent = Vector(
            obbHalfExtent.x * math.abs(worldTmodel:GetField(1, 1)) +
            obbHalfExtent.y * math.abs(worldTmodel:GetField(1, 2)) +
            obbHalfExtent.z * math.abs(worldTmodel:GetField(1, 3)),
            obbHalfExtent.x * math.abs(worldTmodel:GetField(2, 1)) +
            obbHalfExtent.y * math.abs(worldTmodel:GetField(2, 2)) +
            obbHalfExtent.z * math.abs(worldTmodel:GetField(2, 3)),
            obbHalfExtent.x * math.abs(worldTmodel:GetField(3, 1)) +
            obbHalfExtent.y * math.abs(worldTmodel:GetField(3, 2)) +
            obbHalfExtent.z * math.abs(worldTmodel:GetField(3, 3)))
        local aabbMax = aabbCenter + aabbHalfExtent
        local aabbMin = aabbCenter - aabbHalfExtent
        local hammerToPixel ---@type number
        local isRotated ---@type boolean
        if CLIENT then
            local rtIndex = #ss.RenderTarget.Resolutions
            local rtSize = ss.RenderTarget.Resolutions[rtIndex]
            local uvScale = ss.RenderTarget.HammerUnitsToUV or 1
            local uv = setmetatable(uvInfo[i][rtIndex], StaticPropUVMeta)
            hammerToPixel = uvScale * rtSize
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
            local faceForwardInModelSystem = localForwards[j]
            local faceAngleInModelSystem = faceForwardInModelSystem:AngleEx(faceNormalInModelSystem)
            local faceOriginInModelSystem = boundingBoxSize * faceLocalOriginCoefficients[j]
            local faceSizeInModelSystem = Vector(
                math.abs(boundingBoxSize:Dot(faceForwardInModelSystem)),
                math.abs(boundingBoxSize:Dot(faceAngleInModelSystem:Right())))
            local ps = ss.new "PaintableSurface"
            ps.AABBMax = aabbMax
            ps.AABBMin = aabbMin
            ps.WorldToLocalGridMatrix:SetAngles(faceAngleInModelSystem)
            ps.WorldToLocalGridMatrix:SetTranslation(faceOriginInModelSystem) -- modelTface
            ps.WorldToLocalGridMatrix:InvertTR()                              -- faceTmodel
            ps.WorldToLocalGridMatrix:Mul(modelTworld)                        -- faceTworld
            ps.Normal = Vector(faceNormalInModelSystem)
            ps.Normal:Rotate(worldTmodel:GetAngles())
            ps.Grid.Width  = math.ceil(faceSizeInModelSystem.x / ss.InkGridCellSize)
            ps.Grid.Height = math.ceil(faceSizeInModelSystem.y / ss.InkGridCellSize)
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
                -- +-------------> v  |    ,--- faceUVOrigin = (OffsetU, OffsetV)
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
                --           /  \ ^   /                      stored to WorldToUVMatrix
                --          /    \| / <--- faceUVOrigin (in model system)
                --         |      *-----> u'
                --         |
                --      modelUVOriginInAbsoluteUV
                local faceSizeInAbsoluteUV = absoluteuvRlocaluv * faceSizeInModelSystem
                faceSizeInAbsoluteUV:SetUnpacked(
                    math.abs(faceSizeInAbsoluteUV.x),
                    math.abs(faceSizeInAbsoluteUV.y), 0)
                local faceUVOrigin = boundingBoxSize * uvOffsetCoefficients[j]
                faceUVOrigin:SetUnpacked(
                    faceUVOrigin.x + faceUVOrigin.y,
                    faceUVOrigin.z, 0) -- in model local UV
                faceUVOrigin:Rotate(absoluteuvRlocaluv:GetAngles())
                faceUVOrigin:Add(modelUVOriginInAbsoluteUV) -- in absolute UV
                faceUVOrigin.x = faceUVOrigin.x - (isRotated and faceSizeInAbsoluteUV.x or 0)
                worldToUV:Set(absoluteuvRlocaluv)
                worldToUV:SetField(1, 4, isRotated and faceSizeInAbsoluteUV.x or 0) -- Translation X
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
                ps.OffsetU  = faceUVOrigin.x * hammerToPixel
                ps.OffsetV  = faceUVOrigin.y * hammerToPixel
                ps.UVWidth  = faceSizeInAbsoluteUV.x * hammerToPixel
                ps.UVHeight = faceSizeInAbsoluteUV.y * hammerToPixel
            end
            ss.SurfaceArray[numSurfaces + 6 * (i - 1) + j] = ps
        end
    end
end
