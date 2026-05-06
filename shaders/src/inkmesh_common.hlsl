
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
#define SAFERCP(x) (TO_SIGNED(step(0.0, x)) * rcp(max(abs(x), 1.0e-21)))

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

struct VS_OUTPUT {
    float4 clipPos : POSITION0;
    VertexInfo vi;
};

struct PS_INPUT {
    float4 screenPos : VPOS;
    VertexInfo vi;
};

