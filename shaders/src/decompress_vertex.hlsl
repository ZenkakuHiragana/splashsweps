
// We're testing 2 normal compression methods
// One compressed normals+tangents into a SHORT2 each (8 bytes total)
// The other compresses them together, into a single UBYTE4 (4 bytes total)
// FIXME: pick one or the other, compare lighting quality in important cases
#define COMPRESSED_NORMALS_SEPARATETANGENTS_SHORT2 0
#define COMPRESSED_NORMALS_COMBINEDTANGENTS_UBYTE4 1
// #define COMPRESSED_NORMALS_TYPE COMPRESSED_NORMALS_SEPARATETANGENTS_SHORT2
#define COMPRESSED_NORMALS_TYPE COMPRESSED_NORMALS_COMBINEDTANGENTS_UBYTE4

float3 mul3x3(float3 v, float3x3 m) {
    return float3(dot(v, transpose(m)[0]), dot(v, transpose(m)[1]), dot(v, transpose(m)[2]));
}

float3 mul4x3(float4 v, float4x3 m) {
    return float3(dot(v, transpose(m)[0]), dot(v, transpose(m)[1]), dot(v, transpose(m)[2]));
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
    float fOne          = 1.0f;
    float4 ztztSignBits = (inputNormal - 128.0f) < 0;                    // sign bits for zs and binormal (1 or 0)  set-less-than (slt) asm instruction
    float4 xyxyAbs      = abs(inputNormal - 128.0f) - ztztSignBits;      // 0..127
    float4 xyxySignBits = (xyxyAbs - 64.0f) < 0;                         // sign bits for xs and ys (1 or 0)
    float4 normTan      = (abs(xyxyAbs - 64.0f) - xyxySignBits) / 63.0f; // abs({nX, nY, tX, tY})
    outputNormal.xy     = normTan.xy;                                    // abs({nX, nY, __, __})
    outputTangent.xy    = normTan.zw;                                    // abs({tX, tY, __, __})

    float4 xyxySigns    = 1 - 2 * xyxySignBits;                     // Convert sign bits to signs
    float4 ztztSigns    = 1 - 2 * ztztSignBits;                     // ( [1,0] -> [-1,+1] )

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
