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

local autoRejoin = false
Functions["autorejoin"] = {
    Name = "autorejoin",
    Arguments = {"Rejoin on 'exploit' or 'hack' detection. (T/F)"},
    Category = "Shell",
    Function = function(chatDetect)
        autoRejoin = not autoRejoin
        logFunc("Auto rejoin toggled.", "default")
    
        local GuiService = game:GetService("GuiService")
        local Players = game:GetService("Players")
        local TeleportService = game:GetService("TeleportService")
        
        local player = LocalPlayer or Players.LocalPlayer
    
        local function rejoin()
            if player then
                TeleportService:Teleport(game.PlaceId, player)
            end
        end
        local function onErrorMessageChanged(errorMessage)
            if autoRejoin then
                if errorMessage and errorMessage ~= "" then
                    logFunc("Error detected: " .. errorMessage,"default")
                    task.wait()
                    rejoin()
                end
            end
        end
        GuiService.ErrorMessageChanged:Connect(onErrorMessageChanged)
        if chatDetect then
            local function onChatted(message)
                if string.find(string.lower(message), "hack") or string.find(string.lower(message), "exploit") or string.find(string.lower(message), "cheat") or string.find(string.lower(message), player.Name) then
                    logFunc("Rejoin trigger detected in chat.","default")
                    task.wait()
                    rejoin()
                end
            end
    
            local function hookPlayer(targetPlayer)
                targetPlayer.Chatted:Connect(onChatted)
            end
            for _, p in ipairs(Players:GetPlayers()) do
                hookPlayer(p)
            end
            Players.PlayerAdded:Connect(hookPlayer)
        end
    end
}

return Functions
