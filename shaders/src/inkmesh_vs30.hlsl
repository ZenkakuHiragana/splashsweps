// Ink Mesh Vertex Shader for SplashSWEPs
// Based on LightmappedGeneric vertex shader

struct VS_INPUT {
    float3 pos              : POSITION;
    float3 normal           : NORMAL0;
    float4 color            : COLOR0;
    float4 baseBumpUV       : TEXCOORD0; // xy: Ink UV, zw: World bumpmap UV
    float4 lightmapUVOffset : TEXCOORD1; // xy: Lightmap UV, zw: Bumpmapped lightmap offset
    float3 inkTangent       : TEXCOORD2;
    float3 inkBinormal      : TEXCOORD3;
    float3 tangent          : TEXCOORD4;
    float3 binormal         : TEXCOORD5;
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
    float4   projPosW_isCeiling    : TEXCOORD9;
};

// [0.0, 1.0] --> [-1.0, +1.0]
#define TO_SIGNED(x) ((x) * 2.0 - 1.0)

// Safe rcp that avoids division by zero
#define SAFERCP(x) (TO_SIGNED(step(0.0, x)) * rcp(max(abs(x), 1.0e-21)))

const float4x4 cModelViewProj : register(c4);
const float4 cEyePosWaterZ : register(c2);
static const float HEIGHT_TO_HAMMER_UNITS = 32.0;
VS_OUTPUT main(const VS_INPUT v) {
    bool isCeiling = v.color.a == 0.0;
    float liftAmount = max(round(v.color.a * 3.0) - 2.0, -1.0);
    float cameraHeight = dot(v.normal, cEyePosWaterZ.xyz - v.pos);
    if (isCeiling) {
        if (cameraHeight < 0.0) {
            VS_OUTPUT w = (VS_OUTPUT)0.0;
            w.pos = float4(0.0, 0.0, -1.0, 1.0);
            return w;
        }
        else {
            liftAmount = 1.0;
        }
    }

    float3 pos = v.pos + v.normal * liftAmount * HEIGHT_TO_HAMMER_UNITS;
    float3 viewVec = cEyePosWaterZ.xyz - pos;
    float viewVecDot = dot(viewVec, v.normal);
    // Extend the side mesh so that it draws ink raised by its height map
    if (!isCeiling && liftAmount == 1.0 && viewVecDot < 0.0) {
        float2 surfaceSizeInUV = {
            v.surfaceClipRange.z - v.surfaceClipRange.x,
            v.surfaceClipRange.w - v.surfaceClipRange.y,
        };
        float surfaceMaxSize = sqrt(
            surfaceSizeInUV.x * surfaceSizeInUV.x *
            SAFERCP(dot(v.inkTangent, v.inkTangent)) +
            surfaceSizeInUV.y * surfaceSizeInUV.y *
            SAFERCP(dot(v.inkBinormal, v.inkBinormal)));
        float3 viewVecFlattened = viewVec - v.normal * viewVecDot;
        float viewVecLength2D = length(viewVecFlattened);
        float viewAngle = viewVecLength2D / max(-viewVecDot, 1e-3);
        float extraHeight = surfaceMaxSize * viewAngle;
        liftAmount += extraHeight / HEIGHT_TO_HAMMER_UNITS;
        liftAmount = clamp(liftAmount, 1.0, 16.0); // Safety cap
        pos = v.pos + v.normal * liftAmount * HEIGHT_TO_HAMMER_UNITS;
    }

    float4 projPos = mul(float4(pos, 1.0), cModelViewProj);
    VS_OUTPUT w;
    w.pos                       = projPos;
    w.surfaceClipRange          = v.surfaceClipRange.yxwz * 0.5;
    w.lightmapUV1And2.xy        = v.lightmapUVOffset.xy + v.lightmapUVOffset.zw;
    w.lightmapUV1And2.zw        = v.lightmapUVOffset.xy + v.lightmapUVOffset.zw * 2.0;
    w.lightmapUV3_projXY.xy     = v.lightmapUVOffset.xy + v.lightmapUVOffset.zw * 3.0;
    w.lightmapUV3_projXY.zw     = projPos.xy;
    w.inkUV_worldBumpUV.xy      = v.baseBumpUV.xy * 0.5;
    w.inkUV_worldBumpUV.zw      = v.baseBumpUV.zw;
    w.worldPos_projPosZ.xyz     = pos;
    w.worldPos_projPosZ.w       = projPos.z;
    w.worldBinormalTangentX.xyz = v.binormal;
    w.worldNormalTangentY.xyz   = v.normal;
    w.inkTangentXYZWorldZ.xyz   = v.inkBinormal * 0.5; // Intentionally swapped
    w.worldBinormalTangentX.w   = v.tangent.x;
    w.worldNormalTangentY.w     = v.tangent.y;
    w.inkTangentXYZWorldZ.w     = v.tangent.z;
    w.inkBinormalMeshLift.xyz   = v.inkTangent * 0.5; // Intentionally swapped
    w.inkBinormalMeshLift.w     = liftAmount;
    w.projPosW_isCeiling.x      = projPos.w;
    w.projPosW_isCeiling.y      = isCeiling ? 1.0 : 0.0;
    w.projPosW_isCeiling.zw     = 0.0;
    return w;
}
