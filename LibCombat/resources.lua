local lib = LibCombat
local libint = lib.internal
local CallbackKeys = libint.callbackKeys
local libfunc = libint.functions
local libdata = libint.data
local Log = libint.Log
local GetFormattedAbilityName = lib.GetFormattedAbilityName

local powerTypeCache = {}

local function GetPowerTypes(abilityId)

	local lastPowerType

	if powerTypeCache[abilityId] == nil then

		local newData = {}

		for i = 1, 4 do

			local powerType = GetNextAbilityMechanicFlag(abilityId, lastPowerType)

			if powerType and (powerType == COMBAT_MECHANIC_FLAGS_HEALTH or powerType == COMBAT_MECHANIC_FLAGS_MAGICKA or powerType == COMBAT_MECHANIC_FLAGS_STAMINA) then

				newData[powerType] = GetAbilityCost(abilityId,powerType, nil, "player")	-- add cost over time ??

			elseif powerType == nil then

				break

			end
		end

		powerTypeCache[abilityId] = newData
	end

	return powerTypeCache[abilityId]
end

local function onSlotUsed(_, slot)

	if libdata.inCombat == false or slot > 8 then return end

	local timems = GetGameTimeMilliseconds()
	local abilityId = libfunc.GetSlottedAbilityId(slot)

	-- Print("events", LOG_LEVEL_DEBUG, "Ability Used: %s (%d)", GetFormattedAbilityName(abilityId), abilityId)

	local powerTypes = GetPowerTypes(abilityId)
	local lastabilities = libdata.lastabilities

	if libint.Events.Resources.active and slot > 2 and NonContiguousCount(powerTypes) > 0 then

		for powerType, cost in pairs(powerTypes) do

			table.insert(lastabilities,{timems, abilityId, -cost, powerType})

		end

		if #lastabilities > libint.ABILITY_RESOURCE_CACHE_SIZE  then table.remove(lastabilities, 1) end

	end
end

local SPRINT_STATE_ACTIVE = 1
local SPRINT_STATE_NONE = 0

local function GetPlayerSprintState()

	for slot = 3,8 do

		local anyAbilityActive = not (
			ActionSlotHasTargetFailure(slot, HOTBAR_CATEGORY_PRIMARY) and
			ActionSlotHasNonCostStateFailure(slot, HOTBAR_CATEGORY_PRIMARY) and
			ActionSlotHasTargetFailure(slot, HOTBAR_CATEGORY_BACKUP) and
			ActionSlotHasNonCostStateFailure(slot, HOTBAR_CATEGORY_PRIMARY)
		)

		if anyAbilityActive then return SPRINT_STATE_NONE end

	end

	return SPRINT_STATE_ACTIVE

end

local function checkLastAbilities(timems, powerType, powerValueChange, powerValue)

	local lastabilities = libdata.lastabilities

	local abilityId = -1
	local adjustedPowerValueChange
	Log("events", "DEBUG", "Check %d Abilities: %d, %d, %d", #lastabilities, powerType, powerValueChange, powerValue)

	for i = #lastabilities, 1, -1 do

		local values = lastabilities[i]
		Log("events", "DEBUG", "Check: %s (%d), %d, %d", GetFormattedAbilityName(values[2]), values[2], powerValueChange / values[3], values[4])

		if powerType == values[4] then

			local ratio = powerValueChange / values[3]

			local goodratio = ratio >= 0.98 and ratio <= 1.06

			if goodratio then

				Log("events", "DEBUG", "Ratio: %.3f (**%s: %d vs. %d) %d", ratio, GetFormattedAbilityName(values[2]), values[3], powerValueChange, #lastabilities-i)

				abilityId = values[2]
				table.remove(lastabilities, i)

				break

			elseif values[2] == 58431 and GetAllyUnitBlockState("player") == BLOCK_STATE_ACTIVE then	-- check if Constitution coincides with Block

				local blockCost = select(2, GetAdvancedStatValue(ADVANCED_STAT_DISPLAY_TYPE_BLOCK_COST))

				local combinedPowerValueChange = values[3] - blockCost

				local ratio = powerValueChange / combinedPowerValueChange

				local goodratio = ratio >= 0.98 and ratio <= 1.06

				if goodratio then

					Log("events", "DEBUG", "Ratio: %.3f (**%s: %d vs. %d) %d", ratio, GetFormattedAbilityName(values[2]), combinedPowerValueChange, powerValueChange, #lastabilities-i)

					abilityId = 23542
					adjustedPowerValueChange = - blockCost
					table.remove(lastabilities, i)

					Log("events", "DEBUG", "Resource: %s (%d): %d (%d) --> %d", GetFormattedAbilityName(values[2]), values[2], values[3], powerType, powerValue - adjustedPowerValueChange)

					lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_RESOURCES]), LIBCOMBAT_EVENT_RESOURCES, timems, values[2], values[3], powerType, powerValue - adjustedPowerValueChange)

					break
				end
			end
		end

		if (values[1] - timems) > 1000 then break end
	end

	Log("events", "DEBUG", "Ability Result: %s (%d), %d", GetFormattedAbilityName(abilityId), abilityId, tostring(adjustedPowerValueChange))

	return abilityId, adjustedPowerValueChange

end

local function checkForCombatActions(powerValueChange)

	if powerValueChange > 0 then return -1 end

	if GetAllyUnitBlockState("player") == BLOCK_STATE_ACTIVE then

		local blockRatio = select(2, GetAdvancedStatValue(ADVANCED_STAT_DISPLAY_TYPE_BLOCK_COST)) / -powerValueChange

		if blockRatio >= 0.98 and blockRatio <= 1.02 then

			Log("events", "DEBUG", "Skill cost: %d Stamina (Block)", powerValueChange)
			return 23542

		end
	end

	local bashRatio = select(2, GetAdvancedStatValue(ADVANCED_STAT_DISPLAY_TYPE_BASH_COST))     / -powerValueChange
	if bashRatio >= 0.98 and bashRatio <= 1.02 then

		Log("events", "DEBUG", "Skill cost: %d Stamina (Bash)", powerValueChange)
		return 21970

	end

	local dodgeRatio = select(2, GetAdvancedStatValue(ADVANCED_STAT_DISPLAY_TYPE_DODGE_COST))    / -powerValueChange
	if dodgeRatio >= 0.98 and dodgeRatio <= 1.02 then

		Log("events", "DEBUG", "Skill cost: %d Stamina (Dodge)", powerValueChange)
		return 28549

	end

	local breakFreeRatio = select(2, GetAdvancedStatValue(ADVANCED_STAT_DISPLAY_TYPE_CC_BREAK_COST)) / -powerValueChange
	if breakFreeRatio >= 0.98 and breakFreeRatio <= 1.02 then

		Log("events", "DEBUG", "Skill cost: %d Stamina (Break Free)", powerValueChange)
		return 16565

	end

	if GetUnitStealthState("player") == STEALTH_STATE_HIDING or GetUnitStealthState("player") == STEALTH_STATE_HIDDEN and powerValueChange < 0 and powerValueChange > -20 then

		Log("events", "DEBUG", "Skill cost: %d Stamina (Sneak)", powerValueChange)
		return  20299

	end

	if GetPlayerSprintState() == SPRINT_STATE_ACTIVE and powerValueChange < 0 and powerValueChange > -20 then

		Log("events", "DEBUG", "Skill cost: %d Stamina (Sprint)", powerValueChange)
		return  15617

	end
end

local function onBaseResourceChanged(powerType, powerValue, powerValueChange)

	local timems = GetGameTimeMilliseconds()
	local abilityId, adjustedPowerValueChange

 	if powerType == COMBAT_MECHANIC_FLAGS_MAGICKA then

		local regenerationTick = libfunc.GetStat(STAT_MAGICKA_REGEN_COMBAT)

		Log("events", "DEBUG", "Magicka change: %d", powerValueChange)

		-- Check for recently used skills

		abilityId = checkLastAbilities(timems, powerType, powerValueChange, powerValue)

		-- Check for regeneration tick

		if abilityId == -1 and powerValueChange == regenerationTick or (powerValueChange > 0 and powerValueChange <= regenerationTick and powerValue == libdata.stats[LIBCOMBAT_STAT_MAXMAGICKA]) then

			abilityId = 0

			Log("events", "DEBUG", "Magicka Regeneration  (%d)", powerValueChange)

		elseif abilityId == -1 then	-- Check for combination of skill and regeneration tick

			abilityId = checkLastAbilities(timems, powerType, powerValueChange + regenerationTick, powerValue)

			if abilityId ~= -1 then

				Log("events", "DEBUG", "Resource: %s (%d): %d (%d) --> %d", "Regeneration", 0, regenerationTick, powerType, powerValue + regenerationTick)

				lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_RESOURCES]), LIBCOMBAT_EVENT_RESOURCES, timems, 0, regenerationTick, powerType, powerValue + regenerationTick)
				powerValueChange = powerValueChange - regenerationTick

			end
		end

	elseif powerType == COMBAT_MECHANIC_FLAGS_STAMINA then

		local regenerationTick = libfunc.GetStat(STAT_STAMINA_REGEN_COMBAT)

		Log("events", "DEBUG", "Stamina change: %d", powerValueChange)

		-- Check for recently used skills

		abilityId, adjustedPowerValueChange = checkLastAbilities(timems, powerType, powerValueChange, powerValue)

		if adjustedPowerValueChange then powerValueChange = adjustedPowerValueChange end

		-- Check for regeneration tick

		if abilityId == -1 and powerValueChange == regenerationTick or (powerValueChange > 0 and powerValueChange <= regenerationTick and powerValue == libdata.stats[LIBCOMBAT_STAT_MAXMAGICKA]) then

			abilityId = 0

			Log("events", "DEBUG", "Stamina Regeneration (%d)", powerValueChange)

		elseif abilityId == -1 then -- Check for combat actions

			abilityId = checkForCombatActions(powerValueChange)

			if abilityId == -1 then	-- Check for combination of skill and regeneration tick

				abilityId, adjustedPowerValueChange = checkLastAbilities(timems, powerType, powerValueChange + regenerationTick, powerValue)

				if adjustedPowerValueChange then powerValueChange = adjustedPowerValueChange end

				if abilityId ~= -1 then
					Log("events", "DEBUG", "Resource: %s (%d): %d (%d) --> %d", "Regeneration", 0, regenerationTick, powerType, powerValue + regenerationTick)

					lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_RESOURCES]), LIBCOMBAT_EVENT_RESOURCES, timems, 0, regenerationTick, powerType, powerValue + regenerationTick)
					powerValueChange = powerValueChange - regenerationTick

				end
			end
		end

	elseif powerType == COMBAT_MECHANIC_FLAGS_ULTIMATE then
		abilityId = 0

	elseif powerType == COMBAT_MECHANIC_FLAGS_HEALTH then
		abilityId = -1

		if powerValueChange == libfunc.GetStat(STAT_HEALTH_REGEN_COMBAT) and libdata.units.playerId then
			abilityId = 0
			lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_HEAL_SELF]), LIBCOMBAT_EVENT_HEAL_SELF, timems, ACTION_RESULT_HOT_TICK, libdata.units.playerId, libdata.units.playerId, abilityId, powerValueChange, powerType, 0)
			return
		end
	end

	Log("events", "DEBUG", "Resource: %s (%d): %d (%d) --> %d", GetFormattedAbilityName(abilityId), abilityId, powerValueChange, powerType, powerValue)

	lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_RESOURCES]), LIBCOMBAT_EVENT_RESOURCES, timems, abilityId, powerValueChange, powerType, powerValue)
end

local function onBaseResourceChangedDelayed(_,unitTag,_,powerType,newValue,_,_)
	if unitTag ~= "player" or (libdata.inCombat == false) then return end
	if powerType ~= COMBAT_MECHANIC_FLAGS_HEALTH and powerType ~= COMBAT_MECHANIC_FLAGS_MAGICKA and powerType ~= COMBAT_MECHANIC_FLAGS_STAMINA and powerType ~= COMBAT_MECHANIC_FLAGS_ULTIMATE then return end

	local oldValue = libdata.resources[powerType]
	libdata.resources[powerType] = newValue
	if oldValue == nil or oldValue == newValue then return end

	local powerValueChange = newValue - oldValue
	if powerType == COMBAT_MECHANIC_FLAGS_HEALTH and libdata.statusEffectBonus and libdata.statusEffectBonus.wealdBonus>0 then libint.currentfight:UpdateSingleStat(LIBCOMBAT_STAT_STATUS_EFFECT_CHANCE) end

	Log("events", "DEBUG", "onBaseResourceChangedDelayed: %s, %d, %d", unitTag, powerType, powerValueChange)
	zo_callLater(function() onBaseResourceChanged(powerType, newValue, powerValueChange) end, 0)
end

--(eventCode, result, isError, abilityName, abilityGraphic, abilityActionSlotType, sourceName, sourceType, targetName, targetType, hitValue, powerType, damageType, log, sourceUnitId, targetUnitId, abilityId, overflow)
local function onResourceChanged (_, result, _, _, _, _, _, _, targetName, _, powerValueChange, powerType, _, _, sourceUnitId, targetUnitId, abilityId)

	if (powerType ~= COMBAT_MECHANIC_FLAGS_MAGICKA and powerType ~= COMBAT_MECHANIC_FLAGS_STAMINA) or libdata.inCombat == false or powerValueChange < 1 then return end

	local timems = GetGameTimeMilliseconds()
	local lastabilities = libdata.lastabilities

	if result == ACTION_RESULT_POWER_DRAIN then powerValueChange = -powerValueChange end

	table.insert(lastabilities,{timems, abilityId, powerValueChange, powerType})

	if #lastabilities > libint.ABILITY_RESOURCE_CACHE_SIZE then table.remove(lastabilities, 1) end
end

libint.Events.Resources = libint.EventHandler:New(
	{LIBCOMBAT_EVENT_RESOURCES},
	function (self)
		self:RegisterEvent(EVENT_POWER_UPDATE, onBaseResourceChangedDelayed, REGISTER_FILTER_UNIT_TAG, "player")
		self:RegisterEvent(EVENT_COMBAT_EVENT, onResourceChanged, REGISTER_FILTER_TARGET_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_PLAYER, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_POWER_ENERGIZE, REGISTER_FILTER_IS_ERROR, false)
		self:RegisterEvent(EVENT_COMBAT_EVENT, onResourceChanged, REGISTER_FILTER_TARGET_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_PLAYER, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_POWER_DRAIN, REGISTER_FILTER_IS_ERROR, false)
		self:RegisterEvent(EVENT_ACTION_SLOT_ABILITY_USED, onSlotUsed)
		self.active = true
	end
)

local isFileInitialized = false

function lib.InitializeResources()

	if isFileInitialized == true then return false end

    isFileInitialized = true
	return true

end