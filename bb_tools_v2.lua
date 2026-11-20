local plrs = game:GetService("Players")
local run = game:GetService("RunService")
local uis = game:GetService("UserInputService")
local ws = game:GetService("Workspace")
local lt = game:GetService("Lighting")
local hs = game:GetService("HttpService")
local vimSvc = game:GetService("VirtualInputManager")
local vu = game:GetService("VirtualUser")
local sss = game:GetService("SoundService")

local lp = plrs.LocalPlayer
local cam = ws.CurrentCamera
local touch = uis.TouchEnabled and not uis.KeyboardEnabled
if cam.ViewportSize.X <= 0 then repeat task.wait() until cam.ViewportSize.X > 0 end

local G = (getgenv and getgenv()) or _G
if G.__bb_cleanup then pcall(G.__bb_cleanup) end
G.__bb_gen = (G.__bb_gen or 0) + 1
local myGen = G.__bb_gen
local function alive() return G.__bb_gen == myGen end

local cfg = {
    parry = { on = true, react = 210, lead = 10, pingOn = true, pingPct = 85, immediate = 15, missOn = true, missTol = 13, heading = true, curve = true, radiusPct = 100 },
    spam = { on = true, dist = 30, enemyDist = 20, interval = 50, fast = true, fastSpeed = 220 },
    abil = { on = false, eta = 140, cd = 6 },
    vis = { hl = true, info = true, line = false, ring = false, status = true, snd = false },
    misc = { afk = false, fpsb = false, floats = touch, light = touch, autotune = false },
}

local cfFile = "bb_tools_v1.json"
local function save()
    pcall(function() if writefile then writefile(cfFile, hs:JSONEncode(cfg)) end end)
end
local function load()
    pcall(function()
        if isfile and isfile(cfFile) then
            local d = hs:JSONDecode(readfile(cfFile))
            if type(d) ~= "table" then return end
            for k, v in pairs(d) do
                if type(v) == "table" and type(cfg[k]) == "table" then
                    for k2, v2 in pairs(v) do
                        if cfg[k][k2] ~= nil and type(v2) == type(cfg[k][k2]) then cfg[k][k2] = v2 end
                    end
                elseif cfg[k] ~= nil and type(v) == type(cfg[k]) then
                    cfg[k] = v
                end
            end
        end
    end)
end
load()
local function sanitize()
    local function cl(v, d, mn, mx) return math.clamp(tonumber(v) or d, mn, mx) end
    cfg.parry.react = cl(cfg.parry.react, 210, 80, 400)
    cfg.parry.lead = cl(cfg.parry.lead, 10, 0, 80)
    cfg.parry.pingPct = cl(cfg.parry.pingPct, 85, 0, 150)
    cfg.parry.immediate = cl(cfg.parry.immediate, 15, 6, 30)
    cfg.parry.missTol = cl(cfg.parry.missTol, 13, 4, 25)
    cfg.parry.radiusPct = cl(cfg.parry.radiusPct, 100, 70, 150)
    cfg.spam.dist = cl(cfg.spam.dist, 30, 12, 60)
    cfg.spam.enemyDist = cl(cfg.spam.enemyDist, 20, 8, 40)
    cfg.spam.interval = cl(cfg.spam.interval, 50, 25, 120)
    cfg.spam.fastSpeed = cl(cfg.spam.fastSpeed, 220, 120, 400)
    cfg.abil.eta = cl(cfg.abil.eta, 140, 60, 300)
    cfg.abil.cd = cl(cfg.abil.cd, 6, 3, 15)
end
sanitize()
local safeMode = false
pcall(function()
    if readfile and isfile and isfile("bb_boot.txt") and readfile("bb_boot.txt") == "run" then safeMode = true end
    if writefile then writefile("bb_boot.txt", "run") end
end)
if safeMode then cfg.parry.on = false end
G.__bb_cfg = cfg

local st = {
    balls = {}, ballStates = {}, ballsDirty = true, scanT = 0, folderBound = false, folderT = 0,
    remotes = {},
    lastParry = 0, lastSpam = 0, lastAbil = -99, lastAfk = tick(), parryCdUntil = 0,
    nParry = 0, nSpam = 0, nAbil = 0, nSuccess = 0, nFail = 0, succStreak = 0, parryTimes = {},
    watch = nil, wasAlive = true,
    manualSpam = false, spamActive = false, touchSeen = touch,
    pingMs = 60, pingT = 0, enemyT = 0, nearEnemy = 1e9, nearEnemyBall = 1e9,
    statusT = 0, espTextT = 0, hasBall = false,
    dbg = { speed = 0, dist = 0, eta = 0, closing = 0, miss = 0, accel = 0, tHit = 0, hitR = 0, targeted = false, targetName = "", window = 0 },
    hl = nil, bbg = nil, bbgLbl = nil, line = nil, ring = nil, snd = nil,
    gui = nil, win = nil, statusLbl = nil, spamBtn = nil, autoBtn = nil, spamToggleBtn = nil, floatsFrame = nil,
    shadowsOrig = nil, dead = false, guiBuilt = false,
}
G.__bb_state = st

local conns = {}
local function bind(ev, fn)
    if not ev then return nil end
    local c = ev:Connect(fn)
    table.insert(conns, c)
    return c
end
local function clampN(v, mn, mx) return math.clamp(v, mn, mx) end

local function getRemote(name)
    local r = st.remotes[name]
    if r and r.Parent then return r end
    local ok, found = pcall(function()
        local rs = game:GetService("ReplicatedStorage")
        local rem = rs and rs:FindFirstChild("Remotes")
        if rem then return rem:FindFirstChild(name) end
        return nil
    end)
    if ok and found then st.remotes[name] = found return found end
    st.remotes[name] = nil
    return nil
end

local function fireRemote(name)
    local r = getRemote(name)
    if r then
        if pcall(function() r:Fire() end) then return true end
        if pcall(function() r:FireServer() end) then return true end
    end
    return false
end

local function playHit()
    if not cfg.vis.snd then return end
    pcall(function()
        if not st.snd then
            local s = Instance.new("Sound")
            s.SoundId = "rbxasset://sounds/electronicpingshort.wav"
            s.Volume = 0.5
            st.snd = s
        end
        st.snd.Parent = sss
        st.snd:Play()
    end)
end

local function doParry(kind, ball)
    local now = tick()
    st.lastParry = now
    st.parryCdUntil = now + 0.35
    if kind == "spam" then st.nSpam = st.nSpam + 1 else st.nParry = st.nParry + 1 end
    table.insert(st.parryTimes, now)
    if ball then st.watch = { ball = ball, t = now } end
    if not fireRemote("ParryButtonPress") then
        pcall(function() vimSvc:SendMouseButtonEvent(0, 0, 0, true, game, 0) end)
        pcall(function() vimSvc:SendMouseButtonEvent(0, 0, 0, false, game, 0) end)
    end
    playHit()
    return true
end

local function doAbility()
    if not fireRemote("AbilityButtonPress") then
        pcall(function() vimSvc:SendKeyEvent(true, Enum.KeyCode.E, false, game) end)
        pcall(function() vimSvc:SendKeyEvent(false, Enum.KeyCode.E, false, game) end)
    end
    st.nAbil = st.nAbil + 1
    return true
end

local function bsFor(b)
    local s = st.ballStates[b]
    if not s then
        s = { hist = {}, smooth = nil, raw = Vector3.zero, accel = Vector3.zero, latched = false, latchT = 0, latchDist = 0, abilUsed = false, wasTarget = false, prevDir = nil, prevDirT = 0, curve = 0, lastPos = nil, lastT = 0 }
        st.ballStates[b] = s
    end
    return s
end

local function scanBalls(now)
    local folder = ws:FindFirstChild("Balls")
    local need = st.ballsDirty
    if folder then
        local n = #folder:GetChildren()
        if n ~= (st.childCount or -1) then
            need = true
            st.childCount = n
        end
    end
    if not need and now - st.scanT < (cfg.misc.light and 0.15 or 0.05) then
        for _, b in ipairs(st.balls) do
            if not b.Parent then st.ballStates[b] = nil end
        end
        return
    end
    st.scanT = now
    st.ballsDirty = false
    local list = nil
    if folder then list = folder:GetChildren() else list = ws:GetChildren() end
    local out = {}
    local seen = {}
    for _, c in ipairs(list) do
        if typeof(c) == "Instance" and c:IsA("BasePart") and c:GetAttribute("realBall") == true then
            table.insert(out, c)
            seen[c] = true
        end
    end
    for b in pairs(st.ballStates) do
        if not seen[b] then st.ballStates[b] = nil end
    end
    st.balls = out
    st.hasBall = #out > 0
end

local function bindBallsFolder()
    if st.folderBound then return end
    local folder = ws:FindFirstChild("Balls")
    if folder then
        st.folderBound = true
        bind(folder.ChildAdded, function() st.ballsDirty = true end)
        bind(folder.ChildRemoved, function() st.ballsDirty = true end)
    end
end
bindBallsFolder()

local function getVel(b, bs, now)
    local v = nil
    local z = b:FindFirstChild("zoomies")
    if z then
        local ok, vv = pcall(function() return z.VectorVelocity end)
        if ok and vv and typeof(vv) == "Vector3" then v = vv end
    end
    if (not v) or v.Magnitude < 0.01 then
        local av = b.AssemblyLinearVelocity
        if av and av.Magnitude >= 0.01 then v = av end
    end
    if (not v) or v.Magnitude < 0.01 then
        local bv = b.Velocity
        if bv and bv.Magnitude >= 0.01 then v = bv end
    end
    local dtv = nil
    if bs.lastPos then
        local dt = now - bs.lastT
        if dt > 0.001 and dt < 0.25 then dtv = (b.Position - bs.lastPos) / dt end
    end
    bs.lastPos = b.Position
    bs.lastT = now
    if (not v) or v.Magnitude < 0.01 then v = dtv or Vector3.zero end
    if dtv and dtv.Magnitude > 1 and v.Magnitude > 1 then
        local d = clampN(v.Unit:Dot(dtv.Unit), -1, 1)
        if math.acos(d) > 0.6 and dtv.Magnitude < v.Magnitude * 3 + 30 then v = dtv end
    end
    bs.raw = v
    local hist = bs.hist
    table.insert(hist, { t = now, v = v })
    while #hist > 14 do table.remove(hist, 1) end
    while #hist > 1 and now - hist[1].t > 0.3 do table.remove(hist, 1) end
    if not bs.smooth then
        bs.smooth = v
    else
        local sm = bs.smooth
        local snap = false
        if v.Magnitude > 1 and sm.Magnitude > 1 then
            local d = clampN(sm.Unit:Dot(v.Unit), -1, 1)
            if math.acos(d) > 0.55 then snap = true end
        end
        if v.Magnitude > sm.Magnitude * 2.2 + 20 or v.Magnitude < sm.Magnitude * 0.4 then snap = true end
        if snap then bs.smooth = v else bs.smooth = sm:Lerp(v, 0.55) end
    end
    if #hist >= 2 then
        local target = now - 0.1
        local old = hist[1]
        for _, h in ipairs(hist) do
            if h.t <= target then old = h else break end
        end
        local dt = now - old.t
        if dt > 0.03 then
            local a = (v - old.v) / dt
            if a.Magnitude > 500 then a = a.Unit * 500 end
            bs.accel = bs.accel:Lerp(a, 0.35)
        end
    end
    if bs.smooth.Magnitude < 5 then
        bs.curve = 0
        bs.prevDir = nil
    else
        local dir = bs.smooth.Unit
        if bs.prevDir and now - bs.prevDirT >= 0.08 then
            local dt = now - bs.prevDirT
            local d = clampN(bs.prevDir:Dot(dir), -1, 1)
            bs.curve = math.acos(d) / dt
            bs.prevDir = dir
            bs.prevDirT = now
        elseif not bs.prevDir then
            bs.prevDir = dir
            bs.prevDirT = now
        end
    end
    return bs.smooth
end

local function readPing(now)
    if now - st.pingT < 0.25 then return end
    st.pingT = now
    local ok, v = pcall(function()
        local stats = game:GetService("Stats")
        local net = stats:FindFirstChild("Network") or stats.Network
        local items = net:FindFirstChild("ServerStatsItem") or net.ServerStatsItem
        local item = items["Data Ping"]
        return item:GetValue()
    end)
    if ok and type(v) == "number" and v > 0 and v < 2000 then
        st.pingMs = clampN(st.pingMs * 0.6 + v * 0.4, 5, 500)
    end
end

local function ballTargeted(b, char, vel, dirToMe)
    if char and char:FindFirstChild("Highlight") then return true, lp.Name end
    local t = b:GetAttribute("target")
    if t ~= nil then return t == lp.Name, tostring(t) end
    if cfg.parry.heading and vel.Magnitude > 10 then
        return vel:Dot(dirToMe) > vel.Magnitude * 0.82, ""
    end
    return false, ""
end

local function predict(bs, bPos, hrpPos, hrpVel)
    local vel = bs.smooth or Vector3.zero
    local speed = vel.Magnitude
    local hitR = clampN(11 + speed * 0.055, 13, 32) * cfg.parry.radiusPct / 100
    local steps = cfg.misc.light and 10 or 16
    local horizon = 0.65
    local dt = horizon / steps
    local p = bPos
    local v = vel
    local tHit, minD, tMin = nil, 1e9, 0
    for i = 1, steps do
        local t = i * dt
        v = v + bs.accel * dt
        p = p + v * dt
        local d = (p - (hrpPos + hrpVel * t)).Magnitude
        if d < minD then minD = d tMin = t end
        if not tHit and d <= hitR then tHit = t end
    end
    return tHit, minD, tMin, hitR, speed
end

local function updateNear(hrpPos, ballPos, now)
    if now - st.enemyT < 0.15 then return end
    st.enemyT = now
    local best = 1e9
    local bestB = 1e9
    for _, p in ipairs(plrs:GetPlayers()) do
        if p ~= lp and p.Character then
            local h = p.Character:FindFirstChild("HumanoidRootPart")
            local hum = p.Character:FindFirstChildOfClass("Humanoid")
            if h and (not hum or hum.Health > 0) then
                local d = (h.Position - hrpPos).Magnitude
                if d < best then best = d end
                if ballPos then
                    local db = (h.Position - ballPos).Magnitude
                    if db < bestB then bestB = db end
                end
            end
        end
    end
    st.nearEnemy = best
    st.nearEnemyBall = bestB
end

local function ensureEsp()
    if not st.hl then
        local ok, hl = pcall(function() return Instance.new("Highlight") end)
        if ok and hl then
            hl.Name = "bb_hl"
            hl.FillTransparency = 0.5
            hl.OutlineTransparency = 0
            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            st.hl = hl
        end
    end
    if not st.bbg then
        local ok, bg = pcall(function() return Instance.new("BillboardGui") end)
        if ok and bg then
            bg.Name = "bb_info"
            bg.Size = UDim2.new(0, 220, 0, 54)
            bg.StudsOffset = Vector3.new(0, 3.2, 0)
            bg.AlwaysOnTop = true
            local lbl = Instance.new("TextLabel")
            lbl.Name = "t"
            lbl.Size = UDim2.new(1, 0, 1, 0)
            lbl.BackgroundTransparency = 1
            lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
            lbl.TextStrokeTransparency = 0.4
            lbl.Font = Enum.Font.BuilderSansBold
            lbl.TextSize = 15
            lbl.Text = ""
            lbl.Parent = bg
            st.bbg = bg
            st.bbgLbl = lbl
        end
    end
    if Drawing and not st.line then
        pcall(function()
            local l = Drawing.new("Line")
            l.Thickness = 2
            l.Color = Color3.fromRGB(255, 255, 255)
            l.Visible = false
            st.line = l
        end)
    end
end

local function updateEsp(b, now)
    if st.line then st.line.Visible = false end
    if not b then
        if st.hl then st.hl.Parent = nil end
        if st.bbg then st.bbg.Parent = nil end
        if st.ring then st.ring.Parent = nil end
        return
    end
    if cfg.vis.hl or cfg.vis.info then
        ensureEsp()
        if st.hl then
            st.hl.Parent = b
            st.hl.Enabled = cfg.vis.hl
            if st.dbg.targeted and st.dbg.targetName == lp.Name then
                st.hl.FillColor = Color3.fromRGB(255, 55, 55)
                st.hl.OutlineColor = Color3.fromRGB(255, 55, 55)
            elseif st.dbg.targetName ~= "" then
                st.hl.FillColor = Color3.fromRGB(255, 170, 40)
                st.hl.OutlineColor = Color3.fromRGB(255, 170, 40)
            else
                st.hl.FillColor = Color3.fromRGB(255, 255, 255)
                st.hl.OutlineColor = Color3.fromRGB(255, 255, 255)
            end
        end
        if st.bbg then
            st.bbg.Parent = b
            st.bbg.Enabled = cfg.vis.info
            if cfg.vis.info and now - st.espTextT > (cfg.misc.light and 0.2 or 0.08) then
                st.espTextT = now
                local eta = st.dbg.eta
                local etaTxt = eta >= 9000 and "--" or string.format("%.2f", eta)
                st.bbgLbl.Text = string.format("距離 %.0f  速度 %.0f  到達 %s\n標的 %s", st.dbg.dist, st.dbg.speed, etaTxt, st.dbg.targetName ~= "" and st.dbg.targetName or "なし")
            end
        end
    else
        if st.hl then st.hl.Parent = nil end
        if st.bbg then st.bbg.Parent = nil end
    end
    if cfg.vis.line and st.line and cam then
        local char = lp.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            local ok = pcall(function()
                local p1, on1 = cam:WorldToViewportPoint(hrp.Position)
                local p2, on2 = cam:WorldToViewportPoint(b.Position)
                if on1 and on2 then
                    st.line.From = Vector2.new(p1.X, p1.Y)
                    st.line.To = Vector2.new(p2.X, p2.Y)
                    st.line.Visible = true
                end
            end)
            if not ok then st.line.Visible = false end
        end
    end
    if cfg.vis.ring and st.dbg.hitR > 0 then
        local char = lp.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            if not st.ring then
                local ok, part = pcall(function() return Instance.new("Part") end)
                if ok and part then
                    part.Name = "bb_ring"
                    part.Shape = Enum.PartType.Ball
                    part.Material = Enum.Material.Neon
                    part.Color = Color3.fromRGB(255, 255, 255)
                    part.Transparency = 0.85
                    part.CanCollide = false
                    part.CanQuery = false
                    part.CanTouch = false
                    part.Anchored = true
                    st.ring = part
                end
            end
            if st.ring then
                local r = st.dbg.hitR
                st.ring.Size = Vector3.new(r * 2, r * 2, r * 2)
                st.ring.Position = hrp.Position
                st.ring.Parent = ws
            end
        end
    elseif st.ring then
        st.ring.Parent = nil
    end
end

local function updateStatus(now)
    if now - st.statusT < (cfg.misc.light and 0.25 or 0.12) then return end
    st.statusT = now
    if st.autoBtn then
        st.autoBtn.Text = cfg.parry.on and "自動ON" or "自動OFF"
        st.autoBtn.BackgroundColor3 = cfg.parry.on and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(18, 18, 21)
        st.autoBtn.TextColor3 = cfg.parry.on and Color3.fromRGB(5, 5, 5) or Color3.fromRGB(240, 240, 240)
    end
    if st.spamBtn then
        st.spamBtn.BackgroundColor3 = st.manualSpam and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(18, 18, 21)
        st.spamBtn.TextColor3 = st.manualSpam and Color3.fromRGB(5, 5, 5) or Color3.fromRGB(240, 240, 240)
    end
    if st.spamToggleBtn then
        st.spamToggleBtn.Text = st.manualSpam and "手動スパム： ON" or "手動スパム： OFF"
    end
    if not st.statusLbl then return end
    st.statusLbl.Visible = cfg.vis.status
    if not cfg.vis.status then return end
    if not st.hasBall then
        st.statusLbl.Text = "ボールなし | パリィ " .. st.nParry .. "回 成功 " .. st.nSuccess .. "回"
        return
    end
    local eta = st.dbg.eta
    local etaTxt = eta >= 9000 and "--" or string.format("%.2f", eta)
    local tgt = st.dbg.targetName == lp.Name and "自分" or (st.dbg.targetName ~= "" and st.dbg.targetName or "なし")
    st.statusLbl.Text = string.format("速度 %.0f | 距離 %.0f | 到達 %s | 標的 %s | パリィ %d 成功 %d", st.dbg.speed, st.dbg.dist, etaTxt, tgt, st.nParry, st.nSuccess)
end

local function applyFpsb()
    pcall(function()
        if cfg.misc.fpsb then
            if st.shadowsOrig == nil then st.shadowsOrig = lt.GlobalShadows end
            lt.GlobalShadows = false
        elseif st.shadowsOrig ~= nil then
            lt.GlobalShadows = st.shadowsOrig
            st.shadowsOrig = nil
        end
    end)
end

local function onDeath(now)
    st.nFail = st.nFail + 1
    st.watch = nil
    st.succStreak = 0
    if cfg.misc.autotune and cfg.parry.on and now - st.lastParry < 3 then
        cfg.parry.react = clampN(cfg.parry.react + 12, 80, 400)
        save()
    end
end

local function coreTick()
    if st.dead or not alive() then return end
    local now = tick()
    readPing(now)
    if not st.folderBound and now - st.folderT > 0.5 then
        st.folderT = now
        bindBallsFolder()
    end
    scanBalls(now)
    local char = lp.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local aliveNow = hum ~= nil and hum.Health > 0
    if hum then
        if st.wasAlive and not aliveNow then onDeath(now) end
        st.wasAlive = aliveNow
    end
    local hasValid = false
    for _, b in ipairs(st.balls) do
        if b.Parent and b:GetAttribute("realBall") == true then
            hasValid = true
            break
        end
    end
    st.hasBall = hasValid
    if not hasValid or not hrp or not aliveNow then
        st.dbg.targeted = false
        st.dbg.hitR = 0
        for _, b in ipairs(st.balls) do
            local bs = bsFor(b)
            bs.latched = false
            bs.abilUsed = false
        end
        updateEsp(nil, now)
        updateStatus(now)
        return
    end
    local hrpPos = hrp.Position
    local hrpVel = hrp.AssemblyLinearVelocity or Vector3.zero
    local best = nil
    local espBall = nil
    local espDist = 1e9
    for _, b in ipairs(st.balls) do
        if b.Parent and b:GetAttribute("realBall") == true then
        local bs = bsFor(b)
        local vel = getVel(b, bs, now)
        local toMe = hrpPos - b.Position
        local dist = toMe.Magnitude
        if dist < espDist then espDist = dist espBall = b end
        if dist > 0.01 then
            local dir = toMe / dist
            local closing = vel:Dot(dir) - hrpVel:Dot(dir)
            local etaS = 9e9
            if closing > 1 then etaS = dist / closing end
            local targeted, tName = ballTargeted(b, char, vel, dir)
            if targeted and not bs.wasTarget then bs.smooth = bs.raw end
            bs.wasTarget = targeted
            if bs.latched then
                if (not targeted) or closing <= 0 or now - bs.latchT > 1.1 or dist > bs.latchDist + 30 then
                    bs.latched = false
                    bs.abilUsed = false
                end
            end
            local tHit, minD, tMin, hitR, speed = predict(bs, b.Position, hrpPos, hrpVel)
            local score = 9e9
            if targeted then score = tHit or etaS end
            local rec = { b = b, bs = bs, dist = dist, closing = closing, etaS = etaS, targeted = targeted, tName = tName, tHit = tHit, minD = minD, tMin = tMin, hitR = hitR, speed = speed }
            if targeted and (not best or score < best.score) then
                rec.score = score
                best = rec
            end
            if b == espBall then st.espRec = rec end
            if best and best.b == b then st.bestRec = rec end
        end
        end
    end
    if st.watch then
        local wb = st.watch.ball
        local wbs = st.ballStates[wb]
        if now - st.watch.t > 0.9 or not wb.Parent or not wbs then
            st.watch = nil
        else
            local tgt = wb:GetAttribute("target")
            local wvel = wbs.smooth or Vector3.zero
            local wToMe = hrpPos - wb.Position
            local away = wToMe.Magnitude > 0.01 and wvel:Dot(wToMe.Unit) < -15
            if (tgt ~= nil and tgt ~= lp.Name) or away then
                st.nSuccess = st.nSuccess + 1
                st.succStreak = st.succStreak + 1
                if cfg.misc.autotune and st.succStreak >= 5 then
                    st.succStreak = 0
                    cfg.parry.react = clampN(cfg.parry.react - 4, 130, 400)
                    save()
                end
                st.watch = nil
            end
        end
    end
    local pri = best or st.espRec
    if pri then
        st.dbg.speed = pri.speed
        st.dbg.dist = pri.dist
        st.dbg.eta = pri.tHit or pri.etaS
        st.dbg.closing = pri.closing
        st.dbg.miss = pri.minD
        st.dbg.tHit = pri.tHit or 0
        st.dbg.hitR = pri.hitR
        st.dbg.targeted = pri.targeted
        st.dbg.targetName = pri.tName
        local pbs = pri.bs
        st.dbg.accel = pbs.accel.Magnitude
    end
    updateNear(hrpPos, espBall and espBall.Position, now)
    if best then
        local bs = best.bs
        local window = (cfg.parry.react + cfg.parry.lead) / 1000
        if cfg.parry.pingOn then window = window + (st.pingMs / 1000) * (cfg.parry.pingPct / 100) end
        if cfg.parry.curve and bs.curve > 2.5 then window = window + math.min(0.06, (bs.curve - 2.5) * 0.012) end
        st.dbg.window = window
        local kept = {}
        for _, t in ipairs(st.parryTimes) do
            if now - t <= 0.9 then table.insert(kept, t) end
        end
        st.parryTimes = kept
        local etaUse = best.tHit or best.etaS
        local clash = #kept >= 2 and (etaUse <= 0.12 or best.dist <= 12)
        local missOkSpam = (not cfg.parry.missOn) or best.minD <= best.hitR + cfg.parry.missTol + 10 or best.dist <= cfg.parry.immediate + 5
        local spamCond = false
        if cfg.spam.on and best.dist <= cfg.spam.dist and missOkSpam then
            if st.nearEnemy <= cfg.spam.enemyDist or st.nearEnemyBall <= cfg.spam.enemyDist or clash or (cfg.spam.fast and best.speed >= cfg.spam.fastSpeed) or (etaUse <= 0.09 and st.nearEnemy <= cfg.spam.enemyDist + 6) then
                spamCond = true
            end
        end
        st.spamActive = spamCond or st.manualSpam
        local effInterval = cfg.spam.interval
        if best.speed > 10 then
            effInterval = clampN(cfg.spam.interval * clampN(140 / best.speed, 0.55, 1.15), 22, 120)
        end
        local firedSpam = false
        if st.spamActive and now - st.lastSpam >= effInterval / 1000 then
            st.lastSpam = now
            doParry("spam", best.b)
            firedSpam = true
            bs.latched = true
            bs.latchT = now
            bs.latchDist = best.dist
        end
        if not firedSpam and cfg.parry.on and not bs.latched then
            local canHit = false
            local timed = false
            if cfg.parry.missOn then
                canHit = (best.tHit ~= nil) or (best.minD <= best.hitR * 0.8)
                timed = (best.tHit ~= nil and best.tHit <= window) or (best.tHit == nil and best.minD <= best.hitR * 0.8 and best.tMin <= window)
            else
                canHit = (best.tHit ~= nil) or (best.etaS <= window + 0.1)
                timed = (best.tHit ~= nil and best.tHit <= window) or (best.etaS <= window)
            end
            if canHit and (timed or best.dist <= cfg.parry.immediate) and best.closing > 5 then
                if doParry("auto", best.b) then
                    bs.latched = true
                    bs.latchT = now
                    bs.latchDist = best.dist
                end
            end
        end
        if cfg.abil.on and not bs.abilUsed and now - st.lastAbil >= cfg.abil.cd then
            local abilWin = cfg.abil.eta / 1000
            local panic = etaUse <= abilWin * 0.45 and ((not cfg.parry.on) or (bs.latched and now - bs.latchT > 0.1))
            local afterParry = bs.latched and (now - bs.latchT) >= 0.22 and etaUse <= abilWin
            local cdBlocked = (now + etaUse) < st.parryCdUntil + 0.05 and etaUse <= abilWin and ((bs.latched and now - bs.latchT > 0.1) or not cfg.parry.on)
            if panic or afterParry or cdBlocked then
                if doAbility() then
                    bs.abilUsed = true
                    st.lastAbil = now
                end
            end
        end
    else
        st.spamActive = st.manualSpam
        if st.manualSpam and now - st.lastSpam >= cfg.spam.interval / 1000 then
            st.lastSpam = now
            doParry("spam", espBall)
        end
    end
    if cfg.misc.afk and now - st.lastAfk > 600 then
        st.lastAfk = now
        pcall(function()
            vu:CaptureController()
            vu:ClickButton2(Vector2.new(0, 0))
        end)
    end
    updateEsp(best and best.b or espBall, now)
    updateStatus(now)
end

local function cleanup()
    if st.dead then return end
    st.dead = true
    G.__bb_gen = G.__bb_gen + 1
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    if st.gui then pcall(function() st.gui:Destroy() end) end
    if st.hl then pcall(function() st.hl:Destroy() end) end
    if st.bbg then pcall(function() st.bbg:Destroy() end) end
    if st.ring then pcall(function() st.ring:Destroy() end) end
    if st.snd then pcall(function() st.snd:Destroy() end) end
    if st.line then pcall(function() st.line:Remove() end) end
    if st.shadowsOrig ~= nil then pcall(function() lt.GlobalShadows = st.shadowsOrig end) end
    pcall(function() if writefile then writefile("bb_boot.txt", "ok") end end)
    if G.__bb_cleanup == cleanup then G.__bb_cleanup = nil end
end
G.__bb_cleanup = cleanup

bind(uis.InputBegan, function(input, gp)
    if input.UserInputType == Enum.UserInputType.Touch then
        st.touchSeen = true
        if st.floatsFrame then st.floatsFrame.Visible = cfg.misc.floats or st.touchSeen end
    end
    if gp then return end
    local focused = nil
    pcall(function() focused = uis:GetFocusedTextBox() end)
    if focused then return end
    if input.KeyCode == Enum.KeyCode.Q then
        st.manualSpam = true
    elseif input.KeyCode == Enum.KeyCode.T then
        doParry("manual", nil)
    elseif input.KeyCode == Enum.KeyCode.E then
        local now = tick()
        if now - st.lastAbil >= 1 then
            if doAbility() then st.lastAbil = now end
        end
    elseif input.KeyCode == Enum.KeyCode.RightShift then
        if st.win then st.win.Visible = not st.win.Visible end
    end
end)
bind(uis.InputEnded, function(input)
    if input.KeyCode == Enum.KeyCode.Q then
        st.manualSpam = false
    end
end)

applyFpsb()
local sig = nil
pcall(function() sig = run.PreSimulation end)
if not sig then sig = run.Heartbeat end
bind(sig, coreTick)
task.delay(0.8, function()
    if alive() and not st.dead then
        pcall(function() if writefile then writefile("bb_boot.txt", "ok") end end)
    end
end)

local function buildGui()
    if not alive() or st.dead or st.guiBuilt then return end
    st.guiBuilt = true
    local C = {
        bg = Color3.fromRGB(10, 10, 12), panel = Color3.fromRGB(18, 18, 21),
        panel2 = Color3.fromRGB(26, 26, 30), line = Color3.fromRGB(48, 48, 56),
        txt = Color3.fromRGB(240, 240, 240), sub = Color3.fromRGB(165, 165, 172),
        white = Color3.fromRGB(255, 255, 255), black = Color3.fromRGB(5, 5, 5),
    }
    local function mk(class, props, parent)
        local o = Instance.new(class)
        for k, v in pairs(props) do o[k] = v end
        if parent then o.Parent = parent end
        return o
    end
    local function corner(o, r)
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, r or 8)
        c.Parent = o
        return c
    end
    local guiParent = nil
    pcall(function() guiParent = gethui() end)
    if not guiParent then guiParent = lp:WaitForChild("PlayerGui") end
    local gui = mk("ScreenGui", { Name = "bb_tools", ResetOnSpawn = false, DisplayOrder = 999, IgnoreGuiInset = true }, guiParent)
    st.gui = gui
    local vp = cam.ViewportSize
    local win = mk("Frame", { Name = "win", Size = UDim2.new(0, 560, 0, 400), Position = UDim2.new(0.5, 0, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = C.bg, BorderSizePixel = 0, ZIndex = 2 }, gui)
    corner(win, 10)
    st.win = win
    local uiScale = math.min(1, vp.X / 640, vp.Y / 480)
    if uiScale < 1 then
        local sc = Instance.new("UIScale")
        sc.Scale = uiScale
        sc.Parent = win
    end
    local titleBar = mk("Frame", { Name = "title", Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = C.panel, BorderSizePixel = 0, ZIndex = 3 }, win)
    corner(titleBar, 10)
    mk("TextLabel", { Size = UDim2.new(0, 340, 1, 0), Position = UDim2.new(0, 14, 0, 0), BackgroundTransparency = 1, Text = safeMode and "Blade Ball ツール v2（セーフモード）" or "Blade Ball ツール v2", TextColor3 = C.txt, Font = Enum.Font.BuilderSansBold, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 }, titleBar)
    local minBtn = mk("TextButton", { Size = UDim2.new(0, touch and 40 or 34, 0, touch and 40 or 34), Position = UDim2.new(1, -84, 0, 3), BackgroundColor3 = C.panel2, Text = "―", TextColor3 = C.txt, Font = Enum.Font.BuilderSansBold, TextSize = 14, BorderSizePixel = 0, ZIndex = 4 }, titleBar)
    corner(minBtn, 8)
    local closeBtn = mk("TextButton", { Size = UDim2.new(0, touch and 40 or 34, 0, touch and 40 or 34), Position = UDim2.new(1, -42, 0, 3), BackgroundColor3 = C.panel2, Text = "×", TextColor3 = C.txt, Font = Enum.Font.BuilderSansBold, TextSize = 15, BorderSizePixel = 0, ZIndex = 4 }, titleBar)
    corner(closeBtn, 8)
    bind(minBtn.Activated, function() win.Visible = false end)
    bind(closeBtn.Activated, function() win.Visible = false end)
    local statusBar = mk("Frame", { Name = "status", Size = UDim2.new(0, 540, 0, 26), Position = UDim2.new(0.5, 0, 0, 8), AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = C.bg, BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 2 }, gui)
    corner(statusBar, 8)
    st.statusLbl = mk("TextLabel", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "待機中", TextColor3 = C.txt, Font = Enum.Font.BuilderSans, TextSize = 13, ZIndex = 3 }, statusBar)
    local sidebar = mk("Frame", { Name = "side", Size = UDim2.new(0, 118, 1, -40), Position = UDim2.new(0, 0, 0, 40), BackgroundColor3 = C.panel, BorderSizePixel = 0, ZIndex = 3 }, win)
    local content = mk("Frame", { Name = "content", Size = UDim2.new(1, -126, 1, -48), Position = UDim2.new(0, 126, 0, 48), BackgroundTransparency = 1, ZIndex = 3 }, win)
    local pages = {}
    local tabBtns = {}
    local refreshers = {}
    local function showPage(name)
        for n, p in pairs(pages) do p.Visible = (n == name) end
        for n, b in pairs(tabBtns) do
            if n == name then
                b.BackgroundColor3 = C.white
                b.TextColor3 = C.black
            else
                b.BackgroundColor3 = C.panel2
                b.TextColor3 = C.txt
            end
        end
    end
    local tabNames = { "パリィ", "スパム", "表示", "その他" }
    for i, name in ipairs(tabNames) do
        local b = mk("TextButton", { Size = UDim2.new(0, 102, 0, 36), Position = UDim2.new(0, 8, 0, 8 + (i - 1) * 44), BackgroundColor3 = C.panel2, Text = name, TextColor3 = C.txt, Font = Enum.Font.BuilderSansBold, TextSize = 14, BorderSizePixel = 0, ZIndex = 4 }, sidebar)
        corner(b, 8)
        tabBtns[name] = b
        local page = mk("ScrollingFrame", { Name = "page_" .. name, Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, CanvasSize = UDim2.new(0, 0, 0, 1180), ZIndex = 3, Visible = false }, content)
        pages[name] = page
        bind(b.Activated, function() showPage(name) end)
    end
    local cursors = {}
    local function pageY(page)
        cursors[page] = (cursors[page] or 4)
        return cursors[page]
    end
    local function addToggle(page, label, get, set)
        local y = pageY(page)
        local row = mk("Frame", { Size = UDim2.new(0, 410, 0, 36), Position = UDim2.new(0, 2, 0, y), BackgroundTransparency = 1, ZIndex = 3 }, page)
        mk("TextLabel", { Size = UDim2.new(0, 320, 1, 0), BackgroundTransparency = 1, Text = label, TextColor3 = C.txt, Font = Enum.Font.BuilderSans, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 }, row)
        local btn = mk("TextButton", { Size = UDim2.new(0, 58, 0, 24), Position = UDim2.new(1, -60, 0, 6), Text = "", Font = Enum.Font.BuilderSansBold, TextSize = 12, BorderSizePixel = 0, ZIndex = 4 }, row)
        corner(btn, 7)
        local function refresh()
            if get() then
                btn.Text = "ON"
                btn.BackgroundColor3 = C.white
                btn.TextColor3 = C.black
            else
                btn.Text = "OFF"
                btn.BackgroundColor3 = C.panel2
                btn.TextColor3 = C.sub
            end
        end
        bind(btn.Activated, function()
            set(not get())
            refresh()
            save()
        end)
        refresh()
        table.insert(refreshers, refresh)
        cursors[page] = y + 38
        return refresh
    end
    local function addSlider(page, label, mn, mx, step, get, set, suffix)
        local y = pageY(page)
        local row = mk("Frame", { Size = UDim2.new(0, 410, 0, 46), Position = UDim2.new(0, 2, 0, y), BackgroundTransparency = 1, ZIndex = 3 }, page)
        mk("TextLabel", { Size = UDim2.new(0, 280, 0, 18), BackgroundTransparency = 1, Text = label, TextColor3 = C.txt, Font = Enum.Font.BuilderSans, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 }, row)
        local valLbl = mk("TextLabel", { Size = UDim2.new(0, 120, 0, 18), Position = UDim2.new(1, -122, 0, 0), BackgroundTransparency = 1, Text = "", TextColor3 = C.sub, Font = Enum.Font.BuilderSans, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 4 }, row)
        local bar = mk("TextButton", { Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 0, 26), BackgroundColor3 = C.panel2, Text = "", BorderSizePixel = 0, ZIndex = 4, AutoButtonColor = false }, row)
        corner(bar, 6)
        local fill = mk("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = C.white, BorderSizePixel = 0, ZIndex = 5 }, bar)
        corner(fill, 6)
        local function refresh()
            local v = get()
            local frac = clampN((v - mn) / (mx - mn), 0, 1)
            fill.Size = UDim2.new(frac, 0, 1, 0)
            valLbl.Text = tostring(math.floor(v + 0.5)) .. (suffix or "")
        end
        local dragging = false
        local function setFromX(x)
            local abs = bar.AbsoluteSize.X
            if abs <= 0 then return end
            local frac = clampN((x - bar.AbsolutePosition.X) / abs, 0, 1)
            local v = mn + frac * (mx - mn)
            v = math.floor(v / step + 0.5) * step
            set(clampN(v, mn, mx))
            refresh()
        end
        bind(bar.InputBegan, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                if input.Position then setFromX(input.Position.X) end
            end
        end)
        bind(uis.InputChanged, function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                if input.Position then setFromX(input.Position.X) end
            end
        end)
        bind(uis.InputEnded, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                if dragging then save() end
                dragging = false
            end
        end)
        refresh()
        table.insert(refreshers, refresh)
        cursors[page] = y + 48
        return refresh
    end
    local function addButton(page, label, fn)
        local y = pageY(page)
        local btn = mk("TextButton", { Size = UDim2.new(0, 220, 0, 32), Position = UDim2.new(0, 2, 0, y), BackgroundColor3 = C.panel2, Text = label, TextColor3 = C.txt, Font = Enum.Font.BuilderSansBold, TextSize = 13, BorderSizePixel = 0, ZIndex = 4 }, page)
        corner(btn, 8)
        bind(btn.Activated, fn)
        cursors[page] = y + 38
        return btn
    end
    local function addLabel(page, text, h)
        local y = pageY(page)
        mk("TextLabel", { Size = UDim2.new(0, 410, 0, h or 20), Position = UDim2.new(0, 2, 0, y), BackgroundTransparency = 1, Text = text, TextColor3 = C.sub, Font = Enum.Font.BuilderSans, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, ZIndex = 4 }, page)
        cursors[page] = y + (h or 20) + 4
    end

    local pParry = pages["パリィ"]
    addToggle(pParry, "自動パリィ", function() return cfg.parry.on end, function(v) cfg.parry.on = v end)
    addSlider(pParry, "反応時間", 80, 400, 5, function() return cfg.parry.react end, function(v) cfg.parry.react = v end, "ms")
    addSlider(pParry, "先行入力", 0, 80, 2, function() return cfg.parry.lead end, function(v) cfg.parry.lead = v end, "ms")
    addToggle(pParry, "ピング補正", function() return cfg.parry.pingOn end, function(v) cfg.parry.pingOn = v end)
    addSlider(pParry, "ピング係数", 0, 150, 5, function() return cfg.parry.pingPct end, function(v) cfg.parry.pingPct = v end, "%")
    addSlider(pParry, "パリィ半径", 70, 150, 5, function() return cfg.parry.radiusPct end, function(v) cfg.parry.radiusPct = v end, "%")
    addSlider(pParry, "即パリィ距離", 6, 30, 1, function() return cfg.parry.immediate end, function(v) cfg.parry.immediate = v end, "")
    addToggle(pParry, "見逃し判定（外れる弾は無視）", function() return cfg.parry.missOn end, function(v) cfg.parry.missOn = v end)
    addSlider(pParry, "許容ずれ", 4, 25, 1, function() return cfg.parry.missTol end, function(v) cfg.parry.missTol = v end, "")
    addToggle(pParry, "向き判定（補助）", function() return cfg.parry.heading end, function(v) cfg.parry.heading = v end)
    addToggle(pParry, "カーブ対応", function() return cfg.parry.curve end, function(v) cfg.parry.curve = v end)
    addToggle(pParry, "自動アビリティ", function() return cfg.abil.on end, function(v) cfg.abil.on = v end)
    addSlider(pParry, "アビリティ到達", 60, 300, 5, function() return cfg.abil.eta end, function(v) cfg.abil.eta = v end, "ms")
    addSlider(pParry, "アビリティ間隔", 3, 15, 1, function() return cfg.abil.cd end, function(v) cfg.abil.cd = v end, "秒")
    addLabel(pParry, "プリセット", 18)
    addButton(pParry, "競技（反応150ms）", function()
        cfg.parry.react = 150 cfg.parry.lead = 0 cfg.parry.pingPct = 100 cfg.parry.radiusPct = 100
        for _, r in ipairs(refreshers) do pcall(r) end
        save()
    end)
    addButton(pParry, "標準（反応210ms）", function()
        cfg.parry.react = 210 cfg.parry.lead = 10 cfg.parry.pingPct = 85 cfg.parry.radiusPct = 100
        for _, r in ipairs(refreshers) do pcall(r) end
        save()
    end)
    addButton(pParry, "安全（反応280ms）", function()
        cfg.parry.react = 280 cfg.parry.lead = 30 cfg.parry.pingPct = 90 cfg.parry.radiusPct = 115
        for _, r in ipairs(refreshers) do pcall(r) end
        save()
    end)
    addLabel(pParry, "操作： Q長押し＝スパム / T＝パリィ / E＝アビリティ / 右Shift＝GUI表示切替。成功・死亡はステータス表示で確認できる。", 32)

    local pSpam = pages["スパム"]
    addToggle(pSpam, "自動スパム", function() return cfg.spam.on end, function(v) cfg.spam.on = v end)
    addSlider(pSpam, "スパム開始距離", 12, 60, 1, function() return cfg.spam.dist end, function(v) cfg.spam.dist = v end, "")
    addSlider(pSpam, "敵接近距離", 8, 40, 1, function() return cfg.spam.enemyDist end, function(v) cfg.spam.enemyDist = v end, "")
    addSlider(pSpam, "スパム間隔", 25, 120, 5, function() return cfg.spam.interval end, function(v) cfg.spam.interval = v end, "ms")
    addToggle(pSpam, "高速ボール時スパム", function() return cfg.spam.fast end, function(v) cfg.spam.fast = v end)
    addSlider(pSpam, "高速しきい値", 120, 400, 10, function() return cfg.spam.fastSpeed end, function(v) cfg.spam.fastSpeed = v end, "")
    st.spamToggleBtn = addButton(pSpam, "手動スパム： OFF", function()
        st.manualSpam = not st.manualSpam
    end)
    addLabel(pSpam, "打ち合い（敵が自分 or ボールに近い）・高速ボール・至近の再接近では自動連打。間隔はボール速度で自動短縮される。スマホは浮動ボタンの長押しでもスパムできる。", 44)

    local pVis = pages["表示"]
    addToggle(pVis, "ボール強調", function() return cfg.vis.hl end, function(v) cfg.vis.hl = v end)
    addToggle(pVis, "ボール情報", function() return cfg.vis.info end, function(v) cfg.vis.info = v end)
    addToggle(pVis, "標的ライン", function() return cfg.vis.line end, function(v) cfg.vis.line = v end)
    addToggle(pVis, "パリィ範囲", function() return cfg.vis.ring end, function(v) cfg.vis.ring = v end)
    addToggle(pVis, "ステータス表示", function() return cfg.vis.status end, function(v) cfg.vis.status = v end)
    addToggle(pVis, "ヒットサウンド", function() return cfg.vis.snd end, function(v) cfg.vis.snd = v end)
    addLabel(pVis, "強調色： 赤＝自分が標的 / 橙＝他人が標的 / 白＝未確定。パリィ範囲は現在の速度から決まる判定半径そのもの。", 32)

    local pMisc = pages["その他"]
    local floatsRefresh = nil
    addToggle(pMisc, "浮動ボタン", function() return cfg.misc.floats end, function(v) cfg.misc.floats = v if floatsRefresh then floatsRefresh() end end)
    addToggle(pMisc, "軽量モード", function() return cfg.misc.light end, function(v) cfg.misc.light = v end)
    addToggle(pMisc, "自動調整（死亡で反応↑）", function() return cfg.misc.autotune end, function(v) cfg.misc.autotune = v end)
    addToggle(pMisc, "AFK防止", function() return cfg.misc.afk end, function(v) cfg.misc.afk = v end)
    addToggle(pMisc, "FPSブースト（影OFF）", function() return cfg.misc.fpsb end, function(v) cfg.misc.fpsb = v applyFpsb() end)
    addButton(pMisc, "設定リセット", function()
        pcall(function() if delfile then delfile(cfFile) end end)
        cfg.parry.react = 210 cfg.parry.lead = 10 cfg.parry.pingOn = true cfg.parry.pingPct = 85 cfg.parry.immediate = 15
        cfg.parry.missOn = true cfg.parry.missTol = 13 cfg.parry.heading = true cfg.parry.curve = true cfg.parry.on = true cfg.parry.radiusPct = 100
        cfg.spam.on = true cfg.spam.dist = 30 cfg.spam.enemyDist = 20 cfg.spam.interval = 50 cfg.spam.fast = true cfg.spam.fastSpeed = 220
        cfg.abil.on = false cfg.abil.eta = 140 cfg.abil.cd = 6
        cfg.vis.hl = true cfg.vis.info = true cfg.vis.line = false cfg.vis.ring = false cfg.vis.status = true cfg.vis.snd = false
        cfg.misc.afk = false cfg.misc.fpsb = false cfg.misc.autotune = false applyFpsb()
        for _, r in ipairs(refreshers) do pcall(r) end
        save()
    end)
    addLabel(pMisc, "セーフモード： 起動完了前に落ちた場合、次回は自動パリィOFFで起動する（設定で戻せる）。軽量モードはスマホ推奨（描画と走査を間引く）。", 44)
    addButton(pMisc, "スクリプト終了", function() cleanup() end)

    local floats = mk("Frame", { Name = "floats", Size = UDim2.new(0, 72, 0, 278), Position = UDim2.new(1, -84, 0.5, -139), BackgroundTransparency = 1, ZIndex = 2 }, gui)
    st.floatsFrame = floats
    local function floatBtn(y, text)
        local b = mk("TextButton", { Size = UDim2.new(0, 72, 0, 50), Position = UDim2.new(0, 0, 0, y), BackgroundColor3 = C.panel, BackgroundTransparency = 0.15, Text = text, TextColor3 = C.txt, Font = Enum.Font.BuilderSansBold, TextSize = 14, BorderSizePixel = 0, ZIndex = 3 }, floats)
        corner(b, 10)
        return b
    end
    local fAuto = floatBtn(0, "自動ON")
    local fSpam = floatBtn(57, "スパム")
    local fParry = floatBtn(114, "パリィ")
    local fAbil = floatBtn(171, "アビ")
    local fGui = floatBtn(228, "表示")
    st.spamBtn = fSpam
    st.autoBtn = fAuto
    floatsRefresh = function() floats.Visible = cfg.misc.floats or st.touchSeen end
    floatsRefresh()
    bind(fAuto.Activated, function()
        cfg.parry.on = not cfg.parry.on
        for _, r in ipairs(refreshers) do pcall(r) end
        save()
    end)
    bind(fSpam.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            st.manualSpam = true
        end
    end)
    bind(fSpam.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            st.manualSpam = false
        end
    end)
    bind(fParry.Activated, function() doParry("manual", nil) end)
    bind(fAbil.Activated, function()
        local now = tick()
        if now - st.lastAbil >= 1 then
            if doAbility() then st.lastAbil = now end
        end
    end)
    bind(fGui.Activated, function() win.Visible = not win.Visible end)

    local draggingWin = false
    local dragStart = nil
    local winStart = nil
    bind(titleBar.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingWin = true
            dragStart = input.Position
            winStart = win.Position
        end
    end)
    bind(uis.InputChanged, function(input)
        if draggingWin and dragStart and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local dx = input.Position.X - dragStart.X
            local dy = input.Position.Y - dragStart.Y
            win.Position = UDim2.new(winStart.X.Scale, winStart.X.Offset + dx, winStart.Y.Scale, winStart.Y.Offset + dy)
        end
    end)
    bind(uis.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingWin = false
        end
    end)
    showPage("パリィ")
end
task.defer(buildGui)
