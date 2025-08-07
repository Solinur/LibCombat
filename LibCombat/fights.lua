-- This file contains handling of collected fight data

local lib = LibCombat
local libint = lib.internal
local lf = libint.functions
local ld = libint.data
local libunits = ld.units
local logger
local isFileInitialized = false
local reset = false
local timeout = 800

local function GetCurrentCP()
	local CP = {}
	CP.version = 2

	-- collect slotted stars
	local slotsById = {}
	for slotIndex = 1, 12 do
		local starId = GetSlotBoundId(slotIndex, HOTBAR_CATEGORY_CHAMPION)
		if starId > 0 then
			slotsById[starId] = slotIndex
		end
	end

	--  collect CP data
	local disciplines = CHAMPION_DATA_MANAGER.disciplineDatas

	for _, discipline in pairs(disciplines) do
		local disciplineId = discipline.disciplineId
		local stars = discipline.championSkillDatas

		local disciplineData = {}
		CP[disciplineId] = disciplineData

		disciplineData.total = discipline:GetNumSavedSpentPoints()
		disciplineData.stars = {}
		disciplineData.slotted = {}

		local discStarData = disciplineData.stars
		local discSlotData = disciplineData.slotted

		for _, star in pairs(stars) do
			local savedPoints = star:GetNumSavedPoints()

			if savedPoints > 0 then
				local starId = star.championSkillId
				local slotable = star:IsTypeSlottable()
				local slotted = slotsById[starId] ~= nil
				local starType = (slotted and LIBCOMBAT_CPTYPE_SLOTTED) or (slotable and LIBCOMBAT_CPTYPE_UNSLOTTED) or LIBCOMBAT_CPTYPE_PASSIVE

				discStarData[starId] = {savedPoints, starType}
				if slotted then discSlotData[starId] = true end
			end
		end
	end

	return CP
end

---@class Fight
---@field New function
local FightHandler = ZO_InitializingObject:Subclass()

function FightHandler:Initialize()
	self.char = libunits.playername
	self.group = libunits.inGroup
	self.dataVersion = 3
	---@type table<integer, UnitData>
	self.units = {}
	self.unitIds = {bosses = {}, group = {}, player = libunits.playerId}
	self.CP = GetCurrentCP()
end

function FightHandler:ResetFight()
	logger:Info("Reset Fight")

	if ld.inCombat ~= true then return end
	reset = true

	self:FinishFight()
	self:onUpdate()

	libint.currentFight:PrepareFight()
	libint.onCombatState(EVENT_PLAYER_COMBAT_STATE, IsUnitInCombat("player"))
end

function FightHandler:GetMetaData(timems)
	self.info = {
		date = GetTimeStamp(),
		time = GetTimeString(),
		zone = GetPlayerActiveZoneName(),
		subzone = GetPlayerActiveSubzoneName(),
		zoneId = GetUnitWorldPosition("player"),
		ESOversion = GetESOVersionString(),
		APIversion = GetAPIVersion(),
		account = libunits.accountname,
		combatStart = timems
	}

	local charData = {}
	self.charData = charData

	charData.name = libunits.playername
	charData.raceId = GetUnitRaceId("player")
	charData.gender = GetUnitGender("player")
	charData.classId = GetUnitClassId("player")
	charData.level = GetUnitLevel("player")
	charData.CPtotal = GetUnitChampionPoints("player")

	self.CP = GetCurrentCP()
end

local function InitUnitPower() -- TODO: Move to resources
	ld.resources[COMBAT_MECHANIC_FLAGS_HEALTH] = GetUnitPower("player", COMBAT_MECHANIC_FLAGS_HEALTH)
	ld.resources[COMBAT_MECHANIC_FLAGS_MAGICKA] = GetUnitPower("player", COMBAT_MECHANIC_FLAGS_MAGICKA)
	ld.resources[COMBAT_MECHANIC_FLAGS_STAMINA] = GetUnitPower("player", COMBAT_MECHANIC_FLAGS_STAMINA)
	ld.resources[COMBAT_MECHANIC_FLAGS_ULTIMATE] = GetUnitPower("player", COMBAT_MECHANIC_FLAGS_ULTIMATE)
end

function FightHandler:PrepareFight()
	local timems = GetGameTimeMilliseconds()

	if self.prepared ~= true then
		logger:Debug("PrepareFight")
		libint.LogProcessingQueue:SetCombatState(true)

		FightHandler:GetMetaData(timems)

		 -- TODO: Move to resource processor 
		-- InitUnitPower()
		
		 -- TODO: Move to stats processor 
		-- ld.backstabber = lf.GetCritBonusFromCP(self.CP)
		-- ld.stats = {}
		-- ld.advancedStats = {}
		
		-- TODO: Move to skills processor 
		-- self.startBar = ld.bar
		-- libint.lastQueuedAbilities = {}
		-- libint.usedCastTimeAbility = {}

		self.isWipe = false
		self.prepared = true
				
		-- self:QueueStatUpdate(timems) -- TODO: Move to stats processor 
		-- lf.GetCurrentSkillBars()  -- TODO: Move to skills processor 
	end

	EVENT_MANAGER:RegisterForUpdate("LibCombat_update", 500, function() self:onUpdate() end)
end


local function GetEquip()
	local equip = {}
	
	---@diagnostic disable-next-line: undefined-global
	for i = EQUIP_SLOT_ITERATION_BEGIN, EQUIP_SLOT_ITERATION_END do
		equip[i] = GetItemLink(BAG_WORN, i, LINK_STYLE_DEFAULT)
	end

	return equip
end

function FightHandler:FinishFight()
	local charData = self.charData

	if charData == nil then return end

	-- charData.skillBars = ZO_DeepTableCopy(ld.skillBars)    -- TODO: Move to skills processor 
	-- charData.scribedSkills = ZO_DeepTableCopy(ld.scribedSkills)    -- TODO: Move to skills processor 
	charData.equip = GetEquip()

	self.info.combatEnd = GetGameTimeMilliseconds()

	-- libint.lastAbilityActivations = {}   -- TODO: Move to skills processor 
	-- libint.isProjectile = {}  -- TODO: Move to skills processor 

	logger:Debug("FinishFight")
	libint.LogProcessingQueue:SetCombatState(false)
	-- ld.lastabilities = {}  -- TODO: Move to resource processor 
end

---@param unitId integer
function FightHandler:CheckUnit(unitId)
	if self.units[unitId] == nil then 
		---@type UnitData
		local unit = lib.GetUnitById(unitId):GetFullUnitData()
		if unit == nil then return end
		self.units[unitId] = unit
		if unit.unitType == COMBAT_UNIT_TYPE_PLAYER then 
			self.unitIds.player = unitId
		end
		if unit.isBoss then 
			self.bossFight = true 
			self.unitIds.bosses[unitId] = true
		end
		if unit.unitType == COMBAT_UNIT_TYPE_GROUP or unit.unitType == libint.COMBAT_UNIT_TYPE_GROUP_COMPANION then
			self.unitIds.group[unitId] = true
		end
		-- TODO: Check if additional info is needed 
	end
end


local lastGetNewStatsCall = 0
---@param timems integer?
function FightHandler:QueueStatUpdate(timems)
	-- TODO: review when integrating stats module
	if libint.Events.Stats.active ~= true then return end
	EVENT_MANAGER:UnregisterForUpdate("LibCombat_Stats")

	timems = timems or GetGameTimeMilliseconds()
	local lastcalldelta = timems - lastGetNewStatsCall

	if lastcalldelta < 100 then
		EVENT_MANAGER:RegisterForUpdate("LibCombat_Stats", (100 - lastcalldelta), function() self:QueueStatUpdate() end)
		return
	end

	lastGetNewStatsCall = timems
	lf.UpdateStats(timems)
end

-- Return player and total damage done to a single unit including the durations in seconds during which the damage happend.
---@param unitId integer
---@return number? playerTime
---@return integer? playerDamage
---@return number? totalTime
---@return integer? totalDamage
function FightHandler:GetDamageToUnit(unitId)
	if self.damageReceived == nil or self.damageReceived[unitId] == nil then return end
	
	local unitData = self.damageReceived[unitId]
	local unitTime = (unitData.endTime - unitData.startTime)/1000
	
	local playerUnitData = unitData[self.unitIds.player]
	local playerDamage = 0
	local playerTime = 0
	if playerUnitData then
		playerDamage = playerUnitData.totalDamage
		playerTime = (playerUnitData.endTime - playerUnitData.startTime)/1000
	end

	return playerTime, playerDamage, unitTime, unitData.totalDamage
end

-- Return player and total damage done to specified units including the durations in seconds during which the damage happend.
---@return number playerTime
---@return integer playerDamage
---@return number totalTime
---@return integer totalDamage
function FightHandler:GetDamageToUnits(unitIds)
	if self.damageReceived == nil then return 0, 0, 0, 0 end

	local playerStartTime = math.huge
	local playerEndTime = 0
	local playerDamage = 0
	local startTime = math.huge
	local endTime = 0
	local totalDamage = 0
	
	for i, unitId in ipairs(unitIds) do
		local unitData = self.damageReceived[unitId]
		if unitData then
			startTime = zo_min(startTime, unitData.startTime)
			endTime = zo_max(endTime, unitData.endTime)
			totalDamage = totalDamage + unitData.totalDamage

			local playerUnitData = unitData[self.unitIds.player]
			if playerUnitData then
				playerStartTime = zo_min(playerStartTime, playerUnitData.startTime)
				playerEndTime = zo_max(playerEndTime, playerUnitData.endTime)
				playerDamage = playerDamage + playerUnitData.totalDamage
			end
		end
	end

	if endTime == 0 then return 0, 0, 0, 0 end
	if playerEndTime == 0 then
		playerStartTime = 0
	end
	local unitTime = (endTime - startTime)/1000
	local playerTime = (playerEndTime - playerStartTime)/1000

	return playerTime, playerDamage, unitTime, totalDamage
end

--- Returns the unitId of the biggest unit.
---@return integer targetUnitId
function FightHandler:GetMainUnit()
	if self.damageReceived == nil then return 0 end
	local damageData = self.damageReceived

	local maxHealth = 0
	local targetUnitId

	for unitId, unit in pairs(self.units) do
		if unit.maxHealth > maxHealth then
			targetUnitId = unitId
			maxHealth = unit.maxHealth
		end
		local unitData = damageData[unitId]
		if unitData ~= nil and unitData.totalDamage > maxHealth then
			targetUnitId = unitId
			maxHealth = unitData.totalDamage
		end
	end
	
	return targetUnitId
end

-- Return player and total healing done including the durations in seconds during which the healing happend.
---@return number playerTime
---@return integer playerHealing
---@return integer playerOverflowHealing
---@return number totalTime
---@return integer totalHealing
---@return integer totalOverflowHealing
function FightHandler:GetHealingDone()
	local healingData = self.healingReceived
	if healingData == nil then return 0, 0, 0, 0 end

	local playerStartTime = math.huge
	local playerEndTime = 0
	local playerHealing = 0
	local playerOverflowHealing = 0
	local startTime = math.huge
	local endTime = 0
	local totalHealing = 0
	local totalOverflowHealing = 0

	local groupUnitIds = self.unitIds.group
	
	for i, unitId in ipairs(groupUnitIds) do
		local unitData = healingData[unitId]
		if unitData then
			startTime = zo_min(startTime, unitData.startTime)
			endTime = zo_max(endTime, unitData.endTime)
			totalHealing = totalHealing + unitData.totalHealing
			totalOverflowHealing = totalOverflowHealing + unitData.totalOverflowHealing
		end
	end

	local playerUnitData = self.healingDone and self.healingDone[self.unitIds.player] or nil
	if playerUnitData then
		playerStartTime = playerUnitData.startTime
		playerEndTime = playerUnitData.endTime
		playerHealing = playerUnitData.totalHealing
		playerOverflowHealing = playerUnitData.overflowHealing
	end

	if endTime == 0 then return 0, 0, 0, 0 end
	if playerEndTime == 0 then 
		playerStartTime = 0
	end
	local unitTime = (endTime - startTime)/1000
	local playerTime = (playerEndTime - playerStartTime)/1000

	return playerTime, playerHealing, playerOverflowHealing, unitTime, totalHealing, totalOverflowHealing
end

-- Return player healing received including the durations in seconds during which the healing happend.
---@return number time
---@return integer playerHealingReceived
function FightHandler:GetPlayerHealingReceived()
	local playerUnitData = self.healingReceived and self.healingDone[self.unitIds.player] or nil
	if playerUnitData == nil then return 0, 0 end

	local playerStartTime = playerUnitData.startTime
	local playerEndTime = playerUnitData.endTime
	local healing = playerUnitData.totalHealing

	if playerEndTime == 0 then return 0, 0 end
	local time = (playerEndTime - playerStartTime)/1000

	return time, healing
end

local function PrintCombatStats()
	local playerTime, playerDamage, unitTime, totalDamage = lib.GetCurrentMainTargetDamageDone()
	local playerDPS =  playerTime > 0 and playerDamage/playerTime or 0
	local groupDPS =  unitTime > 0 and totalDamage/unitTime or 0
	logger:Info("%.0f, %.3fs / %.0f, %.3fs", playerDPS, playerTime, groupDPS, unitTime)

	local playerMultiTime, playerMultiDamage, unitMultiTime, totalMultiDamage = lib.GetCurrentTotalDamageDone()
	local playerMultiDPS =  playerMultiTime > 0 and playerMultiDamage/playerMultiTime or 0
	local groupMultiDPS =  unitMultiTime > 0 and totalMultiDamage/unitMultiTime or 0
	logger:Info("%.0f, %.3fs / %.0f, %.3fs", playerMultiDPS, playerMultiTime, groupMultiDPS, unitMultiTime)
end

function FightHandler:onUpdate()
	libint.onCombatState(EVENT_PLAYER_COMBAT_STATE, IsUnitInCombat("player"))

	--reset data
	if reset == true or (ld.inCombat == false and self.info.combatEnd ~= nil and (GetGameTimeMilliseconds() > (self.info.combatEnd + timeout)) ) then
		libint.cm:FireCallbacks((libint.CallbackKeys[LIBCOMBAT_EVENT_FIGHTSUMMARY]), LIBCOMBAT_EVENT_FIGHTSUMMARY, self)
		EVENT_MANAGER:UnregisterForUpdate("LibCombat_update")
		logger:Debug("resetting...")
		reset = false

		PrintCombatStats()

		libint.lastFight = libint.currentFight
		local newFight = FightHandler:New()
		libint.currentFight = newFight
		libint.LogProcessingQueue:SetFight(newFight)
	end
end


function lf.onPlayerActivated()
	logger:Debug("onPlayerActivated")

	-- zo_callLater(lf.GetCurrentSkillBars, 100) -- TODO: Reactivate ?
	libint.isInPortalWorld = false
end

local function getCurrentBossHP()
	if BOSS_BAR.control:IsHidden() then return 0 end

	local totalHealth = 0
    local totalMaxHealth = 0

    for unitTag, bossEntry in pairs(BOSS_BAR.bossHealthValues) do
        totalHealth = totalHealth + bossEntry.health
        totalMaxHealth = totalMaxHealth + bossEntry.maxHealth
	end

	return totalHealth/totalMaxHealth
end

local function IsOngoingBossfight()
	if libint.isInPortalWorld then -- prevent fight reset in bossfights when using a portal.
		logger:Debug("Prevented combat reset because player is in Portal!")
		return true
	elseif getCurrentBossHP() > 0 and getCurrentBossHP() < 1 then
		logger:Info("Prevented combat reset because boss is still in fight!")
		return true
	end
	return false
end


-- Event Functions
function libint.onCombatState(event, inCombat)  -- Detect Combat Stage, local is defined above - Don't Change !!!
	if inCombat ~= ld.inCombat then     -- Check if player state changed
		local timems = GetGameTimeMilliseconds()

		if inCombat then
			ld.inCombat = inCombat
			logger:Debug("Entering combat.")
			libint.cm:FireCallbacks((libint.CallbackKeys[LIBCOMBAT_LOG_EVENT_COMBATSTATE]), LIBCOMBAT_LOG_EVENT_COMBATSTATE, timems, LIBCOMBAT_MESSAGE_COMBATSTART, 0)
			libint.currentFight:PrepareFight()
		else
			if IsOngoingBossfight() then
				logger:Debug("Failed: Leaving combat.")
				return
			end

			ld.inCombat = false
			logger:Debug("Leaving combat.")
			libint.currentFight:FinishFight()

			if libint.currentFight.charData == nil then return end
			libint.cm:FireCallbacks((libint.CallbackKeys[LIBCOMBAT_LOG_EVENT_COMBATSTATE]), LIBCOMBAT_LOG_EVENT_COMBATSTATE, timems, LIBCOMBAT_MESSAGE_COMBATEND, 0)
		end
	end
end

local function onPortalWorld( _, changeType)
	libint.isInPortalWorld = changeType == EFFECT_RESULT_GAINED
end

local function onMageExplode()
	libint.currentFight:ResetFight()	-- special tracking for The Mage in Aetherian Archives. It will reset the fight when the mage encounter starts.
end


local lastUpdateStats
local function UpdateStats()
	local fight = libint.currentFight

	if (fight.dpsend == nil and fight.hpsend == nil) or (fight.dpsstart == nil and fight.hpsstart == nil) then return end
	
	local playerBossTime, playerBossDamage, groupBossTime, groupBossDamage = lib.GetCurrentMainTargetDamageDone()
	local bossDPSOut = zo_floor(playerBossDamage / playerBossTime + 0.5)
	local bossDPSOutGroup = zo_floor(groupBossDamage / groupBossTime + 0.5)

	local playerDPSTime, playerDamageOut, groupDPSTime, groupDamageOut = lib.GetCurrentTotalDamageDone()
	local playerDPSOut = zo_floor(playerDamageOut / playerDPSTime + 0.5)
	local groupDPSOut = zo_floor(groupDamageOut / groupDPSTime + 0.5)

	local playerHPSTime, playerHealingOut, playerHealingOutOverflow, groupHPSTime, groupHealingOut, groupHealingOutOverflow = fight:GetHealingDone()
	local playerHPSOut = zo_floor(playerHealingOut / playerHPSTime + 0.5)
	local playerOHPSOut = zo_floor(playerHealingOutOverflow / playerHPSTime + 0.5)
	local groupHPSOut = zo_floor(groupHealingOut / groupHPSTime + 0.5)
	local groupOHPSOut = zo_floor(groupHealingOutOverflow / groupHPSTime + 0.5)

	local playerDPSInTime, playerDamageIn, groupDPSInTime, groupDamageIn = lib.GetCurrentTotalDamageDone()
	local playerDPSIn = zo_floor(playerDamageIn / playerDPSInTime + 0.5)
	local groupDPSIn = zo_floor(groupDamageIn / groupDPSInTime + 0.5)

	local healingReceivedTime, healingReceived = fight:GetPlayerHealingReceived()
	local HPSIn = zo_floor(healingReceived / healingReceivedTime + 0.5)

	local data = {
		["bossfight"] = fight.bossfight,
		["group"] = fight.group,

		["bossDamageTotal"] = playerBossDamage,
		["bossTime"] = playerBossTime,
		["bossDPSOut"] = bossDPSOut,
		["bossDamageTotalGroup"] = groupBossDamage,
		["bossGroupTime"] = groupBossTime,
		["bossDPSOutGroup"] = bossDPSOutGroup,

		["damageOutTotal"] = playerDamageOut,
		["dpstime"] = playerDPSTime,
		["DPSOut"] = playerDPSOut,
		["dpsGroupTime"] = groupDPSTime,
		["damageOutTotalGroup"] = groupDamageOut,
		["groupDPSOut"] = playerDPSOut,

		["healingOutTotal"] = playerHealingOut,
		["overHealingOutTotal"] = playerHealingOutOverflow,
		["hpstime"] = playerHPSTime,
		["HPSOut"] = playerHPSOut,
		["HPSAOut"] = playerOHPSOut,
		["OHPSOut"] = playerOHPSOut,

		["groupHPSOut"] = groupHPSOut,
		["groupOHPSOut"] = groupOHPSOut,

		["DPSIn"] = playerDPSIn,
		["groupDPSIn"] = groupDPSIn,
		["HPSIn"] = HPSIn,
	}

	for key, value in pairs(data) do
		if lastUpdateStats[key] ~= value then 
			lib.cm:FireCallbacks((libint.CallbackKeys[LIBCOMBAT_EVENT_UNITS]), LIBCOMBAT_EVENT_UNITS, fight.units)
			lib.cm:FireCallbacks((libint.CallbackKeys[LIBCOMBAT_EVENT_FIGHTRECAP]), LIBCOMBAT_EVENT_FIGHTRECAP, data)
			break
		end
	end
	lastUpdateStats = data
end


-- Events

libint.Events.General = libint.EventHandler:New(
	lf.GetAllCallbackTypes(),
	function (self)
		self:RegisterEvent(EVENT_PLAYER_COMBAT_STATE, libint.onCombatState)

		-- self:RegisterEvent(EVENT_HOTBAR_SLOT_CHANGE_REQUESTED, lf.GetCurrentSkillBars)  -- TODO: Reactivate ?
		self:RegisterEvent(EVENT_PLAYER_ACTIVATED, lf.onPlayerActivated)
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onMageExplode, REGISTER_FILTER_ABILITY_ID, 50184)
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onPortalWorld, REGISTER_FILTER_ABILITY_ID, 108045)
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onPortalWorld, REGISTER_FILTER_ABILITY_ID, 121216)

		self.active = true
	end
)


function libint.InitializeFights()
	if isFileInitialized == true then return false end
	logger = lf.initSublogger("fights")

	local newFight = FightHandler:New()
	libint.currentFight = newFight
	lf.ActivateProcessors()
	libint.LogProcessingQueue:SetFight(newFight)
	
	libint.onCombatState(EVENT_PLAYER_COMBAT_STATE, IsUnitInCombat("player"))
	EVENT_MANAGER:RegisterForUpdate("LibCombatUpdateCombatStats", 500, UpdateStats)

	ld.inCombat = false

    isFileInitialized = true
	return true
end