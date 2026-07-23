local compiler = {}
compiler.Functions = {}

_G.ShellRunning = true
_G.ShellDev = false
_G.ShellTheme = _G.ShellTheme or "default"
_G.ShellKeybinds = _G.ShellKeybinds or {}

local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

-- =========================================================
-- HELPER FUNCTIONS
-- =========================================================

local function showCoreNotification(title, text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title or "Notification",
            Text = text or "notification text :D",
            Duration = duration or 5
        })
    end)
end

local function logDev(msg)
    if _G.ShellLog then
        _G.ShellLog("[Dev]: " .. tostring(msg), "developer")
    end
end
local function devlog(msg)
    logDev(msg)
end

local function log(msg)
    if _G.ShellLog then
        _G.ShellLog("[Core]: " .. tostring(msg), "default")
    else
        print("[Core] (UI Log Missing): " .. tostring(msg))
    end
end

local function logWarn(msg)
    if _G.ShellLog then
        _G.ShellLog("[Core Warn]: " .. tostring(msg), "warn")
    else
        warn("[Core Warn] (UI Log Missing): " .. tostring(msg))
    end
end

local function logError(msg)
    if _G.ShellLog then
        _G.ShellLog("[Core Error]: " .. tostring(msg), "error")
    else
        warn("[Core Error] (UI Log Missing): " .. tostring(msg))
    end
end

local function parseCommandString(str)
    local arguments = {}
    for argument in string.gmatch(str, "[^%s]+") do
        table.insert(arguments, argument)
    end
    local cmdName = table.remove(arguments, 1)
    return cmdName, arguments
end

local function getAutoexecLines()
    if not isfile or not isfile("Shell/Core/autoexec.csv") then 
        return {} 
    end
    
    local content = readfile("Shell/Core/autoexec.csv")
    local lines = {}
    for line in string.gmatch(content, "[^\r\n]+") do
        local cleanLine = string.gsub(line, "^%s*(.-)%s*$", "%1")
        if cleanLine ~= "" then
            table.insert(lines, cleanLine)
        end
    end
    return lines
end

local function saveAutoexecLines(lines)
    if writefile then
        writefile("Shell/Core/autoexec.csv", table.concat(lines, "\n"))
    end
end

-- =========================================================
-- KEYBIND LISTENER
-- =========================================================

if not _G.ShellKeybindConnection then
    _G.ShellKeybindConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if input.UserInputType == Enum.UserInputType.Keyboard then
            local keyName = input.KeyCode.Name
            local boundLine = _G.ShellKeybinds[keyName]
            
            if boundLine and _G.ShellRunning then
                local cmdName, args = parseCommandString(boundLine)
                local cmdData = _G.ShellFunctions and _G.ShellFunctions[cmdName]
                
                if cmdData and type(cmdData.Function) == "function" then
                    local success, err = pcall(cmdData.Function, unpack(args))
                    if not success then
                        warn("[Shell Bind Error]: " .. tostring(err))
                    end
                end
            end
        end
    end)
end

showCoreNotification("Shell", "Initializing...", 5)

-- =========================================================
-- COMPILER REFRESH
-- =========================================================

function compiler.Refresh()
    compiler.Functions = {}
    
    if isfile and isfile("Shell/Core/functions.lua") then
        local success, funcModule = pcall(function()
            return loadstring(readfile("Shell/Core/functions.lua"))()
        end)
        
        if success and type(funcModule) == "table" then
            for k, v in pairs(funcModule) do
                compiler.Functions[k] = v
            end
        else
            logError("Failed to load functions.lua: " .. tostring(funcModule))
        end
    else
        logError("functions.lua not found")
    end
    
    -- CORE COMMAND REGISTRATION
    compiler.Functions["exit"] = {
        Name = "exit",
        Arguments = {},
        Category = "Core",
        Function = function()
            _G.ShellRunning = false
            if _G.ShellUI then
                pcall(function() _G.ShellUI:Destroy() end)
                _G.ShellUI = nil
            end
            showCoreNotification("Shell", "Thanks for using the Shell, goodbye!", 5)
        end
    }
    
    compiler.Functions["_shelldev"] = {
        Name = "_shelldev",
        Arguments = {},
        Category = "Hidden",
        Function = function()
            _G.ShellDev = not _G.ShellDev
            logDev((_G.ShellDev and "Enabled" or "Disabled") .." Shell Developer Mode")
            compiler.Refresh()
            showCoreNotification("Shell Developer", "Shell Developer Mode is now " .. (_G.ShellDev and "enabled" or "disabled") .. ".", 5)
        end
    }
    
    compiler.Functions["relaunch"] = {
        Name = "relaunch",
        Arguments = {},
        Category = "Core",
        Function = function()
            _G.ShellRunning = false
            if _G.ShellUI then
                pcall(function() _G.ShellUI:Destroy() end)
                _G.ShellUI = nil
            end
            showCoreNotification("Shell", "Relaunching shell...", 5)
            task.wait(0.5)
            local success, err = pcall(function() loadstring(readfile("Shell/Core/compiler.lua"))() end)
            if err then warn(err) end
        end
    }
    
    compiler.Functions["clear"] = {
        Name = "clear",
        Arguments = {},
        Category = "Core",
        Function = function()
            if _G.ShellClearConsole then
                _G.ShellClearConsole()
            else
                logError("Global ShellClearConsole function not found.")
            end
        end
    }
    
    compiler.Functions["help"] = {
        Name = "help",
        Arguments = {},
        Category = "Core",
        Function = function()
            log("--- Command List ---")
            local categorized = {}
            for _, cmd in pairs(compiler.Functions) do
                if cmd.Category ~= "Hidden" then
                    local cat = cmd.Category or "Uncategorized"
                    categorized[cat] = categorized[cat] or {}
                    table.insert(categorized[cat], cmd.Name)
                end
            end
            
            local sortedCategories = {}
            for cat in pairs(categorized) do
                table.insert(sortedCategories, cat)
            end
            table.sort(sortedCategories)
            
            for _, cat in ipairs(sortedCategories) do
                local cmds = categorized[cat]
                table.sort(cmds)
                log("[" .. cat .. " (" .. #cmds .. ")]: " .. table.concat(cmds, ", "))
            end
            log("--------------------")
            log("This list is extensive to all currently loaded commands. If you expected to see a command here, try using the 'refresh' command to refresh the list.")
        end
    }
    
    compiler.Functions["refresh"] = {
        Name = "refresh",
        Arguments = {},
        Category = "Core",
        Function = compiler.Refresh
    }

    compiler.Functions["theme"] = {
        Name = "theme",
        Arguments = {"ThemeName"},
        Category = "Core",
        Function = function(themeName)
            if not themeName or themeName == "" then
                return "Current theme: " .. tostring(_G.ShellTheme)
            end

            if type(_G.SelectTheme) == "function" then
                local success = _G.SelectTheme(themeName)
                if success then
                    log("Theme changed to '" .. themeName .. "'.")
                else
                    logError("Failed to load theme '" .. themeName .. "'.")
                end
            else
                logError("Error: Shell UI theme switcher not initialized.")
            end
        end
    }

    compiler.Functions["autoexec"] = {
        Name = "autoexec",
        Arguments = {"..."},
        Category = "Core",
        Function = function(...)
            local args = {...}
            if #args == 0 then
                logError("autoexec requires a command line string as an argument.")
                return
            end

            local fullLine = table.concat(args, " ")
            fullLine = string.gsub(fullLine, "^%s*(.-)%s*$", "%1")
            
            local lines = getAutoexecLines()
            local foundIndex = nil

            for i, line in ipairs(lines) do
                if line == fullLine then
                    foundIndex = i
                    break
                end
            end

            if foundIndex then
                table.remove(lines, foundIndex)
                log("Removed '" .. fullLine .. "' from autoexec sequence.")
            else
                table.insert(lines, fullLine)
                log("Added '" .. fullLine .. "' to autoexec sequence.")
            end

            saveAutoexecLines(lines)
        end
    }    
    
    compiler.Functions["import"] = {
        Name = "import",
        Arguments = {"URL"},
        Category = "Core",
        Function = function(...)
            local args = {...}
            if #args == 0 then
                logError("import requires a URL link as an argument.")
                return
            end

            local url = table.concat(args, " ")
            url = string.gsub(url, "^%s*(.-)%s*$", "%1")

            -- Helper function to read lines from imported.csv
            local function getImportedLines()
                local lines = {}
                local csvPath = "Shell/Core/imported.csv"
                
                if isfile and isfile(csvPath) then
                    local content = readfile(csvPath)
                    for line in content:gmatch("[^\r\n]+") do
                        local trimmed = string.gsub(line, "^%s*(.-)%s*$", "%1")
                        if trimmed ~= "" then
                            table.insert(lines, trimmed)
                        end
                    end
                end
                return lines
            end

            -- Helper function to save lines back to imported.csv
            local function saveImportedLines(lines)
                local csvPath = "Shell/Core/imported.csv"
                local content = table.concat(lines, "\n")
                if writefile then
                    writefile(csvPath, content)
                end
            end

            local lines = getImportedLines()
            local foundIndex = nil

            for i, line in ipairs(lines) do
                if line == url then
                    foundIndex = i
                    break
                end
            end

            if foundIndex then
                table.remove(lines, foundIndex)
                log("Removed '" .. url .. "' from imported.csv.")
            else
                table.insert(lines, url)
                log("Added '" .. url .. "' to imported.csv.")
            end

            saveImportedLines(lines)
        end
    }

    compiler.Functions["autoexeclist"] = {
        Name = "autoexeclist",
        Arguments = {},
        Category = "Core",
        Function = function()
            log("--- Autoexec List ---")
            local cmds = getAutoexecLines()
            for _, cmd in ipairs(cmds) do
                log("- " .. cmd)
            end
            log("---------------------")
            log("This list is extensive to all currently loaded auto executions.")
        end
    }

    compiler.Functions["bind"] = {
        Name = "bind",
        Arguments = {"Key", "Command..."},
        Category = "Core",
        Function = function(keyName, ...)
            if not keyName then
                logError("Usage: bind <Key> <Command>")
                return
            end

            local targetKey = nil
            for _, keyCode in ipairs(Enum.KeyCode:GetEnumItems()) do
                if string.lower(keyCode.Name) == string.lower(keyName) then
                    targetKey = keyCode
                    break
                end
            end

            if not targetKey then
                logError("Invalid key name: '" .. tostring(keyName) .. "'")
                return
            end

            local commandArgs = {...}
            local boundCommand = table.concat(commandArgs, " ")
            boundCommand = string.gsub(boundCommand, "^%s*(.-)%s*$", "%1")

            if boundCommand == "" or _G.ShellKeybinds[targetKey.Name] == boundCommand then
                _G.ShellKeybinds[targetKey.Name] = nil
                log("Unbound key [" .. targetKey.Name .. "]")
            else
                _G.ShellKeybinds[targetKey.Name] = boundCommand
                log("Bound [" .. targetKey.Name .. "] -> '" .. boundCommand .. "'")
            end
        end
    }

    compiler.Functions["binds"] = {
        Name = "binds",
        Arguments = {},
        Category = "Core",
        Function = function()
            log("--- Active Keybinds ---")
            for key, cmd in pairs(_G.ShellKeybinds) do
                log("[" .. key .. "] -> '" .. cmd .. "'")
            end
            log("-----------------------")
        end
    }
    
    -- Sync functions to global space
    _G.ShellFunctions = compiler.Functions
    
    if _G.ShellUIUpdate then
        pcall(function()
            _G.ShellUIUpdate(compiler.Functions)
        end)
    end
    log("Environment compiled successfully.")
end

-- =========================================================
-- INITIALIZATION SEQUENCE
-- =========================================================

-- 1. Register functions and publish to global memory
compiler.Refresh()

-- 2. Load UI layer FIRST (so UI globals like _G.SelectTheme exist)
if isfile and isfile("Shell/Core/ui.lua") then
    local success, err = pcall(function()
        loadstring(readfile("Shell/Core/ui.lua"))()
    end)
    if not success then
        logError("Failed to load ui.lua: " .. tostring(err))
    end
else
    logError("ui.lua not found")
end

-- Push commands to UI after it is initialized
if _G.ShellUIUpdate then
    _G.ShellUIUpdate(compiler.Functions)
end

-- 3. Process autoexec queue AFTER UI is ready
local autoexecLines = getAutoexecLines()
if #autoexecLines > 0 then
    log("Running autoexec routine...")
    for _, line in ipairs(autoexecLines) do
        local cmdName, args = parseCommandString(line)
        local cmdData = compiler.Functions[cmdName]
        
        if cmdData and type(cmdData.Function) == "function" then
            local success, err = pcall(cmdData.Function, unpack(args))
            if success then
                log("Autoexec ran successfully: " .. line)
            else
                logError("Autoexec failed for '" .. line .. "': " .. tostring(err))
            end
        else
            logWarn("Autoexec skipped: '" .. tostring(cmdName) .. "' is not a registered command.")
        end
    end
end

showCoreNotification("Shell", "Done! Press F2 or ' to open Command Bar.", 5)

return compiler