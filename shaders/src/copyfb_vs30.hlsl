struct VS {
    float4 pos : POSITION0;
    float2 uv  : TEXCOORD0;
};

// DrawQuad supplies a unit square in the existing 3D context. Bypass the
// camera matrices: w = 1 makes these clip coordinates also NDC coordinates.
VS main(const VS v) {
    VS w;
    w.pos = float4(v.pos.x * 2.0 - 1.0, 1.0 - v.pos.y * 2.0, 0.5, 1.0);
    w.uv = v.pos.xy;
    return w;
}
