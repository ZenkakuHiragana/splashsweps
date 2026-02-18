
#include "inkmesh_common.hlsl"

sampler InkMap             : register(s0);
sampler DataSampler        : register(s1);
sampler BaseTextureAtlas   : register(s2);
sampler TintTextureAtlas   : register(s3);
const float2 RcpRTSize     : register(c4); // One over render target size
const float2 RcpDataRTSize : register(c5);

struct PS_INPUT {
    float2 screenPos            : VPOS;
    float4 inkAndTintUV         : TEXCOORD0;
    float4 detailAndShapeUV     : TEXCOORD1;
    float4 surfaceClipRange     : TEXCOORD2;
    float4 typeRegionTimeZScale : TEXCOORD3;
};

struct PS_OUTPUT {
    float4 color : COLOR0;
    float  depth : DEPTH0;
};

static const float eps = 5e-3;
#define NODIG     abs(0.5 - miscParam.w) < eps ? 1.0 : 0.0
#define paintType i.typeRegionTimeZScale.x
#define regionID  i.typeRegionTimeZScale.y
#define time      i.typeRegionTimeZScale.z
#define zScale    i.typeRegionTimeZScale.w
#define inkMapUV  ((i.screenPos + float2(0.5, 0.5)) * RcpRTSize)

int GetSurfaceIndex(float4 indexSample) {
    return int(lerp(indexSample.r, indexSample.g, ceil(indexSample.b)) * 255);
}

float4 FetchDataPixel(int id, int index) {
    if (id == 0) {
        return GROUND_PROPERTIES[index];
    }
    else {
        return tex2Dlod(DataSampler, float4(
            (id    - 0.5) * RcpDataRTSize.x,
            (index + 0.5) * RcpDataRTSize.y,
            0.0,
            0.0));
    }
}

// oldPixelValue = switch (regionID) {
//     0 => height value ranging from -1 to +1,
//     1 => depth value ranging from -1 to 0,
//     2 => ink type ID as a whole number,
// };
void CalculateHeight(
    const PS_INPUT i, float oldPixelValue, float heightSample,
    float4 heightParam, float geometryPaintBias, float nodig, float flatten,
    out float paintStrength, out float newHeight) {
    // Height map blend parameters
    float maxHeight      = heightParam.y;
    float heightBaseline = heightParam.w;
    float heightScale    = TO_SIGNED(heightParam.z) * zScale;
    float paintHeight    = heightSample * heightScale; // -1.0 -- +1.0
    float paintDetail    = paintHeight - heightBaseline * heightScale;
    float oldHeight, oldDepth;
    int oldIndex = int(oldPixelValue);
    if (regionID == 2) {
        float4 oldHeightUV = float4(inkMapUV + float2(0.0, -0.5), 0.0, 0.0);
        oldHeight = TO_SIGNED(tex2Dlod(InkMap, oldHeightUV).a);
        oldPixelValue = oldHeight;
    }

    // Height map blend calculation
    float oldHeightSaturated = saturate(sign(paintHeight) * oldPixelValue);
    float baselineFalloff = exp(-sign(paintHeight) * oldPixelValue / maxHeight);
    baselineFalloff *= 1 - oldHeightSaturated;
    float baselineAdd = paintHeight * baselineFalloff;
    float detailFalloff = oldHeightSaturated * oldHeightSaturated;
    detailFalloff *= detailFalloff;
    detailFalloff *= detailFalloff;
    detailFalloff *= detailFalloff;
    float detailAdd = paintDetail * (1 - detailFalloff);
    float desiredAdd = baselineAdd + detailAdd;
    newHeight = oldPixelValue + desiredAdd;
    paintStrength = 1.0 - geometryPaintBias;

    // Digging
    if (desiredAdd < 0.0) {
        desiredAdd = abs(desiredAdd);
        if (regionID == 0) {
            float4 oldDepthUV  = float4(inkMapUV + float2(0.5, 0.0), 0.0, 0.0);
            float4 oldIndexUV  = float4(inkMapUV + float2(0.0, 0.5), 0.0, 0.0);
            float4 indexSample = tex2Dlod(InkMap, oldIndexUV);
            oldHeight = oldPixelValue;
            oldDepth = tex2Dlod(InkMap, oldDepthUV).a;
            oldIndex = GetSurfaceIndex(indexSample);
        }
        else if (regionID == 1) {
            float4 oldHeightUV = float4(inkMapUV + float2(-0.5, 0.0), 0.0, 0.0);
            float4 oldIndexUV  = float4(inkMapUV + float2(-0.5, 0.5), 0.0, 0.0);
            float4 indexSample = tex2Dlod(InkMap, oldIndexUV);
            oldHeight = TO_SIGNED(tex2Dlod(InkMap, oldHeightUV).a);
            oldDepth = -oldPixelValue;
            oldIndex = GetSurfaceIndex(indexSample);
        }
        else if (regionID == 2) {
            float4 oldDepthUV = float4(inkMapUV + float2(0.5, -0.5), 0.0, 0.0);
            oldDepth = tex2Dlod(InkMap, oldDepthUV).a;
        }

        // Applying viscosity of the fluid on top of the ground
        float oldThickness = max(0.0, oldHeight + oldDepth);
        float viscosity = FetchDataPixel(oldIndex, ID_MISC).z;
        float fluidDigAmount = min(desiredAdd * viscosity, oldThickness);
        float solidDigAmount = desiredAdd - fluidDigAmount;
        newHeight = oldPixelValue;
        newHeight -= solidDigAmount;
        newHeight -= fluidDigAmount * (regionID == 1 ? 0 : 1);
        newHeight = max(nodig - 1.0, lerp(newHeight, 0.0, flatten));
        paintStrength = saturate(1 - nodig - geometryPaintBias
            * step(-oldHeight + fluidDigAmount + solidDigAmount, oldDepth + eps));
    }
}

PS_OUTPUT AdditiveAndHeight(const PS_INPUT i, float t, float shapeMask) {
    float4 add          = tex2D(BaseTextureAtlas, i.inkAndTintUV.xy);
    float4 tint         = tex2D(TintTextureAtlas, i.inkAndTintUV.zw);
    float4 old          = tex2D(InkMap, inkMapUV);
    float4 colorAlpha   = FetchDataPixel(paintType, ID_COLOR_ALPHA);
    float4 tintParam    = FetchDataPixel(paintType, ID_TINT_GEOMETRYPAINT);
    float4 heightParam  = FetchDataPixel(paintType, ID_HEIGHT_MAXLAYERS);
    float4 miscParam    = FetchDataPixel(paintType, ID_MISC);
    float  flatten      = miscParam.y;
    float  nodig        = NODIG;
    float  geometryBias = tintParam.w;
    float  paintStrength, newHeight;
    CalculateHeight(i, TO_SIGNED(old.a), add.a, heightParam,
        geometryBias, nodig, flatten, paintStrength, newHeight);

    // Basic tint by $color, $tintcolor, and $alpha
    add.rgb *= colorAlpha.rgb * paintStrength;
    tint.rgb *= (1.0 - colorAlpha.aaa) * tintParam.rgb;
    tint.rgb = lerp(1.0, tint.rgb, paintStrength);
    tint.rgb = saturate(tint.rgb);
    float erase = miscParam.x;
    float maxLayers = floor(heightParam.x * 255);
    float3 tintLimit = pow(tint.rgb, maxLayers);
    float3 tintFade = smoothstep(tintLimit, tintLimit + 0.0625, distance(old.rgb, add.rgb));
    float3 newColor = (old.rgb * lerp(1.0, tint.rgb, tintFade) + add.rgb * colorAlpha.aaa * tintFade) * (1.0 - erase);
    PS_OUTPUT output = { newColor, TO_UNSIGNED(newHeight), t };
    return output;
}

PS_OUTPUT TintAndDepth(const PS_INPUT i, float t, float shapeMask) {
    float4 add         = tex2D(BaseTextureAtlas, i.inkAndTintUV.xy);
    float4 tint        = tex2D(TintTextureAtlas, i.inkAndTintUV.zw);
    float4 old         = tex2D(InkMap, inkMapUV);
    float4 colorAlpha  = FetchDataPixel(paintType, ID_COLOR_ALPHA);
    float4 tintParam   = FetchDataPixel(paintType, ID_TINT_GEOMETRYPAINT);
    float4 heightParam = FetchDataPixel(paintType, ID_HEIGHT_MAXLAYERS);
    float4 miscParam   = FetchDataPixel(paintType, ID_MISC);
    float flatten      = miscParam.y;
    float nodig        = NODIG;
    float geometryBias = tintParam.w;
    float paintStrength, newHeight;
    CalculateHeight(i, -old.a, add.a, heightParam,
        geometryBias, nodig, flatten, paintStrength, newHeight);

    // Do not darken more than maxLayers times
    // But if current one is already darker than that, keep it
    tint.rgb *= (1.0 - colorAlpha.aaa) * tintParam.rgb;
    tint.rgb = lerp(1.0, tint.rgb, paintStrength);
    tint.rgb = saturate(tint.rgb);
    float erase = miscParam.x;
    float maxLayers = floor(heightParam.x * 255);
    float newDepth = max(-newHeight, old.a);
    float3 tintClipped = max(old.rgb * tint.rgb, pow(tint.rgb, maxLayers));
    float3 tintFinal = lerp(min(tintClipped, old.rgb), 1.0, erase);
    PS_OUTPUT output = { tintFinal, newDepth, newDepth };
    return output;
}

PS_OUTPUT PaintIndices(const PS_INPUT i, float t, float shapeMask) {
    float4 old          = tex2D(InkMap, inkMapUV);
    float4 miscParam    = FetchDataPixel(paintType, ID_MISC);
    PS_OUTPUT output = { old, t };
    if (max(old.r, max(old.g, old.b)) < 1.0 / 255.0) output.color.b = 1.0;
    if (abs(0.5 - frac(miscParam.w * 4.0)) < eps) return output; // $heightonly

    float4 add          = tex2D(BaseTextureAtlas, i.inkAndTintUV.xy);
    float4 tint         = tex2D(TintTextureAtlas, i.inkAndTintUV.zw);
    float4 tintParam    = FetchDataPixel(paintType, ID_TINT_GEOMETRYPAINT);
    float4 heightParam  = FetchDataPixel(paintType, ID_HEIGHT_MAXLAYERS);
    float  flatten      = miscParam.y;
    float  nodig        = NODIG;
    float  geometryBias = tintParam.w;
    float  paintStrength, newHeight;
    CalculateHeight(i, GetSurfaceIndex(old), add.a, heightParam,
        geometryBias, nodig, flatten, paintStrength, newHeight);
    if (paintStrength < eps) return output;

    float4 colorAlpha   = FetchDataPixel(paintType, ID_COLOR_ALPHA);
    tint.rgb *= (1.0 - colorAlpha.aaa) * tintParam.rgb;
    tint.rgb = lerp(1.0, tint.rgb, paintStrength);
    float thisID        = paintType / 255.0;
    float translucency  = length(tint.rgb);
    bool  isOpaque      = translucency < eps;
    output.color.rgb = float3(
        isOpaque ? thisID : old.r,
        isOpaque ? old.g  : thisID,
        isOpaque ? 0.0    : 1.0 - translucency * (1.0 - output.color.b));
    return output;
}

PS_OUTPUT DetailMapping(const PS_INPUT i, float t, float shapeMask) {
    float detailRotation = 0.0;
    float detailScale = 0.0;
    PS_OUTPUT output = {
        i.detailAndShapeUV.xy,
        detailRotation,
        detailScale, t,
    };
    return output;
}

PS_OUTPUT main(const PS_INPUT i) {
    clip(step(float4(i.surfaceClipRange.xy, inkMapUV), float4(inkMapUV, i.surfaceClipRange.zw)) - 0.5);

    float4 shapeMask = tex2D(TintTextureAtlas, i.detailAndShapeUV.zw);
    clip(shapeMask.a < eps ? -1.0 : 1.0);

    if (floor(regionID) == 0)
        return AdditiveAndHeight(i, time, shapeMask.a);
    else if (floor(regionID) == 1)
        return TintAndDepth(i, time, shapeMask.a);
    else if (floor(regionID) == 2)
        return PaintIndices(i, time, shapeMask.a);
    else
        return DetailMapping(i, time, shapeMask.a);
}
