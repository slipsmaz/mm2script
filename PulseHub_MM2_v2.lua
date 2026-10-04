--[[
    PulseHub MM2 — standalone build
    UI: soft white / light blue, rectangular cards, compact controls.
    Intended for executor environments; features degrade gracefully when optional
    executor APIs (Drawing, hookmetamethod, setfpscap, etc.) are unavailable.
]]

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local Stats = game:GetService("Stats")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()
local Camera = workspace.CurrentCamera
local V3 = Vector3.new
local C3 = Color3.fromRGB
local U2 = UDim2.new
local K = Enum.KeyCode
local hasDrawing = type(Drawing) == "table" or type(Drawing) == "userdata"
local espGui
local canHook = type(hookmetamethod) == "function" and type(getnamecallmethod) == "function"
local canFPS = type(setfpscap) == "function"
local Env = (getgenv and getgenv()) or _G

local Hub = {
    alive = true,
    conns = {},
    cleanups = {},
    esp = {},
    backtrack = {},
    xray = {},
    state = {},
    tabs = {},
    controls = {},
    tabButtons = {},
    selectedTab = nil,
    drag = nil,
    rightDown = false,
    lastPing = 0,
    roleCache = {},
    musicSound = nil,
    restoreAnimations = {},
    originalLighting = {},
    presetObjects = {},
    createdGui = nil,
    fovDrawing = nil,
    clickFlingConn = nil,
    touchFlingConn = nil,
    silentHookInstalled = false,
}

Hub.state = {
    -- Visuals
    esp = false, espBox = false, espSkel = false, espTracer = false,
    gunEsp = false, xray = false, lblRole = false, lblName = false, lblDist = false,
    chams = false, chamsTrans = 55, backtrack = false, backMs = 150,
    trail = false, trailColor = "Blue", trailLife = 1,
    bloom = false, bloomInt = 0.8, bloomSize = 24, bloomThr = 0.9,
    atmo = false, atmoDensity = 30, atmoHaze = 1,
    rays = false, raysInt = 0.25, raysSpread = 0.8,
    blur = false, blurSize = 12,
    dof = false, dofFar = 50, dofFocus = 60, dofRadius = 30,
    fog = false, fogEnd = 800,
    -- Combat
    aimOn = false, aimVersion = "Silent", aimType = "Auto role", aimSpeed = 35,
    aimReturn = false, predict = 60, aimWall = false, fovShow = false, fovRadius = 160,
    killAura = false, killRadius = 18, killMode = "All",
    autoPickup = false, autoShoot = false, autoKill = false, autoFlingSheriff = false,
    knifeAim = false, knifeWall = false, knifeLead = 80, knifeAuto = false,
    desync = false, desyncMode = "Jitter", desyncRadius = 6, desyncSpeed = 20,
    faceThreat = false, resolver = false,
    -- Player
    farm = false, farmVersion = "Tween", farmSpeed = 40, farmReset = false,
    farmAvoid = false, farmFling = false,
    noclip = false, infJump = false, antiFling = false, fly = false, spin = false,
    bhop = false, invis = false, bombPower = 90, flySpeed = 50, spinSpeed = 20,
    -- Animation / troll
    packSel = "Ninja", packSpeed = 1, emoteSel = "Wave", emoteSpeed = 1,
    emoteHold = false, animAuto = false, toy = "Halo", toyOn = false,
    korblox = false, headless = false, speedOn = false, walkSpeed = 40,
    jumpOn = false, jumpPower = 70, touchFling = false, clickFling = false,
    orbit = false, orbitTarget = "Murderer", orbitRadius = 8, orbitSpeed = 4,
    -- Music / misc
    music = false, musicDelay = 3, musicVol = 50, songs = {},
    fpsUnlock = false, fpsCap = 240, optTex = false, optPart = false,
    optShadow = false, optRefl = false, optLow = false, antiAfk = false,
    theme = "Frost", uiScale = 100, stretch = false, font = "Gotham",
    textSize = 0, lang = "Русский", menuKey = K.RightShift, menuKeyName = "RightShift",
    preset_night_brightness = 1.0, preset_night_clock = 0.5, preset_night_exposure = -0.2,
    preset_realism_brightness = 2.0, preset_realism_clock = 14, preset_realism_exposure = 0,
    preset_future_brightness = 3.0, preset_future_clock = 16, preset_future_exposure = 0.35,
    preset_studio_brightness = 2.5, preset_studio_clock = 12, preset_studio_exposure = 0.15,
    preset_desert_brightness = 2.4, preset_desert_clock = 15, preset_desert_exposure = 0.1,
    preset_clean_brightness = 2.2, preset_clean_clock = 13, preset_clean_exposure = 0,
}

-- Automatic config persistence. No manual config creation is required.
-- Uses the executor filesystem when available; otherwise falls back to a session-only env table.
Hub.config = {
    path = "PulseHub/MM2.json",
    fallbackPath = "PulseHub_MM2.json",
    loaded = false,
    dirty = false,
}

local function configFS()
    return type(readfile) == "function" and type(writefile) == "function"
end

local function ensureConfigFolder()
    if type(makefolder) ~= "function" then return end
    if type(isfolder) == "function" then
        local ok, yes = pcall(isfolder, "PulseHub")
        if ok and yes then return end
    end
    pcall(makefolder, "PulseHub")
end

local function configSnapshot()
    local out = {}
    for k,v in pairs(Hub.state) do
        local tv = type(v)
        if tv == "boolean" or tv == "number" or tv == "string" then
            out[k] = v
        elseif tv == "table" and k == "songs" then
            out[k] = {}
            for i,x in ipairs(v) do out[k][i] = tostring(x) end
        end
    end
    out._version = 2
    return out
end

local function applyLoadedConfig(data)
    if type(data) ~= "table" then return end
    for k,v in pairs(data) do
        if k ~= "_version" and Hub.state[k] ~= nil then
            if type(Hub.state[k]) == type(v) then Hub.state[k] = v end
        end
    end
    Hub.state.menuKey = ({RightShift=K.RightShift,Insert=K.Insert,Home=K.Home,End=K.End,Delete=K.Delete})[Hub.state.menuKeyName] or K.RightShift
end

local function loadConfig()
    if Env.PulseHubConfig and type(Env.PulseHubConfig) == "table" then
        applyLoadedConfig(Env.PulseHubConfig)
        Hub.config.loaded = true
        return
    end
    if configFS() then
        ensureConfigFolder()
        local paths = {Hub.config.path, Hub.config.fallbackPath}
        for _,path in ipairs(paths) do
            local exists = true
            if type(isfile) == "function" then
                local ok, val = pcall(isfile, path)
                exists = ok and val or false
            end
            if exists then
                local okRead, raw = pcall(readfile, path)
                if okRead and type(raw) == "string" and #raw > 2 then
                    local okDecode, data = pcall(function() return HttpService:JSONDecode(raw) end)
                    if okDecode and type(data) == "table" then
                        applyLoadedConfig(data)
                        Hub.config.loaded = true
                        return
                    end
                end
            end
        end
    end
end

local function saveConfig()
    local snap = configSnapshot()
    Env.PulseHubConfig = snap
    if not configFS() then return false end
    ensureConfigFolder()
    local okEncode, raw = pcall(function() return HttpService:JSONEncode(snap) end)
    if not okEncode or type(raw) ~= "string" then return false end
    local ok = pcall(writefile, Hub.config.path, raw)
    if not ok then ok = pcall(writefile, Hub.config.fallbackPath, raw) end
    Hub.config.dirty = false
    return ok
end

loadConfig()
Hub.uiBaseSize = {}

local function pushConn(c)
    if c then Hub.conns[#Hub.conns + 1] = c end
    return c
end

local function pushCleanup(f)
    if f then Hub.cleanups[#Hub.cleanups + 1] = f end
    return f
end

local function safe(f, ...)
    if type(f) ~= "function" then return nil end
    local a = table.pack(pcall(f, ...))
    if a[1] then return table.unpack(a, 2, a.n) end
    return nil
end

local function notify(msg)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "PulseHub MM2", Text = tostring(msg), Duration = 3
        })
    end)
end

local function aliveCharacter(p)
    local c = p and p.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    local r = c and c:FindFirstChild("HumanoidRootPart")
    return c, h, r
end

local function hasTool(p, name)
    local c = p and p.Character
    local b = p and p:FindFirstChildOfClass("Backpack")
    return (c and c:FindFirstChild(name)) or (b and b:FindFirstChild(name))
end

local function roleOf(p)
    if not p then return "Unknown" end
    if Hub.roleCache[p] and Hub.roleCache[p].t and os.clock() - Hub.roleCache[p].t < 0.25 then
        return Hub.roleCache[p].r
    end
    local role = "Innocent"
    if hasTool(p, "Knife") then
        role = "Murderer"
    elseif hasTool(p, "Gun") then
        role = "Sheriff"
    end
    Hub.roleCache[p] = {r = role, t = os.clock()}
    return role
end

local function roleColor(role)
    if role == "Murderer" then return C3(247, 92, 108) end
    if role == "Sheriff" then return C3(100, 164, 255) end
    if role == "Hero" then return C3(255, 204, 95) end
    return C3(180, 212, 232)
end

local function nearestTarget(filter, fromPos)
    local origin = fromPos or (select(3, aliveCharacter(LocalPlayer)) and select(3, aliveCharacter(LocalPlayer)).Position)
    if not origin then return nil end
    local best, bestD = nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and (not filter or filter(p)) then
            local c, h, r = aliveCharacter(p)
            if c and h and h.Health > 0 and r then
                local d = (r.Position - origin).Magnitude
                if d < bestD then best, bestD = p, d end
            end
        end
    end
    return best, bestD
end

local function playersRoleTarget()
    local meRole = roleOf(LocalPlayer)
    if Hub.state.aimType == "Murderer" then
        return nearestTarget(function(p) return roleOf(p) == "Murderer" end)
    elseif Hub.state.aimType == "Sheriff" then
        return nearestTarget(function(p) return roleOf(p) == "Sheriff" end)
    elseif Hub.state.aimType == "Closest to me" then
        return nearestTarget()
    elseif Hub.state.aimType == "Closest to cursor" then
        local best, dist = nil, math.huge
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then
                local c, h, r = aliveCharacter(p)
                if c and h and h.Health > 0 and r then
                    local vp, onScreen = Camera:WorldToViewportPoint(r.Position)
                    if onScreen then
                        local d = (Vector2.new(vp.X, vp.Y) - Vector2.new(Mouse.X, Mouse.Y)).Magnitude
                        if d < dist then best, dist = p, d end
                    end
                end
            end
        end
        return best, dist
    else
        if meRole == "Sheriff" or hasTool(LocalPlayer, "Gun") then
            return nearestTarget(function(p) return roleOf(p) == "Murderer" end)
        elseif meRole == "Murderer" then
            return nearestTarget(function(p) return roleOf(p) == "Sheriff" end)
        end
        return nearestTarget(function(p) return roleOf(p) == "Murderer" end)
    end
end

local function predictedPosition(p, ms)
    local _, _, r = aliveCharacter(p)
    if not r then return nil end
    local lead = math.max(0, ms or 0) / 1000
    local v = r.AssemblyLinearVelocity or r.Velocity or V3(0, 0, 0)
    if Hub.state.resolver then
        local hist = Hub.backtrack[p]
        if hist and #hist >= 2 then
            local a, b = hist[#hist-1], hist[#hist]
            local dt = math.max(0.01, b.t - a.t)
            v = (b.cf.Position - a.cf.Position) / dt
        end
    end
    return r.Position + v * lead
end

local function visibleFrom(origin, targetPos, targetCharacter)
    local d = targetPos - origin
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {LocalPlayer.Character}
    local hit = workspace:Raycast(origin, d, params)
    return not hit or (targetCharacter and hit.Instance:IsDescendantOf(targetCharacter))
end

local function targetByFov()
    local origin = Camera.CFrame.Position
    local best, bestPx = nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            local c, h, r = aliveCharacter(p)
            if c and h and h.Health > 0 and r then
                local vp, on = Camera:WorldToViewportPoint(r.Position)
                if on then
                    local px = (Vector2.new(vp.X, vp.Y) - Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)).Magnitude
                    if px <= Hub.state.fovRadius and px < bestPx then
                        if not Hub.state.aimWall or visibleFrom(origin, r.Position, c) then
                            best, bestPx = p, px
                        end
                    end
                end
            end
        end
    end
    return best
end

local function findRemoteLike(root, names, className)
    if not root then return nil end
    for _, n in ipairs(names) do
        local obj = root:FindFirstChild(n, true)
        if obj and (not className or obj:IsA(className)) then return obj end
    end
    for _, obj in ipairs(root:GetDescendants()) do
        if (not className or obj:IsA(className)) then
            local low = obj.Name:lower()
            for _, n in ipairs(names) do
                if low:find(n:lower(), 1, true) then return obj end
            end
        end
    end
    return nil
end

local function equippedGun()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("Gun")
end

local function equippedKnife()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("Knife")
end

local function shootAt(p)
    local gun = equippedGun()
    if not gun then
        local b = LocalPlayer:FindFirstChildOfClass("Backpack")
        local g = b and b:FindFirstChild("Gun")
        local _, h = aliveCharacter(LocalPlayer)
        if g and h then safe(function() h:EquipTool(g) end); task.wait() end
        gun = equippedGun()
    end
    if not gun then return false end
    local pos = predictedPosition(p, Hub.state.predict)
    if not pos then return false end
    local rf = findRemoteLike(gun, {"CreateBeam", "RemoteFunction", "Shoot", "Fire"}, "RemoteFunction")
    if rf and rf:IsA("RemoteFunction") then
        local ok = pcall(function() rf:InvokeServer(1, pos, "AH2") end)
        if ok then return true end
    end
    local re = findRemoteLike(gun, {"Shoot", "Fire", "CreateBeam"}, "RemoteEvent")
    if re and re:IsA("RemoteEvent") then
        local ok = pcall(function() re:FireServer(1, pos, "AH2") end)
        if ok then return true end
    end
    local click = gun:FindFirstChildOfClass("Tool")
    if click and click.Activate then
        safe(function() click:Activate() end)
        return true
    end
    return false
end

local function knifeThrowAt(p)
    local knife = equippedKnife()
    if not knife then
        local b = LocalPlayer:FindFirstChildOfClass("Backpack")
        local k = b and b:FindFirstChild("Knife")
        local _, h = aliveCharacter(LocalPlayer)
        if k and h then safe(function() h:EquipTool(k) end); task.wait() end
        knife = equippedKnife()
    end
    if not knife then return false end
    local pos = predictedPosition(p, Hub.state.knifeLead)
    if not pos then return false end
    local remote = findRemoteLike(knife, {"CreateBeam", "Throw", "RemoteFunction", "KnifeThrow"}, "RemoteFunction")
    if remote and remote:IsA("RemoteFunction") then
        local ok = pcall(function() remote:InvokeServer(1, pos, "AH2") end)
        if ok then return true end
    end
    local ev = findRemoteLike(knife, {"Throw", "KnifeThrow", "Remote"}, "RemoteEvent")
    if ev and ev:IsA("RemoteEvent") then
        local ok = pcall(function() ev:FireServer("Down", pos) end)
        if ok then return true end
    end
    local localScript = knife:FindFirstChild("KnifeLocal", true)
    local stab = localScript and findRemoteLike(localScript, {"Throw", "RemoteFunction"}, "RemoteFunction")
    if stab and stab:IsA("RemoteFunction") then
        return pcall(function() stab:InvokeServer(1, pos, "AH2") end)
    end
    return false
end

local function stab()
    local knife = equippedKnife()
    local remote = knife and knife:FindFirstChild("Stab")
    if remote and remote:IsA("RemoteEvent") then return pcall(function() remote:FireServer("Down") end) end
    remote = knife and findRemoteLike(knife, {"Stab", "Remote"}, "RemoteEvent")
    if remote then return pcall(function() remote:FireServer("Down") end) end
    return false
end

local function findGunDrop()
    local direct = workspace:FindFirstChild("GunDrop", true)
    if direct and direct:IsA("BasePart") then return direct end
    for _, d in ipairs(workspace:GetDescendants()) do
        if d.Name:lower():find("gundrop", 1, true) and d:IsA("BasePart") then return d end
    end
end

local function pickupGun()
    if hasTool(LocalPlayer, "Gun") then return true end
    local drop = findGunDrop()
    local c, h, r = aliveCharacter(LocalPlayer)
    if not drop or not r then return false end

    -- Fastest supported path: trigger the same interaction objects used by the game.
    for _,obj in ipairs(drop:GetDescendants()) do
        if type(fireproximityprompt) == "function" and obj:IsA("ProximityPrompt") then
            pcall(fireproximityprompt, obj)
        elseif type(fireclickdetector) == "function" and obj:IsA("ClickDetector") then
            pcall(fireclickdetector, obj, 0)
        end
    end

    -- Touch-based pickup used by many MM2 builds.
    if type(firetouchinterest) == "function" then
        local parts = {drop}
        for _,obj in ipairs(drop:GetDescendants()) do if obj:IsA("BasePart") then parts[#parts+1]=obj end end
        for _,part in ipairs(parts) do
            pcall(firetouchinterest, r, part, 0)
            pcall(firetouchinterest, r, part, 1)
        end
        if hasTool(LocalPlayer, "Gun") then return true end
    end

    -- Fallback: move over the pickup for a single physics frame, then restore.
    local old = r.CFrame
    r.CFrame = drop.CFrame + V3(0, 1.75, 0)
    task.wait()
    if not hasTool(LocalPlayer, "Gun") then
        pcall(function() h:MoveTo(drop.Position + V3(0,1,0)) end)
        task.wait(0.03)
    end
    local got = hasTool(LocalPlayer, "Gun")
    if not got then r.CFrame = old end
    return got and true or false
end

local function antiFlingStep()
    if not Hub.state.antiFling then
        Hub.antiFlingSafeCF = nil
        Hub.antiFlingLastPos = nil
        return
    end
    local _,h,r = aliveCharacter(LocalPlayer)
    if not h or not r then return end
    local nowPos = r.Position
    local vel = r.AssemblyLinearVelocity
    local ang = r.AssemblyAngularVelocity
    local violent = vel.Magnitude > 120 or ang.Magnitude > 45
    local movedTooFar = Hub.antiFlingLastPos and (nowPos - Hub.antiFlingLastPos).Magnitude > 65
    if violent or movedTooFar then
        local safeCF = Hub.antiFlingSafeCF
        if safeCF then
            pcall(function() r.CFrame = safeCF end)
        end
        pcall(function() r.AssemblyLinearVelocity = V3(0,0,0) end)
        pcall(function() r.AssemblyAngularVelocity = V3(0,0,0) end)
        pcall(function() h.PlatformStand = false end)
        pcall(function() h.Sit = false end)
    else
        Hub.antiFlingSafeCF = r.CFrame
    end
    Hub.antiFlingLastPos = r.Position
end

local function fling(p, seconds)
    local _, _, meRoot = aliveCharacter(LocalPlayer)
    local _, _, root = aliveCharacter(p)
    if not meRoot or not root then return false end
    local stop = os.clock() + (seconds or 1.5)
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if not Hub.alive or os.clock() > stop or not root.Parent or not meRoot.Parent then
            pcall(function() conn:Disconnect() end)
            return
        end
        meRoot.CFrame = root.CFrame * CFrame.new(0, 0, 3)
        meRoot.AssemblyLinearVelocity = V3(0, 10000, 0)
        root.AssemblyLinearVelocity = V3(0, -10000, 0)
    end)
    pushCleanup(function() pcall(function() conn:Disconnect() end) end)
    return true
end

local function mapModel()
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("Model") and (obj:FindFirstChild("CoinContainer", true) or obj:FindFirstChild("Coin_Server", true)) then
            return obj
        end
    end
    return nil
end

local function coinParts()
    local list = {}
    local map = mapModel()
    if map then
        local cc = map:FindFirstChild("CoinContainer", true)
        if cc then
            for _, d in ipairs(cc:GetDescendants()) do
                if d:IsA("BasePart") and d.Name == "Coin_Server" then list[#list + 1] = d end
            end
        end
    end
    if #list == 0 then
        for _, d in ipairs(workspace:GetDescendants()) do
            if d:IsA("BasePart") and d.Name == "Coin_Server" then list[#list + 1] = d end
        end
    end
    return list
end

local function bagCount()
    local c = LocalPlayer.Character
    local b = LocalPlayer:FindFirstChildOfClass("Backpack")
    local candidates = {LocalPlayer, c, b}
    for _, obj in ipairs(candidates) do
        if obj then
            for _, n in ipairs({"Coin", "Coins", "CoinAmount", "Bag", "BagValue"}) do
                local v = obj:GetAttribute(n)
                if type(v) == "number" then return v end
                local child = obj:FindFirstChild(n)
                if child and child:IsA("NumberValue") then return child.Value end
            end
        end
    end
    return nil
end

local function roundActive()
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if pg then
        for _, d in ipairs(pg:GetDescendants()) do
            if d:IsA("TextLabel") and d.Text:lower():find("in round", 1, true) then return true end
        end
    end
    return #coinParts() > 0
end

local function startFly()
    if Hub.flyConn then return end
    local c, h, r = aliveCharacter(LocalPlayer)
    if not c or not h or not r then return end
    Hub.flyConn = RunService.RenderStepped:Connect(function()
        if not Hub.alive or not Hub.state.fly then return end
        local cam = workspace.CurrentCamera
        local dir = V3(0,0,0)
        if UIS:IsKeyDown(K.W) then dir = dir + cam.CFrame.LookVector end
        if UIS:IsKeyDown(K.S) then dir = dir - cam.CFrame.LookVector end
        if UIS:IsKeyDown(K.A) then dir = dir - cam.CFrame.RightVector end
        if UIS:IsKeyDown(K.D) then dir = dir + cam.CFrame.RightVector end
        if UIS:IsKeyDown(K.Space) then dir = dir + V3(0,1,0) end
        if UIS:IsKeyDown(K.LeftControl) then dir = dir - V3(0,1,0) end
        if dir.Magnitude > 0 then r.AssemblyLinearVelocity = dir.Unit * Hub.state.flySpeed else r.AssemblyLinearVelocity = V3(0,0,0) end
        r.CFrame = CFrame.lookAt(r.Position, r.Position + cam.CFrame.LookVector)
    end)
    pushCleanup(function() pcall(function() Hub.flyConn:Disconnect() end) end)
end

local function stopFly()
    if Hub.flyConn then pcall(function() Hub.flyConn:Disconnect() end); Hub.flyConn = nil end
end

local function applyNoclip()
    if Hub.noclipConn then return end
    Hub.noclipConn = RunService.Stepped:Connect(function()
        if not Hub.state.noclip then return end
        local c = LocalPlayer.Character
        if c then for _, d in ipairs(c:GetDescendants()) do if d:IsA("BasePart") then d.CanCollide = false end end end
    end)
    pushCleanup(function() pcall(function() Hub.noclipConn:Disconnect() end) end)
end

local function resetNoclip()
    local c = LocalPlayer.Character
    if c then for _, d in ipairs(c:GetDescendants()) do if d:IsA("BasePart") then d.CanCollide = true end end end
end

local function setXray(on)
    Hub.state.xray = on
    if Hub.xrayConn then pcall(function() Hub.xrayConn:Disconnect() end); Hub.xrayConn=nil end
    if on then
        for _, d in ipairs(workspace:GetDescendants()) do
            if d:IsA("BasePart") and not d:IsDescendantOf(LocalPlayer.Character) then
                if Hub.xray[d] == nil then Hub.xray[d] = d.LocalTransparencyModifier end
                d.LocalTransparencyModifier = math.max(d.LocalTransparencyModifier, 0.55)
            end
        end
        Hub.xrayConn = workspace.DescendantAdded:Connect(function(d)
            if Hub.alive and Hub.state.xray and d:IsA("BasePart") and not d:IsDescendantOf(LocalPlayer.Character) then
                Hub.xray[d] = d.LocalTransparencyModifier
                d.LocalTransparencyModifier = math.max(d.LocalTransparencyModifier, 0.55)
            end
        end)
        pushCleanup(function() if Hub.xrayConn then pcall(function() Hub.xrayConn:Disconnect() end); Hub.xrayConn=nil end end)
    else
        for d, old in pairs(Hub.xray) do
            if d and d.Parent then pcall(function() d.LocalTransparencyModifier = old end) end
        end
        Hub.xray = {}
    end
end

local function destroyName(parent, names)
    for _, n in ipairs(names) do
        local o = parent:FindFirstChild(n)
        if o then pcall(function() o:Destroy() end) end
    end
end

local function clearEspFor(p)
    local e = Hub.esp[p]
    if not e then return end
    for _, o in pairs(e) do pcall(function() if o.Remove then o:Remove() elseif o.Destroy then o:Destroy() end end) end
    Hub.esp[p] = nil
end

local function drawingLine()
    if not hasDrawing then return nil end
    local o = Drawing.new("Line")
    o.Visible = false; o.Thickness = 1; o.Transparency = 0.9
    return o
end

local function drawingSquare()
    if not hasDrawing then return nil end
    local o = Drawing.new("Square")
    o.Visible = false; o.Thickness = 1; o.Filled = false; o.Transparency = 0.9
    return o
end

local function drawingText()
    if not hasDrawing then return nil end
    local o = Drawing.new("Text")
    o.Visible = false; o.Center = true; o.Outline = true; o.Size = 13; o.Transparency = 1
    return o
end

local function ensureBillboard(p)
    local c, _, r = aliveCharacter(p)
    if not c or not r then return nil end
    local tag = c:FindFirstChild("PulseTag")
    if not tag then
        tag = Instance.new("BillboardGui")
        tag.Name = "PulseTag"
        tag.Size = U2(0, 180, 0, 42)
        tag.StudsOffset = V3(0, 3.5, 0)
        tag.AlwaysOnTop = true
        tag.MaxDistance = 5000
        tag.Parent = r
        local bg = Instance.new("Frame")
        bg.Name = "BG"; bg.BackgroundColor3 = C3(245, 251, 255); bg.BackgroundTransparency = 0.1
        bg.BorderSizePixel = 0; bg.Size = U2(1,0,1,0); bg.Parent = tag
        local stroke = Instance.new("UIStroke")
        stroke.Color = C3(166, 208, 238); stroke.Thickness = 1; stroke.Parent = bg
        local txt = Instance.new("TextLabel")
        txt.Name = "Text"; txt.BackgroundTransparency = 1; txt.Size = U2(1,0,1,0)
        txt.Font = Enum.Font.GothamSemibold; txt.TextSize = 12; txt.TextColor3 = C3(48,78,104)
        txt.Parent = bg
    end
    return tag
end

local function updateBillboard(p)
    local tag = ensureBillboard(p)
    if not tag then return end
    local c, _, r = aliveCharacter(p)
    local _, _, meR = aliveCharacter(LocalPlayer)
    local dist = meR and math.floor((r.Position - meR.Position).Magnitude) or 0
    local role = roleOf(p)
    local text = ""
    if Hub.state.lblRole then text = text .. role end
    if Hub.state.lblName then text = text .. (text ~= "" and "  •  " or "") .. p.Name end
    if Hub.state.lblDist then text = text .. (text ~= "" and "  •  " or "") .. tostring(dist) .. " st" end
    tag.BG.Text.Text = text
    tag.BG.Text.TextColor3 = roleColor(role)
    tag.Enabled = Hub.state.esp and (Hub.state.lblRole or Hub.state.lblName or Hub.state.lblDist)
end

local function setupEsp(p)
    if p == LocalPlayer then return end
    if not Hub.esp[p] then
        Hub.esp[p] = {box = drawingSquare(), tracer = drawingLine(), name = drawingText(), role = drawingText(), dist = drawingText(), bones = {}}
        local e = Hub.esp[p]
        for _, b in ipairs({"Head","UpperTorso","LowerTorso","LeftUpperArm","LeftLowerArm","LeftHand","RightUpperArm","RightLowerArm","RightHand","LeftUpperLeg","LeftLowerLeg","LeftFoot","RightUpperLeg","RightLowerLeg","RightFoot"}) do
            e.bones[b] = drawingLine()
        end
    end
end

local function bonePairs()
    return {
        {"Head","UpperTorso"},{"UpperTorso","LowerTorso"},
        {"UpperTorso","LeftUpperArm"},{"LeftUpperArm","LeftLowerArm"},{"LeftLowerArm","LeftHand"},
        {"UpperTorso","RightUpperArm"},{"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},
        {"LowerTorso","LeftUpperLeg"},{"LeftUpperLeg","LeftLowerLeg"},{"LeftLowerLeg","LeftFoot"},
        {"LowerTorso","RightUpperLeg"},{"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"},
    }
end

local function ensureGuiEsp(p)
    local c,_,r = aliveCharacter(p)
    if not c or not r then return nil end
    local e = Hub.esp[p]
    if not e or not e.gui then
        e = e or {}
        local holder = Instance.new("Frame")
        holder.Name = "PulseESP"
        holder.BackgroundTransparency = 1
        holder.Size = U2(0,1,0,1)
        holder.Parent = espGui
        holder.ZIndex = 20
        e.gui = holder
        e.guiBox = Instance.new("Frame"); e.guiBox.BackgroundTransparency=1; e.guiBox.BorderSizePixel=0; e.guiBox.Parent=holder; uiCorner(e.guiBox,3)
        local bs=Instance.new("UIStroke"); bs.Thickness=1.4; bs.Parent=e.guiBox; e.guiBoxStroke=bs
        e.guiTracer=Instance.new("Frame"); e.guiTracer.BorderSizePixel=0; e.guiTracer.AnchorPoint=Vector2.new(0.5,1); e.guiTracer.Parent=holder; uiCorner(e.guiTracer,2)
        e.guiHead=Instance.new("Frame"); e.guiHead.BackgroundTransparency=1; e.guiHead.BorderSizePixel=0; e.guiHead.Parent=holder; uiCorner(e.guiHead,10)
        local hs=Instance.new("UIStroke"); hs.Thickness=1.5; hs.Parent=e.guiHead; e.guiHeadStroke=hs
        e.guiText=Instance.new("TextLabel"); e.guiText.BackgroundTransparency=1; e.guiText.Size=U2(0,240,0,56); e.guiText.AnchorPoint=Vector2.new(0.5,1); e.guiText.Font=Enum.Font.GothamSemibold; e.guiText.TextSize=11; e.guiText.TextStrokeTransparency=0.55; e.guiText.TextYAlignment=Enum.TextYAlignment.Bottom; e.guiText.Parent=holder
        e.guiBones={}
        for i=1,14 do local ln=Instance.new("Frame"); ln.BorderSizePixel=0; ln.Parent=holder; uiCorner(ln,2); e.guiBones[i]=ln end
        Hub.esp[p]=e
    end
    return e
end

local function guiLine(frame, a, b, col, visible)
    local d=b-a
    frame.Visible=visible and d.Magnitude>1
    frame.Position=U2(0,a.X,0,a.Y)
    frame.Size=U2(0,d.Magnitude,0,2)
    frame.Rotation=math.deg(math.atan2(d.Y,d.X))
    frame.BackgroundColor3=col
end

local function espGuiStep()
    for _,p in ipairs(Players:GetPlayers()) do
        if p~=LocalPlayer then
            local e=ensureGuiEsp(p)
            local c,h,r=aliveCharacter(p)
            if e and Hub.state.esp and c and h and h.Health>0 and r then
                local me=select(3,aliveCharacter(LocalPlayer))
                local head=c:FindFirstChild("Head")
                local top3=head and (head.Position+V3(0,0.6,0)) or r.Position
                local bot3=r.Position-V3(0,3,0)
                local top,on1=Camera:WorldToViewportPoint(top3); local bot,on2=Camera:WorldToViewportPoint(bot3); local rp,on3=Camera:WorldToViewportPoint(r.Position)
                local ok=on1 and on2 and on3 and top.Z>0 and bot.Z>0
                if ok then
                    local height=math.max(18,math.abs(bot.Y-top.Y)); local width=math.max(14,height*0.55); local x=rp.X
                    local col=roleColor(roleOf(p))
                    e.gui.Visible=true; e.guiBox.Visible=Hub.state.espBox; e.guiBox.Position=U2(0,x-width/2,0,top.Y); e.guiBox.Size=U2(0,width,0,height); e.guiBoxStroke.Color=col
                    e.guiHead.Visible=Hub.state.espSkel; e.guiHead.Position=U2(0,x,0,top.Y+6); e.guiHead.Size=U2(0,10,0,10); e.guiHeadStroke.Color=col
                    e.guiTracer.Visible=Hub.state.espTracer; e.guiTracer.Position=U2(0,Camera.ViewportSize.X/2,0,Camera.ViewportSize.Y); e.guiTracer.Size=U2(0,math.max(1,(Vector2.new(x,bot.Y)-Vector2.new(Camera.ViewportSize.X/2,Camera.ViewportSize.Y)).Magnitude),0,2); e.guiTracer.Rotation=math.deg(math.atan2(bot.Y-Camera.ViewportSize.Y,x-Camera.ViewportSize.X/2)); e.guiTracer.BackgroundColor3=col
                    local txt=""; if Hub.state.lblRole then txt=tr(roleOf(p)) end; if Hub.state.lblName then txt=txt..(txt~="" and "  •  " or "")..p.Name end; if Hub.state.lblDist and me then txt=txt..(txt~="" and "  •  " or "")..tostring(math.floor((r.Position-me.Position).Magnitude)).." st" end
                    e.guiText.Text=txt; e.guiText.TextColor3=col; e.guiText.Visible=txt~=""; e.guiText.Position=U2(0,x,0,top.Y-4)
                    local pairs=bonePairs(); for i,pair in ipairs(pairs) do local ln=e.guiBones[i]; local a=c:FindFirstChild(pair[1]); local b=c:FindFirstChild(pair[2]); if a and b and Hub.state.espSkel then local ap,ao=Camera:WorldToViewportPoint(a.Position); local bp,bo=Camera:WorldToViewportPoint(b.Position); guiLine(ln,Vector2.new(ap.X,ap.Y),Vector2.new(bp.X,bp.Y),col,ao and bo and ap.Z>0 and bp.Z>0) else ln.Visible=false end end
                else
                    e.gui.Visible=false
                end
            elseif e and e.gui then e.gui.Visible=false end
        end
    end
end

local function espStep()
    espGuiStep()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            setupEsp(p)
            updateBillboard(p)
            local e = Hub.esp[p]
            local c, h, r = aliveCharacter(p)
            if not Hub.state.esp or not c or not h or h.Health <= 0 or not r then
                for _, o in pairs(e) do
                    if type(o) == "table" then for _, q in pairs(o) do pcall(function() q.Visible = false end) end
                    else pcall(function() o.Visible = false end) end
                end
            elseif Hub.state.esp then
                local pos, on = Camera:WorldToViewportPoint(r.Position)
                if not on or pos.Z <= 0 then
                    for _, o in pairs(e) do if type(o) == "table" then for _, q in pairs(o) do pcall(function() q.Visible = false end) end else pcall(function() o.Visible = false end) end end
                else
                    local head = c:FindFirstChild("Head")
                    local top = head and Camera:WorldToViewportPoint(head.Position + V3(0,0.6,0)) or pos
                    local bottom = Camera:WorldToViewportPoint(r.Position - V3(0,3,0))
                    local height = math.abs(top.Y - bottom.Y)
                    local width = math.max(12, height * 0.55)
                    local col = roleColor(roleOf(p))
                    if e.box then
                        e.box.Position = Vector2.new(pos.X - width/2, top.Y)
                        e.box.Size = Vector2.new(width, height)
                        e.box.Color = col; e.box.Visible = Hub.state.espBox
                    end
                    if e.tracer then
                        e.tracer.From = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y)
                        e.tracer.To = Vector2.new(pos.X, bottom.Y)
                        e.tracer.Color = col; e.tracer.Visible = Hub.state.espTracer
                    end
                    local tlist = {{e.name, Hub.state.lblName, p.Name}, {e.role, Hub.state.lblRole, roleOf(p)}, {e.dist, Hub.state.lblDist, tostring(math.floor((r.Position - (select(3, aliveCharacter(LocalPlayer))).Position).Magnitude)) .. " st"}}
                    for _, q in ipairs(tlist) do
                        if q[1] then q[1].Text = q[3]; q[1].Position = Vector2.new(pos.X, top.Y + 14 + (_-1)*13); q[1].Color = col; q[1].Visible = q[2] end
                    end
                    for _, pair in ipairs(bonePairs()) do
                        local a, b = c:FindFirstChild(pair[1]), c:FindFirstChild(pair[2])
                        local ln = e.bones[pair[1] .. ":" .. pair[2]] or nil
                        if not ln then ln = drawingLine(); e.bones[pair[1] .. ":" .. pair[2]] = ln end
                        if ln and a and b then
                            local ap, ao = Camera:WorldToViewportPoint(a.Position); local bp, bo = Camera:WorldToViewportPoint(b.Position)
                            ln.From = Vector2.new(ap.X, ap.Y); ln.To = Vector2.new(bp.X, bp.Y); ln.Color = col; ln.Visible = Hub.state.espSkel and ao and bo
                        elseif ln then ln.Visible = false end
                    end
                end
            end
        end
    end
end

local function gunEspStep()
    local drop = findGunDrop()
    local h = workspace:FindFirstChild("PulseGun", true)
    if Hub.state.gunEsp and drop then
        if not h or not h:IsA("Highlight") then
            if h then h:Destroy() end
            h = Instance.new("Highlight")
            h.Name = "PulseGun"
            h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            h.Parent = drop
        end
        h.FillColor = C3(112, 177, 255)
        h.OutlineColor = C3(220, 241, 255)
        h.FillTransparency = 0.25
        h.OutlineTransparency = 0
    elseif h then
        h:Destroy()
    end
end

local function applyChams(p)
    local c = p.Character
    if not c then return end
    local h = c:FindFirstChild("PulseCham")
    if Hub.state.chams then
        if not h then h = Instance.new("Highlight"); h.Name = "PulseCham"; h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; h.Parent = c end
        h.FillColor = roleColor(roleOf(p)); h.OutlineColor = roleColor(roleOf(p)); h.FillTransparency = Hub.state.chamsTrans / 100; h.OutlineTransparency = 0.1
    elseif h then h:Destroy() end
end

local function applyTrail()
    local c, _, root = aliveCharacter(LocalPlayer)
    if not c or not root then return end
    local a0 = root:FindFirstChild("PulseTrailA0")
    local a1 = root:FindFirstChild("PulseTrailA1")
    local tr = root:FindFirstChild("PulseTrail")
    if not Hub.state.trail then
        if tr then tr:Destroy() end
        if a0 then a0:Destroy() end
        if a1 then a1:Destroy() end
        return
    end
    if not a0 then a0 = Instance.new("Attachment"); a0.Name = "PulseTrailA0"; a0.Position = V3(0,1,0); a0.Parent = root end
    if not a1 then a1 = Instance.new("Attachment"); a1.Name = "PulseTrailA1"; a1.Position = V3(0,-1,0); a1.Parent = root end
    if not tr then tr = Instance.new("Trail"); tr.Name = "PulseTrail"; tr.Attachment0 = a0; tr.Attachment1 = a1; tr.Lifetime = Hub.state.trailLife; tr.LightEmission = 0.7; tr.Parent = root end
    tr.Lifetime = Hub.state.trailLife
    if Hub.state.trailColor == "Rainbow" then
        local h = (os.clock() * 0.2) % 1
        tr.Color = ColorSequence.new(Color3.fromHSV(h,0.55,1), Color3.fromHSV((h+0.2)%1,0.55,1))
    elseif Hub.state.trailColor == "Pink" then
        tr.Color = ColorSequence.new(C3(255,170,208), C3(244,202,255))
    elseif Hub.state.trailColor == "White" then
        tr.Color = ColorSequence.new(C3(255,255,255), C3(211,237,255))
    else
        tr.Color = ColorSequence.new(C3(126,191,255), C3(205,235,255))
    end
end

local function applyPostFX()
    local function fx(className, name)
        local o = Lighting:FindFirstChild(name)
        if not o then o = Instance.new(className); o.Name = name; o.Parent = Lighting end
        return o
    end
    local bloom = fx("BloomEffect", "PulseBloom")
    bloom.Enabled = Hub.state.bloom; bloom.Intensity = Hub.state.bloomInt; bloom.Size = Hub.state.bloomSize; bloom.Threshold = Hub.state.bloomThr
    local atmo = fx("Atmosphere", "PulseAtmosphere")
    atmo.Enabled = Hub.state.atmo; atmo.Density = Hub.state.atmoDensity/100; atmo.Haze = Hub.state.atmoHaze
    local rays = fx("SunRaysEffect", "PulseRays")
    rays.Enabled = Hub.state.rays; rays.Intensity = Hub.state.raysInt; rays.Spread = Hub.state.raysSpread
    local blur = fx("BlurEffect", "PulseBlur")
    blur.Enabled = Hub.state.blur; blur.Size = Hub.state.blurSize
    local dof = fx("DepthOfFieldEffect", "PulseDof")
    dof.Enabled = Hub.state.dof; dof.FarIntensity = Hub.state.dofFar/100; dof.FocusDistance = Hub.state.dofFocus; dof.InFocusRadius = Hub.state.dofRadius
    local fog = Lighting:FindFirstChild("PulseFog")
    if not fog then fog = Instance.new("Atmosphere"); fog.Name = "PulseFog"; fog.Parent = Lighting end
    fog.Enabled = Hub.state.fog; fog.Density = math.clamp(1200 / math.max(Hub.state.fogEnd, 50), 0.01, 0.35); fog.Haze = 2
end

local function saveOriginalLighting()
    for _, n in ipairs({"Brightness","ClockTime","ExposureCompensation","FogEnd","GlobalShadows","OutdoorAmbient","Ambient"}) do
        Hub.originalLighting[n] = Lighting[n]
    end
end

local function setPreset(id)
    for _, o in pairs(Hub.presetObjects) do pcall(function() o:Destroy() end) end
    Hub.presetObjects = {}
    if not id then
        for k,v in pairs(Hub.originalLighting) do pcall(function() Lighting[k] = v end) end
        return
    end
    local n = id
    local b = tonumber(Hub.state["preset_"..n.."_brightness"]) or 2
    local c = tonumber(Hub.state["preset_"..n.."_clock"]) or 13
    local e = tonumber(Hub.state["preset_"..n.."_exposure"]) or 0
    local ambient, outdoor
    if id == "night" then ambient, outdoor = C3(45,60,90), C3(55,75,105)
    elseif id == "realism" then ambient, outdoor = C3(150,170,190), C3(140,160,180)
    elseif id == "future" then ambient, outdoor = C3(175,225,255), C3(155,200,240)
    elseif id == "studio" then ambient, outdoor = C3(210,220,230), C3(190,205,220)
    elseif id == "desert" then ambient, outdoor = C3(235,215,180), C3(230,200,165)
    else ambient, outdoor = C3(205,225,240), C3(195,218,235) end
    pcall(function()
        Lighting.ClockTime=c; Lighting.Brightness=b; Lighting.ExposureCompensation=e
        Lighting.Ambient=ambient; Lighting.OutdoorAmbient=outdoor
    end)
end

local function applyOptimizations()
    Hub.optStore = Hub.optStore or {}
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("Texture") or d:IsA("Decal") then
            Hub.optStore[d] = Hub.optStore[d] or {transparency=d.Transparency}
            d.Transparency = Hub.state.optTex and 1 or Hub.optStore[d].transparency
        elseif d:IsA("ParticleEmitter") or d:IsA("Trail") then
            Hub.optStore[d] = Hub.optStore[d] or {enabled=d.Enabled}
            d.Enabled = Hub.state.optPart and false or Hub.optStore[d].enabled
        elseif d:IsA("BasePart") then
            Hub.optStore[d] = Hub.optStore[d] or {shadow=d.CastShadow, material=d.Material, reflect=(d:IsA("MeshPart") and d.Reflectance or nil)}
            d.CastShadow = Hub.state.optShadow and false or Hub.optStore[d].shadow
            if d:IsA("MeshPart") then pcall(function() d.Reflectance = Hub.state.optRefl and 0 or Hub.optStore[d].reflect end) end
            d.Material = Hub.state.optLow and Enum.Material.Plastic or Hub.optStore[d].material
        end
    end
end

local function fpsApply()
    if canFPS and Hub.state.fpsUnlock then pcall(function() setfpscap(Hub.state.fpsCap) end) end
end

local function setAnimations(pack)
    local c = LocalPlayer.Character
    if not c then return end
    local animate = c:FindFirstChild("Animate")
    if not animate then return end
    local packs = {
        Bubbly = {run=910025107, walk=910034870, jump=910016857, idle=910004836},
        Cartoony = {run=742638842, walk=742640026, jump=742637942, idle=742637544},
        Ninja = {run=656118852, walk=656121766, jump=656117878, idle=656117400},
        Pirate = {run=750783738, walk=750785693, jump=750782230, idle=750781874},
        Robot = {run=616091570, walk=616095330, jump=616090535, idle=616088211},
        Mage = {run=707861613, walk=707897309, jump=707853694, idle=707742142},
        Astronaut = {run=891636393, walk=891636393, jump=891627522, idle=891621366},
        Knight = {run=657564596, walk=657552124, jump=658409194, idle=657595757},
    }
    local p = packs[pack]
    if not p then return end
    local function setId(path, id)
        local x = path and path:FindFirstChildOfClass("Animation")
        if x then x.AnimationId = "rbxassetid://" .. tostring(id) end
    end
    setId(animate:FindFirstChild("run"), p.run)
    setId(animate:FindFirstChild("walk"), p.walk)
    setId(animate:FindFirstChild("jump"), p.jump)
    setId(animate:FindFirstChild("idle"), p.idle)
    for _, d in ipairs(c:GetDescendants()) do
        if d:IsA("AnimationTrack") then pcall(function() d:AdjustSpeed(Hub.state.packSpeed) end) end
    end
end

local function playEmote(name)
    local _, h = aliveCharacter(LocalPlayer)
    if not h then return end
    if type(h.PlayEmote) == "function" then pcall(function() h:PlayEmote(name) end); return end
    local emotes = {Wave="/e wave", Cheer="/e cheer", Laugh="/e laugh", Dance="/e dance", Dance2="/e dance2", Dance3="/e dance3", Point="/e point"}
    local command = emotes[name]
    if command then pcall(function() game:GetService("ReplicatedStorage").DefaultChatSystemChatEvents.SayMessageRequest:FireServer(command, "All") end) end
end

local function setKorblox(on)
    local c = LocalPlayer.Character
    if not c then return end
    local desc = c:FindFirstChildOfClass("Humanoid") and c:FindFirstChildOfClass("Humanoid"):GetAppliedDescription()
    if not desc then return end
    if on then pcall(function() desc.RightLeg = 139607718; c:FindFirstChildOfClass("Humanoid"):ApplyDescription(desc) end)
    else
        pcall(function() c:FindFirstChildOfClass("Humanoid"):ApplyDescription(Players:GetHumanoidDescriptionFromUserId(LocalPlayer.UserId)) end)
    end
end

local function setHeadless(on)
    local c = LocalPlayer.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    if not h then return end
    local head = c:FindFirstChild("Head")
    if on and head then head.Transparency = 1; destroyName(head, {"face"})
    elseif head then head.Transparency = 0 end
end

local function clearToy()
    local c=LocalPlayer.Character
    if c then destroyName(c,{"PulseToy","PulseToyRing","PulseToyOrb","PulseToyBalloon"}) end
end

local function makeToy(name)
    clearToy()
    local _,_,r=aliveCharacter(LocalPlayer); if not r then return end
    if name=="Halo" then
        local ring=Instance.new("Part"); ring.Name="PulseToyRing"; ring.Anchored=true; ring.CanCollide=false; ring.Shape=Enum.PartType.Cylinder; ring.Size=V3(3,0.18,3); ring.Material=Enum.Material.Neon; ring.Color=C3(206,236,255); ring.CFrame=r.CFrame*CFrame.new(0,3.1,0)*CFrame.Angles(0,0,math.rad(90)); ring.Parent=r;
        pushCleanup(function() if ring then ring:Destroy() end end)
    elseif name=="Balloon" then
        local ball=Instance.new("Part"); ball.Name="PulseToyBalloon"; ball.Shape=Enum.PartType.Ball; ball.Size=V3(1.5,1.5,1.5); ball.Material=Enum.Material.SmoothPlastic; ball.Color=C3(183,220,255); ball.Anchored=true; ball.CanCollide=false; ball.Parent=r
        local rope=Instance.new("Beam"); local a0=Instance.new("Attachment",r); local a1=Instance.new("Attachment",ball); a0.Position=V3(0,1,0); a1.Position=V3(0,-0.8,0); rope.Attachment0=a0; rope.Attachment1=a1; rope.Width0=0.02; rope.Width1=0.02; rope.Parent=r;
        pushCleanup(function() pcall(function() ball:Destroy(); rope:Destroy(); a0:Destroy(); a1:Destroy() end) end)
    else
        local orb=Instance.new("Part"); orb.Name="PulseToyOrb"; orb.Shape=Enum.PartType.Ball; orb.Size=V3(1,1,1); orb.Material=Enum.Material.Neon; orb.Color=C3(166,214,255); orb.Anchored=true; orb.CanCollide=false; orb.Parent=r
        pushCleanup(function() if orb then orb:Destroy() end end)
    end
end

local function setSpeed()
    local _, h = aliveCharacter(LocalPlayer)
    if h then h.WalkSpeed = Hub.state.speedOn and Hub.state.walkSpeed or 16 end
end

local function setJump()
    local _, h = aliveCharacter(LocalPlayer)
    if h then pcall(function() h.JumpPower = Hub.state.jumpOn and Hub.state.jumpPower or 50 end) end
end

local function setLocalInvisible(on)
    local c = LocalPlayer.Character
    if not c then return end
    for _,d in ipairs(c:GetDescendants()) do
        if d:IsA("BasePart") then
            d.LocalTransparencyModifier = on and 1 or 0
        elseif d:IsA("Decal") or d:IsA("Texture") then
            d.Transparency = on and 1 or 0
        elseif d:IsA("ParticleEmitter") or d:IsA("Trail") then
            d.Enabled = not on
        end
    end
end

local function bombJump()
    local _, _, r = aliveCharacter(LocalPlayer)
    if r then r.AssemblyLinearVelocity = V3(0, Hub.state.bombPower, 0) end
end

local function orbitTarget()
    if Hub.state.orbitTarget == "Murderer" then return nearestTarget(function(p) return roleOf(p) == "Murderer" end)
    elseif Hub.state.orbitTarget == "Sheriff" then return nearestTarget(function(p) return roleOf(p) == "Sheriff" end)
    else return nearestTarget() end
end

local function animationToSpeed()
    for _, d in ipairs(LocalPlayer.Character and LocalPlayer.Character:GetDescendants() or {}) do
        if d:IsA("AnimationTrack") then pcall(function() d:AdjustSpeed(Hub.state.emoteSpeed) end) end
    end
end

local function musicStop()
    if Hub.musicSound then pcall(function() Hub.musicSound:Stop(); Hub.musicSound:Destroy() end); Hub.musicSound=nil end
end

local function musicPlayRandom()
    if #Hub.state.songs == 0 then return end
    musicStop()
    local id = Hub.state.songs[math.random(1,#Hub.state.songs)]
    local s = Instance.new("Sound")
    s.Name = "PulseRoundMusic"; s.SoundId = "rbxassetid://" .. tostring(id); s.Volume = Hub.state.musicVol/100
    s.Looped = false; s.Parent = SoundService; Hub.musicSound = s
    task.delay(Hub.state.musicDelay, function() if Hub.alive and s.Parent and Hub.state.music then pcall(function() s:Play() end) end end)
end

local function serverHop(small)
    local servers = nil
    if type(request) == "function" then
        local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
        local ok, res = pcall(function() return request({Url=url, Method="GET"}) end)
        if ok and res and res.Body then servers = safe(function() return HttpService:JSONDecode(res.Body) end) end
    end
    local best
    if servers and servers.data then
        for _, sv in ipairs(servers.data) do
            if sv.playing < sv.maxPlayers and sv.id ~= game.JobId then
                if not small or sv.playing <= math.max(3, math.floor(sv.maxPlayers*0.35)) then best = sv.id; break end
            end
        end
    end
    if best then TeleportService:TeleportToPlaceInstance(game.PlaceId, best, LocalPlayer) else TeleportService:Teleport(game.PlaceId, LocalPlayer) end
end

local function setAntiAfk(on)
    Hub.state.antiAfk = on
    if Hub.afkConn then pcall(function() Hub.afkConn:Disconnect() end); Hub.afkConn=nil end
    if on then
        local vu = game:GetService("VirtualUser")
        Hub.afkConn = LocalPlayer.Idled:Connect(function()
            pcall(function() vu:Button2Down(Vector2.new(0,0), Camera.CFrame); task.wait(0.1); vu:Button2Up(Vector2.new(0,0), Camera.CFrame) end)
        end)
        pushCleanup(function() pcall(function() Hub.afkConn:Disconnect() end) end)
    end
end

local function setDesync()
    if not Hub.state.desync then return end
    local _, _, r = aliveCharacter(LocalPlayer)
    if not r then return end
    local t = os.clock() * Hub.state.desyncSpeed / 5
    local off
    if Hub.state.desyncMode == "Jitter" then off = V3(math.sin(t)*Hub.state.desyncRadius,0,math.cos(t)*Hub.state.desyncRadius)
    elseif Hub.state.desyncMode == "Orbit" then off = V3(math.cos(t),0,math.sin(t)) * Hub.state.desyncRadius
    elseif Hub.state.desyncMode == "Vertical" then off = V3(0,math.sin(t)*Hub.state.desyncRadius,0)
    elseif Hub.state.desyncMode == "Behind" then off = -r.CFrame.LookVector * Hub.state.desyncRadius
    else off = r.CFrame.RightVector * Hub.state.desyncRadius end
    r.CFrame = r.CFrame + off
end

local function faceThreat()
    if not Hub.state.faceThreat then return end
    local p = nearestTarget()
    local _, _, r = aliveCharacter(LocalPlayer)
    local _, _, tr = aliveCharacter(p)
    if r and tr then r.CFrame = CFrame.lookAt(r.Position, tr.Position) end
end

local function farmStep()
    if not Hub.state.farm or not roundActive() then return end
    local _, _, r = aliveCharacter(LocalPlayer)
    if not r then return end
    local count = bagCount()
    if Hub.state.farmReset and count and count >= 40 then
        local h = select(2, aliveCharacter(LocalPlayer)); if h then h.Health = 0 end
        return
    end
    local nearest, d = nil, math.huge
    for _, c in ipairs(coinParts()) do
        if c and c.Parent then
            local dd = (c.Position - r.Position).Magnitude
            if dd < d then nearest, d = c, dd end
        end
    end
    if not nearest then return end
    if Hub.state.farmAvoid then
        local m = nearestTarget(function(p) return roleOf(p)=="Murderer" end)
        local _,_,mr = aliveCharacter(m)
        if mr and (mr.Position-r.Position).Magnitude < 18 then return end
    end
    if Hub.state.farmVersion == "Teleport" then
        r.CFrame = nearest.CFrame + V3(0,2,0)
    else
        local distance = (nearest.Position - r.Position).Magnitude
        local duration = math.max(0.02, distance / math.max(Hub.state.farmSpeed, 1))
        safe(function() TweenService:Create(r, TweenInfo.new(duration, Enum.EasingStyle.Linear), {CFrame=nearest.CFrame+V3(0,2,0)}):Play() end)
    end
end

local function installSilentHook()
    if Hub.silentHookInstalled or not canHook then return end
    local old
    old = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        local args = {...}
        if Hub.alive and Hub.state.aimOn and Hub.state.aimVersion == "Silent" and (method == "InvokeServer" or method == "FireServer") then
            local gun = equippedGun()
            local target = targetByFov() or select(1, playersRoleTarget())
            if gun and target and (self:IsDescendantOf(gun) or self.Name:lower():find("beam",1,true)) then
                local pos = predictedPosition(target, Hub.state.predict)
                if pos then
                    for i, v in ipairs(args) do if typeof(v) == "Vector3" then args[i] = pos; break end end
                    return old(self, table.unpack(args))
                end
            end
        end
        return old(self, ...)
    end)
    Hub.silentHookInstalled = true
end

local function fovInit()
    if hasDrawing and not Hub.fovDrawing then
        local c = Drawing.new("Circle")
        c.Visible = false; c.Filled = false; c.Thickness = 1.3; c.NumSides = 64; c.Transparency = 0.9
        c.Color = C3(139,210,247)
        Hub.fovDrawing = c
        pushCleanup(function() pcall(function() c:Remove() end) end)
    end
end

local function fovStep()
    local visible = Hub.state.aimOn and Hub.state.fovShow
    local vp = Camera.ViewportSize
    if Hub.fovDrawing then
        local c = Hub.fovDrawing
        c.Position = Vector2.new(vp.X/2,vp.Y/2)
        c.Radius = Hub.state.fovRadius
        c.Visible = visible
    end
    fovGui.Position = U2(0,vp.X/2,0,vp.Y/2)
    fovGui.Size = U2(0,Hub.state.fovRadius*2,0,Hub.state.fovRadius*2)
    fovGui.Visible = visible and not Hub.fovDrawing
end

local function cameraAimStep()
    local knifeMode = Hub.state.knifeAim and equippedKnife() and Hub.rightDown
    if knifeMode then
        local p = nearestTarget(function(x) return roleOf(x)=="Sheriff" or roleOf(x)=="Hero" end)
        local _,_,r = aliveCharacter(p)
        if r then
            local pos = predictedPosition(p, Hub.state.knifeLead) or r.Position
            local from = Camera.CFrame.Position
            Camera.CFrame = Camera.CFrame:Lerp(CFrame.lookAt(from,pos), math.clamp(Hub.state.aimSpeed/100,0.02,1))
        end
        return
    end
    if not Hub.state.aimOn or Hub.state.aimVersion ~= "Camera" or not Hub.rightDown then return end
    local p = targetByFov() or select(1, playersRoleTarget())
    local _, _, r = aliveCharacter(p)
    if not r then return end
    local pos = predictedPosition(p, Hub.state.predict) or r.Position
    local from = Camera.CFrame.Position
    local wanted = CFrame.lookAt(from, pos)
    local alpha = math.clamp(Hub.state.aimSpeed/100, 0.02, 1)
    local old = Camera.CFrame
    Camera.CFrame = old:Lerp(wanted, alpha)
end

local function aimReturn()
    if not Hub.state.aimReturn then return end
end

local function initBacktrack()
    if Hub.backtrackConn then return end
    Hub.backtrackConn = RunService.Heartbeat:Connect(function()
        if not Hub.state.backtrack then return end
        local now = os.clock()
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then
                local _, h, r = aliveCharacter(p)
                if h and h.Health > 0 and r then
                    Hub.backtrack[p] = Hub.backtrack[p] or {}
                    table.insert(Hub.backtrack[p], {t=now, cf=r.CFrame})
                    while #Hub.backtrack[p] > 20 or (Hub.backtrack[p][1] and now - Hub.backtrack[p][1].t > 0.75) do table.remove(Hub.backtrack[p], 1) end
                end
            end
        end
    end)
    pushCleanup(function() pcall(function() Hub.backtrackConn:Disconnect() end) end)
end

local function renderBacktrack()
    if not Hub.state.backtrack then
        for _,e in pairs(Hub.backtrack) do
            if e.ghost then pcall(function() e.ghost:Destroy() end); e.ghost=nil end
        end
        return
    end
    local targetT=os.clock()-Hub.state.backMs/1000
    for p,hist in pairs(Hub.backtrack) do
        if hist and #hist>0 then
            local sample=hist[1]
            for i=#hist,1,-1 do if hist[i].t<=targetT then sample=hist[i]; break end end
            local c=p.Character; local r=c and c:FindFirstChild("HumanoidRootPart")
            if r then
                local entry=Hub.backtrack[p]
                local ghost=entry.ghost
                if not ghost then
                    ghost=Instance.new("Part"); ghost.Name="PulseBackGhost"; ghost.Anchored=true; ghost.CanCollide=false; ghost.CanQuery=false; ghost.CanTouch=false; ghost.Material=Enum.Material.ForceField; ghost.Transparency=0.72; ghost.Size=V3(3,5,2); ghost.Parent=workspace; entry.ghost=ghost
                end
                ghost.CFrame=sample.cf; ghost.Color=roleColor(roleOf(p)); ghost.Transparency=0.72
            end
        end
    end
end

local function roundLoops()
    task.spawn(function()
        while Hub.alive do
            if Hub.state.killAura and equippedKnife() then
                local meRoot = select(3, aliveCharacter(LocalPlayer))
                if meRoot then
                    for _, p in ipairs(Players:GetPlayers()) do
                        if p ~= LocalPlayer then
                            local _, h, r = aliveCharacter(p)
                            local okTarget = Hub.state.killMode == "All" or roleOf(p) == "Sheriff"
                            if okTarget and h and h.Health > 0 and r and (r.Position-meRoot.Position).Magnitude <= Hub.state.killRadius then stab() end
                        end
                    end
                end
            end
            if Hub.state.autoPickup then pickupGun() end
            if Hub.state.autoKill then
                local m = nearestTarget(function(p) return roleOf(p)=="Murderer" end)
                if m then shootAt(m) end
            elseif Hub.state.autoShoot then
                local t = targetByFov() or select(1, playersRoleTarget())
                if t then shootAt(t) end
            end
            if Hub.state.knifeAuto then
                local m = nearestTarget(function(p) return roleOf(p) ~= "Innocent" or true end)
                if m then
                    local _,_,r = aliveCharacter(m)
                    local _,_,me = aliveCharacter(LocalPlayer)
                    if r and me and (r.Position-me.Position).Magnitude <= 70 and (not Hub.state.knifeWall or visibleFrom(me.Position, r.Position, m.Character)) then knifeThrowAt(m) end
                end
            end
            if Hub.state.autoFlingSheriff then
                local s = nearestTarget(function(p) return roleOf(p)=="Sheriff" end)
                if s then fling(s, 0.8) end
            end
            if Hub.state.farm then farmStep() end
            task.wait(0.05)
        end
    end)
end

task.spawn(function()
    while Hub.alive do
        if Hub.state.emoteHold then
            playEmote(Hub.state.emoteSel)
            task.wait(2.2)
        else
            task.wait(0.4)
        end
    end
end)

local function playerWatch()
    pushConn(Players.PlayerAdded:Connect(function(p)
        Hub.roleCache[p] = nil
        pushConn(p.CharacterAdded:Connect(function() task.wait(0.5); if Hub.state.trail and p==LocalPlayer then applyTrail() end end))
    end))
    pushConn(Players.PlayerRemoving:Connect(function(p) clearEspFor(p); Hub.roleCache[p]=nil; Hub.backtrack[p]=nil end))
    for _,p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            pushConn(p.CharacterAdded:Connect(function() task.wait(0.2); applyChams(p) end))
        end
    end
end

-- UI -------------------------------------------------------------------------
local RU = {
    ['VISUALS'] = 'ВИЗУАЛ',
    ['MAIN'] = 'ОСНОВНОЕ',
    ['PLAYERS'] = 'ИГРОКИ',
    ['Combat'] = 'Бой',
    ['Player'] = 'Игрок',
    ['Animations & Troll'] = 'Анимации и троллинг',
    ['World'] = 'Мир',
    ['System'] = 'Система',
    ['WORLD'] = 'МИР',
    ['POST FX'] = 'ЭФФЕКТЫ',
    ['PLAYER FX'] = 'ЭФФЕКТЫ ИГРОКА',
    ['ESP'] = 'ESP',
    ['POST FX'] = 'ЭФФЕКТЫ',
    ['WEAPONS'] = 'ОРУЖИЕ',
    ['KNIFE'] = 'НОЖ',
    ['FAKE POSITION'] = 'ФЕЙКОВАЯ ПОЗИЦИЯ',
    ['CONFIG'] = 'КОНФИГ',
    ['ANIMATIONS'] = 'АНИМАЦИИ',
    ['AUTOFARM'] = 'АВТОФАРМ',
    ['TELEPORT'] = 'ТЕЛЕПОРТ',
    ['TROLL'] = 'ТРОЛЛИНГ',
    ['OPTIMIZATION'] = 'ОПТИМИЗАЦИЯ',
    ['LIGHTING PRESETS'] = 'ПРЕСЕТЫ ОСВЕЩЕНИЯ',
    ['KILL RADIUS'] = 'РАДИУС КИЛЛА',
    ['Kill radius'] = 'Радиус килла',
    ['Kill targets'] = 'Цели килла',
    ['Desync mode'] = 'Режим десинка',
    ['Desync radius'] = 'Радиус десинка',
    ['Desync speed'] = 'Скорость десинка',
    ['Knife lead'] = 'Упреждение ножа',
    ['Knife wall check'] = 'Проверка стен ножом',
    ['Trail length'] = 'Длина следа',
    ['Save config now'] = 'Сохранить конфиг сейчас',
    ['Stop'] = 'Остановить',
    ['brightness'] = 'яркость',
    ['clock'] = 'время',
    ['exposure'] = 'экспозиция',
    ['preset applied'] = 'пресет применён',
    ['AIM'] = 'АИМБОТ',
    ['FOV'] = 'FOV',
    ['MELEE'] = 'БЛИЖНИЙ БОЙ',
    ['GUN'] = 'ПИСТОЛЕТ',
    ['KNIFE'] = 'НОЖ',
    ['DESYNC'] = 'ДЕСИНК',
    ['EXTRAS'] = 'ДОПОЛНЕНИЯ',
    ['MOVEMENT'] = 'ПЕРЕДВИЖЕНИЕ',
    ['COINS'] = 'МОНЕТЫ',
    ['QUICK TELEPORT'] = 'БЫСТРЫЙ ТЕЛЕПОРТ',
    ['PACKS'] = 'ПАКИ',
    ['EMOTES'] = 'ЭМОУТЫ',
    ['AVATAR'] = 'АВАТАР',
    ['TOYS / EMOTES'] = 'ИГРУШКИ / ЭМОУТЫ',
    ['SPEED / JUMP'] = 'СКОРОСТЬ / ПРЫЖОК',
    ['FLING / ORBIT'] = 'ФЛИНГ / ОРБИТА',
    ['ROUND MUSIC'] = 'МУЗЫКА РАУНДА',
    ['SONGS'] = 'ПЕСНИ',
    ['PRESETS'] = 'ПРЕСЕТЫ',
    ['REMOVE'] = 'УДАЛЕНИЕ',
    ['FPS'] = 'FPS',
    ['SERVER'] = 'СЕРВЕР',
    ['INTERFACE'] = 'ИНТЕРФЕЙС',
    ['SCRIPT'] = 'СКРИПТ',
    ['ESP'] = 'ESP',
    ['Lighting'] = 'Освещение',
    ['Optimization'] = 'Оптимизация',
    ['Server'] = 'Сервер',
    ['Settings'] = 'Настройки',
    ['Silent aim'] = 'Сайлент аим',
    ['Kill aura'] = 'Килл-аура',
    ['Auto shoot'] = 'Автовыстрел',
    ['Knife aimbot'] = 'Аимбот ножа',
    ['Fake position'] = 'Фейковая позиция',
    ['Movement'] = 'Передвижение',
    ['Autofarm'] = 'Автофарм',
    ['Teleport'] = 'Телепорт',
    ['Animations'] = 'Анимации',
    ['Troll'] = 'Троллинг',
    ['Round music'] = 'Музыка раунда',
    ['Visuals'] = 'Визуал',
    ['RightShift'] = 'Правый Shift',
    ['PULSE  /  MM2'] = 'PULSE  /  MM2',
    ['precision hub  •  soft frost edition'] = 'точный хаб  •  нежный frost-дизайн',
    ['Menu key  •  all controls persist while injected'] = 'Клавиша меню  •  настройки сохраняются во время работы',
    ['Role ESP'] = 'ESP ролей',
    ['Boxes'] = 'Боксы',
    ['Skeleton'] = 'Скелет',
    ['Tracers'] = 'Трейсеры',
    ['Role'] = 'Роль',
    ['Nickname'] = 'Ник',
    ['Distance'] = 'Дистанция',
    ['Gun ESP'] = 'ESP пистолета',
    ['X-Ray'] = 'Рентген',
    ['Chams'] = 'Чамсы',
    ['Chams transparency'] = 'Прозрачность чамсов',
    ['Bloom'] = 'Блум',
    ['Bloom intensity'] = 'Интенсивность блум',
    ['Bloom size'] = 'Размер блум',
    ['Bloom threshold'] = 'Порог блум',
    ['Atmosphere'] = 'Атмосфера',
    ['Density'] = 'Плотность',
    ['Haze'] = 'Дымка',
    ['Sun rays'] = 'Лучи солнца',
    ['Ray intensity'] = 'Интенсивность лучей',
    ['Ray spread'] = 'Разброс лучей',
    ['Blur'] = 'Размытие',
    ['Blur size'] = 'Сила размытия',
    ['Depth of field'] = 'Глубина резкости',
    ['Far blur'] = 'Дальнее размытие',
    ['Focus distance'] = 'Дистанция фокуса',
    ['In-focus radius'] = 'Радиус резкости',
    ['Fog'] = 'Туман',
    ['Fog distance'] = 'Дальность тумана',
    ['Backtrack'] = 'Бэктрек',
    ['Backtrack time'] = 'Время бэктрека',
    ['Trail'] = 'След',
    ['Trail colour'] = 'Цвет следа',
    ['Enable aim'] = 'Включить аим',
    ['Aim version'] = 'Версия аима',
    ['Aim type'] = 'Тип аимбота',
    ['Flick speed'] = 'Скорость флика',
    ['Return flick'] = 'Возврат флика',
    ['Prediction'] = 'Предикт',
    ['Wall check'] = 'Проверка стен',
    ['Show FOV circle'] = 'Показать круг FOV',
    ['FOV radius'] = 'Радиус FOV',
    ['Radius'] = 'Радиус',
    ['Targets'] = 'Цели',
    ['Auto pick up gun'] = 'Автоподбор пистолета',
    ['Auto kill murderer'] = 'Автоубийство мардера',
    ['Auto fling sheriff'] = 'Автофлинг шерифа',
    ['Shoot murderer'] = 'Выстрелить в мардера',
    ['Get gun now'] = 'Взять пистолет',
    ['Lead'] = 'Упреждение',
    ['Auto throw'] = 'Автобросок',
    ['Throw at target'] = 'Бросить в цель',
    ['Mode'] = 'Режим',
    ['Speed'] = 'Скорость',
    ['Face threat'] = 'Смотреть на угрозу',
    ['Resolver'] = 'Резольвер',
    ['Noclip'] = 'Ноуклип',
    ['Infinite jump'] = 'Бесконечный прыжок',
    ['Anti-fling'] = 'Анти-флинг',
    ['Fly'] = 'Полёт',
    ['Spin'] = 'Спин',
    ['Bunny hop'] = 'Бхоп',
    ['Invisible'] = 'Невидимость (локально)',
    ['Bomb jump'] = 'Бомб-джамп',
    ['Fly speed'] = 'Скорость полёта',
    ['Spin speed'] = 'Скорость спина',
    ['Bomb power'] = 'Сила прыжка',
    ['Autofarm coins'] = 'Автофарм монет',
    ['Farm version'] = 'Версия фарма',
    ['Farm speed'] = 'Скорость фарма',
    ['Reset when bag is full'] = 'Авторесп при полной сумке',
    ['Avoid murderer'] = 'Обход мардера',
    ['Auto fling after respawn'] = 'Автофлинг после респа',
    ['Lobby'] = 'Лобби',
    ['Murderer'] = 'Мардер',
    ['Sheriff'] = 'Шериф',
    ['Pack'] = 'Пак',
    ['Pack speed'] = 'Скорость пака',
    ['Emote'] = 'Эмоут',
    ['Emote speed'] = 'Скорость эмоута',
    ['Hold mode'] = 'Режим удержания',
    ['Auto-load after respawn'] = 'Автозагрузка после респа',
    ['Play emote'] = 'Запустить эмоут',
    ['Stop emote'] = 'Остановить эмоут',
    ['Fake Korblox'] = 'Фейковый Korblox',
    ['Fake headless'] = 'Фейковый Headless',
    ['Toy'] = 'Игрушка',
    ['Equip toy'] = 'Надеть игрушку',
    ['Random emote'] = 'Случайный эмоут',
    ['Custom speed'] = 'Своя скорость',
    ['Walk speed'] = 'Скорость ходьбы',
    ['Custom jump'] = 'Свой прыжок',
    ['Jump power'] = 'Сила прыжка',
    ['Touch fling'] = 'Флинг касанием',
    ['Click fling'] = 'Флинг кликом',
    ['Orbit player'] = 'Орбита вокруг игрока',
    ['Orbit target'] = 'Цель орбиты',
    ['Orbit radius'] = 'Радиус орбиты',
    ['Orbit speed'] = 'Скорость орбиты',
    ['Auto-play on round start'] = 'Автозапуск в начале раунда',
    ['Start delay'] = 'Задержка старта',
    ['Volume'] = 'Громкость',
    ['Audio ID'] = 'ID аудио',
    ['Play random now'] = 'Включить случайную',
    ['Clear list'] = 'Очистить список',
    ['Night'] = 'Ночь',
    ['Realism'] = 'Реализм',
    ['Future'] = 'Future',
    ['Studio'] = 'Студия',
    ['Desert'] = 'Пустыня',
    ['Clean atmosphere'] = 'Чистая атмосфера',
    ['Remove textures'] = 'Убрать текстуры',
    ['Remove particles'] = 'Убрать частицы',
    ['Remove shadows'] = 'Убрать тени',
    ['Remove reflections'] = 'Убрать отражения',
    ['Low quality mode'] = 'Режим низкого качества',
    ['FPS unlock'] = 'Разлок FPS',
    ['FPS cap'] = 'Лимит FPS',
    ['Rejoin'] = 'Перезайти',
    ['Server hop'] = 'Сменить сервер',
    ['Small server'] = 'Маленький сервер',
    ['Copy Job ID'] = 'Копировать Job ID',
    ['Anti-AFK'] = 'Анти-АФК',
    ['Theme'] = 'Тема',
    ['Menu size'] = 'Размер меню',
    ['Stretch to screen'] = 'Растянуть на экран',
    ['Font'] = 'Шрифт',
    ['Text size'] = 'Размер текста',
    ['Menu key'] = 'Клавиша меню',
    ['Language'] = 'Язык',
    ['Unload script'] = 'Выгрузить скрипт',
    ['role colours + labels'] = 'цвет роли и подписи',
    ['2D player boxes'] = '2D-боксы игроков',
    ['R15 bone lines'] = 'линии скелета R15',
    ['bottom-to-player lines'] = 'линии от низа экрана',
    ['show Murderer / Sheriff / Innocent'] = 'показывать роль',
    ['show usernames'] = 'показывать ники',
    ['show studs distance'] = 'показывать дистанцию',
    ['highlight dropped gun'] = 'подсветить лежащий пистолет',
    ['local wall transparency'] = 'локальная прозрачность стен',
    ['always-on-top role highlight'] = 'подсветка роли поверх стен',
    ['fill transparency'] = 'прозрачность заполнения',
    ['soft highlight bloom'] = 'мягкое свечение',
    ['soft depth haze'] = 'мягкая дымка',
    ['cinematic light rays'] = 'кинематографичные лучи',
    ['scene blur'] = 'размытие сцены',
    ['camera depth effect'] = 'эффект глубины камеры',
    ['atmospheric fog'] = 'атмосферный туман',
    ['ghost timing / historical positions'] = 'история позиций-призраков',
    ['character motion trail'] = 'след движения',
    ['trail palette'] = 'палитра следа',
    ['Silent hooks shots; Camera guides view'] = 'Silent меняет выстрел; Camera ведёт камеру',
    ['target selector'] = 'выбор цели',
    ['camera interpolation'] = 'скорость наведения камеры',
    ['return view after camera flick'] = 'вернуть камеру после флика',
    ['velocity lead'] = 'упреждение по скорости',
    ['line-of-sight check'] = 'проверка прямой видимости',
    ['screen-space target circle'] = 'круг цели на экране',
    ['automatic knife stabs'] = 'автоматические удары ножом',
    ['attack distance'] = 'дистанция атаки',
    ['who can be selected'] = 'кого атаковать',
    ['move to dropped gun'] = 'подойти к лежащему пистолету',
    ['fire at selected target'] = 'стрелять по выбранной цели',
    ['only murder target'] = 'стрелять только по мардеру',
    ['physics fling sheriff'] = 'флинг шерифа физикой',
    ['one-shot action'] = 'одноразовое действие',
    ['teleport to GunDrop and back'] = 'телепорт к пистолету и обратно',
    ['assist knife target selection'] = 'помощь в выборе цели ножа',
    ['automatic knife throws'] = 'автоматический бросок ножа',
    ['local offset loop'] = 'локальное смещение',
    ['offset pattern'] = 'режим смещения',
    ['offset distance'] = 'дальность смещения',
    ['offset rate'] = 'частота смещения',
    ['turn toward nearest target'] = 'поворачиваться к ближайшей цели',
    ['smooth motion samples for targeting'] = 'сглаживание движения для наведения',
    ['toggle with N'] = 'переключение клавишей N',
    ['toggle with J'] = 'переключение клавишей J',
    ['reduce incoming velocity'] = 'снижать входящую скорость',
    ['toggle with F'] = 'переключение клавишей F',
    ['toggle with X'] = 'переключение клавишей X',
    ['toggle with B'] = 'переключение клавишей B',
    ['experimental local hide'] = 'экспериментальная локальная невидимость',
    ['use vertical launch'] = 'вертикальный запуск',
    ['movement mode'] = 'режим движения',
    ['movement rate'] = 'скорость перемещения',
    ['reset at detected 40-coin threshold'] = 'респавн при обнаружении лимита в 40 монет',
    ['pause near murderer'] = 'пауза рядом с мардером',
    ['fling nearby players after respawn'] = 'флинг ближайшего игрока после респавна',
    ['best-effort lobby teleport'] = 'телепорт в предполагаемое лобби',
    ['R15 animation bundle'] = 'пак анимаций R15',
    ['animation playback'] = 'скорость проигрывания',
    ['built-in emotes'] = 'встроенные эмоуты',
    ['playback'] = 'скорость проигрывания',
    ['keep emote active'] = 'удерживать эмоут активным',
    ['reapply animation pack'] = 'повторно применить пак',
    ['local avatar change'] = 'локальное изменение аватара',
    ['local head transparency'] = 'локальная прозрачность головы',
    ['local visual toy'] = 'локальная визуальная игрушка',
    ['local walk speed'] = 'локальная скорость ходьбы',
    ['local jump power'] = 'локальная сила прыжка',
    ['touch nearby player physics'] = 'флинг при касании',
    ['click player to fling'] = 'клик по игроку для флинга',
    ['circle selected target'] = 'круг вокруг цели',
    ['orbit selector'] = 'выбор цели орбиты',
    ['random song at round start'] = 'случайная песня в начале раунда',
    ['add any Roblox audio asset ID'] = 'добавить ID аудио Roblox',
    ['apply preset'] = 'применить пресет',
    ['preset brightness'] = 'яркость пресета',
    ['time of day'] = 'время суток',
    ['exposure'] = 'экспозиция',
    ['local transparency'] = 'локальная прозрачность',
    ['disable particle emitters'] = 'выключить частицы',
    ['disable BasePart shadows'] = 'выключить тени',
    ['reduce mesh reflection'] = 'уменьшить отражения MeshPart',
    ['force Plastic material'] = 'принудительный Plastic',
    ['executor setfpscap'] = 'setfpscap executor',
    ['prevent idle kick'] = 'защита от AFK',
    ['interface scale'] = 'масштаб интерфейса',
    ['fit to viewport'] = 'подогнать под экран',
    ['UI font'] = 'шрифт интерфейса',
    ['global offset'] = 'смещение размера текста',
    ['keyboard toggle'] = 'клавиша переключения',
    ['interface language'] = 'язык интерфейса',
    ['remove GUI, loops and effects'] = 'удалить меню, циклы и эффекты',
    ['numeric ID + Enter'] = 'числовой ID + Enter',
    ['apply'] = 'применить',
    ['Blue'] = 'Синий',
    ['Rainbow'] = 'Радуга',
    ['Pink'] = 'Розовый',
    ['White'] = 'Белый',
    ['Silent'] = 'Сайлент',
    ['Camera'] = 'Камера',
    ['Auto role'] = 'Авто-роль',
    ['Closest to cursor'] = 'Ближайший к курсору',
    ['Closest to me'] = 'Ближайший ко мне',
    ['All'] = 'Все',
    ['Sheriff only'] = 'Только шериф',
    ['Tween'] = 'Плавно',
    ['Jitter'] = 'Дёрганье',
    ['Orbit'] = 'Орбита',
    ['Vertical'] = 'Вертикально',
    ['Behind'] = 'Сзади',
    ['Sideways'] = 'Сбоку',
    ['Bubbly'] = 'Bubbly',
    ['Cartoony'] = 'Cartoony',
    ['Ninja'] = 'Ninja',
    ['Pirate'] = 'Pirate',
    ['Robot'] = 'Robot',
    ['Mage'] = 'Mage',
    ['Astronaut'] = 'Astronaut',
    ['Knight'] = 'Knight',
    ['Wave'] = 'Помахать',
    ['Cheer'] = 'Порадоваться',
    ['Laugh'] = 'Смеяться',
    ['Dance'] = 'Танец',
    ['Dance2'] = 'Танец 2',
    ['Dance3'] = 'Танец 3',
    ['Point'] = 'Указать',
    ['Halo'] = 'Аура',
    ['Balloon'] = 'Шарик',
    ['Orb pet'] = 'Орб-питомец',
    ['Gotham'] = 'Gotham',
    ['Ubuntu'] = 'Ubuntu',
    ['Source Sans'] = 'Source Sans',
    ['Montserrat'] = 'Montserrat',
    ['Nunito'] = 'Nunito',
    ['Arial'] = 'Arial',
    ['Frost'] = 'Мороз',
    ['Snow'] = 'Снег',
    ['Sky'] = 'Небо',
    ['Ice'] = 'Лёд',
    ['Русский'] = 'Русский',
    ['English'] = 'English',
    ['N'] = 'N',
    ['J'] = 'J',
    ['F'] = 'F',
    ['X'] = 'X',
    ['B'] = 'B',
    ['V'] = 'V',
    ['GO'] = 'ПУСК',
}

local function tr(s)
    if Hub.state.lang == "Русский" then return RU[s] or s end
    return s
end

Hub.i18n = {}
local function i18nText(obj, raw)
    if not obj then return end
    Hub.i18n[#Hub.i18n + 1] = {o=obj, raw=raw}
    obj.Text = tr(raw)
end

local function refreshLanguage()
    for _, ref in ipairs(Hub.i18n) do
        if ref.o and ref.o.Parent then
            if ref.placeholder then ref.o.PlaceholderText = tr(ref.raw) else ref.o.Text = tr(ref.dynamic and ref.dynamic() or ref.raw) end
        end
    end
    for id,b in pairs(Hub.tabButtons) do
        if b and b.Parent then
            local raw = b:GetAttribute("PulseRawLabel") or ""
            local icon = b:GetAttribute("PulseIcon") or ""
            b.Text = icon .. "  " .. tr(raw)
        end
    end
    title.Text = "PULSE  /  MM2"
    sub.Text = tr("precision hub  •  soft frost edition")
    footer.Text = tr("Menu key  •  all controls persist while injected")
end

local gui = Instance.new("ScreenGui")
gui.Name = "PulseHubMM2"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
gui.DisplayOrder = 500
gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")
Hub.createdGui = gui

espGui = Instance.new("ScreenGui")
espGui.Name = "PulseHubESP"
espGui.ResetOnSpawn = false
espGui.IgnoreGuiInset = true
espGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
espGui.DisplayOrder = 499
espGui.Parent = (gethui and gethui()) or game:GetService("CoreGui")

local shadow = Instance.new("Frame")
shadow.Name = "Shadow"
shadow.AnchorPoint = Vector2.new(0.5,0.5)
shadow.Size = U2(0,970,0,630)
shadow.Position = U2(0.5,4,0.5,4)
shadow.BackgroundColor3 = C3(58,107,137)
shadow.BackgroundTransparency = 0.87
shadow.BorderSizePixel = 0
shadow.Parent = gui
uiCorner(shadow,18)

local root = Instance.new("Frame")
root.Name = "Root"
root.AnchorPoint = Vector2.new(0.5,0.5)
root.Size = U2(0,960,0,620)
root.Position = U2(0.5,0,0.5,0)
root.BackgroundColor3 = C3(244,250,254)
root.BorderSizePixel = 0
root.Parent = gui
uiCorner(root,16)

local uiScale = Instance.new("UIScale")
uiScale.Scale = 1
uiScale.Parent = root
Hub.uiScaleObj = uiScale

local rootStroke = Instance.new("UIStroke")
rootStroke.Color = C3(177,213,235)
rootStroke.Thickness = 1.2
rootStroke.Transparency = 0.12
rootStroke.Parent = root

local top = Instance.new("Frame")
top.Size = U2(1,0,0,66)
top.BackgroundColor3 = C3(233,246,253)
top.BorderSizePixel = 0
top.Parent = root
uiCorner(top,16)

local topMask = Instance.new("Frame")
topMask.Position = U2(0,52,0,0)
topMask.Size = U2(1,0,0,14)
topMask.BackgroundColor3 = C3(233,246,253)
topMask.BorderSizePixel = 0
topMask.Parent = top

local topGradient = Instance.new("UIGradient")
topGradient.Color = ColorSequence.new{
    ColorSequenceKeypoint.new(0, C3(228,244,253)),
    ColorSequenceKeypoint.new(0.55, C3(244,251,255)),
    ColorSequenceKeypoint.new(1, C3(219,238,249)),
}
topGradient.Rotation = 15
topGradient.Parent = top

local accent = Instance.new("Frame")
accent.Position = U2(0,0,1,-3)
accent.Size = U2(1,0,0,3)
accent.BackgroundColor3 = C3(144,210,247)
accent.BorderSizePixel = 0
accent.Parent = top
uiCorner(accent,3)

title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = U2(0,22,0,0)
title.Size = U2(0,380,0,30)
title.Font = Enum.Font.GothamBold
title.TextSize = 21
title.TextColor3 = C3(48,78,104)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = top
i18nText(title,"PULSE  /  MM2")

sub = Instance.new("TextLabel")
sub.BackgroundTransparency = 1
sub.Position = U2(0,24,0,31)
sub.Size = U2(0,500,0,19)
sub.Font = Enum.Font.Gotham
sub.TextSize = 10
sub.TextColor3 = C3(116,153,177)
sub.TextXAlignment = Enum.TextXAlignment.Left
sub.Parent = top
i18nText(sub,"precision hub  •  soft frost edition")

status = Instance.new("TextLabel")
status.BackgroundTransparency = 1
status.AnchorPoint = Vector2.new(1,0)
status.Position = U2(1,-24,0,17)
status.Size = U2(0,180,0,25)
status.Font = Enum.Font.GothamSemibold
status.TextSize = 11
status.TextColor3 = C3(78,143,184)
status.TextXAlignment = Enum.TextXAlignment.Right
status.Parent = top
status.Text = Hub.state.lang=="Русский" and "ГОТОВ  •  0 ms" or "READY  •  0 ms"

local closeBtn = Instance.new("TextButton")
closeBtn.AutoButtonColor = false
closeBtn.Text = "×"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 20
closeBtn.TextColor3 = C3(80,119,144)
closeBtn.Size = U2(0,34,0,34)
closeBtn.Position = U2(1,-49,0,14)
closeBtn.BackgroundColor3 = C3(246,251,255)
closeBtn.BorderSizePixel = 0
closeBtn.Parent = top
uiCorner(closeBtn,10)
local closeStroke = Instance.new("UIStroke")
closeStroke.Color = C3(204,225,238)
closeStroke.Parent = closeBtn
closeBtn.MouseEnter:Connect(function()
    closeBtn.BackgroundColor3 = C3(226,242,252)
    closeStroke.Color = C3(154,207,239)
end)
closeBtn.MouseLeave:Connect(function()
    closeBtn.BackgroundColor3 = C3(246,251,255)
    closeStroke.Color = C3(204,225,238)
end)
closeBtn.MouseButton1Click:Connect(function() root.Visible = false end)

local nav = Instance.new("ScrollingFrame")
nav.Name = "Nav"
nav.Position = U2(0,14,0,77)
nav.Size = U2(0,196,1,-96)
nav.BackgroundColor3 = C3(236,246,251)
nav.BorderSizePixel = 0
nav.CanvasSize = U2(0,0,0,0)
nav.AutomaticCanvasSize = Enum.AutomaticSize.Y
nav.ScrollBarThickness = 4
nav.ScrollBarImageColor3 = C3(172,210,233)
nav.Parent = root
uiCorner(nav,12)
local navStroke = Instance.new("UIStroke")
navStroke.Color = C3(205,225,238)
navStroke.Transparency = 0.25
navStroke.Parent = nav
local navPad = Instance.new("UIPadding")
navPad.PaddingTop = UDim.new(0,8)
navPad.PaddingBottom = UDim.new(0,8)
navPad.PaddingLeft = UDim.new(0,8)
navPad.PaddingRight = UDim.new(0,8)
navPad.Parent = nav
local navList = Instance.new("UIListLayout")
navList.Padding = UDim.new(0,5)
navList.SortOrder = Enum.SortOrder.LayoutOrder
navList.Parent = nav

local page = Instance.new("Frame")
page.Position = U2(0,220,0,77)
page.Size = U2(1,-236,1,-110)
page.BackgroundColor3 = C3(249,253,255)
page.BorderSizePixel = 0
page.Parent = root
uiCorner(page,12)
local pageStroke = Instance.new("UIStroke")
pageStroke.Color = C3(215,232,242)
pageStroke.Transparency = 0.2
pageStroke.Parent = page

footer = Instance.new("TextLabel")
footer.BackgroundTransparency = 1
footer.AnchorPoint = Vector2.new(1,1)
footer.Position = U2(1,-20,1,-13)
footer.Size = U2(0,380,0,18)
footer.Font = Enum.Font.Gotham
footer.TextSize = 9
footer.TextColor3 = C3(132,164,184)
footer.TextXAlignment = Enum.TextXAlignment.Right
footer.Parent = root
i18nText(footer,"Menu key  •  all controls persist while injected")

local FontMap = {Gotham=Enum.Font.Gotham, Ubuntu=Enum.Font.Ubuntu, ["Source Sans"]=Enum.Font.SourceSans, Montserrat=Enum.Font.Montserrat, Nunito=Enum.Font.Nunito, Arial=Enum.Font.Arial}
local ThemeMap = {
    Frost={root=C3(244,250,254), top=C3(233,246,253), page=C3(249,253,255), nav=C3(236,246,251), accent=C3(144,210,247)},
    Snow={root=C3(249,251,253), top=C3(242,247,250), page=C3(255,255,255), nav=C3(243,247,250), accent=C3(172,216,241)},
    Sky={root=C3(239,248,255), top=C3(226,242,252), page=C3(247,252,255), nav=C3(230,243,250), accent=C3(145,208,244)},
    Ice={root=C3(238,245,250), top=C3(222,238,248), page=C3(245,250,254), nav=C3(227,239,246), accent=C3(137,200,239)},
}

local function applyUISettings()
    local tm = ThemeMap[Hub.state.theme] or ThemeMap.Frost
    root.BackgroundColor3 = tm.root
    top.BackgroundColor3 = tm.top
    topMask.BackgroundColor3 = tm.top
    nav.BackgroundColor3 = tm.nav
    page.BackgroundColor3 = tm.page
    accent.BackgroundColor3 = tm.accent
    rootStroke.Color = C3(177,213,235)

    local font = FontMap[Hub.state.font] or Enum.Font.Gotham
    for _,o in ipairs(gui:GetDescendants()) do
        if o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox") then
            local base = o:GetAttribute("PulseBaseTextSize")
            if not base then
                base = o.TextSize
                o:SetAttribute("PulseBaseTextSize", base)
            end
            o.Font = font
            o.TextSize = math.max(7, base + Hub.state.textSize)
        end
    end

    local cam = workspace.CurrentCamera
    if cam then
        local vs = cam.ViewportSize
        local fit = math.min((vs.X-28)/960, (vs.Y-28)/620)
        fit = math.max(0.55, fit)
        local userScale = math.clamp(Hub.state.uiScale/100,0.7,1.4)
        if Hub.state.stretch then
            uiScale.Scale = math.max(0.55, math.min(1.1, fit))
            root.Size = U2(0,960,0,620)
        else
            uiScale.Scale = math.min(userScale, fit)
            root.Size = U2(0,960,0,620)
        end
    end
    shadow.Size = U2(0,970,0,630)
    shadow.Position = U2(0.5,4,0.5,4)
end

local function section(parent, raw)
    local l=Instance.new("TextLabel")
    l.BackgroundTransparency=1
    l.Size=U2(1,0,0,24)
    l.TextXAlignment=Enum.TextXAlignment.Left
    l.Font=Enum.Font.GothamBold
    l.TextSize=10
    l.TextColor3=C3(85,128,158)
    l.Parent=parent
    i18nText(l,raw)
    return l
end

local function card(parent, rawLabel, rawDesc)
    local f=Instance.new("Frame")
    f.Size=U2(1,-18,0,54)
    f.BackgroundColor3=C3(255,255,255)
    f.BackgroundTransparency=0.08
    f.BorderSizePixel=0
    f.Parent=parent
    uiCorner(f,11)
    local st=Instance.new("UIStroke")
    st.Color=C3(220,235,244)
    st.Transparency=0.15
    st.Thickness=1
    st.Parent=f

    local glow=Instance.new("Frame")
    glow.Name="AccentGlow"
    glow.BackgroundColor3=C3(185,226,248)
    glow.BackgroundTransparency=0.9
    glow.BorderSizePixel=0
    glow.Size=U2(0,3,1,-12)
    glow.Position=U2(0,5,0,6)
    glow.Parent=f
    uiCorner(glow,4)

    local l=Instance.new("TextLabel")
    l.BackgroundTransparency=1
    l.Position=U2(0,14,0,0)
    l.Size=U2(1,-205,0,19)
    l.Font=Enum.Font.GothamSemibold
    l.TextSize=11
    l.TextColor3=C3(58,90,112)
    l.TextXAlignment=Enum.TextXAlignment.Left
    l.Parent=f
    i18nText(l,rawLabel)

    local d=Instance.new("TextLabel")
    d.BackgroundTransparency=1
    d.Position=U2(0,14,0,21)
    d.Size=U2(1,-205,0,18)
    d.Font=Enum.Font.Gotham
    d.TextSize=8.5
    d.TextColor3=C3(142,169,187)
    d.TextXAlignment=Enum.TextXAlignment.Left
    d.Parent=f
    i18nText(d,rawDesc or "")
    return f,l,d
end

local function toggle(parent,labelText,key,desc,callback)
    local f=card(parent,labelText,desc)
    local b=Instance.new("TextButton")
    b.AutoButtonColor=false
    b.Text=""
    b.Size=U2(0,46,0,25)
    b.Position=U2(1,-60,0.5,-12.5)
    b.BackgroundColor3=C3(224,236,244)
    b.BorderSizePixel=0
    b.Parent=f
    uiCorner(b,13)
    local s=Instance.new("UIStroke"); s.Color=C3(201,219,232); s.Thickness=1; s.Parent=b
    local dot=Instance.new("Frame")
    dot.Size=U2(0,19,0,19)
    dot.Position=U2(0,3,0,3)
    dot.BackgroundColor3=C3(255,255,255)
    dot.BorderSizePixel=0
    dot.Parent=b
    uiCorner(dot,10)
    local ds=Instance.new("UIStroke"); ds.Color=C3(198,216,229); ds.Parent=dot
    local glow=Instance.new("UIStroke"); glow.Color=C3(150,217,248); glow.Thickness=3; glow.Transparency=1; glow.Parent=b

    local function render(v)
        b.BackgroundColor3=v and C3(161,218,248) or C3(224,236,244)
        s.Color=v and C3(128,197,235) or C3(201,219,232)
        dot.Position=v and U2(1,-22,0,3) or U2(0,3,0,3)
        dot.BackgroundColor3=C3(255,255,255)
        glow.Transparency=v and 0.65 or 1
    end
    local function set(v,silent)
        Hub.state[key]=v; render(v)
        if not silent and callback then callback(v) end
        if not silent then saveConfig() end
    end
    b.MouseButton1Click:Connect(function() set(not Hub.state[key]) end)
    Hub.controls[key]={set=set,render=render}
    render(Hub.state[key])
    return f
end

local function slider(parent,labelText,key,min,max,step,desc,suffix,callback)
    local f=card(parent,labelText,desc)
    local value=Instance.new("TextLabel")
    value.BackgroundTransparency=1
    value.Position=U2(1,-170,0,12)
    value.Size=U2(0,72,0,18)
    value.TextXAlignment=Enum.TextXAlignment.Right
    value.Font=Enum.Font.GothamSemibold
    value.TextSize=10
    value.TextColor3=C3(83,133,164)
    value.Parent=f

    local bar=Instance.new("Frame")
    bar.Position=U2(1,-91,0,19)
    bar.Size=U2(0,70,0,9)
    bar.BackgroundColor3=C3(224,237,245)
    bar.BorderSizePixel=0
    bar.Parent=f
    uiCorner(bar,6)
    local fill=Instance.new("Frame")
    fill.Size=U2(0,0,1,0)
    fill.BackgroundColor3=C3(153,211,244)
    fill.BorderSizePixel=0
    fill.Parent=bar
    uiCorner(fill,6)
    local knob=Instance.new("Frame")
    knob.Size=U2(0,14,0,14)
    knob.AnchorPoint=Vector2.new(0.5,0.5)
    knob.Position=U2(0,0,0.5,0)
    knob.BackgroundColor3=C3(255,255,255)
    knob.BorderSizePixel=0
    knob.Parent=bar
    uiCorner(knob,8)
    local ks=Instance.new("UIStroke"); ks.Color=C3(170,207,226); ks.Thickness=1; ks.Parent=knob
    local kb=Instance.new("UIStroke"); kb.Color=C3(142,208,244); kb.Thickness=2.5; kb.Transparency=1; kb.Parent=knob

    local function snap(v)
        return math.clamp(min + math.floor(((v-min)/step)+0.5)*step,min,max)
    end
    local function render(v)
        Hub.state[key]=snap(v)
        local p=(Hub.state[key]-min)/(max-min)
        fill.Size=U2(p,0,1,0)
        knob.Position=U2(p,0,0.5,0)
        value.Text=tostring(Hub.state[key])..(suffix or "")
    end
    local dragging=false
    local function update(x)
        local p=math.clamp((x-bar.AbsolutePosition.X)/math.max(1,bar.AbsoluteSize.X),0,1)
        render(min+p*(max-min))
        if callback then callback(Hub.state[key]) end
        saveConfig()
    end
    bar.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 then
            dragging=true; kb.Transparency=0.55; update(i.Position.X)
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if dragging and i.UserInputType==Enum.UserInputType.MouseMovement then update(i.Position.X) end
    end)
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false; kb.Transparency=1 end
    end)
    Hub.controls[key]={set=function(v,silent) render(v); if not silent and callback then callback(Hub.state[key]) end end,render=render}
    render(Hub.state[key])
    return f
end

local function input(parent,labelText,hint,desc,callback)
    local f=card(parent,labelText,desc)
    local box=Instance.new("TextBox")
    box.ClearTextOnFocus=false
    box.PlaceholderText=tr(hint or "enter")
    box.Text=""
    box.Font=Enum.Font.Gotham
    box.TextSize=9
    box.TextColor3=C3(65,99,122)
    box.PlaceholderColor3=C3(157,181,197)
    box.BackgroundColor3=C3(240,248,253)
    box.BorderSizePixel=0
    box.Size=U2(0,160,0,30)
    box.Position=U2(1,-172,0,12)
    box.Parent=f
    uiCorner(box,9)
    local st=Instance.new("UIStroke"); st.Color=C3(206,226,238); st.Parent=box
    Hub.i18n[#Hub.i18n+1]={o=box,raw=hint or "enter",placeholder=true}
    box.FocusLost:Connect(function(enter) if enter and callback then callback(box.Text) end end)
    return f,box
end

local function dropdown(parent,labelText,key,items,desc,callback)
    local f=card(parent,labelText,desc)
    local b=Instance.new("TextButton")
    b.AutoButtonColor=false
    b.Text=""
    b.Size=U2(0,155,0,30)
    b.Position=U2(1,-166,0,12)
    b.BackgroundColor3=C3(240,248,253)
    b.BorderSizePixel=0
    b.Parent=f
    uiCorner(b,9)
    local bs=Instance.new("UIStroke"); bs.Color=C3(204,225,238); bs.Parent=b
    local t=Instance.new("TextLabel")
    t.BackgroundTransparency=1
    t.Size=U2(1,-22,1,0)
    t.Position=U2(0,10,0,0)
    t.TextXAlignment=Enum.TextXAlignment.Right
    t.Font=Enum.Font.GothamSemibold
    t.TextSize=9
    t.TextColor3=C3(72,111,137)
    t.Parent=b

    local menu=Instance.new("Frame")
    menu.Visible=false
    menu.ZIndex=300
    menu.Size=U2(0,155,0,math.min(#items*27,190))
    menu.Position=U2(1,-166,0,45)
    menu.BackgroundColor3=C3(251,254,255)
    menu.BorderSizePixel=0
    menu.Parent=f
    uiCorner(menu,9)
    local ms=Instance.new("UIStroke"); ms.Color=C3(202,224,238); ms.Parent=menu
    local ml=Instance.new("UIListLayout"); ml.SortOrder=Enum.SortOrder.LayoutOrder; ml.Parent=menu

    local opts={}
    local function set(v)
        Hub.state[key]=v
        t.Text=tr(v)
        saveConfig()
        menu.Visible=false
        if callback then callback(v) end
    end
    for _,item in ipairs(items) do
        local q=Instance.new("TextButton")
        q.AutoButtonColor=false
        q.Text=tr(item)
        q.Font=Enum.Font.Gotham
        q.TextSize=9
        q.TextColor3=C3(69,102,125)
        q.BackgroundTransparency=1
        q.Size=U2(1,0,0,27)
        q.ZIndex=301
        q.Parent=menu
        uiCorner(q,7)
        q.MouseEnter:Connect(function() q.BackgroundTransparency=0; q.BackgroundColor3=C3(233,246,253) end)
        q.MouseLeave:Connect(function() q.BackgroundTransparency=1 end)
        q.MouseButton1Click:Connect(function() set(item) end)
        Hub.i18n[#Hub.i18n+1]={o=q,raw=item}
        opts[#opts+1]=q
    end
    b.MouseEnter:Connect(function() b.BackgroundColor3=C3(232,246,253); bs.Color=C3(153,210,242) end)
    b.MouseLeave:Connect(function() b.BackgroundColor3=C3(240,248,253); bs.Color=C3(204,225,238) end)
    b.MouseButton1Click:Connect(function() menu.Visible=not menu.Visible end)
    t.Text=tr(Hub.state[key])
    Hub.i18n[#Hub.i18n+1]={o=t,raw=Hub.state[key],dynamic=function() return Hub.state[key] end}
    Hub.controls[key]={set=set,render=function(v)t.Text=tr(v)end}
    return f
end

local function button(parent,labelText,callback,desc)
    local f=card(parent,labelText,desc)
    local b=Instance.new("TextButton")
    b.AutoButtonColor=false
    b.Text=tr("GO")
    b.Font=Enum.Font.GothamBold
    b.TextSize=9
    b.TextColor3=C3(69,121,156)
    b.Size=U2(0,58,0,26)
    b.Position=U2(1,-69,0.5,-13)
    b.BackgroundColor3=C3(225,241,250)
    b.BorderSizePixel=0
    b.Parent=f
    uiCorner(b,9)
    local st=Instance.new("UIStroke"); st.Color=C3(194,221,237); st.Parent=b
    b.MouseEnter:Connect(function() b.BackgroundColor3=C3(208,235,249); st.Color=C3(149,208,241) end)
    b.MouseLeave:Connect(function() b.BackgroundColor3=C3(225,241,250); st.Color=C3(194,221,237) end)
    b.MouseButton1Click:Connect(function() if callback then callback() end end)
    Hub.i18n[#Hub.i18n+1]={o=b,raw="GO",dynamic=function() return "GO" end,button=true}
    return f
end

local function newTab(id,labelText,icon)
    local b=Instance.new("TextButton")
    b.AutoButtonColor=false
    b.Text=icon.."  "..tr(labelText)
    b.Font=Enum.Font.GothamSemibold
    b.TextSize=10
    b.TextColor3=C3(87,116,136)
    b.TextXAlignment=Enum.TextXAlignment.Left
    b.Size=U2(1,-8,0,35)
    b.BackgroundColor3=C3(236,246,251)
    b.BorderSizePixel=0
    b.Parent=nav
    uiCorner(b,9)
    b:SetAttribute("PulseRawLabel",labelText)
    b:SetAttribute("PulseIcon",icon)
    local s=Instance.new("UIStroke"); s.Color=C3(218,231,239); s.Transparency=0.4; s.Parent=b
    Hub.tabButtons[id]=b

    local p=Instance.new("ScrollingFrame")
    p.Name=id
    p.Visible=false
    p.Size=U2(1,-18,1,-16)
    p.Position=U2(0,8,0,8)
    p.BackgroundTransparency=1
    p.BorderSizePixel=0
    p.ScrollBarThickness=4
    p.ScrollBarImageColor3=C3(181,214,236)
    p.AutomaticCanvasSize=Enum.AutomaticSize.Y
    p.CanvasSize=U2(0,0,0,0)
    p.Parent=page
    local pad=Instance.new("UIPadding")
    pad.PaddingLeft=UDim.new(0,5); pad.PaddingRight=UDim.new(0,5); pad.PaddingTop=UDim.new(0,2); pad.PaddingBottom=UDim.new(0,10)
    pad.Parent=p
    local l=Instance.new("UIListLayout"); l.Padding=UDim.new(0,7); l.SortOrder=Enum.SortOrder.LayoutOrder; l.Parent=p
    Hub.tabs[id]=p
    b.MouseEnter:Connect(function() if Hub.selectedTab~=id then b.BackgroundColor3=C3(228,241,249) end end)
    b.MouseLeave:Connect(function() if Hub.selectedTab~=id then b.BackgroundColor3=C3(236,246,251) end end)
    b.MouseButton1Click:Connect(function() Hub.showTab(id) end)
    return p
end

function Hub.showTab(id)
    Hub.selectedTab=id
    for k,p in pairs(Hub.tabs) do
        p.Visible=(k==id)
        local b=Hub.tabButtons[k]
        if b then
            if k==id then
                b.BackgroundColor3=C3(214,237,249)
                b.TextColor3=C3(50,103,136)
                local s=b:FindFirstChildOfClass("UIStroke"); if s then s.Color=C3(145,210,241); s.Transparency=0 end
            else
                b.BackgroundColor3=C3(236,246,251)
                b.TextColor3=C3(87,116,136)
                local s=b:FindFirstChildOfClass("UIStroke"); if s then s.Color=C3(218,231,239); s.Transparency=0.4 end
            end
        end
    end
end

section(nav,"MAIN")
local tCombat=newTab("combat","Combat","⚔")
section(tCombat,"AIM")
toggle(tCombat,"Enable aim","aimOn","master aimbot switch")
dropdown(tCombat,"Aim version","aimVersion",{"Silent","Camera"},"Silent changes outgoing shot target; Camera guides view")
dropdown(tCombat,"Aim type","aimType",{"Auto role","Murderer","Sheriff","Closest to cursor","Closest to me"},"target selector")
slider(tCombat,"Flick speed","aimSpeed",1,100,1,"camera interpolation","%")
toggle(tCombat,"Return flick","aimReturn","restore camera after flick")
slider(tCombat,"Prediction","predict",0,300,5,"velocity lead"," ms")
toggle(tCombat,"Wall check","aimWall","line-of-sight check")
toggle(tCombat,"Show FOV circle","fovShow","screen-space target circle")
slider(tCombat,"FOV radius","fovRadius",20,600,5,"target radius"," px")
section(tCombat,"WEAPONS")
toggle(tCombat,"Auto pick up gun","autoPickup","instant multi-method GunDrop pickup")
toggle(tCombat,"Auto shoot","autoShoot","fire at selected target")
toggle(tCombat,"Auto kill murderer","autoKill","fire at murderer")
toggle(tCombat,"Auto fling sheriff","autoFlingSheriff","try physics fling on sheriff")
toggle(tCombat,"Kill aura","killAura","automatic knife attacks")
slider(tCombat,"Kill radius","killRadius",5,60,1,"attack distance"," st")
dropdown(tCombat,"Kill targets","killMode",{"All","Sheriff only"},"who can be selected")
button(tCombat,"Get gun now",pickupGun,"instant pickup action")
button(tCombat,"Shoot murderer",function() local p=nearestTarget(function(x)return roleOf(x)=="Murderer"end); if p then shootAt(p) end end,"one-shot action")
section(tCombat,"KNIFE")
toggle(tCombat,"Knife aimbot","knifeAim","assist knife target selection")
toggle(tCombat,"Knife wall check","knifeWall","line-of-sight check")
slider(tCombat,"Knife lead","knifeLead",0,300,5,"knife velocity lead"," ms")
toggle(tCombat,"Auto throw","knifeAuto","automatic knife throws")
button(tCombat,"Throw at target",function() local p=select(1,playersRoleTarget()); if p then knifeThrowAt(p) end end)
section(tCombat,"FAKE POSITION")
toggle(tCombat,"Fake position","desync","local offset loop")
dropdown(tCombat,"Desync mode","desyncMode",{"Jitter","Orbit","Vertical","Behind","Sideways"},"offset pattern")
slider(tCombat,"Desync radius","desyncRadius",1,30,1,"offset distance"," st")
slider(tCombat,"Desync speed","desyncSpeed",1,100,1,"offset rate")
toggle(tCombat,"Face threat","faceThreat","turn toward nearest target")
toggle(tCombat,"Resolver","resolver","smooth motion samples for targeting")

local tPlayer=newTab("player","Player","⇢")
section(tPlayer,"MOVEMENT")
toggle(tPlayer,"Noclip","noclip","toggle with N",function(v) if v then applyNoclip() else resetNoclip() end end)
toggle(tPlayer,"Infinite jump","infJump","toggle with J")
toggle(tPlayer,"Anti-fling","antiFling","recover from violent incoming physics")
toggle(tPlayer,"Fly","fly","toggle with F",function(v) if v then startFly() else stopFly() end end)
toggle(tPlayer,"Spin","spin","toggle with X")
toggle(tPlayer,"Bunny hop","bhop","toggle with B")
toggle(tPlayer,"Invisible","invis","local-only transparency",function(v) setLocalInvisible(v) end)
button(tPlayer,"Bomb jump",bombJump,"vertical launch")
slider(tPlayer,"Fly speed","flySpeed",10,200,1,"","",function() if Hub.state.fly then startFly() end end)
slider(tPlayer,"Spin speed","spinSpeed",1,60,1,"","")
slider(tPlayer,"Bomb power","bombPower",20,250,5,"launch power","")
section(tPlayer,"AUTOFARM")
toggle(tPlayer,"Autofarm coins","farm","collect Coin_Server parts")
dropdown(tPlayer,"Farm version","farmVersion",{"Tween","Teleport"},"movement mode")
slider(tPlayer,"Farm speed","farmSpeed",10,150,1,"movement rate","")
toggle(tPlayer,"Reset when bag is full","farmReset","reset at detected bag threshold")
toggle(tPlayer,"Avoid murderer","farmAvoid","pause near murderer")
toggle(tPlayer,"Auto fling after respawn","farmFling","try to fling a nearby player")
section(tPlayer,"TELEPORT")
button(tPlayer,"Lobby",function() local _,_,r=aliveCharacter(LocalPlayer); if r then r.CFrame=CFrame.new(0,10,0) end end,"best-effort lobby teleport")
button(tPlayer,"Murderer",function() local p=nearestTarget(function(x)return roleOf(x)=="Murderer"end); local _,_,r=aliveCharacter(p); local _,_,me=aliveCharacter(LocalPlayer); if r and me then me.CFrame=r.CFrame+V3(3,0,0) end end)
button(tPlayer,"Sheriff",function() local p=nearestTarget(function(x)return roleOf(x)=="Sheriff"end); local _,_,r=aliveCharacter(p); local _,_,me=aliveCharacter(LocalPlayer); if r and me then me.CFrame=r.CFrame+V3(3,0,0) end end)

local tVisual=newTab("visual","Visuals","✦")
section(tVisual,"ESP")
toggle(tVisual,"ESP","esp","master ESP switch")
toggle(tVisual,"Boxes","espBox","2D player boxes")
toggle(tVisual,"Skeleton","espSkel","R15 bone lines")
toggle(tVisual,"Tracers","espTracer","bottom-to-player lines")
toggle(tVisual,"Role","lblRole","show role")
toggle(tVisual,"Nickname","lblName","show username")
toggle(tVisual,"Distance","lblDist","show distance")
toggle(tVisual,"Gun ESP","gunEsp","highlight dropped gun")
toggle(tVisual,"X-Ray","xray","local wall transparency",function(v)setXray(v)end)
toggle(tVisual,"Chams","chams","always-on-top role highlight",function(v) for _,p in ipairs(Players:GetPlayers()) do if p~=LocalPlayer then applyChams(p) end end end)
slider(tVisual,"Chams transparency","chamsTrans",0,100,1,"fill transparency","%",function() for _,p in ipairs(Players:GetPlayers()) do if p~=LocalPlayer then applyChams(p) end end end)
section(tVisual,"POST FX")
toggle(tVisual,"Bloom","bloom","soft highlight bloom",applyPostFX)
slider(tVisual,"Bloom intensity","bloomInt",0,3,0.1,"","",function() applyPostFX() end)
slider(tVisual,"Bloom size","bloomSize",0,56,1,"","",function() applyPostFX() end)
slider(tVisual,"Bloom threshold","bloomThr",0,2,0.05,"","",function() applyPostFX() end)
toggle(tVisual,"Atmosphere","atmo","soft depth haze",applyPostFX)
slider(tVisual,"Density","atmoDensity",0,100,1,"","%",function() applyPostFX() end)
slider(tVisual,"Haze","atmoHaze",0,10,0.1,"","",function() applyPostFX() end)
toggle(tVisual,"Sun rays","rays","cinematic light rays",applyPostFX)
slider(tVisual,"Ray intensity","raysInt",0,1,0.05,"","",function() applyPostFX() end)
slider(tVisual,"Ray spread","raysSpread",0,1,0.05,"","",function() applyPostFX() end)
toggle(tVisual,"Blur","blur","scene blur",applyPostFX)
slider(tVisual,"Blur size","blurSize",0,56,1,"","",function() applyPostFX() end)
toggle(tVisual,"Depth of field","dof","camera depth effect",applyPostFX)
slider(tVisual,"Far blur","dofFar",0,100,1,"","%",function() applyPostFX() end)
slider(tVisual,"Focus distance","dofFocus",0,200,1,"","",function() applyPostFX() end)
slider(tVisual,"In-focus radius","dofRadius",0,100,1,"","%",function() applyPostFX() end)
toggle(tVisual,"Fog","fog","atmospheric fog",applyPostFX)
slider(tVisual,"Fog distance","fogEnd",50,5000,10,""," st",function() applyPostFX() end)
toggle(tVisual,"Backtrack","backtrack","historical position overlay")
slider(tVisual,"Backtrack time","backMs",50,500,10,""," ms")
toggle(tVisual,"Trail","trail","character motion trail",function() applyTrail() end)
dropdown(tVisual,"Trail colour","trailColor",{"Blue","Rainbow","Pink","White"},"trail palette",function() applyTrail() end)
slider(tVisual,"Trail length","trailLife",0.2,3,0.1,""," s",function() applyTrail() end)

local tSocial=newTab("social","Animations & Troll","◒")
section(tSocial,"ANIMATIONS")
dropdown(tSocial,"Pack","packSel",{"Bubbly","Cartoony","Ninja","Pirate","Robot","Mage","Astronaut","Knight"},"R15 animation bundle",function(v)setAnimations(v)end)
slider(tSocial,"Pack speed","packSpeed",0.2,3,0.1,"animation playback","x")
dropdown(tSocial,"Emote","emoteSel",{"Wave","Cheer","Laugh","Dance","Dance2","Dance3","Point"},"built-in emotes")
slider(tSocial,"Emote speed","emoteSpeed",0.2,3,0.1,"playback","x",animationToSpeed)
toggle(tSocial,"Hold mode","emoteHold","keep emote active")
toggle(tSocial,"Auto-load after respawn","animAuto","reapply animation pack")
button(tSocial,"Play emote",function() playEmote(Hub.state.emoteSel) end)
button(tSocial,"Stop emote",function() local _,h=aliveCharacter(LocalPlayer); if h then for _,tr in ipairs(h:GetPlayingAnimationTracks()) do pcall(function() tr:Stop() end) end end end)
section(tSocial,"TROLL")
toggle(tSocial,"Fake Korblox","korblox","local avatar change",setKorblox)
toggle(tSocial,"Fake headless","headless","local head transparency",setHeadless)
dropdown(tSocial,"Toy","toy",{"Halo","Balloon","Orb pet"},"local visual toy",function(v) if Hub.state.toyOn then makeToy(v) end end)
toggle(tSocial,"Equip toy","toyOn","local visual toy",function(v) if v then makeToy(Hub.state.toy) else clearToy() end end)
button(tSocial,"Random emote",function() local es={"Wave","Cheer","Laugh","Dance","Dance2","Dance3","Point"}; playEmote(es[math.random(1,#es)]) end)
toggle(tSocial,"Custom speed","speedOn","local walk speed",function() setSpeed() end)
slider(tSocial,"Walk speed","walkSpeed",16,200,1,"","",function() setSpeed() end)
toggle(tSocial,"Custom jump","jumpOn","local jump power",function() setJump() end)
slider(tSocial,"Jump power","jumpPower",50,300,1,"","",function() setJump() end)
toggle(tSocial,"Touch fling","touchFling","touch nearby player physics")
toggle(tSocial,"Click fling","clickFling","click player to fling")
toggle(tSocial,"Orbit player","orbit","circle selected target")
dropdown(tSocial,"Orbit target","orbitTarget",{"Murderer","Sheriff","Nearest"},"orbit selector")
slider(tSocial,"Orbit radius","orbitRadius",3,30,1,""," st")
slider(tSocial,"Orbit speed","orbitSpeed",1,20,1,"","")

local tWorld=newTab("world","World","☼")
section(tWorld,"ROUND MUSIC")
toggle(tWorld,"Auto-play on round start","music","random song at round start",function(v) if not v then musicStop() elseif roundActive() then musicPlayRandom() end end)
slider(tWorld,"Start delay","musicDelay",0,30,1,""," s")
slider(tWorld,"Volume","musicVol",0,100,1,"","%",function(v) if Hub.musicSound then Hub.musicSound.Volume=v/100 end end)
input(tWorld,"Audio ID","numeric ID + Enter","add any Roblox audio asset ID",function(v) local id=v:match("%d+"); if id then Hub.state.songs[#Hub.state.songs+1]=id; saveConfig(); notify("Audio ID added: "..id) end end)
button(tWorld,"Play random now",musicPlayRandom)
button(tWorld,"Stop",musicStop)
button(tWorld,"Clear list",function() Hub.state.songs={}; saveConfig(); musicStop() end)
section(tWorld,"LIGHTING PRESETS")
local presets={{"night","Night"},{"realism","Realism"},{"future","Future"},{"studio","Studio"},{"desert","Desert"},{"clean","Clean atmosphere"}}
for _,pr in ipairs(presets) do
    button(tWorld,pr[2],function() setPreset(pr[1]); notify(pr[2].." preset applied") end,"apply preset")
    slider(tWorld,pr[2].." brightness","preset_"..pr[1].."_brightness",0.2,4,0.1,"preset brightness","",function() if Hub.selectedTab=="world" then setPreset(pr[1]) end end)
    slider(tWorld,pr[2].." clock","preset_"..pr[1].."_clock",0,24,0.5,"time of day"," h",function() if Hub.selectedTab=="world" then setPreset(pr[1]) end end)
    slider(tWorld,pr[2].." exposure","preset_"..pr[1].."_exposure",-2,2,0.05,"exposure","",function() if Hub.selectedTab=="world" then setPreset(pr[1]) end end)
end

local tSystem=newTab("system","System","◫")
section(tSystem,"OPTIMIZATION")
toggle(tSystem,"Remove textures","optTex","local texture removal",applyOptimizations)
toggle(tSystem,"Remove particles","optPart","disable particle emitters",applyOptimizations)
toggle(tSystem,"Remove shadows","optShadow","disable BasePart shadows",applyOptimizations)
toggle(tSystem,"Remove reflections","optRefl","reduce mesh reflection",applyOptimizations)
toggle(tSystem,"Low quality mode","optLow","force Plastic material",applyOptimizations)
toggle(tSystem,"FPS unlock","fpsUnlock","executor setfpscap",function() fpsApply() end)
slider(tSystem,"FPS cap","fpsCap",30,9999,10,"target cap"," FPS",function() fpsApply() end)
section(tSystem,"SERVER")
button(tSystem,"Rejoin",function() TeleportService:Teleport(game.PlaceId,LocalPlayer) end)
button(tSystem,"Server hop",function() serverHop(false) end)
button(tSystem,"Small server",function() serverHop(true) end)
button(tSystem,"Copy Job ID",function() if type(setclipboard)=="function" then pcall(setclipboard,game.JobId) end; notify(game.JobId) end)
toggle(tSystem,"Anti-AFK","antiAfk","prevent idle kick",function(v) setAntiAfk(v) end)

local tSet=newTab("set","Settings","⚙")
section(tSet,"INTERFACE")
dropdown(tSet,"Theme","theme",{"Frost","Snow","Sky","Ice"},"interface theme",function() applyUISettings() end)
slider(tSet,"Menu size","uiScale",70,140,5,"interface scale","%",function() applyUISettings() end)
toggle(tSet,"Stretch to screen","stretch","fit to viewport",function() applyUISettings() end)
dropdown(tSet,"Font","font",{"Gotham","Ubuntu","Source Sans","Montserrat","Nunito","Arial"},"UI font",function() applyUISettings() end)
slider(tSet,"Text size","textSize",-3,6,1,"global offset", "",function() applyUISettings() end)
dropdown(tSet,"Menu key","menuKeyName",{"RightShift","Insert","Home","End","Delete"},"keyboard toggle",function(v) Hub.state.menuKey=({RightShift=K.RightShift,Insert=K.Insert,Home=K.Home,End=K.End,Delete=K.Delete})[v] or K.RightShift; saveConfig() end)
dropdown(tSet,"Language","lang",{"Русский","English"},"interface language",function(v) refreshLanguage(); applyUISettings(); saveConfig() end)
section(tSet,"CONFIG")
button(tSet,"Save config now",saveConfig,"automatic background config is also enabled")
button(tSet,"Unload script",function() Hub.Unload() end,"remove GUI, loops and effects")

Hub.showTab("combat")
applyUISettings()
refreshLanguage()

-- input / keybinds -----------------------------------------------------------
pushConn(UIS.InputBegan:Connect(function(i,gp)
    if i.KeyCode == Hub.state.menuKey then
        root.Visible = not root.Visible
        if not root.Visible then
            for _,p in pairs(Hub.tabs) do
                for _,d in ipairs(p:GetDescendants()) do
                    if d:IsA("Frame") and d.ZIndex >= 300 then d.Visible=false end
                end
            end
        end
        return
    end
    if gp then return end
    if i.UserInputType == Enum.UserInputType.MouseButton2 then Hub.rightDown=true; Hub.aimReturnCF=Camera.CFrame end
    if i.KeyCode==K.N then if Hub.controls.noclip then Hub.controls.noclip.set(not Hub.state.noclip) end end
    if i.KeyCode==K.J then if Hub.controls.infJump then Hub.controls.infJump.set(not Hub.state.infJump) end end
    if i.KeyCode==K.F then if Hub.controls.fly then Hub.controls.fly.set(not Hub.state.fly) end end
    if i.KeyCode==K.X then if Hub.controls.spin then Hub.controls.spin.set(not Hub.state.spin) end end
    if i.KeyCode==K.B then if Hub.controls.bhop then Hub.controls.bhop.set(not Hub.state.bhop) end end
    if i.KeyCode==K.V then bombJump() end
end))
pushConn(UIS.InputEnded:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton2 then
        Hub.rightDown=false
        if Hub.state.aimReturn and Hub.state.aimVersion=="Camera" and Hub.aimReturnCF then safe(function() TweenService:Create(Camera,TweenInfo.new(0.14,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{CFrame=Hub.aimReturnCF}):Play() end) end
    end
end))
pushConn(UIS.JumpRequest:Connect(function() if Hub.state.infJump then local _,h=aliveCharacter(LocalPlayer); if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end end end))

-- drag
pushConn(top.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then Hub.drag={start=i.Position, pos=root.Position} end end))
pushConn(UIS.InputChanged:Connect(function(i) if Hub.drag and i.UserInputType==Enum.UserInputType.MouseMovement then local delta=i.Position-Hub.drag.start; root.Position=UDim2.new(Hub.drag.pos.X.Scale,Hub.drag.pos.X.Offset+delta.X,Hub.drag.pos.Y.Scale,Hub.drag.pos.Y.Offset+delta.Y); shadow.Position=UDim2.new(root.Position.X.Scale,root.Position.X.Offset+4,root.Position.Y.Scale,root.Position.Y.Offset+4) end end))
pushConn(UIS.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then Hub.drag=nil end end))

-- background loops -----------------------------------------------------------
saveOriginalLighting()
fovInit(); installSilentHook(); initBacktrack(); playerWatch(); roundLoops(); applyNoclip(); setAntiAfk(Hub.state.antiAfk); fpsApply(); if Hub.state.trail then applyTrail() end; if Hub.state.xray then setXray(true) end; if Hub.state.chams then for _,p in ipairs(Players:GetPlayers()) do if p~=LocalPlayer then applyChams(p) end end end; applyPostFX()

pushConn(RunService.RenderStepped:Connect(function()
    if not Hub.alive then return end
    Camera = workspace.CurrentCamera
    espStep(); gunEspStep(); fovStep(); cameraAimStep(); renderBacktrack(); setDesync(); faceThreat()
    if Hub.state.spin then
        local _,_,r=aliveCharacter(LocalPlayer); if r then r.CFrame=r.CFrame*CFrame.Angles(0,math.rad(Hub.state.spinSpeed),0) end
    end
    if Hub.state.bhop then local _,h=aliveCharacter(LocalPlayer); if h then h:Move(h.MoveDirection, true); if h.FloorMaterial~=Enum.Material.Air then h.Jump=true end end end
    if Hub.state.antiFling then local _,_,r=aliveCharacter(LocalPlayer); if r and r.AssemblyLinearVelocity.Magnitude>200 then r.AssemblyLinearVelocity=V3(0,0,0) end end
    if Hub.state.orbit then
        local p=orbitTarget(); local _,_,tr=aliveCharacter(p); local _,_,me=aliveCharacter(LocalPlayer)
        if tr and me then local tt=os.clock()*Hub.state.orbitSpeed; local off=V3(math.cos(tt),0,math.sin(tt))*Hub.state.orbitRadius; me.CFrame=CFrame.lookAt(tr.Position+off,tr.Position) end
    end
    if Hub.state.clickFling and not Hub.clickFlingConn then
        Hub.clickFlingConn=Mouse.Button1Down:Connect(function() local target=Mouse.Target; local p=target and Players:GetPlayerFromCharacter(target:FindFirstAncestorOfClass("Model")); if p and p~=LocalPlayer then fling(p,1) end end)
    elseif not Hub.state.clickFling and Hub.clickFlingConn then pcall(function() Hub.clickFlingConn:Disconnect() end); Hub.clickFlingConn=nil end
    if Hub.state.touchFling and not Hub.touchFlingConn then
        local _,_,me=aliveCharacter(LocalPlayer); if me then Hub.touchFlingConn=me.Touched:Connect(function(hit) local p=Players:GetPlayerFromCharacter(hit:FindFirstAncestorOfClass("Model")); if p and p~=LocalPlayer then fling(p,0.7) end end) end
    elseif not Hub.state.touchFling and Hub.touchFlingConn then pcall(function() Hub.touchFlingConn:Disconnect() end); Hub.touchFlingConn=nil end
end))

pushConn(LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.4)
    setSpeed(); setJump(); setHeadless(Hub.state.headless); setLocalInvisible(Hub.state.invis); applyTrail(); setAnimations(Hub.state.packSel); if Hub.state.toyOn then makeToy(Hub.state.toy) end
    if Hub.state.farmFling then
        task.delay(0.7,function() local p=nearestTarget(); if p then fling(p,0.8) end end)
    end
end))

-- periodic status
 task.spawn(function()
    local wasRound=false
    while Hub.alive do
        local nowRound=roundActive()
        if Hub.state.music and nowRound and not wasRound then musicPlayRandom() end
        wasRound=nowRound
        local ping=0
        safe(function() ping=math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue()) end)
        Hub.lastPing=ping
        status.Text=(Hub.state.lang=="Русский" and (Hub.state.fpsUnlock and "FPS "..tostring(Hub.state.fpsCap) or "ГОТОВ") or (Hub.state.fpsUnlock and "FPS "..tostring(Hub.state.fpsCap) or "READY")) .. "  •  " .. tostring(ping) .. " ms"
        task.wait(0.5)
    end
end)

function Hub.Unload()
    if not Hub.alive then return end
    saveConfig()
    Hub.alive=false
    musicStop(); stopFly()
    setXray(false)
    for _,e in pairs(Hub.backtrack) do if e.ghost then pcall(function() e.ghost:Destroy() end) end end
    for _,p in ipairs(Players:GetPlayers()) do
        clearEspFor(p)
        local c=p.Character
        if c then destroyName(c,{"PulseCham","PulseTag","PulseBacktrack","PulseTrailA0","PulseTrailA1","PulseTrail"}) end
    end
    for _,f in ipairs(Hub.cleanups) do pcall(f) end
    for _,c in ipairs(Hub.conns) do pcall(function() c:Disconnect() end) end
    for k,v in pairs(Hub.originalLighting) do pcall(function() Lighting[k]=v end) end
    for _,n in ipairs({"PulseBloom","PulseAtmosphere","PulseRays","PulseBlur","PulseDof","PulseFog"}) do local o=Lighting:FindFirstChild(n); if o then o:Destroy() end end
    resetNoclip()
    setLocalInvisible(false)
    for d,old in pairs(Hub.optStore or {}) do if d and d.Parent then pcall(function() if old.transparency~=nil then d.Transparency=old.transparency end; if old.enabled~=nil then d.Enabled=old.enabled end; if old.shadow~=nil then d.CastShadow=old.shadow end; if old.material~=nil then d.Material=old.material end; if old.reflect~=nil and d:IsA("MeshPart") then d.Reflectance=old.reflect end end) end end
    pcall(function() espGui:Destroy() end)
    pcall(function() gui:Destroy() end)
    Env.PulseHub = nil
end

Env.PulseHub = Hub
notify("PulseHub loaded • RightShift opens the menu")
