
-- Clientside ink renderer

---@class ss
local ss = SplashSWEPs
if not ss then return end
local locals = ss.Locals ---@class ss.Locals
if not locals.Renderer then
    locals.Renderer = {} ---@class ss.Locals.Renderer
    locals.Renderer.Queue = {}
    locals.Renderer.MaterialWatchList = {}
    locals.Renderer.LastSunDirection = Vector()
    locals.Renderer.StaticPropQueue = {}
    locals.Renderer.IsDrawingStaticProps = false
end

---@class ss.Locals.Renderer
---@field IsDrawingStaticProps boolean True while the ink renderer draws the queued static props.

---@class ss.Locals.Renderer.Queue
---@field pos    Vector   The world position to paint
---@field ang    Angle    The world angles to paint
---@field scale  Vector   X/Y/Z scale in hammer units
---@field base   number[] UV range for $basetexture
---@field shape  number[] UV range for the shape mask
---@field surf   number[] UV range for the surface
---@field tint   number[] UV range for $tinttexture
---@field typeid integer  ID of brush type
---@field detail integer  $detailblendmode of the ink type, 0 if the detail is disabled
---@field row1   number[] The first row of World to UV matrix
---@field row2   number[] The second row of World to UV matrix

---@class ss.Locals.Renderer.MaterialWatchState
---@field Interval integer Index of adaptive interval array to check this parameter.
---@field LastTime number  CurTime()-based last check time for this parameter.
---@field Value    string  Last observed value.

---@class ss.Locals.Renderer.MaterialWatchEntry
---@field Material IMaterial The material to watch the changes.
---@field Fields   table<string, ss.Locals.Renderer.MaterialWatchState>

local NUM_REGION, NUM_VERTEX = 4, 4
local INDICES_REGION = 2 -- Region of the ink type IDs, the only one the boundary band of a paint updates
local NUM_TEXCOORDS = 7
local SIZEOF_POS_NORMAL_COLOR = 4 * (3 + 3 + 1) -- pos: float3, normal: float3, color: uint8 * 4
local SIZEOF_TEXCOORDS = NUM_TEXCOORDS * 4 * 4  -- texcoord: float4
local SIZEOF_VERTEX = math.ceil((SIZEOF_POS_NORMAL_COLOR + SIZEOF_TEXCOORDS) / 16) * 16 -- float4 padding
local MAX_VERTEX_SIZE_KB = (1024 + 512) * 1024 -- Maximum size of dynamic mesh hardcoded in Source
local MAX_QUADS = math.floor(MAX_VERTEX_SIZE_KB / (NUM_VERTEX * SIZEOF_VERTEX))

local FullFrameFb1 = render.GetScreenEffectTexture(1)
local SceneCopyMaterial = Material "splashsweps/shaders/scene_copy"
local InkColorInitMaterial = Material "splashsweps/shaders/gbuf_inkcolor_init"
local FlashlightInitMaterial = Material "splashsweps/shaders/flashlight_init"
local FlashlightBakeMaterial = Material "splashsweps/shaders/lightmappedgeneric"
local SSRTraceMaterial = Material "splashsweps/shaders/inkssr"
local SSRCompositeMaterial = Material "splashsweps/shaders/inkssr_compose"
local SSRDownsampleMaterial = Material "splashsweps/shaders/inkssr_downsample"
local InkWaterMaterial = Material "splashsweps/shaders/inkmesh"
local InkDrawMaterial = Material "splashsweps/shaders/drawink"
local StaticPropLightMaterial = Material "splashsweps/shaders/phong"
local StaticPropFlashlightMaterial = Material "splashsweps/shaders/vertexlitgeneric"
local StaticPropFlashlightMaterialMSAA = Material "splashsweps/shaders/vertexlitgeneric_msaa"
local CVarWireframe = GetConVar "mat_wireframe"
local CVarMinecraft = GetConVar "mat_showlowresimage"
local CVarDrawStaticProps = GetConVar "r_drawstaticprops"
local MIN_DRAW_RADIUS = 0.01 * 0.01 -- Squared minimum draw radius for static props relative to ScrH()
local math_Remap = math.Remap
local net_ReadInt = net.ReadInt
local net_ReadUInt = net.ReadUInt
local Vector, Angle = Vector, Angle

local ScreenQuadCorners = { Vector(0, 0, 0), Vector(1, 0, 0), Vector(1, 1, 0), Vector(0, 1, 0) }

---CurTime() based time to perform traces to check player's ink state.
---@type ss.Locals.Renderer.Queue[]
local Queue = locals.Renderer.Queue

---Static props the engine draws in the current view, whose ink is drawn with the ink meshes.
---@type ss.PaintableCSEnt[]
local StaticPropQueue = locals.Renderer.StaticPropQueue

---@type ss.Locals.Renderer.MaterialWatchEntry[]
local MaterialWatchList       = locals.Renderer.MaterialWatchList
local MaterialWatchInterval   = { 0, 0.05, 0.5, 1, 2, 5, math.huge }
local MaterialWatchParameters = {
    ["$basetexturetransform"] = "Matrix",
    ["$bumptransform"]        = "Matrix",
    ["$detailblendfactor"]    = "Float",
    ["$detailblendmode"]      = "Int",
    ["$detailscale"]          = "Vector",
    ["$detailtint"]           = "Vector",
    ["$color"]                = "Vector",
    ["$color2"]               = "Vector",
}

---Reflects a changed parameter of the source material to the ink material.
---
---  RefreshInkMaterial        world and static props   transforms, $color, $color2
---  RefreshWorldInkMaterial   world                    the above and $detail*
---@type table<string, fun(mat: IMaterial, src: IMaterial, value: any)>
local RefreshInkMaterial = {
    ---@param mat IMaterial
    ---@param _   IMaterial
    ---@param value VMatrix
    ["$basetexturetransform"] = function(mat, _, value)
        local m = mat:GetMatrix "$viewprojmat"
        m:SetField(1, 1, value:GetField(1, 1))
        m:SetField(1, 2, value:GetField(1, 2))
        m:SetField(1, 3, value:GetField(1, 4))
        m:SetField(2, 1, value:GetField(2, 1))
        m:SetField(2, 2, value:GetField(2, 2))
        m:SetField(2, 3, value:GetField(2, 4))
        mat:SetMatrix("$viewprojmat", m)
    end,
    ---@param mat IMaterial
    ---@param _   IMaterial
    ---@param value VMatrix
    ["$bumptransform"] = function(mat, _, value)
        local m = mat:GetMatrix "$viewprojmat"
        m:SetField(3, 1, value:GetField(1, 1))
        m:SetField(3, 2, value:GetField(1, 2))
        m:SetField(3, 3, value:GetField(1, 4))
        m:SetField(4, 1, value:GetField(2, 1))
        m:SetField(4, 2, value:GetField(2, 2))
        m:SetField(4, 3, value:GetField(2, 4))
        mat:SetMatrix("$viewprojmat", m)
    end,
    ---@param mat IMaterial
    ---@param src IMaterial
    ---@param value Vector
    ["$color"] = function(mat, src, value)
        local color = value * (src:GetVector "$color2" or ss.vector_one)
        mat:SetFloat("$c3_x", color.x)
        mat:SetFloat("$c3_y", color.y)
        mat:SetFloat("$c3_z", color.z)
    end,
    ---@param mat IMaterial
    ---@param src IMaterial
    ---@param value Vector
    ["$color2"] = function(mat, src, value)
        local color = value * (src:GetVector "$color" or ss.vector_one)
        mat:SetFloat("$c3_x", color.x)
        mat:SetFloat("$c3_y", color.y)
        mat:SetFloat("$c3_z", color.z)
    end,
}

---@type table<string, fun(mat: IMaterial, src: IMaterial, value: any)>
local RefreshWorldInkMaterial = table.Merge({
    ---@param mat IMaterial
    ---@param _   IMaterial
    ---@param value number
    ["$detailblendfactor"] = function(mat, _, value)
        local m = mat:GetMatrix "$viewprojmat"
        m:SetField(4, 4, value)
        mat:SetMatrix("$viewprojmat", m)
    end,
    ---@param mat IMaterial
    ---@param _   IMaterial
    ---@param value integer
    ["$detailblendmode"] = function(mat, _, value)
        mat:SetInt("$linearread_texture5", value == 1 and 0 or 1)
        mat:SetInt("$c0_w", value)
    end,
    ---@param mat IMaterial
    ---@param _   IMaterial
    ---@param value Vector
    ["$detailscale"] = function(mat, _, value)
        mat:SetFloat("$c2_z", value.x)
        mat:SetFloat("$c2_w", value.y)
    end,
    ---@param mat IMaterial
    ---@param _   IMaterial
    ---@param value Vector
    ["$detailtint"] = function(mat, _, value)
        local m = mat:GetMatrix "$viewprojmat"
        m:SetField(1, 4, value.x)
        m:SetField(2, 4, value.y)
        m:SetField(3, 4, value.z)
        mat:SetMatrix("$viewprojmat", m)
    end,
}, RefreshInkMaterial)

local currentNormalMaterial = nil ---@type IMaterial?
local function DrawNormalMesh(m, _)
    local mat = m.Material
    if currentNormalMaterial ~= mat then
        render.SetMaterial(mat)
        currentNormalMaterial = mat
    end
    m.Mesh:Draw()
end

---Draws the mesh with the material already set.
local function DrawMeshOnly(m, _)
    m.Mesh:Draw()
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

local function DrawFlashlightMeshes()
    for _, model in ipairs(ss.RenderBatches) do
        local ent = model.BrushEntity
        if #model.FlashlightMeshes > 0 and (not ent or IsValid(ent)) then
            if IsValid(ent) then ---@cast ent -?
                cam.PushModelMatrix(ent:GetWorldTransformMatrix())
            end

            for _, m in ipairs(model.FlashlightMeshes) do
                m:Draw()
            end

            if IsValid(ent) then
                cam.PopModelMatrix()
            end
        end
    end
end

local function DrawNormalMeshes()
    currentNormalMaterial = nil
    DrawMesh(DrawNormalMesh)
end

local StaticPropView = Matrix()

---RenderOverride of the static props. The engine draws the props themselves, and these models draw the ink.
---In each view:
---
---  PreDrawOpaqueRenderables        clears StaticPropQueue
---  ss.QueueStaticProp              queues the prop unless it is faded out or too small on the screen
---  PreDrawTranslucentRenderables   draws the queue after the ink meshes, in the flashlight and MRT passes
---  `-- prop:DrawModel()            calls ss.QueueStaticProp again, which draws the model this time
---
---The queue is left undrawn wherever the hook returns before drawing the ink meshes, such as the water reflection.
---@param self ss.PaintableCSEnt
---@param flags Enum.STUDIO
function ss.QueueStaticProp(self, flags)
    if locals.Renderer.IsDrawingStaticProps then
        self:DrawModel(flags)
        return
    end

    if bit.band(flags, STUDIO_SSAODEPTHTEXTURE) ~= 0 then return end
    if bit.band(flags, STUDIO_SHADOWDEPTHTEXTURE) ~= 0 then return end
    if not CVarDrawStaticProps:GetBool() then return end
    if self.FadeMaxSqr and self:GetPos():DistToSqr(EyePos()) > self.FadeMaxSqr then return end
    StaticPropView:SetTranslation(EyePos())
    StaticPropView:SetAngles(EyeAngles())
    StaticPropView:InvertTR()
    local fov = math.rad(render.GetViewSetup().fov)
    local z = (StaticPropView * self:GetPos()).x       -- projected z-position
    local fp = ScrH() / (2 * math.tan(fov / 2))        -- focus distance in pixels
    local r = self.ModelLengthSqr * fp * fp / (z * z) -- draw radius on the screen in pixels
    local minRadius = MIN_DRAW_RADIUS * ScrH() * ScrH()
    if r < minRadius then return end
    self.QueuedFlags = flags
    StaticPropQueue[#StaticPropQueue + 1] = self
end

---Draws the flashlight light on the queued static props into StaticPropFlashlight.
---
---  depth buffer                  depth test                     transparent parts of alpha test
---  ----------------------------  -----------------------------  -------------------------------
---  the frame's                   equal (by $alphatest)          not lit
---  from flashlight_init (MSAA)   less or equal                  lit
local function DrawStaticPropsFlashlight()
    locals.Renderer.IsDrawingStaticProps = true
    render.MaterialOverride(ss.RenderTarget.StaticPropFlashlightSharesDepth
        and StaticPropFlashlightMaterial or StaticPropFlashlightMaterialMSAA)
    for _, prop in ipairs(StaticPropQueue) do
        prop:DrawModel(prop.QueuedFlags)
    end
    render.MaterialOverride()
    locals.Renderer.IsDrawingStaticProps = false
end

---Draws the ink of the queued static props.
local function DrawStaticPropsInk()
    locals.Renderer.IsDrawingStaticProps = true
    for _, prop in ipairs(StaticPropQueue) do
        -- VertexLitGeneric leaves the lighting of the prop in the shader constants the ink material reads.
        render.MaterialOverride(StaticPropLightMaterial)
        prop:DrawModel(prop.QueuedFlags)
        render.MaterialOverride()
        prop:DrawModel(prop.QueuedFlags)
    end
    locals.Renderer.IsDrawingStaticProps = false
end

local SSRViewMatrix = Matrix()
local function UpdateViewParameters()
    local view = render.GetViewSetup()
    local origin = view.origin
    local angles = view.angles
    local aspect = view.aspect
    local tanHalfFovX = math.tan(math.rad(view.fov) * 0.5)
    local tanHalfFovY = tanHalfFovX / aspect
    local right = angles:Right() * tanHalfFovX
    local up = angles:Up() * tanHalfFovY
    local forward = angles:Forward()
    SSRViewMatrix:SetUnpacked(
        right.x, right.y, right.z, 0,
        up.x, up.y, up.z, 0,
        forward.x, forward.y, forward.z, 0,
        origin.x, origin.y, origin.z, 1)
    SSRTraceMaterial:SetMatrix("$viewprojmat", SSRViewMatrix)

    -- Maps the view depth to the depth buffer value of the current projection.
    local znear, zfar = view.znear, view.zfar
    FlashlightInitMaterial:SetFloat("$c0_x", zfar / (zfar - znear))
    FlashlightInitMaterial:SetFloat("$c0_y", -znear * zfar / (zfar - znear))
end

---Reflects the changed parameters of the source materials to their ink materials.
---@param materials table<IMaterial, IMaterial> Ink material --> source material.
---@param refreshers table<string, fun(mat: IMaterial, src: IMaterial, value: any)> RefreshInkMaterial or RefreshWorldInkMaterial.
---@param refreshList table<IMaterial, string[]> Source material --> changed parameters.
local function RefreshInkMaterials(materials, refreshers, refreshList)
    for renderMaterial, geometryMaterial in pairs(materials) do
        for _, key in ipairs(refreshList[geometryMaterial] or {}) do
            local refresh = refreshers[key]
            ---@type fun(self: IMaterial, key: string): number|Vector|VMatrix
            local get = geometryMaterial["Get" .. (MaterialWatchParameters[key] or "???")]
            if refresh and get then
                refresh(renderMaterial, geometryMaterial, get(geometryMaterial, key))
            end
        end
    end
end

hook.Add("PreRender", "SplashSWEPs: Refresh material parameters", function()
    local now = CurTime()
    local refreshList = {} ---@type table<IMaterial, string[]>
    for _, entry in ipairs(MaterialWatchList) do
        local keys = {} ---@type string[]
        for key, state in pairs(entry.Fields) do
            if now > state.LastTime + MaterialWatchInterval[state.Interval] then
                state.LastTime = now
                local value = entry.Material:GetString(key)
                if value == state.Value then
                    state.Interval = state.Interval + 1
                else
                    state.Interval = 1
                    state.Value = value
                    keys[#keys + 1] = key
                end
            end
        end

        if #keys > 0 then
            refreshList[entry.Material] = keys
        end
    end

    RefreshInkMaterials(ss.InkMeshMaterials, RefreshWorldInkMaterial, refreshList)
    RefreshInkMaterials(ss.StaticPropInkMaterials, RefreshInkMaterial, refreshList)

    local sunInfo = util.GetSunInfo()
    local sunDir = sunInfo and sunInfo.direction or Vector(0, 0.3, 0.954)
    if not ss.Locals.Renderer.LastSunDirection:IsEqualTol(sunDir, ss.eps) then
        ss.Locals.Renderer.LastSunDirection = sunDir
        InkWaterMaterial:SetFloat("$c0_x", sunDir.x)
        InkWaterMaterial:SetFloat("$c0_y", sunDir.y)
        InkWaterMaterial:SetFloat("$c0_z", sunDir.z)
        -- Only the world part reads it. The static prop part uses the four lights instead.
        for m in pairs(ss.InkMeshMaterials) do
            m:SetFloat("$c0_x", sunDir.x)
            m:SetFloat("$c0_y", sunDir.y)
            m:SetFloat("$c0_z", sunDir.z)
        end
    end
end)

-- IMAGE_FORMAT_R32F = 27, Single-channel 32-bit floating point
hook.Add("NeedsDepthPass", "SplashSWEPs: Needs depth pass", function() return true end)
GetRenderTargetEx("_rt_resolvedfullframedepth", ScrW(), ScrH(),
    RT_SIZE_FULL_FRAME_BUFFER,
    MATERIAL_RT_DEPTH_SHARED,
    bit.bor(4, 8, 256, 512, 65536), 0, 27)

-- See ss.QueueStaticProp
hook.Add("PreDrawOpaqueRenderables", "SplashSWEPs: Reset static prop queue", function()
    for k in pairs(StaticPropQueue) do StaticPropQueue[k] = nil end
end)

hook.Add("PreDrawTranslucentRenderables", "SplashSWEPs: Draw ink",
function(bDrawingDepth, bDrawingSkybox)
    -- if ss.GetOption "hideink" then return end
    if LocalPlayer():KeyDown(IN_RELOAD) then return end
    if bDrawingDepth or bDrawingSkybox then return end
    if CVarWireframe:GetBool() or CVarMinecraft:GetBool() then return end
    local rt = render.GetRenderTarget()
    local isDrawingWater = rt and rt:GetName():find "_rt_waterref"
    if isDrawingWater then
        render.SetMaterial(InkWaterMaterial)
        DrawMesh(DrawMeshOnly)
        return
    end

    -- Frame buffer copy for SSR reflection and underlay sampling
    UpdateViewParameters()
    render.CopyRenderTargetToTexture(FullFrameFb1)
    render.PushRenderTarget(ss.RenderTarget.FrameTextures.InkColor)
    render.ClearDepth(false)
    render.SetMaterial(InkColorInitMaterial)
    render.DrawQuad(ScreenQuadCorners[1], ScreenQuadCorners[2], ScreenQuadCorners[3], ScreenQuadCorners[4])
    render.PopRenderTarget()

    -- Upper half of SceneAndFlashlight: frame buffer color and view depth.
    -- Lower half: light the ink meshes receive from flashlights, behind the scene depth.
    local w, h = ScrW(), ScrH()
    render.PushRenderTarget(ss.RenderTarget.FrameTextures.SceneAndFlashlight, 0, 0, w, h)
    render.SetMaterial(SceneCopyMaterial)
    render.DrawQuad(ScreenQuadCorners[1], ScreenQuadCorners[2], ScreenQuadCorners[3], ScreenQuadCorners[4])
    render.SetViewPort(0, h, w, h)
    render.SetMaterial(FlashlightInitMaterial)
    render.DrawQuad(ScreenQuadCorners[1], ScreenQuadCorners[2], ScreenQuadCorners[3], ScreenQuadCorners[4])
    render.RenderFlashlights(function()
        render.SetMaterial(FlashlightBakeMaterial)
        DrawFlashlightMeshes()
    end)
    render.PopRenderTarget()

    if #StaticPropQueue > 0 then
        render.PushRenderTarget(ss.RenderTarget.FrameTextures.StaticPropFlashlight)
        if ss.RenderTarget.StaticPropFlashlightSharesDepth then
            render.Clear(0, 0, 0, 0)
        else
            render.SetMaterial(FlashlightInitMaterial)
            render.DrawQuad(ScreenQuadCorners[1], ScreenQuadCorners[2], ScreenQuadCorners[3], ScreenQuadCorners[4])
        end
        render.RenderFlashlights(DrawStaticPropsFlashlight)
        render.PopRenderTarget()
    end

    render.PushRenderTarget(ss.RenderTarget.FrameTextures.InkColor)
    render.SetRenderTargetEx(1, ss.RenderTarget.FrameTextures.InkNormals)
    render.SetRenderTargetEx(2, ss.RenderTarget.FrameTextures.Reflection)
    render.SetRenderTargetEx(3, ss.RenderTarget.FrameTextures.Envmap)
    render.OverrideDepthEnable(true, true)
    DrawNormalMeshes()
    DrawStaticPropsInk()
    render.OverrideDepthEnable(false)
    render.PopRenderTarget()

    -- Shrunk copy of InkColor, blurred reflections on rough surfaces read it
    render.PushRenderTarget(ss.RenderTarget.FrameTextures.InkColorBlur)
    render.SetMaterial(SSRDownsampleMaterial)
    render.DrawScreenQuad()
    render.PopRenderTarget()

    render.PushRenderTarget(ss.RenderTarget.FrameTextures.SSRResult)
    render.Clear(0, 0, 0, 0)
    render.SetMaterial(SSRTraceMaterial)
    render.DrawScreenQuad()
    render.PopRenderTarget()

    render.SetMaterial(SSRCompositeMaterial)
    render.DrawScreenQuad()
end)

---Reads the common part of paint messages.
---@return Vector  pos
---@return Angle   angle
---@return Vector  scale
---@return integer shapeIndex
---@return integer inktype
local function ReadPaint()
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
    return pos, angle, scale, shapeIndex, inktype
end

net.Receive("SplashSWEPs: Paint", function()
    ss.PaintWorld(ReadPaint())
end)

net.Receive("SplashSWEPs: Paint brush model", function()
    local modelIndex = net_ReadUInt(ss.MAX_MODEL_INDEX_BITS) + 1 -- Model index
    ss.PaintBrushModel(modelIndex, ReadPaint())
end)

---Queues a paint onto a surface to draw it into the ink map.
---@param surf   ss.PaintableSurface The surface to paint.
---@param pos    Vector  The origin in the same coordinate system as the surface.
---@param ang    Angle   The normal and rotation in the same coordinate system as the surface.
---@param scale  Vector  Scale along the angles which is limited to 510 Hammer units because of network optimization.
---@param shape  integer The internal index of shape to paint.
---@param typeid integer The internal index of ink type.
function ss.PushPaintRenderTargetQueue(surf, pos, ang, scale, shape, typeid)
    local inkshape = ss.InkShapes[shape]
    local inktype = ss.InkTypes[typeid]
    if not (inkshape and inktype) then return end
    Queue[#Queue + 1] = {
        pos    = pos,
        ang    = ang,
        scale  = scale,
        base   = inktype.BaseUV,
        shape  = inkshape.UV,
        tint   = inktype.TintUV,
        typeid = typeid,
        detail = inktype.DetailBlendMode,
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

---Clears all painted ink in the map.
function ss.ClearAllInk()
    for _, s in ipairs(ss.SurfaceArray) do ss.ClearGrid(s) end
    local rt = ss.RenderTarget.StaticTextures.InkMap
    local w, h = rt:Width() / 2, rt:Height() / 2
    render.PushRenderTarget(rt)
    render.OverrideAlphaWriteEnable(true, true)
    render.ClearDepth()
    render.ClearStencil()
    render.Clear(0, 0, 0, 0) -- Additive color
    render.SetViewPort(w, 0, w, h)
    render.Clear(255, 255, 255, 0) -- Tint color
    render.SetViewPort(0, h, w, h)
    render.Clear(0, 0, 0, 0) -- Ink type IDs, and $detailblendmode = 0 (disabled)
    render.SetViewPort(w, h, w, h)
    render.Clear(128, 0, 0, 0) -- 16-bit height = 0 and 16-bit depth = 0
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
local render_CopyRenderTarget = render.CopyRenderTargetToTexture
local render_PushRenderTarget = render.PushRenderTarget
local render_PopRenderTarget  = render.PopRenderTarget
local render_SetMaterial      = render.SetMaterial
local min                     = math.min
local ipairs, pairs, unpack   = ipairs, pairs, unpack

---Adds a quad of a queued paint, starting a new dynamic mesh every MAX_QUADS quads.
---@param q         ss.Locals.Renderer.Queue
---@param region    integer Ink map region index
---@param band      integer 255 for the boundary band outside the shape edge, 0 for the paint itself
---@param quadIndex integer Zero-based index of this quad among all quads of the batch
---@param numQuads  integer Number of quads in the batch
---@return integer nextQuadIndex
local function AddQuad(q, region, band, quadIndex, numQuads)
    if quadIndex % MAX_QUADS == 0 then
        if quadIndex > 0 then mesh_End() end
        mesh_Begin(MATERIAL_QUADS, min(numQuads - quadIndex, MAX_QUADS))
    end

    -- 0b0000RRCC, RR = Region, CC = Corner
    for i = region * NUM_VERTEX * 16, (region * NUM_VERTEX + NUM_VERTEX - 1) * 16, 16 do
        mesh_Color(band, i, q.typeid, q.detail)
        mesh_Normal(q.scale)
        mesh_Position(q.pos)
        mesh_TexCoord(0, q.ang.p, q.ang.y, q.ang.r, ss.RenderTarget.HammerUnitsToUV)
        mesh_TexCoord(1, unpack(q.base))
        mesh_TexCoord(2, unpack(q.tint))
        mesh_TexCoord(3, unpack(q.shape))
        mesh_TexCoord(4, unpack(q.surf))
        mesh_TexCoord(5, unpack(q.row1))
        mesh_TexCoord(6, unpack(q.row2))
        mesh_AdvanceVertex()
    end

    return quadIndex + 1
end

hook.Add("RenderScreenspaceEffects", "SplashSWEPs: Paint ink in queue", function()
    if #Queue == 0 then return end
    local numQuads = #Queue * (NUM_REGION + 1) -- The boundary band and the regions of each paint
    local quadIndex = 0
    render_PushRenderTarget(ss.RenderTarget.StaticTextures.InkMap)
    render_CopyRenderTarget(ss.RenderTarget.StaticTextures.InkMap2)
    render_SetMaterial(InkDrawMaterial)
    -- Quads are drawn in the queue order without depth, and the later ones overwrite the earlier ones.
    -- A band writes back the IDs of the batch-start snapshot, so every band goes before every paint.
    for _, q in ipairs(Queue) do
        quadIndex = AddQuad(q, INDICES_REGION, 255, quadIndex, numQuads)
    end
    for _, q in ipairs(Queue) do
        for region = 0, NUM_REGION - 1 do
            quadIndex = AddQuad(q, region, 0, quadIndex, numQuads)
        end
    end
    mesh_End()
    render_PopRenderTarget()
    for k in pairs(Queue) do Queue[k] = nil end
end)

---Checks material proxied to be checked in the given list of materials
---and registers them to the watch list to be refreshed.
---@param mats table<integer, { Material: IMaterial }> Materials, such as sparse enumeration-ID-indexed ss.SurfaceBuilder.MaterialInfo.
function ss.BuildMaterialWatchList(mats)
    for _, m in pairs(mats) do
        local mat = m.Material
        local vmt = string.format("materials/%s.vmt", mat:GetName())
        local vmtkv = file.Read(vmt, "GAME")
        if vmtkv and vmtkv ~= "" then
            local params = util.KeyValuesToTablePreserveOrder(vmtkv)
            local proxies ---@type KeyValue[]?
            for _, kv in ipairs(params) do
                if kv.Key == "proxies" then
                    proxies = kv.Value
                    break
                end
            end

            local states = nil ---@type ss.Locals.Renderer.MaterialWatchEntry
            for _, entry in ipairs(proxies or {}) do
                local contents = entry.Value ---@cast contents { Key: string, Value: string }[]
                local kv = table.CollapseKeyValue(contents)
                local resultvar = kv.resultvar and kv.resultvar:lower()
                if resultvar then
                    states = states or {
                        Material = mat,
                        Fields = {},
                    }
                    states.Fields[resultvar] = {
                        Interval = 1,
                        LastTime = CurTime(),
                        Value = "",
                    }
                end
            end

            if states then
                MaterialWatchList[#MaterialWatchList + 1] = states
            end
        end
    end
end

---Creates render targets and packs textures used in WorldVertexTransition and Lightmapped_4WayBlend materials.
---@param mats table<integer, ss.SurfaceBuilder.MaterialInfo> Sparse enumeration-ID-indexed materials.
function ss.BuildUnderlayTexturePack(mats)
    local copy = Material "pp/copy"
    for _, m in pairs(mats) do
        local mat = m.Material
        local bt2str = mat:GetString "$basetexture2"
        local bt3str = mat:GetString "$basetexture3"
        local bt4str = mat:GetString "$basetexture4"
        local bmtstr = mat:GetString "$blendmodulatetexture"
        local bumpstr = mat:GetString "$bumpmap"
        local bumpstr2 = mat:GetString "$bumpmap2"
        local detailstr = mat:GetString "$detail"
        if bt2str then
            local bt2 = mat:GetTexture "$basetexture2"
            local bt3 = mat:GetTexture "$basetexture3"
            local bt4 = mat:GetTexture "$basetexture4"
            local bmt = mat:GetTexture "$blendmodulatetexture"
            local bumpmap2 = mat:GetTexture "$bumpmap2"
            local detail = mat:GetTexture "$detail"
            local numTextures = 1
                + (bt3str and 1 or 0)
                + (bt4str and 1 or 0)
                + (bmtstr and 1 or 0)
                + (bumpstr2 and 1 or 0)
                + (detailstr and 1 or 0)
            if numTextures > 0 then
                local meanWidth = (bt2:Width()
                    + (bt3str and bt3:Width() or 0)
                    + (bt4str and bt4:Width() or 0)
                    + (bmtstr and bmt:Width() or 0)
                    + (bumpstr2 and bumpmap2:Width() or 0)
                    + (detailstr and detail:Width() or 0)) / numTextures
                local meanHeight = (bt2:Height()
                    + (bt3str and bt3:Height() or 0)
                    + (bt4str and bt4:Height() or 0)
                    + (bmtstr and bmt:Height() or 0)
                    + (bumpstr2 and bumpmap2:Height() or 0)
                    + (detailstr and detail:Height() or 0)) / numTextures
                local size = math.min((meanWidth + meanHeight) / 2, 2048)
                local columns = bt3str and 3 or 2
                local name = string.format("splashsweps_texture_%s", mat:GetName())
                local rt = GetRenderTargetEx(name, size * columns, size * 2,
                    RT_SIZE_NO_CHANGE, MATERIAL_RT_DEPTH_NONE,
                    256 + 512 + 32768, 0, IMAGE_FORMAT_DEFAULT)
                timer.Simple(0, function()
                    render.PushRenderTarget(rt)
                    cam.Start2D()
                    surface.SetMaterial(copy)
                    copy:SetTexture("$basetexture", detailstr or "grey")
                    surface.DrawTexturedRect(0, 0, size, size)
                    copy:SetTexture("$basetexture", bt2str)
                    surface.DrawTexturedRect(size, 0, size, size)
                    copy:SetTexture("$basetexture", bmtstr or "grey")
                    surface.DrawTexturedRect(0, size, size, size)
                    copy:SetTexture("$basetexture", bumpstr2 or bumpstr or "null-bumpmap")
                    surface.DrawTexturedRect(size, size, size, size)
                    if bt3str then
                        copy:SetTexture("$basetexture", bt3str)
                        surface.DrawTexturedRect(size * 2, 0, size, size)
                        copy:SetTexture("$basetexture", bt4str or "grey")
                        surface.DrawTexturedRect(size * 2, size, size, size)
                    end
                    cam.End2D()
                    render.PopRenderTarget()
                end)
                m.Detail = name
            end
        end
    end
end
