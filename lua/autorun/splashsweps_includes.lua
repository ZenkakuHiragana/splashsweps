
-- SplashSWEPs library inclusions

local RootDirectory = "splashsweps/"
local ClientDirectory = RootDirectory .. "client/"
local ServerDirectory = RootDirectory .. "server/"
local SharedDirectory = RootDirectory .. "shared/"
if SERVER then -- Finds all Lua files used on client and AddCSLuaFile() them.
    local shared = file.Find(SharedDirectory .. "*.lua", "LUA") or {}
    local client = file.Find(ClientDirectory .. "*.lua", "LUA") or {}
    for i, filename in ipairs(shared) do
        shared[i] = SharedDirectory .. filename
    end

    for i, filename in ipairs(client) do
        client[i] = ClientDirectory .. filename
    end

    local merged = table.Add(shared, client)
    for _, filepath in ipairs(merged) do
        AddCSLuaFile(filepath)
    end

    include(ServerDirectory .. "autorun.lua")
else
    include(ClientDirectory .. "autorun.lua")
end
