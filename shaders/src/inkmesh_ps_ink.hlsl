#ifndef INKMESH_PS_INK_HLSL
#define INKMESH_PS_INK_HLSL

// Ink part of the ink mesh pixel shaders for SplashSWEPs, shared by the geometry kinds.
//
//   inkmesh_ps30.hlsl, inkmesh_wvt_ps30.hlsl, inkmesh_4wayblend_ps30.hlsl (UNDERLAY_KIND),
//   staticprop_ps30.hlsl (INKMESH_STATIC_PROP)
//   `-- inkmesh_ps_main.hlsl              main()
//       `-- inkmesh_ps_world.hlsl         or inkmesh_ps_staticprop.hlsl with INKMESH_STATIC_PROP
//           `-- inkmesh_ps_ink.hlsl       this file
//               `-- inkmesh_common.hlsl
#include "inkmesh_common.hlsl"

// Build configurations
#define g_EnvmapEnabled
#define g_PhongEnabled
#define g_RimEnabled

struct PS_OUTPUT {
    float4 finalColorWithoutSSR : COLOR0;
    float4 encodedNormals       : COLOR1; // encoded normal vector of xy: painted ink, zw: the mesh
    float4 reflectionAndHeight  : COLOR2; // reflected ink color and ink height
    float4 envmapAndRoughness   : COLOR3; // envmap sample and ink roughness
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

// Samplers
sampler InkMap          : register(s0);
sampler InkDataDetail   : register(s1);
sampler FrameBuffer     : register(s2);
sampler UnderlayAlbedo  : register(s3);
sampler UnderlayBumpmap : register(s4);
// s5 and s6 are defined by the geometry part that uses them
sampler Envmap          : register(s7);

static const float   g_DetailGridColumns  = c1.x;   // Number of columns in the ink detail image grid
static const float   g_InkMapHUPerUV      = c1.z;   // Packed-surface HU per ink UV: 2 / HammerUnitsToUV
static const float3  g_Color              = c3.rgb;
static const float2  g_RTSize             = s0Size; // One over ink map size
static const float2  g_FbSize             = s2Size * float2(1.0, 2.0); // One over frame buffer size
static const float2  g_UnderlayAlbedoSize = s3Size; // One over $basetexture size
static const float3  BaseTransform[2]     = { c11.xyz, c12.xyz };
static const float3  BumpTransform[2]     = { c13.xyz, c14.xyz };
static const float   g_TonemapScale       = HDRParams.x;
static const float   g_LightmapScale      = HDRParams.y;
static const float   g_EnvmapScale        = HDRParams.z;
static const float   g_GammaScale         = HDRParams.w; // = TonemapScale ^ (1 / 2.2)

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

// Samples only height value
float FetchHeight(float2 uv) {
    float4 s = tex2Dlod(InkMap, float4(uv + INKMAP_HEIGHT_DEPTH, 0.0, 0.0));
    return TO_SIGNED(DecodeUnorm16(s.rg));
}

// The region of the ink map selected at the sample point, among the four nearest indices texels.
struct InkRegionSelection {
    float4 indices;      // Indices texel of the selected region
    float2 texelUV;      // Center UV of that texel, without the region offset
    float2 cornerUV;     // Center UV of the first of the four texels, without the region offset
    float4 colorWeights; // Bilinear weights of the four texels, restricted to the selected region and normalized
    bool   isUniform;    // All four texels belong to the selected region
};

// Samples a color region (additive or multiplicative) with gamma correction.
// The color is interpolated over the texels of the selected region only,
// so that it ends at the region boundary instead of fading out along the texel grid.
float3 FetchRegionColor(const InkRegionSelection s, float2 uv, float2 regionOffset) {
    float3 color = 0.0;
    if (s.isUniform) {
        color = tex2Dlod(InkMap, float4(uv + regionOffset, 0.0, 0.0)).rgb;
    }
    else {
        float2 texelOffsets[4] = { float2(0.0, 0.0), float2(g_RTSize.x, 0.0), float2(0.0, g_RTSize.y), g_RTSize };
        [unroll]
        for (int k = 0; k < 4; k++) {
            float4 t = tex2Dlod(InkMap, float4(s.cornerUV + texelOffsets[k] + regionOffset, 0.0, 0.0));
            color += s.colorWeights[k] * t.rgb;
        }
    }
    return pow(abs(color), 2.2);
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

// FrameBuffer stacks the frame buffer copy with the view depth in alpha (upper half)
// on the flashlight light of the world ink meshes (lower half).
// The frame buffer is read with bilinear filtering, so its v stops half a texel before the lower half.
float4 SampleScene(float2 screenUV) {
    return tex2Dlod(FrameBuffer, float4(screenUV.x, min(screenUV.y * 0.5, 0.5 - s2Size.y * 0.5), 0.0, 0.0));
}

// Selects the region of the ink map at the sample point.
// Each of the four nearest texels votes its bilinear weight times its distance to the region boundary
// for its own region, and the region with the most votes wins. Between two regions, this is the sign of
// the interpolated signed distance, so the boundary passes between the texel centers.
InkRegionSelection SelectInkRegion(float2 inkUV) {
    float2 texelPos = inkUV / g_RTSize - 0.5;
    float2 base     = floor(texelPos);
    float2 f        = texelPos - base;
    float2 uv00     = (base + 0.5) * g_RTSize;
    float2 tapUV[4] = { uv00, uv00 + float2(g_RTSize.x, 0.0), uv00 + float2(0.0, g_RTSize.y), uv00 + g_RTSize };
    float4 weights  = float4((1.0 - f.x) * (1.0 - f.y), f.x * (1.0 - f.y), (1.0 - f.x) * f.y, f.x * f.y);
    float4 taps[4];
    float4 regions, votes;
    [unroll]
    for (int k = 0; k < 4; k++) {
        taps[k] = tex2Dlod(InkMap, float4(tapUV[k] + INKMAP_INDICES, 0.0, 0.0));
        float2 distanceBlend = DecodeIndicesDistanceBlend(taps[k].b);
        // Lower ID, upper ID, and whether anything is painted
        regions[k] = dot(round(taps[k].rg * 255.0), float2(512.0, 2.0)) + (IsIndicesPainted(taps[k]) ? 1.0 : 0.0);
        // A small constant breaks ties toward the heavier texels where every distance is zero.
        votes[k] = weights[k] * (distanceBlend.x + 1.0e-3);
    }

    float4 scores = {
        dot((float4)(regions == regions.x), votes),
        dot((float4)(regions == regions.y), votes),
        dot((float4)(regions == regions.z), votes),
        dot((float4)(regions == regions.w), votes),
    };
    InkRegionSelection s;
    s.indices  = taps[0];
    s.texelUV  = tapUV[0];
    s.cornerUV = uv00;
    float best = scores.x;
    float selectedRegion = regions.x;
    [unroll]
    for (int j = 1; j < 4; j++) {
        if (scores[j] > best) {
            best           = scores[j];
            selectedRegion = regions[j];
            s.indices      = taps[j];
            s.texelUV      = tapUV[j];
        }
    }

    // The selected region has a positive vote, so some of its texels have positive weights.
    float4 inRegion = (float4)(regions == selectedRegion);
    s.colorWeights  = weights * inRegion / dot(weights, inRegion);
    s.isUniform     = all(inRegion);
    return s;
}

#endif
