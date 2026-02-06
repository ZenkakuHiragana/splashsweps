
// POSITION0
//   xyz : The world position of the splash
//   w   : Paint type ID
// TEXCOORD0
//   xyz : The world angle of the splash (x, y, z = pitch, yaw roll)
//   w   : Opacity for this paint type (0 -> transparent, 1 -> fully opaque)
// TEXCOORD1
//   x : Ink texture atlas min U
//   y : Ink texture atlas min V
//   z : Ink texture atlas max U
//   w : Ink texture atlas max V
// TEXCOORD2
//   x : Ink shape mask atlas min U
//   y : Ink shape mask atlas min V
//   z : Ink shape mask atlas max U
//   w : Ink shape mask atlas max V
// TEXCOORD3
//   x : surface min U
//   y : surface min V
//   z : surface max U
//   w : surface max V
// TEXCOORD4
//   x : width
//   y : height
//   z : region index (0, 1, 2, 3)
//   w : corner index (0, 1, 2, 3)
// TEXCOORD5
//   x : Earliest time in batch
//   y : Latest time in batch
//   z : Time of this splash
//   w : Unused
// TEXCOORD6 -- TEXCOORD7 WorldToUV matrix

// HammerUnitsToPixels goes to pixel shader constant

static const float  CornerSignX[4] = { -1,  1, 1, -1 };
static const float  CornerSignY[4] = { -1, -1, 1,  1 };
static const float2 ConstantUV[4]  = {{ 0, 0 }, { 0, 1 }, { 1, 1 }, { 1, 0 }};
static const float2 RegionOffset[4] = {
    { 0.0, 0.0 }, { 0.0, 0.5 }, { 0.5, 0.0 }, { 0.5, 0.5 }
};

struct VS_INPUT {
    float4   worldPosPaintType        : POSITION0;
    float4   worldAnglesOpacity       : TEXCOORD0;
    float4   inkTextureAtlasRange     : TEXCOORD1;
    float4   shapeMaskAtlasRange      : TEXCOORD2;
    float4   surfaceClipRange         : TEXCOORD3;
    float4   sizeAndRegionCornerIndex : TEXCOORD4;
    float4   timesAndPaintType        : TEXCOORD5;
    float4x2 worldToUV                : TEXCOORD6;
};

struct VS_OUTPUT {
    float4 pos                   : POSITION;
    float4 inkUV_shapeUV         : TEXCOORD0;
    float4 surfaceClipRange      : TEXCOORD1;
    float4 timeRegionTypeOpacity : TEXCOORD2;
};

#define curTime v.timesAndPaintType.x
#define maxTime v.timesAndPaintType.y
#define minTime v.timesAndPaintType.z
VS_OUTPUT main(const VS_INPUT v) {
    float3 sine, cosine;
    sincos(radians(v.worldAnglesOpacity.xyz), sine, cosine);
    float3 worldForward = { cosine.x * cosine.y, cosine.x * sine.y, -sine.x };
    float2 basisU = normalize(mul(float4(worldForward, 0.0), v.worldToUV));
    float2 basisV = { -basisU.y, basisU.x };

    float timeFraction = saturate((curTime - minTime) / (maxTime - minTime));
    float2 uvPos = mul(float4(v.worldPosPaintType.xyz, 1.0), v.worldToUV);
    float2 size = v.sizeAndRegionCornerIndex.xy;
    int cornerIndex = int(v.sizeAndRegionCornerIndex.w);
    int regionIndex = int(v.sizeAndRegionCornerIndex.z);
    uvPos += basisU * size.x * CornerSignX[cornerIndex];
    uvPos += basisV * size.y * CornerSignY[cornerIndex];

    // Convert position to local to specific region
    uvPos *= 0.5;
    uvPos += RegionOffset[regionIndex];

    VS_OUTPUT output;
    float2 inkTextureMinUV = v.inkTextureAtlasRange.xy;
    float2 inkTextureMaxUV = v.inkTextureAtlasRange.zw;
    float2 shapeMaskMinUV = v.shapeMaskAtlasRange.xy;
    float2 shapeMaskMaxUV = v.shapeMaskAtlasRange.zw;
    output.pos = float4(uvPos * 2.0 - 1.0, timeFraction, 1.0);
    output.pos.y *= -1.0;
    output.inkUV_shapeUV = float4(
        lerp(inkTextureMinUV, inkTextureMaxUV, ConstantUV[cornerIndex]),
        lerp(shapeMaskMinUV, shapeMaskMaxUV, ConstantUV[cornerIndex]));
    output.surfaceClipRange
        = v.surfaceClipRange * 0.5 + RegionOffset[regionIndex].xyxy;
    output.timeRegionTypeOpacity = float4(
        timeFraction,
        regionIndex,
        v.worldPosPaintType.w,
        v.worldAnglesOpacity.w);
    return output;
}
