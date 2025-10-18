
sampler Albedo : register(s0); // $basetexture
sampler Normal : register(s1); // $texture1

// Fixed as there is no way to provide current projected texture to draw
sampler FlashlightSampler : register(s3);

// xyz -> OBB size
// w = 1, 2, 3 -> UV expansion pattern
const float4 c0 : register(c0);

// x = 0 -> do nothing special; just rendering
// x = 1 -> additive flashlight
const float4 c1 : register(c1);

const float4x4 ModelMatrix : register(c11);
const float4x4 UVMatrix : register(c15);

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

//      sx   sy   sx   sy
//    +----+----+----+----+
// sz |  0 |  1 |  2 |  3 |
//    +----+----+----+----+
// sx |    |  4 |    |  5 |
//    +----+----+----+----+
float2 CalculateMappedUV(const float3 worldPos, const float3 worldNormal) {
    float3 localPos = mul(float4(worldPos, 1.0), ModelMatrix).xyz;
    float3 localNormal = mul(float4(worldNormal, 0.0), ModelMatrix).xyz;
    float3 absLocalNormal = abs(localNormal);
    float maxAbsComponent = max(absLocalNormal.x, max(absLocalNormal.y, absLocalNormal.z));

    float2 uv;
    float3 size;
    int faceIndex;
    int patternIndex = c0.w;
    if (patternIndex == 1) {
        size = c0.xyz;
        if (maxAbsComponent == absLocalNormal.x) {
            uv = localPos.yz;
            faceIndex = localNormal.x < 0 ? 3 : 1;
        } else if (maxAbsComponent == absLocalNormal.y) {
            uv = localPos.xz;
            faceIndex = localNormal.y < 0 ? 0 : 2;
        } else {
            uv = localPos.yx;
            faceIndex = localNormal.z < 0 ? 4 : 5;
        }
    } else if (patternIndex == 2) {
        size = c0.yxz;
        if (maxAbsComponent == absLocalNormal.x) {
            uv = localPos.yz;
            faceIndex = localNormal.x < 0 ? 0 : 2;
        } else if (maxAbsComponent == absLocalNormal.y) {
            uv = localPos.xz;
            faceIndex = localNormal.y < 0 ? 3 : 1;
        } else {
            uv = localPos.xy;
            faceIndex = localNormal.z < 0 ? 4 : 5;
        }
    } else {
        size = c0.zxy;
        if (maxAbsComponent == absLocalNormal.x) {
            uv = localPos.zy;
            faceIndex = localNormal.x < 0 ? 0 : 2;
        } else if (maxAbsComponent == absLocalNormal.y) {
            uv = localPos.xz;
            faceIndex = localNormal.y < 0 ? 4 : 5;
        } else {
            uv = localPos.xy;
            faceIndex = localNormal.z < 0 ? 3 : 1;
        }
    }

    float2 offset[6] = {
        float2(       0.0,          0.0   ),
        float2(    size.x,          0.0   ),
        float2(    size.x + size.y, 0.0   ),
        float2(2 * size.x + size.y, 0.0   ),
        float2(    size.x,          size.z),
        float2(2 * size.x + size.y, size.z),
    };

    if (faceIndex == 2 || faceIndex == 3 || faceIndex == 5) {
        uv.x = size.x - uv.x;
    }
    float4 uv4 = float4(uv.xy + offset[faceIndex], 0.0, 1.0);
    float4 uvTransformed = mul(uv4, UVMatrix);
    return uvTransformed.yx;
}

struct PS_INPUT {
    float2 pos                     : VPOS;
    float3 diffuse                 : COLOR0;
    float4 vWorldPos_BinormalX     : TEXCOORD0;
    float4 vWorldNormal_BinormalY  : TEXCOORD1;
    float4 vWorldTangent_BinormalZ : TEXCOORD2;
    float4 vLightAtten             : TEXCOORD3;
};

float4 main(const PS_INPUT i) : COLOR0 {
    const float4   g_FlashlightAttenuationFactors = c22;
    const float3   g_FlashlightPos                = c23.xyz;
    const float4x4 g_FlashlightWorldToTexture = {
        c24.x, c25.x, c26.x, c27.x,
        c24.y, c25.y, c26.y, c27.y,
        c24.z, c25.z, c26.z, c27.z,
        c24.w, c25.w, c26.w, c27.w,
    };
    PixelShaderLightInfo cLightInfo[3];
    cLightInfo[0].color = c20;
    cLightInfo[0].pos   = c21;
    cLightInfo[1].color = c22;
    cLightInfo[1].pos   = c23;
    cLightInfo[2].color = c24;
    cLightInfo[2].pos   = c25;

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
    if (normal.x == 0 && normal.y == 0 && normal.z == 0) {
        normal = float4(0.5, 0.5, 1.0, 1.0);
    }
    float3 tangentSpaceNormal = normal.xyz * 2.0 - 1.0;
    float3 worldNormal = Vec3TangentToWorldNormalized(
        tangentSpaceNormal, vertexNormal, vertexTangent, vertexBinormal);
    if (c1.x > 0.5) {
        float3 vEyeDir = normalize(g_EyePos.xyz - vertexPos);
        float3 vLightDir = normalize(g_FlashlightPos.xyz - vertexPos);
        float4 flashlightSpacePos = mul(float4(vertexPos, 1.0), g_FlashlightWorldToTexture);
        float3 flashlightUV = flashlightSpacePos.xyz / flashlightSpacePos.w;
        float3 flashlightColor = DoFlashlight(
            g_FlashlightPos.xyz, vertexPos, flashlightSpacePos,
            worldNormal, g_FlashlightAttenuationFactors.xyz,
            g_FlashlightAttenuationFactors.w, FlashlightSampler);
        float3 flashlightSpecular = flashlightColor * SpecularLight(worldNormal, vLightDir, g_fSpecExp, vEyeDir);
        flashlightColor += flashlightSpecular;
        flashlightColor
            *= step(0.0, flashlightUV.x)
            *  step(0.0, flashlightUV.y)
            *  step(flashlightUV.x, 1.0)
            *  step(flashlightUV.y, 1.0);
        return albedo * float4(flashlightColor, 1.0);
    }
    else {
        float3 diffuseLighting = PixelShaderDoLightingLinear(
            vertexPos, worldNormal, i.vLightAtten, 4, cLightInfo, true);
        diffuseLighting += i.diffuse;
        return albedo * float4(diffuseLighting, 1.0);
    }
}
