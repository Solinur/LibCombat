-- stats

---@class LibCombat2
local lib = LibCombat2
---@class LCint
local libint = lib.internal
---@class LCData
local ld = libint.data
---@class LCUnits
local libunits = ld.units
---@class LCfunc
local lf = libint.functions
---@class Logger
local logger

local GetSlottedAbilityId = lf.GetSlottedAbilityId
local DivineSlots = {
	EQUIP_SLOT_HEAD,
	EQUIP_SLOT_SHOULDERS,
	EQUIP_SLOT_CHEST,
	EQUIP_SLOT_HAND,
	EQUIP_SLOT_WAIST,
	EQUIP_SLOT_LEGS,
	EQUIP_SLOT_FEET,
}

local function ParseDescriptionBonus(description, startIndex)
	local bonus = { description:match("cffffff[un ]*(%d+)%p?(%d*)[%%|][r|]", startIndex) }
	local bonusString = table.concat(bonus, ".")
	return tonumber(bonusString)
end

local parseHeraldFail = false
local function CheckForHeraldAbility()
	local bonusData = { [0] = 0, [1] = 0 }
	if GetUnitClassId("player") ~= 117 then
		return bonusData
	end
	local skillType, lineIndex, skillIndex = GetSpecificSkillAbilityKeysByAbilityId(184873)
	local abilityId = GetSkillAbilityId(skillType, lineIndex, skillIndex, false)
	local description = GetAbilityDescription(abilityId)
	local startindex = select(2, description:find("cffffff[un ]*%d+%p?%d*[%%|][r|]"))
	local bonus = ParseDescriptionBonus(description, startindex)

	if bonus == nil and parseHeraldFail == false then
		logger:Warn("Failed to parse description for SE bonus: %s", description)
		parseHeraldFail = true
	end

	for hotbarCategory = 0, 1 do
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
	for hotbarCategory = 0, 1 do
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
				logger:Warn("Failed to parse description for SE bonus: %s", description)
				parseChargedFail = true
			end

			chargedBonus = chargedBonus + (bonus or 0)
		end

		local trait, description = GetItemLinkTraitInfo(item_link_off)
		if trait == ITEM_TRAIT_TYPE_WEAPON_CHARGED then
			local bonus = ParseDescriptionBonus(description)

			if bonus == nil and parseChargedFail == false then
				logger:Warn("Failed to parse description for SE bonus: %s", description)
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
	if select(4, GetItemSetInfo(583)) < 3 then
		return 0
	end -- at least 3 pieces must always be active (2 could be hidden on other bar) otherwise 5-piece bonus will never activate
	local _, description = GetItemSetBonusInfo(583, 4)
	local bonus = ParseDescriptionBonus(description)

	if bonus == nil and parseHeartlandFail == false then
		logger:Warn("Failed to parse description for SE bonus: %s", description)
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
	local bonusData = { [0] = 0, [1] = 0 }
	local skillType, lineIndex, skillIndex = GetSpecificSkillAbilityKeysByAbilityId(45512)
	local abilityId = GetSkillAbilityId(skillType, lineIndex, skillIndex, false)
	local description = GetAbilityDescription(abilityId)
	local bonus = ParseDescriptionBonus(description)

	if bonus == nil and parseDestroFail == false then
		logger:Warn("Failed to parse description for SE bonus: %s", description)
		parseDestroFail = true
	end

	local weaponTypeMain = GetItemWeaponType(BAG_WORN, EQUIP_SLOT_MAIN_HAND)
	if DestroStaffTypes[weaponTypeMain] then
		bonusData[0] = bonus
	end
	local weaponTypeBackup = GetItemWeaponType(BAG_WORN, EQUIP_SLOT_BACKUP_MAIN)
	if DestroStaffTypes[weaponTypeBackup] then
		bonusData[1] = bonus
	end
	return bonusData
end

local function CheckCPBonus()
	local martial = 1.5 * GetNumPointsSpentOnChampionSkill(18)
	local magic = 1.5 * GetNumPointsSpentOnChampionSkill(17)

	return (martial + magic) / 2
end

local parseWealdFail = false
local function CheckWealdSet()
	if select(4, GetItemSetInfo(757)) < 3 then
		return 0
	end -- at least 3 pieces must always be active (2 could be hidden on other bar) otherwise 5-piece bonus will never activate
	local _, description = GetItemSetBonusInfo(757, 4)
	local bonus = ParseDescriptionBonus(description)

	if bonus == nil and parseWealdFail == false then
		logger:Warn("Failed to parse description for SE bonus: %s", description)
		parseWealdFail = true
	end
	return bonus or 0
end

local parseFocusedEffortsFail = false
local function GetFocusedEffortsBonus()
	local stacks = GetNumStacksForEndlessDungeonBuff(200904, false)
	if stacks <= 0 then
		return 0
	end
	local description = GetAbilityDescription(200904)
	local bonus = ParseDescriptionBonus(description)

	if bonus == nil and parseFocusedEffortsFail == false then
		logger:Warn("Failed to parse description for SE bonus: %s", description)
		parseFocusedEffortsFail = true
	end
	return bonus or 0
end

function lf.InitStatusEffectBonuses()
	local SEBonus = {}
	SEBonus.arcanistBonus = CheckForHeraldAbility()
	SEBonus.charged = GetChargedBonus()
	SEBonus.heartlandBonus = CheckHeartlandSet()
	SEBonus.wealdBonus = CheckWealdSet()
	SEBonus.destro = CheckDestroPassive()
	SEBonus.CP = CheckCPBonus()
	SEBonus.focusedEfforts = GetFocusedEffortsBonus()
	ld.statusEffectBonus = SEBonus
end

function lf.GetCritBonusFromCP(CPdata)
	local slots = CPdata[1].slotted
	local points = CPdata[1].stars
	local backstabber = slots[31] and (2 * zo_floor(0.1 * points[31][1])) or 0 -- Backstabber 2% per every full 10 points (flanking!)
	return backstabber
end

function lf.GetShadowBonus(effectSlot)
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
	local calcBonus = zo_floor(11 * (1 + totalBonus / 100))

	ld.critBonusMundus = calcBonus - ZOSBonus -- mundus bonus difference
	logger:Debug("Shadow Mundus Offset: %d%% (calc %d%% - ZOS %d%%)", ld.critBonusMundus, calcBonus, ZOSBonus)
end

local TFSBonus = 0

local function GetStat(stat)
	return GetPlayerStat(stat, STAT_BONUS_OPTION_APPLY_BONUS)
end
lf.GetStat = GetStat

local function GetPenetrationStat(stat)
	if stat == STAT_SPELL_PENETRATION or stat == STAT_PHYSICAL_PENETRATION then
		return GetStat(stat) + TFSBonus
	end
	logger:Error("Invalid stat type provided. Must be either STAT_SPELL_PENETRATION or STAT_PHYSICAL_PENETRATION.")
end

local function GetCritStat(stat)
	local maxcrit = zo_floor(100 / GetCriticalStrikeChance(1))
	return zo_min(GetStat(stat), maxcrit)
end

function GetCritbonus()
	local _, _, valueFromZos = GetAdvancedStatValue(ADVANCED_STAT_DISPLAY_TYPE_CRITICAL_DAMAGE)
	local total2 = 50 + valueFromZos + ld.backstabber + ld.critBonusMundus

	local spelltotal = total2
	local weapontotal = total2

	return weapontotal, spelltotal
end

local function GetStatusEffectChance()
	local SEBonus = ld.statusEffectBonus
	local weaponPair = GetHeldWeaponPair()
	local hotBar = weaponPair >= 1 and (weaponPair - 1) or nil
	local arcanistBonus = hotBar and SEBonus.arcanistBonus[hotBar] or 0
	local chargedBonus = hotBar and SEBonus.charged[hotBar] or 0
	local destroBonus = hotBar and SEBonus.destro[hotBar] or 0
	local CPBonus = SEBonus.CP
	local FEBonus = SEBonus.focusedEfforts

	local wealdBonus = 0
	if SEBonus.wealdBonus > 0 and select(4, GetItemSetInfo(757)) >= 5 then
		local current, maxHealth = GetUnitPower("player", COMBAT_MECHANIC_FLAGS_HEALTH)
		if current / maxHealth > 0.5 then
			wealdBonus = SEBonus.wealdBonus
		end
	end

	local totalBonus = arcanistBonus + chargedBonus + destroBonus + wealdBonus + FEBonus + CPBonus

	return totalBonus
end

local statData = {
	[LIBCOMBAT_STAT_MAXMAGICKA] = 0,
	[LIBCOMBAT_STAT_SPELLPOWER] = 0,
	[LIBCOMBAT_STAT_SPELLCRIT] = 0,
	[LIBCOMBAT_STAT_SPELLCRITBONUS] = 0,
	[LIBCOMBAT_STAT_SPELLPENETRATION] = 0,

	[LIBCOMBAT_STAT_MAXSTAMINA] = 0,
	[LIBCOMBAT_STAT_WEAPONPOWER] = 0,
	[LIBCOMBAT_STAT_WEAPONCRIT] = 0,
	[LIBCOMBAT_STAT_WEAPONCRITBONUS] = 0,
	[LIBCOMBAT_STAT_WEAPONPENETRATION] = 0,

	[LIBCOMBAT_STAT_MAXHEALTH] = 0,
	[LIBCOMBAT_STAT_PHYSICALRESISTANCE] = 0,
	[LIBCOMBAT_STAT_SPELLRESISTANCE] = 0,
	[LIBCOMBAT_STAT_CRITICALRESISTANCE] = 0,
	[LIBCOMBAT_STAT_STATUS_EFFECT_CHANCE] = 0,
}

local statSourceFunctions = {
	[LIBCOMBAT_STAT_MAXMAGICKA] = GetStat,
	[LIBCOMBAT_STAT_SPELLPOWER] = GetStat,
	[LIBCOMBAT_STAT_SPELLCRIT] = GetCritStat,
	[LIBCOMBAT_STAT_SPELLCRITBONUS] = GetCritbonus,
	[LIBCOMBAT_STAT_SPELLPENETRATION] = GetPenetrationStat,

	[LIBCOMBAT_STAT_MAXSTAMINA] = GetStat,
	[LIBCOMBAT_STAT_WEAPONPOWER] = GetStat,
	[LIBCOMBAT_STAT_WEAPONCRIT] = GetCritStat,
	[LIBCOMBAT_STAT_WEAPONCRITBONUS] = GetCritbonus,
	[LIBCOMBAT_STAT_WEAPONPENETRATION] = GetPenetrationStat,

	[LIBCOMBAT_STAT_MAXHEALTH] = GetStat,
	[LIBCOMBAT_STAT_PHYSICALRESISTANCE] = GetStat,
	[LIBCOMBAT_STAT_SPELLRESISTANCE] = GetStat,
	[LIBCOMBAT_STAT_CRITICALRESISTANCE] = GetStat,
	[LIBCOMBAT_STAT_STATUS_EFFECT_CHANCE] = GetStatusEffectChance,
}

local zoDerivedStatIds = {
	[LIBCOMBAT_STAT_MAXMAGICKA] = STAT_MAGICKA_MAX,
	[LIBCOMBAT_STAT_SPELLPOWER] = STAT_SPELL_POWER,
	[LIBCOMBAT_STAT_SPELLCRIT] = STAT_SPELL_CRITICAL,
	[LIBCOMBAT_STAT_SPELLPENETRATION] = STAT_SPELL_PENETRATION,

	[LIBCOMBAT_STAT_MAXSTAMINA] = STAT_STAMINA_MAX,
	[LIBCOMBAT_STAT_WEAPONPOWER] = STAT_POWER,
	[LIBCOMBAT_STAT_WEAPONCRIT] = STAT_CRITICAL_STRIKE,
	[LIBCOMBAT_STAT_WEAPONPENETRATION] = STAT_PHYSICAL_PENETRATION,

	[LIBCOMBAT_STAT_MAXHEALTH] = STAT_HEALTH_MAX,
	[LIBCOMBAT_STAT_PHYSICALRESISTANCE] = STAT_PHYSICAL_RESIST,
	[LIBCOMBAT_STAT_SPELLRESISTANCE] = STAT_SPELL_RESIST,
	[LIBCOMBAT_STAT_CRITICALRESISTANCE] = STAT_CRITICAL_RESISTANCE,
}

local function GetSingleStat(statId)
	if not libint.currentFight.prepared then
		libint.currentFight:PrepareFight()
	end
	return statSourceFunctions[statId](zoDerivedStatIds[statId])
end
lf.GetSingleStat = GetSingleStat

local function GetStats()
	for statId, _ in pairs(statData) do
		statData[statId] = GetSingleStat(statId)
	end
	return statData
end

function lf.UpdateStats(timeMs)
	local stats = ld.stats

	for statId, newValue in pairs(GetStats()) do
		local oldValue = stats[statId]
		local delta = oldValue and (newValue - oldValue) or 0
		if oldValue == nil or delta ~= 0 then
			if newValue == nil then
				logger:Error("Invalid values encountered: newValue is nil")
				return
			end
			if delta == nil then
				logger:Error("Invalid values encountered: delta is nil")
				return
			end
			if statId == nil then
				logger:Error("Invalid values encountered: statId is nil")
				return
			end
			lf.FireCallback(LIBCOMBAT_LOG_EVENT_STATS, timeMs, delta, newValue, statId)
			stats[statId] = newValue
		end
	end
end

local lastUpdateSingleStatsCall = 0

function lf.UpdateSingleStat(statId, timeMs)
	if libint.Events.Stats.active ~= true then
		return
	end
	EVENT_MANAGER:UnregisterForUpdate("LibCombat_Stats_Single")

	timeMs = timeMs or GetGameTimeMilliseconds()
	local lastcalldelta = timeMs - lastUpdateSingleStatsCall

	if lastcalldelta < 100 then
		EVENT_MANAGER:RegisterForUpdate("LibCombat_Stats_Single", (100 - lastcalldelta), function()
			lf.UpdateSingleStat(statId, nil)
		end)
		return
	end

	lastUpdateSingleStatsCall = timeMs
	local stats = ld.stats
	local oldValue = stats[statId]
	local newValue = lf.GetSingleStat(statId)
	local delta = oldValue and (newValue - oldValue) or 0
	if oldValue == nil or delta ~= 0 then
		assert(delta ~= nil)
		assert(newValue ~= nil)
		assert(statId ~= nil)
		lf.FireCallback(LIBCOMBAT_LOG_EVENT_STATS, timeMs, delta, newValue, statId)
		stats[statId] = newValue
	end
end

function lf.onTFSChanged(_, changeType, _, _, _, _, _, stackCount, _, _, _, _, _, _, _, _, _)
	local getBonus = (changeType == EFFECT_RESULT_GAINED or changeType == EFFECT_RESULT_UPDATED) and stackCount > 1
	TFSBonus = getBonus and (stackCount - 1) * 544 or 0
	libint.currentFight:QueueStatUpdate()
end

local function onShadowMundus(_, changeType, effectSlot)
	if changeType == EFFECT_RESULT_GAINED or changeType == EFFECT_RESULT_UPDATED then
		lf.GetShadowBonus(effectSlot)
	elseif changeType == EFFECT_RESULT_FADED then
		ld.critBonusMundus = 0
	end

	if libint.currentFight.prepared == true then
		libint.currentFight:QueueStatUpdate()
	end
end

libint.Events.Stats = libint.EventHandler:New({ LIBCOMBAT_LOG_EVENT_STATS }, function(self)
	self:RegisterEvent(
		EVENT_EFFECT_CHANGED,
		onShadowMundus,
		REGISTER_FILTER_UNIT_TAG,
		"player",
		REGISTER_FILTER_ABILITY_ID,
		13984
	)
	self:RegisterEvent(
		EVENT_EFFECT_CHANGED,
		lf.onTFSChanged,
		REGISTER_FILTER_UNIT_TAG,
		"player",
		REGISTER_FILTER_ABILITY_ID,
		51176
	) -- to track TFS procs, which aren't recognized for stacks > 1 in penetration stat.
	self.active = true
end)

-- libint.Events.AdvancedStats = libint.EventHandler:New(
-- 	{LIBCOMBAT_EVENT_PLAYERSTATS_ADVANCED},
-- 	function (self)
-- 		self.active = true
-- 	end
-- )

local isFileInitialized = false
function libint.InitializeStats()
	if isFileInitialized == true then
		return false
	end
	logger = lf.initSublogger("stats")

	ld.stats = {}
	-- ld.advancedStats = {} -- TODO: Remove?

	ld.backstabber = 0
	ld.critBonusMundus = 0
	ld.lastabilities = {}

	ld.currentQuickslotIndex = GetCurrentQuickslot()

	isFileInitialized = true
	return true
end
