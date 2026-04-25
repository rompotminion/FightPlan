local multiRefObjects = {
}

-- Splatoon (Savage)
local config = {
    mapID = 344,
    
    dropdowns = {
        -- Template for dropdown settings
        -- {
        --     label = "Setting Name",
        --     id = "uniqueSettingId",
        --     options = {"Option1", "Option2", "Option3"},
        --     useIndex = true, -- true to store the index, false to store the option string
        --     tooltip = "Description of what this setting does.",
        --     condition = function() -- Optional condition
        --         return FightPlan.isTank() -- Example: only show for tanks
        --     end
        -- },
		{
			label = "First Manta Baiting",
			id = "r6MantaBait123",
			options = {"Left", "Right", "None"},
			tooltip = "If you are or are not baiting First set of Mantas.",
			condition = function()
				return FightPlan.isRanged() or FightPlan.isCaster() or FightPlan.isHealer()
			end
		},
		{
			label = "Second Manta Baiting",
			id = "r6MantaBait2",
			options = {"Left", "Right", "None"},
			tooltip = "If you are or are not baiting Second set of Mantas.",
			condition = function()
				return FightPlan.isRanged() or FightPlan.isCaster() or FightPlan.isHealer()
			end
		},
		{
			label = "Thunder Bridge",
			id = "r6Bridge",
			options = {"PF", "CW(Left)", "CCW(Right)"},
			tooltip = "PF uses EU PF Strats.\bPF puts Supports CW (Left looking In)",
    },
},
	
    
    checkboxes = {
        -- Template for checkbox settings
        -- {
        --     label = "Setting Name",
        --     id = "uniqueSettingId",
        --     tooltip = "Description of what this setting does.",
        --     condition = function() -- Optional condition
        --         return FightPlan.isTank() -- Example: only show for tanks
        --     end
        -- },

        {
            label = "Pot Feather Ray",
            id = "r6HoldAdds",
            tooltip = "Holds 2mins and pot for the first set of Feather Rays",
        },
        {
            label = "Adds Targeter",
            id = "r6TargetAdds",
            tooltip = "Jabber - Cat - Nearest priority",
        },
        {
            label = "Lava Lockface",
            id = "r6LockFaceLava",
            tooltip = "Auto Locks face for Lava Island",
        },
    }
}

return config