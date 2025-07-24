-- This file provides combat log entries regarding damage and heal events

local lib = LibCombat
local libint = lib.internal
local ld = libint.data
local libunits = ld.units
local lf = libint.functions
local logger

local countResultKeys = {
	[ACTION_RESULT_DAMAGE]            = "normalHits",
	[ACTION_RESULT_DOT_TICK]          = "normalHits",
	[ACTION_RESULT_CRITICAL_DAMAGE]   = "criticalHits",
	[ACTION_RESULT_DOT_TICK_CRITICAL] = "criticalHits",
	[ACTION_RESULT_BLOCKED_DAMAGE]    = "blockedHits",
	[ACTION_RESULT_DAMAGE_SHIELDED]   = "absorbedHits",
	[ACTION_RESULT_HEAL]              = "normalHeals",
	[ACTION_RESULT_HOT_TICK]          = "normalHeals",
	[ACTION_RESULT_CRITICAL_HEAL]     = "criticalHeals",
	[ACTION_RESULT_HOT_TICK_CRITICAL] = "criticalHeals",
	[ACTION_RESULT_HEAL_ABSORBED]     = "absorbedHeals",
}

local amountResultKeys = {
	[ACTION_RESULT_DAMAGE]            = "normalDamage",
	[ACTION_RESULT_DOT_TICK]          = "normalDamage",
	[ACTION_RESULT_CRITICAL_DAMAGE]   = "criticalDamage",
	[ACTION_RESULT_DOT_TICK_CRITICAL] = "criticalDamage",
	[ACTION_RESULT_BLOCKED_DAMAGE]    = "blockedDamage",
	[ACTION_RESULT_DAMAGE_SHIELDED]   = "absorbedDamage",
	[ACTION_RESULT_HOT_TICK]          = "normalHealing",
	[ACTION_RESULT_HEAL]              = "normalHealing",
	[ACTION_RESULT_CRITICAL_HEAL]     = "criticalHealing",
	[ACTION_RESULT_HOT_TICK_CRITICAL] = "criticalHealing",
	[ACTION_RESULT_HEAL_ABSORBED]     = "absorbedHealing",
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

---@param fight Fight
function LogProcessorCombat:onInitilizeFight(fight)
	if self.active ~= true then return end

	fight.damageDone = {} 			-- levels: [sourceUnitId][targetUnitId][abilityId]
	fight.damageReceived = {}		-- levels: [targetUnitId][sourceUnitId][abilityId]
	fight.healingDone = {}			-- levels: [sourceUnitId][targetUnitId][abilityId]
	fight.healingReceived = {}		-- levels: [targetUnitId][sourceUnitId][abilityId]

	local timems = GetGameTimeMilliseconds()

	for i = DamageShields.first, DamageShields.last do
		if timems - DamageShields[i][1] > 100 then DamageShields:Pop() end
	end

	for i = HealAbsorbs.first, HealAbsorbs.last do
		if timems - HealAbsorbs[i][1] > 100 then HealAbsorbs:Pop() end
	end
end

function LogProcessorCombat:onCombatStart() end

---@param fight Fight
function LogProcessorCombat:onCombatEnd(fight)
	for targetUnitId, data in pairs(fight.damageReceived) do
		local hasData = false
		for sourceUnitId, _ in pairs(data) do
			if type(sourceUnitId) == "number" and sourceUnitId > 0 then 
				hasData = true
				break
			end
		end
		
		if hasData == false then fight.damageReceived[targetUnitId] = nil end
	end
end

---@param fight Fight
---@param logType integer
function LogProcessorCombat:ProcessLogLine(fight, logType, ...)
	if logType == LIBCOMBAT_LOG_EVENT_DAMAGE then
		self:ProcessLogLineDamage(fight, logType, ...)
		return
	end
	if logType == LIBCOMBAT_LOG_EVENT_HEAL then
		self:ProcessLogLineHeal(fight, logType, ...)
		return
	end
	logger:Error("Unsupported logtype %s for processor %s", logType, self.name)
end

local function InitUnitDamageData(fight, t, unitId, startTime)
	fight:CheckUnit(unitId)

	local unitData = {
		totalDamage = 0,
		startTime = startTime,
	}
	t[unitId] = unitData

	return unitData
end

local function GetUnitDamageData(fight, sourceUnitId, targetUnitId, timems)
	local targetData = fight.damageReceived[targetUnitId] or InitUnitDamageData(fight, fight.damageReceived, targetUnitId, timems)
	local unitData = targetData[sourceUnitId or 0] or InitUnitDamageData(fight, targetData, sourceUnitId, timems)

	local sourceDataDone
	if sourceUnitId and sourceUnitId > 0 then 
		sourceDataDone = fight.damageDone[sourceUnitId] or InitUnitDamageData(fight, fight.damageDone, sourceUnitId, timems)
		if sourceDataDone[targetUnitId] == nil then sourceDataDone[targetUnitId] = unitData end
	end

	return targetData, unitData, sourceDataDone
end


local function InitDamageAbilityData(timems, damageType)
	local abilityData = {
		normalDamage   = 0,
		criticalDamage = 0,
		blockedDamage  = 0,
		absorbedDamage = 0,
		totalDamage    = 0,
		normalHits     = 0,
		criticalHits   = 0,
		blockedHits    = 0,
		absorbedHits   = 0,
		totalHits      = 0,
		damageType     = damageType,
		startTime = timems,
		endTime = timems,
	}

	return abilityData
end

local function UpdateUnitDamageData(unitData, damage, timems)	
	unitData.totalDamage = unitData.totalDamage + damage
	unitData.endTime = timems
end

local function UpdateDamageAbilityData(abilityData, timems, hitValue, overflow, result)
	local fullValue = hitValue + overflow

	local resultkey = amountResultKeys[result]
	local hitKey = countResultKeys[result]

	abilityData.totalDamage = abilityData.totalDamage + fullValue
	abilityData.totalHits = abilityData.totalHits + fullValue
	abilityData[resultkey] = abilityData[resultkey] + fullValue
	abilityData[hitKey] = abilityData[hitKey] + 1

	abilityData.max = zo_max(abilityData.max or fullValue, fullValue)
	abilityData.min = zo_min(abilityData.min or fullValue, fullValue)
	abilityData.endTime = timems

	-- IncrementStatSum(fight, damageType, resultkey, isDamageOut, hitValue, false, unit) TODO: Move to stat module
end

---@param fight Fight
---@param logType integer
---@param timems integer
---@param result ActionResult
---@param sourceUnitId integer
---@param targetUnitId integer
---@param abilityId integer
---@param hitValue integer
---@param damageType DamageType
---@param overflow integer
function LogProcessorCombat:ProcessLogLineDamage(fight, logType, timems, result, sourceUnitId, targetUnitId, abilityId, hitValue, damageType, overflow)
	if targetUnitId == nil or targetUnitId <= 0 then return end
	
	local targetData, unitData, sourceDataDone = GetUnitDamageData(fight, sourceUnitId, targetUnitId, timems)
	local fullValue = hitValue + overflow
	UpdateUnitDamageData(targetData, fullValue, timems)
	UpdateUnitDamageData(unitData, fullValue, timems)
	if sourceDataDone then UpdateUnitDamageData(sourceDataDone, fullValue, timems) end

	if unitData[abilityId] == nil then unitData[abilityId] = InitDamageAbilityData(timems, damageType) end
	UpdateDamageAbilityData(unitData[abilityId], timems, hitValue, overflow, result)
end


local function InitUnitHealingData(fight, t, unitId, startTime)
	fight:CheckUnit(unitId)

	local unitData = {
		totalHealing = 0,
		overflowHealing = 0,
		startTime = startTime,
	}
	t[unitId] = unitData

	return unitData
end

local function UpdateUnitHealingData(unitData, healing, overflow, timems)	
	unitData.totalHealing = unitData.totalHealing + healing
	unitData.overflowHealing = unitData.overflowHealing + overflow
	unitData.endTime = timems
end

local function GetUnitHealingData(fight, sourceUnitId, targetUnitId, timems)
	local targetData = fight.healingReceived[targetUnitId] or InitUnitHealingData(fight, fight.healingReceived, targetUnitId, timems)
	local unitData = targetData[sourceUnitId or 0] or InitUnitHealingData(fight, targetData, sourceUnitId, timems)

	local sourceDataDone
	if sourceUnitId and sourceUnitId > 0 then 
		sourceDataDone = fight.healingDone[sourceUnitId] or InitUnitHealingData(fight, fight.healingDone, sourceUnitId, timems)
		if sourceDataDone[targetUnitId] == nil then sourceDataDone[targetUnitId] = unitData end
	end

	return targetData, unitData, sourceDataDone
end

local function InitHealAbilityData(timems, powerType)
	local abilityData = {
		normalHealing   = 0,
		criticalHealing = 0,
		overflowHealing = 0,
		absorbedHealing = 0,
		totalHealing    = 0,
		normalHeals     = 0,
		criticalHeals   = 0,
		overflowHeals  = 0,
		absorbedHeals   = 0,
		totalHeals      = 0,
		powerType       = powerType,
		startTime       = timems,
	}

	return abilityData
end

local function UpdateHealAbilityData(abilityData, timems, hitValue, overflow, result)
	local resultkey = amountResultKeys[result]
	local hitKey = countResultKeys[result]
	local fullValue = hitValue + overflow

	abilityData[resultkey] = abilityData[resultkey] + hitValue
	abilityData[hitKey] = abilityData[hitKey] + 1	
	abilityData.totalHealing = abilityData.totalHealing + hitValue
	abilityData.totalHeals = abilityData.totalHeals + 1

	abilityData.max = zo_max(abilityData.max or fullValue, fullValue)
	abilityData.min = zo_min(abilityData.min or fullValue, fullValue)
	abilityData.endTime = timems

	if overflow > 0 then
		abilityData.overflowHealing = abilityData.overflowHealing + overflow
		abilityData.overflowHeals = abilityData.overflowHeals + 1
	end

	-- IncrementStatSum(fight, damageType, resultkey, isDamageOut, hitValue, false, unit) TODO: Move to stat module
end

---@param fight Fight
---@param logType integer
---@param timems integer
---@param result ActionResult
---@param sourceUnitId integer
---@param targetUnitId integer
---@param abilityId integer
---@param hitValue integer
---@param powerType CombatMechanicFlags
---@param overflow integer
function LogProcessorCombat:ProcessLogLineHeal(fight, logType, timems, result, sourceUnitId, targetUnitId, abilityId, hitValue, powerType, overflow)
	if targetUnitId == nil or targetUnitId <= 0 then return end

	local fullValue = hitValue + overflow

	local targetData, unitData, sourceDataDone = GetUnitHealingData(fight, sourceUnitId, targetUnitId, timems)
	UpdateUnitHealingData(targetData, fullValue, timems)
	UpdateUnitHealingData(unitData, fullValue, timems)
	if sourceDataDone then UpdateUnitHealingData(sourceDataDone, fullValue, timems) end

	if unitData[abilityId] == nil then unitData[abilityId] = InitHealAbilityData(timems, powerType) end
	UpdateHealAbilityData(unitData[abilityId], timems, hitValue, overflow, result)
end

-- Shield Buffers --

local function CheckForAbsorb(cacheData, timems, sourceUnitId, targetUnitId)
	for i = cacheData.last, cacheData.first, -1 do
		local shieldTimems, shieldSourceUnitId, shieldTargetUnitId, shieldHitValue = unpack(cacheData[i])

		logger:Verbose("Eval Shield Index %d: Source: %s, Target: %s, Time: %d", i, tostring(shieldSourceUnitId == sourceUnitId), tostring(shieldTargetUnitId == targetUnitId), timems - shieldTimems)
		if shieldSourceUnitId == sourceUnitId and shieldTargetUnitId == targetUnitId and timems - shieldTimems < 100 then
			cacheData:Delete(i)
			return shieldHitValue
		end
	end
end

--(eventCode, result, isError, abilityName, abilityGraphic, abilityActionSlotType, sourceName, sourceType, targetName, targetType, hitValue, powerType, damageType, log, sourceUnitId, targetUnitId, abilityId, overflow)
local function isGroupInvolved(hitValue, sourceUnitId, targetUnitId)
	if hitValue == nil or hitValue <= 0 then return false end
	if sourceUnitId and sourceUnitId >0 and libunits[sourceUnitId] and libunits[sourceUnitId].isFriendly then return true end
	if targetUnitId and targetUnitId >0 and libunits[targetUnitId] and libunits[targetUnitId].isFriendly then return true end
	return false
end


local function onCombatEventDamage(_, result, _, _, _, _, _, _, targetName, _, hitValue, _, damageType, _, sourceUnitId, targetUnitId, abilityId, overflow)  -- called by Event
	local timeMs = GetGameTimeMilliseconds()
	if hitValue > 500000 then logger:Warning("Big Damage Event: (%d) %s did %d damage to %d", abilityId, lib.GetFormattedAbilityName(abilityId), hitValue, tostring(targetName)) end
	
	local absorb = CheckForAbsorb(DamageShields, timeMs, sourceUnitId, targetUnitId) or 0
	if (hitValue + overflow + absorb) <= 0 then 
		logger:Debug("Empty Damage Event %s (%d) -> targetName", lib.GetFormattedAbilityName(abilityId), abilityId, tostring(targetName)) 
		return
	end

	if libint.currentFight.prepared ~= true and isGroupInvolved() then libint.currentFight:OnCombatStart() end
	if absorb > 0 then 
		libint.cm:FireCallbacks((libint.CallbackKeys[LIBCOMBAT_LOG_EVENT_DAMAGE]), LIBCOMBAT_LOG_EVENT_DAMAGE, timeMs, ACTION_RESULT_DAMAGE_SHIELDED, sourceUnitId, targetUnitId, abilityId, hitValue, damageType, 0)
	end
	libint.cm:FireCallbacks((libint.CallbackKeys[LIBCOMBAT_LOG_EVENT_DAMAGE]), LIBCOMBAT_LOG_EVENT_DAMAGE, timeMs, result, sourceUnitId, targetUnitId, abilityId, hitValue, damageType, overflow)
end

local function onCombatEventHeal(_, result, _, _, _, _, _, _, targetName, _, hitValue, powerType, _, _, sourceUnitId, targetUnitId, abilityId, overflow)  -- called by Event
	local timeMs = GetGameTimeMilliseconds()
	local absorb = CheckForAbsorb(HealAbsorbs, timeMs, sourceUnitId, targetUnitId) or 0
	if (hitValue + overflow + absorb) <= 0 then
		logger:Debug("Empty Damage Event %s (%d) -> targetName", lib.GetFormattedAbilityName(abilityId), abilityId, tostring(targetName)) 
		return
	end

	if absorb > 0 then 
		libint.cm:FireCallbacks((libint.CallbackKeys[LIBCOMBAT_LOG_EVENT_HEAL]), LIBCOMBAT_LOG_EVENT_HEAL, timeMs, ACTION_RESULT_HEAL_ABSORBED, sourceUnitId, targetUnitId, abilityId, absorb, powerType, 0)
	end
	libint.cm:FireCallbacks((libint.CallbackKeys[LIBCOMBAT_LOG_EVENT_HEAL]), LIBCOMBAT_LOG_EVENT_HEAL, timeMs, result, sourceUnitId, targetUnitId, abilityId, hitValue, powerType, overflow)
end

local function onCombatEventDamageAbsorbed(_, result, _, _, _, _, _, _, _, _, hitValue, _, _, _, sourceUnitId, targetUnitId, _, overflow)
	if overflow and overflow > 0 then logger:Info("Overflow! Add %d (+%d) Shield: %d -> %d  (%d)", hitValue, overflow, sourceUnitId, targetUnitId, #DamageShields) end
	DamageShields:Push({GetGameTimeMilliseconds(), sourceUnitId, targetUnitId, hitValue})

	logger:Debug("Add %d Shield: %d -> %d  (%d)", hitValue, sourceUnitId, targetUnitId, #DamageShields)
end

local function onCombatEventHealAbsorbed(_, result, _, _, _, _, _, _, _, _, hitValue, _, _, _, sourceUnitId, targetUnitId, _, overflow)
	if overflow and overflow > 0 then logger:Info("Overflow! Add %d (+%d) Heal Absorption: %d -> %d  (%d)", hitValue, overflow, sourceUnitId, targetUnitId, #HealAbsorbs) end
	HealAbsorbs:Push({GetGameTimeMilliseconds(), sourceUnitId, targetUnitId, hitValue})

	logger:Debug("Add %d Shield: %d -> %d  (%d)", hitValue, sourceUnitId, targetUnitId, #HealAbsorbs)
end


libint.Events.Damage = libint.EventHandler:New(
	{LIBCOMBAT_EVENT_FIGHTRECAP, LIBCOMBAT_EVENT_FIGHTSUMMARY, LIBCOMBAT_LOG_EVENT_DAMAGE},
	function (self)
		logger:Debug("Register Damage Events")

		local filters = {
			ACTION_RESULT_DAMAGE,
			ACTION_RESULT_DOT_TICK,
			ACTION_RESULT_CRITICAL_DAMAGE,
			ACTION_RESULT_DOT_TICK_CRITICAL,
			ACTION_RESULT_BLOCKED_DAMAGE,
		}

		for i=1,#filters do
			self:RegisterEvent(EVENT_COMBAT_EVENT, onCombatEventDamage, REGISTER_FILTER_COMBAT_RESULT, filters[i], REGISTER_FILTER_IS_ERROR, false)
		end

		self:RegisterEvent(EVENT_COMBAT_EVENT, onCombatEventDamageAbsorbed, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_DAMAGE_SHIELDED, REGISTER_FILTER_IS_ERROR, false)

		self.active = true
	end
)

libint.Events.Healing = libint.EventHandler:New(
	{LIBCOMBAT_EVENT_FIGHTRECAP, LIBCOMBAT_EVENT_FIGHTSUMMARY, LIBCOMBAT_LOG_EVENT_HEAL},
	function (self)

		local filters = {
			ACTION_RESULT_HEAL,
			ACTION_RESULT_CRITICAL_HEAL,
			ACTION_RESULT_HOT_TICK,
			ACTION_RESULT_HOT_TICK_CRITICAL,
		}

		for i=1,#filters do
			self:RegisterEvent(EVENT_COMBAT_EVENT, onCombatEventHeal, REGISTER_FILTER_COMBAT_RESULT, filters[i], REGISTER_FILTER_IS_ERROR, false)
		end

		self:RegisterEvent(EVENT_COMBAT_EVENT, onCombatEventHealAbsorbed, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_HEAL_ABSORBED, REGISTER_FILTER_IS_ERROR, false)

		self.active = true
	end
)

local isFileInitialized = false

function libint.InitializeCombat()
	if isFileInitialized == true then return false end
	logger = lf.initSublogger("combat")

    isFileInitialized = true
	return true
end