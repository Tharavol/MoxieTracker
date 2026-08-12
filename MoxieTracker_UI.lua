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
local INDENT = "    " -- one profession row under a multi-profession character name
local KNOWLEDGE_WINDOW_GAP = 6 -- vertical gap between the two windows

-- Shared shell for both windows: same backdrop, same starting size, same
-- line-pool table. Movement and dragging are wired separately below, since
-- only the main window is user-draggable -- the Knowledge Points window
-- stays anchored beneath it instead.
local function CreateTrackerWindow(globalName)
    local window = CreateFrame("Frame", globalName, UIParent, "BackdropTemplate")
    window:SetSize(MIN_WIDTH, DEFAULT_HEIGHT)
    window:SetClampedToScreen(true)
    window:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    window:SetBackdropColor(0, 0, 0, 0.45)
    window:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.9)
    window.lines = {}
    return window
end

local frame = CreateTrackerWindow("MoxieTrackerFrame")
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetMovable(true)
frame.movable = true
-- Never reassigned after this, so ns.frame and the local above always share
-- the same table; other files reach it through ns, this file keeps using the
-- shorter local name throughout.
ns.frame = frame

-- The Knowledge Points roster (#38) lives in its own window below the main
-- one rather than as a section within it, so a long roster does not push the
-- currency rows around. Anchored to `frame`'s bottom edge -- a live SetPoint
-- relationship, not a one-time copy -- so it tracks both drags and the main
-- window's own height changes with no extra code here.
local knowledgeFrame = CreateTrackerWindow("MoxieTrackerKnowledgeFrame")
knowledgeFrame:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -KNOWLEDGE_WINDOW_GAP)
ns.knowledgeFrame = knowledgeFrame

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

frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
frame.title:SetText("Moxie Tracker")

knowledgeFrame.title = knowledgeFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
knowledgeFrame.title:SetPoint("TOPLEFT", knowledgeFrame, "TOPLEFT", 8, -8)
knowledgeFrame.title:SetText("Knowledge Points")

-- Each line is a Frame, not a FontString: only Frames support OnEnter/OnLeave.
-- Shared by both windows; `owner` is whichever one the line belongs to, so a
-- line always resizes/hovers/drags its own window rather than always
-- reaching for the module-level `frame`.
local function EnsureLine(owner, index)
    local line = owner.lines[index]
    if not line then
        line = CreateFrame("Frame", nil, owner)
        line:SetPoint("TOPLEFT", owner, "TOPLEFT", PADDING, -(FIRST_LINE_Y + ((index - 1) * LINE_HEIGHT)))
        line:SetPoint("RIGHT", owner, "RIGHT", -PADDING, 0)
        line:SetHeight(LINE_HEIGHT)

        -- Only the main window drags via its rows; the Knowledge Points
        -- window isn't independently movable, so wiring drag scripts onto
        -- its lines would have nothing to do.
        if owner.movable then
            line:EnableMouse(true)
            line:RegisterForDrag("LeftButton")
            line:SetScript("OnDragStart", function()
                owner:StartMoving()
            end)
            line:SetScript("OnDragStop", function()
                owner:StopMovingOrSizing()
            end)
        end

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

        owner.lines[index] = line
    end
    return line
end

function ns.UpdateDisplay()
    local tracked = ns.CollectTracked()

    for index = 1, #frame.lines do
        frame.lines[index]:Hide()
    end

    -- Width is driven by the widest rendered row so long names such as
    -- "Artisan Leatherworker's Moxie" are not clipped. Colour escapes do not
    -- contribute to GetStringWidth, so this measures the visible text.
    local widest = 0
    local lineIndex = 0

    local function RenderLine(text, currencyID, itemID)
        lineIndex = lineIndex + 1
        local line = EnsureLine(frame, lineIndex)
        line.currencyID = currencyID
        line.itemID = itemID
        line.text:SetText(text)
        line:Show()
        widest = math.max(widest, line.text:GetStringWidth())
    end

    if #tracked == 0 then
        -- Distinguish "nothing to show" from "you hid everything", which would
        -- otherwise look identical to the addon having broken.
        local everythingHidden = MoxieTrackerDB.hidden ~= nil and next(MoxieTrackerDB.hidden) ~= nil
        RenderLine(everythingHidden and "All rows hidden - /moxie options" or "No tracked currencies")
    else
        for _, entry in ipairs(tracked) do
            RenderLine(string.format("%s: %s%d|r", entry.name, ns.GetQuantityColor(entry), entry.quantity),
                entry.currencyID, entry.itemID)
        end
    end

    frame:SetWidth(math.max(MIN_WIDTH, math.ceil(widest) + (PADDING * 2)))
    frame:SetHeight(math.max(EMPTY_HEIGHT, BASE_HEIGHT + (lineIndex * LINE_HEIGHT)))
end

-- Knowledge Points roster (#38), in its own window (see knowledgeFrame above)
-- rather than a section of the main one. Grows as more alts log in; muted
-- characters (options panel) never appear here. A character with nothing
-- unspent is dropped entirely rather than shown at 0, and the whole window
-- hides itself when that leaves nothing to show, the same "distinguish
-- nothing-to-show from broken" concern as the main window, just resolved by
-- hiding rather than a fallback line since there's no user action (like
-- unhiding a row) that would fix an empty roster. MoxieTrackerDB.hideKnowledgeWindow
-- is a separate, blunter off switch (options panel) for hiding the whole
-- window regardless of content.
function ns.UpdateKnowledgeDisplay()
    if MoxieTrackerDB.hideKnowledgeWindow then
        knowledgeFrame:Hide()
        return
    end

    local roster = ns.CollectKnowledgeRoster()

    for index = 1, #knowledgeFrame.lines do
        knowledgeFrame.lines[index]:Hide()
    end

    local widest = 0
    local lineIndex = 0

    local function RenderLine(text)
        lineIndex = lineIndex + 1
        local line = EnsureLine(knowledgeFrame, lineIndex)
        line.currencyID = nil
        line.itemID = nil
        line.text:SetText(text)
        line:Show()
        widest = math.max(widest, line.text:GetStringWidth())
    end

    for _, entry in ipairs(roster) do
        if entry.points > 0 then
            -- Name on its own line, then one indented row per profession
            -- with unspent points -- always broken out this way, even for a
            -- character with only one, so the count is never ambiguous
            -- between "N total" and "N in this profession". Only a
            -- pre-breakdown legacy entry (see ns.CollectKnowledgeRoster)
            -- falls back to a plain "Name: total" line, since it has no
            -- breakdown to show.
            if entry.professions then
                RenderLine(string.format("%s%s|r", ns.WHITE, entry.name))
                for _, profession in ipairs(entry.professions) do
                    RenderLine(string.format("%s%s%s|r: %s%d|r",
                        INDENT, ns.WHITE, profession.name, ns.GREEN, profession.points))
                end
            else
                RenderLine(string.format("%s%s|r: %s%d|r", ns.WHITE, entry.name, ns.GREEN, entry.points))
            end
        end
    end

    if lineIndex == 0 then
        knowledgeFrame:Hide()
        return
    end

    knowledgeFrame:SetWidth(math.max(MIN_WIDTH, math.ceil(widest) + (PADDING * 2)))
    knowledgeFrame:SetHeight(BASE_HEIGHT + (lineIndex * LINE_HEIGHT))
    knowledgeFrame:Show()
end

frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
    GameTooltip:SetText("Artisan Moxie, Shard of Dundun, Unalloyed Abundance, Fused Vitality")
    GameTooltip:AddLine(
        "Shows the current character's tracked amounts. Unspent Knowledge for every character that " ..
            "has logged in appears in a second window below. /moxie options to choose rows.",
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
        -- Shows or hides itself based on whether there's anything to display;
        -- see ns.UpdateKnowledgeDisplay.
        ns.UpdateKnowledgeDisplay()
    else
        frame:Hide()
        knowledgeFrame:Hide()
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

-- Currency events (CURRENCY_DISPLAY_UPDATE etc.) cover both the tracked
-- currencies and the Knowledge currencies, so any handler below that reacts
-- to one refreshes both windows rather than risking one going stale.
local function RefreshBothWindows()
    ns.UpdateDisplay()
    ns.UpdateKnowledgeDisplay()
end

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            MoxieTrackerDB = MoxieTrackerDB or {}
        end
    elseif event == "PLAYER_LOGIN" then
        if not MoxieTrackerDB.suppressLoginMessage then
            ns.Print("%s loaded. Type /moxie for options.", ns.GetVersion())
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- The whole "accumulation" mechanism (#38): each login snapshots this
        -- character's unspent Knowledge into the account-wide roster.
        ns.SnapshotKnowledge()
        if self:IsShown() then
            RefreshBothWindows()
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
        RefreshBothWindows()
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
    -- Match the crafting frame's strata and sit above it. Both windows get
    -- the same treatment so the Knowledge Points window doesn't end up
    -- behind the crafting frame while the main window sits above it.
    frame:SetFrameStrata(target:GetFrameStrata())
    frame:SetFrameLevel(target:GetFrameLevel() + 10)
    knowledgeFrame:SetFrameStrata(target:GetFrameStrata())
    knowledgeFrame:SetFrameLevel(target:GetFrameLevel() + 10)

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
