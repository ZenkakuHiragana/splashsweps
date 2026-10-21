
struct PS_INPUT {
    float2 uv   : TEXCOORD0;
    float4 tint : TEXCOORD1;
};

sampler BaseTexture : register(s0);
const float2 c0 : register(c0);
const float2 BaseTexturePixelSize : register(c4); // One over $basetexture size
static const float Channel = c0.x;
static const float VertexColor = c0.y;
float4 main(const PS_INPUT i) : COLOR0 {
    if (step(0.5, VertexColor)) {
        return saturate(i.tint);
    }
    else {
        // UVs outside the texture read its edge pixels, regardless of the texture's wrap mode.
        float2 halfPixel = BaseTexturePixelSize * 0.5;
        float4 s = tex2D(BaseTexture, clamp(i.uv, halfPixel, 1.0 - halfPixel));
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
