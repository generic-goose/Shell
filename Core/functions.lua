local functionsList = {}
local gameId = tostring(game.PlaceId)
local CONFIG_PATH = "Shell/Core/config.json"

-- Ensure ShellSettings global table exists
_G.ShellSettings = _G.ShellSettings or {}
_G.ShellSettings.Core = _G.ShellSettings.Core or {
    Developer = false,
    AutoScroll = true,
    Timestamps = true,
    Audio = true,
    ScriptTabVis = true,
    WaypointTabVis = true,
    ConsoleTabVis = true,
    SettingsTabVis = true
}

local function devlog(msg)
    if _G.ShellLog then
        _G.ShellLog(msg, "developer")
    end
end

local function registerSettings(cmdName, value)
    if value and type(value.Settings) == "table" and cmdName then
        _G.ShellSettings.Scripts = _G.ShellSettings.Scripts or {}
        _G.ShellSettings.Scripts[cmdName] = value.Settings
    end
end

local function processResult(result, category)
    if type(result) ~= "table" then 
        devlog("functions.lua -- type(result) expected table, got "..tostring(type(result))) 
        return 
    end

    -- Case 1: The file directly returned a single command table (e.g., result.Name exists)
    if result.Name and result.Function then
        result.Category = result.Category or category
        local cmdName = result.Name
        functionsList[cmdName:lower()] = result
        registerSettings(cmdName, result)
    else
        -- Case 2: The file returned a container table (array or dictionary) of multiple commands
        for key, value in pairs(result) do
            if type(value) == "table" and value.Function then
                -- Fallback to the dictionary key if value.Name is missing
                local cmdName = value.Name or (type(key) == "string" and key)
                if cmdName and (value.Category ~= "_shelldev" or _G.ShellDev == true) then
                    value.Name = cmdName
                    functionsList[cmdName:lower()] = value
                    registerSettings(cmdName, value)
                end
            end
        end
    end
end

local function loadDirectory(dir, category)
    devlog("functions.lua -- Loading directory: " .. dir .. " with category: " .. category)
    if listfiles then
        local success, files = pcall(listfiles, dir)
        if not success or not files then 
            devlog("functions.lua -- expected success or files, got nil or error.") 
            return 
        end
        
        for _, filePath in ipairs(files) do
            if filePath:sub(-4) == ".lua" then
                local loadSuccess, chunk = pcall(function()
                    return loadstring(readfile(filePath))()
                end)
                
                if loadSuccess then
                    local cat = filePath:match("([^\\/]+)%.lua$") or filePath
                    devlog("functions.lua -- Processing file: " .. filePath .. " with category: " .. cat)
                    processResult(chunk, cat)
                end
            end
        end
    end
end

local function loadImportedConfig()
    devlog("functions.lua -- Loading imported URLs from " .. CONFIG_PATH)
    if not readfile or not isfile or not isfile(CONFIG_PATH) then return end

    local success, content = pcall(readfile, CONFIG_PATH)
    if not success or not content then return end

    local decodeSuccess, decoded = pcall(function()
        return game:GetService("HttpService"):JSONDecode(content)
    end)

    if not decodeSuccess or type(decoded) ~= "table" or not decoded.imported then
        return
    end

    for _, url in ipairs(decoded.imported) do
        local lineSuccess, lineError = pcall(function()
            local cleanUrl = tostring(url):match("^%s*[\"']?(.-)[\"']?%s*$")
            
            if cleanUrl and cleanUrl ~= "" and not cleanUrl:find("^%s*#") then
                local rawScript = game:HttpGet(cleanUrl)
                local compiledFunc, compileErr = loadstring(rawScript)
                
                if not compiledFunc then
                    error("Compile error: " .. tostring(compileErr))
                end
                devlog("functions.lua -- Processing imported functions: " .. cleanUrl)
                local chunk = compiledFunc()
                processResult(chunk, "Imported")
            end
        end)

        if not lineSuccess then
            devlog("functions.lua -- Error processing config import entry (" .. tostring(url) .. "): " .. tostring(lineError))
        end
    end
end

-- Load general functions
pcall(loadDirectory, "Shell/Functions", "Functions")

-- Load game-specific functions
if listfiles then
    local success, gameFiles = pcall(listfiles, "Shell/Games")
    if success and gameFiles then
        for _, filePath in ipairs(gameFiles) do
            local fileName = filePath:match("([^/\\]+)%.lua$")
            if fileName == gameId then
                local loadSuccess, chunk = pcall(function()
                    return loadstring(readfile(filePath))()
                end)
                
                if loadSuccess then
                    devlog("functions.lua -- Processing game-specific file: " .. filePath)
                    processResult(chunk, "Game (" .. gameId .. ")")
                end
            end
        end
    end
end

-- Load functions from config.json instead of imported.csv
pcall(loadImportedConfig)

return functionsList
