-- This file contains the initialziation code 

LibCombat = LibCombat or {}
local lib = LibCombat

LIBCOMBAT_LINE_SIZE = zo_ceil(GuiRoot:GetWidth()/tonumber(GetCVar("WindowedWidth"))*1000)/1000

-- Basic values
lib.name = "LibCombat"
lib.version = 85
lib.cm = ZO_CallbackObject:New()
lib.internal = {}

local libint = lib.internal
libint.debug = false or GetDisplayName() == "@Solinur"

local lf = {}
libint.functions = lf
libint.data = {}
libint.logger = {}

-- variables

libint.abilityIdZen = 126597
libint.abilityIdForceOfNature = 174250

-- Logger

if LibDebugLogger then
	libint.logger.main = LibDebugLogger.Create(lib.name)
else
	local internalLogger = {}
	function internalLogger:Debug(...)
		df(...)
	end
	internalLogger.Warn = internalLogger.Debug
	internalLogger.Info = internalLogger.Debug
	internalLogger.Error = internalLogger.Debug
	internalLogger.Verbose = internalLogger.Debug
	libint.logger.main = internalLogger
end

function lf.initSublogger(name)
	local mainlogger = libint.logger.main
	if mainlogger.Create == nil or name == nil or name == "" then return mainlogger end
	if libint.logger[name] ~= nil then
		libint.logger.main:Warn("Sublogger %s already exists!", name)
		return libint.logger[name]
	end

	local sublogger = libint.logger.main:Create(name)
	mainlogger:Info("Sublogger %s created", name)
	libint.logger[name] = sublogger
	return sublogger
end

local function spairs(t, order) -- from https://stackoverflow.com/questions/15706270/sort-a-table-in-lua
    local keys = {}
    for k in pairs(t) do keys[#keys+1] = k end

    if order then
        table.sort(keys, function(a,b) return order(t, a, b) end)
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
	if addon ~= lib.name then return end

	assert(lib.InitializeGlobals(), "Initialization of globals module failed")
	assert(lib.InitializeUtility(), "Initialization of utility module failed")
	assert(lib.InitializeCalculations(), "Initialization of calculations module failed")
	assert(lib.InitializeEvents(), "Initialization of events module failed")
	assert(lib.InitializeUnits(), "Initialization of units module failed")
	assert(lib.InitializeCombat(), "Initialization of combat module failed")
	assert(lib.InitializeEffects(), "Initialization of effects module failed")
	-- assert(lib.InitializeStats(), "Initialization of stats module failed")
	-- assert(lib.InitializeSkillcasting(), "Initialization of skill casting module failed")
	-- assert(lib.InitializeResources(), "Initialization of resources module failed")
	-- assert(lib.InitializePerformance(), "Initialization of performance module failed")
	-- assert(lib.InitializeDeaths(), "Initialization of deaths module failed")
	assert(lib.InitializeMain(), "Initialization of main module failed")

	EVENT_MANAGER:UnregisterForEvent("LibCombat_Initialize", EVENT_ADD_ON_LOADED)
end

EVENT_MANAGER:RegisterForEvent("LibCombat_Initialize", EVENT_ADD_ON_LOADED, Initialize)