struct VS_INPUT {
    float3 pos                  : POSITION0;
    float4 inkUV_worldBumpUV    : TEXCOORD0;
    float4 surfaceClipRange     : TEXCOORD1;
    float4 worldPos_projPosZ    : TEXCOORD2;
    float4 worldNormalTangentY  : TEXCOORD3;
    float4 inkTangentXYZWorldZ  : TEXCOORD4;
    float4 inkBinormalMeshLift  : TEXCOORD5;
    float4 projPosW_meshRole    : TEXCOORD6;
};

struct VS_OUTPUT {
    float4 pos                   : POSITION;
    float4 surfaceClipRange      : TEXCOORD0;
    float4 lightmapUV1And2       : TEXCOORD1;
    float4 lightmapUV3_projXY    : TEXCOORD2;
    float4 inkUV_worldBumpUV     : TEXCOORD3;
    float4 worldPos_projPosZ     : TEXCOORD4;
    float4 worldBinormalTangentX : TEXCOORD5;
    float4 worldNormalTangentY   : TEXCOORD6;
    float4 inkTangentXYZWorldZ   : TEXCOORD7;
    float4 inkBinormalMeshLift   : TEXCOORD8;
    float4 projPosW_meshRole     : TEXCOORD9;
};

const float4x4 cViewProj : register(c8);

VS_OUTPUT main(const VS_INPUT v) {
    VS_OUTPUT o = (VS_OUTPUT)0.0;
    o.pos                   = mul(float4(v.pos, 1.0), cViewProj);
    o.surfaceClipRange      = v.surfaceClipRange;
    o.lightmapUV1And2       = 0.0;
    o.lightmapUV3_projXY    = 0.0;
    o.inkUV_worldBumpUV     = v.inkUV_worldBumpUV;
    o.worldPos_projPosZ     = v.worldPos_projPosZ;
    o.worldBinormalTangentX = 0.0;
    o.worldNormalTangentY   = v.worldNormalTangentY;
    o.inkTangentXYZWorldZ   = v.inkTangentXYZWorldZ;
    o.inkBinormalMeshLift   = v.inkBinormalMeshLift;
    o.projPosW_meshRole     = v.projPosW_meshRole;
    return o;
}
