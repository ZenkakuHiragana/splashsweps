
// Vertex-input probe for Screenspace_General_8Tex.
// TEXCOORD7 carries clip-space position for stable on-screen placement.
// TEXCOORD6.w selects the payload page copied to the pixel shader.
// c3.w > 0 enables vertex-payload display in the pixel shader.
// c0  cConstants0
// c1  cConstants1
// c2  cEyePos_WaterHeightW
// c3  cObsoleteLightIndex
// c4  cModelViewProj column 0
// c5  cModelViewProj column 1
// c6  cModelViewProj column 2
// c7  cModelViewProj column 3
// c8  cViewProj column 0
// c9  cViewProj column 1
// c10 cViewProj column 2
// c11 cViewProj column 3
// c12 SHADER_SPECIFIC_CONST_12
// c13 cFlexScale
// c14 SHADER_SPECIFIC_CONST_10
// c15 SHADER_SPECIFIC_CONST_11
// c16 cFogParams
// c17 cViewModel column 0
// c18 cViewModel column 1
// c19 cViewModel column 2
// c20 cViewModel column 3
// c21 cAmbientCubeX[0]
// c22 cAmbientCubeX[1]
// c23 cAmbientCubeY[0]
// c24 cAmbientCubeY[1]
// c25 cAmbientCubeZ[0]
// c26 cAmbientCubeZ[1]
// c27 cLightInfo[0].color
// c28 cLightInfo[0].dir
// c29 cLightInfo[0].pos
// c30 cLightInfo[0].spotParams
// c31 cLightInfo[0].atten
// c32 cLightInfo[1].color
// c33 cLightInfo[1].dir
// c34 cLightInfo[1].pos
// c35 cLightInfo[1].spotParams
// c36 cLightInfo[1].atten
// c37 cLightInfo[2].color
// c38 cLightInfo[2].dir
// c39 cLightInfo[2].pos
// c40 cLightInfo[2].spotParams
// c41 cLightInfo[2].atten
// c42 cLightInfo[3].color
// c43 cLightInfo[3].dir
// c44 cLightInfo[3].pos
// c45 cLightInfo[3].spotParams
// c46 cLightInfo[3].atten
// c47 cModulationColor
// c48 SHADER_SPECIFIC_CONST_0
// c49 SHADER_SPECIFIC_CONST_1
// c50 SHADER_SPECIFIC_CONST_2
// c51 SHADER_SPECIFIC_CONST_3
// c52 SHADER_SPECIFIC_CONST_4
// c53 SHADER_SPECIFIC_CONST_5
// c54 SHADER_SPECIFIC_CONST_6
// c55 SHADER_SPECIFIC_CONST_7
// c56 SHADER_SPECIFIC_CONST_8
// c57 SHADER_SPECIFIC_CONST_9
// c58 cModel[0] column 0
// c59 cModel[0] column 1
// c60 cModel[0] column 2
// c61 cModel[0] column 3

#define cFogParams c[16]
#define cFogMaxDensity cFogParams.z
#define cAmbientCubeX1 c[21]

const float4 c[128] : register(c0);
struct VS_INPUT {
    float3 pos         : POSITION0;
    float4 texcoord0   : TEXCOORD0;
    float4 texcoord1   : TEXCOORD1;
    float4 texcoord2   : TEXCOORD2;
    float4 texcoord3   : TEXCOORD3;
    float4 texcoord4   : TEXCOORD4;
    float4 texcoord5   : TEXCOORD5;
    float4 texcoord6   : TEXCOORD6;
    float4 texcoord7   : TEXCOORD7;
    float3 normal      : NORMAL0;
    float4 color0      : COLOR0;
    float4 color1      : COLOR1;
    float4 tangent     : TANGENT0;
    float3 binormal    : BINORMAL0;
    float4 boneWeights : BLENDWEIGHT;
    float4 boneIndices : BLENDINDICES;
};

struct VS_OUTPUT {
    float4 pos      : POSITION;
    float4 uv_depth : TEXCOORD0;
    float4 data[8]  : TEXCOORD1;
};

VS_OUTPUT main(const VS_INPUT v) {
    VS_OUTPUT output = (VS_OUTPUT)0;
    float page = floor(v.texcoord6.w + 0.5);
    output.pos = float4(v.texcoord7.x, v.texcoord7.y, v.texcoord7.z, max(v.texcoord7.w, 1e-6));
    output.uv_depth.xy  = v.texcoord0.xy;
    output.uv_depth.zw = output.pos.zw;

    if (page < 0.5) {
        output.data[0] = float4(v.pos, 1.0);
        output.data[1] = v.texcoord0;
        output.data[2] = v.texcoord1;
        output.data[3] = v.texcoord2;
        output.data[4] = v.texcoord3;
        output.data[5] = v.texcoord4;
        output.data[6] = v.texcoord5;
        output.data[7] = v.texcoord6;
    }
    else if (page < 1.5) {
        output.data[0] = v.texcoord7;
        output.data[1] = float4(v.normal, 1.0);
        output.data[2] = v.color0;
        output.data[3] = v.color1;
        output.data[4] = v.tangent;
        output.data[5] = float4(v.binormal, 1.0);
        output.data[6] = v.boneWeights;
        output.data[7] = v.boneIndices;
    }
    else if (page < 2.5) {
        output.data[0] = c[0];
        output.data[1] = c[1];
        output.data[2] = c[2];
        output.data[3] = c[3];
        output.data[4] = c[16];
        output.data[5] = c[47];
        output.data[6] = c[58];
        output.data[7] = c[59];
    }
    else if (page < 3.5) {
        output.data[0] = c[60];
        output.data[1] = c[61];
        output.data[2] = c[4];
        output.data[3] = c[5];
        output.data[4] = c[6];
        output.data[5] = c[7];
        output.data[6] = c[8];
        output.data[7] = c[9];
    }
    else {
        output.data[0] = c[10];
        output.data[1] = c[11];
        output.data[2] = c[12];
        output.data[3] = c[13];
        output.data[4] = c[14];
        output.data[5] = c[15];
        output.data[6] = c[17];
        output.data[7] = c[18];
    }
    return output;
}
