--[[
This lib is supposed to act as an interface between the API of Eso and potential addons that want to display Combat Data (e.g. dps)
I extracted it from Combat Metrics, for which most of the functions are designed. I believe however that it's possible that others can use it.

Todo:
Falling Damage (also save routine!!)
Check what events fire on death
Implement tracking when players are resurrecting
implement group info function
work on the addon description
Add more debug Functions

]]
---@class LibCombat
local lib = LibCombat

-- Basic Parameters

local ABILITY_RESOURCE_CACHE_SIZE = 20

-- Logger

local logger
local LOG_LEVEL_VERBOSE = "V"
local LOG_LEVEL_DEBUG = "D"
local LOG_LEVEL_INFO = "I"
local LOG_LEVEL_WARNING ="W"
local LOG_LEVEL_ERROR = "E"

if LibDebugLogger then

	---@type Logger
	logger = LibDebugLogger.Create(lib.name)

	LOG_LEVEL_VERBOSE = LibDebugLogger.LOG_LEVEL_VERBOSE
	LOG_LEVEL_DEBUG = LibDebugLogger.LOG_LEVEL_DEBUG
	LOG_LEVEL_INFO = LibDebugLogger.LOG_LEVEL_INFO
	LOG_LEVEL_WARNING = LibDebugLogger.LOG_LEVEL_WARNING
	LOG_LEVEL_ERROR = LibDebugLogger.LOG_LEVEL_ERROR

	logger.doa = logger:Create("DoA")
	logger.other = logger:Create("other")
	logger.fight = logger:Create("fight")
	logger.events = logger:Create("events")
	logger.debug = logger:Create("debug")

end

local function Log(category, level, ...)
	if logger == nil then return end
	if level == LOG_LEVEL_DEBUG or level == LOG_LEVEL_VERBOSE then return end
	logger = category and logger[category] or logger
	if category == "debug" and lib.debug ~= true then return end
	if type(logger.Log)=="function" then logger:Log(level, ...) end
end

-- aliases

local em = GetEventManager()
local _
local reset = false
local data = lib.data
local timeout = 800
local activetimeonheals = true
local ActiveCallbackTypes = {}
lib.ActiveCallbackTypes = ActiveCallbackTypes
local CustomAbilityTypeList = {}
local currentfight
local Events = {}
local EffectBuffer = {}
local abilityIdZen = 126597
local abilityIdForceOfNature = 174250
local lastdeaths = {}
local SlotSkills = {}
local IdToReducedSlot = {}
local lastAbilityActivations = {}
local isProjectile = {}
local isInPortalWorld = false	-- used to prevent fight reset in Cloudrest/Sunspire when using a portal.

local lastBossHealthValue = 2

local CombatEventCache = {}
local maxUnitCacheEvents = 60
local UnitDeathsToProcess = {}
local deathRecapTimePeriod = 10000

local playerActivatedTime = 10000
local lastQueuedAbilities = {}
local usedCastTimeAbility = {}
local maxSkillDelay = GetDisplayName() == "@Chronix1753" and 10000 or 2000

local DamageShieldBuffer = {}

local registeredSkills = {}
lib.registeredSkills = registeredSkills

local onTFSChanged

-- localize some functions for performance

local ZO_CachedStrFormat = ZO_CachedStrFormat

-- types of callbacks: Units, DPS/HPS, DPS/HPS for Group, Logevents

local CallbackKeys = {}

for i = LIBCOMBAT_EVENT_MIN, LIBCOMBAT_EVENT_MAX do
	CallbackKeys[i] = "LibCombat" .. i
end

-- Strings

local BadAbility = {
	[51487] = true,
	[20546] = true,
	[69168] = true,
	[52515] = true,
	[41189] = true,
	-- [61898] = true, -- Minor Savagery, too spammy
	[63601] = true, -- ESO Plus
}

local SpecialBuffs = {	-- buffs that the API doesn't show via EVENT_EFFECT_CHANGED and need to be specially tracked via EVENT_COMBAT_EVENT

	21230,	-- Weapon/spell power enchant (Berserker)
	21578,	-- Damage shield enchant (Hardening)
	71067,	-- Trial By Fire: Shock
	71058,	-- Trial By Fire: Fire
	71019,	-- Trial By Fire: Frost
	71069,	-- Trial By Fire: Disease
	71072,	-- Trial By Fire: Poison
	49236,	-- Whitestrake's Retribution
	57170,	-- Blood Frenzy
	75726,	-- Tava's Favor
	75746,	-- Clever Alchemist
	61870,	-- Armor Master Resistance
	71107,	-- Briarheart
	122729,	-- Seething Fury Stat Buff
}


local SpecialDebuffs = {   -- debuffs that the API doesn't show via EVENT_EFFECT_CHANGED and need to be specially tracked via EVENT_COMBAT_EVENT

	178118,	-- Status Effect Magic (Overcharged)
	95136,  -- Status Effect Frost (Chill, used for tracking Warden crit damage buff)
	95134,  -- Status Effect Lightning (Concussion)
	178123,  -- Status Effect Physical (Sundered)
	178127,  -- Status Effect Foulness (Diseased)
	148801,  -- Status Effect Bleeding (Hemorrhaging)
}

local SourceBuggedBuffs = {   -- buffs where ZOS messed up the source, causing CMX to falsely not track them

	88401,  -- Minor Magickasteal
}

local StatusEffectIds = {

	[178118] = true, -- Magic (Overcharged)
	[18084]  = true, -- Fire (Burning)
	[95136]  = true, -- Frost (Chill)
	[95134]  = true, -- Lightning (Concussion)
	[178123] = true, -- Physical (Sundered)
	[21929]  = true, -- Poison (Poisoned)
	[178127] = true, -- Foulness (Diseased)
	[148801] = true, -- Bleeding (Hemorrhaging)
}

local abilityConversions = {	-- Ability conversions for tracking skill activations

	[22178] = {22179, 2240, nil, nil}, --Sun Shield --> Sun Shield
	[22182] = {22183, 2240, nil, nil}, --Radiant Ward --> Radiant Ward
	[22180] = {49091, 2240, nil, nil}, --Blazing Shield --> Blazing Shield

	[26209] = {26220, 2240, nil, nil}, --Restoring Aura --> Minor Magickasteal
	[26807] = {26809, 2240, nil, nil}, --Radiant Aura --> Minor Magickasteal
	[26821] = {29824, nil, nil, nil}, --Repentance? --> Repentance?

	[29173] = {53881, 2240, nil, nil}, --Weakness to Elements --> Major Breach
	[39089] = {62775, 2240, nil, nil}, --Elemental Susceptibility --> Major Breach
	[39095] = {62787, 2240, nil, nil}, --Elemental Drain --> Major Breach

	[28799] = {146553, nil, nil, nil}, --Shock Impulse --> Shock Impulse
	[39162] = {170989, nil, nil, nil}, --Flame Pulsar --> Flame Pulsar
	[39167] = {146593, nil, nil, nil}, --Storm Pulsar --> Storm Pulsar
	[39163] = {170990, nil, nil, nil}, --Frost Pulsar --> Frost Pulsar

	[29556] = {63015, 2240, nil, nil}, --Evasion --> Major Evasion
	[39195] = {63019, 2240, nil, nil}, --Shuffle --> Major Evasion
	[39192] = {63030, 2240, nil, nil}, --Elude --> Major Evasion

	[103492] = {103492, 2240, 103492, 2250}, --Meditate --> Meditate
	[103652] = {103652, 2240, 103652, 2250}, --Deep Thoughts --> Deep Thoughts
	[103665] = {103665, 2240, 103665, 2250}, --Introspection --> Introspection

	[103503] = {103521, 2240, nil, nil}, --Accelerate --> Minor Force
	[103706] = {103706, nil, 103708, 2240}, --Channeled Acceleration --> Minor Force
	[103710] = {122260, 2240, nil, nil}, --Race Against Time --> Race Against Time

	[103478] = {108609, 2240, nil, nil}, --Undo --> Undo
	[103557] = {108621, 2240, nil, nil}, --Precognition --> Precognition
	[103564] = {108641, 2240, nil, nil}, --Temporal Guard --> Temporal Guard

	[61503] = {61504, 2240, nil, nil}, --Vigor --> Vigor
	[61505] = {61506, 2240, nil, nil}, --Echoing Vigor --> Echoing Vigor
	[61507] = {61509, 2240, nil, nil}, --Resolving Vigor --> Resolving Vigor

	[38566] = {101161, 2240, nil, nil}, --Rapid Maneuver --> Major Expedition
	[40211] = {101169, 2240, nil, nil}, --Retreating Maneuver --> Major Expedition
	[40215] = {101178, 2240, nil, nil}, --Charging Maneuver --> Major Expedition

	[38563] = {38564, 2240, nil, nil}, --War Horn --> War Horn
	[40223] = {40224, 2240, nil, nil}, --Aggressive Horn --> Aggressive Horn
	[40220] = {40221, 2240, nil, nil}, --Sturdy Horn --> Sturdy Horn

	[28279] = {28279, 2200, 28279, nil}, --Uppercut --> Uppercut
	[38814] = {38814, 2200, 38814, nil}, --Dizzying Swing --> Dizzying Swing
	[38807] = {38807, 2200, 38807, nil}, --Wrecking Blow --> Wrecking Blow

	[83600] = {83600, 2200, 85156, 2240}, --Lacerate --> Lacerate
	[85187] = {85187, 2200, 85192, 2240}, --Rend --> Rend
	[85179] = {85179, 2200, 85182, 2240}, --Thrive in Chaos --> Thrive in Chaos

	[31531] = {88565, 2240, nil, nil}, --Force Siphon --> Force Siphon
	[40109] = {88575, 2240, nil, nil}, --Siphon Spirit --> Siphon Spirit
	[40116] = {88606, nil, nil, nil}, --Quick Siphon --> Minor Lifesteal

	[29043] = {92507, 2240, nil, nil}, --Molten Weapons --> Major Sorcery
	[31874] = {92503, 2240, nil, nil}, --Igneous Weapons --> Major Sorcery
	[31888] = {92512, 2240, nil, nil}, --Molten Armaments --> Major Sorcery

	[33375] = {90587, 2240, nil, nil}, --Blur --> Major Evasion
	[35414] = {90593, 2240, nil, nil}, --Mirage --> Major Evasion
	[35419] = {90620, 2240, nil, nil}, --Phantasmal Escape --> Major Evasion

	[35445] = {35451, 2250, nil, nil}, --Shadow Image Teleport --> Shadow Image

	[24584] = {nil, nil, 114903, 2250}, --Dark Exchange --> Dark Exchange
	[24595] = {nil, nil, 114908, 2250}, --Dark Deal -->
	[24589] = {nil, nil, 114909, 2250}, --Dark Conversion -->

	[108840] = {108842, 2240, nil, nil}, --Summon Unstable Familiar --> Unstable Familiar Damage Pulse
	[76076] = {76078, nil, nil, nil}, --Summon Unstable Clannfear --> Clannfear Heal
	[77182] = {77187, 2240, nil, nil}, --Summon Volatile Familiar --> Volatile Famliiar Damage Pulsi

	[108845] = {108846, 16, nil, nil}, --Winged Twilight Restore --> Winged Twilight Restore
	[77140] = {77354, 2240, nil, nil}, --Summon Twilight Tormentor  --> Twilight Tormentor Enrage
	[77369] = {77371, 16, nil, nil}, --Twilight Matriarch Restore --> Twilight Matriarch Restore

	[23234] = {51392, 2240, nil, nil}, --Bolt Escape --> Bolt Escape Fatigue
	[23236] = {51392, 2240, nil, nil}, --Streak --> Bolt Escape Fatigue

	[85922] = {85841, nil, nil, nil}, --Budding Seeds (2nd cast) --> Budding Seeds Heal

	[86122] = {86224, 2240, nil, nil}, --Frost Cloak --> Major Resolve
	[86126] = {88758, 2240, nil, nil}, --Expansive Frost Cloak --> Major Resolve
	[86130] = {88761, 2240, nil, nil}, --Ice Fortress --> Major Resolve

	[115238] = {119372, 2240, nil, nil}, --Bitter Harvest --> Bitter Harvest
	[118623] = {118624, 2240, nil, nil}, --Deaden Pain --> Deaden Pain
	[118639] = {121797, 2240, nil, nil}, --Necrotic Potency --> Necrotic Potency

	[114860] = {114861, 2240, nil, nil}, --Blastbones --> Blastbones
	[117330] = {114861, 2240, nil, nil}, --Blastbones --> Blastbones
	[117690] = {117691, 2240, nil, nil}, --Blighted Blastbones --> Blighted Blastbones
	[117693] = {117691, 2240, nil, nil}, --Blighted Blastbones --> Blighted Blastbones (Id when greyed out)
	[117749] = {117750, 2240, nil, nil}, --Stalking Blastbones --> Stalking Blastbones
	[117773] = {117750, 2240, nil, nil}, --Stalking Blastbones --> Stalking Blastbones (Id when greyed out)

	--[115307] = {???, nil, nil, nil}, --Expunge -->
	[117940] = {117947, 2240, nil, nil}, --Expunge and Modify --> Expunge and Modify
	--[117919] = {???, nil, nil, nil}, --Hexproof -->

	[28567] = {126370, 2240, nil, nil}, --Entropy --> Entropy
	[40457] = {126374, 2240, nil, nil}, --Degeneration --> Degeneration
	[40452] = {126371, 2240, nil, nil}, --Structured Entropy --> Structured Entropy

	[16536] = {163227, 2240, nil, nil}, --Meteor --> Meteor
	[40493] = {163236, 2240, nil, nil}, --Shooting Star --> Shooting Star
	[40489] = {163238, 2240, nil, nil}, --Ice Comet --> Meteor

	[185836] = {185838, 2240, nil, nil}, --The Imperfect Ring (Stam) --> The Imperfect Ring
	[201286] = {185838, 2240, nil, nil}, --The Imperfect Ring (Mag) --> The Imperfect Ring
	[185839] = {185841, 2240, nil, nil}, --Rune of Displacement (Stam) --> Rune of Displacement
	[201293] = {185841, 2240, nil, nil}, --Rune of Displacement (Mag) --> Rune of Displacement
	[182988] = {182989, 2240, nil, nil}, --Fulminating Rune (Stam) --> Fulminating Rune
	[201296] = {182989, 2240, nil, nil}, --Fulminating Rune (Mag) --> Fulminating Rune

	[185912] = {185913, 2240, nil, nil}, --Runic Defense --> Minor Resolve
	[186489] = {186490, 2240, nil, nil}, --Runeguard of Freedom --> Minor Resolve

}

local abilityAdditions = { -- Abilities to register additionally because they change in fight

	[61902] = 61907,    -- Grim Focus --> Assasins Will
	[61907] = 61902,    -- Assasins Will --> Grim Focus
	[61919] = 61930,    -- Merciless Resolve --> Assasins Will
	[61930] = 61919,    -- Assasins Will --> Merciless Resolve
	[61927] = 61932,    -- Relentless Focus --> Assasins Scourge
	[61932] = 61927,    -- Assasins Scourge --> Relentless Focus
	[46324] = 114716,  	-- Crystal Fragments Proc
	[114716] = 46324,  	-- Crystal Fragments Proc
	[185836] = 201286,  	-- The Imperfect Ring (Stam) --> (Mag)
	[201286] = 185836,  	-- The Imperfect Ring (Mag) --> (Stam)
	[185839] = 201293,  	-- Rune of Displacement (Stam) --> (Mag)
	[201293] = 185839,  	-- Rune of Displacement (Mag) --> (Stam)
	[182988] = 201296,  	-- Fulminating Rune (Stam) --> (Mag)s
	[201296] = 182988,  	-- Fulminating Rune (Mag) --> (Stam)
	[185794] = 188658,  	-- Runeblades (Stam) --> (Mag)
	[188658] = 185794,  	-- Runeblades (Mag) --> (Stam)
	[185805] = 193331,  	-- Fatecarver (Stam) --> (Mag)
	[193331] = 185805,  	-- Fatecarver (Mag) --> (Stam)
	[183261] = 198282,  	-- Runemend (Stam) --> (Mag)
	[198282] = 183261,  	-- Runemend (Mag) --> (Stam)
	[183537] = 198309,  	-- Remedy Cascade (Stam) --> (Mag)
	[198309] = 183537,  	-- Remedy Cascade (Mag) --> (Stam)
	[183447] = 198563,  	-- Chakram Shields (Stam) --> (Mag)
	[198563] = 183447,  	-- Chakram Shields (Mag) --> (Stam)
	[185803] = 188787,  	-- Writhing Runeblades (Stam) --> (Mag)
	[188787] = 185803,  	-- Writhing Runeblades (Mag) --> (Stam)
	[183122] = 193397,  	-- Exhausting Fatecarver (Stam) --> (Mag)
	[193397] = 183122,  	-- Exhausting Fatecarver (Mag) --> (Stam)
	[186189] = 198288,  	-- Evolving Runemend (Stam) --> (Mag)
	[198288] = 186189,  	-- Evolving Runemend (Mag) --> (Stam)
	[186193] = 198330,  	-- Cascading Fortune (Stam) --> (Mag)
	[198330] = 186193,  	-- Cascading Fortune (Mag) --> (Stam)
	[186207] = 198564,  	-- Chakram of Destiny (Stam) --> (Mag)
	[198564] = 186207,  	-- Chakram of Destiny (Mag) --> (Stam)
	[182977] = 188780,  	-- Escalating Runeblades (Stam) --> (Mag)
	[188780] = 182977,  	-- Escalating Runeblades (Mag) --> (Stam)
	[186366] = 193398,  	-- Pragmatic Fatecarver (Stam) --> (Mag)
	[193398] = 186366,  	-- Pragmatic Fatecarver (Mag) --> (Stam)
	[186191] = 198292,  	-- Audacious Runemend (Stam) --> (Mag)
	[198292] = 186191,  	-- Audacious Runemend (Mag) --> (Stam)
	[186200] = 198537,  	-- Curative Surge (Stam) --> (Mag)
	[198537] = 186200,  	-- Curative Surge (Mag) --> (Stam)
	[186209] = 198567,  	-- Tidal Chakram (Stam) --> (Mag)
	[198567] = 186209,  	-- Tidal Chakram (Mag) --> (Stam)
}

local abilityAdditionsReverse = {}
for k,v in pairs(abilityAdditions) do
	abilityAdditionsReverse[v] = k
end

local DirectHeavyAttacks = {	-- for special handling to detect their end

	[16041] = true, -- 2H
	[15279] = true, -- 1H+S
	[16420] = true, -- DW
	[16691] = true, -- Bow
	[15383] = true, -- Inferno
	[16261] = true, -- Frost
	[32477] = true, -- Werewolf

}

local validSkillStartResults = {

	[ACTION_RESULT_BLOCKED_DAMAGE] = true, -- 2151
	[ACTION_RESULT_DAMAGE_SHIELDED] = true, -- 2460
	[ACTION_RESULT_SNARED] = true, -- 2025
	[ACTION_RESULT_BEGIN] = true, -- 2200
	[ACTION_RESULT_EFFECT_GAINED] = true, -- 2240
	[ACTION_RESULT_KNOCKBACK] = true, -- 2275
	[ACTION_RESULT_IMMUNE] = true, -- 2000

}

local validNonProjectileSkillStartResults = {

	[ACTION_RESULT_DAMAGE] = true, -- 1
	[ACTION_RESULT_CRITICAL_DAMAGE] = true, -- 2
	[ACTION_RESULT_HEAL] = true, -- 16
	[ACTION_RESULT_CRITICAL_HEAL] = true, -- 32

}

local validSkillEndResults = {

	[ACTION_RESULT_EFFECT_GAINED] = true, -- 2240
	[ACTION_RESULT_EFFECT_FADED] = true, -- 2250

}

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



local GetFormattedAbilityName = lib.GetFormattedAbilityName

local UnitHandler = ZO_Object:Subclass()

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

		data.playerid = unitId
		currentfight.playerid = unitId
		self.displayname = data.accountname
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

	local groupdata = data.groupInfo

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

	if abilityId == abilityIdZen then

		local isActive = changeType == EFFECT_RESULT_GAINED -- or (changeType == EFFECT_RESULT_UPDATED)
		local stacks = isActive and math.min(self.stacksOfZen, 5) or 0

		lib.cm:FireCallbacks(callbackKeys, eventid, timeMs, unitId, abilityIdZen, changeType, effectType, stacks, sourceType, effectSlot)	-- stack count is 1 to 6, with 1 meaning 0% bonus, and 6 meaning 5% bonus from Z'en
		Log("debug", LOG_LEVEL_VERBOSE, table.concat({eventid, timeMs, unitId, abilityIdZen, changeType, effectType, stacks, sourceType, effectSlot}, ", "))
		self.zenEffectSlot = (isActive and effectSlot) or nil

	elseif abilityType == ABILITY_TYPE_DAMAGE then

		if changeType == EFFECT_RESULT_GAINED then

			self.stacksOfZen = self.stacksOfZen + 1

		elseif changeType == EFFECT_RESULT_FADED then

			if self.stacksOfZen - 1 < 0 then Log("debug", LOG_LEVEL_WARNING, "Encountered negative Z'en stacks: %s (%d)", GetFormattedAbilityName(abilityId), abilityId) end
			self.stacksOfZen = math.max(0, self.stacksOfZen - 1)

		end

		if self.zenEffectSlot then

			local stacks = math.min(self.stacksOfZen, 5)
			lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_EFFECTS_OUT]), LIBCOMBAT_EVENT_EFFECTS_OUT, timeMs, unitId, abilityIdZen, EFFECT_RESULT_UPDATED, effectType, stacks, sourceType, self.zenEffectSlot)

		end
	end
end

function UnitHandler:UpdateForceOfNatureData(_, _, timeMs, unitId, abilityId, changeType, _, _, _, _)

	if StatusEffectIds[abilityId] == nil or currentfight.CP[1]["slotted"] == nil or currentfight.CP[1]["slotted"][276] ~= true then return end

	local forceOfNatureChangeType = EFFECT_RESULT_UPDATED

	local debugChangeType = "o"

	if changeType == EFFECT_RESULT_GAINED and self.forceOfNature[abilityId] == nil then

		self.forceOfNature[abilityId] = true

		self.forceOfNatureStacks = self.forceOfNatureStacks + 1

		if self.forceOfNatureStacks == 1 then forceOfNatureChangeType = EFFECT_RESULT_GAINED end
		if self.forceOfNatureStacks > 8 then Log("debug", LOG_LEVEL_WARNING, "Encountered too many Force of Nature stacks (%d): %s (%d)", self.forceOfNatureStacks, GetFormattedAbilityName(abilityId), abilityId) end
		debugChangeType = "+"

	elseif changeType == EFFECT_RESULT_FADED and self.forceOfNature[abilityId] == true then

		self.forceOfNature[abilityId] = nil

		if self.forceOfNatureStacks == 0 then forceOfNatureChangeType = EFFECT_RESULT_FADED end
		if self.forceOfNatureStacks - 1 < 0 then Log("debug", LOG_LEVEL_WARNING, "Encountered negative Force of Nature stacks: %s (%d)", GetFormattedAbilityName(abilityId), abilityId) end

		self.forceOfNatureStacks = math.max(0, self.forceOfNatureStacks - 1)
		debugChangeType = "-"

	end

	local stacks = math.min(self.forceOfNatureStacks, 8)
	lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_EFFECTS_OUT]), LIBCOMBAT_EVENT_EFFECTS_OUT, timeMs, unitId, abilityIdForceOfNature, forceOfNatureChangeType, BUFF_EFFECT_TYPE_DEBUFF, stacks, COMBAT_UNIT_TYPE_PLAYER, 0)
	Log("debug", LOG_LEVEL_VERBOSE, "Force of Nature: %s (%d) x%d, %s%s", self.name, self.unitId, stacks, GetFormattedAbilityName(abilityId), debugChangeType)
end

local FightHandler = ZO_Object:Subclass()

---@diagnostic disable-next-line: duplicate-set-field
function FightHandler:New(...)
    local object = ZO_Object.New(self)
    object:Initialize(...)
    return object
end

function FightHandler:Initialize(...)
	self.char = data.playername
	self.combatstart = 0 - timeout - 1	-- start of combat in ms
	self.combatend = -150				-- end of combat in ms
	self.combattime = 0 				-- total combat time
	self.dpsstart = nil 				-- start of dps in ms
	self.dpsend = nil				 	-- end of dps in ms
	self.hpsstart = nil 				-- start of hps in ms
	self.hpsend = nil				 	-- end of hps in ms
	self.dpstime = 0					-- total dps time
	self.hpstime = 0					-- total dps time
	self.units = {}
	self.grplog = {}					-- log from group actions
	self.groupDamageOut = 0				-- dmg from and to the group
	self.groupDamageIn = 0				-- dmg from and to the group
	self.groupHealingOut = 0				-- heal of the group
	self.groupHealingIn = 0				-- heal of the group
	self.groupDPSOut = 0				-- group dps
	self.groupDPSIn = 0					-- incoming dps	on group
	self.groupHPSOut = 0				-- group hps
	self.groupHPSIn = 0					-- group hps
	self.damageOutTotal = 0				-- total damage out
	self.healingOutTotal = 0			-- total healing out
	self.healingOutAbsolute = 0			-- total healing out including Overheal
	self.damageInTotal = 0				-- total damage in
	self.damageInShielded = 0			-- total damage in shielded
	self.healingInTotal = 0				-- total healing in
	self.DPSOut = 0						-- dps
	self.HPSOut = 0						-- hps
	self.HPSAOut = 0					-- hps including Overheal
	self.DPSIn = 0						-- incoming dps
	self.HPSIn = 0						-- incoming hps
	self.group = data.inGroup
	self.playerid = data.playerid
	self.bosses = {}
	self.dataVersion = 2
	self.special = {}	-- for storing special information (like glacial presence before update 36)
end

local onCombatState

function FightHandler:ResetFight()
	if data.inCombat ~= true then return end

	reset = true

	self:FinishFight()
	self:onUpdate()

	currentfight:PrepareFight()

	onCombatState(EVENT_PLAYER_COMBAT_STATE, IsUnitInCombat("player"))
end

function lib.ResetFight()
	currentfight:ResetFight()
end

local DivineSlots = {EQUIP_SLOT_HEAD, EQUIP_SLOT_SHOULDERS, EQUIP_SLOT_CHEST, EQUIP_SLOT_HAND, EQUIP_SLOT_WAIST, EQUIP_SLOT_LEGS, EQUIP_SLOT_FEET}

local function ParseDescriptionBonus(description, startIndex)
	local bonus = {description:match("cffffff[un ]*(%d+)%p?(%d*)[%%|][r|]", startIndex)}
	local bonusString = table.concat(bonus, ".")
	return tonumber(bonusString)
end

local function GetShadowBonus(effectSlot)
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

	Log("other", LOG_LEVEL_INFO, "Shadow Mundus Offset: %d%% (calc %d%% - ZOS %d%%)", data.critBonusMundus, calcBonus, ZOSBonus)
end

local function GetPlayerBuffs(timems)

	local newtime = timems

	if Events.Effects.active == false then return end

	if data.playerid == nil then

		zo_callLater(function() GetPlayerBuffs(timems) end, 100)
		return

	end

	data.critBonusMundus = 0

	for i=1,GetNumBuffs("player") do

		-- buffName, timeStarted, timeEnding, effectSlot, stackCount, iconFilename, buffType, effectType, abilityType, statusEffectType, abilityId, canClickOff, castByPlayer

		local _, _, endTime, effectSlot, stackCount, _, _, effectType, abilityType, _, abilityId, _, castByPlayer = GetUnitBuffInfo("player",i)

		-- Log("events", LOG_LEVEL_VERBOSE, "player has the %s %d x %s (%d, ET: %d, self: %s)", effectType == BUFF_EFFECT_TYPE_BUFF and "buff" or "debuff", stackCount, GetFormattedAbilityName(abilityId), abilityId, abilityType, tostring(castByPlayer))

		local unitType = castByPlayer and COMBAT_UNIT_TYPE_PLAYER or COMBAT_UNIT_TYPE_NONE

		local stacks = zo_max(stackCount,1)

		local playerid = data.playerid

		if (not BadAbility[abilityId]) then

			lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_EFFECTS_IN]), LIBCOMBAT_EVENT_EFFECTS_IN, newtime, playerid, abilityId, EFFECT_RESULT_GAINED, effectType, stacks, unitType, effectSlot)
			--timems, unitId, abilityId, changeType, effectType, stacks, sourceType

		end

		if abilityId ==	13984 then GetShadowBonus(effectSlot) end

		if abilityId ==	51176 then -- TFS workaround

			onTFSChanged(_, EFFECT_RESULT_GAINED, _, _, _, _, _, stackCount)

		end
	end
end

local function GetOtherBuffs(timems)

	local newtime = timems

	for unitId, unitData in pairs(EffectBuffer) do

		for abilityId, abilityData in pairs(unitData) do

			local endTime, logdata, abilityType = unpack(abilityData)

			logdata[2] = newtime
			local sourceType = logdata[8]

			if sourceType ~= COMBAT_UNIT_TYPE_PLAYER or abilityId ~= abilityIdZen then lib.cm:FireCallbacks((CallbackKeys[logdata[1]]), unpack(logdata)) end

			if sourceType == COMBAT_UNIT_TYPE_PLAYER and (abilityId == abilityIdZen or abilityType == ABILITY_TYPE_DAMAGE) then

				local unit = currentfight.units[unitId]
				if unit then unit:UpdateZenData((CallbackKeys[logdata[1]]), unpack(logdata), abilityType) end

			end

			if sourceType == COMBAT_UNIT_TYPE_PLAYER and StatusEffectIds[abilityId] then

				local unit = currentfight.units[unitId]
				if unit then unit:UpdateForceOfNatureData((CallbackKeys[logdata[1]]), unpack(logdata)) end

			end
		end
	end

	EffectBuffer = {}
end

local function GetCritBonusFromCP(CPdata)
	local slots = CPdata[1].slotted
	local points = CPdata[1].stars

	local backstabber = slots[31] and (2 * math.floor(0.1 * points[31][1])) or 0 -- Backstabber 2% per every full 10 points (flanking!)

	return backstabber
end

local function GetCurrentCP()
	local CP = {}
	CP.version = 2

	-- collect slotted stars
	local slotsById = {}
	for slotIndex = 1, 12 do
		local starId = GetSlotBoundId(slotIndex, HOTBAR_CATEGORY_CHAMPION)
		if starId > 0 then
			slotsById[starId] = slotIndex
		end
	end

	--  collect CP data

	local disciplines = CHAMPION_DATA_MANAGER.disciplineDatas

	for _, discipline in pairs(disciplines) do

		local disciplineId = discipline.disciplineId
		local stars = discipline.championSkillDatas

		local disciplineData = {}
		CP[disciplineId] = disciplineData

		disciplineData.total = discipline:GetNumSavedSpentPoints()
		disciplineData.stars = {}
		disciplineData.slotted = {}

		local discStarData = disciplineData.stars
		local discSlotData = disciplineData.slotted

		for _, star in pairs(stars) do

			local savedPoints = star:GetNumSavedPoints()

			if savedPoints > 0 then

				local starId = star.championSkillId

				local slotable = star:IsTypeSlottable()
				local slotted = slotsById[starId] ~= nil

				local starType = (slotted and LIBCOMBAT_CPTYPE_SLOTTED) or (slotable and LIBCOMBAT_CPTYPE_UNSLOTTED) or LIBCOMBAT_CPTYPE_PASSIVE

				discStarData[starId] = {savedPoints, starType}
				if slotted then discSlotData[starId] = true end

			end
		end
	end

	return CP
end

local function PurgeEffectBuffer(timems)

	for id, unit in pairs(EffectBuffer) do

		for _, data in pairs(unit) do

			local timeend = data[1]

			if timems/1000 > timeend then unit[id] = nil end

		end
	end
end

local function GetSkillRegistrationData(abilityId)

	local channeled, castTime = GetAbilityCastInfo(abilityId)

	local convertedId, result, convertedId2, result2 = unpack(abilityConversions[abilityId] or {})

	local result = result or (castTime > 0 and ACTION_RESULT_BEGIN) or nil

	local result2 = result2 or (castTime > 0 and ACTION_RESULT_EFFECT_GAINED) or (channeled and ACTION_RESULT_EFFECT_FADED) or nil

	local convertedId = convertedId or abilityId
	local convertedId2 = convertedId2 or abilityId

	local data = result2 and {convertedId, result, convertedId2, result2} or {convertedId, result}

	return data

end

local function UpdateSlotSkillEvents()

	local events = Events.Skills

	if not events.active then return end

	SlotSkills = {}

	local registeredIds = {}

	if data.skillBars == nil then data.skillBars = {} end

	for _, bar in pairs(data.skillBars) do

		for _, abilityId in pairs(bar) do

			if registeredIds[abilityId] == nil then

				registeredIds[abilityId] = true

				table.insert(SlotSkills, GetSkillRegistrationData(abilityId))

				if abilityAdditions[abilityId] then table.insert(SlotSkills, GetSkillRegistrationData(abilityAdditions[abilityId])) end
			end
		end
	end

	events:Update()
end

local function GetSlottedAbilityId(actionSlotIndex, hotbarCategory)	-- thanks to Anthonysc for the snippet
	hotbarCategory = hotbarCategory or GetActiveHotbarCategory()
	local actionType = GetSlotType(actionSlotIndex, hotbarCategory)
	local abilityId = GetSlotBoundId(actionSlotIndex, hotbarCategory)

	if actionType == ACTION_TYPE_CRAFTED_ABILITY then
		return GetAbilityIdForCraftedAbilityId(abilityId), abilityId
	end

	return abilityId, nil
end

local function GetCurrentSkillBars()
	local skillBars = data.skillBars
	local scribedSkills = data.scribedSkills
	local bar = data.bar

	skillBars[bar] = {}
	local currentbar = skillBars[bar]
	local hotbarCategory = GetActiveHotbarCategory()

	for i = 1, 8 do
		local id, scribedAbilityId = GetSlottedAbilityId(i, hotbarCategory)
		currentbar[i] = id
		local reducedslot = (bar - 1) * 10 + i
		local conversion = abilityConversions[id]
		local convertedId = conversion and conversion[1] or id

		IdToReducedSlot[convertedId] = reducedslot

		if conversion and conversion[3] then IdToReducedSlot[conversion[3]] = reducedslot end
		if scribedAbilityId and scribedSkills[id] == nil then
			scribedSkills[id] = {GetCraftedAbilityActiveScriptIds(scribedAbilityId)}
			Log("debug", LOG_LEVEL_INFO, "ScribedSkill: ", scribedAbilityId, unpack(scribedSkills[id]))
		end
	end
	UpdateSlotSkillEvents()
end

local function onPlayerActivated()

	zo_callLater(GetCurrentSkillBars, 100)
	isInPortalWorld = false

end

local function onBossesChanged(_) -- Detect Bosses
	data.bossInfo = {}
	local bossdata = data.bossInfo

	for i = 1, 12 do
		local unitTag = ZO_CachedStrFormat("boss<<1>>", i)

		if DoesUnitExist(unitTag) then
			local name = GetUnitName(unitTag)

			bossdata[name] = i
			currentfight.bossfight = true
			if currentfight.bossname == nil and name ~= nil and name ~= "" then currentfight.bossname = name end
		elseif i >= 2 then
			return
		end
	end
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
		Log("main", LOG_LEVEL_WARNING, "Failed to parse description for SE bonus: %s", description)
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
	local bonus = ParseDescriptionBonus(ParseDescriptionBonus)

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

local function InitStatusEffectBonuses()
	local SEBonus = {}
	SEBonus.arcanistBonus = CheckForHeraldAbility()
	SEBonus.charged = GetChargedBonus()
	SEBonus.heartlandBonus = CheckHeartlandSet()
	SEBonus.wealdBonus = CheckWealdSet()
	SEBonus.destro = CheckDestroPassive()
	SEBonus.CP = CheckCPBonus()
	SEBonus.focusedEfforts = GetFocusedEffortsBonus()
	data.statusEffectBonus = SEBonus
end


function FightHandler:PrepareFight()
	local timems = GetGameTimeMilliseconds()

	if self.prepared ~= true then

		self.combatstart = timems
		self.group = data.inGroup

		PurgeEffectBuffer(timems)

		self.date = GetTimeStamp()
		self.time = GetTimeString()
		self.zone = GetPlayerActiveZoneName()
		self.subzone = GetPlayerActiveSubzoneName()
		self.zoneId = GetUnitWorldPosition("player")
		self.ESOversion = GetESOVersionString()
		self.APIversion = GetAPIVersion()
		self.account = data.accountname

		self.charData = {}

		local charData = self.charData

		charData.name = data.playername
		charData.raceId = GetUnitRaceId("player")
		charData.gender = GetUnitGender("player")
		charData.classId = GetUnitClassId("player")
		charData.level = GetUnitLevel("player")
		charData.CPtotal = GetUnitChampionPoints("player")

		self.CP = GetCurrentCP()

		GetPlayerBuffs(timems)
		GetOtherBuffs(timems)

		data.resources[COMBAT_MECHANIC_FLAGS_HEALTH] = GetUnitPower("player", COMBAT_MECHANIC_FLAGS_HEALTH)
		data.resources[COMBAT_MECHANIC_FLAGS_MAGICKA] = GetUnitPower("player", COMBAT_MECHANIC_FLAGS_MAGICKA)
		data.resources[COMBAT_MECHANIC_FLAGS_STAMINA] = GetUnitPower("player", COMBAT_MECHANIC_FLAGS_STAMINA)
		data.resources[COMBAT_MECHANIC_FLAGS_ULTIMATE] = GetUnitPower("player", COMBAT_MECHANIC_FLAGS_ULTIMATE)

		data.backstabber = GetCritBonusFromCP(self.CP)

		self.prepared = true

		self.startBar = data.bar

		data.stats = {}
		data.advancedStats = {}
		InitStatusEffectBonuses()

		self:GetNewStats(timems)

		data.scribedSkills = {}
		GetCurrentSkillBars()

		lastBossHealthValue = 2

		self.isWipe = false
		lastQueuedAbilities = {}
		usedCastTimeAbility = {}

		DamageShieldBuffer = {}

		onBossesChanged()

	end

	em:RegisterForUpdate("LibCombat_update", 500, function() self:onUpdate() end)
end

local function GetEquip()
	local equip = {}
	for i = EQUIP_SLOT_ITERATION_BEGIN, EQUIP_SLOT_ITERATION_END do
		equip[i] = GetItemLink(BAG_WORN, i, LINK_STYLE_DEFAULT)
	end

	return equip
end

function FightHandler:FinishFight()

	local charData = self.charData

	if charData == nil then return end

	charData.skillBars = ZO_DeepTableCopy(data.skillBars)
	charData.scribedSkills = ZO_DeepTableCopy(data.scribedSkills)
	charData.equip = GetEquip()

	local timems = GetGameTimeMilliseconds()
	self.combatend = timems
	self.combattime = zo_round((timems - self.combatstart)/10)/100

	self.starttime = zo_min(self.dpsstart or self.hpsstart or 0, self.hpsstart or self.dpsstart or 0)
	self.endtime = zo_max(self.dpsend or 0, self.hpsend or 0)
	self.activetime = zo_max((self.endtime - self.starttime) / 1000, 1)

	EffectBuffer = {}

	lastAbilityActivations = {}
	isProjectile = {}

	Log("other", LOG_LEVEL_DEBUG, "Number of Projectile data entries: %d", NonContiguousCount(isProjectile))

	data.lastabilities = {}
end

local function GetStat(stat) -- helper function to make code shorter
	return GetPlayerStat(stat, STAT_BONUS_OPTION_APPLY_BONUS)
end

local TFSBonus = 0

local function GetPenetrationStat(stat) -- helper function to make code shorter
	return GetStat(stat) + TFSBonus
end

local function GetCritStat(stat) -- helper function to make code shorter
	local maxcrit = zo_floor(100/GetCriticalStrikeChance(1))
	return zo_min(GetStat(stat), maxcrit)
end


local function GetCritbonus()
	local _, _, valueFromZos = GetAdvancedStatValue(ADVANCED_STAT_DISPLAY_TYPE_CRITICAL_DAMAGE)
	local total = 50 + valueFromZos + data.backstabber + data.critBonusMundus

	return total
end

local function GetStatusEffectChance()
	local SEBonus = data.statusEffectBonus
	local hotBar = GetActiveHotbarCategory()
	local arcanistBonus = SEBonus.arcanistBonus[hotBar]
	local chargedBonus = SEBonus.charged[hotBar]
	local destroBonus = SEBonus.destro[hotBar]
	local CPBonus = SEBonus.CP
	local FEBonus = SEBonus.focusedEfforts

	-- local heartlandBonus = 0 -- only for debugging. Its not needed actually, since charged tooltip updates.
	-- if SEBonus.heartlandBonus > 0 and select(4, GetItemSetInfo(583)) >= 5 then
	-- 	heartlandBonus = chargedBonus * SEBonus.heartlandBonus / (1 + SEBonus.heartlandBonus)
	-- end

	local wealdBonus = 0
	if SEBonus.wealdBonus > 0 and select(4, GetItemSetInfo(757)) >= 5 then
		local current, maxHealth = GetUnitPower("player", COMBAT_MECHANIC_FLAGS_HEALTH)
		if current/maxHealth > 0.5 then wealdBonus = SEBonus.wealdBonus end
	end

	local totalBonus = arcanistBonus + chargedBonus + destroBonus + wealdBonus + FEBonus + CPBonus

	return totalBonus
end

local statData = {
	[LIBCOMBAT_STAT_MAXMAGICKA]				= 0,
	[LIBCOMBAT_STAT_SPELLPOWER]				= 0,
	[LIBCOMBAT_STAT_SPELLCRIT]				= 0,
	[LIBCOMBAT_STAT_SPELLCRITBONUS]			= 0,
	[LIBCOMBAT_STAT_SPELLPENETRATION]		= 0,

	[LIBCOMBAT_STAT_MAXSTAMINA]				= 0,
	[LIBCOMBAT_STAT_WEAPONPOWER]			= 0,
	[LIBCOMBAT_STAT_WEAPONCRIT]				= 0,
	[LIBCOMBAT_STAT_WEAPONCRITBONUS]		= 0,
	[LIBCOMBAT_STAT_WEAPONPENETRATION]		= 0,

	[LIBCOMBAT_STAT_MAXHEALTH]				= 0,
	[LIBCOMBAT_STAT_PHYSICALRESISTANCE]		= 0,
	[LIBCOMBAT_STAT_SPELLRESISTANCE]		= 0,
	[LIBCOMBAT_STAT_CRITICALRESISTANCE]		= 0,
	[LIBCOMBAT_STAT_STATUS_EFFECT_CHANCE]	= 0,
}

local statSourceFunctions = {
	[LIBCOMBAT_STAT_MAXMAGICKA]				= GetStat,
	[LIBCOMBAT_STAT_SPELLPOWER]				= GetStat,
	[LIBCOMBAT_STAT_SPELLCRIT]				= GetCritStat,
	[LIBCOMBAT_STAT_SPELLCRITBONUS]			= GetCritbonus,
	[LIBCOMBAT_STAT_SPELLPENETRATION]		= GetPenetrationStat,

	[LIBCOMBAT_STAT_MAXSTAMINA]				= GetStat,
	[LIBCOMBAT_STAT_WEAPONPOWER]			= GetStat,
	[LIBCOMBAT_STAT_WEAPONCRIT]				= GetCritStat,
	[LIBCOMBAT_STAT_WEAPONCRITBONUS]		= GetCritbonus,
	[LIBCOMBAT_STAT_WEAPONPENETRATION]		= GetPenetrationStat,

	[LIBCOMBAT_STAT_MAXHEALTH]				= GetStat,
	[LIBCOMBAT_STAT_PHYSICALRESISTANCE]		= GetStat,
	[LIBCOMBAT_STAT_SPELLRESISTANCE]		= GetStat,
	[LIBCOMBAT_STAT_CRITICALRESISTANCE]		= GetStat,
	[LIBCOMBAT_STAT_STATUS_EFFECT_CHANCE]	= GetStatusEffectChance,
}

local zoDerivedStatIds = {
	[LIBCOMBAT_STAT_MAXMAGICKA]				= STAT_MAGICKA_MAX,
	[LIBCOMBAT_STAT_SPELLPOWER]				= STAT_SPELL_POWER,
	[LIBCOMBAT_STAT_SPELLCRIT]				= STAT_SPELL_CRITICAL,
	[LIBCOMBAT_STAT_SPELLPENETRATION]		= STAT_SPELL_PENETRATION,

	[LIBCOMBAT_STAT_MAXSTAMINA]				= STAT_STAMINA_MAX,
	[LIBCOMBAT_STAT_WEAPONPOWER]			= STAT_POWER,
	[LIBCOMBAT_STAT_WEAPONCRIT]				= STAT_CRITICAL_STRIKE,
	[LIBCOMBAT_STAT_WEAPONPENETRATION]		= STAT_PHYSICAL_PENETRATION,

	[LIBCOMBAT_STAT_MAXHEALTH]				= STAT_HEALTH_MAX,
	[LIBCOMBAT_STAT_PHYSICALRESISTANCE]		= STAT_PHYSICAL_RESIST,
	[LIBCOMBAT_STAT_SPELLRESISTANCE]		= STAT_SPELL_RESIST,
	[LIBCOMBAT_STAT_CRITICALRESISTANCE]		= STAT_CRITICAL_RESISTANCE,
}

local function GetSingleStat(statId)
	if not currentfight.prepared then currentfight:PrepareFight() end
	return statSourceFunctions[statId](zoDerivedStatIds[statId])
end

local function GetStats()
	for statId, _ in pairs(statData) do
		statData[statId] = GetSingleStat(statId)
	end
	return statData
end

function onTFSChanged(_, changeType, _, _, _, _, _, stackCount, _, _, _, _, _, _, _, _, _)
	if (changeType == EFFECT_RESULT_GAINED or changeType == EFFECT_RESULT_UPDATED) and stackCount > 1 then
		TFSBonus = (stackCount - 1) * 544
	else
		TFSBonus = 0
	end
	FightHandler:GetNewStats()
end

local advancedStatData = {}

local function InitAdvancedStats()
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

-- TODO: Activate or remove this dead code ?
local function GetAdvancedStats()
	if true then return {} end

	for statType, _ in pairs(advancedStatData) do
		local _, flatValue, percentValue = GetAdvancedStatValue(statType)

		if flatValue then advancedStatData[statType][1] = flatValue end
		if percentValue then advancedStatData[statType][2] = percentValue end

	end
	return advancedStatData
end

local lastUpdateSingleStatsCall = 0

function FightHandler:UpdateSingleStat(statId, timems)
	if Events.Stats.active ~= true then return end
	em:UnregisterForUpdate("LibCombat_Stats_Single")

	timems = timems or GetGameTimeMilliseconds()
	local lastcalldelta = timems - lastUpdateSingleStatsCall

	if lastcalldelta < 100 then
		em:RegisterForUpdate("LibCombat_Stats_Single", (100 - lastcalldelta), function() self:UpdateSingleStat(statId, nil) end)
		return
	end

	lastUpdateSingleStatsCall = timems
	local stats = data.stats
	local oldValue = stats[statId]
	local newValue = GetSingleStat(statId)
	local delta = oldValue and (newValue - oldValue) or 0
	if oldValue == nil or delta ~= 0 then
		assert(delta ~= nil)
		assert(newValue ~= nil)
		assert(statId ~= nil)
		lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_PLAYERSTATS]), LIBCOMBAT_EVENT_PLAYERSTATS, timems, delta, newValue, statId)
		stats[statId] = newValue
	end

end

local lastGetNewStatsCall = 0

function FightHandler:GetNewStats(timems)
	if Events.Stats.active ~= true then return end
	em:UnregisterForUpdate("LibCombat_Stats")

	timems = timems or GetGameTimeMilliseconds()
	local lastcalldelta = timems - lastGetNewStatsCall

	if lastcalldelta < 100 then
		em:RegisterForUpdate("LibCombat_Stats", (100 - lastcalldelta), function() self:GetNewStats() end)
		return
	end

	lastGetNewStatsCall = timems
	local stats = data.stats

	for statId, newValue in pairs(GetStats()) do
		local oldValue = stats[statId]
		local delta = oldValue and (newValue - oldValue) or 0
		if oldValue == nil or delta ~= 0 then
			assert(newValue ~= nil)
			assert(delta ~= nil)
			assert(statId ~= nil)
			lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_PLAYERSTATS]), LIBCOMBAT_EVENT_PLAYERSTATS, timems, delta, newValue, statId)
			stats[statId] = newValue
		end
	end

	if Events.AdvancedStats.active ~= true then return end
	local advancedStats = data.advancedStats

	for statId, values in pairs(GetAdvancedStats()) do
		if advancedStats[statId] == nil then advancedStats[statId] = {} end
		local oldValues = advancedStats[statId]
		local newValue1 = values[1]
		local newValue2 = values[2]

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

function FightHandler:AddCombatEvent(timems, result, targetUnitId, value, eventid, overflow)
	if eventid == LIBCOMBAT_EVENT_DAMAGE_OUT then 		--outgoing dmg
		self.damageOutTotal = self.damageOutTotal + value + overflow
		self.units[targetUnitId]["damageOutTotal"] = self.units[targetUnitId]["damageOutTotal"] + value + overflow
		self.dpsstart = self.dpsstart or timems
		self.dpsend = timems

	elseif eventid == LIBCOMBAT_EVENT_DAMAGE_IN then 	--incoming dmg
		self.damageInShielded = self.damageInShielded + (overflow or 0)
		self.damageInTotal = self.damageInTotal + value

	elseif eventid == LIBCOMBAT_EVENT_HEAL_OUT then --outgoing heal
		self.healingOutTotal = self.healingOutTotal + value
		self.healingOutAbsolute = self.healingOutAbsolute + value + (overflow or 0)

		if activetimeonheals then
			self.hpsstart = self.hpsstart or timems
			self.hpsend = timems
		end

	elseif eventid == LIBCOMBAT_EVENT_HEAL_IN then --incoming heals
		self.healingInTotal = self.healingInTotal + value

	elseif eventid == LIBCOMBAT_EVENT_HEAL_SELF then --outgoing heal
		self.healingInTotal = self.healingInTotal + value
		self.healingOutTotal = self.healingOutTotal + value
		self.healingOutAbsolute = self.healingOutAbsolute + value + (overflow or 0)

		if activetimeonheals then
			self.hpsstart = self.hpsstart or timems
			self.hpsend = timems
		end
	end
end

local function ProcessDeathRecaps()
	local timems = GetGameTimeMilliseconds()
	for unitId, UnitCache in pairs(UnitDeathsToProcess) do
		if timems - UnitCache.timems > 200 then
			Log("debug", LOG_LEVEL_DEBUG, "ProcessDeath: %s (%d)", currentfight.units[unitId].name, unitId)
			UnitCache:ProcessDeath()
		end
	end
end

local function ClearUnitCaches()
	Log("debug", LOG_LEVEL_DEBUG, "ClearUnitCaches (%d)", NonContiguousCount(CombatEventCache))

	for unitId, UnitCache in pairs(CombatEventCache) do
		CombatEventCache[unitId] = nil
	end

	UnitDeathsToProcess = {}
end

function FightHandler:GetBossTargetDamage() -- Gets Damage done to bosses and counts enemy boss units.
	if not self.bossfight then return end

	local totalBossDamage = 0
	local totalBossGroupDamage = 0
	local starttime
	local endtime = 0

	for _, unit in pairs(self.units) do
		local totalUnitDamage = unit.damageOutTotal
		if (unit.bossId ~= nil and totalUnitDamage>0) then
			totalBossDamage = totalBossDamage + totalUnitDamage
			totalBossGroupDamage = totalBossGroupDamage + unit.groupDamageOut

			if starttime == nil then
				starttime = unit.dpsstart
			elseif unit.dpsstart ~= nil then
				starttime = math.min(starttime, unit.dpsstart)
			end

			endtime = math.max(endtime or unit.dpsend or 0, unit.dpsend or 0)
		end
	end

	local bossTime
	if starttime and starttime ~= endtime then
		bossTime = (endtime - starttime)/1000
	else
		bossTime = self.dpstime
	end

	return bossTime, totalBossDamage, totalBossGroupDamage
end

function FightHandler:GetSingleTargetDamage()	-- Gets highest Single Target Damage and counts enemy units.
	if self.bossfight then return self:GetBossTargetDamage() end

	local damage, groupDamage, unittime = 0, 0, 0
	for _, unit in pairs(self.units) do
		local totalUnitDamage = unit.damageOutTotal
		if totalUnitDamage > 0 and unit.isFriendly == false then
			if totalUnitDamage > damage then
				damage = totalUnitDamage
				groupDamage = unit.groupDamageOut
				unittime = unit.dpsend and unit.dpsstart and unit.dpsend - unit.dpsstart or 0
			end
		end
	end

	unittime = unittime > 0 and unittime/1000 or self.dpstime
	return unittime, damage, groupDamage
end

function FightHandler:UpdateStats()
	ProcessDeathRecaps()

	if (self.dpsend == nil and self.hpsend == nil) or (self.dpsstart == nil and self.hpsstart == nil) then return end

	local dpstime = zo_max(((self.dpsend or 1) - (self.dpsstart or 0)) / 1000, 1)
	local hpstime = zo_max(((self.hpsend or 1) - (self.hpsstart or 0)) / 1000, 1)

	self.dpstime = dpstime
	self.hpstime = hpstime

	self:UpdateGrpStats()
	local bossTime, totalBossDamage, totalBossGroupDamage = self:GetSingleTargetDamage()

	self.DPSOut = zo_floor(self.damageOutTotal / dpstime + 0.5)
	self.HPSOut = zo_floor(self.healingOutTotal / hpstime + 0.5)
	self.HPSAOut = zo_floor(self.healingOutAbsolute / hpstime + 0.5)
	self.DPSIn = zo_floor(self.damageInTotal / dpstime + 0.5)
	self.HPSIn = zo_floor(self.healingInTotal / hpstime + 0.5)
	self.HPSIn = zo_floor(self.healingInTotal / hpstime + 0.5)
	local bossDPSOut = zo_floor(totalBossDamage / bossTime + 0.5)

	local data = {
		["DPSOut"] = self.DPSOut,
		["DPSIn"] = self.DPSIn,
		["HPSOut"] = self.HPSOut,
		["OHPSOut"] = self.HPSAOut,
		["HPSIn"] = self.HPSIn,
		["overHealingOutTotal"] = self.healingOutAbsolute,
		["healingOutTotal"] = self.healingOutTotal,
		["damageOutTotal"] = self.damageOutTotal,
		["dpstime"] = dpstime,
		["hpstime"] = hpstime,
		["bossfight"] = self.bossfight,
		["group"] = self.group,
		["groupDPSOut"] = self.DPSOut,
		["groupDPSIn"] = self.DPSIn,
		["groupHPSOut"] = self.HPSOut,
		["damageOutTotalGroup"] = self.damageOutTotal,
		["bossDPSOut"] = bossDPSOut,
		["bossDamageTotal"] = totalBossDamage,
		["bossDPSOutGroup"] = bossDPSOut,
		["bossDamageTotalGroup"] = totalBossDamage,
		["bossTime"] = bossTime,
	}

	if self.group and Events.CombatGrp.active then
		data["groupDPSOut"] = self.groupDPSOut
		data["groupDPSIn"] = self.groupDPSIn
		data["groupHPSOut"] = self.groupHPSOut
		data["damageOutTotalGroup"] = self.groupDamageOut
		data["bossDamageTotalGroup"] = totalBossGroupDamage
		data["bossDPSOutGroup"] = zo_floor(totalBossGroupDamage / bossTime + 0.5)
	end

	lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_UNITS]), LIBCOMBAT_EVENT_UNITS, self.units)
	lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_FIGHTRECAP]), LIBCOMBAT_EVENT_FIGHTRECAP, data)

end

function FightHandler:UpdateGrpStats() -- called by onUpdate
	if not (self.group and Events.CombatGrp.active) then return end

	local iend = (self.grplog and #self.grplog) or 0
	if iend > 1 then
		for i = iend, 1, -1 do 			-- go backwards for easier deletions

			local line = self.grplog[i]
			local unitId, value, action = unpack(line)

			local unit = self.units[unitId]

			if unit and unit.isFriendly == false and action=="heal" then
				table.remove(self.grplog,i)

			elseif unit and unit.isFriendly == true and action=="heal" then --only events of identified units are removed. The others might be identified later.
				self.groupHealingOut = self.groupHealingOut + value
				table.remove(self.grplog,i)

			elseif unit and unit.isFriendly == false and action=="dmg" then
				unit.groupDamageOut = unit.groupDamageOut + value
				self.groupDamageOut = self.groupDamageOut + value
				table.remove(self.grplog,i)

			elseif unit and unit.isFriendly == true and action=="dmg" then
				self.groupDamageIn = self.groupDamageIn + value
				table.remove(self.grplog,i)

			end
		end
	end

	local dpstime = self.dpstime
	local hpstime = self.hpstime

	self.groupHealingIn = self.groupHealingOut

	self.groupDPSOut = zo_floor(self.groupDamageOut / dpstime + 0.5)
	self.groupDPSIn = zo_floor(self.groupDamageIn / dpstime + 0.5)
	self.groupHPSOut = zo_floor(self.groupHealingOut / hpstime + 0.5)

	self.groupHPSIn = self.groupHPSOut

	local data = {
		["groupDPSOut"] = self.groupDPSOut,
		["groupDPSIn"] = self.groupDPSIn,
		["groupHPSOut"] = self.groupHPSOut,
		["dpstime"] = dpstime,
		["hpstime"] = hpstime
	}

	lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_GROUPRECAP]), LIBCOMBAT_EVENT_GROUPRECAP, data)
end


local function getCurrentBossHP()

	if BOSS_BAR.control:IsHidden() then return 0 end

	local totalHealth = 0
    local totalMaxHealth = 0

    for unitTag, bossEntry in pairs(BOSS_BAR.bossHealthValues) do
        totalHealth = totalHealth + bossEntry.health
        totalMaxHealth = totalMaxHealth + bossEntry.maxHealth
	end

	return totalHealth/totalMaxHealth

end

local function IsOngoingBossfight()

	if isInPortalWorld then -- prevent fight reset in Cloudrest when using a portal.

		Log("other", LOG_LEVEL_DEBUG, "Prevented combat reset because player is in Portal!")
		return true

	elseif getCurrentBossHP() > 0 and getCurrentBossHP() < 1 then

		Log("other", LOG_LEVEL_INFO, "Prevented combat reset because boss is still in fight!")
		return true

	else

		return false

	end
end

function FightHandler:onUpdate()

	onCombatState(EVENT_PLAYER_COMBAT_STATE, IsUnitInCombat("player"))

	--reset data
	if reset == true or (data.inCombat == false and self.combatend > 0 and (GetGameTimeMilliseconds() > (self.combatend + timeout)) ) then

		reset = false

		self:UpdateStats()

		if self.damageOutTotal>0 or self.healingOutTotal>0 or self.damageInTotal>0 then

			Log("fight", LOG_LEVEL_DEBUG, "Time: %.2fs (DPS) | %.2fs (HPS) ", self.dpstime, self.hpstime)
			Log("fight", LOG_LEVEL_DEBUG, "Dmg: %d (DPS: %d)", self.damageOutTotal, self.DPSOut)
			Log("fight", LOG_LEVEL_DEBUG, "Heal: %d (HPS: %d)", self.healingOutTotal, self.HPSOut)
			Log("fight", LOG_LEVEL_DEBUG, "IncDmg: %d (Shield: %d, IncDPS: %d)", self.damageInTotal, self.damageInShielded, self.DPSIn)
			Log("fight", LOG_LEVEL_DEBUG, "IncHeal: %d (IncHPS: %d)", self.healingInTotal, self.HPSIn)

			if data.inGroup and Events.CombatGrp.active then

				Log("fight", LOG_LEVEL_DEBUG, "GrpDmg: %d (DPS: %d)", self.groupDamageOut, self.groupDPSOut)
				Log("fight", LOG_LEVEL_DEBUG, "GrpHeal: %d (HPS: %d)", self.groupHealingOut, self.groupHPSOut)
				Log("fight", LOG_LEVEL_DEBUG, "GrpIncDmg: %d (IncDPS: %d)", self.groupDamageIn, self.groupDPSIn)

			end
		end

		Log("fight", LOG_LEVEL_DEBUG, "resetting...")

		self.grplog = {}

		lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_FIGHTSUMMARY]), LIBCOMBAT_EVENT_FIGHTSUMMARY, self)

		currentfight = FightHandler:New()
		ClearUnitCaches()

		em:UnregisterForUpdate("LibCombat_update")

	elseif data.inCombat == true then

		self:UpdateStats()

	end

end

local UnitCacheHandler = ZO_Object:Subclass()	-- holds all recent events + info to send on death

function UnitCacheHandler:New(...)
    local object = ZO_Object.New(self)
    object:Initialize(...)
    return object
end

function UnitCacheHandler:Initialize(unitId)

	self.nextKey = 1
	self.maxlength = maxUnitCacheEvents
	self.cache = {}
	self.unitId = unitId

	CombatEventCache[unitId] = self

	if not lib.debug then return end

	local unitname = currentfight.units[unitId] and currentfight.units[unitId].name or "Unknown"

	Log("debug", LOG_LEVEL_DEBUG, "Init UnitCache: %s (%d)", unitname, unitId)

end

function UnitCacheHandler:OnDeath(timems)

	self.timems = timems

	UnitDeathsToProcess[self.unitId] = self

	if not lib.debug then return end

	local unitname = currentfight.units[self.unitId] and currentfight.units[self.unitId].name or "Unknown"

	Log("debug", LOG_LEVEL_DEBUG, "UnitCacheHandler:OnDeath: %s (%d)", unitname, self.unitId)

end

function UnitCacheHandler:ProcessDeath()

	local unit = currentfight.units[self.unitId]

	if unit then ZO_ShallowTableCopy(unit:GetUnitInfo(), self) end

	self.bossname = currentfight.bossname
	self.zoneId = currentfight.zoneId
	self.fighttime = currentfight.date
	self.combatstart = currentfight.combatstart

	self.log = {}
	local cache = self.cache

	if #cache > 0 then

		local log = self.log
		local offset = self.nextKey - 1
		local length = #self.cache
		local timems = self.timems

		local deleted = 0

		Log("debug", LOG_LEVEL_DEBUG, "Processing death event cache. Offset: %d, length:%d", offset, length)

		for i = 0, length - 1 do

			local cachekey = (i + offset)%length + 1
			local data = cache[cachekey]

			if timems - data[1] < deathRecapTimePeriod then

				log[#log + 1] = data
				local sourceUnitId = data[3]
				local sourceUnit = sourceUnitId and sourceUnitId>0 and currentfight and currentfight.units and currentfight.units[sourceUnitId] or "nil"

				data[3] = (sourceUnit and sourceUnit.name) or "Unknown"

				if data[10] and data[10] > self.magickaMax then self.magickaMax = data[10] end
				if data[11] and data[11] > self.staminaMax then self.staminaMax = data[11] end

			else

				deleted = deleted + 1

			end
		end

		Log("debug", LOG_LEVEL_DEBUG , "%s: cache: %d, log: %d, deleted: %d", unit and unit.name or "Unknown", #cache, #log, deleted)
	end

	self.cache = nil
	self.health = nil
	self.stamina = nil
	self.magicka = nil
	self.nextKey = nil
	self.maxlength = nil

	lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_DEATHRECAP]), LIBCOMBAT_EVENT_DEATHRECAP, self.timems, self)

	UnitCacheHandler:New(self.unitId)
	UnitDeathsToProcess[self.unitId] = nil
end

function UnitCacheHandler:AddEvent(timems, result, sourceUnitId, abilityId, hitValue, damageType, overflow)

	if self.health == nil then self:InitResources() end

	local nextKey = self.nextKey

	self.cache[nextKey] = {timems, result, sourceUnitId, abilityId, damageType, hitValue, overflow, self.health, self.healthMax, self.magicka, self.stamina}

	self.nextKey = (nextKey % self.maxlength) + 1

	self.timems = timems

end

function UnitCacheHandler:InitResources()
	local unit = currentfight.units[self.unitId]

	if unit then
		local unitTag = unit.unitTag
		self.health, self.healthMax = GetUnitPower(unitTag, COMBAT_MECHANIC_FLAGS_HEALTH)

		if unitTag == "player" then
			self.magicka = GetUnitPower(unitTag, COMBAT_MECHANIC_FLAGS_MAGICKA)
			self.stamina = GetUnitPower(unitTag, COMBAT_MECHANIC_FLAGS_STAMINA)
		end
	end
end

function UnitCacheHandler:UpdateResource(powerType, value, powerMax)
	if powerType == COMBAT_MECHANIC_FLAGS_HEALTH then

		self.health = value
		self.healthMax = powerMax > 0 and powerMax or self.healthMax or 0

	elseif powerType == COMBAT_MECHANIC_FLAGS_STAMINA then

		self.stamina = value
		self.staminaMax = powerMax > 0 and powerMax or self.staminaMax or 0

	elseif powerType == COMBAT_MECHANIC_FLAGS_MAGICKA then

		self.magicka = value
		self.magickaMax = powerMax > 0 and powerMax or self.magickaMax or 0

	end
end

local function GetUnitCache(unitId)
	if unitId == nil or unitId < 1 then return end
	local unitCache = CombatEventCache[unitId]
	if unitCache == nil then unitCache = UnitCacheHandler:New(unitId) end

	return unitCache
end

-- Event Functions

function onCombatState(event, inCombat)  -- Detect Combat Stage, local is defined above - Don't Change !!!
	if inCombat ~= data.inCombat then     -- Check if player state changed
		local timems = GetGameTimeMilliseconds()

		if inCombat then
			data.inCombat = inCombat
			Log("fight", LOG_LEVEL_DEBUG, "Entering combat.")
			lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_MESSAGES]), LIBCOMBAT_EVENT_MESSAGES, timems, LIBCOMBAT_MESSAGE_COMBATSTART, 0)
			currentfight:PrepareFight()
		else
			if IsOngoingBossfight() then
				Log("fight", LOG_LEVEL_DEBUG, "Failed: Leaving combat.")
				return
			end

			data.inCombat = false
			Log("fight", LOG_LEVEL_DEBUG, "Leaving combat.")
			currentfight:FinishFight()

			if currentfight.charData == nil then return end
			lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_MESSAGES]), LIBCOMBAT_EVENT_MESSAGES, timems, LIBCOMBAT_MESSAGE_COMBATEND, 0)
		end
	end
end

-- Buffs/Debuffs

local GROUP_EFFECT_NONE = 0
local GROUP_EFFECT_IN = 1
local GROUP_EFFECT_OUT = 2

--(eventCode, changeType, effectSlot, effectName, unitTag, beginTime, endTime, stackCount, iconName, buffType, effectType, abilityType, statusEffectType, unitName, unitId, abilityId, sourceType)

local lastPurge = 0

local function AddtoEffectBuffer(endTime, abilityType, eventid, timems, unitId, abilityId, ...)

	local data = {endTime, {eventid, timems, unitId, abilityId, ...}, abilityType}

	local unit = EffectBuffer[unitId]

	if unit == nil then

		EffectBuffer[unitId] = {[abilityId] = data}

	else

		unit[abilityId] = data

	end

	if timems - lastPurge > 1000 then

		PurgeEffectBuffer(timems)
		lastPurge = timems

	end
end

local function onPortalWorld( _, changeType)

	isInPortalWorld = changeType == EFFECT_RESULT_GAINED
	onBossesChanged()

end

local function onMageExplode( _, changeType, effectSlot, _, unitTag, _, endTime, stackCount, _, _, effectType, abilityType, _, unitName, unitId, abilityId, sourceType)

	currentfight:ResetFight()	-- special tracking for The Mage in Aetherian Archives. It will reset the fight when the mage encounter starts.

end

local function onTrialDummy(_, _, _, _, _, _, _, _, _, _, _, _, _, _, sourceUnitId, _, _, _)
	if not currentfight.prepared then return end

	local unit = currentfight.units[sourceUnitId]
	if unit then unit.isTrialDummy = true end
end

local function BuffEventHandler(isspecial, groupeffect, _, changeType, effectSlot, _, unitTag, _, endTime, stackCount, _, _, effectType, abilityType, _, unitName, unitId, abilityId, sourceType)

	if (changeType ~= EFFECT_RESULT_GAINED and changeType ~= EFFECT_RESULT_FADED and not (changeType == EFFECT_RESULT_UPDATED and stackCount > 1)) or unitName == "Offline" or unitId == nil then return end

	Log("events", LOG_LEVEL_VERBOSE, "%s %s the %s %dx %s (%d, ET: %d, %s, %d)", unitName, changeType, effectType == BUFF_EFFECT_TYPE_BUFF and "buff" or "debuff", stackCount, GetFormattedAbilityName(abilityId), abilityId, abilityType, unitTag, sourceType)

	if BadAbility[abilityId] == true then return end

	if unitTag and zo_strsub(unitTag, 1, 5) == "group" and AreUnitsEqual(unitTag, "player") then return end
	if unitTag and zo_strsub(unitTag, 1, 11) ~= "reticleover" and (AreUnitsEqual(unitTag, "reticleover") or AreUnitsEqual(unitTag, "reticleoverplayer") or AreUnitsEqual(unitTag, "reticleovertarget")) then return end

	local timems = GetGameTimeMilliseconds()

	local eventid = groupeffect == GROUP_EFFECT_IN and LIBCOMBAT_EVENT_GROUPEFFECTS_IN or groupeffect == GROUP_EFFECT_OUT and LIBCOMBAT_EVENT_GROUPEFFECTS_OUT or unitTag and zo_strsub(unitTag, 1, 6) == "player" and LIBCOMBAT_EVENT_EFFECTS_IN or LIBCOMBAT_EVENT_EFFECTS_OUT
	local stacks = zo_max(1, stackCount)

	local inCombat = currentfight.prepared


	-- local hitValue = (abilityId == 75753 and changeType == EFFECT_RESULT_GAINED and AlkoshData[unitId]) or nil

	if inCombat ~= true and unitTag ~= "player" and (changeType == EFFECT_RESULT_GAINED or changeType == EFFECT_RESULT_UPDATED) then

		AddtoEffectBuffer(endTime, abilityType, eventid, timems, unitId, abilityId, changeType, effectType, stacks, sourceType, effectSlot)
		return

	elseif inCombat == true then

		local unit = currentfight.units[unitId]

		if unitTag == "player" or unitId == data.playerid then currentfight:GetNewStats(timems) end
		if sourceType ~= COMBAT_UNIT_TYPE_PLAYER or abilityId ~= abilityIdZen then lib.cm:FireCallbacks((CallbackKeys[eventid]), eventid, timems, unitId, abilityId, changeType, effectType, stacks, sourceType, effectSlot) end

		if unit then

			unit.starttime = unit.starttime or timems
			unit.endtime = timems

			if sourceType == COMBAT_UNIT_TYPE_PLAYER and (abilityId == abilityIdZen or abilityType == ABILITY_TYPE_DAMAGE) then unit:UpdateZenData((CallbackKeys[eventid]), eventid, timems, unitId, abilityId, changeType, effectType, stacks, sourceType, effectSlot, abilityType) end
			if StatusEffectIds[abilityId] and (sourceType == COMBAT_UNIT_TYPE_PLAYER or (unitName == "" and unit.forceOfNature[abilityId] and SpecialDebuffs[abilityId])) then unit:UpdateForceOfNatureData((CallbackKeys[eventid]), eventid, timems, unitId, abilityId, changeType, effectType, stacks, sourceType, effectSlot) end

		end
	end
end

local function onEffectChanged(...)
	BuffEventHandler(false, GROUP_EFFECT_NONE, ...)		-- (isspecial, groupeffect, ...)
end

local function onGroupEffectOut(...)
	BuffEventHandler(false, GROUP_EFFECT_OUT, ...)		-- (isspecial, groupeffect, ...)
end

local function onGroupEffectIn(...)
	BuffEventHandler(false, GROUP_EFFECT_IN, ...)		-- (isspecial, groupeffect, ...)
end

local function onSourceBuggedEffectChanged(eventCode, changeType, effectSlot, effectName, unitTag, beginTime, endTime, stackCount, iconName, buffType, effectType, abilityType, statusEffectType, unitName, unitId, abilityId, _)
	BuffEventHandler(false, GROUP_EFFECT_OUT, eventCode, changeType, effectSlot, effectName, unitTag, beginTime, endTime, stackCount, iconName, buffType, effectType, abilityType, statusEffectType, unitName, unitId, abilityId, COMBAT_UNIT_TYPE_GROUP)
end

local resultTochangeType = {

	[ACTION_RESULT_EFFECT_GAINED_DURATION] = EFFECT_RESULT_GAINED,
	[ACTION_RESULT_EFFECT_FADED] = EFFECT_RESULT_FADED,
	[ACTION_RESULT_EFFECT_GAINED] = EFFECT_RESULT_UPDATED,
}

local DurationCache = {}

-- [7890.234] R: 2245, Overcharged (178118), Type: 0, Power: 0, DType: 1, V: 4000, OF: 0, Solinur^Mx (31967, 1) -> The Precursor (30413, 4)

local function SpecialBuffEventHandler(isdebuff, _, result, _, _, _, _, sourceName, sourceType, targetName, targetType, hitValue, _, damageType, _, sourceUnitId, targetUnitId, abilityId)
	--(eventCode, result, isError, abilityName, abilityGraphic, abilityActionSlotType, sourceName, sourceType, targetName, targetType, hitValue, powerType, damageType, log, sourceUnitId, targetUnitId, abilityId)

	local now = GetGameTimeSeconds()

	if BadAbility[abilityId] == true or (result == ACTION_RESULT_EFFECT_GAINED and hitValue < 2) then return end

	if result == ACTION_RESULT_EFFECT_GAINED_DURATION then

		DurationCache[abilityId] = hitValue

	elseif DurationCache[abilityId] == nil and result == ACTION_RESULT_EFFECT_FADED then

		DurationCache[abilityId] = hitValue

	end

	local stackCount = 1
	local duration = hitValue

	if result == ACTION_RESULT_EFFECT_GAINED then

		if DurationCache[abilityId] then

			duration = DurationCache[abilityId]
			stackCount = hitValue

		else return end
	end

	-- if unitName ~= data.rawPlayername then return end

	local changeType = resultTochangeType[result] or nil
	-- Print("debug", LOG_LEVEL_INFO, "%s (%d): %d (%d)", GetFormattedAbilityName(abilityId), abilityId, changeType, result)

	local effectType = isdebuff and BUFF_EFFECT_TYPE_DEBUFF or BUFF_EFFECT_TYPE_BUFF

	local endTime = now + duration/1000

	local unitTag = currentfight.units and currentfight.units[targetUnitId] and currentfight.units[targetUnitId].unitTag or nil

	BuffEventHandler(true, GROUP_EFFECT_NONE, _, changeType, 0, _, unitTag, _, endTime, stackCount, _, _, effectType, ABILITY_TYPE_BONUS, _, targetName, targetUnitId, abilityId, sourceType)

end

local function onSpecialBuffEvent(...)
	SpecialBuffEventHandler(false, ...)		-- (isdebuff, ...)
end

local function onSpecialDebuffEvent(...)
	SpecialBuffEventHandler(true, ...)		-- (isdebuff, ...)
end

local function onSpecialBuffEventOnSelf(...)
	local _, _, _, _, _, _, _, sourceType, _, targetType, _, _, _, _, _, _, _ = ...
	if sourceType == COMBAT_UNIT_TYPE_PLAYER and targetType == COMBAT_UNIT_TYPE_PLAYER then return end
	SpecialBuffEventHandler(false, ...)		-- (isdebuff, ...)
end

local function onSpecialDebuffEventOnSelf(...)
	local _, _, _, _, _, _, _, sourceType, _, targetType, _, _, _, _, _, _, _ = ...
	if sourceType == COMBAT_UNIT_TYPE_PLAYER and targetType == COMBAT_UNIT_TYPE_PLAYER then return end
	SpecialBuffEventHandler(true, ...)		-- (isdebuff, ...)
end

local function onShadowMundus( _, changeType, effectSlot)

	if changeType == EFFECT_RESULT_GAINED or changeType == EFFECT_RESULT_UPDATED then GetShadowBonus(effectSlot)
	elseif changeType == EFFECT_RESULT_FADED then data.critBonusMundus = 0 end

	if currentfight.prepared == true then currentfight:GetNewStats() end

end

local IsTypeFriendly={						-- for debug purposes, maybe one can use this to add more custom buffs.
	[COMBAT_UNIT_TYPE_PLAYER]=true,
	[COMBAT_UNIT_TYPE_PLAYER_PET]=true,
	[COMBAT_UNIT_TYPE_GROUP]=true,
	[COMBAT_UNIT_TYPE_TARGET_DUMMY]=false,
	[COMBAT_UNIT_TYPE_OTHER]=false,
}

local function onCustomEvent(_, _, _, _, _, _, _, sourceType, _, targetType, _, _, _, _, _, _, abilityId)
	if sourceType ~= nil and targetType ~= nil and IsTypeFriendly[sourceType]~=IsTypeFriendly[targetType] then
		CustomAbilityTypeList[abilityId] = BUFF_EFFECT_TYPE_DEBUFF
	else
		CustomAbilityTypeList[abilityId] = CustomAbilityTypeList[abilityId] or BUFF_EFFECT_TYPE_BUFF
	end
end

function lib.GetCustomAbilityList()
	return CustomAbilityTypeList
end

local SPRINT_STATE_ACTIVE = 1
local SPRINT_STATE_NONE = 0

local function GetPlayerSprintState()

	for slot = 3,8 do

		local anyAbilityActive = not (
			ActionSlotHasTargetFailure(slot, HOTBAR_CATEGORY_PRIMARY) and
			ActionSlotHasNonCostStateFailure(slot, HOTBAR_CATEGORY_PRIMARY) and
			ActionSlotHasTargetFailure(slot, HOTBAR_CATEGORY_BACKUP) and
			ActionSlotHasNonCostStateFailure(slot, HOTBAR_CATEGORY_PRIMARY)
		)

		if anyAbilityActive then return SPRINT_STATE_NONE end

	end

	return SPRINT_STATE_ACTIVE

end

local function checkLastAbilities(timems, powerType, powerValueChange, powerValue)

	local lastabilities = data.lastabilities

	local abilityId = -1
	local adjustedPowerValueChange

	-- Print("events", LOG_LEVEL_DEBUG, "Check %d Abilities: %d, %d, %d", #lastabilities, powerType, powerValueChange, powerValue)

	for i = #lastabilities, 1, -1 do

		local values = lastabilities[i]

		-- Print("events", LOG_LEVEL_DEBUG, "Check: %s (%d), %d, %d", GetFormattedAbilityName(values[2]), values[2], powerValueChange / values[3], values[4])

		if powerType == values[4] then

			local ratio = powerValueChange / values[3]

			local goodratio = ratio >= 0.98 and ratio <= 1.06

			if goodratio then

				-- Print("events", LOG_LEVEL_DEBUG, "Ratio: %.3f (**%s: %d vs. %d) %d", ratio, GetFormattedAbilityName(values[2]), values[3], powerValueChange, #lastabilities-i)

				abilityId = values[2]
				table.remove(lastabilities, i)

				break

			elseif values[2] == 58431 and GetAllyUnitBlockState("player") == BLOCK_STATE_ACTIVE then	-- check if Constitution coincides with Block

				local blockCost = select(2, GetAdvancedStatValue(ADVANCED_STAT_DISPLAY_TYPE_BLOCK_COST))

				local combinedPowerValueChange = values[3] - blockCost

				local ratio = powerValueChange / combinedPowerValueChange

				local goodratio = ratio >= 0.98 and ratio <= 1.06

				if goodratio then

					-- Print("events", LOG_LEVEL_DEBUG, "Ratio: %.3f (**%s: %d vs. %d) %d", ratio, GetFormattedAbilityName(values[2]), combinedPowerValueChange, powerValueChange, #lastabilities-i)

					abilityId = 23542
					adjustedPowerValueChange = - blockCost
					table.remove(lastabilities, i)

					-- Print("events", LOG_LEVEL_DEBUG, "Resource: %s (%d): %d (%d) --> %d", GetFormattedAbilityName(values[2]), values[2], values[3], powerType, powerValue - adjustedPowerValueChange)

					lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_RESOURCES]), LIBCOMBAT_EVENT_RESOURCES, timems, values[2], values[3], powerType, powerValue - adjustedPowerValueChange)

					break
				end
			end
		end

		if (values[1] - timems) > 1000 then break end
	end

	-- Print("events", LOG_LEVEL_DEBUG, "Ability Result: %s (%d), %d", GetFormattedAbilityName(abilityId), abilityId, tostring(adjustedPowerValueChange))

	return abilityId, adjustedPowerValueChange

end

local function checkForCombatActions(powerValueChange)
	if powerValueChange > 0 then return -1 end

	if GetAllyUnitBlockState("player") == BLOCK_STATE_ACTIVE then
		local blockRatio = select(2, GetAdvancedStatValue(ADVANCED_STAT_DISPLAY_TYPE_BLOCK_COST)) / -powerValueChange
		if blockRatio >= 0.98 and blockRatio <= 1.02 then
			Log("events", LOG_LEVEL_DEBUG, "Skill cost: %d Stamina (Block)", powerValueChange)
			return 23542

		end
	end

	local bashRatio = select(2, GetAdvancedStatValue(ADVANCED_STAT_DISPLAY_TYPE_BASH_COST))     / -powerValueChange
	if bashRatio >= 0.98 and bashRatio <= 1.02 then
		Log("events", LOG_LEVEL_DEBUG, "Skill cost: %d Stamina (Bash)", powerValueChange)
		return 21970

	end

	local dodgeRatio = select(2, GetAdvancedStatValue(ADVANCED_STAT_DISPLAY_TYPE_DODGE_COST))    / -powerValueChange
	if dodgeRatio >= 0.98 and dodgeRatio <= 1.02 then
		Log("events", LOG_LEVEL_DEBUG, "Skill cost: %d Stamina (Dodge)", powerValueChange)
		return 28549

	end

	local breakFreeRatio = select(2, GetAdvancedStatValue(ADVANCED_STAT_DISPLAY_TYPE_CC_BREAK_COST)) / -powerValueChange
	if breakFreeRatio >= 0.98 and breakFreeRatio <= 1.02 then
		Log("events", LOG_LEVEL_DEBUG, "Skill cost: %d Stamina (Break Free)", powerValueChange)
		return 16565

	end

	if GetUnitStealthState("player") == STEALTH_STATE_HIDING or GetUnitStealthState("player") == STEALTH_STATE_HIDDEN and powerValueChange < 0 and powerValueChange > -20 then
		Log("events", LOG_LEVEL_DEBUG, "Skill cost: %d Stamina (Sneak)", powerValueChange)
		return  20299

	end

	if GetPlayerSprintState() == SPRINT_STATE_ACTIVE and powerValueChange < 0 and powerValueChange > -20 then
		Log("events", LOG_LEVEL_DEBUG, "Skill cost: %d Stamina (Sprint)", powerValueChange)
		return  15617

	end
end

local function onBaseResourceChanged(powerType, powerValue, powerValueChange)
	local timems = GetGameTimeMilliseconds()
	local abilityId, adjustedPowerValueChange

 	if powerType == COMBAT_MECHANIC_FLAGS_MAGICKA then
		local regenerationTick = GetStat(STAT_MAGICKA_REGEN_COMBAT)

		Log("events", LOG_LEVEL_DEBUG, "Magicka change: %d", powerValueChange)

		-- Check for recently used skills
		abilityId = checkLastAbilities(timems, powerType, powerValueChange, powerValue)

		-- Check for regeneration tick
		if abilityId == -1 and powerValueChange == regenerationTick or (powerValueChange > 0 and powerValueChange <= regenerationTick and powerValue == data.stats[LIBCOMBAT_STAT_MAXMAGICKA]) then
			abilityId = 0
			Log("events", LOG_LEVEL_DEBUG, "Magicka Regeneration  (%d)", powerValueChange)

		elseif abilityId == -1 then	-- Check for combination of skill and regeneration tick
			abilityId = checkLastAbilities(timems, powerType, powerValueChange + regenerationTick, powerValue)

			if abilityId ~= -1 then
				Log("events", LOG_LEVEL_DEBUG, "Resource: %s (%d): %d (%d) --> %d", "Regeneration", 0, regenerationTick, powerType, powerValue + regenerationTick)
				lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_RESOURCES]), LIBCOMBAT_EVENT_RESOURCES, timems, 0, regenerationTick, powerType, powerValue + regenerationTick)
				powerValueChange = powerValueChange - regenerationTick

			end
		end

	elseif powerType == COMBAT_MECHANIC_FLAGS_STAMINA then
		local regenerationTick = GetStat(STAT_STAMINA_REGEN_COMBAT)
		Log("events", LOG_LEVEL_DEBUG, "Stamina change: %d", powerValueChange)

		-- Check for recently used skills
		abilityId, adjustedPowerValueChange = checkLastAbilities(timems, powerType, powerValueChange, powerValue)
		if adjustedPowerValueChange then powerValueChange = adjustedPowerValueChange end

		-- Check for regeneration tick
		if abilityId == -1 and powerValueChange == regenerationTick or (powerValueChange > 0 and powerValueChange <= regenerationTick and powerValue == data.stats[LIBCOMBAT_STAT_MAXMAGICKA]) then
			abilityId = 0
			Log("events", LOG_LEVEL_DEBUG, "Stamina Regeneration (%d)", powerValueChange)

		elseif abilityId == -1 then -- Check for combat actions
			abilityId = checkForCombatActions( powerValueChange)

			if abilityId == -1 then	-- Check for combination of skill and regeneration tick
				abilityId, adjustedPowerValueChange = checkLastAbilities(timems, powerType, powerValueChange + regenerationTick, powerValue)

				if adjustedPowerValueChange then powerValueChange = adjustedPowerValueChange end
				if abilityId ~= -1 then
					Log("events", LOG_LEVEL_DEBUG, "Resource: %s (%d): %d (%d) --> %d", "Regeneration", 0, regenerationTick, powerType, powerValue + regenerationTick)
					lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_RESOURCES]), LIBCOMBAT_EVENT_RESOURCES, timems, 0, regenerationTick, powerType, powerValue + regenerationTick)
					powerValueChange = powerValueChange - regenerationTick
				end
			end
		end

	elseif powerType == COMBAT_MECHANIC_FLAGS_ULTIMATE then
		abilityId = 0

	elseif powerType == COMBAT_MECHANIC_FLAGS_HEALTH then
		abilityId = -1

		if powerValueChange == GetStat(STAT_HEALTH_REGEN_COMBAT) and data.playerid then
			abilityId = 0
			lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_HEAL_SELF]), LIBCOMBAT_EVENT_HEAL_SELF, timems, ACTION_RESULT_HOT_TICK, data.playerid, data.playerid, abilityId, powerValueChange, powerType, 0)
			return
		end
	end

	Log("events", LOG_LEVEL_DEBUG, "Resource: %s (%d): %d (%d) --> %d", GetFormattedAbilityName(abilityId), abilityId, powerValueChange, powerType, powerValue)
	lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_RESOURCES]), LIBCOMBAT_EVENT_RESOURCES, timems, abilityId, powerValueChange, powerType, powerValue)
end

local function onBaseResourceChangedDelayed(_,unitTag,_,powerType,newValue,_,_)
	if unitTag ~= "player" or (data.inCombat == false) then return end
	if powerType ~= COMBAT_MECHANIC_FLAGS_HEALTH and powerType ~= COMBAT_MECHANIC_FLAGS_MAGICKA and powerType ~= COMBAT_MECHANIC_FLAGS_STAMINA and powerType ~= COMBAT_MECHANIC_FLAGS_ULTIMATE then return end

	local oldValue = data.resources[powerType]
	data.resources[powerType] = newValue
	if oldValue == nil or oldValue == newValue then return end

	local powerValueChange = newValue - oldValue
	if powerType == COMBAT_MECHANIC_FLAGS_HEALTH and data.statusEffectBonus and data.statusEffectBonus.wealdBonus>0 then currentfight:UpdateSingleStat(LIBCOMBAT_STAT_STATUS_EFFECT_CHANCE) end

	Log("events", LOG_LEVEL_DEBUG, "onBaseResourceChangedDelayed: %s, %d, %d", unitTag, powerType, powerValueChange)
	zo_callLater(function() onBaseResourceChanged(powerType, newValue, powerValueChange) end, 0)
end

--(eventCode, result, isError, abilityName, abilityGraphic, abilityActionSlotType, sourceName, sourceType, targetName, targetType, hitValue, powerType, damageType, log, sourceUnitId, targetUnitId, abilityId)
local function onResourceChanged (_, result, _, _, _, _, _, _, targetName, _, powerValueChange, powerType, _, _, sourceUnitId, targetUnitId, abilityId)
	if data.playerid == nil and targetName == data.rawPlayername then data.playerid = targetUnitId end
	if (powerType ~= COMBAT_MECHANIC_FLAGS_MAGICKA and powerType ~= COMBAT_MECHANIC_FLAGS_STAMINA) or data.inCombat == false or powerValueChange < 1 then return end

	local timems = GetGameTimeMilliseconds()
	local lastabilities = data.lastabilities

	if result == ACTION_RESULT_POWER_DRAIN then powerValueChange = -powerValueChange end
	table.insert(lastabilities,{timems, abilityId, powerValueChange, powerType})
	if #lastabilities > ABILITY_RESOURCE_CACHE_SIZE then table.remove(lastabilities, 1) end
end

local function onWeaponSwap(_, isHotbarSwap)
	local newbar = GetActiveHotbarCategory() + 1
	if data.bar == newbar then return end

	data.bar = newbar
	GetCurrentSkillBars()
	local inCombat = currentfight.prepared

	if inCombat == true then
		local timems = GetGameTimeMilliseconds()
		lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_MESSAGES]), LIBCOMBAT_EVENT_MESSAGES, timems, LIBCOMBAT_MESSAGE_WEAPONSWAP, data.bar)

		currentfight:GetNewStats(timems)
	end
end

local function CheckForWipe()

	if not IsUnitDeadOrReincarnating("player") then return end -- maybe it's enough if player is dead on combat end? (Unless it bugs, like Sunspire ... ¯\_(ツ)_/¯)

	if data.inGroup == false then

		currentfight.isWipe = true

	elseif data.inGroup == true then

		local loc = GetUnitZoneIndex("player")

		for i = 1, GetGroupSize() do

			local tag = ZO_CachedStrFormat("group<<1>>", i)

			local unitId = data.groupInfo.tagToId[tag]
			local unit = unitId and currentfight.units[unitId]

			if unit and (not unit.isDead) and GetUnitZoneIndex(tag) == loc then return end	-- if there is a group member in the zame zone but not dead then it's not a wipe

		end
	end

	currentfight.isWipe = true

	Log("DoA", LOG_LEVEL_DEBUG, "=== This is a wipe ! ===")

end

local function OnDeathStateChanged(_, unitTag, isDead) 	-- death (for group display, also works for different zones)

	local unitId = unitTag == "player" and data.playerid or data.groupInfo.tagToId[unitTag]

	Log("debug", LOG_LEVEL_DEBUG, "OnDeathStateChanged: %s (%s) is dead: %s", unitTag, tostring(unitId), tostring(isDead))

	if data.inCombat == false or unitId == nil then

		Log("debug", LOG_LEVEL_DEBUG, "OnDeathStateChanged: Combat: %s", tostring(data.inCombat))
		return
	end

	local unit = currentfight.units[unitId]
	if unit then unit.isDead = isDead else

		Log("debug", LOG_LEVEL_DEBUG, "OnDeathStateChanged: no unit")
		return
	end

	local timems = GetGameTimeMilliseconds()

	if isDead then

		local lasttime = lastdeaths[unitId]

		if (lasttime and lasttime - timems < 1000) then return end

		GetUnitCache(unitId):OnDeath(timems)

		Log("debug", LOG_LEVEL_DEBUG, "OnDeathStateChanged: fire callback")
		lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_DEATH]), LIBCOMBAT_EVENT_DEATH, timems, LIBCOMBAT_STATE_DEAD, unitId)

		CheckForWipe()

	else

		lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_DEATH]), LIBCOMBAT_EVENT_DEATH, timems, LIBCOMBAT_STATE_ALIVE, unitId)

	end
end

local function OnPlayerReincarnated()

	Log("DoA", LOG_LEVEL_DEBUG, "You revived")

end

local SpecialResultsInverse = {

	["ACTION_RESULT_BLADETURN"]       = ACTION_RESULT_BLADETURN,
	["ACTION_RESULT_BLOCKED_DAMAGE"]  = ACTION_RESULT_BLOCKED_DAMAGE,
	["ACTION_RESULT_DIED"]            = ACTION_RESULT_DIED,
	["ACTION_RESULT_DIED_XP"]         = ACTION_RESULT_DIED_XP,
	["ACTION_RESULT_KILLING_BLOW"]    = ACTION_RESULT_KILLING_BLOW,
	["ACTION_RESULT_PARTIAL_RESIST"]  = ACTION_RESULT_PARTIAL_RESIST,
	["ACTION_RESULT_PRECISE_DAMAGE"]  = ACTION_RESULT_PRECISE_DAMAGE,
	["ACTION_RESULT_REFLECTED"]       = ACTION_RESULT_REFLECTED,
	["ACTION_RESULT_REINCARNATING"]   = ACTION_RESULT_REINCARNATING,
	["ACTION_RESULT_RESIST"]          = ACTION_RESULT_RESIST,
	["ACTION_RESULT_RESURRECT"]       = ACTION_RESULT_RESURRECT,
	["ACTION_RESULT_WRECKING_DAMAGE"] = ACTION_RESULT_WRECKING_DAMAGE,

}

-- This avoids errors if obsolete constants are removed
local SpecialResults = {}
for k,v in pairs(SpecialResultsInverse) do
	if v then SpecialResults[v] = k end
end

local function OnDeath(_, result, _, abilityName, _, abilityActionSlotType, sourceName, sourceType, targetName, targetType, hitValue, powerType, damageType, _, sourceUnitId, targetUnitId, abilityId, overflow)

	local timems = GetGameTimeMilliseconds()

	if targetUnitId == nil or targetUnitId == 0 then return end

	local unitdata = currentfight.units[targetUnitId]

	if unitdata == nil or (unitdata.unitType ~= COMBAT_UNIT_TYPE_PLAYER and unitdata.unitType ~= COMBAT_UNIT_TYPE_GROUP) then return end

	lastdeaths[targetUnitId] = timems

	GetUnitCache(targetUnitId):OnDeath(timems)

	lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_DEATH]), LIBCOMBAT_EVENT_DEATH, timems, LIBCOMBAT_STATE_DEAD, targetUnitId, abilityId)

	CheckForWipe()
end

local function OnResurrect(_, result, _, abilityName, _, abilityActionSlotType, sourceName, sourceType, targetName, targetType, hitValue, powerType, damageType, _, sourceUnitId, targetUnitId, abilityId)


	local timems = GetGameTimeMilliseconds()

	if targetUnitId == nil or targetUnitId == 0 or data.inCombat == false then return end

	local unitdata = currentfight.units[targetUnitId]

	if unitdata == nil or unitdata.type ~= COMBAT_UNIT_TYPE_GROUP then return end

	lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_DEATH]), LIBCOMBAT_EVENT_DEATH, timems, LIBCOMBAT_STATE_ALIVE, targetUnitId)
end

local function OnResurrectResult(_, targetCharacterName, result, targetDisplayName)

	Log("DoA", LOG_LEVEL_DEBUG, "OnResurrectResult: %s", targetCharacterName)

	local timems = GetGameTimeMilliseconds()

	if result ~= RESURRECT_RESULT_SUCCESS then return end

	local name = ZO_CachedStrFormat(SI_UNIT_NAME, targetCharacterName) or ""

	local unitId = data.groupInfo.nameToId[name]

	if not unitId then return end

	lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_DEATH]), LIBCOMBAT_EVENT_DEATH, timems, LIBCOMBAT_STATE_RESURRECTED, unitId, data.playerid)

end

local function OnResurrectRequest(_, requesterCharacterName, timeLeftToAccept, requesterDisplayName)

	Log("DoA", LOG_LEVEL_DEBUG, "OnResurrectRequest: %s", requesterCharacterName)

	local timems = GetGameTimeMilliseconds()

	local name = ZO_CachedStrFormat(SI_UNIT_NAME, requesterCharacterName) or ""

	local unitId = data.groupInfo.nameToId[name]

	if not unitId then return end

	lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_DEATH]), LIBCOMBAT_EVENT_DEATH, timems, LIBCOMBAT_STATE_RESURRECTED, data.playerid, unitId)

end

local function onGroupChange()

	data.inGroup = IsUnitGrouped("player")

	local groupdata = data.groupInfo

	groupdata.nameToDisplayname = {}
	groupdata.nameToTag = {}

	if data.inGroup == true then

		for i = 1, GetGroupSize() do

			local unitTag = "group"..i

			local name = ZO_CachedStrFormat(SI_UNIT_NAME, GetUnitName(unitTag))
			local displayname = ZO_CachedStrFormat(SI_UNIT_NAME, GetUnitDisplayName(unitTag))

			groupdata.nameToDisplayname[name] = displayname
			groupdata.nameToTag[name] = unitTag

			local unitId = groupdata.nameToId[name]
			local unit = unitId and currentfight.units[unitId] or nil

			if unit then unit:UpdateGroupData() end
		end
	end
end

local function onWTF(_, result, _, abilityName, _, abilityActionSlotType, sourceName, sourceType, targetName, targetType, hitValue, powerType, damageType, _, sourceUnitId, targetUnitId, abilityId)

	local resulttext = SpecialResults[result] or tostring(result)

	Log("other", LOG_LEVEL_VERBOSE, "onWTF (%s): %s (%d, %d) / %s (%d, %d) - %s (%d): %d (type: %d)", resulttext, sourceName, sourceUnitId, sourceType, targetName, targetUnitId, targetType, GetFormattedAbilityName(abilityId), abilityId, hitValue or 0, damageType or 0)

end

local function CheckUnit(unitName, unitId, unitType, timems)

	local currentunits = currentfight.units

	if currentunits[unitId] == nil then currentunits[unitId] = UnitHandler:New(unitName, unitId, unitType) end
	local unit = currentunits[unitId]

	if unit.name == "Offline" or unit.name == "" then unit.name = ZO_CachedStrFormat(SI_UNIT_NAME, unitName) end

	if unit.unitType ~= COMBAT_UNIT_TYPE_GROUP and unitType==COMBAT_UNIT_TYPE_GROUP then

		unit.unitType = COMBAT_UNIT_TYPE_GROUP
		unit.isFriendly = true

	end

	if unit.isFriendly == false then

		local bossId = data.bossInfo[unit.name]		-- if this is a boss, add the id (e.g. 1 for unitTag == "boss1")

		if bossId then

			unit.bossId = bossId
			currentfight.bosses[bossId] = unitId

			unit.unitTag = ZO_CachedStrFormat("boss<<1>>", bossId)

		end
	end

	unit.dpsstart = unit.dpsstart or timems
	unit.dpsend = timems

	unit.starttime = unit.starttime or timems
	unit.endtime = timems
end

local function CheckForShield(timems, sourceUnitId, targetUnitId)

	for i = #DamageShieldBuffer, 1, -1 do

		local shieldTimems, shieldSourceUnitId, shieldTargetUnitId, shieldHitValue = unpack(DamageShieldBuffer[i])

		Log("debug", LOG_LEVEL_VERBOSE, "Eval Shield Index %d: Source: %s, Target: %s, Time: %d", i, tostring(shieldSourceUnitId == sourceUnitId), tostring(shieldTargetUnitId == targetUnitId), timems - shieldTimems)

		if shieldSourceUnitId == sourceUnitId and shieldTargetUnitId == targetUnitId and timems - shieldTimems < 100 then

			table.remove(DamageShieldBuffer, i)

			return shieldHitValue

		end
	end
end

--(eventCode, result, isError, abilityName, abilityGraphic, abilityActionSlotType, sourceName, sourceType, targetName, targetType, hitValue, powerType, damageType, log, sourceUnitId, targetUnitId, abilityId)

local function CombatEventHandler(isheal, _, result, _, _, _, _, sourceName, sourceType, targetName, targetType, hitValue, powerType, damageType, _, sourceUnitId, targetUnitId, abilityId, overflow)  -- called by Event

	if not (sourceUnitId > 0 and targetUnitId > 0) or (data.inCombat == false and (result==ACTION_RESULT_DOT_TICK_CRITICAL or result==ACTION_RESULT_DOT_TICK or isheal)) or targetType==2 then return end -- only record if both unitids are valid or player is in combat or a non dot damage action happens or the target is not a pet

	local timems = GetGameTimeMilliseconds()

	local shieldHitValue = CheckForShield(timems, sourceUnitId, targetUnitId) or 0

	if (hitValue + (overflow or 0) + shieldHitValue) <= 0 then return end

	if sourceUnitId then CheckUnit(sourceName, sourceUnitId, sourceType, timems) end
	if targetUnitId then CheckUnit(targetName, targetUnitId, targetType, timems) end

	if result == ACTION_RESULT_DAMAGE_SHIELDED then

		sourceUnitId = targetUnitId
		sourceType = targetType

	end

	local isout = (sourceType == 1 or sourceType == 2)
	local isin = targetType == 1

	local eventid = LIBCOMBAT_EVENT_DAMAGE_OUT + (isheal and 3 or 0) + ((isout and isin) and 2 or isin and 1 or 0)

	if currentfight.dpsstart == nil then currentfight:PrepareFight() end -- get stats before the damage event

	damageType = (isheal and powerType) or damageType

	if not isheal then overflow = shieldHitValue end

	currentfight:AddCombatEvent(timems, result, targetUnitId, hitValue, eventid, overflow)

	lib.cm:FireCallbacks((CallbackKeys[eventid]), eventid, timems, result, sourceUnitId, targetUnitId, abilityId, hitValue, damageType, (overflow or 0))

end

local function onCombatEventDmg(...)
	CombatEventHandler(false, ...)	-- (isheal, ...)
end

local function onCombatEventShield(eventCode, result, isError, abilityName, abilityGraphic, abilityActionSlotType, sourceName, sourceType, targetName, targetType, hitValue, powerType, damageType, log, sourceUnitId, targetUnitId, abilityId)

	DamageShieldBuffer[#DamageShieldBuffer + 1] = {GetGameTimeMilliseconds(), sourceUnitId, targetUnitId, hitValue}

	Log("debug", LOG_LEVEL_DEBUG, "Add %d Shield: %d -> %d  (%d)", hitValue, sourceUnitId, targetUnitId, #DamageShieldBuffer)

end

local function onCombatEventDmgIn(...)
	-- avoid counting actions to oneself twice
	local _, _, _, _, _, _, _, sourceType, _, targetType, _, _, _, _, _, _, _ = ...

	if (sourceType == COMBAT_UNIT_TYPE_PLAYER or sourceType == COMBAT_UNIT_TYPE_PLAYER_PET) and (targetType == COMBAT_UNIT_TYPE_PLAYER or targetType == COMBAT_UNIT_TYPE_PLAYER_PET) then return end

	CombatEventHandler(false, ...)	-- (isheal, ...)
end

local function onCombatEventHeal(...)
	local _, _, _, _, _, _, _, _, _, _, hitValue, _, _, _, _, _, _, overflow = ...

	if (hitValue + (overflow or 0)) < 2 or (data.inCombat == false and (GetGameTimeMilliseconds() - currentfight.combatend >= 50)) then return end				-- only record in combat

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

		Log("debug", LOG_LEVEL_WARNING, "Big Damage Event: (%d) %s did %d damage to %s", abilityId, GetFormattedAbilityName(abilityId), hitValue, tostring(targetName))

		return

	end

	table.insert(currentfight.grplog,{targetUnitId,hitValue,"dmg"})
end

local function onCombatEventHealGrp(_, _, _, _, _, _, _, _, _, targetType, hitValue, _, _, _, _, targetUnitId, _)  -- called by Event

	if targetType==2 or targetUnitId == nil or hitValue<2 or (data.inCombat == false and (GetGameTimeMilliseconds() - (currentfight.combatend or 0) >= 50)) then return end

	table.insert(currentfight.grplog,{targetUnitId,hitValue,"heal"})
end

--(eventCode, result, isError, abilityName, abilityGraphic, abilityActionSlotType, sourceName, sourceType, targetName, targetType, hitValue, powerType, damageType, log, sourceUnitId, targetUnitId, abilityId)

local function GroupCombatEventHandler(isheal, result, _, abilityName, _, _, sourceName, sourceType, targetName, _, hitValue, powerType, damageType, _, sourceUnitId, targetUnitId, abilityId, overflow)  -- called by Event

	if (hitValue + (overflow or 0)) < 0 or (not (targetUnitId > 0)) or (data.inCombat == false and (result==ACTION_RESULT_DOT_TICK_CRITICAL or result==ACTION_RESULT_DOT_TICK or isheal) ) then return end -- only record if both unitids are valid or player is in combat or a non dot damage action happens

	local timems = GetGameTimeMilliseconds()

	if currentfight.dpsstart == nil then currentfight:PrepareFight() end -- get stats before the damage event

	damageType = (isheal and powerType) or damageType

	GetUnitCache(targetUnitId):AddEvent(timems, result, sourceUnitId, abilityId, hitValue, damageType, overflow or 0)

	if overflow and overflow > 0 and not isheal then

		Log("debug", LOG_LEVEL_DEBUG, "GroupCombatEventHandler: %s has overflow damage!", targetName)
		GetUnitCache(targetUnitId):OnDeath(timems)

	end

end

local function onCombatEventGrpDmgIn(event, ...)

	local targetUnitId = select(15, ...)

	local unit = currentfight.units[targetUnitId]
	local targetType = unit and unit.unitType or nil

	if not targetType or (targetType ~= COMBAT_UNIT_TYPE_GROUP and targetType ~= COMBAT_UNIT_TYPE_PLAYER) then return end

	GroupCombatEventHandler(false, ...)

end

local function onCombatEventGrpHealIn(event, ...)

	local targetUnitId = select(15, ...)

	local unit = currentfight.units[targetUnitId]
	local targetType = unit and unit.unitType or nil

	if not targetType or (targetType ~= COMBAT_UNIT_TYPE_GROUP and targetType ~= COMBAT_UNIT_TYPE_PLAYER) then return end

	GroupCombatEventHandler(true, ...)

end

local function onBaseResourceChangedGroup(event, unitTag, powerIndex, powerType, powerValue, powerMax, powerEffectiveMax)

	local unitId = unitTag == "player" and data.playerid or data.groupInfo.tagToId[unitTag]

	if unitId then GetUnitCache(unitId):UpdateResource(powerType, powerValue, powerMax) end

end

local function GetReducedSlotId(reducedslot)

	local bar = zo_floor(reducedslot/10) + 1

	local slot = reducedslot%10

	local origId = (data.skillBars and data.skillBars[bar] and data.skillBars[bar][slot]) or nil

	return origId

end

local HeavyAttackCharging

local function onAbilityUsed(eventCode, result, isError, abilityName, abilityGraphic, abilityActionSlotType, sourceName, sourceType, targetName, targetType, hitValue, powerType, damageType, log, sourceUnitId, targetUnitId, abilityId)

	if Events.Skills.active ~= true or data.inCombat == false or not (validSkillStartResults[result] or (validNonProjectileSkillStartResults[result] and not isProjectile[abilityId])) then return end

	local timems = GetGameTimeMilliseconds()

	local lasttime = lastAbilityActivations[abilityId]
	if lasttime == nil or (timems - lasttime) > maxSkillDelay then return end

	lastAbilityActivations[abilityId] = nil

	local reducedslot = IdToReducedSlot[abilityId] or (abilityAdditionsReverse[abilityId] and IdToReducedSlot[abilityAdditionsReverse[abilityId]]) or nil

	local origId = GetReducedSlotId(reducedslot)

	local channeled, castTime = GetAbilityCastInfo(origId)

	Log("events", LOG_LEVEL_VERBOSE, "[%.3f] Skill fired: %s (%d), Duration: %ds Target: %s", timems/1000, GetAbilityName(origId), origId, (castTime or 0)/1000, tostring(targetName))

	HeavyAttackCharging = DirectHeavyAttacks[origId] and origId or nil

	local lastQ = lastQueuedAbilities[origId]
	lastQueuedAbilities[origId] = nil

	if lastQ and lasttime then

		Log("events", LOG_LEVEL_VERBOSE, "%s: act: %d, Q: %d, Diff: %d", GetFormattedAbilityName(origId), timems-lasttime, timems-lastQ, lastQ - lasttime)

	end

	local skillExecution = lastQ and math.max(lastQ, lasttime) or lasttime
	local skillDelay = timems - skillExecution

	skillDelay = skillDelay < maxSkillDelay and skillDelay or nil

	if castTime > 0 then

		local status = channeled and LIBCOMBAT_SKILLSTATUS_BEGIN_CHANNEL or LIBCOMBAT_SKILLSTATUS_BEGIN_DURATION

		lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_SKILL_TIMINGS]), LIBCOMBAT_EVENT_SKILL_TIMINGS, timems, reducedslot, origId, status, skillDelay, hitValue)

		local convertedId = abilityConversions[origId] and abilityConversions[origId][3] or abilityId

		usedCastTimeAbility[convertedId] = true


	else

		local status = LIBCOMBAT_SKILLSTATUS_INSTANT

		lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_SKILL_TIMINGS]), LIBCOMBAT_EVENT_SKILL_TIMINGS, timems, reducedslot, origId, status, skillDelay)

	end
end

local function onAbilityFinished(eventCode, result, isError, abilityName, abilityGraphic, abilityActionSlotType, sourceName, sourceType, targetName, targetType, hitValue, powerType, damageType, log, sourceUnitId, targetUnitId, abilityId)

	local timems = GetGameTimeMilliseconds()

	local reducedslot = IdToReducedSlot[abilityId] or (abilityAdditionsReverse[abilityId] and IdToReducedSlot[abilityAdditionsReverse[abilityId]]) or nil

	local origId = GetReducedSlotId(reducedslot)

	local specialResult = abilityConversions[origId] and abilityConversions[origId][4] or false

	if (validSkillEndResults[result] ~= true and result ~= specialResult) or (abilityId == 46324 and hitValue > 1) then return end

	if usedCastTimeAbility[abilityId] then

		Log("events", LOG_LEVEL_VERBOSE ,"Skill finished: %s (%d, R: %d)", GetAbilityName(origId), origId, result)

		lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_SKILL_TIMINGS]), LIBCOMBAT_EVENT_SKILL_TIMINGS, timems, reducedslot, origId, LIBCOMBAT_SKILLSTATUS_SUCCESS)

	end
end

local function onQueueEvent(_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, abilityId)

	if data.inCombat == false then return end

	local timems = GetGameTimeMilliseconds()

	local conversion = abilityConversions[abilityId]

	local convertedId = conversion and conversion[1] or abilityId

	local reducedslot = IdToReducedSlot[convertedId]

	if reducedslot == nil then

		Log("events", LOG_LEVEL_WARNING ,"reducedslot missing on queue event: [%.3f s] %s (%d)", (timems - currentfight.combatstart)/1000, GetAbilityName(abilityId), abilityId)
		return

	end

	lastQueuedAbilities[abilityId] = timems

	lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_SKILL_TIMINGS]), LIBCOMBAT_EVENT_SKILL_TIMINGS, timems, reducedslot, abilityId, LIBCOMBAT_SKILLSTATUS_QUEUE)

end

local function onProjectileEvent(eventCode, result, isError, abilityName, abilityGraphic, abilityActionSlotType, sourceName, sourceType, targetName, targetType, hitValue, powerType, damageType, log, sourceUnitId, targetUnitId, abilityId)

	if hitValue == nil or hitValue <= 1 or targetType == COMBAT_UNIT_TYPE_PLAYER or isProjectile[abilityId] == true then return end

	isProjectile[abilityId] = true

	Log("events", LOG_LEVEL_VERBOSE ,"[%.3f s] projectile: %s (%d)", (GetGameTimeMilliseconds() - currentfight.combatstart)/1000, GetAbilityName(abilityId), abilityId)

	-- if IdToReducedSlot[abilityId] then isProjectile[abilityId] = true end TODO: Check if this should be limited

end

local powerTypeCache = {}

local function GetPowerTypes(abilityId)

	local lastPowerType

	if powerTypeCache[abilityId] == nil then

		local newData = {}

		for i = 1, 4 do

			local powerType = GetNextAbilityMechanicFlag(abilityId, lastPowerType)

			if powerType and (powerType == COMBAT_MECHANIC_FLAGS_HEALTH or powerType == COMBAT_MECHANIC_FLAGS_MAGICKA or powerType == COMBAT_MECHANIC_FLAGS_STAMINA) then

				newData[powerType] = GetAbilityCost(abilityId,powerType, nil, "player")	-- add cost over time ??
				lastPowerType = powerType

			elseif powerType == nil then

				break

			end
		end

		powerTypeCache[abilityId] = newData
	end

	return powerTypeCache[abilityId]
end

local function onSlotUsed(_, slot)

	if data.inCombat == false or slot > 8 then return end

	local timems = GetGameTimeMilliseconds()
	local abilityId = GetSlottedAbilityId(slot)

	-- Print("events", LOG_LEVEL_DEBUG, "Ability Used: %s (%d)", GetFormattedAbilityName(abilityId), abilityId)

	local powerTypes = GetPowerTypes(abilityId)
	local lastabilities = data.lastabilities

	if Events.Resources.active and slot > 2 and NonContiguousCount(powerTypes)> 0 then

		for powerType, cost in pairs(powerTypes) do

			table.insert(lastabilities,{timems, abilityId, -cost, powerType})

		end

		if #lastabilities > ABILITY_RESOURCE_CACHE_SIZE then table.remove(lastabilities, 1) end

	end

	if Events.Skills.active then

		local conversion = abilityConversions[abilityId]

		local convertedId = conversion and conversion[1] or abilityId

		if HeavyAttackCharging == abilityId then

			onAbilityFinished(EVENT_COMBAT_EVENT, ACTION_RESULT_EFFECT_FADED, _, _, _, ACTION_SLOT_TYPE_HEAVY_ATTACK, _, _, _, _, _, _, _, _, _, _, convertedId)
			HeavyAttackCharging = nil

		else

			lastAbilityActivations[convertedId] = timems
			HeavyAttackCharging = nil

			local reducedslot = (data.bar - 1) * 10 + slot

			lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_SKILL_TIMINGS]), LIBCOMBAT_EVENT_SKILL_TIMINGS, timems, reducedslot, abilityId, LIBCOMBAT_SKILLSTATUS_REGISTERED)

		end
	end
end


-- * EVENT_POWER_UPDATE (*string* _unitTag_, *luaindex* _powerIndex_, *[CombatMechanicType|#CombatMechanicType]* _powerType_, *integer* _powerValue_, *integer* _powerMax_, *integer* _powerEffectiveMax_)

local tagToBossId = {} -- avoid string ops
for i = 1, 12 do
	local unitTag = ZO_CachedStrFormat("boss<<1>>", i)
	tagToBossId[unitTag] = i
end


local function onBossHealthChanged(eventid, unitTag, _, powerType, powerValue, powerMax, powerEffectiveMax)
	local timems = GetGameTimeMilliseconds()
	local BossHealthValue = zo_round(powerValue / powerMax * 100)
	if BossHealthValue == lastBossHealthValue then return end

	lastBossHealthValue = BossHealthValue
	local bossId = tagToBossId[unitTag]
	lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_BOSSHP]), LIBCOMBAT_EVENT_BOSSHP, timems, bossId, powerValue, powerMax)
end

local lastSkillBarUpdate = 0

local function GetCurrentSkillBarsDelayed()
	local timems = GetGameTimeMilliseconds()
	if timems - lastSkillBarUpdate < 400 then return end
	lastSkillBarUpdate = timems

	-- reregister skill
	zo_callLater(GetCurrentSkillBars, 400) 	-- temporary workaround for NB skill Assasins Will
end

local function onSlotUpdate(_, slotNum)
	if slotNum == 1 or slotNum == 2 then return end
	GetCurrentSkillBarsDelayed()
end

local frameIndex = 1
local frameData = {}
local currentsecond

local size = math.floor((1/GetCVar("MinFrameTime.2") + 40)/20)*20

for i = 1, size do
	frameData[i] = 0
end

local function onFrameUpdate()
	local new = GetFrameDeltaTimeSeconds()
	local now = GetTimeStamp()

	frameData[frameIndex] = new

	if now == currentsecond then
		frameIndex = frameIndex + 1
	else
		local timems = GetGameTimeMilliseconds()
		local sum = 0
		local min = 100
		local max = 0

		for k = 1, frameIndex do
			local v = frameData[k]
			sum = sum + v
			min = math.min(v, min)
			max = math.max(v, max)
		end

		lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_PERFORMANCE]), LIBCOMBAT_EVENT_PERFORMANCE, timems, frameIndex/sum, 1/max, 1/min, GetLatency())
		frameIndex = 1
		currentsecond = now
	end
end

local function enableLogging()
	frameIndex = 1
	currentsecond = GetTimeStamp()

	local active = em:RegisterForUpdate("LibCombat_Frames", 0, onFrameUpdate)

	em:UnregisterForUpdate("LibCombat_Frames_Enable")
end

local function onPlayerActivated2()
	em:RegisterForUpdate("LibCombat_Frames_Enable", playerActivatedTime , enableLogging)
end

local function onPlayerDeactivated()
	em:UnregisterForUpdate("LibCombat_Frames")
end

local function onQuickSlotChanged(_, actionSlotIndex)
	data.currentQuickslotIndex = actionSlotIndex
	local itemLink = GetSlotItemLink(data.currentQuickslotIndex, HOTBAR_CATEGORY_QUICKSLOT_WHEEL)
	Log("debug", LOG_LEVEL_INFO, "Quickslot New: %s", itemLink, actionSlotIndex)
end

local function onQuickSlotUsed(_, itemSoundCategory)
	local timems = GetGameTimeMilliseconds()
	-- if data.inCombat == false then return end
	local itemLink = GetSlotItemLink(data.currentQuickslotIndex, HOTBAR_CATEGORY_QUICKSLOT_WHEEL)
	Log("debug", LOG_LEVEL_INFO, "Used: %s", itemLink)
	if itemSoundCategory ~= GetSlotItemSound(data.currentQuickslotIndex, HOTBAR_CATEGORY_QUICKSLOT_WHEEL) then return end
	lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_QUICKSLOT]), LIBCOMBAT_EVENT_QUICKSLOT, timems, itemLink)
end

local function UpdateEventRegistrations()
	for _,Eventgroup in pairs(Events) do
		Eventgroup:UpdateEvents()
	end
end

local function UpdateResources(name, callbacktype, callback)
	local oldCallback = ActiveCallbackTypes[callbacktype][name]

	if callback and oldCallback then
		return false
	else
		ActiveCallbackTypes[callbacktype][name] = callback
		zo_callLater(UpdateEventRegistrations, 0)	-- delay a frame to avoid an issue if functions get registered and deregistered within the same frame
	end

	return true, oldCallback
end

local function InitResources()
	for i=LIBCOMBAT_EVENT_MIN,LIBCOMBAT_EVENT_MAX do
		ActiveCallbackTypes[i]={}
	end
end

function lib:RegisterForLogableCombatEvents(name, callback)
	for i = LIBCOMBAT_EVENT_DAMAGE_OUT, LIBCOMBAT_EVENT_MAX do
		lib:RegisterForCombatEvent(name, i, callback)
	end
end

function lib:RegisterForCombatEvent(name, callbacktype, callback)
	local isRegistered = UpdateResources(name, callbacktype, callback)
	if isRegistered then lib.cm:RegisterCallback(CallbackKeys[callbacktype], callback) end

	return isRegistered
end

function lib:UnregisterForCombatEvent(name, callbacktype)
	local isUnregistered, callback = UpdateResources(name, callbacktype)
	lib.cm:UnregisterCallback(CallbackKeys[callbacktype], callback)

	return isUnregistered
end

--- Legacy

function lib:RegisterAllLogCallbacks(callback, name)
	lib:RegisterForLogableCombatEvents(name, callback)
end

function lib:RegisterCallbackType(callbacktype, callback, name)
	lib:RegisterForCombatEvent(name, callbacktype, callback)
end

function lib:UnregisterCallbackType(callbacktype, callback, name)
	lib:UnregisterForCombatEvent(name, callbacktype)
end

function lib:GetCurrentFight()
	if currentfight.dpsstart ~= nil then
		return ZO_DeepTableCopy(currentfight)
	end
end

local function UpdateSkillEvents(self)

	for _, skill in pairs(SlotSkills) do

		local id, result, id2, result2 = unpack(skill)

		if not registeredSkills[id] then

			Log("events", LOG_LEVEL_VERBOSE, "Skill registered: %d: %s (%s), End:  %d: %s (%s))", id, GetAbilityName(id), tostring(result), id2 or 0, GetAbilityName(id2 or 0), tostring(result2))

			local active

			if result then

				active = self:RegisterEvent(EVENT_COMBAT_EVENT, onAbilityUsed, REGISTER_FILTER_ABILITY_ID, id, REGISTER_FILTER_COMBAT_RESULT, result)

			else

				active = self:RegisterEvent(EVENT_COMBAT_EVENT, onAbilityUsed, REGISTER_FILTER_ABILITY_ID, id)

			end

			if id2 and result2 then

				self:RegisterEvent(EVENT_COMBAT_EVENT, onAbilityFinished, REGISTER_FILTER_ABILITY_ID, id2, REGISTER_FILTER_COMBAT_RESULT, result2)

			end

			registeredSkills[id] = active

		end
	end
end

local EventHandler = ZO_Object:Subclass()

function EventHandler:New(...)
    local object = ZO_Object.New(self)
    object:Initialize(...)
    return object
end

function EventHandler:Initialize(callbacktypes,regfunc)

	self.data={}
	self.callbacktypes=callbacktypes
	self.active=false
	self.RegisterEvents = regfunc

end

function EventHandler:RegisterEvent(event, callback, ...) -- convinience function

	local filters = {...}

	lib.totalevents = (lib.totalevents or 0) + 1

	local active = EVENT_MANAGER:RegisterForEvent(lib.name..lib.totalevents, event, callback)
	local filtered = false

	if #filters>0 and (#filters)%2==0 then

		filtered = EVENT_MANAGER:AddFilterForEvent(lib.name..lib.totalevents, event, unpack(filters))

	end

	self.data[#self.data+1] = {

		["id"] = lib.totalevents,
		["event"] = event,
		["callback"] = callback,
		["active"] = active,
		["filtered"] = filtered,
		["filters"] = filters }  -- remove callbacks later, probably not necessary

	if active then lib.totalevents = lib.totalevents + 1 end

	if data.isUIActivated and event == EVENT_PLAYER_ACTIVATED then callback(EVENT_PLAYER_ACTIVATED, false) end

	return active
end

function EventHandler:UpdateEvents()

	local condition = false

	for k,v in pairs(self.callbacktypes) do

		if NonContiguousCount(ActiveCallbackTypes[v])>0 then condition = true break end

	end

	if condition == true and self.active == false then

		self:RegisterEvents()

	elseif condition == false and self.active == true then

		self:UnregisterEvents()
	end

end

function EventHandler:UnregisterEvents()

	for k,reg in pairs(self.data) do

		local inactive = EVENT_MANAGER:UnregisterForEvent(lib.name..reg.id, reg.event)

		if inactive then

			ZO_ClearTable(reg)
			self.data[k] = nil

		end
	end

	self.active = false

	if self.resetIds then registeredSkills = {} end
end

lib.Events = Events		-- debug exposure

local function UnregisterAllEvents()

	for _,Eventgroup in pairs(Events) do
		Eventgroup:UnregisterEvents()
	end
end

--  lib.UnregisterAllEvents = UnregisterAllEvents 	-- debug exposure

local function GetAllCallbackTypes()
	local t={}
	for i=LIBCOMBAT_EVENT_MIN,LIBCOMBAT_EVENT_MAX do
		t[i]=i
	end
	return t
end

Events.General = EventHandler:New(GetAllCallbackTypes()
	,
	function (self)
		self:RegisterEvent(EVENT_PLAYER_COMBAT_STATE, onCombatState)
		self:RegisterEvent(EVENT_GROUP_UPDATE, onGroupChange)
		self:RegisterEvent(EVENT_HOTBAR_SLOT_CHANGE_REQUESTED, GetCurrentSkillBars)
		self:RegisterEvent(EVENT_PLAYER_ACTIVATED, onPlayerActivated)
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onMageExplode, REGISTER_FILTER_ABILITY_ID, 50184)
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onPortalWorld, REGISTER_FILTER_ABILITY_ID, 108045)
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onPortalWorld, REGISTER_FILTER_ABILITY_ID, 121216)

		if lib.debug == true then

			self:RegisterEvent(EVENT_COMBAT_EVENT, onWTF, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_BLADETURN)
			self:RegisterEvent(EVENT_COMBAT_EVENT, onWTF, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_BLOCKED)
			self:RegisterEvent(EVENT_COMBAT_EVENT, onWTF, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_DIED_XP)
			self:RegisterEvent(EVENT_COMBAT_EVENT, onWTF, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_KILLING_BLOW)
			self:RegisterEvent(EVENT_COMBAT_EVENT, onWTF, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_PARTIAL_RESIST)
			self:RegisterEvent(EVENT_COMBAT_EVENT, onWTF, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_PRECISE_DAMAGE)
			self:RegisterEvent(EVENT_COMBAT_EVENT, onWTF, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_REFLECTED)
			self:RegisterEvent(EVENT_COMBAT_EVENT, onWTF, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_RESIST)
			self:RegisterEvent(EVENT_COMBAT_EVENT, onWTF, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_WRECKING_DAMAGE)

			self:RegisterEvent(EVENT_COMBAT_EVENT, onCustomEvent, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_EFFECT_GAINED_DURATION, REGISTER_FILTER_IS_ERROR, false)

		end

		self.active = true
	end
)

Events.DmgOut = EventHandler:New(
	{LIBCOMBAT_EVENT_FIGHTRECAP, LIBCOMBAT_EVENT_FIGHTSUMMARY, LIBCOMBAT_EVENT_DAMAGE_OUT, LIBCOMBAT_EVENT_DAMAGE_SELF},
	function (self)
		self:RegisterEvent(EVENT_BOSSES_CHANGED, onBossesChanged)
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

Events.DmgIn = EventHandler:New(
	{LIBCOMBAT_EVENT_FIGHTRECAP, LIBCOMBAT_EVENT_FIGHTSUMMARY, LIBCOMBAT_EVENT_DAMAGE_IN},
	function (self)
		self:RegisterEvent(EVENT_BOSSES_CHANGED, onBossesChanged)
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

Events.HealOut = EventHandler:New(
	{LIBCOMBAT_EVENT_FIGHTRECAP, LIBCOMBAT_EVENT_FIGHTSUMMARY, LIBCOMBAT_EVENT_HEAL_OUT, LIBCOMBAT_EVENT_HEAL_SELF},
	function (self)
		self:RegisterEvent(EVENT_BOSSES_CHANGED, onBossesChanged)
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

Events.HealIn = EventHandler:New(
	{LIBCOMBAT_EVENT_FIGHTRECAP, LIBCOMBAT_EVENT_FIGHTSUMMARY, LIBCOMBAT_EVENT_HEAL_IN},
	function (self)
		self:RegisterEvent(EVENT_BOSSES_CHANGED, onBossesChanged)
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

Events.CombatGrp = EventHandler:New(
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

Events.Effects = EventHandler:New(
	{LIBCOMBAT_EVENT_EFFECTS_IN,LIBCOMBAT_EVENT_EFFECTS_OUT,LIBCOMBAT_EVENT_GROUPEFFECTS_IN,LIBCOMBAT_EVENT_GROUPEFFECTS_OUT},
	function (self)
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onEffectChanged, REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_PLAYER)
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onEffectChanged, REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_PLAYER_PET)
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onEffectChanged, REGISTER_FILTER_UNIT_TAG, "player", REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_NONE)
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onEffectChanged, REGISTER_FILTER_UNIT_TAG, "player", REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_GROUP)
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onEffectChanged, REGISTER_FILTER_UNIT_TAG, "player", REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_TARGET_DUMMY)
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onEffectChanged, REGISTER_FILTER_UNIT_TAG, "player", REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_OTHER)

		for i=1,#SpecialBuffs do
			self:RegisterEvent(EVENT_COMBAT_EVENT, onSpecialBuffEvent, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_EFFECT_GAINED_DURATION, REGISTER_FILTER_ABILITY_ID, SpecialBuffs[i], REGISTER_FILTER_IS_ERROR, false)
			self:RegisterEvent(EVENT_COMBAT_EVENT, onSpecialBuffEvent, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_EFFECT_FADED, REGISTER_FILTER_ABILITY_ID, SpecialBuffs[i], REGISTER_FILTER_IS_ERROR, false)
			self:RegisterEvent(EVENT_COMBAT_EVENT, onSpecialBuffEvent, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_EFFECT_GAINED, REGISTER_FILTER_ABILITY_ID, SpecialBuffs[i], REGISTER_FILTER_IS_ERROR, false)
		end

		for i=1,#SpecialDebuffs do
			self:RegisterEvent(EVENT_COMBAT_EVENT, onSpecialDebuffEvent, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_EFFECT_GAINED_DURATION, REGISTER_FILTER_ABILITY_ID, SpecialDebuffs[i], REGISTER_FILTER_IS_ERROR, false)
			self:RegisterEvent(EVENT_COMBAT_EVENT, onSpecialDebuffEvent, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_EFFECT_FADED, REGISTER_FILTER_ABILITY_ID, SpecialDebuffs[i], REGISTER_FILTER_IS_ERROR, false)
			self:RegisterEvent(EVENT_COMBAT_EVENT, onSpecialDebuffEvent, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_EFFECT_GAINED, REGISTER_FILTER_ABILITY_ID, SpecialDebuffs[i], REGISTER_FILTER_IS_ERROR, false)
		end

		for i=1,#SourceBuggedBuffs do
			self:RegisterEvent(EVENT_EFFECT_CHANGED, onSourceBuggedEffectChanged, REGISTER_FILTER_ABILITY_ID, SourceBuggedBuffs[i])
		end

		self:RegisterEvent(EVENT_COMBAT_EVENT, onTrialDummy, REGISTER_FILTER_ABILITY_ID, 120024, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_EFFECT_GAINED, REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_TARGET_DUMMY, REGISTER_FILTER_IS_ERROR, false)

		self.active = true
	end
)

Events.GroupEffectsIn = EventHandler:New(
	{LIBCOMBAT_EVENT_GROUPEFFECTS_IN},
	function (self)
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onGroupEffectIn, REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_GROUP, REGISTER_FILTER_UNIT_TAG_PREFIX, "group")
		self.active = true
	end
)

Events.GroupEffectsOut = EventHandler:New(
	{LIBCOMBAT_EVENT_GROUPEFFECTS_OUT},
	function (self)
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onGroupEffectOut, REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_GROUP, REGISTER_FILTER_UNIT_TAG, "")
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onGroupEffectOut, REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_GROUP, REGISTER_FILTER_UNIT_TAG, "reticleover")
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onGroupEffectOut, REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_GROUP, REGISTER_FILTER_UNIT_TAG, "reticleoverplayer")
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onGroupEffectOut, REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_GROUP, REGISTER_FILTER_UNIT_TAG_PREFIX, "boss")
		self.active = true
	end
)

Events.Stats = EventHandler:New(
	{LIBCOMBAT_EVENT_PLAYERSTATS},
	function (self)

		self:RegisterEvent(EVENT_EFFECT_CHANGED, onShadowMundus, REGISTER_FILTER_UNIT_TAG, "player", REGISTER_FILTER_ABILITY_ID, 13984)

		self:RegisterEvent(EVENT_EFFECT_CHANGED, onTFSChanged, REGISTER_FILTER_UNIT_TAG, "player", REGISTER_FILTER_ABILITY_ID, 51176)  -- to track TFS procs, which aren't recognized for stacks > 1 in penetration stat.

		self.active = true
	end
)

Events.AdvancedStats = EventHandler:New(
	{LIBCOMBAT_EVENT_PLAYERSTATS_ADVANCED},
	function (self)
		self.active = true
	end
)

Events.Resources = EventHandler:New(
	{LIBCOMBAT_EVENT_RESOURCES},
	function (self)
		self:RegisterEvent(EVENT_POWER_UPDATE, onBaseResourceChangedDelayed, REGISTER_FILTER_UNIT_TAG, "player")
		self:RegisterEvent(EVENT_COMBAT_EVENT, onResourceChanged, REGISTER_FILTER_TARGET_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_PLAYER, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_POWER_ENERGIZE, REGISTER_FILTER_IS_ERROR, false)
		self:RegisterEvent(EVENT_COMBAT_EVENT, onResourceChanged, REGISTER_FILTER_TARGET_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_PLAYER, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_POWER_DRAIN, REGISTER_FILTER_IS_ERROR, false)
		self.active = true
	end
)

Events.Messages = EventHandler:New(
	{LIBCOMBAT_EVENT_MESSAGES, LIBCOMBAT_EVENT_FIGHTSUMMARY, LIBCOMBAT_EVENT_SKILL_TIMINGS},
	function (self)
		self:RegisterEvent(EVENT_ACTION_SLOTS_FULL_UPDATE, onWeaponSwap)


		self.active = true
	end
)

Events.Deaths = EventHandler:New(
	{LIBCOMBAT_EVENT_DEATH, LIBCOMBAT_EVENT_DEATHRECAP},
	function (self)

		self:RegisterEvent(EVENT_COMBAT_EVENT, OnDeath, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_KILLING_BLOW)
		self:RegisterEvent(EVENT_COMBAT_EVENT, OnDeath, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_DIED)
		self:RegisterEvent(EVENT_COMBAT_EVENT, OnResurrect, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_RESURRECT)
		self:RegisterEvent(EVENT_COMBAT_EVENT, OnResurrect, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_REINCARNATING)
		self:RegisterEvent(EVENT_UNIT_DEATH_STATE_CHANGED, OnDeathStateChanged, REGISTER_FILTER_UNIT_TAG_PREFIX, "group")
		self:RegisterEvent(EVENT_UNIT_DEATH_STATE_CHANGED, OnDeathStateChanged, REGISTER_FILTER_UNIT_TAG, "player")
		self:RegisterEvent(EVENT_PLAYER_REINCARNATED, OnPlayerReincarnated)

		self:RegisterEvent(EVENT_RESURRECT_RESULT, OnResurrectResult)
		self:RegisterEvent(EVENT_RESURRECT_REQUEST, OnResurrectRequest)

		self.active = true

	end
)

Events.DeathRecap = EventHandler:New(
	{LIBCOMBAT_EVENT_DEATHRECAP},
	function (self)

		local filters = {
			ACTION_RESULT_DAMAGE,
			ACTION_RESULT_DOT_TICK,
			ACTION_RESULT_BLOCKED_DAMAGE,
			ACTION_RESULT_DAMAGE_SHIELDED,
			ACTION_RESULT_CRITICAL_DAMAGE,
			ACTION_RESULT_DOT_TICK_CRITICAL,
			ACTION_RESULT_FALL_DAMAGE,
			ACTION_RESULT_DODGED,
		}

		for _, filter in ipairs(filters) do
			self:RegisterEvent(EVENT_COMBAT_EVENT, onCombatEventGrpDmgIn, REGISTER_FILTER_COMBAT_RESULT, filter, REGISTER_FILTER_IS_ERROR, false)
		end

		local filters2 = {
			ACTION_RESULT_HOT_TICK,
			ACTION_RESULT_HEAL,
			ACTION_RESULT_CRITICAL_HEAL,
			ACTION_RESULT_HOT_TICK_CRITICAL,
		}

		for _, filter in ipairs(filters2) do
			self:RegisterEvent(EVENT_COMBAT_EVENT, onCombatEventGrpHealIn, REGISTER_FILTER_COMBAT_RESULT, filter, REGISTER_FILTER_IS_ERROR, false)
		end

		self:RegisterEvent(EVENT_POWER_UPDATE, onBaseResourceChangedGroup, REGISTER_FILTER_UNIT_TAG_PREFIX, "group")
		self:RegisterEvent(EVENT_POWER_UPDATE, onBaseResourceChangedGroup, REGISTER_FILTER_UNIT_TAG, "player")

		self.active = true
	end
)

Events.Slots = EventHandler:New(
	{LIBCOMBAT_EVENT_RESOURCES, LIBCOMBAT_EVENT_SKILL_TIMINGS},
	function (self)

		self:RegisterEvent(EVENT_ACTION_SLOT_ABILITY_USED, onSlotUsed)

		self.active = true

	end
)

Events.Skills = EventHandler:New(
	{LIBCOMBAT_EVENT_SKILL_TIMINGS},
	function (self)

		self:RegisterEvent(EVENT_COMBAT_EVENT, GetCurrentSkillBarsDelayed, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_EFFECT_GAINED, REGISTER_FILTER_ABILITY_ID, 24785) -- Overload & Morphs
		self:RegisterEvent(EVENT_COMBAT_EVENT, GetCurrentSkillBarsDelayed, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_EFFECT_GAINED, REGISTER_FILTER_ABILITY_ID, 24806) -- Overload & Morphs
		self:RegisterEvent(EVENT_COMBAT_EVENT, GetCurrentSkillBarsDelayed, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_EFFECT_GAINED, REGISTER_FILTER_ABILITY_ID, 24804) -- Overload & Morphs
		self:RegisterEvent(EVENT_ACTION_SLOT_UPDATED, onSlotUpdate)
		self:RegisterEvent(EVENT_COMBAT_EVENT, onQueueEvent, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_QUEUED, REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_PLAYER)
		self:RegisterEvent(EVENT_COMBAT_EVENT, onProjectileEvent, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_EFFECT_GAINED, REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_PLAYER)

		self.Update = UpdateSkillEvents

		UpdateSkillEvents(self)

		self.active = true
		self.resetIds = true

	end
)

Events.BossHP = EventHandler:New(
	{LIBCOMBAT_EVENT_BOSSHP},
	function (self)
		self:RegisterEvent(EVENT_POWER_UPDATE, onBossHealthChanged, REGISTER_FILTER_UNIT_TAG, "boss1", REGISTER_FILTER_POWER_TYPE, COMBAT_MECHANIC_FLAGS_HEALTH)
		self.active = true
	end
)

Events.Performance = EventHandler:New(
	{LIBCOMBAT_EVENT_PERFORMANCE},
	function (self)
		self:RegisterEvent(EVENT_PLAYER_DEACTIVATED, onPlayerDeactivated)
		self:RegisterEvent(EVENT_PLAYER_ACTIVATED, onPlayerActivated2)
		self.active = true
	end
)

Events.QuickSlot = EventHandler:New(
	{LIBCOMBAT_EVENT_QUICKSLOT},
	function (self)
		self:RegisterEvent(EVENT_INVENTORY_ITEM_USED, onQuickSlotUsed)
		self:RegisterEvent(EVENT_ACTIVE_QUICKSLOT_CHANGED, onQuickSlotChanged)
		self.active = true
	end
)

-- Events.Synergy = EventHandler:New(
-- 	{LIBCOMBAT_EVENT_SYNERGY},
-- 	function (self)
-- 		-- self:RegisterEvent(EVENT_PLAYER_DEACTIVATED, onSynergyAvailable)
-- 		-- self:RegisterEvent(EVENT_PLAYER_DEACTIVATED, onSynergyTaken)
-- 		self.active = true
-- 	end
-- )


function lib:GetCombatLogString(fight, logline, fontsize, showIds)

	if fight == nil then fight = currentfight end

	local logtype = logline[1]

	local color, text

	local timeValue = fight.combatstart < 0 and 0 or (logline[2] - fight.combatstart)/1000
	local timeString = string.format("|ccccccc[%.3fs]|r", timeValue)
	local logFormat = GetString("SI_LIBCOMBAT_LOG_FORMATSTRING", logtype)

	local units = fight.units

	if logtype == LIBCOMBAT_EVENT_DAMAGE_OUT then

		local _, _, result, _, targetUnitId, abilityId, hitValue, damageType, overflow = unpack(logline)

		local crit = (result == ACTION_RESULT_CRITICAL_DAMAGE or result == ACTION_RESULT_DOT_TICK_CRITICAL) and ZO_CachedStrFormat("|cFFCC99<<1>>|r", GetString(SI_LIBCOMBAT_LOG_CRITICAL)) or ""

		local targetname = units[targetUnitId].name
		local targetFormat = (result == ACTION_RESULT_BLOCKED_DAMAGE and SI_LIBCOMBAT_LOG_FORMAT_TARGET_BLOCK) or SI_LIBCOMBAT_LOG_FORMAT_TARGET_NORMAL

		local targetString = ZO_CachedStrFormat(GetString(targetFormat), targetname)

		local ability = lib.GetAbilityString(abilityId, damageType, fontsize, showIds)

		local hitValueString = overflow > 0 and ZO_CachedStrFormat(GetString(SI_LIBCOMBAT_LOG_FORMAT_ABSORBED), hitValue, overflow) or hitValue

		color = {1.0,0.6,0.6}
		text = ZO_CachedStrFormat(logFormat, timeString, crit, targetString, ability, hitValueString)

	elseif logtype == LIBCOMBAT_EVENT_DAMAGE_IN then

		local _, _, result, sourceUnitId, _, abilityId, hitValue, damageType, overflow = unpack(logline)

		local crit = (result == ACTION_RESULT_CRITICAL_DAMAGE or result == ACTION_RESULT_DOT_TICK_CRITICAL) and ZO_CachedStrFormat("|cFFCC99<<1>>|r", GetString(SI_LIBCOMBAT_LOG_CRITICAL)) or ""

		local sourceName = units[sourceUnitId].name

		local targetFormat = (result == ACTION_RESULT_BLOCKED_DAMAGE and SI_LIBCOMBAT_LOG_FORMAT_TARGETSELF_BLOCK) or SI_LIBCOMBAT_LOG_FORMAT_TARGETSELF_NORMAL
		local targetString = GetString(targetFormat)

		local ability = lib.GetAbilityString(abilityId, damageType, fontsize, showIds)

		local hitValueString = overflow > 0 and ZO_CachedStrFormat(GetString(SI_LIBCOMBAT_LOG_FORMAT_ABSORBED), hitValue, overflow) or hitValue

		color = {0.8,0.4,0.4}

		text = ZO_CachedStrFormat(logFormat, timeString, sourceName, crit, targetString, ability, hitValueString)

	elseif logtype == LIBCOMBAT_EVENT_DAMAGE_SELF then

		local _, _, result, _, _, abilityId, hitValue, damageType, overflow = unpack(logline)

		local crit = (result == ACTION_RESULT_CRITICAL_HEAL or result == ACTION_RESULT_HOT_TICK_CRITICAL) and ZO_CachedStrFormat("|cFFCC99<<1>>|r", GetString(SI_LIBCOMBAT_LOG_CRITICAL)) or ""

		local targetFormat = (result == ACTION_RESULT_BLOCKED_DAMAGE and SI_LIBCOMBAT_LOG_FORMAT_TARGETSELF_BLOCK) or SI_LIBCOMBAT_LOG_FORMAT_TARGETSELF_SELF
		local targetString = GetString(targetFormat)

		local ability = lib.GetAbilityString(abilityId, damageType, fontsize)

		local hitValueString = overflow > 0 and ZO_CachedStrFormat(GetString(SI_LIBCOMBAT_LOG_FORMAT_ABSORBED), hitValue, overflow) or hitValue

		color = {0.8,0.4,0.4}
		text = ZO_CachedStrFormat(logFormat, timeString, crit, targetString, ability, hitValueString)

	elseif logtype == LIBCOMBAT_EVENT_HEAL_OUT then

		local _, _, result, _, targetUnitId, abilityId, hitValue, _, overflow = unpack(logline)

		local crit = (result == ACTION_RESULT_CRITICAL_HEAL or result == ACTION_RESULT_HOT_TICK_CRITICAL) and ZO_CachedStrFormat("|cFFCC99<<1>>|r", GetString(SI_LIBCOMBAT_LOG_CRITICAL)) or ""

		local targetname = units[targetUnitId].name

		local ability = lib.GetAbilityString(abilityId, "heal", fontsize, showIds)

		color = {0.6,1.0,0.6}
		text = ZO_CachedStrFormat(logFormat, timeString, crit, targetname, ability, hitValue)

	elseif logtype == LIBCOMBAT_EVENT_HEAL_IN then

		local _, _, result, sourceUnitId, _, abilityId, hitValue, _, overflow  = unpack(logline)

		local crit = (result == ACTION_RESULT_CRITICAL_HEAL or result == ACTION_RESULT_HOT_TICK_CRITICAL) and ZO_CachedStrFormat("|cFFCC99<<1>>|r", GetString(SI_LIBCOMBAT_LOG_CRITICAL)) or ""

		local sourceName = units[sourceUnitId].name

		local ability = lib.GetAbilityString(abilityId, "heal", fontsize, showIds)

		color = {0.4,0.8,0.4}

		text = ZO_CachedStrFormat(logFormat, timeString, sourceName, crit, ability, hitValue)

	elseif logtype == LIBCOMBAT_EVENT_HEAL_SELF then

		local _, _, result, _, _, abilityId, hitValue, _, overflow = unpack(logline)

		local crit = (result == ACTION_RESULT_CRITICAL_HEAL or result == ACTION_RESULT_HOT_TICK_CRITICAL) and ZO_CachedStrFormat("|cFFCC99<<1>>|r", GetString(SI_LIBCOMBAT_LOG_CRITICAL)) or ""

		local ability = lib.GetAbilityString(abilityId, "heal", fontsize, showIds)

		color = {0.8,1.0,0.6}
		text = result == ACTION_RESULT_DAMAGE_SHIELDED and ZO_CachedStrFormat(GetString(SI_LIBCOMBAT_LOG_FORMAT_HEALABSORB), timeString, ability, hitValue) or ZO_CachedStrFormat(logFormat, timeString, crit, ability, hitValue)

	elseif logtype == LIBCOMBAT_EVENT_EFFECTS_IN or logtype == LIBCOMBAT_EVENT_EFFECTS_OUT or logtype == LIBCOMBAT_EVENT_GROUPEFFECTS_IN or logtype == LIBCOMBAT_EVENT_GROUPEFFECTS_OUT then

		local _, _, unitId, abilityId, changeType, effectType, stacks, sourceType, slot = unpack(logline)

		if units[unitId] == nil then return end

		local unitString = fight.playerid == unitId and GetString(SI_LIBCOMBAT_LOG_YOU) or units[unitId].name

		local changeTypeString = (changeType == EFFECT_RESULT_GAINED or changeType == EFFECT_RESULT_UPDATED) and GetString(SI_LIBCOMBAT_LOG_GAINED) or changeType == EFFECT_RESULT_FADED and GetString(SI_LIBCOMBAT_LOG_LOST)

		local source = lib.UnitTypeString[sourceType] == nil and "" or ZO_CachedStrFormat(" from <<1>>", lib.UnitTypeString[sourceType])

		local colorKey = effectType == BUFF_EFFECT_TYPE_DEBUFF and "debuff" or "buff"

		local buff = lib.GetAbilityString(abilityId, colorKey, fontsize, showIds, stacks)

		color = {0.8,0.8,0.8}

		text = ZO_CachedStrFormat(logFormat, timeString, unitString, changeTypeString, buff, source)

	elseif logtype == LIBCOMBAT_EVENT_RESOURCES then

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

			local ability = abilityId and ZO_CachedStrFormat("(<<1>>)", lib.GetAbilityString(abilityId, "resource", fontsize, showIds)) or ""

			color = (powerType == COMBAT_MECHANIC_FLAGS_MAGICKA and {0.7,0.7,1}) or (powerType == COMBAT_MECHANIC_FLAGS_STAMINA and {0.7,1,0.7}) or (powerType == COMBAT_MECHANIC_FLAGS_ULTIMATE and {1,1,0.7}) or color
			text = ZO_CachedStrFormat(logFormat, timeString, changeTypeString, amount, resource, ability)

		else return
		end

	elseif logtype == LIBCOMBAT_EVENT_PLAYERSTATS then

		local _, _, statchange, newvalue, statId = unpack(logline)

		local stat = lib.statStrings[statId]
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

	elseif logtype == LIBCOMBAT_EVENT_MESSAGES then

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

		else return end

		text = ZO_CachedStrFormat("<<1>> <<2>>", timeString, messagetext)

	elseif logtype == LIBCOMBAT_EVENT_SKILL_TIMINGS then

		local _, _, reducedslot, abilityId, status, skillDelay = unpack(logline)

		if reducedslot == nil then

			Log("events", LOG_LEVEL_DEBUG, "Invalid Slot: %s (%d), Status: %d)", GetAbilityName(abilityId), abilityId, status)

			return

		end

		local skillDelayString = skillDelay and ZO_CachedStrFormat(GetString(SI_LIBCOMBAT_LOG_FORMATSTRING_SKILLDELAY), skillDelay) or ""

		logFormat = GetString("SI_LIBCOMBAT_LOG_FORMATSTRING_SKILLS", status)

		local isWeaponAttack = reducedslot%10 == 1 or reducedslot%10 == 2

		local formatstring = " |cddffbb<<1>>|r"

		if isWeaponAttack then formatstring = " |cffffff<<1>>|r" end

		local name = ZO_CachedStrFormat(formatstring, GetFormattedAbilityName(abilityId))

		color = {.9,.8,.7}

		text = ZO_CachedStrFormat(logFormat, timeString, name, skillDelayString)

	elseif logtype == LIBCOMBAT_EVENT_BOSSHP then

		local _, _, bossId, currenthp, maxhp = unpack(logline)

		local unitId = fight.bosses[bossId]

		local bossName = units[unitId].name

		local percent = zo_round(currenthp/maxhp * 100)

		color = {.9,.7,.5}

		text = ZO_CachedStrFormat(logFormat, timeString, bossName, percent, currenthp, maxhp)

	elseif logtype == LIBCOMBAT_EVENT_PERFORMANCE then

		local _, _, fps, min, max, ping = unpack(logline)

		color = {.9,.9,.9}

		local pingcolor = ping <= 50 and "99ff99" or ping <= 80 and "ccff99" or ping <= 120 and "ffff99" or ping <= 160 and "ffcc99" or "ff9999"
		local pingString = ZO_CachedStrFormat("|c<<1>><<2>>|r", pingcolor, ping)

		local fpsColor = fps >= 100 and "99ff99" or fps >= 60 and "ccff99" or fps >= 40 and "ffff99" or fps >= 25 and "ffcc99" or "ff9999"
		local fpsString = ZO_CachedStrFormat("|c<<1>><<2>>|r", fpsColor, fps)

		local minString = min < (0.5 * fps) and min < 25 and ZO_CachedStrFormat("|cff9999<<1>>|r", min) or min < (0.7 * fps) and min < 40 and ZO_CachedStrFormat("|cffddbb<<1>>|r", min) or min

		text = ZO_CachedStrFormat(logFormat, timeString, fpsString, minString, max, pingString)

	elseif logtype == LIBCOMBAT_EVENT_DEATH then

		local _, _, state, unitId, otherId = unpack(logline)

		logFormat = GetString("SI_LIBCOMBAT_LOG_FORMATSTRING_DEATH", state)

		local isSelf = fight.playerid == unitId

		local unitString = isSelf and GetString(SI_LIBCOMBAT_LOG_YOU) or units[unitId].name

		local action = ""
		local otherString = ""

		if state == 1 and otherId ~= nil then otherString = lib.GetAbilityString(otherId, DAMAGE_TYPE_GENERIC, fontsize, showIds) end

		if state > 2 then

			action = GetString("SI_LIBCOMBAT_LOG_RESURRECT", isSelf and 1 or 2)

		end

		text = ZO_CachedStrFormat(logFormat, timeString, unitString, action, otherString)

		color = {.7,.7,.7}

	end

	return text, color
end

function lib.Initialize()

	data.inCombat = IsUnitInCombat("player")
	data.inGroup = IsUnitGrouped("player")
	data.rawPlayername = GetRawUnitName("player")
	data.playername = ZO_CachedStrFormat(SI_UNIT_NAME, data.rawPlayername)
	data.accountname = ZO_CachedStrFormat(SI_UNIT_NAME, GetDisplayName())
	data.bossInfo = {}
	data.groupInfo = {nameToId = {}, tagToId = {}, nameToTag = {}, nameToDisplayname = {}}
	data.PlayerPets = {}
	data.lastabilities = {}
	data.backstabber = 0
	data.critBonusMundus = 0
	data.bar = GetActiveWeaponPairInfo()
	data.resources = {}
	data.stats = {}
	data.advancedStats = {}
	data.currentQuickslotIndex = GetCurrentQuickslot()

	--resetfightdata
	currentfight = FightHandler:New()

	InitResources()
	onBossesChanged()
	InitAdvancedStats()

	if data.LoadCustomizations then data.LoadCustomizations() end

	em:RegisterForEvent("LibCombatActive", EVENT_PLAYER_ACTIVATED, function() data.isUIActivated = true end)
	em:RegisterForEvent("LibCombatActive", EVENT_PLAYER_DEACTIVATED, function() data.isUIActivated = false end)
end

lib.Initialize()
