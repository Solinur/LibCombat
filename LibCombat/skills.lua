--[[ New scheme to detect skill activations
On login: Register skills on your bar. 
In fight: Figure out replacement skills by watching changes to the bar. Put them into a skill bars object. Add API function to get those bars.
--> no need for replacement skills table
TBD: Save replacements per patch or relearn on use? 

--]]

local lib = LibCombat
local libint = lib.internal
local CallbackKeys = lib.internal.callbackKeys
local libfunc = libint.functions
local libdata = lib.data
local Print = libint.Print
libint.ABILITY_RESOURCE_CACHE_SIZE = 20
local maxSkillDelay = 2000

local SlotSkills = {}
local IdToReducedSlot = {}
libint.lastAbilityActivations = {}

local registeredSkills = {}
libint.registeredSkills = registeredSkills

libint.abilityConversions = {	-- Ability conversions for tracking skill activations

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

libint.abilityAdditions = { -- Abilities to register additionally because they change in fight

[61902] = 61907,    -- Grim Focus --> Assasins Will
	[61907] = 61902,    -- Assasins Will --> Grim Focus
	[61919] = 61930,    -- Merciless Resolve --> Assasins Will
	[61930] = 61919,    -- Assasins Will --> Merciless Resolve
	[61927] = 61932,    -- Relentless Focus --> Assasins Scourge
	[61932] = 61927,    -- Assasins Scourge --> Relentless Focus
	[46324] = 114716,  	-- Crystal Fragments Proc
	[114716] = 46324,  	-- Crystal Fragments Proc Fades
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

libint.abilityAdditionsReverse = {}

for k,v in pairs(libint.abilityAdditions) do

	libint.abilityAdditionsReverse[v] = k

end

libint.directHeavyAttacks = {	-- for special handling to detect their end

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

local function GetSkillRegistrationData(abilityId)

	local channeled, castTime = GetAbilityCastInfo(abilityId)

	local convertedId, result, convertedId2, result2 = unpack(libint.abilityConversions[abilityId] or {})

	local result = result or (castTime > 0 and ACTION_RESULT_BEGIN) or nil

	local result2 = result2 or (castTime > 0 and ACTION_RESULT_EFFECT_GAINED) or (channeled and ACTION_RESULT_EFFECT_FADED) or nil

	local convertedId = convertedId or abilityId
	local convertedId2 = convertedId2 or abilityId

	local data = result2 and {convertedId, result, convertedId2, result2} or {convertedId, result}

	return data

end

local function UpdateSlotSkillEvents()

	local events = libint.Events.Skills

	if not events.active then return end

	SlotSkills = {}

	local registeredIds = {}

	if libdata.skillBars == nil then libdata.skillBars = {} end

	for _, bar in pairs(libdata.skillBars) do

		for _, abilityId in pairs(bar) do

			if registeredIds[abilityId] == nil then

				registeredIds[abilityId] = true

				table.insert(SlotSkills, GetSkillRegistrationData(abilityId))

				if libint.abilityAdditions[abilityId] then table.insert(SlotSkills, GetSkillRegistrationData(libint.abilityAdditions[abilityId])) end
			end
		end
	end

	events:Update()
end

function libfunc.GetCurrentSkillBars()

	local skillBars = libdata.skillBars

	local bar = libdata.bar

	skillBars[bar] = {}

	local currentbar = skillBars[bar]

	for i = 1, 8 do

		local id = GetSlotBoundId(i, GetActiveHotbarCategory())

		currentbar[i] = id

		local reducedslot = (bar - 1) * 10 + i

		local conversion = libint.abilityConversions[id]

		local convertedId = conversion and conversion[1] or id

		IdToReducedSlot[convertedId] = reducedslot

		if conversion and conversion[3] then IdToReducedSlot[conversion[3]] = reducedslot end

	end

	UpdateSlotSkillEvents()

end

local function GetReducedSlotId(reducedslot)

	local bar = math.floor(reducedslot/10) + 1

	local slot = reducedslot%10

	local origId = (libdata.skillBars and libdata.skillBars[bar] and libdata.skillBars[bar][slot])

	return origId

end

local HeavyAttackCharging

local function onAbilityUsed(eventCode, result, isError, abilityName, abilityGraphic, abilityActionSlotType, sourceName, sourceType, targetName, targetType, hitValue, powerType, damageType, log, sourceUnitId, targetUnitId, abilityId, overflow)

	if libint.Events.Skills.active ~= true or libdata.inCombat == false or not (validSkillStartResults[result] or (validNonProjectileSkillStartResults[result] and not libint.isProjectile[abilityId])) then return end

	local timems = GetGameTimeMilliseconds()

	local lasttime = libint.lastAbilityActivations[abilityId]
	if lasttime == nil or (timems - lasttime) > maxSkillDelay then return end

	libint.lastAbilityActivations[abilityId] = nil

	local reducedslot = IdToReducedSlot[abilityId] or (libint.abilityAdditionsReverse[abilityId] and IdToReducedSlot[libint.abilityAdditionsReverse[abilityId]]) or nil

	local origId = GetReducedSlotId(reducedslot)

	local channeled, castTime, channelTime = GetAbilityCastInfo(origId)

	castTime = channeled and channelTime or castTime

	Print("events", "VERBOSE", "[%.3f] Skill fired: %s (%d), Duration: %ds Target: %s", timems/1000, GetAbilityName(origId), origId, castTime/1000, tostring(targetName))

	HeavyAttackCharging = libint.directHeavyAttacks[origId] and origId or nil

	local lastQ = libint.lastQueuedAbilities[origId]
	libint.lastQueuedAbilities[origId] = nil

	if lastQ and lasttime then

		Print("events", "VERBOSE", "%s: act: %d, Q: %d, Diff: %d", lib.GetFormattedAbilityName(origId), timems-lasttime, timems-lastQ, lastQ - lasttime)

	end

	local skillExecution = lastQ and math.max(lastQ, lasttime) or lasttime
	local skillDelay = timems - skillExecution

	skillDelay = skillDelay < maxSkillDelay and skillDelay or nil

	if castTime > 0 then

		local status = channeled and LIBCOMBAT_SKILLSTATUS_BEGIN_CHANNEL or LIBCOMBAT_SKILLSTATUS_BEGIN_DURATION

		lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_SKILL_TIMINGS]), LIBCOMBAT_EVENT_SKILL_TIMINGS, timems, reducedslot, origId, status, skillDelay)

		local convertedId = libint.abilityConversions[origId] and libint.abilityConversions[origId][3] or abilityId

		libint.usedCastTimeAbility[convertedId] = true


	else

		local status = LIBCOMBAT_SKILLSTATUS_INSTANT

		lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_SKILL_TIMINGS]), LIBCOMBAT_EVENT_SKILL_TIMINGS, timems, reducedslot, origId, status, skillDelay)

	end
end

local function onAbilityFinished(eventCode, result, isError, abilityName, abilityGraphic, abilityActionSlotType, sourceName, sourceType, targetName, targetType, hitValue, powerType, damageType, log, sourceUnitId, targetUnitId, abilityId, overflow)

	local timems = GetGameTimeMilliseconds()

	local reducedslot = IdToReducedSlot[abilityId] or (libint.abilityAdditionsReverse[abilityId] and IdToReducedSlot[libint.abilityAdditionsReverse[abilityId]]) or nil

	local origId = GetReducedSlotId(reducedslot)

	local specialResult = libint.abilityConversions[origId] and libint.abilityConversions[origId][4] or false

	if (validSkillEndResults[result] ~= true and result ~= specialResult) or (abilityId == 46324 and hitValue > 1) then return end

	if libint.usedCastTimeAbility[abilityId] then

		Print("events","VERBOSE" ,"Skill finished: %s (%d, R: %d)", GetAbilityName(origId), origId, result)

		lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_SKILL_TIMINGS]), LIBCOMBAT_EVENT_SKILL_TIMINGS, timems, reducedslot, origId, LIBCOMBAT_SKILLSTATUS_SUCCESS)

	end
end

local function onQueueEvent(_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, abilityId)

	if libdata.inCombat == false then return end

	local timems = GetGameTimeMilliseconds()

	local conversion = libint.abilityConversions[abilityId]

	local convertedId = conversion and conversion[1] or abilityId

	local reducedslot = IdToReducedSlot[convertedId]

	if reducedslot == nil then

		Print("events","WARNING" ,"reducedslot missing on queue event: [%.3f s] %s (%d)", (timems - libint.currentfight.combatstart)/1000, GetAbilityName(abilityId), abilityId)
		return

	end

	libint.lastQueuedAbilities[abilityId] = timems

	lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_SKILL_TIMINGS]), LIBCOMBAT_EVENT_SKILL_TIMINGS, timems, reducedslot, abilityId, LIBCOMBAT_SKILLSTATUS_QUEUE)

end

local function onProjectileEvent(eventCode, result, isError, abilityName, abilityGraphic, abilityActionSlotType, sourceName, sourceType, targetName, targetType, hitValue, powerType, damageType, log, sourceUnitId, targetUnitId, abilityId, overflow)

	if hitValue == nil or hitValue <= 1 or targetType == COMBAT_UNIT_TYPE_PLAYER or libint.isProjectile[abilityId] == true then return end

	libint.isProjectile[abilityId] = true

	Print("events","VERBOSE" ,"[%.3f s] projectile: %s (%d)", (GetGameTimeMilliseconds() - libint.currentfight.combatstart)/1000, GetAbilityName(abilityId), abilityId)

	-- if IdToReducedSlot[abilityId] then libint.isProjectile[abilityId] = true end TODO: Check if this should be limited

end

local function onSkillSlotUsed(_, slot)

	if libdata.inCombat == false or slot > 8 then return end

	local timems = GetGameTimeMilliseconds()
	local abilityId = GetSlotBoundId(slot, GetActiveHotbarCategory())

	if libint.Events.Skills.active then

		local conversion = libint.abilityConversions[abilityId]

		local convertedId = conversion and conversion[1] or abilityId

		if HeavyAttackCharging == abilityId then

			onAbilityFinished(EVENT_COMBAT_EVENT, ACTION_RESULT_EFFECT_FADED, _, _, _, ACTION_SLOT_TYPE_HEAVY_ATTACK, _, _, _, _, _, _, _, _, _, _, convertedId)
			HeavyAttackCharging = nil

		else

			libint.lastAbilityActivations[convertedId] = timems
			HeavyAttackCharging = nil

			local reducedslot = (libdata.bar - 1) * 10 + slot

			lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_SKILL_TIMINGS]), LIBCOMBAT_EVENT_SKILL_TIMINGS, timems, reducedslot, abilityId, LIBCOMBAT_SKILLSTATUS_REGISTERED)

		end
	end
end

local function UpdateSkillEvents(self)

	for _, skill in pairs(SlotSkills) do

		local id, result, id2, result2 = unpack(skill)

		if not registeredSkills[id] then

			Print("events","VERBOSE", "Skill registered: %d: %s (%s), End:  %d: %s (%s))", id, GetAbilityName(id), tostring(result), id2 or 0, GetAbilityName(id2 or 0), tostring(result2))

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

local lastSkillBarUpdate = 0

local function GetCurrentSkillBarsDelayed()

	local timems = GetGameTimeMilliseconds()

	if timems - lastSkillBarUpdate < 400 then return end

	lastSkillBarUpdate = timems

	-- reregister skill

	zo_callLater(libfunc.GetCurrentSkillBars, 400) 	-- temporary workaround for NB skill Assasins Will

end

local function onSlotUpdate(_, slotNum)

	if slotNum == 1 or slotNum == 2 then return end

	GetCurrentSkillBarsDelayed()

end

libint.Events.Skills = libint.EventHandler:New(
	{LIBCOMBAT_EVENT_SKILL_TIMINGS},
	function (self)

		self:RegisterEvent(EVENT_COMBAT_EVENT, GetCurrentSkillBarsDelayed, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_EFFECT_GAINED, REGISTER_FILTER_ABILITY_ID, 24785) -- Overload & Morphs
		self:RegisterEvent(EVENT_COMBAT_EVENT, GetCurrentSkillBarsDelayed, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_EFFECT_GAINED, REGISTER_FILTER_ABILITY_ID, 24806) -- Overload & Morphs
		self:RegisterEvent(EVENT_COMBAT_EVENT, GetCurrentSkillBarsDelayed, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_EFFECT_GAINED, REGISTER_FILTER_ABILITY_ID, 24804) -- Overload & Morphs
		self:RegisterEvent(EVENT_ACTION_SLOT_UPDATED, onSlotUpdate)
		self:RegisterEvent(EVENT_COMBAT_EVENT, onQueueEvent, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_QUEUED, REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_PLAYER)
		self:RegisterEvent(EVENT_COMBAT_EVENT, onProjectileEvent, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_EFFECT_GAINED, REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_PLAYER)
		self:RegisterEvent(EVENT_ACTION_SLOT_ABILITY_USED, onSkillSlotUsed)

		self.Update = UpdateSkillEvents
		self:Update()

		self.active = true
		self.resetIds = true

	end
)
