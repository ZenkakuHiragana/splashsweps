// Ink Mesh Vertex Shader for SplashSWEPs, static prop part
// Based on VertexLitGeneric vertex shader
// The previous VertexLitGeneric draw of the same prop leaves the ambient cube and the lights in the constants.
#include "inkmesh_common.hlsl"

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

// See staticprop_ps30.hlsl for PS_INPUT
struct VS_OUTPUT {
    float4 pos               : POSITION;
    float4 worldPos_ClipW    : TEXCOORD0;
    float4 worldNormal_ClipZ : TEXCOORD1;
    float2 modelUV           : TEXCOORD2;
    float4 lightAtten        : TEXCOORD3;
    float3 ambientXPos       : TEXCOORD4;
    float3 ambientXNeg       : TEXCOORD5;
    float3 ambientYPos       : TEXCOORD6;
    float3 ambientYNeg       : TEXCOORD7;
    float3 ambientZPos       : TEXCOORD8;
    float3 ambientZNeg       : TEXCOORD9;
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
LightInfo cLightInfo[4] : register(c27);

#define COMPRESSED_VERTS
#include "decompress_vertex.hlsl"

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

VS_OUTPUT main(const VS_INPUT v) {
    VS_OUTPUT output;

    // Choose an arbitrary vector that is not parallel to the normal
    float3 up = abs(v.normal.z) < 0.999 ? float3(0.0, 0.0, 1.0) : float3(0.0, 1.0, 0.0);
    float3 worldPos = v.pos.xyz;
    float3 normal = v.normal.xyz;
    float4 tangent = { normalize(cross(up, normal)), 1.0 };
    float3 worldNormal = normal;
    float3 worldTangentS = tangent.xyz;
    float3 worldTangentT = normalize(cross(normal, tangent.xyz));

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

    output.pos.z            -= DEPTH_BIAS * output.pos.w;
    output.worldPos_ClipW    = float4(worldPos, output.pos.w);
    output.worldNormal_ClipZ = float4(worldNormal, output.pos.z);
    output.modelUV           = v.uv;
    output.lightAtten.x      = VertexAtten(worldPos, 0);
    output.lightAtten.y      = VertexAtten(worldPos, 1);
    output.lightAtten.z      = VertexAtten(worldPos, 2);
    output.lightAtten.w      = VertexAtten(worldPos, 3);
    output.ambientXPos       = cAmbientCubeX[0];
    output.ambientXNeg       = cAmbientCubeX[1];
    output.ambientYPos       = cAmbientCubeY[0];
    output.ambientYNeg       = cAmbientCubeY[1];
    output.ambientZPos       = cAmbientCubeZ[0];
    output.ambientZNeg       = cAmbientCubeZ[1];
    return output;
}
