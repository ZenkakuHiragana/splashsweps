
-- Draws paints into the ink map, the render target the ink meshes read the painted ink from.

---@class ss
local ss = SplashSWEPs
local DetailAtlas      = ss.import "splashsweps/client/ink/detailatlas"
local InkShape         = ss.import "splashsweps/shared/inkshape"
local InkType          = ss.import "splashsweps/shared/inktype"
local PaintableGrid    = ss.import "splashsweps/shared/paint/paintablegrid"
local PaintableSurface = ss.import "splashsweps/shared/paint/paintablesurface"
local RenderTargets    = ss.import "splashsweps/client/render/rendertargets"
local TypeAtlas        = ss.import "splashsweps/client/ink/typeatlas"

---@class ss.InkMapModule
local InkMap = ss.module "splashsweps/client/render/inkmap"

---A paint waiting to be drawn into the ink map.
---@class ss.InkMap.Paint
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

---@class ss.InkMapModule.State
---@field Queue ss.InkMap.Paint[] Paints to draw in the next frame.
local state = ss.state("splashsweps/client/render/inkmap", { Queue = {} }) ---@type ss.InkMapModule.State

local NUM_REGION, NUM_VERTEX = 4, 4
local INDICES_REGION = 2 -- Region of the ink type IDs, the only one the boundary band of a paint updates
local NUM_TEXCOORDS = 7
local SIZEOF_POS_NORMAL_COLOR = 4 * (3 + 3 + 1) -- pos: float3, normal: float3, color: uint8 * 4
local SIZEOF_TEXCOORDS = NUM_TEXCOORDS * 4 * 4  -- texcoord: float4
local SIZEOF_VERTEX = math.ceil((SIZEOF_POS_NORMAL_COLOR + SIZEOF_TEXCOORDS) / 16) * 16 -- float4 padding
local MAX_VERTEX_SIZE_KB = (1024 + 512) * 1024 -- Maximum size of dynamic mesh hardcoded in Source
local MAX_QUADS = math.floor(MAX_VERTEX_SIZE_KB / (NUM_VERTEX * SIZEOF_VERTEX))
local InkDrawMaterial = Material "splashsweps/shaders/drawink"

---Queues a paint onto a surface to draw it into the ink map.
---@param surf   ss.PaintableSurface The surface to paint.
---@param pos    Vector  The origin in the same coordinate system as the surface.
---@param ang    Angle   The normal and rotation in the same coordinate system as the surface.
---@param scale  Vector  Scale along the angles which is limited to 510 Hammer units because of network optimization.
---@param shape  integer The internal index of shape to paint.
---@param typeid integer The internal index of ink type.
function InkMap.Push(surf, pos, ang, scale, shape, typeid)
    local inkshape = InkShape.Shapes[shape]
    local inktype = InkType.Types[typeid]
    if not (inkshape and inktype) then return end
    state.Queue[#state.Queue + 1] = {
        pos    = pos,
        ang    = ang,
        scale  = scale,
        base   = TypeAtlas.GetBaseUV(typeid),
        shape  = TypeAtlas.GetShapeUV(shape),
        tint   = TypeAtlas.GetTintUV(typeid),
        typeid = typeid,
        detail = DetailAtlas.GetBlendMode(typeid),
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

---Writes the layout of the detail atlas into the material drawing paints, which reads the data rows of ink types.
function InkMap.Setup()
    DetailAtlas.WriteLayout(InkDrawMaterial)
end

---Clears all painted ink in the map.
function InkMap.ClearAll()
    for _, s in ipairs(PaintableSurface.Surfaces) do PaintableGrid.Clear(s) end
    local rt = RenderTargets.InkMaps.InkMap
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
---@param q         ss.InkMap.Paint
---@param region    integer Ink map region index
---@param band      integer 255 for the boundary band outside the shape edge, 0 for the paint itself
---@param quadIndex integer Zero-based index of this quad among all quads of the batch
---@param numQuads  integer Number of quads in the batch
---@param hammerUnitsToUV number Conversion multiplier from hammer units to UV coordinates of the ink map
---@return integer nextQuadIndex
local function AddQuad(q, region, band, quadIndex, numQuads, hammerUnitsToUV)
    if quadIndex % MAX_QUADS == 0 then
        if quadIndex > 0 then mesh_End() end
        mesh_Begin(MATERIAL_QUADS, min(numQuads - quadIndex, MAX_QUADS))
    end

    -- 0b0000RRCC, RR = Region, CC = Corner
    for i = region * NUM_VERTEX * 16, (region * NUM_VERTEX + NUM_VERTEX - 1) * 16, 16 do
        mesh_Color(band, i, q.typeid, q.detail)
        mesh_Normal(q.scale)
        mesh_Position(q.pos)
        mesh_TexCoord(0, q.ang.p, q.ang.y, q.ang.r, hammerUnitsToUV)
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
    local queue = state.Queue
    if #queue == 0 then return end
    local numQuads = #queue * (NUM_REGION + 1) -- The boundary band and the regions of each paint
    local quadIndex = 0
    local hammerUnitsToUV = RenderTargets.GetHammerUnitsToUV()
    render_PushRenderTarget(RenderTargets.InkMaps.InkMap)
    render_CopyRenderTarget(RenderTargets.InkMaps.InkMap2)
    render_SetMaterial(InkDrawMaterial)
    -- Quads are drawn in the queue order without depth, and the later ones overwrite the earlier ones.
    -- A band writes back the IDs of the batch-start snapshot, so every band goes before every paint.
    for _, q in ipairs(queue) do
        quadIndex = AddQuad(q, INDICES_REGION, 255, quadIndex, numQuads, hammerUnitsToUV)
    end
    for _, q in ipairs(queue) do
        for region = 0, NUM_REGION - 1 do
            quadIndex = AddQuad(q, region, 0, quadIndex, numQuads, hammerUnitsToUV)
        end
    end
    mesh_End()
    render_PopRenderTarget()
    for k in pairs(queue) do queue[k] = nil end
end)

return InkMap
