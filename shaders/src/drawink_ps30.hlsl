
sampler Albedo   : register(s0); // $basetexture
sampler Normal   : register(s1); // $texture1
sampler Material : register(s2); // $texture2
sampler Mask     : register(s3); // $texture3
struct PS_INPUT {
    float2 pos : VPOS;
    float2 uv  : TEXCOORD0;
};
struct PS_OUTPUT {
    float4 additive       : COLOR0;
    float4 multiplicative : COLOR1;
    float4 pbr            : COLOR2;
    float4 details        : COLOR3;
};

#define AddRGB     output.additive.rgb
#define MulRGB     output.multiplicative.rgb
#define Height     output.additive.a
#define Refraction output.multiplicative.a
#define PBR        output.pbr.rgb
#define BumpBlend  output.pbr.a
PS_OUTPUT main(const PS_INPUT i) {
    PS_OUTPUT output;
    float mask = tex2D(Mask, i.uv).a;
    if (mask == 0) discard;
    float4 albedo = tex2D(Albedo, i.uv);
    float4 normal = tex2D(Normal, i.uv);
    float4 pbr    = tex2D(Material, i.uv);
    AddRGB = albedo.rgb;
    MulRGB = float3(0.0, 0.0, 0.0);
    Height = normal.z;
    Refraction = 0.0;
    PBR    = pbr.rgb;
    BumpBlend = 0.75;
    output.details = float4(0.0, 0.0, 0.0, 1.0);
    return output;
}
