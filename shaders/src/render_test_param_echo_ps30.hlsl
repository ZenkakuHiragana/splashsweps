
struct PS_INPUT {
    float2 uv   : TEXCOORD0;
    float4 tint : TEXCOORD1;
};

const float4 c0 : register(c0);
float4 main(const PS_INPUT i) : COLOR0 {
    return float4(c0.x, c0.y, c0.z, c0.w);
}
