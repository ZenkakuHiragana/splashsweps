
// Pixel shader constants available if we draw VertexLitGeneric with $phong = 1 first.
// c0  $c0_xyzw from VMT
// c1  $c1_xyzw from VMT
// c2  $c2_xyzw from VMT
// c3  $c3_xyzw from VMT
// c4  TexBaseSize   normalized dimensions for each texture above
// c5  Tex1Size      (x = 1.0 / width, y = 1.0 / height)
// c6  Tex2Size
// c7  Tex3Size
// c8  cAmbientCube[4]
// c9  cAmbientCube[5]
// c10 g_EyePos   w seems to be unused
// c11 g_ViewProjMatrix column 0 from $viewprojmat
// c12 g_ViewProjMatrix column 1
// c13 g_ViewProjMatrix column 2
// c14 g_ViewProjMatrix column 3
// c15 g_InvViewProjMatrix column 0 from $invviewprojmat
// c16 g_InvViewProjMatrix column 1
// c17 g_InvViewProjMatrix column 2
// c18 g_InvViewProjMatrix column 3
// c19 g_FresnelSpecParams
//     g_FresnelSpecParams.xyz = g_FresnelRanges (not equal to $phongfresnelranges)
//     g_FresnelSpecParams.w   = $phongboost
// c20 cLightInfo[0].color
// c21 cLightInfo[0].pos
// c22 cLightInfo[1].color                         g_FlashlightAttenuationFactors      (if $phong = 0)
// c23 cLightInfo[1].pos                           g_FlashlightPos                     (if $phong = 0)
// c24 cLightInfo[2].color                         g_FlashlightWorldToTexture column 0 (if $phong = 0)
// c25 cLightInfo[2].pos                           g_FlashlightWorldToTexture column 1 (if $phong = 0)
// c26 g_SpecularRimParams                         g_FlashlightWorldToTexture column 2 (if $phong = 0)
//     g_SpecularRimParams.xyz = $phongtint
//     g_SpecularRimParams.w   = $rimlightexponent if $rimlight = 1
// c27 g_ShaderControls                            g_FlashlightWorldToTexture column 3 (if $phong = 0)
//     g_ShaderControls.x = $basemapalphaphongmask
//     g_ShaderControls.y = Unused
//     g_ShaderControls.z = $blendtintcoloroverbase
//     g_ShaderControls.w = $invertphongmask
// c28 cFlashlightColor
//     cFlashlightColor.w = flFlashlightNoLambertValue = 0.0 or 2.0
// c29 g_LinearFogColor
// c30 HDRParams
//     HDRParams.x = TonemapScale exposure scale (bounded by tonemap controller's min/max)
//     HDRParams.y = LightmapScale 16 in HDR, 4.59479 in LDR
//     HDRParams.z = EnvmapScale 16 in HDR, 1 in LDR
//     HDRParams.w = GammaScale gamma, equivalent to pow(TonemapScale, 1.0 / 2.2)
// c31 cFlashlightScreenScale
//     cFlashlightScreenScale.x
//     cFlashlightScreenScale.y
//     cFlashlightScreenScale.z Unused
//     cFlashlightScreenScale.w Unused

sampler Texture2 : register(s2);
const float4 c[32] : register(c0);

struct PS_INPUT {
    float4 pos      : VPOS;
    float4 uv_depth : TEXCOORD0;
    float4 data[8]  : TEXCOORD1;
};

struct PS_OUTPUT {
    float4 color : COLOR0;
    float  depth : DEPTH0;
};

PS_OUTPUT main(const PS_INPUT i) {
    const float NUM_DIVISION = 8;
    float2 uv    = i.uv_depth.xy;
    float  ix    = min(floor(uv.x * NUM_DIVISION), NUM_DIVISION - 1);
    float  iy    = min(floor(uv.y * 0.5 * NUM_DIVISION), NUM_DIVISION - 1);
    float  index = iy * NUM_DIVISION + ix;
    float4 data  = c[index];
    PS_OUTPUT output = {
        float4(0.0, 0.0, 0.0, 0.0),
        i.uv_depth.z / i.uv_depth.w,
    };
    if (c[3].w > 0) {
        data = index < 8 ? i.data[index] : float4(0.0, 0.0, 0.0, 0.0);
    }
    float4 albedo = tex2D(Texture2, uv);
    albedo.rgb = 1.0 - albedo.rgb;

    if (uv.y * 0.5 * NUM_DIVISION - iy < 0.5) {
        if (uv.x * NUM_DIVISION - ix < 0.25 && uv.y * 0.5 * NUM_DIVISION - iy < 0.125) {
            float u = (uv.x * NUM_DIVISION - ix) * 4.0;
            float v = (uv.y * 0.5 * NUM_DIVISION - iy) * 8.0;
            u = (0.25 - (u - 0.5) * (u - 0.5)) * 4.0;
            v = (0.25 - (v - 0.5) * (v - 0.5)) * 4.0;
            if (data.r < -1 || data.r > 1 ||
                data.g < -1 || data.g > 1 ||
                data.b < -1 || data.b > 1) {
                output.color = lerp(float4(u, v, (u + v) / 2.0, 1.0), float4(albedo.rgb, 1.0), albedo.a);
            }
            else if (data.r < 0 || data.g < 0 || data.b < 0) {
                output.color = float4(
                    data.r < 0 ? 1.0 : 0.0,
                    data.g < 0 ? 1.0 : 0.0,
                    data.b < 0 ? 1.0 : 0.0,
                    1.0);
            }
        }
        if (-1 <= data.r && data.r <= 1 &&
            -1 <= data.g && data.g <= 1 &&
            -1 <= data.b && data.b <= 1) {
            output.color = lerp(float4(abs(data.rgb), 1.0), float4(albedo.rgb, 1.0), albedo.a);
        }
        else if (c[1].w > 0) {
            output.color = lerp(float4((clamp(rcp(data.rgb), -1.0, 1.0) + 1.0) / 2.0, 1.0), float4(albedo.rgb, 1.0), albedo.a);
        }
        else {
            output.color = lerp(float4((sign(data.rgb) + 1.0) / 2.0, 1.0), float4(albedo.rgb, 1.0), albedo.a);
        }
    }
    else {
        if (uv.x * NUM_DIVISION - ix < 0.25 && uv.y * 0.5 * NUM_DIVISION - iy < 0.625) {
            float u = (uv.x * NUM_DIVISION - ix) * 4.0;
            float v = (uv.y * 0.5 * NUM_DIVISION - iy - 0.5) * 8.0;
            u = (0.25 - (u - 0.5) * (u - 0.5)) * 4.0;
            v = (0.25 - (v - 0.5) * (v - 0.5)) * 4.0;
            if (data.a < -1 || data.a > 1) {
                output.color = lerp(float4(u, v, (u + v) / 2.0, 1.0), float4(albedo.rgb, 1.0), albedo.a);
            }
            else if (data.a < 0) {
                output.color = float4(1.0, 0.0, 0.0, 1.0);
            }
        }
        if (-1 <= data.a && data.a <= 1) {
            output.color = lerp(float4(abs(data.aaa), 1.0), float4(albedo.rgb, 1.0), albedo.a);
        }
        else if (c[1].w > 0) {
            output.color = lerp(float4((clamp(rcp(data.aaa), -1.0, 1.0) + 1.0) / 2.0, 1.0), float4(albedo.rgb, 1.0), albedo.a);
        }
        else {
            output.color = lerp(float4((sign(data.aaa) + 1.0) / 2.0, 1.0), float4(albedo.rgb, 1.0), albedo.a);
        }
    }
    return output;
}
