
---@class ss
local ss = SplashSWEPs
if not ss then return end

local abs = math.abs
local max = math.max
local sqrt = math.sqrt
local sort = table.sort
local tableCopy = table.Copy
local Vector = Vector
local Matrix = Matrix

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
            if cross.z > 0 or pq:LengthSqr() < ss.eps or pr:LengthSqr() < ss.eps then
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
            if cross.z > 0 or pq:LengthSqr() < ss.eps or pr:LengthSqr() < ss.eps then
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
function ss.FindMBR(vertices, angle)
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

    local mbrMins = ss.vector_one * math.huge
    local minArea = math.huge
    local mbrSize = Vector()
    local mbrRotation = Matrix()
    local convex = GetConvex(vertices2D)
    for i = 1, #convex do
        local p0, p1 = convex[i], convex[i % #convex + 1]
        local dp = p1 - p0
        if dp:LengthSqr() > 0 then
            local dir = dp:GetNormalized()
            local rotation = Matrix() -- to represent the angle of the MBR
            rotation:SetForward(dir)
            rotation:SetRight(Vector(dir.y, -dir.x))
            rotation:SetUp(vector_up)

            local maxs = ss.vector_one * -math.huge
            local mins = ss.vector_one * math.huge
            local rotationInv = rotation:GetInverseTR()
            for _, v in ipairs(convex) do
                maxs:Set(ss.MaxVector(maxs, rotationInv * v))
                mins:Set(ss.MinVector(mins, rotationInv * v))
            end

            local size = maxs - mins
            if minArea > size.x * size.y then
                minArea = size.x * size.y
                mbrMins = mins
                mbrSize = size
                mbrRotation = rotation
            end
        end
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
function ss.FindMinimumOBB(vertices)
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
        if maxCovarianceSqr < ss.eps then break end
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
    local mins = ss.vector_one * math.huge
    local maxs = ss.vector_one * -math.huge
    for _, v in ipairs(vertices) do
        local pos = worldToLocal * v.Translation
        mins:Set(ss.MinVector(mins, pos))
        maxs:Set(ss.MaxVector(maxs, pos))
    end

    localToWorld:Translate(mins)
    return localToWorld, maxs - mins
end
