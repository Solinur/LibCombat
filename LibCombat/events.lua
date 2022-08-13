local lib = LibCombat
local libint = lib.internal
local libdata = lib.data
local Print = libint.Print

local Events = {}
libint.Events = Events

local EventHandler = ZO_Object:Subclass()
libint.EventHandler = EventHandler

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

	if libdata.isUIActivated and event == EVENT_PLAYER_ACTIVATED then callback(EVENT_PLAYER_ACTIVATED, false) end

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

function libint.GetAllCallbackTypes()

	local t={}

	for i=LIBCOMBAT_EVENT_MIN,LIBCOMBAT_EVENT_MAX do

		t[i]=i

	end

	return t

end