-- Replay Player with WIND UI + Full Auth System
-- By: BantaiXmarV Team
-- Version: 2.5

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Load WIND UI
local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

-- Create Window
local Window = WindUI:CreateWindow({
    Title = "Bantaigunung | Replay Player",
    Icon = "rbxassetid://131136405062773",
    Author = "bantaigunung.my.id",
    Folder = "Bantai Gunung Replay",
    Size = UDim2.fromOffset(600, 380),
    MinSize = Vector2.new(560, 320),
    MaxSize = Vector2.new(950, 760),
    Transparent = true,
    Theme = "CottonCandy",
    Resizable = true,
    SideBarWidth = 190,
    BackgroundImageTransparency = 0.8,
    HideSearchBar = true,
    ScrollBarEnabled = true,
    Background = "rbxassetid://119914369911773",
    
    User = {
        Enabled = true,
        Anonymous = true,
        Callback = function() end,
    },
})

-- ========== PLAYBACK CONFIGURATION ==========
local STATE_CHANGE_COOLDOWN = 0.08

-- ========== VARIABLES ==========
local isAuthenticated = false
local replayData = {}
local isPlaying = false
local currentFrame = 1
local playbackSpeed = 1
local connection = nil
local JSON_URL = "https://raw.githubusercontent.com/Bardenss/FS/refs/heads/main/TESTER.json"

-- Playback state
local lastPlaybackState = nil
local lastStateChangeTime = 0
local frameTimeAccumulator = 0

-- Tab variables
local MainTab, SettingsTab, AboutTab
local statusParagraph, frameInfo, speedDropdown

-- ========== HELPER FUNCTIONS (AUTH) ==========

--  SESSION MANAGEMENT (1 Day Auto-Login)
local function saveSession(key, username, hwid, expiresAt)
    if not writefile or not readfile then return false end
    
    local sessionData = {
        key = key,
        username = username,
        hwid = hwid,
        expiresAt = expiresAt,
        savedAt = os.time()
    }
    
    local success = pcall(function()
        writefile("BantaiXmarV_Session.json", HttpService:JSONEncode(sessionData))
    end)
    
    return success
end

local function loadSession()
    if not readfile then return nil end
    
    local success, data = pcall(function()
        return readfile("BantaiXmarV_Session.json")
    end)
    
    if not success or not data then return nil end
    
    local parseSuccess, session = pcall(function()
        return HttpService:JSONDecode(data)
    end)
    
    if not parseSuccess or not session then return nil end
    
    -- Check if session expired (1 day = 86400 seconds)
    local sessionAge = os.time() - session.savedAt
    if sessionAge > 86400 then

        return nil
    end
    
    -- Check if key expired
    if session.expiresAt and session.expiresAt ~= "Lifetime" then
        local expiryTime = os.time({
            year = tonumber(session.expiresAt:sub(1, 4)),
            month = tonumber(session.expiresAt:sub(6, 7)),
            day = tonumber(session.expiresAt:sub(9, 10)),
            hour = tonumber(session.expiresAt:sub(12, 13)),
            min = tonumber(session.expiresAt:sub(15, 16)),
            sec = tonumber(session.expiresAt:sub(18, 19))
        })
        
        if os.time() > expiryTime then
            return nil
        end
    end
    
        return session
end

local function clearSession()
    if not delfile then return false end
    
    local success = pcall(function()
        delfile("BantaiXmarV_Session.json")
    end)
    
    return success
end

--  HTTP REQUEST BYPASS for blocked executors
local request_fn = 
    (syn and syn.request) or 
    (http and http.request) or 
    (http_request) or 
    (fluxus and fluxus.request) or
    (request)

local function makeAuthRequest(url)
    -- Method 1: Custom request (works for most executors)
    if request_fn then
        local success, response = pcall(function()
            return request_fn({
                Url = url,
                Method = "GET",
                Headers = {
                    ["User-Agent"] = "Roblox/WinInet",
                    ["Content-Type"] = "application/json"
                }
            })
        end)
        
        if success and response then
            return true, response
        end
    end
    
    -- Method 2: HttpService fallback
    local success2, response2 = pcall(function()
        return HttpService:RequestAsync({
            Url = url,
            Method = "GET",
            Headers = {
                ["User-Agent"] = "BantaiXmarV-Auth/1.0"
            }
        })
    end)
    
    if success2 and response2 then
        return true, response2
    end
    
    -- Method 3: game:HttpGet fallback
    local success3, body = pcall(function()
        return game:HttpGet(url)
    end)
    
    if success3 and body then
        return true, {
            StatusCode = 200,
            Body = body,
            Success = true
        }
    end
    
    return false, "All request methods failed"
end

local function trim(s)
    if not s or s == "" then return "" end
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local function KickPlayer(reason)
    local player = game.Players.LocalPlayer
    local kickMessage = string.format(
        "\n BantaiXmarV Authentication Failed\n\n" ..
        "Reason: %s\n" ..
        "Key/Token Buy in https://dsc.gg/BantaiXmarV",
        reason
    )
    
    task.wait(0.5)
    pcall(function()
        player:Kick(kickMessage)
    end)
end

local function GetHWID()
    local hwid = "UNKNOWN"
    local method = "Not Detected"
    local player = game.Players.LocalPlayer
    
    -- Try gethwid()
    if typeof(gethwid) == "function" then
        local success, result = pcall(gethwid)
        if success and result then
            hwid = tostring(result)
            method = "gethwid()"
            return hwid, method
        end
    end
    
    -- Try Synapse
    if syn and typeof(syn.get_hwid) == "function" then
        local success, result = pcall(syn.get_hwid)
        if success and result then
            hwid = tostring(result)
            method = "syn.get_hwid()"
            return hwid, method
        end
    end
    
    -- Try RbxAnalytics
    local success, clientId = pcall(function()
        return game:GetService("RbxAnalyticsService"):GetClientId()
    end)
    if success and clientId and clientId ~= "" then
        hwid = tostring(clientId)
        method = "RbxAnalytics"
        return hwid, method
    end
    
    -- Get executor name
    if typeof(getexecutorname) == "function" then
        local success, execName = pcall(getexecutorname)
        if success and execName then
            method = "Executor: " .. tostring(execName)
        end
    end
    
    -- Fallback
    if hwid == "UNKNOWN" then
        hwid = "FALLBACK-" .. tostring(player.UserId) .. "-" .. game.JobId
        method = "UserID+JobId Fallback"
    end
    
    return hwid, method
end

-- ========== PLAYBACK HELPER FUNCTIONS ==========

local function GetFrameCFrame(frame, humanoid)
    if not frame then return CFrame.new() end
    
    local y = frame.Position[2]
    if frame.HipHeight and humanoid then
        local recordedHipHeight = frame.HipHeight
        local currentHipHeight = humanoid.HipHeight
        local offset = currentHipHeight - recordedHipHeight
        y = y + offset
        
        if currentFrame == 1 then

        end
    end
    
    local pos = Vector3.new(frame.Position[1], y, frame.Position[3])
    local look = Vector3.new(frame.LookVector[1], frame.LookVector[2], frame.LookVector[3])
    local up = frame.UpVector and Vector3.new(frame.UpVector[1], frame.UpVector[2], frame.UpVector[3]) or Vector3.new(0, 1, 0)
    return CFrame.lookAt(pos, pos + look, up)
end

local function GetFrameVelocity(frame)
    if not frame or not frame.Velocity then return Vector3.new(0, 0, 0) end
    return Vector3.new(frame.Velocity[1], frame.Velocity[2], frame.Velocity[3])
end

local function ApplyFrameDirect(frame, humanoidRootPart, humanoid)
    if not frame or not humanoidRootPart or not humanoid then return end
    
    local moveState = frame.MoveState or "Grounded"
    local currentTime = tick()
    
    humanoid.WalkSpeed = (frame.WalkSpeed or 16) * playbackSpeed
    humanoid.AutoRotate = false
    humanoid.PlatformStand = false
    
    if moveState == "Jumping" then
        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        lastPlaybackState = "Jumping"
    elseif moveState == "Falling" then
        humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
        lastPlaybackState = "Falling"
    elseif moveState == "Climbing" then
        if lastPlaybackState ~= "Climbing" then
            humanoid:ChangeState(Enum.HumanoidStateType.Climbing)
            lastPlaybackState = "Climbing"
            lastStateChangeTime = currentTime
        end
    elseif moveState == "Swimming" then
        if lastPlaybackState ~= "Swimming" then
            humanoid:ChangeState(Enum.HumanoidStateType.Swimming)
            lastPlaybackState = "Swimming"
            lastStateChangeTime = currentTime
        end
    else
        if lastPlaybackState ~= "Grounded" and 
           (currentTime - lastStateChangeTime) >= STATE_CHANGE_COOLDOWN then
            humanoid:ChangeState(Enum.HumanoidStateType.Running)
            lastPlaybackState = "Grounded"
            lastStateChangeTime = currentTime
        end
    end
    
    humanoidRootPart.CFrame = GetFrameCFrame(frame, humanoid)
    humanoidRootPart.AssemblyLinearVelocity = GetFrameVelocity(frame)
    humanoidRootPart.AssemblyAngularVelocity = Vector3.zero
end

-- ========== CORE PLAYBACK FUNCTIONS ==========

local function updateStatus(text, icon)
    if statusParagraph then
        statusParagraph:SetDesc(text)
    end
end

local function updateFrameInfo()
    if frameInfo then
        local totalSeconds = #replayData > 0 and (replayData[#replayData].Timestamp or 0) or 0
        local minutes = math.floor(totalSeconds / 60)
        local seconds = math.floor(totalSeconds % 60)
        frameInfo:SetDesc(string.format("Frame: %d / %d | Duration: %d:%02d", 
            currentFrame, #replayData, minutes, seconds))
    end
end

function loadReplayData()
    local success, result = pcall(function()
        local response = game:HttpGet(JSON_URL)
        return HttpService:JSONDecode(response)
    end)
    
    if success then
        replayData = result
        
        --  Auto-detect framerate from data
        if #replayData >= 2 then
            local timeDiff = replayData[2].Timestamp - replayData[1].Timestamp
            local detectedFPS = 1 / timeDiff
            
        end
        
        return true
    else

        return false
    end
end

function stopPlayback()
    isPlaying = false
    updateStatus("Playback stopped", "pause")
    
    if connection then
        connection:Disconnect()
        connection = nil
    end
    
    lastPlaybackState = nil
    lastStateChangeTime = 0
    frameTimeAccumulator = 0
    
    local character = LocalPlayer.Character
    if character then
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.AutoRotate = true
            humanoid.WalkSpeed = 16
        end
    end
end

function startPlayback()
    if #replayData == 0 then
        WindUI:Notify({
            Title = "Error",
            Content = "No replay data loaded!",
            Duration = 3,
            Icon = "alert-triangle"
        })
        return
    end
    
    if connection then
        connection:Disconnect()
        connection = nil
    end
    
    isPlaying = true
    updateStatus("Playing replay...", "play")
    
    local character = LocalPlayer.Character
    if not character then
        WindUI:Notify({
            Title = "Error",
            Content = "Character not found!",
            Duration = 3,
            Icon = "user-x"
        })
        stopPlayback()
        return
    end
    
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    
    if not humanoidRootPart or not humanoid then
        WindUI:Notify({
            Title = "Error",
            Content = "HumanoidRootPart or Humanoid not found!",
            Duration = 3,
            Icon = "alert-circle"
        })
        stopPlayback()
        return
    end
    
    WindUI:Notify({
        Title = "Replay Started",
        Content = string.format("Playing at %.2fx speed", playbackSpeed),
        Duration = 2,
        Icon = "play"
    })
    
    currentFrame = 1
    lastPlaybackState = nil
    lastStateChangeTime = 0
    frameTimeAccumulator = 0

    if #replayData > 0 then
        humanoidRootPart.CFrame = GetFrameCFrame(replayData[1], humanoid)
        humanoidRootPart.AssemblyLinearVelocity = Vector3.zero
        humanoidRootPart.AssemblyAngularVelocity = Vector3.zero
        task.wait(0.03)
    end
    
    local playbackStartTime = tick()
    local replayStartTimestamp = replayData[1].Timestamp or 0
    
    connection = RunService.Heartbeat:Connect(function(deltaTime)
        if not isPlaying then 
            if connection then
                connection:Disconnect()
                connection = nil
            end
            return 
        end
        
        local char = LocalPlayer.Character
        if not char then
            stopPlayback()
            return
        end
        
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        
        if not hrp or not hum then
            stopPlayback()
            return
        end
        
        -- Timestamp-based playback (FPS independent!)
        local fpsMultiplier = _G.__FPS_MULTIPLIER or 1
        local effectiveSpeed = playbackSpeed * fpsMultiplier
        
        local currentPlaybackTime = (tick() - playbackStartTime) * effectiveSpeed
        local targetTimestamp = replayStartTimestamp + currentPlaybackTime
        
        -- Find frame closest to target timestamp
        local targetFrame = currentFrame
        
        if _G.__REVERSE_MODE then
            -- Reverse: find frame with timestamp <= target
            for i = currentFrame, 1, -1 do
                if replayData[i] and replayData[i].Timestamp <= targetTimestamp then
                    targetFrame = i
                    break
                end
            end
        else
            -- Normal: find frame with timestamp >= target
            for i = currentFrame, #replayData do
                if replayData[i] and replayData[i].Timestamp >= targetTimestamp then
                    targetFrame = i
                    break
                end
            end
        end
        
        -- Apply all frames between current and target
        if targetFrame ~= currentFrame then
            local startFrame = currentFrame
            local endFrame = targetFrame
            local step = 1
            
            if _G.__REVERSE_MODE then
                startFrame = currentFrame
                endFrame = targetFrame
                step = -1
            end
            
            -- Apply frames (limit to max 10 per tick to avoid lag)
            local framesApplied = 0
            local maxFramesPerTick = 10
            
            for i = startFrame, endFrame, step do
                if framesApplied >= maxFramesPerTick then break end
                
                if i >= 1 and i <= #replayData then
                    local frame = replayData[i]
                    if frame then
                        ApplyFrameDirect(frame, hrp, hum)
                        framesApplied = framesApplied + 1
                    end
                end
            end
            
            currentFrame = targetFrame
            updateFrameInfo()
        end
        
        -- Check if finished
        if currentFrame >= #replayData and not _G.__REVERSE_MODE then
            if _G.__LOOP_MODE then
                currentFrame = 1
                playbackStartTime = tick()
                replayStartTimestamp = replayData[1].Timestamp or 0
                WindUI:Notify({
                    Title = "Looping",
                    Content = "Replay restarted",
                    Duration = 1,
                    Icon = "repeat"
                })
            else
                if connection then
                    connection:Disconnect()
                    connection = nil
                end
                
                isPlaying = false
                currentFrame = 1
                lastPlaybackState = nil
                lastStateChangeTime = 0
                
                updateStatus("Replay finished", "check-circle")
                WindUI:Notify({
                    Title = "Replay Finished",
                    Content = "Replay has completed!",
                    Duration = 3,
                    Icon = "check"
                })
                
                if hum then
                    hum.AutoRotate = true
                    hum.WalkSpeed = 16
                end
                
                updateFrameInfo()
                return
            end
        end
    end)
end

-- ========== INITIALIZE MAIN TABS (AFTER AUTH) ==========

local function InitializeMainTabs()
    if MainTab then return end
    
    --  Define player variable
    local player = Players.LocalPlayer
    
    MainTab = Window:Tab({
        Title = "Replay Player",
        Icon = "play"
    })

    statusParagraph = MainTab:Paragraph({
        Title = "Status",
        Desc = "Ready",
        Icon = "activity"
    })

    frameInfo = MainTab:Paragraph({
        Title = "Frame Info",
        Desc = string.format("Frame: %d / %d", currentFrame, #replayData),
        Icon = "film"
    })

    MainTab:Divider()

    MainTab:Button({
        Title = "Play Replay",
        Callback = function()
            if isPlaying then
                stopPlayback()
            else
                startPlayback()
            end
        end
    })

    MainTab:Button({
        Title = "Reset to Start",
        Callback = function()
            stopPlayback()
            currentFrame = 1
            frameTimeAccumulator = 0
            updateFrameInfo()
            updateStatus("Reset to frame 1", "rotate-ccw")
            WindUI:Notify({
                Title = "Reset Complete",
                Content = "Replay reset to frame 1",
                Duration = 2,
                Icon = "check"
            })
        end
    })

    MainTab:Divider()

    local speeds = {}
    for v = 0.25, 8, 0.25 do
        table.insert(speeds, string.format("%.2fx", v))
    end
    
    speedDropdown = MainTab:Dropdown({
        Title = "Playback Speed",
        Values = speeds,
        Value = "1.00x",
        Callback = function(option)
            local num = tonumber(option:match("([%d%.]+)"))
            if num then
                playbackSpeed = num
                frameTimeAccumulator = 0
                WindUI:Notify({
                    Title = "Speed Changed",
                    Content = string.format("Speed set to %.2fx", playbackSpeed),
                    Duration = 1.5,
                    Icon = "gauge"
                })
            end
        end
    })

    -- Settings Tab
    SettingsTab = Window:Tab({
        Title = "Settings",
        Icon = "settings"
    })

    local urlInput = ""
    SettingsTab:Input({
        Title = "Custom JSON URL",
        Placeholder = "Enter GitHub raw URL...",
        Default = JSON_URL,
        Callback = function(text)
            urlInput = text
        end
    })

    SettingsTab:Button({
        Title = "Load Custom Replay",
        Callback = function()
            if urlInput and urlInput ~= "" then
                JSON_URL = urlInput
                stopPlayback()
                currentFrame = 1
                replayData = {}
                updateStatus("Loading custom replay...", "download")
                
                task.spawn(function()
                    if loadReplayData() then
                        updateStatus("Custom replay loaded successfully!", "check")
                        updateFrameInfo()
                        WindUI:Notify({
                            Title = "Success",
                            Content = "Custom replay loaded!",
                            Duration = 3,
                            Icon = "check"
                        })
                    else
                        updateStatus("Failed to load custom replay", "x")
                    end
                end)
            else
                WindUI:Notify({
                    Title = "Error",
                    Content = "Please enter a valid URL",
                    Duration = 3,
                    Icon = "alert-triangle"
                })
            end
        end
    })

    SettingsTab:Divider()
    
    --  FPS Multiplier for slow replays
    SettingsTab:Paragraph({
        Title = "Replay Too Slow?",
        Desc = "If replay plays slower than expected at 1.00x speed, try adjusting FPS multiplier below.",
        Icon = "alert-circle"
    })
    
    local fpsMultipliers = {}
    for v = 1, 4, 0.5 do
        table.insert(fpsMultipliers, string.format("%.1fx", v))
    end
    
    SettingsTab:Dropdown({
        Title = "FPS Multiplier",
        Values = fpsMultipliers,
        Value = "1.0x",
        Callback = function(option)
            local num = tonumber(option:match("([%d%.]+)"))
            if num then
                -- Store FPS multiplier globally
                _G.__FPS_MULTIPLIER = num
                WindUI:Notify({
                    Title = "FPS Multiplier Changed",
                    Content = string.format("Multiplier set to %.1fx", num),
                    Duration = 2,
                    Icon = "zap"
                })
            end
        end
    })

    SettingsTab:Divider()

    SettingsTab:Paragraph({
        Title = "Info",
        Desc = "Default replay is automatically loaded on startup.\nYou can load custom replays from GitHub raw URLs.\n\nFPS Multiplier: Use if replay is too slow (1.5x = 50% faster, 2.0x = 2x faster)",
        Icon = "info"
    })

    -- About Tab
    AboutTab = Window:Tab({
        Title = "About",
        Icon = "info"
    })

    AboutTab:Paragraph({
        Title = "Replay Player v2.3",
        Desc = "A powerful replay player for Roblox games.\nVersion: 2.3 (Auth + Bugfix)\nCreated by: BantaiXmarV Team",
        Icon = "code"
    })

    AboutTab:Divider()

    AboutTab:Paragraph({
        Title = "Features & Fixes",
        Desc = "• Full JSON format (8 fields)\n•  HipHeight auto-correction\n•  Speed consistency\n• Velocity & MoveState replay\n• Adjustable speed (0.25x-8x)\n• State detection (Jump/Fall/Climb/Swim)",
        Icon = "list"
    })
    
    -- ========== ACCOUNT TAB ==========
    local AccountTab = Window:Tab({
        Title = "Account",
        Icon = "user"
    })
    
    AccountTab:Section({
        Title = "Information Account",
        TextSize = 18
    })
    
    --  Get player info properly
    local displayName = player.DisplayName or player.Name
    local username = player.Name
    local userId = player.UserId
    local hwid, hwidMethod = GetHWID()
    
    -- Get account info from global storage
    local accountRole = _G.__AUTH_ROLE or "Premium Member"
    local accountToken = _G.__AUTH_KEY or "Not Available"
    local accountExpiry = _G.__AUTH_EXPIRY or "Not Available"
    local accountExpiryDays = _G.__AUTH_EXPIRY_DAYS or "N/A"
    local accountStatus = _G.__AUTH_STATUS or "Active"
    
    -- Format token display
    local tokenDisplay = accountToken
    if accountToken ~= "Not Available" and #accountToken > 20 then
        tokenDisplay = accountToken:sub(1, 8) .. "********" .. accountToken:sub(-4)
    end
    
    AccountTab:Paragraph({
        Title = "Account Information",
        Desc = string.format(
            "Display Name: %s\n" ..
            "Username: %s\n" ..
            "Role: %s\n" ..
            "Token: %s\n" ..
            "VIP Member: %s\n" ..
            "Expire: %s\n" ..
            "Status: %s",
            displayName,
            username,
            accountRole,
            tokenDisplay,
            accountExpiry,
            accountExpiryDays,
            accountStatus
        ),
        Icon = "info"
    })
    
    AccountTab:Divider()
    
    AccountTab:Button({
        Title = "Refresh Account Info",
        Icon = "refresh-cw",
        Callback = function()
            WindUI:Notify({
                Title = "Info Updated",
                Content = "Account information refreshed!",
                Duration = 2,
                Icon = "check"
            })
        end
    })
    
    -- ========== BYPASS TAB ==========
    local BypassTab = Window:Tab({
        Title = "Bypass",
        Icon = "shield"
    })
    
    BypassTab:Section({
        Title = "Bypass Features",
        TextSize = 18
    })
    
    BypassTab:Paragraph({
        Title = "Bypass Afk Tidak Berfungsi?",
        Desc = "Jika fitur bypass afk di bawah tidak berfungsi silahkan pake auto clicker di bawah ini, untuk cara menggunakan auto clicker tutorial nya banyak dari youtube silahkan di tonton saja.",
        Icon = "alert-triangle"
    })
    
    BypassTab:Divider()
    
    -- Bypass Admin Detection
    local bypassAdminEnabled = false
    BypassTab:Toggle({
        Title = "Bypass Admin Detection",
        Desc = "Berfungsi jika admin masuk ke dalam server, maka kamu secara otomatis disconnect dari server.",
        Value = false,
        Callback = function(value)
            bypassAdminEnabled = value
            
            if value then
                WindUI:Notify({
                    Title = "Admin Detection ON",
                    Content = "You will auto-disconnect if admin joins",
                    Duration = 2,
                    Icon = "shield"
                })
                
                -- Monitor for admin joins
                _G.__ADMIN_DETECTION = Players.PlayerAdded:Connect(function(newPlayer)
                    if bypassAdminEnabled then
                        -- Check if player is admin (customize this logic)
                        local adminNames = {"Admin", "Moderator", "Staff"} -- Add admin usernames
                        for _, adminName in ipairs(adminNames) do
                            if newPlayer.Name:lower():find(adminName:lower()) then
                                WindUI:Notify({
                                    Title = "Admin Detected!",
                                    Content = "Disconnecting from server...",
                                    Duration = 2,
                                    Icon = "alert-triangle"
                                })
                                task.wait(1)
                                player:Kick("Admin detected - Auto disconnect enabled")
                            end
                        end
                    end
                end)
            else
                WindUI:Notify({
                    Title = "Admin Detection OFF",
                    Content = "Auto-disconnect disabled",
                    Duration = 2,
                    Icon = "shield-off"
                })
                
                if _G.__ADMIN_DETECTION then
                    _G.__ADMIN_DETECTION:Disconnect()
                    _G.__ADMIN_DETECTION = nil
                end
            end
        end
    })
    
    -- Bypass AFK
    local bypassAFKEnabled = false
    BypassTab:Toggle({
        Title = "Bypass AFK",
        Desc = "Berfungsi untuk afk push summit biar tidak terkena kick oleh bot idle 20 menit.",
        Value = false,
        Callback = function(value)
            bypassAFKEnabled = value
            
            if value then
                WindUI:Notify({
                    Title = "AFK Bypass ON",
                    Content = "Anti-AFK kick activated",
                    Duration = 2,
                    Icon = "coffee"
                })
                
                -- Simple anti-AFK (move character slightly every 10 minutes)
                _G.__AFK_BYPASS = task.spawn(function()
                    while bypassAFKEnabled do
                        task.wait(600) -- 10 minutes
                        if bypassAFKEnabled then
                            local char = player.Character
                            if char and char:FindFirstChild("HumanoidRootPart") then
                                local hrp = char.HumanoidRootPart
                                local originalCF = hrp.CFrame
                                hrp.CFrame = hrp.CFrame + Vector3.new(0, 0.1, 0)
                                task.wait(0.1)
                                hrp.CFrame = originalCF
                            end
                        end
                    end
                end)
            else
                WindUI:Notify({
                    Title = "AFK Bypass OFF",
                    Content = "Anti-AFK disabled",
                    Duration = 2,
                    Icon = "coffee"
                })
                
                if _G.__AFK_BYPASS then
                    task.cancel(_G.__AFK_BYPASS)
                    _G.__AFK_BYPASS = nil
                end
            end
        end
    })
    
    BypassTab:Divider()
    
    -- Auto Clicker Downloads
    BypassTab:Paragraph({
        Title = "AUTO CLICKER | PC",
        Desc = "Download auto clicker untuk PC/Laptop",
        Icon = "download",
        Buttons = {
            {
                Title = "Download",
                Icon = "download",
                Callback = function()
                    setclipboard("https://sourceforge.net/projects/orphamielautoclicker/")
                    WindUI:Notify({
                        Title = "Link Copied!",
                        Content = "Auto clicker download link copied to clipboard",
                        Duration = 3,
                        Icon = "copy"
                    })
                end
            }
        }
    })
    
    BypassTab:Paragraph({
        Title = "AUTO CLICKER | ANDROID",
        Desc = "Download auto clicker untuk Android/Mobile",
        Icon = "smartphone",
        Buttons = {
            {
                Title = "Download",
                Icon = "download",
                Callback = function()
                    setclipboard("https://play.google.com/store/apps/details?id=com.truedevelopersstudio.automatictap.autoclicker")
                    WindUI:Notify({
                        Title = "Link Copied!",
                        Content = "Auto clicker download link copied to clipboard",
                        Duration = 3,
                        Icon = "copy"
                    })
                end
            }
        }
    })
    
    -- ========== SKYBOX TAB ==========
    local SkyboxTab = Window:Tab({
        Title = "Skybox",
        Icon = "sun"
    })
    
    SkyboxTab:Section({
        Title = "Change Skybox",
        TextSize = 18
    })
    
    SkyboxTab:Paragraph({
        Title = "Skybox Changer",
        Desc = "Pilih skybox untuk mengubah tampilan langit di game. Perubahan hanya terlihat oleh kamu.",
        Icon = "cloud"
    })
    
    SkyboxTab:Divider()
    
    -- Skybox data
    local skyboxes = {
        {name = "Rainbow Clear", id = "16573649975"},
        {name = "Anime Sky", id = "14753835117"},
        {name = "Cyberpunk Night", id = "13689001090"},
        {name = "Aurora Sky", id = "17124418086"},
        {name = "Dream Sky", id = "17480150596"},
        {name = "HD Clear", id = "8199641442"},
        {name = "Pet Sim Sky", id = "9603351943"},
        {name = "Candy Sky", id = "76584711398016"},
        {name = "Cartoon Sky", id = "15387348852"},
        {name = "Sunset Sky", id = "627302570"}
    }
    
    -- Function to apply skybox
    local function applySkybox(skyboxId, skyboxName)
        local Lighting = game:GetService("Lighting")
        
        -- Remove all existing Sky objects
        for _, obj in pairs(Lighting:GetChildren()) do
            if obj:IsA("Sky") then
                pcall(function() obj:Destroy() end)
            end
        end
        
        task.wait(0.2)
        
        -- Create new sky
        local sky = Instance.new("Sky")
        sky.Name = "BantaiSky"
        
        -- Set all 6 sides
        local assetUrl = "rbxassetid://" .. skyboxId
        sky.SkyboxBk = assetUrl
        sky.SkyboxDn = assetUrl
        sky.SkyboxFt = assetUrl
        sky.SkyboxLf = assetUrl
        sky.SkyboxRt = assetUrl
        sky.SkyboxUp = assetUrl
        
        -- Additional sky properties
        sky.StarCount = 3000
        sky.SunAngularSize = 21
        sky.MoonAngularSize = 11
        
        sky.Parent = Lighting
        
        WindUI:Notify({
            Title = "Skybox Changed",
            Content = "Applied: " .. skyboxName,
            Duration = 2,
            Icon = "check"
        })
    end
    
    -- Create buttons for each skybox
    for _, skybox in ipairs(skyboxes) do
        SkyboxTab:Button({
            Title = skybox.name,
            Callback = function()
                applySkybox(skybox.id, skybox.name)
            end
        })
    end
    
    SkyboxTab:Divider()
    
    -- Reset skybox button
    SkyboxTab:Button({
        Title = "Reset to Default",
        Callback = function()
            local Lighting = game:GetService("Lighting")
            for _, obj in pairs(Lighting:GetChildren()) do
                if obj:IsA("Sky") then
                    obj:Destroy()
                end
            end
            WindUI:Notify({
                Title = "Skybox Reset",
                Content = "Skybox removed, using default sky",
                Duration = 2,
                Icon = "rotate-ccw"
            })
        end
    })
    

    -- ========== VISUAL EFFECTS TAB ==========
    local EffectsTab = Window:Tab({
        Title = "Visual Effects",
        Icon = "sparkles"
    })
    
    EffectsTab:Section({
        Title = "Character Effects",
        TextSize = 18
    })
    
    -- Trail Effect
    local trailEnabled = false
    local trailColor = Color3.fromRGB(0, 255, 255)
    
    EffectsTab:Toggle({
        Title = "Trail Effect",
        Desc = "Character leaves a colorful trail behind",
        Value = false,
        Callback = function(value)
            trailEnabled = value
            
            if value then
                local char = player.Character
                if char and char:FindFirstChild("HumanoidRootPart") then
                    local hrp = char.HumanoidRootPart
                    
                    local trail = Instance.new("Trail")
                    trail.Name = "BantaiTrail"
                    trail.Color = ColorSequence.new(trailColor)
                    trail.Lifetime = 2
                    trail.MinLength = 0.1
                    trail.Transparency = NumberSequence.new(0.5)
                    trail.WidthScale = NumberSequence.new(1)
                    
                    local att0 = Instance.new("Attachment")
                    att0.Name = "TrailAttachment0"
                    att0.Position = Vector3.new(-0.5, 0, 0)
                    att0.Parent = hrp
                    
                    local att1 = Instance.new("Attachment")
                    att1.Name = "TrailAttachment1"
                    att1.Position = Vector3.new(0.5, 0, 0)
                    att1.Parent = hrp
                    
                    trail.Attachment0 = att0
                    trail.Attachment1 = att1
                    trail.Parent = hrp
                    
                    _G.__TRAIL_EFFECT = trail
                    
                    WindUI:Notify({
                        Title = "Trail ON",
                        Content = "Character trail activated",
                        Duration = 2,
                        Icon = "check"
                    })
                end
            else
                if _G.__TRAIL_EFFECT then
                    _G.__TRAIL_EFFECT:Destroy()
                    _G.__TRAIL_EFFECT = nil
                end
                
                local char = player.Character
                if char and char:FindFirstChild("HumanoidRootPart") then
                    local hrp = char.HumanoidRootPart
                    for _, obj in pairs(hrp:GetChildren()) do
                        if obj.Name == "BantaiTrail" or obj.Name:find("TrailAttachment") then
                            obj:Destroy()
                        end
                    end
                end
                
                WindUI:Notify({
                    Title = "Trail OFF",
                    Content = "Character trail disabled",
                    Duration = 2,
                    Icon = "check"
                })
            end
        end
    })
    
    -- Ghost Mode
    local ghostEnabled = false
    
    EffectsTab:Toggle({
        Title = "Ghost Mode",
        Desc = "Make character semi-transparent",
        Value = false,
        Callback = function(value)
            ghostEnabled = value
            
            local char = player.Character
            if char then
                for _, part in pairs(char:GetDescendants()) do
                    if part:IsA("BasePart") or part:IsA("Decal") then
                        if value then
                            part.Transparency = 0.5
                        else
                            if part.Name == "HumanoidRootPart" then
                                part.Transparency = 1
                            else
                                part.Transparency = 0
                            end
                        end
                    end
                end
                
                WindUI:Notify({
                    Title = value and "Ghost Mode ON" or "Ghost Mode OFF",
                    Content = value and "Character is now transparent" or "Character opacity restored",
                    Duration = 2,
                    Icon = "eye"
                })
            end
        end
    })
    
    -- Glow Effect
    local glowEnabled = false
    
    EffectsTab:Toggle({
        Title = "Glow Effect",
        Desc = "Add glowing aura around character",
        Value = false,
        Callback = function(value)
            glowEnabled = value
            
            local char = player.Character
            if char and char:FindFirstChild("HumanoidRootPart") then
                if value then
                    local hrp = char.HumanoidRootPart
                    
                    local light = Instance.new("PointLight")
                    light.Name = "BantaiGlow"
                    light.Brightness = 2
                    light.Range = 20
                    light.Color = Color3.fromRGB(0, 255, 255)
                    light.Parent = hrp
                    
                    _G.__GLOW_EFFECT = light
                    
                    WindUI:Notify({
                        Title = "Glow Effect ON",
                        Content = "Character is glowing",
                        Duration = 2,
                        Icon = "sun"
                    })
                else
                    if _G.__GLOW_EFFECT then
                        _G.__GLOW_EFFECT:Destroy()
                        _G.__GLOW_EFFECT = nil
                    end
                    
                    local hrp = char:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        for _, obj in pairs(hrp:GetChildren()) do
                            if obj.Name == "BantaiGlow" then
                                obj:Destroy()
                            end
                        end
                    end
                    
                    WindUI:Notify({
                        Title = "Glow Effect OFF",
                        Content = "Glow disabled",
                        Duration = 2,
                        Icon = "sun"
                    })
                end
            end
        end
    })
    
    -- Speed Lines
    local speedLinesEnabled = false
    
    EffectsTab:Toggle({
        Title = "Speed Lines",
        Desc = "Show speed lines during fast playback",
        Value = false,
        Callback = function(value)
            speedLinesEnabled = value
            _G.__SPEED_LINES_ENABLED = value
            
            WindUI:Notify({
                Title = value and "Speed Lines ON" or "Speed Lines OFF",
                Content = value and "Speed lines will appear at 2x+ speed" or "Speed lines disabled",
                Duration = 2,
                Icon = "zap"
            })
        end
    })
    
    EffectsTab:Divider()
    
    -- Nametag Customization
    local customNametagText = ""
    
    EffectsTab:Input({
        Title = "Custom Nametag",
        Placeholder = "Enter custom text...",
        Callback = function(text)
            customNametagText = text
        end
    })
    
    EffectsTab:Button({
        Title = "Apply Nametag",
        Callback = function()
            local char = player.Character
            if char and char:FindFirstChild("Head") then
                local head = char.Head
                
                for _, obj in pairs(head:GetChildren()) do
                    if obj.Name == "BantaiNametag" then
                        obj:Destroy()
                    end
                end
                
                if customNametagText ~= "" then
                    local billboard = Instance.new("BillboardGui")
                    billboard.Name = "BantaiNametag"
                    billboard.Size = UDim2.new(0, 200, 0, 50)
                    billboard.StudsOffset = Vector3.new(0, 3, 0)
                    billboard.AlwaysOnTop = true
                    billboard.Parent = head
                    
                    local textLabel = Instance.new("TextLabel")
                    textLabel.Size = UDim2.new(1, 0, 1, 0)
                    textLabel.BackgroundTransparency = 1
                    textLabel.Text = customNametagText
                    textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
                    textLabel.TextStrokeTransparency = 0
                    textLabel.Font = Enum.Font.GothamBold
                    textLabel.TextScaled = true
                    textLabel.Parent = billboard
                    
                    WindUI:Notify({
                        Title = "Nametag Applied",
                        Content = "Custom text: " .. customNametagText,
                        Duration = 2,
                        Icon = "type"
                    })
                else
                    WindUI:Notify({
                        Title = "Nametag Removed",
                        Content = "Custom nametag cleared",
                        Duration = 2,
                        Icon = "x"
                    })
                end
            end
        end
    })
    

    -- ========== CONTROLLER TAB ==========
    local ControllerTab = Window:Tab({
        Title = "Controller",
        Icon = "gamepad-2"
    })
    
    ControllerTab:Section({
        Title = "Advanced Controls",
        TextSize = 18
    })
    
    -- Loop Mode
    local loopEnabled = false
    
    ControllerTab:Toggle({
        Title = "Loop Mode",
        Desc = "Automatically restart replay when finished",
        Value = false,
        Callback = function(value)
            loopEnabled = value
            _G.__LOOP_MODE = value
            
            WindUI:Notify({
                Title = value and "Loop Mode ON" or "Loop Mode OFF",
                Content = value and "Replay will loop infinitely" or "Loop disabled",
                Duration = 2,
                Icon = "repeat"
            })
        end
    })
    
    -- Reverse Playback
    local reverseEnabled = false
    
    ControllerTab:Toggle({
        Title = "Reverse Playback",
        Desc = "Play replay backwards (experimental)",
        Value = false,
        Callback = function(value)
            reverseEnabled = value
            _G.__REVERSE_MODE = value
            
            WindUI:Notify({
                Title = value and "Reverse Mode ON" or "Reverse Mode OFF",
                Content = value and "Replay will play backwards" or "Normal playback",
                Duration = 2,
                Icon = "rewind"
            })
        end
    })
    
    ControllerTab:Divider()
    
    -- Frame-by-Frame Controls
    ControllerTab:Paragraph({
        Title = "Frame Controls",
        Desc = "Use these buttons to move frame-by-frame through the replay",
        Icon = "skip-forward"
    })
    
    ControllerTab:Button({
        Title = "Previous Frame (-1)",
        Callback = function()
            if currentFrame > 1 then
                stopPlayback()
                currentFrame = currentFrame - 1
                updateFrameInfo()
                
                local char = LocalPlayer.Character
                if char and #replayData > 0 then
                    local hrp = char:FindFirstChild("HumanoidRootPart")
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    if hrp and hum and replayData[currentFrame] then
                        ApplyFrameDirect(replayData[currentFrame], hrp, hum)
                    end
                end
                
                WindUI:Notify({
                    Title = "Frame " .. currentFrame,
                    Content = "Moved back 1 frame",
                    Duration = 1,
                    Icon = "chevron-left"
                })
            end
        end
    })
    
    ControllerTab:Button({
        Title = "Next Frame (+1)",
        Callback = function()
            if currentFrame < #replayData then
                stopPlayback()
                currentFrame = currentFrame + 1
                updateFrameInfo()
                
                local char = LocalPlayer.Character
                if char and #replayData > 0 then
                    local hrp = char:FindFirstChild("HumanoidRootPart")
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    if hrp and hum and replayData[currentFrame] then
                        ApplyFrameDirect(replayData[currentFrame], hrp, hum)
                    end
                end
                
                WindUI:Notify({
                    Title = "Frame " .. currentFrame,
                    Content = "Moved forward 1 frame",
                    Duration = 1,
                    Icon = "chevron-right"
                })
            end
        end
    })
    
    ControllerTab:Divider()
    
    -- Keybind Info
    ControllerTab:Paragraph({
        Title = "Keybinds (Coming Soon)",
        Desc = "Space = Play/Pause\nLeft Arrow = -1 Frame\nRight Arrow = +1 Frame\nR = Reset to Start\nL = Toggle Loop",
        Icon = "keyboard"
    })
    

        WindUI:Notify({
        Title = "Tabs Loaded",
        Content = "All features are now available!",
        Duration = 2,
        Icon = "check-circle"
    })
end

-- ========== ON AUTH SUCCESS ==========

local function OnAuthSuccess()
    isAuthenticated = true
    
    WindUI:Notify({
        Title = "Authentication Success",
        Content = "Key valid! Loading main features...",
        Duration = 3,
        Icon = "check"
    })
    
    task.wait(0.5)
    InitializeMainTabs()
end

-- ========== AUTH TAB ==========

local AuthTab = Window:Tab({
    Title = "Authentication",
    Icon = "shield",
    Locked = false,
})

local authSection = AuthTab:Section({
    Title = "Enter Access Key",
    TextSize = 20,
})

authSection:Paragraph({
    Title = "Authentication Required",
    Content = "Please enter the access key to unlock all features.",
    Icon = "shield"
})

local enteredKey = ""

authSection:Input({
    Title = "Access Key",
    Desc = "Enter your key here",
    Value = "",
    Placeholder = "Enter key...",
    Icon = "key",
    Callback = function(text)
        enteredKey = text
    end
})

authSection:Button({
    Title = "Verify Key",
    Icon = "unlock",
    Color = Color3.fromRGB(0, 255, 127),
    Callback = function()
        local keyToVerify = trim(enteredKey or "")
        
        if keyToVerify == "" then
            WindUI:Notify({ 
                Title = "Error", 
                Content = "Please enter a key first.", 
                Duration = 3, 
                Icon = "x" 
            })
            return
        end
        
        local hwid, hwidMethod = GetHWID()
        local username = game.Players.LocalPlayer.Name
        
        if hwid == "UNKNOWN" or hwid == "" then
            WindUI:Notify({ 
                Title = "HWID Error", 
                Content = "Failed to get device ID. Try using a different executor.", 
                Duration = 3, 
                Icon = "alert-triangle" 
            })
            return
        end
        
        local encodedKey = HttpService:UrlEncode(keyToVerify)
        local encodedUsername = HttpService:UrlEncode(username)
        local encodedHWID = HttpService:UrlEncode(hwid)
        
        --  PASTIKAN URL INI SESUAI DENGAN NAMA FILE PHP DI SERVER!
        -- Coba ganti ke salah satu dari ini:
        local url = string.format(
            "https://bantaigunung.my.id/adminaw.php?action=api&Key=%s&Username=%s&HWID=%s",
            -- Kalau masih 404, coba ganti jadi:
            -- "https://bantaigunung.my.id/adminaw_fixed.php?action=api&Key=%s&Username=%s&HWID=%s",
            encodedKey,
            encodedUsername,
            encodedHWID
        )
        
        WindUI:Notify({ 
            Title = "Verifying...", 
            Content = "Connecting to server... (" .. hwidMethod .. ")", 
            Duration = 2, 
            Icon = "loader" 
        })
        
        --  Use bypass function
        local success, response = makeAuthRequest(url)
        
        if not success then
            WindUI:Notify({ 
                Title = "Connection Error", 
                Content = "Failed to reach authentication server.", 
                Duration = 3, 
                Icon = "wifi-off" 
            })
            return
        end
        
        if success then

            local statusCode = response.StatusCode or (response.Success and 200) or 500
            
            if statusCode ~= 200 then
                WindUI:Notify({ 
                    Title = "Server Error", 
                    Content = "HTTP " .. statusCode .. " - Authentication failed.", 
                    Duration = 3, 
                    Icon = "alert-triangle" 
                })
                return
            end
            
            local parseSuccess, result = pcall(function()
                return HttpService:JSONDecode(response.Body)
            end)
            
            if parseSuccess and result then
                if result.status == "success" then
                    isAuthenticated = true
                    
                    --  Store auth data globally
                    _G.__AUTH_KEY = keyToVerify
                    _G.__AUTH_ROLE = "Premium Member"
                    _G.__AUTH_STATUS = "Active"
                    
                    if result.expires_at then
                        _G.__AUTH_EXPIRY = result.expires_at
                        if result.expires_in_days then
                            _G.__AUTH_EXPIRY_DAYS = result.expires_in_days .. " Days"
                        else
                            _G.__AUTH_EXPIRY_DAYS = "Lifetime"
                        end
                    else
                        _G.__AUTH_EXPIRY = "Lifetime"
                        _G.__AUTH_EXPIRY_DAYS = "Lifetime"
                    end
                    
                    --  Save session (1 day auto-login)
                    saveSession(keyToVerify, username, hwid, _G.__AUTH_EXPIRY)
                    
                    WindUI:Notify({ 
                        Title = "Authentication Successful", 
                        Content = "Welcome! Loading features...", 
                        Duration = 3, 
                        Icon = "check" 
                    })
                    
                    task.wait(0.5)
                    OnAuthSuccess()
                else
                    local errorMsg = result.message or "Key Invalid or Expired"
                    
                    --  Smart kick: Only kick on username/HWID mismatch
                    if errorMsg:lower():find("username") or 
                       errorMsg:lower():find("hwid") or 
                       errorMsg:lower():find("bound") or 
                       errorMsg:lower():find("mismatch") or
                       errorMsg:lower():find("another") then
                        
                        WindUI:Notify({ 
                            Title = "Account Mismatch", 
                            Content = errorMsg, 
                            Duration = 5, 
                            Icon = "alert-triangle" 
                        })
                        KickPlayer(errorMsg)
                    else
                        -- Wrong key / Expired / Blocked - DON'T KICK
                        WindUI:Notify({ 
                            Title = "Authentication Failed", 
                            Content = errorMsg, 
                            Duration = 3, 
                            Icon = "x" 
                        })
                        clearSession()
                    end
                end
            else
                WindUI:Notify({ 
                    Title = "Parse Error", 
                    Content = "Server returned invalid data.", 
                    Duration = 3, 
                    Icon = "alert-triangle" 
                })
            end
        end
    end
})

authSection:Divider()

local hwidInfo = authSection:Paragraph({
    Title = "Device Info",
    Desc = "Detecting device identifier...",
    Icon = "monitor"
})

task.spawn(function()
    task.wait(0.5)
    local hwid, method = GetHWID()
    local hwidShort = hwid:sub(1, 16)
    hwidInfo:SetDesc(string.format("Method: %s\nDevice ID: %s", method, hwidShort))
end)

authSection:Paragraph({
    Title = "BantaiXmarV Community",
    Desc = "Join Our Community Discord Server to get the latest updates, support, and connect with other users!",
    Image = "rbxassetid://106735919480937",
    ImageSize = 24,
    Buttons = {
        {
            Title = "Copy Discord Link",
            Icon = "link",
            Callback = function()
                setclipboard("https://dsc.gg/BantaiXmarV")
                WindUI:Notify({
                    Title = "Link Copied!",
                    Content = "Discord link has been copied to clipboard.",
                    Duration = 3,
                    Icon = "copy",
                })
            end,
        }
    }
})

-- ========== INITIALIZATION ==========

WindUI:Notify({
    Title = "Replay Player v2.3",
    Content = "Please authenticate to continue",
    Duration = 5,
    Icon = "info"
})

task.spawn(function()
    task.wait(1)
    if loadReplayData() then
            else
            end
end)

--  AUTO-LOGIN FROM SESSION
task.spawn(function()
    task.wait(2)
    
    local session = loadSession()
    if session then
                
        local hwid, _ = GetHWID()
        local username = game.Players.LocalPlayer.Name
        
        -- Verify session matches current user
        if session.username == username and session.hwid == hwid then
            _G.__AUTH_KEY = session.key
            _G.__AUTH_ROLE = "Premium Member"
            _G.__AUTH_STATUS = "Active"
            _G.__AUTH_EXPIRY = session.expiresAt or "Lifetime"
            
            local daysLeft = "N/A"
            if session.expiresAt and session.expiresAt ~= "Lifetime" then
                local expiryDate = session.expiresAt:sub(1, 10)
                local currentDate = os.date("%Y-%m-%d")
                -- Simple days calculation
                daysLeft = "Check Account Tab"
            else
                daysLeft = "Lifetime"
            end
            _G.__AUTH_EXPIRY_DAYS = daysLeft
            
            WindUI:Notify({
                Title = "Auto-Login Success",
                Content = "Welcome back! Session restored.",
                Duration = 3,
                Icon = "check"
            })
            
            task.wait(0.5)
            OnAuthSuccess()
        else
                        clearSession()
        end
    else
            end
end)
