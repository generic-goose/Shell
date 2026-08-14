-- ============================================================================
-- 1. SERVICES & DEPENDENCIES
-- Localize Roblox services at the top for performance and clarity.
-- ============================================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local StarterGui = game:GetService("StarterGui")
local SoundService = game:GetService("SoundService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local Functions = {}

-- State variables for persistent or toggled command loops
local commandStates = {
    infiniteJump = false,
    bhop = false,
    spin = false,
    spinSpeed = 10,
    fullbright = false,
    xray = false,
    godMode = false,
    antiAfk = false,
    freecam = false,
    clickDelete = false,
    muted = false,
}

local connections = {}
local currentAudio = nil

-- ============================================================================
-- 2. CENTRALIZED LOGGING SYSTEM
-- All commands log output through logFunc to maintain compatibility with ShellLog.
-- ============================================================================
local function devlog(msg)
    if _G.ShellLog then
        _G.ShellLog("[Dev]: " .. tostring(msg), "developer")
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

local function PathToInstance(path)
    if not path or path == "" then
        return nil
    end

    local segments = string.split(path, ".")
    local currentInstance = game

    for _, segment in ipairs(segments) do
        if segment ~= "" then
            currentInstance = currentInstance:FindFirstChild(segment)
            if not currentInstance then
                return nil
            end
        end
    end

    return currentInstance
end

-- ============================================================================
-- 3. UTILITY HELPER FUNCTIONS
-- Common internal functions to keep command implementations concise.
-- ============================================================================

local function getLocalCharacterParts()
    local char = LocalPlayer and LocalPlayer.Character
    if not char then return nil, nil, nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")
    return char, hum, hrp
end

local function findPlayerByName(targetName)
    if not targetName or targetName == "" then return nil end
    targetName = targetName:lower()
    
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Name:lower():sub(1, #targetName) == targetName or 
           p.DisplayName:lower():sub(1, #targetName) == targetName then
            return p
        end
    end
    return nil
end

-- ============================================================================
-- 4. COMMAND DEFINITIONS
-- ============================================================================


--------------------------------------------------------------------------------
-- Category: Automation
--------------------------------------------------------------------------------
local function getAutofarmSetting(settingName, defaultValue)
    if _G.ShellSettings 
        and _G.ShellSettings.Scripts 
        and _G.ShellSettings.Scripts["autofarm"] 
        and _G.ShellSettings.Scripts["autofarm"][settingName] ~= nil then
        return _G.ShellSettings.Scripts["autofarm"][settingName]
    end
    return defaultValue
end

local tweenedObjects = {}

local function applyTweenMoveToPlayer(targetPart)
    if not targetPart then
        return
    end

    if tweenedObjects[targetPart] then
        return
    end
    tweenedObjects[targetPart] = true

    local player = game.Players.LocalPlayer
    local character = player.Character or player.CharacterAdded:Wait()
    local humanoidRootPart = character:WaitForChild("HumanoidRootPart")

    local partToTween = nil
    if targetPart:IsA("Model") then
        partToTween = targetPart.PrimaryPart or targetPart:FindFirstChild("Main") or targetPart:FindFirstChild("Part") or targetPart:FindFirstChildOfClass("BasePart")
    elseif targetPart:IsA("BasePart") then
        partToTween = targetPart
    end

    if not partToTween or not partToTween:IsA("BasePart") then
        tweenedObjects[targetPart] = nil
        return
    end

    local originalAnchored = partToTween.Anchored
    local originalCanCollide = partToTween.CanCollide

    partToTween.Anchored = true
    partToTween.CanCollide = false

    local tweenService = game:GetService("TweenService")
    local tweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Linear)
    local tweenGoal = { CFrame = humanoidRootPart.CFrame }
    local tween = tweenService:Create(partToTween, tweenInfo, tweenGoal)

    tween:Play()

    tween.Completed:Connect(function()
        partToTween.CanCollide = originalCanCollide
        task.delay(0.5, function()
            tweenedObjects[targetPart] = nil
        end)
    end)
end

-- Helper function to evaluate the item against check types
local function matchesCheckType(v, checkType, expected)
    if checkType == "HasName" then
        return v.Name == expected
    elseif checkType == "HasType" then
        return v:IsA(expected)
    elseif checkType == "HasChildWithName" then
        for _, child in ipairs(v:GetChildren()) do
            if child.Name == expected then
                return true
            end
        end
        return false
    elseif checkType == "HasChildWithType" then
        for _, child in ipairs(v:GetChildren()) do
            if child:IsA(expected) then
                return true
            end
        end
        return false
    end
    return false
end

local autoFarm = false
Functions["autofarm"] = {
    Name = "autofarm",
    Arguments = {"Speed", "Path", "Expected"},
    Category = "Automation",
    Settings = {
        CheckType = {"HasName", "HasType", "HasChildWithName", "HasChildWithType"},
        CollectType = {"Player Tween", "Object Tween"},
        SelectType = {"Closest", "Hierarchy"},
    },
    Function = function(speed, path, expected)
        if not (expected and path and speed) and not autoFarm then
            logFunc("Usage: autofarm <Speed> <Path> <Expected>", "warn")
            return
        end
        autoFarm = not autoFarm
        logFunc("Auto Farm: " .. (autoFarm and "Enabled" or "Disabled"), "default")
        if not autoFarm then return end
        
        local TweenService = game:GetService("TweenService")
        local player = game.Players.LocalPlayer
        
        local moveSpeed = tonumber(speed) or 500

        local pathInstance = PathToInstance(path)
        if not pathInstance then
            logFunc("Invalid path: " .. path, "error")
            return
        end

        while autoFarm and _G.ShellRunning do
            local character = player.Character or player.CharacterAdded:Wait()
            local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")

            if humanoidRootPart then
                local collectType = getAutofarmSetting("CollectType", "Object Tween")
                local autofarmtype = getAutofarmSetting("CheckType", "HasName")
                local selectType = getAutofarmSetting("SelectType", "Closest")

                if collectType == "Object Tween" then
                    local foundAny = false
                    for _, v in ipairs(pathInstance:GetChildren()) do
                        if matchesCheckType(v, autofarmtype, expected) then
                            foundAny = true
                            applyTweenMoveToPlayer(v)
                        end
                    end

                    if not foundAny then
                        task.wait(0.5)
                    else
                        task.wait(0.1)
                    end
                else
                    local targetPart = nil
                    local shortestDistance = math.huge

                    if selectType == "Hierarchy" then
                        for _, v in ipairs(pathInstance:GetChildren()) do
                            if matchesCheckType(v, autofarmtype, expected) then
                                targetPart = v
                                break
                            end
                        end
                    else
                        for _, v in ipairs(pathInstance:GetChildren()) do
                            if matchesCheckType(v, autofarmtype, expected) then
                                local targetCFrame
                                if typeof(v.GetPivot) == "function" then
                                    targetCFrame = v:GetPivot()
                                elseif v:IsA("Model") then
                                    targetCFrame = v.WorldPivot
                                elseif v:IsA("BasePart") then
                                    targetCFrame = v.CFrame
                                else
                                    continue
                                end

                                local distance = (humanoidRootPart.Position - targetCFrame.Position).Magnitude

                                if distance < shortestDistance then
                                    shortestDistance = distance
                                    targetPart = v
                                end
                            end
                        end
                    end

                    if targetPart then
                        local targetCFrame
                        if typeof(targetPart.GetPivot) == "function" then
                            targetCFrame = targetPart:GetPivot()
                        elseif targetPart:IsA("Model") then
                            targetCFrame = targetPart.WorldPivot
                        elseif targetPart:IsA("BasePart") then
                            targetCFrame = targetPart.CFrame
                        else
                            targetCFrame = CFrame.new()
                        end

                        local distance = (humanoidRootPart.Position - targetCFrame.Position).Magnitude
                        local duration = math.max(distance / moveSpeed, 0.05)

                        local tweenInfo = TweenInfo.new(
                            duration,
                            Enum.EasingStyle.Linear,
                            Enum.EasingDirection.Out
                        )

                        local tween = TweenService:Create(humanoidRootPart, tweenInfo, { CFrame = targetCFrame })
                        tween:Play()
                        tween.Completed:Wait()
                        task.wait(0.18)
                    else
                        task.wait(0.5)
                    end
                end
            else
                task.wait(0.5)
            end
        end
    end
}

--------------------------------------------------------------------------------
-- Category: Movement
--------------------------------------------------------------------------------

Functions["infjump"] = {
    Name = "infjump",
    Arguments = {},
    Category = "Movement",
    Function = function()
        commandStates.infiniteJump = not commandStates.infiniteJump
        
        if commandStates.infiniteJump then
            if connections["InfJump"] then connections["InfJump"]:Disconnect() end
            connections["InfJump"] = UserInputService.JumpRequest:Connect(function()
                local _, hum, _ = getLocalCharacterParts()
                if hum then
                    hum:ChangeState(Enum.HumanoidStateType.Jumping)
                end
            end)
            logFunc("Infinite Jump enabled.", "default")
        else
            if connections["InfJump"] then
                connections["InfJump"]:Disconnect()
                connections["InfJump"] = nil
            end
            logFunc("Infinite Jump disabled.", "default")
        end
    end
}

Functions["bhop"] = {
    Name = "bhop",
    Arguments = {},
    Category = "Movement",
    Function = function()
        commandStates.bhop = not commandStates.bhop
        
        if commandStates.bhop then
            if connections["BHop"] then connections["BHop"]:Disconnect() end
            connections["BHop"] = RunService.PreRender:Connect(function()
                local _, hum, _ = getLocalCharacterParts()
                if hum and hum.FloorMaterial ~= Enum.Material.Air then
                    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
                        hum:ChangeState(Enum.HumanoidStateType.Jumping)
                    end
                end
            end)
            logFunc("Bunny Hop enabled.", "default")
        else
            if connections["BHop"] then
                connections["BHop"]:Disconnect()
                connections["BHop"] = nil
            end
            logFunc("Bunny Hop disabled.", "default")
        end
    end
}

Functions["spin"] = {
    Name = "spin",
    Arguments = {"Speed"},
    Category = "Movement",
    Function = function(speedArg)
        local speed = tonumber(speedArg) or 10
        commandStates.spinSpeed = speed
        
        if not commandStates.spin then
            commandStates.spin = true
            if connections["Spin"] then connections["Spin"]:Disconnect() end
            
            connections["Spin"] = RunService.PreRender:Connect(function(dt)
                local _, _, hrp = getLocalCharacterParts()
                if hrp then
                    hrp.CFrame = hrp.CFrame * CFrame.Angles(0, math.rad(commandStates.spinSpeed * dt * 60), 0)
                end
            end)
            logFunc("Spin enabled at speed " .. tostring(speed) .. ".", "default")
        else
            commandStates.spin = false
            if connections["Spin"] then
                connections["Spin"]:Disconnect()
                connections["Spin"] = nil
            end
            logFunc("Spin disabled.", "default")
        end
    end
}

Functions["unspin"] = {
    Name = "unspin",
    Arguments = {},
    Category = "Movement",
    Function = function()
        if commandStates.spin then
            commandStates.spin = false
            if connections["Spin"] then
                connections["Spin"]:Disconnect()
                connections["Spin"] = nil
            end
            logFunc("Spin disabled.", "default")
        else
            logFunc("Spin was not active.", "warn")
        end
    end
}

Functions["gravity"] = {
    Name = "gravity",
    Arguments = {"Number"},
    Category = "Movement",
    Function = function(amount)
        local grav = tonumber(amount)
        if not grav then
            return logFunc("Invalid gravity value. Usage: gravity <number>", "warn")
        end
        Workspace.Gravity = grav
        logFunc("Workspace gravity set to " .. tostring(grav) .. ".", "default")
    end
}

Functions["resetgravity"] = {
    Name = "resetgravity",
    Arguments = {},
    Category = "Movement",
    Function = function()
        Workspace.Gravity = 196.2
        logFunc("Workspace gravity reset to default (196.2).", "default")
    end
}

Functions["walkspeed"] = {
    Name = "walkspeed",
    Arguments = {"Number"},
    Category = "Movement",
    Function = function(speed)
        local num = tonumber(speed)
        if not num then
            return logFunc("Invalid speed value. Usage: walkspeed <number>", "warn")
        end
        local _, hum, _ = getLocalCharacterParts()
        if hum then
            hum.WalkSpeed = num
            logFunc("WalkSpeed set to " .. tostring(num) .. ".", "default")
        end
    end
}

Functions["ws"] = {
    Name = "ws",
    Arguments = {"Number"},
    Category = "Movement",
    Function = Functions["walkspeed"].Function
}

Functions["jumppower"] = {
    Name = "jumppower",
    Arguments = {"Number"},
    Category = "Movement",
    Function = function(power)
        local num = tonumber(power)
        if not num then
            return logFunc("Invalid jump power value. Usage: jumppower <number>", "warn")
        end
        local _, hum, _ = getLocalCharacterParts()
        if hum then
            hum.UseJumpPower = true
            hum.JumpPower = num
            logFunc("JumpPower set to " .. tostring(num) .. ".", "default")
        end
    end
}

Functions["jp"] = {
    Name = "jp",
    Arguments = {"Number"},
    Category = "Movement",
    Function = Functions["jumppower"].Function
}

--------------------------------------------------------------------------------
-- Category: Player
--------------------------------------------------------------------------------

Functions["fov"] = {
    Name = "fov",
    Arguments = {"Number"},
    Category = "Player",
    Function = function(amount)
        local fovVal = tonumber(amount)
        if not fovVal or fovVal < 1 or fovVal > 120 then
            return logFunc("Invalid FOV value (1-120). Usage: fov <number>", "warn")
        end
        Camera.FieldOfView = fovVal
        logFunc("Field of View set to " .. tostring(fovVal) .. ".", "default")
    end
}

Functions["sit"] = {
    Name = "sit",
    Arguments = {},
    Category = "Player",
    Function = function()
        local _, hum, _ = getLocalCharacterParts()
        if hum then
            hum.Sit = true
            logFunc("Player forced into sit state.", "default")
        end
    end
}

Functions["god"] = {
    Name = "god",
    Arguments = {},
    Category = "Player",
    Function = function()
        local _, hum, _ = getLocalCharacterParts()
        if hum then
            hum.MaxHealth = math.huge
            hum.Health = math.huge
            logFunc("Client-side local health set to maximum.", "default")
        else
            logFunc("Character or Humanoid missing.", "error")
        end
    end
}

Functions["ungod"] = {
    Name = "ungod",
    Arguments = {},
    Category = "Player",
    Function = function()
        local _, hum, _ = getLocalCharacterParts()
        if hum then
            hum.MaxHealth = 100
            hum.Health = 100
            logFunc("Local health reset to 100.", "default")
        end
    end
}

--------------------------------------------------------------------------------
-- Category: Visual & Camera
--------------------------------------------------------------------------------

Functions["fullbright"] = {
    Name = "fullbright",
    Arguments = {},
    Category = "Visual",
    Function = function()
        commandStates.fullbright = not commandStates.fullbright
        
        if commandStates.fullbright then
            Lighting.Ambient = Color3.fromRGB(255, 255, 255)
            Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
            Lighting.Brightness = 2
            Lighting.GlobalShadows = false
            logFunc("Fullbright enabled.", "default")
        else
            Lighting.Ambient = Color3.fromRGB(127, 127, 127)
            Lighting.OutdoorAmbient = Color3.fromRGB(127, 127, 127)
            Lighting.Brightness = 1
            Lighting.GlobalShadows = true
            logFunc("Fullbright disabled.", "default")
        end
    end
}

local chams = false
Functions["chams"] = {
    Name = "chams",
    Arguments = {},
    Category = "Visual",
    Function = function()
        chams = true
        local count = 0
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character then
                local highlight = p.Character:FindFirstChild("ShellChams")
                if not highlight then
                    highlight = Instance.new("Highlight")
                    highlight.Name = "ShellChams"
                    highlight.FillColor = p.TeamColor.Color
                    highlight.OutlineColor = p.TeamColor.Color
                    highlight.FillTransparency = 0.5
                    highlight.OutlineTransparency = 0
                    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    highlight.Parent = p.Character
                    count = count + 1
                end
                p.CharacterAdded:Connect(function(char)
                    if not chams then return end
                    local highlight = p.Character:FindFirstChild("ShellChams")
                    if not highlight then
                        highlight = Instance.new("Highlight")
                        highlight.Name = "ShellChams"
                        highlight.FillColor = p.TeamColor.Color
                        highlight.OutlineColor = p.TeamColor.Color
                        highlight.FillTransparency = 0.5
                        highlight.OutlineTransparency = 0
                        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                        highlight.Parent = p.Character
                        count = count + 1
                    end
                end)
            end
        end
        Players.PlayerAdded:Connect(function()
            local highlight = p.Character:FindFirstChild("ShellChams")
            if not highlight then
                highlight = Instance.new("Highlight")
                highlight.Name = "ShellChams"
                highlight.FillColor = p.TeamColor.Color
                highlight.OutlineColor = p.TeamColor.Color
                highlight.FillTransparency = 0.5
                highlight.OutlineTransparency = 0
                highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                highlight.Parent = p.Character
                count = count + 1
            end
            p.CharacterAdded:Connect(function(char)
                if not chams then return end
                local highlight = p.Character:FindFirstChild("ShellChams")
                if not highlight then
                    highlight = Instance.new("Highlight")
                    highlight.Name = "ShellChams"
                    highlight.FillColor = p.TeamColor.Color
                    highlight.OutlineColor = p.TeamColor.Color
                    highlight.FillTransparency = 0.5
                    highlight.OutlineTransparency = 0
                    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    highlight.Parent = p.Character
                    count = count + 1
                end
            end)
        end)
        logFunc("Applied chams to " .. tostring(count) .. " players.", "default")
    end
}

Functions["unchams"] = {
    Name = "unchams",
    Arguments = {},
    Category = "Visual",
    Function = function()
        chams = false
        local count = 0
        for _, p in ipairs(Players:GetPlayers()) do
            if p.Character then
                local highlight = p.Character:FindFirstChild("ShellChams")
                if highlight then
                    highlight:Destroy()
                    count = count + 1
                end
            end
        end
        logFunc("Removed chams from " .. tostring(count) .. " players.", "default")
    end
}

Functions["xray"] = {
    Name = "xray",
    Arguments = {},
    Category = "Visual",
    Function = function()
        commandStates.xray = not commandStates.xray
        
        for _, object in ipairs(Workspace:GetDescendants()) do
            if object:IsA("BasePart") and not object:IsDescendantOf(LocalPlayer.Character) then
                if commandStates.xray then
                    if not object:FindFirstChild("OriginalTransparency") then
                        local tag = Instance.new("NumberValue")
                        tag.Name = "OriginalTransparency"
                        tag.Value = object.LocalTransparencyModifier
                        tag.Parent = object
                    end
                    object.LocalTransparencyModifier = 0.75
                else
                    local tag = object:FindFirstChild("OriginalTransparency")
                    if tag then
                        object.LocalTransparencyModifier = tag.Value
                        tag:Destroy()
                    else
                        object.LocalTransparencyModifier = 0
                    end
                end
            end
        end
        logFunc("X-Ray toggled: " .. tostring(commandStates.xray), "default")
    end
}

Functions["freecam"] = {
    Name = "freecam",
    Arguments = {},
    Category = "Visual",
    Function = function()
        commandStates.freecam = not commandStates.freecam

        if commandStates.freecam then
            Camera.CameraType = Enum.CameraType.Scriptable
            local speed = 1
            local sensitivity = 0.005

            local position = Camera.CFrame.Position
            local rotX, rotY = Camera.CFrame:ToOrientation() -- pitch (X), yaw (Y), in radians
            local rightMouseDown = false

            if connections["Freecam"] then connections["Freecam"]:Disconnect() end
            if connections["FreecamInputBegan"] then connections["FreecamInputBegan"]:Disconnect() end
            if connections["FreecamInputEnded"] then connections["FreecamInputEnded"]:Disconnect() end

            connections["FreecamInputBegan"] = UserInputService.InputBegan:Connect(function(input, gameProcessed)
                if input.UserInputType == Enum.UserInputType.MouseButton2 then
                    rightMouseDown = true
                    UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
                    UserInputService.MouseIconEnabled = false
                end
            end)

            connections["FreecamInputEnded"] = UserInputService.InputEnded:Connect(function(input, gameProcessed)
                if input.UserInputType == Enum.UserInputType.MouseButton2 then
                    rightMouseDown = false
                    UserInputService.MouseBehavior = Enum.MouseBehavior.Default
                    UserInputService.MouseIconEnabled = true
                end
            end)

            connections["Freecam"] = RunService.RenderStepped:Connect(function(dt)
                if rightMouseDown then
                    local delta = UserInputService:GetMouseDelta()
                    rotY -= delta.X * sensitivity
                    rotX -= delta.Y * sensitivity
                    rotX = math.clamp(rotX, math.rad(-89), math.rad(89))
                end

                local lookCFrame = CFrame.Angles(0, rotY, 0) * CFrame.Angles(rotX, 0, 0)

                local moveVector = Vector3.zero
                if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveVector += lookCFrame.LookVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveVector -= lookCFrame.LookVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveVector -= lookCFrame.RightVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveVector += lookCFrame.RightVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.E) then moveVector += lookCFrame.UpVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.Q) then moveVector -= lookCFrame.UpVector end

                position += moveVector * (speed * dt * 50)
                Camera.CFrame = CFrame.new(position) * lookCFrame
            end)

            logFunc("Freecam enabled. WASD+Q/E to move, hold right click to look around.", "default")
        else
            if connections["Freecam"] then
                connections["Freecam"]:Disconnect()
                connections["Freecam"] = nil
            end
            if connections["FreecamInputBegan"] then
                connections["FreecamInputBegan"]:Disconnect()
                connections["FreecamInputBegan"] = nil
            end
            if connections["FreecamInputEnded"] then
                connections["FreecamInputEnded"]:Disconnect()
                connections["FreecamInputEnded"] = nil
            end

            UserInputService.MouseBehavior = Enum.MouseBehavior.Default
            UserInputService.MouseIconEnabled = true
            Camera.CameraType = Enum.CameraType.Custom
            logFunc("Freecam disabled.", "default")
        end
    end
}

Functions["ambient"] = {
    Name = "ambient",
    Arguments = {"R", "G", "B"},
    Category = "Visual",
    Function = function(r, g, b)
        local red = tonumber(r) or 255
        local green = tonumber(g) or 255
        local blue = tonumber(b) or 255
        
        Lighting.Ambient = Color3.fromRGB(red, green, blue)
        Lighting.OutdoorAmbient = Color3.fromRGB(red, green, blue)
        logFunc(string.format("Ambient set to RGB(%d, %d, %d)", red, green, blue), "default")
    end
}

--------------------------------------------------------------------------------
-- Category: Utility & Automation
--------------------------------------------------------------------------------

Functions["antiafk"] = {
    Name = "antiafk",
    Arguments = {},
    Category = "Utility",
    Function = function()
        commandStates.antiAfk = not commandStates.antiAfk

        if commandStates.antiAfk then
            if connections["AntiAfk"] then connections["AntiAfk"]:Disconnect() end
            
            local VirtualUser = game:GetService("VirtualUser")
            connections["AntiAfk"] = LocalPlayer.Idled:Connect(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
                logFunc("Prevented AFK disconnect.", "default")
            end)
            logFunc("Anti-AFK system activated.", "default")
        else
            if connections["AntiAfk"] then
                connections["AntiAfk"]:Disconnect()
                connections["AntiAfk"] = nil
            end
            logFunc("Anti-AFK system deactivated.", "default")
        end
    end
}

Functions["copypos"] = {
    Name = "copypos",
    Arguments = {},
    Category = "Utility",
    Function = function()
        local _, _, hrp = getLocalCharacterParts()
        if hrp then
            local pos = hrp.Position
            local posString = string.format("%.2f, %.2f, %.2f", pos.X, pos.Y, pos.Z)
            if setclipboard then
                setclipboard(posString)
                logFunc("Copied coordinates to clipboard: " .. posString, "default")
            else
                logFunc("Position: " .. posString .. " (setclipboard not supported)", "warn")
            end
        else
            logFunc("HumanoidRootPart missing.", "error")
        end
    end
}

Functions["time"] = {
    Name = "time",
    Arguments = {"Number"},
    Category = "Utility",
    Function = function(timeArg)
        local timeNum = tonumber(timeArg)
        if not timeNum then
            return logFunc("Invalid time value. Usage: time <0-24>", "warn")
        end
        Lighting.ClockTime = timeNum
        logFunc("Clock time set to " .. tostring(timeNum) .. ":00.", "default")
    end
}

Functions["fogend"] = {
    Name = "fogend",
    Arguments = {"Number"},
    Category = "Visual",
    Function = function(distance)
        local dist = tonumber(distance)
        if not dist then
            return logFunc("Invalid fog distance. Usage: fogend <number>", "warn")
        end
        Lighting.FogEnd = dist
        logFunc("FogEnd set to " .. tostring(dist) .. ".", "default")
    end
}

Functions["clickdelete"] = {
    Name = "clickdelete",
    Arguments = {},
    Category = "Utility",
    Function = function()
        commandStates.clickDelete = not commandStates.clickDelete

        if commandStates.clickDelete then
            if connections["ClickDelete"] then connections["ClickDelete"]:Disconnect() end
            connections["ClickDelete"] = UserInputService.InputBegan:Connect(function(input, gameProcessed)
                if not gameProcessed and input.UserInputType == Enum.UserInputType.MouseButton1 then
                    local target = LocalPlayer:GetMouse().Target
                    if target and not target:IsDescendantOf(LocalPlayer.Character) then
                        target:Destroy()
                        logFunc("Destroyed part: " .. target:GetFullName(), "default")
                    end
                end
            end)
            logFunc("Click Delete enabled. Click any object to remove it locally.", "default")
        else
            if connections["ClickDelete"] then
                connections["ClickDelete"]:Disconnect()
                connections["ClickDelete"] = nil
            end
            logFunc("Click Delete disabled.", "default")
        end
    end
}

Functions["bringpart"] = {
    Name = "bringpart",
    Arguments = {"PartName"},
    Category = "Utility",
    Function = function(partName)
        if not partName or partName == "" then
            return logFunc("Part name required. Usage: bringpart <PartName>", "warn")
        end

        local _, _, hrp = getLocalCharacterParts()
        if not hrp then return logFunc("Character root part missing.", "error") end

        local targetPart = Workspace:FindFirstChild(partName, true)
        if targetPart and targetPart:IsA("BasePart") then
            targetPart.CFrame = hrp.CFrame * CFrame.new(0, 0, -5)
            logFunc("Brought part '" .. targetPart.Name .. "' to player.", "default")
        else
            logFunc("BasePart '" .. tostring(partName) .. "' not found in Workspace.", "error")
        end
    end
}

--------------------------------------------------------------------------------
-- Category: Network & Teleportation
--------------------------------------------------------------------------------

Functions["serverhop"] = {
    Name = "serverhop",
    Arguments = {},
    Category = "Network",
    Function = function()
        logFunc("Searching for alternative server...", "default")
        local placeId = game.PlaceId
        local req = (syn and syn.request) or (http and http.request) or http_request or request

        if req then
            local serversApi = "https://games.roblox.com/v1/games/" .. tostring(placeId) .. "/servers/Public?sortOrder=Asc&limit=100"
            local success, response = pcall(function()
                return req({ Url = serversApi, Method = "GET" })
            end)

            if success and response and response.Body then
                local data = HttpService:JSONDecode(response.Body)
                if data and data.data then
                    for _, server in ipairs(data.data) do
                        if server.id ~= game.JobId and server.playing < server.maxPlayers then
                            TeleportService:TeleportToPlaceInstance(placeId, server.id, LocalPlayer)
                            return
                        end
                    end
                end
            end
        end
        logFunc("Failed to find standard server; attempting random rejoin.", "warn")
        TeleportService:Teleport(placeId, LocalPlayer)
    end
}

Functions["teleportplace"] = {
    Name = "teleportplace",
    Category = "Network",
    Arguments = {"PlaceId"},
    Function = function(placeIdArg)
        local pid = tonumber(placeIdArg)
        if not pid then
            return logFunc("Invalid Place ID. Usage: teleportplace <PlaceID>", "warn")
        end
        logFunc("Teleporting to Place ID: " .. tostring(pid), "default")
        TeleportService:Teleport(pid, LocalPlayer)
    end
}

--------------------------------------------------------------------------------
-- Category: Audio
--------------------------------------------------------------------------------

Functions["playaudio"] = {
    Name = "playaudio",
    Arguments = {"SoundId", "Volume"},
    Category = "Sound",
    Function = function(soundId, volume)
        if not soundId then
            return logFunc("Missing Sound ID. Usage: playaudio <SoundId> [Volume]", "warn")
        end
        
        if currentAudio then
            currentAudio:Stop()
            currentAudio:Destroy()
        end

        local sound = Instance.new("Sound")
        sound.Name = "ShellAudioPlayer"
        sound.SoundId = "rbxassetid://" .. tostring(soundId)
        sound.Volume = tonumber(volume) or 1
        sound.Parent = SoundService
        sound:Play()

        currentAudio = sound
        logFunc("Playing audio ID: " .. tostring(soundId), "default")
    end
}

Functions["stopaudio"] = {
    Name = "stopaudio",
    Arguments = {},
    Category = "Sound",
    Function = function()
        if currentAudio then
            currentAudio:Stop()
            currentAudio:Destroy()
            currentAudio = nil
            logFunc("Audio playback stopped.", "default")
        else
            logFunc("No audio is currently playing.", "warn")
        end
    end
}

--------------------------------------------------------------------------------
-- Category: Additional Extra Commands (Info & Diagnostics)
--------------------------------------------------------------------------------

Functions["serverinfo"] = {
    Name = "serverinfo",
    Arguments = {},
    Category = "Utility",
    Function = function()
        local infoText = string.format("PlaceID: %d | JobID: %s | Players: %d/%d", game.PlaceId, game.JobId, #Players:GetPlayers(), Players.MaxPlayers)
        logFunc(infoText, "default")
    end
}

Functions["fps"] = {
    Name = "fps",
    Arguments = {},
    Category = "Utility",
    Function = function()
        local currentFps = math.round(1 / RunService.RenderStepped:Wait())
        logFunc("Current estimated FPS: " .. tostring(currentFps), "default")
    end
}

Functions["togglesound"] = {
    Name = "togglesound",
    Arguments = {},
    Category = "Sound",
    Function = function()
        commandStates.muted = not commandStates.muted
        SoundService.Volume = commandStates.muted and 0 or 1
        logFunc("Global audio output muted: " .. tostring(commandStates.muted), "default")
    end
}

Functions["resetcam"] = {
    Name = "resetcam",
    Arguments = {},
    Category = "Visual",
    Function = function()
        Camera.CameraType = Enum.CameraType.Custom
        Camera.FieldOfView = 70
        logFunc("Camera settings reset to default.", "default")
    end
}

Functions["servertime"] = {
    Name = "servertime",
    Arguments = {},
    Category = "Utility",
    Function = function()
        local t = os.date("*t")
        logFunc(string.format("Current local time: %02d:%02d:%02d", t.hour, t.min, t.sec), "default")
    end
}
return Functions
