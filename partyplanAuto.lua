-- Read-only chat monitoring. Registered from module code, never a bridge script.
local seen, listening, lastPoll = {}, false, 0
local function fail(message)
    d("[PartyPlan.AutoDetection] " .. message)
    PartyPlan.autoDetectionFault = message
    listening = false
    return false
end
function PartyPlan.ParseRoleCallout(text)
    if type(text) ~= "string" then return nil end
    local found
    for word in text:upper():gmatch("[%w]+") do
        if word == "MT" or word == "OT" or word:match("^[HMR][12]$") then
            if found and found ~= word then return nil end -- Ambiguous discussion, not a claim.
            found = word
        end
    end
    return found
end
function PartyPlan.ApplyRoleCallout(name, text)
    local role = PartyPlan.ParseRoleCallout(text)
    if not role then return false end
    local member
    for _, m in ipairs(PartyPlan.partyList or {}) do if m.name == name then member = m; break end end
    if not member or member.dummy or member.roleSource == "manual" or member.roleSource == "chat" then return false end
    local other = PartyPlan.GetMember(role)
    if other and other ~= member and (other.roleSource == "manual" or other.roleSource == "chat") then
        d("[PartyPlan.AutoDetection] Rejected occupied role " .. role .. " from " .. name .. "; owner=" .. other.name)
        return false
    end
    if type(TensorCore.addAlertText) ~= "function" then return fail("TensorCore.addAlertText dependency missing; assignment stopped") end
    if not PartyPlan.SetRole(member.id, role, "chat") then return fail("SetRole failed; player=" .. name .. ", role=" .. role) end
    TensorCore.addAlertText(4000, (name:match("^%S+") or name) .. " (" .. member.job .. ") set to " .. role, 1, 1, false)
    return true
end
function PartyPlan.UpdateAutoDetection()
    if TimeSince(lastPoll) < 250 then return end
    lastPoll = Now()
    if not FightPlan.settings or FightPlan.settings.partyPlanAutoDetection ~= true or PartyPlan.autoDetectionFault then
        seen, listening = {}, false
        return
    end
    local p = TensorCore.mGetPlayer()
    if not p or not p.localmapid or p.localmapid == 0 then seen, listening = {}, false; return end
    if type(FightPlan.RaidMaps) ~= "table" then return fail("FightPlan.RaidMaps dependency missing") end
    if not FightPlan.RaidMaps[p.localmapid] or PartyPlan.replayMode then seen, listening = {}, false; return end
    local entities = TensorCore.entityList("myparty")
    if type(entities) ~= "table" then return fail("TensorCore.entityList returned " .. type(entities)) end
    local n, ids = 0, {}
    for id in pairs(entities) do ids[id] = true end
    ids[p.id] = true
    for _ in pairs(ids) do n = n + 1 end
    if n ~= 8 then seen, listening = {}, false; return end
    if not PartyPlan.partyList then
        if not PartyPlan.generatePartyPositions() then return fail("generatePartyPositions failed; map=" .. p.localmapid) end
    end
    if #PartyPlan.partyList ~= 8 then seen, listening = {}, false; return end
    for _, m in ipairs(PartyPlan.partyList) do if m.dummy or not ids[m.id] then seen, listening = {}, false; return end end
    if type(GetChatLines) ~= "function" then return fail("GetChatLines dependency missing") end
    local lines = GetChatLines()
    if type(lines) ~= "table" then return fail("GetChatLines returned " .. type(lines)) end
    local pending, nextSeen = {}, {}
    for id, line in pairs(lines) do
        if type(id) ~= "number" or type(line) ~= "table" or type(line.line) ~= "string" then return fail("invalid GetChatLines entry id=" .. tostring(id)) end
        local key = tostring(line.timestamp) .. ":" .. line.line
        nextSeen[id] = key
        if listening and seen[id] ~= key then pending[#pending+1] = {id=id, line=line} end
    end
    seen, listening = nextSeen, true
    table.sort(pending, function(a,b) return a.id < b.id end)
    for _, entry in ipairs(pending) do
        local name, text = entry.line.line:match("^@?(.-):%s*(.*)$")
        if name then
            name = name:gsub("^%s+", ""):gsub("%s+$", "")
            PartyPlan.ApplyRoleCallout(name, text)
            if PartyPlan.autoDetectionFault then return end
        end
    end
end
RegisterEventHandler("Gameloop.Update", PartyPlan.UpdateAutoDetection, "PartyPlan.AutoDetection")
