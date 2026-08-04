if not Taneth then return end

LC2Test.RequireLibCombat("utility.lua")

local lib = LibCombat2
local libint = lib.internal
local lf = libint.functions

-- Queue:Pop logs through the file's sublogger, so the file has to be initialized before a test can
-- pop an empty queue. In the game client this already ran and returns false.
libint.InitializeUtility()

--- Swaps a global for the duration of fn and restores it even if fn throws. Used instead of editing
--- mocks.lua so the suite stays safe in-game, where the globals are the real API.
local function WithGlobal(name, value, fn)
	local original = _G[name]
	_G[name] = value
	local ok, err = pcall(fn)
	_G[name] = original
	assert(ok, err)
end

Taneth("LibCombat2", function()
	describe("spairs", function()
		it("iterates keys in sorted order", function()
			local seen = {}
			for key in lf.spairs({ c = 3, a = 1, b = 2 }) do
				seen[#seen + 1] = key
			end
			assert.same({ "a", "b", "c" }, seen)
		end)

		it("yields the value alongside the key", function()
			local seen = {}
			for key, value in lf.spairs({ c = 3, a = 1, b = 2 }) do
				seen[#seen + 1] = key .. value
			end
			assert.same({ "a1", "b2", "c3" }, seen)
		end)

		it("honours a custom comparator", function()
			local t = { a = 3, b = 1, c = 2 }
			local seen = {}
			for key in lf.spairs(t, function(source, a, b)
				return source[a] < source[b]
			end) do
				seen[#seen + 1] = key
			end
			assert.same({ "b", "c", "a" }, seen)
		end)
	end)

	describe("IsCPStarSlotted", function()
		-- Shaped like fights.lua GetCurrentCP: star id at odd indices, spent points at even ones,
		-- maxSlotIndex being the last index of the champion bar slots. Discipline 2 leaves its
		-- second slot empty, which is stored as 0, 0. Passive stars follow the slots.
		local CP = {
			version = 2,
			maxSlotIndex = 4,
			[1] = { 101, 50, 102, 20, 301, 10 },
			[2] = { 201, 50, 0, 0, 302, 10 },
		}

		it("finds a star in the first slot", function()
			assert.equals(true, lf.IsCPStarSlotted(CP, 101))
		end)

		it("finds a star in a later slot", function()
			assert.equals(true, lf.IsCPStarSlotted(CP, 102))
		end)

		it("finds a star in another discipline", function()
			assert.equals(true, lf.IsCPStarSlotted(CP, 201))
		end)

		it("does not treat a spent-points value as a star id", function()
			assert.equals(false, lf.IsCPStarSlotted(CP, 50))
		end)

		it("does not treat a passive star as slotted", function()
			assert.equals(false, lf.IsCPStarSlotted(CP, 301))
		end)

		it("does not match the 0 of an empty slot", function()
			assert.equals(false, lf.IsCPStarSlotted(CP, 0))
		end)

		it("returns false for an unslotted star", function()
			assert.equals(false, lf.IsCPStarSlotted(CP, 999))
		end)

		it("returns false when there are no champion bar slots", function()
			assert.equals(false, lf.IsCPStarSlotted({ version = 2, maxSlotIndex = 0, [1] = { 101, 50 } }, 101))
		end)

		it("returns false for a negative star id", function()
			assert.equals(false, lf.IsCPStarSlotted(CP, -1))
		end)
	end)

	describe("Queue", function()
		local function FilledQueue(...)
			local queue = lf.CreateQueue()
			for i = 1, select("#", ...) do
				queue:Push((select(i, ...)))
			end
			return queue
		end

		it("pops in FIFO order", function()
			local queue = lf.CreateQueue()
			queue:Push("a")
			queue:Push("b")
			assert.equals(2, queue:Size())
			assert.equals("a", queue:Pop())
			assert.equals("b", queue:Pop())
			assert.equals(0, queue:Size())
		end)

		it("starts out empty and reports emptiness again once drained", function()
			local queue = lf.CreateQueue()
			assert.equals(true, queue:IsEmpty())
			queue:Push("a")
			assert.equals(false, queue:IsEmpty())
			queue:Pop()
			assert.equals(true, queue:IsEmpty())
		end)

		it("keeps its indices advancing across interleaved pushes and pops", function()
			local queue = FilledQueue("a", "b")
			assert.equals("a", queue:Pop())
			queue:Push("c")
			assert.equals(2, queue:Size())
			assert.equals("b", queue:Pop())
			assert.equals("c", queue:Pop())
			assert.equals(true, queue:IsEmpty())
		end)

		it("returns nil when popping an empty queue", function()
			assert.equals(nil, lf.CreateQueue():Pop())
		end)

		-- Delete takes the absolute internal index, not a 1-based position: the first element sits at
		-- index 0 and every Pop moves that origin up by one.
		it("deletes from the middle and shifts the tail down", function()
			local queue = FilledQueue("a", "b", "c")
			assert.equals("b", queue:Delete(1))
			assert.equals(2, queue:Size())
			assert.equals("a", queue:Pop())
			assert.equals("c", queue:Pop())
		end)

		it("deletes the head by delegating to Pop", function()
			local queue = FilledQueue("a", "b")
			assert.equals("a", queue:Delete(0))
			assert.equals(1, queue:Size())
			assert.equals("b", queue:Pop())
		end)

		it("deletes the tail", function()
			local queue = FilledQueue("a", "b")
			assert.equals("b", queue:Delete(1))
			assert.equals(1, queue:Size())
			assert.equals("a", queue:Pop())
		end)

		it("indexes relative to the origin left by earlier pops", function()
			local queue = FilledQueue("a", "b", "c")
			queue:Pop()
			assert.equals(nil, queue:Delete(0))
			assert.equals("c", queue:Delete(2))
			assert.equals(1, queue:Size())
		end)

		it("returns nil for an out-of-range index", function()
			local queue = FilledQueue("a")
			assert.equals(nil, queue:Delete(5))
			assert.equals(1, queue:Size())
		end)

		it("returns nil for a non-numeric index", function()
			assert.equals(nil, FilledQueue("a"):Delete("0"))
		end)

		it("returns nil when deleting from an empty queue", function()
			assert.equals(nil, lf.CreateQueue():Delete(0))
		end)
	end)

	describe("GetFormattedAbilityName", function()
		it("returns an empty string for a nil id", function()
			assert.equals("", lib.GetFormattedAbilityName(nil))
		end)

		it("prefers a custom name over the API name", function()
			assert.equals(GetString(SI_LIBCOMBAT_LOG_BASEREG), lib.GetFormattedAbilityName(0))
		end)

		it("falls back to the API name", function()
			assert.equals(GetAbilityName(12345), lib.GetFormattedAbilityName(12345))
		end)

		it("normalizes the hyphenated Off-Balance name", function()
			WithGlobal("GetAbilityName", function()
				return "Off-Balance"
			end, function()
				assert.equals("Off Balance", lib.GetFormattedAbilityName(990001))
			end)
		end)

		it("caches the first lookup", function()
			local first = lib.GetFormattedAbilityName(990002)
			WithGlobal("GetAbilityName", function()
				return "Changed"
			end, function()
				assert.equals(first, lib.GetFormattedAbilityName(990002))
			end)
		end)

		it("uses the script name lookup for scripts", function()
			assert.equals(GetCraftedAbilityScriptDisplayName(7), lib.GetFormattedAbilityName(7, true))
		end)

		it("keeps script names in a separate cache from ability names", function()
			assert.equals(GetAbilityName(7), lib.GetFormattedAbilityName(7))
		end)
	end)

	describe("GetFormattedAbilityIcon", function()
		it("returns the missing-icon texture for a nil id", function()
			assert.equals("/esoui/art/icons/icon_missing.dds", lib.GetFormattedAbilityIcon(nil))
		end)

		it("passes a texture path through unchanged", function()
			assert.equals("custom/path.dds", lib.GetFormattedAbilityIcon("custom/path.dds"))
		end)

		it("returns the unknown-script texture for script id 0", function()
			assert.equals(
				"EsoUI/Art/crafting/gamepad/crafting_alchemy_trait_unknown.dds",
				lib.GetFormattedAbilityIcon(0, true)
			)
		end)

		it("prefers a custom icon over the API icon", function()
			assert.equals("esoui/art/icons/achievement_wrothgar_046.dds", lib.GetFormattedAbilityIcon(0))
		end)

		it("falls back to the API icon", function()
			assert.equals(GetAbilityIcon(12345), lib.GetFormattedAbilityIcon(12345))
		end)

		it("caches the first lookup", function()
			local first = lib.GetFormattedAbilityIcon(990003)
			WithGlobal("GetAbilityIcon", function()
				return "changed.dds"
			end, function()
				assert.equals(first, lib.GetFormattedAbilityIcon(990003))
			end)
		end)

		it("uses the script icon lookup for scripts", function()
			assert.equals(GetCraftedAbilityScriptIcon(7), lib.GetFormattedAbilityIcon(7, true))
		end)
	end)

	describe("AddCustomAbilityData", function()
		it("registers custom names and icons", function()
			lib.AddCustomAbilityData({ [990100] = "Custom Name" }, { [990100] = "custom/icon.dds" })
			assert.equals("Custom Name", lib.GetFormattedAbilityName(990100))
			assert.equals("custom/icon.dds", lib.GetFormattedAbilityIcon(990100))
		end)

		it("overrides an entry that was already cached", function()
			lib.GetFormattedAbilityName(990101)
			lib.GetFormattedAbilityIcon(990101)
			lib.AddCustomAbilityData({ [990101] = "Late Name" }, { [990101] = "late/icon.dds" })
			assert.equals("Late Name", lib.GetFormattedAbilityName(990101))
			assert.equals("late/icon.dds", lib.GetFormattedAbilityIcon(990101))
		end)

		it("accepts empty tables", function()
			lib.AddCustomAbilityData({}, {})
		end)
	end)

	describe("GetDamageColor", function()
		it("returns a distinct color per damage type", function()
			assert.equals(true, lib.GetDamageColor(DAMAGE_TYPE_FIRE) ~= lib.GetDamageColor(DAMAGE_TYPE_NONE))
		end)

		it("colors the non-damage keys too", function()
			assert.equals(true, lib.GetDamageColor("heal") ~= lib.GetDamageColor(DAMAGE_TYPE_NONE))
		end)

		it("falls back to the neutral color for an unknown damage type", function()
			assert.equals(lib.GetDamageColor(DAMAGE_TYPE_NONE), lib.GetDamageColor(-1))
			assert.equals(lib.GetDamageColor(DAMAGE_TYPE_NONE), lib.GetDamageColor(nil))
		end)
	end)

	describe("callbacks", function()
		-- Registered against a synthetic key rather than a real LIBCOMBAT_EVENT_*: in-game those have
		-- live listeners that would receive this test's payload.
		local TEST_KEY = 9999

		it("delivers the event key and payload, and stops after unregistering", function()
			libint.CallbackKeys[TEST_KEY] = "LibCombat2TestCallback"

			local seen
			local function callback(...)
				seen = { ... }
			end

			lf.RegisterCallback(TEST_KEY, callback)
			lf.FireCallback(TEST_KEY, "payload", 1)
			assert.same({ TEST_KEY, "payload", 1 }, seen)

			seen = nil
			lf.UnregisterCallback(TEST_KEY, callback)
			lf.FireCallback(TEST_KEY, "payload")
			assert.equals(nil, seen)

			libint.CallbackKeys[TEST_KEY] = nil
		end)
	end)
end)
