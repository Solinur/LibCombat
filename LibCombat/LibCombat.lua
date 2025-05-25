--[[ Main addon file (loaded last)
This lib is supposed to act as a interface between the API of Eso and potential addons that want to display Combat Data (e.g. dps)
I extracted it from Combat Metrics, for which most of the functions are designed. I believe however that it's possible that others can use it.

Todo:
Falling Damage (also save routine!!)
Check what events fire on death
Implement tracking when players are resurrecting
Implement group info function
Work on the addon description
Add more debug Functions

]]

local lib = LibCombat
local libint = lib.internal
local ld = libint.data
local libunits = ld.units
local lf = libint.functions
local EventHandler = libint.EventHandler
local Events = libint.Events

--aliases

local _
local logger
local CallbackKeys = libint.callbackKeys
local reset = false
local timeout = 800
local GetFormattedAbilityName = lib.GetFormattedAbilityName
local activetimeonheals = true
local ActiveCallbackTypes = {}
libint.ActiveCallbackTypes = ActiveCallbackTypes
libint.isProjectile = {}
libint.isInPortalWorld = false	-- used to prevent fight reset in Cloudrest/Sunspire when using a portal.

local lastBossHealthValue = 2

libint.lastQueuedAbilities = {}
libint.usedCastTimeAbility = {}

-- localize some functions for performance

local ZO_CachedStrFormat = ZO_CachedStrFormat

local FightHandler = ZO_Object:Subclass()

---@diagnostic disable-next-line: duplicate-set-field
function FightHandler:New(...)
    local object = ZO_Object.New(self)
    object:Initialize(...)
    return object
end

function FightHandler:Initialize()
	self.char = libunits.playername
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
	self.group = libunits.inGroup
	self.playerId = libunits.playerId
	self.bosses = {}
	self.dataVersion = 2
	self.special = {}	-- for storing special information (like glacial presence before update 36)
end

function FightHandler:ResetFight()

	logger:Info("Reset Fight")

	if ld.inCombat ~= true then return end

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

	if libunits.playerId == nil then

		zo_callLater(function() GetPlayerBuffs(timems) end, 100)
		return

	end

	ld.critBonusMundus = 0

	for i=1,GetNumBuffs("player") do

		-- buffName, timeStarted, timeEnding, effectSlot, stackCount, iconFilename, buffType, effectType, abilityType, statusEffectType, abilityId, canClickOff, castByPlayer

		local _, _, endTime, effectSlot, stackCount, _, _, effectType, abilityType, _, abilityId, _, castByPlayer = GetUnitBuffInfo("player",i)

		logger:Verbose("player has the %s %d x %s (%d, ET: %d, self: %s)", effectType == BUFF_EFFECT_TYPE_BUFF and "buff" or "debuff", stackCount, GetFormattedAbilityName(abilityId), abilityId, abilityType, tostring(castByPlayer))

		local unitType = castByPlayer and COMBAT_UNIT_TYPE_PLAYER or COMBAT_UNIT_TYPE_NONE

		local stacks = zo_max(stackCount,1)

		local playerId = libunits.playerId

		if (not libint.badAbility[abilityId]) then

			lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_EFFECTS_IN]), LIBCOMBAT_EVENT_EFFECTS_IN, newtime, playerId, abilityId, EFFECT_RESULT_GAINED, effectType, stacks, unitType, effectSlot)
			--timems, unitId, abilityId, changeType, effectType, stacks, sourceType

		end

		if abilityId ==	13984 then lf.GetShadowBonus(effectSlot) end

		if abilityId ==	51176 then -- TFS workaround

			lf.onTFSChanged(_, EFFECT_RESULT_GAINED, _, _, _, _, _, stackCount)

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

			if sourceType == COMBAT_UNIT_TYPE_PLAYER and libint.StatusEffectIds[abilityId] then

				local unit = libint.currentfight.units[unitId]
				if unit then unit:UpdateForceOfNatureData((CallbackKeys[logdata[1]]), unpack(logdata)) end

			end
		end
	end
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


function lf.onPlayerActivated()

	logger:Debug("onPlayerActivated")

	zo_callLater(lf.GetCurrentSkillBars, 100)
	libint.isInPortalWorld = false

	LibCombat_Save = LibCombat_Save or {}
	LibCombat_Save.UnitInfoResult = LibCombat_Save.UnitInfoResult or {}

end

local function onBossesChanged(_) -- Detect Bosses

	ld.bossInfo = {}
	local bossdata = ld.bossInfo

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

function FightHandler:GetMetaData()
	self.date = GetTimeStamp()
	self.time = GetTimeString()
	self.zone = GetPlayerActiveZoneName()
	self.subzone = GetPlayerActiveSubzoneName()
	self.zoneId = GetUnitWorldPosition("player")
	self.ESOversion = GetESOVersionString()
	self.APIversion = GetAPIVersion()
	self.account = libunits.accountname

	local charData = {}
	self.charData = charData

	charData.name = libunits.playername
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
		logger:Debug("PrepareFight")
		self.combatstart = timems
		libint.PurgeEffectBuffer(timems)

		FightHandler:GetMetaData()
		GetPlayerBuffs(timems)
		GetOtherBuffs(timems)

		ld.resources[COMBAT_MECHANIC_FLAGS_HEALTH] = GetUnitPower("player", COMBAT_MECHANIC_FLAGS_HEALTH)
		ld.resources[COMBAT_MECHANIC_FLAGS_MAGICKA] = GetUnitPower("player", COMBAT_MECHANIC_FLAGS_MAGICKA)
		ld.resources[COMBAT_MECHANIC_FLAGS_STAMINA] = GetUnitPower("player", COMBAT_MECHANIC_FLAGS_STAMINA)
		ld.resources[COMBAT_MECHANIC_FLAGS_ULTIMATE] = GetUnitPower("player", COMBAT_MECHANIC_FLAGS_ULTIMATE)

		ld.backstabber = lf.GetCritBonusFromCP(self.CP)

		self.startBar = ld.bar

		ld.stats = {}
		ld.advancedStats = {}
		libint.lastQueuedAbilities = {}
		libint.usedCastTimeAbility = {}

		lastBossHealthValue = 2

		self.isWipe = false

		libint.DamageShieldBuffer = {}

		self.prepared = true

		self:QueueStatUpdate(timems)
		lf.GetCurrentSkillBars()
		onBossesChanged()
	end

	EVENT_MANAGER:RegisterForUpdate("LibCombat_update", 500, function() self:onUpdate() end)
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

	libint.EffectBuffer = {}

	libint.lastAbilityActivations = {}
	libint.isProjectile = {}

	logger:Debug("FinishFight")
	logger:Debug("Number of Projectile data entries: %d", NonContiguousCount(libint.isProjectile))

	ld.lastabilities = {}
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
	lf.UpdateStats(timems)
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
				starttime = zo_min(starttime, unit.dpsstart)
			end

			endtime = zo_max(endtime or unit.dpsend or 0, unit.dpsend or 0)
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

--[[ TODO: 
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

--]]
function FightHandler:UpdateStats()
	lf.ProcessDeathRecaps()

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
		["HPSAOut"] = self.HPSAOut,
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

	if libint.isInPortalWorld then -- prevent fight reset in bossfights when using a portal.

		logger:Debug("Prevented combat reset because player is in Portal!")
		return true

	elseif getCurrentBossHP() > 0 and getCurrentBossHP() < 1 then

		logger:Info("Prevented combat reset because boss is still in fight!")
		return true

	else

		return false

	end
end

function FightHandler:onUpdate()

	libint.onCombatState(EVENT_PLAYER_COMBAT_STATE, IsUnitInCombat("player"))

	--reset data
	if reset == true or (ld.inCombat == false and self.combatend > 0 and (GetGameTimeMilliseconds() > (self.combatend + timeout)) ) then

		reset = false

		self:UpdateFightStats()

		if self.damageOutTotal>0 or self.healingOutTotal>0 or self.damageInTotal>0 then

			logger:Debug("Time: %.2fs (DPS) | %.2fs (HPS) ", self.dpstime, self.hpstime)
			logger:Debug("Dmg: %d (DPS: %d)", self.damageOutTotal, self.DPSOut)
			logger:Debug("Heal: %d (HPS: %d)", self.healingOutTotal, self.HPSOut)
			logger:Debug("IncDmg: %d (Shield: %d, IncDPS: %d)", self.damageInTotal, self.damageInShielded, self.DPSIn)
			logger:Debug("IncHeal: %d (IncHPS: %d)", self.healingInTotal, self.HPSIn)

			if libunits.inGroup and Events.CombatGrp.active then

				logger:Debug("GrpDmg: %d (DPS: %d)", self.groupDamageOut, self.groupDPSOut)
				logger:Debug("GrpHeal: %d (HPS: %d)", self.groupHealingOut, self.groupHPSOut)
				logger:Debug("GrpIncDmg: %d (IncDPS: %d)", self.groupDamageIn, self.groupDPSIn)

			end
		end

		logger:Debug("resetting...")

		self.grplog = {}

		lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_FIGHTSUMMARY]), LIBCOMBAT_EVENT_FIGHTSUMMARY, self)

		libint.currentfight = FightHandler:New()
		lf.ClearUnitCaches()

		EVENT_MANAGER:UnregisterForUpdate("LibCombat_update")

	elseif ld.inCombat == true then

		self:UpdateFightStats()

	end

end


local lastUpdateSingleStatsCall = 0

function FightHandler:UpdateSingleStat(statId, timems)
	if Events.Stats.active ~= true then return end
	EVENT_MANAGER:UnregisterForUpdate("LibCombat_Stats_Single")

	timems = timems or GetGameTimeMilliseconds()
	local lastcalldelta = timems - lastUpdateSingleStatsCall

	if lastcalldelta < 100 then
		EVENT_MANAGER:RegisterForUpdate("LibCombat_Stats_Single", (100 - lastcalldelta), function() self:UpdateSingleStat(statId, nil) end)
		return
	end

	lastUpdateSingleStatsCall = timems
	local stats = ld.stats
	local oldValue = stats[statId]
	local newValue = lf.GetSingleStat(statId)
	local delta = oldValue and (newValue - oldValue) or 0
	if oldValue == nil or delta ~= 0 then
		assert(delta ~= nil)
		assert(newValue ~= nil)
		assert(statId ~= nil)
		lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_PLAYERSTATS]), LIBCOMBAT_EVENT_PLAYERSTATS, timems, delta, newValue, statId)
		stats[statId] = newValue
	end

end

-- Event Functions


function libint.onCombatState(event, inCombat)  -- Detect Combat Stage, local is defined above - Don't Change !!!
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

--(eventCode, changeType, effectSlot, effectName, unitTag, beginTime, endTime, stackCount, iconName, buffType, effectType, abilityType, statusEffectType, unitName, unitId, abilityId, sourceType)

local function onPortalWorld( _, changeType)

	libint.isInPortalWorld = changeType == EFFECT_RESULT_GAINED
	onBossesChanged()

end

local function onMageExplode( _, changeType, effectSlot, _, unitTag, _, endTime, stackCount, _, _, effectType, abilityType, _, unitName, unitId, abilityId, sourceType)

	libint.currentfight:ResetFight()	-- special tracking for The Mage in Aetherian Archives. It will reset the fight when the mage encounter starts.

end

local function onWeaponSwap(_, isHotbarSwap)

	local newbar = GetActiveHotbarCategory() + 1

	if ld.bar == newbar then return end

	ld.bar = newbar

	lf.GetCurrentSkillBars()

	local inCombat = libint.currentfight.prepared

	if inCombat == true then

		local timems = GetGameTimeMilliseconds()
		lib.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_MESSAGES]), LIBCOMBAT_EVENT_MESSAGES, timems, LIBCOMBAT_MESSAGE_WEAPONSWAP, ld.bar)

		libint.currentfight:QueueStatUpdate(timems)

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
	if libint.currentfight.dpsstart ~= nil then
		return ZO_DeepTableCopy(libint.currentfight)
	end
end

Events.General = EventHandler:New(
	libint.GetAllCallbackTypes(),
	function (self)
		self:RegisterEvent(EVENT_PLAYER_COMBAT_STATE, libint.onCombatState)
		self:RegisterEvent(EVENT_BOSSES_CHANGED, onBossesChanged)

		self:RegisterEvent(EVENT_HOTBAR_SLOT_CHANGE_REQUESTED, lf.GetCurrentSkillBars)
		self:RegisterEvent(EVENT_PLAYER_ACTIVATED, lf.onPlayerActivated)
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onMageExplode, REGISTER_FILTER_ABILITY_ID, 50184)
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onPortalWorld, REGISTER_FILTER_ABILITY_ID, 108045)
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onPortalWorld, REGISTER_FILTER_ABILITY_ID, 121216)

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

Events.BossHP = EventHandler:New(
	{LIBCOMBAT_EVENT_BOSSHP},
	function (self)
		self:RegisterEvent(EVENT_POWER_UPDATE, onBossHealthChanged, REGISTER_FILTER_UNIT_TAG, "boss1", REGISTER_FILTER_POWER_TYPE, COMBAT_MECHANIC_FLAGS_HEALTH)
		self.active = true
	end
)

local isFileInitialized = false

function lib.InitializeMain()
	if isFileInitialized == true then return false end
	logger = libint.logger.main
	logger:Debug("Initialize")

	ld.inCombat = IsUnitInCombat("player")
	ld.bossInfo = {}
	ld.PlayerPets = {}
	ld.lastabilities = {}
	ld.backstabber = 0
	ld.critBonusMundus = 0
	ld.bar = GetActiveWeaponPairInfo()
	ld.resources = {}
	ld.stats = {}
	ld.advancedStats = {}
	ld.currentQuickslotIndex = GetCurrentQuickslot()

	--resetfightdata
	libint.currentfight = FightHandler:New()

	InitCallbackIndex()

	onBossesChanged()

	EVENT_MANAGER:RegisterForEvent("LibCombatActive", EVENT_PLAYER_ACTIVATED, function() ld.isUIActivated = true end)
	EVENT_MANAGER:RegisterForEvent("LibCombatActive", EVENT_PLAYER_DEACTIVATED, function() ld.isUIActivated = false end)

	isFileInitialized = true
	return true
end