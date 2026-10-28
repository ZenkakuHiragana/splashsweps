
-- Painting ink onto surfaces and networking it.

---@class ss
local ss = SplashSWEPs
local Geometry         = ss.import "splashsweps/shared/geometry"
local Hash             = ss.import "splashsweps/shared/hash"
local InkShape         = ss.import "splashsweps/shared/inkshape"
local InkType          = ss.import "splashsweps/shared/inktype"
local PaintableGrid    = ss.import "splashsweps/shared/paint/paintablegrid"
local PaintableSurface = ss.import "splashsweps/shared/paint/paintablesurface"
local InkMap           = CLIENT and ss.import "splashsweps/client/render/inkmap" or nil

---@class ss.PaintModule
local Paint = ss.module "splashsweps/shared/paint/paint"

---A paint: an ink shape of an ink type put at a pose.
---The ink shape lies on the plane of the forward and the left, facing the up.
---@class ss.Paint
---@field X       number  The origin.
---@field Y       number
---@field Z       number
---@field Pitch   number  The angles of the forward, the left, and the up.
---@field Yaw     number
---@field Roll    number
---@field RadiusX number  Distance from the origin to the edge of the shape along the forward.
---@field RadiusY number  Distance from the origin to the edge of the shape along the left.
---@field RadiusZ number  Distance from the origin to search for surfaces along the up.
---                       The search reaches at least half of the smaller of RadiusX and RadiusY.
---@field Shape   integer The internal index of the ink shape.
---@field InkType integer The internal index of the ink type.

local wrap = coroutine.wrap
local yield = coroutine.yield
local huge = math.huge
local max = math.max
local min = math.min
local Round = math.Round
local Remap = math.Remap
local NormalizeAngle = math.NormalizeAngle
local GetPredictionPlayer = GetPredictionPlayer
local net_Start = net.Start
local net_WriteUInt = net.WriteUInt
local net_WriteInt = net.WriteInt
---@diagnostic disable-next-line undefined-field
local net_SendOmit = net.SendOmit

---Maximum paint scale of a single drop to be networked
local MAX_RADIUS = math.pow(2, ss.MAX_INK_RADIUS_BITS + 1) - 1

---Maximum angle difference allowed to paint.
local MAX_COS = math.cos(math.rad(45))
local MAX_COS_PROP = math.cos(math.rad(60))

---Gets the AABB of a paint.
---@param paint ss.Paint
---@return number minX, number minY, number minZ, number maxX, number maxY, number maxZ
function Paint.GetBoundingBox(paint)
    local radiusX, radiusY = paint.RadiusX, paint.RadiusY
    local radiusZ = max(paint.RadiusZ, min(radiusX, radiusY) * 0.5)
    return Geometry.TransformAABB(
        Geometry.FromAngles(paint.Pitch, paint.Yaw, paint.Roll, paint.X, paint.Y, paint.Z),
        -radiusX, -radiusY, -radiusZ, radiusX, radiusY, radiusZ)
end

---Returns the paint mapped from a triangle of a displacement onto the flat surface the displacement came from.
---@param surf       ss.PaintableSurface The displacement.
---@param triangle   ss.DisplacementTriangle
---@param paint      ss.Paint The paint on the triangle.
---@param inkToWorld number[] The rotation of the paint.
---@param b1         number   Barycentric coordinates of the paint in the triangle.
---@param b2         number
---@param b3         number
---@return ss.Paint
local function MapOntoFlatSurface(surf, triangle, paint, inkToWorld, b1, b2, b3)
    local i1, i2, i3 = triangle.VertexIndex1, triangle.VertexIndex2, triangle.VertexIndex3
    local xs, ys, zs = surf.PaintOriginX, surf.PaintOriginY, surf.PaintOriginZ
    ---@cast xs -?
    ---@cast ys -?
    ---@cast zs -?
    local pitch, yaw, roll = Geometry.ToAngles(Geometry.Multiply(triangle.WorldToLocalGridRotation, inkToWorld))
    return {
        X = xs[i1] * b1 + xs[i2] * b2 + xs[i3] * b3,
        Y = ys[i1] * b1 + ys[i2] * b2 + ys[i3] * b3,
        Z = zs[i1] * b1 + zs[i2] * b2 + zs[i3] * b3,
        Pitch = pitch,
        Yaw = yaw,
        Roll = roll,
        RadiusX = paint.RadiusX,
        RadiusY = paint.RadiusY,
        RadiusZ = paint.RadiusZ,
        Shape = paint.Shape,
        InkType = paint.InkType,
    }
end

---Before processing paintings, if the target surface is a displacement,
---we have to map the paint to the flat surface where it came from.
---
---So this function enumerates the paints mapped onto the flat surface to handle deformed surfaces correctly.
---@param surf ss.PaintableSurface The surface to search.
---@param paint ss.Paint The paint in the same coordinate system as the surface.
---@param minX number AABB to enumerate triangles of displacement.
---@param minY number
---@param minZ number
---@param maxX number
---@param maxY number
---@param maxZ number
---@return fun(): ss.Paint # The paints ready to be written into the paint grid of the surface.
function Paint.EnumeratePositions(surf, paint, minX, minY, minZ, maxX, maxY, maxZ)
    return wrap(function()
        local inkToWorld = Geometry.FromAngles(paint.Pitch, paint.Yaw, paint.Roll, 0, 0, 0)
        local upX, upY, upZ = inkToWorld[3], inkToWorld[7], inkToWorld[11]
        if surf.Triangles then
            -- The score is the sum of the negative barycentric coordinates, which is closer to 0 when the paint is nearer.
            local nearestScore = -huge
            local nearestTriangle = nil ---@type ss.DisplacementTriangle?
            local nearestB1, nearestB2, nearestB3 = 0, 0, 0
            for t in Hash.CollectDisplacementTriangles(surf, minX, minY, minZ, maxX, maxY, maxZ) do
                local b1, b2, b3 = PaintableSurface.BarycentricCoordinates(t, paint.X, paint.Y, paint.Z)
                if b1 > 0 and b2 > 0 and b3 > 0 then
                    if Geometry.Dot(upX, upY, upZ, t.NormalX, t.NormalY, t.NormalZ) > MAX_COS then
                        yield(MapOntoFlatSurface(surf, t, paint, inkToWorld, b1, b2, b3))
                        nearestScore = huge
                        nearestTriangle = nil
                    end
                else
                    local score = min(b1, 0) + min(b2, 0) + min(b3, 0)
                    if score > nearestScore then
                        nearestScore = score
                        nearestTriangle = t
                        nearestB1, nearestB2, nearestB3 = b1, b2, b3
                    end
                end
            end

            -- If the paint position is outside, find the nearest triangle roughly and return it.
            local t = nearestTriangle
            if t and Geometry.Dot(upX, upY, upZ, t.NormalX, t.NormalY, t.NormalZ) > MAX_COS then
                yield(MapOntoFlatSurface(surf, t, paint, inkToWorld, nearestB1, nearestB2, nearestB3))
            end
        elseif Geometry.Dot(upX, upY, upZ, surf.NormalX, surf.NormalY, surf.NormalZ)
            > (surf.StaticPropUnwrapIndex and MAX_COS_PROP or MAX_COS) then
            yield(paint)
        end
    end)
end

---Rounds a pose to the integers of network messages.
---@param x     number
---@param y     number
---@param z     number
---@param pitch number
---@param yaw   number
---@param roll  number
---@return integer x, integer y, integer z, integer pitch, integer yaw, integer roll
local function EncodePose(x, y, z, pitch, yaw, roll)
    return Round(x * 0.5), Round(y * 0.5), Round(z * 0.5), -- -16384 to 16384, 2 step
        Round(Remap(NormalizeAngle(pitch), -180, 180, -128, 127)),
        Round(Remap(NormalizeAngle(yaw),   -180, 180, -128, 127)),
        Round(Remap(NormalizeAngle(roll),  -180, 180, -128, 127))
end

---Creates a paint from the integers of network messages,
---which the sender of the messages also paints with to get the same result as the receivers.
---@param inktype integer
---@param shape   integer
---@param x       integer
---@param y       integer
---@param z       integer
---@param pitch   integer
---@param yaw     integer
---@param roll    integer
---@param radiusX integer
---@param radiusY integer
---@param radiusZ integer
---@return ss.Paint
local function Decode(inktype, shape, x, y, z, pitch, yaw, roll, radiusX, radiusY, radiusZ)
    return {
        X = x * 2,
        Y = y * 2,
        Z = z * 2,
        Pitch = Remap(pitch, -128, 127, -180, 180),
        Yaw   = Remap(yaw,   -128, 127, -180, 180),
        Roll  = Remap(roll,  -128, 127, -180, 180),
        RadiusX = radiusX * 2,
        RadiusY = radiusY * 2,
        RadiusZ = radiusZ * 2,
        Shape = shape,
        InkType = inktype,
    }
end

---Writes the common part of paint messages and sends it to the players except the predicting one.
---The arguments are the integers Decode takes.
local function WritePaintAndSend(inktype, shape, x, y, z, pitch, yaw, roll, radiusX, radiusY, radiusZ)
    net_WriteUInt(inktype - 1, InkType.GetNumBits()) -- Ink type
    net_WriteUInt(shape - 1, InkShape.GetNumBits()) -- Ink shape
    net_WriteInt(pitch, 8) -- Pitch
    net_WriteInt(yaw,   8) -- Yaw
    net_WriteInt(roll,  8) -- Roll
    net_WriteInt(x, 15) -- X
    net_WriteInt(y, 15) -- Y
    net_WriteInt(z, 15) -- Z
    net_WriteUInt(radiusX, ss.MAX_INK_RADIUS_BITS) -- Radius X
    net_WriteUInt(radiusY, ss.MAX_INK_RADIUS_BITS) -- Radius Y
    net_WriteUInt(radiusZ, ss.MAX_INK_RADIUS_BITS) -- Radius Z
    net_SendOmit(ss.sp and NULL or GetPredictionPlayer())
end

---Paints the surfaces given by the generator.
---@param surfaces fun(): ss.PaintableSurface
---@param paint ss.Paint The paint in the same coordinate system as the surfaces.
---@param minX  number   AABB of the paint.
---@param minY  number
---@param minZ  number
---@param maxX  number
---@param maxY  number
---@param maxZ  number
local function PaintSurfaces(surfaces, paint, minX, minY, minZ, maxX, maxY, maxZ)
    for surf in surfaces do
        for p in Paint.EnumeratePositions(surf, paint, minX, minY, minZ, maxX, maxY, maxZ) do
            PaintableGrid.Write(surf, p)
            if InkMap then
                InkMap.Push(surf, p)
            end
        end
    end
end

---Paints the worldspawn and static props without networking.
---The paint must be already quantized by Paint.Paint.
---@param paint ss.Paint
function Paint.PaintWorld(paint)
    local minX, minY, minZ, maxX, maxY, maxZ = Paint.GetBoundingBox(paint)
    PaintSurfaces(Hash.CollectSurfaces(minX, minY, minZ, maxX, maxY, maxZ),
        paint, minX, minY, minZ, maxX, maxY, maxZ)
end

---Paints a brush model without networking.
---The paint must be already quantized by Paint.Paint.
---@param modelIndex integer  The index of the brush model.
---@param paint      ss.Paint The paint in the model's local coordinates.
function Paint.PaintBrushModel(modelIndex, paint)
    local minX, minY, minZ, maxX, maxY, maxZ = Paint.GetBoundingBox(paint)
    PaintSurfaces(Hash.CollectBrushModelSurfaces(modelIndex, minX, minY, minZ, maxX, maxY, maxZ),
        paint, minX, minY, minZ, maxX, maxY, maxZ)
end

---Paints an ink with given information.
---@param pos     Vector  The origin.
---@param ang     Angle   The normal and rotation.
---@param radius  Vector  The radii of the paint, which are limited to 510 Hammer units because of network optimization.
---@param shape   integer The internal index of shape to paint.
---@param inktype integer The internal index of ink type.
function Paint.Paint(pos, ang, radius, shape, inktype)
    -- Parameter limit to reduce network traffic
    local radiusX = Round(min(radius.x, MAX_RADIUS) * 0.5) -- 0 to MAX_RADIUS, 2 step, integer
    local radiusY = Round(min(radius.y, MAX_RADIUS) * 0.5) -- 0 to MAX_RADIUS, 2 step, integer
    local radiusZ = Round(min(radius.z, MAX_RADIUS) * 0.5) -- 0 to MAX_RADIUS, 2 step, integer
    local x, y, z, pitch, yaw, roll = EncodePose(pos.x, pos.y, pos.z, ang.pitch, ang.yaw, ang.roll)
    local paint = Decode(inktype, shape, x, y, z, pitch, yaw, roll, radiusX, radiusY, radiusZ)
    Paint.PaintWorld(paint)
    if SERVER then
        net_Start "SplashSWEPs: Paint"
        WritePaintAndSend(inktype, shape, x, y, z, pitch, yaw, roll, radiusX, radiusY, radiusZ)
    end

    -- Brush entities can move, so the ink is localized to their models and networked separately.
    -- The receiving clients do not search for the entities; only the predicting client does.
    local inkToWorld = Geometry.FromAngles(paint.Pitch, paint.Yaw, paint.Roll, paint.X, paint.Y, paint.Z)
    for _, modelIndex, worldToModel in Hash.CollectBrushEntities(Paint.GetBoundingBox(paint)) do
        local inkToModel = Geometry.Multiply(worldToModel, inkToWorld)
        local localPitch, localYaw, localRoll = Geometry.ToAngles(inkToModel)
        local lx, ly, lz, lpitch, lyaw, lroll = EncodePose(
            inkToModel[4], inkToModel[8], inkToModel[12], localPitch, localYaw, localRoll)
        if SERVER then
            net_Start "SplashSWEPs: Paint brush model"
            net_WriteUInt(modelIndex - 1, PaintableSurface.GetModelIndexBits()) -- Model index
            WritePaintAndSend(inktype, shape, lx, ly, lz, lpitch, lyaw, lroll, radiusX, radiusY, radiusZ)
        end

        Paint.PaintBrushModel(modelIndex,
            Decode(inktype, shape, lx, ly, lz, lpitch, lyaw, lroll, radiusX, radiusY, radiusZ))
    end
end

if SERVER then
    ---Clears all painted ink in the map, and tells the clients to clear theirs.
    function Paint.ClearAll()
        for _, s in ipairs(PaintableSurface.Surfaces) do PaintableGrid.Clear(s) end
        net.Start "SplashSWEPs: Clear all ink"
        ---@diagnostic disable-next-line undefined-field
        net.Broadcast()
    end
else
    local net_ReadInt = net.ReadInt
    local net_ReadUInt = net.ReadUInt

    ---Reads the common part of paint messages written by WritePaintAndSend.
    ---@return ss.Paint
    function Paint.Read()
        local inktype = net_ReadUInt(InkType.GetNumBits()) + 1 -- Ink type
        local shape   = net_ReadUInt(InkShape.GetNumBits()) + 1 -- Ink shape
        local pitch   = net_ReadInt(8) -- Pitch
        local yaw     = net_ReadInt(8) -- Yaw
        local roll    = net_ReadInt(8) -- Roll
        local x       = net_ReadInt(15) -- X
        local y       = net_ReadInt(15) -- Y
        local z       = net_ReadInt(15) -- Z
        local radiusX = net_ReadUInt(ss.MAX_INK_RADIUS_BITS) -- Radius X
        local radiusY = net_ReadUInt(ss.MAX_INK_RADIUS_BITS) -- Radius Y
        local radiusZ = net_ReadUInt(ss.MAX_INK_RADIUS_BITS) -- Radius Z
        return Decode(inktype, shape, x, y, z, pitch, yaw, roll, radiusX, radiusY, radiusZ)
    end

    ---Reads the model index of brush model paint messages, written before the common part.
    ---@return integer modelIndex
    function Paint.ReadModelIndex()
        return net_ReadUInt(PaintableSurface.GetModelIndexBits()) + 1 -- Model index
    end
end

return Paint
