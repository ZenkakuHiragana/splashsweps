
-- Geometry on plain numbers, which avoids calling C functions of Vector, Angle, and VMatrix in long loops.
-- A vector is given as its x, y, and z.
-- A transform is a 3x4 matrix as a table of 12 numbers in row-major order,
-- the same as the first 3 rows of VMatrix:Unpack, whose columns are forward, left, up, and the translation.

---@class ss
local ss = SplashSWEPs

local Util = ss.import "splashsweps/shared/util"

---@class ss.GeometryModule
local Geometry = ss.module "splashsweps/shared/geometry"

local abs = math.abs
local atan2 = math.atan2
local cos = math.cos
local deg = math.deg
local max = math.max
local min = math.min
local rad = math.rad
local sin = math.sin
local sqrt = math.sqrt

---@param ax number
---@param ay number
---@param az number
---@param bx number
---@param by number
---@param bz number
---@return number
function Geometry.Dot(ax, ay, az, bx, by, bz)
    return ax * bx + ay * by + az * bz
end

---@param ax number
---@param ay number
---@param az number
---@param bx number
---@param by number
---@param bz number
---@return number x
---@return number y
---@return number z
function Geometry.Cross(ax, ay, az, bx, by, bz)
    return ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
end

---@param x number
---@param y number
---@param z number
---@return number
function Geometry.Length(x, y, z)
    return sqrt(x * x + y * y + z * z)
end

---@param x number
---@param y number
---@param z number
---@return number
function Geometry.LengthSqr(x, y, z)
    return x * x + y * y + z * z
end

---Returns the vector of length 1 in the same direction, or the zero vector for the zero vector.
---@param x number
---@param y number
---@param z number
---@return number x
---@return number y
---@return number z
function Geometry.Normalize(x, y, z)
    local length = sqrt(x * x + y * y + z * z)
    if length == 0 then return 0, 0, 0 end
    return x / length, y / length, z / length
end

---Returns the dual basis of vectors a and b: the vectors a* and b* in the plane of a and b such that
---a・a* = 1, b・a* = 0, a・b* = 0, and b・b* = 1.
---A point p = s * a + t * b in the plane has s = p・a* and t = p・b*.
---@param ax number
---@param ay number
---@param az number
---@param bx number
---@param by number
---@param bz number
---@return number aDualX, number aDualY, number aDualZ, number bDualX, number bDualY, number bDualZ
function Geometry.DualBasis(ax, ay, az, bx, by, bz)
    local aa = Geometry.Dot(ax, ay, az, ax, ay, az)
    local ab = Geometry.Dot(ax, ay, az, bx, by, bz)
    local bb = Geometry.Dot(bx, by, bz, bx, by, bz)
    local det = aa * bb - ab * ab
    return (bb * ax - ab * bx) / det, (bb * ay - ab * by) / det, (bb * az - ab * bz) / det,
           (aa * bx - ab * ax) / det, (aa * by - ab * ay) / det, (aa * bz - ab * az) / det
end

---Creates a transform from angles in degrees and a translation, as VMatrix:SetAngles and SetTranslation do.
---@param pitch number
---@param yaw   number
---@param roll  number
---@param x     number
---@param y     number
---@param z     number
---@return number[]
function Geometry.FromAngles(pitch, yaw, roll, x, y, z)
    local sp, cp = sin(rad(pitch)), cos(rad(pitch))
    local sy, cy = sin(rad(yaw)), cos(rad(yaw))
    local sr, cr = sin(rad(roll)), cos(rad(roll))
    return {
        cp * cy, sp * sr * cy - cr * sy, sp * cr * cy + sr * sy, x,
        cp * sy, sp * sr * sy + cr * cy, sp * cr * sy - sr * cy, y,
        -sp,     sr * cp,                cr * cp,                z,
    }
end

---Returns the angles in degrees of the rotation of a transform, as VMatrix:GetAngles does.
---@param m number[]
---@return number pitch
---@return number yaw
---@return number roll
function Geometry.ToAngles(m)
    local forwardX, forwardY, forwardZ = m[1], m[5], m[9]
    local xyDistance = sqrt(forwardX * forwardX + forwardY * forwardY)
    if xyDistance > 0.001 then
        return deg(atan2(-forwardZ, xyDistance)), deg(atan2(forwardY, forwardX)), deg(atan2(m[10], m[11]))
    else -- The forward is almost vertical, and the yaw and the roll are the same rotation.
        return deg(atan2(-forwardZ, xyDistance)), deg(atan2(-m[2], m[6])), 0
    end
end

---Returns the product a * b of transforms, which applies b first.
---@param a number[]
---@param b number[]
---@return number[]
function Geometry.Multiply(a, b)
    local m = {} ---@type number[]
    for row = 0, 8, 4 do
        local a1, a2, a3, a4 = a[row + 1], a[row + 2], a[row + 3], a[row + 4]
        m[row + 1] = a1 * b[1] + a2 * b[5] + a3 * b[9]
        m[row + 2] = a1 * b[2] + a2 * b[6] + a3 * b[10]
        m[row + 3] = a1 * b[3] + a2 * b[7] + a3 * b[11]
        m[row + 4] = a1 * b[4] + a2 * b[8] + a3 * b[12] + a4
    end

    return m
end

---Returns the inverse of a transform made of a rotation and a translation, as VMatrix:GetInverseTR does.
---@param m number[]
---@return number[]
function Geometry.InvertRotationTranslation(m)
    local x, y, z = m[4], m[8], m[12]
    return {
        m[1], m[5], m[9],  -(m[1] * x + m[5] * y + m[9] * z),
        m[2], m[6], m[10], -(m[2] * x + m[6] * y + m[10] * z),
        m[3], m[7], m[11], -(m[3] * x + m[7] * y + m[11] * z),
    }
end

---@param m number[]
---@param x number
---@param y number
---@param z number
---@return number x
---@return number y
---@return number z
function Geometry.TransformPoint(m, x, y, z)
    return m[1] * x + m[2] * y + m[3]  * z + m[4],
           m[5] * x + m[6] * y + m[7]  * z + m[8],
           m[9] * x + m[10] * y + m[11] * z + m[12]
end

---Returns the AABB that contains a box transformed by a transform.
---@param m    number[]
---@param minX number The minimum of the box.
---@param minY number
---@param minZ number
---@param maxX number The maximum of the box.
---@param maxY number
---@param maxZ number
---@return number minX, number minY, number minZ, number maxX, number maxY, number maxZ
function Geometry.TransformAABB(m, minX, minY, minZ, maxX, maxY, maxZ)
    local centerX, centerY, centerZ
        = Geometry.TransformPoint(m, (minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2)
    local halfX, halfY, halfZ = (maxX - minX) / 2, (maxY - minY) / 2, (maxZ - minZ) / 2
    local extentX = halfX * abs(m[1]) + halfY * abs(m[2])  + halfZ * abs(m[3])
    local extentY = halfX * abs(m[5]) + halfY * abs(m[6])  + halfZ * abs(m[7])
    local extentZ = halfX * abs(m[9]) + halfY * abs(m[10]) + halfZ * abs(m[11])
    return centerX - extentX, centerY - extentY, centerZ - extentZ,
           centerX + extentX, centerY + extentY, centerZ + extentZ
end

---Tests if an oriented box intersects with an axis-aligned box, by the separating axis test.
---The oriented box is [0, sizeX] x [0, sizeY] x [0, sizeZ] in the coordinates that m converts into.
---@param m     number[] The transform from the coordinates of the axis-aligned box into those of the oriented box,
---                      which only rotates and translates.
---@param sizeX number
---@param sizeY number
---@param sizeZ number
---@param cx    number   The center of the axis-aligned box.
---@param cy    number
---@param cz    number
---@param hx    number   The half extents of the axis-aligned box.
---@param hy    number
---@param hz    number
---@return boolean
function Geometry.IsBoxIntersectingAABB(m, sizeX, sizeY, sizeZ, cx, cy, cz, hx, hy, hz)
    local eps = Util.eps
    local r00, r01, r02 = m[1], m[2], m[3]
    local r10, r11, r12 = m[5], m[6], m[7]
    local r20, r21, r22 = m[9], m[10], m[11]
    local ex, ey, ez = sizeX * 0.5, sizeY * 0.5, sizeZ * 0.5
    -- The center of the axis-aligned box from that of the oriented box, in the coordinates of the oriented box
    local t0 = r00 * cx + r01 * cy + r02 * cz + m[4] - ex
    local t1 = r10 * cx + r11 * cy + r12 * cz + m[8] - ey
    local t2 = r20 * cx + r21 * cy + r22 * cz + m[12] - ez
    local a00, a01, a02 = abs(r00) + eps, abs(r01) + eps, abs(r02) + eps
    local a10, a11, a12 = abs(r10) + eps, abs(r11) + eps, abs(r12) + eps
    local a20, a21, a22 = abs(r20) + eps, abs(r21) + eps, abs(r22) + eps
    -- The axes of the oriented box
    if abs(t0) > ex + hx * a00 + hy * a01 + hz * a02 then return false end
    if abs(t1) > ey + hx * a10 + hy * a11 + hz * a12 then return false end
    if abs(t2) > ez + hx * a20 + hy * a21 + hz * a22 then return false end
    -- The axes of the axis-aligned box
    if abs(t0 * r00 + t1 * r10 + t2 * r20) > ex * a00 + ey * a10 + ez * a20 + hx then return false end
    if abs(t0 * r01 + t1 * r11 + t2 * r21) > ex * a01 + ey * a11 + ez * a21 + hy then return false end
    if abs(t0 * r02 + t1 * r12 + t2 * r22) > ex * a02 + ey * a12 + ez * a22 + hz then return false end
    -- The cross products of the axes of the two boxes
    if abs(t2 * r10 - t1 * r20) > ey * a20 + ez * a10 + hy * a02 + hz * a01 then return false end
    if abs(t2 * r11 - t1 * r21) > ey * a21 + ez * a11 + hx * a02 + hz * a00 then return false end
    if abs(t2 * r12 - t1 * r22) > ey * a22 + ez * a12 + hx * a01 + hy * a00 then return false end
    if abs(t0 * r20 - t2 * r00) > ex * a20 + ez * a00 + hy * a12 + hz * a11 then return false end
    if abs(t0 * r21 - t2 * r01) > ex * a21 + ez * a01 + hx * a12 + hz * a10 then return false end
    if abs(t0 * r22 - t2 * r02) > ex * a22 + ez * a02 + hx * a11 + hy * a10 then return false end
    if abs(t1 * r00 - t0 * r10) > ex * a10 + ey * a00 + hy * a22 + hz * a21 then return false end
    if abs(t1 * r01 - t0 * r11) > ex * a11 + ey * a01 + hx * a22 + hz * a20 then return false end
    if abs(t1 * r02 - t0 * r12) > ex * a12 + ey * a02 + hx * a21 + hy * a20 then return false end
    return true
end

---Tests if the projections of a triangle onto an axis, p0, p1, and p2, are apart from that of a box, [-r, r].
---@param p0 number
---@param p1 number
---@param p2 number
---@param r  number
---@return boolean
local function isApart(p0, p1, p2, r)
    return min(p0, p1, p2) > r or max(p0, p1, p2) < -r
end

---Tests if the axes X, Y, and Z of an axis-aligned box crossed with an edge of a triangle,
---which are (0, -ez, ey), (ez, 0, -ex), and (-ey, ex, 0), separate the triangle from the box.
---@param ex  number The edge.
---@param ey  number
---@param ez  number
---@param v0x number The vertices of the triangle from the center of the box.
---@param v0y number
---@param v0z number
---@param v1x number
---@param v1y number
---@param v1z number
---@param v2x number
---@param v2y number
---@param v2z number
---@param hx  number The half extents of the box.
---@param hy  number
---@param hz  number
---@return boolean
local function isSeparatedByEdge(ex, ey, ez, v0x, v0y, v0z, v1x, v1y, v1z, v2x, v2y, v2z, hx, hy, hz)
    return isApart(ey * v0z - ez * v0y, ey * v1z - ez * v1y, ey * v2z - ez * v2y, hy * abs(ez) + hz * abs(ey))
        or isApart(ez * v0x - ex * v0z, ez * v1x - ex * v1z, ez * v2x - ex * v2z, hx * abs(ez) + hz * abs(ex))
        or isApart(ex * v0y - ey * v0x, ex * v1y - ey * v1x, ex * v2y - ey * v2x, hx * abs(ey) + hy * abs(ex))
end

---Tests if a triangle intersects with an axis-aligned box, by the separating axis test.
---@param ax number The vertices of the triangle.
---@param ay number
---@param az number
---@param bx number
---@param by number
---@param bz number
---@param cx number
---@param cy number
---@param cz number
---@param qx number The center of the box.
---@param qy number
---@param qz number
---@param hx number The half extents of the box.
---@param hy number
---@param hz number
---@return boolean
function Geometry.IsTriangleIntersectingAABB(ax, ay, az, bx, by, bz, cx, cy, cz, qx, qy, qz, hx, hy, hz)
    local v0x, v0y, v0z = ax - qx, ay - qy, az - qz
    local v1x, v1y, v1z = bx - qx, by - qy, bz - qz
    local v2x, v2y, v2z = cx - qx, cy - qy, cz - qz

    -- The axes of the box, which also tell if the box contains the triangle
    local minX, maxX = min(v0x, v1x, v2x), max(v0x, v1x, v2x)
    local minY, maxY = min(v0y, v1y, v2y), max(v0y, v1y, v2y)
    local minZ, maxZ = min(v0z, v1z, v2z), max(v0z, v1z, v2z)
    if minX > hx or maxX < -hx or minY > hy or maxY < -hy or minZ > hz or maxZ < -hz then return false end
    if minX >= -hx and maxX <= hx and minY >= -hy and maxY <= hy and minZ >= -hz and maxZ <= hz then return true end

    -- The normal of the triangle
    local e0x, e0y, e0z = v1x - v0x, v1y - v0y, v1z - v0z
    local e1x, e1y, e1z = v2x - v1x, v2y - v1y, v2z - v1z
    local e2x, e2y, e2z = v0x - v2x, v0y - v2y, v0z - v2z
    local nx, ny, nz = Geometry.Cross(e0x, e0y, e0z, e1x, e1y, e1z)
    if abs(nx * v0x + ny * v0y + nz * v0z) > hx * abs(nx) + hy * abs(ny) + hz * abs(nz) then return false end

    -- The axes of the box crossed with the edges
    return not (isSeparatedByEdge(e0x, e0y, e0z, v0x, v0y, v0z, v1x, v1y, v1z, v2x, v2y, v2z, hx, hy, hz)
        or isSeparatedByEdge(e1x, e1y, e1z, v0x, v0y, v0z, v1x, v1y, v1z, v2x, v2y, v2z, hx, hy, hz)
        or isSeparatedByEdge(e2x, e2y, e2z, v0x, v0y, v0z, v1x, v1y, v1z, v2x, v2y, v2z, hx, hy, hz))
end

return Geometry
