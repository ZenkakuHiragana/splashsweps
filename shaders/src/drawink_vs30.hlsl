
// POSITION0
//   xyz : The world position of the splash
// TEXCOORD0
//   xyz : The world angle of the splash (x, y, z = pitch, yaw roll)
//   w   : Hammer units to UV conversion constant
// TEXCOORD1
//   x : Ink $basetexture atlas min U (negative if transposed)
//   y : Ink $basetexture atlas min V
//   z : Ink $basetexture atlas max U
//   w : Ink $basetexture atlas max V
// TEXCOORD2
//   x : Ink $tinttexture atlas min U (negative if transposed)
//   y : Ink $tinttexture atlas min V
//   z : Ink $tinttexture atlas max U
//   w : Ink $tinttexture atlas max V
// TEXCOORD3
//   x : Ink shape mask atlas min U (negative if transposed)
//   y : Ink shape mask atlas min V
//   z : Ink shape mask atlas max U
//   w : Ink shape mask atlas max V
// TEXCOORD4
//   x : Surface min U
//   y : Surface min V
//   z : Surface max U
//   w : Surface max V
// TEXCOORD5
//   xyz : WorldToUV matrix rotation (first row)
//   w   : WorldToUV matrix offset U
// TEXCOORD6
//   xyz : WorldToUV matrix rotation (second row)
//   w   : WorldToUV matrix offset V
// TANGENT0
//   x : Width
//   y : Height
//   z : Depth scale
// COLOR0
//   r : Normalized paint time
//   g : x16 = 0bRRCC = Region and corner index
//   b : x255 + 1 = Paint type ID
//   a : x255 = $detailblendmode of the paint type, 0 if the detail is disabled

#include "inkmesh_common.hlsl"

static const float  CornerSignX[4]  = { -1,  1, 1, -1 };
static const float  CornerSignY[4]  = { -1, -1, 1,  1 };
static const float2 ConstantUV[4]   = {{ 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 }};

struct VS_INPUT {
    float3   worldPos              : POSITION0;
    float4   worldAngles           : TEXCOORD0;
    float4   baseTextureAtlasRange : TEXCOORD1;
    float4   tintTextureAtlasRange : TEXCOORD2;
    float4   shapeMaskAtlasRange   : TEXCOORD3;
    float4   surfaceClipRange      : TEXCOORD4;
    float4x2 worldToUV             : TEXCOORD5;
    float4   size                  : NORMAL0;
    float4   timeIndexTypeDetail   : COLOR0;
};

struct VS_OUTPUT {
    float4 pos                  : POSITION;
    float4 inkAndTintUV         : TEXCOORD0;
    float4 shapeUVDetailMode    : TEXCOORD1; // xy: mask, z: mode, w: rotation code
    float4 surfaceClipRange     : TEXCOORD2;
    float4 typeRegionTimeZScale : TEXCOORD3;
    float4 detailCenterRotation : TEXCOORD4; // Ink-map HU center and inverse paint rotation
};

#define time                 v.timeIndexTypeDetail.x
#define regionIndex      int(v.timeIndexTypeDetail.y * 4)
#define cornerIndex int(fmod(v.timeIndexTypeDetail.y * 16, 4))
#define inkType        floor(v.timeIndexTypeDetail.z * 255)
#define detailMode           v.timeIndexTypeDetail.a
#define HammerUnitsToUV      v.worldAngles.w

float2 AtlasUV(float4 range, float2 corner) {
    // Decode the signed min U and cancel the source transposition used when copying the cell.
    bool transposed = range.x < 0.0;
    range.x = abs(range.x);
    return lerp(range.xy, range.zw, transposed ? corner.yx : corner);
}

VS_OUTPUT main(const VS_INPUT v) {
    float3 sine, cosine;
    sincos(radians(v.worldAngles.xyz), sine, cosine);

    float3 worldForward = { cosine.x * cosine.y, cosine.x * sine.y, -sine.x };
    float2 basisV = normalize(mul(float4(worldForward, 0.0), v.worldToUV)).yx;
    float2 basisU = { basisV.y, -basisV.x };
    float angle = atan2(basisU.y, basisU.x);
    float rotationCode = floor(frac(angle / 6.283185307179586) * 32.0 + 0.5);
    rotationCode -= floor(rotationCode / 32.0) * 32.0;

    // Flip U and V to match handedness to the world coordinate system
    float2 uvPos = mul(float4(v.worldPos, 1.0), v.worldToUV).yx;
    float2 detailCenter = uvPos;
    uvPos += basisU * v.size.x * CornerSignX[cornerIndex];
    uvPos += basisV * v.size.y * CornerSignY[cornerIndex];
    uvPos *= HammerUnitsToUV;

    // Convert position to local to specific region
    uvPos *= 0.5;
    uvPos += INKMAP_REGION_OFFSETS[regionIndex];

    VS_OUTPUT output;
    float2 corner = ConstantUV[cornerIndex];
    float  zScale = saturate(v.size.z / HEIGHT_TO_HU);
    output.inkAndTintUV = float4(
        AtlasUV(v.baseTextureAtlasRange, corner),
        AtlasUV(v.tintTextureAtlasRange, corner));
    output.shapeUVDetailMode = float4(AtlasUV(v.shapeMaskAtlasRange, corner), detailMode, rotationCode);
    output.surfaceClipRange
        = v.surfaceClipRange.yxwz * 0.5 + INKMAP_REGION_OFFSETS[regionIndex].xyxy;
    output.typeRegionTimeZScale = float4(inkType, regionIndex, time, zScale);
    output.detailCenterRotation = float4(detailCenter, InkDetailRotation(rotationCode));
    output.pos = float4(uvPos * 2.0 - 1.0, time, 1.0);
    output.pos.y *= -1.0;
    return output;
}
