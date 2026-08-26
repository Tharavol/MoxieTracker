-- Depends on MoxieTracker_Config.lua, MoxieTracker_Collect.lua, and
-- MoxieTracker_UI.lua, loaded first per the TOC. The options panel, including
-- the Position and Color thresholds sections and the row-list scroll frame.
local _, ns = ...

-- Everything below the title/subtitle lives inside one scrolling content
-- frame (see CreateOptionsPanel's scrollFrame), merging what used to be two
-- separate small scroll boxes (the tracked-row list and the character-mute
-- list) plus the un-scrolled Position/Threshold sections above them. Those
-- fixed sections plus a growing roster of alts could add up to more than the
-- panel's real visible height, and since nothing wrapped the whole page, the
-- overflow used to just draw past the bottom of the window and over the
-- Close button instead of scrolling. A single scroll region covering
-- everything fixes that regardless of how many rows any of the lists below
-- end up with.
--
-- The scroll frame's own size is an explicit SetSize (see its creation
-- below), not anchored to the options panel's edges, because a canvas
-- settings category is not guaranteed to stretch the frame it's given to
-- fill the available area -- in-game `/run` previously confirmed
-- MoxieTrackerOptionsPanel:GetWidth() genuinely returns 0, i.e. the panel is
-- never actually resized to fill the canvas (see docs/HANDOFF.md). Anchoring
-- to it would collapse the scroll frame to nothing instead of filling the
-- page. OPTIONS_CONTENT_HEIGHT is picked to comfortably fit within the
-- canvas area the pre-existing two-box layout already rendered inside
-- without complaint; it hasn't been re-verified in-game since the merge, so
-- treat it as a starting point to confirm against the real client.
local OPTIONS_ROW_HEIGHT = 26
local OPTIONS_HEADER_HEIGHT = 20
local OPTIONS_SECTION_GAP = 6
local OPTIONS_CONTENT_WIDTH = 500
local OPTIONS_CONTENT_HEIGHT = 460
local OPTIONS_BOTTOM_MARGIN = 16

-- The three independently positioned tracker windows (#40), in the order
-- their compact Position rows render.
local WINDOWS = {
    { key = "main", label = "Main" },
    { key = "knowledge", label = "Knowledge" },
    { key = "concentration", label = "Concentration" },
}

local OPTIONS_LOGIN_ROW_Y = 0
local OPTIONS_KNOWLEDGE_WINDOW_ROW_Y = OPTIONS_LOGIN_ROW_Y - OPTIONS_ROW_HEIGHT
local OPTIONS_CONCENTRATION_WINDOW_ROW_Y = OPTIONS_KNOWLEDGE_WINDOW_ROW_Y - OPTIONS_ROW_HEIGHT

-- Position section: a header (sharing its row with the X/Y column labels)
-- plus one compact "Label [X] [Y] [Reset]" row per window (#40 -- previously
-- a header, two offset fields, and a single reset button for the one main
-- window only).
local OPTIONS_POSITION_HEADER_Y = OPTIONS_CONCENTRATION_WINDOW_ROW_Y - OPTIONS_ROW_HEIGHT
local OPTIONS_POSITION_MAIN_ROW_Y = OPTIONS_POSITION_HEADER_Y - OPTIONS_HEADER_HEIGHT
local OPTIONS_POSITION_KNOWLEDGE_ROW_Y = OPTIONS_POSITION_MAIN_ROW_Y - OPTIONS_ROW_HEIGHT
local OPTIONS_POSITION_CONCENTRATION_ROW_Y = OPTIONS_POSITION_KNOWLEDGE_ROW_Y - OPTIONS_ROW_HEIGHT

-- Threshold section: a header, the three base thresholds, one row per
-- Concentration profession (#40 -- all eleven thresholds share one section
-- and one reset button, rather than splitting Concentration into its own),
-- then the reset button. The Concentration rows' start is a constant since
-- ns.CONCENTRATION_PROFESSIONS is a fixed-length table known at load time;
-- CreateOptionsPanel still loops over it rather than naming eight more
-- per-profession constants.
local OPTIONS_THRESHOLD_HEADER_Y = OPTIONS_POSITION_CONCENTRATION_ROW_Y - OPTIONS_ROW_HEIGHT - OPTIONS_SECTION_GAP
local OPTIONS_THRESHOLD_UA_ROW_Y = OPTIONS_THRESHOLD_HEADER_Y - OPTIONS_HEADER_HEIGHT
local OPTIONS_THRESHOLD_MOXIE_ROW_Y = OPTIONS_THRESHOLD_UA_ROW_Y - OPTIONS_ROW_HEIGHT
local OPTIONS_THRESHOLD_FV_ROW_Y = OPTIONS_THRESHOLD_MOXIE_ROW_Y - OPTIONS_ROW_HEIGHT
local OPTIONS_THRESHOLD_CONCENTRATION_FIRST_Y = OPTIONS_THRESHOLD_FV_ROW_Y - OPTIONS_ROW_HEIGHT
local OPTIONS_THRESHOLD_RESET_Y = OPTIONS_THRESHOLD_CONCENTRATION_FIRST_Y
    - (#ns.CONCENTRATION_PROFESSIONS * OPTIONS_ROW_HEIGHT)

-- Everything from here down has a row count only known at refresh time (the
-- tracked-currency list and the four mute lists -- Knowledge's characters
-- and character-professions, then Concentration's own independent pair), so
-- their start positions are computed in RefreshOptions rather than as fixed
-- constants -- each section's header anchors to the bottom of whatever
-- rendered above it.
local OPTIONS_FIRST_ROW_Y = OPTIONS_THRESHOLD_RESET_Y - OPTIONS_ROW_HEIGHT - OPTIONS_SECTION_GAP

local optionsCategory

-- Builds a "Label:  [box]" row for a settings section. Callers wire up
-- validation and commit handlers per field, since signed offsets and
-- non-negative thresholds validate differently.
local function CreateSettingField(parent, y, labelText)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    label:SetText(labelText)

    local editBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    editBox:SetSize(60, 20)
    editBox:SetAutoFocus(false)
    editBox:SetPoint("LEFT", label, "RIGHT", 8, 0)

    return editBox
end

-- Shared shape for all five row lists below: a checkbox plus label, parented
-- to the shared scroll content and positioned explicitly by the caller (each
-- list's start Y depends on how tall the list above it turned out to be, so
-- position can't be baked in here the way a single fixed-origin list could).
local function EnsureListRow(pool, index, frameNamePrefix, onClick)
    local row = pool[index]
    if not row then
        row = CreateFrame("CheckButton", frameNamePrefix .. index, ns.optionsPanel.content, "UICheckButtonTemplate")
        row:SetSize(24, 24)
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.label:SetPoint("LEFT", row, "RIGHT", 4, 0)
        row:SetScript("OnClick", onClick)
        pool[index] = row
    end
    return row
end

local function PositionRow(row, y)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", ns.optionsPanel.content, "TOPLEFT", 0, y)
end

local function EnsureOptionRow(index)
    return EnsureListRow(ns.optionsPanel.rows, index, "MoxieTrackerOption", function(self)
        ns.SetHidden(self.entryKey, not self:GetChecked())
        if ns.frame:IsShown() then
            ns.UpdateDisplay()
        end
    end)
end

-- Same shape as EnsureOptionRow above, but for the character-mute list: a
-- muted character is dropped from the Knowledge Points roster everywhere,
-- not just this row's checkbox.
local function EnsureCharacterRow(index)
    return EnsureListRow(ns.optionsPanel.charRows, index, "MoxieTrackerCharacterOption", function(self)
        ns.SetCharacterMuted(self.entryKey, not self:GetChecked())
        if ns.frame:IsShown() then
            ns.UpdateDisplay()
        end
    end)
end

-- Same shape again, one level more specific: mutes a single profession for a
-- single character rather than the whole character.
local function EnsureProfessionRow(index)
    return EnsureListRow(ns.optionsPanel.professionRows, index, "MoxieTrackerProfessionOption", function(self)
        ns.SetKnowledgeProfessionMuted(self.characterKey, self.professionName, not self:GetChecked())
        if ns.frame:IsShown() then
            ns.UpdateDisplay()
        end
    end)
end

-- Concentration's own independent whole-character mute list (#40), mirroring
-- EnsureCharacterRow exactly but against ns.SetConcentrationCharacterMuted
-- so muting a character's Concentration never touches their Knowledge mute.
local function EnsureConcentrationCharacterRow(index)
    return EnsureListRow(ns.optionsPanel.concentrationCharRows, index, "MoxieTrackerConcentrationCharacterOption",
        function(self)
            ns.SetConcentrationCharacterMuted(self.entryKey, not self:GetChecked())
            ns.UpdateConcentrationDisplay()
        end)
end

-- Concentration's per-profession mute list (#40), mirroring
-- EnsureProfessionRow against ns.SetConcentrationProfessionMuted.
local function EnsureConcentrationProfessionRow(index)
    return EnsureListRow(ns.optionsPanel.concentrationProfessionRows, index,
        "MoxieTrackerConcentrationProfessionOption", function(self)
            ns.SetConcentrationProfessionMuted(self.characterKey, self.professionName, not self:GetChecked())
            ns.UpdateConcentrationDisplay()
        end)
end

function ns.RefreshOptions()
    ns.optionsPanel.loginCheckbox:SetChecked(not MoxieTrackerDB.suppressLoginMessage)
    ns.optionsPanel.knowledgeWindowCheckbox:SetChecked(not MoxieTrackerDB.hideKnowledgeWindow)
    ns.optionsPanel.concentrationWindowCheckbox:SetChecked(not MoxieTrackerDB.hideConcentrationWindow)

    for _, window in ipairs(WINDOWS) do
        local fields = ns.optionsPanel.positionFields[window.key]
        local x, y = ns.GetOffset(window.key)
        fields.xEditBox:SetText(x and tostring(x) or "")
        fields.yEditBox:SetText(y and tostring(y) or "")
    end

    ns.optionsPanel.unalloyedEditBox:SetText(tostring(ns.GetThreshold("unalloyedAbundance")))
    ns.optionsPanel.moxieEditBox:SetText(tostring(ns.GetThreshold("moxie")))
    ns.optionsPanel.fusedVitalityEditBox:SetText(tostring(ns.GetThreshold("fusedVitality")))

    for _, profession in ipairs(ns.CONCENTRATION_PROFESSIONS) do
        local box = ns.optionsPanel.concentrationThresholdEditBoxes[profession.name]
        box:SetText(tostring(ns.GetThreshold("concentration:" .. profession.name)))
    end

    ----------------------------------------------------------------------
    -- Tracked-currency rows.
    ----------------------------------------------------------------------
    local tracked = ns.CollectTracked(true)

    for _, row in ipairs(ns.optionsPanel.rows) do
        row:Hide()
    end

    for index, entry in ipairs(tracked) do
        local row = EnsureOptionRow(index)
        row.entryKey = entry.key
        row.label:SetText(entry.name)
        row:SetChecked(not entry.hidden)
        PositionRow(row, OPTIONS_FIRST_ROW_Y - ((index - 1) * OPTIONS_ROW_HEIGHT))
        row:Show()
    end

    if #tracked == 0 then
        ns.optionsPanel.empty:ClearAllPoints()
        ns.optionsPanel.empty:SetPoint("TOPLEFT", ns.optionsPanel.content, "TOPLEFT", 0, OPTIONS_FIRST_ROW_Y)
        ns.optionsPanel.empty:Show()
    else
        ns.optionsPanel.empty:Hide()
    end

    local trackedRowCount = math.max(#tracked, 1) -- reserve one row of space for the "nothing to configure" message
    local trackedListBottomY = OPTIONS_FIRST_ROW_Y - (trackedRowCount * OPTIONS_ROW_HEIGHT)

    ----------------------------------------------------------------------
    -- Character-mute rows. includeMuted=true so a muted character stays
    -- listed (unchecked) instead of disappearing along with its row -- the
    -- only way to un-mute it. The current character is always in this list,
    -- even at 0 points, so it can be pre-muted before it earns any.
    ----------------------------------------------------------------------
    local charHeaderY = trackedListBottomY - OPTIONS_SECTION_GAP
    ns.optionsPanel.charHeader:ClearAllPoints()
    ns.optionsPanel.charHeader:SetPoint("TOPLEFT", ns.optionsPanel.content, "TOPLEFT", 0, charHeaderY)

    local charRowsY = charHeaderY - OPTIONS_HEADER_HEIGHT

    local roster = ns.CollectKnowledgeRoster(true)

    for _, row in ipairs(ns.optionsPanel.charRows) do
        row:Hide()
    end

    for index, entry in ipairs(roster) do
        local row = EnsureCharacterRow(index)
        row.entryKey = entry.key
        row.label:SetText(entry.name)
        row:SetChecked(not entry.muted)
        PositionRow(row, charRowsY - ((index - 1) * OPTIONS_ROW_HEIGHT))
        row:Show()
    end

    local charRowCount = math.max(#roster, 1)
    local charListBottomY = charRowsY - (charRowCount * OPTIONS_ROW_HEIGHT)

    ----------------------------------------------------------------------
    -- Character-profession-mute rows: same idea one level deeper, muting a
    -- single profession for a single character instead of the whole
    -- character. See ns.CollectKnowledgeProfessionRoster for why a muted
    -- character doesn't also appear here.
    ----------------------------------------------------------------------
    local professionHeaderY = charListBottomY - OPTIONS_SECTION_GAP
    ns.optionsPanel.professionHeader:ClearAllPoints()
    ns.optionsPanel.professionHeader:SetPoint("TOPLEFT", ns.optionsPanel.content, "TOPLEFT", 0, professionHeaderY)

    local professionRowsY = professionHeaderY - OPTIONS_HEADER_HEIGHT

    local professionList = ns.CollectKnowledgeProfessionRoster()

    for _, row in ipairs(ns.optionsPanel.professionRows) do
        row:Hide()
    end

    for index, entry in ipairs(professionList) do
        local row = EnsureProfessionRow(index)
        row.characterKey = entry.characterKey
        row.professionName = entry.professionName
        row.label:SetText(string.format("%s \226\128\148 %s", entry.characterName, entry.professionName))
        row:SetChecked(not entry.muted)
        PositionRow(row, professionRowsY - ((index - 1) * OPTIONS_ROW_HEIGHT))
        row:Show()
    end

    if #professionList == 0 then
        ns.optionsPanel.professionEmpty:ClearAllPoints()
        ns.optionsPanel.professionEmpty:SetPoint("TOPLEFT", ns.optionsPanel.content, "TOPLEFT", 0, professionRowsY)
        ns.optionsPanel.professionEmpty:Show()
    else
        ns.optionsPanel.professionEmpty:Hide()
    end

    local professionRowCount = math.max(#professionList, 1)
    local professionListBottomY = professionRowsY - (professionRowCount * OPTIONS_ROW_HEIGHT)

    ----------------------------------------------------------------------
    -- Concentration character-mute rows (#40), mirroring the Characters
    -- section above but against Concentration's own independent mute state
    -- -- muting a character's Concentration never touches their Knowledge
    -- mute, and vice versa. Same includeMuted=true / always-listed-current-
    -- character reasoning as Characters.
    ----------------------------------------------------------------------
    local concentrationCharHeaderY = professionListBottomY - OPTIONS_SECTION_GAP
    ns.optionsPanel.concentrationCharHeader:ClearAllPoints()
    ns.optionsPanel.concentrationCharHeader:SetPoint("TOPLEFT", ns.optionsPanel.content, "TOPLEFT", 0,
        concentrationCharHeaderY)

    local concentrationCharRowsY = concentrationCharHeaderY - OPTIONS_HEADER_HEIGHT

    local concentrationRoster = ns.CollectConcentrationRoster(true)

    for _, row in ipairs(ns.optionsPanel.concentrationCharRows) do
        row:Hide()
    end

    for index, entry in ipairs(concentrationRoster) do
        local row = EnsureConcentrationCharacterRow(index)
        row.entryKey = entry.key
        row.label:SetText(entry.name)
        row:SetChecked(not entry.muted)
        PositionRow(row, concentrationCharRowsY - ((index - 1) * OPTIONS_ROW_HEIGHT))
        row:Show()
    end

    local concentrationCharRowCount = math.max(#concentrationRoster, 1)
    local concentrationCharListBottomY = concentrationCharRowsY - (concentrationCharRowCount * OPTIONS_ROW_HEIGHT)

    ----------------------------------------------------------------------
    -- Concentration profession-mute rows (#40), mirroring Character
    -- Professions against ns.CollectConcentrationProfessionRoster.
    ----------------------------------------------------------------------
    local concentrationProfessionHeaderY = concentrationCharListBottomY - OPTIONS_SECTION_GAP
    ns.optionsPanel.concentrationProfessionHeader:ClearAllPoints()
    ns.optionsPanel.concentrationProfessionHeader:SetPoint("TOPLEFT", ns.optionsPanel.content, "TOPLEFT", 0,
        concentrationProfessionHeaderY)

    local concentrationProfessionRowsY = concentrationProfessionHeaderY - OPTIONS_HEADER_HEIGHT

    local concentrationProfessionList = ns.CollectConcentrationProfessionRoster()

    for _, row in ipairs(ns.optionsPanel.concentrationProfessionRows) do
        row:Hide()
    end

    for index, entry in ipairs(concentrationProfessionList) do
        local row = EnsureConcentrationProfessionRow(index)
        row.characterKey = entry.characterKey
        row.professionName = entry.professionName
        row.label:SetText(string.format("%s \226\128\148 %s", entry.characterName, entry.professionName))
        row:SetChecked(not entry.muted)
        PositionRow(row, concentrationProfessionRowsY - ((index - 1) * OPTIONS_ROW_HEIGHT))
        row:Show()
    end

    if #concentrationProfessionList == 0 then
        ns.optionsPanel.concentrationProfessionEmpty:ClearAllPoints()
        ns.optionsPanel.concentrationProfessionEmpty:SetPoint("TOPLEFT", ns.optionsPanel.content, "TOPLEFT", 0,
            concentrationProfessionRowsY)
        ns.optionsPanel.concentrationProfessionEmpty:Show()
    else
        ns.optionsPanel.concentrationProfessionEmpty:Hide()
    end

    local concentrationProfessionRowCount = math.max(#concentrationProfessionList, 1)
    local concentrationProfessionListBottomY = concentrationProfessionRowsY
        - (concentrationProfessionRowCount * OPTIONS_ROW_HEIGHT)

    -- Content height drives whether the scroll frame's bar is usable at all;
    -- floored at 1 rather than 0, since a zero-height scroll child is what
    -- some client versions treat as "not scrollable" even once rows appear.
    ns.optionsPanel.content:SetHeight(math.max(1, -concentrationProfessionListBottomY + OPTIONS_BOTTOM_MARGIN))

    -- A ScrollFrame does not reliably recompute its scroll range on its own
    -- when its scroll child is resized after creation; without this, rows
    -- added after the initial (1px) scroll child height can end up outside
    -- the range the scroll frame thinks is scrollable and never draw.
    ns.optionsPanel.scrollFrame:UpdateScrollChildRect()
end

-- Called from MoxieTracker_UI.lua's drag-stop handlers after a window is
-- dropped, so an already-open Options panel reflects the new position right
-- away. ns.RefreshOptions only runs on the panel's OnShow, which does not
-- fire again just because a window moved while Settings stayed open -- the
-- symptom this exists to fix: drag a window with Settings open, and its X/Y
-- boxes sat stale until the panel was closed and reopened. Updates just the
-- two boxes for that window rather than calling ns.RefreshOptions, which
-- would also reset the panel's scroll position back to the top on every
-- drag. Skips a box that currently has keyboard focus, so a drag on one
-- window cannot stomp text the user is mid-typing into another window's row.
function ns.RefreshPositionField(windowKey)
    local panel = ns.optionsPanel
    if not panel or not panel:IsShown() then
        return
    end
    local fields = panel.positionFields[windowKey]
    if not fields then
        return
    end
    local x, y = ns.GetOffset(windowKey)
    if not fields.xEditBox:HasFocus() then
        fields.xEditBox:SetText(x and tostring(x) or "")
    end
    if not fields.yEditBox:HasFocus() then
        fields.yEditBox:SetText(y and tostring(y) or "")
    end
end

-- Builds one window's compact Position row: "Label  [X]  [Y]  [Reset]" all
-- on one line (#40 -- replacing what used to be a single header-plus-two-
-- fields-plus-button block for the one main window only).
local function CreatePositionRow(parent, y, window)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    label:SetWidth(90)
    label:SetJustifyH("LEFT")
    label:SetText(window.label)

    local xEditBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    xEditBox:SetSize(50, 20)
    xEditBox:SetAutoFocus(false)
    xEditBox:SetPoint("LEFT", label, "RIGHT", 4, 0)

    local yEditBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    yEditBox:SetSize(50, 20)
    yEditBox:SetAutoFocus(false)
    yEditBox:SetPoint("LEFT", xEditBox, "RIGHT", 8, 0)

    local resetButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    resetButton:SetSize(90, 22)
    resetButton:SetPoint("LEFT", yEditBox, "RIGHT", 12, 0)
    resetButton:SetText("Reset")

    -- Offsets are signed (the default vertical offset is -440), so these are
    -- plain EditBoxes with manual tonumber() validation rather than
    -- SetNumeric(true), which does not allow a minus sign.
    --
    -- The two fields commit together (a half-valid pair would anchor the
    -- window off just one bad entry), but that must not mean "clear
    -- whatever's typed the moment the OTHER box is merely still empty" --
    -- Knowledge/Concentration start with BOTH boxes blank (no default
    -- offset until first dragged, see ns.GetOffset), so filling in just X
    -- and tabbing to Y used to immediately wipe X back to blank as soon as
    -- that tab/Enter/focus-loss fired CommitOffset with Y still empty. A
    -- box is only reverted when it holds text that fails to parse -- an
    -- empty box waiting on its pair is left alone, not treated as invalid.
    local function CommitOffset()
        local xText, yText = xEditBox:GetText(), yEditBox:GetText()
        local newX = xText ~= "" and tonumber(xText) or nil
        local newY = yText ~= "" and tonumber(yText) or nil

        if xText ~= "" and not newX then
            local currentX = ns.GetOffset(window.key)
            xEditBox:SetText(currentX and tostring(currentX) or "")
        end
        if yText ~= "" and not newY then
            local _, currentY = ns.GetOffset(window.key)
            yEditBox:SetText(currentY and tostring(currentY) or "")
        end

        if newX and newY then
            ns.SetOffset(window.key, newX, newY)
            ns.ApplyAnchor()
        end
    end

    for _, box in ipairs({ xEditBox, yEditBox }) do
        box:SetScript("OnEnterPressed", function(self)
            CommitOffset()
            self:ClearFocus()
        end)
        box:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
        end)
        box:SetScript("OnEditFocusLost", CommitOffset)
    end

    -- Tab/shift-tab moves between X and Y within the row, rather than
    -- leaving the box (WoW's EditBox does not chain focus between sibling
    -- boxes on its own).
    xEditBox:SetScript("OnTabPressed", function(self)
        if IsShiftKeyDown() then
            self:ClearFocus()
        else
            yEditBox:SetFocus()
        end
    end)
    yEditBox:SetScript("OnTabPressed", function(self)
        if IsShiftKeyDown() then
            xEditBox:SetFocus()
        else
            self:ClearFocus()
        end
    end)

    resetButton:SetScript("OnClick", function()
        ns.ResetWindowPosition(window.key)
        local resetX, resetY = ns.GetOffset(window.key)
        xEditBox:SetText(resetX and tostring(resetX) or "")
        yEditBox:SetText(resetY and tostring(resetY) or "")
    end)

    return { xEditBox = xEditBox, yEditBox = yEditBox }
end

local function CreateOptionsPanel()
    local panel = CreateFrame("Frame", "MoxieTrackerOptionsPanel", UIParent)
    panel.name = "MoxieTracker"
    panel.rows = {}
    panel.charRows = {}
    panel.professionRows = {}
    panel.concentrationCharRows = {}
    panel.concentrationProfessionRows = {}
    panel.positionFields = {}
    panel.concentrationThresholdEditBoxes = {}

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    title:SetText("MoxieTracker " .. ns.GetVersion())

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("Uncheck a row to hide it from the tracker. Choices apply to the whole account.")

    -- Everything else lives inside this single scroll region -- see the
    -- comment above OPTIONS_ROW_HEIGHT for why a fixed layout wasn't enough,
    -- and for why this is an explicit SetSize rather than anchored to the
    -- panel's own edges.
    local scrollFrame = CreateFrame("ScrollFrame", "MoxieTrackerOptionsScrollFrame", panel,
        "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -60)
    scrollFrame:SetSize(OPTIONS_CONTENT_WIDTH, OPTIONS_CONTENT_HEIGHT)
    panel.scrollFrame = scrollFrame

    -- No SetPoint calls here: a ScrollFrame manages its scroll child's
    -- anchoring internally once SetScrollChild is called. Manually anchoring
    -- the child first (as this used to) fights that internal positioning and
    -- loses -- confirmed in-game via GetLeft()/GetTop() both reading nil on
    -- the scroll child and everything anchored to it, despite each frame
    -- otherwise reporting a normal size and Show/IsVisible state. An explicit
    -- SetSize before SetScrollChild is the correct, sufficient way to give
    -- the child a shape; the scroll frame positions it from there.
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(OPTIONS_CONTENT_WIDTH, 1)
    scrollFrame:SetScrollChild(content)
    panel.content = content

    local loginCheckbox = CreateFrame("CheckButton", "MoxieTrackerLoginMessageOption", content, "UICheckButtonTemplate")
    loginCheckbox:SetSize(24, 24)
    loginCheckbox:SetPoint("TOPLEFT", content, "TOPLEFT", 0, OPTIONS_LOGIN_ROW_Y)
    loginCheckbox.label = loginCheckbox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    loginCheckbox.label:SetPoint("LEFT", loginCheckbox, "RIGHT", 4, 0)
    loginCheckbox.label:SetText("Show version message at login")
    loginCheckbox:SetScript("OnClick", function(self)
        MoxieTrackerDB.suppressLoginMessage = not self:GetChecked()
    end)
    panel.loginCheckbox = loginCheckbox

    -- Separate from muting individual characters/professions: this is the
    -- blunt "I don't want this window at all" off switch, independent of
    -- either roster's mute state.
    local knowledgeWindowCheckbox = CreateFrame("CheckButton", "MoxieTrackerKnowledgeWindowOption", content,
        "UICheckButtonTemplate")
    knowledgeWindowCheckbox:SetSize(24, 24)
    knowledgeWindowCheckbox:SetPoint("TOPLEFT", content, "TOPLEFT", 0, OPTIONS_KNOWLEDGE_WINDOW_ROW_Y)
    knowledgeWindowCheckbox.label = knowledgeWindowCheckbox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    knowledgeWindowCheckbox.label:SetPoint("LEFT", knowledgeWindowCheckbox, "RIGHT", 4, 0)
    knowledgeWindowCheckbox.label:SetText("Show Knowledge Points window")
    knowledgeWindowCheckbox:SetScript("OnClick", function(self)
        MoxieTrackerDB.hideKnowledgeWindow = not self:GetChecked()
        if ns.frame:IsShown() then
            ns.UpdateKnowledgeDisplay()
        end
    end)
    panel.knowledgeWindowCheckbox = knowledgeWindowCheckbox

    local concentrationWindowCheckbox = CreateFrame("CheckButton", "MoxieTrackerConcentrationWindowOption", content,
        "UICheckButtonTemplate")
    concentrationWindowCheckbox:SetSize(24, 24)
    concentrationWindowCheckbox:SetPoint("TOPLEFT", content, "TOPLEFT", 0, OPTIONS_CONCENTRATION_WINDOW_ROW_Y)
    concentrationWindowCheckbox.label = concentrationWindowCheckbox:CreateFontString(nil, "OVERLAY",
        "GameFontHighlight")
    concentrationWindowCheckbox.label:SetPoint("LEFT", concentrationWindowCheckbox, "RIGHT", 4, 0)
    concentrationWindowCheckbox.label:SetText("Show Concentration window")
    concentrationWindowCheckbox:SetScript("OnClick", function(self)
        MoxieTrackerDB.hideConcentrationWindow = not self:GetChecked()
        ns.UpdateConcentrationDisplay()
        ns.RefreshConcentrationTicker()
    end)
    panel.concentrationWindowCheckbox = concentrationWindowCheckbox

    local positionHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    positionHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 0, OPTIONS_POSITION_HEADER_Y)
    positionHeader:SetText("Position")

    -- Column labels, aligned with CreatePositionRow's own layout (a 90px
    -- window-name label plus 4px gap puts the X box's left edge at x=110;
    -- the X box's 50px width plus 8px gap puts the Y box's at x=168) so
    -- they sit directly above each row's boxes, sharing the header's row
    -- rather than costing an extra one.
    local xColumnLabel = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    xColumnLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 110, OPTIONS_POSITION_HEADER_Y)
    xColumnLabel:SetWidth(50)
    xColumnLabel:SetJustifyH("CENTER")
    xColumnLabel:SetText("X")

    local yColumnLabel = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    yColumnLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 168, OPTIONS_POSITION_HEADER_Y)
    yColumnLabel:SetWidth(50)
    yColumnLabel:SetJustifyH("CENTER")
    yColumnLabel:SetText("Y")

    panel.positionFields.main = CreatePositionRow(content, OPTIONS_POSITION_MAIN_ROW_Y, WINDOWS[1])
    panel.positionFields.knowledge = CreatePositionRow(content, OPTIONS_POSITION_KNOWLEDGE_ROW_Y, WINDOWS[2])
    panel.positionFields.concentration = CreatePositionRow(content, OPTIONS_POSITION_CONCENTRATION_ROW_Y, WINDOWS[3])

    -- All thresholds together (#40 follow-up): Moxie/Unalloyed Abundance/
    -- Fused Vitality and the 8 per-profession Concentration thresholds
    -- under one header, rather than Concentration split into its own
    -- separate section. They already share one flat MoxieTrackerDB.thresholds
    -- table, so a single "Reset thresholds" button below covers all 11.
    local thresholdHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    thresholdHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 0, OPTIONS_THRESHOLD_HEADER_Y)
    thresholdHeader:SetText("Color thresholds")

    -- Thresholds are always non-negative, so SetNumeric(true) is enough
    -- validation on its own; a cleared box (empty string) still needs the
    -- same tonumber() nil-check as the position fields.
    local unalloyedEditBox = CreateSettingField(content, OPTIONS_THRESHOLD_UA_ROW_Y, "Unalloyed Abundance")
    local moxieEditBox = CreateSettingField(content, OPTIONS_THRESHOLD_MOXIE_ROW_Y, "Moxie")
    local fusedVitalityEditBox = CreateSettingField(content, OPTIONS_THRESHOLD_FV_ROW_Y, "Fused Vitality")
    for _, box in ipairs({ unalloyedEditBox, moxieEditBox, fusedVitalityEditBox }) do
        box:SetNumeric(true)
    end
    panel.unalloyedEditBox = unalloyedEditBox
    panel.moxieEditBox = moxieEditBox
    panel.fusedVitalityEditBox = fusedVitalityEditBox

    -- Each threshold commits independently, unlike the offset pair: they are
    -- unrelated settings, so one bad entry should not revert the others.
    local function CommitThreshold(box, key)
        local value = tonumber(box:GetText())
        if not value then
            box:SetText(tostring(ns.GetThreshold(key)))
            return
        end
        MoxieTrackerDB.thresholds = MoxieTrackerDB.thresholds or {}
        MoxieTrackerDB.thresholds[key] = value
        if ns.frame:IsShown() then
            ns.UpdateDisplay()
        end
        if key:find("^concentration:") then
            ns.UpdateConcentrationDisplay()
        end
    end

    local thresholdFields = {
        { box = unalloyedEditBox, key = "unalloyedAbundance" },
        { box = moxieEditBox, key = "moxie" },
        { box = fusedVitalityEditBox, key = "fusedVitality" },
    }

    for index, profession in ipairs(ns.CONCENTRATION_PROFESSIONS) do
        local y = OPTIONS_THRESHOLD_CONCENTRATION_FIRST_Y - ((index - 1) * OPTIONS_ROW_HEIGHT)
        local editBox = CreateSettingField(content, y, profession.name)
        editBox:SetNumeric(true)
        local key = "concentration:" .. profession.name
        panel.concentrationThresholdEditBoxes[profession.name] = editBox
        table.insert(thresholdFields, { box = editBox, key = key })
    end

    for _, field in ipairs(thresholdFields) do
        field.box:SetScript("OnEnterPressed", function(self)
            CommitThreshold(field.box, field.key)
            self:ClearFocus()
        end)
        field.box:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
        end)
        field.box:SetScript("OnEditFocusLost", function()
            CommitThreshold(field.box, field.key)
        end)
    end

    local resetThresholdsButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    resetThresholdsButton:SetSize(120, 22)
    resetThresholdsButton:SetPoint("TOPLEFT", content, "TOPLEFT", 0, OPTIONS_THRESHOLD_RESET_Y)
    resetThresholdsButton:SetText("Reset thresholds")
    resetThresholdsButton:SetScript("OnClick", function()
        MoxieTrackerDB.thresholds = nil
        for _, field in ipairs(thresholdFields) do
            field.box:SetText(tostring(ns.GetThreshold(field.key)))
        end
        if ns.frame:IsShown() then
            ns.UpdateDisplay()
        end
        ns.UpdateConcentrationDisplay()
    end)

    -- Tracked-row checkboxes start at OPTIONS_FIRST_ROW_Y; RefreshOptions
    -- positions each one (row count, so start Y, isn't known until then).
    panel.empty = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    panel.empty:SetText("Nothing to configure yet - open a profession or log in on a character with moxie.")
    panel.empty:Hide()

    local charHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    charHeader:SetText("Characters")
    panel.charHeader = charHeader

    local charSubtitle = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    charSubtitle:SetPoint("LEFT", charHeader, "RIGHT", 8, 0)
    charSubtitle:SetText("(uncheck to mute a character from the Knowledge Points list forever)")

    local professionHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    professionHeader:SetText("Character Professions")
    panel.professionHeader = professionHeader

    local professionSubtitle = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    professionSubtitle:SetPoint("LEFT", professionHeader, "RIGHT", 8, 0)
    professionSubtitle:SetText("(uncheck to mute a single profession's points for that character)")

    panel.professionEmpty = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    panel.professionEmpty:SetText("No profession Knowledge recorded yet.")
    panel.professionEmpty:Hide()

    -- Concentration's own mute sections (#40), mirroring Characters/
    -- Character Professions above but independent of Knowledge's mute state.
    local concentrationCharHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    concentrationCharHeader:SetText("Concentration")
    panel.concentrationCharHeader = concentrationCharHeader

    local concentrationCharSubtitle = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    concentrationCharSubtitle:SetPoint("LEFT", concentrationCharHeader, "RIGHT", 8, 0)
    concentrationCharSubtitle:SetText("(uncheck to mute a character from the Concentration list forever)")

    local concentrationProfessionHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    concentrationProfessionHeader:SetText("Concentration Professions")
    panel.concentrationProfessionHeader = concentrationProfessionHeader

    local concentrationProfessionSubtitle = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    concentrationProfessionSubtitle:SetPoint("LEFT", concentrationProfessionHeader, "RIGHT", 8, 0)
    concentrationProfessionSubtitle:SetText("(uncheck to mute a single profession's Concentration for that character)")

    panel.concentrationProfessionEmpty = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    panel.concentrationProfessionEmpty:SetText("No Concentration discovered yet.")
    panel.concentrationProfessionEmpty:Hide()

    -- Hidden until the Settings frame shows it. Also makes OnShow the single
    -- point where rows are built, rather than it having to run once here too.
    panel:Hide()
    panel:SetScript("OnShow", ns.RefreshOptions)

    ns.optionsPanel = panel
end

CreateOptionsPanel()

if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    optionsCategory = Settings.RegisterCanvasLayoutCategory(ns.optionsPanel, "MoxieTracker")
    Settings.RegisterAddOnCategory(optionsCategory)
end

function ns.OpenOptions()
    if optionsCategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(optionsCategory:GetID())
        return true
    end
    return false
end
