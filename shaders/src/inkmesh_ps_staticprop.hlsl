// Ink Mesh Pixel Shader for SplashSWEPs, static prop part; see inkmesh_ps_ink.hlsl
// Draws the ink on the model of a static prop, which reads the ink map by the box projection of its bounding box.
// The previous VertexLitGeneric draw of the same prop leaves its lighting in the constants.

#include "inkmesh_ps_ink.hlsl"

// See staticprop_vs30.hlsl for VS_OUTPUT
struct PS_INPUT {
    float4 screenPos         : VPOS;
    float  face              : VFACE; // Negative on the back faces, drawn for $nocull materials
    float4 worldPos_ClipW    : TEXCOORD0;
    float4 worldNormal_ClipZ : TEXCOORD1;
    float2 modelUV           : TEXCOORD2;
    float4 lightAtten        : TEXCOORD3;
    float3 ambientXPos       : TEXCOORD4;
    float3 ambientXNeg       : TEXCOORD5;
    float3 ambientYPos       : TEXCOORD6;
    float3 ambientYNeg       : TEXCOORD7;
    float3 ambientZPos       : TEXCOORD8;
    float3 ambientZNeg       : TEXCOORD9;
};

struct UVs {
    float2 base;
    float2 bump;
    float2 screen;
    float  edgefade;
    float  depth;
};

struct PsVertexInfo {
    float2   screenUV;
    float3   worldPos;
    float    clipZ;
    float    clipW;
    float2   minUV;
    float2   maxUV;
    float3   inkUV;
    float2   worldUV;        // Model UV
    float3x3 worldTransform; // Rows: world gradients of the model texels U and V, and the mesh normal
    float3x3 inkTransform;   // Rows: world gradients of the ink map U and V, and the mesh normal
    float4   lightAtten;     // Attenuation of the four lights
    float3   ambientCube[6]; // +X, -X, +Y, -Y, +Z, -Z
};

// Rendering for the water reflection is not used for static props
static const bool g_Simplified = false;

// Light the flashlights cast on the static props, drawn with the depth buffer of the frame.
// See DrawStaticPropsFlashlight in inkrenderer.lua.
sampler StaticPropFlashlight : register(s5);

// Written by ss.SetupStaticProps. c0.yzw, c2.zw, and c11..c14.w are unused.
static const float  g_PackedRotatedWidth = c1.y;  // Width of the packed rectangle in Hammer units if rotated, 0 otherwise
static const float  g_AlphaTestReference = c1.w;  // $basetexture alpha below this has no ink, 0 to draw everywhere
static const float2 g_PackedOrigin       = c2.xy; // Origin of the packed rectangle in Hammer units
static const float3 g_BoxSize            = c18.xyz;
static const float  g_FaceMargin         = c18.w; // Margin of each face cell per side in Hammer units

// Inset of the clip range of each face in ink map UV, as PaintableSurface.SetupStaticProps and inkmesh_vs30.hlsl do
static const float RT_BILINEAR_GUARD_PIXELS = c0.x; // ss.RT_BILINEAR_GUARD_PIXELS
static const float g_ClipGuard = 0.5 * RT_BILINEAR_GUARD_PIXELS * g_RTSize.x;

// World to the bounding box, whose origin is the minimum corner and whose axes are permuted for the unwrap pattern
static const float4 LocalTWorld[3] = { c15, c16, c17 };

//  Leftover from VertexLitGeneric.
//  We store four light colors and positions in an
//  array of three of these structures like so:
//
//       x      y      z      w
//    +------+------+------+------+
//    |       L0.rgb       |      |
//    +------+------+------+      |
//    |       L0.pos       |  L3  |
//    +------+------+------+  rgb |
//    |       L1.rgb       |      |
//    +------+------+------+------+
//    |       L1.pos       |      |
//    +------+------+------+      |
//    |       L2.rgb       |  L3  |
//    +------+------+------+  pos |
//    |       L2.pos       |      |
//    +------+------+------+------+
//
const float4 c20 : register(c20);
const float4 c21 : register(c21);
const float4 c22 : register(c22);
const float4 c23 : register(c23);
const float4 c24 : register(c24);
const float4 c25 : register(c25);
static const float3 LightColors[4]    = { c20.rgb, c22.rgb, c24.rgb, float3(c20.w, c21.w, c22.w) };
static const float3 LightPositions[4] = { c21.xyz, c23.xyz, c25.xyz, float3(c23.w, c24.w, c25.w) };

// Cells of the six faces in the packed rectangle (not rotated). m = g_FaceMargin.
//            sz+2m   sx+2m
//          +-------+-------+
//   sx+2m  |   0   |       |
//          +-------+-------+
//   sy+2m  |   1   |   4   |
//          +-------+-------+
//   sx+2m  |   2   |       |
//          +-------+-------+
//   sy+2m  |   3   |   5   |
//          +-------+-------+
// Selects the face of the bounding box from the mesh normal, and projects the position onto it.
void MapToInkMap(const float3 worldPos, const float3 worldNormal, inout PsVertexInfo v) {
    float3 localPos = {
        dot(float4(worldPos, 1.0), LocalTWorld[0]),
        dot(float4(worldPos, 1.0), LocalTWorld[1]),
        dot(float4(worldPos, 1.0), LocalTWorld[2]),
    };
    float3 localNormal = {
        dot(worldNormal, LocalTWorld[0].xyz),
        dot(worldNormal, LocalTWorld[1].xyz),
        dot(worldNormal, LocalTWorld[2].xyz),
    };
    float3 absLocalNormal = abs(localNormal);
    float maxAbsComponent = max(absLocalNormal.x, max(absLocalNormal.y, absLocalNormal.z));

    const float3 normals[6] = {
        { 1.0, 0.0, 0.0 }, { 0.0,  1.0, 0.0 }, { 0.0, 0.0,  1.0 },
        {-1.0, 0.0, 0.0 }, { 0.0, -1.0, 0.0 }, { 0.0, 0.0, -1.0 },
    };
    const float3 tangents[6] = {
        normals[4], normals[0], normals[4],
        normals[1], normals[3], normals[1],
    };
    const float3 binormals[6] = {
        cross(normals[0], tangents[0]), cross(normals[1], tangents[1]),
        cross(normals[2], tangents[2]), cross(normals[3], tangents[3]),
        cross(normals[4], tangents[4]), cross(normals[5], tangents[5]),
    };
    const float3 faceOriginCoefficients[6] = {
        { 1, 1, 1 }, { 0, 1, 1 }, { 0, 1, 1 },
        { 0, 0, 1 }, { 1, 0, 1 }, { 0, 0, 0 },
    };
    const float3 uvOffsetCoefficients[6] = {
        { 2, 1, 0 }, { 1, 1, 0 }, { 2, 1, 1 },
        { 1, 0, 0 }, { 0, 0, 0 }, { 1, 0, 1 },
    };

    int faceIndex;
    if (maxAbsComponent == absLocalNormal.x) {
        faceIndex = localNormal.x < 0 ? 3 : 0;
    } else if (maxAbsComponent == absLocalNormal.y) {
        faceIndex = localNormal.y < 0 ? 4 : 1;
    } else {
        faceIndex = localNormal.z < 0 ? 5 : 2;
    }

    // Face UV, its world gradients, and the face size, in Hammer units
    float3 tangent    = tangents[faceIndex];
    float3 binormal   = binormals[faceIndex];
    float3 faceOrigin = g_BoxSize * faceOriginCoefficients[faceIndex];
    float2 faceUV     = { dot(localPos - faceOrigin, tangent), dot(localPos - faceOrigin, binormal) };
    float2 faceSize   = { abs(dot(g_BoxSize, tangent)), abs(dot(g_BoxSize, binormal)) };
    float3 faceGradU  = mul(tangent,  float3x3(LocalTWorld[0].xyz, LocalTWorld[1].xyz, LocalTWorld[2].xyz));
    float3 faceGradV  = mul(binormal, float3x3(LocalTWorld[0].xyz, LocalTWorld[1].xyz, LocalTWorld[2].xyz));

    // Position of the face in the packed rectangle
    float3 cellOffset   = (g_BoxSize + 2.0 * g_FaceMargin) * uvOffsetCoefficients[faceIndex];
    float2 faceUVOrigin = float2(cellOffset.x + cellOffset.y, cellOffset.z) + g_FaceMargin;
    float2 localUV      = faceUVOrigin + faceUV;
    float2 localMin     = faceUVOrigin - g_FaceMargin;
    float2 localMax     = faceUVOrigin + faceSize + g_FaceMargin;

    // Packed rectangle to the ink map, where the rotated one maps (u, v) to (width - v, u)
    bool   isRotated = g_PackedRotatedWidth > 0.0;
    float2 packedUV  = isRotated ? float2(g_PackedRotatedWidth - localUV.y, localUV.x) : localUV;
    float2 packedMin = isRotated ? float2(g_PackedRotatedWidth - localMax.y, localMin.x) : localMin;
    float2 packedMax = isRotated ? float2(g_PackedRotatedWidth - localMin.y, localMax.x) : localMax;
    float3 gradU     = isRotated ? -faceGradV : faceGradU;
    float3 gradV     = isRotated ?  faceGradU : faceGradV;

    // U and V in the cache are V and U in the ink map, as PaintableSurface.Setup and inkmesh_vs30.hlsl do
    float uvPerHU  = rcp(g_InkMapHUPerUV);
    v.inkUV        = float3((g_PackedOrigin + packedUV).yx * uvPerHU, 0.0);
    v.minUV        = (g_PackedOrigin + packedMin).yx * uvPerHU + g_ClipGuard;
    v.maxUV        = (g_PackedOrigin + packedMax).yx * uvPerHU - g_ClipGuard;
    v.inkTransform = float3x3(gradV * uvPerHU, gradU * uvPerHU, worldNormal);
}

PsVertexInfo DecomposeInput(const PS_INPUT i) {
    // No ink where the alpha test of the prop material discards the prop
    clip(tex2D(UnderlayAlbedo, ApplyBaseTransform(i.modelUV)).a - g_AlphaTestReference);

    PsVertexInfo v;
    float3 worldPos    = i.worldPos_ClipW.xyz;
    float3 worldNormal = normalize(i.worldNormal_ClipZ.xyz);
    v.screenUV = (i.screenPos.xy + float2(0.5, 0.5)) * g_FbSize;
    v.worldPos = worldPos;
    v.clipZ    = i.worldNormal_ClipZ.w;
    v.clipW    = i.worldPos_ClipW.w;
    MapToInkMap(worldPos, worldNormal, v);

    // Both faces read the same ink, as MapToInkMap selects the face of the bounding box by the mesh normal.
    // The back faces are shaded with the normal toward the viewer.
    worldNormal *= sign(i.face);
    v.inkTransform[2] = worldNormal;

    // The model has no world gradients of its UV, so take them from the screen-space derivatives
    float3x3 dual   = MakeBasisInverse(ddx(worldPos), ddy(worldPos), worldNormal);
    float2   duvdx  = ddx(i.modelUV);
    float2   duvdy  = ddy(i.modelUV);
    float3   gradU  = duvdx.x * dual[0] + duvdy.x * dual[1];
    float3   gradV  = duvdx.y * dual[0] + duvdy.y * dual[1];
    v.worldUV        = i.modelUV;
    v.worldTransform = float3x3(gradU / g_UnderlayAlbedoSize.x, gradV / g_UnderlayAlbedoSize.y, worldNormal);

    v.lightAtten     = i.lightAtten;
    v.ambientCube[0] = i.ambientXPos;
    v.ambientCube[1] = i.ambientXNeg;
    v.ambientCube[2] = i.ambientYPos;
    v.ambientCube[3] = i.ambientYNeg;
    v.ambientCube[4] = i.ambientZPos;
    v.ambientCube[5] = i.ambientZNeg;
    return v;
}

// Sample $bumpmap of the model
float3 FetchGeometryNormal(const PsVertexInfo i, UVs uv, float3 layerWeights) {
    float2 wuv = ApplyBumpTransform(i.worldUV);
    float3 geometryNormal = tex2Dgrad(UnderlayBumpmap, uv.bump, ddx(wuv), ddy(wuv)).rgb;
    geometryNormal *= 2.0;
    geometryNormal -= 1.0;

    // Handle missing bumpmap (default to flat normal)
    bool hasNoBump = geometryNormal.x == -1.0 &&
                     geometryNormal.y == -1.0 &&
                     geometryNormal.z == -1.0;
    if (hasNoBump) return float3(0.0, 0.0, 1.0);
    return geometryNormal;
}

// Samples $basetexture of the model
GeometryAlbedo FetchGeometryAlbedo(const PsVertexInfo i, const UVs uv) {
    float2 wuv = ApplyBaseTransform(i.worldUV);
    GeometryAlbedo result;
    result.color        = tex2Dgrad(UnderlayAlbedo, uv.base, ddx(wuv), ddy(wuv)).rgb * g_Color;
    result.layerWeights = 0.0;
    return result;
}

// The model has no other UVs to shift
void ApplyGeometryParallax(const PsVertexInfo i, float3 worldOffset, float2 uvOffset, float2 worldUVParallax,
    inout UVs uv) {
}

// Light the static prop receives, from the ambient cube and the four lights
struct GeometryLight {
    float3 diffuse;
};

float3 AmbientLight(const PsVertexInfo i, float3 worldNormal) {
    float3 nSquared = worldNormal * worldNormal;
    return nSquared.x * (worldNormal.x < 0.0 ? i.ambientCube[1] : i.ambientCube[0]) +
           nSquared.y * (worldNormal.y < 0.0 ? i.ambientCube[3] : i.ambientCube[2]) +
           nSquared.z * (worldNormal.z < 0.0 ? i.ambientCube[5] : i.ambientCube[4]);
}

// Half Lambert falloff of the four lights
float HalfLambert(float3 worldNormal, float3 lightDir) {
    float NDotL = saturate(dot(worldNormal, lightDir) * 0.5 + 0.5);
    return NDotL * NDotL;
}

GeometryLight EvaluateGeometryLight(const PsVertexInfo i, const UVs uv, float3 tangentSpaceNormal, float3 worldSpaceNormal) {
    GeometryLight light;
    light.diffuse = AmbientLight(i, worldSpaceNormal);
    [unroll]
    for (int k = 0; k < 4; k++) {
        float3 lightDir = normalize(LightPositions[k] - i.worldPos);
        light.diffuse += LightColors[k] * i.lightAtten[k] * HalfLambert(worldSpaceNormal, lightDir);
    }
    return light;
}

// Specular from the four lights
float3 EvaluateGeometryPhong(const PsVertexInfo i, const GeometryLight light,
    float3 worldSpaceNormal, float3 viewDir, float exponent, float3x3 shadingBasis) {
    float3 specular = 0.0;
    [unroll]
    for (int k = 0; k < 4; k++) {
        float3 lightDir = normalize(LightPositions[k] - i.worldPos);
        specular += LightColors[k] * i.lightAtten[k] * CalcBlinnPhongSpec(worldSpaceNormal, lightDir, viewDir, exponent);
    }
    return specular;
}

// Use the diffuse light as rim light color
float3 GeometryRimLightColor(const GeometryLight light) {
    return light.diffuse;
}

// The light constants are already in the linear scale
#define GEOMETRY_LIGHT_SCALE 1.0

// Light the flashlights cast on the prop at the pixel center screenUV.
float3 SampleFlashlight(float2 screenUV) {
    return tex2Dlod(StaticPropFlashlight, float4(screenUV, 0.0, 0.0)).rgb / g_TonemapScale;
}
