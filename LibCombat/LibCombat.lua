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

local ActiveCallbackTypes = {}
libint.ActiveCallbackTypes = ActiveCallbackTypes
libint.isProjectile = {}
libint.isInPortalWorld = false	-- used to prevent fight reset in Cloudrest/Sunspire when using a portal.

local lastBossHealthValue = 2

function lf.onPlayerActivated()
	logger:Debug("onPlayerActivated")

	zo_callLater(lf.GetCurrentSkillBars, 100)
	libint.isInPortalWorld = false
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
	end
	return false
end


-- Event Functions
function libint.onCombatState(event, inCombat)  -- Detect Combat Stage, local is defined above - Don't Change !!!
	if inCombat ~= ld.inCombat then     -- Check if player state changed
		local timems = GetGameTimeMilliseconds()

		if inCombat then
			ld.inCombat = inCombat
			logger:Debug("Entering combat.")
			libint.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_LOG_EVENT_COMBATSTATE]), LIBCOMBAT_LOG_EVENT_COMBATSTATE, timems, LIBCOMBAT_MESSAGE_COMBATSTART, 0)
			libint.currentFight:PrepareFight()
		else
			if IsOngoingBossfight() then
				logger:Debug("Failed: Leaving combat.")
				return
			end

			ld.inCombat = false
			logger:Debug("Leaving combat.")
			libint.currentFight:FinishFight()

			if libint.currentFight.charData == nil then return end
			libint.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_LOG_EVENT_COMBATSTATE]), LIBCOMBAT_LOG_EVENT_COMBATSTATE, timems, LIBCOMBAT_MESSAGE_COMBATEND, 0)
		end
	end
end

local function onPortalWorld( _, changeType)
	libint.isInPortalWorld = changeType == EFFECT_RESULT_GAINED
end

local function onMageExplode()
	libint.currentFight:ResetFight()	-- special tracking for The Mage in Aetherian Archives. It will reset the fight when the mage encounter starts.
end

local function onWeaponSwap(_, isHotbarSwap)
	local newbar = GetActiveHotbarCategory() + 1
	if ld.bar == newbar then return end
	ld.bar = newbar
	lf.GetCurrentSkillBars()

	local inCombat = libint.currentFight.prepared
	if inCombat == true then
		local timems = GetGameTimeMilliseconds()
		libint.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_LOG_EVENT_COMBATSTATE]), LIBCOMBAT_LOG_EVENT_COMBATSTATE, timems, LIBCOMBAT_MESSAGE_WEAPONSWAP, ld.bar)

		-- libint.currentFight:QueueStatUpdate(timems) -- move to stats
	end
end

local tagToBossId = {} -- avoid string ops
for i = 1, 12 do
	local unitTag = ZO_CachedStrFormat("boss<<1>>", i)
	tagToBossId[unitTag] = i
end

-- EVENT_POWER_UPDATE (*string* _unitTag_, *luaindex* _powerIndex_, *[CombatMechanicType|#CombatMechanicType]* _powerType_, *integer* _powerValue_, *integer* _powerMax_, *integer* _powerEffectiveMax_)
local function onBossHealthChanged(eventid, unitTag, _, powerType, powerValue, powerMax, powerEffectiveMax)
	local timems = GetGameTimeMilliseconds()
	local BossHealthValue = zo_round(powerValue / powerMax * 100)

	if BossHealthValue == lastBossHealthValue then return end
	lastBossHealthValue = BossHealthValue

	local bossId = tagToBossId[unitTag]

	-- TODO: REwork this into callback type UNIT_HEALTH
	-- libint.cm:FireCallbacks((CallbackKeys[LIBCOMBAT_EVENT_BOSSHP]), LIBCOMBAT_EVENT_BOSSHP, timems, bossId, powerValue, powerMax)
end

-- Calllback Registrations

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
	for i=LIBCOMBAT_LOG_EVENT_MIN,LIBCOMBAT_LOG_EVENT_MAX do
		ActiveCallbackTypes[i]={}
	end
end

function lib:RegisterForLogableCombatEvents(name, callback)
	for i = LIBCOMBAT_LOG_EVENT_MIN, LIBCOMBAT_LOG_EVENT_MAX do
		lib:RegisterForCombatEvent(name, i, callback)
	end
end

function lib:RegisterForCombatEvent(name, callbacktype, callback)
	local isRegistered = UpdateResources(name, callbacktype, callback)
	if isRegistered then libint.cm:RegisterCallback(CallbackKeys[callbacktype], callback) end

	return isRegistered
end

function lib:UnregisterForCombatEvent(name, callbacktype)
	local isUnregistered, callback = UpdateResources(name, callbacktype)
	libint.cm:UnregisterCallback(CallbackKeys[callbacktype], callback)

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
	if libint.currentFight.dpsstart ~= nil then
		return ZO_DeepTableCopy(libint.currentFight)
	end
end

-- Events

Events.General = EventHandler:New(
	libint.GetAllCallbackTypes(),
	function (self)
		self:RegisterEvent(EVENT_PLAYER_COMBAT_STATE, libint.onCombatState)

		self:RegisterEvent(EVENT_HOTBAR_SLOT_CHANGE_REQUESTED, lf.GetCurrentSkillBars)
		self:RegisterEvent(EVENT_PLAYER_ACTIVATED, lf.onPlayerActivated)
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onMageExplode, REGISTER_FILTER_ABILITY_ID, 50184)
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onPortalWorld, REGISTER_FILTER_ABILITY_ID, 108045)
		self:RegisterEvent(EVENT_EFFECT_CHANGED, onPortalWorld, REGISTER_FILTER_ABILITY_ID, 121216)

		self.active = true
	end
)

Events.Messages = EventHandler:New(
	{LIBCOMBAT_LOG_EVENT_COMBATSTATE, LIBCOMBAT_EVENT_FIGHTSUMMARY, LIBCOMBAT_LOG_EVENT_SKILL_CAST},
	function (self)
		self:RegisterEvent(EVENT_ACTION_SLOTS_FULL_UPDATE, onWeaponSwap)
		self.active = true
	end
)

-- TODO: Rework into UNIT Health
-- Events.BossHP = EventHandler:New(
-- 	{LIBCOMBAT_EVENT_BOSSHP},
-- 	function (self)
-- 		self:RegisterEvent(EVENT_POWER_UPDATE, onBossHealthChanged, REGISTER_FILTER_UNIT_TAG, "boss1", REGISTER_FILTER_POWER_TYPE, COMBAT_MECHANIC_FLAGS_HEALTH)
-- 		self.active = true
-- 	end
-- )

local isFileInitialized = false

function lib.InitializeMain()
	if isFileInitialized == true then return false end
	logger = libint.logger.main
	logger:Debug("Initialize")
	InitCallbackIndex()

	ld.inCombat = false
	libint.onCombatState(EVENT_PLAYER_COMBAT_STATE, IsUnitInCombat("player"))
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

	isFileInitialized = true
	return true
end