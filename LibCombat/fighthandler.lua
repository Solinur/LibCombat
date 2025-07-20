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
local FightHandler = ZO_Object:Subclass()

---@diagnostic disable-next-line: duplicate-set-field
function FightHandler:New(...)
    local object = ZO_Object.New(self)
    object:Initialize(...)
    return object
end

function FightHandler:Initialize()
	self.char = libunits.playername
	self.group = libunits.inGroup
	self.dataVersion = 3
	self.units = {}
	self.unitInfo = {bosses = {}, group = {}, player = libunits.playerId}
end

function FightHandler:ResetFight()
	logger:Info("Reset Fight")

	if ld.inCombat ~= true then return end
	reset = true

	self:FinishFight()
	self:onUpdate()

	libint.currentfight:PrepareFight()
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
		combatstart = timems
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

local function InitUnitPower()
	ld.resources[COMBAT_MECHANIC_FLAGS_HEALTH] = GetUnitPower("player", COMBAT_MECHANIC_FLAGS_HEALTH)
	ld.resources[COMBAT_MECHANIC_FLAGS_MAGICKA] = GetUnitPower("player", COMBAT_MECHANIC_FLAGS_MAGICKA)
	ld.resources[COMBAT_MECHANIC_FLAGS_STAMINA] = GetUnitPower("player", COMBAT_MECHANIC_FLAGS_STAMINA)
	ld.resources[COMBAT_MECHANIC_FLAGS_ULTIMATE] = GetUnitPower("player", COMBAT_MECHANIC_FLAGS_ULTIMATE)
end

function FightHandler:PrepareFight()
	local timems = GetGameTimeMilliseconds()

	if self.prepared ~= true then
		logger:Debug("PrepareFight")

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

	charData.skillBars = ZO_DeepTableCopy(ld.skillBars)
	charData.scribedSkills = ZO_DeepTableCopy(ld.scribedSkills)
	charData.equip = GetEquip()

	self.info.combatend = GetGameTimeMilliseconds()

	-- libint.lastAbilityActivations = {}   -- TODO: Move to skills processor 
	-- libint.isProjectile = {}  -- TODO: Move to skills processor 

	logger:Debug("FinishFight")
	-- ld.lastabilities = {}  -- TODO: Move to resource processor 
end

---@param unitId integer
function FightHandler:CheckUnit(unitId)
	if self.units[unitId] == nil then 
		local unit = lib.GetUnitById(unitId):GetFullUnitData()
		self.units[unitId] = unit
		if unit.isBoss then 
			self.bossfight = true 
			self.unitInfo.bosses[unitId] = true
		end
		if unit.unitType == COMBAT_UNIT_TYPE_GROUP or unit.unitType == libint.COMBAT_UNIT_TYPE_GROUP_COMPANION then
			self.unitInfo.group[unitId] = true
		end
		-- TODO: Check if additional info is needed 
	end
end


local lastGetNewStatsCall = 0
---@param timems integer
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

---@return number? playerTime
---@return integer? playerDamage
---@return number? totalTime
---@return integer? totalDamage
function FightHandler:GetDamageToUnit(unitId)
	if self.damageReceived == nil or self.damageReceived[unitId] == nil then return end

	local unitData = self.damageReceived[unitId]
	local unitTime = (unitData.endTime - unitData.startTime)/1000
	
	local playerUnitData = unitData[self.unitInfo.playerId]
	local playerDamage = 0
	local playerTime = 0
	if playerUnitData then
		playerDamage = playerUnitData.totalDamage
		playerTime = (playerUnitData.endTime - playerUnitData.startTime)/1000
	end

	return playerTime, playerDamage, unitTime, unitData.totalDamage
end

---@return number? playerTime
---@return integer? playerDamage
---@return number? totalTime
---@return integer? totalDamage
function FightHandler:GetDamageToUnits(unitIds)	-- Gets highest Single Target Damage and counts enemy units.
	if self.damageReceived == nil then return end

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

			local playerUnitData = unitData[self.unitInfo.playerId]
			if playerUnitData then
				playerStartTime = zo_min(playerStartTime, unitData.playerStartTime)
				playerEndTime = zo_max(playerEndTime, unitData.playerEndTime)
				playerDamage = playerDamage + unitData.playerDamage
			end
		end
	end

	if endTime == 0 then return end
	if playerEndTime == 0 then 
		playerStartTime = 0
	end
	local unitTime = (endTime - startTime)/1000
	local playerTime = (playerEndTime - playerStartTime)/1000

	return playerTime, playerDamage, unitTime, totalDamage
end

--- Get biggest unit.
---@return number? playerTime
---@return integer? playerDamage
---@return number? totalTime
---@return integer? totalDamage
function FightHandler:GetMainUnit()
	if self.damageReceived == nil then return end
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

---@return number? playerTime
---@return integer? playerHealing
---@return number? totalTime
---@return integer? totalHealing
function FightHandler:GetHealing()
	local healingData = self.healingReceived
	if healingData == nil then return end

	local playerStartTime = math.huge
	local playerEndTime = 0
	local playerHealing = 0
	local startTime = math.huge
	local endTime = 0
	local totalHealing = 0

	local groupUnitIds = self.unitInfo.groupt
	
	for i, unitId in ipairs(groupUnitIds) do
		local unitData = self.healingReceived[unitId]
		if unitData then
			startTime = zo_min(startTime, unitData.startTime)
			endTime = zo_max(endTime, unitData.endTime)
			totalHealing = totalHealing + unitData.totalHealing

			local playerUnitData = unitData[self.unitInfo.playerId]
			if playerUnitData then
				playerStartTime = zo_min(playerStartTime, unitData.playerStartTime)
				playerEndTime = zo_max(playerEndTime, unitData.playerEndTime)
				playerHealing = playerHealing + unitData.playerHealing
			end
		end
	end

	if endTime == 0 then return end
	if playerEndTime == 0 then 
		playerStartTime = 0
	end
	local unitTime = (endTime - startTime)/1000
	local playerTime = (playerEndTime - playerStartTime)/1000

	return playerTime, playerHealing, unitTime, totalHealing
end

function FightHandler:onUpdate()
	libint.onCombatState(EVENT_PLAYER_COMBAT_STATE, IsUnitInCombat("player"))

	--reset data
	if reset == true or (ld.inCombat == false and self.combatend > 0 and (GetGameTimeMilliseconds() > (self.combatend + timeout)) ) then
		self:UpdateFightStats()
		lib.cm:FireCallbacks((libint.CallbackKeys[LIBCOMBAT_EVENT_FIGHTSUMMARY]), LIBCOMBAT_EVENT_FIGHTSUMMARY, self)
		EVENT_MANAGER:UnregisterForUpdate("LibCombat_update")
		logger:Debug("resetting...")
		reset = false

		libint.currentfight = FightHandler:New()
	elseif ld.inCombat == true then
		self:UpdateFightStats()
	end
end

function lib.InitializeFights()
	if isFileInitialized == true then return false end
	logger = lf.initSublogger("fights")
	libint.currentfight = FightHandler:New()

    isFileInitialized = true
	return true
end