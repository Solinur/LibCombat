-- This file provides combat log entries regarding buffs and debuffs

local lib = LibCombat
local libint = lib.internal
local ld = libint.data
local libunits = ld.units
local logger
local EffectKey = libint.callbackKeys[LIBCOMBAT_LOG_EVENT_EFFECT]
local lf = libint.functions
local unitData = {}
local abilityIdZen = libint.abilityIdZen
local abilityIdForceOfNature = libint.abilityIdForceOfNature


libint.badAbility = {
	[51487] = true, -- Shehai Shockwave
	[20546] = true, -- Prioritize Hit
	[69168] = true, -- Purifying Light Heal FX
	[52515] = true, -- Grand Healing Fx
	[61898] = true, -- Minor Savagery, too spammy
	[63601] = true, -- ESO Plus
}

libint.specialBuffs = {	-- buffs that the API doesn't show via EVENT_EFFECT_CHANGED and need to be specially tracked via EVENT_COMBAT_EVENT
	21230,	-- Weapon/spell power enchant (Berserker)
	21578,	-- Damage shield enchant (Hardening)
	71067,	-- Trial By Fire: Shock
	71058,	-- Trial By Fire: Fire
	71019,	-- Trial By Fire: Frost
	71069,	-- Trial By Fire: Disease
	71072,	-- Trial By Fire: Poison
	49236,	-- Whitestrake's Retribution
	57170,	-- Blood Frenzy
	75726,	-- Tava's Favor
	75746,	-- Clever Alchemist
	61870,	-- Armor Master Resistance
	71107,	-- Briarheart
	122729,	-- Seething Fury Stat Buff
}


libint.specialDebuffs = {   -- debuffs that the API doesn't show via EVENT_EFFECT_CHANGED and need to be specially tracked via EVENT_COMBAT_EVENT
	95136,   -- Chilled (used for tracking Warden crit damage buff)
	178118,  -- Status Effect Magic (Overcharged)
	95136,   -- Status Effect Frost (Chill, used for tracking Warden crit damage buff)
	95134,   -- Status Effect Lightning (Concussion)
	178123,  -- Status Effect Physical (Sundered)
	178127,  -- Status Effect Foulness (Diseased)
	148801,  -- Status Effect Bleeding (Hemorrhaging)
}

libint.StatusEffectIds = {
	[178118] = true, -- Magic (Overcharged)
	[18084]  = true, -- Fire (Burning)
	[95136]  = true, -- Frost (Chill)
	[95134]  = true, -- Lightning (Concussion)
	[178123] = true, -- Physical (Sundered)
	[21929]  = true, -- Poison (Poisoned)
	[178127] = true, -- Foulness (Diseased)
	[148801] = true, -- Bleeding (Hemorrhaging)
}

libint.sourceBuggedBuffs = {   -- buffs where ZOS messed up the source, causing CMX to falsely not track them
	88401,  -- Minor Magickasteal
}


local function InitUnitData(fight, unitId)
	fight:CheckUnit(unitId)

	local unitData = {}
	fight.effects[unitId] = unitData

	return unitData
end

local function GetUnitData(fight, unitId)
	return fight.effects[unitId] or InitUnitData(fight, unitId)
end

local function InitEffectdata(unitData, abilityId, effectType)
	local effectData = {
		name = lib.GetFormattedAbilityName(abilityId),
		iconId = abilityId,
		uptime = 0,						-- uptime of effect caused by player
		count = 0,						-- count of effect applications caused by player
		groupUptime = 0,				-- uptime of effect caused by the whole group
		groupCount = 0,					-- count of effect applications caused by the whole group
		effectType = effectType,		-- buff or debuff
		maxStacks = 0,					-- stacks = 0 if the effect wasn't tracked trough EVENT_EFFECT_CHANGED
		firstStartTime = nil,			-- temp variable to track when uptime for a buff initially started
		firstGroupStartTime = nil,		-- temp variable to track when uptime for a buff from the group initially started
		slots = {},						-- slotid is unique for each application, this is the temporary place to track them
		stacks = {}						-- tracking applied stacks
	}
	
	unitData[abilityId] = effectData
	return effectData
end

local function InitStackData(effectData, stacks)
	local stackData = {
		uptime = 0,			-- uptime of effect caused by player
		count = 0,			-- count of effect applications caused by player
		groupUptime = 0,	-- uptime of effect caused by the whole group
		groupCount = 0,		-- count of effect applications caused by the whole group}
	}

	effectData[stacks] = stackData
	return stackData
end

local function GetEffectData(fight, unitId, abilityId, effectType)
	local unitData = GetUnitData(fight, unitId)
	local effectData = unitData[abilityId] or InitEffectdata(unitData, abilityId, effectType)

	return effectData
end

-- Log Handling -- 
local LogProcessorEffects = lf.LogProcessingHandler:New("effects", LIBCOMBAT_LOG_EVENT_EFFECT)

function LogProcessorEffects:onInitilizeFight(fight)
	if self.active ~= true then return end

	fight.effects = {}

	--TODO: Import handover effects, refresh group member buffs using unitTag?
	local timems = GetGameTimeMilliseconds()
	self:GetPlayerBuffs(timems, fight)
end

function LogProcessorEffects:GetPlayerBuffs(timems, fight)
	if libint.Events.Effects.active == false then return end
	
	local playerId = fight.units.player
	local effects = fight.effects

	for i=1,GetNumBuffs("player") do
		-- buffName, timeStarted, timeEnding, effectSlot, stackCount, iconFilename, buffType, effectType, abilityType, statusEffectType, abilityId, canClickOff, castByPlayer
		local _, _, endTime, effectSlot, stackCount, _, _, effectType, abilityType, _, abilityId, _, castByPlayer = GetUnitBuffInfo("player",i)
		logger:Verbose("player has the %s %d x %s (%d, ET: %d, self: %s)", effectType == BUFF_EFFECT_TYPE_BUFF and "buff" or "debuff", stackCount, lib.GetFormattedAbilityName(abilityId), abilityId, abilityType, tostring(castByPlayer))

		local effectData = GetEffectData(effects, playerId, abilityId, effectType)
		if effectData.slots[effectSlot] then return end

		local sourceType = castByPlayer and COMBAT_UNIT_TYPE_PLAYER or COMBAT_UNIT_TYPE_NONE
		local stacks = zo_max(stackCount, 1)

		if (not libint.badAbility[abilityId]) then
			self:ProcessLogLineEffects(fight, LIBCOMBAT_LOG_EVENT_EFFECT, timems, playerId, abilityId, EFFECT_RESULT_GAINED, effectType, stacks, sourceType, effectSlot)
		end

		if abilityId ==	13984 then lf.GetShadowBonus(effectSlot) end
		if abilityId ==	51176 then lf.onTFSChanged(_, EFFECT_RESULT_GAINED, _, _, _, _, _, stackCount) end -- TFS workaround
	end
end

function LogProcessorEffects:onCombatStart()
end

function LogProcessorEffects:onCombatEnd()
	--TODO: Truncate and hand over running buffs.
end

local function CountSlots(slots)
	local slotcount = 0
	local groupSlotCount = 0

	for _, slotData in pairs(slots) do
		if slotData.isPlayerSource then slotcount = slotcount + 1 end
		groupSlotCount = groupSlotCount + 1
	end
	
	return slotcount, groupSlotCount
end

function LogProcessorEffects:ProcessLogLineEffects(fight, logType, timems, unitId, abilityId, changeType, effectType, stacks, sourceType, slotId)
	-- if timems < (fight.combatstart - 500) or fight.units[unitId] == nil then return end
	-- TODO: handle processing before combatstart 
	
	local currentstacks = stacks or 0
	local effectData = GetEffectData(fight, unitId, abilityId, effectType)
	effectData.maxStacks = zo_max(stacks, effectData.maxStacks)

	local isPlayerSource = sourceType == COMBAT_UNIT_TYPE_PLAYER or sourceType == COMBAT_UNIT_TYPE_PLAYER_PET

	local slots = effectData.slots
	local slotcount, groupSlotCount = CountSlots(slots)
	local slotdata = slots[slotId]

	if (changeType == EFFECT_RESULT_GAINED or changeType == EFFECT_RESULT_UPDATED) and timems < fight.endtime then
		local starttime = zo_max(timems, fight.starttime)

		if slotcount == 0 and isPlayerSource then effectData.firstStartTime = starttime end
		if groupSlotCount == 0 then effectData.firstGroupStartTime = starttime end

		if slotdata == nil then
			slotdata = {isPlayerSource = isPlayerSource, abilityId = abilityId,}
			slots[slotId] = slotdata
		end

		local minStacks = abilityId == abilityIdZen and 0 or 1
		for stacks = minStacks, currentstacks do
			if slotdata[stacks] == nil then
				slotdata[stacks] = starttime
				effectData:CheckInstance(abilityId, stacks)
			end
		end

		for stacks, starttime in pairs(slotdata) do
			if type(stacks) == "number" and stacks > currentstacks then
				local stackData = effectData[stacks] or InitStackData(effectData, stacks)
				local duration = zo_min(timems, fight.endtime) - starttime

				if isPlayerSource then
					stackData.uptime = stackData.uptime + duration
					stackData.count = stackData.count + 1
				end

				stackData.groupUptime = stackData.groupUptime + duration
				stackData.groupCount = stackData.groupCount + 1
				slotdata[stacks] = nil
			end
		end

	elseif changeType == EFFECT_RESULT_FADED then
		slots[slotId] = nil

		if slotdata and timems > fight.starttime then
			if slotdata.isPlayerSource then slotcount = slotcount - 1 end
			groupSlotCount = groupSlotCount - 1

			slotdata.isPlayerSource = nil	-- remove, so the loop gets only stackData
			slotdata.abilityId = nil

			for stacks, starttime in pairs(slotdata) do
				local stackData = effectData[stacks] or InitStackData(effectData, stacks)
				local duration = zo_min(timems, fight.endtime) - starttime

				if isPlayerSource then
					stackData.uptime = stackData.uptime + duration
					stackData.count = stackData.count + 1
				end

				stackData.groupUptime = stackData.groupUptime + duration
				stackData.groupCount = stackData.groupCount + 1
			end

			if slotcount == 0 and effectData.firstStartTime then
				local duration = zo_min(timems, fight.endtime) - effectData.firstStartTime
				effectData.uptime = effectData.uptime + duration
				effectData.count = effectData.count + 1
				effectData.firstStartTime = nil
			end

			if groupSlotCount == 0 and effectData.firstGroupStartTime then
				local duration = zo_min(timems,fight.endtime) - effectData.firstGroupStartTime
				effectData.groupUptime = effectData.groupUptime + duration
				effectData.groupCount = effectData.groupCount + 1
				effectData.firstGroupStartTime = nil
			end
		end
	end

	-- unit:UpdateStats(fight, effectData, abilityId, hitValue) -- TODO: Setup when stats module works
end


---[[ TODO: implement Z'en and FoN tracking on analysis side
local function InitLocalUnitData(unitId)
	local unit = {
		stacksOfZen = 0,
		forceOfNatureStacks = 0,
		forceOfNature = {},
	}
	unitData[unitId] = unit
	return unit
end


local function UpdateZenData(timeMs, unitId, abilityId, changeType, effectType, sourceType, effectSlot)
	local unit = unitData[unitId] or InitLocalUnitData(unitId)

	if abilityId == abilityIdZen then
		local isActive = changeType == EFFECT_RESULT_GAINED -- or (changeType == EFFECT_RESULT_UPDATED)
		local stacks = isActive and zo_min(unit.stacksOfZen, 5) or 0

		libint.cm:FireCallbacks(EffectKey, LIBCOMBAT_LOG_EVENT_EFFECT, timeMs, unitId, abilityIdZen, changeType, effectType, stacks, sourceType, effectSlot)	-- stack count is 1 to 6, with 1 meaning 0% bonus, and 6 meaning 5% bonus from Z'en
		logger:Debug("VERBOSE", table.concat({timeMs, unitId, abilityIdZen, changeType, effectType, stacks, sourceType, effectSlot}, ", "))
		unit.zenEffectSlot = (isActive and effectSlot) or nil
	else
		if changeType == EFFECT_RESULT_GAINED then
			unit.stacksOfZen = unit.stacksOfZen + 1
		elseif changeType == EFFECT_RESULT_FADED then
			if unit.stacksOfZen - 1 < 0 then logger:Debug("WARNING", "Encountered negative Z'en stacks: %s (%d)", lib.GetFormattedAbilityName(abilityId), abilityId) end
			unit.stacksOfZen = zo_max(0, unit.stacksOfZen - 1)
		end

		if unit.zenEffectSlot then
			local stacks = zo_min(unit.stacksOfZen, 5)
			libint.cm:FireCallbacks(EffectKey, LIBCOMBAT_LOG_EVENT_EFFECT, timeMs, unitId, abilityIdZen, EFFECT_RESULT_UPDATED, effectType, stacks, sourceType, unit.zenEffectSlot)
		end
	end
end

function UpdateForceOfNatureData(_, _, timeMs, unitId, abilityId, changeType, _, _, _, _)
	local unit = unitData[unitId] or InitLocalUnitData(unitId)
	if libint.StatusEffectIds[abilityId] == nil or libint.currentFight.CP[1]["slotted"] == nil or libint.currentFight.CP[1]["slotted"][276] ~= true then return end

	local forceOfNatureChangeType = EFFECT_RESULT_UPDATED
	local debugChangeType = "o"

	if changeType == EFFECT_RESULT_GAINED and unit.forceOfNature[abilityId] == nil then
		unit.forceOfNature[abilityId] = true
		unit.forceOfNatureStacks = unit.forceOfNatureStacks + 1
		debugChangeType = "+"

		if unit.forceOfNatureStacks == 1 then forceOfNatureChangeType = EFFECT_RESULT_GAINED end
		if unit.forceOfNatureStacks > 8 then logger:Debug("WARNING", "Encountered too many Force of Nature stacks (%d): %s (%d)", unit.forceOfNatureStacks, lib.GetFormattedAbilityName(abilityId), abilityId) end
	elseif changeType == EFFECT_RESULT_FADED and unit.forceOfNature[abilityId] == true then
		unit.forceOfNature[abilityId] = nil
		debugChangeType = "-"

		if unit.forceOfNatureStacks == 0 then forceOfNatureChangeType = EFFECT_RESULT_FADED end
		if unit.forceOfNatureStacks - 1 < 0 then logger:Debug("WARNING", "Encountered negative Force of Nature stacks: %s (%d)", lib.GetFormattedAbilityName(abilityId), abilityId) end

		unit.forceOfNatureStacks = zo_max(0, unit.forceOfNatureStacks - 1)
	end

	local stacks = zo_min(unit.forceOfNatureStacks, 8)
	libint.cm:FireCallbacks(EffectKey, LIBCOMBAT_LOG_EVENT_EFFECT, timeMs, unitId, abilityIdForceOfNature, forceOfNatureChangeType, BUFF_EFFECT_TYPE_DEBUFF, stacks, COMBAT_UNIT_TYPE_PLAYER, 0)
	logger:Debug("VERBOSE", "Force of Nature: %s (%d) x%d, %s%s", unit.name, unit.unitId, stacks, lib.GetFormattedAbilityName(abilityId), debugChangeType)
end

-- TODO: use units module to get the unit directly
local function isDuplicateUnit(unitTag)
	if unitTag and zo_strsub(unitTag, 1, 5) == "group" and AreUnitsEqual(unitTag, "player") then return true end
	if unitTag and zo_strsub(unitTag, 1, 11) ~= "reticleover" then
		if AreUnitsEqual(unitTag, "reticleover") then return true end	-- TODO: maybe ignore those unitTags instead? 
		if AreUnitsEqual(unitTag, "reticleoverplayer") then return true end
		if AreUnitsEqual(unitTag, "reticleovertarget") then return true end
	end
	return false
end

local function validateBuffEventValues(changeType, stackCount)
	if changeType == EFFECT_RESULT_GAINED then return true end
	if changeType == EFFECT_RESULT_FADED then return true end
	if changeType == EFFECT_RESULT_UPDATED and stackCount > 1 then return true end
	return false
end

local function BuffEventHandler(isspecial, changeType, effectSlot, _, unitTag, _, endTime, stackCount, _, _, effectType, abilityType, _, unitName, unitId, abilityId, sourceType)
	if unitName == "Offline" or unitId == nil then return end -- TODO: Use unit module here? 
	if not validateBuffEventValues(changeType, stackCount) then return end
	if libint.badAbility[abilityId] == true then return end
	if isDuplicateUnit(unitTag) then return end
	if libint.sourceBuggedBuffs[abilityId] then sourceType = COMBAT_UNIT_TYPE_GROUP end

	local timems = GetGameTimeMilliseconds()
	local stacks = zo_max(1, stackCount)
	logger:Verbose("%s %s the %s %dx %s (%d, ET: %d, %s, %d)", unitName, changeType, effectType == BUFF_EFFECT_TYPE_BUFF and "buff" or "debuff", stackCount, lib.GetFormattedAbilityName(abilityId), abilityId, abilityType, unitTag, sourceType)

	-- if lib.IsPlayerUnitId(unitId) then libint.currentFight:QueueStatUpdate(timems) end -- TODO: move to stats

	if sourceType == COMBAT_UNIT_TYPE_PLAYER and (abilityId == abilityIdZen or abilityType == ABILITY_TYPE_DAMAGE) then
		UpdateZenData(timems, unitId, abilityId, changeType, effectType, sourceType, effectSlot)
	end

	if libint.StatusEffectIds[abilityId] then 
		logger:Info("unitData", unitData)
		logger:Info("[unitId]", unitData[unitId])
		logger:Info(".forceOfNature", unitData[unitId].forceOfNature)
		logger:Info("libint.SpecialDebuffs[abilityId]", libint.SpecialDebuffs[abilityId])
		if (sourceType == COMBAT_UNIT_TYPE_PLAYER or (unitName == "" and unitData[unitId] and unitData[unitId].forceOfNature[abilityId] and libint.SpecialDebuffs[abilityId])) then
			UpdateForceOfNatureData(EffectKey, LIBCOMBAT_LOG_EVENT_EFFECT, timems, unitId, abilityId, changeType, effectType, stacks, sourceType, effectSlot) 
		end
	end

	libint.cm:FireCallbacks(EffectKey, LIBCOMBAT_LOG_EVENT_EFFECT, timems, unitId, abilityId, changeType, effectType, stacks, sourceType, effectSlot)
end

local function onEffectChanged(_, ...)
	BuffEventHandler(false, ...)		-- (isspecial, groupeffect, ...)
end


local resultToChangeType = {
	[ACTION_RESULT_EFFECT_GAINED_DURATION] = EFFECT_RESULT_GAINED,
	[ACTION_RESULT_EFFECT_FADED] = EFFECT_RESULT_FADED,
	[ACTION_RESULT_EFFECT_GAINED] = EFFECT_RESULT_UPDATED,
}

local DurationCache = {}
local function SpecialBuffEventHandler(isdebuff, result, _, _, _, _, _, sourceType, targetName, _, hitValue, _, _, _, _, targetUnitId, abilityId)
	--(eventCode, result, isError, abilityName, abilityGraphic, abilityActionSlotType, sourceName, sourceType, targetName, targetType, hitValue, powerType, damageType, log, sourceUnitId, targetUnitId, abilityId)
	local now = GetGameTimeSeconds()

	if libint.badAbility[abilityId] == true or (result == ACTION_RESULT_EFFECT_GAINED and hitValue < 2) then return end

	if result == ACTION_RESULT_EFFECT_GAINED_DURATION then
		DurationCache[abilityId] = hitValue
	elseif DurationCache[abilityId] == nil and result == ACTION_RESULT_EFFECT_FADED then
		DurationCache[abilityId] = hitValue
	end

	local stackCount = 1
	local duration = hitValue

	if result == ACTION_RESULT_EFFECT_GAINED then
		if DurationCache[abilityId] then
			duration = DurationCache[abilityId]
			stackCount = hitValue
		else return end
	end

	-- if unitName ~= ld.units.rawPlayername then return end

	local changeType = resultToChangeType[result] or nil
	-- logger:Info("%s (%d): %d (%d)", GetFormattedAbilityName(abilityId), abilityId, changeType, result)

	local effectType = isdebuff and BUFF_EFFECT_TYPE_DEBUFF or BUFF_EFFECT_TYPE_BUFF
	local endTime = now + duration/1000
	local unitTag = libint.currentFight.units and libint.currentFight.units[targetUnitId] and libint.currentFight.units[targetUnitId].unitTag or nil

	BuffEventHandler(true, changeType, targetUnitId, _, unitTag, _, endTime, stackCount, _, _, effectType, ABILITY_TYPE_BONUS, _, targetName, targetUnitId, abilityId, sourceType)
end

local function onSpecialBuffEvent(_, ...)
	SpecialBuffEventHandler(false, ...)		-- (isdebuff, ...)
end

local function onSpecialDebuffEvent(_, ...)
	SpecialBuffEventHandler(true, ...)		-- (isdebuff, ...)
end



libint.Events.Effects = libint.EventHandler:New(
	{LIBCOMBAT_LOG_EVENT_EFFECT},
	function (self)
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onEffectChanged, REGISTER_FILTER_IS_ERROR, false)

		for i=1,#libint.specialBuffs do
			self:RegisterEvent(EVENT_COMBAT_EVENT, onSpecialBuffEvent, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_EFFECT_GAINED_DURATION, REGISTER_FILTER_ABILITY_ID, libint.specialBuffs[i], REGISTER_FILTER_IS_ERROR, false)
			self:RegisterEvent(EVENT_COMBAT_EVENT, onSpecialBuffEvent, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_EFFECT_FADED, REGISTER_FILTER_ABILITY_ID, libint.specialBuffs[i], REGISTER_FILTER_IS_ERROR, false)
		end

		for i=1,#libint.specialDebuffs do
			self:RegisterEvent(EVENT_COMBAT_EVENT, onSpecialDebuffEvent, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_EFFECT_GAINED_DURATION, REGISTER_FILTER_ABILITY_ID, libint.specialDebuffs[i], REGISTER_FILTER_IS_ERROR, false)
			self:RegisterEvent(EVENT_COMBAT_EVENT, onSpecialDebuffEvent, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_EFFECT_FADED, REGISTER_FILTER_ABILITY_ID, libint.specialDebuffs[i], REGISTER_FILTER_IS_ERROR, false)
		end
		
		self.active = true
	end
)


local isFileInitialized = false

function lib.InitializeEffects()
	if isFileInitialized == true then return false end
	logger = lf.initSublogger("effects")

    isFileInitialized = true
	return true
end