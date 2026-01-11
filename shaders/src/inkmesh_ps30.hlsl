// Ink Mesh Pixel Shader for SplashSWEPs
// Based on LightmappedGeneric pixel shader with bumped lightmaps

// Samplers
sampler InkAlbedoSampler   : register(s0); // $basetexture - Ink albedo RenderTarget
sampler InkBumpmapSampler  : register(s1); // $texture1 - Ink bumpmap RenderTarget
sampler LightmapSampler    : register(s2); // $texture2 - Lightmap
sampler WorldBumpmapSampler: register(s3); // $texture3 - World geometry bumpmap

const float4 c0 : register(c0);
#define g_InkNormalBlendAlpha c0.x;

// Constants
const float4 g_EyePos : register(c1); // $c1 - xyz: eye position

static const float g_TintValuesAndLightmapScale = 4.5947934199881400271945077871117; // 2 ^ 2.2

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

float4 main(PS_INPUT i) : COLOR {
    // Sample ink albedo
    float4 inkAlbedoSample = tex2D(InkAlbedoSampler, i.inkUV_worldBumpUV.xy);

    // Early alpha test
    clip(inkAlbedoSample.a - 0.0625);

    // Sample ink bumpmap (tangent space normal)
    float4 inkNormalSample = tex2D(InkBumpmapSampler, i.inkUV_worldBumpUV.xy);
    float3 inkNormal = inkNormalSample.xyz * 2.0 - 1.0;

    // Sample world bumpmap
    float4 worldNormalSample = tex2D(WorldBumpmapSampler, i.inkUV_worldBumpUV.zw);
    float3 worldNormal = worldNormalSample.xyz * 2.0 - 1.0;

    // Handle missing world bumpmap (default to flat normal)
    if (worldNormalSample.x == 0 && worldNormalSample.y == 0 && worldNormalSample.z == 0) {
        worldNormal = float3(0.0, 0.0, 1.0);
    }

    // Blend ink and world normals based on ink alpha
    float inkAlpha = inkNormalSample.a * g_InkNormalBlendAlpha;
    float3 blendedNormal = BlendNormals(worldNormal, inkNormal, inkAlpha);

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
        diffuseLighting *= g_TintValuesAndLightmapScale / max(sum, 0.001);
    }
    else {
        float3 lightmapColor1 = tex2D(LightmapSampler, i.lightmapUV1And2.xy).rgb;
        diffuseLighting = lightmapColor1 * g_TintValuesAndLightmapScale;
    }

    // Apply vertex color (modulation)
    float3 albedo = inkAlbedoSample.rgb; // * i.vertexColor.rgb;

    // Final color
    float3 result = albedo * diffuseLighting;

    return float4(result, inkAlbedoSample.a);
}
