# API Implementation

The global table for the Library is `LibCombat2`
The version is given by `LibCombat2.version`

## Legacy API

To allow an easier transition between LibCombat and Libcombat2 the following functions are available:

In order to receive combat events from the library one has to register a callback function. A function to unregister is also available.

```lua
    LibCombat2:RegisterCallbackType(eventType, callback, idString)
    LibCombat2:UnregisterCallbackType(eventType, callback, idString)
```

* parameters
  * *number* `eventType` - one of the log types described below.
  * *function* `callback` - callback function. When unregistering the underlying ZOS code actually compares this to the registered one. If it is not the same, the callback won't be removed.
  * *string* `idString` - string used to identify the addon which requests the callback. I recommend using the addon name.

## Event Types

The parameters handed to the callback are given by commentary.

```lua
LIBCOMBAT_EVENT_FIGHTRECAP = 50    -- LIBCOMBAT_EVENT_FIGHTRECAP, {data}
LIBCOMBAT_EVENT_FIGHTSUMMARY = 51   -- LIBCOMBAT_EVENT_FIGHTSUMMARY, {fight}
LIBCOMBAT_EVENT_DEATHRECAP = 52    -- LIBCOMBAT_EVENT_DEATHRECAP, timeMs, {data}
```

## Utility Functions

The following functions provide a cached way to look up icon paths and ability names without language formatter appendixes (like "^F").
Looking up and formatting icons and ability names is quite costly CPU-wise. Caching greatly reduces the required CPU time at the expense of a little memory.

```lua
    LibCombat2.GetFormattedAbilityName(abilityId)
    LibCombat2.GetFormattedAbilityIcon(abilityId)
```

* parameters
  * *number* `abilityId` - abilityId as provided by combat and buff events
* returns:
  * *string* `abilityName` or `iconPath`

A function returning the typical colors for each damage type  (Used by Combat Metrics for years).
Changed from v1: In LibCombat2, GetDamageColor now returns a ZO_ColorDef instance instead of a string.
To get the hex string representation, call :ToHex() on the returned object, or use :Colorize(text) to colorize text directly.

```lua
    LibCombat2.GetDamageColor(damageType)
```

* parameters
  * *number* `damageType` - damageType as provided by combat and buff events
* returns:
  * *ZO_ColorDef* `color` - returns the color as a `ZO_ColorDef` instance

*Solinur (PC-EU)*
