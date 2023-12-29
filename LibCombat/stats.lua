-- stats

local lib = LibCombat
local libint = lib.internal
local libfunc = libint.functions
local libdata = libint.data
local Print = libint.Print
local CallbackKeys = libint.callbackKeys

local DivineSlots = {EQUIP_SLOT_HEAD, EQUIP_SLOT_SHOULDERS, EQUIP_SLOT_CHEST, EQUIP_SLOT_HAND, EQUIP_SLOT_WAIST, EQUIP_SLOT_LEGS, EQUIP_SLOT_FEET}

function libfunc.GetCritBonusFromCP(CPdata)

	local slots = CPdata[1].slotted
	local points = CPdata[1].stars

	local backstabber = slots[31] and (2 * math.floor(0.1 * points[31][1])) or 0 -- Backstabber 2% per every full 10 points (flanking!)

	return backstabber
end

function libfunc.GetShadowBonus(effectSlot)

	local totalBonus = 0

	for _, key in pairs(DivineSlots) do

		local trait, desc = GetItemLinkTraitInfo(GetItemLink(BAG_WORN, key, LINK_STYLE_DEFAULT))

		if trait == ITEM_TRAIT_TYPE_ARMOR_DIVINES then

			local bonus = {desc:match("(%d+)%p?(%d*)[%%|]")}
			local bonusString = table.concat(bonus, ".")
			totalBonus = (tonumber(bonusString) or 0) + totalBonus

		end

	end

	local ZOSDesc = GetAbilityEffectDescription(effectSlot)
	local ZOSBonusString = ZOSDesc:match("cffffff(%d+)[%%|]")

	local calcBonus =  math.floor(11 * (1 + totalBonus/100))
	local ZOSBonus = tonumber(ZOSBonusString) or 0 -- value attributed by ZOS

	libdata.critBonusMundus = calcBonus - ZOSBonus -- mundus bonus difference

	Print("other","INFO", "Shadow Mundus Offset: %d%% (calc %d%% - ZOS %d%%)", libdata.critBonusMundus, calcBonus, ZOSBonus)
end

local TFSBonus = 0

local function GetCritbonus()

	local _, _, valueFromZos = GetAdvancedStatValue(ADVANCED_STAT_DISPLAY_TYPE_CRITICAL_DAMAGE)
	local total2 = 50 + valueFromZos + libdata.backstabber + libdata.critBonusMundus

	local spelltotal = total2
	local weapontotal = total2

	return weapontotal, spelltotal

end

local statData = {
	[LIBCOMBAT_STAT_MAXMAGICKA]			= 0,
	[LIBCOMBAT_STAT_SPELLPOWER]			= 0,
	[LIBCOMBAT_STAT_SPELLCRIT]			= 0,
	[LIBCOMBAT_STAT_SPELLCRITBONUS]		= 0,
	[LIBCOMBAT_STAT_SPELLPENETRATION]	= 0,

	[LIBCOMBAT_STAT_MAXSTAMINA]			= 0,
	[LIBCOMBAT_STAT_WEAPONPOWER]		= 0,
	[LIBCOMBAT_STAT_WEAPONCRIT]			= 0,
	[LIBCOMBAT_STAT_WEAPONCRITBONUS]	= 0,
	[LIBCOMBAT_STAT_WEAPONPENETRATION]	= 0,

	[LIBCOMBAT_STAT_MAXHEALTH]			= 0,
	[LIBCOMBAT_STAT_PHYSICALRESISTANCE]	= 0,
	[LIBCOMBAT_STAT_SPELLRESISTANCE]	= 0,
	[LIBCOMBAT_STAT_CRITICALRESISTANCE]	= 0,
}

local function GetStat(stat) -- helper function to make code shorter
	return GetPlayerStat(stat, STAT_BONUS_OPTION_APPLY_BONUS)
end
libfunc.GetStat = GetStat

local function GetStats()

	if libint.Events.Stats.active ~= true then return end

	local weaponcritbonus, spellcritbonus = GetCritbonus()
	local maxcrit = math.floor(100/GetCriticalStrikeChance(1)) -- Critical Strike chance of 100%

	statData[LIBCOMBAT_STAT_MAXMAGICKA]			= GetStat(STAT_MAGICKA_MAX)
	statData[LIBCOMBAT_STAT_SPELLPOWER]			= GetStat(STAT_SPELL_POWER)
	statData[LIBCOMBAT_STAT_SPELLCRIT]			= math.min(GetStat(STAT_SPELL_CRITICAL), maxcrit)
	statData[LIBCOMBAT_STAT_SPELLCRITBONUS]		= spellcritbonus
	statData[LIBCOMBAT_STAT_SPELLPENETRATION]	= GetStat(STAT_SPELL_PENETRATION) + TFSBonus

	statData[LIBCOMBAT_STAT_MAXSTAMINA]			= GetStat(STAT_STAMINA_MAX)
	statData[LIBCOMBAT_STAT_WEAPONPOWER]		= GetStat(STAT_POWER)
	statData[LIBCOMBAT_STAT_WEAPONCRIT]			= math.min(GetStat(STAT_CRITICAL_STRIKE), maxcrit)
	statData[LIBCOMBAT_STAT_WEAPONCRITBONUS]	= weaponcritbonus
	statData[LIBCOMBAT_STAT_WEAPONPENETRATION]	= GetStat(STAT_PHYSICAL_PENETRATION) + TFSBonus

	statData[LIBCOMBAT_STAT_MAXHEALTH]			= GetStat(STAT_HEALTH_MAX)
	statData[LIBCOMBAT_STAT_PHYSICALRESISTANCE]	= GetStat(STAT_PHYSICAL_RESIST)
	statData[LIBCOMBAT_STAT_SPELLRESISTANCE]	= GetStat(STAT_SPELL_RESIST)
	statData[LIBCOMBAT_STAT_CRITICALRESISTANCE]	= GetStat(STAT_CRITICAL_RESISTANCE)

	return statData
end

local advancedStatData = {}

function libfunc.InitAdvancedStats()

	if true then return {} end

	for statCategoryIndex = 1, GetNumAdvancedStatCategories() do

		local statCategoryId = GetAdvancedStatsCategoryId(statCategoryIndex)
		local _, numStats = GetAdvancedStatCategoryInfo(statCategoryId)

		if numStats > 0 then

			for statIndex = 1, numStats do

				local statType = GetAdvancedStatInfo(statCategoryId, statIndex)

				local _, flatValue, percentValue = GetAdvancedStatValue(statType)

				advancedStatData[statType] = {flatValue, percentValue}

			end
		end
	end
end

local function GetAdvancedStats()

	if true then return {} end

	for statType, _ in pairs(advancedStatData) do

		local _, flatValue, percentValue = GetAdvancedStatValue(statType)

		if flatValue then advancedStatData[statType][1] = flatValue end
		if percentValue then advancedStatData[statType][2] = percentValue end

	end

	return advancedStatData
end

function libfunc.UpdateStats(timems)
    local stats = libdata.stats

	for statId, newValue in pairs(GetStats()) do

		local oldValue = stats[statId]

		local delta = oldValue and (newValue - oldValue) or 0

		if oldValue == nil or delta ~= 0 then

			lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_PLAYERSTATS]), LIBCOMBAT_EVENT_PLAYERSTATS, timems, delta, newValue, statId)

			stats[statId] = newValue

		end
	end

	if libint.Events.AdvancedStats.active ~= true then return end

	local advancedStats = libdata.advancedStats

	for statId, values in pairs(GetAdvancedStats()) do

		local newValue1 = values[1]
		local newValue2 = values[2]

		if advancedStats[statId] == nil then advancedStats[statId] = {} end

		local oldValues = advancedStats[statId]

		if newValue1 then

			local oldValue = oldValues[1]

			local delta = oldValue and (newValue1 - oldValue) or 0

			if oldValue == nil or delta ~= 0 then

				lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_PLAYERSTATS_ADVANCED]), LIBCOMBAT_EVENT_PLAYERSTATS_ADVANCED, timems, delta, newValue1, statId)

				advancedStats[statId][1] = newValue1

			end
		end

		if newValue2 then

			local oldValue = oldValues[2]

			local delta = oldValue and (newValue2 - oldValue) or 0

			if oldValue == nil or delta ~= 0 then

				lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_PLAYERSTATS_ADVANCED]), LIBCOMBAT_EVENT_PLAYERSTATS_ADVANCED, timems, delta, newValue2, statId + 2048)

				advancedStats[statId][2] = newValue2
			end
		end
	end
end

function libfunc.onTFSChanged(_, changeType, _, _, _, _, _, stackCount, _, _, _, _, _, _, _, _, _)

	if (changeType == EFFECT_RESULT_GAINED or changeType == EFFECT_RESULT_UPDATED) and stackCount > 1 then

		TFSBonus = (stackCount - 1) * 544

	else

		TFSBonus = 0

	end

	libint.currentfight:QueueStatUpdate()
end

local function onShadowMundus( _, changeType, effectSlot)

	if changeType == EFFECT_RESULT_GAINED or changeType == EFFECT_RESULT_UPDATED then libfunc.GetShadowBonus(effectSlot)
	elseif changeType == EFFECT_RESULT_FADED then libdata.critBonusMundus = 0 end

	if libint.currentfight.prepared == true then libint.currentfight:QueueStatUpdate() end

end

libint.Events.Stats = libint.EventHandler:New(
	{LIBCOMBAT_EVENT_PLAYERSTATS},
	function (self)

		self:RegisterEvent(EVENT_EFFECT_CHANGED, onShadowMundus, REGISTER_FILTER_UNIT_TAG, "player", REGISTER_FILTER_ABILITY_ID, 13984)

		self:RegisterEvent(EVENT_EFFECT_CHANGED, libfunc.onTFSChanged, REGISTER_FILTER_UNIT_TAG, "player", REGISTER_FILTER_ABILITY_ID, 51176)  -- to track TFS procs, which aren't recognized for stacks > 1 in penetration stat.

		self.active = true
	end
)

libint.Events.AdvancedStats = libint.EventHandler:New(
	{LIBCOMBAT_EVENT_PLAYERSTATS_ADVANCED},
	function (self)
		self.active = true
	end
)

local isFileInitialized = false

function lib.InitializeStats()

	if isFileInitialized == true then return false end

    isFileInitialized = true
	return true

end
