
-- Packs the paintable surfaces and the static props into the ink map.

---@class ss
local ss = SplashSWEPs
local RectanglePacker = ss.import "splashsweps/shared/packer/packer"
local Structures      = ss.import "splashsweps/shared/packer/structures"

---@class ss.UVBuilderModule
local UVBuilder = ss.module "splashsweps/server/mapcache/uvbuilder"

---Places rectangles in the ink map.
---Each rectangle has its size before this, and gets its position and rotation, with its size swapped if rotated.
---@param rectangles ss.PrecachedData.InkMapRectangle[]
---@return number # Converts hammer units of the rectangles into UV coordinates of the ink map.
function UVBuilder.Build(rectangles)
    print "Packing surfaces into the ink map..."
    local t0 = SysTime()
    local rects = {} ---@type ss.Rectangle[]
    for i, r in ipairs(rectangles) do
        rects[i] = Structures.MakeRectangle(r.Width, r.Height, 0, 0, r)
    end

    local packer = RectanglePacker.new(rects):packall()
    for _, index in ipairs(packer.results) do
        local rect = packer.rects[index]
        local r = rect.tag ---@cast r ss.PrecachedData.InkMapRectangle
        r.OffsetU   = rect.left
        r.OffsetV   = rect.bottom
        r.Width     = rect.width
        r.Height    = rect.height
        r.IsRotated = rect.rotated
    end

    local elapsed = math.Round((SysTime() - t0) * 1000, 2)
    print("    Packed " .. #rects .. " rectangles into "
        .. packer.maxsize .. " hammer units (" .. elapsed .. " ms)")
    return 1 / packer.maxsize
end

return UVBuilder
