
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
    ALBEDO = "splashsweps_basetexture",
    NORMAL = "splashsweps_bumpmap",
}
local RTFLAGS = {
    ALBEDO = bit.bor(
        TEXTUREFLAGS.NOMIP,
        TEXTUREFLAGS.NOLOD,
        TEXTUREFLAGS.ALL_MIPS,
        TEXTUREFLAGS.RENDERTARGET,
        TEXTUREFLAGS.NODEPTHBUFFER
    ),
    NORMAL = bit.bor(
        TEXTUREFLAGS.NORMAL,
        TEXTUREFLAGS.NOMIP,
        TEXTUREFLAGS.NOLOD,
        TEXTUREFLAGS.ALL_MIPS,
        TEXTUREFLAGS.RENDERTARGET,
        TEXTUREFLAGS.NODEPTHBUFFER
    ),
}

if not ss.RenderTarget then
    ---@class ss.RenderTarget
    ss.RenderTarget = {
        ---Render targets for static part of the world.
        StaticTextures = {
            Albedo = nil, ---@type ITexture
            Normal = nil, ---@type ITexture
            Lightmap = nil, ---@type ITexture
        },
        ---List of render target resolutions available.
        Resolutions = {
            2048,
            4096,
            5792,
            8192,
            11586,
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
    local rtIndex = #ss.RenderTarget.Resolutions
    local rtSize = rt.Resolutions[rtIndex]
    rt.StaticTextures.Albedo = GetRenderTargetEx(
        RTNAMES.ALBEDO,
        rtSize, rtSize,
        RT_SIZE_LITERAL,
        MATERIAL_RT_DEPTH_NONE,
        RTFLAGS.ALBEDO,
        CREATERENDERTARGETFLAGS_HDR,
        IMAGE_FORMAT_RGBA8888)
    rt.StaticTextures.Normal = GetRenderTargetEx(
        RTNAMES.NORMAL,
        rtSize, rtSize,
        RT_SIZE_LITERAL,
        MATERIAL_RT_DEPTH_NONE,
        RTFLAGS.NORMAL,
        CREATERENDERTARGETFLAGS_HDR,
        IMAGE_FORMAT_RGBA8888)
    -- ss.InkMeshMaterial:SetTexture("$basetexture", rt.StaticTextures.Albedo)
    -- ss.InkMeshMaterial:SetTexture("$bumpmap", rt.StaticTextures.Normal)
    -- ss.InkMeshMaterial:SetUndefined("$detail") -- Unused for now
    rt.HammerUnitsToPixels = rt.HammerUnitsToUV * rtSize
    ss.ClearAllInk()
end

local copy = Material "pp/copy"

---Loads lightmap texture and places it.
---@param page integer Number of lightmap page
---@param width integer
---@param height integer
---@return ITexture
function ss.CreateLightmapRT(page, width, height)
    local ishdr = render.GetHDREnabled()
    local fmt = ishdr and "splashsweps_lightmap_hdr_%d_%s" or "splashsweps_lightmap_%d_%s"
    return GetRenderTargetEx(
        fmt:format(page, game.GetMap()),
        width, height,
        RT_SIZE_NO_CHANGE,
        MATERIAL_RT_DEPTH_NONE,
        RTFLAGS.ALBEDO,
        CREATERENDERTARGETFLAGS_HDR,
        ishdr and IMAGE_FORMAT_RGBA16161616F or IMAGE_FORMAT_RGBA8888)
end
