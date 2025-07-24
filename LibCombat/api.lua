-- This file contains handling of the api

local lib = LibCombat
local libint = lib.internal
local ld = libint.data
local libunits = ld.units
local lf = libint.functions
local logger
local isFileInitialized = false


function lib.ResetFight()
	libint.currentFight:ResetFight()
end

function lib.GetPlayerUnitId()
	return libunits.playerid
end

---comment
---@param unitId any
---@return boolean
function lib.IsPlayerUnitId(unitId)
	return unitId == libunits.playerid
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

	if fight.bossfight then
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


function libint.InitializeAPI()
	if isFileInitialized == true then return false end
	logger = lf.initSublogger("api")

    isFileInitialized = true
	return true
end