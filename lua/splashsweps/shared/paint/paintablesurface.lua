
-- Paintable surfaces of the map: brush faces, displacements, and the faces of static prop bounding boxes.

---@class ss
local ss = SplashSWEPs
local Geometry      = ss.import "splashsweps/shared/geometry"
local PaintableGrid = ss.import "splashsweps/shared/paint/paintablegrid"

---@class ss.PaintableSurfaceModule
local PaintableSurface = ss.module "splashsweps/shared/paint/paintablesurface"

---A surface to paint, which has a paint grid in the coordinates converted from the world by WorldToLocalGrid.
---```text
---World origin
---  +--> x
---  |
---  v   The origin of the paint grid
---  y      +--> X
---         |
---         v   * (Xi, Yi) = WorldToLocalGrid * (xi, yi)
---         Y
---```
---@class ss.PaintableSurface
---@field AABBMinX              number AABB minimum of this surface in world coordinates.
---@field AABBMinY              number
---@field AABBMinZ              number
---@field AABBMaxX              number AABB maximum of this surface in world coordinates.
---@field AABBMaxY              number
---@field AABBMaxZ              number
---@field NormalX               number Normal vector of this surface.
---@field NormalY               number
---@field NormalZ               number
---@field Grid                  ss.PaintableGrid Represents serverside "canvas" for this surface to manage collision detection against painted ink.
---@field StaticPropUnwrapIndex integer?         Determines how this static prop surfaces are unwrapped.
---@field TriangleHash          ss.PrecachedData.TriangleHash? Spatial hash to look up triangles of a displacement.
---@field Triangles             ss.DisplacementTriangle[]? Array of triangles of a displacement.
---@field PositionX             number[]? Positions of the vertices of a displacement, which its triangles refer to.
---@field PositionY             number[]?
---@field PositionZ             number[]?
---@field PaintOriginX          number[]? Positions on the flat surface the vertices of a displacement are mapped onto.
---@field PaintOriginY          number[]?
---@field PaintOriginZ          number[]?
---@field WorldToLocalGrid      number[] The transform of ss.GeometryModule to convert world coordinates into local coordinates of the paint grid. This does not modify scales.
---The transform of ss.GeometryModule to convert world coordinates into local coordinates of the minimum bounding box,
---which is [0, MBBSizeX] x [0, MBBSizeY] x [0, MBBSizeZ] there.
---A flat surface shares WorldToLocalGrid, and the faces of a static prop share the box of the prop.
---@field WorldToMBB            number[]
---@field MBBSizeX              number   The size of the minimum bounding box.
---@field MBBSizeY              number
---@field MBBSizeZ              number
---@field Index                 integer  The index of this surface in PaintableSurface.Surfaces, which keys what other modules keep for each surface.

---A triangle in a displacement.
---@class ss.DisplacementTriangle
---@field VertexIndex1     integer The vertices of this triangle in the vertex arrays of the displacement.
---@field VertexIndex2     integer
---@field VertexIndex3     integer
---@field NormalX          number  Normal vector of this triangle, (t2 - t3) x (t1 - t3) normalized for its vertices t1, t2, and t3.
---@field NormalY          number
---@field NormalZ          number
---@field BarycentricDot1X number  Parameter to calculate barycentric coordinates v.
---@field BarycentricDot1Y number
---@field BarycentricDot1Z number
---@field BarycentricDot2X number  Parameter to calculate barycentric coordinates w.
---@field BarycentricDot2Y number
---@field BarycentricDot2Z number
---@field BarycentricAdd1  number  Parameter to calculate barycentric coordinates v.
---@field BarycentricAdd2  number  Parameter to calculate barycentric coordinates w.
---The rotation of ss.GeometryModule which converts world angles into local ones to map them to the paint grid.
---@field WorldToLocalGridRotation number[]

---@class ss.PaintableSurfaceModule.State
---@field Surfaces           ss.PaintableSurface[] Paintable surfaces of the world and static props.
---@field BrushModelSurfaces table<integer, ss.PaintableSurface[]> Brush model index --> its paintable surfaces.
---@field ModelIndexBits     integer Required bits to transfer a brush model index as an unsigned integer.
local state = ss.state("splashsweps/shared/paint/paintablesurface", {
    Surfaces = {},
    BrushModelSurfaces = {},
}) ---@type ss.PaintableSurfaceModule.State

---Paintable surfaces of the world and static props:
---the surfaces of the map cache in order, followed by the 6 faces of each static prop
---in the order of the faces of PaintableSurface.GetStaticPropBox.
PaintableSurface.Surfaces = state.Surfaces

---Paintable surfaces of brush entities, which are not registered to the spatial hash of the world
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
---@param index            integer
---@param gridWidth        integer
---@param gridHeight       integer
---@param worldToLocalGrid number[]
---@return ss.PaintableSurface
local function newSurface(index, gridWidth, gridHeight, worldToLocalGrid)
    return {
        Index = index,
        AABBMinX = 0,
        AABBMinY = 0,
        AABBMinZ = 0,
        AABBMaxX = 0,
        AABBMaxY = 0,
        AABBMaxZ = 0,
        NormalX = 0,
        NormalY = 0,
        NormalZ = 0,
        Grid = PaintableGrid.new(gridWidth, gridHeight),
        WorldToLocalGrid = worldToLocalGrid,
        WorldToMBB = worldToLocalGrid,
        MBBSizeX = 0,
        MBBSizeY = 0,
        MBBSizeZ = 0,
    }
end

---Returns barycentric coordinates (1 - u - v, u, v) from given triangle.
---The coordinates may be outside of the triangle.
---@param triangle ss.DisplacementTriangle
---@param x number The query point.
---@param y number
---@param z number
---@return number
---@return number u
---@return number v
function PaintableSurface.BarycentricCoordinates(triangle, x, y, z)
    local t = triangle
    local u = Geometry.Dot(x, y, z, t.BarycentricDot1X, t.BarycentricDot1Y, t.BarycentricDot1Z) + t.BarycentricAdd1
    local v = Geometry.Dot(x, y, z, t.BarycentricDot2X, t.BarycentricDot2Y, t.BarycentricDot2Z) + t.BarycentricAdd2
    return 1 - u - v, u, v
end

---Reads a surface list from a file and stores them for later use.
---@param surfaces  ss.PrecachedData.Surface[]?
---@param numModels integer Number of entries in the BSP model lump.
function PaintableSurface.Setup(surfaces, numModels)
    if not surfaces then return end
    state.ModelIndexBits = math.max(select(2, math.frexp(numModels - 1)), 1)
    table.Empty(state.BrushModelSurfaces)
    for i, surf in ipairs(surfaces) do
        local g = surf.WorldToLocalGrid
        local ps = newSurface(i, surf.PaintGridWidth, surf.PaintGridHeight, g)
        local mbbToWorld = Geometry.FromAngles(surf.MBBPitch, surf.MBBYaw, surf.MBBRoll, 0, 0, 0)
        ps.AABBMinX, ps.AABBMinY, ps.AABBMinZ = surf.AABBMinX, surf.AABBMinY, surf.AABBMinZ
        ps.AABBMaxX, ps.AABBMaxY, ps.AABBMaxZ = surf.AABBMaxX, surf.AABBMaxY, surf.AABBMaxZ
        ps.NormalX, ps.NormalY, ps.NormalZ = mbbToWorld[3], mbbToWorld[7], mbbToWorld[11]
        ps.MBBSizeX, ps.MBBSizeY, ps.MBBSizeZ = surf.MBBSizeX, surf.MBBSizeY, surf.MBBSizeZ
        local triangles = surf.DisplacementTriangles
        if triangles then
            -- The box of a displacement is in 3D, while its paint grid is made from its flattened shape.
            ps.WorldToMBB = Geometry.InvertRotationTranslation(Geometry.FromAngles(
                surf.MBBPitch, surf.MBBYaw, surf.MBBRoll, surf.MBBOriginX, surf.MBBOriginY, surf.MBBOriginZ))
            ps.TriangleHash = surf.TriangleHash
            local xs, ys, zs = surf.PositionX, surf.PositionY, surf.PositionZ
            local vertexIndices = surf.VertexIndices
            ps.PositionX, ps.PositionY, ps.PositionZ = xs, ys, zs
            ps.PaintOriginX, ps.PaintOriginY, ps.PaintOriginZ = surf.PaintOriginX, surf.PaintOriginY, surf.PaintOriginZ
            ps.Triangles = {}
            for j, t in ipairs(triangles) do
                local i1, i2, i3 = vertexIndices[3 * j - 2], vertexIndices[3 * j - 1], vertexIndices[3 * j]
                local r = t.WorldToLocalGridRotation
                local nx, ny, nz = Geometry.Normalize(Geometry.Cross(
                    xs[i2] - xs[i3], ys[i2] - ys[i3], zs[i2] - zs[i3],
                    xs[i1] - xs[i3], ys[i1] - ys[i3], zs[i1] - zs[i3]))
                ps.Triangles[j] = {
                    VertexIndex1     = i1,
                    VertexIndex2     = i2,
                    VertexIndex3     = i3,
                    NormalX          = nx,
                    NormalY          = ny,
                    NormalZ          = nz,
                    BarycentricDot1X = t.BarycentricDot1X,
                    BarycentricDot1Y = t.BarycentricDot1Y,
                    BarycentricDot1Z = t.BarycentricDot1Z,
                    BarycentricDot2X = t.BarycentricDot2X,
                    BarycentricDot2Y = t.BarycentricDot2Y,
                    BarycentricDot2Z = t.BarycentricDot2Z,
                    BarycentricAdd1  = -Geometry.Dot(xs[i1], ys[i1], zs[i1],
                        t.BarycentricDot1X, t.BarycentricDot1Y, t.BarycentricDot1Z),
                    BarycentricAdd2  = -Geometry.Dot(xs[i1], ys[i1], zs[i1],
                        t.BarycentricDot2X, t.BarycentricDot2Y, t.BarycentricDot2Z),
                    WorldToLocalGridRotation = {
                        r[1], r[2], r[3], 0,
                        r[4], r[5], r[6], 0,
                        r[7], r[8], r[9], 0,
                    },
                }
            end
        end
        state.Surfaces[i] = ps
        if surf.ModelIndex > 1 then
            state.BrushModelSurfaces[surf.ModelIndex]
            = table.ForceInsert(state.BrushModelSurfaces[surf.ModelIndex], ps)
        end
    end
end

---A face of the bounding box of a static prop in the coordinates of the box,
---with the origin, the offset in the UV space, and the forward as described in PaintableSurface.GetStaticPropBox.
---@class ss.PaintableSurface.BoxFace
---@field NormalX   number The normal, which is the up of the face.
---@field NormalY   number
---@field NormalZ   number
---@field ForwardX  number The forward of the face.
---@field ForwardY  number
---@field ForwardZ  number
---@field OriginX   number The origin of the face divided by the size of the box.
---@field OriginY   number
---@field OriginZ   number
---@field UVOffsetX number The offset of the face in the UV space, in the size of the box plus the margins.
---@field UVOffsetY number
---@field UVOffsetZ number

---@param normal   number[]
---@param forward  number[]
---@param origin   number[]
---@param uvOffset number[]
---@return ss.PaintableSurface.BoxFace
local function boxFace(normal, forward, origin, uvOffset)
    return {
        NormalX   = normal[1],   NormalY   = normal[2],   NormalZ   = normal[3],
        ForwardX  = forward[1],  ForwardY  = forward[2],  ForwardZ  = forward[3],
        OriginX   = origin[1],   OriginY   = origin[2],   OriginZ   = origin[3],
        UVOffsetX = uvOffset[1], UVOffsetY = uvOffset[2], UVOffsetZ = uvOffset[3],
    }
end

---The faces of the bounding box of a static prop, #1 to #6.
local BOX_FACES = {
    boxFace({  1,  0,  0 }, {  0, -1,  0 }, { 1, 1, 1 }, { 2, 1, 0 }),
    boxFace({  0,  1,  0 }, {  1,  0,  0 }, { 0, 1, 1 }, { 1, 1, 0 }),
    boxFace({  0,  0,  1 }, {  0, -1,  0 }, { 0, 1, 1 }, { 2, 1, 1 }),
    boxFace({ -1,  0,  0 }, {  0,  1,  0 }, { 0, 0, 1 }, { 1, 0, 0 }),
    boxFace({  0, -1,  0 }, { -1,  0,  0 }, { 1, 0, 1 }, { 0, 0, 0 }),
    boxFace({  0,  0, -1 }, {  0,  1,  0 }, { 0, 0, 0 }, { 1, 0, 1 }),
}

---The rotation whose forward, left, and up are the Y, Z, and X axes, which swaps the axes of a box.
local AXES_YZX = {
    0, 0, 1, 0,
    1, 0, 0, 0,
    0, 1, 0, 0,
}

---The rotation whose forward, left, and up are the Z, X, and Y axes, which swaps the axes of a box.
local AXES_ZXY = {
    0, 1, 0, 0,
    0, 0, 1, 0,
    1, 0, 0, 0,
}

---A face of the bounding box of a static prop.
---@class ss.PaintableSurface.StaticPropFace
---@field BoxFace ss.PaintableSurface.BoxFace The orientation and the place in the UV space of the face.
---@field ToWorld number[] The transform from the face to the world, whose columns are the forward, the left, the normal, and the origin.
---@field SizeX   number   The size of the face along its forward.
---@field SizeY   number   The size of the face along its left.

---The bounding box of a static prop with its axes swapped by its unwrap index.
---@class ss.PaintableSurface.StaticPropBox
---@field ToWorld number[] The transform from the box, whose origin is at the minimum of the bounds, to the world.
---@field SizeX   number
---@field SizeY   number
---@field SizeZ   number
---@field Faces   ss.PaintableSurface.StaticPropFace[] The faces #1 to #6.

---Returns the bounding box of a static prop and its faces,
---which are paintable surfaces in the paint grids and in the ink map.
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
---- Orientation of the coordinate system for each surface (BOX_FACES):
---  - Normal = `{ X, Y, Z, -X, -Y, -Z }`
---  - Forward (Tangent) = the following replacement of the normal:
---    - `X` -> `-Y`
---    - `Y` ->  `X`
---    - `Z` -> `-Y`
---  - Left (Binormal) = Normal × Forward
---- Origin of the coordinate system = `S * Origin` (element-wise multiplication)
---- Offset in UV space: `mul = S * UVOffset` (element-wise multiplication)
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
---so the cell of a face with `UVOffset = (a, b, c)` starts at
---`u = a * (sx + 2m) + b * (sy + 2m)` and `v = c * (sz + 2m)`, and its face starts at `m` inside the cell.
---
---The area of total wasted space is `2 * sx * sx`, so if `sx` is not the shortest,
---We swap the basis of the OBB as follows:
---
---- `sx` is the smallest: (X, Y, Z) -> (X, Y, Z)
---- `sy` is the smallest: (X, Y, Z) -> (Y, Z, X) by AXES_YZX
---- `sz` is the smallest: (X, Y, Z) -> (Z, X, Y) by AXES_ZXY
---@param prop ss.PrecachedData.StaticProp
---@return ss.PaintableSurface.StaticPropBox
function PaintableSurface.GetStaticPropBox(prop)
    local sizeX = prop.BoundsMaxX - prop.BoundsMinX
    local sizeY = prop.BoundsMaxY - prop.BoundsMinY
    local sizeZ = prop.BoundsMaxZ - prop.BoundsMinZ
    local boxToWorld = Geometry.FromAngles(
        prop.Pitch, prop.Yaw, prop.Roll, prop.PositionX, prop.PositionY, prop.PositionZ)
    boxToWorld[4], boxToWorld[8], boxToWorld[12] = Geometry.TransformPoint(
        boxToWorld, prop.BoundsMinX, prop.BoundsMinY, prop.BoundsMinZ)
    if prop.UnwrapIndex == 2 then
        boxToWorld = Geometry.Multiply(boxToWorld, AXES_YZX)
        sizeX, sizeY, sizeZ = sizeY, sizeZ, sizeX
    elseif prop.UnwrapIndex == 3 then
        boxToWorld = Geometry.Multiply(boxToWorld, AXES_ZXY)
        sizeX, sizeY, sizeZ = sizeZ, sizeX, sizeY
    end

    local faces = {} ---@type ss.PaintableSurface.StaticPropFace[]
    for j, face in ipairs(BOX_FACES) do
        local nx, ny, nz = face.NormalX, face.NormalY, face.NormalZ
        local fx, fy, fz = face.ForwardX, face.ForwardY, face.ForwardZ
        local lx, ly, lz = Geometry.Cross(nx, ny, nz, fx, fy, fz)
        local faceToBox = {
            fx, lx, nx, face.OriginX * sizeX,
            fy, ly, ny, face.OriginY * sizeY,
            fz, lz, nz, face.OriginZ * sizeZ,
        }
        faces[j] = {
            BoxFace = face,
            ToWorld = Geometry.Multiply(boxToWorld, faceToBox),
            SizeX   = math.abs(Geometry.Dot(sizeX, sizeY, sizeZ, fx, fy, fz)),
            SizeY   = math.abs(Geometry.Dot(sizeX, sizeY, sizeZ, lx, ly, lz)),
        }
    end

    return { ToWorld = boxToWorld, SizeX = sizeX, SizeY = sizeY, SizeZ = sizeZ, Faces = faces }
end

---Creates the paintable surfaces of the faces of the bounding boxes of static props,
---after the surfaces PaintableSurface.Setup creates.
---@param staticPropInfo ss.PrecachedData.StaticProp[]?
function PaintableSurface.SetupStaticProps(staticPropInfo)
    local index = #state.Surfaces
    for _, prop in ipairs(staticPropInfo or {}) do
        local box = PaintableSurface.GetStaticPropBox(prop)
        local aabbMinX, aabbMinY, aabbMinZ, aabbMaxX, aabbMaxY, aabbMaxZ
            = Geometry.TransformAABB(box.ToWorld, 0, 0, 0, box.SizeX, box.SizeY, box.SizeZ)
        local worldToBox = Geometry.InvertRotationTranslation(box.ToWorld)
        for _, face in ipairs(box.Faces) do
            index = index + 1
            local faceToWorld = face.ToWorld
            local ps = newSurface(index,
                math.ceil(face.SizeX / PaintableGrid.CELL_SIZE),
                math.ceil(face.SizeY / PaintableGrid.CELL_SIZE),
                Geometry.InvertRotationTranslation(faceToWorld))
            ps.AABBMinX, ps.AABBMinY, ps.AABBMinZ = aabbMinX, aabbMinY, aabbMinZ
            ps.AABBMaxX, ps.AABBMaxY, ps.AABBMaxZ = aabbMaxX, aabbMaxY, aabbMaxZ
            ps.NormalX, ps.NormalY, ps.NormalZ = faceToWorld[3], faceToWorld[7], faceToWorld[11]
            ps.StaticPropUnwrapIndex = prop.UnwrapIndex
            ps.WorldToMBB = worldToBox
            ps.MBBSizeX, ps.MBBSizeY, ps.MBBSizeZ = box.SizeX, box.SizeY, box.SizeZ
            state.Surfaces[index] = ps
        end
    end
end

return PaintableSurface
