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

--aliases

local _
local logger

-- local lastBossHealthValue = 2

-- local tagToBossId = {} -- avoid string ops
-- for i = 1, 12 do
-- 	local unitTag = ZO_CachedStrFormat("boss<<1>>", i)
-- 	tagToBossId[unitTag] = i
-- end

-- EVENT_POWER_UPDATE (*string* _unitTag_, *luaindex* _powerIndex_, *[CombatMechanicType|#CombatMechanicType]* _powerType_, *integer* _powerValue_, *integer* _powerMax_, *integer* _powerEffectiveMax_)
-- local function onBossHealthChanged(eventid, unitTag, _, powerType, powerValue, powerMax, powerEffectiveMax)
-- local timeMs = GetGameTimeMilliseconds()
-- local BossHealthValue = zo_round(powerValue / powerMax * 100)

-- if BossHealthValue == lastBossHealthValue then return end
-- lastBossHealthValue = BossHealthValue

-- local bossId = tagToBossId[unitTag]

-- TODO: Rework this into callback type UNIT_HEALTH
-- lf.FireCallback(LIBCOMBAT_EVENT_BOSSHP, timeMs, bossId, powerValue, powerMax)
-- end

-- TODO: Rework into UNIT Health
-- Events.BossHP = EventHandler:New(
-- 	{LIBCOMBAT_EVENT_BOSSHP},
-- 	function (self)
-- 		self:RegisterEvent(EVENT_POWER_UPDATE, onBossHealthChanged, REGISTER_FILTER_UNIT_TAG, "boss1", REGISTER_FILTER_POWER_TYPE, COMBAT_MECHANIC_FLAGS_HEALTH)
-- 		self.active = true
-- 	end
-- )

local isFileInitialized = false

function libint.InitializeMain()
	if isFileInitialized == true then return false end
	logger = libint.logger.main
	logger:Debug("Initialize")

	isFileInitialized = true
	return true
end