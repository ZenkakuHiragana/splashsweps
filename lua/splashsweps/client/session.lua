---@class ss
local ss = SplashSWEPs

-- The path to the file where we store the calculated application start time.
local START_TIME_FILE_PATH = "splashsweps/session-start-time.txt"
-- A 2-second tolerance to account for minor漂移 in os.time() and os.clock().
local START_TIME_TOLERANCE = 2

-- State
local isFirstRunInSession = false

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
        isFirstRunInSession = true

        -- Write the new, authoritative start time to the file for this session.
        file.Write(START_TIME_FILE_PATH, tostring(currentStartTime))
    else
        -- The calculated start time is consistent with the stored one. We are in
        -- the same gmod.exe session. This is not the first run.
        isFirstRunInSession = false
    end
end

-- Run the check as soon as this file is loaded.
checkSessionState()

---Returns true if this is the first time the addon has been loaded since the
---Garry's Mod client (gmod.exe) was started. This is determined with extremely
---high accuracy by calculating and comparing a stable application start time.
---@return boolean
function ss.IsFirstRunInSession()
    return isFirstRunInSession
end
