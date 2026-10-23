// Shading of the ink mesh pixel shaders for SplashSWEPs, shared by the geometry kinds.
// Included last by the geometry pixel shaders; see inkmesh_ps_ink.hlsl.

// Axes the ink detail image is projected along, in world space: rows are U, V, and the projection Z.
// World mode projects along the positive world axis of the largest absolute component of the mesh normal,
// and takes the other two axes in X, Y, Z order as U and V.
// Local mode takes the flattened paint coordinates used by drawink, which follow
// brush transforms and the displacement's existing paint mapping.
// Derived from the vertex inputs where needed, as carrying them takes too many temp registers.
float3x3 GetDetailProjectionBasis(const PsVertexInfo i, bool usePaintLocalDetail) {
    if (usePaintLocalDetail) {
        return float3x3(
            normalize(i.inkTransform[0]),
            normalize(i.inkTransform[1]),
            normalize(i.worldTransform[2]));
    }

    float3 absNormal = abs(i.worldTransform[2]);
    if (absNormal.x >= absNormal.y && absNormal.x >= absNormal.z) {
        return float3x3(0, 1, 0,  0, 0, 1,  1, 0, 0);
    }
    else if (absNormal.y >= absNormal.z) {
        return float3x3(1, 0, 0,  0, 0, 1,  0, 1, 0);
    }
    else {
        return float3x3(1, 0, 0,  0, 1, 0,  0, 0, 1);
    }
}

// Samples height value and ground depth, and calculates the ink normal from the height
void FetchHeightDepthAndNormal(const PsVertexInfo i, float2 uv, inout MaterialParams params) {
    float4 s = tex2Dlod(InkMap, float4(uv + INKMAP_HEIGHT_DEPTH, 0.0, 0.0));
    params.height = TO_SIGNED(DecodeUnorm16(s.rg));
    params.depth  = DecodeUnorm16(s.ba);

    // Forward differences of the height over deltaUV, in Hammer units per ink map UV.
    float2 deltaUV = g_RTSize * 2.0;
    float2 hxy = {
        FetchHeight(uv + float2(deltaUV.x, 0.0)),
        FetchHeight(uv + float2(0.0, deltaUV.y)),
    };

    // The first two rows of inkTransform are the world gradients of ink map U and V.
    // Chain rule: the height field's world normal is N - (dz/du * grad(u) + dz/dv * grad(v)).
    float2 slope = (hxy - params.height) * HEIGHT_TO_HU / deltaUV;
    params.normal = normalize(mul(float3(-slope, 1.0), i.inkTransform));
}

// Lit geometry color: the frame buffer, or the geometry albedo lit by diffuseLight where it's unavailable.
float3 EvaluateGeometryLighting(const UVs uv, const GeometryAlbedo albedo, float3 diffuseLight) {
    float fbRatio = uv.edgefade;
    float4 fb = SampleScene(uv.screen);
    if (fb.a * DEPTHWRITE_TO_HU < uv.depth - max(2.0, uv.depth * 0.015)) {
        fbRatio = 0.0;
    }
    return lerp(albedo.color * diffuseLight, fb.rgb, fbRatio);
}

// Sample the upper material's image and evaluate its normal/color/lighting effects.
// Discrete placement comes from the texel the IDs were read from (idTexelUV, without the region offset);
// image position uses the continuous parallax hit.
InkDetailEffect EvaluateInkDetail(const PsVertexInfo i, float3 IDs, int modeRotationByte, float2 idTexelUV,
    float3 inkUV, float height, float depth, bool usePaintLocalDetail) {
    InkDetailEffect effect = (InkDetailEffect)0;
    effect.colorScale    = 1.0;
    effect.specularScale = 1.0;
    effect.normal        = float3(0.0, 0.0, 1.0);
    int paintRotationCode5 = modeRotationByte / 8;
    int mode = modeRotationByte - paintRotationCode5 * 8;
    if (mode == DETAIL_MODE_NONE) return effect;
    int id  = (int)(IDs.y > 0.0 ? IDs.y : IDs.x);

    // Project detail sample position onto the 2D plane of the projection axes
    float3x3 projectionBasis = GetDetailProjectionBasis(i, usePaintLocalDetail);

    // The parallax ray's Z is in HEIGHT_TO_HU units along the mesh normal.
    // Evaluate the display texture at that hit, not at the unshifted mesh pixel.
    float3 viewVec = g_EyePos.xyz - i.worldPos;
    float3 worldPos = i.worldPos + viewVec * inkUV.z * HEIGHT_TO_HU * SAFERCP(dot(viewVec, i.worldTransform[2]));
    float2 projectionPositionHU = float2(dot(worldPos, projectionBasis[0]), dot(worldPos, projectionBasis[1]));
    float2 mapToPaintCosSin = float2(1.0, 0.0); // World mode keeps the projection axes.
    float2 phase = 0.0;
    [branch]
    if (usePaintLocalDetail) {
        // The same flattened paint coordinates used by drawink, including atlas placement.
        projectionPositionHU = inkUV.xy * g_InkMapHUPerUV;
        mapToPaintCosSin = DecodeInkMapToPaintCosSin(paintRotationCode5);
        phase.x = tex2Dlod(InkMap, float4(idTexelUV + INKMAP_ADDITIVE, 0.0, 0.0)).a;
        phase.y = tex2Dlod(InkMap, float4(idTexelUV + INKMAP_MULTIPLICATIVE, 0.0, 0.0)).a;
    }

    InkDetailSettings settings;
    float4 encodedTransform       = FetchDataPixel(InkDataDetail, id, ID_DETAIL_TRANSFORM);
    float4 encodedScaleRow        = FetchDataPixel(InkDataDetail, id, ID_DETAIL_SCALE);
    float  gridIndex              = round(encodedScaleRow.z * 255.0);
    float  gridRow                = floor((gridIndex + 0.5) / g_DetailGridColumns);
    float  gridColumn             = gridIndex - gridRow * g_DetailGridColumns;
    float  cellSizePixels         = g_InkDataOffsetV / g_DetailGridColumns;
    settings.uvRotationCosSin     = encodedTransform.zw * (255.0 / 127.0) - 1.0; // 127 / 255 encodes zero
    settings.repeatsPerHU         = exp2(encodedScaleRow.xy * (255.0 / 24.0) - 13.0); // 24 steps per octave
    settings.translationUV        = encodedTransform.xy;
    settings.atlasOriginPixels    = float2(gridColumn, gridRow) * cellSizePixels + 1.0;
    settings.atlasInnerSizePixels = cellSizePixels - 2.0;
    settings.blendScale           = FetchDataPixel(InkDataDetail, id, ID_DETAIL_BLEND_SCALE) * (255.0 / 127.0);

    // Local mode: ink-map HU -> paint HU; world mode keeps the projection axes unchanged.
    float2 paintPositionHU = float2(
        mapToPaintCosSin.x * projectionPositionHU.x - mapToPaintCosSin.y * projectionPositionHU.y,
        mapToPaintCosSin.y * projectionPositionHU.x + mapToPaintCosSin.x * projectionPositionHU.y);
    float2 scaledUV = paintPositionHU * settings.repeatsPerHU;
    float2 rotatedUV = float2(
        settings.uvRotationCosSin.x * scaledUV.x - settings.uvRotationCosSin.y * scaledUV.y,
        settings.uvRotationCosSin.y * scaledUV.x + settings.uvRotationCosSin.x * scaledUV.y);
    float2 repeatedUV   = frac(rotatedUV + settings.translationUV + phase);
    float2 atlasUV      = (settings.atlasOriginPixels + repeatedUV * settings.atlasInnerSizePixels) * g_DataRTSize;
    float4 detailSample = tex2Dlod(InkDataDetail, float4(atlasUV, 0, 0));

    // Convert the sample to the value range of each mode, then apply $detailblendscale to all channels.
    // RG of the normal modes stores normal XY. Reconstruct Z before the scale steepens XY.
    float4 s = detailSample;
    if (mode == DETAIL_MODE_MATERIAL) s     = TO_SIGNED(s);
    if (mode == DETAIL_MODE_NORMAL)   s.rgb = TO_SIGNED(s.rgb);
    if (mode == DETAIL_MODE_THINFILM) s.rg  = TO_SIGNED(s.rg);
    float normalZ = sqrt(saturate(1.0 - dot(s.xy, s.xy)));
    s *= settings.blendScale;

    [branch]
    if (mode == DETAIL_MODE_MATERIAL || mode == DETAIL_MODE_NORMAL || mode == DETAIL_MODE_THINFILM) {
        // Transpose the material UV rotation, then the ink-map -> paint rotation, without rescaling XY.
        float2 normalXYInPaint = float2(
            settings.uvRotationCosSin.x * s.x + settings.uvRotationCosSin.y * s.y,
           -settings.uvRotationCosSin.y * s.x + settings.uvRotationCosSin.x * s.y);
        float2 paintToMapCosSin = float2(mapToPaintCosSin.x, -mapToPaintCosSin.y);
        float2 normalXYInProjection = float2(
            paintToMapCosSin.x * normalXYInPaint.x - paintToMapCosSin.y * normalXYInPaint.y,
            paintToMapCosSin.y * normalXYInPaint.x + paintToMapCosSin.x * normalXYInPaint.y);
        effect.normal = float3(normalXYInProjection, normalZ);
    }

    [branch]
    if (mode == DETAIL_MODE_MATERIAL) {
        effect.colorScale   = max(0.0, 1.0 + s.a);
        effect.roughnessAdd = s.b;
    }
    else if (mode == DETAIL_MODE_NORMAL) {
        effect.specularScale = s.a;
    }
    else if (mode == DETAIL_MODE_EMISSION) {
        effect.emission = s.rgb * s.a;
    }
    else if (mode == DETAIL_MODE_COLOR) {
        effect.colorScale = 1.0 - s.a;
        effect.colorAdd   = s.rgb * s.a;
    }
    else if (mode == DETAIL_MODE_THINFILM) {
        effect.filmThickness = s.b * FILM_THICKNESS_MAX;
        effect.filmStrength  = saturate(s.a);
    }

    float heightBlendByte        = round(encodedScaleRow.w * 255.0);
    float heightLimitSqrtCode5   = floor(heightBlendByte / 8.0);
    float heightSourceInvertBits = heightBlendByte - heightLimitSqrtCode5 * 8.0;
    float heightSource           = floor(heightSourceInvertBits / 2.0);
    [branch]
    if (heightSource > 0.0) {
        // Source 1 = thickness, 2 = height, 3 = ground depth; all in HEIGHT_TO_HU units.
        float heightBlendInput = heightSource < 1.5 ? height + depth
                               : heightSource < 2.5 ? height : depth;
        // The stored limit is sqrt(maxHU / HEIGHT_TO_HU), quantized to a nonzero 5-bit level.
        float heightLimitSqrt = (heightLimitSqrtCode5 + 1.0) / 32.0;
        float heightWeight = saturate(heightBlendInput / (heightLimitSqrt * heightLimitSqrt));
        if (heightSourceInvertBits - heightSource * 2.0 > 0.5)
            heightWeight = 1.0 - heightWeight;

        effect.normal        = lerp(float3(0.0, 0.0, 1.0), effect.normal, heightWeight);
        effect.roughnessAdd *= heightWeight;
        effect.specularScale = lerp(1.0, effect.specularScale, heightWeight);
        effect.colorScale    = lerp(1.0, effect.colorScale, heightWeight);
        effect.colorAdd     *= heightWeight;
        effect.emission     *= heightWeight;
        effect.filmStrength *= heightWeight;
    }

    return effect;
}

// Steep Parallax Occlusion Mapping
float3 ApplyParallaxInk(const PsVertexInfo i) {
    const float PIXELS_PER_STEP_RCP = rcp(16.0);
    const float MIN_STEPS = 2.0;
    const float MAX_STEPS = 12.0;
    float3 worldPos = i.worldPos;
    float3 inkUV    = i.inkUV;
    float3x3 tangentSpaceInk = i.inkTransform;
    tangentSpaceInk[2] /= HEIGHT_TO_HU;

    float3 boxMin      = { i.minUV, -1.0 - 1e-5 };
    float3 boxMax      = { i.maxUV,  0.0        };
    float3 viewDir     = mul(tangentSpaceInk, g_EyePos.xyz - worldPos);
    float3 viewDirInv  = SAFERCP(viewDir);
    float3 fractionMin = (boxMin - inkUV) * viewDirInv;
    float3 fractionMax = (boxMax - inkUV) * viewDirInv;
    float3 fractionFar = min(fractionMin, fractionMax);
    float  fractionEnd = max(max(fractionFar.x, fractionFar.y), fractionFar.z);
    float3 rayStart    = inkUV;
    float3 rayEnd      = inkUV + viewDir * fractionEnd;
    float  pixelPerUV  = rcp(max(min(length(ddx(inkUV.xy)), length(ddy(inkUV.xy))), 1.0e-8));
    float  numSteps    = distance(rayStart.xy, rayEnd.xy);
    numSteps *= PIXELS_PER_STEP_RCP * pixelPerUV;
    numSteps = clamp(round(numSteps), MIN_STEPS, MAX_STEPS);
    float3 previousRay;
    float3 currentRay = rayStart;
    float previousInkHeight;
    float currentInkHeight = FetchHeight(currentRay.xy);
    if (currentInkHeight >= 0.0) return currentRay;
    [unroll]
    for (int j = 1; j <= MAX_STEPS; j++) {
        if (j > (int)numSteps) break;
        float fraction = (float)j / numSteps;
        previousInkHeight = currentInkHeight;
        previousRay = currentRay;
        currentRay = lerp(rayStart, rayEnd, fraction);
        currentInkHeight = FetchHeight(currentRay.xy);
        if (currentInkHeight >= 0.0) return currentRay;
        if ((previousInkHeight <= previousRay.z && currentRay.z <= currentInkHeight) ||
            (previousRay.z <= previousInkHeight && currentInkHeight <= currentRay.z)) {
            float previousHeightLeft = previousRay.z - previousInkHeight;
            float currentHeightExceeds = currentInkHeight - currentRay.z;
            float parallaxRefinement = currentHeightExceeds / (previousHeightLeft + currentHeightExceeds);
            inkUV = lerp(currentRay, previousRay, parallaxRefinement);
            return clamp(inkUV, float3(i.minUV, -1.0), float3(i.maxUV,  1.0));
        }
    }
    return clamp(inkUV, float3(i.minUV, -1.0), float3(i.maxUV,  1.0));
}

// interfaceNormal: world normal of the ink surface, without the underlay bumpmap
UVs ApplyParallaxGeometry(const PsVertexInfo i, const MaterialParams params, float3 interfaceNormal) {
    UVs uv;
    float3 meshNormal = i.worldTransform[2];
    float3 viewVec    = g_EyePos.xyz - i.worldPos;

    // Straight view ray reaching the ground at params.depth below the mesh, in Hammer units
    float  viewVecZ = max(dot(viewVec, meshNormal) / HEIGHT_TO_HU, 1.0e-3);
    float3 parallax = -viewVec * params.depth / viewVecZ;

    // Approximated refraction: the view ray shifts against the interface slope,
    // in proportion to the liquid thickness (interface height + ground depth).
    float  thickness      = (params.height + params.depth) * HEIGHT_TO_HU;
    float3 interfaceSlope = interfaceNormal - meshNormal * dot(interfaceNormal, meshNormal);
    float3 refraction     = -thickness * params.pbr.refraction * interfaceSlope;

    // The first two rows of worldTransform are the world gradients of the geometry texels
    float3 worldOffset = parallax + refraction;
    float2 uvOffset = float2(
        dot(i.worldTransform[0], worldOffset),
        dot(i.worldTransform[1], worldOffset)) * g_UnderlayAlbedoSize;
    float2 worldUVParallax = i.worldUV + uvOffset;
    uv.base     = ApplyBaseTransform(worldUVParallax);
    uv.bump     = ApplyBumpTransform(worldUVParallax);
    ApplyGeometryParallax(i, worldOffset, uvOffset, worldUVParallax, uv);

    float2 offset = ProjectiveUVToScreenOffset(i.worldUV, i.worldUV + uvOffset, i.clipW);
    float2 s      = i.screenUV + offset * g_FbSize;
    uv.edgefade   = ScreenEdgeFade(s);
    uv.screen     = saturate(s);
    uv.depth      = i.clipW + ddx(i.clipW) * offset.x + ddy(i.clipW) * offset.y;
    return uv;
}

PS_OUTPUT main(const PS_INPUT rawInput) {
    PsVertexInfo i = DecomposeInput(rawInput);
    float sceneViewDepthHU = SampleScene(i.screenUV).a * DEPTHWRITE_TO_HU;
    float depthToleranceHU = max(2.0, i.clipW * 0.015);
    clip(sceneViewDepthHU - i.clipW + depthToleranceHU);

    // Z = final ray marching height
    float3 inkUV   = g_Simplified ? i.inkUV : ApplyParallaxInk(i);
    float3 viewVec = g_EyePos.xyz - i.worldPos;
    float3 viewDir = normalize(viewVec);
    InkRegionSelection region = SelectInkRegion(inkUV.xy);
    float4 inkIDs  = region.indices;
    float3 IDs = {
        round(inkIDs.r * 255.0),
        round(inkIDs.g * 255.0),
        DecodeIndicesDistanceBlend(inkIDs.b).y,
    };
    int detailModeRotationByte = (int)round(inkIDs.a * 255.0);
    clip(floor(IDs.x + IDs.y + IDs.z) - 0.5);

    // Samples ink parameters
    MaterialParams params;
    params.additive = FetchRegionColor(region, inkUV.xy, INKMAP_ADDITIVE);
    params.multiplicative = FetchRegionColor(region, inkUV.xy, INKMAP_MULTIPLICATIVE);
    FetchHeightDepthAndNormal(i, inkUV.xy, params);
    FetchInkMaterialParams(IDs, params);

    InkDetailEffect detail = EvaluateInkDetail(i, IDs,
        detailModeRotationByte, region.texelUV, inkUV, params.height, params.depth, params.usePaintLocalDetail);
    float3 inkColor = params.additive * detail.colorScale + detail.colorAdd;
    params.pbr.roughness = saturate(params.pbr.roughness + detail.roughnessAdd);
    params.pbr.specularScale *= detail.specularScale;
    params.multiplicative *= detail.colorScale;

    // The ink interface refracts the underlay, regardless of the underlay bumpmap
    float3 interfaceNormal = normalize(
        ApplyDetailNormalWorld(params.normal, detail,
        GetDetailProjectionBasis(i, params.usePaintLocalDetail)));
    UVs uv = ApplyParallaxGeometry(i, params, interfaceNormal);
    GeometryAlbedo geometryAlbedo = FetchGeometryAlbedo(i, uv);

    // Match Source's shading basis without changing the UV gradients used by parallax.
    float3 normal = normalize(i.worldTransform[2]);
    float3 tangent = normalize(cross(normal, i.worldTransform[1]));
    float3 binormal = normalize(cross(tangent, normal));
    if (dot(normal, cross(i.worldTransform[0], i.worldTransform[1])) > 0.0)
        tangent = -tangent;
    float3x3 shadingBasis = float3x3(tangent, binormal, normal);

    // Blend ink and world normals in world space.
    float3 geometryNormal      = normalize(FetchGeometryNormal(i, uv, geometryAlbedo.layerWeights));
    float3 geometryNormalWorld = mul(geometryNormal, shadingBasis);
    float  inkNormalWeight     = saturate((params.height + params.depth) * SAFERCP(params.normalBlendThickness));
    float3 blendedNormal       = lerp(geometryNormalWorld, params.normal, inkNormalWeight);
    float3 worldSpaceNormal    = normalize(ApplyDetailNormalWorld(blendedNormal, detail,
        GetDetailProjectionBasis(i, params.usePaintLocalDetail)));
    float3 tangentSpaceNormal  = normalize(mul(shadingBasis, worldSpaceNormal));

    // Calculate diffuse color
    GeometryLight light = EvaluateGeometryLight(i, uv, tangentSpaceNormal, worldSpaceNormal);

    float3 geometryLit = params.multiplicative * EvaluateGeometryLighting(uv, geometryAlbedo, light.diffuse);

    // Modulate surface albedo and add ink color
    float3 ambientOcclusion = { 1.0, 1.0, 1.0 }; // dummy!
    float  diffuseScale = lerp(1.0, DIFFUSE_MIN, params.pbr.metallic);
    float3 inkLit = inkColor * light.diffuse;
    float3 albedo = geometryLit + inkLit;
    float3 result = albedo * diffuseScale + detail.emission;

    // Simplified pass doesn't need specular component
    if (g_Simplified) {
        PS_OUTPUT output = (PS_OUTPUT)0.0;
        output.finalColorWithoutSSR = float4(result * g_TonemapScale, 1.0);
        return output;
    }

    // Flashlights and projected textures
    result += inkColor * SampleFlashlight(i.screenUV) * diffuseScale;

    // ^ Diffuse component (multiplies to the final result)
    // -------------------------------------------------------------------------
    // v Specular component (accumulates to the final result)

    // Fresnel term shared by the specular and the reflection, tinted by the thin film interference
    float3 fresnel = CalcFresnel(worldSpaceNormal, viewDir, lerp(FRESNEL_MIN, albedo, params.pbr.metallic));
    [branch]
    if (detail.filmStrength > 0.0) {
        float3 interference = CalcThinFilmInterference(worldSpaceNormal, viewDir, detail.filmThickness);
        fresnel *= lerp(1.0, interference, detail.filmStrength);
    }

#ifdef g_PhongEnabled
    float  phongExponent = lerp(PHONG_EXPONENT_MIN, PHONG_EXPONENT_MAX, params.pbr.roughness);
    float3 phongSpecular = EvaluateGeometryPhong(i, light, worldSpaceNormal, viewDir, phongExponent, shadingBasis);
    phongSpecular *= fresnel;
    phongSpecular *= ambientOcclusion;
    phongSpecular *= params.pbr.specularScale;
    phongSpecular *= GEOMETRY_LIGHT_SCALE;
    result += phongSpecular;
#endif

#ifdef g_RimEnabled
    float3 worldMeshNormal = i.worldTransform[2];
    float rimExponent = lerp(RIM_EXPONENT_MIN, RIM_EXPONENT_MAX, params.pbr.roughness);
    float rimNormalDotViewDir = saturate(dot(worldMeshNormal, viewDir));
    float rimScale = saturate(pow(1.0 - rimNormalDotViewDir, rimExponent));
    rimScale *= lerp(RIM_METALIC_MIN, RIM_METALIC_MAX, params.pbr.metallic);
    rimScale *= lerp(RIM_ROUGHNESS_MIN, RIM_ROUGHNESS_MAX, params.pbr.roughness);
    rimScale *= saturate(
        (RIMLIGHT_FADE_MAX - i.clipZ) /
        (RIMLIGHT_FADE_MAX - RIMLIGHT_FADE_MIN));

    float3 rimLighting = GeometryRimLightColor(light);
    rimLighting = lerp(rimLighting, albedo, params.pbr.metallic);
    rimLighting *= min(rimScale, RIMLIGHT_MAX_SCALE);
    rimLighting *= params.pbr.specularScale;
    rimLighting *= GEOMETRY_LIGHT_SCALE;
    result += rimLighting;
#endif

#ifdef g_EnvmapEnabled
    float3 reflectDir    = reflect(-viewDir, worldSpaceNormal);
    // Rougher surfaces read the coarser mip levels of the envmap
    float3 envmapSample  = texCUBElod(Envmap, float4(reflectDir, params.pbr.roughness * ENVMAP_LOD_MAX)).rgb * g_EnvmapScale;
    float3 envmapAlbedo  = lerp(float3(1.0, 1.0, 1.0), albedo, params.pbr.metallic);
    float3 reflectionWeight = envmapAlbedo;
    reflectionWeight *= fresnel;
    reflectionWeight *= ambientOcclusion;
    reflectionWeight *= params.pbr.specularScale;
#endif

    // ^ Specular component (accumulates to the final result)
    // -------------------------------------------------------------------------
    PS_OUTPUT output = {
        { result, 1.0 },
        {
            EncodeOctahedralUnitVector(worldSpaceNormal),
            EncodeOctahedralUnitVector(i.worldTransform[2])
        },
        { reflectionWeight, params.height },
        { envmapSample, params.pbr.roughness }
    };
    return output;
}
