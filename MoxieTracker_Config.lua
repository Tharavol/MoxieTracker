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

-- Shown only when held, and only for a profession this character actually
-- has (ns.CollectTracked's Pass 2 gates on `enum` via ns.IsProfessionLearned
-- -- the same reasoning as ns.CONCENTRATION_PROFESSIONS/Concentration's own
-- account-wide-currency-ID leak below: C_CurrencyInfo.GetCurrencyInfo
-- happily returns a valid nonzero quantity for a Moxie currency ID any
-- character on the account has ever earned, not just ones the CURRENT
-- character has trained. Reported live in-game: a character with only one
-- profession showed both that profession's Moxie and a second profession's
-- Moxie it never had). `enum` is Enum.Profession, kept alongside `id` the
-- same way ns.CONCENTRATION_PROFESSIONS does, so ns.IsProfessionLearned can
-- check it directly.
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

-- Flat ID list derived from the above, for the two call sites that only
-- ever needed bare IDs (the keyword-fallback MOXIE_ID_SET in the Collect
-- file, and /moxie debug dump's "tracked IDs" printer) and have no reason
-- to know profession identity.
ns.MOXIE_IDS = {}
for _, profession in ipairs(ns.MOXIE_PROFESSIONS) do
    table.insert(ns.MOXIE_IDS, profession.id)
end

-- One currency per profession, all eleven accounted for: each profession's
-- unspent Midnight Knowledge, confirmed in-game (#38). Named per profession,
-- not just a bare ID list, because the Knowledge Points roster breaks a
-- character's total down per profession when they hold points in more than
-- one (ns.CollectUnspentKnowledgeByProfession in the Collect file). `enum`
-- (Enum.Profession) is used by ns.CollectKnowledgeByProfession (#42
-- follow-up) to list a profession the character has actually trained even
-- while its points sit at 0 -- the options panel's Character Professions
-- mute list needs that row available before the profession has ever earned
-- a point, the same reasoning MOXIE_PROFESSIONS/CONCENTRATION_PROFESSIONS
-- already follow for their own enum field.
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

-- Crafter's Concentration (#40) has no static currency ID to list here the
-- way Moxie and Knowledge do: it is resolved live per profession via
-- C_TradeSkillUI.GetConcentrationCurrencyID(skillLineID), confirmed against
-- derfloh205/CraftSim's ConcentrationTracker.lua/ConcentrationData.lua
-- (see docs/CURRENCY_DISCOVERY.md's Sources section). Only the 8 crafting professions carry
-- Concentration -- the 3 gathering professions among MoxieTracker's eleven
-- (Herbalism, Mining, Skinning) do not, same exclusion CraftSim's
-- GATHERING_PROFESSIONS check makes.
--
-- Keyed by `enum` (Enum.Profession, the client's own locale-independent
-- profession identifier -- confirmed as the `.profession` field on
-- C_TradeSkillUI.GetProfessionInfoBySkillLineID's return value via
-- Blizzard's own TradeSkillUITypesDocumentation.lua) rather than by the
-- struct's `.professionName` field, which is localized display text and
-- would silently never match this list on a non-English client -- the same
-- "matched by ID, not name, so it works on any locale" principle
-- MOXIE_IDS/KNOWLEDGE_PROFESSIONS already follow. `name` is MoxieTracker's
-- own stable English label, used as the storage/display key throughout,
-- same role KNOWLEDGE_PROFESSIONS' `name` field plays.
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

-- Concentration (#40) gets its own threshold per crafting profession, unlike
-- Moxie's single shared threshold across all eleven -- confirmed with the
-- user, since how much Concentration is "enough" varies by profession.
-- Flat keys in the same DEFAULT_THRESHOLDS/MoxieTrackerDB.thresholds table
-- rather than a parallel structure, so the options panel's existing "Reset
-- thresholds" button resets these for free. Every profession defaults to
-- 300; only Alchemy's default was specified, so the rest start at the same
-- value until tuned individually.
for _, profession in ipairs(ns.CONCENTRATION_PROFESSIONS) do
    DEFAULT_THRESHOLDS["concentration:" .. profession.name] = 300
end

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

-- Concentration coloring (#40): red at the currency's real cap
-- (maxQuantity, read live from C_CurrencyInfo rather than a hardcoded
-- 1000 -- the same "tied to the actual game mechanic" reasoning as Shard
-- of Dundun's fixed band above) always wins, then green at the
-- profession's own editable threshold, yellow otherwise. maxQuantity of 0
-- or nil means the currency has not been discovered yet (see
-- ns.CONCENTRATION_PROFESSIONS above), which has nothing sensible to
-- color against.
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

-- Display filter for the "Hide Concentration values under threshold" option
-- (#48): kept separate from ns.GetConcentrationColor since a hidden line
-- still needs no color decision made at all, and separate from the
-- MoxieTrackerDB flag check so callers don't have to duplicate the
-- "concentration:" .. profession key format.
function ns.IsConcentrationBelowThreshold(profession, quantity)
    return quantity < ns.GetThreshold("concentration:" .. profession)
end

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

-- Concentration muting (#40): the exact same whole-character/per-profession
-- pair as Knowledge's above, just against Concentration's own
-- mutedConcentrationCharacters/mutedConcentrationProfessions tables, so
-- muting a character's (or one profession's) Concentration never touches
-- their Knowledge mute state, and vice versa.
function ns.IsConcentrationCharacterMuted(key)
    return MoxieTrackerDB.mutedConcentrationCharacters ~= nil
        and MoxieTrackerDB.mutedConcentrationCharacters[key] == true
end

function ns.SetConcentrationCharacterMuted(key, muted)
    if muted then
        MoxieTrackerDB.mutedConcentrationCharacters = MoxieTrackerDB.mutedConcentrationCharacters or {}
        MoxieTrackerDB.mutedConcentrationCharacters[key] = true
    elseif MoxieTrackerDB.mutedConcentrationCharacters then
        MoxieTrackerDB.mutedConcentrationCharacters[key] = nil
    end
end

function ns.IsConcentrationProfessionMuted(characterKey, professionName)
    local muted = MoxieTrackerDB.mutedConcentrationProfessions
    return muted ~= nil and muted[characterKey] ~= nil and muted[characterKey][professionName] == true
end

function ns.SetConcentrationProfessionMuted(characterKey, professionName, muted)
    if muted then
        MoxieTrackerDB.mutedConcentrationProfessions = MoxieTrackerDB.mutedConcentrationProfessions or {}
        MoxieTrackerDB.mutedConcentrationProfessions[characterKey] =
            MoxieTrackerDB.mutedConcentrationProfessions[characterKey] or {}
        MoxieTrackerDB.mutedConcentrationProfessions[characterKey][professionName] = true
    elseif MoxieTrackerDB.mutedConcentrationProfessions
        and MoxieTrackerDB.mutedConcentrationProfessions[characterKey] then
        MoxieTrackerDB.mutedConcentrationProfessions[characterKey][professionName] = nil
    end
end

-- Offset from the crafting window's TOPRIGHT corner, one entry per window
-- (#40 -- previously a single MoxieTrackerDB.offsetX/Y for the main window
-- only). Only "main" has a numeric default: it hangs off the crafting
-- window's right edge at a placement verified in-game. Knowledge and
-- Concentration have no numeric default here -- until dragged, they stay
-- anchored beneath the window above them (a live SetPoint relationship set
-- up in the UI file), which this function cannot express since it never
-- touches a frame.
local WINDOW_OFFSET_DEFAULTS = {
    main = { x = 4, y = -440 },
}

-- Third return value: which of the crafting frame's corners the offset is
-- relative to (#47) -- "right" (the only mode that ever existed before
-- this) anchors the window's TOPLEFT to the crafting frame's TOPRIGHT;
-- "left" anchors the window's TOPRIGHT to the crafting frame's TOPLEFT, for
-- a window the user dragged to rest on the frame's *left* side. Always
-- "right" for a legacy/default offset with no stored side, so nothing
-- changes for any offset saved before this existed.
function ns.GetOffset(windowKey)
    -- Called from the UI file's file-scope ApplyAnchor(), which runs before
    -- ADDON_LOADED has had a chance to initialize MoxieTrackerDB. SavedVariables
    -- are only guaranteed populated once ADDON_LOADED fires for this addon; see
    -- the UI file's ADDON_LOADED handler for the real initialization.
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

-- `side` is optional and only ever passed by ns.UI's drag-stop handler,
-- which is the one place that can actually tell which side of the crafting
-- frame the window landed on. Every other caller (the options panel's
-- manual X/Y edit boxes) calls this with just x/y, and must not silently
-- flip a left-docked window back to "right" just because the user typed a
-- new number into one box -- so an omitted `side` preserves whatever was
-- already stored, rather than defaulting to "right" outright.
function ns.SetOffset(windowKey, x, y, side)
    if not side then
        local existing = MoxieTrackerDB.windows and MoxieTrackerDB.windows[windowKey]
        side = existing and existing.side
    end
    MoxieTrackerDB.windows = MoxieTrackerDB.windows or {}
    MoxieTrackerDB.windows[windowKey] = { offsetX = x, offsetY = y, side = side }
end

function ns.ClearOffset(windowKey)
    if MoxieTrackerDB.windows then
        MoxieTrackerDB.windows[windowKey] = nil
    end
end

-- Pure geometry, no frame objects, so it is testable without a live client
-- (#47): decides which of the crafting frame's edges a just-dropped window
-- should track from now on. ProfessionsFrame resizes across its own tabs --
-- confirmed live in-game, the Specializations tab is visibly wider than
-- Recipes/Crafting Orders, extending mostly leftward -- so a window
-- anchored to the frame's TOPRIGHT (the only anchor MoxieTracker had before
-- this) drifts along with however far right TOPRIGHT happens to sit, while
-- a window sitting to the frame's *left* actually needs to track its
-- TOPLEFT edge to hold a constant gap regardless of how wide the frame
-- gets. Unambiguous cases (window entirely clear of the frame on one side)
-- decide directly; an overlapping drop (on top of the frame, or only
-- nudged vertically) falls back to comparing centers, defaulting to
-- "right" on an exact tie -- what every offset meant before "left" existed,
-- so nudging a window near its already-anchored spot never flips it.
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

-- One-time upgrade path for the pre-#40 single offsetX/offsetY pair (main
-- window only) into windows.main.
function ns.MigrateWindowOffset()
    if type(MoxieTrackerDB.offsetX) == "number" and type(MoxieTrackerDB.offsetY) == "number" then
        ns.SetOffset("main", MoxieTrackerDB.offsetX, MoxieTrackerDB.offsetY)
    end
    MoxieTrackerDB.offsetX = nil
    MoxieTrackerDB.offsetY = nil
end

-- Duration formatting for Concentration's "time until cap" (#40). nil or
-- <= 0 means already at cap (or not regenerating at all, e.g. an
-- undiscovered currency); otherwise days only show once there is at least
-- one, matching a Concentration cap that takes several hours to reach from
-- zero but never multiple days at the per-point recharge rates seen so far.
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
