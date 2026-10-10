-- Frame draws disappear automatically on completion, cancellation, or disable.
PartyPlan.AOEProgress = {preview = false, faults = {}, overrides = {}}
local P = PartyPlan.AOEProgress
local shapes = {"circle", "rectangle", "square", "cone", "donut", "donutCone", "cross", "arrow", "chevron"}
local function number(v, name)
    assert(type(v) == "number" and v == v and math.abs(v) < math.huge,
        "[PartyPlan.AOEProgress] invalid " .. name .. "=" .. tostring(v))
    return v
end
local function report(key, err)
    local previous = P.faults[key]
    if previous then previous.repeats = previous.repeats + 1; return end
    P.faults[key] = {error = tostring(err), repeats = 0}
    d("[PartyPlan.AOEProgress] " .. key .. ": " .. tostring(err))
end
local function traceback(err)
    return debug and debug.traceback and debug.traceback(tostring(err), 2) or tostring(err)
end

-- Explicit geometry also supports callers whose shape is absent from Argus metadata.
-- startTime is Now() milliseconds; duration is seconds; angle is radians.
function PartyPlan.DrawAOEProgress(a, drawer, now)
    local elapsed = (number(now or Now(), "now") - number(a.startTime, "startTime")) / 1000
    local duration = number(a.duration, "duration")
    if duration <= 0 or elapsed <= 0 or elapsed >= duration then return false end
    local p = elapsed / duration
    local x, y, z = number(a.x, "x"), number(a.y, "y"), number(a.z, "z")
    local length = number(a.length, "length")
    assert(length > 0, "[PartyPlan.AOEProgress] length must be positive")
    local h, shape = a.heading or 0, a.shape
    number(h, "heading")
    if shape == "circle" then drawer:addCircle(x,y,z,length*p)
    elseif shape == "donut" or shape == "donutCone" then
        local inner = number(a.innerRadius, "innerRadius")
        assert(inner >= 0 and inner < length, "[PartyPlan.AOEProgress] invalid donut radii")
        local outer = inner + (length-inner)*p
        if shape == "donut" then drawer:addDonut(x,y,z,inner,outer)
        else drawer:addDonutCone(x,y,z,inner,outer,number(a.angle,"angle"),h) end
    elseif shape == "cone" then drawer:addCone(x,y,z,length*p,number(a.angle,"angle"),h)
    else
        local width = shape == "square" and length or number(a.width,"width")
        assert(width > 0, "[PartyPlan.AOEProgress] width must be positive")
        if shape == "rectangle" or shape == "square" then
            -- Forward rectangles grow about their geometric center, staying inside the base.
            if a.forward then x=x+math.sin(h)*length/2; z=z+math.cos(h)*length/2 end
            drawer:addCenteredRect(x,y,z,length*p,width*p,h)
        -- Keep the skeleton anchored inside the final footprint. Scaling lengths
        -- moves disconnected arms/arrowheads across the shape's empty regions.
        elseif shape == "cross" then drawer:addCross(x,y,z,length,width*p,h)
        elseif shape == "arrow" then drawer:addArrow(x,y,z,h,length,width*p,a.tipLength or width,(a.tipWidth or width*2)*p)
        elseif shape == "chevron" then drawer:addChevron(x,y,z,length,width*p,h)
        else error("[PartyPlan.AOEProgress] unsupported shape="..tostring(shape)) end
    end
    return true
end

local function geometry(a)
    local custom = P.overrides[a.aoeID]
    local s = MoogleTelegraphs and MoogleTelegraphs.Settings
    local render = s and s.aoeIDUserSetRender and s.aoeIDUserSetRender[a.aoeID]
    if s and s.aoeIDUserBlacklist and s.aoeIDUserBlacklist[a.aoeID] then return nil end
    local result = {x=a.x,y=a.y,z=a.z,heading=a.heading,length=a.aoeLength,width=a.aoeWidth,
        startTime=a.startTime,duration=a.duration}
    if custom then for k,v in pairs(custom) do result[k]=v end
    elseif a.aoeCastType == 2 then
        local circle = s and s.aoeIDUserSetCircles and s.aoeIDUserSetCircles[a.aoeID]
        local donut = s and s.aoeIDUserSetDonuts and s.aoeIDUserSetDonuts[a.aoeID]
        result.shape = donut and "donut" or "circle"
        result.innerRadius = donut and donut.radius
        result.length = circle and circle.radius or result.length
    elseif a.aoeCastType == 4 then result.shape="rectangle"; result.forward=true
    elseif a.aoeCastType == 3 then
        local cone = s and s.aoeIDUserSetCones and s.aoeIDUserSetCones[a.aoeID]
        assert(cone, "cone angle unavailable; supply Moogle cone override or AOEProgress.overrides")
        result.shape="cone"; result.angle=math.rad(cone.angle)
    else error("unresolved aoeCastType="..tostring(a.aoeCastType).."; supply AOEProgress.overrides") end
    local delay = render and render.delay or a.delay or 0
    number(delay,"delay")
    if Now() < result.startTime + delay*1000 then return nil end
    return result
end

function PartyPlan.DrawAOEProgressSettings()
    local g=FightPlan.gui
    g.captionDivider("AOE Cast Progress")
    local enabled, changed = g.formBool("Show Cast Progress", "White fill reaches the boundary at cast completion. Crosses, arrows and chevrons fill outward from their fixed centerlines.",
        "PPProgress", FightPlan.settings.partyPlanAOEProgress == true)
    if changed then
        FightPlan.settings.partyPlanAOEProgress=enabled
        P.faults={}; P.stopped=false
        PartyPlan.SaveDefaults()
    end
    local preview, previewChanged = g.formBool("Loop Shape Preview", "Cycles every shape at your position, five seconds each.", "PPProgressPreview", P.preview)
    if previewChanged then
        P.preview=preview; P.previewStart=Now(); P.faults={}; P.stopped=false
        local player=TensorCore.mGetPlayer()
        assert(player and player.pos,"[PartyPlan.AOEProgress.Preview] player position unavailable")
        P.previewPos={x=player.pos.x,y=player.pos.y,z=player.pos.z, map=player.localmapid}
    end
    for key, fault in pairs(P.faults) do
        g.wrappedText(g.C.red, "Progress error: "..key..": "..fault.error.." (repeats: "..fault.repeats..")")
    end
end

function PartyPlan.DrawAOEProgressFrame()
    if not P.preview and FightPlan.settings.partyPlanAOEProgress ~= true then return end
    local ok,err=xpcall(function()
        assert(TensorCore and type(TensorCore.getCachedDrawer)=="function", "TensorCore.getCachedDrawer unavailable")
        local drawer=TensorCore.getCachedDrawer(nil,nil,GUI:ColorConvertFloat4ToU32(1,1,1,0.45),4294967295,2)
        assert(drawer,"TensorCore.getCachedDrawer returned nil")
        drawer:setGradient(0,1,0)
        if P.preview then
            local player=TensorCore.mGetPlayer()
            if not player or player.localmapid ~= P.previewPos.map then P.preview=false; return end
            local elapsed=Now()-P.previewStart
            local index=math.floor(elapsed/5000)%#shapes+1
            local a={shape=shapes[index],x=P.previewPos.x,y=P.previewPos.y,z=P.previewPos.z,
                heading=0,length=8,width=4,innerRadius=3,angle=math.pi/2,
                duration=4,startTime=Now()-elapsed%5000}
            if elapsed%5000<4000 then
                local base=TensorCore.getMoogleDrawer()
                assert(base,"TensorCore.getMoogleDrawer returned nil")
                local static={}
                for k,v in pairs(a) do static[k]=v end
                static.duration=1; static.startTime=Now()-999
                PartyPlan.DrawAOEProgress(static,base)
                PartyPlan.DrawAOEProgress(a,drawer)
            end
        end
        if FightPlan.settings.partyPlanAOEProgress == true then
            assert(Argus and type(Argus.getCurrentAOEs)=="function","Argus.getCurrentAOEs unavailable")
            local aoes=Argus.getCurrentAOEs()
            assert(type(aoes)=="table","Argus.getCurrentAOEs returned "..type(aoes))
            for _,a in pairs(aoes) do
                if not a.friendly and a.duration and a.duration>0 then
                    local success, failure=xpcall(function()
                        local g=geometry(a)
                        if g then PartyPlan.DrawAOEProgress(g,drawer) end
                    end,traceback)
                    if not success then report("action="..tostring(a.aoeID).." entity="..tostring(a.entityID),failure) end
                end
            end
        end
    end,traceback)
    if not ok then P.preview=false; P.stopped=true; report("Frame",err) end
end

RegisterEventHandler("Gameloop.Draw", function()
    if not P.stopped then PartyPlan.DrawAOEProgressFrame() end
end, "PartyPlan-AOEProgress")
