_G.ShellVersions["ui"] = "Gamma (#2)"

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local HttpService = game:GetService("HttpService")
local LocalizationService = game:GetService("LocalizationService")
local MarketplaceService = game:GetService("MarketplaceService")
local Lighting = game:GetService("Lighting")
local TeleportService = game:GetService("TeleportService")
local VirtualUser = game:GetService("VirtualUser")

local localPlayer = Players.LocalPlayer

if _G.ShellUI then _G.ShellUI:Destroy() end

-- =========================================================
-- Constants & Theme State
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
	SuggestionFontSize = 14,
	FrameSize = Vector2.new(620, 450),
	UseUICorner = true,
	CustomTitle = "",
	BackgroundImage = "",
	BackgroundImageTransparency = 0.5,
	BackgroundImageScaleType = Enum.ScaleType.Stretch,
	BackgroundImageTileSize = UDim2.new(0, 32, 0, 32),
	TypingSound = "",
	EnterSound = "",
}

local SETTINGS = {
	AutoScroll = true,
	ShowTimestamps = true,
	SoundEnabled = true,
	DevStatsFrequency = 0.25,
}

local TAB_VISIBILITY_SETTINGS = {
	Console = true,
	Scripts = true,
	Waypoints = true,
	Settings = true,
}

local SCRIPT_STATES = {
	Fullbright = false,
	InfJump = false,
	Noclip = false,
	Fly = false,
	AntiAFK = false,
}

local LOG_FILTER_STATE = {
	SearchText = "",
	ShowInfo = true,
	ShowWarn = true,
	ShowError = true,
}

local WAYPOINTS = {}

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
	-- Fixed: Properly matches 3 numbers (R, G, B)
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
	return parseColor3(val) or (typeof(fallback) == "Color3" and fallback) or DEFAULT_TEXT_COLOR
end

local function autoParseValue(key, val)
	local lower = val:lower()
	if lower == "true" then return true end
	if lower == "false" then return false end

	local parsedColor = parseColor3(val)
	if parsedColor then return parsedColor end

	if tonumber(val) then return tonumber(val) end

	local clean = cleanStr(val)
	-- Fixed: Vector2/Dimensions only matched if color parsing failed and it's explicitly 2 numbers
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
		Size = UDim2.new(1, -6, 0, 1),
		BackgroundColor3 = toColor3(THEME.Border),
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
				msgStr = fullMsg:split("\n")[1]
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
-- Theme & Storage Logic
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

local function loadWaypointsFromFile()
	if isfile and readfile and isfile(WAYPOINTS_PATH) then
		local ok, decoded = pcall(function() return HttpService:JSONDecode(readfile(WAYPOINTS_PATH)) end)
		if ok and type(decoded) == "table" then
			WAYPOINTS = decoded
			return
		end
	end
	WAYPOINTS = {}
end

local function saveWaypointsToFile()
	if writefile then
		pcall(function() writefile(WAYPOINTS_PATH, HttpService:JSONEncode(WAYPOINTS)) end)
	end
end

loadWaypointsFromFile()

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
	if _G.ShellSettings.Core.Audio and assetId and assetId ~= "" then
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

createUIElement("UIStroke", {
	Color = toColor3(THEME.Border), Thickness = 1,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = mainFrame
})

local titleBar = createUIElement("Frame", {
	Name = "TitleBar", Size = UDim2.new(1, 0, 0, 32),
	BackgroundColor3 = toColor3(THEME.Header, THEME.Border), BorderSizePixel = 0, Parent = mainFrame
})
applyCorners(titleBar)

createUIElement("TextLabel", {
	Name = "TitleText", Size = UDim2.new(1, -50, 1, 0), Position = UDim2.new(0, 10, 0, 0),
	BackgroundTransparency = 1, Text = "Shell Console", TextColor3 = toColor3(THEME.Text),
	Font = Enum.Font.GothamBold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, Parent = titleBar
})

local minButton = createUIElement("TextButton", {
	Name = "MinimizeButton", Size = UDim2.new(0, 30, 1, 0), Position = UDim2.new(1, -30, 0, 0),
	BackgroundTransparency = 1, Text = "-", TextColor3 = toColor3(THEME.Text),
	Font = Enum.Font.GothamBold, TextSize = 16, Parent = titleBar
})

-- =========================================================
-- Tab Navigation Architecture
-- =========================================================
local tabBar = createUIElement("ScrollingFrame", {
	Name = "TabBar", Size = UDim2.new(1, -10, 0, 28),
	Position = UDim2.new(0, 5, 0, 35), BackgroundTransparency = 1,
	BorderSizePixel = 0, ScrollBarThickness = 2,
	ScrollBarImageColor3 = toColor3(THEME.Accent),
	AutomaticCanvasSize = Enum.AutomaticSize.X,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	Parent = mainFrame
})

createUIElement("UIListLayout", {
	SortOrder = Enum.SortOrder.LayoutOrder,
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 4),
	Parent = tabBar
})

local container = createUIElement("Frame", {
	Name = "Container", Size = UDim2.new(1, -10, 1, -72),
	Position = UDim2.new(0, 5, 0, 67), BackgroundTransparency = 1, Parent = mainFrame
})

local tabPages, tabButtons, activeTabName = {}, {}, "Console"

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

local tabPages = {}
local tabButtons = {}
local tabCloseButtons = {}
local dropdownItems = {}

-- Create Dropdown Menu as a child of the Main Frame/container so it renders nicely below the plus button
local dropdownFrame = createUIElement("Frame", {
	Name = "TabDropdownMenu",
	Size = UDim2.new(0, 130, 0, 0),
	Position = UDim2.new(1, -135, 0, 32),
	BackgroundColor3 = toColor3(THEME.Header, THEME.Border),
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 50,
	Parent = tabBar.Parent
})
applyCorners(dropdownFrame, UDim.new(0, 4))

local dropdownLayout = createUIElement("UIListLayout", {
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 2),
	Parent = dropdownFrame
})

-- Create '+' Tab at the far right
local plusBtn = createUIElement("TextButton", {
	Name = "PlusTabBtn", Size = UDim2.new(0, 30, 1, -4),
	BackgroundColor3 = toColor3(THEME.Header, THEME.Border),
	BorderSizePixel = 0, Text = "+", TextColor3 = toColor3(THEME.Placeholder),
	Font = Enum.Font.GothamBold, TextSize = 14, Parent = tabBar
})
applyCorners(plusBtn, UDim.new(0, 4))

plusBtn.MouseButton1Click:Connect(function()
	dropdownFrame.Visible = not dropdownFrame.Visible
	local itemCount = 0
	for _, _ in pairs(dropdownItems) do
		itemCount = itemCount + 1
	end
	dropdownFrame.Size = UDim2.new(0, 130, 0, (itemCount * 24) + 4)
end)

local function switchTab(targetName)
	activeTabName = targetName
	for name, page in pairs(tabPages) do
		local isTarget = (name == targetName)
		page.Visible = isTarget
		local btn = tabButtons[name]
		if btn then
			local title = btn:FindFirstChild("Title")
			if title then
				title.TextColor3 = toColor3(isTarget and THEME.Accent or THEME.Placeholder)
			end
			local ind = btn:FindFirstChild("Indicator")
			if ind then ind.Visible = isTarget end
		end
	end
end

local function createTabPage(name, canClose)
	canClose = (canClose ~= nil) and canClose or true

	local page = createUIElement("Frame", {
		Name = name .. "Page", Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1, Visible = false, Parent = container
	})
	tabPages[name] = page

	local btnWidth = canClose and 105 or 80
	local btn = createUIElement("TextButton", {
		Name = name .. "TabBtn", Size = UDim2.new(0, btnWidth, 1, -4),
		BackgroundColor3 = toColor3(THEME.Header, THEME.Border),
		BorderSizePixel = 0, Text = "", Parent = tabBar
	})
	applyCorners(btn, UDim.new(0, 4))
	tabButtons[name] = btn

	local textLabel = createUIElement("TextLabel", {
		Name = "Title", Size = UDim2.new(1, canClose and -22 or 0, 1, 0),
		Position = UDim2.new(0, 8, 0, 0), BackgroundTransparency = 1,
		Text = name, TextColor3 = toColor3(THEME.Placeholder),
		Font = Enum.Font.GothamBold, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
		Parent = btn
	})

	local indicator = createUIElement("Frame", {
		Name = "Indicator", Size = UDim2.new(1, 0, 0, 2),
		Position = UDim2.new(0, 0, 1, -2), BackgroundColor3 = toColor3(THEME.Accent),
		BorderSizePixel = 0, Visible = false, Parent = btn
	})

	if canClose then
		local closeBtn = createUIElement("TextButton", {
			Name = "CloseBtn", Size = UDim2.new(0, 16, 0, 16),
			Position = UDim2.new(1, -18, 0.5, -8), BackgroundTransparency = 1,
			Text = "×", TextColor3 = toColor3(THEME.Placeholder),
			Font = Enum.Font.GothamBold, TextSize = 12, Parent = btn
		})
		tabCloseButtons[name] = closeBtn

		closeBtn.MouseButton1Click:Connect(function()
			TAB_VISIBILITY_SETTINGS[name] = false
			updateTabVisibilities()
			if activeTabName == name then
				for otherName, p in pairs(tabPages) do
					if p.Visible and otherName ~= name then
						switchTab(otherName)
						break
					end
				end
			end
		end)
	end

	-- Dropdown Toggle Item
	local dropItem = createUIElement("TextButton", {
		Name = name .. "DropItem", Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1, Text = "  " .. name,
		TextColor3 = toColor3(THEME.Placeholder),
		Font = Enum.Font.Gotham, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 51,
		Parent = dropdownFrame
	})
	dropdownItems[name] = dropItem

	dropItem.MouseButton1Click:Connect(function()
		local currentState = TAB_VISIBILITY_SETTINGS[name] ~= false
		TAB_VISIBILITY_SETTINGS[name] = not currentState
		updateTabVisibilities()
	end)

	btn.MouseButton1Click:Connect(function()
		switchTab(name)
	end)

	return page, btn, indicator
end

local function updateTabVisibilities()
	local devEnabled = _G.ShellDev == true
	for name, btn in pairs(tabButtons) do
		local isVisible = true
		if name == "Statistics" or name == "Dev Console" then
			isVisible = devEnabled and (TAB_VISIBILITY_SETTINGS[name] ~= false)
		elseif TAB_VISIBILITY_SETTINGS[name] ~= nil then
			isVisible = TAB_VISIBILITY_SETTINGS[name]
		end
		
		btn.Visible = isVisible
		
		local dropItem = dropdownItems[name]
		if dropItem then
			dropItem.TextColor3 = toColor3(isVisible and THEME.Accent or THEME.Placeholder)
		end
	end

	if not devEnabled and (activeTabName == "Statistics" or activeTabName == "Dev Console") then
		switchTab("Console")
	elseif TAB_VISIBILITY_SETTINGS[activeTabName] == false then
		switchTab("Console")
	end
end

local consolePage, consoleBtn = createTabPage("Console")
local scriptsPage, scriptsBtn = createTabPage("Scripts")
local waypointsPage, waypointsBtn = createTabPage("Waypoints")
local statsPage, statsBtn = createTabPage("Statistics")
local devConsolePage, devConsoleBtn = createTabPage("Dev Console")
local settingsPage, settingsBtn = createTabPage("Settings")

task.spawn(function()
	while screenGui.Parent do
		updateTabVisibilities()
		task.wait(0.25)
	end
end)

-- ---------------------------------------------------------
-- TAB 1: CONSOLE & REWORKED AUTOCOMPLETE
-- ---------------------------------------------------------
createUIElement("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4), Parent = consolePage })

local consoleFilterBar = createUIElement("Frame", {
	Name = "FilterBar", Size = UDim2.new(1, 0, 0, 26),
	LayoutOrder = 1, BackgroundColor3 = Color3.fromRGB(28, 28, 34), BorderSizePixel = 0, Parent = consolePage
})
applyCorners(consoleFilterBar, UDim.new(0, 4))

local searchBoxContainer = createUIElement("Frame", {
	Name = "SearchBoxContainer", Size = UDim2.new(1, -165, 1, -4), Position = UDim2.new(0, 2, 0, 2),
	BackgroundColor3 = Color3.fromRGB(20, 20, 24), BorderSizePixel = 0, Parent = consoleFilterBar
})
applyCorners(searchBoxContainer, UDim.new(0, 4))

local searchInput = createUIElement("TextBox", {
	Name = "SearchInput", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
	Text = "", PlaceholderText = "Search console logs...", TextColor3 = toColor3(THEME.Text),
	PlaceholderColor3 = toColor3(THEME.Placeholder), Font = Enum.Font.Gotham, TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false, Parent = searchBoxContainer
})
applyPadding(searchInput, 1, 1, 6, 6)

local function createFilterToggle(name, posX, initialVal, activeColor, callback)
	local toggleBtn = createUIElement("TextButton", {
		Name = name .. "Toggle", Size = UDim2.new(0, 50, 1, -4), Position = UDim2.new(1, posX, 0, 2),
		BackgroundColor3 = initialVal and activeColor or Color3.fromRGB(40, 40, 50),
		Text = name, TextColor3 = initialVal and Color3.new(1, 1, 1) or toColor3(THEME.Placeholder),
		Font = Enum.Font.GothamBold, TextSize = 10, Parent = consoleFilterBar
	})
	applyCorners(toggleBtn, UDim.new(0, 4))
	
	toggleBtn.MouseButton1Click:Connect(function()
		local newState = callback()
		toggleBtn.BackgroundColor3 = newState and activeColor or Color3.fromRGB(40, 40, 50)
		toggleBtn.TextColor3 = newState and Color3.new(1, 1, 1) or toColor3(THEME.Placeholder)
	end)
end

local consoleWrapper = createUIElement("Frame", {
	Name = "ConsoleWrapper", Size = UDim2.new(1, 0, 1, -65),
	LayoutOrder = 2, BackgroundTransparency = 1, ClipsDescendants = true, Parent = consolePage
})

local consoleFrame = buildScrollingConsole("ConsoleFrame", consoleWrapper)

local commandBarContainer = createUIElement("Frame", {
	Name = "CommandBarContainer", Size = UDim2.new(1, 0, 0, 28),
	LayoutOrder = 3, BackgroundColor3 = Color3.fromRGB(30, 30, 35), BorderSizePixel = 0, Parent = consolePage
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

-- Rebuilt Autocomplete Menu Frame & State
local suggestionFrame = createUIElement("Frame", {
	Name = "SuggestionFrame", Size = UDim2.new(1, 0, 0, 0), Position = UDim2.new(0, 0, 0, -5),
	AnchorPoint = Vector2.new(0, 1), BackgroundColor3 = toColor3(THEME.Background),
	BorderSizePixel = 0, Visible = false, ZIndex = 50, Parent = commandBarContainer
})
applyCorners(suggestionFrame)
createUIElement("UIStroke", { Color = toColor3(THEME.Border), Thickness = 1, Parent = suggestionFrame })

local suggestionList = buildScrollingConsole("SuggestionList", suggestionFrame)
suggestionList.ZIndex = 51

local commands, matches, selectedIndex = {}, {}, 1

local function applyConsoleFilters()
	for _, child in ipairs(consoleFrame:GetChildren()) do
		if child:IsA("TextBox") then
			local entryType = child:GetAttribute("LogType") or "info"
			local textMatch = (LOG_FILTER_STATE.SearchText == "") or (child.Text:lower():find(LOG_FILTER_STATE.SearchText:lower(), 1, true) ~= nil)
			
			local typeMatch = false
			if entryType == "info" and LOG_FILTER_STATE.ShowInfo then typeMatch = true
			elseif entryType == "warn" and LOG_FILTER_STATE.ShowWarn then typeMatch = true
			elseif entryType == "error" and LOG_FILTER_STATE.ShowError then typeMatch = true
			end
			
			child.Visible = textMatch and typeMatch
		end
	end
end

searchInput:GetPropertyChangedSignal("Text"):Connect(function()
	LOG_FILTER_STATE.SearchText = searchInput.Text
	applyConsoleFilters()
end)

createFilterToggle("Info", -160, LOG_FILTER_STATE.ShowInfo, toColor3(THEME.Accent), function()
	LOG_FILTER_STATE.ShowInfo = not LOG_FILTER_STATE.ShowInfo
	applyConsoleFilters()
	return LOG_FILTER_STATE.ShowInfo
end)

createFilterToggle("Warn", -105, LOG_FILTER_STATE.ShowWarn, toColor3(THEME.Console_Warn), function()
	LOG_FILTER_STATE.ShowWarn = not LOG_FILTER_STATE.ShowWarn
	applyConsoleFilters()
	return LOG_FILTER_STATE.ShowWarn
end)

createFilterToggle("Error", -50, LOG_FILTER_STATE.ShowError, toColor3(THEME.Console_Error), function()
	LOG_FILTER_STATE.ShowError = not LOG_FILTER_STATE.ShowError
	applyConsoleFilters()
	return LOG_FILTER_STATE.ShowError
end)

-- Rebuilt Autocomplete Logic Engine
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

	if #matches == 0 then
		suggestionFrame.Visible = false
		return
	end

	suggestionFrame.Visible = true
	local rowHeight = 24
	local displayedCount = math.min(#matches, 5)
	suggestionFrame.Size = UDim2.new(1, 0, 0, (displayedCount * rowHeight) + 8)

	for i, match in ipairs(matches) do
		local isSelected = (i == selectedIndex)
		local sugBtn = createUIElement("TextButton", {
			Name = "Sug_" .. match.Name,
			Size = UDim2.new(1, 0, 0, rowHeight - 2),
			BackgroundColor3 = isSelected and Color3.fromRGB(45, 45, 60) or Color3.fromRGB(25, 25, 30),
			BackgroundTransparency = isSelected and 0 or 0.5,
			Text = "  " .. match.Display,
			TextColor3 = isSelected and toColor3(THEME.Accent) or toColor3(THEME.SuggestionTextColor),
			Font = THEME.CommandFont or Enum.Font.Code,
			TextSize = THEME.SuggestionFontSize or 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 52,
			Parent = suggestionList
		})
		applyCorners(sugBtn, UDim.new(0, 4))

		sugBtn.MouseButton1Click:Connect(function()
			applySuggestion(match.Value)
		end)
	end
end

local function updateSuggestions()
	local text = commandBar.Text
	matches = {}

	if text == "" then
		suggestionFrame.Visible = false
		return
	end

	local parts = string.split(text, " ")
	local inputCmd = parts[1]:lower()

	if #parts <= 1 then
		for name, cmd in pairs(commands) do
			if name:sub(1, #inputCmd) == inputCmd and cmd.Category ~= "Hidden" then
				local argsDisplay = (cmd.Arguments and #cmd.Arguments > 0) and (" " .. table.concat(cmd.Arguments, " ")) or ""
				table.insert(matches, {
					Name = cmd.Name,
					Display = cmd.Name .. argsDisplay,
					Value = cmd.Name .. " "
				})
			end
		end
		table.sort(matches, function(a, b) return a.Name < b.Name end)
	end

	if selectedIndex > #matches then selectedIndex = 1 end
	renderSuggestions()
end

UserInputService.InputBegan:Connect(function(input, processed)
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

-- ---------------------------------------------------------
-- TAB 2: SCRIPTS / QUICK ACTIONS
-- ---------------------------------------------------------
local scriptScroll = buildScrollingConsole("ScriptScroll", scriptsPage, nil, nil, true)
scriptScroll.Size = UDim2.new(1, 0, 1, 0)

createUIElement("UIGridLayout", {
	CellSize = UDim2.new(0, 142, 0, 32),
	CellPadding = UDim2.new(0, 6, 0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = scriptScroll
})

local quickScripts = {
	{ Name = "Clear Console", Action = function() if _G.ShellClearConsole then _G.ShellClearConsole() end end },
	{ Name = "Anti-AFK", Action = function()
		SCRIPT_STATES.AntiAFK = not SCRIPT_STATES.AntiAFK
		if SCRIPT_STATES.AntiAFK then
			localPlayer.Idled:Connect(function()
				if SCRIPT_STATES.AntiAFK then
					VirtualUser:CaptureController()
					VirtualUser:ClickButton2(Vector2.zero)
				end
			end)
		end
	end },
	{ Name = "Toggle Fly", Action = function()
		SCRIPT_STATES.Fly = not SCRIPT_STATES.Fly
		local char = localPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end

		if SCRIPT_STATES.Fly then
			local bv = Instance.new("BodyVelocity", hrp)
			bv.Name = "ShellFlyVelocity"
			bv.MaxForce = Vector3.new(1e9, 1e9, 1e9)
			bv.Velocity = Vector3.zero

			local bg = Instance.new("BodyGyro", hrp)
			bg.Name = "ShellFlyGyro"
			bg.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
			bg.CFrame = hrp.CFrame

			task.spawn(function()
				while SCRIPT_STATES.Fly and hrp:FindFirstChild("ShellFlyVelocity") do
					local cam = workspace.CurrentCamera
					local moveDir = Vector3.zero
					if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir += cam.CFrame.LookVector end
					if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir -= cam.CFrame.LookVector end
					if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir -= cam.CFrame.RightVector end
					if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir += cam.CFrame.RightVector end
					if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDir += Vector3.new(0, 1, 0) end
					if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then moveDir -= Vector3.new(0, 1, 0) end

					bv.Velocity = moveDir * 50
					bg.CFrame = cam.CFrame
					RunService.RenderStepped:Wait()
				end
				bv:Destroy()
				bg:Destroy()
			end)
		end
	end },
	{ Name = "FPS Booster", Action = function()
		for _, v in ipairs(workspace:GetDescendants()) do
			if v:IsA("BasePart") then
				v.Material = Enum.Material.SmoothPlastic
				v.Reflectance = 0
			elseif v:IsA("Decal") or v:IsA("Texture") then
				v:Destroy()
			elseif v:IsA("ParticleEmitter") or v:IsA("Trail") then
				v.Enabled = false
			end
		end
	end },
	{ Name = "FOV 120", Action = function() workspace.CurrentCamera.FieldOfView = 120 end },
	{ Name = "Reset FOV", Action = function() workspace.CurrentCamera.FieldOfView = 70 end },
	{ Name = "Click Teleport", Action = function()
		local mouse = localPlayer:GetMouse()
		local char = localPlayer.Character
		if char and mouse.Hit then char:PivotTo(mouse.Hit + Vector3.new(0, 3, 0)) end
	end },
	{ Name = "Copy CFrame", Action = function()
		local char = localPlayer.Character
		if char and setclipboard then setclipboard(tostring(char:GetPivot())) end
	end },
	{ Name = "Hop Small Server", Action = function()
		local api = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/0?sortOrder=Asc&limit=100"
		local ok, body = pcall(function() return game:HttpGet(api) end)
		if ok then
			local data = HttpService:JSONDecode(body)
			for _, server in ipairs(data.data) do
				if server.playing < server.maxPlayers and server.id ~= game.JobId then
					TeleportService:TeleportToPlaceInstance(game.PlaceId, server.id, localPlayer)
					break
				end
			end
		end
	end },
	{ Name = "Toggle Fullbright", Action = function()
		SCRIPT_STATES.Fullbright = not SCRIPT_STATES.Fullbright
		Lighting.Ambient = SCRIPT_STATES.Fullbright and Color3.new(1, 1, 1) or Color3.fromRGB(128, 128, 128)
		Lighting.Brightness = SCRIPT_STATES.Fullbright and 2 or 1
		Lighting.GlobalShadows = not SCRIPT_STATES.Fullbright
	end },
	{ Name = "Toggle Inf Jump", Action = function() SCRIPT_STATES.InfJump = not SCRIPT_STATES.InfJump end },
	{ Name = "Toggle Noclip", Action = function() SCRIPT_STATES.Noclip = not SCRIPT_STATES.Noclip end },
	{ Name = "Re-anchor Char", Action = function()
		local char = localPlayer.Character
		if char and char:FindFirstChild("HumanoidRootPart") then
			char.HumanoidRootPart.Anchored = true
			task.wait(0.2)
			char.HumanoidRootPart.Anchored = false
		end
	end },
	{ Name = "Reset Character", Action = function()
		local hum = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
		if hum then hum.Health = 0 end
	end },
	{ Name = "Copy Position", Action = function()
		local char = localPlayer.Character
		if char and setclipboard then
			local pos = char:GetPivot().Position
			setclipboard(string.format("%.2f, %.2f, %.2f", pos.X, pos.Y, pos.Z))
		end
	end },
	{ Name = "Copy Place ID", Action = function() if setclipboard then setclipboard(tostring(game.PlaceId)) end end },
	{ Name = "Copy Job ID", Action = function() if setclipboard then setclipboard(tostring(game.JobId)) end end },
	{ Name = "Remove Fog", Action = function()
		Lighting.FogEnd = 9e9
		for _, v in ipairs(Lighting:GetChildren()) do if v:IsA("Atmosphere") then v:Destroy() end end
	end },
	{ Name = "Speed +10", Action = function()
		local hum = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
		if hum then hum.WalkSpeed = hum.WalkSpeed + 10 end
	end },
	{ Name = "Speed Reset", Action = function()
		local hum = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
		if hum then hum.WalkSpeed = 16 end
	end },
	{ Name = "Jump +20", Action = function()
		local hum = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
		if hum then hum.JumpPower = hum.JumpPower + 20 end
	end },
	{ Name = "Jump Reset", Action = function()
		local hum = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
		if hum then hum.JumpPower = 50 end
	end },
	{ Name = "Unlock Camera", Action = function()
		localPlayer.CameraMaxZoomDistance, localPlayer.CameraMinZoomDistance = 100000, 0.5
		localPlayer.CameraMode = Enum.CameraMode.Classic
	end },
	{ Name = "Rejoin Server", Action = function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, localPlayer) end },
}

UserInputService.JumpRequest:Connect(function()
	if SCRIPT_STATES.InfJump then
		local hum = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
		if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
	end
end)

RunService.Stepped:Connect(function()
	if SCRIPT_STATES.Noclip and localPlayer.Character then
		for _, part in ipairs(localPlayer.Character:GetDescendants()) do
			if part:IsA("BasePart") and part.CanCollide then part.CanCollide = false end
		end
	end
end)

for _, scriptData in ipairs(quickScripts) do
	local btn = createUIElement("TextButton", {
		Name = scriptData.Name .. "Btn", BackgroundColor3 = Color3.fromRGB(32, 32, 40),
		Text = scriptData.Name, TextColor3 = toColor3(THEME.Text), Font = Enum.Font.Gotham, TextSize = 10, Parent = scriptScroll
	})
	applyCorners(btn)
	btn.MouseButton1Click:Connect(function() pcall(scriptData.Action) end)
end

-- ---------------------------------------------------------
-- TAB 3: WAYPOINTS
-- ---------------------------------------------------------
createUIElement("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6), Parent = waypointsPage })

local waypointBar = createUIElement("Frame", {
	Name = "WaypointInputBar", Size = UDim2.new(1, 0, 0, 30),
	BackgroundColor3 = Color3.fromRGB(28, 28, 34), BorderSizePixel = 0, Parent = waypointsPage
})
applyCorners(waypointBar)

local waypointNameBox = createUIElement("TextBox", {
	Name = "WaypointNameBox", Size = UDim2.new(1, -110, 1, 0), BackgroundTransparency = 1,
	Text = "", PlaceholderText = "Enter waypoint name...", TextColor3 = toColor3(THEME.Text),
	PlaceholderColor3 = toColor3(THEME.Placeholder), Font = Enum.Font.Gotham, TextSize = 12,
	ClearTextOnFocus = false, Parent = waypointBar
})
applyPadding(waypointNameBox, 2, 2, 8, 8)

local addWaypointBtn = createUIElement("TextButton", {
	Name = "AddWaypointBtn", Size = UDim2.new(0, 100, 1, -4), Position = UDim2.new(1, -102, 0, 2),
	BackgroundColor3 = toColor3(THEME.Accent), Text = "+ Save Pos", TextColor3 = Color3.new(1, 1, 1),
	Font = Enum.Font.GothamBold, TextSize = 11, Parent = waypointBar
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
			Name = "WpRow_" .. name, Size = UDim2.new(1, -4, 0, 32),
			BackgroundColor3 = Color3.fromRGB(32, 32, 40), BorderSizePixel = 0, Parent = waypointsScroll
		})
		applyCorners(row)

		createUIElement("TextLabel", {
			Size = UDim2.new(0.4, 0, 1, 0), Position = UDim2.new(0, 10, 0, 0),
			BackgroundTransparency = 1, Text = name, TextColor3 = toColor3(THEME.Text),
			Font = Enum.Font.GothamBold, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, Parent = row
		})

		local tpBtn = createUIElement("TextButton", {
			Size = UDim2.new(0, 55, 0, 22), Position = UDim2.new(1, -170, 0.5, -11),
			BackgroundColor3 = toColor3(THEME.Accent), Text = "Teleport", TextColor3 = Color3.new(1, 1, 1),
			Font = Enum.Font.GothamBold, TextSize = 10, Parent = row
		})
		applyCorners(tpBtn, UDim.new(0, 4))

		local copyBtn = createUIElement("TextButton", {
			Size = UDim2.new(0, 50, 0, 22), Position = UDim2.new(1, -110, 0.5, -11),
			BackgroundColor3 = Color3.fromRGB(50, 50, 65), Text = "Copy", TextColor3 = toColor3(THEME.Text),
			Font = Enum.Font.Gotham, TextSize = 10, Parent = row
		})
		applyCorners(copyBtn, UDim.new(0, 4))

		local delBtn = createUIElement("TextButton", {
			Size = UDim2.new(0, 50, 0, 22), Position = UDim2.new(1, -55, 0.5, -11),
			BackgroundColor3 = toColor3(THEME.Console_Error), Text = "Delete", TextColor3 = Color3.new(1, 1, 1),
			Font = Enum.Font.GothamBold, TextSize = 10, Parent = row
		})
		applyCorners(delBtn, UDim.new(0, 4))

		tpBtn.MouseButton1Click:Connect(function()
			local char = localPlayer.Character
			if char then
				local coords = {}
				for val in cfStr:gmatch("[^,%s]+") do table.insert(coords, tonumber(val)) end
				if #coords >= 3 then
					local targetCF = CFrame.new(coords[1], coords[2], coords[3])
					if #coords >= 6 then
						targetCF = CFrame.new(coords[1], coords[2], coords[3]) * CFrame.Angles(coords[4], coords[5], coords[6])
					end
					char:PivotTo(targetCF)
				end
			end
		end)

		copyBtn.MouseButton1Click:Connect(function()
			if setclipboard then setclipboard(cfStr) end
		end)

		delBtn.MouseButton1Click:Connect(function()
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

-- ---------------------------------------------------------
-- TAB 4: STATISTICS
-- ---------------------------------------------------------
local statsScroll = buildScrollingConsole("StatsPageScroll", statsPage)
statsScroll.Size = UDim2.new(1, 0, 1, 0)

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
local compilerLoadedLabel = createStatLabel("Loaded Compiler: ".._G.ShellVersions["compiler"], statsScroll)
local uiCommitLabel = createStatLabel("UI: Loading...", statsScroll)
local uiLoadedLabel = createStatLabel("Loaded UI: ".._G.ShellVersions["ui"], statsScroll)
local functionCommitLabel = createStatLabel("FncMgr: Loading...", statsScroll)
local functionLoadedLabel = createStatLabel("Loaded FncMgr: ".._G.ShellVersions["fncmgr"], statsScroll)

task.spawn(function()
	local compilerData = fetchLatestCommit("Core/compiler.lua")
	compilerCommitLabel.Text = string.format("Compiler: %s (%s)", compilerData.Date, compilerData.Message)

	local uiData = fetchLatestCommit("Core/ui.lua")
	uiCommitLabel.Text = string.format("UI: %s (%s)", uiData.Date, uiData.Message)

	local funcData = fetchLatestCommit("Core/functions.lua")
	functionCommitLabel.Text = string.format("FncMgr: %s (%s)", funcData.Date, funcData.Message)
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

			-- Performance & Ping
			pcall(function()
				local pingItem = Stats:FindFirstChild("Network") and Stats.Network:FindFirstChild("ServerStatsItem") and Stats.Network.ServerStatsItem:FindFirstChild("Data Ping")
				local currentPing = pingItem and math.floor(pingItem:GetValue()) or 0
				local currentMem = math.floor(Stats:GetTotalMemoryUsageMb())
				local physMem = math.floor(Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.PhysicsParts))

				table.insert(fpsHistory, currentFps)
				table.insert(pingHistory, currentPing)
				if #fpsHistory > maxHistorySamples then table.remove(fpsHistory, 1) end
				if #pingHistory > maxHistorySamples then table.remove(pingHistory, 1) end

				local sumFps, sumPing = 0, 0
				for _, v in ipairs(fpsHistory) do sumFps += v end
				for _, v in ipairs(pingHistory) do sumPing += v end
				local avgFps = #fpsHistory > 0 and math.floor(sumFps / #fpsHistory) or currentFps
				local avgPing = #pingHistory > 0 and math.floor(sumPing / #pingHistory) or currentPing

				fpsLabel.Text = string.format("FPS: %d", currentFps)
				avgFpsLabel.Text = string.format("Avg FPS: %d", avgFps)
				frameTimeLabel.Text = string.format("Frame Time: %.2f ms", lastFrameDelta * 1000)
				pingLabel.Text = string.format("Ping: %d ms", currentPing)
				avgPingLabel.Text = string.format("Avg Ping: %d ms", avgPing)
				memoryLabel.Text = string.format("Mem: %d MB", currentMem)
				physicsMemLabel.Text = string.format("Physics Mem: %d MB", physMem)
			end)

			-- Network
			pcall(function()
				local lossItem = Stats:FindFirstChild("Network") and Stats.Network:FindFirstChild("ServerStatsItem") and Stats.Network.ServerStatsItem:FindFirstChild("Data Loss")
				packetLossLabel.Text = string.format("Packet Loss: %d%%", lossItem and math.floor(lossItem:GetValue()) or 0)
				networkInLabel.Text = string.format("Data Recv: %d KB/s", math.floor(Stats.DataReceiveKbps or 0))
				networkOutLabel.Text = string.format("Data Sent: %d KB/s", math.floor(Stats.DataSendKbps or 0))
			end)

			-- Memory Tags (Individual pcalls to prevent memory tag errors from crashing downstream stats)
			pcall(function() luaHeapMemLabel.Text = string.format("Lua Heap: %d MB", math.floor(Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.Internal) or 0)) end)
			pcall(function() textureMemLabel.Text = string.format("Texture Mem: %d MB", math.floor(Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.Textures) or 0)) end)
			pcall(function() soundMemLabel.Text = string.format("Audio Mem: %d MB", math.floor(Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.Sounds) or 0)) end)
			pcall(function() guiMemLabel.Text = string.format("GUI Mem: %d MB", math.floor(Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.Gui) or 0)) end)

			-- Server & Environment
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

			-- Player Stats
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

			-- Shell State
			pcall(function()
				shellRunningLabel.Text = "Running: " .. tostring(_G.ShellRunning or false)
				shellDevLabel.Text = "Dev: " .. tostring(_G.ShellDev or false)
				shellThemeLabel.Text = "Theme: " .. tostring(_G.ShellTheme or "Default")
			end)
		end
		task.wait(_G.ShellSettings.Core.DevStatsFrequency or 0.25)
	end
end)

-- ---------------------------------------------------------
-- TAB 5: DEV CONSOLE
-- ---------------------------------------------------------
local devConsoleFrame = buildScrollingConsole("DevConsoleFrame", devConsolePage)
devConsoleFrame.Size = UDim2.new(1, 0, 1, 0)

-- ---------------------------------------------------------
-- TAB 6: SETTINGS
-- ---------------------------------------------------------
local settingsScroll = buildScrollingConsole("SettingsScroll", settingsPage)
settingsScroll.Size = UDim2.new(1, 0, 1, 0)

local function createSettingDropdown(titleText, optionsList, currentIndex, isDisabled, callback)
    local row = createUIElement("Frame", {
        Size = UDim2.new(1, -10, 0, 32),
        BackgroundColor3 = Color3.fromRGB(30, 30, 36),
        BorderSizePixel = 0, Parent = settingsScroll
    })
    applyCorners(row)

    createUIElement("TextLabel", {
        Size = UDim2.new(1, -100, 1, 0), Position = UDim2.new(0, 10, 0, 0),
        BackgroundTransparency = 1, Text = titleText .. (isDisabled and " (Locked)" or ""),
        TextColor3 = isDisabled and Color3.fromRGB(130, 130, 130) or toColor3(THEME.Text),
        Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, Parent = row
    })

    local index = currentIndex or 1
    local currentVal = optionsList[index] or "Select"

    local dropdownBtn = createUIElement("TextButton", {
        Size = UDim2.new(0, 90, 0, 20), Position = UDim2.new(1, -100, 0.5, -10),
        BackgroundColor3 = isDisabled and Color3.fromRGB(40, 40, 40) or Color3.fromRGB(50, 50, 60),
        Text = tostring(currentVal), TextColor3 = isDisabled and Color3.fromRGB(150, 150, 150) or Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.GothamBold, TextSize = 10, Parent = row
    })
    applyCorners(dropdownBtn, UDim.new(0, 6))

    if not isDisabled and type(optionsList) == "table" and #optionsList > 0 then
        dropdownBtn.MouseButton1Click:Connect(function()
            index = index + 1
            if index > #optionsList then
                index = 1
            end
            currentVal = optionsList[index]
            dropdownBtn.Text = tostring(currentVal)
            callback(currentVal, index)
        end)
    end
end

local function createSettingToggle(titleText, defaultState, isDisabled, callback)
    local row = createUIElement("Frame", {
        Size = UDim2.new(1, -10, 0, 32),
        BackgroundColor3 = Color3.fromRGB(30, 30, 36),
        BorderSizePixel = 0, Parent = settingsScroll
    })
    applyCorners(row)

    createUIElement("TextLabel", {
        Size = UDim2.new(1, -60, 1, 0), Position = UDim2.new(0, 10, 0, 0),
        BackgroundTransparency = 1, Text = titleText .. (isDisabled and " (Locked)" or ""),
        TextColor3 = isDisabled and Color3.fromRGB(130, 130, 130) or toColor3(THEME.Text),
        Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, Parent = row
    })

    local toggleBtn = createUIElement("TextButton", {
        Size = UDim2.new(0, 40, 0, 20), Position = UDim2.new(1, -50, 0.5, -10),
        BackgroundColor3 = isDisabled and Color3.fromRGB(40, 40, 40) or (defaultState and toColor3(THEME.Accent) or Color3.fromRGB(50, 50, 60)),
        Text = defaultState and "ON" or "OFF", TextColor3 = isDisabled and Color3.fromRGB(150, 150, 150) or Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.GothamBold, TextSize = 10, Parent = row
    })
    applyCorners(toggleBtn, UDim.new(0, 10))

    local state = defaultState
    if not isDisabled then
        toggleBtn.MouseButton1Click:Connect(function()
            state = not state
            toggleBtn.Text = state and "ON" or "OFF"
            toggleBtn.BackgroundColor3 = state and toColor3(THEME.Accent) or Color3.fromRGB(50, 50, 60)
            callback(state)
        end)
    end
end

-- Ensure global table exists
_G.ShellSettings = _G.ShellSettings or {}
_G.ShellSettings.Core = _G.ShellSettings.Core or {}

createStatLabel("-- GENERAL SETTINGS --", settingsScroll, true)

createSettingToggle("Enable Dev Mode", _G.ShellDev or false, false, function(enabled)
    _G.ShellDev = enabled
    updateTabVisibilities()
end)

-- Dynamically generate settings from _G.ShellSettings.Core
for settingName, defaultValue in pairs(_G.ShellSettings.Core) do
    if type(defaultValue) == "boolean" then
        createSettingToggle(settingName, defaultValue, false, function(enabled)
            _G.ShellSettings.Core[settingName] = enabled
        end)
    end
end

createDivider(settingsScroll)
createStatLabel("-- TAB VISIBILITY MENU --", settingsScroll, true)

createSettingToggle("Console Tab", true, true, function() end)

createSettingToggle("Scripts Tab", _G.ShellSettings.Core.ScriptTabVis ~= false, false, function(enabled)
    _G.ShellSettings.Core.ScriptTabVis = enabled
    updateTabVisibilities()
end)

createSettingToggle("Waypoints Tab", _G.ShellSettings.Core.WaypointTabVis ~= false, false, function(enabled)
    _G.ShellSettings.Core.WaypointTabVis = enabled
    updateTabVisibilities()
end)

createSettingToggle("Settings Tab", true, true, function() end)

local function refreshSettingsUI()
    if not settingsScroll then return end

    -- Remove previously generated dynamic elements (Frames, TextLabels, Dividers/UI objects) to prevent duplicates
    for _, child in ipairs(settingsScroll:GetChildren()) do
        if child:IsA("Frame") or child:IsA("TextLabel") then
            child:Destroy()
        end
    end

    -- Re-render General Settings header and toggles
    createStatLabel("-- GENERAL SETTINGS --", settingsScroll, true)
    
    createSettingToggle("Enable Dev Mode", _G.ShellDev or false, false, function(enabled)
        _G.ShellDev = enabled
        updateTabVisibilities()
    end)

    if _G.ShellSettings and _G.ShellSettings.Core then
        for settingName, defaultValue in pairs(_G.ShellSettings.Core) do
            if type(defaultValue) == "boolean" then
                createSettingToggle(settingName, defaultValue, false, function(enabled)
                    _G.ShellSettings.Core[settingName] = enabled
                end)
            end
        end
    end

    -- Re-render Command/Script specific settings from _G.ShellSettings.Scripts
    if _G.ShellSettings and _G.ShellSettings.Scripts and next(_G.ShellSettings.Scripts) ~= nil then
        createStatLabel("-- SCRIPT SETTINGS --", settingsScroll, true)

        for cmdName, settingsTable in pairs(_G.ShellSettings.Scripts) do
        	createStatLabel(cmdName, settingsScroll, true)
            if type(settingsTable) == "table" then
                for settingKey, settingOptions in pairs(settingsTable) do
                    local titleText = cmdName .. ": " .. settingKey
                    
                    if type(settingOptions) == "boolean" then
                        createSettingToggle(titleText, settingOptions, false, function(enabled)
                            _G.ShellSettings.Scripts[cmdName][settingKey] = enabled
                        end)
                    elseif type(settingOptions) == "table" then
                        local currentIndex = 1
                        -- Check if the current saved value matches one of the options to set the initial index
                        local currentVal = _G.ShellSettings.Scripts[cmdName][settingKey]
                        if type(currentVal) == "string" then
                            for i, opt in ipairs(settingOptions) do
                                if opt == currentVal then
                                    currentIndex = i
                                    break
                                end
                            end
                        end
						_G.ShellSettings.Scripts[cmdName][settingKey] = _G.ShellSettings.Scripts[cmdName][settingKey][1]
                        createSettingDropdown(titleText, settingOptions, currentIndex, false, function(selectedVal, newIndex)
                            _G.ShellSettings.Scripts[cmdName][settingKey] = selectedVal
                        end)
                    end
                end
            end
        end
    end
end

switchTab("Console")

-- Dynamic Edge Resizing
local function setupEdgeResizing(targetFrame, minSize)
	minSize = minSize or Vector2.new(380, 220)
	local THICK = 6
	local resizing, activeDir, startFrameSize, startFramePos, startMousePos

	local handles = {
		Left = {Size = UDim2.new(0, THICK, 1, -THICK*2), Pos = UDim2.new(0, -THICK/2, 0, THICK)},
		Right = {Size = UDim2.new(0, THICK, 1, -THICK*2), Pos = UDim2.new(1, -THICK/2, 0, THICK)},
		Top = {Size = UDim2.new(1, -THICK*2, 0, THICK), Pos = UDim2.new(0, THICK, 0, -THICK/2)},
		Bottom = {Size = UDim2.new(1, -THICK*2, 0, THICK), Pos = UDim2.new(0, THICK, 1, -THICK/2)},
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

setupEdgeResizing(mainFrame)

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

	local logColor, isDev, logCategory = THEME.Console_Info, false, "info"
	if typeof(logTypeOrColor) == "Color3" then
		logColor = logTypeOrColor
	elseif type(logTypeOrColor) == "string" then
		local lType = logTypeOrColor:lower()
		isDev = (lType == "developer")
		logCategory = (lType:find("warn") and "warn") or (lType:find("error") and "error") or "info"
		logColor = isDev and THEME.Accent or ({
			error = THEME.Console_Error,
			warn = THEME.Console_Warn, warning = THEME.Console_Warn,
			success = THEME.Console_Success
		})[lType] or THEME[logTypeOrColor] or THEME.Console_Info
	end

	local targetConsole = isDev and devConsoleFrame or consoleFrame
	local logText = _G.ShellSettings.Core.Timestamps and string.format("[%s] %s", os.date("%H:%M:%S"), tostring(text)) or tostring(text)

	local logEntry = createUIElement("TextBox", {
		Name = "LogEntry", BackgroundTransparency = 1, Size = UDim2.new(1, -10, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y, Text = logText,
		TextColor3 = toColor3(logColor, THEME.Text), Font = THEME.ConsoleFont or Enum.Font.Code,
		TextSize = THEME.ConsoleFontSize or 14, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
		TextEditable = false, ClearTextOnFocus = false, Parent = targetConsole
	})
	logEntry:SetAttribute("LogType", logCategory)

	applyConsoleFilters()

	if _G.ShellSettings.Core.AutoScroll then
		task.defer(function() targetConsole.CanvasPosition = Vector2.new(0, 100000) end)
	end
end

_G.ShellLog = shellLog
local function devlog(msg) if _G.ShellLog then _G.ShellLog("[Dev]: " .. msg, "developer") end end

shellLog("Shell UI Framework Loaded.", THEME.Accent)
shellLog("Press F2 or ' to toggle/focus visibility.", THEME.Placeholder)

local isMinimized, lastCommand = false, ""

_G.ShellUIUpdate = function(newCommands)
    commands = newCommands or {}
    local count = 0; for _ in pairs(commands) do count += 1 end
    shellLog("Command map synchronized. (" .. count .. " entries)", THEME.Accent)
    
    -- Refresh connected command settings in the UI if applicable
    if type(refreshSettingsUI) == "function" then
        pcall(refreshSettingsUI)
    end
end

local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

minButton.MouseButton1Click:Connect(function()
	isMinimized = not isMinimized
	minButton.Text = isMinimized and "+" or "-"
	TweenService:Create(mainFrame, tweenInfo, { Size = UDim2.new(0, mainFrame.AbsoluteSize.X, 0, isMinimized and 32 or THEME.FrameSize.Y) }):Play()
	tabBar.Visible = not isMinimized
	container.Visible = not isMinimized
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
