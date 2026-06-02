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
    float4 color : COLOR0;
    float  depth : DEPTH0;
};

struct UVs {
    float2 base;
    float2 bump;
    float2 detail;
    float2 lightmap;
    float2 screen;
    float  isedge;
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
    float2 depthGradient;
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
static const float DepthWriteConstant = 4000.0; // Used by DepthWrite / _rt_resolvedfullframedepth
static const float3 GrayScaleFactor   = { 0.2126, 0.7152, 0.0722 };
static const float3x3 BumpBasis = {
    // Bumped lightmap basis vectors (same as LightmappedGeneric) in tangent space
    {  0.81649661064147949,  0.0,                 0.57735025882720947 },
    { -0.40824833512306213,  0.70710676908493042, 0.57735025882720947 },
    { -0.40824833512306213, -0.70710676908493042, 0.57735025882720947 },
};

// Samplers
sampler InkMap          : register(s0);
sampler InkData         : register(s1);
sampler FrameBuffer     : register(s2);
sampler UnderlayAlbedo  : register(s3);
sampler UnderlayBumpmap : register(s4);
sampler TextureSampler5 : register(s5);
sampler Lightmap        : register(s6);
sampler InkDetail       : register(s7);

#define UnderlayDetail TextureSampler5 // g_HasUnderlayAtlas == 0.0
#define UnderlayAtlas  TextureSampler5 // g_HasUnderlayAtlas != 0.0

// Constants
const float4 c0        : register(c0);
const float4 c1        : register(c1);
const float4 c2        : register(c2);
const float4 c3        : register(c3);
const float2 s0Size    : register(c4);
const float2 s1Size    : register(c5);
const float2 s2Size    : register(c6);
const float2 s3Size    : register(c7);
const float4 c8        : register(c8);
const float4 c9        : register(c9);
const float4 g_EyePos  : register(c10); // xyz: eye position
const float4 c11       : register(c11); // $viewprojmat
const float4 c12       : register(c12);
const float4 c13       : register(c13);
const float4 c14       : register(c14);
const float4x4 c15     : register(c15); // $invviewprojmat
const float4 HDRParams : register(c30);

static const float3 BaseTransform[2]       = { c11.xyz, c12.xyz };
static const float3 BumpTransform[2]       = { c13.xyz, c14.xyz };
static const float4 g_DetailTint           = { c11.w, c12.w, c13.w, 1.0 };
static const float3 g_SunDirection         = c0.xyz; // in world space
static const float  g_DetailBlendMode      = c0.w;
static const float  g_HammerUnitsToUV      = c1.x;   // = ss.RenderTarget.HammerUnitsToUV * 0.5
static const float  g_MaterialFlags        = c1.y;
static const float2 g_LightmapSize         = c2.xy;  // One over lightmap size
static const float2 g_DetailScale          = c2.zw;
static const float3 g_Color                = c3.rgb;
static const float  g_DetailBlendFactor    = c3.w;
static const float2 g_RTSize               = s0Size; // One over ink map size
static const float2 g_DataRTSize           = s1Size; // One over data look-up table size
static const float2 g_FbSize               = s2Size; // One over frame buffer size
static const float2 g_UnderlayAlbedoSize   = s3Size; // One over $basetexture size
static const float  g_TonemapScale         = HDRParams.x;
static const float  g_LightmapScale        = HDRParams.y;
static const float  g_EnvmapScale          = HDRParams.z;
static const float  g_GammaScale           = HDRParams.w; // = TonemapScale ^ (1 / 2.2)

// Bit flags:
//   0x01 .. has $bumpmap
//   0x02 .. is  WorldVertexTransition
//   0x04 .. is  Lightmapped_4WayBlend
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

float4 CalcNearFarZ(float projPosZ, float projPosW) {
    // Construct near and far Z from projected position Z and W
    // Projection matrix looks like
    // / *   0               0                    0 \
    // | 0   *               0                    0 |
    // | 0   0            farZ / (farZ - nearZ)   1 |
    // \ 0   0   -nearZ * farZ / (farZ - nearZ)   0 /
    //
    // and projected position Z and W are
    // W = z
    // Z = z * ( farZ / (farZ - nearZ) ) + ( -nearZ * farZ / (farZ - nearZ) )
    //   = Propotional * W + Offset
    //
    // Partial derivatives of Z and W effectively estimates the projection matrix
    // ∂Z/∂x = ∂/∂x(Propotional * W + Offset) = Propotiolal * ∂W/∂x
    //
    // We have two formula to estimate the Propotional factor
    // ∂Z/∂x = Propotional * ∂W/∂x
    // ∂Z/∂y = Propotional * ∂W/∂y
    // float2(∂Z/∂x, ∂Z/∂y) = Propotional * float2(∂W/∂x, ∂W/∂y)
    //
    // The dot product of the partial derivatives are
    // dot(∂Z/∂X, ∂W/∂X) = Propotional * dot(∂W/∂X, ∂W/∂X)
    // <=>   Propotional = dot(∂Z/∂X, ∂W/∂X) / dot(∂W/∂X, ∂W/∂X)
    float2 dZ = { ddx(projPosZ), ddy(projPosZ) };
    float2 dW = { ddx(projPosW), ddy(projPosW) };
    float projMatrixPropotional = dot(dW, dW) > 1e-6 ? dot(dZ, dW) * rcp(dot(dW, dW)) : 1.0;
    float projMatrixOffset = projPosZ - projMatrixPropotional * projPosW;
    float nearZ = -projMatrixOffset * SAFERCP(projMatrixPropotional);
    float farZ = -projMatrixPropotional * nearZ / (1.0 - projMatrixPropotional);
    return float4(nearZ, farZ, projMatrixPropotional, projMatrixOffset);
}

// Inverse conversion of world position -- UV coordinates equation:
// P: world pos,  S: tangent S,         T: tangent T
// U: (u, v),     X: screen pos (x, y)
//    P = S u + T v
// 1. Get partial derivatives of both sides
//    ∂P/∂x = S ∂u/∂x + T ∂v/∂x
//    ∂P/∂y = S ∂u/∂y + T ∂v/∂y
// 2. Consolidates them into matrix form (assuming row vectors)
//   / ∂P/dx \ _ / ∂U/∂x \ / S \
//   \ ∂P/∂y / ‾ \ ∂U/∂y / \ T /
// 3. Multiplies inverse dUdx--dUdy matrix from left side to get S, T
// float2x3 dPdX   = { ddx(worldPos), ddy(worldPos) };
// float2x2 dUdX   = { ddx(inkUV),    ddy(inkUV)    };
// float dUdXdet   = dUdX._m00 * dUdX._m11 - dUdX._m01 * dUdX._m10;
// float dUdXidet  = sign(dUdXdet) * rcp(max(abs(dUdXdet), 1.0e-8));
// float2x2 dUdXInv = float2x2(
//      dUdX._m11, -dUdX._m01,
//     -dUdX._m10,  dUdX._m00) * dUdXidet;
// float3x3 tangentSpaceInk = { mul(dUdXInv, dPdX), i.worldNormalTangentY.xyz };
// tangentSpaceInk[0] = normalize(tangentSpaceInk[0]) * g_HammerUnitsToUV;
// tangentSpaceInk[1] = normalize(tangentSpaceInk[1]) * g_HammerUnitsToUV;
float2 ProjectiveUVToScreenOffset(float2 uv, float2 targetUV, float clipW) {
    float  invW      = rcp(max(clipW, 1.0e-12));
    float2 uvOverW   = uv * invW;
    float  invWdx    = ddx(invW),    invWdy    = ddy(invW);
    float2 uvOverWdx = ddx(uvOverW), uvOverWdy = ddy(uvOverW);
    float2 a         = uvOverWdx - targetUV * invWdx;
    float2 b         = uvOverWdy - targetUV * invWdy;
    float2 c         = targetUV * invW - uvOverW;
    float  det       = a.x * b.y - b.x * a.y;
    float  invDet    = sign(det) * rcp(max(abs(det), 1.0e-20));
    return float2(
        (c.x * b.y - b.x * c.y) * invDet,
        (a.x * c.y - c.x * a.y) * invDet);
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
    return float2(dot(float3(uv, 1.0), BaseTransform[0]), dot(float3(uv, 1.0), BaseTransform[1]));
}

float2 ApplyBumpTransform(float2 uv) {
    return float2(dot(float3(uv, 1.0), BumpTransform[0]), dot(float3(uv, 1.0), BumpTransform[1]));
}

float2 ApplyDetailTransform(float2 uv) {
    return float2(
        uv.x * BaseTransform[0].x * g_DetailScale.x + uv.y * BaseTransform[0].y * g_DetailScale.y + BaseTransform[0].z * g_DetailScale.x,
        uv.x * BaseTransform[1].x * g_DetailScale.x + uv.y * BaseTransform[1].y * g_DetailScale.y + BaseTransform[1].z * g_DetailScale.y);
}

float4 ApplyDetailSample(float4 albedo, float4 detailSample) {
    int mode = (int)g_DetailBlendMode;
    if (mode == 0) {
        albedo.rgb *= lerp(1.0, 2.0 * detailSample.rgb, g_DetailBlendFactor);
    }
    else if (mode == 1) {
        albedo.rgb += g_DetailBlendFactor * detailSample.rgb;
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

float4 FetchDataPixel(int id, int index) {
    if (id == 0) {
        return GROUND_PROPERTIES[index];
    }
    else {
        return tex2Dlod(InkData, float4(
            (id    - 0.5) * g_DataRTSize.x,
            (index + 0.5) * g_DataRTSize.y,
            0.0,
            0.0));
    }
}

// Samples only height value to apply parallax effect to the ink
float FetchHeight(float2 uv) {
    return TO_SIGNED(tex2Dlod(InkMap, float4(uv, 0.0, 0.0)).a);
}

// Samples only depth value to apply parallax effect to the ink
float FetchDepth(float2 uv) {
    return tex2Dlod(InkMap, float4(uv.x + 0.5, uv.y, 0.0, 0.0)).a;
}

// Samples additive color and height value
void FetchAdditiveAndHeight(float2 uv, inout MaterialParams params) {
    float4 uv4 = { uv, 0.0, 0.0 };
    float4 s = tex2Dlod(InkMap, uv4);
    params.additive = pow(abs(s.rgb), 2.2); // Manually correct gamma
    params.height   = TO_SIGNED(s.a);

    // Additional samples to calculate tangent space normal
    float hx = TO_SIGNED(tex2Dlod(InkMap, uv4 + float4(g_RTSize.x, 0.0, 0.0, 0.0)).a);
    float hy = TO_SIGNED(tex2Dlod(InkMap, uv4 + float4(0.0, g_RTSize.y, 0.0, 0.0)).a);
    float dx = hx - params.height;
    float dy = hy - params.height;
    params.normal = normalize(float3(-dx, -dy, 1.0));
}

// Samples multiplicative color and ground depth
void FetchMultiplicativeAndDepth(float2 uv, inout MaterialParams params) {
    float4 uv4 = { uv.x + 0.5, uv.y, 0.0, 0.0 };
    float4 s = tex2Dlod(InkMap, uv4);
    params.multiplicative = pow(abs(s.rgb), 2.2); // Manually correct gamma
    params.depth          = s.a;

    // Additional samples to calculate depth gradient
    float dx = tex2Dlod(InkMap, uv4 + float4(g_RTSize.x, 0.0, 0.0, 0.0)).a;
    float dy = tex2Dlod(InkMap, uv4 + float4(0.0, g_RTSize.y, 0.0, 0.0)).a;
    params.depthGradient = float2(dx, dy) - params.depth;
}

// Samples lighting parameters from texture sampler
void FetchInkMaterial(float3 IDs, out PseudoPBR pbr) {
    float4 s;
    int id1 = (int)IDs.x;
    int id2 = (int)IDs.y;
    float idBlend = IDs.z;

    s = FetchDataPixel(id1, ID_MATERIAL_REFRACT);
    pbr.metallic      = s.r;
    pbr.roughness     = s.g;
    pbr.specularScale = s.b;
    pbr.refraction    = s.a;
    s = FetchDataPixel(id2, ID_MATERIAL_REFRACT);
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

    s = FetchDataPixel(id1, ID_DETAILS_BUMPBLEND);
    detail.blendMode       = s.r;
    detail.blendScale      = s.g;
    detail.bumpScale       = s.b;
    detail.bumpBlendFactor = s.a;
    s = FetchDataPixel(id2, ID_DETAILS_BUMPBLEND);
    detail.blendMode       = lerp(detail.blendMode,       s.r, idBlend);
    detail.blendScale      = lerp(detail.blendScale,      s.g, idBlend);
    detail.bumpScale       = lerp(detail.bumpScale,       s.b, idBlend);
    detail.bumpBlendFactor = lerp(detail.bumpBlendFactor, s.a, idBlend);
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
    if (uv.isedge < 0.5) {
        float4 fb = tex2Dlod(FrameBuffer, float4(uv.screen, 0.0, 0.0));
        if (fb.a * DepthWriteConstant > uv.depth - max(2.0, uv.depth * 0.015)) return fb.rgb;
        if (g_Is4WayBlend) return tex2Dlod(FrameBuffer, float4(i.screenUV, 0.0, 0.0)).rgb / g_TonemapScale;
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
        albedo.rgb = ApplyDetailSample(lerp(albedo, albedo2, uv.blend), detail).rgb * g_Color;
        return albedo.rgb * lightmapFinalColor;
    }
    else {
        float4 detail = tex2Dgrad(UnderlayDetail, uv.detail, ddx(duv), ddy(duv)) * g_DetailTint;
        albedo.rgb = ApplyDetailSample(albedo, detail).rgb * g_Color;
        return albedo.rgb * lightmapFinalColor;
    }
}

// Steep Parallax Occlusion Mapping
float3 ApplyParallaxInk(const PsVertexInfo i) {
    const float PIXELS_PER_STEP_RCP = rcp(16.0);
    const float MIN_STEPS = 2.0;
    const float MAX_STEPS = 16.0;
    float3 worldPos = i.worldPos;
    float3 inkUV    = i.inkUV;
    float3x3 tangentSpaceInk = i.inkTransform;
    tangentSpaceInk[2] /= HEIGHT_TO_HU;

    float3 boxMin        = { i.minUV, -1.0 - 1e-5 };
    float3 boxMax        = { i.maxUV,  0.0        };
    float3 viewDir       = mul(tangentSpaceInk, g_EyePos.xyz - worldPos);
    float3 viewDirInv    = SAFERCP(viewDir);
    float3 fractionMin   = (boxMin - inkUV) * viewDirInv;
    float3 fractionMax   = (boxMax - inkUV) * viewDirInv;
    float3 fractionFar   = min(fractionMin, fractionMax);
    float  fractionEnd   = max(max(fractionFar.x, fractionFar.y), fractionFar.z);
    float3 rayStart      = inkUV;
    float3 rayEnd        = inkUV + viewDir * fractionEnd;
    float  pixelPerUV    = rcp(max(min(length(ddx(inkUV.xy)), length(ddy(inkUV.xy))), 1.0e-8));
    float  numSteps      = distance(rayStart.xy, rayEnd.xy);
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
    float3x3 tangentSpaceGeometry = i.worldTransform;    // TEXINFO.textureVecS, TEXINFO.textureVecT, normal
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

    float4 dUdxy  = { ddx(i.worldUV), ddy(i.worldUV) };
    float2 dbdxy  = { ddx(i.baseTextureBlend), ddy(i.baseTextureBlend) };
    float  invdet = SAFERCP(dUdxy.x * dUdxy.w - dUdxy.y * dUdxy.z);
    float2 blendGrad = {
        (dbdxy.x * dUdxy.w - dUdxy.y * dbdxy.y) * invdet,
        (dUdxy.x * dbdxy.y - dbdxy.x * dUdxy.z) * invdet,
    };
    float2 offset = ProjectiveUVToScreenOffset(i.worldUV, i.worldUV + uvOffset, i.clipPos.w);
    float2 s  = i.screenUV + offset * g_FbSize;
    uv.isedge = 1.0 - step(0.0, min(min(s.x, s.y), 1.0 - max(s.x, s.y)));
    uv.screen = saturate(s);
    uv.blend  = ModulateBlend(i.baseTextureBlend + dot(blendGrad, uvOffset), uv.base);
    uv.depth  = i.clipPos.w + ddx(i.clipPos.w) * offset.x + ddy(i.clipPos.w) * offset.y;
    return uv;
}

float4 main(const PS_INPUT rawInput) : COLOR0 {
    PsVertexInfo i = DecomposeInput(rawInput);
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
    FetchAdditiveAndHeight(inkUV.xy, params);
    FetchMultiplicativeAndDepth(inkUV.xy, params);
    FetchInkMaterial(IDs, params.pbr);
    FetchInkDetails(IDs, params.detail);

    // Blend ink and world normals
    UVs      uv                 = ApplyParallaxGeometry(i, params);
    float3   geometryNormal     = FetchGeometryNormal(i, uv);
    float3   tangentSpaceNormal = normalize(lerp(geometryNormal, params.normal, params.detail.bumpBlendFactor));
    float3   worldSpaceNormal   = normalize(mul(tangentSpaceNormal, i.worldTransform));
    float3   lightmapFactors    = CalcLightmapFactors(tangentSpaceNormal);
    float3x3 lightmapColors     = FetchLightmapSamples(i, uv.lightmap);
    float3   lightmapFinalColor = CalcFinalLightmapColor(lightmapColors, lightmapFactors);

    // Compute and apply diffuse lighting factors using bumped lightmap basis
    float3 geometryLit = FetchGeometrySamples(i, uv, lightmapFinalColor) * params.multiplicative;
    float3 inkLit      = params.additive * CalcFinalLightmapColor(lightmapColors, lightmapFactors);
    float3 albedo      = geometryLit + inkLit;

    // Modulate surface albedo and add ink color
    float3 ambientOcclusion = { 1.0, 1.0, 1.0 }; // dummy!
    float3 result = albedo * lerp(1.0, DIFFUSE_MIN, params.pbr.metallic);

    // ^ Diffuse component (multiplies to the final result)
    // -------------------------------------------------------------------------
    // v Specular component (accumulates to the final result)

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
    float3 tangentViewDir = mul(i.worldTransform, viewDir);
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
    // Envmap specular component
    float3 envmapReflect = reflect(tangentViewDir, tangentSpaceNormal);
    float2 envmapUVOffset = envmapReflect.xy * 7.0;
    float2 tangentScaleSqr = {
        dot(i.worldTransform[0], i.worldTransform[0]),
        dot(i.worldTransform[1], i.worldTransform[1]),
    };
    envmapUVOffset /= max(tangentScaleSqr, 1.0e-3);
    float2 screenOffset = ProjectiveUVToScreenOffset(i.worldUV, i.worldUV + envmapUVOffset, i.clipPos.w);
    float2 fakeSSRUV = saturate(i.screenUV - screenOffset * g_FbSize);
    float3 envmapSpecular = tex2Dlod(FrameBuffer, float4(fakeSSRUV, 0.0, 0.0)).rgb;
    envmapSpecular /= g_TonemapScale;
    envmapSpecular *= smoothstep(-0.35, 0.35, envmapReflect.z);
    envmapSpecular *= step(abs(i.clipPos.w), 1e-3);

    // Apply envmap contribution
    float3 envmapFresnel = lerp(FRESNEL_MIN, albedo, params.pbr.metallic);
    float  envmapScale   = lerp(ENVMAP_SCALE_MIN, ENVMAP_SCALE_MAX, params.pbr.roughness * params.pbr.roughness);
    float3 envmapAlbedo  = lerp(float3(1.0, 1.0, 1.0), albedo, params.pbr.metallic);
    envmapSpecular *= envmapAlbedo;
    envmapSpecular *= CalcFresnel(worldSpaceNormal, viewDir, envmapFresnel);
    envmapSpecular *= envmapScale;
    envmapSpecular *= ambientOcclusion;
    envmapSpecular *= params.pbr.specularScale;
    envmapSpecular *= g_LightmapScale;
    result += envmapSpecular;
#endif

    // ^ Specular component (accumulates to the final result)
    // -------------------------------------------------------------------------
    return float4(result * g_TonemapScale, 1.0);
}
