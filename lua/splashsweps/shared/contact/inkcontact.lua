
-- Finds the contacts of entities with painted ink, from the paintable grids of the surfaces around them.

---@class ss
local ss = SplashSWEPs
local Geometry         = ss.import "splashsweps/shared/geometry"
local PaintableGrid    = ss.import "splashsweps/shared/paint/paintablegrid"
local PaintableSurface = ss.import "splashsweps/shared/paint/paintablesurface"
local SpatialIndex     = ss.import "splashsweps/shared/spatialindex"

---@class ss.InkContactModule
local InkContact = ss.module "splashsweps/shared/contact/inkcontact"

---A painted surface an entity is in contact with.
---The point is where the perpendicular from the center of the searched box meets the surface.
---@class ss.InkContact
---@field InkType  ss.InkType The ink type painted at the point.
---@field Position Vector     The point in world coordinates.
---@field Normal   Vector     The normal of the surface at the point in world coordinates.

---Hammer units added around the searched box, so that the surfaces an entity stands on or leans against are found.
local MARGIN = 1

---Returns if an entity is a target of the checks of contacts with ink.
---The world never is. For the others, the hook `SplashSWEPs: ShouldCheckInkContact` returns true or false to decide,
---or nil to leave it to the default, which makes an entity a target if it is solid.
---The hook must return the same on the server and on the client predicting a player.
---@param ent Entity
---@return boolean
function InkContact.ShouldCheck(ent)
    if ent:IsWorld() then return false end
    local result = hook.Run("SplashSWEPs: ShouldCheckInkContact", ent) ---@type boolean?
    if result ~= nil then return result end
    return ent:GetSolid() ~= SOLID_NONE and bit.band(ent:GetSolidFlags(), FSOLID_NOT_SOLID) == 0
end

---Returns the contact with a flat surface, if the center is in front of it and the foot of the perpendicular is painted.
---@param surf    ss.PaintableSurface A flat surface in the coordinate system of the center.
---@param toWorld number[]? The transform from that coordinate system to the world, or nil if it is the world.
---@param cx      number The center of the searched box.
---@param cy      number
---@param cz      number
---@return ss.InkContact?
local function findFlatContact(surf, toWorld, cx, cy, cz)
    -- The local Z of the paintable grid is the distance from the surface.
    local _, _, distance = Geometry.TransformPoint(surf.ToGrid, cx, cy, cz)
    if distance < 0 then return end

    local nx, ny, nz = surf.NormalX, surf.NormalY, surf.NormalZ
    local x, y, z = cx - nx * distance, cy - ny * distance, cz - nz * distance
    local inktype = PaintableGrid.Read(surf, x, y, z)
    if not inktype then return end
    if not toWorld then
        return { InkType = inktype, Position = Vector(x, y, z), Normal = Vector(nx, ny, nz) }
    end

    local position = Vector(Geometry.TransformPoint(toWorld, x, y, z))
    local normal = Vector(Geometry.TransformPoint(toWorld, x + nx, y + ny, z + nz)) - position
    return { InkType = inktype, Position = position, Normal = normal }
end

---Returns the contact with the nearest triangle of a displacement the center is in front of,
---if the foot of the perpendicular is painted.
---@param surf ss.PaintableSurface The displacement.
---@param minX number The searched box.
---@param minY number
---@param minZ number
---@param maxX number
---@param maxY number
---@param maxZ number
---@param cx   number The center of the box.
---@param cy   number
---@param cz   number
---@return ss.InkContact?
local function findDisplacementContact(surf, minX, minY, minZ, maxX, maxY, maxZ, cx, cy, cz)
    local xs, ys, zs = surf.PositionX, surf.PositionY, surf.PositionZ
    ---@cast xs -?
    ---@cast ys -?
    ---@cast zs -?
    local nearest = nil ---@type ss.PaintableSurface.DisplacementTriangle?
    local nearestDistance, b1, b2, b3 = 0, 0, 0, 0
    for _, t in ipairs(SpatialIndex.CollectDisplacementTriangles(surf, minX, minY, minZ, maxX, maxY, maxZ)) do
        local u1, u2, u3 = PaintableSurface.BarycentricCoordinates(t, cx, cy, cz)
        if u1 >= 0 and u2 >= 0 and u3 >= 0 then
            local i = t.VertexIndex1
            local distance = Geometry.Dot(cx - xs[i], cy - ys[i], cz - zs[i], t.NormalX, t.NormalY, t.NormalZ)
            if distance >= 0 and (not nearest or distance < nearestDistance) then
                nearest, nearestDistance, b1, b2, b3 = t, distance, u1, u2, u3
            end
        end
    end
    if not nearest then return end

    local inktype = PaintableGrid.Read(surf, PaintableSurface.MapToFlatSurface(surf, nearest, b1, b2, b3))
    if not inktype then return end

    local normal = Vector(nearest.NormalX, nearest.NormalY, nearest.NormalZ)
    return { InkType = inktype, Position = Vector(cx, cy, cz) - normal * nearestDistance, Normal = normal }
end

---Returns the contacts of an entity with ink, grouped by the modules named by `$features` of their ink types.
---The contacts are those with the surfaces near the box, collected as painting does,
---each read at the foot of the perpendicular from the center of the box.
---@param ent  Entity  The entity, whose own surfaces are excluded if it is a brush entity.
---@param mins Vector  The box in world coordinates, usually the AABB of the entity.
---@param maxs Vector
---@param step Vector? The movement of the entity, which extends the box to include the surfaces it reaches.
---@return table<ss.IInkFeature, ss.InkContact[]> # Module --> the contacts with the ink types naming it.
function InkContact.Find(ent, mins, maxs, step)
    local minX, minY, minZ = mins:Unpack()
    local maxX, maxY, maxZ = maxs:Unpack()
    if step then
        local dx, dy, dz = step:Unpack()
        minX, minY, minZ = math.min(minX, minX + dx), math.min(minY, minY + dy), math.min(minZ, minZ + dz)
        maxX, maxY, maxZ = math.max(maxX, maxX + dx), math.max(maxY, maxY + dy), math.max(maxZ, maxZ + dz)
    end

    minX, minY, minZ = minX - MARGIN, minY - MARGIN, minZ - MARGIN
    maxX, maxY, maxZ = maxX + MARGIN, maxY + MARGIN, maxZ + MARGIN
    local cx, cy, cz = (minX + maxX) * 0.5, (minY + maxY) * 0.5, (minZ + maxZ) * 0.5
    local contacts = {} ---@type ss.InkContact[]
    for _, surf in ipairs(SpatialIndex.CollectSurfaces(minX, minY, minZ, maxX, maxY, maxZ)) do
        if surf.Triangles then
            contacts[#contacts + 1] = findDisplacementContact(surf, minX, minY, minZ, maxX, maxY, maxZ, cx, cy, cz)
        else
            contacts[#contacts + 1] = findFlatContact(surf, nil, cx, cy, cz)
        end
    end

    -- Brush models have no displacements, so their surfaces are always flat.
    local entities, modelIndices, worldToModels = SpatialIndex.CollectBrushEntities(minX, minY, minZ, maxX, maxY, maxZ)
    for k = 1, #entities do
        if entities[k] ~= ent then
            local worldToModel = worldToModels[k]
            local modelToWorld = Geometry.InvertRotationTranslation(worldToModel)
            local lx, ly, lz = Geometry.TransformPoint(worldToModel, cx, cy, cz)
            for _, surf in ipairs(SpatialIndex.CollectBrushModelSurfaces(modelIndices[k],
                Geometry.TransformAABB(worldToModel, minX, minY, minZ, maxX, maxY, maxZ))) do
                contacts[#contacts + 1] = findFlatContact(surf, modelToWorld, lx, ly, lz)
            end
        end
    end

    local groups = {} ---@type table<ss.IInkFeature, ss.InkContact[]>
    for _, contact in ipairs(contacts) do
        for _, feature in ipairs(contact.InkType.Features) do
            groups[feature] = groups[feature] or {}
            table.insert(groups[feature], contact)
        end
    end

    return groups
end

return InkContact
