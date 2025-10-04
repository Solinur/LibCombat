local lib = LibCombat2
local libint = lib.internal
local lf = libint.functions
local logger

local playerActivatedTime = 10000
local frameIndex = 1
local frameData = {}
local currentsecond

local size = zo_floor((1/GetCVar("MinFrameTime.2") + 40)/20)*20

for i = 1, size do

	frameData[i] = 0

end

local function onFrameUpdate()

	local new = GetFrameDeltaTimeSeconds()
	local now = GetTimeStamp()

	frameData[frameIndex] = new

	if now == currentsecond then

		frameIndex = frameIndex + 1

	else

		local timeMs = GetGameTimeMilliseconds()

		local sum = 0
		local min = 100
		local max = 0

		for k = 1, frameIndex do

			local v = frameData[k]

			sum = sum + v

			min = zo_min(v, min)
			max = zo_max(v, max)

		end

		lf.FireCallback(LIBCOMBAT_LOG_EVENT_PERFORMANCE, timeMs, frameIndex/sum, 1/max, 1/min, GetLatency())

		frameIndex = 1
		currentsecond = now

	end
end

local function enableLogging()

	frameIndex = 1
	currentsecond = GetTimeStamp()

	local active = EVENT_MANAGER:RegisterForUpdate("LibCombat_Frames", 0, onFrameUpdate)

	EVENT_MANAGER:UnregisterForUpdate("LibCombat_Frames_Enable")

end

local function onPlayerActivated2()

	EVENT_MANAGER:RegisterForUpdate("LibCombat_Frames_Enable", playerActivatedTime , enableLogging)

end

local function onPlayerDeactivated()
	EVENT_MANAGER:UnregisterForUpdate("LibCombat_Frames")
end

libint.Events.Performance = libint.EventHandler:New(
	{LIBCOMBAT_LOG_EVENT_PERFORMANCE},
	function (self)
		self:RegisterEvent(EVENT_PLAYER_DEACTIVATED, onPlayerDeactivated)
		self:RegisterEvent(EVENT_PLAYER_ACTIVATED, onPlayerActivated2)
		self.active = true
	end
)

local isFileInitialized = false

function libint.InitializePerformance()
	if isFileInitialized == true then return false end
	logger = lf.initSublogger("performance")

    isFileInitialized = true
	return true

end