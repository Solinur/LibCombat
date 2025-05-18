-- This file contains definitions of global variables

local lib = LibCombat

-- types of callbacks: Units, DPS/HPS, DPS/HPS for Group, Logevents

LIBCOMBAT_EVENT_MIN = 0
LIBCOMBAT_EVENT_UNITS = 0					-- LIBCOMBAT_EVENT_UNITS, {units}
LIBCOMBAT_EVENT_FIGHTRECAP = 1				-- LIBCOMBAT_EVENT_FIGHTRECAP, {data}
LIBCOMBAT_EVENT_FIGHTSUMMARY = 2			-- LIBCOMBAT_EVENT_FIGHTSUMMARY, {fight}
LIBCOMBAT_EVENT_GROUPRECAP = 3				-- LIBCOMBAT_EVENT_GROUPRECAP, groupDPSOut, groupDPSIn, groupHPS, dpstime, hpstime
LIBCOMBAT_EVENT_DEATHRECAP = 4				-- LIBCOMBAT_EVENT_DEATHRECAP, timems, {data}
LIBCOMBAT_EVENT_MAX = 4

LIBCOMBAT_LOG_EVENT_COMBATSTATE = 1				-- LIBCOMBAT_EVENT_MESSAGES, timems, combatMessage, value
LIBCOMBAT_LOG_EVENT_DAMAGE = 2					-- LIBCOMBAT_EVENT_DAMAGE_OUT, timems, result, sourceUnitId, targetUnitId, abilityId, hitValue, damageType, overflow
LIBCOMBAT_LOG_EVENT_HEAL = 3					-- LIBCOMBAT_EVENT_HEAL_OUT, timems, result, sourceUnitId, targetUnitId, abilityId, hitValue, damageType, overflow
LIBCOMBAT_LOG_EVENT_EFFECT = 4					-- LIBCOMBAT_LOG_EVENT_EFFECT, timems, unitId, abilityId, changeType, effectType, stacks, sourceType, effectSlot
LIBCOMBAT_LOG_EVENT_STATS = 5					-- LIBCOMBAT_EVENT_PLAYERSTATS, timems, statchange, newvalue, statId
LIBCOMBAT_LOG_EVENT_RESOURCE = 6				-- LIBCOMBAT_EVENT_RESOURCES, timems, abilityId, powerValueChange, powerType, powerValue
LIBCOMBAT_LOG_EVENT_DEATH = 7					-- LIBCOMBAT_EVENT_DEATH, timems, state, unitId, abilityId/unitId
LIBCOMBAT_LOG_EVENT_SKILL_CAST = 8				-- LIBCOMBAT_EVENT_SKILL_TIMINGS, timems, reducedslot, abilityId, skillStatus, skillDelay, skillDuration
LIBCOMBAT_LOG_EVENT_PERFORMANCE = 9				-- LIBCOMBAT_EVENT_PERFORMANCE, timems, avg, min, max, ping
LIBCOMBAT_LOG_EVENT_QUICKSLOT = 10				-- LIBCOMBAT_EVENT_QUICKSLOT, timems, itemLink
LIBCOMBAT_LOG_EVENT_SYNERGY = 11				-- LIBCOMBAT_EVENT_SYNERGY, timems, abilityId, status	

LIBCOMBAT_UNIT_STATE_DEAD = 1
LIBCOMBAT_UNIT_STATE_ALIVE = 2
LIBCOMBAT_UNIT_STATE_RESURRECTING = 3
LIBCOMBAT_UNIT_STATE_RESURRECTED = 4

local CallbackKeys = {}

for i = LIBCOMBAT_EVENT_MIN, LIBCOMBAT_EVENT_MAX do
	CallbackKeys[i] = "LibCombat" .. i
end

lib.internal.callbackKeys = CallbackKeys

-- combatMessage

LIBCOMBAT_MESSAGE_COMBATSTART = 1
LIBCOMBAT_MESSAGE_COMBATEND = 2
LIBCOMBAT_MESSAGE_WEAPONSWAP = 3

-- skillStatus

LIBCOMBAT_SKILLSTATUS_INSTANT = 1
LIBCOMBAT_SKILLSTATUS_BEGIN_DURATION = 2
LIBCOMBAT_SKILLSTATUS_BEGIN_CHANNEL = 3
LIBCOMBAT_SKILLSTATUS_SUCCESS = 4
LIBCOMBAT_SKILLSTATUS_REGISTERED = 5
LIBCOMBAT_SKILLSTATUS_QUEUE = 6
LIBCOMBAT_SKILLSTATUS_CANCELLED = 6

-- statId

LIBCOMBAT_STAT_MAXMAGICKA = 1
LIBCOMBAT_STAT_SPELLPOWER = 2
LIBCOMBAT_STAT_SPELLCRIT = 3
LIBCOMBAT_STAT_SPELLCRITBONUS = 4
LIBCOMBAT_STAT_SPELLPENETRATION = 5

LIBCOMBAT_STAT_MAXSTAMINA = 11
LIBCOMBAT_STAT_WEAPONPOWER = 12
LIBCOMBAT_STAT_WEAPONCRIT = 13
LIBCOMBAT_STAT_WEAPONCRITBONUS = 14
LIBCOMBAT_STAT_WEAPONPENETRATION = 15

LIBCOMBAT_STAT_MAXHEALTH = 21
LIBCOMBAT_STAT_PHYSICALRESISTANCE = 22
LIBCOMBAT_STAT_SPELLRESISTANCE = 23
LIBCOMBAT_STAT_CRITICALRESISTANCE = 24
LIBCOMBAT_STAT_STATUS_EFFECT_CHANCE = 25

-- CP type

LIBCOMBAT_CPTYPE_PASSIVE = 0
LIBCOMBAT_CPTYPE_UNSLOTTED = 1
LIBCOMBAT_CPTYPE_SLOTTED = 2

-- Food buff Ids

local foodBuffIdToItemLinks = {
	[61218] = "|H0:item:68253:311:50:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h", 		-- Longfin Pasty with Melon Sauce
	[61255] = "|H0:item:68247:310:50:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h", 		-- Braised Rabbit with Spring Vegetables
	[61257] = "|H0:item:68243:310:50:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h", 		-- Melon-Baked Parmesan Pork
	[61259] = "|H0:item:43142:139:50:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h", 		-- Argonian Saddle-Cured Rabbit
	[61260] = "|H0:item:43154:139:50:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h", 		-- Fresh Apples and Eidar Cheese
	[61261] = "|H0:item:68239:309:50:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h", 		-- Hearty Garlic Corn Chowder
	[61294] = "|H0:item:68250:310:50:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h", 		-- Late Hearthfire Vegetable Tart
	[61322] = "|H0:item:68257:309:50:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h", 		-- Markarth Mead
	[61325] = "|H0:item:68260:309:50:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h", 		-- Muthsera's Remorse
	[61328] = "|H0:item:68263:309:50:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h", 		-- Hagraven's Tonic
	[61335] = "|H0:item:68266:310:50:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h", 		-- Bravil Bitter Barley Beer
	[61340] = "|H0:item:68268:310:50:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h", 		-- Camlorn Sweet Brown Ale
	[61345] = "|H0:item:68271:310:50:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h", 		-- Rosy Disposition Tonic
	[61350] = "|H0:item:68276:311:50:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h", 		-- Lusty Argonian Maid Mazte
	[68411] = "|H0:item:64711:123:1:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h", 		-- Crown Fortifying Meal
	[68416] = "|H0:item:64712:123:1:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h", 		-- Crown Refreshing Drink
	[71057] = "|H0:item:71057:4:1:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h", 		-- Orzorga's Tripe Trifle Pocket
	[72822] = "|H0:item:71058:4:1:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h", 		-- Orzorga's Blood Price Pie
	[72824] = "|H0:item:71059:6:1:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h", 		-- Orzorga's Smoked Bear Haunch
	[84720] = "|H0:item:87695:4:1:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h", 		-- Ghastly Eye Bowl
	[84731] = "|H0:item:87697:5:1:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h", 		-- Witchmother's Potent Brew
	[84709] = "|H0:item:87691:4:1:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h", 		-- Crunchy Spider Skewer
	[86673] = "|H0:item:112425:4:1:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h", 		-- Lava Foot Soup-and-Saltrice
	[89955] = "|H0:item:120762:4:1:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h", 		-- Candied Jester's Coins
	[89957] = "|H0:item:120763:5:1:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h ", 		-- Dubious Camoran Throne
	[89971] = "|H0:item:120764:5:1:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h", 		-- Jewels of Misrule
	[100498] = "|H0:item:133556:6:1:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h", 		-- Clockwork Citrus Filet
	[107748] = "|H0:item:139016:5:1:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h", 		-- Artaeum Pickled Fish Bowl
	[107789] = "|H0:item:139018:6:1:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h", 		-- Artaeum Takeaway Broth
	[127596] = "|H0:item:153629:6:1:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h", 		-- Bewitched Sugar Skulls
	[147687] = "|H0:item:171323:124:10:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0:0|h|h", 	-- Colovian War Torte
}

function lib.GetFoodDrinkItemLinkFromAbilityId(abilityId)
	return foodBuffIdToItemLinks[abilityId]
end

local MundusStones = {
	[13975] = true,
	[13980] = true,
	[13943] = true,
	[13978] = true,
	[13976] = true,
	[13981] = true,
	[13982] = true,
	[13979] = true,
	[13940] = true,
	[13985] = true,
	[13977] = true,
	[13984] = true,
	[13974] = true,
}

lib.MundusStones = MundusStones

local isFileInitialized = false
function lib.InitializeGlobals()

	if isFileInitialized == true then return false end

    isFileInitialized = true
	return true
end

