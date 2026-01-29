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
---@return {[integer]: boolean} unitIds
function lib.GetFriendlyUnits(fight)
	unitIds = {}

	for unitId, unit in pairs(fight.units) do
		---@cast unit UnitData
		if unit.isFriendly == true then
			unitIds[unitId] = true
		end
	end
	return unitIds
end

---@param fight Fight
---@return {[integer]: boolean} unitIds
function lib.GetEnemyUnits(fight)
	unitIds = {}

	for unitId, unit in pairs(fight.units) do
		---@cast unit UnitData
		if unit.isFriendly == false then
			unitIds[unitId] = true
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
---@param targetUnitIds {[integer]: bool} | nil -- if nil, all enemy units
---@param abilityIds {[integer]: bool} | nil -- if nil, all abilities
---@param dataOut DamageAbilityData | nil -- if provided, will be used to store the result
---@return DamageAbilityData | nil
local function GetUnitDamageDoneToUnits(fight, sourceUnitId, targetUnitIds, abilityIds, dataOut)
	local data = fight.damageDone[sourceUnitId]

	if data == nil then
		return
	end

	targetUnitIds = targetUnitIds or lib.GetEnemyUnits(fight)
	if NonContiguousCount(targetUnitIds) == 0 then
		return
	end

	dataOut = dataOut or lf.InitDamageAbilityData(0)

	for unitId in pairs(targetUnitIds) do
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
---@param targetUnitIds {[integer]: bool} | nil -- if nil, all enemy units
---@param abilityIds {[integer]: bool} | nil -- if nil, all abilities
---@return DamageAbilityData | nil
function lib.GetPlayerDamageDoneToUnits(fight, targetUnitIds, abilityIds)
	local playerId = fight.unitIds.player
	return GetUnitDamageDoneToUnits(fight, playerId, targetUnitIds, abilityIds)
end

--- Returns aggregated data of damage done by all units to specified target units with specified abilities
---@param fight Fight
---@param targetUnitIds {[integer]: bool} | nil -- if nil, all enemy units
---@param abilityIds {[integer]: bool} | nil -- if nil, all abilities
---@return DamageAbilityData | nil
function lib.GetAllDamageDoneToUnits(fight, targetUnitIds, abilityIds)
	local data = fight.damageDone
	local dataOut = lf.InitDamageAbilityData(0)

	for sourceUnitId, sourceData in pairs(data) do
		GetUnitDamageDoneToUnits(fight, sourceUnitId, targetUnitIds, abilityIds, dataOut)
	end

	return dataOut
end

--- Returns aggregated data of damage received by a unit from specified source units with specified abilities
---@param fight Fight
---@param targetUnitId integer
---@param sourceUnitIds {[integer]: bool} | nil -- if nil, all enemy units
---@param abilityIds {[integer]: bool} | nil -- if nil, all abilities
---@param dataOut DamageAbilityData | nil -- if provided, will be used to store the result
---@return DamageAbilityData | nil
local function GetUnitDamageReceivedByUnits(fight, targetUnitId, sourceUnitIds, abilityIds, dataOut)
	local data = fight.damageReceived[targetUnitId]

	if data == nil then
		return dataOut
	end

	sourceUnitIds = sourceUnitIds or lib.GetEnemyUnits(fight)
	if NonContiguousCount(sourceUnitIds) == 0 then
		return dataOut
	end

	dataOut = dataOut or lf.InitDamageAbilityData(0)

	for unitId in pairs(sourceUnitIds) do
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
---@param sourceUnitIds {[integer]: bool} | nil -- if nil, all enemy units
---@param abilityIds {[integer]: bool} | nil -- if nil, all abilities
---@return DamageAbilityData | nil
function lib.GetPlayerDamageReceivedByUnits(fight, sourceUnitIds, abilityIds)
	local playerId = fight.unitIds.player
	return GetUnitDamageReceivedByUnits(fight, playerId, sourceUnitIds, abilityIds)
end

--- Returns aggregated data of damage received by all units from specified source units with specified abilities
---@param fight Fight
---@param sourceUnitIds {[integer]: bool} | nil -- if nil, all enemy units
---@param abilityIds {[integer]: bool} | nil -- if nil, all abilities
---@return DamageAbilityData | nil
function lib.GetAllDamageReceivedByUnits(fight, sourceUnitIds, abilityIds)
	local data = fight.damageReceived
	local dataOut = lf.InitDamageAbilityData(0)

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
---@param targetUnitIds {[integer]: bool} | nil -- if nil, all friendly units
---@param abilityIds {[integer]: bool} | nil -- if nil, all abilities
---@param dataOut HealAbilityData | nil -- if provided, will be used to store the result
---@return HealAbilityData | nil
function lib.GetUnitHealingDoneToUnits(fight, sourceUnitId, targetUnitIds, abilityIds, dataOut)
	local data = fight.healingDone[sourceUnitId]

	if data == nil then
		return
	end

	targetUnitIds = targetUnitIds or lib.GetFriendlyUnits(fight)
	if NonContiguousCount(targetUnitIds) == 0 then
		return
	end

	dataOut = dataOut or lf.InitHealAbilityData(0)

	for unitId in pairs(targetUnitIds) do
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
---@param targetUnitIds {[integer]: bool} | nil -- if nil, all friendly units
---@param abilityIds {[integer]: bool} | nil -- if nil, all abilities
---@return HealAbilityData | nil
function lib.GetPlayerHealingDoneToUnits(fight, targetUnitIds, abilityIds)
	local playerId = fight.unitIds.player
	return lib.GetUnitHealingDoneToUnits(fight, playerId, targetUnitIds, abilityIds)
end

---@param fight Fight
---@param targetUnitIds {[integer]: bool} | nil -- if nil, all friendly units
---@param abilityIds {[integer]: bool} | nil -- if nil, all abilities
---@return HealAbilityData | nil
function lib.GetAllHealingDoneToUnits(fight, targetUnitIds, abilityIds)
	local data = fight.healingDone
	local dataOut = lf.InitHealAbilityData(0)

	for sourceUnitId, sourceData in pairs(data) do
		lib.GetUnitHealingDoneToUnits(fight, sourceUnitId, targetUnitIds, abilityIds, dataOut)
	end
	return dataOut
end

--- Returns aggregated data of healing received by a unit from specified source units with specified abilities
---@param fight Fight
---@param targetUnitId integer
---@param sourceUnitIds {[integer]: bool} | nil -- if nil, all friendly units
---@param abilityIds {[integer]: bool} | nil -- if nil, all abilities
---@return HealAbilityData | nil
function lib.GetUnitHealingReceivedByUnits(fight, targetUnitId, sourceUnitIds, abilityIds, dataOut)
	local data = fight.healingReceived[targetUnitId]

	if data == nil then
		return
	end

	sourceUnitIds = sourceUnitIds or lib.GetFriendlyUnits(fight)
	if NonContiguousCount(sourceUnitIds) == 0 then
		return
	end

	dataOut = dataOut or lf.InitHealAbilityData(0)

	for unitId in pairs(sourceUnitIds) do
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
---@param sourceUnitIds {[integer]: bool} | nil -- if nil, all friendly units
---@param abilityIds {[integer]: bool} | nil -- if nil, all abilities
---@return HealAbilityData | nil
function lib.GetPlayerHealingReceivedByUnits(fight, sourceUnitIds, abilityIds)
	local playerId = fight.unitIds.player
	return lib.GetUnitHealingReceivedByUnits(fight, playerId, sourceUnitIds, abilityIds)
end
--- Returns aggregated data of healing received by all units from specified source units with specified abilities
---@param fight Fight
---@param sourceUnitIds {[integer]: bool} | nil -- if nil, all friendly units
---@param abilityIds {[integer]: bool} | nil -- if nil, all abilities
---@return HealAbilityData | nil
function lib.GetAllHealingReceivedByUnits(fight, sourceUnitIds, abilityIds)
	local data = fight.healingReceived
	local dataOut = lf.InitHealAbilityData(0)

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
