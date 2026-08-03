float2 OctSignNotZero(float2 v) {
    return float2(v.x >= 0.0 ? 1.0 : -1.0, v.y >= 0.0 ? 1.0 : -1.0);
}

float2 EncodeOctahedralUnitVector(float3 v) {
    v *= rcp(abs(v.x) + abs(v.y) + abs(v.z));
    float2 encoded = v.xy;
    if (v.z < 0.0) {
        encoded = (1.0 - abs(encoded.yx)) * OctSignNotZero(encoded);
    }
    return encoded * 0.5 + 0.5;
}

float3 DecodeOctahedralUnitVector(float2 encoded) {
    float2 f = encoded * 2.0 - 1.0;
    float3 v = float3(f, 1.0 - abs(f.x) - abs(f.y));
    if (v.z < 0.0) {
        v.xy = (1.0 - abs(v.yx)) * OctSignNotZero(v.xy);
    }
    return normalize(v);
}
