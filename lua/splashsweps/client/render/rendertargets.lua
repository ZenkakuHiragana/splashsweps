
-- Render targets of the ink map and the frame, created when the map cache is loaded.

---@class ss
local ss = SplashSWEPs

---@class ss.RenderTargetsModule
local RenderTargets = ss.module "splashsweps/client/render/rendertargets"

local InkSSRComposeMaterial = Material "splashsweps/shaders/inkssr_compose"
local InkSSRBlurResolutionMul = InkSSRComposeMaterial:GetFloat "$c0_x"
local CREATERENDERTARGETFLAGS_NONE = 0
local INK_MAP_SIZE = 16384 -- Width and height of the ink map in pixels
local TEXTUREFLAGS = {
    CLAMPS            = 4,
    NOMIP             = 256,
    UNUSED_80000000   = 2147483648,
    UNUSED_40000000   = 1073741824,
    CLAMPU            = 33554432,
    BORDER            = 536870912,
    UNUSED_10000000   = 268435456,
    ENVMAP            = 16384,
    SINGLECOPY        = 262144,
    ANISOTROPIC       = 16,
    VERTEXTEXTURE     = 67108864,
    UNUSED_00400000   = 4194304,
    NODEBUGOVERRIDE   = 131072,
    UNUSED_01000000   = 16777216,
    UNUSED_00200000   = 2097152,
    EIGHTBITALPHA     = 8192,
    PWL_CORRECTED     = 64,
    NOLOD             = 512,
    ALL_MIPS          = 1024,
    RENDERTARGET      = 32768,
    UNUSED_00080000   = 524288,
    NODEPTHBUFFER     = 8388608,
    POINTSAMPLE       = 1,
    DEPTHRENDERTARGET = 65536,
    HINT_DXT5         = 32,
    ONEBITALPHA       = 4096,
    IMMEDIATE_CLEANUP = 1048576,
    NORMAL            = 128,
    CLAMPT            = 8,
    TRILINEAR         = 2,
    PROCEDURAL        = 2048,
    SSBUMP            = 134217728,
}
local RTNAMES = {
    INKMAP          = "splashsweps_inkmap",
    INKMAP_SNAPSHOT = "splashsweps_inkmap_snapshot",
    SCENE           = "splashsweps_sceneandflashlight",
    PROPLIGHT       = "splashsweps_staticpropflashlight",
    PROPLIGHT_MSAA  = "splashsweps_staticpropflashlight_msaa",
    GCOLOR          = "splashsweps_gbuf_inkcolor",
    GCOLOR_BLUR     = "splashsweps_gbuf_inkcolor_blur",
    GNORMAL         = "splashsweps_gbuf_inknormals",
    SSR_RESULT      = "splashsweps_ssr_result",
}
local COMMON_FLAGS = bit.bor(
    TEXTUREFLAGS.NOMIP,
    TEXTUREFLAGS.NOLOD,
    TEXTUREFLAGS.RENDERTARGET)
local RTFLAGS = {
    -- Wish this prevents sRGB correction
    INKMAP = bit.bor(COMMON_FLAGS, TEXTUREFLAGS.NORMAL),
    FRAME  = bit.bor(COMMON_FLAGS, TEXTUREFLAGS.CLAMPS, TEXTUREFLAGS.CLAMPT, TEXTUREFLAGS.NODEBUGOVERRIDE),
}

---Render targets of the ink map.
---@class ss.RenderTargets.InkMaps
---@field InkMap  ITexture Where the paints are drawn.
---@field InkMapSnapshot ITexture Copy of InkMap taken before drawing a batch of paints into InkMap.

---One-frame textures for forward MRT shading and SSR composition.
---@class ss.RenderTargets.FrameTextures
---@field SceneAndFlashlight   ITexture? Twice the screen height. Upper half: frame buffer copy + alpha channel as depth buffer. Lower half: flashlight light on the world ink meshes.
---@field StaticPropFlashlight ITexture? Flashlight light on the static props. See StaticPropRenderer.DrawFlashlight.
---@field SSRResult            ITexture? Half-resolution (hit UV * confidence, blur width in pixels at roughness = 100% * confidence, confidence).
---@field InkColor             ITexture? Background or painted color without SSR; alpha is the painted-surface mask.
---@field InkColorBlur         ITexture? Quarter-resolution copy of InkColor for reflections on rough surfaces.
---@field InkNormals           ITexture? G-Buffer to store octahedral encoded ink normals.
---@field Reflection           ITexture? G-Buffer to store precomputed reflection weights and ink height.
---@field Envmap               ITexture? G-Buffer to store precomputed $envmap sample and ink roughness.

---@class ss.RenderTargetsModule.State
---@field InkMaps                         ss.RenderTargets.InkMaps
---@field Frame                           ss.RenderTargets.FrameTextures
---@field HammerUnitsToUV                 number  Conversion multiplier from hammer units to UV coordinates of the ink map.
---@field StaticPropFlashlightSharesDepth boolean True if StaticPropFlashlight shares the depth buffer of the frame, false with MSAA.
local state = ss.state("splashsweps/client/render/rendertargets", {
    InkMaps = {},
    Frame = {},
    HammerUnitsToUV = 1,
    StaticPropFlashlightSharesDepth = true,
})

---Render targets of the ink map.
RenderTargets.InkMaps = state.InkMaps

---One-frame textures for forward MRT shading and SSR composition.
RenderTargets.Frame = state.Frame

---Returns the conversion multiplier from hammer units to UV coordinates of the ink map.
---@return number
function RenderTargets.GetHammerUnitsToUV()
    return state.HammerUnitsToUV
end

---Returns true if StaticPropFlashlight shares the depth buffer of the frame, false with MSAA.
---@return boolean
function RenderTargets.IsStaticPropFlashlightSharingDepth()
    return state.StaticPropFlashlightSharesDepth
end

---Reserves render targets.
---@param hammerUnitsToUV number Conversion multiplier from hammer units to UV coordinates of the ink map.
function RenderTargets.Setup(hammerUnitsToUV)
    state.HammerUnitsToUV = hammerUnitsToUV
    local function GetGBuffer(name, depthMode, scale)
        scale = scale or 1
        return GetRenderTargetEx(name,
            ScrW() * scale, ScrH() * scale,
            RT_SIZE_LITERAL,
            depthMode,
            RTFLAGS.FRAME,
            CREATERENDERTARGETFLAGS_NONE,
            IMAGE_FORMAT_RGBA16161616F)
    end

    state.InkMaps.InkMap = GetRenderTargetEx(
        RTNAMES.INKMAP,
        INK_MAP_SIZE, INK_MAP_SIZE,
        RT_SIZE_LITERAL,
        MATERIAL_RT_DEPTH_SEPARATE,
        RTFLAGS.INKMAP,
        CREATERENDERTARGETFLAGS_NONE,
        IMAGE_FORMAT_RGBA8888)
    state.InkMaps.InkMapSnapshot = GetRenderTargetEx(
        RTNAMES.INKMAP_SNAPSHOT,
        INK_MAP_SIZE, INK_MAP_SIZE,
        RT_SIZE_LITERAL,
        MATERIAL_RT_DEPTH_NONE,
        RTFLAGS.INKMAP,
        CREATERENDERTARGETFLAGS_NONE,
        IMAGE_FORMAT_RGBA8888)
    state.Frame.SceneAndFlashlight = GetRenderTargetEx(RTNAMES.SCENE,
        ScrW(), ScrH() * 2,
        RT_SIZE_LITERAL,
        MATERIAL_RT_DEPTH_SEPARATE,
        RTFLAGS.FRAME,
        CREATERENDERTARGETFLAGS_NONE,
        IMAGE_FORMAT_RGBA16161616F)
    -- MATERIAL_RT_DEPTH_SHARED gets its own depth buffer with MSAA. Changing MSAA needs a map reload.
    state.StaticPropFlashlightSharesDepth = GetConVar "mat_antialias":GetInt() <= 1
    if state.StaticPropFlashlightSharesDepth then
        state.Frame.StaticPropFlashlight = GetGBuffer(RTNAMES.PROPLIGHT, MATERIAL_RT_DEPTH_SHARED)
    else
        state.Frame.StaticPropFlashlight = GetGBuffer(RTNAMES.PROPLIGHT_MSAA, MATERIAL_RT_DEPTH_SEPARATE)
    end
    state.Frame.SSRResult    = GetGBuffer(RTNAMES.SSR_RESULT,  MATERIAL_RT_DEPTH_NONE, 0.5)
    state.Frame.InkColor     = GetGBuffer(RTNAMES.GCOLOR,      MATERIAL_RT_DEPTH_SEPARATE)
    state.Frame.InkColorBlur = GetGBuffer(RTNAMES.GCOLOR_BLUR, MATERIAL_RT_DEPTH_NONE, InkSSRBlurResolutionMul)
    state.Frame.InkNormals   = GetGBuffer(RTNAMES.GNORMAL,     MATERIAL_RT_DEPTH_NONE)
    state.Frame.Reflection   = render.GetSuperFPTex()
    state.Frame.Envmap       = render.GetSuperFPTex2()
end

return RenderTargets
