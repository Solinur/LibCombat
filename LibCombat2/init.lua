-- This file contains the initialziation code

---@class LibCombat2
LibCombat2 = LibCombat2 or {}
---@class LibCombat2
local lib = LibCombat2
if LibCombat == nil then
	LibCombat = lib
end

-- Basic values
lib.name = "LibCombat2"
lib.version = 8

---@class LCint
lib.internal = {}
---@class LCint
local libint = lib.internal
libint.debug = false or GetDisplayName() == "@Solinur"

---@class LCfunc
libint.functions = {}
---@class LCData
libint.data = {}
libint.logger = {}
---@class LCfunc
local lf = libint.functions

-- Logger

if LibDebugLogger and libint.debug then
	---@type Logger
	libint.logger.main = LibDebugLogger.Create(lib.name)
else
	local internalLogger = {}

	function internalLogger:Warn(...)
		df(...)
	end
	function internalLogger:Debug() end -- do nothing

	internalLogger.Verbose = internalLogger.Debug
	internalLogger.Info = internalLogger.Debug
	internalLogger.Error = internalLogger.Warn
	libint.logger.main = internalLogger
end

function lf.initSublogger(name)
	local mainlogger = libint.logger.main
	if mainlogger.Create == nil or name == nil or name == "" then
		return mainlogger
	end
	if libint.logger[name] ~= nil then
		libint.logger.main:Warn("Sublogger %s already exists!", name)
		return libint.logger[name]
	end

	local sublogger = libint.logger.main:Create(name)
	mainlogger:Info("Sublogger %s created", name)
	libint.logger[name] = sublogger
	return sublogger
end

---from https://stackoverflow.com/questions/15706270/sort-a-table-in-lua
---@param t table
---@param order? fun(t: table, a, b):boolean
---@return function
local function spairs(t, order)
	local keys = {}
	for k in pairs(t) do
		keys[#keys + 1] = k
	end

	if order then
		table.sort(keys, function(a, b)
			return order(t, a, b)
		end)
	else
		table.sort(keys)
	end

	local i = 0
	return function()
		i = i + 1
		if keys[i] then
			return keys[i], t[keys[i]]
		end
	end
end
lf.spairs = spairs

local function Initialize(eventId, addon)
	if addon ~= lib.name then
		return
	end

	assert(libint.InitializeGlobals(), "Initialization of globals module failed")
	assert(libint.InitializeUtility(), "Initialization of utility module failed")
	assert(libint.InitializeCalculations(), "Initialization of calculations module failed")
	assert(libint.InitializeEvents(), "Initialization of events module failed")
	assert(libint.InitializeUnits(), "Initialization of units module failed")
	assert(libint.InitializeCombat(), "Initialization of combat module failed")
	assert(libint.InitializeEffects(), "Initialization of effects module failed")
	-- assert(libint.InitializeStats(), "Initialization of stats module failed")
	-- assert(libint.InitializeActions(), "Initialization of actions module failed")
	-- assert(libint.InitializeResources(), "Initialization of resources module failed")
	-- assert(libint.InitializePerformance(), "Initialization of performance module failed")
	-- assert(libint.InitializeDeaths(), "Initialization of deaths module failed")
	assert(libint.InitializeFights(), "Initialization of fights module failed")
	assert(libint.InitializeAPI(), "Initialization of api module failed")

	EVENT_MANAGER:UnregisterForEvent("LibCombat_Initialize", EVENT_ADD_ON_LOADED)
end

EVENT_MANAGER:RegisterForEvent("LibCombat_Initialize", EVENT_ADD_ON_LOADED, Initialize)
