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
    esp = false, espBox = true, espSkel = false, espTracer = false,
    gunEsp = false, xray = false, lblRole = true, lblName = true, lblDist = true,
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
    aimReturn = true, predict = 60, aimWall = true, fovShow = true, fovRadius = 160,
    killAura = false, killRadius = 18, killMode = "All",
    autoPickup = false, autoShoot = false, autoKill = false, autoFlingSheriff = false,
    knifeAim = false, knifeWall = true, knifeLead = 80, knifeAuto = false,
    desync = false, desyncMode = "Jitter", desyncRadius = 6, desyncSpeed = 20,
    faceThreat = false, resolver = false,
    -- Player
    farm = false, farmVersion = "Tween", farmSpeed = 40, farmReset = true,
    farmAvoid = true, farmFling = false,
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
    optShadow = false, optRefl = false, optLow = false, antiAfk = true,
    theme = "Frost", uiScale = 100, stretch = false, font = "Gotham",
    textSize = 0, lang = "Русский", menuKey = K.RightShift, menuKeyName = "RightShift",
    preset_night_brightness = 1.0, preset_night_clock = 0.5, preset_night_exposure = -0.2,
    preset_realism_brightness = 2.0, preset_realism_clock = 14, preset_realism_exposure = 0,
    preset_future_brightness = 3.0, preset_future_clock = 16, preset_future_exposure = 0.35,
    preset_studio_brightness = 2.5, preset_studio_clock = 12, preset_studio_exposure = 0.15,
    preset_desert_brightness = 2.4, preset_desert_clock = 15, preset_desert_exposure = 0.1,
    preset_clean_brightness = 2.2, preset_clean_clock = 13, preset_clean_exposure = 0,
}
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
    local drop = findGunDrop()
    local c, h, r = aliveCharacter(LocalPlayer)
    if not drop or not r then return false end
    local old = r.CFrame
    r.CFrame = drop.CFrame + V3(0, 2, 0)
    task.wait(0.15)
    r.CFrame = old
    return true
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
    if on then
        for _, d in ipairs(workspace:GetDescendants()) do
            if d:IsA("BasePart") and not d:IsDescendantOf(LocalPlayer.Character) then
                Hub.xray[d] = d.LocalTransparencyModifier
                d.LocalTransparencyModifier = 0.55
            end
        end
    else
        for d, old in pairs(Hub.xray) do if d and d.Parent then d.LocalTransparencyModifier = old end end
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

local function espStep()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            setupEsp(p)
            updateBillboard(p)
            local e = Hub.esp[p]
            local c, h, r = aliveCharacter(p)
            if not Hub.state.esp or not c or not h or h.Health <= 0 or not r or not hasDrawing then
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
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("Texture") or d:IsA("Decal") then d.Transparency = Hub.state.optTex and 1 or 0 end
        if d:IsA("ParticleEmitter") or d:IsA("Trail") then d.Enabled = not Hub.state.optPart end
        if d:IsA("BasePart") then
            if Hub.state.optShadow then d.CastShadow = false end
            if Hub.state.optRefl and d:IsA("MeshPart") then pcall(function() d.Reflectance = 0 end) end
            if Hub.state.optLow then d.Material = Enum.Material.Plastic end
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
    if not hasDrawing or Hub.fovDrawing then return end
    local c = Drawing.new("Circle")
    c.Visible = false; c.Filled = false; c.Thickness = 1.3; c.NumSides = 64; c.Transparency = 0.9
    c.Color = C3(137, 205, 255); Hub.fovDrawing = c
    pushCleanup(function() pcall(function() c:Remove() end) end)
end

local function fovStep()
    if not Hub.fovDrawing then return end
    local c = Hub.fovDrawing
    c.Position = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
    c.Radius = Hub.state.fovRadius
    c.Visible = Hub.state.aimOn and Hub.state.fovShow
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
local gui = Instance.new("ScreenGui")
gui.Name = "PulseHubMM2"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")
Hub.createdGui = gui

local root = Instance.new("Frame")
root.Name="Root"; root.Size=U2(0,960,0,610); root.Position=U2(0.5,-480,0.5,-305)
root.BackgroundColor3=C3(243,249,253); root.BorderSizePixel=0; root.Parent=gui
local rootStroke=Instance.new("UIStroke"); rootStroke.Color=C3(182,211,232); rootStroke.Thickness=1; rootStroke.Parent=root
local top=Instance.new("Frame"); top.Size=U2(1,0,0,58); top.BackgroundColor3=C3(235,246,253); top.BorderSizePixel=0; top.Parent=root
local title=Instance.new("TextLabel"); title.BackgroundTransparency=1; title.Position=U2(0,22,0,0); title.Size=U2(0,400,0,34); title.Text="PULSE  /  MM2"; title.Font=Enum.Font.GothamBold; title.TextSize=21; title.TextColor3=C3(48,78,104); title.TextXAlignment=Enum.TextXAlignment.Left; title.Parent=top
local sub=Instance.new("TextLabel"); sub.BackgroundTransparency=1; sub.Position=U2(0,24,0,30); sub.Size=U2(0,500,0,20); sub.Text="precision hub  •  soft frost edition"; sub.Font=Enum.Font.Gotham; sub.TextSize=10; sub.TextColor3=C3(123,157,181); sub.TextXAlignment=Enum.TextXAlignment.Left; sub.Parent=top
local status=Instance.new("TextLabel"); status.BackgroundTransparency=1; status.Position=U2(1,-190,0,12); status.Size=U2(0,165,0,32); status.Text="READY  •  0 ms"; status.Font=Enum.Font.GothamSemibold; status.TextSize=11; status.TextColor3=C3(91,147,183); status.TextXAlignment=Enum.TextXAlignment.Right; status.Parent=top
local nav=Instance.new("Frame"); nav.Position=U2(0,16,0,72); nav.Size=U2(0,185,1,-88); nav.BackgroundColor3=C3(235,244,250); nav.BorderSizePixel=0; nav.Parent=root
local navStroke=Instance.new("UIStroke"); navStroke.Color=C3(204,224,238); navStroke.Parent=nav
local navList=Instance.new("UIListLayout"); navList.Padding=UDim.new(0,4); navList.SortOrder=Enum.SortOrder.LayoutOrder; navList.Parent=nav
local page=Instance.new("Frame"); page.Position=U2(0,215,0,72); page.Size=U2(1,-231,1,-88); page.BackgroundColor3=C3(248,252,255); page.BorderSizePixel=0; page.Parent=root
local pageStroke=Instance.new("UIStroke"); pageStroke.Color=C3(218,232,242); pageStroke.Parent=page
local footer=Instance.new("TextLabel"); footer.BackgroundTransparency=1; footer.Position=U2(0,215,1,-40); footer.Size=U2(1,-231,0,20); footer.Text="RightShift  •  menu  |  all controls persist while injected"; footer.Font=Enum.Font.Gotham; footer.TextSize=10; footer.TextColor3=C3(134,164,185); footer.TextXAlignment=Enum.TextXAlignment.Right; footer.Parent=root

local FontMap = {Gotham=Enum.Font.Gotham, Ubuntu=Enum.Font.Ubuntu, ["Source Sans"]=Enum.Font.SourceSans, Montserrat=Enum.Font.Montserrat, Nunito=Enum.Font.Nunito, Arial=Enum.Font.Arial}
local ThemeMap = {
    Frost={root=C3(243,249,253), top=C3(235,246,253), page=C3(248,252,255), nav=C3(235,244,250), accent=C3(166,218,248)},
    Snow={root=C3(249,251,253), top=C3(242,247,250), page=C3(255,255,255), nav=C3(243,247,250), accent=C3(188,220,242)},
    Sky={root=C3(239,248,255), top=C3(226,242,252), page=C3(247,252,255), nav=C3(230,243,250), accent=C3(149,208,244)},
    Ice={root=C3(238,245,250), top=C3(222,238,248), page=C3(245,250,254), nav=C3(227,239,246), accent=C3(137,200,239)},
}
local function applyUISettings()
    local tm=ThemeMap[Hub.state.theme] or ThemeMap.Frost
    root.BackgroundColor3=tm.root; top.BackgroundColor3=tm.top; page.BackgroundColor3=tm.page; nav.BackgroundColor3=tm.nav
    local font=FontMap[Hub.state.font] or Enum.Font.Gotham
    for _,o in ipairs(gui:GetDescendants()) do
        if o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox") then
            if Hub.uiBaseSize[o]==nil then Hub.uiBaseSize[o]=o.TextSize end
            o.Font=font; o.TextSize=math.max(7,(Hub.uiBaseSize[o] or 10)+Hub.state.textSize)
        end
    end
end

local function section(parent, text)
    local l=Instance.new("TextLabel"); l.BackgroundTransparency=1; l.Size=U2(1,0,0,30); l.Text=text; l.Font=Enum.Font.GothamBold; l.TextSize=11; l.TextColor3=C3(83,126,157); l.TextXAlignment=Enum.TextXAlignment.Left; l.Parent=parent
    return l
end

local function card(parent, labelText, desc)
    local f=Instance.new("Frame"); f.Size=U2(1,-24,0,52); f.BackgroundColor3=C3(255,255,255); f.BorderSizePixel=0; f.Parent=parent
    local st=Instance.new("UIStroke"); st.Color=C3(223,235,244); st.Parent=f
    local l=Instance.new("TextLabel"); l.BackgroundTransparency=1; l.Position=U2(0,12,0,0); l.Size=U2(1,-90,0,20); l.Text=labelText; l.Font=Enum.Font.GothamSemibold; l.TextSize=12; l.TextColor3=C3(61,88,109); l.TextXAlignment=Enum.TextXAlignment.Left; l.Parent=f
    local d=Instance.new("TextLabel"); d.BackgroundTransparency=1; d.Position=U2(0,12,0,22); d.Size=U2(1,-90,0,19); d.Text=desc or ""; d.Font=Enum.Font.Gotham; d.TextSize=9; d.TextColor3=C3(145,169,188); d.TextXAlignment=Enum.TextXAlignment.Left; d.Parent=f
    return f,l,d
end

local function toggle(parent, labelText, key, desc, callback)
    local f=card(parent,labelText,desc)
    local b=Instance.new("TextButton"); b.AutoButtonColor=false; b.Text=""; b.Size=U2(0,44,0,24); b.Position=U2(1,-56,0.5,-12); b.BackgroundColor3=C3(224,235,243); b.BorderSizePixel=0; b.Parent=f
    local s=Instance.new("UIStroke"); s.Color=C3(204,220,232); s.Parent=b
    local dot=Instance.new("Frame"); dot.Size=U2(0,18,0,18); dot.Position=U2(0,3,0,3); dot.BackgroundColor3=C3(255,255,255); dot.BorderSizePixel=0; dot.Parent=b
    local ds=Instance.new("UIStroke"); ds.Color=C3(197,215,228); ds.Parent=dot
    local function render(v)
        b.BackgroundColor3=v and C3(166,218,248) or C3(224,235,243)
        dot.Position=v and U2(1,-21,0,3) or U2(0,3,0,3)
        dot.BackgroundColor3=v and C3(255,255,255) or C3(249,253,255)
    end
    local function set(v, silent)
        Hub.state[key]=v; render(v); if not silent and callback then callback(v) end
    end
    b.MouseButton1Click:Connect(function() set(not Hub.state[key]) end)
    Hub.controls[key]={set=set, render=render}
    render(Hub.state[key])
    return f
end

local function slider(parent, labelText, key, min, max, step, desc, suffix, callback)
    local f=card(parent,labelText,desc)
    local value=Instance.new("TextLabel"); value.BackgroundTransparency=1; value.Position=U2(1,-155,0,11); value.Size=U2(0,65,0,18); value.TextXAlignment=Enum.TextXAlignment.Right; value.Font=Enum.Font.GothamSemibold; value.TextSize=11; value.TextColor3=C3(85,130,160); value.Parent=f
    local bar=Instance.new("Frame"); bar.Position=U2(1,-90,0,17); bar.Size=U2(0,72,0,8); bar.BackgroundColor3=C3(225,237,245); bar.BorderSizePixel=0; bar.Parent=f
    local fill=Instance.new("Frame"); fill.Size=U2(0,0,1,0); fill.BackgroundColor3=C3(157,211,245); fill.BorderSizePixel=0; fill.Parent=bar
    local knob=Instance.new("Frame"); knob.Size=U2(0,10,0,10); knob.AnchorPoint=Vector2.new(0.5,0.5); knob.Position=U2(0,0,0.5,0); knob.BackgroundColor3=C3(255,255,255); knob.BorderSizePixel=0; knob.Parent=bar
    local function snap(v)
        return math.clamp(min + math.floor(((v-min)/step)+0.5)*step, min, max)
    end
    local function render(v)
        Hub.state[key]=snap(v); local p=(Hub.state[key]-min)/(max-min); fill.Size=U2(p,0,1,0); knob.Position=U2(p,0,0.5,0); value.Text=tostring(Hub.state[key]) .. (suffix or "")
    end
    local dragging=false
    local function update(x)
        local p=math.clamp((x-bar.AbsolutePosition.X)/math.max(1,bar.AbsoluteSize.X),0,1); local v=min+p*(max-min); render(v); if callback then callback(Hub.state[key]) end
    end
    bar.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=true; update(i.Position.X) end end)
    UIS.InputChanged:Connect(function(i) if dragging and i.UserInputType==Enum.UserInputType.MouseMovement then update(i.Position.X) end end)
    UIS.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end end)
    Hub.controls[key]={set=function(v) render(v); if callback then callback(Hub.state[key]) end end, render=render}
    render(Hub.state[key])
    return f
end

local function input(parent, labelText, hint, desc, callback)
    local f=card(parent,labelText,desc)
    local box=Instance.new("TextBox"); box.ClearTextOnFocus=false; box.PlaceholderText=hint or "enter"; box.Text=""; box.Font=Enum.Font.Gotham; box.TextSize=10; box.TextColor3=C3(72,105,128); box.PlaceholderColor3=C3(161,183,198); box.BackgroundColor3=C3(240,248,253); box.BorderSizePixel=0; box.Size=U2(0,165,0,28); box.Position=U2(1,-177,0,12); box.Parent=f
    box.FocusLost:Connect(function(enter) if enter and callback then callback(box.Text) end end)
    return f, box
end

local function dropdown(parent, labelText, key, items, desc, callback)
    local f=card(parent,labelText,desc)
    local b=Instance.new("TextButton"); b.AutoButtonColor=false; b.Text=""; b.Size=U2(0,150,0,28); b.Position=U2(1,-162,0,12); b.BackgroundColor3=C3(240,248,253); b.BorderSizePixel=0; b.Parent=f
    local t=Instance.new("TextLabel"); t.BackgroundTransparency=1; t.Size=U2(1,-24,1,0); t.Position=U2(0,10,0,0); t.TextXAlignment=Enum.TextXAlignment.Right; t.Font=Enum.Font.GothamSemibold; t.TextSize=10; t.TextColor3=C3(74,111,137); t.Parent=b
    local menu=Instance.new("Frame"); menu.Visible=false; menu.ZIndex=20; menu.Size=U2(0,150,0,#items*26); menu.Position=U2(1,-162,0,42); menu.BackgroundColor3=C3(250,253,255); menu.BorderSizePixel=0; menu.Parent=f
    local ms=Instance.new("UIStroke"); ms.Color=C3(205,225,237); ms.Parent=menu
    local layout=Instance.new("UIListLayout"); layout.SortOrder=Enum.SortOrder.LayoutOrder; layout.Parent=menu
    local function set(v)
        Hub.state[key]=v; t.Text=tostring(v); menu.Visible=false; if callback then callback(v) end
    end
    for _, item in ipairs(items) do
        local q=Instance.new("TextButton"); q.Text=item; q.TextSize=10; q.Font=Enum.Font.Gotham; q.TextColor3=C3(73,103,126); q.BackgroundTransparency=1; q.Size=U2(1,0,0,26); q.ZIndex=21; q.Parent=menu; q.MouseButton1Click:Connect(function() set(item) end)
    end
    b.MouseButton1Click:Connect(function() menu.Visible=not menu.Visible end)
    t.Text=tostring(Hub.state[key])
    Hub.controls[key]={set=set,render=function(v)t.Text=tostring(v)end}
    return f
end

local function button(parent, labelText, callback, desc)
    local f=card(parent,labelText,desc)
    local b=Instance.new("TextButton"); b.AutoButtonColor=false; b.Text="GO"; b.Font=Enum.Font.GothamBold; b.TextSize=10; b.TextColor3=C3(69,121,156); b.Size=U2(0,54,0,24); b.Position=U2(1,-66,0.5,-12); b.BackgroundColor3=C3(225,241,250); b.BorderSizePixel=0; b.Parent=f
    b.MouseEnter:Connect(function() b.BackgroundColor3=C3(210,235,249) end); b.MouseLeave:Connect(function() b.BackgroundColor3=C3(225,241,250) end)
    b.MouseButton1Click:Connect(function() if callback then callback() end end)
    return f
end

local function newTab(id, labelText, icon)
    local b=Instance.new("TextButton"); b.AutoButtonColor=false; b.Text=icon .. "  " .. labelText; b.Font=Enum.Font.GothamSemibold; b.TextSize=10; b.TextColor3=C3(88,119,139); b.TextXAlignment=Enum.TextXAlignment.Left; b.Size=U2(1,-8,0,34); b.BackgroundColor3=C3(235,244,250); b.BorderSizePixel=0; b.Parent=nav
    Hub.tabButtons[id]=b
    local p=Instance.new("ScrollingFrame"); p.Name=id; p.Visible=false; p.Size=U2(1,-22,1,-14); p.Position=U2(0,10,0,7); p.BackgroundTransparency=1; p.BorderSizePixel=0; p.ScrollBarThickness=3; p.ScrollBarImageColor3=C3(181,214,236); p.AutomaticCanvasSize=Enum.AutomaticSize.Y; p.CanvasSize=U2(0,0,0,0); p.Parent=page
    local l=Instance.new("UIListLayout"); l.Padding=UDim.new(0,7); l.SortOrder=Enum.SortOrder.LayoutOrder; l.Parent=p
    Hub.tabs[id]=p
    b.MouseButton1Click:Connect(function() Hub.showTab(id) end)
    return p
end

function Hub.showTab(id)
    Hub.selectedTab=id
    for k,p in pairs(Hub.tabs) do p.Visible=(k==id); Hub.tabButtons[k].BackgroundColor3=(k==id and C3(215,235,248) or C3(235,244,250)); Hub.tabButtons[k].TextColor3=(k==id and C3(56,104,137) or C3(88,119,139)) end
end

section(nav,"VISUALS")
local tESP=newTab("esp","ESP","◈")
section(tESP,"PLAYERS")
toggle(tESP,"Role ESP","esp","role colours + labels",function() end)
toggle(tESP,"Boxes","espBox","2D player boxes")
toggle(tESP,"Skeleton","espSkel","R15 bone lines")
toggle(tESP,"Tracers","espTracer","bottom-to-player lines")
toggle(tESP,"Role","lblRole","show Murderer / Sheriff / Innocent")
toggle(tESP,"Nickname","lblName","show usernames")
toggle(tESP,"Distance","lblDist","show studs distance")
section(tESP,"WORLD")
toggle(tESP,"Gun ESP","gunEsp","highlight dropped gun")
toggle(tESP,"X-Ray","xray","local wall transparency",function(v)setXray(v)end)

toggle(tESP,"Chams","chams","always-on-top role highlight",function(v) for _,p in ipairs(Players:GetPlayers()) do if p~=LocalPlayer then applyChams(p) end end end)
slider(tESP,"Chams transparency","chamsTrans",0,100,1,"fill transparency","%",function() for _,p in ipairs(Players:GetPlayers()) do if p~=LocalPlayer then applyChams(p) end end end)

local tVis=newTab("visual","Visuals","✦")
section(tVis,"POST FX")
toggle(tVis,"Bloom","bloom","soft highlight bloom",applyPostFX)
slider(tVis,"Bloom intensity","bloomInt",0,3,0.1,"","",applyPostFX)
slider(tVis,"Bloom size","bloomSize",0,56,1,"","",applyPostFX)
slider(tVis,"Bloom threshold","bloomThr",0,2,0.05,"","",applyPostFX)
toggle(tVis,"Atmosphere","atmo","soft depth haze",applyPostFX)
slider(tVis,"Density","atmoDensity",0,100,1,"","%",applyPostFX)
slider(tVis,"Haze","atmoHaze",0,10,0.1,"","",applyPostFX)
toggle(tVis,"Sun rays","rays","cinematic light rays",applyPostFX)
slider(tVis,"Ray intensity","raysInt",0,1,0.05,"","",applyPostFX)
slider(tVis,"Ray spread","raysSpread",0,1,0.05,"","",applyPostFX)
toggle(tVis,"Blur","blur","scene blur",applyPostFX)
slider(tVis,"Blur size","blurSize",0,56,1,"","",applyPostFX)
toggle(tVis,"Depth of field","dof","camera depth effect",applyPostFX)
slider(tVis,"Far blur","dofFar",0,100,1,"","%",applyPostFX)
slider(tVis,"Focus distance","dofFocus",0,200,1,"","",applyPostFX)
slider(tVis,"In-focus radius","dofRadius",0,100,1,"","",applyPostFX)
toggle(tVis,"Fog","fog","atmospheric fog",applyPostFX)
slider(tVis,"Fog distance","fogEnd",50,5000,10,""," st",applyPostFX)
section(tVis,"PLAYER FX")
toggle(tVis,"Backtrack","backtrack","ghost timing / historical positions")
slider(tVis,"Backtrack time","backMs",50,500,10,""," ms")
toggle(tVis,"Trail","trail","character motion trail",function(v) applyTrail() end)
dropdown(tVis,"Trail colour","trailColor",{"Blue","Rainbow","Pink","White"},"trail palette",function() applyTrail() end)
slider(tVis,"Trail length","trailLife",0.2,3,0.1,""," s",function() applyTrail() end)

local tAim=newTab("aim","Silent aim","⌁")
section(tAim,"AIM")
toggle(tAim,"Enable aim","aimOn","master aimbot switch")
dropdown(tAim,"Aim version","aimVersion",{"Silent","Camera"},"Silent hooks shots; Camera guides view")
dropdown(tAim,"Aim type","aimType",{"Auto role","Murderer","Sheriff","Closest to cursor","Closest to me"},"target selector")
slider(tAim,"Flick speed","aimSpeed",1,100,1,"camera interpolation","%")
toggle(tAim,"Return flick","aimReturn","return view after camera flick")
slider(tAim,"Prediction","predict",0,300,5,"velocity lead"," ms")
toggle(tAim,"Wall check","aimWall","line-of-sight check")
section(tAim,"FOV")
toggle(tAim,"Show FOV circle","fovShow","screen-space target circle")
slider(tAim,"FOV radius","fovRadius",20,600,5,""," px")

local tKill=newTab("kill","Kill aura","✹")
section(tKill,"MELEE")
toggle(tKill,"Kill aura","killAura","automatic knife stabs")
slider(tKill,"Radius","killRadius",5,60,1,"attack distance"," st")
dropdown(tKill,"Targets","killMode",{"All","Sheriff only"},"who can be selected")

local tShoot=newTab("shoot","Auto shoot","⊙")
section(tShoot,"GUN")
toggle(tShoot,"Auto pick up gun","autoPickup","move to dropped gun")
toggle(tShoot,"Auto shoot","autoShoot","fire at selected target")
toggle(tShoot,"Auto kill murderer","autoKill","only murder target")
toggle(tShoot,"Auto fling sheriff","autoFlingSheriff","physics fling sheriff")
button(tShoot,"Shoot murderer",function() local p=nearestTarget(function(x)return roleOf(x)=="Murderer"end); if p then shootAt(p) end end,"one-shot action")
button(tShoot,"Get gun now",pickupGun,"teleport to GunDrop and back")

local tKnife=newTab("knife","Knife aimbot","◇")
section(tKnife,"KNIFE")
toggle(tKnife,"Knife aimbot","knifeAim","assist knife target selection")
toggle(tKnife,"Wall check","knifeWall","line-of-sight check")
slider(tKnife,"Lead","knifeLead",0,300,5,"knife velocity lead"," ms")
toggle(tKnife,"Auto throw","knifeAuto","automatic knife throws")
button(tKnife,"Throw at target",function() local p=select(1, playersRoleTarget()); if p then knifeThrowAt(p) end end)

local tFake=newTab("fake","Fake position","◌")
section(tFake,"DESYNC")
toggle(tFake,"Fake position","desync","local offset loop")
dropdown(tFake,"Mode","desyncMode",{"Jitter","Orbit","Vertical","Behind","Sideways"},"offset pattern")
slider(tFake,"Radius","desyncRadius",1,30,1,"offset distance"," st")
slider(tFake,"Speed","desyncSpeed",1,100,1,"offset rate")
section(tFake,"EXTRAS")
toggle(tFake,"Face threat","faceThreat","turn toward nearest target")
toggle(tFake,"Resolver","resolver","smooth motion samples for targeting")

local tMove=newTab("move","Movement","⇢")
section(tMove,"MOVEMENT")
toggle(tMove,"Noclip","noclip","toggle with N",function(v) if v then applyNoclip() else resetNoclip() end end)
toggle(tMove,"Infinite jump","infJump","toggle with J")
toggle(tMove,"Anti-fling","antiFling","reduce incoming velocity")
toggle(tMove,"Fly","fly","toggle with F",function(v) if v then startFly() else stopFly() end end)
toggle(tMove,"Spin","spin","toggle with X")
toggle(tMove,"Bunny hop","bhop","toggle with B")
toggle(tMove,"Invisible","invis","experimental local hide",function(v) local c=LocalPlayer.Character; if c then for _,d in ipairs(c:GetDescendants()) do if d:IsA("BasePart") or d:IsA("Decal") then d.LocalTransparencyModifier=v and 1 or 0 end end end end)
button(tMove,"Bomb jump",bombJump,"use vertical launch")
slider(tMove,"Fly speed","flySpeed",10,200,1,"","",function() if Hub.state.fly then startFly() end end)
slider(tMove,"Spin speed","spinSpeed",1,60,1,"","")
slider(tMove,"Bomb power","bombPower",20,250,5,"launch power","")

local tFarm=newTab("farm","Autofarm","⌘")
section(tFarm,"COINS")
toggle(tFarm,"Autofarm coins","farm","collect Coin_Server parts")
dropdown(tFarm,"Farm version","farmVersion",{"Tween","Teleport"},"movement mode")
slider(tFarm,"Farm speed","farmSpeed",10,150,1,"movement rate","")
toggle(tFarm,"Reset when bag is full","farmReset","reset at detected 40-coin threshold")
toggle(tFarm,"Avoid murderer","farmAvoid","pause near murderer")
toggle(tFarm,"Auto fling after respawn","farmFling","fling nearby players after respawn")

local tTp=newTab("tp","Teleport","↗")
section(tTp,"QUICK TELEPORT")
button(tTp,"Lobby",function() local c,_,r=aliveCharacter(LocalPlayer); if r then r.CFrame=CFrame.new(0,10,0) end end,"best-effort lobby teleport")
button(tTp,"Murderer",function() local p=nearestTarget(function(x)return roleOf(x)=="Murderer"end); local _,_,r=aliveCharacter(p); local _,_,me=aliveCharacter(LocalPlayer); if r and me then me.CFrame=r.CFrame+V3(3,0,0) end end)
button(tTp,"Sheriff",function() local p=nearestTarget(function(x)return roleOf(x)=="Sheriff"end); local _,_,r=aliveCharacter(p); local _,_,me=aliveCharacter(LocalPlayer); if r and me then me.CFrame=r.CFrame+V3(3,0,0) end end)
for _,p in ipairs(Players:GetPlayers()) do if p~=LocalPlayer then button(tTp,p.Name,function() local _,_,r=aliveCharacter(p); local _,_,me=aliveCharacter(LocalPlayer); if r and me then me.CFrame=r.CFrame+V3(3,0,0) end end,"teleport") end end

local tAnim=newTab("anim","Animations","◒")
section(tAnim,"PACKS")
dropdown(tAnim,"Pack","packSel",{"Bubbly","Cartoony","Ninja","Pirate","Robot","Mage","Astronaut","Knight"},"R15 animation bundle",function(v)setAnimations(v)end)
slider(tAnim,"Pack speed","packSpeed",0.2,3,0.1,"animation playback","x",function(v) end)
section(tAnim,"EMOTES")
dropdown(tAnim,"Emote","emoteSel",{"Wave","Cheer","Laugh","Dance","Dance2","Dance3","Point"},"built-in emotes")
slider(tAnim,"Emote speed","emoteSpeed",0.2,3,0.1,"playback","x",animationToSpeed)
toggle(tAnim,"Hold mode","emoteHold","keep emote active")
toggle(tAnim,"Auto-load after respawn","animAuto","reapply animation pack")
button(tAnim,"Play emote",function() playEmote(Hub.state.emoteSel) end)
button(tAnim,"Stop emote",function() local _,h=aliveCharacter(LocalPlayer); if h then for _,tr in ipairs(h:GetPlayingAnimationTracks()) do pcall(function() tr:Stop() end) end end end)

local tTroll=newTab("troll","Troll","☷")
section(tTroll,"AVATAR")
toggle(tTroll,"Fake Korblox","korblox","local avatar change",setKorblox)
toggle(tTroll,"Fake headless","headless","local head transparency",setHeadless)
section(tTroll,"TOYS / EMOTES")
dropdown(tTroll,"Toy","toy",{"Halo","Balloon","Orb pet"},"local visual toy",function(v) if Hub.state.toyOn then makeToy(v) end end)
toggle(tTroll,"Equip toy","toyOn","local visual toy",function(v) if v then makeToy(Hub.state.toy) else clearToy() end end)
button(tTroll,"Random emote",function() local es={"Wave","Cheer","Laugh","Dance","Dance2","Dance3","Point"}; playEmote(es[math.random(1,#es)]) end)
section(tTroll,"SPEED / JUMP")
toggle(tTroll,"Custom speed","speedOn","local walk speed",function() setSpeed() end)
slider(tTroll,"Walk speed","walkSpeed",16,200,1,"","",function() setSpeed() end)
toggle(tTroll,"Custom jump","jumpOn","local jump power",function() setJump() end)
slider(tTroll,"Jump power","jumpPower",50,300,1,"","",function() setJump() end)
section(tTroll,"FLING / ORBIT")
toggle(tTroll,"Touch fling","touchFling","touch nearby player physics")
toggle(tTroll,"Click fling","clickFling","click player to fling")
toggle(tTroll,"Orbit player","orbit","circle selected target")
dropdown(tTroll,"Orbit target","orbitTarget",{"Murderer","Sheriff","Nearest"},"orbit selector")
slider(tTroll,"Orbit radius","orbitRadius",3,30,1,""," st")
slider(tTroll,"Orbit speed","orbitSpeed",1,20,1,"","")

local tMusic=newTab("music","Round music","♫")
section(tMusic,"ROUND MUSIC")
toggle(tMusic,"Auto-play on round start","music","random song at round start",function(v) if not v then musicStop() elseif roundActive() then musicPlayRandom() end end)
slider(tMusic,"Start delay","musicDelay",0,30,1,""," s")
slider(tMusic,"Volume","musicVol",0,100,1,"","%",function(v) if Hub.musicSound then Hub.musicSound.Volume=v/100 end end)
section(tMusic,"SONGS")
input(tMusic,"Audio ID","numeric ID + Enter","add any Roblox audio asset ID",function(v) local id=v:match("%d+"); if id then Hub.state.songs[#Hub.state.songs+1]=id; notify("Audio ID added: "..id) end end)
button(tMusic,"Play random now",musicPlayRandom)
button(tMusic,"Stop",musicStop)
button(tMusic,"Clear list",function() Hub.state.songs={}; musicStop() end)

local tLight=newTab("light","Lighting","☼")
section(tLight,"PRESETS")
local presets={{"night","Night"},{"realism","Realism"},{"future","Future"},{"studio","Studio"},{"desert","Desert"},{"clean","Clean atmosphere"}}
for _,pr in ipairs(presets) do
    button(tLight,pr[2],function() setPreset(pr[1]); notify(pr[2].." preset applied") end,"apply preset")
    slider(tLight,pr[2].." brightness","preset_"..pr[1].."_brightness",0.2,4,0.1,"preset brightness","",function() if Hub.selectedTab=="light" then setPreset(pr[1]) end end)
    slider(tLight,pr[2].." clock","preset_"..pr[1].."_clock",0,24,0.5,"time of day"," h",function() if Hub.selectedTab=="light" then setPreset(pr[1]) end end)
    slider(tLight,pr[2].." exposure","preset_"..pr[1].."_exposure",-2,2,0.05,"exposure","",function() if Hub.selectedTab=="light" then setPreset(pr[1]) end end)
end

local tOpt=newTab("opt","Optimization","◫")
section(tOpt,"REMOVE")
toggle(tOpt,"Remove textures","optTex","local transparency",applyOptimizations)
toggle(tOpt,"Remove particles","optPart","disable particle emitters",applyOptimizations)
toggle(tOpt,"Remove shadows","optShadow","disable BasePart shadows",applyOptimizations)
toggle(tOpt,"Remove reflections","optRefl","reduce mesh reflection",applyOptimizations)
toggle(tOpt,"Low quality mode","optLow","force Plastic material",applyOptimizations)
section(tOpt,"FPS")
toggle(tOpt,"FPS unlock","fpsUnlock","executor setfpscap",function(v) fpsApply() end)
slider(tOpt,"FPS cap","fpsCap",30,9999,10,""," FPS",function() fpsApply() end)

local tSrv=newTab("srv","Server","⌁")
section(tSrv,"SERVER")
button(tSrv,"Rejoin",function() TeleportService:TeleportToPlaceInstance(game.PlaceId,game.JobId,LocalPlayer) end)
button(tSrv,"Server hop",function() serverHop(false) end)
button(tSrv,"Small server",function() serverHop(true) end)
button(tSrv,"Copy Job ID",function() if setclipboard then setclipboard(game.JobId); notify("Job ID copied") else notify(game.JobId) end end,game.JobId)
toggle(tSrv,"Anti-AFK","antiAfk","prevent idle kick",function(v)setAntiAfk(v)end)

local tSet=newTab("set","Settings","⚙")
section(tSet,"INTERFACE")
dropdown(tSet,"Theme","theme",{"Frost","Snow","Sky","Ice"},"soft palette",function() applyUISettings() end)
slider(tSet,"Menu size","uiScale",70,140,5,"interface scale","%",function(v) root.Size=U2(0,960*v/100,0,610*v/100) end)
toggle(tSet,"Stretch to screen","stretch","fit to viewport",function(v) root.Size=v and U2(1,-60,1,-60) or U2(0,960,0,610) end)
dropdown(tSet,"Font","font",{"Gotham","Ubuntu","Source Sans","Montserrat","Nunito","Arial"},"UI font",function() applyUISettings() end)
slider(tSet,"Text size","textSize",-3,6,1,"global offset","",function() applyUISettings() end)
dropdown(tSet,"Menu key","menuKeyName",{"RightShift","Insert","Home","End","Delete"},"keyboard toggle",function(v) Hub.state.menuKey=({RightShift=K.RightShift,Insert=K.Insert,Home=K.Home,End=K.End,Delete=K.Delete})[v] or K.RightShift end)
dropdown(tSet,"Language","lang",{"Русский","English"},"interface language",function(v)
    if v=="English" then title.Text="PULSE  /  MM2"; sub.Text="precision hub  •  soft frost edition"; footer.Text="Menu key  •  all controls persist while injected"
    else title.Text="PULSE  /  MM2"; sub.Text="точный хаб  •  soft frost edition"; footer.Text="Клавиша меню  •  настройки сохраняются во время инжекта" end
end)
section(tSet,"SCRIPT")
button(tSet,"Unload script",function() Hub.Unload() end,"remove GUI, loops and effects")

Hub.showTab("esp")
applyUISettings()

-- input / keybinds -----------------------------------------------------------
pushConn(UIS.InputBegan:Connect(function(i,gp)
    if gp then return end
    if i.KeyCode == Hub.state.menuKey then root.Visible = not root.Visible end
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
pushConn(UIS.InputChanged:Connect(function(i) if Hub.drag and i.UserInputType==Enum.UserInputType.MouseMovement then local delta=i.Position-Hub.drag.start; root.Position=UDim2.new(Hub.drag.pos.X.Scale,Hub.drag.pos.X.Offset+delta.X,Hub.drag.pos.Y.Scale,Hub.drag.pos.Y.Offset+delta.Y) end end))
pushConn(UIS.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then Hub.drag=nil end end))

-- background loops -----------------------------------------------------------
saveOriginalLighting()
fovInit(); installSilentHook(); initBacktrack(); playerWatch(); roundLoops(); applyNoclip(); setAntiAfk(true); fpsApply(); setAnimations(Hub.state.packSel); applyPostFX()

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
    setSpeed(); setJump(); setHeadless(Hub.state.headless); applyTrail(); setAnimations(Hub.state.packSel); if Hub.state.toyOn then makeToy(Hub.state.toy) end
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
        status.Text=(Hub.state.fpsUnlock and "FPS "..tostring(Hub.state.fpsCap) or "READY") .. "  •  " .. tostring(ping) .. " ms"
        task.wait(0.5)
    end
end)

function Hub.Unload()
    if not Hub.alive then return end
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
    pcall(function() gui:Destroy() end)
    Env.PulseHub = nil
end

Env.PulseHub = Hub
notify("PulseHub loaded • RightShift opens the menu")
