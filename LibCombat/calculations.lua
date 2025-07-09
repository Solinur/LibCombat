---@diagnostic disable: undefined-field
-- contains the analysis of log events to calculate stats 

local lib = LibCombat
local libint = lib.internal
local CallbackKeys = libint.callbackKeys
local lf = libint.functions
local ld = libint.data
local logger

---@type table<string, LogProcessingHandler>
libint.LogProcessors = {}
lf.LogTypeProcessors = {}

---@class LogProcessingHandler
local LogProcessingHandler = ZO_InitializingObject:Subclass() -- object to store log proccessing routines
lf.LogProcessingHandler = LogProcessingHandler

LogProcessingHandler.onInitilizeFight = LogProcessingHandler:MUST_IMPLEMENT()
LogProcessingHandler.onCombatStart = LogProcessingHandler:MUST_IMPLEMENT()
LogProcessingHandler.onCombatEnd = LogProcessingHandler:MUST_IMPLEMENT()
LogProcessingHandler.ProcessLogLine = LogProcessingHandler:MUST_IMPLEMENT()

---@param name string
---@param AllowedLogTypes number|[number]
function LogProcessingHandler:Initialize(name,  AllowedLogTypes)
	self.active = false
	self.name = name
	self.idCounter = 1
	self.RegisteredLogTypes = {}
	self.currentfight = nil
	self.idString = {}

	libint.LogProcessors[name] = self
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
		local success = lib:RegisterForCombatEvent(idString, logType, lf.AddLogLine)
		if success then self.idString[logType] = idString else logger:warn("Error during callback registration. Name: %s, Type: %d, idString: %s", self.name, logType, idString) end
	end
end

function LogProcessingHandler:Deactivate()
	self.active = false

	for logType, _ in pairs(self.RegisteredLogTypes) do
		lib:UnregisterForCombatEvent(logType, self.idString[logType])
		self.idString[logType] = nil
	end
end

local LogProcessingQueue = ZO_InitializingObject:Subclass()

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

function LogProcessingQueue:NumQueuedItems()
	return self.last - self.first
end

local LOG_LINE_TERMINATE_STRING = ":end;"
function lf.AddLogLine(...)
	local queue = libint.LogProcessingQueue
	for i = 1, select("#", ...) do
		queue:Push(select(i, ...))
	end
	queue:Push(LOG_LINE_TERMINATE_STRING)
end

local LOG_LINE_SET_FIGHT_STRING = ":fight;"
function LogProcessingQueue:SetFight(fight)
	self:Push(LOG_LINE_SET_FIGHT_STRING)
	self:Push(fight)
	self:Push(LOG_LINE_TERMINATE_STRING)
end

local line = {}
function LogProcessingQueue:ProcessLine()
	local item = self:Pop()
	
	if item == LOG_LINE_SET_FIGHT_STRING then
		self.fight = self:Pop()
		if self:Pop() == LOG_LINE_TERMINATE_STRING then
			return lf.ProcessorsInitilizeFight(self.fight)
		else
			logger:Error("End of log line expected!")
		end
	end

	if self.fight == nil then
		logger:Error("No fight is set for processing!")
	end
	
	local processor = lf.LogTypeProcessors[item]
	local i = 1
    while item ~= LOG_LINE_TERMINATE_STRING do
		line[i] = item
		i = i + 1
		item = self:Pop()
	end

	processor:ProcessLogLine(self.fight, unpack(line, 1, i))
	ZO_ClearTable(line)
end

function lf.ProcessorsInitilizeFight(fight)
	for _, processor in pairs(libint.LogProcessors) do
		if processor.active then processor:onInitilizeFight(fight) end
	end
end

function lf.ActivateProcessors() -- add start / stop / pause and connect with fight creation
	for _, processor in pairs(libint.LogProcessors) do
		processor:Activate()
	end
end

function lf.DeactivateProcessors() -- add start / stop / pause and connect with fight creation
	for _, processor in pairs(libint.LogProcessors) do
		processor:Dectivate()
	end
end

local isFileInitialized = false
function lib.InitializeCalculations()
	if isFileInitialized == true then return false end
	logger = lf.initSublogger("calc")
	libint.LogProcessingQueue = LogProcessingQueue:New()

    isFileInitialized = true
	return true
end