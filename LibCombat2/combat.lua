-- This file provides combat log entries regarding damage and heal events

---@class LibCombat2
local lib = LibCombat2
---@class LCint
local libint = lib.internal
---@class LCData
local ld = libint.data
---@class LCUnits
local libunits = ld.units
---@class LCfunc
local lf = libint.functions
---@class Logger
local logger

local countResultKeys = {
	[ACTION_RESULT_DAMAGE] = "normalCount",
	[ACTION_RESULT_DOT_TICK] = "normalCount",
	[ACTION_RESULT_CRITICAL_DAMAGE] = "criticalCount",
	[ACTION_RESULT_DOT_TICK_CRITICAL] = "criticalCount",
	[ACTION_RESULT_BLOCKED_DAMAGE] = "blockedCount",
	[ACTION_RESULT_DAMAGE_SHIELDED] = "absorbedCount",
	[ACTION_RESULT_HEAL] = "normalCount",
	[ACTION_RESULT_HOT_TICK] = "normalCount",
	[ACTION_RESULT_CRITICAL_HEAL] = "criticalCount",
	[ACTION_RESULT_HOT_TICK_CRITICAL] = "criticalCount",
	[ACTION_RESULT_HEAL_ABSORBED] = "absorbedCount",
}

local amountResultKeys = {
	[ACTION_RESULT_DAMAGE] = "normalAmount",
	[ACTION_RESULT_DOT_TICK] = "normalAmount",
	[ACTION_RESULT_CRITICAL_DAMAGE] = "criticalAmount",
	[ACTION_RESULT_DOT_TICK_CRITICAL] = "criticalAmount",
	[ACTION_RESULT_BLOCKED_DAMAGE] = "blockedAmount",
	[ACTION_RESULT_DAMAGE_SHIELDED] = "absorbedAmount",
	[ACTION_RESULT_HOT_TICK] = "normalAmount",
	[ACTION_RESULT_HEAL] = "normalAmount",
	[ACTION_RESULT_CRITICAL_HEAL] = "criticalAmount",
	[ACTION_RESULT_HOT_TICK_CRITICAL] = "criticalAmount",
	[ACTION_RESULT_HEAL_ABSORBED] = "absorbedAmount",
}

local AllowedLogTypes = {
	LIBCOMBAT_LOG_EVENT_DAMAGE,
	LIBCOMBAT_LOG_EVENT_HEAL,
}

---@type Queue
local DamageShields = lf.CreateQueue()
ld.DamageShields = DamageShields

---@type Queue
local HealAbsorbs = lf.CreateQueue()
ld.HealAbsorbs = HealAbsorbs

local LogProcessorCombat = lf.LogProcessingHandler:New("combat", AllowedLogTypes)

---@class Fight
---@field damageDone {[integer]: UnitDamageData}  -- levels: [sourceUnitId][targetUnitId][abilityId]
---@field damageReceived {[integer]: UnitDamageData} -- levels: [targetUnitId][sourceUnitId][abilityId]
---@field healingDone {[integer]: UnitHealData} -- levels: [sourceUnitId][targetUnitId][abilityId]
---@field healingReceived {[integer]: UnitHealData} -- levels: [targetUnitId][sourceUnitId][abilityId]

---@param fight Fight
function LogProcessorCombat:onInitilizeFight(fight)
	if self.active ~= true then
		return
	end

	fight.damageDone = {}
	fight.damageReceived = {}
	fight.healingDone = {}
	fight.healingReceived = {}

	local timeMs = GetGameTimeMilliseconds()

	for i = DamageShields.first, DamageShields.last do
		if timeMs - DamageShields[i][1] > 100 then
			DamageShields:Pop()
		end
	end

	for i = HealAbsorbs.first, HealAbsorbs.last do
		if timeMs - HealAbsorbs[i][1] > 100 then
			HealAbsorbs:Pop()
		end
	end
end

function LogProcessorCombat:onCombatStart() end

---@param fight Fight
function LogProcessorCombat:onCombatEnd(fight)
	if fight.processors[self.name] ~= true then
		return
	end
	for targetUnitId, data in pairs(fight.damageReceived) do
		local hasData = false
		for sourceUnitId, _ in pairs(data) do
			if type(sourceUnitId) == "number" and sourceUnitId > 0 then
				hasData = true
				break
			end
		end

		if hasData == false then
			fight.damageReceived[targetUnitId] = nil
		end
	end
end

---@param fight Fight
---@param logType integer
function LogProcessorCombat:ProcessLogLine(fight, logType, ...)
	if logType == LIBCOMBAT_LOG_EVENT_DAMAGE then
		self:ProcessLogLineDamage(fight, ...)
		return
	end
	if logType == LIBCOMBAT_LOG_EVENT_HEAL then
		self:ProcessLogLineHeal(fight, ...)
		return
	end
	logger:Error("Unsupported logtype %d for processor %s", logType, self.name)
end

---@param fight Fight
---@param t table<integer, UnitDamageData>
---@param unitId integer
---@param timeMs integer
---@return UnitDamageData
local function InitUnitDamageData(fight, t, unitId, timeMs)
	fight:CheckUnit(unitId)

	---@class UnitDamageData
	---@field [integer] UnitDamageData|DamageAbilityData
	local unitData = {
		totalAmount = 0,
		startTime = timeMs,
		endTime = timeMs,
	}
	t[unitId] = unitData

	return unitData
end

local function GetUnitDamageData(fight, sourceUnitId, targetUnitId, timeMs)
	local targetData = fight.damageReceived[targetUnitId]
		or InitUnitDamageData(fight, fight.damageReceived, targetUnitId, timeMs)
	local unitData = targetData[sourceUnitId or 0] or InitUnitDamageData(fight, targetData, sourceUnitId, timeMs)

	local sourceDataDone
	if sourceUnitId and sourceUnitId > 0 then
		sourceDataDone = fight.damageDone[sourceUnitId]
			or InitUnitDamageData(fight, fight.damageDone, sourceUnitId, timeMs)
		if sourceDataDone[targetUnitId] == nil then
			sourceDataDone[targetUnitId] = unitData
		end
	end

	return targetData, unitData, sourceDataDone
end

---@param timeMs integer
---@param damageType DamageType
---@return DamageAbilityData
local function InitDamageAbilityData(timeMs, damageType)
	---@class DamageAbilityData
	local abilityData = {
		totalAmount = 0,
		normalAmount = 0,
		criticalAmount = 0,
		blockedAmount = 0,
		absorbedAmount = 0,
		totalCount = 0,
		normalCount = 0,
		criticalCount = 0,
		blockedCount = 0,
		absorbedCount = 0,
		damageType = damageType,
		startTime = timeMs,
		endTime = timeMs,
	}

	return abilityData
end
lf.InitDamageAbilityData = InitDamageAbilityData

---@param unitData UnitDamageData
---@param damage integer
---@param timeMs integer
local function UpdateUnitDamageData(unitData, damage, timeMs)
	unitData.totalAmount = unitData.totalAmount + damage
	unitData.endTime = timeMs
end

---@param abilityData DamageAbilityData
---@param timeMs integer
---@param damage integer
---@param overflow integer
---@param result ActionResult
local function UpdateDamageAbilityData(abilityData, timeMs, damage, overflow, result)
	local fullValue = damage + overflow

	local resultkey = amountResultKeys[result]
	local hitKey = countResultKeys[result]

	abilityData.totalAmount = abilityData.totalAmount + fullValue
	abilityData.totalCount = abilityData.totalCount + fullValue
	abilityData[resultkey] = abilityData[resultkey] + fullValue
	abilityData[hitKey] = abilityData[hitKey] + 1

	abilityData.max = zo_max(abilityData.max or fullValue, fullValue)
	abilityData.min = zo_min(abilityData.min or fullValue, fullValue)
	abilityData.endTime = timeMs

	-- IncrementStatSum(fight, damageType, resultkey, isDamageOut, hitValue, false, unit) TODO: Move to stat module
end

---@param fight Fight
---@param timeMs integer
---@param result ActionResult
---@param sourceUnitId integer
---@param targetUnitId integer
---@param abilityId integer
---@param hitValue integer
---@param damageType DamageType
---@param overflow integer
function LogProcessorCombat:ProcessLogLineDamage(
	fight,
	timeMs,
	result,
	sourceUnitId,
	targetUnitId,
	abilityId,
	hitValue,
	damageType,
	overflow
)
	if targetUnitId == nil or targetUnitId <= 0 then
		return
	end

	local targetData, unitData, sourceDataDone = GetUnitDamageData(fight, sourceUnitId, targetUnitId, timeMs)
	local fullValue = hitValue + overflow
	UpdateUnitDamageData(targetData, fullValue, timeMs)
	UpdateUnitDamageData(unitData, fullValue, timeMs)
	if sourceDataDone then
		UpdateUnitDamageData(sourceDataDone, fullValue, timeMs)
	end

	if unitData[abilityId] == nil then
		unitData[abilityId] = InitDamageAbilityData(timeMs, damageType)
	end
	UpdateDamageAbilityData(unitData[abilityId], timeMs, hitValue, overflow, result)
end

local function InitUnitHealingData(fight, t, unitId, timeMs)
	fight:CheckUnit(unitId)

	---@class UnitHealData
	---@field [integer] UnitHealData|HealAbilityData
	local unitData = {
		totalAmount = 0,
		overflowAmount = 0,
		startTime = timeMs,
		endTime = timeMs,
	}
	t[unitId] = unitData

	return unitData
end

local function UpdateUnitHealingData(unitData, healing, overflow, timeMs)
	unitData.totalAmount = unitData.totalAmount + healing
	unitData.overflowAmount = unitData.overflowAmount + overflow
	unitData.endTime = timeMs
end

local function GetUnitHealingData(fight, sourceUnitId, targetUnitId, timeMs)
	local targetData = fight.healingReceived[targetUnitId]
		or InitUnitHealingData(fight, fight.healingReceived, targetUnitId, timeMs)
	local unitData = targetData[sourceUnitId or 0] or InitUnitHealingData(fight, targetData, sourceUnitId, timeMs)

	local sourceDataDone
	if sourceUnitId and sourceUnitId > 0 then
		sourceDataDone = fight.healingDone[sourceUnitId]
			or InitUnitHealingData(fight, fight.healingDone, sourceUnitId, timeMs)
		if sourceDataDone[targetUnitId] == nil then
			sourceDataDone[targetUnitId] = unitData
		end
	end

	return targetData, unitData, sourceDataDone
end

local function InitHealAbilityData(timeMs, powerType)
	---@class HealAbilityData
	local abilityData = {
		totalAmount = 0,
		normalAmount = 0,
		criticalAmount = 0,
		overflowAmount = 0,
		absorbedAmount = 0,
		totalCount = 0,
		normalCount = 0,
		criticalCount = 0,
		overflowCount = 0,
		absorbedCount = 0,
		powerType = powerType,
		startTime = timeMs,
		endTime = timeMs,
	}

	return abilityData
end
lf.InitHealAbilityData = InitHealAbilityData

local function UpdateHealAbilityData(abilityData, timeMs, healing, overflow, result)
	local resultkey = amountResultKeys[result]
	local hitKey = countResultKeys[result]
	local fullValue = healing + overflow

	abilityData[resultkey] = abilityData[resultkey] + healing
	abilityData[hitKey] = abilityData[hitKey] + 1
	abilityData.totalAmount = abilityData.totalAmount + healing
	abilityData.totalCount = abilityData.totalCount + 1

	abilityData.max = zo_max(abilityData.max or fullValue, fullValue)
	abilityData.min = zo_min(abilityData.min or fullValue, fullValue)
	abilityData.endTime = timeMs

	if overflow > 0 then
		abilityData.overflowAmount = abilityData.overflowAmount + overflow
		abilityData.overflowCount = abilityData.overflowCount + 1
	end

	-- IncrementStatSum(fight, damageType, resultkey, isDamageOut, hitValue, false, unit) TODO: Move to stat module
end

---@param fight Fight
---@param timeMs integer
---@param result ActionResult
---@param sourceUnitId integer
---@param targetUnitId integer
---@param abilityId integer
---@param hitValue integer
---@param powerType CombatMechanicFlags
---@param overflow integer
function LogProcessorCombat:ProcessLogLineHeal(
	fight,
	timeMs,
	result,
	sourceUnitId,
	targetUnitId,
	abilityId,
	hitValue,
	powerType,
	overflow
)
	if targetUnitId == nil or targetUnitId <= 0 then
		return
	end

	local fullValue = hitValue + overflow

	local targetData, unitData, sourceDataDone = GetUnitHealingData(fight, sourceUnitId, targetUnitId, timeMs)
	UpdateUnitHealingData(targetData, hitValue, overflow, timeMs)
	UpdateUnitHealingData(unitData, hitValue, overflow, timeMs)
	if sourceDataDone then
		UpdateUnitHealingData(sourceDataDone, hitValue, overflow, timeMs)
	end

	if unitData[abilityId] == nil then
		unitData[abilityId] = InitHealAbilityData(timeMs, powerType)
	end
	UpdateHealAbilityData(unitData[abilityId], timeMs, hitValue, overflow, result)
end

-- Shield Buffers --

local function CheckForAbsorb(cacheData, timeMs, sourceUnitId, targetUnitId)
	for i = cacheData.last, cacheData.first, -1 do
		local shieldtimeMs, shieldSourceUnitId, shieldTargetUnitId, shieldHitValue = unpack(cacheData[i])

		logger:Verbose(
			"Eval Shield Index %d: Source: %s, Target: %s, Time: %d",
			i,
			tostring(shieldSourceUnitId == sourceUnitId),
			tostring(shieldTargetUnitId == targetUnitId),
			timeMs - shieldtimeMs
		)
		if
			shieldSourceUnitId == sourceUnitId
			and shieldTargetUnitId == targetUnitId
			and timeMs - shieldtimeMs < 100
		then
			cacheData:Delete(i)
			return shieldHitValue
		end
	end
end

--(eventCode, result, isError, abilityName, abilityGraphic, abilityActionSlotType, sourceName, sourceType, targetName, targetType, hitValue, powerType, damageType, log, sourceUnitId, targetUnitId, abilityId, overflow)
local function isGroupInvolved(hitValue, sourceUnitId, targetUnitId)
	if hitValue == nil or hitValue <= 0 then
		return false
	end
	if sourceUnitId and sourceUnitId > 0 and libunits[sourceUnitId] and libunits[sourceUnitId].isFriendly then
		return true
	end
	if targetUnitId and targetUnitId > 0 and libunits[targetUnitId] and libunits[targetUnitId].isFriendly then
		return true
	end
	return false
end

local function onCombatEventDamage(
	_,
	result,
	_,
	_,
	_,
	_,
	_,
	_,
	targetName,
	_,
	hitValue,
	_,
	damageType,
	_,
	sourceUnitId,
	targetUnitId,
	abilityId,
	overflow
) -- called by Event
	local timeMs = GetGameTimeMilliseconds()
	if hitValue > 500000 and libint.debug then
		logger:Warn(
			"Big Damage Event: (%d) %s did %d damage to %s",
			abilityId,
			lib.GetFormattedAbilityName(abilityId),
			hitValue,
			tostring(targetName)
		)
	end

	local absorb = CheckForAbsorb(DamageShields, timeMs, sourceUnitId, targetUnitId) or 0
	if (hitValue + overflow + absorb) <= 0 then
		logger:Debug(
			"Empty Damage Event %s (%d) -> %s",
			lib.GetFormattedAbilityName(abilityId),
			abilityId,
			tostring(targetName)
		)
		return
	end

	if libint.currentFight.prepared ~= true and isGroupInvolved() then
		libint.currentFight:OnCombatStart()
	end
	if absorb > 0 then
		lf.FireCallback(
			LIBCOMBAT_LOG_EVENT_DAMAGE,
			timeMs,
			ACTION_RESULT_DAMAGE_SHIELDED,
			sourceUnitId,
			targetUnitId,
			abilityId,
			hitValue,
			damageType,
			0
		)
	end
	lf.FireCallback(
		LIBCOMBAT_LOG_EVENT_DAMAGE,
		timeMs,
		result,
		sourceUnitId,
		targetUnitId,
		abilityId,
		hitValue,
		damageType,
		overflow
	)
end

local function onCombatEventHeal(
	_,
	result,
	_,
	_,
	_,
	_,
	_,
	_,
	targetName,
	_,
	hitValue,
	powerType,
	_,
	_,
	sourceUnitId,
	targetUnitId,
	abilityId,
	overflow
) -- called by Event
	local timeMs = GetGameTimeMilliseconds()
	local absorb = CheckForAbsorb(HealAbsorbs, timeMs, sourceUnitId, targetUnitId) or 0
	if (hitValue + overflow + absorb) <= 0 then
		logger:Debug(
			"Empty Damage Event %s (%d) -> %s",
			lib.GetFormattedAbilityName(abilityId),
			abilityId,
			tostring(targetName)
		)
		return
	end

	if absorb > 0 then
		lf.FireCallback(
			LIBCOMBAT_LOG_EVENT_HEAL,
			timeMs,
			ACTION_RESULT_HEAL_ABSORBED,
			sourceUnitId,
			targetUnitId,
			abilityId,
			absorb,
			powerType,
			0
		)
	end
	lf.FireCallback(
		LIBCOMBAT_LOG_EVENT_HEAL,
		timeMs,
		result,
		sourceUnitId,
		targetUnitId,
		abilityId,
		hitValue,
		powerType,
		overflow
	)
end

local function onCombatEventDamageAbsorbed(
	_,
	result,
	_,
	_,
	_,
	_,
	_,
	_,
	_,
	_,
	hitValue,
	_,
	_,
	_,
	sourceUnitId,
	targetUnitId,
	_,
	overflow
)
	if overflow and overflow > 0 and libint.debug then
		logger:Info(
			"Overflow! Add %d (+%d) Shield: %d -> %d  (%d)",
			hitValue,
			overflow,
			sourceUnitId,
			targetUnitId,
			#DamageShields
		)
	end
	DamageShields:Push({ GetGameTimeMilliseconds(), sourceUnitId, targetUnitId, hitValue })

	logger:Debug("Add %d Shield: %d -> %d  (%d)", hitValue, sourceUnitId, targetUnitId, #DamageShields)
end

local function onCombatEventHealAbsorbed(
	_,
	result,
	_,
	_,
	_,
	_,
	_,
	_,
	_,
	_,
	hitValue,
	_,
	_,
	_,
	sourceUnitId,
	targetUnitId,
	_,
	overflow
)
	if overflow and overflow > 0 and libint.debug then
		logger:Info(
			"Overflow! Add %d (+%d) Heal Absorption: %d -> %d  (%d)",
			hitValue,
			overflow,
			sourceUnitId,
			targetUnitId,
			#HealAbsorbs
		)
	end
	HealAbsorbs:Push({ GetGameTimeMilliseconds(), sourceUnitId, targetUnitId, hitValue })

	logger:Debug("Add %d Shield: %d -> %d  (%d)", hitValue, sourceUnitId, targetUnitId, #HealAbsorbs)
end

libint.Events.Damage = libint.EventHandler:New(
	{ LIBCOMBAT_EVENT_FIGHTRECAP, LIBCOMBAT_EVENT_FIGHTSUMMARY, LIBCOMBAT_LOG_EVENT_DAMAGE },
	function(self)
		logger:Debug("Register Damage Events")

		local filters = {
			ACTION_RESULT_DAMAGE,
			ACTION_RESULT_DOT_TICK,
			ACTION_RESULT_CRITICAL_DAMAGE,
			ACTION_RESULT_DOT_TICK_CRITICAL,
			ACTION_RESULT_BLOCKED_DAMAGE,
		}

		for i = 1, #filters do
			self:RegisterEvent(
				EVENT_COMBAT_EVENT,
				onCombatEventDamage,
				REGISTER_FILTER_COMBAT_RESULT,
				filters[i],
				REGISTER_FILTER_IS_ERROR,
				false
			)
		end

		self:RegisterEvent(
			EVENT_COMBAT_EVENT,
			onCombatEventDamageAbsorbed,
			REGISTER_FILTER_COMBAT_RESULT,
			ACTION_RESULT_DAMAGE_SHIELDED,
			REGISTER_FILTER_IS_ERROR,
			false
		)

		self.active = true
	end
)

libint.Events.Healing = libint.EventHandler:New(
	{ LIBCOMBAT_EVENT_FIGHTRECAP, LIBCOMBAT_EVENT_FIGHTSUMMARY, LIBCOMBAT_LOG_EVENT_HEAL },
	function(self)
		local filters = {
			ACTION_RESULT_HEAL,
			ACTION_RESULT_CRITICAL_HEAL,
			ACTION_RESULT_HOT_TICK,
			ACTION_RESULT_HOT_TICK_CRITICAL,
		}

		for i = 1, #filters do
			self:RegisterEvent(
				EVENT_COMBAT_EVENT,
				onCombatEventHeal,
				REGISTER_FILTER_COMBAT_RESULT,
				filters[i],
				REGISTER_FILTER_IS_ERROR,
				false
			)
		end

		self:RegisterEvent(
			EVENT_COMBAT_EVENT,
			onCombatEventHealAbsorbed,
			REGISTER_FILTER_COMBAT_RESULT,
			ACTION_RESULT_HEAL_ABSORBED,
			REGISTER_FILTER_IS_ERROR,
			false
		)

		self.active = true
	end
)

local isFileInitialized = false

function libint.InitializeCombat()
	if isFileInitialized == true then
		return false
	end
	logger = lf.initSublogger("combat")

	isFileInitialized = true
	return true
end
