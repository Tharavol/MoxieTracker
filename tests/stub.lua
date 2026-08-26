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
            if not c then
                return nil
            end
            return {
                name = c.name,
                quantity = c.quantity,
                maxQuantity = c.maxQuantity,
                rechargingCycleDurationMS = c.rechargingCycleDurationMS,
            }
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

    -- Real WoW provides Enum.Profession as a client-defined global (the
    -- actual numeric values are Blizzard's, not MoxieTracker's, and are
    -- irrelevant here -- ns.CONCENTRATION_PROFESSIONS only needs each key
    -- to be distinct and stable so its enum-to-name lookup round-trips).
    _G.Enum = {
        Profession = {
            Alchemy = 1,
            Blacksmithing = 2,
            Enchanting = 3,
            Engineering = 4,
            Herbalism = 5,
            Inscription = 6,
            Jewelcrafting = 7,
            Leatherworking = 8,
            Mining = 9,
            Skinning = 10,
            Tailoring = 11,
        },
    }

    local characterName, realmName = "TestChar", "TestRealm"
    _G.UnitName = function() return characterName end
    _G.GetRealmName = function() return realmName end

    -- Concentration discovery (#40): [skillLineID] = { profession = Enum.Profession.X,
    -- currencyID = n }. childSkillLineID is what
    -- C_TradeSkillUI.GetProfessionChildSkillLineID() returns -- nil means no
    -- profession window is open, matching the real API outside a crafting session.
    local childSkillLineID
    local skillLines = {}
    local serverTime = 1000000

    _G.C_TradeSkillUI = {
        GetProfessionChildSkillLineID = function()
            return childSkillLineID
        end,
        GetConcentrationCurrencyID = function(skillLineID)
            local entry = skillLines[skillLineID]
            return entry and entry.currencyID or nil
        end,
        GetProfessionInfoBySkillLineID = function(skillLineID)
            local entry = skillLines[skillLineID]
            return entry and { profession = entry.profession } or nil
        end,
    }

    _G.GetServerTime = function()
        return serverTime
    end

    -- ns.IsProfessionLearned (#40): GetProfessions() returns up to six
    -- profession-book slot indices, and GetProfessionInfo(slotIndex)'s 7th
    -- return value is that slot's skillLineID. The stub collapses "slot
    -- index" and "skillLineID" into the same value -- nothing in
    -- ns.IsProfessionLearned cares that they're distinct concepts in the
    -- real API, only that GetProfessionInfo(slot) resolves to a skillLineID
    -- that C_TradeSkillUI.GetProfessionInfoBySkillLineID (already stubbed
    -- above via setOpenProfession) can look up.
    local learnedSkillLineIDs = {}

    _G.GetProfessions = function()
        return learnedSkillLineIDs[1], learnedSkillLineIDs[2], learnedSkillLineIDs[3],
            learnedSkillLineIDs[4], learnedSkillLineIDs[5], learnedSkillLineIDs[6]
    end

    _G.GetProfessionInfo = function(skillLineID)
        return nil, nil, nil, nil, nil, nil, skillLineID
    end

    local fixtures
    fixtures = {
        setCurrency = function(id, name, quantity, maxQuantity, rechargingCycleDurationMS)
            currencies[id] = {
                name = name,
                quantity = quantity,
                maxQuantity = maxQuantity,
                rechargingCycleDurationMS = rechargingCycleDurationMS,
            }
        end,
        setItem = function(id, name, count)
            items[id] = { name = name, count = count }
        end,
        -- list is an array of { id = , name = , quantity = , isHeader = , noLink = }
        setCurrencyList = function(list)
            currencyList = list
        end,
        setCharacter = function(name, realm)
            characterName = name
            realmName = realm
        end,
        -- Simulates a profession's crafting window being open, with its
        -- Concentration currency ID resolvable the way the real client
        -- exposes it once that profession's skill line is known.
        setOpenProfession = function(skillLineID, professionEnum, currencyID)
            childSkillLineID = skillLineID
            skillLines[skillLineID] = { profession = professionEnum, currencyID = currencyID }
        end,
        closeProfession = function()
            childSkillLineID = nil
        end,
        setServerTime = function(value)
            serverTime = value
        end,
        -- Which professions (by skillLineID, matching setOpenProfession's
        -- first argument) the current character has actually learned, for
        -- ns.IsProfessionLearned. Accepts up to six, mirroring GetProfessions().
        setLearnedProfessions = function(...)
            learnedSkillLineIDs = { ... }
        end,
        -- Between test scenarios: clears every fixture and starts MoxieTrackerDB
        -- fresh, so one test's hidden rows or currencies cannot leak into the next.
        reset = function()
            currencies = {}
            currencyList = {}
            items = {}
            characterName, realmName = "TestChar", "TestRealm"
            childSkillLineID = nil
            skillLines = {}
            serverTime = 1000000
            learnedSkillLineIDs = {}
            _G.MoxieTrackerDB = {}
        end,
    }
    return fixtures
end

return M
