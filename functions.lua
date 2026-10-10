local jobMap = {
    ADV = 0, GLD = 1, PGL = 2, MRD = 3, LNC = 4, ARC = 5, CNJ = 6, THM = 7, CRP = 8, BSM = 9,
    ARM = 10, GSM = 11, LTW = 12, WVR = 13, ALC = 14, CUL = 15, MIN = 16, BTN = 17, FSH = 18,
    PLD = 19, MNK = 20, WAR = 21, DRG = 22, BRD = 23, WHM = 24, BLM = 25, ACN = 26, SMN = 27,
    SCH = 28, ROG = 29, NIN = 30, MCH = 31, DRK = 32, AST = 33, SAM = 34, RDM = 35, BLU = 36,
    GNB = 37, DNC = 38, RPR = 39, SGE = 40, VPR = 41, PCT = 42
  }
  
  local roleMap = {
    DPS = { "MNK", "DRG", "NIN", "SAM", "RPR", "VPR", "MCH", "BRD", "DNC", "BLM", "RDM", "SMN", "PCT", "BLU" },
    Melee = { "MNK", "DRG", "NIN", "SAM", "RPR", "VPR" },
    Caster = { "BLM", "SMN", "RDM", "BLU", "PCT" },
    Ranged = { "BRD", "MCH", "DNC" },
    Tank = { "PLD", "WAR", "DRK", "GNB" },
    Healer = { "WHM", "SCH", "AST", "SGE" },
    Regen = { "WHM", "AST" },
    Shield = { "SCH", "AST" },
    Support = { "PLD", "WAR", "DRK", "GNB", "WHM", "SCH", "AST", "SGE" },
    MeleeRange = { "MNK", "DRG", "NIN", "SAM", "RPR", "VPR", "PLD", "WAR", "DRK", "GNB" },
    CasterRange = { "MCH", "BRD", "DNC", "BLM", "RDM", "SMN", "PCT", "BLU", "WHM", "SCH", "AST", "SGE" },
    DoTBL = { "MNK", "DRG", "SAM", "BRD", "WHM", "SCH", "AST", "SGE" }
  }
  
  local function getJob(ent)
    if ent and TensorCore then
      local entity = TensorCore.mGetEntity(ent)
      if entity then return entity.job end
    end
    return Player and Player.job or 0
  end
  
  for jobName, jobId in pairs(jobMap) do
    FightPlan["is" .. jobName] = function(ent) return getJob(ent) == jobId end
  end
  
  for roleName, jobList in pairs(roleMap) do
    FightPlan["is" .. roleName] = function(ent)
      ent = ent or Player.id
      for _, jobName in ipairs(jobList) do
        if FightPlan["is" .. jobName](ent) then return true end
      end
      return false
    end
  end
  
  FightPlan.hasDoTBL = function(ent)
    ent = ent or Player.id
    for _, jobName in ipairs(roleMap.DoTBL) do
      if FightPlan["is" .. jobName](ent) then return true end
    end
    return false
  end
  
  FightPlan.has2mPot = function()
    if not Player or not In then return false end
    return In(Player.job, 20, 21, 22, 23, 24, 30, 31, 32, 34, 35, 37, 38, 39, 41)
  end

  FightPlan.isMT = function()
    if not TensorCore or not gACRSelectedProfiles then return false end
    local p = TensorCore.mGetPlayer()
    if not p then return false end
    local profile = gACRSelectedProfiles[p.job]
    if not profile then return false end
    return _G["ACR_" .. profile .. "_TankStance"] == "mt"
  end

  FightPlan.isOT = function()
    if not TensorCore or not gACRSelectedProfiles then return false end
    local p = TensorCore.mGetPlayer()
    if not p then return false end
    local profile = gACRSelectedProfiles[p.job]
    if not profile then return false end
    return _G["ACR_" .. profile .. "_TankStance"] == "ot"
  end
  
  FightPlan.potCD = function()
    if not ActionList then return 0 end
    local pot = ActionList:Get(1, 846)
    return pot and math.floor((pot.cdmax - pot.cd) * 1000) or 0
  end
  
  FightPlan.assistOn = function()
    if not FFXIV_Common_BotRunning and ml_global_information then
      ml_global_information.ToggleRun()
      d("[FightPlan] Assist On")
    end
  end

  FightPlan.assistOff = function()
    if FFXIV_Common_BotRunning and ml_global_information then
      ml_global_information.ToggleRun()
      d("[FightPlan] Assist Off")
    end
  end
  
  local function toggleVar(prefix, varname, state)
    if not varname then
      d("[FightPlan." .. prefix .. "] Error: Variable is nil. Use quotes around the variable name. Example: FightPlan." .. prefix .. "(\"Burn\", true)")
      return
    end
    local player = TensorCore.mGetPlayer()
    if not player then
      d("[FightPlan." .. prefix .. "] Error: player is nil")
      return
    end
    local currentACR = gACRSelectedProfiles[player.job]
    if not currentACR then
      d("[FightPlan." .. prefix .. "] Error: no ACR profile selected")
      return
    end
    local varPath = "ACR_" .. currentACR .. "_" .. prefix .. "_" .. varname
    _G[varPath] = state
    d("[FightPlan." .. prefix .. "] Set " .. varPath .. " to " .. tostring(state))
  end
  
  FightPlan.qt = function(varname, state) toggleVar("", varname, state) end
  FightPlan.hb = function(varname, state) toggleVar("Hotbar", varname, state) end
  FightPlan.tb = function(varname, state) toggleVar("Tankbar", varname, state) end
  FightPlan.hl = function(varname, state) toggleVar("Healbar", varname, state) end

-- Caller-driven: evaluate once per call; never interrupt a friendly target.
local function hpSwap(targets, gap, contentIds)
    local function check(condition, message)
        assert(condition, "[FightPlan.hpSwap] " .. message)
    end
    local function number(value)
        return type(value) == "number" and value == value and value > -math.huge and value < math.huge
    end
    local function id(value, label)
        check(number(value) and value > 0 and value % 1 == 0, label .. " must be a positive integer; got " .. tostring(value))
        return value
    end
    check(type(targets) == "table", "targets must be a list of numeric IDs")
    check(contentIds == nil or type(contentIds) == "boolean", "contentIds must be true or false; got " .. tostring(contentIds))
    gap = gap == nil and 2 or gap
    check(number(gap) and gap >= 0 and gap <= 100, "gap must be between 0 and 100; got " .. tostring(gap))
    local ids = {}
    for index, value in pairs(targets) do
        check(number(index) and index > 0 and index % 1 == 0, "targets must use positive integer indices")
        ids[id(value, "targets[" .. index .. "]")] = true
    end
    check(type(TensorCore) == "table", "TensorCore is unavailable")
    for _, api in ipairs({"mGetPlayer", "mGetTarget", contentIds and "entityList" or "mGetEntity"}) do
        check(type(TensorCore[api]) == "function", "TensorCore." .. api .. " is unavailable")
    end
    local player = TensorCore.mGetPlayer()
    check(type(player) == "table", "TensorCore.mGetPlayer returned " .. type(player))
    local current = TensorCore.mGetTarget()
    if current then
        check(type(current.friendly) == "boolean", "invalid friendly flag for current target=" .. tostring(current.id))
        if current.friendly then return nil, false end
    end
    local range = ml_global_information and ml_global_information.AttackRange
    check(number(range) and range >= 0, "Minion AttackRange is unavailable/invalid; job=" .. tostring(player.job) .. " range=" .. tostring(range))
    local candidates = {}
    local function add(entity)
        if entity == nil then return end -- Normal: absent/despawned entity ID.
        check(type(entity) == "table", "TensorCore returned invalid entity type " .. type(entity))
        for _, field in ipairs({"alive", "attackable", "targetable"}) do
            check(type(entity[field]) == "boolean", "invalid " .. field .. " for entity=" .. tostring(entity.id))
        end
        if not entity.alive or not entity.attackable or not entity.targetable then return end
        local entityId = id(entity.id, "entity.id")
        local hp = entity.hp and entity.hp.percent
        check(number(hp) and hp >= 0 and hp <= 100, "invalid HP for entity=" .. entityId .. " hp=" .. tostring(hp))
        if hp == 0 then return end
        check(number(entity.distance2d), "invalid distance2d for entity=" .. entityId .. " distance=" .. tostring(entity.distance2d))
        candidates[entityId] = {id=entityId, hp=hp, inRange=entity.distance2d <= range}
    end
    for targetId in pairs(ids) do
        if contentIds then
            local entities = TensorCore.entityList("contentid=" .. targetId .. ",attackable,alive,targetable")
            check(type(entities) == "table", "TensorCore.entityList returned " .. type(entities) .. " for contentId=" .. targetId)
            for _, entity in pairs(entities) do add(entity) end
        else
            add(TensorCore.mGetEntity(targetId))
        end
    end
    local best, hasInRange
    for _, candidate in pairs(candidates) do
        if not best or (candidate.inRange and not best.inRange)
            or (candidate.inRange == best.inRange and (candidate.hp > best.hp
                or (candidate.hp == best.hp and candidate.id < best.id))) then
            best = candidate
        end
        hasInRange = hasInRange or candidate.inRange
    end
    if not best then return nil, false end
    local previous = current and candidates[current.id]
    if hasInRange and previous and previous.inRange and best.id ~= previous.id
        and (best.hp <= previous.hp or best.hp - previous.hp < gap) then
        best = previous
    end
    if current and current.id == best.id then return best.id, false end
    check(type(player.SetTarget) == "function", "TensorCore.mGetPlayer():SetTarget is unavailable")
    local result = player:SetTarget(best.id)
    check(result ~= false, "TensorCore.mGetPlayer():SetTarget returned false; target=" .. best.id .. " job=" .. tostring(player.job))
    return best.id, true -- A targeting request, not a claim of asynchronous completion.
end

function FightPlan.hpSwap(targets, gap, contentIds)
    local ok, selectedId, requested = xpcall(function() return hpSwap(targets, gap, contentIds) end, function(reason)
        local message = "[FightPlan.hpSwap] " .. tostring(reason)
        return debug and debug.traceback and debug.traceback(message, 2) or message
    end)
    if not ok then error(selectedId, 0) end
    return selectedId, requested
end

local worldTextPosition = {x = 0, y = 0, z = 0}

-- immediate label for one frame: call every frame from OnDraw.
local function drawWorldText(text, position, color, background, sizeMul, style, fontId)
    if not position then
        local pos = TensorCore.mGetPlayer().pos
        worldTextPosition.x, worldTextPosition.y, worldTextPosition.z = pos.x, pos.y + 0.5, pos.z
        position = worldTextPosition
    end
    if not Fonter.fonts[fontId or "default"] then
        d("[FightPlan] WorldText ERROR: font unavailable: " .. (fontId or "default"))
        return false
    end
    Fonter.beginESPOverlay()
    local ok, err = pcall(Fonter.renderWorldText, text, position, color, background, sizeMul, style, fontId)
    Fonter.endESPOverlay()
    if not ok then
        d("[FightPlan] WorldText ERROR: " .. tostring(err))
        return false
    end
    return true
end

-- timed world texts and countdowns: started once, drawn by FightPlan every
-- frame until their time runs out or ClearWorldText removes them.
local timedTexts, lastHandle = {}, 0
local timedPosition = {x = 0, y = 0, z = 0}

local function addTimed(api, ms, text, position, color, background, sizeMul, style, fontId, countdown)
    local problem
    if type(ms) ~= "number" or ms ~= ms or ms <= 0 or ms == math.huge then
        problem = "ms must be a positive number of milliseconds, got " .. tostring(ms)
    elseif countdown and (type(text) ~= "string" or not pcall(string.format, text, 1)) then
        problem = "text must be a format with one number such as \"%.1f\", got " .. tostring(text)
    elseif not countdown and type(text) ~= "string" and type(text) ~= "number" then
        problem = "text must be a string, got " .. type(text)
    elseif type(position) == "table" then
        if type(position.x) ~= "number" or type(position.y) ~= "number" or type(position.z) ~= "number" then
            problem = "position table needs numeric x, y and z (pass entity.pos or the entity id, not the entity)"
        end
    elseif type(position) ~= "number" then
        problem = "position is required: {x, y, z} or an entity id (TensorCore.mGetPlayer().id for the player), got " .. type(position)
    end
    if problem then
        d("[FightPlan] " .. api .. " ERROR: " .. problem)
        return nil
    end
    lastHandle = lastHandle + 1
    timedTexts[lastHandle] = {
        endsAt = Now() + ms, text = countdown and text or tostring(text), countdown = countdown,
        whole = countdown and text:find("%%[-+ #0]*%d*[di]") ~= nil,
        position = position, color = color, background = background,
        sizeMul = sizeMul, style = style, fontId = fontId,
    }
    return lastHandle
end

-- WorldText(ms, text, position, color?, background?, sizeMul?, style?, fontId?)
--   timed: call once; shows for ms milliseconds and returns an id for
--   ClearWorldText (nil after a reported invalid argument). position is
--   required: an entity id follows that entity at Y + 0.5 (ends when it
--   disappears; TensorCore.mGetPlayer().id for the player) or a fixed {x, y, z}.
-- WorldText(text, position?, ...) without a duration is the immediate form:
--   call it every frame from OnDraw; returns false after a reported failure.
function FightPlan.WorldText(ms, ...)
    if type(ms) == "number" then
        local text, position, color, background, sizeMul, style, fontId = ...
        return addTimed("WorldText", ms, text, position, color, background, sizeMul, style, fontId, false)
    end
    return drawWorldText(ms, ...)
end

-- WorldCountdown(ms, text, position, color?, background?, sizeMul?, style?, fontId?)
-- like timed WorldText, but text is a format with one number, the seconds
-- left: "%.1f" (default) counts 10.0, 9.9 ...; "%d" whole seconds 10 ... 1.
function FightPlan.WorldCountdown(ms, text, position, color, background, sizeMul, style, fontId)
    return addTimed("WorldCountdown", ms, text or "%.1f", position, color, background, sizeMul, style, fontId, true)
end

-- remove one timed text or countdown by the id it returned. true if it was
-- still showing; false is normal (expired, already cleared, or nil id).
function FightPlan.ClearWorldText(id)
    if id == nil or timedTexts[id] == nil then return false end
    timedTexts[id] = nil
    return true
end

-- remove every timed text and countdown; returns how many were showing.
function FightPlan.ClearAllWorldText()
    local count = 0
    for id in pairs(timedTexts) do
        timedTexts[id] = nil
        count = count + 1
    end
    return count
end

local function drawTimedTexts()
    if next(timedTexts) == nil then return end
    local now = Now()
    for id, t in pairs(timedTexts) do
        local remaining = (t.endsAt - now) / 1000
        local position = t.position
        if type(position) == "number" then
            local entity = TensorCore.mGetEntity(position)
            if entity then
                local pos = entity.pos
                timedPosition.x, timedPosition.y, timedPosition.z = pos.x, pos.y + 0.5, pos.z
                position = timedPosition
            else
                remaining = 0 -- entity gone (died or despawned): its text ends with it
            end
        end
        if remaining <= 0 then
            timedTexts[id] = nil
        else
            local text = t.text
            if t.countdown then text = string.format(text, t.whole and math.ceil(remaining) or remaining) end
            if not drawWorldText(text, position, t.color, t.background, t.sizeMul, t.style, t.fontId) then
                timedTexts[id] = nil -- drawWorldText printed why; stop instead of repeating it every frame
            end
        end
    end
end
RegisterEventHandler("Gameloop.Draw", drawTimedTexts, "FightPlan.TimedWorldText")

-- AutoMove: one native auto-follow driver for every reaction. A move is a
-- smooth curve sampled into points ~1 yalm apart; the driver steers at the
-- next point ahead (re-asserted every 100 ms). Starting a move replaces the
-- current one; it ends on arrival, timeout (error), the TensorDrift drift-off
-- key, death, zone change, StopMove or StopMovement.
local move, lastMovePush = nil, 0
local MOVE_STEP, MOVE_LOOKAHEAD = 1, 1.5

local function distance2d(a, b)
    local dx, dz = a.x - b.x, a.z - b.z
    return math.sqrt(dx * dx + dz * dz)
end

-- random point within radius of p (uniform over the disc)
local function scatter(p, radius)
    if radius <= 0 then return {x = p.x, y = p.y, z = p.z} end
    local r, a = radius * math.sqrt(math.random()), math.random() * 2 * math.pi
    return {x = p.x + r * math.cos(a), y = p.y, z = p.z + r * math.sin(a)}
end

-- centripetal catmull-rom through every control point (no loops or cusps on
-- uneven spacing), sampled every MOVE_STEP yalms; the first point is excluded.
local function sampleCurve(points)
    local samples, n = {}, #points
    for i = 1, n - 1 do
        local p0, p1, p2, p3 = points[math.max(i - 1, 1)], points[i], points[i + 1], points[math.min(i + 2, n)]
        local function knot(t, a, b) return t + math.max(distance2d(a, b), 0.01) ^ 0.5 end
        local t0 = 0
        local t1 = knot(t0, p0, p1)
        local t2 = knot(t1, p1, p2)
        local t3 = knot(t2, p2, p3)
        local steps = math.max(1, math.ceil(distance2d(p1, p2) / MOVE_STEP))
        for s = 1, steps do
            local t = t1 + (t2 - t1) * s / steps
            local function lerp(a, b, ta, tb)
                local w = (t - ta) / (tb - ta)
                return {x = a.x + (b.x - a.x) * w, z = a.z + (b.z - a.z) * w}
            end
            local a1, a2, a3 = lerp(p0, p1, t0, t1), lerp(p1, p2, t1, t2), lerp(p2, p3, t2, t3)
            local b1, b2 = lerp(a1, a2, t0, t2), lerp(a2, a3, t1, t3)
            local c = lerp(b1, b2, t1, t2)
            samples[#samples + 1] = {x = c.x, y = p2.y, z = c.z}
        end
    end
    samples[#samples] = points[n] -- land exactly on the goal
    return samples
end

-- hard also stops the character (arrival/timeout); a drift-off or death
-- release only lets go of auto-follow so the player keeps control.
local function endMove(hard)
    local ended = move
    move = nil
    local player = TensorCore.mGetPlayer()
    if player then
        player:SetAutoFollowOn(false)
        if hard then player:Stop() end
    end
    return ended
end

local function isNumber(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function badPosition(value)
    return type(value) ~= "table" or not isNumber(value.x) or not isNumber(value.z) or (value.y ~= nil and not isNumber(value.y))
end

-- returns true when started, false when every candidate is in an AoE, or
-- nil plus a problem message for an invalid call or missing dependency.
local function startMove(name, target, opts, asPath)
    if type(name) ~= "string" or name == "" then return nil, "name must be a non-empty string; got " .. tostring(name) end
    if type(target) ~= "table" then return nil, "target must be {x, y, z} or a list of them; got " .. type(target) end
    if opts ~= nil and type(opts) ~= "table" then return nil, "opts must be a table; got " .. type(opts) end
    opts = opts or {}
    local tolerance, humanize = opts.tolerance or 0.2, opts.humanize or 0.1
    local delay, spread = opts.delay or 150, opts.spread or 0
    if not isNumber(tolerance) or tolerance <= 0 then return nil, "tolerance must be > 0 yalms; got " .. tostring(tolerance) end
    if not isNumber(humanize) or humanize < 0 or humanize > 0.5 then return nil, "humanize must be 0..0.5; got " .. tostring(humanize) end
    if not isNumber(delay) or delay < 0 then return nil, "delay must be >= 0 ms; got " .. tostring(delay) end
    if not isNumber(spread) or spread < 0 then return nil, "spread must be >= 0 yalms; got " .. tostring(spread) end
    if opts.timeout ~= nil and (not isNumber(opts.timeout) or opts.timeout <= 0) then return nil, "timeout must be > 0 ms; got " .. tostring(opts.timeout) end
    if type(TensorCore) ~= "table" or type(TensorCore.mGetPlayer) ~= "function" then return nil, "TensorCore.mGetPlayer is unavailable" end
    local player = TensorCore.mGetPlayer()
    if type(player) ~= "table" or type(player.pos) ~= "table" then return nil, "TensorCore.mGetPlayer returned no player" end
    local from = player.pos
    local points
    if asPath then
        if target[1] == nil then return nil, "path needs a list of points {{x, z}, ...}" end
        points = target
    elseif target[1] ~= nil then
        local inAnyAOE = TensorCore.Avoidance and TensorCore.Avoidance.inAnyAOE
        if type(inAnyAOE) ~= "function" then return nil, "TensorCore.Avoidance.inAnyAOE is unavailable" end
        local best, bestDistance
        for i, candidate in ipairs(target) do
            if badPosition(candidate) then return nil, "target[" .. i .. "] needs numeric x and z (y optional)" end
            local inAoe = inAnyAOE(candidate.x, candidate.y or from.y, candidate.z)
            if type(inAoe) ~= "boolean" then return nil, "TensorCore.Avoidance.inAnyAOE returned " .. tostring(inAoe) .. " (AoE data unavailable) for target[" .. i .. "]" end
            local distance = distance2d(from, candidate)
            if not inAoe and (not best or distance < bestDistance) then best, bestDistance = candidate, distance end
        end
        if not best then return false end -- Normal: every candidate is inside an AoE right now.
        points = {best}
    else
        points = {target}
    end
    for i, point in ipairs(points) do
        if badPosition(point) then return nil, (asPath and "path[" .. i .. "]" or "target") .. " needs numeric x and z (y optional)" end
    end
    local goal = points[#points]
    -- a looping reaction re-calling the same move must not re-roll its path every tick
    if move and move.name == name and move.key == goal.x .. "," .. goal.z .. "," .. #points then return true end
    local control = {{x = from.x, y = from.y, z = from.z}}
    for _, point in ipairs(points) do
        control[#control + 1] = scatter({x = point.x, y = point.y or from.y, z = point.z}, spread)
    end
    local first = control[2]
    local distance = distance2d(from, first)
    if humanize > 0 and distance > 3 then
        -- bend the first leg through an off-line point: random side, depth and spot along it
        local dx, dz = (first.x - from.x) / distance, (first.z - from.z) / distance
        local along = distance * (0.35 + math.random() * 0.3)
        local side = distance * humanize * (0.5 + math.random() * 0.5) * (math.random() < 0.5 and -1 or 1)
        table.insert(control, 2, {x = from.x + dx * along - dz * side, y = first.y, z = from.z + dz * along + dx * side})
    end
    local path = sampleCurve(control)
    local length, previous = 0, from
    for _, point in ipairs(path) do length = length + distance2d(previous, point); previous = point end
    local startAt = Now() + math.random(0, math.floor(delay))
    move = {name = name, key = goal.x .. "," .. goal.z .. "," .. #points, path = path, goal = path[#path],
        tolerance = tolerance, startAt = startAt, mapId = Player.localmapid, draw = opts.draw ~= false,
        expires = startAt + (opts.timeout or 3000 + length * 300)} -- default allows >= ~3.5 yalms/s
    return true
end

local function updateMove()
    if not move then return end
    local player = TensorCore.mGetPlayer()
    if not player or Player.localmapid ~= move.mapId then move = nil return end -- Normal: zoning/loading.
    if TensorDrift_SlidecastDisableHold == true or player.hp.current <= 0 then endMove(false) return end
    local now, pos, path = Now(), player.pos, move.path
    -- steer at the next point at least MOVE_LOOKAHEAD ahead; skip points already passed
    while #path > 1 and (distance2d(pos, path[1]) <= MOVE_LOOKAHEAD or distance2d(pos, path[2]) <= distance2d(pos, path[1])) do
        table.remove(path, 1)
    end
    local distance = distance2d(pos, move.goal)
    if #path == 1 and distance <= move.tolerance then endMove(true) return end
    if now >= move.expires then
        local ended = endMove(true)
        d(string.format("[FightPlan] MoveTo ERROR: %q timed out %.2f yalms short of (%.2f, %.2f)",
            ended.name, distance, ended.goal.x, ended.goal.z))
        return
    end
    if now < move.startAt or now - lastMovePush < 100 then return end
    lastMovePush = now
    local point = path[1]
    player:SetAutoFollowPos(point.x, point.y, point.z)
    player:SetAutoFollowOn(true)
end

RegisterEventHandler("Gameloop.Update", function()
    local ok, err = xpcall(updateMove, function(reason)
        local message = tostring(reason)
        return debug and debug.traceback and debug.traceback(message, 2) or message
    end)
    if ok then return end
    local name = move and move.name
    move = nil -- never leave a failed move driving the character
    d("[FightPlan] MoveTo ERROR: driver failed for move " .. tostring(name) .. "; releasing auto-follow\n" .. tostring(err))
    local released, releaseErr = pcall(function() TensorCore.mGetPlayer():SetAutoFollowOn(false) end)
    if not released then d("[FightPlan] MoveTo ERROR: could not release auto-follow: " .. tostring(releaseErr)) end
end, "FightPlan.MoveDriver")

RegisterEventHandler("Gameloop.Draw", function()
    if not move or not move.draw or type(fpMove) ~= "table" then return end -- fp drawers report their own absence
    local player = TensorCore.mGetPlayer()
    if not player then return end
    local from = player.pos
    for _, point in ipairs(move.path) do
        fpMove:addLine(from.x, from.y, from.z, point.x, point.y, point.z)
        from = point
    end
    fpMove:addCircle(move.goal.x, move.goal.y, move.goal.z, math.max(move.tolerance, 0.3))
end, "FightPlan.MoveDraw")

local function reportMove(api, ok, problem)
    if ok == nil then d("[FightPlan] " .. api .. " ERROR: " .. tostring(problem)) end
    return ok
end

-- MoveTo(name, target, opts?) -> true when moving, false when every candidate
-- is in an AoE (normal; call again), nil after printing an invalid call.
-- target is {x, y?, z} or a list of candidates (the closest outside every AoE).
-- opts: tolerance (0.2 yalms), spread (0: land randomly within this many yalms
-- of the spot), humanize (0.1: bend the approach by up to 10% of the distance,
-- 0 = straight), delay (150: random 0-150 ms start), timeout (3000 ms + 300 per
-- yalm of path, then an error), draw (true). Same name and target again: no-op.
function FightPlan.MoveTo(name, target, opts)
    return reportMove("MoveTo", startMove(name, target, opts, false))
end

-- MovePath(name, points, opts?) runs one smooth curve through every point in
-- order and stops on the last; same opts as MoveTo (spread jitters every point).
function FightPlan.MovePath(name, points, opts)
    return reportMove("MovePath", startMove(name, points, opts, true))
end

-- stop the named move; false is normal (not that move, or already finished).
function FightPlan.StopMove(name)
    if not move or move.name ~= name then return false end
    endMove(false)
    return true
end

-- stop every movement: the current FightPlan move and any auto-follow left
-- on by older reactions. true if a FightPlan move was active.
function FightPlan.StopMovement()
    local wasMoving = move ~= nil
    move = nil
    local player = TensorCore.mGetPlayer()
    if player then
        player:SetAutoFollowOn(false)
        player:Stop()
    end
    return wasMoving
end

-- true while a move (or the named move) is in progress.
function FightPlan.IsMoving(name)
    return move ~= nil and (name == nil or move.name == name)
end
