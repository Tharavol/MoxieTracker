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

-- ns is addon-private: it is the vararg table WoW hands every file listed in
-- the TOC, so it is how MoxieTracker's files share state without adding
-- globals. This file loads first and owns identity, config, and the
-- SavedVariables accessors -- nothing here touches a frame.
local ADDON_NAME, ns = ...

-- Every command-output call site routes through this instead of hand-writing
-- its own copy of the colour code, so the addon has exactly one place that
-- owns the prefix.
local PREFIX = "|cff33ff99MoxieTracker|r: "
function ns.Print(fmt, ...)
    local msg = select("#", ...) > 0 and fmt:format(...) or fmt
    print(PREFIX .. msg)
end

-- The TOC's @project-version@ placeholder is only substituted by the packager
-- at release time, so an unpackaged dev copy still carries the literal token.
function ns.GetVersion()
    local version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")
    if not version or version == "" or version == "@project-version@" then
        return "dev"
    end
    return version
end

-- Identifies the current character for the account-wide knowledge roster
-- (#38). Name alone collides across realms, so the key includes realm;
-- the name is returned separately since it's what actually gets displayed.
function ns.GetCharacterKey()
    local name = UnitName("player")
    local realm = GetRealmName()
    return name .. "-" .. realm, name
end

-- Shown even at zero. A currency the character has not discovered is absent
-- from the currency list entirely, so these must be queried by ID or they would
-- silently have no row at all.
ns.ALWAYS_SHOWN_IDS = {
    3376, -- Shard of Dundun
    3377, -- Unalloyed Abundance
}

-- Shown only when held. Every character can theoretically hold all eleven, so
-- listing them unconditionally would fill the panel with empty rows.
ns.MOXIE_IDS = {
    3256, -- Artisan Alchemist's Moxie
    3257, -- Artisan Blacksmith's Moxie
    3258, -- Artisan Enchanter's Moxie
    3259, -- Artisan Engineer's Moxie
    3260, -- Artisan Herbalist's Moxie
    3261, -- Artisan Scribe's Moxie
    3262, -- Artisan Jewelcrafter's Moxie
    3263, -- Artisan Leatherworker's Moxie
    3264, -- Artisan Miner's Moxie
    3265, -- Artisan Skinner's Moxie
    3266, -- Artisan Tailor's Moxie
}

-- One currency per profession, all eleven accounted for: each profession's
-- unspent Midnight Knowledge, confirmed in-game (#38). Named per profession,
-- not just a bare ID list, because the Knowledge Points roster breaks a
-- character's total down per profession when they hold points in more than
-- one (ns.CollectUnspentKnowledgeByProfession in the Collect file).
ns.KNOWLEDGE_PROFESSIONS = {
    { id = 3150, name = "Alchemy" },
    { id = 3151, name = "Blacksmithing" },
    { id = 3152, name = "Enchanting" },
    { id = 3153, name = "Engineering" },
    { id = 3154, name = "Herbalism" },
    { id = 3155, name = "Inscription" },
    { id = 3156, name = "Jewelcrafting" },
    { id = 3157, name = "Leatherworking" },
    { id = 3158, name = "Mining" },
    { id = 3159, name = "Skinning" },
    { id = 3160, name = "Tailoring" },
}

-- Bag items, not currencies: these come from C_Item rather than C_CurrencyInfo
-- and are counted across bags, bank, and reagent bank. Always listed, the same
-- way ALWAYS_SHOWN_IDS is, so a row at zero reads as "none" rather than
-- vanishing. `name` is only a fallback for the moments before the client has
-- cached the item.
ns.TRACKED_ITEMS = {
    { itemID = 245345, name = "Fused Vitality" },
}

-- GET_ITEM_INFO_RECEIVED fires for every item entering the client's cache,
-- not just ones this addon tracks, so the UI file's redraw filter needs this.
ns.TRACKED_ITEM_ID_SET = {}
for _, item in ipairs(ns.TRACKED_ITEMS) do
    ns.TRACKED_ITEM_ID_SET[item.itemID] = true
end

-- Fallback only, for a moxie currency added in a future patch that is not in
-- MOXIE_IDS yet. Matching by name is locale-dependent and will not fire on a
-- non-English client, which is precisely why the IDs above are the primary path.
ns.KEYWORDS = {
    "moxie",
    "dundun",
}

ns.GREEN = "|cff33ff33"
ns.YELLOW = "|cffffd200"
ns.RED = "|cffff3333"
ns.WHITE = "|cffffffff"

-- User-editable via the options panel's Color thresholds section. Shard of
-- Dundun is deliberately not here: its rule below is a fixed three-band cutoff
-- tied to the currency's actual in-game cap of 8, not a single threshold, so
-- making it editable would invite a config that contradicts the game
-- mechanic it models.
local DEFAULT_THRESHOLDS = {
    unalloyedAbundance = 800,
    moxie = 600,
    fusedVitality = 20,
}

function ns.GetThreshold(key)
    local thresholds = MoxieTrackerDB and MoxieTrackerDB.thresholds
    local value = thresholds and thresholds[key]
    return type(value) == "number" and value or DEFAULT_THRESHOLDS[key]
end

-- Quantity coloring, keyed by currency ID. Moxie is deliberately absent: its
-- ID varies per profession, so it is handled by name in the Collect file's
-- GetQuantityColor.
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

-- Stable identity for a row, used as the key for the show/hide setting. IDs are
-- preferred because names are localized; the name form only ever applies to an
-- entry that reached us through the keyword fallback with no resolvable ID.
function ns.EntryKey(currencyID, itemID, name)
    if currencyID then
        return "currency:" .. currencyID
    elseif itemID then
        return "item:" .. itemID
    end
    return "name:" .. (name or ""):lower()
end

function ns.IsHidden(key)
    return MoxieTrackerDB.hidden ~= nil and MoxieTrackerDB.hidden[key] == true
end

-- Stored only for hidden rows. Visible is the default, so writing `false` would
-- grow the saved variables with entries that mean nothing.
function ns.SetHidden(key, hidden)
    if hidden then
        MoxieTrackerDB.hidden = MoxieTrackerDB.hidden or {}
        MoxieTrackerDB.hidden[key] = true
    elseif MoxieTrackerDB.hidden then
        MoxieTrackerDB.hidden[key] = nil
    end
end

-- Muted characters (#38 follow-up): once muted, a character's knowledge-roster
-- entry never renders again, even after it re-snapshots on a later login.
-- Mirrors ns.IsHidden/ns.SetHidden's shape exactly, just keyed by character
-- rather than by currency/item row.
function ns.IsCharacterMuted(key)
    return MoxieTrackerDB.mutedCharacters ~= nil and MoxieTrackerDB.mutedCharacters[key] == true
end

function ns.SetCharacterMuted(key, muted)
    if muted then
        MoxieTrackerDB.mutedCharacters = MoxieTrackerDB.mutedCharacters or {}
        MoxieTrackerDB.mutedCharacters[key] = true
    elseif MoxieTrackerDB.mutedCharacters then
        MoxieTrackerDB.mutedCharacters[key] = nil
    end
end

-- Muted professions, per character: finer-grained than ns.IsCharacterMuted --
-- lets a character stay on the roster while hiding just the one profession
-- (an alt's mained-out trade, say) whose points aren't worth tracking.
-- Keyed by character key first, then profession name, so muting is per
-- character rather than account-wide (the same profession can be muted for
-- one alt and left visible on another).
function ns.IsKnowledgeProfessionMuted(characterKey, professionName)
    local muted = MoxieTrackerDB.mutedProfessions
    return muted ~= nil and muted[characterKey] ~= nil and muted[characterKey][professionName] == true
end

function ns.SetKnowledgeProfessionMuted(characterKey, professionName, muted)
    if muted then
        MoxieTrackerDB.mutedProfessions = MoxieTrackerDB.mutedProfessions or {}
        MoxieTrackerDB.mutedProfessions[characterKey] = MoxieTrackerDB.mutedProfessions[characterKey] or {}
        MoxieTrackerDB.mutedProfessions[characterKey][professionName] = true
    elseif MoxieTrackerDB.mutedProfessions and MoxieTrackerDB.mutedProfessions[characterKey] then
        MoxieTrackerDB.mutedProfessions[characterKey][professionName] = nil
    end
end

-- Offset from the crafting window's TOPRIGHT corner. The panel hangs off the
-- right edge, dropped down the side. Taken from a placement verified in-game
-- rather than guessed.
local DEFAULT_OFFSET_X = 4
local DEFAULT_OFFSET_Y = -440

function ns.GetOffset()
    -- Called from the UI file's file-scope ApplyAnchor(), which runs before
    -- ADDON_LOADED has had a chance to initialize MoxieTrackerDB. SavedVariables
    -- are only guaranteed populated once ADDON_LOADED fires for this addon; see
    -- the UI file's ADDON_LOADED handler for the real initialization.
    local x = MoxieTrackerDB and MoxieTrackerDB.offsetX
    local y = MoxieTrackerDB and MoxieTrackerDB.offsetY
    if type(x) ~= "number" or type(y) ~= "number" then
        return DEFAULT_OFFSET_X, DEFAULT_OFFSET_Y
    end
    return x, y
end
