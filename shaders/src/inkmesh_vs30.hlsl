// Ink Mesh Vertex Shader for SplashSWEPs
// Based on LightmappedGeneric vertex shader

struct VS_INPUT {
    float3 vPos              : POSITION;
    float4 vNormal           : NORMAL;
    float2 vBaseTexCoord     : TEXCOORD0; // xy: Ink UV
    float2 vLightmapTexCoord : TEXCOORD1; // Lightmap UV
    float2 vLightmapOffset   : TEXCOORD2; // Bumpmapped lightmap offset
    float2 vWorldBumpCoord   : TEXCOORD3; // World bumpmap UV
    float3 vTangentS         : TANGENT;
    float3 vTangentT         : BINORMAL;
    float4 vColor            : COLOR0;
};

struct VS_OUTPUT {
    float4   projPos               : POSITION;
    float4   inkUV_worldBumpUV     : TEXCOORD0; // xy: ink albedo UV, zw: world bumpmap UV
    float4   lightmapUV1And2       : TEXCOORD1; // xy: lightmap UV, zw: bumpmapped lightmap UV (1)
    float4   lightmapUV3           : TEXCOORD2; // xy: bumpmapped lightmap UV (2)
    float4   worldPos_projPosZ     : TEXCOORD3;
    float3x3 tangentSpaceTranspose : TEXCOORD4; // TEXCOORD4, 5, 6
    float4   vertexColor           : COLOR0;
};

const float4x4 cModelViewProj : register(c4);
const float4x4 cModel[1]      : register(c58);

// Decompress vertex normal
void DecompressVertex_Normal(float4 inputNormal, out float3 outputNormal) {
    outputNormal = inputNormal.xyz * 2.0 - 1.0;
}

VS_OUTPUT main(const VS_INPUT v) {
    VS_OUTPUT o = (VS_OUTPUT)0;

    // Decompress normal
    float3 vObjNormal;
    DecompressVertex_Normal(v.vNormal, vObjNormal);

    // Transform position
    float3 worldPos = mul(float4(v.vPos, 1.0), cModel[0]).xyz;
    o.projPos = mul(float4(v.vPos, 1.0), cModelViewProj);
    o.worldPos_projPosZ = float4(worldPos, o.projPos.z);

    // Transform normal and tangent to world space
    float3 worldNormal   = mul(vObjNormal,  (float3x3)cModel[0]);
    float3 worldTangentS = mul(v.vTangentS, (float3x3)cModel[0]);
    float3 worldTangentT = mul(v.vTangentT, (float3x3)cModel[0]);

    // Build tangent space transpose matrix for normal mapping
    o.tangentSpaceTranspose[0] = worldTangentS;
    o.tangentSpaceTranspose[1] = worldTangentT;
    o.tangentSpaceTranspose[2] = worldNormal;

    // Pack texture coordinates
    o.inkUV_worldBumpUV.xy = v.vBaseTexCoord;
    o.inkUV_worldBumpUV.zw = v.vWorldBumpCoord;

    if (v.vLightmapOffset.x > 0) {
        o.lightmapUV1And2.xy     = v.vLightmapTexCoord  + v.vLightmapOffset;
        float2 lightmapTexCoord2 = o.lightmapUV1And2.xy + v.vLightmapOffset;
        float2 lightmapTexCoord3 = lightmapTexCoord2    + v.vLightmapOffset;
        o.lightmapUV1And2.wz = lightmapTexCoord2.xy; // reversed component order
        o.lightmapUV3.xy = lightmapTexCoord3;
        o.lightmapUV3.z = 1.0;
    }
    else {
        o.lightmapUV1And2.xy = v.vLightmapTexCoord;
    }

    // Vertex color
    o.vertexColor = v.vColor;

    return o;
}
