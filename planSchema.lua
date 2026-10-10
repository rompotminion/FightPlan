-- Pure plan compiler. Loaded before FightPlan.lua; never calls game APIs.
FightPlanSchema = {}

local audiences = {}
for word in string.gmatch("DPS Melee Caster Ranged Tank Healer Regen Shield Support MeleeRange CasterRange DoTBL ADV GLD PGL MRD LNC ARC CNJ THM CRP BSM ARM GSM LTW WVR ALC CUL MIN BTN FSH PLD MNK WAR DRG BRD WHM BLM ACN SMN SCH ROG NIN MCH DRK AST SAM RDM BLU GNB DNC RPR SGE VPR PCT", "%S+") do
    audiences[word] = true
end
local reserved = {}
for word in string.gmatch("GUI Groups currentJob settings paths MigrateDataLayout Food RoleIndex RoleToIndex version lastMapId RaidMaps ultimateRaidMaps DebugMaps AutoMarker HectorStrats mapPlanGroups IO gui dropdowns checkboxes controls plans Init Draw DrawTLDR Physical Magical Mitigation MitigationBuffs assistOn assistOff qt hb tb hl has2mPot hasDoTBL potCD", "%S+") do reserved[word] = true end

local function fail(source, message)
    error("[FightPlan.Schema] " .. tostring(source) .. ": " .. message, 0)
end
local function array(t, source)
    if type(t) ~= "table" then fail(source, "expected a list") end
    local count = 0
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then fail(source, "expected a consecutive list") end
        count = count + 1
    end
    if count ~= #t then fail(source, "list contains gaps") end
end
local function keys(t, allowed, source)
    for k in pairs(t) do
        if not allowed[k] then fail(source, "unknown field '" .. tostring(k) .. "'") end
    end
end
local function text(v, source, optional)
    if optional and v == nil then return end
    if type(v) ~= "string" or not v:find("%S") then fail(source, "expected non-empty text") end
end
local function compileCondition(expression, where, expected)
    text(expression, where)
    if #expression > 4096 then fail(where, "condition exceeds 4096 bytes") end
    if type(loadstring) ~= "function" then fail(where, "required Lua loadstring compiler unavailable") end
    local compiled, compileError = loadstring("return (\n" .. expression .. "\n)", "@" .. where)
    if not compiled then fail(where, "invalid Lua condition: " .. tostring(compileError)) end
    return function()
        local value = compiled()
        if type(value) ~= "boolean" then fail(where, "condition must return true or false; got " .. type(value)) end
        return value == expected
    end
end
local function conditionRule(rule, where, nested)
    if type(rule) ~= "table" then fail(where, "condition must be a table") end
    if rule.type == "all" then
        if nested then fail(where, "check groups cannot contain more groups") end
        keys(rule, {type=true, checks=true}, where)
        array(rule.checks, where .. ".checks")
        if #rule.checks == 0 then fail(where, "a condition requires at least one check") end
        local checks = {}
        for i, check in ipairs(rule.checks) do checks[i] = conditionRule(check, where .. ".checks[" .. i .. "]", true) end
        return function()
            for _, evaluate in ipairs(checks) do if not evaluate() then return false end end
            return true
        end
    end
    keys(rule, {type=true, variable=true, value=true, operator=true, expression=true, result=true}, where)
    if rule.result ~= nil and type(rule.result) ~= "boolean" then fail(where, "result must be true or false") end
    local expression
    if rule.type == "lua" then
        if rule.variable ~= nil or rule.value ~= nil or rule.operator ~= nil then fail(where, "Lua conditions use expression instead of variable/value/operator") end
        expression = rule.expression
    else
        if rule.type ~= "boolean" and rule.type ~= "number" and rule.type ~= "string" then fail(where, "condition type must be boolean, number, string or lua") end
        if rule.expression ~= nil then fail(where, "comparison conditions cannot have expression") end
        text(rule.variable, where .. ".variable")
        -- Check the variable expression separately so malformed operands cannot alter the comparison.
        compileCondition(rule.variable, where .. ".variable", true)
        local operator = rule.operator
        if operator == nil then operator = "==" end
        local allowed = {['==']=true, ['~=']=true, ['<']=true, ['>']=true, ['<=']=true, ['>=']=true}
        if not allowed[operator] or (rule.type ~= "number" and operator ~= "==" and operator ~= "~=") then fail(where, "invalid comparison operator for " .. rule.type) end
        if type(rule.value) ~= rule.type then fail(where, "value must be " .. rule.type) end
        if rule.type == "number" and (rule.value ~= rule.value or rule.value == math.huge or rule.value == -math.huge) then fail(where, "value must be a finite number") end
        local literal = rule.type == "string" and string.format("%q", rule.value) or tostring(rule.value)
        expression = "(" .. rule.variable .. "\n) " .. operator .. " " .. literal
    end
    return compileCondition(expression, where, rule.result ~= false)
end

-- Shared by loading and the browser's mirrored validation contract.
function FightPlanSchema.Compile(config, source)
    source = source or "plan"
    if type(config) ~= "table" then fail(source, "file must return a table") end
    if config.mapID ~= nil and (type(config.mapID) ~= "number" or config.mapID < 1 or config.mapID % 1 ~= 0) then fail(source, "mapID must be a positive integer, or omitted for global settings") end
    local modern = config.version ~= nil or config.controls ~= nil
    if modern then
        if config.version ~= 2 then fail(source, "version must be 2") end
        keys(config, {version=true, name=true, mapID=true, controls=true}, source)
        text(config.name, source .. ".name", true)
        array(config.controls, source .. ".controls")
    else
        keys(config, {mapID=true, dropdowns=true, checkboxes=true}, source)
        if config.dropdowns == nil and config.checkboxes == nil then fail(source, "expected controls or legacy dropdowns/checkboxes") end
    end
    local result = {mapID=config.mapID, name=config.name, controls={}, dropdowns={}, checkboxes={}}
    local ids = {}
    local function add(raw, kind)
        if type(raw) ~= "table" then fail(source, "control must be a table") end
        local where = source .. " / " .. tostring(raw.id or "control")
        if modern then
            keys(raw, {type=true, id=true, label=true, options=true, store=true, tooltip=true, default=true, showFor=true, showOn=true, section=true, condition=true, conditionResult=true, conditions=true}, where)
        else
            keys(raw, {id=true, label=true, options=true, useIndex=true, tooltip=true, condition=true, defaultValue=true}, where)
        end
        text(raw.id, where .. ".id")
        if not raw.id:match("^[A-Za-z_][A-Za-z0-9_]*$") or reserved[raw.id] or raw.id:match("^is[A-Z]") then fail(where, "id must be a Lua identifier that does not overwrite FightPlan APIs") end
        if ids[raw.id] then fail(where, "duplicate id in this plan") end
        ids[raw.id] = true
        text(raw.label, where .. ".label")
        if raw.tooltip ~= nil and type(raw.tooltip) ~= "string" then fail(where, "tooltip must be text") end
        text(raw.section, where .. ".section", true)
        kind = kind or raw.type
        if kind ~= "select" and kind ~= "toggle" then fail(where, "type must be 'select' or 'toggle'") end
        local e = {type=kind, id=raw.id, label=raw.label, tooltip=raw.tooltip or "", section=raw.section}
        if kind == "select" then
            array(raw.options, where .. ".options")
            if #raw.options == 0 then fail(where, "select needs at least one option") end
            local seen = {}
            for _, option in ipairs(raw.options) do
                text(option, where .. ".options")
                if seen[option] then fail(where, "duplicate option '" .. option .. "'") end
                seen[option] = true
            end
            if modern and raw.store ~= nil and raw.store ~= "index" and raw.store ~= "value" then fail(where, "store must be 'index' or 'value'") end
            if not modern and raw.useIndex ~= nil and type(raw.useIndex) ~= "boolean" then fail(where, "useIndex must be boolean") end
            e.options = raw.options
            e.useIndex = modern and raw.store == "index" or (not modern and raw.useIndex == true)
            if modern then e.defaultValue = raw.default else e.defaultValue = raw.defaultValue end
            if e.defaultValue == nil then e.defaultValue = e.useIndex and 1 or raw.options[1] end
            if e.useIndex then
                if type(e.defaultValue) ~= "number" or e.defaultValue % 1 ~= 0 or e.defaultValue < 1 or e.defaultValue > #raw.options then fail(where, "default must be an option index (1..n)") end
            elseif not seen[e.defaultValue] then fail(where, "default must equal an option value") end
        else
            if raw.options ~= nil or raw.store ~= nil or raw.useIndex ~= nil then fail(where, "toggles cannot have options or a storage mode") end
            if modern then e.defaultValue = raw.default else e.defaultValue = raw.defaultValue end
            if e.defaultValue == nil then e.defaultValue = false end
            if type(e.defaultValue) ~= "boolean" then fail(where, "toggle default must be true or false") end
        end
        if raw.showFor ~= nil then
            array(raw.showFor, where .. ".showFor")
            if #raw.showFor == 0 then fail(where, "showFor cannot be empty; omit it for everyone") end
            local seen = {}
            for _, audience in ipairs(raw.showFor) do
                if not audiences[audience] or seen[audience] then fail(where, "unknown or duplicate audience '" .. tostring(audience) .. "'") end
                seen[audience] = true
            end
        end
        if raw.showOn ~= nil and raw.showOn ~= "raid" and raw.showOn ~= "autoMarker" then fail(where, "showOn must be 'raid' or 'autoMarker'") end
        local customConditions = {}
        if modern then
            if raw.conditions ~= nil and (raw.condition ~= nil or raw.conditionResult ~= nil) then fail(where, "use conditions or a single condition, not both") end
            if raw.conditions ~= nil then
                array(raw.conditions, where .. ".conditions")
                if #raw.conditions == 0 then fail(where, "conditions cannot be empty; omit for no custom conditions") end
                for i, rule in ipairs(raw.conditions) do customConditions[i] = conditionRule(rule, where .. ".conditions[" .. i .. "]") end
            end
            if raw.conditionResult ~= nil and (type(raw.conditionResult) ~= "boolean" or raw.condition == nil) then fail(where, "conditionResult must be boolean and requires a condition") end
            if raw.condition ~= nil then
                customConditions[1] = compileCondition(raw.condition, where .. ".condition", raw.conditionResult ~= false)
            end
        elseif raw.condition ~= nil and type(raw.condition) ~= "function" then
            fail(where, "legacy condition must be a function")
        end
        e.condition = function()
            if config.mapID and (not Player or Player.localmapid ~= config.mapID) then return false end
            if raw.showOn then
                if not Player then return false end
                local maps = raw.showOn == "raid" and FightPlan.RaidMaps or FightPlan.AutoMarker
                if type(maps) ~= "table" then fail(where, "required FightPlan map registry unavailable") end
                if not maps[Player.localmapid] then return false end
            end
            if raw.showFor then
                if not Player or not Player.job or Player.job == 0 then return false end
                local matched = false
                for _, audience in ipairs(raw.showFor) do
                    local predicate = FightPlan["is" .. audience]
                    if audience == "DoTBL" then predicate = FightPlan.hasDoTBL end
                    if type(predicate) ~= "function" then fail(where, "missing predicate for " .. audience) end
                    if predicate() then matched = true end
                end
                if not matched then return false end
            end
            if #customConditions > 0 then
                for _, evaluate in ipairs(customConditions) do
                    if not evaluate() then return false end
                end
                return true
            end
            if not modern and raw.condition then return raw.condition() end
            return true
        end
        result.controls[#result.controls+1] = e
        local list = kind == "select" and result.dropdowns or result.checkboxes
        list[#list+1] = e
    end
    if modern then
        for _, raw in ipairs(config.controls) do add(raw) end
    else
        for _, entry in ipairs({{config.dropdowns, "select"}, {config.checkboxes, "toggle"}}) do
            if entry[1] ~= nil then
                array(entry[1], source .. "." .. entry[2])
                for _, raw in ipairs(entry[1]) do add(raw, entry[2]) end
            end
        end
    end
    return result
end

return FightPlanSchema
