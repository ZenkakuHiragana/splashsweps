
struct VS_INPUT {
    float4 pos      : POSITION0;
    float2 uv       : TEXCOORD0;
    float3 normal   : NORMAL0;
    float3 color    : COLOR0;
};

struct VS_OUTPUT {
    float4 pos                     : POSITION;
    float3 color                   : COLOR0;
    float4 vWorldPos_BinormalX     : TEXCOORD0;
    float4 vWorldNormal_BinormalY  : TEXCOORD1;
    float4 vWorldTangent_BinormalZ : TEXCOORD2;
    float4 vLightAtten             : TEXCOORD3;
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
const int g_nLightCountRegister : register(i0);
#define g_nLightCount g_nLightCountRegister.x
LightInfo cLightInfo[4] : register(c27);

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

VS_OUTPUT main(const VS_INPUT v) {
    VS_OUTPUT output;

    // Choose an arbitrary vector that is not parallel to the normal
    float3 up = abs(v.normal.z) < 0.999 ? float3(0.0, 0.0, 1.0) : float3(0.0, 1.0, 0.0);
    float3 tangent = normalize(cross(up, v.normal));
    float3 binormal = normalize(cross(v.normal, tangent));

    output.pos = mul(float4(v.pos.xyz, 1.0), cModelViewProj);
    output.color = DoLighting(v.pos.xyz, v.normal, true);
    output.vWorldPos_BinormalX.xyz     = v.pos.xyz;
    output.vWorldNormal_BinormalY.xyz  = v.normal;
    output.vWorldTangent_BinormalZ.xyz = tangent;
    output.vWorldPos_BinormalX.w       = binormal.x;
    output.vWorldNormal_BinormalY.w    = binormal.y;
    output.vWorldTangent_BinormalZ.w   = binormal.z;
    output.vLightAtten.x = VertexAtten(v.pos.xyz, 0);
    output.vLightAtten.y = VertexAtten(v.pos.xyz, 1);
    output.vLightAtten.z = VertexAtten(v.pos.xyz, 2);
    output.vLightAtten.w = VertexAtten(v.pos.xyz, 3);
    return output;
}
