-- Depends on all other MoxieTracker files, loaded last per the TOC. Slash
-- command registration and the /moxie handler.
local _, ns = ...

SLASH_MOXIETRACKER1 = "/moxie"
-- /moxie is short enough to be contested by another addon; SlashCmdList
-- registration is last-writer-wins, so this full-length fallback is never lost.
SLASH_MOXIETRACKER2 = "/moxietracker"
SlashCmdList["MOXIETRACKER"] = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")

    if msg == "debug" then
        local offsetX, offsetY = ns.GetOffset()
        print(string.format("|cff33ff99MoxieTracker|r: anchor offset %.1f, %.1f (%s); crafting frame %s",
            offsetX, offsetY,
            (type(MoxieTrackerDB.offsetY) == "number") and "user placed" or "default",
            ns.craftingFrame and "found" or "not loaded"))

        -- Queried by ID so zero-quantity and undiscovered currencies still
        -- report, which the currency-list walk below cannot show.
        print("|cff33ff99MoxieTracker|r: tracked IDs")
        for _, group in ipairs({ { "always", ns.ALWAYS_SHOWN_IDS }, { "moxie", ns.MOXIE_IDS } }) do
            for _, currencyID in ipairs(group[2]) do
                local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
                print(string.format("  [%s] %d %s = %s",
                    group[1], currencyID,
                    info and info.name or "|cffff3333unknown|r",
                    info and tostring(info.quantity or 0) or "n/a"))
            end
        end

        print("|cff33ff99MoxieTracker|r: tracked items")
        for _, item in ipairs(ns.TRACKED_ITEMS) do
            local name = C_Item.GetItemInfo(item.itemID)
            print(string.format("  [item] %d %s = %d%s",
                item.itemID,
                name or (item.name .. " |cffff3333(uncached)|r"),
                C_Item.GetItemCount(item.itemID, true, false, true, true) or 0,
                ns.IsHidden(ns.EntryKey(nil, item.itemID)) and " |cffff3333(hidden)|r" or ""))
        end

        local hiddenCount = 0
        if MoxieTrackerDB.hidden then
            for key in pairs(MoxieTrackerDB.hidden) do
                hiddenCount = hiddenCount + 1
                print(string.format("  [hidden] %s", key))
            end
        end
        print(string.format("|cff33ff99MoxieTracker|r: %d hidden row(s)", hiddenCount))

        local size = C_CurrencyInfo.GetCurrencyListSize and C_CurrencyInfo.GetCurrencyListSize() or 0
        print(string.format("|cff33ff99MoxieTracker|r: currency list size = %d", size))
        for index = 1, size do
            local info = C_CurrencyInfo.GetCurrencyListInfo(index)
            if info then
                if info.isHeader then
                    print(string.format("  [%d] HEADER %s (expanded: %s)",
                        index, tostring(info.name), tostring(info.isHeaderExpanded)))
                elseif (info.quantity or 0) > 0 then
                    print(string.format("  [%d] %s = %d (id %s)",
                        index, tostring(info.name), info.quantity, tostring(ns.GetCurrencyIDForIndex(index))))
                end
            end
        end
        return
    end

    if msg == "reset" then
        ns.ResetPosition()
        print("|cff33ff99MoxieTracker|r: position reset to the crafting window's top-right corner.")
        return
    end

    if msg == "options" or msg == "config" then
        if not ns.OpenOptions() then
            print("|cff33ff99MoxieTracker|r: this client has no Settings panel; open Options > AddOns manually.")
        end
        return
    end

    if msg == "showall" then
        MoxieTrackerDB.hidden = nil
        if ns.optionsPanel:IsShown() then
            ns.RefreshOptions()
        end
        ns.RefreshVisibility()
        print("|cff33ff99MoxieTracker|r: every row is visible again.")
        return
    end

    if msg == "pin" then
        ns.frame.pinned = not ns.frame.pinned
        ns.RefreshVisibility()
        print(string.format("|cff33ff99MoxieTracker|r: pinned %s.",
            ns.frame.pinned and "on - panel stays visible" or "off - panel follows the crafting window"))
        return
    end

    print("|cff33ff99MoxieTracker|r: shows automatically with the crafting window.")
    print("  /moxie options - choose which rows are shown")
    print("  /moxie showall - unhide every row")
    print("  /moxie pin - keep the panel visible regardless")
    print("  /moxie debug - list currencies")
    print("  /moxie reset - move the panel back to the crafting window's top-right")
end
