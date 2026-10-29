
-- Bounding rectangles and boxes of points, computed in plain numbers.
-- The points are given as the arrays of their x, y, and z,
-- and the results are transforms of ss.GeometryModule, of which the translation is the corner of the minimum.

---@class ss
local ss = SplashSWEPs
local Geometry = ss.import "splashsweps/shared/geometry"
local Util     = ss.import "splashsweps/shared/util"

---@class ss.BoundingBox
local BoundingBox = ss.module "splashsweps/shared/mapcache/boundingbox"

local abs = math.abs
local huge = math.huge
local max = math.max
local min = math.min
local sort = table.sort
local sqrt = math.sqrt

---Relative difference of areas regarded as the same in BoundingBox.FindMBR.
local AREA_TOLERANCE = 1e-5

---Generates a convex hull of points in 2D by the monotone chain method.
---The points have z, which is ignored except for the distance between points.
---@param xs number[]
---@param ys number[]
---@param zs number[]
---@return integer[] # Indices of the points on the hull.
local function GetConvex(xs, ys, zs)
    local sorted = {} ---@type integer[]
    for i = 1, #xs do sorted[i] = i end
    sort(sorted, function(a, b)
        if xs[a] == xs[b] then return ys[a] < ys[b] end
        return xs[a] < xs[b]
    end)

    ---Tests whether the last point of the hull should be removed to add point r.
    ---@param convex integer[]
    ---@param r integer
    ---@return boolean
    local function isNotConvex(convex, r)
        local p, q = convex[#convex], convex[#convex - 1]
        local pqX, pqY, pqZ = xs[q] - xs[p], ys[q] - ys[p], zs[q] - zs[p]
        local prX, prY, prZ = xs[r] - xs[p], ys[r] - ys[p], zs[r] - zs[p]
        local _, _, turn = Geometry.Cross(pqX, pqY, pqZ, prX, prY, prZ)
        return turn > 0
            or Geometry.LengthSqr(pqX, pqY, pqZ) < Util.eps
            or Geometry.LengthSqr(prX, prY, prZ) < Util.eps
    end

    local convex = {} ---@type integer[]
    local n = #sorted
    for i = 1, n do
        if i > 2 and isNotConvex(convex, sorted[i]) then
            convex[#convex] = nil
        end

        if i ~= n then
            convex[#convex + 1] = sorted[i]
        end
    end

    for i = n, 1, -1 do
        if i < n - 1 and isNotConvex(convex, sorted[i]) then
            convex[#convex] = nil
        end

        if i ~= 1 then
            convex[#convex + 1] = sorted[i]
        end
    end

    return convex
end

---Calculates minimum bounding rectangle (MBR) of given points in a plane.
---@param xs          number[] Points in the world coordinate system.
---@param ys          number[]
---@param zs          number[]
---@param orientation number[] A transform of which the up column is the normal of the plane. The translation is not used.
---@return number[] localToWorld The origin and the orientation of the MBR in the world coordinate system.
---@return number   sizeX        The size of the MBR in Hammer units.
---@return number   sizeY
---@return number   sizeZ
function BoundingBox.FindMBR(xs, ys, zs, orientation)
    local n = #xs
    local centerX, centerY, centerZ = 0, 0, 0
    for i = 1, n do
        centerX, centerY, centerZ = centerX + xs[i], centerY + ys[i], centerZ + zs[i]
    end
    centerX, centerY, centerZ = centerX / n, centerY / n, centerZ / n

    -- Transforms the points in the world into the plane.
    -- ```
    --   ________
    --  /        \
    -- |   +--> x |
    -- |   v      |
    -- |   y      |
    -- +----------+
    -- ```
    local o = orientation
    local planeToWorld = {
        o[1], o[2],  o[3],  centerX,
        o[5], o[6],  o[7],  centerY,
        o[9], o[10], o[11], centerZ,
    }
    local worldToPlane = Geometry.InvertRotationTranslation(planeToWorld)
    local localXs, localYs, localZs = {}, {}, {} ---@type number[], number[], number[]
    for i = 1, n do
        localXs[i], localYs[i], localZs[i] = Geometry.TransformPoint(worldToPlane, xs[i], ys[i], zs[i])
    end

    -- For each edge of the convex hull, finds the rectangle along the edge containing the hull.
    -- The rectangle of an edge with the direction d = (dx, dy, 0) has the axes d, up = (0, 0, 1), and up × d,
    -- so the point p is at (d・p, (d × p).z, p.z) in the rectangle.
    -- The points can be off the plane by a little, so the edges are projected onto the plane
    -- to keep the axes perpendicular; otherwise the axes are not a rotation and break into angles.
    -- Edges giving the same area within rounding errors, such as the four edges of a rectangle,
    -- keep the first one so that the result does not depend on the rounding.
    local convex = GetConvex(localXs, localYs, localZs)
    local numConvex = #convex
    local minArea = huge
    local mbrDX, mbrDY = 1, 0
    local mbrMinX, mbrMinY, mbrMinZ = 0, 0, 0
    local sizeX, sizeY, sizeZ = 0, 0, 0
    for i = 1, numConvex do
        local a, b = convex[i], convex[i % numConvex + 1]
        local dx, dy = Geometry.Normalize(localXs[b] - localXs[a], localYs[b] - localYs[a], 0)
        if dx ~= 0 or dy ~= 0 then
            local minX, minY, minZ = huge, huge, huge
            local maxX, maxY, maxZ = -huge, -huge, -huge
            for k = 1, numConvex do
                local c = convex[k]
                local x, y, z = localXs[c], localYs[c], localZs[c]
                local u = Geometry.Dot(dx, dy, 0, x, y, 0)
                local _, _, v = Geometry.Cross(dx, dy, 0, x, y, 0)
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
                mbrDX, mbrDY = dx, dy
                mbrMinX, mbrMinY, mbrMinZ = minX, minY, minZ
                sizeX, sizeY, sizeZ = maxX - minX, maxY - minY, maxZ - minZ
            end
        end
    end

    -- The rectangle in the plane, of which the origin is the corner of the minimum.
    local rectToPlane = {
        mbrDX, -mbrDY, 0, 0,
        mbrDY,  mbrDX, 0, 0,
        0,      0,     1, 0,
    }
    rectToPlane[4], rectToPlane[8], rectToPlane[12] = Geometry.TransformPoint(rectToPlane, mbrMinX, mbrMinY, mbrMinZ)
    return Geometry.Multiply(planeToWorld, rectToPlane), sizeX, sizeY, sizeZ
end

---Finds the oriented minimum bounding box of points, along the eigenvectors of their covariance.
---@param xs number[]
---@param ys number[]
---@param zs number[]
---@return number[] localToWorld The origin and the orientation of the box in the world coordinate system.
---@return number   sizeX        The size of the box in Hammer units.
---@return number   sizeY
---@return number   sizeZ
function BoundingBox.FindMinimumOBB(xs, ys, zs)
    local n = #xs
    local meanX, meanY, meanZ = 0, 0, 0
    for i = 1, n do
        meanX, meanY, meanZ = meanX + xs[i], meanY + ys[i], meanZ + zs[i]
    end
    meanX, meanY, meanZ = meanX / n, meanY / n, meanZ / n

    -- Calculates a variance-covariance matrix
    --     [ sxx sxy szx ]
    -- S = [ sxy syy syz ]
    --     [ szx syz szz ]
    local sxx, syy, szz = 0, 0, 0
    local sxy, syz, szx = 0, 0, 0
    for i = 1, n do
        local dx, dy, dz = xs[i] - meanX, ys[i] - meanY, zs[i] - meanZ
        sxx, syy, szz = sxx + dx * dx, syy + dy * dy, szz + dz * dz
        sxy, syz, szx = sxy + dx * dy, syz + dy * dz, szx + dz * dx
    end

    -- Here I don't divide variance by the number of the points as I just need eigenvectors.

    -- The axes will be eigenvectors by Jacobi's algorithm, as the columns of the rotation R.
    local r11, r12, r13 = 1, 0, 0
    local r21, r22, r23 = 0, 1, 0
    local r31, r32, r33 = 0, 0, 1
    for _ = 1, 20 do
        local sxySqr, syzSqr, szxSqr = sxy * sxy, syz * syz, szx * szx
        local maxCovarianceSqr = max(sxySqr, syzSqr, szxSqr)
        if maxCovarianceSqr < Util.eps then break end
        if maxCovarianceSqr == sxySqr then
            --             [ c  -s  0 ][ xx xy xz ][  c  s  0 ]
            -- S' = RᵀSR = [ s   c  0 ][ xy yy yz ][ -s  c  0 ]
            --             [ 0   0  1 ][ xz yz zz ][  0  0  1 ]
            --             [ cxx - sxy   cxy - syy   cxz - syz ][ c -s  0 ]
            --           = [ sxx + cxy   sxy + cyy   sxz + cyz ][ s  c  0 ]
            --             [        xz          yz          zz ][ 0  0  1 ]
            --             [ ccxx - 2csxy + ssyy                     0   cxz - syz ]
            --           = [                   0   ssxx + 2csxy + ccyy   sxz + cyz ]
            --             [          cxz -  syz            sxz +  cyz          zz ]
            local tau = (syy - sxx) / (2 * sxy)
            local tan = (tau < 0 and -1 or 1) / (abs(tau) + sqrt(1 + tau * tau))
            local c = 1 / sqrt(1 + tan * tan)
            local s = c * tan
            local cc, ss2, cs2 = c * c, s * s, 2 * s * c * sxy
            sxx, syy = cc * sxx + ss2 * syy - cs2, ss2 * sxx + cc * syy + cs2
            sxy, syz, szx = 0, c * syz + s * szx, c * szx - s * syz
            -- R = R * [ c s 0; -s c 0; 0 0 1 ]
            r11, r12 = c * r11 - s * r12, s * r11 + c * r12
            r21, r22 = c * r21 - s * r22, s * r21 + c * r22
            r31, r32 = c * r31 - s * r32, s * r31 + c * r32
        elseif maxCovarianceSqr == syzSqr then
            --             [ 1  0  0 ][ xx xy xz ][ 1  0  0 ]
            -- S' = RᵀSR = [ 0  c -s ][ xy yy yz ][ 0  c  s ]
            --             [ 0  s  c ][ xz yz zz ][ 0 -s  c ]
            --             [        xx          xy          xz ][ 1  0  0 ]
            --           = [ cxy - sxz   cyy - syz   cyz - szz ][ 0  c  s ]
            --             [ sxy + cxz   syy + cyz   syz + czz ][ 0 -s  c ]
            --             [        xx            cxy -  sxz            szy +  cxz ]
            --           = [ cxy - sxz   ccyy - 2csyz + sszz                     0 ]
            --             [ sxy + cxz                     0   ssyy + 2csyz + cczz ]
            local tau = (szz - syy) / (2 * syz)
            local tan = (tau < 0 and -1 or 1) / (abs(tau) + sqrt(1 + tau * tau))
            local c = 1 / sqrt(1 + tan * tan)
            local s = c * tan
            local cc, ss2, cs2 = c * c, s * s, 2 * s * c * syz
            syy, szz = cc * syy + ss2 * szz - cs2, ss2 * syy + cc * szz + cs2
            sxy, syz, szx = c * sxy - s * szx, 0, c * szx + s * sxy
            -- R = R * [ 1 0 0; 0 c s; 0 -s c ]
            r12, r13 = c * r12 - s * r13, s * r12 + c * r13
            r22, r23 = c * r22 - s * r23, s * r22 + c * r23
            r32, r33 = c * r32 - s * r33, s * r32 + c * r33
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
            local tau = (szz - sxx) / (2 * szx)
            local tan = (tau < 0 and -1 or 1) / (abs(tau) + sqrt(1 + tau * tau))
            local c = 1 / sqrt(1 + tan * tan)
            local s = c * tan
            local cc, ss2, cs2 = c * c, s * s, 2 * s * c * szx
            sxx, szz = cc * sxx + ss2 * szz - cs2, ss2 * sxx + cc * szz + cs2
            sxy, syz, szx = c * sxy - s * syz, c * syz + s * sxy, 0
            -- R = R * [ c 0 s; 0 1 0; -s 0 c ]
            r11, r13 = c * r11 - s * r13, s * r11 + c * r13
            r21, r23 = c * r21 - s * r23, s * r21 + c * r23
            r31, r33 = c * r31 - s * r33, s * r31 + c * r33
        end
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
    local boxToWorld = {
        r11, r12, r13, meanX,
        r21, r22, r23, meanY,
        r31, r32, r33, meanZ,
    }
    local worldToBox = Geometry.InvertRotationTranslation(boxToWorld)
    local minX, minY, minZ = huge, huge, huge
    local maxX, maxY, maxZ = -huge, -huge, -huge
    for i = 1, n do
        local x, y, z = Geometry.TransformPoint(worldToBox, xs[i], ys[i], zs[i])
        minX, minY, minZ = min(minX, x), min(minY, y), min(minZ, z)
        maxX, maxY, maxZ = max(maxX, x), max(maxY, y), max(maxZ, z)
    end

    -- Moves the origin to the corner of the minimum.
    boxToWorld[4], boxToWorld[8], boxToWorld[12] = Geometry.TransformPoint(boxToWorld, minX, minY, minZ)
    return boxToWorld, maxX - minX, maxY - minY, maxZ - minZ
end

return BoundingBox
