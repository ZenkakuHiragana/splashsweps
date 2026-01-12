// Ink Mesh Pixel Shader for SplashSWEPs
// Based on LightmappedGeneric pixel shader with bumped lightmaps

// Samplers
sampler InkAlbedoSampler  : register(s0); // $basetexture - Ink albedo RenderTarget
sampler InkBumpmapSampler : register(s1); // $texture1 - Ink bumpmap RenderTarget
sampler LightmapSampler   : register(s2); // $texture2 - Lightmap
sampler GeometorySampler  : register(s3); // $texture3 - World geometry bumpmap
samplerCUBE EnvmapSampler : register(s4); // $texture4 - Environment map (cubemap)

const float4 c0 : register(c0);
#define g_InkNormalBlendAlpha c0.x
#define g_EnvmapEnabled       c0.y
#define g_FresnelReflection   c0.z
#define g_EnvmapStrength      c0.w

// Constants
const float4 g_EnvmapTint : register(c1);  // xyz: envmap tint color
const float4 g_EyePos     : register(c10); // xyz: eye position
const float4 HDRParams    : register(c30);
#define g_TonemapScale  HDRParams.x
#define g_LightmapScale HDRParams.y
#define g_EnvmapScale   HDRParams.z
#define g_GammaScale    HDRParams.w // = TonemapScale ^ (1 / 2.2)

// Bumped lightmap basis vectors (same as LightmappedGeneric)
static const float3 bumpBasis[3] = {
    float3(0.81649661064147949, 0.0, 0.57735025882720947),
    float3(-0.40824833512306213, 0.70710676908493042, 0.57735025882720947),
    float3(-0.40824833512306213, -0.70710676908493042, 0.57735025882720947)
};

struct PS_INPUT {
    float4   inkUV_worldBumpUV     : TEXCOORD0; // xy: ink albedo UV, zw: world bumpmap UV
    float4   lightmapUV1And2       : TEXCOORD1; // xy: lightmap UV, zw: bumpmapped lightmap UV (1)
    float4   lightmapUV3           : TEXCOORD2; // xy: bumpmapped lightmap UV (2)
    float4   worldPos_projPosZ     : TEXCOORD3;
    float3x3 tangentSpaceTranspose : TEXCOORD4; // TEXCOORD4, 5, 6
    float4   vertexColor           : COLOR0;
};

// Blend two normals using RNM (Reoriented Normal Mapping)
float3 BlendNormals(float3 n1, float3 n2, float blendFactor) {
    // Simple lerp blend for now
    float3 blended = lerp(n1, n2, blendFactor);
    return normalize(blended);
}

// Calculate reflection vector (unnormalized)
float3 CalcReflectionVector(float3 normal, float3 eyeVector) {
    return 2.0 * dot(normal, eyeVector) * normal - eyeVector;
}

float4 main(PS_INPUT i) : COLOR {
    // Sample ink albedo
    float4 inkAlbedoSample = tex2D(InkAlbedoSampler, i.inkUV_worldBumpUV.xy);

    // Early alpha test
    clip(inkAlbedoSample.a - 0.0625);

    // Sample ink bumpmap (tangent space normal)
    float4 inkNormalSample = tex2D(InkBumpmapSampler, i.inkUV_worldBumpUV.xy);
    float3 inkNormal = inkNormalSample.xyz * 2.0 - 1.0;

    // Sample world bumpmap
    float3 geometoryNormal = tex2D(GeometorySampler, i.inkUV_worldBumpUV.zw).xyz;
    geometoryNormal *= 2.0;
    geometoryNormal -= 1.0;

    // Handle missing world bumpmap (default to flat normal)
    if (geometoryNormal.x == -1.0 && geometoryNormal.y == -1.0 && geometoryNormal.z == -1.0) {
        geometoryNormal = float3(0.0, 0.0, 1.0);
    }

    // Blend ink and world normals based on ink alpha
    float inkAlpha = inkNormalSample.a * g_InkNormalBlendAlpha;
    float3 blendedNormal = BlendNormals(geometoryNormal, inkNormal, inkAlpha);

    // Transform blended normal to world space
    float3 worldSpaceNormal = normalize(mul(blendedNormal, i.tangentSpaceTranspose));

    float3 diffuseLighting;
    if (i.lightmapUV3.z > 0) {
        // Sample 3 directional lightmaps
        float3 lightmapColor1 = tex2D(LightmapSampler, i.lightmapUV1And2.xy).rgb;
        float3 lightmapColor2 = tex2D(LightmapSampler, i.lightmapUV1And2.wz).rgb; // reversed order!!!
        float3 lightmapColor3 = tex2D(LightmapSampler, i.lightmapUV3.xy).rgb;

        // Compute diffuse lighting using bumped lightmaps
        float3 dp;
        dp.x = saturate(dot(blendedNormal, bumpBasis[0]));
        dp.y = saturate(dot(blendedNormal, bumpBasis[1]));
        dp.z = saturate(dot(blendedNormal, bumpBasis[2]));
        dp *= dp; // Square for softer falloff

        diffuseLighting
            = dp.x * lightmapColor1
            + dp.y * lightmapColor2
            + dp.z * lightmapColor3;

        float sum = dot(dp, float3(1.0, 1.0, 1.0));
        diffuseLighting *= g_LightmapScale / max(sum, 0.001);
    }
    else {
        float3 lightmapColor1 = tex2D(LightmapSampler, i.lightmapUV1And2.xy).rgb;
        diffuseLighting = lightmapColor1 * g_LightmapScale;
    }

    // Diffuse component
    float3 albedo = inkAlbedoSample.rgb;
    float3 diffuseComponent = albedo * diffuseLighting;

    // Specular/Envmap component
    float3 specularLighting = float3(0.0, 0.0, 0.0);
    if (g_EnvmapEnabled > 0.0) {
        // Calculate view direction
        float3 worldVertToEyeVector = g_EyePos.xyz - i.worldPos_projPosZ.xyz;
        float3 eyeVect = normalize(worldVertToEyeVector);

        // Calculate reflection vector
        float3 reflectVect = CalcReflectionVector(worldSpaceNormal, eyeVect);

        // Fresnel factor (Schlick approximation)
        float fresnel = 1.0 - saturate(dot(worldSpaceNormal, eyeVect));
        fresnel = pow(fresnel, 5.0);
        fresnel = fresnel * (1.0 - g_FresnelReflection) + g_FresnelReflection;

        // Sample environment map
        float3 envmapColor = texCUBE(EnvmapSampler, reflectVect).rgb;

        // Apply envmap contribution
        specularLighting = envmapColor * g_EnvmapTint.rgb * fresnel * g_EnvmapStrength * g_EnvmapScale;
    }

    // Final color
    float3 result = diffuseComponent + specularLighting;

    return float4(result * g_TonemapScale, inkAlbedoSample.a);
}
