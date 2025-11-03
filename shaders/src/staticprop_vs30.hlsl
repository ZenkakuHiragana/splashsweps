// #define COMPRESSED_VERTS

// We're testing 2 normal compression methods
// One compressed normals+tangents into a SHORT2 each (8 bytes total)
// The other compresses them together, into a single UBYTE4 (4 bytes total)
// FIXME: pick one or the other, compare lighting quality in important cases
#define COMPRESSED_NORMALS_SEPARATETANGENTS_SHORT2 0
#define COMPRESSED_NORMALS_COMBINEDTANGENTS_UBYTE4 1
// #define COMPRESSED_NORMALS_TYPE COMPRESSED_NORMALS_SEPARATETANGENTS_SHORT2
#define COMPRESSED_NORMALS_TYPE COMPRESSED_NORMALS_COMBINEDTANGENTS_UBYTE4

struct VS_INPUT {
    float4 pos         : POSITION0;
    float2 uv          : TEXCOORD0;
    float4 normal      : NORMAL0;
    float4 color       : COLOR0;
    float4 boneWeights : BLENDWEIGHT;
    float4 boneIndices : BLENDINDICES;
    float4 tangentS    : TANGENT0;
    float4 tangentT    : BINORMAL0;
};

struct VS_OUTPUT {
    float4 pos                     : POSITION;
    float3 diffuse                 : COLOR0;
    float2 uv                      : TEXCOORD0;
    float4 vWorldPos_BinormalX     : TEXCOORD1;
    float4 vWorldNormal_BinormalY  : TEXCOORD2;
    float4 vWorldTangent_BinormalZ : TEXCOORD3;
    float4 vLightAtten             : TEXCOORD4;
};

struct LightInfo {
    float4 color; // {xyz} is color w is light type code (see comment below)
    float4 dir;   // {xyz} is dir   w is light type code
    float4 pos;
    float4 spotParams;
    float4 atten;
};

const float3 cAmbientCubeX[2] : register(c21);
const float3 cAmbientCubeY[2] : register(c23);
const float3 cAmbientCubeZ[2] : register(c25);
const float4x4 cModelViewProj : register(c4);
const float4x4 cViewProj      : register(c8);
const float4x3 cModel[16]     : register(c48);
const int g_nLightCountRegister : register(i0);
#define g_nLightCount g_nLightCountRegister.x
LightInfo cLightInfo[4] : register(c27);

float3 mul3x3(float3 v, float3x3 m) {
    return float3(dot(v, transpose(m)[0]), dot(v, transpose(m)[1]), dot(v, transpose(m)[2]));
}

float3 mul4x3(float4 v, float4x3 m) {
    return float3(dot(v, transpose(m)[0]), dot(v, transpose(m)[1]), dot(v, transpose(m)[2]));
}

float3 AmbientLight(const float3 worldNormal) {
    float3 nSquared = worldNormal * worldNormal;
    int3 isNegative = (worldNormal < 0.0);
    return nSquared.x * cAmbientCubeX[isNegative.x] +
           nSquared.y * cAmbientCubeY[isNegative.y] +
           nSquared.z * cAmbientCubeZ[isNegative.z];
}

float SoftenCosineTerm(float flDot) {
    return (flDot + (flDot * flDot)) * 0.5;
}

float CosineTerm(const float3 worldPos, const float3 worldNormal, int lightNum, bool bHalfLambert) {
    // Calculate light direction assuming this is a point or spot
    float3 lightDir = normalize(cLightInfo[lightNum].pos.xyz - worldPos);

    // Select the above direction or the one in the structure, based upon light type
    lightDir = lerp(lightDir, -cLightInfo[lightNum].dir.xyz, cLightInfo[lightNum].color.w);

    // compute N dot L
    float NDotL = dot(worldNormal, lightDir);

    if (bHalfLambert) {
        NDotL = NDotL * 0.5 + 0.5;
        NDotL = NDotL * NDotL;
    }
    else {
        NDotL = max(0.0, NDotL);
        NDotL = SoftenCosineTerm(NDotL);
    }
    return NDotL;
}

float VertexAtten(const float3 worldPos, int lightNum) {
    // Get light direction
    float3 lightDir = cLightInfo[lightNum].pos.xyz - worldPos;

    // Get light distance squared.
    float lightDistSquared = dot(lightDir, lightDir);

    // Get 1 / lightDistance
    float ooLightDist = rsqrt(lightDistSquared);

    // Normalize light direction
    lightDir *= ooLightDist;

    float3 vDist = dst(lightDistSquared, ooLightDist).xyz;
    float flDistanceAtten = 1.0 / dot(cLightInfo[lightNum].atten.xyz, vDist);

    // Spot attenuation
    float flCosTheta = dot(cLightInfo[lightNum].dir.xyz, -lightDir);
    float flSpotAtten = (flCosTheta - cLightInfo[lightNum].spotParams.z) * cLightInfo[lightNum].spotParams.w;
    flSpotAtten = max(0.0001f, flSpotAtten);
    flSpotAtten = pow(flSpotAtten, cLightInfo[lightNum].spotParams.x);
    flSpotAtten = saturate(flSpotAtten);

    // Select between point and spot
    float flAtten = lerp(flDistanceAtten, flDistanceAtten * flSpotAtten, cLightInfo[lightNum].dir.w);

    // Select between above and directional (no attenuation)
    return lerp(flAtten, 1.0, cLightInfo[lightNum].color.w);
}

float3 DoLightInternal(const float3 worldPos, const float3 worldNormal, int lightNum, bool bHalfLambert) {
    return cLightInfo[lightNum].color.xyz *
        CosineTerm(worldPos, worldNormal, lightNum, bHalfLambert) *
        VertexAtten(worldPos, lightNum);
}

float3 DoLighting(const float3 worldPos, const float3 worldNormal, bool bHalfLambert) {
    float3 linearColor = float3(0.0, 0.0, 0.0);
    for (int i = 0; i < g_nLightCount; i++) {
        linearColor += DoLightInternal(worldPos, worldNormal, i, bHalfLambert);
    }

    linearColor += AmbientLight(worldNormal); // ambient light is already remapped
    return linearColor;
}

//-----------------------------------------------------------------------------------
// Decompress a normal from two-component compressed format
// We expect this data to come from a signed SHORT2 stream in the range of -32768..32767
//
// -32678 and 0 are invalid encodings
// w contains the sign to use in the cross product when generating a binormal
void DecompressShort2Tangent(float2 inputTangent, out float4 outputTangent) {
    float2 ztSigns   = sign(inputTangent); // sign bits for z and tangent (+1 or -1)
    float2 xyAbs     = abs(inputTangent);  // 1..32767
    outputTangent.xy = (xyAbs - 16384.0f) / 16384.0f; // x and y
    outputTangent.z  = ztSigns.x * sqrt(saturate(1.0f - dot(outputTangent.xy, outputTangent.xy)));
    outputTangent.w  = ztSigns.y;
}

//-----------------------------------------------------------------------------------
// Same code as DecompressShort2Tangent, just one returns a float4, one a float3
void DecompressShort2Normal(float2 inputNormal, out float3 outputNormal) {
    float4 result;
    DecompressShort2Tangent(inputNormal, result);
    outputNormal = result.xyz;
}

//-----------------------------------------------------------------------------------
// Decompress normal+tangent together
void DecompressShort2NormalTangent(
    float2 inputNormal, float2 inputTangent,
    out float3 outputNormal, out float4 outputTangent) {
    // FIXME: if we end up sticking with the SHORT2 format, pack the normal and tangent into a single SHORT4 element
    //        (that would make unpacking normal+tangent here together much cheaper than the sum of their parts)
    DecompressShort2Normal(inputNormal, outputNormal);
    DecompressShort2Tangent(inputTangent, outputTangent);
}

//=======================================================================================
// Decompress a normal and tangent from four-component compressed format
// We expect this data to come from an unsigned UBYTE4 stream in the range of 0..255
// The final vTangent.w contains the sign to use in the cross product when generating a binormal
void DecompressUByte4NormalTangent(float4 inputNormal,
    out float3 outputNormal,    // {nX, nY, nZ}
    out float4 outputTangent) { // {tX, tY, tZ, sign of binormal}
    float fOne   = 1.0f;
    float4 ztztSignBits = (inputNormal - 128.0f) < 0;                    // sign bits for zs and binormal (1 or 0)  set-less-than (slt) asm instruction
    float4 xyxyAbs      = abs(inputNormal - 128.0f) - ztztSignBits;      // 0..127
    float4 xyxySignBits = (xyxyAbs - 64.0f) < 0;                         // sign bits for xs and ys (1 or 0)
    float4 normTan      = (abs(xyxyAbs - 64.0f) - xyxySignBits) / 63.0f; // abs({nX, nY, tX, tY})
    outputNormal.xy     = normTan.xy;                                    // abs({nX, nY, __, __})
    outputTangent.xy    = normTan.zw;                                    // abs({tX, tY, __, __})

    float4 xyxySigns    = 1 - 2*xyxySignBits;                       // Convert sign bits to signs
    float4 ztztSigns    = 1 - 2*ztztSignBits;                       // ( [1,0] -> [-1,+1] )

    outputNormal.z      = 1.0f - outputNormal.x - outputNormal.y;   // Project onto x+y+z=1
    outputNormal.xyz    = normalize(outputNormal.xyz);              // Normalize onto unit sphere
    outputNormal.xy    *= xyxySigns.xy;                             // Restore x and y signs
    outputNormal.z     *= ztztSigns.x;                              // Restore z sign

    outputTangent.z     = 1.0f - outputTangent.x - outputTangent.y; // Project onto x+y+z=1
    outputTangent.xyz   = normalize(outputTangent.xyz);             // Normalize onto unit sphere
    outputTangent.xy   *= xyxySigns.zw;                             // Restore x and y signs
    outputTangent.z    *= ztztSigns.z;                              // Restore z sign
    outputTangent.w     = ztztSigns.w;                              // Binormal sign
}

void DecompressVertex_NormalTangent(
    float4 inputNormal, float4 inputTangent,
    out float3 outputNormal, out float4 outputTangent) {
#ifdef COMPRESSED_VERTS
    if (COMPRESSED_NORMALS_TYPE == COMPRESSED_NORMALS_SEPARATETANGENTS_SHORT2) {
        DecompressShort2NormalTangent(inputNormal.xy, inputTangent.xy, outputNormal, outputTangent);
    } else { // (COMPRESSED_NORMALS_TYPE == COMPRESSED_NORMALS_COMBINEDTANGENTS_UBYTE4)
        DecompressUByte4NormalTangent(inputNormal, outputNormal, outputTangent);
    }
#else
    outputNormal  = inputNormal.xyz;
    outputTangent = inputTangent;
#endif
}

float4 DecompressBoneWeights(const float4 weights) {
    float4 result = weights;
#ifdef COMPRESSED_VERTS
    // Decompress from SHORT2 to float. In our case, [-1, +32767] -> [0, +1]
    // NOTE: we add 1 here so we can divide by 32768 - which is exact (divide by 32767 is not).
    //       This avoids cracking between meshes with different numbers of bone weights.
    //       We use SHORT2 instead of SHORT2N for a similar reason - the GPU's conversion
    //       from [-32768,+32767] to [-1,+1] is imprecise in the same way.
    result += 1;
    result /= 32768;
#endif
    return result;
}

// Is it worth keeping SkinPosition and SkinPositionAndNormal around since the optimizer
// gets rid of anything that isn't used?
void SkinPositionNormalAndTangentSpace(
    bool bSkinning,
    const float4 modelPos,
    const float3 modelNormal,
    const float4 modelTangentS,
    const float4 boneWeights,
    const float4 fBoneIndices,
    out float3 worldPos,      out float3 worldNormal,
    out float3 worldTangentS, out float3 worldTangentT) {
    int3 boneIndices = D3DCOLORtoUBYTE4(fBoneIndices).xyz;
    if (bSkinning) { // skinning - always three bones
        float4x3 mat1 = cModel[boneIndices[0]];
        float4x3 mat2 = cModel[boneIndices[1]];
        float4x3 mat3 = cModel[boneIndices[2]];

        float3 weights = DecompressBoneWeights(boneWeights).xyz;
        weights[2] = 1 - (weights[0] + weights[1]);

        float4x3 blendMatrix = mat1 * weights[0] + mat2 * weights[1] + mat3 * weights[2];
        worldPos = mul4x3(modelPos, blendMatrix);
        worldNormal = mul3x3(modelNormal, (const float3x3)blendMatrix);
        worldTangentS = mul3x3((float3)modelTangentS, (const float3x3)blendMatrix);
    } else {
        worldPos = mul4x3(modelPos, cModel[0]);
        worldNormal = mul3x3(modelNormal, (const float3x3)cModel[0]);
        worldTangentS = mul3x3((float3)modelTangentS, (const float3x3)cModel[0]);
    }
    worldTangentT = cross(worldNormal, worldTangentS) * modelTangentS.w;
}

void SkinPosition(
    bool bSkinning, const float4 modelPos,
    const float4 boneWeights, float4 fBoneIndices,
    out float3 worldPos) {
    int3 boneIndices = D3DCOLORtoUBYTE4(fBoneIndices).xyz;
    if (bSkinning) { // skinning - always three bones
        float4x3 mat1 = cModel[boneIndices[0]];
        float4x3 mat2 = cModel[boneIndices[1]];
        float4x3 mat3 = cModel[boneIndices[2]];
        float3 weights = DecompressBoneWeights(boneWeights).xyz;
        weights[2] = 1 - (weights[0] + weights[1]);
        float4x3 blendMatrix = mat1 * weights[0] + mat2 * weights[1] + mat3 * weights[2];
        worldPos = mul4x3(modelPos, blendMatrix);
    } else {
        worldPos = mul4x3(modelPos, cModel[0]);
    }
}

VS_OUTPUT main(const VS_INPUT v) {
    VS_OUTPUT output;

    // Choose an arbitrary vector that is not parallel to the normal
    float3 up = abs(v.normal.z) < 0.999 ? float3(0.0, 0.0, 1.0) : float3(0.0, 1.0, 0.0);
    float3 worldPos = v.pos.xyz;
    float3 normal = v.normal.xyz;
    float4 tangent = { normalize(cross(up, normal)), 1.0 };
    float3 binormal = normalize(cross(normal, tangent.xyz));
    float3 worldNormal = normal;
    float3 worldTangentS = tangent.xyz;
    float3 worldTangentT = binormal;

#ifdef COMPRESSED_VERTS
    DecompressVertex_NormalTangent(v.normal, v.tangentS, normal, tangent);
    SkinPositionNormalAndTangentSpace(
        true, v.pos, normal, tangent,
        v.boneWeights, v.boneIndices,
        worldPos, worldNormal, worldTangentS, worldTangentT);
    output.pos = mul(float4(worldPos, 1.0), cViewProj);
#else
    output.pos = mul(float4(worldPos, 1.0), cModelViewProj);
#endif

    output.uv = v.uv;
    output.diffuse = DoLighting(worldPos, worldNormal, true);
    output.vWorldPos_BinormalX.xyz     = worldPos;
    output.vWorldNormal_BinormalY.xyz  = worldNormal;
    output.vWorldTangent_BinormalZ.xyz = worldTangentS;
    output.vWorldPos_BinormalX.w       = worldTangentT.x;
    output.vWorldNormal_BinormalY.w    = worldTangentT.y;
    output.vWorldTangent_BinormalZ.w   = worldTangentT.z;
    output.vLightAtten.x = VertexAtten(worldPos, 0);
    output.vLightAtten.y = VertexAtten(worldPos, 1);
    output.vLightAtten.z = VertexAtten(worldPos, 2);
    output.vLightAtten.w = VertexAtten(worldPos, 3);
    return output;
}
