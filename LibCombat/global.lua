-- This file contains definitions of global variables

local lib = LibCombat

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

local isFileInitialized = false

function lib.InitializeGlobals()

	if isFileInitialized == true then return false end

    isFileInitialized = true
	return true

end