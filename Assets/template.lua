local Functions = {}

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

Functions["examplecmd"] = {
    Name = "examplecmd",
    Arguments = {},
    Category = "Hidden",
    Function = function()
        logFunc("This is the default.", "default")
        logFunc("This is the warning.", "warn")
        logFunc("This is the error.", "error")
    end
}

return Functions
