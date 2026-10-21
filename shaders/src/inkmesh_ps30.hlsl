// Ink Mesh Pixel Shader for SplashSWEPs
// Based on LightmappedGeneric pixel shader with bumped lightmaps

#include "inkmesh_common.hlsl"

// Build configurations
#define g_EnvmapEnabled
#define g_PhongEnabled
#define g_RimEnabled

// Kind of the underlay material, built as separate shaders so that the temp registers are allocated per kind.
// This file is for the materials without $basetexture2, and also for the simplified pass.
//   inkmesh_wvt_ps30.hlsl       .. WorldVertexTransition = has $basetexture2
//   inkmesh_4wayblend_ps30.hlsl .. Lightmapped_4WayBlend = has $basetexture3
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

struct PseudoPBR {
    float metallic;
    float roughness;
    float specularScale;
    float refraction;
};

struct MaterialParams {
    float  normalBlendThickness; // Thickness / HEIGHT_TO_HU, from $bumpblendheight.
    bool   usePaintLocalDetail;  // Selected from the same upper material as the detail image.
    float  height;
    float  depth;
    float3 additive;
    float3 multiplicative;
    float3 normal;
    PseudoPBR pbr;
};

struct GeometryAlbedo {
    float3 color;        // All layers blended, with $detail and $color
    float3 flashlit;     // Albedo the flashlight pass of the geometry multiplies its light by
    float3 layerWeights; // Weights of $basetexture2, 3, and 4, which also blend the bumpmaps
};

struct InkDetailSettings {
    float4 blendScale;        // $detailblendscale
    float2 uvRotationCosSin;  // Material UV rotation, decoded (cos, sin); not re-normalized.
    float2 repeatsPerHU;      // $detailtexturetransform scale / $detailperiod
    float2 translationUV;     // Offset in periods, applied after rotation.
    float2 atlasOriginPixels; // First image texel, inside the cell's wrapping border.
    float  atlasInnerSizePixels;
};

struct InkDetailEffect {
    float3 colorAdd;
    float3 emission;
    float3 normal;   // Detail normal along the projection axes U, V, and Z; need not be unit length.
    float  colorScale;
    float  specularScale;
    float  roughnessAdd;
    float  filmThickness; // Thin film thickness in nanometers
    float  filmStrength;  // Blend factor from the plain Fresnel term to the thin film one
};

static const float ALBEDO_ALPHA_MIN   = 0.0625;
static const float DIFFUSE_MIN        = 0.0625; // Diffuse factor at metallic = 100%
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
static const float ENVMAP_LOD_MAX     = 2.0;    // Envmap mip level at roughness = 100%
static const float FILM_THICKNESS_MAX = 600.0;  // Thin film thickness in nanometers at B * $detailblendscale.z = 1
static const float FILM_IOR           = 1.33;   // Refractive index of the thin film
static const float3 FILM_WAVELENGTHS  = { 650.0, 532.0, 450.0 }; // Wavelengths of R, G, B in nanometers
static const float3 LUMINANCE_FACTOR  = { 0.2125, 0.7154, 0.0721 }; // Luminance() of Lightmapped_4WayBlend
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
#if HAS_UNDERLAY_ATLAS
sampler UnderlayAtlas   : register(s5); // Built by ss.BuildUnderlayTexturePack
#else
sampler UnderlayDetail  : register(s5); // $detail
#endif
sampler Lightmap        : register(s6);
sampler Envmap          : register(s7);

static const float3  g_SunDirection       = c0.xyz; // in world space
static const float   g_DetailBlendMode    = c0.w;
static const float   g_DetailGridColumns  = c1.x;   // Number of columns in the ink detail image grid
static const float   g_MaterialFlags      = c1.y;
static const float   g_InkMapHUPerUV      = c1.z;   // Packed-surface HU per ink UV: 2 / HammerUnitsToUV
static const float2  g_LightmapSize       = c2.xy;  // One over lightmap size
static const float2  g_DetailScale        = c2.zw;
static const float3  g_Color              = c3.rgb;
static const float2  g_RTSize             = s0Size; // One over ink map size
static const float2  g_FbSize             = s2Size; // One over frame buffer size
static const float2  g_UnderlayAlbedoSize = s3Size; // One over $basetexture size
static const float3  BaseTransform[2]     = { c11.xyz, c12.xyz };
static const float3  BumpTransform[2]     = { c13.xyz, c14.xyz };
static const float4  g_DetailTint         = { c11.w, c12.w, c13.w, 1.0 };
static const float   g_DetailBlendFactor  = c14.w;
static const float   g_TonemapScale       = HDRParams.x;
static const float   g_LightmapScale      = HDRParams.y;
static const float   g_EnvmapScale        = HDRParams.z;
static const float   g_GammaScale         = HDRParams.w; // = TonemapScale ^ (1 / 2.2)

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

// Approximated thin film interference: the reflectance of each channel
// oscillates with the optical path difference between the two film surfaces.
// Returns the factor of the Fresnel term, which is 1 at zero thickness.
float3 CalcThinFilmInterference(float3 normal, float3 viewDirection, float thickness) {
    float nDotV = saturate(dot(normal, viewDirection));
    float cosT  = sqrt(saturate(1.0 - (1.0 - nDotV * nDotV) / (FILM_IOR * FILM_IOR)));
    float opd   = 2.0 * FILM_IOR * thickness * cosT;
    return 0.5 + 0.5 * cos(radians(360.0) * opd / FILM_WAVELENGTHS);
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

// Axes the ink detail image is projected along, in world space: rows are U, V, and the projection Z.
// World mode projects along the positive world axis of the largest absolute component of the mesh normal,
// and takes the other two axes in X, Y, Z order as U and V.
// Local mode takes the flattened paint coordinates used by drawink, which follow
// brush transforms and the displacement's existing paint mapping.
// Derived from the vertex inputs where needed, as carrying them takes too many temp registers.
float3x3 GetDetailProjectionBasis(const PsVertexInfo i, bool usePaintLocalDetail) {
    if (usePaintLocalDetail) {
        return float3x3(
            normalize(i.inkTransform[0]),
            normalize(i.inkTransform[1]),
            normalize(i.worldTransform[2]));
    }

    float3 absNormal = abs(i.worldTransform[2]);
    if (absNormal.x >= absNormal.y && absNormal.x >= absNormal.z) {
        return float3x3(0, 1, 0,  0, 0, 1,  1, 0, 0);
    }
    else if (absNormal.y >= absNormal.z) {
        return float3x3(1, 0, 0,  0, 0, 1,  0, 1, 0);
    }
    else {
        return float3x3(1, 0, 0,  0, 1, 0,  0, 0, 1);
    }
}

// Partial derivative blending of the detail normal, evaluated in world space.
// Permuting the base normal N into the projection space, adding the detail slopes,
// and permuting the result back is equivalent to:
//   detail Z * N + (N's component along the projection axis) * detail slopes in world
// The result is not normalized. The length of worldNormal cancels at final normalization.
// basis: GetDetailProjectionBasis
float3 ApplyDetailNormalWorld(float3 worldNormal, InkDetailEffect detail, float3x3 basis) {
    float3 slopeWorld = detail.normal.x * basis[0] + detail.normal.y * basis[1];
    float3 n = detail.normal.z * worldNormal + dot(worldNormal, basis[2]) * slopeWorld;
    return dot(n, n) == 0.0 ? worldNormal : n;
}

float2 ApplyBaseTransform(float2 uv) {
    return float2(
        dot(float3(uv, 1.0), BaseTransform[0]),
        dot(float3(uv, 1.0), BaseTransform[1]));
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

// Samples only height value
float FetchHeight(float2 uv) {
    float4 s = tex2Dlod(InkMap, float4(uv + INKMAP_HEIGHT_DEPTH, 0.0, 0.0));
    return TO_SIGNED(DecodeUnorm16(s.rg));
}

// Samples additive color with gamma correction
float3 FetchAdditive(float2 uv) {
    float4 s = tex2Dlod(InkMap, float4(uv + INKMAP_ADDITIVE, 0.0, 0.0));
    return pow(abs(s.rgb), 2.2);
}

// Samples multiplicative color with gamma correction
float3 FetchMultiplicative(float2 uv) {
    float4 s = tex2Dlod(InkMap, float4(uv + INKMAP_MULTIPLICATIVE, 0.0, 0.0));
    return pow(abs(s.rgb), 2.2);
}

// Samples height value and ground depth, and calculates the ink normal from the height
void FetchHeightDepthAndNormal(const PsVertexInfo i, float2 uv, inout MaterialParams params) {
    float4 s = tex2Dlod(InkMap, float4(uv + INKMAP_HEIGHT_DEPTH, 0.0, 0.0));
    params.height = TO_SIGNED(DecodeUnorm16(s.rg));
    params.depth  = DecodeUnorm16(s.ba);

    // Forward differences of the height over deltaUV, in Hammer units per ink map UV.
    float2 deltaUV = g_RTSize * 2.0;
    float2 hxy = {
        FetchHeight(uv + float2(deltaUV.x, 0.0)),
        FetchHeight(uv + float2(0.0, deltaUV.y)),
    };

    // The first two rows of inkTransform are the world gradients of ink map U and V.
    // Chain rule: the height field's world normal is N - (dz/du * grad(u) + dz/dv * grad(v)).
    float2 slope = (hxy - params.height) * HEIGHT_TO_HU / deltaUV;
    params.normal = normalize(mul(float3(-slope, 1.0), i.inkTransform));
}

// Fetch blended lighting/thickness; select the upper material's local-detail flag without blending it.
void FetchInkMaterialParams(float3 IDs, inout MaterialParams params) {
    float4 s;
    int id1 = (int)IDs.x;
    int id2 = (int)IDs.y;
    float idBlend = IDs.z;

    s = FetchDataPixel(InkDataDetail, id1, ID_MATERIAL_REFRACT);
    params.pbr.metallic      = s.r;
    params.pbr.roughness     = s.g;
    params.pbr.specularScale = s.b;
    params.pbr.refraction    = s.a;
    s = FetchDataPixel(InkDataDetail, id2, ID_MATERIAL_REFRACT);
    params.pbr.metallic      = lerp(params.pbr.metallic,      s.r, idBlend);
    params.pbr.roughness     = lerp(params.pbr.roughness,     s.g, idBlend);
    params.pbr.specularScale = lerp(params.pbr.specularScale, s.b, idBlend);
    params.pbr.refraction    = lerp(params.pbr.refraction,    s.a, idBlend);

    float4 misc1 = FetchDataPixel(InkDataDetail, id1, ID_MISC);
    float4 misc2 = FetchDataPixel(InkDataDetail, id2, ID_MISC);
    params.normalBlendThickness = lerp(misc1.b, misc2.b, idBlend);
    params.usePaintLocalDetail = frac((id2 > 0 ? misc2.a : misc1.a) * 4.0) >= 0.5;
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
    // The flashlight pass of Lightmapped_4WayBlend only takes the first layer (garrysmod-issues #6549).
    result.flashlit = ApplyDetailSample(albedo, detail, detailBlendFactor).rgb * g_Color;

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
#if !IS_4WAYBLEND
    result.flashlit = result.color;
#endif
    return result;
}

// Lit geometry color: the frame buffer, or the geometry albedo lit by lightmapFinalColor where it's unavailable.
// extraLight: light the frame buffer received on top of geometryLightmapColor, e.g. flashlights.
float3 EvaluateGeometryLighting(const UVs uv, const GeometryAlbedo albedo,
    float3 lightmapFinalColor, float3 geometryLightmapColor, out float3 extraLight) {
    float fbRatio = uv.edgefade;
    float4 fb = tex2Dlod(FrameBuffer, float4(uv.screen, 0.0, 0.0));
    if (fb.a * DEPTHWRITE_TO_HU < uv.depth - max(2.0, uv.depth * 0.015)) {
        fbRatio = 0.0;
    }

    // Solve fb = albedo.color * geometryLightmapColor + albedo.flashlit * extraLight per channel,
    // as LightmappedGeneric's flashlight pass multiplies its light by each albedo channel.
    // Anything else in fb, e.g. specular, envmap, or emission, counts as light too.
    // A channel with zero albedo shows no flashlight, but SAFERCP multiplies any residual there by 1e16.
    extraLight = max(fb.rgb - albedo.color * geometryLightmapColor, 0.0) * SAFERCP(albedo.flashlit) * fbRatio;
    return lerp(albedo.color * lightmapFinalColor, fb.rgb, fbRatio);
}

// Sample the upper material's image and evaluate its normal/color/lighting effects.
// Discrete placement comes from texel centers; image position uses the continuous parallax hit.
InkDetailEffect EvaluateInkDetail(const PsVertexInfo i, float3 IDs, int modeRotationByte,
    float3 inkUV, float height, float depth, bool usePaintLocalDetail) {
    InkDetailEffect effect = (InkDetailEffect)0;
    effect.colorScale    = 1.0;
    effect.specularScale = 1.0;
    effect.normal        = float3(0.0, 0.0, 1.0);
    int paintRotationCode5 = modeRotationByte / 8;
    int mode = modeRotationByte - paintRotationCode5 * 8;
    if (mode == DETAIL_MODE_NONE) return effect;
    int id  = (int)(IDs.y > 0.0 ? IDs.y : IDs.x);

    // Project detail sample position onto the 2D plane of the projection axes
    float3x3 projectionBasis = GetDetailProjectionBasis(i, usePaintLocalDetail);

    // The parallax ray's Z is in HEIGHT_TO_HU units along the mesh normal.
    // Evaluate the display texture at that hit, not at the unshifted mesh pixel.
    float3 viewVec = g_EyePos.xyz - i.worldPos;
    float3 worldPos = i.worldPos + viewVec * inkUV.z * HEIGHT_TO_HU * SAFERCP(dot(viewVec, i.worldTransform[2]));
    float2 projectionPositionHU = float2(dot(worldPos, projectionBasis[0]), dot(worldPos, projectionBasis[1]));
    float2 mapToPaintCosSin = float2(1.0, 0.0); // World mode keeps the projection axes.
    float2 phase = 0.0;
    [branch]
    if (usePaintLocalDetail) {
        // The same flattened paint coordinates used by drawink, including atlas placement.
        projectionPositionHU = inkUV.xy * g_InkMapHUPerUV;
        mapToPaintCosSin = DecodeInkMapToPaintCosSin(paintRotationCode5);
        float2 phaseUV = (floor(inkUV.xy / g_RTSize) + 0.5) * g_RTSize;
        phase.x = tex2Dlod(InkMap, float4(phaseUV + INKMAP_ADDITIVE, 0.0, 0.0)).a;
        phase.y = tex2Dlod(InkMap, float4(phaseUV + INKMAP_MULTIPLICATIVE, 0.0, 0.0)).a;
    }

    InkDetailSettings settings;
    float4 encodedTransform       = FetchDataPixel(InkDataDetail, id, ID_DETAIL_TRANSFORM);
    float4 encodedScaleRow        = FetchDataPixel(InkDataDetail, id, ID_DETAIL_SCALE);
    float  gridIndex              = round(encodedScaleRow.z * 255.0);
    float  gridRow                = floor((gridIndex + 0.5) / g_DetailGridColumns);
    float  gridColumn             = gridIndex - gridRow * g_DetailGridColumns;
    float  cellSizePixels         = g_InkDataOffsetV / g_DetailGridColumns;
    settings.uvRotationCosSin     = encodedTransform.zw * (255.0 / 127.0) - 1.0; // 127 / 255 encodes zero
    settings.repeatsPerHU         = exp2(encodedScaleRow.xy * (255.0 / 24.0) - 13.0); // 24 steps per octave
    settings.translationUV        = encodedTransform.xy;
    settings.atlasOriginPixels    = float2(gridColumn, gridRow) * cellSizePixels + 1.0;
    settings.atlasInnerSizePixels = cellSizePixels - 2.0;
    settings.blendScale           = FetchDataPixel(InkDataDetail, id, ID_DETAIL_BLEND_SCALE) * (255.0 / 127.0);

    // Local mode: ink-map HU -> paint HU; world mode keeps the projection axes unchanged.
    float2 paintPositionHU = float2(
        mapToPaintCosSin.x * projectionPositionHU.x - mapToPaintCosSin.y * projectionPositionHU.y,
        mapToPaintCosSin.y * projectionPositionHU.x + mapToPaintCosSin.x * projectionPositionHU.y);
    float2 scaledUV = paintPositionHU * settings.repeatsPerHU;
    float2 rotatedUV = float2(
        settings.uvRotationCosSin.x * scaledUV.x - settings.uvRotationCosSin.y * scaledUV.y,
        settings.uvRotationCosSin.y * scaledUV.x + settings.uvRotationCosSin.x * scaledUV.y);
    float2 repeatedUV   = frac(rotatedUV + settings.translationUV + phase);
    float2 atlasUV      = (settings.atlasOriginPixels + repeatedUV * settings.atlasInnerSizePixels) * g_DataRTSize;
    float4 detailSample = tex2Dlod(InkDataDetail, float4(atlasUV, 0, 0));

    // Convert the sample to the value range of each mode, then apply $detailblendscale to all channels.
    // RG of the normal modes stores normal XY. Reconstruct Z before the scale steepens XY.
    float4 s = detailSample;
    if (mode == DETAIL_MODE_MATERIAL) s     = TO_SIGNED(s);
    if (mode == DETAIL_MODE_NORMAL)   s.rgb = TO_SIGNED(s.rgb);
    if (mode == DETAIL_MODE_THINFILM) s.rg  = TO_SIGNED(s.rg);
    float normalZ = sqrt(saturate(1.0 - dot(s.xy, s.xy)));
    s *= settings.blendScale;

    [branch]
    if (mode == DETAIL_MODE_MATERIAL || mode == DETAIL_MODE_NORMAL || mode == DETAIL_MODE_THINFILM) {
        // Transpose the material UV rotation, then the ink-map -> paint rotation, without rescaling XY.
        float2 normalXYInPaint = float2(
            settings.uvRotationCosSin.x * s.x + settings.uvRotationCosSin.y * s.y,
           -settings.uvRotationCosSin.y * s.x + settings.uvRotationCosSin.x * s.y);
        float2 paintToMapCosSin = float2(mapToPaintCosSin.x, -mapToPaintCosSin.y);
        float2 normalXYInProjection = float2(
            paintToMapCosSin.x * normalXYInPaint.x - paintToMapCosSin.y * normalXYInPaint.y,
            paintToMapCosSin.y * normalXYInPaint.x + paintToMapCosSin.x * normalXYInPaint.y);
        effect.normal = float3(normalXYInProjection, normalZ);
    }

    [branch]
    if (mode == DETAIL_MODE_MATERIAL) {
        effect.colorScale   = max(0.0, 1.0 + s.a);
        effect.roughnessAdd = s.b;
    }
    else if (mode == DETAIL_MODE_NORMAL) {
        effect.specularScale = s.a;
    }
    else if (mode == DETAIL_MODE_EMISSION) {
        effect.emission = s.rgb * s.a;
    }
    else if (mode == DETAIL_MODE_COLOR) {
        effect.colorScale = 1.0 - s.a;
        effect.colorAdd   = s.rgb * s.a;
    }
    else if (mode == DETAIL_MODE_THINFILM) {
        effect.filmThickness = s.b * FILM_THICKNESS_MAX;
        effect.filmStrength  = saturate(s.a);
    }

    float heightBlendByte        = round(encodedScaleRow.w * 255.0);
    float heightLimitSqrtCode5   = floor(heightBlendByte / 8.0);
    float heightSourceInvertBits = heightBlendByte - heightLimitSqrtCode5 * 8.0;
    float heightSource           = floor(heightSourceInvertBits / 2.0);
    [branch]
    if (heightSource > 0.0) {
        // Source 1 = thickness, 2 = height, 3 = ground depth; all in HEIGHT_TO_HU units.
        float heightBlendInput = heightSource < 1.5 ? height + depth
                               : heightSource < 2.5 ? height : depth;
        // The stored limit is sqrt(maxHU / HEIGHT_TO_HU), quantized to a nonzero 5-bit level.
        float heightLimitSqrt = (heightLimitSqrtCode5 + 1.0) / 32.0;
        float heightWeight = saturate(heightBlendInput / (heightLimitSqrt * heightLimitSqrt));
        if (heightSourceInvertBits - heightSource * 2.0 > 0.5)
            heightWeight = 1.0 - heightWeight;

        effect.normal        = lerp(float3(0.0, 0.0, 1.0), effect.normal, heightWeight);
        effect.roughnessAdd *= heightWeight;
        effect.specularScale = lerp(1.0, effect.specularScale, heightWeight);
        effect.colorScale    = lerp(1.0, effect.colorScale, heightWeight);
        effect.colorAdd     *= heightWeight;
        effect.emission     *= heightWeight;
        effect.filmStrength *= heightWeight;
    }

    return effect;
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

// interfaceNormal: world normal of the ink surface, without the underlay bumpmap
UVs ApplyParallaxGeometry(const PsVertexInfo i, const MaterialParams params, float3 interfaceNormal) {
    UVs uv;
    float3 meshNormal = i.worldTransform[2];
    float3 viewVec    = g_EyePos.xyz - i.worldPos;

    // Straight view ray reaching the ground at params.depth below the mesh, in Hammer units
    float  viewVecZ = max(dot(viewVec, meshNormal) / HEIGHT_TO_HU, 1.0e-3);
    float3 parallax = -viewVec * params.depth / viewVecZ;

    // Approximated refraction: the view ray shifts against the interface slope,
    // in proportion to the liquid thickness (interface height + ground depth).
    float  thickness      = (params.height + params.depth) * HEIGHT_TO_HU;
    float3 interfaceSlope = interfaceNormal - meshNormal * dot(interfaceNormal, meshNormal);
    float3 refraction     = -thickness * params.pbr.refraction * interfaceSlope;

    // Rows of the transforms are the world gradients of texels: TEXINFO.textureVecs and TEXINFO.lightmapVecs
    float3 worldOffset = parallax + refraction;
    float2 uvOffset = float2(
        dot(i.worldTransform[0], worldOffset),
        dot(i.worldTransform[1], worldOffset)) * g_UnderlayAlbedoSize;
    float2 lightmapOffset = float2(
        dot(i.lightmapTransform[0], worldOffset),
        dot(i.lightmapTransform[1], worldOffset)) * g_LightmapSize;
    float2 worldUVParallax = i.worldUV + uvOffset;
    uv.base     = ApplyBaseTransform(worldUVParallax);
    uv.bump     = ApplyBumpTransform(worldUVParallax);
    uv.detail   = ApplyDetailTransform(worldUVParallax);
    uv.lightmap = i.lightmapUV + lightmapOffset;

    // The vertex blend is affine in the UV over a face. uvOffset = x * ddx(uv) + y * ddy(uv)
    // in pixel steps (x, y), which move the vertex blend by x * ddx(blend) + y * ddy(blend).
    float2 blendSteps = DecomposeBasis(ddx(i.worldUV), ddy(i.worldUV), uvOffset).xy;
    uv.blend = i.vertexBlend + ddx(i.vertexBlend) * blendSteps.x + ddy(i.vertexBlend) * blendSteps.y;
#if IS_WVT
    uv.blend.x = ModulateBlend(uv.blend.x, ApplyBlendMaskTransform(worldUVParallax));
#endif

    float2 offset = ProjectiveUVToScreenOffset(i.worldUV, i.worldUV + uvOffset, i.clipW);
    float2 s      = i.screenUV + offset * g_FbSize;
    uv.edgefade   = ScreenEdgeFade(s);
    uv.screen     = saturate(s);
    uv.depth      = i.clipW + ddx(i.clipW) * offset.x + ddy(i.clipW) * offset.y;
    return uv;
}

PS_OUTPUT main(const PS_INPUT rawInput) {
    PsVertexInfo i = DecomposeInput(rawInput);
    float sceneViewDepthHU = tex2Dlod(FrameBuffer, float4(i.screenUV, 0.0, 0.0)).a * DEPTHWRITE_TO_HU;
    float depthToleranceHU = max(2.0, i.clipW * 0.015);
    clip(sceneViewDepthHU - i.clipW + depthToleranceHU);

    // Z = final ray marching height
    float3 inkUV   = g_Simplified ? i.inkUV : ApplyParallaxInk(i);
    float3 viewVec = g_EyePos.xyz - i.worldPos;
    float3 viewDir = normalize(viewVec);
    float2 pixelUV = (floor(inkUV.xy / g_RTSize) + 0.5) * g_RTSize + INKMAP_INDICES;
    float4 inkIDs  = tex2Dlod(InkMap, float4(pixelUV, 0.0, 0.0));
    float3 IDs     = { round(inkIDs.r * 255.0), round(inkIDs.g * 255.0), inkIDs.b };
    int detailModeRotationByte = (int)round(inkIDs.a * 255.0);
    clip(floor(IDs.x + IDs.y + IDs.z) - 0.5);

    // Samples ink parameters
    MaterialParams params;
    params.additive = FetchAdditive(inkUV.xy);
    params.multiplicative = FetchMultiplicative(inkUV.xy);
    FetchHeightDepthAndNormal(i, inkUV.xy, params);
    FetchInkMaterialParams(IDs, params);

    InkDetailEffect detail = EvaluateInkDetail(i, IDs,
        detailModeRotationByte, inkUV, params.height, params.depth, params.usePaintLocalDetail);
    float3 inkColor = params.additive * detail.colorScale + detail.colorAdd;
    params.pbr.roughness = saturate(params.pbr.roughness + detail.roughnessAdd);
    params.pbr.specularScale *= detail.specularScale;
    params.multiplicative *= detail.colorScale;

    // The ink interface refracts the underlay, regardless of the underlay bumpmap
    float3 interfaceNormal = normalize(
        ApplyDetailNormalWorld(params.normal, detail,
        GetDetailProjectionBasis(i, params.usePaintLocalDetail)));
    UVs uv = ApplyParallaxGeometry(i, params, interfaceNormal);
    GeometryAlbedo geometryAlbedo = FetchGeometryAlbedo(i, uv);

    // Match Source's shading basis without changing the UV gradients used by parallax.
    float3 normal = normalize(i.worldTransform[2]);
    float3 tangent = normalize(cross(normal, i.worldTransform[1]));
    float3 binormal = normalize(cross(tangent, normal));
    if (dot(normal, cross(i.worldTransform[0], i.worldTransform[1])) > 0.0)
        tangent = -tangent;
    float3x3 shadingBasis = float3x3(tangent, binormal, normal);

    // Blend ink and world normals in world space.
    float3 geometryNormal      = normalize(FetchGeometryNormal(i, uv, geometryAlbedo.layerWeights));
    float3 geometryNormalWorld = mul(geometryNormal, shadingBasis);
    float  inkNormalWeight     = saturate((params.height + params.depth) * SAFERCP(params.normalBlendThickness));
    float3 blendedNormal       = lerp(geometryNormal, params.normal, inkNormalWeight);
    float3 worldSpaceNormal    = normalize(ApplyDetailNormalWorld(blendedNormal, detail,
        GetDetailProjectionBasis(i, params.usePaintLocalDetail)));
    float3 tangentSpaceNormal  = normalize(mul(shadingBasis, worldSpaceNormal));

    // Calculate diffuse color
    float3x3 lightmapColors  = FetchLightmapSamples(i, uv.lightmap);
    float3   lightmapFactors = CalcLightmapFactors(tangentSpaceNormal);
    float3   lightmapFinal   = CalcFinalLightmapColor(lightmapFactors, lightmapColors);

    // The frame buffer is lit with the geometry's own normal, not the ink's.
    float3 extraLight;
    float3 geometryLit = params.multiplicative * EvaluateGeometryLighting(uv, geometryAlbedo, lightmapFinal,
        CalcFinalLightmapColor(CalcLightmapFactors(geometryNormalWorld), lightmapColors), extraLight);

    // Modulate surface albedo and add ink color
    float3 ambientOcclusion = { 1.0, 1.0, 1.0 }; // dummy!
    float  diffuseScale = lerp(1.0, DIFFUSE_MIN, params.pbr.metallic);
    float3 inkLit = inkColor * lightmapFinal;
    float3 albedo = geometryLit + inkLit;
    float3 result = albedo * diffuseScale + detail.emission;

    // Simplified pass doesn't need specular component
    if (g_Simplified) {
        PS_OUTPUT output = (PS_OUTPUT)0.0;
        output.finalColorWithoutSSR = float4(result * g_TonemapScale, 1.0);
        return output;
    }

    // Flashlight / projected texture estimation
    result += inkColor * extraLight * diffuseScale;

    // ^ Diffuse component (multiplies to the final result)
    // -------------------------------------------------------------------------
    // v Specular component (accumulates to the final result)

    // Fresnel term shared by the specular and the reflection, tinted by the thin film interference
    float3 fresnel = CalcFresnel(worldSpaceNormal, viewDir, lerp(FRESNEL_MIN, albedo, params.pbr.metallic));
    [branch]
    if (detail.filmStrength > 0.0) {
        float3 interference = CalcThinFilmInterference(worldSpaceNormal, viewDir, detail.filmThickness);
        fresnel *= lerp(1.0, interference, detail.filmStrength);
    }

#ifdef g_PhongEnabled
    float  phongExponent = lerp(PHONG_EXPONENT_MIN, PHONG_EXPONENT_MAX, params.pbr.roughness);
    float3 phongLightDir = g_SunDirection;
    [branch]
    if (g_HasBumpedLightmap) {
        float3 strength = mul(lightmapColors, GrayScaleFactor);
        float3 fakeTangentLightDir = mul(strength, BumpBasis);
        float3 fakeWorldLightDir = mul(fakeTangentLightDir, shadingBasis);
        phongLightDir = lerp(g_SunDirection, fakeWorldLightDir, saturate(strength));
    }

    float spec = CalcBlinnPhongSpec(worldSpaceNormal, phongLightDir, viewDir, phongExponent);
    float3 phongSpecular = mul(lightmapFactors * spec, lightmapColors);
    phongSpecular *= fresnel;
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
        (RIMLIGHT_FADE_MAX - i.clipZ) /
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
    // Rougher surfaces read the coarser mip levels of the envmap
    float3 envmapSample  = texCUBElod(Envmap, float4(reflectDir, params.pbr.roughness * ENVMAP_LOD_MAX)).rgb * g_EnvmapScale;
    float3 envmapAlbedo  = lerp(float3(1.0, 1.0, 1.0), albedo, params.pbr.metallic);
    float3 reflectionWeight = envmapAlbedo;
    reflectionWeight *= fresnel;
    reflectionWeight *= ambientOcclusion;
    reflectionWeight *= params.pbr.specularScale;
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
