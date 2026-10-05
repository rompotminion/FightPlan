# FightPlan

A Lua addon for FFXIVMinion that gives fight reactions per-job settings and a shared set of helpers. Plans define the toggles and dropdowns a player sees for a fight; reactions read the choices as plain values.

Open the editor: https://rompotminion.github.io/FightPlan/

## Install

Clone or copy this folder into `LuaMods` as `FightPlan`, then reload Lua. Requires `minionlib`, `FFXIVMINION`, `TensorCore` and `AnyoneCore`.

## What's in it

| File | Purpose |
|---|---|
| `planSchema.lua` | Compiles plan files into controls. |
| `FightPlan.lua` | Runtime: loads plans, saves choices per job, exposes values as `FightPlan.<id>`, creates the shape drawers. |
| `PartyPlan.lua` | Party and positioning helpers: closest/furthest player queries, placement solvers, on-screen timers, partner tracking. |
| `functions.lua` | Role and job predicates (`FightPlan.isTank()`, `FightPlan.isDNC()`, ...). |
| `datagui.lua` | Reaction Helper window showing live target, timer and position data. |
| `fpGui.lua` | Shared ImGui theme and widgets. |
| `plans/` | Plan files, loaded at reload. |

## Plans

A plan is a Lua file in `plans/` that returns one ordered list of controls:

```lua
return {
    version = 2,
    name = "My Fight",
    mapID = 1226,           -- omit for global settings
    controls = {
        { type = "toggle", id = "myFightInvuln", label = "Invuln First Buster", showFor = { "Tank" } },
        { type = "select", id = "myFightSide",   label = "Side", options = { "Left", "Right" } },
    },
}
```

A reaction reads the choice directly:

```lua
if FightPlan.myFightInvuln then ... end
return FightPlan.myFightSide == "Left"
```

| Field | Meaning |
|---|---|
| `type`, `id`, `label` | Required. `type` is `"toggle"` or `"select"`. |
| `options`, `store` | Select only. `store` is `"value"` (option text, default) or `"index"` (1..n). |
| `default` | Boolean for toggles; option text or number for selects. Saved choices win. |
| `tooltip`, `section` | Help text and a group heading. |
| `showFor`, `showOn` | Show by role or job (`{ "Tank", "DNC" }`) and by map type (`"raid"`, `"autoMarker"`). |
| `condition`, `conditions` | Show only when your own Lua variables match. Syntax is checked at load; failures are reported, not hidden. |

Keep IDs, option order and storage modes stable once players have saved choices.

## Plan editor

A browser editor builds plans without hand-writing Lua: add controls, set visibility and conditions, preview by job and map, then export the `.lua` file into `plans/`. It runs entirely in the browser, never executes imported scripts and never talks to the game.

## Reaction API

| Area | Entry points |
|---|---|
| Shape drawers | `fpRed`, `fpGreen`, `fpBlue`, ... plus role aliases such as `fpDanger`, `fpSafe`, `fpSpread`, `fpGroupStack`. Preconfigured `Argus2.ShapeDrawer` objects; use them as-is. |
| Roles | `FightPlan.Role` (`M1`..`H2`), `FightPlan.RoleIndex`, and predicates by job, role and group. |
| Bot control | `FightPlan.assistOn()`, `FightPlan.assistOff()`, ACR toggles `FightPlan.qt/hb/tb/hl(name, bool)`. |
| Party | `PartyPlan.getClosestPlayersToEnt`, `getFurthestInCardinal`, `findBestCoordinate`, `equalizeHP`, timers. |
