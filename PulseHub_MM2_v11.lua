--[[
    PulseHub MM2 — standalone build
    UI: black / midnight, rectangular cards, compact controls, blue frost accents.
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
local Env = (type(getgenv) == "function" and getgenv()) or _G

local Hub = {
    alive = true,
    startedAt = os.clock(),
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
    theme = "Midnight", uiScale = 100, stretch = false, font = "Gotham",
    textSize = 0, lang = "Русский", menuKey = K.RightShift, menuKeyName = "RightShift",
    lightingPreset = "None", selectedPlayer = "", flingPower = 295, flingUp = 125, flingSpin = 16000, flingDuration = 1.35, antiFlingVelocity = 105, antiFlingAngular = 38, antiFlingJump = 48,
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
-- Prevent legacy saved post-processing from making the screen blurry after injection.
Hub.state.blur=false; Hub.state.dof=false; Hub.state.bloom=false; Hub.state.atmo=false; Hub.state.rays=false; Hub.state.fog=false
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

local function livingCharacter(p)
    local c, h, r = aliveCharacter(p)
    if not c or not h or not r or h.Health <= 0 or not c:IsDescendantOf(workspace) then return nil end
    return c, h, r
end

local function hasTool(p, name)
    local c = p and p.Character
    local b = p and p:FindFirstChildOfClass("Backpack")
    return (c and c:FindFirstChild(name)) or (b and b:FindFirstChild(name))
end

local function roleOf(p)
    if not p then return "Unknown" end
    local now=os.clock()
    if Hub.roleCache[p] and Hub.roleCache[p].t and now-Hub.roleCache[p].t<0.6 then return Hub.roleCache[p].r end
    local function normalize(v)
        if type(v)~="string" then return nil end
        local x=v:lower()
        if x:find("murder",1,true) then return "Murderer" end
        if x:find("sheriff",1,true) then return "Sheriff" end
        if x:find("hero",1,true) then return "Hero" end
        if x:find("innocent",1,true) then return "Innocent" end
        return nil
    end
    local role
    pcall(function() role=normalize(p.Team and p.Team.Name) end)
    if not role then
        for _,key in ipairs({"Role","RoleName","PlayerRole","CurrentRole"}) do
            local ok,v=pcall(function() return p:GetAttribute(key) end)
            if ok then role=normalize(v) end
            if not role and p.Character then
                ok,v=pcall(function() return p.Character:GetAttribute(key) end)
                if ok then role=normalize(v) end
            end
            if role then break end
        end
    end
    if not role and hasTool(p,"Knife") then role="Murderer" end
    if not role and hasTool(p,"Gun") then role="Sheriff" end
    role=role or "Innocent"
    Hub.roleCache[p]={r=role,t=now}
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

local function findGunDrop(force)
    local now=os.clock()
    if not force and Hub.gunDropCache and Hub.gunDropCache.Parent and now-(Hub.gunDropCacheAt or 0)<0.15 then
        return Hub.gunDropCache
    end
    local direct = workspace:FindFirstChild("GunDrop", true)
    if direct and direct:IsA("BasePart") then Hub.gunDropCache=direct; Hub.gunDropCacheAt=now; return direct end
    for _, d in ipairs(workspace:GetDescendants()) do
        if d.Name:lower():find("gundrop", 1, true) and d:IsA("BasePart") then
            Hub.gunDropCache=d; Hub.gunDropCacheAt=now
            return d
        end
    end
    Hub.gunDropCache=nil
    Hub.gunDropCacheAt=now
end

local function pickupGun()
    if not livingCharacter(LocalPlayer) then return false end
    if hasTool(LocalPlayer, "Gun") then return true end
    if not roundActive() then return false end
    local drop = findGunDrop()
    local c, h, r = livingCharacter(LocalPlayer)
    if not drop or not c or not h or not r then return false end

    -- Try all interaction APIs first. These are executor-dependent.
    for _,obj in ipairs(drop:GetDescendants()) do
        if obj:IsA("ProximityPrompt") and type(fireproximityprompt) == "function" then
            pcall(fireproximityprompt, obj, 1, true)
        elseif obj:IsA("ClickDetector") and type(fireclickdetector) == "function" then
            pcall(fireclickdetector, obj, 0)
        end
    end
    if hasTool(LocalPlayer, "Gun") then return true end

    -- Touch pickup, when the executor exposes it.
    if type(firetouchinterest) == "function" then
        local parts = {drop}
        for _,obj in ipairs(drop:GetDescendants()) do
            if obj:IsA("BasePart") then parts[#parts+1] = obj end
        end
        for _,part in ipairs(parts) do
            pcall(firetouchinterest, r, part, 0)
            pcall(firetouchinterest, r, part, 1)
        end
        if hasTool(LocalPlayer, "Gun") then return true end
    end

    -- Last resort: a very short move over the drop, only while alive.
    local old = r.CFrame
    local okMove = pcall(function() r.CFrame = drop.CFrame + V3(0,1.75,0) end)
    if not okMove then return false end
    task.wait(0.05)
    local got = hasTool(LocalPlayer, "Gun") ~= nil
    if not got and h and h.Health > 0 then
        pcall(function() h:MoveTo(drop.Position + V3(0,1,0)) end)
        task.wait(0.04)
        got = hasTool(LocalPlayer, "Gun") ~= nil
    end
    if not got and r and r.Parent then pcall(function() r.CFrame = old end) end
    return got
end

local function antiFlingStep()
    local nowTick=os.clock()
    if Hub._antiNext and nowTick<Hub._antiNext then return end
    Hub._antiNext=nowTick+0.05
    if not Hub.state.antiFling then
        Hub.antiFlingSafeCF=nil; Hub.antiFlingLastPos=nil; Hub.antiFlingLastTime=nil; Hub.antiFlingRecoverUntil=0; Hub.antiFlingShieldUntil=0
        return
    end
    local c,h,r=livingCharacter(LocalPlayer); if not c or not h or not r then return end
    local now=os.clock(); local pos=r.Position; local vel=r.AssemblyLinearVelocity; local ang=r.AssemblyAngularVelocity
    local last=Hub.antiFlingLastPos
    local dt=Hub.antiFlingLastTime and math.max(0.008,now-Hub.antiFlingLastTime) or 0.016
    local moved=last and (pos-last).Magnitude or 0
    local speed=moved/dt
    local violent=vel.Magnitude>95 or ang.Magnitude>75 or speed>140
    local stable=vel.Magnitude<65 and ang.Magnitude<55 and speed<100
    if violent and now>=(Hub.antiFlingRecoverUntil or 0) then
        if Hub.antiFlingSafeCF then pcall(function() r.CFrame=Hub.antiFlingSafeCF end) end
        pcall(function()
            r.AssemblyLinearVelocity=V3(0,0,0)
            r.AssemblyAngularVelocity=V3(0,0,0)
            h.PlatformStand=false
            h.Sit=false
            h:ChangeState(Enum.HumanoidStateType.GettingUp)
        end)
        -- Short collision shield helps against contact-based physics fling.
        Hub.antiFlingShieldUntil=now+0.28
        Hub.antiFlingRecoverUntil=now+0.16
    elseif stable then
        Hub.antiFlingSafeCF=r.CFrame
    end
    if (Hub.antiFlingShieldUntil or 0)>now then
        for _,d in ipairs(c:GetDescendants()) do
            if d:IsA("BasePart") then pcall(function() d.CanCollide=false end) end
        end
    elseif Hub.antiFlingShieldUntil and Hub.antiFlingShieldUntil>0 and now-Hub.antiFlingShieldUntil>0 then
        for _,d in ipairs(c:GetDescendants()) do
            if d:IsA("BasePart") and d~=r then pcall(function() d.CanCollide=true end) end
        end
        Hub.antiFlingShieldUntil=0
    end
    Hub.antiFlingLastPos=pos; Hub.antiFlingLastTime=now
end

-- Fling remains a client-side physics attempt. The server may override ownership or movement.
local function fling(p, seconds)
    if not p or p==LocalPlayer then return false end
    local _,mh,myr=livingCharacter(LocalPlayer); local tc,th,tr=livingCharacter(p)
    if not mh or not myr or not tc or not th or not tr then return false end
    if Hub.activeFlingConn then pcall(function() Hub.activeFlingConn:Disconnect() end); Hub.activeFlingConn=nil end
    local startCF=myr.CFrame
    local oldAuto=mh.AutoRotate; local oldCollide=myr.CanCollide; local oldMass=myr.Massless; local oldState=mh:GetState()
    local proxy=Instance.new("Part"); proxy.Name="PulseFlingProxy"; proxy.Size=V3(4.2,4.2,4.2); proxy.Transparency=1; proxy.CanCollide=true; proxy.CanTouch=true; proxy.CanQuery=false; proxy.Massless=false; proxy.CFrame=myr.CFrame; proxy.Parent=myr.Parent
    local weld=Instance.new("WeldConstraint"); weld.Part0=myr; weld.Part1=proxy; weld.Parent=proxy
    local bav
    pcall(function() bav=Instance.new("BodyAngularVelocity"); bav.Name="PulseFlingSpin"; bav.MaxTorque=V3(math.huge,math.huge,math.huge); bav.AngularVelocity=V3(0,Hub.state.flingSpin or 16000,0); bav.P=125000; bav.Parent=myr end)
    pcall(function() mh.AutoRotate=false; mh:ChangeState(Enum.HumanoidStateType.Physics); myr.CanCollide=true; myr.Massless=false end)
    local stopAt=os.clock()+(seconds or Hub.state.flingDuration or 1.35)
    local conn; local finished=false
    local function finish(restorePosition)
        if finished then return end; finished=true
        pcall(function() if conn then conn:Disconnect() end end)
        pcall(function() weld:Destroy(); proxy:Destroy(); if bav then bav:Destroy() end end)
        Hub.activeFlingConn=nil
        pcall(function()
            myr.CanCollide=oldCollide; myr.Massless=oldMass; mh.AutoRotate=oldAuto
            if restorePosition and mh.Health>0 and myr.Parent then myr.CFrame=startCF; myr.AssemblyLinearVelocity=V3(0,0,0); myr.AssemblyAngularVelocity=V3(0,0,0) end
            if mh.Health>0 and oldState~=Enum.HumanoidStateType.Dead then mh:ChangeState(Enum.HumanoidStateType.GettingUp) end
        end)
    end
    conn=RunService.Heartbeat:Connect(function()
        local _,ah,me=livingCharacter(LocalPlayer); local _,at,target=livingCharacter(p)
        if not Hub.alive or os.clock()>stopAt or not ah or not me or not at or not target then finish(true); return end
        local delta=target.Position-me.Position; local dist=delta.Magnitude; local dir=dist>0.1 and delta.Unit or V3(1,0,0); local tangent=V3(-dir.Z,0,dir.X)
        local spinT=os.clock()*math.max(32,(Hub.state.flingSpin or 16000)/275)
        local orbit=(tangent*math.cos(spinT)+dir*math.sin(spinT))*math.clamp((Hub.state.flingPower or 295)*0.45,110,180)
        local desired=target.Position-dir*2.15+V3(0,1.25,0)
        pcall(function()
            me.CFrame=CFrame.lookAt(desired,target.Position)
            local v=dir*(Hub.state.flingPower or 295)+orbit+V3(0,Hub.state.flingUp or 125,0)
            me.AssemblyLinearVelocity=v; me.AssemblyAngularVelocity=V3(0,Hub.state.flingSpin or 16000,0)
            if me.Velocity then me.Velocity=v end
        end)
        pcall(function() target.AssemblyLinearVelocity=dir*-(Hub.state.flingPower or 295)+V3(0,Hub.state.flingUp or 125,0); target.AssemblyAngularVelocity=V3(0,Hub.state.flingSpin or 16000,0) end)
    end)
    Hub.activeFlingConn=conn
    pushCleanup(function() finish(true) end)
    return true
end

local function refreshFlingConnections()
    if Hub.clickFlingConn then pcall(function() Hub.clickFlingConn:Disconnect() end); Hub.clickFlingConn=nil end
    if Hub.touchFlingConn then pcall(function() Hub.touchFlingConn:Disconnect() end); Hub.touchFlingConn=nil end

    if Hub.state.clickFling then
        Hub.clickFlingConn=Mouse.Button1Down:Connect(function()
            local target=Mouse.Target
            local model=target and target:FindFirstAncestorOfClass("Model")
            local p=model and Players:GetPlayerFromCharacter(model)
            if not p and target then
                local c=target.Parent
                while c and c~=workspace do
                    if c:IsA("Model") then
                        p=Players:GetPlayerFromCharacter(c)
                        if p then break end
                    end
                    c=c.Parent
                end
            end
            if p and p~=LocalPlayer then
                fling(p,Hub.state.flingDuration or 1.35)
            end
        end)
    end

    if Hub.state.touchFling then
        local c=LocalPlayer.Character
        local parts={}
        if c then
            for _,d in ipairs(c:GetDescendants()) do
                if d:IsA("BasePart") then parts[#parts+1]=d end
            end
        end
        if #parts>0 then
            local cons={}
            local fired={}
            local function onTouch(hit)
                local model=hit and hit:FindFirstAncestorOfClass("Model")
                local p=model and Players:GetPlayerFromCharacter(model)
                if p and p~=LocalPlayer and not fired[p] then
                    fired[p]=true
                    fling(p,math.max(0.6,(Hub.state.flingDuration or 1.35)*0.72))
                    task.delay(0.35,function() fired[p]=nil end)
                end
            end
            for _,part in ipairs(parts) do
                cons[#cons+1]=part.Touched:Connect(onTouch)
            end
            Hub.touchFlingConn={
                Disconnect=function()
                    for _,cc in ipairs(cons) do pcall(function() cc:Disconnect() end) end
                end
            }
        end
    end
end

local function selectedPlayer()
    local uid = tonumber(Hub.state.selectedPlayer)
    if not uid then return nil end
    for _,p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.UserId == uid then return p end
    end
    return nil
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
    local now=os.clock(); if Hub.coinCache and Hub.coinCacheAt and now-Hub.coinCacheAt<0.18 then return Hub.coinCache end
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
    Hub.coinCache=list; Hub.coinCacheAt=now
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
    local e=Hub.esp[p]; if not e then return end
    if e.gui then pcall(function() e.gui:Destroy() end) end
    if e.tracerBeam then pcall(function() e.tracerBeam:Destroy() end) end
    if e.skel then for _,x in ipairs(e.skel) do pcall(function() if x.beam then x.beam:Destroy() end end); pcall(function() if x.a then x.a:Destroy() end end); pcall(function() if x.b then x.b:Destroy() end end) end end
    Hub.esp[p]=nil
end
local ESP_BONES={{"Head","UpperTorso"},{"UpperTorso","LowerTorso"},{"UpperTorso","LeftUpperArm"},{"LeftUpperArm","LeftLowerArm"},{"LeftLowerArm","LeftHand"},{"UpperTorso","RightUpperArm"},{"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},{"LowerTorso","LeftUpperLeg"},{"LeftUpperLeg","LeftLowerLeg"},{"LeftLowerLeg","LeftFoot"},{"LowerTorso","RightUpperLeg"},{"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"},{"UpperTorso","Left Arm"},{"UpperTorso","Right Arm"},{"LowerTorso","Left Leg"},{"LowerTorso","Right Leg"}}
local function playerFromPart(part)
    if typeof(part)~="Instance" then return nil end
    local x=part
    while x and x~=workspace do
        if x:IsA("Model") then local p=Players:GetPlayerFromCharacter(x); if p then return p end end
        x=x.Parent
    end
    return nil
end
local function ensureGuiEsp(p)
    local e=Hub.esp[p]; if e and e.gui and e.gui.Parent then return e end
    e={skel={}}; if not espGui or not espGui.Parent then return e end
    local g=Instance.new("BillboardGui"); g.Name="PulseESP_"..tostring(p.UserId); g.ResetOnSpawn=false; g.AlwaysOnTop=true; g.LightInfluence=0; g.Size=UDim2.fromOffset(78,108); g.StudsOffset=Vector3.new(0,1.65,0); g.MaxDistance=10000; g.Parent=espGui; e.gui=g
    local box=Instance.new("Frame"); box.Name="Box"; box.BackgroundTransparency=1; box.Size=U2(1,-6,1,-6); box.Position=U2(0,3,0,3); box.Parent=g; uiCorner(box,5); e.box=box
    local st=Instance.new("UIStroke"); st.Thickness=1.4; st.Parent=box; e.boxStroke=st
    local tx=Instance.new("TextLabel"); tx.Name="Info"; tx.BackgroundTransparency=1; tx.Size=U2(1,32,0,38); tx.AnchorPoint=Vector2.new(0.5,1); tx.Position=U2(0.5,0,0,1); tx.Font=Enum.Font.GothamSemibold; tx.TextSize=10; tx.TextStrokeTransparency=0.45; tx.TextWrapped=true; tx.Parent=g; e.text=tx
    Hub.esp[p]=e; return e
end
local function ensureSkeleton(e,c)
    if not c then return end
    for _,pair in ipairs(ESP_BONES) do
        local aPart,bPart=c:FindFirstChild(pair[1]),c:FindFirstChild(pair[2])
        if aPart and bPart then
            local key=pair[1].."|"..pair[2]; local found
            for _,x in ipairs(e.skel) do if x.key==key then found=x break end end
            if not found then
                local a=Instance.new("Attachment"); a.Name="PulseSkelA"; a.Parent=aPart
                local b=Instance.new("Attachment"); b.Name="PulseSkelB"; b.Parent=bPart
                local beam=Instance.new("Beam"); beam.Name="PulseSkeleton"; beam.Attachment0=a; beam.Attachment1=b; beam.Width0=0.025; beam.Width1=0.025; beam.FaceCamera=true; beam.LightEmission=1; beam.Transparency=NumberSequence.new(0.05); beam.Parent=aPart
                e.skel[#e.skel+1]={key=key,a=a,b=b,beam=beam}
            end
        end
    end
end
local function espGuiStep()
    if not Hub.state.esp then
        for _,e in pairs(Hub.esp) do
            if e.gui then e.gui.Enabled=false end; if e.tracerBeam then e.tracerBeam.Enabled=false end
            for _,x in ipairs(e.skel or {}) do if x.beam then x.beam.Enabled=false end end
        end
        return
    end
    local localRoot=select(3,livingCharacter(LocalPlayer))
    for _,p in ipairs(Players:GetPlayers()) do
        if p~=LocalPlayer then
            local c,h,r=livingCharacter(p); local e=ensureGuiEsp(p)
            if e.gui then e.gui.Enabled=c~=nil; e.gui.Adornee=r end
            if c and h and r then
                local col=roleColor(roleOf(p)); e.box.Visible=Hub.state.espBox; e.boxStroke.Color=col; e.text.TextColor3=col
                local me=localRoot; local dist=me and math.floor((r.Position-me.Position).Magnitude) or 0; local bits={}
                if Hub.state.lblRole then bits[#bits+1]=tr(roleOf(p)) end; if Hub.state.lblName then bits[#bits+1]=p.Name end; if Hub.state.lblDist then bits[#bits+1]=tostring(dist).." st" end
                e.text.Text=table.concat(bits,"  •  "); e.text.Visible=#bits>0
                if Hub.state.espTracer and localRoot then
                    local la=localRoot:FindFirstChild("PulseTracerOrigin") or Instance.new("Attachment")
                    la.Name="PulseTracerOrigin"; la.Position=Vector3.new(0,-1.5,0); la.Parent=localRoot; e.tracerLocalAtt=la
                    local ta=r:FindFirstChild("PulseTracerTarget") or Instance.new("Attachment")
                    ta.Name="PulseTracerTarget"; ta.Position=Vector3.new(0,-1.5,0); ta.Parent=r; e.tracerTargetAtt=ta
                    if not e.tracerBeam then
                        local beam=Instance.new("Beam"); beam.Name="PulseTracer"; beam.Attachment0=la; beam.Attachment1=ta; beam.Width0=0.018; beam.Width1=0.018; beam.FaceCamera=true; beam.LightEmission=1; beam.Transparency=NumberSequence.new(0.15); beam.Parent=r; e.tracerBeam=beam
                    end
                    e.tracerBeam.Enabled=true; e.tracerBeam.Color=ColorSequence.new(col)
                elseif e.tracerBeam then e.tracerBeam.Enabled=false end
                ensureSkeleton(e,c)
                for _,x in ipairs(e.skel or {}) do if x.beam then x.beam.Enabled=Hub.state.espSkel; x.beam.Color=ColorSequence.new(col) end end
            else
                if e.tracerBeam then e.tracerBeam.Enabled=false end; for _,x in ipairs(e.skel or {}) do if x.beam then x.beam.Enabled=false end end
            end
        end
    end
end
local function espStep()
    local now=os.clock(); if Hub._espNext and now<Hub._espNext then return end; Hub._espNext=now+0.03; espGuiStep()
end

local function gunEspStep()
    local now=os.clock(); if Hub._gunNext and now<Hub._gunNext then return end; Hub._gunNext=now+0.15
    if not Hub.state.gunEsp then local old=workspace:FindFirstChild("PulseGun",true); if old then pcall(function() old:Destroy() end) end; return end
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
        if o and not o:IsA(className) then
            pcall(function() o:Destroy() end)
            o = nil
        end
        if not o then o = Instance.new(className); o.Name = name; o.Parent = Lighting end
        return o
    end

    local bloom = fx("BloomEffect", "PulseBloom")
    bloom.Enabled = Hub.state.bloom
    bloom.Intensity = Hub.state.bloomInt
    bloom.Size = Hub.state.bloomSize
    bloom.Threshold = Hub.state.bloomThr

    -- Atmosphere does not have an Enabled property. Disable it by driving
    -- Density/Haze/Glare to zero while retaining the configured values.
    local atmo = fx("Atmosphere", "PulseAtmosphere")
    atmo.Density = Hub.state.atmo and (Hub.state.atmoDensity / 100) or 0
    atmo.Haze = Hub.state.atmo and Hub.state.atmoHaze or 0
    atmo.Glare = 0

    local rays = fx("SunRaysEffect", "PulseRays")
    rays.Enabled = Hub.state.rays
    rays.Intensity = Hub.state.raysInt
    rays.Spread = Hub.state.raysSpread

    local blur = fx("BlurEffect", "PulseBlur")
    blur.Enabled = Hub.state.blur
    blur.Size = Hub.state.blurSize

    local dof = fx("DepthOfFieldEffect", "PulseDof")
    dof.Enabled = Hub.state.dof
    dof.FarIntensity = Hub.state.dofFar / 100
    dof.FocusDistance = Hub.state.dofFocus
    dof.InFocusRadius = Hub.state.dofRadius

    -- Fog is a Lighting property, not an Atmosphere.Enabled flag.
    if Hub.state.fog then
        pcall(function()
            Lighting.FogStart = 0
            Lighting.FogEnd = math.max(50, Hub.state.fogEnd)
        end)
    elseif Hub.originalLighting.FogEnd then
        pcall(function()
            Lighting.FogEnd = Hub.originalLighting.FogEnd
        end)
        if Hub.originalLighting.FogStart then
            pcall(function()
                Lighting.FogStart = Hub.originalLighting.FogStart
            end)
        end
    end

    -- Keep a single atmosphere object for the main effect; remove the old
    -- duplicate PulseFog object left by earlier builds.
    local oldFog = Lighting:FindFirstChild("PulseFog")
    if oldFog then pcall(function() oldFog:Destroy() end) end
end

local function saveOriginalLighting()
    for _, n in ipairs({"Brightness","ClockTime","ExposureCompensation","FogStart","FogEnd","GlobalShadows","OutdoorAmbient","Ambient"}) do
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
    elseif id == "bright" then ambient, outdoor = C3(210,225,240), C3(200,220,235)
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
    local now=os.clock(); if Hub._fovNext and now<Hub._fovNext then return end; Hub._fovNext=now+0.03
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
    fovGui.ZIndex = 120; fovGui.Visible = visible and not Hub.fovDrawing
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
            pcall(function()
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
                if Hub.state.autoPickup and livingCharacter(LocalPlayer) then pickupGun() end
                if Hub.state.autoKill then
                    local m = nearestTarget(function(p) return roleOf(p)=="Murderer" end)
                    if m then shootAt(m) end
                elseif Hub.state.autoShoot then
                    local t = targetByFov() or select(1, playersRoleTarget())
                    if t then shootAt(t) end
                end
                if Hub.state.knifeAuto then
                    local m = nearestTarget(function(p) return true end)
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
            end)
            task.wait(0.12)
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
    local function watchRole(p)
        p:GetPropertyChangedSignal("Team"):Connect(function() Hub.roleCache[p]=nil end)
        for _,key in ipairs({"Role","RoleName","PlayerRole","CurrentRole"}) do pcall(function() p:GetAttributeChangedSignal(key):Connect(function() Hub.roleCache[p]=nil end) end) end
    end
    pushConn(Players.PlayerAdded:Connect(function(p)
        watchRole(p)
        Hub.roleCache[p] = nil
        pushConn(p.CharacterAdded:Connect(function() task.wait(0.5); if Hub.state.trail and p==LocalPlayer then applyTrail() end end))
    end))
    pushConn(Players.PlayerRemoving:Connect(function(p) clearEspFor(p); Hub.roleCache[p]=nil; Hub.backtrack[p]=nil end))
    for _,p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            watchRole(p)
            pushConn(p.CharacterAdded:Connect(function() Hub.roleCache[p]=nil; task.wait(0.2); applyChams(p) end))
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
    ['Players'] = 'Игроки',
    ['PLAYER LIST'] = 'СПИСОК ИГРОКОВ',
    ['Selected: none'] = 'Выбран: никто',
    ['Selected: '] = 'Выбран: ',
    ['none'] = 'никто',
    ['Teleport selected'] = 'Телепорт к выбранному',
    ['Fling selected'] = 'Флинг выбранного',
    ['teleport to selected player'] = 'телепорт к выбранному игроку',
    ['best-effort physics fling'] = 'попытка физического флинга',
    ['Search functions'] = 'Поиск функций',
    ['Lighting preset'] = 'Пресет освещения',
    ['Bright'] = 'Яркое',
    ['simple lighting only'] = 'только базовое освещение',
    ['accelerates each jump'] = 'ускорение после каждого прыжка',
    ['R15 / R6 skeleton'] = 'скелет R15 / R6',
    ['lines to players'] = 'линии к игрокам',
    ['master player overlay'] = 'основной ESP игроков',
    ['PULSE  /  MM2'] = 'PULSE  /  MM2',
    ['precision hub  •  midnight interface'] = 'точный хаб  •  нежный frost-дизайн',
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
    ['Home'] = 'Главная',
    ['Overview'] = 'Обзор',
    ['Players'] = 'Игроки',
    ['Session'] = 'Сессия',
    ['Game'] = 'Игра',
    ['Status'] = 'Статус',
    ['Executor compatibility'] = 'Совместимость с executor',
    ['PulseHub is attached to the current experience'] = 'PulseHub подключён к текущей игре',
    ['Optional APIs are detected at runtime; unavailable ones stay disabled'] = 'Необязательные API определяются при запуске; недоступные функции остаются выключенными',
    ['Steal An Egg  /  Murder Mystery 2'] = 'Steal An Egg  /  Murder Mystery 2',
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
            b.Text = tr(raw)
        end
    end
    title.Text = "PULSEHUB  /  MM2"
    sub.Text = tr("precision hub  •  midnight interface")
    footer.Text = tr("Menu key  •  all controls persist while injected")
end

local function uiCorner(obj, radius)
    if not obj then return nil end
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 8)
    c.Parent = obj
    return c
end

local function getGuiParent()
    local gh = (type(gethui) == "function") and gethui or nil
    if gh then
        local ok, parent = pcall(gh)
        if ok and parent then return parent end
    end
    return game:GetService("CoreGui")
end

-- Remove stale PulseHub-owned artifacts left by a previous crashed instance.
pcall(function()
    if Env.PulseHub and type(Env.PulseHub.Unload) == "function" then Env.PulseHub.Unload() end
end)
pcall(function()
    local parent=getGuiParent()
    for _,name in ipairs({"PulseHubMM2","PulseHubESP"}) do
        local old=parent:FindFirstChild(name)
        if old then old:Destroy() end
    end
end)
pcall(function()
    for _,name in ipairs({"PulseBloom","PulseAtmosphere","PulseRays","PulseBlur","PulseDof","PulseFog"}) do
        local old=Lighting:FindFirstChild(name)
        if old then old:Destroy() end
    end
end)

local gui = Instance.new("ScreenGui")
gui.Name = "PulseHubMM2"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 500

gui.Parent = getGuiParent()
Hub.createdGui = gui

espGui = Instance.new("ScreenGui")
espGui.Name = "PulseHubESP"
espGui.ResetOnSpawn = false
espGui.IgnoreGuiInset = true
espGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
espGui.DisplayOrder = 600
espGui.Parent = getGuiParent()

local stage=Instance.new("Frame")
stage.Name="Stage"; stage.AnchorPoint=Vector2.new(0.5,0.5); stage.Size=U2(0,960,0,620); stage.ClipsDescendants=false; stage.Position=U2(0.5,0,0.5,0); stage.BackgroundTransparency=1; stage.BorderSizePixel=0; stage.ZIndex=1; stage.Parent=gui
local shadow=Instance.new("Frame")
shadow.Name="Shadow"; shadow.AnchorPoint=Vector2.new(0.5,0.5); shadow.Size=U2(0,964,0,624); shadow.Position=U2(0.5,2,0.5,2); shadow.BackgroundColor3=C3(0,0,0); shadow.BackgroundTransparency=0.62; shadow.BorderSizePixel=0; shadow.ZIndex=0; shadow.Parent=stage; uiCorner(shadow,16)
local root=Instance.new("Frame")
root.Name="Root"; root.AnchorPoint=Vector2.new(0.5,0.5); root.Size=U2(0,960,0,620); root.Position=U2(0.5,0,0.5,0); root.BackgroundColor3=C3(13,15,19); root.BorderSizePixel=0; root.ZIndex=1; root.Parent=stage; uiCorner(root,16)
local uiScale=Instance.new("UIScale"); uiScale.Scale=1; uiScale.Parent=stage; Hub.uiScaleObj=uiScale; Hub.uiStage=stage

local rootStroke = Instance.new("UIStroke")
rootStroke.Color = C3(177,213,235)
rootStroke.Thickness = 1.2
rootStroke.Transparency = 0.12
rootStroke.Parent = root

local top = Instance.new("Frame")
top.Size = U2(1,0,0,62)
top.BackgroundColor3 = C3(17,19,24)
top.BorderSizePixel = 0
top.Parent = root
top.ZIndex = 2
uiCorner(top,16)

local topMask = Instance.new("Frame")
topMask.Position = U2(0,48,0,0)
topMask.Size = U2(1,0,0,14)
topMask.BackgroundColor3 = C3(17,19,24)
topMask.BorderSizePixel = 0
topMask.Parent = top


local accent = Instance.new("Frame")
accent.Position = U2(0,0,1,-2)
accent.Size = U2(1,0,0,2)
accent.BackgroundColor3 = C3(122,205,255)
accent.BorderSizePixel = 0
accent.Parent = top
uiCorner(accent,3)

local brand = Instance.new("Frame")
brand.Size = U2(0,34,0,34)
brand.Position = U2(0,16,0,14)
brand.BackgroundColor3 = C3(21,43,56)
brand.BorderSizePixel = 0
brand.Parent = top
uiCorner(brand,9)
local brandStroke = Instance.new("UIStroke")
brandStroke.Color = C3(79,162,210)
brandStroke.Transparency = 0.2
brandStroke.Parent = brand
local brandDot = Instance.new("Frame")
brandDot.Size = U2(0,10,0,10)
brandDot.Position = U2(0.5,-5,0.5,-5)
brandDot.BackgroundColor3 = C3(122,205,255)
brandDot.BorderSizePixel = 0
brandDot.Parent = brand
uiCorner(brandDot,5)

title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = U2(0,62,0,0)
title.Size = U2(0,360,0,28)
title.Font = Enum.Font.GothamBold
title.TextSize = 18
title.TextColor3 = C3(235,244,250)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = top
i18nText(title,"PULSE  /  MM2")

sub = Instance.new("TextLabel")
sub.BackgroundTransparency = 1
sub.Position = U2(0,64,0,30)
sub.Size = U2(0,500,0,17)
sub.Font = Enum.Font.Gotham
sub.TextSize = 9
sub.TextColor3 = C3(124,151,170)
sub.TextXAlignment = Enum.TextXAlignment.Left
sub.Parent = top
i18nText(sub,"precision hub  •  midnight interface")

status = Instance.new("TextLabel")
status.BackgroundTransparency = 1
status.AnchorPoint = Vector2.new(1,0)
status.Position = U2(1,-24,0,17)
status.Size = U2(0,72,0,26)
status.Position = U2(1,-130,0,17)
status.Font = Enum.Font.GothamBold
status.TextSize = 9
status.TextColor3 = C3(182,230,253)
status.TextXAlignment = Enum.TextXAlignment.Center
status.BackgroundColor3 = C3(26,50,64)
status.BorderSizePixel = 0
status.Parent = top
uiCorner(status,8)
local statusStroke=Instance.new("UIStroke"); statusStroke.Color=C3(77,142,181); statusStroke.Transparency=0.15; statusStroke.Parent=status
status.Text = "FREE"

local closeBtn = Instance.new("TextButton")
closeBtn.AutoButtonColor = false
closeBtn.Text = "×"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 18
closeBtn.TextColor3 = C3(80,119,144)
closeBtn.Size = U2(0,30,0,30)
closeBtn.Position = U2(1,-45,0,15)
closeBtn.BackgroundColor3 = C3(28,32,40)
closeBtn.BorderSizePixel = 0
closeBtn.Parent = top
uiCorner(closeBtn,10)
local closeStroke = Instance.new("UIStroke")
closeStroke.Color = C3(57,72,86)
closeStroke.Parent = closeBtn
closeBtn.MouseEnter:Connect(function()
    closeBtn.BackgroundColor3 = C3(34,46,58)
    closeStroke.Color = C3(128,205,255)
end)
closeBtn.MouseLeave:Connect(function()
    closeBtn.BackgroundColor3 = C3(28,32,40)
    closeStroke.Color = C3(57,72,86)
end)
closeBtn.MouseButton1Click:Connect(function() stage.Visible = false end)

local nav = Instance.new("ScrollingFrame")
nav.Name = "Nav"
nav.Position = U2(0,14,0,73)
nav.Size = U2(0,154,1,-92)
nav.BackgroundColor3 = C3(18,21,27)
nav.BorderSizePixel = 0
nav.CanvasSize = U2(0,0,0,0)
nav.AutomaticCanvasSize = Enum.AutomaticSize.Y
nav.ScrollBarThickness = 4
nav.ScrollBarImageColor3 = C3(172,210,233)
nav.ZIndex = 4
nav.Parent = root
nav.ZIndex = 2
uiCorner(nav,12)
local navStroke = Instance.new("UIStroke")
navStroke.Color = C3(46,55,68)
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
page.Position = U2(0,168,0,73)
page.Size = U2(1,-184,1,-106)
page.BackgroundColor3 = C3(12,14,18)
page.BorderSizePixel = 0
page.ZIndex = 3
page.Parent = root
page.ZIndex = 2
uiCorner(page,12)
local pageStroke = Instance.new("UIStroke")
pageStroke.Color = C3(42,50,62)
pageStroke.Transparency = 0.2
pageStroke.Parent = page

footer = Instance.new("TextLabel")
footer.BackgroundTransparency = 1
footer.AnchorPoint = Vector2.new(1,1)
footer.Position = U2(1,-16,1,-10)
footer.Size = U2(0,420,0,18)
footer.Font = Enum.Font.Gotham
footer.TextSize = 9
footer.TextColor3 = C3(132,164,184)
footer.TextXAlignment = Enum.TextXAlignment.Right
footer.Parent = root
i18nText(footer,"Menu key  •  all controls persist while injected")

local FontMap={Gotham=Enum.Font.Gotham,Ubuntu=Enum.Font.Ubuntu,["Source Sans"]=Enum.Font.SourceSans,Montserrat=Enum.Font.Montserrat,Nunito=Enum.Font.Gotham,Arial=Enum.Font.Arial}
local ThemeMap={
    Midnight={root=C3(8,9,12),top=C3(12,15,20),page=C3(7,9,12),nav=C3(10,12,16),accent=C3(116,201,255)},
    Carbon={root=C3(5,6,8),top=C3(9,11,14),page=C3(4,5,7),nav=C3(7,9,12),accent=C3(103,191,247)},
    Frost={root=C3(18,24,30),top=C3(24,33,41),page=C3(15,20,26),nav=C3(20,27,34),accent=C3(139,210,247)},
    Snow={root=C3(235,240,245),top=C3(225,233,239),page=C3(245,248,251),nav=C3(231,238,244),accent=C3(137,200,239)},
    Sky={root=C3(14,23,31),top=C3(18,32,42),page=C3(11,19,26),nav=C3(15,27,36),accent=C3(145,208,244)},
    Ice={root=C3(13,21,27),top=C3(17,30,38),page=C3(10,17,23),nav=C3(14,25,32),accent=C3(137,200,239)},
}
local function applyUISettings()
    local tm=ThemeMap[Hub.state.theme] or ThemeMap.Midnight
    root.BackgroundColor3=tm.root; top.BackgroundColor3=tm.top; topMask.BackgroundColor3=tm.top
    nav.BackgroundColor3=tm.nav; page.BackgroundColor3=tm.page; accent.BackgroundColor3=tm.accent; rootStroke.Color=tm.accent
    local font=FontMap[Hub.state.font] or Enum.Font.Gotham
    local textOffset=tonumber(Hub.state.textSize) or 0
    if Hub._uiFont ~= font or Hub._uiTextOffset ~= textOffset then
        for _,o in ipairs(gui:GetDescendants()) do
            if o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox") then
                local base=o:GetAttribute("PulseBaseTextSize")
                if base==nil then base=o.TextSize; o:SetAttribute("PulseBaseTextSize",base) end
                o.Font=font
                o.TextSize=math.max(7,base+textOffset)
            end
        end
        Hub._uiFont=font; Hub._uiTextOffset=textOffset
    end
    local cam=workspace.CurrentCamera
    if cam then
        local vs=cam.ViewportSize
        local fit=math.max(0.55,math.min((vs.X-28)/960,(vs.Y-28)/620))
        local userScale=math.clamp((Hub.state.uiScale or 100)/100,0.7,1.4)
        local targetScale=Hub.state.stretch and math.min(fit,1.12) or math.min(userScale,fit)
        if math.abs((uiScale.Scale or 1)-targetScale)>0.001 then uiScale.Scale=targetScale end
    end
end

local function section(parent,raw)
    local l=Instance.new("TextLabel"); l.BackgroundTransparency=1; l.Size=U2(1,-8,0,22); l.TextXAlignment=Enum.TextXAlignment.Left; l.Font=Enum.Font.GothamBold; l.TextSize=9; l.TextColor3=C3(111,156,182); l.Parent=parent; i18nText(l,raw); return l
end
local function card(parent,rawLabel,rawDesc)
    local f=Instance.new("Frame"); f.Size=U2(1,-10,0,58); f.BackgroundColor3=C3(16,20,26); f.BorderSizePixel=0; f.Parent=parent; uiCorner(f,10)
    local st=Instance.new("UIStroke"); st.Color=C3(39,49,61); st.Parent=f
    local glow=Instance.new("Frame"); glow.Name="AccentGlow"; glow.BackgroundColor3=C3(122,205,255); glow.BackgroundTransparency=0.93; glow.Size=U2(0,3,1,-14); glow.Position=U2(0,7,0,7); glow.BorderSizePixel=0; glow.Parent=f; uiCorner(glow,4)
    local l=Instance.new("TextLabel"); l.BackgroundTransparency=1; l.Position=U2(0,14,0,0); l.Size=U2(1,-246,0,19); l.Font=Enum.Font.GothamSemibold; l.TextSize=10; l.TextColor3=C3(224,237,246); l.TextXAlignment=Enum.TextXAlignment.Left; l.TextTruncate=Enum.TextTruncate.AtEnd; l.Parent=f; i18nText(l,rawLabel)
    local d=Instance.new("TextLabel"); d.BackgroundTransparency=1; d.Position=U2(0,14,0,23); d.Size=U2(1,-246,0,17); d.Font=Enum.Font.Gotham; d.TextSize=8; d.TextColor3=C3(112,134,150); d.TextXAlignment=Enum.TextXAlignment.Left; d.TextTruncate=Enum.TextTruncate.AtEnd; d.Parent=f; i18nText(d,rawDesc or "")
    f:SetAttribute("PulseSearchText",string.lower((rawLabel or "").." "..(rawDesc or ""))); return f,l,d
end
local searchBox=Instance.new("TextBox"); searchBox.Name="FunctionSearch"; searchBox.ClearTextOnFocus=false; searchBox.Text=""; searchBox.PlaceholderText=tr("Search functions"); searchBox.Font=Enum.Font.Gotham; searchBox.TextSize=9; searchBox.TextColor3=C3(220,235,245); searchBox.PlaceholderColor3=C3(106,126,144); searchBox.BackgroundColor3=C3(23,27,34); searchBox.BorderSizePixel=0; searchBox.Size=U2(0,190,0,30); searchBox.Position=U2(1,-332,0,16); searchBox.Parent=top; uiCorner(searchBox,9); local searchStroke=Instance.new("UIStroke"); searchStroke.Color=C3(48,61,74); searchStroke.Parent=searchBox; Hub.i18n[#Hub.i18n+1]={o=searchBox,raw="Search functions",placeholder=true}
local function filterCurrentTab()
    local q=string.lower(searchBox.Text or ""); local tab=Hub.tabs[Hub.selectedTab]; if not tab then return end; for _,o in ipairs(tab:GetChildren()) do if o:IsA("GuiObject") and o:GetAttribute("PulseSearchText") then local hay=o:GetAttribute("PulseSearchText") or ""; o.Visible=(q=="" or hay:find(q,1,true)~=nil) end end
end
searchBox:GetPropertyChangedSignal("Text"):Connect(filterCurrentTab)
local function toggle(parent,labelText,key,desc,callback)
    local f=card(parent,labelText,desc); local b=Instance.new("TextButton"); b.AutoButtonColor=false; b.Text=""; b.Size=U2(0,44,0,24); b.Position=U2(1,-58,0.5,-12); b.BackgroundColor3=C3(39,46,57); b.BorderSizePixel=0; b.Parent=f; uiCorner(b,12); local s=Instance.new("UIStroke"); s.Color=C3(58,71,86); s.Parent=b; local dot=Instance.new("Frame"); dot.Size=U2(0,18,0,18); dot.Position=U2(0,3,0,3); dot.BackgroundColor3=C3(178,190,199); dot.BorderSizePixel=0; dot.Parent=b; uiCorner(dot,9); local glow=Instance.new("UIStroke"); glow.Color=C3(122,205,255); glow.Thickness=3; glow.Transparency=1; glow.Parent=b
    local function render(v) b.BackgroundColor3=v and C3(58,125,163) or C3(29,35,43); s.Color=v and C3(111,199,246) or C3(49,61,74); dot.Position=v and U2(1,-21,0,3) or U2(0,3,0,3); dot.BackgroundColor3=v and C3(235,248,255) or C3(178,190,199); glow.Transparency=v and 0.58 or 1 end
    local function set(v,silent) Hub.state[key]=v; render(v); if not silent and callback then callback(v) end; if not silent then saveConfig() end end
    b.MouseButton1Click:Connect(function() set(not Hub.state[key]) end); Hub.controls[key]={set=set,render=render}; render(Hub.state[key]); return f
end
local function slider(parent,labelText,key,min,max,step,desc,suffix,callback)
    local f=card(parent,labelText,desc); local value=Instance.new("TextLabel"); value.BackgroundTransparency=1; value.Position=U2(1,-180,0,12); value.Size=U2(0,72,0,18); value.TextXAlignment=Enum.TextXAlignment.Right; value.Font=Enum.Font.GothamSemibold; value.TextSize=9; value.TextColor3=C3(132,204,238); value.Parent=f
    local bar=Instance.new("Frame"); bar.Position=U2(1,-99,0,20); bar.Size=U2(0,78,0,8); bar.BackgroundColor3=C3(31,38,48); bar.BorderSizePixel=0; bar.Parent=f; uiCorner(bar,4); local fill=Instance.new("Frame"); fill.Size=U2(0,0,1,0); fill.BackgroundColor3=C3(94,190,238); fill.BorderSizePixel=0; fill.Parent=bar; uiCorner(fill,4); local knob=Instance.new("Frame"); knob.Size=U2(0,16,0,16); knob.AnchorPoint=Vector2.new(0.5,0.5); knob.Position=U2(0,0,0.5,0); knob.BackgroundColor3=C3(226,244,253); knob.BorderSizePixel=0; knob.Parent=bar; uiCorner(knob,8); local ks=Instance.new("UIStroke"); ks.Color=C3(112,185,224); ks.Parent=knob
    local function snap(v) return math.clamp(min+math.floor(((v-min)/step)+0.5)*step,min,max) end; local function render(v) Hub.state[key]=snap(v); local pp=(Hub.state[key]-min)/(max-min); fill.Size=U2(pp,0,1,0); knob.Position=U2(pp,0,0.5,0); value.Text=tostring(Hub.state[key])..(suffix or "") end
    local dragging=false; local pending=false; local function update(x) local pp=math.clamp((x-bar.AbsolutePosition.X)/math.max(1,bar.AbsoluteSize.X),0,1); render(min+pp*(max-min)); if key=="uiScale" then pending=true elseif callback then callback(Hub.state[key]) end end
    bar.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=true; update(i.Position.X) end end); UIS.InputChanged:Connect(function(i) if dragging and i.UserInputType==Enum.UserInputType.MouseMovement then update(i.Position.X) end end); UIS.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false; if pending then pending=false; if callback then callback(Hub.state[key]) end; saveConfig() elseif key~="uiScale" then saveConfig() end end end)
    Hub.controls[key]={set=function(v,silent) render(v); if not silent and callback then callback(Hub.state[key]) end end,render=render}; render(Hub.state[key]); return f
end
local function input(parent,labelText,hint,desc,callback)
    local f=card(parent,labelText,desc); local b=Instance.new("TextBox"); b.ClearTextOnFocus=false; b.PlaceholderText=tr(hint or "enter"); b.Text=""; b.Font=Enum.Font.Gotham; b.TextSize=9; b.TextColor3=C3(220,235,245); b.PlaceholderColor3=C3(105,126,142); b.BackgroundColor3=C3(20,25,32); b.BorderSizePixel=0; b.Size=U2(0,165,0,29); b.Position=U2(1,-177,0,14); b.Parent=f; uiCorner(b,8); local st=Instance.new("UIStroke"); st.Color=C3(48,61,74); st.Parent=b; Hub.i18n[#Hub.i18n+1]={o=b,raw=hint or "enter",placeholder=true}; b.FocusLost:Connect(function(enter) if enter and callback then callback(b.Text) end end); return f,b
end
local function dropdown(parent,labelText,key,items,desc,callback)
    local f=card(parent,labelText,desc); local b=Instance.new("TextButton"); b.AutoButtonColor=false; b.Text=""; b.Size=U2(0,165,0,29); b.Position=U2(1,-176,0,14); b.BackgroundColor3=C3(20,25,32); b.BorderSizePixel=0; b.Parent=f; uiCorner(b,8); local bs=Instance.new("UIStroke"); bs.Color=C3(48,61,74); bs.Parent=b; local t=Instance.new("TextLabel"); t.BackgroundTransparency=1; t.Size=U2(1,-20,1,0); t.Position=U2(0,10,0,0); t.TextXAlignment=Enum.TextXAlignment.Right; t.Font=Enum.Font.GothamSemibold; t.TextSize=9; t.TextColor3=C3(207,225,237); t.Parent=b
    local menu=Instance.new("Frame"); menu.Visible=false; menu.ZIndex=400; menu.Size=U2(0,165,0,math.min(#items*26+4,192)); menu.Position=U2(1,-176,0,45); menu.BackgroundColor3=C3(15,19,25); menu.BorderSizePixel=0; menu.Parent=f; uiCorner(menu,8); local ms=Instance.new("UIStroke"); ms.Color=C3(48,61,74); ms.Parent=menu; local ml=Instance.new("UIListLayout"); ml.SortOrder=Enum.SortOrder.LayoutOrder; ml.Parent=menu
    local function set(v) Hub.state[key]=v; t.Text=tr(v); saveConfig(); menu.Visible=false; if callback then callback(v) end end
    for _,item in ipairs(items) do local q=Instance.new("TextButton"); q.AutoButtonColor=false; q.Text=tr(item); q.Font=Enum.Font.Gotham; q.TextSize=9; q.TextColor3=C3(205,223,235); q.BackgroundTransparency=1; q.Size=U2(1,0,0,25); q.ZIndex=401; q.Parent=menu; uiCorner(q,6); q.MouseEnter:Connect(function() q.BackgroundTransparency=0; q.BackgroundColor3=C3(25,54,70) end); q.MouseLeave:Connect(function() q.BackgroundTransparency=1 end); q.MouseButton1Click:Connect(function() set(item) end); Hub.i18n[#Hub.i18n+1]={o=q,raw=item} end
    b.MouseButton1Click:Connect(function() menu.Visible=not menu.Visible end); t.Text=tr(Hub.state[key]); Hub.i18n[#Hub.i18n+1]={o=t,raw=Hub.state[key],dynamic=function() return Hub.state[key] end}; Hub.controls[key]={set=set,render=function(v)t.Text=tr(v)end}; return f
end
local function button(parent,labelText,callback,desc)
    local f=card(parent,labelText,desc); local b=Instance.new("TextButton"); b.AutoButtonColor=false; b.Text=tr("GO"); b.Font=Enum.Font.GothamBold; b.TextSize=9; b.TextColor3=C3(218,239,250); b.Size=U2(0,60,0,26); b.Position=U2(1,-72,0.5,-13); b.BackgroundColor3=C3(24,63,84); b.BorderSizePixel=0; b.Parent=f; uiCorner(b,8); local st=Instance.new("UIStroke"); st.Color=C3(74,148,194); st.Parent=b; b.MouseEnter:Connect(function() b.BackgroundColor3=C3(31,91,119) end); b.MouseLeave:Connect(function() b.BackgroundColor3=C3(24,63,84) end); b.MouseButton1Click:Connect(function() if callback then callback() end end); Hub.i18n[#Hub.i18n+1]={o=b,raw="GO",dynamic=function()return"GO"end,button=true}; return f
end
local function newTab(id,labelText,icon)
    local b=Instance.new("TextButton"); b.AutoButtonColor=false; b.Text=tr(labelText); b.Font=Enum.Font.GothamSemibold; b.TextSize=9; b.TextColor3=C3(125,145,160); b.TextXAlignment=Enum.TextXAlignment.Left; b.TextYAlignment=Enum.TextYAlignment.Center; b.TextTruncate=Enum.TextTruncate.AtEnd; b.Size=U2(1,-8,0,34); b.BackgroundColor3=C3(13,17,22); b.BorderSizePixel=0; b.Parent=nav; uiCorner(b,8); b:SetAttribute("PulseRawLabel",labelText)
    local pad=Instance.new("UIPadding"); pad.PaddingLeft=UDim.new(0,11); pad.PaddingRight=UDim.new(0,8); pad.Parent=b
    local st=Instance.new("UIStroke"); st.Color=C3(35,44,55); st.Parent=b
    local indicator=Instance.new("Frame"); indicator.Name="PulseIndicator"; indicator.Size=U2(0,3,0,18); indicator.Position=U2(0,0.5,-1,-9); indicator.BackgroundColor3=C3(119,205,255); indicator.BorderSizePixel=0; indicator.BackgroundTransparency=1; indicator.Parent=b; uiCorner(indicator,2)
    Hub.tabButtons[id]=b
    local p=Instance.new("ScrollingFrame"); p.Name=id; p.Visible=false; p.Size=U2(1,-14,1,-14); p.Position=U2(0,7,0,7); p.BackgroundTransparency=1; p.ZIndex=10; p.BorderSizePixel=0; p.ScrollBarThickness=3; p.ScrollBarImageColor3=C3(78,109,128); p.AutomaticCanvasSize=Enum.AutomaticSize.Y; p.CanvasSize=U2(0,0,0,0); p.Parent=page; local pad=Instance.new("UIPadding"); pad.PaddingLeft=UDim.new(0,4); pad.PaddingRight=UDim.new(0,4); pad.PaddingTop=UDim.new(0,2); pad.PaddingBottom=UDim.new(0,10); pad.Parent=p; local l=Instance.new("UIListLayout"); l.Padding=UDim.new(0,6); l.Parent=p; Hub.tabs[id]=p
    b.MouseEnter:Connect(function() if Hub.selectedTab~=id then b.BackgroundColor3=C3(24,30,38) end end); b.MouseLeave:Connect(function() if Hub.selectedTab~=id then b.BackgroundColor3=C3(18,21,27) end end); b.MouseButton1Click:Connect(function() Hub.showTab(id) end); return p
end
function Hub.showTab(id)
    Hub.selectedTab=id
    for k,p in pairs(Hub.tabs) do
        p.Visible=(k==id)
        local b=Hub.tabButtons[k]
        if b then
            local st=b:FindFirstChildOfClass("UIStroke")
            local indicator=b:FindFirstChild("PulseIndicator")
            if k==id then
                b.BackgroundColor3=C3(20,40,53)
                b.TextColor3=C3(189,233,252)
                if st then st.Color=C3(93,174,220); st.Transparency=0 end
                if indicator then indicator.BackgroundTransparency=0.1 end
            else
                b.BackgroundColor3=C3(13,17,22)
                b.TextColor3=C3(125,145,160)
                if st then st.Color=C3(35,44,55); st.Transparency=0.5 end
                if indicator then indicator.BackgroundTransparency=1 end
            end
        end
    end
    filterCurrentTab()
end

section(nav,"MAIN")
local tHome=newTab("home","Home","⌂")
section(tHome,"OVERVIEW")
local dashRow=Instance.new("Frame")
dashRow.BackgroundTransparency=1
dashRow.Size=U2(1,-8,0,72)
dashRow.Parent=tHome
local grid=Instance.new("UIGridLayout")
grid.CellPadding=UDim2.fromOffset(6,6)
grid.CellSize=UDim2.fromOffset(155,66)
grid.FillDirectionMaxCells=4
grid.SortOrder=Enum.SortOrder.LayoutOrder
grid.Parent=dashRow
local function dashCard(raw, valueKey)
    local box=Instance.new("Frame")
    box.BackgroundColor3=C3(14,18,23)
    box.BorderSizePixel=0
    box.Parent=dashRow
    uiCorner(box,8)
    local st=Instance.new("UIStroke"); st.Color=C3(38,48,58); st.Transparency=0.15; st.Parent=box
    local a=Instance.new("TextLabel")
    a.BackgroundTransparency=1; a.Position=U2(0,10,0,7); a.Size=U2(1,-18,0,14)
    a.Font=Enum.Font.GothamSemibold; a.TextSize=8; a.TextColor3=C3(113,139,156); a.TextXAlignment=Enum.TextXAlignment.Left; a.Parent=box
    i18nText(a,raw)
    local v=Instance.new("TextLabel")
    v.BackgroundTransparency=1; v.Position=U2(0,10,0,24); v.Size=U2(1,-18,0,25)
    v.Font=Enum.Font.GothamBold; v.TextSize=15; v.TextColor3=C3(220,239,249); v.TextXAlignment=Enum.TextXAlignment.Left; v.Parent=box
    v.Text="--"
    Hub.homeStats=Hub.homeStats or {}
    Hub.homeStats[valueKey]=v
    return box
end
dashCard("Players","players"); dashCard("Session","session"); dashCard("FPS","fps"); dashCard("Ping","ping")
section(tHome,"GAME")
local gameCard=card(tHome,"Murder Mystery 2","PulseHub is attached to the current experience")
local gameAccent=Instance.new("Frame"); gameAccent.Size=U2(0,4,1,-12); gameAccent.Position=U2(0,6,0,6); gameAccent.BackgroundColor3=C3(122,205,255); gameAccent.BorderSizePixel=0; gameAccent.Parent=gameCard; uiCorner(gameAccent,3)
local gameId=Instance.new("TextLabel"); gameId.BackgroundTransparency=1; gameId.Position=U2(0,14,0,35); gameId.Size=U2(1,-190,0,14); gameId.Font=Enum.Font.Gotham; gameId.TextSize=8; gameId.TextColor3=C3(101,126,143); gameId.TextXAlignment=Enum.TextXAlignment.Left; gameId.Text="Place "..tostring(game.PlaceId).."  •  Job "..string.sub(game.JobId,1,12); gameId.Parent=gameCard
button(tHome,"Rejoin",function() TeleportService:Teleport(game.PlaceId,LocalPlayer) end,"reload this server")
button(tHome,"Server hop",function() serverHop(false) end,"join another server")
section(tHome,"STATUS")
local compat=card(tHome,"Executor compatibility","Optional APIs are detected at runtime; unavailable ones stay disabled")
local compatText=Instance.new("TextLabel"); compatText.BackgroundTransparency=1; compatText.Position=U2(0,14,0,34); compatText.Size=U2(1,-28,0,16); compatText.Font=Enum.Font.Gotham; compatText.TextSize=8; compatText.TextColor3=C3(111,139,156); compatText.TextXAlignment=Enum.TextXAlignment.Left; compatText.Text="Drawing: "..(hasDrawing and "YES" or "NO").."   •   hook: "..(canHook and "YES" or "NO").."   •   FPS: "..(canFPS and "YES" or "NO"); compatText.Parent=compat

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
toggle(tPlayer,"Bunny hop","bhop","accelerates each jump",function(v)
    if not v then Hub.state.bhopSpeed=16; setSpeed() end
end)
toggle(tPlayer,"Invisible","invis","local-only transparency",function(v) setLocalInvisible(v) end)
button(tPlayer,"Bomb jump",bombJump,"vertical launch")
slider(tPlayer,"Fly speed","flySpeed",10,200,1,"","",function() if Hub.state.fly then startFly() end end)
slider(tPlayer,"Spin speed","spinSpeed",1,60,1,"","")
slider(tPlayer,"Bomb power","bombPower",20,250,5,"launch power","")
section(tPlayer,"ANTI-FLING TUNING")
slider(tPlayer,"Velocity threshold","antiFlingVelocity",60,180,5,"incoming linear speed","",function() end)
slider(tPlayer,"Angular threshold","antiFlingAngular",15,80,1,"incoming angular speed","",function() end)
slider(tPlayer,"Jump threshold","antiFlingJump",20,100,2,"sudden position delta"," st",function() end)
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

local tPlayers=newTab("players","Players","♙")
section(tPlayers,"PLAYER LIST")
local selectedLabel=Instance.new("TextLabel")
selectedLabel.BackgroundTransparency=1
selectedLabel.Size=U2(1,-18,0,24)
selectedLabel.TextXAlignment=Enum.TextXAlignment.Left
selectedLabel.Font=Enum.Font.GothamSemibold
selectedLabel.TextSize=10
selectedLabel.TextColor3=C3(80,122,149)
selectedLabel.Parent=tPlayers
i18nText(selectedLabel,"Selected: none")
Hub.selectedLabel=selectedLabel

local playerList=Instance.new("Frame")
playerList.BackgroundTransparency=1
playerList.Size=U2(1,-18,0,420)
playerList.Parent=tPlayers
local plLayout=Instance.new("UIListLayout")
plLayout.Padding=UDim.new(0,6)
plLayout.SortOrder=Enum.SortOrder.LayoutOrder
plLayout.Parent=playerList

local function refreshPlayerList()
    for _,c in ipairs(playerList:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
    local rows={}
    for _,p in ipairs(Players:GetPlayers()) do
        if p~=LocalPlayer then rows[#rows+1]=p end
    end
    table.sort(rows,function(a,b) return a.Name:lower()<b.Name:lower() end)
    for _,p in ipairs(rows) do
        local row=Instance.new("Frame")
        row.BackgroundColor3=C3(16,20,25)
        row.BackgroundTransparency=0.03
        row.BorderSizePixel=0
        row.Size=U2(1,0,0,48)
        row.Parent=playerList
        uiCorner(row,10)
        local st=Instance.new("UIStroke")
        st.Color=(selectedPlayer()==p) and C3(122,205,255) or C3(38,48,58)
        st.Parent=row
        local name=Instance.new("TextLabel")
        name.BackgroundTransparency=1; name.Position=U2(0,12,0,5); name.Size=U2(0,170,0,18)
        name.Font=Enum.Font.GothamSemibold; name.TextSize=10; name.TextColor3=roleColor(roleOf(p)); name.TextXAlignment=Enum.TextXAlignment.Left
        name.Text=p.Name; name.Parent=row
        local role=Instance.new("TextLabel")
        role.BackgroundTransparency=1; role.Position=U2(0,12,0,24); role.Size=U2(0,170,0,14)
        role.Font=Enum.Font.Gotham; role.TextSize=8; role.TextColor3=C3(135,162,179); role.TextXAlignment=Enum.TextXAlignment.Left
        role.Text=tr(roleOf(p)); role.Parent=row
        local function action(text,x,cb)
            local b=Instance.new("TextButton")
            b.AutoButtonColor=false; b.Text=text; b.Font=Enum.Font.GothamSemibold; b.TextSize=8; b.TextColor3=C3(67,112,143)
            b.Size=U2(0,54,0,26); b.Position=U2(1,x,0.5,-13); b.BackgroundColor3=C3(20,27,35); b.BorderSizePixel=0; b.Parent=row; uiCorner(b,8)
            b.MouseEnter:Connect(function() b.BackgroundColor3=C3(29,63,82) end)
            b.MouseLeave:Connect(function() b.BackgroundColor3=C3(20,27,35) end)
            b.MouseButton1Click:Connect(cb)
        end
        action("SEL",-240,function()
            Hub.state.selectedPlayer=tostring(p.UserId)
            selectedLabel.Text=tr("Selected: ")..p.Name
            refreshPlayerList(); saveConfig()
        end)
        action("CP",-180,function()
            if type(setclipboard)=="function" then pcall(setclipboard,p.Name) end
            notify(p.Name)
        end)
        action("TP",-120,function()
            local _,_,me=livingCharacter(LocalPlayer); local _,_,tar=livingCharacter(p)
            if me and tar then me.CFrame=tar.CFrame+V3(3,0,0) end
        end)
        action("FL",-60,function() fling(p,Hub.state.flingDuration or 1.35) end)
    end
    selectedLabel.Text = tr("Selected: ") .. (selectedPlayer() and selectedPlayer().Name or tr("none"))
end

pushConn(Players.PlayerAdded:Connect(function() task.delay(0.15,refreshPlayerList) end))
pushConn(Players.PlayerRemoving:Connect(function(p)
    if tostring(p.UserId)==tostring(Hub.state.selectedPlayer) then Hub.state.selectedPlayer="" end
    task.delay(0.05,refreshPlayerList)
end))
button(tPlayers,"Teleport selected",function()
    local p=selectedPlayer(); local _,_,me=livingCharacter(LocalPlayer); local _,_,tar=livingCharacter(p)
    if p and me and tar then me.CFrame=tar.CFrame+V3(3,0,0) end
end,"teleport to selected player")
button(tPlayers,"Fling selected",function() local p=selectedPlayer(); if p then fling(p,Hub.state.flingDuration or 1.35) end end,"best-effort physics fling")
section(tPlayers,"FLING TUNING")
slider(tPlayers,"Fling power","flingPower",180,500,5,"forward impulse","",function() end)
slider(tPlayers,"Fling lift","flingUp",40,220,5,"vertical impulse","",function() end)
slider(tPlayers,"Fling spin","flingSpin",5000,24000,500,"angular speed","",function() end)
slider(tPlayers,"Fling duration","flingDuration",0.5,2.5,0.05,"contact window"," s",function() end)

local tVisual=newTab("visual","Visuals","✦")
section(tVisual,"ESP")
toggle(tVisual,"ESP","esp","master player overlay")
toggle(tVisual,"Boxes","espBox","2D boxes")
toggle(tVisual,"Skeleton","espSkel","R15 / R6 skeleton")
toggle(tVisual,"Tracers","espTracer","lines to players")
toggle(tVisual,"Role","lblRole","show role")
toggle(tVisual,"Nickname","lblName","show nickname")
toggle(tVisual,"Distance","lblDist","show distance")
toggle(tVisual,"Gun ESP","gunEsp","highlight dropped gun")
toggle(tVisual,"X-Ray","xray","local wall transparency",function(v)setXray(v)end)
toggle(tVisual,"Chams","chams","always-on-top role highlight",function(v) for _,p in ipairs(Players:GetPlayers()) do if p~=LocalPlayer then applyChams(p) end end end)
slider(tVisual,"Chams transparency","chamsTrans",0,100,1,"fill transparency","%",function() for _,p in ipairs(Players:GetPlayers()) do if p~=LocalPlayer then applyChams(p) end end end)
section(tVisual,"LIGHTING")
dropdown(tVisual,"Lighting preset","lightingPreset",{"None","Night","Bright","Clean"},"simple lighting only",function(v)
    if v=="None" then setPreset(nil) else setPreset(({Night="night",Bright="bright",Clean="clean"})[v]) end
end)
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
toggle(tSocial,"Touch fling","touchFling","touch nearby player physics",function() refreshFlingConnections() end)
toggle(tSocial,"Click fling","clickFling","click player to fling",function() refreshFlingConnections() end)
toggle(tSocial,"Orbit player","orbit","circle selected target")
dropdown(tSocial,"Orbit target","orbitTarget",{"Murderer","Sheriff","Nearest"},"orbit selector")
slider(tSocial,"Orbit radius","orbitRadius",3,30,1,""," st")
slider(tSocial,"Orbit speed","orbitSpeed",1,20,1,"","")

local tWorld=newTab("world","World","☼")
section(tWorld,"ROUND MUSIC")
toggle(tWorld,"Auto-play on round start","music","random song at round start",function(v) if not v then musicStop() elseif roundActive() then musicPlayRandom() end end)
slider(tWorld,"Start delay","musicDelay",0,30,1,"delay"," s")
slider(tWorld,"Volume","musicVol",0,100,1,"volume","%",function(v) if Hub.musicSound then Hub.musicSound.Volume=v/100 end end)
input(tWorld,"Audio ID","numeric ID + Enter","add Roblox audio asset ID",function(v) local id=v:match("%d+"); if id then Hub.state.songs[#Hub.state.songs+1]=id; saveConfig(); notify("Audio ID added: "..id) end end)
button(tWorld,"Play random now",musicPlayRandom)
button(tWorld,"Stop",musicStop)
button(tWorld,"Clear list",function() Hub.state.songs={}; saveConfig(); musicStop() end)
local tSystem=newTab("system","System","◫")
section(tSystem,"OPTIMIZATION")
toggle(tSystem,"Remove textures","optTex","hide decals and textures",applyOptimizations)
toggle(tSystem,"Remove particles","optPart","disable particle emitters",applyOptimizations)
toggle(tSystem,"Low quality mode","optLow","use low-cost materials",applyOptimizations)
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
dropdown(tSet,"Theme","theme",{"Midnight","Carbon","Frost","Snow","Sky","Ice"},"interface theme",function() applyUISettings() end)
slider(tSet,"Menu size","uiScale",70,140,5,"interface scale","%",function() applyUISettings() end)
toggle(tSet,"Stretch to screen","stretch","fit to viewport",function() applyUISettings() end)
dropdown(tSet,"Font","font",{"Gotham","Ubuntu","Source Sans","Montserrat","Nunito","Arial"},"UI font",function() applyUISettings() end)
slider(tSet,"Text size","textSize",-3,6,1,"global offset", "",function() applyUISettings() end)
dropdown(tSet,"Menu key","menuKeyName",{"RightShift","Insert","Home","End","Delete"},"keyboard toggle",function(v) Hub.state.menuKey=({RightShift=K.RightShift,Insert=K.Insert,Home=K.Home,End=K.End,Delete=K.Delete})[v] or K.RightShift; saveConfig() end)
dropdown(tSet,"Language","lang",{"Русский","English"},"interface language",function(v) refreshLanguage(); applyUISettings(); saveConfig() end)
section(tSet,"CONFIG")
button(tSet,"Save config now",saveConfig,"automatic background config is also enabled")
button(tSet,"Unload script",function() Hub.Unload() end,"remove GUI, loops and effects")

Hub.showTab("home")
applyUISettings()
refreshLanguage()
refreshPlayerList()
-- UI sanity: make sure the actual window and first page are visible.
stage.Visible = true
root.Visible = true
local _home = Hub.tabs["home"]
if _home then _home.Visible = true end

local function restoreSavedState()
    if not Hub.config.loaded then
        -- Fresh injection: every functional toggle remains OFF by default.
        return
    end
    pcall(applyNoclip)
    pcall(setSpeed)
    pcall(setJump)
    if Hub.state.fly then pcall(startFly) end
    if Hub.state.invis then pcall(setLocalInvisible, true) end
    if Hub.state.xray then pcall(setXray, true) end
    if Hub.state.chams then for _,p in ipairs(Players:GetPlayers()) do if p~=LocalPlayer then pcall(applyChams,p) end end end
    if Hub.state.trail then pcall(applyTrail) end
    pcall(setAntiAfk, Hub.state.antiAfk)
    pcall(fpsApply)
    if Hub.state.speedOn then pcall(setSpeed) end
    if Hub.state.jumpOn then pcall(setJump) end
    if Hub.state.korblox then pcall(setKorblox, true) end
    if Hub.state.headless then pcall(setHeadless, true) end
    if Hub.state.toyOn then pcall(makeToy, Hub.state.toy) end
    if Hub.state.animAuto then pcall(setAnimations, Hub.state.packSel) end
    if Hub.state.lightingPreset and Hub.state.lightingPreset ~= "None" then
        local map={Night="night",Bright="bright",Clean="clean"}
        pcall(setPreset, map[Hub.state.lightingPreset])
    end
end
restoreSavedState()

-- input / keybinds -----------------------------------------------------------
pushConn(UIS.InputBegan:Connect(function(i,gp)
    if i.KeyCode == Hub.state.menuKey then
        stage.Visible = not stage.Visible
        if not stage.Visible then
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
pushConn(UIS.JumpRequest:Connect(function()
    local _,h,r=livingCharacter(LocalPlayer)
    if Hub.state.bhop and h and r then
        Hub.state.bhopSpeed = math.clamp((tonumber(Hub.state.bhopSpeed) or 16) + (tonumber(Hub.state.bhopAccel) or 2), 16, tonumber(Hub.state.bhopMax) or 100)
        pcall(function() h.WalkSpeed = Hub.state.bhopSpeed; h:ChangeState(Enum.HumanoidStateType.Jumping) end)
    elseif Hub.state.infJump and h then
        pcall(function() h:ChangeState(Enum.HumanoidStateType.Jumping) end)
    end
end))

local currentCamera=workspace.CurrentCamera
if currentCamera then
    pushConn(currentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
        if Hub._resizeQueued then return end
        Hub._resizeQueued=true
        task.defer(function()
            Hub._resizeQueued=false
            if Hub.alive then applyUISettings() end
        end)
    end))
end

-- drag
pushConn(top.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then Hub.drag={start=i.Position, pos=stage.Position} end end))
pushConn(UIS.InputChanged:Connect(function(i)
    if Hub.drag and i.UserInputType==Enum.UserInputType.MouseMovement then
        local delta=i.Position-Hub.drag.start
        stage.Position=UDim2.new(Hub.drag.pos.X.Scale,Hub.drag.pos.X.Offset+delta.X,Hub.drag.pos.Y.Scale,Hub.drag.pos.Y.Offset+delta.Y)
    end
end))
pushConn(UIS.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then Hub.drag=nil end end))

-- background loops -----------------------------------------------------------
saveOriginalLighting()
fovInit(); installSilentHook(); initBacktrack(); playerWatch(); roundLoops(); refreshFlingConnections(); applyNoclip(); setAntiAfk(Hub.state.antiAfk); fpsApply(); if Hub.state.trail then applyTrail() end; if Hub.state.xray then setXray(true) end; if Hub.state.chams then for _,p in ipairs(Players:GetPlayers()) do if p~=LocalPlayer then applyChams(p) end end end
-- Legacy scene post-FX are intentionally not auto-created; the visual tab stays lightweight.

pushConn(RunService.RenderStepped:Connect(function()
    if not Hub.alive then return end
    Camera = workspace.CurrentCamera
    local now=os.clock()
    if Hub.state.esp then pcall(espStep) end
    if Hub.state.gunEsp then pcall(gunEspStep) end
    if Hub.state.aimOn and Hub.state.fovShow then pcall(fovStep) end
    if Hub.state.aimOn or Hub.state.knifeAim then pcall(cameraAimStep) end
    if Hub.state.backtrack and (not Hub._backtrackNext or now>=Hub._backtrackNext) then Hub._backtrackNext=now+0.05; pcall(renderBacktrack) end
    if Hub.state.desync and (not Hub._desyncNext or now>=Hub._desyncNext) then Hub._desyncNext=now+0.035; pcall(setDesync) end
    if Hub.state.faceThreat and (not Hub._faceNext or now>=Hub._faceNext) then Hub._faceNext=now+0.05; pcall(faceThreat) end
    if Hub.state.spin then
        local _,_,r=livingCharacter(LocalPlayer); if r then r.CFrame=r.CFrame*CFrame.Angles(0,math.rad(Hub.state.spinSpeed),0) end
    end
    if Hub.state.bhop then
        local _,h,r=livingCharacter(LocalPlayer)
        if h and r then
            pcall(function() h.WalkSpeed = math.clamp(Hub.state.bhopSpeed,16,Hub.state.bhopMax) end)
            h:Move(h.MoveDirection, true)
            if h.FloorMaterial~=Enum.Material.Air then h.Jump=true end
        end
    end
    antiFlingStep()
    if Hub.state.orbit then
        local p=orbitTarget(); local _,_,tr=aliveCharacter(p); local _,_,me=aliveCharacter(LocalPlayer)
        if tr and me then local tt=os.clock()*Hub.state.orbitSpeed; local off=V3(math.cos(tt),0,math.sin(tt))*Hub.state.orbitRadius; me.CFrame=CFrame.lookAt(tr.Position+off,tr.Position) end
    end
    if Hub.state.clickFling and not Hub.clickFlingConn then refreshFlingConnections() end
    if Hub.state.touchFling and not Hub.touchFlingConn then refreshFlingConnections() end
end))

pushConn(LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.4)
    Hub.state.bhopSpeed = math.max(16, tonumber(Hub.state.bhopSpeed) or 16)
    setSpeed(); setJump(); setHeadless(Hub.state.headless); setLocalInvisible(Hub.state.invis); applyTrail();
    if Hub.state.animAuto then setAnimations(Hub.state.packSel) end
    if Hub.state.toyOn then makeToy(Hub.state.toy) end
    if Hub.state.chams then for _,p in ipairs(Players:GetPlayers()) do if p~=LocalPlayer then applyChams(p) end end end
    if Hub.state.xray then setXray(true) end
    refreshFlingConnections()
    if Hub.state.lightingPreset and Hub.state.lightingPreset~="None" then
        local mp={Night="night",Bright="bright",Clean="clean"}
        pcall(setPreset,mp[Hub.state.lightingPreset])
    end
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
        if Hub.state.chams then
            for _,p in ipairs(Players:GetPlayers()) do
                if p~=LocalPlayer then pcall(applyChams,p) end
            end
        end
        status.Text="FREE"
        if Hub.homeStats then
            Hub.homeStats.players.Text=tostring(math.max(0,#Players:GetPlayers()))
            Hub.homeStats.session.Text=string.format("%dm", math.floor((os.clock()-(Hub.startedAt or os.clock()))/60))
            Hub.homeStats.fps.Text=Hub.state.fpsUnlock and tostring(Hub.state.fpsCap) or "--"
            Hub.homeStats.ping.Text=tostring(ping).." ms"
        end
        task.wait(0.5)
    end
end)

function Hub.Unload()
    if not Hub.alive then return end
    saveConfig()
    Hub.alive=false
    musicStop(); stopFly()
    pcall(function() if Hub.clickFlingConn then Hub.clickFlingConn:Disconnect(); Hub.clickFlingConn=nil end end)
    pcall(function() if Hub.touchFlingConn then Hub.touchFlingConn:Disconnect(); Hub.touchFlingConn=nil end end)
    pcall(function() if Hub.activeFlingConn then Hub.activeFlingConn:Disconnect(); Hub.activeFlingConn=nil end end)
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
