
struct VS {
    float4 pos : POSITION0;
    float4 uv  : TEXCOORD0;
};

const float4x4 cViewProj : register(c8);
VS main(const VS v) {
    VS w = { mul(v.pos, cViewProj), v.uv };
    return w;
}
