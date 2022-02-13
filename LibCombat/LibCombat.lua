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
local dx = math.ceil(GuiRoot:GetWidth()/tonumber(GetCVar("WindowedWidth"))*1000)/1000
LIBCOMBAT_LINE_SIZE = dx

local lib = {}
lib.version = 58
LibCombat = lib

-- Basic values
lib.name = "LibCombat"
lib.data = {skillBars= {}}
lib.cm = ZO_CallbackObject:New()

-- Logger

local mainlogger
local subloggers = {}
local LOG_LEVEL_VERBOSE = "V"
local LOG_LEVEL_DEBUG = "D"
local LOG_LEVEL_INFO = "I"
local LOG_LEVEL_WARNING ="W"
local LOG_LEVEL_ERROR = "E"

if LibDebugLogger then

	mainlogger = LibDebugLogger.Create(lib.name)

	LOG_LEVEL_VERBOSE = LibDebugLogger.LOG_LEVEL_VERBOSE
	LOG_LEVEL_DEBUG = LibDebugLogger.LOG_LEVEL_DEBUG
	LOG_LEVEL_INFO = LibDebugLogger.LOG_LEVEL_INFO
	LOG_LEVEL_WARNING = LibDebugLogger.LOG_LEVEL_WARNING
	LOG_LEVEL_ERROR = LibDebugLogger.LOG_LEVEL_ERROR

	subloggers["DoA"] = mainlogger:Create("DoA")
	subloggers["other"] = mainlogger:Create("other")
	subloggers["fight"] = mainlogger:Create("fight")
	subloggers["events"] = mainlogger:Create("events")
	subloggers["debug"] = mainlogger:Create("debug")

end

local function Print(category, level, ...)

	if mainlogger == nil then return end

	local logger = category and subloggers[category] or mainlogger

	if category == "debug" and lib.debug ~= true then return end

	if type(logger.Log)=="function" then logger:Log(level, ...) end

end

--aliases

local wm = GetWindowManager()
local em = GetEventManager()
local _
local reset = false
local data = lib.data
lib.debug = false or GetDisplayName() == "@Solinur"
local timeout = 800
local activetimeonheals = true
local ActiveCallbackTypes = {}
lib.ActiveCallbackTypes = ActiveCallbackTypes
local CustomAbilityTypeList = {}
local currentfight
local Events = {}
local EffectBuffer = {}
local lastdeaths = {}
local SlotSkills = {}
local IdToReducedSlot = {}
local lastAbilityActivations = {}
local isProjectile = {}
local AlkoshData = {}
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

local stringformat = string.format
local stringsub = string.sub
local stringmatch = string.match
local mathfloor = math.floor
local mathmax = math.max
local mathmin = math.min
local mathabs = math.abs

local ZO_CachedStrFormat = ZO_CachedStrFormat

-- types of callbacks: Units, DPS/HPS, DPS/HPS for Group, Logevents

LIBCOMBAT_EVENT_MIN = 0
LIBCOMBAT_EVENT_UNITS = 0					-- LIBCOMBAT_EVENT_UNITS, {units}
LIBCOMBAT_EVENT_FIGHTRECAP = 1				-- LIBCOMBAT_EVENT_FIGHTRECAP, {data}
LIBCOMBAT_EVENT_FIGHTSUMMARY = 2			-- LIBCOMBAT_EVENT_FIGHTSUMMARY, {fight}
LIBCOMBAT_EVENT_GROUPRECAP = 3				-- LIBCOMBAT_EVENT_GROUPRECAP, groupDPSOut, groupDPSIn, groupHPS, dpstime, hpstime
LIBCOMBAT_EVENT_DAMAGE_OUT = 4				-- LIBCOMBAT_EVENT_DAMAGE_OUT, timems, result, sourceUnitId, targetUnitId, abilityId, hitValue, damageType, overflow
LIBCOMBAT_EVENT_DAMAGE_IN = 5				-- LIBCOMBAT_EVENT_DAMAGE_IN, timems, result, sourceUnitId, targetUnitId, abilityId, hitValue, damageType, overflow
LIBCOMBAT_EVENT_DAMAGE_SELF = 6				-- LIBCOMBAT_EVENT_DAMAGE_SELF, timems, result, sourceUnitId, targetUnitId, abilityId, hitValue, damageType, overflow
LIBCOMBAT_EVENT_HEAL_OUT = 7				-- LIBCOMBAT_EVENT_HEAL_OUT, timems, result, sourceUnitId, targetUnitId, abilityId, hitValue, damageType, overflow
LIBCOMBAT_EVENT_HEAL_IN = 8					-- LIBCOMBAT_EVENT_HEAL_IN, timems, result, sourceUnitId, targetUnitId, abilityId, hitValue, damageType, overflow
LIBCOMBAT_EVENT_HEAL_SELF = 9				-- LIBCOMBAT_EVENT_HEAL_SELF, timems, result, sourceUnitId, targetUnitId, abilityId, hitValue, damageType, overflow
LIBCOMBAT_EVENT_EFFECTS_IN = 10				-- LIBCOMBAT_EVENT_EFFECTS_IN, timems, unitId, abilityId, changeType, effectType, stacks, sourceType, effectSlot
LIBCOMBAT_EVENT_EFFECTS_OUT = 11			-- LIBCOMBAT_EVENT_EFFECTS_OUT, timems, unitId, abilityId, changeType, effectType, stacks, sourceType, effectSlot
LIBCOMBAT_EVENT_GROUPEFFECTS_IN = 12		-- LIBCOMBAT_EVENT_GROUPEFFECTS_IN, timems, unitId, abilityId, changeType, effectType, stacks, sourceType, effectSlot
LIBCOMBAT_EVENT_GROUPEFFECTS_OUT = 13		-- LIBCOMBAT_EVENT_GROUPEFFECTS_OUT, timems, unitId, abilityId, changeType, effectType, stacks, sourceType, effectSlot
LIBCOMBAT_EVENT_PLAYERSTATS = 14			-- LIBCOMBAT_EVENT_PLAYERSTATS, timems, statchange, newvalue, statId
LIBCOMBAT_EVENT_RESOURCES = 15				-- LIBCOMBAT_EVENT_RESOURCES, timems, abilityId, powerValueChange, powerType, powerValue
LIBCOMBAT_EVENT_MESSAGES = 16				-- LIBCOMBAT_EVENT_MESSAGES, timems, combatMessage, value
LIBCOMBAT_EVENT_DEATH = 17					-- LIBCOMBAT_EVENT_DEATH, timems, state, unitId, abilityId/unitId
LIBCOMBAT_EVENT_PLAYERSTATS_ADVANCED = 18	-- LIBCOMBAT_EVENT_PLAYERSTATS_ADVANCED, timems, statchange, newvalue, statId
LIBCOMBAT_EVENT_SKILL_TIMINGS = 19			-- LIBCOMBAT_EVENT_SKILL_TIMINGS, timems, reducedslot, abilityId, skillStatus, skillDelay
LIBCOMBAT_EVENT_BOSSHP = 20					-- LIBCOMBAT_EVENT_BOSSHP, timems, bossId, currenthp, maxhp
LIBCOMBAT_EVENT_PERFORMANCE = 21			-- LIBCOMBAT_EVENT_PERFORMANCE, timems, avg, min, max, ping
LIBCOMBAT_EVENT_DEATHRECAP = 22				-- LIBCOMBAT_EVENT_DEATHRECAP, timems, {data}
LIBCOMBAT_EVENT_MAX = 22

LIBCOMBAT_STATE_DEAD = 1
LIBCOMBAT_STATE_ALIVE = 2
LIBCOMBAT_STATE_RESURRECTING = 3
LIBCOMBAT_STATE_RESURRECTED = 4

local CallbackKeys = {}

for i = LIBCOMBAT_EVENT_MIN, LIBCOMBAT_EVENT_MAX do

	CallbackKeys[i] = "LibCombat" .. i

end

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

-- CP type

LIBCOMBAT_CPTYPE_PASSIVE = 0
LIBCOMBAT_CPTYPE_UNSLOTTED = 1
LIBCOMBAT_CPTYPE_SLOTTED = 2

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
	71107,  -- Briarheart

}


local SpecialDebuffs = {   -- debuffs that the API doesn't show via EVENT_EFFECT_CHANGED and need to be specially tracked via EVENT_COMBAT_EVENT

	95136,  -- Chilled (used for tracking Warden crit damage buff)

}

local SourceBuggedBuffs = {   -- buffs where ZOS messed up the source, causing CMX to falsely not track them

	88401,  -- Minor Magickasteal

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

}

local abilityAdditions = { -- Abilities to register additionally because they change in fight

	[61902] = 61907,    -- Grim Focus --> Assasins Will
	[61919] = 61930,    -- Merciless Resolve --> Assasins Will
	[61927] = 61932,    -- Relentless Focus --> Assasins Scourge
	[46324] = 114716,  	-- Crystal Fragments Proc

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

}

local CustomAbilityIcon = {

	[0] = "esoui/art/icons/achievement_wrothgar_046.dds"

}

local AbilityNameCache = {}

local function GetFormattedAbilityName(id)

	if id == nil then return "" end

	local name = AbilityNameCache[id]

	if name == nil then

		name = CustomAbilityName[id] or zo_strformat(SI_ABILITY_NAME, GetAbilityName(id))
		if name == "Off-Balance" then name = "Off Balance" end
		AbilityNameCache[id] = name

	end

	return name

end

lib.GetFormattedAbilityName = GetFormattedAbilityName

local AbilityIconCache = {}

local function GetFormattedAbilityIcon(id)

	if id == nil then return
	elseif type(id) == "string" then return id end

	local icon = AbilityIconCache[id]

	if icon == nil then

		icon = CustomAbilityIcon[id] or GetAbilityIcon(id)
		AbilityIconCache[id] = icon

	end

	return icon

end

lib.GetFormattedAbilityIcon = GetFormattedAbilityIcon

local UnitHandler = ZO_Object:Subclass()

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

local FightHandler = ZO_Object:Subclass()

function FightHandler:New(...)
    local object = ZO_Object.New(self)
    object:Initialize(...)
    return object
end

function FightHandler:Initialize()
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
	self.special = {}
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

local function GetShadowBonus(effectSlot)

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

	local calcBonus =  mathfloor(11 * (1 + totalBonus/100))
	local ZOSBonus = tonumber(ZOSBonusString) or 0 -- value attributed by ZOS

	data.critBonusMundus = calcBonus - ZOSBonus -- mundus bonus difference

	Print("other", LOG_LEVEL_INFO, "Shadow Mundus Offset: %d%% (calc %d%% - ZOS %d%%)", data.critBonusMundus, calcBonus, ZOSBonus)
end

local function GetGlacialPresence()

	if GetUnitClassId("player") ~= 4 then return 0 end

	local skillDataTable = SKILLS_DATA_MANAGER.abilityIdToProgressionDataMap
	local skillData = skillDataTable and skillDataTable[86192] and skillDataTable[86192].skillData

	local rank = skillData.currentRank	-- Glacial Presence
	local purchased = skillData.isPurchased	-- Glacial Presence

	local bonus = purchased and rank or 0

	return bonus * 0.5
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

		Print("events", LOG_LEVEL_VERBOSE, "player has the %s %d x %s (%d, ET: %d, self: %s)", effectType == BUFF_EFFECT_TYPE_BUFF and "buff" or "debuff", stackCount, GetFormattedAbilityName(abilityId), abilityId, abilityType, tostring(castByPlayer))

		local unitType = castByPlayer and COMBAT_UNIT_TYPE_PLAYER or COMBAT_UNIT_TYPE_NONE

		local stacks = mathmax(stackCount,1)

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

	for _, unit in pairs(EffectBuffer) do

		for id, ability in pairs(unit) do

			local endTime, logdata = unpack(ability)

			logdata[2] = newtime

			lib.cm:FireCallbacks((CallbackKeys[logdata[1]]), unpack(logdata))

		end
	end

	EffectBuffer = {}
end

local function GetCritBonusFromCP(CPdata)

	local slots = CPdata[1].slotted
	local points = CPdata[1].stars

	local backstabber = slots[31] and (3 * math.floor(0.1 * points[31][1])) or 0 -- Backstabber 3% per every full 10 points (flanking!)

	return backstabber
end

local function GetCurrentCP()

	local CP = {}

	CP.version = 2

	-- collect slotted stars

	local championBarData = CHAMPION_PERKS.championBar.slots

	local slotsById = {}

	for i, slot in pairs(championBarData) do

		local slotData = slot:GetSavedChampionSkillData()

		if slotData then

			local starId = slotData:GetId()

			slotsById[starId] = i
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

local function GetCurrentSkillBars()

	local skillBars = data.skillBars

	local bar = data.bar

	skillBars[bar] = {}

	local currentbar = skillBars[bar]

	for i = 1, 8 do

		local id = GetSlotBoundId(i)

		currentbar[i] = id

		local reducedslot = (bar - 1) * 10 + i

		local conversion = abilityConversions[id]

		local convertedId = conversion and conversion[1] or id

		IdToReducedSlot[convertedId] = reducedslot

		if conversion and conversion[3] then IdToReducedSlot[conversion[3]] = reducedslot end

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

function FightHandler:PrepareFight()

	local timems = GetGameTimeMilliseconds()

	if self.prepared ~= true then

		self.combatstart = timems

		PurgeEffectBuffer(timems)

		self.date = GetTimeStamp()
		self.time = GetTimeString()
		self.zone = GetPlayerActiveZoneName()
		self.subzone = GetPlayerActiveSubzoneName()
		self.zoneId = GetUnitWorldPosition("player")
		self.ESOversion = GetESOVersionString()
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

		data.resources[POWERTYPE_HEALTH] = GetUnitPower("player", POWERTYPE_HEALTH)
		data.resources[POWERTYPE_MAGICKA] = GetUnitPower("player", POWERTYPE_MAGICKA)
		data.resources[POWERTYPE_STAMINA] = GetUnitPower("player", POWERTYPE_STAMINA)
		data.resources[POWERTYPE_ULTIMATE] = GetUnitPower("player", POWERTYPE_ULTIMATE)

		data.backstabber = GetCritBonusFromCP(self.CP)
		self.special.glacial = GetGlacialPresence()

		self.prepared = true

		self.startBar = data.bar

		data.stats = {}
		data.advancedStats = {}
		self:GetNewStats(timems)

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

local function GetSkillBars()

	local currentSkillBars = {}

	ZO_DeepTableCopy(data.skillBars, currentSkillBars)

	return currentSkillBars

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

	charData.skillBars = GetSkillBars()
	charData.equip = GetEquip()

	local timems = GetGameTimeMilliseconds()
	self.combatend = timems
	self.combattime = zo_round((timems - self.combatstart)/10)/100

	self.starttime = mathmin(self.dpsstart or self.hpsstart or 0, self.hpsstart or self.dpsstart or 0)
	self.endtime = mathmax(self.dpsend or 0, self.hpsend or 0)
	self.activetime = mathmax((self.endtime - self.starttime) / 1000, 1)

	EffectBuffer = {}

	lastAbilityActivations = {}
	isProjectile = {}

	Print("other", LOG_LEVEL_DEBUG, "Number of Projectile data entries: %d", NonContiguousCount(isProjectile))

	data.lastabilities = {}
end

local function GetStat(stat) -- helper function to make code shorter
	return GetPlayerStat(stat, STAT_BONUS_OPTION_APPLY_BONUS)
end

local TFSBonus = 0

local function GetCritbonus()

	local _, _, valueFromZos = GetAdvancedStatValue(ADVANCED_STAT_DISPLAY_TYPE_CRITICAL_DAMAGE)
	local total2 = 50 + valueFromZos + data.backstabber + data.critBonusMundus

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

local function GetStats()

	local weaponcritbonus, spellcritbonus = GetCritbonus()
	local maxcrit = mathfloor(100/GetCriticalStrikeChance(1)) -- Critical Strike chance of 100%

	statData[LIBCOMBAT_STAT_MAXMAGICKA]			= GetStat(STAT_MAGICKA_MAX)
	statData[LIBCOMBAT_STAT_SPELLPOWER]			= GetStat(STAT_SPELL_POWER)
	statData[LIBCOMBAT_STAT_SPELLCRIT]			= mathmin(GetStat(STAT_SPELL_CRITICAL), maxcrit)
	statData[LIBCOMBAT_STAT_SPELLCRITBONUS]		= spellcritbonus
	statData[LIBCOMBAT_STAT_SPELLPENETRATION]	= GetStat(STAT_SPELL_PENETRATION)

	statData[LIBCOMBAT_STAT_MAXSTAMINA]			= GetStat(STAT_STAMINA_MAX)
	statData[LIBCOMBAT_STAT_WEAPONPOWER]		= GetStat(STAT_POWER)
	statData[LIBCOMBAT_STAT_WEAPONCRIT]			= mathmin(GetStat(STAT_CRITICAL_STRIKE), maxcrit)
	statData[LIBCOMBAT_STAT_WEAPONCRITBONUS]	= weaponcritbonus
	statData[LIBCOMBAT_STAT_WEAPONPENETRATION]	= GetStat(STAT_PHYSICAL_PENETRATION) + TFSBonus

	statData[LIBCOMBAT_STAT_MAXHEALTH]			= GetStat(STAT_HEALTH_MAX)
	statData[LIBCOMBAT_STAT_PHYSICALRESISTANCE]	= GetStat(STAT_PHYSICAL_RESIST)
	statData[LIBCOMBAT_STAT_SPELLRESISTANCE]	= GetStat(STAT_SPELL_RESIST)
	statData[LIBCOMBAT_STAT_CRITICALRESISTANCE]	= GetStat(STAT_CRITICAL_RESISTANCE)

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

local function GetAdvancedStats()

	if true then return {} end

	for statType, _ in pairs(advancedStatData) do

		local _, flatValue, percentValue = GetAdvancedStatValue(statType)

		if flatValue then advancedStatData[statType][1] = flatValue end
		if percentValue then advancedStatData[statType][2] = percentValue end

	end

	return advancedStatData
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

			lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_PLAYERSTATS]), LIBCOMBAT_EVENT_PLAYERSTATS, timems, delta, newValue, statId)

			stats[statId] = newValue

		end
	end

	if Events.AdvancedStats.active ~= true then return end

	local advancedStats = data.advancedStats

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

			Print("debug", LOG_LEVEL_INFO, "ProcessDeath: %s (%d)", currentfight.units[unitId].name, unitId)
			UnitCache:ProcessDeath()

		end

	end

end

local function ClearUnitCaches()

	Print("debug", LOG_LEVEL_INFO, "ClearUnitCaches (%d)", NonContiguousCount(CombatEventCache))

	for unitId, UnitCache in pairs(CombatEventCache) do

		CombatEventCache[unitId] = nil

	end

	UnitDeathsToProcess = {}

end

function FightHandler:UpdateStats()

	ProcessDeathRecaps()

	if (self.dpsend == nil and self.hpsend == nil) or (self.dpsstart == nil and self.hpsstart == nil) then return end

	local dpstime = mathmax(((self.dpsend or 1) - (self.dpsstart or 0)) / 1000, 1)
	local hpstime = mathmax(((self.hpsend or 1) - (self.hpsstart or 0)) / 1000, 1)

	self.dpstime = dpstime
	self.hpstime = hpstime

	self:UpdateGrpStats()

	self.DPSOut = mathfloor(self.damageOutTotal / dpstime + 0.5)
	self.HPSOut = mathfloor(self.healingOutTotal / hpstime + 0.5)
	self.HPSAOut = mathfloor(self.healingOutAbsolute / hpstime + 0.5)
	self.DPSIn = mathfloor(self.damageInTotal / dpstime + 0.5)
	self.HPSIn = mathfloor(self.healingInTotal / hpstime + 0.5)

	local data = {
		["DPSOut"] = self.DPSOut,
		["DPSIn"] = self.DPSIn,
		["HPSOut"] = self.HPSOut,
		["HPSAOut"] = self.HPSAOut,
		["HPSIn"] = self.HPSIn,
		["healingOutTotal"] = self.healingOutTotal,
		["dpstime"] = dpstime,
		["hpstime"] = hpstime,
		["bossfight"] = self.bossfight,
	}

	lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_UNITS]), LIBCOMBAT_EVENT_UNITS, self.units)
	lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_FIGHTRECAP]), LIBCOMBAT_EVENT_FIGHTRECAP, data)

end

function FightHandler:UpdateGrpStats() -- called by onUpdate

	if not (data.inGroup and Events.CombatGrp.active) then return end

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

	self.groupDPSOut = mathfloor(self.groupDamageOut / dpstime + 0.5)
	self.groupDPSIn = mathfloor(self.groupDamageIn / dpstime + 0.5)
	self.groupHPSOut = mathfloor(self.groupHealingOut / hpstime + 0.5)

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

		Print("other", LOG_LEVEL_DEBUG, "Prevented combat reset because player is in Portal!")
		return true

	elseif getCurrentBossHP() > 0 and getCurrentBossHP() < 1 then

		Print("other", LOG_LEVEL_INFO, "Prevented combat reset because boss is still in fight!")
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

			Print("fight", LOG_LEVEL_DEBUG, "Time: %.2fs (DPS) | %.2fs (HPS) ", self.dpstime, self.hpstime)
			Print("fight", LOG_LEVEL_DEBUG, "Dmg: %d (DPS: %d)", self.damageOutTotal, self.DPSOut)
			Print("fight", LOG_LEVEL_DEBUG, "Heal: %d (HPS: %d)", self.healingOutTotal, self.HPSOut)
			Print("fight", LOG_LEVEL_DEBUG, "IncDmg: %d (Shield: %d, IncDPS: %d)", self.damageInTotal, self.damageInShielded, self.DPSIn)
			Print("fight", LOG_LEVEL_DEBUG, "IncHeal: %d (IncHPS: %d)", self.healingInTotal, self.HPSIn)

			if data.inGroup and Events.CombatGrp.active then

				Print("fight", LOG_LEVEL_DEBUG, "GrpDmg: %d (DPS: %d)", self.groupDamageOut, self.groupDPSOut)
				Print("fight", LOG_LEVEL_DEBUG, "GrpHeal: %d (HPS: %d)", self.groupHealingOut, self.groupHPSOut)
				Print("fight", LOG_LEVEL_DEBUG, "GrpIncDmg: %d (IncDPS: %d)", self.groupDamageIn, self.groupDPSIn)

			end
		end

		Print("fight", LOG_LEVEL_DEBUG, "resetting...")

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

	Print("debug", LOG_LEVEL_INFO, "Init UnitCache: %s (%d)", unitname, unitId)

end

function UnitCacheHandler:OnDeath(timems)

	self.timems = timems

	UnitDeathsToProcess[self.unitId] = self

	if not lib.debug then return end

	local unitname = currentfight.units[self.unitId] and currentfight.units[self.unitId].name or "Unknown"

	Print("debug", LOG_LEVEL_INFO, "UnitCacheHandler:OnDeath: %s (%d)", unitname, self.unitId)

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

		Print("debug", LOG_LEVEL_INFO, "Processing death event cache. Offset: %d, length:%d", offset, length)

		for i = 0, length - 1 do

			local cachekey = (i + offset)%length + 1
			local data = cache[cachekey]

			if timems - data[1] < deathRecapTimePeriod then

				log[#log + 1] = data
				local sourceUnitId = data[3]
				local sourceUnit = sourceUnitId and sourceUnitId>0 and currentfight.units[sourceUnitId] or "nil"

				data[3] = (sourceUnit and sourceUnit.name) or "Unknown"

				if data[10] and data[10] > self.magickaMax then self.magickaMax = data[10] end
				if data[11] and data[11] > self.staminaMax then self.staminaMax = data[11] end

			else

				deleted = deleted + 1

			end
		end

		Print("debug", LOG_LEVEL_INFO , "%s: cache: %d, log: %d, deleted: %d", unit and unit.name or "Unknown", #cache, #log, deleted)
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

		self.health, self.healthMax = GetUnitPower(unitTag, POWERTYPE_HEALTH)

		if unitTag == "player" then

			self.magicka = GetUnitPower(unitTag, POWERTYPE_MAGICKA)
			self.stamina = GetUnitPower(unitTag, POWERTYPE_STAMINA)

		end
	end
end

function UnitCacheHandler:UpdateResource(powerType, value, powerMax)

	if powerType == POWERTYPE_HEALTH then

		self.health = value
		self.healthMax = powerMax > 0 and powerMax or self.healthMax or 0

	elseif powerType == POWERTYPE_STAMINA then

		self.stamina = value
		self.staminaMax = powerMax > 0 and powerMax or self.staminaMax or 0

	elseif powerType == POWERTYPE_MAGICKA then

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

			Print("fight", LOG_LEVEL_DEBUG, "Entering combat.")

			lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_MESSAGES]), LIBCOMBAT_EVENT_MESSAGES, timems, LIBCOMBAT_MESSAGE_COMBATSTART, 0)

			currentfight:PrepareFight()

		else

			if IsOngoingBossfight() then

				Print("fight", LOG_LEVEL_INFO, "Failed: Leaving combat.")
				return

			end

			data.inCombat = false

			Print("fight", LOG_LEVEL_DEBUG, "Leaving combat.")

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

local function AddtoEffectBuffer(endTime, eventid, timems, unitId, abilityId, ...)

	local data = {endTime, {eventid, timems, unitId, abilityId, ...}}

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

local function onAlkoshDmg(_, _, _, _, _, _, _, _, _, _, hitValue, _, _, _, _, targetUnitId, _, overflow)	-- inactive

	local fullValue = hitValue + (overflow or 0)

	Print("events", LOG_LEVEL_DEBUG, "Alkosh Dmg: %d", fullValue)

	AlkoshData[targetUnitId] = math.min(fullValue, 3000)

end

local function onTrialDummy(_, _, _, _, _, _, _, _, _, _, _, _, _, _, sourceUnitId, _, _, _)

	-- Print("debug", LOG_LEVEL_INFO, "Trial Dummy Detected: %s (%d)", sourceName, sourceUnitId)

	if not currentfight.prepared then return end

	local unit = currentfight.units[sourceUnitId]

	if unit then unit.isTrialDummy = true end

end

local function BuffEventHandler(isspecial, groupeffect, _, changeType, effectSlot, _, unitTag, _, endTime, stackCount, _, _, effectType, abilityType, _, unitName, unitId, abilityId, sourceType)

	if (changeType ~= EFFECT_RESULT_GAINED and changeType ~= EFFECT_RESULT_FADED and not (changeType == EFFECT_RESULT_UPDATED and stackCount > 1)) or unitName == "Offline" or unitId == nil then return end

	Print("events", LOG_LEVEL_VERBOSE, "%s %s the %s %dx %s (%d, ET: %d, %s, %d)", unitName, changeType, effectType == BUFF_EFFECT_TYPE_BUFF and "buff" or "debuff", stackCount, GetFormattedAbilityName(abilityId), abilityId, abilityType, unitTag, sourceType)

	if BadAbility[abilityId] == true then return end

	if unitTag and stringsub(unitTag, 1, 5) == "group" and AreUnitsEqual(unitTag, "player") then return end
	if unitTag and stringsub(unitTag, 1, 11) ~= "reticleover" and (AreUnitsEqual(unitTag, "reticleover") or AreUnitsEqual(unitTag, "reticleoverplayer") or AreUnitsEqual(unitTag, "reticleovertarget")) then return end

	local timems = GetGameTimeMilliseconds()

	local eventid = groupeffect == GROUP_EFFECT_IN and LIBCOMBAT_EVENT_GROUPEFFECTS_IN or groupeffect == GROUP_EFFECT_OUT and LIBCOMBAT_EVENT_GROUPEFFECTS_OUT or stringsub(unitTag, 1, 6) == "player" and LIBCOMBAT_EVENT_EFFECTS_IN or LIBCOMBAT_EVENT_EFFECTS_OUT
	local stacks = (isspecial and 0) or mathmax(1, stackCount)

	local inCombat = currentfight.prepared

	-- local hitValue = (abilityId == 75753 and changeType == EFFECT_RESULT_GAINED and AlkoshData[unitId]) or nil

	if inCombat ~= true and unitTag ~= "player" and (changeType == EFFECT_RESULT_GAINED or changeType == EFFECT_RESULT_UPDATED) then

		AddtoEffectBuffer(endTime, eventid, timems, unitId, abilityId, changeType, effectType, stacks, sourceType, effectSlot, hitValue)	-- hitValue is Alkosh only for now
		return

	elseif inCombat == true then

		local unit = currentfight.units[unitId]

		if unit then

			unit.starttime = unit.starttime or timems
			unit.endtime = timems

		end

		if unitTag == "player" then currentfight:GetNewStats(timems) end
		lib.cm:FireCallbacks((CallbackKeys[eventid]), eventid, timems, unitId, abilityId, changeType, effectType, stacks, sourceType, effectSlot)

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

local function SpecialBuffEventHandler(isdebuff, _, result, _, _, _, _, _, sourceType, unitName, targetType, _, _, damageType, _, _, unitId, abilityId)

	if BadAbility[abilityId] == true then return end

	-- if unitName ~= data.rawPlayername then return end
	
	local changeType = result == ACTION_RESULT_EFFECT_GAINED_DURATION and 1 or result == ACTION_RESULT_EFFECT_FADED and 2 or nil
	-- Print("debug", LOG_LEVEL_INFO, "%s (%d): %d (%d)", GetFormattedAbilityName(abilityId), abilityId, changeType, result)

	local effectType = isdebuff and BUFF_EFFECT_TYPE_DEBUFF or BUFF_EFFECT_TYPE_BUFF
	BuffEventHandler(true, GROUP_EFFECT_NONE, _, changeType, 0, _, _, _, _, _, _, _, effectType, ABILITY_TYPE_BONUS, _, unitName, unitId, abilityId, sourceType)

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

local function checkLastAbilities(powerType, powerValueChange)

	local lastabilities = data.lastabilities

	local aId = -1

	for i = #lastabilities, 1, -1 do

		local values = lastabilities[i]

		if powerType == values[4] then

			local ratio = powerValueChange / values[3]

			local goodratio = ratio >= 0.98 and ratio <= 1.06

			if goodratio then

				-- if values[3] < 0 then df("Ratio: %.3f (**%s: %d vs. %d) %d", ratio, GetFormattedAbilityName(values[2]), values[3], powerValueChange, #lastabilities-i) end

				aId = values[2]
				table.remove(lastabilities, i)

				break

			end

			-- if i == #lastabilities and values[3] < 0 then df("Ratio: %.3f (%s: %d vs. %d)", ratio, GetFormattedAbilityName(values[2]), values[3], powerValueChange) end
		end
	end

	return aId

end

local function onBaseResourceChanged(_,unitTag,_,powerType,powerValue,_,_)

	if unitTag ~= "player" then return end
	if (powerType ~= POWERTYPE_HEALTH and powerType ~= POWERTYPE_MAGICKA and powerType ~= POWERTYPE_STAMINA and powerType ~= POWERTYPE_ULTIMATE) or (data.inCombat == false) then return end

	local timems = GetGameTimeMilliseconds()
	local aId

	local powerValueChange = powerValue - (data.resources[powerType] or powerValue)
	data.resources[powerType] = powerValue

	if powerValueChange == 0 then return end

 	if powerType == POWERTYPE_MAGICKA then

		Print("events", LOG_LEVEL_VERBOSE, "Skill cost: %d", powerValueChange)

		aId = checkLastAbilities(powerType, powerValueChange)

		if aId == -1 and powerValueChange == GetStat(STAT_MAGICKA_REGEN_COMBAT) then

			aId = 0

		end

	elseif powerType == POWERTYPE_STAMINA then

		aId = checkLastAbilities(powerType, powerValueChange)

		if powerValueChange == GetStat(STAT_STAMINA_REGEN_COMBAT) and aId == -1 then

			aId = 0

		elseif aId == -1 then

			local bashratio = -GetAbilityCost(21970) * 5/3 / powerValueChange
			local dodgeratio = -GetAbilityCost(28549) / powerValueChange

			local goodbashratio = bashratio >= 0.98 and bashratio <= 1.02
			local gooddodgeratio = dodgeratio >= 0.98 and dodgeratio <= 1.02

			if goodbashratio then

				aId = 21970

			elseif gooddodgeratio then

				aId = 28549

			end
		end

	elseif powerType == POWERTYPE_ULTIMATE then

		aId = 0

	elseif powerType == POWERTYPE_HEALTH then

		aId = -1

		if powerValueChange == GetStat(STAT_HEALTH_REGEN_COMBAT) and data.playerid then

			aId = 0

			lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_HEAL_SELF]), LIBCOMBAT_EVENT_HEAL_SELF, timems, ACTION_RESULT_HOT_TICK, data.playerid, data.playerid, aId, powerValueChange, powerType, 0)
			return

		end
	end

	lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_RESOURCES]), LIBCOMBAT_EVENT_RESOURCES, timems, aId, powerValueChange, powerType, powerValue)
end

--(eventCode, result, isError, abilityName, abilityGraphic, abilityActionSlotType, sourceName, sourceType, targetName, targetType, hitValue, powerType, damageType, log, sourceUnitId, targetUnitId, abilityId)
local function onResourceChanged (_, result, _, _, _, _, _, _, targetName, _, powerValueChange, powerType, _, _, sourceUnitId, targetUnitId, abilityId)

	local lastabilities = data.lastabilities

	if data.playerid == nil and targetName == data.rawPlayername then data.playerid = targetUnitId end

	local timems = GetGameTimeMilliseconds()

	if (powerType ~= 0 and powerType ~= 6) or data.inCombat == false or powerValueChange < 1 then return end

	if result == ACTION_RESULT_POWER_DRAIN then powerValueChange = -powerValueChange end

	table.insert(lastabilities,{timems, abilityId, powerValueChange, powerType})

	if #lastabilities > 10 then table.remove(lastabilities, 1) end
end

local function onWeaponSwap(_, isHotbarSwap)

	local newbar = ACTION_BAR_ASSIGNMENT_MANAGER.currentHotbarCategory + 1

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

	Print("DoA", LOG_LEVEL_DEBUG, "=== This is a wipe ! ===")

end

local function OnDeathStateChanged(_, unitTag, isDead) 	-- death (for group display, also works for different zones)

	local unitId = unitTag == "player" and data.playerid or data.groupInfo.tagToId[unitTag]

	Print("debug", LOG_LEVEL_INFO, "OnDeathStateChanged: %s (%s) is dead: %s", unitTag, tostring(unitId), tostring(isDead))

	if data.inCombat == false or unitId == nil then

		Print("debug", LOG_LEVEL_INFO, "OnDeathStateChanged: Combat: %s", tostring(data.inCombat))
		return
	end

	local unit = currentfight.units[unitId]
	if unit then unit.isDead = isDead else

		Print("debug", LOG_LEVEL_INFO, "OnDeathStateChanged: no unit")
		return
	end

	local timems = GetGameTimeMilliseconds()

	if isDead then

		local lasttime = lastdeaths[unitId]

		if (lasttime and lasttime - timems < 1000) then return end

		GetUnitCache(unitId):OnDeath(timems)

		Print("debug", LOG_LEVEL_INFO, "OnDeathStateChanged: fire callback")
		lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_DEATH]), LIBCOMBAT_EVENT_DEATH, timems, LIBCOMBAT_STATE_DEAD, unitId)

		CheckForWipe()

	else

		lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_DEATH]), LIBCOMBAT_EVENT_DEATH, timems, LIBCOMBAT_STATE_ALIVE, unitId)

	end
end

local function OnPlayerReincarnated()

	Print("DoA", LOG_LEVEL_DEBUG, "You revived")

end

local SpecialResults = {

	[ACTION_RESULT_ABSORBED]		= "ACTION_RESULT_ABSORBED",
	[ACTION_RESULT_BLADETURN]		= "ACTION_RESULT_BLADETURN",
	[ACTION_RESULT_BLOCKED_DAMAGE]	= "ACTION_RESULT_BLOCKED_DAMAGE",
	[ACTION_RESULT_DIED] 	    	= "ACTION_RESULT_DIED",
	[ACTION_RESULT_DIED_XP] 	    = "ACTION_RESULT_DIED_XP",
	[ACTION_RESULT_KILLING_BLOW] 	= "ACTION_RESULT_KILLING_BLOW",
	[ACTION_RESULT_LINKED_CAST] 	= "ACTION_RESULT_LINKED_CAST",
	[ACTION_RESULT_PARTIAL_RESIST] 	= "ACTION_RESULT_PARTIAL_RESIST",
	[ACTION_RESULT_PRECISE_DAMAGE] 	= "ACTION_RESULT_PRECISE_DAMAGE",
	[ACTION_RESULT_REFLECTED] 		= "ACTION_RESULT_REFLECTED",
	[ACTION_RESULT_REINCARNATING] 	= "ACTION_RESULT_REINCARNATING",
	[ACTION_RESULT_RESIST]			= "ACTION_RESULT_RESIST",
	[ACTION_RESULT_RESURRECT] 		= "ACTION_RESULT_RESURRECT",
	[ACTION_RESULT_WRECKING_DAMAGE]	= "ACTION_RESULT_WRECKING_DAMAGE",

}

local function OnDeath(_, result, _, abilityName, _, abilityActionSlotType, sourceName, sourceType, targetName, targetType, hitValue, powerType, damageType, _, sourceUnitId, targetUnitId, abilityId, overflow)

	local timems = GetGameTimeMilliseconds()

	if targetUnitId == nil or targetUnitId == 0 then return end

	local unitdata = currentfight.units[targetUnitId]

	if unitdata == nil or (unitdata.unitType ~= COMBAT_UNIT_TYPE_PLAYER and unitdata.unitType ~= COMBAT_UNIT_TYPE_GROUP) then return end

	Print("debug", LOG_LEVEL_INFO, "OnDeath (%s): %s (%d, %d) / %s (%d, %d) - %s (%d): %d (o: %d, type: %d)", SpecialResults[result], sourceName, sourceUnitId, sourceType, targetName, targetUnitId, targetType, GetFormattedAbilityName(abilityId), abilityId, hitValue or 0, overflow or 0, damageType or 0)

	lastdeaths[targetUnitId] = timems

	GetUnitCache(targetUnitId):OnDeath(timems)

	lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_DEATH]), LIBCOMBAT_EVENT_DEATH, timems, LIBCOMBAT_STATE_DEAD, targetUnitId, abilityId)

	CheckForWipe()
end

local function OnResurrect(_, result, _, abilityName, _, abilityActionSlotType, sourceName, sourceType, targetName, targetType, hitValue, powerType, damageType, _, sourceUnitId, targetUnitId, abilityId)

	Print("debug", LOG_LEVEL_INFO, "OnResurrect (%s): %s (%d, %d) / %s (%d, %d) - %s (%d): %d (type: %d)", SpecialResults[result], sourceName, sourceUnitId, sourceType, targetName, targetUnitId, targetType, GetFormattedAbilityName(abilityId), abilityId, hitValue or 0, damageType or 0)

	local timems = GetGameTimeMilliseconds()

	if targetUnitId == nil or targetUnitId == 0 or data.inCombat == false then return end

	local unitdata = currentfight.units[targetUnitId]

	if unitdata == nil or unitdata.type ~= COMBAT_UNIT_TYPE_GROUP then return end

	lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_DEATH]), LIBCOMBAT_EVENT_DEATH, timems, LIBCOMBAT_STATE_ALIVE, targetUnitId)
end

local function OnResurrectResult(_, targetCharacterName, result, targetDisplayName)

	Print("DoA", LOG_LEVEL_DEBUG, "OnResurrectResult: %s", targetCharacterName)

	local timems = GetGameTimeMilliseconds()

	if result ~= RESURRECT_RESULT_SUCCESS then return end

	local name = ZO_CachedStrFormat(SI_UNIT_NAME, targetCharacterName) or ""

	local unitId = data.groupInfo.nameToId[name]

	if not unitId then return end

	lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_DEATH]), LIBCOMBAT_EVENT_DEATH, timems, LIBCOMBAT_STATE_RESURRECTED, unitId, data.playerid)

end

local function OnResurrectRequest(_, requesterCharacterName, timeLeftToAccept, requesterDisplayName)

	Print("DoA", LOG_LEVEL_DEBUG, "OnResurrectRequest: %s", requesterCharacterName)

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

	Print("other", LOG_LEVEL_VERBOSE, "onWTF (%s): %s (%d, %d) / %s (%d, %d) - %s (%d): %d (type: %d)", resulttext, sourceName, sourceUnitId, sourceType, targetName, targetUnitId, targetType, GetFormattedAbilityName(abilityId), abilityId, hitValue or 0, damageType or 0)

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

		Print("debug", LOG_LEVEL_VERBOSE, "Eval Shield Index %d: Source: %s, Target: %s, Time: %d", i, tostring(shieldSourceUnitId == sourceUnitId), tostring(shieldTargetUnitId == targetUnitId), timems - shieldTimems)

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

	Print("debug", LOG_LEVEL_DEBUG, "Add %d Shield: %d -> %d  (%d)", hitValue, sourceUnitId, targetUnitId, #DamageShieldBuffer)

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

		Print("debug", LOG_LEVEL_WARNING, "Big Damage Event: (%d) %s did %d damage to %s", abilityId, GetFormattedAbilityName(abilityId), hitValue, tostring(targetName))

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

		Print("debug", LOG_LEVEL_INFO, "GroupCombatEventHandler: %s has overflow damage!", targetName)
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

	local bar = mathfloor(reducedslot/10) + 1

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

	local channeled, castTime, channelTime = GetAbilityCastInfo(origId)

	castTime = channeled and channelTime or castTime

	Print("events", LOG_LEVEL_VERBOSE, "[%.3f] Skill fired: %s (%d), Duration: %ds Target: %s", timems/1000, GetAbilityName(origId), origId, castTime/1000, tostring(targetName))

	HeavyAttackCharging = DirectHeavyAttacks[origId] and origId or nil

	local lastQ = lastQueuedAbilities[origId]
	lastQueuedAbilities[origId] = nil

	if lastQ and lasttime then

		Print("events", LOG_LEVEL_VERBOSE, "%s: act: %d, Q: %d, Diff: %d", GetFormattedAbilityName(origId), timems-lasttime, timems-lastQ, lastQ - lasttime)

	end

	local skillExecution = lastQ and math.max(lastQ, lasttime) or lasttime
	local skillDelay = timems - skillExecution

	skillDelay = skillDelay < maxSkillDelay and skillDelay or nil

	if castTime > 0 then

		local status = channeled and LIBCOMBAT_SKILLSTATUS_BEGIN_CHANNEL or LIBCOMBAT_SKILLSTATUS_BEGIN_DURATION

		lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_SKILL_TIMINGS]), LIBCOMBAT_EVENT_SKILL_TIMINGS, timems, reducedslot, origId, status, skillDelay)

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

		Print("events", LOG_LEVEL_VERBOSE ,"Skill finished: %s (%d, R: %d)", GetAbilityName(origId), origId, result)

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

		Print("events", LOG_LEVEL_WARNING ,"reducedslot missing on queue event: [%.3f s] %s (%d)", (timems - currentfight.combatstart)/1000, GetAbilityName(abilityId), abilityId)
		return

	end

	lastQueuedAbilities[abilityId] = timems

	lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_SKILL_TIMINGS]), LIBCOMBAT_EVENT_SKILL_TIMINGS, timems, reducedslot, abilityId, LIBCOMBAT_SKILLSTATUS_QUEUE)

end

local function onProjectileEvent(eventCode, result, isError, abilityName, abilityGraphic, abilityActionSlotType, sourceName, sourceType, targetName, targetType, hitValue, powerType, damageType, log, sourceUnitId, targetUnitId, abilityId)

	if hitValue == nil or hitValue <= 1 or targetType == COMBAT_UNIT_TYPE_PLAYER or isProjectile[abilityId] == true then return end

	isProjectile[abilityId] = true

	Print("events", LOG_LEVEL_VERBOSE ,"[%.3f s] projectile: %s (%d)", (GetGameTimeMilliseconds() - currentfight.combatstart)/1000, GetAbilityName(abilityId), abilityId)

	-- if IdToReducedSlot[abilityId] then isProjectile[abilityId] = true end TODO: Check if this should be limited

end

local function onSlotUsed(_, slot)

	if data.inCombat == false or slot > 8 then return end

	local timems = GetGameTimeMilliseconds()
	local cost, powerType = GetSlotAbilityCost(slot)
	local abilityId = GetSlotBoundId(slot)
	local lastabilities = data.lastabilities

	if Events.Resources.active and slot > 2 and (powerType == POWERTYPE_HEALTH or powerType == POWERTYPE_MAGICKA or powerType == POWERTYPE_STAMINA) then

		table.insert(lastabilities,{timems, abilityId, -cost, powerType})

		if #lastabilities > 10 then table.remove(lastabilities, 1) end

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

local function onPlayerDeativated()
	em:UnregisterForUpdate("LibCombat_Frames")
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

	local copy = {}

	if currentfight.dpsstart ~= nil then

		ZO_DeepTableCopy(currentfight, copy)

	else

		copy = nil

	end

	return copy
end

local function UpdateSkillEvents(self)

	for _, skill in pairs(SlotSkills) do

		local id, result, id2, result2 = unpack(skill)

		if not registeredSkills[id] then

			Print("events", LOG_LEVEL_VERBOSE, "Skill registered: %d: %s (%s), End:  %d: %s (%s))", id, GetAbilityName(id), tostring(result), id2 or 0, GetAbilityName(id2 or 0), tostring(result2))

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

if GetAPIVersion() > 100027 then EVENT_ACTION_SLOT_ABILITY_SLOTTED = EVENT_HOTBAR_SLOT_CHANGE_REQUESTED end

Events.General = EventHandler:New(GetAllCallbackTypes()
	,
	function (self)
		self:RegisterEvent(EVENT_PLAYER_COMBAT_STATE, onCombatState)
		self:RegisterEvent(EVENT_GROUP_UPDATE, onGroupChange)
		self:RegisterEvent(EVENT_ACTION_SLOT_ABILITY_SLOTTED, GetCurrentSkillBars)
		self:RegisterEvent(EVENT_PLAYER_ACTIVATED, onPlayerActivated)
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onMageExplode, REGISTER_FILTER_ABILITY_ID, 50184)
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onPortalWorld, REGISTER_FILTER_ABILITY_ID, 108045)
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onPortalWorld, REGISTER_FILTER_ABILITY_ID, 121216)

		if lib.debug == true then

			self:RegisterEvent(EVENT_COMBAT_EVENT, onWTF, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_ABSORBED)
			self:RegisterEvent(EVENT_COMBAT_EVENT, onWTF, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_BLADETURN)
			self:RegisterEvent(EVENT_COMBAT_EVENT, onWTF, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_BLOCKED)
			self:RegisterEvent(EVENT_COMBAT_EVENT, onWTF, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_DIED_XP)
			self:RegisterEvent(EVENT_COMBAT_EVENT, onWTF, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_KILLING_BLOW)
			self:RegisterEvent(EVENT_COMBAT_EVENT, onWTF, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_LINKED_CAST)
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

			self:RegisterEvent(EVENT_COMBAT_EVENT, onSpecialBuffEventOnSelf, REGISTER_FILTER_TARGET_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_PLAYER, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_EFFECT_GAINED_DURATION, REGISTER_FILTER_ABILITY_ID, SpecialBuffs[i], REGISTER_FILTER_IS_ERROR, false)
			self:RegisterEvent(EVENT_COMBAT_EVENT, onSpecialBuffEventOnSelf, REGISTER_FILTER_TARGET_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_PLAYER, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_EFFECT_FADED, REGISTER_FILTER_ABILITY_ID, SpecialBuffs[i], REGISTER_FILTER_IS_ERROR, false)
		end

		for i=1,#SpecialDebuffs do
			self:RegisterEvent(EVENT_COMBAT_EVENT, onSpecialDebuffEvent, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_EFFECT_GAINED_DURATION, REGISTER_FILTER_ABILITY_ID, SpecialDebuffs[i], REGISTER_FILTER_IS_ERROR, false)
			self:RegisterEvent(EVENT_COMBAT_EVENT, onSpecialDebuffEvent, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_EFFECT_FADED, REGISTER_FILTER_ABILITY_ID, SpecialDebuffs[i], REGISTER_FILTER_IS_ERROR, false)

			self:RegisterEvent(EVENT_COMBAT_EVENT, onSpecialDebuffEventOnSelf, REGISTER_FILTER_TARGET_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_PLAYER, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_EFFECT_GAINED_DURATION, REGISTER_FILTER_ABILITY_ID, SpecialDebuffs[i], REGISTER_FILTER_IS_ERROR, false)
			self:RegisterEvent(EVENT_COMBAT_EVENT, onSpecialDebuffEventOnSelf, REGISTER_FILTER_TARGET_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_PLAYER, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_EFFECT_FADED, REGISTER_FILTER_ABILITY_ID, SpecialDebuffs[i], REGISTER_FILTER_IS_ERROR, false)
		end

		for i=1,#SourceBuggedBuffs do
			self:RegisterEvent(EVENT_EFFECT_CHANGED, onSourceBuggedEffectChanged, REGISTER_FILTER_ABILITY_ID, SourceBuggedBuffs[i])
		end

		-- self:RegisterEvent(EVENT_COMBAT_EVENT, onAlkoshDmg, REGISTER_FILTER_ABILITY_ID, 75752, REGISTER_FILTER_IS_ERROR, false)
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
		self:RegisterEvent(EVENT_POWER_UPDATE, onBaseResourceChanged, REGISTER_FILTER_UNIT_TAG, "player")
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
		self:RegisterEvent(EVENT_POWER_UPDATE, onBossHealthChanged, REGISTER_FILTER_UNIT_TAG, "boss1", REGISTER_FILTER_POWER_TYPE, POWERTYPE_HEALTH)
		self.active = true
	end
)

Events.Performance = EventHandler:New(
	{LIBCOMBAT_EVENT_PERFORMANCE},
	function (self)
		self:RegisterEvent(EVENT_PLAYER_DEACTIVATED, onPlayerDeativated)
		self:RegisterEvent(EVENT_PLAYER_ACTIVATED, onPlayerActivated2)
		self.active = true
	end
)

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

local logColors={
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

	local format = showIds and "<<5[//$dx ]>><<1>> <<2>><<3>> (<<4>>)|r" or "<<5[//$dx ]>><<1>> <<2>><<3>>|r"

	local abilityString = ZO_CachedStrFormat(format, icon, damageColor, name, showIds and abilityId or nil, stacks)

	return abilityString
end

local UnitTypeString = {
	[COMBAT_UNIT_TYPE_PLAYER] 		= GetString(SI_LIBCOMBAT_LOG_UNITTYPE_PLAYER),
	[COMBAT_UNIT_TYPE_PLAYER_PET] 	= GetString(SI_LIBCOMBAT_LOG_UNITTYPE_PET),
	[COMBAT_UNIT_TYPE_GROUP] 		= GetString(SI_LIBCOMBAT_LOG_UNITTYPE_GROUP),
	[COMBAT_UNIT_TYPE_OTHER] 		= GetString(SI_LIBCOMBAT_LOG_UNITTYPE_OTHER),
}

function lib:GetCombatLogString(fight, logline, fontsize, showIds)

	if fight == nil then fight = currentfight end

	local logtype = logline[1]

	local color, text

	local timeValue = fight.combatstart < 0 and 0 or (logline[2] - fight.combatstart)/1000
	local timeString = stringformat("|ccccccc[%.3fs]|r", timeValue)
	local logFormat = GetString("SI_LIBCOMBAT_LOG_FORMATSTRING", logtype)

	local units = fight.units

	if logtype == LIBCOMBAT_EVENT_DAMAGE_OUT then

		local _, _, result, _, targetUnitId, abilityId, hitValue, damageType, overflow = unpack(logline)

		local crit = (result == ACTION_RESULT_CRITICAL_DAMAGE or result == ACTION_RESULT_DOT_TICK_CRITICAL) and ZO_CachedStrFormat("|cFFCC99<<1>>|r", GetString(SI_LIBCOMBAT_LOG_CRITICAL)) or ""

		local targetname = units[targetUnitId].name
		local targetFormat = (result == ACTION_RESULT_BLOCKED_DAMAGE and SI_LIBCOMBAT_LOG_FORMAT_TARGET_BLOCK) or SI_LIBCOMBAT_LOG_FORMAT_TARGET_NORMAL

		local targetString = ZO_CachedStrFormat(GetString(targetFormat), targetname)

		local ability = GetAbilityString(abilityId, damageType, fontsize, showIds)

		local hitValueString = overflow > 0 and ZO_CachedStrFormat(GetString(SI_LIBCOMBAT_LOG_FORMAT_ABSORBED), hitValue, overflow) or hitValue

		color = {1.0,0.6,0.6}
		text = ZO_CachedStrFormat(logFormat, timeString, crit, targetString, ability, hitValueString)

	elseif logtype == LIBCOMBAT_EVENT_DAMAGE_IN then

		local _, _, result, sourceUnitId, _, abilityId, hitValue, damageType, overflow = unpack(logline)

		local crit = (result == ACTION_RESULT_CRITICAL_DAMAGE or result == ACTION_RESULT_DOT_TICK_CRITICAL) and ZO_CachedStrFormat("|cFFCC99<<1>>|r", GetString(SI_LIBCOMBAT_LOG_CRITICAL)) or ""

		local sourceName = units[sourceUnitId].name

		local targetFormat = (result == ACTION_RESULT_BLOCKED_DAMAGE and SI_LIBCOMBAT_LOG_FORMAT_TARGETSELF_BLOCK) or SI_LIBCOMBAT_LOG_FORMAT_TARGETSELF_NORMAL
		local targetString = GetString(targetFormat)

		local ability = GetAbilityString(abilityId, damageType, fontsize, showIds)

		local hitValueString = overflow > 0 and ZO_CachedStrFormat(GetString(SI_LIBCOMBAT_LOG_FORMAT_ABSORBED), hitValue, overflow) or hitValue

		color = {0.8,0.4,0.4}

		text = ZO_CachedStrFormat(logFormat, timeString, sourceName, crit, targetString, ability, hitValueString)

	elseif logtype == LIBCOMBAT_EVENT_DAMAGE_SELF then

		local _, _, result, _, _, abilityId, hitValue, damageType, overflow = unpack(logline)

		local crit = (result == ACTION_RESULT_CRITICAL_HEAL or result == ACTION_RESULT_HOT_TICK_CRITICAL) and ZO_CachedStrFormat("|cFFCC99<<1>>|r", GetString(SI_LIBCOMBAT_LOG_CRITICAL)) or ""

		local targetFormat = (result == ACTION_RESULT_BLOCKED_DAMAGE and SI_LIBCOMBAT_LOG_FORMAT_TARGETSELF_BLOCK) or SI_LIBCOMBAT_LOG_FORMAT_TARGETSELF_SELF
		local targetString = GetString(targetFormat)

		local ability = GetAbilityString(abilityId, damageType, fontsize)

		local hitValueString = overflow > 0 and ZO_CachedStrFormat(GetString(SI_LIBCOMBAT_LOG_FORMAT_ABSORBED), hitValue, overflow) or hitValue

		color = {0.8,0.4,0.4}
		text = ZO_CachedStrFormat(logFormat, timeString, crit, targetString, ability, hitValueString)

	elseif logtype == LIBCOMBAT_EVENT_HEAL_OUT then

		local _, _, result, _, targetUnitId, abilityId, hitValue, _, overflow = unpack(logline)

		local crit = (result == ACTION_RESULT_CRITICAL_HEAL or result == ACTION_RESULT_HOT_TICK_CRITICAL) and ZO_CachedStrFormat("|cFFCC99<<1>>|r", GetString(SI_LIBCOMBAT_LOG_CRITICAL)) or ""

		local targetname = units[targetUnitId].name

		local ability = GetAbilityString(abilityId, "heal", fontsize, showIds)

		color = {0.6,1.0,0.6}
		text = ZO_CachedStrFormat(logFormat, timeString, crit, targetname, ability, hitValue)

	elseif logtype == LIBCOMBAT_EVENT_HEAL_IN then

		local _, _, result, sourceUnitId, _, abilityId, hitValue, _, overflow  = unpack(logline)

		local crit = (result == ACTION_RESULT_CRITICAL_HEAL or result == ACTION_RESULT_HOT_TICK_CRITICAL) and ZO_CachedStrFormat("|cFFCC99<<1>>|r", GetString(SI_LIBCOMBAT_LOG_CRITICAL)) or ""

		local sourceName = units[sourceUnitId].name

		local ability = GetAbilityString(abilityId, "heal", fontsize, showIds)

		color = {0.4,0.8,0.4}

		text = ZO_CachedStrFormat(logFormat, timeString, sourceName, crit, ability, hitValue)

	elseif logtype == LIBCOMBAT_EVENT_HEAL_SELF then

		local _, _, result, _, _, abilityId, hitValue, _, overflow = unpack(logline)

		local crit = (result == ACTION_RESULT_CRITICAL_HEAL or result == ACTION_RESULT_HOT_TICK_CRITICAL) and ZO_CachedStrFormat("|cFFCC99<<1>>|r", GetString(SI_LIBCOMBAT_LOG_CRITICAL)) or ""

		local ability = GetAbilityString(abilityId, "heal", fontsize, showIds)

		color = {0.8,1.0,0.6}
		text = result == ACTION_RESULT_DAMAGE_SHIELDED and ZO_CachedStrFormat(GetString(SI_LIBCOMBAT_LOG_FORMAT_HEALABSORB), timeString, ability, hitValue) or ZO_CachedStrFormat(logFormat, timeString, crit, ability, hitValue)

	elseif logtype == LIBCOMBAT_EVENT_EFFECTS_IN or logtype == LIBCOMBAT_EVENT_EFFECTS_OUT or logtype == LIBCOMBAT_EVENT_GROUPEFFECTS_IN or logtype == LIBCOMBAT_EVENT_GROUPEFFECTS_OUT then

		local _, _, unitId, abilityId, changeType, effectType, stacks, sourceType, slot = unpack(logline)

		if units[unitId] == nil then return end

		local unitString = fight.playerid == unitId and GetString(SI_LIBCOMBAT_LOG_YOU) or units[unitId].name

		local changeTypeString = (changeType == EFFECT_RESULT_GAINED or changeType == EFFECT_RESULT_UPDATED) and GetString(SI_LIBCOMBAT_LOG_GAINED) or changeType == EFFECT_RESULT_FADED and GetString(SI_LIBCOMBAT_LOG_LOST)

		local source = UnitTypeString[sourceType] == nil and "" or ZO_CachedStrFormat(" from <<1>>", UnitTypeString[sourceType])

		local colorKey = effectType == BUFF_EFFECT_TYPE_DEBUFF and "debuff" or "buff"

		local buff = GetAbilityString(abilityId, colorKey, fontsize, showIds, stacks)
		
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

			local amount = powerValueChange~=0 and tostring(mathabs(powerValueChange)) or ""

			local resource = (powerType == POWERTYPE_MAGICKA and GetString(SI_ATTRIBUTES2)) or (powerType == POWERTYPE_STAMINA and GetString(SI_ATTRIBUTES3)) or (powerType == POWERTYPE_ULTIMATE and GetString(SI_LIBCOMBAT_LOG_ULTIMATE))

			local ability = abilityId and ZO_CachedStrFormat("(<<1>>)", GetAbilityString(abilityId, "resource", fontsize, showIds)) or ""

			color = (powerType == POWERTYPE_MAGICKA and {0.7,0.7,1}) or (powerType == POWERTYPE_STAMINA and {0.7,1,0.7}) or (powerType == POWERTYPE_ULTIMATE and {1,1,0.7})
			text = ZO_CachedStrFormat(logFormat, timeString, changeTypeString, amount, resource, ability)

		else return
		end

	elseif logtype == LIBCOMBAT_EVENT_PLAYERSTATS then

		local _, _, statchange, newvalue, statId = unpack(logline)

		local stat = statStrings[statId]
		local change = statchange
		local value = newvalue

		if statId == LIBCOMBAT_STAT_SPELLCRIT or statId == LIBCOMBAT_STAT_WEAPONCRIT then

			value = stringformat("%.1f%%", GetCriticalStrikeChance(newvalue))
			change = stringformat("%.1f%%", GetCriticalStrikeChance(statchange))

		end

		if statId == LIBCOMBAT_STAT_SPELLCRITBONUS or statId == LIBCOMBAT_STAT_WEAPONCRITBONUS then

			value = stringformat("%.1f%%", newvalue)
			change = stringformat("%.1f%%", statchange)

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

			Print("events", LOG_LEVEL_INFO, "Invalid Slot: %s (%d), Status: %d)", GetAbilityName(abilityId), abilityId, status)

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

		if state == 1 and otherId ~= nil then otherString = GetAbilityString(otherId, DAMAGE_TYPE_GENERIC, fontsize, showIds) end

		if state > 2 then

			action = GetString("SI_LIBCOMBAT_LOG_RESURRECT", isSelf and 1 or 2)

		end

		text = ZO_CachedStrFormat(logFormat, timeString, unitString, action, otherString)

		color = {.7,.7,.7}

	end

	return text, color
end

local function Initialize()

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

  --resetfightdata
  currentfight = FightHandler:New()

  InitResources()

  -- make addon options menu

  data.CustomAbilityIcon = {}
  data.CustomAbilityName = {
	[46539]	= "Major Force",
  }

  onBossesChanged()

  InitAdvancedStats()

  if data.LoadCustomizations then data.LoadCustomizations() end

  em:RegisterForEvent("LibCombatActive", EVENT_PLAYER_ACTIVATED, function() data.isUIActivated = true end)
  em:RegisterForEvent("LibCombatActive", EVENT_PLAYER_DEACTIVATED, function() data.isUIActivated = false end)
end

Initialize()
