-- Loads only the LibCombat2 files a suite needs, instead of the whole addon.
--
-- Standalone (ESOLua) only. In the game client the addon is already fully loaded by the time the
-- suites run, so RequireLibCombat has nothing to do and the `eso` module does not exist at all.

LC2Test = LC2Test or {}

local IN_GAME = ScriptBuildInfo ~= nil

local loaded = {}

--- Loads a single Lua file relative to the AddOns directory.
---
--- Uses eso.LoadLuaFile rather than eso.LoadAddon: LoadAddon swallows per-file errors, so a manifest
--- reports success while every file in it aborted mid-load. LoadLuaFile returns a success flag.
---@param path string
function LC2Test.Require(path)
	if IN_GAME or loaded[path] then
		return
	end
	assert(eso.LoadLuaFile(path, true), "failed to load " .. path)
	loaded[path] = true
end

--- Loads the named LibCombat2 files, plus the init chain they depend on.
---@param ... string file names within LibCombat2, e.g. "utility.lua"
function LC2Test.RequireLibCombat(...)
	if IN_GAME then
		return
	end

	LC2Test.Require("LibCombat2/lang/en.lua")
	LC2Test.Require("LibCombat2/init.lua")
	LC2Test.Require("LibCombat2/constants.lua")
	assert(LibCombat2.internal.InitializeGlobals(), "InitializeGlobals failed")

	for i = 1, select("#", ...) do
		LC2Test.Require("LibCombat2/" .. select(i, ...))
	end
end
