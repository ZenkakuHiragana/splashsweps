
---@class ss
local ss = SplashSWEPs
if not ss then return end

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
    INKMAP     = "splashsweps_inkmap",
    INKMAP2    = "splashsweps_inkmap2",
    ALBEDO     = "splashsweps_albedo",
    TINT       = "splashsweps_tint",
    GCOLOR     = "splashsweps_gbuf_inkcolor",
    GNORMAL    = "splashsweps_gbuf_inknormals",
    GREFLECT   = "splashsweps_gbuf_reflection",
    GENVMAP    = "splashsweps_gbuf_envmap",
    SSR_RESULT = "splashsweps_ssr_result",
    SSR_FILTER = "splashsweps_ssr_filter",
}
local COMMON_FLAGS = bit.bor(
    TEXTUREFLAGS.NOMIP,
    TEXTUREFLAGS.NOLOD,
    TEXTUREFLAGS.RENDERTARGET)
local RTFLAGS = {
    -- Wish this prevents sRGB correction
    INKMAP = bit.bor(COMMON_FLAGS, TEXTUREFLAGS.NORMAL),
    ALBEDO = bit.bor(COMMON_FLAGS, TEXTUREFLAGS.NODEPTHBUFFER),
    TINT   = bit.bor(COMMON_FLAGS, TEXTUREFLAGS.NODEPTHBUFFER),
    FRAME  = bit.bor(COMMON_FLAGS, TEXTUREFLAGS.CLAMPS, TEXTUREFLAGS.CLAMPT, TEXTUREFLAGS.NODEBUGOVERRIDE),
}

if not ss.RenderTarget then
    ---@class ss.RenderTarget
    ss.RenderTarget = {
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
        ---@field SceneColorDepth ITexture? Frame buffer copy + alpha channel as depth buffer
        ---@field SSRResult  ITexture?
        ---@field SSRFilter  ITexture?
        ---@field InkColor   ITexture? G-Buffer to store final painted ink color without SSR component.
        ---@field InkNormals ITexture? G-Buffer to store octahedral encoded ink normals.
        ---@field Reflection ITexture? G-Buffer to store precomputed reflection weights and ink height.
        ---@field Envmap     ITexture? G-Buffer to store precomputed $envmap sample and ink roughness.
        FrameTextures = {
            SceneColorDepth = nil,
            SSRResult  = nil,
            SSRFilter  = nil,
            InkColor   = nil,
            InkNormals = nil,
            Reflection = nil,
            Envmap     = nil,
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
    rtSize = rtSize / 32
    rt.StaticTextures.Albedo = GetRenderTargetEx(
        RTNAMES.ALBEDO,
        rtSize, rtSize,
        RT_SIZE_LITERAL,
        MATERIAL_RT_DEPTH_NONE,
        RTFLAGS.ALBEDO,
        CREATERENDERTARGETFLAGS_NONE,
        IMAGE_FORMAT_RGBA8888)
    rt.StaticTextures.Tint = GetRenderTargetEx(
        RTNAMES.TINT,
        rtSize, rtSize,
        RT_SIZE_LITERAL,
        MATERIAL_RT_DEPTH_NONE,
        RTFLAGS.TINT,
        CREATERENDERTARGETFLAGS_NONE,
        IMAGE_FORMAT_RGBA8888)
    rt.FrameTextures.SceneColorDepth = render.GetSuperFPTex()
    rt.FrameTextures.SSRResult  = GetGBuffer(RTNAMES.SSR_RESULT, MATERIAL_RT_DEPTH_NONE, 0.5)
    rt.FrameTextures.SSRFilter  = GetGBuffer(RTNAMES.SSR_FILTER, MATERIAL_RT_DEPTH_NONE, 0.5)
    rt.FrameTextures.InkColor   = GetGBuffer(RTNAMES.GCOLOR,     MATERIAL_RT_DEPTH_SEPARATE)
    rt.FrameTextures.InkNormals = GetGBuffer(RTNAMES.GNORMAL,    MATERIAL_RT_DEPTH_NONE)
    rt.FrameTextures.Reflection = GetGBuffer(RTNAMES.GREFLECT,   MATERIAL_RT_DEPTH_NONE)
    rt.FrameTextures.Envmap     = GetGBuffer(RTNAMES.GENVMAP,    MATERIAL_RT_DEPTH_NONE)
    ss.ClearAllInk()
end
