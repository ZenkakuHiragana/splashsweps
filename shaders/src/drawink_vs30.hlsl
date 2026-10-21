
// POSITION0
//   xyz : Paint center in world coordinates, or flattened displacement paint coordinates
// TEXCOORD0
//   xyz : Paint angles in degrees (pitch, yaw, roll), flattened for displacement surfaces
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
// NORMAL0
//   x : Width
//   y : Height
//   z : Depth scale
// COLOR0
//   r : x255 = 255 for the boundary band quad drawn before the paints, 0 otherwise
//   g : x16 = 0bRRCC = Region and corner index
//   b : x255 = Paint type ID
//   a : x255 = $detailblendmode of the paint type, 0 if the detail is disabled

#include "inkmesh_common.hlsl"

static const float  CornerSignX[4] = { -1,  1, 1, -1 };
static const float  CornerSignY[4] = { -1, -1, 1,  1 };
static const float2 ConstantUV[4]  = {{ 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 }};

struct VS_INPUT {
    float3   worldPos              : POSITION0;
    float4   worldAngles           : TEXCOORD0;
    float4   baseTextureAtlasRange : TEXCOORD1;
    float4   tintTextureAtlasRange : TEXCOORD2;
    float4   shapeMaskAtlasRange   : TEXCOORD3;
    float4   surfaceClipRange      : TEXCOORD4;
    float4x2 worldToUV             : TEXCOORD5;
    float4   size                  : NORMAL0;
    float4   bandIndexTypeDetail   : COLOR0;
};

struct VS_OUTPUT {
    float4 pos                  : POSITION;
    float4 inkAndTintUV         : TEXCOORD0;
    float4 shapeUVAndDetail     : TEXCOORD1; // xy: shape atlas UV, z: mode / 255, w: 5-bit paint angle
    float4 surfaceClipRange     : TEXCOORD2;
    float4 typeRegionBandZScale : TEXCOORD3;
    float4 paintPlacement       : TEXCOORD4; // xy: packed-surface HU center, zw: ink-map -> paint (cos, sin)
    float2 shapeDistanceScale   : TEXCOORD5; // x: HU per shape mask alpha unit, y: Hammer units to UV
};

#define isBand               v.bandIndexTypeDetail.x
#define regionIndex      int(v.bandIndexTypeDetail.y * 4)
#define cornerIndex int(fmod(v.bandIndexTypeDetail.y * 16, 4))
#define inkType        floor(v.bandIndexTypeDetail.z * 255)
#define detailMode           v.bandIndexTypeDetail.a
#define HammerUnitsToUV      v.worldAngles.w

float2 AtlasUV(float4 range, float2 corner) {
    // Decode the signed min U and cancel the source transposition used when copying the cell.
    bool transposed = range.x < 0.0;
    range.x = abs(range.x);
    return lerp(range.xy, range.zw, transposed ? corner.yx : corner);
}

// The shape mask alpha is 0.5 + (signed distance in mask pixels) / (mask width in pixels).
// The mask spans the paint quad, so one alpha unit is W pixels of 2 * size.x / W and 2 * size.y / H HU.
// The shorter of the two is used for both directions; masks keep their pixels nearly square in HU.
float ShapeMaskAlphaToHU(float4 shapeRange, float2 halfSize) {
    // The atlas is square, so the cell's UV extents give the mask aspect ratio.
    float2 cellUV      = abs(float2(shapeRange.z - abs(shapeRange.x), shapeRange.w - shapeRange.y));
    float  widthHeight = shapeRange.x < 0.0 ? cellUV.y / cellUV.x : cellUV.x / cellUV.y;
    return 2.0 * min(halfSize.x, halfSize.y * widthHeight);
}

VS_OUTPUT main(const VS_INPUT v) {
    float3 sine, cosine;
    sincos(radians(v.worldAngles.xyz), sine, cosine);

    float3 worldForward = { cosine.x * cosine.y, cosine.x * sine.y, -sine.x };
    float2 paintAxisVInInkMap = normalize(mul(float4(worldForward, 0.0), v.worldToUV)).yx;
    float2 paintAxisUInInkMap = { paintAxisVInInkMap.y, -paintAxisVInInkMap.x };
    float paintAngle = atan2(paintAxisUInInkMap.y, paintAxisUInInkMap.x);
    float paintRotationCode5 = floor(frac(paintAngle / TAU) * 32.0 + 0.5);
    // Nearest-angle rounding can produce one full turn (32), stored as direction 0.
    paintRotationCode5 -= floor(paintRotationCode5 / 32.0) * 32.0;

    // Flip U and V to match handedness to the world coordinate system
    float2 uvPos = mul(float4(v.worldPos, 1.0), v.worldToUV).yx;
    float2 inkMapCenterHU = uvPos; // Before UV scaling and the four-region offset.
    uvPos += paintAxisUInInkMap * v.size.x * CornerSignX[cornerIndex];
    uvPos += paintAxisVInInkMap * v.size.y * CornerSignY[cornerIndex];
    uvPos *= HammerUnitsToUV;

    VS_OUTPUT output;
    float2 corner = ConstantUV[cornerIndex];
    float  zScale = saturate(v.size.z / HEIGHT_TO_HU);
    output.inkAndTintUV = float4(
        AtlasUV(v.baseTextureAtlasRange, corner),
        AtlasUV(v.tintTextureAtlasRange, corner));
    output.shapeUVAndDetail = float4(AtlasUV(v.shapeMaskAtlasRange, corner), detailMode, paintRotationCode5);
    output.surfaceClipRange
        = v.surfaceClipRange.yxwz * 0.5 + INKMAP_REGION_OFFSETS[regionIndex].xyxy;
    output.typeRegionBandZScale = float4(inkType, regionIndex, isBand, zScale);
    output.paintPlacement = float4(inkMapCenterHU, DecodeInkMapToPaintCosSin(paintRotationCode5));
    output.shapeDistanceScale = float2(ShapeMaskAlphaToHU(v.shapeMaskAtlasRange, v.size.xy), HammerUnitsToUV);
    // Fold region placement into clip space to avoid rounding the shifted UV before subtracting 1.
    // Paints are drawn in queue order without depth, so later quads overwrite earlier ones.
    output.pos = float4(uvPos + (INKMAP_REGION_OFFSETS[regionIndex] * 2.0 - 1.0), 0.0, 1.0);
    output.pos.y *= -1.0;
    return output;
}
