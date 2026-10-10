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
    float  height;
    float  depth;
    float3 additive;
    float3 multiplicative;
    float3 normal;
    PseudoPBR pbr;
};

struct InkDetailProjection {
    float2 position;
    float3 worldU;
    float3 worldV;
};

struct InkDetailSettings {
    float2 scale;
    float  period;
    float  sine;
    float  cosine;
    float2 translation;
    float2 atlasOrigin;
    float  atlasSize;
    float4 strength;
};

struct InkDetailEffect {
    float3 colorAdd;
    float3 emission;
    float3 normal;         // Direction in axis-aligned projection space; need not be unit length.
    int    projectionAxis; // World axis used as projection Z: 0 = X, 1 = Y, 2 = Z.
    float  colorScale;
    float  specularScale;
    float  roughnessAdd;
    float  bumpBlendFactor;
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
static const float Tau                = 6.28318530718; // τ = 2π
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

void ApplyInkDetailNormal(
    inout float3 tangentNormal,
    inout float3 worldNormal,
    float3x3 transform,
    InkDetailEffect detail
) {
    if (dot(detail.normal.xy, detail.normal.xy) == 0.0) return;

    // Projection axes are world-axis permutations, not the mesh's texture basis.
    float3 baseNormal = worldNormal;
         if (detail.projectionAxis == 0) baseNormal = worldNormal.yzx;
    else if (detail.projectionAxis == 1) baseNormal = worldNormal.xzy;
    // Add XY/Z slopes without dividing. Input lengths cancel at final normalization.
    float3 n = detail.normal * baseNormal.z;
    n.xy += baseNormal.xy * detail.normal.z;
    if (dot(n, n) == 0.0) return;
         if (detail.projectionAxis == 0) n = n.zxy;
    else if (detail.projectionAxis == 1) n = n.xzy;
    worldNormal = n;
    // The mesh carries texture vectors, not necessarily an orthonormal basis.
    // Solve tangent * transform = n, rather than using its transpose as inverse.
    // Normalization cancels the inverse determinant's magnitude, but not its sign.
    float3 cn = cross(transform[2], n);
    float3 ab = cross(transform[0], transform[1]);
    float handedness = dot(transform[2], ab) < 0.0 ? -1.0 : 1.0;
    tangentNormal = float3(dot(transform[1], cn), -dot(transform[0], cn), dot(n, ab)) * handedness;
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

InkDetailEffect FetchInkDetails(const PsVertexInfo i, float3 IDs, float3 inkUV) {
    int id1 = (int)IDs.x;
    int id2 = (int)IDs.y;
    int id  = id2 > 0.0 ? id2 : id1;
    float idBlend = IDs.z;
    float4 modeAndBumpFactor1 = FetchDataPixel(InkDataDetail, id1, ID_DETAIL_MODE);
    float4 modeAndBumpFactor2 = FetchDataPixel(InkDataDetail, id2, ID_DETAIL_MODE);
    float4 encodedMode = id == id1 ? modeAndBumpFactor1 : modeAndBumpFactor2;
    float bumpBlendFactor = lerp(modeAndBumpFactor1.w, modeAndBumpFactor2.w, idBlend);
    int mode = (int)round(encodedMode.z * 255.0);
    InkDetailEffect effect = (InkDetailEffect)0;
    effect.bumpBlendFactor = bumpBlendFactor;
    effect.colorScale      = 1.0;
    effect.specularScale   = 1.0;
    effect.normal          = float3(0, 0, 1);
    if (mode == DETAIL_MODE_NONE) return effect;

    // Project detail sample position onto axis-aligned 2D plane
    InkDetailProjection projection;
    float3 absNormal = abs(i.worldTransform[2]);
    if (absNormal.x >= absNormal.y && absNormal.x >= absNormal.z) {
        projection.worldU = float3(0, 1, 0);
        projection.worldV = float3(0, 0, 1);
        effect.projectionAxis = 0;
    }
    else if (absNormal.y >= absNormal.z) {
        projection.worldU = float3(1, 0, 0);
        projection.worldV = float3(0, 0, 1);
        effect.projectionAxis = 1;
    }
    else {
        projection.worldU = float3(1, 0, 0);
        projection.worldV = float3(0, 1, 0);
        effect.projectionAxis = 2;
    }

    // The parallax ray's Z is in HEIGHT_TO_HU units along the mesh normal.
    // Evaluate the display texture at that hit, not at the unshifted mesh pixel.
    float3 viewVec = g_EyePos.xyz - i.worldPos;
    float3 worldPos = i.worldPos + viewVec * inkUV.z * HEIGHT_TO_HU * SAFERCP(dot(viewVec, i.worldTransform[2]));
    projection.position = float2(dot(worldPos, projection.worldU), dot(worldPos, projection.worldV));

    InkDetailSettings settings;
    float4 encodedMapping = FetchDataPixel(InkDataDetail, id, ID_DETAIL_MAPPING);
    float3 grid = round(FetchDataPixel(InkDataDetail, id, ID_DETAIL_GRID).xyz * 255.0);
    float cellSize = g_InkDataOffsetV / grid.z;
    sincos(encodedMapping.z * Tau, settings.sine, settings.cosine);
    settings.scale       = 0.5 + 1.5 * encodedMapping.xy;
    settings.period      = 16.0 * exp2(8.0 * encodedMapping.w);
    settings.translation = encodedMode.xy;
    settings.atlasOrigin = grid.xy * cellSize + 1.0;
    settings.atlasSize   = cellSize - 2.0;
    settings.strength    = (mode == DETAIL_MODE_MATERIAL || mode == DETAIL_MODE_NORMAL)
        ? FetchDataPixel(InkDataDetail, id, ID_DETAIL_STRENGTH) * 255.0 / 127.0
        : 0.0;

    float2 scaledPosition  = projection.position / settings.period * settings.scale;
    float2 rotatedPosition = {
        settings.cosine * scaledPosition.x - settings.sine   * scaledPosition.y,
        settings.sine   * scaledPosition.x + settings.cosine * scaledPosition.y,
    };
    float2 repeatedUV   = frac(rotatedPosition + settings.translation);
    float2 atlasUV      = (settings.atlasOrigin + repeatedUV * settings.atlasSize) * g_DataRTSize;
    float4 detailSample = tex2Dlod(InkDataDetail, float4(atlasUV, 0, 0));

    [branch]
    if (mode == DETAIL_MODE_MATERIAL || mode == DETAIL_MODE_NORMAL) {
        // RG stores normal XY. Reconstruct Z before applying XY strength.
        float3 detailNormal = { TO_SIGNED(detailSample.rg), 0.0 };
        detailNormal.z = sqrt(saturate(1.0 - dot(detailNormal.xy, detailNormal.xy)));
        detailNormal.xy *= settings.strength.xy;

        // Undo image rotation, retaining the complete normal in projection space.
        effect.normal = float3(
            settings.cosine * detailNormal.x + settings.sine   * detailNormal.y,
           -settings.sine   * detailNormal.x + settings.cosine * detailNormal.y,
            detailNormal.z);
    }

    [branch]
    if (mode == DETAIL_MODE_MATERIAL) {
        effect.colorScale = max(0.0, 1.0 + settings.strength.w * TO_SIGNED(detailSample.a));
        effect.roughnessAdd = settings.strength.z * TO_SIGNED(detailSample.b);
    }
    else if (mode == DETAIL_MODE_NORMAL) {
        effect.specularScale = detailSample.a;
    }
    else if (mode == DETAIL_MODE_EMISSION) {
        effect.emission = detailSample.rgb * detailSample.a;
    }
    else if (mode == DETAIL_MODE_COLOR) {
        effect.colorScale = 1.0 - detailSample.a;
        effect.colorAdd = detailSample.rgb * detailSample.a;
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

    InkDetailEffect detail    = FetchInkDetails(i, IDs, inkUV);
    params.pbr.roughness      = saturate(params.pbr.roughness + detail.roughnessAdd);
    params.pbr.specularScale *= detail.specularScale;
    params.multiplicative    *= detail.colorScale;
    params.additive          *= detail.colorScale;

    // Blend ink and world normals
    UVs    uv                 = ApplyParallaxGeometry(i, params);
    float3 geometryNormal     = FetchGeometryNormal(i, uv);
    float3 tangentSpaceNormal = lerp(geometryNormal, params.normal, detail.bumpBlendFactor);
    float3 worldSpaceNormal   = mul(tangentSpaceNormal, i.worldTransform);
    ApplyInkDetailNormal(tangentSpaceNormal, worldSpaceNormal, i.worldTransform, detail);
    worldSpaceNormal   = normalize(worldSpaceNormal);
    tangentSpaceNormal = normalize(tangentSpaceNormal);

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
