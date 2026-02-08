
-- Shared library

---@class ss
local ss = SplashSWEPs
if not ss then return end
if not ss.Locals then
    ---Various temporary tables used in limited files.
    ---@class ss.Locals
    ss.Locals = {}

    ---A set of event handlers with interactions to painted ink.
    ---@type table<string, ss.IInkFeature>
    ss.InkFeatures = {}

    ---Internal shape index --> ss.InkShape object
    ---@type ss.InkShape[]
    ss.InkShapes = {}

    ---Definition of ink type (color and functionality)
    ---@type ss.InkType[]
    ss.InkTypes = {}

    ---Lookup table equals to table.Flip(ss.PlayersReady).
    ---@type table<Player, integer>
    ss.PlayerIndices = {}

    ---List of players ready to network.
    ---@type Player[]
    ss.PlayersReady = {}

    ---Array of paintable surfaces.
    ---@type ss.PaintableSurface[]
    ss.SurfaceArray = {}

    ---A hash table to represent grid separation of paintable surfaces
    --- `= { [hash] = { i1, i2, i3, ... }, ... }`
    ---where `i` is index of `ss.SurfaceArray`
    ---@type table<integer, integer[]>
    ss.SurfaceHash = {}

    ---@class ss.HashParameters
    ---@field GridSizeSurface integer Grid cell size for spatial hashing surfaces in the world.
    ---@field MinGridSizeDisplacement integer Minimum grid cell size for spatial hashing triangles in a displacement.
    ---@field NumDivisionsDisplacement integer Number of divisions to partition AABB containing triangles of a displacement.
    ss.HashParameters = {
        GridSizeSurface = 128,
        MinGridSizeDisplacement = 32,
        NumDivisionsDisplacement = 8,
    }
end

---Resolution of serverside canvas to maintain collision detection.
ss.InkGridCellSize = 12

---Number of bits to transfer ink drop radius.
ss.MAX_INK_RADIUS_BITS = 8

---Gap between surfaces in UV coordinates in pixels.
ss.RT_MARGIN_PIXELS = 4

---Indicates if this game is a single player game.
ss.sp = game.SinglePlayer()

include "splashsweps/shared/util.lua"
include "splashsweps/shared/hash.lua"
include "splashsweps/shared/struct.lua"
include "splashsweps/shared/inkfeature.lua"
include "splashsweps/shared/inkshape.lua"
include "splashsweps/shared/inktype.lua"
include "splashsweps/shared/binary/reader.lua"
include "splashsweps/shared/binary/writer.lua"
include "splashsweps/shared/packer/packer.lua"
include "splashsweps/shared/packer/structures.lua"
include "splashsweps/shared/paint/paint.lua"
include "splashsweps/shared/paint/paintablegrid.lua"
include "splashsweps/shared/paint/paintablesurface.lua"
include "splashsweps/shared/touch/player.lua"
include "splashsweps/shared/typing/precachedata.lua"
include "splashsweps/shared/vtf/reader.lua"
