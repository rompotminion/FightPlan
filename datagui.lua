ReactionHelper = {
    open = false,
    visible = false,
    fontScale = 1.0
}

local function RH_SaveScale()
    if FightPlan and FightPlan.settings then
        FightPlan.settings.dataGuiScale = ReactionHelper.fontScale
        local path = GetStartupPath() .. "\\LuaMods\\FightPlan\\settings.lua"
        persistence.store(path, FightPlan.settings)
    end
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
    g.pushTheme()

    local window_flags = GUI.WindowFlags_AlwaysAutoResize
    ReactionHelper.visible, ReactionHelper.open = GUI:Begin("Data", ReactionHelper.open, window_flags)

    if ReactionHelper.visible then
        local scale = ReactionHelper.fontScale

        GUI:SetWindowFontScale(scale)

        local timer = TensorReactions_CurrentTimer or 0
        GUI:Text("Timer: " .. (timer == 0 and "0" or string.format("%.1f", timer)))

        local lb_gauge = TensorCore.getLBGauge() or 0
        GUI:Text("LB: " .. (lb_gauge == 0 and "No LB" or string.format("%.0f", lb_gauge)))

        local target = TensorCore.mGetTarget()
        local target_hp = target and target.hp and target.hp.percent or nil
        GUI:Text(target_hp == nil and "No Target" or "HP: " .. string.format("%.0f", target_hp) .. "%")

        local target_id = target and target.contentid or nil
        GUI:Text(target_id == nil and "No Target" or string.format("tID: %.0f", target_id))

        local ttk = target and TensorCore.calcTimeToKill(target.id, 1000) or nil
        local ttk_display = (ttk == nil or ttk == 0 or ttk == 1000) and "N/A" or string.format("%.0fs", ttk)
        GUI:Text("TTK: " .. ttk_display)

        local fight_id = AnyoneCore.Data.currentFightID or 0
        GUI:Text("ID: " .. (fight_id == 0 and "No ID" or tostring(fight_id)))

        if FightPlan then
            GUI:SetWindowFontScale(scale * 0.8)
            local mit_phys = FightPlan.Physical or 0
            local mit_magic = FightPlan.Magical or 0
            g.coloredText(g.C.yellow, "%.1f%%", mit_phys)
            GUI:SameLine()
            g.coloredText(g.C.lightblue, "%.1f%%", mit_magic)
        end

        local player = TensorCore.mGetPlayer()
        if player then
            GUI:SetWindowFontScale(scale * 0.8)
            local x, y, z = player.pos.x, player.pos.y, player.pos.z
            GUI:Text("X:" .. string.format("%.2f", x) .. " Z:" .. string.format("%.2f", z))
            if y < -2 or y > 2 then
                GUI:Text("Y:" .. string.format("%.2f", y))
            end
        end

        GUI:SetWindowFontScale(1.0)
        GUI:Separator()
        GUI:Text("Scale")
        GUI:SameLine()
        GUI:PushItemWidth(80)
        local newScale, changed = GUI:SliderFloat("##dataScale", scale, 0.5, 3.0)
        GUI:PopItemWidth()
        if changed then
            ReactionHelper.fontScale = newScale
            RH_SaveScale()
        end
    end
    GUI:End()
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
