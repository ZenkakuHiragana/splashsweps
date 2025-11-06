
struct VS_INPUT {
    float4 pos : POSITION0;
    float2 uv  : TEXCOORD0;
};
struct VS_OUTPUT {
    float4 pos : POSITION;
    float2 uv  : TEXCOORD0;
};
const float4x4 cModelViewProj : register(c4);
VS_OUTPUT main(const VS_INPUT v) {
    VS_OUTPUT output;
    output.pos = mul(float4(v.pos.xyz, 1.0), cModelViewProj);
    output.uv = v.uv;
    return output;
}
