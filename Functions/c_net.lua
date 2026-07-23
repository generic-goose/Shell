local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local Functions = {}

--------------------------------------------------------------------------------
-- Unified Logger
--------------------------------------------------------------------------------
local function devlog(msg)
    if _G.ShellLog then
    _G.ShellLog("[Dev]: "..msg, "developer")
    end
end
local function logFunc(msg, logType)
    logType = logType or "default"
    local formattedMsg = "[Func] " .. tostring(msg)
    
    if _G.ShellLog then
        _G.ShellLog(formattedMsg, logType)
    else
        if logType == "error" or logType == "warn" then
            warn(formattedMsg)
        else
            print(formattedMsg)
        end
    end
end

--------------------------------------------------------------------------------
-- Server Utility Commands
--------------------------------------------------------------------------------
Functions["rejoin"] = {
    Name = "rejoin",
    Arguments = {},
    Category = "Network",
    Function = function()
        local LocalPlayer = Players.LocalPlayer
        if not LocalPlayer then
            logFunc("Local player not found.", "error")
            return
        end

        logFunc("Rejoining the game...", "default")

        local placeId = game.PlaceId
        local jobId = game.JobId

        local success, err = pcall(function()
            if #Players:GetPlayers() <= 1 then
                TeleportService:Teleport(placeId, LocalPlayer)
            else
                TeleportService:TeleportToPlaceInstance(placeId, jobId, LocalPlayer)
            end
        end)

        if not success then
            logFunc("Failed to rejoin: " .. tostring(err), "error")
        end
    end
}

logFunc("Join the Shell Discord!\nhttps://discord.gg/jBW96MNauQ")
    
Functions["discord"] = {
    Name = "discord",
    Arguments = {},
    Category = "Shell",
    Function = function()
        logFunc("https://discord.gg/jBW96MNauQ", "default")
    end
}

return Functions
