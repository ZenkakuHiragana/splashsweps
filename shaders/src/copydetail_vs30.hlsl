// Dedicated atlas transfer: pixel-space quads use the same 2D transform as copy.
struct VS {
    float4 pos : POSITION0;
    float2 uv  : TEXCOORD0;
};

const float4x4 cViewProj : register(c8);
VS main(const VS v) {
    VS w = { mul(v.pos, cViewProj), v.uv };
    return w;
}
