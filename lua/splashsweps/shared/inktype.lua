
-- Types of ink, each defined by an ink material: a vmt file under materials/splashsweps/inks.
-- The server defines them from its ink materials and sends the list to each client,
-- which defines the same ink types in the same order.

---@class ss
local ss = SplashSWEPs
local Util = ss.import "splashsweps/shared/util"

---@class ss.InkTypeModule
local InkType = ss.module "splashsweps/shared/inktype"

---A module defining how painted ink behaves with a set of functions.
---The `$features` parameter of an ink material names these modules as ss.import does, separated by spaces.
---The modules are imported in both realms, except on a client that does not have the ink material.
---Move runs on the server and the client predicting the player, PhysicsCollide on the server,
---and OnEnter, OnStay, and OnExit on both realms.
---They get the contacts with all the ink types naming the module at once.
---@class ss.IInkFeature
---Called when this type of ink is about to be painted.
---Return true to suppress painting.
---@field OnPaint? fun(pos: Vector, normal: Vector, transform: VMatrix): boolean?
---Called for every command of each player, even if the player touches none of this ink.
---Return true to suppress the engine movement.
---@field Move? fun(ply: Player, mv: CMoveData, contacts: ss.InkContact[], vars: table<string, any>?): boolean?
---Variables Move keeps across commands for each player, given as `vars`, by name and type of Entity:NetworkVar.
---@field PredictedVars? table<string, "String"|"Bool"|"Float"|"Int"|"Vector"|"Angle"|"Entity">
---Called in the PhysicsCollide callback of a physics object hitting this ink, with the contacts at the point,
---where the same limits as in the callback apply.
---@field PhysicsCollide? fun(ent: Entity, contacts: ss.InkContact[], data: Structure.CollisionData)
---Called when an entity starts touching this ink.
---@field OnEnter? fun(ent: Entity, contacts: ss.InkContact[])
---Called at every check while an entity is touching this ink.
---@field OnStay? fun(ent: Entity, contacts: ss.InkContact[], dt: number)
---Called once for each OnEnter while the entity is still valid, when it stops touching this ink.
---@field OnExit? fun(ent: Entity)

---A type of ink.
---@class ss.InkType
---@field Index      integer          Internal index number used by networking.
---@field Identifier string           The name of the ink material defining this type of ink.
---@field Material   IMaterial        The ink material, or the error ink material on a client that does not have it.
---@field Features   ss.IInkFeature[] Modules named by `$features` of the ink material.

---@class ss.InkTypeModule.State
---@field Types             ss.InkType[]           Defined ink types indexed by their internal index.
---@field Features          ss.IInkFeature[]       Modules named by the ink types, each once.
---@field IdentifierToIndex table<string, integer> Conversion table from identifier string to internal index.
---@field NumBits           integer                Required bits to transfer an ink type index as an unsigned integer.
---@field Received          string[]?              Client only; identifiers the server sent in the order of the indices.
local state = ss.state("splashsweps/shared/inktype", {
    Types = {},
    Features = {},
    IdentifierToIndex = {},
})

---Paintable grids and the ink map store the index in 8 bits, where 0 means no ink.
local MAX_INK_TYPES = 255

---Drawn instead of an ink type the server has and the client does not.
local ERROR_INK_MATERIAL = "splashsweps/inkerror"

---Defined ink types indexed by their internal index.
InkType.Types = state.Types

---Modules named by the ink types, each once, in the order of the ink types and then of their `$features`.
---Both realms have the same order, as they define the same ink types in the same order.
InkType.Features = state.Features

---Converts ink type identifier (string) into internal index.
---@param identifier string
---@return integer?
function InkType.FindIndex(identifier)
    return state.IdentifierToIndex[identifier]
end

---Defines an ink type at the index.
---@param index      integer
---@param identifier string
---@param mat        IMaterial
---@param features   ss.IInkFeature[]
local function Define(index, identifier, mat, features)
    state.Types[index] = {
        Index = index,
        Identifier = identifier,
        Material = mat,
        Features = features,
    }
    state.IdentifierToIndex[identifier] = index
end

---Imports the modules named by `$features` of the ink material.
---@param mat IMaterial
---@return ss.IInkFeature[]
local function ImportFeatures(mat)
    local features = {} ---@type ss.IInkFeature[]
    for feature in (mat:GetString "$features" or ""):gmatch "%S+" do
        features[#features + 1] = ss.import(feature)
    end
    return features
end

---Defines the ink types.
---The server reads all ink materials, and the client follows the list the server sent by InkType.Write.
function InkType.Load()
    local inktypeCount = 0
    if SERVER then
        for f in Util.IterateFilesRecursive("materials/splashsweps/inks", "GAME", "*.vmt") do
            local mat = Material(f:sub(11))
            if mat and not mat:IsError() then
                inktypeCount = inktypeCount + 1
                Define(inktypeCount, mat:GetName(), mat, ImportFeatures(mat))
            end
        end
        Util.assert(inktypeCount <= MAX_INK_TYPES, string.format(
            "There are %d ink materials, more than %d ink types", inktypeCount, MAX_INK_TYPES))
    else
        local identifiers = Util.assert(state.Received, "The server did not send the ink types before InitPostEntity")
        local missing = {} ---@type string[]
        for i, identifier in ipairs(identifiers) do
            local mat = Material(identifier)
            if mat:IsError() then
                missing[#missing + 1] = identifier
                Define(i, identifier, Material(ERROR_INK_MATERIAL), {})
            else
                Define(i, identifier, mat, ImportFeatures(mat))
            end
        end
        inktypeCount = #identifiers
        if #missing > 0 then
            print("SplashSWEPs: These ink materials of the server are missing and drawn as errors:\n    "
                .. table.concat(missing, "\n    "))
        end
    end

    state.NumBits = math.max(select(2, math.frexp(inktypeCount - 1)), 1)

    table.Empty(state.Features)
    for _, inktype in ipairs(state.Types) do
        for _, feature in ipairs(inktype.Features) do
            if not table.HasValue(state.Features, feature) then
                state.Features[#state.Features + 1] = feature
            end
        end
    end
end

---Writes the identifiers of the ink types to the net message, for the client to define the same ink types.
function InkType.Write()
    net.WriteUInt(#state.Types, 8)
    for _, inktype in ipairs(state.Types) do
        net.WriteString(inktype.Identifier)
    end
end

---Reads the identifiers InkType.Write wrote and keeps them for InkType.Load.
function InkType.Read()
    local identifiers = {} ---@type string[]
    for i = 1, net.ReadUInt(8) do
        identifiers[i] = net.ReadString()
    end
    state.Received = identifiers
end

---Returns the required bits to transfer an ink type index as an unsigned integer.
---@return integer
function InkType.GetNumBits()
    return state.NumBits
end

return InkType
