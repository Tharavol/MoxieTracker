-- The three tracker windows: creation, anchoring, dragging, rendering, visibility and events.
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
ns.frame = frame

-- Knowledge Points roster (#38) and Concentration roster (#40) windows.
local knowledgeFrame = CreateTrackerWindow("MoxieTrackerKnowledgeFrame")
ns.knowledgeFrame = knowledgeFrame

local concentrationFrame = CreateTrackerWindow("MoxieTrackerConcentrationFrame")
ns.concentrationFrame = concentrationFrame

-- Anchors used while a window has no stored offset (#40): Knowledge and
-- Concentration stack beneath the window above them until dragged.
local WINDOW_ANCHOR_FALLBACK = {
    main = function(window)
        window:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 20, 20)
    end,
    knowledge = function(window)
        window:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -KNOWLEDGE_WINDOW_GAP)
    end,
    concentration = function(window)
        window:SetPoint("TOPLEFT", knowledgeFrame, "BOTTOMLEFT", 0, -KNOWLEDGE_WINDOW_GAP)
    end,
}

local function ApplyWindowAnchor(window, windowKey)
    local offsetX, offsetY, side = ns.GetOffset(windowKey)
    window:ClearAllPoints()
    if offsetX and offsetY then
        if ns.craftingFrame then
            -- See ns.ComputeAnchorSide (#47).
            if side == "left" then
                window:SetPoint("TOPRIGHT", ns.craftingFrame, "TOPLEFT", offsetX, offsetY)
            else
                window:SetPoint("TOPLEFT", ns.craftingFrame, "TOPRIGHT", offsetX, offsetY)
            end
        else
            window:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 20, 20)
        end
    else
        WINDOW_ANCHOR_FALLBACK[windowKey](window)
    end
end

-- Always all three: moving one can change where an undragged window below it stacks.
function ns.ApplyAnchor()
    ApplyWindowAnchor(frame, "main")
    ApplyWindowAnchor(knowledgeFrame, "knowledge")
    ApplyWindowAnchor(concentrationFrame, "concentration")
end

-- The scale division below leaves remainders like 3.9999999999994 when scales differ.
local function RoundToPixel(value)
    return math.floor(value + 0.5)
end

-- Converts a dropped window's screen position into an offset from the crafting
-- frame. A "left"-docked window (#47) measures from its right edge to the frame's left.
local function SaveOffsetFromAnchor(window, windowKey)
    if not ns.craftingFrame then
        return
    end

    local windowScale = window:GetEffectiveScale()
    local anchorScale = ns.craftingFrame:GetEffectiveScale()
    local windowLeft, windowRight, top = window:GetLeft(), window:GetRight(), window:GetTop()
    local frameLeft, frameRight, anchorTop =
        ns.craftingFrame:GetLeft(), ns.craftingFrame:GetRight(), ns.craftingFrame:GetTop()
    if not windowLeft or not windowRight or not top or not frameLeft or not frameRight or not anchorTop then
        return
    end

    local side = ns.ComputeAnchorSide(windowLeft, windowRight, frameLeft, frameRight)
    local windowEdge = (side == "left") and windowRight or windowLeft
    local anchorEdge = (side == "left") and frameLeft or frameRight

    ns.SetOffset(windowKey,
        RoundToPixel(((windowEdge * windowScale) - (anchorEdge * anchorScale)) / windowScale),
        RoundToPixel(((top * windowScale) - (anchorTop * anchorScale)) / windowScale),
        side)
end

local function MakeWindowDraggable(window, windowKey)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetMovable(true)
    window.movable = true
    window.windowKey = windowKey
    window:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    window:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveOffsetFromAnchor(self, windowKey)
        ns.ApplyAnchor()
        ns.RefreshPositionField(windowKey)
    end)
end

MakeWindowDraggable(frame, "main")
MakeWindowDraggable(knowledgeFrame, "knowledge")
MakeWindowDraggable(concentrationFrame, "concentration")

ns.ApplyAnchor()

frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
frame.title:SetText("Moxie Tracker")

knowledgeFrame.title = knowledgeFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
knowledgeFrame.title:SetPoint("TOPLEFT", knowledgeFrame, "TOPLEFT", 8, -8)
knowledgeFrame.title:SetText("Knowledge Points")

concentrationFrame.title = concentrationFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
concentrationFrame.title:SetPoint("TOPLEFT", concentrationFrame, "TOPLEFT", 8, -8)
concentrationFrame.title:SetText("Concentration")

-- Each line is a Frame, not a FontString: only Frames support OnEnter/OnLeave.
local function EnsureLine(owner, index)
    local line = owner.lines[index]
    if not line then
        line = CreateFrame("Frame", nil, owner)
        line:SetPoint("TOPLEFT", owner, "TOPLEFT", PADDING, -(FIRST_LINE_Y + ((index - 1) * LINE_HEIGHT)))
        line:SetPoint("RIGHT", owner, "RIGHT", -PADDING, 0)
        line:SetHeight(LINE_HEIGHT)

        -- Rows cover most of a window, so they drag it too and must save the offset.
        if owner.movable then
            line:EnableMouse(true)
            line:RegisterForDrag("LeftButton")
            line:SetScript("OnDragStart", function()
                owner:StartMoving()
            end)
            line:SetScript("OnDragStop", function()
                owner:StopMovingOrSizing()
                SaveOffsetFromAnchor(owner, owner.windowKey)
                ns.ApplyAnchor()
                ns.RefreshPositionField(owner.windowKey)
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
            elseif self.questID then
                GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
                GameTooltip:SetHyperlink("quest:" .. self.questID)
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

    -- Width follows the widest row; colour escapes do not count toward GetStringWidth.
    local widest = 0
    local lineIndex = 0

    local function RenderLine(text, currencyID, itemID, questID)
        lineIndex = lineIndex + 1
        local line = EnsureLine(frame, lineIndex)
        line.currencyID = currencyID
        line.itemID = itemID
        line.questID = questID
        line.text:SetText(text)
        line:Show()
        widest = math.max(widest, line.text:GetStringWidth())
    end

    if #tracked == 0 then
        local everythingHidden = next(MoxieTrackerDB.hidden) ~= nil
        RenderLine(everythingHidden and "All rows hidden - /moxie options" or "No tracked currencies")
    else
        for _, entry in ipairs(tracked) do
            if entry.questID then
                local color, status = ns.GetQuestStatus(entry)
                RenderLine(string.format("%s: %s%s|r", entry.name, color, status), nil, nil, entry.questID)
            else
                RenderLine(string.format("%s: %s%d|r", entry.name, ns.GetQuantityColor(entry), entry.quantity),
                    entry.currencyID, entry.itemID)
            end
        end
    end

    frame:SetWidth(math.max(MIN_WIDTH, math.ceil(widest) + (PADDING * 2)))
    frame:SetHeight(math.max(EMPTY_HEIGHT, BASE_HEIGHT + (lineIndex * LINE_HEIGHT)))
end

-- Knowledge Points roster (#38). Characters with nothing unspent are left out, and
-- the window hides when nothing remains.
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
            -- Name, then one indented row per profession; a legacy entry with no
            -- breakdown gets a single "Name: total" line.
            if entry.professions then
                RenderLine(string.format("%s%s|r", ns.WHITE, entry.name))
                for _, profession in ipairs(entry.professions) do
                    -- Stored entries include professions at 0 (#42).
                    if profession.points > 0 then
                        RenderLine(string.format("%s%s%s|r: %s%d|r",
                            INDENT, ns.WHITE, profession.name, ns.GREEN, profession.points))
                    end
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

-- Concentration roster (#40), with a projected time to cap. Unlike Knowledge, a
-- profession at 0 still renders.
function ns.UpdateConcentrationDisplay()
    if MoxieTrackerDB.hideConcentrationWindow then
        concentrationFrame:Hide()
        return
    end

    local roster = ns.CollectConcentrationRoster()

    for index = 1, #concentrationFrame.lines do
        concentrationFrame.lines[index]:Hide()
    end

    local widest = 0
    local lineIndex = 0

    local function RenderLine(text)
        lineIndex = lineIndex + 1
        local line = EnsureLine(concentrationFrame, lineIndex)
        line.currencyID = nil
        line.itemID = nil
        line.text:SetText(text)
        line:Show()
        widest = math.max(widest, line.text:GetStringWidth())
    end

    local hideUnderThreshold = MoxieTrackerDB.hideConcentrationUnderThreshold

    for _, entry in ipairs(roster) do
        local headerShown = false
        for _, profession in ipairs(entry.professions) do
            if not hideUnderThreshold or not ns.IsConcentrationBelowThreshold(profession.name, profession.current) then
                if not headerShown then
                    RenderLine(string.format("%s%s|r", ns.WHITE, entry.name))
                    headerShown = true
                end
                local color = ns.GetConcentrationColor(profession.name, profession.current, profession.maxQuantity)
                RenderLine(string.format("%s%s%s|r: %s%d|r (%s)",
                    INDENT, ns.WHITE, profession.name,
                    color, profession.current,
                    ns.FormatDuration(profession.secondsUntilCap)))
            end
        end
    end

    if lineIndex == 0 then
        concentrationFrame:Hide()
        return
    end

    concentrationFrame:SetWidth(math.max(MIN_WIDTH, math.ceil(widest) + (PADDING * 2)))
    concentrationFrame:SetHeight(BASE_HEIGHT + (lineIndex * LINE_HEIGHT))
    concentrationFrame:Show()
end

frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
    GameTooltip:SetText("Artisan Moxie, Shard of Dundun, Unalloyed Abundance, Fused Vitality")
    GameTooltip:AddLine(
        "Shows the current character's tracked amounts. Unspent Knowledge and Concentration for every " ..
            "character that has logged in appear in their own windows below. /moxie options to choose rows.",
        0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end)
frame:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

-- Visibility follows the crafting window; `pinned` keeps it shown regardless.
frame.craftOpen = false
frame.pinned = false

-- Concentration ID discovery (#40) is retried on every redraw:
-- GetProfessionChildSkillLineID() is not always ready when the crafting window opens.
local function RefreshAllWindows()
    if ns.DiscoverConcentrationCurrencyID() then
        ns.SnapshotConcentration()
    end
    ns.UpdateDisplay()
    ns.UpdateKnowledgeDisplay()
    ns.UpdateConcentrationDisplay()
    ns.RefreshConcentrationTicker()
end

-- Default panels (Mail, Bags, Professions) are `toplevel` and re-raise their
-- FrameLevel on every click, so matching the crafting frame's level loses (#52).
-- The windows sit one FrameStrata above it instead, which always wins.
local STRATA_ORDER = {
    "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP",
}
local STRATA_INDEX = {}
for index, name in ipairs(STRATA_ORDER) do
    STRATA_INDEX[name] = index
end

local function StrataAbove(strata)
    local index = STRATA_INDEX[strata] or STRATA_INDEX.MEDIUM
    return STRATA_ORDER[math.min(index + 1, #STRATA_ORDER)]
end

local function SyncWindowLevels()
    if not ns.craftingFrame then
        return
    end
    local strata = StrataAbove(ns.craftingFrame:GetFrameStrata())
    local level = ns.craftingFrame:GetFrameLevel() + 10
    for _, window in ipairs({ frame, knowledgeFrame, concentrationFrame }) do
        window:SetFrameStrata(strata)
        window:SetFrameLevel(level)
    end
end

function ns.RefreshVisibility()
    if frame.craftOpen or frame.pinned then
        SyncWindowLevels()
        ns.ApplyAnchor()
        frame:Show()
        -- The roster windows show or hide themselves depending on content.
        RefreshAllWindows()
    else
        frame:Hide()
        knowledgeFrame:Hide()
        concentrationFrame:Hide()
        ns.RefreshConcentrationTicker()
    end
end

local function SetCraftOpen(isOpen)
    frame.craftOpen = isOpen
    ns.RefreshVisibility()
end

-- Per-window "Reset" button on the options panel.
function ns.ResetWindowPosition(windowKey)
    ns.ClearOffset(windowKey)
    ns.ApplyAnchor()
    ns.RefreshVisibility()
end

-- /moxie reset position.
function ns.ResetPosition()
    ns.ClearOffset("main")
    ns.ClearOffset("knowledge")
    ns.ClearOffset("concentration")
    ns.ApplyAnchor()
    ns.RefreshVisibility()
end

local concentrationTicker

-- Concentration regenerates with no event (#40), so the window redraws once a
-- minute while it is shown.
function ns.RefreshConcentrationTicker()
    if concentrationTicker then
        concentrationTicker:Cancel()
        concentrationTicker = nil
    end
    if not concentrationFrame:IsShown() then
        return
    end
    concentrationTicker = C_Timer.NewTicker(60, function()
        if concentrationFrame:IsShown() then
            ns.UpdateConcentrationDisplay()
        end
    end)
end

frame:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("CURRENCY_TRANSFER_LOG_UPDATE")
frame:RegisterEvent("TRADE_SKILL_SHOW")
frame:RegisterEvent("TRADE_SKILL_CLOSE")
frame:RegisterEvent("ADDON_LOADED")
-- Item counts change on bag updates, not currency events; GET_ITEM_INFO_RECEIVED
-- replaces the fallback name once the item is cached.
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
-- Quest rows (#53): IsQuestFlaggedCompleted already reads true when QUEST_TURNED_IN
-- fires; QUEST_DATA_LOAD_RESULT replaces the fallback title.
frame:RegisterEvent("QUEST_TURNED_IN")
frame:RegisterEvent("QUEST_DATA_LOAD_RESULT")

-- Warm the item and quest caches so the first draw has real names.
for _, item in ipairs(ns.TRACKED_ITEMS) do
    C_Item.RequestLoadItemDataByID(item.itemID)
end
for _, quest in ipairs(ns.TRACKED_QUESTS) do
    C_QuestLog.RequestLoadQuestByID(quest.questID)
end

-- Any other registered event (the currency events) redraws all three windows.
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            ns.InitSavedVariables()
            ns.MigrateWindowOffset()
        end
    elseif event == "PLAYER_LOGIN" then
        if not MoxieTrackerDB.suppressLoginMessage then
            ns.Print("%s loaded. Type /moxie for options.", ns.GetVersion())
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Unconditional: the profession API is dark by PLAYER_LOGOUT (see ns.IsProfessionLearned).
        ns.WarmLearnedProfessionsCache()
        if self:IsShown() then
            RefreshAllWindows()
        end
    elseif event == "PLAYER_LOGOUT" then
        -- Roster snapshots (#38, #40). Not at PLAYER_ENTERING_WORLD: currency data may
        -- not be synced yet then and could persist a spurious 0.
        ns.SnapshotKnowledge()
        ns.SnapshotConcentration()
    elseif event == "TRADE_SKILL_SHOW" then
        SetCraftOpen(true)
    elseif event == "TRADE_SKILL_CLOSE" then
        SetCraftOpen(false)
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if ns.TRACKED_ITEM_ID_SET[arg1] and self:IsShown() then
            ns.UpdateDisplay()
        end
    elseif event == "QUEST_TURNED_IN" or event == "QUEST_DATA_LOAD_RESULT" then
        if ns.TRACKED_QUEST_ID_SET[arg1] and self:IsShown() then
            ns.UpdateDisplay()
        end
    elseif self:IsShown() then
        RefreshAllWindows()
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

    -- RefreshVisibility resyncs on every show; this covers the time until then.
    SyncWindowLevels()

    target:HookScript("OnShow", function()
        SetCraftOpen(true)
    end)
    target:HookScript("OnHide", function()
        SetCraftOpen(false)
    end)
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_Professions", function()
    HookCraftingFrame("ProfessionsFrame")
end)

ns.RefreshVisibility()
