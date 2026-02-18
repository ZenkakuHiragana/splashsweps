
// Data texture layout
#define ID_COLOR_ALPHA        0
#define ID_TINT_GEOMETRYPAINT 1
#define ID_EDGE               2
#define ID_HEIGHT_MAXLAYERS   3
#define ID_MATERIAL_REFRACT   4
#define ID_MISC               5
#define ID_DETAILS_BUMPBLEND  6
#define ID_OTHERS             7

// [0.0, 1.0] --> [-1.0, +1.0]
#define TO_SIGNED(x) ((x) * 2.0 - 1.0)

// Safe rcp that avoids division by zero
#define SAFERCP(x) (TO_SIGNED(step(0.0, x)) * rcp(max(abs(x), 1.0e-21)))

static const float HEIGHT_TO_HAMMER_UNITS = 32.0;
static const float LOD_DISTANCE = 4096.0;
static const float4 GROUND_PROPERTIES[8] = {
    { 1.0, 1.0, 1.0,  1.0 },
    { 1.0, 1.0, 1.0,  0.0 },
    { 1.0, 1.0, 1.0,  1.0 },
    { 1.0, 1.0, 0.75, 0.5 },
    { 0.0, 0.0, 0.0,  1.0 },
    { 0.0, 1.0, 1.0,  1.0 },
    { 0.0, 1.0, 1.0,  1.0 },
    { 0.0, 0.0, 0.0,  0.0 },
};
