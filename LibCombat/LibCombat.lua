--[[
This lib is supposed to act as a interface between the API of Eso and potential addons that want to display Combat Data (e.g. dps)
I extracted it from Combat Metrics, for which most of the functions are designed. I believe however that it's possible that others can use it.

Todo:
Falling Damage (also save routine!!)
Check what events fire on death
Implement tracking when players are resurrecting
implement group info function
work on the addon description
Add more debug Functions

]]

local lib = LibCombat
local libint = lib.internal
local libfunc = libint.functions
local libdata = lib.data
local EventHandler = libint.EventHandler
local Events = libint.Events

--aliases

local _
local Print = libint.Print
local CallbackKeys = lib.internal.callbackKeys
local reset = false
local timeout = 800
local GetFormattedAbilityName = lib.GetFormattedAbilityName
local activetimeonheals = true
local ActiveCallbackTypes = {}
libint.ActiveCallbackTypes = ActiveCallbackTypes
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

local registeredSkills = {}
libint.registeredSkills = registeredSkills

-- localize some functions for performance

local ZO_CachedStrFormat = ZO_CachedStrFormat

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

local FightHandler = ZO_Object:Subclass()

function FightHandler:New(...)
    local object = ZO_Object.New(self)
    object:Initialize(...)
    return object
end

function FightHandler:Initialize()
	self.char = libdata.playername
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
	self.group = libdata.inGroup
	self.playerid = libdata.playerid
	self.bosses = {}
	self.dataVersion = 2
	self.special = {}	-- for storing special information (like glacial presence before update 36)
end

function FightHandler:ResetFight()

	Print("dev", "INFO", "ResetFight")

	if libdata.inCombat ~= true then return end

	reset = true

	self:FinishFight()
	self:onUpdate()

	libint.currentfight:PrepareFight()

	libint.onCombatState(EVENT_PLAYER_COMBAT_STATE, IsUnitInCombat("player"))
end

function lib.ResetFight()
	libint.currentfight:ResetFight()
end


local function GetPlayerBuffs(timems)

	if Events.Effects.active == false then return end
	
	local newtime = timems

	if libdata.playerid == nil then

		zo_callLater(function() GetPlayerBuffs(timems) end, 100)
		return

	end

	libdata.critBonusMundus = 0

	for i=1,GetNumBuffs("player") do

		-- buffName, timeStarted, timeEnding, effectSlot, stackCount, iconFilename, buffType, effectType, abilityType, statusEffectType, abilityId, canClickOff, castByPlayer

		local _, _, endTime, effectSlot, stackCount, _, _, effectType, abilityType, _, abilityId, _, castByPlayer = GetUnitBuffInfo("player",i)

		Print("events","VERBOSE", "player has the %s %d x %s (%d, ET: %d, self: %s)", effectType == BUFF_EFFECT_TYPE_BUFF and "buff" or "debuff", stackCount, GetFormattedAbilityName(abilityId), abilityId, abilityType, tostring(castByPlayer))

		local unitType = castByPlayer and COMBAT_UNIT_TYPE_PLAYER or COMBAT_UNIT_TYPE_NONE

		local stacks = math.max(stackCount,1)

		local playerid = libdata.playerid

		if (not libint.badAbility[abilityId]) then

			lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_EFFECTS_IN]), LIBCOMBAT_EVENT_EFFECTS_IN, newtime, playerid, abilityId, EFFECT_RESULT_GAINED, effectType, stacks, unitType, effectSlot)
			--timems, unitId, abilityId, changeType, effectType, stacks, sourceType

		end

		if abilityId ==	13984 then libfunc.GetShadowBonus(effectSlot) end

		if abilityId ==	51176 then -- TFS workaround

			libfunc.onTFSChanged(_, EFFECT_RESULT_GAINED, _, _, _, _, _, stackCount)

		end
	end
end

local function GetOtherBuffs(timems)

	if Events.Effects.active == false then return end

	local newtime = timems

	for unitId, unitData in pairs(libint.EffectBuffer) do

		for abilityId, abilityData in pairs(unitData) do

			local endTime, logdata, abilityType = unpack(abilityData)

			logdata[2] = newtime
			local sourceType = logdata[8]

			if sourceType ~= COMBAT_UNIT_TYPE_PLAYER or abilityId ~= libint.abilityIdZen then lib.cm:FireCallbacks((CallbackKeys[logdata[1]]), unpack(logdata)) end

			if sourceType == COMBAT_UNIT_TYPE_PLAYER and (abilityId == libint.abilityIdZen or abilityType == ABILITY_TYPE_DAMAGE) then 

				local unit = libint.currentfight.units[unitId]
				if unit then unit:UpdateZenData(unpack(logdata), abilityType) end

			end
		end
	end
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

	local events = Events.Skills

	if not events.active then return end

	SlotSkills = {}

	local registeredIds = {}

	if libdata.skillBars == nil then libdata.skillBars = {} end

	for _, bar in pairs(libdata.skillBars) do

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

local function onPlayerActivated()

	Print("dev", "DEBUG", "onPlayerActivated")

	zo_callLater(GetCurrentSkillBars, 100)
	isInPortalWorld = false

	LibCombat_Save = LibCombat_Save or {}
	LibCombat_Save.UnitInfoResult = LibCombat_Save.UnitInfoResult or {}

end

local function onBossesChanged(_) -- Detect Bosses

	libdata.bossInfo = {}
	local bossdata = libdata.bossInfo

	for i = 1, 12 do

		local unitTag = ZO_CachedStrFormat("boss<<1>>", i)

		if DoesUnitExist(unitTag) then

			local name = GetUnitName(unitTag)

			bossdata[name] = i
			libint.currentfight.bossfight = true
			if libint.currentfight.bossname == nil and name ~= nil and name ~= "" then libint.currentfight.bossname = name end

		elseif i >= 2 then

			return

		end
	end
end

local function onGroupChange()

	libdata.inGroup = IsUnitGrouped("player")

	local groupdata = libdata.groupInfo

	groupdata.nameToDisplayname = {}
	groupdata.nameToTag = {}

	if libdata.inGroup == true then

		for i = 1, GetGroupSize() do

			local unitTag = "group"..i

			local name = ZO_CachedStrFormat(SI_UNIT_NAME, GetUnitName(unitTag))
			local displayname = ZO_CachedStrFormat(SI_UNIT_NAME, GetUnitDisplayName(unitTag))

			groupdata.nameToDisplayname[name] = displayname
			groupdata.nameToTag[name] = unitTag

			local unitId = groupdata.nameToId[name]
			local unit = unitId and libint.currentfight.units[unitId] or nil

			if unit then unit:UpdateGroupData() end
		end
	end
end

function FightHandler:GetMetaData()

	self.date = GetTimeStamp()
	self.time = GetTimeString()
	self.zone = GetPlayerActiveZoneName()
	self.subzone = GetPlayerActiveSubzoneName()
	self.zoneId = GetUnitWorldPosition("player")
	self.ESOversion = GetESOVersionString()
	self.APIversion = GetAPIVersion()
	self.account = libdata.accountname

	local charData = {}
	self.charData = charData

	charData.name = libdata.playername
	charData.raceId = GetUnitRaceId("player")
	charData.gender = GetUnitGender("player")
	charData.classId = GetUnitClassId("player")
	charData.level = GetUnitLevel("player")
	charData.CPtotal = GetUnitChampionPoints("player")

	self.CP = GetCurrentCP()

end

function FightHandler:PrepareFight()

	local timems = GetGameTimeMilliseconds()

	if self.prepared ~= true then

		Print("dev", "DEBUG", "PrepareFight")

		self.combatstart = timems

		libint.PurgeEffectBuffer(timems)

		FightHandler:GetMetaData()

		GetPlayerBuffs(timems)
		GetOtherBuffs(timems)

		libdata.resources[COMBAT_MECHANIC_FLAGS_HEALTH] = GetUnitPower("player", COMBAT_MECHANIC_FLAGS_HEALTH)
		libdata.resources[COMBAT_MECHANIC_FLAGS_MAGICKA] = GetUnitPower("player", COMBAT_MECHANIC_FLAGS_MAGICKA)
		libdata.resources[COMBAT_MECHANIC_FLAGS_STAMINA] = GetUnitPower("player", COMBAT_MECHANIC_FLAGS_STAMINA)
		libdata.resources[COMBAT_MECHANIC_FLAGS_ULTIMATE] = GetUnitPower("player", COMBAT_MECHANIC_FLAGS_ULTIMATE)

		libdata.backstabber = libfunc.GetCritBonusFromCP(self.CP)

		self.startBar = libdata.bar

		libdata.stats = {}
		libdata.advancedStats = {}
		lastQueuedAbilities = {}
		usedCastTimeAbility = {}

		lastBossHealthValue = 2

		self.isWipe = false

		libint.DamageShieldBuffer = {}

		self.prepared = true

		self:QueueStatUpdate(timems)
		GetCurrentSkillBars()
		onBossesChanged()

	end

	EVENT_MANAGER:RegisterForUpdate("LibCombat_update", 500, function() self:onUpdate() end)
end

local function GetSkillBars()

	local currentSkillBars = {}

	ZO_DeepTableCopy(libdata.skillBars, currentSkillBars)

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

	self.starttime = math.min(self.dpsstart or self.hpsstart or 0, self.hpsstart or self.dpsstart or 0)
	self.endtime = math.max(self.dpsend or 0, self.hpsend or 0)
	self.activetime = math.max((self.endtime - self.starttime) / 1000, 1)

	libint.EffectBuffer = {}

	lastAbilityActivations = {}
	isProjectile = {}

	Print("dev", "DEBUG", "FinishFight")
	Print("other", "DEBUG", "Number of Projectile data entries: %d", NonContiguousCount(isProjectile))

	libdata.lastabilities = {}
end


local lastGetNewStatsCall = 0

function FightHandler:QueueStatUpdate(timems)

	if Events.Stats.active ~= true then return end

	EVENT_MANAGER:UnregisterForUpdate("LibCombat_Stats")

	timems = timems or GetGameTimeMilliseconds()

	local lastcalldelta = timems - lastGetNewStatsCall

	if lastcalldelta < 100 then

		EVENT_MANAGER:RegisterForUpdate("LibCombat_Stats", (100 - lastcalldelta), function() self:QueueStatUpdate() end)

		return

	end

	lastGetNewStatsCall = timems

	libfunc.UpdateStats(timems)

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

	for unitId, UnitDeathCache in pairs(UnitDeathsToProcess) do

		if timems - UnitDeathCache.timems > 200 then

			Print("dev","INFO", "ProcessDeath: %s (%d)", libint.currentfight.units[unitId].name, unitId)
			UnitDeathCache:ProcessDeath()

		end

	end

end

function libint.ClearUnitCaches()

	Print("dev","INFO", "ClearUnitCaches (%d)", NonContiguousCount(CombatEventCache))

	for unitId, UnitDeathCache in pairs(CombatEventCache) do

		CombatEventCache[unitId] = nil

	end

	UnitDeathsToProcess = {}

end

function FightHandler:UpdateFightStats()

	ProcessDeathRecaps()

	if (self.dpsend == nil and self.hpsend == nil) or (self.dpsstart == nil and self.hpsstart == nil) then return end

	local dpstime = math.max(((self.dpsend or 1) - (self.dpsstart or 0)) / 1000, 1)
	local hpstime = math.max(((self.hpsend or 1) - (self.hpsstart or 0)) / 1000, 1)

	self.dpstime = dpstime
	self.hpstime = hpstime

	self:UpdateGrpStats()

	self.DPSOut = math.floor(self.damageOutTotal / dpstime + 0.5)
	self.HPSOut = math.floor(self.healingOutTotal / hpstime + 0.5)
	self.HPSAOut = math.floor(self.healingOutAbsolute / hpstime + 0.5)
	self.DPSIn = math.floor(self.damageInTotal / dpstime + 0.5)
	self.HPSIn = math.floor(self.healingInTotal / hpstime + 0.5)

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

	Print("dev", "DEBUG", "UpdateFightStats", self.damageOutTotal, dpstime)

end

function FightHandler:UpdateGrpStats() -- called by onUpdate

	if not (libdata.inGroup and Events.CombatGrp.active) then return end

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

	self.groupDPSOut = math.floor(self.groupDamageOut / dpstime + 0.5)
	self.groupDPSIn = math.floor(self.groupDamageIn / dpstime + 0.5)
	self.groupHPSOut = math.floor(self.groupHealingOut / hpstime + 0.5)

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

	if isInPortalWorld then -- prevent fight reset in bossfights when using a portal.

		Print("other","DEBUG", "Prevented combat reset because player is in Portal!")
		return true

	elseif getCurrentBossHP() > 0 and getCurrentBossHP() < 1 then

		Print("other","INFO", "Prevented combat reset because boss is still in fight!")
		return true

	else

		return false

	end
end

function FightHandler:onUpdate()

	libint.onCombatState(EVENT_PLAYER_COMBAT_STATE, IsUnitInCombat("player"))

	--reset data
	if reset == true or (libdata.inCombat == false and self.combatend > 0 and (GetGameTimeMilliseconds() > (self.combatend + timeout)) ) then

		reset = false

		self:UpdateFightStats()

		if self.damageOutTotal>0 or self.healingOutTotal>0 or self.damageInTotal>0 then

			Print("fight","DEBUG", "Time: %.2fs (DPS) | %.2fs (HPS) ", self.dpstime, self.hpstime)
			Print("fight","DEBUG", "Dmg: %d (DPS: %d)", self.damageOutTotal, self.DPSOut)
			Print("fight","DEBUG", "Heal: %d (HPS: %d)", self.healingOutTotal, self.HPSOut)
			Print("fight","DEBUG", "IncDmg: %d (Shield: %d, IncDPS: %d)", self.damageInTotal, self.damageInShielded, self.DPSIn)
			Print("fight","DEBUG", "IncHeal: %d (IncHPS: %d)", self.healingInTotal, self.HPSIn)

			if libdata.inGroup and Events.CombatGrp.active then

				Print("fight","DEBUG", "GrpDmg: %d (DPS: %d)", self.groupDamageOut, self.groupDPSOut)
				Print("fight","DEBUG", "GrpHeal: %d (HPS: %d)", self.groupHealingOut, self.groupHPSOut)
				Print("fight","DEBUG", "GrpIncDmg: %d (IncDPS: %d)", self.groupDamageIn, self.groupDPSIn)

			end
		end

		Print("fight","DEBUG", "resetting...")

		self.grplog = {}

		lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_FIGHTSUMMARY]), LIBCOMBAT_EVENT_FIGHTSUMMARY, self)

		libint.currentfight = FightHandler:New()
		libint.ClearUnitCaches()

		EVENT_MANAGER:UnregisterForUpdate("LibCombat_update")

	elseif libdata.inCombat == true then

		self:UpdateFightStats()

	end

end

local UnitDeathCacheHandler = ZO_Object:Subclass()	-- holds all recent events + info to send on death

function UnitDeathCacheHandler:New(...)
    local object = ZO_Object.New(self)
    object:Initialize(...)
    return object
end

function UnitDeathCacheHandler:Initialize(unitId)

	self.nextKey = 1
	self.maxlength = maxUnitCacheEvents
	self.cache = {}
	self.unitId = unitId

	CombatEventCache[unitId] = self

	if not libint.debug then return end

	local unitname = libint.currentfight.units[unitId] and libint.currentfight.units[unitId].name or "Unknown"

	Print("dev","INFO", "Init unit death cache: %s (%d)", unitname, unitId)

end

function UnitDeathCacheHandler:OnDeath(timems)

	self.timems = timems

	UnitDeathsToProcess[self.unitId] = self

	if not libint.debug then return end

	local unitname = libint.currentfight.units[self.unitId] and libint.currentfight.units[self.unitId].name or "Unknown"

	Print("dev","INFO", "UnitCacheHandler:OnDeath: %s (%d)", unitname, self.unitId)

end

function UnitDeathCacheHandler:ProcessDeath()

	local unit = libint.currentfight.units[self.unitId]

	if unit then ZO_ShallowTableCopy(unit:GetUnitInfo(), self) end

	self.bossname = libint.currentfight.bossname
	self.zoneId = libint.currentfight.zoneId
	self.fighttime = libint.currentfight.date
	self.combatstart = libint.currentfight.combatstart

	self.log = {}
	local cache = self.cache

	if #cache > 0 then

		local log = self.log
		local offset = self.nextKey - 1
		local length = #self.cache
		local timems = self.timems

		local deleted = 0

		Print("dev","INFO", "Processing death event cache. Offset: %d, length:%d", offset, length)

		for i = 0, length - 1 do

			local cachekey = (i + offset)%length + 1
			local data = cache[cachekey]

			if timems - data[1] < deathRecapTimePeriod then

				log[#log + 1] = data
				local sourceUnitId = data[3]
				local sourceUnit = sourceUnitId and sourceUnitId>0 and libint.currentfight and libint.currentfight.units and libint.currentfight.units[sourceUnitId] or "nil"
				--sourceUnitId == location ??
				data[3] = (sourceUnit and sourceUnit.name) or "Unknown"

				if data[10] and self.magickaMax and data[10] > self.magickaMax then self.magickaMax = data[10] end
				if data[11] and self.staminaMax and data[11] > self.staminaMax then self.staminaMax = data[11] end

			else

				deleted = deleted + 1

			end
		end

		Print("dev","INFO" , "%s: cache: %d, log: %d, deleted: %d", unit and unit.name or "Unknown", #cache, #log, deleted)
	end

	self.cache = nil
	self.health = nil
	self.stamina = nil
	self.magicka = nil
	self.nextKey = nil
	self.maxlength = nil

	lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_DEATHRECAP]), LIBCOMBAT_EVENT_DEATHRECAP, self.timems, self)

	UnitDeathCacheHandler:New(self.unitId)
	UnitDeathsToProcess[self.unitId] = nil
end

function UnitDeathCacheHandler:AddEvent(timems, result, sourceUnitId, abilityId, hitValue, damageType, overflow)

	if self.health == nil then self:InitResources() end

	local nextKey = self.nextKey

	self.cache[nextKey] = {timems, result, sourceUnitId, abilityId, damageType, hitValue, overflow, self.health, self.healthMax, self.magicka, self.stamina}

	self.nextKey = (nextKey % self.maxlength) + 1

	self.timems = timems

end

function UnitDeathCacheHandler:InitResources()

	local unit = libint.currentfight.units[self.unitId]

	if unit then

		local unitTag = unit.unitTag

		self.health, self.healthMax = GetUnitPower(unitTag, COMBAT_MECHANIC_FLAGS_HEALTH)

		if unitTag == "player" then

			self.magicka = GetUnitPower(unitTag, COMBAT_MECHANIC_FLAGS_MAGICKA)
			self.stamina = GetUnitPower(unitTag, COMBAT_MECHANIC_FLAGS_STAMINA)

		end
	end
end

function UnitDeathCacheHandler:UpdateResource(powerType, value, powerMax)

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

	if unitCache == nil then unitCache = UnitDeathCacheHandler:New(unitId) end

	return unitCache

end

-- Event Functions

function libint.onCombatState(event, inCombat)  -- Detect Combat Stage, local is defined above - Don't Change !!!

	if inCombat ~= libdata.inCombat then     -- Check if player state changed

		local timems = GetGameTimeMilliseconds()

		if inCombat then

			libdata.inCombat = inCombat

			Print("fight","DEBUG", "Entering combat.")

			lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_MESSAGES]), LIBCOMBAT_EVENT_MESSAGES, timems, LIBCOMBAT_MESSAGE_COMBATSTART, 0)

			libint.currentfight:PrepareFight()

		else

			if IsOngoingBossfight() then

				Print("fight","INFO", "Failed: Leaving combat.")
				return

			end

			libdata.inCombat = false

			Print("fight","DEBUG", "Leaving combat.")

			libint.currentfight:FinishFight()

			if libint.currentfight.charData == nil then return end

			lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_MESSAGES]), LIBCOMBAT_EVENT_MESSAGES, timems, LIBCOMBAT_MESSAGE_COMBATEND, 0)

		end
	end
end

-- Buffs/Debuffs

--(eventCode, changeType, effectSlot, effectName, unitTag, beginTime, endTime, stackCount, iconName, buffType, effectType, abilityType, statusEffectType, unitName, unitId, abilityId, sourceType)

local function onPortalWorld( _, changeType)

	isInPortalWorld = changeType == EFFECT_RESULT_GAINED
	onBossesChanged()

end

local function onMageExplode( _, changeType, effectSlot, _, unitTag, _, endTime, stackCount, _, _, effectType, abilityType, _, unitName, unitId, abilityId, sourceType)

	libint.currentfight:ResetFight()	-- special tracking for The Mage in Aetherian Archives. It will reset the fight when the mage encounter starts.

end

local function checkLastAbilities(powerType, powerValueChange)

	local lastabilities = libdata.lastabilities

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
	if (powerType ~= COMBAT_MECHANIC_FLAGS_HEALTH and powerType ~= COMBAT_MECHANIC_FLAGS_MAGICKA and powerType ~= COMBAT_MECHANIC_FLAGS_STAMINA and powerType ~= COMBAT_MECHANIC_FLAGS_ULTIMATE) or (libdata.inCombat == false) then return end

	local timems = GetGameTimeMilliseconds()
	local aId

	local powerValueChange = powerValue - (libdata.resources[powerType] or powerValue)
	libdata.resources[powerType] = powerValue

	if powerValueChange == 0 then return end

	if powerType == COMBAT_MECHANIC_FLAGS_MAGICKA then

		Print("events","VERBOSE", "Skill cost: %d", powerValueChange)

		aId = checkLastAbilities(powerType, powerValueChange)

		if aId == -1 and powerValueChange == libfunc.GetStat(STAT_MAGICKA_REGEN_COMBAT) then

			aId = 0

		end

	elseif powerType == COMBAT_MECHANIC_FLAGS_STAMINA then

		aId = checkLastAbilities(powerType, powerValueChange)

		if powerValueChange == libfunc.GetStat(STAT_STAMINA_REGEN_COMBAT) and aId == -1 then

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

	elseif powerType == COMBAT_MECHANIC_FLAGS_ULTIMATE then

		aId = 0

	elseif powerType == COMBAT_MECHANIC_FLAGS_HEALTH then

		aId = -1

		if powerValueChange == libfunc.GetStat(STAT_HEALTH_REGEN_COMBAT) and libdata.playerid then

			aId = 0

			lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_HEAL_SELF]), LIBCOMBAT_EVENT_HEAL_SELF, timems, ACTION_RESULT_HOT_TICK, libdata.playerid, libdata.playerid, aId, powerValueChange, powerType, 0)
			return

		end
	end

	lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_RESOURCES]), LIBCOMBAT_EVENT_RESOURCES, timems, aId, powerValueChange, powerType, powerValue)
end

--(eventCode, result, isError, abilityName, abilityGraphic, abilityActionSlotType, sourceName, sourceType, targetName, targetType, hitValue, powerType, damageType, log, sourceUnitId, targetUnitId, abilityId, overflow)
local function onResourceChanged (_, result, _, _, _, _, _, _, targetName, _, powerValueChange, powerType, _, _, sourceUnitId, targetUnitId, abilityId)

	local lastabilities = libdata.lastabilities

	if libdata.playerid == nil and targetName == libdata.rawPlayername then libdata.playerid = targetUnitId end

	local timems = GetGameTimeMilliseconds()

	if (powerType ~= 0 and powerType ~= 6) or libdata.inCombat == false or powerValueChange < 1 then return end

	if result == ACTION_RESULT_POWER_DRAIN then powerValueChange = -powerValueChange end

	table.insert(lastabilities,{timems, abilityId, powerValueChange, powerType})

	if #lastabilities > 10 then table.remove(lastabilities, 1) end
end

local function onWeaponSwap(_, isHotbarSwap)

	local newbar = GetActiveHotbarCategory() + 1

	if libdata.bar == newbar then return end

	libdata.bar = newbar

	GetCurrentSkillBars()

	local inCombat = libint.currentfight.prepared

	if inCombat == true then

		local timems = GetGameTimeMilliseconds()
		lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_MESSAGES]), LIBCOMBAT_EVENT_MESSAGES, timems, LIBCOMBAT_MESSAGE_WEAPONSWAP, libdata.bar)

		libint.currentfight:QueueStatUpdate(timems)

	end
end

local function CheckForWipe()

	if not IsUnitDeadOrReincarnating("player") then return end -- maybe it's enough if player is dead on combat end? (Unless it bugs, like Sunspire ... ¯\_(ツ)_/¯)

	if libdata.inGroup == false then

		libint.currentfight.isWipe = true

	elseif libdata.inGroup == true then

		local loc = GetUnitZoneIndex("player")

		for i = 1, GetGroupSize() do

			local tag = ZO_CachedStrFormat("group<<1>>", i)

			local unitId = libdata.groupInfo.tagToId[tag]
			local unit = unitId and libint.currentfight.units[unitId]

			if unit and (not unit.isDead) and GetUnitZoneIndex(tag) == loc then return end	-- if there is a group member in the zame zone but not dead then it's not a wipe

		end
	end

	libint.currentfight.isWipe = true

	Print("DoA","DEBUG", "=== This is a wipe ! ===")

end

local function OnDeathStateChanged(_, unitTag, isDead) 	-- death (for group display, also works for different zones)

	local unitId = unitTag == "player" and libdata.playerid or libdata.groupInfo.tagToId[unitTag]

	Print("dev","INFO", "OnDeathStateChanged: %s (%s) is dead: %s", unitTag, tostring(unitId), tostring(isDead))

	if libdata.inCombat == false or unitId == nil then

		Print("dev","INFO", "OnDeathStateChanged: Combat: %s", tostring(libdata.inCombat))
		return
	end

	local unit = libint.currentfight.units[unitId]
	if unit then unit.isDead = isDead else

		Print("dev","INFO", "OnDeathStateChanged: no unit")
		return
	end

	local timems = GetGameTimeMilliseconds()

	if isDead then

		local lasttime = lastdeaths[unitId]

		if (lasttime and lasttime - timems < 1000) then return end

		GetUnitCache(unitId):OnDeath(timems)

		Print("dev","INFO", "OnDeathStateChanged: fire callback")
		lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_DEATH]), LIBCOMBAT_EVENT_DEATH, timems, LIBCOMBAT_STATE_DEAD, unitId)

		CheckForWipe()

	else

		lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_DEATH]), LIBCOMBAT_EVENT_DEATH, timems, LIBCOMBAT_STATE_ALIVE, unitId)

	end
end

local function OnPlayerReincarnated()

	Print("DoA","DEBUG", "You revived")

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

	local unitdata = libint.currentfight.units[targetUnitId]

	if unitdata == nil or (unitdata.unitType ~= COMBAT_UNIT_TYPE_PLAYER and unitdata.unitType ~= COMBAT_UNIT_TYPE_GROUP) then return end

	Print("dev","INFO", "OnDeath (%s): %s (%d, %d) / %s (%d, %d) - %s (%d): %d (o: %d, type: %d)", SpecialResults[result], sourceName, sourceUnitId, sourceType, targetName, targetUnitId, targetType, GetFormattedAbilityName(abilityId), abilityId, hitValue or 0, overflow or 0, damageType or 0)

	lastdeaths[targetUnitId] = timems

	GetUnitCache(targetUnitId):OnDeath(timems)

	lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_DEATH]), LIBCOMBAT_EVENT_DEATH, timems, LIBCOMBAT_STATE_DEAD, targetUnitId, abilityId)

	CheckForWipe()
end

local function OnResurrect(_, result, _, abilityName, _, abilityActionSlotType, sourceName, sourceType, targetName, targetType, hitValue, powerType, damageType, _, sourceUnitId, targetUnitId, abilityId)

	Print("dev","INFO", "OnResurrect (%s): %s (%d, %d) / %s (%d, %d) - %s (%d): %d (type: %d)", SpecialResults[result], sourceName, sourceUnitId, sourceType, targetName, targetUnitId, targetType, GetFormattedAbilityName(abilityId), abilityId, hitValue or 0, damageType or 0)

	local timems = GetGameTimeMilliseconds()

	if targetUnitId == nil or targetUnitId == 0 or libdata.inCombat == false then return end

	local unitdata = libint.currentfight.units[targetUnitId]

	if unitdata == nil or unitdata.type ~= COMBAT_UNIT_TYPE_GROUP then return end

	lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_DEATH]), LIBCOMBAT_EVENT_DEATH, timems, LIBCOMBAT_STATE_ALIVE, targetUnitId)
end

local function OnResurrectResult(_, targetCharacterName, result, targetDisplayName)

	Print("DoA","DEBUG", "OnResurrectResult: %s", targetCharacterName)

	local timems = GetGameTimeMilliseconds()

	if result ~= RESURRECT_RESULT_SUCCESS then return end

	local name = ZO_CachedStrFormat(SI_UNIT_NAME, targetCharacterName) or ""

	local unitId = libdata.groupInfo.nameToId[name]

	if not unitId then return end

	lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_DEATH]), LIBCOMBAT_EVENT_DEATH, timems, LIBCOMBAT_STATE_RESURRECTED, unitId, libdata.playerid)

end

local function OnResurrectRequest(_, requesterCharacterName, timeLeftToAccept, requesterDisplayName)

	Print("DoA","DEBUG", "OnResurrectRequest: %s", requesterCharacterName)

	local timems = GetGameTimeMilliseconds()

	local name = ZO_CachedStrFormat(SI_UNIT_NAME, requesterCharacterName) or ""

	local unitId = libdata.groupInfo.nameToId[name]

	if not unitId then return end

	lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_DEATH]), LIBCOMBAT_EVENT_DEATH, timems, LIBCOMBAT_STATE_RESURRECTED, libdata.playerid, unitId)

end

local function onWTF(_, result, _, abilityName, _, abilityActionSlotType, sourceName, sourceType, targetName, targetType, hitValue, powerType, damageType, _, sourceUnitId, targetUnitId, abilityId)

	local resulttext = SpecialResults[result] or tostring(result)

	Print("other","VERBOSE", "onWTF (%s): %s (%d, %d) / %s (%d, %d) - %s (%d): %d (type: %d)", resulttext, sourceName, sourceUnitId, sourceType, targetName, targetUnitId, targetType, GetFormattedAbilityName(abilityId), abilityId, hitValue or 0, damageType or 0)

end

local function GroupCombatEventHandler(isheal, result, _, abilityName, _, _, sourceName, sourceType, targetName, _, hitValue, powerType, damageType, _, sourceUnitId, targetUnitId, abilityId, overflow)  -- called by Event

	if (hitValue + (overflow or 0)) < 0 or (not (targetUnitId > 0)) or (libdata.inCombat == false and (result==ACTION_RESULT_DOT_TICK_CRITICAL or result==ACTION_RESULT_DOT_TICK or isheal) ) then return end -- only record if both unitids are valid or player is in combat or a non dot damage action happens

	local timems = GetGameTimeMilliseconds()

	if libint.currentfight.prepared ~= true then libint.currentfight:PrepareFight() end -- get stats before the damage event

	damageType = (isheal and powerType) or damageType

	GetUnitCache(targetUnitId):AddEvent(timems, result, sourceUnitId, abilityId, hitValue, damageType, overflow or 0)

	if overflow and overflow > 0 and not isheal then

		Print("dev","INFO", "GroupCombatEventHandler: %s has overflow damage!", targetName)
		GetUnitCache(targetUnitId):OnDeath(timems)

	end

end

local function onCombatEventGrpDmgIn(event, ...)

	local targetUnitId = select(15, ...)

	local unit = libint.currentfight.units[targetUnitId]
	local targetType = unit and unit.unitType or nil

	if not targetType or (targetType ~= COMBAT_UNIT_TYPE_GROUP and targetType ~= COMBAT_UNIT_TYPE_PLAYER) then return end

	GroupCombatEventHandler(false, ...)

end

local function onCombatEventGrpHealIn(event, ...)

	local targetUnitId = select(15, ...)

	local unit = libint.currentfight.units[targetUnitId]
	local targetType = unit and unit.unitType or nil

	if not targetType or (targetType ~= COMBAT_UNIT_TYPE_GROUP and targetType ~= COMBAT_UNIT_TYPE_PLAYER) then return end

	GroupCombatEventHandler(true, ...)

end

local function onBaseResourceChangedGroup(event, unitTag, powerIndex, powerType, powerValue, powerMax, powerEffectiveMax)

	local unitId = unitTag == "player" and libdata.playerid or libdata.groupInfo.tagToId[unitTag]

	if unitId then GetUnitCache(unitId):UpdateResource(powerType, powerValue, powerMax) end

end

local function GetReducedSlotId(reducedslot)

	local bar = math.floor(reducedslot/10) + 1

	local slot = reducedslot%10

	local origId = (libdata.skillBars and libdata.skillBars[bar] and libdata.skillBars[bar][slot])

	return origId

end

local HeavyAttackCharging

local function onAbilityUsed(eventCode, result, isError, abilityName, abilityGraphic, abilityActionSlotType, sourceName, sourceType, targetName, targetType, hitValue, powerType, damageType, log, sourceUnitId, targetUnitId, abilityId, overflow)

	if Events.Skills.active ~= true or libdata.inCombat == false or not (validSkillStartResults[result] or (validNonProjectileSkillStartResults[result] and not isProjectile[abilityId])) then return end

	local timems = GetGameTimeMilliseconds()

	local lasttime = lastAbilityActivations[abilityId]
	if lasttime == nil or (timems - lasttime) > maxSkillDelay then return end

	lastAbilityActivations[abilityId] = nil

	local reducedslot = IdToReducedSlot[abilityId] or (abilityAdditionsReverse[abilityId] and IdToReducedSlot[abilityAdditionsReverse[abilityId]]) or nil

	local origId = GetReducedSlotId(reducedslot)

	local channeled, castTime, channelTime = GetAbilityCastInfo(origId)

	castTime = channeled and channelTime or castTime

	Print("events","VERBOSE", "[%.3f] Skill fired: %s (%d), Duration: %ds Target: %s", timems/1000, GetAbilityName(origId), origId, castTime/1000, tostring(targetName))

	HeavyAttackCharging = DirectHeavyAttacks[origId] and origId or nil

	local lastQ = lastQueuedAbilities[origId]
	lastQueuedAbilities[origId] = nil

	if lastQ and lasttime then

		Print("events","VERBOSE", "%s: act: %d, Q: %d, Diff: %d", GetFormattedAbilityName(origId), timems-lasttime, timems-lastQ, lastQ - lasttime)

	end

	local skillExecution = lastQ and math.max(lastQ, lasttime) or lasttime
	local skillDelay = timems - skillExecution

	skillDelay = skillDelay < maxSkillDelay and skillDelay or nil

	if castTime > 0 then

		local status = channeled and LIBCOMBAT_SKILLSTATUS_BEGIN_CHANNEL or LIBCOMBAT_SKILLSTATUS_BEGIN_DURATION

		lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_SKILL_TIMINGS]), LIBCOMBAT_EVENT_SKILL_TIMINGS, timems, reducedslot, origId, status, skillDelay)

		local convertedId = libint.abilityConversions[origId] and libint.abilityConversions[origId][3] or abilityId

		usedCastTimeAbility[convertedId] = true


	else

		local status = LIBCOMBAT_SKILLSTATUS_INSTANT

		lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_SKILL_TIMINGS]), LIBCOMBAT_EVENT_SKILL_TIMINGS, timems, reducedslot, origId, status, skillDelay)

	end
end

local function onAbilityFinished(eventCode, result, isError, abilityName, abilityGraphic, abilityActionSlotType, sourceName, sourceType, targetName, targetType, hitValue, powerType, damageType, log, sourceUnitId, targetUnitId, abilityId, overflow)

	local timems = GetGameTimeMilliseconds()

	local reducedslot = IdToReducedSlot[abilityId] or (abilityAdditionsReverse[abilityId] and IdToReducedSlot[abilityAdditionsReverse[abilityId]]) or nil

	local origId = GetReducedSlotId(reducedslot)

	local specialResult = libint.abilityConversions[origId] and libint.abilityConversions[origId][4] or false

	if (validSkillEndResults[result] ~= true and result ~= specialResult) or (abilityId == 46324 and hitValue > 1) then return end

	if usedCastTimeAbility[abilityId] then

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

	lastQueuedAbilities[abilityId] = timems

	lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_SKILL_TIMINGS]), LIBCOMBAT_EVENT_SKILL_TIMINGS, timems, reducedslot, abilityId, LIBCOMBAT_SKILLSTATUS_QUEUE)

end

local function onProjectileEvent(eventCode, result, isError, abilityName, abilityGraphic, abilityActionSlotType, sourceName, sourceType, targetName, targetType, hitValue, powerType, damageType, log, sourceUnitId, targetUnitId, abilityId, overflow)

	if hitValue == nil or hitValue <= 1 or targetType == COMBAT_UNIT_TYPE_PLAYER or isProjectile[abilityId] == true then return end

	isProjectile[abilityId] = true

	Print("events","VERBOSE" ,"[%.3f s] projectile: %s (%d)", (GetGameTimeMilliseconds() - libint.currentfight.combatstart)/1000, GetAbilityName(abilityId), abilityId)

	-- if IdToReducedSlot[abilityId] then isProjectile[abilityId] = true end TODO: Check if this should be limited

end

local powerTypeCache = {}

local function GetPowerTypes(abilityId)

	local lastPowerType

	if powerTypeCache[abilityId] == nil then

		local newData = {}

		for i = 1, 4 do

			local powerType = GetNextAbilityMechanicFlag(abilityId)

			if powerType and (powerType == COMBAT_MECHANIC_FLAGS_HEALTH or powerType == COMBAT_MECHANIC_FLAGS_MAGICKA or powerType == COMBAT_MECHANIC_FLAGS_STAMINA) then

				newData[powerType] = GetAbilityCost(abilityId,powerType)	-- add cost over time ??

			elseif powerType == nil then

				break

			end
		end

		powerTypeCache[abilityId] = newData
	end

	return powerTypeCache[abilityId]
end

local function onSlotUsed(_, slot)

	if libdata.inCombat == false or slot > 8 then return end

	local timems = GetGameTimeMilliseconds()
	local abilityId = GetSlotBoundId(slot, GetActiveHotbarCategory())
	local powerTypes = GetPowerTypes(abilityId)
	local lastabilities = libdata.lastabilities

	if Events.Resources.active and slot > 2 and #powerTypes > 0 then

		for powerType, cost in pairs(powerTypes) do

			table.insert(lastabilities,{timems, abilityId, -cost, powerType})

		end

		if #lastabilities > 10 then table.remove(lastabilities, 1) end

	end

	if Events.Skills.active then

		local conversion = libint.abilityConversions[abilityId]

		local convertedId = conversion and conversion[1] or abilityId

		if HeavyAttackCharging == abilityId then

			onAbilityFinished(EVENT_COMBAT_EVENT, ACTION_RESULT_EFFECT_FADED, _, _, _, ACTION_SLOT_TYPE_HEAVY_ATTACK, _, _, _, _, _, _, _, _, _, _, convertedId)
			HeavyAttackCharging = nil

		else

			lastAbilityActivations[convertedId] = timems
			HeavyAttackCharging = nil

			local reducedslot = (libdata.bar - 1) * 10 + slot

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

	local active = EVENT_MANAGER:RegisterForUpdate("LibCombat_Frames", 0, onFrameUpdate)

	EVENT_MANAGER:UnregisterForUpdate("LibCombat_Frames_Enable")

end

local function onPlayerActivated2()

	EVENT_MANAGER:RegisterForUpdate("LibCombat_Frames_Enable", playerActivatedTime , enableLogging)

end

local function onPlayerDeactivated()
	EVENT_MANAGER:UnregisterForUpdate("LibCombat_Frames")
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

local function InitCallbackIndex()

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

	if libint.currentfight.dpsstart ~= nil then

		ZO_DeepTableCopy(libint.currentfight, copy)

	else

		copy = nil

	end

	return copy
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

Events.General = EventHandler:New(
	libint.GetAllCallbackTypes(),
	function (self)

		self:RegisterEvent(EVENT_PLAYER_COMBAT_STATE, libint.onCombatState)
		self:RegisterEvent(EVENT_BOSSES_CHANGED, onBossesChanged)

		self:RegisterEvent(EVENT_GROUP_UPDATE, onGroupChange)
		self:RegisterEvent(EVENT_HOTBAR_SLOT_CHANGE_REQUESTED, GetCurrentSkillBars)
		self:RegisterEvent(EVENT_PLAYER_ACTIVATED, onPlayerActivated)
		self:RegisterEvent(EVENT_PLAYER_ACTIVATED, onGroupChange)
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onMageExplode, REGISTER_FILTER_ABILITY_ID, 50184)
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onPortalWorld, REGISTER_FILTER_ABILITY_ID, 108045)
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onPortalWorld, REGISTER_FILTER_ABILITY_ID, 121216)
		self:RegisterEvent(EVENT_COMBAT_EVENT, lib.internal.onUnitCombatEvent)


		if libint.debug == true then

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

		end

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

local function Initialize()

	Print("dev", "DEBUG", "Initialize")

	libdata.inCombat = IsUnitInCombat("player")
	libdata.inGroup = IsUnitGrouped("player")
	libdata.rawPlayername = GetRawUnitName("player")
	libdata.playername = ZO_CachedStrFormat(SI_UNIT_NAME, libdata.rawPlayername)
	libdata.accountname = ZO_CachedStrFormat(SI_UNIT_NAME, GetDisplayName())
	libdata.bossInfo = {}
	libdata.groupInfo = {nameToId = {}, tagToId = {}, nameToTag = {}, nameToDisplayname = {}}
	libdata.PlayerPets = {}
	libdata.lastabilities = {}
	libdata.backstabber = 0
	libdata.critBonusMundus = 0
	libdata.bar = GetActiveWeaponPairInfo()
	libdata.resources = {}
	libdata.stats = {}
	libdata.advancedStats = {}

	--resetfightdata
	libint.currentfight = FightHandler:New()

	InitCallbackIndex()

	onBossesChanged()

	libfunc.InitAdvancedStats()

	EVENT_MANAGER:RegisterForEvent("LibCombatActive", EVENT_PLAYER_ACTIVATED, function() libdata.isUIActivated = true end)
	EVENT_MANAGER:RegisterForEvent("LibCombatActive", EVENT_PLAYER_DEACTIVATED, function() libdata.isUIActivated = false end)
end

Initialize()
