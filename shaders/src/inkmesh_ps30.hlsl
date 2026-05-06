// Ink Mesh Pixel Shader for SplashSWEPs
// Based on LightmappedGeneric pixel shader with bumped lightmaps

#include "inkmesh_common.hlsl"

// Build configurations
#define g_EnvmapEnabled
#define g_PhongEnabled
#define g_RimEnabled

struct PS_OUTPUT {
    float4 color : COLOR0;
    float  depth : DEPTH0;
};

struct PsVertexInfo {
    float2   screenPos;
    float3   worldPos;
    float4   clipPos;
    float2   minUV;
    float2   maxUV;
    float3   inkUV;
    float2   worldUV;
    float3x2 lightmapUV;
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
    float height;
    float depth;
    float3 additive;
    float3 multiplicative;
    PseudoPBR pbr;
    DetailParams detail;
};

static const float HEIGHT_TO_HU       = 8.0;
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
static const float3 GrayScaleFactor   = { 0.2126, 0.7152, 0.0722 };
static const float3x3 BumpBasis = {
    // Bumped lightmap basis vectors (same as LightmappedGeneric) in tangent space
    {  0.81649661064147949,  0.0,                 0.57735025882720947 },
    { -0.40824833512306213,  0.70710676908493042, 0.57735025882720947 },
    { -0.40824833512306213, -0.70710676908493042, 0.57735025882720947 },
};


// Samplers
sampler InkMap             : register(s0);
sampler InkDataSampler     : register(s1);
sampler UnusedSampler      : register(s2);
sampler FrameBuffer        : register(s3);
sampler InkDetailSampler   : register(s4);
sampler WallAlbedoSampler  : register(s5);
sampler WallBumpmapSampler : register(s6);
sampler LightmapSampler    : register(s7);

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
const float2x4 BaseTextureTransform : register(c11);
const float2x4 BumpTextureTransform : register(c15);
const float4 HDRParams : register(c30);

#define g_SunDirection      c0.xyz // in world space
#define g_Unused            c0.w
#define g_HasBumpedLightmap c1.x
#define g_NeedsFrameBuffer  c1.y   // True when WorldVertexTransition or Lightmapped_4WayBlend
#define g_ScreenScale       c1.y   // If g_NeedsFrameBuffer > 0, it is parallax mapping scale
#define g_HammerUnitsToUV   c1.z   // = ss.RenderTarget.HammerUnitsToUV * 0.5
#define g_Simplified        c1.w   // Simplified rendering for water reflection/refraction
#define g_RTSize            s0Size // One over ink map size
#define g_DataRTSize        s1Size // One over data look-up table size
#define g_FbSize            s3Size // One over frame buffer size
#define g_TonemapScale  HDRParams.x
#define g_LightmapScale HDRParams.y
#define g_EnvmapScale   HDRParams.z
#define g_GammaScale    HDRParams.w // = TonemapScale ^ (1 / 2.2)

PsVertexInfo DecomposeInput(const PS_INPUT i) {
    float3 lightmapOffset = g_HasBumpedLightmap ? float3(0.0, 0.0, 0.0) : float3(1.0, 2.0, 3.0);
    PsVertexInfo v;
    v.screenPos         = i.screenPos.xy;
    v.worldPos          = i.vi.worldPos.xyz;
    v.clipPos           = i.vi.clipPos;
    v.minUV             = i.vi.surfaceClipRange.xy;
    v.maxUV             = i.vi.surfaceClipRange.zw;
    v.inkUV             = float3(i.vi.inkTangent_U.w, i.vi.inkBinormal_V.w, 0.0);
    v.worldUV           = float2(i.vi.worldTangent_U.w, i.vi.worldBinormal_V.w);
    v.lightmapUV        = float3x2(
        i.vi.lightmapTangent_U.w + i.vi.worldNormal_dU.w * lightmapOffset[0], i.vi.lightmapBinormal_V.w,
        i.vi.lightmapTangent_U.w + i.vi.worldNormal_dU.w * lightmapOffset[1], i.vi.lightmapBinormal_V.w,
        i.vi.lightmapTangent_U.w + i.vi.worldNormal_dU.w * lightmapOffset[2], i.vi.lightmapBinormal_V.w);
    v.worldTransform    = float3x3(i.vi.worldTangent_U.xyz,    i.vi.worldBinormal_V.xyz,    i.vi.worldNormal_dU.xyz);
    v.inkTransform      = float3x3(i.vi.inkTangent_U.xyz,      i.vi.inkBinormal_V.xyz,      i.vi.worldNormal_dU.xyz);
    v.lightmapTransform = float3x3(i.vi.lightmapTangent_U.xyz, i.vi.lightmapBinormal_V.xyz, i.vi.worldNormal_dU.xyz);
    return v;
}

float4 FetchDataPixel(int id, int index) {
    if (id == 0) {
        return GROUND_PROPERTIES[index];
    }
    else {
        return tex2Dlod(InkDataSampler, float4(
            (id    - 0.5) * g_DataRTSize.x,
            (index + 0.5) * g_DataRTSize.y,
            0.0,
            0.0));
    }
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

// Samples only height value to apply parallax effect to the ink
float FetchHeight(float2 uv) {
    return TO_SIGNED(tex2Dlod(InkMap, float4(uv, 0.0, 0.0)).a);
}

// Samples only depth value to apply parallax effect to the ink
float FetchDepth(float2 uv) {
    return tex2Dlod(InkMap, float4(uv.x + 0.5, uv.y, 0.0, 0.0)).a;
}

// Samples additive color and height value
void FetchAdditiveAndHeight(float2 uv, inout MaterialParams params, out float3 normal) {
    float4 uv4 = { uv, 0.0, 0.0 };
    float4 s = tex2Dlod(InkMap, uv4);
    params.additive = pow(abs(s.rgb), 2.2); // Manually correct gamma
    params.height   = TO_SIGNED(s.a);

    // Additional samples to calculate tangent space normal
    float hx = TO_SIGNED(tex2Dlod(InkMap, uv4 + float4(g_RTSize.x, 0, 0.0, 0.0)).a);
    float hy = TO_SIGNED(tex2Dlod(InkMap, uv4 + float4(0, g_RTSize.y, 0.0, 0.0)).a);
    float dx = hx - params.height;
    float dy = hy - params.height;
    normal = normalize(float3(-dx, -dy, 1.0));
}

// Samples multiplicative color and ground depth
void FetchMultiplicativeAndDepth(float2 uv, inout MaterialParams params) {
    float4 s = tex2Dlod(InkMap, float4(uv.x + 0.5, uv.y, 0.0, 0.0));
    params.multiplicative = pow(abs(s.rgb), 2.2);
    params.depth          = s.a;
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
float3 FetchGeometryNormal(float2 uv, float2 uvddx, float2 uvddy) {
    uv = mul(BumpTextureTransform, float4(uv, 1.0, 1.0));
    float3 geometryNormal = tex2Dgrad(WallBumpmapSampler, uv, uvddx, uvddy).rgb;
    geometryNormal *= 2.0;
    geometryNormal -= 1.0;

    // Handle missing world bumpmap (default to flat normal)
    bool hasNoBump = geometryNormal.x == -1.0 &&
                     geometryNormal.y == -1.0 &&
                     geometryNormal.z == -1.0;
    if (hasNoBump) geometryNormal = float3(0.0, 0.0, 1.0);
    return geometryNormal;
}

// Samples albedo and bumpmap pixel from geometry textures
float3 FetchGeometrySamples(
    float2 uv, float2 uvddx, float2 uvddy,
    float3x3 lightmapColors, float3 geometryNormal) {
    if (g_NeedsFrameBuffer) {
        float4 frameBufferSample = tex2Dgrad(FrameBuffer, uv, uvddx, uvddy);
        frameBufferSample /= g_TonemapScale * g_LightmapScale;
        float3 lightDirectionDifferences = g_HasBumpedLightmap
            ? float3(saturate(dot(geometryNormal, BumpBasis[0])),
                     saturate(dot(geometryNormal, BumpBasis[1])),
                     saturate(dot(geometryNormal, BumpBasis[2])))
            : float3(1.0, 0.0, 0.0);
        float3 lightmapColorExpected = mul(lightDirectionDifferences, lightmapColors);
        return frameBufferSample.rgb / max(lightmapColorExpected, 1.0e-4);
    }
    else {
        uv = mul(BaseTextureTransform, float4(uv, 1.0, 1.0));
        return tex2Dgrad(WallAlbedoSampler, uv, uvddx, uvddy).rgb;
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

void ApplyParallaxGeometry(
    const PsVertexInfo i, float2 tangentScaleSqr,
    float3 inkNormal, MaterialParams params,
    out float2 baseUV, out float2 bumpUV) {
    float2 texTransformScale = {
        length(BaseTextureTransform[0].xyz),
        length(BaseTextureTransform[1].xyz),
    };
    float3 viewVec = g_EyePos.xyz - i.worldPos;
    float3 tangentViewDir = mul(i.worldTransform, normalize(viewVec));
    float2 parallaxVec = tangentViewDir.xy / max(tangentViewDir.z, 1.0e-3);
    float2 uvDepthParallax = -parallaxVec;
    uvDepthParallax *= params.depth;
    uvDepthParallax /= max(tangentScaleSqr, 1.0e-3) * max(texTransformScale, 1e-3);
    float2 uvRefraction = inkNormal.xy * params.pbr.refraction * rsqrt(max(tangentScaleSqr, 1.0e-3)) * 0.0;
    float2 uvOffset = uvDepthParallax + uvRefraction;
    bumpUV = i.worldUV + uvOffset;
    baseUV = bumpUV;
    if (g_NeedsFrameBuffer > 0.0) {
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
        float2 du = ddx(i.worldUV);
        float2 dv = ddy(i.worldUV);
        float det = du.x * dv.y - dv.x * du.y;
        det = rcp(det + (det < 0 ? -1.0e-7 : 1.0e-7));
        float2 screenOffset = {
            dot(float2( dv.y, -dv.x), uvOffset) * det,
            dot(float2(-du.y,  du.x), uvOffset) * det,
        };
        float2 finalUV = (i.screenPos + screenOffset * g_ScreenScale) * g_FbSize;
        float2 fade = smoothstep(0.0, 0.05, finalUV) * smoothstep(1.0, 0.55, finalUV);
        baseUV = lerp(i.screenPos * g_FbSize, finalUV, fade);
    }
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
    float3 inkNormal;
    MaterialParams params;
    FetchAdditiveAndHeight(inkUV.xy, params, inkNormal);
    FetchMultiplicativeAndDepth(inkUV.xy, params);
    FetchInkMaterial(IDs, params.pbr);
    FetchInkDetails(IDs, params.detail);

    float2 baseUV, bumpUV;
    float2 tangentScaleSqr = {
        dot(i.worldTransform[0], i.worldTransform[0]),
        dot(i.worldTransform[1], i.worldTransform[1]),
    };
    ApplyParallaxGeometry(i, tangentScaleSqr, inkNormal, params, baseUV, bumpUV);

    // Sample 3 directional lightmaps
    float3x3 lightmapColors = {
        tex2D(LightmapSampler, i.lightmapUV[0]).rgb,
        tex2D(LightmapSampler, i.lightmapUV[1]).rgb,
        tex2D(LightmapSampler, i.lightmapUV[2]).rgb,
    };
    float2 bumpUVd[2] = { ddx(i.worldUV), ddy(i.worldUV) };
    float2 baseUVd[2] = {
        g_HasBumpedLightmap ? float2(g_FbSize.x, 0.0) : bumpUVd[0],
        g_HasBumpedLightmap ? float2(0.0, g_FbSize.y) : bumpUVd[1],
    };

    // Sample geometry albedo and normal
    float3 geometryNormal = FetchGeometryNormal(bumpUV, bumpUVd[0], bumpUVd[1]);
    float3 geometryAlbedo = FetchGeometrySamples(baseUV, baseUVd[0], baseUVd[1], lightmapColors, geometryNormal);

    // Blend ink and world normals
    float3 tangentSpaceNormal = normalize(lerp(geometryNormal, inkNormal, params.detail.bumpBlendFactor));
    float3 worldSpaceNormal = normalize(mul(tangentSpaceNormal, i.worldTransform));

    // Compute diffuse lighting factors using bumped lightmap basis
    float3 lightDirectionDifferences;
    if (g_HasBumpedLightmap) {
        lightDirectionDifferences = float3(
            saturate(dot(tangentSpaceNormal, BumpBasis[0])),
            saturate(dot(tangentSpaceNormal, BumpBasis[1])),
            saturate(dot(tangentSpaceNormal, BumpBasis[2])));

        // Square for softer falloff
        lightDirectionDifferences *= lightDirectionDifferences;
    }
    else {
        lightDirectionDifferences = float3(1.0, 0.0, 0.0);
    }

    // Modulate surface albedo and add ink color
    float3 albedo = geometryAlbedo * params.multiplicative + params.additive;
    float3 ambientOcclusion = { 1.0, 1.0, 1.0 }; // dummy!
    float3 result = albedo * lerp(1.0, DIFFUSE_MIN, params.pbr.metallic);

    // Apply diffuse lighting component
    result *= mul(lightDirectionDifferences, lightmapColors);
    result *= rcp(max(dot(lightDirectionDifferences, float3(1.0, 1.0, 1.0)), 1.0e-3));
    result *= g_LightmapScale;

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
    float3 phongSpecular = mul(lightDirectionDifferences * spec, lightmapColors);
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
    float3 rimLighting = mul(lightDirectionDifferences, lightmapColors);
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
    envmapUVOffset /= max(tangentScaleSqr, 1.0e-3);
    float2 du = ddx(i.worldUV);
    float2 dv = ddy(i.worldUV);
    float det = du.x * dv.y - dv.x * du.y;
    det = rcp(det + (det < 0 ? -1.0e-7 : 1.0e-7));
    float2 screenOffset = {
        dot(float2( dv.y, -dv.x), envmapUVOffset) * det,
        dot(float2(-du.y,  du.x), envmapUVOffset) * det,
    };
    float2 fakeSSRUV = saturate((i.screenPos - screenOffset) * g_FbSize);
    float3 envmapSpecular = tex2D(FrameBuffer, fakeSSRUV).rgb;
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
