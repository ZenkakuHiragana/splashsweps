// Ink Mesh Pixel Shader for SplashSWEPs
// Based on LightmappedGeneric pixel shader with bumped lightmaps

// Samplers
sampler InkAlbedoSampler  : register(s0); // $basetexture - Ink albedo RenderTarget
sampler InkBumpmapSampler : register(s1); // $texture1 - Ink bumpmap RenderTarget
sampler LightmapSampler   : register(s2); // $texture2 - Lightmap
sampler GeometorySampler  : register(s3); // $texture3 - World geometry bumpmap
samplerCUBE EnvmapSampler : register(s4); // $texture4 - Environment map (cubemap)

#define g_EnvmapEnabled
#define g_PhongEnabled
#define g_RimEnabled
#define g_FakeAOEnabled

// Constants
const float4 c0 : register(c0);
const float4 c1 : register(c1);
const float4 c2 : register(c2);
const float4 c3 : register(c3);

#define g_EnvmapTint          c0.xyz
#define g_InkNormalBlendAlpha c0.w
#define g_EnvmapFresnel       c1.x
#define g_EnvmapStrength      c1.y
#define g_PhongFresnel        c1.z
#define g_PhongStrength       c1.w
#define g_RimExponent         c2.x   // 2-6 recommended
#define g_RimStrength         c2.y   // 0.1-0.5 recommended
#define g_RimBoost            c2.z   // How much bumpiness affects rim (0-1)
#define g_Unused              c2.w
#define g_SunDirection        c3.xyz // in world space
#define g_PhongExponent       c3.w

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

// Calculate rim lighting - highlights edges and reveals bumps from all angles
float CalcRimLight(float3 normal, float3 viewDir, float exponent, float bumpInfluence) {
    float nDotV = dot(normal, viewDir);

    // Basic rim: bright at edges (where nDotV is low)
    float rim = 1.0 - saturate(nDotV);
    rim = pow(rim, exponent);

    // Add variation based on normal deviation from flat
    // This makes bumps visible even when facing away from light
    float3 flatNormal = float3(0.0, 0.0, 1.0);
    float normalDeviation = 1.0 - saturate(dot(normal, flatNormal));

    // Boost rim where normal differs from flat (shows bumps)
    rim += normalDeviation * bumpInfluence * rim;

    return saturate(rim);
}

// Fake AO / Cavity Shadow - darkens concave areas based on normal
// This creates depth by adding shadows instead of highlights
float CalcFakeAO(float3 normal, float3 lightDir) {
    // Hardcoded parameters (adjust these to taste)
    static const float CAVITY_STRENGTH = 1;    // Overall strength
    static const float CAVITY_POWER    = 0.75; // Controls falloff sharpness

    float3 flatNormal = float3(0.0, 0.0, 1.0);

    // 1. Normal deviation from flat - areas that aren't facing "up" get darker
    //    This darkens slopes and areas where bumpmap causes tilting
    float normalDeviation = 1.0 - saturate(dot(normal, flatNormal));

    // 2. Cavity detection - areas facing away from light get darker
    //    Use the passed light direction (or average of bump basis)
    float nDotL = dot(normal, lightDir);
    float cavityFromLight = saturate(-nDotL * 0.5 + 0.5); // Remap [-1,1] to darkening factor

    // 3. Combine factors - use the stronger of the two
    float cavity = max(normalDeviation, cavityFromLight * 0.5);

    // Apply power curve for sharper transitions
    cavity = pow(cavity, CAVITY_POWER);

    // Return as multiplier (1.0 = no darkening, 0.0 = full black)
    // We only partially apply the effect based on strength
    return saturate(1.0 - (cavity * CAVITY_STRENGTH));
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
    float3 lightmapColorForRim = float3(0.0, 0.0, 0.0);

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

        // Average lightmap color for rim lighting
        lightmapColorForRim = (lightmapColor1 + lightmapColor2 + lightmapColor3) / 3.0;

        // Phong specular from bumped lightmap directions
#ifdef g_PhongEnabled
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
#endif
    }
    else {
        // Non-bumpmapped surface: single lightmap sample
        float3 lightmapColor = tex2D(LightmapSampler, i.lightmapUV1And2.xy).rgb;
        diffuseLighting = lightmapColor * g_LightmapScale;
        lightmapColorForRim = lightmapColor;

        // Phong for non-bumpmapped surfaces using default light direction
#ifdef g_PhongEnabled
            float exponent = max(g_PhongExponent, 1.0);

            // Use specularNormal which includes ink bumpmap
            float spec = CalcBlinnPhongSpec(specularNormal, g_SunDirection, tangentViewDir, exponent);

            // Use lightmap intensity as light color (halves it because it looks too shiny)
            phongSpecular = spec * lightmapColor * 0.5;

            // Apply Fresnel for rim highlights
            phongSpecular *= ApplyFresnel(specularNormal, tangentViewDir);
#endif
    }

    // Rim lighting - reveals bumps from all angles
    float3 rimLighting = float3(0.0, 0.0, 0.0);
#ifdef g_RimEnabled
        float rimExponent = max(g_RimExponent, 1.0);
        float rimValue = CalcRimLight(specularNormal, tangentViewDir, rimExponent, g_RimBoost);

        // Use lightmap color as rim light color (slightly desaturated for subtle effect)
        float3 rimColor = lerp(lightmapColorForRim, float3(1.0, 1.0, 1.0), 0.3);
        rimLighting = rimValue * rimColor * g_RimStrength * g_LightmapScale;
#endif

#ifdef g_FakeAOEnabled
    // Fake AO / Cavity Shadow - darkens concave areas for depth
    // Use upward direction in tangent space as primary "light" for AO
    float3 aoLightDir = float3(0.0, 0.0, 1.0);
    float fakeAO = CalcFakeAO(specularNormal, aoLightDir);
#else
    const float fakeAO = 1.0;
#endif

    // Diffuse component with fake AO applied
    float3 albedo = inkAlbedoSample.rgb;
    float3 diffuseComponent = albedo * diffuseLighting * fakeAO;

    // Envmap specular component
    float3 envmapSpecular = float3(0.0, 0.0, 0.0);
#ifdef g_EnvmapEnabled
        // Calculate reflection vector
        float3 reflectVect = CalcReflectionVector(worldSpaceSpecNormal, eyeVect);

        // Fresnel factor (Schlick approximation)
        float fresnel = 1.0 - saturate(dot(worldSpaceSpecNormal, eyeVect));
        fresnel = pow(fresnel, 5.0);
        fresnel = fresnel * (1.0 - g_EnvmapFresnel) + g_EnvmapFresnel;

        // Sample environment map
        float3 envmapColor = texCUBE(EnvmapSampler, reflectVect).rgb;

        // Apply envmap contribution
        envmapSpecular = envmapColor * g_EnvmapTint * fresnel * g_EnvmapStrength * g_EnvmapScale;
#endif

    // Final color
    float3 result = diffuseComponent + phongSpecular + rimLighting + envmapSpecular;

    return float4(result * g_TonemapScale, inkAlbedoSample.a);
}
