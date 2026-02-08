
// POSITION0
//   xyz : The world position of the splash
// TEXCOORD0
//   xyz : The world angle of the splash (x, y, z = pitch, yaw roll)
//   w   : Hammer units to UV conversion constant
// TEXCOORD1
//   x : Ink $basetexture atlas min U
//   y : Ink $basetexture atlas min V
//   z : Ink $basetexture atlas max U
//   w : Ink $basetexture atlas max V
// TEXCOORD2
//   x : Ink $tinttexture atlas min U
//   y : Ink $tinttexture atlas min V
//   z : Ink $tinttexture atlas max U
//   w : Ink $tinttexture atlas max V
// TEXCOORD3
//   x : Ink $detail atlas min U
//   y : Ink $detail atlas min V
//   z : Ink $detail atlas max U
//   w : Ink $detail atlas max V
// TEXCOORD4
//   x : Ink shape mask atlas min U
//   y : Ink shape mask atlas min V
//   z : Ink shape mask atlas max U
//   w : Ink shape mask atlas max V
// TEXCOORD5
//   x : Surface min U
//   y : Surface min V
//   z : Surface max U
//   w : Surface max V
// TEXCOORD6
//   xyz : WorldToUV matrix rotation (first row)
//   w   : WorldToUV matrix offset U
// TEXCOORD7
//   xyz : WorldToUV matrix rotation (second row)
//   w   : WorldToUV matrix offset V
// TANGENT0
//   x : Width
//   y : Height
//   z : Depth scale
// BINORMAL0
//   r : Normalized paint time
//   g : x16 = 0bRRCC = Region and corner index
//   b : x255 + 1 = Paint type ID
//   a : Unused

const float4 c21 : register(c21); // Ambient cube front
static const float  HammerUnitsToMaxHeight = rcp(32.0);
static const float  CornerSignX[4] = { -1,  1, 1, -1 };
static const float  CornerSignY[4] = { -1, -1, 1,  1 };
static const float2 ConstantUV[4]  = {{ 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 }};
static const float2 RegionOffset[4] = {
    { 0.0, 0.0 }, { 0.0, 0.5 }, { 0.5, 0.0 }, { 0.5, 0.5 }
};

struct VS_INPUT {
    float3   worldPos                : POSITION0;
    float4   worldAngles             : TEXCOORD0;
    float4   baseTextureAtlasRange   : TEXCOORD1;
    float4   tintTextureAtlasRange   : TEXCOORD2;
    float4   detailTextureAtlasRange : TEXCOORD3;
    float4   shapeMaskAtlasRange     : TEXCOORD4;
    float4   surfaceClipRange        : TEXCOORD5;
    float4x2 worldToUV               : TEXCOORD6;
    float4   size                    : NORMAL0;
    float4   timeIndexType           : COLOR0;
};

struct VS_OUTPUT {
    float4 pos                  : POSITION;
    float4 inkAndTintUV         : TEXCOORD0;
    float4 detailAndShapeUV     : TEXCOORD1;
    float4 surfaceClipRange     : TEXCOORD2;
    float4 typeRegionTimeZScale : TEXCOORD3;
};

#define time            v.timeIndexType.x
#define regionIndex int(v.timeIndexType.y * 4)
#define cornerIndex int(fmod(v.timeIndexType.y * 16, 4))
#define inkType   floor(v.timeIndexType.z * 255)
#define HammerUnitsToUV v.worldAngles.w
VS_OUTPUT main(const VS_INPUT v) {
    float3 sine, cosine;
    sincos(radians(v.worldAngles.xyz), sine, cosine);

    float3 worldForward = { cosine.x * cosine.y, cosine.x * sine.y, -sine.x };
    float2 basisV = normalize(mul(float4(worldForward, 0.0), v.worldToUV)).yx;
    float2 basisU = { basisV.y, -basisV.x };

    // Flip U and V to match handedness to the world coordinate system
    float2 uvPos = mul(float4(v.worldPos, 1.0), v.worldToUV).yx;
    uvPos += basisU * v.size.x * CornerSignX[cornerIndex];
    uvPos += basisV * v.size.y * CornerSignY[cornerIndex];
    uvPos *= HammerUnitsToUV;

    // Convert position to local to specific region
    uvPos *= 0.5;
    uvPos += RegionOffset[regionIndex].yx;

    VS_OUTPUT output;
    float2 baseMin   = v.baseTextureAtlasRange.xy;
    float2 baseMax   = v.baseTextureAtlasRange.zw;
    float2 tintMin   = v.tintTextureAtlasRange.xy;
    float2 tintMax   = v.tintTextureAtlasRange.zw;
    float2 detailMin = v.detailTextureAtlasRange.xy;
    float2 detailMax = v.detailTextureAtlasRange.zw;
    float2 shapeMin  = v.shapeMaskAtlasRange.xy;
    float2 shapeMax  = v.shapeMaskAtlasRange.zw;
    float2 corner    = ConstantUV[cornerIndex];
    float  zScale    = saturate(v.size.z * HammerUnitsToMaxHeight);
    output.inkAndTintUV = float4(
        lerp(baseMin, baseMax, corner),
        lerp(tintMin, tintMax, corner));
    output.detailAndShapeUV = float4(
        lerp(detailMin, detailMax, corner),
        lerp(shapeMin,  shapeMax,  corner));
    output.surfaceClipRange
        = v.surfaceClipRange.yxwz * 0.5 + RegionOffset[regionIndex].yxyx;
    output.typeRegionTimeZScale = float4(inkType, regionIndex, time, zScale);
    output.pos = float4(uvPos * 2.0 - 1.0, time, 1.0);
    output.pos.y *= -1.0;
    return output;
}
