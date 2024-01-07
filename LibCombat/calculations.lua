-- contains the analysis of log events to calculate stats 

local lib = LibCombat
local libint = lib.internal
local CallbackKeys = libint.callbackKeys
local libfunc = libint.functions
local libdata = libint.data
local Print = libint.Print


libfunc.LogProcessingHandler = ZO_InitializingObject:Subclass() -- object to store log proccessing routines
libfunc.LogTypeProcessors = {}
libfunc.LogProcessors = {}

---@param name string
---@param onInitilizeFight function
---@param onCombatStarted function
---@param onCombatFinished function
---@param ProcessLogLine function
---@param AllowedLogTypes table
function LogProcessingHandler:Initialize(name, onInitilizeFight, onCombatStarted, onCombatFinished, ProcessLogLine, AllowedLogTypes)

	self.active = false
	self.onInitilizeFight = onInitilizeFight
	self.onCombatStarted = onCombatStarted
	self.onCombatFinished = onCombatFinished
	self.ProcessLogLine = ProcessLogLine
	self.name = name
	self.idCounter = 1
	self.RegisteredLogTypes = {}

	libfunc.LogProcessors[name] = self

	for _, logType in pairs(AllowedLogTypes) do
		libfunc.LogTypeProcessors[logType] = function(...) self:ProcessLogLine(...) end
		self.RegisteredLogTypes[logType] = false
	end

end

function LogProcessingHandler:Activate()

	self.active  = true

	--[[ Todo: register events and link them to a log handler

	for _, eventType in pairs(self.RequiredEvents) do

		local idString = string.format("LibCombat_%s_%d", self.name, self.idCounter)
		lib:RegisterCallbackType(eventType, self.AddLogLine, idString)
		self.idCounter = self.idCounter + 1

	end
	--]]
end




local isFileInitialized = false

function lib.InitializeCalculations()

	if isFileInitialized == true then return false end

    isFileInitialized = true
	return true

end