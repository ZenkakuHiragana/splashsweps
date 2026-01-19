
---@class ss
local ss = SplashSWEPs
if not ss then return end

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
    ADDITIVE       = "splashsweps_additive",
    MULTIPLICATIVE = "splashsweps_multiplicative",
    PBR            = "splashsweps_pbr",
    DETAILS        = "splashsweps_details",
}
local COMMON_FLAGS = bit.bor(
    TEXTUREFLAGS.NOMIP,
    TEXTUREFLAGS.NOLOD,
    TEXTUREFLAGS.ALL_MIPS,
    TEXTUREFLAGS.RENDERTARGET,
    TEXTUREFLAGS.NODEPTHBUFFER)
local RTFLAGS = {
    ADDITIVE = COMMON_FLAGS,
    MULTIPLICATIVE = COMMON_FLAGS,
    PBR = COMMON_FLAGS,
    DETAILS = COMMON_FLAGS,
}

if not ss.RenderTarget then
    ---@class ss.RenderTarget
    ss.RenderTarget = {
        ---Render targets for static part of the world.
        StaticTextures = {
            Additive       = nil, ---@type ITexture
            Multiplicative = nil, ---@type ITexture
            PseudoPBR      = nil, ---@type ITexture
            Details        = nil, ---@type ITexture
        },
        ---List of render target resolutions available.
        Resolutions = {
            2048,
            4096,
            -- 5792,
            -- 8192,
            -- 11586,
            -- 16384,
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
    local rtIndex = #ss.RenderTarget.Resolutions
    local rtSize = rt.Resolutions[rtIndex]
    rt.StaticTextures.Additive = GetRenderTargetEx(
        RTNAMES.ADDITIVE,
        rtSize, rtSize,
        RT_SIZE_LITERAL,
        MATERIAL_RT_DEPTH_NONE,
        RTFLAGS.ADDITIVE,
        CREATERENDERTARGETFLAGS_HDR,
        IMAGE_FORMAT_RGBA8888)
    rt.StaticTextures.Multiplicative = GetRenderTargetEx(
        RTNAMES.MULTIPLICATIVE,
        rtSize, rtSize,
        RT_SIZE_LITERAL,
        MATERIAL_RT_DEPTH_NONE,
        RTFLAGS.MULTIPLICATIVE,
        CREATERENDERTARGETFLAGS_HDR,
        IMAGE_FORMAT_RGBA8888)
    rt.StaticTextures.PseudoPBR = GetRenderTargetEx(
        RTNAMES.PBR,
        rtSize, rtSize,
        RT_SIZE_LITERAL,
        MATERIAL_RT_DEPTH_NONE,
        RTFLAGS.PBR,
        CREATERENDERTARGETFLAGS_HDR,
        IMAGE_FORMAT_RGBA8888)
    rt.StaticTextures.Details = GetRenderTargetEx(
        RTNAMES.DETAILS,
        rtSize, rtSize,
        RT_SIZE_LITERAL,
        MATERIAL_RT_DEPTH_NONE,
        RTFLAGS.DETAILS,
        CREATERENDERTARGETFLAGS_HDR,
        IMAGE_FORMAT_RGBA8888)
    rt.HammerUnitsToPixels = rt.HammerUnitsToUV * rtSize
    ss.ClearAllInk()
end
