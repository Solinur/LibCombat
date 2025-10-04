local _
local libunits            = {}
local lib                 = LibCombat2
local libint              = lib.internal
local lf                  = libint.functions
local ld                  = libint.data
ld.units                  = libunits
local logger
local spairs              = lf.spairs

---@diagnostic disable-next-line: undefined-global
local em                  = EventCallbackManager and EventCallbackManager:New("LCU_EventManager") or GetEventManager()
local wm                  = GetWindowManager()


-- internal objects
libunits.debug            = false or GetDisplayName() == "@Solinur"
libunits.unitData         = {}
libunits.unitIdsByRawName = {}
libunits.unitIdsByName    = {}
libunits.unitIdsByTag     = {}
libunits.groupTagByName   = {}
libunits.petData          = {}
libunits.bossTagByName    = {}
libunits.petTagByName     = {}
libunits.effectCache      = {}
libunits.effectSlotCache  = {}
libunits.UnitExportCache  = {}
libunits.debugPanel       = { init = false }

-- localized to optimze performace due to frequent calls by OnCombatEvent
local UnitCache = libunits.unitData
local EffectCache = libunits.effectCache

-- localized for convinience
local UnitExportCache = libunits.UnitExportCache
---@class UnitHandler 
local UnitHandler

---@diagnostic disable-next-line: undefined-global
local COMBAT_UNIT_TYPE_GROUP_COMPANION = COMBAT_UNIT_TYPE_GROUP_COMPANION or (COMBAT_UNIT_TYPE_GROUP + 100)
libint.COMBAT_UNIT_TYPE_GROUP_COMPANION = COMBAT_UNIT_TYPE_GROUP_COMPANION
-- Internal functions

local function IsValidUnitId(unitId)
	return unitId and (unitId >= 0)
end

local function IsValidUnitName(unitName)
	return unitName and (unitName ~= "") and (unitName ~= "Offline")
end

local function IsValidUnitData(rawName, unitId, unitType)
	return IsValidUnitName(rawName) and IsValidUnitId(unitId) and unitType
end

local function UpdatePlayerId(newPlayerId)
	if libunits.playerId == newPlayerId then return end -- check if it changed

	local oldPlayerId = libunits.playerId
	libunits.playerId = newPlayerId

	if oldPlayerId then UnitCache[oldPlayerId]:Delete() end -- delete old unit since it is obsolete
end

local function UpdateUnitTagId(unitTag, unitId)
	local UnitIdsByTag = libunits.unitIdsByTag
	local oldUnitId = UnitIdsByTag[unitTag]

	if oldUnitId then UnitCache[oldUnitId]:RemoveUnitTag(unitTag) end
	UnitIdsByTag[unitTag] = unitId
end

local function CheckForPetUnit(rawName, unitId) -- TODO: potentially detect other people's pets ?

end

-- Event Callbacks
-- Discover names of special units:

local GroupUnitTags = {} -- preassemble unit tags

for i = 1, GROUP_SIZE_MAX do
	GroupUnitTags[i] = ZO_CachedStrFormat("group<<1>>", i)
end
libunits.GroupUnitTags = GroupUnitTags

local BossUnitTags = {} -- preassemble unit tags
for i = 1, MAX_BOSSES do
	BossUnitTags[i] = ZO_CachedStrFormat("boss<<1>>", i)
end

local PetUnitTags = {} -- preassemble unit tags

for i = 1, MAX_PET_UNIT_TAGS do
	PetUnitTags[i] = ZO_CachedStrFormat("playerpet<<1>>", i)
end

local function onGroupChange()
	libunits.inGroup = IsUnitGrouped("player")
	libunits.groupTagByName = {}

	if libunits.inGroup == true then
		local groupTagByName = libunits.groupTagByName

		for i = 1, GetGroupSize() do
			local unitTag = GroupUnitTags[i]

			if DoesUnitExist(unitTag) == true and AreUnitsEqual(unitTag, "player") == false then
				local rawName = GetUnitName(unitTag)
				groupTagByName[rawName] = unitTag
			end
		end
	end
end

local hasMultipleTags = "multiple tags found"

local function onBossesChanged(_) -- Detect Bosses
	local bossTagByName = {}      -- holds only bosses discovered in this round

	for i = 1, MAX_BOSSES do
		local unitTag = BossUnitTags[i]

		if DoesUnitExist(unitTag) then
			local rawName = GetUnitName(unitTag)

			if bossTagByName[rawName] and bossTagByName[rawName] ~= unitTag then
				logger:Warn("Multiple tags found for %s (%s, %s)", rawName, bossTagByName[rawName], unitTag)
				bossTagByName[rawName] = hasMultipleTags
			end

			libunits.bossTagByName[rawName] = bossTagByName[rawName]
		end
	end
end
lf.onBossesChanged = onBossesChanged

local function onPlayerPetsChanged(_) -- TODO: figure out when to call this
	local petTagByName = libunits.petTagByName

	for i = 1, MAX_PET_UNIT_TAGS do
		local unitTag = PetUnitTags[i]

		if DoesUnitExist(unitTag) == true then
			local rawName = GetUnitName(unitTag)
			petTagByName[rawName] = unitTag
		end
	end
end

local unitDetectionResults = { -- valid values of result from combat events to determine info from
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

local function OnCombatEvent(eventCode, result, _, _, _, _, sourceName, sourceType, targetName, targetType, _, _, _, _,
							 sourceUnitId, targetUnitId, _, _)
	if not unitDetectionResults[result] then return end

	if IsValidUnitData(sourceName, sourceUnitId, sourceType) then
		if UnitCache[sourceUnitId] == nil then
			UnitHandler:New(sourceName, sourceUnitId, sourceType)
		else
			UnitCache[sourceUnitId]:Update(sourceName, sourceType)
		end
	end

	if IsValidUnitData(targetName, targetUnitId, targetType) then
		if UnitCache[targetUnitId] == nil then
			UnitHandler:New(targetName, targetUnitId, targetType)
		else
			UnitCache[targetUnitId]:Update(targetName, targetType)
		end
	end
end

local function GetUnitTypeFromTag(unitTag)
	if unitTag == "player" then
		return COMBAT_UNIT_TYPE_PLAYER
	elseif unitTag == "companion" then
		return COMBAT_UNIT_TYPE_PLAYER_COMPANION
	elseif string.sub(unitTag, 1, 9) == "playerpet" then
		return COMBAT_UNIT_TYPE_PLAYER_PET
	elseif string.sub(unitTag, 1, 4) == "boss" then
		return COMBAT_UNIT_TYPE_OTHER
	elseif string.sub(unitTag, 1, 5) == "group" then
		if string.len(unitTag) < 8 then
			return COMBAT_UNIT_TYPE_GROUP
		else
			return COMBAT_UNIT_TYPE_GROUP_COMPANION
		end
	else
		return nil
	end
end

local function OnTargetChange()
	if not DoesUnitExist("reticleover") then
		if libunits.unitIdsByTag["reticleover"] then
			UpdateUnitTagId("reticleover", nil)
			logger:Debug("ReticleOverUnit removed.")
		end

		return
	end
	local numBuffs = GetNumBuffs("reticleover")
	if numBuffs == 0 then return end

	for i = 1, numBuffs do
		local _, _, endTime, buffSlot, _, _, _, _, _, _, abilityId, _ = GetUnitBuffInfo("reticleover", i)
		local unitId = EffectCache[abilityId] and EffectCache[abilityId][endTime] or nil
		local unit = unitId and UnitCache[unitId] or nil

		if unit and unit.effectTimeData[buffSlot] == endTime then
			logger:Debug("ReticleOverUnit found: %s (%d)", unit.name, unitId)
			unit:UpdateUnitTag("reticleover")
			return
		end
	end

	logger:Debug("ReticleOverUnit not found: %s (%d buffs)", GetUnitName("reticleover"), numBuffs)
end

local function OnEffectChanged(_, changeType, effectSlot, _, unitTag, _, endTime, _, _, _, effectType, _, _, unitName,
							   unitId, abilityId, _)
	local unitType = GetUnitTypeFromTag(unitTag)
	if IsValidUnitData(unitName, unitId, unitType) then -- Allow even if unitType is not known?
		if UnitCache[unitId] == nil then
			UnitHandler:New(unitName, unitId, unitType, unitTag)
		else
			UnitCache[unitId]:Update(unitName, unitType, unitTag)
		end
	end

	if (changeType ~= EFFECT_RESULT_GAINED and changeType ~= EFFECT_RESULT_FADED and changeType ~= EFFECT_RESULT_UPDATED) or
		(effectType ~= BUFF_EFFECT_TYPE_BUFF and effectType ~= BUFF_EFFECT_TYPE_DEBUFF) then
		return
	end

	if IsValidUnitId(unitId) and UnitCache[unitId] then
		UnitCache[unitId]:UpdateEffectData(abilityId, changeType, endTime,
			effectSlot)
	end

	OnTargetChange()
end


local function onTrialDummy(_, _, _, _, _, _, _, _, _, _, _, _, _, _, sourceUnitId, _, _, _) -- TODO: this
	logger:Debug("Trial Dummy Detected: %d", sourceUnitId)

	-- UnitCache[sourceUnitId]:UpdateTrialDummy() #TODO: Add this function back in
end

-- UnitHandler
---@class UnitHandler 
UnitHandler = ZO_InitializingObject:Subclass() -- internal object to store everything about a unit

---@diagnostic disable-next-line: duplicate-set-field
function UnitHandler:Initialize(rawName, unitId, unitType, unitTag)
	if unitType == COMBAT_UNIT_TYPE_PLAYER then UpdatePlayerId(unitId) end

	local name          = ZO_CachedStrFormat(SI_UNIT_NAME, rawName) -- name

	self.unitId         = unitId
	self.name           = name
	self.rawName        = rawName
	self.unitType       = unitType -- type of unit: player, group, pet, companion, group_companion or boss
	self.effectData     = {}
	self.effectTimeData = {}

	self:UpdateFriendlyStatus()

	if (unitTag == nil or unitTag == "") then self:LookupUnitTag() end

	local UnitIdByRawName = libunits.unitIdsByRawName
	local UnitIdByName = libunits.unitIdsByName

	if UnitIdByRawName[rawName] then table.insert(UnitIdByRawName[rawName], unitId) else UnitIdByRawName[rawName] = {
			unitId } end
	if UnitIdByName[name] then table.insert(UnitIdByName[name], unitId) else UnitIdByName[name] = { unitId } end

	self:UpdateUnitTag(unitTag)

	self.firstSeen = GetGameTimeSeconds()
	self.lastSeen = GetGameTimeSeconds()

	UnitCache[unitId] = self

	logger:Debug("New Unit: %s (%d, %d, %s)", name, unitId, unitType, unitTag or "")
end

function UnitHandler:LookupUnitTag()
	if self.unitType == nil then return end

	if self.unitType == COMBAT_UNIT_TYPE_PLAYER then
		self:UpdateUnitTag("player")
	elseif self.unitType == COMBAT_UNIT_TYPE_GROUP then
		self:UpdateUnitTag(libunits.groupTagByName[self.rawName]) -- Todo: Group Companion?
	elseif self.unitType == COMBAT_UNIT_TYPE_PLAYER_PET then
		self:UpdateUnitTag(libunits.petTagByName[self.rawName])
	else
		CheckForPetUnit(self.rawName, self.unitId)
		local bossTag = libunits.bossTagByName[self.rawName]

		if bossTag then
			self.isBoss = true
			if bossTag ~= hasMultipleTags then
				self:UpdateUnitTag(bossTag)
			end
		end
	end
end

local friendlyUnitTypes = {
	[COMBAT_UNIT_TYPE_PLAYER] = true,
	[COMBAT_UNIT_TYPE_PLAYER_COMPANION] = true,
	[COMBAT_UNIT_TYPE_GROUP] = true,
	[COMBAT_UNIT_TYPE_GROUP_COMPANION] = true,
	[COMBAT_UNIT_TYPE_PLAYER_PET] = true,
}

function UnitHandler:UpdateFriendlyStatus()
	self.isFriendly = friendlyUnitTypes[self.unitType] == true
end

function UnitHandler:Update(rawName, unitType, unitTag)
	self.lastSeen = GetGameTimeSeconds()

	if self.rawName ~= rawName then
		local unitId = self.unitId
		self:Delete()
		local unit = UnitHandler:New(rawName, unitId, unitType, unitTag)

		return
	end

	if unitTag then self:UpdateUnitTag(unitTag) end

	if unitType and self.unitType ~= unitType then
		logger.Debug("unitType changed: %d -> %d %s (%d)", self.unitType, unitType, self.name, self.unitId)
		self.unitType = unitType
		self:UpdateFriendlyStatus()
	end
end

function UnitHandler:UpdateUnitTagData(unitTag)
	-- General
	UnitHandler:ValidateUnitTagUpdate("gender", GetUnitGender(unitTag))
	UnitHandler:ValidateUnitTagUpdate("maxHealth", GetUnitPower(unitTag, COMBAT_MECHANIC_FLAGS_HEALTH))

	-- Player characters	TODO: check classification
	UnitHandler:ValidateUnitTagUpdate("displayName", GetUnitDisplayName(unitTag))
	UnitHandler:ValidateUnitTagUpdate("class", GetUnitClass(unitTag))
	UnitHandler:ValidateUnitTagUpdate("classId", GetUnitClassId(unitTag))
	UnitHandler:ValidateUnitTagUpdate("CP", GetUnitChampionPoints(unitTag))
	UnitHandler:ValidateUnitTagUpdate("effectiveCP", GetUnitEffectiveChampionPoints(unitTag))
	UnitHandler:ValidateUnitTagUpdate("effectiveLevel", GetUnitEffectiveLevel(unitTag))

	-- Status
	UnitHandler:ValidateUnitTagUpdate("isDead", IsUnitDead(unitTag))
	UnitHandler:ValidateUnitTagUpdate("isReincarnating", IsUnitReincarnating(unitTag))
	UnitHandler:ValidateUnitTagUpdate("isAlive", not IsUnitDeadOrReincarnating(unitTag))

	-- TODO: check limitations and only update necessary values
	-- TODO: check not to overwrite data
	-- TODO: Add more data from unitTag if possible
end

function UnitHandler:ValidateUnitTagUpdate(key, value)
	if value == nil then return end
	if type(value) == "string" then
		if value == "" then return end
	end
	if type(value) == "number" then
		if value == 0 then return end
	end

	self[key] = value
end

function UnitHandler:UpdateUnitTag(newUnitTag)
	if newUnitTag == nil or newUnitTag == "" or (self.unitTags and self.unitTags[newUnitTag]) then return end

	local unitId = self.unitId
	self:UpdateUnitTagData(newUnitTag)

	if self.unitTags == nil then
		self.unitTags = { [newUnitTag] = newUnitTag }
		UpdateUnitTagId(newUnitTag, unitId)
	else
		for unitTag, _ in pairs(self.unitTags) do
			if AreUnitsEqual(unitTag, newUnitTag) == false then
				self.unitTags[unitTag] = nil -- this tag doesn't belong to this unit
				if libunits.unitIdsByTag[unitTag] == unitId then libunits.unitIdsByTag[unitTag] = nil end
			end
		end

		self.unitTags[newUnitTag] = newUnitTag
		UpdateUnitTagId(newUnitTag, unitId)
	end
end

function UnitHandler:RemoveUnitTag(unitTag)
	self.unitTags[unitTag] = nil
end

function UnitHandler:Delete()
	UnitCache[self.unitId] = nil
	UnitExportCache[self.unitId] = nil

	if self.unitTags then
		for _, unitTag in pairs(self.unitTags) do
			if self.unitId == libunits.unitIdsByTag[unitTag] then libunits.unitIdsByTag[unitTag] = nil end
		end
	end

	for i, unitId in ipairs(libunits.unitIdsByRawName) do
		if unitId == self.unitId then
			table.remove(libunits.unitIdsByRawName, i)
			table.remove(libunits.unitIdsByName, i)
			break
		end
	end

	for effectSlot, abilityId in pairs(self.effectData) do -- remove cached effects
		local endTime = self.effectTimeData[effectSlot]

		if EffectCache[abilityId] and EffectCache[abilityId][endTime] then EffectCache[abilityId][endTime] = nil end
	end
end

function UnitHandler:UpdateEffectData(abilityId, changeType, endTime, effectSlot)
	local effectData = self.effectData
	local effectTimeData = self.effectTimeData

	if changeType == EFFECT_RESULT_GAINED or changeType == EFFECT_RESULT_UPDATED then
		effectData[effectSlot]          = abilityId -- effectSlot should be unique per unit
		effectTimeData[effectSlot]      = endTime

		EffectCache[abilityId]          = EffectCache[abilityId] or {}
		EffectCache[abilityId][endTime] = self.unitId
	elseif changeType == EFFECT_RESULT_FADED then
		effectData[effectSlot] = nil
		effectTimeData[effectSlot] = nil

		if EffectCache[abilityId] and EffectCache[abilityId][endTime] then EffectCache[abilityId][endTime] = nil end
	end
end

function UnitHandler:SetTrialDummy()
	self.isTrialdummy = true
end

-- Unit object for exporting info

---@class UnitAPIHandler 
local UnitAPIHandler = ZO_InitializingObject:Subclass() -- object to expose data about units

---@diagnostic disable-next-line: duplicate-set-field
function UnitAPIHandler:Initialize(unitId)
	if unitId == nil then logger:Error("No unit Id!") return end
	if UnitCache[unitId] == nil then logger:Info("Unit %d is not known!", unitId) return end
	-- TODO: Add safeguard if unit is unkown!
	self.unitId = unitId

	UnitExportCache[unitId] = self
end

---@return UnitData?
function UnitAPIHandler:GetFullUnitData()
	if self.unitId == nil then return end

	---@class UnitData
	local unitData = {
		unitId     = self.unitId,
		name       = self:GetUnitName(),
		rawName    = self:GetUnitRawName(),
		unitType   = self:GetUnitType(),
		unitTags   = self:GetUnitTags(),
		isBoss     = self:IsBoss(),
		isFriendly = self:IsFriendly(),
		maxHealth  = self:GetMaxHealth(),
	}

	return unitData
end

function UnitAPIHandler:GetUnitName()
	return UnitCache[self.unitId].name
end

function UnitAPIHandler:GetUnitRawName()
	return UnitCache[self.unitId].rawName
end

function UnitAPIHandler:GetUnitType()
	return UnitCache[self.unitId].unitType
end

function UnitAPIHandler:GetUnitTags()
	return UnitCache[self.unitId].unitTags
end

function UnitAPIHandler:IsBoss()
	return UnitCache[self.unitId].isBoss
end

function UnitAPIHandler:IsFriendly()
	return UnitCache[self.unitId].isFriendly
end

function UnitAPIHandler:GetMaxHealth()
	return UnitCache[self.unitId].maxHealth
end

local function GetExportUnit(unitId)
	return UnitExportCache[unitId] or UnitAPIHandler:New(unitId)
end

-- API

function lib.GetUnitIdByTag(unitTag)
	return libunits.unitIdsByTag[unitTag]
end

function lib.GetUnitByTag(unitTag)
	local unitId = lib.GetUnitIdByTag(unitTag)

	return GetExportUnit(unitId)
end

function lib.GetUnitsByName(unitName)
	local unitIds = libunits.unitIdsByName[unitName]

	local units = {}

	for i, unitId in ipairs(unitIds) do
		units[i] = GetExportUnit(unitId)
	end

	return unpack(units)
end

function lib.GetUnitIdsByName(unitName)
	return unpack(libunits.unitIdsByName[unitName])
end

function lib.GetUnitsByRawName(unitName)
	local unitIds = libunits.unitIdsByRawName[unitName]

	local units = {}
	for i, unitId in ipairs(unitIds) do
		units[i] = GetExportUnit(unitId)
	end

	return unpack(units)
end

function lib.GetUnitIdsByRawName(unitName)
	return unpack(libunits.unitIdsByRawName[unitName])
end

---comment
---@param unitId integer
---@return UnitAPIHandler
function lib.GetUnitById(unitId)
	return GetExportUnit(unitId)
end

-- Debug Utilities
local logBase = math.log(5)

local function GetUnitSummary() -- gives a list of all units with names and id and the last seen time:
	local unitData = {}
	local now      = GetGameTimeSeconds()

	for unitId, unit in pairs(UnitCache) do
		unitData[unitId] = {
			["unitName"] = unit.name,
			["lastSeenRange"] = math.log(now - unit.lastSeen) / logBase,
		}
	end

	return unitData
end

local function InitDebugPanel()
	local tlw = wm:CreateTopLevelWindow("LCUDebugPanel")
	local bg = wm:CreateControl("Bg", tlw, CT_BACKDROP)
	wm:ApplyTemplateToControl(bg, "ZO_EditBackdrop")
	local textbox = wm:CreateControl("TextBox", tlw, CT_EDITBOX)
	wm:ApplyTemplateToControl(textbox, "ZO_DefaultEditForBackdrop")
	wm:ApplyTemplateToControl(textbox, "ZO_EditDefaultText")

	tlw:SetMouseEnabled(true)
	tlw:SetMovable(true)
	tlw:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, 0, 0)
	tlw:SetDimensions(500, 1000)

	bg:SetAnchorFill(tlw)

	---@cast textbox EditControl
	textbox:SetAnchorFill(tlw)
	textbox:SetMultiLine(true)
	textbox:SetNewLineEnabled(true)
	textbox:SetAllowMarkupType(ALLOW_MARKUP_TYPE_ALL)
	textbox:SetFont("$(MEDIUM_FONT)|$(KB_14)")
	textbox:SetText("TEST TEST \n TEST", true)
	textbox:SetMaxInputChars(10000)
	textbox:SetMouseEnabled(false)

	local debugPanel = libunits.debugPanel
	debugPanel.tlw = tlw
	debugPanel.textbox = textbox
	debugPanel.init = true
end

local function UnitSummaryOrder(table, a, b)
	local ishigher = false

	local lastSeenRangeA = table[a].lastSeenRange * 10
	local lastSeenRangeB = table[b].lastSeenRange * 10

	if lastSeenRangeB - lastSeenRangeA > 0.1 then
		ishigher = true
	elseif zo_abs(lastSeenRangeA - lastSeenRangeB) < 0.1 then
		ishigher = b > a
	end

	return ishigher
end

local typeStrings = {
	[COMBAT_UNIT_TYPE_NONE] = "npc",
	[COMBAT_UNIT_TYPE_PLAYER] = "player",
	[COMBAT_UNIT_TYPE_PLAYER_PET] = "pet",
	[COMBAT_UNIT_TYPE_GROUP] = "group",
	[COMBAT_UNIT_TYPE_OTHER] = "other",
	[COMBAT_UNIT_TYPE_TARGET_DUMMY] = "dummy",
	[COMBAT_UNIT_TYPE_PLAYER_COMPANION] = "companion",
	[COMBAT_UNIT_TYPE_GROUP_COMPANION] = "companion",
}

local function UpdateDebugPanel()
	local unitData = GetUnitSummary()
	local now = GetGameTimeSeconds()
	local stringArray = {}
	local lines = 0

	for unitId, unitData in spairs(unitData, UnitSummaryOrder) do
		local unit = UnitCache[unitId]

		local g = (4 - zo_min(zo_max(2, unitData.lastSeenRange), 4)) / 2
		local r = zo_min(zo_max(1, unitData.lastSeenRange), 2) - 1

		local tags = {}

		for unitTag, _ in pairs(unit.unitTags or {}) do
			tags[#tags + 1] = unitTag
		end

		local tags = table.concat(tags, ", ")
		local type = typeStrings[unit.unitType]

		local string = string.format("%s (%d, %s, %s): %.1f", unit.name, unitId, type, tags, now - unit.lastSeen)

		stringArray[#stringArray + 1] = string.format("|c%.2x%.2x%.2x%s|r", zo_floor(r * 255), zo_floor(g * 255), 0,
			string)

		lines = lines + 1

		if lines >= 40 then break end
	end

	local fullstring = table.concat(stringArray, "\n")

	libunits.debugPanel.textbox:SetText(fullstring)
end

function libunits.toggleDebug(override)
	libunits.debug = override or (not libunits.debug)

	if libunits.debug then
		if libunits.debugPanel.init == false then InitDebugPanel() end
		libunits.debugPanel.tlw:SetHidden(false)
		em:RegisterForUpdate("LCU_DebugPanel", 500, UpdateDebugPanel)
	else
		libunits.debugPanel.tlw:SetHidden(true)
		em:UnregisterForUpdate("LCU_DebugPanel")
	end

	libunits.debugPanel.tlw:SetHidden(not libunits.debug)
end

-- Init

libint.Events.Units = libint.EventHandler:New(
	lf.GetAllCallbackTypes(),
	function(self)
		self:RegisterEvent(EVENT_COMBAT_EVENT, OnCombatEvent)
		self:RegisterEvent(EVENT_EFFECT_CHANGED, OnEffectChanged)
		self:RegisterEvent(EVENT_RETICLE_TARGET_CHANGED, OnTargetChange)

		self:RegisterEvent(EVENT_GROUP_UPDATE, onGroupChange)
		self:RegisterEvent(EVENT_PLAYER_ACTIVATED, onGroupChange)
		self:RegisterEvent(EVENT_BOSSES_CHANGED, onBossesChanged)
		self:RegisterEvent(EVENT_PLAYER_ACTIVATED, onBossesChanged)

		self:RegisterEvent(EVENT_EFFECT_CHANGED, onBossesChanged, REGISTER_FILTER_ABILITY_ID, 108045) -- Rescan bosses on certain portal use
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onBossesChanged, REGISTER_FILTER_ABILITY_ID, 121216) -- Rescan bosses on certain portal use

		EVENT_MANAGER:RegisterForUpdate("LibCombat_PetStatus", 500, onPlayerPetsChanged) --  TODO: find better way to determine if pets changed
		self:RegisterEvent(EVENT_COMBAT_EVENT, onTrialDummy, REGISTER_FILTER_ABILITY_ID, 120024,
			REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_EFFECT_GAINED, REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE,
			COMBAT_UNIT_TYPE_TARGET_DUMMY, REGISTER_FILTER_IS_ERROR, false)

		self.active = true
	end
)

local isFileInitialized = false

function libint.InitializeUnits()
	if isFileInitialized == true then return false end
	logger = lf.initSublogger("units")

	libunits.rawPlayername = GetRawUnitName("player")
	libunits.playername = ZO_CachedStrFormat(SI_UNIT_NAME, libunits.rawPlayername)
	libunits.accountname = ZO_CachedStrFormat(SI_UNIT_NAME, GetDisplayName())
	libunits.inGroup = IsUnitGrouped("player")

	onBossesChanged()

	SLASH_COMMANDS["/lcudebug"] = libunits.toggleDebug

	isFileInitialized = true
	return true
end
