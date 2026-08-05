-- Headless tests for the pure logic exposed on MoxieTracker's addon-private
-- `ns` table (see MoxieTracker.lua:21 and #12). Run with: lua5.1 tests/run.lua
-- Exits non-zero on any failure so CI catches a regression here the same way
-- it catches a luacheck or syntax failure.

local stub = dofile("tests/stub.lua")
local fixtures = stub.install()

local ns = {}
local loadAddon = assert(loadfile("MoxieTracker.lua"))
loadAddon("MoxieTracker", ns)

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

print(string.format("%d checks, %d failure(s)", count, failures))
if failures > 0 then
    os.exit(1)
end
