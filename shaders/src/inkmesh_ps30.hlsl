// Ink Mesh Pixel Shader for SplashSWEPs
// Based on LightmappedGeneric pixel shader with bumped lightmaps

#include "inkmesh_common.hlsl"

// Build configurations
#define g_EnvmapEnabled
#define g_PhongEnabled
#define g_RimEnabled

struct PS_INPUT {
    float4 screenPos : VPOS;
    VertexInfo vi;
};

struct PS_OUTPUT {
    float4 finalColorWithoutSSR : COLOR0;
    float4 encodedNormals       : COLOR1; // encoded normal vector of xy: painted ink, zw: the mesh
    float4 reflectionAndHeight  : COLOR2; // reflected ink color and ink height
    float4 envmapAndRoughness   : COLOR3; // envmap sample and ink roughness
};

struct UVs {
    float2 base;
    float2 bump;
    float2 detail;
    float2 lightmap;
    float2 screen;
    float  edgefade;
    float  blend;
    float  depth;
};

struct PsVertexInfo {
    float    baseTextureBlend;
    float2   screenUV;
    float3   worldPos;
    float4   clipPos;
    float2   minUV;
    float2   maxUV;
    float3   inkUV;
    float2   worldUV;
    float2   lightmapUV;
    float2   lightmapOffset;
    float3x3 worldTransform;
    float3x3 inkTransform;
    float3x3 lightmapTransform;
};

struct PseudoPBR {
    float metallic;
    float roughness;
    float specularScale;
    float refraction;
};

struct DetailParams {
    float blendMode;
    float blendScale;
    float bumpScale;
    float bumpBlendFactor;
};

struct MaterialParams {
    float  height;
    float  depth;
    float3 additive;
    float3 multiplicative;
    float3 normal;
    PseudoPBR pbr;
    DetailParams detail;
};

static const float ALBEDO_ALPHA_MIN   = 0.0625;
static const float DIFFUSE_MIN        = 0.0625; // Diffuse factor at metallic = 100%
static const float ENVMAP_SCALE_MIN   = 0.5;    // Envmap factor at roughness = 0%
static const float ENVMAP_SCALE_MAX   = 0.02;   // Envmap factor at roughness = 100%
static const float FRESNEL_MIN        = 0.04;   // Fresnel coefficient at metallic = 0%
static const float PHONG_EXPONENT_MIN = 1024;   // Exponent at roughness = 0%
static const float PHONG_EXPONENT_MAX = 32;     // Exponent at roughness = 100%
static const float RIM_EXPONENT_MIN   = 6;      // Exponent at roughness = 0%
static const float RIM_EXPONENT_MAX   = 2;      // Exponent at roughness = 100%
static const float RIM_ROUGHNESS_MIN  = 0.25;   // Rim lighting strength at roughness = 0%
static const float RIM_ROUGHNESS_MAX  = 0.0625; // Rim lighting strength at roughness = 100%
static const float RIM_METALIC_MIN    = 0.25;   // Rim lighting strength at metalic = 0%
static const float RIM_METALIC_MAX    = 0.0625; // Rim lighting strength at metalic = 100%
static const float RIMLIGHT_FADE_MIN  = 128.0;  // Rim lighting near distance
static const float RIMLIGHT_FADE_MAX  = 2048.0; // Rim lighting falloff distance
static const float RIMLIGHT_MAX_SCALE = 0.125;  // Rim lighting max scale
static const float3x3 BumpBasis = {
    // Bumped lightmap basis vectors (same as LightmappedGeneric) in tangent space
    {  0.81649661064147949,  0.0,                 0.57735025882720947 },
    { -0.40824833512306213,  0.70710676908493042, 0.57735025882720947 },
    { -0.40824833512306213, -0.70710676908493042, 0.57735025882720947 },
};

// Samplers
sampler InkMap          : register(s0);
sampler InkDataDetail   : register(s1);
sampler FrameBuffer     : register(s2);
sampler UnderlayAlbedo  : register(s3);
sampler UnderlayBumpmap : register(s4);
sampler TextureSampler5 : register(s5);
sampler Lightmap        : register(s6);
sampler Envmap          : register(s7);

static const sampler UnderlayDetail       = TextureSampler5; // g_HasUnderlayAtlas == 0.0
static const sampler UnderlayAtlas        = TextureSampler5; // g_HasUnderlayAtlas != 0.0
static const float3  g_SunDirection       = c0.xyz; // in world space
static const float   g_DetailBlendMode    = c0.w;
static const float   g_HammerUnitsToUV    = c1.x;   // = ss.RenderTarget.HammerUnitsToUV * 0.5
static const float   g_MaterialFlags      = c1.y;
static const float2  g_LightmapSize       = c2.xy;  // One over lightmap size
static const float2  g_DetailScale        = c2.zw;
static const float3  g_Color              = c3.rgb;
static const float2  g_RTSize             = s0Size; // One over ink map size
static const float2  g_FbSize             = s2Size; // One over frame buffer size
static const float2  g_UnderlayAlbedoSize = s3Size; // One over $basetexture size
static const float3  BaseTransform[2]     = { c11.xyz, c12.xyz };
static const float3  BumpTransform[2]     = { c13.xyz, c14.xyz };
static const float3  BlendTransform[2]    = { c15.xyz, c16.xyz };
static const float4  g_DetailTint         = { c11.w, c12.w, c13.w, 1.0 };
static const float   g_DetailBlendFactor  = c14.w;
static const float   g_TonemapScale       = HDRParams.x;
static const float   g_LightmapScale      = HDRParams.y;
static const float   g_EnvmapScale        = HDRParams.z;
static const float   g_GammaScale         = HDRParams.w; // = TonemapScale ^ (1 / 2.2)

// Bit flags:
//   0x01 .. has $bumpmap
//   0x02 .. is  WorldVertexTransition = has $basetexture2
//   0x04 .. is  Lightmapped_4WayBlend = has $basetexture3
//   0x08 .. has $blendmodulatetexture
//   0x10 .. is  simplified rendering for water reflection
static const bool g_HasBumpedLightmap    = fmod(floor(g_MaterialFlags / 1),  2.0) > 0.5;
static const bool g_HasUnderlayAtlas     = fmod(floor(g_MaterialFlags / 2),  2.0) > 0.5;
static const bool g_Is4WayBlend          = fmod(floor(g_MaterialFlags / 4),  2.0) > 0.5;
static const bool g_NeedsBlendModulation = fmod(floor(g_MaterialFlags / 8),  2.0) > 0.5;
static const bool g_Simplified           = fmod(floor(g_MaterialFlags / 16), 2.0) > 0.5;

PsVertexInfo DecomposeInput(const PS_INPUT i) {
    PsVertexInfo v;
    v.screenUV          = i.screenPos.xy * g_FbSize;
    v.worldPos          = i.vi.worldPos.xyz;
    v.clipPos           = i.vi.clipPos;
    v.minUV             = i.vi.surfaceClipRange.xy;
    v.maxUV             = i.vi.surfaceClipRange.zw;
    v.inkUV             = float3(i.vi.inkTangent_U.w, i.vi.inkBinormal_V.w, 0.0);
    v.worldUV           = float2(i.vi.worldTangent_U.w, i.vi.worldBinormal_V.w) * g_UnderlayAlbedoSize;
    v.lightmapUV        = float2(i.vi.lightmapTangent_U.w, i.vi.lightmapBinormal_V.w);
    v.lightmapOffset    = float2(i.vi.worldNormal_dU.w, 0.0);
    v.worldTransform    = float3x3(i.vi.worldTangent_U.xyz,    i.vi.worldBinormal_V.xyz,    i.vi.worldNormal_dU.xyz);
    v.inkTransform      = float3x3(i.vi.inkTangent_U.xyz,      i.vi.inkBinormal_V.xyz,      i.vi.worldNormal_dU.xyz);
    v.lightmapTransform = float3x3(i.vi.lightmapTangent_U.xyz, i.vi.lightmapBinormal_V.xyz, i.vi.worldNormal_dU.xyz);
    v.baseTextureBlend  = i.vi.worldPos.w;
    return v;
}

// Blinn-Phong specular calculation
float CalcBlinnPhongSpec(float3 normal, float3 lightDir, float3 viewDir, float exponent) {
    float3 halfVector = normalize(lightDir + viewDir);
    float nDotH = saturate(dot(normal, halfVector));
    return pow(nDotH, exponent);
}

// Schlick's approximation of Fresnel reflection
float3 CalcFresnel(float3 normal, float3 viewDirection, float3 f0) {
    float nDotV = saturate(dot(normal, viewDirection));
    return lerp(f0, float3(1.0, 1.0, 1.0), pow(1.0 - nDotV, 5.0));
}

// Estimate the screen-space pixel offset where the perspective-correct UV would
// become targetUV.  Around the current pixel, the rasterizer interpolates uv / w
// and 1 / w linearly in screen space:
//     U(x, y) = (uvOverW + d(uvOverW)/dx * x + d(uvOverW)/dy * y)
//             / (invW    + d(invW)   /dx * x + d(invW)   /dy * y)
// Solving U(x, y) = targetUV gives a 2D linear system for x and y.
// The returned offset is in screen pixels; callers multiply by g_FbSize
// to convert it to normalized framebuffer UVs.
float2 ProjectiveUVToScreenOffset(float2 uv, float2 targetUV, float clipW) {
    float  invW      = rcp(max(clipW, 1.0e-12));
    float2 uvOverW   = uv * invW;
    float  invWdx    = ddx(invW),    invWdy    = ddy(invW);
    float2 uvOverWdx = ddx(uvOverW), uvOverWdy = ddy(uvOverW);
    float2 a         = uvOverWdx - targetUV * invWdx;
    float2 b         = uvOverWdy - targetUV * invWdy;
    float2 c         = targetUV * invW - uvOverW;
    return DecomposeBasis(a, b, c).xy;
}

float ModulateBlend(float raw, float2 uv) {
    if (!g_NeedsBlendModulation) return raw;
    float4 blendModulation = tex2D(UnderlayAtlas, frac(uv) * 0.5 + float2(0.0, 0.5));
    return smoothstep(blendModulation.g - blendModulation.r, blendModulation.g + blendModulation.r, raw);
}

float3 CalcLightmapFactors(float3 normal) {
    if (g_HasBumpedLightmap) {
        float3 dp = {
            saturate(dot(normal, BumpBasis[0])),
            saturate(dot(normal, BumpBasis[1])),
            saturate(dot(normal, BumpBasis[2])),
        };
        return dp * dp;
    }
    else {
        return float3(1.0, 0.0, 0.0);
    }
}

float3 CalcFinalLightmapColor(float3x3 lightmapColors, float3 lightmapFactors) {
    float3 lightmapFinalColor = mul(lightmapFactors, lightmapColors);
    lightmapFinalColor *= rcp(max(dot(lightmapFactors, float3(1.0, 1.0, 1.0)), 1.0e-3));
    lightmapFinalColor *= g_LightmapScale;
    return lightmapFinalColor;
}

float2 ApplyBaseTransform(float2 uv) {
    return float2(
        dot(float3(uv, 1.0), BaseTransform[0]),
        dot(float3(uv, 1.0), BaseTransform[1]));
}

float2 ApplyBlendMaskTransform(float2 uv) {
    return float2(
        dot(float3(uv, 1.0), BlendTransform[0]),
        dot(float3(uv, 1.0), BlendTransform[1]));
}

float2 ApplyBumpTransform(float2 uv) {
    return float2(
        dot(float3(uv, 1.0), BumpTransform[0]),
        dot(float3(uv, 1.0), BumpTransform[1]));
}

float2 ApplyDetailTransform(float2 uv) {
    return float2(
        uv.x * BaseTransform[0].x * g_DetailScale.x +
        uv.y * BaseTransform[0].y * g_DetailScale.y +
        BaseTransform[0].z * g_DetailScale.x,
        uv.x * BaseTransform[1].x * g_DetailScale.x +
        uv.y * BaseTransform[1].y * g_DetailScale.y +
        BaseTransform[1].z * g_DetailScale.y);
}

float4 ApplyDetailSample(float4 albedo, float4 detailSample) {
    int mode = (int)g_DetailBlendMode;
    if (mode == 0) {
        albedo.rgb *= lerp(1.0, 2.0 * detailSample.rgb, g_DetailBlendFactor);
    }
    else if (mode == 1) {
        albedo.rgb += g_DetailBlendFactor * pow(abs(detailSample.rgb), 2.2);
    }
    else if (mode == 2) {
        albedo.rgb = lerp(albedo.rgb, detailSample.rgb, g_DetailBlendFactor * detailSample.a);
    }
    else if (mode == 3) {
        albedo = lerp(albedo, detailSample, g_DetailBlendFactor);
    }
    else if (mode == 4) {
        albedo.rgb = lerp(albedo.rgb, detailSample.rgb, g_DetailBlendFactor * (1.0 - albedo.a));
        albedo.a = detailSample.a;
    }
    else if (mode == 7) {
        float detailPattern = lerp(detailSample.r, detailSample.a, albedo.a);
        albedo.rgb *= lerp(1.0, 2.0 * detailPattern, g_DetailBlendFactor);
    }
    else if (mode == 8) {
        albedo = lerp(albedo, albedo * detailSample, g_DetailBlendFactor);
    }
    else if (mode == 9) {
        albedo.a = lerp(albedo.a, albedo.a * detailSample.a, g_DetailBlendFactor);
    }
    else if (mode == 11) {
        albedo.rgb *= dot(detailSample.rgb, 2.0 / 3.0);
    }
    return albedo;
}

// Samples only height value to apply parallax effect to the ink
float FetchHeight(float2 uv) {
    return TO_SIGNED(tex2Dlod(InkMap, float4(uv, 0.0, 0.0)).a);
}

// Samples additive color and height value
void FetchAdditiveAndHeight(const PsVertexInfo i, float2 uv, inout MaterialParams params) {
    float4 uv4 = { uv, 0.0, 0.0 };
    float4 s = tex2Dlod(InkMap, uv4);
    params.additive = pow(abs(s.rgb), 2.2); // Manually correct gamma
    params.height   = TO_SIGNED(s.a);

    // Additional samples to calculate tangent space normal
    // 1 px difference = g_RTSize UV difference = (g_RTSize / g_HammerUnitsToUV) HU difference
    float2 deltaUV = g_RTSize * 2.0;
    float2 rcpDiffInHU = g_HammerUnitsToUV / max(2.0 * deltaUV, 1.0e-8);
    float hx = TO_SIGNED(tex2Dlod(InkMap, uv4 + float4(deltaUV.x, 0.0, 0.0, 0.0)).a);
    float hy = TO_SIGNED(tex2Dlod(InkMap, uv4 + float4(0.0, deltaUV.y, 0.0, 0.0)).a);

    // Central difference over 2 * deltaUV.
    float dzdu = (hx - params.height) * HEIGHT_TO_HU * rcpDiffInHU.x;
    float dzdv = (hy - params.height) * HEIGHT_TO_HU * rcpDiffInHU.y;

    // Normal in ink tangent space.
    float3 inkTangentNormal = normalize(float3(-dzdu, -dzdv, 1.0));

    // Convert ink tangent normal -> world normal.
    float3 worldInkNormal = normalize(mul(inkTangentNormal, i.inkTransform));

    // Convert world normal -> underlay/world-material tangent space,
    // because the later code treats params.normal as compatible with geometryNormal.
    params.normal = normalize(mul(i.worldTransform, worldInkNormal));
}

// Samples multiplicative color and ground depth
void FetchMultiplicativeAndDepth(float2 uv, inout MaterialParams params) {
    float4 uv4 = { uv.x + 0.5, uv.y, 0.0, 0.0 };
    float4 s = tex2Dlod(InkMap, uv4);
    params.multiplicative = pow(abs(s.rgb), 2.2); // Manually correct gamma
    params.depth          = s.a;
}

// Samples lighting parameters from texture sampler
void FetchInkMaterial(float3 IDs, out PseudoPBR pbr) {
    float4 s;
    int id1 = (int)IDs.x;
    int id2 = (int)IDs.y;
    float idBlend = IDs.z;

    s = FetchDataPixel(InkDataDetail, id1, ID_MATERIAL_REFRACT);
    pbr.metallic      = s.r;
    pbr.roughness     = s.g;
    pbr.specularScale = s.b;
    pbr.refraction    = s.a;
    s = FetchDataPixel(InkDataDetail, id2, ID_MATERIAL_REFRACT);
    pbr.metallic      = lerp(pbr.metallic,      s.r, idBlend);
    pbr.roughness     = lerp(pbr.roughness,     s.g, idBlend);
    pbr.specularScale = lerp(pbr.specularScale, s.b, idBlend);
    pbr.refraction    = lerp(pbr.refraction,    s.a, idBlend);
}

// Samples detail component
void FetchInkDetails(float3 IDs, out DetailParams detail) {
    float4 s;
    int id1 = (int)IDs.x;
    int id2 = (int)IDs.y;
    float idBlend = IDs.z;

    s = FetchDataPixel(InkDataDetail, id1, ID_DETAILS_BUMPBLEND);
    detail.blendMode       = s.r;
    detail.blendScale      = s.g;
    detail.bumpScale       = s.b;
    detail.bumpBlendFactor = s.a;
    s = FetchDataPixel(InkDataDetail, id2, ID_DETAILS_BUMPBLEND);
    detail.blendMode       = lerp(detail.blendMode,       s.r, idBlend);
    detail.blendScale      = lerp(detail.blendScale,      s.g, idBlend);
    // Detail belongs to the visible top material, not a blend of both textures.
    detail.bumpScale       = idBlend > 0.0 ? s.b : detail.bumpScale;
    detail.bumpBlendFactor = lerp(detail.bumpBlendFactor, s.a, idBlend);
}

// Atlas bounds are integer texel indices split into two bytes per axis.
float2 DecodeDetailTexel(float4 packed) {
    float4 bytes = floor(packed * 255.0 + 0.5);
    return float2(bytes.x * 256.0 + bytes.y, bytes.z * 256.0 + bytes.w);
}

float3 ApplyInkDetailNormal(const PsVertexInfo i, float2 inkUV, float2 pixelUV,
    float3 IDs, float bumpScale, float3 baseNormal) {
    int owner = (int)(IDs.z > 0.0 ? IDs.y : IDs.x);
    if (owner == 0 || bumpScale <= 0.0) return baseNormal;

    float2 localUV = tex2Dlod(InkMap, float4(inkUV + float2(0.5, 0.5), 0.0, 0.0)).rg;
    // UV is linearly filtered; rotation uses the same pixel center as the IDs.
    float rotation = tex2Dlod(InkMap, float4(pixelUV + float2(0.5, 0.0), 0.0, 0.0)).b;
    float2 atlasMin = (DecodeDetailTexel(FetchDataPixel(InkDataDetail, owner, ID_DETAIL_MIN)) + 0.5) * s1Size;
    float2 atlasMax = (DecodeDetailTexel(FetchDataPixel(InkDataDetail, owner, ID_DETAIL_MAX)) + 0.5) * s1Size;
    float2 detailUV = lerp(atlasMin, atlasMax, saturate(localUV));
    float2 xy = TO_SIGNED(tex2Dlod(InkDataDetail, float4(detailUV, 0.0, 0.0)).rg);
    float3 detail = normalize(float3(xy * bumpScale, sqrt(saturate(1.0 - dot(xy, xy)))));

    float sine, cosine;
    sincos(rotation * (2.0 * 3.141592653589793), sine, cosine);
    float2 inkXY = float2(cosine * detail.x - sine * detail.y,
                         sine * detail.x + cosine * detail.y);
    // Ink UV axes contain an atlas scale; use only their directions for normals.
    float3 worldDetail = inkXY.x * normalize(i.inkTransform[0])
                      + inkXY.y * normalize(i.inkTransform[1])
                      + detail.z * i.worldTransform[2];
    // BSP texture axes can be scaled or oblique. Resolve coefficients in their
    // dual basis; multiplying by worldTransform is an inverse only for orthonormal axes.
    float3 tangent = i.worldTransform[0];
    float3 binormal = i.worldTransform[1];
    float3 normal = i.worldTransform[2];
    float3 dualU = cross(binormal, normal);
    float3 dualV = cross(normal, tangent);
    float3 dualN = cross(tangent, binormal);
    float invDet = SAFERCP(dot(tangent, dualU));
    float3 geometryDetail = normalize(float3(dot(worldDetail, dualU),
        dot(worldDetail, dualV), dot(worldDetail, dualN)) * invDet);
    // Whiteout blend: a flat detail leaves the existing ink/underlay normal intact.
    return normalize(float3(baseNormal.xy + geometryDetail.xy, baseNormal.z * geometryDetail.z));
}

// Sample world bumpmap
float3 FetchGeometryNormal(const PsVertexInfo i, UVs uv) {
    float2 dx = ddx(i.worldUV), dy = ddy(i.worldUV);
    float3 geometryNormal = tex2Dgrad(UnderlayBumpmap, uv.bump, dx, dy).rgb;
    if (g_HasUnderlayAtlas) {
        float3 normal2 = tex2Dgrad(UnderlayAtlas, frac(uv.bump) * 0.5 + 0.5, dx, dy).rgb;
        geometryNormal = lerp(geometryNormal, normal2, uv.blend);
    }
    geometryNormal *= 2.0;
    geometryNormal -= 1.0;

    // Handle missing world bumpmap (default to flat normal)
    bool hasNoBump = geometryNormal.x == -1.0 &&
                     geometryNormal.y == -1.0 &&
                     geometryNormal.z == -1.0;
    if (hasNoBump) return float3(0.0, 0.0, 1.0);
    return geometryNormal;
}

float3x3 FetchLightmapSamples(const PsVertexInfo i, float2 uv) {
    float2 dx = ddx(i.lightmapUV), dy = ddy(i.lightmapUV);
    if (g_HasBumpedLightmap) {
        return float3x3(
            tex2Dgrad(Lightmap, uv + i.lightmapOffset * 1.0, dx, dy).rgb,
            tex2Dgrad(Lightmap, uv + i.lightmapOffset * 2.0, dx, dy).rgb,
            tex2Dgrad(Lightmap, uv + i.lightmapOffset * 3.0, dx, dy).rgb);
    }
    else {
        float3 sample = tex2Dgrad(Lightmap, uv, dx, dy).rgb;
        return float3x3(sample, sample, sample);
    }
}

// Samples already-lit geometry sample from geometry textures
float3 FetchGeometrySamples(const PsVertexInfo i, const UVs uv, float3 lightmapFinalColor) {
    float fbRatio = uv.edgefade;
    float4 fb = tex2Dlod(FrameBuffer, float4(uv.screen, 0.0, 0.0));
    if (fb.a * DEPTHWRITE_TO_HU < uv.depth - max(2.0, uv.depth * 0.015)) {
        fbRatio = 0.0;
    }
    if (g_Is4WayBlend) {
        fb = tex2Dlod(FrameBuffer, float4(i.screenUV, 0.0, 0.0));
    }

    float2 duv = ApplyDetailTransform(i.worldUV);
    float2 wuv = ApplyBaseTransform(i.worldUV);
    float2 wdx = ddx(wuv), wdy = ddy(wuv);
    float4 albedo = tex2Dgrad(UnderlayAlbedo, uv.base, wdx, wdy);
    if (g_HasUnderlayAtlas) {
        float4 albedo2 = tex2Dgrad(UnderlayAtlas,
            frac(uv.base) * 0.5 + float2(0.5, 0.0), wdx * 0.5, wdy * 0.5);
        float4 detail = tex2Dgrad(UnderlayAtlas,
            frac(uv.detail) * 0.5, ddx(duv) * 0.5, ddy(duv) * 0.5) * g_DetailTint;
        albedo2.rgb = pow(abs(albedo2.rgb), 2.2);
        albedo.rgb = ApplyDetailSample(lerp(albedo, albedo2, uv.blend), detail).rgb * g_Color;
        return lerp(albedo.rgb * lightmapFinalColor, fb.rgb, fbRatio);
    }
    else {
        float4 detail = tex2Dgrad(UnderlayDetail, uv.detail, ddx(duv), ddy(duv)) * g_DetailTint;
        albedo.rgb = ApplyDetailSample(albedo, detail).rgb * g_Color;
        return lerp(albedo.rgb * lightmapFinalColor, fb.rgb, fbRatio);
    }
}

// Steep Parallax Occlusion Mapping
float3 ApplyParallaxInk(const PsVertexInfo i) {
    const float PIXELS_PER_STEP_RCP = rcp(16.0);
    const float MIN_STEPS = 2.0;
    const float MAX_STEPS = 12.0;
    float3 worldPos = i.worldPos;
    float3 inkUV    = i.inkUV;
    float3x3 tangentSpaceInk = i.inkTransform;
    tangentSpaceInk[2] /= HEIGHT_TO_HU;

    float3 boxMin      = { i.minUV, -1.0 - 1e-5 };
    float3 boxMax      = { i.maxUV,  0.0        };
    float3 viewDir     = mul(tangentSpaceInk, g_EyePos.xyz - worldPos);
    float3 viewDirInv  = SAFERCP(viewDir);
    float3 fractionMin = (boxMin - inkUV) * viewDirInv;
    float3 fractionMax = (boxMax - inkUV) * viewDirInv;
    float3 fractionFar = min(fractionMin, fractionMax);
    float  fractionEnd = max(max(fractionFar.x, fractionFar.y), fractionFar.z);
    float3 rayStart    = inkUV;
    float3 rayEnd      = inkUV + viewDir * fractionEnd;
    float  pixelPerUV  = rcp(max(min(length(ddx(inkUV.xy)), length(ddy(inkUV.xy))), 1.0e-8));
    float  numSteps    = distance(rayStart.xy, rayEnd.xy);
    numSteps *= PIXELS_PER_STEP_RCP * pixelPerUV;
    numSteps = clamp(round(numSteps), MIN_STEPS, MAX_STEPS);
    float3 previousRay;
    float3 currentRay = rayStart;
    float previousInkHeight;
    float currentInkHeight = FetchHeight(currentRay.xy);
    if (currentInkHeight >= 0.0) return currentRay;
    [unroll]
    for (int j = 1; j <= MAX_STEPS; j++) {
        if (j > (int)numSteps) break;
        float fraction = (float)j / numSteps;
        previousInkHeight = currentInkHeight;
        previousRay = currentRay;
        currentRay = lerp(rayStart, rayEnd, fraction);
        currentInkHeight = FetchHeight(currentRay.xy);
        if (currentInkHeight >= 0.0) return currentRay;
        if ((previousInkHeight <= previousRay.z && currentRay.z <= currentInkHeight) ||
            (previousRay.z <= previousInkHeight && currentInkHeight <= currentRay.z)) {
            float previousHeightLeft = previousRay.z - previousInkHeight;
            float currentHeightExceeds = currentInkHeight - currentRay.z;
            float parallaxRefinement = currentHeightExceeds / (previousHeightLeft + currentHeightExceeds);
            inkUV = lerp(currentRay, previousRay, parallaxRefinement);
            return clamp(inkUV, float3(i.minUV, -1.0), float3(i.maxUV,  1.0));
        }
    }
    return clamp(inkUV, float3(i.minUV, -1.0), float3(i.maxUV,  1.0));
}

UVs ApplyParallaxGeometry(const PsVertexInfo i, const MaterialParams params) {
    UVs uv;
    float3x3 tangentSpaceLightmap = i.lightmapTransform; // TEXINFO.lightmapVecS, TEXINFO.lightmapVecT, normal
    float3x3 tangentSpaceGeometry = i.worldTransform;    // TEXINFO.textureVecS,  TEXINFO.textureVecT,  normal
    tangentSpaceLightmap[2] /= HEIGHT_TO_HU;             // units are in $basetexture's texel per Hammer units
    tangentSpaceGeometry[2] /= HEIGHT_TO_HU;
    float3 viewVecLightmap  = mul(tangentSpaceLightmap, g_EyePos.xyz - i.worldPos);
    float3 viewVecGeometry  = mul(tangentSpaceGeometry, g_EyePos.xyz - i.worldPos);
    float2 viewVecZ         = max(float2(viewVecLightmap.z, viewVecGeometry.z), 1.0e-3);
    float2 lightmapParallax = -viewVecLightmap.xy * params.depth / viewVecZ.x * g_LightmapSize;
    float2 uvParallax       = -viewVecGeometry.xy * params.depth / viewVecZ.y * g_UnderlayAlbedoSize;
    float2 uvRefraction     = params.normal.xy * params.pbr.refraction * 0.0;
    float2 uvOffset         = uvParallax + uvRefraction;
    float2 worldUVParallax  = i.worldUV + uvOffset;
    uv.base     = ApplyBaseTransform(worldUVParallax);
    uv.bump     = ApplyBumpTransform(worldUVParallax);
    uv.detail   = ApplyDetailTransform(worldUVParallax);
    uv.lightmap = i.lightmapUV + lightmapParallax;

    float2 dUdx      = ddx(i.worldUV);
    float2 dUdy      = ddy(i.worldUV);
    float2 dBdxy     = { ddx(i.baseTextureBlend), ddy(i.baseTextureBlend) };
    float2 blendGrad = DecomposeBasis(dUdx, dUdy, dBdxy).xy;
    float2 offset    = ProjectiveUVToScreenOffset(i.worldUV, i.worldUV + uvOffset, i.clipPos.w);
    float2 s         = i.screenUV + offset * g_FbSize;
    float2 uvbmt     = ApplyBlendMaskTransform(worldUVParallax);
    uv.edgefade      = ScreenEdgeFade(s);
    uv.screen        = saturate(s);
    uv.blend         = ModulateBlend(i.baseTextureBlend + dot(blendGrad, uvOffset), uvbmt);
    uv.depth         = i.clipPos.w + ddx(i.clipPos.w) * offset.x + ddy(i.clipPos.w) * offset.y;
    return uv;
}

PS_OUTPUT main(const PS_INPUT rawInput) {
    PsVertexInfo i = DecomposeInput(rawInput);
    float sceneViewDepthHU = tex2Dlod(FrameBuffer, float4(i.screenUV, 0.0, 0.0)).a * DEPTHWRITE_TO_HU;
    float depthToleranceHU = max(2.0, i.clipPos.w * 0.015);
    clip(sceneViewDepthHU - i.clipPos.w + depthToleranceHU);

    // Z = final ray marching height
    float3 inkUV   = g_Simplified ? i.inkUV : ApplyParallaxInk(i);
    float3 viewVec = g_EyePos.xyz - i.worldPos;
    float3 viewDir = normalize(viewVec);
    float2 pixelUV = (floor(inkUV.xy / g_RTSize) + 0.5) * g_RTSize + float2(0.0, 0.5);
    float4 inkIDs  = tex2Dlod(InkMap, float4(pixelUV, 0.0, 0.0));
    float3 IDs     = { round(inkIDs.r * 255.0), round(inkIDs.g * 255.0), inkIDs.b };
    clip(floor(IDs.x + IDs.y + IDs.z) - 0.5);

    // Samples ink parameters
    MaterialParams params;
    FetchAdditiveAndHeight(i, inkUV.xy, params);
    FetchMultiplicativeAndDepth(inkUV.xy, params);
    FetchInkMaterial(IDs, params.pbr);
    FetchInkDetails(IDs, params.detail);

    // Blend ink and world normals
    UVs      uv                 = ApplyParallaxGeometry(i, params);
    float3   geometryNormal     = FetchGeometryNormal(i, uv);
    float3   tangentSpaceNormal = normalize(lerp(geometryNormal, params.normal, params.detail.bumpBlendFactor));
    tangentSpaceNormal = ApplyInkDetailNormal(i, inkUV.xy, pixelUV, IDs, params.detail.bumpScale, tangentSpaceNormal);
    float3   worldSpaceNormal   = normalize(mul(tangentSpaceNormal, i.worldTransform));
    float3   lightmapFactors    = CalcLightmapFactors(tangentSpaceNormal);
    float3x3 lightmapColors     = FetchLightmapSamples(i, uv.lightmap);
    float3   lightmapFinalColor = CalcFinalLightmapColor(lightmapColors, lightmapFactors);

    // Compute and apply diffuse lighting factors using bumped lightmap basis
    float3 geometryLit = FetchGeometrySamples(i, uv, lightmapFinalColor) * params.multiplicative;
    float3 inkLit      = params.additive * lightmapFinalColor;
    float3 albedo      = geometryLit + inkLit;

    // Modulate surface albedo and add ink color
    float3 ambientOcclusion = { 1.0, 1.0, 1.0 }; // dummy!
    float3 result = albedo * lerp(1.0, DIFFUSE_MIN, params.pbr.metallic);

    // Simplified pass doesn't need specular component
    if (g_Simplified) {
        PS_OUTPUT output = (PS_OUTPUT)0.0;
        output.finalColorWithoutSSR = float4(result * g_TonemapScale, 1.0);
        return output;
    }

    // ^ Diffuse component (multiplies to the final result)
    // -------------------------------------------------------------------------
    // v Specular component (accumulates to the final result)

    float3 tangentViewDir = mul(i.worldTransform, viewDir);

#ifdef g_PhongEnabled
    float  phongExponent = lerp(PHONG_EXPONENT_MIN, PHONG_EXPONENT_MAX, params.pbr.roughness);
    float3 phongFresnel  = lerp(FRESNEL_MIN, albedo, params.pbr.metallic);
    float3 phongLightDir = g_SunDirection;
    if (g_HasBumpedLightmap) {
        float3 strength = mul(GrayScaleFactor, lightmapColors);
        float3 fakeTangentLightDir = mul(strength, BumpBasis);
        float3 fakeWorldLightDir = mul(fakeTangentLightDir, i.worldTransform);
        phongLightDir = lerp(g_SunDirection, fakeWorldLightDir, saturate(strength));
    }

    float spec = CalcBlinnPhongSpec(worldSpaceNormal, phongLightDir, viewDir, phongExponent);
    float3 phongSpecular = mul(lightmapFactors * spec, lightmapColors);
    phongSpecular *= CalcFresnel(tangentSpaceNormal, tangentViewDir, phongFresnel);
    phongSpecular *= ambientOcclusion;
    phongSpecular *= params.pbr.specularScale;
    phongSpecular *= g_LightmapScale;
    result += phongSpecular;
#endif

#ifdef g_RimEnabled
    float3 worldMeshNormal = i.worldTransform[2];
    float rimExponent = lerp(RIM_EXPONENT_MIN, RIM_EXPONENT_MAX, params.pbr.roughness);
    float rimNormalDotViewDir = saturate(dot(worldMeshNormal, viewDir));
    float rimScale = saturate(pow(1.0 - rimNormalDotViewDir, rimExponent));
    rimScale *= lerp(RIM_METALIC_MIN, RIM_METALIC_MAX, params.pbr.metallic);
    rimScale *= lerp(RIM_ROUGHNESS_MIN, RIM_ROUGHNESS_MAX, params.pbr.roughness);
    rimScale *= saturate(
        (RIMLIGHT_FADE_MAX - i.clipPos.z) /
        (RIMLIGHT_FADE_MAX - RIMLIGHT_FADE_MIN));

    // Use average lightmap color as rim light color
    float3 rimLighting = mul(lightmapFactors, lightmapColors);
    rimLighting = lerp(rimLighting, albedo, params.pbr.metallic);
    rimLighting *= min(rimScale, RIMLIGHT_MAX_SCALE);
    rimLighting *= params.pbr.specularScale;
    rimLighting *= g_LightmapScale;
    result += rimLighting;
#endif

#ifdef g_EnvmapEnabled
    float3 reflectDir    = reflect(-viewDir, worldSpaceNormal);
    float3 envmapSample  = texCUBE(Envmap, reflectDir).rgb * g_EnvmapScale;
    float3 envmapFresnel = lerp(FRESNEL_MIN, albedo, params.pbr.metallic);
    float  envmapScale   = lerp(ENVMAP_SCALE_MIN, ENVMAP_SCALE_MAX, params.pbr.roughness * params.pbr.roughness);
    float3 envmapAlbedo  = lerp(float3(1.0, 1.0, 1.0), albedo, params.pbr.metallic);
    float3 reflectionWeight = envmapAlbedo;
    reflectionWeight *= CalcFresnel(worldSpaceNormal, viewDir, envmapFresnel);
    reflectionWeight *= envmapScale;
    reflectionWeight *= ambientOcclusion;
    reflectionWeight *= params.pbr.specularScale;
    reflectionWeight *= g_LightmapScale;
#endif

    // ^ Specular component (accumulates to the final result)
    // -------------------------------------------------------------------------
    PS_OUTPUT output = {
        { result, 1.0 },
        {
            EncodeOctahedralUnitVector(worldSpaceNormal),
            EncodeOctahedralUnitVector(i.worldTransform[2])
        },
        { reflectionWeight, params.height },
        { envmapSample, params.pbr.roughness }
    };
    return output;
}
