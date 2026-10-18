
// Data texture layout
#define ID_COLOR_ALPHA        0
#define ID_TINT_GEOMETRYPAINT 1
#define ID_HEIGHT_MAXLAYERS   2
#define ID_MISC               3
#define ID_MATERIAL_REFRACT   4
#define ID_BUMPBLEND          5 // r: $bumpblenddistance / BUMPBLEND_DISTANCE_MAX, see BumpBlendFactor in inkmesh_ps30
#define ID_DETAIL_BLEND_SCALE 6 // $detailblendscale xyzw
#define ID_DETAIL_TRANSFORM   7 // $detailtexturetransform translation / rotation basis
#define ID_DETAIL_SCALE       8 // $detailtexturetransform scale / $detail index / height mask (see DetailHeightMask)

static const int DETAIL_MODE_NONE     = 0;
static const int DETAIL_MODE_MATERIAL = 1;
static const int DETAIL_MODE_NORMAL   = 2;
static const int DETAIL_MODE_EMISSION = 3;
static const int DETAIL_MODE_COLOR    = 4;
static const int DETAIL_MODE_THINFILM = 5;

// Ink map layout: four regions with the same surface packing, at these UV offsets
//   additive color  : rgb = additive color,       a = detail phase U of the upper layer
//   multiplicative  : rgb = multiplicative color, a = detail phase V of the upper layer
//   indices         : rgb = ink type IDs,         a = x255 = 0bRRRRRMMM of the upper layer,
//                     M = $detailblendmode, R = detail rotation in DETAIL_ROTATION_STEPS
// The three regions above take their alpha from the paint that writes the ink type IDs.
// Phases and rotations matter only to $detaillocal ink types, see DetailImagePosition.
//   height and depth: rg = height, ba = ground depth, both in 16 bits (see EncodeUnorm16)
static const float2 INKMAP_ADDITIVE       = { 0.0, 0.0 };
static const float2 INKMAP_MULTIPLICATIVE = { 0.5, 0.0 };
static const float2 INKMAP_INDICES        = { 0.0, 0.5 };
static const float2 INKMAP_HEIGHT_DEPTH   = { 0.5, 0.5 };
static const float2 INKMAP_REGION_OFFSETS[4] = {
    INKMAP_ADDITIVE, INKMAP_MULTIPLICATIVE, INKMAP_INDICES, INKMAP_HEIGHT_DEPTH,
};

// Splits [0, 1] into two 8-bit channels holding the upper and lower bytes.
// Each channel gets k/255 plus a quarter step, so that both rounding and truncation store k.
// Decoding is linear in the channels, so bilinear filtering of them stays correct across carries.
float2 EncodeUnorm16(float x) {
    float q  = round(saturate(x) * 65535.0);
    float hi = floor(q / 256.0);
    return (float2(hi, q - hi * 256.0) + 0.25) / 255.0;
}

float DecodeUnorm16(float2 hiLo) {
    return dot(hiLo, float2(256.0, 1.0)) / 257.0; // (hi * 256 + lo) * 255 / 65535
}

// [0.0, 1.0] --> [-1.0, +1.0]
#define TO_SIGNED(x) ((x) * 2.0 - 1.0)

// [-1.0, +1.0] --> [0.0, 1.0]
#define TO_UNSIGNED(x) saturate((x) * 0.5 + 0.5)

// Safe rcp that avoids division by zero
#define SAFERCP(x) (TO_SIGNED(step(0.0, x)) * rcp(max(abs(x), 1.0e-16)))

static const float  DEPTHWRITE_TO_HU = 4000.0; // Hardcoded in DepthWrite shader used in _rt_resolvedfullframedepth
static const float  HEIGHT_TO_HU     = 24.0;   // Ink height map to hammer unit conversion constant
static const float  BUMPBLEND_DISTANCE_MAX = 2.0 * HEIGHT_TO_HU; // Hardcoded in inkdetail.lua
static const float  DETAIL_ROTATION_STEPS  = 32.0; // Steps of a local detail rotation per turn
static const float  DETAIL_HEIGHT_STEPS    = 32.0; // Steps of a detail height mask range, see DetailHeightMask
static const float3 GrayScaleFactor  = { 0.2126, 0.7152, 0.0722 };
static const float4 GROUND_PROPERTIES[] = {
    { 1.0, 1.0, 1.0,  1.0 },
    { 1.0, 1.0, 1.0,  0.0 },
    { 1.0, 0.0, 0.75, 0.5 },
    { 0.0, 1.0, 1.0,  1.0 },
    { 0.0, 0.0, 0.0,  0.0 },
    { 0.0, 0.0, 0.0,  0.0 },
    { 0.0, 0.0, 0.0,  0.0 },
    { 0.0, 0.0, 254.0 / 255.0, 127.0 / 255.0 },
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
const float4 c15       : register(c15); // xyz: blend transform row 0
const float4 c16       : register(c16); // xyz: blend transform row 1
const float4 c17       : register(c17); // unused
const float4 c18       : register(c18); // unused
const float4 HDRParams : register(c30);

static const float2 g_DataRTSize     = s1Size.xy;
static const float  g_InkDataOffsetV = c3.w;
float4 FetchDataPixel(sampler s, int id, int index) {
    if (id == 0) {
        return GROUND_PROPERTIES[index];
    }
    else {
        return tex2Dlod(s, float4(
            (id    - 0.5) * g_DataRTSize.x,
            (index + g_InkDataOffsetV + 0.5) * g_DataRTSize.y,
            0.0,
            0.0));
    }
}

float ScreenEdgeFade(float2 uv) {
    float edge = min(min(uv.x, uv.y), 1.0 - max(uv.x, uv.y));
    return smoothstep(0.0, 0.0625, edge);
}

// Prepares the inverse of the basis (a, b, c), so that
// mul(MakeBasisInverse(a, b, c), v) solves v = x*a + y*b + z*c for (x, y, z).
// Prepare once and apply to several vectors when the basis is shared.
float3x3 MakeBasisInverse(float3 a, float3 b, float3 c) {
    float3 bCrossC = cross(b, c);
    float3 cCrossA = cross(c, a);
    float3 aCrossB = cross(a, b);
    float invDet   = SAFERCP(dot(a, bCrossC));
    return float3x3(
        bCrossC * invDet,
        cCrossA * invDet,
        aCrossB * invDet);
}

// Solves v = x*a + y*b + z*c for the direction of (x, y, z) without dividing by
// det(a, b, c). The result is scaled by |det(a, b, c)|, so use it only when
// the solution is normalized afterwards. Otherwise, use MakeBasisInverse.
float3 SolveBasisDirection(float3 a, float3 b, float3 c, float3 v) {
    float3 aCrossB = cross(a, b);
    float3 cCrossV = cross(c, v);
    float  detSign = dot(c, aCrossB) < 0.0 ? -1.0 : 1.0;
    return float3(dot(b, cCrossV), -dot(a, cCrossV), dot(v, aCrossB)) * detSign;
}

// Solves X = float3(x, y, det) such that v = x*a + y*b
float3 DecomposeBasis(float2 a, float2 b, float2 v) {
    float det = a.x * b.y - b.x * a.y;
    float invDet = SAFERCP(det);
    return float3(
        (v.x * b.y - b.x * v.y) * invDet,
        (a.x * v.y - v.x * a.y) * invDet,
        det);
}

float2 OctSignNotZero(float2 v) {
    return float2(v.x >= 0.0 ? 1.0 : -1.0, v.y >= 0.0 ? 1.0 : -1.0);
}

float2 EncodeOctahedralUnitVector(float3 v) {
    v *= rcp(abs(v.x) + abs(v.y) + abs(v.z));
    float2 encoded = v.xy;
    if (v.z < 0.0) {
        encoded = (1.0 - abs(encoded.yx)) * OctSignNotZero(encoded);
    }
    return encoded * 0.5 + 0.5;
}

float3 DecodeOctahedralUnitVector(float2 encoded) {
    float2 f = encoded * 2.0 - 1.0;
    float3 v = float3(f, 1.0 - abs(f.x) - abs(f.y));
    if (v.z < 0.0) {
        v.xy = (1.0 - abs(v.yx)) * OctSignNotZero(v.xy);
    }
    return normalize(v);
}

// ID_MISC.w * 255 = 0bNHL0 0000, N = $nodig, H = $heightonly, L = $detaillocal
bool IsDetailLocal(float4 miscParam) {
    return frac(miscParam.w * 4.0) >= 0.5;
}

// Rotates a 2D vector by a direction given as (cos, sin)
float2 RotateDirection(float2 v, float2 rotation) {
    return float2(rotation.x * v.x - rotation.y * v.y, rotation.y * v.x + rotation.x * v.y);
}

// (cos, sin) of a local detail rotation given in DETAIL_ROTATION_STEPS
float2 DetailStampRotation(float steps) {
    float2 rotation;
    sincos(steps * (radians(360.0) / DETAIL_ROTATION_STEPS), rotation.y, rotation.x);
    return rotation;
}

// Direction on the ink map UV frame that a local detail rotation is measured from.
// gradU and gradV are the world gradients of the ink map UV, orthogonal and of equal length.
// Painting and drawing agree on it because both pick the world axis the same way,
// so neighboring surfaces keep one splash aligned even when their UV frames differ.
float2 DetailReferenceDirection(float3 gradU, float3 gradV) {
    float3 normal = abs(cross(gradU, gradV));
    float3 axis = normal.x <= normal.y && normal.x <= normal.z ? float3(1, 0, 0)
                : normal.y <= normal.z                         ? float3(0, 1, 0)
                :                                                float3(0, 0, 1);
    return normalize(float2(dot(axis, gradU), dot(axis, gradV)));
}

// $detailtexturetransform of an ink type, decoded from ID_DETAIL_TRANSFORM and ID_DETAIL_SCALE
struct DetailTransform {
    float2 rotation;    // (cos, sin) of the image rotation
    float2 scale;       // $detailtexturetransform scale / $detailperiod = image repeats per Hammer unit
    float2 translation;
};

DetailTransform DecodeDetailTransform(float4 encodedTransform, float4 encodedScale) {
    DetailTransform t;
    t.rotation    = encodedTransform.zw * (255.0 / 127.0) - 1.0;   // 127 / 255 encodes zero
    t.scale       = exp2(encodedScale.xy * (255.0 / 24.0) - 13.0); // 24 steps per octave from 2^-13
    t.translation = encodedTransform.xy;
    return t;
}

// Position in the detail image, before repeating and before adding the phase of a local detail.
// stampRotation turns the image with the splash and is (1, 0) unless the detail is local.
float2 DetailImagePosition(float2 position, float2 stampRotation, DetailTransform t) {
    float2 inStamp = RotateDirection(position, float2(stampRotation.x, -stampRotation.y));
    return RotateDirection(inStamp * t.scale, t.rotation) + t.translation;
}
