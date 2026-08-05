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
-- the TOC, not a global, so exposing pure logic on it does not add anything
-- luacheck needs to know about. Kept minimal on purpose -- only what a second
-- file or a test harness needs to reach: the ID/colour tables and the
-- functions that turn them into tracked rows.
local ADDON_NAME, ns = ...

-- The TOC's @project-version@ placeholder is only substituted by the packager
-- at release time, so an unpackaged dev copy still carries the literal token.
local function GetVersion()
    local version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")
    if not version or version == "" or version == "@project-version@" then
        return "dev"
    end
    return version
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

-- Bag items, not currencies: these come from C_Item rather than C_CurrencyInfo
-- and are counted across bags, bank, and reagent bank. Always listed, the same
-- way ALWAYS_SHOWN_IDS is, so a row at zero reads as "none" rather than
-- vanishing. `name` is only a fallback for the moments before the client has
-- cached the item.
ns.TRACKED_ITEMS = {
    { itemID = 245345, name = "Fused Vitality" },
}

-- Fallback only, for a moxie currency added in a future patch that is not in
-- MOXIE_IDS yet. Matching by name is locale-dependent and will not fire on a
-- non-English client, which is precisely why the IDs above are the primary path.
ns.KEYWORDS = {
    "moxie",
    "dundun",
}

local GREEN = "|cff33ff33"
local YELLOW = "|cffffd200"
local RED = "|cffff3333"
local WHITE = "|cffffffff"

-- Quantity coloring, keyed by currency ID. Moxie is deliberately absent: its
-- ID varies per profession, so it is handled by name in GetQuantityColor.
ns.QUANTITY_COLOR = {
    -- Shard of Dundun caps at 8, so the yellow fallback only ever covers 0-5.
    [3376] = function(quantity)
        if quantity == 6 then
            return GREEN
        elseif quantity == 7 or quantity == 8 then
            return RED
        end
        return YELLOW
    end,
    [3377] = function(quantity) -- Unalloyed Abundance
        return quantity >= 800 and GREEN or YELLOW
    end,
}

-- Same idea for bag items, keyed by item ID.
ns.ITEM_QUANTITY_COLOR = {
    [245345] = function(quantity) -- Fused Vitality
        return quantity >= 20 and GREEN or YELLOW
    end,
}

-- SavedVariables are only guaranteed populated once ADDON_LOADED fires for this
-- addon; initializing here at file scope would create a throwaway table that
-- the client's own load then silently discards. See the ADDON_LOADED handler
-- below for the real initialization.

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

local function IsHidden(key)
    return MoxieTrackerDB.hidden ~= nil and MoxieTrackerDB.hidden[key] == true
end

-- Stored only for hidden rows. Visible is the default, so writing `false` would
-- grow the saved variables with entries that mean nothing.
local function SetHidden(key, hidden)
    if hidden then
        MoxieTrackerDB.hidden = MoxieTrackerDB.hidden or {}
        MoxieTrackerDB.hidden[key] = true
    elseif MoxieTrackerDB.hidden then
        MoxieTrackerDB.hidden[key] = nil
    end
end

-- Offset from the crafting window's TOPRIGHT corner. The panel hangs off the
-- right edge, dropped down the side. Taken from a placement verified in-game
-- rather than guessed.
local DEFAULT_OFFSET_X = 4
local DEFAULT_OFFSET_Y = -440

local craftingFrame

local MIN_WIDTH = 240
local PADDING = 8
local LINE_HEIGHT = 14

local frame = CreateFrame("Frame", "MoxieTrackerFrame", UIParent, "BackdropTemplate")
frame:SetSize(MIN_WIDTH, 70)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetMovable(true)
frame:SetClampedToScreen(true)

local function GetOffset()
    -- Called from the file-scope ApplyAnchor() below, which runs before
    -- ADDON_LOADED has had a chance to initialize MoxieTrackerDB.
    local x = MoxieTrackerDB and MoxieTrackerDB.offsetX
    local y = MoxieTrackerDB and MoxieTrackerDB.offsetY
    if type(x) ~= "number" or type(y) ~= "number" then
        return DEFAULT_OFFSET_X, DEFAULT_OFFSET_Y
    end
    return x, y
end

-- Anchored to the crafting window so the panel tracks it when the user moves
-- or rescales that window. Falls back to the screen corner if the crafting UI
-- is not loaded yet, which only happens while pinned.
local function ApplyAnchor()
    local offsetX, offsetY = GetOffset()
    frame:ClearAllPoints()
    if craftingFrame then
        frame:SetPoint("TOPLEFT", craftingFrame, "TOPRIGHT", offsetX, offsetY)
    else
        frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 20, 20)
    end
end

-- After a free drag the frame is anchored to wherever it was dropped, so
-- convert that screen position back into an offset from the crafting window.
local function SaveOffsetFromAnchor()
    if not craftingFrame then
        return
    end

    local frameScale = frame:GetEffectiveScale()
    local anchorScale = craftingFrame:GetEffectiveScale()
    local left, top = frame:GetLeft(), frame:GetTop()
    local anchorRight, anchorTop = craftingFrame:GetRight(), craftingFrame:GetTop()
    if not left or not top or not anchorRight or not anchorTop then
        return
    end

    MoxieTrackerDB.offsetX = ((left * frameScale) - (anchorRight * anchorScale)) / frameScale
    MoxieTrackerDB.offsetY = ((top * frameScale) - (anchorTop * anchorScale)) / frameScale
end

frame:SetScript("OnDragStart", function(self)
    self:StartMoving()
end)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SaveOffsetFromAnchor()
    ApplyAnchor()
end)

ApplyAnchor()

frame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
})
frame:SetBackdropColor(0, 0, 0, 0.45)
frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.9)

frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
frame.title:SetText("Moxie Tracker")

frame.lines = {}

-- Each line is a Frame, not a FontString: only Frames support OnEnter/OnLeave.
local function EnsureLine(index)
    local line = frame.lines[index]
    if not line then
        line = CreateFrame("Frame", nil, frame)
        line:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -(24 + ((index - 1) * LINE_HEIGHT)))
        line:SetPoint("RIGHT", frame, "RIGHT", -PADDING, 0)
        line:SetHeight(LINE_HEIGHT)
        line:EnableMouse(true)
        line:RegisterForDrag("LeftButton")
        line:SetScript("OnDragStart", function()
            frame:StartMoving()
        end)
        line:SetScript("OnDragStop", function()
            frame:StopMovingOrSizing()
        end)

        line.text = line:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        line.text:SetAllPoints(line)
        line.text:SetJustifyH("LEFT")

        line:SetScript("OnEnter", function(self)
            if self.currencyID then
                GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
                GameTooltip:SetCurrencyByID(self.currencyID)
                GameTooltip:Show()
            elseif self.itemID then
                GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
                GameTooltip:SetItemByID(self.itemID)
                GameTooltip:Show()
            end
        end)
        line:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        frame.lines[index] = line
    end
    return line
end

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

-- GET_ITEM_INFO_RECEIVED fires for every item entering the client's cache, not
-- just ones this addon tracks, so redraws must be filtered down to these IDs.
local TRACKED_ITEM_ID_SET = {}
for _, item in ipairs(ns.TRACKED_ITEMS) do
    TRACKED_ITEM_ID_SET[item.itemID] = true
end

function ns.GetQuantityColor(entry)
    if entry.itemID then
        local itemRule = ns.ITEM_QUANTITY_COLOR[entry.itemID]
        return itemRule and itemRule(entry.quantity) or WHITE
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
        return entry.quantity >= 600 and GREEN or YELLOW
    end
    return WHITE
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
local function GetCurrencyIDForIndex(index)
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
        local hidden = IsHidden(key)
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
            Add(GetCurrencyIDForIndex(index), nil, info.name, info.quantity)
        end
    end

    table.sort(tracked, function(a, b)
        return a.name < b.name
    end)

    return tracked
end

local function UpdateDisplay()
    local tracked = ns.CollectTracked()

    for index = 1, #frame.lines do
        frame.lines[index]:Hide()
    end

    if #tracked == 0 then
        local fallback = EnsureLine(1)
        fallback.currencyID = nil
        fallback.itemID = nil
        -- Distinguish "nothing to show" from "you hid everything", which would
        -- otherwise look identical to the addon having broken.
        local everythingHidden = MoxieTrackerDB.hidden ~= nil and next(MoxieTrackerDB.hidden) ~= nil
        fallback.text:SetText(everythingHidden and "All rows hidden - /moxie options" or "No tracked currencies")
        fallback:Show()
        frame:SetSize(MIN_WIDTH, 56)
        return
    end

    -- Width is driven by the widest rendered row so long names such as
    -- "Artisan Leatherworker's Moxie" are not clipped. Colour escapes do not
    -- contribute to GetStringWidth, so this measures the visible text.
    local widest = 0
    for index, entry in ipairs(tracked) do
        local line = EnsureLine(index)
        line.currencyID = entry.currencyID
        line.itemID = entry.itemID
        line.text:SetText(string.format("%s: %s%d|r", entry.name, ns.GetQuantityColor(entry), entry.quantity))
        line:Show()
        widest = math.max(widest, line.text:GetStringWidth())
    end

    frame:SetWidth(math.max(MIN_WIDTH, math.ceil(widest) + (PADDING * 2)))
    frame:SetHeight(math.max(56, 40 + (#tracked * LINE_HEIGHT)))
end

frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
    GameTooltip:SetText("Artisan Moxie, Shard of Dundun, Unalloyed Abundance, Fused Vitality")
    GameTooltip:AddLine("Shows the current character's tracked amounts. /moxie options to choose rows.",
        0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end)
frame:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

-- Visibility is driven by the crafting window. `pinned` is an override so the
-- panel can be inspected without a profession open.
frame.craftOpen = false
frame.pinned = false

local function RefreshVisibility()
    if frame.craftOpen or frame.pinned then
        ApplyAnchor()
        UpdateDisplay()
        frame:Show()
    else
        frame:Hide()
    end
end

local function SetCraftOpen(isOpen)
    frame.craftOpen = isOpen
    RefreshVisibility()
end

-- Registering an event the client does not know about raises an error, which
-- would abort the rest of this file. Register optional events defensively.
local function SafeRegisterEvent(event)
    pcall(frame.RegisterEvent, frame, event)
end

SafeRegisterEvent("CURRENCY_DISPLAY_UPDATE")
SafeRegisterEvent("PLAYER_ENTERING_WORLD")
SafeRegisterEvent("PLAYER_LOGIN")
SafeRegisterEvent("CURRENCY_TRANSFER_LOG_UPDATE")
SafeRegisterEvent("TRADE_SKILL_SHOW")
SafeRegisterEvent("TRADE_SKILL_CLOSE")
SafeRegisterEvent("ADDON_LOADED")
-- Item rows are counted from the bags, so they move on bag changes rather than
-- on the currency events. GET_ITEM_INFO_RECEIVED redraws the row once the
-- client has cached the item and its real name replaces the fallback.
SafeRegisterEvent("BAG_UPDATE_DELAYED")
SafeRegisterEvent("GET_ITEM_INFO_RECEIVED")

-- Warm the item cache at load so the first draw has real names.
for _, item in ipairs(ns.TRACKED_ITEMS) do
    if C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(item.itemID)
    end
end

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            MoxieTrackerDB = MoxieTrackerDB or {}
        end
    elseif event == "PLAYER_LOGIN" then
        if not MoxieTrackerDB.suppressLoginMessage then
            print(string.format("|cff33ff99MoxieTracker|r %s loaded. Type /moxie for options.", GetVersion()))
        end
    elseif event == "TRADE_SKILL_SHOW" then
        SetCraftOpen(true)
    elseif event == "TRADE_SKILL_CLOSE" then
        SetCraftOpen(false)
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if TRACKED_ITEM_ID_SET[arg1] and self:IsShown() then
            UpdateDisplay()
        end
    elseif self:IsShown() then
        UpdateDisplay()
    end
end)

-- Blizzard_Professions is load-on-demand, so ProfessionsFrame does not exist
-- yet. Hooking OnShow/OnHide covers cases the TRADE_SKILL_* events miss, such
-- as the window being reopened on a tab that does not refire them.
local function HookCraftingFrame(globalName)
    local target = _G[globalName]
    if not target or target.moxieTrackerHooked then
        return
    end
    target.moxieTrackerHooked = true
    craftingFrame = target

    -- UIParent's default MEDIUM strata draws below the crafting window and the
    -- addon panes docked to it, so an overlapping panel would hide behind them.
    -- Match the crafting frame's strata and sit above it.
    frame:SetFrameStrata(target:GetFrameStrata())
    frame:SetFrameLevel(target:GetFrameLevel() + 10)

    target:HookScript("OnShow", function()
        SetCraftOpen(true)
    end)
    target:HookScript("OnHide", function()
        SetCraftOpen(false)
    end)
end

if EventUtil and EventUtil.ContinueOnAddOnLoaded then
    EventUtil.ContinueOnAddOnLoaded("Blizzard_Professions", function()
        HookCraftingFrame("ProfessionsFrame")
    end)
else
    frame:HookScript("OnEvent", function(_, event, loadedAddon)
        if event == "ADDON_LOADED" and loadedAddon == "Blizzard_Professions" then
            HookCraftingFrame("ProfessionsFrame")
        end
    end)
end

-- Options panel. The row list is rebuilt every time the panel is shown rather
-- than built once at load, because what is trackable changes: moxie rows exist
-- only for professions the character has, and the keyword fallback can turn up
-- a currency no ID table knows about.
local OPTIONS_ROW_HEIGHT = 26
local OPTIONS_LOGIN_ROW_Y = -72
local OPTIONS_FIRST_ROW_Y = OPTIONS_LOGIN_ROW_Y - OPTIONS_ROW_HEIGHT

local optionsPanel
local optionsCategory

local function EnsureOptionRow(index)
    local row = optionsPanel.rows[index]
    if not row then
        row = CreateFrame("CheckButton", "MoxieTrackerOption" .. index, optionsPanel, "UICheckButtonTemplate")
        row:SetSize(24, 24)
        row:SetPoint("TOPLEFT", optionsPanel, "TOPLEFT",
            16, OPTIONS_FIRST_ROW_Y - ((index - 1) * OPTIONS_ROW_HEIGHT))

        -- An explicit label rather than the template's own text region, whose
        -- name has moved between expansions.
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.label:SetPoint("LEFT", row, "RIGHT", 4, 0)

        row:SetScript("OnClick", function(self)
            SetHidden(self.entryKey, not self:GetChecked())
            if frame:IsShown() then
                UpdateDisplay()
            end
        end)

        optionsPanel.rows[index] = row
    end
    return row
end

local function RefreshOptions()
    optionsPanel.loginCheckbox:SetChecked(not MoxieTrackerDB.suppressLoginMessage)

    local tracked = ns.CollectTracked(true)

    for _, row in ipairs(optionsPanel.rows) do
        row:Hide()
    end

    for index, entry in ipairs(tracked) do
        local row = EnsureOptionRow(index)
        row.entryKey = entry.key
        row.label:SetText(entry.name)
        row:SetChecked(not entry.hidden)
        row:Show()
    end

    if #tracked == 0 then
        optionsPanel.empty:Show()
    else
        optionsPanel.empty:Hide()
    end
end

local function CreateOptionsPanel()
    local panel = CreateFrame("Frame", "MoxieTrackerOptionsPanel", UIParent)
    panel.name = "MoxieTracker"
    panel.rows = {}

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    title:SetText("MoxieTracker " .. GetVersion())

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("Uncheck a row to hide it from the tracker. Choices apply to the whole account.")

    local loginCheckbox = CreateFrame("CheckButton", "MoxieTrackerLoginMessageOption", panel, "UICheckButtonTemplate")
    loginCheckbox:SetSize(24, 24)
    loginCheckbox:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, OPTIONS_LOGIN_ROW_Y)
    loginCheckbox.label = loginCheckbox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    loginCheckbox.label:SetPoint("LEFT", loginCheckbox, "RIGHT", 4, 0)
    loginCheckbox.label:SetText("Show version message at login")
    loginCheckbox:SetScript("OnClick", function(self)
        MoxieTrackerDB.suppressLoginMessage = not self:GetChecked()
    end)
    panel.loginCheckbox = loginCheckbox

    panel.empty = panel:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    panel.empty:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, OPTIONS_FIRST_ROW_Y)
    panel.empty:SetText("Nothing to configure yet - open a profession or log in on a character with moxie.")
    panel.empty:Hide()

    -- Hidden until the Settings frame shows it. Also makes OnShow the single
    -- point where rows are built, rather than it having to run once here too.
    panel:Hide()
    panel:SetScript("OnShow", RefreshOptions)

    optionsPanel = panel
end

CreateOptionsPanel()

if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    optionsCategory = Settings.RegisterCanvasLayoutCategory(optionsPanel, "MoxieTracker")
    Settings.RegisterAddOnCategory(optionsCategory)
end

local function OpenOptions()
    if optionsCategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(optionsCategory:GetID())
        return true
    end
    return false
end

SLASH_MOXIETRACKER1 = "/moxie"
-- /moxie is short enough to be contested by another addon; SlashCmdList
-- registration is last-writer-wins, so this full-length fallback is never lost.
SLASH_MOXIETRACKER2 = "/moxietracker"
SlashCmdList["MOXIETRACKER"] = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")

    if msg == "debug" then
        local offsetX, offsetY = GetOffset()
        print(string.format("|cff33ff99MoxieTracker|r: anchor offset %.1f, %.1f (%s); crafting frame %s",
            offsetX, offsetY,
            (type(MoxieTrackerDB.offsetY) == "number") and "user placed" or "default",
            craftingFrame and "found" or "not loaded"))

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
                IsHidden(ns.EntryKey(nil, item.itemID)) and " |cffff3333(hidden)|r" or ""))
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
                        index, tostring(info.name), info.quantity, tostring(GetCurrencyIDForIndex(index))))
                end
            end
        end
        return
    end

    if msg == "reset" then
        MoxieTrackerDB.offsetX = nil
        MoxieTrackerDB.offsetY = nil
        ApplyAnchor()
        RefreshVisibility()
        print("|cff33ff99MoxieTracker|r: position reset to the crafting window's top-right corner.")
        return
    end

    if msg == "options" or msg == "config" then
        if not OpenOptions() then
            print("|cff33ff99MoxieTracker|r: this client has no Settings panel; open Options > AddOns manually.")
        end
        return
    end

    if msg == "showall" then
        MoxieTrackerDB.hidden = nil
        if optionsPanel:IsShown() then
            RefreshOptions()
        end
        RefreshVisibility()
        print("|cff33ff99MoxieTracker|r: every row is visible again.")
        return
    end

    if msg == "pin" then
        frame.pinned = not frame.pinned
        RefreshVisibility()
        print(string.format("|cff33ff99MoxieTracker|r: pinned %s.",
            frame.pinned and "on - panel stays visible" or "off - panel follows the crafting window"))
        return
    end

    print("|cff33ff99MoxieTracker|r: shows automatically with the crafting window.")
    print("  /moxie options - choose which rows are shown")
    print("  /moxie showall - unhide every row")
    print("  /moxie pin - keep the panel visible regardless")
    print("  /moxie debug - list currencies")
    print("  /moxie reset - move the panel back to the crafting window's top-right")
end

RefreshVisibility()
