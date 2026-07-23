local functionsList = {}
local gameId = tostring(game.PlaceId)

local function devlog(msg)
    if _G.ShellLog then
        _G.ShellLog(msg, "developer")
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
        functionsList[result.Name:lower()] = result
    else
        -- Case 2: The file returned a container table (array or dictionary) of multiple commands
        for key, value in pairs(result) do
            if type(value) == "table" and value.Function then
                -- Fallback to the dictionary key if value.Name is missing
                local cmdName = value.Name or (type(key) == "string" and key)
                if cmdName and (value.Category ~= "_shelldev" or _G.ShellDev == true) then
                    value.Name = cmdName
                    functionsList[cmdName:lower()] = value
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

local function loadImportedCSV(csvPath)
    devlog("functions.lua -- Loading imported CSV: " .. csvPath)
    if not readfile or not isfile or not isfile(csvPath) then return end

    local success, content = pcall(readfile, csvPath)
    if not success or not content then return end

    for line in content:gmatch("[^\r\n]+") do
        -- Isolate each line entry inside its own pcall wrapper
        local lineSuccess, lineError = pcall(function()
            -- Trim whitespace and quote characters
            local url = line:match("^%s*[\"']?(.-)[\"']?%s*$")
            
            if url and url ~= "" and not url:find("^%s*#") then
                local rawScript = game:HttpGet(url)
                local compiledFunc, compileErr = loadstring(rawScript)
                
                if not compiledFunc then
                    error("Compile error: " .. tostring(compileErr))
                end
                devlog("functions.lua -- Processing imported functions: " .. url)
                local chunk = compiledFunc()
                processResult(chunk, "Imported")
            end
        end)

        if not lineSuccess then
            devlog("functions.lua -- Error processing CSV entry (" .. tostring(line) .. "): " .. tostring(lineError))
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

-- Load functions from Shell/Core/imported.csv
pcall(loadImportedCSV, "Shell/Core/imported.csv")

return functionsList