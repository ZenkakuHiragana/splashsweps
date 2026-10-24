
---@class ss
local ss = SplashSWEPs
if not ss then return end

local InkSSRComposeMaterial = Material "splashsweps/shaders/inkssr_compose"
local InkSSRBlurResolutionMul = InkSSRComposeMaterial:GetFloat "$c0_x"
local CREATERENDERTARGETFLAGS_NONE = 0
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
    INKMAP      = "splashsweps_inkmap",
    INKMAP2     = "splashsweps_inkmap2",
    SCENE       = "splashsweps_sceneandflashlight",
    PROPLIGHT   = "splashsweps_staticpropflashlight",
    PROPLIGHT_MSAA = "splashsweps_staticpropflashlight_msaa",
    GCOLOR      = "splashsweps_gbuf_inkcolor",
    GCOLOR_BLUR = "splashsweps_gbuf_inkcolor_blur",
    GNORMAL     = "splashsweps_gbuf_inknormals",
    SSR_RESULT  = "splashsweps_ssr_result",
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

if not ss.RenderTarget then
    ---@class ss.RenderTarget
    ss.RenderTarget = {
        ---Square image area above the ink-material data rows.
        DetailsImageSize = 0, ---@type number
        ---Number of columns in the detail image grid.
        DetailGridColumns = 0, ---@type number
        ---Render targets for static part of the world.
        StaticTextures = {
            InkMap  = nil, ---@type ITexture
            InkMap2 = nil, ---@type ITexture
            Albedo  = nil, ---@type ITexture
            Tint    = nil, ---@type ITexture
            Details = nil, ---@type ITexture
        },
        ---One-frame textures for forward MRT shading and SSR composition.
        ---@class ss.RenderTarget.FrameTextures
        ---@field SceneAndFlashlight ITexture? Twice the screen height. Upper half: frame buffer copy + alpha channel as depth buffer. Lower half: flashlight light on the world ink meshes.
        ---@field StaticPropFlashlight ITexture? Flashlight light on the static props. See DrawStaticPropsFlashlight in inkrenderer.lua.
        ---@field SSRResult          ITexture? Half-resolution (hit UV * confidence, blur width in pixels at roughness = 100% * confidence, confidence).
        ---@field InkColor           ITexture? Background or painted color without SSR; alpha is the painted-surface mask.
        ---@field InkColorBlur       ITexture? Quarter-resolution copy of InkColor for reflections on rough surfaces.
        ---@field InkNormals         ITexture? G-Buffer to store octahedral encoded ink normals.
        ---@field Reflection         ITexture? G-Buffer to store precomputed reflection weights and ink height.
        ---@field Envmap             ITexture? G-Buffer to store precomputed $envmap sample and ink roughness.
        FrameTextures = {
            SceneAndFlashlight = nil,
            StaticPropFlashlight = nil,
            SSRResult          = nil,
            InkColor           = nil,
            InkColorBlur       = nil,
            InkNormals         = nil,
            Reflection         = nil,
            Envmap             = nil,
        },
        ---List of render target resolutions available.
        Resolutions = {
            4096,
            8192,
            16384,
        },
        ---Conversion multiplier from hammer units to UV coordinates.
        HammerUnitsToUV = 1,
        ---Conversion multiplier from hammer units to texture pixels (= UV x render target resolution).
        HammerUnitsToPixels = 1,
        ---True if StaticPropFlashlight shares the depth buffer of the frame, false with MSAA.
        StaticPropFlashlightSharesDepth = true,
    }
end

---Reserves render targets.
function ss.SetupRenderTargets()
    local rt = ss.RenderTarget
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

    local rtIndex = #ss.RenderTarget.Resolutions
    local rtSize = rt.Resolutions[rtIndex]
    rt.StaticTextures.InkMap = GetRenderTargetEx(
        RTNAMES.INKMAP,
        rtSize, rtSize,
        RT_SIZE_LITERAL,
        MATERIAL_RT_DEPTH_SEPARATE,
        RTFLAGS.INKMAP,
        CREATERENDERTARGETFLAGS_NONE,
        IMAGE_FORMAT_RGBA8888)
    rt.StaticTextures.InkMap2 = GetRenderTargetEx(
        RTNAMES.INKMAP2,
        rtSize, rtSize,
        RT_SIZE_LITERAL,
        MATERIAL_RT_DEPTH_NONE,
        RTFLAGS.INKMAP,
        CREATERENDERTARGETFLAGS_NONE,
        IMAGE_FORMAT_RGBA8888)
    rt.HammerUnitsToPixels = rt.HammerUnitsToUV * rtSize
    rt.FrameTextures.SceneAndFlashlight = GetRenderTargetEx(RTNAMES.SCENE,
        ScrW(), ScrH() * 2,
        RT_SIZE_LITERAL,
        MATERIAL_RT_DEPTH_SEPARATE,
        RTFLAGS.FRAME,
        CREATERENDERTARGETFLAGS_NONE,
        IMAGE_FORMAT_RGBA16161616F)
    -- MATERIAL_RT_DEPTH_SHARED gets its own depth buffer with MSAA. Changing MSAA needs a map reload.
    rt.StaticPropFlashlightSharesDepth = GetConVar "mat_antialias":GetInt() <= 1
    if rt.StaticPropFlashlightSharesDepth then
        rt.FrameTextures.StaticPropFlashlight = GetGBuffer(RTNAMES.PROPLIGHT, MATERIAL_RT_DEPTH_SHARED)
    else
        rt.FrameTextures.StaticPropFlashlight = GetGBuffer(RTNAMES.PROPLIGHT_MSAA, MATERIAL_RT_DEPTH_SEPARATE)
    end
    rt.FrameTextures.SSRResult    = GetGBuffer(RTNAMES.SSR_RESULT,  MATERIAL_RT_DEPTH_NONE, 0.5)
    rt.FrameTextures.InkColor     = GetGBuffer(RTNAMES.GCOLOR,      MATERIAL_RT_DEPTH_SEPARATE)
    rt.FrameTextures.InkColorBlur = GetGBuffer(RTNAMES.GCOLOR_BLUR, MATERIAL_RT_DEPTH_NONE, InkSSRBlurResolutionMul)
    rt.FrameTextures.InkNormals   = GetGBuffer(RTNAMES.GNORMAL,     MATERIAL_RT_DEPTH_NONE)
    rt.FrameTextures.Reflection   = render.GetSuperFPTex()
    rt.FrameTextures.Envmap       = render.GetSuperFPTex2()
    ss.ClearAllInk()
end
