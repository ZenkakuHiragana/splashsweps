
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

static const float  eps = 1e-4;
static const float3 GrayScaleFactor = { 0.2126, 0.7152, 0.0722 };
#define TO_SIGNED(x)   ((x) * 2.0 - 1.0) // [0.0, 1.0] --> [-1.0, +1.0]
#define TO_UNSIGNED(x) ((x) * 0.5 + 0.5) // [-1.0, +1.0] --> [0.0, 1.0]
#define paintType i.typeRegionTimeZScale.x
#define regionID  i.typeRegionTimeZScale.y
#define time      i.typeRegionTimeZScale.z
#define zScale    i.typeRegionTimeZScale.w
#define inkMapUV  (i.screenPos * RcpRTSize)

#define ID_COLOR_ALPHA        0
#define ID_TINT_GEOMETRYPAINT 1
#define ID_EDGE               2
#define ID_HEIGHT_MAXLAYERS   3
#define ID_MATERIAL_REFRACT   4
#define ID_MISC               5
#define ID_DETAILS_BUMPBLEND  6
#define ID_OTHERS             7

float4 FetchDataPixel(int id, int index) {
    float4 uv = { (float(id) - 0.5) * RcpDataRTSize.x, (float(index) + 0.5) * RcpDataRTSize.y, 0.0, 0.0 };
    return tex2Dlod(DataSampler, uv);
}

void CalculateHeight(const PS_INPUT i, float oldHeight, float heightSample,
    float geometryPaintBias, float nodig, out float paintStrength, out float newHeight) {
    // Height map blend parameters
    float4 heightParam = FetchDataPixel(paintType, ID_HEIGHT_MAXLAYERS);
    float maxHeight = heightParam.x;
    float meanHeight = heightParam.y;
    float heightScale = TO_SIGNED(heightParam.z) * 2.0 * zScale;

    // Height map blend calculation
    float paintHeight = heightSample * heightScale; // -2.0 -- +2.0
    float paintDetail = paintHeight - meanHeight * heightScale;
    float oldSpace = saturate(1.0 - sign(paintHeight) * oldHeight);
    float baselineFalloff = exp(-sign(paintHeight) * oldHeight / maxHeight);
    float baselineAdd = paintHeight * oldSpace * baselineFalloff;
    float detailFalloff = pow(oldSpace, 0.2);
    float detailAdd = paintDetail * detailFalloff;
    float desiredAdd = baselineAdd + detailAdd;
    newHeight = oldHeight + desiredAdd;
    paintStrength = 1.0;

    // Digging
    if (desiredAdd < 0.0) {
        float4 oldIndexUV = float4(inkMapUV + float2(0.0, 0.5), 0.0, 0.0);
        float4 oldDepthUV = float4(inkMapUV + float2(0.5, 0.0), 0.0, 0.0);
        float4 oldIndexSample = tex2Dlod(InkMap, oldIndexUV);
        float oldDepth = tex2Dlod(InkMap, oldDepthUV).a;
        float oldIndex = lerp(oldIndexSample.r, oldIndexSample.g, ceil(oldIndexSample.b)) * 255;
        float oldThickness = max(0.0, oldHeight + oldDepth);
        float viscosity = FetchDataPixel(int(oldIndex), ID_MISC).z;
        float fluidDigAmount = min(-desiredAdd * viscosity, oldThickness);
        float solidDigAmount = -desiredAdd - fluidDigAmount;
        newHeight = oldHeight - fluidDigAmount - solidDigAmount * viscosity;
        paintStrength = saturate(1 - nodig - geometryPaintBias * step(-newHeight, oldDepth + eps));
    }
}

PS_OUTPUT AdditiveAndHeight(const PS_INPUT i, float t, float shapeMask) {
    float4 add = tex2D(BaseTextureAtlas, i.inkAndTintUV.xy);
    float4 tint = tex2D(TintTextureAtlas, i.inkAndTintUV.zw);
    float4 old = tex2D(InkMap, inkMapUV);
    float4 colorAlphaParam = FetchDataPixel(paintType, ID_COLOR_ALPHA);
    float4 tintParam = FetchDataPixel(paintType, ID_TINT_GEOMETRYPAINT);
    float4 miscParam = FetchDataPixel(paintType, ID_MISC);
    float nodig = step(0.5, miscParam.w);
    float geometryPaintBias = tintParam.w;
    float oldHeight = TO_SIGNED(old.a);
    float heightSample = add.a;
    float paintStrength, newHeight;
    CalculateHeight(i, oldHeight, heightSample,
        geometryPaintBias, nodig, paintStrength, newHeight);

    // Basic tint by $color, $tintcolor, and $alpha
    add.rgb *= colorAlphaParam.rgb * paintStrength;
    tint.rgb *= (1.0 - colorAlphaParam.aaa) * tintParam.rgb * paintStrength;
    float erase = miscParam.x;
    float flatten = miscParam.y;
    float3 newColor = old.rgb * tint.rgb + add.rgb * (1.0 - erase);
    float clampedHeight = max(nodig - 1.0, lerp(newHeight, 0.0, flatten));
    PS_OUTPUT output = { newColor.r, newColor.g, newColor.b, TO_UNSIGNED(clampedHeight), t };
    return output;
}

PS_OUTPUT TintAndDepth(const PS_INPUT i, float t, float shapeMask) {
    float4 add = tex2D(BaseTextureAtlas, i.inkAndTintUV.xy);
    float4 tint = tex2D(TintTextureAtlas, i.inkAndTintUV.zw);
    float4 old = tex2D(InkMap, inkMapUV);
    float4 colorAlphaParam = FetchDataPixel(paintType, ID_COLOR_ALPHA);
    float4 tintParam = FetchDataPixel(paintType, ID_TINT_GEOMETRYPAINT);
    float4 heightParam = FetchDataPixel(paintType, ID_HEIGHT_MAXLAYERS);
    float4 miscParam = FetchDataPixel(paintType, ID_MISC);
    float nodig = step(0.5, miscParam.w);
    float depthScale = TO_SIGNED(heightParam.z) * 2.0 * zScale;

    // Digging
    float depth = old.a;
    float paintStrength = 1.0;
    if (depthScale < 0.0 && nodig == 0.0) {
        // Height map blend calculation
        float flatten = miscParam.y;
        float maxDepth = heightParam.x;
        float meanDepth = heightParam.y;
        float paintDepth = add.a * depthScale; // -2.0 -- 0.0
        float paintDetail = paintDepth - meanDepth * depthScale;
        float oldSpace = saturate(1.0 - depth);
        float baselineFalloff = exp(-depth / maxDepth);
        float baselineAdd = paintDepth * oldSpace * baselineFalloff; // < 0
        float detailFalloff = pow(oldSpace, 0.2);
        float detailAdd = paintDetail * detailFalloff;
        float desiredAdd = baselineAdd + detailAdd; // < 0

        // Applying viscosity of the fluid on top of the ground
        static const float eps = 1e-4;
        float4 oldIndexUV = float4(inkMapUV + float2(-0.5, 0.5), 0.0, 0.0);
        float4 oldHeightUV = float4(inkMapUV + float2(0.5, 0.0), 0.0, 0.0);
        float4 oldIndexSample = tex2Dlod(InkMap, oldIndexUV);
        float oldHeight = tex2Dlod(InkMap, oldHeightUV).a;
        float oldIndex = lerp(oldIndexSample.r, oldIndexSample.g, ceil(oldIndexSample.b)) * 255;
        float oldThickness = max(0.0, oldHeight + depth);
        float viscosity = FetchDataPixel(int(oldIndex), ID_MISC).z;
        float fluidDigAmount = min(-desiredAdd * viscosity, oldThickness);
        float solidDigAmount = -desiredAdd - fluidDigAmount;
        float geometryPaintBias = tintParam.w;
        float newDepth = depth + solidDigAmount;
        paintStrength = saturate(1 - geometryPaintBias * step(newDepth, depth + eps));
        depth = max(-1.0, lerp(newDepth, 0.0, flatten));
    }

    // Do not darken more than maxLayers times
    // But if current one is already darker than that, keep it
    tint.rgb *= (1.0 - colorAlphaParam.aaa) * tintParam.rgb * paintStrength;
    float erase = miscParam.x;
    float maxLayers = floor(heightParam.w * 255);
    float3 tintClipped = max(old.rgb * tint.rgb, pow(saturate(tint.rgb), maxLayers));
    float3 tintFinal = lerp(min(tintClipped, old.rgb), 1.0, erase);
    PS_OUTPUT output = { tintFinal.r, tintFinal.g, tintFinal.b, depth, depth };
    return output;
}

PS_OUTPUT PaintIndices(const PS_INPUT i, float t, float shapeMask) {
    float4 old = tex2D(InkMap, inkMapUV);
    float4 tint = tex2D(TintTextureAtlas, i.inkAndTintUV.zw);
    float4 heightSample = tex2D(InkMap, inkMapUV + float2(0.0, -0.5));
    float4 colorAlphaParam = FetchDataPixel(paintType, ID_COLOR_ALPHA);
    float4 tintParam = FetchDataPixel(paintType, ID_TINT_GEOMETRYPAINT);
    float nodig = step(0.5, FetchDataPixel(paintType, ID_MISC).w);
    float geometryPaintBias = tintParam.w;
    float oldHeight = TO_SIGNED(old.a);
    float paintStrength, newHeight;
    CalculateHeight(i, oldHeight, heightSample.a,
        geometryPaintBias, nodig, paintStrength, newHeight);
    float scale = dot(GrayScaleFactor,
        tint.rgb * colorAlphaParam.aaa * tintParam.rgb * paintStrength);
    PS_OUTPUT output = {
        scale < eps ? saturate(paintType / 255) : old.r,
        scale > 0.0 ? saturate(paintType / 255) : old.g,
        scale < eps ? 0.0                       : saturate(1.0 - scale),
        0.0, t,
    };
    return output;
}

PS_OUTPUT DetailMapping(const PS_INPUT i, float t, float shapeMask) {
    float detailRotation = 0.0;
    float detailScale = 0.0;
    PS_OUTPUT output = {
        i.detailAndShapeUV.x,
        i.detailAndShapeUV.y,
        detailRotation,
        detailScale, t,
    };
    return output;
}

PS_OUTPUT main(const PS_INPUT i) {
    clip(inkMapUV - i.surfaceClipRange.xy);
    clip(i.surfaceClipRange.zw - inkMapUV);

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
