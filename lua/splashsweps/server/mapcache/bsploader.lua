
---@class ss
local ss = SplashSWEPs
if not ss then return end

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

---Used for calculating the size of lump structures
local BuiltinTypeSizes = {
    Angle       = 12,
    Bool        = 1,
    Byte        = 1,
    Float       = 4,
    Long        = 4,
    LongVector  = 12,
    SByte       = 1,
    Short       = 2,
    ShortVector = 6,
    ULong       = 4,
    UShort      = 2,
    Vector      = 12,
}

---@class ss.Binary.BSP.Header
---@field identifier  integer
---@field version     integer
---@field lumps       ss.Binary.BSP.LumpHeader[]
---@field mapRevision integer
ss.bstruct "BSP.Header" {
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
ss.bstruct "BSP.LumpHeader" {
    ---@param self ss.BinaryStructureDefinition
    ---@param bsp File
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
ss.bstruct "BSP.CDispSubNeighbor" {
    "UShort neighbor",
    "Byte   neighborOrientation",
    "Byte   span",
    "Byte   neighborSpan",
    "Byte   padding",
}

---@class ss.Binary.BSP.CDispNeighbor
---@field subneighbors ss.Binary.BSP.CDispSubNeighbor[]
ss.bstruct "BSP.CDispNeighbor" {
    "BSP.CDispSubNeighbor subneighbors 2",
}

---@class ss.Binary.BSP.CDispCornerNeighbors
---@field neighbors    integer[] Indices of neighbors
---@field numNeighbors integer
---@field padding      integer
ss.bstruct "BSP.CDispCornerNeighbors" {
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
ss.bstruct "BSP.dgamelump_t" {
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
---@field origin             Vector
---@field angle              Angle
---@field propType           integer
---@field firstLeaf          integer
---@field leafCount          integer
---@field solid              integer
---@field flags              integer    every version except v7*
---@field padding            integer?   v7*
---@field skin               integer
---@field fadeMinDist        number
---@field fadeMaxDist        number
---@field lightingOrigin     Vector
---@field forcedFadeScale    number?    since v5
---@field minDXLevel         integer?   v6, v7, and v7*
---@field maxDXLevel         integer?   v6, v7, and v7*
---@field cpugpuLevels       integer[]? since v8
---@field diffuseModulation  integer[]? since v7
---@field disableX360        boolean?   v9 and v10
---@field flagsEx            integer?   since v10
---@field uniformScale       number?    since v11

ss.bstruct "BSP.StaticProp.4" { -- version == 4
    Size = 56,
    "Vector origin",
    "Angle  angle",
    "UShort propType",
    "UShort firstLeaf",
    "UShort leafCount",
    "Byte   solid",
    "Byte   flags", -- every version except v7*
    "Long   skin",
    "Float  fadeMinDist",
    "Float  fadeMaxDist",
    "Vector lightingOrigin",
}

ss.bstruct "BSP.StaticProp.5" { -- version == 5
    Size = 60,
    "Vector origin",
    "Angle  angle",
    "UShort propType",
    "UShort firstLeaf",
    "UShort leafCount",
    "Byte   solid",
    "Byte   flags", -- every version except v7*
    "Long   skin",
    "Float  fadeMinDist",
    "Float  fadeMaxDist",
    "Vector lightingOrigin",
    "Float  forcedFadeScale", -- since v5
}

ss.bstruct "BSP.StaticProp.6" { -- version == 6
    Size = 64,
    "Vector origin",
    "Angle  angle",
    "UShort propType",
    "UShort firstLeaf",
    "UShort leafCount",
    "Byte   solid",
    "Byte   flags", -- every version except v7*
    "Long   skin",
    "Float  fadeMinDist",
    "Float  fadeMaxDist",
    "Vector lightingOrigin",
    "Float  forcedFadeScale", -- since v5
    "UShort minDXLevel",      -- v6, v7, v7*
    "UShort maxDXLevel",      -- v6, v7, v7*
}

ss.bstruct "BSP.StaticProp.7*" { -- version == 7 or version == 10 and size matches
    Size = 72,
    "Vector origin",
    "Angle  angle",
    "UShort propType",
    "UShort firstLeaf",
    "UShort leafCount",
    "Byte   solid",
    "Byte   padding", -- flags, every version except v7*
    "Long   skin",
    "Float  fadeMinDist",
    "Float  fadeMaxDist",
    "Vector lightingOrigin",
    "Float  forcedFadeScale", -- since v5
    "UShort minDXLevel",      -- v6, v7, v7*
    "UShort maxDXLevel",      -- v6, v7, v7*
    "ULong  flags",           -- v7* only
    "UShort lightmapResX",    -- v7* only
    "UShort lightmapResY",    -- v7* only
}

ss.bstruct "BSP.StaticProp.7" { -- version == 7
    Size = 68,
    "Vector origin",
    "Angle  angle",
    "UShort propType",
    "UShort firstLeaf",
    "UShort leafCount",
    "Byte   solid",
    "Byte   flags", -- every version except v7*
    "Long   skin",
    "Float  fadeMinDist",
    "Float  fadeMaxDist",
    "Vector lightingOrigin",
    "Float  forcedFadeScale",     -- since v5
    "UShort minDXLevel",          -- v6, v7, v7*
    "UShort maxDXLevel",          -- v6, v7, v7*
    "Byte   diffuseModulation 4", -- since v7
}

ss.bstruct "BSP.StaticProp.8" { -- version == 8
    Size = 68,
    "Vector origin",
    "Angle  angle",
    "UShort propType",
    "UShort firstLeaf",
    "UShort leafCount",
    "Byte   solid",
    "Byte   flags", -- every version except v7*
    "Long   skin",
    "Float  fadeMinDist",
    "Float  fadeMaxDist",
    "Vector lightingOrigin",
    "Float  forcedFadeScale",     -- since v5
    -- "UShort minDXLevel",          -- v6, v7, v7*
    -- "UShort maxDXLevel",          -- v6, v7, v7*
    "Byte   cpugpuLevels 4",      -- since v8
    "Byte   diffuseModulation 4", -- since v7
}

ss.bstruct "BSP.StaticProp.9" { -- version == 9
    Size = 72,
    "Vector origin",
    "Angle  angle",
    "UShort propType",
    "UShort firstLeaf",
    "UShort leafCount",
    "Byte   solid",
    "Byte   flags", -- every version except v7*
    "Long   skin",
    "Float  fadeMinDist",
    "Float  fadeMaxDist",
    "Vector lightingOrigin",
    "Float  forcedFadeScale",     -- since v5
    -- "UShort minDXLevel",          -- v6, v7, v7*
    -- "UShort maxDXLevel",          -- v6, v7, v7*
    "Byte   cpugpuLevels 4",      -- since v8
    "Byte   diffuseModulation 4", -- since v7
    "Long   disableX360",         -- v9, v10
}

ss.bstruct "BSP.StaticProp.10" { -- version == 10
    Size = 76,
    "Vector origin",
    "Angle  angle",
    "UShort propType",
    "UShort firstLeaf",
    "UShort leafCount",
    "Byte   solid",
    "Byte   flags", -- every version except v7*
    "Long   skin",
    "Float  fadeMinDist",
    "Float  fadeMaxDist",
    "Vector lightingOrigin",
    "Float  forcedFadeScale",     -- since v5
    -- "UShort minDXLevel",          -- v6, v7, v7*
    -- "UShort maxDXLevel",          -- v6, v7, v7*
    "Byte   cpugpuLevels 4",      -- since v8
    "Byte   diffuseModulation 4", -- since v7
    "Long   disableX360",         -- v9, v10
    "ULong  flagsEx",             -- since v10
}

ss.bstruct "BSP.StaticProp.11" { -- version == 11
    Size = 76,
    "Vector origin",
    "Angle  angle",
    "UShort propType",
    "UShort firstLeaf",
    "UShort leafCount",
    "Byte   solid",
    "Byte   flags", -- every version except v7*
    "Long   skin",
    "Float  fadeMinDist",
    "Float  fadeMaxDist",
    "Vector lightingOrigin",
    "Float  forcedFadeScale",     -- since v5
    -- "UShort minDXLevel",          -- v6, v7, v7*
    -- "UShort maxDXLevel",          -- v6, v7, v7*
    "Byte   cpugpuLevels 4",      -- since v8
    "Byte   diffuseModulation 4", -- since v7
    -- "Bool   disableX360",         -- v9, v10
    "ULong  flagsEx",             -- since v10
    "Float uniformScale",         -- since v11
}

---@class ss.Binary.BSP.PLANES
---@field normal   Vector
---@field dist     number
---@field axisType integer
ss.bstruct "BSP.PLANES" {
    Size = 12 + 4 + 4,
    "Vector normal",
    "Float  dist",
    "Long   axisType"
}

---@alias ss.Binary.BSP.EDGES integer[]
ss.bstruct "BSP.EDGES" {
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
ss.bstruct "BSP.FACES" {
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
ss.bstruct "BSP.BRUSHES" {
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
ss.bstruct "BSP.BRUSHSIDES" {
    Size = 2 + 2 + 2 + 2,
    "UShort planeNum",
    "Short  texInfo",
    "Short  dispInfo",
    "Short  bevel",
}

---@class ss.Binary.BSP.NODES
---@field planeNum  integer
---@field children  integer[]
---@field mins      Vector
---@field maxs      Vector
---@field firstFace integer
---@field numFaces  integer
---@field area      integer
---@field padding   integer
ss.bstruct "BSP.NODES" {
    Size = 32,
    "Long        planeNum",
    "Long        children 2",
    "ShortVector mins",
    "ShortVector maxs",
    "UShort      firstFace",
    "UShort      numFaces",
    "Short       area",
    "Short       padding",
}

---@class ss.Binary.BSP.LEAFS
---@field contents         integer
---@field cluster          integer
---@field areaAndFlags     integer
---@field mins             Vector
---@field maxs             Vector
---@field firstLeafFace    integer
---@field numLeafFaces     integer
---@field firstLeafBrush   integer
---@field numLeafBrush     integer
---@field leafWaterDataID  integer
---@field padding          integer
ss.bstruct "BSP.LEAFS" {
    Size = 32,
    "Long        contents",
    "Short       cluster",
    "Short       areaAndFlags", -- area: lower 9 bits, flags: upper 7 bits
    "ShortVector mins",
    "ShortVector maxs",
    "UShort      firstLeafFace",
    "UShort      numLeafFaces",
    "UShort      firstLeafBrush",
    "UShort      numLeafBrushes",
    "Short       leafWaterDataID",
    -- Also need the following when version <= 19
    -- "CompressedLightCube ambientLighting", -- 24 bytes
    "Short       padding",
}

---@class ss.Binary.BSP.TEXINFO
---@field textureVecS     Vector
---@field textureOffsetS  number
---@field textureVecT     Vector
---@field textureOffsetT  number
---@field lightmapVecS    Vector
---@field lightmapOffsetS number
---@field lightmapVecT    Vector
---@field lightmapOffsetT number
---@field flags           integer
---@field texData         integer
ss.bstruct "BSP.TEXINFO" {
    Size = 72,
    "Vector textureVecS",
    "Float  textureOffsetS",
    "Vector textureVecT",
    "Float  textureOffsetT",
    "Vector lightmapVecS",
    "Float  lightmapOffsetS",
    "Vector lightmapVecT",
    "Float  lightmapOffsetT",
    "Long   flags",
    "Long   texData",
}

---@class ss.Binary.BSP.TEXDATA
---@field reflectivity      Vector
---@field nameStringTableID integer
---@field width             integer
---@field height            integer
---@field viewWidth         integer
---@field viewHeight        integer
ss.bstruct "BSP.TEXDATA" {
    Size = 4 * 3 + 4 + 4 + 4 + 4 + 4,
    "Vector reflectivity",
    "Long   nameStringTableID",
    "Long   width",
    "Long   height",
    "Long   viewWidth",
    "Long   viewHeight",
}

---@class ss.Binary.BSP.MODELS
---@field mins      Vector
---@field maxs      Vector
---@field origin    Vector
---@field headNode  integer
---@field firstFace integer
---@field numFaces  integer
ss.bstruct "BSP.MODELS" {
    Size = 48,
    "Vector mins",
    "Vector maxs",
    "Vector origin",
    "Long   headNode",
    "Long   firstFace",
    "Long   numFaces",
}

---@class ss.Binary.BSP.DISPINFO
---@field startPosition               Vector
---@field dispVertStart               integer
---@field dispTriStart                integer
---@field power                       integer
---@field minTesselation              integer
---@field smoothingAngle              number
---@field contents                    integer
---@field mapFace                     integer
---@field padding                     integer
---@field lightmapAlphaTest           integer
---@field lightmapSamplePositionStart integer
---@field edgeNeighbors               ss.Binary.BSP.CDispNeighbor[]
---@field cornerNeighbors             ss.Binary.BSP.CDispCornerNeighbors[]
---@field allowedVerts                integer[]
ss.bstruct "BSP.DISPINFO" {
    Size = 176,
    "Vector                   startPosition",
    "Long                     dispVertStart",
    "Long                     dispTriStart",
    "Long                     power",
    "Long                     minTesselation",
    "Float                    smoothingAngle",
    "Long                     contents",
    "UShort                   mapFace",
    "UShort                   padding",
    "Long                     lightmapAlphaTest",
    "Long                     lightmapSamplesPositionStart",
    "BSP.CDispNeighbor        edgeNeighbors   4", -- Probably these are
    "BSP.CDispCornerNeighbors cornerNeighbors 4", -- not correctly parsed
    "ULong                    allowedVerts    10",
}

---@class ss.Binary.BSP.DISP_VERTS
---@field vec   Vector
---@field dist  number
---@field alpha number
ss.bstruct "BSP.DISP_VERTS" {
    Size = 20,
    "Vector vec",
    "Float  dist",
    "Float  alpha",
}

---@class ss.Binary.BSP.CUBEMAPS
---@field origin Vector
---@field size   integer
ss.bstruct "BSP.CUBEMAPS" {
    Size = 16,
    "LongVector origin",
    "Long       size",
}

---@class ss.Binary.BSP.GAME_LUMP
---@field lumpCount integer
---@field [integer] ss.Binary.BSP.dgamelunp_t
ss.bstruct "BSP.GAME_LUMP" {
    "Long                lumpCount",
    "BSP.dgamelump_t nil lumpCount",
}

---@class ss.Binary.BSP.StaticPropDict
---@field dictEntries integer
---@field name        string[]
ss.bstruct "BSP.StaticPropDict" {
    "Long           dictEntries",
    "String128 name dictEntries",
}

---@class ss.Binary.BSP.StaticPropLeaf
---@field leafEntries integer
---@field leaf        integer[]
ss.bstruct "BSP.StaticPropLeaf" {
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
ss.bstruct "BSP.GAME_LUMP.sprp" { -- Static Props
    ---@param self ss.BinaryStructureDefinition
    ---@param binary File
    ---@param header ss.Binary.BSP.dgamelunp_t
    ---@return ss.Binary.BSP.GAME_LUMP.sprp
    Read = function(self, binary, header)
        local names = ss.ReadStructureFromFile(binary, "BSP.StaticPropDict")
        local leafs = ss.ReadStructureFromFile(binary, "BSP.StaticPropLeaf")
        local propEntries = ss.ReadStructureFromFile(binary, "Long")

        local offset = names.dictEntries * 128 + leafs.leafEntries * 2 + 4 * 3
        local nextlump = header.fileOffset + header.fileLength
        local staticPropOffset = header.fileOffset + offset
        local sizeofStaticPropLump = (nextlump - staticPropOffset) / propEntries

        local version = header.version
        local structType = "BSP.StaticProp." .. tostring(version) -- Size depends on game lump version
        if version == 7 or version == 10 and sizeofStaticPropLump == ss.bstruct "BSP.StaticProp.7*".Size then
            structType = "BSP.StaticProp.7*"
        end

        local props = {} ---@type ss.Binary.BSP.StaticProp[]
        if #ss.bstruct(structType) > 0 then
            ---Prevent spamming error messages about the size of static prop lump.
            local sprpInvalidSize = false
            for i = 1, propEntries do
                props[i] = ss.ReadStructureFromFile(binary, structType)
                if sizeofStaticPropLump ~= ss.bstruct(structType).Size then
                    binary:Skip(sizeofStaticPropLump - ss.bstruct(structType).Size)
                    if not sprpInvalidSize then
                        sprpInvalidSize = true
                        ErrorNoHalt(string.format(
                            "SplashSWEPs/BSPLoader: StaticPropLump_t has unknown format.\n"
                            .. "    Map: %s\n"
                            .. "    Calculated size of StaticPropLump_t: %d\n"
                            .. "    StaticPropLump_t version: %d\n"
                            .. "    Suggested size of StaticPropLump_t: %d\n",
                            game.GetMap(), sizeofStaticPropLump, version, ss.bstruct(structType).Size))
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
---| Angle
---| boolean
---| number
---| string
---| Vector

---Stores all the Lumps parsed from the BSP.
---@class ss.RawBSPResults
---@field header                    ss.Binary.BSP.Header
---@field ENTITIES                  string[]
---@field PLANES                    ss.Binary.BSP.PLANES[]
---@field VERTEXES                  Vector[]
---@field EDGES                     integer[][]
---@field SURFEDGES                 integer[]
---@field FACES                     ss.Binary.BSP.FACES[]
---@field FACES_HDR                 ss.Binary.BSP.FACES_HDR[]
---@field LEAFS                     ss.Binary.BSP.LEAFS[]
---@field TEXINFO                   ss.Binary.BSP.TEXINFO[]
---@field TEXDATA                   ss.Binary.BSP.TEXDATA[]
---@field TEXDATA_STRING_TABLE      integer[]
---@field TEXDATA_STRING_DATA       string[]
---@field MODELS                    ss.Binary.BSP.MODELS[]
---@field DISPINFO                  ss.Binary.BSP.DISPINFO[]
---@field DISP_VERTS                ss.Binary.BSP.DISP_VERTS[]
---@field DISP_TRIS                 integer[]
---@field LIGHTING                  string
---@field LIGHTING_HDR              string
---@field GAME_LUMP                 ss.Binary.BSP.GAME_LUMP
---@field TexDataStringTableToIndex integer[]
---@field [string]                  BSP.DefinedStructures
ss.struct "RawBSPResults" {
    header = {
        identifier = 0,
        version = 0,
        lumps = {},
        mapRevision = 0,
    },
    ENTITIES = {},
    PLANES = {},
    VERTEXES = {},
    EDGES = {},
    SURFEDGES = {},
    FACES = {},
    FACES_HDR = {},
    LEAFS = {},
    TEXINFO = {},
    TEXDATA = {},
    TEXDATA_STRING_TABLE = {},
    TEXDATA_STRING_DATA = {},
    MODELS = {},
    DISPINFO = {},
    DISP_VERTS = {},
    DISP_TRIS = {},
    LIGHTING = "",
    LIGHTING_HDR = "",
    GAME_LUMP = { lumpCount = 0 },
    TexDataStringTableToIndex = {},
}

local GameLumpToRead = { sprp = "BSP.GAME_LUMP.sprp" }
local LUMP_INV = table.Flip(LUMP)

---List of lumps to read in the BSP file.  False to skip.
---String values mean the entire lump is an array of that type.
local LumpsToRead = {
    ENTITIES             = "String",
    PLANES               = "BSP.PLANES",
    VERTEXES             = "Vector",
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
    LIGHTING             = "Raw",
    LIGHTING_HDR         = "Raw",
    CUBEMAPS             = false,
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

---@param bsp File
---@return string
---@return integer
local function decompress(bsp)
    local current       = bsp:Tell()
    local actualSize    = ss.ReadStructureFromFile(bsp, 4)
    bsp:Seek(current)
    local actualSizeNum = ss.ReadStructureFromFile(bsp, "Long")
    local lzmaSize      = ss.ReadStructureFromFile(bsp, "Long")
    local props         = ss.ReadStructureFromFile(bsp, 5)
    local contents      = ss.ReadStructureFromFile(bsp, lzmaSize)
    local formatted     = props .. actualSize .. "\0\0\0\0" .. contents
    return util.Decompress(formatted) or "", actualSizeNum
end

---@param bsp File
---@return File
---@return integer
local function openDecompressed(bsp)
    local decompressed, length = decompress(bsp)
    file.Write("splashsweps/temp.txt", decompressed)
    return file.Open("splashsweps/temp.txt", "rb", "DATA"), length
end

---@param tmp File
local function closeDecompressed(tmp)
    tmp:Close()
    file.Delete "splashsweps/temp.txt"
end

---@param bsp File
---@param header ss.Binary.BSP.LumpHeader
---@param structType string
---@return BSP.DefinedStructures?
local function readLump(bsp, header, structType)
    local t = {} ---@type BSP.DefinedStructures|BSP.DefinedStructures[]
    local offset = header.fileOffset
    local totalLength = header.fileLength
    local elementLength = BuiltinTypeSizes[structType] or ss.bstruct(structType).Size or math.huge

    bsp:Seek(offset)
    local isCompressed = ss.ReadStructureFromFile(bsp, 4) == "LZMA"
    if isCompressed then
        bsp, totalLength = openDecompressed(bsp)
    else
        bsp:Seek(offset)
    end

    local numElements = totalLength / elementLength
    if structType == "Raw" then
        t = ss.ReadStructureFromFile(bsp, totalLength)
    elseif structType == "String" then
        t = ss.ReadStructureFromFile(bsp, totalLength):Split "\0"
    elseif numElements > 0 then
        for i = 1, numElements do
            t[i] = ss.ReadStructureFromFile(bsp, structType)
        end
    else
        ---@type BSP.DefinedStructures
        t = ss.ReadStructureFromFile(bsp, structType)
    end

    if isCompressed then
        closeDecompressed(bsp)
    end

    return t
end

---Parses the BSP structure of current map.
---@return ss.RawBSPResults?
function ss.LoadBSP()
    local t0 = SysTime()
    local bsp = file.Open(string.format("maps/%s.bsp", game.GetMap()), "rb", "GAME")
    if not bsp then return end

    print "Loading BSP file..."

    local t = ss.new "RawBSPResults"
    t.header = ss.ReadStructureFromFile(bsp, "BSP.Header")
    t.TexDataStringTableToIndex = {}
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
            bsp:Seek(header.fileOffset)
            local LZMAHeader = ss.ReadStructureFromFile(bsp, 4)
            if LZMAHeader == "LZMA" then
                local tmp = openDecompressed(bsp)
                t[idstr] = ss.ReadStructureFromFile(tmp, structType, header)
                closeDecompressed(tmp)
            else
                bsp:Seek(header.fileOffset)
                t[idstr] = ss.ReadStructureFromFile(bsp, structType, header)
            end
        end
    end

    print "    Constructing texture name table..."
    t.TexDataStringTableToIndex = table.Flip(t.TEXDATA_STRING_TABLE)

    local elapsed = math.Round((SysTime() - t0) * 1000, 2)
    print("Done.  Elapsed time: " .. elapsed .. " ms.")

    return t
end
