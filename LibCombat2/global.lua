-- This file contains definitions of global variables

local lib = LibCombat2
local CallbackKeys = {}
lib.internal.CallbackKeys = CallbackKeys

---@alias CallbackEventKey integer
---| "LIBCOMBAT_EVENT_MIN"
---| "LIBCOMBAT_EVENT_UNITS"
---| "LIBCOMBAT_EVENT_FIGHTRECAP"
---| "LIBCOMBAT_EVENT_FIGHTSUMMARY"
---| "LIBCOMBAT_EVENT_GROUPRECAP"
---| "LIBCOMBAT_EVENT_DEATHRECAP"
---| "LIBCOMBAT_EVENT_MAX"

LIBCOMBAT_EVENT_MIN = 50
LIBCOMBAT_EVENT_FIGHTRECAP = 50				-- LIBCOMBAT_EVENT_FIGHTRECAP, {data}
LIBCOMBAT_EVENT_FIGHTSUMMARY = 51			-- LIBCOMBAT_EVENT_FIGHTSUMMARY, {fight}
LIBCOMBAT_EVENT_DEATHRECAP = 52				-- LIBCOMBAT_EVENT_DEATHRECAP, timeMs, {data}
LIBCOMBAT_EVENT_MAX = 52

for i = LIBCOMBAT_EVENT_MIN, LIBCOMBAT_EVENT_MAX do
	CallbackKeys[i] = "LibCombat2" .. i
end

---@alias CallbackLogKey integer
---| "LIBCOMBAT_LOG_EVENT_MIN"
---| "LIBCOMBAT_LOG_EVENT_COMBATSTATE"
---| "LIBCOMBAT_LOG_EVENT_DAMAGE"
---| "LIBCOMBAT_LOG_EVENT_HEAL"
---| "LIBCOMBAT_LOG_EVENT_EFFECT"
---| "LIBCOMBAT_LOG_EVENT_STATS"
---| "LIBCOMBAT_LOG_EVENT_RESOURCE"
---| "LIBCOMBAT_LOG_EVENT_DEATH"
---| "LIBCOMBAT_LOG_EVENT_SKILL_CAST"
---| "LIBCOMBAT_LOG_EVENT_PERFORMANCE"
---| "LIBCOMBAT_LOG_EVENT_QUICKSLOT"
---| "LIBCOMBAT_LOG_EVENT_SYNERGY"
---| "LIBCOMBAT_LOG_EVENT_MAX"

---@alias CallbackKey CallbackLogKey | CallbackEventKey

LIBCOMBAT_LOG_EVENT_MIN = 1
LIBCOMBAT_LOG_EVENT_COMBATSTATE = 1				-- LIBCOMBAT_LOG_EVENT_COMBATSTATE, timeMs, combatMessage, value
LIBCOMBAT_LOG_EVENT_DAMAGE = 2					-- LIBCOMBAT_LOG_EVENT_DAMAGE, timeMs, result, sourceUnitId, targetUnitId, abilityId, hitValue, damageType, overflow
LIBCOMBAT_LOG_EVENT_HEAL = 3					-- LIBCOMBAT_LOG_EVENT_HEAL, timeMs, result, sourceUnitId, targetUnitId, abilityId, hitValue, damageType, overflow
LIBCOMBAT_LOG_EVENT_EFFECT = 4					-- LIBCOMBAT_LOG_EVENT_EFFECT, timeMs, unitId, abilityId, changeType, effectType, stacks, sourceType, effectSlot
LIBCOMBAT_LOG_EVENT_STATS = 5					-- LIBCOMBAT_LOG_EVENT_STATS, timeMs, statchange, newvalue, statId
LIBCOMBAT_LOG_EVENT_RESOURCE = 6				-- LIBCOMBAT_LOG_EVENT_RESOURCE, timeMs, abilityId, powerValueChange, powerType, powerValue
LIBCOMBAT_LOG_EVENT_DEATH = 7					-- LIBCOMBAT_LOG_EVENT_DEATH, timeMs, state, unitId, abilityId/unitId
LIBCOMBAT_LOG_EVENT_SKILL_CAST = 8				-- LIBCOMBAT_LOG_EVENT_SKILL_CAST, timeMs, reducedslot, abilityId, skillStatus, skillDelay, skillDuration
LIBCOMBAT_LOG_EVENT_PERFORMANCE = 9				-- LIBCOMBAT_LOG_EVENT_PERFORMANCE, timeMs, avg, min, max, ping
LIBCOMBAT_LOG_EVENT_QUICKSLOT = 10				-- LIBCOMBAT_LOG_EVENT_QUICKSLOT, timeMs, itemLink
LIBCOMBAT_LOG_EVENT_MAX = 10

for i = LIBCOMBAT_LOG_EVENT_MIN, LIBCOMBAT_LOG_EVENT_MAX do
	CallbackKeys[i] = "LibCombat2" .. i
end



-- state

LIBCOMBAT_UNIT_STATE_DEAD = 1
LIBCOMBAT_UNIT_STATE_ALIVE = 2
LIBCOMBAT_UNIT_STATE_RESURRECTING = 3
LIBCOMBAT_UNIT_STATE_RESURRECTED = 4

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

---comment
---@param abilityId integer
---@return string itemLink
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

---@param abilityId integer
---@return boolean
function lib.IsMundusBuff(abilityId)
	return MundusStones[abilityId] == true
end

lib.internal.abilityIdZen = 126597
lib.internal.abilityIdForceOfNature = 174250

local isFileInitialized = false
function lib.internal.InitializeGlobals()
	if isFileInitialized == true then return false end

    isFileInitialized = true
	return true
end

