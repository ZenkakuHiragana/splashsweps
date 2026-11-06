
-- Records of the map cache, saved by MapCache.WriteFile and loaded by MapCache.ReadFile.
-- <map>.dat is MapCache itself.
-- Each record is a binary structure of BinaryStruct.Define, which lists its fields in the order in the file.
-- An array is preceded by the field of its length, which the code building the cache sets.

---@class ss
local ss = SplashSWEPs
local BinaryReader = ss.import "splashsweps/shared/binary/reader"
local BinaryStruct = ss.import "splashsweps/shared/binary/struct"
local BinaryWriter = ss.import "splashsweps/shared/binary/writer"

---@class ss.MapCacheModule
---@field new fun(): ss.MapCache Creates the root of the map cache with the defaults.
local MapCache = ss.module "splashsweps/shared/mapcache/mapcache"

---Records by the names of their binary structures, to create the defaults of nested records.
local records = {} ---@type table<string, { new: fun(): table }>

---Default values of the built-in types of the fields.
local builtinDefaults = {
    Bool   = false,
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
    if builtinDefaults[fieldType] ~= nil then return builtinDefaults[fieldType] end
    error("SplashSWEPs/MapCache: no default value for type " .. fieldType)
end

---Defines a record: registers its fields as a binary structure,
---and gives the record new() which creates an instance with every field set.
---Each field is `<type> <name> <array amount (optional)>` as BinaryStruct.Define takes.
---The default of a field is the default of its type: a new record, "", or 0.
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
    BinaryStruct.Define(name)(fields)
    function R.new()
        local t = {}
        for _, field in ipairs(BinaryStruct.GetFields(fields)) do
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

---Placement of a rectangle in the ink map, which has a surface or the sides of a static prop.
---Values are in hammer units, which ss.MapCache.HammerUnitsToUV converts into UV coordinates.
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
---@class ss.MapCache.InkMapRectangle
---@field OffsetU   number  Left position.
---@field OffsetV   number  Top position.
---@field IsRotated boolean True if the rectangle is rotated by 90 degrees in the ink map.
---@field Width     number  Width in the ink map, including the margins.
---@field Height    number  Height in the ink map, including the margins.

---@type { new: fun(): ss.MapCache.InkMapRectangle }
MapCache.InkMapRectangle = record("MapCache.InkMapRectangle", {
    "Float OffsetU",
    "Float OffsetV",
    "Bool  IsRotated",
    "Float Width",
    "Float Height",
})

---Fetched static prop information from the Game lump.
---@class ss.MapCache.StaticProp
---@field Pitch        number  The angle of the prop.
---@field Yaw          number
---@field Roll         number
---@field BoundsMaxX   number  OBB maximum in the local coordinates of the prop.
---@field BoundsMaxY   number
---@field BoundsMaxZ   number
---@field BoundsMinX   number  OBB minimum in the local coordinates of the prop.
---@field BoundsMinY   number
---@field BoundsMinZ   number
---@field FadeMax      number  Fade-out distance which completely hides this model.
---@field FadeMin      number  Fade-out distance which starts fading.
---@field ModelIndex   integer Index to array of paths to mdl.
---@field PositionX    number  The origin.
---@field PositionY    number
---@field PositionZ    number
---@field Scale        number  The model scale of this prop.
---@field Skin         integer The skin of this prop.
---@field ShortestAxis integer The axis of the shortest edge of the bounding box, 1 to 3 for X, Y, and Z. See GetStaticPropUVSize.
---@field InkMapRectangle ss.MapCache.InkMapRectangle Where the unwrapped sides of the bounding box are in the ink map.
---@field Envmap       string  The cubemap texture the engine uses for this prop, `maps/<map>/cX_Y_Z` without ".hdr", or "" if the map has no cubemaps.

---@type { new: fun(): ss.MapCache.StaticProp }
MapCache.StaticProp = record("MapCache.StaticProp", {
    "Float  Pitch",
    "Float  Yaw",
    "Float  Roll",
    "Float  BoundsMaxX",
    "Float  BoundsMaxY",
    "Float  BoundsMaxZ",
    "Float  BoundsMinX",
    "Float  BoundsMinY",
    "Float  BoundsMinZ",
    "Float  FadeMax",
    "Float  FadeMin",
    "ULong  ModelIndex",   -- propType of StaticPropLump_t (unsigned short) + 1
    "Float  PositionX",
    "Float  PositionY",
    "Float  PositionZ",
    "Float  Scale",
    "Byte   ShortestAxis", -- 1 to 3 for X, Y, and Z
    "Long   Skin",         -- m_Skin of StaticPropLump_t (int)
    "String Envmap",
    "MapCache.InkMapRectangle InkMapRectangle",
}, {
    FadeMin     = -1,
    Scale       = 1,
    ShortestAxis = 1,
})

---Info of a triangle in a displacement to paint it.
---Element j of the displacement triangles of a surface is the triangle j of its mesh.
---@class ss.MapCache.DisplacementTriangle
---@field BarycentricDot1X number Parameter to calculate barycentric coordinates v.
---@field BarycentricDot1Y number
---@field BarycentricDot1Z number
---@field BarycentricDot2X number Parameter to calculate barycentric coordinates w.
---@field BarycentricDot2Y number
---@field BarycentricDot2Z number
---3x3 rotation matrix in row-major order from the triangle to its triangle of the flat positions,
---which maps the angles of a paint on the triangle onto the flat surface.
---@field ToFlatRotation number[]

---@type { new: fun(): ss.MapCache.DisplacementTriangle }
MapCache.DisplacementTriangle = record("MapCache.DisplacementTriangle", {
    "Float BarycentricDot1X",
    "Float BarycentricDot1Y",
    "Float BarycentricDot1Z",
    "Float BarycentricDot2X",
    "Float BarycentricDot2Y",
    "Float BarycentricDot2Z",
    "Float ToFlatRotation 9",
})

---Spatial hash of the triangles of a displacement.
---Element h + 1 of FirstTriangleIndex and NumTriangleIndices is for the cell of hash value h,
---which has the triangles DisplacementTriangles[TriangleIndices[k]]
---for k = FirstTriangleIndex[h + 1], ..., FirstTriangleIndex[h + 1] + NumTriangleIndices[h + 1] - 1.
---@class ss.MapCache.TriangleHash
---@field NumHashValues        integer
---@field FirstTriangleIndex   integer[]?
---@field NumTriangleIndices   integer[]?
---@field TotalTriangleIndices integer
---@field TriangleIndices      integer[]?

---@type { new: fun(): ss.MapCache.TriangleHash }
MapCache.TriangleHash = record("MapCache.TriangleHash", {
    "UShort NumHashValues",                        -- 8 * 8 * 8 cells at most
    "ULong  FirstTriangleIndex NumHashValues",
    "UShort NumTriangleIndices NumHashValues",     -- MAX_DISPTRIS = 512
    "ULong  TotalTriangleIndices",                 -- A triangle may be in all cells
    "UShort TriangleIndices    TotalTriangleIndices",
})

---Per-surface record of the map cache to construct a paintable surface.
---Its positions, directions, and transforms are in the coordinates of the surface:
---those of its BSP model, which are the world coordinates for the worldspawn.
---@class ss.MapCache.Surface
---@field AABBMaxX number   Maximum component of all vertices in the coordinates of the surface, plus a margin.
---@field AABBMaxY number
---@field AABBMaxZ number
---@field AABBMinX number   Minimum component of all vertices in the coordinates of the surface, minus a margin.
---@field AABBMinY number
---@field AABBMinZ number
---3x4 matrix in row-major order, which transforms the coordinates of the surface into the paintable grid coordinates.
---@field ToGrid number[]
---@field MBBPitch            number   The angle of minimum (oriented) bounding box.
---@field MBBYaw              number
---@field MBBRoll             number
---@field MBBOriginX          number   The origin of minimum (oriented) bounding box.
---@field MBBOriginY          number
---@field MBBOriginZ          number
---@field MBBSizeX            number   The size of minimum (oriented) bounding box in its local coordinates.
---@field MBBSizeY            number
---@field MBBSizeZ            number
---@field ModelIndex          integer  Index to model lump entry.
---@field PaintableGridHeight integer  The height of this surface in the paintable grid.
---@field PaintableGridWidth  integer  The width of this surface in the paintable grid.
---Where the paintable grid of the surface is in the ink map.
---The paintable grid starts at the margin from the corner of the rectangle, and is rotated with the rectangle.
---@field InkMapRectangle ss.MapCache.InkMapRectangle
---Vertices of the mesh: the vertices of the polygon of a brush face, or the grid points of a displacement.
---Element k of each of the following arrays is for vertex k.
---@field NumVertices  integer
---@field PositionX    number[] Positions in the coordinates of the surface.
---@field PositionY    number[]
---@field PositionZ    number[]
---@field NormalX      number[]
---@field NormalY      number[]
---@field NormalZ      number[]
---@field TangentX     number[]
---@field TangentY     number[]
---@field TangentZ     number[]
---@field BinormalX    number[]
---@field BinormalY    number[]
---@field BinormalZ    number[]
---@field BumpmapU     number[] Bumpmap UV coordinates of the original face in texels.
---@field BumpmapV     number[]
---Blend factors toward $basetexture2, 3, and 4 in the unit of the vertex color, from 0 to 255.
---@field Blend2       number[]
---@field Blend3       number[]
---@field Blend4       number[]
---Reference points in the coordinates of the surface to compute the ink UV coordinates, the same as the positions except for displacements.
---@field FlatPositionX number[]
---@field FlatPositionY number[]
---@field FlatPositionZ number[]
---@field LightmapU    number[] Lightmap UV coordinates relative to the lightmap of the face in luxels.
---@field LightmapV    number[]
---Triangles of the mesh. Triangle j has the vertices VertexIndices[3j - 2], VertexIndices[3j - 1], and VertexIndices[3j].
---Element j of the lightmap tangents and binormals is for triangle j.
---@field NumTriangles      integer
---@field NumVertexIndices  integer Number of the triangles times 3.
---@field VertexIndices     integer[]
---@field LightmapTangentX  number[]
---@field LightmapTangentY  number[]
---@field LightmapTangentZ  number[]
---@field LightmapBinormalX number[]
---@field LightmapBinormalY number[]
---@field LightmapBinormalZ number[]
---@field TriangleHash ss.MapCache.TriangleHash Spatial hash to search triangles of displacement.
---@field NumDisplacementTriangles integer
---@field DisplacementTriangles    ss.MapCache.DisplacementTriangle[]? The triangles of a displacement, nil for the others.
---@field FaceLumpIndex integer? Index to face lump just used to calculate lightmap UV coordinates, not saved.
---@field MBRMatrix     VMatrix? Minimum bounding rectangle in the coordinates of the surface, used by UVBuilder while building the cache, not saved.

---@type { new: fun(): ss.MapCache.Surface }
MapCache.Surface = record("MapCache.Surface", {
    "Float  AABBMaxX",
    "Float  AABBMaxY",
    "Float  AABBMaxZ",
    "Float  AABBMinX",
    "Float  AABBMinY",
    "Float  AABBMinZ",
    "Float  ToGrid 12",
    "Float  MBBPitch",
    "Float  MBBYaw",
    "Float  MBBRoll",
    "Float  MBBOriginX",
    "Float  MBBOriginY",
    "Float  MBBOriginZ",
    "Float  MBBSizeX",
    "Float  MBBSizeY",
    "Float  MBBSizeZ",
    "UShort ModelIndex",      -- MAX_MAP_MODELS = 1024
    "UShort PaintableGridHeight", -- The diagonal of the map divided by PaintableGrid.CELL_SIZE
    "UShort PaintableGridWidth",
    "MapCache.InkMapRectangle InkMapRectangle",
    "UShort NumVertices",     -- (2^4 + 1)^2 for the displacements of power 4
    "Float  PositionX    NumVertices",
    "Float  PositionY    NumVertices",
    "Float  PositionZ    NumVertices",
    "Float  NormalX      NumVertices",
    "Float  NormalY      NumVertices",
    "Float  NormalZ      NumVertices",
    "Float  TangentX     NumVertices",
    "Float  TangentY     NumVertices",
    "Float  TangentZ     NumVertices",
    "Float  BinormalX    NumVertices",
    "Float  BinormalY    NumVertices",
    "Float  BinormalZ    NumVertices",
    "Float  BumpmapU     NumVertices",
    "Float  BumpmapV     NumVertices",
    "Float  Blend2       NumVertices",
    "Float  Blend3       NumVertices",
    "Float  Blend4       NumVertices",
    "Float  FlatPositionX NumVertices",
    "Float  FlatPositionY NumVertices",
    "Float  FlatPositionZ NumVertices",
    "Float  LightmapU    NumVertices",
    "Float  LightmapV    NumVertices",
    "UShort NumTriangles",     -- MAX_DISPTRIS = 512
    "UShort NumVertexIndices", -- 3 * MAX_DISPTRIS = 1536
    "UShort VertexIndices NumVertexIndices",
    "Float  LightmapTangentX  NumTriangles",
    "Float  LightmapTangentY  NumTriangles",
    "Float  LightmapTangentZ  NumTriangles",
    "Float  LightmapBinormalX NumTriangles",
    "Float  LightmapBinormalY NumTriangles",
    "Float  LightmapBinormalZ NumTriangles",
    "MapCache.TriangleHash TriangleHash",
    "UShort NumDisplacementTriangles", -- MAX_DISPTRIS = 512
    "MapCache.DisplacementTriangle DisplacementTriangles NumDisplacementTriangles",
})

---A wrapper for a BSP face to cache its properties for sorting.
---@class ss.MapCache.LightmapInfo
---@field MaterialIndex integer Index to material names in ss.MapCache.MaterialNames
---@field HasLightmap   integer 0 = false, 1 = true, 2 = also has light styles
---@field Width         integer Width of the lightmap in luxels, or 0 if it has no lightmap.
---@field Height        integer Height of the lightmap in luxels, or 0 if it has no lightmap.
---@field SurfaceIndex  integer Index to the MapCache.Surface array, or 0 if the face has no paintable surface.

---@type { new: fun(): ss.MapCache.LightmapInfo }
MapCache.LightmapInfo = record("MapCache.LightmapInfo", {
    "ULong MaterialIndex", -- MAX_MAP_TEXDATA_STRING_TABLE = 65536
    "Byte  HasLightmap",
    "Byte  Width",         -- MAX_DISP_LIGHTMAP_DIM_INCLUDING_BORDER = 128
    "Byte  Height",
    "ULong SurfaceIndex",  -- MAX_MAP_FACES = 65536
})

---@class ss.MapCache.HashParameters
---@field MinGridSizeDisplacement integer
---@field NumDivisionsDisplacement integer

---@type { new: fun(): ss.MapCache.HashParameters }
MapCache.HashParameters = record("MapCache.HashParameters", {
    "UShort MinGridSizeDisplacement",
    "UShort NumDivisionsDisplacement",
}, {
    MinGridSizeDisplacement  = 32,
    NumDivisionsDisplacement = 8,
})

---Defines playable area in the map.
---@class ss.MapCache.MinimapAreaBounds
---@field MinX number
---@field MinY number
---@field MinZ number
---@field MaxX number
---@field MaxY number
---@field MaxZ number

---@type { new: fun(): ss.MapCache.MinimapAreaBounds }
MapCache.MinimapAreaBounds = record("MapCache.MinimapAreaBounds", {
    "Float MinX",
    "Float MinY",
    "Float MinZ",
    "Float MaxX",
    "Float MaxY",
    "Float MaxZ",
})

---The root record of the map cache, the results of the BSP which MapCache.WriteFile saves to <map>.dat.
---An array of no elements is nil when it is read from the cache file.
---@class ss.MapCache
---@field NumMaterialNames integer
---@field MaterialNames    string[]? List of material names used in the map ordered by the same as TEXDATA_STRING_DATA lump.
---@field NumMinimapBounds integer
---@field MinimapBounds    ss.MapCache.MinimapAreaBounds[]? Bounds of each area of the map, indexed by the area number.
---@field NumModels        integer
---@field HashParameters   ss.MapCache.HashParameters
---@field NumStaticProps   integer
---@field StaticProps      ss.MapCache.StaticProp[]?
---@field NumStaticPropMDL integer
---@field StaticPropMDL    string[]? List of paths to model of static props.
---@field NumWaterSurfaces integer
---@field WaterSurfaces    ss.MapCache.Surface[]? Surfaces of water, which have no paintable grid or placement in the ink map.
---@field NumLightmapsLDR  integer
---@field LightmapsLDR     ss.MapCache.LightmapInfo[]? Made from LUMP_FACES to pack lightmaps, indexed by the face.
---@field NumLightmapsHDR  integer
---Made from LUMP_FACES_HDR in the same way, empty if the map has no HDR lighting
---or LUMP_FACES_HDR has faces other than LUMP_FACES.
---@field LightmapsHDR     ss.MapCache.LightmapInfo[]?
---@field NumSurfaces      integer
---@field Surfaces         ss.MapCache.Surface[]? Paintable surfaces built from LUMP_FACES.
---@field HammerUnitsToUV  number Converts hammer units of the ink map rectangles into UV coordinates.
record("MapCache", {
    "ULong  NumMaterialNames",
    "String MaterialNames NumMaterialNames",
    "UShort NumMinimapBounds", -- The area number is 9 bits
    "MapCache.MinimapAreaBounds MinimapBounds NumMinimapBounds",
    "UShort NumModels", -- MAX_MAP_MODELS = 1024
    "MapCache.HashParameters HashParameters",
    "ULong  NumStaticProps",
    "MapCache.StaticProp StaticProps NumStaticProps",
    "ULong  NumStaticPropMDL",
    "String StaticPropMDL NumStaticPropMDL",
    "ULong  NumWaterSurfaces",
    "MapCache.Surface WaterSurfaces NumWaterSurfaces",
    "ULong  NumLightmapsLDR",
    "MapCache.LightmapInfo LightmapsLDR NumLightmapsLDR",
    "ULong  NumLightmapsHDR",
    "MapCache.LightmapInfo LightmapsHDR NumLightmapsHDR",
    "ULong  NumSurfaces",
    "MapCache.Surface Surfaces NumSurfaces",
    "Float  HammerUnitsToUV",
}, nil, MapCache)

---Writes the map cache to a temporary file in the data folder, after the cache version and the map revision,
---without compression. MapCache.CompressFile compresses it into the cache file afterwards,
---so that the caller can release the cache before the compression needs memory,
---and the cache file never holds the uncompressed data even if the game crashes in between.
---@param path     string Path of the temporary file in the data folder.
---@param revision integer mapRevision of the BSP header the cache is built from.
---@param cache    ss.MapCache
function MapCache.WriteFile(path, revision, cache)
    local f = file.Open(path, "wb", "DATA")
    f:WriteLong(ss.CACHE_VERSION)
    f:WriteLong(revision)
    BinaryWriter.Write(f, "MapCache", cache)
    f:Close()
end

---Compresses a temporary file written by MapCache.WriteFile into the cache file, and deletes the temporary file.
---@param tempPath string Path of the temporary file in the data folder.
---@param path     string Path of the cache file in the data folder.
function MapCache.CompressFile(tempPath, path)
    file.Write(path, util.Compress(file.Read(tempPath, "DATA")))
    file.Delete(tempPath)
end

---Reads the map cache from a file written by MapCache.WriteFile and MapCache.CompressFile.
---It decodes the cache only if the cache version and the map revision match.
---@param path     string  Path in the data folder.
---@param revision integer The map revision the cache must be built from.
---@return ss.MapCache? # nil if the file is missing, cannot be decompressed, is shorter than the header,
---                          or is written by another version of the cache or for another revision. A truncated body raises an error.
function MapCache.ReadFile(path, revision)
    local data = util.Decompress(file.Read(path, "DATA") or "")
    if not data or #data < 8 then return end
    local reader = BinaryReader.NewStringReader(data)
    if BinaryReader.Read(reader, "Long") ~= ss.CACHE_VERSION then return end
    if BinaryReader.Read(reader, "Long") ~= revision then return end
    return BinaryReader.Read(reader, "MapCache") --[[@as ss.MapCache]]
end

return MapCache
