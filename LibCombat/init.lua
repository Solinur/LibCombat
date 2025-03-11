--- @class LibCombat
LibCombat = {}
LibCombat.__index = LibCombat
LibCombat.name = "LibCombat"
LibCombat.version = 78
LibCombat.data = { skillBars = {}, scribedSkills = {} }
LibCombat.cm = ZO_CallbackObject:New()
LibCombat.debug = false or (SoliTest ~= nil)

-- GLOBAL CONSTANTS

LIBCOMBAT_EVENT_MIN = 0
LIBCOMBAT_EVENT_UNITS = 0                 -- LIBCOMBAT_EVENT_UNITS, {units}
LIBCOMBAT_EVENT_FIGHTRECAP = 1            -- LIBCOMBAT_EVENT_FIGHTRECAP, {data}
LIBCOMBAT_EVENT_FIGHTSUMMARY = 2          -- LIBCOMBAT_EVENT_FIGHTSUMMARY, {fight}
LIBCOMBAT_EVENT_GROUPRECAP = 3            -- LIBCOMBAT_EVENT_GROUPRECAP, groupDPSOut, groupDPSIn, groupHPS, dpstime, hpstime
LIBCOMBAT_EVENT_DAMAGE_OUT = 4            -- LIBCOMBAT_EVENT_DAMAGE_OUT, timems, result, sourceUnitId, targetUnitId, abilityId, hitValue, damageType, overflow
LIBCOMBAT_EVENT_DAMAGE_IN = 5             -- LIBCOMBAT_EVENT_DAMAGE_IN, timems, result, sourceUnitId, targetUnitId, abilityId, hitValue, damageType, overflow
LIBCOMBAT_EVENT_DAMAGE_SELF = 6           -- LIBCOMBAT_EVENT_DAMAGE_SELF, timems, result, sourceUnitId, targetUnitId, abilityId, hitValue, damageType, overflow
LIBCOMBAT_EVENT_HEAL_OUT = 7              -- LIBCOMBAT_EVENT_HEAL_OUT, timems, result, sourceUnitId, targetUnitId, abilityId, hitValue, damageType, overflow
LIBCOMBAT_EVENT_HEAL_IN = 8               -- LIBCOMBAT_EVENT_HEAL_IN, timems, result, sourceUnitId, targetUnitId, abilityId, hitValue, damageType, overflow
LIBCOMBAT_EVENT_HEAL_SELF = 9             -- LIBCOMBAT_EVENT_HEAL_SELF, timems, result, sourceUnitId, targetUnitId, abilityId, hitValue, damageType, overflow
LIBCOMBAT_EVENT_EFFECTS_IN = 10           -- LIBCOMBAT_EVENT_EFFECTS_IN, timems, unitId, abilityId, changeType, effectType, stacks, sourceType, effectSlot
LIBCOMBAT_EVENT_EFFECTS_OUT = 11          -- LIBCOMBAT_EVENT_EFFECTS_OUT, timems, unitId, abilityId, changeType, effectType, stacks, sourceType, effectSlot
LIBCOMBAT_EVENT_GROUPEFFECTS_IN = 12      -- LIBCOMBAT_EVENT_GROUPEFFECTS_IN, timems, unitId, abilityId, changeType, effectType, stacks, sourceType, effectSlot
LIBCOMBAT_EVENT_GROUPEFFECTS_OUT = 13     -- LIBCOMBAT_EVENT_GROUPEFFECTS_OUT, timems, unitId, abilityId, changeType, effectType, stacks, sourceType, effectSlot
LIBCOMBAT_EVENT_PLAYERSTATS = 14          -- LIBCOMBAT_EVENT_PLAYERSTATS, timems, statchange, newvalue, statId
LIBCOMBAT_EVENT_RESOURCES = 15            -- LIBCOMBAT_EVENT_RESOURCES, timems, abilityId, powerValueChange, powerType, powerValue
LIBCOMBAT_EVENT_MESSAGES = 16             -- LIBCOMBAT_EVENT_MESSAGES, timems, combatMessage, value
LIBCOMBAT_EVENT_DEATH = 17                -- LIBCOMBAT_EVENT_DEATH, timems, state, unitId, abilityId/unitId
LIBCOMBAT_EVENT_PLAYERSTATS_ADVANCED = 18 -- LIBCOMBAT_EVENT_PLAYERSTATS_ADVANCED, timems, statchange, newvalue, statId
LIBCOMBAT_EVENT_SKILL_TIMINGS = 19        -- LIBCOMBAT_EVENT_SKILL_TIMINGS, timems, reducedslot, abilityId, skillStatus, skillDelay, skillDuration
LIBCOMBAT_EVENT_BOSSHP = 20               -- LIBCOMBAT_EVENT_BOSSHP, timems, bossId, currenthp, maxhp
LIBCOMBAT_EVENT_PERFORMANCE = 21          -- LIBCOMBAT_EVENT_PERFORMANCE, timems, avg, min, max, ping
LIBCOMBAT_EVENT_DEATHRECAP = 22           -- LIBCOMBAT_EVENT_DEATHRECAP, timems, {data}
LIBCOMBAT_EVENT_QUICKSLOT = 23            -- LIBCOMBAT_EVENT_QUICKSLOT, timems, itemLink
LIBCOMBAT_EVENT_SYNERGY = 24              -- LIBCOMBAT_EVENT_SYNERGY, timems, abilityId, status
LIBCOMBAT_EVENT_MAX = 24

LIBCOMBAT_STATE_DEAD = 1
LIBCOMBAT_STATE_ALIVE = 2
LIBCOMBAT_STATE_RESURRECTING = 3
LIBCOMBAT_STATE_RESURRECTED = 4

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
LIBCOMBAT_STAT_STATUS_EFFECT_CHANCE = 25

-- CP type

LIBCOMBAT_CPTYPE_PASSIVE = 0
LIBCOMBAT_CPTYPE_UNSLOTTED = 1
LIBCOMBAT_CPTYPE_SLOTTED = 2

do
    local dx = math.ceil(GuiRoot:GetWidth() / tonumber(GetCVar("WindowedWidth")) * 1000) / 1000
    LIBCOMBAT_LINE_SIZE = dx
end

-- Utility Functions
-- -----------------------------------------------------------------------------
do
    local AbilityNameCache = {}
    local ScriptNameCache = {}

    local CustomAbilityName =
    {

        [-1] = "Unknown",                                                                                                                 -- Whenever there is no known abilityId
        [-2] = "Unknown",                                                                                                                 -- Whenever there is no known abilityId

        [0] = GetString(SI_LIBCOMBAT_LOG_BASEREG),                                                                                        -- Whenever there is no known abilityId

        [75753] = zo_strformat(SI_ABILITY_NAME, GetAbilityName(75753)),                                                                   -- Line-breaker (Alkosh). pin abiltiy name so it can't get overridden
        [17906] = zo_strformat(SI_ABILITY_NAME, GetAbilityName(17906)),                                                                   -- Crusher (Glyph). pin abiltiy name so it can't get overridden
        [62988] = zo_strformat(SI_ABILITY_NAME, GetAbilityName(62988)),                                                                   -- Off-Balance

        [81274] = "(C) " .. zo_strformat(SI_ABILITY_NAME, GetAbilityName(81274)),                                                         -- Crown Store Poison, Rename to differentiate from normal Poison, which can apparently stack ?
        [81275] = "(C) " .. zo_strformat(SI_ABILITY_NAME, GetAbilityName(81275)),                                                         -- Crown Store Poison, Rename to differentiate from normal Poison, which can apparently stack ?

        [113382] = zo_strformat(SI_LIBCOMBAT_CUSTOM_ABILITY_FORMAT, GetAbilityName(113382), GetString(SI_LIBCOMBAT_LOG_DEBUFF)),          -- To make sure that tracking works correctly since both buff and debuff are named the same.

        [61901] = zo_strformat(SI_LIBCOMBAT_CUSTOM_ABILITY_FORMAT, GetAbilityName(61901), GetString(SI_ABILITY_TOOLTIP_TOGGLE_DURATION)), -- Grim Focus Toggle
        [61919] = zo_strformat(SI_LIBCOMBAT_CUSTOM_ABILITY_FORMAT, GetAbilityName(61919), GetString(SI_ABILITY_TOOLTIP_TOGGLE_DURATION)), -- Merciless Resolve Toggle
        [61927] = zo_strformat(SI_LIBCOMBAT_CUSTOM_ABILITY_FORMAT, GetAbilityName(61927), GetString(SI_ABILITY_TOOLTIP_TOGGLE_DURATION)), -- Relentless Focus Toggle

        [122729] = zo_strformat(SI_LIBCOMBAT_CUSTOM_ABILITY_FORMAT, GetAbilityName(122729), GetString(SI_LIBCOMBAT_LOG_BUFF)),            --  Name for separate stats buff of Seething Fury
    }

    --- Function to return cached and formatted ability and script names.
    --- @param id any
    --- @param isScript? boolean
    --- @return string name
    local function GetFormattedAbilityName(id, isScript)
        if id == nil then return "" end
        local cache = isScript and ScriptNameCache or AbilityNameCache
        local name = cache[id]

        if name == nil then
            if isScript then
                name = GetCraftedAbilityScriptDisplayName(id)
            else
                name = CustomAbilityName[id] or GetAbilityName(id)
            end
            if name == "Off-Balance" then name = "Off Balance" end
            cache[id] = name
        end

        return name
    end
    LibCombat.GetFormattedAbilityName = GetFormattedAbilityName
end
-- -----------------------------------------------------------------------------
do
    local CustomAbilityIcon =
    {

        [0] = "esoui/art/icons/achievement_wrothgar_046.dds",
        [122729] = "esoui/art/icons/ability_warrior_025.dds",
        [174250] = "esoui/art/icons/ability_healer_018.dds",

    }

    local AbilityIconCache = {}
    local ScriptIconCache = {}
    local noIcon = "/esoui/art/icons/icon_missing.dds"
    local noScriptIcon = "EsoUI/Art/crafting/gamepad/crafting_alchemy_trait_unknown.dds"

    --- Function to return cached and formatted ability and script icons.
    --- @param id unknown
    --- @param isScript? boolean
    --- @return string texturePath
    local function GetFormattedAbilityIcon(id, isScript)
        if id == nil then
            return noIcon
        elseif type(id) == "string" then
            return id
        elseif isScript and id == 0 then
            return noScriptIcon
        end

        local cache = isScript and ScriptIconCache or AbilityIconCache
        local icon = cache[id]

        if icon == nil then
            if isScript then
                icon = GetCraftedAbilityScriptIcon(id)
            else
                icon = CustomAbilityIcon[id] or GetAbilityIcon(id)
            end
            cache[id] = icon
        end

        return icon
    end
    LibCombat.GetFormattedAbilityIcon = GetFormattedAbilityIcon
end
-- -----------------------------------------------------------------------------
do
    local logColors =
    {
        [DAMAGE_TYPE_NONE]     = "|cE6E6E6",
        [DAMAGE_TYPE_GENERIC]  = "|cE6E6E6",
        [DAMAGE_TYPE_PHYSICAL] = "|cf4f2e8",
        [DAMAGE_TYPE_FIRE]     = "|cff6600",
        [DAMAGE_TYPE_SHOCK]    = "|cffff66",
        [DAMAGE_TYPE_OBLIVION] = "|cd580ff",
        [DAMAGE_TYPE_COLD]     = "|cb3daff",
        [DAMAGE_TYPE_EARTH]    = "|cbfa57d",
        [DAMAGE_TYPE_MAGIC]    = "|c9999ff",
        [DAMAGE_TYPE_DROWN]    = "|ccccccc",
        [DAMAGE_TYPE_DISEASE]  = "|cc48a9f",
        [DAMAGE_TYPE_POISON]   = "|c9fb121",
        [DAMAGE_TYPE_BLEED]    = "|cc20a38",
        ["heal"]               = "|c55ff55",
        ["buff"]               = "|c00cc00",
        ["debuff"]             = "|cff3333",
        ["resource"]           = "|cffffff",
    }

    local function GetDamageColor(damageType)
        return logColors[damageType]
    end

    LibCombat.GetDamageColor = GetDamageColor
end
-- -----------------------------------------------------------------------------
LibCombat.statStrings =
{
    [LIBCOMBAT_STAT_MAXMAGICKA]         = "|c8888ff" .. GetString(SI_DERIVEDSTATS4) .. "|r ", -- |c8888ff blue
    [LIBCOMBAT_STAT_SPELLPOWER]         = "|c8888ff" .. GetString(SI_DERIVEDSTATS25) .. "|r ",
    [LIBCOMBAT_STAT_SPELLCRIT]          = "|c8888ff" .. GetString(SI_DERIVEDSTATS23) .. "|r ",
    [LIBCOMBAT_STAT_SPELLCRITBONUS]     = "|c8888ff" .. GetString(SI_LIBCOMBAT_LOG_STAT_SPELL_CRIT_DONE) .. "|r ",
    [LIBCOMBAT_STAT_SPELLPENETRATION]   = "|c8888ff" .. GetString(SI_DERIVEDSTATS34) .. "|r ",

    [LIBCOMBAT_STAT_MAXSTAMINA]         = "|c88ff88" .. GetString(SI_DERIVEDSTATS29) .. "|r ", -- |c88ff88 green
    [LIBCOMBAT_STAT_WEAPONPOWER]        = "|c88ff88" .. GetString(SI_DERIVEDSTATS1) .. "|r ",
    [LIBCOMBAT_STAT_WEAPONCRIT]         = "|c88ff88" .. GetString(SI_DERIVEDSTATS16) .. "|r ",
    [LIBCOMBAT_STAT_WEAPONCRITBONUS]    = "|c88ff88" .. GetString(SI_LIBCOMBAT_LOG_STAT_WEAPON_CRIT_DONE) .. "|r ",
    [LIBCOMBAT_STAT_WEAPONPENETRATION]  = "|c88ff88" .. GetString(SI_DERIVEDSTATS33) .. "|r ",

    [LIBCOMBAT_STAT_MAXHEALTH]          = "|cffff88" .. GetString(SI_DERIVEDSTATS7) .. "|r ", -- |cffff88 red
    [LIBCOMBAT_STAT_PHYSICALRESISTANCE] = "|cffff88" .. GetString(SI_DERIVEDSTATS22) .. "|r ",
    [LIBCOMBAT_STAT_SPELLRESISTANCE]    = "|cffff88" .. GetString(SI_DERIVEDSTATS13) .. "|r ",
    [LIBCOMBAT_STAT_CRITICALRESISTANCE] = "|cffff88" .. GetString(SI_DERIVEDSTATS24) .. "|r ",
}
-- -----------------------------------------------------------------------------
do
    local function GetAbilityString(abilityId, damageType, fontsize, showIds, stacks)
        local stacks = stacks or 0

        local icon = zo_iconFormat(LibCombat.GetFormattedAbilityIcon(abilityId), fontsize, fontsize)
        local name = LibCombat.GetFormattedAbilityName(abilityId)
        local damageColor = LibCombat.GetDamageColor(damageType)

        local format = abilityId == 126597 and "<<5[/$dx /$dx ]>><<1>> <<2>><<3>><<4[/ ($d)/ ($d)]>>|r" or "<<5[//$dx ]>><<1>> <<2>><<3>><<4[/ ($d)/ ($d)]>>|r"
        local abilityString = ZO_CachedStrFormat(format, icon, damageColor, name, showIds and abilityId or 0, stacks)

        return abilityString
    end

    LibCombat.GetAbilityString = GetAbilityString
end
-- -----------------------------------------------------------------------------
LibCombat.UnitTypeString =
{
    [COMBAT_UNIT_TYPE_PLAYER]     = GetString(SI_LIBCOMBAT_LOG_UNITTYPE_PLAYER),
    [COMBAT_UNIT_TYPE_PLAYER_PET] = GetString(SI_LIBCOMBAT_LOG_UNITTYPE_PET),
    [COMBAT_UNIT_TYPE_GROUP]      = GetString(SI_LIBCOMBAT_LOG_UNITTYPE_GROUP),
    [COMBAT_UNIT_TYPE_OTHER]      = GetString(SI_LIBCOMBAT_LOG_UNITTYPE_OTHER),
}
-- -----------------------------------------------------------------------------
