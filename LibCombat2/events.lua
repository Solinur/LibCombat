-- This file provides the framework to (de-)register the required set of events

---@class LibCombat2
local lib = LibCombat2
---@class LCint
local libint = lib.internal
---@class LCData
local ld = libint.data
---@class LCfunc
local lf = libint.functions
---@class Logger
local logger

local ActiveCallbackTypes = {}
libint.ActiveCallbackTypes = ActiveCallbackTypes

local Events = {}
libint.Events = Events

local EventHandler = ZO_Object:Subclass()
libint.EventHandler = EventHandler

---@diagnostic disable-next-line: duplicate-set-field
function EventHandler:New(...)
    local object = ZO_Object.New(self)
    object:Initialize(...)
    return object
end

function EventHandler:Initialize(callbacktypes,regfunc)
	self.data={}
	self.callbacktypes=callbacktypes
	self.active=false
	self.RegisterEvents = regfunc
end

function EventHandler:RegisterEvent(event, callback, ...) -- convinience function
	local filters = {...}

	libint.totalevents = (libint.totalevents or 0) + 1

    local eventId = lib.name .. libint.totalevents

	local active = EVENT_MANAGER:RegisterForEvent(eventId, event, callback)
	local filtered = false

	if #filters>0 and (#filters)%2==0 then
		filtered = EVENT_MANAGER:AddFilterForEvent(eventId, event, unpack(filters))
	end

	self.data[#self.data+1] = {

		["id"] = libint.totalevents,
		["event"] = event,
		["callback"] = callback,
		["active"] = active,
		["filtered"] = filtered,
		["filters"] = filters }  -- remove callbacks later, probably not necessary

	if active then libint.totalevents = libint.totalevents + 1 end

	if ld.isUIActivated and event == EVENT_PLAYER_ACTIVATED then callback(EVENT_PLAYER_ACTIVATED, false) end

	return active
end

function EventHandler:UpdateEvents()
	local condition = false

	for k, callbacktype in pairs(self.callbacktypes) do
		if NonContiguousCount(libint.ActiveCallbackTypes[callbacktype])>0 then condition = true break end
	end

	if condition == true and self.active == false then
		self:RegisterEvents()
	elseif condition == false and self.active == true then
		self:UnregisterEvents()
	end
end

function EventHandler:UnregisterEvents()
	for k,reg in pairs(self.data) do
		local inactive = EVENT_MANAGER:UnregisterForEvent(lib.name..reg.id, reg.event)

		if inactive then
			ZO_ClearTable(reg)
			self.data[k] = nil
		end
	end

	self.active = false
	if self.resetIds then ZO_ClearTable(libint.registeredSkills) end
end

local function UnregisterAllEvents()
	for _,Eventgroup in pairs(Events) do
		Eventgroup:UnregisterEvents()
	end
end

--  lib.UnregisterAllEvents = UnregisterAllEvents 	-- debug exposure

function lf.GetAllCallbackTypes()
	local t={}

	for i=LIBCOMBAT_EVENT_MIN,LIBCOMBAT_EVENT_MAX do
		t[i]=i
	end

	for i=LIBCOMBAT_LOG_EVENT_MIN,LIBCOMBAT_LOG_EVENT_MAX do
		t[i]=i
	end

	return t
end


-- Calllback Registrations

local function InitCallbackIndex()
	for i=LIBCOMBAT_EVENT_MIN,LIBCOMBAT_EVENT_MAX do
		ActiveCallbackTypes[i]={}
	end
	for i=LIBCOMBAT_LOG_EVENT_MIN,LIBCOMBAT_LOG_EVENT_MAX do
		ActiveCallbackTypes[i]={}
	end
end

local function UpdateEventRegistrations()
	for _,Eventgroup in pairs(Events) do
		Eventgroup:UpdateEvents()
	end
end

function lf.UpdateResources(name, callbacktype, callback)
	if ActiveCallbackTypes[callbacktype] == nil then return false end
	local oldCallback = ActiveCallbackTypes[callbacktype][name]

	if callback and oldCallback then 
		return false
	else
		ActiveCallbackTypes[callbacktype][name] = callback
		zo_callLater(UpdateEventRegistrations, 0)	-- delay a frame to avoid an issue if functions get registered and deregistered within the same frame
	end

	return true, oldCallback
end


local isFileInitialized = false

function libint.InitializeEvents()
	if isFileInitialized == true then return false end
	logger = lf.initSublogger("events")

	InitCallbackIndex()
	
	EVENT_MANAGER:RegisterForEvent("LibCombatActive", EVENT_PLAYER_ACTIVATED, function() ld.isUIActivated = true end)
	EVENT_MANAGER:RegisterForEvent("LibCombatActive", EVENT_PLAYER_DEACTIVATED, function() ld.isUIActivated = false end)

    isFileInitialized = true
	return true
end