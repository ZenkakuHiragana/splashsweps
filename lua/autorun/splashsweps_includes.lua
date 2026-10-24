
-- SplashSWEPs library inclusions

local RootDirectory = "splashsweps/"
local ClientDirectory = RootDirectory .. "client/"
local ServerDirectory = RootDirectory .. "server/"
local SharedDirectory = RootDirectory .. "shared/"
if SERVER then -- Finds all Lua files used on client, including subdirectories, and AddCSLuaFile() them.
    ---@param directory string
    local function addCSLuaFiles(directory)
        local files, directories = file.Find(directory .. "*", "LUA")
        for _, filename in ipairs(files or {}) do
            if filename:EndsWith ".lua" then
                AddCSLuaFile(directory .. filename)
            end
        end

        for _, dirname in ipairs(directories or {}) do
            addCSLuaFiles(directory .. dirname .. "/")
        end
    end

    addCSLuaFiles(SharedDirectory)
    addCSLuaFiles(ClientDirectory)
    include(ServerDirectory .. "autorun.lua")
else
    include(ClientDirectory .. "autorun.lua")
end
