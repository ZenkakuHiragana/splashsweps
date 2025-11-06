
sampler Albedo : register(s0); // $basetexture
sampler Normal : register(s1); // $texture1
sampler Mask   : register(s3); // $texture3
struct PS_INPUT {
    float2 pos : VPOS;
    float2 uv  : TEXCOORD0;
};
struct PS_OUTPUT {
    float4 albedo : COLOR0;
    float4 normal : COLOR1;
};
PS_OUTPUT main(const PS_INPUT i) {
    PS_OUTPUT output;
    float mask = tex2D(Mask, i.uv).a;
    output.albedo = tex2D(Albedo, i.uv);
    output.normal = tex2D(Normal, i.uv);
    output.albedo.a *= mask;
    output.normal.a *= mask;
    return output;
}
