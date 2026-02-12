
-- Clientside ink renderer

---@class ss
local ss = SplashSWEPs
if not ss then return end
local locals = ss.Locals ---@class ss.Locals
if not locals.Renderer then
    locals.Renderer = {} ---@class ss.Locals.Renderer
    locals.Renderer.Queue = {}
end

---@class ss.Locals.Renderer.Queue
---@field pos    Vector   The world position to paint
---@field ang    Angle    The world angles to paint
---@field scale  Vector   X/Y/Z scale in hammer units
---@field base   number[] UV range for $basetexture
---@field detail number[] UV range for $detail
---@field shape  number[] UV range for the shape mask
---@field surf   number[] UV range for the surface
---@field time   number   CurTime()-based paint time
---@field tint   number[] UV range for $tinttexture
---@field typeid integer  ID of brush type
---@field row1   number[] The first row of World to UV matrix
---@field row2   number[] The second row of World to UV matrix

---CurTime() based time to perform traces to check player's ink state.
---@type ss.Locals.Renderer.Queue[]
local Queue = locals.Renderer.Queue

local MinTime,    MaxTime    = 0, 0 --- = Queue[1].time, Queue[#Queue].time
local NUM_REGION, NUM_VERTEX = 4, 4
local MAX_QUEUE = math.floor(32768 / (NUM_VERTEX * NUM_REGION))
local InkWaterMaterial = Material "splashsweps/shaders/inkmesh"
local InkDrawMaterial = Material "splashsweps/shaders/drawink"
local CVarWireframe = GetConVar "mat_wireframe"
local CVarMinecraft = GetConVar "mat_showlowresimage"
local math_Remap = math.Remap
local net_ReadInt = net.ReadInt
local net_ReadUInt = net.ReadUInt
local Vector, Angle = Vector, Angle

---@return fun(m: ss.MeshData, ent: Entity?)
local function NormalMeshHandler()
    local currentMaterial = nil ---@type IMaterial?
    return function(m, ent)
        local mat = m.Material
        if currentMaterial ~= mat then
            render.SetMaterial(mat)
            currentMaterial = mat
        end
        m.Mesh:Draw()
    end
end

---@return fun(m: ss.MeshData, ent: Entity?)
local function FlashlightHandler()
    local currentMaterial = nil ---@type IMaterial?
    return function(m, ent)
        local mat = m.MaterialFlashlight
        if currentMaterial ~= mat then
            render.SetMaterial(mat)
            currentMaterial = mat
        end
        m.MeshFlashlight:Draw()
    end
end

---@return fun(m: ss.MeshData, ent: Entity?)
local function WaterHandler()
    return function(m, ent) m.Mesh:Draw() end
end

---@param handler fun(m: ss.MeshData, ent: Entity?)
local function DrawMesh(handler)
    for _, model in ipairs(ss.RenderBatches) do -- Draw ink surface
        local ent = model.BrushEntity
        if #model > 0 and (not ent or IsValid(ent)) then
            if IsValid(ent) then ---@cast ent -?
                cam.PushModelMatrix(ent:GetWorldTransformMatrix())
            end

            for _, m in ipairs(model) do
                handler(m, ent)
            end

            if IsValid(ent) then
                cam.PopModelMatrix()
            end
        end
    end
end

hook.Add("PreRender", "SplashSWEPs: Refresh material parameters", function()
    local sunInfo = util.GetSunInfo()
    local sunDir = sunInfo and sunInfo.direction or Vector(0, 0.3, 0.954)
    InkWaterMaterial:SetFloat("$c0_x", sunDir.x)
    InkWaterMaterial:SetFloat("$c0_y", sunDir.y)
    InkWaterMaterial:SetFloat("$c0_z", sunDir.z)
    for _, model in ipairs(ss.RenderBatches) do
        for _, m in ipairs(model) do
            m.Material:SetFloat("$c0_x", sunDir.x)
            m.Material:SetFloat("$c0_y", sunDir.y)
            m.Material:SetFloat("$c0_z", sunDir.z)
        end
    end
end)

hook.Add("PreDrawTranslucentRenderables", "SplashSWEPs: Draw ink",
function(bDrawingDepth, bDrawingSkybox)
    -- if ss.GetOption "hideink" then return end
    if LocalPlayer():KeyDown(IN_RELOAD) then return end
    if bDrawingSkybox or CVarWireframe:GetBool() or CVarMinecraft:GetBool() then return end
    local rt = render.GetRenderTarget()
    local isDrawingWater = rt and rt:GetName():find "_rt_waterref"
    if isDrawingWater then
        render.SetMaterial(InkWaterMaterial)
        render.DepthRange(0, 65535 / 65536)
        DrawMesh(WaterHandler())
        render.DepthRange(0, 1)
        return
    end

    render.UpdateScreenEffectTexture(1)
    render.DepthRange(0, 65535 / 65536)
    render.OverrideDepthEnable(true, true)
    DrawMesh(NormalMeshHandler())
    render.OverrideDepthEnable(false)
    render.OverrideBlend(true, BLEND_DST_COLOR, BLEND_ONE, BLENDFUNC_ADD, BLEND_ONE, BLEND_ONE, BLENDFUNC_ADD)
    render.RenderFlashlights(function() DrawMesh(FlashlightHandler()) end)
    render.OverrideBlend(false)
    render.DepthRange(0, 1)
end)

net.Receive("SplashSWEPs: Paint", function()
    local inktype    = net_ReadUInt(ss.MAX_INKTYPE_BITS) + 1 -- Ink type
    local shapeIndex = net_ReadUInt(ss.MAX_INKSHAPE_BITS) + 1 -- Ink shape
    local pitch      = net_ReadInt(8) -- Pitch
    local yaw        = net_ReadInt(8) -- Yaw
    local roll       = net_ReadInt(8) -- Roll
    local x          = net_ReadInt(15) * 2 -- X
    local y          = net_ReadInt(15) * 2 -- Y
    local z          = net_ReadInt(15) * 2 -- Z
    local sx         = net_ReadUInt(ss.MAX_INK_RADIUS_BITS) * 2 -- Scale X
    local sy         = net_ReadUInt(ss.MAX_INK_RADIUS_BITS) * 2 -- Scale Y
    local sz         = net_ReadUInt(ss.MAX_INK_RADIUS_BITS) * 2 -- Scale Z
    local scale      = Vector(sx, sy, sz)
    local pos        = Vector(x, y, z)
    local angle      = Angle(
        math_Remap(pitch, -128, 127, -180, 180),
        math_Remap(yaw,   -128, 127, -180, 180),
        math_Remap(roll,  -128, 127, -180, 180))
    ss.Paint(pos, angle, scale, shapeIndex, inktype)
end)

---@param worldPos Vector  The origin.
---@param worldAng Angle   The normal and rotation.
---@param scale    Vector  Scale along the angles which is limited to 510 Hammer units because of network optimization.
---@param shape    integer The internal index of shape to paint.
---@param typeid   integer The internal index of ink type.
function ss.PushPaintRenderTargetQueue(worldPos, worldAng, scale, shape, typeid)
    local inkshape = ss.InkShapes[shape]
    local inktype = ss.InkTypes[typeid]
    if not (inkshape and inktype) then return end
    MaxTime = CurTime()
    if #Queue == 0 then MinTime = MaxTime end
    local mins, maxs = ss.GetPaintBoundingBox(worldPos, worldAng, scale)
    for surf in ss.CollectSurfaces(mins, maxs) do
        for posWarp, angWarp in ss.EnumeratePaintPositions(surf, mins, maxs, worldPos, worldAng) do
            Queue[#Queue + 1] = {
                pos    = posWarp,
                ang    = angWarp,
                scale  = scale,
                base   = inktype.BaseUV,
                detail = inktype.DetailUV,
                shape  = inkshape.UV,
                time   = MaxTime,
                tint   = inktype.TintUV,
                typeid = typeid,
                row1   = surf.WorldToUVRow1,
                row2   = surf.WorldToUVRow2,
                surf   = {
                    surf.OffsetU,
                    surf.OffsetV,
                    surf.OffsetU + surf.UVWidth,
                    surf.OffsetV + surf.UVHeight,
                },
            }
        end
    end
end

---Clears all painted ink in the map.
function ss.ClearAllInk()
    for _, s in ipairs(ss.SurfaceArray) do ss.ClearGrid(s) end
    local rt = ss.RenderTarget.StaticTextures.InkMap
    render.PushRenderTarget(rt)
    render.OverrideAlphaWriteEnable(true, true)
    render.ClearDepth()
    render.ClearStencil()
    render.Clear(0, 0, 0, 128)
    render.SetViewPort(rt:Width() / 2, 0, rt:Width() / 2, rt:Height() / 2)
    render.Clear(255, 255, 255, 0)
    render.OverrideAlphaWriteEnable(false)
    render.PopRenderTarget()
    ss.LoadInkTypesRT()
end

local mesh_Begin              = mesh.Begin
local mesh_End                = mesh.End
local mesh_TexCoord           = mesh.TexCoord
local mesh_Position           = mesh.Position
local mesh_Normal             = mesh.Normal
local mesh_Color              = mesh.Color
local mesh_AdvanceVertex      = mesh.AdvanceVertex
local mesh_VertexCount        = mesh.VertexCount
local render_ClearDepth       = render.ClearDepth
local render_CopyRenderTarget = render.CopyRenderTargetToTexture
local render_PushRenderTarget = render.PushRenderTarget
local render_PopRenderTarget  = render.PopRenderTarget
local render_SetMaterial      = render.SetMaterial
local max, min, RealFrameTime = math.max, math.min, RealFrameTime
local ipairs, pairs, unpack   = ipairs, pairs, unpack
hook.Add("RenderScreenspaceEffects", "SplashSWEPs: Paint ink in queue", function()
    if #Queue == 0 then return end
    local numQuads = #Queue
    local primitiveCount = min(numQuads, MAX_QUEUE) * NUM_REGION
    local RcpTimeRange = 1 / max(MaxTime - MinTime, RealFrameTime())
    render_PushRenderTarget(ss.RenderTarget.StaticTextures.InkMap)
    render_CopyRenderTarget(ss.RenderTarget.StaticTextures.InkMap2)
    render_ClearDepth()
    render_SetMaterial(InkDrawMaterial)
    mesh_Begin(MATERIAL_QUADS, primitiveCount)
    for _, q in ipairs(Queue) do
        local normalizedTime = (q.time - MinTime) * RcpTimeRange * 255 -- pass this as color
        if mesh_VertexCount() == primitiveCount * NUM_VERTEX then
            numQuads = numQuads - MAX_QUEUE
            primitiveCount = min(numQuads, MAX_QUEUE) * NUM_REGION
            mesh_End()
            render_CopyRenderTarget(ss.RenderTarget.StaticTextures.InkMap2)
            mesh_Begin(MATERIAL_QUADS, primitiveCount)
        end

        for i = 0, 240, 16 do -- 0b0000RRCC, RR = Region, CC = Corner
            mesh_Color(normalizedTime, i, q.typeid, 0)
            mesh_Normal(q.scale)
            mesh_Position(q.pos)
            mesh_TexCoord(0, q.ang.p, q.ang.y, q.ang.r, ss.RenderTarget.HammerUnitsToUV)
            mesh_TexCoord(1, unpack(q.base))
            mesh_TexCoord(2, unpack(q.tint))
            mesh_TexCoord(3, unpack(q.detail))
            mesh_TexCoord(4, unpack(q.shape))
            mesh_TexCoord(5, unpack(q.surf))
            mesh_TexCoord(6, unpack(q.row1))
            mesh_TexCoord(7, unpack(q.row2))
            mesh_AdvanceVertex()
        end
    end
    mesh_End()
    render_PopRenderTarget()
    for k in pairs(Queue) do Queue[k] = nil end
end)
