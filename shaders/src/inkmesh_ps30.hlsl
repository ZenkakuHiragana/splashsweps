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

struct MaterialParams {
    float  bumpBlendFactor;
    float  height;
    float  depth;
    float3 additive;
    float3 multiplicative;
    float3 normal;
    PseudoPBR pbr;
};

struct InkDetailSettings {
    float4 blendscale; // $detailblendscale
    float2 rotation;   // (x, y) = (cosθ, sinθ)
    float2 scale;      // $detailtexturetransform scale / $detailperiod = image repeats per Hammer unit
    float2 translation;
    float2 atlasOrigin;
    float  atlasSize;
};

struct InkDetailEffect {
    float3 colorAdd;
    float3 emission;
    float3 normalSlope;    // Detail normal XY assigned to the world axes of the projection plane.
    float  normalZ;        // Detail normal Z. The detail normal need not be unit length.
    float3 projectionAxis; // World axis used as projection Z.
    float  colorScale;
    float  specularScale;
    float  roughnessAdd;
    float  filmThickness;  // Thin film thickness in nanometers
    float  filmStrength;   // Blend factor from the plain Fresnel term to the thin film one
};

static const float ALBEDO_ALPHA_MIN   = 0.0625;
static const float DIFFUSE_MIN        = 0.0625; // Diffuse factor at metallic = 100%
static const float ENVMAP_SCALE       = 0.5;    // Envmap factor
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
static const float3 GrayScaleFactor   = { 0.2126, 0.7152, 0.0722 };
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
static const float   g_DetailGridColumns  = c1.x;   // Number of columns in the ink detail image grid
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

// Approximated thin film interference: the reflectance of each channel
// oscillates with the optical path difference between the two film surfaces.
// Returns the factor of the Fresnel term, which is 1 at zero thickness.
float3 CalcThinFilmInterference(float3 normal, float3 viewDirection, float thickness) {
    float nDotV  = saturate(dot(normal, viewDirection));
    float cosT   = sqrt(saturate(1.0 - (1.0 - nDotV * nDotV) / (FILM_IOR * FILM_IOR)));
    float opd    = 2.0 * FILM_IOR * thickness * cosT;
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

// Partial derivative blending of the detail normal, evaluated in world space.
// Permuting the base normal N into the projection space, adding the detail slopes,
// and permuting the result back is equivalent to:
//   detail Z * N + (N's component along the projection axis) * detail slopes in world
// The result is not normalized. The length of worldNormal cancels at final normalization.
float3 ApplyInkDetailNormal(float3 worldNormal, InkDetailEffect detail) {
    float3 n = detail.normalZ * worldNormal
        + dot(worldNormal, detail.projectionAxis) * detail.normalSlope;
    return dot(n, n) == 0.0 ? worldNormal : n;
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

// Applies underlay $detail texture to the albedo
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

// x: $bumpblendfactor, y: 1 if $edgecolor is set, 0 otherwise
float2 DecodeEdgeBumpBlend(float a) {
    float bits = round(a * 255.0);
    float edgeEnabled = step(128.0, bits);
    return float2((bits - 128.0 * edgeEnabled) / 127.0, edgeEnabled);
}

// Samples lighting parameters from texture sampler
// and replaces the additive color of thin ink with $edgecolor
void FetchInkMaterial(float3 IDs, inout MaterialParams params) {
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

    float4 edge1 = FetchDataPixel(InkDataDetail, id1, ID_EDGE_BUMPBLND);
    float4 edge2 = FetchDataPixel(InkDataDetail, id2, ID_EDGE_BUMPBLND);
    float2 edgeBumpBlend1 = DecodeEdgeBumpBlend(edge1.a);
    float2 edgeBumpBlend2 = DecodeEdgeBumpBlend(edge2.a);
    params.bumpBlendFactor = lerp(edgeBumpBlend1.x, edgeBumpBlend2.x, idBlend);

    // The edge color turns into the ink color as the thickness reaches the larger $maxheight of the inks
    [branch]
    if (lerp(edgeBumpBlend1.y, edgeBumpBlend2.y, idBlend) > 0.0) {
        float maxHeight1 = FetchDataPixel(InkDataDetail, id1, ID_HEIGHT_MAXLAYERS).y;
        float maxHeight2 = FetchDataPixel(InkDataDetail, id2, ID_HEIGHT_MAXLAYERS).y;
        float thickness  = max(0.0, params.height + params.depth);
        float edge       = 1.0 - saturate(thickness * SAFERCP(max(maxHeight1, maxHeight2)));
        params.additive += edge * lerp(
            edgeBumpBlend1.y * (pow(abs(edge1.rgb), 2.2) - params.additive),
            edgeBumpBlend2.y * (pow(abs(edge2.rgb), 2.2) - params.additive),
            idBlend);
    }
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

// mode: $detailblendmode of the upper layer, stored in the ink map with the IDs
InkDetailEffect FetchInkDetails(const PsVertexInfo i, float3 IDs, int mode, float3 inkUV) {
    InkDetailEffect effect = (InkDetailEffect)0;
    effect.colorScale    = 1.0;
    effect.specularScale = 1.0;
    effect.normalZ       = 1.0;
    if (mode == DETAIL_MODE_NONE) return effect;
    int id  = (int)(IDs.y > 0.0 ? IDs.y : IDs.x);

    // Project detail sample position onto axis-aligned 2D plane
    float3 projectionWorldU, projectionWorldV;
    float3 absNormal = abs(i.worldTransform[2]);
    if (absNormal.x >= absNormal.y && absNormal.x >= absNormal.z) {
        projectionWorldU      = float3(0, 1, 0);
        projectionWorldV      = float3(0, 0, 1);
        effect.projectionAxis = float3(1, 0, 0);
    }
    else if (absNormal.y >= absNormal.z) {
        projectionWorldU      = float3(1, 0, 0);
        projectionWorldV      = float3(0, 0, 1);
        effect.projectionAxis = float3(0, 1, 0);
    }
    else {
        projectionWorldU      = float3(1, 0, 0);
        projectionWorldV      = float3(0, 1, 0);
        effect.projectionAxis = float3(0, 0, 1);
    }

    // The parallax ray's Z is in HEIGHT_TO_HU units along the mesh normal.
    // Evaluate the display texture at that hit, not at the unshifted mesh pixel.
    float3 viewVec = g_EyePos.xyz - i.worldPos;
    float3 worldPos = i.worldPos + viewVec * inkUV.z * HEIGHT_TO_HU * SAFERCP(dot(viewVec, i.worldTransform[2]));
    float2 projectionPos = float2(dot(worldPos, projectionWorldU), dot(worldPos, projectionWorldV));

    InkDetailSettings settings;
    float4 encodedTransform = FetchDataPixel(InkDataDetail, id, ID_DETAIL_TRANSFORM);
    float4 encodedScale     = FetchDataPixel(InkDataDetail, id, ID_DETAIL_SCALE);
    float  gridIndex        = round(encodedScale.z * 255.0);
    float  gridRow          = floor((gridIndex + 0.5) / g_DetailGridColumns);
    float  gridColumn       = gridIndex - gridRow * g_DetailGridColumns;
    float  cellSize         = g_InkDataOffsetV / g_DetailGridColumns;
    settings.rotation    = encodedTransform.zw * (255.0 / 127.0) - 1.0;   // 127 / 255 encodes zero
    settings.scale       = exp2(encodedScale.xy * (255.0 / 24.0) - 13.0); // 24 steps per octave from 2^-13
    settings.translation = encodedTransform.xy;
    settings.atlasOrigin = float2(gridColumn, gridRow) * cellSize + 1.0;
    settings.atlasSize   = cellSize - 2.0;
    settings.blendscale  = FetchDataPixel(InkDataDetail, id, ID_DETAIL_BLEND_SCALE) * (255.0 / 127.0);

    float2 scaledPosition  = projectionPos * settings.scale;
    float2 rotatedPosition = {
        settings.rotation.x * scaledPosition.x - settings.rotation.y * scaledPosition.y,
        settings.rotation.y * scaledPosition.x + settings.rotation.x * scaledPosition.y,
    };
    float2 repeatedUV   = frac(rotatedPosition + settings.translation);
    float2 atlasUV      = (settings.atlasOrigin + repeatedUV * settings.atlasSize) * g_DataRTSize;
    float4 detailSample = tex2Dlod(InkDataDetail, float4(atlasUV, 0, 0));

    // Convert the sample to the value range of each mode, then apply $detailblendscale to all channels.
    // RG of the normal modes stores normal XY. Reconstruct Z before the scale steepens XY.
    float4 s = detailSample;
    if (mode == DETAIL_MODE_MATERIAL) s     = TO_SIGNED(s);
    if (mode == DETAIL_MODE_NORMAL)   s.rgb = TO_SIGNED(s.rgb);
    if (mode == DETAIL_MODE_THINFILM) s.rg  = TO_SIGNED(s.rg);
    float normalZ = sqrt(saturate(1.0 - dot(s.xy, s.xy)));
    s *= settings.blendscale;

    [branch]
    if (mode == DETAIL_MODE_MATERIAL || mode == DETAIL_MODE_NORMAL || mode == DETAIL_MODE_THINFILM) {
        // Undo image rotation, then assign XY to the world axes of the projection plane.
        float2 slope = {
            settings.rotation.x * s.x + settings.rotation.y * s.y,
           -settings.rotation.y * s.x + settings.rotation.x * s.y,
        };
        effect.normalSlope = slope.x * projectionWorldU + slope.y * projectionWorldV;
        effect.normalZ     = normalZ;
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
    float2 pixelUV = (floor(inkUV.xy / g_RTSize) + 0.5) * g_RTSize + INKMAP_INDICES;
    float4 inkIDs  = tex2Dlod(InkMap, float4(pixelUV, 0.0, 0.0));
    float3 IDs     = { round(inkIDs.r * 255.0), round(inkIDs.g * 255.0), inkIDs.b };
    int detailMode = (int)round(inkIDs.a * 255.0);
    clip(floor(IDs.x + IDs.y + IDs.z) - 0.5);

    // Samples ink parameters
    MaterialParams params;
    params.additive = FetchAdditive(inkUV.xy);
    params.multiplicative = FetchMultiplicative(inkUV.xy);
    FetchHeightDepthAndNormal(i, inkUV.xy, params);
    FetchInkMaterial(IDs, params);

    InkDetailEffect detail    = FetchInkDetails(i, IDs, detailMode, inkUV);
    params.pbr.roughness      = saturate(params.pbr.roughness + detail.roughnessAdd);
    params.pbr.specularScale *= detail.specularScale;
    params.multiplicative    *= detail.colorScale;
    params.additive          *= detail.colorScale;

    // The ink interface refracts the underlay, regardless of the underlay bumpmap
    float3 interfaceNormal = normalize(ApplyInkDetailNormal(params.normal, detail));
    UVs    uv              = ApplyParallaxGeometry(i, params, interfaceNormal);

    // Blend ink and world normals in world space
    float3 geometryNormal   = normalize(mul(FetchGeometryNormal(i, uv), i.worldTransform));
    float3 blendedNormal    = lerp(geometryNormal, params.normal, params.bumpBlendFactor);
    float3 worldSpaceNormal = normalize(ApplyInkDetailNormal(blendedNormal, detail));

    // The mesh carries texture vectors, not necessarily an orthonormal basis.
    // Solve tangent * worldTransform = world normal, rather than using its transpose as inverse.
    float3 tangentSpaceNormal = normalize(SolveBasisDirection(
        i.worldTransform[0], i.worldTransform[1], i.worldTransform[2], worldSpaceNormal));

    // Calculate diffuse color
    float3   lightmapFactors = CalcLightmapFactors(tangentSpaceNormal);
    float3x3 lightmapColors  = FetchLightmapSamples(i, uv.lightmap);
    float3   lightmapFinal   = CalcFinalLightmapColor(lightmapColors, lightmapFactors);
    float3   geometryLit     = FetchGeometrySamples(i, uv, lightmapFinal) * params.multiplicative;
    float3   inkLit          = (params.additive + detail.colorAdd) * lightmapFinal;
    float3   albedo          = geometryLit + inkLit;

    // Modulate surface albedo and add ink color
    float3 ambientOcclusion = { 1.0, 1.0, 1.0 }; // dummy!
    float3 result = albedo * lerp(1.0, DIFFUSE_MIN, params.pbr.metallic) + detail.emission;

    // Simplified pass doesn't need specular component
    if (g_Simplified) {
        PS_OUTPUT output = (PS_OUTPUT)0.0;
        output.finalColorWithoutSSR = float4(result * g_TonemapScale, 1.0);
        return output;
    }

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
    if (g_HasBumpedLightmap) {
        float3 strength = mul(GrayScaleFactor, lightmapColors);
        float3 fakeTangentLightDir = mul(strength, BumpBasis);
        float3 fakeWorldLightDir = mul(fakeTangentLightDir, i.worldTransform);
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
    // Rougher surfaces read the coarser mip levels of the envmap
    float3 envmapSample  = texCUBElod(Envmap, float4(reflectDir, params.pbr.roughness * ENVMAP_LOD_MAX)).rgb * g_EnvmapScale;
    float3 envmapAlbedo  = lerp(float3(1.0, 1.0, 1.0), albedo, params.pbr.metallic);
    float3 reflectionWeight = envmapAlbedo;
    reflectionWeight *= fresnel;
    reflectionWeight *= ENVMAP_SCALE;
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
