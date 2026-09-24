const float4x4 cModelViewProj : register(c4);
float4 main(float3 v : POSITION0) : POSITION0 {
    return mul(float4(v, 1.0), cModelViewProj);
}
