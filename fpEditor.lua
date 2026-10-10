-- fpEditor.lua  Plan Editor: edit FightPlan plan files in game.
--
-- The in-game counterpart of FightPlan Studio (the browser editor). Lists
-- every plans\**\*.lua of this install and edits one as a draft. Save
-- validates the draft with FightPlan's own compiler (FightPlanSchema.Compile),
-- writes the file in Studio's layout and calls FightPlan.ReloadPlans(), so the
-- FightPlan window and FightPlan.<id> values update at once. If the reload
-- rejects the file (e.g. a storage-contract clash with another plan) the
-- previous text is written back and reloaded.
--
-- Only version 2 data plans are editable; legacy plans are shown read-only.
-- Saving rewrites the file, so hand-written comments in it are not kept.
-- Drafts live in memory per plan until saved or reverted. Opened from
-- PartyPlan > Config > General (Plan Editor).

FightPlan.Editor = FightPlan.Editor or {}
local FE = FightPlan.Editor

local function say(fmt, ...) d("[FightPlan Editor] " .. string.format(fmt, ...)) end

-- Same 55 names as planSchema.lua's audience list, grouped for the picker.
local AUDIENCE_GROUPS = {
    { "Roles",   { "Tank", "Healer", "DPS", "Melee", "Ranged", "Caster", "Support" } },
    { "Groups",  { "Regen", "Shield", "MeleeRange", "CasterRange", "DoTBL" } },
    { "Jobs",    { "PLD", "WAR", "DRK", "GNB", "WHM", "SCH", "AST", "SGE", "MNK", "DRG", "NIN", "SAM", "RPR", "VPR",
                   "BRD", "MCH", "DNC", "BLM", "SMN", "RDM", "PCT", "BLU" } },
    { "Classes", { "GLD", "MRD", "PGL", "LNC", "ARC", "CNJ", "THM", "ACN", "ROG" } },
    { "Other",   { "CRP", "BSM", "ARM", "GSM", "LTW", "WVR", "ALC", "CUL", "MIN", "BTN", "FSH", "ADV" } },
}
FE.AUDIENCE_GROUPS = AUDIENCE_GROUPS

-- One field order for plans, controls and conditions (matches Studio's output).
local KEY_ORDER = { "version", "name", "mapID", "controls", "type", "id", "label", "options", "store", "default",
    "tooltip", "section", "showFor", "showOn", "condition", "conditionResult", "conditions",
    "variable", "operator", "value", "expression", "result", "checks" }
local KNOWN_KEY = {}
for _, k in ipairs(KEY_ORDER) do KNOWN_KEY[k] = true end

local RULE_TYPES  = { "boolean", "number", "string", "lua", "all" }
local RULE_LABELS = { "Boolean", "Number", "String", "Lua", "Group" }
local NUM_OPS, EQ_OPS = { "==", "~=", "<", ">", "<=", ">=" }, { "==", "~=" }
local SHOW_ON     = { nil, "raid", "autoMarker" }
local SHOW_ON_LBL = { "Any Map", "Raid Maps", "Auto Marker Maps" }
local RAIL_W, FOOTER_H = 220, 30

FE.state = FE.state or {
    open    = false,
    plans   = nil,  -- scan result: { {path, rel, folder, file, name, mapID, count, err} }
    sel     = nil,  -- rel of the selected plan
    drafts  = {},   -- rel -> { plan, dirty, errors, readOnly, needValidate }
    openCtl = {},   -- control table -> expanded
    numBuf  = {},
    search  = "",
    status  = "",
    newFolder = 1, newFile = "", newName = "",
}
local s = FE.state

local function setStatus(fmt, ...) s.status = string.format(fmt, ...) end

function FE.Toggle() s.open = not s.open end
function FE.IsOpen() return s.open end

function FE.PlansRoot() return FightPlan.paths.plansDir end

-- ------------------------------------------------------------------
-- Plan file IO. Plans are source text, not settings, so they bypass
-- FightPlan.IO.Write's table serializer.
-- ------------------------------------------------------------------

-- Plan table, or nil plus the reason (missing, syntax error, not a table).
local function readPlan(path)
    if not FileExists(path) then return nil, "file missing" end
    local ok, t = pcall(FightPlan.IO.Read, path)
    if not ok then return nil, tostring(t) end
    return t
end

local function readText(path)
    local f, err = io.open(path, "rb")
    if not f then return nil, err end
    local text = f:read("*a")
    f:close()
    if not text then return nil, "read failed" end
    return text
end

-- Binary mode keeps the file byte-identical to what Studio writes.
local function writeText(path, text)
    local f, err = io.open(path, "wb")
    if not f then return false, err end
    local ok, werr = f:write(text)
    local closed, cerr = f:close()
    if not ok then return false, werr end
    if not closed then return false, cerr end
    return true
end

-- ------------------------------------------------------------------
-- Lua output (mirrors FightPlan Studio's profile.js encoder)
-- ------------------------------------------------------------------

local function quote(str)
    return '"' .. str:gsub('[%c"\\]', function(c)
        if c == "\n" then return "\\n" elseif c == "\r" then return "\\r" elseif c == "\t" then return "\\t"
        elseif c == '"' or c == "\\" then return "\\" .. c end
        return string.format("\\%03d", c:byte())
    end) .. '"'
end

local function encode(v, level, unknown)
    local t = type(v)
    if t == "string" then return quote(v) end
    if t == "number" or t == "boolean" then return tostring(v) end
    if t ~= "table" then unknown[#unknown + 1] = "value of type " .. t return "nil" end
    local entries, n = {}, #v
    if n > 0 then
        local allStrings = true
        for i = 1, n do if type(v[i]) ~= "string" then allStrings = false break end end
        if allStrings then
            for i = 1, n do entries[i] = quote(v[i]) end
            return "{" .. table.concat(entries, ", ") .. "}"
        end
        for i = 1, n do entries[i] = encode(v[i], level + 1, unknown) end
    else
        for k in pairs(v) do if not KNOWN_KEY[k] then unknown[#unknown + 1] = "field " .. tostring(k) end end
        for _, k in ipairs(KEY_ORDER) do
            if v[k] ~= nil then entries[#entries + 1] = k .. " = " .. encode(v[k], level + 1, unknown) end
        end
    end
    if #entries == 0 then return "{}" end
    local pad = string.rep("    ", level + 1)
    return "{\n" .. pad .. table.concat(entries, ",\n" .. pad) .. ",\n" .. string.rep("    ", level) .. "}"
end

-- Plan table -> file text, or nil plus the reason (unencodable field).
function FE.ToLua(plan)
    local unknown = {}
    local body = encode(plan, 0, unknown)
    if #unknown > 0 then return nil, "cannot write " .. table.concat(unknown, ", ") end
    return "-- FightPlan profile. Add a control to the controls list.\nreturn " .. body .. "\n"
end

-- ------------------------------------------------------------------
-- Plans on disk
-- ------------------------------------------------------------------

local function hasFunction(v)
    if type(v) == "function" then return true end
    if type(v) == "table" then for _, x in pairs(v) do if hasFunction(x) then return true end end end
    return false
end

local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = deepCopy(x) end
    return out
end

-- Recursive scan of plans\. Returns the list, or nil plus the error.
function FE.Scan()
    local root = FE.PlansRoot()
    if not FolderExists(root) then return nil, "FightPlan plans folder missing: " .. root end
    local out, failure = {}, nil
    local function walk(dir, rel)
        local files = FolderList(dir, [[(.*)lua$]], false)
        if type(files) ~= "table" then failure = "FolderList returned " .. type(files) .. " for " .. dir return end
        for _, f in pairs(files) do
            local relPath = (rel == "" and f) or (rel .. "\\" .. f)
            out[#out + 1] = { path = dir .. "\\" .. f, rel = relPath, folder = rel, file = f:gsub("%.lua$", "") }
        end
        local entries = FolderList(dir, nil, true)
        if type(entries) ~= "table" then failure = "FolderList returned " .. type(entries) .. " for " .. dir return end
        for _, name in pairs(entries) do
            -- Minion's include-folders listing contains files too.
            if FolderExists(dir .. "\\" .. name) then walk(dir .. "\\" .. name, (rel == "" and name) or (rel .. "\\" .. name)) end
            if failure then return end
        end
    end
    walk(root, "")
    if failure then return nil, failure end
    table.sort(out, function(a, b)
        if a.folder ~= b.folder then return a.folder < b.folder end
        return a.file < b.file
    end)
    for _, p in ipairs(out) do
        local t, why = readPlan(p.path)
        if t then
            p.name, p.mapID = t.name, t.mapID
            p.count = type(t.controls) == "table" and #t.controls or nil
        else
            p.err = why
            say("Cannot read %s: %s", p.rel, tostring(why))
        end
    end
    return out
end

function FE.Rescan()
    local list, err = FE.Scan()
    if not list then say("Scan failed: %s", err) setStatus("Scan failed: %s", err) return false end
    s.plans = list
    return true
end

local function findPlan(rel)
    for _, p in ipairs(s.plans or {}) do if p.rel == rel then return p end end
end

-- Draft for a plan, read from disk on first use (or after Revert).
local function loadDraft(p)
    local d = { dirty = false, needValidate = true }
    local t, why = readPlan(p.path)
    if not t then
        d.readOnly = "Could not read this file: " .. tostring(why) .. ". Fix it by hand, then Rescan."
    elseif t.version ~= 2 then
        d.readOnly = "Legacy plan format (no version = 2). FightPlan still loads it; edit it by hand or convert it in FightPlan Studio."
    elseif hasFunction(t) then
        d.readOnly = "This plan contains Lua functions, which the editor cannot write back."
    else
        if type(t.controls) ~= "table" then t.controls = {} end
        d.plan = t
    end
    s.drafts[p.rel] = d
    return d
end

local function validate(d, p)
    d.needValidate = false
    -- Compile raises on the first problem; that message is the validation result.
    local ok, err = pcall(FightPlanSchema.Compile, d.plan, p.rel)
    d.errors = (not ok) and tostring(err) or nil
end

local function touch(d) d.dirty, d.needValidate = true, true end

-- Write `text` to p and reload FightPlan; on rejection restore `old`.
-- ReloadPlans stays protected: a rejected plan must be rolled back, not left half-applied.
local function writeAndReload(p, text, old)
    local ok, err = writeText(p.path, text)
    if not ok then say("Write %s failed: %s", p.rel, tostring(err)) return false, "write failed: " .. tostring(err) end
    local rok, rerr = pcall(FightPlan.ReloadPlans)
    if rok then return true end
    say("FightPlan rejected %s: %s", p.rel, tostring(rerr))
    if old == nil then return false, tostring(rerr) end
    local back, berr = writeText(p.path, old)
    if not back then
        say("RESTORE FAILED for %s: %s. Fix the file by hand before the next Lua reload.", p.rel, tostring(berr))
        return false, tostring(rerr) .. " (restore failed)"
    end
    local ok2, err2 = pcall(FightPlan.ReloadPlans)
    if not ok2 then say("Reload after restoring %s failed: %s", p.rel, tostring(err2)) end
    return false, tostring(rerr) .. " (previous file restored)"
end

function FE.Save(rel)
    local p, d = findPlan(rel), s.drafts[rel]
    if not (p and d and d.plan) then return false end
    validate(d, p)
    if d.errors then setStatus("Not saved: %s", d.errors) return false end
    local text, encErr = FE.ToLua(d.plan)
    if not text then say("Save %s: %s", p.rel, encErr) setStatus("Not saved: %s", encErr) return false end
    local old, readErr = readText(p.path)
    if not old then
        local why = readErr or "file no longer exists"
        say("Save %s: cannot read the current file for rollback (%s); not saved.", p.rel, why)
        setStatus("Not saved: %s", why)
        return false
    end
    local ok, err = writeAndReload(p, text, old)
    if not ok then setStatus("Not saved: %s", err) return false end
    d.dirty = false
    p.name, p.mapID, p.count, p.err = d.plan.name, d.plan.mapID, #d.plan.controls, nil
    say("Saved %s and reloaded FightPlan.", p.rel)
    setStatus("Saved %s; FightPlan reloaded.", p.rel)
    return true
end

function FE.Revert(rel)
    local p = findPlan(rel)
    if not p then return end
    loadDraft(p)
    setStatus("Reverted %s to the file on disk.", rel)
end

-- New empty plan file in `folder` (relative to plans\, "" = root).
function FE.CreatePlan(folder, file, name)
    file = (file or ""):gsub("%.lua$", "")
    if not file:match("^[%w _%-%.]+$") then setStatus("File name may use letters, digits, space, - _ and .") return false end
    if not (name or ""):find("%S") then setStatus("Enter a plan name.") return false end
    local dir = FE.PlansRoot() .. (folder ~= "" and ("\\" .. folder) or "")
    local p = { path = dir .. "\\" .. file .. ".lua", rel = (folder ~= "" and (folder .. "\\") or "") .. file .. ".lua",
                folder = folder, file = file }
    if FileExists(p.path) then setStatus("%s already exists.", p.rel) return false end
    local text = FE.ToLua({ version = 2, name = name, controls = {} })
    local ok, err = writeAndReload(p, text, nil)
    if not ok then setStatus("Create failed: %s", err) return false end
    say("Created %s.", p.rel)
    FE.Rescan()
    s.sel = p.rel
    setStatus("Created %s.", p.rel)
    return true
end

-- ------------------------------------------------------------------
-- Widgets
-- ------------------------------------------------------------------

local function tip(text) if GUI:IsItemHovered() then GUI:SetTooltip(text) end end

-- Text box bound to t[key]. Optional fields become nil when emptied.
local function textBox(id, t, key, width, optional, d)
    GUI:PushItemWidth(width)
    local v, changed = GUI:InputText(id, t[key] or "")
    GUI:PopItemWidth()
    if changed then
        if optional and not v:find("%S") then v = nil end
        t[key] = v
        touch(d)
    end
end

-- Number text box bound to t[key]. Keeps the typed text (e.g. "1.") until it
-- parses; empty text means nil when `optional`.
local function numberBox(id, t, key, width, optional, d)
    local buf = s.numBuf[id]
    if buf == nil or tonumber(buf) ~= t[key] then buf = t[key] ~= nil and tostring(t[key]) or "" end
    GUI:PushItemWidth(width)
    local v, changed = GUI:InputText(id, buf)
    GUI:PopItemWidth()
    s.numBuf[id] = v
    if changed then
        local n = tonumber(v)
        if n then t[key] = n touch(d)
        elseif optional and not v:find("%S") then t[key] = nil touch(d) end
    end
end

local function combo(id, idx, items, width)
    GUI:PushItemWidth(width)
    local v = GUI:Combo(id, idx, items)
    GUI:PopItemWidth()
    return v
end

-- One-of-two segmented row; setIdx fires only on change.
local function choiceRow(g, label, hint, id, items, cur, setIdx)
    g.formRow(label, hint, function()
        g.segmented(id, items, cur, function(i) if i ~= cur then setIdx(i) end end)
    end)
end

local function indexOf(list, v)
    for i, x in ipairs(list) do if x == v then return i end end
end

-- Unique, plan-prefixed control id (ids share one namespace across plans).
local function newId(plan, p, kind)
    local prefix = p.file:gsub("[^%w]", "")
    if prefix == "" or prefix:match("^%d") then prefix = "fp" .. prefix end
    local taken = {}
    for _, c in ipairs(plan.controls) do taken[c.id] = true end
    for _, c in ipairs(FightPlan.controls or {}) do taken[c.id] = true end
    local n = 1
    while taken[prefix .. kind .. n] do n = n + 1 end
    return prefix .. kind .. n
end

-- ------------------------------------------------------------------
-- Conditions
-- ------------------------------------------------------------------

local function resetRule(rule, ruleType)
    local variable = rule.variable or rule.expression or ""
    for k in pairs(rule) do rule[k] = nil end
    rule.type = ruleType
    if ruleType == "lua" then rule.expression = variable
    elseif ruleType == "all" then rule.checks = { { type = "boolean", variable = variable, value = true } }
    else
        rule.variable = variable
        rule.value = (ruleType == "boolean" and true) or (ruleType == "number" and 0) or ""
    end
end

local function mustBe(id, rule, key, d)
    local cur = rule[key] == false and 2 or 1
    local v = combo(id, cur, { "True", "False" }, 62)
    tip("Must Be: the result this check needs.")
    if v ~= cur then rule[key] = (v == 2) and false or nil touch(d) end
end

-- One condition row. Returns true when its remove button was clicked.
local function drawRule(g, rule, id, nested, d)
    local types, labels = RULE_TYPES, RULE_LABELS
    if nested then types, labels = { unpack(RULE_TYPES, 1, 4) }, { unpack(RULE_LABELS, 1, 4) } end
    GUI:PushID(id)
    local cur = indexOf(types, rule.type) or 1
    local t = combo("##type", cur, labels, 80)
    if t ~= cur then resetRule(rule, types[t]) touch(d) end
    GUI:SameLine(0, 4)
    local remove
    if rule.type == "all" then
        g.coloredText(g.C.text_dim, "All of these checks:")
        GUI:SameLine(0, 8)
        remove = GUI:Button("Remove##rm", 0, g.UI.ROW_H)
        local drop
        for j, check in ipairs(rule.checks or {}) do
            GUI:SetCursorPosX(GUI:GetCursorPosX() + 24)
            if drawRule(g, check, "chk" .. j, true, d) then drop = j end
        end
        if drop then table.remove(rule.checks, drop) touch(d) end
        GUI:SetCursorPosX(GUI:GetCursorPosX() + 24)
        if GUI:Button("Add Check##addchk", 0, g.UI.ROW_H) then
            rule.checks = rule.checks or {}
            rule.checks[#rule.checks + 1] = { type = "boolean", variable = "", value = true }
            touch(d)
        end
    else
        if rule.type == "lua" then
            textBox("##expr", rule, "expression", 300, false, d)
            tip("Lua expression returning true or false, e.g. MyVar.enabled == true and MyValue.is >= 2")
        else
            textBox("##var", rule, "variable", 150, false, d)
            tip("Variable: a Lua expression read each time visibility is checked, e.g. MyVar.enabled")
            GUI:SameLine(0, 4)
            local ops = rule.type == "number" and NUM_OPS or EQ_OPS
            local oi = indexOf(ops, rule.operator or "==") or 1
            local o = combo("##op", oi, ops, 48)
            if o ~= oi then rule.operator = (o == 1) and nil or ops[o] touch(d) end
            GUI:SameLine(0, 4)
            if rule.type == "boolean" then
                local bi = rule.value == false and 2 or 1
                local b = combo("##bval", bi, { "true", "false" }, 90)
                if b ~= bi then rule.value = (b == 1) touch(d) end
            elseif rule.type == "number" then
                numberBox("##nval", rule, "value", 90, false, d)
            else
                textBox("##sval", rule, "value", 90, false, d)
                tip("Compared as text; quotes are added for you.")
            end
        end
        GUI:SameLine(0, 4)
        mustBe("##res", rule, "result", d)
        GUI:SameLine(0, 4)
        remove = GUI:Button("X##rm", 22, g.UI.ROW_H)
        tip("Remove")
    end
    GUI:PopID()
    return remove
end

local function drawConditions(g, c, d)
    g.captionDivider("Conditions")
    if c.condition ~= nil then
        g.formRow("Condition", "Single Lua expression (older form). Add Condition converts it to the list.", function()
            textBox("##cond1", c, "condition", 300, false, d)
            GUI:SameLine(0, 4)
            mustBe("##cond1res", c, "conditionResult", d)
        end)
    end
    local drop
    for j, rule in ipairs(c.conditions or {}) do
        if drawRule(g, rule, "rule" .. j, false, d) then drop = j end
    end
    if drop then
        table.remove(c.conditions, drop)
        if #c.conditions == 0 then c.conditions = nil end
        touch(d)
    end
    if GUI:Button("Add Condition##addcond", 0, g.UI.ROW_H) then
        c.conditions = c.conditions or {}
        if c.condition ~= nil then
            c.conditions[#c.conditions + 1] = { type = "lua", expression = c.condition, result = c.conditionResult == false and false or nil }
            c.condition, c.conditionResult = nil, nil
        end
        c.conditions[#c.conditions + 1] = { type = "boolean", variable = "", value = true }
        touch(d)
    end
    tip("Every condition must match (as well as map and Show For). Group several checks with Type: Group.")
end

-- ------------------------------------------------------------------
-- Control editor
-- ------------------------------------------------------------------

local function drawShowFor(g, c, d)
    local summary = c.showFor and table.concat(c.showFor, ", ") or "Everyone"
    g.formRow("Show For", nil, function()
        g.coloredText(g.C.text_dim, "%s", g.fitText(summary, 260))
        GUI:SameLine(0, 8)
        if GUI:Button((s.openShowFor == c and "Done" or "Edit") .. "##sfedit", 0, g.UI.ROW_H) then
            s.openShowFor = (s.openShowFor ~= c) and c or nil
        end
        if c.showFor then
            GUI:SameLine(0, 4)
            if GUI:Button("Clear##sfclear", 0, g.UI.ROW_H) then c.showFor = nil touch(d) end
        end
    end)
    if s.openShowFor ~= c then return end
    local on = {}
    for _, a in ipairs(c.showFor or {}) do on[a] = true end
    local changed
    for _, grp in ipairs(AUDIENCE_GROUPS) do
        g.coloredText(g.C.text_mute, "%s", grp[1])
        for i, a in ipairs(grp[2]) do
            if (i - 1) % 7 ~= 0 then GUI:SameLine(0, 0) end
            GUI:SetCursorPosX(((i - 1) % 7) * 92 + 8)
            local v = GUI:Checkbox(a .. "##sf_" .. a, on[a] or false)
            if (v and true or false) ~= (on[a] or false) then on[a] = v or nil changed = true end
        end
    end
    if changed then
        local list = {}
        for _, grp in ipairs(AUDIENCE_GROUPS) do for _, a in ipairs(grp[2]) do if on[a] then list[#list + 1] = a end end end
        c.showFor = (#list > 0) and list or nil
        touch(d)
    end
end

local function drawOptions(g, c, d)
    local move, drop
    for i, opt in ipairs(c.options) do
        GUI:PushID("opt" .. i)
        GUI:SetCursorPosX(g.UI.LABEL_W)
        GUI:PushItemWidth(200)
        local v, changed = GUI:InputText("##o", opt)
        GUI:PopItemWidth()
        if changed then
            if c.default == opt then c.default = v end  -- a value default follows its option's rename
            c.options[i] = v
            touch(d)
        end
        GUI:SameLine(0, 4)
        if GUI:Button("Up##u", 0, g.UI.ROW_H) and i > 1 then move = { i, i - 1 } end
        GUI:SameLine(0, 2)
        if GUI:Button("Down##d", 0, g.UI.ROW_H) and i < #c.options then move = { i, i + 1 } end
        GUI:SameLine(0, 2)
        if GUI:Button("X##x", 22, g.UI.ROW_H) then drop = i end
        GUI:PopID()
    end
    if move then
        local a, b = move[1], move[2]
        c.options[a], c.options[b] = c.options[b], c.options[a]
        if c.store == "index" and (c.default == a or c.default == b) then c.default = (c.default == a) and b or a end
        touch(d)
    end
    if drop then
        local removed = table.remove(c.options, drop)
        if c.store == "index" and type(c.default) == "number" then
            if c.default == drop then c.default = nil elseif c.default > drop then c.default = c.default - 1 end
        elseif c.default == removed then c.default = nil end
        touch(d)
    end
    GUI:SetCursorPosX(g.UI.LABEL_W)
    if GUI:Button("Add Option##addopt", 0, g.UI.ROW_H) then
        c.options[#c.options + 1] = "Option " .. (#c.options + 1)
        touch(d)
    end
    GUI:Spacing()
end

local function setType(c, kind)
    c.type = kind
    c.default, c.store = nil, nil
    c.options = (kind == "select") and { "Option 1", "Option 2" } or nil
end

local function drawControlBody(g, c, d)
    choiceRow(g, "Type", nil, "fe_type", { "Toggle", "Dropdown" }, c.type == "select" and 2 or 1,
        function(i) setType(c, i == 2 and "select" or "toggle") touch(d) end)
    g.formRow("Label", nil, function() textBox("##label", c, "label", 260, false, d) end)
    g.formRow("ID", "Reactions read FightPlan." .. tostring(c.id) .. ". Renaming it leaves saved choices and reactions on the old ID.",
        function() textBox("##id", c, "id", 260, false, d) end)
    g.formRow("Tooltip", nil, function()
        local v, changed = GUI:InputTextMultiline("##tooltip", c.tooltip or "", 260, 48)
        if changed then c.tooltip = v:find("%S") and v or nil touch(d) end
    end)
    g.formRow("Section", "Heading shown above this control; repeat it on neighbors to group them.",
        function() textBox("##section", c, "section", 260, true, d) end)

    if c.type == "select" then
        c.options = c.options or {}
        g.formRow("Options", "Order and storage are part of the reactions' contract; keep them stable.", function() end)
        drawOptions(g, c, d)
        choiceRow(g, "Store", "Value: FightPlan.<id> is the option text. Index: it is the option number.", "fe_store",
            { "Value", "Index" }, c.store == "index" and 2 or 1,
            function(i)
                local def = c.default
                if i == 2 then
                    c.store = "index"
                    c.default = def and indexOf(c.options, def) or nil
                else
                    c.store = nil
                    c.default = type(def) == "number" and c.options[def] or nil
                end
                touch(d)
            end)
        g.formRow("Default", "Applies only to jobs without a saved choice.", function()
            local items = { "(First Option)" }
            for _, o in ipairs(c.options) do items[#items + 1] = o end
            local cur = 1
            if c.store == "index" then cur = type(c.default) == "number" and c.default + 1 or 1
            else cur = c.default ~= nil and ((indexOf(c.options, c.default) or 0) + 1) or 1 end
            local v = combo("##default", cur, items, 200)
            if v ~= cur then
                if v == 1 then c.default = nil
                elseif c.store == "index" then c.default = v - 1
                else c.default = c.options[v - 1] end
                touch(d)
            end
        end)
    else
        local v, changed = g.formBool("Default On", "Applies only to jobs without a saved choice.", "fe_def", c.default == true)
        if changed then c.default = v or nil touch(d) end
    end

    drawShowFor(g, c, d)
    g.formRow("Show On", nil, function()
        local cur = c.showOn == "raid" and 2 or (c.showOn == "autoMarker" and 3 or 1)
        local v = combo("##showon", cur, SHOW_ON_LBL, 200)
        if v ~= cur then c.showOn = SHOW_ON[v] touch(d) end
    end)
    drawConditions(g, c, d)
end

local function drawControls(g, d, p)
    local plan = d.plan
    local action
    for i, c in ipairs(plan.controls) do
        GUI:PushID("ctl" .. i)
        local open = s.openCtl[c]
        if GUI:Button((open and "-" or "+") .. "##exp", 22, g.UI.ROW_H) then s.openCtl[c] = not open or nil end
        GUI:SameLine(0, 6)
        g.coloredText(c.type == "select" and g.C.lightblue or g.C.accent_hov, "%s", c.type == "select" and "Dropdown" or "Toggle  ")
        GUI:SameLine(0, 6)
        local avail = GUI:GetContentRegionAvailWidth()
        g.coloredText(g.C.text, "%s", g.fitText(tostring(c.label or ""), math.max(60, avail - 330)))
        GUI:SameLine(0, 6)
        g.coloredText(g.C.text_mute, "%s", g.fitText(tostring(c.id or ""), 120))
        GUI:SameLine(GUI:GetWindowContentRegionWidth() - 176, 0)
        if GUI:Button("Up##up", 0, g.UI.ROW_H) and i > 1 then action = { "move", i, i - 1 } end
        GUI:SameLine(0, 2)
        if GUI:Button("Down##dn", 0, g.UI.ROW_H) and i < #plan.controls then action = { "move", i, i + 1 } end
        GUI:SameLine(0, 2)
        if GUI:Button("Copy##cp", 0, g.UI.ROW_H) then action = { "copy", i } end
        GUI:SameLine(0, 2)
        if g.colorButton("Remove##rm", g.PAL_RED, 0, g.UI.ROW_H) then action = { "remove", i } end
        if open then
            GUI:Spacing()
            drawControlBody(g, c, d)
            GUI:Separator()
        end
        GUI:PopID()
    end
    if not action then return end
    local list = plan.controls
    if action[1] == "move" then
        list[action[2]], list[action[3]] = list[action[3]], list[action[2]]
    elseif action[1] == "copy" then
        local src = list[action[2]]
        local cp = deepCopy(src)
        cp.id = newId(plan, p, src.type == "select" and "Dropdown" or "Toggle")
        cp.label = tostring(src.label or "") .. " Copy"
        table.insert(list, action[2] + 1, cp)
        s.openCtl[cp] = true
    else
        table.remove(list, action[2])
    end
    touch(d)
end

-- ------------------------------------------------------------------
-- Plan list and editor
-- ------------------------------------------------------------------

local function railHeader(g, text)
    GUI:Spacing()
    g.coloredText(g.C.text_mute, "%s", string.upper(text))
end

local function drawPlanRail(g)
    GUI:PushItemWidth(RAIL_W - 16)
    s.search = GUI:InputText("##fe_search", s.search or "")
    GUI:PopItemWidth()
    tip("Search by file, plan name or map ID")
    if GUI:Button("New Plan##fe_new", (RAIL_W - 20) / 2, g.UI.ROW_H) then
        s.newFile, s.newName = "", ""
        GUI:OpenPopup("fe_newplan")
    end
    GUI:SameLine(0, 4)
    if GUI:Button("Rescan##fe_rescan", (RAIL_W - 20) / 2, g.UI.ROW_H) then
        if FE.Rescan() then setStatus("Found %d plans.", #s.plans) end
    end
    tip("Re-read " .. FE.PlansRoot() .. " (picks up files added outside the game). Drafts are kept.")

    local q = (s.search or ""):lower()
    local mapId = Player and Player.localmapid
    local function item(p, scope)
        local hay = (p.rel .. " " .. tostring(p.name or "") .. " " .. tostring(p.mapID or "")):lower()
        if q ~= "" and not hay:find(q, 1, true) then return end
        local d = s.drafts[p.rel]
        local label = p.file .. ((d and d.dirty) and " *" or "") .. (p.err and "  !" or (p.count and ("  (" .. p.count .. ")") or ""))
        -- Same file name can appear in two folders and under This Map.
        local _, clicked = GUI:Selectable(label .. "##" .. scope .. p.rel, s.sel == p.rel, 0, 0, 0)
        if clicked then s.sel = p.rel end
        tip((p.name or p.file) .. "\n" .. p.rel .. (p.mapID and ("\nMap " .. p.mapID) or "\nGlobal (all maps)")
            .. (p.err and ("\n" .. p.err) or ""))
    end
    local here = {}
    for _, p in ipairs(s.plans) do if mapId and p.mapID == mapId then here[#here + 1] = p end end
    if #here > 0 then
        railHeader(g, "This Map")
        for _, p in ipairs(here) do item(p, "here") end
    end
    local folder
    for _, p in ipairs(s.plans) do
        if p.folder ~= folder then
            folder = p.folder
            railHeader(g, folder == "" and "plans" or (folder:gsub("\\", " / ")))
        end
        item(p, "all")
    end

    if GUI:BeginPopup("fe_newplan") then
        local folders, seen = { "" }, { [""] = true }
        for _, p in ipairs(s.plans) do if not seen[p.folder] then seen[p.folder] = true folders[#folders + 1] = p.folder end end
        local labels = {}
        for i, f in ipairs(folders) do labels[i] = (f == "" and "plans" or ("plans\\" .. f)) end
        if s.newFolder > #folders then s.newFolder = 1 end
        g.alignedLabel("Folder")
        s.newFolder = combo("##fe_nf", s.newFolder, labels, 260)
        g.alignedLabel("File Name")
        GUI:PushItemWidth(260) s.newFile = GUI:InputText("##fe_nfile", s.newFile) GUI:PopItemWidth()
        g.alignedLabel("Plan Name")
        GUI:PushItemWidth(260) s.newName = GUI:InputText("##fe_nname", s.newName) GUI:PopItemWidth()
        if g.colorButton("Create##fe_create", g.PAL_GREEN, 120, g.UI.BTN_H) then
            if FE.CreatePlan(folders[s.newFolder], s.newFile, s.newName) then GUI:CloseCurrentPopup() end
        end
        GUI:SameLine()
        if GUI:Button("Cancel##fe_ncancel", 120, g.UI.BTN_H) then GUI:CloseCurrentPopup() end
        g.coloredText(g.C.text_mute, "%s", s.status)
        GUI:EndPopup()
    end
end

local function drawPlanEditor(g)
    local C = g.C
    local p = s.sel and findPlan(s.sel)
    if not p then g.coloredText(C.text_mute, "Select a plan on the left, or create one with New Plan.") return end
    local d = s.drafts[p.rel] or loadDraft(p)

    g.coloredText(C.text, "%s", p.rel)
    GUI:SameLine(0, 8)
    if d.readOnly then g.coloredText(C.yellow, "Read Only")
    elseif d.dirty then g.coloredText(C.yellow, "Unsaved")
    else g.coloredText(C.green, "Saved") end
    if d.readOnly then
        g.wrappedText(C.yellow, d.readOnly)
        if GUI:Button("Reload From Disk##fe_rl", 0, g.UI.ROW_H) then FE.Revert(p.rel) end
        return
    end
    if d.needValidate then validate(d, p) end

    if not d.errors then
        if g.colorButton("Save##fe_save", g.PAL_GREEN, 90, g.UI.BTN_H) then FE.Save(p.rel) end
        tip("Write the file and reload FightPlan's plans now.")
    else
        GUI:Button("Save##fe_save_off", 90, g.UI.BTN_H)
        tip("Fix the errors below first.")
    end
    GUI:SameLine(0, 4)
    if GUI:Button("Revert##fe_revert", 90, g.UI.BTN_H) then FE.Revert(p.rel) return end
    tip("Discard unsaved changes and re-read the file.")
    GUI:SameLine(0, 4)
    if GUI:Button("Open FightPlan##fe_openfp", 0, g.UI.BTN_H) then FightPlan.GUI.open = true end
    tip("FightPlan's own window shows the saved controls with the real job/map visibility.")
    if d.errors then g.wrappedText(C.red, d.errors) end
    GUI:Spacing()

    local plan = d.plan
    g.formRow("Plan Name", nil, function() textBox("##fe_pname", plan, "name", 260, true, d) end)
    g.formRow("Map ID", "Blank = global settings shown on every map.", function()
        numberBox("##fe_pmap", plan, "mapID", 90, true, d)
        GUI:SameLine(0, 6)
        if GUI:Button("Use Current Map##fe_curmap", 0, g.UI.ROW_H) and Player then plan.mapID = Player.localmapid touch(d) end
        if Player then GUI:SameLine(0, 6) g.coloredText(C.text_mute, "now %s", tostring(Player.localmapid)) end
    end)

    g.captionDivider(string.format("Controls (%d)", #plan.controls))
    if GUI:Button("Add Toggle##fe_addt", 0, g.UI.ROW_H) then
        local c = { type = "toggle", id = newId(plan, p, "Toggle"), label = "New Toggle" }
        plan.controls[#plan.controls + 1] = c
        s.openCtl[c] = true
        touch(d)
    end
    GUI:SameLine(0, 4)
    if GUI:Button("Add Dropdown##fe_adds", 0, g.UI.ROW_H) then
        local c = { type = "select", id = newId(plan, p, "Dropdown"), label = "New Dropdown", options = { "Option 1", "Option 2" } }
        plan.controls[#plan.controls + 1] = c
        s.openCtl[c] = true
        touch(d)
    end
    GUI:Spacing()
    drawControls(g, d, p)
end

-- ------------------------------------------------------------------
-- Window
-- ------------------------------------------------------------------

local function traceback(e)
    return debug and debug.traceback and debug.traceback(tostring(e), 2) or tostring(e)
end

-- Draw faults print once, then every 300 repeats with the count: this runs
-- every frame, so an unthrottled print would flood the console.
local lastFault, faultRepeats = nil, 0
local function guarded(g, fn)
    local ok, err = xpcall(fn, traceback)
    if ok then return end
    err = tostring(err)
    if err ~= lastFault then
        lastFault, faultRepeats = err, 0
        say("draw failed: %s", err)
    else
        faultRepeats = faultRepeats + 1
        if faultRepeats % 300 == 0 then say("draw failed again (%d repeats): %s", faultRepeats, err:match("[^\n]*")) end
    end
    g.wrappedText(g.C.red, "[FightPlan Editor] " .. err)
end

function FE.OnDraw()
    if not s.open then return end
    local g = FightPlan.gui
    g.pushTheme()
    g.pushDensity()
    GUI:SetNextWindowSize(920, 640, GUI.SetCond_FirstUseEver or 4)
    local visible, open = GUI:Begin("FightPlan Editor", s.open, GUI.WindowFlags_NoCollapse)
    s.open = open
    if visible then
        guarded(g, function()
            if not s.plans then FE.Rescan() end
            local bodyH = math.max(1, GUI:GetWindowHeight() - GUI:GetCursorPosY() - FOOTER_H)
            if s.plans then
                g.pushColor4(GUI.Col_ChildBg, g.C.bg_frame)
                GUI:BeginChild("fe_rail", RAIL_W, bodyH, true)
                guarded(g, function() drawPlanRail(g) end)
                GUI:EndChild()
                GUI:PopStyleColor(1)
                GUI:SameLine(0, 8)
                GUI:BeginChild("fe_main", 0, bodyH, false)
                guarded(g, function() drawPlanEditor(g) end)
                GUI:EndChild()
            else
                g.wrappedText(g.C.red, s.status)
            end
            local dirty = 0
            for _, d in pairs(s.drafts) do if d.dirty then dirty = dirty + 1 end end
            g.statusFooter{
                dot   = dirty > 0 and "warn" or "idle",
                left  = dirty > 0 and string.format("%d unsaved plan%s", dirty, dirty == 1 and "" or "s") or "No unsaved changes",
                right = (s.status ~= "") and s.status or nil,
            }
        end)
    end
    GUI:End()
    g.popDensity()
    g.popTheme()
end

RegisterEventHandler("Gameloop.Draw", FE.OnDraw, "FightPlan.Editor")
