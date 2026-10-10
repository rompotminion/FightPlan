ReactionHelper = {
    open = false,
    visible = false,
    fontScale = 1.0
}

-- Readouts are drawn with DiminishingReturns' Fonter bitmap renderer using the
-- HostGrotesk-Bold atlas: heavy, evenly spaced digits that survive video
-- compression better than ImGui's default font. The atlas is generated at 26px
-- (18px caps/digits) and drawn at ~1:1, because upscaling a bitmap atlas blurs
-- it; tools/font_atlas_generator.py makes more sizes. If Fonter or the atlas is
-- missing, the window falls back to plain ImGui text and says so in red.
local FONT_ID    = "datagui"
local FONT_FILE  = "HostGrotesk-DataGUI_26" -- DiminishingReturns\json\<file>_data.lua + font\<file>.png (a HostGrotesk-Bold atlas; separate family name so the DR font picker keeps its own sizes)
local VALUE_BASE = 1.0                     -- value scale at fontScale 1.0 (1:1 with the atlas)
local LABEL_RATIO = 0.68                   -- label size relative to value size (~15px caps)
local CAP_H      = 18                      -- glyph height of caps/digits in the atlas
local POS_RATIO  = 0.6                     -- POS value size relative to the other values so "120.99,120.99,120.99" stays compact
local POS_SAMPLE = "120.99,120.99,120.99"  -- widest expected POS text; sizes the value column
local ROW_PAD    = 3                       -- extra px below each row's digits
local LABEL_GAP  = 8                       -- px between label column and value column

local WHITE       = { 1.00, 1.00, 1.00, 1.0 }
local LABEL_COLOR = { 0.72, 0.74, 0.78, 1.0 }
local MUTED       = { 0.50, 0.52, 0.56, 1.0 }

local fontErr, fontErrFor, reportedMissing = nil, nil, false

local function RH_SaveScale()
    if FightPlan and FightPlan.settings then
        FightPlan.settings.dataGuiScale = ReactionHelper.fontScale
        local path = FightPlan.paths.settingsFile
        FightPlan.IO.Write(path, FightPlan.settings)
    end
end

-- Returns true when the HostGrotesk font is registered and drawable; otherwise
-- false plus a reason. Load failures are reported to the console once per
-- Fonter instance (a DR reload creates a fresh Fonter and earns a fresh try).
local function EnsureFont()
    if not (Fonter and FonterText and Fonter.LoadFontFromLua and Fonter.jsonPath) then
        if not reportedMissing then
            reportedMissing = true
            d("[ReactionHelper]: Fonter (DiminishingReturns) is not loaded; Data window is using the default font")
        end
        return false, "Fonter not loaded (DiminishingReturns)"
    end
    reportedMissing = false
    if Fonter.fonts and Fonter.fonts[FONT_ID] then return true end
    if fontErr and fontErrFor == Fonter then return false, fontErr end

    local data, err = Fonter.LoadFontFromLua(FONT_ID, Fonter.jsonPath .. FONT_FILE .. "_data.lua", FONT_FILE .. ".png")
    if not data then
        fontErr, fontErrFor = tostring(err), Fonter
        d("[ReactionHelper]: failed to load Data window font '" .. FONT_FILE .. "': " .. fontErr)
        return false, fontErr
    end
    return true
end

local function Chars()
    return Fonter.fonts[FONT_ID].data.characters
end

local function Advance(str, size)
    local chars, w = Chars(), 0
    for i = 1, #str do
        local cd = chars[str:sub(i, i)]
        if cd then w = w + cd.advance * size end
    end
    return w
end

local function MaxOriginY(str)
    local chars, m = Chars(), 0
    for i = 1, #str do
        local cd = chars[str:sub(i, i)]
        if cd and cd.originY > m then m = cd.originY end
    end
    return m
end

-- Draw `str` with its baseline on screen-y `baseline` so labels and values of
-- different sizes share a baseline (FonterText itself anchors the tallest glyph's top).
local function DrawAt(str, x, baseline, size, c)
    GUI:SetCursorScreenPos(x, baseline - MaxOriginY(str) * size)
    FonterText(str, size, c[1], c[2], c[3], c[4], FONT_ID)
end

local function BuildRows()
    local rows = {}
    local function add(label, text, c, ratio) rows[#rows + 1] = { label = label, text = text, color = c or WHITE, ratio = ratio } end

    local timer = TensorReactions_CurrentTimer or 0
    add("TIMER", timer == 0 and "0" or string.format("%.1f", timer))

    local lb = TensorCore.getLBGauge() or 0
    if lb == 0 then add("LB", "--", MUTED) else add("LB", string.format("%.0f", lb)) end

    local target = TensorCore.mGetTarget()
    local hp = target and target.hp and target.hp.percent or nil
    if hp == nil then add("HP", "--", MUTED) else add("HP", string.format("%.0f", hp) .. "%") end

    local tid = target and target.contentid or nil
    if tid == nil then add("TID", "--", MUTED) else add("TID", string.format("%.0f", tid)) end

    local ttk = target and TensorCore.calcTimeToKill(target.id, 1000) or nil
    if ttk == nil or ttk == 0 or ttk == 1000 then add("TTK", "--", MUTED)
    else add("TTK", string.format("%.0fs", ttk)) end

    local pos = Player and Player.pos
    if pos and pos.x and pos.y and pos.z then
        add("POS", string.format("%.2f,%.2f,%.2f", pos.x, pos.y, pos.z), nil, POS_RATIO)
    else
        add("POS", "--", MUTED)
    end

    return rows
end

local function DrawFonterRows(rows, scale)
    local vs = VALUE_BASE * scale
    local ls = vs * LABEL_RATIO

    local labelW = 0
    for _, r in ipairs(rows) do labelW = math.max(labelW, Advance(r.label, ls)) end
    labelW = labelW + LABEL_GAP
    local valueW = Advance("88888888", vs)        -- reserve room for the longest value (8 digits covers "-1234.56") so the window never resizes
    valueW = math.max(valueW, Advance(POS_SAMPLE, vs * POS_RATIO))
    local rowW, rowH = labelW + valueW, CAP_H * vs + ROW_PAD

    for _, r in ipairs(rows) do
        local x0, y0 = GUI:GetCursorScreenPos()
        local baseline = y0 + CAP_H * vs
        DrawAt(r.label, x0, baseline, ls, LABEL_COLOR)
        DrawAt(r.text, x0 + labelW, baseline, vs * (r.ratio or 1), r.color)
        GUI:SetCursorScreenPos(x0, y0)
        GUI:Dummy(rowW, rowH)
    end
end

local function DrawFallbackRows(rows, scale, g, reason)
    g.coloredText(g.C.red, "Font unavailable: %s", reason)
    GUI:SetWindowFontScale(scale * 1.3)
    for _, r in ipairs(rows) do
        g.coloredText(LABEL_COLOR, "%s", r.label)
        GUI:SameLine()
        g.coloredText(r.color, "%s", r.text)
    end
    GUI:SetWindowFontScale(1.0)
end

function ReactionHelper.toggle()
    ReactionHelper.open = not ReactionHelper.open
end

function ReactionHelper.Draw()
    if not ReactionHelper.open then return end

    if FightPlan and FightPlan.settings and FightPlan.settings.dataGuiScale then
        ReactionHelper.fontScale = FightPlan.settings.dataGuiScale
    end

    local g = FightPlan.gui
    if not GUI.StyleVar_WindowRounding then
        error("[ReactionHelper]: GUI.StyleVar_WindowRounding is missing; cannot square the window corners")
    end
    g.pushTheme()

    -- No title bar: the window is a pure readout. Drag it by its body; close it from the
    -- right-click menu, the Data GUI button or the Reaction Helper menu entry.
    local window_flags = GUI.WindowFlags_AlwaysAutoResize + GUI.WindowFlags_NoTitleBar
    GUI:PushStyleVar(GUI.StyleVar_WindowRounding, 0)
    ReactionHelper.visible, ReactionHelper.open = GUI:Begin("Data", ReactionHelper.open, window_flags)

    if ReactionHelper.visible then
        local scale = ReactionHelper.fontScale
        local rows = BuildRows()

        local ok, reason = EnsureFont()
        if ok then
            DrawFonterRows(rows, scale)
        else
            DrawFallbackRows(rows, scale, g, reason)
        end

        if GUI:BeginPopupContextWindow("##dataCtx", 1, true) then
            GUI:Text("Size")
            GUI:SameLine()
            GUI:PushItemWidth(120)
            local newScale, changed = GUI:SliderFloat("##dataScale", scale, 0.5, 3.0)
            GUI:PopItemWidth()
            if changed then
                ReactionHelper.fontScale = newScale
                RH_SaveScale()
            end
            if GUI:MenuItem("Close") then ReactionHelper.open = false end
            GUI:EndPopup()
        end
    end
    GUI:End()
    GUI:PopStyleVar(1)
    g.popTheme()
end

function ReactionHelper.Init()
    d("[ReactionHelper]: Initialized")
end

function ReactionHelper.Update(event, tickcount)
end

RegisterEventHandler("Module.Initialize", ReactionHelper.Init, "ReactionHelper.Init")
RegisterEventHandler("Gameloop.Draw", ReactionHelper.Draw, "ReactionHelper.Draw")
RegisterEventHandler("Gameloop.Update", ReactionHelper.Update, "ReactionHelper.Update")

ml_gui.ui_mgr:AddMember({
    id = "REACTIONHELPER##MENU_TOGGLE",
    name = "Reaction Helper",
    onClick = function()
        ReactionHelper.toggle()
    end,
    tooltip = "Toggle the Reaction Helper window."
}, "FFXIVMINION##MENU_HEADER")

ReactionHelper.Init()
