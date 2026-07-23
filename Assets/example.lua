-- ============================================================================
-- 1. SERVICES & DEPENDENCIES
-- Localize Roblox services at the top for performance and clarity.
-- ============================================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Functions = {}

-- ============================================================================
-- 2. CENTRALIZED LOGGING SYSTEM
-- All commands should log output through logFunc to maintain compatibility
-- with _G.ShellLog or standard Roblox output.
-- ============================================================================
local function devlog(msg)
    if _G.ShellLog then
    _G.ShellLog("[Dev]: "..msg, "developer")
    end
end
local function logFunc(msg, logType)
    logType = logType or "default" -- Types: "default", "warn", "error"
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

-- ============================================================================
-- 3. UTILITY HELPER FUNCTIONS
-- Keep code DRY (Don't Repeat Yourself) by creating helpers for common actions.
-- ============================================================================

-- Safely retrieves the Humanoid and HumanoidRootPart of the local player
local function getLocalCharacterParts()
    local char = LocalPlayer and LocalPlayer.Character
    if not char then return nil, nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")
    return hum, hrp
end

-- Helper to find a player by full or partial name (supports display names)
local function findPlayerByName(targetName)
    if not targetName or targetName == "" then return nil end
    targetName = targetName:lower()
    
    for _, p in pairs(Players:GetPlayers()) do
        if p.Name:lower():sub(1, #targetName) == targetName or 
           p.DisplayName:lower():sub(1, #targetName) == targetName then
            return p
        end
    end
    return nil
end

-- ============================================================================
-- 4. COMMAND DEFINITIONS
-- Schema Requirements:
--  - Name      : string (Unique command identifier)
--  - Arguments : table  (List of expected argument labels)
--  - Category  : string (e.g., "Utility", "Movement", "Visuals", "Teleportation")
--  - Function  : function(...) (The actual code executed by the handler)
-- ============================================================================

--------------------------------------------------------------------------------
-- Category: Utility (Example: File/External Execution)
--------------------------------------------------------------------------------
Functions["example_external"] = {
    Name = "example_external",
    Arguments = {},
    Function = function()
        logFunc("Attempting to load external script...", "default")
        
        -- Safe execution pattern using pcall
        local success, err = pcall(function()
            -- Example unsafe call (HTTP request or File read)
            loadstring(game:HttpGet("https://example.com/script.lua"))()
        end)
        
        if not success then
            logFunc("Execution failed: " .. tostring(err), "error")
        end
    end
}

--------------------------------------------------------------------------------
-- Category: Teleportation (Example: Argument Parsing & Target Search)
--------------------------------------------------------------------------------
Functions["example_teleport"] = {
    Name = "example_teleport",
    Arguments = {"Player"},
    Function = function(targetName)
        if not targetName or targetName == "" then
            return logFunc("Target name missing! Usage: example_teleport <player>", "warn")
        end

        local targetPlayer = findPlayerByName(targetName)
        if not targetPlayer then
            return logFunc("Player '" .. tostring(targetName) .. "' not found.", "error")
        end

        local _, targetHrp = targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart")
        local _, localHrp = getLocalCharacterParts()

        if localHrp and targetHrp then
            localHrp.CFrame = targetHrp.CFrame
            logFunc("Teleported to " .. targetPlayer.Name .. ".", "default")
        else
            logFunc("Character root part missing.", "error")
        end
    end
}

-- Creating Aliases (Reuse existing function pointer)
Functions["ex_tp"] = {
    Name = "ex_tp",
    Arguments = {"Player"},
    Function = Functions["example_teleport"].Function
}

--------------------------------------------------------------------------------
-- Category: Movement (Example: Toggle / Loop Connections)
--------------------------------------------------------------------------------
local loopEnabled = false
local loopConnection = nil

Functions["example_loop"] = {
    Name = "example_loop",
    Arguments = {},
    Function = function()
        loopEnabled = not loopEnabled
        
        if loopEnabled then
            logFunc("Loop enabled.", "default")
            
            -- Clean up active connections before binding a new one
            if loopConnection then loopConnection:Disconnect() end
            
            loopConnection = RunService.Stepped:Connect(function()
                -- Code to execute on every physics step
            end)
        else
            logFunc("Loop disabled.", "default")
            if loopConnection then
                loopConnection:Disconnect()
                loopConnection = nil
            end
        end
    end
}

-- ============================================================================
-- 5. MODULE RETURN
-- Returns the table to be consumed by your central command runner or UI handler.
-- ============================================================================
return Functions