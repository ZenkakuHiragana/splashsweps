
-- Records of the map cache, saved by PrecachedData.WriteFile and loaded by PrecachedData.ReadFile.
-- <map>.dat is PrecachedData itself, and <map>_hdr.dat and <map>_ldr.dat are PrecachedData.SurfaceInfo.
-- Each record is a binary structure of Binary.struct, which lists its fields in the order in the file.
-- An array is preceded by the field of its length, which the code building the cache sets.

---@class ss
local ss = SplashSWEPs
local Binary       = ss.import "splashsweps/shared/binary/reader"
local BinaryWriter = ss.import "splashsweps/shared/binary/writer"
local Util         = ss.import "splashsweps/shared/util"

---@class ss.PrecachedDataModule
---@field new fun(): ss.PrecachedData Creates the root of the map cache with the defaults.
local PrecachedData = ss.module "splashsweps/shared/typing/precachedata"

---Resolutions of the ink map, which the UV arrays of the cache are indexed by.
---The client uses the last one.
PrecachedData.InkMapResolutions = { 4096, 8192, 16384 }

---Records by the names of their binary structures, to create the defaults of nested records.
local records = {} ---@type table<string, { new: fun(): table }>

---Default values of the built-in types of the fields.
local builtinDefaults = {
    Byte   = 0,
    UShort = 0,
    ULong  = 0,
    Long   = 0,
    Float  = 0,
    String = "",
} ---@type table<string, number|string>

---Creates the default value of a field from its type.
---@param fieldType string
---@return any
local function newDefault(fieldType)
    if records[fieldType] then return records[fieldType].new() end
    if fieldType == "Vector" then return Vector() end
    if fieldType == "Angle" then return Angle() end
    if builtinDefaults[fieldType] ~= nil then return builtinDefaults[fieldType] end
    error("SplashSWEPs/PrecachedData: no default value for type " .. fieldType)
end

---Defines a record: registers its fields as a binary structure,
---and gives the record new() which creates an instance with every field set.
---Each field is `<type> <name> <array amount (optional)>` as Binary.struct takes.
---The default of a field is the default of its type: a new record, Vector(), Angle(), "", or 0.
---The default of an array of a fixed amount is that many defaults,
---and that of an array whose amount is a field is an empty table.
---@param name     string The name of the binary structure.
---@param fields   string[]
---@param defaults table<string, any>? Defaults other than the above, with functions called for each instance.
---@param R        table? The table to define the record in, or a new one.
---@return table
local function record(name, fields, defaults, R)
    R = R or {}
    records[name] = R
    Binary.struct(name)(fields)
    function R.new()
        local t = {}
        for _, field in ipairs(Binary.GetFields(fields)) do
            local fieldType, key, amount = field[1], field[2], field[3]
            local default = defaults and defaults[key]
            if default ~= nil then
                t[key] = isfunction(default) and default() or default
            elseif amount == nil then
                t[key] = newDefault(fieldType)
            elseif tonumber(amount) then
                local array = {}
                for i = 1, tonumber(amount) do array[i] = newDefault(fieldType) end
                t[key] = array
            else
                t[key] = {}
            end
        end

        return t
    end

    return R
end

local function blackColor() return Color(0, 0, 0) end
local NUM_RESOLUTIONS = #PrecachedData.InkMapResolutions

---Components of Color, which the cache stores without the metatable of Color.
Binary.struct "PrecachedData.Color" {
    "Float r",
    "Float g",
    "Float b",
    "Float a",
}

---The directional light of light_environment.
---@class ss.PrecachedData.DirectionalLight
---@field Color    Color  The LDR color of the directional light.
---@field ColorHDR Color  The HDR color of the directional light. -1 means the same as LDR.
---@field ScaleHDR number HDR scale.

---@type { new: fun(): ss.PrecachedData.DirectionalLight }
PrecachedData.DirectionalLight = record("PrecachedData.DirectionalLight", {
    "PrecachedData.Color Color",
    "PrecachedData.Color ColorHDR",
    "Float               ScaleHDR",
}, {
    Color    = blackColor,
    ColorHDR = blackColor,
})

---Structure of UV coordinates for static props.
---```text
---. +-----------------------------> v
---. |
---. |            (OffsetU, OffsetV)
---. |          /^^^^^^^^^^^^^^^^^^^
---. |         /
---. |        / Height              Width
---. |       +---------+          +-------+
---. | Width |         |          |       |
---. |       +---------+   Height |       |
---. |                            |       |
---. |                            +-------+
---. |        (OffsetU, OffsetV) /
---. |        ^^^^^^^^^^^^^^^^^^^
---. V      (not rotated)         (rotated)
---. u
---```
---@class ss.PrecachedData.StaticProp.UVInfo
---Offset (left and top position) in the UV space in hammer units.
---Z indicates if this rectangle is rotated.
---@field Offset Vector
---@field Width  number Width in the UV space in hammer units, including the margins of each face.
---@field Height number Height in the UV space in hammer units, including the margins of each face.

---@type { new: fun(): ss.PrecachedData.StaticProp.UVInfo }
PrecachedData.StaticPropUVInfo = record("PrecachedData.StaticPropUVInfo", {
    "Vector Offset",
    "Float  Width",
    "Float  Height",
})

---Structure of UV coordinates.
---```text
---. +-----------------------------> v
---. |
---. |            (OffsetU, OffsetV)
---. |          /^^^^^^^^^^^^^^^^^^^
---. |         /
---. |        / Height              Width
---. |       +---------+          +-------+
---. | Width |         |          |       |
---. |       +---------+   Height |       |
---. |                            |       |
---. |                            +-------+
---. |        (OffsetU, OffsetV) /
---. |        ^^^^^^^^^^^^^^^^^^^
---. V      (not rotated)         (rotated)
---. u
---```
---@class ss.PrecachedData.UVInfo
---Rows 1 and 2 of the 3x4 matrix that transforms world coordinates into the UV space in Hammer units,
---which UVScales of the surface info scales into 0 to 1.
---@field WorldToUVRow1 number[]
---@field WorldToUVRow2 number[]
---@field OffsetU     number Left position in UV space ranging from 0 to 1.
---@field OffsetV     number Top position in UV space ranging from 0 to 1.
---@field Width       number The width of this surface in UV space ranging from 0 to 1.
---@field Height      number The height of this surface in UV space ranging from 0 to 1.

---@type { new: fun(): ss.PrecachedData.UVInfo }
PrecachedData.UVInfo = record("PrecachedData.UVInfo", {
    "Float  WorldToUVRow1 4",
    "Float  WorldToUVRow2 4",
    "Float  OffsetU",
    "Float  OffsetV",
    "Float  Width",
    "Float  Height",
})

---Fetched static prop information from the Game lump.
---@class ss.PrecachedData.StaticProp
---@field Angles       Angle   The angle of the prop.
---@field BoundsMax    Vector  OBB maximum.
---@field BoundsMin    Vector  OBB minimum.
---@field FadeMax      number  Fade-out distance which completely hides this model.
---@field FadeMin      number  Fade-out distance which starts fading.
---@field ModelIndex   integer Index to array of paths to mdl.
---@field Position     Vector  The origin.
---@field Scale        number  The model scale of this prop.
---@field Skin         integer The skin of this prop.
---@field UnwrapIndex  integer Describes how the bounding box is unwrapped in UV space.  See GetStaticPropUVSize.
---@field CubemapIndex integer Index to ss.PrecachedData.SurfaceInfo.Cubemaps of the cubemap the engine uses, or 0 if none.

---@type { new: fun(): ss.PrecachedData.StaticProp }
PrecachedData.StaticProp = record("PrecachedData.StaticProp", {
    "Angle  Angles",
    "Vector BoundsMax",
    "Vector BoundsMin",
    "Float  FadeMax",
    "Float  FadeMin",
    "ULong  ModelIndex",   -- propType of StaticPropLump_t (unsigned short) + 1
    "Vector Position",
    "Float  Scale",
    "Byte   UnwrapIndex",  -- 1 to 3
    "Long   Skin",         -- m_Skin of StaticPropLump_t (int)
    "UShort CubemapIndex", -- MAX_MAP_CUBEMAPSAMPLES = 1024
}, {
    FadeMin     = -1,
    Scale       = 1,
    UnwrapIndex = 1,
})

---Info of a triangle in a displacement to paint it.
---Element j of the triangles of a surface is the triangle j of its mesh.
---@class ss.PrecachedData.DisplacementTriangle
---@field BarycentricDot1 Vector  Parameter to calculate barycentric coordinates v.
---@field BarycentricDot2 Vector  Parameter to calculate barycentric coordinates w.
---@field MBBAngles       Angle   The angle of minimum (oriented) bounding box.
---@field MBBOrigin       Vector  The origin of minimum (oriented) bounding box.
---@field MBBSize         Vector  The size of minimum (oriented) bounding box in their local coordinates.
---3x3 rotation matrix in row-major order,
---which transforms world angles into local ones to map them to the serverside paint grid.
---@field WorldToLocalGridRotation number[]

---@type { new: fun(): ss.PrecachedData.DisplacementTriangle }
PrecachedData.DisplacementTriangle = record("PrecachedData.DisplacementTriangle", {
    "Vector BarycentricDot1",
    "Vector BarycentricDot2",
    "Angle  MBBAngles",
    "Vector MBBOrigin",
    "Vector MBBSize",
    "Float  WorldToLocalGridRotation 9",
})

---Spatial hash of the triangles of a displacement.
---Element h + 1 of FirstTriangleIndex and NumTriangleIndices is for the cell of hash value h,
---which has the triangles Triangles[TriangleIndices[k]]
---for k = FirstTriangleIndex[h + 1], ..., FirstTriangleIndex[h + 1] + NumTriangleIndices[h + 1] - 1.
---@class ss.PrecachedData.TriangleHash
---@field NumHashValues        integer
---@field FirstTriangleIndex   integer[]?
---@field NumTriangleIndices   integer[]?
---@field TotalTriangleIndices integer
---@field TriangleIndices      integer[]?

---@type { new: fun(): ss.PrecachedData.TriangleHash }
PrecachedData.TriangleHash = record("PrecachedData.TriangleHash", {
    "UShort NumHashValues",                        -- 8 * 8 * 8 cells at most
    "ULong  FirstTriangleIndex NumHashValues",
    "UShort NumTriangleIndices NumHashValues",     -- MAX_DISPTRIS = 512
    "ULong  TotalTriangleIndices",                 -- A triangle may be in all cells
    "UShort TriangleIndices    TotalTriangleIndices",
})

---Per-surface precached data to construct paintable surface.
---@class ss.PrecachedData.Surface
---@field AABBMax            Vector   Maximum component of all vertices in world coordinates.
---@field AABBMin            Vector   Minimum component of all vertices in world coordinates.
---3x4 matrix in row-major order, which transforms world coordinates into the serverside paint grid coordinates.
---@field WorldToLocalGrid   number[]
---@field MBBAngles          Angle    The angle of minimum (oriented) bounding box.
---@field MBBOrigin          Vector   The origin of minimum (oriented) bounding box.
---@field MBBSize            Vector   The size of minimum (oriented) bounding box in their local coordinates.
---@field ModelIndex         integer  Index to model lump entry.
---@field PaintGridHeight    integer  The height of this surface in the serverside paint grid.
---@field PaintGridWidth     integer  The width of this surface in the serverside paint grid.
---Array of UV coordinates.
---One of them will be selected on mesh construction depending on the resolution of RenderTarget.
---@field UVInfo ss.PrecachedData.UVInfo[]
---Vertices of the mesh: the vertices of the polygon of a brush face, or the grid points of a displacement.
---Vertex k has its x, y, and z at 3k - 2, 3k - 1, and 3k of Positions, Normals, Tangents, Binormals,
---BumpmapUVs, and PaintOrigins, and its u and v at 2k - 1 and 2k of LightmapUVs.
---@field NumVertexCoordinates     integer  Number of the vertices times 3.
---@field Positions                number[] Positions in world coordinates.
---@field Normals                  number[]
---@field Tangents                 number[]
---@field Binormals                number[]
---Bumpmap UV coordinates of the original face in texels,
---and the blend factors toward $basetexture2, 3, and 4 as b2 + b3 * 256 + b4 * 65536.
---@field BumpmapUVs               number[]
---World-space reference points to compute the ink UV coordinates, the same as Positions except for displacements.
---@field PaintOrigins             number[]
---@field NumLightmapUVCoordinates integer  Number of the vertices times 2.
---@field LightmapUVs              number[] Lightmap UV coordinates relative to the lightmap of the face in luxels.
---Triangles of the mesh. Triangle j has the vertices VertexIndices[3j - 2], VertexIndices[3j - 1], and VertexIndices[3j],
---and its lightmap tangent and binormal at 3j - 2, 3j - 1, and 3j of LightmapTangents and LightmapBinormals.
---@field NumVertexIndices         integer  Number of the triangles times 3.
---@field VertexIndices            integer[]
---@field NumTriangleCoordinates   integer  Number of the triangles times 3.
---@field LightmapTangents         number[]
---@field LightmapBinormals        number[]
---@field TriangleHash  ss.PrecachedData.TriangleHash Spatial hash to search triangles of displacement.
---@field NumTriangles  integer
---@field Triangles     ss.PrecachedData.DisplacementTriangle[]? Array of triangles of a displacement, nil for the others.
---@field FaceLumpIndex integer? Index to face lump just used to calculate lightmap UV coordinates, not saved.
---@field MBRMatrix     VMatrix? Minimum bounding rectangle in the world, used by UVBuilder while building the cache, not saved.

---@type { new: fun(): ss.PrecachedData.Surface }
PrecachedData.Surface = record("PrecachedData.Surface", {
    "Vector AABBMax",
    "Vector AABBMin",
    "Float  WorldToLocalGrid 12",
    "Angle  MBBAngles",
    "Vector MBBOrigin",
    "Vector MBBSize",
    "UShort ModelIndex",      -- MAX_MAP_MODELS = 1024
    "UShort PaintGridHeight", -- The diagonal of the map divided by PaintableGrid.CELL_SIZE
    "UShort PaintGridWidth",
    "PrecachedData.UVInfo UVInfo " .. NUM_RESOLUTIONS,
    "UShort NumVertexCoordinates",     -- 3 * (2^4 + 1)^2 for the displacements of power 4
    "Float  Positions    NumVertexCoordinates",
    "Float  Normals      NumVertexCoordinates",
    "Float  Tangents     NumVertexCoordinates",
    "Float  Binormals    NumVertexCoordinates",
    "Float  BumpmapUVs   NumVertexCoordinates",
    "Float  PaintOrigins NumVertexCoordinates",
    "UShort NumLightmapUVCoordinates",
    "Float  LightmapUVs  NumLightmapUVCoordinates",
    "UShort NumVertexIndices",         -- 3 * MAX_DISPTRIS = 1536
    "UShort VertexIndices NumVertexIndices",
    "UShort NumTriangleCoordinates",
    "Float  LightmapTangents  NumTriangleCoordinates",
    "Float  LightmapBinormals NumTriangleCoordinates",
    "PrecachedData.TriangleHash TriangleHash",
    "UShort NumTriangles",    -- MAX_DISPTRIS = 512
    "PrecachedData.DisplacementTriangle Triangles NumTriangles",
}, {
    AABBMax = function() return Util.vector_one * -math.huge end,
    AABBMin = function() return Util.vector_one * math.huge end,
})

---A wrapper for a BSP face to cache its properties for sorting.
---@class ss.PrecachedData.LightmapInfo
---@field MaterialIndex integer Index to material names in ss.PrecachedData.MaterialNames
---@field HasLightmap   integer 0 = false, 1 = true, 2 = also has light styles
---@field Width         integer Width of the lightmap in luxels, or 0 if it has no lightmap.
---@field Height        integer Height of the lightmap in luxels, or 0 if it has no lightmap.
---@field FaceIndex     integer Index to the PrecachedData.Surface array. 0 if it does not correspond to paintable surface array.

---@type { new: fun(): ss.PrecachedData.LightmapInfo }
PrecachedData.LightmapInfo = record("PrecachedData.LightmapInfo", {
    "ULong MaterialIndex", -- MAX_MAP_TEXDATA_STRING_TABLE = 65536
    "Byte  HasLightmap",
    "Byte  Width",         -- MAX_DISP_LIGHTMAP_DIM_INCLUDING_BORDER = 128
    "Byte  Height",
    "ULong FaceIndex",     -- MAX_MAP_FACES = 65536
})

---Cubemap sample and the paintable face bounds that use it.
---@class ss.PrecachedData.CubemapInfo
---@field Envmap    string  Resolved cubemap texture name, e.g. `maps/<map>/cX_Y_Z`.
---@field Origin    Vector  Cubemap sample origin in world coordinates.
---@field BoxMin    Vector  Minimum corner of paintable face bounds using this cubemap.
---@field BoxMax    Vector  Maximum corner of paintable face bounds using this cubemap.
---@field FaceCount integer Number of paintable faces accumulated into this box.
---@field Blend     number  Parallax correction blend ratio. 0 disables correction.

---@type { new: fun(): ss.PrecachedData.CubemapInfo }
PrecachedData.CubemapInfo = record("PrecachedData.CubemapInfo", {
    "String Envmap",
    "Vector Origin",
    "Vector BoxMin",
    "Vector BoxMax",
    "ULong  FaceCount", -- MAX_MAP_FACES = 65536
    "Float  Blend",
})

---Spatial hash of the paintable surfaces.
---Element k of HashValues, FirstSurfaceIndex, and NumSurfaceIndices is for the cell of hash value HashValues[k],
---which has the surfaces PaintableSurface.Surfaces[SurfaceIndices[j]]
---for j = FirstSurfaceIndex[k], ..., FirstSurfaceIndex[k] + NumSurfaceIndices[k] - 1.
---@class ss.PrecachedData.SurfaceHash
---@field NumHashValues       integer
---@field HashValues          integer[]?
---@field FirstSurfaceIndex   integer[]?
---@field NumSurfaceIndices   integer[]?
---@field TotalSurfaceIndices integer
---@field SurfaceIndices      integer[]?

---@type { new: fun(): ss.PrecachedData.SurfaceHash }
PrecachedData.SurfaceHash = record("PrecachedData.SurfaceHash", {
    "ULong NumHashValues",
    "ULong HashValues        NumHashValues", -- 256 * 256 * 256 cells
    "ULong FirstSurfaceIndex NumHashValues",
    "ULong NumSurfaceIndices NumHashValues",
    "ULong TotalSurfaceIndices",
    "ULong SurfaceIndices    TotalSurfaceIndices",
})

---Paintable surfaces built from LUMP_FACES or LUMP_FACES_HDR.
---An array of no elements is nil when it is read from the cache file.
---@class ss.PrecachedData.SurfaceInfo
---@field NumLightmaps          integer
---@field Lightmaps             ss.PrecachedData.LightmapInfo[]? Array made from LUMP_FACES used to pack lightmaps.
---@field NumSurfaces           integer
---@field Surfaces              ss.PrecachedData.Surface[]? Array of paintable surfaces.
---@field SurfaceHash           ss.PrecachedData.SurfaceHash Spatial hash given to Hash.Setup.
---@field UVScales              number[]  Render target size index -> Hammer units to UV multiplier
---@field NumCubemaps           integer
---@field Cubemaps              ss.PrecachedData.CubemapInfo[]? Cubemap samples and paintable face bounds using them.

---@type { new: fun(): ss.PrecachedData.SurfaceInfo }
PrecachedData.SurfaceInfo = record("PrecachedData.SurfaceInfo", {
    "ULong  NumLightmaps",
    "PrecachedData.LightmapInfo Lightmaps NumLightmaps",
    "ULong  NumSurfaces",
    "PrecachedData.Surface Surfaces NumSurfaces",
    "PrecachedData.SurfaceHash SurfaceHash",
    "Float  UVScales " .. NUM_RESOLUTIONS,
    "UShort NumCubemaps", -- MAX_MAP_CUBEMAPSAMPLES = 1024
    "PrecachedData.CubemapInfo Cubemaps NumCubemaps",
})

---@class ss.PrecachedData.HashParameters
---@field GridSizeSurface integer
---@field MinGridSizeDisplacement integer
---@field NumDivisionsDisplacement integer

---@type { new: fun(): ss.PrecachedData.HashParameters }
PrecachedData.HashParameters = record("PrecachedData.HashParameters", {
    "UShort GridSizeSurface",
    "UShort MinGridSizeDisplacement",
    "UShort NumDivisionsDisplacement",
}, {
    GridSizeSurface          = 128,
    MinGridSizeDisplacement  = 32,
    NumDivisionsDisplacement = 8,
})

---Defines playable area in the map.
---@class ss.MinimapAreaBounds
---@field maxs Vector
---@field mins Vector

---@type { new: fun(): ss.MinimapAreaBounds }
PrecachedData.MinimapAreaBounds = record("PrecachedData.MinimapAreaBounds", {
    "Vector maxs",
    "Vector mins",
})

---Precached results of the BSP which PrecachedData.WriteFile saves to <map>.dat.
---An array of no elements is nil when it is read from the cache file.
---@class ss.PrecachedData
---@field Revision            integer  mapRevision of the BSP header the cache is built from.
---@field NumMaterialNames    integer
---@field MaterialNames       string[]? List of material names used in the map ordered by the same as TEXDATA_STRING_DATA lump.
---@field NumMinimapBounds    integer
---@field MinimapBounds       ss.MinimapAreaBounds[]? Bounds of each area of the map, indexed by the area number.
---@field NumModels           integer
---@field DirectionalLight    ss.PrecachedData.DirectionalLight
---@field HashParameters      ss.PrecachedData.HashParameters
---@field NumStaticProps      integer
---@field StaticProps         ss.PrecachedData.StaticProp[]?
---@field NumStaticPropMDL    integer
---@field StaticPropMDL       string[]? List of paths to model of static props.
---Placement of the static props in the ink map for HDR,
---the element (i - 1) * #PrecachedData.InkMapResolutions + r for the static prop i and the resolution r.
---@field NumStaticPropHDR    integer
---@field StaticPropHDR       ss.PrecachedData.StaticProp.UVInfo[]?
---@field NumStaticPropLDR    integer
---@field StaticPropLDR       ss.PrecachedData.StaticProp.UVInfo[]? The same as StaticPropHDR for LDR.
---@field NumSurfacesWaterHDR integer
---@field SurfacesWaterHDR    ss.PrecachedData.Surface[]?
---@field NumSurfacesWaterLDR integer
---@field SurfacesWaterLDR    ss.PrecachedData.Surface[]?
record("PrecachedData", {
    "Long   Revision", -- mapRevision of dheader_t (int)
    "ULong  NumMaterialNames",
    "String MaterialNames NumMaterialNames",
    "UShort NumMinimapBounds", -- The area number is 9 bits
    "PrecachedData.MinimapAreaBounds MinimapBounds NumMinimapBounds",
    "UShort NumModels", -- MAX_MAP_MODELS = 1024
    "PrecachedData.DirectionalLight DirectionalLight",
    "PrecachedData.HashParameters HashParameters",
    "ULong  NumStaticProps",
    "PrecachedData.StaticProp StaticProps NumStaticProps",
    "ULong  NumStaticPropMDL",
    "String StaticPropMDL NumStaticPropMDL",
    "ULong  NumStaticPropHDR",
    "PrecachedData.StaticPropUVInfo StaticPropHDR NumStaticPropHDR",
    "ULong  NumStaticPropLDR",
    "PrecachedData.StaticPropUVInfo StaticPropLDR NumStaticPropLDR",
    "ULong  NumSurfacesWaterHDR",
    "PrecachedData.Surface SurfacesWaterHDR NumSurfacesWaterHDR",
    "ULong  NumSurfacesWaterLDR",
    "PrecachedData.Surface SurfacesWaterLDR NumSurfacesWaterLDR",
}, nil, PrecachedData)

---Writes a record to a cache file in the data folder, after the cache version, without compression.
---PrecachedData.CompressFile compresses it afterwards,
---so that the caller can release the record before the compression needs memory.
---@param path     string Path in the data folder.
---@param typename string The name of the binary structure of the record.
---@param value    table
function PrecachedData.WriteFile(path, typename, value)
    local f = file.Open(path, "wb", "DATA")
    f:WriteLong(ss.CACHE_VERSION)
    BinaryWriter.Write(f, typename, value)
    f:Close()
end

---Compresses a cache file written by PrecachedData.WriteFile in place.
---@param path string Path in the data folder.
function PrecachedData.CompressFile(path)
    file.Write(path, util.Compress(file.Read(path, "DATA")))
end

---Reads a record from a cache file written by PrecachedData.WriteFile and PrecachedData.CompressFile.
---@param path     string Path in the data folder.
---@param typename string The name of the binary structure of the record.
---@return any # The record of the binary structure, or nil if the file is missing, broken, or written by another version of the cache.
function PrecachedData.ReadFile(path, typename)
    local data = util.Decompress(file.Read(path, "DATA") or "")
    if not data or #data < 4 then return end
    local reader = Binary.NewStringReader(data)
    if Binary.Read(reader, "Long") ~= ss.CACHE_VERSION then return end
    return Binary.Read(reader, typename)
end

return PrecachedData
