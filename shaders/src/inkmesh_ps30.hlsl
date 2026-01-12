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

const float4 c2 : register(c2);
#define g_PhongEnabled  c2.x
#define g_PhongExponent c2.y
#define g_PhongStrength c2.z
#define g_PhongFresnel  c2.w

const float4 g_SunDirection : register(c3); // xyz: the sun direction

const float4 g_EyePos     : register(c10); // xyz: eye position
const float4 HDRParams    : register(c30);
#define g_TonemapScale  HDRParams.x
#define g_LightmapScale HDRParams.y
#define g_EnvmapScale   HDRParams.z
#define g_GammaScale    HDRParams.w // = TonemapScale ^ (1 / 2.2)

// Bumped lightmap basis vectors (same as LightmappedGeneric)
// These are in tangent space
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
    float3 blended = lerp(n1, n2, blendFactor);
    return normalize(blended);
}

// Calculate reflection vector
float3 CalcReflectionVector(float3 normal, float3 eyeVector) {
    return 2.0 * dot(normal, eyeVector) * normal - eyeVector;
}

// Blinn-Phong specular calculation
float CalcBlinnPhongSpec(float3 normal, float3 lightDir, float3 viewDir, float exponent) {
    float3 halfVector = normalize(lightDir + viewDir);
    float nDotH = saturate(dot(normal, halfVector));
    return pow(nDotH, exponent);
}

float3 ApplyFresnel(float3 specularNormal, float3 tangentViewDir) {
    // Apply Fresnel for rim highlights
    float nDotV = saturate(dot(specularNormal, tangentViewDir));
    float phongFresnel = pow(1.0 - nDotV, 5.0);
    phongFresnel = phongFresnel * (1.0 - g_PhongFresnel) + g_PhongFresnel;
    return g_PhongStrength * phongFresnel * g_LightmapScale;
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
    bool noWorldBump =
        geometoryNormal.x == -1.0 &&
        geometoryNormal.y == -1.0 &&
        geometoryNormal.z == -1.0;
    if (noWorldBump) {
        geometoryNormal = float3(0.0, 0.0, 1.0);
    }

    // Blend ink and world normals based on ink alpha
    float inkAlpha = inkNormalSample.a * g_InkNormalBlendAlpha;
    float3 blendedNormal = BlendNormals(geometoryNormal, inkNormal, inkAlpha);

    // Blend factor of ink/world normals for specular
    float specularInkBlend = inkAlpha;
    float3 specularNormal = BlendNormals(geometoryNormal, inkNormal, specularInkBlend);

    // Transform blended normal to world space
    float3 worldSpaceNormal = normalize(mul(blendedNormal, i.tangentSpaceTranspose));
    float3 worldSpaceSpecNormal = normalize(mul(specularNormal, i.tangentSpaceTranspose));

    // Calculate view direction (for specular)
    float3 worldVertToEyeVector = g_EyePos.xyz - i.worldPos_projPosZ.xyz;
    float3 eyeVect = normalize(worldVertToEyeVector);

    // Transform view direction to tangent space for Phong calculation
    float3 tangentViewDir = float3(
        dot(eyeVect, i.tangentSpaceTranspose[0]),
        dot(eyeVect, i.tangentSpaceTranspose[1]),
        dot(eyeVect, i.tangentSpaceTranspose[2])
    );
    tangentViewDir = normalize(tangentViewDir);

    float3 diffuseLighting = float3(0.0, 0.0, 0.0);
    float3 phongSpecular = float3(0.0, 0.0, 0.0);

    bool hasBumpedLightmap = i.lightmapUV3.z > 0;
    if (hasBumpedLightmap) {
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

        // Phong specular from bumped lightmap directions
        if (g_PhongEnabled > 0.0) {
            float exponent = max(g_PhongExponent, 1.0);

            // Calculate specular for each lightmap direction (in tangent space)
            float spec1 = CalcBlinnPhongSpec(specularNormal, bumpBasis[0], tangentViewDir, exponent);
            float spec2 = CalcBlinnPhongSpec(specularNormal, bumpBasis[1], tangentViewDir, exponent);
            float spec3 = CalcBlinnPhongSpec(specularNormal, bumpBasis[2], tangentViewDir, exponent);

            // Weight by lightmap intensity and diffuse factor
            phongSpecular
                = spec1 * lightmapColor1 * dp.x
                + spec2 * lightmapColor2 * dp.y
                + spec3 * lightmapColor3 * dp.z;

            // Apply Fresnel for rim highlights
            phongSpecular *= ApplyFresnel(specularNormal, tangentViewDir);
        }
    }
    else {
        // Non-bumpmapped surface: single lightmap sample
        float3 lightmapColor = tex2D(LightmapSampler, i.lightmapUV1And2.xy).rgb;
        diffuseLighting = lightmapColor * g_LightmapScale;

        // Phong for non-bumpmapped surfaces using default light direction
        if (g_PhongEnabled > 0.0) {
            float exponent = max(g_PhongExponent, 1.0);

            // Use specularNormal which includes ink bumpmap
            float spec = CalcBlinnPhongSpec(specularNormal, g_SunDirection.xyz, tangentViewDir, exponent);

            // Use lightmap intensity as light color (halves it because it looks too shiny)
            phongSpecular = spec * lightmapColor * 0.5;

            // Apply Fresnel for rim highlights
            phongSpecular *= ApplyFresnel(specularNormal, tangentViewDir);
        }
    }

    // Diffuse component
    float3 albedo = inkAlbedoSample.rgb;
    float3 diffuseComponent = albedo * diffuseLighting;

    // Envmap specular component
    float3 envmapSpecular = float3(0.0, 0.0, 0.0);
    if (g_EnvmapEnabled > 0.0) {
        // Calculate reflection vector
        float3 reflectVect = CalcReflectionVector(worldSpaceSpecNormal, eyeVect);

        // Fresnel factor (Schlick approximation)
        float fresnel = 1.0 - saturate(dot(worldSpaceSpecNormal, eyeVect));
        fresnel = pow(fresnel, 5.0);
        fresnel = fresnel * (1.0 - g_FresnelReflection) + g_FresnelReflection;

        // Sample environment map
        float3 envmapColor = texCUBE(EnvmapSampler, reflectVect).rgb;

        // Apply envmap contribution
        envmapSpecular = envmapColor * g_EnvmapTint.rgb * fresnel * g_EnvmapStrength * g_EnvmapScale;
    }

    // Final color
    float3 result = diffuseComponent + phongSpecular + envmapSpecular;

    return float4(result * g_TonemapScale, inkAlbedoSample.a);
}
