-- fuck me this will need to be remade at some point but im a lazy pos
local compiler = {Functions = {}}

_G.ShellVersions = {
    compiler = "Gamma #4",
    ui = "Gamma #2",
    fncmgr = "Gamma #1",
}
_G.ShellRunning = true
_G.ShellDev = false
_G.ShellTheme = _G.ShellTheme or "default"
_G.ShellKeybinds = _G.ShellKeybinds or {}
_G.ShellSettings = {
    Core = {
        AutoScroll = true,
        Timestamps = true,
        Audio = true,
        ScriptTabVis = true,
        WaypointTabVis = true,
        ConsoleTabVis = true,
        SettingsTabVis = true,
    },
    Scripts = {
    }
}

local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local HttpService = game:GetService("HttpService")

local BASE_URL = "https://raw.githubusercontent.com/generic-goose/Shell/refs/heads/main/"
local compilerPath = BASE_URL .. "Core/compiler.lua"
local funcPath = BASE_URL .. "Core/functions.lua"
local uiPath = BASE_URL .. "Core/ui.lua"

local CONFIG_PATH = "Shell/Core/config.json"

local function fetchRemote(url)
    local ok, res = pcall(function()
        return game:HttpGet(url)
    end)
    return ok and res or nil
end

local function checkFile(path) return isfile and isfile(path) end
local function checkFolder(path) return isfolder and isfolder(path) end

local function ensureFolder(path)
    if makefolder and isfolder and not isfolder(path) then
        pcall(makefolder, path)
    end
end

local function safeLoadString(code, chunkName)
    local fn, err = loadstring(code, chunkName)
    if not fn then
        return false, err
    end
    return pcall(fn)
end

local function showCoreNotification(title, text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title or "Notification",
            Text = text or "notification text :D",
            Duration = duration or 5
        })
    end)
end

local function logTo(prefix, msg, category)
    if _G.ShellLog then
        _G.ShellLog(prefix .. tostring(msg), category)
    else
        if category == "error" or category == "warn" then
            warn(prefix .. tostring(msg))
        else
            print(prefix .. tostring(msg))
        end
    end
end

local function log(msg) logTo("[Core]: ", msg, "default") end
local function logDev(msg) logTo("[Dev]: ", msg, "developer") end
local function logError(msg) logTo("[Core Error]: ", msg, "error") end
local function logWarn(msg) logTo("[Core Warn]: ", msg, "warn") end

local function parseCommandString(str)
    local args = {}
    for arg in str:gmatch("[^%s]+") do
        table.insert(args, arg)
    end
    return table.remove(args, 1), args
end

-- Config Management Functions for config.json
local cachedConfigData = nil

local function loadConfig()
    if not checkFile or not checkFile(CONFIG_PATH) then return end

    local success, content = pcall(readfile, CONFIG_PATH)
    if not success or not content or content == "" then return end

    local decodeSuccess, decoded = pcall(function()
        return HttpService:JSONDecode(content)
    end)

    if decodeSuccess and type(decoded) == "table" then
        cachedConfigData = decoded
    end
end

local function saveConfig()
    if not writefile then return end

    local encodeSuccess, encoded = pcall(function()
        return HttpService:JSONEncode(_G.ShellSettings or {})
    end)

    if encodeSuccess then
        writefile(CONFIG_PATH, encoded)
        if log then log("Configuration saved successfully.") end
    end
end

local function getLinesFromConfig(key)
    _G.ShellSettings = _G.ShellSettings or {}
    return _G.ShellSettings[key] or {}
end

local function toggleConfigEntry(key, value, tag)
    _G.ShellSettings = _G.ShellSettings or {}
    _G.ShellSettings[key] = _G.ShellSettings[key] or {}

    local foundIdx
    for i, line in ipairs(_G.ShellSettings[key]) do
        if line == value then
            foundIdx = i
            break
        end
    end

    if foundIdx then
        table.remove(_G.ShellSettings[key], foundIdx)
        if log then log("Removed '" .. tostring(value) .. "' from " .. tostring(tag) .. ".") end
    else
        table.insert(_G.ShellSettings[key], value)
        if log then log("Added '" .. tostring(value) .. "' to " .. tostring(tag) .. ".") end
    end

    saveConfig()
end

local function loadCoreModule(localPath, remoteUrl, chunkName)
    local localExists = checkFile(localPath)
    local localContent = localExists and readfile(localPath) or nil

    if localContent then
        log("Loading local module: " .. localPath)

        task.spawn(function()
            local remoteContent = fetchRemote(remoteUrl)
            if remoteContent then
                local localHash = hash and hash(localContent, "md5") or nil
                local remoteHash = hash and hash(remoteContent, "md5") or nil
                
                if (localHash and remoteHash and localHash ~= remoteHash) or (localContent ~= remoteContent) then
                    logWarn("Version mismatch detected for " .. chunkName .. "! Local file differs from latest GitHub version. Run 'download' to update.")
                end
            end
        end)

        return safeLoadString(localContent, chunkName)
    else
        log("Local module missing. Fetching remote in-memory: " .. remoteUrl)
        local remoteContent = fetchRemote(remoteUrl)
        if remoteContent then
            return safeLoadString(remoteContent, chunkName)
        else
            return false, "Failed to load code locally or from GitHub."
        end
    end
end

local function downloadRepositoryFiles()
    log("Downloading latest files from GitHub...")
    
    local coreFiles = {
        ["Core/compiler.lua"] = "Shell/Core/compiler.lua",
        ["Core/functions.lua"] = "Shell/Core/functions.lua",
        ["Core/ui.lua"] = "Shell/Core/ui.lua"
    }

    for remoteSubPath, localSubPath in pairs(coreFiles) do
        local content = fetchRemote(BASE_URL .. remoteSubPath)
        if content and writefile then
            writefile(localSubPath, content)
            log("Updated core file: " .. localSubPath)
        else
            logError("Failed to update: " .. localSubPath)
        end
    end

    local function fetchGithubDirectory(repoPath, localPath)
        local json = fetchRemote("https://api.github.com/repos/generic-goose/Shell/contents/" .. repoPath)
        if not json then return end

        local ok, items = pcall(function()
            return HttpService:JSONDecode(json)
        end)

        if ok and type(items) == "table" then
            for _, item in ipairs(items) do
                local targetPath = localPath .. "/" .. item.name
                if item.type == "file" and item.download_url then
                    local content = fetchRemote(item.download_url)
                    if content and writefile then 
                        writefile(targetPath, content)
                        log("Downloaded asset: " .. targetPath)
                    end
                elseif item.type == "dir" then
                    ensureFolder(targetPath)
                    fetchGithubDirectory(repoPath .. "/" .. item.name, targetPath)
                end
            end
        end
    end

    fetchGithubDirectory("Assets", "Shell/Assets")
    log("Download complete!")
end

local function loadShellAssets()
    for _, path in ipairs({
        "Shell", "Shell/Core", "Shell/Assets", 
        "Shell/Assets/Themes", "Shell/Games", "Shell/Functions"
    }) do
        ensureFolder(path)
    end

    if writefile then
        if not checkFile(CONFIG_PATH) then
            saveConfig({ imported = {}, autoexec = {} })
        end
    end
end

if not _G.ShellKeybindConnection then
    _G.ShellKeybindConnection = UserInputService.InputBegan:Connect(function(input, processed)
        if processed or input.UserInputType ~= Enum.UserInputType.Keyboard or not _G.ShellRunning then return end
        
        local boundLine = _G.ShellKeybinds[input.KeyCode.Name]
        if boundLine then
            local cmdName, args = parseCommandString(boundLine)
            local cmdData = _G.ShellFunctions and _G.ShellFunctions[cmdName]
            if cmdData and type(cmdData.Function) == "function" then
                local ok, err = pcall(cmdData.Function, unpack(args))
                if not ok then warn("[Shell Bind Error]: " .. tostring(err)) end
            end
        end
    end)
end

showCoreNotification("Shell", "Initializing...", 5)

function compiler.Refresh()
    compiler.Functions = {}
    
    local ok, funcModule = loadCoreModule("Shell/Core/functions.lua", funcPath, "functions.lua")
    if ok and type(funcModule) == "table" then
        for k, v in pairs(funcModule) do compiler.Functions[k] = v end
    else
        logError("Failed to load functions.lua: " .. tostring(funcModule))
    end

    local cmds = compiler.Functions
    
    cmds["setting"] = {
            Name = "setting", 
            Arguments = {"cmdname", "settingname", "value"}, 
            Category = "Core", 
            Desc = "Changes a setting value for a specified command script.",
            Function = function(cmdname,settingname,value)
                
                if not cmdname or not settingname or value == nil then
                    logWarn("Usage: setting <cmdname> <settingname> <value>", "Warn")
                    return
                end

                if value == "true" then value = true elseif value == "false" then value = false end
                
                if _G.ShellSettings and _G.ShellSettings.Scripts and _G.ShellSettings.Scripts[cmdname] then
                    _G.ShellSettings.Scripts[cmdname][settingname] = value
                    log("Successfully updated setting "..settingname.." in command "..cmdname.." to "..tostring(value), "Default")
                else
                    logWarn("Failed to update setting "..settingname.." in command "..cmdname.." to "..tostring(value), "Warn")
                end
            end
        }
        
    cmds["download"] = {
        Name = "download", Arguments = {}, Category = "Core", Desc = "Downloads the latest Shell Core files locally to your device for faster loading or for modified core versions. Please note locally saved files will take priority over new updates pushed to the GitHub, you will need to redownload the Core files each time an update is pushed.",
        Function = function()
            downloadRepositoryFiles()
            showCoreNotification("Shell", "Latest GitHub updates downloaded!", 5)
        end
    }

    cmds["exit"] = {
        Name = "exit", Arguments = {}, Category = "Core", Desc = "Exits the Shell script, closing any supporting loops, UIs, or systems. Note that in order for a loop to be closed when shell is exited, the loop must check Shell globals.",
        Function = function()
            _G.ShellRunning = false
            if _G.ShellUI then
                pcall(function() _G.ShellUI:Destroy() end)
                _G.ShellUI = nil
            end
            showCoreNotification("Shell", "Thanks for using the Shell, goodbye!", 5)
        end
    }

    cmds["gamegen"] = {
        Name = "gamegen", Arguments = {}, Category = "Core", Desc = "Generates a new script locally for the game you're playing, in 'Shell/Games/[GAME ID].lua'",
        Function = function()
            print("Generating script for game " .. tostring(game.PlaceId))
            local data = fetchRemote(BASE_URL .. "Assets/template.lua")
            local filePath = "Shell/Games/" .. game.PlaceId .. ".lua"
            if data then
                writefile(filePath, data)
            else
                warn("[Shell Setup]: Failed to download template.lua from GitHub")
                writefile(filePath, "-- Template failed to download: " .. BASE_URL .. "Assets/template.lua")
            end
        end
    }

    cmds["_shelldev"] = {
        Name = "_shelldev", Arguments = {}, Category = "Hidden", Desc = "Turns on Shell Developer mode, displaying debugging logs and statistics for easier scripting.",
        Function = function()
            _G.ShellDev = not _G.ShellDev
            logDev((_G.ShellDev and "Enabled" or "Disabled") .. " Shell Developer Mode")
            compiler.Refresh()
            showCoreNotification("Shell Developer", "Shell Developer Mode is now " .. (_G.ShellDev and "enabled" or "disabled") .. ".", 5)
        end
    }

    cmds["relaunch"] = {
        Name = "relaunch", Arguments = {}, Category = "Core", Desc = "Relaunches Shell, reloading all files, systems, functions, and loops.",
        Function = function()
            cmds["exit"].Function()
            showCoreNotification("Shell", "Relaunching shell...", 5)
            task.wait(0.5)
            local ok, err = loadCoreModule("Shell/Core/compiler.lua", compilerPath, "compiler.lua")
            if not ok then logError("Failed to load compiler.lua on relaunch: " .. tostring(err)) end
        end
    }

    cmds["clear"] = {
        Name = "clear", Arguments = {}, Category = "Core", Desc = "Clears the console, as well as the local log.txt file.",
        Function = function()
            if writefile then writefile("Shell/Core/log.txt", "-- Start of Log --") end
            if _G.ShellClearConsole then
                _G.ShellClearConsole()
            else
                logError("Global ShellClearConsole function not found.")
            end
        end
    }

    cmds["help"] = {
        Name = "help", Arguments = {"Category or Command (Optional)"}, Category = "Core", Desc = "Displays helpful information on commands and categories.",
        Function = function(query)
            log("=================== [ SHELL COMMANDS ] ===================")
            
            if query and query ~= "" then
                local targetCmd = cmds[query:lower()]
                if targetCmd and targetCmd.Category ~= "Hidden" then
                    local argsText = ""
                    if targetCmd.Arguments and #targetCmd.Arguments > 0 then
                        argsText = " <" .. table.concat(targetCmd.Arguments, "> <") .. ">"
                    end
                    
                    local description = targetCmd.Description or targetCmd.Desc or "No description provided."

                    log("Command: " .. targetCmd.Name .. argsText)
                    log("Category: " .. (targetCmd.Category or "Uncategorized"))
                    log("Description: " .. description)
                    log("==========================================================")
                    return
                end
            end

            local categories = {}
            for _, cmd in pairs(cmds) do
                if cmd.Category ~= "Hidden" then
                    local cat = cmd.Category or "Uncategorized"
                    categories[cat] = categories[cat] or {}
                    table.insert(categories[cat], cmd)
                end
            end

            if query and query ~= "" then
                local filtered = {}
                for catName, cmdList in pairs(categories) do
                    if catName:lower() == query:lower() then
                        filtered[catName] = cmdList
                    end
                end
                
                if next(filtered) == nil then
                    logError("No command or category matching '" .. query .. "' found.")
                    log("==========================================================")
                    return
                end
                categories = filtered
            end

            local sortedCatNames = {}
            for catName in pairs(categories) do table.insert(sortedCatNames, catName) end
            table.sort(sortedCatNames)

            for _, catName in ipairs(sortedCatNames) do
                local cmdList = categories[catName]
                table.sort(cmdList, function(a, b) return a.Name < b.Name end)

                log("[" .. catName:upper() .. "] (" .. #cmdList .. ")")
                
                for _, cmd in ipairs(cmdList) do
                    local argsText = ""
                    if cmd.Arguments and #cmd.Arguments > 0 then
                        argsText = " <" .. table.concat(cmd.Arguments, "> <") .. ">"
                    end
                    log(string.format("  • %s%s", cmd.Name, argsText))
                end
            end

            log("==========================================================")
            log("Tip: Use 'help <Category/Command>' to search.")
            log("Discord: https://discord.gg/jBW96MNauQ")
        end
    }

    cmds["refresh"] = { Name = "refresh", Arguments = {}, Category = "Core", Function = compiler.Refresh }

    cmds["theme"] = {
        Name = "theme", Arguments = {"ThemeName"}, Category = "Core",
        Function = function(themeName)
            if not themeName or themeName == "" then return "Current theme: " .. tostring(_G.ShellTheme) end
            if type(_G.SelectTheme) == "function" then
                log(_G.SelectTheme(themeName) and ("Theme changed to '" .. themeName .. "'.") or ("Failed to load theme '" .. themeName .. "'."))
            else
                logError("Error: Shell UI theme switcher not initialized.")
            end
        end
    }

    cmds["autoexec"] = {
        Name = "autoexec", Arguments = {"..."}, Category = "Core",
        Function = function(...)
            local args = {...}
            if #args == 0 then return logError("autoexec requires a command line string as an argument.") end
            toggleConfigEntry("autoexec", table.concat(args, " "):match("^%s*(.-)%s*$"), "autoexec sequence")
        end
    }

    cmds["import"] = {
        Name = "import", Arguments = {"URL"}, Category = "Core",
        Function = function(...)
            local args = {...}
            if #args == 0 then return logError("import requires a URL link as an argument.") end
            toggleConfigEntry("imported", table.concat(args, " "):match("^%s*(.-)%s*$"), "config.json (imported)")
        end
    }

    cmds["importlist"] = {
        Name = "importlist", Arguments = {}, Category = "Core",
        Function = function()
            log("--- Imported Commands List ---")
            for _, cmd in ipairs(getLinesFromConfig("imported")) do log("- " .. cmd) end
            log("------------------------------")
            log("This list is extensive to all currently loaded imported command modules.")
        end
    }

    cmds["autoexeclist"] = {
        Name = "autoexeclist", Arguments = {}, Category = "Core",
        Function = function()
            log("--- Autoexec List ---")
            for _, cmd in ipairs(getLinesFromConfig("autoexec")) do log("- " .. cmd) end
            log("---------------------")
            log("This list is extensive to all currently loaded auto executions.")
        end
    }

    cmds["bind"] = {
        Name = "bind", Arguments = {"Key", "Command..."}, Category = "Core",
        Function = function(keyName, ...)
            if not keyName then return logError("Usage: bind <Key> <Command>") end

            local targetKey
            for _, keyCode in ipairs(Enum.KeyCode:GetEnumItems()) do
                if keyCode.Name:lower() == keyName:lower() then
                    targetKey = keyCode
                    break
                end
            end

            if not targetKey then return logError("Invalid key name: '" .. tostring(keyName) .. "'") end

            local boundCommand = table.concat({...}, " "):match("^%s*(.-)%s*$")
            if boundCommand == "" or _G.ShellKeybinds[targetKey.Name] == boundCommand then
                _G.ShellKeybinds[targetKey.Name] = nil
                log("Unbound key [" .. targetKey.Name .. "]")
            else
                _G.ShellKeybinds[targetKey.Name] = boundCommand
                log("Bound [" .. targetKey.Name .. "] -> '" .. boundCommand .. "'")
            end
        end
    }

    cmds["binds"] = {
        Name = "binds", Arguments = {}, Category = "Core",
        Function = function()
            log("--- Active Keybinds ---")
            for key, cmd in pairs(_G.ShellKeybinds) do log("[" .. key .. "] -> '" .. cmd .. "'") end
            log("-----------------------")
        end
    }

    cmds["reloadui"] = {
        Name = "reloadui", Arguments = {}, Category = "Core",
        Function = function()
            local ok, err = loadCoreModule("Shell/Core/ui.lua", uiPath, "ui.lua")
            if not ok then logError("Failed to load ui.lua: " .. tostring(err)) end
            if _G.ShellUIUpdate then _G.ShellUIUpdate(compiler.Functions) end
        end
    }

    _G.ShellFunctions = compiler.Functions
    if _G.ShellUIUpdate then pcall(_G.ShellUIUpdate, compiler.Functions) end
    log("Environment compiled successfully.")
end

loadShellAssets()
compiler.Refresh()

local ok, err = loadCoreModule("Shell/Core/ui.lua", uiPath, "ui.lua")
if not ok then logError("Failed to load ui.lua: " .. tostring(err)) end

if _G.ShellUIUpdate then _G.ShellUIUpdate(compiler.Functions) end

local autoexecLines = getLinesFromConfig("autoexec")
if #autoexecLines > 0 then
    log("Running autoexec routine...")
    for _, line in ipairs(autoexecLines) do
        local cmdName, args = parseCommandString(line)
        task.spawn(function()
            local timeout = 10
            local startTime = os.clock()
            local cmdData = compiler.Functions[cmdName]
            while not (cmdData and type(cmdData.Function) == "function") do
                if os.clock() - startTime >= timeout then
                    logWarn("Autoexec timed out (10s): '" .. tostring(cmdName) .. "' was not registered in time.")
                    return
                end
                task.wait(0.1)
                cmdData = compiler.Functions[cmdName]
            end
            local ok, err = pcall(cmdData.Function, unpack(args))
            if ok then
                log("Autoexec ran successfully: " .. line)
            else
                logError("Autoexec failed for '" .. line .. "': " .. tostring(err))
            end
        end)
    end
end

showCoreNotification("Shell", "Done! Press F2 or ' to open Command Bar.", 5)
                                                                        
return compiler
