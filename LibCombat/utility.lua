local lib = LibCombat
local libint = lib.internal
local lf = libint.functions
local logger

---@class Queue
local Queue = ZO_InitializingObject:Subclass()

function Queue:Initialize()
	self.first = 0
	self.last = -1
end

function Queue:Push(value) -- https://www.lua.org/pil/11.4.html
	local last = self.last + 1
	self.last = last
	self[last] = value
end

function Queue:Pop()
	if self:IsEmpty() then logger:error("Queue is empty") end
	local first = self.first
	local value = self[first]
	self[first] = nil
	self.first = first + 1
	return value
end

function Queue:Delete(index)
	if self:IsEmpty() then logger:error("Queue is empty") end
	if index == self.first then return self:Pop() end

	self.last = self.last - 1
	return table.remove(self, index) -- TODO: This is a bit hacky. Maybe review
end

function Queue:IsEmpty()
	return self.first > self.last
end

---comment
---@return Queue
function lf.CreateQueue()
	return Queue:New()
end
-- Cache formatted Ability Names and Icons. Makes sure they stay consistent, since some addons like to meddle with them.

local CustomAbilityName = {
	[-1] = "Unknown", -- Whenever there is no known abilityId
	[-2] = "Unknown", -- Whenever there is no known abilityId

	[0] = GetString(SI_LIBCOMBAT_LOG_BASEREG), -- Whenever there is no known abilityId

	[75753] = zo_strformat(SI_ABILITY_NAME, GetAbilityName(75753)), -- Line-breaker (Alkosh). pin abiltiy name so it can't get overridden
	[17906] = zo_strformat(SI_ABILITY_NAME, GetAbilityName(17906)), -- Crusher (Glyph). pin abiltiy name so it can't get overridden
	[62988] = zo_strformat(SI_ABILITY_NAME, GetAbilityName(62988)), -- Off-Balance

	[81274] = "(C) " .. zo_strformat(SI_ABILITY_NAME, GetAbilityName(81274)), -- Crown Store Poison, Rename to differentiate from normal Poison, which can apparently stack ?
	[81275] = "(C) " .. zo_strformat(SI_ABILITY_NAME, GetAbilityName(81275)), -- Crown Store Poison, Rename to differentiate from normal Poison, which can apparently stack ?

	[113382] = zo_strformat(SI_LIBCOMBAT_CUSTOM_ABILITY_FORMAT, GetAbilityName(113382), GetString(SI_LIBCOMBAT_LOG_DEBUFF)), -- To make sure that tracking works correctly since both buff and debuff are named the same.

	[61901] = zo_strformat(SI_LIBCOMBAT_CUSTOM_ABILITY_FORMAT, GetAbilityName(61901), GetString(SI_ABILITY_TOOLTIP_TOGGLE_DURATION)),	-- Grim Focus Toggle
	[61919] = zo_strformat(SI_LIBCOMBAT_CUSTOM_ABILITY_FORMAT, GetAbilityName(61919), GetString(SI_ABILITY_TOOLTIP_TOGGLE_DURATION)),	-- Merciless Resolve Toggle
	[61927] = zo_strformat(SI_LIBCOMBAT_CUSTOM_ABILITY_FORMAT, GetAbilityName(61927), GetString(SI_ABILITY_TOOLTIP_TOGGLE_DURATION)),	-- Relentless Focus Toggle

	[122729] = zo_strformat(SI_LIBCOMBAT_CUSTOM_ABILITY_FORMAT, GetAbilityName(122729), GetString(SI_LIBCOMBAT_LOG_BUFF)), --  Name for separate stats buff of Seething Fury
}

local CustomAbilityIcon = {
	[0] = "esoui/art/icons/achievement_wrothgar_046.dds",
	[122729] = "esoui/art/icons/ability_warrior_025.dds",
	[libint.abilityIdForceOfNature] = "esoui/art/icons/ability_healer_018.dds",
}

function lib.AddCustomAbilityData(names, icons)
	for id, name in names do
		CustomAbilityName[id] = zo_strformat(SI_ABILITY_NAME, name)
	end

	for id, icon in icons do
		CustomAbilityIcon[id] = icon
	end
end


local AbilityNameCache = {}
local ScriptNameCache = {}

---Function to return cached and formatted ability and script names. 
---@param id any
---@param isScript? boolean
---@return string name
local function GetFormattedAbilityName(id, isScript)
	if id == nil then return "" end
	local cache = isScript and ScriptNameCache or AbilityNameCache
	local name = cache[id]

	if name == nil then
		if isScript then
			name = GetCraftedAbilityScriptDisplayName(id)
		else
			name =  CustomAbilityName[id] or GetAbilityName(id)
		end
		if name == "Off-Balance" then name = "Off Balance" end
		cache[id] = name
	end

	return name
end
lib.GetFormattedAbilityName = GetFormattedAbilityName

local AbilityIconCache = {}
local ScriptIconCache = {}
local noIcon = "/esoui/art/icons/icon_missing.dds"
local noScriptIcon = "EsoUI/Art/crafting/gamepad/crafting_alchemy_trait_unknown.dds"

---Function to return cached and formatted ability and script icons. 
---@param id unknown
---@param isScript? boolean
---@return string texturePath
local function GetFormattedAbilityIcon(id, isScript)
	if id == nil then return noIcon
	elseif type(id) == "string" then return id
	elseif isScript and id == 0 then return noScriptIcon
	end

	local cache = isScript and ScriptIconCache or AbilityIconCache
	local icon = cache[id]

	if icon == nil then
		if isScript then
			icon = GetCraftedAbilityScriptIcon(id)
		else
			icon =  CustomAbilityIcon[id] or GetAbilityIcon(id)
		end
		cache[id] = icon
	end

	return icon
end
lib.GetFormattedAbilityIcon = GetFormattedAbilityIcon

-- Combat log generator
local statStrings = {

	[LIBCOMBAT_STAT_MAXMAGICKA]			= "|c8888ff"..GetString(SI_DERIVEDSTATS4).."|r ", 							--|c8888ff blue
	[LIBCOMBAT_STAT_SPELLPOWER]			= "|c8888ff"..GetString(SI_DERIVEDSTATS25).."|r ",
	[LIBCOMBAT_STAT_SPELLCRIT]			= "|c8888ff"..GetString(SI_DERIVEDSTATS23).."|r ",
	[LIBCOMBAT_STAT_SPELLCRITBONUS]		= "|c8888ff"..GetString(SI_LIBCOMBAT_LOG_STAT_SPELL_CRIT_DONE).."|r ",
	[LIBCOMBAT_STAT_SPELLPENETRATION]	= "|c8888ff"..GetString(SI_DERIVEDSTATS34).."|r ",

	[LIBCOMBAT_STAT_MAXSTAMINA]			= "|c88ff88"..GetString(SI_DERIVEDSTATS29).."|r ",							--|c88ff88 green
	[LIBCOMBAT_STAT_WEAPONPOWER]		= "|c88ff88"..GetString(SI_DERIVEDSTATS1).."|r ",
	[LIBCOMBAT_STAT_WEAPONCRIT]			= "|c88ff88"..GetString(SI_DERIVEDSTATS16).."|r ",
	[LIBCOMBAT_STAT_WEAPONCRITBONUS]	= "|c88ff88"..GetString(SI_LIBCOMBAT_LOG_STAT_WEAPON_CRIT_DONE).."|r ",
	[LIBCOMBAT_STAT_WEAPONPENETRATION]	= "|c88ff88"..GetString(SI_DERIVEDSTATS33).."|r ",

	[LIBCOMBAT_STAT_MAXHEALTH]			= "|cffff88"..GetString(SI_DERIVEDSTATS7).."|r ",							--|cffff88 red
	[LIBCOMBAT_STAT_PHYSICALRESISTANCE]	= "|cffff88"..GetString(SI_DERIVEDSTATS22).."|r ",
	[LIBCOMBAT_STAT_SPELLRESISTANCE]	= "|cffff88"..GetString(SI_DERIVEDSTATS13).."|r ",
	[LIBCOMBAT_STAT_CRITICALRESISTANCE]	= "|cffff88"..GetString(SI_DERIVEDSTATS24).."|r ",
}

local logColors = {

	[DAMAGE_TYPE_NONE] 		= "|cE6E6E6",
	[DAMAGE_TYPE_GENERIC] 	= "|cE6E6E6",
	[DAMAGE_TYPE_PHYSICAL] 	= "|cf4f2e8",
	[DAMAGE_TYPE_FIRE] 		= "|cff6600",
	[DAMAGE_TYPE_SHOCK] 	= "|cffff66",
	[DAMAGE_TYPE_OBLIVION] 	= "|cd580ff",
	[DAMAGE_TYPE_COLD] 		= "|cb3daff",
	[DAMAGE_TYPE_EARTH] 	= "|cbfa57d",
	[DAMAGE_TYPE_MAGIC] 	= "|c9999ff",
	[DAMAGE_TYPE_DROWN] 	= "|ccccccc",
	[DAMAGE_TYPE_DISEASE] 	= "|cc48a9f",
	[DAMAGE_TYPE_POISON] 	= "|c9fb121",
	[DAMAGE_TYPE_BLEED] 	= "|cc20a38",
	["heal"]				= "|c55ff55",
	["buff"]				= "|c00cc00",
	["debuff"]				= "|cff3333",
	["resource"]			= "|cffffff",
}

function lib.GetDamageColor(damageType)
	return logColors[damageType]
end

local function GetAbilityString(abilityId, damageType, fontsize, showIds, stacks)

	local stacks = stacks or 0

	local icon = zo_iconFormat(GetFormattedAbilityIcon(abilityId), fontsize, fontsize)
	local name = GetFormattedAbilityName(abilityId)
	local damageColor = lib.GetDamageColor(damageType)

	local format = abilityId == libint.abilityIdZen and "<<5[/$dx /$dx ]>><<1>> <<2>><<3>><<4[/ ($d)/ ($d)]>>|r" or "<<5[//$dx ]>><<1>> <<2>><<3>><<4[/ ($d)/ ($d)]>>|r"
	local abilityString = ZO_CachedStrFormat(format, icon, damageColor, name, showIds and abilityId or 0, stacks)


	return abilityString
end

local UnitTypeString = {
	[COMBAT_UNIT_TYPE_PLAYER] 		= GetString(SI_LIBCOMBAT_LOG_UNITTYPE_PLAYER),
	[COMBAT_UNIT_TYPE_PLAYER_PET] 	= GetString(SI_LIBCOMBAT_LOG_UNITTYPE_PET),
	[COMBAT_UNIT_TYPE_GROUP] 		= GetString(SI_LIBCOMBAT_LOG_UNITTYPE_GROUP),
	[COMBAT_UNIT_TYPE_OTHER] 		= GetString(SI_LIBCOMBAT_LOG_UNITTYPE_OTHER),
}

function lib:GetCombatLogString(fight, logline, fontsize, showIds)
	if fight == nil then fight = libint.currentfight end

	local logtype = logline[1]
	local color, text

	local timeValue = fight.combatstart < 0 and 0 or (logline[2] - fight.combatstart)/1000
	local timeString = string.format("|ccccccc[%.3fs]|r", timeValue)
	local logFormat = GetString("SI_LIBCOMBAT_LOG_FORMATSTRING", logtype)

	local units = fight.units

	if logtype == LIBCOMBAT_LOG_EVENT_DAMAGE then
		local _, _, result, _, targetUnitId, abilityId, hitValue, damageType, overflow = unpack(logline)
		overflow = overflow or 0

		local crit = (result == ACTION_RESULT_CRITICAL_DAMAGE or result == ACTION_RESULT_DOT_TICK_CRITICAL) and ZO_CachedStrFormat("|cFFCC99<<1>>|r", GetString(SI_LIBCOMBAT_LOG_CRITICAL)) or ""
		local targetname = units[targetUnitId].name
		local targetFormat = (result == ACTION_RESULT_BLOCKED_DAMAGE and SI_LIBCOMBAT_LOG_FORMAT_TARGET_BLOCK) or SI_LIBCOMBAT_LOG_FORMAT_TARGET_NORMAL
		local targetString = ZO_CachedStrFormat(GetString(targetFormat), targetname)
		local ability = GetAbilityString(abilityId, damageType, fontsize, showIds)
		local hitValueString = overflow > 0 and ZO_CachedStrFormat(GetString(SI_LIBCOMBAT_LOG_FORMAT_ABSORBED), hitValue, overflow) or hitValue

		color = {1.0,0.6,0.6}
		text = ZO_CachedStrFormat(logFormat, timeString, crit, targetString, ability, hitValueString)

	elseif logtype == LIBCOMBAT_LOG_EVENT_DAMAGE then
		local _, _, result, sourceUnitId, _, abilityId, hitValue, damageType, overflow = unpack(logline)
		overflow = overflow or 0

		local crit = (result == ACTION_RESULT_CRITICAL_DAMAGE or result == ACTION_RESULT_DOT_TICK_CRITICAL) and ZO_CachedStrFormat("|cFFCC99<<1>>|r", GetString(SI_LIBCOMBAT_LOG_CRITICAL)) or ""
		local sourceName = units[sourceUnitId].name
		local targetFormat = (result == ACTION_RESULT_BLOCKED_DAMAGE and SI_LIBCOMBAT_LOG_FORMAT_TARGETSELF_BLOCK) or SI_LIBCOMBAT_LOG_FORMAT_TARGETSELF_NORMAL
		local targetString = GetString(targetFormat)
		local ability = GetAbilityString(abilityId, damageType, fontsize, showIds)
		local hitValueString = overflow > 0 and ZO_CachedStrFormat(GetString(SI_LIBCOMBAT_LOG_FORMAT_ABSORBED), hitValue, overflow) or hitValue

		color = {0.8,0.4,0.4}
		text = ZO_CachedStrFormat(logFormat, timeString, sourceName, crit, targetString, ability, hitValueString)

	elseif logtype == LIBCOMBAT_LOG_EVENT_DAMAGE then
		local _, _, result, _, _, abilityId, hitValue, damageType, overflow = unpack(logline)
		overflow = overflow or 0

		local crit = (result == ACTION_RESULT_CRITICAL_HEAL or result == ACTION_RESULT_HOT_TICK_CRITICAL) and ZO_CachedStrFormat("|cFFCC99<<1>>|r", GetString(SI_LIBCOMBAT_LOG_CRITICAL)) or ""
		local targetFormat = (result == ACTION_RESULT_BLOCKED_DAMAGE and SI_LIBCOMBAT_LOG_FORMAT_TARGETSELF_BLOCK) or SI_LIBCOMBAT_LOG_FORMAT_TARGETSELF_SELF
		local targetString = GetString(targetFormat)
		local ability = GetAbilityString(abilityId, damageType, fontsize)
		local hitValueString = overflow > 0 and ZO_CachedStrFormat(GetString(SI_LIBCOMBAT_LOG_FORMAT_ABSORBED), hitValue, overflow) or hitValue

		color = {0.8,0.4,0.4}
		text = ZO_CachedStrFormat(logFormat, timeString, crit, targetString, ability, hitValueString)

	elseif logtype == LIBCOMBAT_LOG_EVENT_HEAL then
		local _, _, result, _, targetUnitId, abilityId, hitValue, _, _ = unpack(logline)

		local crit = (result == ACTION_RESULT_CRITICAL_HEAL or result == ACTION_RESULT_HOT_TICK_CRITICAL) and ZO_CachedStrFormat("|cFFCC99<<1>>|r", GetString(SI_LIBCOMBAT_LOG_CRITICAL)) or ""
		local targetname = units[targetUnitId].name
		local ability = GetAbilityString(abilityId, "heal", fontsize, showIds)

		color = {0.6,1.0,0.6}
		text = ZO_CachedStrFormat(logFormat, timeString, crit, targetname, ability, hitValue)

	elseif logtype == LIBCOMBAT_LOG_EVENT_HEAL then
		local _, _, result, sourceUnitId, _, abilityId, hitValue, _, _  = unpack(logline)

		local crit = (result == ACTION_RESULT_CRITICAL_HEAL or result == ACTION_RESULT_HOT_TICK_CRITICAL) and ZO_CachedStrFormat("|cFFCC99<<1>>|r", GetString(SI_LIBCOMBAT_LOG_CRITICAL)) or ""
		local sourceName = units[sourceUnitId].name
		local ability = GetAbilityString(abilityId, "heal", fontsize, showIds)

		color = {0.4,0.8,0.4}
		text = ZO_CachedStrFormat(logFormat, timeString, sourceName, crit, ability, hitValue)

	elseif logtype == LIBCOMBAT_LOG_EVENT_HEAL then
		local _, _, result, _, _, abilityId, hitValue, _, _ = unpack(logline)

		local crit = (result == ACTION_RESULT_CRITICAL_HEAL or result == ACTION_RESULT_HOT_TICK_CRITICAL) and ZO_CachedStrFormat("|cFFCC99<<1>>|r", GetString(SI_LIBCOMBAT_LOG_CRITICAL)) or ""
		local ability = GetAbilityString(abilityId, "heal", fontsize, showIds)

		color = {0.8,1.0,0.6}
		text = result == ACTION_RESULT_DAMAGE_SHIELDED and ZO_CachedStrFormat(GetString(SI_LIBCOMBAT_LOG_FORMAT_HEALABSORB), timeString, ability, hitValue) or ZO_CachedStrFormat(logFormat, timeString, crit, ability, hitValue)

	elseif logtype == LIBCOMBAT_LOG_EVENT_EFFECT then
		local _, _, unitId, abilityId, changeType, effectType, stacks, sourceType, slot = unpack(logline)
		if units[unitId] == nil then return end

		local unitString = fight.playerid == unitId and GetString(SI_LIBCOMBAT_LOG_YOU) or units[unitId].name
		local changeTypeString = (changeType == EFFECT_RESULT_GAINED or changeType == EFFECT_RESULT_UPDATED) and GetString(SI_LIBCOMBAT_LOG_GAINED) or changeType == EFFECT_RESULT_FADED and GetString(SI_LIBCOMBAT_LOG_LOST)
		local source = UnitTypeString[sourceType] == nil and "" or ZO_CachedStrFormat(" from <<1>>", UnitTypeString[sourceType])
		local colorKey = effectType == BUFF_EFFECT_TYPE_DEBUFF and "debuff" or "buff"
		local buff = GetAbilityString(abilityId, colorKey, fontsize, showIds, stacks)

		color = {0.8,0.8,0.8}
		text = ZO_CachedStrFormat(logFormat, timeString, unitString, changeTypeString, buff, source)

	elseif logtype == LIBCOMBAT_LOG_EVENT_RESOURCE then
		local _, _, abilityId, powerValueChange, powerType = unpack(logline)

		if powerValueChange ~= nil then
			local changeColor, changeString

			if powerValueChange > 0 then
				changeColor = "|c00cc00"
				changeString = GetString(SI_LIBCOMBAT_LOG_GAINED)
			elseif powerValueChange == 0 then
				changeColor = "|cffffff"
				changeString = GetString(SI_LIBCOMBAT_LOG_NOGAINED)
			else
				changeColor = "|cff3333"
				changeString = GetString(SI_LIBCOMBAT_LOG_LOST)
			end

			local changeTypeString = ZO_CachedStrFormat("<<1>><<2>>|r", changeColor, changeString)
			local amount = powerValueChange~=0 and tostring(zo_abs(powerValueChange)) or ""
			local resource = (powerType == COMBAT_MECHANIC_FLAGS_MAGICKA and GetString(SI_ATTRIBUTES2)) or (powerType == COMBAT_MECHANIC_FLAGS_STAMINA and GetString(SI_ATTRIBUTES3)) or (powerType == COMBAT_MECHANIC_FLAGS_ULTIMATE and GetString(SI_LIBCOMBAT_LOG_ULTIMATE))
			local ability = abilityId and ZO_CachedStrFormat("(<<1>>)", GetAbilityString(abilityId, "resource", fontsize, showIds)) or ""

			color = (powerType == COMBAT_MECHANIC_FLAGS_MAGICKA and {0.7,0.7,1}) or (powerType == COMBAT_MECHANIC_FLAGS_STAMINA and {0.7,1,0.7}) or (powerType == COMBAT_MECHANIC_FLAGS_ULTIMATE and {1,1,0.7}) or color
			text = ZO_CachedStrFormat(logFormat, timeString, changeTypeString, amount, resource, ability)

		else return
		end

	elseif logtype == LIBCOMBAT_LOG_EVENT_STATS then
		local _, _, statchange, newvalue, statId = unpack(logline)

		local stat = statStrings[statId]
		local change = statchange
		local value = newvalue

		if statId == LIBCOMBAT_STAT_SPELLCRIT or statId == LIBCOMBAT_STAT_WEAPONCRIT then
			value = string.format("%.1f%%", GetCriticalStrikeChance(newvalue))
			change = string.format("%.1f%%", GetCriticalStrikeChance(statchange))
		end

		if statId == LIBCOMBAT_STAT_SPELLCRITBONUS or statId == LIBCOMBAT_STAT_WEAPONCRITBONUS then
			value = string.format("%.1f%%", newvalue)
			change = string.format("%.1f%%", statchange)
		end

		local changeText, changeValueText
		if statchange > 0 then
			changeText = ZO_CachedStrFormat("|c00cc00<<1>>|r", GetString(SI_LIBCOMBAT_LOG_INCREASED))
			changeValueText = ZO_CachedStrFormat(" |c00cc00(+<<1>>)|r", change)
		elseif statchange < 0 then
			changeText = ZO_CachedStrFormat("|cff3333<<1>>|r", GetString(SI_LIBCOMBAT_LOG_DECREASED))
			changeValueText = ZO_CachedStrFormat(" |cff3333(<<1>>)|r", change)
		else
			changeText = GetString(SI_LIBCOMBAT_LOG_IS_AT)
			changeValueText = ""
		end

		color = {0.8,0.8,0.8}
		text = ZO_CachedStrFormat(logFormat, timeString, stat, changeText, value, changeValueText)

	elseif logtype == LIBCOMBAT_LOG_EVENT_COMBATSTATE then
		local message = logline[3]
		local bar = logline[4]
		local messagetext

		if message == LIBCOMBAT_MESSAGE_WEAPONSWAP then
			color = {.6,.6,.6}
			local formatstring = bar ~= nil and bar > 0 and "<<1>> (<<2>> <<3>>)" or "<<1>>"
			messagetext = ZO_CachedStrFormat(formatstring, GetString(SI_LIBCOMBAT_LOG_MESSAGE3), GetString(SI_LIBCOMBAT_LOG_MESSAGE_BAR), bar)
		elseif message ~= nil then
			color = {.7,.7,.7}
			messagetext = type(message) == "number" and GetString("SI_LIBCOMBAT_LOG_MESSAGE", message) or message
		else
			return
		end

		text = ZO_CachedStrFormat("<<1>> <<2>>", timeString, messagetext)

	elseif logtype == LIBCOMBAT_LOG_EVENT_SKILL_CAST then
		local _, _, reducedslot, abilityId, status, skillDelay = unpack(logline)

		if reducedslot == nil then
			logger:Debug("Invalid Slot: %s (%d), Status: %d)", GetAbilityName(abilityId), abilityId, status)
			return
		end

		local skillDelayString = skillDelay and ZO_CachedStrFormat(GetString(SI_LIBCOMBAT_LOG_FORMATSTRING_SKILLDELAY), skillDelay) or ""
		local isWeaponAttack = reducedslot%10 == 1 or reducedslot%10 == 2
		local formatstring = " |cddffbb<<1>>|r"
		if isWeaponAttack then formatstring = " |cffffff<<1>>|r" end
		local name = ZO_CachedStrFormat(formatstring, GetFormattedAbilityName(abilityId))

		logFormat = GetString("SI_LIBCOMBAT_LOG_FORMATSTRING_SKILLS", status)
		color = {.9,.8,.7}
		text = ZO_CachedStrFormat(logFormat, timeString, name, skillDelayString)

	-- TODO: Rework
	-- elseif logtype == LIBCOMBAT_EVENT_BOSSHP then
	-- 	local _, _, bossId, currenthp, maxhp = unpack(logline)

	-- 	local unitId = fight.bosses[bossId]
	-- 	local bossName = units[unitId].name
	-- 	local percent = zo_round(currenthp/maxhp * 100)

	-- 	color = {.9,.7,.5}
	-- 	text = ZO_CachedStrFormat(logFormat, timeString, bossName, percent, currenthp, maxhp)

	elseif logtype == LIBCOMBAT_LOG_EVENT_PERFORMANCE then
		local _, _, fps, min, max, ping = unpack(logline)

		local pingcolor = ping <= 50 and "99ff99" or ping <= 80 and "ccff99" or ping <= 120 and "ffff99" or ping <= 160 and "ffcc99" or "ff9999"
		local pingString = ZO_CachedStrFormat("|c<<1>><<2>>|r", pingcolor, ping)
		local fpsColor = fps >= 100 and "99ff99" or fps >= 60 and "ccff99" or fps >= 40 and "ffff99" or fps >= 25 and "ffcc99" or "ff9999"
		local fpsString = ZO_CachedStrFormat("|c<<1>><<2>>|r", fpsColor, fps)
		local minString = min < (0.5 * fps) and min < 25 and ZO_CachedStrFormat("|cff9999<<1>>|r", min) or min < (0.7 * fps) and min < 40 and ZO_CachedStrFormat("|cffddbb<<1>>|r", min) or min

		color = {.9,.9,.9}
		text = ZO_CachedStrFormat(logFormat, timeString, fpsString, minString, max, pingString)

	elseif logtype == LIBCOMBAT_LOG_EVENT_DEATH then
		local _, _, state, unitId, otherId = unpack(logline)

		logFormat = GetString("SI_LIBCOMBAT_LOG_FORMATSTRING_DEATH", state)
		local isSelf = fight.playerid == unitId
		local unitString = isSelf and GetString(SI_LIBCOMBAT_LOG_YOU) or units[unitId].name

		local action = ""
		local otherString = ""
		if state == 1 and otherId ~= nil then 
			otherString = GetAbilityString(otherId, DAMAGE_TYPE_GENERIC, fontsize, showIds) 
		end

		if state > 2 then
			action = GetString("SI_LIBCOMBAT_LOG_RESURRECT", isSelf and 1 or 2)
		end

		text = ZO_CachedStrFormat(logFormat, timeString, unitString, action, otherString)
		color = {.7,.7,.7}
	end

	return text, color
end

local isFileInitialized = false

function lib.InitializeUtility()
	if isFileInitialized == true then return false end
	logger = lf.initSublogger("util")

    isFileInitialized = true
	return true
end
