-- Depends on all other MoxieTracker files, loaded last per the TOC. Slash
-- command registration and the /moxie handler.
local _, ns = ...

SLASH_MOXIETRACKER1 = "/moxie"
-- /moxie is short enough to be contested by another addon; SlashCmdList
-- registration is last-writer-wins, so this full-length fallback is never lost.
SLASH_MOXIETRACKER2 = "/moxietracker"

local function OpenOptions()
    if not ns.OpenOptions() then
        ns.Print("this client has no Settings panel; open Options > AddOns manually.")
    end
end

-- The one-shot diagnostic dump, unchanged from the old bare "debug" command --
-- still the fastest way to see which currency IDs resolved -- just moved
-- behind "debug dump" now that "debug" on its own is a real logging toggle.
local function PrintDebugDump()
    for _, window in ipairs({ "main", "knowledge", "concentration" }) do
        local offsetX, offsetY = ns.GetOffset(window)
        local windows = MoxieTrackerDB.windows
        local placement = (windows and windows[window]) and "user placed"
            or (offsetX and "default" or "stacked below the window above it")
        if offsetX and offsetY then
            ns.Print("%s window offset %.1f, %.1f (%s); crafting frame %s",
                window, offsetX, offsetY, placement, ns.craftingFrame and "found" or "not loaded")
        else
            ns.Print("%s window offset: %s; crafting frame %s",
                window, placement, ns.craftingFrame and "found" or "not loaded")
        end
    end

    -- Queried by ID so zero-quantity and undiscovered currencies still
    -- report, which the currency-list walk below cannot show.
    ns.Print("tracked IDs")
    for _, group in ipairs({ { "always", ns.ALWAYS_SHOWN_IDS }, { "moxie", ns.MOXIE_IDS } }) do
        for _, currencyID in ipairs(group[2]) do
            local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
            ns.Print("  [%s] %d %s = %s",
                group[1], currencyID,
                info and info.name or "|cffff3333unknown|r",
                info and tostring(info.quantity or 0) or "n/a")
        end
    end

    ns.Print("concentration currency IDs (discovered by opening each profession)")
    local discoveredAny = false
    for _, profession in ipairs(ns.CONCENTRATION_PROFESSIONS) do
        local currencyID = MoxieTrackerDB.concentrationCurrencyIDs and
            MoxieTrackerDB.concentrationCurrencyIDs[profession.name]
        if currencyID then
            discoveredAny = true
            local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
            ns.Print("  [concentration] %d %s = %s/%s",
                currencyID, profession.name,
                info and tostring(info.quantity or 0) or "n/a",
                info and tostring(info.maxQuantity or 0) or "n/a")
        end
    end
    if not discoveredAny then
        ns.Print("  none yet - open a crafting profession's window to discover its currency ID")
    end

    ns.Print("tracked items")
    for _, item in ipairs(ns.TRACKED_ITEMS) do
        local name = C_Item.GetItemInfo(item.itemID)
        ns.Print("  [item] %d %s = %d%s",
            item.itemID,
            name or (item.name .. " |cffff3333(uncached)|r"),
            C_Item.GetItemCount(item.itemID, true, false, true, true) or 0,
            ns.IsHidden(ns.EntryKey(nil, item.itemID)) and " |cffff3333(hidden)|r" or "")
    end

    local hiddenCount = 0
    if MoxieTrackerDB.hidden then
        for key in pairs(MoxieTrackerDB.hidden) do
            hiddenCount = hiddenCount + 1
            ns.Print("  [hidden] %s", key)
        end
    end
    ns.Print("%d hidden row(s)", hiddenCount)

    local size = C_CurrencyInfo.GetCurrencyListSize and C_CurrencyInfo.GetCurrencyListSize() or 0
    ns.Print("currency list size = %d", size)
    for index = 1, size do
        local info = C_CurrencyInfo.GetCurrencyListInfo(index)
        if info then
            if info.isHeader then
                ns.Print("  [%d] HEADER %s (expanded: %s)",
                    index, tostring(info.name), tostring(info.isHeaderExpanded))
            elseif (info.quantity or 0) > 0 then
                ns.Print("  [%d] %s = %d (id %s)",
                    index, tostring(info.name), info.quantity, tostring(ns.GetCurrencyIDForIndex(index)))
            end
        end
    end
end

-- Bare toggles and reports the new state; explicit on/off sets it; "dump" runs
-- the one-shot diagnostic printout above; anything else is rejected instead
-- of silently doing nothing (S8/S12).
local function HandleDebug(arg1)
    if arg1 == "dump" then
        PrintDebugDump()
        return
    end
    if arg1 == "on" then
        MoxieTrackerDB.debugLogging = true
    elseif arg1 == "off" then
        MoxieTrackerDB.debugLogging = false
    elseif arg1 == nil then
        MoxieTrackerDB.debugLogging = not MoxieTrackerDB.debugLogging
    else
        ns.Print("'%s' - expected 'on', 'off' or 'dump'.", arg1)
        return
    end
    ns.Print("debug logging is %s.", MoxieTrackerDB.debugLogging and "on" or "off")
end

-- "reset" alone used to mean "move the panel back to the crafting window's
-- top-right", which the cross-addon standard reserves for restoring settings.
-- Split into "reset position" (the old meaning) and "reset settings" (hidden
-- rows, pin state, threshold overrides and debug logging -- not position,
-- which keeps its own explicit subcommand).
local function HandleReset(arg1)
    if arg1 == "position" then
        ns.ResetPosition()
        ns.Print("position reset to the crafting window's top-right corner.")
    elseif arg1 == "settings" then
        MoxieTrackerDB.hidden = nil
        MoxieTrackerDB.mutedCharacters = nil
        MoxieTrackerDB.mutedProfessions = nil
        MoxieTrackerDB.mutedConcentrationCharacters = nil
        MoxieTrackerDB.mutedConcentrationProfessions = nil
        MoxieTrackerDB.hideMoxie = nil
        MoxieTrackerDB.hideKnowledgeWindow = nil
        MoxieTrackerDB.hideConcentrationWindow = nil
        MoxieTrackerDB.thresholds = nil
        MoxieTrackerDB.debugLogging = nil
        ns.frame.pinned = false
        -- Three separate pages now (#41); only refresh whichever is
        -- actually open, same as the old single-page check did.
        if ns.generalPanel:IsShown() then
            ns.RefreshGeneralOptions()
        end
        if ns.moxieProfessionsPanel:IsShown() then
            ns.RefreshMoxieProfessionsOptions()
        end
        if ns.thresholdsPanel:IsShown() then
            ns.RefreshThresholdsOptions()
        end
        if ns.charactersPanel:IsShown() then
            ns.RefreshCharactersOptions()
        end
        if ns.characterProfessionsPanel:IsShown() then
            ns.RefreshCharacterProfessionsOptions()
        end
        if ns.concentrationPanel:IsShown() then
            ns.RefreshConcentrationOptions()
        end
        if ns.concentrationProfessionsPanel:IsShown() then
            ns.RefreshConcentrationProfessionsOptions()
        end
        ns.RefreshVisibility()
        ns.Print("settings restored to defaults.")
    else
        ns.Print("Usage: /moxie reset position|settings")
    end
end

local function PrintStatus()
    ns.Print("pinned: %s", tostring(ns.frame.pinned == true))

    local hiddenCount = 0
    if MoxieTrackerDB.hidden then
        for _ in pairs(MoxieTrackerDB.hidden) do
            hiddenCount = hiddenCount + 1
        end
    end
    ns.Print("hidden rows: %d", hiddenCount)

    -- mutedCharacters/mutedConcentrationCharacters are flat {char = true}
    -- tables; mutedProfessions/mutedConcentrationProfessions are nested one
    -- level deeper ({char = {profession = true}}), so they need separate
    -- counting shapes rather than one CountMuted for both.
    local function CountFlat(field)
        local count = 0
        if MoxieTrackerDB[field] then
            for _ in pairs(MoxieTrackerDB[field]) do
                count = count + 1
            end
        end
        return count
    end
    local function CountNested(field)
        local count = 0
        if MoxieTrackerDB[field] then
            for _, entries in pairs(MoxieTrackerDB[field]) do
                for _ in pairs(entries) do
                    count = count + 1
                end
            end
        end
        return count
    end
    ns.Print("Knowledge mutes: %d character(s), %d profession(s)",
        CountFlat("mutedCharacters"), CountNested("mutedProfessions"))
    ns.Print("Concentration mutes: %d character(s), %d profession(s)",
        CountFlat("mutedConcentrationCharacters"), CountNested("mutedConcentrationProfessions"))

    ns.Print("Moxie: %s", MoxieTrackerDB.hideMoxie and "hidden" or "shown")
    ns.Print("Knowledge Points window: %s", MoxieTrackerDB.hideKnowledgeWindow and "hidden" or "shown")
    ns.Print("Concentration window: %s", MoxieTrackerDB.hideConcentrationWindow and "hidden" or "shown")

    if MoxieTrackerDB.thresholds then
        local parts = {}
        for key, value in pairs(MoxieTrackerDB.thresholds) do
            parts[#parts + 1] = key .. "=" .. tostring(value)
        end
        table.sort(parts)
        ns.Print("threshold overrides: %s", table.concat(parts, ", "))
    else
        ns.Print("threshold overrides: none (using defaults)")
    end

    ns.Print("debug logging: %s", MoxieTrackerDB.debugLogging and "on" or "off")
end

-- Table of { name, help, handler }, so the help list is derived from the same
-- data Dispatch matches against instead of a second hand-maintained block
-- that could drift out of sync (S13). "", "config" and "gui" are silent
-- aliases of "options" (S5): each opens the panel but carries no help text of
-- its own, so help doesn't repeat the same line four times.
local COMMANDS = {
    {name = "", help = {}, handler = OpenOptions},
    {
        name = "options",
        help = {"/moxie, /moxie options, /moxie config, /moxie gui - open the options panel"},
        handler = OpenOptions
    },
    {name = "config", help = {}, handler = OpenOptions},
    {name = "gui", help = {}, handler = OpenOptions},
    {
        name = "showall",
        help = {"/moxie showall - unhide every row"},
        handler = function()
            MoxieTrackerDB.hidden = nil
            if ns.generalPanel:IsShown() then
                ns.RefreshGeneralOptions()
            end
            ns.RefreshVisibility()
            ns.Print("every row is visible again.")
        end
    },
    {
        name = "pin",
        help = {"/moxie pin - keep the panel visible regardless of the crafting window"},
        handler = function()
            ns.frame.pinned = not ns.frame.pinned
            ns.RefreshVisibility()
            ns.Print("pinned %s.",
                ns.frame.pinned and "on - panel stays visible" or "off - panel follows the crafting window")
        end
    },
    {
        name = "debug",
        help = {
            "/moxie debug [on|off] - toggle or set debug logging",
            "/moxie debug dump - print diagnostic info about tracked currencies and items"
        },
        handler = HandleDebug
    },
    {
        name = "reset",
        help = {
            "/moxie reset position - move all three windows back to their default positions",
            "/moxie reset settings - restore hidden rows, muted characters/professions, the Knowledge " ..
                "Points and Concentration windows, pin state, thresholds and debug logging to defaults"
        },
        handler = HandleReset
    },
    {name = "status", help = {"/moxie status - show current settings"}, handler = PrintStatus},
    {
        name = "version",
        help = {"/moxie version - show the addon version"},
        handler = function() ns.Print(ns.GetVersion()) end
    }
}

local function PrintUsage()
    ns.Print("shows automatically with the crafting window. Commands (alias: /moxietracker):")
    for _, entry in ipairs(COMMANDS) do
        for _, line in ipairs(entry.help) do
            ns.Print(line)
        end
    end
end

COMMANDS[#COMMANDS + 1] = {name = "help", help = {"/moxie help - show this list"}, handler = PrintUsage}

SlashCmdList["MOXIETRACKER"] = function(msg)
    local tokens = {}
    -- Every token is lowercased for matching: unlike an addon with free-text
    -- arguments (a player name, a search term), nothing /moxie takes is
    -- case-sensitive, so there is no "whole input" to accidentally corrupt.
    for word in (msg or ""):gmatch("%S+") do
        tokens[#tokens + 1] = word:lower()
    end

    local cmd = tokens[1] or ""

    for _, entry in ipairs(COMMANDS) do
        if entry.name == cmd then
            entry.handler(tokens[2])
            return
        end
    end

    -- A typo must be visibly a typo, never a silent fallback (S4).
    ns.Print("Unknown command: %s", cmd)
    PrintUsage()
end
