
---@class ss
local ss = SplashSWEPs
if not ss then return end

local abs = math.abs
local assert = assert
local ipairs = ipairs
local max = math.max
local TOLERANCE = 1e-9 -- Relative tolerance

---@param a number
---@param b number
---@return boolean
local function isclose(a, b)
    return abs(a - b) <= max(TOLERANCE * max(abs(a), abs(b)), 0)
end

---An implementation of "A New Placement Heuristic
---for the Orthogonal Stock-Cutting Problem", but having two skylines.
---@param rectangles ss.Rectangle[]
---@return ss.RectanglePacker
function ss.MakeRectanglePacker(rectangles)
    ---Baseline (or skyline) definition to manage free space.  
    ---It has origin (x = offset, y = height),
    ---length, and rectangle touching it.
    ---```log
    ---  offset   <----length---->
    ------------->|===baseline===|
    ---           ^
    ---           | height
    ---           |
    ---```
    ---Rectangle packer has a list of baseline
    ---and it looks like the following:
    ---```log
    ---+--------+
    ---         |          +--------
    ---         |          |
    ---height-> @----------+
    ---         <--length-->
    ---         ^
    ---       offset
    ---```
    ---@param offset number
    ---@param length number
    ---@param height number
    ---@param rectangle integer?
    ---@return ss.RectanglePackerBaseline
    local function Baseline(offset, length, height, rectangle)
        ---@class ss.RectanglePackerBaseline
        ---@field offset    number
        ---@field length    number
        ---@field height    number
        ---@field rectangle integer?
        ---@field __type    "SplashSWEPsRectanglePackerBaseline"
        return setmetatable({
            offset = offset,
            length = length,
            height = height,
            rectangle = rectangle,
            __type = "SplashSWEPsRectanglePackerBaseline",
        }, {__tostring = function(self)
            return string.format("(%6.2f, %6.2f) = %6.2f @ %s",
            self.offset, self.height, self.length, tostring(self.rectangle))
        end})
    end

    ---@param rects ss.Rectangle[]
    local function sortinputs(rects)
        for _, r in ipairs(rects) do
            if r.istall then r:rotate() end
        end
        table.SortDesc(rects)
    end

    ---@param rects ss.Rectangle[]
    ---@return integer[]
    local function generateRotatedIndices(rects)
        local rotatedIndices = {} ---@type integer[]
        for i = 1, #rects do rotatedIndices[i] = i end
        table.sort(rotatedIndices, function(i, j)
            if rects[i].height ~= rects[j].height then
                return rects[i].height > rects[j].height
            elseif rects[i].width ~= rects[j].width then
                return rects[i].width > rects[j].width
            else
                return i > j
            end
        end)
        return rotatedIndices
    end

    sortinputs(rectangles)

    ---@class ss.RectanglePacker
    ---@field results      integer[]
    ---@field optimized    boolean[]
    ---@field rects        ss.Rectangle[]
    ---@field queue        ss.AVLTree
    ---@field queueRotated ss.AVLTree
    ---@field xbase        ss.LinkedList
    ---@field ybase        ss.LinkedList
    ---@field width        number
    ---@field height       number
    ---@field maxsize      number
    ---@field framesize    { [1]: number, [2]: number }
    ---@field __type       "SplashSWEPsRectanglePacker"
    local t = {
        results      = {},
        optimized    = {},
        rects        = rectangles,
        queue        = ss.MakeAVL(),
        queueRotated = ss.MakeAVL(),
        xbase        = ss.LinkedList(),
        ybase        = ss.LinkedList(),
    }
    ---@param self ss.RectanglePacker
    ---@param key "width"|"height"|"framesize"|"maxsize"|string
    ---@return number|{ width: number, height: number }|any
    local function __index(self, key)
        local sum = 0
        if key == "width" then
            for _, v in self.xbase() do sum = max(sum, v.value.height) end
            return sum
        elseif key == "height" then
            for _, v in self.ybase() do sum = max(sum, v.value.height) end
            return sum
        elseif key == "framesize" then
            return { self.width, self.height }
        elseif key == "maxsize" then
            return max(self.width, self.height)
        else
            return rawget(self, key)
        end
    end

    local rrects = generateRotatedIndices(t.rects)
    for i, r in ipairs(t.rects) do t.queue:insert(-r.width, i) end
    for _, i in ipairs(rrects) do t.queueRotated:insert(-t.rects[i].height, i) end
    if #rectangles > 0 then
        t.xbase:append(Baseline(0, t.rects[1].width, 0))
        t.ybase:append(Baseline(0, t.rects[1].height, 0))
    end

    ---@param a ss.LinkedListCell?
    ---@param b ss.LinkedListCell?
    ---@return ss.LinkedListCell
    local function pickLowest(a, b)
        if not a then return b --[[@as ss.LinkedListCell]] end
        if not b then return a --[[@as ss.LinkedListCell]] end
        local A = max(a.value.offset, a.value.height)
        local B = max(b.value.offset, b.value.height)
        return A < B and a or b
    end

    ---Returns the smallest baseline, with respect to larger positional components.  
    ---That means to select the following using a line y = x:
    ---
    ---1. For ones in the area between y = x and x-axis, pick the leftmost one.
    ---2. For ones in the area between y = x and y-axis, pick the lowest one.
    ---
    ---If these two choises have the same score, `prefer_y` is used to decide one.
    ---```log
    ---y
    ---^
    ---|  returns
    ---|  lowest one       /
    ---|---  v  ------  / y = x
    ---|   =====     /
    ---|          /  ||
    ---|       /     ||
    ---|    /      ||<= returns
    ---| /         ||   leftmost one
    ---+----------------------------> x
    ---```
    ---@param prefer_y boolean
    ---@return ss.LinkedListCell
    ---@return boolean
    ---@return boolean
    function t:getlowest(prefer_y)
        ---@type ss.LinkedListCell?, ss.LinkedListCell? Calculated in O(N = # of baseline segments)
        local xmin, ymin
        for _, v in self.xbase() do xmin = pickLowest(xmin, v) end
        for _, v in self.ybase() do ymin = pickLowest(ymin, v) end

        -- Calculated in a constant time
        local xdist = max(xmin.value.offset, xmin.value.height)
        local ydist = max(ymin.value.offset, ymin.value.height)
        if xdist == ydist then
            return prefer_y and ymin or xmin, prefer_y, true
        elseif xdist > ydist then
            return ymin, true, false
        else
            return xmin, false, false
        end
    end

    ---Changes the given baseline `origin` to that of adjacent one to fill the gap.  
    ---For x-baseline:
    ---```log
    ---       Fills this baseline
    ---    ------+     v
    ---          |==========+---------
    ---          |          |
    ---          +----------+
    ---          ^
    ---        origin
    ---```
    ---For y-baseline:
    ---```log
    ---                        |
    ---             +----------+
    ---             |    ||
    ---             |    || <= Fill this
    ---             |    ||       baseline
    ---   origin -> +-----+
    ---                   |
    ---                   |
    ---```
    ---@param origin ss.LinkedListCell
    ---@return boolean merged indicates if baseline was merged
    function t:fillline(origin)
        -- If the previous one exists,
        -- and it is higher than the current,
        -- and satisfying either of the following:
        -- (1) the following one does not exist
        -- (2) it is lower than the following one
        --                  +- - - - - +
        -- +-------+
        --         |        |
        --         +--------+
        local before, after = origin.before, origin.after
        local hbase = origin.value.height
        local hbefore = before and before.value.height ---@cast hbefore -?
        local hafter = after and after.value.height ---@cast hafter -?
        local can_merge_before = hbefore and hbefore >= hbase
        local can_merge_after = hafter and hafter >= hbase
        if can_merge_before and can_merge_after then
            can_merge_after = hbefore >= hafter
            can_merge_before = hbefore < hafter
        end

        if can_merge_before then ---@cast before -?
            before.value.length = before.value.length + origin.value.length
            before.value.height = hbefore
            origin:remove()
        -- Or vice-versa
        -- +- - - -+
        --                  +----------
        --         |        |
        --         +--------+
        elseif can_merge_after then ---@cast after -?
            after.value.offset = after.value.offset - origin.value.length
            after.value.length = after.value.length + origin.value.length
            after.value.height = hafter
            origin:remove()
        end

        -- Merge adjacent baselines if their height are the same
        -- +-------+        +----------
        --         |        |
        --         +--------+
        if hafter and hbefore and isclose(hafter, hbefore) then
            ---@cast before -?
            ---@cast after -?
            before.value.length = before.value.length + after.value.length
            before.value.height = hbefore
            after:remove()
        end

        return can_merge_before or can_merge_after or false
    end

    ---Finds the best-fit rectangle for given length.  
    ---`y` is set to true if this forcuses along y-baseline.  
    ---Returns two values: index of the rectangle, rotation flag
    ---@param length number
    ---@param y boolean
    ---@return integer
    ---@return boolean
    function t:findrect(length, y)
        local i = self.queue:lowerbound(-length)
        local j = self.queueRotated:lowerbound(-length)
        local width, height ---@type number, number
        if i then
            width = self.rects[i.value].width
        end

        if j then
            height = self.rects[j.value].height
            if width and width < height then
                return j.value, not y
            end
        end

        if width then ---@cast i -?
            return i.value, y
        else
            return -1, false
        end
    end

    ---Find the next rectangle to be placed
    ---@return ss.LinkedListCell
    ---@return integer
    ---@return boolean
    ---@return boolean
    function t:findbestlocation()
        local prefer_y = false -- Which axis do we prefer if both are considered as candidate?
        while true do
            local x, is_y, alt = self:getlowest(prefer_y)
            local best, rotated = self:findrect(x.value.length, is_y)
            if best >= 0 then
                return x, best, rotated, is_y
            elseif alt and not prefer_y then
                prefer_y = true
            else
                prefer_y = false
                if not self:fillline(x) then
                    return x, -1, false, is_y -- Should not happen if logic is correct, but for safety
                end
            end
        end
    end

    function t:printbaseline()
        for _, x in self.xbase() do
            local e = x.before and (x.before.value.offset + x.before.value.length - x.value.offset) or 0
            print(string.format("%f,%f,  ,  ,%f\n%f,%f,  ,  ,%f",
                x.value.offset, x.value.height, e, x.value.offset + x.value.length, x.value.height, e))
        end
        for _, x in self.ybase() do
            local e = x.before and (x.before.value.offset + x.before.value.length - x.value.offset) or 0
            print(string.format("%f,  ,%f,  ,%f\n%f,  ,%f,  ,%f",
                x.value.height, x.value.offset, e, x.value.height, x.value.offset + x.value.length, e))
        end
    end

    ---Place given rectangle and apply changes to baselines
    ---```log
    ---    <-----rw---->     n
    ---  ^ +-----------+     v
    ---  | |           |     |
    --- rh | rectangle |     |
    ---  | |           |     |
    ---  v +-----------+-----+-^- --- <- xline.parent
    ---  ^ <-------Lx------->| |
    ---  | ^                 | Ly
    ---  | x                 | |
    ---  |              y -> + v
    ---  | hx                ^
    ---  |                   hy
    ---```
    ---@param ri    integer           Index of the rectangle
    ---@param xline ss.LinkedListCell Baseline to be placed on
    ---@param is_y  boolean           Is the baseline along y-axis?
    function t:placebox(ri, xline, is_y)
        local r  = self.rects[ri]
        local n  = is_y and self.xbase or self.ybase -- Baseline that is prependicular to xline
        local rw = is_y and r.height or r.width
        local rh = is_y and r.width or r.height
        local x  = xline.value.offset
        local Lx = xline.value.length
        local hx = xline.value.height
        local xend, hxend = x + rw, hx + rh
        local xbefore, xafter = xline.before, xline.after
        local xmax = max(1, x, Lx, hx, xend, hxend)

        for _, yline in n() do
            local y = yline.value.offset
            local Ly = yline.value.length
            local hy = yline.value.height
            local yend = y + Ly
            local ybefore, yafter = yline.before, yline.after
            local eps = TOLERANCE * max(xmax, y, Ly, hy, yend)

            -- Ensure the baseline is not completely inside the following area
            -- ///////////////////////XXXX             XXXX\\\\\\\\\\\\XXXX
            -- ///////////////////////XXXX             XXXX\\\\\\\\\\\\XXXX
            --      +<------rw------>+\\\\             ////+----------+////
            --      ^                |\\\\             ////^          |////
            --     rh                |\\\\             ////|          |////
            --      v                |\\\\             ////rw         |////
            --      @<=(x, hx)-------+\\\\             ////|          |////
            -- ///////////////////////XXXX             ////v          |////
            -- ///////////////////////XXXX    ---(hx, x)-->@<---rh--->+////
            --                                         ////            ////
            --                                         ////            ////
            if not (yend <= hx - eps or hy >= xend + eps or y >= hxend + eps) then
                -- In case both end points are within the rectangle
                --      +<------rw------>+                     yline
                --      ^                |                       |
                --     rh           || <-+-- yline         +-----+----+
                --      v                |                 ^     v    |
                --      @<=(x, hx)-------+                 |    ===   |
                --                                         rw         |
                --                                         |          |
                --                                         v          |
                --                            ---(hx, x)-->@<---rh--->+
                if hx <= y + eps and yend - eps <= hxend then
                    yline.value.rectangle = ri
                    yline.value.offset    = y
                    yline.value.height    = xend
                    if not yafter then
                        yline.value.length = hxend - y
                    else
                        yline.value.length = Ly
                    end
                -- In case the starting point is out of the bottom of the rectangle
                --      +<------rw------>+                     yline
                --      ^                |                       |
                --     rh           || <-+-- yline         +-----+----+
                --      v           ||   |                 ^     v    |
                --      @<=(x, hx)--++---+             ====+=======   |
                --                  ||                     rw         |
                --                                         |          |
                --                                         v          |
                --                            ---(hx, x)-->@<---rh--->+
                elseif y - eps < hx and yend - eps <= hxend then
                    if not isclose(hx, y) then
                        n:insert(Baseline(y, hx - y, hy), yline)
                    end
                    yline.value.offset    = hx
                    yline.value.height    = xend
                    yline.value.rectangle = ri
                    if not yafter then
                        yline.value.length = rh
                    elseif isclose(yend, hx) then
                        yline:remove()
                        yafter.value.offset = hx
                    else
                        yline.value.length = yend - hx
                    end
                -- In case the end point is out of the top of the rectangle
                --                  ||
                --      +<------rw--++-->+                     yline
                --      ^           ||   |                       |
                --     rh           || <-+-- yline         +-----+----+
                --      v                |                 ^     v    |
                --      @<=(x, hx)-------+                 |    ======+====
                --                                         rw         |
                --                                         |          |
                --                                         v          |
                --                            ---(hx, x)-->@<---rh--->+
                elseif hx <= y + eps and hxend < yend + eps then
                    if not isclose(hxend, y) then
                        n:insert(Baseline(y, hxend - y, xend, ri), yline)
                    end

                    if isclose(yend, hxend) then
                        yline:remove()
                        if yafter then
                            yafter.value.offset = hxend
                        end
                    else
                        yline.value.offset = hxend
                        yline.value.length = yend - hxend
                        yline.value.height = hy
                    end
                end

                -- Merge the current baseline with the previous one
                -- if their height are the same
                --                  ||               ybefore.after ----+
                --      +<------rw------>||          ybefore -----+    |
                --      ^                ||                       v    v
                --     rh                || <- ybefore.after    /////====+
                --      v                // <- ybefore          ^        |
                --      @<=(x, hx)-------//                /////|        +===
                --                 //                           rw       |
                --                 //                           |        |
                --                                              v        |
                --                                 ---(hx, x)-->@<--rh-->+
                if ybefore and isclose(ybefore.value.height, ybefore.after.value.height) then
                    ybefore.after.value.offset = ybefore.value.offset
                    ybefore.after.value.length = ybefore.value.length + ybefore.after.value.length
                    ybefore.after.value.height = ybefore.value.height
                    ybefore.after.value.rectangle = ybefore.value.rectangle
                    ybefore:remove()
                end
            end
        end

        -- Extend the prependicular baseline
        -- if the last edge ends within the following area:
        --
        --     +<------rw------>+        /////////////+----------+
        --     ^                |        /////////////^          |
        --    rh                |        /////////////|          |
        --     v                |        /////////////rw         |
        --     @<=(x, hx)-------+        /////////////|          |
        -- //////////////////////////    /////////////v          |
        -- //////////////////////////    /////////////@<---rh--->+
        -- //////////////////////////                 ^
        -- //////////////////////////                 |
        -- //////////////////////////    ---(hx, x)---+
        local lastoffset = n.last.value.offset
        local lastlength = n.last.value.length
        local lastheight = n.last.value.height
        local lastend = lastoffset + lastlength
        local eps = TOLERANCE * max(xmax, lastoffset, lastlength, lastheight, lastend)
        if lastend - eps <= hx then
            if isclose(lastheight, xend) then
                n.last.value.length = hxend - lastoffset
                n.last.value.rectangle = ri
            else
                n.last.value.length = hx - n.last.value.offset
                n:append(Baseline(hx, rh, xend, ri))
            end
        -- Extension is also applied in this case,
        -- which is excluded in the former loop
        --      +<------rw------>+//////
        --      ^                |//////
        --     rh                |//////
        --      v                |//////
        --      @<=(x, hx)-------+//////
        elseif isclose(lastheight, xend) then
            n.last.value.length = hxend - n.last.value.offset
            n.last.value.rectangle = ri
        elseif lastheight > xend then
            local diff = hxend - lastend
            if diff > 0 then
                n:append(Baseline(lastend, diff, xend, ri))
            end
        end

        -- Apply changes for parallel baseline
        --          x        xend
        --          v          v
        -- hxend -> +----------+
        --          |          |
        --          |          |
        --    hx -> +----------+----+
        --          <----rw---->
        --          <------Lx------->
        if isclose(Lx, rw) then
            xline.value.offset = x
            xline.value.length = rw
            xline.value.height = hxend
            xline.value.rectangle = ri
            if xafter then
                xafter.value.offset = xend
            end
        else
            xline.parent:insert(Baseline(x, rw, hxend, ri), xline)
            xline.value.offset = xend
            xline.value.length = Lx - rw
            xline.value.height = hx
        end

        -- Merge parallel baselines
        -- if adjacent ones have the same height as currently placing rectangle.
        --            x         xend
        --            v           v
        -- ==xbefore==+-----------+==xafter== <- hxend
        --            |           |
        --            | rectangle |
        --            |           |
        --            +-----------+---------+ <- hx
        if xbefore and isclose(xbefore.value.height, xbefore.after.value.height) then
            xbefore.value.length = xbefore.value.length + rw
            xbefore.value.rectangle = nil
            xbefore.after:remove()
        end
        if xafter and isclose(xafter.value.height, xafter.before.value.height) then
            xafter.value.offset = xafter.before.value.offset
            xafter.value.length = xafter.value.length + xafter.before.value.length
            xafter.value.height = xafter.before.value.height
            xafter.value.rectangle = nil
            xafter.before:remove()
        end
    end

    ---Find the best-fit baseline to place given rectangle index ri.
    ---@param ri integer
    ---@return ss.LinkedListCell?
    ---@return boolean
    function t:findbaseline(ri)
        local prefer_y = false -- Which axis do we prefer if both are considered as candidate?
        local rect = self.rects[ri]
        while true do
            local x, is_y, alt = self:getlowest(prefer_y)
            local Lx = x.value.length
            if Lx >= max(rect.width, rect.height) then
                return x, is_y
            elseif alt and not prefer_y then
                prefer_y = true
            else
                prefer_y = false
                if not self:fillline(x) then
                    return nil, false
                end
            end
        end
    end

    ---Optimization around edges after packing (actual part).
    ---is_y is set to true if this attempt forcuses y-baseline.
    ---@param is_y boolean
    ---@return boolean
    function t:replace(is_y)
        local xbackup = self.xbase
        local ybackup = self.ybase
        self.xbase = ss.LinkedList(self.xbase)
        self.ybase = ss.LinkedList(self.ybase)

        local line ---@type ss.LinkedListCell
        local lines = is_y and self.ybase or self.xbase
        for _, v in lines() do
            if not line then line = v end
            if line.value.height < v.value.height then line = v end
        end

        local i = line and line.value and line.value.rectangle
        if not i or line.value.height >= self.maxsize or self.optimized[i] then return false end
        self.optimized[i] = true

        local h = line.value.height
        local r = self.rects[i]
        local rwidth = is_y and r.height or r.width
        local rheight = is_y and r.width or r.height
        r:rotate()
        line.value.height = line.value.height - rheight
        line.value.rectangle = nil
        local newline, new_y = self:findbaseline(i)
        if newline and newline.value.height + rwidth < h then
            local offset = newline.value.offset
            local height = newline.value.height
            if new_y ~= is_y then r:rotate() end
            if new_y then offset, height = height --[[@as number]], offset --[[@as number]] end
            r:place(offset, height)
            self:placebox(i, newline, new_y)
            return true
        else
            r:rotate()
            self.xbase = xbackup
            self.ybase = ybackup
            return false
        end
    end

    ---Optimization around edges after packing.  
    ---Remove rectangles touching the baselines
    ---and place them again with no-rotation constraint.  
    ---If the attempt actually makes better result, it will be approved.
    ---@return boolean
    function t:optimize()
        local xreplaced = self:replace(false)
        local yreplaced = xreplaced or self:replace(true)
        return not yreplaced
    end

    ---Entry point of rectangle packing.
    ---@return boolean
    function t:pack()
        if self.queue.root then
            local lowest, best, istall, is_y = self:findbestlocation()
            assert(best >= 0, "Can't fit")
            local r = self.rects[best]
            self.queue:remove(-r.width, best)
            self.queueRotated:remove(-r.height, best)
            if istall then r:rotate() end
            local offset = lowest.value.offset
            local height = lowest.value.height
            if is_y then
                ---@type number, number
                offset, height = height, offset
            end
            r:place(offset, height)
            self.results[#self.results + 1] = best
            self:placebox(best, lowest, is_y)
            return false
        else
            return self:optimize()
        end
    end

    function t:packall()
        while true do
            if self:pack() then return self end
        end
    end

    t.__type = "SplashSWEPsRectanglePacker"
    return setmetatable(t, { __index = __index })
end
