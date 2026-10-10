-- Party profiles keep mechanic order separate from roles and groups.
local mapToCheck = 968
PartyPlan = {GUI = {open = false, visible = false, pos = 0, selected = 1}, replayMode = false,
    partnerName = "", partnerID = 0, partnerRole = nil}
local gui = PartyPlan.GUI
local savePath = FightPlan.paths.partyLegacyDir
local roles = {"-", "MT", "OT", "H1", "H2", "M1", "M2", "R1", "R2"}
PartyPlan.roles = roles
local roleSet = {}
for _, role in ipairs(roles) do roleSet[role] = true end
local jobs = {[1]="GLD",[2]="PGL",[3]="MRD",[4]="LNC",[5]="ARC",[6]="CNJ",[7]="THM",
    [19]="PLD",[20]="MNK",[21]="WAR",[22]="DRG",[23]="BRD",[24]="WHM",[25]="BLM",
    [26]="ACN",[27]="SMN",[28]="SCH",[29]="ROG",[30]="NIN",[31]="MCH",[32]="DRK",
    [33]="AST",[34]="SAM",[35]="RDM",[36]="BLU",[37]="GNB",[38]="DNC",[39]="RPR",
    [40]="SGE",[41]="VPR",[42]="PCT"}
local categories = {GLD="tank",MRD="tank",PLD="tank",WAR="tank",DRK="tank",GNB="tank",
    CNJ="regen",WHM="regen",AST="regen",SCH="shield",SGE="shield",PGL="melee",LNC="melee",
    ROG="melee",MNK="melee",DRG="melee",NIN="melee",SAM="melee",RPR="melee",VPR="melee",
    ARC="ranged",BRD="ranged",MCH="ranged",DNC="ranged",THM="caster",ACN="caster",
    BLM="caster",SMN="caster",RDM="caster",PCT="caster",BLU="caster"}
local initialDefaults = {regen="H1", shield="H2", ranged="R1", caster="R2", tanks={WAR="MT",GNB="OT",DRK="MT",PLD="OT"}}
local defaultGroups = {MT=1,H1=1,M1=1,R1=1,OT=2,H2=2,M2=2,R2=2}
local defaultPairs = {MT="R1",R1="MT",OT="R2",R2="OT",M1="H1",H1="M1",M2="H2",H2="M2"}
local roleFamily = {MT="tank",OT="tank",H1="healer",H2="healer",M1="melee",M2="melee",R1="ranged",R2="ranged"}
local function jobFamily(job)
    local category=categories[job]
    if category=="regen" or category=="shield" then return "healer" end
    if category=="caster" then return "ranged" end
    return category or job
end
local migrateStore
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end
local function listLength(list, operation)
    assert(type(list)=="table", "["..operation.."] expected array")
    local count=0
    for key in pairs(list) do
        assert(type(key)=="number" and key>=1 and key%1==0, "["..operation.."] non-array key="..tostring(key))
        count=count+1
    end
    assert(count==#list, "["..operation.."] array contains gaps")
    return count
end
local function store()
    assert(type(FightPlan.settings) == "table", "[PartyPlan.Profiles] FightPlan.settings unavailable")
    if FightPlan.settings.partyPlan == nil then
        FightPlan.settings.partyPlan = {version=2, defaults=copy(initialDefaults), profiles={}}
    end
    local data = FightPlan.settings.partyPlan
    assert(type(data) == "table" and (data.version == 1 or data.version == 2) and type(data.defaults) == "table"
        and type(data.profiles) == "table", "[PartyPlan.Profiles] invalid partyPlan settings/version")
    if data.version==1 then migrateStore(data) end
    return data
end
local function persist()
    local path = FightPlan.paths.settingsFile
    local ok, err = FightPlan.IO.Write(path, FightPlan.settings)
    if not ok then d("[PartyPlan.Profiles.Save] " .. path .. ": " .. tostring(err)); return false end
    return true
end
function PartyPlan.GetDefaults() return store().defaults end
function PartyPlan.SaveDefaults() return persist() end
function PartyPlan.GetDefaultPairs()
    local defaults = PartyPlan.GetDefaults()
    if defaults.pairs == nil then defaults.pairs = copy(defaultPairs) end
    local configured = defaults.pairs
    if type(configured) ~= "table" then
        d("[PartyPlan.GetDefaultPairs] defaults.pairs must be a table")
        return nil
    end
    for role in pairs(defaultPairs) do
        local partner = configured[role]
        if not defaultPairs[partner] or partner == role or configured[partner] ~= role then
            d("[PartyPlan.GetDefaultPairs] invalid reciprocal pair: role=" .. role .. " partner=" .. tostring(partner))
            return nil
        end
    end
    return configured
end
function PartyPlan.SetDefaultPair(role, partner)
    local configured = PartyPlan.GetDefaultPairs()
    if not configured then return false end
    if not defaultPairs[role] or not defaultPairs[partner] or role == partner then
        d("[PartyPlan.SetDefaultPair] invalid roles: " .. tostring(role) .. "/" .. tostring(partner))
        return false
    end
    if configured[role] == partner then return true end
    local previous, displaced = configured[role], configured[partner]
    configured[role], configured[partner] = partner, role
    configured[previous], configured[displaced] = displaced, previous
    PartyPlan.SyncAssignments()
    return PartyPlan.SaveDefaults()
end
local function token(value)
    value = tostring(value)
    return #value .. ":" .. value
end
local function memberKey(member) return member.name end
local function signature(members, map, selfName, mode)
    local keys, seen = {}, {}
    for _, member in ipairs(members) do
        assert(not seen[member.name], "[PartyPlan.Profiles.Match] ambiguous duplicate player name: " .. member.name)
        seen[member.name] = true
        keys[#keys+1] = token(member.name)..token(jobFamily(member.job))
    end
    table.sort(keys)
    return token(map) .. token(selfName) .. token(mode) .. table.concat(keys)
end
migrateStore=function(data)
    local migrated, converted, origins, collisions = {},0,{},{}
    for oldKey,original in pairs(data.profiles) do
        local profile=copy(original)
        assert(profile.version==1 and type(profile.members)=="table", "[PartyPlan.Profiles.Migrate] invalid profile="..tostring(oldKey))
        local function readToken(offset)
            local colon=oldKey:find(":",offset,true)
            assert(colon, "[PartyPlan.Profiles.Migrate] invalid key="..oldKey)
            local length=tonumber(oldKey:sub(offset,colon-1))
            assert(length and length>=0, "[PartyPlan.Profiles.Migrate] invalid token="..oldKey)
            return oldKey:sub(colon+1,colon+length),colon+length+1
        end
        local _,offset=readToken(1)
        profile.selfName=readToken(offset)
        if profile.pair.kind=="player" then
            local found
            for _,m in ipairs(profile.members) do
                if profile.pair.value==token(m.name)..token(m.job) then found=m.name; break end
            end
            assert(found, "[PartyPlan.Profiles.Migrate] missing saved partner; profile="..profile.name)
            profile.pair.value=found
        elseif profile.pair.kind=="role" then profile.pair={kind="default"} end
        for _,m in ipairs(profile.members) do
            if not roleSet[m.role] then
                d("[PartyPlan.Profiles.Migrate] Removed unsupported role "..tostring(m.role).." for "..m.name.." in "..profile.name.."; reassign this player.")
                m.role="-"; converted=converted+1
            end
            m.group=defaultGroups[m.role] or 0
        end
        profile.version=2
        local key=signature(profile.members,profile.map,profile.selfName,profile.mode)
        if migrated[key] then
            migrated[key..token(origins[key])]=migrated[key]
            migrated[key]=nil
            collisions[key]=true
        end
        origins[key]=oldKey
        if collisions[key] then key=key..token(oldKey) end -- Ambiguous older profiles remain manual choices.
        migrated[key]=profile
    end
    data.profiles=migrated
    data.defaults.dpsRoles,data.defaults.groups,data.defaults.pairs=nil,nil,nil
    data.version=2
    for job,settings in pairs(FightPlan.settings) do
        if type(job)=="number" and type(settings)=="table" and (settings.Role=="D1" or settings.Role=="D2" or settings.Role=="D3" or settings.Role=="D4") then
            d("[PartyPlan.Profiles.Migrate] Removed unsupported per-job role "..settings.Role.." for job="..job.."; choose one of the eight raid roles.")
            settings.Role="-"
        end
    end
    d("[PartyPlan.Profiles.Migrate] Updated version 1 profiles to name/role-family matching; unsupported roles="..converted..". Changes save with the next edit.")
end
local function player()
    local p = TensorCore.mGetPlayer()
    if not p or not p.id or not p.name or p.name == "" or not p.job or p.job == 0 or not p.localmapid or p.localmapid == 0 then return nil end
    return p -- Login/loading is a documented pending state.
end
local function collectMembers(dummy)
    local p = player()
    assert(p, "[PartyPlan.Generate] player is not ready")
    local entities = TensorCore.entityList(PartyPlan.replayMode and "chartype=4" or "myparty")
    assert(type(entities) == "table", "[PartyPlan.Collect/TensorCore.entityList] returned " .. type(entities))
    local members, seen = {}, {}
    local function insert(id, entity)
        assert(entity and type(entity.name) == "string" and entity.name ~= "" and entity.job,
            "[PartyPlan.Collect] invalid entity id=" .. tostring(id))
        assert(entity.pos and type(entity.pos.x) == "number", "[PartyPlan.Collect] missing position id=" .. tostring(id))
        if not seen[id] then
            seen[id] = true
            members[#members+1] = {name=entity.name,job=jobs[entity.job] or ("JOB"..entity.job),jobId=entity.job,id=id,x=entity.pos.x}
        end
    end
    for id, entity in pairs(entities) do insert(id, entity) end
    insert(p.id, p)
    assert(#members <= 8, "[PartyPlan.Collect] expected at most eight players; found " .. #members .. " (check Replay Mode)")
    if #members == 1 and dummy then
        local template = {21,37,24,28,20,22,23,25}
        local names = {"Sakura Haruno","Sasuke Uchiha","Naruto Uzumaki","Orochimaru King","Kakashi Hatake","Rock Lee","Neji Hyuga","Dummy Player"}
        local category = categories[jobs[p.job]]
        local removed = false
        for i, job in ipairs(template) do
            if not removed and categories[jobs[job]] == category then removed = true
            else
                -- An unsupported solo job still gets seven combat-role dummies.
                if #members < 8 then members[#members+1] = {name=names[i],job=jobs[job],jobId=job,id=-i,x=p.pos.x+i,dummy=true} end
            end
        end
    end
    table.sort(members, function(a,b) if a.x == b.x then return a.name < b.name end return a.x < b.x end)
    local mode = PartyPlan.replayMode and "replay" or (#members > 1 and members[2].dummy and "dummy" or "party")
    for _, m in ipairs(members) do if m.dummy then mode = PartyPlan.replayMode and "replay-dummy" or "dummy"; break end end
    return members, signature(members,p.localmapid,p.name,mode), p, mode
end
function PartyPlan.AssignDefaults(members)
    listLength(members,"PartyPlan.AssignDefaults")
    local defaults, used = PartyPlan.GetDefaults(), {}
    local ranked = {}
    for _, member in ipairs(members) do ranked[#ranked+1] = member end
    -- Priority and deterministic tie-breaking must not reorder the mechanic lineup.
    local rank = {WAR=1,DRK=2,PLD=3,GNB=4}
    table.sort(ranked, function(a,b)
        local ra, rb = rank[a.job] or 10, rank[b.job] or 10
        if ra ~= rb then return ra < rb end
        if a.name == b.name then return a.job < b.job end
        return a.name < b.name
    end)
    local function claim(member, choices)
        for _, role in ipairs(choices) do
            if not used[role] then member.role=role; used[role]=true; return end
        end
    end
    for _, member in ipairs(ranked) do
        member.role = "-"
        local category = categories[member.job]
        local preferred
        if category == "tank" then preferred = defaults.tanks[member.job] or (member.job == "MRD" and defaults.tanks.WAR or defaults.tanks.PLD)
        elseif category == "regen" or category == "shield" then preferred = defaults[category]
        elseif category == "ranged" or category == "caster" then preferred = defaults[category] end
        if preferred then
            assert(roleSet[preferred] and preferred ~= "-", "[PartyPlan.AssignDefaults] invalid default for " .. member.job .. ": " .. tostring(preferred))
            claim(member,{preferred})
        end
    end
    for _, member in ipairs(ranked) do
        if member.role == "-" then
            local category = categories[member.job]
            if category == "tank" then claim(member,{"MT","OT"})
            elseif category == "regen" or category == "shield" then claim(member,{"H1","H2"})
            elseif category == "melee" then claim(member,{"M1","M2"})
            elseif category == "ranged" or category == "caster" then claim(member,{"R1","R2"}) end
        end
        member.group = defaultGroups[member.role] or 0
    end
    return members
end

FightPlan.Groups = {[1]={},[2]={}}
local temporaryGroups = {}
local function rebuildGroups()
    for group=1,2 do
        local ids = {}
        if temporaryGroups[group] then
            for _, id in ipairs(temporaryGroups[group]) do ids[#ids+1] = id end
        else
            for _, member in ipairs(PartyPlan.partyList or {}) do if defaultGroups[member.role] == group then ids[#ids+1] = member.id end end
        end
        FightPlan.Groups[group] = ids
    end
end
function FightPlan.Groups.SetTemporary(group, ids)
    assert(group == 1 or group == 2, "[FightPlan.Groups.SetTemporary] group must be 1 or 2")
    assert(type(ids) == "table", "[FightPlan.Groups.SetTemporary] expected entity ID array")
    listLength(ids,"FightPlan.Groups.SetTemporary")
    local valid, seen = {}, {}
    for _, member in ipairs(PartyPlan.partyList or {}) do valid[member.id] = true end
    for _, id in ipairs(ids) do assert(valid[id] and not seen[id], "[FightPlan.Groups.SetTemporary] invalid/duplicate party ID=" .. tostring(id)); seen[id] = true end
    temporaryGroups[group] = copy(ids)
    rebuildGroups()
end
function FightPlan.Groups.ClearTemporary()
    temporaryGroups = {}
    rebuildGroups()
end
function PartyPlan.GetMember(roleOrID)
    for _, member in ipairs(PartyPlan.partyList or {}) do
        if member.id == roleOrID or (roleOrID ~= "-" and member.role == roleOrID) then return member end
    end
end
function PartyPlan.SyncAssignments()
    rebuildGroups()
    PartyPlan.partnerID, PartyPlan.partnerName, PartyPlan.partnerRole = 0, "", nil
    local pair = PartyPlan.pair or {kind="default"}
    local selfMember
    local p = player()
    if p then selfMember = PartyPlan.GetMember(p.id) end
    if selfMember then
        FightPlan.Role = selfMember.role ~= "-" and selfMember.role or nil
        FightPlan.RoleIndex = FightPlan.RoleToIndex and FightPlan.RoleToIndex[FightPlan.Role]
    end
    local target
    local configuredPairs
    if pair.kind=="default" and selfMember then
        configuredPairs = PartyPlan.GetDefaultPairs()
        if not configuredPairs then return end
    end
    local pairedRole=configuredPairs and configuredPairs[selfMember.role]
    for _, member in ipairs(PartyPlan.partyList or {}) do
        if (pair.kind == "player" and pair.value == member.name) or (pairedRole and pairedRole==member.role) then target = member; break end
    end
    if target and (not p or target.id ~= p.id) then
        PartyPlan.partnerID, PartyPlan.partnerName, PartyPlan.partnerRole = target.id, target.name, target.role
    end
end
local activeKey, activeMap, activeMode, activeName, activeNamed
local function validateProfile(profile)
    assert(type(profile) == "table" and profile.version == 2 and type(profile.members) == "table" and #profile.members > 0 and #profile.members <= 8,
        "[PartyPlan.Profiles.Validate] malformed profile")
    listLength(profile.members,"PartyPlan.Profiles.Validate")
    assert(profile.named==nil or type(profile.named)=="boolean", "[PartyPlan.Profiles.Validate] invalid named flag")
    local seen, identities = {},{}
    for _, m in ipairs(profile.members) do
        assert(type(m.name)=="string" and type(m.job)=="string" and roleSet[m.role] and (m.group==0 or m.group==1 or m.group==2),
            "[PartyPlan.Profiles.Validate] invalid member assignment")
        if m.role ~= "-" then assert(not seen[m.role], "[PartyPlan.Profiles.Validate] duplicate role " .. m.role); seen[m.role]=true end
        assert(not identities[memberKey(m)], "[PartyPlan.Profiles.Validate] duplicate player "..m.name)
        identities[memberKey(m)]=true
    end
    assert(type(profile.pair)=="table" and (profile.pair.kind=="none" or profile.pair.kind=="default" or profile.pair.kind=="player"),
        "[PartyPlan.Profiles.Validate] invalid pair selection")
    assert(profile.pair.kind~="player" or type(profile.pair.value)=="string", "[PartyPlan.Profiles.Validate] missing pair value")
    if profile.pair.kind=="player" then assert(identities[profile.pair.value], "[PartyPlan.Profiles.Validate] missing pair player="..profile.pair.value) end
end
function PartyPlan.SaveProfile(name)
    assert(activeKey and PartyPlan.partyList, "[PartyPlan.Profiles.Save] generate/load a party first")
    if name then assert(type(name)=="string" and name:find("%S"), "[PartyPlan.Profiles.Save] blank profile name") end
    local profile = {version=2,map=activeMap,mode=activeMode,selfName=player().name,name=name or activeName or ("Zone "..activeMap),named=name~=nil or activeNamed==true,members=copy(PartyPlan.partyList),pair=copy(PartyPlan.pair)}
    validateProfile(profile)
    store().profiles[activeKey] = profile
    if not persist() then return false end
    activeName = profile.name
    activeNamed = profile.named
    return true
end
local function activate(profile, current, key, p, mode)
    validateProfile(profile)
    local byKey, bound = {}, {}
    for _, member in ipairs(current) do byKey[memberKey(member)] = member end
    assert(#profile.members == #current, "[PartyPlan.Profiles.Load] party size does not match")
    for _, saved in ipairs(profile.members) do
        local member = byKey[memberKey(saved)]
        assert(member, "[PartyPlan.Profiles.Load] missing player: " .. saved.name)
        assert(not bound[memberKey(saved)], "[PartyPlan.Profiles.Load] duplicate player: " .. saved.name)
        bound[memberKey(saved)] = true
    end
    local list = {}
    for _, saved in ipairs(profile.members) do
        local member = copy(byKey[memberKey(saved)])
        member.role, member.group = saved.role, defaultGroups[saved.role] or 0
        member.roleSource = saved.roleSource
        list[#list+1] = member
    end
    PartyPlan.partyList, PartyPlan.pair = list, copy(profile.pair)
    activeKey, activeMap, activeMode, activeName = key,p.localmapid,mode,profile.name
    activeNamed=profile.named==true or (profile.named==nil and profile.name~="Zone "..p.localmapid)
    FightPlan.Groups.ClearTemporary()
    PartyPlan.SyncAssignments()
end
function PartyPlan.generatePartyPositions()
    local members, key, p, mode = collectMembers(true)
    local saved=store().profiles[key]
    if saved and (saved.named==true or (saved.named==nil and saved.name~="Zone "..saved.map)) then
        activate(saved,members,key,p,mode)
        d("[PartyPlan.Generate] Reused named profile "..saved.name.."; saved lineup, roles and partner retained.")
        return PartyPlan.partyList
    end
    PartyPlan.AssignDefaults(members)
    activate({version=2,members=members,pair={kind="default"},name="Zone "..p.localmapid,named=false},members,key,p,mode)
    if not PartyPlan.SaveProfile() then return nil end
    return PartyPlan.partyList
end
function PartyPlan.SetRole(id, role, source)
    if not roleSet[role] or (source ~= nil and source ~= "chat" and source ~= "manual") then
        d("[PartyPlan.SetRole] unsupported role/source=" .. tostring(role) .. "/" .. tostring(source)); return false
    end
    local member = PartyPlan.GetMember(id)
    if not member then d("[PartyPlan.SetRole] missing party ID=" .. tostring(id)); return false end
    local other = role ~= "-" and PartyPlan.GetMember(role)
    local previous = member.role
    member.role, member.group, member.roleSource = role, defaultGroups[role] or 0, source or "manual"
    if other and other ~= member then
        other.role, other.group = previous, defaultGroups[previous] or 0
        -- A manual swap protects both assignments; a chat swap leaves the default owner free to claim.
        if source ~= "chat" then other.roleSource = "manual" end
    end
    PartyPlan.SyncAssignments()
    return PartyPlan.SaveProfile()
end
function PartyPlan.Reorder()
    local current = collectMembers(true)
    if not PartyPlan.partyList then return PartyPlan.generatePartyPositions() ~= nil end
    local positions = {}
    for _, m in ipairs(current) do positions[m.name] = m.x end
    for _, m in ipairs(PartyPlan.partyList) do
        if not positions[m.name] then d("[PartyPlan.Reorder] roster changed; generate a party first; missing=" .. m.name); return false end
    end
    table.sort(PartyPlan.partyList, function(a,b)
        if positions[a.name] == positions[b.name] then return a.name < b.name end
        return positions[a.name] < positions[b.name]
    end)
    PartyPlan.SyncAssignments()
    return PartyPlan.SaveProfile()
end
function PartyPlan.SetPartner(kind, value)
    assert(kind=="none" or kind=="default" or kind=="player", "[PartyPlan.SetPartner] use player, default or none")
    local p = player()
    if kind=="player" then
        local member = PartyPlan.GetMember(value)
        assert(member and (not p or member.id~=p.id), "[PartyPlan.SetPartner] select another party member")
        value = memberKey(member)
    end
    PartyPlan.pair = {kind=kind,value=kind=="player" and value or nil}
    PartyPlan.SyncAssignments()
    PartyPlan.SaveProfile()
end
function PartyPlan.MoveMember(id, destination)
    local source
    for i,m in ipairs(PartyPlan.partyList or {}) do if m.id==id then source=i; break end end
    assert(source and type(destination)=="number" and destination%1==0 and destination>=1 and destination<=#PartyPlan.partyList,
        "[PartyPlan.MoveMember] invalid source/destination: id="..tostring(id)..", destination="..tostring(destination))
    if source==destination then return end
    local member=table.remove(PartyPlan.partyList,source)
    table.insert(PartyPlan.partyList,destination,member)
    gui.selected=destination
    PartyPlan.SyncAssignments()
    PartyPlan.SaveProfile()
end
local function compatible(saved,current)
    if saved.role=="-" then return jobFamily(saved.job)==jobFamily(current.job) end
    return roleFamily[saved.role]==jobFamily(current.job)
end
function PartyPlan.MatchProfile(profile,current)
    validateProfile(profile)
    local names, matched, full = {},0,#profile.members==#current
    for _,m in ipairs(current) do names[m.name]=m end
    for _,saved in ipairs(profile.members) do
        local member=names[saved.name]
        if member then matched=matched+1 else full=false end
        if not member or not compatible(saved,member) then full=false end
    end
    return matched/math.max(#profile.members,#current),full
end
function PartyPlan.GetMatchingProfiles()
    if not player() then return {} end
    local current,_,p,mode=collectMembers(true)
    local result={}
    for key,profile in pairs(store().profiles) do
        if profile.mode==mode and profile.selfName==p.name then
            local overlap,full=PartyPlan.MatchProfile(profile,current)
            if overlap>=0.5 then result[#result+1]={key=key,name=profile.name,map=profile.map,overlap=overlap,exact=full} end
        end
    end
    table.sort(result,function(a,b)
        if a.overlap~=b.overlap then return a.overlap>b.overlap end
        if a.map~=b.map then return a.map<b.map end
        if a.name~=b.name then return a.name<b.name end
        return a.key<b.key
    end)
    return result
end
function PartyPlan.LoadProfile(key)
    local profile = store().profiles[key]
    assert(profile, "[PartyPlan.Profiles.Load] unknown profile=" .. tostring(key))
    local current, currentKey, p, mode = collectMembers(true)
    assert(profile.mode==mode and profile.selfName==p.name,"[PartyPlan.Profiles.Load] profile belongs to another player or replay/dummy scope")
    local overlap,full=PartyPlan.MatchProfile(profile,current)
    assert(overlap>=0.5,"[PartyPlan.Profiles.Load] fewer than 50% of player names match")
    if not full then
        local merged,byName,reserved={}, {},{}
        PartyPlan.AssignDefaults(current)
        for _,m in ipairs(current) do byName[m.name]=m end
        for _,saved in ipairs(profile.members) do
            local m=byName[saved.name]
            if m and compatible(saved,m) then m.role=saved.role; reserved[m.role]=true end
        end
        local pools={tank={"MT","OT"},healer={"H1","H2"},melee={"M1","M2"},ranged={"R1","R2"}}
        local retained={}
        for _,saved in ipairs(profile.members) do
            local m=byName[saved.name]
            if m then retained[m.name]=compatible(saved,m); merged[#merged+1]=m; byName[m.name]=nil end
        end
        for _,m in ipairs(current) do if byName[m.name] then merged[#merged+1]=m end end
        for _,m in ipairs(merged) do
            if not retained[m.name] then
                local preferred=m.role
                m.role="-"
                if preferred~="-" and not reserved[preferred] then m.role=preferred
                else for _,role in ipairs(pools[jobFamily(m.job)] or {}) do if not reserved[role] then m.role=role; break end end end
                if m.role~="-" then reserved[m.role]=true end
            end
            m.group=defaultGroups[m.role] or 0
        end
        local pair=copy(profile.pair)
        local pairPresent=false
        for _,m in ipairs(merged) do if m.name==pair.value then pairPresent=true end end
        if pair.kind=="player" and not pairPresent then pair={kind="default"} end
        profile={version=2,name=profile.name,members=merged,pair=pair}
        d("[PartyPlan.Profiles.Load] Manual load: "..math.floor(overlap*100).."% name overlap; retained compatible roles, assigned defaults to replacements.")
    end
    activate(profile,current,currentKey,p,mode)
    PartyPlan.SaveProfile(profile.name)
end
local lastPoll, candidateKey, stableCount = 0,nil,0
function PartyPlan.UpdateProfiles()
    if TimeSince(lastPoll) < 1000 then return end
    lastPoll = Now()
    if not player() then
        if PartyPlan.partyList then PartyPlan.ClearParty() end
        candidateKey, stableCount = nil,0
        return
    end
    local members,key,p,mode = collectMembers(true)
    if activeKey and activeKey~=key then PartyPlan.ClearParty() end
    if candidateKey==key then stableCount=stableCount+1 else candidateKey,stableCount=key,1 end
    if stableCount < 2 then return end
    if activeKey==key then
        -- Runtime entity IDs can change without changing names/jobs/map.
        local byName = {}
        for _, m in ipairs(members) do byName[m.name] = m end
        local changed = false
        for _, m in ipairs(PartyPlan.partyList) do
            local current=byName[m.name]
            if m.id~=current.id then changed=true end
            m.id,m.job,m.jobId=current.id,current.job,current.jobId
        end
        if changed then FightPlan.Groups.ClearTemporary() end
        PartyPlan.SyncAssignments()
    else
        local profiles=store().profiles
        local matches={}
        for savedKey,profile in pairs(profiles) do
            if profile.map==p.localmapid and profile.mode==mode and profile.selfName==p.name then
                local _,full=PartyPlan.MatchProfile(profile,members)
                if full then matches[#matches+1]=savedKey end
            end
        end
        local selected
        for _,savedKey in ipairs(matches) do if savedKey==key then selected=savedKey end end
        if not selected and #matches==1 then selected=matches[1] end
        PartyPlan.profileStatus=#matches>1 and not selected and "Multiple matching profiles: select one manually." or nil
        if selected then
            local profile=profiles[selected]
            activate(profile,members,key,p,mode)
            d("[PartyPlan.Profiles] Loaded "..profile.name.." for zone "..p.localmapid)
        end
    end
end
function PartyPlan.ClearParty()
    PartyPlan.partyList, PartyPlan.pair = nil,nil
    activeKey,activeMap,activeMode,activeName,activeNamed = nil,nil,nil,nil,nil
    FightPlan.Groups.ClearTemporary()
    PartyPlan.SyncAssignments()
    local p = player()
    FightPlan.Role = p and FightPlan.settings[p.job] and FightPlan.settings[p.job].Role or nil
    FightPlan.RoleIndex = FightPlan.RoleToIndex and FightPlan.RoleToIndex[FightPlan.Role]
end

local currentMenuTab, selectedProfileKey, profileName, renameOpen = "party",nil,"",false
local configSection, measuredHeight = 1, {}
local function tooltip(text) if GUI:IsItemHovered() then GUI:SetTooltip(text) end end
local function indexOf(list,value) for i,v in ipairs(list) do if v==value then return i end end return 1 end
local function combo(id, value, options, width)
    return FightPlan.gui.compactCombo(id,value,options,width or 64)
end
local function drawProfiles()
    local matches=PartyPlan.GetMatchingProfiles()
    local labels,selected={},1
    for i,match in ipairs(matches) do
        labels[i]=match.name.." ("..match.map..", "..math.floor(match.overlap*100).."%)"
        if match.key==(selectedProfileKey or activeKey) then selected=i end
    end
    GUI:AlignFirstTextHeightToWidgets(); GUI:Text("Profile") GUI:SameLine(78,0)
    local changed
    if #matches==0 then
        combo("##PPProfile",1,{"No matching profiles"},222)
    else
        selected,changed=combo("##PPProfile",selected,labels,222)
        selectedProfileKey=matches[selected].key
    end
    local hint=PartyPlan.profileStatus or "At least 50% name overlap is shown. Only 100% names and compatible saved roles auto-load in this zone."
    if matches[selected] then
        local profile=store().profiles[matches[selected].key]
        hint=profile.name.."\n"..hint
        for _,m in ipairs(profile.members) do hint=hint.."\n"..m.role.."  "..m.name end
    end
    tooltip(hint)
    GUI:SameLine(312,0)
    if GUI:Button("Load##PPProfileLoad",60,24) and #matches>0 then
        PartyPlan.LoadProfile(matches[selected].key); profileName=activeName
    end
    tooltip("Manual load keeps compatible named players and fills replacement players with available role defaults.")
end
local function drawLegacy()
    if not PartyPlan.showLegacy then return end
    local files={}
    if FolderExists(savePath) then
        local listed=FolderList(savePath,[[(.*)lua$]])
        assert(type(listed)=="table", "[PartyPlan.Profiles.Import/FolderList] invalid listing: "..savePath)
        for _,name in pairs(listed) do files[#files+1]=name end
    end
    table.sort(files)
    if #files==0 then GUI:Text("No old profiles."); return end
    PartyPlan.legacySelected=math.min(PartyPlan.legacySelected or 1,#files)
    GUI:AlignFirstTextHeightToWidgets(); GUI:Text("Import") GUI:SameLine(78,0)
    PartyPlan.legacySelected=combo("##PPLegacyFiles",PartyPlan.legacySelected,files,222)
    GUI:SameLine(312,0)
    if GUI:Button("Import##PPLegacyLoad",60,24) then
        local file=files[PartyPlan.legacySelected]
        assert(not file:find("[/\\]"), "[PartyPlan.Profiles.Import] invalid filename="..file)
        local old=FightPlan.IO.Read(savePath.."\\"..file)
        assert(type(old)=="table", "[PartyPlan.Profiles.Import] missing file="..file)
        PartyPlan.AssignDefaults(old)
        local current,key,p,mode=collectMembers(true)
        activate({version=2,members=old,pair={kind="default"},name=file:gsub("%.lua$", "")},current,key,p,mode)
        PartyPlan.SaveProfile()
    end
end
local function rightClickPartner(member)
    local p=player()
    if GUI:IsItemClicked(1) and p and member.id~=p.id then PartyPlan.SetPartner("player",member.id) end
end
function PartyPlan.DrawPartySettings()
    local g=FightPlan.gui
    g.captionDivider("Profile")
    drawProfiles()
    if g.colorButton("Generate##PPGenerate",g.PAL_GREEN,104,24) then PartyPlan.generatePartyPositions(); profileName=activeName; selectedProfileKey=activeKey end
    tooltip("Generate and save a west (1) to east (8) lineup. A matching named profile is reused without overwriting its assignments. Solo creates seven dummy members.")
    GUI:SameLine(122,0)
    if GUI:Button("Name##PPName",58,24) and PartyPlan.partyList then renameOpen=not renameOpen; profileName=activeName end
    GUI:SameLine(192,0)
    if GUI:Button("Import##PPLegacy",58,24) then PartyPlan.showLegacy=not PartyPlan.showLegacy end
    GUI:SameLine(268,0)
    local replay,changed=GUI:Checkbox("Replay##PPReplay",PartyPlan.replayMode)
    if changed then PartyPlan.replayMode=replay; PartyPlan.ClearParty(); candidateKey=nil; selectedProfileKey=nil end
    tooltip("Use player entities from a duty recording. Replay profiles remain separate.")
    if renameOpen and PartyPlan.partyList then
        GUI:AlignFirstTextHeightToWidgets(); GUI:Text("Name") GUI:SameLine(78,0)
        GUI:PushItemWidth(222)
        profileName=GUI:InputText("##PPProfileName",profileName)
        GUI:PopItemWidth()
        GUI:SameLine(312,0)
        if GUI:Button("Save##PPProfileRename",60,24) then PartyPlan.SaveProfile(profileName); renameOpen=false end
    end
    if GUI:Button("Reorder##PPReorder",104,24) then PartyPlan.Reorder() end
    tooltip("Reorder 1-8 from west to east while keeping roles, chat/manual locks and partners.")
    drawLegacy()
    g.sectionHeader("Lineup")
    if not PartyPlan.partyList then
        g.coloredText(g.C.text_dim,"%s",PartyPlan.profileStatus or "Generate a party or choose a profile.")
        return
    end
    g.pushColor4(GUI.Col_Text,g.C.text_mute)
    GUI:Text("#") GUI:SameLine(34,0); GUI:Text("JOB") GUI:SameLine(80,0); GUI:Text("PLAYER")
    GUI:SameLine(312,0); GUI:Text("ROLE")
    GUI:PopStyleColor(1)
    local mouseX,mouseY=GUI:GetMousePos()
    local destination
    for i,member in ipairs(PartyPlan.partyList) do
        GUI:AlignFirstTextHeightToWidgets(); GUI:Text(tostring(i)) GUI:SameLine(34,0)
        GUI:InvisibleButton("##PPRow"..member.id,266,24)
        local x,y=GUI:GetItemRectMin()
        local maxX,maxY=GUI:GetItemRectMax()
        local over=mouseX>=x and mouseX<=maxX and mouseY>=y and mouseY<maxY
        if GUI:IsItemClicked(0) then gui.dragID=member.id; gui.selected=i end
        rightClickPartner(member)
        if over and gui.dragID and GUI:IsMouseDown(0) then destination=i end
        if over then GUI:SetTooltip(member.name.."\nDrag the job or name to change 1–8 priority. Right-click to set your partner.") end
        local fill=over and g.C.bg_ctrl_hov or (gui.dragID==member.id and g.C.bg_ctrl_act or g.C.bg_control)
        GUI:AddRectFilled(x,y,maxX,maxY,GUI:ColorConvertFloat4ToU32(fill[1],fill[2],fill[3],fill[4]))
        local paired=member.id==PartyPlan.partnerID
        if paired then
            -- Same RGB and 122/255 fill opacity as fpYellow (0x7A00C5FF).
            GUI:AddRectFilled(x,y,maxX,maxY,GUI:ColorConvertFloat4ToU32(1,197/255,0,122/255))
        end
        local color=GUI:ColorConvertFloat4ToU32(g.C.text[1],g.C.text[2],g.C.text[3],1)
        GUI:AddText(x,y+4,color,g.fitText(member.job,34))
        local nameRight=maxX-4
        if paired then
            local markerX=maxX-GUI:CalcTextSize("[P]")-4
            GUI:AddText(markerX,y+4,GUI:ColorConvertFloat4ToU32(1,197/255,0,1),"[P]")
            nameRight=markerX-8
        end
        GUI:AddText(x+46,y+4,color,g.fitText(member.name,nameRight-(x+46)))
        GUI:SameLine(312,0)
        local idx,roleChanged=combo("##PPRole"..member.id,indexOf(roles,member.role),roles,60)
        tooltip("Selecting an occupied role swaps assignments without moving the lineup.")
        if roleChanged then PartyPlan.SetRole(member.id,roles[idx]) end
    end
    if gui.dragID and destination then PartyPlan.MoveMember(gui.dragID,destination) end
    if not GUI:IsMouseDown(0) then gui.dragID=nil end
end
function PartyPlan.DrawDefaults()
    local g=FightPlan.gui
    g.segmented("PPConfig",{"General","Drawers"},configSection,function(i) configSection=i end)
    GUI:Spacing()
    if configSection==2 then
        FightPlan.DrawDrawerSettings(g)
        GUI:Spacing()
        PartyPlan.DrawAOEProgressSettings()
        return
    end
    local defaults=PartyPlan.GetDefaults()
    g.captionDivider("Plans")
    g.formRow("Plan Editor", "Edit this install's plan files in game; saving reloads FightPlan.", function()
        if GUI:Button((FightPlan.Editor.IsOpen() and "Close" or "Open").." Editor##PPEditor", g.UI.INPUT_W, g.UI.ROW_H) then FightPlan.Editor.Toggle() end
    end)
    g.sectionHeader("Role Detection")
    local auto, autoChanged = g.formBool("Auto Detection", "In an eight-player raid, accept each player's first chat role claim. Manual assignments take priority.",
        "PPAuto", FightPlan.settings.partyPlanAutoDetection == true)
    if autoChanged then
        FightPlan.settings.partyPlanAutoDetection = auto
        PartyPlan.autoDetectionFault = nil
        PartyPlan.SaveDefaults()
    end
    if PartyPlan.autoDetectionFault then g.wrappedText(g.C.red, "Auto detection stopped: " .. PartyPlan.autoDetectionFault) end
    g.sectionHeader("Role Defaults")
    local rows={
        {{"Regen","regen",{"H1","H2"}},{"Shield","shield",{"H1","H2"}}},
        {{"Ranged","ranged",{"R1","R2"}},{"Caster","caster",{"R1","R2"}}},
        {{"WAR","WAR",{"MT","OT"},defaults.tanks},{"GNB","GNB",{"MT","OT"},defaults.tanks}},
        {{"DRK","DRK",{"MT","OT"},defaults.tanks},{"PLD","PLD",{"MT","OT"},defaults.tanks}},
    }
    for _,row in ipairs(rows) do
        for column,setting in ipairs(row) do
            local start=column==1 and 10 or 204
            if column==2 then GUI:SameLine(start,0) end
            GUI:AlignFirstTextHeightToWidgets(); GUI:Text(setting[1]); tooltip("Default when generating a party. Saved profiles retain their assignments.")
            GUI:SameLine(start+76,0)
            local owner=setting[4] or defaults
            local idx,changed=combo("##PPDefault"..setting[1],indexOf(setting[3],owner[setting[2]]),setting[3],64)
            if changed then owner[setting[2]]=setting[3][idx]; PartyPlan.SaveDefaults() end
        end
    end
    g.sectionHeader("Default Partners")
    local configuredPairs = PartyPlan.GetDefaultPairs()
    if configuredPairs then
        for i, role in ipairs({"MT", "OT", "H1", "H2", "M1", "M2", "R1", "R2"}) do
            local start = i % 2 == 1 and 10 or 204
            if i % 2 == 0 then GUI:SameLine(start, 0) end
            GUI:AlignFirstTextHeightToWidgets(); GUI:Text(role)
            GUI:SameLine(start + 76, 0)
            local options = {}
            for _, candidate in ipairs(roles) do
                if candidate ~= "-" and candidate ~= role then options[#options + 1] = candidate end
            end
            local idx, changed = combo("##PPDefaultPair" .. role, indexOf(options, configuredPairs[role]), options, 64)
            tooltip("Reciprocal partners. Selecting a new partner pairs the two displaced roles together. Applies when your partner uses Default; explicit player partners stay unchanged.")
            if changed and not PartyPlan.SetDefaultPair(role, options[idx]) then return end
        end
    end
end
local firstRun, mapCheckTick = false,Now()
local menuTabs={{id="party",label="Party"},{id="timers",label="Timers"},{id="config",label="Config"}}
function PartyPlan.draw(event,ticks)
    local p=player()
    if TimeSince(mapCheckTick)>2000 and not firstRun and not PartyPlan.partyList and p and p.localmapid==mapToCheck then
        gui.open,gui.visible,firstRun=true,true,true
        mapCheckTick=Now()
    end
    PartyPlan.DrawTimers()
    if not gui.open then return end
    local g=FightPlan.gui
    g.pushTheme()
    g.pushDensity()
    -- Fixed width per tab; height is last frame's measured content height (DR hub style).
    GUI:SetNextWindowSize(currentMenuTab=="party" and 390 or 410,measuredHeight[currentMenuTab] or 416,GUI.SetCond_Always)
    gui.visible,gui.open=GUI:Begin("FightPlan Party",gui.open,GUI.WindowFlags_NoResize+GUI.WindowFlags_NoCollapse
        +GUI.WindowFlags_NoScrollbar+GUI.WindowFlags_NoScrollWithMouse)
    local ok,err=xpcall(function()
        if not gui.visible then return end
        g.drawTopTabs("PPTabs",menuTabs,currentMenuTab,function(id) currentMenuTab=id end)
        GUI:Spacing()
        local tab=currentMenuTab
        if tab=="party" then PartyPlan.DrawPartySettings()
        elseif tab=="config" then PartyPlan.DrawDefaults()
        else PartyPlan.DrawTimerSettings() end
        GUI:Spacing()
        local list=PartyPlan.partyList
        g.statusFooter{dot=list and "live" or "idle",
            left=list and g.fitText((activeName or "Unsaved Lineup").." - "..#list.." players",250) or "No party",
            right="v"..tostring(FightPlan.version)}
        measuredHeight[tab]=math.ceil(GUI:GetCursorPosY()+4)
    end,function(reason)
        local message="[PartyPlan.draw] "..tostring(reason)
        return debug and debug.traceback and debug.traceback(message,2) or message
    end)
    GUI:End()
    g.popDensity()
    g.popTheme()
    if not ok then d(err) return end
end
RegisterEventHandler("Gameloop.Update",PartyPlan.UpdateProfiles,"PartyPlan.Profiles")


function PartyPlan.getClosestPlayersToEnt(entid,number) -- provide entityID to the target you want to check from, and number of party members to check, returns a table of entityIDs in order.
    local enemy
    if type(entid) ~= "table" then

        enemy = TensorCore.mGetEntity(entid)
    else
        enemy = {}
        enemy.pos = entid
    end

    local distances = {}
    local party = TensorCore.entityList("chartype=4,alive")
    if TensorCore.mGetPlayer().alive then
        party[TensorCore.mGetPlayer().id] = TensorCore.mGetPlayer()
    end
    for id, ent in pairs(party) do
        local distance = TensorCore.getDistance2d(ent.pos,enemy.pos)
        table.insert(distances, {distance = distance, id = id})
    end

    table.sort(distances, function(a, b) return a.distance < b.distance end)

    local closestPlayers = {}
    for i = 1, math.min(number, #distances) do
        table.insert(closestPlayers, distances[i].id)
    end

    return closestPlayers
end


-- Deprecated spelling for installed profiles; hpSwap uses the gap, not an HP floor.
local warnedEqualizeHP = false
function PartyPlan.equalizeHP(t1,t2,minhp,diffAllowed)
    assert(FightPlan and type(FightPlan.hpSwap) == "function", "[PartyPlan.equalizeHP] FightPlan.hpSwap is unavailable")
    if not warnedEqualizeHP then
        d("[PartyPlan.equalizeHP] Deprecated: use FightPlan.hpSwap({id1,id2}, 2); minhp is ignored. This notice repeats after Lua reload.")
        warnedEqualizeHP = true
    end
    return FightPlan.hpSwap({t1,t2}, diffAllowed)
end

PartyPlan.timers = {}
PartyPlan.parentWindowName = "##PartyPlanTimerBarsParent"
PartyPlan.timerAnchorUnlocked = false -- Editing is temporary; always lock after a reload.
PartyPlan.timerHeight = 32
PartyPlan.timerSpacing = 6
local timerSettingsRef
local timerSettingsDirtyAt
local placeTimerAnchor = true
local newTimerName, newTimerLabel, newTimerSeconds = "", "", 30
local timerDefaults = { x = 400, y = 300, width = 300, height = 32, spacing = 6,
    growth = "down", r = 0.345, g = 0.694, b = 0.957, a = 1 }

local function finiteNumber(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function getTimerSettings()
    assert(type(FightPlan.settings) == "table", "[PartyPlan.TimerSettings] FightPlan.settings is unavailable")
    local s = FightPlan.settings.partyPlanTimers
    -- FightPlan rereads settings on job changes; preserve edits awaiting a save.
    if timerSettingsDirtyAt and timerSettingsRef and s ~= timerSettingsRef then
        s = timerSettingsRef
        FightPlan.settings.partyPlanTimers = s
    end
    if s == nil then s = {}; FightPlan.settings.partyPlanTimers = s end
    assert(type(s) == "table", "[PartyPlan.TimerSettings] partyPlanTimers must be a table")
    if timerSettingsRef ~= s then
        for key, default in pairs(timerDefaults) do
            if s[key] == nil then s[key] = default end
            if type(default) == "number" then
                assert(finiteNumber(s[key]), "[PartyPlan.TimerSettings] invalid " .. key .. "=" .. tostring(s[key]))
            end
        end
        assert(s.growth == "up" or s.growth == "down", "[PartyPlan.TimerSettings] invalid growth=" .. tostring(s.growth))
        assert(s.width >= 180 and s.width <= 800 and s.height >= 28 and s.height <= 80
            and s.spacing >= 0 and s.spacing <= 24, "[PartyPlan.TimerSettings] dimensions outside supported range")
        for _, key in ipairs({"r", "g", "b", "a"}) do
            assert(s[key] >= 0 and s[key] <= 1, "[PartyPlan.TimerSettings] invalid color " .. key .. "=" .. tostring(s[key]))
        end
        timerSettingsRef = s
        placeTimerAnchor = true
    end
    PartyPlan.timerHeight, PartyPlan.timerSpacing = s.height, s.spacing
    return s
end

local function timerSettingsChanged()
    timerSettingsDirtyAt = Now()
end

local function saveTimerSettings()
    if not timerSettingsDirtyAt then return end
    local path = FightPlan.paths.settingsFile
    local ok, err = FightPlan.IO.Write(path, FightPlan.settings)
    if not ok then error("[PartyPlan.TimerSettings.Save] " .. path .. ": " .. tostring(err), 0) end
    timerSettingsDirtyAt = nil
end

-- Named timers are unique: setting an existing name restarts it in its original slot.
-- Omitted names append using the lowest free auto1, auto2, ... identifier.
function PartyPlan.SetTimer(seconds, label, name)
    assert(finiteNumber(seconds) and seconds > 0 and finiteNumber(seconds * 1000),
        "[PartyPlan.SetTimer] positive finite seconds required; seconds=" .. tostring(seconds) .. ", name=" .. tostring(name))
    assert(label == nil or type(label) == "string", "[PartyPlan.SetTimer] label must be a string or nil")
    assert(name == nil or (type(name) == "string" and name:find("%S")), "[PartyPlan.SetTimer] name must be a non-blank string or nil")
    if name == nil then
        local used = {}
        for _, existing in ipairs(PartyPlan.timers) do
            if existing.name then used[existing.name] = true end
        end
        local number = 1
        while used["auto" .. number] do number = number + 1 end
        name = "auto" .. number
    end
    local timer = { timer = Now(), limit = seconds * 1000, string = label or "", name = name }
    if name then
        for i, existing in ipairs(PartyPlan.timers) do
            if existing.name == name then PartyPlan.timers[i] = timer; return name end
        end
    end
    table.insert(PartyPlan.timers, timer)
    return name
end
PartyPlan.setTimer = PartyPlan.SetTimer

function PartyPlan.RemoveTimer(name)
    assert(type(name) == "string" and name:find("%S"), "[PartyPlan.RemoveTimer] non-blank timer name required")
    local removed = 0
    for i = #PartyPlan.timers, 1, -1 do
        if PartyPlan.timers[i].name == name then table.remove(PartyPlan.timers, i); removed = removed + 1 end
    end
    return removed -- Zero is a normal no-match (already expired or removed).
end

function PartyPlan.resetTimers(indexOrLabel)
    if indexOrLabel == nil then
        local count = #PartyPlan.timers
        PartyPlan.timers = {}
        return count
    end
    if type(indexOrLabel) == "number" then
        assert(finiteNumber(indexOrLabel) and indexOrLabel >= 1 and indexOrLabel % 1 == 0,
            "[PartyPlan.resetTimers] positive integer index required; index=" .. tostring(indexOrLabel))
        if indexOrLabel > #PartyPlan.timers then return 0 end
        table.remove(PartyPlan.timers, indexOrLabel)
        return 1
    end
    assert(type(indexOrLabel) == "string", "[PartyPlan.resetTimers] expected index, label/name, or nil")
    local removed = 0
    for i = #PartyPlan.timers, 1, -1 do
        local timer = PartyPlan.timers[i]
        if timer.name == indexOrLabel or timer.string == indexOrLabel then
            table.remove(PartyPlan.timers, i)
            removed = removed + 1
        end
    end
    return removed
end

local function timerTrace(err)
    local message = "[PartyPlan.DrawTimers] " .. tostring(err)
    if debug and debug.traceback then return debug.traceback(message, 2) end
    return message
end

-- Native windows only host draw-list bars; errors unwind the style/window stacks.
local function timerWindow(name, flags, editing, draw)
    local g = FightPlan.gui
    g.pushTheme()
    g.pushColor4(GUI.Col_WindowBg, editing and g.C.bg_window or {0, 0, 0, 0})
    g.pushColor4(GUI.Col_Border, editing and g.C.accent_hov or {0, 0, 0, 0})
    GUI:PushStyleVar(GUI.StyleVar_WindowPadding, 0, 0)
    GUI:PushStyleVar(GUI.StyleVar_WindowMinSize, 1, 1)
    local began = false
    local ok, err = xpcall(function()
        local visible = GUI:Begin(name, true, flags)
        began = true
        if visible then draw() end
    end, timerTrace)
    if began then GUI:End() end
    GUI:PopStyleVar(2)
    GUI:PopStyleColor(2)
    g.popTheme()
    if not ok then error(err, 0) end
end

function PartyPlan.DrawTimers()
    local s = getTimerSettings()
    -- Reverse removal also handles several adjacent expirations in one frame.
    for i = #PartyPlan.timers, 1, -1 do
        if TimeSince(PartyPlan.timers[i].timer) >= PartyPlan.timers[i].limit then table.remove(PartyPlan.timers, i) end
    end
    if timerSettingsDirtyAt and TimeSince(timerSettingsDirtyAt) >= 500 and not GUI:IsMouseDown(0) then saveTimerSettings() end
    local unlocked = PartyPlan.timerAnchorUnlocked
    local flags = GUI.WindowFlags_NoTitleBar + GUI.WindowFlags_NoCollapse + GUI.WindowFlags_NoScrollbar + GUI.WindowFlags_NoScrollWithMouse

    if unlocked then
        if placeTimerAnchor then
            GUI:SetNextWindowPos(s.x, s.y, GUI.SetCond_Always)
            GUI:SetNextWindowSize(s.width, s.height, GUI.SetCond_Always)
            placeTimerAnchor = false
        end
        timerWindow("##PartyPlanTimerAnchor", flags, true, function()
            local x, y = GUI:GetWindowPos()
            local width = math.max(180, math.min(800, GUI:GetWindowWidth()))
            local height = math.max(28, math.min(80, GUI:GetWindowHeight()))
            if width ~= GUI:GetWindowWidth() or height ~= GUI:GetWindowHeight() then placeTimerAnchor = true end
            if x ~= s.x or y ~= s.y or width ~= s.width or height ~= s.height then
                s.x, s.y, s.width, s.height = x, y, width, height
                PartyPlan.timerHeight = height
                timerSettingsChanged()
            end
            GUI:SetCursorPos(10, math.max(4, (height - 16) * 0.5))
            FightPlan.gui.coloredText(FightPlan.gui.C.text, "Timer Anchor  |  Drag / Resize")
        end)
    else
        placeTimerAnchor = true
    end

    -- Preview rows never enter the live array, expire, or affect timer removal.
    local count = #PartyPlan.timers + (unlocked and 3 or 0)
    if count == 0 then return end
    local pitch = s.height + s.spacing
    local firstOffset = unlocked and 1 or 0
    local topY = s.growth == "up" and s.y - (count - 1 + firstOffset) * pitch or s.y + firstOffset * pitch
    GUI:SetNextWindowPos(s.x, topY, GUI.SetCond_Always)
    GUI:SetNextWindowSize(s.width, count * pitch - s.spacing, GUI.SetCond_Always)
    timerWindow(PartyPlan.parentWindowName, flags + GUI.WindowFlags_NoMove + GUI.WindowFlags_NoResize + GUI.WindowFlags_NoInputs, false, function()
        local x, y = GUI:GetWindowPos()
        local function drawRow(slot, label, remaining, fraction)
            local row = s.growth == "up" and count - slot or slot - 1
            FightPlan.gui.timerBar(x, y + row * pitch, s.width, s.height, label, remaining, fraction, {s.r, s.g, s.b, s.a})
        end
        if unlocked then
            drawRow(1, "Preview - 80%", 24, 0.8)
            drawRow(2, "Preview - 50%", 15, 0.5)
            drawRow(3, "Preview - 20%", 6, 0.2)
        end
        for i, timer in ipairs(PartyPlan.timers) do
            local remaining = math.max(0, timer.limit - TimeSince(timer.timer))
            drawRow(i + (unlocked and 3 or 0), timer.string, remaining / 1000, remaining / timer.limit)
        end
    end)
end

function PartyPlan.DrawTimerSettings()
    local s = getTimerSettings()
    local g = FightPlan.gui
    local W = g.UI.INPUT_W
    local changed
    g.captionDivider("Timer Layout")
    g.formRow("Anchor", "Unlock to drag the anchor and resize each bar. Three previews show 80%, 50%, and 20% remaining.", function()
        g.toggleButton(PartyPlan.timerAnchorUnlocked and "Lock Anchor" or "Unlock Anchor", "PPTimerUnlock", PartyPlan.timerAnchorUnlocked, function()
            PartyPlan.timerAnchorUnlocked = not PartyPlan.timerAnchorUnlocked
            placeTimerAnchor = true
            if not PartyPlan.timerAnchorUnlocked then saveTimerSettings() end
        end, W, g.UI.BTN_H)
    end)
    g.formRow("Growth", "Direction new bars stack from the anchor.", function()
        g.segmented("PPTimerGrowth", {"Down", "Up"}, s.growth == "down" and 1 or 2, function(i)
            s.growth = i == 1 and "down" or "up"; timerSettingsChanged()
        end)
    end)
    s.width, changed = g.formSlider("Width", nil, "PPTimerWidth", s.width, 180, 800, "%d px", true)
    if changed then placeTimerAnchor = true; timerSettingsChanged() end
    s.height, changed = g.formSlider("Height", nil, "PPTimerHeight", s.height, 28, 80, "%d px", true)
    if changed then placeTimerAnchor = true; timerSettingsChanged() end
    s.spacing, changed = g.formSlider("Spacing", nil, "PPTimerSpacing", s.spacing, 0, 24, "%d px", true)
    if changed then timerSettingsChanged() end
    g.formRow("Bar Color", nil, function()
        GUI:PushItemWidth(W)
        s.r, s.g, s.b, s.a, changed = GUI:ColorEdit4("##PPTimerColor", s.r, s.g, s.b, s.a)
        GUI:PopItemWidth()
    end)
    if changed then timerSettingsChanged() end
    GUI:SetCursorPosX(g.UI.LABEL_W)
    if GUI:Button("Reset Layout##PPTimerReset", W, g.UI.BTN_H) then
        for key, value in pairs(timerDefaults) do s[key] = value end
        placeTimerAnchor = true
        timerSettingsChanged()
        saveTimerSettings()
    end
    g.sectionHeader("Add a Timer")
    g.formRow("Name", "Adding the same name restarts its timer. Leave empty to use the first free auto1, auto2, ... name.", function()
        GUI:PushItemWidth(W)
        newTimerName = GUI:InputText("##PPTimerName", newTimerName)
        GUI:PopItemWidth()
    end)
    g.formRow("Label", "Text shown on the bar. Defaults to the name.", function()
        GUI:PushItemWidth(W)
        newTimerLabel = GUI:InputText("##PPTimerLabel", newTimerLabel)
        GUI:PopItemWidth()
    end)
    g.formRow("Duration", nil, function()
        GUI:PushItemWidth(W - 14)
        newTimerSeconds = GUI:InputInt("##PPTimerSeconds", newTimerSeconds)
        GUI:PopItemWidth()
        GUI:SameLine(0, 4)
        g.coloredText(g.C.text_mute, "%s", "s")
    end)
    GUI:SetCursorPosX(g.UI.LABEL_W)
    if g.colorButton("Add / Restart Timer##PPTimerAdd", g.PAL_GREEN, W) then
        local name = newTimerName:find("%S") and newTimerName or nil
        local label = newTimerLabel ~= "" and newTimerLabel or name or "Timer"
        PartyPlan.SetTimer(newTimerSeconds, label, name)
    end
    g.sectionHeader("Active Timers (" .. #PartyPlan.timers .. ")")
    if #PartyPlan.timers == 0 then
        g.coloredText(g.C.text_mute, "%s", "No active timers.")
    else
        if g.colorButton("Remove All##PPTimerClear", g.PAL_RED) then PartyPlan.resetTimers() end
        local removeIndex
        for i, timer in ipairs(PartyPlan.timers) do
            if GUI:Button("Remove##PPTimerRemove" .. i, 0, g.UI.ROW_H) then removeIndex = i end
            GUI:SameLine()
            local remaining = math.max(0, (timer.limit - TimeSince(timer.timer)) / 1000)
            GUI:TextWrapped((timer.name or timer.string) .. "  -  " .. string.format("%.1fs", remaining))
        end
        if removeIndex then PartyPlan.resetTimers(removeIndex) end
    end
end


function PartyPlan.getFurthestInCardinal(cardinal,entitylistString,role) -- provide a string cardinal n,s,w,e, and optional entitylistString like contentid=1234, defaults to myparty
    local roleTable = {
        ["healer"] = {6,24,28,33,40},
        ["dps"] = {2,4,5,7,20,22,23,25,26,27,29,30,31,34,35,38,39},
        ["tank"] = {1,3,19,21,32,37}
    }

    if cardinal == nil then return d("Please give a cardinal direction to check either n,s,w,e.") end
    if entitylistString == nil then entitylistString = "myparty"  end

    local sortedTable = {}
    local pl = TensorCore.entityList(tostring(entitylistString))
    for id,ent in pairs(pl) do
        if role ~= nil then
            if table.contains(roleTable[role],ent.job) then
                table.insert(sortedTable,{id = id,z = ent.pos.z,x = ent.pos.x})
            end
        else
            table.insert(sortedTable,{id = id,z = ent.pos.z,x = ent.pos.x})

        end
    end
    if table.valid(sortedTable) then
        if cardinal == "n" then
            table.sort(sortedTable,function(a,b) return a.z < b.z  end)
        end
        if cardinal == "s" then
            table.sort(sortedTable,function(a,b) return a.z > b.z  end)
        end
        if cardinal == "w" then
            table.sort(sortedTable,function(a,b) return a.x < b.x  end)
        end
        if cardinal == "e" then
            table.sort(sortedTable,function(a,b) return a.x > b.x  end)
        end
        return sortedTable[1].id
    else
        d("tried to iterate myparty without being in a party, returning playerID")
        return TensorCore.mGetPlayer().id
    end
end

function dd(string)
    d(string)
    TensorCore.timelineLogToFile(string.." \n")
end



function PartyPlan.IsPosInPolyAndDraw(x, y, drawer, ...)
    local vertices = {...}
    local points = {}

    for i = 1, #vertices - 1, 2 do
        points[#points + 1] = {x = vertices[i], y = vertices[i + 1]}
    end

    local i, j = #points, #points
    local inside = false

    for i = 1, #points do
        if ((points[i].y < y and points[j].y >= y) or (points[j].y < y and points[i].y >= y)) and (points[i].x <= x or points[j].x <= x) then
            if (points[i].x + (y - points[i].y) / (points[j].y - points[i].y) * (points[j].x - points[i].x) < x) then
                inside = not inside
            end
        end

        if drawer ~= nil then
             drawer:addLine(points[i].x, Player.pos.y, points[i].y,points[j].x,Player.pos.y, points[j].y,0,true)
        end
        j = i
    end

    return inside
end

local function GenerateRectangleInFrontOfPlayer(Player, distance, width, height)
    local playerPos = Player.pos
    local playerHeading = Player.pos.h
    if Player:GetTarget() ~= nil then
        playerHeading = TensorCore.getHeadingToTarget(Player.pos,Player:GetTarget().pos)
    end
    -- Calculate the position of the center of the rectangle in front of the player
    local offsetX = distance * math.sin(playerHeading)
    local offsetZ = distance * math.cos(playerHeading)
    local centerPos = { x = playerPos.x + offsetX, z = playerPos.z + offsetZ }

    -- Calculate the direction vector perpendicular to the player's heading
    local perpendicularHeading = playerHeading + math.pi / 2

    -- Calculate the positions of the four corners of the rectangle
    local halfWidth = width / 2
    local halfHeight = height / 2
    local topLeftX = centerPos.x - halfWidth * math.sin(perpendicularHeading)
    local topLeftZ = centerPos.z - halfWidth * math.cos(perpendicularHeading)
    local topRightX = centerPos.x + halfWidth * math.sin(perpendicularHeading)
    local topRightZ = centerPos.z + halfWidth * math.cos(perpendicularHeading)
    local bottomLeftX = topLeftX + height * math.sin(playerHeading)
    local bottomLeftZ = topLeftZ + height * math.cos(playerHeading)
    local bottomRightX = topRightX + height * math.sin(playerHeading)
    local bottomRightZ = topRightZ + height * math.cos(playerHeading)

    -- Form the vertices to represent the rectangle
    local vertices = {
        topLeftX, topLeftZ,
        topRightX, topRightZ,
        bottomRightX, bottomRightZ,
        bottomLeftX, bottomLeftZ,
        topLeftX, topLeftZ -- Closing vertex
    }
    local drawer = TensorCore.getStaticDrawer(1879113472)
    drawer:addLine(topLeftX,Player.pos.y, topLeftZ, topRightX,Player.pos.y, topRightZ)
    drawer:addLine(topRightX,Player.pos.y, topRightZ, bottomRightX,Player.pos.y, bottomRightZ)
    drawer:addLine(bottomRightX, Player.pos.y, bottomRightZ, bottomLeftX,Player.pos.y, bottomLeftZ)
    drawer:addLine(bottomLeftX,Player.pos.y, bottomLeftZ, topLeftX, Player.pos.y,topLeftZ)
    return vertices
end

function PartyPlan.rangedLBCheck(number,distance,width,height)
    local vertices = GenerateRectangleInFrontOfPlayer(Player,distance or 0,width or 5,height or 30)
    local count = 0
    for id,ent in pairs(TensorCore.entityList("attackable")) do
        local inside = PartyPlan.IsPosInPolyAndDraw(ent.pos.x,ent.pos.z,nil,unpack(vertices))
        if inside then
            count = count+1
        end
    end
    return count >= number

end


local function calculateDistance(coord1, coord2)
    return math.sqrt((coord1.x - coord2.x)^2 + (coord1.y - coord2.y)^2 + (coord1.z - coord2.z)^2)
end

--[[ returns position table of best x,y,z coords to place aoe
-- targets is a table with positions that you can get from either iterating an entitylist example:
local targets = {}
for id,ent in pairs(TensorCore.entityList("contentid=541,maxdistance=30")) do table.insert(targets,ent.pos)  end

radius is the radius of your AoE spell that you want to aim

scanCenter(optional) is a position table of where you want to scan for targets, it defaults to Player.pos

scanRadius(optional) is how far you want to scan from scanCenter, this is usually the range of your spell, default 25.pos

noVariance(optional) default it will have some random variance of where to hit, set this to true to have no variance



DSR example for LB2 with draws with draws using flag position on map as the scan position (go into o12s to test)
Put it in a onFrame reaction
---------------

local drawer = TensorCore.getMoogleDrawer()
local redStaticDrawer = TensorCore.getStaticDrawer(GUI:ColorConvertFloat4ToU32(1, 0, 0, 0.3), 2)
local targets = {
    {x = 100.000, y = 0.000, z = 86.000},
    {x = 90.101, y = 0.000, z = 90.101},
    {x = 109.899, y = 0.000, z = 90.100},
    {x = 86.000, y = 0.000, z = 100.000},
    {x = 90.101, y = 0.000, z = 109.899},
    {x = 100.000, y = 0.000, z = 114.000},
    {x = 109.899, y = 0.000, z = 109.899},
    {x = 114.000, y = 0.000, z = 100.000}
}
for k, v in pairs(targets) do
    redStaticDrawer:addCircle(v.x, Player.pos.y, v.z, 1, nil)
end

local flagPos = GetMapFlagPosition()
if flagPos then
    flagPos.y = Player.pos.y
    local scanCenter = flagPos
    local scanRadius = 10
    local radius = 10
    local coords = PartyPlan.findBestCoordinate(targets, radius,scanCenter,scanRadius)
    local redStaticDrawer = TensorCore.getStaticDrawer(GUI:ColorConvertFloat4ToU32(1, 0, 0, 0.1), 2)
    drawer:addCircle(math.random(-10, 10) / 100 + coords.x, Player.pos.y, math.random(-10, 10) / 100 + coords.z, radius) -- math random for some more randomized positions
end
self.used = true
local targets = {};for id,ent in pairs(TensorCore.entityList("contentid=541,maxdistance=30")) do table.insert(targets,ent.pos)  end ActionList:Get(1,188):Cast(PartyPlan.findBestCoordinate(targets,25).x,PartyPlan.findBestCoordinate(targets,25).y,PartyPlan.findBestCoordinate(targets,25).z)

]]--
function PartyPlan.findBestCoordinate(targets, radius, scanCenter, scanRadius, noVariance)
    scanCenter = scanCenter or {x = Player.pos.x, y = Player.pos.y, z = Player.pos.z}
    scanRadius = scanRadius or 25
    local variance = 0
    if noVariance == nil then
        variance = math.random(-10,10)/100
    end

    local bestCoordinate = {x = 0, y = 0, z = 0}
    local maxTargetsHit = 0
    for _, target1 in pairs(targets) do
        for _, target2 in pairs(targets) do
            local midpoint = {
                x = (target1.x + target2.x) / 2,
                y = (target1.y + target2.y) / 2,
                z = (target1.z + target2.z) / 2
            }
            local distanceToCenter = calculateDistance(midpoint, scanCenter)
            if distanceToCenter <= scanRadius then
                local targetsHit = 0

                for _, targetPos in pairs(targets) do
                    -- Incorporate hit radius of the target into distance calculation
                    local distanceToTarget = calculateDistance(midpoint, targetPos) - targetPos.hitradius
                    if distanceToTarget <= radius then
                        targetsHit = targetsHit + 1
                    end
                end

                if targetsHit > maxTargetsHit then
                    maxTargetsHit = targetsHit
                    bestCoordinate = midpoint
                end
            end
        end
    end
    if noVariance == nil then
        bestCoordinate.x = variance+bestCoordinate.x
        bestCoordinate.z = variance+bestCoordinate.z
    end
    return bestCoordinate
end

-- User-supplied soundengine.exe and sound files live in Settings\Sounds (never deployed).
function PartyPlan.playSound(sound)
    local dir = FightPlan.paths.soundsDir
    local engine = dir .. [[\soundengine.exe]]
    local file = dir .. [[\]] .. tostring(sound)
    if type(sound) ~= "string" or sound == "" then
        d("[FightPlan] playSound ERROR: sound must be a filename, got " .. tostring(sound))
        return false
    end
    if not FileExists(engine) then
        d("[FightPlan] playSound ERROR: missing " .. engine)
        return false
    end
    if not FileExists(file) then
        d("[FightPlan] playSound ERROR: missing " .. file)
        return false
    end
    local p, err = io.popen('"' .. engine .. '" "' .. file .. '"')
    if not p then
        d("[FightPlan] playSound ERROR: io.popen failed for " .. file .. ": " .. tostring(err))
        return false
    end
    p:close()
    return true
end
function PartyPlan.startRecording(commandLocation,ip,savePath,debug)
    local date = os.date("*t");
    local identifier = os.time()
    local currdate = string.format("%d-%02d-%02d", date.year, date.month, date.day)
    local foldername = string.gsub(savePath.."\\"..GetMapName(Player.localmapid).."\\"..currdate, "%s", "-");

    if not FolderExists(foldername) then
        FolderCreate(foldername)
    end
    local filename = string.gsub(idtoJob[Player.job].."-"..identifier, "%s", "-");
    dd("New recording started: "..foldername.."\\"..filename)
    local p = io.popen(commandLocation.. " /server="..ip.." /command=SetRecordDirectory,recordDirectory="..foldername.." /command=SetProfileParameter,parameterCategory=Output,parameterName=FilenameFormatting,parameterValue="..filename.." /startrecording",r)
    if debug == true then local output = p:read('*all')
        p:close()
        dd(output)
    end
end
function PartyPlan.stopRecording(commandLocation,ip,savePath)
    io.popen(commandLocation.. " /server="..ip.." /stoprecording",r)
end

-- returns the heading of most targets hit with a cone, takes source pos (usually player), table of target positions tbl = {{x = 100,y=0,z=100},{x = 102,y=0,z=103}} etc
-- specify cone angle(width) in radians and radius(length) example below:
--
-- local elist = TensorCore.entityList("chartype=4")
-- local targets = {}
-- for id,ent in pairs(elist) do
-- table.insert(targets,ent.pos)
-- end
-- local heading = PartyPlan.getMostClusteredCone(Player.pos, targets, math.rad(90), 20)
-- this would give us the best heading to hit as many chartype4 (players) as possible from the player pos with a 90 degree cone that has a 20 yds radius

function PartyPlan.getMostClusteredCone(playerPos, targets, coneAngle, coneRadius)
    local bestHeading = 0
    local maxTargetsHit = 0
    local bestCentroidX, bestCentroidZ

    for heading = 0, math.pi * 2, 0.05 do --mby adjust this for more accuracy vs potential lag (decreasing the 0.05 to 0.01 gives more accuracy but 5 times the amount of iteration)
        local targetsHit = 0
        local hitTargets = {}

        for _, targetPos in ipairs(targets) do
            local headingToTarget = TensorCore.getHeadingToTarget(playerPos,targetPos)
            local angleDiff = math.abs((heading - headingToTarget + math.pi) % (math.pi * 2) - math.pi)
            if angleDiff <= coneAngle / 2 and TensorCore.getDistance2d(playerPos, targetPos) <= coneRadius then
                targetsHit = targetsHit + 1
                table.insert(hitTargets, targetPos)
            end
        end
        local centerX, centerZ = 0, 0
        for _, pos in ipairs(hitTargets) do
            centerX = centerX + pos.x
            centerZ = centerZ + pos.z
        end
        centerX = centerX / #hitTargets
        centerZ = centerZ / #hitTargets
        if targetsHit > maxTargetsHit then
            maxTargetsHit = targetsHit
            bestHeading = TensorCore.getHeadingToTarget(playerPos,{x = centerX,y = 0,z = centerZ})
        end
    end
    return bestHeading
end


RegisterEventHandler("Gameloop.Draw", PartyPlan.draw, "PartyPlan-GUI")
