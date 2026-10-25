
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
    float4 shapeUVAndDetail     : TEXCOORD1;
    float4 surfaceClipRange     : TEXCOORD2;
    float4 typeRegionBandZScale : TEXCOORD3;
    float4 paintPlacement       : TEXCOORD4;
    float2 shapeDistanceScale   : TEXCOORD5; // x: HU per shape mask alpha unit, y: Hammer units to UV
};

struct PS_OUTPUT {
    float4 color : COLOR0;
};

// Batch-start snapshot: the sampler reads InkMapSnapshot, copied once before the queue is drawn.
struct OldInk {
    float height; // ranging from -1 to +1
    float depth;  // ranging from 0 to 1
    int   index;  // surface index of the upper layer
};

struct PsInputBundle {
    PS_INPUT i;
    OldInk old;
};

// Values written to the alpha channels of the additive, multiplicative, and index regions.
struct InkMapDetailWrite {
    float2 phaseUV;            // Phase in periods; UNORM8 stores code / 255, with 0 and 1 coincident.
    float  modeRotationUNorm;  // (5-bit paint angle * 8 + 3-bit mode) / 255.
};

// Shape mask contract:
//   alpha = 0.5 + (signed distance to the edge in mask pixels, positive inside) / (mask width in pixels),
// correct over the whole mask. Outside the shape, the mask keeps its own margin.
// The server-side paint detection binarizes the masks at the same edge value.
static const float SHAPE_MASK_EDGE = 0.5;
static const float eps = 5e-3;

#define NODIG       (miscParam.w >= 0.5)              // w * 255 = 0bNHL0 0000
#define HEIGHTONLY  (frac(miscParam.w * 2.0) >= 0.5)  // N = $nodig, H = $heightonly
#define DETAILLOCAL (frac(miscParam.w * 4.0) >= 0.5)  // L = $detaillocal
#define paintType  i.i.typeRegionBandZScale.x
#define regionID   i.i.typeRegionBandZScale.y
#define isBand     (i.i.typeRegionBandZScale.z > 0.5) // Boundary band outside the shape edge
#define zScale     i.i.typeRegionBandZScale.w
#define inkMapUV   ((i.i.screenPos + float2(0.5, 0.5)) * RcpRTSize)

// A region of the ink map is half the render target, and one UV unit spans a region.
#define TEXELS_PER_HU (i.i.shapeDistanceScale.y * 0.5 / RcpRTSize.x)

// Ink map UV of the texel being painted, moved to the given region
#define INKMAP_UV_AT(region) float4(inkMapUV - floor(inkMapUV * 2.0) * 0.5 + (region), 0.0, 0.0)

int GetSurfaceIndex(float4 indexSample) {
    float upperBlend = DecodeIndicesDistanceBlend(indexSample.b).y;
    return int(lerp(indexSample.r, indexSample.g, ceil(upperBlend)) * 255);
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
    float edgeDistanceHU, float4 heightParam, float geometryPaintBias, float nodig, float flatten) {

    // Height map blend parameters
    float maxHeight      = heightParam.y;
    float heightBaseline = heightParam.w;
    float heightScale    = TO_SIGNED(heightParam.z);
    heightScale *= step(5.0e-3, abs(heightScale)) * zScale;

    // Shape strength scales the complete change, before viscosity divides digging between layers.
    // It rises over the film thickness from the edge, as a 45-degree contact angle does,
    // and over one ink map texel at least, so that the height has no step at the edge.
    float riseWidthHU   = max(abs(heightScale) * HEIGHT_TO_HU, 1.0 / TEXELS_PER_HU);
    float shapeStrength = saturate(edgeDistanceHU / riseWidthHU);
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
        float viscosity = FetchDataPixel(InkDataDetail, i.old.index, ID_VISCOSITY).a;
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

// All three detail bytes follow the same adoption test as the upper material.
float MaterialAdoptionStrength(const PsInputBundle i,
    float heightSample, float edgeDistanceHU, float4 heightParam, float geometryBias, float4 miscParam) {
    if (HEIGHTONLY) return 0.0;
    return CalculateHeight(i, HEIGHT_TARGET_STRENGTH,
        heightSample, edgeDistanceHU, heightParam, geometryBias, NODIG, miscParam.y).x;
}

// Construct the center phase with the same quantized transform used by the display shader.
InkMapDetailWrite EncodeDetailPlacement(const PsInputBundle i, float4 miscParam) {
    float modeUNorm = i.i.shapeUVAndDetail.z;
    InkMapDetailWrite encoded = { float2(0.0, 0.0), modeUNorm };
    if (modeUNorm == 0.0 || !DETAILLOCAL) return encoded;

    float4 encodedTransform   = FetchDataPixel(InkDataDetail, paintType, ID_DETAIL_TRANSFORM);
    float2 repeatsPerHULog    = FetchDataPixel(InkDataDetail, paintType, ID_DETAIL_SCALE).xy;
    float2 repeatsPerHU       = exp2(repeatsPerHULog * (255.0 / 24.0) - 13.0);
    float  paintRotationCode5 = i.i.shapeUVAndDetail.w;
    float2 inkMapCenterHU     = i.i.paintPlacement.xy;
    float2 mapToPaintCosSin   = i.i.paintPlacement.zw;
    float2 paintCenterHU = float2(
        mapToPaintCosSin.x * inkMapCenterHU.x - mapToPaintCosSin.y * inkMapCenterHU.y,
        mapToPaintCosSin.y * inkMapCenterHU.x + mapToPaintCosSin.x * inkMapCenterHU.y);
    float2 scaledCenterUV = paintCenterHU * repeatsPerHU;
    float2 materialCosSin = encodedTransform.zw * (255.0 / 127.0) - 1.0;
    float2 detailUVAtCenter = float2(
        materialCosSin.x * scaledCenterUV.x - materialCosSin.y * scaledCenterUV.y,
        materialCosSin.y * scaledCenterUV.x + materialCosSin.x * scaledCenterUV.y);

    // Material translation is added at display time: zero translation puts image UV 0.5 at the hit.
    encoded.phaseUV = frac(0.5 - detailUVAtCenter);
    encoded.modeRotationUNorm = (paintRotationCode5 * 8.0 + round(modeUNorm * 255.0)) / 255.0;
    return encoded;
}

PS_OUTPUT Additive(const PsInputBundle i, float edgeDistanceHU) {
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
        HEIGHT_TARGET_HEIGHT, add.a, edgeDistanceHU, heightParam, geometryBias, nodig, flatten).x;

    float phase = old.a;
    if (MaterialAdoptionStrength(i, add.a, edgeDistanceHU, heightParam, geometryBias, miscParam) >= eps)
        phase = EncodeDetailPlacement(i, miscParam).phaseUV.x;

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
    PS_OUTPUT output = { newColor * (1.0 - erase), phase };
    return output;
}

PS_OUTPUT Multiplicative(const PsInputBundle i, float edgeDistanceHU) {
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
        add.a, edgeDistanceHU, heightParam, geometryBias, nodig, flatten).x;
    float phase = old.a;
    if (MaterialAdoptionStrength(i, add.a, edgeDistanceHU, heightParam, geometryBias, miscParam) >= eps)
        phase = EncodeDetailPlacement(i, miscParam).phaseUV.y;

    // Do not darken more than maxLayers times
    // But if current one is already darker than that, keep it
    tint.rgb *= (1.0 - colorAlpha.aaa) * tintParam.rgb;
    tint.rgb = lerp(1.0, tint.rgb, paintStrength);
    tint.rgb = saturate(tint.rgb);
    float erase        = miscParam.x;
    float maxLayers    = floor(heightParam.x * 255);
    float3 tintClipped = max(old.rgb * tint.rgb, pow(tint.rgb, maxLayers));
    float3 tintFinal   = lerp(min(tintClipped, old.rgb), 1.0, erase);
    // Match indices/additive ordering so that the V phase belongs to the same paint.
    PS_OUTPUT output   = { tintFinal, phase };
    return output;
}

PS_OUTPUT HeightAndDepth(const PsInputBundle i, float edgeDistanceHU) {
    float4 add          = tex2D(BaseTextureAtlas, i.i.inkAndTintUV.xy);
    float4 tintParam    = FetchDataPixel(InkDataDetail, paintType, ID_TINT_GEOMETRYPAINT);
    float4 heightParam  = FetchDataPixel(InkDataDetail, paintType, ID_HEIGHT_MAXLAYERS);
    float4 miscParam    = FetchDataPixel(InkDataDetail, paintType, ID_MISC);
    float  geometryBias = tintParam.w;
    float  flatten      = miscParam.y;
    float  nodig        = NODIG;

    float newHeight = CalculateHeight(i, HEIGHT_TARGET_HEIGHT,
        add.a, edgeDistanceHU, heightParam, geometryBias, nodig, flatten).y;
    float newDepth = -CalculateHeight(i, HEIGHT_TARGET_DEPTH,
        add.a, edgeDistanceHU, heightParam, geometryBias, nodig, flatten).y;
    PS_OUTPUT output = {
        EncodeUnorm16(TO_UNSIGNED(newHeight)),
        EncodeUnorm16(max(newDepth, i.old.depth)),
    };
    return output;
}

// Inside the shape, the paint writes the region it makes: its IDs, blend, and the distance to its edge.
// In the band outside the edge, it keeps the IDs and only shortens the distance of other regions,
// as its edge has become their boundary there. The band is drawn before every inside of the batch.
// Every quad of a batch reads the same snapshot, so where two bands of a batch overlap,
// the later band's distance remains instead of the nearer one.
PS_OUTPUT PaintIndices(const PsInputBundle i, float edgeDistanceHU, float edgeDistanceTexels) {
    float4 old       = tex2D(InkMap, inkMapUV);
    float4 miscParam = FetchDataPixel(InkDataDetail, paintType, ID_MISC);
    float2 oldDistanceBlend = DecodeIndicesDistanceBlend(old.b);
    float  oldDistance      = oldDistanceBlend.x;
    float  oldBlend         = oldDistanceBlend.y;
    PS_OUTPUT output = { old };

    // An empty texel gets the full upper blend, so that paint without a material still shows its volume.
    if (!isBand && !IsIndicesPainted(old)) {
        oldBlend = 1.0;
        output.color.b = EncodeIndicesDistanceBlend(oldDistance, INDICES_CODE_MAX);
    }
    if (HEIGHTONLY) return output;

    float4 add          = tex2D(BaseTextureAtlas, i.i.inkAndTintUV.xy);
    float4 tint         = tex2D(TintTextureAtlas, i.i.inkAndTintUV.zw);
    float4 tintParam    = FetchDataPixel(InkDataDetail, paintType, ID_TINT_GEOMETRYPAINT);
    float4 heightParam  = FetchDataPixel(InkDataDetail, paintType, ID_HEIGHT_MAXLAYERS);
    float  geometryBias = tintParam.w;
    float adoptionStrength = MaterialAdoptionStrength(
        i, add.a, edgeDistanceHU, heightParam, geometryBias, miscParam);
    if (adoptionStrength < eps) return output;

    float4 colorAlpha   = FetchDataPixel(InkDataDetail, paintType, ID_COLOR_ALPHA);
    tint.rgb *= (1.0 - colorAlpha.aaa) * tintParam.rgb;
    tint.rgb = lerp(1.0, tint.rgb, adoptionStrength);
    float translucency  = dot(tint.rgb, GrayScaleFactor);
    bool  isOpaque      = translucency < eps;

    // Opaque paint makes the region (this, none), and translucent paint makes (old lower, this).
    float oldLowerID   = round(old.r * 255.0);
    float oldUpperID   = round(old.g * 255.0);
    bool  isSameRegion = isOpaque ? oldLowerID == paintType && oldUpperID == 0.0 : oldUpperID == paintType;
    float oldBlendCode = round(oldBlend * INDICES_CODE_MAX);
    if (isBand) {
        float distance = isSameRegion ? oldDistance : min(oldDistance, -edgeDistanceTexels);
        output.color.b = EncodeIndicesDistanceBlend(distance, oldBlendCode);
        return output;
    }

    // The union with the same region reaches its boundary no closer than either part does.
    float distance = max(edgeDistanceTexels, isSameRegion ? oldDistance : 0.0);
    // Floor the share left to the lower layer, so that every translucent layer advances the blend.
    float lowerShareCode = floor(translucency * (1.0 - oldBlend) * INDICES_CODE_MAX + 1.0e-3);
    float detailEncoded  = EncodeDetailPlacement(i, miscParam).modeRotationUNorm;
    output.color = float4(
        isOpaque ? paintType / 255.0 : old.r,
        isOpaque ? 0.0 : paintType / 255.0, // Opaque paint replaces the upper layer.
        EncodeIndicesDistanceBlend(distance, isOpaque ? 0.0 : INDICES_CODE_MAX - lowerShareCode),
        detailEncoded); // Upper detail mode and quantized paint rotation
    return output;
}

PS_OUTPUT main(const PS_INPUT raw) {
    PsInputBundle i = { raw, (OldInk)0 };
    float2 surfaceClipRangeMin = i.i.surfaceClipRange.xy;
    float2 surfaceClipRangeMax = i.i.surfaceClipRange.zw;
    clip(step(float4(surfaceClipRangeMin, inkMapUV), float4(inkMapUV, surfaceClipRangeMax)) - 0.5);

    // Signed distance to the shape edge, positive inside
    float shapeAlpha         = tex2D(TintTextureAtlas, i.i.shapeUVAndDetail.xy).a;
    float edgeDistanceHU     = (shapeAlpha - SHAPE_MASK_EDGE) * i.i.shapeDistanceScale.x;
    float edgeDistanceTexels = edgeDistanceHU * TEXELS_PER_HU;
    // The band quad keeps the texels outside the edge within one texel, and the others the inside.
    clip(isBand ? min(-edgeDistanceTexels, edgeDistanceTexels + 1.0) : edgeDistanceTexels);

    FetchOldInk(i);
    if (floor(regionID) == 0)
        return Additive(i, edgeDistanceHU);
    else if (floor(regionID) == 1)
        return Multiplicative(i, edgeDistanceHU);
    else if (floor(regionID) == 2)
        return PaintIndices(i, edgeDistanceHU, edgeDistanceTexels);
    else
        return HeightAndDepth(i, edgeDistanceHU);
}
