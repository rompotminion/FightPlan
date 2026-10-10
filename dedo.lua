-- Global table to store the draws
unsafeZones = {}


function isPositionInCone(centerPos, targetPos, maxRadius, angle, heading)
    local headingToTarget = TensorCore.getHeadingToTarget(centerPos,targetPos)
    local angleDiff = math.abs((heading - headingToTarget + math.pi) % (math.pi * 2) - math.pi)
    if angleDiff <= angle / 2 and TensorCore.getDistance2d(centerPos, targetPos) <= maxRadius then
        return true
    end
end

    -- too retarded to figure out the rectangle shit so i just use the triangle and re-arrange them to triangles feelskek
    -- helper func using cross product to check if point is in a triangle yoinked from https://stackoverflow.com/questions/2049582/how-to-determine-if-a-point-is-in-a-2d-triangle
local function crossProduct(p1, p2, p3)
    return (p2.x - p1.x) * (p3.z - p1.z) - (p2.z - p1.z) * (p3.x - p1.x)
end
local function isPointInTriangle(corner1, corner2, corner3, point)
    local d1 = crossProduct(corner1, corner2, point)
    local d2 = crossProduct(corner2, corner3, point)
    local d3 = crossProduct(corner3, corner1, point)

    return (d1 >= 0 and d2 >= 0 and d3 >= 0) or (d1 <= 0 and d2 <= 0 and d3 <= 0)
end

function isPositionInRect(originPos, targetPos, length, width, heading, duration)
    local origin = originPos
    local y = Player.pos.y or 0
    local duration = duration or 100
    local halfWidth = width / 2

    local corner1 = TensorCore.getPosInDirection(origin, heading - math.pi / 2, halfWidth) -- bottom left
    local corner2 = TensorCore.getPosInDirection(origin, heading + math.pi / 2, halfWidth) -- bottom right
    local corner3 = TensorCore.getPosInDirection(corner1, heading, length)  -- top left
    local corner4 = TensorCore.getPosInDirection(corner2, heading, length)  -- top right

    -- Debug draws to draw corners
    -- local smallSize = 0.2
    -- TensorCore.getMoogleDrawer():addTimedRect(duration, corner1.x, y, corner1.z, smallSize, smallSize, heading)
    -- TensorCore.getMoogleDrawer():addTimedRect(duration, corner2.x, y, corner2.z, smallSize, smallSize, heading)
    -- TensorCore.getMoogleDrawer():addTimedRect(duration, corner3.x, y, corner3.z, smallSize, smallSize, heading)
    -- TensorCore.getMoogleDrawer():addTimedRect(duration, corner4.x, y, corner4.z, smallSize, smallSize, heading)

    local isInsideTriangle1 = isPointInTriangle(corner1, corner2, corner3, targetPos)
    local isInsideTriangle2 = isPointInTriangle(corner2, corner3, corner4, targetPos)

    return isInsideTriangle1 or isInsideTriangle2
end


function isPositionInCircle(centerPos, targetPos, radius)
    local distance = math.sqrt((targetPos.x - centerPos.x)^2 + (targetPos.z - centerPos.z)^2)
    if distance <= radius then
        return true
    end

    return false
end


function isPositionInDonut(centerPos, targetPos, innerRadius, outerRadius)
    local distance = math.sqrt((targetPos.x - centerPos.x)^2 + (targetPos.z - centerPos.z)^2)
    if distance >= innerRadius and distance <= outerRadius then
        return true
    end
    return false
end

function addConeToUnsafeZones(duration,x, y, z, radius, angle, heading,delay)
    local delay = delay or 0
    -- Debug Draw
    -- TensorCore.getMoogleDrawer():addTimedCone(duration,x, y, z, radius, angle, heading, delay)
    local startTime = Now()+delay

    table.insert(unsafeZones, {
        shape = "cone",
        center = { x = x, y = y, z = z },
        radius = radius,
        angle = angle,
        heading = heading,
        duration = duration,
        time = Now(),
        startTime = startTime,
        delay = delay,
    })

    d("Cone added to unsafe zones.")
end

function addRectToUnsafeZones(duration,x, y, z, length, width, heading,delay)

    local delay = delay or 0
    -- Debug Draw
    -- TensorCore.getMoogleDrawer():addTimedRect(duration,x, y, z, length, width, heading,delay)
    local startTime = Now()+delay
    table.insert(unsafeZones, {
        shape = "rectangle",
        center = { x = x, y = y, z = z },
        length = length,
        width = width,
        heading = heading,
        duration = duration,
        time = Now(),
        startTime = startTime,
        delay = delay
    })

    d("Rectangle added to unsafe zones.")
end


function addCircleToUnsafeZones(duration,x, y, z, radius,delay)
    local delay = delay or 0
    -- Debug Draw
    -- TensorCore.getMoogleDrawer():addTimedCircle(duration,x, y, z, radius,delay)
local startTime = Now()+delay
    table.insert(unsafeZones, {
        shape = "circle",
        center = { x = x, y = y, z = z },
        radius = radius,
        duration = duration,
        time = Now(),
        startTime = startTime,
        delay = delay,
    })
    d("Circle added to unsafe zones.")
end

function addDonutToUnsafeZones(duration,x, y, z, innerRadius, outerRadius,delay)
    local delay = delay or 0
    -- Debug Draw
    -- TensorCore.getMoogleDrawer():addTimedDonut(duration, x,y,z, innerRadius, outerRadius,delay)
    local startTime = Now() + delay
    table.insert(unsafeZones, {
        shape = "donut",
        center = { x = x, y = y, z = z },
        innerRadius = innerRadius,
        outerRadius = outerRadius,
        duration = duration,
        time = Now(),
        startTime = startTime,
        delay = delay
    })

    d("Donut added to unsafe zones.")
end

local HEADING_MODE = {
    FIXED = 1,      -- fixed heading keeps the provided one through out the duration of the unsafezone
    ENTITY = 2,     -- uses the "source" entitys heading and keeps updating it for the duration
    TARGET = 3      -- "target mode", sets a target for the source entitys heading to update towards, takes either a pos table for a fixed position or an entityID to aim towards
}


function addConeOnEntToUnsafeZones(duration, entityID, radius, angle, heading, delay, headingMode, target)
    local delay = delay or 0
    local headingMode = headingMode or HEADING_MODE.FIXED
    local startTime = Now() + delay
    local ent = TensorCore.mGetEntity(entityID)
    
    if not ent then return end

    -- Handle target which can be either position table or entity ID
    local targetPos = target
    if headingMode == HEADING_MODE.TARGET and type(target) == "number" then
        local targetEnt = TensorCore.mGetEntity(target)
        if targetEnt then
            targetPos = targetEnt.pos
        end
    end

    -- Calculate initial heading based on mode
    local initialHeading = heading
    if headingMode == HEADING_MODE.ENTITY then
        initialHeading = ent.pos.h
    elseif headingMode == HEADING_MODE.TARGET and targetPos then
        initialHeading = TensorCore.getHeadingToTarget(ent.pos, targetPos)
    end

    table.insert(unsafeZones, {
        shape = "cone",
        entityID = entityID,
        radius = radius,
        angle = angle,
        heading = initialHeading,
        headingMode = headingMode,
        targetPos = targetPos,  -- Store target position if provided
        duration = duration,
        time = Now(),
        startTime = startTime,
        delay = delay,
        center = { 
            x = ent.pos.x, 
            y = ent.pos.y, 
            z = ent.pos.z 
        }
    })

    d("Entity-attached cone added to unsafe zones.")
end

function addRectOnEntToUnsafeZones(duration, entityID, length, width, heading, delay, headingMode, target)
    local delay = delay or 0
    local headingMode = headingMode or HEADING_MODE.FIXED
    local startTime = Now() + delay
    local ent = TensorCore.mGetEntity(entityID)
    
    if not ent then return end

 
    local targetPos = target
    if headingMode == HEADING_MODE.TARGET and type(target) == "number" then
        local targetEnt = TensorCore.mGetEntity(target)
        if targetEnt then
            targetPos = targetEnt.pos
        end
    end

    local initialHeading = heading
    if headingMode == HEADING_MODE.ENTITY then
        initialHeading = ent.pos.h
    elseif headingMode == HEADING_MODE.TARGET and targetPos then
        initialHeading = TensorCore.getHeadingToTarget(ent.pos, targetPos)
    end

    table.insert(unsafeZones, {
        shape = "rectangle",
        entityID = entityID,
        length = length,
        width = width,
        heading = initialHeading,
        headingMode = headingMode,
        targetPos = targetPos,
        duration = duration,
        time = Now(),
        startTime = startTime,
        delay = delay,
        center = { 
            x = ent.pos.x, 
            y = ent.pos.y, 
            z = ent.pos.z 
        }
    })

    d("Entity-attached rectangle added to unsafe zones.")
end

function addCircleOnEntToUnsafeZones(duration, entityID, radius, delay)
    local delay = delay or 0
    local startTime = Now() + delay
    local ent = TensorCore.mGetEntity(entityID)
    
    if not ent then return end

    table.insert(unsafeZones, {
        shape = "circle",
        entityID = entityID,
        radius = radius,
        duration = duration,
        time = Now(),
        startTime = startTime,
        delay = delay,
        center = {x = ent.pos.x,y = ent.pos.y,z = ent.pos.z}
    })

    d("Entity-attached circle added to unsafe zones.")
end

function addDonutOnEntToUnsafeZones(duration, entityID, innerRadius, outerRadius, delay)
    local delay = delay or 0
    local startTime = Now() + delay
    local ent = TensorCore.mGetEntity(entityID)
    
    if not ent then return end

    table.insert(unsafeZones, {
        shape = "donut",
        entityID = entityID,
        innerRadius = innerRadius,
        outerRadius = outerRadius,
        duration = duration,
        time = Now(),
        startTime = startTime,
        delay = delay,
        center = {x = ent.pos.x,y = ent.pos.y,z = ent.pos.z}
    })

    d("Entity-attached donut added to unsafe zones.")
end

function isPositionInUnsafeZone(targetPos)
    local currentTime = Now() 
    for _, zone in ipairs(unsafeZones) do
        if currentTime >= zone.startTime then
            if zone.shape == "cone" then
                if isPositionInCone(zone.center, targetPos, zone.radius, zone.angle, zone.heading) then
                    return true, "cone"
                end
            elseif zone.shape == "rectangle" then
                if isPositionInRect(zone.center, targetPos, zone.length, zone.width, zone.heading) then
                    return true, "rectangle"
                end
            elseif zone.shape == "circle" then
                if isPositionInCircle(zone.center, targetPos, zone.radius) then
                    return true, "circle"
                end
            elseif zone.shape == "donut" then
                if isPositionInDonut(zone.center, targetPos, zone.innerRadius, zone.outerRadius) then
                    return true, "donut"
                end
            end
        end
    end

    return false
end

-- these 2 funcs needs to be ran on either update/draw loop to handle removal of safezones and updating pos on enetity attached zones
function removeExpiredUnsafeZones()
    local currentTime = Now()
    for i = #unsafeZones, 1, -1 do
        local zone = unsafeZones[i]
        if currentTime >= zone.startTime + zone.duration then
            table.remove(unsafeZones, i)
            d("Expired zone removed.")
        end
    end
end

-- update pos on entity attached zones 
function updateEntityAttachedZones()
    local currentTime = Now()
    for _, zone in ipairs(unsafeZones) do
        if zone.entityID and currentTime >= zone.startTime and currentTime < (zone.startTime + zone.duration) then
            local ent = TensorCore.mGetEntity(zone.entityID)
            if ent then
                zone.center.x = ent.pos.x
                zone.center.y = ent.pos.y
                zone.center.z = ent.pos.z
                if (zone.shape == "cone" or zone.shape == "rectangle") and zone.headingMode then -- update the heading only for cone and rectangles
                    if zone.headingMode == HEADING_MODE.ENTITY then
                        zone.heading = ent.pos.h
                    elseif zone.headingMode == HEADING_MODE.TARGET then
                        local targetPos = zone.targetPos
                        if type(zone.targetPos) == "number" then -- if targetPos is a number it means its an entity so we get the entityIDs heading
                            local targetEnt = TensorCore.mGetEntity(zone.targetPos)
                            if targetEnt then
                                targetPos = targetEnt.pos
                            end
                        end
                        if targetPos then -- otherwise if its a table we just use that targetPos
                            zone.heading = TensorCore.getHeadingToTarget(ent.pos, targetPos)
                        end
                    end
                end
            end
        end
    end
end

-- Example usage
--[[ Add different shapes to the unsafe zones
addConeToUnsafeZones(5000,100, 0, 100, 10, math.rad(45), math.rad(0))   -- Adding a cone
addRectToUnsafeZones(5000,100, 0, 100, 20, 10, math.rad(30))           -- Adding a rectangle
addCircleToUnsafeZones(5000, 100, 0, 100,5)                           -- Adding a circle
addDonutToUnsafeZones(5000,100, 0, 100, 5, 15,)                     -- Adding a donut

-- Check if a position is inside any unsafe zone
local targetPos = { x = 105, y = 0, z = 100 }  -- Example position to check
local isUnsafe, shapeType = isPositionInUnsafeZone(targetPos)
if isUnsafe then
    d("The position is inside an unsafe zone (" .. shapeType .. ").")
else
    d("The position is safe.")
end

]]











local g_innerPos1 = {x = 0, y = 0, z = 0}
local g_innerPos2 = {x = 0, y = 0, z = 0}
local g_outerPos1 = {x = 0, y = 0, z = 0}
local g_outerPos2 = {x = 0, y = 0, z = 0}
local g_checkPos = {x = 0, y = 0, z = 0}


local activeAnnuli = {}

local HEADING_MODE = {
    FIXED = 1,   -- fixed heading keeps the provided one throughout the duration
    ENTITY = 2,  -- uses the "source" entity's heading and keeps updating it
    TARGET = 3   -- aims toward a target (position or entity)
}

function DrawWorldAnnulus(centerPos, innerRadius, outerRadius, heading, angleWidth, fillColor, outlineColor, outlineThickness, segments, radialBands)
    segments = segments or 15               
    radialBands = radialBands or 5          
    outlineColor = outlineColor or fillColor 
    outlineThickness = outlineThickness or 2 
    

    local correctedHeading = -heading + (math.pi / 2)
    
    local halfAngle = angleWidth / 2
    local startAngle = correctedHeading - halfAngle
    local endAngle = correctedHeading + halfAngle
    
    if endAngle < startAngle then
        endAngle = endAngle + 2 * math.pi
    end
    
 
    local angleIncrement = (endAngle - startAngle) / segments
    local radiusIncrement = (outerRadius - innerRadius) / radialBands
    
    
    local centerScreenX, centerScreenY = RenderManager:WorldToScreen(centerPos, true)
    if not centerScreenX then
        local visible = false
        
        for i = 0, segments, segments / 4 do
            local angle = startAngle + i * angleIncrement
            
            for r = 0, radialBands do
                local radius = innerRadius + r * radiusIncrement
                g_checkPos.x = centerPos.x + radius * math.cos(angle)
                g_checkPos.y = centerPos.y
                g_checkPos.z = centerPos.z + radius * math.sin(angle)
                
                if RenderManager:WorldToScreen(g_checkPos, true) then
                    visible = true
                    break
                end
            end
            
            if visible then break end
        end
        
        if not visible then
            return 
        end
    end
    
  
    for band = 0, radialBands - 1 do
        local bandInnerRadius = innerRadius + band * radiusIncrement
        local bandOuterRadius = innerRadius + (band + 1) * radiusIncrement
        
        for seg = 0, segments - 1 do
            local angle1 = startAngle + seg * angleIncrement
            local angle2 = startAngle + (seg + 1) * angleIncrement
            
            g_innerPos1.x = centerPos.x + bandInnerRadius * math.cos(angle1)
            g_innerPos1.y = centerPos.y
            g_innerPos1.z = centerPos.z + bandInnerRadius * math.sin(angle1)
            
            g_innerPos2.x = centerPos.x + bandInnerRadius * math.cos(angle2)
            g_innerPos2.y = centerPos.y
            g_innerPos2.z = centerPos.z + bandInnerRadius * math.sin(angle2)
            
            g_outerPos1.x = centerPos.x + bandOuterRadius * math.cos(angle1)
            g_outerPos1.y = centerPos.y
            g_outerPos1.z = centerPos.z + bandOuterRadius * math.sin(angle1)
            
            g_outerPos2.x = centerPos.x + bandOuterRadius * math.cos(angle2)
            g_outerPos2.y = centerPos.y
            g_outerPos2.z = centerPos.z + bandOuterRadius * math.sin(angle2)
            
            -- Convert to screen coordinates
            local innerScreenX1, innerScreenY1 = RenderManager:WorldToScreen(g_innerPos1, true)
            local innerScreenX2, innerScreenY2 = RenderManager:WorldToScreen(g_innerPos2, true)
            local outerScreenX1, outerScreenY1 = RenderManager:WorldToScreen(g_outerPos1, true)
            local outerScreenX2, outerScreenY2 = RenderManager:WorldToScreen(g_outerPos2, true)
            
            
            if innerScreenX1 and innerScreenY1 and innerScreenX2 and innerScreenY2 and 
               outerScreenX1 and outerScreenY1 and outerScreenX2 and outerScreenY2 then
                
                GUI:AddTriangleFilled(innerScreenX1, innerScreenY1, outerScreenX1, outerScreenY1, outerScreenX2, outerScreenY2, fillColor)
                GUI:AddTriangleFilled(innerScreenX1, innerScreenY1, outerScreenX2, outerScreenY2, innerScreenX2, innerScreenY2, fillColor)
                
                if outlineColor ~= fillColor then
                    
                    if band == 0 then
                        GUI:AddLine(
                            innerScreenX1, innerScreenY1,
                            innerScreenX2, innerScreenY2,
                            outlineColor, outlineThickness
                        )
                    end
                    
                    if band == radialBands - 1 then
                        GUI:AddLine(
                            outerScreenX1, outerScreenY1,
                            outerScreenX2, outerScreenY2,
                            outlineColor, outlineThickness
                        )
                    end
                    
                    if seg == 0 then
                        GUI:AddLine(
                            innerScreenX1, innerScreenY1,
                            outerScreenX1, outerScreenY1,
                            outlineColor, outlineThickness
                        )
                    end
                    
                    if seg == segments - 1 then
                        GUI:AddLine(
                            innerScreenX2, innerScreenY2,
                            outerScreenX2, outerScreenY2,
                            outlineColor, outlineThickness
                        )
                    end
                end
            end
        end
    end
end



function addTimedAnnulus(duration, x, y, z, innerRadius, outerRadius, heading, angleWidth, fillColor, outlineColor, outlineThickness, segments, radialBands, delay)
    local delay = delay or 0
    local startTime = Now() + delay
    
    -- convert deg to rad if needed
    local angleWidthRad = angleWidth
    if angleWidth > 6.3 then  
        angleWidthRad = math.rad(angleWidth)
    end
    
    -- convert deg to rad if needed
    local headingRad = heading
    if heading > 6.3 then  
        headingRad = math.rad(heading)
    end
    
    table.insert(activeAnnuli, {
        center = { x = x, y = y, z = z },
        innerRadius = innerRadius,
        outerRadius = outerRadius,
        heading = headingRad,
        angleWidth = angleWidthRad,
        fillColor = fillColor,
        outlineColor = outlineColor,
        outlineThickness = outlineThickness,
        segments = segments,
        radialBands = radialBands,
        duration = duration,
        time = Now(),
        startTime = startTime,
        delay = delay,
    })

    --d("Annulus added to active draws.")
end


function addTimedAnnulusOnEnt(duration, entityID, innerRadius, outerRadius, heading, angleWidth, fillColor, outlineColor, outlineThickness, segments, radialBands, delay, headingMode, target)
    local delay = delay or 0
    local headingMode = headingMode or HEADING_MODE.FIXED
    local startTime = Now() + delay
    local ent = TensorCore.mGetEntity(entityID)
    
    if not ent then return end

    -- convert from deg to rad if needed
    local angleWidthRad = angleWidth
    if angleWidth > 6.3 then 
        angleWidthRad = math.rad(angleWidth)
    end
    
    -- convert from deg to rad if needed
    local headingRad = heading
    if heading > 6.3 then  
        headingRad = math.rad(heading)
    end

    local targetPos = target
    if headingMode == HEADING_MODE.TARGET and type(target) == "number" then
        local targetEnt = TensorCore.mGetEntity(target)
        if targetEnt then
            targetPos = targetEnt.pos
        end
    end

    local initialHeading = headingRad
    if headingMode == HEADING_MODE.ENTITY then
        initialHeading = ent.pos.h
    elseif headingMode == HEADING_MODE.TARGET and targetPos then
        initialHeading = TensorCore.getHeadingToTarget(ent.pos, targetPos)
    end

    table.insert(activeAnnuli, {
        entityID = entityID,
        innerRadius = innerRadius,
        outerRadius = outerRadius,
        heading = initialHeading,
        angleWidth = angleWidthRad,
        headingMode = headingMode,
        targetPos = targetPos,
        fillColor = fillColor,
        outlineColor = outlineColor,
        outlineThickness = outlineThickness,
        segments = segments,
        radialBands = radialBands,
        duration = duration,
        time = Now(),
        startTime = startTime,
        delay = delay,
        center = { 
            x = ent.pos.x, 
            y = ent.pos.y, 
            z = ent.pos.z 
        }
    })
    --d("Entity annulus added to active draws.")
end

function removeAnnulus(index)
    if activeAnnuli[index] then
        table.remove(activeAnnuli, index)
        d("Annulus ".. index .." removed.")
        return true
    end
    return false
end

-- clear all draws
function clearAllAnnuli()
    activeAnnuli = {}
    d("All annuli cleared.")
end

function removeExpiredAnnuli()
    local currentTime = Now()
    for i = #activeAnnuli, 1, -1 do
        local annulus = activeAnnuli[i]
        if currentTime >= annulus.startTime + annulus.duration then
            table.remove(activeAnnuli, i)
           -- d("Expired annulus removed.")
        end
    end
end


function updateEntityAttachedAnnuli()
    local currentTime = Now()
    for _, annulus in ipairs(activeAnnuli) do
        if annulus.entityID and currentTime >= annulus.startTime and currentTime < (annulus.startTime + annulus.duration) then
            local ent = TensorCore.mGetEntity(annulus.entityID)
            if ent then
                annulus.center.x = ent.pos.x
                annulus.center.y = ent.pos.y
                annulus.center.z = ent.pos.z
                
                if annulus.headingMode then
                    if annulus.headingMode == HEADING_MODE.ENTITY then
                        annulus.heading = ent.pos.h
                    elseif annulus.headingMode == HEADING_MODE.TARGET then
                        local targetPos = annulus.targetPos
                        if type(annulus.targetPos) == "number" then
                            local targetEnt = TensorCore.mGetEntity(annulus.targetPos)
                            if targetEnt then
                                targetPos = targetEnt.pos
                            end
                        end
                        if targetPos then
                            annulus.heading = TensorCore.getHeadingToTarget(ent.pos, targetPos)
                        end
                    end
                end
            end
        end
    end
end

function renderAllAnnuli()
    local currentTime = Now()
    for _, annulus in ipairs(activeAnnuli) do
        if currentTime >= annulus.startTime and currentTime < (annulus.startTime + annulus.duration) then

 
            DrawWorldAnnulus(
                annulus.center,
                annulus.innerRadius,
                annulus.outerRadius,
                annulus.heading,
                annulus.angleWidth,
                annulus.fillColor,
                annulus.outlineColor,
                annulus.outlineThickness,
                annulus.segments,
                annulus.radialBands
            )
        end
    end
end

function RenderAnnulusOverlay()
    local maxWidth, maxHeight = GUI:GetScreenSize()
    local flags = (GUI.WindowFlags_NoInputs + GUI.WindowFlags_NoBringToFrontOnFocus + 
                  GUI.WindowFlags_NoTitleBar + GUI.WindowFlags_NoResize + 
                  GUI.WindowFlags_NoScrollbar + GUI.WindowFlags_NoCollapse)
    
    GUI:SetNextWindowPos(0, 0, GUI.SetCond_Always)
    GUI:SetNextWindowSize(maxWidth, maxHeight, GUI.SetCond_Always)
    GUI:PushStyleColor(GUI.Col_WindowBg, 0, 0, 0, 0)
    
    local visible, open = GUI:Begin("DedoAnnulus", true, flags)
    updateEntityAttachedAnnuli()
    removeExpiredAnnuli()
    renderAllAnnuli()
    
    GUI:End()
    GUI:PopStyleColor(1)
end

function isPositionInSector(centerPos, targetPos, sectorNumbers, targetSector, headingOffset,maxRadius, debug)
    maxRadius = maxRadius or 20
    headingOffset = headingOffset or 0
    sectorNumbers = sectorNumbers or 4

    local distance = TensorCore.getDistance2d(centerPos, targetPos)
    if distance > maxRadius then
        d("Error, pos outside of maxRadius: "..maxRadius)
        return 0,false -- Position is outside the maximum radius
    end

    local headingToTarget = TensorCore.getHeadingToTarget(centerPos, targetPos)
    
    -- readjust heading so that 0 is north instead of south by subtracting pi then convert to 0-2pi instead of -pi/pi for clockwise rotation
    local adjustedHeading = (headingToTarget - math.pi + headingOffset) % (math.pi * 2)
    -- set sector size aka full circle / sectornumbers
    local sectorSize = (math.pi * 2) / sectorNumbers
    -- debug draw, if true it will draw the sectors with a green sector to indicate where the first one is
    if debug then
        for i = 1,sectorNumbers do
            local color = 26879
            if i == 1 then
                color = 318832405
            end
            local angle = ((math.pi*2/sectorNumbers*i)-headingOffset-(sectorSize/2))+math.pi
            TensorCore.getStaticDrawer(color):addCone(centerPos.x,centerPos.y,centerPos.z,maxRadius,sectorSize,angle)
        end
    end
    -- calculate which sector we're in
    local sector = math.floor(adjustedHeading / sectorSize) + 1
    local sectorBool = sector == targetSector
    return sector, sectorBool
end