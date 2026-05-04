--[[
## CHANGELOG
1.1.3 - rc1 really, fixed so that if there are multiple profiles on fightplan for a single fight this lets us 
1.1.2 - fixed global variable initialization for dropdown defaults
1.1.1 - realistically no maintenance to be done here anymore. most things will be modularized and changelogs can go fuck off
1.1.0 - made the addon modular. thnx dedo
1.0.4 - added mitigation calculations. wip?
1.0.3 - added roletoindex for legacy purposes
1.0.2 - added fight settings for m1-m4 and all ultimates bar top. fuck top.
1.0.1 - added job and role functions
1.0.0 - initial release
]]

FightPlan = {
    GUI = {
        open = false,
        visible = false
    },
    currentJob = 0,
    settings = {},
    Food = nil,
    RoleToIndex = {
        ["M1"] = 1,
        ["M2"] = 2,
        ["R1"] = 3,
        ["R2"] = 4,
        ["MT"] = 5,
        ["OT"] = 6,
        ["H1"] = 7,
        ["H2"] = 8
    },
    version = "1.1.3",
    lastMapId = 0,
    --RaidMaps a bit of a legacy system since we fetch it from the duty name now but i am way too lazy to remove this! :)
    RaidMaps = {
        [1] = true,       -- Debug Map
        [1196] = true,    -- Ex1
        [1201] = true,    -- Ex2
        [1226] = true,    -- R1S
        [1228] = true,    -- R2S
        [1230] = true,    -- R3S
        [1232] = true,    -- R4S
        [1238] = true     -- Futures Rewritten (Ultimate)
    },
    ultimateRaidMaps = {
        [733] = true,  -- The Unending Coil of Bahamut
        [777] = true,   -- The Weapon's Refrain
        [887] = true,   -- The Epic of Alexander
        [968] = true,   -- Dragonsong's Reprise
        [1122] = true,  -- The Omega Protocol
        [1238] = true,  -- The Fatebreaker's Undoing
    },
    DebugMaps = {
        [1] = true,       -- Debug Map
        [339] = true,     -- Mists Debugging
        [340] = true      -- Lavender Debugging
    },
    AutoMarker = {
        [1] = true,       -- Debug Map
        [340] = true,     -- Lavender Debugging
        [777] = true,     -- The Weapon's Refrain (Ultimate)
        [1111] = true     -- The Omega Protocol (Ultimate)
    },
    HectorStrats = {
        [1226] = true     -- R1S
    },
    mapPlanGroups = {}
}

local function SaveSettings()
    local path = GetStartupPath() .. "\\LuaMods\\FightPlan\\settings.lua"
    persistence.store(path, FightPlan.settings)
end

local function isRaidDutyByName()
    local dutyInfo = Duty:GetActiveDutyInfo()
    if not dutyInfo or not dutyInfo.name then
        return false, nil
    end
    local dutyName = dutyInfo.name
    local isSavage = string.find(dutyName, "%(Savage%)") and true or false
    local isUltimate = string.find(dutyName, "%(Ultimate%)") and true or false
    local isExtreme = string.find(dutyName, "%(Extreme%)") and true or false
    local isChaotic = string.find(dutyName, "%(Chaotic%)") and true or false
    return (isSavage or isUltimate or isExtreme or isChaotic), dutyName
end

local function checkAndUpdateRaidMaps()
    if not Player then return end
    local currentMapId = Player.localmapid
    if currentMapId ~= FightPlan.lastMapId then
        d("[FightPlan] map changed to " .. tostring(currentMapId))
        FightPlan.lastMapId = currentMapId
        if not FightPlan.RaidMaps[currentMapId] then
            local isRaid, dutyName = isRaidDutyByName()
            if isRaid then
                d("[FightPlan] auto-detected raid: " .. dutyName .. " (Map ID: " .. currentMapId .. ")")
                FightPlan.RaidMaps[currentMapId] = true
                if not FightPlan.settings.RaidMaps then
                    FightPlan.settings.RaidMaps = {}
                end
                FightPlan.settings.RaidMaps[currentMapId] = true
                SaveSettings()
            end
        end
    end
end

local function InitializeDefaultSettings()
    for _, dropdown in ipairs(FightPlan.dropdowns) do
        if dropdown.useIndex then
            dropdown.defaultValue = 1
        else
            dropdown.defaultValue = dropdown.options[1]
        end
    end
    for _, checkbox in ipairs(FightPlan.checkboxes) do
        checkbox.defaultValue = false
    end
end

local function InitializeJobSettings(jobId)
    if not FightPlan.settings[jobId] then
        FightPlan.settings[jobId] = {}
    end
    
    local needsSave = false
    
    for _, dropdown in ipairs(FightPlan.dropdowns) do
        local conditionMet = false
        local success, result = pcall(dropdown.condition)
        if success then
            conditionMet = result
        else
            conditionMet = true
            d("[FightPlan] Warning: condition failed for " .. dropdown.id .. ": " .. tostring(result))
        end
        
        if conditionMet then
            if FightPlan.settings[jobId][dropdown.id] == nil then
                FightPlan.settings[jobId][dropdown.id] = dropdown.defaultValue
                needsSave = true
                d("[FightPlan] Setting default for " .. dropdown.id .. ": " .. tostring(dropdown.defaultValue))
            end
            FightPlan[dropdown.id] = FightPlan.settings[jobId][dropdown.id]
        end
    end
    
    for _, checkbox in ipairs(FightPlan.checkboxes) do
        local conditionMet = false
        local success, result = pcall(checkbox.condition)
        if success then
            conditionMet = result
        else
            conditionMet = true
            d("[FightPlan] Warning: condition failed for " .. checkbox.id .. ": " .. tostring(result))
        end
        
        if conditionMet then
            if FightPlan.settings[jobId][checkbox.id] == nil then
                FightPlan.settings[jobId][checkbox.id] = checkbox.defaultValue
                needsSave = true
            end
            FightPlan[checkbox.id] = FightPlan.settings[jobId][checkbox.id]
        end
    end
    
    if needsSave then
        SaveSettings()
    end
end

local function LoadSettings()
    if not Player or not Player.job or Player.job == 0 then
        d("[FightPlan] no job detected. if you entered a recording or loading into game, this is normal.")
        return
    end
    local currentJob = Player.job
    if currentJob ~= FightPlan.currentJob then
        local path = GetStartupPath() .. "\\LuaMods\\FightPlan\\settings.lua"
        local settings = persistence.load(path)
        FightPlan.settings = settings or {}
        FightPlan.settings.activePlan = FightPlan.settings.activePlan or {}
        if FightPlan.settings.tldrAccepted == nil then
            FightPlan.settings.tldrAccepted = false
        end
        if FightPlan.settings.RaidMaps then
            for mapId, value in pairs(FightPlan.settings.RaidMaps) do
                if value == true then
                    FightPlan.RaidMaps[mapId] = true
                end
            end
        else
            FightPlan.settings.RaidMaps = {}
            for mapId, value in pairs(FightPlan.RaidMaps) do
                if value == true then
                    FightPlan.settings.RaidMaps[mapId] = true
                end
            end
        end

        InitializeDefaultSettings()
        
        InitializeJobSettings(currentJob)
        
        if FightPlan.Role then
            FightPlan.RoleIndex = FightPlan.RoleToIndex[FightPlan.Role]
        end
        FightPlan.currentJob = currentJob
    end
    
    if FightPlan.lastMapId ~= Player.localmapid then
        InitializeDefaultSettings()
        InitializeJobSettings(Player.job)
    end
end

function FightPlan.DrawTLDR()
    if FightPlan.settings.tldrAccepted or FightPlan._tldrDismissed then return end

    local g = FightPlan.gui
    g.pushTheme()

    local sw, sh = GUI:GetScreenSize()
    local winW = 600
    GUI:SetNextWindowSize(winW, 0, "Always")
    GUI:SetNextWindowPos(sw / 2, sh / 2, "Always", 0.5, 0.5)
    local visible = GUI:Begin("FightPlan - Please Read", true, GUI.WindowFlags_AlwaysAutoResize + GUI.WindowFlags_NoMove)
    if visible then
        GUI:Text("Before using FightPlan, please read the following:")
        GUI:Separator()
        GUI:Dummy(0, 4)
        g.coloredText(g.C.text_dim, "%s", "FightPlan is a prioprietary AddOn not FPS optimized like Riku Products.")
        g.coloredText(g.C.text_dim, "%s", "Read the entire discord thread before using the addon.")
        g.coloredText(g.C.text_dim, "%s", "If you're using this without reading the thread, I will not provide you support and will probably block you!")
        GUI:Dummy(0, 8)
        GUI:Separator()
        GUI:Dummy(0, 4)
        if GUI:Button("OK") then
            FightPlan._tldrDismissed = true
        end
        GUI:SameLine()
        if GUI:Button("Decline") then
            FightPlan.settings.tldrAccepted = true
            SaveSettings()
        end
    end
    GUI:End()
    g.popTheme()
end

function FightPlan.Draw()
    if not FightPlan.settings.tldrAccepted then return end
    checkAndUpdateRaidMaps()

    
    if fpRed then fpRed.gradientIntensity = 0 end
    if fpGreen then fpGreen.gradientIntensity = 0 end
    if fpBlue then fpBlue.gradientIntensity = 0 end
    if fpYellow then fpYellow.gradientIntensity = 0 end
    if fpCyan then fpCyan.gradientIntensity = 0 end
    if fpPurple then fpPurple.gradientIntensity = 0 end
    if fpMagenta then fpMagenta.gradientIntensity = 0 end
    if not FightPlan.GUI.open then
        return
    end
    LoadSettings()
    local g = FightPlan.gui
    g.pushTheme()
    GUI:SetNextWindowSize(0, 0, GUI.SetCond_Appearing)
    FightPlan.GUI.visible, FightPlan.GUI.open = GUI:Begin("FightPlan", FightPlan.GUI.open, GUI.WindowFlags_AlwaysAutoResize)
    if FightPlan.GUI.visible then
        if not Player then GUI:End(); g.popTheme(); return end

        local partyOpen = PartyPlan and PartyPlan.GUI and PartyPlan.GUI.open or false
        g.toggleButton("PartyPlan", "fpPartyBtn", partyOpen, function()
            if PartyPlan and PartyPlan.GUI then
                PartyPlan.GUI.open = not PartyPlan.GUI.open
                PartyPlan.GUI.visible = PartyPlan.GUI.open
            end
        end, 80, g.UI.BTN_H)
        GUI:Separator()

        local currentMapID = Player.localmapid
        local conflictGroup = FightPlan.mapPlanGroups[currentMapID]

        if conflictGroup and #conflictGroup > 1 then
            FightPlan.settings.activePlan = FightPlan.settings.activePlan or {}
            if not FightPlan.settings.activePlan[currentMapID] then
                FightPlan.settings.activePlan[currentMapID] = conflictGroup[1]
            end
            local savedPlan = FightPlan.settings.activePlan[currentMapID]
            local stillExists = false
            for _, n in ipairs(conflictGroup) do
                if n == savedPlan then stillExists = true; break end
            end
            if not stillExists then
                FightPlan.settings.activePlan[currentMapID] = conflictGroup[1]
            end
            local activePlan = FightPlan.settings.activePlan[currentMapID]
            local selectedIdx = 1
            for i, name in ipairs(conflictGroup) do
                if name == activePlan then selectedIdx = i; break end
            end
            g.alignedLabel("Active Plan")
            GUI:PushItemWidth(g.UI.INPUT_W)
            local newIdx, changed = GUI:Combo("##ActivePlan", selectedIdx, conflictGroup)
            GUI:PopItemWidth()
            if changed then
                FightPlan.settings.activePlan[currentMapID] = conflictGroup[newIdx]
                SaveSettings()
            end
            GUI:Separator()
        end

        if not FightPlan.settings[Player.job] then GUI:End(); g.popTheme(); return end
        local hasAnySettings = false
        for _, dropdown in ipairs(FightPlan.dropdowns) do
            local conditionMet = false
            local success, result = pcall(dropdown.condition)
            if success then
                conditionMet = result
            else
                conditionMet = false
            end

            -- if multiple plans share this map, only show the active plan's elements. it should work idfk
            if conditionMet and dropdown.planSource and conflictGroup and #conflictGroup > 1 then
                local active = FightPlan.settings.activePlan and FightPlan.settings.activePlan[currentMapID]
                if active and dropdown.planSource ~= active then
                    conditionMet = false
                end
            end

            if conditionMet then
                hasAnySettings = true
                g.alignedLabel(dropdown.label)
                if GUI:IsItemHovered() then
                    GUI:SetTooltip(dropdown.tooltip)
                end
                GUI:PushItemWidth(g.UI.INPUT_W)
                if dropdown.id == "Role" then
                    local currentValue = FightPlan.settings[Player.job][dropdown.id]
                    local selectedIndex = 1
                    for i, opt in ipairs(dropdown.options) do
                        if opt == currentValue then
                            selectedIndex = i
                            break
                        end
                    end
                    local newIndex, changed = GUI:Combo("##" .. dropdown.id, selectedIndex, dropdown.options)
                    if changed then
                        local newRole = dropdown.options[newIndex]
                        FightPlan.settings[Player.job][dropdown.id] = newRole
                        FightPlan[dropdown.id] = newRole
                        FightPlan.RoleIndex = FightPlan.RoleToIndex[newRole]
                        SaveSettings()
                    end
                else
                    local currentValue = FightPlan.settings[Player.job][dropdown.id]
                    local selectedIndex = dropdown.useIndex and currentValue or 1
                    for i, opt in ipairs(dropdown.options) do
                        if not dropdown.useIndex and opt == currentValue then
                            selectedIndex = i
                        end
                    end
                    local newIndex, changed = GUI:Combo("##" .. dropdown.id, selectedIndex, dropdown.options)
                    if changed then
                        if dropdown.useIndex then
                            FightPlan.settings[Player.job][dropdown.id] = newIndex
                            FightPlan[dropdown.id] = newIndex
                        else
                            FightPlan.settings[Player.job][dropdown.id] = dropdown.options[newIndex]
                            FightPlan[dropdown.id] = dropdown.options[newIndex]
                        end
                        SaveSettings()
                    end
                end
                GUI:PopItemWidth()
            end
        end
        for _, checkbox in ipairs(FightPlan.checkboxes) do
            local conditionMet = false
            local success, result = pcall(checkbox.condition)
            if success then
                conditionMet = result
            else
                conditionMet = false
            end

            if conditionMet and checkbox.planSource and conflictGroup and #conflictGroup > 1 then
                local active = FightPlan.settings.activePlan and FightPlan.settings.activePlan[currentMapID]
                if active and checkbox.planSource ~= active then
                    conditionMet = false
                end
            end

            if conditionMet then
                hasAnySettings = true
                local value = FightPlan.settings[Player.job][checkbox.id]
                if FightPlan.settings[Player.job][checkbox.id] == nil then
                    FightPlan.settings[Player.job][checkbox.id] = false
                end
                local changed
                value, changed = GUI:Checkbox(checkbox.label, value)
                if GUI:IsItemHovered() then
                    GUI:SetTooltip(checkbox.tooltip)
                end
                if changed then
                    FightPlan.settings[Player.job][checkbox.id] = value
                    FightPlan[checkbox.id] = value
                    SaveSettings()
                end
            end
        end
        if not hasAnySettings then
            local mapLabel = (GetMapName and GetMapName(Player.localmapid)) or tostring(Player.localmapid)
            g.coloredText(g.C.text_dim, "No settings for %s", mapLabel)
        end
    end
    GUI:End()
    g.popTheme()
end

function FightPlan.Init()
    d("[FightPlan] by rompot. v" .. FightPlan.version)
    local path = GetStartupPath() .. "\\LuaMods\\FightPlan"
    if not FolderExists(path) then
        CreateFolder(path)
    end
    if not FightPlan.settings.RaidMaps then
        FightPlan.settings.RaidMaps = FightPlan.RaidMaps
    else
        for mapId, dutyName in pairs(FightPlan.settings.RaidMaps) do
            FightPlan.RaidMaps[mapId] = dutyName
        end
    end
    InitializeDefaultSettings()
    LoadSettings()
    if ml_gui and ml_gui.ui_mgr then
        ml_gui.ui_mgr:AddMember({
            id = "FFXIVMINION##MENU_FightPlan",
            name = "FightPlan",
            onClick = function()
                FightPlan.GUI.open = not FightPlan.GUI.open
            end,
            tooltip = "FightPlan is a Reaction settings menu system.",
            texture    = GetStartupPath() ..
                      [[\LuaMods\FightPlan\icon.png]],
        }, "FFXIVMINION##MENU_HEADER")
    end
    if Argus2 and Argus2.ShapeDrawer then
        fpRed     = Argus2.ShapeDrawer:new(2046820607, nil, 2046820607, 4294967295, 1.5)
        fpGreen   = Argus2.ShapeDrawer:new(2046885639, nil, 2046885639, 4294967295, 1.5)
        fpBlue    = Argus2.ShapeDrawer:new(2063542272, nil, 2063542272, 4294967295, 1.5)
        fpYellow  = Argus2.ShapeDrawer:new(2046871039, nil, 2046871039, 4294967295, 1.5)
        fpCyan    = Argus2.ShapeDrawer:new(2057633536, nil, 2057633536, 4294967295, 1.5)
        fpPurple  = Argus2.ShapeDrawer:new(2063532106, nil, 2063532106, 4294967295, 1.5)
        fpMagenta = Argus2.ShapeDrawer:new(2063532277, nil, 2063532277, 4294967295, 1.5)
        fpRed.gradientIntensity = 0
        fpGreen.gradientIntensity = 0
        fpBlue.gradientIntensity = 0
        fpYellow.gradientIntensity = 0
        fpCyan.gradientIntensity = 0
        fpPurple.gradientIntensity = 0
        fpMagenta.gradientIntensity = 0
    else
        d("[FightPlan] WARNING: Argus2 not found — shape drawing disabled")
        local stub = { gradientIntensity = 0 }
        fpRed = stub; fpGreen = stub; fpBlue = stub
        fpYellow = stub; fpCyan = stub; fpPurple = stub; fpMagenta = stub
    end
end

local function loadConfigsFromFiles()
    FightPlan.dropdowns = {}
    FightPlan.checkboxes = {}
    FightPlan.mapPlanGroups = {}
    local basePath = GetStartupPath() .. "\\LuaMods\\FightPlan\\plans"
    if not FolderExists(basePath) then
        FolderCreate(basePath)
        return
    end
    local function loadFromDirectory(dirPath)
        local fileList = FolderList(dirPath, [[(.*)lua$]], false)
        for _, fileName in pairs(fileList) do
            local filePath = dirPath .. "\\" .. fileName
            if FileExists(filePath) then
                d("[FightPlan] Loading file: " .. filePath)
                local fightConfigFunc = loadfile(filePath)
                if fightConfigFunc then
                    local success, fightConfig = pcall(fightConfigFunc)
                    if success and fightConfig and type(fightConfig) == "table" then
                        local globalMapID = fightConfig.mapID
                        local planName = fileName:match("([^/\\]+)%.lua$") or fileName

                        if globalMapID then
                            FightPlan.mapPlanGroups[globalMapID] = FightPlan.mapPlanGroups[globalMapID] or {}
                            local alreadyAdded = false
                            for _, n in ipairs(FightPlan.mapPlanGroups[globalMapID]) do
                                if n == planName then alreadyAdded = true; break end
                            end
                            if not alreadyAdded then
                                table.insert(FightPlan.mapPlanGroups[globalMapID], planName)
                            end
                        end

                        if fightConfig.dropdowns and type(fightConfig.dropdowns) == "table" then
                            for _, dropdown in ipairs(fightConfig.dropdowns) do
                                if dropdown.condition == nil then
                                    dropdown.condition = function() return true end
                                end
                                if globalMapID then
                                    local originalCondition = dropdown.condition
                                    dropdown.condition = function() return Player.localmapid == globalMapID and originalCondition() end
                                end
                                dropdown.planSource = planName
                                table.insert(FightPlan.dropdowns, dropdown)
                            end
                        end
                        if fightConfig.checkboxes and type(fightConfig.checkboxes) == "table" then
                            for _, checkbox in ipairs(fightConfig.checkboxes) do
                                if checkbox.condition == nil then
                                    checkbox.condition = function() return true end
                                end
                                if globalMapID then
                                    local originalCondition = checkbox.condition
                                    checkbox.condition = function() return Player.localmapid == globalMapID and originalCondition() end
                                end
                                checkbox.planSource = planName
                                table.insert(FightPlan.checkboxes, checkbox)
                            end
                        end
                        d("[FightPlan] Successfully loaded: " .. fileName)
                    else
                        d("[FightPlan] Error loading: " .. fileName)
                        if not success then
                            d("[FightPlan] Error: " .. tostring(fightConfig))
                        end
                    end
                else
                    d("[FightPlan] Could not load file: " .. fileName)
                end
            end
        end
        local subDirList = FolderList(dirPath, nil, true)
        for _, subDir in pairs(subDirList) do
            if FolderExists(dirPath .. "\\" .. subDir) then
                loadFromDirectory(dirPath .. "\\" .. subDir)
            end
        end
    end
    loadFromDirectory(basePath)
    d("[FightPlan] Loaded " .. #FightPlan.dropdowns .. " dropdowns and " .. #FightPlan.checkboxes .. " checkboxes")
end

loadConfigsFromFiles()
do
    local _path = GetStartupPath() .. "\\LuaMods\\FightPlan\\settings.lua"
    local _s = persistence.load(_path)
    if _s then FightPlan.settings = _s end
end
RegisterEventHandler("Module.Initalize", FightPlan.Init, "FightPlan.Init")
RegisterEventHandler("Gameloop.Update", LoadSettings, "FightPlan.Update")
RegisterEventHandler("Gameloop.Draw", FightPlan.Draw, "FightPlan.Draw")
RegisterEventHandler("Gameloop.Draw", FightPlan.DrawTLDR, "FightPlan.DrawTLDR")