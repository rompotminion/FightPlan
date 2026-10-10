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
    version = "2.0.0",
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

-- ── Paths ────────────────────────────────────────────────────────────────
-- Every file FightPlan reads or writes is built from these. User data lives
-- under Settings\ (layout: docs/deployment.md); plans\ is shipped code.
FightPlan.paths = {}
FightPlan.paths.addonDir     = GetStartupPath() .. [[\LuaMods\FightPlan]]
FightPlan.paths.plansDir     = FightPlan.paths.addonDir .. [[\plans]]
FightPlan.paths.settingsDir  = FightPlan.paths.addonDir .. [[\Settings]]
FightPlan.paths.settingsFile = FightPlan.paths.settingsDir .. [[\Shared.lua]]
FightPlan.paths.partyLegacyDir = FightPlan.paths.settingsDir .. [[\Party\Legacy]]

-- Older builds kept settings.lua and partySavedFiles\ in the addon root.
-- tools\DataMigrate.ps1 moves them (and stray root files) into Settings\.
-- Runs synchronously at load, before anything reads settings, and only while
-- an old file is still present.
function FightPlan.MigrateDataLayout()
    local P = FightPlan.paths
    if not FileExists(P.addonDir .. [[\settings.lua]]) and not FolderExists(P.addonDir .. [[\partySavedFiles]]) then
        if not FolderExists(P.settingsDir) then FolderCreate(P.settingsDir) end
        if not FolderExists(P.settingsDir) then
            d("[FightPlan] ERROR: could not create " .. P.settingsDir .. "; settings will not save.")
            return false
        end
        return true
    end
    local script = P.addonDir .. [[\tools\DataMigrate.ps1]]
    if not FileExists(script) then
        d("[FightPlan] ERROR: settings migration needed but " .. script .. " is missing; settings will look empty until it runs.")
        return false
    end
    if not (type(io) == "table" and type(io.popen) == "function") then
        d("[FightPlan] ERROR: settings migration needed but io.popen is unavailable; settings will look empty.")
        return false
    end
    local cmd = 'powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' .. script ..
                '" -Root "' .. P.addonDir .. '" 2>&1'
    local h, openErr = io.popen(cmd, "r")
    if not h then
        d("[FightPlan] ERROR: settings migration could not start (io.popen): " .. tostring(openErr))
        return false
    end
    local out = h:read("*all") or ""
    h:close()
    local ok = false
    for line in string.gmatch(out, "[^\r\n]+") do
        d("[FightPlan] settings migration: " .. line)
        if line == "OK" then ok = true end
    end
    if not ok then
        d("[FightPlan] ERROR: settings migration failed; old files were left in place. Output: " .. out)
    end
    return ok
end
FightPlan.MigrateDataLayout()

-- ── Storage shim ─────────────────────────────────────────────────────────
-- The platform removed the global `persistence` table, which crashed this
-- addon on load. Reads now use loadfile(), which parses both the old
-- persistence.store output and this shim's output (both are chunks that
-- return a table), so the existing settings.lua keeps loading untouched.
--
-- Writes deliberately do NOT use FileSave: it does not track tables it has
-- already visited, so one cyclic reference sends it into unbounded recursion.
-- This addon's settings.lua contains a `multiRefObjects` block, which is
-- exactly persistence telling us the data has multiply-referenced tables.
-- The serializer below has cycle detection, a depth cap and a size budget,
-- and builds the whole document in memory before opening the file so a fault
-- can never truncate good data.
FightPlan.IO = FightPlan.IO or {}

local function fpTrace(err)
    return debug and debug.traceback and debug.traceback(tostring(err), 2) or tostring(err)
end

function FightPlan.IO.Read(path)
    assert(type(path) == "string" and path ~= "", "[FightPlan.IO.Read] path is required")
    assert(type(FileExists) == "function", "[FightPlan.IO.Read] FileExists unavailable")
    if not FileExists(path) then return nil end -- A new installation has no settings yet.
    local chunk, loadError = loadfile(path)
    if not chunk then error("[FightPlan.IO.Read] " .. path .. ": " .. tostring(loadError), 0) end
    local okRun, result = xpcall(chunk, fpTrace)
    if not okRun then error("[FightPlan.IO.Read] " .. path .. ": " .. tostring(result), 0) end
    if type(result) ~= "table" then error("[FightPlan.IO.Read] " .. path .. ": expected table, got " .. type(result), 0) end
    return result
end

local FP_MAX_DEPTH = 64
local FP_MAX_PARTS = 2000000

local function fpKey(k)
    if type(k) == "number" then return "[" .. string.format("%.14g", k) .. "]" end
    return "[" .. string.format("%q", k) .. "]"
end

local function fpVal(v)
    local t = type(v)
    if t == "string" then return string.format("%q", v) end
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return nil end
        return string.format("%.14g", v)
    end
    if t == "boolean" then return tostring(v) end
    return nil
end

local function fpSer(out, value, indent, open, depth)
    if depth > FP_MAX_DEPTH then return false, "max depth exceeded" end
    if #out > FP_MAX_PARTS then return false, "size budget exceeded" end

    out[#out + 1] = "{\n"
    local pad = string.rep("\t", indent + 1)

    local nk, sk = {}, {}
    for k in pairs(value) do
        if type(k) == "number" and k == k and k ~= math.huge and k ~= -math.huge then nk[#nk + 1] = k
        elseif type(k) == "string" then sk[#sk + 1] = k
        else return false, "unsupported key type/value: " .. tostring(k) end
    end
    table.sort(nk); table.sort(sk)
    local ordered = {}
    for _, k in ipairs(nk) do ordered[#ordered + 1] = k end
    for _, k in ipairs(sk) do ordered[#ordered + 1] = k end

    for _, k in ipairs(ordered) do
        if #out > FP_MAX_PARTS then return false, "size budget exceeded" end
        local v = value[k]
        if type(v) == "table" then
            if open[v] then
                return false, "cyclic reference at key " .. tostring(k)
            else
                open[v] = true
                out[#out + 1] = pad .. fpKey(k) .. " = "
                local ok, err = fpSer(out, v, indent + 1, open, depth + 1)
                open[v] = nil
                if not ok then return false, err end
                out[#out + 1] = ",\n"
            end
        else
            local lit = fpVal(v)
            if not lit then return false, "unsupported value at key " .. tostring(k) .. " (" .. type(v) .. ")" end
            out[#out + 1] = pad .. fpKey(k) .. " = " .. lit .. ",\n"
        end
    end

    out[#out + 1] = string.rep("\t", indent) .. "}"
    return true
end

function FightPlan.IO.Write(path, tbl)
    assert(type(path) == "string" and path ~= "", "[FightPlan.IO.Write] path is required")
    assert(type(tbl) == "table", "[FightPlan.IO.Write] payload must be a table")

    local out = { "-- FightPlan data\nlocal tbl = " }
    local ok, err = fpSer(out, tbl, 0, { [tbl] = true }, 1)
    if not ok then
        d("[FightPlan.IO.Write] " .. path .. ": " .. tostring(err) .. ". Existing file left untouched.")
        return false, err
    end
    out[#out + 1] = "\nreturn tbl\n"

    -- Binary mode: text mode would turn the escaped newline string.format("%q")
    -- emits inside a string literal into backslash-CR-LF, which no longer parses.
    local okOpen, f, openError = xpcall(function() return io.open(path, "wb") end, fpTrace)
    if not okOpen or not f then
        local reason = okOpen and openError or f
        d("[FightPlan.IO.Write] open " .. path .. ": " .. tostring(reason))
        return false, reason
    end
    local okWrite, written, writeError = xpcall(function() return f:write(table.concat(out)) end, fpTrace)
    local okClose, closed, closeError = xpcall(function() return f:close() end, fpTrace)
    if not okWrite or not written or not okClose or not closed then
        local reason = "write=" .. tostring(okWrite and writeError or written) .. "; close=" .. tostring(okClose and closeError or closed)
        d("[FightPlan.IO.Write] " .. path .. ": " .. reason)
        return false, reason
    end
    return true
end

local function SaveSettings()
    local path = FightPlan.paths.settingsFile
    local ok, err = FightPlan.IO.Write(path, FightPlan.settings)
    if not ok then error("[FightPlan.SaveSettings] " .. path .. ": " .. tostring(err), 0) end
end

-- Master switch for the rompot\.global prepull system (FightPlan.Prepull); persisted.
function FightPlan.SetPrepull(enabled)
    assert(type(enabled) == "boolean", "[FightPlan.SetPrepull] expected boolean, got " .. type(enabled))
    -- Saving before LoadSettings has read settings.lua would overwrite it.
    assert(FightPlan.currentJob, "[FightPlan.SetPrepull] settings not loaded yet (no job detected)")
    FightPlan.settings.prepull = enabled
    FightPlan.Prepull = enabled
    SaveSettings()
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

local function conditionMet(element)
    local ok, result = xpcall(element.condition, fpTrace)
    if not ok then
        error("[FightPlan.condition] plan=" .. tostring(element.planSource) .. " id=" .. element.id ..
            " job=" .. tostring(Player and Player.job) .. " map=" .. tostring(Player and Player.localmapid) .. ": " .. tostring(result), 0)
    end
    return result
end

local function InitializeJobSettings(jobId)
    FightPlan.settings[jobId] = FightPlan.settings[jobId] or {}
    local values = FightPlan.settings[jobId]
    local needsSave = false
    -- Defaults are data, independent of visibility. Reactions never need a dummy control.
    for _, element in ipairs(FightPlan.controls) do
        if values[element.id] == nil then
            values[element.id] = element.defaultValue
            needsSave = true
        end
        FightPlan[element.id] = values[element.id]
    end
    if FightPlan.Role then FightPlan.RoleIndex = FightPlan.RoleToIndex[FightPlan.Role] end
    if PartyPlan and PartyPlan.SyncAssignments then PartyPlan.SyncAssignments() end
    if needsSave then SaveSettings() end
end

local function LoadSettings()
    if not Player or not Player.job or Player.job == 0 then
        d("[FightPlan] no job detected. if you entered a recording or loading into game, this is normal.")
        return
    end
    local currentJob = Player.job
    if currentJob ~= FightPlan.currentJob then
        local path = FightPlan.paths.settingsFile
        local settings = FightPlan.IO.Read(path)
        FightPlan.settings = settings or {}
        FightPlan.settings.activePlan = FightPlan.settings.activePlan or {}
        if FightPlan.settings.tldrAccepted == nil then
            FightPlan.settings.tldrAccepted = false
        end
        if FightPlan.settings.prepull == nil then
            FightPlan.settings.prepull = true
        end
        FightPlan.Prepull = FightPlan.settings.prepull
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

        
        InitializeJobSettings(currentJob)
        
        if FightPlan.Role then
            FightPlan.RoleIndex = FightPlan.RoleToIndex[FightPlan.Role]
        end
        FightPlan.currentJob = currentJob
    end
    
    if FightPlan.lastMapId ~= Player.localmapid then
        InitializeJobSettings(Player.job)
    end
    if PartyPlan and PartyPlan.SyncAssignments then PartyPlan.SyncAssignments() end
end

function FightPlan.DrawTLDR()
    if FightPlan.settings.tldrAccepted or FightPlan._tldrDismissed then return end

    local g = FightPlan.gui
    g.pushTheme()

    local sw, sh = GUI:GetScreenSize()
    local winW = 600
    GUI:SetNextWindowSize(winW, 0, "Always")
    GUI:SetNextWindowPos(sw / 2, sh / 2, "Always", 0.5, 0.5)
    local visible = GUI:Begin("FightPlan - Please Read", true, GUI.WindowFlags_AlwaysAutoResize + GUI.WindowFlags_NoMove + GUI.WindowFlags_NoCollapse)
    local okDraw, drawError = xpcall(function()
        if visible then
            GUI:Text("Before using FightPlan, please read the following:")
            GUI:Separator()
            GUI:Dummy(0, 4)
            g.coloredText(g.C.text_dim, "%s", "FightPlan is a prioprietary AddOn not optimized well. Read the entire discord thread before using the addon.")
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
    end, fpTrace)
    GUI:End()
    g.popTheme()
    if not okDraw then error("[FightPlan.DrawTLDR] " .. tostring(drawError), 0) end
end

local drawerNames = { "fpRed", "fpGreen", "fpBlue", "fpYellow", "fpCyan", "fpPurple",
    "fpMagenta", "fpSub", "fpOrange", "fpSky", "fpPink", "fpWhite" }
local drawerDefaults = { enabled = false, opacity = 30, outlineOpacity = 100,
    outlineThickness = 0.750, gradient = false, gradientDistance = 1.5,
    gradientMinOpacity = 15, gradientIntensity = 2, warp = true, overlay = false,
    occlude = false, occlusionBase = false, renderUI = false, occlusionChannel = 0, heightOffset = 0 }
local drawerStock, drawerFailures = {}, {}
local function drawerConfig()
    local cfg = FightPlan.settings.drawerStyle
    if cfg == nil then cfg = {} FightPlan.settings.drawerStyle = cfg end
    for key, value in pairs(drawerDefaults) do
        if cfg[key] == nil then cfg[key] = value end
    end
    return cfg
end
local function withAlpha(color, percent)
    if color == nil then return nil end
    return color % 16777216 + math.floor(percent * 255 / 100 + 0.5) * 16777216
end

-- Keep existing objects and aliases intact, including drawers held by timed draws.
-- Only FightPlan owns shared styling; reactions continue to use the same globals.
function FightPlan.ApplyDrawerStyle()
    local cfg = drawerConfig()
    local parts = {}
    for key in pairs(drawerDefaults) do parts[#parts + 1] = key .. "=" .. tostring(cfg[key]) end
    table.sort(parts)
    local signature = table.concat(parts, "|")
    local flags = (cfg.warp and 1 or 0) + (cfg.overlay and 2 or 0) + (cfg.occlude and 4 or 0)
        + (cfg.occlusionBase and 16 or 0) + (cfg.renderUI and 256 or 0)
    for _, name in ipairs(drawerNames) do
        local drawer = _G[name]
        if type(drawer) ~= "table" or type(drawer.reset) ~= "function" then
            local count = (drawerFailures[name] or 0) + 1
            drawerFailures[name] = count
            if count == 1 then
                d("[FightPlan.ApplyDrawerStyle] " .. name .. " unavailable; Argus2 drawer required (repeats counted)")
            end
            return false
        end
        if drawerFailures[name] then
            d("[FightPlan.ApplyDrawerStyle] " .. name .. " recovered; failed attempts=" .. drawerFailures[name])
            drawerFailures[name] = nil
        end
        local stock = drawerStock[name]
        if not stock or stock.object ~= drawer then
            stock = { object = drawer, colorStart = drawer.colorStart, colorMid = drawer.colorMid,
                colorEnd = drawer.colorEnd, colorOutline = drawer.colorOutline }
            drawerStock[name] = stock
            stock.signature = nil
        end
        if stock.signature ~= signature then
            drawer:reset()
            if cfg.enabled then
                drawer:setColor(withAlpha(stock.colorEnd, cfg.opacity), withAlpha(stock.colorStart, cfg.opacity),
                    withAlpha(stock.colorMid, cfg.opacity))
                drawer.colorOutline = withAlpha(stock.colorOutline, cfg.outlineOpacity)
                drawer.outlineThickness = cfg.outlineThickness
                drawer:setGradient(cfg.gradientDistance, cfg.gradientMinOpacity / 100, cfg.gradient and cfg.gradientIntensity or 0)
                drawer:setRenderFlags(flags)
                drawer:setOcclusionChannel(cfg.occlusionChannel)
                drawer:setHeightOffset(cfg.heightOffset)
            end
            stock.signature = signature
        end
        if cfg.enabled then
            drawer.gradientIntensity = cfg.gradient and cfg.gradientIntensity or 0
        elseif name ~= "fpSub" then
            drawer.gradientIntensity = 0
        end
    end
    return true
end

function FightPlan.DrawDrawerSettings(g)
    g.captionDivider("Drawer Style")
    local cfg = drawerConfig()
    local changed, edited
    cfg.enabled, edited = g.formBool("Custom Mode", "Global for all FightPlan drawers and role aliases. Hues stay unchanged. Disable to restore stock styling; custom values are retained.",
        "fpDrawerCustom", cfg.enabled)
    changed = edited
    if cfg.enabled then
        local function slider(key, label, low, high, fmt, integer)
            local value, change = g.formSlider(label, nil, "fpDrawer" .. key, cfg[key], low, high, fmt, integer)
            if change then cfg[key] = value changed = true end
        end
        local function toggle(key, label)
            local value, change = g.formBool(label, nil, "fpDrawer" .. key, cfg[key])
            if change then cfg[key] = value changed = true end
        end
        slider("opacity", "Fill Opacity", 0, 100, "%d %%", true)
        slider("outlineOpacity", "Outline Opacity", 0, 100, "%d %%", true)
        slider("outlineThickness", "Outline Thickness", 0, 10, "%.2f")
        toggle("gradient", "Gradient")
        if cfg.gradient then
            slider("gradientDistance", "Gradient Distance", 0, 50, "%.1f y")
            slider("gradientMinOpacity", "Gradient Min Opacity", 0, 100, "%d %%", true)
            slider("gradientIntensity", "Gradient Intensity", 0, 20, "%.1f")
        end
        toggle("warp", "Warp Terrain")
        toggle("overlay", "Overlay")
        toggle("occlude", "Occlude")
        toggle("occlusionBase", "Occlusion Base")
        toggle("renderUI", "Render UI")
        slider("occlusionChannel", "Occlusion Channel", 0, 31, "%d", true)
        slider("heightOffset", "Height Offset", -50, 50, "%.1f y")
        g.wrappedText(g.C.text_mute, "Height offset applies to entity-attached timed draws when Warp Terrain is off. Per-call render flags and Old Draw can override drawer settings. Existing timed draws may need to be recreated.")
    end
    if changed then
        if not FightPlan.ApplyDrawerStyle() then
            d("[FightPlan.DrawerSettings] requested style could not be applied")
            return
        end
        SaveSettings()
    end
end

function FightPlan.Draw()
    if not FightPlan.settings.tldrAccepted then return end
    checkAndUpdateRaidMaps()

    
    if not FightPlan.ApplyDrawerStyle() then return end
    if not FightPlan.GUI.open then
        return
    end
    LoadSettings()
    local visibility = {}
    for _, element in ipairs(FightPlan.controls) do visibility[element] = conditionMet(element) end
    local g = FightPlan.gui
    g.pushTheme()
    g.pushDensity()
    GUI:SetNextWindowSize(0, 0, GUI.SetCond_Always)
    FightPlan.GUI.visible, FightPlan.GUI.open = GUI:Begin("FightPlan", FightPlan.GUI.open, GUI.WindowFlags_AlwaysAutoResize + GUI.WindowFlags_NoCollapse)
    -- The PartyPlan bar spans last frame's measured content width (not tracked
    -- itself), so it follows the window instead of sizing it.
    g.widest = 0
    local okDraw, drawError = xpcall(function()
        if FightPlan.GUI.visible then
            GUI:Dummy(math.max(104, GUI:CalcTextSize("FightPlan") + 32), 0)
            g.trackWidth()
            if not Player then return end

            local partyOpen = PartyPlan and PartyPlan.GUI and PartyPlan.GUI.open or false
            g.toggleButton("PartyPlan", "fpPartyBtn", partyOpen, function()
                if PartyPlan and PartyPlan.GUI then
                    PartyPlan.GUI.open = not PartyPlan.GUI.open
                    PartyPlan.GUI.visible = PartyPlan.GUI.open
                end
            end, math.max(1, (FightPlan.GUI.bodyWidth or 0) - GUI:GetCursorPosX()), g.UI.TAB_H)
            GUI:Spacing()

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
                local newIdx, changed = g.compactCombo("##ActivePlan", selectedIdx, conflictGroup)
                if changed then
                    FightPlan.settings.activePlan[currentMapID] = conflictGroup[newIdx]
                    SaveSettings()
                end
                GUI:Spacing()
            end

            if not FightPlan.settings[Player.job] then return end
            local hasAnySettings = false
            local lastSection, lastSource
            for _, element in ipairs(FightPlan.controls) do
                local show = visibility[element]
                if show and element.mapID and conflictGroup and #conflictGroup > 1 then
                    show = element.planSource == FightPlan.settings.activePlan[currentMapID]
                end
                if show then
                    hasAnySettings = true
                    if element.section and (element.section ~= lastSection or element.planSource ~= lastSource) then
                        g.sectionHeader(g.fitText(element.section, g.UI.LABEL_W + g.UI.INPUT_W - 40))
                    end
                    lastSection, lastSource = element.section, element.planSource
                    local value = FightPlan.settings[Player.job][element.id]
                    if element.id == "Role" and PartyPlan and PartyPlan.partyList then value = FightPlan.Role end
                    local changed
                    local tip = element.tooltip ~= "" and element.tooltip or nil
                    if element.type == "select" then
                        g.alignedLabel(element.label, element.label .. (tip and ("\n" .. tip) or ""))
                        local selected = element.useIndex and value or 1
                        if not element.useIndex then
                            for i, option in ipairs(element.options) do if option == value then selected = i; break end end
                        end
                        local newIndex
                        newIndex, changed = g.compactCombo("##" .. element.id, selected, element.options)
                        if changed then value = element.useIndex and newIndex or element.options[newIndex] end
                    else
                        value, changed = g.formBool(element.label, tip, element.id, value)
                    end
                    if changed then
                        FightPlan.settings[Player.job][element.id] = value
                        FightPlan[element.id] = value
                        if element.id == "Role" then
                            FightPlan.RoleIndex = FightPlan.RoleToIndex[value]
                            if PartyPlan and PartyPlan.GetMember and PartyPlan.GetMember(Player.id) then
                                PartyPlan.SetRole(Player.id, value)
                            end
                        end
                        SaveSettings()
                    end
                end
            end
            local mapLabel = (GetMapName and GetMapName(Player.localmapid)) or tostring(Player.localmapid)
            if not hasAnySettings then g.coloredText(g.C.text_mute, "%s", "No settings for this zone.") end
            GUI:Spacing()
            g.statusFooter{ dot = hasAnySettings and "live" or "idle",
                left = g.fitText(mapLabel, g.UI.LABEL_W + g.UI.INPUT_W - 70), right = "v" .. tostring(FightPlan.version) }
        end
    end, fpTrace)
    if g.widest > 0 then FightPlan.GUI.bodyWidth = g.widest end
    g.widest = nil
    GUI:End()
    g.popDensity()
    g.popTheme()
    if not okDraw then d("[FightPlan.Draw] " .. tostring(drawError)) return end
end

function FightPlan.Init()
    d("[FightPlan] by rompot. v" .. FightPlan.version)
    local path = FightPlan.paths.addonDir
    assert(FolderExists(path), "[FightPlan.Init] addon folder missing: " .. path)
    if not FightPlan.settings.RaidMaps then
        FightPlan.settings.RaidMaps = FightPlan.RaidMaps
    else
        for mapId, dutyName in pairs(FightPlan.settings.RaidMaps) do
            FightPlan.RaidMaps[mapId] = dutyName
        end
    end
    LoadSettings()
    if ml_gui and ml_gui.ui_mgr then
        ml_gui.ui_mgr:AddMember({
            id = "FFXIVMINION##MENU_FightPlan",
            name = "FightPlan",
            onClick = function()
                FightPlan.GUI.open = not FightPlan.GUI.open
            end,
            tooltip = "FightPlan is a Reaction settings menu system.",
            texture    = FightPlan.paths.addonDir .. [[\icon.png]],
        }, "FFXIVMINION##MENU_HEADER")
    end
    if Argus2 and Argus2.ShapeDrawer then
        fpRed     = Argus2.ShapeDrawer:new(1291845887, nil, 1291845887, 4294967295, 0.750)
        fpGreen   = Argus2.ShapeDrawer:new(1291910919, nil, 1291910919, 4294967295, 0.750)
        fpBlue    = Argus2.ShapeDrawer:new(1308567552, nil, 1308567552, 4294967295, 0.750)
        fpYellow  = Argus2.ShapeDrawer:new(1291896319, nil, 1291896319, 4294967295, 0.750)
        fpCyan    = Argus2.ShapeDrawer:new(1302658816, nil, 1302658816, 4294967295, 0.750)
        fpPurple  = Argus2.ShapeDrawer:new(1308557386, nil, 1308557386, 4294967295, 0.750)
        fpMagenta = Argus2.ShapeDrawer:new(1308557557, nil, 1308557557, 4294967295, 0.750)
        fpSub     = Argus2.ShapeDrawer:new(1308557557, nil, 1308557557, 4294967295, 0.750)
        -- All fills use 30% opacity (alpha 77/255, rounded to the nearest byte).
        fpOrange  = Argus2.ShapeDrawer:new(1291872767, nil, 1291872767, 4294967295, 0.750)
        fpSky     = Argus2.ShapeDrawer:new(1308608512, nil, 1308608512, 4294967295, 0.750)
        fpPink    = Argus2.ShapeDrawer:new(1304328447, nil, 1304328447, 4294967295, 0.750)
        fpWhite   = Argus2.ShapeDrawer:new(1308622847, nil, 1308622847, 4294967295, 0.750)
        fpOcclude = 4
        fpWarp    = 1
        fpOverlay = 2

        fpRed.gradientIntensity = 0
        fpGreen.gradientIntensity = 0
        fpBlue.gradientIntensity = 0
        fpYellow.gradientIntensity = 0
        fpCyan.gradientIntensity = 0
        fpPurple.gradientIntensity = 0
        fpMagenta.gradientIntensity = 0
        fpOrange.gradientIntensity = 0
        fpSky.gradientIntensity = 0
        fpPink.gradientIntensity = 0
        fpWhite.gradientIntensity = 0
    else
        d("[FightPlan] WARNING: Argus2 not found — shape drawing disabled")
        local stub = { gradientIntensity = 0 }
        fpRed = stub; fpGreen = stub; fpBlue = stub
        fpYellow = stub; fpCyan = stub; fpPurple = stub; fpMagenta = stub
        fpOrange = stub; fpSky = stub; fpPink = stub; fpWhite = stub
    end
    -- role names point at the same drawer objects as the colors above, so the
    -- per-frame gradient reset in FightPlan.Draw covers them too. See the
    -- palette table in REACTIONS_API.md before adding or changing one.
    fpDanger    = fpRed      -- avoid this area
    fpSpread    = fpRed      -- spread marker (shape tells it apart from danger)
    fpSevere    = fpOrange   -- stronger danger: lethal, tankbuster, must not be hit
    fpSafe      = fpGreen    -- go here
    fpCaution   = fpYellow   -- warning, distance checks
    fpGroupStack = fpSky     -- full/light party stack
    fpPairStack = fpPink     -- two-player partner stack
    fpSupport   = fpBlue     -- healer / support marks
    fpGuide     = fpCyan     -- compass, reference lines
    fpMove      = fpGreen    -- movement guidance; green when readable
    fpMove2     = fpMagenta  -- alternate movement guidance when green conflicts
    fpTether    = fpPurple   -- tethers and linked players
    fpInfo      = fpWhite    -- neutral markers, timing
end

local function loadConfigsFromFiles()
    assert(FightPlanSchema and type(FightPlanSchema.Compile) == "function", "[FightPlan.loader] planSchema.lua must load first")
    local controls, dropdowns, checkboxes, groups, names, contracts = {}, {}, {}, {}, {}, {}
    local basePath = FightPlan.paths.plansDir
    assert(FolderExists(basePath), "[FightPlan.loader] required plans folder missing: " .. basePath)
    local function listing(directory, pattern, folders)
        local result = FolderList(directory, pattern, folders)
        assert(type(result) == "table", "[FightPlan.loader] FolderList returned " .. type(result) .. " for " .. directory)
        local sorted = {}
        for _, name in pairs(result) do sorted[#sorted+1] = name end
        table.sort(sorted)
        return sorted
    end
    local function loadFromDirectory(directory)
        for _, fileName in ipairs(listing(directory, [[(.*)lua$]], false)) do
            local filePath = directory .. "\\" .. fileName
            assert(FileExists(filePath), "[FightPlan.loader] listed file missing: " .. filePath)
            local chunk, loadError = loadfile(filePath)
            if not chunk then error("[FightPlan.loader] " .. filePath .. ": " .. tostring(loadError), 0) end
            local ok, config = xpcall(chunk, fpTrace)
            if not ok then error("[FightPlan.loader] " .. filePath .. ": " .. tostring(config), 0) end
            local compiled = FightPlanSchema.Compile(config, filePath)
            local planName = fileName:match("([^/\\]+)%.lua$") or fileName
            if compiled.mapID then
                groups[compiled.mapID] = groups[compiled.mapID] or {}
                names[compiled.mapID] = names[compiled.mapID] or {}
                if names[compiled.mapID][planName] then error("[FightPlan.loader] duplicate plan filename for map " .. compiled.mapID .. ": " .. filePath, 0) end
                names[compiled.mapID][planName] = true
                groups[compiled.mapID][#groups[compiled.mapID]+1] = planName
            end
            for _, element in ipairs(compiled.controls) do
                -- Existing demo profiles intentionally share setting IDs. Their storage contract must agree.
                local prior = contracts[element.id]
                if prior then
                    local same = prior.type == element.type and prior.useIndex == element.useIndex and prior.defaultValue == element.defaultValue
                    if element.type == "select" then
                        same = same and #prior.options == #element.options
                        for i, option in ipairs(element.options) do same = same and prior.options[i] == option end
                    end
                    if not same then error("[FightPlan.loader] conflicting storage contract for id=" .. element.id .. " in " .. filePath, 0) end
                else contracts[element.id] = element end
                element.planSource, element.mapID = planName, compiled.mapID
                controls[#controls+1] = element
                local list = element.type == "select" and dropdowns or checkboxes
                list[#list+1] = element
            end
        end
        for _, name in ipairs(listing(directory, nil, true)) do
            -- Minion's include-folders listing contains files too.
            local entryPath = directory .. "\\" .. name
            if FolderExists(entryPath) then
                loadFromDirectory(entryPath)
            elseif not FileExists(entryPath) then
                error("[FightPlan.loader] listed entry missing: " .. entryPath, 0)
            end
        end
    end
    loadFromDirectory(basePath)
    FightPlan.controls, FightPlan.dropdowns, FightPlan.checkboxes, FightPlan.mapPlanGroups = controls, dropdowns, checkboxes, groups
    d("[FightPlan] Loaded " .. #dropdowns .. " dropdowns and " .. #checkboxes .. " checkboxes")
end

-- Re-scan plans\ without a Lua reload (DiminishingReturns' FP Editor calls this
-- after saving a plan). Raises like the load-time scan; on failure the previous
-- controls stay registered. Re-projects defaults/values for the current job.
function FightPlan.ReloadPlans()
    loadConfigsFromFiles()
    if Player and Player.job and Player.job ~= 0 and Player.job == FightPlan.currentJob then
        InitializeJobSettings(Player.job)
    end
end

loadConfigsFromFiles()
do
    local _path = FightPlan.paths.settingsFile
    local _s = FightPlan.IO.Read(_path)
    if _s then FightPlan.settings = _s end
end
RegisterEventHandler("Module.Initalize", FightPlan.Init, "FightPlan.Init")
RegisterEventHandler("Gameloop.Update", LoadSettings, "FightPlan.Update")
RegisterEventHandler("Gameloop.Draw", FightPlan.Draw, "FightPlan.Draw")
RegisterEventHandler("Gameloop.Draw", FightPlan.DrawTLDR, "FightPlan.DrawTLDR")
