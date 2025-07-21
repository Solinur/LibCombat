---@diagnostic disable: undefined-field
-- contains the analysis of log events to calculate stats 

local lib = LibCombat
local libint = lib.internal
local CallbackKeys = libint.callbackKeys
local lf = libint.functions
local ld = libint.data
local logger
local isFileInitialized = false

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
	self.currentFight = nil
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
	lf.LogTypeProcessors[logType] = self
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

local LogProcessingQueue = lf.CreateQueue()
LogProcessingQueue.active = false

function LogProcessingQueue:NumQueuedItems()
	return self.last - self.first
end

local LOG_LINE_TERMINATE_STRING = ":end;"
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
	logger:Info("Process Line: ", processor.name, unpack(line, 1, i))
	ZO_ClearTable(line)
end


local desiredFrameTime
local lastRun

local function DeactivateProcessing()
	local success = EVENT_MANAGER:UnregisterForUpdate("LibCombatProcessing")
	libint.LogProcessingQueue.active = not success
end

local function ProcessChunk()
	if isFileInitialized == false or libint.LogProcessingQueue == nil then return end
	local queue = libint.LogProcessingQueue
	if queue:IsEmpty() then 
		if GetGameTimeSeconds() - lastRun > 0.5 then DeactivateProcessing() end
		return 
	end

	while GetFrameDeltaTimeSeconds() < desiredFrameTime do
		libint.LogProcessingQueue:ProcessLine()
		if queue:IsEmpty() then break end
	end

	lastRun = GetGameTimeSeconds()
end

local function ActivateProcessing()
	if isFileInitialized == false or libint.LogProcessingQueue == nil or libint.LogProcessingQueue.active == true then return end
	desiredFrameTime = tonumber(GetCVar("MinFrameTime.2") / 2)
	libint.LogProcessingQueue.active = EVENT_MANAGER:RegisterForUpdate("LibCombatProcessing", 0, ProcessChunk)
end

function lf.AddLogLine(...)
	local queue = libint.LogProcessingQueue
	for i = 1, select("#", ...) do
		queue:Push(select(i, ...))
	end
	queue:Push(LOG_LINE_TERMINATE_STRING)
	if queue.active == false then ActivateProcessing() end
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

function lf.DeactivateProcessors() 
	for _, processor in pairs(libint.LogProcessors) do
		processor:Dectivate()
	end
end

function lib.InitializeCalculations()
	if isFileInitialized == true then return false end
	logger = lf.initSublogger("calc")
	libint.LogProcessingQueue = LogProcessingQueue

    isFileInitialized = true
	return true
end