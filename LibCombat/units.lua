local lib = LibCombat
local libint = lib.internal
local libdata = lib.data
local Print = libint.Print

local UnitHandler = ZO_Object:Subclass()
libint.UnitHandler = UnitHandler

function UnitHandler:New(...)
    local object = ZO_Object.New(self)
    object:Initialize(...)
    return object
end

function UnitHandler:Initialize(name, unitId, unitType)

	name = ZO_CachedStrFormat(SI_UNIT_NAME, name)

	if (unitType == nil or unitType == COMBAT_UNIT_TYPE_TARGET_DUMMY) then unitType = COMBAT_UNIT_TYPE_NONE end

	self.isFriendly = false

	if unitType==COMBAT_UNIT_TYPE_PLAYER or unitType==COMBAT_UNIT_TYPE_GROUP or unitType==COMBAT_UNIT_TYPE_PLAYER_PET then

		self.isFriendly = true

	end

	if unitType == COMBAT_UNIT_TYPE_PLAYER then

		libdata.playerid = unitId
		libint.currentfight.playerid = unitId
		self.displayname = libdata.accountname
		self.unitTag = "player"
		self.isDead = IsUnitDeadOrReincarnating("player")

	end

	self.unitId = unitId
	self.name = name					-- name
	self.unitType = unitType			-- type of unit: group, pet or boss
	self.damageOutTotal = 0
	self.groupDamageOut  = 0
	self.dpsstart = nil 				-- start of dps in ms
	self.dpsend = nil				 	-- end of dps in ms
	self.zenEffectSlot = nil
	self.stacksOfZen = 0

	if self.unitType == COMBAT_UNIT_TYPE_GROUP then self:UpdateGroupData() end
end

function UnitHandler:UpdateGroupData()

	local groupdata = libdata.groupInfo

	local unitTag = groupdata.nameToTag[self.name]

	self.displayname = groupdata.nameToDisplayname[self.name]
	self.unitTag = unitTag

	if unitTag then self.isDead = IsUnitDeadOrReincarnating(unitTag) end

	groupdata.nameToId[self.name] = self.unitId

	if unitTag then groupdata.tagToId[unitTag] = self.unitId end

end

function UnitHandler:GetUnitInfo()

	local data = {}

	data.unitId = self.unitId
	data.name = self.name
	data.displayname = self.displayname
	data.unitTag = self.unitTag
	data.unitType = self.unitType

	return data

end

function UnitHandler:UpdateZenData(eventid, timems, unitId, abilityId, changeType, effectType, _, sourceType, effectSlot, abilityType)

	if abilityId == libint.abilityIdZen then

		local isActive = (changeType == EFFECT_RESULT_GAINED) or (changeType == EFFECT_RESULT_UPDATED)
		local stacks = isActive and self.stacksOfZen or 0

		lib.cm:FireCallbacks((libint.callbackKeys[eventid]), eventid, timems, unitId, libint.abilityIdZen, changeType, effectType, stacks, sourceType, effectSlot)	-- stack count is 1 to 6, with 1 meaning 0% bonus, and 6 meaning 5% bonus from Z'en
		Print("other","WARNING", table.concat({eventid, timems, unitId, libint.abilityIdZen, changeType, effectType, stacks, sourceType, effectSlot}, ", "))
		self.zenEffectSlot = (isActive and effectSlot) or nil


	elseif abilityType == ABILITY_TYPE_DAMAGE then

		if changeType == EFFECT_RESULT_GAINED or changeType == EFFECT_RESULT_UPDATED then
			
			self.stacksOfZen = self.stacksOfZen + 1

		else

			--if self.stacksOfZen - 1 < 0 then Print("other","WARNING", "Encountererd negative Z'en stacks: %s (%d)", GetFormattedAbilityName(abilityId), abilityId) end
			self.stacksOfZen = math.max(0, self.stacksOfZen - 1)

		end

		if self.zenEffectSlot then

			local stacks = math.min(self.stacksOfZen, 5)
			lib.cm:FireCallbacks((libint.callbackKeys[LIBCOMBAT_EVENT_EFFECTS_OUT]), LIBCOMBAT_EVENT_EFFECTS_OUT, timems, unitId, libint.abilityIdZen, EFFECT_RESULT_UPDATED, effectType, stacks, sourceType, self.zenEffectSlot)
			Print("other","WARNING", table.concat({LIBCOMBAT_EVENT_EFFECTS_OUT, timems, unitId, libint.abilityIdZen, EFFECT_RESULT_UPDATED, effectType, stacks, sourceType, self.zenEffectSlot}, ", "))
		end
	end
end

local UnitCache = {}
lib.UnitCache = UnitCache

UnitCache.UnitsById = {}
UnitCache.UnitsByTag = {}
UnitCache.UnitsByName = {}

local resultVars = {

	[ACTION_RESULT_ABILITY_ON_COOLDOWN] = "ABILITY_ON_COOLDOWN",
	[ACTION_RESULT_ABSORBED] = "ABSORBED",
	[ACTION_RESULT_BAD_TARGET] = "BAD_TARGET",
	[ACTION_RESULT_BEGIN] = "BEGIN",
	[ACTION_RESULT_BEGIN_CHANNEL] = "BEGIN_CHANNEL",
	[ACTION_RESULT_BLADETURN] = "BLADETURN",
	[ACTION_RESULT_BLOCKED] = "BLOCKED",
	[ACTION_RESULT_BLOCKED_DAMAGE] = "BLOCKED_DAMAGE",
	[ACTION_RESULT_BUSY] = "BUSY",
	[ACTION_RESULT_CANNOT_USE] = "CANNOT_USE",
	[ACTION_RESULT_CANT_SEE_TARGET] = "CANT_SEE_TARGET",
	[ACTION_RESULT_CANT_SWAP_HOTBAR_IS_OVERRIDDEN] = "CANT_SWAP_HOTBAR_IS_OVERRIDDEN",
	[ACTION_RESULT_CANT_SWAP_WHILE_CHANGING_GEAR] = "CANT_SWAP_WHILE_CHANGING_GEAR",
	[ACTION_RESULT_CASTER_DEAD] = "CASTER_DEAD",
	[ACTION_RESULT_CRITICAL_DAMAGE] = "CRITICAL_DAMAGE",
	[ACTION_RESULT_CRITICAL_HEAL] = "CRITICAL_HEAL",
	[ACTION_RESULT_DAMAGE] = "DAMAGE",
	[ACTION_RESULT_DAMAGE_SHIELDED] = "DAMAGE_SHIELDED",
	[ACTION_RESULT_DEFENDED] = "DEFENDED",
	[ACTION_RESULT_DIED] = "DIED",
	[ACTION_RESULT_DIED_XP] = "DIED_XP",
	[ACTION_RESULT_DISARMED] = "DISARMED",
	[ACTION_RESULT_DISORIENTED] = "DISORIENTED",
	[ACTION_RESULT_DODGED] = "DODGED",
	[ACTION_RESULT_DOT_TICK] = "DOT_TICK",
	[ACTION_RESULT_DOT_TICK_CRITICAL] = "DOT_TICK_CRITICAL",
	[ACTION_RESULT_EFFECT_FADED] = "EFFECT_FADED",
	[ACTION_RESULT_EFFECT_GAINED] = "EFFECT_GAINED",
	[ACTION_RESULT_EFFECT_GAINED_DURATION] = "EFFECT_GAINED_DURATION",
	[ACTION_RESULT_FAILED] = "FAILED",
	[ACTION_RESULT_FAILED_REQUIREMENTS] = "FAILED_REQUIREMENTS",
	[ACTION_RESULT_FAILED_SIEGE_CREATION_REQUIREMENTS] = "FAILED_SIEGE_CREATION_REQUIREMENTS",
	[ACTION_RESULT_FALL_DAMAGE] = "FALL_DAMAGE",
	[ACTION_RESULT_FALLING] = "FALLING",
	[ACTION_RESULT_FEARED] = "FEARED",
	[ACTION_RESULT_GRAVEYARD_DISALLOWED_IN_INSTANCE] = "GRAVEYARD_DISALLOWED_IN_INSTANCE",
	[ACTION_RESULT_GRAVEYARD_TOO_CLOSE] = "GRAVEYARD_TOO_CLOSE",
	[ACTION_RESULT_HEAL] = "HEAL",
	[ACTION_RESULT_HEAL_ABSORBED] = "HEAL_ABSORBED",
	[ACTION_RESULT_HOT_TICK] = "HOT_TICK",
	[ACTION_RESULT_HOT_TICK_CRITICAL] = "HOT_TICK_CRITICAL",
	[ACTION_RESULT_IMMUNE] = "IMMUNE",
	[ACTION_RESULT_IN_AIR] = "IN_AIR",
	[ACTION_RESULT_IN_COMBAT] = "IN_COMBAT",
	[ACTION_RESULT_IN_ENEMY_KEEP] = "IN_ENEMY_KEEP",
	[ACTION_RESULT_IN_ENEMY_OUTPOST] = "IN_ENEMY_OUTPOST",
	[ACTION_RESULT_IN_ENEMY_RESOURCE] = "IN_ENEMY_RESOURCE",
	[ACTION_RESULT_IN_ENEMY_TOWN] = "IN_ENEMY_TOWN",
	[ACTION_RESULT_IN_HIDEYHOLE] = "IN_HIDEYHOLE",
	[ACTION_RESULT_INSUFFICIENT_RESOURCE] = "INSUFFICIENT_RESOURCE",
	[ACTION_RESULT_INTERCEPTED] = "INTERCEPTED",
	[ACTION_RESULT_INTERRUPT] = "INTERRUPT",
	[ACTION_RESULT_INVALID] = "INVALID",
	[ACTION_RESULT_INVALID_FIXTURE] = "INVALID_FIXTURE",
	[ACTION_RESULT_INVALID_JUSTICE_TARGET] = "INVALID_JUSTICE_TARGET",
	[ACTION_RESULT_INVALID_TERRAIN] = "INVALID_TERRAIN",
	[ACTION_RESULT_ITERATION_BEGIN] = "ITERATION_BEGIN",
	[ACTION_RESULT_ITERATION_END] = "ITERATION_END",
	[ACTION_RESULT_KILLED_BY_DAEDRIC_WEAPON] = "KILLED_BY_DAEDRIC_WEAPON",
	[ACTION_RESULT_KILLED_BY_SUBZONE] = "KILLED_BY_SUBZONE",
	[ACTION_RESULT_KILLING_BLOW] = "KILLING_BLOW",
	[ACTION_RESULT_KNOCKBACK] = "KNOCKBACK",
	[ACTION_RESULT_LEVITATED] = "LEVITATED",
	[ACTION_RESULT_LINKED_CAST] = "LINKED_CAST",
	[ACTION_RESULT_MERCENARY_LIMIT] = "MERCENARY_LIMIT",
	[ACTION_RESULT_MISS] = "MISS",
	[ACTION_RESULT_MISSING_EMPTY_SOUL_GEM] = "MISSING_EMPTY_SOUL_GEM",
	[ACTION_RESULT_MISSING_FILLED_SOUL_GEM] = "MISSING_FILLED_SOUL_GEM",
	[ACTION_RESULT_MOBILE_GRAVEYARD_LIMIT] = "MOBILE_GRAVEYARD_LIMIT",
	[ACTION_RESULT_MOUNTED] = "MOUNTED",
	[ACTION_RESULT_MUST_BE_IN_OWN_KEEP] = "MUST_BE_IN_OWN_KEEP",
	[ACTION_RESULT_NO_LOCATION_FOUND] = "NO_LOCATION_FOUND",
	[ACTION_RESULT_NO_RAM_ATTACKABLE_TARGET_WITHIN_RANGE] = "NO_RAM_ATTACKABLE_TARGET_WITHIN_RANGE",
	[ACTION_RESULT_NO_WEAPONS_TO_SWAP_TO] = "NO_WEAPONS_TO_SWAP_TO",
	[ACTION_RESULT_NOT_ENOUGH_INVENTORY_SPACE] = "NOT_ENOUGH_INVENTORY_SPACE",
	[ACTION_RESULT_NOT_ENOUGH_INVENTORY_SPACE_SOUL_GEM] = "NOT_ENOUGH_INVENTORY_SPACE_SOUL_GEM",
	[ACTION_RESULT_NOT_ENOUGH_SPACE_FOR_SIEGE] = "NOT_ENOUGH_SPACE_FOR_SIEGE",
	[ACTION_RESULT_NPC_TOO_CLOSE] = "NPC_TOO_CLOSE",
	[ACTION_RESULT_OFFBALANCE] = "OFFBALANCE",
	[ACTION_RESULT_PACIFIED] = "PACIFIED",
	[ACTION_RESULT_PARRIED] = "PARRIED",
	[ACTION_RESULT_PARTIAL_RESIST] = "PARTIAL_RESIST",
	[ACTION_RESULT_POWER_DRAIN] = "POWER_DRAIN",
	[ACTION_RESULT_POWER_ENERGIZE] = "POWER_ENERGIZE",
	[ACTION_RESULT_PRECISE_DAMAGE] = "PRECISE_DAMAGE",
	[ACTION_RESULT_QUEUED] = "QUEUED",
	[ACTION_RESULT_RAM_ATTACKABLE_TARGETS_ALL_DESTROYED] = "RAM_ATTACKABLE_TARGETS_ALL_DESTROYED",
	[ACTION_RESULT_RAM_ATTACKABLE_TARGETS_ALL_OCCUPIED] = "RAM_ATTACKABLE_TARGETS_ALL_OCCUPIED",
	[ACTION_RESULT_RECALLING] = "RECALLING",
	[ACTION_RESULT_REFLECTED] = "REFLECTED",
	[ACTION_RESULT_REINCARNATING] = "REINCARNATING",
	[ACTION_RESULT_RESIST] = "RESIST",
	[ACTION_RESULT_RESURRECT] = "RESURRECT",
	[ACTION_RESULT_ROOTED] = "ROOTED",
	[ACTION_RESULT_SIEGE_LIMIT] = "SIEGE_LIMIT",
	[ACTION_RESULT_SIEGE_NOT_ALLOWED_IN_ZONE] = "SIEGE_NOT_ALLOWED_IN_ZONE",
	[ACTION_RESULT_SIEGE_TOO_CLOSE] = "SIEGE_TOO_CLOSE",
	[ACTION_RESULT_SILENCED] = "SILENCED",
	[ACTION_RESULT_SNARED] = "SNARED",
	[ACTION_RESULT_SOUL_GEM_RESURRECTION_ACCEPTED] = "SOUL_GEM_RESURRECTION_ACCEPTED",
	[ACTION_RESULT_SPRINTING] = "SPRINTING",
	[ACTION_RESULT_STAGGERED] = "STAGGERED",
	[ACTION_RESULT_STUNNED] = "STUNNED",
	[ACTION_RESULT_SWIMMING] = "SWIMMING",
	[ACTION_RESULT_TARGET_DEAD] = "TARGET_DEAD",
	[ACTION_RESULT_TARGET_NOT_IN_VIEW] = "TARGET_NOT_IN_VIEW",
	[ACTION_RESULT_TARGET_NOT_PVP_FLAGGED] = "TARGET_NOT_PVP_FLAGGED",
	[ACTION_RESULT_TARGET_OUT_OF_RANGE] = "TARGET_OUT_OF_RANGE",
	[ACTION_RESULT_TARGET_TOO_CLOSE] = "TARGET_TOO_CLOSE",
	[ACTION_RESULT_UNEVEN_TERRAIN] = "UNEVEN_TERRAIN",
	[ACTION_RESULT_WEAPONSWAP] = "WEAPONSWAP",
	[ACTION_RESULT_WRECKING_DAMAGE] = "WRECKING_DAMAGE",
	[ACTION_RESULT_WRONG_WEAPON] = "WRONG_WEAPON",

}

local unitDetectionResults = {

	[ACTION_RESULT_DAMAGE] = true,
	[ACTION_RESULT_CRITICAL_DAMAGE] = true,
	[ACTION_RESULT_HEAL] = true,
	[ACTION_RESULT_CRITICAL_HEAL] = true,
	[ACTION_RESULT_POWER_DRAIN] = true,
	[ACTION_RESULT_POWER_ENERGIZE] = true,
	[ACTION_RESULT_IMMUNE] = true,
	[ACTION_RESULT_SILENCED] = true,
	[ACTION_RESULT_STUNNED] = true,
	[ACTION_RESULT_SNARED] = true,
	[ACTION_RESULT_BUSY] = true,
	[ACTION_RESULT_BAD_TARGET] = true,
	[ACTION_RESULT_TARGET_DEAD] = true,
	[ACTION_RESULT_CASTER_DEAD] = true,
	[ACTION_RESULT_TARGET_NOT_IN_VIEW] = true,
	[ACTION_RESULT_ABILITY_ON_COOLDOWN] = true,
	[ACTION_RESULT_INSUFFICIENT_RESOURCE] = true,
	[ACTION_RESULT_TARGET_OUT_OF_RANGE] = true,
	[ACTION_RESULT_FAILED] = true,
	[ACTION_RESULT_DODGED] = true,
	[ACTION_RESULT_BLOCKED_DAMAGE] = true,
	[ACTION_RESULT_BEGIN] = true,
	[ACTION_RESULT_INTERRUPT] = true,
	[ACTION_RESULT_EFFECT_GAINED] = true,
	[ACTION_RESULT_EFFECT_GAINED_DURATION] = true,
	[ACTION_RESULT_EFFECT_FADED] = true,
	[ACTION_RESULT_DIED] = true,
	[ACTION_RESULT_DIED_XP] = true,
	[ACTION_RESULT_CANNOT_USE] = true,
	[ACTION_RESULT_FAILED_REQUIREMENTS] = true,
	[ACTION_RESULT_FEARED] = true,
	[ACTION_RESULT_CANT_SEE_TARGET] = true,
	[ACTION_RESULT_QUEUED] = true,
	[ACTION_RESULT_TARGET_TOO_CLOSE] = true,
	[ACTION_RESULT_FALL_DAMAGE] = true,
	[ACTION_RESULT_OFFBALANCE] = true,
	[ACTION_RESULT_DAMAGE_SHIELDED] = true,
	[ACTION_RESULT_STAGGERED] = true,
	[ACTION_RESULT_KNOCKBACK] = true,
	[ACTION_RESULT_FALLING] = true,
	[ACTION_RESULT_NO_LOCATION_FOUND] = true,
	[ACTION_RESULT_SPRINTING] = true,
	[ACTION_RESULT_SOUL_GEM_RESURRECTION_ACCEPTED] = true,
	[ACTION_RESULT_DOT_TICK] = true,
	[ACTION_RESULT_DOT_TICK_CRITICAL] = true,
	[ACTION_RESULT_HOT_TICK] = true,
	[ACTION_RESULT_HOT_TICK_CRITICAL] = true,

}

lib.resultVars = resultVars

local function onUnitCombatEvent(eventCode, result, isError, abilityName, abilityGraphic, abilityActionSlotType, sourceName, sourceType, targetName, targetType, hitValue, powerType, damageType, log, sourceUnitId, targetUnitId, abilityId, overflow)

	local UnitInfoResult = LibCombat_Save.UnitInfoResult

	if sourceName == lib.data.rawPlayername then sourceType = COMBAT_UNIT_TYPE_PLAYER end
	if targetName == lib.data.rawPlayername then targetType = COMBAT_UNIT_TYPE_PLAYER end

	local isSource = sourceName and sourceName ~= "" and sourceType and sourceUnitId and sourceUnitId >= 0
	local isTarget = targetName and targetName ~= "" and targetType and targetUnitId and targetUnitId >= 0

	local resultVar = resultVars[result] or "?"

	if isSource then

		if UnitInfoResult[sourceType] == nil then UnitInfoResult[sourceType] = {} end

		if UnitInfoResult[sourceType][result] == nil then

			-- Print("dev", 3, "New source result (%d) with full unit info: %d - %s", sourceType, result, resultVar)
			UnitInfoResult[sourceType][result] = resultVar .. " " .. sourceName
			LibCombat_Save.timestamp = GetTimeStamp()

		end

	end

	if isTarget then

		if UnitInfoResult[targetType] == nil then UnitInfoResult[targetType] = {} end

		if UnitInfoResult[targetType][result] == nil then

			-- Print("dev", 3, "New target result (%d) with full unit info: %d - %s", targetType, result, resultVar)
			UnitInfoResult[targetType][result] = resultVar .. " " .. targetName
			LibCombat_Save.timestamp = GetTimeStamp()

		end

	end

end

libint.onUnitCombatEvent = onUnitCombatEvent
libint.unitDetectionResults = unitDetectionResults

function libint.CheckUnit(unitName, unitId, unitType, timems)

	local currentunits = libint.currentfight.units

	if currentunits[unitId] == nil then currentunits[unitId] = UnitHandler:New(unitName, unitId, unitType) end
	local unit = currentunits[unitId]

	if unit.name == "Offline" or unit.name == "" then unit.name = ZO_CachedStrFormat(SI_UNIT_NAME, unitName) end

	if unit.unitType ~= COMBAT_UNIT_TYPE_GROUP and unitType==COMBAT_UNIT_TYPE_GROUP then

		unit.unitType = COMBAT_UNIT_TYPE_GROUP
		unit.isFriendly = true

	end

	if unit.isFriendly == false then

		local bossId = libdata.bossInfo[unit.name]		-- if this is a boss, add the id (e.g. 1 for unitTag == "boss1")

		if bossId then

			unit.bossId = bossId
			libint.currentfight.bosses[bossId] = unitId

			unit.unitTag = ZO_CachedStrFormat("boss<<1>>", bossId)

		end
	end

	unit.dpsstart = unit.dpsstart or timems
	unit.dpsend = timems

	unit.starttime = unit.starttime or timems
	unit.endtime = timems
end

function libint.CheckUnitFromTag(unitName, unitId, unitTag, timems, isGroup)

	if unitId == nil or unitId <= 0 or libint.currentfight.units[unitId] ~= nil then return end

	local unitType = COMBAT_UNIT_TYPE_NONE

	if unitTag == "player" then

		unitType = COMBAT_UNIT_TYPE_PLAYER

	elseif unitTag and string.sub(unitTag, 1, 9) == "playerpet" then unitType = COMBAT_UNIT_TYPE_PLAYER_PET end
	if isGroup then unitType = COMBAT_UNIT_TYPE_GROUP end

	-- IsUnitGrouped(unitTag), GetGroupIndexByUnitTag(unitTag), IsPlayerInGroup(GetUnitDisplayName(unitTag))

	Print("dev","INFO", "New Unit detected: %s (%d), tag: %s, type: %d", unitName or "", unitId or 0, unitTag or "", unitType or 0)

	libint.CheckUnit(unitName, unitId, unitType, timems)

end