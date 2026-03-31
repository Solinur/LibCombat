-- This file contains handling of collected fight data

---@class LibCombat2
local lib = LibCombat2
---@class LCint
local libint = lib.internal
---@class LCData
local ld = libint.data
---@class LCUnits
local libunits = ld.units
---@class LCfunc
local lf = libint.functions
---@class Logger
local logger

local isFileInitialized = false

---@param fight Fight
---@return integer[] unitIds
function lib.GetFriendlyUnits(fight)
	local unitIds = {}

	for unitId, unit in pairs(fight.units) do
		if unit.isFriendly == true then
			unitIds[#unitIds + 1] = unitId
		end
	end
	return unitIds
end

---@param fight Fight
---@return integer[] unitIds
function lib.GetEnemyUnits(fight)
	local unitIds = {}

	for unitId, unit in pairs(fight.units) do
		if unit.isFriendly == false then
			unitIds[#unitIds + 1] = unitId
		end
	end
	return unitIds
end

---@param dataOut DamageAbilityData
---@param abilityData DamageAbilityData
local function CombineDamageAbilityData(dataOut, abilityData)
	dataOut.normalAmount = dataOut.normalAmount + abilityData.normalAmount
	dataOut.criticalAmount = dataOut.criticalAmount + abilityData.criticalAmount
	dataOut.blockedAmount = dataOut.blockedAmount + abilityData.blockedAmount
	dataOut.absorbedAmount = dataOut.absorbedAmount + abilityData.absorbedAmount
	dataOut.totalAmount = dataOut.totalAmount + abilityData.totalAmount

	dataOut.normalCount = dataOut.normalCount + abilityData.normalCount
	dataOut.criticalCount = dataOut.criticalCount + abilityData.criticalCount
	dataOut.blockedCount = dataOut.blockedCount + abilityData.blockedCount
	dataOut.absorbedCount = dataOut.absorbedCount + abilityData.absorbedCount
	dataOut.totalCount = dataOut.totalCount + abilityData.totalCount

	if dataOut.startTime == 0 or (abilityData.startTime < dataOut.startTime) then
		dataOut.startTime = abilityData.startTime
	end

	dataOut.endTime = zo_max(dataOut.endTime, abilityData.endTime)
end

--- Returns aggregated data of damage done by a unit to specified target units with specified abilities
---@param fight Fight
---@param sourceUnitId integer
---@param targetUnitIds? integer[] -- if nil or empty, the function does nothing
---@param abilityIds? table<integer, boolean> -- if nil, all abilities
---@param dataOut DamageAbilityData | nil -- if provided, will be used to store the result
---@return DamageAbilityData | nil
local function GetUnitDamageDoneToUnits(fight, sourceUnitId, targetUnitIds, abilityIds, dataOut)
	local data = fight.damageDone[sourceUnitId]

	if data == nil then
		return
	end

	if targetUnitIds == nil or NonContiguousCount(targetUnitIds) == 0 then
		return
	end

	dataOut = dataOut or lf.InitDamageAbilityData()

	for _, unitId in pairs(targetUnitIds) do
		-- TODO: Validate?
		local unitData = data[unitId]
		if unitData ~= nil then
			for abilityId, abilityData in pairs(unitData) do
				if type(abilityId) == "number" and (abilityIds == nil or abilityIds[abilityId]) then
					CombineDamageAbilityData(dataOut, abilityData)
				end
			end
		end
	end
	return dataOut
end

--- Returns aggregated data of damage done by the player to specified target units with specified abilities
---@param fight Fight
---@param targetUnitIds? integer[] -- if nil, all enemy units
---@param abilityIds? table<integer, boolean> -- if nil, all abilities
---@return DamageAbilityData | nil
function lib.GetPlayerDamageDoneToUnits(fight, targetUnitIds, abilityIds)
	local playerId = fight.unitIds.player
	targetUnitIds = targetUnitIds or lib.GetEnemyUnits(fight)
	return GetUnitDamageDoneToUnits(fight, playerId, targetUnitIds, abilityIds)
end

--- Returns aggregated data of damage done by all units to specified target units with specified abilities
---@param fight Fight
---@param targetUnitIds? integer[] -- if nil, all enemy units
---@param abilityIds? table<integer, boolean> -- if nil, all abilities
---@return DamageAbilityData | nil
function lib.GetDamageDoneToUnits(fight, targetUnitIds, abilityIds)
	local data = fight.damageDone
	local dataOut = lf.InitDamageAbilityData()
	targetUnitIds = targetUnitIds or lib.GetEnemyUnits(fight)

	for sourceUnitId, _ in pairs(data) do
		GetUnitDamageDoneToUnits(fight, sourceUnitId, targetUnitIds, abilityIds, dataOut)
	end

	return dataOut
end

---Returns data of damage done by a unit
---@param fight Fight
---@param unitId integer
---@return UnitDamageData
function lib.GetUnitDamageDone(fight, unitId)
	return fight.damageDone[unitId]
end

---Returns data of damage received by a unit
---@param fight Fight
---@param unitId integer
---@return UnitDamageData
function lib.GetUnitDamageReceived(fight, unitId)
	return fight.damageReceived[unitId]
end

---Returns data of healing done by a unit
---@param fight Fight
---@param unitId integer
---@return UnitHealData
function lib.GetUnitHealingDone(fight, unitId)
	return fight.healingDone[unitId]
end

---Returns data of healing received by a unit
---@param fight Fight
---@param unitId integer
---@return UnitHealData
function lib.GetUnitHealingReceived(fight, unitId)
	return fight.healingReceived[unitId]
end

--- Returns aggregated data of damage received by a unit from specified source units with specified abilities
---@param fight Fight
---@param targetUnitId integer
---@param sourceUnitIds? integer[] -- if nil or empty, the function does nothing
---@param abilityIds? table<integer, boolean> -- if nil, all abilities
---@param dataOut DamageAbilityData | nil -- if provided, will be used to store the result
---@return DamageAbilityData | nil
local function GetUnitDamageReceivedByUnits(fight, targetUnitId, sourceUnitIds, abilityIds, dataOut)
	local data = fight.damageReceived[targetUnitId]

	if data == nil then
		return dataOut
	end

	if sourceUnitIds == nil or NonContiguousCount(sourceUnitIds) == 0 then
		return dataOut
	end

	dataOut = dataOut or lf.InitDamageAbilityData()

	for _, unitId in pairs(sourceUnitIds) do
		-- TODO: Validate?

		local unitData = data[unitId]
		if unitData ~= nil then
			for abilityId, abilityData in pairs(unitData) do
				if type(abilityId) == "number" and (abilityIds == nil or abilityIds[abilityId]) then
					CombineDamageAbilityData(dataOut, abilityData)
				end
			end
		end
	end
	return dataOut
end

--- Returns aggregated data of damage received by the player from specified source units with specified abilities
---@param fight Fight
---@param sourceUnitIds? integer[] -- if nil, all enemy units
---@param abilityIds? table<integer, boolean> -- if nil, all abilities
---@return DamageAbilityData | nil
function lib.GetPlayerDamageReceivedByUnits(fight, sourceUnitIds, abilityIds)
	local playerId = fight.unitIds.player
	sourceUnitIds = sourceUnitIds or lib.GetEnemyUnits(fight)

	return GetUnitDamageReceivedByUnits(fight, playerId, sourceUnitIds, abilityIds)
end

--- Returns aggregated data of damage received by all units from specified source units with specified abilities
---@param fight Fight
---@param sourceUnitIds? integer[] -- if nil, all enemy units
---@param abilityIds? table<integer, boolean> -- if nil, all abilities
---@return DamageAbilityData | nil
function lib.GetDamageReceivedByUnits(fight, sourceUnitIds, abilityIds)
	local data = fight.damageReceived
	local dataOut = lf.InitDamageAbilityData()
	sourceUnitIds = sourceUnitIds or lib.GetEnemyUnits(fight)

	for sourceUnitId, sourceData in pairs(data) do
		GetUnitDamageReceivedByUnits(fight, sourceUnitId, sourceUnitIds, abilityIds, dataOut)
	end
	return dataOut
end

---@param dataOut HealAbilityData
---@param abilityData HealAbilityData
local function CombineHealAbilityData(dataOut, abilityData)
	dataOut.normalAmount = dataOut.normalAmount + abilityData.normalAmount
	dataOut.criticalAmount = dataOut.criticalAmount + abilityData.criticalAmount
	dataOut.overflowAmount = dataOut.overflowAmount + abilityData.overflowAmount
	dataOut.absorbedAmount = dataOut.absorbedAmount + abilityData.absorbedAmount
	dataOut.totalAmount = dataOut.totalAmount + abilityData.totalAmount

	dataOut.normalCount = dataOut.normalCount + abilityData.normalCount
	dataOut.criticalCount = dataOut.criticalCount + abilityData.criticalCount
	dataOut.overflowCount = dataOut.overflowCount + abilityData.overflowCount
	dataOut.absorbedCount = dataOut.absorbedCount + abilityData.absorbedCount
	dataOut.totalCount = dataOut.totalCount + abilityData.totalCount

	if dataOut.startTime == 0 or (abilityData.startTime < dataOut.startTime) then
		dataOut.startTime = abilityData.startTime
	end

	dataOut.endTime = zo_max(dataOut.endTime, abilityData.endTime)
end

---
---@param fight Fight
---@param sourceUnitId integer
---@param targetUnitIds? integer[] -- if nil or empty, the function does nothing
---@param abilityIds? table<integer, boolean> -- if nil, all abilities
---@param dataOut HealAbilityData | nil -- if provided, will be used to store the result
---@return HealAbilityData | nil
function lib.GetUnitHealingDoneToUnits(fight, sourceUnitId, targetUnitIds, abilityIds, dataOut)
	local data = fight.healingDone[sourceUnitId]

	if data == nil then
		return
	end

	if targetUnitIds == nil or NonContiguousCount(targetUnitIds) == 0 then
		return
	end

	dataOut = dataOut or lf.InitHealAbilityData()

	for _, unitId in ipairs(targetUnitIds) do
		-- TODO: Validate?

		local unitData = data[unitId]
		if unitData ~= nil then
			for abilityId, abilityData in pairs(unitData) do
				if type(abilityId) == "number" and (abilityIds == nil or abilityIds[abilityId]) then
					CombineHealAbilityData(dataOut, abilityData)
				end
			end
		end
	end
	return dataOut
end

--- Returns aggregated data of healing done by the player to specified target units with specified abilities
---@param fight Fight
---@param targetUnitIds? integer[] -- if nil, all friendly units
---@param abilityIds? table<integer, boolean> -- if nil, all abilities
---@return HealAbilityData | nil
function lib.GetPlayerHealingDoneToUnits(fight, targetUnitIds, abilityIds)
	local playerId = fight.unitIds.player
	targetUnitIds = targetUnitIds or lib.GetFriendlyUnits(fight)

	return lib.GetUnitHealingDoneToUnits(fight, playerId, targetUnitIds, abilityIds)
end

---@param fight Fight
---@param targetUnitIds? integer[] -- if nil, all friendly units
---@param abilityIds? table<integer, boolean> -- if nil, all abilities
---@return HealAbilityData | nil
function lib.GetHealingDoneToUnits(fight, targetUnitIds, abilityIds)
	local data = fight.healingDone
	local dataOut = lf.InitHealAbilityData()
	targetUnitIds = targetUnitIds or lib.GetFriendlyUnits(fight)

	for sourceUnitId, sourceData in pairs(data) do
		lib.GetUnitHealingDoneToUnits(fight, sourceUnitId, targetUnitIds, abilityIds, dataOut)
	end
	return dataOut
end

--- Returns aggregated data of healing received by a unit from specified source units with specified abilities
---@param fight Fight
---@param targetUnitId integer
---@param sourceUnitIds? integer[] -- if nil or empty, the function does nothing
---@param abilityIds? table<integer, boolean> -- if nil, all abilities
---@return HealAbilityData | nil
function lib.GetUnitHealingReceivedByUnits(fight, targetUnitId, sourceUnitIds, abilityIds, dataOut)
	local data = fight.healingReceived[targetUnitId]

	if data == nil then
		return
	end

	if sourceUnitIds == nil or NonContiguousCount(sourceUnitIds) == 0 then
		return
	end

	dataOut = dataOut or lf.InitHealAbilityData()

	for _, unitId in ipairs(sourceUnitIds) do
		-- TODO: Validate?

		local unitData = data[unitId]
		if unitData ~= nil then
			for abilityId, abilityData in pairs(unitData) do
				if type(abilityId) == "number" and (abilityIds == nil or abilityIds[abilityId]) then
					CombineHealAbilityData(dataOut, abilityData)
				end
			end
		end
	end
	return dataOut
end

--- Returns aggregated data of healing received by the player from specified source units with specified abilities
---@param fight Fight
---@param sourceUnitIds? integer[] -- if nil, all friendly units
---@param abilityIds? table<integer, boolean> -- if nil, all abilities
---@return HealAbilityData | nil
function lib.GetPlayerHealingReceivedByUnits(fight, sourceUnitIds, abilityIds)
	local playerId = fight.unitIds.player
	sourceUnitIds = sourceUnitIds or lib.GetFriendlyUnits(fight)

	return lib.GetUnitHealingReceivedByUnits(fight, playerId, sourceUnitIds, abilityIds)
end
--- Returns aggregated data of healing received by all units from specified source units with specified abilities
---@param fight Fight
---@param sourceUnitIds? integer[] -- if nil, all friendly units
---@param abilityIds? table<integer, boolean> -- if nil, all abilities
---@return HealAbilityData | nil
function lib.GetHealingReceivedByUnits(fight, sourceUnitIds, abilityIds)
	local data = fight.healingReceived
	local dataOut = lf.InitHealAbilityData()
	sourceUnitIds = sourceUnitIds or lib.GetFriendlyUnits(fight)

	for sourceUnitId, sourceData in pairs(data) do
		lib.GetUnitHealingReceivedByUnits(fight, sourceUnitId, sourceUnitIds, abilityIds, dataOut)
	end
	return dataOut
end

function libint.InitializeFightStatUtils()
	if isFileInitialized == true then
		return false
	end
	logger = lf.initSublogger("fightStatUtils")

	isFileInitialized = true
	return true
end
