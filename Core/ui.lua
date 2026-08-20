_G.ShellVersions["ui"] = "Gamma (#4)"

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
-- Constants & State Definitions
-- =========================================================
local DEFAULT_TEXT_COLOR = Color3.fromRGB(220, 220, 220)
local DEFAULT_THEME_PATH = "Shell/Assets/Themes/default.csv"
local SHELL_THEME_PATH = "Shell/Assets/Themes/shell.csv"
local LOG_PATH = "Shell/Core/log.txt"
local WAYPOINTS_PATH = "Shell/Core/waypoints.json"

local THEME = {
	Background = Color3.fromRGB(20, 20, 24),
	Header = Color3.fromRGB(28, 28, 34),
	Border = Color3.fromRGB(45, 45, 55),
	Text = DEFAULT_TEXT_COLOR,
	Placeholder = Color3.fromRGB(120, 120, 130),
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
	SuggestionFontSize = 13,
	FrameSize = Vector2.new(620, 450),
	UseUICorner = true,
	CustomTitle = "", BackgroundImage = "", TypingSound = "", EnterSound = "",
	BackgroundImageTransparency = 0.5,
	BackgroundImageScaleType = Enum.ScaleType.Stretch,
	BackgroundImageTileSize = UDim2.new(0, 32, 0, 32),
}

local TAB_VISIBILITY_SETTINGS = { Console = true, Scripts = false, Waypoints = true, Settings = true }
local LOG_FILTER_STATE = { SearchText = "", ShowInfo = true, ShowWarn = true, ShowError = true }
local WAYPOINTS, commands, matches, selectedIndex = {}, {}, {}, 1

-- =========================================================
-- Universal Helpers
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
	if lower == "true" or lower == "false" then return lower == "true" end

	local parsedColor = parseColor3(val)
	if parsedColor then return parsedColor end
	if tonumber(val) then return tonumber(val) end

	local clean = cleanStr(val)
	local x, y = clean:match("^%s*(%d+)%s*,%s*(%d+)%s*$")
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

local function createUIElement(className, properties)
	local inst = Instance.new(className)
	for k, v in pairs(properties) do inst[k] = v end
	return inst
end

local function applyCorners(parent, radius)
	if not THEME.UseUICorner then
		local existing = parent:FindFirstChildOfClass("UICorner")
		if existing then existing:Destroy() end
		return nil
	end
	local corner = parent:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	corner.CornerRadius = radius or UDim.new(0, 6)
	corner.Parent = parent
	return corner
end

local function applyPadding(parent, top, bot, left, right)
	local pad = parent:FindFirstChildOfClass("UIPadding") or Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, top or 5), UDim.new(0, bot or 5)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, left or 8), UDim.new(0, right or 8)
	pad.Parent = parent
	return pad
end

local function createStatLabel(text, parent, isHeader)
	return createUIElement("TextLabel", {
		Size = UDim2.new(1, -6, 0, isHeader and 20 or 16),
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
		Size = UDim2.new(1, -6, 0, 1), BackgroundColor3 = toColor3(THEME.Border),
		BorderSizePixel = 0, Parent = parent
	})
end

local commitCache = {}
local function fetchLatestCommit(filePath)
	if commitCache[filePath] then return commitCache[filePath] end
	if isfile and isfile(filePath) then
		commitCache[filePath] = { Date = "N/A (Local)", Message = "N/A (Local)" }
		return commitCache[filePath]
	end

	local url = string.format("https://api.github.com/repos/generic-goose/Shell/commits?path=%s&page=1&per_page=1", filePath)
	local requestFunc = (syn and syn.request) or (http and http.request) or request or http_request
	local dateStr, msgStr = "N/A", "Fetch Failed"

	if requestFunc then
		local ok, response = pcall(requestFunc, { Url = url, Method = "GET" })
		if ok and response and response.Body then
			local parseOk, data = pcall(function() return HttpService:JSONDecode(response.Body) end)
			if parseOk and type(data) == "table" and data[1] and data[1].commit then
				local commit = data[1].commit
				local rawDate = commit.committer and commit.committer.date or commit.author.date or ""
				dateStr = rawDate:match("^(%d%d%d%d%-%d%d%-%d%d)") or "Unknown"
				msgStr = (commit.message or "No Message"):split("\n")[1]
				if #msgStr > 25 then msgStr = msgStr:sub(1, 22) .. "..." end
			end
		end
	end

	commitCache[filePath] = { Date = dateStr, Message = msgStr }
	return commitCache[filePath]
end

-- =========================================================
-- Theme & Data IO
-- =========================================================
local function loadThemeFromCSV(filePath)
	THEME.CustomTitle, THEME.BackgroundImage, THEME.TypingSound, THEME.EnterSound = "", "", "", ""
	THEME.BackgroundImageTransparency, THEME.BackgroundImageScaleType = 0.5, Enum.ScaleType.Stretch
	THEME.BackgroundImageTileSize = UDim2.new(0, 32, 0, 32)

	if not (readfile and isfile and isfile(filePath)) then return end
	for line in readfile(filePath):gmatch("[^\r\n]+") do
		local key, val = line:match("^([^,]+),(.*)$")
		if key and val then
			key, val = cleanStr(key), cleanStr(val)
			if key:lower() ~= "key" and key ~= "" then THEME[key] = autoParseValue(key, val) end
		end
	end
end

pcall(function()
	if isfile and writefile and readfile and not isfile(DEFAULT_THEME_PATH) and isfile(SHELL_THEME_PATH) then
		writefile(DEFAULT_THEME_PATH, readfile(SHELL_THEME_PATH))
	end
	loadThemeFromCSV(DEFAULT_THEME_PATH)
end)

local function loadWaypointsFromFile()
	if isfile and readfile and isfile(WAYPOINTS_PATH) then
		local ok, decoded = pcall(function() return HttpService:JSONDecode(readfile(WAYPOINTS_PATH)) end)
		if ok and type(decoded) == "table" then WAYPOINTS = decoded return end
	end
	WAYPOINTS = {}
end

local function saveWaypointsToFile()
	if writefile then pcall(function() writefile(WAYPOINTS_PATH, HttpService:JSONEncode(WAYPOINTS)) end) end
end

loadWaypointsFromFile()

-- =========================================================
-- Main UI Framework
-- =========================================================
local screenGui = createUIElement("ScreenGui", {
	Name = "Shell_Core", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = (pcall(function() return CoreGui end) and CoreGui) or localPlayer:WaitForChild("PlayerGui")
})
_G.ShellUI = screenGui

local enterSoundObj = createUIElement("Sound", { Name = "EnterAudio", Volume = 0.5, Parent = screenGui })

local function playThemeAudio(soundObj, assetId)
	if _G.ShellSettings and _G.ShellSettings.Core and _G.ShellSettings.Core.Audio and assetId and assetId ~= "" then
		local formatted = assetId:match("^rbxassetid://") and assetId or ("rbxassetid://" .. assetId)
		if soundObj.SoundId ~= formatted then soundObj.SoundId = formatted end
		soundObj:Play()
	end
end

local mainFrame = createUIElement("Frame", {
	Name = "MainFrame", Size = UDim2.new(0, THEME.FrameSize.X, 0, THEME.FrameSize.Y),
	Position = UDim2.new(0.5, -THEME.FrameSize.X / 2, 0.5, -THEME.FrameSize.Y / 2),
	BackgroundColor3 = toColor3(THEME.Background), BorderSizePixel = 0, Visible = false, Active = true, Parent = screenGui
})
applyCorners(mainFrame)

createUIElement("UIStroke", { Color = toColor3(THEME.Border), Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = mainFrame })

local titleBar = createUIElement("Frame", {
	Name = "TitleBar", Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = toColor3(THEME.Header, THEME.Border), BorderSizePixel = 0, Parent = mainFrame
})
applyCorners(titleBar)

createUIElement("TextLabel", {
	Name = "TitleText", Size = UDim2.new(1, -50, 1, 0), Position = UDim2.new(0, 10, 0, 0),
	BackgroundTransparency = 1, Text = "Shell Console", TextColor3 = toColor3(THEME.Text),
	Font = Enum.Font.GothamBold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, Parent = titleBar
})

local minButton = createUIElement("TextButton", {
	Name = "MinimizeButton", Size = UDim2.new(0, 30, 1, 0), Position = UDim2.new(1, -30, 0, 0),
	BackgroundTransparency = 1, Text = "-", TextColor3 = toColor3(THEME.Text), Font = Enum.Font.GothamBold, TextSize = 16, Parent = titleBar
})

local tabBar = createUIElement("ScrollingFrame", {
	Name = "TabBar", Size = UDim2.new(1, -10, 0, 28), Position = UDim2.new(0, 5, 0, 35),
	BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 2,
	ScrollBarImageColor3 = toColor3(THEME.Accent), AutomaticCanvasSize = Enum.AutomaticSize.X,
	CanvasSize = UDim2.new(0, 0, 0, 0), Parent = mainFrame
})

createUIElement("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), Parent = tabBar })

local container = createUIElement("Frame", {
	Name = "Container", Size = UDim2.new(1, -10, 1, -72), Position = UDim2.new(0, 5, 0, 67),
	BackgroundTransparency = 1, Parent = mainFrame
})

local function buildScrollingConsole(name, parent, size, pos, skipLayout)
	local scroll = createUIElement("ScrollingFrame", {
		Name = name, Size = size or UDim2.new(1, 0, 1, 0), Position = pos or UDim2.new(0, 0, 0, 0),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4,
		ScrollBarImageColor3 = toColor3(THEME.Border), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(0, 0, 0, 0), Parent = parent
	})
	applyPadding(scroll, 2, 2, 8, 8)
	if not skipLayout then
		createUIElement("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2), Parent = scroll })
	end
	return scroll
end

-- =========================================================
-- Tab Engine
-- =========================================================
local tabPages, tabButtons, dropdownItems, activeTabName = {}, {}, {}, "Console"

local dropdownFrame = createUIElement("Frame", {
	Name = "TabDropdownMenu", Size = UDim2.new(0, 130, 0, 0), Position = UDim2.new(1, -135, 0, 32),
	BackgroundColor3 = toColor3(THEME.Header, THEME.Border), BorderSizePixel = 0, Visible = false, ZIndex = 50, Parent = mainFrame
})
applyCorners(dropdownFrame, UDim.new(0, 4))
createUIElement("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2), Parent = dropdownFrame })

local plusBtn = createUIElement("TextButton", {
	Name = "PlusTabBtn", Size = UDim2.new(0, 30, 1, -4), BackgroundColor3 = toColor3(THEME.Header, THEME.Border),
	BorderSizePixel = 0, Text = "+", TextColor3 = toColor3(THEME.Placeholder), Font = Enum.Font.GothamBold, TextSize = 14, Parent = tabBar
})
applyCorners(plusBtn, UDim.new(0, 4))

plusBtn.MouseButton1Click:Connect(function()
	dropdownFrame.Visible = not dropdownFrame.Visible
	local count = 0; for _ in pairs(dropdownItems) do count += 1 end
	dropdownFrame.Size = UDim2.new(0, 130, 0, (count * 24) + 4)
end)

local function switchTab(targetName)
	activeTabName = targetName
	for name, page in pairs(tabPages) do
		local isTarget = (name == targetName)
		page.Visible = isTarget
		local btn = tabButtons[name]
		if btn then
			local title = btn:FindFirstChild("Title")
			if title then title.TextColor3 = toColor3(isTarget and THEME.Accent or THEME.Placeholder) end
			local ind = btn:FindFirstChild("Indicator")
			if ind then ind.Visible = isTarget end
		end
	end
end

local function updateTabVisibilities()
	local devEnabled = _G.ShellDev == true
	for name, btn in pairs(tabButtons) do
		local isVisible = (name == "Statistics" or name == "Dev Console") and devEnabled or (TAB_VISIBILITY_SETTINGS[name] ~= false)
		btn.Visible = isVisible
		if dropdownItems[name] then dropdownItems[name].TextColor3 = toColor3(isVisible and THEME.Accent or THEME.Placeholder) end
	end

	if (not devEnabled and (activeTabName == "Statistics" or activeTabName == "Dev Console")) or TAB_VISIBILITY_SETTINGS[activeTabName] == false then
		switchTab("Console")
	end
end

local function createTabPage(name, canClose)
	canClose = (canClose == nil) and true or canClose

	local page = createUIElement("Frame", { Name = name .. "Page", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Visible = false, Parent = container })
	tabPages[name] = page

	local btn = createUIElement("TextButton", {
		Name = name .. "TabBtn", Size = UDim2.new(0, canClose and 105 or 80, 1, -4),
		BackgroundColor3 = toColor3(THEME.Header, THEME.Border), BorderSizePixel = 0, Text = "", Parent = tabBar
	})
	applyCorners(btn, UDim.new(0, 4))
	tabButtons[name] = btn

	createUIElement("TextLabel", {
		Name = "Title", Size = UDim2.new(1, canClose and -22 or 0, 1, 0), Position = UDim2.new(0, 8, 0, 0),
		BackgroundTransparency = 1, Text = name, TextColor3 = toColor3(THEME.Placeholder),
		Font = Enum.Font.GothamBold, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left, Parent = btn
	})

	createUIElement("Frame", {
		Name = "Indicator", Size = UDim2.new(1, 0, 0, 2), Position = UDim2.new(0, 0, 1, -2),
		BackgroundColor3 = toColor3(THEME.Accent), BorderSizePixel = 0, Visible = false, Parent = btn
	})

	if canClose then
		local closeBtn = createUIElement("TextButton", {
			Name = "CloseBtn", Size = UDim2.new(0, 16, 0, 16), Position = UDim2.new(1, -18, 0.5, -8),
			BackgroundTransparency = 1, Text = "×", TextColor3 = toColor3(THEME.Placeholder), Font = Enum.Font.GothamBold, TextSize = 12, Parent = btn
		})
		closeBtn.MouseButton1Click:Connect(function()
			TAB_VISIBILITY_SETTINGS[name] = false
			updateTabVisibilities()
		end)
	end

	local dropItem = createUIElement("TextButton", {
		Name = name .. "DropItem", Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Text = "  " .. name,
		TextColor3 = toColor3(THEME.Placeholder), Font = Enum.Font.Gotham, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 51, Parent = dropdownFrame
	})
	dropdownItems[name] = dropItem

	dropItem.MouseButton1Click:Connect(function()
		TAB_VISIBILITY_SETTINGS[name] = not (TAB_VISIBILITY_SETTINGS[name] ~= false)
		updateTabVisibilities()
	end)

	btn.MouseButton1Click:Connect(function() switchTab(name) end)
	return page
end

local consolePage = createTabPage("Console")
local waypointsPage = createTabPage("Waypoints")
local statsPage = createTabPage("Statistics")
local devConsolePage = createTabPage("Dev Console")
local settingsPage = createTabPage("Settings")

task.spawn(function()
	while screenGui.Parent do
		updateTabVisibilities()
		task.wait(0.25)
	end
end)

-- =========================================================
-- Console & Command Engine
-- =========================================================
createUIElement("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4), Parent = consolePage })

local consoleFilterBar = createUIElement("Frame", {
	Name = "FilterBar", Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 1, BackgroundColor3 = Color3.fromRGB(28, 28, 34), BorderSizePixel = 0, Parent = consolePage
})
applyCorners(consoleFilterBar, UDim.new(0, 4))

local searchBoxContainer = createUIElement("Frame", {
	Name = "SearchBoxContainer", Size = UDim2.new(1, -165, 1, -4), Position = UDim2.new(0, 2, 0, 2),
	BackgroundColor3 = Color3.fromRGB(20, 20, 24), BorderSizePixel = 0, Parent = consoleFilterBar
})
applyCorners(searchBoxContainer, UDim.new(0, 4))

local searchInput = createUIElement("TextBox", {
	Name = "SearchInput", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", PlaceholderText = "Search console logs...",
	TextColor3 = toColor3(THEME.Text), PlaceholderColor3 = toColor3(THEME.Placeholder), Font = Enum.Font.Gotham, TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false, Parent = searchBoxContainer
})
applyPadding(searchInput, 1, 1, 6, 6)

local consoleWrapper = createUIElement("Frame", {
	Name = "ConsoleWrapper", Size = UDim2.new(1, 0, 1, -65), LayoutOrder = 2, BackgroundTransparency = 1, ClipsDescendants = true, Parent = consolePage
})
local consoleFrame = buildScrollingConsole("ConsoleFrame", consoleWrapper)

local commandBarContainer = createUIElement("Frame", {
	Name = "CommandBarContainer", Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 3, BackgroundColor3 = Color3.fromRGB(30, 30, 35), BorderSizePixel = 0, Parent = consolePage
})
applyCorners(commandBarContainer)

local commandBar = createUIElement("TextBox", {
	Name = "CommandBar", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, TextColor3 = toColor3(THEME.Text),
	PlaceholderColor3 = toColor3(THEME.Placeholder), PlaceholderText = "Type a command...", Font = THEME.CommandFont or Enum.Font.Code,
	TextSize = THEME.CommandFontSize or 14, TextXAlignment = Enum.TextXAlignment.Left, Text = "", ClearTextOnFocus = false, Parent = commandBarContainer
})
applyPadding(commandBar, 2, 2, 8, 8)

local suggestionFrame = createUIElement("Frame", {
	Name = "SuggestionFrame", Size = UDim2.new(1, 0, 0, 0), Position = UDim2.new(0, 0, 0, -5), AnchorPoint = Vector2.new(0, 1),
	BackgroundColor3 = toColor3(THEME.Background), BorderSizePixel = 0, Visible = false, ZIndex = 50, Parent = commandBarContainer
})
applyCorners(suggestionFrame)
createUIElement("UIStroke", { Color = toColor3(THEME.Border), Thickness = 1, Parent = suggestionFrame })

local suggestionList = buildScrollingConsole("SuggestionList", suggestionFrame)
suggestionList.ZIndex = 51

local function applyConsoleFilters()
	for _, child in ipairs(consoleFrame:GetChildren()) do
		if child:IsA("TextBox") then
			local entryType = child:GetAttribute("LogType") or "info"
			local textMatch = (LOG_FILTER_STATE.SearchText == "") or (child.Text:lower():find(LOG_FILTER_STATE.SearchText:lower(), 1, true) ~= nil)
			local typeMatch = (entryType == "info" and LOG_FILTER_STATE.ShowInfo) or (entryType == "warn" and LOG_FILTER_STATE.ShowWarn) or (entryType == "error" and LOG_FILTER_STATE.ShowError)
			child.Visible = textMatch and typeMatch
		end
	end
end

searchInput:GetPropertyChangedSignal("Text"):Connect(function()
	LOG_FILTER_STATE.SearchText = searchInput.Text
	applyConsoleFilters()
end)

local function createFilterToggle(name, posX, initialVal, activeColor, stateKey)
	local toggleBtn = createUIElement("TextButton", {
		Name = name .. "Toggle", Size = UDim2.new(0, 50, 1, -4), Position = UDim2.new(1, posX, 0, 2),
		BackgroundColor3 = initialVal and activeColor or Color3.fromRGB(40, 40, 50),
		Text = name, TextColor3 = initialVal and Color3.new(1, 1, 1) or toColor3(THEME.Placeholder),
		Font = Enum.Font.GothamBold, TextSize = 10, Parent = consoleFilterBar
	})
	applyCorners(toggleBtn, UDim.new(0, 4))
	
	toggleBtn.MouseButton1Click:Connect(function()
		LOG_FILTER_STATE[stateKey] = not LOG_FILTER_STATE[stateKey]
		local newState = LOG_FILTER_STATE[stateKey]
		toggleBtn.BackgroundColor3 = newState and activeColor or Color3.fromRGB(40, 40, 50)
		toggleBtn.TextColor3 = newState and Color3.new(1, 1, 1) or toColor3(THEME.Placeholder)
		applyConsoleFilters()
	end)
end

createFilterToggle("Info", -160, LOG_FILTER_STATE.ShowInfo, toColor3(THEME.Accent), "ShowInfo")
createFilterToggle("Warn", -105, LOG_FILTER_STATE.ShowWarn, toColor3(THEME.Console_Warn), "ShowWarn")
createFilterToggle("Error", -50, LOG_FILTER_STATE.ShowError, toColor3(THEME.Console_Error), "ShowError")

local function applySuggestion(val)
	commandBar.Text = val
	suggestionFrame.Visible = false
	task.defer(function()
		commandBar.CursorPosition = #commandBar.Text + 1
		commandBar:CaptureFocus()
	end)
end

local function renderSuggestions()
	for _, child in ipairs(suggestionList:GetChildren()) do
		if child:IsA("TextButton") then child:Destroy() end
	end

	if #matches == 0 then suggestionFrame.Visible = false return end

	suggestionFrame.Visible = true
	local rowHeight = 24
	suggestionFrame.Size = UDim2.new(1, 0, 0, (math.min(#matches, 5) * rowHeight) + 8)

	for i, match in ipairs(matches) do
		local isSelected = (i == selectedIndex)
		local sugBtn = createUIElement("TextButton", {
			Name = "Sug_" .. match.Name, Size = UDim2.new(1, 0, 0, rowHeight - 2),
			BackgroundColor3 = isSelected and Color3.fromRGB(45, 45, 60) or Color3.fromRGB(25, 25, 30),
			BackgroundTransparency = isSelected and 0 or 0.5, Text = "  " .. match.Display,
			TextColor3 = isSelected and toColor3(THEME.Accent) or toColor3(THEME.SuggestionTextColor),
			Font = THEME.CommandFont or Enum.Font.Code, TextSize = THEME.SuggestionFontSize or 13,
			TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 52, Parent = suggestionList
		})
		applyCorners(sugBtn, UDim.new(0, 4))
		sugBtn.MouseButton1Click:Connect(function() applySuggestion(match.Value) end)
	end
end

local function updateSuggestions()
	local text = commandBar.Text
	matches = {}
	if text == "" then suggestionFrame.Visible = false return end

	local parts = string.split(text, " ")
	local inputCmd = parts[1]:lower()

	if #parts <= 1 then
		for name, cmd in pairs(commands) do
			if name:sub(1, #inputCmd) == inputCmd and cmd.Category ~= "Hidden" then
				local argsDisplay = (cmd.Arguments and #cmd.Arguments > 0) and (" " .. table.concat(cmd.Arguments, " ")) or ""
				table.insert(matches, { Name = cmd.Name, Display = cmd.Name .. argsDisplay, Value = cmd.Name .. " " })
			end
		end
		table.sort(matches, function(a, b) return a.Name < b.Name end)
	end

	if selectedIndex > #matches then selectedIndex = 1 end
	renderSuggestions()
end

UserInputService.InputBegan:Connect(function(input)
	if suggestionFrame.Visible and #matches > 0 then
		if input.KeyCode == Enum.KeyCode.Tab then
			applySuggestion(matches[selectedIndex].Value)
		elseif input.KeyCode == Enum.KeyCode.Down then
			selectedIndex = (selectedIndex % #matches) + 1
			renderSuggestions()
		elseif input.KeyCode == Enum.KeyCode.Up then
			selectedIndex = (selectedIndex - 2) % #matches + 1
			renderSuggestions()
		end
	end
end)

-- =========================================================
-- Tab Logic: Waypoints
-- =========================================================
createUIElement("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6), Parent = waypointsPage })

local waypointBar = createUIElement("Frame", {
	Name = "WaypointInputBar", Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = Color3.fromRGB(28, 28, 34), BorderSizePixel = 0, Parent = waypointsPage
})
applyCorners(waypointBar)

local waypointNameBox = createUIElement("TextBox", {
	Name = "WaypointNameBox", Size = UDim2.new(1, -110, 1, 0), BackgroundTransparency = 1, Text = "",
	PlaceholderText = "Enter waypoint name...", TextColor3 = toColor3(THEME.Text), PlaceholderColor3 = toColor3(THEME.Placeholder),
	Font = Enum.Font.Gotham, TextSize = 12, ClearTextOnFocus = false, Parent = waypointBar
})
applyPadding(waypointNameBox, 2, 2, 8, 8)

local addWaypointBtn = createUIElement("TextButton", {
	Name = "AddWaypointBtn", Size = UDim2.new(0, 100, 1, -4), Position = UDim2.new(1, -102, 0, 2),
	BackgroundColor3 = toColor3(THEME.Accent), Text = "+ Save Pos", TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold, TextSize = 11, Parent = waypointBar
})
applyCorners(addWaypointBtn)

local waypointsScroll = buildScrollingConsole("WaypointsScroll", waypointsPage)
waypointsScroll.Size = UDim2.new(1, 0, 1, -36)

local function refreshWaypointUI()
	for _, child in ipairs(waypointsScroll:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end

	for name, cfStr in pairs(WAYPOINTS) do
		local row = createUIElement("Frame", {
			Name = "WpRow_" .. name, Size = UDim2.new(1, -4, 0, 32), BackgroundColor3 = Color3.fromRGB(32, 32, 40), BorderSizePixel = 0, Parent = waypointsScroll
		})
		applyCorners(row)

		createUIElement("TextLabel", {
			Size = UDim2.new(0.4, 0, 1, 0), Position = UDim2.new(0, 10, 0, 0), BackgroundTransparency = 1,
			Text = name, TextColor3 = toColor3(THEME.Text), Font = Enum.Font.GothamBold, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, Parent = row
		})

		local function createWpBtn(text, posX, bg, callback)
			local btn = createUIElement("TextButton", {
				Size = UDim2.new(0, 50, 0, 22), Position = UDim2.new(1, posX, 0.5, -11),
				BackgroundColor3 = bg, Text = text, TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold, TextSize = 10, Parent = row
			})
			applyCorners(btn, UDim.new(0, 4))
			btn.MouseButton1Click:Connect(callback)
		end

		createWpBtn("Teleport", -170, toColor3(THEME.Accent), function()
			local char = localPlayer.Character
			if char then
				local coords = {}
				for val in cfStr:gmatch("[^,%s]+") do table.insert(coords, tonumber(val)) end
				if #coords >= 3 then
					local targetCF = CFrame.new(coords[1], coords[2], coords[3])
					if #coords >= 6 then targetCF = targetCF * CFrame.Angles(coords[4], coords[5], coords[6]) end
					char:PivotTo(targetCF)
				end
			end
		end)

		createWpBtn("Copy", -110, Color3.fromRGB(50, 50, 65), function() if setclipboard then setclipboard(cfStr) end end)

		createWpBtn("Delete", -55, toColor3(THEME.Console_Error), function()
			WAYPOINTS[name] = nil
			saveWaypointsToFile()
			refreshWaypointUI()
		end)
	end
end

addWaypointBtn.MouseButton1Click:Connect(function()
	local name = cleanStr(waypointNameBox.Text)
	local char = localPlayer.Character
	if name ~= "" and char then
		local cf = char:GetPivot()
		local rx, ry, rz = cf:ToEulerAnglesXYZ()
		WAYPOINTS[name] = string.format("%.2f, %.2f, %.2f, %.2f, %.2f, %.2f", cf.X, cf.Y, cf.Z, rx, ry, rz)
		saveWaypointsToFile()
		waypointNameBox.Text = ""
		refreshWaypointUI()
	end
end)

refreshWaypointUI()

-- =========================================================
-- Tab Logic: Statistics
-- =========================================================
local statsScroll = buildScrollingConsole("StatsPageScroll", statsPage)

createStatLabel("-- STATISTICS & SYSTEM PERFORMANCE --", statsScroll, true)
local fpsLabel = createStatLabel("FPS: --", statsScroll)
local avgFpsLabel = createStatLabel("Avg FPS: --", statsScroll)
local frameTimeLabel = createStatLabel("Frame Time: -- ms", statsScroll)
local pingLabel = createStatLabel("Ping: -- ms", statsScroll)
local avgPingLabel = createStatLabel("Avg Ping: -- ms", statsScroll)
local memoryLabel = createStatLabel("Mem: -- MB", statsScroll)
local physicsMemLabel = createStatLabel("Physics Mem: -- MB", statsScroll)

createDivider(statsScroll)
createStatLabel("Advanced Network & Hardware", statsScroll, true)
local packetLossLabel = createStatLabel("Packet Loss: --%", statsScroll)
local networkInLabel = createStatLabel("Data Recv: -- KB/s", statsScroll)
local networkOutLabel = createStatLabel("Data Sent: -- KB/s", statsScroll)

createDivider(statsScroll)
createStatLabel("Memory Breakdowns", statsScroll, true)
local luaHeapMemLabel = createStatLabel("Lua Heap: -- MB", statsScroll)
local textureMemLabel = createStatLabel("Texture Mem: -- MB", statsScroll)
local soundMemLabel = createStatLabel("Audio Mem: -- MB", statsScroll)
local guiMemLabel = createStatLabel("GUI Mem: -- MB", statsScroll)

createDivider(statsScroll)
createStatLabel("Server & Environment", statsScroll, true)
local gameNameLabel = createStatLabel("Game: --", statsScroll)
local gameIdLabel = createStatLabel("Place ID: --", statsScroll)
local jobIdLabel = createStatLabel("Job ID: --", statsScroll)
local playersCountLabel = createStatLabel("Players: --", statsScroll)
local maxPlayersLabel = createStatLabel("Max Players: --", statsScroll)
local serverTimeLabel = createStatLabel("Time: --", statsScroll)
local timeInGameLabel = createStatLabel("Session: --", statsScroll)
local serverLocLabel = createStatLabel("Server Region: --", statsScroll)

createDivider(statsScroll)
createStatLabel("Player Stats", statsScroll, true)
local teamLabel = createStatLabel("Team: --", statsScroll)
local posLabel = createStatLabel("Pos: --", statsScroll)
local rotLabel = createStatLabel("Rot: --", statsScroll)
local seatedLabel = createStatLabel("Seated: --", statsScroll)
local healthLabel = createStatLabel("Health: --", statsScroll)
local speedLabel = createStatLabel("WalkSpeed: --", statsScroll)
local actualSpeedLabel = createStatLabel("Actual Speed: --", statsScroll)

createDivider(statsScroll)
createStatLabel("Shell System State", statsScroll, true)
local shellRunningLabel = createStatLabel("Running: --", statsScroll)
local shellDevLabel = createStatLabel("Dev: --", statsScroll)
local shellThemeLabel = createStatLabel("Theme: --", statsScroll)

local compilerCommitLabel = createStatLabel("Compiler: Loading...", statsScroll)
createStatLabel("Loaded Compiler: " .. tostring(_G.ShellVersions["compiler"]), statsScroll)
local uiCommitLabel = createStatLabel("UI: Loading...", statsScroll)
createStatLabel("Loaded UI: " .. tostring(_G.ShellVersions["ui"]), statsScroll)
local functionCommitLabel = createStatLabel("FncMgr: Loading...", statsScroll)
createStatLabel("Loaded FncMgr: " .. tostring(_G.ShellVersions["fncmgr"]), statsScroll)

task.spawn(function()
	local cData = fetchLatestCommit("Core/compiler.lua")
	compilerCommitLabel.Text = string.format("Compiler: %s (%s)", cData.Date, cData.Message)

	local uiData = fetchLatestCommit("Core/ui.lua")
	uiCommitLabel.Text = string.format("UI: %s (%s)", uiData.Date, uiData.Message)

	local fData = fetchLatestCommit("Core/functions.lua")
	functionCommitLabel.Text = string.format("FncMgr: %s (%s)", fData.Date, fData.Message)
end)

task.spawn(function()
	local frameCount, lastTime, currentFps, lastFrameDelta = 0, os.clock(), 60, 0
	local sessionStartTime = os.clock()
	local fpsHistory, pingHistory, maxHistorySamples = {}, {}, 120
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

	RunService.RenderStepped:Connect(function(dt)
		frameCount += 1
		lastFrameDelta = dt
		local now = os.clock()
		if now - lastTime >= 1 then
			currentFps = math.floor(frameCount / (now - lastTime))
			frameCount, lastTime = 0, now
		end
	end)

	while screenGui.Parent do
		if statsPage.Visible then
			local now = os.clock()

			pcall(function()
				local net = Stats:FindFirstChild("Network")
				local serverStats = net and net:FindFirstChild("ServerStatsItem")
				local pingItem = serverStats and serverStats:FindFirstChild("Data Ping")
				local currentPing = pingItem and math.floor(pingItem:GetValue()) or 0

				table.insert(fpsHistory, currentFps)
				table.insert(pingHistory, currentPing)
				if #fpsHistory > maxHistorySamples then table.remove(fpsHistory, 1) end
				if #pingHistory > maxHistorySamples then table.remove(pingHistory, 1) end

				local sumFps, sumPing = 0, 0
				for _, v in ipairs(fpsHistory) do sumFps += v end
				for _, v in ipairs(pingHistory) do sumPing += v end

				fpsLabel.Text = string.format("FPS: %d", currentFps)
				avgFpsLabel.Text = string.format("Avg FPS: %d", #fpsHistory > 0 and math.floor(sumFps / #fpsHistory) or currentFps)
				frameTimeLabel.Text = string.format("Frame Time: %.2f ms", lastFrameDelta * 1000)
				pingLabel.Text = string.format("Ping: %d ms", currentPing)
				avgPingLabel.Text = string.format("Avg Ping: %d ms", #pingHistory > 0 and math.floor(sumPing / #pingHistory) or currentPing)
				memoryLabel.Text = string.format("Mem: %d MB", math.floor(Stats:GetTotalMemoryUsageMb()))
				physicsMemLabel.Text = string.format("Physics Mem: %d MB", math.floor(Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.PhysicsParts)))

				local lossItem = serverStats and serverStats:FindFirstChild("Data Loss")
				packetLossLabel.Text = string.format("Packet Loss: %d%%", lossItem and math.floor(lossItem:GetValue()) or 0)
				networkInLabel.Text = string.format("Data Recv: %d KB/s", math.floor(Stats.DataReceiveKbps or 0))
				networkOutLabel.Text = string.format("Data Sent: %d KB/s", math.floor(Stats.DataSendKbps or 0))
			end)

			pcall(function() luaHeapMemLabel.Text = string.format("Lua Heap: %d MB", math.floor(Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.Internal) or 0)) end)
			pcall(function() textureMemLabel.Text = string.format("Texture Mem: %d MB", math.floor(Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.Textures) or 0)) end)
			pcall(function() soundMemLabel.Text = string.format("Audio Mem: %d MB", math.floor(Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.Sounds) or 0)) end)
			pcall(function() guiMemLabel.Text = string.format("GUI Mem: %d MB", math.floor(Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.Gui) or 0)) end)

			pcall(function()
				gameNameLabel.Text = "Game: " .. gameName
				gameIdLabel.Text = "Place ID: " .. tostring(game.PlaceId)
				jobIdLabel.Text = "Job ID: " .. (game.JobId ~= "" and game.JobId:sub(1, 12) .. "..." or "Solo Studio")
				playersCountLabel.Text = "Players: " .. tostring(#Players:GetPlayers())
				maxPlayersLabel.Text = "Max Players: " .. tostring(Players.MaxPlayers)
				serverTimeLabel.Text = "Time: " .. os.date("%H:%M:%S")

				local elapsed = math.floor(now - sessionStartTime)
				timeInGameLabel.Text = string.format("Session: %02d:%02d:%02d", math.floor(elapsed / 3600), math.floor((elapsed % 3600) / 60), elapsed % 60)
				serverLocLabel.Text = "Server Region: " .. serverCountry
			end)

			pcall(function()
				teamLabel.Text = "Team: " .. (localPlayer and localPlayer.Team and localPlayer.Team.Name or "None")
				local char = localPlayer and localPlayer.Character
				local hum = char and char:FindFirstChildOfClass("Humanoid")

				if char then
					local pivot = char:GetPivot()
					local pos = pivot.Position
					local rx, ry, rz = pivot:ToOrientation()
					posLabel.Text = string.format("Pos: %d, %d, %d", math.round(pos.X), math.round(pos.Y), math.round(pos.Z))
					rotLabel.Text = string.format("Rot: %d°, %d°, %d°", math.round(math.deg(rx)), math.round(math.deg(ry)), math.round(math.deg(rz)))

					if lastPosition then
						local dt = now - lastPosTime
						actualSpeedLabel.Text = string.format("Actual Speed: %.1f", dt > 0 and ((pos - lastPosition).Magnitude / dt) or 0)
					end
					lastPosition, lastPosTime = pos, now
					seatedLabel.Text = "Seated: " .. tostring(hum and hum.Sit or false)
				end

				if hum then
					healthLabel.Text = string.format("HP: %d/%d", math.floor(hum.Health), math.floor(hum.MaxHealth))
					speedLabel.Text = string.format("WalkSpeed: %.1f", hum.WalkSpeed)
				end
			end)

			pcall(function()
				shellRunningLabel.Text = "Running: " .. tostring(_G.ShellRunning or false)
				shellDevLabel.Text = "Dev: " .. tostring(_G.ShellDev or false)
				shellThemeLabel.Text = "Theme: " .. tostring(_G.ShellTheme or "Default")
			end)
		end
		local freq = (_G.ShellSettings and _G.ShellSettings.Core and _G.ShellSettings.Core.DevStatsFrequency) or 0.25
		task.wait(freq)
	end
end)

-- =========================================================
-- Tab Logic: Dev Console & Settings
-- =========================================================
local devConsoleFrame = buildScrollingConsole("DevConsoleFrame", devConsolePage)
local settingsScroll = buildScrollingConsole("SettingsScroll", settingsPage)

local function createSettingDropdown(titleText, optionsList, currentIndex, isDisabled, callback)
	local row = createUIElement("Frame", { Size = UDim2.new(1, -10, 0, 32), BackgroundColor3 = Color3.fromRGB(30, 30, 36), BorderSizePixel = 0, Parent = settingsScroll })
	applyCorners(row)

	createUIElement("TextLabel", {
		Size = UDim2.new(1, -100, 1, 0), Position = UDim2.new(0, 10, 0, 0), BackgroundTransparency = 1,
		Text = titleText .. (isDisabled and " (Locked)" or ""), TextColor3 = isDisabled and Color3.fromRGB(130, 130, 130) or toColor3(THEME.Text),
		Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, Parent = row
	})

	local index = currentIndex or 1
	local dropdownBtn = createUIElement("TextButton", {
		Size = UDim2.new(0, 90, 0, 20), Position = UDim2.new(1, -100, 0.5, -10),
		BackgroundColor3 = isDisabled and Color3.fromRGB(40, 40, 40) or Color3.fromRGB(50, 50, 60),
		Text = tostring(optionsList[index] or "Select"), TextColor3 = isDisabled and Color3.fromRGB(150, 150, 150) or Color3.fromRGB(255, 255, 255),
		Font = Enum.Font.GothamBold, TextSize = 10, Parent = row
	})
	applyCorners(dropdownBtn, UDim.new(0, 6))

	if not isDisabled and type(optionsList) == "table" and #optionsList > 0 then
		dropdownBtn.MouseButton1Click:Connect(function()
			index = (index % #optionsList) + 1
			dropdownBtn.Text = tostring(optionsList[index])
			callback(optionsList[index], index)
		end)
	end
end

local function createSettingToggle(titleText, defaultState, isDisabled, callback)
	local row = createUIElement("Frame", { Size = UDim2.new(1, -10, 0, 32), BackgroundColor3 = Color3.fromRGB(30, 30, 36), BorderSizePixel = 0, Parent = settingsScroll })
	applyCorners(row)

	createUIElement("TextLabel", {
		Size = UDim2.new(1, -60, 1, 0), Position = UDim2.new(0, 10, 0, 0), BackgroundTransparency = 1,
		Text = titleText .. (isDisabled and " (Locked)" or ""), TextColor3 = isDisabled and Color3.fromRGB(130, 130, 130) or toColor3(THEME.Text),
		Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, Parent = row
	})

	local state = defaultState
	local toggleBtn = createUIElement("TextButton", {
		Size = UDim2.new(0, 40, 0, 20), Position = UDim2.new(1, -50, 0.5, -10),
		BackgroundColor3 = isDisabled and Color3.fromRGB(40, 40, 40) or (state and toColor3(THEME.Accent) or Color3.fromRGB(50, 50, 60)),
		Text = state and "ON" or "OFF", TextColor3 = isDisabled and Color3.fromRGB(150, 150, 150) or Color3.fromRGB(255, 255, 255),
		Font = Enum.Font.GothamBold, TextSize = 10, Parent = row
	})
	applyCorners(toggleBtn, UDim.new(0, 10))

	if not isDisabled then
		toggleBtn.MouseButton1Click:Connect(function()
			state = not state
			toggleBtn.Text = state and "ON" or "OFF"
			toggleBtn.BackgroundColor3 = state and toColor3(THEME.Accent) or Color3.fromRGB(50, 50, 60)
			callback(state)
		end)
	end
end

_G.ShellSettings = _G.ShellSettings or {}
_G.ShellSettings.Core = _G.ShellSettings.Core or {}

local function refreshSettingsUI()
	if not settingsScroll then return end
	for _, child in ipairs(settingsScroll:GetChildren()) do
		if child:IsA("Frame") or child:IsA("TextLabel") then child:Destroy() end
	end

	createStatLabel("-- GENERAL SETTINGS --", settingsScroll, true)
	createSettingToggle("Enable Dev Mode", _G.ShellDev or false, false, function(enabled)
		_G.ShellDev = enabled
		updateTabVisibilities()
	end)

	for settingName, defaultValue in pairs(_G.ShellSettings.Core) do
		if type(defaultValue) == "boolean" then
			createSettingToggle(settingName, defaultValue, false, function(enabled) _G.ShellSettings.Core[settingName] = enabled end)
		end
	end

	if _G.ShellSettings.Scripts and next(_G.ShellSettings.Scripts) then
		createStatLabel("-- SCRIPT SETTINGS --", settingsScroll, true)
		for cmdName, settingsTable in pairs(_G.ShellSettings.Scripts) do
			createStatLabel(cmdName, settingsScroll, true)
			if type(settingsTable) == "table" then
				for settingKey, settingOptions in pairs(settingsTable) do
					local titleText = cmdName .. ": " .. settingKey
					if type(settingOptions) == "boolean" then
						createSettingToggle(titleText, settingOptions, false, function(enabled) _G.ShellSettings.Scripts[cmdName][settingKey] = enabled end)
					elseif type(settingOptions) == "table" then
						local currentIndex = 1
						local currentVal = _G.ShellSettings.Scripts[cmdName][settingKey]
						if type(currentVal) == "string" then
							for i, opt in ipairs(settingOptions) do
								if opt == currentVal then currentIndex = i break end
							end
						end
						_G.ShellSettings.Scripts[cmdName][settingKey] = settingOptions[1]
						createSettingDropdown(titleText, settingOptions, currentIndex, false, function(selectedVal)
							_G.ShellSettings.Scripts[cmdName][settingKey] = selectedVal
						end)
					end
				end
			end
		end
	end

	createDivider(settingsScroll)
	createStatLabel("-- TAB VISIBILITY MENU --", settingsScroll, true)
	createSettingToggle("Console Tab", true, true, function() end)
	createSettingToggle("Waypoints Tab", _G.ShellSettings.Core.WaypointTabVis ~= false, false, function(enabled)
		_G.ShellSettings.Core.WaypointTabVis = enabled
		updateTabVisibilities()
	end)
	createSettingToggle("Settings Tab", true, true, function() end)
end

refreshSettingsUI()
switchTab("Console")

-- =========================================================
-- Dynamic Window Interaction Logic
-- =========================================================
local function setupEdgeResizing(targetFrame, minSize)
	minSize = minSize or Vector2.new(380, 220)
	local THICK = 6
	local resizing, activeDir, startFrameSize, startFramePos, startMousePos

	local handles = {
		Left = {Size = UDim2.new(0, THICK, 1, -THICK * 2), Pos = UDim2.new(0, -THICK / 2, 0, THICK)},
		Right = {Size = UDim2.new(0, THICK, 1, -THICK * 2), Pos = UDim2.new(1, -THICK / 2, 0, THICK)},
		Top = {Size = UDim2.new(1, -THICK * 2, 0, THICK), Pos = UDim2.new(0, THICK, 0, -THICK / 2)},
		Bottom = {Size = UDim2.new(1, -THICK * 2, 0, THICK), Pos = UDim2.new(0, THICK, 1, -THICK / 2)},
	}

	local handleFolder = targetFrame:FindFirstChild("ResizeHandles") or Instance.new("Folder", targetFrame)
	handleFolder.Name = "ResizeHandles"
	handleFolder:ClearAllChildren()

	for dir, config in pairs(handles) do
		local handle = createUIElement("TextButton", {
			Name = dir .. "Handle", Size = config.Size, Position = config.Pos, BackgroundTransparency = 1, Text = "", ZIndex = 20, Parent = handleFolder
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

setupEdgeResizing(mainFrame)

-- =========================================================
-- Logging Logic & Command Listener
-- =========================================================
local function shellLog(text, logTypeOrColor)
	local saveText = cleanStr(text)
	if saveText ~= "" then
		if appendfile then
			if not isfile(LOG_PATH) then writefile(LOG_PATH, "-- Start of Log --\n") end
			appendfile(LOG_PATH, saveText .. "\n")
		elseif writefile then
			local content = (isfile and isfile(LOG_PATH) and readfile(LOG_PATH)) or "-- Start of Log --"
			writefile(LOG_PATH, content .. "\n" .. saveText)
		end
	end

	local logColor, isDev, logCategory = THEME.Console_Info, false, "info"
	if typeof(logTypeOrColor) == "Color3" then
		logColor = logTypeOrColor
	elseif type(logTypeOrColor) == "string" then
		local lType = logTypeOrColor:lower()
		isDev = (lType == "developer")
		logCategory = (lType:find("warn") and "warn") or (lType:find("error") and "error") or "info"
		logColor = isDev and THEME.Accent or ({ error = THEME.Console_Error, warn = THEME.Console_Warn, warning = THEME.Console_Warn, success = THEME.Console_Success })[lType] or THEME[logTypeOrColor] or THEME.Console_Info
	end

	local targetConsole = isDev and devConsoleFrame or consoleFrame
	local logText = (_G.ShellSettings and _G.ShellSettings.Core and _G.ShellSettings.Core.Timestamps) and string.format("[%s] %s", os.date("%H:%M:%S"), tostring(text)) or tostring(text)

	local logEntry = createUIElement("TextBox", {
		Name = "LogEntry", BackgroundTransparency = 1, Size = UDim2.new(1, -10, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		Text = logText, TextColor3 = toColor3(logColor, THEME.Text), Font = THEME.ConsoleFont or Enum.Font.Code,
		TextSize = THEME.ConsoleFontSize or 14, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
		TextEditable = false, ClearTextOnFocus = false, Parent = targetConsole
	})
	logEntry:SetAttribute("LogType", logCategory)

	applyConsoleFilters()

	if _G.ShellSettings and _G.ShellSettings.Core and _G.ShellSettings.Core.AutoScroll then
		task.defer(function() targetConsole.CanvasPosition = Vector2.new(0, 100000) end)
	end
end

_G.ShellLog = shellLog
local function devlog(msg) if _G.ShellLog then _G.ShellLog("[Dev]: " .. msg, "developer") end end

shellLog("Shell UI Framework Loaded.", THEME.Accent)
shellLog("Press F2 or ' to toggle/focus visibility.", THEME.Placeholder)

local isMinimized = false

_G.ShellUIUpdate = function(newCommands)
	commands = newCommands or {}
	local count = 0; for _ in pairs(commands) do count += 1 end
	shellLog("Command map synchronized. (" .. count .. " entries)", THEME.Accent)
	pcall(refreshSettingsUI)
end

local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

minButton.MouseButton1Click:Connect(function()
	isMinimized = not isMinimized
	minButton.Text = isMinimized and "+" or "-"
	TweenService:Create(mainFrame, tweenInfo, { Size = UDim2.new(0, mainFrame.AbsoluteSize.X, 0, isMinimized and 32 or THEME.FrameSize.Y) }):Play()
	tabBar.Visible, container.Visible = not isMinimized, not isMinimized
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
		if mainFrame.Visible and activeTabName == "Console" then commandBar:CaptureFocus() else commandBar:ReleaseFocus() suggestionFrame.Visible = false end
	elseif input.KeyCode == Enum.KeyCode.Quote and not processed then
		mainFrame.Visible = true
		switchTab("Console")
		task.defer(function() commandBar.Text = ""; commandBar:CaptureFocus() end)
	end
end)

commandBar:GetPropertyChangedSignal("Text"):Connect(function()
	commandBar.Text = commandBar.Text:gsub("\t", ""):gsub("'", "")
	updateSuggestions()
end)

_G.ShellClearConsole = function()
	local targetConsole = (activeTabName == "Dev Console") and devConsoleFrame or consoleFrame
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
