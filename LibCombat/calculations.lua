-- contains the analysis of log events to calculate stats 

local lib = LibCombat
local libint = lib.internal
local CallbackKeys = libint.callbackKeys
local libfunc = libint.functions
local libdata = libint.data
local Print = libint.Print

local isFileInitialized = false

function lib.InitializeCalculations()

	if isFileInitialized == true then return false end

    isFileInitialized = true
	return true

end