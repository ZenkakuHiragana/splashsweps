
-- Tells whether this is the first map loaded in this process of the game.

---@class ss
local ss = SplashSWEPs

---@class ss.SessionModule
local Session = ss.module "splashsweps/client/session"

---@class ss.SessionModule.State
---@field IsFirstRun boolean? Cached across hot reloads; nil until material enumeration.
local state = ss.state("splashsweps/client/session", {}) ---@type ss.SessionModule.State

-- The path to the file where we store the calculated application start time.
local START_TIME_FILE_PATH = "splashsweps/session-start-time.txt"
-- A 2-second tolerance to account for minor drift in os.time() and os.clock().
local START_TIME_TOLERANCE = 2

-- This function uses the formula `os.time() - os.clock()` to calculate a stable
-- application start time. This value acts as a perfect session identifier, as it
-- remains constant throughout the lifetime of the gmod.exe process. By comparing
-- the currently calculated start time with a stored value from a previous run,
-- we can determine with virtually 100% accuracy if a new gmod.exe session has begun.
-- This method is robust against all known edge cases, including crashes followed
-- by long waits in the main menu.
local function checkSessionState()
    -- Calculate the approximate, absolute start time of the gmod.exe application.
    local currentStartTime = os.time() - os.clock()

    -- Read the start time recorded from a previous map load.
    local storedStartTime = tonumber(file.Read(START_TIME_FILE_PATH, "DATA"))

    if not storedStartTime or math.abs(currentStartTime - storedStartTime) > START_TIME_TOLERANCE then
        -- If there was no stored start time, or if the newly calculated start time
        -- differs significantly from the stored one, it proves that this is a new
        -- gmod.exe session. This is the definitive "First Run".
        state.IsFirstRun = true

        -- Write the new, authoritative start time to the file for this session.
        file.Write(START_TIME_FILE_PATH, tostring(currentStartTime))
    else
        -- The calculated start time is consistent with the stored one. We are in
        -- the same gmod.exe session. This is not the first run.
        state.IsFirstRun = false
    end
end

---Returns whether this is the first map with material enumeration in this process.
---Check lazily so a missing map cache cannot mark old material names as current.
---@return boolean
function Session.IsFirstRun()
    if state.IsFirstRun == nil then
        checkSessionState()
    end
    return state.IsFirstRun
end

return Session
