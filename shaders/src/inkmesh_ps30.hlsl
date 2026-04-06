// Ink Mesh Pixel Shader for SplashSWEPs
// Based on LightmappedGeneric pixel shader with bumped lightmaps

#include "inkmesh_core.hlsl"

// Build configurations
#define g_EnvmapEnabled
#define g_PhongEnabled
#define g_RimEnabled

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
static const float DEPTH_BASE_BIAS  = 2.0e-5; // 1.0e-5 -- 5.0e-5
static const float DEPTH_DIFF_SCALE = 1.5;    // Sensitivity of the depth difference
static const float3 GrayScaleFactor = { 0.2126, 0.7152, 0.0722 };
static const float DEBUG_TRACE_MAX_STEPS = 16.0;

// Bumped lightmap basis vectors (same as LightmappedGeneric) in tangent space
static const float3x3 BumpBasis = {
    float3( 0.81649661064147949,  0.0,                 0.57735025882720947),
    float3(-0.40824833512306213,  0.70710676908493042, 0.57735025882720947),
    float3(-0.40824833512306213, -0.70710676908493042, 0.57735025882720947),
};

struct PS_OUTPUT {
    float4 color : COLOR0;
    float  depth : DEPTH0;
};

float4 FetchDataPixel(int id, int index) {
    if (id == 0) {
        return GROUND_PROPERTIES[index];
    }
    else {
        return tex2Dlod(InkDataSampler, float4(
            (id    - 0.5) * RcpDataRTSize.x,
            (index + 0.5) * RcpDataRTSize.y,
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

// Samples additive color and height value
void FetchAdditiveAndHeight(float2 uv, out float3 additive, out float height, out float3 normal) {
    float4 uv4 = { uv, 0.0, 0.0 };
    float4 s = tex2Dlod(InkMap, uv4);
    additive = pow(abs(s.rgb), 2.2); // Manually correct gamma
    height   = TO_SIGNED(s.a);

    // Additional samples to calculate tangent space normal
    float hx = TO_SIGNED(tex2Dlod(InkMap, uv4 + float4(RcpRTSize.x, 0, 0.0, 0.0)).a);
    float hy = TO_SIGNED(tex2Dlod(InkMap, uv4 + float4(0, RcpRTSize.y, 0.0, 0.0)).a);
    float dx = hx - height;
    float dy = hy - height;
    normal = normalize(float3(-dx, -dy, 1.0));
}

// Samples multiplicative color and ground depth
void FetchMultiplicativeAndDepth(float2 uv, out float3 multiplicative, out float depth) {
    float4 s = tex2Dlod(InkMap, float4(uv.x + 0.5, uv.y, 0.0, 0.0));
    multiplicative = pow(abs(s.rgb), 2.2);
    depth          = s.a;
}

// Samples lighting parameters from texture sampler
void FetchInkMaterial(
    int id1,
    int id2,
    float idBlend,
    out float metallic,
    out float roughness,
    out float specularScale,
    out float refraction) {
    float4 s;

    s = FetchDataPixel(id1, ID_MATERIAL_REFRACT);
    metallic      = s.r;
    roughness     = s.g;
    specularScale = s.b;
    refraction    = s.a;
    s = FetchDataPixel(id2, ID_MATERIAL_REFRACT);
    metallic      = lerp(metallic,      s.r, idBlend);
    roughness     = lerp(roughness,     s.g, idBlend);
    specularScale = lerp(specularScale, s.b, idBlend);
    refraction    = lerp(refraction,    s.a, idBlend);
}

// Samples detail component
void FetchInkDetails(
    int id1,
    int id2,
    float idBlend,
    out float detailblendmode,
    out float detailblendscale,
    out float detailbumpscale,
    out float bumpblendfactor) {
    float4 s;

    s = FetchDataPixel(id1, ID_DETAILS_BUMPBLEND);
    detailblendmode  = s.r;
    detailblendscale = s.g;
    detailbumpscale  = s.b;
    bumpblendfactor  = s.a;
    s = FetchDataPixel(id2, ID_DETAILS_BUMPBLEND);
    detailblendmode  = lerp(detailblendmode,  s.r, idBlend);
    detailblendscale = lerp(detailblendscale, s.g, idBlend);
    detailbumpscale  = lerp(detailbumpscale,  s.b, idBlend);
    bumpblendfactor  = lerp(bumpblendfactor,  s.a, idBlend);
}

// Samples albedo and bumpmap pixel from geometry textures
void FetchGeometrySamples(
    float2 bumpUV, float2 bumpUVddx, float2 bumpUVddy,
    float2 baseUV, float2 baseUVddx, float2 baseUVddy,
    float3x3 lightmapColors,
    out float3 geometryAlbedo,
    out float3 geometryNormal) {
    // Sample world bumpmap
    float2 uv = mul(BumpTextureTransform, float4(bumpUV, 1.0, 1.0));
    geometryNormal = tex2Dgrad(WallBumpmapSampler, uv, bumpUVddx, bumpUVddy).rgb;
    geometryNormal *= 2.0;
    geometryNormal -= 1.0;

    // Handle missing world bumpmap (default to flat normal)
    bool hasNoBump = geometryNormal.x == -1.0 &&
                     geometryNormal.y == -1.0 &&
                     geometryNormal.z == -1.0;
    if (hasNoBump) {
        geometryNormal = float3(0.0, 0.0, 1.0);
    }

    if (g_NeedsFrameBuffer) {
        float4 frameBufferSample = tex2Dgrad(FrameBuffer, baseUV, baseUVddx, baseUVddy);
        frameBufferSample /= g_TonemapScale * g_LightmapScale;
        float3 lightDirectionDifferences = hasNoBump
            ? float3(1.0, 0.0, 0.0)
            : float3(saturate(dot(geometryNormal, BumpBasis[0])),
                     saturate(dot(geometryNormal, BumpBasis[1])),
                     saturate(dot(geometryNormal, BumpBasis[2])));
        float3 lightmapColorExpected = mul(lightDirectionDifferences, lightmapColors);
        geometryAlbedo = frameBufferSample.rgb / max(lightmapColorExpected, 1.0e-4);
    }
    else {
        uv = mul(BaseTextureTransform, float4(baseUV, 1.0, 1.0));
        geometryAlbedo = tex2Dgrad(WallAlbedoSampler, uv, baseUVddx, baseUVddy).rgb;
    }
}

PS_OUTPUT main(const PS_INPUT i) {
    float projPosZ = i.worldPos_projPosZ.w;
    float projPosW = i.projPosW_meshRole.x;
    float sceneLinearDepth = tex2Dlod(DepthSampler, float4(i.screenPos.xy * RcpDepthSize, 0.0, 0.0)).r;
    float linearDepth = projPosZ / 4096.0;
    float role = round(i.projPosW_meshRole.y * MESH_ROLE_MAX);
    bool  isBase = role == MESH_ROLE_BASE;
    bool  isCeil = role == MESH_ROLE_CEIL;
    bool  isDepth = role == MESH_ROLE_DEPTH;
    bool  isSideIn = role == MESH_ROLE_SIDE_IN;
    bool  isSideOut = role == MESH_ROLE_SIDE_OUT;
    // if (isBase || isDepth || isSideOut) {
    //     clip(sceneLinearDepth + 1e-8 - linearDepth); // Early-Z culling
    // }

    float debugDepth = max(projPosZ / projPosW, 0.0);
    float3 inkUV; // Z = final ray marching height
    float traceKind = TRACE_BOX_MISS;
    float traceSteps = 0.0;
    float traceRayFraction = 1.0;
    if (g_Simplified) {
        clip(-abs(i.inkBinormalMeshLift.w));
        inkUV = float3(i.inkUV_worldBumpUV.xy, 0.0);
    }
    else {
        inkUV = TracePaintInterface(i, traceKind, traceSteps, traceRayFraction);
    }
    int debugMode = (int)round(g_Unused);
    if (debugMode == 1) {
        PS_OUTPUT debugTraceOutput = { DebugTraceKindColor(traceKind) * g_TonemapScale, 1.0, debugDepth };
        return debugTraceOutput;
    }
    if (!g_Simplified && !IsTraceHit(traceKind)) {
        clip(-1.0);
    }
    float3 hitWorldPos = lerp(g_EyePos.xyz, i.worldPos_projPosZ.xyz, traceRayFraction);
    float3 viewVec = g_EyePos.xyz - hitWorldPos;
    float  viewVecLength = max(length(viewVec), 1.0e-4);
    float3 viewDir = viewVec * rcp(viewVecLength);
    float2 pixelUV = (floor(inkUV.xy / RcpRTSize) + 0.5) * RcpRTSize + float2(0.0, 0.5);
    float4 inkIDs  = tex2Dlod(InkMap, float4(pixelUV, 0.0, 0.0));
    float  ID1     = round(inkIDs.r * 255.0);
    float  ID2     = round(inkIDs.g * 255.0);
    float  idBlend = inkIDs.b;
    clip(floor(ID1 + ID2 + idBlend) - 0.5);

    // Samples ink parameters
    float metallic, roughness, specularScale, refraction, height, depth;
    float detailblendmode, detailblendscale, detailbumpscale, bumpblendfactor;
    float3 additive, multiplicative, inkNormal;
    FetchAdditiveAndHeight(inkUV.xy, additive, height, inkNormal);
    FetchMultiplicativeAndDepth(inkUV.xy, multiplicative, depth);
    clip(max(depth + inkUV.z, 0));
    FetchInkMaterial(ID1, ID2, idBlend, metallic, roughness, specularScale, refraction);
    FetchInkDetails(ID1, ID2, idBlend, detailblendmode, detailblendscale, detailbumpscale, bumpblendfactor);

    float3 worldTangent = {
        i.worldBinormalTangentX.w,
        i.worldNormalTangentY.w,
        i.inkTangentXYZWorldZ.w,
    };
    float3x3 tangentSpaceWorld = {
        worldTangent,
        i.worldBinormalTangentX.xyz,
        i.worldNormalTangentY.xyz,
    };
    float2 tangentScaleSqr = {
        dot(worldTangent, worldTangent),
        dot(i.worldBinormalTangentX.xyz, i.worldBinormalTangentX.xyz),
    };
    float2 texTransformScale = {
        length(BaseTextureTransform[0].xyz),
        length(BaseTextureTransform[1].xyz),
    };
    float3 tangentViewDir = mul(tangentSpaceWorld, viewDir);
    float2 parallaxVec = tangentViewDir.xy / max(tangentViewDir.z, 1.0e-3);
    float2 uvDepthParallax = -parallaxVec;
    float thickness = max(depth + inkUV.z, 0.0);
    uvDepthParallax *= thickness;
    uvDepthParallax /= max(tangentScaleSqr, 1.0e-3) * max(texTransformScale, 1e-3);
    float2 uvRefraction = inkNormal.xy * refraction * rsqrt(max(tangentScaleSqr, 1.0e-3)) * 0.0;
    float2 uvOffset = uvDepthParallax + uvRefraction;
    float2 inkProxyUV = i.inkUV_worldBumpUV.xy;
    float2 bumpProxyUV = i.inkUV_worldBumpUV.zw;
    float2 inkHitOffset = (inkUV.xy - inkProxyUV) * 2.0;
    float2 bumpFromInkRow0 = i.lightmapUV3_projXY.zw;
    float2 bumpFromInkRow1 = i.projPosW_meshRole.zw;
    float2 hitBumpOffset = {
        dot(bumpFromInkRow0, inkHitOffset),
        dot(bumpFromInkRow1, inkHitOffset),
    };
    float2 bumpUV = bumpProxyUV + hitBumpOffset + uvOffset;
    float2 baseUV = bumpUV;
    float2 bumpUVd[2] = {
        ddx(bumpProxyUV),
        ddy(bumpProxyUV),
    };
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
        float2 screenOffset = SolveScreenOffset(bumpUVd[0], bumpUVd[1], hitBumpOffset + uvOffset);
        float2 finalUV = (i.screenPos + screenOffset * g_ScreenScale) * RcpFbSize;
        float2 fade = smoothstep(0.0, 0.05, finalUV) * smoothstep(1.0, 0.55, finalUV);
        baseUV = lerp(i.screenPos * RcpFbSize, finalUV, fade);
    }

    // Sample 3 directional lightmaps
    float3x3 lightmapColors = {
        tex2D(LightmapSampler, i.lightmapUV1And2.xy).rgb,
        tex2D(LightmapSampler, i.lightmapUV1And2.zw).rgb,
        tex2D(LightmapSampler, i.lightmapUV3_projXY.xy).rgb,
    };
    float2 baseUVd[2] = {
        g_HasBumpedLightmap ? float2(RcpFbSize.x, 0.0) : bumpUVd[0],
        g_HasBumpedLightmap ? float2(0.0, RcpFbSize.y) : bumpUVd[1],
    };

    // Sample geometry albedo and normal
    float3 geometryAlbedo, geometryNormal;
    FetchGeometrySamples(
        bumpUV, bumpUVd[0], bumpUVd[1],
        baseUV, baseUVd[0], baseUVd[1],
        lightmapColors, geometryAlbedo, geometryNormal);

    // Blend ink and world normals
    float3 tangentSpaceNormal = normalize(lerp(geometryNormal, inkNormal, bumpblendfactor));
    float3 worldSpaceNormal = normalize(mul(tangentSpaceNormal, tangentSpaceWorld));

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
    float3 albedo = geometryAlbedo * multiplicative + additive;
    float3 ambientOcclusion = { 1.0, 1.0, 1.0 }; // dummy!
    float3 result = albedo * lerp(1.0, DIFFUSE_MIN, metallic);

    // Apply diffuse lighting component
    result *= mul(lightDirectionDifferences, lightmapColors);
    result *= rcp(max(dot(lightDirectionDifferences, float3(1.0, 1.0, 1.0)), 1.0e-3));
    result *= g_LightmapScale;

    // ^ Diffuse component (multiplies to the final result)
    // -------------------------------------------------------------------------
    // v Specular component (accumulates to the final result)

#ifdef g_PhongEnabled
    float  phongExponent = lerp(PHONG_EXPONENT_MIN, PHONG_EXPONENT_MAX, roughness);
    float3 phongFresnel  = lerp(FRESNEL_MIN, albedo, metallic);
    float3 phongLightDir = g_SunDirection;
    if (g_HasBumpedLightmap) {
        float3 strength = mul(GrayScaleFactor, lightmapColors);
        float3 fakeTangentLightDir = mul(strength, BumpBasis);
        float3 fakeWorldLightDir = mul(fakeTangentLightDir, tangentSpaceWorld);
        phongLightDir = lerp(g_SunDirection, fakeWorldLightDir, saturate(strength));
    }

    float spec = CalcBlinnPhongSpec(worldSpaceNormal, phongLightDir, viewDir, phongExponent);
    float3 phongSpecular = mul(lightDirectionDifferences * spec, lightmapColors);
    phongSpecular *= CalcFresnel(tangentSpaceNormal, tangentViewDir, phongFresnel);
    phongSpecular *= ambientOcclusion;
    phongSpecular *= specularScale;
    phongSpecular *= g_LightmapScale;
    result += phongSpecular;
#endif

#ifdef g_RimEnabled
    float3 worldMeshNormal = i.worldNormalTangentY.xyz;
    float rimExponent = lerp(RIM_EXPONENT_MIN, RIM_EXPONENT_MAX, roughness);
    float rimNormalDotViewDir = saturate(dot(worldMeshNormal, viewDir));
    float rimScale = saturate(pow(1.0 - rimNormalDotViewDir, rimExponent));
    rimScale *= lerp(RIM_METALIC_MIN, RIM_METALIC_MAX, metallic);
    rimScale *= lerp(RIM_ROUGHNESS_MIN, RIM_ROUGHNESS_MAX, roughness);
    rimScale *= saturate(
        (RIMLIGHT_FADE_MAX - i.worldPos_projPosZ.w) /
        (RIMLIGHT_FADE_MAX - RIMLIGHT_FADE_MIN));

    // Use average lightmap color as rim light color
    float3 rimLighting = mul(lightDirectionDifferences, lightmapColors);
    rimLighting = lerp(rimLighting, albedo, metallic);
    rimLighting *= min(rimScale, RIMLIGHT_MAX_SCALE);
    rimLighting *= specularScale;
    rimLighting *= g_LightmapScale;
    result += rimLighting;
#endif

#ifdef g_EnvmapEnabled
    // Envmap specular component
    float3 envmapReflect = reflect(tangentViewDir, tangentSpaceNormal);
    float2 envmapUVOffset = envmapReflect.xy * 7.0;
    envmapUVOffset /= max(tangentScaleSqr, 1.0e-3);
    float2 du = ddx(i.inkUV_worldBumpUV.zw);
    float2 dv = ddy(i.inkUV_worldBumpUV.zw);
    float det = du.x * dv.y - dv.x * du.y;
    det = rcp(det + (det < 0 ? -1.0e-7 : 1.0e-7));
    float2 screenOffset = {
        dot(float2( dv.y, -dv.x), envmapUVOffset) * det,
        dot(float2(-du.y,  du.x), envmapUVOffset) * det,
    };
    float2 fakeSSRUV = saturate((i.screenPos - screenOffset) * RcpFbSize);
    float3 envmapSpecular = tex2D(FrameBuffer, fakeSSRUV).rgb;
    envmapSpecular /= g_TonemapScale;
    envmapSpecular *= smoothstep(-0.35, 0.35, envmapReflect.z);
    envmapSpecular *= step(abs(i.inkBinormalMeshLift.w), 1e-3);

    // Apply envmap contribution
    float3 envmapFresnel = lerp(FRESNEL_MIN, albedo, metallic);
    float  envmapScale   = lerp(ENVMAP_SCALE_MIN, ENVMAP_SCALE_MAX, roughness * roughness);
    float3 envmapAlbedo  = lerp(float3(1.0, 1.0, 1.0), albedo, metallic);
    envmapSpecular *= envmapAlbedo;
    envmapSpecular *= CalcFresnel(worldSpaceNormal, viewDir, envmapFresnel);
    envmapSpecular *= envmapScale;
    envmapSpecular *= ambientOcclusion;
    envmapSpecular *= specularScale;
    envmapSpecular *= g_LightmapScale;
    result += envmapSpecular;
#endif

    // ^ Specular component (accumulates to the final result)
    // -------------------------------------------------------------------------
    // v Depth & alpha calculation

    float alpha = 1.0;
    float newDepth = projPosZ / projPosW;
    if (!g_Simplified && i.projPosW_meshRole.y > 0.125) {
        // The traced hit lies on the same screen ray as the proxy point, so clip-space W
        // scales linearly by the traced ray fraction even when the hit is behind the proxy.
        float4 zRange = CalcNearFarZ(projPosZ, projPosW);
        float minW = zRange.x + 16.0;
        float newW = max(projPosW * traceRayFraction, minW);
        float newZ = zRange.z * newW + zRange.w;
        float meshDepth = projPosZ / projPosW;
        float hitDepth = newZ / newW;
        float maxDepthDiff = max(abs(ddx(hitDepth)), abs(ddy(hitDepth)));
        bool isSideOut = i.projPosW_meshRole.y > 0.875;
        newDepth = isSideOut ? hitDepth : min(meshDepth, hitDepth);
        newDepth -= DEPTH_BASE_BIAS + maxDepthDiff * DEPTH_DIFF_SCALE; // Slightly go towards the camera
        alpha = saturate(1.0 - i.inkBinormalMeshLift.w * smoothstep(LOD_DISTANCE * 0.5, LOD_DISTANCE * 0.875, newW));
    }

    if (debugMode > 0) {
        float3 debugColor = float3(1.0, 0.0, 1.0);
        if (debugMode == 2) {
            debugColor = DebugTexelFraction(inkUV.xy, RcpRTSize);
        }
        else if (debugMode == 3) {
            debugColor = DebugSnapDelta(inkUV.xy, pixelUV, RcpRTSize);
        }
        else if (debugMode == 4) {
            debugColor = DebugHeightDepth(height, inkUV.z, depth);
        }
        else if (debugMode == 5) {
            debugColor = DebugInkIDs(ID1, ID2, idBlend);
        }
        else if (debugMode == 6) {
            debugColor = traceSteps / DEBUG_TRACE_MAX_STEPS;
        }

        PS_OUTPUT debugOutput = { debugColor * g_TonemapScale, alpha, max(newDepth, 0.0) };
        return debugOutput;
    }

    PS_OUTPUT p = { result * g_TonemapScale, alpha, max(newDepth, 0.0) };
    return p;
}
