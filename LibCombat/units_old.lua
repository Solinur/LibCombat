local lib = LibCombat
local libint = lib.internal
local ld = libint.data
local logger
local CallbackKeys = libint.callbackKeys
local GetFormattedAbilityName = lib.GetFormattedAbilityName

local UnitHandler = ZO_Object:Subclass()
libint.UnitHandler = UnitHandler

---@diagnostic disable-next-line: duplicate-set-field
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

		ld.units.playerId = unitId
		libint.currentfight.playerid = unitId
		self.displayname = ld.accountname
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
	self.forceOfNature = {}
	self.forceOfNatureStacks = 0

	if self.unitType == COMBAT_UNIT_TYPE_GROUP then self:UpdateGroupData() end
end

function UnitHandler:UpdateGroupData()

	local groupdata = ld.groupInfo

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

function UnitHandler:UpdateZenData(callbackKeys, eventid, timeMs, unitId, abilityId, changeType, effectType, _, sourceType, effectSlot, abilityType)

	if abilityId == libint.abilityIdZen then

		local isActive = changeType == EFFECT_RESULT_GAINED -- or (changeType == EFFECT_RESULT_UPDATED)
		local stacks = isActive and zo_min(self.stacksOfZen, 5) or 0

		lib.cm:FireCallbacks(callbackKeys, eventid, timeMs, unitId, libint.abilityIdZen, changeType, effectType, stacks, sourceType, effectSlot)	-- stack count is 1 to 6, with 1 meaning 0% bonus, and 6 meaning 5% bonus from Z'en
		logger:Debug("VERBOSE", table.concat({eventid, timeMs, unitId, libint.abilityIdZen, changeType, effectType, stacks, sourceType, effectSlot}, ", "))
		self.zenEffectSlot = (isActive and effectSlot) or nil

	elseif abilityType == ABILITY_TYPE_DAMAGE then

		if changeType == EFFECT_RESULT_GAINED then

			self.stacksOfZen = self.stacksOfZen + 1

		elseif changeType == EFFECT_RESULT_FADED then

			if self.stacksOfZen - 1 < 0 then logger:Debug("WARNING", "Encountered negative Z'en stacks: %s (%d)", GetFormattedAbilityName(abilityId), abilityId) end
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
		if self.forceOfNatureStacks > 8 then logger:Debug("WARNING", "Encountered too many Force of Nature stacks (%d): %s (%d)", self.forceOfNatureStacks, GetFormattedAbilityName(abilityId), abilityId) end
		debugChangeType = "+"

	elseif changeType == EFFECT_RESULT_FADED and self.forceOfNature[abilityId] == true then

		self.forceOfNature[abilityId] = nil

		if self.forceOfNatureStacks == 0 then forceOfNatureChangeType = EFFECT_RESULT_FADED end
		if self.forceOfNatureStacks - 1 < 0 then logger:Debug("WARNING", "Encountered negative Force of Nature stacks: %s (%d)", GetFormattedAbilityName(abilityId), abilityId) end

		self.forceOfNatureStacks = zo_max(0, self.forceOfNatureStacks - 1)
		debugChangeType = "-"

	end

	local stacks = zo_min(self.forceOfNatureStacks, 8)
	lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_EFFECTS_OUT]), LIBCOMBAT_EVENT_EFFECTS_OUT, timeMs, unitId, libint.abilityIdForceOfNature, forceOfNatureChangeType, BUFF_EFFECT_TYPE_DEBUFF, stacks, COMBAT_UNIT_TYPE_PLAYER, 0)
	logger:Debug("VERBOSE", "Force of Nature: %s (%d) x%d, %s%s", self.name, self.unitId, stacks, GetFormattedAbilityName(abilityId), debugChangeType)
end

local isFileInitialized = false

function lib.InitializeUnits()

	if isFileInitialized == true then return false end

    isFileInitialized = true
	return true

end
