
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
---Definition of Lumps.
local StructureDefinitions = {
    BSPHeader = {
        "Long       identifier",
        "Long       version",
        "LumpHeader lumps 64",
        "Long       mapRevision",
        ---@class ss.BSP.Header
        ---@field identifier  integer
        ---@field version     integer
        ---@field lumps       BSP.LumpHeader[]
        ---@field mapRevision integer

        ---@class BSP.LumpHeader
        ---@field fileOffset integer
        ---@field fileLength integer
        ---@field version    integer
        ---@field fourCC     integer
    },
    CDispSubNeighbor = {
        "UShort neighbor",            -- Index into DISPINFO, 0xFFFF for no neighbor
        "Byte   neighborOrientation", -- (CCW) rotation of the neighbor with reference to this displacement
        "Byte   span",                -- Where the neighbor fits onto this side of our displacement
        "Byte   neighborSpan",        -- Where we fit onto our neighbor
        "Byte   padding",
        ---@class CDispSubNeighbor
        ---@field neighbor            integer
        ---@field neighborOrientation integer
        ---@field span                integer
        ---@field neighborSpan        integer
        ---@field padding             integer
    },
    CDispNeighbor = {
        "CDispSubNeighbor subneighbors 2",
        ---@class CDispNeighbor
        ---@field subneighbors CDispSubNeighbor[]
    },
    CDispCornerNeighbors = {
        "UShort neighbors 4", -- Indices of neighbors
        "Byte   numNeighbors",
        "Byte   padding",
        ---@class CDispCornerNeighbor
        ---@field neighbors    integer[]
        ---@field numNeighbors integer
        ---@field padding      integer
    },
    dgamelump_t = {
        "Long   id",
        "UShort flags",
        "UShort version",
        "Long   fileOffset",
        "Long   fileLength",
        ---@class dgamelunp_t
        ---@field id         integer
        ---@field flags      integer
        ---@field version    integer
        ---@field fileOffset integer
        ---@field fileLength integer
    },
    StaticProp4 = { -- version == 4
        size = 56,
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
    },
    StaticProp5 = { -- version == 5
        size = 60,
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
    },
    StaticProp6 = { -- version == 6
        size = 64,
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
    },
    StaticProp7Star = { -- version == 7 or version == 10 and size matches
        size = 72,
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
    },
    StaticProp7 = { -- version == 7
        size = 68,
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
    },
    StaticProp8 = { -- version == 8
        size = 68,
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
    },
    StaticProp9 = { -- version == 9
        size = 72,
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
    },
    StaticProp10 = { -- version == 10
        size = 76,
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
    },
    StaticProp11 = { -- version == 11
        size = 76,
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
        ---@class BSP.StaticProp
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
    },
    ENTITIES = "String",
    PLANES = {
        size = 12 + 4 + 4,
        "Vector normal",
        "Float  dist",
        "Long   axisType"
        ---@class BSP.Plane
        ---@field normal   Vector
        ---@field dist     number
        ---@field axisType integer
    },
    VERTEXES  = "Vector",
    EDGES     = { size = 2 + 2, "UShort", "UShort" },
    SURFEDGES = "Long",
    FACES = {
        size = 56,
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
        ---@class BSP.Face
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
    },
    FACES_HDR = "FACES",
    -- Completely unused in this addon so skip parsing them by commenting out.
    -- ORIGINALFACES = "FACES",
    -- BRUSHES = {
    --     size = 4 + 4 + 4,
    --     "Long firstSide",
    --     "Long numSides",
    --     "Long contents",
    -- },
    -- BRUSHSIDES = {
    --     size = 2 + 2 + 2 + 2,
    --     "UShort planeNum",
    --     "Short  texInfo",
    --     "Short  dispInfo",
    --     "Short  bevel",
    -- },
    -- NODES = {
    --     size = 32,
    --     "Long        planeNum",
    --     "Long        children 2",
    --     "ShortVector mins",
    --     "ShortVector maxs",
    --     "UShort      firstFace",
    --     "UShort      numFaces",
    --     "Short       area",
    --     "Short       padding",
    -- },
    LEAFS = {
        size = 32,
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
        ---@class BSP.Leaf
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
    },
    -- LEAFFACES = "UShort",
    -- LEAFBRUSHES = "UShort",
    TEXINFO = {
        size = 72,
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
        ---@class BSP.TexInfo
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
    },
    TEXDATA = {
        size = 4 * 3 + 4 + 4 + 4 + 4 + 4,
        "Vector reflectivity",
        "Long   nameStringTableID",
        "Long   width",
        "Long   height",
        "Long   viewWidth",
        "Long   viewHeight",
        ---@class BSP.TexData
        ---@field reflectivity      Vector
        ---@field nameStringTableID integer
        ---@field width             integer
        ---@field height            integer
        ---@field viewWidth         integer
        ---@field viewHeight        integer
    },
    TEXDATA_STRING_TABLE = "Long",
    TEXDATA_STRING_DATA = "String",
    MODELS = {
        size = 48,
        "Vector mins",
        "Vector maxs",
        "Vector origin",
        "Long   headNode",
        "Long   firstFace",
        "Long   numFaces",
        ---@class BSP.Model
        ---@field mins      Vector
        ---@field maxs      Vector
        ---@field origin    Vector
        ---@field headNode  integer
        ---@field firstFace integer
        ---@field numFaces  integer
    },
    DISPINFO = {
        size = 176,
        "Vector               startPosition",
        "Long                 dispVertStart",
        "Long                 dispTriStart",
        "Long                 power",
        "Long                 minTesselation",
        "Float                smoothingAngle",
        "Long                 contents",
        "UShort               mapFace",
        "UShort               padding",
        "Long                 lightmapAlphaTest",
        "Long                 lightmapSamplesPositionStart",
        "CDispNeighbor        edgeNeighbors   4", -- Probably these are
        "CDispCornerNeighbors cornerNeighbors 4", -- not correctly parsed
        "ULong                allowedVerts    10",
        ---@class BSP.DispInfo
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
        ---@field edgeNeighbors               CDispNeighbor[]
        ---@field cornerNeighbors             CDispCornerNeighbor[]
        ---@field allowedVerts                integer[]
    },
    DISP_VERTS = {
        size = 20,
        "Vector vec",
        "Float  dist",
        "Float  alpha",
        ---@class BSP.DispVerts
        ---@field vec   Vector
        ---@field dist  number
        ---@field alpha number
    },
    DISP_TRIS = "UShort",
    LIGHTING = "Raw",
    LIGHTING_HDR = "Raw",
    -- CUBEMAPS = {
    --     size = 16,
    --     "LongVector origin",
    --     "Long       size",
    -- },
    GAME_LUMP = {
        size = -1, -- Negative size means this is a single lump
        "Long        lumpCount",
        "dgamelump_t nil lumpCount",
        ---@class ss.BSP.GameLump
        ---@field lumpCount integer
        ---@field [integer] dgamelunp_t
    }
}
local GameLumpContents = {
    sprp = { -- Static Props
        "Long            dictEntries",
        "String128  name dictEntries",
        "Long            leafEntries",
        "UShort     leaf leafEntries",
        "Long            propEntries",
        "StaticProp prop propEntries", -- Size depends on game lump version
        ---@class BSP.sprp
        ---@field dictEntries integer
        ---@field name        string[]
        ---@field leafEntries integer
        ---@field leaf        integer[]
        ---@field propEntries integer
        ---@field prop        BSP.StaticProp[]
    },
}

---@alias BSP.DefinedStructures
---| BSP.DispInfo
---| BSP.DispVerts
---| BSP.Face
---| ss.BSP.GameLump
---| ss.BSP.Header
---| BSP.Leaf
---| BSP.Model
---| BSP.Plane
---| BSP.sprp
---| BSP.StaticProp
---| BSP.TexData
---| BSP.TexInfo
---| CDispNeighbor
---| CDispCornerNeighbor
---| dgamelunp_t
---| Angle
---| boolean
---| number
---| string
---| Vector

---Stores all the Lumps parsed from the BSP.
---@class ss.RawBSPResults
---@field header                    ss.BSP.Header
---@field ENTITIES                  string[]
---@field PLANES                    BSP.Plane[]
---@field VERTEXES                  Vector[]
---@field EDGES                     integer[][]
---@field SURFEDGES                 integer[]
---@field FACES                     BSP.Face[]
---@field FACES_HDR                 BSP.Face[]
---@field LEAFS                     BSP.Leaf[]
---@field TEXINFO                   BSP.TexInfo[]
---@field TEXDATA                   BSP.TexData[]
---@field TEXDATA_STRING_TABLE      integer[]
---@field TEXDATA_STRING_DATA       string[]
---@field MODELS                    BSP.Model[]
---@field DISPINFO                  BSP.DispInfo[]
---@field DISP_VERTS                BSP.DispVerts[]
---@field DISP_TRIS                 integer[]
---@field LIGHTING                  string
---@field LIGHTING_HDR              string
---@field GAME_LUMP                 ss.BSP.GameLump
---@field TexDataStringTableToIndex integer[]
---@field [string]                  BSP.DefinedStructures
ss.struct "RawBSPResults" {
    header = ss.new "BSP.Header",
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
    GAME_LUMP = ss.new "BSP.GameLump",
    TexDataStringTableToIndex = {},
}

---Read a value or structure from bsp file.
---The offset should correctly be set before call.
---arg should be one of the following:
---  - String for one of these:
---    - a call of `File:Read%s()`, e.g. `Long`, `Float`
---    - Additional built-in types: `Vector`, `ShortVector`, `LongVector`, `Angle`, or `SByte` (signed byte)
---    - `String` for null-terminated string
---    - `String%d` for a null-terminated string but padded to `%d` bytes.
---    - Structure name defined at StructureDefinitions
---  - Table representing a structure
---    Table containing a sequence of strings formatted as
---    `<type> <fieldname> <array amount (optional)>`
---    e.g. `Vector normal`, `Byte fourCC 4`
---    Array amount can be a field name previously defined in the same structure.
---    e.g. `{ "Long edgeCount", "UShort edgeIndices edgeCount" }`
---  - Number for `File:Read(%d)`
---  - Function for custom procedure, passing `(bsp, currentTable, ...)`
---@param bsp File
---@param arg integer|string|string[]|fun(bsp: File, ...): BSP.DefinedStructures
---@param ... any
---@return BSP.DefinedStructures?
local function read(bsp, arg, ...)
    if isfunction(arg) then
        ---@cast arg fun(bsp: File, ...): BSP.DefinedStructures
        return arg(bsp, ...)
    end
    if isnumber(arg) then
        ---@cast arg integer
        return bsp:Read(arg)
    end
    if istable(arg) then
        ---@cast arg string[]
        ---@type BSP.DefinedStructures[]
        local structure = {}
        for _, varstring in ipairs(arg) do
            ---@type string?, integer|string?, integer|string?
            local vartype, varname, arraysize = unpack(string.Explode(" +", varstring, true))
            if varname == nil or varname == "" or varname == "nil" then varname = #structure + 1 end
            if arraysize == nil or arraysize == "" then arraysize = 1 end
            ---@cast vartype -?
            if isstring(arraysize) and structure[arraysize] or tonumber(arraysize) > 1 then
                arraysize = structure[arraysize] or tonumber(arraysize) --[[@as integer]]
                for i = 1, arraysize do
                    if isstring(varname) then
                        ---@cast varname string
                        ---@cast structure table<string, BSP.DefinedStructures[]>
                        structure[varname] = structure[varname] or {}
                        structure[varname][i] = read(bsp, vartype, structure, ...)
                    else
                        ---@cast varname integer
                        structure[varname] = read(bsp, vartype, structure, ...)
                        varname = varname + 1
                    end
                end
            else
                structure[varname] = read(bsp, vartype, structure, ...)
            end
        end
        return structure
    end
    ---@cast arg string
    if arg == "Angle" then
        local pitch = bsp:ReadFloat()
        local yaw   = bsp:ReadFloat()
        local roll  = bsp:ReadFloat()
        return Angle(pitch, yaw, roll)
    elseif arg == "SByte" then
        local n = bsp:ReadByte()
        return n - (n > 127 and 256 or 0)
    elseif arg == "ShortVector" then
        local x = bsp:ReadShort()
        local y = bsp:ReadShort()
        local z = bsp:ReadShort()
        return Vector(x, y, z)
    elseif arg == "LongVector" then
        local x = bsp:ReadLong()
        local y = bsp:ReadLong()
        local z = bsp:ReadLong()
        return Vector(x, y, z)
    elseif arg:StartsWith "String" then
        local str = ""
        local chr = read(bsp, 1)
        local minlen = tonumber(arg:sub(#"String" + 1)) or 0
        local MAX_STRING_LENGTH = 1024
        while chr and chr ~= "\x00" and #str < MAX_STRING_LENGTH do
            str = str .. chr
            chr = read(bsp, 1)
        end
        for _ = 1, minlen - (#str + 1) do
            read(bsp, 1)
        end
        return str
    elseif arg == "Vector" then
        local x = bsp:ReadFloat()
        local y = bsp:ReadFloat()
        local z = bsp:ReadFloat()
        return Vector(x, y, z)
    elseif isfunction(bsp["Read" .. arg]) then
        return bsp["Read" .. arg](bsp)
    elseif StructureDefinitions[arg] then
        return read(bsp, StructureDefinitions[arg], ...)
    else
        ErrorNoHalt(string.format(
            "SplashSWEPs/BSPLoader: Need a correct structure name\n"
            .. "    Map: %s\n"
            .. "    Structure name given: %s\n",
            game.GetMap(), tostring(arg)))
    end
end

local sprpInvalidSize = false

---Reading structures from StaticProp_Lump_t
---@param bsp File
---@param struct BSP.sprp
---@param header BSP.LumpHeader
---@return BSP.DefinedStructures?
function StructureDefinitions.StaticProp(bsp, struct, header)
    local offset = struct.dictEntries * 128 + struct.leafEntries * 2 + 4 * 3
    local nextlump = header.fileOffset + header.fileLength
    local staticPropOffset = header.fileOffset + offset
    local sizeofStaticPropLump = (nextlump - staticPropOffset) / struct.propEntries
    local version = header.version
    local structType = "StaticProp" .. tostring(version)
    if not StructureDefinitions[structType] then return {} end
    if version == 7 or version == 10 and sizeofStaticPropLump == StructureDefinitions.StaticProp7Star.size then
        structType = "StaticProp7Star"
    end
    local data = read(bsp, structType)
    if sizeofStaticPropLump ~= StructureDefinitions[structType].size then
        bsp:Skip(sizeofStaticPropLump - StructureDefinitions[structType].size)
        if not sprpInvalidSize then
            sprpInvalidSize = true
            ErrorNoHalt(string.format(
                "SplashSWEPs/BSPLoader: StaticPropLump_t has unknown format.\n"
                .. "    Map: %s\n"
                .. "    Calculated size of StaticPropLump_t: %d\n"
                .. "    StaticPropLump_t version: %d\n"
                .. "    Suggested size of StaticPropLump_t: %d\n",
                game.GetMap(), sizeofStaticPropLump, version, StructureDefinitions[structType].size))
        end
    end
    return data
end

---@param bsp File
---@return BSP.DefinedStructures
function StructureDefinitions.LumpHeader(bsp)
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
    local actualSize    = read(bsp, 4)        --[[@as string]]
    bsp:Seek(current)
    local actualSizeNum = read(bsp, "Long")   --[[@as integer]]
    local lzmaSize      = read(bsp, "Long")   --[[@as integer]]
    local props         = read(bsp, 5)        --[[@as string]]
    local contents      = read(bsp, lzmaSize) --[[@as string]]
    local formatted     = props .. actualSize .. "\0\0\0\0" .. contents
    return util.Decompress(formatted) or "", actualSizeNum
end

---@param bsp File
---@return File
---@return integer
local function getDecompressed(bsp)
    local decompressed, length = decompress(bsp)
    file.Write("splashsweps/temp.txt", decompressed)
    return file.Open("splashsweps/temp.txt", "rb", "DATA"), length
end

---@param tmp File
local function closeDecompressed(tmp)
    tmp:Close()
    file.Delete "splashsweps/temp.txt"
end

local LUMP_INV = table.Flip(LUMP)
---@param name string
---@return integer
local function LookupLump(name)
    return LUMP_INV[name]
end

---@param bsp table
---@return ss.BSP.Header
local function ReadHeader(bsp)
    return read(bsp, "BSPHeader") --[[@as ss.BSP.Header]]
end

---@param bsp table
---@param headers BSP.LumpHeader[]
---@param lumpname string
---@return BSP.DefinedStructures?
local function ReadLump(bsp, headers, lumpname)
    local t = {} ---@type BSP.DefinedStructures|BSP.DefinedStructures[]?
    local header = headers[LookupLump(lumpname)]
    local offset = header.fileOffset
    local length = header.fileLength
    local struct = StructureDefinitions[lumpname]

    -- get length per struct
    local strlen = istable(struct) and struct.size or length
    if StructureDefinitions[struct] then ---@cast struct string
        strlen = StructureDefinitions[struct].size
    elseif BuiltinTypeSizes[struct] then ---@cast struct string
        strlen = BuiltinTypeSizes[struct]
    end

    bsp:Seek(offset)
    local isCompressed = read(bsp, 4) == "LZMA"
    if isCompressed then
        bsp, length = getDecompressed(bsp)
    else
        bsp:Seek(offset)
    end

    local numElements = length / strlen
    if struct == "Raw" then
        t = read(bsp, length)
    elseif struct == "String" then
        local all = read(bsp, length) --[[@as string]]
        t = all:Split "\0"
    elseif numElements > 0 then
        for i = 1, numElements do
            t[i] = read(bsp, struct, header)
        end
    else
        t = read(bsp, struct, header)
    end

    if isCompressed then closeDecompressed(bsp) end
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
    t.header = ReadHeader(bsp)
    t.TexDataStringTableToIndex = {}
    print("    BSP file version: " .. t.header.version)
    for i = 1, #LUMP do
        local lumpname = LUMP[i]
        if StructureDefinitions[lumpname] then
            print(string.format("        LUMP #%02d\t%s", i, lumpname))
            t[lumpname] = ReadLump(bsp, t.header.lumps, lumpname)
        end
    end

    print "    Loading GameLump..."
    for _, header in ipairs(t.GAME_LUMP) do
        local idstr = getGameLumpStr(header.id)
        local gamelump = GameLumpContents[idstr]
        if gamelump then
            print("        GameLump \"" .. idstr .. "\"... (version: " .. header.version .. ")")
            bsp:Seek(header.fileOffset)
            local LZMAHeader = read(bsp, 4)
            if LZMAHeader == "LZMA" then
                local tmp = getDecompressed(bsp)
                t[idstr] = read(tmp, gamelump, header)
                closeDecompressed(tmp)
            else
                bsp:Seek(header.fileOffset)
                t[idstr] = read(bsp, gamelump, header)
            end
        end
    end

    print "    Constructing texture name table..."
    for i, j in ipairs(t.TEXDATA_STRING_TABLE) do
        t.TexDataStringTableToIndex[j] = i
    end

    local elapsed = math.Round((SysTime() - t0) * 1000, 2)
    print("Done.  Elapsed time: " .. elapsed .. " ms.")

    return t
end
