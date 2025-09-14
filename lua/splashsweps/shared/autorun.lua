
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
end

---Resolution of serverside canvas to maintain collision detection.
ss.InkGridCellSize = 12

---Number of bits to transfer ink drop radius.
ss.MAX_INK_RADIUS_BITS = 8

---Gap between surfaces in UV coordinates in pixels.
ss.RT_MARGIN_PIXELS = 4

include "splashsweps/shared/util.lua"
include "splashsweps/shared/hash.lua"
include "splashsweps/shared/struct.lua"
include "splashsweps/shared/inkfeature.lua"
include "splashsweps/shared/inkshape.lua"
include "splashsweps/shared/inktype.lua"
include "splashsweps/shared/binary/reader.lua"
include "splashsweps/shared/binary/writer.lua"
include "splashsweps/shared/paint/paint.lua"
include "splashsweps/shared/paint/paintablegrid.lua"
include "splashsweps/shared/paint/paintablesurface.lua"
include "splashsweps/shared/touch/player.lua"
include "splashsweps/shared/typing/precachedata.lua"
include "splashsweps/shared/vtf/reader.lua"
