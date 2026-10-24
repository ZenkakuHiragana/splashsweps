#include "inkmesh_common.hlsl"

// Initializes the lower half of SceneAndFlashlight: zero light in the color,
// and the scene depth in the depth buffer so the flashlight pass of the ink meshes skips the parts the scene hides.
sampler DepthBuffer : register(s0); // _rt_resolvedfullframedepth
static const float g_DepthScale = c0.x; // zfar / (zfar - znear)
static const float g_DepthBias  = c0.y; // -znear * zfar / (zfar - znear)

struct PS_OUTPUT {
    float4 color : COLOR0;
    float  depth : DEPTH0;
};

PS_OUTPUT main(float2 uv : TEXCOORD0) {
    uv += s0Size * 0.5;
    float viewDepthHU = tex2D(DepthBuffer, uv).r * DEPTHWRITE_TO_HU;

    // Pushes the depth back by the tolerance inkmesh_ps_main.hlsl uses to compare with the scene depth,
    // as the ink meshes lie on the scene geometry.
    viewDepthHU += max(2.0, viewDepthHU * 0.015);

    PS_OUTPUT output = {
        float4(0.0, 0.0, 0.0, 0.0),
        saturate(g_DepthScale + g_DepthBias / max(viewDepthHU, 1.0e-3)),
    };
    return output;
}
