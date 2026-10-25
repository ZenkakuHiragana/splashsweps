
-- InkDetailUpdate material proxy, which lets ink types draw their detail cells by updater modules.

---@class ss
local ss = SplashSWEPs
local Util = ss.import "splashsweps/shared/util"

---@class ss.InkDetailProxyModule
local InkDetailProxy = ss.module "splashsweps/client/ink/inkdetailproxy"

---Draws the shared periodic-border mesh; the caller has set the cell transform and RT.
---@alias ss.InkDetailDrawCell fun(material: IMaterial)

---Draws a generated cell from the state, using drawCell for the actual drawing.
---@alias ss.InkDetailDraw fun(state: table, drawCell: ss.InkDetailDrawCell)

---A module drawing the detail cells of ink types whose material has the InkDetailUpdate proxy.
---The proxy block names the module by "updater" key, as ss.import does, e.g.
---```
---"InkDetailUpdate"
---{
---    "updater" "myaddon/client/ripple"
---}
---```
---```lua
---local Ripple = SplashSWEPs.module "myaddon/client/ripple"
---function Ripple.Update(state, material, values) ... end
---return Ripple
---```
---Annotate the module table as a class extending this one.
---Update records every drawing input in the state, which is kept per material,
---and returns the function to draw the cell, or nil not to request drawing.
---The cell is drawn only if the state or Update differs from the ones it was last drawn with,
---so hot reloading the module redraws the cell.
---@class ss.IInkDetailUpdater
---@field Update fun(state: table, material: IMaterial, values: table<string, any>): ss.InkDetailDraw?

---@class ss.InkDetailProxyInstance
---@field Values table<string, any> Key values of the proxy block
---@field State  table              Inputs of drawing, kept per material
---@field Draw   ss.InkDetailDraw?  Function returned by the updater
---@field Update fun(state: table, material: IMaterial, values: table<string, any>): ss.InkDetailDraw? Update of the updater module that returned Draw

---@class ss.InkDetailProxyModule.State
---@field Updaters    table<string, ss.IInkDetailUpdater>      Material name --> updater module drawing its cell
---@field Requests    table<string, ss.InkDetailProxyInstance> Material name --> pending draw request; bind queues, atlas update consumes
---@field LastStates  table<string, table>                     Material name --> input snapshot from its last successful draw
---@field LastUpdates table<string, function>                  Material name --> Update of the updater module that last drew its cell
local state = ss.state("splashsweps/client/ink/inkdetailproxy", {
    Updaters = {},
    Requests = {},
    LastStates = {},
    LastUpdates = {},
}) ---@type ss.InkDetailProxyModule.State

---Compares all drawing inputs with the snapshot saved after the last successful cell draw.
---Vector, Angle, and VMatrix compare their components with ==,
---while material and texture handles are compared by their names
---as getting the same resource again gives another handle.
---@param current any
---@param last any
---@return boolean
local function AreInputsEqual(current, last)
    if current == last then return true end
    local kind = TypeID(current)
    if kind ~= TypeID(last) then return false end
    if kind == TYPE_MATERIAL or kind == TYPE_TEXTURE then
        return current:GetName() == last:GetName()
    end
    if kind ~= TYPE_TABLE then return false end
    for key, value in pairs(current) do
        if not AreInputsEqual(value, last[key]) then return false end
    end
    for key in pairs(last) do
        if current[key] == nil then return false end
    end
    return true
end

---Starts taking requests of the materials whose cells the detail atlas has laid out, discarding the old ones.
---@param updaters table<string, string> Material name --> module name of its updater
function InkDetailProxy.Reset(updaters)
    state.Updaters = {}
    for name, moduleName in pairs(updaters) do
        state.Updaters[name] = ss.import(moduleName)
    end
    state.Requests = {}
    state.LastStates = {}
    state.LastUpdates = {}
end

---Consumes the bind-time request queue, returning only requests with changed drawing inputs.
---@return table<string, ss.InkDetailProxyInstance> drawRequests Changed drawing requests by material name
function InkDetailProxy.TakeChanged()
    local drawRequests = {} ---@type table<string, ss.InkDetailProxyInstance>
    for name, proxy in pairs(state.Requests) do
        if proxy.Update ~= state.LastUpdates[name] or not AreInputsEqual(proxy.State, state.LastStates[name]) then
            drawRequests[name] = proxy
        end
        state.Requests[name] = nil
    end
    return drawRequests
end

---Saves the drawing inputs of a request whose cell has been drawn.
---@param name string Material name
---@param proxy ss.InkDetailProxyInstance
function InkDetailProxy.MarkDrawn(name, proxy)
    state.LastStates[name] = Util.deepcopy(proxy.State)
    state.LastUpdates[name] = proxy.Update
end

matproxy.Add {
    name = "InkDetailUpdate",
    ---@param self ss.InkDetailProxyInstance
    init = function(self)
        self.State = {}
    end,
    ---@param self ss.InkDetailProxyInstance
    ---@param material IMaterial
    -- Bind collects inputs and queues work; drawing runs later in the Details RT context.
    bind = function(self, material)
        local name = material:GetName()
        local updater = state.Updaters[name]
        if not updater then return end
        local update = updater.Update
        local draw = update(self.State, material, self.Values)
        if draw then
            self.Draw = draw
            self.Update = update
            state.Requests[name] = self
        end
    end,
}

return InkDetailProxy
