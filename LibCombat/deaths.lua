-- This file provides info on player and group member deaths and resurrection

local lib = LibCombat
local libint = lib.internal
local CallbackKeys = libint.callbackKeys
local lf = libint.functions
local ld = libint.data
local libunits = ld.units
local logger

local lastdeaths = {}
local CombatEventCache = {}
local maxUnitCacheEvents = 60
local UnitDeathsToProcess = {}
local deathRecapTimePeriod = 10000


function lf.ProcessDeathRecaps()
	local timems = GetGameTimeMilliseconds()

	for unitId, UnitDeathCache in pairs(UnitDeathsToProcess) do
		if timems - UnitDeathCache.timems > 200 then
			logger:Debug("ProcessDeath: %s (%d)", libint.currentfight.units[unitId].name, unitId)
			UnitDeathCache:ProcessDeath()
		end
	end
end

function lf.ClearUnitCaches()
	logger:Debug("ClearUnitCaches (%d)", NonContiguousCount(CombatEventCache))

	for unitId, UnitDeathCache in pairs(CombatEventCache) do
		CombatEventCache[unitId] = nil
	end

	UnitDeathsToProcess = {}
end

local UnitDeathCacheHandler = ZO_Object:Subclass()	-- holds all recent events + info to send on death

---@diagnostic disable-next-line: duplicate-set-field
function UnitDeathCacheHandler:New(...)
    local object = ZO_Object.New(self)
    object:Initialize(...)
    return object
end

function UnitDeathCacheHandler:Initialize(unitId)

	self.nextKey = 1
	self.maxlength = maxUnitCacheEvents
	self.cache = {}
	self.unitId = unitId

	CombatEventCache[unitId] = self

	if not libint.debug then return end

	local unitname = libint.currentfight.units[unitId] and libint.currentfight.units[unitId].name or "Unknown"

	logger:Debug("Init unit death cache: %s (%d)", unitname, unitId)

end

function UnitDeathCacheHandler:OnDeath(timems)

	self.timems = timems

	UnitDeathsToProcess[self.unitId] = self

	if not libint.debug then return end

	local unitname = libint.currentfight.units[self.unitId] and libint.currentfight.units[self.unitId].name or "Unknown"

	logger:Debug("UnitCacheHandler:OnDeath: %s (%d)", unitname, self.unitId)

end

function UnitDeathCacheHandler:ProcessDeath()

	local unit = libint.currentfight.units[self.unitId]

	if unit then ZO_ShallowTableCopy(unit:GetUnitInfo(), self) end

	self.bossname = libint.currentfight.bossname
	self.zoneId = libint.currentfight.zoneId
	self.fighttime = libint.currentfight.date
	self.combatstart = libint.currentfight.combatstart

	self.log = {}
	local cache = self.cache

	if #cache > 0 then

		local log = self.log
		local offset = self.nextKey - 1
		local length = #self.cache
		local timems = self.timems

		local deleted = 0

		logger:Debug("Processing death event cache. Offset: %d, length:%d", offset, length)

		for i = 0, length - 1 do

			local cachekey = (i + offset)%length + 1
			local data = cache[cachekey]

			if timems - data[1] < deathRecapTimePeriod then

				log[#log + 1] = data
				local sourceUnitId = data[3]
				local sourceUnit = sourceUnitId and sourceUnitId>0 and libint.currentfight and libint.currentfight.units and libint.currentfight.units[sourceUnitId] or "nil"
				--sourceUnitId == location ??
				data[3] = (sourceUnit and sourceUnit.name) or "Unknown"

				if data[10] and self.magickaMax and data[10] > self.magickaMax then self.magickaMax = data[10] end
				if data[11] and self.staminaMax and data[11] > self.staminaMax then self.staminaMax = data[11] end

			else

				deleted = deleted + 1

			end
		end

		logger:Debug("%s: cache: %d, log: %d, deleted: %d", unit and unit.name or "Unknown", #cache, #log, deleted)
	end

	self.cache = nil
	self.health = nil
	self.stamina = nil
	self.magicka = nil
	self.nextKey = nil
	self.maxlength = nil

	libint.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_DEATHRECAP]), LIBCOMBAT_EVENT_DEATHRECAP, self.timems, self)

	UnitDeathCacheHandler:New(self.unitId)
	UnitDeathsToProcess[self.unitId] = nil
end

function UnitDeathCacheHandler:AddEvent(timems, result, sourceUnitId, abilityId, hitValue, damageType, overflow)

	if self.health == nil then self:InitResources() end

	local nextKey = self.nextKey

	self.cache[nextKey] = {timems, result, sourceUnitId, abilityId, damageType, hitValue, overflow, self.health, self.healthMax, self.magicka, self.stamina}

	self.nextKey = (nextKey % self.maxlength) + 1

	self.timems = timems

end

function UnitDeathCacheHandler:InitResources()

	local unit = libint.currentfight.units[self.unitId]

	if unit then

		local unitTag = unit.unitTag

		self.health, self.healthMax = GetUnitPower(unitTag, COMBAT_MECHANIC_FLAGS_HEALTH)

		if unitTag == "player" then

			self.magicka = GetUnitPower(unitTag, COMBAT_MECHANIC_FLAGS_MAGICKA)
			self.stamina = GetUnitPower(unitTag, COMBAT_MECHANIC_FLAGS_STAMINA)

		end
	end
end

function UnitDeathCacheHandler:UpdateResource(powerType, value, powerMax)

	if powerType == COMBAT_MECHANIC_FLAGS_HEALTH then

		self.health = value
		self.healthMax = powerMax > 0 and powerMax or self.healthMax or 0

	elseif powerType == COMBAT_MECHANIC_FLAGS_STAMINA then

		self.stamina = value
		self.staminaMax = powerMax > 0 and powerMax or self.staminaMax or 0

	elseif powerType == COMBAT_MECHANIC_FLAGS_MAGICKA then

		self.magicka = value
		self.magickaMax = powerMax > 0 and powerMax or self.magickaMax or 0

	end
end

local function GetUnitCache(unitId)

	if unitId == nil or unitId < 1 then return end

	local unitCache = CombatEventCache[unitId]

	if unitCache == nil then unitCache = UnitDeathCacheHandler:New(unitId) end

	return unitCache

end

local function CheckForWipe()	-- TODO use preassembled group unit tags

	if not IsUnitDeadOrReincarnating("player") then return end -- maybe it's enough if player is dead on combat end? (Unless it bugs, like Sunspire ... ¯\_(ツ)_/¯)

	if libunits.inGroup == false then

		libint.currentfight.isWipe = true

	elseif libunits.inGroup == true then

		local playerZoneIndex = GetUnitZoneIndex("player")

		local GroupUnitTags = libunits.GroupUnitTags

		for i = 1, GetGroupSize() do

			local unitTag = GroupUnitTags[i]

			local unitId = libunits.unitIdsByTag[unitTag]
			local unit = unitId and libunits.unitCache[unitId]

			if unit and (not unit.isDead) and GetUnitZoneIndex(unitTag) == playerZoneIndex then return end	-- if there is a group member in the same zone but not dead then it's not a wipe

		end
	end

	libint.currentfight.isWipe = true

	logger:Debug("=== This is a wipe ! ===")

end

local function OnDeathStateChanged(_, unitTag, isDead) 	-- death (for group display, also works for different zones)
	local unitId = unitTag == "player" and lib.GetPlayerUnitId() or libunits.unitIdsByTag[unitTag]

	logger:Debug("OnDeathStateChanged: %s (%s) is dead: %s", unitTag, tostring(unitId), tostring(isDead))

	if ld.inCombat == false or unitId == nil then

		logger:Debug("OnDeathStateChanged: Combat: %s", tostring(ld.inCombat))
		return
	end

	local unit = libint.currentfight.units[unitId]
	if unit then unit.isDead = isDead else

		logger:Debug("OnDeathStateChanged: no unit")
		return
	end

	local timems = GetGameTimeMilliseconds()

	if isDead then

		local lasttime = lastdeaths[unitId]

		if (lasttime and lasttime - timems < 1000) then return end

		GetUnitCache(unitId):OnDeath(timems)

		logger:Debug("OnDeathStateChanged: fire callback")
		libint.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_LOG_EVENT_DEATH]), LIBCOMBAT_LOG_EVENT_DEATH, timems, LIBCOMBAT_UNIT_STATE_DEAD, unitId)

		CheckForWipe()

	else

		libint.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_LOG_EVENT_DEATH]), LIBCOMBAT_LOG_EVENT_DEATH, timems, LIBCOMBAT_UNIT_STATE_ALIVE, unitId)

	end
end

local function OnPlayerReincarnated()
	logger:Debug("You revived")
end


local function OnDeath(_, result, _, abilityName, _, abilityActionSlotType, sourceName, sourceType, targetName, targetType, hitValue, powerType, damageType, _, sourceUnitId, targetUnitId, abilityId, overflow)
	local timems = GetGameTimeMilliseconds()
	if targetUnitId == nil or targetUnitId == 0 then return end

	local unitdata = libint.currentfight.units[targetUnitId]
	if unitdata == nil or (unitdata.unitType ~= COMBAT_UNIT_TYPE_PLAYER and unitdata.unitType ~= COMBAT_UNIT_TYPE_GROUP) then return end
	lastdeaths[targetUnitId] = timems
	GetUnitCache(targetUnitId):OnDeath(timems)

	libint.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_LOG_EVENT_DEATH]), LIBCOMBAT_LOG_EVENT_DEATH, timems, LIBCOMBAT_UNIT_STATE_DEAD, targetUnitId, abilityId)
	CheckForWipe()
end

local function OnResurrect(_, result, _, abilityName, _, abilityActionSlotType, sourceName, sourceType, targetName, targetType, hitValue, powerType, damageType, _, sourceUnitId, targetUnitId, abilityId)
	local timems = GetGameTimeMilliseconds()
	if targetUnitId == nil or targetUnitId == 0 or ld.inCombat == false then return end
	local unitdata = libint.currentfight.units[targetUnitId]
	if unitdata == nil or unitdata.type ~= COMBAT_UNIT_TYPE_GROUP then return end
	libint.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_LOG_EVENT_DEATH]), LIBCOMBAT_LOG_EVENT_DEATH, timems, LIBCOMBAT_UNIT_STATE_ALIVE, targetUnitId)
end

local function OnResurrectResult(_, targetCharacterName, result, targetDisplayName)
	if result ~= RESURRECT_RESULT_SUCCESS then return end
	logger:Debug("OnResurrectResult: %s", targetCharacterName)

	local name = ZO_CachedStrFormat(SI_UNIT_NAME, targetCharacterName) or ""
	local unitId = libunits.unitIdsByName[name]
	if not unitId then return end
	
	local timems = GetGameTimeMilliseconds()
	libint.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_LOG_EVENT_DEATH]), LIBCOMBAT_LOG_EVENT_DEATH, timems, LIBCOMBAT_UNIT_STATE_RESURRECTED, unitId, libunits.playerId)
end

local function OnResurrectRequest(_, requesterCharacterName, timeLeftToAccept, requesterDisplayName)
	logger:Debug("OnResurrectRequest: %s", requesterCharacterName)

	local name = ZO_CachedStrFormat(SI_UNIT_NAME, requesterCharacterName) or ""
	local unitId = libunits.unitIdsByName[name]
	if not unitId then return end
	
	local timems = GetGameTimeMilliseconds()
	libint.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_LOG_EVENT_DEATH]), LIBCOMBAT_LOG_EVENT_DEATH, timems, LIBCOMBAT_UNIT_STATE_RESURRECTED, libunits.playerId, unitId)

end
local function GroupCombatEventHandler(isheal, result, _, abilityName, _, _, sourceName, sourceType, targetName, _, hitValue, powerType, damageType, _, sourceUnitId, targetUnitId, abilityId, overflow)  -- called by Event

	if (hitValue + (overflow or 0)) < 0 or (not (targetUnitId > 0)) or (ld.inCombat == false and (result==ACTION_RESULT_DOT_TICK_CRITICAL or result==ACTION_RESULT_DOT_TICK or isheal) ) then return end -- only record if both unitids are valid or player is in combat or a non dot damage action happens

	local timems = GetGameTimeMilliseconds()

	if libint.currentfight.prepared ~= true then libint.currentfight:PrepareFight() end -- get stats before the damage event

	damageType = (isheal and powerType) or damageType

	GetUnitCache(targetUnitId):AddEvent(timems, result, sourceUnitId, abilityId, hitValue, damageType, overflow or 0)

	if overflow and overflow > 0 and not isheal then

		logger:Debug("GroupCombatEventHandler: %s has overflow damage!", targetName)
		GetUnitCache(targetUnitId):OnDeath(timems)

	end

end

local function onCombatEventGrpDmgIn(event, ...)

	local targetUnitId = select(15, ...)

	local unit = libint.currentfight.units[targetUnitId]
	local targetType = unit and unit.unitType or nil

	if not targetType or (targetType ~= COMBAT_UNIT_TYPE_GROUP and targetType ~= COMBAT_UNIT_TYPE_PLAYER) then return end

	GroupCombatEventHandler(false, ...)

end

local function onCombatEventGrpHealIn(event, ...)

	local targetUnitId = select(15, ...)

	local unit = libint.currentfight.units[targetUnitId]
	local targetType = unit and unit.unitType or nil

	if not targetType or (targetType ~= COMBAT_UNIT_TYPE_GROUP and targetType ~= COMBAT_UNIT_TYPE_PLAYER) then return end

	GroupCombatEventHandler(true, ...)

end

local function onBaseResourceChangedGroup(event, unitTag, powerIndex, powerType, powerValue, powerMax, powerEffectiveMax)

	local unitId = unitTag == "player" and libunits.playerId or libunits.unitIdsByTag

	if unitId then GetUnitCache(unitId):UpdateResource(powerType, powerValue, powerMax) end

end

libint.Events.Deaths = libint.EventHandler:New(
	{LIBCOMBAT_LOG_EVENT_DEATH, LIBCOMBAT_EVENT_DEATHRECAP},
	function (self)

		self:RegisterEvent(EVENT_COMBAT_EVENT, OnDeath, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_KILLING_BLOW)
		self:RegisterEvent(EVENT_COMBAT_EVENT, OnDeath, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_DIED)
		self:RegisterEvent(EVENT_COMBAT_EVENT, OnResurrect, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_RESURRECT)
		self:RegisterEvent(EVENT_COMBAT_EVENT, OnResurrect, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_REINCARNATING)
		self:RegisterEvent(EVENT_UNIT_DEATH_STATE_CHANGED, OnDeathStateChanged, REGISTER_FILTER_UNIT_TAG_PREFIX, "group")
		self:RegisterEvent(EVENT_UNIT_DEATH_STATE_CHANGED, OnDeathStateChanged, REGISTER_FILTER_UNIT_TAG, "player")
		self:RegisterEvent(EVENT_PLAYER_REINCARNATED, OnPlayerReincarnated)

		self:RegisterEvent(EVENT_RESURRECT_RESULT, OnResurrectResult)
		self:RegisterEvent(EVENT_RESURRECT_REQUEST, OnResurrectRequest)

		self.active = true

	end
)

libint.Events.DeathRecap = libint.EventHandler:New(
	{LIBCOMBAT_EVENT_DEATHRECAP},
	function (self)

		local filters = {
			ACTION_RESULT_DAMAGE,
			ACTION_RESULT_DOT_TICK,
			ACTION_RESULT_BLOCKED_DAMAGE,
			ACTION_RESULT_DAMAGE_SHIELDED,
			ACTION_RESULT_CRITICAL_DAMAGE,
			ACTION_RESULT_DOT_TICK_CRITICAL,
			ACTION_RESULT_FALL_DAMAGE,
			ACTION_RESULT_DODGED,
		}

		for _, filter in ipairs(filters) do
			self:RegisterEvent(EVENT_COMBAT_EVENT, onCombatEventGrpDmgIn, REGISTER_FILTER_COMBAT_RESULT, filter, REGISTER_FILTER_IS_ERROR, false)
		end

		local filters2 = {
			ACTION_RESULT_HOT_TICK,
			ACTION_RESULT_HEAL,
			ACTION_RESULT_CRITICAL_HEAL,
			ACTION_RESULT_HOT_TICK_CRITICAL,
		}

		for _, filter in ipairs(filters2) do
			self:RegisterEvent(EVENT_COMBAT_EVENT, onCombatEventGrpHealIn, REGISTER_FILTER_COMBAT_RESULT, filter, REGISTER_FILTER_IS_ERROR, false)
		end

		self:RegisterEvent(EVENT_POWER_UPDATE, onBaseResourceChangedGroup, REGISTER_FILTER_UNIT_TAG_PREFIX, "group")
		self:RegisterEvent(EVENT_POWER_UPDATE, onBaseResourceChangedGroup, REGISTER_FILTER_UNIT_TAG, "player")

		self.active = true
	end
)

local isFileInitialized = false
function lib.InitializeDeaths()
	if isFileInitialized == true then return false end
	logger = lf.initSublogger("death")

    isFileInitialized = true
	return true
end