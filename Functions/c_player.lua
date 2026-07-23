local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

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
-- Helpers
--------------------------------------------------------------------------------
local function getLocalCharacterParts()
    local char = LocalPlayer and LocalPlayer.Character
    if not char then return nil, nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")
    return hum, hrp
end

local function findPlayerByName(targetName)
    if not targetName or targetName == "" then return nil end
    targetName = targetName:lower()
    
    for _, p in pairs(Players:GetPlayers()) do
        if p.Name:lower():sub(1, #targetName) == targetName or p.DisplayName:lower():sub(1, #targetName) == targetName then
            return p
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Cleanup Handler for ESP & View
--------------------------------------------------------------------------------
local espPlayers = {}

local function removeESP(char)
    if not char then devlog("c_player.lua -- expected affected character, got nil or error.") return end
    local existing = char:FindFirstChild("ShellESP")
    if existing then
        existing:Destroy()
    end
end

local function cleanupVisuals()
    -- Clear all Highlights
    for _, plr in pairs(Players:GetPlayers()) do
        if plr.Character then
            removeESP(plr.Character)
        end
    end
    table.clear(espPlayers)

    -- Reset Camera
    local camera = Workspace.CurrentCamera
    if camera then
        local hum, _ = getLocalCharacterParts()
        if hum then
            camera.CameraSubject = hum
        end
    end
end

-- Monitor ShellRunning flag to handle unexpected script stops
task.spawn(function()
    while true do
        if _G.ShellRunning == false then
            cleanupVisuals()
            break
        end
        task.wait(0.2)
    end
end)

--------------------------------------------------------------------------------
-- Teleport Commands
--------------------------------------------------------------------------------
Functions["teleport"] = {
    Name = "teleport",
    Arguments = {"Player"},
    Category = "Movement",
    Function = function(targetName)
        if not LocalPlayer then
            logFunc("Local player not found.", "error")
            return
        end

        if not targetName or targetName == "" then
            logFunc("Please specify a target player name.", "warn")
            return
        end

        local targetPlayer = findPlayerByName(targetName)

        if targetPlayer and targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart") then
            local _, hrp = getLocalCharacterParts()
            if hrp then
                logFunc("Teleporting to " .. targetPlayer.Name .. "...", "default")
                hrp.CFrame = targetPlayer.Character.HumanoidRootPart.CFrame
            else
                logFunc("Your character root part was not found.", "error")
            end
        else
            logFunc("Target player or character not found.", "error")
        end
    end
}

Functions["to"] = {
    Name = "to",
    Arguments = {"Player"},
    Category = "Movement",
    Function = Functions["teleport"].Function
}

Functions["tp"] = {
    Name = "tp",
    Arguments = {"Player"},
    Category = "Movement",
    Function = Functions["teleport"].Function
}

--------------------------------------------------------------------------------
-- Visual Commands
--------------------------------------------------------------------------------

-- Highlight / ESP
Functions["esp"] = {
    Name = "esp",
    Arguments = {"Player"},
    Category = "Visual",
    Function = function(targetArg)
        local function applyESP(char)
            if not char then devlog("c_player.lua -- expected affected character, got nil or error.") return end
            removeESP(char)

            local highlight = Instance.new("Highlight")
            highlight.Name = "ShellESP"
            highlight.Adornee = char
            highlight.FillColor = Players:WaitForChild(char.Name).TeamColor.Color or Color3.fromRGB(255, 255, 255)
            highlight.OutlineColor = Players:WaitForChild(char.Name).TeamColor.Color or Color3.fromRGB(100, 100, 100)
            highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            highlight.Parent = char
        end

        local function toggleESP(targetPlayer)
            if not targetPlayer then devlog("c_player.lua -- expected targetPlayer, got nil or error.") return end

            if espPlayers[targetPlayer] then
                -- Disable ESP for this player
                espPlayers[targetPlayer]:Disconnect()
                espPlayers[targetPlayer] = nil
                if targetPlayer.Character then
                    removeESP(targetPlayer.Character)
                end
            else
                -- Enable ESP & hook into re-spawns
                if targetPlayer.Character then
                    applyESP(targetPlayer.Character)
                end
                
                espPlayers[targetPlayer] = targetPlayer.CharacterAdded:Connect(function(newChar)
                    if _G.ShellRunning ~= false and espPlayers[targetPlayer] then
                        applyESP(newChar)
                    end
                end)
            end
        end

        if not targetArg or targetArg == "" or targetArg:lower() == "all" then
            for _, plr in pairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer then
                    toggleESP(plr)
                end
            end
            logFunc("Toggled ESP for all players.", "default")
        else
            local targetPlayer = findPlayerByName(targetArg)
            if targetPlayer then
                toggleESP(targetPlayer)
                logFunc("Toggled ESP for " .. targetPlayer.Name .. ".", "default")
            else
                logFunc("Player not found or character does not exist.", "warn")
            end
        end
    end
}

-- Spectate / View
Functions["view"] = {
    Name = "view",
    Arguments = {"Player"},
    Category = "Visual",
    Function = function(targetName)
        local camera = Workspace.CurrentCamera
        if not camera then devlog("c_player.lua -- expected camera, got nil or error.") return end

        if not targetName or targetName == "" or targetName:lower() == "unview" then
            local hum, _ = getLocalCharacterParts()
            if hum then
                camera.CameraSubject = hum
                logFunc("Camera reset to local character.", "default")
            end
            return
        end

        local targetPlayer = findPlayerByName(targetName)
        if targetPlayer and targetPlayer.Character then
            local hum = targetPlayer.Character:FindFirstChildOfClass("Humanoid")
            if hum then
                camera.CameraSubject = hum
                logFunc("Now spectating " .. targetPlayer.Name .. ".", "default")
            else
                logFunc("Target player humanoid not found.", "warn")
            end
        else
            logFunc("Player not found to view.", "error")
        end
    end
}

return Functions