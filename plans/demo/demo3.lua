local multiRefObjects = {
}

-- The Weapon's Refrain (Ultimate)
local config = {
    mapID = 344,
    
    dropdowns = {
        {
            label = "Ifrit Nails",
            id = "uwuNails",
            options = {"Not Baiting", "Baiting East (1)", "Baiting West (2)"},
            useIndex = true,
            tooltip = "Choose which Nail you are baiting.",
            condition = function()
                return (FightPlan.isCaster() or FightPlan.isRanged())
            end
        },
        {
            label = "Titan Busters",
            id = "uwuTitanBuster",
            options = {"MT OT MT", "MT MT OT"},
            useIndex = true,
            tooltip = "Choose which Tank Busters you are taking.",
            condition = function()
                return FightPlan.isTank()
            end
        },
        {
            label = "Annihilation Orbs",
            id = "uwuAnniOrbs",
            options = {"Doing Orbs", "Not Doing Orbs"},
            useIndex = true,
            tooltip = "Choose if you are taking Anni Orbs.",
            condition = function()
                return (FightPlan.isTank() or FightPlan.isMelee())
            end
        },
        {
            label = "Roulette Mitigation",
            id = "uwuRoulette",
            options = {"1st Primal", "2nd Primal", "3rd Primal", "Default LPDU"},
            useIndex = true,
            tooltip = "Choose which Roulette you mitigate.",
            condition = function()
                return (FightPlan.isTank() or FightPlan.isRanged() or FightPlan.isCaster())
            end
        }
    },
    
    checkboxes = {
        {
            label = "Auto Move",
            id = "uwuAutoMove",
            tooltip = "Handles Automated Movement for:\nIfrit Transition\nTitan Jails" -- you can use \n for linebreak, as this will put the next text after it underneath.
        }
    }
}

return config