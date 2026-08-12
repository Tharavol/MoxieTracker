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
-- everything fixes that regardless of how many rows any of the three lists
-- below end up with.
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

local OPTIONS_LOGIN_ROW_Y = 0
local OPTIONS_KNOWLEDGE_WINDOW_ROW_Y = OPTIONS_LOGIN_ROW_Y - OPTIONS_ROW_HEIGHT

-- Position section: a header, two offset fields, and a reset button.
local OPTIONS_POSITION_HEADER_Y = OPTIONS_KNOWLEDGE_WINDOW_ROW_Y - OPTIONS_ROW_HEIGHT
local OPTIONS_POSITION_X_ROW_Y = OPTIONS_POSITION_HEADER_Y - OPTIONS_HEADER_HEIGHT
local OPTIONS_POSITION_Y_ROW_Y = OPTIONS_POSITION_X_ROW_Y - OPTIONS_ROW_HEIGHT
local OPTIONS_POSITION_RESET_Y = OPTIONS_POSITION_Y_ROW_Y - OPTIONS_ROW_HEIGHT

-- Threshold section: a header, three threshold fields, and a reset button.
local OPTIONS_THRESHOLD_HEADER_Y = OPTIONS_POSITION_RESET_Y - OPTIONS_ROW_HEIGHT - OPTIONS_SECTION_GAP
local OPTIONS_THRESHOLD_UA_ROW_Y = OPTIONS_THRESHOLD_HEADER_Y - OPTIONS_HEADER_HEIGHT
local OPTIONS_THRESHOLD_MOXIE_ROW_Y = OPTIONS_THRESHOLD_UA_ROW_Y - OPTIONS_ROW_HEIGHT
local OPTIONS_THRESHOLD_FV_ROW_Y = OPTIONS_THRESHOLD_MOXIE_ROW_Y - OPTIONS_ROW_HEIGHT
local OPTIONS_THRESHOLD_RESET_Y = OPTIONS_THRESHOLD_FV_ROW_Y - OPTIONS_ROW_HEIGHT

-- Everything from here down has a row count only known at refresh time (the
-- tracked-currency list, the character-mute list, and the profession-mute
-- list), so their start positions are computed in RefreshOptions rather than
-- as fixed constants -- each section's header anchors to the bottom of
-- whatever rendered above it.
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

-- Shared shape for all three row lists below: a checkbox plus label, parented
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

function ns.RefreshOptions()
    ns.optionsPanel.loginCheckbox:SetChecked(not MoxieTrackerDB.suppressLoginMessage)
    ns.optionsPanel.knowledgeWindowCheckbox:SetChecked(not MoxieTrackerDB.hideKnowledgeWindow)

    local offsetX, offsetY = ns.GetOffset()
    ns.optionsPanel.xEditBox:SetText(tostring(offsetX))
    ns.optionsPanel.yEditBox:SetText(tostring(offsetY))

    ns.optionsPanel.unalloyedEditBox:SetText(tostring(ns.GetThreshold("unalloyedAbundance")))
    ns.optionsPanel.moxieEditBox:SetText(tostring(ns.GetThreshold("moxie")))
    ns.optionsPanel.fusedVitalityEditBox:SetText(tostring(ns.GetThreshold("fusedVitality")))

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

    -- Content height drives whether the scroll frame's bar is usable at all;
    -- floored at 1 rather than 0, since a zero-height scroll child is what
    -- some client versions treat as "not scrollable" even once rows appear.
    ns.optionsPanel.content:SetHeight(math.max(1, -professionListBottomY + OPTIONS_BOTTOM_MARGIN))

    -- A ScrollFrame does not reliably recompute its scroll range on its own
    -- when its scroll child is resized after creation; without this, rows
    -- added after the initial (1px) scroll child height can end up outside
    -- the range the scroll frame thinks is scrollable and never draw.
    ns.optionsPanel.scrollFrame:UpdateScrollChildRect()
end

local function CreateOptionsPanel()
    local panel = CreateFrame("Frame", "MoxieTrackerOptionsPanel", UIParent)
    panel.name = "MoxieTracker"
    panel.rows = {}
    panel.charRows = {}
    panel.professionRows = {}

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

    -- Separate from muting individual characters: this is the blunt "I don't
    -- want this second window at all" off switch, independent of the roster.
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

    local positionHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    positionHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 0, OPTIONS_POSITION_HEADER_Y)
    positionHeader:SetText("Position")

    -- Offsets are signed (the default vertical offset is -440), so these are
    -- plain EditBoxes with manual tonumber() validation rather than
    -- SetNumeric(true), which does not allow a minus sign.
    local xEditBox = CreateSettingField(content, OPTIONS_POSITION_X_ROW_Y, "Horizontal offset")
    local yEditBox = CreateSettingField(content, OPTIONS_POSITION_Y_ROW_Y, "Vertical offset")
    panel.xEditBox = xEditBox
    panel.yEditBox = yEditBox

    -- Both fields commit together: a half-valid pair would anchor the panel
    -- off just one bad entry, so invalid input reverts both to their last
    -- stored (or default) value instead of applying only the valid one.
    local function CommitOffset()
        local x = tonumber(xEditBox:GetText())
        local y = tonumber(yEditBox:GetText())
        if not x or not y then
            local currentX, currentY = ns.GetOffset()
            xEditBox:SetText(tostring(currentX))
            yEditBox:SetText(tostring(currentY))
            return
        end
        MoxieTrackerDB.offsetX = x
        MoxieTrackerDB.offsetY = y
        ns.ApplyAnchor()
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

    local resetPositionButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    resetPositionButton:SetSize(120, 22)
    resetPositionButton:SetPoint("TOPLEFT", content, "TOPLEFT", 0, OPTIONS_POSITION_RESET_Y)
    resetPositionButton:SetText("Reset position")
    resetPositionButton:SetScript("OnClick", function()
        ns.ResetPosition()
        local x, y = ns.GetOffset()
        xEditBox:SetText(tostring(x))
        yEditBox:SetText(tostring(y))
    end)

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
    end

    for _, field in ipairs({
        { box = unalloyedEditBox, key = "unalloyedAbundance" },
        { box = moxieEditBox, key = "moxie" },
        { box = fusedVitalityEditBox, key = "fusedVitality" },
    }) do
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
        unalloyedEditBox:SetText(tostring(ns.GetThreshold("unalloyedAbundance")))
        moxieEditBox:SetText(tostring(ns.GetThreshold("moxie")))
        fusedVitalityEditBox:SetText(tostring(ns.GetThreshold("fusedVitality")))
        if ns.frame:IsShown() then
            ns.UpdateDisplay()
        end
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
