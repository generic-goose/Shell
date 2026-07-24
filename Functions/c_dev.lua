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

Functions["msginfo"] = {
    Name = "msginfo",
    Arguments = {},
    Category = "_shelldev",
    Function = function()
        logFunc("This is the default.", "default")
        logFunc("This is the warning.", "warn")
        logFunc("This is the error.", "error")
    end
}

Functions["debug"] = {
    Name = "debug",
    Arguments = {"FilePath"},
    Category = "_shelldev",
    Function = function(path)
        if path == nil or path == "" then
            devlog("Please specify a file path to debug.")
            return
        elseif path == "Core/compiler.lua" then
            devlog("Debugging compiler.lua could not be completed, would result in double processing for the Shell system.")
            return
        end
        local success, err = pcall(function()
            local func, loadErr = loadstring(readfile("Shell/" .. path))
            assert(func, loadErr) -- Throws the actual syntax error if loadstring failed
            return func()
        end)

        if not success then
            print("Script Error:", err)
        end
        if err then devlog("Debugged " .. path .. ": " .. tostring(err)) end
    end
}

-- Track active loops using task threads so they can be explicitly stopped
local activeLoopThread = nil
local activeLooping = false

--- Resolves a string path (e.g., "ReplicatedStorage.MyEvent" or "game:GetService('ReplicatedStorage').MyEvent") into an Instance.
local function getInstanceFromPath(pathStr)
    if typeof(pathStr) ~= "string" or pathStr == "" then 
        return nil 
    end

    local current = game

    -- Strip leading 'game.' or 'game:' if present
    pathStr = pathStr:gsub("^game[%.%:]", "")

    -- Split path by '.' or ':'
    for segment in pathStr:gmatch("[^%.%:]+") do
        if not current then return nil end

        -- Handle explicit GetService calls in path string: GetService("ServiceName")
        local serviceName = segment:match('GetService%s*%(%s*["\'](.-)["\']%s*%)')
        if serviceName then
            local success, service = pcall(function()
                return game:GetService(serviceName)
            end)
            current = success and service or nil
        else
            -- Standard child lookup
            current = current:FindFirstChild(segment)
        end
    end

    return current
end

--- Stops any currently running event loop safely
local function stopEventLoop()
    activeLooping = false
    if activeLoopThread then
        task.cancel(activeLoopThread)
        activeLoopThread = nil
    end
end

-- Command definition
Functions["loopevent"] = {
    Name = "loopevent",
    Arguments = {"eventPath", "..."},
    Category = "Automation",
    Function = function(...)
        local passed = {...}
        local args = typeof(passed[1]) == "table" and passed[1] or (typeof(passed[2]) == "table" and passed[2] or passed)

        -- If a loop is already running, calling the command again turns it OFF
        if activeLooping then
            stopEventLoop()
            logFunc("Eventloop disabled.")
            return
        end

        -- 1. Validate Event Path
        local rawPath = args[1]
        if not rawPath or rawPath == "" then
            logFunc("Event path is required to start loopevent.", "error")
            return
        end

        -- 2. Resolve Instance
        local eventInstance = getInstanceFromPath(rawPath)
        if not eventInstance or not eventInstance:IsA("RemoteEvent") then
            logFunc("Invalid RemoteEvent path: " .. tostring(rawPath), "error")
            return
        end

        -- 3. Gather remaining arguments
        local eventArgs = {}
        for i = 2, #args do
            table.insert(eventArgs, args[i])
        end

        -- 4. Start the loop thread cleanly
        activeLooping = true
        logFunc("Eventloop enabled for: " .. eventInstance:GetFullName())

        activeLoopThread = task.spawn(function()
            while activeLooping do
                eventInstance:FireServer(unpack(eventArgs))
                task.wait()
            end
        end)
    end
}

Functions["gameinfo"] = {
    Name = "gameinfo",
    Arguments = {},
    Category = "_shelldev",
    Function = function()
        logFunc("Game ID: " .. tostring(game.PlaceId), "default")
        logFunc("Job ID: " .. tostring(game.JobId), "default")
    end
}

Functions["dex"] = {
    Name = "dex",
    Arguments = {},
    Category = "Developer",
    Function = function()
        logFunc("Loading Dex Explorer...", "default")
        local success, err = pcall(function()
            loadstring(game:HttpGet("https://github.com/AZYsGithub/DexPlusPlus/releases/latest/download/out.lua"))()
        end)
        
        if not success then
            logFunc("Failed to load Dex: " .. tostring(err), "error")
        end
    end
}

Functions["cobalt"] = {
    Name = "cobalt",
    Arguments = {},
    Category = "Developer",
    Function = function()
        logFunc("Loading Dex Explorer...", "default")
        local success, err = pcall(function()
            loadstring(game:HttpGet("https://github.com/notpoiu/cobalt/releases/latest/download/Cobalt.luau"))()
        end)
        
        if not success then
            logFunc("Failed to load Dex: " .. tostring(err), "error")
        end
    end
}

return Functions
