
#include "inkmesh_common.hlsl"

sampler InkMap             : register(s0);
sampler InkDataDetail      : register(s1);
sampler BaseTextureAtlas   : register(s2);
sampler TintTextureAtlas   : register(s3);
const float2 RcpRTSize     : register(c4); // One over render target size
const float2 RcpDataRTSize : register(c5);

struct PS_INPUT {
    float2 screenPos            : VPOS;
    float4 inkAndTintUV         : TEXCOORD0;
    float3 shapeUVDetailPacked  : TEXCOORD1;
    float4 surfaceClipRange     : TEXCOORD2;
    float4 typeRegionTimeZScale : TEXCOORD3;
    float4 detailStamp          : TEXCOORD4;
};

struct PS_OUTPUT {
    float4 color : COLOR0;
    float  depth : DEPTH0;
};

// Ink state of the texel before painting
struct OldInk {
    float height; // ranging from -1 to +1
    float depth;  // ranging from 0 to 1
    int   index;  // surface index of the upper layer
};

struct PsInputBundle {
    PS_INPUT i;
    OldInk old;
};

static const float eps = 5e-3;

// Shape masks are signed distance fields with the edge at 0.5, toward 1 inside.
// The server-side paint detection in inkshape.lua binarizes them by the same value.
static const float SHAPE_MASK_EDGE = 0.5;
#define NODIG      miscParam.w >= 0.5             // w * 255 = 0bNHL0 0000, N = $nodig,
#define HEIGHTONLY frac(miscParam.w * 2.0) >= 0.5 // H = $heightonly, L = $detaillocal (see IsDetailLocal)
#define paintType  i.i.typeRegionTimeZScale.x
#define regionID   i.i.typeRegionTimeZScale.y
#define time       i.i.typeRegionTimeZScale.z
#define zScale     i.i.typeRegionTimeZScale.w
#define inkMapUV   ((i.i.screenPos + float2(0.5, 0.5)) * RcpRTSize)

// Ink map UV of the texel being painted, moved to the given region
#define INKMAP_UV_AT(region) float4(inkMapUV - floor(inkMapUV * 2.0) * 0.5 + (region), 0.0, 0.0)

int GetSurfaceIndex(float4 indexSample) {
    return int(lerp(indexSample.r, indexSample.g, ceil(indexSample.b)) * 255);
}

void FetchOldInk(inout PsInputBundle i) {
    float4 heightDepth = tex2Dlod(InkMap, INKMAP_UV_AT(INKMAP_HEIGHT_DEPTH));
    float4 indices     = tex2Dlod(InkMap, INKMAP_UV_AT(INKMAP_INDICES));
    i.old.height = TO_SIGNED(DecodeUnorm16(heightDepth.rg));
    i.old.depth  = DecodeUnorm16(heightDepth.ba);
    i.old.index  = GetSurfaceIndex(indices);
}

// Quantity that CalculateHeight computes as newHeight
static const int HEIGHT_TARGET_HEIGHT   = 0; // height value ranging from -1 to +1
static const int HEIGHT_TARGET_DEPTH    = 1; // negated depth value ranging from -1 to 0
static const int HEIGHT_TARGET_STRENGTH = 2; // height value, used only for paintStrength
float2 CalculateHeight(const PsInputBundle i, int target, float heightSample,
    float shapeMask, float4 heightParam, float geometryPaintBias, float nodig, float flatten) {

    // Height map blend parameters
    float maxHeight      = heightParam.y;
    float heightBaseline = heightParam.w;
    float heightScale    = TO_SIGNED(heightParam.z);
    heightScale *= step(5.0e-3, abs(heightScale)) * zScale;

    // Shape strength scales the complete change, before viscosity divides digging between layers.
    float shapeStrength = saturate((shapeMask - SHAPE_MASK_EDGE) / (1.0 - SHAPE_MASK_EDGE));
    float paintDir      = heightScale >= 0.0 ? 1.0 : -1.0;
    float paintHeight   = heightSample * heightScale; // -1.0 -- +1.0
    float paintDetail   = paintHeight - heightBaseline * heightScale;
    float oldPixelValue = target == HEIGHT_TARGET_DEPTH ? -i.old.depth : i.old.height;

    // Height map blend calculation
    // Height and ground depth must divide the same request between fluid and solid.
    float oldHeightSaturated = saturate(
        paintDir * (i.old.height + (target == HEIGHT_TARGET_STRENGTH ? 0.0 : i.old.depth)));
    float baselineFalloff = exp(-max(oldHeightSaturated, 1.0e-6) / max(maxHeight, 1.0e-12));
    baselineFalloff *= 1 - oldHeightSaturated;
    float baselineAdd   = paintHeight * baselineFalloff;
    float detailFalloff = oldHeightSaturated * oldHeightSaturated;
    detailFalloff *= detailFalloff;
    detailFalloff *= detailFalloff;
    detailFalloff *= detailFalloff;
    float detailAdd     = paintDetail * (1 - detailFalloff);
    float desiredAdd    = (baselineAdd + detailAdd) * shapeStrength;
    float paintStrength = 1.0 - geometryPaintBias;
    float newHeight     = oldPixelValue + desiredAdd;

    // Digging
    if (desiredAdd < 0.0) {
        desiredAdd = abs(desiredAdd);

        // Applying viscosity of the fluid on top of the ground
        float oldThickness = max(0.0, i.old.height + i.old.depth);
        float viscosity = FetchDataPixel(InkDataDetail, i.old.index, ID_MISC).z;
        float fluidDigAmount = min(desiredAdd * viscosity, oldThickness);
        float solidDigAmount = desiredAdd - fluidDigAmount;
        newHeight = oldPixelValue;
        newHeight -= solidDigAmount;
        newHeight -= fluidDigAmount * (target == HEIGHT_TARGET_DEPTH ? 0 : 1);
        // No-dig stops at the existing ground, including inside an already dug area.
        float minimumHeight = lerp(-1.0, -i.old.depth, nodig);
        newHeight = max(minimumHeight, lerp(newHeight, 0.0, flatten * shapeStrength));
        paintStrength = saturate(1 - nodig - geometryPaintBias
            * step(-i.old.height + fluidDigAmount + solidDigAmount, i.old.depth + eps));
    }

    return float2(paintStrength, newHeight);
}

// Phase that places the center of the detail image at the splash center, zero unless $detaillocal.
// Drawing adds it to the image position it rebuilds from the same UV frame, see DetailImagePosition.
float2 DetailPhase(const PsInputBundle i, float4 miscParam) {
    if (!IsDetailLocal(miscParam)) return 0.0;
    DetailTransform transform = DecodeDetailTransform(
        FetchDataPixel(InkDataDetail, paintType, ID_DETAIL_TRANSFORM),
        FetchDataPixel(InkDataDetail, paintType, ID_DETAIL_SCALE));
    return frac(0.5 + transform.translation
        - DetailImagePosition(i.i.detailStamp.xy, i.i.detailStamp.zw, transform));
}

// Whether this paint takes over the upper layer, which PaintIndices decides with its own
// paintStrength. The phases and the ink type IDs come from the same paint as long as they agree.
#define WRITES_UPPER_LAYER (!(HEIGHTONLY) && paintStrength >= eps)

PS_OUTPUT Additive(const PsInputBundle i, float t, float shapeMask) {
    float4 add          = tex2D(BaseTextureAtlas, i.i.inkAndTintUV.xy);
    float4 tint         = tex2D(TintTextureAtlas, i.i.inkAndTintUV.zw);
    float4 old          = tex2D(InkMap, inkMapUV);
    float4 colorAlpha   = FetchDataPixel(InkDataDetail, paintType, ID_COLOR_ALPHA);
    float4 tintParam    = FetchDataPixel(InkDataDetail, paintType, ID_TINT_GEOMETRYPAINT);
    float4 heightParam  = FetchDataPixel(InkDataDetail, paintType, ID_HEIGHT_MAXLAYERS);
    float4 miscParam    = FetchDataPixel(InkDataDetail, paintType, ID_MISC);
    float  geometryBias = tintParam.w;
    float  flatten      = miscParam.y;
    float  nodig        = NODIG;
    float paintStrength = CalculateHeight(i,
        HEIGHT_TARGET_HEIGHT, add.a, shapeMask, heightParam, geometryBias, nodig, flatten).x;

    // Basic tint by $color, $tintcolor, and $alpha
    add.rgb *= colorAlpha.rgb * paintStrength;
    tint.rgb *= (1.0 - colorAlpha.aaa) * tintParam.rgb;
    tint.rgb = lerp(1.0, tint.rgb, paintStrength);
    tint.rgb = saturate(tint.rgb);
    float erase      = miscParam.x;
    float maxLayers  = floor(heightParam.x * 255);
    float3 tintLimit = pow(tint.rgb, maxLayers);
    float3 tintFade  = smoothstep(tintLimit, tintLimit + 0.0625, distance(old.rgb, add.rgb));
    float3 newColor  = old.rgb * lerp(1.0, tint.rgb, tintFade) + add.rgb * colorAlpha.aaa * tintFade;
    float  phaseU    = WRITES_UPPER_LAYER ? DetailPhase(i, miscParam).x : old.a;
    PS_OUTPUT output = { newColor * (1.0 - erase), phaseU, t };
    return output;
}

PS_OUTPUT Multiplicative(const PsInputBundle i, float t, float shapeMask) {
    float4 add         = tex2D(BaseTextureAtlas, i.i.inkAndTintUV.xy);
    float4 tint        = tex2D(TintTextureAtlas, i.i.inkAndTintUV.zw);
    float4 old         = tex2D(InkMap, inkMapUV);
    float4 colorAlpha  = FetchDataPixel(InkDataDetail, paintType, ID_COLOR_ALPHA);
    float4 tintParam   = FetchDataPixel(InkDataDetail, paintType, ID_TINT_GEOMETRYPAINT);
    float4 heightParam = FetchDataPixel(InkDataDetail, paintType, ID_HEIGHT_MAXLAYERS);
    float4 miscParam   = FetchDataPixel(InkDataDetail, paintType, ID_MISC);
    float geometryBias = tintParam.w;
    float flatten      = miscParam.y;
    float nodig        = NODIG;

    float paintStrength = CalculateHeight(i, HEIGHT_TARGET_DEPTH,
        add.a, shapeMask, heightParam, geometryBias, nodig, flatten).x;

    // Do not darken more than maxLayers times
    // But if current one is already darker than that, keep it
    tint.rgb *= (1.0 - colorAlpha.aaa) * tintParam.rgb;
    tint.rgb = lerp(1.0, tint.rgb, paintStrength);
    tint.rgb = saturate(tint.rgb);
    float erase        = miscParam.x;
    float maxLayers    = floor(heightParam.x * 255);
    float3 tintClipped = max(old.rgb * tint.rgb, pow(tint.rgb, maxLayers));
    float3 tintFinal   = lerp(min(tintClipped, old.rgb), 1.0, erase);
    float  phaseV      = WRITES_UPPER_LAYER ? DetailPhase(i, miscParam).y : old.a;
    // Ordered by paint time as the other regions are, so that one paint owns the whole upper layer.
    PS_OUTPUT output   = { tintFinal, phaseV, t };
    return output;
}

PS_OUTPUT HeightAndDepth(const PsInputBundle i, float t, float shapeMask) {
    float4 add          = tex2D(BaseTextureAtlas, i.i.inkAndTintUV.xy);
    float4 tintParam    = FetchDataPixel(InkDataDetail, paintType, ID_TINT_GEOMETRYPAINT);
    float4 heightParam  = FetchDataPixel(InkDataDetail, paintType, ID_HEIGHT_MAXLAYERS);
    float4 miscParam    = FetchDataPixel(InkDataDetail, paintType, ID_MISC);
    float  geometryBias = tintParam.w;
    float  flatten      = miscParam.y;
    float  nodig        = NODIG;

    float newHeight = CalculateHeight(i,
        HEIGHT_TARGET_HEIGHT, add.a, shapeMask, heightParam, geometryBias, nodig, flatten).y;
    float newDepth = -CalculateHeight(i,
        HEIGHT_TARGET_DEPTH, add.a, shapeMask, heightParam, geometryBias, nodig, flatten).y;
    PS_OUTPUT output = {
        EncodeUnorm16(TO_UNSIGNED(newHeight)),
        EncodeUnorm16(max(newDepth, i.old.depth)),
        t,
    };
    return output;
}

PS_OUTPUT PaintIndices(const PsInputBundle i, float t, float shapeMask) {
    float4 old          = tex2D(InkMap, inkMapUV);
    float4 miscParam    = FetchDataPixel(InkDataDetail, paintType, ID_MISC);
    PS_OUTPUT output = { old, t };
    if (max(old.r, max(old.g, old.b)) < 1.0 / 255.0) output.color.b = 1.0;
    if (HEIGHTONLY) return output;

    float4 add          = tex2D(BaseTextureAtlas, i.i.inkAndTintUV.xy);
    float4 tint         = tex2D(TintTextureAtlas, i.i.inkAndTintUV.zw);
    float4 tintParam    = FetchDataPixel(InkDataDetail, paintType, ID_TINT_GEOMETRYPAINT);
    float4 heightParam  = FetchDataPixel(InkDataDetail, paintType, ID_HEIGHT_MAXLAYERS);
    float  geometryBias = tintParam.w;
    float  flatten      = miscParam.y;
    float  nodig        = NODIG;

    float2 h = CalculateHeight(i, HEIGHT_TARGET_STRENGTH,
        add.a, shapeMask, heightParam, geometryBias, nodig, flatten);
    float paintStrength = h.x;
    float newHeight     = h.y;
    if (paintStrength < eps) return output;

    float4 colorAlpha   = FetchDataPixel(InkDataDetail, paintType, ID_COLOR_ALPHA);
    tint.rgb *= (1.0 - colorAlpha.aaa) * tintParam.rgb;
    tint.rgb = lerp(1.0, tint.rgb, paintStrength);
    float thisID        = paintType / 255.0;
    float translucency  = dot(tint.rgb, GrayScaleFactor);
    bool  isOpaque      = translucency < eps;
    output.color = float4(
        isOpaque ? thisID : old.r,
        isOpaque ? 0.0    : thisID, // Opaque paint replaces the upper layer.
        isOpaque ? 0.0    : 1.0 - translucency * (1.0 - output.color.b),
        i.i.shapeUVDetailPacked.z); // Detail mode and rotation of the upper layer
    return output;
}

PS_OUTPUT main(const PS_INPUT raw) {
    PsInputBundle i = { raw, (OldInk)0 };
    float2 surfaceClipRangeMin = i.i.surfaceClipRange.xy;
    float2 surfaceClipRangeMax = i.i.surfaceClipRange.zw;
    clip(step(float4(surfaceClipRangeMin, inkMapUV), float4(inkMapUV, surfaceClipRangeMax)) - 0.5);

    float4 shapeMask = tex2D(TintTextureAtlas, i.i.shapeUVDetailPacked.xy);
    clip(shapeMask.a < SHAPE_MASK_EDGE ? -1.0 : 1.0);

    FetchOldInk(i);
    if (floor(regionID) == 0)
        return Additive(i, time, shapeMask.a);
    else if (floor(regionID) == 1)
        return Multiplicative(i, time, shapeMask.a);
    else if (floor(regionID) == 2)
        return PaintIndices(i, time, shapeMask.a);
    else
        return HeightAndDepth(i, time, shapeMask.a);
}
