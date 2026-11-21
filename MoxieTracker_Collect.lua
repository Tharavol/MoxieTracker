-- Data collection from C_CurrencyInfo, C_Item, C_QuestLog and MoxieTrackerDB. No frames.
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

-- Quest rows (#53) show a status word instead of a count.
function ns.GetQuestStatus(entry)
    if entry.completed then
        return ns.GREEN, "Done"
    end
    return ns.YELLOW, "Not done"
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

-- `includeHidden` lists switched-off rows for the options panel. `excludeMoxie` is
-- for the General page (#43); Moxie has its own Moxie Professions page.
function ns.CollectTracked(includeHidden, excludeMoxie)
    local tracked = {}
    local seenID, seenItemID, seenQuestID, seenName = {}, {}, {}, {}

    -- Deduped by both ID and name: the keyword fallback can produce an entry
    -- whose link failed to resolve, leaving it with no ID to match on.
    -- Returns the inserted entry, so a pass can attach fields of its own.
    local function Add(currencyID, itemID, name, quantity, questID)
        name = name or "Currency"
        local nameKey = name:lower()
        if (currencyID and seenID[currencyID]) or (itemID and seenItemID[itemID])
            or (questID and seenQuestID[questID]) or seenName[nameKey] then
            return
        end
        if currencyID then
            seenID[currencyID] = true
        end
        if itemID then
            seenItemID[itemID] = true
        end
        if questID then
            seenQuestID[questID] = true
        end
        seenName[nameKey] = true

        -- Marked seen before the hidden check, so a hidden row cannot slip back
        -- in through a later pass that identifies it a different way.
        local key = ns.EntryKey(currencyID, itemID, name, questID)
        local hidden = ns.IsHidden(key)
        if hidden and not includeHidden then
            return
        end

        local entry = {
            name = name,
            quantity = quantity or 0,
            currencyID = currencyID,
            itemID = itemID,
            questID = questID,
            key = key,
            hidden = hidden,
        }
        table.insert(tracked, entry)
        return entry
    end

    -- Pass 1: by ID, shown regardless of quantity.
    for _, currencyID in ipairs(ns.ALWAYS_SHOWN_IDS) do
        local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
        if info and info.name then
            Add(currencyID, nil, info.name, info.quantity)
        end
    end

    -- Pass 1b (#53): weekly quests, always listed. See ns.TRACKED_QUESTS.
    for _, quest in ipairs(ns.TRACKED_QUESTS) do
        local name = C_QuestLog.GetTitleForQuestID(quest.questID) or quest.name
        local entry = Add(nil, nil, name, 0, quest.questID)
        if entry then
            entry.completed = C_QuestLog.IsQuestFlaggedCompleted(quest.questID) == true
            entry.sortAfter = quest.sortAfter
        end
    end

    -- Pass 2: Moxie by ID, only for learned professions (see ns.MOXIE_PROFESSIONS)
    -- and only while "Show Moxie" (#43) is on.
    if not excludeMoxie and not MoxieTrackerDB.hideMoxie then
        for _, profession in ipairs(ns.MOXIE_PROFESSIONS) do
            local info = C_CurrencyInfo.GetCurrencyInfo(profession.id)
            if info and info.name and (info.quantity or 0) > 0 and ns.IsProfessionLearned(profession.enum) then
                Add(profession.id, nil, info.name, info.quantity)
            end
        end
    end

    -- Pass 3: bag items. Counted across bags, bank, and reagent bank, so the
    -- number matches what the character owns rather than what is carried.
    for _, item in ipairs(ns.TRACKED_ITEMS) do
        local name = C_Item.GetItemInfo(item.itemID) or item.name
        local count = C_Item.GetItemCount(item.itemID, true, false, true, true) or 0
        Add(nil, item.itemID, name, count)
    end

    -- Pass 4: keyword fallback over the currency list for anything neither ID
    -- table knows. Known Moxie IDs are skipped: Pass 2 already applied the
    -- learned-profession gate, which this walk cannot repeat.
    local size = C_CurrencyInfo.GetCurrencyListSize()
    for index = 1, size do
        local info = C_CurrencyInfo.GetCurrencyListInfo(index)
        if IsTrackedCurrency(info) then
            local currencyID = ns.GetCurrencyIDForIndex(index)
            if not (currencyID and MOXIE_ID_SET[currencyID]) then
                Add(currencyID, nil, info.name, info.quantity)
            end
        end
    end

    -- A row with `sortAfter` (#53) sorts as its anchor currency's name plus
    -- "\1", which lands it directly after that row and ahead of any name the
    -- anchor's is a prefix of. The anchor's name is read by ID rather than
    -- from `tracked`, so the pin holds even while the anchor row is hidden.
    local sortName = {}
    for _, entry in ipairs(tracked) do
        local anchor = entry.sortAfter and C_CurrencyInfo.GetCurrencyInfo(entry.sortAfter)
        sortName[entry] = (anchor and anchor.name) and (anchor.name .. "\1") or entry.name
    end
    table.sort(tracked, function(a, b)
        return sortName[a] < sortName[b]
    end)

    return tracked
end

--------------------------------------------------------------------------------
-- Knowledge points roster (#38)
--------------------------------------------------------------------------------

-- Knowledge for every learned profession, name-sorted, including those at 0 so the
-- Character Professions page can mute them (#42). Gated on ns.IsProfessionLearned
-- because Knowledge currency IDs are visible account-wide.
function ns.CollectKnowledgeByProfession()
    local list = {}
    for _, profession in ipairs(ns.KNOWLEDGE_PROFESSIONS) do
        if ns.IsProfessionLearned(profession.enum) then
            local info = C_CurrencyInfo.GetCurrencyInfo(profession.id)
            table.insert(list, { name = profession.name, points = info and (info.quantity or 0) or 0 })
        end
    end
    table.sort(list, function(a, b)
        return a.name < b.name
    end)
    return list
end

-- Same as above, without professions at 0.
function ns.CollectUnspentKnowledgeByProfession()
    local list = {}
    for _, profession in ipairs(ns.CollectKnowledgeByProfession()) do
        if profession.points > 0 then
            table.insert(list, profession)
        end
    end
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

-- Saves this character's Knowledge into the account-wide roster at logout (see the
-- PLAYER_LOGOUT handler); the client cannot read other characters' state. Professions
-- at 0 are kept for the options panel (#42) and filtered out when rendering.
function ns.SnapshotKnowledge()
    local key, name = ns.GetCharacterKey()
    local professions = ns.CollectKnowledgeByProfession()
    local total = 0
    for _, profession in ipairs(professions) do
        total = total + profession.points
    end

    MoxieTrackerDB.knowledge[key] = { name = name, points = total, professions = professions }
end

-- Drops muted professions and re-sums the total. Applied at read time so stored data
-- stays complete. Returns nil, nil for a legacy entry with no breakdown.
local function FilterMutedProfessions(characterKey, professions)
    if not professions then
        return nil, nil
    end
    local filtered = {}
    local total = 0
    for _, profession in ipairs(professions) do
        if not ns.IsKnowledgeProfessionMuted(characterKey, profession.name) then
            table.insert(filtered, profession)
            total = total + profession.points
        end
    end
    return filtered, total
end

-- The current character is read live; others come from their last logout. A legacy
-- entry may lack `professions`. `includeMuted` is for the options panel.
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

    local currentProfessions, currentTotal =
        FilterMutedProfessions(currentKey, ns.CollectUnspentKnowledgeByProfession())
    Add(currentKey, currentName, currentTotal, currentProfessions)

    for key, entry in pairs(MoxieTrackerDB.knowledge) do
        local professions, total = FilterMutedProfessions(key, entry.professions)
        if professions then
            Add(key, entry.name, total, professions)
        else
            Add(key, entry.name, entry.points, entry.professions)
        end
    end

    ns.SortRosterByCharacterOrder(roster, ns.GetCharacterOrder())

    return roster
end

-- Character+profession rows for the Character Professions page: every learned
-- profession, muted or not, including those at 0 (#42). Wholly muted characters are skipped.
function ns.CollectKnowledgeProfessionRoster()
    local currentKey, currentName = ns.GetCharacterKey()
    local list = {}

    local function AddCharacter(key, name, professions)
        if not professions or ns.IsCharacterMuted(key) then
            return
        end
        for _, profession in ipairs(professions) do
            table.insert(list, {
                characterKey = key,
                characterName = name,
                professionName = profession.name,
                points = profession.points,
                muted = ns.IsKnowledgeProfessionMuted(key, profession.name),
            })
        end
    end

    AddCharacter(currentKey, currentName, ns.CollectKnowledgeByProfession())

    for key, entry in pairs(MoxieTrackerDB.knowledge) do
        if key ~= currentKey then
            AddCharacter(key, entry.name, entry.professions)
        end
    end

    table.sort(list, function(a, b)
        if a.characterName == b.characterName then
            return a.professionName < b.professionName
        end
        return a.characterName < b.characterName
    end)

    return list
end

--------------------------------------------------------------------------------
-- Concentration roster (#40)
--------------------------------------------------------------------------------

-- Records the open profession's Concentration currency ID. Returns nil for a
-- gathering profession or when no crafting window is open.
function ns.DiscoverConcentrationCurrencyID()
    local skillLineID = C_TradeSkillUI.GetProfessionChildSkillLineID()
    if not skillLineID or skillLineID <= 0 then
        return nil
    end

    local currencyID = C_TradeSkillUI.GetConcentrationCurrencyID(skillLineID)
    if not currencyID then
        return nil
    end

    local professionInfo = C_TradeSkillUI.GetProfessionInfoBySkillLineID(skillLineID)
    local professionName = professionInfo and ns.CONCENTRATION_PROFESSION_BY_ENUM[professionInfo.profession]
    if not professionName then
        return nil
    end

    MoxieTrackerDB.concentrationCurrencyIDs[professionName] = currencyID
    return professionName, currencyID
end

-- Live Concentration for the current character, or nil if the currency ID is not
-- discovered yet. rechargeMS is milliseconds per point.
function ns.CollectConcentrationForProfession(professionName)
    local currencyID = MoxieTrackerDB.concentrationCurrencyIDs[professionName]
    if not currencyID then
        return nil
    end
    local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
    if not info then
        return nil
    end
    return {
        quantity = info.quantity or 0,
        maxQuantity = info.maxQuantity or 0,
        rechargeMS = info.rechargingCycleDurationMS or 0,
    }
end

-- Projects an offline snapshot to now: one point per rechargeMS since lastUpdated,
-- capped at maxQuantity. `secondsUntilCap` is nil when the recharge rate is unknown.
function ns.ProjectConcentration(snapshot)
    local rechargeSeconds = (snapshot.rechargeMS or 0) / 1000
    local current = snapshot.quantity or 0

    if rechargeSeconds > 0 and snapshot.maxQuantity and snapshot.maxQuantity > 0 then
        local elapsed = math.max(0, (GetServerTime() - (snapshot.lastUpdated or GetServerTime())))
        current = math.min(snapshot.maxQuantity, current + (elapsed / rechargeSeconds))
    end

    local secondsUntilCap
    if rechargeSeconds > 0 and snapshot.maxQuantity and snapshot.maxQuantity > 0 then
        secondsUntilCap = math.max(0, (snapshot.maxQuantity - current) * rechargeSeconds)
    end

    return current, secondsUntilCap
end

-- Learned-profession detection. Currency IDs are account-wide, so GetCurrencyInfo
-- answers for professions this character never trained; this gates them.
--
-- GetProfessions() returns nil for all six slots by PLAYER_LOGOUT (confirmed
-- in-game), so the last successful result is kept per character: in a
-- session cache, and in MoxieTrackerDB.learnedProfessions (#46) for a session
-- where the cache was never warmed.
local function PersistLearnedProfessions(key, learned)
    MoxieTrackerDB.learnedProfessions[key] = learned
end

-- On `ns` so tests/run.lua can clear it between scenarios.
ns._learnedProfessionsCache = {}

local function AddSlotProfession(learned, slotIndex)
    if not slotIndex then
        return
    end
    local skillLineID = select(7, GetProfessionInfo(slotIndex))
    local info = skillLineID and C_TradeSkillUI.GetProfessionInfoBySkillLineID(skillLineID)
    if info and info.profession then
        learned[info.profession] = true
    end
end

-- GetProfessions returns six slot indices, several commonly nil, so each is checked
-- individually. GetProfessionInfo's 7th return is the slot's skillLineID.
local function ComputeLearnedProfessions()
    local prof1, prof2, arch, fish, cook, firstAid = GetProfessions()
    if not (prof1 or prof2 or arch or fish or cook or firstAid) then
        return nil
    end
    local learned = {}
    AddSlotProfession(learned, prof1)
    AddSlotProfession(learned, prof2)
    AddSlotProfession(learned, arch)
    AddSlotProfession(learned, fish)
    AddSlotProfession(learned, cook)
    AddSlotProfession(learned, firstAid)
    return learned
end

-- Called at PLAYER_ENTERING_WORLD so the cache is warm before logout, even if no
-- tracker window was ever shown.
function ns.WarmLearnedProfessionsCache()
    local learned = ComputeLearnedProfessions()
    if learned then
        local key = ns.GetCharacterKey()
        ns._learnedProfessionsCache[key] = learned
        PersistLearnedProfessions(key, learned)
    end
end

function ns.IsProfessionLearned(profession)
    local key = ns.GetCharacterKey()
    local learned = ComputeLearnedProfessions()
    if learned then
        ns._learnedProfessionsCache[key] = learned
        PersistLearnedProfessions(key, learned)
    else
        learned = ns._learnedProfessionsCache[key] or MoxieTrackerDB.learnedProfessions[key]
    end
    return learned ~= nil and learned[profession] == true
end

-- Saves this character's Concentration at logout, like ns.SnapshotKnowledge, for
-- each profession with a known currency ID that this character has learned.
function ns.SnapshotConcentration()
    local key, name = ns.GetCharacterKey()
    local professions = {}

    for _, profession in ipairs(ns.CONCENTRATION_PROFESSIONS) do
        if MoxieTrackerDB.concentrationCurrencyIDs[profession.name]
            and ns.IsProfessionLearned(profession.enum) then
            local live = ns.CollectConcentrationForProfession(profession.name)
            if live then
                professions[profession.name] = {
                    quantity = live.quantity,
                    maxQuantity = live.maxQuantity,
                    rechargeMS = live.rechargeMS,
                    lastUpdated = GetServerTime(),
                }
            end
        end
    end

    MoxieTrackerDB.concentration[key] = { name = name, professions = professions }
end

-- Like ns.CollectKnowledgeRoster, but other characters are projected forward since
-- Concentration regenerates offline. Projected `current` is floored to a whole point.
function ns.CollectConcentrationRoster(includeMuted)
    local currentKey, currentName = ns.GetCharacterKey()
    local roster = {}
    local seen = {}

    local function BuildProfessions(characterKey, source, isLive)
        local result = {}
        local any = false
        for _, profession in ipairs(ns.CONCENTRATION_PROFESSIONS) do
            local snapshot = source and source[profession.name]
            if snapshot then
                local muted = ns.IsConcentrationProfessionMuted(characterKey, profession.name)
                if includeMuted or not muted then
                    local current, secondsUntilCap
                    if isLive then
                        current, secondsUntilCap = snapshot.quantity, nil
                        if snapshot.rechargeMS and snapshot.rechargeMS > 0 and snapshot.maxQuantity
                            and snapshot.maxQuantity > 0 then
                            secondsUntilCap = math.max(0, (snapshot.maxQuantity - snapshot.quantity)
                                * (snapshot.rechargeMS / 1000))
                        end
                    else
                        current, secondsUntilCap = ns.ProjectConcentration(snapshot)
                        current = math.floor(current)
                    end
                    table.insert(result, {
                        name = profession.name,
                        current = current,
                        maxQuantity = snapshot.maxQuantity,
                        secondsUntilCap = secondsUntilCap,
                        muted = muted,
                    })
                    any = true
                end
            end
        end
        table.sort(result, function(a, b)
            return a.name < b.name
        end)
        return result, any
    end

    local function Add(key, name, source, isLive)
        if seen[key] then
            return
        end
        seen[key] = true

        local wholeMuted = ns.IsConcentrationCharacterMuted(key)
        if wholeMuted and not includeMuted then
            return
        end

        local professions, any = BuildProfessions(key, source, isLive)
        if not includeMuted and not any then
            return
        end

        table.insert(roster, { key = key, name = name, professions = professions, muted = wholeMuted })
    end

    local liveSource = {}
    for _, profession in ipairs(ns.CONCENTRATION_PROFESSIONS) do
        if MoxieTrackerDB.concentrationCurrencyIDs[profession.name]
            and ns.IsProfessionLearned(profession.enum) then
            local live = ns.CollectConcentrationForProfession(profession.name)
            if live then
                liveSource[profession.name] = live
            end
        end
    end
    Add(currentKey, currentName, liveSource, true)

    for key, entry in pairs(MoxieTrackerDB.concentration) do
        Add(key, entry.name, entry.professions, false)
    end

    ns.SortRosterByCharacterOrder(roster, ns.GetCharacterOrder())

    return roster
end

-- Union of both rosters for the Character Order page (#51), in display order.
function ns.CollectKnownCharacters()
    local seen = {}
    local list = {}

    local function Add(key, name)
        if not seen[key] then
            seen[key] = true
            table.insert(list, { key = key, name = name })
        end
    end

    local currentKey, currentName = ns.GetCharacterKey()
    Add(currentKey, currentName)

    for key, entry in pairs(MoxieTrackerDB.knowledge) do
        Add(key, entry.name)
    end

    for key, entry in pairs(MoxieTrackerDB.concentration) do
        Add(key, entry.name)
    end

    ns.SortRosterByCharacterOrder(list, ns.GetCharacterOrder())

    return list
end

-- Concentration counterpart of ns.CollectKnowledgeProfessionRoster, built from the
-- roster so both always agree.
function ns.CollectConcentrationProfessionRoster()
    local list = {}
    for _, entry in ipairs(ns.CollectConcentrationRoster(true)) do
        if not entry.muted then
            for _, profession in ipairs(entry.professions) do
                table.insert(list, {
                    characterKey = entry.key,
                    characterName = entry.name,
                    professionName = profession.name,
                    current = profession.current,
                    maxQuantity = profession.maxQuantity,
                    muted = profession.muted,
                })
            end
        end
    end
    table.sort(list, function(a, b)
        if a.characterName == b.characterName then
            return a.professionName < b.professionName
        end
        return a.characterName < b.characterName
    end)
    return list
end
