
// Vertex shader constants
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
    float3 pos     : POSITION0;
    float2 uv      : TEXCOORD0;
    float3 normal  : NORMAL0;
    float3 color   : COLOR0;
    float3 tangent : TANGENT0;
};

struct VS_OUTPUT {
    float4 pos      : POSITION;
    float4 uv_depth : TEXCOORD0;
    float4 data[8]  : TEXCOORD1;
};

VS_OUTPUT main(const VS_INPUT v) {
    const float4x4 cModelViewProj = {
        c[4].x, c[5].x, c[6].x, c[7].x,
        c[4].y, c[5].y, c[6].y, c[7].y,
        c[4].z, c[5].z, c[6].z, c[7].z,
        c[4].w, c[5].w, c[6].w, c[7].w,
    };
    VS_OUTPUT output;
    output.pos = mul(float4(v.pos, 1.0), cModelViewProj);
    output.uv_depth.xy  = v.uv;
    output.uv_depth.zw = output.pos.zw;
    const int VERTEX_CONST_OFFSET = 52;
    for (int i = 0; i < 8; ++i) {
        output.data[i] = c[i + VERTEX_CONST_OFFSET];
    }
    return output;
}
