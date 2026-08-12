-- Headless tests for the pure logic exposed on MoxieTracker's addon-private
-- `ns` table (see MoxieTracker_Config.lua and #12). Run with:
-- lua5.1 tests/run.lua
-- Exits non-zero on any failure so CI catches a regression here the same way
-- it catches a luacheck or syntax failure.

local stub = dofile("tests/stub.lua")
local fixtures = stub.install()

-- Loads every Lua file MoxieTracker.toc lists, in order, against a shared ns
-- -- mirrors exactly how the client loads a multi-file addon (#14), and
-- stays correct automatically as files are added or reordered later.
local function LoadAddonFiles(tocPath, addonName, ns)
    local toc = assert(io.open(tocPath, "r"))
    for line in toc:lines() do
        local file = line:match("^%s*(.-)%s*$")
        if file ~= "" and not file:match("^##") then
            local chunk = assert(loadfile(file))
            chunk(addonName, ns)
        end
    end
    toc:close()
end

local ns = {}
LoadAddonFiles("MoxieTracker.toc", "MoxieTracker", ns)

local failures = 0
local count = 0

local function check(name, condition, detail)
    count = count + 1
    if not condition then
        failures = failures + 1
        print(string.format("FAIL: %s%s", name, detail and (" -- " .. detail) or ""))
    end
end

local function assertEqual(name, actual, expected)
    check(name, actual == expected, string.format("expected %s, got %s", tostring(expected), tostring(actual)))
end

-- Colour codes from MoxieTracker.lua. Not exposed on ns (they are formatting
-- constants, not logic), so this is the one place the test file must agree
-- with the addon on their literal values.
local GREEN = "|cff33ff33"
local YELLOW = "|cffffd200"
local RED = "|cffff3333"
local WHITE = "|cffffffff"

-- Finds a tracked entry by name so tests read naturally; CollectTracked's own
-- sort order is not what is under test here.
local function findByName(tracked, name)
    for _, entry in ipairs(tracked) do
        if entry.name == name then
            return entry
        end
    end
    return nil
end

--------------------------------------------------------------------------
-- 1. Dedupe and hidden-row precedence (MoxieTracker.lua ~334-364).
-- An entry is marked seen before the hidden check, so a hidden row cannot
-- re-enter through a later pass that identifies it a different way.
--------------------------------------------------------------------------
do
    fixtures.reset()
    fixtures.setCurrency(3376, "Shard of Dundun", 5)
    -- Same currency, reachable a second time through the keyword-fallback
    -- pass, but with a link that fails to resolve -- exactly the case the
    -- name-based dedupe backstop exists for.
    fixtures.setCurrencyList({
        { id = 3376, name = "Shard of Dundun", quantity = 5, noLink = true },
    })
    MoxieTrackerDB.hidden = { ["currency:3376"] = true }

    local visible = ns.CollectTracked(false)
    check("hidden row excluded from the default view", findByName(visible, "Shard of Dundun") == nil)

    local withHidden = ns.CollectTracked(true)
    local matches = 0
    for _, entry in ipairs(withHidden) do
        if entry.name == "Shard of Dundun" then
            matches = matches + 1
        end
    end
    assertEqual("hidden row appears exactly once with includeHidden", matches, 1)

    local entry = findByName(withHidden, "Shard of Dundun")
    check("hidden row is flagged hidden", entry ~= nil and entry.hidden == true)
end

--------------------------------------------------------------------------
-- 1b. Dedupe across two ID-bearing passes (always-shown vs. bag item), no
-- hidden rows involved -- a plain double-count would be a visible bug.
--------------------------------------------------------------------------
do
    fixtures.reset()
    fixtures.setCurrency(3377, "Unalloyed Abundance", 900)
    fixtures.setCurrencyList({
        { id = 3377, name = "Unalloyed Abundance", quantity = 900 },
    })

    local tracked = ns.CollectTracked(false)
    local matches = 0
    for _, entry in ipairs(tracked) do
        if entry.name == "Unalloyed Abundance" then
            matches = matches + 1
        end
    end
    assertEqual("currency found by ID and by keyword list is not duplicated", matches, 1)
end

--------------------------------------------------------------------------
-- 2. EntryKey stability. These are persisted SavedVariables keys, so their
-- exact shape matters -- a change here silently orphans a user's hidden rows.
--------------------------------------------------------------------------
do
    assertEqual("currency key form", ns.EntryKey(3376, nil, "Shard of Dundun"), "currency:3376")
    assertEqual("item key form", ns.EntryKey(nil, 245345, "Fused Vitality"), "item:245345")
    assertEqual("name-fallback key form", ns.EntryKey(nil, nil, "Some Currency"), "name:some currency")
    assertEqual("name-fallback key is lowercased", ns.EntryKey(nil, nil, "MiXeD CaSe"), "name:mixed case")
    assertEqual("currency ID takes precedence over item ID", ns.EntryKey(3376, 245345, "x"), "currency:3376")
end

--------------------------------------------------------------------------
-- 3. Colour thresholds.
--------------------------------------------------------------------------
do
    -- Shard of Dundun: green only at 6, red at 7-8, yellow otherwise.
    assertEqual("Shard of Dundun below threshold", ns.GetQuantityColor({ currencyID = 3376, quantity = 5 }), YELLOW)
    assertEqual("Shard of Dundun at green", ns.GetQuantityColor({ currencyID = 3376, quantity = 6 }), GREEN)
    assertEqual("Shard of Dundun at red (cap side)", ns.GetQuantityColor({ currencyID = 3376, quantity = 7 }), RED)
    assertEqual("Shard of Dundun at red (max)", ns.GetQuantityColor({ currencyID = 3376, quantity = 8 }), RED)

    -- Unalloyed Abundance: green at 800+.
    assertEqual("Unalloyed Abundance below threshold",
        ns.GetQuantityColor({ currencyID = 3377, quantity = 799 }), YELLOW)
    assertEqual("Unalloyed Abundance at threshold", ns.GetQuantityColor({ currencyID = 3377, quantity = 800 }), GREEN)

    -- Fused Vitality (item, not currency): green at 20+.
    assertEqual("Fused Vitality below threshold", ns.GetQuantityColor({ itemID = 245345, quantity = 19 }), YELLOW)
    assertEqual("Fused Vitality at threshold", ns.GetQuantityColor({ itemID = 245345, quantity = 20 }), GREEN)

    -- Moxie, matched by ID: green at 600+.
    assertEqual("Moxie by ID below threshold", ns.GetQuantityColor({ currencyID = 3256, quantity = 599 }), YELLOW)
    assertEqual("Moxie by ID at threshold", ns.GetQuantityColor({ currencyID = 3256, quantity = 600 }), GREEN)

    -- Moxie reached only through the keyword fallback (no ID match): same
    -- threshold, matched by name instead.
    assertEqual("Moxie by name below threshold",
        ns.GetQuantityColor({ name = "Future Artisan Moxie", quantity = 599 }), YELLOW)
    assertEqual("Moxie by name at threshold",
        ns.GetQuantityColor({ name = "Future Artisan Moxie", quantity = 600 }), GREEN)

    -- Anything untracked and uncolored falls back to plain white.
    assertEqual("unknown currency has no color rule",
        ns.GetQuantityColor({ currencyID = 9999, name = "Doubloons", quantity = 1 }), WHITE)
end

--------------------------------------------------------------------------
-- 4. Threshold overrides. MoxieTrackerDB.thresholds lets the options panel
-- move these three cutoffs; Shard of Dundun is deliberately not among them
-- (its rule is a fixed band tied to the currency's actual in-game cap).
--------------------------------------------------------------------------
do
    MoxieTrackerDB.thresholds = { unalloyedAbundance = 900, moxie = 700, fusedVitality = 30 }

    assertEqual("Unalloyed Abundance respects override, below",
        ns.GetQuantityColor({ currencyID = 3377, quantity = 899 }), YELLOW)
    assertEqual("Unalloyed Abundance respects override, at",
        ns.GetQuantityColor({ currencyID = 3377, quantity = 900 }), GREEN)

    assertEqual("Moxie respects override, below", ns.GetQuantityColor({ currencyID = 3256, quantity = 699 }), YELLOW)
    assertEqual("Moxie respects override, at", ns.GetQuantityColor({ currencyID = 3256, quantity = 700 }), GREEN)

    assertEqual("Fused Vitality respects override, below",
        ns.GetQuantityColor({ itemID = 245345, quantity = 29 }), YELLOW)
    assertEqual("Fused Vitality respects override, at",
        ns.GetQuantityColor({ itemID = 245345, quantity = 30 }), GREEN)

    -- Old default (600) must no longer apply once overridden.
    assertEqual("Moxie override replaces the default, not adds to it",
        ns.GetQuantityColor({ currencyID = 3256, quantity = 600 }), YELLOW)

    MoxieTrackerDB.thresholds = nil
    assertEqual("clearing thresholds falls back to the default",
        ns.GetQuantityColor({ currencyID = 3256, quantity = 600 }), GREEN)
end

--------------------------------------------------------------------------
-- 5. Slash command dispatch (cross-addon slash command standard, #37).
--------------------------------------------------------------------------
do
    fixtures.reset()

    -- The stub's generic StubObject fabricates plain functions for any
    -- unconfigured field, which ns.RefreshOptions cannot survive indexing
    -- further (it is UI wiring, not the pure logic this suite targets).
    -- Forcing IsShown() false keeps every handler below off that path.
    ns.optionsPanel.IsShown = function() return false end

    local originalPrint = print
    local printedLines

    local function dispatch(msg)
        printedLines = {}
        print = function(line) table.insert(printedLines, line) end
        SlashCmdList["MOXIETRACKER"](msg)
        print = originalPrint
    end

    local function firstLineHas(needle)
        return printedLines[1] ~= nil and printedLines[1]:find(needle, 1, true) ~= nil
    end

    dispatch("")
    check("bare command opens the options panel (S2)", firstLineHas("no Settings panel"))

    dispatch("options")
    check("options opens the same way as bare", firstLineHas("no Settings panel"))

    dispatch("bogus")
    check("an unknown command names what was unrecognised (S4)", firstLineHas("Unknown command: bogus"))
    check("an unknown command falls back to the full help list", #printedLines > 1)

    dispatch("help")
    check("help prints no 'unknown command' line", not firstLineHas("Unknown command"))
    check("help prints the same list an unknown command falls back to", #printedLines > 1)

    MoxieTrackerDB.debugLogging = false
    dispatch("debug")
    assertEqual("bare debug toggles the current state", MoxieTrackerDB.debugLogging, true)
    dispatch("debug")
    assertEqual("bare debug toggles back", MoxieTrackerDB.debugLogging, false)

    dispatch("debug on")
    assertEqual("debug on sets the state explicitly", MoxieTrackerDB.debugLogging, true)
    dispatch("debug off")
    assertEqual("debug off sets the state explicitly", MoxieTrackerDB.debugLogging, false)

    MoxieTrackerDB.debugLogging = true
    dispatch("debug maybe")
    assertEqual("an invalid debug value is rejected instead of applied (S12)", MoxieTrackerDB.debugLogging, true)
    check("an invalid debug value is reported", firstLineHas("expected 'on', 'off' or 'dump'"))

    dispatch("debug dump")
    check("debug dump still prints the diagnostic block, not lost in the rename", #printedLines > 3)

    dispatch("reset")
    check("bare reset prints usage instead of doing nothing", firstLineHas("Usage: /moxie reset"))

    MoxieTrackerDB.hidden = { ["currency:9999"] = true }
    MoxieTrackerDB.mutedCharacters = { ["Borin-Stormrage"] = true }
    MoxieTrackerDB.hideKnowledgeWindow = true
    MoxieTrackerDB.thresholds = { moxie = 700 }
    MoxieTrackerDB.debugLogging = true
    ns.frame.pinned = true
    dispatch("reset settings")
    assertEqual("reset settings clears hidden rows", MoxieTrackerDB.hidden, nil)
    assertEqual("reset settings clears muted characters", MoxieTrackerDB.mutedCharacters, nil)
    assertEqual("reset settings clears the Knowledge Points window toggle", MoxieTrackerDB.hideKnowledgeWindow, nil)
    assertEqual("reset settings clears threshold overrides", MoxieTrackerDB.thresholds, nil)
    assertEqual("reset settings clears debug logging", MoxieTrackerDB.debugLogging, nil)
    assertEqual("reset settings unpins the panel, but does not move it (S9 split)", ns.frame.pinned, false)

    MoxieTrackerDB.offsetX, MoxieTrackerDB.offsetY = 99, 99
    dispatch("reset position")
    check("reset position reports what it did", firstLineHas("position reset"))
    assertEqual("reset position clears the saved offset, reset settings does not touch it",
        MoxieTrackerDB.offsetX, nil)

    dispatch("status")
    check("status prints a multi-line settings summary", #printedLines >= 3)

    dispatch("version")
    check("version prints the addon version", firstLineHas("v0.0.0-test"))

    -- Unchanged, addon-specific command (kept as-is per #37's deviation list).
    -- "pin" is not exercised here: flipping it true drives RefreshVisibility
    -- into the full render path, which needs real font-string metrics the
    -- generic frame stub cannot fabricate -- a stub-fidelity gap, not
    -- something this change touches.
    dispatch("showall")
    check("showall still works", firstLineHas("every row is visible again"))
end

--------------------------------------------------------------------------
-- 6. Knowledge points roster (#38).
--------------------------------------------------------------------------
do
    fixtures.reset()
    fixtures.setCharacter("Alaria", "Stormrage")

    -- Only three of the eleven professions have any unspent Knowledge; the
    -- other eight report no currency info at all, matching a character who
    -- hasn't touched those professions.
    fixtures.setCurrency(3150, "Alchemy Knowledge", 3) -- Alchemy
    fixtures.setCurrency(3158, "Mining Knowledge", 5)  -- Mining
    fixtures.setCurrency(3160, "Tailoring Knowledge", 2) -- Tailoring

    assertEqual("unspent knowledge sums across every tracked profession",
        ns.CollectUnspentKnowledge(), 10)

    local byProfession = ns.CollectUnspentKnowledgeByProfession()
    assertEqual("per-profession breakdown excludes professions at 0", #byProfession, 3)
    assertEqual("per-profession breakdown is name-sorted", byProfession[1].name, "Alchemy")
    assertEqual("per-profession breakdown carries each profession's own points", byProfession[1].points, 3)
    assertEqual("per-profession breakdown, second entry", byProfession[2].name, "Mining")
    assertEqual("per-profession breakdown, third entry", byProfession[3].name, "Tailoring")
end

do
    fixtures.reset()
    fixtures.setCharacter("Alaria", "Stormrage")
    fixtures.setCurrency(3150, "Alchemy Knowledge", 7)

    local key, name = ns.GetCharacterKey()
    assertEqual("character key includes the realm", key, "Alaria-Stormrage")
    assertEqual("character key also returns the bare name", name, "Alaria")

    ns.SnapshotKnowledge()
    assertEqual("snapshot records the current character under its key",
        MoxieTrackerDB.knowledge[key].points, 7)
    assertEqual("snapshot records the display name", MoxieTrackerDB.knowledge[key].name, "Alaria")
    assertEqual("snapshot records the per-profession breakdown",
        #MoxieTrackerDB.knowledge[key].professions, 1)
    assertEqual("the saved breakdown's profession is named",
        MoxieTrackerDB.knowledge[key].professions[1].name, "Alchemy")
end

do
    fixtures.reset()

    -- A different character's login already snapshotted some points.
    MoxieTrackerDB.knowledge = {
        ["Borin-Stormrage"] = { name = "Borin", points = 12 },
    }

    fixtures.setCharacter("Alaria", "Stormrage")
    fixtures.setCurrency(3150, "Alchemy Knowledge", 4)

    local roster = ns.CollectKnowledgeRoster()
    assertEqual("roster includes both the current and a previously-seen character", #roster, 2)
    assertEqual("roster is sorted by name", roster[1].name, "Alaria")
    assertEqual("the current character's entry is always present", roster[1].points, 4)
    assertEqual("a saved character's entry carries over", roster[2].name, "Borin")
    assertEqual("a saved character's points come from storage, not live currency", roster[2].points, 12)
end

do
    fixtures.reset()
    fixtures.setCharacter("Alaria", "Stormrage")

    -- The current character's own saved snapshot is stale (5); live currency
    -- has since changed (9). The roster must report the live value, not the
    -- stale one -- the whole point of not waiting for the next login.
    MoxieTrackerDB.knowledge = {
        ["Alaria-Stormrage"] = { name = "Alaria", points = 5 },
    }
    fixtures.setCurrency(3150, "Alchemy Knowledge", 9)

    local roster = ns.CollectKnowledgeRoster()
    assertEqual("the current character's roster entry is live, not the stale snapshot",
        roster[1].points, 9)
end

--------------------------------------------------------------------------
-- 7. Muted characters (#38 follow-up). A muted character is dropped from
-- the roster everywhere except the options panel's own list, which needs
-- to keep showing it (unchecked) to offer un-muting it.
--------------------------------------------------------------------------
do
    fixtures.reset()

    assertEqual("a character starts unmuted", ns.IsCharacterMuted("Borin-Stormrage"), false)
    ns.SetCharacterMuted("Borin-Stormrage", true)
    assertEqual("SetCharacterMuted(true) marks the character muted",
        ns.IsCharacterMuted("Borin-Stormrage"), true)
    ns.SetCharacterMuted("Borin-Stormrage", false)
    assertEqual("SetCharacterMuted(false) clears it again", ns.IsCharacterMuted("Borin-Stormrage"), false)
end

do
    fixtures.reset()
    MoxieTrackerDB.knowledge = {
        ["Borin-Stormrage"] = { name = "Borin", points = 12 },
    }
    ns.SetCharacterMuted("Borin-Stormrage", true)

    fixtures.setCharacter("Alaria", "Stormrage")
    fixtures.setCurrency(3150, "Alchemy Knowledge", 4)

    local roster = ns.CollectKnowledgeRoster()
    assertEqual("a muted character is excluded from the default roster", #roster, 1)
    assertEqual("the unmuted current character remains", roster[1].name, "Alaria")

    local withMuted = ns.CollectKnowledgeRoster(true)
    assertEqual("includeMuted=true keeps the muted character listed", #withMuted, 2)
    local borin
    for _, entry in ipairs(withMuted) do
        if entry.name == "Borin" then
            borin = entry
        end
    end
    check("the muted character's entry is flagged muted", borin ~= nil and borin.muted == true)
    check("the unmuted character's entry is not flagged muted",
        withMuted[1].name == "Alaria" and withMuted[1].muted == false)
end

--------------------------------------------------------------------------
-- 8. Per-profession breakdown on the roster (the "show it indented per
-- profession" follow-up to #38).
--------------------------------------------------------------------------
do
    fixtures.reset()
    fixtures.setCharacter("Tharavol", "Stormrage")
    fixtures.setCurrency(3153, "Engineering Knowledge", 2) -- Engineering
    fixtures.setCurrency(3160, "Tailoring Knowledge", 2)   -- Tailoring

    local roster = ns.CollectKnowledgeRoster()
    assertEqual("the current character's roster entry carries its breakdown", #roster[1].professions, 2)
    assertEqual("current character total still sums the breakdown", roster[1].points, 4)
    assertEqual("breakdown entry is name-sorted, first", roster[1].professions[1].name, "Engineering")
    assertEqual("breakdown entry is name-sorted, second", roster[1].professions[2].name, "Tailoring")
end

do
    fixtures.reset()

    -- A character saved before the per-profession breakdown existed: only
    -- `points` and `name`, no `professions` field. Must not error, and must
    -- still report its total.
    MoxieTrackerDB.knowledge = {
        ["Borin-Stormrage"] = { name = "Borin", points = 9 },
    }
    fixtures.setCharacter("Alaria", "Stormrage")

    local roster = ns.CollectKnowledgeRoster()
    local borin
    for _, entry in ipairs(roster) do
        if entry.name == "Borin" then
            borin = entry
        end
    end
    check("a pre-breakdown character entry still appears", borin ~= nil)
    check("its professions field is absent rather than fabricated", borin ~= nil and borin.professions == nil)
    assertEqual("its total still comes through", borin and borin.points, 9)
end

--------------------------------------------------------------------------
-- 9. Per-character profession muting (options panel follow-up to #38).
-- Finer-grained than character muting: hides one profession's points for
-- one character without dropping the whole character from the roster.
--------------------------------------------------------------------------
do
    fixtures.reset()

    assertEqual("a profession starts unmuted",
        ns.IsKnowledgeProfessionMuted("Borin-Stormrage", "Mining"), false)
    ns.SetKnowledgeProfessionMuted("Borin-Stormrage", "Mining", true)
    assertEqual("SetKnowledgeProfessionMuted(true) marks it muted",
        ns.IsKnowledgeProfessionMuted("Borin-Stormrage", "Mining"), true)
    assertEqual("a different profession for the same character is unaffected",
        ns.IsKnowledgeProfessionMuted("Borin-Stormrage", "Tailoring"), false)
    assertEqual("the same profession for a different character is unaffected",
        ns.IsKnowledgeProfessionMuted("Alaria-Stormrage", "Mining"), false)
    ns.SetKnowledgeProfessionMuted("Borin-Stormrage", "Mining", false)
    assertEqual("SetKnowledgeProfessionMuted(false) clears it again",
        ns.IsKnowledgeProfessionMuted("Borin-Stormrage", "Mining"), false)
end

do
    fixtures.reset()
    fixtures.setCharacter("Tharavol", "Stormrage")
    fixtures.setCurrency(3153, "Engineering Knowledge", 2) -- Engineering
    fixtures.setCurrency(3160, "Tailoring Knowledge", 3)   -- Tailoring

    local key = ns.GetCharacterKey()
    ns.SetKnowledgeProfessionMuted(key, "Engineering", true)

    local roster = ns.CollectKnowledgeRoster()
    assertEqual("a muted profession is dropped from the live breakdown", #roster[1].professions, 1)
    assertEqual("the remaining profession is the unmuted one", roster[1].professions[1].name, "Tailoring")
    assertEqual("the character's total excludes the muted profession's points", roster[1].points, 3)
end

do
    fixtures.reset()

    -- A different character's stored snapshot has two professions; one is
    -- muted after the fact, without that character logging in again.
    MoxieTrackerDB.knowledge = {
        ["Borin-Stormrage"] = {
            name = "Borin",
            points = 15,
            professions = {
                { name = "Alchemy", points = 6 },
                { name = "Mining", points = 9 },
            },
        },
    }
    ns.SetKnowledgeProfessionMuted("Borin-Stormrage", "Mining", true)

    fixtures.setCharacter("Alaria", "Stormrage")

    local roster = ns.CollectKnowledgeRoster()
    local borin
    for _, entry in ipairs(roster) do
        if entry.name == "Borin" then
            borin = entry
        end
    end
    check("the stored character still appears", borin ~= nil)
    assertEqual("its muted profession is dropped without a new login", borin and #borin.professions, 1)
    assertEqual("its remaining profession is the unmuted one", borin and borin.professions[1].name, "Alchemy")
    assertEqual("its total is re-summed from what's left, not the stored total", borin and borin.points, 6)
end

do
    fixtures.reset()
    fixtures.setCharacter("Tharavol", "Stormrage")
    fixtures.setCurrency(3153, "Engineering Knowledge", 2)

    -- A pre-breakdown legacy entry (no `professions` field) can't be filtered
    -- by profession -- nothing to check it against -- so it must pass
    -- through untouched rather than erroring.
    MoxieTrackerDB.knowledge = {
        ["Borin-Stormrage"] = { name = "Borin", points = 9 },
    }

    local roster = ns.CollectKnowledgeRoster()
    local borin
    for _, entry in ipairs(roster) do
        if entry.name == "Borin" then
            borin = entry
        end
    end
    check("a pre-breakdown entry is unaffected by profession muting",
        borin ~= nil and borin.professions == nil and borin.points == 9)
end

do
    fixtures.reset()
    fixtures.setCharacter("Tharavol", "Stormrage")
    fixtures.setCurrency(3153, "Engineering Knowledge", 2)
    fixtures.setCurrency(3160, "Tailoring Knowledge", 3)

    MoxieTrackerDB.knowledge = {
        ["Borin-Stormrage"] = {
            name = "Borin",
            points = 4,
            professions = { { name = "Mining", points = 4 } },
        },
    }
    ns.SetKnowledgeProfessionMuted("Tharavol-Stormrage", "Engineering", true)
    ns.SetCharacterMuted("Borin-Stormrage", true)

    local list = ns.CollectKnowledgeProfessionRoster()
    assertEqual("a fully muted character contributes no rows", #list, 2)
    assertEqual("rows are sorted by character then profession", list[1].professionName, "Engineering")
    check("a muted profession is listed but flagged muted",
        list[1].characterName == "Tharavol" and list[1].muted == true)
    check("an unmuted profession is listed and flagged unmuted",
        list[2].professionName == "Tailoring" and list[2].muted == false)
end

print(string.format("%d checks, %d failure(s)", count, failures))
if failures > 0 then
    os.exit(1)
end
