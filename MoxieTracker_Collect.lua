-- Depends on MoxieTracker_Config.lua's ns.* tables and accessors, loaded
-- first per the TOC. Pure collection/rendering logic: reads C_CurrencyInfo,
-- C_Item, and MoxieTrackerDB, and touches no frame.
local _, ns = ...

local function MatchesKeyword(text)
    if not text or text == "" then
        return false
    end
    text = text:lower()
    for _, keyword in ipairs(ns.KEYWORDS) do
        if text:find(keyword, 1, true) then
            return true
        end
    end
    return false
end

local MOXIE_ID_SET = {}
for _, currencyID in ipairs(ns.MOXIE_IDS) do
    MOXIE_ID_SET[currencyID] = true
end

function ns.GetQuantityColor(entry)
    if entry.itemID then
        local itemRule = ns.ITEM_QUANTITY_COLOR[entry.itemID]
        return itemRule and itemRule(entry.quantity) or ns.WHITE
    end

    local rule = entry.currencyID and ns.QUANTITY_COLOR[entry.currencyID]
    if rule then
        return rule(entry.quantity)
    end
    -- ID first so the threshold survives a non-English client; the name check
    -- only covers a moxie currency that reached us through the keyword fallback.
    local isMoxie = (entry.currencyID and MOXIE_ID_SET[entry.currencyID])
        or (entry.name and entry.name:lower():find("moxie", 1, true))
    if isMoxie then
        return entry.quantity >= ns.GetThreshold("moxie") and ns.GREEN or ns.YELLOW
    end
    return ns.WHITE
end

-- Name only. Descriptions cross-reference each other -- Shard of Dundun's
-- description mentions Unalloyed Abundance -- so matching them pulls in
-- unrelated currencies that merely name one of ours.
local function IsTrackedCurrency(info)
    if not info or info.isHeader or not info.quantity or info.quantity <= 0 then
        return false
    end
    return MatchesKeyword(info.name)
end

-- GetCurrencyListInfo does not return the currency ID; it has to come from the link.
function ns.GetCurrencyIDForIndex(index)
    local link = C_CurrencyInfo.GetCurrencyListLink(index)
    if link then
        return C_CurrencyInfo.GetCurrencyIDFromLink(link)
    end
end

-- `includeHidden` is for the options panel, which has to list the rows the user
-- has switched off in order to offer switching them back on.
function ns.CollectTracked(includeHidden)
    local tracked = {}
    local seenID, seenItemID, seenName = {}, {}, {}

    -- Deduped by both ID and name: the keyword fallback can produce an entry
    -- whose link failed to resolve, leaving it with no ID to match on.
    local function Add(currencyID, itemID, name, quantity)
        name = name or "Currency"
        local nameKey = name:lower()
        if (currencyID and seenID[currencyID]) or (itemID and seenItemID[itemID]) or seenName[nameKey] then
            return
        end
        if currencyID then
            seenID[currencyID] = true
        end
        if itemID then
            seenItemID[itemID] = true
        end
        seenName[nameKey] = true

        -- Marked seen before the hidden check, so a hidden row cannot slip back
        -- in through a later pass that identifies it a different way.
        local key = ns.EntryKey(currencyID, itemID, name)
        local hidden = ns.IsHidden(key)
        if hidden and not includeHidden then
            return
        end

        table.insert(tracked, {
            name = name,
            quantity = quantity or 0,
            currencyID = currencyID,
            itemID = itemID,
            key = key,
            hidden = hidden,
        })
    end

    -- Pass 1: by ID, shown regardless of quantity.
    for _, currencyID in ipairs(ns.ALWAYS_SHOWN_IDS) do
        local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
        if info and info.name then
            Add(currencyID, nil, info.name, info.quantity)
        end
    end

    -- Pass 2: by ID, only for professions this character actually has.
    for _, currencyID in ipairs(ns.MOXIE_IDS) do
        local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
        if info and info.name and (info.quantity or 0) > 0 then
            Add(currencyID, nil, info.name, info.quantity)
        end
    end

    -- Pass 3: bag items. Counted across bags, bank, and reagent bank, so the
    -- number matches what the character owns rather than what is carried.
    for _, item in ipairs(ns.TRACKED_ITEMS) do
        local name = C_Item.GetItemInfo(item.itemID) or item.name
        local count = C_Item.GetItemCount(item.itemID, true, false, true, true) or 0
        Add(nil, item.itemID, name, count)
    end

    -- Pass 4: keyword fallback over the currency list, for anything matching
    -- that neither ID table knows about yet.
    local size = C_CurrencyInfo.GetCurrencyListSize and C_CurrencyInfo.GetCurrencyListSize() or 0
    for index = 1, size do
        local info = C_CurrencyInfo.GetCurrencyListInfo(index)
        if IsTrackedCurrency(info) then
            Add(ns.GetCurrencyIDForIndex(index), nil, info.name, info.quantity)
        end
    end

    table.sort(tracked, function(a, b)
        return a.name < b.name
    end)

    return tracked
end
