local mapToCheck = 968

PartyPlan = {}

PartyPlan.GUI = {
open = false,
visible = false,
pos = 0,
selected = 1,
}

local modPath = GetLuaModsPath() .. [[FightPlan\]]
local savePath = modPath .. [[partySavedFiles]]
PartyPlan.replayMode = false

local function savePositionsToFile(fileName,saveTable)
    if (not FolderExists(savePath)) then
        FolderCreate(savePath)
    end
    local saveFile = savePath.."\\" .. fileName ..".lua"
    d(saveFile)
    FileSave(saveFile,saveTable)
end

local function loadFileList()
    return FolderList(savePath,[[(.*)lua$]])
end

local function loadPositionsFromFile(fileName)
    if (not FolderExists(savePath)) then
        FolderCreate(savePath)
    end
    local fileList = FolderList(savePath,[[(.*)lua$]])
    if fileList then
        for k,v in pairs(fileList) do
            if v == fileName then
                return FileLoad(savePath.."\\"..fileName)
            end
        end
    end
end

local idtoJob = {

    [21] = "WAR",
    [19] =  "PLD",
    [30] =  "NIN",
    [28] =  "SCH",
    [34] =  "SAM",
    [5] =  "ARC",
    [32] =  "DRK",
    [20] =  "MNK",
    [11] =  "GSM",
    [12] =  "LTW",
    [1] =  "GLD",
    [4] =  "LNC",
    [13] =  "WVR",
    [31] =  "MCH",
    [6] =  "CNJ",
    [40] =  "SGE",
    [9] =  "BSM",
    [23] =  "BRD",
    [14] =  "ALC",
    [26] =  "ACN",
    [18] =  "FSH",
    [15] =  "CUL",
    [25] =  "BLM",
    [17] =  "BTN",
    [39] =  "RPR",
    [38] =  "DNC",
    [37] =  "GNB",
    [36] =  "BLU",
    [22] =  "DRG",
    [33] =  "AST",
    [8] =  "CRP",
    [10] =  "ARM",
    [3] =  "MRD",
    [16] =  "MIN",
    [29] =  "ROG",
    [2] =  "PGL",
    [0] =  "ADV",
    [27] =  "SMN",
    [7] =  "THM",
    [35] =  "RDM",
    [24] =  "WHM",
    [41] = "VPR",
    [42] = "PCT",

}


function PartyPlan.generatePartyPositions()
    local pl = TensorCore.entityList("myparty")
    if PartyPlan.replayMode == true then
        pl = TensorCore.entityList("chartype=4")
    end
    local partyList = {}
    if table.size(pl) < 1 then -- generate fake party if we're not in a party for debugging purpose
        pl[123456789] = {name = "Sakura Haruno",pos = {x = math.random(80,120)},job = math.random(20,40),}
        pl[223456789] = {name = "Sasuke Uchiha",pos = {x = math.random(80,120)},job = math.random(20,40),}
        pl[323456789] = {name = "Naruto Uzumaki",pos = {x = math.random(80,120)},job = math.random(20,40),}
        pl[423456789] = {name = "Orochimaru King",pos = {x = math.random(80,120)},job = math.random(20,40),}
        pl[523456789] = {name = "Kakashi Hatake",pos = {x = math.random(80,120)},job = math.random(20,40),}
        pl[623456789] = {name = "Rock Lee",pos = {x = math.random(80,120)},job = math.random(20,40),}
        pl[723456789] = {name = "Neji Hyuga",pos = {x = math.random(80,120)},job = math.random(20,40),}
    end
    pl[TensorCore.mGetPlayer().id] = TensorCore.mGetEntity(TensorCore.mGetPlayer().id) -- insert player into pl
    for k,v in pairs(pl) do
        table.insert(partyList,{name = v.name,x = v.pos.x,id = k,job = idtoJob[v.job] or "UNKWN"})
        if table.size(partyList) > 10 then break end
    end
    table.sort(partyList,function(a,b) return a.x < b.x  end)
    return partyList
end
PartyPlan.progressTimer = Now()
PartyPlan.progressTimerLimit = 1
PartyPlan.progressTimerString = ""
local progressTimerLocked = true
local gui = PartyPlan.GUI
local firstRun = false
local mapCheckTick = Now()
local windowWidth
local currentFileList = loadFileList()
local currentSelectedFile = 1
local newSaveFile = "Profile name"
local lastSave
local autocompleteTable = {}
local showAutocomplete = false
local partnerName = ""
local gSuggestions
local gSuggestionsIndex = 1
local hoveredColor = 0
PartyPlan.partnerName = partnerName
PartyPlan.partnerID = 0

local isMenuOpen = false
local currentMenuTab = 1
local popupWidth = 0
local animatedWidth = 0
local animatedHeight = 0
local maxWidth = 250
local maxHeight = 350
local windowX,windowY
local blankJob = "-"


function PartyPlan.draw(event,ticks)
    if TimeSince(mapCheckTick) > 2000 and firstRun == false and PartyPlan.partyList == nil  and TensorCore.mGetPlayer().localmapid == mapToCheck then
        gui.open = true gui.visible = true
        firstRun = true
        mapCheckTick = Now()
    end
   --[[ if TimeSince(PartyPlan.progressTimer) < PartyPlan.progressTimerLimit then
        GUI:SetNextWindowSize(0, 0,GUI.SetCond_Always)
        local WinFlags
        if progressTimerLocked then
            WinFlags = (GUI.WindowFlags_NoTitleBar + GUI.WindowFlags_AlwaysAutoResize + GUI.WindowFlags_NoScrollbar + GUI.WindowFlags_NoCollapse + GUI.WindowFlags_NoMove);
        else
            WinFlags = (GUI.WindowFlags_NoTitleBar + GUI.WindowFlags_AlwaysAutoResize + GUI.WindowFlags_NoScrollbar + GUI.WindowFlags_NoCollapse);
        end
        GUI:Begin("##PartyPlanProgressbar", true, WinFlags)


        GUI:ProgressBar( 1-TimeSince(PartyPlan.progressTimer)/PartyPlan.progressTimerLimit, 200, 30, "")
        if GUI:IsItemClicked(1) then
            progressTimerLocked = not progressTimerLocked
        end
        GUI:CalcTextSize(PartyPlan.progressTimerString)
        GUI:SetCursorPos((210-GUI:CalcTextSize(PartyPlan.progressTimerString))*0.5 , 15 )
        GUI:SetWindowFontSize(1.2)
        GUI:Text(PartyPlan.progressTimerString)



        GUI:End()
    else
        PartyPlan.progressTimerString = ""
    end --]]


    PartyPlan.DrawTimers()
    if gui.visible == false or gui.open == false then

       -- animatedWidth = 0
        animatedHeight = 0

    end
    if gui.open then

        local targetWidth, targetHeight = maxWidth, maxHeight -- Default target size
        if currentMenuTab == 1 then
            targetWidth, targetHeight = 280, 350 -- Size for tab 1
        elseif currentMenuTab == 2 then
            targetWidth, targetHeight = 150, 200 -- Size for tab 2
        end


        animatedWidth = animatedWidth + math.floor((targetWidth - animatedWidth) * 0.1)
        animatedHeight = animatedHeight + math.floor((targetHeight - animatedHeight) * 0.1)
        local g = FightPlan.gui
        g.pushTheme()
        GUI:SetNextWindowSize(animatedWidth,animatedHeight,GUI.SetCond_Always + GUI.WindowFlags_NoScrollbar)
        gui.visible,gui.open = GUI:Begin("PartyPlan",gui.open,GUI.WindowFlags_NoResize + GUI.WindowFlags_NoScrollbar)
	if GUI:IsItemHovered() then if GUI:IsItemClicked(1) then GUI:SetWindowCollapsed(gui.visible) end end
        if gui.visible then
            --local x,y = GUI:GetWindowPos()
            --  drawMenuBar(x,y)
            local menustr
            if isMenuOpen then menustr = [[\/]] else menustr = ">" end
            if GUI:Button(menustr, 20, 20) then
                isMenuOpen = not isMenuOpen -- Toggle the menu
                popupWidth = 0
            end

            -- If the menu is open, draw the menu items
            if isMenuOpen then
                GUI:OpenPopup("FileMenu") -- Open the popup menu
                popupWidth = math.min(popupWidth + 3, 50) -- Adjust the increment and max width as needed
                GUI:SetNextWindowSize(popupWidth, 0)
            end

            -- If the popup menu is open, draw its contents
            if GUI:BeginPopup("FileMenu",GUI.WindowFlags_NoScrollbar) then
                -- Add menu items as buttons
                if GUI:Button("Tab1") then
                    if currentMenuTab ~= 1 then
                        currentMenuTab = 1
                        animatedWidth = animatedWidth or 0
                        animatedHeight = animatedHeight or 0
                        maxWidth = 250
                        maxHeight = 350
                    end
                    GUI:CloseCurrentPopup( )
                end
                if GUI:Button("Tab2") then
                    if currentMenuTab ~= 2 then
                        currentMenuTab = 2
                        animatedWidth = animatedWidth or 0
                        animatedHeight = animatedHeight or 0
                        maxWidth = 150
                        maxHeight = 200
                    end
                    GUI:CloseCurrentPopup( )
                end
                if GUI:IsWindowHovered() and GUI:IsMouseClicked(0) then
                    isMenuOpen = false
                    GUI:CloseCurrentPopup( )
                end
                GUI:EndPopup() -- Close the popup menu
            end
            if not GUI:IsWindowHovered() and GUI:IsMouseClicked(0) then
                isMenuOpen = false
                GUI:CloseCurrentPopup( )
            end
            if currentMenuTab == 1 then

                GUI:Button("Generate Party")

                if GUI:IsItemHovered() then
                    GUI:SetTooltip("Click to generate a party list, it will be sorted from left to right to determine priority.")
                end
                if GUI:IsItemClicked() then
                    PartyPlan.partyList = PartyPlan.generatePartyPositions()
                    autocompleteTable = {}
                    for i = 1,#PartyPlan.partyList do
                        table.insert(autocompleteTable,PartyPlan.partyList[i].name)
                    end
                    function getAutocompleteSuggestions(inputText)
                        local suggestions = {}

                        for _, word in ipairs(autocompleteTable) do
                            -- Change the matching condition to case-insensitive
                            if string.match(string.lower(word), "^" .. string.lower(inputText)) then
                                table.insert(suggestions, word)
                            end
                        end

                        return suggestions
                    end
                end
                GUI:SameLine()
                PartyPlan.replayMode = GUI:Checkbox("Replay Mode",PartyPlan.replayMode)
                if GUI:IsItemHovered() then
                    GUI:SetTooltip("Check this if you're testing in duty recorder to properly generate the party.")
                end
                if PartyPlan.partyList then




                    GUI:PushItemWidth(GUI:GetWindowWidth()-25)
                    GUI:ListBoxHeader("##PartyPlan_PartyList", 200, 175)

                    for i = 1,#PartyPlan.partyList do
                        local currentselection = function() if i == gui.selected then return true end return false end
                            GUI:Selectable("# "..i.." "..PartyPlan.partyList[i].job.." - "..PartyPlan.partyList[i].name,currentselection())
                        if GUI:IsItemClicked(1) then
                            PartyPlan.partnerID = PartyPlan.partyList[i].id
                            PartyPlan.partnerName = PartyPlan.partyList[i].name
                            partnerName = PartyPlan.partyList[i].name

                        end
                        if GUI:IsItemHovered(GUI.HoveredFlags_AllowWhenBlockedByPopup + GUI.HoveredFlags_AllowWhenBlockedByActiveItem + GUI.HoveredFlags_AllowWhenOverlapped) then

                            if GUI:IsMouseDown(0) then
                                if gui.pos == 0 then
                                    if gui.pos ~= i then gui.pos = i end
                                    if gui.selected ~= i then gui.selected = i end
                                elseif gui.pos ~= i then
                                    local move = PartyPlan.partyList[gui.pos]
                                    PartyPlan.partyList[gui.pos] = PartyPlan.partyList[i]
                                    PartyPlan.partyList[i] = move
                                    gui.pos = i
                                    if gui.selected ~= i then gui.selected = i end
                                end
                            end
                        end
                        if gui.pos ~= 0 and (GUI:IsMouseReleased(0) or not GUI:IsMouseDown(0)) then
                            gui.pos = 0
                        end
                    end
                    GUI:ListBoxFooter()
                    if gui.pos ~= 0 and not GUI:IsItemHovered(GUI.HoveredFlags_AllowWhenBlockedByPopup + GUI.HoveredFlags_AllowWhenBlockedByActiveItem + GUI.HoveredFlags_AllowWhenOverlapped) then gui.pos = 0 end
                    GUI:NewLine()
                end
                GUI:PushItemWidth(150)
                if table.valid(autocompleteTable) then
                    GUI:Text("Partner: ")
                    local changed
                    partnerName,changed = GUI:InputText("##InputText",partnerName)
                    --local suggestions = getAutocompleteSuggestions(partnerName)
                    if changed then
                        PartyPlan.partnerName = partnerName
                        gSuggestions = getAutocompleteSuggestions(partnerName)
                        d(gSuggestions)
                        showAutocomplete = true
                        d(autocompleteTable)
                    end
                    if table.valid(gSuggestions) and #gSuggestions > 0 and showAutocomplete then
                        if GUI:IsMouseDown(1) then
                            showAutocomplete = false
                        end
                        --GUI:BeginTooltip( )
                        local changed2

                        GUI:Dummy(0,25) GUI:SameLine();gSuggestionsIndex,changed2 = GUI:ListBox("##listBoxTest",gSuggestionsIndex,gSuggestions,#gSuggestions+1)
                        if changed2 then
                            partnerName = gSuggestions[gSuggestionsIndex]
                            PartyPlan.partnerName = partnerName
                            showAutocomplete = false
                        end
                        if not GUI:IsItemHovered() then
                            if GUI:IsMouseReleased(0) then
                                showAutocomplete = false
                            end
                        end
                        --for _,sug in ipairs(gSuggestions) do

                        -- GUI:ListBox("##listBoxTest",#gSuggestions)


                        -- end

                        -- GUI:EndTooltip( )

                    end
                else
                    partnerName,changed = GUI:InputText("##InputText",partnerName)
                    PartyPlan.partnerName = partnerName
                end




                if GUI:CollapsingHeader("Profiles") then
                    if table.valid(currentFileList) then
                        local changed
                        GUI:Text("Select profile:")GUI:SameLine() currentSelectedFile,changed = GUI:Combo("##Select Profile", currentSelectedFile,currentFileList,10)
                        if GUI:IsItemHovered() then
                            GUI:SetTooltip("Select a pre-saved profile to load.")
                        end
                        if changed then
                            local fileList = loadFileList()
                            PartyPlan.partyList = loadPositionsFromFile(fileList[currentSelectedFile])
                            local party = TensorCore.entityList("myparty")
                            party[Player.id] = Player
                            for id,ent in pairs(party) do
                                for i = 1,#PartyPlan.partyList do
                                    if ent.name == PartyPlan.partyList[i].name then

                                        if PartyPlan.partyList[i].id ~= ent.id then
                                            d("ID mismatch on "..ent.name.." old ID: ["..PartyPlan.partyList[i].id.."] new ID: ["..ent.id.."]")
                                            PartyPlan.partyList[i].id = ent.id
                                            d("Updated ID.")
                                            savePositionsToFile(string.sub(fileList[currentSelectedFile],1,-5),PartyPlan.partyList)
                                        end
                                    end
                                end
                            end
                        end

                    end
                    if table.valid(PartyPlan.partyList) then
                        local changed
                        GUI:Text("Save Profile:")GUI:SameLine() newSaveFile,changed = GUI:InputText("##New File", newSaveFile, GUI.InputTextFlags_EnterReturnsTrue)
                        if GUI:IsItemHovered() then
                            GUI:SetTooltip("Input prefered profile name, and enter to save it to file.")
                        end
                        if changed then
                            savePositionsToFile(newSaveFile,PartyPlan.partyList)
                            currentFileList = loadFileList()
                            lastSave = Now()
                        end
                        if lastSave ~= nil and TimeSince(lastSave) < 3000 then
                            GUI:Text("Saved "..newSaveFile.." as a new profile")
                        end
                    end

                end

            elseif currentMenuTab == 2 then
                GUI:Text("Different tab")
            end

        end

        GUI:End()
        FightPlan.gui.popTheme()
    else

    end
end




function PartyPlan.getClosestPlayersToEnt(entid,number) -- provide entityID to the target you want to check from, and number of party members to check, returns a table of entityIDs in order.
    local enemy
    if type(entid) ~= "table" then

        enemy = TensorCore.mGetEntity(entid)
    else
        enemy = {}
        enemy.pos = entid
    end

    local distances = {}
    local party = TensorCore.entityList("chartype=4,alive")
    if TensorCore.mGetPlayer().alive then
        party[TensorCore.mGetPlayer().id] = TensorCore.mGetPlayer()
    end
    for id, ent in pairs(party) do
        local distance = TensorCore.getDistance2d(ent.pos,enemy.pos)
        table.insert(distances, {distance = distance, id = id})
    end

    table.sort(distances, function(a, b) return a.distance < b.distance end)

    local closestPlayers = {}
    for i = 1, math.min(number, #distances) do
        table.insert(closestPlayers, distances[i].id)
    end

    return closestPlayers
end


-- provide 2 entityIDs to equalize the HP of, if minhp or diffAllowed is not provided it will default to 2 and 2 respectively
-- minhp is what hp the script will stop retargeting at, diffAllowed is how much the difference between the 2 targets is allowed before swapping.
function PartyPlan.equalizeHP(t1,t2,minhp,diffAllowed)
    local target1 = TensorCore.mGetEntity(t1)
    local target2 = TensorCore.mGetEntity(t2)
    --local cTarget = TensorCore.mGetTarget()
    local minHP = minhp or 2 -- script will stop running when targets drop below this hp%
    local hpDiffAllowed = diffAllowed or 2 -- the allowed hp difference before it swaps
    local difference = target1.hp.percent - target2.hp.percent

    if target2.hp.percent > minHP and target1.hp.percent > minHP then
        if math.abs(difference) > hpDiffAllowed then
            if difference > 0 then
                if target1.distance < AnyoneCore.maxRanges[Player.job]+Player.hitradius+Player:GetTarget().hitradius then
                    TensorCore.mGetPlayer():SetTarget(target1.id)

                end
            else
                if target2.distance < AnyoneCore.maxRanges[Player.job]+Player.hitradius+Player:GetTarget().hitradius then
                    TensorCore.mGetPlayer():SetTarget(target2.id)
                end
            end
        end
    end

end

--[[
function PartyPlan.SetTimer(num,string) -- set the timer for the progress bar to count down from in seconds
    PartyPlan.progressTimerString = string or ""
    PartyPlan.progressTimerLimit = num*1000
    PartyPlan.progressTimer = Now()
end --]]
function PartyPlan.resetTimers(num)
    if num ~= nil and type(num) == "number" then
        table.remove(PartyPlan.timers,num)
    end
    if num ~= nil and type(num) == "string" then
        for k,v in ipairs(PartyPlan.timers) do
            if v.string == num then
                table.remove(PartyPlan.timers,k)
            end
        end
    end
    if num == nil then
        PartyPlan.timers = {}
    end
end



function PartyPlan.SetTimer(num, string)
    local timerData = {
        timer = Now(),
        limit = num * 1000,
        string = string or "",
    }
    table.insert(PartyPlan.timers, timerData)  -- Add the new timer to the list
    return string
end

PartyPlan.setTimer = PartyPlan.SetTimer


PartyPlan.timers = {}  -- Table to hold multiple timers
PartyPlan.parentWindowName = "##PartyPlanTimerBarsParent"  -- Name of the parent window
local progressTimerBarFlag
PartyPlan.timerHeight = 45  -- Height of each timer
PartyPlan.timerSpacing = 10  -- Spacing between timers
function PartyPlan.DrawTimers()
    if table.valid(PartyPlan.timers) then
        local g = FightPlan.gui
        g.pushTheme()
        GUI:SetNextWindowSize(0,0, GUI.SetCond_Always)
        GUI:PushStyleColor(GUI.Col_WindowBg, 1, 1, 1, 0)
        GUI:PushStyleColor(GUI.Col_Border, 1, 1, 1, 0)
        GUI:PushStyleColor(GUI.Col_BorderShadow, 1, 1, 1, 0)

      --  GUI:PushStyleVar(GUI.StyleVar_Alpha, 0)

        if progressTimerLocked then progressTimerBarFlag = GUI.WindowFlags_NoTitleBar + GUI.WindowFlags_NoResize + GUI.WindowFlags_NoMove + GUI.WindowFlags_NoCollapse else progressTimerBarFlag = GUI.WindowFlags_NoTitleBar + GUI.WindowFlags_NoResize + GUI.WindowFlags_NoCollapse end
        local guiopen = GUI:Begin(PartyPlan.parentWindowName, table.valid(PartyPlan.timers), progressTimerBarFlag)
       GUI:PopStyleColor(3)
      --  GUI:PopStyleVar(1)
        for i, timerData in ipairs(PartyPlan.timers) do
            local progressTimer = timerData.timer
            local progressTimerLimit = timerData.limit
            local progressTimerString = timerData.string

            if TimeSince(progressTimer) < progressTimerLimit then
                GUI:BeginChild("##PartyPlanProgressbar"..tostring(i), 200, PartyPlan.timerHeight, false,GUI.WindowFlags_NoScrollbar + GUI.WindowFlags_NoScrollWithMouse)
                GUI:ProgressBar(1 - TimeSince(progressTimer) / progressTimerLimit, 200, 30, "")
                if GUI:IsItemClicked(1) then
                    progressTimerLocked = not progressTimerLocked
                end
                GUI:CalcTextSize(progressTimerString)
                GUI:SetCursorPos((200 - GUI:CalcTextSize(progressTimerString)) * 0.5, 5)
                GUI:SetWindowFontSize(1.2)
                GUI:Text(progressTimerString)
                --FonterText(progressTimerString)
                GUI:EndChild()
                GUI:Spacing()  -- Add spacing between timer windows
            else
                table.remove(PartyPlan.timers, i)  -- Remove the timer when it's done
            end
        end
        GUI:End()
        g.popTheme()
    end

end


function PartyPlan.getFurthestInCardinal(cardinal,entitylistString,role) -- provide a string cardinal n,s,w,e, and optional entitylistString like contentid=1234, defaults to myparty
    local roleTable = {
        ["healer"] = {6,24,28,33,40},
        ["dps"] = {2,4,5,7,20,22,23,25,26,27,29,30,31,34,35,38,39},
        ["tank"] = {1,3,19,21,32,37}
    }

    if cardinal == nil then return d("Please give a cardinal direction to check either n,s,w,e.") end
    if entitylistString == nil then entitylistString = "myparty"  end

    local sortedTable = {}
    local pl = TensorCore.entityList(tostring(entitylistString))
    for id,ent in pairs(pl) do
        if role ~= nil then
            if table.contains(roleTable[role],ent.job) then
                table.insert(sortedTable,{id = id,z = ent.pos.z,x = ent.pos.x})
            end
        else
            table.insert(sortedTable,{id = id,z = ent.pos.z,x = ent.pos.x})

        end
    end
    if table.valid(sortedTable) then
        if cardinal == "n" then
            table.sort(sortedTable,function(a,b) return a.z < b.z  end)
        end
        if cardinal == "s" then
            table.sort(sortedTable,function(a,b) return a.z > b.z  end)
        end
        if cardinal == "w" then
            table.sort(sortedTable,function(a,b) return a.x < b.x  end)
        end
        if cardinal == "e" then
            table.sort(sortedTable,function(a,b) return a.x > b.x  end)
        end
        return sortedTable[1].id
    else
        d("tried to iterate myparty without being in a party, returning playerID")
        return TensorCore.mGetPlayer().id
    end
end

function dd(string)
    d(string)
    TensorCore.timelineLogToFile(string.." \n")
end



function PartyPlan.IsPosInPolyAndDraw(x, y, drawer, ...)
    local vertices = {...}
    local points = {}

    for i = 1, #vertices - 1, 2 do
        points[#points + 1] = {x = vertices[i], y = vertices[i + 1]}
    end

    local i, j = #points, #points
    local inside = false

    for i = 1, #points do
        if ((points[i].y < y and points[j].y >= y) or (points[j].y < y and points[i].y >= y)) and (points[i].x <= x or points[j].x <= x) then
            if (points[i].x + (y - points[i].y) / (points[j].y - points[i].y) * (points[j].x - points[i].x) < x) then
                inside = not inside
            end
        end

        if drawer ~= nil then
             drawer:addLine(points[i].x, Player.pos.y, points[i].y,points[j].x,Player.pos.y, points[j].y,0,true)
        end
        j = i
    end

    return inside
end

local function GenerateRectangleInFrontOfPlayer(Player, distance, width, height)
    local playerPos = Player.pos
    local playerHeading = Player.pos.h
    if Player:GetTarget() ~= nil then
        playerHeading = TensorCore.getHeadingToTarget(Player.pos,Player:GetTarget().pos)
    end
    -- Calculate the position of the center of the rectangle in front of the player
    local offsetX = distance * math.sin(playerHeading)
    local offsetZ = distance * math.cos(playerHeading)
    local centerPos = { x = playerPos.x + offsetX, z = playerPos.z + offsetZ }

    -- Calculate the direction vector perpendicular to the player's heading
    local perpendicularHeading = playerHeading + math.pi / 2

    -- Calculate the positions of the four corners of the rectangle
    local halfWidth = width / 2
    local halfHeight = height / 2
    local topLeftX = centerPos.x - halfWidth * math.sin(perpendicularHeading)
    local topLeftZ = centerPos.z - halfWidth * math.cos(perpendicularHeading)
    local topRightX = centerPos.x + halfWidth * math.sin(perpendicularHeading)
    local topRightZ = centerPos.z + halfWidth * math.cos(perpendicularHeading)
    local bottomLeftX = topLeftX + height * math.sin(playerHeading)
    local bottomLeftZ = topLeftZ + height * math.cos(playerHeading)
    local bottomRightX = topRightX + height * math.sin(playerHeading)
    local bottomRightZ = topRightZ + height * math.cos(playerHeading)

    -- Form the vertices to represent the rectangle
    local vertices = {
        topLeftX, topLeftZ,
        topRightX, topRightZ,
        bottomRightX, bottomRightZ,
        bottomLeftX, bottomLeftZ,
        topLeftX, topLeftZ -- Closing vertex
    }
    local drawer = TensorCore.getStaticDrawer(1879113472)
    drawer:addLine(topLeftX,Player.pos.y, topLeftZ, topRightX,Player.pos.y, topRightZ)
    drawer:addLine(topRightX,Player.pos.y, topRightZ, bottomRightX,Player.pos.y, bottomRightZ)
    drawer:addLine(bottomRightX, Player.pos.y, bottomRightZ, bottomLeftX,Player.pos.y, bottomLeftZ)
    drawer:addLine(bottomLeftX,Player.pos.y, bottomLeftZ, topLeftX, Player.pos.y,topLeftZ)
    return vertices
end

function PartyPlan.rangedLBCheck(number,distance,width,height)
    local vertices = GenerateRectangleInFrontOfPlayer(Player,distance or 0,width or 5,height or 30)
    local count = 0
    for id,ent in pairs(TensorCore.entityList("attackable")) do
        local inside = PartyPlan.IsPosInPolyAndDraw(ent.pos.x,ent.pos.z,nil,unpack(vertices))
        if inside then
            count = count+1
        end
    end
    return count >= number

end


local function calculateDistance(coord1, coord2)
    return math.sqrt((coord1.x - coord2.x)^2 + (coord1.y - coord2.y)^2 + (coord1.z - coord2.z)^2)
end

--[[ returns position table of best x,y,z coords to place aoe
-- targets is a table with positions that you can get from either iterating an entitylist example:
local targets = {}
for id,ent in pairs(TensorCore.entityList("contentid=541,maxdistance=30")) do table.insert(targets,ent.pos)  end

radius is the radius of your AoE spell that you want to aim

scanCenter(optional) is a position table of where you want to scan for targets, it defaults to Player.pos

scanRadius(optional) is how far you want to scan from scanCenter, this is usually the range of your spell, default 25.pos

noVariance(optional) default it will have some random variance of where to hit, set this to true to have no variance



DSR example for LB2 with draws with draws using flag position on map as the scan position (go into o12s to test)
Put it in a onFrame reaction
---------------

local drawer = TensorCore.getMoogleDrawer()
local redStaticDrawer = TensorCore.getStaticDrawer(GUI:ColorConvertFloat4ToU32(1, 0, 0, 0.3), 2)
local targets = {
    {x = 100.000, y = 0.000, z = 86.000},
    {x = 90.101, y = 0.000, z = 90.101},
    {x = 109.899, y = 0.000, z = 90.100},
    {x = 86.000, y = 0.000, z = 100.000},
    {x = 90.101, y = 0.000, z = 109.899},
    {x = 100.000, y = 0.000, z = 114.000},
    {x = 109.899, y = 0.000, z = 109.899},
    {x = 114.000, y = 0.000, z = 100.000}
}
for k, v in pairs(targets) do
    redStaticDrawer:addCircle(v.x, Player.pos.y, v.z, 1, nil)
end

local flagPos = GetMapFlagPosition()
if flagPos then
    flagPos.y = Player.pos.y
    local scanCenter = flagPos
    local scanRadius = 10
    local radius = 10
    local coords = PartyPlan.findBestCoordinate(targets, radius,scanCenter,scanRadius)
    local redStaticDrawer = TensorCore.getStaticDrawer(GUI:ColorConvertFloat4ToU32(1, 0, 0, 0.1), 2)
    drawer:addCircle(math.random(-10, 10) / 100 + coords.x, Player.pos.y, math.random(-10, 10) / 100 + coords.z, radius) -- math random for some more randomized positions
end
self.used = true
local targets = {};for id,ent in pairs(TensorCore.entityList("contentid=541,maxdistance=30")) do table.insert(targets,ent.pos)  end ActionList:Get(1,188):Cast(PartyPlan.findBestCoordinate(targets,25).x,PartyPlan.findBestCoordinate(targets,25).y,PartyPlan.findBestCoordinate(targets,25).z)

]]--
function PartyPlan.findBestCoordinate(targets, radius, scanCenter, scanRadius, noVariance)
    scanCenter = scanCenter or {x = Player.pos.x, y = Player.pos.y, z = Player.pos.z}
    scanRadius = scanRadius or 25
    local variance = 0
    if noVariance == nil then
        variance = math.random(-10,10)/100
    end

    local bestCoordinate = {x = 0, y = 0, z = 0}
    local maxTargetsHit = 0
    for _, target1 in pairs(targets) do
        for _, target2 in pairs(targets) do
            local midpoint = {
                x = (target1.x + target2.x) / 2,
                y = (target1.y + target2.y) / 2,
                z = (target1.z + target2.z) / 2
            }
            local distanceToCenter = calculateDistance(midpoint, scanCenter)
            if distanceToCenter <= scanRadius then
                local targetsHit = 0

                for _, targetPos in pairs(targets) do
                    -- Incorporate hit radius of the target into distance calculation
                    local distanceToTarget = calculateDistance(midpoint, targetPos) - targetPos.hitradius
                    if distanceToTarget <= radius then
                        targetsHit = targetsHit + 1
                    end
                end

                if targetsHit > maxTargetsHit then
                    maxTargetsHit = targetsHit
                    bestCoordinate = midpoint
                end
            end
        end
    end
    if noVariance == nil then
        bestCoordinate.x = variance+bestCoordinate.x
        bestCoordinate.z = variance+bestCoordinate.z
    end
    return bestCoordinate
end

function PartyPlan.playSound(sound)
    local soundPath = modPath..[[sounds\]]
    if FileExists(soundPath..sound) then
        local p = io.popen(soundPath.."soundengine.exe "..soundPath..sound)
        p:close()
    end
end
function PartyPlan.startRecording(commandLocation,ip,savePath,debug)
    local date = os.date("*t");
    local identifier = os.time()
    local currdate = string.format("%d-%02d-%02d", date.year, date.month, date.day)
    local foldername = string.gsub(savePath.."\\"..GetMapName(Player.localmapid).."\\"..currdate, "%s", "-");

    if not FolderExists(foldername) then
        FolderCreate(foldername)
    end
    local filename = string.gsub(idtoJob[Player.job].."-"..identifier, "%s", "-");
    dd("New recording started: "..foldername.."\\"..filename)
    local p = io.popen(commandLocation.. " /server="..ip.." /command=SetRecordDirectory,recordDirectory="..foldername.." /command=SetProfileParameter,parameterCategory=Output,parameterName=FilenameFormatting,parameterValue="..filename.." /startrecording",r)
    if debug == true then local output = p:read('*all')
        p:close()
        dd(output)
    end
end
function PartyPlan.stopRecording(commandLocation,ip,savePath)
    io.popen(commandLocation.. " /server="..ip.." /stoprecording",r)
end

-- returns the heading of most targets hit with a cone, takes source pos (usually player), table of target positions tbl = {{x = 100,y=0,z=100},{x = 102,y=0,z=103}} etc
-- specify cone angle(width) in radians and radius(length) example below:
--
-- local elist = TensorCore.entityList("chartype=4")
-- local targets = {}
-- for id,ent in pairs(elist) do
-- table.insert(targets,ent.pos)
-- end
-- local heading = PartyPlan.getMostClusteredCone(Player.pos, targets, math.rad(90), 20)
-- this would give us the best heading to hit as many chartype4 (players) as possible from the player pos with a 90 degree cone that has a 20 yds radius

function PartyPlan.getMostClusteredCone(playerPos, targets, coneAngle, coneRadius)
    local bestHeading = 0
    local maxTargetsHit = 0
    local bestCentroidX, bestCentroidZ

    for heading = 0, math.pi * 2, 0.05 do --mby adjust this for more accuracy vs potential lag (decreasing the 0.05 to 0.01 gives more accuracy but 5 times the amount of iteration)
        local targetsHit = 0
        local hitTargets = {}

        for _, targetPos in ipairs(targets) do
            local headingToTarget = TensorCore.getHeadingToTarget(playerPos,targetPos)
            local angleDiff = math.abs((heading - headingToTarget + math.pi) % (math.pi * 2) - math.pi)
            if angleDiff <= coneAngle / 2 and TensorCore.getDistance2d(playerPos, targetPos) <= coneRadius then
                targetsHit = targetsHit + 1
                table.insert(hitTargets, targetPos)
            end
        end
        local centerX, centerZ = 0, 0
        for _, pos in ipairs(hitTargets) do
            centerX = centerX + pos.x
            centerZ = centerZ + pos.z
        end
        centerX = centerX / #hitTargets
        centerZ = centerZ / #hitTargets
        if targetsHit > maxTargetsHit then
            maxTargetsHit = targetsHit
            bestHeading = TensorCore.getHeadingToTarget(playerPos,{x = centerX,y = 0,z = centerZ})
        end
    end
    return bestHeading
end


RegisterEventHandler("Gameloop.Draw", PartyPlan.draw, "PartyPlan-GUI")


