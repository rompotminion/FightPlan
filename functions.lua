local jobMap = {
    ADV = 0, GLD = 1, PGL = 2, MRD = 3, LNC = 4, ARC = 5, CNJ = 6, THM = 7, CRP = 8, BSM = 9,
    ARM = 10, GSM = 11, LTW = 12, WVR = 13, ALC = 14, CUL = 15, MIN = 16, BTN = 17, FSH = 18,
    PLD = 19, MNK = 20, WAR = 21, DRG = 22, BRD = 23, WHM = 24, BLM = 25, ACN = 26, SMN = 27,
    SCH = 28, ROG = 29, NIN = 30, MCH = 31, DRK = 32, AST = 33, SAM = 34, RDM = 35, BLU = 36,
    GNB = 37, DNC = 38, RPR = 39, SGE = 40, VPR = 41, PCT = 42
  }
  
  local roleMap = {
    DPS = { "MNK", "DRG", "NIN", "SAM", "RPR", "VPR", "MCH", "BRD", "DNC", "BLM", "RDM", "SMN", "PCT", "BLU" },
    Melee = { "MNK", "DRG", "NIN", "SAM", "RPR", "VPR" },
    Caster = { "BLM", "SMN", "RDM", "BLU", "PCT" },
    Ranged = { "BRD", "MCH", "DNC" },
    Tank = { "PLD", "WAR", "DRK", "GNB" },
    Healer = { "WHM", "SCH", "AST", "SGE" },
    Regen = { "WHM", "AST" },
    Shield = { "SCH", "AST" },
    Support = { "PLD", "WAR", "DRK", "GNB", "WHM", "SCH", "AST", "SGE" },
    MeleeRange = { "MNK", "DRG", "NIN", "SAM", "RPR", "VPR", "PLD", "WAR", "DRK", "GNB" },
    CasterRange = { "MCH", "BRD", "DNC", "BLM", "RDM", "SMN", "PCT", "BLU", "WHM", "SCH", "AST", "SGE" },
    DoTBL = { "MNK", "DRG", "SAM", "BRD", "WHM", "SCH", "AST", "SGE" }
  }
  
  local function getJob(ent)
    return ent and TensorCore.mGetEntity(ent).job or Player.job
  end
  
  for jobName, jobId in pairs(jobMap) do
    FightPlan["is" .. jobName] = function(ent) return getJob(ent) == jobId end
  end
  
  for roleName, jobList in pairs(roleMap) do
    FightPlan["is" .. roleName] = function(ent)
      ent = ent or Player.id
      for _, jobName in ipairs(jobList) do
        if FightPlan["is" .. jobName](ent) then return true end
      end
      return false
    end
  end
  
  FightPlan.hasDoTBL = function(ent)
    ent = ent or Player.id
    for _, jobName in ipairs(roleMap.DoTBL) do
      if FightPlan["is" .. jobName](ent) then return true end
    end
    return false
  end
  
  FightPlan.has2mPot = function()
    return In(Player.job, 20, 21, 22, 23, 24, 30, 31, 32, 34, 35, 37, 38, 39, 41)
  end
  
  FightPlan.isMT = function()
    return _G["ACR_" .. gACRSelectedProfiles[TensorCore.mGetPlayer().job] .. "_TankStance"] == "mt"
  end
  
  FightPlan.isOT = function()
    return _G["ACR_" .. gACRSelectedProfiles[TensorCore.mGetPlayer().job] .. "_TankStance"] == "ot"
  end
  
  FightPlan.potCD = function()
    local pot = ActionList:Get(1, 846)
    return pot and math.floor((pot.cdmax - pot.cd) * 1000) or 0
  end
  
  FightPlan.assistOn = function()
    if not FFXIV_Common_BotRunning then
      ml_global_information.ToggleRun()
      d("[FightPlan] Assist On")
    end
  end
  
  FightPlan.assistOff = function()
    if FFXIV_Common_BotRunning then
      ml_global_information.ToggleRun()
      d("[FightPlan] Assist Off")
    end
  end
  
  local function toggleVar(prefix, varname, state)
    if not varname then
      d("[FightPlan." .. prefix .. "] Error: Variable is nil. Use quotes around the variable name. Example: FightPlan." .. prefix .. "(\"Burn\", true)")
      return
    end
    local player = TensorCore.mGetPlayer()
    if not player then
      d("[FightPlan." .. prefix .. "] Error: player is nil")
      return
    end
    local currentACR = gACRSelectedProfiles[player.job]
    if not currentACR then
      d("[FightPlan." .. prefix .. "] Error: no ACR profile selected")
      return
    end
    local varPath = "ACR_" .. currentACR .. "_" .. prefix .. "_" .. varname
    _G[varPath] = state
    d("[FightPlan." .. prefix .. "] Set " .. varPath .. " to " .. tostring(state))
  end
  
  FightPlan.qt = function(varname, state) toggleVar("", varname, state) end
  FightPlan.hb = function(varname, state) toggleVar("Hotbar", varname, state) end
  FightPlan.tb = function(varname, state) toggleVar("Tankbar", varname, state) end
  FightPlan.hl = function(varname, state) toggleVar("Healbar", varname, state) end