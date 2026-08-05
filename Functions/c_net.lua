local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local Functions = {}

--------------------------------------------------------------------------------
-- Unified Logger
--------------------------------------------------------------------------------
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

local function antiKickEnable()
    if getrawmetatable then
    	function formatargs(getArgs,v)
    		if #getArgs == 0 then 
    			return "" 
    		end
    		
    		local collectArgs = {}
    		for k,v in next,getArgs do
    			local argument = ""
    			if type(v) == "string" then
    				argument = "\""..v.."\""
    			elseif type(v) == "table" then
    				argument = "{" .. formatargs(v,true) .. "}"
    			else
    				argument = tostring(v)
    			end
    			if v and type(k) ~= "number" then
    				table.insert(collectArgs,k.."="..argument)
    			else
    				table.insert(collectArgs,argument)
    			end
    		end
    		return table.concat(collectArgs, ", ")
    	end
    	
    	kicknum = 0
    	local game_meta = getrawmetatable(game)
    	local game_namecall = game_meta.__namecall
    	local game_index = game_meta.__index
    	local w = (setreadonly or fullaccess or make_writeable)
    	pcall(w, game_meta, false)
    	game_meta.__namecall = function(out, ...)
    		local args = {...}
    		local Method = args[#args]
    		args[#args] = nil
    		
    		if Method == "Kick" and out == LP then
    			kicknum = kicknum + 1
    			warn("Blocked client-kick attempt "..kicknum)
    			return
    		end
    		
    		if antiremotes then
    			if Method == "FireServer" or Method == "InvokeServer" then
    				if out.Name ~= "CharacterSoundEvent" and out.Name ~= "SayMessageRequest" and out.Name ~= "AddCharacterLoadedEvent" and out.Name ~= "RemoveCharacterEvent" and out.Name ~= "DefaultServerSoundEvent" and out.Parent ~= "DefaultChatSystemChatEvents" then
    					warn("Blocked remote: "..out.Name.." // Method: "..Method)
    					return
    				end
    			end
    		else
    			if Method == "FireServer" or Method == "InvokeServer" then
    				for i,noremote in pairs(blockedremotes) do
    					if out.Name == noremote and out.Name ~= "SayMessageRequest" then
    						warn("Blocked remote: "..out.Name.." // Method: "..Method)
    						return
    					end
    				end
    			end
    		end
    		
    		if spyingremotes then
    			if Method == "FireServer" or Method == "InvokeServer" then
    				if out.Name ~= "CharacterSoundEvent" and out.Name ~= "AddCharacterLoadedEvent" and out.Name ~= "RemoveCharacterEvent" and out.Name ~= "DefaultServerSoundEvent" and out.Name ~= "SayMessageRequest" then
    					local arguments = {}
    					for i = 1,#args do
    						arguments[i] = args[i]
    					end
    					local getScript = getfenv(2).script
    					if getScript == nil then
    						getScript = "??? (Not Found) ???"
    					end
    					warn("<> <> <> A "..out.ClassName.." has been fired! How to fire:\ngame."..out:GetFullName()..":"..Method.."("..formatargs(arguments)..")\n\nFired from script: ".. tostring(getScript:GetFullName()))
    				end
    			end
    		end
    		
    		return game_namecall(out, ...)
    	end
    end
end

--------------------------------------------------------------------------------
-- Server Utility Commands
--------------------------------------------------------------------------------
Functions["rejoin"] = {
    Name = "rejoin",
    Arguments = {},
    Category = "Network",
    Function = function()
        local LocalPlayer = Players.LocalPlayer
        if not LocalPlayer then
            logFunc("Local player not found.", "error")
            return
        end

        logFunc("Rejoining the game...", "default")

        local placeId = game.PlaceId
        local jobId = game.JobId

        local success, err = pcall(function()
            if #Players:GetPlayers() <= 1 then
                TeleportService:Teleport(placeId, LocalPlayer)
            else
                TeleportService:TeleportToPlaceInstance(placeId, jobId, LocalPlayer)
            end
        end)

        if not success then
            logFunc("Failed to rejoin: " .. tostring(err), "error")
        end
    end
}

logFunc("Join the Shell Discord!\nhttps://discord.gg/jBW96MNauQ")
    
Functions["discord"] = {
    Name = "discord",
    Arguments = {},
    Category = "Shell",
    Function = function()
        logFunc("https://discord.gg/jBW96MNauQ", "default")
    end
}

local autoRejoin = false
Functions["autorejoin"] = {
    Name = "autorejoin",
    Arguments = {"Rejoin on 'exploit' or 'hack' detection. (T/F)"},
    Category = "Network",
    Function = function(chatDetect)
        autoRejoin = not autoRejoin
        logFunc("Auto rejoin toggled.", "default")
    
        local GuiService = game:GetService("GuiService")
        local Players = game:GetService("Players")
        local TeleportService = game:GetService("TeleportService")
        
        local player = LocalPlayer or Players.LocalPlayer
    
        local function rejoin()
            if player then
                TeleportService:Teleport(game.PlaceId, player)
            end
        end
        local function onErrorMessageChanged(errorMessage)
            if autoRejoin then
                if errorMessage and errorMessage ~= "" then
                    logFunc("Error detected: " .. errorMessage,"default")
                    task.wait()
                    rejoin()
                end
            end
        end
        GuiService.ErrorMessageChanged:Connect(onErrorMessageChanged)
        if chatDetect then
            local function onChatted(message)
                if string.find(string.lower(message), "hack") or string.find(string.lower(message), "exploit") or string.find(string.lower(message), "cheat") or string.find(string.lower(message), player.Name) then
                    logFunc("Rejoin trigger detected in chat.","default")
                    task.wait()
                    rejoin()
                end
            end
    
            local function hookPlayer(targetPlayer)
                targetPlayer.Chatted:Connect(onChatted)
            end
            for _, p in ipairs(Players:GetPlayers()) do
                hookPlayer(p)
            end
            Players.PlayerAdded:Connect(hookPlayer)
        end
    end
}
            
Functions["anticlientkick"] = {
    Name = "anticlientkick",
    Arguments = {},
    Category = "Network",
    Function = function()
        antiKickEnable()
        logFunc("Enabled AntiClientKick. (This cannot be disabled, rejoin to fix)", "default")
    end
}
                
return Functions
