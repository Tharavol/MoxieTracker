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

--------------------------------------------------------------------------------
-- Knowledge points roster (#38)
--------------------------------------------------------------------------------

-- Unspent Midnight Knowledge for the current character, broken down by
-- profession and name-sorted. A profession the character doesn't have simply
-- reports no currency info, so this doesn't need to know which professions
-- actually exist for them; professions at 0 are left out, the same "don't
-- show what isn't there" rule the roster applies to whole characters.
function ns.CollectUnspentKnowledgeByProfession()
    local list = {}
    for _, profession in ipairs(ns.KNOWLEDGE_PROFESSIONS) do
        local info = C_CurrencyInfo.GetCurrencyInfo(profession.id)
        local points = info and (info.quantity or 0) or 0
        if points > 0 then
            table.insert(list, { name = profession.name, points = points })
        end
    end
    table.sort(list, function(a, b)
        return a.name < b.name
    end)
    return list
end

-- Sums unspent Midnight Knowledge across all eleven professions.
function ns.CollectUnspentKnowledge()
    local total = 0
    for _, profession in ipairs(ns.CollectUnspentKnowledgeByProfession()) do
        total = total + profession.points
    end
    return total
end

-- Persists the current character's unspent Knowledge into the account-wide
-- roster, so it stays visible while playing a different character. Called
-- on logout (not login -- see the PLAYER_LOGOUT handler in
-- MoxieTracker_UI.lua for why); there is no scan of other characters,
-- because the client cannot see their state -- the roster grows one entry
-- at a time as each alt logs out, which is the whole "accumulation"
-- mechanism the issue asks for. The per-profession breakdown is saved
-- alongside the total so another character's roster entry can show it too,
-- not just the current one's.
function ns.SnapshotKnowledge()
    local key, name = ns.GetCharacterKey()
    local professions = ns.CollectUnspentKnowledgeByProfession()
    local total = 0
    for _, profession in ipairs(professions) do
        total = total + profession.points
    end

    MoxieTrackerDB.knowledge = MoxieTrackerDB.knowledge or {}
    MoxieTrackerDB.knowledge[key] = { name = name, points = total, professions = professions }
end

-- Returns the saved roster as a name-sorted array. The current character's
-- entry is always present and always live (not the last saved snapshot), so
-- spending or earning points mid-session doesn't look stale until the next
-- logout; every other character reflects whatever their last logout saw. A
-- character snapshotted before the per-profession breakdown existed carries
-- no `professions` field until their next logout re-snapshots it -- display
-- code treats that the same as a single-profession character (a plain
-- "Name: total" line) rather than erroring on the missing field.
--
-- `includeMuted` is for the options panel, which has to list muted characters
-- in order to offer un-muting them -- same shape as CollectTracked's
-- `includeHidden`. Muted is checked here rather than left to the caller so a
-- muted character can never slip back in through a display path that forgets
-- the filter.
function ns.CollectKnowledgeRoster(includeMuted)
    local currentKey, currentName = ns.GetCharacterKey()
    local roster = {}
    local seen = {}

    local function Add(key, name, points, professions)
        if seen[key] then
            return
        end
        seen[key] = true

        local muted = ns.IsCharacterMuted(key)
        if muted and not includeMuted then
            return
        end

        table.insert(roster, { key = key, name = name, points = points, professions = professions, muted = muted })
    end

    local currentProfessions = ns.CollectUnspentKnowledgeByProfession()
    local currentTotal = 0
    for _, profession in ipairs(currentProfessions) do
        currentTotal = currentTotal + profession.points
    end
    Add(currentKey, currentName, currentTotal, currentProfessions)

    for key, entry in pairs(MoxieTrackerDB.knowledge or {}) do
        Add(key, entry.name, entry.points, entry.professions)
    end

    table.sort(roster, function(a, b)
        return a.name < b.name
    end)

    return roster
end
