local multiRefObjects = {
}

local config = {
    
    dropdowns = {
        {
            label = "Select Role",
            id = "Role",
            options = {"M1", "M2", "R1", "R2", "MT", "OT", "H1", "H2"},
            useIndex = false,
            tooltip = "Select your role.",
            condition = function()
                return FightPlan.RaidMaps[Player.localmapid]
            end
        }
    },
    
    checkboxes = {
        {
            label = "Use Pot",
            id = "usePot",
            tooltip = "Determines whether or not Potion toggle enables on prepull.",
        },
        {
            label = "Two Minute Pot",
            id = "twoMinPot",
            tooltip = "Changes the first potion to be at the second 2m window.",
        },
        {
            label = "Technical Opener",
            id = "techOpener",
            tooltip = "Opens with Technical instead of Standard",
            condition = function ()
                return FightPlan.isDNC()
                
            end
        }
    }
}

return config
