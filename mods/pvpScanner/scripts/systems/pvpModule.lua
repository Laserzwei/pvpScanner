package.path = package.path .. ";data/scripts/systems/?.lua"
package.path = package.path .. ";data/scripts/lib/?.lua"
require ("basesystem")
require ("utility")
require ("randomext")
require ("callable")

-- optimization so that energy requirement doesn't have to be read every frame
--FixedEnergyRequirement = true

--data
local seed, rarity
local isScanning = false
local scanningprogress = 0
local scanningTime = 25
local playerList
local foundPlayers = {}
local additionalEnergyUsage = 0
local myRandom  = Random(Seed(appTimeMs()))
local origProductionRate = 0

--UI
local uiInitialized = false
local window
local nameList = {}
local coordList = {}
local labelcontent = {}
local scanButton
local progressBar
local oldLabelList = {}

function onInstalled(pSeed, pRarity)
    seed, rarity = pSeed, pRarity
    if onServer() then
        invokeClientFunction(Player(), "onInstalled", seed, rarity)

		-- Hammelpilaw: When user get moved in other sector while scanning, search MUST be stopped
		Entity():registerCallback("onJump", "stopScanning")
    else
        initUI(seed, rarity)
    end
end

function onUninstalled(seed, rarity)

end

function interactionPossible(playerIndex, option)
    local player = Player(playerIndex)
    if player.craft.index.string == Entity().index.string then
        return true
    else
        return false
    end
end

-- create all required UI elements for the client side
function initUI(seed, rarity)
    if not seed or not rarity then
        print("cheese")
        local res = getResolution()
        local size = vec2(800, 600)

        local menu = ScriptUI()
        window = menu:createWindow(Rect(res * 0.5 - size * 0.5, res * 0.5 + size * 0.5))
        menu:registerWindow(window, "Scan for players"%_t)

        window.caption = "Player Scanner"%_t
        window.showCloseButton = 1
        window.moveable = 1

         return
    end --super cheesy hacking, don't do this
    local size = window.size

    local scanButtonSize = 200
    y = 20
    local buttonRect = Rect(size.x/2 - scanButtonSize/2-15, y, size.x/2 + scanButtonSize/2-15, y + 35)
    scanButton = window:createButton(buttonRect, "Start Scanning"%_t, "onStartScanning")
    scanButton.tooltip = "Scan up to " ..getPlayerScannerRange(seed, rarity).." Sectors away. \n"
    y = y + 45

    local rect = Rect(size.x/2 - scanButtonSize-15, size.y-20-25, size.x/2 + scanButtonSize-15, size.y-20)
    progressBar = window:createNumbersBar(rect)
    progressBar:setRange(0, scanningTime)

    uiInitialized = true
end

function getName(seed, rarity)
    return "Player Scanner"%_t
end

function getIcon(seed, rarity)
    return "data/textures/icons/wavy-chains.png"
end

function getEnergy(seed, rarity)
    math.randomseed(seed)
    local energy = getPlayerScannerRange(seed, rarity) * 1e8 + getPlayerScannerRange(seed, rarity) * 1e6 * (math.random()+0.5)
    return energy * 4.5 ^ rarity.value + additionalEnergyUsage
end

function getBE(seed, rarity)
    math.randomseed(seed)
    local energy = getPlayerScannerRange(seed, rarity) * 1e8 + getPlayerScannerRange(seed, rarity) * 1e6 * (math.random()+0.5)
    return energy * 4.5 ^ rarity.value
end

function getPrice(seed, rarity)
    math.randomseed(seed)
    local price = getPlayerScannerRange(seed, rarity) * 1e4 + getPlayerScannerRange(seed, rarity) * 1e4 * (math.random()+0.5)
    return price * 2.5 ^ rarity.value
end

function getPlayerScannerRange(seed, rarity)
    math.randomseed(seed)
    local range = 3 * rarity.value + 4 + math.floor(math.random()+0.5)
    return range
end

function getTooltipLines(seed, rarity)
    local texts = {}
    local range = getPlayerScannerRange(seed, rarity)
    table.insert(texts, {ltext = "Player scanning range"%_t, rtext = string.format("+%i", range), icon = "data/textures/icons/rss.png"})
    return texts
end

function getDescriptionLines(seed, rarity)
    return
    {
        {ltext = "Adds a scanner for Players. \n Halves energy production when active."%_t, rtext = "", icon = ""}
    }
end

function getUpdateInterval()
  return 0.05
end

function updateServer(timestep)
    if seed and rarity then
        if isScanning then
			-- Consume energy
			setProductionRate()
        end
    end
end

function updateClient(timestep)
    if seed and rarity then
        if isScanning then

            -- Hammelpilaw
			-- scan lasts longer when there is not enaugh energy
			local energySystem = EnergySystem(Entity().index)
			local step = timestep
			if energySystem.consumableEnergy == 0 then
				-- multiplier value depending on energy: 0.05 - 1
				local multiplier = math.max(1 - ((energySystem.requiredEnergy - energySystem.productionRate) / (origProductionRate * 0.5)), 0.05)
				multiplier = math.min(multiplier, 1)
				step = timestep * multiplier
			end
            -- End: Hammelpilaw
            scanningprogress = scanningprogress + step
            if scanningprogress >= scanningTime then
                onStopScanning()
                scanningprogress = scanningTime
            end
            percProgress = scanningprogress/scanningTime
            progressBar:clear()
            progressBar:setRange(0, scanningTime)
            progressBar:addEntry(scanningprogress, "Progress: "..round(percProgress*100,2).."%", ColorARGB(0.9, 1-percProgress, percProgress, 0.1))
            if playerList then
                for i,playerData in ipairs(playerList) do
                    if foundPlayers[i] then
                        local coordIndex = coordList[i].index
                        local x, y
                        local name
                        if labelcontent[coordIndex] then
                            x, y = getRandomCoord(playerData.x, playerData.y, labelcontent[coordIndex].x, labelcontent[coordIndex].y, percProgress)
                            name = getRandomName(playerData.name, labelcontent[coordIndex].name, percProgress)
                            oldLabelList[i].caption = labelcontent[coordIndex].name
                        else
                            x, y = getRandomCoord(playerData.x, playerData.y, nil, nil, percProgress)
                            name = getRandomName(playerData.name, nil, percProgress)
                        end
                        local coordText = "("..x..":"..y..")"
                        local showName = name:gsub(" ", "")

                        nameList[i].caption = name
                        coordList[i].caption = coordText
                        coordList[i].tooltip = "Click to find "..showName.." on the Galaxymap"
                        coordList[i].mouseDownFunction = "onCoordClicked"
                        if showName == playerData.name then
                            oldLabelList[i].caption = ""
                        end
                        if x == playerData.x and y == playerData.y then
                            coordList[i].color = ColorRGB(0.3, 0.9, 0.1)
                        else
                            coordList[i].color = ColorRGB(1.0, 1.0, 1.0)
                        end
                        labelcontent[coordIndex]= {x=x,y=y, name = name, playerData.index}
                    else
                        if findPlayer(i, percProgress) then foundPlayers[i] = true end
                    end
                end
            end
        end
    end
end

function findPlayer(i, percProgress)
    return myRandom:getFloat(0.0, 1.0)-0.7 > (0.5-percProgress)
end

function getRandomCoord(pX, pY, lastX, lastY, percProgress)
    lastX = lastX or myRandom:getInt(-500,500)
    lastY = lastY or myRandom:getInt(-500,500)
    local x,y
    if percProgress > 0.2 then
        if pX ~= lastX then
            local dist = math.min(50, math.sqrt(pX^2-lastX^2))
            dist = dist * (1 - percProgress)
            x = myRandom:getInt(pX-dist, pX + dist)
        else
            x = pX
        end

        if pY ~= lastY then
            local dist = math.min(50, math.sqrt(pY^2-lastY^2))
            dist = dist * (1 - percProgress)
            y = myRandom:getInt(pY-dist, pY + dist)
        else
            y = pY
        end
    else
        x,y = myRandom:getInt(-500,500), myRandom:getInt(-500,500)
    end

    return x, y
end

function getRandomName(name, lastName, percProgress)
	if percProgress >= 1.0 then
        return name
    end

    lastName = lastName or ""
    local newName = ""
    for i=1, 25 do
        if percProgress > 0.2 then
            local nameChar = name:byte(i) or 32 -- " "
            local lastNameChar = lastName:byte(i) or myRandom:getInt(48,57)
            --print(nameChar == lastNameChar, nameChar, lastNameChar)
            if lastNameChar ~= nameChar then
                if percProgress + myRandom:getFloat(0.0, 0.4) >= 1 then
                    newName = newName..string.char(nameChar)
                else
                    local char = myRandom:getInt(48,57)
                    newName = newName..string.char(char)
                end
            else
                newName = newName..string.char(nameChar)
            end
        else
            --newName = newName..string.char(myRandom:getInt(48,57))
        end
    end
    return newName
end

function applyMalus()
    print("Malus", onServer())
    local entity = Entity()
	if entity.shieldDurability then
		local damage = entity.shieldDurability * 0.99
		entity:damageShield(damage, entity.translationf, Player(callingPlayer).craftIndex)
    end
    entity.hyperspaceCooldown = math.max(entity.hyperspaceCooldown, scanningTime * 2)
end

function setProductionRate()
	local energySystem = EnergySystem(Entity().index)

	if onServer() then
		invokeClientFunction(Player(), "setProductionRate")
	end

	-- Should never happen, but did in some tests... maybe few ms async
	if not isScanning then
		restoreProductionRate()
		return
	end

	energySystem.productionRate = origProductionRate * 0.5

	--print("rate: "..energySystem.productionRate / 1000000 .. " M")
end

function restoreProductionRate()
	if not origProductionRate then
		print("No valid original production rate. Can not restore energy production.")
		return
	end

	local energySystem = EnergySystem(Entity().index)

	energySystem.productionRate = origProductionRate
	print("restoreProductionRate: " .. origProductionRate)
end

function startScanning()
	local energySystem = EnergySystem(Entity().index)
	origProductionRate = energySystem.productionRate
    myRandom  = Random(Seed(appTimeMs()))
    isScanning = true
end
callable(nil, "startScanning")

function stopScanning()
    isScanning = false
	restoreProductionRate()
end
callable(nil, "stopScanning")

function onStartScanning()
	-- This function may be executed when already scanning. This should be skipped.
	if not isScanning then
        scanButton.onPressedFunction = "onStopScanning"
        scanButton.caption = "Stop Scanning"
        progressBar:clear()
        scanningprogress = 0
        foundPlayers = {}
        startScanning()
        invokeServerFunction("startScanning")
        invokeServerFunction("getPlayersInRange")
    end
end

function onStopScanning()
    scanButton.onPressedFunction = "onStartScanning"
    scanButton.caption = "Start Scanning"
    stopScanning()
    invokeServerFunction("stopScanning")
end

function getPlayersInRange()
	if not rarity then
		print("Function getPlayersInRange() skipping - rarity is nil")
		return
	end
    applyMalus()
    local onlineplayers = {Server():getOnlinePlayers()}
    table.insert(onlineplayers, {index = 10, name = "playerA", getSectorCoordinates = function() return -422,-152 end})
    table.insert(onlineplayers, {index = 11, name = "playerB", getSectorCoordinates = function() return -416,-152 end})
    table.insert(onlineplayers, {index = 12, name = "playerCWith an absolutely far too long name used for shenanigains", getSectorCoordinates = function() return 422,152 end})
    table.insert(onlineplayers, {index = 13, name = "playerD", getSectorCoordinates = function() return -412,-152 end})
    table.insert(onlineplayers, {index = 14, name = "playerE", getSectorCoordinates = function() return -416,-154 end})
    table.insert(onlineplayers, {index = 15, name = "playerF", getSectorCoordinates = function() return -427,-156 end})
    table.insert(onlineplayers, {index = 16, name = "playerG", getSectorCoordinates = function() return -419,-158 end})
    local scannedplayers = {}

    local range = math.huge--getPlayerScannerRange(seed, rarity)
    local playerposX, playerposY = Player():getSectorCoordinates()

    for _,player in pairs(onlineplayers) do
        if player and player.index ~= Player().index then --don't scan for yourself
			local pX, pY = player.getSectorCoordinates()
            local dist = math.sqrt((playerposX-pX)^2 + (playerposY-pY)^2)
            if dist <= range then
                table.insert(scannedplayers, {index = player.index, name = player.name, x=pX, y=pY})
                --player:sendChatMessage("", 2, "Another ship located your position!"%_t)
            end
        end
    end
    local player = Player(callingPlayer)
    invokeClientFunction(player, "receivePlayersInRange", scannedplayers)
end
callable(nil, "getPlayersInRange")

function receivePlayersInRange(pPlayerList)
    playerList = pPlayerList
    y = 75
    for i,e in pairs(nameList) do
        e:hide()
        nameList[i] = nil
    end
    for i,e in pairs(oldLabelList) do
        e:hide()
        oldLabelList[i] = nil
    end
    for i,e in pairs(coordList) do
        e:hide()
        coordList[i] = nil
    end
    labelcontent = {}

    local nameLabelSizeX = 400
    local coordLabelSize = 150

    for i,playerData in ipairs(playerList) do
        local oldLbl = window:createLabel(vec2(10, y+1), "", 15)
        oldLbl.color = ColorARGB(0.9, 0.1, 0.5, 0.1)
        oldLbl.size = vec2(nameLabelSizeX, 25)
        oldLbl.wordBreak = false
        local lbl = window:createLabel(vec2(10, y), "", 15)
        lbl.color = ColorARGB(1.0, 0.1, 0.8, 0.1)
        lbl.size = vec2(nameLabelSizeX, 25)
        lbl.caption = ""
        lbl.wordBreak = false
        local lbl2 = window:createLabel(vec2(nameLabelSizeX + 10 + 20, y), "", 15)
        lbl2.tooltip = nil
        lbl2.mouseDownFunction = ""
        lbl2.size = vec2(coordLabelSize, 25)
        table.insert(oldLabelList, oldLbl)
        table.insert(nameList, lbl)
        table.insert(coordList, lbl2)
        y = y + 35
    end
end

function onCoordClicked(labelIndex)
    local x, y = labelcontent[labelIndex].x, labelcontent[labelIndex].y
    GalaxyMap():show(x, y)
end
