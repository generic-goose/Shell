local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

-- Variables
local LocalPlayer = Players.LocalPlayer
local reachRadi = 1
local Functions = {}
--> Services <--
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

--> LocalPlayer Varaibles <--
local player = Players.LocalPlayer
local playerCharacter = player.Character
local playerHumanoidRootPart = playerCharacter:FindFirstChild("HumanoidRootPart") or playerCharacter:WaitForChild("HumanoidRootPart")

--> LocalPlayer Tools Varaibles <--
local playerTool = nil
local playerToolHandle = nil

--> Function To Handle When LocalPlayer Respawns <--
player.CharacterAdded:Connect(function(NewCharacter)
    playerCharacter = NewCharacter
    playerHumanoidRootPart = playerCharacter:FindFirstChild("HumanoidRootPart") or playerCharacter:WaitForChild("HumanoidRootPart")
end)

--> Function To Get Closest Player <--
local function GetClosestPlayer()
    local closestPlayer = nil
    local getClosestPlayerDistance = reachRadi*2 -- math.huge == inf

    for _, Player in pairs(Players:GetPlayers()) do
        if Player ~= player and Player and Player.Character and Player.Character:FindFirstChild("HumanoidRootPart") and Player.Character:FindFirstChild("Humanoid") and Player.Character:FindFirstChild("Humanoid").Health ~= 0 then
            local magnitudeDistance = (Player.Character:FindFirstChild("HumanoidRootPart").Position - playerHumanoidRootPart.Position).Magnitude
            if magnitudeDistance < getClosestPlayerDistance then
                closestPlayer = Player
                getClosestPlayerDistance = magnitudeDistance
            end
        end
    end
    return closestPlayer
end

--> Sword Reach Event Function <--
local function swordReach()
    --> closestPlayer Varaibles <--
    local closestPlayer = GetClosestPlayer()
    --> Checks <--
    if closestPlayer ~= player and closestPlayer and closestPlayer.Character and closestPlayer.Character:FindFirstChild("Humanoid") and closestPlayer.Character:FindFirstChild("Humanoid").Health ~= 0 then
        --> closestPlayer Varaibles <--
        local closestPlayerCharacter = closestPlayer.Character
        local closestPlayerHumanoidRootPart = closestPlayerCharacter:FindFirstChild("HumanoidRootPart") or closestPlayerCharacter:WaitForChild("HumanoidRootPart")
         
        for _, CharacterChild in ipairs(playerCharacter:GetChildren()) do
            if CharacterChild and CharacterChild:IsA("Tool") then
                for _, ToolHandle in ipairs(CharacterChild:GetChildren()) do
                    if ToolHandle and ToolHandle:IsA("BasePart") then
                        if ToolHandle:FindFirstChild("TouchInterest") then
                            playerTool = CharacterChild
                            playerToolHandle = ToolHandle
                        elseif not ToolHandle:FindFirstChild("TouchInterest") then
                            for _, HandleChild in ipairs(ToolHandle:GetChildren()) do
                                if HandleChild and HandleChild:IsA("BasePart") then
                                    if HandleChild:FindFirstChild("TouchInterest") then
                                        playerTool = CharacterChild
                                        playerToolHandle = HandleChild
                                    end
                                end
                            end
                        end
                    end
                end
                break
            end
        end

        --> Manipulates Handle Position [ Sword Reach ] <--
        if playerTool and playerToolHandle then
            playerTool.Equipped:Connect(function()
                if playerTool and playerToolHandle then
                    --> Manipulates LocalPlayer HumanoidRootPart CFrame To Look At Closest Player HumanoidRootPart <--              
                    playerHumanoidRootPart.CFrame = CFrame.lookAt(playerHumanoidRootPart.Position, Vector3.new(closestPlayerHumanoidRootPart.Position.X, playerHumanoidRootPart.Position.Y, closestPlayerHumanoidRootPart.Position.Z))
                    playerToolHandle.Transparency = .5 
                    playerToolHandle.Size = Vector3.new(reachRadi, reachRadi, reachRadi)
                    playerToolHandle.Position = closestPlayerHumanoidRootPart.Position
                    playerTool:Activate()                
                    --[[firetouchinterest(playerToolHandle, closestPlayerHumanoidRootPart, 1)
                    firetouchinterest(playerToolHandle, closestPlayerHumanoidRootPart, 0)]]
                end
            end)
            
            playerTool.Unequipped:Connect(function()
                playerTool = nil
                playerToolHandle = nil
            end)
        end
    end
end

local reach = false
Functions["reach"] = {
    Name = "reach",
    Arguments = {"Number"},
    Category = "Combat",
    Function = function(num)
        reach = not reach
        logFunc(reach and "Now enabling reach." or "Now disabling reach.")
        local RunService = game:GetService("RunService")
        local connection
        reachRadi = num
        connection = RunService.RenderStepped:Connect(function()
            if reach and _G.ShellRunning then
                swordReach()
            else
                connection:Disconnect()
            end
        end)
    end
}

return Functions