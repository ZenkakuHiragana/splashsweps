// Ink Mesh Pixel Shader for SplashSWEPs
// Based on LightmappedGeneric pixel shader with bumped lightmaps

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
static const float THICKNESS_SCALE = 1.0e-2;
static const float THICKNESS_SCALE_SCREENSPACE = 128;
static const float3 GrayScaleFactor = { 0.2126, 0.7152, 0.0722 };

// Samplers
sampler2D   AdditiveAndHeightMap        : register(s0);
sampler2D   MultiplicativeAndRefraction : register(s5);
sampler2D   InkMaterialSampler          : register(s2);
sampler2D   InkDetailSampler            : register(s3);
sampler2D   WallBumpmapSampler          : register(s4);
sampler2D   WallAlbedoSampler           : register(s1);
sampler2D   LightmapSampler             : register(s6);
samplerCUBE EnvmapSampler               : register(s7);

// If the base geometry is WorldVertexTransition,
// the albedo sampler becomes a frame buffer
#define FrameBufferSampler WallAlbedoSampler

// Constants
const float4 c0          : register(c0);
const float4 c1          : register(c1);
const float4 c2          : register(c2);
const float4 c3          : register(c3);
const float2 RcpBaseSize : register(c4); // One over texture size
const float2 RcpFbSize   : register(c5); // One over frame buffer size
const float4 c6          : register(c6);
const float4 c7          : register(c7);
const float4 c8          : register(c8);
const float4 c9          : register(c9);
const float4 g_EyePos    : register(c10); // xyz: eye position
const float2x4 BaseTextureTransform : register(c11);
const float2x4 BumpTextureTransform : register(c15);
const float4 HDRParams   : register(c30);

#define g_SunDirection      c0.xyz // in world space
#define g_Unused            c0.w
#define g_HasBumpedLightmap c1.x
#define g_NeedsFrameBuffer  c1.y   // True when WorldVertexTransition or Lightmapped_4WayBlend

#define g_TonemapScale  HDRParams.x
#define g_LightmapScale HDRParams.y
#define g_EnvmapScale   HDRParams.z
#define g_GammaScale    HDRParams.w // = TonemapScale ^ (1 / 2.2)

// Bumped lightmap basis vectors (same as LightmappedGeneric) in tangent space
static const float3x3 BumpBasis = {
    float3( 0.81649661064147949,  0.0,                 0.57735025882720947),
    float3(-0.40824833512306213,  0.70710676908493042, 0.57735025882720947),
    float3(-0.40824833512306213, -0.70710676908493042, 0.57735025882720947),
};

struct PS_INPUT {
    float2   screenPos             : VPOS;
    float4   inkUV_worldBumpUV     : TEXCOORD0; // xy: ink albedo UV, zw: world bumpmap UV
    float4   lightmapUV1And2       : TEXCOORD1; // xy: lightmap UV, zw: bumpmapped lightmap UV (1)
    float4   lightmapUV3_projPosXY : TEXCOORD2; // xy: bumpmapped lightmap UV (2)
    float4   worldPos_projPosZ     : TEXCOORD3;
    float3x3 tangentSpaceTranspose : TEXCOORD4; // TEXCOORD4, 5, 6
};

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

// Samples additive color and height value
void FetchAdditiveAndHeight(float2 uv, out float3 additive, out float height, out float3 normal) {
    float4 s = tex2D(AdditiveAndHeightMap, uv);
    additive = s.rgb;
    height   = s.a;

    // Additional samples to calculate tangent space normal
    float hx = tex2D(AdditiveAndHeightMap, uv + float2(RcpBaseSize.x, 0)).a;
    float hy = tex2D(AdditiveAndHeightMap, uv + float2(0, RcpBaseSize.y)).a;
    float dx = hx - height;
    float dy = hy - height;
    normal = normalize(float3(-dx, -dy, 1.0));
}

// Samples multiplicative color and refraction strength
void FetchMultiplicativeAndRefraction(float2 uv, out float3 multiplicative, out float refraction) {
    float4 s = tex2D(MultiplicativeAndRefraction, uv);
    multiplicative = s.rgb;
    refraction     = s.a;
}

// Samples lighting parameters from texture sampler
void FetchInkMaterial(
    float2 uv,
    out float metallic,
    out float roughness,
    out float specularMask,
    out float inkNormalBlendFactor) {
    float4 s = tex2D(InkMaterialSampler, uv);
    metallic             = s.r;
    roughness            = s.g;
    specularMask         = s.b;
    inkNormalBlendFactor = s.a;
}

// Samples detail component
void FetchInkDetails(
    float2 uv,
    out float unused1,
    out float unused2,
    out float unused3,
    out float miscibility) {
    float4 s = tex2D(InkDetailSampler, uv);
    unused1     = s.r;
    unused2     = s.g;
    unused3     = s.b;
    miscibility = s.a;
}

// Samples albedo and bumpmap pixel from geometry textures
void FetchGeometrySamples(
    float2 bumpUV,
    float2 baseUV,
    float3x3 lightmapColors,
    out float3 geometryAlbedo,
    out float3 geometryNormal) {
    // Sample world bumpmap
    float2 uv = mul(BumpTextureTransform, float4(bumpUV, 1.0, 1.0));
    geometryNormal = tex2D(WallBumpmapSampler, uv).rgb;
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
        float4 frameBufferSample = tex2D(FrameBufferSampler, baseUV) / (g_TonemapScale * g_LightmapScale);
        float3 lightDirectionDifferences = hasNoBump
            ? float3(1.0, 0.0, 0.0)
            : float3(saturate(dot(geometryNormal, BumpBasis[0])),
                     saturate(dot(geometryNormal, BumpBasis[1])),
                     saturate(dot(geometryNormal, BumpBasis[2])));
        float3 lightmapColorExpected = mul(lightDirectionDifferences, lightmapColors);
        geometryAlbedo = frameBufferSample.rgb / max(lightmapColorExpected, 1e-4);
    }
    else {
        uv = mul(BaseTextureTransform, float4(baseUV, 1.0, 1.0));
        geometryAlbedo = tex2D(WallAlbedoSampler, uv).rgb;
    }
}

float4 main(PS_INPUT i) : COLOR {
    // Set up UV coordinates
    float2 inkUV = i.inkUV_worldBumpUV.xy;
    float4 inkDetail = tex2D(InkDetailSampler, inkUV);
    clip(inkDetail.a - 0.5 / 255.0); // if inkDetail.a == 0.0, no paint here

    // Transform view direction to tangent space
    float3 eyeDirection = normalize(g_EyePos.xyz - i.worldPos_projPosZ.xyz);
    float3 tangentViewDir = mul(i.tangentSpaceTranspose, eyeDirection);

    // Sample 3 directional lightmaps
    float3x3 lightmapColors = {
        tex2D(LightmapSampler, i.lightmapUV1And2.xy).rgb,
        tex2D(LightmapSampler, i.lightmapUV1And2.zw).rgb,
        tex2D(LightmapSampler, i.lightmapUV3_projPosXY.xy).rgb,
    };

    // Samples ink parameters
    float3 additive, multiplicative, inkNormal;
    float3 geometryAlbedo, geometryNormal;
    float height, refraction, metallic, roughness, specularMask, inkNormalBlendFactor;
    FetchAdditiveAndHeight(inkUV, additive, height, inkNormal);
    FetchMultiplicativeAndRefraction(inkUV, multiplicative, refraction);
    FetchInkMaterial(inkUV, metallic, roughness, specularMask, inkNormalBlendFactor);

    float  thickness = (height + 1) * THICKNESS_SCALE;
    float2 uvOffset = inkNormal.xy; // refraction by normal
    uvOffset += tangentViewDir.xy / max(tangentViewDir.z, 1e-3) * thickness; // parallax effect
    uvOffset *= refraction;

    float2 bumpUV = i.inkUV_worldBumpUV.zw + uvOffset;
    float2 baseUV = bumpUV;
    if (g_NeedsFrameBuffer) {
        float2 du = ddx(uvOffset);
        float2 dv = ddy(uvOffset);
        float det = du.x * dv.y - dv.x * du.y;
        det = rcp(det + (det < 0 ? -1e-7 : 1e-7));
        float2 su = float2( dv.y, -du.y) * det;
        float2 sv = float2(-dv.x,  du.x) * det;
        float3 meshNormal = i.tangentSpaceTranspose[2];
        float meshAngleFactor = dot(meshNormal, eyeDirection);
        float2 pixelOffset = uvOffset.x * su + uvOffset.y * sv;
        pixelOffset *= step(0, meshAngleFactor); // disable if not facing at all
        pixelOffset *= rcp(max(i.worldPos_projPosZ.w, 1e-3)); // fade by distance
        pixelOffset *= THICKNESS_SCALE_SCREENSPACE;
        float2 finalUV = (i.screenPos - pixelOffset) * RcpFbSize;
        float2 fade = smoothstep(0.0, 0.05, finalUV) * smoothstep(1.0, 0.55, finalUV);
        baseUV = lerp(i.screenPos * RcpFbSize, finalUV, fade);
    }
    FetchGeometrySamples(bumpUV, baseUV, lightmapColors, geometryAlbedo, geometryNormal);

    // Blend ink and world normals
    float3 tangentSpaceNormal = normalize(lerp(geometryNormal, inkNormal, inkNormalBlendFactor));
    float3 worldSpaceNormal = normalize(mul(tangentSpaceNormal, i.tangentSpaceTranspose));

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
    // ------------------------------------------------------
    // v Specular component (accumulates to the final result)

#ifdef g_PhongEnabled
    float  phongExponent = lerp(PHONG_EXPONENT_MIN, PHONG_EXPONENT_MAX, roughness);
    float3 phongFresnel  = lerp(FRESNEL_MIN, albedo, metallic);
    float3 phongLightDir = g_SunDirection;
    if (g_HasBumpedLightmap) {
        float3 strength = mul(GrayScaleFactor, lightmapColors);
        float3 fakeTangentLightDir = mul(strength, BumpBasis);
        float3 fakeWorldLightDir = mul(fakeTangentLightDir, i.tangentSpaceTranspose);
        phongLightDir = lerp(g_SunDirection, fakeWorldLightDir, saturate(strength));
    }

    float spec = CalcBlinnPhongSpec(worldSpaceNormal, phongLightDir, eyeDirection, phongExponent);
    float3 phongSpecular = mul(lightDirectionDifferences * spec, lightmapColors);
    phongSpecular *= CalcFresnel(tangentSpaceNormal, tangentViewDir, phongFresnel);
    phongSpecular *= ambientOcclusion;
    phongSpecular *= specularMask;
    phongSpecular *= g_LightmapScale;
    result += phongSpecular;
#endif

#ifdef g_RimEnabled
    float3 worldMeshNormal = i.tangentSpaceTranspose[2];
    float rimExponent = lerp(RIM_EXPONENT_MIN, RIM_EXPONENT_MAX, roughness);
    float rimNormalDotViewDir = saturate(dot(worldMeshNormal, eyeDirection));
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
    rimLighting *= specularMask;
    rimLighting *= g_LightmapScale;
    result += rimLighting;
#endif

#ifdef g_EnvmapEnabled
    // Envmap specular component
    float3 envmapFresnel  = lerp(FRESNEL_MIN, albedo, metallic);
    float3 envmapReflect  = -reflect(eyeDirection, worldSpaceNormal);
    float3 envmapSpecular = texCUBE(EnvmapSampler, envmapReflect).rgb;

    // Apply envmap contribution
    float  envmapScale  = lerp(ENVMAP_SCALE_MIN, ENVMAP_SCALE_MAX, roughness * roughness);
    float3 envmapAlbedo = lerp(float3(1.0, 1.0, 1.0), albedo, metallic);
    envmapSpecular *= envmapAlbedo;
    envmapSpecular *= CalcFresnel(worldSpaceNormal, eyeDirection, envmapFresnel);
    envmapSpecular *= envmapScale;
    envmapSpecular *= ambientOcclusion;
    envmapSpecular *= specularMask;
    envmapSpecular *= g_LightmapScale;
    result += envmapSpecular;
#endif

    return float4(result * g_TonemapScale, 1.0);
}
