
// Data texture layout
#define ID_COLOR_ALPHA        0
#define ID_TINT_GEOMETRYPAINT 1
#define ID_EDGE               2
#define ID_HEIGHT_MAXLAYERS   3
#define ID_MATERIAL_REFRACT   4
#define ID_MISC               5
#define ID_DETAILS_BUMPBLEND  6
#define ID_OTHERS             7

// [0.0, 1.0] --> [-1.0, +1.0]
#define TO_SIGNED(x) ((x) * 2.0 - 1.0)

// [-1.0, +1.0] --> [0.0, 1.0]
#define TO_UNSIGNED(x) saturate((x) * 0.5 + 0.5)

// Safe rcp that avoids division by zero
#define SAFERCP(x) (TO_SIGNED(step(0.0, x)) * rcp(max(abs(x), 1.0e-16)))

static const float  HEIGHT_TO_HU = 24.0;
static const float4 GROUND_PROPERTIES[8] = {
    { 1.0, 1.0, 1.0,  1.0 },
    { 1.0, 1.0, 1.0,  0.0 },
    { 1.0, 1.0, 1.0,  1.0 },
    { 1.0, 1.0, 0.75, 0.5 },
    { 0.0, 0.0, 0.0,  1.0 },
    { 0.0, 1.0, 1.0,  1.0 },
    { 0.0, 1.0, 1.0,  1.0 },
    { 0.0, 0.0, 0.0,  0.0 },
};

// Canonical shader semantics usage through vertex shader and pixel shader.
// For vertex shader, TEXCOORD0 to TEXCOORD7 are valid semantics.
// For pixel shader, all semantics are used.
struct VertexInfo {
    float4 surfaceClipRange   : TEXCOORD0; // xy: ink map min UV, zw: ink map max UV
    float4 worldTangent_U     : TEXCOORD1; // w:  world geometry U
    float4 worldBinormal_V    : TEXCOORD2; // w:  world geometry V
    float4 worldNormal_dU     : TEXCOORD3; // w:  lightmap UV offset U
    float4 inkTangent_U       : TEXCOORD4; // w:  ink U
    float4 inkBinormal_V      : TEXCOORD5; // w:  ink V
    float4 lightmapTangent_U  : TEXCOORD6; // w:  lightmap U
    float4 lightmapBinormal_V : TEXCOORD7; // w:  lightmap V
    float4 worldPos           : TEXCOORD8; // w:  unused
    float4 clipPos            : TEXCOORD9;
};

// Constants
const float4 c0        : register(c0);
const float4 c1        : register(c1);
const float4 c2        : register(c2);
const float4 c3        : register(c3);
const float2 s0Size    : register(c4);
const float2 s1Size    : register(c5);
const float2 s2Size    : register(c6);
const float2 s3Size    : register(c7);
const float4 c8        : register(c8);
const float4 c9        : register(c9);
const float4 g_EyePos  : register(c10); // xyz: eye position
const float4 c11       : register(c11); // $viewprojmat
const float4 c12       : register(c12);
const float4 c13       : register(c13);
const float4 c14       : register(c14);
const float4 c15       : register(c15); // w: unused
const float4 c16       : register(c16); // w: unused
const float2x4 c17     : register(c15); // $invviewprojmat
const float4 HDRParams : register(c30);

const sampler InkDataDetail : register(s1);
static const float2 g_DataRTSize     = s1Size.xy;
static const float  g_InkDataOffsetV = c3.w;
float4 FetchDataPixel(int id, int index) {
    if (id == 0) {
        return GROUND_PROPERTIES[index];
    }
    else {
        return tex2Dlod(InkDataDetail, float4(
            (id    - 0.5) * g_DataRTSize.x,
            (index + g_InkDataOffsetV + 0.5) * g_DataRTSize.y,
            0.0,
            0.0));
    }
}

