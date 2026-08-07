-- Depends on MoxieTracker_Config.lua and MoxieTracker_Collect.lua, loaded
-- first per the TOC. Owns the tracker frame: creation, anchoring, dragging,
-- rendering, visibility, and the events that drive all of it.
local ADDON_NAME, ns = ...

local MIN_WIDTH = 240
local PADDING = 8
local LINE_HEIGHT = 14
local FIRST_LINE_Y = 24 -- top offset of the first currency/item row, below the title
local BASE_HEIGHT = 40 -- header + padding above the rows, before LINE_HEIGHT * row count
local EMPTY_HEIGHT = 56 -- height while showing the single "nothing tracked" fallback line
local DEFAULT_HEIGHT = 70 -- placeholder until the first UpdateDisplay call resizes the frame

local frame = CreateFrame("Frame", "MoxieTrackerFrame", UIParent, "BackdropTemplate")
frame:SetSize(MIN_WIDTH, DEFAULT_HEIGHT)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetMovable(true)
frame:SetClampedToScreen(true)
-- Never reassigned after this, so ns.frame and the local above always share
-- the same table; other files reach it through ns, this file keeps using the
-- shorter local name throughout.
ns.frame = frame

-- Anchored to the crafting window so the panel tracks it when the user moves
-- or rescales that window. Falls back to the screen corner if the crafting UI
-- is not loaded yet, which only happens while pinned.
function ns.ApplyAnchor()
    local offsetX, offsetY = ns.GetOffset()
    frame:ClearAllPoints()
    if ns.craftingFrame then
        frame:SetPoint("TOPLEFT", ns.craftingFrame, "TOPRIGHT", offsetX, offsetY)
    else
        frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 20, 20)
    end
end

-- The scale division in SaveOffsetFromAnchor below is exact only when
-- frameScale and anchorScale match, and otherwise leaves a trailing remainder
-- like 3.9999999999994 that would show up verbatim in the options panel's
-- offset fields and /moxie debug. A local helper rather than the WoW global
-- Round(), so this stays a plain math operation the same in-game and in tests.
local function RoundToPixel(value)
    return math.floor(value + 0.5)
end

-- After a free drag the frame is anchored to wherever it was dropped, so
-- convert that screen position back into an offset from the crafting window.
local function SaveOffsetFromAnchor()
    if not ns.craftingFrame then
        return
    end

    local frameScale = frame:GetEffectiveScale()
    local anchorScale = ns.craftingFrame:GetEffectiveScale()
    local left, top = frame:GetLeft(), frame:GetTop()
    local anchorRight, anchorTop = ns.craftingFrame:GetRight(), ns.craftingFrame:GetTop()
    if not left or not top or not anchorRight or not anchorTop then
        return
    end

    MoxieTrackerDB.offsetX = RoundToPixel(((left * frameScale) - (anchorRight * anchorScale)) / frameScale)
    MoxieTrackerDB.offsetY = RoundToPixel(((top * frameScale) - (anchorTop * anchorScale)) / frameScale)
end

frame:SetScript("OnDragStart", function(self)
    self:StartMoving()
end)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SaveOffsetFromAnchor()
    ns.ApplyAnchor()
end)

ns.ApplyAnchor()

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
        line:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -(FIRST_LINE_Y + ((index - 1) * LINE_HEIGHT)))
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

function ns.UpdateDisplay()
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
        frame:SetSize(MIN_WIDTH, EMPTY_HEIGHT)
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
    frame:SetHeight(math.max(EMPTY_HEIGHT, BASE_HEIGHT + (#tracked * LINE_HEIGHT)))
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

function ns.RefreshVisibility()
    if frame.craftOpen or frame.pinned then
        ns.ApplyAnchor()
        ns.UpdateDisplay()
        frame:Show()
    else
        frame:Hide()
    end
end

local function SetCraftOpen(isOpen)
    frame.craftOpen = isOpen
    ns.RefreshVisibility()
end

-- Shared by /moxie reset and the options panel's "Reset position" button, so
-- the two never drift apart.
function ns.ResetPosition()
    MoxieTrackerDB.offsetX = nil
    MoxieTrackerDB.offsetY = nil
    ns.ApplyAnchor()
    ns.RefreshVisibility()
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
            print(string.format("|cff33ff99MoxieTracker|r %s loaded. Type /moxie for options.", ns.GetVersion()))
        end
    elseif event == "TRADE_SKILL_SHOW" then
        SetCraftOpen(true)
    elseif event == "TRADE_SKILL_CLOSE" then
        SetCraftOpen(false)
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if ns.TRACKED_ITEM_ID_SET[arg1] and self:IsShown() then
            ns.UpdateDisplay()
        end
    elseif self:IsShown() then
        ns.UpdateDisplay()
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
    ns.craftingFrame = target

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

ns.RefreshVisibility()
