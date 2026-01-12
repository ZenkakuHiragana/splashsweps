
sampler Albedo : register(s0); // $basetexture
sampler Normal : register(s1); // $texture1
sampler OriginalBaseTexture : register(s2); // $texture2

// Fixed as there is no way to provide current projected texture to draw
sampler FlashlightSampler : register(s3);

// xyz -> OBB size
// w = 1, 2, 3 -> UV expansion pattern
const float4 c0 : register(c0);

// x = 0 -> do nothing special; just rendering
// x = 1 -> additive flashlight
// y -> Hammer Unit to UV multiplier
const float4 c1 : register(c1);

const float4x4 Model_T_World : register(c11);
const float4x4 AbsoluteUV_T_LocalUV : register(c15);

//  We store four light colors and positions in an
//  array of three of these structures like so:
//
//       x      y      z      w
//    +------+------+------+------+
//    |       L0.rgb       |      |
//    +------+------+------+      |
//    |       L0.pos       |  L3  |
//    +------+------+------+  rgb |
//    |       L1.rgb       |      |
//    +------+------+------+------+
//    |       L1.pos       |      |
//    +------+------+------+      |
//    |       L2.rgb       |  L3  |
//    +------+------+------+  pos |
//    |       L2.pos       |      |
//    +------+------+------+------+
//
struct PixelShaderLightInfo {
    float4 color;
    float4 pos;
};

// Leftover from VertexLitGeneric
const float4 c20 : register(c20); // PixelShaderLightInfo cLightInfo[3];
const float4 c21 : register(c21);
const float4 c22 : register(c22); // g_FlashlightAttenuationFactors
const float4 c23 : register(c23); // g_FlashlightPos
const float4 c24 : register(c24); // g_FlashlightWorldToTexture through c27
const float4 c25 : register(c25);
const float4 c26 : register(c26);
const float4 c27 : register(c27);

const float4 g_EyePos : register(c10);
#define g_fSpecExp g_EyePos.w

const float4 cFlashlightColor : register(c28);
#define flFlashlightNoLambertValue cFlashlightColor.w

const float4 HDRParams : register(c30);
#define g_TonemapScale  HDRParams.x
#define g_LightmapScale HDRParams.y
#define g_EnvmapScale   HDRParams.z
#define g_GammaScale    HDRParams.w // = TonemapScale ^ (1 / 2.2)

// Taken from common_flashlight_fxc.h
float RemapNormalizedValClamped(float val, float A, float B) {
    return saturate((val - A) / (B - A));
}

float SoftenCosineTerm(float flDot) {
    return (flDot + (flDot * flDot)) * 0.5;
}

float3 Vec3TangentToWorld(float3 iTangentVector, float3 iWorldNormal, float3 iWorldTangent, float3 iWorldBinormal) {
    float3 vWorldVector;
    vWorldVector.xyz = iTangentVector.x * iWorldTangent.xyz;
    vWorldVector.xyz += iTangentVector.y * iWorldBinormal.xyz;
    vWorldVector.xyz += iTangentVector.z * iWorldNormal.xyz;
    return vWorldVector.xyz; // Return without normalizing
}

float3 Vec3TangentToWorldNormalized(float3 iTangentVector, float3 iWorldNormal, float3 iWorldTangent, float3 iWorldBinormal) {
    return normalize(Vec3TangentToWorld( iTangentVector, iWorldNormal, iWorldTangent, iWorldBinormal));
}

// Taken from common_flashlight_fxc.h
float3 DoFlashlight(
    float3 flashlightPos, float3 worldPos, float4 flashlightSpacePosition,
    float3 worldNormal, float3 attenuationFactors, float farZ, sampler FlashlightSampler) {
    float3 vProjCoords = flashlightSpacePosition.xyz / flashlightSpacePosition.w;
    float3 flashlightColor = tex2D(FlashlightSampler, vProjCoords.xy).rgb;
    flashlightColor *= flashlightSpacePosition.www > float3(0.0, 0.0, 0.0); // Catch back projection (ps2b and up)
    flashlightColor *= cFlashlightColor.xyz; // Flashlight color

    float3 delta = flashlightPos - worldPos;
    float3 L = normalize(delta);
    float distSquared = dot(delta, delta);
    float dist = sqrt(distSquared);
    float endFalloffFactor = RemapNormalizedValClamped(dist, farZ, 0.6 * farZ);

    // Attenuation for light and to fade out shadow over distance
    float fAtten = saturate(dot(attenuationFactors, float3(1.0, 1.0 / dist, 1.0 / distSquared)));
    float flLDotWorldNormal = dot(L.xyz, worldNormal.xyz);
    float3 diffuseLighting = fAtten;
    diffuseLighting *= saturate(flLDotWorldNormal + flFlashlightNoLambertValue); // Lambertian term
    diffuseLighting *= flashlightColor;
    diffuseLighting *= endFalloffFactor;
    return diffuseLighting;
}

float3 SpecularLight(
    const float3 vWorldNormal, const float3 vLightDir,
    const float fSpecularExponent, const float3 vEyeDir) {
    float3 vReflect = reflect(-vEyeDir, vWorldNormal);     // Reflect view through normal
    float3 vSpecular = saturate(dot(vReflect, vLightDir)); // L.R (use half-angle instead?)
    vSpecular = pow(vSpecular.x, fSpecularExponent);       // Raise to specular power
    return vSpecular;
}

//-----------------------------------------------------------------------------
// Purpose: Compute scalar diffuse term
//-----------------------------------------------------------------------------
float3 DiffuseTerm(
    const bool bHalfLambert,
    const float3 worldNormal,
    const float3 lightDir) {
    float fResult;
    float NDotL = dot(worldNormal, lightDir); // Unsaturated dot (-1 to 1 range)

    if (bHalfLambert) {
        fResult = saturate(NDotL * 0.5 + 0.5); // Scale and bias to 0 to 1 range
        fResult *= fResult; // Square
    }
    else {
        fResult = saturate(NDotL); // Saturate pure Lambertian term
        fResult = SoftenCosineTerm(fResult); // For CS:GO
    }

    return float3(fResult, fResult, fResult);
}

float3 PixelShaderDoGeneralDiffuseLight(
    const float fAtten, const float3 worldPos, const float3 worldNormal,
    const float3 vPosition, const float3 vColor, const bool bHalfLambert) {
    float3 lightDir = normalize(vPosition - worldPos);
    return vColor * fAtten * DiffuseTerm(
        bHalfLambert, worldNormal, lightDir);
}

float3 PixelShaderDoLightingLinear(
    const float3 worldPos, const float3 worldNormal, const float4 lightAtten,
    const int nNumLights, PixelShaderLightInfo cLightInfo[3], const bool bHalfLambert,
    float flDirectShadow = 1.0) {
    float3 linearColor = 0.0f;
    if (nNumLights > 0) {
        // First local light will always be forced to a directional light
        // in CS:GO (see CanonicalizeMaterialLightingState() in shaderapidx8.cpp)
        // - it may be completely black.
        linearColor += PixelShaderDoGeneralDiffuseLight(
            lightAtten.x, worldPos, worldNormal,
            cLightInfo[0].pos.xyz, cLightInfo[0].color.rgb, bHalfLambert);
        linearColor *= flDirectShadow;
        if (nNumLights > 1) {
            linearColor += PixelShaderDoGeneralDiffuseLight(
                lightAtten.y, worldPos, worldNormal,
                cLightInfo[1].pos.xyz, cLightInfo[1].color.rgb, bHalfLambert);
            if (nNumLights > 2) {
                linearColor += PixelShaderDoGeneralDiffuseLight(
                    lightAtten.z, worldPos, worldNormal,
                    cLightInfo[2].pos.xyz, cLightInfo[2].color.rgb, bHalfLambert);
                if (nNumLights > 3) {
                    // Unpack the 4th light's data from tight constant packing
                    float3 vLight3Color = float3(cLightInfo[0].color.w, cLightInfo[0].pos.w, cLightInfo[1].color.w);
                    float3 vLight3Pos = float3(cLightInfo[1].pos.w, cLightInfo[2].color.w, cLightInfo[2].pos.w);
                    linearColor += PixelShaderDoGeneralDiffuseLight(
                        lightAtten.w, worldPos, worldNormal,
                        vLight3Pos, vLight3Color, bHalfLambert);
                }
            }
        }
    }

    return linearColor;
}

//      sz   sx
//    +----+----+
// sx |  0 |    |
//    +----+----+
// sy |  1 |  4 |
//    +----+----+
//    |  2 |    |
//    +----+----+
//    |  3 |  5 |
//    +----+----+
float2 CalculateMappedUV(const float3 worldPos, const float3 worldNormal) {
    float3 localPos = mul(float4(worldPos, 1.0), Model_T_World).xyz;
    float3 localNormal = mul(float4(worldNormal, 0.0), Model_T_World).xyz;
    float3 absLocalNormal = abs(localNormal);
    float maxAbsComponent = max(absLocalNormal.x, max(absLocalNormal.y, absLocalNormal.z));

    const float uvScale = c1.y;
    const float3 size = c0.xyz;
    const float3 normals[6] = {
        { 1.0, 0.0, 0.0 }, { 0.0,  1.0, 0.0 }, { 0.0, 0.0,  1.0 },
        {-1.0, 0.0, 0.0 }, { 0.0, -1.0, 0.0 }, { 0.0, 0.0, -1.0 },
    };
    const float3 tangents[6] = {
        normals[4], normals[0], normals[4],
        normals[1], normals[3], normals[1],
    };
    const float3 binormals[6] = {
        cross(normals[0], tangents[0]), cross(normals[1], tangents[1]),
        cross(normals[2], tangents[2]), cross(normals[3], tangents[3]),
        cross(normals[4], tangents[4]), cross(normals[5], tangents[5]),
    };
    const float3x3 modelRfaces[6] = {
        { tangents[0], binormals[0], normals[0] },
        { tangents[1], binormals[1], normals[1] },
        { tangents[2], binormals[2], normals[2] },
        { tangents[3], binormals[3], normals[3] },
        { tangents[4], binormals[4], normals[4] },
        { tangents[5], binormals[5], normals[5] },
    };
    const float3x3 faceRmodels[6] = {
        transpose(modelRfaces[0]),
        transpose(modelRfaces[1]),
        transpose(modelRfaces[2]),
        transpose(modelRfaces[3]),
        transpose(modelRfaces[4]),
        transpose(modelRfaces[5]),
    };
    const float3 faceOriginCoefficients[6] = {
        { 1, 1, 1 }, { 0, 1, 1 }, { 0, 1, 1 },
        { 0, 0, 1 }, { 1, 0, 1 }, { 0, 0, 0 },
    };
    const float3 uvOffsetCoefficients[6] = {
        { 2, 1, 0 }, { 1, 1, 0 }, { 2, 1, 1 },
        { 1, 0, 0 }, { 0, 0, 0 }, { 1, 0, 1 },
    };
    const float2x2 absoluteuvRlocaluv = (const float2x2)AbsoluteUV_T_LocalUV;
    const float2 absoluteUVOriginInLocalUV = AbsoluteUV_T_LocalUV[3].xy;
    const float4x4 absoluteuvRlocaluv4 = {
        { absoluteuvRlocaluv[0], 0.0, 0.0 },
        { absoluteuvRlocaluv[1], 0.0, 0.0 },
        { 0.0, 0.0, 1.0, 0.0 },
        { 0.0, 0.0, 0.0, 1.0 },
    };

    int faceIndex;
    if (maxAbsComponent == absLocalNormal.x) {
        faceIndex = localNormal.x < 0 ? 3 : 0;
    } else if (maxAbsComponent == absLocalNormal.y) {
        faceIndex = localNormal.y < 0 ? 4 : 1;
    } else {
        faceIndex = localNormal.z < 0 ? 5 : 2;
    }

    float3x3 faceRmodel = faceRmodels[faceIndex];
    float3 faceOriginInModelSystem = size * faceOriginCoefficients[faceIndex];
    float2 faceSizeInModelSystem = {
        abs(dot(size, tangents[faceIndex])),
        abs(dot(size, binormals[faceIndex])),
    };

    float3 modelOriginInFaceSystem = mul(-faceOriginInModelSystem, faceRmodel);
    float4x4 faceTmodel = {
        { faceRmodel[0],           0.0 },
        { faceRmodel[1],           0.0 },
        { faceRmodel[2],           0.0 },
        { modelOriginInFaceSystem, 1.0 },
    };
    float4x4 faceTworld = mul(Model_T_World, faceTmodel);

    float2 faceSizeInAbsoluteUV = abs(mul(faceSizeInModelSystem, absoluteuvRlocaluv));
    float4x4 worldToUV = mul(faceTworld, absoluteuvRlocaluv4);
    float3 faceUVOriginInLocalUV = size * uvOffsetCoefficients[faceIndex];
    faceUVOriginInLocalUV.x += faceUVOriginInLocalUV.y;
    faceUVOriginInLocalUV.y = faceUVOriginInLocalUV.z;
    faceUVOriginInLocalUV.z = 0.0;
    float2 faceUVOriginInAbsoluteUV
        = mul(faceUVOriginInLocalUV.xy, absoluteuvRlocaluv)
        + absoluteUVOriginInLocalUV;
    float2 uv = mul(float4(worldPos, 1.0), worldToUV).xy + faceUVOriginInAbsoluteUV;
    return uv.yx * uvScale;
}

struct PS_INPUT {
    float2 pos                     : VPOS;
    float3 diffuse                 : COLOR0;
    float4 uv_depth                : TEXCOORD0;
    float4 vWorldPos_BinormalX     : TEXCOORD1;
    float4 vWorldNormal_BinormalY  : TEXCOORD2;
    float4 vWorldTangent_BinormalZ : TEXCOORD3;
    float4 vLightAtten             : TEXCOORD4;
};

struct PS_OUTPUT {
    float4 color : COLOR0;
    float  depth : DEPTH0;
};

float4 main(const PS_INPUT i) : COLOR0 {
    const float    depthRatio = 65534.0 / 65535.0;
    const float4   g_FlashlightAttenuationFactors = c22;
    const float3   g_FlashlightPos                = c23.xyz;
    const float4x4 g_FlashlightWorldToTexture = {
        c24.x, c25.x, c26.x, c27.x,
        c24.y, c25.y, c26.y, c27.y,
        c24.z, c25.z, c26.z, c27.z,
        c24.w, c25.w, c26.w, c27.w,
    };
    const PixelShaderLightInfo cLightInfo[3] = {
        { c20, c21 },
        { c22, c23 },
        { c24, c25 },
    };

    float3 vertexPos      = i.vWorldPos_BinormalX.xyz;
    float3 vertexNormal   = i.vWorldNormal_BinormalY.xyz;
    float3 vertexTangent  = i.vWorldTangent_BinormalZ.xyz;
    float3 vertexBinormal = float3(
        i.vWorldPos_BinormalX.w,
        i.vWorldNormal_BinormalY.w,
        i.vWorldTangent_BinormalZ.w);
    float2 uv     = CalculateMappedUV(vertexPos, vertexNormal);
    float4 albedo = tex2D(Albedo, uv);
    float4 normal = tex2D(Normal, uv);
    float  alpha  = tex2D(OriginalBaseTexture, i.uv_depth.xy).a;
    if (normal.x == 0 && normal.y == 0 && normal.z == 0) {
        normal = float4(0.5, 0.5, 1.0, 1.0);
    }
    float3 tangentSpaceNormal = normal.xyz * 2.0 - 1.0;
    float3 worldNormal = Vec3TangentToWorldNormalized(
        tangentSpaceNormal, vertexNormal, vertexTangent, vertexBinormal);
    float3 diffuseLighting = PixelShaderDoLightingLinear(
        vertexPos, worldNormal, i.vLightAtten, 4, cLightInfo, true);
    diffuseLighting += i.diffuse;
    return albedo * float4(diffuseLighting, alpha) * g_TonemapScale;
}
