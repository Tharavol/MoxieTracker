-- Slash command registration and the /moxie handler. Loads last.
local _, ns = ...

SLASH_MOXIETRACKER1 = "/moxie"
-- /moxie is short enough to be contested by another addon; SlashCmdList
-- registration is last-writer-wins, so this full-length fallback is never lost.
SLASH_MOXIETRACKER2 = "/moxietracker"

local function OpenOptions()
    ns.OpenOptions()
end

local function PrintDebugDump()
    for _, window in ipairs({ "main", "knowledge", "concentration" }) do
        local offsetX, offsetY = ns.GetOffset(window)
        local placement = MoxieTrackerDB.windows[window] and "user placed"
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
        local currencyID = MoxieTrackerDB.concentrationCurrencyIDs[profession.name]
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

    ns.Print("tracked quests")
    for _, quest in ipairs(ns.TRACKED_QUESTS) do
        local name = C_QuestLog.GetTitleForQuestID(quest.questID)
        ns.Print("  [quest] %d %s = %s%s",
            quest.questID,
            name or (quest.name .. " |cffff3333(uncached)|r"),
            C_QuestLog.IsQuestFlaggedCompleted(quest.questID) and "done" or "not done",
            ns.IsHidden(ns.EntryKey(nil, nil, nil, quest.questID)) and " |cffff3333(hidden)|r" or "")
    end

    local hiddenCount = 0
    for key in pairs(MoxieTrackerDB.hidden) do
        hiddenCount = hiddenCount + 1
        ns.Print("  [hidden] %s", key)
    end
    ns.Print("%d hidden row(s)", hiddenCount)

    local size = C_CurrencyInfo.GetCurrencyListSize()
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

-- Bare toggles; on/off sets; "dump" prints diagnostics; anything else is rejected (S8/S12).
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

-- "reset settings" restores options to defaults; window positions have "reset position".
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
        MoxieTrackerDB.hideConcentrationUnderThreshold = nil
        MoxieTrackerDB.characterOrder = nil
        MoxieTrackerDB.debugLogging = nil
        ns.InitSavedVariables()
        ns.frame.pinned = false
        -- Refresh whichever options page is open.
        local pages = {
            { ns.generalPanel, ns.RefreshGeneralOptions },
            { ns.moxieProfessionsPanel, ns.RefreshMoxieProfessionsOptions },
            { ns.thresholdsPanel, ns.RefreshThresholdsOptions },
            { ns.charactersPanel, ns.RefreshCharactersOptions },
            { ns.characterProfessionsPanel, ns.RefreshCharacterProfessionsOptions },
            { ns.concentrationPanel, ns.RefreshConcentrationOptions },
            { ns.concentrationProfessionsPanel, ns.RefreshConcentrationProfessionsOptions },
            { ns.characterOrderPanel, ns.RefreshCharacterOrderOptions },
        }
        for _, page in ipairs(pages) do
            if page[1]:IsShown() then
                page[2]()
            end
        end
        ns.RefreshVisibility()
        ns.Print("settings restored to defaults.")
    else
        ns.Print("Usage: /moxie reset position|settings")
    end
end

local function PrintStatus()
    ns.Print("pinned: %s", tostring(ns.frame.pinned == true))

    local function CountFlat(field)
        local count = 0
        for _ in pairs(MoxieTrackerDB[field]) do
            count = count + 1
        end
        return count
    end
    -- {char = {profession = true}}
    local function CountNested(field)
        local count = 0
        for _, entries in pairs(MoxieTrackerDB[field]) do
            for _ in pairs(entries) do
                count = count + 1
            end
        end
        return count
    end
    ns.Print("hidden rows: %d", CountFlat("hidden"))

    ns.Print("Knowledge mutes: %d character(s), %d profession(s)",
        CountFlat("mutedCharacters"), CountNested("mutedProfessions"))
    ns.Print("Concentration mutes: %d character(s), %d profession(s)",
        CountFlat("mutedConcentrationCharacters"), CountNested("mutedConcentrationProfessions"))

    ns.Print("Moxie: %s", MoxieTrackerDB.hideMoxie and "hidden" or "shown")
    ns.Print("Knowledge Points window: %s", MoxieTrackerDB.hideKnowledgeWindow and "hidden" or "shown")
    ns.Print("Concentration window: %s", MoxieTrackerDB.hideConcentrationWindow and "hidden" or "shown")
    ns.Print("Concentration values under threshold: %s",
        MoxieTrackerDB.hideConcentrationUnderThreshold and "hidden" or "shown")

    if next(MoxieTrackerDB.thresholds) then
        local parts = {}
        for key, value in pairs(MoxieTrackerDB.thresholds) do
            parts[#parts + 1] = key .. "=" .. tostring(value)
        end
        table.sort(parts)
        ns.Print("threshold overrides: %s", table.concat(parts, ", "))
    else
        ns.Print("threshold overrides: none (using defaults)")
    end

    local characterOrder = ns.GetCharacterOrder()
    if characterOrder then
        ns.Print("character order: custom (%d character(s))", #characterOrder)
    else
        ns.Print("character order: alphabetical (default)")
    end

    ns.Print("debug logging: %s", MoxieTrackerDB.debugLogging and "on" or "off")
end

-- Help text is derived from this table (S13). "", "config" and "gui" are silent
-- aliases of "options" (S5).
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
            "/moxie reset settings - restore hidden rows, muted characters/professions, the Moxie, Knowledge " ..
                "Points and Concentration window toggles, pin state, thresholds, the Concentration " ..
                "under-threshold display toggle, character order, and debug logging to defaults"
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
    -- No /moxie argument is case-sensitive, so every token is lowercased.
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

    -- S4: an unknown command is reported, not silently ignored.
    ns.Print("Unknown command: %s", cmd)
    PrintUsage()
end
