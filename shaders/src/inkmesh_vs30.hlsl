// Ink Mesh Vertex Shader for SplashSWEPs

// world position          xyz
// world geometry normal   xyz
//
// world geometry tangent  xyz, world geometry u   w
// world geometry binormal xyz, world geometry v   w
// ink mesh tangent        xyz, ink mesh u         w
// ink mesh binormal       xyz, ink mesh v         w
// lightmap tangent        xyz, lighmap  u         w
// lightmap binormal       xyz, lighmap  v         w
// surface clip range      xyzw
//
// lightmap offset         xy

struct VS_INPUT {
    float3 pos                     : POSITION;
    float3 normal                  : NORMAL0;
    float4 baseBumpUV              : TEXCOORD0; // xy:  Ink UV,                  zw: World bumpmap UV
    float4 lightmapUV_offset       : TEXCOORD1; // xy:  Lightmap UV,             zw: Bumpmapped lightmap offset
    float3 inkTangent_lightmapX    : TEXCOORD2; // xyz: Ink mesh tangent,        w:  lightmap tangent X
    float3 inkBinormal_lightmapX   : TEXCOORD3; // xyz: Ink mesh binormal,       w:  lightmap binormal X
    float3 worldTangent_lightmapY  : TEXCOORD4; // xyz: World geometry tangent,  w:  lightmap tangent Y
    float3 worldBinormal_lightmapY : TEXCOORD5; // xyz: World geometry binormal, w:  lightmap binormal Y
    float4 surfaceClipRange        : TEXCOORD6;
    float  lightmapTangentZ        : BLENDWEIGHT0;
    float  lightmapBinormalZ       : BLENDWEIGHT1;
};

struct VS_OUTPUT {
    float4 pos                          : POSITION;
    float4 projPos                      : TEXCOORD0; // xyzw: projected position
    float4 inkUV_worldBumpUV            : TEXCOORD1; // xy: ink albedo UV,      zw: world bumpmap UV
    float4 lightmapUV_offset            : TEXCOORD2; // xy: lightmap UV,        zw: bumpmapped lightmap offset
    float4 surfaceClipRange             : TEXCOORD3; // xy: ink map min UV,     zw: ink map max UV
    float4 worldPos_tangentX            : TEXCOORD4; // xyz: world position,    w:  world tangent X
    float4 worldBinormal_tangentY       : TEXCOORD5; // xyz: world binormal,    w:  world tangent Y
    float4 worldNormal_tangentZ         : TEXCOORD6; // xyz: world normal,      w:  world tangent Z
    float4 inkTangent_lightmapTangentX  : TEXCOORD7; // xyz: ink tangent,       w:  lightmap tangent X
    float4 inkBinormal_lightmapTangentY : TEXCOORD8; // xyz: ink binormal,      w:  lightmap tangent Y
    float4 lightmapBinormal_tangentZ    : TEXCOORD9; // xyz: lightmap binormal, w:  lightmap tangent Z
};

static const float DEPTH_BIAS = 2.0e-5; // Depth bias in normalized device coordinates
const float4x4 cModelViewProj : register(c4);
const float4   cEyePosWaterZ  : register(c2); // xyz: eye position
VS_OUTPUT main(const VS_INPUT v) {
    float4 projPos = mul(float4(v.pos, 1.0), cModelViewProj);
    projPos.z -= DEPTH_BIAS * projPos.w;

    VS_OUTPUT w;
    w.pos                        = projPos;
    w.projPos                    = projPos;
    w.inkUV_worldBumpUV.xy       = v.baseBumpUV.xy * 0.5;
    w.inkUV_worldBumpUV.zw       = v.baseBumpUV.zw;
    w.lightmapUV_offset          = v.lightmapUV_offset;
    w.surfaceClipRange           = v.surfaceClipRange.yxwz * 0.5;
    w.worldPos_tangentX.xyz      = v.pos;
    w.worldBinormal_tangentY.xyz = v.worldBinormal_lightmapY;
    w.worldNormal_tangentZ.xyz   = v.normal;
    w.worldPos_tangentX.w        = v.worldTangent_lightmapY.x;
    w.worldBinormal_tangentY.w   = v.worldTangent_lightmapY.y;
    w.worldNormal_tangentZ.w     = v.worldTangent_lightmapY.z;
    w.inkTangent_lightmapTangentX.xyz = v.inkBinormal_lightmapX * 0.5; // Intentionally swapped
    w.inkBinormal_lightmapTangentY.xyz = v.inkTangent_lightmapX * 0.5; // Intentionally swapped
    w.inkTangent_lightmapTangentX.w = v.inkTangent_lightmapX.w;
    w.inkBinormal_lightmapTangentY.w = v.worldTangent_lightmapY;
    w.lightmapBinormal_tangentZ.w = v.lightmapTangentZ;
    w.lightmapBinormal_tangentZ.xyz = float3(v.lightmapBinormalZ);
    return w;
}
