
-- Shared library

---@class ss
local ss = SplashSWEPs
if not ss then return end

include "splashsweps/shared/util.lua"
include "splashsweps/shared/hash.lua"
include "splashsweps/shared/struct.lua"
include "splashsweps/shared/inkfeature.lua"
include "splashsweps/shared/inkshape.lua"
include "splashsweps/shared/inktype.lua"
include "splashsweps/shared/binary/reader.lua"
include "splashsweps/shared/paint/paint.lua"
include "splashsweps/shared/paint/paintablegrid.lua"
include "splashsweps/shared/paint/paintablesurface.lua"
include "splashsweps/shared/typing/precachedata.lua"
include "splashsweps/shared/vtf/reader.lua"
