-- This file provides combat log entries regarding buffs and debuffs

local lib = LibCombat
local libint = lib.internal
local libdata = libint.data
local Print = libint.Print
local CallbackKeys = libint.callbackKeys

libint.badAbility = {
	[51487] = true,
	[20546] = true,
	[69168] = true,
	[52515] = true,
	[41189] = true,
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

	95136,  -- Chilled (used for tracking Warden crit damage buff)
	178118,	-- Status Effect Magic (Overcharged)
	95136,  -- Status Effect Frost (Chill, used for tracking Warden crit damage buff)
	95134,  -- Status Effect Lightning (Concussion)
	178123,  -- Status Effect Physical (Sundered)
	178127,  -- Status Effect Foulness (Diseased)
	148801,  -- Status Effect Bleeding (Hemorrhaging)

}

libint.statusEffectIds = {

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

-- EffectBuffer --

local EffectBuffer = {}
libint.EffectBuffer = EffectBuffer

local GROUP_EFFECT_NONE = 0
local GROUP_EFFECT_IN = 1
local GROUP_EFFECT_OUT = 2

function libint.PurgeEffectBuffer(timems)

	for id, unit in pairs(EffectBuffer) do

		for _, data in pairs(unit) do

			local timeend = data[1]

			if timems/1000 > timeend then unit[id] = nil end

		end
	end
end

local lastPurge = 0

local function AddtoEffectBuffer(endTime, abilityType, eventid, timems, unitId, abilityId, ...)

	local data = {endTime, {eventid, timems, unitId, abilityId, ...}, abilityType}

	local unit = EffectBuffer[unitId]

	if unit == nil then

		EffectBuffer[unitId] = {[abilityId] = data}

	else

		unit[abilityId] = data

	end

	if timems - lastPurge > 1000 then

		libint.PurgeEffectBuffer(timems)
		lastPurge = timems

	end
end

local function onTrialDummy(_, _, _, _, _, _, _, _, _, _, _, _, _, _, sourceUnitId, _, _, _)

	-- Print("dev","INFO", "Trial Dummy Detected: %s (%d)", sourceName, sourceUnitId)

	if not libint.currentfight.prepared then return end

	local unit = libint.currentfight.units[sourceUnitId]

	if unit then unit.isTrialDummy = true end

end

local function BuffEventHandler(isspecial, groupeffect, _, changeType, effectSlot, _, unitTag, _, endTime, stackCount, _, _, effectType, abilityType, _, unitName, unitId, abilityId, sourceType)

	if (changeType ~= EFFECT_RESULT_GAINED and changeType ~= EFFECT_RESULT_FADED and not (changeType == EFFECT_RESULT_UPDATED and stackCount > 1)) or unitName == "Offline" or unitId == nil then return end

	Print("events","VERBOSE", "%s %s the %s %dx %s (%d, ET: %d, %s, %d)", unitName, changeType, effectType == BUFF_EFFECT_TYPE_BUFF and "buff" or "debuff", stackCount, lib.GetFormattedAbilityName(abilityId), abilityId, abilityType, unitTag, sourceType)

	if libint.badAbility[abilityId] == true then return end

	local isGroup = unitTag and string.sub(unitTag, 1, 5) == "group"

	if isGroup and AreUnitsEqual(unitTag, "player") then return end
	if unitTag and string.sub(unitTag, 1, 11) ~= "reticleover" and (AreUnitsEqual(unitTag, "reticleover") or AreUnitsEqual(unitTag, "reticleoverplayer") or AreUnitsEqual(unitTag, "reticleovertarget")) then return end

	local timems = GetGameTimeMilliseconds()

	local eventid = groupeffect == GROUP_EFFECT_IN and LIBCOMBAT_EVENT_GROUPEFFECTS_IN or groupeffect == GROUP_EFFECT_OUT and LIBCOMBAT_EVENT_GROUPEFFECTS_OUT or unitTag and string.sub(unitTag, 1, 6) == "player" and LIBCOMBAT_EVENT_EFFECTS_IN or LIBCOMBAT_EVENT_EFFECTS_OUT
	local stacks = zo_max(1, stackCount)

	local inCombat = libint.currentfight.prepared

	if inCombat ~= true and unitTag ~= "player" and (changeType == EFFECT_RESULT_GAINED or changeType == EFFECT_RESULT_UPDATED) then

		AddtoEffectBuffer(endTime, abilityType, eventid, timems, unitId, abilityId, changeType, effectType, stacks, sourceType, effectSlot)
		return

	elseif inCombat == true then

		local unit = libint.currentfight.units[unitId]

		if unitTag == "player" or unitId == libdata.units.playerId then libint.currentfight:QueueStatUpdate(timems) end
		if sourceType ~= COMBAT_UNIT_TYPE_PLAYER or abilityId ~= libint.abilityIdZen then lib.cm:FireCallbacks((CallbackKeys[eventid]), eventid, timems, unitId, abilityId, changeType, effectType, stacks, sourceType, effectSlot) end

		if unit then

			unit.starttime = unit.starttime or timems
			unit.endtime = timems

			if sourceType == COMBAT_UNIT_TYPE_PLAYER and (abilityId == libint.abilityIdZen or abilityType == ABILITY_TYPE_DAMAGE) then unit:UpdateZenData((CallbackKeys[eventid]), eventid, timems, unitId, abilityId, changeType, effectType, stacks, sourceType, effectSlot, abilityType) end
			if libint.StatusEffectIds[abilityId] and (sourceType == COMBAT_UNIT_TYPE_PLAYER or (unitName == "" and unit.forceOfNature[abilityId] and libint.SpecialDebuffs[abilityId])) then unit:UpdateForceOfNatureData((CallbackKeys[eventid]), eventid, timems, unitId, abilityId, changeType, effectType, stacks, sourceType, effectSlot) end

		end

		lib.cm:FireCallbacks((CallbackKeys[eventid]), eventid, timems, unitId, abilityId, changeType, effectType, stacks, sourceType, effectSlot)

	end
end

local function onEffectChanged(...)
	BuffEventHandler(false, GROUP_EFFECT_NONE, ...)		-- (isspecial, groupeffect, ...)
end

local function onGroupEffectOut(...)
	BuffEventHandler(false, GROUP_EFFECT_OUT, ...)		-- (isspecial, groupeffect, ...)
end

local function onGroupEffectIn(...)
	BuffEventHandler(false, GROUP_EFFECT_IN, ...)		-- (isspecial, groupeffect, ...)
end

local function onSourceBuggedEffectChanged(eventCode, changeType, effectSlot, effectName, unitTag, beginTime, endTime, stackCount, iconName, buffType, effectType, abilityType, statusEffectType, unitName, unitId, abilityId, _)
	BuffEventHandler(false, GROUP_EFFECT_OUT, eventCode, changeType, effectSlot, effectName, unitTag, beginTime, endTime, stackCount, iconName, buffType, effectType, abilityType, statusEffectType, unitName, unitId, abilityId, COMBAT_UNIT_TYPE_GROUP)
end

local resultTochangeType = {

	[ACTION_RESULT_EFFECT_GAINED_DURATION] = EFFECT_RESULT_GAINED,
	[ACTION_RESULT_EFFECT_FADED] = EFFECT_RESULT_FADED,
	[ACTION_RESULT_EFFECT_GAINED] = EFFECT_RESULT_UPDATED,
}

local DurationCache = {}

local function SpecialBuffEventHandler(isdebuff, _, result, _, _, _, _, sourceName, sourceType, targetName, targetType, hitValue, _, damageType, _, sourceUnitId, targetUnitId, abilityId)
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

	-- if unitName ~= data.units.rawPlayername then return end

	local changeType = resultTochangeType[result] or nil
	-- Print("debug","INFO", "%s (%d): %d (%d)", GetFormattedAbilityName(abilityId), abilityId, changeType, result)

	local effectType = isdebuff and BUFF_EFFECT_TYPE_DEBUFF or BUFF_EFFECT_TYPE_BUFF

	local endTime = now + duration/1000

	local unitTag = libint.currentfight.units and libint.currentfight.units[targetUnitId] and libint.currentfight.units[targetUnitId].unitTag or nil

	BuffEventHandler(true, GROUP_EFFECT_NONE, _, changeType, 0, _, unitTag, _, endTime, stackCount, _, _, effectType, ABILITY_TYPE_BONUS, _, targetName, targetUnitId, abilityId, sourceType)

end

local function onSpecialBuffEvent(...)
	SpecialBuffEventHandler(false, ...)		-- (isdebuff, ...)
end

local function onSpecialDebuffEvent(...)
	SpecialBuffEventHandler(true, ...)		-- (isdebuff, ...)
end

--[[ TODO: implement Z'en and FoN tracking on analysis side

function UnitHandler:UpdateZenData(callbackKeys, eventid, timeMs, unitId, abilityId, changeType, effectType, _, sourceType, effectSlot, abilityType)

	if abilityId == libint.abilityIdZen then

		local isActive = changeType == EFFECT_RESULT_GAINED -- or (changeType == EFFECT_RESULT_UPDATED)
		local stacks = isActive and zo_min(self.stacksOfZen, 5) or 0

		lib.cm:FireCallbacks(callbackKeys, eventid, timeMs, unitId, libint.abilityIdZen, changeType, effectType, stacks, sourceType, effectSlot)	-- stack count is 1 to 6, with 1 meaning 0% bonus, and 6 meaning 5% bonus from Z'en
		Print("debug", "VERBOSE", table.concat({eventid, timeMs, unitId, libint.abilityIdZen, changeType, effectType, stacks, sourceType, effectSlot}, ", "))
		self.zenEffectSlot = (isActive and effectSlot) or nil

	elseif abilityType == ABILITY_TYPE_DAMAGE then

		if changeType == EFFECT_RESULT_GAINED then

			self.stacksOfZen = self.stacksOfZen + 1

		elseif changeType == EFFECT_RESULT_FADED then

			if self.stacksOfZen - 1 < 0 then Print("debug", "WARNING", "Encountered negative Z'en stacks: %s (%d)", GetFormattedAbilityName(abilityId), abilityId) end
			self.stacksOfZen = zo_max(0, self.stacksOfZen - 1)

		end

		if self.zenEffectSlot then

			local stacks = zo_min(self.stacksOfZen, 5)
			lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_EFFECTS_OUT]), LIBCOMBAT_EVENT_EFFECTS_OUT, timeMs, unitId, libint.abilityIdZen, EFFECT_RESULT_UPDATED, effectType, stacks, sourceType, self.zenEffectSlot)

		end
	end
end

function UnitHandler:UpdateForceOfNatureData(_, _, timeMs, unitId, abilityId, changeType, _, _, _, _)

	if libint.StatusEffectIds[abilityId] == nil or libint.currentfight.CP[1]["slotted"] == nil or libint.currentfight.CP[1]["slotted"][276] ~= true then return end

	local forceOfNatureChangeType = EFFECT_RESULT_UPDATED

	local debugChangeType = "o"

	if changeType == EFFECT_RESULT_GAINED and self.forceOfNature[abilityId] == nil then

		self.forceOfNature[abilityId] = true

		self.forceOfNatureStacks = self.forceOfNatureStacks + 1

		if self.forceOfNatureStacks == 1 then forceOfNatureChangeType = EFFECT_RESULT_GAINED end
		if self.forceOfNatureStacks > 8 then Print("debug", "WARNING", "Encountered too many Force of Nature stacks (%d): %s (%d)", self.forceOfNatureStacks, GetFormattedAbilityName(abilityId), abilityId) end
		debugChangeType = "+"

	elseif changeType == EFFECT_RESULT_FADED and self.forceOfNature[abilityId] == true then

		self.forceOfNature[abilityId] = nil

		if self.forceOfNatureStacks == 0 then forceOfNatureChangeType = EFFECT_RESULT_FADED end
		if self.forceOfNatureStacks - 1 < 0 then Print("debug", "WARNING", "Encountered negative Force of Nature stacks: %s (%d)", GetFormattedAbilityName(abilityId), abilityId) end

		self.forceOfNatureStacks = zo_max(0, self.forceOfNatureStacks - 1)
		debugChangeType = "-"

	end

	local stacks = zo_min(self.forceOfNatureStacks, 8)
	lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_EFFECTS_OUT]), LIBCOMBAT_EVENT_EFFECTS_OUT, timeMs, unitId, libint.abilityIdForceOfNature, forceOfNatureChangeType, BUFF_EFFECT_TYPE_DEBUFF, stacks, COMBAT_UNIT_TYPE_PLAYER, 0)
	Print("debug", "VERBOSE", "Force of Nature: %s (%d) x%d, %s%s", self.name, self.unitId, stacks, GetFormattedAbilityName(abilityId), debugChangeType)
end
	
--]]

libint.Events.Effects = libint.EventHandler:New(
	{LIBCOMBAT_EVENT_EFFECTS_IN,LIBCOMBAT_EVENT_EFFECTS_OUT,LIBCOMBAT_EVENT_GROUPEFFECTS_IN,LIBCOMBAT_EVENT_GROUPEFFECTS_OUT},
	function (self)
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onEffectChanged, REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_PLAYER)
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onEffectChanged, REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_PLAYER_PET)
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onEffectChanged, REGISTER_FILTER_UNIT_TAG, "player", REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_NONE)
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onEffectChanged, REGISTER_FILTER_UNIT_TAG, "player", REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_GROUP)
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onEffectChanged, REGISTER_FILTER_UNIT_TAG, "player", REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_TARGET_DUMMY)
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onEffectChanged, REGISTER_FILTER_UNIT_TAG, "player", REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_OTHER)

		for i=1,#libint.specialBuffs do

			self:RegisterEvent(EVENT_COMBAT_EVENT, onSpecialBuffEvent, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_EFFECT_GAINED_DURATION, REGISTER_FILTER_ABILITY_ID, libint.specialBuffs[i], REGISTER_FILTER_IS_ERROR, false)
			self:RegisterEvent(EVENT_COMBAT_EVENT, onSpecialBuffEvent, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_EFFECT_FADED, REGISTER_FILTER_ABILITY_ID, libint.specialBuffs[i], REGISTER_FILTER_IS_ERROR, false)

		end

		for i=1,#libint.specialDebuffs do

			self:RegisterEvent(EVENT_COMBAT_EVENT, onSpecialDebuffEvent, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_EFFECT_GAINED_DURATION, REGISTER_FILTER_ABILITY_ID, libint.specialDebuffs[i], REGISTER_FILTER_IS_ERROR, false)
			self:RegisterEvent(EVENT_COMBAT_EVENT, onSpecialDebuffEvent, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_EFFECT_FADED, REGISTER_FILTER_ABILITY_ID, libint.specialDebuffs[i], REGISTER_FILTER_IS_ERROR, false)

		end

		for i=1,#libint.sourceBuggedBuffs do

			self:RegisterEvent(EVENT_EFFECT_CHANGED, onSourceBuggedEffectChanged, REGISTER_FILTER_ABILITY_ID, libint.sourceBuggedBuffs[i])

		end

		-- self:RegisterEvent(EVENT_COMBAT_EVENT, onAlkoshDmg, REGISTER_FILTER_ABILITY_ID, 75752, REGISTER_FILTER_IS_ERROR, false)
		self:RegisterEvent(EVENT_COMBAT_EVENT, onTrialDummy, REGISTER_FILTER_ABILITY_ID, 120024, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_EFFECT_GAINED, REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_TARGET_DUMMY, REGISTER_FILTER_IS_ERROR, false)

		self.active = true
	end
)

libint.Events.GroupEffectsIn = libint.EventHandler:New(
	{LIBCOMBAT_EVENT_GROUPEFFECTS_IN},
	function (self)
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onGroupEffectIn, REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_GROUP, REGISTER_FILTER_UNIT_TAG_PREFIX, "group")
		self.active = true
	end
)

libint.Events.GroupEffectsOut = libint.EventHandler:New(
	{LIBCOMBAT_EVENT_GROUPEFFECTS_OUT},
	function (self)
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onGroupEffectOut, REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_GROUP, REGISTER_FILTER_UNIT_TAG, "")
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onGroupEffectOut, REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_GROUP, REGISTER_FILTER_UNIT_TAG, "reticleover")
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onGroupEffectOut, REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_GROUP, REGISTER_FILTER_UNIT_TAG, "reticleoverplayer")
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onGroupEffectOut, REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_GROUP, REGISTER_FILTER_UNIT_TAG_PREFIX, "boss")
		self.active = true
	end
)

local isFileInitialized = false

function lib.InitializeEffects()

	if isFileInitialized == true then return false end

    isFileInitialized = true
	return true

end