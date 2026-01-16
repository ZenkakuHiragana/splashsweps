// Ink Mesh Vertex Shader for SplashSWEPs
// Based on LightmappedGeneric vertex shader

struct VS_INPUT {
    float3 pos              : POSITION;
    float3 normal           : NORMAL0;
    float2 baseTexCoord     : TEXCOORD0; // xy: Ink UV
    float2 lightmapTexCoord : TEXCOORD1; // Lightmap UV
    float2 lightmapOffset   : TEXCOORD2; // Bumpmapped lightmap offset
    float2 worldBumpCoord   : TEXCOORD3; // World bumpmap UV
};

struct VS_OUTPUT {
    float4   pos                   : POSITION;
    float4   inkUV_worldBumpUV     : TEXCOORD0; // xy: ink albedo UV, zw: world bumpmap UV
    float4   lightmapUV1And2       : TEXCOORD1; // xy: lightmap UV, zw: bumpmapped lightmap UV (1)
    float4   lightmapUV3           : TEXCOORD2; // xy: bumpmapped lightmap UV (2)
    float4   worldPos_projPosZ     : TEXCOORD3;
    float3x3 tangentSpaceTranspose : TEXCOORD4; // TEXCOORD4, 5, 6
};

const float4x4 cModelViewProj : register(c4);
const float4x4 cViewProj      : register(c8);
const float4x3 cModel[1]      : register(c58);

VS_OUTPUT main(const VS_INPUT v) {
    VS_OUTPUT output = (VS_OUTPUT)0;

    // Transform position
    output.pos = mul(float4(v.pos, 1.0), cModelViewProj);
    output.worldPos_projPosZ = float4(v.pos, output.pos.z);

    // Choose an arbitrary vector that is not parallel to the normal
    float3 up = abs(v.normal.z) < 0.999 ? float3(0.0, 0.0, 1.0) : float3(0.0, 1.0, 0.0);
    float3 tangent = normalize(cross(up, v.normal));

    // Build tangent space transpose matrix for normal mapping
    output.tangentSpaceTranspose[0] = tangent;
    output.tangentSpaceTranspose[1] = normalize(cross(v.normal, tangent));
    output.tangentSpaceTranspose[2] = v.normal;

    // Pack texture coordinates
    output.inkUV_worldBumpUV.xy = v.baseTexCoord;
    output.inkUV_worldBumpUV.zw = v.worldBumpCoord;

    if (v.lightmapOffset.x > 0) {
        float2 lightmapTexCoord1  = v.lightmapTexCoord + v.lightmapOffset;
        float2 lightmapTexCoord2  = lightmapTexCoord1  + v.lightmapOffset;
        float2 lightmapTexCoord3  = lightmapTexCoord2  + v.lightmapOffset;
        output.lightmapUV1And2.xy = lightmapTexCoord1;
        output.lightmapUV1And2.zw = lightmapTexCoord2;
        output.lightmapUV3.xy     = lightmapTexCoord3;
    }
    else {
        output.lightmapUV1And2.xy = v.lightmapTexCoord;
    }

    return output;
}
