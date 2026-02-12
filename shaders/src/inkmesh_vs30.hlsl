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
    float4   worldNormalTangentY   : TEXCOORD6; // xyz: world normal, w: world tangent Y
    float4   inkTangentXYZWorldZ   : TEXCOORD7; // xyz: ink tangent, w: world tangent Z
    float4   inkBinormalMeshLift   : TEXCOORD8; // xyz: ink binormal, w: mesh lift amount
    float4   unused                : TEXCOORD9;
};

const float4x4 cModelViewProj : register(c4);
const float4 cEyePosWaterZ : register(c2);
static const float HEIGHT_TO_HAMMER_UNITS = 32.0;
VS_OUTPUT main(const VS_INPUT v) {
    float liftAmount = v.color.a * HEIGHT_TO_HAMMER_UNITS;
    float4 projPos = mul(float4(v.pos + v.normal * liftAmount, 1.0), cModelViewProj);
    VS_OUTPUT w;
    w.pos                       = projPos;
    w.surfaceClipRange          = v.surfaceClipRange.yxwz * 0.5;
    w.lightmapUV1And2.xy        = v.lightmapUVOffset.xy + v.lightmapUVOffset.zw;
    w.lightmapUV1And2.zw        = v.lightmapUVOffset.xy + v.lightmapUVOffset.zw * 2.0;
    w.lightmapUV3_projXY.xy     = v.lightmapUVOffset.xy + v.lightmapUVOffset.zw * 3.0;
    w.lightmapUV3_projXY.zw     = projPos.xy;
    w.inkUV_worldBumpUV.xy      = v.baseBumpUV.xy * 0.5;
    w.inkUV_worldBumpUV.zw      = v.baseBumpUV.zw;
    w.worldPos_projPosZ.xyz     = v.pos;
    w.worldPos_projPosZ.w       = projPos.z;
    w.worldBinormalTangentX.xyz = v.binormal;
    w.worldNormalTangentY.xyz   = v.normal;
    w.inkTangentXYZWorldZ.xyz   = v.inkTangent;
    w.worldBinormalTangentX.w   = v.tangent.x;
    w.worldNormalTangentY.w     = v.tangent.y;
    w.inkTangentXYZWorldZ.w     = v.tangent.z;
    w.inkBinormalMeshLift.xyz   = v.inkBinormal;
    w.inkBinormalMeshLift.w     = liftAmount;
    w.unused                    = 0.0;
    return w;
}
