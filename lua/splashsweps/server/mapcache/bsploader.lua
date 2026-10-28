
-- Reads the BSP file of the current map.

---@class ss
local ss = SplashSWEPs
local Binary = ss.import "splashsweps/shared/binary/reader"

---@class ss.BSPLoader
local BSP = ss.module "splashsweps/server/mapcache/bsploader"

---Lump names. most of these are unused in this addon.
---@type table<integer, string>
local LUMP = {
    [1]  = "ENTITIES",
    [2]  = "PLANES",
    [3]  = "TEXDATA",
    [4]  = "VERTEXES",
    [5]  = "VISIBLITY",
    [6]  = "NODES",
    [7]  = "TEXINFO",
    [8]  = "FACES",
    [9]  = "LIGHTING",
    [10] = "OCCLUSION",
    [11] = "LEAFS",
    [12] = "FACEIDS",
    [13] = "EDGES",
    [14] = "SURFEDGES",
    [15] = "MODELS",
    [16] = "WORLDLIGHTS",
    [17] = "LEAFFACES",
    [18] = "LEAFBRUSHES",
    [19] = "BRUSHES",
    [20] = "BRUSHSIDES",
    [21] = "AREAS",
    [22] = "AREAPORTALS",
    [23] = "PORTALS",        -- unused in version 20
    [24] = "CLUSTERS",       --
    [25] = "PORTALVERTS",    --
    [26] = "CLUSTERPORTALS", -- unused in version 20
    [27] = "DISPINFO",
    [28] = "ORIGINALFACES",
    [29] = "PHYSDISP",
    [30] = "PHYSCOLLIDE",
    [31] = "VERTNORMALS",
    [32] = "VERTNORMALINDICES",
    [33] = "DISP_LIGHTMAP_ALPHAS",
    [34] = "DISP_VERTS",
    [35] = "DISP_LIGHMAP_SAMPLE_POSITIONS",
    [36] = "GAME_LUMP",
    [37] = "LEAFWATERDATA",
    [38] = "PRIMITIVES",
    [39] = "PRIMVERTS",
    [40] = "PRIMINDICES",
    [41] = "PAKFILE",
    [42] = "CLIPPORTALVERTS",
    [43] = "CUBEMAPS",
    [44] = "TEXDATA_STRING_DATA",
    [45] = "TEXDATA_STRING_TABLE",
    [46] = "OVERLAYS",
    [47] = "LEAFMINDISTTOWATER",
    [48] = "FACE_MACRO_TEXTURE_INFO",
    [49] = "DISP_TRIS",
    [50] = "PHYSCOLLIDESURFACE",
    [51] = "WATEROVERLAYS",
    [52] = "LIGHTMAPEDGES",
    [53] = "LIGHTMAPPAGEINFOS",
    [54] = "LIGHTING_HDR",              -- only used in version 20+ BSP files
    [55] = "WORLDLIGHTS_HDR",           --
    [56] = "LEAF_AMBIENT_LIGHTING_HDR", --
    [57] = "LEAF_AMBIENT_LIGHTING",     -- only used in version 20+ BSP files
    [58] = "XZIPPAKFILE",
    [59] = "FACES_HDR",
    [60] = "MAP_FLAGS",
    [61] = "OVERLAY_FADES",
    [62] = "OVERLAY_SYSTEM_LEVELS",
    [63] = "PHYSLEVEL",
    [64] = "DISP_MULTIBLEND",
}

---Size of dheader_t in bytes: ident, version, 64 lump_t of 16 bytes, and mapRevision.
local HEADER_SIZE = 4 + 4 + 64 * 16 + 4

---Used for calculating the size of lump structures
local BuiltinTypeSizes = {
    Bool   = 1,
    Byte   = 1,
    Float  = 4,
    Long   = 4,
    SByte  = 1,
    Short  = 2,
    ULong  = 4,
    UShort = 2,
}

---@class ss.Binary.BSP.Header
---@field identifier  integer
---@field version     integer
---@field lumps       ss.Binary.BSP.LumpHeader[]
---@field mapRevision integer
Binary.struct "BSP.Header" {
    "Long           identifier",
    "Long           version",
    "BSP.LumpHeader lumps 64",
    "Long           mapRevision",
}

---@class ss.Binary.BSP.LumpHeader
---@field fileOffset integer
---@field fileLength integer
---@field version    integer
---@field fourCC     integer
Binary.struct "BSP.LumpHeader" {
    ---@param self ss.BinaryStructureDefinition
    ---@param bsp ss.BinaryStringReader
    ---@return ss.Binary.BSP.LumpHeader
    Read = function(self, bsp)
        local fileOffset = bsp:ReadLong()
        local fileLength = bsp:ReadLong()
        local version = bsp:ReadLong()
        local fourCC = bsp:ReadLong()
        if fileOffset < bsp:Tell() or version >= 0x100 then
            -- Left 4 Dead 2 maps have different order
            -- but I don't know how to detemine if this is Left 4 Dead 2 map
            return {
                fileOffset = fileLength,
                fileLength = version,
                version = fileOffset,
                fourCC = fourCC,
            }
        else
            return {
                fileOffset = fileOffset,
                fileLength = fileLength,
                version = version,
                fourCC = fourCC,
            }
        end
    end
}

---@class ss.Binary.BSP.CDispSubNeighbor
---@field neighbor            integer Index into DISPINFO, 0xFFFF for no neighbor
---@field neighborOrientation integer (CCW) rotation of the neighbor with reference to this displacement
---@field span                integer Where the neighbor fits onto this side of our displacement
---@field neighborSpan        integer Where we fit onto our neighbor
---@field padding             integer
Binary.struct "BSP.CDispSubNeighbor" {
    "UShort neighbor",
    "Byte   neighborOrientation",
    "Byte   span",
    "Byte   neighborSpan",
    "Byte   padding",
}

---@class ss.Binary.BSP.CDispNeighbor
---@field subneighbors ss.Binary.BSP.CDispSubNeighbor[]
Binary.struct "BSP.CDispNeighbor" {
    "BSP.CDispSubNeighbor subneighbors 2",
}

---@class ss.Binary.BSP.CDispCornerNeighbors
---@field neighbors    integer[] Indices of neighbors
---@field numNeighbors integer
---@field padding      integer
Binary.struct "BSP.CDispCornerNeighbors" {
    "UShort neighbors 4",
    "Byte   numNeighbors",
    "Byte   padding",
}

---@class ss.Binary.BSP.dgamelunp_t
---@field id         integer
---@field flags      integer
---@field version    integer
---@field fileOffset integer
---@field fileLength integer
Binary.struct "BSP.dgamelump_t" {
    "Long   id",
    "UShort flags",
    "UShort version",
    "Long   fileOffset",
    "Long   fileLength",
}

---@alias ss.Binary.BSP.StaticProp.4  ss.Binary.BSP.StaticProp
---@alias ss.Binary.BSP.StaticProp.5  ss.Binary.BSP.StaticProp
---@alias ss.Binary.BSP.StaticProp.6  ss.Binary.BSP.StaticProp
---@alias ss.Binary.BSP.StaticProp.7  ss.Binary.BSP.StaticProp
---@alias ss.Binary.BSP.StaticProp.7* ss.Binary.BSP.StaticProp
---@alias ss.Binary.BSP.StaticProp.8  ss.Binary.BSP.StaticProp
---@alias ss.Binary.BSP.StaticProp.9  ss.Binary.BSP.StaticProp
---@alias ss.Binary.BSP.StaticProp.10 ss.Binary.BSP.StaticProp
---@alias ss.Binary.BSP.StaticProp.11 ss.Binary.BSP.StaticProp
---@class ss.Binary.BSP.StaticProp
---@field originX           number
---@field originY           number
---@field originZ           number
---@field pitch             number
---@field yaw               number
---@field roll              number
---@field propType          integer
---@field firstLeaf         integer
---@field leafCount         integer
---@field solid             integer
---@field flags             integer    every version except v7*
---@field padding           integer?   v7*
---@field skin              integer
---@field fadeMinDist       number
---@field fadeMaxDist       number
---@field lightingOriginX   number
---@field lightingOriginY   number
---@field lightingOriginZ   number
---@field forcedFadeScale   number?    since v5
---@field minDXLevel        integer?   v6, v7, and v7*
---@field maxDXLevel        integer?   v6, v7, and v7*
---@field cpugpuLevels      integer[]? since v8
---@field diffuseModulation integer[]? since v7
---@field disableX360       boolean?   v9 and v10
---@field flagsEx           integer?   since v10
---@field uniformScale      number?    since v11

Binary.struct "BSP.StaticProp.4" { -- version == 4
    Size = 56,
    "Float  originX",
    "Float  originY",
    "Float  originZ",
    "Float  pitch",
    "Float  yaw",
    "Float  roll",
    "UShort propType",
    "UShort firstLeaf",
    "UShort leafCount",
    "Byte   solid",
    "Byte   flags", -- every version except v7*
    "Long   skin",
    "Float  fadeMinDist",
    "Float  fadeMaxDist",
    "Float  lightingOriginX",
    "Float  lightingOriginY",
    "Float  lightingOriginZ",
}

Binary.struct "BSP.StaticProp.5" { -- version == 5
    Size = 60,
    "Float  originX",
    "Float  originY",
    "Float  originZ",
    "Float  pitch",
    "Float  yaw",
    "Float  roll",
    "UShort propType",
    "UShort firstLeaf",
    "UShort leafCount",
    "Byte   solid",
    "Byte   flags", -- every version except v7*
    "Long   skin",
    "Float  fadeMinDist",
    "Float  fadeMaxDist",
    "Float  lightingOriginX",
    "Float  lightingOriginY",
    "Float  lightingOriginZ",
    "Float  forcedFadeScale", -- since v5
}

Binary.struct "BSP.StaticProp.6" { -- version == 6
    Size = 64,
    "Float  originX",
    "Float  originY",
    "Float  originZ",
    "Float  pitch",
    "Float  yaw",
    "Float  roll",
    "UShort propType",
    "UShort firstLeaf",
    "UShort leafCount",
    "Byte   solid",
    "Byte   flags", -- every version except v7*
    "Long   skin",
    "Float  fadeMinDist",
    "Float  fadeMaxDist",
    "Float  lightingOriginX",
    "Float  lightingOriginY",
    "Float  lightingOriginZ",
    "Float  forcedFadeScale", -- since v5
    "UShort minDXLevel",      -- v6, v7, v7*
    "UShort maxDXLevel",      -- v6, v7, v7*
}

Binary.struct "BSP.StaticProp.7*" { -- version == 7 or version == 10 and size matches
    Size = 72,
    "Float  originX",
    "Float  originY",
    "Float  originZ",
    "Float  pitch",
    "Float  yaw",
    "Float  roll",
    "UShort propType",
    "UShort firstLeaf",
    "UShort leafCount",
    "Byte   solid",
    "Byte   padding", -- flags, every version except v7*
    "Long   skin",
    "Float  fadeMinDist",
    "Float  fadeMaxDist",
    "Float  lightingOriginX",
    "Float  lightingOriginY",
    "Float  lightingOriginZ",
    "Float  forcedFadeScale", -- since v5
    "UShort minDXLevel",      -- v6, v7, v7*
    "UShort maxDXLevel",      -- v6, v7, v7*
    "ULong  flags",           -- v7* only
    "UShort lightmapResX",    -- v7* only
    "UShort lightmapResY",    -- v7* only
}

Binary.struct "BSP.StaticProp.7" { -- version == 7
    Size = 68,
    "Float  originX",
    "Float  originY",
    "Float  originZ",
    "Float  pitch",
    "Float  yaw",
    "Float  roll",
    "UShort propType",
    "UShort firstLeaf",
    "UShort leafCount",
    "Byte   solid",
    "Byte   flags", -- every version except v7*
    "Long   skin",
    "Float  fadeMinDist",
    "Float  fadeMaxDist",
    "Float  lightingOriginX",
    "Float  lightingOriginY",
    "Float  lightingOriginZ",
    "Float  forcedFadeScale",     -- since v5
    "UShort minDXLevel",          -- v6, v7, v7*
    "UShort maxDXLevel",          -- v6, v7, v7*
    "Byte   diffuseModulation 4", -- since v7
}

Binary.struct "BSP.StaticProp.8" { -- version == 8
    Size = 68,
    "Float  originX",
    "Float  originY",
    "Float  originZ",
    "Float  pitch",
    "Float  yaw",
    "Float  roll",
    "UShort propType",
    "UShort firstLeaf",
    "UShort leafCount",
    "Byte   solid",
    "Byte   flags", -- every version except v7*
    "Long   skin",
    "Float  fadeMinDist",
    "Float  fadeMaxDist",
    "Float  lightingOriginX",
    "Float  lightingOriginY",
    "Float  lightingOriginZ",
    "Float  forcedFadeScale",     -- since v5
    -- "UShort minDXLevel",          -- v6, v7, v7*
    -- "UShort maxDXLevel",          -- v6, v7, v7*
    "Byte   cpugpuLevels 4",      -- since v8
    "Byte   diffuseModulation 4", -- since v7
}

Binary.struct "BSP.StaticProp.9" { -- version == 9
    Size = 72,
    "Float  originX",
    "Float  originY",
    "Float  originZ",
    "Float  pitch",
    "Float  yaw",
    "Float  roll",
    "UShort propType",
    "UShort firstLeaf",
    "UShort leafCount",
    "Byte   solid",
    "Byte   flags", -- every version except v7*
    "Long   skin",
    "Float  fadeMinDist",
    "Float  fadeMaxDist",
    "Float  lightingOriginX",
    "Float  lightingOriginY",
    "Float  lightingOriginZ",
    "Float  forcedFadeScale",     -- since v5
    -- "UShort minDXLevel",          -- v6, v7, v7*
    -- "UShort maxDXLevel",          -- v6, v7, v7*
    "Byte   cpugpuLevels 4",      -- since v8
    "Byte   diffuseModulation 4", -- since v7
    "Long   disableX360",         -- v9, v10
}

Binary.struct "BSP.StaticProp.10" { -- version == 10
    Size = 76,
    "Float  originX",
    "Float  originY",
    "Float  originZ",
    "Float  pitch",
    "Float  yaw",
    "Float  roll",
    "UShort propType",
    "UShort firstLeaf",
    "UShort leafCount",
    "Byte   solid",
    "Byte   flags", -- every version except v7*
    "Long   skin",
    "Float  fadeMinDist",
    "Float  fadeMaxDist",
    "Float  lightingOriginX",
    "Float  lightingOriginY",
    "Float  lightingOriginZ",
    "Float  forcedFadeScale",     -- since v5
    -- "UShort minDXLevel",          -- v6, v7, v7*
    -- "UShort maxDXLevel",          -- v6, v7, v7*
    "Byte   cpugpuLevels 4",      -- since v8
    "Byte   diffuseModulation 4", -- since v7
    "Long   disableX360",         -- v9, v10
    "ULong  flagsEx",             -- since v10
}

Binary.struct "BSP.StaticProp.11" { -- version == 11
    Size = 76,
    "Float  originX",
    "Float  originY",
    "Float  originZ",
    "Float  pitch",
    "Float  yaw",
    "Float  roll",
    "UShort propType",
    "UShort firstLeaf",
    "UShort leafCount",
    "Byte   solid",
    "Byte   flags", -- every version except v7*
    "Long   skin",
    "Float  fadeMinDist",
    "Float  fadeMaxDist",
    "Float  lightingOriginX",
    "Float  lightingOriginY",
    "Float  lightingOriginZ",
    "Float  forcedFadeScale",     -- since v5
    -- "UShort minDXLevel",          -- v6, v7, v7*
    -- "UShort maxDXLevel",          -- v6, v7, v7*
    "Byte   cpugpuLevels 4",      -- since v8
    "Byte   diffuseModulation 4", -- since v7
    -- "Bool   disableX360",         -- v9, v10
    "ULong  flagsEx",             -- since v10
    "Float uniformScale",         -- since v11
}

---@class ss.Binary.BSP.VERTEXES
---@field x number
---@field y number
---@field z number
Binary.struct "BSP.VERTEXES" {
    Size = 12,
    "Float x",
    "Float y",
    "Float z",
}

---@class ss.Binary.BSP.PLANES
---@field normalX  number
---@field normalY  number
---@field normalZ  number
---@field dist     number
---@field axisType integer
Binary.struct "BSP.PLANES" {
    Size = 12 + 4 + 4,
    "Float normalX",
    "Float normalY",
    "Float normalZ",
    "Float dist",
    "Long  axisType"
}

---@alias ss.Binary.BSP.EDGES integer[]
Binary.struct "BSP.EDGES" {
    Size = 2 + 2,
    "UShort",
    "UShort"
}

---@alias ss.Binary.BSP.FACES_HDR ss.Binary.BSP.FACES
---@class ss.Binary.BSP.FACES
---@field planeNum                    integer
---@field side                        integer
---@field onNode                      integer
---@field firstEdge                   integer
---@field numEdges                    integer
---@field texInfo                     integer
---@field dispInfo                    integer
---@field surfaceFogVolumeID          integer
---@field styles                      integer[]
---@field lightOffset                 integer
---@field area                        number
---@field lightmapTextureMinsInLuxels integer[]
---@field lightmapTextureSizeInLuxels integer[]
---@field originalFace                integer
---@field numPrimitives               integer
---@field firstPrimitiveID            integer
---@field smoothingGroups             integer
Binary.struct "BSP.FACES" {
    Size = 56,
    "UShort planeNum",
    "Byte   side",
    "Bool   onNode",
    "Long   firstEdge",
    "Short  numEdges",
    "Short  texInfo",
    "Short  dispInfo",
    "Short  surfaceFogVolumeID",
    "Byte   styles 4",
    "Long   lightOffset",
    "Float  area",
    "Long   lightmapTextureMinsInLuxels 2",
    "Long   lightmapTextureSizeInLuxels 2",
    "Long   originalFace",
    "UShort numPrimitives",
    "UShort firstPrimitiveID",
    "ULong  smoothingGroups",
}

---@class ss.Binary.BSP.BRUSHES
---@field firstSide integer
---@field numSides  integer
---@field contents  integer
Binary.struct "BSP.BRUSHES" {
    Size = 4 + 4 + 4,
    "Long firstSide",
    "Long numSides",
    "Long contents",
}

---@class ss.Binary.BSP.BRUSHSIDES
---@field planeNum integer
---@field texInfo  integer
---@field dispInfo integer
---@field bevel    integer
Binary.struct "BSP.BRUSHSIDES" {
    Size = 2 + 2 + 2 + 2,
    "UShort planeNum",
    "Short  texInfo",
    "Short  dispInfo",
    "Short  bevel",
}

---@class ss.Binary.BSP.NODES
---@field planeNum  integer
---@field children  integer[]
---@field minX      integer
---@field minY      integer
---@field minZ      integer
---@field maxX      integer
---@field maxY      integer
---@field maxZ      integer
---@field firstFace integer
---@field numFaces  integer
---@field area      integer
---@field padding   integer
Binary.struct "BSP.NODES" {
    Size = 32,
    "Long   planeNum",
    "Long   children 2",
    "Short  minX",
    "Short  minY",
    "Short  minZ",
    "Short  maxX",
    "Short  maxY",
    "Short  maxZ",
    "UShort firstFace",
    "UShort numFaces",
    "Short  area",
    "Short  padding",
}

---@class ss.Binary.BSP.LEAFS
---@field contents         integer
---@field cluster          integer
---@field areaAndFlags     integer
---@field minX             integer
---@field minY             integer
---@field minZ             integer
---@field maxX             integer
---@field maxY             integer
---@field maxZ             integer
---@field firstLeafFace    integer
---@field numLeafFaces     integer
---@field firstLeafBrush   integer
---@field numLeafBrush     integer
---@field leafWaterDataID  integer
---@field padding          integer
Binary.struct "BSP.LEAFS" {
    Size = 32,
    "Long   contents",
    "Short  cluster",
    "Short  areaAndFlags", -- area: lower 9 bits, flags: upper 7 bits
    "Short  minX",
    "Short  minY",
    "Short  minZ",
    "Short  maxX",
    "Short  maxY",
    "Short  maxZ",
    "UShort firstLeafFace",
    "UShort numLeafFaces",
    "UShort firstLeafBrush",
    "UShort numLeafBrushes",
    "Short  leafWaterDataID",
    -- Also need the following when version <= 19
    -- "CompressedLightCube ambientLighting", -- 24 bytes
    "Short  padding",
}

---@class ss.Binary.BSP.TEXINFO
---The texture coordinate s of a point p in texels is textureS・p + textureOffsetS, and the same for t.
---The lightmap coordinates in luxels are given by lightmapS and lightmapT in the same way.
---@field textureSX       number
---@field textureSY       number
---@field textureSZ       number
---@field textureOffsetS  number
---@field textureTX       number
---@field textureTY       number
---@field textureTZ       number
---@field textureOffsetT  number
---@field lightmapSX      number
---@field lightmapSY      number
---@field lightmapSZ      number
---@field lightmapOffsetS number
---@field lightmapTX      number
---@field lightmapTY      number
---@field lightmapTZ      number
---@field lightmapOffsetT number
---@field flags           integer
---@field texData         integer
Binary.struct "BSP.TEXINFO" {
    Size = 72,
    "Float textureSX",
    "Float textureSY",
    "Float textureSZ",
    "Float textureOffsetS",
    "Float textureTX",
    "Float textureTY",
    "Float textureTZ",
    "Float textureOffsetT",
    "Float lightmapSX",
    "Float lightmapSY",
    "Float lightmapSZ",
    "Float lightmapOffsetS",
    "Float lightmapTX",
    "Float lightmapTY",
    "Float lightmapTZ",
    "Float lightmapOffsetT",
    "Long  flags",
    "Long  texData",
}

---@class ss.Binary.BSP.TEXDATA
---@field reflectivityR     number
---@field reflectivityG     number
---@field reflectivityB     number
---@field nameStringTableID integer
---@field width             integer
---@field height            integer
---@field viewWidth         integer
---@field viewHeight        integer
Binary.struct "BSP.TEXDATA" {
    Size = 4 * 3 + 4 + 4 + 4 + 4 + 4,
    "Float reflectivityR",
    "Float reflectivityG",
    "Float reflectivityB",
    "Long  nameStringTableID",
    "Long  width",
    "Long  height",
    "Long  viewWidth",
    "Long  viewHeight",
}

---@class ss.Binary.BSP.MODELS
---@field minX      number
---@field minY      number
---@field minZ      number
---@field maxX      number
---@field maxY      number
---@field maxZ      number
---@field originX   number
---@field originY   number
---@field originZ   number
---@field headNode  integer
---@field firstFace integer
---@field numFaces  integer
Binary.struct "BSP.MODELS" {
    Size = 48,
    "Float minX",
    "Float minY",
    "Float minZ",
    "Float maxX",
    "Float maxY",
    "Float maxZ",
    "Float originX",
    "Float originY",
    "Float originZ",
    "Long  headNode",
    "Long  firstFace",
    "Long  numFaces",
}

---@class ss.Binary.BSP.DISPINFO
---@field startPositionX    number
---@field startPositionY    number
---@field startPositionZ    number
---@field dispVertStart     integer
---@field dispTriStart      integer
---@field power             integer
---@field minTesselation    integer
---@field smoothingAngle    number
---@field contents          integer
---@field mapFace           integer
---@field padding           integer
---@field lightmapAlphaTest integer
---@field lightmapSamplePositionStart integer
---@field edgeNeighbors     ss.Binary.BSP.CDispNeighbor[]
---@field cornerNeighbors   ss.Binary.BSP.CDispCornerNeighbors[]
---@field allowedVerts      integer[]
Binary.struct "BSP.DISPINFO" {
    Size = 176,
    "Float  startPositionX",
    "Float  startPositionY",
    "Float  startPositionZ",
    "Long   dispVertStart",
    "Long   dispTriStart",
    "Long   power",
    "Long   minTesselation",
    "Float  smoothingAngle",
    "Long   contents",
    "UShort mapFace",
    "UShort padding",
    "Long   lightmapAlphaTest",
    "Long   lightmapSamplesPositionStart",
    "BSP.CDispNeighbor        edgeNeighbors   4", -- Probably these are
    "BSP.CDispCornerNeighbors cornerNeighbors 4", -- not correctly parsed
    "ULong                    allowedVerts    10",
}

---The offset of a grid point of a displacement from the flat surface, and its alpha.
---@class ss.Binary.BSP.DISP_VERTS
---@field directionX number The direction of the offset, of length 1.
---@field directionY number
---@field directionZ number
---@field distance   number The length of the offset.
---@field alpha      number
Binary.struct "BSP.DISP_VERTS" {
    Size = 20,
    "Float directionX",
    "Float directionY",
    "Float directionZ",
    "Float distance",
    "Float alpha",
}

---@class ss.Binary.BSP.DISP_MULTIBLEND
---@field multiblend       number[] Blend factors (x, y, z, w); Lightmapped_4WayBlend blends layers 2, 3, and 4 by y, z, and w.
---@field alphablend       number[]
---@field multiblendColors number[] R, G, and B of each of the 4 layers.
Binary.struct "BSP.DISP_MULTIBLEND" {
    Size = 80,
    "Float multiblend       4",
    "Float alphablend       4",
    "Float multiblendColors 12",
}

---@class ss.Binary.BSP.CUBEMAPS
---@field originX integer
---@field originY integer
---@field originZ integer
---@field size    integer
---@field padding integer[]
Binary.struct "BSP.CUBEMAPS" {
    Size = 16,
    "Long originX",
    "Long originY",
    "Long originZ",
    "Byte size",
    "Byte padding 3",
}

---@class ss.Binary.BSP.GAME_LUMP
---@field lumpCount integer
---@field [integer] ss.Binary.BSP.dgamelunp_t
Binary.struct "BSP.GAME_LUMP" {
    "Long                lumpCount",
    "BSP.dgamelump_t nil lumpCount",
}

---@class ss.Binary.BSP.StaticPropDict
---@field dictEntries integer
---@field name        string[]
Binary.struct "BSP.StaticPropDict" {
    "Long           dictEntries",
    "String128 name dictEntries",
}

---@class ss.Binary.BSP.StaticPropLeaf
---@field leafEntries integer
---@field leaf        integer[]
Binary.struct "BSP.StaticPropLeaf" {
    "Long        leafEntries",
    "UShort leaf leafEntries",
}

---@class ss.Binary.BSP.GAME_LUMP.sprp
---@field dictEntries integer
---@field name        string[]
---@field leafEntries integer
---@field leaf        integer[]
---@field propEntries integer
---@field prop        ss.Binary.BSP.StaticProp[]
Binary.struct "BSP.GAME_LUMP.sprp" { -- Static Props
    ---@param self ss.BinaryStructureDefinition
    ---@param binary ss.BinaryStringReader
    ---@param header ss.Binary.BSP.dgamelunp_t
    ---@return ss.Binary.BSP.GAME_LUMP.sprp
    Read = function(self, binary, header)
        local names = Binary.Read(binary, "BSP.StaticPropDict")
        local leafs = Binary.Read(binary, "BSP.StaticPropLeaf")
        local propEntries = Binary.Read(binary, "Long")

        local offset = names.dictEntries * 128 + leafs.leafEntries * 2 + 4 * 3
        local nextlump = header.fileOffset + header.fileLength
        local staticPropOffset = header.fileOffset + offset
        local sizeofStaticPropLump = (nextlump - staticPropOffset) / propEntries

        local version = header.version
        local structType = "BSP.StaticProp." .. tostring(version) -- Size depends on game lump version
        local staticProp7Star = Binary.Find "BSP.StaticProp.7*"
        if version == 7 or version == 10 and staticProp7Star and sizeofStaticPropLump == staticProp7Star.Size then
            structType = "BSP.StaticProp.7*"
        end

        local props = {} ---@type ss.Binary.BSP.StaticProp[]
        local definition = Binary.Find(structType)
        if definition and #definition > 0 then
            ---Prevent spamming error messages about the size of static prop lump.
            local sprpInvalidSize = false
            for i = 1, propEntries do
                -- A smaller size of each prop than the definition means an unknown format. Stop at the end of the lump.
                if binary:Tell() + definition.Size > binary:Size() then break end
                props[i] = Binary.Read(binary, structType)
                if sizeofStaticPropLump ~= definition.Size then
                    binary:Skip(sizeofStaticPropLump - definition.Size)
                    if not sprpInvalidSize then
                        sprpInvalidSize = true
                        ErrorNoHalt(string.format(
                            "SplashSWEPs/BSPLoader: StaticPropLump_t has unknown format.\n"
                            .. "    Map: %s\n"
                            .. "    Calculated size of StaticPropLump_t: %d\n"
                            .. "    StaticPropLump_t version: %d\n"
                            .. "    Suggested size of StaticPropLump_t: %d\n",
                            game.GetMap(), sizeofStaticPropLump, version, definition.Size))
                    end
                end
            end
        end

        return {
            dictEntries = names.dictEntries,
            name        = names.name,
            leafEntries = leafs.leafEntries,
            leaf        = leafs.leaf,
            propEntries = propEntries,
            prop        = props,
        }
    end,
}

---@alias BSP.DefinedStructures
---| ss.Binary.BSP.DISPINFO
---| ss.Binary.BSP.DISP_VERTS
---| ss.Binary.BSP.FACES
---| ss.Binary.BSP.GAME_LUMP
---| ss.Binary.BSP.Header
---| ss.Binary.BSP.LEAFS
---| ss.Binary.BSP.MODELS
---| ss.Binary.BSP.PLANES
---| ss.Binary.BSP.GAME_LUMP.sprp
---| ss.Binary.BSP.StaticProp
---| ss.Binary.BSP.TEXDATA
---| ss.Binary.BSP.TEXINFO
---| ss.Binary.BSP.CDispNeighbor
---| ss.Binary.BSP.CDispCornerNeighbors
---| ss.Binary.BSP.dgamelunp_t
---| ss.Binary.BSP.VERTEXES
---| boolean
---| number
---| string

---Stores all the Lumps parsed from the BSP.
---@class ss.RawBSPResults
---@field header                    ss.Binary.BSP.Header
---@field ENTITIES                  string[]
---@field PLANES                    ss.Binary.BSP.PLANES[]
---@field VERTEXES                  ss.Binary.BSP.VERTEXES[]
---@field EDGES                     integer[][]
---@field SURFEDGES                 integer[]
---@field FACES                     ss.Binary.BSP.FACES[]
---@field FACES_HDR                 ss.Binary.BSP.FACES_HDR[]
---@field LEAFS                     ss.Binary.BSP.LEAFS[]
---@field CUBEMAPS                  ss.Binary.BSP.CUBEMAPS[]
---@field TEXINFO                   ss.Binary.BSP.TEXINFO[]
---@field TEXDATA                   ss.Binary.BSP.TEXDATA[]
---@field TEXDATA_STRING_TABLE      integer[]
---@field TEXDATA_STRING_DATA       string[]
---@field MODELS                    ss.Binary.BSP.MODELS[]
---@field DISPINFO                  ss.Binary.BSP.DISPINFO[]
---@field DISP_VERTS                ss.Binary.BSP.DISP_VERTS[]
---@field DISP_TRIS                 integer[]
---@field DISP_MULTIBLEND           ss.Binary.BSP.DISP_MULTIBLEND[]
---@field LIGHTING                  string
---@field LIGHTING_HDR              string
---@field GAME_LUMP                 ss.Binary.BSP.GAME_LUMP
---@field TexDataStringTableToIndex integer[]
---@field DispMultiBlendStart       table<integer, integer> DISPINFO index --> index of its first DISP_MULTIBLEND record
---@field [string]                  BSP.DefinedStructures

local GameLumpToRead = { sprp = "BSP.GAME_LUMP.sprp" }
local LUMP_INV = table.Flip(LUMP)

---List of lumps to read in the BSP file.  False to skip.
---String values mean the entire lump is an array of that type.
local LumpsToRead = {
    ENTITIES             = "String",
    PLANES               = "BSP.PLANES",
    VERTEXES             = "BSP.VERTEXES",
    EDGES                = "BSP.EDGES",
    SURFEDGES            = "Long",
    FACES                = "BSP.FACES",
    FACES_HDR            = "BSP.FACES",
    ORIGINALFACES        = false, -- "BSP.FACES"
    BRUSHES              = false,
    BRUSHSIDES           = false,
    NODES                = false,
    LEAFS                = "BSP.LEAFS",
    LEAFFACES            = false, -- "UShort"
    LEAFBRUSHES          = false, -- "UShort"
    TEXINFO              = "BSP.TEXINFO",
    TEXDATA              = "BSP.TEXDATA",
    TEXDATA_STRING_TABLE = "Long",
    TEXDATA_STRING_DATA  = "String",
    MODELS               = "BSP.MODELS",
    DISPINFO             = "BSP.DISPINFO",
    DISP_VERTS           = "BSP.DISP_VERTS",
    DISP_TRIS            = "UShort",
    DISP_MULTIBLEND      = "BSP.DISP_MULTIBLEND",
    LIGHTING             = "Raw",
    LIGHTING_HDR         = "Raw",
    CUBEMAPS             = "BSP.CUBEMAPS",
    GAME_LUMP            = "BSP.GAME_LUMP",
}

---@param id integer
---@return string
local function getGameLumpStr(id)
    local a = bit.band(0xFF, bit.rshift(id, 24))
    local b = bit.band(0xFF, bit.rshift(id, 16))
    local c = bit.band(0xFF, bit.rshift(id, 8))
    local d = bit.band(0xFF, id)
    return string.char(a, b, c, d)
end

---Decompresses the LZMA data of a lump, which follows the "LZMA" id read before.
---@param lump ss.BinaryStringReader
---@return ss.BinaryStringReader decompressed
---@return integer length
local function decompress(lump)
    local current       = lump:Tell()
    local actualSize    = Binary.Read(lump, 4)
    lump:Seek(current)
    local actualSizeNum = Binary.Read(lump, "Long")
    local lzmaSize      = Binary.Read(lump, "Long")
    local props         = Binary.Read(lump, 5)
    local contents      = Binary.Read(lump, lzmaSize)
    local formatted     = props .. actualSize .. "\0\0\0\0" .. contents
    return Binary.NewStringReader(util.Decompress(formatted) or ""), actualSizeNum
end

---Reads the data of a lump, decompressing it if needed.
---@param bsp File
---@param fileOffset integer
---@param fileLength integer
---@return ss.BinaryStringReader lump
---@return integer length
local function openLump(bsp, fileOffset, fileLength)
    bsp:Seek(fileOffset)
    local lump = Binary.NewStringReader(bsp:Read(fileLength) or "")
    if Binary.Read(lump, 4) == "LZMA" then
        return decompress(lump)
    end

    lump:Seek(0)
    return lump, fileLength
end

---@param bsp File
---@param header ss.Binary.BSP.LumpHeader
---@param structType string
---@return BSP.DefinedStructures?
local function readLump(bsp, header, structType)
    local t = {} ---@type BSP.DefinedStructures|BSP.DefinedStructures[]
    local definition = Binary.Find(structType)
    local elementLength = BuiltinTypeSizes[structType] or definition and definition.Size or math.huge
    local lump, totalLength = openLump(bsp, header.fileOffset, header.fileLength)
    if totalLength == 0 then
        -- An empty lump has no element. A structure read from it would be made of nothing.
        return structType == "Raw" and "" or {}
    end

    local numElements = totalLength / elementLength
    if structType == "Raw" then
        t = Binary.Read(lump, totalLength)
    elseif structType == "String" then
        t = Binary.Read(lump, totalLength):Split "\0"
        if t[#t] == "" then t[#t] = nil end -- Remove the last empty string
    elseif numElements > 0 then
        for i = 1, numElements do
            t[i] = Binary.Read(lump, structType)
        end
    else
        ---@type BSP.DefinedStructures
        t = Binary.Read(lump, structType)
    end

    return t
end

---Parses the BSP structure of current map.
---@return ss.RawBSPResults?
function BSP.Load()
    local t0 = SysTime()
    local bsp = file.Open(string.format("maps/%s.bsp", game.GetMap()), "rb", "GAME")
    if not bsp then return end

    print "Loading BSP file..."

    ---@type ss.RawBSPResults
    local t = {
        -- The header is at the beginning of the file, so its positions are the file offsets BSP.LumpHeader compares.
        header = Binary.Read(Binary.NewStringReader(bsp:Read(HEADER_SIZE) or ""), "BSP.Header"),
        ENTITIES = {},
        PLANES = {},
        VERTEXES = {},
        EDGES = {},
        SURFEDGES = {},
        FACES = {},
        FACES_HDR = {},
        LEAFS = {},
        CUBEMAPS = {},
        TEXINFO = {},
        TEXDATA = {},
        TEXDATA_STRING_TABLE = {},
        TEXDATA_STRING_DATA = {},
        MODELS = {},
        DISPINFO = {},
        DISP_VERTS = {},
        DISP_TRIS = {},
        DISP_MULTIBLEND = {},
        LIGHTING = "",
        LIGHTING_HDR = "",
        GAME_LUMP = { lumpCount = 0 },
        TexDataStringTableToIndex = {},
        DispMultiBlendStart = {},
    }
    print("    BSP file version: " .. t.header.version)
    for i = 1, #LUMP do
        local name = LUMP[i]
        local structType = LumpsToRead[name]
        if structType then
            print(string.format("        LUMP #%02d\t%s", i, name))
            t[name] = readLump(bsp, t.header.lumps[LUMP_INV[name]], structType)
        end
    end

    print "    Loading GameLump..."
    for _, header in ipairs(t.GAME_LUMP) do
        local idstr = getGameLumpStr(header.id)
        local structType = GameLumpToRead[idstr]
        if structType then
            print("        GameLump \"" .. idstr .. "\"... (version: " .. header.version .. ")")
            local lump = openLump(bsp, header.fileOffset, header.fileLength)
            t[idstr] = Binary.Read(lump, structType, header)
        end
    end

    print "    Constructing texture name table..."
    t.TexDataStringTableToIndex = table.Flip(t.TEXDATA_STRING_TABLE)

    -- Only displacements with this flag have DISP_MULTIBLEND records, one per vertex, in DISPINFO order.
    -- See engine/disp_mapload.cpp in Source.
    print "    Associating displacement multiblend data..."
    local DISP_INFO_FLAG_HAS_MULTIBLEND = 0x40000000
    local multiblendStart = 1
    for i, dispInfo in ipairs(t.DISPINFO) do
        if bit.band(dispInfo.minTesselation, DISP_INFO_FLAG_HAS_MULTIBLEND) ~= 0 then
            t.DispMultiBlendStart[i] = multiblendStart
            multiblendStart = multiblendStart + (2 ^ dispInfo.power + 1) ^ 2
        end
    end

    local elapsed = math.Round((SysTime() - t0) * 1000, 2)
    print("Done.  Elapsed time: " .. elapsed .. " ms.")

    bsp:Close()
    return t
end

return BSP
