-- fpGui.lua — bundled visual design system for FightPlan, ReactionHelper,
-- and PartyPlan. Ported from DiminishingReturns/drGui.lua so FightPlan stays
-- self-contained (no dependency on DiminishingReturns).
--
-- USAGE
--   local g = FightPlan.gui
--   g.pushTheme()
--   GUI:Begin("FightPlan", ...)
--   g.alignedLabel("Setting")
--   GUI:PushItemWidth(g.UI.INPUT_W)
--   ...
--   GUI:End()
--   g.popTheme()

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
    text          = {0.839, 0.847, 0.859, 1.00},
    text_dim      = {0.541, 0.553, 0.573, 1.00},
    text_mute     = {0.357, 0.369, 0.388, 1.00},
    accent        = {0.239, 0.420, 0.690, 1.00},
    accent_hov    = {0.302, 0.494, 0.784, 1.00},
    accent_act    = {0.173, 0.314, 0.573, 1.00},
    green         = {0.200, 0.800, 0.333, 1.00},
    yellow        = {1.000, 0.800, 0.102, 1.00},
    red           = {0.878, 0.282, 0.282, 1.00},
    lightblue     = {0.345, 0.694, 0.957, 1.00},
}
local C = g.C

-- ============================================================
-- Pixel constants
-- ============================================================
g.UI = {
    LABEL_W    = 120,
    INPUT_W    = 200,
    SLIDER_W   = 200,
    ROW_H      = 20,
    BTN_H      = 22,
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

-- ============================================================
-- Theme push/pop. Pops 14 style colors — matches what pushTheme adds.
-- ============================================================
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
end

function g.popTheme() GUI:PopStyleColor(14) end

-- ============================================================
-- Inline colored text. Format string + format args.
-- ============================================================
function g.coloredText(c, fmt, ...)
    pushColor4(GUI.Col_Text, c)
    GUI:Text(string.format(fmt, ...))
    GUI:PopStyleColor(1)
end

-- ============================================================
-- Setting-row label that jumps the cursor to a fixed input column.
-- ============================================================
function g.alignedLabel(label)
    GUI:Text(label)
    GUI:SameLine(UI.LABEL_W, 0)
end

-- ============================================================
-- Toggle button — accent when active, bg_control when not.
-- ============================================================
function g.toggleButton(label, captureId, active, onClick, w, h)
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
    if GUI:Button(label .. "##" .. captureId, w or UI.HUB_BTN_W, h or UI.HUB_BTN_H) then
        onClick()
    end
    GUI:PopStyleColor(4)
end
