--[[
MoxieTracker - displays Artisan Moxie, Shard of Dundun, Unalloyed Abundance,
and Fused Vitality alongside the World of Warcraft crafting window.

Copyright (C) 2026 Tharavol

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
--]]

-- Loads first: identity, config tables and SavedVariables accessors. No frames.
local ADDON_NAME, ns = ...

local PREFIX = "|cff33ff99MoxieTracker|r: "
function ns.Print(fmt, ...)
    local msg = select("#", ...) > 0 and fmt:format(...) or fmt
    print(PREFIX .. msg)
end

-- @project-version@ is only substituted by the packager, so a dev copy keeps the token.
function ns.GetVersion()
    local version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")
    if not version or version == "" or version == "@project-version@" then
        return "dev"
    end
    return version
end

-- Roster key (#38): name alone collides across realms. The bare name is what gets displayed.
function ns.GetCharacterKey()
    local name = UnitName("player")
    local realm = GetRealmName()
    return name .. "-" .. realm, name
end

-- Character display order (#51) shared by both roster windows: nil means alphabetical,
-- otherwise an array of character keys.
function ns.GetCharacterOrder()
    return MoxieTrackerDB and MoxieTrackerDB.characterOrder
end

function ns.SetCharacterOrder(orderedKeys)
    MoxieTrackerDB.characterOrder = orderedKeys
end

function ns.ClearCharacterOrder()
    MoxieTrackerDB.characterOrder = nil
end

-- Sub-tables that always exist once ns.InitSavedVariables has run (#54).
local SAVED_TABLES = {
    "hidden", "thresholds", "windows",
    "mutedCharacters", "mutedProfessions", "mutedConcentrationCharacters", "mutedConcentrationProfessions",
    "knowledge", "concentration", "concentrationCurrencyIDs", "learnedProfessions",
}

-- Run at ADDON_LOADED, and again after /moxie reset settings clears fields.
function ns.InitSavedVariables()
    if type(MoxieTrackerDB) ~= "table" then
        MoxieTrackerDB = {}
    end
    for _, field in ipairs(SAVED_TABLES) do
        if type(MoxieTrackerDB[field]) ~= "table" then
            MoxieTrackerDB[field] = {}
        end
    end
end

-- Entries not in orderedKeys (e.g. a new alt) follow the listed ones, alphabetically.
function ns.SortRosterByCharacterOrder(roster, orderedKeys)
    local rank = {}
    if orderedKeys then
        for i, key in ipairs(orderedKeys) do
            rank[key] = i
        end
    end
    table.sort(roster, function(a, b)
        local ra, rb = rank[a.key], rank[b.key]
        if ra and rb then
            return ra < rb
        elseif ra and not rb then
            return true
        elseif rb and not ra then
            return false
        end
        return a.name < b.name
    end)
end

-- Shown even at zero. An undiscovered currency is absent from the currency list,
-- so these are queried by ID.
ns.ALWAYS_SHOWN_IDS = {
    3376, -- Shard of Dundun
    3377, -- Unalloyed Abundance
}

-- Shown only when held and the profession is learned: GetCurrencyInfo returns a
-- nonzero quantity for any Moxie an alt on the account has earned. `enum` is
-- Enum.Profession, for ns.IsProfessionLearned.
ns.MOXIE_PROFESSIONS = {
    { id = 3256, enum = Enum.Profession.Alchemy, name = "Alchemy" }, -- Artisan Alchemist's Moxie
    { id = 3257, enum = Enum.Profession.Blacksmithing, name = "Blacksmithing" }, -- Artisan Blacksmith's Moxie
    { id = 3258, enum = Enum.Profession.Enchanting, name = "Enchanting" }, -- Artisan Enchanter's Moxie
    { id = 3259, enum = Enum.Profession.Engineering, name = "Engineering" }, -- Artisan Engineer's Moxie
    { id = 3260, enum = Enum.Profession.Herbalism, name = "Herbalism" }, -- Artisan Herbalist's Moxie
    { id = 3261, enum = Enum.Profession.Inscription, name = "Inscription" }, -- Artisan Scribe's Moxie
    { id = 3262, enum = Enum.Profession.Jewelcrafting, name = "Jewelcrafting" }, -- Artisan Jewelcrafter's Moxie
    { id = 3263, enum = Enum.Profession.Leatherworking, name = "Leatherworking" }, -- Artisan Leatherworker's Moxie
    { id = 3264, enum = Enum.Profession.Mining, name = "Mining" }, -- Artisan Miner's Moxie
    { id = 3265, enum = Enum.Profession.Skinning, name = "Skinning" }, -- Artisan Skinner's Moxie
    { id = 3266, enum = Enum.Profession.Tailoring, name = "Tailoring" }, -- Artisan Tailor's Moxie
}

ns.MOXIE_IDS = {}
for _, profession in ipairs(ns.MOXIE_PROFESSIONS) do
    table.insert(ns.MOXIE_IDS, profession.id)
end

-- Unspent Midnight Knowledge per profession, confirmed in-game (#38).
ns.KNOWLEDGE_PROFESSIONS = {
    { id = 3150, enum = Enum.Profession.Alchemy, name = "Alchemy" },
    { id = 3151, enum = Enum.Profession.Blacksmithing, name = "Blacksmithing" },
    { id = 3152, enum = Enum.Profession.Enchanting, name = "Enchanting" },
    { id = 3153, enum = Enum.Profession.Engineering, name = "Engineering" },
    { id = 3154, enum = Enum.Profession.Herbalism, name = "Herbalism" },
    { id = 3155, enum = Enum.Profession.Inscription, name = "Inscription" },
    { id = 3156, enum = Enum.Profession.Jewelcrafting, name = "Jewelcrafting" },
    { id = 3157, enum = Enum.Profession.Leatherworking, name = "Leatherworking" },
    { id = 3158, enum = Enum.Profession.Mining, name = "Mining" },
    { id = 3159, enum = Enum.Profession.Skinning, name = "Skinning" },
    { id = 3160, enum = Enum.Profession.Tailoring, name = "Tailoring" },
}

-- Concentration (#40) has no static currency ID: it is resolved per profession via
-- C_TradeSkillUI.GetConcentrationCurrencyID (see docs/CURRENCY_DISCOVERY.md).
-- Gathering professions have none. Matched by Enum.Profession (the `.profession`
-- field of GetProfessionInfoBySkillLineID), not the localized professionName.
ns.CONCENTRATION_PROFESSIONS = {
    { enum = Enum.Profession.Alchemy, name = "Alchemy" },
    { enum = Enum.Profession.Blacksmithing, name = "Blacksmithing" },
    { enum = Enum.Profession.Enchanting, name = "Enchanting" },
    { enum = Enum.Profession.Engineering, name = "Engineering" },
    { enum = Enum.Profession.Inscription, name = "Inscription" },
    { enum = Enum.Profession.Jewelcrafting, name = "Jewelcrafting" },
    { enum = Enum.Profession.Leatherworking, name = "Leatherworking" },
    { enum = Enum.Profession.Tailoring, name = "Tailoring" },
}

ns.CONCENTRATION_PROFESSION_BY_ENUM = {}
for _, profession in ipairs(ns.CONCENTRATION_PROFESSIONS) do
    ns.CONCENTRATION_PROFESSION_BY_ENUM[profession.enum] = profession.name
end

-- Bag items counted across bags, bank and reagent bank; always listed. `name` is
-- a fallback until the client caches the item.
ns.TRACKED_ITEMS = {
    { itemID = 245345, name = "Fused Vitality" },
}

-- Redraw filter for GET_ITEM_INFO_RECEIVED, which fires for every item.
ns.TRACKED_ITEM_ID_SET = {}
for _, item in ipairs(ns.TRACKED_ITEMS) do
    ns.TRACKED_ITEM_ID_SET[item.itemID] = true
end

-- Weekly quests (#53), shown as Done / Not done and always listed. Read per
-- character: IsQuestFlaggedCompletedOnAccount reads true once any alt has done it.
-- `name` is a fallback title; `sortAfter` pins the row below that currency ID.
ns.TRACKED_QUESTS = {
    { questID = 89507, name = "Abundant Offerings", sortAfter = 3376 }, -- below Shard of Dundun
}

-- Redraw filter for QUEST_TURNED_IN / QUEST_DATA_LOAD_RESULT, which fire for every quest.
ns.TRACKED_QUEST_ID_SET = {}
for _, quest in ipairs(ns.TRACKED_QUESTS) do
    ns.TRACKED_QUEST_ID_SET[quest.questID] = true
end

-- Fallback for a future moxie currency not yet in MOXIE_IDS. English-only.
ns.KEYWORDS = {
    "moxie",
    "dundun",
}

ns.GREEN = "|cff33ff33"
ns.YELLOW = "|cffffd200"
ns.RED = "|cffff3333"
ns.WHITE = "|cffffffff"

-- Editable on the Thresholds page. Shard of Dundun is fixed: its bands follow its cap of 8.
local DEFAULT_THRESHOLDS = {
    unalloyedAbundance = 800,
    moxie = 600,
    fusedVitality = 20,
}

-- One Concentration threshold per profession (#40), as flat keys so "Reset thresholds" covers them.
for _, profession in ipairs(ns.CONCENTRATION_PROFESSIONS) do
    DEFAULT_THRESHOLDS["concentration:" .. profession.name] = 300
end

function ns.GetThreshold(key)
    local value = MoxieTrackerDB.thresholds[key]
    return type(value) == "number" and value or DEFAULT_THRESHOLDS[key]
end

-- Keyed by currency ID. Moxie is handled in ns.GetQuantityColor, since its ID varies per profession.
ns.QUANTITY_COLOR = {
    -- Shard of Dundun caps at 8, so the yellow fallback only ever covers 0-5.
    [3376] = function(quantity)
        if quantity == 6 then
            return ns.GREEN
        elseif quantity == 7 or quantity == 8 then
            return ns.RED
        end
        return ns.YELLOW
    end,
    [3377] = function(quantity) -- Unalloyed Abundance
        return quantity >= ns.GetThreshold("unalloyedAbundance") and ns.GREEN or ns.YELLOW
    end,
}

-- Same idea for bag items, keyed by item ID.
ns.ITEM_QUANTITY_COLOR = {
    [245345] = function(quantity) -- Fused Vitality
        return quantity >= ns.GetThreshold("fusedVitality") and ns.GREEN or ns.YELLOW
    end,
}

-- Concentration (#40): red at the live cap, green at the profession's threshold,
-- yellow otherwise. No maxQuantity means the currency is undiscovered.
function ns.GetConcentrationColor(profession, quantity, maxQuantity)
    if not maxQuantity or maxQuantity <= 0 then
        return ns.WHITE
    end
    if quantity >= maxQuantity then
        return ns.RED
    end
    if quantity >= ns.GetThreshold("concentration:" .. profession) then
        return ns.GREEN
    end
    return ns.YELLOW
end

-- For "Hide Concentration values under threshold" (#48).
function ns.IsConcentrationBelowThreshold(profession, quantity)
    return quantity < ns.GetThreshold("concentration:" .. profession)
end

-- Persisted show/hide key. The name form only applies to a keyword-fallback entry with no ID.
function ns.EntryKey(currencyID, itemID, name, questID)
    if currencyID then
        return "currency:" .. currencyID
    elseif itemID then
        return "item:" .. itemID
    elseif questID then
        return "quest:" .. questID
    end
    return "name:" .. (name or ""):lower()
end

function ns.IsHidden(key)
    return MoxieTrackerDB.hidden[key] == true
end

-- Only hidden rows are stored; visible is the default.
function ns.SetHidden(key, hidden)
    MoxieTrackerDB.hidden[key] = hidden and true or nil
end

-- Whole-character mute for the Knowledge roster (#38).
function ns.IsCharacterMuted(key)
    return MoxieTrackerDB.mutedCharacters[key] == true
end

function ns.SetCharacterMuted(key, muted)
    MoxieTrackerDB.mutedCharacters[key] = muted and true or nil
end

-- Per-character profession mutes, [characterKey][professionName] = true. The
-- inner per-character table is created on demand.
local function IsProfessionMuted(store, characterKey, professionName)
    return store[characterKey] ~= nil and store[characterKey][professionName] == true
end

local function SetProfessionMuted(store, characterKey, professionName, muted)
    if muted then
        store[characterKey] = store[characterKey] or {}
        store[characterKey][professionName] = true
    elseif store[characterKey] then
        store[characterKey][professionName] = nil
    end
end

function ns.IsKnowledgeProfessionMuted(characterKey, professionName)
    return IsProfessionMuted(MoxieTrackerDB.mutedProfessions, characterKey, professionName)
end

function ns.SetKnowledgeProfessionMuted(characterKey, professionName, muted)
    SetProfessionMuted(MoxieTrackerDB.mutedProfessions, characterKey, professionName, muted)
end

-- Concentration (#40) keeps its own mute tables, independent of Knowledge's.
function ns.IsConcentrationCharacterMuted(key)
    return MoxieTrackerDB.mutedConcentrationCharacters[key] == true
end

function ns.SetConcentrationCharacterMuted(key, muted)
    MoxieTrackerDB.mutedConcentrationCharacters[key] = muted and true or nil
end

function ns.IsConcentrationProfessionMuted(characterKey, professionName)
    return IsProfessionMuted(MoxieTrackerDB.mutedConcentrationProfessions, characterKey, professionName)
end

function ns.SetConcentrationProfessionMuted(characterKey, professionName, muted)
    SetProfessionMuted(MoxieTrackerDB.mutedConcentrationProfessions, characterKey, professionName, muted)
end

-- Per-window offset from the crafting window (#40). Only "main" has a default;
-- the others stack beneath the window above them until dragged.
local WINDOW_OFFSET_DEFAULTS = {
    main = { x = 4, y = -440 },
}

-- Third return (#47): "right" anchors the window's TOPLEFT to the crafting frame's
-- TOPRIGHT; "left" anchors its TOPRIGHT to the frame's TOPLEFT. Defaults to "right".
function ns.GetOffset(windowKey)
    -- Also called at file scope, before ADDON_LOADED has loaded MoxieTrackerDB.
    local windows = MoxieTrackerDB and MoxieTrackerDB.windows
    local stored = windows and windows[windowKey]
    local x = stored and stored.offsetX
    local y = stored and stored.offsetY
    if type(x) == "number" and type(y) == "number" then
        return x, y, (stored.side == "left") and "left" or "right"
    end
    local default = WINDOW_OFFSET_DEFAULTS[windowKey]
    if default then
        return default.x, default.y, "right"
    end
    return nil, nil, nil
end

-- `side` is only passed by the drag-stop handler; the options panel's X/Y boxes
-- omit it, which keeps the stored side.
function ns.SetOffset(windowKey, x, y, side)
    if not side then
        local existing = MoxieTrackerDB.windows[windowKey]
        side = existing and existing.side
    end
    MoxieTrackerDB.windows[windowKey] = { offsetX = x, offsetY = y, side = side }
end

function ns.ClearOffset(windowKey)
    MoxieTrackerDB.windows[windowKey] = nil
end

-- Which crafting-frame edge a dropped window tracks (#47). ProfessionsFrame widens
-- leftward on the Specializations tab, so a window left of it must track TOPLEFT.
-- Overlapping drops compare centers; a tie stays "right".
function ns.ComputeAnchorSide(windowLeft, windowRight, frameLeft, frameRight)
    if windowRight <= frameLeft then
        return "left"
    end
    if windowLeft >= frameRight then
        return "right"
    end
    local windowCenter = (windowLeft + windowRight) / 2
    local frameCenter = (frameLeft + frameRight) / 2
    if windowCenter < frameCenter then
        return "left"
    end
    return "right"
end

-- Upgrades the pre-#40 single offsetX/offsetY pair into windows.main.
function ns.MigrateWindowOffset()
    if type(MoxieTrackerDB.offsetX) == "number" and type(MoxieTrackerDB.offsetY) == "number" then
        ns.SetOffset("main", MoxieTrackerDB.offsetX, MoxieTrackerDB.offsetY)
    end
    MoxieTrackerDB.offsetX = nil
    MoxieTrackerDB.offsetY = nil
end

-- Concentration time until cap (#40). nil or <= 0 reads as "at cap".
function ns.FormatDuration(seconds)
    if not seconds or seconds <= 0 then
        return "at cap"
    end
    local totalMinutes = math.floor(seconds / 60)
    local days = math.floor(totalMinutes / 1440)
    local hours = math.floor((totalMinutes % 1440) / 60)
    local minutes = totalMinutes % 60
    if days > 0 then
        return string.format("%dd %dh", days, hours)
    elseif hours > 0 then
        return string.format("%dh %dm", hours, minutes)
    end
    return string.format("%dm", minutes)
end
