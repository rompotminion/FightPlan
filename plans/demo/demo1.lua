local multiRefObjects = {
}

-- Arcadion 1 (Savage)
local config = {
    mapID = 344,
    
    dropdowns = {
        {
            label = "Protean",
            id = "r1Protean",
            options = {"NorthEast", "East", "SouthEast", "South", "SouthWest", "West", "NorthWest", "North"},
            useIndex = true,
            tooltip = "Choose where you bait proteans."
        },
        {
            label = "Pairs",
            id = "r1Pairs",
            options = {"CW", "CCW"},
            useIndex = true,
            tooltip = "Choose where pair spots are taken relative to your Protean."
        }
    },
    
    checkboxes = {
        {
            label = "True North",
            id = "r1TN",
            tooltip = "If you're doing mechanics based on True North."
        },
        {
            label = "Intercardinal",
            id = "r1InterStacks",
            tooltip = "If you're stacking on Intercardinals (Hector)."
        },
        {
            label = "Invuln First Buster",
            id = "r1Invuln",
            tooltip = "If you're Invulning the first tank buster.",
            condition = function()
                return FightPlan.isTank()
            end
        }
    }
}

return config
