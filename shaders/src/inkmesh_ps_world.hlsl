// Ink Mesh Pixel Shader for SplashSWEPs, world geometry part; see inkmesh_ps_ink.hlsl
// Based on LightmappedGeneric pixel shader with bumped lightmaps

#include "inkmesh_ps_ink.hlsl"

// Kind of the underlay material, built as separate shaders so that the temp registers are allocated per kind.
//   inkmesh_ps30.hlsl           .. UNDERLAY_SINGLE: no $basetexture2, and the simplified pass
//   inkmesh_wvt_ps30.hlsl       .. UNDERLAY_WVT: WorldVertexTransition, has $basetexture2
//   inkmesh_4wayblend_ps30.hlsl .. UNDERLAY_4WAYBLEND: Lightmapped_4WayBlend, has $basetexture3
#define UNDERLAY_SINGLE    0
#define UNDERLAY_WVT       1
#define UNDERLAY_4WAYBLEND 2
#ifndef UNDERLAY_KIND
#define UNDERLAY_KIND UNDERLAY_SINGLE
#endif
#define HAS_UNDERLAY_ATLAS (UNDERLAY_KIND != UNDERLAY_SINGLE)
#define IS_WVT             (UNDERLAY_KIND == UNDERLAY_WVT)
#define IS_4WAYBLEND       (UNDERLAY_KIND == UNDERLAY_4WAYBLEND)

struct PS_INPUT {
    float4 screenPos : VPOS;
    VertexInfo vi;
};

struct UVs {
    float2 base;
    float2 bump;
    float2 detail;
    float2 lightmap;
    float2 screen;
    float  edgefade;
    float3 blend; // Vertex blend of $basetexture2, 3, and 4, shifted by parallax
    float  depth;
};

struct PsVertexInfo {
    float3   vertexBlend;
    float2   screenUV;
    float3   worldPos;
    float    clipZ;
    float    clipW;
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

static const float3 LUMINANCE_FACTOR = { 0.2125, 0.7154, 0.0721 }; // Luminance() of Lightmapped_4WayBlend
static const float3x3 BumpBasis = {
    // Bumped lightmap basis vectors (same as LightmappedGeneric) in tangent space
    {  0.81649661064147949,  0.0,                 0.57735025882720947 },
    { -0.40824833512306213,  0.70710676908493042, 0.57735025882720947 },
    { -0.40824833512306213, -0.70710676908493042, 0.57735025882720947 },
};

#if HAS_UNDERLAY_ATLAS
sampler UnderlayAtlas  : register(s5); // Built by ss.BuildUnderlayTexturePack
#else
sampler UnderlayDetail : register(s5); // $detail
#endif
sampler Lightmap       : register(s6);

static const float3 g_SunDirection      = c0.xyz; // in world space
static const float  g_DetailBlendMode   = c0.w;
static const float  g_MaterialFlags     = c1.y;
static const float2 g_LightmapSize      = c2.xy;  // One over lightmap size
static const float2 g_DetailScale       = c2.zw;
static const float4 g_DetailTint        = { c11.w, c12.w, c13.w, 1.0 };
static const float  g_DetailBlendFactor = c14.w;

// Bit flags:
//   0x01 .. has $bumpmap
//   0x08 .. has $blendmodulatetexture, read only for WorldVertexTransition
//   0x10 .. is  simplified rendering for water reflection, read only for UNDERLAY_SINGLE
static const bool g_HasBumpedLightmap = fmod(floor(g_MaterialFlags / 1),  2.0) > 0.5;
static const bool g_Simplified        = UNDERLAY_KIND == UNDERLAY_SINGLE && fmod(floor(g_MaterialFlags / 16), 2.0) > 0.5;

#if HAS_UNDERLAY_ATLAS
// Cells of the underlay atlas built by ss.BuildUnderlayTexturePack.
// Lightmapped_4WayBlend has the third column.
//   row 0: $detail,               $basetexture2,         $basetexture3
//   row 1: $blendmodulatetexture, $bumpmap2 or $bumpmap, $basetexture4
static const float2 ATLAS_DETAIL        = { 0.0, 0.0 };
static const float2 ATLAS_BASETEXTURE2  = { 1.0, 0.0 };
static const float2 ATLAS_BASETEXTURE3  = { 2.0, 0.0 };
static const float2 ATLAS_BLENDMODULATE = { 0.0, 1.0 };
static const float2 ATLAS_BUMPMAP2      = { 1.0, 1.0 };
static const float2 ATLAS_BASETEXTURE4  = { 2.0, 1.0 };
#if IS_4WAYBLEND
static const float2 ATLAS_CELL_SIZE     = { 1.0 / 3.0, 0.5 };
#else
static const float2 ATLAS_CELL_SIZE     = { 0.5, 0.5 };
#endif

float2 AtlasUV(float2 uv, float2 cell) {
    return (frac(uv) + cell) * ATLAS_CELL_SIZE;
}

// The atlas is a render target, which has no mipmaps regardless of its flags (garrysmod-issues #4718).
float4 SampleAtlas(float2 uv, float2 cell) {
    return tex2Dlod(UnderlayAtlas, float4(AtlasUV(uv, cell), 0.0, 0.0));
}

// Atlas colors are stored without sRGB decoding, unlike the separate UnderlayAlbedo sampler.
float4 FetchAtlasAlbedo(float2 uv, float2 scale, float2 cell) {
    float4 color = SampleAtlas(uv * scale, cell);
    color.rgb = pow(abs(color.rgb), 2.2);
    return color;
}
#endif

#if IS_WVT
static const bool   g_NeedsBlendModulation = fmod(floor(g_MaterialFlags / 8), 2.0) > 0.5;
static const float3 BlendTransform[2]      = { c15.xyz, c16.xyz }; // Only with $blendmodulatetexture

float2 ApplyBlendMaskTransform(float2 uv) {
    return float2(
        dot(float3(uv, 1.0), BlendTransform[0]),
        dot(float3(uv, 1.0), BlendTransform[1]));
}

float ModulateBlend(float raw, float2 uv) {
    [branch]
    if (g_NeedsBlendModulation) {
        float4 blendModulation = SampleAtlas(uv, ATLAS_BLENDMODULATE);
        raw = smoothstep(blendModulation.g - blendModulation.r, blendModulation.g + blendModulation.r, raw);
    }
    return raw;
}
#endif

#if IS_4WAYBLEND
// Lightmapped_4WayBlend layout for $invviewprojmat.
// Each component of c15 and c16 has 8-bit values of layer 2, 3, and 4 as v2 + v3 * 256 + v4 * 65536.
//   c15: $textureN_blendstart, $textureN_blendend, $textureN_lumstart, $textureN_lumend
//   c16: $lumblendfactorN, $textureN_bumpblendfactor, $detailblendfactorN,
//        w = ($texture1_lumstart, $texture1_lumend, has $bumpmap2)
//   c17, c18: xyz = x and y of $textureN_uvscale, w = $texture3_blendmode and $texture4_blendmode
#define UNPACK_8BIT(packed, shift) (fmod(floor((packed) / (shift)), 256.0) / 255.0)
#define UNPACK_LAYERS(packed)      UNPACK_8BIT(packed, float3(1.0, 256.0, 65536.0)) // Layers 2, 3, and 4
static const float2 g_4WayLumRange1   = { UNPACK_8BIT(c16.w, 1.0), UNPACK_8BIT(c16.w, 256.0) };
static const float  g_4WayHasBumpmap2 = UNPACK_8BIT(c16.w, 65536.0);
static const float2 g_4WayUVScale2    = { c17.x, c18.x };
static const float2 g_4WayUVScale3    = { c17.y, c18.y };
static const float2 g_4WayUVScale4    = { c17.z, c18.z };
static const float  g_4WayBlendMode3  = c17.w; // 0: blend, 1: modulate 2x
static const float  g_4WayBlendMode4  = c18.w;

// Weight of the next layer from its color and the accumulated luminance,
// in the same way as lightmapped_4wayblend_ps20b.fxc.
// luminance: accumulated luminance of the lower layers, initially that of layer 1
// shift: 1, 256, and 65536 for layer 2, 3, and 4
float Next4WayLayerWeight(inout float luminance, float3 color, float vertexBlend, float shift) {
    float4 ranges = UNPACK_8BIT(c15, shift); // $textureN_blendstart, _blendend, _lumstart, _lumend
    float  layerLuminance = smoothstep(ranges.z, ranges.w, dot(color, LUMINANCE_FACTOR));
    float  lum    = lerp(1.0 - luminance, layerLuminance, UNPACK_8BIT(c16.x, shift));
    float  weight = smoothstep(ranges.x, ranges.y, vertexBlend * lum + vertexBlend);
    luminance = lerp(luminance, layerLuminance, weight);
    return weight;
}

// Blends a parameter of layer 1 toward those of layer 2, 3, and 4 in order.
float Blend4WayLayerParam(float layer1, float3 layers, float3 weights) {
    return lerp(lerp(lerp(layer1, layers.x, weights.x), layers.y, weights.y), layers.z, weights.z);
}
#endif

PsVertexInfo DecomposeInput(const PS_INPUT i) {
    PsVertexInfo v;
    v.screenUV          = (i.screenPos.xy + float2(0.5, 0.5)) * g_FbSize;
    v.worldPos          = i.vi.worldPos_ClipW.xyz;
    v.clipZ             = i.vi.vertexBlend_ClipZ.w;
    v.clipW             = i.vi.worldPos_ClipW.w;
    v.minUV             = i.vi.surfaceClipRange.xy;
    v.maxUV             = i.vi.surfaceClipRange.zw;
    v.inkUV             = float3(i.vi.inkTangent_U.w, i.vi.inkBinormal_V.w, 0.0);
    v.worldUV           = float2(i.vi.worldTangent_U.w, i.vi.worldBinormal_V.w) * g_UnderlayAlbedoSize;
    v.lightmapUV        = float2(i.vi.lightmapTangent_U.w, i.vi.lightmapBinormal_V.w);
    v.lightmapOffset    = float2(i.vi.worldNormal_dU.w, 0.0);
    v.worldTransform    = float3x3(i.vi.worldTangent_U.xyz,    i.vi.worldBinormal_V.xyz,    i.vi.worldNormal_dU.xyz);
    v.inkTransform      = float3x3(i.vi.inkTangent_U.xyz,      i.vi.inkBinormal_V.xyz,      i.vi.worldNormal_dU.xyz);
    v.lightmapTransform = float3x3(i.vi.lightmapTangent_U.xyz, i.vi.lightmapBinormal_V.xyz, i.vi.worldNormal_dU.xyz);
    v.vertexBlend       = i.vi.vertexBlend_ClipZ.xyz;
    return v;
}

float3 CalcLightmapFactors(float3 normal) {
    [branch]
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

float3 CalcFinalLightmapColor(float3 lightmapFactors, float3x3 lightmapColors) {
    float3 lightmapFinalColor = mul(lightmapFactors, lightmapColors);
    lightmapFinalColor *= rcp(max(dot(lightmapFactors, float3(1.0, 1.0, 1.0)), 1.0e-3));
    lightmapFinalColor *= g_LightmapScale;
    return lightmapFinalColor;
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

// Applies underlay $detail texture to the albedo
float4 ApplyDetailSample(float4 albedo, float4 detailSample, float factor) {
    int mode = (int)g_DetailBlendMode;
    if (mode == 0) {
        albedo.rgb *= lerp(1.0, 2.0 * detailSample.rgb, factor);
    }
    else if (mode == 1) {
        albedo.rgb += factor * pow(abs(detailSample.rgb), 2.2);
    }
    else if (mode == 2) {
        albedo.rgb = lerp(albedo.rgb, detailSample.rgb, factor * detailSample.a);
    }
    else if (mode == 3) {
        albedo = lerp(albedo, detailSample, factor);
    }
    else if (mode == 4) {
        albedo.rgb = lerp(albedo.rgb, detailSample.rgb, factor * (1.0 - albedo.a));
        albedo.a = detailSample.a;
    }
    else if (mode == 7) {
        float detailPattern = lerp(detailSample.r, detailSample.a, albedo.a);
        albedo.rgb *= lerp(1.0, 2.0 * detailPattern, factor);
    }
    else if (mode == 8) {
        albedo = lerp(albedo, albedo * detailSample, factor);
    }
    else if (mode == 9) {
        albedo.a = lerp(albedo.a, albedo.a * detailSample.a, factor);
    }
    else if (mode == 11) {
        albedo.rgb *= dot(detailSample.rgb, 2.0 / 3.0);
    }
    return albedo;
}

// Sample world bumpmap, blended as the geometry's material does
// layerWeights: GeometryAlbedo.layerWeights
float3 FetchGeometryNormal(const PsVertexInfo i, UVs uv, float3 layerWeights) {
    float2 wuv = ApplyBumpTransform(i.worldUV);
    float2 dx = ddx(wuv), dy = ddy(wuv);
    float3 geometryNormal = tex2Dgrad(UnderlayBumpmap, uv.bump, dx, dy).rgb;
#if IS_WVT
    float3 normal2 = SampleAtlas(uv.bump, ATLAS_BUMPMAP2).rgb;
    geometryNormal = lerp(geometryNormal, normal2, layerWeights.x);
#elif IS_4WAYBLEND
    // $bumpmap2 is scaled by $texture2_uvscale, and blended only if it exists.
    float3 normal2 = SampleAtlas(uv.bump * g_4WayUVScale2, ATLAS_BUMPMAP2).rgb;
    geometryNormal = lerp(geometryNormal, normal2, layerWeights.x * g_4WayHasBumpmap2);
#endif
    geometryNormal *= 2.0;
    geometryNormal -= 1.0;

    // Handle missing world bumpmap (default to flat normal)
    bool hasNoBump = geometryNormal.x == -1.0 &&
                     geometryNormal.y == -1.0 &&
                     geometryNormal.z == -1.0;
    if (hasNoBump) return float3(0.0, 0.0, 1.0);
#if IS_4WAYBLEND
    // Each layer flattens the bumpmap by $textureN_bumpblendfactor.
    // With $bumpmap2, layer 2 mixes the two normals instead.
    float3 bumpBlendFactors = UNPACK_LAYERS(c16.y);
    bumpBlendFactors.x = lerp(bumpBlendFactors.x, 1.0, g_4WayHasBumpmap2);
    float  bumpBlendFactor = Blend4WayLayerParam(1.0, bumpBlendFactors, layerWeights);
    return lerp(float3(0.0, 0.0, 1.0), normalize(geometryNormal), bumpBlendFactor);
#else
    return geometryNormal;
#endif
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

// Samples the geometry textures and blends them as the geometry's material does.
GeometryAlbedo FetchGeometryAlbedo(const PsVertexInfo i, const UVs uv) {
    float2 wuv = ApplyBaseTransform(i.worldUV);
    float4 albedo = tex2Dgrad(UnderlayAlbedo, uv.base, ddx(wuv), ddy(wuv));
    float  detailBlendFactor = g_DetailBlendFactor;
    GeometryAlbedo result;
    result.layerWeights = 0.0;
#if HAS_UNDERLAY_ATLAS
    float4 detail = g_DetailTint * SampleAtlas(uv.detail, ATLAS_DETAIL);
#else
    float2 duv = ApplyDetailTransform(i.worldUV);
    float4 detail = g_DetailTint * tex2Dgrad(UnderlayDetail, uv.detail, ddx(duv), ddy(duv));
#endif

#if IS_WVT
    result.layerWeights.x = uv.blend.x;
    albedo = lerp(albedo, FetchAtlasAlbedo(uv.base, 1.0, ATLAS_BASETEXTURE2), uv.blend.x);
#elif IS_4WAYBLEND
    // Each layer's weight depends on its color and the luminance accumulated so far, not on the blended color.
    float  luminance = smoothstep(g_4WayLumRange1.x, g_4WayLumRange1.y, dot(albedo.rgb, LUMINANCE_FACTOR));
    float4 color = FetchAtlasAlbedo(uv.base, g_4WayUVScale2, ATLAS_BASETEXTURE2);
    float3 w;
    w.x    = Next4WayLayerWeight(luminance, color.rgb, uv.blend.x, 1.0);
    albedo = lerp(albedo, color, w.x);
    color  = FetchAtlasAlbedo(uv.base, g_4WayUVScale3, ATLAS_BASETEXTURE3);
    w.y    = Next4WayLayerWeight(luminance, color.rgb, uv.blend.y, 256.0);
    albedo = lerp(albedo, color * lerp(1.0, 2.0 * albedo, g_4WayBlendMode3), w.y);
    color  = FetchAtlasAlbedo(uv.base, g_4WayUVScale4, ATLAS_BASETEXTURE4);
    w.z    = Next4WayLayerWeight(luminance, color.rgb, uv.blend.z, 65536.0);
    albedo = lerp(albedo, color * lerp(1.0, 2.0 * albedo, g_4WayBlendMode4), w.z);
    result.layerWeights = w;
    detailBlendFactor = Blend4WayLayerParam(detailBlendFactor, UNPACK_LAYERS(c16.z), w);
#endif

    result.color = ApplyDetailSample(albedo, detail, detailBlendFactor).rgb * g_Color;
    return result;
}

// Shifts the UVs of the world geometry by the parallax and the refraction.
// The first two rows of lightmapTransform are TEXINFO.lightmapVecs.
void ApplyGeometryParallax(const PsVertexInfo i, float3 worldOffset, float2 uvOffset, float2 worldUVParallax,
    inout UVs uv) {
    float2 lightmapOffset = float2(
        dot(i.lightmapTransform[0], worldOffset),
        dot(i.lightmapTransform[1], worldOffset)) * g_LightmapSize;
    uv.detail   = ApplyDetailTransform(worldUVParallax);
    uv.lightmap = i.lightmapUV + lightmapOffset;

    // The vertex blend is affine in the UV over a face. uvOffset = x * ddx(uv) + y * ddy(uv)
    // in pixel steps (x, y), which move the vertex blend by x * ddx(blend) + y * ddy(blend).
    float2 blendSteps = DecomposeBasis(ddx(i.worldUV), ddy(i.worldUV), uvOffset).xy;
    uv.blend = i.vertexBlend + ddx(i.vertexBlend) * blendSteps.x + ddy(i.vertexBlend) * blendSteps.y;
#if IS_WVT
    uv.blend.x = ModulateBlend(uv.blend.x, ApplyBlendMaskTransform(worldUVParallax));
#endif
}

// Light the world geometry receives, from the lightmap
struct GeometryLight {
    float3x3 colors;  // Lightmap samples along BumpBasis
    float3   factors; // Weights of the samples from the normal
    float3   diffuse; // Final lightmap color
};

GeometryLight EvaluateGeometryLight(const PsVertexInfo i,
    const UVs uv, float3 tangentSpaceNormal, float3 worldSpaceNormal) {
    GeometryLight light;
    light.colors  = FetchLightmapSamples(i, uv.lightmap);
    light.factors = CalcLightmapFactors(tangentSpaceNormal);
    light.diffuse = CalcFinalLightmapColor(light.factors, light.colors);
    return light;
}

// Specular from the sun, or from the light direction the bumped lightmap implies
float3 EvaluateGeometryPhong(const PsVertexInfo i, const GeometryLight light,
    float3 worldSpaceNormal, float3 viewDir, float exponent, float3x3 shadingBasis) {
    float3 phongLightDir = g_SunDirection;
    [branch]
    if (g_HasBumpedLightmap) {
        float3 strength = mul(light.colors, GrayScaleFactor);
        float3 fakeTangentLightDir = mul(strength, BumpBasis);
        float3 fakeWorldLightDir = mul(fakeTangentLightDir, shadingBasis);
        phongLightDir = lerp(g_SunDirection, fakeWorldLightDir, saturate(strength));
    }

    float spec = CalcBlinnPhongSpec(worldSpaceNormal, phongLightDir, viewDir, exponent);
    return mul(light.factors * spec, light.colors);
}

// Use average lightmap color as rim light color
float3 GeometryRimLightColor(const GeometryLight light) {
    return mul(light.factors, light.colors);
}

// The lightmap samples need the lightmap scale, which CalcFinalLightmapColor applies to the diffuse light
#define GEOMETRY_LIGHT_SCALE g_LightmapScale

// Light the flashlights cast on the ink mesh at the pixel center screenUV.
float3 SampleFlashlight(float2 screenUV) {
    return tex2Dlod(FrameBuffer, float4(screenUV.x, 0.5 + screenUV.y * 0.5, 0.0, 0.0)).rgb / g_TonemapScale;
}
