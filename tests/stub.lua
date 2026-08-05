-- Minimal fake of the WoW API surface MoxieTracker.lua touches at file scope.
--
-- MoxieTracker.lua is loaded whole (there is no module boundary to require()
-- around), so every top-level statement runs, including the frame/UI
-- construction -- not just the pure logic under test. Two kinds of stub cover
-- that:
--
-- 1. A generic "any method, any field, always chainable" object for the frame
--    API (CreateFrame, GameTooltip, UIParent, and everything created off
--    them). The file only ever calls methods on these and never inspects
--    their return values, so one catch-all shape is enough for all of it.
-- 2. Configurable fakes for C_CurrencyInfo, C_Item, and C_AddOns, since those
--    are what CollectTracked/GetQuantityColor actually read. Tests populate
--    these through the returned fixtures table before loading the addon.

local function StubObject()
    local obj = {}
    setmetatable(obj, {
        __index = function()
            return function()
                return StubObject()
            end
        end,
    })
    return obj
end

local M = {}

-- Installs the stub globals and returns a fixtures table tests use to set up
-- scenarios before loading MoxieTracker.lua against them.
function M.install()
    local currencies = {} -- [id] = { name = ..., quantity = ... }
    local currencyList = {} -- ordered list entries, as GetCurrencyListInfo returns them
    local items = {} -- [id] = { name = ..., count = ... }

    _G.MoxieTrackerDB = {}

    _G.C_CurrencyInfo = {
        GetCurrencyInfo = function(id)
            local c = currencies[id]
            return c and { name = c.name, quantity = c.quantity } or nil
        end,
        GetCurrencyListSize = function()
            return #currencyList
        end,
        GetCurrencyListInfo = function(index)
            local entry = currencyList[index]
            if not entry then
                return nil
            end
            if entry.isHeader then
                return { isHeader = true, name = entry.name, isHeaderExpanded = true }
            end
            return { isHeader = false, name = entry.name, quantity = entry.quantity }
        end,
        -- Real WoW resolves the ID from the link, not the list entry. A nil
        -- link (entry.noLink) simulates the "link failed to resolve" case
        -- CollectTracked's name-based dedupe backstop exists for.
        GetCurrencyListLink = function(index)
            local entry = currencyList[index]
            if not entry or entry.isHeader or entry.noLink then
                return nil
            end
            return "currencylink:" .. entry.id
        end,
        GetCurrencyIDFromLink = function(link)
            local id = link:match("^currencylink:(%d+)$")
            return id and tonumber(id) or nil
        end,
    }

    _G.C_Item = {
        GetItemInfo = function(id)
            local it = items[id]
            return it and it.name or nil
        end,
        GetItemCount = function(id)
            local it = items[id]
            return it and it.count or 0
        end,
        RequestLoadItemDataByID = function() end,
    }

    _G.C_AddOns = {
        GetAddOnMetadata = function(_, key)
            if key == "Version" then
                return "v0.0.0-test"
            end
            return nil
        end,
    }

    _G.SlashCmdList = {}
    _G.CreateFrame = function()
        return StubObject()
    end
    _G.GameTooltip = StubObject()
    _G.UIParent = StubObject()

    local fixtures
    fixtures = {
        setCurrency = function(id, name, quantity)
            currencies[id] = { name = name, quantity = quantity }
        end,
        setItem = function(id, name, count)
            items[id] = { name = name, count = count }
        end,
        -- list is an array of { id = , name = , quantity = , isHeader = , noLink = }
        setCurrencyList = function(list)
            currencyList = list
        end,
        -- Between test scenarios: clears every fixture and starts MoxieTrackerDB
        -- fresh, so one test's hidden rows or currencies cannot leak into the next.
        reset = function()
            currencies = {}
            currencyList = {}
            items = {}
            _G.MoxieTrackerDB = {}
        end,
    }
    return fixtures
end

return M
