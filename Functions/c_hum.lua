local Functions = {}

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

local function getLocalHumanoid()
    local Players = game:GetService("Players")
    local player = Players.LocalPlayer
    local character = player and player.Character
    if not character then
        logFunc("Character not found.", "error")
        return nil
    end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        logFunc("Humanoid not found.", "error")
        return nil
    end
    
    return humanoid
end

Functions["speed"] = {
    Name = "speed",
    Arguments = {"Number"},
    Category = "Player",
    Function = function(speed)
        local num = tonumber(speed)
        if not num then
            logFunc("Invalid speed value provided.", "error")
            return
        end

        local humanoid = getLocalHumanoid()
        if humanoid then
            humanoid.WalkSpeed = num
            logFunc("WalkSpeed set to " .. tostring(num), "default")
        end
    end
}

Functions["jump"] = {
    Name = "jump",
    Arguments = {"Number"},
    Category = "Player",
    Function = function(jumpPower)
        local num = tonumber(jumpPower)
        if not num then
            logFunc("Invalid jump value provided.", "error")
            return
        end

        local humanoid = getLocalHumanoid()
        if humanoid then
            humanoid.UseJumpPower = true
            humanoid.JumpPower = num
            logFunc("JumpPower set to " .. tostring(num), "default")
        end
    end
}

Functions["freeze"] = {
    Name = "freeze",
    Arguments = {},
    Category = "Player",
    Function = function()
        local Players = game:GetService("Players")
        local player = Players.LocalPlayer
        local character = player and player.Character
        local rootPart = character and character:FindFirstChild("HumanoidRootPart")

        if rootPart then
            rootPart.Anchored = not rootPart.Anchored
            local state = rootPart.Anchored and "Frozen" or "Unfrozen"
            logFunc("Player " .. state, "default")
        else
            logFunc("HumanoidRootPart not found.", "error")
        end
    end
}

Functions["hipheight"] = {
    Name = "hipheight",
    Arguments = {"Number"},
    Category = "Player",
    Function = function(hipHeight)
        local num = tonumber(hipHeight)
        if not num then
            logFunc("Invalid hip height value provided.", "error")
            return
        end

        local humanoid = getLocalHumanoid()
        if humanoid then
            humanoid.HipHeight = num
            logFunc("HipHeight set to " .. tostring(num), "default")
        end
    end
}

Functions["respawn"] = {
    Name = "respawn",
    Arguments = {},
    Category = "Player",
    Function = function()
        local humanoid = getLocalHumanoid()
        if humanoid then
            humanoid.Health = 0
            logFunc("Respawning character...", "default")
        end
    end
}

Functions["reset"] = {
    Name = "reset",
    Arguments = {},
    Category = "Player",
    Function = Functions["respawn"].Function
}

return Functions