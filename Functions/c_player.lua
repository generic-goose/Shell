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

local espEnabled = false
local activeConnections = {}
local activeDrawings = {}

Functions["esp"] = {
    Name = "esp",
    Arguments = {},
    Settings = {
        Tracers = false,
        ClickFunction = {"None", "Teleport", "TweenTo", "View"}
    },
    Category = "Visual",
    Function = function()
        espEnabled = not espEnabled

        if not espEnabled then
            for _, conn in ipairs(activeConnections) do
                if conn then conn:Disconnect() end
            end
            activeConnections = {}

            for _, drawing in ipairs(activeDrawings) do
                if drawing then drawing:Remove() end
            end
            activeDrawings = {}
            return
        end

        -- Ensure settings structure exists to prevent nil errors
        _G.ShellSettings = _G.ShellSettings or {}
        _G.ShellSettings.Scripts = _G.ShellSettings.Scripts or {}
        _G.ShellSettings.Scripts["esp"] = _G.ShellSettings.Scripts["esp"] or {
            Tracers = false,
            ClickFunction = "None"
        }

        local CmdSettings = _G.ShellSettings.Scripts["esp"]
        local Players = game:GetService("Players")
        local RunService = game:GetService("RunService")
        local UserInputService = game:GetService("UserInputService")
        local TweenService = game:GetService("TweenService")
        local LocalPlayer = Players.LocalPlayer

        -- Global click detection for the boxes
        local clickConnection = UserInputService.InputBegan:Connect(function(input)
            if not espEnabled then return end
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                local mousePos = UserInputService:GetMouseLocation()
                
                for _, player in ipairs(Players:GetPlayers()) do
                    if player ~= LocalPlayer and player.Character then
                        local character = player.Character
                        local rootPart = character:FindFirstChild("HumanoidRootPart")
                        local humanoid = character:FindFirstChild("Humanoid")
                        
                        if rootPart and humanoid and humanoid.Health > 0 then
                            local camera = workspace.CurrentCamera
                            local cf, size = character:GetBoundingBox()
                            local topCenter = (cf + Vector3.new(0, size.Y / 2, 0)).Position
                            local bottomCenter = (cf - Vector3.new(0, size.Y / 2, 0)).Position

                            local topVector, topOnScreen = camera:WorldToViewportPoint(topCenter)
                            local bottomVector, bottomOnScreen = camera:WorldToViewportPoint(bottomCenter)

                            if topOnScreen or bottomOnScreen then
                                local height = math.abs(bottomVector.Y - topVector.Y)
                                local width = height / 2
                                local boxPos = Vector2.new(topVector.X - width / 2, topVector.Y)
                                local boxSize = Vector2.new(width, height)

                                if mousePos.X >= boxPos.X and mousePos.X <= boxPos.X + boxSize.X and
                                   mousePos.Y >= boxPos.Y and mousePos.Y <= boxPos.Y + boxSize.Y then
                                    
                                    if CmdSettings.ClickFunction == "Teleport" then
                                        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                                            LocalPlayer.Character:PivotTo(rootPart:GetPivot())
                                        end
                                    elseif CmdSettings.ClickFunction == "TweenTo" then
                                        local localRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                                        if localRoot then
                                            local targetCFrame = rootPart:GetPivot()
                                            local distance = (localRoot.Position - rootPart.Position).Magnitude
                                            local duration = math.max(distance / 200, 0.05)

                                            local tweenInfo = TweenInfo.new(
                                                duration,
                                                Enum.EasingStyle.Linear,
                                                Enum.EasingDirection.Out
                                            )

                                            local tween = TweenService:Create(localRoot, tweenInfo, { CFrame = targetCFrame })
                                            tween:Play()
                                        end
                                    elseif CmdSettings.ClickFunction == "View" then
                                        local camera = Workspace.CurrentCamera
                                        if not camera then devlog("c_player.lua -- expected camera, got nil or error.") return end
                                
                                        local targetPlayer = player
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
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end)
        table.insert(activeConnections, clickConnection)

        local function createESP(player)
            if player == LocalPlayer then return end

            local box = Drawing.new("Square")
            box.Visible = false
            box.Filled = false
            box.Thickness = 1
            table.insert(activeDrawings, box)

            local tracer = Drawing.new("Line")
            tracer.Visible = false
            tracer.Thickness = 1
            table.insert(activeDrawings, tracer)

            local nameLabel = Drawing.new("Text")
            nameLabel.Visible = false
            nameLabel.Size = 14
            nameLabel.Center = true
            nameLabel.Outline = true
            nameLabel.Color = Color3.new(1, 1, 1)
            table.insert(activeDrawings, nameLabel)

            local teamLabel = Drawing.new("Text")
            teamLabel.Visible = false
            teamLabel.Size = 14
            teamLabel.Center = false
            teamLabel.Outline = true
            table.insert(activeDrawings, teamLabel)

            local healthLabel = Drawing.new("Text")
            healthLabel.Visible = false
            healthLabel.Size = 14
            healthLabel.Center = false
            healthLabel.Outline = true
            table.insert(activeDrawings, healthLabel)

            local toolLabel = Drawing.new("Text")
            toolLabel.Visible = false
            toolLabel.Size = 14
            toolLabel.Center = false
            toolLabel.Outline = true
            toolLabel.Color = Color3.new(1, 1, 1)
            table.insert(activeDrawings, toolLabel)

            local connection
            connection = RunService.RenderStepped:Connect(function()
                if not espEnabled then return end
                
                local character = player.Character
                if not character or not character:FindFirstChild("HumanoidRootPart") or not character:FindFirstChild("Humanoid") then
                    box.Visible = false
                    tracer.Visible = false
                    nameLabel.Visible = false
                    teamLabel.Visible = false
                    healthLabel.Visible = false
                    toolLabel.Visible = false
                    return
                end

                local rootPart = character.HumanoidRootPart
                local humanoid = character.Humanoid
                local camera = workspace.CurrentCamera

                local cf, size = character:GetBoundingBox()
                local topCenter = (cf + Vector3.new(0, size.Y / 2, 0)).Position
                local bottomCenter = (cf - Vector3.new(0, size.Y / 2, 0)).Position

                local topVector, topOnScreen = camera:WorldToViewportPoint(topCenter)
                local bottomVector, bottomOnScreen = camera:WorldToViewportPoint(bottomCenter)

                if topOnScreen or bottomOnScreen then
                    local teamColor = player.Team and player.Team.TeamColor.Color or Color3.new(1, 1, 1)
                    box.Color = teamColor

                    local height = math.abs(bottomVector.Y - topVector.Y)
                    local width = height / 2

                    box.Size = Vector2.new(width, height)
                    box.Position = Vector2.new(topVector.X - width / 2, topVector.Y)
                    box.Visible = true

                    -- Tracer Logic
                    local tracersEnabled = CmdSettings and CmdSettings.Tracers
                    if tracersEnabled then
                        tracer.Visible = true
                        tracer.Color = teamColor
                        tracer.From = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y)
                        tracer.To = Vector2.new(bottomVector.X, bottomVector.Y)
                    else
                        tracer.Visible = false
                    end

                    nameLabel.Text = player.Name
                    nameLabel.Position = Vector2.new(topVector.X, topVector.Y - 18)
                    nameLabel.Visible = true

                    local rightX = box.Position.X + box.Size.X + 4
                    local startY = box.Position.Y

                    local teamName = player.Team and player.Team.Name or "No Team"
                    teamLabel.Text = "Team: " .. teamName
                    teamLabel.Color = teamColor
                    teamLabel.Position = Vector2.new(rightX, startY)
                    teamLabel.Visible = true

                    local healthPercent = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
                    healthLabel.Color = Color3.new(1 - healthPercent, healthPercent, 0)
                    healthLabel.Text = "HP: " .. math.floor(humanoid.Health)
                    healthLabel.Position = Vector2.new(rightX, startY + 16)
                    healthLabel.Visible = true

                    local equippedTool = character:FindFirstChildOfClass("Tool")
                    local toolName = equippedTool and equippedTool.Name or "None"
                    toolLabel.Text = "Tool: " .. toolName
                    toolLabel.Position = Vector2.new(rightX, startY + 32)
                    toolLabel.Visible = true
                else
                    box.Visible = false
                    tracer.Visible = false
                    nameLabel.Visible = false
                    teamLabel.Visible = false
                    healthLabel.Visible = false
                    toolLabel.Visible = false
                end

                if not player.Parent then
                    box:Remove()
                    tracer:Remove()
                    nameLabel:Remove()
                    teamLabel:Remove()
                    healthLabel:Remove()
                    toolLabel:Remove()
                    connection:Disconnect()
                end
            end)
            table.insert(activeConnections, connection)
        end

        for _, player in ipairs(Players:GetPlayers()) do
            createESP(player)
        end

        local playerAddedConn = Players.PlayerAdded:Connect(createESP)
        table.insert(activeConnections, playerAddedConn)
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
