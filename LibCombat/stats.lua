-- stats

local lib = LibCombat
local libint = lib.internal
local libfunc = libint.functions
---@type fun(actionSlotIndex: integer, hotbarCategory: HotBarCategory): integer, integer?
local GetSlottedAbilityId = libfunc.GetSlottedAbilityId
local libdata = libint.data
local Log = libint.Log
local CallbackKeys = libint.callbackKeys

local DivineSlots = {EQUIP_SLOT_HEAD, EQUIP_SLOT_SHOULDERS, EQUIP_SLOT_CHEST, EQUIP_SLOT_HAND, EQUIP_SLOT_WAIST, EQUIP_SLOT_LEGS, EQUIP_SLOT_FEET}

local function ParseDescriptionBonus(description, startIndex)
	local bonus = {description:match("cffffff[un ]*(%d+)%p?(%d*)[%%|][r|]", startIndex)}
	local bonusString = table.concat(bonus, ".")
	return tonumber(bonusString)
end

local parseHeraldFail = false
local function CheckForHeraldAbility()
	local bonusData = {[0] = 0, [1] = 0}
	if GetUnitClassId("player") ~= 117 then return bonusData end
	local skillType, lineIndex, skillIndex  = GetSpecificSkillAbilityKeysByAbilityId(184873)
	local abilityId = GetSkillAbilityId(skillType, lineIndex, skillIndex, false)
	local description = GetAbilityDescription(abilityId)
	local startindex = select(2, description:find("cffffff[un ]*%d+%p?%d*[%%|][r|]"))
	local bonus = ParseDescriptionBonus(description, startindex)

	if bonus == nil and parseHeraldFail == false then
		Log("main", "WARNING", "Failed to parse description for SE bonus: %s", description)
		parseHeraldFail = true
	end

	for hotbarCategory = 0,1 do
		for slot = 3, 8 do
			local abilityId = GetSlottedAbilityId(slot, hotbarCategory)
			local skillType, lineIndex2, _ = GetSpecificSkillAbilityKeysByAbilityId(abilityId)
			if skillType == 0 and lineIndex == lineIndex2 and abilityId ~= 0 then
				bonusData[hotbarCategory] = bonus
				break
			end
		end
	end
	return bonusData
end

local parseChargedFail = false
local function GetChargedBonus()
	local charged = {}
	for hotbarCategory = 0,1 do
		local slot_main_hand, slot_off_hand
		if hotbarCategory == HOTBAR_CATEGORY_PRIMARY then
			slot_main_hand = EQUIP_SLOT_MAIN_HAND
			slot_off_hand = EQUIP_SLOT_OFF_HAND
		elseif hotbarCategory == HOTBAR_CATEGORY_BACKUP then
			slot_main_hand = EQUIP_SLOT_BACKUP_MAIN
			slot_off_hand = EQUIP_SLOT_BACKUP_OFF
		end

		local item_link_main = GetItemLink(BAG_WORN, slot_main_hand, LINK_STYLE_DEFAULT)
		local item_link_off = GetItemLink(BAG_WORN, slot_off_hand, LINK_STYLE_DEFAULT)
		local chargedBonus = 0

		local trait, description = GetItemLinkTraitInfo(item_link_main)
		if trait == ITEM_TRAIT_TYPE_WEAPON_CHARGED then
			local bonus = ParseDescriptionBonus(description)

			if bonus == nil and parseChargedFail == false then
				Log("main", LOG_LEVEL_WARNING, "Failed to parse description for SE bonus: %s", description)
				parseChargedFail = true
			end
			
			chargedBonus = chargedBonus + (bonus or 0)
		end



		local trait, description = GetItemLinkTraitInfo(item_link_off)
		if trait == ITEM_TRAIT_TYPE_WEAPON_CHARGED then
			local bonus = ParseDescriptionBonus(description)

			if bonus == nil and parseChargedFail == false then
				Log("main", LOG_LEVEL_WARNING, "Failed to parse description for SE bonus: %s", description)
				parseChargedFail = true
			end
			
			chargedBonus = chargedBonus + (bonus or 0)
		end

		charged[hotbarCategory] = chargedBonus
	end
	return charged
end

local parseHeartlandFail = false
local function CheckHeartlandSet()
	if select(4, GetItemSetInfo(583)) < 3 then return 0 end -- at least 3 pieces must always be active (2 could be hidden on other bar) otherwise 5-piece bonus will never activate
	local _, description = GetItemSetBonusInfo(583, 4)
	local bonus = ParseDescriptionBonus(description)

	if bonus == nil and parseHeartlandFail == false then
		Log("main", LOG_LEVEL_WARNING, "Failed to parse description for SE bonus: %s", description)
		parseHeartlandFail = true
	end
	return (bonus or 0) / 100
end

local DestroStaffTypes = {
	[WEAPONTYPE_FIRE_STAFF] = true,
	[WEAPONTYPE_FROST_STAFF] = true,
	[WEAPONTYPE_LIGHTNING_STAFF] = true,
}

local parseDestroFail = false
local function CheckDestroPassive()
	local bonusData = {[0] = 0, [1] = 0}
	local skillType, lineIndex, skillIndex  = GetSpecificSkillAbilityKeysByAbilityId(45512)
	local abilityId = GetSkillAbilityId(skillType, lineIndex, skillIndex, false)
	local description = GetAbilityDescription(abilityId)
	local bonus = ParseDescriptionBonus(description)

	if bonus == nil and parseDestroFail == false then
		Log("main", LOG_LEVEL_WARNING, "Failed to parse description for SE bonus: %s", description)
		parseDestroFail = true
	end

	local weaponTypeMain = GetItemWeaponType(BAG_WORN, EQUIP_SLOT_MAIN_HAND)
	if DestroStaffTypes[weaponTypeMain] then bonusData[0] = bonus end
	local weaponTypeBackup = GetItemWeaponType(BAG_WORN, EQUIP_SLOT_BACKUP_MAIN)
	if DestroStaffTypes[weaponTypeBackup] then bonusData[1] = bonus end
	return bonusData
end


local function CheckCPBonus()
	local martial = 1.5 * GetNumPointsSpentOnChampionSkill(18)
	local magic = 1.5 * GetNumPointsSpentOnChampionSkill(17)

	return (martial + magic)/2
end

local parseWealdFail = false
local function CheckWealdSet()
	if select(4, GetItemSetInfo(757)) < 3 then return 0 end  -- at least 3 pieces must always be active (2 could be hidden on other bar) otherwise 5-piece bonus will never activate
	local _, description = GetItemSetBonusInfo(757, 4)
	local bonus = ParseDescriptionBonus(description)

	if bonus == nil and parseWealdFail == false then
		Log("main", LOG_LEVEL_WARNING, "Failed to parse description for SE bonus: %s", description)
		parseWealdFail = true
	end
	return bonus or 0
end

local parseFocusedEffortsFail = false
local function GetFocusedEffortsBonus()
	local stacks = GetNumStacksForEndlessDungeonBuff(200904, false)
	if stacks <= 0 then return 0 end
	local description = GetAbilityDescription(200904)
	local bonus = ParseDescriptionBonus(description)

	if bonus == nil and parseFocusedEffortsFail == false then
		Log("main", LOG_LEVEL_WARNING, "Failed to parse description for SE bonus: %s", description)
		parseFocusedEffortsFail = true
	end
	return bonus or 0
end

function libfunc.InitStatusEffectBonuses()
	local SEBonus = {}
	SEBonus.arcanistBonus = CheckForHeraldAbility()
	SEBonus.charged = GetChargedBonus()
	SEBonus.heartlandBonus = CheckHeartlandSet()
	SEBonus.wealdBonus = CheckWealdSet()
	SEBonus.destro = CheckDestroPassive()
	SEBonus.CP = CheckCPBonus()
	SEBonus.focusedEfforts = GetFocusedEffortsBonus()
	libdata.statusEffectBonus = SEBonus
end

function libfunc.GetCritBonusFromCP(CPdata)

	local slots = CPdata[1].slotted
	local points = CPdata[1].stars

	local backstabber = slots[31] and (2 * zo_floor(0.1 * points[31][1])) or 0 -- Backstabber 2% per every full 10 points (flanking!)

	return backstabber
end

function libfunc.GetShadowBonus(effectSlot)
	local totalBonus = 0
	for _, key in pairs(DivineSlots) do
		local trait, desc = GetItemLinkTraitInfo(GetItemLink(BAG_WORN, key, LINK_STYLE_DEFAULT))

		if trait == ITEM_TRAIT_TYPE_ARMOR_DIVINES then

			local bonus = ParseDescriptionBonus(desc) or 0
			totalBonus = bonus + totalBonus

		end
	end

	local ZOSDesc = GetAbilityEffectDescription(effectSlot)
	local ZOSBonus = ParseDescriptionBonus(ZOSDesc) or 0 -- value attributed by ZOS

	local calcBonus =  zo_floor(11 * (1 + totalBonus/100))

	data.critBonusMundus = calcBonus - ZOSBonus -- mundus bonus difference

	Log("other", "INFO", "Shadow Mundus Offset: %d%% (calc %d%% - ZOS %d%%)", data.critBonusMundus, calcBonus, ZOSBonus)
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
	local maxcrit = zo_floor(100/GetCriticalStrikeChance(1)) -- Critical Strike chance of 100%

	statData[LIBCOMBAT_STAT_MAXMAGICKA]			= GetStat(STAT_MAGICKA_MAX)
	statData[LIBCOMBAT_STAT_SPELLPOWER]			= GetStat(STAT_SPELL_POWER)
	statData[LIBCOMBAT_STAT_SPELLCRIT]			= zo_min(GetStat(STAT_SPELL_CRITICAL), maxcrit)
	statData[LIBCOMBAT_STAT_SPELLCRITBONUS]		= spellcritbonus
	statData[LIBCOMBAT_STAT_SPELLPENETRATION]	= GetStat(STAT_SPELL_PENETRATION) + TFSBonus

	statData[LIBCOMBAT_STAT_MAXSTAMINA]			= GetStat(STAT_STAMINA_MAX)
	statData[LIBCOMBAT_STAT_WEAPONPOWER]		= GetStat(STAT_POWER)
	statData[LIBCOMBAT_STAT_WEAPONCRIT]			= zo_min(GetStat(STAT_CRITICAL_STRIKE), maxcrit)
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
