
-- Records of the map cache, saved by PrecachedData.WriteFile and loaded by PrecachedData.ReadFile.
-- <map>.dat is PrecachedData itself, and <map>_surfaces.dat is PrecachedData.SurfaceInfo.
-- Each record is a binary structure of Binary.struct, which lists its fields in the order in the file.
-- An array is preceded by the field of its length, which the code building the cache sets.

---@class ss
local ss = SplashSWEPs
local Binary       = ss.import "splashsweps/shared/binary/reader"
local BinaryWriter = ss.import "splashsweps/shared/binary/writer"

---@class ss.PrecachedDataModule
---@field new fun(): ss.PrecachedData Creates the root of the map cache with the defaults.
local PrecachedData = ss.module "splashsweps/shared/typing/precachedata"

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
    error("SplashSWEPs/PrecachedData: no default value for type " .. fieldType)
end

---Defines a record: registers its fields as a binary structure,
---and gives the record new() which creates an instance with every field set.
---Each field is `<type> <name> <array amount (optional)>` as Binary.struct takes.
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

---Placement of a rectangle in the ink map, which has a surface or the faces of a static prop.
---Values are in hammer units, which ss.PrecachedData.SurfaceInfo.HammerUnitsToUV converts into UV coordinates.
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
---@class ss.PrecachedData.InkMapRectangle
---@field OffsetU   number  Left position.
---@field OffsetV   number  Top position.
---@field IsRotated boolean True if the rectangle is rotated by 90 degrees in the ink map.
---@field Width     number  Width in the ink map, including the margins.
---@field Height    number  Height in the ink map, including the margins.

---@type { new: fun(): ss.PrecachedData.InkMapRectangle }
PrecachedData.InkMapRectangle = record("PrecachedData.InkMapRectangle", {
    "Float OffsetU",
    "Float OffsetV",
    "Bool  IsRotated",
    "Float Width",
    "Float Height",
})

---Fetched static prop information from the Game lump.
---@class ss.PrecachedData.StaticProp
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
---@field UnwrapIndex  integer Describes how the bounding box is unwrapped in UV space.  See GetStaticPropUVSize.
---@field InkMapRectangle ss.PrecachedData.InkMapRectangle Where the unwrapped faces of the bounding box are in the ink map.
---@field CubemapIndex integer Index to ss.PrecachedData.SurfaceInfo.Cubemaps of the cubemap the engine uses, or 0 if none.

---@type { new: fun(): ss.PrecachedData.StaticProp }
PrecachedData.StaticProp = record("PrecachedData.StaticProp", {
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
    "Byte   UnwrapIndex",  -- 1 to 3
    "Long   Skin",         -- m_Skin of StaticPropLump_t (int)
    "UShort CubemapIndex", -- MAX_MAP_CUBEMAPSAMPLES = 1024
    "PrecachedData.InkMapRectangle InkMapRectangle",
}, {
    FadeMin     = -1,
    Scale       = 1,
    UnwrapIndex = 1,
})

---Info of a triangle in a displacement to paint it.
---Element j of the displacement triangles of a surface is the triangle j of its mesh.
---@class ss.PrecachedData.DisplacementTriangle
---@field BarycentricDot1X number Parameter to calculate barycentric coordinates v.
---@field BarycentricDot1Y number
---@field BarycentricDot1Z number
---@field BarycentricDot2X number Parameter to calculate barycentric coordinates w.
---@field BarycentricDot2Y number
---@field BarycentricDot2Z number
---@field MBBPitch         number The angle of minimum bounding box, which is a rectangle in the plane of the triangle.
---@field MBBYaw           number
---@field MBBRoll          number
---@field MBBOriginX       number The origin of minimum bounding box.
---@field MBBOriginY       number
---@field MBBOriginZ       number
---@field MBBSizeX         number The size of minimum bounding box in its local coordinates.
---@field MBBSizeY         number
---3x3 rotation matrix in row-major order,
---which transforms world angles into local ones to map them to the serverside paint grid.
---@field WorldToLocalGridRotation number[]

---@type { new: fun(): ss.PrecachedData.DisplacementTriangle }
PrecachedData.DisplacementTriangle = record("PrecachedData.DisplacementTriangle", {
    "Float BarycentricDot1X",
    "Float BarycentricDot1Y",
    "Float BarycentricDot1Z",
    "Float BarycentricDot2X",
    "Float BarycentricDot2Y",
    "Float BarycentricDot2Z",
    "Float MBBPitch",
    "Float MBBYaw",
    "Float MBBRoll",
    "Float MBBOriginX",
    "Float MBBOriginY",
    "Float MBBOriginZ",
    "Float MBBSizeX",
    "Float MBBSizeY",
    "Float WorldToLocalGridRotation 9",
})

---Spatial hash of the triangles of a displacement.
---Element h + 1 of FirstTriangleIndex and NumTriangleIndices is for the cell of hash value h,
---which has the triangles DisplacementTriangles[TriangleIndices[k]]
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
---@field AABBMaxX number   Maximum component of all vertices in world coordinates, plus a margin.
---@field AABBMaxY number
---@field AABBMaxZ number
---@field AABBMinX number   Minimum component of all vertices in world coordinates, minus a margin.
---@field AABBMinY number
---@field AABBMinZ number
---3x4 matrix in row-major order, which transforms world coordinates into the serverside paint grid coordinates.
---@field WorldToLocalGrid number[]
---@field MBBPitch         number   The angle of minimum (oriented) bounding box.
---@field MBBYaw           number
---@field MBBRoll          number
---@field MBBOriginX       number   The origin of minimum (oriented) bounding box.
---@field MBBOriginY       number
---@field MBBOriginZ       number
---@field MBBSizeX         number   The size of minimum (oriented) bounding box in its local coordinates.
---@field MBBSizeY         number
---@field MBBSizeZ         number
---@field ModelIndex       integer  Index to model lump entry.
---@field PaintGridHeight  integer  The height of this surface in the serverside paint grid.
---@field PaintGridWidth   integer  The width of this surface in the serverside paint grid.
---Where the paint grid of the surface is in the ink map.
---The paint grid starts at the margin from the corner of the rectangle, and is rotated with the rectangle.
---@field InkMapRectangle ss.PrecachedData.InkMapRectangle
---Vertices of the mesh: the vertices of the polygon of a brush face, or the grid points of a displacement.
---Element k of each of the following arrays is for vertex k.
---@field NumVertices  integer
---@field PositionX    number[] Positions in world coordinates.
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
---World-space reference points to compute the ink UV coordinates, the same as the positions except for displacements.
---@field PaintOriginX number[]
---@field PaintOriginY number[]
---@field PaintOriginZ number[]
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
---@field TriangleHash ss.PrecachedData.TriangleHash Spatial hash to search triangles of displacement.
---@field NumDisplacementTriangles integer
---@field DisplacementTriangles    ss.PrecachedData.DisplacementTriangle[]? The triangles of a displacement, nil for the others.
---@field FaceLumpIndex integer? Index to face lump just used to calculate lightmap UV coordinates, not saved.
---@field MBRMatrix     VMatrix? Minimum bounding rectangle in the world, used by UVBuilder while building the cache, not saved.

---@type { new: fun(): ss.PrecachedData.Surface }
PrecachedData.Surface = record("PrecachedData.Surface", {
    "Float  AABBMaxX",
    "Float  AABBMaxY",
    "Float  AABBMaxZ",
    "Float  AABBMinX",
    "Float  AABBMinY",
    "Float  AABBMinZ",
    "Float  WorldToLocalGrid 12",
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
    "UShort PaintGridHeight", -- The diagonal of the map divided by PaintableGrid.CELL_SIZE
    "UShort PaintGridWidth",
    "PrecachedData.InkMapRectangle InkMapRectangle",
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
    "Float  PaintOriginX NumVertices",
    "Float  PaintOriginY NumVertices",
    "Float  PaintOriginZ NumVertices",
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
    "PrecachedData.TriangleHash TriangleHash",
    "UShort NumDisplacementTriangles", -- MAX_DISPTRIS = 512
    "PrecachedData.DisplacementTriangle DisplacementTriangles NumDisplacementTriangles",
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
---@field OriginX   number  Cubemap sample origin in world coordinates.
---@field OriginY   number
---@field OriginZ   number
---@field BoxMinX   number  Minimum corner of paintable face bounds using this cubemap.
---@field BoxMinY   number
---@field BoxMinZ   number
---@field BoxMaxX   number  Maximum corner of paintable face bounds using this cubemap.
---@field BoxMaxY   number
---@field BoxMaxZ   number
---@field FaceCount integer Number of paintable faces accumulated into this box.
---@field Blend     number  Parallax correction blend ratio. 0 disables correction.

---@type { new: fun(): ss.PrecachedData.CubemapInfo }
PrecachedData.CubemapInfo = record("PrecachedData.CubemapInfo", {
    "String Envmap",
    "Float  OriginX",
    "Float  OriginY",
    "Float  OriginZ",
    "Float  BoxMinX",
    "Float  BoxMinY",
    "Float  BoxMinZ",
    "Float  BoxMaxX",
    "Float  BoxMaxY",
    "Float  BoxMaxZ",
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

---Paintable surfaces built from LUMP_FACES, which PrecachedData.WriteFile saves to <map>_surfaces.dat.
---An array of no elements is nil when it is read from the cache file.
---@class ss.PrecachedData.SurfaceInfo
---@field NumLightmapsLDR       integer
---@field LightmapsLDR          ss.PrecachedData.LightmapInfo[]? Made from LUMP_FACES to pack lightmaps, indexed by the face.
---@field NumLightmapsHDR       integer
---Made from LUMP_FACES_HDR in the same way, empty if the map has no HDR lighting
---or LUMP_FACES_HDR has faces other than LUMP_FACES.
---@field LightmapsHDR          ss.PrecachedData.LightmapInfo[]?
---@field NumSurfaces           integer
---@field Surfaces              ss.PrecachedData.Surface[]? Array of paintable surfaces.
---@field SurfaceHash           ss.PrecachedData.SurfaceHash Spatial hash given to Hash.Setup.
---@field HammerUnitsToUV       number Converts hammer units of the ink map rectangles into UV coordinates.
---@field NumCubemaps           integer
---@field Cubemaps              ss.PrecachedData.CubemapInfo[]? Cubemap samples and paintable face bounds using them.

---@type { new: fun(): ss.PrecachedData.SurfaceInfo }
PrecachedData.SurfaceInfo = record("PrecachedData.SurfaceInfo", {
    "ULong  NumLightmapsLDR",
    "PrecachedData.LightmapInfo LightmapsLDR NumLightmapsLDR",
    "ULong  NumLightmapsHDR",
    "PrecachedData.LightmapInfo LightmapsHDR NumLightmapsHDR",
    "ULong  NumSurfaces",
    "PrecachedData.Surface Surfaces NumSurfaces",
    "PrecachedData.SurfaceHash SurfaceHash",
    "Float  HammerUnitsToUV",
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
---@field MinX number
---@field MinY number
---@field MinZ number
---@field MaxX number
---@field MaxY number
---@field MaxZ number

---@type { new: fun(): ss.MinimapAreaBounds }
PrecachedData.MinimapAreaBounds = record("PrecachedData.MinimapAreaBounds", {
    "Float MinX",
    "Float MinY",
    "Float MinZ",
    "Float MaxX",
    "Float MaxY",
    "Float MaxZ",
})

---Precached results of the BSP which PrecachedData.WriteFile saves to <map>.dat.
---An array of no elements is nil when it is read from the cache file.
---@class ss.PrecachedData
---@field Revision         integer  mapRevision of the BSP header the cache is built from.
---@field NumMaterialNames integer
---@field MaterialNames    string[]? List of material names used in the map ordered by the same as TEXDATA_STRING_DATA lump.
---@field NumMinimapBounds integer
---@field MinimapBounds    ss.MinimapAreaBounds[]? Bounds of each area of the map, indexed by the area number.
---@field NumModels        integer
---@field DirectionalLight ss.PrecachedData.DirectionalLight
---@field HashParameters   ss.PrecachedData.HashParameters
---@field NumStaticProps   integer
---@field StaticProps      ss.PrecachedData.StaticProp[]?
---@field NumStaticPropMDL integer
---@field StaticPropMDL    string[]? List of paths to model of static props.
---@field NumWaterSurfaces integer
---@field WaterSurfaces    ss.PrecachedData.Surface[]? Surfaces of water, which have no paint grid or placement in the ink map.
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
    "ULong  NumWaterSurfaces",
    "PrecachedData.Surface WaterSurfaces NumWaterSurfaces",
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
