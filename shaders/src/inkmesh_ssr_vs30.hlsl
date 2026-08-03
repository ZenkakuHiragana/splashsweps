struct VS_INPUT {
    float3 pos : POSITION;
};

const float4x4 cModelViewProj : register(c4);

float4 main(const VS_INPUT v) : POSITION0 {
    return mul(float4(v.pos, 1.0), cModelViewProj);
}
