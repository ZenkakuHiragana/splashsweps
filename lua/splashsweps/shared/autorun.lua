
-- Shared library

---@class ss
local ss = SplashSWEPs
if not ss then return end
if not ss.Locals then
    ---Various temporary tables used in limited files.
    ---@class ss.Locals
    ss.Locals = {}

    ---Lookup table equals to table.Flip(ss.PlayersReady).
    ---@type table<Player, integer>
    ss.PlayerIndices = {}

    ---List of players ready to network.
    ---@type Player[]
    ss.PlayersReady = {}

    ---A hash table to represent grid separation of paintable surfaces
    --- `= { [hash] = { i1, i2, i3, ... }, ... }`
    ---where `i` is index of `PaintableSurface.Surfaces`
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

---World-space margin per side in Hammer units for heightmap raymarching and adjacent face discovery.
ss.MARGIN_HAMMER_UNITS = 8

---Guard margin in pixels to prevent bilinear filtering from bleeding across packed rectangles.
ss.RT_BILINEAR_GUARD_PIXELS = 1

---Version of generated map cache files.
ss.CACHE_VERSION = 6

---Indicates if this game is a single player game.
ss.sp = game.SinglePlayer()

include "splashsweps/shared/import.lua"
include "splashsweps/shared/hash.lua"
include "splashsweps/shared/touch/player.lua"
