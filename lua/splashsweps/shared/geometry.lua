
-- Geometry on plain numbers, which avoids calling C functions of Vector, Angle, and VMatrix in long loops.
-- A vector is given as its x, y, and z.
-- A transform is a 3x4 matrix as a table of 12 numbers in row-major order,
-- the same as the first 3 rows of VMatrix:Unpack, whose columns are forward, left, up, and the translation.

---@class ss
local ss = SplashSWEPs

---@class ss.GeometryModule
local Geometry = ss.module "splashsweps/shared/geometry"

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

return Geometry
