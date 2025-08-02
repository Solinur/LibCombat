-- This file contains handling of the api

local lib = LibCombat
local libint = lib.internal
local ld = libint.data
local libunits = ld.units
local lf = libint.functions
local logger
local isFileInitialized = false

--- Ends the current fight and immediately starts a new one.
function lib.ResetFight()
	libint.currentFight:ResetFight()
end

---Returns if the unitId is the one from the player
---@return integer unitId
function lib.GetPlayerUnitId()
	return libunits.playerId
end

---Returns if the unitId is the one from the player
---@param unitId any
---@return boolean
function lib.IsPlayerUnitId(unitId)
	return unitId == libunits.playerId
end

---Returns if the current fight is a boss fight
---@return boolean isBossFight
function lib.IsCurrentFightBossFight()
	local fight = libint.currentFight
	return fight.bossFight
end

---Returns the time since the player went into combat in seconds
---@return number combatDuration 
function lib.GetCurrentFightDuration()
	local fight = libint.currentFight
	return (GetGameTimeMilliseconds() - fight.info.combatStart)/1000
end

---Returns player and total damage done to the main target(s) as well as the durations during which the damage occured.
---
---In a bossfight the main target refers to the boss(es), in other fights to the unit with the most health or damage taken.
---@return number playerTime
---@return integer playerDamage
---@return number totalTime
---@return integer totalDamage
function lib.GetCurrentMainTargetDamage()
	local fight = libint.currentFight

	if fight.bossFight then
		local unitIds = fight.unitIds.bosses
		return fight:GetDamageToUnits(unitIds)
	else
		local unitId = fight:GetMainUnit()
		return fight:GetDamageToUnit(unitId)
	end
end

---Returns player and total damage done to the main target(s) as well as the durations during which the damage occured.
---
---In a bossfight the main target refers to the boss(es), in other fights to the unit with the most health or damage taken.
---@return number playerTime
---@return integer playerDamage
---@return number totalTime
---@return integer totalDamage
function lib.GetCurrentTotalDamage()
	local fight = libint.currentFight

	local unitIds = {}
	for unitId, unit in pairs(fight.units) do
		if unit.isFriendly == false then unitIds[#unitIds+1] = unitId end
	end

	return fight:GetDamageToUnits(unitIds)
end

--- Callbacks

---Register all events that return log info
---@param name string
---@param callback function
function lib.RegisterForLogableCombatEvents(name, callback)
	for i = LIBCOMBAT_LOG_EVENT_MIN, LIBCOMBAT_LOG_EVENT_MAX do
		local isRegistered = lib.RegisterForCombatEvent(name, i, callback)
		if not isRegistered then logger:Warn("Could not register event type %d for %s", i, name) end
	end
end

---Unregister all events that return log info
---@param name string
function lib.UnregisterForLogableCombatEvents(name)
	for i = LIBCOMBAT_LOG_EVENT_MIN, LIBCOMBAT_LOG_EVENT_MAX do
		local isUnregistered = lib.UnregisterForCombatEvent(name, i)
		if not isUnregistered then logger:Warn("Could not unregister event type %d for %s", i, name) end
	end
end

---Register a single events
---@param name string
---@param callbacktype CallbackKey
---@param callback function
function lib.RegisterForCombatEvent(name, callbacktype, callback)
	local isRegistered = lf.UpdateResources(name, callbacktype, callback)
	if isRegistered then libint.cm:RegisterCallback(libint.CallbackKeys[callbacktype], callback) end

	return isRegistered
end

---Unregister a single event
---@param name string
---@param callbacktype CallbackKey
function lib.UnregisterForCombatEvent(name, callbacktype)
	local isUnregistered, callback = lf.UpdateResources(name, callbacktype)
	libint.cm:UnregisterCallback(libint.CallbackKeys[callbacktype], callback)

	return isUnregistered
end

--- Legacy

---Register all events that return log info
---@param callback function
---@param name string
function lib:RegisterAllLogCallbacks(callback, name)
	lib.RegisterForLogableCombatEvents(name, callback)
end

---@param callbacktype CallbackKey
---@param callback function
---@param name string
function lib:RegisterCallbackType(callbacktype, callback, name)
	lib.RegisterForCombatEvent(name, callbacktype, callback)
end

---@param callbacktype CallbackKey
---@param callback function
---@param name string
function lib:UnregisterCallbackType(callbacktype, callback, name)
	lib.UnregisterForCombatEvent(name, callbacktype)
end


-- function lib:GetCurrentFight()
-- 	if libint.currentFight.dpsstart ~= nil then
-- 		return ZO_DeepTableCopy(libint.currentFight)
-- 	end
-- end


function libint.InitializeAPI()
	if isFileInitialized == true then return false end
	logger = lf.initSublogger("api")

    isFileInitialized = true
	return true
end