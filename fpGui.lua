-- fpGui.lua — bundled visual design system for FightPlan, ReactionHelper,
-- and PartyPlan. Ported from DiminishingReturns/drGui.lua so FightPlan stays
-- self-contained (no dependency on DiminishingReturns) while looking the same:
-- sharp corners, 1 px frame borders, filled top tabs, caption dividers, one
-- label/value column for setting rows and a status footer.
--
-- USAGE
--   local g = FightPlan.gui
--   g.pushTheme(); g.pushDensity()
--   GUI:Begin("FightPlan", ...)
--   g.captionDivider("Section")
--   g.formRow("Setting", "hint", function() ... end)
--   g.statusFooter{ dot = "live", left = "...", right = "v1" }
--   GUI:End()
--   g.popDensity(); g.popTheme()

FightPlan = FightPlan or {}
FightPlan.gui = FightPlan.gui or {}
local g = FightPlan.gui

-- ============================================================
-- Color palette (floats in 0..1, ImGui-friendly)
-- ============================================================
g.C = {
    bg_window     = {0.122, 0.129, 0.141, 1.00},
    bg_titlebar   = {0.086, 0.094, 0.106, 1.00},
    bg_control    = {0.165, 0.176, 0.192, 1.00},
    bg_ctrl_hov   = {0.204, 0.220, 0.239, 1.00},
    bg_ctrl_act   = {0.114, 0.125, 0.141, 1.00},
    bg_frame      = {0.082, 0.090, 0.102, 1.00},
    border        = {0.051, 0.055, 0.063, 1.00},
    border_soft   = {0.180, 0.192, 0.216, 1.00},
    border_soft2  = {0.137, 0.145, 0.161, 1.00},
    text          = {0.839, 0.847, 0.859, 1.00},
    text_dim      = {0.541, 0.553, 0.573, 1.00},
    text_mute     = {0.357, 0.369, 0.388, 1.00},
    accent        = {0.239, 0.420, 0.690, 1.00},
    accent_hov    = {0.302, 0.494, 0.784, 1.00},
    accent_act    = {0.173, 0.314, 0.573, 1.00},
    accent_bg     = {0.239, 0.420, 0.690, 0.12},
    green         = {0.200, 0.800, 0.333, 1.00},
    yellow        = {1.000, 0.800, 0.102, 1.00},
    red           = {0.878, 0.282, 0.282, 1.00},
    lightblue     = {0.345, 0.694, 0.957, 1.00},
}
local C = g.C

-- Action-button palettes for g.colorButton: green = go/save, red = remove.
-- Layout = {bg.rgb, hover.rgb, active.rgb, text.rgb}, as in drGui.
g.PAL_GREEN = { 0.20,0.80,0.33, 0.25,0.86,0.40, 0.15,0.62,0.26, 0.04,0.16,0.07 }
g.PAL_RED   = { 0.88,0.28,0.28, 0.96,0.36,0.36, 0.62,0.18,0.18, 1.00,1.00,1.00 }

-- ============================================================
-- Pixel constants
-- ============================================================
g.UI = {
    LABEL_W    = 160,  -- value column for every setting row (DR's FORM_LABEL_W)
    INPUT_W    = 164,
    SLIDER_W   = 200,
    ROW_H      = 20,
    BTN_H      = 22,
    TAB_H      = 24,
    HUB_BTN_W  = 168,
    HUB_BTN_H  = 28,
}
local UI = g.UI

-- ============================================================
-- Window flag presets
-- ============================================================
g.WINDOW_FLAGS_SETTINGS =
    GUI.WindowFlags_NoCollapse +
    GUI.WindowFlags_NoScrollbar

-- ============================================================
-- Color push helpers
-- ============================================================
function g.pushColor4(slot, c)
    GUI:PushStyleColor(slot, c[1], c[2], c[3], c[4])
end

local pushColor4 = g.pushColor4
local function u32(c, alpha)
    return GUI:ColorConvertFloat4ToU32(c[1], c[2], c[3], alpha or c[4])
end

-- ============================================================
-- Theme push/pop: 14 style colors plus DR's sharp-corner style vars.
-- The binding may not expose every StyleVar constant, so each push is
-- probed and counted on a stack; nested pairs pop exactly what they pushed.
-- ============================================================
local themeVarStack = {}
function g.pushTheme()
    pushColor4(GUI.Col_WindowBg,        C.bg_window)
    pushColor4(GUI.Col_TitleBg,         C.bg_titlebar)
    pushColor4(GUI.Col_TitleBgActive,   C.bg_titlebar)
    pushColor4(GUI.Col_FrameBg,         C.bg_frame)
    pushColor4(GUI.Col_FrameBgHovered,  C.bg_ctrl_hov)
    pushColor4(GUI.Col_FrameBgActive,   C.bg_ctrl_act)
    pushColor4(GUI.Col_Button,          C.bg_control)
    pushColor4(GUI.Col_ButtonHovered,   C.bg_ctrl_hov)
    pushColor4(GUI.Col_ButtonActive,    C.bg_ctrl_act)
    pushColor4(GUI.Col_Border,          C.border)
    pushColor4(GUI.Col_Text,            C.text)
    pushColor4(GUI.Col_CheckMark,       C.green)
    pushColor4(GUI.Col_SliderGrab,      C.accent)
    pushColor4(GUI.Col_SliderGrabActive,C.accent_hov)
    local pushed = 0
    for _, var in ipairs({"StyleVar_FrameRounding", "StyleVar_GrabRounding", "StyleVar_WindowRounding",
            "StyleVar_ChildRounding", "StyleVar_PopupRounding", "StyleVar_ScrollbarRounding"}) do
        if GUI[var] then GUI:PushStyleVar(GUI[var], 0); pushed = pushed + 1 end
    end
    if GUI.StyleVar_FrameBorderSize then GUI:PushStyleVar(GUI.StyleVar_FrameBorderSize, 1); pushed = pushed + 1 end
    themeVarStack[#themeVarStack + 1] = pushed
end

function g.popTheme()
    local pushed = table.remove(themeVarStack)
    if pushed and pushed > 0 then GUI:PopStyleVar(pushed) end
    GUI:PopStyleColor(14)
end

-- DR's comfortable density (frame padding, item spacing, window padding).
-- Push after pushTheme and pop before popTheme, around a settings window.
function g.pushDensity()
    GUI:PushStyleVar(GUI.StyleVar_FramePadding,  6, 4)
    GUI:PushStyleVar(GUI.StyleVar_ItemSpacing,   6, 4)
    GUI:PushStyleVar(GUI.StyleVar_WindowPadding, 6, 6)
end
function g.popDensity() GUI:PopStyleVar(3) end

-- Compact timer card, following DR's dark panels and restrained accent fills.
-- Ellipsize labels at UTF-8 boundaries so they cannot overlap the countdown.
function g.timerBar(x, y, width, height, label, seconds, fraction, color)
    fraction = math.max(0, math.min(1, fraction))
    local countdown = string.format("%.1fs", seconds)
    local timeWidth, textHeight = GUI:CalcTextSize(countdown)
    local available = math.max(0, width - timeWidth - 32)
    local text = label:gsub("[\r\n\t]", " ")
    if GUI:CalcTextSize(text) > available then
        while #text > 0 and GUI:CalcTextSize(text .. "...") > available do
            local last = #text
            while last > 1 and text:byte(last) >= 128 and text:byte(last) < 192 do last = last - 1 end
            text = text:sub(1, last - 1)
        end
        text = text .. "..."
        if GUI:CalcTextSize(text) > available then text = "" end
    end
    GUI:AddRectFilled(x, y, x + width, y + height, u32(C.bg_titlebar, 0.94))
    if fraction > 0 then
        GUI:AddRectFilled(x, y, x + width * fraction, y + height, u32(color, color[4] * 0.45))
        GUI:AddRectFilled(x + 1, y + height - 3, x + math.max(1, (width - 1) * fraction), y + height - 1, u32(color))
    end
    GUI:AddRect(x, y, x + width, y + height, u32(C.border_soft))
    local textY = y + (height - textHeight) * 0.5
    GUI:AddText(x + 10, textY + 1, GUI:ColorConvertFloat4ToU32(0, 0, 0, 0.8), text)
    GUI:AddText(x + 10, textY, u32(C.text), text)
    GUI:AddText(x + width - timeWidth - 10, textY + 1, GUI:ColorConvertFloat4ToU32(0, 0, 0, 0.8), countdown)
    GUI:AddText(x + width - timeWidth - 10, textY, GUI:ColorConvertFloat4ToU32(1, 1, 1, 1), countdown)
end

-- ============================================================
-- Width tracking. While g.widest is a number (a window sets it to 0 before
-- drawing), helpers record the rightmost item edge in window-local x, so a
-- full-width control can be sized to the rest of the content next frame
-- instead of forcing the window wider. nil = off.
-- ============================================================
function g.trackWidth()
    if not g.widest then return end
    local right = GUI:GetItemRectMax() - GUI:GetWindowPos()
    if right > g.widest then g.widest = right end
end

-- ============================================================
-- Text
-- ============================================================
function g.coloredText(c, fmt, ...)
    pushColor4(GUI.Col_Text, c)
    GUI:Text(string.format(fmt, ...))
    GUI:PopStyleColor(1)
    g.trackWidth()
end

-- Word-wrapped coloured text (wraps at the content region's right edge).
function g.wrappedText(c, text)
    pushColor4(GUI.Col_Text, c)
    GUI:TextWrapped(tostring(text))
    GUI:PopStyleColor(1)
end

-- Uppercase muted caption with a rule filling the rest of the row. The rule
-- is drawn, not laid out (1 px dummy), so auto-resizing windows never grow
-- to fit it.
function g.captionDivider(label)
    g.coloredText(C.text_mute, "%s", string.upper(label))
    GUI:SameLine()
    local x1, y = GUI:GetCursorScreenPos()
    local rightX = GUI:GetWindowPos() + GUI:GetWindowContentRegionMax()
    if rightX > x1 + 8 then GUI:AddRectFilled(x1 + 8, y + 7, rightX, y + 8, u32(C.border_soft2)) end
    GUI:Dummy(1, 14)
end

function g.sectionHeader(label)
    GUI:Spacing()
    g.captionDivider(label)
end

-- ============================================================
-- Setting rows: label on the left, value at the LABEL_W column. A label
-- too wide for the column pushes the value to the next line (as in DR);
-- labels are capped at the row width and the full text is the tooltip.
-- ============================================================
function g.alignedLabel(label, tooltip)
    local x0 = GUI:GetCursorPosX()
    local text = g.fitText(label, UI.LABEL_W + UI.INPUT_W - x0)
    GUI:AlignFirstTextHeightToWidgets()
    GUI:Text(text)
    g.trackWidth()
    if GUI:IsItemHovered() then GUI:SetTooltip(tooltip or label) end
    if x0 + GUI:CalcTextSize(text) + 6 > UI.LABEL_W then
        GUI:SetCursorPosX(UI.LABEL_W)
    else
        GUI:SameLine(UI.LABEL_W, 0)
    end
end

-- drawValue draws the control; the hint shows as a tooltip on label and value.
function g.formRow(label, hint, drawValue)
    g.alignedLabel(label, hint and hint ~= "" and (label .. "\n" .. hint) or nil)
    drawValue()
    g.trackWidth()
    if hint and hint ~= "" and GUI:IsItemHovered() then GUI:SetTooltip(hint) end
end

-- Boolean row: unlabeled checkbox in the value column. Returns value, changed.
function g.formBool(label, hint, id, value)
    local changed
    g.formRow(label, hint, function() value, changed = GUI:Checkbox("##" .. id, value) end)
    return value, changed
end

-- Bounded number row. fmt carries the unit in the readout ("%d px").
-- Returns value, changed.
function g.formSlider(label, hint, id, value, low, high, fmt, integer)
    local changed
    g.formRow(label, hint, function()
        GUI:PushItemWidth(UI.INPUT_W)
        if integer then value, changed = GUI:SliderInt("##" .. id, value, low, high, fmt or "%d")
        else value, changed = GUI:SliderFloat("##" .. id, value, low, high, fmt or "%.2f") end
        GUI:PopItemWidth()
    end)
    return value, changed
end

-- Fixed-width controls and bounded popups keep long choices from resizing windows.
function g.fitText(text, width)
    text = tostring(text):gsub("[\r\n\t]", " ")
    if GUI:CalcTextSize(text) <= width then return text end
    while #text > 0 and GUI:CalcTextSize(text .. "...") > width do
        local last = #text
        while last > 1 and text:byte(last) >= 128 and text:byte(last) < 192 do last = last - 1 end
        text = text:sub(1, last - 1)
    end
    return text .. "..."
end
function g.compactCombo(id, selected, options, width)
    width = width or UI.INPUT_W
    local display = {}
    for i, option in ipairs(options) do display[i] = g.fitText(option, width - 32) end
    GUI:PushItemWidth(width)
    local value, changed
    local ok, err = xpcall(function() value, changed = GUI:Combo(id, selected, display, 8) end,
        function(reason) return debug and debug.traceback and debug.traceback(tostring(reason),2) or tostring(reason) end)
    GUI:PopItemWidth()
    if not ok then error("[FightPlan.gui.compactCombo] " .. id .. ": " .. tostring(err), 0) end
    g.trackWidth()
    if GUI:IsItemHovered() then GUI:SetTooltip(options[value] or "") end
    return value, changed
end

-- ============================================================
-- Buttons
-- ============================================================
local function pushButtonState(active)
    if active then
        pushColor4(GUI.Col_Button,        C.accent)
        pushColor4(GUI.Col_ButtonHovered, C.accent_hov)
        pushColor4(GUI.Col_ButtonActive,  C.accent_act)
        pushColor4(GUI.Col_Text,          {1,1,1,1})
    else
        pushColor4(GUI.Col_Button,        C.bg_control)
        pushColor4(GUI.Col_ButtonHovered, C.bg_ctrl_hov)
        pushColor4(GUI.Col_ButtonActive,  C.bg_ctrl_act)
        pushColor4(GUI.Col_Text,          C.text_dim)
    end
end

-- Toggle button — accent when active, bg_control when not.
function g.toggleButton(label, captureId, active, onClick, w, h)
    pushButtonState(active)
    if GUI:Button(label .. "##" .. captureId, w or UI.HUB_BTN_W, h or UI.HUB_BTN_H) then
        onClick()
    end
    GUI:PopStyleColor(4)
end

-- Primary action button in a g.PAL_* palette. Returns true on click.
function g.colorButton(label, palette, w, h)
    local p = palette
    GUI:PushStyleColor(GUI.Col_Button,        p[1], p[2], p[3], 1)
    GUI:PushStyleColor(GUI.Col_ButtonHovered, p[4], p[5], p[6], 1)
    GUI:PushStyleColor(GUI.Col_ButtonActive,  p[7], p[8], p[9], 1)
    GUI:PushStyleColor(GUI.Col_Text,          p[10], p[11], p[12], 1)
    local clicked = GUI:Button(label, w or 0, h or UI.BTN_H + 2)
    GUI:PopStyleColor(4)
    return clicked
end

-- Top tab strip: equal-width filled tabs across the row, accent on the
-- active one. tabs = { {id=, label=} }; onSelect(id) fires on click.
function g.drawTopTabs(id, tabs, selectedId, onSelect)
    local w = math.floor((GUI:GetContentRegionAvailWidth() - (#tabs - 1)) / #tabs)
    for i, tab in ipairs(tabs) do
        if i > 1 then GUI:SameLine(0, 1) end
        pushButtonState(tab.id == selectedId)
        if GUI:Button(tab.label .. "##" .. id .. tab.id, w, UI.TAB_H) then onSelect(tab.id) end
        GUI:PopStyleColor(4)
    end
end

-- Segmented control: buttons in a tight row, accent on the active one.
-- items = { "label", ... }; selectedIdx is 1-based; onSelect(i) on click.
function g.segmented(id, items, selectedIdx, onSelect)
    for i, label in ipairs(items) do
        if i > 1 then GUI:SameLine(0, 0) end
        pushButtonState(i == selectedIdx)
        if GUI:Button(label .. "##seg_" .. id .. i, 0, UI.ROW_H) then onSelect(i) end
        GUI:PopStyleColor(4)
    end
end

-- Status footer drawn inline at the end of a window: separator, a square
-- status dot (live = green, idle = mute, warn = yellow), left text, and right
-- text anchored to the content edge (drawn, so it never widens the window).
function g.statusFooter(opts)
    GUI:Separator()
    local dot = opts.dot == "idle" and C.text_mute or opts.dot == "warn" and C.yellow or C.green
    local sx, sy = GUI:GetCursorScreenPos()
    GUI:Dummy(10, 14)
    GUI:AddRectFilled(sx + 1, sy + 4, sx + 7, sy + 10, u32(dot))
    local leftEnd = sx + 16
    if opts.left then
        GUI:SameLine(0, 6)
        g.coloredText(C.text_dim, "%s", opts.left)
        leftEnd = leftEnd + GUI:CalcTextSize(opts.left)
    end
    if opts.right then
        local rightX = GUI:GetWindowPos() + GUI:GetWindowContentRegionMax()
        local x = rightX - GUI:CalcTextSize(opts.right)
        if x > leftEnd + 8 then GUI:AddText(x, sy, u32(C.text_mute), opts.right) end
    end
end
