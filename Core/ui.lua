local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")

local localPlayer = Players.LocalPlayer

-- Cleanup existing UI
if _G.ShellUI then
    _G.ShellUI:Destroy()
end

-- =========================================================
-- Theme Loader & Safe Type Conversion Logic
-- =========================================================

local DEFAULT_TEXT_COLOR = Color3.fromRGB(220, 220, 220)
local DEFAULT_THEME_PATH = "Shell/Assets/Themes/default.csv"
local SHELL_THEME_PATH = "Shell/Assets/Themes/shell.csv"

local function parseColor3(val)
    if typeof(val) == "Color3" then return val end
    if type(val) ~= "string" then return nil end
    
    local clean = val:gsub('\239\187\191', ''):gsub('"', ''):gsub("^%s*(.-)%s*$", "%1")
    
    local r, g, b = clean:match("(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
    if r and g and b then
        return Color3.fromRGB(tonumber(r), tonumber(g), tonumber(b))
    end
    
    local cleanHex = clean:gsub("#", "")
    if #cleanHex == 6 and tonumber(cleanHex, 16) then
        return Color3.fromHex(cleanHex)
    end
    
    return nil
end

local function toColor3(val, fallback)
    local parsed = parseColor3(val)
    if parsed then return parsed end
    if typeof(fallback) == "Color3" then return fallback end
    return DEFAULT_TEXT_COLOR
end

local function parseVector2(str)
    if type(str) ~= "string" then return nil end
    local clean = str:gsub('"', ''):gsub("^%s*(.-)%s*$", "%1")
    local x, y = clean:match("(%d+)%s*,%s*(%d+)")
    if x and y then
        return Vector2.new(tonumber(x), tonumber(y))
    end
    return nil
end

local function formatImageAsset(pathOrId)
    if not pathOrId or pathOrId == "" then return "" end

    if isfile and isfile(pathOrId) and getcustomasset then
        local success, customAsset = pcall(function()
            return getcustomasset(pathOrId)
        end)
        if success then return customAsset end
    end

    if pathOrId:find("rbxassetid://") or pathOrId:find("http") then
        return pathOrId
    end

    if tonumber(pathOrId) then
        return "rbxassetid://" .. pathOrId
    end

    return pathOrId
end

-- Automatic type detector for CSV entries
local function autoParseValue(key, val)
    local lowerVal = val:lower()

    -- 1. Booleans
    if lowerVal == "true" then return true end
    if lowerVal == "false" then return false end

    -- 2. Numbers
    if tonumber(val) then return tonumber(val) end

    -- 3. Color3 (RGB or Hex)
    local parsedColor = parseColor3(val)
    if parsedColor then return parsedColor end

    -- 4. Vector2 or UDim2
    local vec = parseVector2(val)
    if vec then
        if key:find("TileSize") or key:find("UDim2") then
            return UDim2.new(0, vec.X, 0, vec.Y)
        end
        return vec
    end

    -- 5. Enums (Font, ScaleType, etc.)
    if key:find("Font") then
        local ok, enumVal = pcall(function() return Enum.Font[val] end)
        if ok and enumVal then return enumVal end
    end

    if key:find("ScaleType") then
        local ok, enumVal = pcall(function() return Enum.ScaleType[val] end)
        if ok and enumVal then return enumVal end
    end

    -- 6. Fallback string
    return val
end

local THEME = {
    Background = Color3.fromRGB(25, 25, 25),
    Border = Color3.fromRGB(45, 45, 45),
    Text = Color3.fromRGB(220, 220, 220),
    Placeholder = Color3.fromRGB(120, 120, 120),
    Accent = Color3.fromRGB(100, 180, 255),
    Console_Info = Color3.fromRGB(200, 200, 200),
    Console_Warn = Color3.fromRGB(255, 180, 50),
    Console_Error = Color3.fromRGB(255, 100, 100),
    Console_Success = Color3.fromRGB(100, 255, 100),
    ConsoleFont = Enum.Font.Code,
    ConsoleFontSize = 14,
    CommandFont = Enum.Font.Code,
    CommandFontSize = 14,
    SuggestionTextColor = Color3.fromRGB(220, 220, 220),
    SuggestionFontSize = 14,
    FrameSize = Vector2.new(550, 400),
    UseUICorner = false,
    -- Customization Defaults
    CustomTitle = "",
    BackgroundImage = "",
    BackgroundImageTransparency = 0.5,
    BackgroundImageScaleType = Enum.ScaleType.Stretch,
    BackgroundImageTileSize = UDim2.new(0, 32, 0, 32),
    TypingSound = "",
    EnterSound = "",
}

local function resetThemeToDefaults()
    THEME.CustomTitle = ""
    THEME.BackgroundImage = ""
    THEME.BackgroundImageTransparency = 0.5
    THEME.BackgroundImageScaleType = Enum.ScaleType.Stretch
    THEME.BackgroundImageTileSize = UDim2.new(0, 32, 0, 32)
    THEME.TypingSound = ""
    THEME.EnterSound = ""
end

local function loadThemeFromCSV(filePath)
    resetThemeToDefaults()
    if not (readfile and isfile and isfile(filePath)) then devlog("ui.lua -- expected an existing theme file, got nil or error.") return end

    local content = readfile(filePath)
    for line in content:gmatch("[^\r\n]+") do
        local commaIdx = line:find(",")
        if commaIdx then
            local rawKey = line:sub(1, commaIdx - 1)
            local rawVal = line:sub(commaIdx + 1)
            
            local key = rawKey:gsub('\239\187\191', ''):gsub('"', ''):gsub("^%s*(.-)%s*$", "%1")
            local val = rawVal:gsub('"', ''):gsub("^%s*(.-)%s*$", "%1")

            if key:lower() ~= "key" and key ~= "" then
                THEME[key] = autoParseValue(key, val)
            end
        end
    end
end

pcall(function()
    if isfile and writefile and readfile then
        if not isfile(DEFAULT_THEME_PATH) and isfile(SHELL_THEME_PATH) then
            writefile(DEFAULT_THEME_PATH, readfile(SHELL_THEME_PATH))
        end
    end
    loadThemeFromCSV(DEFAULT_THEME_PATH)
end)

local function getAvailableThemes()
    local themes = {}
    local themeDir = "Shell/Assets/Themes"
    
    if listfiles and isfolder and isfolder(themeDir) then
        local files = listfiles(themeDir)
        for _, file in ipairs(files) do
            local name = file:match("([^/\\]+)%.csv$")
            if name then table.insert(themes, name) end
        end
    end
    
    return themes
end

-- ScreenGui Setup
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "Shell_Core"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local success = pcall(function() screenGui.Parent = CoreGui end)
if not success then screenGui.Parent = localPlayer:WaitForChild("PlayerGui") end
_G.ShellUI = screenGui

-- Audio Instances
local typingSoundObj = Instance.new("Sound")
typingSoundObj.Name = "TypingAudio"
typingSoundObj.Volume = 0.5
typingSoundObj.Parent = screenGui

local enterSoundObj = Instance.new("Sound")
enterSoundObj.Name = "EnterAudio"
enterSoundObj.Volume = 0.5
enterSoundObj.Parent = screenGui

local function playThemeAudio(soundObj, assetId)
    if assetId and assetId ~= "" then
        local formattedId = assetId:match("^rbxassetid://") and assetId or ("rbxassetid://" .. assetId)
        if soundObj.SoundId ~= formattedId then
            soundObj.SoundId = formattedId
        end
        soundObj:Play()
    end
end

-- Utility Helpers
local function addCorners(parent, radius)
    if not THEME.UseUICorner then return nil end
    local corner = Instance.new("UICorner")
    corner.CornerRadius = radius or UDim.new(0, 4)
    corner.Parent = parent
    return corner
end

local function addPadding(parent, padding)
    local uiPadding = Instance.new("UIPadding")
    uiPadding.PaddingTop = padding or UDim.new(0, 5)
    uiPadding.PaddingBottom = padding or UDim.new(0, 5)
    uiPadding.PaddingLeft = padding or UDim.new(0, 8)
    uiPadding.PaddingRight = padding or UDim.new(0, 8)
    return uiPadding
end

-- UI Construction
local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, THEME.FrameSize.X, 0, THEME.FrameSize.Y)
mainFrame.Position = UDim2.new(0.5, -THEME.FrameSize.X / 2, 0.5, -THEME.FrameSize.Y / 2)
mainFrame.BackgroundColor3 = toColor3(THEME.Background)
mainFrame.BorderSizePixel = 0
mainFrame.Visible = false
mainFrame.Active = true
mainFrame.ClipsDescendants = false
mainFrame.Parent = screenGui
addCorners(mainFrame)

local mainStroke = Instance.new("UIStroke")
mainStroke.Color = toColor3(THEME.Border)
mainStroke.Thickness = 1
mainStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
mainStroke.Parent = mainFrame

-- Title Bar
local titleBar = Instance.new("Frame")
titleBar.Name = "TitleBar"
titleBar.Size = UDim2.new(1, 0, 0, 30)
titleBar.BackgroundColor3 = toColor3(THEME.Border)
titleBar.BorderSizePixel = 0
titleBar.Parent = mainFrame
addCorners(titleBar)

local titleText = Instance.new("TextLabel")
titleText.Name = "TitleText"
titleText.Size = UDim2.new(1, -220, 1, 0)
titleText.Position = UDim2.new(0, 10, 0, 0)
titleText.BackgroundTransparency = 1
titleText.Text = "Shell Console"
titleText.TextColor3 = toColor3(THEME.Text)
titleText.Font = Enum.Font.GothamBold
titleText.TextSize = 14
titleText.TextXAlignment = Enum.TextXAlignment.Left
titleText.Parent = titleBar

-- Developer Console Checkbox Container
local devCheckboxFrame = Instance.new("Frame")
devCheckboxFrame.Name = "DevCheckboxFrame"
devCheckboxFrame.Size = UDim2.new(0, 170, 1, 0)
devCheckboxFrame.Position = UDim2.new(1, -200, 0, 0)
devCheckboxFrame.BackgroundTransparency = 1
devCheckboxFrame.Parent = titleBar

local devCheckboxButton = Instance.new("TextButton")
devCheckboxButton.Name = "DevCheckboxButton"
devCheckboxButton.Size = UDim2.new(1, 0, 1, 0)
devCheckboxButton.BackgroundTransparency = 1
devCheckboxButton.Text = "[ ] Enable Developer Console"
devCheckboxButton.TextColor3 = toColor3(THEME.Text)
devCheckboxButton.Font = Enum.Font.Gotham
devCheckboxButton.TextSize = 11
devCheckboxButton.TextTransparency = 1 -- Invisible by default
devCheckboxButton.TextXAlignment = Enum.TextXAlignment.Left
devCheckboxButton.Parent = devCheckboxFrame

local minButton = Instance.new("TextButton")
minButton.Name = "MinimizeButton"
minButton.Size = UDim2.new(0, 30, 1, 0)
minButton.Position = UDim2.new(1, -30, 0, 0)
minButton.BackgroundTransparency = 1
minButton.Text = "-"
minButton.TextColor3 = toColor3(THEME.Text)
minButton.Font = Enum.Font.GothamBold
minButton.TextSize = 16
minButton.Parent = titleBar

-- Background Listener to check _G.ShellDev state
task.spawn(function()
    while screenGui.Parent do
        if _G.ShellDev == true then
            devCheckboxButton.TextTransparency = 0
        else
            devCheckboxButton.TextTransparency = 1
        end
        task.wait(0.25)
    end
end)

-- Container
local container = Instance.new("Frame")
container.Name = "Container"
container.Size = UDim2.new(1, -10, 1, -40)
container.Position = UDim2.new(0, 5, 0, 35)
container.BackgroundTransparency = 1
container.Parent = mainFrame

local containerLayout = Instance.new("UIListLayout")
containerLayout.SortOrder = Enum.SortOrder.LayoutOrder
containerLayout.Padding = UDim.new(0, 5)
containerLayout.Parent = container

-- Console Frame Container
local consoleWrapper = Instance.new("Frame")
consoleWrapper.Name = "ConsoleWrapper"
consoleWrapper.Size = UDim2.new(1, 0, 1, -35)
consoleWrapper.LayoutOrder = 1
consoleWrapper.BackgroundTransparency = 1
consoleWrapper.ClipsDescendants = true
consoleWrapper.Parent = container

local consoleBgImage = Instance.new("ImageLabel")
consoleBgImage.Name = "ConsoleBackgroundImage"
consoleBgImage.Size = UDim2.new(1, 0, 1, 0)
consoleBgImage.BackgroundTransparency = 1
consoleBgImage.ZIndex = 0
consoleBgImage.Visible = false
consoleBgImage.Parent = consoleWrapper

-- Normal Console Frame
local consoleFrame = Instance.new("ScrollingFrame")
consoleFrame.Name = "ConsoleFrame"
consoleFrame.Size = UDim2.new(1, 0, 1, 0)
consoleFrame.BackgroundTransparency = 1
consoleFrame.BorderSizePixel = 0
consoleFrame.ScrollBarThickness = 4
consoleFrame.ScrollBarImageColor3 = toColor3(THEME.Border)
consoleFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
consoleFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
consoleFrame.ZIndex = 1
consoleFrame.Visible = true
consoleFrame.Parent = consoleWrapper
addPadding(consoleFrame, UDim.new(0, 2))

local consoleLayout = Instance.new("UIListLayout")
consoleLayout.SortOrder = Enum.SortOrder.LayoutOrder
consoleLayout.Padding = UDim.new(0, 2)
consoleLayout.Parent = consoleFrame

-- =========================================================
-- Developer Console Split Container (Invisible by Default)
-- =========================================================

local devConsoleContainer = Instance.new("Frame")
devConsoleContainer.Name = "DevConsoleContainer"
devConsoleContainer.Size = UDim2.new(1, 0, 1, 0)
devConsoleContainer.BackgroundTransparency = 1
devConsoleContainer.Visible = false
devConsoleContainer.ZIndex = 1
devConsoleContainer.Parent = consoleWrapper

-- 1. Left Frame: Regular Log (3/4 of space = 75%)
local devConsoleFrame = Instance.new("ScrollingFrame")
devConsoleFrame.Name = "DevConsoleFrame"
devConsoleFrame.Size = UDim2.new(0.75, -5, 1, 0)
devConsoleFrame.Position = UDim2.new(0, 0, 0, 0)
devConsoleFrame.BackgroundTransparency = 1
devConsoleFrame.BorderSizePixel = 0
devConsoleFrame.ScrollBarThickness = 4
devConsoleFrame.ScrollBarImageColor3 = toColor3(THEME.Border)
devConsoleFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
devConsoleFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
devConsoleFrame.Parent = devConsoleContainer
addPadding(devConsoleFrame, UDim.new(0, 2))

local devConsoleLayout = Instance.new("UIListLayout")
devConsoleLayout.SortOrder = Enum.SortOrder.LayoutOrder
devConsoleLayout.Padding = UDim.new(0, 2)
devConsoleLayout.Parent = devConsoleFrame

-- 2. Right Frame: Stats Panel (1/4 of space = 25%)
local statsFrame = Instance.new("ScrollingFrame")
statsFrame.Name = "StatsFrame"
statsFrame.Size = UDim2.new(0.25, 0, 1, 0)
statsFrame.Position = UDim2.new(0.75, 5, 0, 0)
statsFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
statsFrame.BackgroundTransparency = 0.3
statsFrame.BorderSizePixel = 0
statsFrame.ScrollBarThickness = 4
statsFrame.ScrollBarImageColor3 = toColor3(THEME.Accent)
statsFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
statsFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
statsFrame.Parent = devConsoleContainer
addCorners(statsFrame)
addPadding(statsFrame, UDim.new(0, 4))

local statsLayout = Instance.new("UIListLayout")
statsLayout.SortOrder = Enum.SortOrder.LayoutOrder
statsLayout.Padding = UDim.new(0, 4)
statsLayout.Parent = statsFrame

-- Helper function to generate dynamic stat labels
local function createStatLabel(name, parent)
    local lbl = Instance.new("TextLabel")
    lbl.Name = name or "Error"
    lbl.Size = UDim2.new(1, -6, 0, 16) -- Adjusted width for scrollbar offset
    lbl.BackgroundTransparency = 1
    lbl.Font = THEME.ConsoleFont or Enum.Font.Code
    lbl.TextSize = 11
    lbl.TextColor3 = toColor3(THEME.Text)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = parent
    return lbl
end

-- Header & Stat Categories
local titleStats = Instance.new("TextLabel")
titleStats.Size = UDim2.new(1, -6, 0, 18)
titleStats.BackgroundTransparency = 1
titleStats.Font = Enum.Font.GothamBold
titleStats.TextSize = 12
titleStats.TextColor3 = toColor3(THEME.Accent)
titleStats.Text = "-- STATISTICS --"
titleStats.TextXAlignment = Enum.TextXAlignment.Center
titleStats.Parent = statsFrame

local fpsLabel = createStatLabel("FPS: --", statsFrame)
local avgFpsLabel = createStatLabel("Avg FPS: --", statsFrame)
local pingLabel = createStatLabel("Ping: -- ms", statsFrame)
local avgPingLabel = createStatLabel("Avg Ping: -- ms", statsFrame)
local memoryLabel = createStatLabel("Mem: -- MB", statsFrame)

local divider1 = Instance.new("Frame")
divider1.Size = UDim2.new(1, -6, 0, 1)
divider1.BackgroundColor3 = toColor3(THEME.Border)
divider1.BorderSizePixel = 0
divider1.Parent = statsFrame

local serverTitle = createStatLabel("-- SERVER --", statsFrame)
serverTitle.Font = Enum.Font.GothamBold
serverTitle.Text = "Server"
serverTitle.TextColor3 = toColor3(THEME.Accent)

local gameNameLabel = createStatLabel("Game: --", statsFrame)
local gameIdLabel = createStatLabel("Place ID: --", statsFrame)
local playersCountLabel = createStatLabel("Players: --", statsFrame)
local serverTimeLabel = createStatLabel("Time: --", statsFrame)
local timeInGameLabel = createStatLabel("Session: --", statsFrame)
local serverLocLabel = createStatLabel("Server Region: --", statsFrame)

local divider2 = Instance.new("Frame")
divider2.Size = UDim2.new(1, -6, 0, 1)
divider2.BackgroundColor3 = toColor3(THEME.Border)
divider2.BorderSizePixel = 0
divider2.Parent = statsFrame

local playerTitle = createStatLabel("-- PLAYER --", statsFrame)
playerTitle.Font = Enum.Font.GothamBold
playerTitle.Text = "Player"
playerTitle.TextColor3 = toColor3(THEME.Accent)

local teamLabel = createStatLabel("Team: --", statsFrame)
local posLabel = createStatLabel("Pos: --", statsFrame)
local seatedLabel = createStatLabel("Seated: --", statsFrame)
local healthLabel = createStatLabel("Health: --", statsFrame)
local speedLabel = createStatLabel("WalkSpeed: --", statsFrame)
local actualSpeedLabel = createStatLabel("Actual Speed: --", statsFrame)
local jumpLabel = createStatLabel("JumpPower: --", statsFrame)
local stateLabel = createStatLabel("State: --", statsFrame)
local toolLabel = createStatLabel("Tool: --", statsFrame)

local divider3 = Instance.new("Frame")
divider3.Size = UDim2.new(1, -6, 0, 1)
divider3.BackgroundColor3 = toColor3(THEME.Border)
divider3.BorderSizePixel = 0
divider3.Parent = statsFrame

local shellTitle = createStatLabel("-- SHELL --", statsFrame)
shellTitle.Font = Enum.Font.GothamBold
shellTitle.Text = "Shell"
shellTitle.TextColor3 = toColor3(THEME.Accent)

local shellRunningLabel = createStatLabel("Running: --", statsFrame)
local shellDevLabel = createStatLabel("Dev: --", statsFrame)
local shellThemeLabel = createStatLabel("Theme: --", statsFrame)
local shellFuncsLabel = createStatLabel("Functions: --", statsFrame)
local shellBindsLabel = createStatLabel("Keybinds: --", statsFrame)

-- Dynamic Updater Loop for Stats
task.spawn(function()
    local RunService = game:GetService("RunService")
    local Stats = game:GetService("Stats")
    local Players = game:GetService("Players")
    local LocalizationService = game:GetService("LocalizationService")
    local MarketplaceService = game:GetService("MarketplaceService")
    local localPlayer = Players.LocalPlayer

    local frameCount = 0
    local lastTime = os.clock()
    local currentFps = 60
    local sessionStartTime = os.clock()

    -- Running Averages Tracking
    local fpsHistory = {}
    local pingHistory = {}
    local maxHistorySamples = 120 -- ~30 seconds of history at 0.25s intervals

    -- 5-second baseline tracking variables
    local historyTimer = os.clock()
    local baselineFps = 60
    local baselinePing = 0
    local baselineMem = 0

    -- Asynchronously fetch region code and game title
    local serverCountry = "Unknown"
    local gameName = "Unknown"

    task.spawn(function()
        local success, result = pcall(function()
            return LocalizationService:GetCountryRegionForPlayerAsync(localPlayer)
        end)
        if success and result then
            serverCountry = result
        end
    end)

    task.spawn(function()
        local success, info = pcall(function()
            return MarketplaceService:GetProductInfo(game.PlaceId)
        end)
        if success and info and info.Name then
            gameName = info.Name
        end
    end)

    -- Smooth FPS Counter
    RunService.RenderStepped:Connect(function()
        frameCount = frameCount + 1
        local now = os.clock()
        if now - lastTime >= 1 then
            currentFps = math.floor(frameCount / (now - lastTime))
            frameCount = 0
            lastTime = now
        end
    end)

    local lastPosition = nil
    local lastPosTime = os.clock()

    while screenGui.Parent do
        if devConsoleContainer.Visible then
            local now = os.clock()

            -- PC / Client Stats Calculation
            local pingItem = Stats.Network.ServerStatsItem:FindFirstChild("Data Ping")
            local currentPing = pingItem and math.floor(pingItem:GetValue()) or 0
            local currentMem = math.floor(Stats:GetTotalMemoryUsageMb())

            -- Rolling Average Calculations
            table.insert(fpsHistory, currentFps)
            table.insert(pingHistory, currentPing)
            if #fpsHistory > maxHistorySamples then table.remove(fpsHistory, 1) end
            if #pingHistory > maxHistorySamples then table.remove(pingHistory, 1) end

            local sumFps, sumPing = 0, 0
            for _, v in ipairs(fpsHistory) do sumFps = sumFps + v end
            for _, v in ipairs(pingHistory) do sumPing = sumPing + v end
            local avgFps = #fpsHistory > 0 and math.floor(sumFps / #fpsHistory) or currentFps
            local avgPing = #pingHistory > 0 and math.floor(sumPing / #pingHistory) or currentPing

            -- Update baseline metrics every 5 seconds
            if now - historyTimer >= 5 then
                baselineFps = currentFps
                baselinePing = currentPing
                baselineMem = currentMem
                historyTimer = now
            end

            -- Format +/- comparison differences
            local diffFps = currentFps - baselineFps
            local diffPing = currentPing - baselinePing
            local diffMem = currentMem - baselineMem

            local strFpsDiff = diffFps >= 0 and string.format("(+%d)", diffFps) or string.format("(%d)", diffFps)
            local strPingDiff = diffPing >= 0 and string.format("(+%d)", diffPing) or string.format("(%d)", diffPing)
            local strMemDiff = diffMem >= 0 and string.format("(+%d)", diffMem) or string.format("(%d)", diffMem)

            -- Assign Client Stats
            fpsLabel.Text = string.format("FPS: %d %s", currentFps, strFpsDiff)
            avgFpsLabel.Text = string.format("Avg FPS: %d", avgFps)
            pingLabel.Text = string.format("Ping: %d ms %s", currentPing, strPingDiff)
            avgPingLabel.Text = string.format("Avg Ping: %d ms", avgPing)
            memoryLabel.Text = string.format("Mem: %d MB %s", currentMem, strMemDiff)

            -- Server Stats
            gameNameLabel.Text = string.format("Game: %s", gameName)
            gameIdLabel.Text = string.format("Place ID: %d", game.PlaceId)
            playersCountLabel.Text = string.format("Players: %d", #Players:GetPlayers())
            serverTimeLabel.Text = string.format("Time: %s", os.date("%H:%M:%S"))

            local elapsedSecs = math.floor(now - sessionStartTime)
            local hours = math.floor(elapsedSecs / 3600)
            local mins = math.floor((elapsedSecs % 3600) / 60)
            local secs = elapsedSecs % 60
            timeInGameLabel.Text = string.format("Session: %02d:%02d:%02d", hours, mins, secs)

            serverLocLabel.Text = string.format("Server Region: %s", serverCountry)

            -- Player & Team Stats
            teamLabel.Text = string.format("Team: %s", localPlayer and localPlayer.Team and localPlayer.Team.Name or "None")

            -- Character & Movement Checks
            local char = localPlayer and localPlayer.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")

            if char then
                local pivot = char:GetPivot().Position
                posLabel.Text = string.format("Pos: %d, %d, %d", math.round(pivot.X), math.round(pivot.Y), math.round(pivot.Z))

                -- Actual Speed Calculation (Studs per second)
                if lastPosition then
                    local dt = now - lastPosTime
                    if dt > 0 then
                        local distance = (pivot - lastPosition).Magnitude
                        actualSpeedLabel.Text = string.format("Actual Speed: %.1f", distance / dt)
                    end
                else
                    actualSpeedLabel.Text = "Actual Speed: 0.0"
                end
                lastPosition = pivot
                lastPosTime = now

                local isSeated = hum and hum.Sit or false
                seatedLabel.Text = string.format("Seated: %s", tostring(isSeated))
            else
                posLabel.Text = "Pos: N/A"
                actualSpeedLabel.Text = "Actual Speed: N/A"
                seatedLabel.Text = "Seated: N/A"
                lastPosition = nil
            end

            -- Humanoid Stats
            if hum and hum.Parent then
                healthLabel.Text = string.format("HP: %d/%d", math.floor(hum.Health), math.floor(hum.MaxHealth))
                speedLabel.Text = string.format("WalkSpeed: %.1f", hum.WalkSpeed)
                jumpLabel.Text = string.format("Jump: %.1f", hum.JumpPower)
                stateLabel.Text = string.format("State: %s", hum:GetState().Name)

                local currentTool = char:FindFirstChildWhichIsA("Tool")
                toolLabel.Text = string.format("Tool: %s", currentTool and currentTool.Name or "None")
            else
                healthLabel.Text = "HP: N/A"
                speedLabel.Text = "WalkSpeed: N/A"
                jumpLabel.Text = "Jump: N/A"
                stateLabel.Text = "State: N/A"
                toolLabel.Text = "Tool: N/A"
            end

            -- Shell Global Stats
            shellRunningLabel.Text = string.format("Running: %s", tostring(_G.ShellRunning or false))
            shellDevLabel.Text = string.format("Dev: %s", tostring(_G.ShellDev or false))
            shellThemeLabel.Text = string.format("Theme: %s", tostring(_G.ShellTheme or "Default"))

            local funcCount = type(_G.ShellFunctions) == "table" and #_G.ShellFunctions or 0
            shellFuncsLabel.Text = string.format("Functions: %d", funcCount)

            local bindCount = type(_G.ShellKeybinds) == "table" and #_G.ShellKeybinds or 0
            shellBindsLabel.Text = string.format("Keybinds: %d", bindCount)
        end
        task.wait(0.25)
    end
end)

-- Checkbox Toggle Logic
local devConsoleEnabled = false
devCheckboxButton.MouseButton1Click:Connect(function()
    if not _G.ShellDev then return end
    devConsoleEnabled = not devConsoleEnabled
    
    if devConsoleEnabled then
        devCheckboxButton.Text = "[X] Enable Developer Console"
        consoleFrame.Visible = false
        devConsoleContainer.Visible = true
    else
        devCheckboxButton.Text = "[ ] Enable Developer Console"
        devConsoleContainer.Visible = false
        consoleFrame.Visible = true
    end
end)

-- =========================================================
-- Dynamic Window Edge Resizing System
-- =========================================================

local function setupEdgeResizing(targetFrame, minSize)
    minSize = minSize or Vector2.new(300, 150)
    local HANDLE_THICKNESS = 6
    local activeResizeInput, resizing, activeDir
    local startFrameSize, startFramePos, startMousePos

    local handles = {
        Left   = {Size = UDim2.new(0, HANDLE_THICKNESS, 1, -HANDLE_THICKNESS*2), Pos = UDim2.new(0, -HANDLE_THICKNESS/2, 0, HANDLE_THICKNESS)},
        Right  = {Size = UDim2.new(0, HANDLE_THICKNESS, 1, -HANDLE_THICKNESS*2), Pos = UDim2.new(1, -HANDLE_THICKNESS/2, 0, HANDLE_THICKNESS)},
        Top    = {Size = UDim2.new(1, -HANDLE_THICKNESS*2, 0, HANDLE_THICKNESS), Pos = UDim2.new(0, HANDLE_THICKNESS, 0, -HANDLE_THICKNESS/2)},
        Bottom = {Size = UDim2.new(1, -HANDLE_THICKNESS*2, 0, HANDLE_THICKNESS), Pos = UDim2.new(0, HANDLE_THICKNESS, 1, -HANDLE_THICKNESS/2)},
        
        TopLeft     = {Size = UDim2.new(0, HANDLE_THICKNESS*2, 0, HANDLE_THICKNESS*2), Pos = UDim2.new(0, -HANDLE_THICKNESS/2, 0, -HANDLE_THICKNESS/2)},
        TopRight    = {Size = UDim2.new(0, HANDLE_THICKNESS*2, 0, HANDLE_THICKNESS*2), Pos = UDim2.new(1, -HANDLE_THICKNESS*1.5, 0, -HANDLE_THICKNESS/2)},
        BottomLeft  = {Size = UDim2.new(0, HANDLE_THICKNESS*2, 0, HANDLE_THICKNESS*2), Pos = UDim2.new(0, -HANDLE_THICKNESS/2, 1, -HANDLE_THICKNESS*1.5)},
        BottomRight = {Size = UDim2.new(0, HANDLE_THICKNESS*2, 0, HANDLE_THICKNESS*2), Pos = UDim2.new(1, -HANDLE_THICKNESS*1.5, 1, -HANDLE_THICKNESS*1.5)},
    }

    local handleFolder = targetFrame:FindFirstChild("ResizeHandles")
    if handleFolder then handleFolder:Destroy() end
    
    handleFolder = Instance.new("Folder")
    handleFolder.Name = "ResizeHandles"
    handleFolder.Parent = targetFrame

    for dir, config in pairs(handles) do
        local handle = Instance.new("TextButton")
        handle.Name = dir .. "Handle"
        handle.Size = config.Size
        handle.Position = config.Pos
        handle.BackgroundTransparency = 1
        handle.Text = ""
        handle.ZIndex = 20
        handle.Parent = handleFolder

        handle.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                resizing = true
                activeDir = dir
                activeResizeInput = input
                startMousePos = input.Position
                startFrameSize = targetFrame.AbsoluteSize
                startFramePos = targetFrame.Position

                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        resizing = false
                    end
                end)
            end
        end)
    end

    UserInputService.InputChanged:Connect(function(input)
        if resizing and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - startMousePos
            local newSizeX, newSizeY = startFrameSize.X, startFrameSize.Y
            local newPosX, newPosY = startFramePos.X.Offset, startFramePos.Y.Offset

            if activeDir:find("Right") then
                newSizeX = math.max(minSize.X, startFrameSize.X + delta.X)
            elseif activeDir:find("Left") then
                local possibleWidth = startFrameSize.X - delta.X
                if possibleWidth >= minSize.X then
                    newSizeX = possibleWidth
                    newPosX = startFramePos.X.Offset + delta.X
                else
                    newSizeX = minSize.X
                    newPosX = startFramePos.X.Offset + (startFrameSize.X - minSize.X)
                end
            end

            if activeDir:find("Bottom") then
                newSizeY = math.max(minSize.Y, startFrameSize.Y + delta.Y)
            elseif activeDir:find("Top") then
                local possibleHeight = startFrameSize.Y - delta.Y
                if possibleHeight >= minSize.Y then
                    newSizeY = possibleHeight
                    newPosY = startFramePos.Y.Offset + delta.Y
                else
                    newSizeY = minSize.Y
                    newPosY = startFramePos.Y.Offset + (startFrameSize.Y - minSize.Y)
                end
            end

            targetFrame.Size = UDim2.new(0, newSizeX, 0, newSizeY)
            targetFrame.Position = UDim2.new(startFramePos.X.Scale, newPosX, startFramePos.Y.Scale, newPosY)
        end
    end)
end

setupEdgeResizing(mainFrame, Vector2.new(350, 200))

-- Universal Logging Function
local function shellLog(text, logTypeOrColor)
    local logColor
    local isDeveloperLog = false

    if typeof(logTypeOrColor) == "Color3" then
        logColor = logTypeOrColor
    elseif type(logTypeOrColor) == "string" then
        local lType = logTypeOrColor:lower()
        if lType == "developer" then
            isDeveloperLog = true
            logColor = THEME.Accent
        elseif lType == "error" then
            logColor = THEME.Console_Error
        elseif lType == "warn" or lType == "warning" then
            logColor = THEME.Console_Warn
        elseif lType == "success" then
            logColor = THEME.Console_Success
        elseif THEME[logTypeOrColor] then
            logColor = THEME[logTypeOrColor]
        else
            logColor = THEME.Console_Info
        end
    else
        logColor = THEME.Console_Info
    end

    local timeStamp = os.date("%H:%M:%S")
    local fullText = string.format("[%s] %s", timeStamp, tostring(text))

    local targetConsole = isDeveloperLog and devConsoleFrame or consoleFrame

    local logEntry = Instance.new("TextBox")
    logEntry.Name = "LogEntry"
    logEntry.BackgroundTransparency = 1
    logEntry.Size = UDim2.new(1, -10, 0, 0)
    logEntry.AutomaticSize = Enum.AutomaticSize.Y
    logEntry.Text = fullText
    logEntry.TextColor3 = toColor3(logColor, THEME.Text)
    logEntry.Font = THEME.ConsoleFont or Enum.Font.Code
    logEntry.TextSize = THEME.ConsoleFontSize or 14
    logEntry.TextWrapped = true
    logEntry.TextXAlignment = Enum.TextXAlignment.Left
    logEntry.TextEditable = false
    logEntry.ClearTextOnFocus = false
    logEntry.Parent = targetConsole

    task.defer(function()
        targetConsole.CanvasPosition = Vector2.new(0, 100000)
    end)
end

_G.ShellLog = shellLog

local function devlog(msg)
    if _G.ShellLog then
    _G.ShellLog("[Dev]: "..msg, "developer")
    end
end

shellLog("Shell UI Framework Loaded.", THEME.Accent)
shellLog("Press F2 or ' to toggle/focus visibility.", THEME.Placeholder)

-- Command Bar Container
local commandBarContainer = Instance.new("Frame")
commandBarContainer.Name = "CommandBarContainer"
commandBarContainer.Size = UDim2.new(1, 0, 0, 30)
commandBarContainer.LayoutOrder = 2
commandBarContainer.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
commandBarContainer.BorderSizePixel = 0
commandBarContainer.Parent = container
addCorners(commandBarContainer)

local commandBar = Instance.new("TextBox")
commandBar.Name = "CommandBar"
commandBar.Size = UDim2.new(1, 0, 1, 0)
commandBar.BackgroundTransparency = 1
commandBar.TextColor3 = toColor3(THEME.Text)
commandBar.PlaceholderColor3 = toColor3(THEME.Placeholder)
commandBar.PlaceholderText = "Type a command..."
commandBar.Font = THEME.CommandFont or Enum.Font.Code
commandBar.TextSize = THEME.CommandFontSize or 14
commandBar.TextXAlignment = Enum.TextXAlignment.Left
commandBar.Text = ""
commandBar.ClearTextOnFocus = false
commandBar.Parent = commandBarContainer
addPadding(commandBar, UDim.new(0, 2))

-- Suggestion Overlay
local suggestionFrame = Instance.new("Frame")
suggestionFrame.Name = "SuggestionFrame"
suggestionFrame.Size = UDim2.new(0, 300, 0, 150)
suggestionFrame.Position = UDim2.new(0, 0, 0, -155)
suggestionFrame.BackgroundColor3 = toColor3(THEME.Background)
suggestionFrame.Visible = false
suggestionFrame.ZIndex = 10
suggestionFrame.Parent = commandBarContainer
addCorners(suggestionFrame)

local suggStroke = Instance.new("UIStroke")
suggStroke.Color = toColor3(THEME.Border)
suggStroke.Parent = suggestionFrame

local suggestionList = Instance.new("ScrollingFrame")
suggestionList.Size = UDim2.new(1, 0, 1, 0)
suggestionList.BackgroundTransparency = 1
suggestionList.BorderSizePixel = 0
suggestionList.ScrollBarThickness = 2
suggestionList.CanvasSize = UDim2.new(0, 0, 0, 0)
suggestionList.AutomaticCanvasSize = Enum.AutomaticSize.Y
suggestionList.Parent = suggestionFrame
addPadding(suggestionList, UDim.new(0, 2))

local suggestionLayout = Instance.new("UIListLayout")
suggestionLayout.SortOrder = Enum.SortOrder.LayoutOrder
suggestionLayout.Padding = UDim.new(0, 1)
suggestionLayout.Parent = suggestionList

-- Logic Variables
local commands = {}
local matches = {}
local matchIndex = 1
local isMinimized = false
local lastCommand = ""

local function getTableCount(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

_G.ShellUIUpdate = function(newCommands)
    commands = newCommands
    shellLog("Command map synchronized. (" .. getTableCount(commands) .. " entries)", THEME.Accent)
end

-- Scrolling & Suggestion Visuals
local function scrollToMatch(index)
    local fontSize = THEME.SuggestionFontSize or 14
    local itemHeight = fontSize + 4 + 1
    local targetYMin = (index - 1) * itemHeight
    local targetYMax = targetYMin + itemHeight

    local currentCanvasY = suggestionList.CanvasPosition.Y
    local visibleHeight = suggestionList.AbsoluteWindowSize.Y

    if targetYMin < currentCanvasY then
        suggestionList.CanvasPosition = Vector2.new(0, targetYMin)
    elseif targetYMax > (currentCanvasY + visibleHeight) then
        suggestionList.CanvasPosition = Vector2.new(0, targetYMax - visibleHeight)
    end
end

local function updateSelectionVisual()
    local labels = {}
    for _, child in ipairs(suggestionList:GetChildren()) do
        if child:IsA("TextButton") then
            table.insert(labels, child)
        end
    end

    for i, button in ipairs(labels) do
        local targetColor = (i == matchIndex) and THEME.Accent or THEME.SuggestionTextColor
        button.TextColor3 = toColor3(targetColor, THEME.Text)
    end

    scrollToMatch(matchIndex)
end

local function applySuggestion(value)
    commandBar.Text = value
    task.defer(function()
        commandBar.CursorPosition = #value + 1
        commandBar:CaptureFocus()
    end)
    suggestionFrame.Visible = false
end

local function updateSuggestions()
    local fullText = commandBar.Text
    matches = {}
    matchIndex = 1

    for _, child in ipairs(suggestionList:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end

    if fullText == "" then
        suggestionFrame.Visible = false
        return
    end

    local parts = string.split(fullText, " ")
    local cmdNameInput = parts[1]:lower()

    if #parts <= 1 then
        for name, cmd in pairs(commands) do
            if name:sub(1, #cmdNameInput) == cmdNameInput and (cmd.Category ~= "Hidden") then
                table.insert(matches, {
                    Type = "Command",
                    Name = cmd.Name,
                    Display = string.format("%s (%s)", cmd.Name, table.concat(cmd.Arguments or {}, ", ")),
                    Value = cmd.Name .. " "
                })
            end
        end
        table.sort(matches, function(a, b) return a.Name < b.Name end)
    else
        local activeCmd = commands[cmdNameInput]
        if activeCmd and activeCmd.Arguments then
            local firstArg = activeCmd.Arguments[1]
            local argInput = parts[2]:lower()
            
            if firstArg == "Player" then
                for _, player in ipairs(Players:GetPlayers()) do
                    if player.Name:lower():sub(1, #argInput) == argInput then
                        table.insert(matches, {
                            Type = "Player",
                            Name = player.Name,
                            Display = player.Name,
                            Value = cmdNameInput .. " " .. player.Name
                        })
                    end
                end
                table.sort(matches, function(a, b) return a.Name < b.Name end)
            elseif firstArg == "Theme" or firstArg == "ThemeName" then
                local availableThemes = getAvailableThemes()
                for _, themeName in ipairs(availableThemes) do
                    if themeName:lower():sub(1, #argInput) == argInput then
                        table.insert(matches, {
                            Type = "Theme",
                            Name = themeName,
                            Display = themeName,
                            Value = cmdNameInput .. " " .. themeName
                        })
                    end
                end
                table.sort(matches, function(a, b) return a.Name < b.Name end)
            elseif firstArg == "FilePath" or firstArg == "File" or firstArg == "Path" then
                if typeof(listfiles) == "function" then
                    -- Helper function to recursively gather all descendant paths
                    local function getAllDescendants(dir)
                        local results = {}
                        local success, files = pcall(function() return listfiles(dir) end)
                        
                        if success and files then
                            for _, rawPath in ipairs(files) do
                                local normalizedPath = rawPath:gsub("\\", "/")
                                table.insert(results, normalizedPath)
                                
                                -- Check if current item is a folder to scan its contents too
                                local isDir = false
                                if typeof(isfolder) == "function" then
                                    pcall(function() isDir = isfolder(rawPath) end)
                                end

                                if isDir then
                                    local subResults = getAllDescendants(normalizedPath)
                                    for _, subPath in ipairs(subResults) do
                                        table.insert(results, subPath)
                                    end
                                end
                            end
                        end
                        return results
                    end

                    local allPaths = getAllDescendants("Shell")

                    for _, fullPath in ipairs(allPaths) do
                        -- Strip leading "Shell/" or "Shell" to get relative descendant paths
                        local relativePath = fullPath:gsub("^Shell/", ""):gsub("^Shell", "")
                        
                        if relativePath ~= "" and relativePath:lower():sub(1, #argInput) == argInput then
                            table.insert(matches, {
                                Type = "FilePath",
                                Name = relativePath,
                                Display = relativePath,
                                Value = cmdNameInput .. " " .. relativePath
                            })
                        end
                    end
                    
                    table.sort(matches, function(a, b) return a.Name < b.Name end)
                end
            end
        end
    end

    if #matches == 0 then
        suggestionFrame.Visible = false
    else
        suggestionFrame.Visible = true
        
        local fontSize = THEME.SuggestionFontSize or 14
        local itemHeight = fontSize + 4
        local count = math.min(#matches, 5)
        local frameHeight = (count * itemHeight) + 10
        
        suggestionFrame.Size = UDim2.new(0, 300, 0, frameHeight)
        suggestionFrame.Position = UDim2.new(0, 0, 0, -frameHeight - 5)

        for i, match in ipairs(matches) do
            local sugButton = Instance.new("TextButton")
            sugButton.Name = "Sug_" .. match.Name
            sugButton.Size = UDim2.new(1, -5, 0, itemHeight)
            sugButton.BackgroundTransparency = 1
            sugButton.Text = "  " .. match.Display
            
            local activeColor = (i == 1) and THEME.Accent or THEME.SuggestionTextColor
            sugButton.TextColor3 = toColor3(activeColor, THEME.Text)
            sugButton.Font = THEME.CommandFont or Enum.Font.Code
            sugButton.TextSize = fontSize
            sugButton.TextXAlignment = Enum.TextXAlignment.Left
            sugButton.Parent = suggestionList

            sugButton.MouseButton1Click:Connect(function()
                applySuggestion(match.Value)
            end)
        end
    end
end

-- Interactions
local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

minButton.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    local handleFolder = mainFrame:FindFirstChild("ResizeHandles")

    if isMinimized then
        suggestionFrame.Visible = false
        minButton.Text = "+"
        if handleFolder then handleFolder.Parent = nil end
        
        TweenService:Create(mainFrame, tweenInfo, {
            Size = UDim2.new(0, mainFrame.AbsoluteSize.X, 0, 75)
        }):Play()

        TweenService:Create(consoleWrapper, tweenInfo, {
            Size = UDim2.new(1, 0, 0, 0)
        }):Play()
    else
        minButton.Text = "-"
        if handleFolder then handleFolder.Parent = mainFrame end
        
        TweenService:Create(mainFrame, tweenInfo, {
            Size = UDim2.new(0, THEME.FrameSize.X, 0, THEME.FrameSize.Y)
        }):Play()

        TweenService:Create(consoleWrapper, tweenInfo, {
            Size = UDim2.new(1, 0, 1, -35)
        }):Play()
    end
end)

-- Window Dragging
local dragging, dragInput, dragStart, startPos

titleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = mainFrame.Position

        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

titleBar.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

-- Hotkey Management
UserInputService.InputBegan:Connect(function(input, processed)
    if input.KeyCode == Enum.KeyCode.F2 then
        mainFrame.Visible = not mainFrame.Visible
        if mainFrame.Visible then
            commandBar:CaptureFocus()
        else
            commandBar:ReleaseFocus()
            suggestionFrame.Visible = false
        end
    elseif input.KeyCode == Enum.KeyCode.Quote and not processed then
        if not mainFrame.Visible then
            mainFrame.Visible = true
        end
        task.defer(function()
            commandBar.Text = ""
            commandBar:CaptureFocus()
        end)
    end
end)

local previousTextLen = 0
commandBar:GetPropertyChangedSignal("Text"):Connect(function()
    updateSuggestions()
    
    -- Sound Logic for typing
    local currentLen = #commandBar.Text
    if currentLen > previousTextLen then
        playThemeAudio(typingSoundObj, THEME.TypingSound)
    end
    previousTextLen = currentLen
end)

UserInputService.InputBegan:Connect(function(input, processed)
    if not commandBar:IsFocused() then return end

    if input.KeyCode == Enum.KeyCode.Tab then
        if suggestionFrame.Visible and #matches > 0 and matches[matchIndex] then
            applySuggestion(matches[matchIndex].Value)
        end
    elseif suggestionFrame.Visible then
        if input.KeyCode == Enum.KeyCode.Up then
            if #matches > 1 then
                matchIndex = matchIndex - 1
                if matchIndex < 1 then matchIndex = #matches end
                updateSelectionVisual()
            end
        elseif input.KeyCode == Enum.KeyCode.Down then
            if #matches > 1 then
                matchIndex = matchIndex + 1
                if matchIndex > #matches then matchIndex = 1 end
                updateSelectionVisual()
            end
        end
    else
        if input.KeyCode == Enum.KeyCode.Up then
            if commandBar.Text == "" and lastCommand ~= "" then
                applySuggestion(lastCommand)
            end
        elseif input.KeyCode == Enum.KeyCode.Down then
            if commandBar.Text == lastCommand and lastCommand ~= "" then
                commandBar.Text = ""
            end
        end
    end
end)

commandBar:GetPropertyChangedSignal("Text"):Connect(function()
    if string.find(commandBar.Text, "\t") or string.find(commandBar.Text, "'") then
        commandBar.Text = string.gsub(string.gsub(commandBar.Text, "\t", ""), "'", "")
    end
end)

_G.ShellTheme = _G.ShellTheme or "default"

-- Dynamic Theme Applicator
local function applyThemeToUI()
    mainFrame.BackgroundColor3 = toColor3(THEME.Background)
    mainFrame.Size = UDim2.new(0, THEME.FrameSize.X, 0, THEME.FrameSize.Y)
    mainStroke.Color = toColor3(THEME.Border)
    
    titleBar.BackgroundColor3 = toColor3(THEME.Border)
    
    -- Dynamic Custom Title Handling
    if THEME.CustomTitle and THEME.CustomTitle ~= "" then
        titleText.Text = THEME.CustomTitle
    else
        titleText.Text = "Shell Console"
    end
    
    titleText.TextColor3 = toColor3(THEME.Text)
    minButton.TextColor3 = toColor3(THEME.Text)
    
    local bg = toColor3(THEME.Background)
    commandBarContainer.BackgroundColor3 = Color3.fromRGB(
        math.clamp(math.floor(bg.R * 255) + 5, 0, 255),
        math.clamp(math.floor(bg.G * 255) + 5, 0, 255),
        math.clamp(math.floor(bg.B * 255) + 5, 0, 255)
    )
    commandBar.TextColor3 = toColor3(THEME.Text)
    commandBar.PlaceholderColor3 = toColor3(THEME.Placeholder)
    commandBar.Font = THEME.CommandFont or Enum.Font.Code
    commandBar.TextSize = THEME.CommandFontSize or 14
    
    suggestionFrame.BackgroundColor3 = toColor3(THEME.Background)
    suggStroke.Color = toColor3(THEME.Border)
    
    -- Dynamic Background Image Application
    if THEME.BackgroundImage and THEME.BackgroundImage ~= "" then
        consoleBgImage.Image = formatImageAsset(THEME.BackgroundImage)
        consoleBgImage.ImageTransparency = THEME.BackgroundImageTransparency or 0
        consoleBgImage.ScaleType = THEME.BackgroundImageScaleType or Enum.ScaleType.Stretch
        if THEME.BackgroundImageTileSize and typeof(THEME.BackgroundImageTileSize) == "UDim2" then
            consoleBgImage.TileSize = THEME.BackgroundImageTileSize
        end
        consoleBgImage.Visible = true
    else
        consoleBgImage.Visible = false
    end

    local framesToCorner = {mainFrame, titleBar, commandBarContainer, suggestionFrame}
    for _, obj in ipairs(framesToCorner) do
        local existingCorner = obj:FindFirstChildOfClass("UICorner")
        if THEME.UseUICorner then
            if not existingCorner then
                addCorners(obj)
            end
        else
            if existingCorner then
                existingCorner:Destroy()
            end
        end
    end

    local targetConsoles = {consoleFrame, devConsoleFrame}
    for _, targetConsole in ipairs(targetConsoles) do
        for _, logEntry in ipairs(targetConsole:GetChildren()) do
            if logEntry:IsA("TextBox") then
                logEntry.Font = THEME.ConsoleFont or Enum.Font.Code
                logEntry.TextSize = THEME.ConsoleFontSize or 14
            end
        end
    end
end

applyThemeToUI()

local function selectTheme(themeName)
    local filePath = string.format("Shell/Assets/Themes/%s.csv", tostring(themeName))
    
    if isfile and not isfile(filePath) then
        shellLog("Theme file not found: " .. filePath, THEME.Console_Error)
        return false
    end

    local success, err = pcall(function()
        loadThemeFromCSV(filePath)
    end)

    if success then
        _G.ShellTheme = themeName
        applyThemeToUI()

        if writefile and readfile and isfile and isfile(filePath) then
            pcall(function()
                writefile(DEFAULT_THEME_PATH, readfile(filePath))
            end)
        end

        shellLog("Successfully loaded theme: " .. themeName, THEME.Accent)
        return true
    else
        shellLog("Failed to load theme '" .. themeName .. "': " .. tostring(err), THEME.Console_Error)
        return false
    end
end

_G.SelectTheme = selectTheme

_G.ShellClearConsole = function()
    local targetConsole = devConsoleEnabled and devConsoleFrame or consoleFrame
    for _, child in ipairs(targetConsole:GetChildren()) do
        if child:IsA("TextBox") then
            child:Destroy()
        end
    end
    targetConsole.CanvasPosition = Vector2.new(0, 0)
end

-- Command Dispatcher
commandBar.FocusLost:Connect(function(enterPressed)
    suggestionFrame.Visible = false
    
    if enterPressed then
        playThemeAudio(enterSoundObj, THEME.EnterSound)
        
        local fullText = commandBar.Text
        commandBar.Text = ""
        
        if fullText ~= "" then
            lastCommand = fullText
        end

        local args = string.split(fullText, " ")
        local cmdName = table.remove(args, 1)
        if not cmdName then devlog("ui.lua -- expected cmdname, got nil or error.") return end
        cmdName = cmdName:lower()
        
        if commands[cmdName] then
            shellLog("> " .. fullText, THEME.Text)
            task.spawn(function()
                local success, result = pcall(commands[cmdName].Function, unpack(args))
                if not success then
                    shellLog("Error: " .. tostring(result), THEME.Console_Error)
                elseif result then
                    shellLog("Return: " .. tostring(result), THEME.Console_Success)
                end
            end)
        else
            shellLog("Unknown command: " .. tostring(cmdName), THEME.Console_Error)
        end
    end
end)