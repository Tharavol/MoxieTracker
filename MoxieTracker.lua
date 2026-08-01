--[[
MoxieTracker - displays Artisan Moxie, Shard of Dundun, and Unalloyed Abundance
alongside the World of Warcraft crafting window.

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

local addonName, addon = ...

-- Matched against currency names and descriptions. Keyword matching is used for
-- moxie because it is per-profession ("Artisan Alchemist's Moxie" and friends),
-- so a keyword picks up every variant without one ID per profession.
local KEYWORDS = {
    "moxie",
    "dundun",
}

-- Always queried directly by ID. A currency the character has not discovered
-- does not appear in the currency list at all, so keyword matching alone would
-- never find it.
local TRACKED_IDS = {
    3376, -- Shard of Dundun
    3377, -- Unalloyed Abundance
}

local GREEN = "|cff33ff33"
local YELLOW = "|cffffd200"
local RED = "|cffff3333"
local WHITE = "|cffffffff"

-- Quantity coloring, keyed by currency ID. Moxie is deliberately absent: its
-- ID varies per profession, so it is handled by name in GetQuantityColor.
local QUANTITY_COLOR = {
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

MoxieTrackerDB = MoxieTrackerDB or {}

-- Offset from the crafting window's TOPRIGHT corner. The panel hangs off the
-- right edge, dropped down the side to clear the upper portion of the crafting
-- frame. Taken from a placement verified in-game rather than guessed.
local DEFAULT_OFFSET_X = 4
local DEFAULT_OFFSET_Y = -440

local craftingFrame

local frame = CreateFrame("Frame", "MoxieTrackerFrame", UIParent, "BackdropTemplate")
frame:SetSize(240, 70)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetMovable(true)
frame:SetClampedToScreen(true)

local function GetOffset()
    local x = MoxieTrackerDB.offsetX
    local y = MoxieTrackerDB.offsetY
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
        line:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -(24 + ((index - 1) * 14)))
        line:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
        line:SetHeight(14)
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
    for _, keyword in ipairs(KEYWORDS) do
        if text:find(keyword, 1, true) then
            return true
        end
    end
    return false
end

local function GetQuantityColor(entry)
    local rule = entry.currencyID and QUANTITY_COLOR[entry.currencyID]
    if rule then
        return rule(entry.quantity)
    end
    if entry.name and entry.name:lower():find("moxie", 1, true) then
        return entry.quantity >= 600 and GREEN or YELLOW
    end
    return WHITE
end

local function IsTrackedCurrency(info)
    if not info or info.isHeader or not info.quantity or info.quantity <= 0 then
        return false
    end
    return MatchesKeyword(info.name) or MatchesKeyword(info.description)
end

-- GetCurrencyListInfo does not return the currency ID; it has to come from the link.
local function GetCurrencyIDForIndex(index)
    local link = C_CurrencyInfo.GetCurrencyListLink(index)
    if link then
        return C_CurrencyInfo.GetCurrencyIDFromLink(link)
    end
end

local function CollectTracked()
    local tracked = {}
    local seen = {}
    local size = C_CurrencyInfo.GetCurrencyListSize and C_CurrencyInfo.GetCurrencyListSize() or 0

    -- Pass 1: keyword scan of the currency list. This is what picks up the
    -- per-profession moxie currencies without hardcoding one ID per profession.
    for index = 1, size do
        local info = C_CurrencyInfo.GetCurrencyListInfo(index)
        if IsTrackedCurrency(info) then
            local currencyID = GetCurrencyIDForIndex(index)
            if currencyID then
                seen[currencyID] = true
            end
            table.insert(tracked, {
                name = info.name or "Currency",
                quantity = info.quantity or 0,
                currencyID = currencyID,
            })
        end
    end

    -- Pass 2: explicit IDs. Undiscovered currencies are absent from the list
    -- entirely, so pass 1 cannot see them at any quantity. These are shown even
    -- at zero so the row does not silently vanish.
    for _, currencyID in ipairs(TRACKED_IDS) do
        if not seen[currencyID] then
            local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
            if info and info.name then
                table.insert(tracked, {
                    name = info.name,
                    quantity = info.quantity or 0,
                    currencyID = currencyID,
                })
            end
        end
    end

    table.sort(tracked, function(a, b)
        return a.name < b.name
    end)

    return tracked
end

local function UpdateDisplay()
    local tracked = CollectTracked()

    for index = 1, #frame.lines do
        frame.lines[index]:Hide()
    end

    if #tracked == 0 then
        local fallback = EnsureLine(1)
        fallback.currencyID = nil
        fallback.text:SetText("No tracked currencies")
        fallback:Show()
        frame:SetHeight(56)
        return
    end

    for index, entry in ipairs(tracked) do
        local line = EnsureLine(index)
        line.currencyID = entry.currencyID
        line.text:SetText(string.format("%s: %s%d|r", entry.name, GetQuantityColor(entry), entry.quantity))
        line:Show()
    end

    frame:SetHeight(math.max(56, 40 + (#tracked * 14)))
end

frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
    GameTooltip:SetText("Artisan Moxie, Shard of Dundun, and Unalloyed Abundance")
    GameTooltip:AddLine("Shows the current character's tracked currency amounts.", 0.7, 0.7, 0.7, true)
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

frame:SetScript("OnEvent", function(self, event)
    if event == "TRADE_SKILL_SHOW" then
        SetCraftOpen(true)
    elseif event == "TRADE_SKILL_CLOSE" then
        SetCraftOpen(false)
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
    SafeRegisterEvent("ADDON_LOADED")
    frame:HookScript("OnEvent", function(_, event, loadedAddon)
        if event == "ADDON_LOADED" and loadedAddon == "Blizzard_Professions" then
            HookCraftingFrame("ProfessionsFrame")
        end
    end)
end

SLASH_MOXIETRACKER1 = "/moxie"
SlashCmdList["MOXIETRACKER"] = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")

    if msg == "debug" then
        local offsetX, offsetY = GetOffset()
        print(string.format("|cff33ff99MoxieTracker|r: anchor offset %.1f, %.1f (%s); crafting frame %s",
            offsetX, offsetY,
            (type(MoxieTrackerDB.offsetY) == "number") and "user placed" or "default",
            craftingFrame and "found" or "not loaded"))

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

    if msg == "pin" then
        frame.pinned = not frame.pinned
        RefreshVisibility()
        print(string.format("|cff33ff99MoxieTracker|r: pinned %s.",
            frame.pinned and "on - panel stays visible" or "off - panel follows the crafting window"))
        return
    end

    print("|cff33ff99MoxieTracker|r: shows automatically with the crafting window.")
    print("  /moxie pin - keep the panel visible regardless")
    print("  /moxie debug - list currencies")
    print("  /moxie reset - move the panel back to the crafting window's top-right")
end

RefreshVisibility()
