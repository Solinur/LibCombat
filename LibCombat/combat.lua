local lib = LibCombat
local libint = lib.internal
local libdata = lib.data
local Print = libint.Print

local DamageShieldBuffer = {}
libint.DamageShieldBuffer = DamageShieldBuffer

local function CheckForShield(timems, sourceUnitId, targetUnitId)

	for i = #DamageShieldBuffer, 1, -1 do

		local shieldTimems, shieldSourceUnitId, shieldTargetUnitId, shieldHitValue = unpack(DamageShieldBuffer[i])

		Print("dev","VERBOSE", "Eval Shield Index %d: Source: %s, Target: %s, Time: %d", i, tostring(shieldSourceUnitId == sourceUnitId), tostring(shieldTargetUnitId == targetUnitId), timems - shieldTimems)

		if shieldSourceUnitId == sourceUnitId and shieldTargetUnitId == targetUnitId and timems - shieldTimems < 100 then

			table.remove(DamageShieldBuffer, i)

			return shieldHitValue

		end
	end
end

--(eventCode, result, isError, abilityName, abilityGraphic, abilityActionSlotType, sourceName, sourceType, targetName, targetType, hitValue, powerType, damageType, log, sourceUnitId, targetUnitId, abilityId, overflow)

local function CombatEventHandler(isheal, _, result, _, _, _, _, sourceName, sourceType, targetName, targetType, hitValue, powerType, damageType, _, sourceUnitId, targetUnitId, abilityId, overflow)  -- called by Event

	if not (sourceUnitId > 0 and targetUnitId > 0) or (libdata.inCombat == false and (result==ACTION_RESULT_DOT_TICK_CRITICAL or result==ACTION_RESULT_DOT_TICK or isheal)) or targetType==2 then return end 
    -- only record if both unitids are valid or player is in combat or a non dot damage action happens or the target is not a pet

	local timems = GetGameTimeMilliseconds()

	local shieldHitValue = CheckForShield(timems, sourceUnitId, targetUnitId) or 0

	if (hitValue + (overflow or 0) + shieldHitValue) <= 0 then return end

	if sourceUnitId then libint.CheckUnit(sourceName, sourceUnitId, sourceType, timems) end
	if targetUnitId then libint.CheckUnit(targetName, targetUnitId, targetType, timems) end

	if result == ACTION_RESULT_DAMAGE_SHIELDED then

		sourceUnitId = targetUnitId
		sourceType = targetType

	end

	local isout = (sourceType == 1 or sourceType == 2)
	local isin = targetType == 1

	local eventid = LIBCOMBAT_EVENT_DAMAGE_OUT + (isheal and 3 or 0) + ((isout and isin) and 2 or isin and 1 or 0)

	if libint.currentfight.prepared ~= true then libint.currentfight:PrepareFight() end -- get stats before the damage event

	damageType = (isheal and powerType) or damageType

	if not isheal then overflow = shieldHitValue end

	libint.currentfight:AddCombatEvent(timems, result, targetUnitId, hitValue, eventid, overflow)

	lib.cm:FireCallbacks((libint.callbackKeys[eventid]), eventid, timems, result, sourceUnitId, targetUnitId, abilityId, hitValue, damageType, (overflow or 0))

end

local function onCombatEventDmg(...)
	CombatEventHandler(false, ...)	-- (isheal, ...)
end

local function onCombatEventShield(eventCode, result, isError, abilityName, abilityGraphic, abilityActionSlotType, sourceName, sourceType, targetName, targetType, hitValue, powerType, damageType, log, sourceUnitId, targetUnitId, abilityId)

	DamageShieldBuffer[#DamageShieldBuffer + 1] = {GetGameTimeMilliseconds(), sourceUnitId, targetUnitId, hitValue}

	Print("dev","DEBUG", "Add %d Shield: %d -> %d  (%d)", hitValue, sourceUnitId, targetUnitId, #DamageShieldBuffer)

end

local function onCombatEventDmgIn(...)
	-- avoid counting actions to oneself twice
	local _, _, _, _, _, _, _, sourceType, _, targetType, _, _, _, _, _, _, _ = ...

	if (sourceType == COMBAT_UNIT_TYPE_PLAYER or sourceType == COMBAT_UNIT_TYPE_PLAYER_PET) and (targetType == COMBAT_UNIT_TYPE_PLAYER or targetType == COMBAT_UNIT_TYPE_PLAYER_PET) then return end

	CombatEventHandler(false, ...)	-- (isheal, ...)
end

local function onCombatEventHeal(...)
	local _, _, _, _, _, _, _, _, _, _, hitValue, _, _, _, _, _, _, overflow = ...

	if (hitValue + (overflow or 0)) < 2 or (libdata.inCombat == false and (GetGameTimeMilliseconds() - libint.currentfight.combatend >= 50)) then return end				-- only record in combat

	CombatEventHandler(true, ...)	-- (isheal, ...)
end

local function onCombatEventHealIn(...)
	-- avoid counting actions to oneself twice
	local _, _, _, _, _, _, _, sourceType, _, targetType, _, _, _, _, _, _, _ = ...

	if (sourceType == COMBAT_UNIT_TYPE_PLAYER or sourceType == COMBAT_UNIT_TYPE_PLAYER_PET) and (targetType == COMBAT_UNIT_TYPE_PLAYER or targetType == COMBAT_UNIT_TYPE_PLAYER_PET) then return end

	onCombatEventHeal(...)
end

local function onCombatEventDmgGrp(_, _, _, _, _, _, _, _, targetName, targetType, hitValue, _, _, _, _, targetUnitId, abilityId)  -- called by Event

	if hitValue < 2 or targetUnitId == nil or targetType==2 then return end

	if hitValue > 200000 then

		Print("dev","WARNING", "Big Damage Event: (%d) %s did %d damage to %s", abilityId, libint.GetFormattedAbilityName(abilityId), hitValue, tostring(targetName))

		return

	end

	table.insert(libint.currentfight.grplog,{targetUnitId,hitValue,"dmg"})
end

local function onCombatEventHealGrp(_, _, _, _, _, _, _, _, _, targetType, hitValue, _, _, _, _, targetUnitId, _)  -- called by Event

    local currentfight = libint.currentfight

	if targetType==2 or targetUnitId == nil or hitValue<2 or (libdata.inCombat == false and (GetGameTimeMilliseconds() - (currentfight.combatend or 0) >= 50)) then return end

	table.insert(currentfight.grplog,{targetUnitId,hitValue,"heal"})
end

--(eventCode, result, isError, abilityName, abilityGraphic, abilityActionSlotType, sourceName, sourceType, targetName, targetType, hitValue, powerType, damageType, log, sourceUnitId, targetUnitId, abilityId, overflow)


libint.Events.DmgOut = libint.EventHandler:New(
	{LIBCOMBAT_EVENT_FIGHTRECAP, LIBCOMBAT_EVENT_FIGHTSUMMARY, LIBCOMBAT_EVENT_DAMAGE_OUT, LIBCOMBAT_EVENT_DAMAGE_SELF},
	function (self)

		Print("dev", "INFO", "Register Damage Events")

		local filters = {
			ACTION_RESULT_DAMAGE,
			ACTION_RESULT_DOT_TICK,
			ACTION_RESULT_BLOCKED_DAMAGE,
			ACTION_RESULT_CRITICAL_DAMAGE,
			ACTION_RESULT_DOT_TICK_CRITICAL,
		}

		for i=1,#filters do
			self:RegisterEvent(EVENT_COMBAT_EVENT, onCombatEventDmg, REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_PLAYER, 		REGISTER_FILTER_COMBAT_RESULT, filters[i], REGISTER_FILTER_IS_ERROR, false)
			self:RegisterEvent(EVENT_COMBAT_EVENT, onCombatEventDmg, REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_PLAYER_PET, 	REGISTER_FILTER_COMBAT_RESULT, filters[i], REGISTER_FILTER_IS_ERROR, false)
		end

		self:RegisterEvent(EVENT_COMBAT_EVENT, onCombatEventShield, REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_PLAYER, 		REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_DAMAGE_SHIELDED, REGISTER_FILTER_IS_ERROR, false)
		self:RegisterEvent(EVENT_COMBAT_EVENT, onCombatEventShield, REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_PLAYER_PET, 	REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_DAMAGE_SHIELDED, REGISTER_FILTER_IS_ERROR, false)

		self.active = true
	end
)

libint.Events.DmgIn = libint.EventHandler:New(
	{LIBCOMBAT_EVENT_FIGHTRECAP, LIBCOMBAT_EVENT_FIGHTSUMMARY, LIBCOMBAT_EVENT_DAMAGE_IN},
	function (self)

		local filters = {
			ACTION_RESULT_DAMAGE,
			ACTION_RESULT_DOT_TICK,
			ACTION_RESULT_BLOCKED_DAMAGE,
			ACTION_RESULT_CRITICAL_DAMAGE,
			ACTION_RESULT_DOT_TICK_CRITICAL,
		}

		for i=1,#filters do
			self:RegisterEvent(EVENT_COMBAT_EVENT, onCombatEventDmgIn, REGISTER_FILTER_TARGET_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_PLAYER, 		REGISTER_FILTER_COMBAT_RESULT, filters[i], REGISTER_FILTER_IS_ERROR, false)
			self:RegisterEvent(EVENT_COMBAT_EVENT, onCombatEventDmgIn, REGISTER_FILTER_TARGET_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_PLAYER_PET, 	REGISTER_FILTER_COMBAT_RESULT, filters[i], REGISTER_FILTER_IS_ERROR, false)
		end

		self:RegisterEvent(EVENT_COMBAT_EVENT, onCombatEventShield, REGISTER_FILTER_TARGET_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_PLAYER, 		REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_DAMAGE_SHIELDED, REGISTER_FILTER_IS_ERROR, false)
		self:RegisterEvent(EVENT_COMBAT_EVENT, onCombatEventShield, REGISTER_FILTER_TARGET_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_PLAYER_PET, 	REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_DAMAGE_SHIELDED, REGISTER_FILTER_IS_ERROR, false)

		self.active = true
	end
)

libint.Events.HealOut = libint.EventHandler:New(
	{LIBCOMBAT_EVENT_FIGHTRECAP, LIBCOMBAT_EVENT_FIGHTSUMMARY, LIBCOMBAT_EVENT_HEAL_OUT, LIBCOMBAT_EVENT_HEAL_SELF},
	function (self)

		local filters = {
			ACTION_RESULT_HOT_TICK,
			ACTION_RESULT_HEAL,
			ACTION_RESULT_CRITICAL_HEAL,
			ACTION_RESULT_HOT_TICK_CRITICAL,
		}

		for i=1,#filters do
			self:RegisterEvent(EVENT_COMBAT_EVENT, onCombatEventHeal, REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_PLAYER, 	REGISTER_FILTER_COMBAT_RESULT, filters[i], REGISTER_FILTER_IS_ERROR, false)
			self:RegisterEvent(EVENT_COMBAT_EVENT, onCombatEventHeal, REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_PLAYER_PET, REGISTER_FILTER_COMBAT_RESULT, filters[i], REGISTER_FILTER_IS_ERROR, false)
		end

		self.active = true
	end
)

libint.Events.HealIn = libint.EventHandler:New(
	{LIBCOMBAT_EVENT_FIGHTRECAP, LIBCOMBAT_EVENT_FIGHTSUMMARY, LIBCOMBAT_EVENT_HEAL_IN},
	function (self)

		local filters = {
			ACTION_RESULT_HOT_TICK,
			ACTION_RESULT_HEAL,
			ACTION_RESULT_CRITICAL_HEAL,
			ACTION_RESULT_HOT_TICK_CRITICAL,
			ACTION_RESULT_DAMAGE_SHIELDED
		}

		for i=1,#filters do
			self:RegisterEvent(EVENT_COMBAT_EVENT, onCombatEventHealIn, REGISTER_FILTER_TARGET_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_PLAYER, 		REGISTER_FILTER_COMBAT_RESULT, filters[i], REGISTER_FILTER_IS_ERROR, false)
			self:RegisterEvent(EVENT_COMBAT_EVENT, onCombatEventHealIn, REGISTER_FILTER_TARGET_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_PLAYER_PET, 	REGISTER_FILTER_COMBAT_RESULT, filters[i], REGISTER_FILTER_IS_ERROR, false)
		end

		self.active = true
	end
)

libint.Events.CombatGrp = libint.EventHandler:New(
	{LIBCOMBAT_EVENT_GROUPRECAP},
	function (self)

		local filters = {
			[onCombatEventDmgGrp] = {
				ACTION_RESULT_DAMAGE,
				ACTION_RESULT_DOT_TICK,
				ACTION_RESULT_BLOCKED_DAMAGE,
				ACTION_RESULT_DAMAGE_SHIELDED,
				ACTION_RESULT_CRITICAL_DAMAGE,
				ACTION_RESULT_DOT_TICK_CRITICAL,
			},
			[onCombatEventHealGrp] = {
				ACTION_RESULT_HOT_TICK,
				ACTION_RESULT_HEAL,
				ACTION_RESULT_CRITICAL_HEAL,
				ACTION_RESULT_HOT_TICK_CRITICAL,
				ACTION_RESULT_DAMAGE_SHIELDED
			},
		}

		for k,v in pairs(filters) do

			for i=1, #v do

				self:RegisterEvent(EVENT_COMBAT_EVENT, k, REGISTER_FILTER_COMBAT_RESULT, v[i], REGISTER_FILTER_IS_ERROR, false)

			end
		end

		self.active = true

	end
)