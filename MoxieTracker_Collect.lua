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

    -- Pass 2: by ID, only for professions this character actually has --
    -- gated via ns.IsProfessionLearned (defined below), the same fix #40
    -- applied to Concentration and for the same reason: GetCurrencyInfo
    -- returns a valid nonzero quantity for a Moxie currency ID any
    -- character on the account has ever earned, not just ones the CURRENT
    -- character has trained.
    for _, profession in ipairs(ns.MOXIE_PROFESSIONS) do
        local info = C_CurrencyInfo.GetCurrencyInfo(profession.id)
        if info and info.name and (info.quantity or 0) > 0 and ns.IsProfessionLearned(profession.enum) then
            Add(profession.id, nil, info.name, info.quantity)
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

-- Drops any profession muted for this character from a raw professions list
-- (either the current character's live breakdown or a stored snapshot's) and
-- re-sums the total from what's left, so muting a profession also removes
-- its points from the character's displayed total rather than just hiding
-- the line. Returns nil, nil for a nil list (the pre-breakdown legacy shape),
-- so callers can tell "nothing to filter" apart from "filtered down to
-- nothing". Applied here, at roster-assembly time, rather than in
-- SnapshotKnowledge or CollectUnspentKnowledgeByProfession, so the raw data
-- keeps accumulating in storage and un-muting a profession later doesn't
-- need that character to log back in to reappear -- same reasoning as
-- ns.IsCharacterMuted only being checked in this function's Add().
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

    local currentProfessions, currentTotal =
        FilterMutedProfessions(currentKey, ns.CollectUnspentKnowledgeByProfession())
    Add(currentKey, currentName, currentTotal, currentProfessions)

    for key, entry in pairs(MoxieTrackerDB.knowledge or {}) do
        local professions, total = FilterMutedProfessions(key, entry.professions)
        if professions then
            Add(key, entry.name, total, professions)
        else
            Add(key, entry.name, entry.points, entry.professions)
        end
    end

    table.sort(roster, function(a, b)
        return a.name < b.name
    end)

    return roster
end

-- Flat character+profession list for the options panel's profession-mute
-- section, one row per profession any character has ever recorded unspent
-- Knowledge in -- muted or not, same "show it anyway so there's a way to
-- un-mute it" reasoning as CollectKnowledgeRoster's includeMuted. A fully
-- muted character is skipped entirely: its roster line never renders, so
-- per-profession controls for it would have nothing to affect.
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

    AddCharacter(currentKey, currentName, ns.CollectUnspentKnowledgeByProfession())

    for key, entry in pairs(MoxieTrackerDB.knowledge or {}) do
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

-- Attempts to learn the currently-open profession's Concentration currency
-- ID, persisting it into MoxieTrackerDB.concentrationCurrencyIDs so it does
-- not need rediscovering on a later login. Safe to call any time -- returns
-- nil for a gathering profession (no Concentration currency exists) or when
-- no profession's crafting window is open. See ns.CONCENTRATION_PROFESSIONS
-- in the Config file for why this is a live per-profession lookup rather
-- than a static ID table, and TODO.md's Sources section for how the API
-- shape was confirmed.
function ns.DiscoverConcentrationCurrencyID()
    if not C_TradeSkillUI or not C_TradeSkillUI.GetProfessionChildSkillLineID
        or not C_TradeSkillUI.GetConcentrationCurrencyID or not C_TradeSkillUI.GetProfessionInfoBySkillLineID then
        return nil
    end

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

    MoxieTrackerDB.concentrationCurrencyIDs = MoxieTrackerDB.concentrationCurrencyIDs or {}
    MoxieTrackerDB.concentrationCurrencyIDs[professionName] = currencyID
    return professionName, currencyID
end

-- Live read of one profession's Concentration for the current character, or
-- nil if that profession's currency ID has not been discovered yet (see
-- ns.DiscoverConcentrationCurrencyID). Returns the same three fields
-- C_CurrencyInfo.GetCurrencyInfo exposes for a regenerating currency:
-- quantity, maxQuantity, and the recharge interval in milliseconds per
-- point -- all read live, never hardcoded (confirmed available on this
-- struct via derfloh205/CraftSim's ConcentrationData:Update()).
function ns.CollectConcentrationForProfession(professionName)
    local currencyIDs = MoxieTrackerDB.concentrationCurrencyIDs
    local currencyID = currencyIDs and currencyIDs[professionName]
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

-- Projects a stored (possibly stale, for an offline character) Concentration
-- snapshot forward to "now", the same linear-regen formula
-- derfloh205/CraftSim's ConcentrationData:GetCurrentAmount()/:GetTimeUntil()
-- use: amount grows by one point per rechargeMS/1000 seconds elapsed since
-- lastUpdated, capped at maxQuantity. `secondsUntilCap` is 0 once already
-- there, or nil when the recharge rate isn't known (an undiscovered/zero
-- rechargeMS currency has nothing to project).
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

-- Whether the current character has actually learned `profession` (an
-- Enum.Profession value). Confirmed against derfloh205/CraftSim's
-- IsProfessionLearned (Util/Util.lua) and each function's real return
-- signature in Blizzard's own source
-- (Blizzard_ProfessionsBook.lua/Blizzard_WorldMapTemplates.lua):
-- GetProfessions() returns up to six profession-book slot indices
-- (prof1, prof2, archaeology, fishing, cooking, firstAid -- several
-- commonly nil, so each is checked individually rather than via ipairs()
-- over a table literal, which stops at the first nil and could skip a
-- later, populated slot), GetProfessionInfo(slotIndex)'s 7th return value
-- is that slot's skillLineID, and C_TradeSkillUI.GetProfessionInfoBySkillLineID
-- resolves the locale-independent Enum.Profession for it.
--
-- This exists because C_CurrencyInfo.GetCurrencyInfo happily returns a
-- valid (0-quantity) struct for a Concentration currency ID discovered via
-- a *different* character on the account (currency IDs are account-wide
-- once known, see ns.DiscoverConcentrationCurrencyID), even for a
-- profession this character has never trained. Without this check, every
-- profession any alt had ever opened would show up for every character.
--
-- GetProfessions() is confirmed empirically to go dark by the time
-- PLAYER_LOGOUT fires -- returning nil for every one of the six slots, not
-- just an unrelated one -- even though the identical call succeeds earlier
-- in the same session (caught live via a debug trace written into
-- SavedVariables from ns.SnapshotConcentration, since a chat print during
-- logout is not reliably seen: a character with a currently-open Alchemy
-- and Engineering, both confirmed moments earlier via a live /run query,
-- still logged out with every profession reporting not-learned). Without a
-- fallback, that made ns.SnapshotConcentration -- the one and only caller
-- of this function that runs at logout -- silently write an empty
-- professions table for any character whose currency ID was already known
-- from a different character, rather than one they had to freshly
-- discover themselves this session (see the module comment above
-- ns.SnapshotConcentration for why only Tharavol/Galanodel/Ebonclad, who
-- each discovered their own profession's ID while the crafting window
-- was open, ever got real data).
--
-- ns._learnedProfessionsCache remembers the last successfully-computed
-- learned set per character (keyed by ns.GetCharacterKey(), session-local
-- only -- never written to SavedVariables) so a logout-time API dropout
-- falls back to what was already confirmed live during normal play, rather
-- than concluding the character has no professions at all. Kept on `ns`
-- itself, not a plain module-local, purely so tests/run.lua can clear it
-- between scenarios the same way it resets MoxieTrackerDB -- real gameplay
-- never clears it mid-session, since a genuine session boundary always
-- means a fresh ns.WarmLearnedProfessionsCache call at PLAYER_ENTERING_WORLD.
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

-- Six slots checked individually rather than via ipairs() over a table
-- literal, which stops at the first nil and could skip a later, populated
-- slot -- several of the six are commonly nil.
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

-- Populates ns._learnedProfessionsCache for the current character without
-- needing an ns.IsProfessionLearned(profession) call for a specific
-- profession first. Called from PLAYER_ENTERING_WORLD (see the UI file)
-- unconditionally, regardless of whether the tracker window is currently
-- shown, so the cache is warm well before PLAYER_LOGOUT can need it --
-- RefreshAllWindows, which every other ns.IsProfessionLearned caller runs
-- through, only fires while a tracker window is visible.
function ns.WarmLearnedProfessionsCache()
    if not GetProfessions or not GetProfessionInfo or not C_TradeSkillUI
        or not C_TradeSkillUI.GetProfessionInfoBySkillLineID then
        return
    end
    local learned = ComputeLearnedProfessions()
    if learned then
        ns._learnedProfessionsCache[ns.GetCharacterKey()] = learned
    end
end

function ns.IsProfessionLearned(profession)
    if not GetProfessions or not GetProfessionInfo or not C_TradeSkillUI
        or not C_TradeSkillUI.GetProfessionInfoBySkillLineID then
        return false
    end
    local key = ns.GetCharacterKey()
    local learned = ComputeLearnedProfessions()
    if learned then
        ns._learnedProfessionsCache[key] = learned
    else
        learned = ns._learnedProfessionsCache[key]
    end
    return learned ~= nil and learned[profession] == true
end

-- Persists the current character's Concentration into the account-wide
-- roster, one entry per profession whose currency ID is already known AND
-- that this character has actually learned (ns.IsProfessionLearned) --
-- mirrors ns.SnapshotKnowledge's per-logout accumulation, called from the
-- same PLAYER_LOGOUT handler (see MoxieTracker_UI.lua for why logout, not
-- entering-world). A profession discovered on some other character, but not
-- learned by this one, stays absent here entirely.
function ns.SnapshotConcentration()
    local key, name = ns.GetCharacterKey()
    local professions = {}

    for _, profession in ipairs(ns.CONCENTRATION_PROFESSIONS) do
        if MoxieTrackerDB.concentrationCurrencyIDs and MoxieTrackerDB.concentrationCurrencyIDs[profession.name]
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

    MoxieTrackerDB.concentration = MoxieTrackerDB.concentration or {}
    MoxieTrackerDB.concentration[key] = { name = name, professions = professions }
end

-- Returns the saved Concentration roster as a name-sorted array, same shape
-- as ns.CollectKnowledgeRoster: the current character's professions are
-- always live (a direct ns.CollectConcentrationForProfession read, not
-- last-login's snapshot), every other character's are projected forward
-- from their last snapshot via ns.ProjectConcentration since Concentration
-- keeps regenerating while offline, unlike Knowledge. Each profession entry
-- carries `current` (rounded down to a whole point, matching what the
-- in-game currency display shows) and `secondsUntilCap` for the caller to
-- format. Muting is Concentration's own independent whole-character/
-- per-profession pair (ns.IsConcentrationCharacterMuted/
-- ns.IsConcentrationProfessionMuted), so it never touches Knowledge's mute
-- state for the same character.
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

    -- Live source is gated by ns.IsProfessionLearned the same way
    -- ns.SnapshotConcentration is (see the comment there): a currency ID
    -- discovered via a different character is known account-wide, but
    -- must not be attributed to a character who never trained that
    -- profession.
    local liveSource = {}
    for _, profession in ipairs(ns.CONCENTRATION_PROFESSIONS) do
        if MoxieTrackerDB.concentrationCurrencyIDs and MoxieTrackerDB.concentrationCurrencyIDs[profession.name]
            and ns.IsProfessionLearned(profession.enum) then
            local live = ns.CollectConcentrationForProfession(profession.name)
            if live then
                liveSource[profession.name] = live
            end
        end
    end
    Add(currentKey, currentName, liveSource, true)

    for key, entry in pairs(MoxieTrackerDB.concentration or {}) do
        Add(key, entry.name, entry.professions, false)
    end

    table.sort(roster, function(a, b)
        return a.name < b.name
    end)

    return roster
end

-- Flat character+profession list for the options panel's Concentration
-- profession-mute section, mirroring ns.CollectKnowledgeProfessionRoster's
-- shape exactly (same characterKey/characterName/professionName/muted
-- fields, plus `current`/`maxQuantity` for context in place of Knowledge's
-- `points`). A wholly muted character is skipped entirely, same reasoning
-- as ns.CollectKnowledgeProfessionRoster: its roster line never renders, so
-- per-profession controls for it would have nothing to affect. Built from
-- ns.CollectConcentrationRoster(true) rather than reimplementing the
-- live-vs-projected read, so this and the tracker window always agree on
-- what a character's Concentration actually is.
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
