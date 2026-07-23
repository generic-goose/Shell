local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

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
    local char = LocalPlayer.Character
    if not char then return nil, nil end
    local hum = char:WaitForChild("Humanoid")
    local hrp = char:WaitForChild("HumanoidRootPart")
    return hum, hrp
end

--------------------------------------------------------------------------------
-- Teleport Commands
--------------------------------------------------------------------------------
Functions["teleport"] = {
    Name = "teleport",
    Arguments = {"Player"},
    Category = "Teleportation",
    Function = function(targetName)
        if not LocalPlayer then
            logFunc("Local player not found.", "error")
            return
        end

        if not targetName or targetName == "" then
            logFunc("Please specify a target player name.", "warn")
            return
        end

        local targetPlayer = nil
        for _, p in pairs(Players:GetPlayers()) do
            if p.Name:lower():sub(1, #targetName) == targetName:lower() then
                targetPlayer = p
                break
            end
        end

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
    Category = "Teleportation",
    Function = Functions["teleport"].Function
}

Functions["tp"] = {
    Name = "tp",
    Arguments = {"Player"},
    Category = "Teleportation",
    Function = Functions["teleport"].Function
}

Functions["clicktp"] = {
    Name = "clicktp",
    Arguments = {},
    Category = "Teleportation",
    Function = function()
        local _, hrp = getLocalCharacterParts()
        if not hrp then return logFunc("Character not found.", "error") end
        
        local mouse = LocalPlayer:GetMouse()
        if mouse and mouse.Hit then
            hrp.CFrame = mouse.Hit + Vector3.new(0, 3, 0)
            logFunc("Teleported to mouse position.", "default")
        end
    end
}

Functions["tpcoords"] = {
    Name = "tpcoords",
    Arguments = {"X", "Y", "Z"},
    Category = "Teleportation",
    Function = function(args)
        local _, hrp = getLocalCharacterParts()
        if not hrp then return logFunc("Character not found.", "error") end
        
        if type(args) ~= "table" then return logFunc("Invalid arguments provided.", "error") end

        local x = tonumber(args[1])
        local y = tonumber(args[2])
        local z = tonumber(args[3])
        
        if x and y and z then
            hrp.CFrame = CFrame.new(x, y, z)
            logFunc(string.format("Teleported to coordinates: %.1f, %.1f, %.1f", x, y, z), "default")
        else
            logFunc("Invalid coordinates provided. Usage: tpcoords X Y Z", "warn")
        end
    end
}

--------------------------------------------------------------------------------
-- Movement Commands
--------------------------------------------------------------------------------

-- Required Services & Helpers

local flying = false
local flySpeed = 50

-- Store instances & connections cleanly
local flyVelocity = nil
local flyGyro = nil
local flyConnection = nil

-- Fallback helper in case getLocalCharacterParts isn't defined globally
local function getLocalCharacterParts()
    local player = game:GetService("Players").LocalPlayer
    if not player or not player.Character then return nil, nil end
    local hum = player.Character:FindFirstChildOfClass("Humanoid")
    local hrp = player.Character:FindFirstChild("HumanoidRootPart")
    return hum, hrp
end

local function stopFly()
    flying = false
    
    if flyConnection then
        flyConnection:Disconnect()
        flyConnection = nil
    end
    if flyVelocity then
        flyVelocity:Destroy()
        flyVelocity = nil
    end
    if flyGyro then
        flyGyro:Destroy()
        flyGyro = nil
    end

    local hum, hrp = getLocalCharacterParts()
    if hum then 
        hum.PlatformStand = false 
    end
    
    -- Reset momentum on character or vehicle
    local targetPart = (hum and hum.SeatPart and hum.SeatPart.AssemblyRootPart) or hrp
    if targetPart then 
        targetPart.AssemblyLinearVelocity = Vector3.zero 
    end
end

local function startFly()
    local hum, hrp = getLocalCharacterParts()
    if not hrp or not hum then 
        stopFly()
        return 
    end

    -- Determine target: Seat's main assembly root if sitting, otherwise HumanoidRootPart
    local isSeated = hum.SeatPart ~= nil
    local targetPart = isSeated and hum.SeatPart.AssemblyRootPart or hrp

    -- Create Attachment on the target physics assembly
    local attachment = targetPart:FindFirstChild("FlyAttachment") or Instance.new("Attachment")
    attachment.Name = "FlyAttachment"
    attachment.Parent = targetPart

    -- Modern Linear Velocity
    flyVelocity = Instance.new("LinearVelocity")
    flyVelocity.Name = "ShellFlyVelocity"
    flyVelocity.MaxForce = math.huge
    flyVelocity.VectorVelocity = Vector3.zero
    flyVelocity.Attachment0 = attachment
    flyVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
    flyVelocity.Parent = targetPart

    -- Modern Align Orientation
    flyGyro = Instance.new("AlignOrientation")
    flyGyro.Name = "ShellFlyGyro"
    flyGyro.MaxTorque = math.huge
    flyGyro.Responsiveness = 200
    flyGyro.Mode = Enum.OrientationAlignmentMode.OneAttachment
    flyGyro.Attachment0 = attachment
    flyGyro.CFrame = targetPart.CFrame
    flyGyro.Parent = targetPart

    -- Only platform stand if walking; doing this in a seat unseats the character
    if not isSeated then
        hum.PlatformStand = true
    end

    -- RenderStepped Event Loop
    flyConnection = RunService.RenderStepped:Connect(function()
        if not flying or (_G.ShellRunning == false) then
            stopFly()
            return
        end

        local currentHum, currentHrp = getLocalCharacterParts()
        if not currentHrp or not currentHum then 
            stopFly()
            return 
        end

        -- Check if target changes mid-flight (e.g. gets out of seat)
        local currentTarget = currentHum.SeatPart and currentHum.SeatPart.AssemblyRootPart or currentHrp
        if flyVelocity.Parent ~= currentTarget then
            -- Re-parent physics instances if the player enters/exits a seat while flying
            attachment.Parent = currentTarget
            flyVelocity.Parent = currentTarget
            flyGyro.Parent = currentTarget
        end

        local moveDirection = Vector3.zero
        local cameraCFrame = workspace.CurrentCamera.CFrame

        -- Movement Input Checks
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then
            moveDirection = moveDirection + cameraCFrame.LookVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then
            moveDirection = moveDirection - cameraCFrame.LookVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then
            moveDirection = moveDirection - cameraCFrame.RightVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then
            moveDirection = moveDirection + cameraCFrame.RightVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
            moveDirection = moveDirection + Vector3.new(0, 1, 0)
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
            moveDirection = moveDirection - Vector3.new(0, 1, 0)
        end

        -- Calculate Flying Velocity
        if moveDirection.Magnitude > 0 then
            flyVelocity.VectorVelocity = moveDirection.Unit * flySpeed
        else
            flyVelocity.VectorVelocity = Vector3.zero
        end

        flyGyro.CFrame = cameraCFrame
    end)
end


-- Float State & Variables
local floating = false
local floatVelocity = nil

local function stopFloat()
    floating = false
    
    if floatVelocity then
        floatVelocity:Destroy()
        floatVelocity = nil
    end

    local hum, hrp = getLocalCharacterParts()
    if hum then 
        hum.PlatformStand = false 
    end
    if hrp then 
        hrp.AssemblyLinearVelocity = Vector3.zero 
    end
end

local function startFloat()
    local hum, hrp = getLocalCharacterParts()
    if not hrp or not hum then 
        stopFloat()
        return 
    end

    -- Attachment setup for LinearVelocity
    local attachment = hrp:FindFirstChild("FloatAttachment") or Instance.new("Attachment")
    attachment.Name = "FloatAttachment"
    attachment.Parent = hrp

    -- LinearVelocity configured to only freeze vertical (Y) velocity
    floatVelocity = Instance.new("LinearVelocity")
    floatVelocity.Name = "ShellFloatVelocity"
    floatVelocity.ForceLimitMode = Enum.ForceLimitMode.PerAxis
    floatVelocity.MaxAxesForce = Vector3.new(0, math.huge, 0) -- Force applied ONLY on Y axis
    floatVelocity.VectorVelocity = Vector3.zero
    floatVelocity.Attachment0 = attachment
    floatVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
    floatVelocity.Parent = hrp

    -- Keep PlatformStand FALSE so player controls remain enabled
    hum.PlatformStand = false

    -- Safety monitor loop
    task.spawn(function()
        while floating do
            if _G.ShellRunning == false then
                stopFloat()
                break
            end

            local currentHum, currentHrp = getLocalCharacterParts()
            if not currentHrp or not currentHum then 
                stopFloat()
                break 
            end

            task.wait(0.1)
        end
    end)
end

Functions["float"] = {
    Name = "float",
    Arguments = {},
    Category = "Movement",
    Function = function()
        floating = not floating
        if floating then
            if typeof(logFunc) == "function" then 
                logFunc("Float enabled.", "default") 
            end
            startFloat()
        else
            stopFloat()
            if typeof(logFunc) == "function" then 
                logFunc("Float disabled.", "default") 
            end
        end
    end
}

Functions["fly"] = {
    Name = "fly",
    Arguments = {},
    Category = "Movement",
    Function = function()
        flying = not flying
        if flying then
            if typeof(logFunc) == "function" then logFunc("Fly enabled.", "default") end
            startFly()
        else
            stopFly()
            if typeof(logFunc) == "function" then logFunc("Fly disabled.", "default") end
        end
    end
}

Functions["flyspeed"] = {
    Name = "flyspeed",
    Arguments = {"Speed"},
    Category = "Movement",
    Function = function(speedInput)
        local numSpeed = tonumber(speedInput)
        if type(speedInput) == "table" then
            numSpeed = tonumber(speedInput[1])
        end

        if numSpeed and numSpeed > 0 then
            flySpeed = numSpeed
            logFunc("Fly speed set to " .. tostring(flySpeed) .. ".", "default")
        else
            logFunc("Invalid speed parameter. Usage: flyspeed <number>", "warn")
        end
    end
}

local flinging = false
-- Fling / Desync
Functions["fling"] = {
    Name = "fling",
    Arguments = {},
    Category = "Movement",
    Function = function()
        flinging = not flinging
        local desyncEnabled = flinging
        local LocalPlayer = Players.LocalPlayer
        if not LocalPlayer:FindFirstChild("DesyncFlingEnabled") then
            if desyncEnabled then
                local globalFlag = Instance.new("BoolValue")
                globalFlag.Name = "DesyncFlingEnabled"
                globalFlag.Value = true
                globalFlag.Parent = LocalPlayer
                logFunc("Desync Fling enabled.", "default")
            end
        elseif not desyncEnabled then
            local existingFlag = LocalPlayer:FindFirstChild("DesyncFlingEnabled")
            if existingFlag then existingFlag:Destroy() end
            logFunc("Desync Fling disabled.", "default")
        end
        
        local jitter = 0.1
        while desyncEnabled do
            if _G.ShellRunning == false then
                desyncEnabled = false
                local existingFlag = LocalPlayer:FindFirstChild("DesyncFlingEnabled")
                if existingFlag then existingFlag:Destroy() end
                break
            end

            if not LocalPlayer:FindFirstChild("DesyncFlingEnabled") then
                break
            end
            RunService.Heartbeat:Wait()
            local _, rootPart = getLocalCharacterParts()
            
            if rootPart then
                local originalVelocity = rootPart.Velocity
                rootPart.Velocity = (originalVelocity * 10000) + Vector3.new(0, 10000, 0)
                RunService.RenderStepped:Wait()
                
                rootPart.Velocity = originalVelocity
                RunService.Stepped:Wait()
                
                rootPart.Velocity = originalVelocity + Vector3.new(0, jitter, 0)
                jitter = -jitter
            end
        end
    end
}

-- Noclip
local noclipEnabled = false
local noclipConnection = nil

Functions["noclip"] = {
    Name = "noclip",
    Arguments = {},
    Category = "Movement",
    Function = function()
        noclipEnabled = not noclipEnabled
        
        if noclipEnabled then
            logFunc("Noclip enabled.", "default")
            if noclipConnection then noclipConnection:Disconnect() end
            
            noclipConnection = RunService.Stepped:Connect(function()
                if _G.ShellRunning == false then
                    if noclipConnection then
                        noclipConnection:Disconnect()
                        noclipConnection = nil
                    end
                    noclipEnabled = false
                    return
                end

                local player = LocalPlayer or game:GetService("Players").LocalPlayer
                if player and player.Character then
                    for _, part in ipairs(player.Character:GetDescendants()) do
                        if part:IsA("BasePart") then
                            part.CanCollide = false
                        end
                    end
                end
            end)
        else
            logFunc("Noclip disabled.", "default")
            if noclipConnection then
                noclipConnection:Disconnect()
                noclipConnection = nil
            end
            
            local player = LocalPlayer or game:GetService("Players").LocalPlayer
            if player and player.Character then
                for _, part in ipairs(player.Character:GetDescendants()) do
                    if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                        part.CanCollide = true
                    end
                end
            end
        end
    end
}

return Functions