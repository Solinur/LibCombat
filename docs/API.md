# LibCombat2 API

The global table for the library is `LibCombat2`. Version is available as `LibCombat2.version`.

## Callback Registration

Register and unregister callbacks for combat events.

```lua
LibCombat2.RegisterForCombatEvent(name, callbackKey, callback)
LibCombat2.UnregisterForCombatEvent(name, callbackKey)
```

```lua
LibCombat2.RegisterForLogableCombatEvents(name, callback)
LibCombat2.UnregisterForLogableCombatEvents(name)
```

`RegisterForLogableCombatEvents` registers for all log events (`LIBCOMBAT_LOG_EVENT_MIN` to `LIBCOMBAT_LOG_EVENT_MAX`) at once.

For `RegisterForCombatEvent` / `UnregisterForCombatEvent`:

- *string* `name` — addon name, used to identify the registering addon
- *CallbackKey* `callbackKey` — one of the event or log event constants below
- *function* `callback` — callback function

For `RegisterForLogableCombatEvents` / `UnregisterForLogableCombatEvents`:

- *string* `name` — addon name, used to identify the registering addon
- *function* `callback` — callback function

## Fight Data

Query data from the current or last fight. All functions operate on whichever fight has data: the current fight if it has started, otherwise the previous one.

```lua
LibCombat2.ResetFight()
```

Ends the current fight and immediately starts a new one.

```lua
LibCombat2.IsLatestFightBossFight()  --> boolean?
```

```lua
LibCombat2.GetLatestFightDuration()  --> number combatDuration (seconds)
```

```lua
LibCombat2.GetLatestMainTargetDamageDone()
    --> number playerTime, integer playerDamage, number totalTime, integer totalDamage
```

In a boss fight the main target is the boss(es); otherwise the unit with the most health or damage taken.

```lua
LibCombat2.GetLatestTotalDamageDone()
    --> number playerTime, integer playerDamage, number totalTime, integer totalDamage
```

Damage done to all non-friendly units.

```lua
LibCombat2.GetLatestTotalDamageReceived()
    --> number playerTime, integer playerDamage, number totalTime, integer totalDamage
```

Damage received by all friendly units.

```lua
LibCombat2.GetLatestHealingDone(overheal)
    --> number playerTime, integer playerHealing, number groupTime, integer groupHealing
```

- *boolean* `overheal` — if true, includes overflow (overhealing) in the returned values

```lua
LibCombat2.GetLatestPlayerHealingReceived()
    --> number playerTime, integer playerHealingReceived
```

## Unit Queries

```lua
LibCombat2.GetPlayerUnitId()        --> integer unitId
LibCombat2.IsPlayerUnitId(unitId)   --> boolean
```

Look up tracked units by tag, name, or id. Functions returning `UnitAPIHandler` return `nil` if the unit is unknown.

```lua
LibCombat2.GetUnitByTag(unitTag)        --> UnitAPIHandler?
LibCombat2.GetUnitIdByTag(unitTag)      --> integer?

LibCombat2.GetUnitById(unitId)          --> UnitAPIHandler?

LibCombat2.GetUnitsByName(unitName)     --> UnitAPIHandler, ...   (multiple returns)
LibCombat2.GetUnitIdsByName(unitName)   --> integer, ...

LibCombat2.GetUnitsByRawName(unitRawName)    --> UnitAPIHandler, ...
LibCombat2.GetUnitIdsByRawName(unitRawName)  --> integer, ...
```

`unitName` is the localized/formatted name; `unitRawName` is the internal name as received from combat events.

### UnitAPIHandler

Object returned by the unit lookup functions above.

```lua
unit:GetUnitName()      --> string
unit:GetUnitRawName()   --> string
unit:GetUnitType()      --> CombatUnitType?
unit:GetUnitTags()      --> table<string, string>
unit:IsBoss()           --> boolean
unit:IsFriendly()       --> boolean
unit:GetMaxHealth()     --> number?
unit:GetFullUnitData()  --> UnitData
```

`GetFullUnitData()` returns a snapshot table `{ unitId, name, rawName, unitType, unitTags, isBoss, isFriendly, maxHealth }`.

## Utility Functions

Cached ability name and icon lookups. Caching reduces CPU cost versus calling the ESO API directly on every frame.

```lua
LibCombat2.GetFormattedAbilityName(id, isScript)  --> string name
LibCombat2.GetFormattedAbilityIcon(id, isScript)  --> string texturePath
```

- *integer* `id` — abilityId (or crafted-ability script id when `isScript` is true)
- *boolean?* `isScript` — if true, looks up a crafted ability script instead of a regular ability

```lua
LibCombat2.GetDamageColor(damageType)  --> ZO_ColorDef
```

Returns a `ZO_ColorDef` for the given damage type. Use `:ToHex()` for a hex string or `:Colorize(text)` to colorize text directly.

```lua
LibCombat2.GetFoodDrinkItemLinkFromAbilityId(abilityId)  --> string? itemLink
```

Returns the item link for a known food/drink buff ability, or `nil`.

```lua
LibCombat2.IsMundusBuff(abilityId)  --> boolean
```

## Event Constants

These events fire at fight boundaries and on death.

```lua
LIBCOMBAT_EVENT_FIGHTRECAP   = 50  -- callback(eventType, {data})
LIBCOMBAT_EVENT_FIGHTSUMMARY = 51  -- callback(eventType, {fight})
LIBCOMBAT_EVENT_DEATHRECAP   = 52  -- callback(eventType, timeMs, {data})
```

## Log Event Constants

These events fire in real time during combat. Use `RegisterForCombatEvent` or `RegisterForLogableCombatEvents` to receive them.

```lua
LIBCOMBAT_LOG_EVENT_COMBATSTATE = 1  -- callback(eventType, timeMs, combatMessage, value)
LIBCOMBAT_LOG_EVENT_DAMAGE      = 2  -- callback(eventType, timeMs, result, sourceUnitId, targetUnitId, abilityId, hitValue, damageType, overflow)
LIBCOMBAT_LOG_EVENT_HEAL        = 3  -- callback(eventType, timeMs, result, sourceUnitId, targetUnitId, abilityId, hitValue, damageType, overflow)
LIBCOMBAT_LOG_EVENT_EFFECT      = 4  -- callback(eventType, timeMs, unitId, abilityId, changeType, effectType, stacks, sourceType, effectSlot)
LIBCOMBAT_LOG_EVENT_STATS       = 5  -- callback(eventType, timeMs, statchange, newvalue, statId)
LIBCOMBAT_LOG_EVENT_RESOURCE    = 6  -- callback(eventType, timeMs, abilityId, powerValueChange, powerType, powerValue)
LIBCOMBAT_LOG_EVENT_DEATH       = 7  -- callback(eventType, timeMs, state, unitId, abilityId/unitId)
LIBCOMBAT_LOG_EVENT_SKILL_CAST  = 8  -- callback(eventType, timeMs, reducedslot, abilityId, skillStatus, skillDelay, skillDuration)
LIBCOMBAT_LOG_EVENT_PERFORMANCE = 9  -- callback(eventType, timeMs, avg, min, max, ping)
LIBCOMBAT_LOG_EVENT_QUICKSLOT   = 10 -- callback(eventType, timeMs, itemLink)
```

### `combatMessage` values (COMBATSTATE)

```lua
LIBCOMBAT_MESSAGE_COMBATSTART = 1
LIBCOMBAT_MESSAGE_COMBATEND   = 2
LIBCOMBAT_MESSAGE_WEAPONSWAP  = 3
```

### `skillStatus` values (SKILL_CAST)

```lua
LIBCOMBAT_SKILLSTATUS_INSTANT         = 1
LIBCOMBAT_SKILLSTATUS_BEGIN_DURATION  = 2
LIBCOMBAT_SKILLSTATUS_BEGIN_CHANNEL   = 3
LIBCOMBAT_SKILLSTATUS_SUCCESS         = 4
LIBCOMBAT_SKILLSTATUS_REGISTERED      = 5
LIBCOMBAT_SKILLSTATUS_QUEUE           = 6
LIBCOMBAT_SKILLSTATUS_CANCELLED       = 7
```

### `statId` values (STATS)

```lua
LIBCOMBAT_STAT_MAXMAGICKA          = 1
LIBCOMBAT_STAT_SPELLPOWER          = 2
LIBCOMBAT_STAT_SPELLCRIT           = 3
LIBCOMBAT_STAT_SPELLCRITBONUS      = 4
LIBCOMBAT_STAT_SPELLPENETRATION    = 5

LIBCOMBAT_STAT_MAXSTAMINA          = 11
LIBCOMBAT_STAT_WEAPONPOWER         = 12
LIBCOMBAT_STAT_WEAPONCRIT          = 13
LIBCOMBAT_STAT_WEAPONCRITBONUS     = 14
LIBCOMBAT_STAT_WEAPONPENETRATION   = 15

LIBCOMBAT_STAT_MAXHEALTH           = 21
LIBCOMBAT_STAT_PHYSICALRESISTANCE  = 22
LIBCOMBAT_STAT_SPELLRESISTANCE     = 23
LIBCOMBAT_STAT_CRITICALRESISTANCE  = 24
LIBCOMBAT_STAT_STATUS_EFFECT_CHANCE = 25
```

### `state` values (DEATH)

```lua
LIBCOMBAT_UNIT_STATE_DEAD         = 1
LIBCOMBAT_UNIT_STATE_ALIVE        = 2
LIBCOMBAT_UNIT_STATE_RESURRECTING = 3
LIBCOMBAT_UNIT_STATE_RESURRECTED  = 4
```

## Legacy API

Kept for compatibility. Prefer the functions above for new code.

```lua
LibCombat2:RegisterCallbackType(callbacktype, callback, name)
LibCombat2:UnregisterCallbackType(callbacktype, callback, name)
LibCombat2:RegisterAllLogCallbacks(callback, name)
```

---

<!-- markdownlint-disable-next-line MD036 -->
**Solinur (PC-EU)**
