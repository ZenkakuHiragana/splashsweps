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

// Samplers
sampler InkAlbedoSampler   : register(s0); // $basetexture - Ink albedo RenderTarget
sampler InkBumpmapSampler  : register(s1); // $texture1    - Ink bumpmap RenderTarget
sampler InkMaterialSampler : register(s2); // $texture2    - Pseudo-PBR RenderTarget
sampler LightmapSampler    : register(s3); // $texture3    - Lightmap
samplerCUBE EnvmapSampler  : register(s4); // $texture4    - Environment map (cubemap)
sampler GeometorySampler   : register(s5); // $texture5    - World geometry bumpmap

// Constants
const float4 c0        : register(c0);
const float4 c1        : register(c1);
const float4 c2        : register(c2);
const float4 c3        : register(c3);
const float4 g_EyePos  : register(c10); // xyz: eye position
const float4 HDRParams : register(c30);

#define g_SunDirection         c0.xyz // in world space
#define g_InkNormalBlendFactor c0.w
#define g_HasBumpedLightmap    c1.x
#define g_TonemapScale  HDRParams.x
#define g_LightmapScale HDRParams.y
#define g_EnvmapScale   HDRParams.z
#define g_GammaScale    HDRParams.w // = TonemapScale ^ (1 / 2.2)

static const float3 GrayScaleFactor = { 0.2126, 0.7152, 0.0722 };

// Bumped lightmap basis vectors (same as LightmappedGeneric) in tangent space
static const float3x3 BumpBasis = {
    float3( 0.81649661064147949,  0.0,                 0.57735025882720947),
    float3(-0.40824833512306213,  0.70710676908493042, 0.57735025882720947),
    float3(-0.40824833512306213, -0.70710676908493042, 0.57735025882720947),
};

struct PS_INPUT {
    float4   inkUV_worldBumpUV     : TEXCOORD0; // xy: ink albedo UV, zw: world bumpmap UV
    float4   lightmapUV1And2       : TEXCOORD1; // xy: lightmap UV, zw: bumpmapped lightmap UV (1)
    float4   lightmapUV3           : TEXCOORD2; // xy: bumpmapped lightmap UV (2)
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

// Samples lighting parameters from texture sampler
void FetchInkMaterial(
    float2 uv,
    out float metallic,
    out float roughness,
    out float ambientOcclusion,
    out float specularMask) {
    float4 materialSample = tex2D(InkMaterialSampler, uv);
    metallic         = materialSample.r;
    roughness        = materialSample.g;
    ambientOcclusion = materialSample.b;
    specularMask     = materialSample.a;
}

// Samples bumpmap pixel from painted ink and scales it to [-1, 1] range
void FetchInkNormal(float2 uv, out float3 normal, out float alpha) {
    float4 inkNormalSample = tex2D(InkBumpmapSampler, uv);
    normal = inkNormalSample.xyz * 2.0 - 1.0;
    alpha  = inkNormalSample.a;
}

// Samples bumpmap pixel from geometry texture and scales it to [-1, 1] range
void FetchGeometryNormal(float2 uv, out float3 geometryNormal) {
    // Sample world bumpmap
    geometryNormal = tex2D(GeometorySampler, uv).xyz;
    geometryNormal *= 2.0;
    geometryNormal -= 1.0;

    // Handle missing world bumpmap (default to flat normal)
    bool noWorldBump =
        geometryNormal.x == -1.0 &&
        geometryNormal.y == -1.0 &&
        geometryNormal.z == -1.0;
    if (noWorldBump) {
        geometryNormal = float3(0.0, 0.0, 1.0);
    }
}

float4 main(PS_INPUT i) : COLOR {
    // Sample ink albedo
    float4 inkAlbedoSample = tex2D(InkAlbedoSampler, i.inkUV_worldBumpUV.xy);
    clip(inkAlbedoSample.a - ALBEDO_ALPHA_MIN); // Early alpha test

    // Sample the other necessary info
    float inkNormalAlpha;
    float metallic, roughness, ambientOcclusion, specularMask;
    float3 inkNormal, geometryNormal;
    FetchInkNormal(i.inkUV_worldBumpUV.xy, inkNormal, inkNormalAlpha);
    FetchInkMaterial(i.inkUV_worldBumpUV.xy, metallic, roughness, ambientOcclusion, specularMask);
    FetchGeometryNormal(i.inkUV_worldBumpUV.zw, geometryNormal);

    // Blend ink and world normals
    float3 tangentSpaceNormal = normalize(lerp(geometryNormal, inkNormal, g_InkNormalBlendFactor));
    float3 worldSpaceNormal = normalize(mul(tangentSpaceNormal, i.tangentSpaceTranspose));

    // Transform view direction to tangent space
    float3 eyeDirection = normalize(g_EyePos.xyz - i.worldPos_projPosZ.xyz);
    float3 tangentViewDir = float3(
        dot(eyeDirection, i.tangentSpaceTranspose[0]),
        dot(eyeDirection, i.tangentSpaceTranspose[1]),
        dot(eyeDirection, i.tangentSpaceTranspose[2]));

    // Set up the final result (then modified later)
    float3 albedo = inkAlbedoSample.rgb;
    float3 result = albedo * ambientOcclusion * lerp(1.0, DIFFUSE_MIN, metallic);

    float3x3 lightmapColors;
    float3   lightDirectionDifferences;
    if (g_HasBumpedLightmap) {
        // Sample 3 directional lightmaps
        lightmapColors = float3x3(
            tex2D(LightmapSampler, i.lightmapUV1And2.xy).rgb,
            tex2D(LightmapSampler, i.lightmapUV1And2.zw).rgb,
            tex2D(LightmapSampler, i.lightmapUV3.xy).rgb);

        // Compute diffuse lighting using bumped lightmaps
        lightDirectionDifferences = float3(
            saturate(dot(tangentSpaceNormal, BumpBasis[0])),
            saturate(dot(tangentSpaceNormal, BumpBasis[1])),
            saturate(dot(tangentSpaceNormal, BumpBasis[2])));

        // Square for softer falloff
        lightDirectionDifferences *= lightDirectionDifferences;

        // Apply diffuse lighting component
        result *= mul(lightDirectionDifferences, lightmapColors);
        result *= rcp(max(dot(lightDirectionDifferences, float3(1.0, 1.0, 1.0)), 1.0e-3));
        result *= g_LightmapScale;
    }
    else {
        // Non-bumpmapped surface: single lightmap sample
        lightmapColors[0] = tex2D(LightmapSampler, i.lightmapUV1And2.xy).rgb;
        lightDirectionDifferences = float3(1.0, 0.0, 0.0);
        result *= lightmapColors[0];
        result *= g_LightmapScale;
    }

    // ^ Diffuse component (multiplies to the final result)
    // ------------------------------------------------------
    // v Specular component (accumulates to the final result)

#ifdef g_PhongEnabled
    float  phongExponent = lerp(PHONG_EXPONENT_MIN, PHONG_EXPONENT_MAX, roughness);
    float3 phongFresnel  = lerp(FRESNEL_MIN, albedo, metallic);
    float3 phongLightDir = g_SunDirection;
    float3 phongSpecular;
    if (g_HasBumpedLightmap) {
        float3 strength = mul(GrayScaleFactor, lightmapColors);
        float3 fakeTangentLightDir = mul(strength, BumpBasis);
        float3 fakeWorldLightDir = mul(fakeTangentLightDir, i.tangentSpaceTranspose);
        phongLightDir = lerp(g_SunDirection, fakeWorldLightDir, saturate(strength));
    }

    float spec = CalcBlinnPhongSpec(worldSpaceNormal, phongLightDir, eyeDirection, phongExponent);
    phongSpecular = mul(lightDirectionDifferences * spec, lightmapColors);
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

    return float4(result * g_TonemapScale, inkAlbedoSample.a);
}
