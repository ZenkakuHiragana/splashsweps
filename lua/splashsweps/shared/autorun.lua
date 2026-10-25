
-- Shared library

---@class ss
local ss = SplashSWEPs
if not ss then return end
if not ss.Locals then
    ---Various temporary tables used in limited files.
    ---@class ss.Locals
    ss.Locals = {}
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
include "splashsweps/shared/touch/player.lua"
