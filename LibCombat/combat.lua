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
	[ACTION_RESULT_DAMAGE_SHIELDED]   = "shieldedHits",
	[ACTION_RESULT_HEAL]              = "normalHeal",
	[ACTION_RESULT_HOT_TICK]          = "normalHeal",
	[ACTION_RESULT_CRITICAL_HEAL]     = "criticalHeal",
	[ACTION_RESULT_HOT_TICK_CRITICAL] = "criticalHeal",
	[ACTION_RESULT_HEAL_ABSORBED]     = "absorbedHeal",
}

local amountResultKeys = {
	[ACTION_RESULT_DAMAGE]            = "normalDamage",
	[ACTION_RESULT_DOT_TICK]          = "normalDamage",
	[ACTION_RESULT_CRITICAL_DAMAGE]   = "criticalDamage",
	[ACTION_RESULT_DOT_TICK_CRITICAL] = "criticalDamage",
	[ACTION_RESULT_BLOCKED_DAMAGE]    = "blockedDamage",
	[ACTION_RESULT_DAMAGE_SHIELDED]   = "shieldedDamage",
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

local LogProcessorCombat = lf.LogProcessingHandler:New("combat", AllowedLogTypes)


function LogProcessorCombat:onInitilizeFight(fight)
	if self.active ~= true then return end

	fight.damageDone = {}
	fight.damageReceived = {}
	fight.healingDone = {}
	fight.healingReceived = {}

	fight.damageStats = {
		groupDamageOut = 0,			-- dmg from and to the group
		groupDamageIn = 0,			-- dmg from and to the group
		groupDamageShielded = 0,	-- dmg from and to the group
		damageOutTotal = 0,			-- total damage out
		damageInTotal = 0,			-- total damage in
		damageInShielded = 0,		-- total damage in shielded
	}
	fight.healStats = {
		healingOut = 0,				-- total healing out
		healingOutOver = 0,			-- total healing out including Overheal
		healingIn = 0,				-- total healing in
		groupHealingOut = 0,		-- heal of the group
		groupHealingIn = 0,			-- heal of the group
		groupHealingOver = 0,		-- total healing out including Overheal
	}
end

function LogProcessorCombat:onCombatStart() end
function LogProcessorCombat:onCombatEnd() end

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


local function InitUnitData(fight, data, unitId)
	fight:CheckUnit()

	local unitData = {}
	data[unitId] = unitData

	return unitData
end

local function GetUnitData(fight, data, unitIdSelf, unitIdOther)
	local unitDataSelf = data[unitIdSelf] or InitUnitData(fight, data, unitIdSelf)
	if unitDataSelf[unitIdOther] == nil then return InitUnitData(fight, unitDataSelf, unitIdOther) end

	return unitDataSelf[unitIdOther]
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
	}

	return abilityData
end

local function GetDamageAbilityData(fight, fightData, timems, unitIdSelf, unitIdOther, abilityId, damageType)
	local unit = GetUnitData(fight, fightData, unitIdSelf, unitIdOther)
	if unit[abilityId] == nil then unit[abilityId] = InitDamageAbilityData(timems, damageType) end
	return unit[abilityId]
end

local function UpdateDamageAbilityData(abilityData, timems, hitValue, overflow, result)
	local fullValue = hitValue + overflow

	local resultkey = amountResultKeys[result]
	local hitKey = countResultKeys[result]

	abilityData[resultkey] = abilityData[resultkey] + fullValue
	abilityData[hitKey] = abilityData[hitKey] + 1

	abilityData.max = zo_max(abilityData.max, fullValue)
	abilityData.min = zo_min(abilityData.min, fullValue)
	abilityData.endTime = timems

	-- IncrementStatSum(fight, damageType, resultkey, isDamageOut, hitValue, false, unit) TODO: Move to stat module
end

function LogProcessorCombat:ProcessLogLineDamage(fight, logType, timems, result, sourceUnitId, targetUnitId, abilityId, hitValue, damageType, overflow)
	-- if timems < (fight.combatstart-500) or fight.units[sourceUnitId] == nil or fight.units[targetUnitId] == nil then return end

	if fight.damageStats.startTime == nil then fight.damageStats.startTime = timems end
	fight.damageStats.endTime = timems

	if sourceUnitId and sourceUnitId > 0 then
		local sourceData = GetDamageAbilityData(fight, fight.damageDone, timems, sourceUnitId, targetUnitId or 0, abilityId, damageType)
		UpdateDamageAbilityData(sourceData, timems, hitValue, overflow, result)
	end

	if targetUnitId and targetUnitId > 0 then
		local targetData = GetDamageAbilityData(fight, fight.damageReceived, timems,  targetUnitId, sourceUnitId or 0, abilityId, damageType)
		UpdateDamageAbilityData(targetData, timems, hitValue, overflow, result)
	end
end

local function InitHealAbilityData(timems, powerType)
	local abilityData = {
		normalHealing   = 0,
		criticalHealing = 0,
		overflowHealing = 0,
		absorbedHealing = 0,
		totalHealing    = 0,
		normalHits      = 0,
		criticalHits    = 0,
		overflowHits    = 0,
		absorbedHits    = 0,
		totalHits       = 0,
		powerType       = powerType,
		startTime       = timems,
	}

	return abilityData
end

local function GetHealAbilityData(fight, fightData, timems, unitIdSelf, unitIdOther, abilityId, powerType)
	local unit = GetUnitData(fight, fightData, unitIdSelf, unitIdOther)
	if unit[abilityId] == nil then unit[abilityId] = InitHealAbilityData(timems, powerType) end
	return unit[abilityId]
end

local function UpdateHealAbilityData(abilityData, timems, hitValue, overflow, result)
	local resultkey = amountResultKeys[result]
	local hitKey = countResultKeys[result]

	abilityData[resultkey] = abilityData[resultkey] + hitValue
	abilityData[hitKey] = abilityData[hitKey] + 1

	abilityData.max = zo_max(abilityData.max, hitValue + overflow)
	abilityData.min = zo_min(abilityData.min, hitValue + overflow)
	abilityData.endTime = timems

	if overflow > 0 then -- shielded damage
		abilityData["overflowHealing"] = abilityData["overflowHealing"] + overflow
		abilityData["overflowHits"] = abilityData["overflowHits"] + 1
	end
	-- TODO: decide on handling overflow healing
	-- IncrementStatSum(fight, damageType, resultkey, isDamageOut, hitValue, false, unit) TODO: Move to stat module
end

function LogProcessorCombat:ProcessLogLineHeal(fight, logType, timems, result, sourceUnitId, targetUnitId, abilityId, hitValue, damageType, overflow)
	-- if timems < (fight.combatstart-500) or fight.units[sourceUnitId] == nil or fight.units[targetUnitId] == nil then return end

	if fight.healStats.startTime == nil then fight.healStats.startTime = timems end
	fight.healStats.endTime = timems

	if sourceUnitId and sourceUnitId > 0 then
		local sourceData = GetHealAbilityData(fight, fight.healingDone, sourceUnitId, targetUnitId or 0, abilityId, damageType)
		UpdateHealAbilityData(sourceData, timems, hitValue, overflow, result)
	end

	if targetUnitId and targetUnitId > 0 then
		local targetData = GetHealAbilityData(fight, fight.healingReceived, targetUnitId, sourceUnitId or 0, abilityId, damageType)
		UpdateHealAbilityData(targetData, timems, hitValue, overflow, result)
	end
end

-- Shield Buffers --

local DamageShieldBuffer = {}
libint.DamageShieldBuffer = DamageShieldBuffer

local HealAbsorbBuffer = {}
libint.HealAbsorbBuffer = HealAbsorbBuffer

local function CheckForShield(buffer, timems, sourceUnitId, targetUnitId)
	for i = #buffer, 1, -1 do
		local shieldTimems, shieldSourceUnitId, shieldTargetUnitId, shieldHitValue = unpack(buffer[i])

		logger:Verbose("Eval Shield Index %d: Source: %s, Target: %s, Time: %d", i, tostring(shieldSourceUnitId == sourceUnitId), tostring(shieldTargetUnitId == targetUnitId), timems - shieldTimems)
		if shieldSourceUnitId == sourceUnitId and shieldTargetUnitId == targetUnitId and timems - shieldTimems < 100 then
			table.remove(buffer, i)
			return shieldHitValue
		end
	end
end

--(eventCode, result, isError, abilityName, abilityGraphic, abilityActionSlotType, sourceName, sourceType, targetName, targetType, hitValue, powerType, damageType, log, sourceUnitId, targetUnitId, abilityId, overflow)

local function onCombatEventDamage(_, result, _, _, _, _, _, _, targetName, _, hitValue, _, damageType, _, sourceUnitId, targetUnitId, abilityId, overflow)  -- called by Event
	local timeMs = GetGameTimeMilliseconds()
	if hitValue > 200000 then logger:Warning("Big Damage Event: (%d) %s did %d damage to %d", abilityId, lib.GetFormattedAbilityName(abilityId), hitValue, tostring(targetName)) end
	
	local absorb = CheckForShield(DamageShieldBuffer, timeMs, sourceUnitId, targetUnitId) or 0
	if (hitValue + overflow + absorb) <= 0 then 
		logger:Debug("Empty Damage Event %s (%d) -> targetName", lib.GetFormattedAbilityName(abilityId), abilityId, tostring(targetName)) 
		return
	end

	if libint.currentfight.prepared ~= true then libint.currentfight:OnCombatStart() end	if absorb > 0 then 
		lib.cm:FireCallbacks((libint.callbackKeys[LIBCOMBAT_LOG_EVENT_DAMAGE]), LIBCOMBAT_LOG_EVENT_DAMAGE, timeMs, ACTION_RESULT_DAMAGE_SHIELDED, sourceUnitId, targetUnitId, abilityId, hitValue, damageType, 0)
	end
	lib.cm:FireCallbacks((libint.callbackKeys[LIBCOMBAT_LOG_EVENT_DAMAGE]), LIBCOMBAT_LOG_EVENT_DAMAGE, timeMs, result, sourceUnitId, targetUnitId, abilityId, hitValue, damageType, overflow)
end

local function onCombatEventHeal(_, result, _, _, _, _, _, _, targetName, _, hitValue, powerType, _, _, sourceUnitId, targetUnitId, abilityId, overflow)  -- called by Event
	local timeMs = GetGameTimeMilliseconds()
	local absorb = CheckForShield(HealAbsorbBuffer, timeMs, sourceUnitId, targetUnitId) or 0
	if (hitValue + overflow + absorb) <= 0 then
		logger:Debug("Empty Damage Event %s (%d) -> targetName", lib.GetFormattedAbilityName(abilityId), abilityId, tostring(targetName)) 
		return
	end

	if absorb > 0 then 
		lib.cm:FireCallbacks((libint.callbackKeys[LIBCOMBAT_LOG_EVENT_HEAL]), LIBCOMBAT_LOG_EVENT_HEAL, timeMs, ACTION_RESULT_HEAL_ABSORBED, sourceUnitId, targetUnitId, abilityId, absorb, powerType, 0)
	end
	lib.cm:FireCallbacks((libint.callbackKeys[LIBCOMBAT_LOG_EVENT_HEAL]), LIBCOMBAT_LOG_EVENT_HEAL, timeMs, result, sourceUnitId, targetUnitId, abilityId, hitValue, powerType, overflow)
end

local function onCombatEventDamageAbsorbed(_, result, _, _, _, _, _, _, _, _, hitValue, _, _, _, sourceUnitId, targetUnitId, _, overflow)
	if overflow and overflow > 0 then logger:Info("Overflow! Add %d (+%d) Shield: %d -> %d  (%d)", hitValue, overflow, sourceUnitId, targetUnitId, #DamageShieldBuffer) end
	DamageShieldBuffer[#DamageShieldBuffer + 1] = {GetGameTimeMilliseconds(), sourceUnitId, targetUnitId, hitValue}

	logger:Debug("Add %d Shield: %d -> %d  (%d)", hitValue, sourceUnitId, targetUnitId, #DamageShieldBuffer)
end

local function onCombatEventHealAbsorbed(_, result, _, _, _, _, _, _, _, _, hitValue, _, _, _, sourceUnitId, targetUnitId, _, overflow)
	if overflow and overflow > 0 then logger:Info("Overflow! Add %d (+%d) Heal Absorption: %d -> %d  (%d)", hitValue, overflow, sourceUnitId, targetUnitId, #HealAbsorbBuffer) end
	HealAbsorbBuffer[#HealAbsorbBuffer + 1] = {GetGameTimeMilliseconds(), sourceUnitId, targetUnitId, hitValue}

	logger:Debug("Add %d Shield: %d -> %d  (%d)", hitValue, sourceUnitId, targetUnitId, #HealAbsorbBuffer)
end


--(eventCode, result, isError, abilityName, abilityGraphic, abilityActionSlotType, sourceName, sourceType, targetName, targetType, hitValue, powerType, damageType, log, sourceUnitId, targetUnitId, abilityId, overflow)


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

function lib.InitializeCombat()
	if isFileInitialized == true then return false end
	logger = lf.initSublogger("combat")

    isFileInitialized = true
	return true
end