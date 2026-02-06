
sampler InkMap             : register(s0);
sampler DataSampler        : register(s1);
sampler BaseTextureAtlas   : register(s2);
sampler TintTextureAtlas   : register(s3);
const float2 RcpRTSize     : register(c4); // One over render target size
const float2 RcpDataRTSize : register(c5);

static const float  eps = 1e-4;

// [0.0, 1.0] --> [-1.0, +1.0]
#define TO_SIGNED(x) ((x) * 2.0 - 1.0)

// [-1.0, +1.0] --> [0.0, 1.0]
#define TO_UNSIGNED(x) ((x) * 0.5 + 0.5)

struct PS_INPUT {
    float2 screenPos             : VPOS;
    float4 inkUV_shapeUV         : TEXCOORD0;
    float4 surfaceClipRange      : TEXCOORD1;
    float4 timeRegionTypeOpacity : TEXCOORD2;
};

struct PS_OUTPUT {
    float4 color : COLOR0;
    float  depth : DEPTH0;
};

float4 FetchDataPixel(int id, int index) {
    float4 uv = { id * RcpDataRTSize.x, index * RcpDataRTSize.y, 0.0, 0.0 };
    return tex2Dlod(DataSampler, uv);
}

PS_OUTPUT AdditiveAndHeight(const PS_INPUT i, float t, float shapeMask) {
    int paintType = int(i.timeRegionTypeOpacity.z);
    float4 add = tex2D(BaseTextureAtlas, i.inkUV_shapeUV.xy);
    float4 tint = tex2D(TintTextureAtlas, i.inkUV_shapeUV.xy);
    float4 old = tex2D(InkMap, i.screenPos * RcpRTSize);
    float4 colorAlphaParam = FetchDataPixel(paintType, 0);
    float4 tintParam = FetchDataPixel(paintType, 1);
    float4 heightParam = FetchDataPixel(paintType, 2);
    float4 miscParam = FetchDataPixel(paintType, 4);

    // Height map blend parameters
    float nodig = step(0.5, miscParam.w);
    float maxHeight = heightParam.x;
    float meanHeight = heightParam.y;
    float heightScale = TO_SIGNED(heightParam.z) * 2.0;

    // Height map blend calculation
    float paintHeight = add.a * heightScale; // -2.0 -- +2.0
    float paintDetail = paintHeight - meanHeight * heightScale;
    float oldHeight = TO_SIGNED(old.a);
    float oldSpace = saturate(1.0 - sign(paintHeight) * oldHeight);
    float baselineFalloff = exp(-sign(paintHeight) * oldHeight / maxHeight);
    float baselineAdd = paintHeight * oldSpace * baselineFalloff;
    float detailFalloff = pow(oldSpace, 0.2);
    float detailAdd = paintDetail * detailFalloff;
    float desiredAdd = baselineAdd + detailAdd;
    float newHeight = oldHeight + desiredAdd;

    // Digging
    float paintStrength = 1.0;
    if (desiredAdd < 0.0) {
        float4 oldIndexUV = float4(i.screenPos * RcpRTSize + float2(0.0, 0.5), 0.0, 0.0);
        float4 oldDepthUV = float4(i.screenPos * RcpRTSize + float2(0.5, 0.0), 0.0, 0.0);
        float4 oldIndexSample = tex2Dlod(InkMap, oldIndexUV);
        float oldDepth = tex2Dlod(InkMap, oldDepthUV).a;
        float oldIndex = lerp(oldIndexSample.r, oldIndexSample.g, ceil(oldIndexSample.b));
        float oldThickness = max(0.0, oldHeight + oldDepth);
        float viscosity = FetchDataPixel(int(oldIndex), 4).z;
        float fluidDigAmount = min(-desiredAdd * viscosity, oldThickness);
        float solidDigAmount = -desiredAdd - fluidDigAmount;
        float geometryPaintBias = tintParam.w;
        newHeight = oldHeight - fluidDigAmount - solidDigAmount * viscosity;
        paintStrength = saturate(1 - nodig - geometryPaintBias * step(-newHeight, oldDepth + eps));
    }

    // Basic tint by $color, $tintcolor, and $alpha
    add.rgb *= colorAlphaParam.rgb * paintStrength;
    tint.rgb *= colorAlphaParam.aaa * tintParam.rgb * paintStrength;
    float erase = miscParam.x;
    float flatten = miscParam.y;
    float3 newColor = old.rgb * tint.rgb + add.rgb * (1.0 - erase);
    float clampedHeight = max(nodig - 1.0, lerp(newHeight, 0.0, flatten));
    PS_OUTPUT output = { newColor.r, newColor.g, newColor.b, TO_UNSIGNED(clampedHeight), t };
    return output;
}

PS_OUTPUT TintAndDepth(const PS_INPUT i, float t, float shapeMask) {
    int paintType = int(i.timeRegionTypeOpacity.z);
    float4 add = tex2D(BaseTextureAtlas, i.inkUV_shapeUV.xy);
    float4 tint = tex2D(TintTextureAtlas, i.inkUV_shapeUV.xy);
    float4 old = tex2D(InkMap, i.screenPos * RcpRTSize);
    float4 colorAlphaParam = FetchDataPixel(paintType, 0);
    float4 tintParam = FetchDataPixel(paintType, 1);
    float4 heightParam = FetchDataPixel(paintType, 2);
    float4 miscParam = FetchDataPixel(paintType, 4);
    float nodig = step(0.5, miscParam.w);
    float depthScale = heightParam.z;

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
        float4 oldIndexUV = float4(i.screenPos * RcpRTSize + float2(-0.5, 0.5), 0.0, 0.0);
        float4 oldHeightUV = float4(i.screenPos * RcpRTSize + float2(0.5, 0.0), 0.0, 0.0);
        float4 oldIndexSample = tex2Dlod(InkMap, oldIndexUV);
        float oldHeight = tex2Dlod(InkMap, oldHeightUV).a;
        float oldIndex = lerp(oldIndexSample.r, oldIndexSample.g, ceil(oldIndexSample.b));
        float oldThickness = max(0.0, oldHeight + depth);
        float viscosity = FetchDataPixel(int(oldIndex), 4).z;
        float fluidDigAmount = min(-desiredAdd * viscosity, oldThickness);
        float solidDigAmount = -desiredAdd - fluidDigAmount;
        float geometryPaintBias = tintParam.w;
        float newDepth = depth + solidDigAmount;
        paintStrength = saturate(1 - geometryPaintBias * step(newDepth, depth + eps));
        depth = max(-1.0, lerp(newDepth, 0.0, flatten));
    }

    // Do not darken more than maxLayers times
    // But if current one is already darker than that, keep it
    tint.rgb *= tintParam.rgb * colorAlphaParam.aaa * paintStrength;
    float erase = miscParam.x;
    float maxLayers = heightParam.w * 255;
    float3 tintClipped = max(old.rgb * tint.rgb, pow(saturate(tint.rgb), maxLayers));
    float3 tintFinal = lerp(min(tintClipped, old.rgb), 1.0, erase);
    PS_OUTPUT output = { tintFinal.r, tintFinal.g, tintFinal.b, depth, depth };
    return output;
}

PS_OUTPUT PaintIndices(const PS_INPUT i, float t, float shapeMask) {
    float4 old = tex2D(InkMap, i.screenPos * RcpRTSize);
    float inkType = i.timeRegionTypeOpacity.z;
    float opacity = i.timeRegionTypeOpacity.w;
    PS_OUTPUT output = {
        opacity > 1.0 - eps ? inkType : old.r,
        opacity < 1.0       ? inkType : old.g,
        opacity < 1.0       ? opacity : 0.0,
        0.0, t,
    };
    return output;
}

PS_OUTPUT DetailMapping(const PS_INPUT i, float t, float shapeMask) {
    float detailRotation = 0.0;
    float detailScale = 1.0;
    PS_OUTPUT output = {
        i.inkUV_shapeUV.x,
        i.inkUV_shapeUV.y,
        detailRotation,
        detailScale, t,
    };
    return output;
}

PS_OUTPUT main(const PS_INPUT i) {
    clip(i.screenPos * RcpRTSize - i.surfaceClipRange.xy);
    clip(i.surfaceClipRange.zw - i.screenPos * RcpRTSize);

    float4 shapeMask = tex2D(TintTextureAtlas, i.inkUV_shapeUV.zw);
    clip(shapeMask.a == 0.0 ? -1.0 : 1.0);

    float t = i.timeRegionTypeOpacity.x;
    float regionIndex = i.timeRegionTypeOpacity.y;
    if (regionIndex == 0)
        return AdditiveAndHeight(i, t, shapeMask.a);
    if (regionIndex == 1)
        return TintAndDepth(i, t, shapeMask.a);
    if (regionIndex == 2)
        return PaintIndices(i, t, shapeMask.a);
    return DetailMapping(i, t, shapeMask.a);
}
