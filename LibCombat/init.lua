LibCombat = LibCombat or {}
local lib = LibCombat

local dx = math.ceil(GuiRoot:GetWidth()/tonumber(GetCVar("WindowedWidth"))*1000)/1000
LIBCOMBAT_LINE_SIZE = dx


-- Basic values
lib.name = "LibCombat"
lib.version = 54
lib.data = {skillBars= {}}
lib.cm = ZO_CallbackObject:New()
lib.internal = {}
lib.debug = false or GetDisplayName() == "@Solinur"

-- Logger

local mainlogger
local subloggers = {}
local levelKeys = {}

-- local LOG_LEVEL_VERBOSE = "V"
-- local LOG_LEVEL_DEBUG = "D"
-- local LOG_LEVEL_INFO = "I"
-- local LOG_LEVEL_WARNING ="W"
-- local LOG_LEVEL_ERROR = "E"

if LibDebugLogger then

	mainlogger = LibDebugLogger.Create(lib.name)

	levelKeys = {

		[1] = LibDebugLogger.LOG_LEVEL_VERBOSE,
		[2] = LibDebugLogger.LOG_LEVEL_DEBUG,
		[3] = LibDebugLogger.LOG_LEVEL_INFO,
		[4] = LibDebugLogger.LOG_LEVEL_WARNING,
		[5] = LibDebugLogger.LOG_LEVEL_ERROR

	}

	subloggers["DoA"] = mainlogger:Create("DoA")
	subloggers["other"] = mainlogger:Create("other")
	subloggers["fight"] = mainlogger:Create("fight")
	subloggers["events"] = mainlogger:Create("events")
	subloggers["dev"] = mainlogger:Create("dev")

end

function lib.Print(category, level, ...)

	if mainlogger == nil then return end

	local logger = category and subloggers[category] or mainlogger

	if category == "dev" and lib.debug ~= true then return end

	if type(logger.Log)=="function" then logger:Log(levelKeys[level], ...) end

end