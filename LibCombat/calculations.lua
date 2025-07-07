-- contains the analysis of log events to calculate stats 

local lib = LibCombat
local libint = lib.internal
local CallbackKeys = libint.callbackKeys
local lf = libint.functions
local ld = libint.data
local logger

lf.LogProcessors = {}
lf.LogTypeProcessors = {}

local LogProcessingHandler = ZO_InitializingObject:Subclass() -- object to store log proccessing routines
lf.LogProcessingHandler = LogProcessingHandler

LogProcessingHandler.onInitilizeFight = LogProcessingHandler:MUST_IMPLEMENT()
LogProcessingHandler.onCombatStarted = LogProcessingHandler:MUST_IMPLEMENT()
LogProcessingHandler.onCombatFinished = LogProcessingHandler:MUST_IMPLEMENT()
LogProcessingHandler.ProcessLogLine = LogProcessingHandler:MUST_IMPLEMENT()

---@param name string
---@param AllowedLogTypes number|[number]
function LogProcessingHandler:Initialize(name,  AllowedLogTypes)
	self.active = false
	self.name = name
	self.idCounter = 1
	self.RegisteredLogTypes = {}

	lf.LogProcessors[name] = self
	self:RegisterLogTypes(AllowedLogTypes)
end

---@param logTypes number|[number]
function LogProcessingHandler:RegisterLogTypes(logTypes)
	if type(logTypes) == "number" then return self:RegisterLogType(logTypes) end

	for _, logType in pairs(logTypes) do
		self:RegisterLogType(logType)
	end
end

---@param logType number
function LogProcessingHandler:RegisterLogType(logType)
	lf.LogTypeProcessors[logType] = function(...) self:ProcessLogLine(...) end
	self.RegisteredLogTypes[logType] = false
end

function LogProcessingHandler:Activate()
	self.active  = true

	for logType, _ in pairs(self.RegisteredLogTypes) do
		local idString = string.format("LibCombat_%s%d", self.name, logType)
		lib:RegisterCallbackType(logType, lf.LogProcessingQueue.AddLogLine, idString)
	end
end


local LogProcessingQueue = ZO_InitializingObject:Subclass() 
lf.LogProcessingQueue = LogProcessingQueue

function LogProcessingQueue:Initialize()
	self.first = 0
	self.last = -1
end

function LogProcessingQueue:Push(value) -- https://www.lua.org/pil/11.4.html
	local last = self.last + 1
	self.last = last
	self[last] = value
end

function LogProcessingQueue:Pop()
	if self:IsEmpty() then logger:error("Queue is empty") end
	local first = self.first
	local value = self[first]
	self[first] = nil
	self.first = first + 1
	return value
end

function LogProcessingQueue:IsEmpty()
	return self.first > self.last
end

function LogProcessingQueue.AddLogLine(...)
	for i = 1, select("#", ...) do
		LogProcessingQueue:Push(select(i, ...))
	end
	LogProcessingQueue:Push(nil)
end

local line = {}
function LogProcessingQueue:ProcessLine()
	local item = self:Pop()
	local processor = lf.LogTypeProcessors[item]

	local i = 1
	while item ~= nil do
		line[i] = item
		i = i + 1
	end
	
	processor:ProcessLogLine(line)

	for j = 1, i do
		line[j] = nil
	end
end

local isFileInitialized = false
function lib.InitializeCalculations()
	if isFileInitialized == true then return false end
	logger = libint.initSublogger("calc")

    isFileInitialized = true
	return true
end