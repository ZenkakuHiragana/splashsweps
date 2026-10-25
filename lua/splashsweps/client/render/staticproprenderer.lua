
-- Draws the ink of the static props the engine draws in each view.

---@class ss
local ss = SplashSWEPs
local RenderTargets = ss.import "splashsweps/client/render/rendertargets"

---@class ss.StaticPropRendererModule
local StaticPropRenderer = ss.module "splashsweps/client/render/staticproprenderer"

---@class ss.StaticPropRendererModule.State
---@field Queue     ss.PaintableCSEnt[] Static props the engine draws in the current view, whose ink is drawn with the ink meshes.
---@field IsDrawing boolean             True while the ink renderer draws the queued static props.
local state = ss.state("splashsweps/client/render/staticproprenderer", {
    Queue = {},
    IsDrawing = false,
}) ---@type ss.StaticPropRendererModule.State

local StaticPropLightMaterial = Material "splashsweps/shaders/phong"
local StaticPropFlashlightMaterial = Material "splashsweps/shaders/vertexlitgeneric"
local StaticPropFlashlightMaterialMSAA = Material "splashsweps/shaders/vertexlitgeneric_msaa"
local CVarDrawStaticProps = GetConVar "r_drawstaticprops"
local MIN_DRAW_RADIUS = 0.01 * 0.01 -- Squared minimum draw radius for static props relative to ScrH()

local StaticPropView = Matrix()

---RenderOverride of the static props. The engine draws the props themselves, and these models draw the ink.
---In each view:
---
---  PreDrawOpaqueRenderables        clears the queue
---  StaticPropRenderer.Queue        queues the prop unless it is faded out or too small on the screen
---  PreDrawTranslucentRenderables   draws the queue after the ink meshes, in the flashlight and MRT passes
---  `-- prop:DrawModel()            calls StaticPropRenderer.Queue again, which draws the model this time
---
---The queue is left undrawn wherever the hook returns before drawing the ink meshes, such as the water reflection.
---@param self ss.PaintableCSEnt
---@param flags Enum.STUDIO
function StaticPropRenderer.Queue(self, flags)
    if state.IsDrawing then
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
    state.Queue[#state.Queue + 1] = self
end

---Draws the flashlight light on the queued static props into StaticPropFlashlight.
---Call it in render.RenderFlashlights with StaticPropFlashlight pushed.
---
---  depth buffer                  depth test                     transparent parts of alpha test
---  ----------------------------  -----------------------------  -------------------------------
---  the frame's                   equal (by $alphatest)          not lit
---  from flashlight_init (MSAA)   less or equal                  lit
function StaticPropRenderer.DrawFlashlight()
    state.IsDrawing = true
    render.MaterialOverride(RenderTargets.IsStaticPropFlashlightSharingDepth()
        and StaticPropFlashlightMaterial or StaticPropFlashlightMaterialMSAA)
    for _, prop in ipairs(state.Queue) do
        prop:DrawModel(prop.QueuedFlags)
    end
    render.MaterialOverride()
    state.IsDrawing = false
end

---Draws the ink of the queued static props.
function StaticPropRenderer.DrawInk()
    state.IsDrawing = true
    for _, prop in ipairs(state.Queue) do
        -- VertexLitGeneric leaves the lighting of the prop in the shader constants the ink material reads.
        render.MaterialOverride(StaticPropLightMaterial)
        prop:DrawModel(prop.QueuedFlags)
        render.MaterialOverride()
        prop:DrawModel(prop.QueuedFlags)
    end
    state.IsDrawing = false
end

---Returns true if any static prop is queued in the current view.
---@return boolean
function StaticPropRenderer.HasQueued()
    return #state.Queue > 0
end

-- See StaticPropRenderer.Queue
hook.Add("PreDrawOpaqueRenderables", "SplashSWEPs: Reset static prop queue", function()
    for k in pairs(state.Queue) do state.Queue[k] = nil end
end)

return StaticPropRenderer
