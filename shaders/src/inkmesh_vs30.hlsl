// Ink Mesh Vertex Shader for SplashSWEPs
#include "inkmesh_core.hlsl"

struct VS_INPUT {
    float3 pos              : POSITION;
    float3 normal           : NORMAL0;
    float4 color            : COLOR0;    // xy: Unused, z: Role, w: Lift amount
    float4 baseBumpUV       : TEXCOORD0; // xy: Ink UV, zw: World bumpmap UV
    float4 lightmapUVOffset : TEXCOORD1; // xy: Lightmap UV, zw: Bumpmapped lightmap offset
    float4 inkTangent       : TEXCOORD2;
    float4 inkBinormal      : TEXCOORD3;
    float4 tangent          : TEXCOORD4;
    float4 binormal         : TEXCOORD5;
    float4 surfaceClipRange : TEXCOORD6;
};

struct VS_OUTPUT {
    float4   pos                   : POSITION;
    float4   surfaceClipRange      : TEXCOORD0; // xy: ink map min UV, zw: ink map max UV
    float4   lightmapUV1And2       : TEXCOORD1; // xy: lightmap UV, zw: bumpmapped lightmap UV (1)
    float4   lightmapUV3_projXY    : TEXCOORD2; // xy: bumpmapped lightmap UV (2), zw: projected position XY
    float4   inkUV_worldBumpUV     : TEXCOORD3; // xy: ink albedo UV, zw: world bumpmap UV
    float4   worldPos_projPosZ     : TEXCOORD4; // xyz: world position, w: projected position Z
    float4   worldBinormalTangentX : TEXCOORD5; // xyz: world binormal, w: world tangent X
    float4   worldNormalTangentY   : TEXCOORD6; // xyz: world normal,   w: world tangent Y
    float4   inkTangentXYZWorldZ   : TEXCOORD7; // xyz: ink tangent,    w: world tangent Z
    float4   inkBinormalMeshLift   : TEXCOORD8; // xyz: ink binormal,   w: mesh lift amount
    float4   projPosW_meshRole     : TEXCOORD9; // x: projPosW, y: tri role / MESH_ROLE_MAX
};

const float4x4 cModelViewProj : register(c4);
const float4 cEyePosWaterZ : register(c2);
VS_OUTPUT main(const VS_INPUT v) {
    int role = (int)round(v.color.b * MESH_ROLE_MAX);
    float cameraHeight = dot(v.normal, cEyePosWaterZ.xyz - v.pos);
    bool isCeiling = role == MESH_ROLE_CEIL;
    float liftAmount = TO_SIGNED(v.color.a);
    if (isCeiling && cameraHeight > HEIGHT_TO_HAMMER_UNITS) {
        VS_OUTPUT w = (VS_OUTPUT)0.0;
        w.pos = float4(0.0, 0.0, -1.0, 1.0);
        return w;
    }

    float3 pos = v.pos + v.normal * liftAmount * HEIGHT_TO_HAMMER_UNITS;
    float3 viewVec = cEyePosWaterZ.xyz - pos;
    float viewVecDist = length(viewVec);
    if (!isCeiling) {
        float fade = 1.0 - smoothstep(LOD_DISTANCE * 0.5, LOD_DISTANCE, viewVecDist);
        fade -= cameraHeight / viewVecDist;
        fade *= step(0.125, fade);
        liftAmount *= fade;
    }

    pos = v.pos + v.normal * liftAmount * HEIGHT_TO_HAMMER_UNITS;
    float4 projPos = mul(float4(pos, 1.0), cModelViewProj);
    VS_OUTPUT w;
    w.pos                       = projPos;
    w.surfaceClipRange          = v.surfaceClipRange.yxwz * 0.5;
    w.lightmapUV1And2.xy        = v.lightmapUVOffset.xy + v.lightmapUVOffset.zw;
    w.lightmapUV1And2.zw        = v.lightmapUVOffset.xy + v.lightmapUVOffset.zw * 2.0;
    w.lightmapUV3_projXY.xy     = v.lightmapUVOffset.xy + v.lightmapUVOffset.zw * 3.0;
    w.lightmapUV3_projXY.zw     = float2(v.tangent.w, v.binormal.w);
    w.inkUV_worldBumpUV.xy      = v.baseBumpUV.xy * 0.5;
    w.inkUV_worldBumpUV.zw      = v.baseBumpUV.zw;
    w.worldPos_projPosZ.xyz     = pos;
    w.worldPos_projPosZ.w       = projPos.z;
    w.worldBinormalTangentX.xyz = v.binormal.xyz;
    w.worldNormalTangentY.xyz   = v.normal;
    w.inkTangentXYZWorldZ.xyz   = v.inkBinormal.xyz * 0.5; // Intentionally swapped
    w.worldBinormalTangentX.w   = v.tangent.x;
    w.worldNormalTangentY.w     = v.tangent.y;
    w.inkTangentXYZWorldZ.w     = v.tangent.z;
    w.inkBinormalMeshLift.xyz   = v.inkTangent.xyz * 0.5; // Intentionally swapped
    w.inkBinormalMeshLift.w     = liftAmount;
    w.projPosW_meshRole.x       = projPos.w;
    w.projPosW_meshRole.y       = (float)role / MESH_ROLE_MAX;
    w.projPosW_meshRole.zw      = float2(v.inkTangent.w, v.inkBinormal.w);
    return w;
}
