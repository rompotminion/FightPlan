-- FightPlan profile. Add a control to the controls list.
return {
    version = 2,
    name = "Global Settings",
    controls = {
        {
            type = "toggle",
            id = "autoMarker",
            label = "Auto Marker",
            tooltip = "Enables Auto Marker.",
            showOn = "autoMarker",
        },
        {
            type = "toggle",
            id = "usePot",
            label = "Potion",
            tooltip = "Determines whether or not Potion toggle enables on prepull.",
        },
        {
            type = "toggle",
            id = "twoMinPot",
            label = "2m Potion",
            tooltip = "Changes the first potion to be at the second 2m window.",
            conditions = {
                {
                    type = "all",
                    checks = {
                        {
                            type = "boolean",
                            variable = "FightPlan.usePot",
                            value = true,
                            result = true,
                        },
                        {
                            -- ACR4 profiles (e.g. TensorViper4) handle 2m pots themselves.
                            type = "lua",
                            expression = "not (Player and gACRSelectedProfiles and tostring(gACRSelectedProfiles[Player.job] or ''):find('4$') ~= nil)",
                            result = true,
                        },
                    },
                },
            },
        },
        {
            type = "toggle",
            id = "techOpener",
            label = "Tech Opener",
            tooltip = "Opens with Technical instead of Standard.",
            showFor = {"DNC"},
        },
        {
            type = "toggle",
            id = "tradePersonal",
            label = "Trade Personals",
            tooltip = "Trade your personal (25s) cooldowns with co-tank.",
            showFor = {"Tank"},
            showOn = "raid",
        },
        {
            type = "toggle",
            id = "altMit",
            label = "Alt Mitigation",
            tooltip = "Uses alternative mitigation timeline.",
            showFor = {"Melee", "Tank", "Caster"},
            showOn = "raid",
        },
        {
            type = "toggle",
            id = "Debug",
            label = "Debug",
            tooltip = "Enables Debug Draws and Mechanics Information.",
        },
    },
}
