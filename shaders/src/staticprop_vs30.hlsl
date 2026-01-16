// Painted Static Props Vertex Shader for SplashSWEPs
// Based on VertexLitGeneric vertex shader

struct VS_INPUT {
    float4 pos         : POSITION0;
    float2 uv          : TEXCOORD0;
    float4 normal      : NORMAL0;
    float4 color       : COLOR0;
    float4 boneWeights : BLENDWEIGHT;
    float4 boneIndices : BLENDINDICES;
    float4 tangentS    : TANGENT0;
    float4 tangentT    : BINORMAL0;
};

struct VS_OUTPUT {
    float4 pos                     : POSITION;
    float3 diffuse                 : COLOR0;
    float4 uv_depth                : TEXCOORD0;
    float4 vWorldPos_BinormalX     : TEXCOORD1;
    float4 vWorldNormal_BinormalY  : TEXCOORD2;
    float4 vWorldTangent_BinormalZ : TEXCOORD3;
    float4 vLightAtten             : TEXCOORD4;
};

struct LightInfo {
    float4 color; // {xyz} is color w is light type code (see comment below)
    float4 dir;   // {xyz} is dir   w is light type code
    float4 pos;
    float4 spotParams;
    float4 atten;
};

const float3 cAmbientCubeX[2] : register(c21);
const float3 cAmbientCubeY[2] : register(c23);
const float3 cAmbientCubeZ[2] : register(c25);
const float4x4 cModelViewProj : register(c4);
const float4x4 cViewProj      : register(c8);
const float4x3 cModel[53]     : register(c58);
const int g_nLightCountRegister : register(i0);
#define g_nLightCount g_nLightCountRegister.x
LightInfo cLightInfo[4] : register(c27);

#define COMPRESSED_VERTS
#include "decompress_vertex.hlsl"

float3 AmbientLight(const float3 worldNormal) {
    float3 nSquared = worldNormal * worldNormal;
    int3 isNegative = (worldNormal < 0.0);
    return nSquared.x * cAmbientCubeX[isNegative.x] +
           nSquared.y * cAmbientCubeY[isNegative.y] +
           nSquared.z * cAmbientCubeZ[isNegative.z];
}

float SoftenCosineTerm(float flDot) {
    return (flDot + (flDot * flDot)) * 0.5;
}

float CosineTerm(const float3 worldPos, const float3 worldNormal, int lightNum, bool bHalfLambert) {
    // Calculate light direction assuming this is a point or spot
    float3 lightDir = normalize(cLightInfo[lightNum].pos.xyz - worldPos);

    // Select the above direction or the one in the structure, based upon light type
    lightDir = lerp(lightDir, -cLightInfo[lightNum].dir.xyz, cLightInfo[lightNum].color.w);

    // compute N dot L
    float NDotL = dot(worldNormal, lightDir);

    if (bHalfLambert) {
        NDotL = NDotL * 0.5 + 0.5;
        NDotL = NDotL * NDotL;
    }
    else {
        NDotL = max(0.0, NDotL);
        NDotL = SoftenCosineTerm(NDotL);
    }
    return NDotL;
}

float VertexAtten(const float3 worldPos, int lightNum) {
    // Get light direction
    float3 lightDir = cLightInfo[lightNum].pos.xyz - worldPos;

    // Get light distance squared.
    float lightDistSquared = dot(lightDir, lightDir);

    // Get 1 / lightDistance
    float ooLightDist = rsqrt(lightDistSquared);

    // Normalize light direction
    lightDir *= ooLightDist;

    float3 vDist = dst(lightDistSquared, ooLightDist).xyz;
    float flDistanceAtten = 1.0 / dot(cLightInfo[lightNum].atten.xyz, vDist);

    // Spot attenuation
    float flCosTheta = dot(cLightInfo[lightNum].dir.xyz, -lightDir);
    float flSpotAtten = (flCosTheta - cLightInfo[lightNum].spotParams.z) * cLightInfo[lightNum].spotParams.w;
    flSpotAtten = max(0.0001f, flSpotAtten);
    flSpotAtten = pow(flSpotAtten, cLightInfo[lightNum].spotParams.x);
    flSpotAtten = saturate(flSpotAtten);

    // Select between point and spot
    float flAtten = lerp(flDistanceAtten, flDistanceAtten * flSpotAtten, cLightInfo[lightNum].dir.w);

    // Select between above and directional (no attenuation)
    return lerp(flAtten, 1.0, cLightInfo[lightNum].color.w);
}

float3 DoLightInternal(const float3 worldPos, const float3 worldNormal, int lightNum, bool bHalfLambert) {
    return cLightInfo[lightNum].color.xyz *
        CosineTerm(worldPos, worldNormal, lightNum, bHalfLambert) *
        VertexAtten(worldPos, lightNum);
}

float3 DoLighting(const float3 worldPos, const float3 worldNormal, bool bHalfLambert) {
    float3 linearColor = float3(0.0, 0.0, 0.0);
    for (int i = 0; i < g_nLightCount; i++) {
        linearColor += DoLightInternal(worldPos, worldNormal, i, bHalfLambert);
    }

    linearColor += AmbientLight(worldNormal); // ambient light is already remapped
    return linearColor;
}

VS_OUTPUT main(const VS_INPUT v) {
    VS_OUTPUT output;

    // Choose an arbitrary vector that is not parallel to the normal
    float3 up = abs(v.normal.z) < 0.999 ? float3(0.0, 0.0, 1.0) : float3(0.0, 1.0, 0.0);
    float3 worldPos = v.pos.xyz;
    float3 normal = v.normal.xyz;
    float4 tangent = { normalize(cross(up, normal)), 1.0 };
    float3 binormal = normalize(cross(normal, tangent.xyz));
    float3 worldNormal = normal;
    float3 worldTangentS = tangent.xyz;
    float3 worldTangentT = binormal;

#ifdef COMPRESSED_VERTS
    DecompressVertex_NormalTangent(v.normal, v.tangentS, normal, tangent);
    SkinPositionNormalAndTangentSpace(
        true, v.pos, normal, tangent,
        v.boneWeights, v.boneIndices,
        worldPos, worldNormal, worldTangentS, worldTangentT);
    output.pos = mul(float4(worldPos, 1.0), cViewProj);
#else
    output.pos = mul(float4(worldPos, 1.0), cModelViewProj);
#endif

    output.uv_depth.xy = v.uv;
    output.uv_depth.z = output.pos.z;
    output.uv_depth.w = output.pos.w;
    output.diffuse = DoLighting(worldPos, worldNormal, true);
    output.vWorldPos_BinormalX.xyz     = worldPos;
    output.vWorldNormal_BinormalY.xyz  = worldNormal;
    output.vWorldTangent_BinormalZ.xyz = worldTangentS;
    output.vWorldPos_BinormalX.w       = worldTangentT.x;
    output.vWorldNormal_BinormalY.w    = worldTangentT.y;
    output.vWorldTangent_BinormalZ.w   = worldTangentT.z;
    output.vLightAtten.x = VertexAtten(worldPos, 0);
    output.vLightAtten.y = VertexAtten(worldPos, 1);
    output.vLightAtten.z = VertexAtten(worldPos, 2);
    output.vLightAtten.w = VertexAtten(worldPos, 3);
    return output;
}
