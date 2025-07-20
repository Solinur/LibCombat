-- This file contains handling of the api

local lib = LibCombat
local libint = lib.internal
local ld = libint.data
local libunits = ld.units
local lf = libint.functions
local logger
local isFileInitialized = false


function lib.ResetFight()
	libint.currentfight:ResetFight()
end

function lib.GetPlayerUnitId()
	return libunits.playerid
end

function lib.IsPlayerUnitId(unitId)
	return unitId == libunits.playerid
end




function lib.InitializeAPI()
	if isFileInitialized == true then return false end
	logger = lf.initSublogger("api")

    isFileInitialized = true
	return true
end