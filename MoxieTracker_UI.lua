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
-- Never reassigned after this, so ns.frame and the local above always share
-- the same table; other files reach it through ns, this file keeps using the
-- shorter local name throughout.
ns.frame = frame

-- The Knowledge Points roster (#38) lives in its own window below the main
-- one rather than as a section within it, so a long roster does not push the
-- currency rows around.
local knowledgeFrame = CreateTrackerWindow("MoxieTrackerKnowledgeFrame")
ns.knowledgeFrame = knowledgeFrame

-- Concentration roster (#40), a third window below Knowledge Points.
local concentrationFrame = CreateTrackerWindow("MoxieTrackerConcentrationFrame")
ns.concentrationFrame = concentrationFrame

-- Each window is independently draggable and stores its own position (#40 --
-- previously only `frame` was movable; Knowledge Points just rode along
-- beneath it via a fixed SetPoint). All three anchor the same way: relative
-- to the crafting frame's corner once dragged (ns.GetOffset(windowKey)
-- returns a stored or default numeric offset), falling back to a live
-- SetPoint against whatever `fallback` describes when nothing has been
-- stored yet -- for Knowledge and Concentration that fallback is "beneath
-- the window above me", which is what today's fixed stacking looked like
-- before any of this existed, and keeps tracking that window's height
-- automatically until the user actually drags it loose.
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
            -- "left" (#47) tracks the crafting frame's TOPLEFT instead of
            -- its TOPRIGHT, so a window resting to the frame's left holds a
            -- constant gap regardless of how wide the frame gets on its
            -- right/interior side -- ProfessionsFrame visibly resizes
            -- across its own tabs (Specializations is wider than
            -- Recipes/Crafting Orders), which a TOPRIGHT-only anchor has no
            -- way to account for on that side.
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

-- Re-anchors all three windows. Always all three, not just the one that
-- moved: dragging Knowledge, for instance, can change where an
-- undragged Concentration should stack beneath it.
function ns.ApplyAnchor()
    ApplyWindowAnchor(frame, "main")
    ApplyWindowAnchor(knowledgeFrame, "knowledge")
    ApplyWindowAnchor(concentrationFrame, "concentration")
end

-- The scale division in SaveOffsetFromAnchor below is exact only when
-- frameScale and anchorScale match, and otherwise leaves a trailing remainder
-- like 3.9999999999994 that would show up verbatim in the options panel's
-- offset fields and /moxie debug. A local helper rather than the WoW global
-- Round(), so this stays a plain math operation the same in-game and in tests.
local function RoundToPixel(value)
    return math.floor(value + 0.5)
end

-- After a free drag `window` is anchored to wherever it was dropped, so
-- convert that screen position back into an offset from the crafting window
-- and store it under `windowKey`. Which of the window's/frame's edges feed
-- that conversion depends on ns.ComputeAnchorSide's verdict (#47): a
-- "left"-docked window's offset is measured from its own right edge to the
-- crafting frame's left edge (matching the TOPRIGHT->TOPLEFT anchor
-- ApplyWindowAnchor uses for that side), not its left edge to the frame's
-- right the way every offset was measured before "left" existed.
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
    -- EnsureLine's per-row drag handlers below need this to save/reapply
    -- too: dragging by a row (StartMoving on `owner`), not the window's own
    -- backdrop, is the only way to move Knowledge/Concentration in
    -- practice, since their rows cover almost the entire window.
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
-- Shared by all three windows; `owner` is whichever one the line belongs to,
-- so a line always resizes/hovers/drags its own window rather than always
-- reaching for the module-level `frame`.
local function EnsureLine(owner, index)
    local line = owner.lines[index]
    if not line then
        line = CreateFrame("Frame", nil, owner)
        line:SetPoint("TOPLEFT", owner, "TOPLEFT", PADDING, -(FIRST_LINE_Y + ((index - 1) * LINE_HEIGHT)))
        line:SetPoint("RIGHT", owner, "RIGHT", -PADDING, 0)
        line:SetHeight(LINE_HEIGHT)

        -- Every window is independently movable now (#40), so every
        -- window's rows drag it, same as the main window always has. A
        -- drag started on a row still has to save and reapply the offset
        -- on release the same way the window-level OnDragStop does
        -- (MakeWindowDraggable above) -- without this, a row-dragged
        -- window (in practice the only way to drag Knowledge/Concentration
        -- at all, since their rows cover almost the whole window) visually
        -- moves while held but snaps right back on the next redraw, because
        -- nothing was ever saved to MoxieTrackerDB.
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
                    -- A stored entry can now include a trained profession
                    -- sitting at 0 points (#42 follow-up: SnapshotKnowledge
                    -- persists every trained profession, not just ones with
                    -- unspent points, so the options panel can offer muting
                    -- one before it has earned anything). Filtered back out
                    -- here so the floating window's own "don't show what
                    -- isn't there" behavior is unchanged.
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

-- Concentration roster (#40), the same "own window below the previous one,
-- name in white with an indented per-profession breakdown in green"
-- treatment as Knowledge Points (ns.UpdateKnowledgeDisplay above), plus a
-- quantity/max reading and a projected time-to-cap per profession. Unlike
-- Knowledge, a profession at 0 still renders -- 0 Concentration is real
-- information here, not "nothing to report" -- so the only professions
-- left out are ones never discovered/muted (see
-- ns.CollectConcentrationRoster). MoxieTrackerDB.hideConcentrationWindow
-- mirrors hideKnowledgeWindow's blunt off switch.
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

-- Visibility is driven by the crafting window. `pinned` is an override so the
-- panel can be inspected without a profession open.
frame.craftOpen = false
frame.pinned = false

-- Concentration ID discovery (#40) plus a redraw of all three windows.
-- Discovery has to be attempted here -- the function nearly every relevant
-- event routes through while the window is open (currency changes,
-- PLAYER_ENTERING_WORLD, RefreshVisibility below) -- rather than only once
-- when the crafting window first opens: GetProfessionChildSkillLineID() is
-- not guaranteed ready the instant the window shows (the profession UI
-- populates its recipe list asynchronously), so a single attempt on open
-- could silently miss it for the rest of that session. Retrying here on
-- every redraw makes it self-healing instead: it just succeeds on the next
-- one. (A previous version only attempted discovery from RefreshVisibility,
-- which most gameplay events never call -- only /moxie reset position and
-- similar did, which is why the Concentration window only ever appeared
-- after using Reset.)
local function RefreshAllWindows()
    if ns.DiscoverConcentrationCurrencyID() then
        ns.SnapshotConcentration()
    end
    ns.UpdateDisplay()
    ns.UpdateKnowledgeDisplay()
    ns.UpdateConcentrationDisplay()
    ns.RefreshConcentrationTicker()
end

function ns.RefreshVisibility()
    if frame.craftOpen or frame.pinned then
        ns.ApplyAnchor()
        frame:Show()
        -- Both show or hide themselves based on whether there's anything to
        -- display; see ns.UpdateKnowledgeDisplay/ns.UpdateConcentrationDisplay.
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

-- Resets one window's stored position back to its default/fallback anchor.
-- Shared by the options panel's per-window "Reset position" buttons.
function ns.ResetWindowPosition(windowKey)
    ns.ClearOffset(windowKey)
    ns.ApplyAnchor()
    ns.RefreshVisibility()
end

-- Resets all three windows. Shared by /moxie reset position and (for
-- backward-compatible bulk reset) available to the options panel too.
function ns.ResetPosition()
    ns.ClearOffset("main")
    ns.ClearOffset("knowledge")
    ns.ClearOffset("concentration")
    ns.ApplyAnchor()
    ns.RefreshVisibility()
end

local concentrationTicker

-- The current character's Concentration keeps regenerating in real time,
-- unlike every other tracked value in this addon, which only changes on a
-- discrete game event -- nothing else needed a clock-driven refresh before
-- this (#40). Runs only while the Concentration window is actually shown,
-- so an idle session with the crafting window closed costs nothing. Guards
-- around C_Timer's existence the same defensive way SafeRegisterEvent does
-- below, since the headless test harness has no C_Timer to stub.
function ns.RefreshConcentrationTicker()
    if concentrationTicker then
        concentrationTicker:Cancel()
        concentrationTicker = nil
    end
    if not concentrationFrame:IsShown() or not C_Timer or not C_Timer.NewTicker then
        return
    end
    concentrationTicker = C_Timer.NewTicker(60, function()
        if concentrationFrame:IsShown() then
            ns.UpdateConcentrationDisplay()
        end
    end)
end

-- Registering an event the client does not know about raises an error, which
-- would abort the rest of this file. Register optional events defensively.
local function SafeRegisterEvent(event)
    pcall(frame.RegisterEvent, frame, event)
end

SafeRegisterEvent("CURRENCY_DISPLAY_UPDATE")
SafeRegisterEvent("PLAYER_ENTERING_WORLD")
SafeRegisterEvent("PLAYER_LOGIN")
SafeRegisterEvent("PLAYER_LOGOUT")
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

-- Currency events (CURRENCY_DISPLAY_UPDATE etc.) cover the tracked
-- currencies, the Knowledge currencies, and Concentration, so any handler
-- below that reacts to one refreshes all three windows (via
-- RefreshAllWindows, defined above ns.RefreshVisibility) rather than
-- risking one going stale.
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            MoxieTrackerDB = MoxieTrackerDB or {}
            -- One-time upgrade from the pre-#40 single-offset SavedVariables
            -- shape; a no-op once already migrated.
            ns.MigrateWindowOffset()
        end
    elseif event == "PLAYER_LOGIN" then
        if not MoxieTrackerDB.suppressLoginMessage then
            ns.Print("%s loaded. Type /moxie for options.", ns.GetVersion())
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Unconditional, unlike the tracker-window refresh below: warms
        -- ns.IsProfessionLearned's per-character cache while the profession
        -- API is confirmed live, regardless of whether any tracker window
        -- is currently shown (RefreshAllWindows, and every other caller of
        -- ns.IsProfessionLearned, only runs while one is). Confirmed
        -- empirically that the same API goes dark by PLAYER_LOGOUT -- see
        -- the comment above ns.IsProfessionLearned in the Collect file --
        -- so this is this session's only guaranteed chance to populate the
        -- cache before SnapshotConcentration needs it at logout.
        ns.WarmLearnedProfessionsCache()
        if self:IsShown() then
            RefreshAllWindows()
        end
    elseif event == "PLAYER_LOGOUT" then
        -- The whole "accumulation" mechanism (#38, extended to Concentration
        -- by #40): snapshot this character's unspent Knowledge and known
        -- Concentration into the account-wide rosters as it leaves, so an
        -- alt sees them next. Deliberately not PLAYER_ENTERING_WORLD: currency
        -- data isn't guaranteed synced from the server the instant that event
        -- fires (most notably right after login), and reading it that early
        -- could persist a spurious 0 that clobbers the real total until the
        -- next snapshot. By logout the session's currency data has settled,
        -- and logout always happens before another character could see the
        -- roster anyway.
        ns.SnapshotKnowledge()
        ns.SnapshotConcentration()
    elseif event == "TRADE_SKILL_SHOW" then
        -- Concentration ID discovery (#40) happens inside
        -- ns.RefreshVisibility, which SetCraftOpen(true) below triggers --
        -- see the comment there for why it lives there instead of only here.
        SetCraftOpen(true)
    elseif event == "TRADE_SKILL_CLOSE" then
        SetCraftOpen(false)
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if ns.TRACKED_ITEM_ID_SET[arg1] and self:IsShown() then
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

    -- UIParent's default MEDIUM strata draws below the crafting window and the
    -- addon panes docked to it, so an overlapping panel would hide behind them.
    -- Match the crafting frame's strata and sit above it. All three windows
    -- get the same treatment so neither Knowledge Points nor Concentration
    -- ends up behind the crafting frame while the main window sits above it.
    for _, window in ipairs({ frame, knowledgeFrame, concentrationFrame }) do
        window:SetFrameStrata(target:GetFrameStrata())
        window:SetFrameLevel(target:GetFrameLevel() + 10)
    end

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
