
struct PS_INPUT {
    float2 uv   : TEXCOORD0;
    float4 tint : TEXCOORD1;
};

sampler BaseTexture : register(s0);
const float2 c0 : register(c0);
#define Channel c0.x
#define VertexColor c0.y
float4 main(const PS_INPUT i) : COLOR0 {
    if (step(0.5, VertexColor)) {
        return saturate(i.tint);
    }
    else {
        float4 s = tex2D(BaseTexture, i.uv);
        if (floor(Channel) == 0)
            return s.rgbr;
        else if (floor(Channel) == 1)
            return s.rgbg;
        else if (floor(Channel) == 2)
            return s.rgbb;
        else
            return s.rgba;
    }
}
