local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local HttpService = game:GetService("HttpService")
local LocalizationService = game:GetService("LocalizationService")
local MarketplaceService = game:GetService("MarketplaceService")

local localPlayer = Players.LocalPlayer

if _G.ShellUI then _G.ShellUI:Destroy() end

-- =========================================================
-- Constants & Theme State
-- =========================================================
local DEFAULT_TEXT_COLOR = Color3.fromRGB(220, 220, 220)
local DEFAULT_THEME_PATH = "Shell/Assets/Themes/default.csv"
local SHELL_THEME_PATH = "Shell/Assets/Themes/shell.csv"
local LOG_PATH = "Shell/Core/log.txt"

local THEME = {
	Background = Color3.fromRGB(25, 25, 25),
	Border = Color3.fromRGB(45, 45, 45),
	Text = DEFAULT_TEXT_COLOR,
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
	SuggestionTextColor = DEFAULT_TEXT_COLOR,
	SuggestionFontSize = 14,
	FrameSize = Vector2.new(550, 400),
	UseUICorner = false,
	CustomTitle = "",
	BackgroundImage = "",
	BackgroundImageTransparency = 0.5,
	BackgroundImageScaleType = Enum.ScaleType.Stretch,
	BackgroundImageTileSize = UDim2.new(0, 32, 0, 32),
	TypingSound = "",
	EnterSound = "",
}

-- =========================================================
-- Helpers & Builders
-- =========================================================
local function cleanStr(str)
	if type(str) ~= "string" then return "" end
	return str:gsub('\239\187\191', ''):gsub('"', ''):gsub("[%c]", ""):match("^%s*(.-)%s*$") or ""
end

local function parseColor3(val)
	if typeof(val) == "Color3" then return val end
	local clean = cleanStr(val)
	local r, g, b = clean:match("(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
	if r and g and b then return Color3.fromRGB(tonumber(r), tonumber(g), tonumber(b)) end
	local cleanHex = clean:gsub("#", "")
	if #cleanHex == 6 and tonumber(cleanHex, 16) then return Color3.fromHex(cleanHex) end
	return nil
end

local function toColor3(val, fallback)
	return parseColor3(val) or (typeof(fallback) == "Color3" and fallback) or DEFAULT_TEXT_COLOR
end

local function autoParseValue(key, val)
	local lower = val:lower()
	if lower == "true" then return true end
	if lower == "false" then return false end
	if tonumber(val) then return tonumber(val) end
	
	local parsedColor = parseColor3(val)
	if parsedColor then return parsedColor end

	local clean = cleanStr(val)
	local x, y = clean:match("(%d+)%s*,%s*(%d+)")
	if x and y then
		local vec = Vector2.new(tonumber(x), tonumber(y))
		return (key:find("TileSize") or key:find("UDim2")) and UDim2.new(0, vec.X, 0, vec.Y) or vec
	end

	if key:find("Font") or key:find("ScaleType") then
		local enumType = key:find("Font") and Enum.Font or Enum.ScaleType
		local ok, enumVal = pcall(function() return enumType[val] end)
		if ok and enumVal then return enumVal end
	end

	return val
end

local function formatImageAsset(pathOrId)
	if not pathOrId or pathOrId == "" then return "" end
	if isfile and isfile(pathOrId) and getcustomasset then
		local ok, customAsset = pcall(getcustomasset, pathOrId)
		if ok then return customAsset end
	end
	if pathOrId:find("rbxassetid://") or pathOrId:find("http") then return pathOrId end
	return tonumber(pathOrId) and ("rbxassetid://" .. pathOrId) or pathOrId
end

local function applyCorners(parent, radius)
	if not THEME.UseUICorner then
		local existing = parent:FindFirstChildOfClass("UICorner")
		if existing then existing:Destroy() end
		return nil
	end
	local corner = parent:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	corner.CornerRadius = radius or UDim.new(0, 4)
	corner.Parent = parent
	return corner
end

local function applyPadding(parent, top, bot, left, right)
	local pad = parent:FindFirstChildOfClass("UIPadding") or Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, top or 5)
	pad.PaddingBottom = UDim.new(0, bot or 5)
	pad.PaddingLeft = UDim.new(0, left or 8)
	pad.PaddingRight = UDim.new(0, right or 8)
	pad.Parent = parent
	return pad
end

local function createUIElement(className, properties)
	local inst = Instance.new(className)
	for k, v in pairs(properties) do
		inst[k] = v
	end
	return inst
end

-- Async Fetcher for GitHub Commits
local commitCache = {}
local function fetchLatestCommit(filePath)
	if commitCache[filePath] then return commitCache[filePath] end
	
	-- Check if the file exists locally on the user's PC
	if isfile and isfile(filePath) then
		commitCache[filePath] = { Date = "N/A (Local)", Message = "N/A (Local)" }
		return commitCache[filePath]
	end

	local url = string.format("https://api.github.com/repos/generic-goose/Shell/commits?path=%s&page=1&per_page=1", filePath)
	local requestFunc = (syn and syn.request) or (http and http.request) or request or http_request
	
	local dateStr, msgStr = "Error", "Fetch Failed"

	if requestFunc then
		local ok, response = pcall(requestFunc, { Url = url, Method = "GET" })
		if ok and response and response.Body then
			local parseOk, data = pcall(function() return HttpService:JSONDecode(response.Body) end)
			if parseOk and type(data) == "table" and data[1] and data[1].commit then
				local commit = data[1].commit
				local rawDate = commit.committer and commit.committer.date or commit.author.date or ""
				dateStr = rawDate:match("^(%d%d%d%d%-%d%d%-%d%d)") or "Unknown"
				
				local fullMsg = commit.message or "No Message"
				msgStr = fullMsg:split("\n")[1] -- First line of commit msg
				if #msgStr > 25 then msgStr = msgStr:sub(1, 22) .. "..." end
			end
		end
	else
		dateStr, msgStr = "N/A", "HttpReq Unavailable"
	end

	commitCache[filePath] = { Date = dateStr, Message = msgStr }
	return commitCache[filePath]
end

-- =========================================================
-- Theme Parsing Logic
-- =========================================================
local function resetThemeToDefaults()
	THEME.CustomTitle, THEME.BackgroundImage, THEME.TypingSound, THEME.EnterSound = "", "", "", ""
	THEME.BackgroundImageTransparency = 0.5
	THEME.BackgroundImageScaleType = Enum.ScaleType.Stretch
	THEME.BackgroundImageTileSize = UDim2.new(0, 32, 0, 32)
end

local function loadThemeFromCSV(filePath)
	resetThemeToDefaults()
	if not (readfile and isfile and isfile(filePath)) then return end
	for line in readfile(filePath):gmatch("[^\r\n]+") do
		local key, val = line:match("^([^,]+),(.*)$")
		if key and val then
			key, val = cleanStr(key), cleanStr(val)
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
	local themes, themeDir = {}, "Shell/Assets/Themes"
	if listfiles and isfolder and isfolder(themeDir) then
		for _, file in ipairs(listfiles(themeDir)) do
			local name = file:match("([^/\\]+)%.csv$")
			if name then table.insert(themes, name) end
		end
	end
	return themes
end

-- =========================================================
-- UI Hierarchy Construction
-- =========================================================
local screenGui = createUIElement("ScreenGui", {
	Name = "Shell_Core",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = (pcall(function() return CoreGui end) and CoreGui) or localPlayer:WaitForChild("PlayerGui")
})
_G.ShellUI = screenGui

local typingSoundObj = createUIElement("Sound", { Name = "TypingAudio", Volume = 0.5, Parent = screenGui })
local enterSoundObj = createUIElement("Sound", { Name = "EnterAudio", Volume = 0.5, Parent = screenGui })

local function playThemeAudio(soundObj, assetId)
	if assetId and assetId ~= "" then
		local formatted = assetId:match("^rbxassetid://") and assetId or ("rbxassetid://" .. assetId)
		if soundObj.SoundId ~= formatted then soundObj.SoundId = formatted end
		soundObj:Play()
	end
end

local mainFrame = createUIElement("Frame", {
	Name = "MainFrame",
	Size = UDim2.new(0, THEME.FrameSize.X, 0, THEME.FrameSize.Y),
	Position = UDim2.new(0.5, -THEME.FrameSize.X / 2, 0.5, -THEME.FrameSize.Y / 2),
	BackgroundColor3 = toColor3(THEME.Background),
	BorderSizePixel = 0, Visible = false, Active = true, Parent = screenGui
})
applyCorners(mainFrame)

local mainStroke = createUIElement("UIStroke", {
	Color = toColor3(THEME.Border), Thickness = 1,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = mainFrame
})

local titleBar = createUIElement("Frame", {
	Name = "TitleBar", Size = UDim2.new(1, 0, 0, 30),
	BackgroundColor3 = toColor3(THEME.Border), BorderSizePixel = 0, Parent = mainFrame
})
applyCorners(titleBar)

local titleText = createUIElement("TextLabel", {
	Name = "TitleText", Size = UDim2.new(1, -220, 1, 0), Position = UDim2.new(0, 10, 0, 0),
	BackgroundTransparency = 1, Text = "Shell Console", TextColor3 = toColor3(THEME.Text),
	Font = Enum.Font.GothamBold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, Parent = titleBar
})

local devCheckboxFrame = createUIElement("Frame", {
	Name = "DevCheckboxFrame", Size = UDim2.new(0, 170, 1, 0),
	Position = UDim2.new(1, -200, 0, 0), BackgroundTransparency = 1, Parent = titleBar
})

local devCheckboxButton = createUIElement("TextButton", {
	Name = "DevCheckboxButton", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
	Text = "[ ] Enable Developer Console", TextColor3 = toColor3(THEME.Text),
	Font = Enum.Font.Gotham, TextSize = 11, TextTransparency = 1,
	TextXAlignment = Enum.TextXAlignment.Left, Parent = devCheckboxFrame
})

local minButton = createUIElement("TextButton", {
	Name = "MinimizeButton", Size = UDim2.new(0, 30, 1, 0), Position = UDim2.new(1, -30, 0, 0),
	BackgroundTransparency = 1, Text = "-", TextColor3 = toColor3(THEME.Text),
	Font = Enum.Font.GothamBold, TextSize = 16, Parent = titleBar
})

task.spawn(function()
	while screenGui.Parent do
		devCheckboxButton.TextTransparency = (_G.ShellDev == true) and 0 or 1
		task.wait(0.25)
	end
end)

local container = createUIElement("Frame", {
	Name = "Container", Size = UDim2.new(1, -10, 1, -40),
	Position = UDim2.new(0, 5, 0, 35), BackgroundTransparency = 1, Parent = mainFrame
})

createUIElement("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 5), Parent = container })

local consoleWrapper = createUIElement("Frame", {
	Name = "ConsoleWrapper", Size = UDim2.new(1, 0, 1, -35),
	LayoutOrder = 1, BackgroundTransparency = 1, ClipsDescendants = true, Parent = container
})

local consoleBgImage = createUIElement("ImageLabel", {
	Name = "ConsoleBackgroundImage", Size = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 1, ZIndex = 0, Visible = false, Parent = consoleWrapper
})

local function buildScrollingConsole(name, parent, size, pos)
	local scroll = createUIElement("ScrollingFrame", {
		Name = name, Size = size or UDim2.new(1, 0, 1, 0), Position = pos or UDim2.new(0, 0, 0, 0),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4,
		ScrollBarImageColor3 = toColor3(THEME.Border), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(0, 0, 0, 0), Parent = parent
	})
	applyPadding(scroll, 2, 2, 8, 8)
	createUIElement("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2), Parent = scroll })
	return scroll
end

local consoleFrame = buildScrollingConsole("ConsoleFrame", consoleWrapper)

local devConsoleContainer = createUIElement("Frame", {
	Name = "DevConsoleContainer", Size = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 1, Visible = false, ZIndex = 1, Parent = consoleWrapper
})

local devConsoleFrame = buildScrollingConsole("DevConsoleFrame", devConsoleContainer, UDim2.new(0.75, -5, 1, 0))

local statsFrame = createUIElement("ScrollingFrame", {
	Name = "StatsFrame", Size = UDim2.new(0.25, 0, 1, 0), Position = UDim2.new(0.75, 5, 0, 0),
	BackgroundColor3 = Color3.fromRGB(20, 20, 20), BackgroundTransparency = 0.3, BorderSizePixel = 0,
	ScrollBarThickness = 4, ScrollBarImageColor3 = toColor3(THEME.Accent), AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new(0, 0, 0, 0), Parent = devConsoleContainer
})
applyCorners(statsFrame)
applyPadding(statsFrame, 4, 4, 8, 8)
createUIElement("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4), Parent = statsFrame })

local function createStatLabel(text, parent, isHeader)
	return createUIElement("TextLabel", {
		Size = UDim2.new(1, -6, 0, isHeader and 18 or 16),
		BackgroundTransparency = 1,
		Font = isHeader and Enum.Font.GothamBold or (THEME.ConsoleFont or Enum.Font.Code),
		TextSize = isHeader and 12 or 11,
		TextColor3 = toColor3(isHeader and THEME.Accent or THEME.Text),
		Text = text,
		TextXAlignment = isHeader and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left,
		Parent = parent
	})
end

local function createDivider(parent)
	return createUIElement("Frame", {
		Size = UDim2.new(1, -6, 0, 1),
		BackgroundColor3 = toColor3(THEME.Border),
		BorderSizePixel = 0, Parent = parent
	})
end

-- Dynamic Stat Panels Creation
createStatLabel("-- STATISTICS --", statsFrame, true)
local fpsLabel = createStatLabel("FPS: --", statsFrame)
local avgFpsLabel = createStatLabel("Avg FPS: --", statsFrame)
local pingLabel = createStatLabel("Ping: -- ms", statsFrame)
local avgPingLabel = createStatLabel("Avg Ping: -- ms", statsFrame)
local memoryLabel = createStatLabel("Mem: -- MB", statsFrame)

createDivider(statsFrame)
createStatLabel("Server", statsFrame, true)
local gameNameLabel = createStatLabel("Game: --", statsFrame)
local gameIdLabel = createStatLabel("Place ID: --", statsFrame)
local playersCountLabel = createStatLabel("Players: --", statsFrame)
local serverTimeLabel = createStatLabel("Time: --", statsFrame)
local timeInGameLabel = createStatLabel("Session: --", statsFrame)
local serverLocLabel = createStatLabel("Server Region: --", statsFrame)

createDivider(statsFrame)
createStatLabel("Player", statsFrame, true)
local teamLabel = createStatLabel("Team: --", statsFrame)
local posLabel = createStatLabel("Pos: --", statsFrame)
local seatedLabel = createStatLabel("Seated: --", statsFrame)
local healthLabel = createStatLabel("Health: --", statsFrame)
local speedLabel = createStatLabel("WalkSpeed: --", statsFrame)
local actualSpeedLabel = createStatLabel("Actual Speed: --", statsFrame)
local jumpLabel = createStatLabel("JumpPower: --", statsFrame)
local stateLabel = createStatLabel("State: --", statsFrame)
local toolLabel = createStatLabel("Tool: --", statsFrame)

createDivider(statsFrame)
createStatLabel("Shell", statsFrame, true)
local shellRunningLabel = createStatLabel("Running: --", statsFrame)
local shellDevLabel = createStatLabel("Dev: --", statsFrame)
local shellThemeLabel = createStatLabel("Theme: --", statsFrame)
local shellFuncsLabel = createStatLabel("Functions: --", statsFrame)
local shellBindsLabel = createStatLabel("Keybinds: --", statsFrame)

-- Newly Added Commit Info Labels
local compilerCommitLabel = createStatLabel("Compiler: Loading...", statsFrame)
local uiCommitLabel = createStatLabel("UI: Loading...", statsFrame)
local funcCommitLabel = createStatLabel("Functions: Loading...", statsFrame)

-- Async load commit details
task.spawn(function()
	local compilerData = fetchLatestCommit("Core/compiler.lua")
	compilerCommitLabel.Text = string.format("Compiler: %s (%s)", compilerData.Date, compilerData.Message)

	local uiData = fetchLatestCommit("Core/ui.lua")
	uiCommitLabel.Text = string.format("UI: %s (%s)", uiData.Date, uiData.Message)

	local funcData = fetchLatestCommit("Core/functions.lua")
	funcCommitLabel.Text = string.format("FuncMgr: %s (%s)", funcData.Date, funcData.Message)
end)

-- Stat Updater Loop
task.spawn(function()
	local frameCount, lastTime, currentFps = 0, os.clock(), 60
	local sessionStartTime, historyTimer = os.clock(), os.clock()
	local fpsHistory, pingHistory, maxHistorySamples = {}, {}, 120
	local baselineFps, baselinePing, baselineMem = 60, 0, 0
	local serverCountry, gameName = "Unknown", "Unknown"
	local lastPosition, lastPosTime = nil, os.clock()

	task.spawn(function()
		local ok, res = pcall(function() return LocalizationService:GetCountryRegionForPlayerAsync(localPlayer) end)
		if ok and res then serverCountry = res end
	end)

	task.spawn(function()
		local ok, info = pcall(function() return MarketplaceService:GetProductInfo(game.PlaceId) end)
		if ok and info and info.Name then gameName = info.Name end
	end)

	RunService.RenderStepped:Connect(function()
		frameCount += 1
		local now = os.clock()
		if now - lastTime >= 1 then
			currentFps = math.floor(frameCount / (now - lastTime))
			frameCount, lastTime = 0, now
		end
	end)

	while screenGui.Parent do
		if devConsoleContainer.Visible then
			local now = os.clock()
			local pingItem = Stats.Network.ServerStatsItem:FindFirstChild("Data Ping")
			local currentPing = pingItem and math.floor(pingItem:GetValue()) or 0
			local currentMem = math.floor(Stats:GetTotalMemoryUsageMb())

			table.insert(fpsHistory, currentFps)
			table.insert(pingHistory, currentPing)
			if #fpsHistory > maxHistorySamples then table.remove(fpsHistory, 1) end
			if #pingHistory > maxHistorySamples then table.remove(pingHistory, 1) end

			local sumFps, sumPing = 0, 0
			for _, v in ipairs(fpsHistory) do sumFps += v end
			for _, v in ipairs(pingHistory) do sumPing += v end
			local avgFps = #fpsHistory > 0 and math.floor(sumFps / #fpsHistory) or currentFps
			local avgPing = #pingHistory > 0 and math.floor(sumPing / #pingHistory) or currentPing

			if now - historyTimer >= 5 then
				baselineFps, baselinePing, baselineMem = currentFps, currentPing, currentMem
				historyTimer = now
			end

			local dFps, dPing, dMem = currentFps - baselineFps, currentPing - baselinePing, currentMem - baselineMem
			fpsLabel.Text = string.format("FPS: %d (%s%d)", currentFps, dFps >= 0 and "+" or "", dFps)
			avgFpsLabel.Text = string.format("Avg FPS: %d", avgFps)
			pingLabel.Text = string.format("Ping: %d ms (%s%d)", currentPing, dPing >= 0 and "+" or "", dPing)
			avgPingLabel.Text = string.format("Avg Ping: %d ms", avgPing)
			memoryLabel.Text = string.format("Mem: %d MB (%s%d)", currentMem, dMem >= 0 and "+" or "", dMem)

			gameNameLabel.Text = "Game: " .. gameName
			gameIdLabel.Text = "Place ID: " .. tostring(game.PlaceId)
			playersCountLabel.Text = "Players: " .. tostring(#Players:GetPlayers())
			serverTimeLabel.Text = "Time: " .. os.date("%H:%M:%S")

			local elapsed = math.floor(now - sessionStartTime)
			timeInGameLabel.Text = string.format("Session: %02d:%02d:%02d", math.floor(elapsed / 3600), math.floor((elapsed % 3600) / 60), elapsed % 60)
			serverLocLabel.Text = "Server Region: " .. serverCountry

			teamLabel.Text = "Team: " .. (localPlayer and localPlayer.Team and localPlayer.Team.Name or "None")

			local char = localPlayer and localPlayer.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")

			if char then
				local pivot = char:GetPivot().Position
				posLabel.Text = string.format("Pos: %d, %d, %d", math.round(pivot.X), math.round(pivot.Y), math.round(pivot.Z))
				if lastPosition then
					local dt = now - lastPosTime
					actualSpeedLabel.Text = string.format("Actual Speed: %.1f", dt > 0 and ((pivot - lastPosition).Magnitude / dt) or 0)
				else
					actualSpeedLabel.Text = "Actual Speed: 0.0"
				end
				lastPosition, lastPosTime = pivot, now
				seatedLabel.Text = "Seated: " .. tostring(hum and hum.Sit or false)
			else
				posLabel.Text, actualSpeedLabel.Text, seatedLabel.Text = "Pos: N/A", "Actual Speed: N/A", "Seated: N/A"
				lastPosition = nil
			end

			if hum and hum.Parent then
				healthLabel.Text = string.format("HP: %d/%d", math.floor(hum.Health), math.floor(hum.MaxHealth))
				speedLabel.Text = string.format("WalkSpeed: %.1f", hum.WalkSpeed)
				jumpLabel.Text = string.format("Jump: %.1f", hum.JumpPower)
				stateLabel.Text = "State: " .. hum:GetState().Name
				local tool = char:FindFirstChildWhichIsA("Tool")
				toolLabel.Text = "Tool: " .. (tool and tool.Name or "None")
			else
				healthLabel.Text, speedLabel.Text, jumpLabel.Text, stateLabel.Text, toolLabel.Text = "HP: N/A", "WalkSpeed: N/A", "Jump: N/A", "State: N/A", "Tool: N/A"
			end

			shellRunningLabel.Text = "Running: " .. tostring(_G.ShellRunning or false)
			shellDevLabel.Text = "Dev: " .. tostring(_G.ShellDev or false)
			shellThemeLabel.Text = "Theme: " .. tostring(_G.ShellTheme or "Default")
			shellFuncsLabel.Text = "Functions: " .. tostring(type(_G.ShellFunctions) == "table" and #_G.ShellFunctions or 0)
			shellBindsLabel.Text = "Keybinds: " .. tostring(type(_G.ShellKeybinds) == "table" and #_G.ShellKeybinds or 0)
		end
		task.wait(0.25)
	end
end)

local devConsoleEnabled = false
devCheckboxButton.MouseButton1Click:Connect(function()
	if not _G.ShellDev then return end
	devConsoleEnabled = not devConsoleEnabled
	devCheckboxButton.Text = devConsoleEnabled and "[X] Enable Developer Console" or "[ ] Enable Developer Console"
	consoleFrame.Visible = not devConsoleEnabled
	devConsoleContainer.Visible = devConsoleEnabled
end)

-- Dynamic Window Edge Resizing
local function setupEdgeResizing(targetFrame, minSize)
	minSize = minSize or Vector2.new(300, 150)
	local THICK = 6
	local resizing, activeDir, startFrameSize, startFramePos, startMousePos

	local handles = {
		Left = {Size = UDim2.new(0, THICK, 1, -THICK*2), Pos = UDim2.new(0, -THICK/2, 0, THICK)},
		Right = {Size = UDim2.new(0, THICK, 1, -THICK*2), Pos = UDim2.new(1, -THICK/2, 0, THICK)},
		Top = {Size = UDim2.new(1, -THICK*2, 0, THICK), Pos = UDim2.new(0, THICK, 0, -THICK/2)},
		Bottom = {Size = UDim2.new(1, -THICK*2, 0, THICK), Pos = UDim2.new(0, THICK, 1, -THICK/2)},
		TopLeft = {Size = UDim2.new(0, THICK*2, 0, THICK*2), Pos = UDim2.new(0, -THICK/2, 0, -THICK/2)},
		TopRight = {Size = UDim2.new(0, THICK*2, 0, THICK*2), Pos = UDim2.new(1, -THICK*1.5, 0, -THICK/2)},
		BottomLeft = {Size = UDim2.new(0, THICK*2, 0, THICK*2), Pos = UDim2.new(0, -THICK/2, 1, -THICK*1.5)},
		BottomRight = {Size = UDim2.new(0, THICK*2, 0, THICK*2), Pos = UDim2.new(1, -THICK*1.5, 1, -THICK*1.5)},
	}

	local handleFolder = targetFrame:FindFirstChild("ResizeHandles") or Instance.new("Folder", targetFrame)
	handleFolder.Name = "ResizeHandles"
	handleFolder:ClearAllChildren()

	for dir, config in pairs(handles) do
		local handle = createUIElement("TextButton", {
			Name = dir .. "Handle", Size = config.Size, Position = config.Pos,
			BackgroundTransparency = 1, Text = "", ZIndex = 20, Parent = handleFolder
		})

		handle.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				resizing, activeDir = true, dir
				startMousePos, startFrameSize, startFramePos = input.Position, targetFrame.AbsoluteSize, targetFrame.Position
				input.Changed:Connect(function()
					if input.UserInputState == Enum.UserInputState.End then resizing = false end
				end)
			end
		end)
	end

	UserInputService.InputChanged:Connect(function(input)
		if resizing and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - startMousePos
			local newSizeX, newSizeY = startFrameSize.X, startFrameSize.Y
			local newPosX, newPosY = startFramePos.X.Offset, startFramePos.Y.Offset

			if activeDir:find("Right") then newSizeX = math.max(minSize.X, startFrameSize.X + delta.X)
			elseif activeDir:find("Left") then
				local posW = startFrameSize.X - delta.X
				newSizeX = math.max(minSize.X, posW)
				newPosX = startFramePos.X.Offset + (posW >= minSize.X and delta.X or (startFrameSize.X - minSize.X))
			end

			if activeDir:find("Bottom") then newSizeY = math.max(minSize.Y, startFrameSize.Y + delta.Y)
			elseif activeDir:find("Top") then
				local posH = startFrameSize.Y - delta.Y
				newSizeY = math.max(minSize.Y, posH)
				newPosY = startFramePos.Y.Offset + (posH >= minSize.Y and delta.Y or (startFrameSize.Y - minSize.Y))
			end

			targetFrame.Size = UDim2.new(0, newSizeX, 0, newSizeY)
			targetFrame.Position = UDim2.new(startFramePos.X.Scale, newPosX, startFramePos.Y.Scale, newPosY)
		end
	end)
end

setupEdgeResizing(mainFrame, Vector2.new(350, 200))

-- =========================================================
-- Logging System
-- =========================================================
local function saveLog(fullLine)
	if not fullLine or fullLine == "" then return end
	if appendfile then
		if not isfile(LOG_PATH) then writefile(LOG_PATH, "-- Start of Log --\n") end
		appendfile(LOG_PATH, fullLine .. "\n")
	elseif writefile then
		local content = (isfile and isfile(LOG_PATH) and readfile(LOG_PATH)) or "-- Start of Log --"
		writefile(LOG_PATH, content .. "\n" .. fullLine)
	end
end

local function shellLog(text, logTypeOrColor)
	local saveText = cleanStr(text)
	saveLog(saveText)

	local logColor, isDev = THEME.Console_Info, false
	if typeof(logTypeOrColor) == "Color3" then
		logColor = logTypeOrColor
	elseif type(logTypeOrColor) == "string" then
		local lType = logTypeOrColor:lower()
		isDev = (lType == "developer")
		logColor = isDev and THEME.Accent or ({
			error = THEME.Console_Error,
			warn = THEME.Console_Warn, warning = THEME.Console_Warn,
			success = THEME.Console_Success
		})[lType] or THEME[logTypeOrColor] or THEME.Console_Info
	end

	local targetConsole = isDev and devConsoleFrame or consoleFrame
	local logEntry = createUIElement("TextBox", {
		Name = "LogEntry", BackgroundTransparency = 1, Size = UDim2.new(1, -10, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y, Text = string.format("[%s] %s", os.date("%H:%M:%S"), tostring(text)),
		TextColor3 = toColor3(logColor, THEME.Text), Font = THEME.ConsoleFont or Enum.Font.Code,
		TextSize = THEME.ConsoleFontSize or 14, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
		TextEditable = false, ClearTextOnFocus = false, Parent = targetConsole
	})

	task.defer(function() targetConsole.CanvasPosition = Vector2.new(0, 100000) end)
end

_G.ShellLog = shellLog
local function devlog(msg) if _G.ShellLog then _G.ShellLog("[Dev]: " .. msg, "developer") end end

shellLog("Shell UI Framework Loaded.", THEME.Accent)
shellLog("Press F2 or ' to toggle/focus visibility.", THEME.Placeholder)

-- Command Bar Framework
local commandBarContainer = createUIElement("Frame", {
	Name = "CommandBarContainer", Size = UDim2.new(1, 0, 0, 30),
	LayoutOrder = 2, BackgroundColor3 = Color3.fromRGB(30, 30, 30), BorderSizePixel = 0, Parent = container
})
applyCorners(commandBarContainer)

local commandBar = createUIElement("TextBox", {
	Name = "CommandBar", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
	TextColor3 = toColor3(THEME.Text), PlaceholderColor3 = toColor3(THEME.Placeholder),
	PlaceholderText = "Type a command...", Font = THEME.CommandFont or Enum.Font.Code,
	TextSize = THEME.CommandFontSize or 14, TextXAlignment = Enum.TextXAlignment.Left,
	Text = "", ClearTextOnFocus = false, Parent = commandBarContainer
})
applyPadding(commandBar, 2, 2, 8, 8)

local suggestionFrame = createUIElement("Frame", {
	Name = "SuggestionFrame", Size = UDim2.new(0, 300, 0, 150), Position = UDim2.new(0, 0, 0, -155),
	BackgroundColor3 = toColor3(THEME.Background), Visible = false, ZIndex = 10, Parent = commandBarContainer
})
applyCorners(suggestionFrame)
local suggStroke = createUIElement("UIStroke", { Color = toColor3(THEME.Border), Parent = suggestionFrame })

local suggestionList = buildScrollingConsole("SuggestionList", suggestionFrame)
suggestionList.ScrollBarThickness = 2

-- Command State Variables
local commands, matches, matchIndex, isMinimized, lastCommand = {}, {}, 1, false, ""

_G.ShellUIUpdate = function(newCommands)
	commands = newCommands
	local count = 0; for _ in pairs(commands) do count += 1 end
	shellLog("Command map synchronized. (" .. count .. " entries)", THEME.Accent)
end

local function scrollToMatch(index)
	local itemHeight = (THEME.SuggestionFontSize or 14) + 5
	local targetYMin = (index - 1) * itemHeight
	local targetYMax = targetYMin + itemHeight
	local currentY, visibleH = suggestionList.CanvasPosition.Y, suggestionList.AbsoluteWindowSize.Y

	if targetYMin < currentY then suggestionList.CanvasPosition = Vector2.new(0, targetYMin)
	elseif targetYMax > (currentY + visibleH) then suggestionList.CanvasPosition = Vector2.new(0, targetYMax - visibleH) end
end

local function updateSelectionVisual()
	local idx = 1
	for _, child in ipairs(suggestionList:GetChildren()) do
		if child:IsA("TextButton") then
			child.TextColor3 = toColor3((idx == matchIndex) and THEME.Accent or THEME.SuggestionTextColor, THEME.Text)
			idx += 1
		end
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
	matches, matchIndex = {}, 1

	for _, child in ipairs(suggestionList:GetChildren()) do
		if child:IsA("TextButton") then child:Destroy() end
	end

	if fullText == "" then suggestionFrame.Visible = false; return end

	local parts = string.split(fullText, " ")
	local cmdInput = parts[1]:lower()

	if #parts <= 1 then
		for name, cmd in pairs(commands) do
			if name:sub(1, #cmdInput) == cmdInput and cmd.Category ~= "Hidden" then
				table.insert(matches, { Name = cmd.Name, Display = string.format("%s (%s)", cmd.Name, table.concat(cmd.Arguments or {}, ", ")), Value = cmd.Name .. " " })
			end
		end
		table.sort(matches, function(a, b) return a.Name < b.Name end)
	else
		local activeCmd = commands[cmdInput]
		if activeCmd and activeCmd.Arguments then
			local firstArg, argInput = activeCmd.Arguments[1], parts[2]:lower()
			
			if firstArg == "Player" then
				for _, p in ipairs(Players:GetPlayers()) do
					if p.Name:lower():sub(1, #argInput) == argInput then
						table.insert(matches, { Name = p.Name, Display = p.Name, Value = cmdInput .. " " .. p.Name })
					end
				end
			elseif firstArg == "Theme" or firstArg == "ThemeName" then
				for _, themeName in ipairs(getAvailableThemes()) do
					if themeName:lower():sub(1, #argInput) == argInput then
						table.insert(matches, { Name = themeName, Display = themeName, Value = cmdInput .. " " .. themeName })
					end
				end
			elseif (firstArg == "FilePath" or firstArg == "File" or firstArg == "Path") and typeof(listfiles) == "function" then
				local function getAllDescendants(dir)
					local results = {}
					local ok, files = pcall(listfiles, dir)
					if ok and files then
						for _, rawPath in ipairs(files) do
							local norm = rawPath:gsub("\\", "/")
							table.insert(results, norm)
							if typeof(isfolder) == "function" and pcall(isfolder, rawPath) then
								for _, sub in ipairs(getAllDescendants(norm)) do table.insert(results, sub) end
							end
						end
					end
					return results
				end
				for _, fullPath in ipairs(getAllDescendants("Shell")) do
					local relative = fullPath:gsub("^Shell/", ""):gsub("^Shell", "")
					if relative ~= "" and relative:lower():sub(1, #argInput) == argInput then
						table.insert(matches, { Name = relative, Display = relative, Value = cmdInput .. " " .. relative })
					end
				end
			end
			table.sort(matches, function(a, b) return a.Name < b.Name end)
		end
	end

	if #matches == 0 then
		suggestionFrame.Visible = false
	else
		suggestionFrame.Visible = true
		local fontSize = THEME.SuggestionFontSize or 14
		local itemHeight = fontSize + 4
		local frameHeight = (math.min(#matches, 5) * itemHeight) + 10

		suggestionFrame.Size = UDim2.new(0, 300, 0, frameHeight)
		suggestionFrame.Position = UDim2.new(0, 0, 0, -frameHeight - 5)

		for i, match in ipairs(matches) do
			local sugButton = createUIElement("TextButton", {
				Name = "Sug_" .. match.Name, Size = UDim2.new(1, -5, 0, itemHeight), BackgroundTransparency = 1,
				Text = "  " .. match.Display, TextColor3 = toColor3((i == 1) and THEME.Accent or THEME.SuggestionTextColor, THEME.Text),
				Font = THEME.CommandFont or Enum.Font.Code, TextSize = fontSize, TextXAlignment = Enum.TextXAlignment.Left,
				Parent = suggestionList
			})
			sugButton.MouseButton1Click:Connect(function() applySuggestion(match.Value) end)
		end
	end
end

-- Interactivity & Keybind Animations
local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

minButton.MouseButton1Click:Connect(function()
	isMinimized = not isMinimized
	local handleFolder = mainFrame:FindFirstChild("ResizeHandles")
	minButton.Text = isMinimized and "+" or "-"
	if handleFolder then handleFolder.Parent = isMinimized and nil or mainFrame end
	if isMinimized then suggestionFrame.Visible = false end

	TweenService:Create(mainFrame, tweenInfo, { Size = UDim2.new(0, mainFrame.AbsoluteSize.X, 0, isMinimized and 75 or THEME.FrameSize.Y) }):Play()
	TweenService:Create(consoleWrapper, tweenInfo, { Size = UDim2.new(1, 0, 0, isMinimized and 0 or -35) }):Play()
end)

local dragging, dragInput, dragStart, startPos
titleBar.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging, dragStart, startPos = true, input.Position, mainFrame.Position
		input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then dragging = false end end)
	end
end)

titleBar.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then dragInput = input end
end)

UserInputService.InputChanged:Connect(function(input)
	if input == dragInput and dragging then
		local delta = input.Position - dragStart
		mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if input.KeyCode == Enum.KeyCode.F2 then
		mainFrame.Visible = not mainFrame.Visible
		if mainFrame.Visible then commandBar:CaptureFocus() else commandBar:ReleaseFocus() suggestionFrame.Visible = false end
	elseif input.KeyCode == Enum.KeyCode.Quote and not processed then
		mainFrame.Visible = true
		task.defer(function() commandBar.Text = ""; commandBar:CaptureFocus() end)
	end
end)

local previousTextLen = 0
commandBar:GetPropertyChangedSignal("Text"):Connect(function()
	commandBar.Text = commandBar.Text:gsub("\t", ""):gsub("'", "")
	updateSuggestions()
	local currentLen = #commandBar.Text
	if currentLen > previousTextLen then playThemeAudio(typingSoundObj, THEME.TypingSound) end
	previousTextLen = currentLen
end)

UserInputService.InputBegan:Connect(function(input)
	if not commandBar:IsFocused() then return end
	if input.KeyCode == Enum.KeyCode.Tab then
		if suggestionFrame.Visible and #matches > 0 and matches[matchIndex] then applySuggestion(matches[matchIndex].Value) end
	elseif suggestionFrame.Visible then
		if input.KeyCode == Enum.KeyCode.Up and #matches > 1 then
			matchIndex = (matchIndex - 2) % #matches + 1
			updateSelectionVisual()
		elseif input.KeyCode == Enum.KeyCode.Down and #matches > 1 then
			matchIndex = matchIndex % #matches + 1
			updateSelectionVisual()
		end
	else
		if input.KeyCode == Enum.KeyCode.Up and commandBar.Text == "" and lastCommand ~= "" then applySuggestion(lastCommand)
		elseif input.KeyCode == Enum.KeyCode.Down and commandBar.Text == lastCommand and lastCommand ~= "" then commandBar.Text = "" end
	end
end)

_G.ShellTheme = _G.ShellTheme or "default"

local function applyThemeToUI()
	mainFrame.BackgroundColor3, mainFrame.Size = toColor3(THEME.Background), UDim2.new(0, THEME.FrameSize.X, 0, THEME.FrameSize.Y)
	mainStroke.Color = toColor3(THEME.Border)
	titleBar.BackgroundColor3 = toColor3(THEME.Border)
	titleText.Text = (THEME.CustomTitle and THEME.CustomTitle ~= "") and THEME.CustomTitle or "Shell Console"
	titleText.TextColor3, minButton.TextColor3 = toColor3(THEME.Text), toColor3(THEME.Text)

	local bg = toColor3(THEME.Background)
	commandBarContainer.BackgroundColor3 = Color3.fromRGB(math.clamp(math.floor(bg.R * 255) + 5, 0, 255), math.clamp(math.floor(bg.G * 255) + 5, 0, 255), math.clamp(math.floor(bg.B * 255) + 5, 0, 255))
	commandBar.TextColor3, commandBar.PlaceholderColor3 = toColor3(THEME.Text), toColor3(THEME.Placeholder)
	commandBar.Font, commandBar.TextSize = THEME.CommandFont or Enum.Font.Code, THEME.CommandFontSize or 14

	suggestionFrame.BackgroundColor3, suggStroke.Color = toColor3(THEME.Background), toColor3(THEME.Border)

	if THEME.BackgroundImage and THEME.BackgroundImage ~= "" then
		consoleBgImage.Image = formatImageAsset(THEME.BackgroundImage)
		consoleBgImage.ImageTransparency = THEME.BackgroundImageTransparency or 0
		consoleBgImage.ScaleType = THEME.BackgroundImageScaleType or Enum.ScaleType.Stretch
		if typeof(THEME.BackgroundImageTileSize) == "UDim2" then consoleBgImage.TileSize = THEME.BackgroundImageTileSize end
		consoleBgImage.Visible = true
	else consoleBgImage.Visible = false end

	for _, obj in ipairs({mainFrame, titleBar, commandBarContainer, suggestionFrame}) do applyCorners(obj) end
	for _, target in ipairs({consoleFrame, devConsoleFrame}) do
		for _, logEntry in ipairs(target:GetChildren()) do
			if logEntry:IsA("TextBox") then
				logEntry.Font, logEntry.TextSize = THEME.ConsoleFont or Enum.Font.Code, THEME.ConsoleFontSize or 14
			end
		end
	end
end

applyThemeToUI()

_G.SelectTheme = function(themeName)
	local filePath = string.format("Shell/Assets/Themes/%s.csv", tostring(themeName))
	if isfile and not isfile(filePath) then
		shellLog("Theme file not found: " .. filePath, THEME.Console_Error)
		return false
	end

	local success, err = pcall(function() loadThemeFromCSV(filePath) end)
	if success then
		_G.ShellTheme = themeName
		applyThemeToUI()
		if writefile and readfile and isfile and isfile(filePath) then
			pcall(function() writefile(DEFAULT_THEME_PATH, readfile(filePath)) end)
		end
		shellLog("Successfully loaded theme: " .. themeName, THEME.Accent)
		return true
	else
		shellLog("Failed to load theme '" .. themeName .. "': " .. tostring(err), THEME.Console_Error)
		return false
	end
end

_G.ShellClearConsole = function()
	local targetConsole = devConsoleEnabled and devConsoleFrame or consoleFrame
	for _, child in ipairs(targetConsole:GetChildren()) do
		if child:IsA("TextBox") then child:Destroy() end
	end
	targetConsole.CanvasPosition = Vector2.new(0, 0)
end

commandBar.FocusLost:Connect(function(enterPressed)
	suggestionFrame.Visible = false
	if enterPressed then
		playThemeAudio(enterSoundObj, THEME.EnterSound)
		local fullText = commandBar.Text
		commandBar.Text = ""
		if fullText ~= "" then lastCommand = fullText end

		local args = string.split(fullText, " ")
		local cmdName = table.remove(args, 1)
		if not cmdName then devlog("ui.lua -- expected cmdname, got nil or error.") return end
		cmdName = cmdName:lower()

		if commands[cmdName] then
			shellLog("> " .. fullText, THEME.Text)
			task.spawn(function()
				local success, result = pcall(commands[cmdName].Function, unpack(args))
				if not success then shellLog("Error: " .. tostring(result), THEME.Console_Error)
				elseif result then shellLog("Return: " .. tostring(result), THEME.Console_Success) end
			end)
		else
			shellLog("Unknown command: " .. tostring(cmdName), THEME.Console_Error)
		end
	end
end)
