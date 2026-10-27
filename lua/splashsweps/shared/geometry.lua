
-- Geometry on plain numbers, which avoids calling C functions of Vector, Angle, and VMatrix in long loops.
-- A vector is given as its x, y, and z.
-- A transform is a 3x4 matrix as a table of 12 numbers in row-major order,
-- the same as the first 3 rows of VMatrix:Unpack, whose columns are forward, left, up, and the translation.

---@class ss
local ss = SplashSWEPs

---@class ss.GeometryModule
local Geometry = ss.module "splashsweps/shared/geometry"

local abs = math.abs
local atan2 = math.atan2
local cos = math.cos
local deg = math.deg
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

return Geometry
