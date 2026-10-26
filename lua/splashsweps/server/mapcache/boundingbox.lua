
-- Bounding rectangles and boxes of vertices.

---@class ss
local ss = SplashSWEPs
local Util = ss.import "splashsweps/shared/util"

---@class ss.BoundingBox
local BoundingBox = ss.module "splashsweps/server/mapcache/boundingbox"

local abs = math.abs
local max = math.max
local sqrt = math.sqrt
local sort = table.sort
local tableCopy = table.Copy
local Vector = Vector
local Matrix = Matrix

---Relative difference of areas regarded as the same in BoundingBox.FindMBR.
local AREA_TOLERANCE = 1e-5

---Compares two vertices used by table.sort
---@param a Vector
---@param b Vector
---@return boolean
local function VerticesComparer(a, b)
    return Either(a.x == b.x, a.y < b.y, a.x < b.x)
end

-- Generates a convex hull by monotone chain method
---@param source Vector[]
---@return Vector[]
local function GetConvex(source)
    local convex = {} ---@type Vector[]
    local vertices2D = tableCopy(source)
    sort(vertices2D, VerticesComparer)
    for i = 1, #vertices2D do
        if i > 2 then
            local p = convex[#convex]
            local q = convex[#convex - 1]
            local pq = q - p
            local pr = vertices2D[i] - p
            local cross = pq:Cross(pr)
            if cross.z > 0 or pq:LengthSqr() < Util.eps or pr:LengthSqr() < Util.eps then
                convex[#convex] = nil
            end
        end

        if i ~= #vertices2D then
            convex[#convex + 1] = vertices2D[i]
        end
    end

    for i = #vertices2D, 1, -1 do
        if i < #vertices2D - 1 then
            local p = convex[#convex]
            local q = convex[#convex - 1]
            local pq = q - p
            local pr = vertices2D[i] - p
            local cross = pq:Cross(pr)
            if cross.z > 0 or pq:LengthSqr() < Util.eps or pr:LengthSqr() < Util.eps then
                convex[#convex] = nil
            end
        end

        if i ~= 1 then
            convex[#convex + 1] = vertices2D[i]
        end
    end

    return convex
end

---Calculates minimum bounding rectangle (MBR) of given vertices.
---@param vertices Vector[] Vertices respresenting the face in the world coordinate system.
---@param angle    Angle    The angle of the face in the world coordinate system. Up() should be the normal.
---@return VMatrix origin Represents the origin and angle of the MBR in the world coordinate system.
---@return Vector  size   The size of the MBR in Hammer units.
function BoundingBox.FindMBR(vertices, angle)
    local center = Vector()
    for _, v in ipairs(vertices) do center:Add(v) end
    center:Div(#vertices)

    -- Transforms vertices in the world to 2D space.
    -- ```
    --   ________
    --  /        \
    -- |   +--> x |
    -- |   v      |
    -- |   y      |
    -- +----------+
    -- ```
    local vertices2D = {} ---@type Vector[]
    for i, v in ipairs(vertices) do
        vertices2D[i] = WorldToLocal(v, angle_zero, center, angle)
    end

    -- For each edge of the convex hull, finds the rectangle along the edge containing the hull.
    -- The rotation of an edge is the matrix of which columns are
    -- forward = (dx, dy, dz), the negated right = (-dy, dx, 0), and up = (0, 0, 1),
    -- so its inverse maps (x, y, z) to (dx * x + dy * y + dz * z, dx * y - dy * x, z).
    -- They are computed in plain numbers as this runs for every pair of an edge and a vertex.
    -- Edges giving the same area within rounding errors, such as the four edges of a rectangle,
    -- keep the first one so that the result does not depend on the rounding.
    local convex = GetConvex(vertices2D)
    local numConvex = #convex
    local xs, ys, zs = {}, {}, {} ---@type number[], number[], number[]
    for i, v in ipairs(convex) do
        xs[i], ys[i], zs[i] = v.x, v.y, v.z
    end

    local minArea = math.huge
    local mbrDir = nil ---@type Vector?
    local mbrMins = Util.vector_one * math.huge
    local mbrSize = Vector()
    for i = 1, numConvex do
        local j = i % numConvex + 1
        local dx, dy, dz = xs[j] - xs[i], ys[j] - ys[i], zs[j] - zs[i]
        local lengthSqr = dx * dx + dy * dy + dz * dz
        if lengthSqr > 0 then
            local length = sqrt(lengthSqr)
            dx, dy, dz = dx / length, dy / length, dz / length
            local minX, minY, minZ = math.huge, math.huge, math.huge
            local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
            for k = 1, numConvex do
                local x, y, z = xs[k], ys[k], zs[k]
                local u = dx * x + dy * y + dz * z
                local v = dx * y - dy * x
                if u < minX then minX = u end
                if u > maxX then maxX = u end
                if v < minY then minY = v end
                if v > maxY then maxY = v end
                if z < minZ then minZ = z end
                if z > maxZ then maxZ = z end
            end

            local area = (maxX - minX) * (maxY - minY)
            if area < minArea * (1 - AREA_TOLERANCE) then
                minArea = area
                mbrDir = Vector(dx, dy, dz)
                mbrMins = Vector(minX, minY, minZ)
                mbrSize = Vector(maxX - minX, maxY - minY, maxZ - minZ)
            end
        end
    end

    local mbrRotation = Matrix()
    if mbrDir then
        mbrRotation:SetForward(mbrDir)
        mbrRotation:SetRight(Vector(mbrDir.y, -mbrDir.x))
        mbrRotation:SetUp(vector_up)
    end

    mbrRotation:SetTranslation(mbrRotation * mbrMins)

    local localToWorld = Matrix()
    localToWorld:SetAngles(angle)
    localToWorld:SetTranslation(center)
    localToWorld:Mul(mbrRotation)
    return localToWorld, mbrSize
end

---Finds the oriented minimum boundibg box from displacement positions.
---@param vertices ss.PrecachedData.Vertex[]
---@return VMatrix origin Represents the origin and angle of the minimum OBB in the world coordinate system.
---@return Vector  size   The size of the MBR in Hammer units.
function BoundingBox.FindMinimumOBB(vertices)
    local mean = Vector()
    for _, v in ipairs(vertices) do mean:Add(v.Translation) end
    mean:Div(#vertices)

    -- Calculates a variance-covariance matrix
    --     [ sxx sxy szx ]
    -- S = [ sxy syy syz ]
    --     [ szx syz szz ]
    local variance   = Vector() -- = ( sxx syy szz )
    local covariance = Vector() -- = ( sxy syz szx )
    for _, v in ipairs(vertices) do
        local diff = v.Translation - mean
        variance:Add(diff * diff)
        covariance:Add(Vector(
            diff.x * diff.y,
            diff.y * diff.z,
            diff.z * diff.x))
    end

    -- Here I don't divide variance by #vertices as I just need eigenvectors.

    -- The angle components will be eigenvectors by Jacobi's algorithm.
    local rotation = Matrix()
    local localToWorld = Matrix()
    for _ = 1, 20 do
        local covarianceSqr = covariance * covariance
        local maxCovarianceSqr = max(covarianceSqr:Unpack())
        if maxCovarianceSqr < Util.eps then break end
        if maxCovarianceSqr == covarianceSqr.x then
            --             [ c  -s  0 ][ xx xy xz ][  c  s  0 ]
            -- S' = RᵀSR = [ s   c  0 ][ xy yy yz ][ -s  c  0 ]
            --             [ 0   0  1 ][ xz yz zz ][  0  0  1 ]
            --             [ cxx - sxy   cxy - syy   cxz - syz ][ c -s  0 ]
            --           = [ sxx + cxy   sxy + cyy   sxz + cyz ][ s  c  0 ]
            --             [        xz          yz          zz ][ 0  0  1 ]
            --             [ ccxx - 2csxy + ssyy                     0   cxz - syz ]
            --           = [                   0   ssxx + 2csxy + ccyy   sxz + cyz ]
            --             [          cxz -  syz            sxz +  cyz          zz ]
            local tau = (variance.y - variance.x) / (2 * covariance.x)
            local tan = (tau < 0 and -1 or 1) / (abs(tau) + sqrt(1 + tau * tau))
            local cos = 1 / sqrt(1 + tan * tan)
            local sin = cos * tan
            local cos2, sin2 = cos * cos, sin * sin
            local sincos2 = 2 * sin * cos * covariance.x
            variance:SetUnpacked(
                cos2 * variance.x + sin2 * variance.y - sincos2,
                sin2 * variance.x + cos2 * variance.y + sincos2,
                variance.z)
            covariance:SetUnpacked(
                0,
                cos * covariance.y + sin * covariance.z,
                cos * covariance.z - sin * covariance.y)
            rotation:SetUnpacked(
                cos, sin, 0, 0,
               -sin, cos, 0, 0,
                0,     0, 1, 0,
                0,     0, 0, 1)
        elseif maxCovarianceSqr == covarianceSqr.y then
            --             [ 1  0  0 ][ xx xy xz ][ 1  0  0 ]
            -- S' = RᵀSR = [ 0  c -s ][ xy yy yz ][ 0  c  s ]
            --             [ 0  s  c ][ xz yz zz ][ 0 -s  c ]
            --             [        xx          xy          xz ][ 1  0  0 ]
            --           = [ cxy - sxz   cyy - syz   cyz - szz ][ 0  c  s ]
            --             [ sxy + cxz   syy + cyz   syz + czz ][ 0 -s  c ]
            --             [        xx            cxy -  sxz            szy +  cxz ]
            --           = [ cxy - sxz   ccyy - 2csyz + sszz                     0 ]
            --             [ sxy + cxz                     0   ssyy + 2csyz + cczz ]
            local tau = (variance.z - variance.y) / (2 * covariance.y)
            local tan = (tau < 0 and -1 or 1) / (abs(tau) + sqrt(1 + tau * tau))
            local cos = 1 / sqrt(1 + tan * tan)
            local sin = cos * tan
            local cos2, sin2 = cos * cos, sin * sin
            local sincos2 = 2 * sin * cos * covariance.y
            variance:SetUnpacked(
                variance.x,
                cos2 * variance.y + sin2 * variance.z - sincos2,
                sin2 * variance.y + cos2 * variance.z + sincos2)
            covariance:SetUnpacked(
                cos * covariance.x - sin * covariance.z,
                0,
                cos * covariance.z + sin * covariance.x)
            rotation:SetUnpacked(
                1,    0,   0, 0,
                0,  cos, sin, 0,
                0, -sin, cos, 0,
                0,    0,   0, 1)
        else
            --             [ c  0 -s ][ xx xy xz ][  c  0  s ]
            -- S' = RᵀSR = [ 0  1  0 ][ xy yy yz ][  0  1  0 ]
            --             [ s  0  c ][ xz yz zz ][ -s  0  c ]
            --             [ cxx - sxz   cxy - syz   cxz - szz ][ c  0 -s ]
            --           = [        xy          yy          yz ][ 0  1  0 ]
            --             [ sxx + cxz   sxy + cyz   sxz + czz ][ s  0  c ]
            --             [ ccxx - 2csxz + sszz   cxy - syz                     0 ]
            --           = [          cxy -  syz          yy            sxy +  cyz ]
            --             [                   0   sxy + cyz   ssxx + 2csxz + cczz ]
            local tau = (variance.z - variance.x) / (2 * covariance.z)
            local tan = (tau < 0 and -1 or 1) / (abs(tau) + sqrt(1 + tau * tau))
            local cos = 1 / sqrt(1 + tan * tan)
            local sin = cos * tan
            local cos2, sin2 = cos * cos, sin * sin
            local sincos2 = 2 * sin * cos * covariance.z
            variance:SetUnpacked(
                cos2 * variance.x + sin2 * variance.z - sincos2,
                variance.y,
                sin2 * variance.x + cos2 * variance.z + sincos2)
            covariance:SetUnpacked(
                cos * covariance.x - sin * covariance.y,
                cos * covariance.y + sin * covariance.x,
                0)
            rotation:SetUnpacked(
                cos, 0, sin, 0,
                0,   1,   0, 0,
               -sin, 0, cos, 0,
                0,   0,   0, 1)
        end

        localToWorld:Mul(rotation)
    end

    -- ---Compares two vectors used by table.sort
    -- ---@param a Vector
    -- ---@param b Vector
    -- ---@return boolean
    -- local function LengthDescending(a, b)
    --     return a:LengthSqr() > b:LengthSqr()
    -- end
    --
    -- Sorting axes (seems broken)
    -- local axes = {
    --     localToWorld:GetForward() * variance.x,
    --     localToWorld:GetRight() * variance.y,
    --     localToWorld:GetUp() * variance.z,
    -- }
    -- sort(axes, LengthDescending)
    -- localToWorld:SetForward(axes[1]:GetNormalized())
    -- localToWorld:SetRight(axes[2]:GetNormalized())
    -- localToWorld:SetUp(axes[3]:GetNormalized())
    localToWorld:SetTranslation(mean)

    local worldToLocal = localToWorld:GetInverseTR()
    local mins = Util.vector_one * math.huge
    local maxs = Util.vector_one * -math.huge
    for _, v in ipairs(vertices) do
        local pos = worldToLocal * v.Translation
        mins:Set(Util.MinVector(mins, pos))
        maxs:Set(Util.MaxVector(maxs, pos))
    end

    localToWorld:Translate(mins)
    return localToWorld, maxs - mins
end

return BoundingBox
