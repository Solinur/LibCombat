-- This file contains the initialziation code 

LibCombat = LibCombat or {}
local lib = LibCombat

LIBCOMBAT_LINE_SIZE = math.ceil(GuiRoot:GetWidth()/tonumber(GetCVar("WindowedWidth"))*1000)/1000

-- Basic values
lib.name = "LibCombat"
lib.version = 64
lib.cm = ZO_CallbackObject:New()

local libint = {}
libint.debug = false or GetDisplayName() == "@Solinur"
if libint.debug then lib.internal = libint end

libint.functions = {}
libint.debug = false or GetDisplayName() == "@Solinur"
libint.data = {skillBars= {}}

-- variables

libint.abilityIdZen = 126597
libint.abilityIdForceOfNature = 174250

-- Logger

local mainlogger
local subloggers = {}
local levelKeys = {}

if LibDebugLogger then

	mainlogger = LibDebugLogger.Create(lib.name)

	levelKeys = {

		["VERBOSE"] = LibDebugLogger.LOG_LEVEL_VERBOSE,
		["DEBUG"] = LibDebugLogger.LOG_LEVEL_DEBUG,
		["INFO"] = LibDebugLogger.LOG_LEVEL_INFO,
		["WARNING"] = LibDebugLogger.LOG_LEVEL_WARNING,
		["ERROR"] = LibDebugLogger.LOG_LEVEL_ERROR,

	}

	subloggers["DoA"] = mainlogger:Create("DoA")
	subloggers["other"] = mainlogger:Create("other")
	subloggers["fight"] = mainlogger:Create("fight")
	subloggers["events"] = mainlogger:Create("events")
	subloggers["dev"] = mainlogger:Create("dev")

end

function libint.Print(category, level, ...)

	if mainlogger == nil then return end

	local logger = category and subloggers[category] or mainlogger

	if category == "dev" and libint.debug ~= true then return end

	if type(logger.Log)=="function" then logger:Log(levelKeys[level], ...) end

end

local function Initialize(eventId, addon)

	if addon ~= lib.name then return end

	assert(lib.InitializeMain(), "Initialization of main module failed")
	assert(lib.InitializeCalculations(), "Initialization of calculations module failed")
	assert(lib.InitializeCombat(), "Initialization of combat module failed")
	assert(lib.InitializeDeaths(), "Initialization of deaths module failed")
	assert(lib.InitializeEffects(), "Initialization of effects module failed")
	assert(lib.InitializeEvents(), "Initialization of events module failed")
	assert(lib.InitializeGlobals(), "Initialization of globals module failed")
	assert(lib.InitializePerformance(), "Initialization of performance module failed")
	assert(lib.InitializeResources(), "Initialization of resources module failed")
	assert(lib.InitializeSkillcasting(), "Initialization of skill casting module failed")
	assert(lib.InitializeStats(), "Initialization of stats module failed")
	assert(lib.InitializeUnits(), "Initialization of units module failed")
	assert(lib.InitializeUtility(), "Initialization of utility module failed")

	EVENT_MANAGER:UnregisterForEvent("LibCombat_Initialize", EVENT_ADD_ON_LOADED)

end

EVENT_MANAGER:RegisterForEvent("LibCombat_Initialize", EVENT_ADD_ON_LOADED, Initialize)