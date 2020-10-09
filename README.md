# LibCombat

## Description

**Please note that the library is not complete yet, so some of the API could still change.**

This library is supposed to provide the data collection for Combat Metrics. 
However I tried to make it in such a way it can be used for other addons which may only need parts of the data.
Additionally it can provide human readable combat log lines, which are arranged so they should be translatable.
I tried to optimize the code to impact the performance as little as possible.

## Implementation

The global table for the Library is `LibCombat`
The version is given by `LibCombat.version`

### Callback Registry

In order to receive combat events from the library one has to register a callback function. A function to unregister is also available.

```lua
    LibCombat:RegisterCallbackType(eventType, callback, idString)
    LibCombat:UnregisterCallbackType(eventType, callback, idString)
```
* parameters
    * *number* `eventType` - one of the log types described below. 
    * *function* `callback` - callback function. When unregistering the underlying ZOS code actually compares this to the registered one. If it is not he same, the callback won't be removed.
    * *string* `idString` - string used to identify the addon which requests the callback. I recommend using the addon name.

### Event Types

The parameters handed to the callback are given by commentary.

```lua 
LIBCOMBAT_EVENT_MIN = 0
LIBCOMBAT_EVENT_UNITS = 0				-- LIBCOMBAT_EVENT_UNITS, {units}
LIBCOMBAT_EVENT_FIGHTRECAP = 1			-- LIBCOMBAT_EVENT_FIGHTRECAP, DPSOut, DPSIn, hps, HPSIn, healingOutTotal, dpstime, hpstime
LIBCOMBAT_EVENT_FIGHTSUMMARY = 2		-- LIBCOMBAT_EVENT_FIGHTSUMMARY, {fight}
LIBCOMBAT_EVENT_GROUPRECAP = 3			-- LIBCOMBAT_EVENT_GROUPRECAP, groupDPSOut, groupDPSIn, groupHPS, dpstime, hpstime
LIBCOMBAT_EVENT_DAMAGE_OUT = 4			-- LIBCOMBAT_EVENT_DAMAGE_OUT, timems, result, sourceUnitId, targetUnitId, abilityId, hitValue, damageType
LIBCOMBAT_EVENT_DAMAGE_IN = 5			-- LIBCOMBAT_EVENT_DAMAGE_IN, timems, result, sourceUnitId, targetUnitId, abilityId, hitValue, damageType
LIBCOMBAT_EVENT_DAMAGE_SELF = 6			-- LIBCOMBAT_EVENT_DAMAGE_SELF, timems, result, sourceUnitId, targetUnitId, abilityId, hitValue, damageType
LIBCOMBAT_EVENT_HEAL_OUT = 7			-- LIBCOMBAT_EVENT_HEAL_OUT, timems, result, sourceUnitId, targetUnitId, abilityId, hitValue, damageType
LIBCOMBAT_EVENT_HEAL_IN = 8				-- LIBCOMBAT_EVENT_HEAL_IN, timems, result, sourceUnitId, targetUnitId, abilityId, hitValue, damageType
LIBCOMBAT_EVENT_HEAL_SELF = 9			-- LIBCOMBAT_EVENT_HEAL_SELF, timems, result, sourceUnitId, targetUnitId, abilityId, hitValue, damageType
LIBCOMBAT_EVENT_EFFECTS_IN = 10			-- LIBCOMBAT_EVENT_EFFECTS_IN, timems, unitId, abilityId, changeType, effectType, stacks, sourceType, effectSlot
LIBCOMBAT_EVENT_EFFECTS_OUT = 11		-- LIBCOMBAT_EVENT_EFFECTS_OUT, timems, unitId, abilityId, changeType, effectType, stacks, sourceType, effectSlot
LIBCOMBAT_EVENT_GROUPEFFECTS_IN = 12	-- LIBCOMBAT_EVENT_GROUPEFFECTS_IN, timems, unitId, abilityId, changeType, effectType, stacks, sourceType, effectSlot
LIBCOMBAT_EVENT_GROUPEFFECTS_OUT = 13	-- LIBCOMBAT_EVENT_GROUPEFFECTS_OUT, timems, unitId, abilityId, changeType, effectType, stacks, sourceType, effectSlot
LIBCOMBAT_EVENT_PLAYERSTATS = 14		-- LIBCOMBAT_EVENT_PLAYERSTATS, timems, statchange, newvalue, [statId]
LIBCOMBAT_EVENT_RESOURCES = 15			-- LIBCOMBAT_EVENT_RESOURCES, timems, abilityId, powerValueChange, powerType, powerValue
LIBCOMBAT_EVENT_MESSAGES = 16			-- LIBCOMBAT_EVENT_MESSAGES, timems, [combatMessage], value
LIBCOMBAT_EVENT_DEATH = 17				-- LIBCOMBAT_EVENT_DEATH, timems, unitId, abilityId
LIBCOMBAT_EVENT_RESURRECTION = 18		-- LIBCOMBAT_EVENT_RESURRECTION, timems, unitId, self
LIBCOMBAT_EVENT_SKILL_TIMINGS = 19		-- LIBCOMBAT_EVENT_SKILL_TIMINGS, timems, reducedslot, abilityId, [skillStatus]
LIBCOMBAT_EVENT_BOSSHP = 20				-- LIBCOMBAT_EVENT_BOSSHP, timems, bossId, currenthp, maxhp
LIBCOMBAT_EVENT_MAX = 20
```

all variables are of type number except when formatted as follows: 
* `{table}` 
* `[global]` 

the globals use the following values:

```lua
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

-- combatMessage

LIBCOMBAT_MESSAGE_COMBATSTART = 1
LIBCOMBAT_MESSAGE_COMBATEND = 2
LIBCOMBAT_MESSAGE_WEAPONSWAP = 3

-- skillStatus

LIBCOMBAT_SKILLSTATUS_INSTANT = 1
LIBCOMBAT_SKILLSTATUS_BEGIN_DURATION = 2
LIBCOMBAT_SKILLSTATUS_BEGIN_CHANNEL = 3
LIBCOMBAT_SKILLSTATUS_SUCCESS = 4
LIBCOMBAT_SKILLSTATUS_REGISTERED = 5  -- when the button press is registered
LIBCOMBAT_SKILLSTATUS_QUEUE = 6
```

### Utility Functions

The following functions provide a cached way to lookup icon paths and ability names without language formatter appendixes (like "^F"). 
Looking up and formatting icons and ability names is quite costly CPU-wise. Caching greatly reduces the required CPU time at the expense of a little memory.

```lua
    LibCombat.GetFormattedAbilityName(abilityId)
    LibCombat.GetFormattedAbilityIcon(abilityId)
```
* parameters
    * *number* `abilityId` - abilityId as provided by combat and buff events 
* returns:
    * *string* `abilityName` or `iconPath`

To provide unified combat log strings the following function can be used.

```lua
    LibCombat.GetCombatLogString(fight, logline, fontsize)
```
* parameters
    * *table* `fight` - table containing the collected data of a fight. Can be aquired using the LIBCOMBAT_EVENT_FIGHTSUMMARY eventType
    * *table* `logline` - table containing the returned values of any event type >= 4 (e.g. `LIBCOMBAT_EVENT_DAMAGE_OUT`, see above)
    * *number* `fontsize`
* returns:
    * *string* `text` - returns the complete formatted log line
    * *table* `color` - returns the general color of the log line (e.g. `{.7,.7,.7}`).
        * Note: Parts within the log string might have different colors according to embedded color string modifiers.

A function returning the typical colors for each damage type  (Used by Combat Metrics for years).

```lua
    LibCombat.GetDamageColor(damageType)
```
* parameters
    * *number* `damageType` - damageType as provided by combat and buff events 
* returns:
    * *string* `color` - returns the color as a string modifier (e.g. `"|cffff66"`)

A function to return a copy of the current fight data:

```lua
    LibCombat.GetCurrentFight()
```
* returns:
    * *table* `fight` - table containing the collected data of a fight. This always generates a copy.

<!-- TODO: Return values? -->

*Solinur (EU)*
