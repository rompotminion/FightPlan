-- Legacy reactions share the actual PartyPlan object, including future fields.
if type(PartyPlan) ~= "table" then
    d("[FightPlan.Compatibility] PartyPlan dependency missing; shim not installed.")
    return
end
if DedoDSRHelper ~= nil and DedoDSRHelper ~= PartyPlan then
    d("[FightPlan.Compatibility] DedoDSRHelper already belongs to another addon; shim not installed.")
    return
end
if PartyPlan.Var == nil then PartyPlan.Var = {} end
if type(PartyPlan.Var) ~= "table" then
    d("[FightPlan.Compatibility] PartyPlan.Var must be a table; shim not installed.")
    return
end
DedoDSRHelper = PartyPlan
