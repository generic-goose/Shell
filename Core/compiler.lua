local compiler = {Functions = {}}

_G.ShellRunning = true
_G.ShellDev = false
_G.ShellTheme = _G.ShellTheme or "default"
_G.ShellKeybinds = _G.ShellKeybinds or {}

local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local HttpService = game:GetService("HttpService")

local BASE_URL = "https://raw.githubusercontent.com/generic-goose/Shell/refs/heads/main/"
local compilerPath = BASE_URL .. "Core/compiler.lua"
local funcPath = BASE_URL .. "Core/functions.lua"
local uiPath = BASE_URL .. "Core/ui.lua"

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

-- Non-blocking core module loader
local function loadCoreModule(localPath, remoteUrl, chunkName)
    local localExists = checkFile(localPath)
    local localContent = localExists and readfile(localPath) or nil

    if localContent then
        log("Loading local module: " .. localPath)

        -- Defer the web check to a background thread so execution is not blocked
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
        -- Fallback: If no local file exists, fetch from remote directly
        log("Local module missing. Fetching remote: " .. remoteUrl)
        local remoteContent = fetchRemote(remoteUrl)
        if remoteContent then
            if writefile then pcall(writefile, localPath, remoteContent) end
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
    local ready = checkFolder("Shell")
        and checkFolder("Shell/Assets")
        and checkFolder("Shell/Core")
        and checkFolder("Shell/Functions")
        and checkFolder("Shell/Games")
        and checkFolder("Shell/Assets/Themes")
        and checkFile("Shell/Assets/Themes/default.csv")
        and checkFile("Shell/Assets/Themes/shell.csv")
        and checkFile("Shell/Core/imported.csv")
        and checkFile("Shell/Core/autoexec.csv")
        and checkFile("Shell/Assets/example.lua")

    if ready then return end

    print("[Shell Setup]: Initializing missing workspace structure and assets...")

    for _, path in ipairs({
        "Shell", "Shell/Core", "Shell/Assets", 
        "Shell/Assets/Themes", "Shell/Games", "Shell/Functions"
    }) do
        ensureFolder(path)
    end

    if writefile then
        if not checkFile("Shell/Core/imported.csv") then
            local importedData = fetchRemote(BASE_URL .. "Core/imported.csv")
            writefile("Shell/Core/imported.csv", importedData or "")
        end
        if not checkFile("Shell/Core/autoexec.csv") then
            writefile("Shell/Core/autoexec.csv", "")
        end
    end

    downloadRepositoryFiles()
end

local function getLines(path)
    if not isfile or not checkFile(path) then return {} end
    local lines = {}
    for line in readfile(path):gmatch("[^\r\n]+") do
        local clean = line:match("^%s*(.-)%s*$")
        if clean ~= "" then table.insert(lines, clean) end
    end
    return lines
end

local function toggleCsvLine(path, value, tag)
    local lines = getLines(path)
    local foundIdx
    for i, line in ipairs(lines) do
        if line == value then
            foundIdx = i
            break
        end
    end

    if foundIdx then
        table.remove(lines, foundIdx)
        log("Removed '" .. value .. "' from " .. tag .. ".")
    else
        table.insert(lines, value)
        log("Added '" .. value .. "' to " .. tag .. ".")
    end

    if writefile then
        writefile(path, table.concat(lines, "\n"))
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

    cmds["download"] = {
        Name = "download", Arguments = {}, Category = "Core",
        Function = function()
            downloadRepositoryFiles()
            showCoreNotification("Shell", "Latest GitHub updates downloaded!", 5)
        end
    }

    cmds["exit"] = {
        Name = "exit", Arguments = {}, Category = "Core",
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
        Name = "gamegen", Arguments = {}, Category = "Core",
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
        Name = "_shelldev", Arguments = {}, Category = "Hidden",
        Function = function()
            _G.ShellDev = not _G.ShellDev
            logDev((_G.ShellDev and "Enabled" or "Disabled") .. " Shell Developer Mode")
            compiler.Refresh()
            showCoreNotification("Shell Developer", "Shell Developer Mode is now " .. (_G.ShellDev and "enabled" or "disabled") .. ".", 5)
        end
    }

    cmds["relaunch"] = {
        Name = "relaunch", Arguments = {}, Category = "Core",
        Function = function()
            cmds["exit"].Function()
            showCoreNotification("Shell", "Relaunching shell...", 5)
            task.wait(0.5)
            local ok, err = loadCoreModule("Shell/Core/compiler.lua", compilerPath, "compiler.lua")
            if not ok then logError("Failed to load compiler.lua on relaunch: " .. tostring(err)) end
        end
    }

    cmds["clear"] = {
        Name = "clear", Arguments = {}, Category = "Core",
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
        Name = "help", Arguments = {}, Category = "Core",
        Function = function()
            log("--- Command List ---")
            local categorized = {}
            for _, cmd in pairs(cmds) do
                if cmd.Category ~= "Hidden" then
                    local cat = cmd.Category or "Uncategorized"
                    categorized[cat] = categorized[cat] or {}
                    table.insert(categorized[cat], cmd.Name)
                end
            end

            local sortedCategories = {}
            for cat in pairs(categorized) do table.insert(sortedCategories, cat) end
            table.sort(sortedCategories)

            for _, cat in ipairs(sortedCategories) do
                local list = categorized[cat]
                table.sort(list)
                log("[" .. cat .. " (" .. #list .. ")]: " .. table.concat(list, ", "))
            end
            log("--------------------")
            log("This list is extensive to all currently loaded commands. If you expected to see a command here, try using the 'refresh' command to refresh the list.\n\nJoin the Shell Discord for more support.\nhttps://discord.gg/jBW96MNauQ")
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
            toggleCsvLine("Shell/Core/autoexec.csv", table.concat(args, " "):match("^%s*(.-)%s*$"), "autoexec sequence")
        end
    }

    cmds["import"] = {
        Name = "import", Arguments = {"URL"}, Category = "Core",
        Function = function(...)
            local args = {...}
            if #args == 0 then return logError("import requires a URL link as an argument.") end
            toggleCsvLine("Shell/Core/imported.csv", table.concat(args, " "):match("^%s*(.-)%s*$"), "imported.csv")
        end
    }

    cmds["autoexeclist"] = {
        Name = "autoexeclist", Arguments = {}, Category = "Core",
        Function = function()
            log("--- Autoexec List ---")
            for _, cmd in ipairs(getLines("Shell/Core/autoexec.csv")) do log("- " .. cmd) end
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

    _G.ShellFunctions = compiler.Functions
    if _G.ShellUIUpdate then pcall(_G.ShellUIUpdate, compiler.Functions) end
    log("Environment compiled successfully.")
end

loadShellAssets()
compiler.Refresh()

local ok, err = loadCoreModule("Shell/Core/ui.lua", uiPath, "ui.lua")
if not ok then logError("Failed to load ui.lua: " .. tostring(err)) end

if _G.ShellUIUpdate then _G.ShellUIUpdate(compiler.Functions) end

local autoexecLines = getLines("Shell/Core/autoexec.csv")
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
