-- Depends on MoxieTracker_Config.lua, MoxieTracker_Collect.lua, and
-- MoxieTracker_UI.lua, loaded first per the TOC. Three Settings pages (#41):
-- General (the top-level category), plus Thresholds and Muting as
-- subcategories -- previously one long scrolling page holding all of it.

local _, ns = ...

-- Each page gets its own scroll region -- see the comment above
-- OPTIONS_ROW_HEIGHT in the original single-page version (still true here,
-- just applied three times instead of once): a canvas settings
-- category/subcategory is not guaranteed to stretch the frame it's given to
-- fill the available area, and does not clip or scroll on its own, so any
-- content taller than the fixed canvas region draws past the bottom of the
-- window instead of scrolling. A UIPanelScrollFrameTemplate inside that
-- region, sized with an explicit SetSize (not anchored to the panel's own
-- edges, which read 0 in-game), fixes that regardless of a page's content.
local OPTIONS_ROW_HEIGHT = 26
local OPTIONS_HEADER_HEIGHT = 20
local OPTIONS_SECTION_GAP = 6
local OPTIONS_CONTENT_WIDTH = 500
local OPTIONS_CONTENT_HEIGHT = 460
local OPTIONS_BOTTOM_MARGIN = 16

-- The three independently positioned tracker windows (#40), in the order
-- their compact Position rows render on the General page.
local WINDOWS = {
    { key = "main", label = "Main" },
    { key = "knowledge", label = "Knowledge" },
    { key = "concentration", label = "Concentration" },
}

local generalCategory

--------------------------------------------------------------------------
-- Shared helpers, used by more than one page.
--------------------------------------------------------------------------

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

-- Shared shape for every row list across all three pages: a checkbox plus
-- label, parented to the given page's scroll content and positioned
-- explicitly by the caller (a list's start Y depends on how tall the list
-- above it turned out to be, so position can't be baked in here the way a
-- single fixed-origin list could). Takes `panel` explicitly now that there
-- are three separate panel tables instead of one shared ns.optionsPanel.
local function EnsureListRow(panel, pool, index, frameNamePrefix, onClick)
    local row = pool[index]
    if not row then
        row = CreateFrame("CheckButton", frameNamePrefix .. index, panel.content, "UICheckButtonTemplate")
        row:SetSize(24, 24)
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.label:SetPoint("LEFT", row, "RIGHT", 4, 0)
        row:SetScript("OnClick", onClick)
        pool[index] = row
    end
    return row
end

local function PositionRow(panel, row, y)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, y)
end

-- Builds one window's compact Position row: "Label  [X]  [Y]  [Reset]" all
-- on one line (#40). Lives here rather than under the General-page section
-- below since nothing else about it is General-specific.
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

-- Builds a page's title + scroll region, shared boilerplate across all
-- three panels. `titleText` is the page's own heading (not necessarily the
-- addon name -- only the top-level General page uses that); `subtitleText`
-- is a short one-line description shown beneath it.
local function CreatePanelShell(globalName, titleText, subtitleText)
    local panel = CreateFrame("Frame", globalName, UIParent)
    panel.name = titleText

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    title:SetText(titleText)

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText(subtitleText)

    local scrollFrame = CreateFrame("ScrollFrame", globalName .. "ScrollFrame", panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -60)
    scrollFrame:SetSize(OPTIONS_CONTENT_WIDTH, OPTIONS_CONTENT_HEIGHT)
    panel.scrollFrame = scrollFrame

    -- No SetPoint calls here: a ScrollFrame manages its scroll child's
    -- anchoring internally once SetScrollChild is called. Manually anchoring
    -- the child first fights that internal positioning and loses --
    -- confirmed in-game via GetLeft()/GetTop() both reading nil on the
    -- scroll child and everything anchored to it, despite each frame
    -- otherwise reporting a normal size and Show/IsVisible state. An
    -- explicit SetSize before SetScrollChild is the correct, sufficient way
    -- to give the child a shape; the scroll frame positions it from there.
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(OPTIONS_CONTENT_WIDTH, 1)
    scrollFrame:SetScrollChild(content)
    panel.content = content

    panel:Hide()
    return panel
end

--------------------------------------------------------------------------
-- General page (top-level category): login/window-visibility checkboxes,
-- the three-window Position section, and the tracked-currency list.
--------------------------------------------------------------------------

local OPTIONS_LOGIN_ROW_Y = 0
local OPTIONS_MOXIE_ROW_Y = OPTIONS_LOGIN_ROW_Y - OPTIONS_ROW_HEIGHT
local OPTIONS_KNOWLEDGE_WINDOW_ROW_Y = OPTIONS_MOXIE_ROW_Y - OPTIONS_ROW_HEIGHT
local OPTIONS_CONCENTRATION_WINDOW_ROW_Y = OPTIONS_KNOWLEDGE_WINDOW_ROW_Y - OPTIONS_ROW_HEIGHT

-- Position section: a header (sharing its row with the X/Y column labels)
-- plus one compact "Label [X] [Y] [Reset]" row per window.
local OPTIONS_POSITION_HEADER_Y = OPTIONS_CONCENTRATION_WINDOW_ROW_Y - OPTIONS_ROW_HEIGHT
local OPTIONS_POSITION_MAIN_ROW_Y = OPTIONS_POSITION_HEADER_Y - OPTIONS_HEADER_HEIGHT
local OPTIONS_POSITION_KNOWLEDGE_ROW_Y = OPTIONS_POSITION_MAIN_ROW_Y - OPTIONS_ROW_HEIGHT
local OPTIONS_POSITION_CONCENTRATION_ROW_Y = OPTIONS_POSITION_KNOWLEDGE_ROW_Y - OPTIONS_ROW_HEIGHT

-- The tracked-currency list's row count is only known at refresh time, so
-- its start is the last fixed constant on this page -- it anchors to the
-- bottom of whatever rendered above it.
local OPTIONS_FIRST_ROW_Y = OPTIONS_POSITION_CONCENTRATION_ROW_Y - OPTIONS_ROW_HEIGHT - OPTIONS_SECTION_GAP

local function EnsureOptionRow(panel, index)
    return EnsureListRow(panel, panel.rows, index, "MoxieTrackerOption", function(self)
        ns.SetHidden(self.entryKey, not self:GetChecked())
        if ns.frame:IsShown() then
            ns.UpdateDisplay()
        end
    end)
end

function ns.RefreshGeneralOptions()
    local panel = ns.generalPanel
    panel.loginCheckbox:SetChecked(not MoxieTrackerDB.suppressLoginMessage)
    panel.moxieCheckbox:SetChecked(not MoxieTrackerDB.hideMoxie)
    panel.knowledgeWindowCheckbox:SetChecked(not MoxieTrackerDB.hideKnowledgeWindow)
    panel.concentrationWindowCheckbox:SetChecked(not MoxieTrackerDB.hideConcentrationWindow)

    for _, window in ipairs(WINDOWS) do
        local fields = panel.positionFields[window.key]
        local x, y = ns.GetOffset(window.key)
        fields.xEditBox:SetText(x and tostring(x) or "")
        fields.yEditBox:SetText(y and tostring(y) or "")
    end

    local tracked = ns.CollectTracked(true, true)

    for _, row in ipairs(panel.rows) do
        row:Hide()
    end

    for index, entry in ipairs(tracked) do
        local row = EnsureOptionRow(panel, index)
        row.entryKey = entry.key
        row.label:SetText(entry.name)
        row:SetChecked(not entry.hidden)
        PositionRow(panel, row, OPTIONS_FIRST_ROW_Y - ((index - 1) * OPTIONS_ROW_HEIGHT))
        row:Show()
    end

    if #tracked == 0 then
        panel.empty:ClearAllPoints()
        panel.empty:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, OPTIONS_FIRST_ROW_Y)
        panel.empty:Show()
    else
        panel.empty:Hide()
    end

    local trackedRowCount = math.max(#tracked, 1) -- reserve one row of space for the "nothing to configure" message
    local trackedListBottomY = OPTIONS_FIRST_ROW_Y - (trackedRowCount * OPTIONS_ROW_HEIGHT)

    -- Content height drives whether the scroll frame's bar is usable at all;
    -- floored at 1 rather than 0, since a zero-height scroll child is what
    -- some client versions treat as "not scrollable" even once rows appear.
    panel.content:SetHeight(math.max(1, -trackedListBottomY + OPTIONS_BOTTOM_MARGIN))

    -- A ScrollFrame does not reliably recompute its scroll range on its own
    -- when its scroll child is resized after creation; without this, rows
    -- added after the initial (1px) scroll child height can end up outside
    -- the range the scroll frame thinks is scrollable and never draw.
    panel.scrollFrame:UpdateScrollChildRect()
end

-- Called from MoxieTracker_UI.lua's drag-stop handlers after a window is
-- dropped, so an already-open General page reflects the new position right
-- away. ns.RefreshGeneralOptions only runs on the page's OnShow, which does
-- not fire again just because a window moved while Settings stayed open --
-- the symptom this exists to fix: drag a window with Settings open, and its
-- X/Y boxes sat stale until the panel was closed and reopened. Updates just
-- the two boxes for that window rather than calling ns.RefreshGeneralOptions,
-- which would also reset the page's scroll position back to the top on
-- every drag. Skips a box that currently has keyboard focus, so a drag on
-- one window cannot stomp text the user is mid-typing into another
-- window's row.
function ns.RefreshPositionField(windowKey)
    local panel = ns.generalPanel
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

local function CreateGeneralPanel()
    local panel = CreatePanelShell("MoxieTrackerOptionsPanel", "MoxieTracker " .. ns.GetVersion(),
        "Uncheck a row to hide it from the tracker. This is a global setting.")
    panel.rows = {}
    panel.positionFields = {}

    local content = panel.content

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

    -- Master Moxie visibility (#43): global, not per-character -- unchecking
    -- this hides Moxie from the tracker regardless of the per-profession
    -- picks on the Moxie Professions page. Those per-profession picks only
    -- take effect while this stays checked.
    local moxieCheckbox = CreateFrame("CheckButton", "MoxieTrackerMoxieOption", content, "UICheckButtonTemplate")
    moxieCheckbox:SetSize(24, 24)
    moxieCheckbox:SetPoint("TOPLEFT", content, "TOPLEFT", 0, OPTIONS_MOXIE_ROW_Y)
    moxieCheckbox.label = moxieCheckbox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    moxieCheckbox.label:SetPoint("LEFT", moxieCheckbox, "RIGHT", 4, 0)
    moxieCheckbox.label:SetText("Show Moxie")
    moxieCheckbox:SetScript("OnClick", function(self)
        MoxieTrackerDB.hideMoxie = not self:GetChecked()
        if ns.frame:IsShown() then
            ns.UpdateDisplay()
        end
    end)
    panel.moxieCheckbox = moxieCheckbox

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

    -- Tracked-row checkboxes start at OPTIONS_FIRST_ROW_Y; RefreshGeneralOptions
    -- positions each one (row count, so start Y, isn't known until then).
    panel.empty = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    panel.empty:SetText("Nothing to configure yet - open a profession or collect a tracked item.")
    panel.empty:Hide()

    panel:SetScript("OnShow", ns.RefreshGeneralOptions)
    ns.generalPanel = panel
end

--------------------------------------------------------------------------
-- Moxie Professions subcategory: Moxie's per-profession visibility list
-- (#43). Global, not per-character -- the master "Show Moxie" checkbox on
-- General is also global, so there is nothing character-specific to key
-- this list on. A Moxie profession's hidden state already lives on its
-- currency ID alone via ns.IsHidden/ns.SetHidden (the same mechanism the
-- General page's tracked-currency list already used before this page
-- existed), so this page lists all eleven professions unconditionally
-- rather than gating on what the currently-logged-in character has
-- trained the way Character Professions/Concentration Professions do.
--------------------------------------------------------------------------

local function EnsureMoxieProfessionRow(panel, index)
    return EnsureListRow(panel, panel.moxieProfessionRows, index, "MoxieTrackerMoxieProfessionOption", function(self)
        ns.SetHidden(self.entryKey, not self:GetChecked())
        if ns.frame:IsShown() then
            ns.UpdateDisplay()
        end
    end)
end

function ns.RefreshMoxieProfessionsOptions()
    local panel = ns.moxieProfessionsPanel
    local rowsY = 0 - OPTIONS_HEADER_HEIGHT

    for _, row in ipairs(panel.moxieProfessionRows) do
        row:Hide()
    end

    for index, profession in ipairs(ns.MOXIE_PROFESSIONS) do
        local entryKey = ns.EntryKey(profession.id, nil, nil)
        local row = EnsureMoxieProfessionRow(panel, index)
        row.entryKey = entryKey
        local info = C_CurrencyInfo.GetCurrencyInfo(profession.id)
        row.label:SetText((info and info.name) or profession.name)
        row:SetChecked(not ns.IsHidden(entryKey))
        PositionRow(panel, row, rowsY - ((index - 1) * OPTIONS_ROW_HEIGHT))
        row:Show()
    end

    local rowCount = #ns.MOXIE_PROFESSIONS
    local listBottomY = rowsY - (rowCount * OPTIONS_ROW_HEIGHT)
    panel.content:SetHeight(math.max(1, -listBottomY + OPTIONS_BOTTOM_MARGIN))
    panel.scrollFrame:UpdateScrollChildRect()
end

local function CreateMoxieProfessionsPanel()
    local panel = CreatePanelShell("MoxieTrackerMoxieProfessionsPanel", "Moxie Professions",
        "Uncheck to hide a single profession's Moxie from the tracker. This is a global setting.")
    panel.moxieProfessionRows = {}
    panel:SetScript("OnShow", ns.RefreshMoxieProfessionsOptions)
    ns.moxieProfessionsPanel = panel
end

--------------------------------------------------------------------------
-- Thresholds subcategory: all eleven color thresholds and a single reset
-- button (#40 follow-up: Concentration's 8 per-profession thresholds share
-- this page with Moxie/Unalloyed Abundance/Fused Vitality rather than
-- having their own separate section -- they already share one flat
-- MoxieTrackerDB.thresholds table).
--------------------------------------------------------------------------

local OPTIONS_THRESHOLD_HEADER_Y = 0
local OPTIONS_THRESHOLD_UA_ROW_Y = OPTIONS_THRESHOLD_HEADER_Y - OPTIONS_HEADER_HEIGHT
local OPTIONS_THRESHOLD_MOXIE_ROW_Y = OPTIONS_THRESHOLD_UA_ROW_Y - OPTIONS_ROW_HEIGHT
local OPTIONS_THRESHOLD_FV_ROW_Y = OPTIONS_THRESHOLD_MOXIE_ROW_Y - OPTIONS_ROW_HEIGHT
local OPTIONS_THRESHOLD_CONCENTRATION_FIRST_Y = OPTIONS_THRESHOLD_FV_ROW_Y - OPTIONS_ROW_HEIGHT
local OPTIONS_THRESHOLD_RESET_Y = OPTIONS_THRESHOLD_CONCENTRATION_FIRST_Y
    - (#ns.CONCENTRATION_PROFESSIONS * OPTIONS_ROW_HEIGHT)

function ns.RefreshThresholdsOptions()
    local panel = ns.thresholdsPanel
    panel.unalloyedEditBox:SetText(tostring(ns.GetThreshold("unalloyedAbundance")))
    panel.moxieEditBox:SetText(tostring(ns.GetThreshold("moxie")))
    panel.fusedVitalityEditBox:SetText(tostring(ns.GetThreshold("fusedVitality")))
    for _, profession in ipairs(ns.CONCENTRATION_PROFESSIONS) do
        local box = panel.concentrationThresholdEditBoxes[profession.name]
        box:SetText(tostring(ns.GetThreshold("concentration:" .. profession.name)))
    end
end

local function CreateThresholdsPanel()
    local panel = CreatePanelShell("MoxieTrackerThresholdsPanel", "Thresholds",
        "Color thresholds for every tracked currency. This is a global setting.")
    panel.concentrationThresholdEditBoxes = {}

    local content = panel.content

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

    -- Each threshold commits independently, unlike the Position fields: they
    -- are unrelated settings, so one bad entry should not revert the others.
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

    -- Every row on this page has a fixed, build-time-known position (unlike
    -- General's tracked-currency list or Muting's four rosters), so the
    -- scroll child's height is set once here rather than recomputed on
    -- every refresh.
    content:SetHeight(math.max(1, -OPTIONS_THRESHOLD_RESET_Y + OPTIONS_BOTTOM_MARGIN))
    panel.scrollFrame:UpdateScrollChildRect()

    panel:SetScript("OnShow", ns.RefreshThresholdsOptions)
    ns.thresholdsPanel = panel
end

--------------------------------------------------------------------------
-- Characters subcategory: Knowledge's whole-character mute list (#41 --
-- previously grouped with the other three mute lists on one Muting page).
--------------------------------------------------------------------------

local function EnsureCharacterRow(panel, index)
    return EnsureListRow(panel, panel.charRows, index, "MoxieTrackerCharacterOption", function(self)
        ns.SetCharacterMuted(self.entryKey, not self:GetChecked())
        if ns.frame:IsShown() then
            ns.UpdateDisplay()
        end
    end)
end

-- includeMuted=true so a muted character stays listed (unchecked) instead
-- of disappearing along with its row -- the only way to un-mute it. The
-- current character is always in this list, even at 0 points, so it can be
-- pre-muted before it earns any.
function ns.RefreshCharactersOptions()
    local panel = ns.charactersPanel
    local charRowsY = 0 - OPTIONS_HEADER_HEIGHT

    local roster = ns.CollectKnowledgeRoster(true)

    for _, row in ipairs(panel.charRows) do
        row:Hide()
    end

    for index, entry in ipairs(roster) do
        local row = EnsureCharacterRow(panel, index)
        row.entryKey = entry.key
        row.label:SetText(entry.name)
        row:SetChecked(not entry.muted)
        PositionRow(panel, row, charRowsY - ((index - 1) * OPTIONS_ROW_HEIGHT))
        row:Show()
    end

    local charRowCount = math.max(#roster, 1)
    local charListBottomY = charRowsY - (charRowCount * OPTIONS_ROW_HEIGHT)
    panel.content:SetHeight(math.max(1, -charListBottomY + OPTIONS_BOTTOM_MARGIN))
    panel.scrollFrame:UpdateScrollChildRect()
end

local function CreateCharactersPanel()
    local panel = CreatePanelShell("MoxieTrackerCharactersPanel", "Characters",
        "Uncheck to mute a character from the Knowledge Points list. This is a global setting.")
    panel.charRows = {}
    panel:SetScript("OnShow", ns.RefreshCharactersOptions)
    ns.charactersPanel = panel
end

--------------------------------------------------------------------------
-- Character Professions subcategory: Knowledge's per-profession mute list.
-- Finer-grained than Characters -- mutes a single profession for a single
-- character without dropping the whole character from the roster.
--------------------------------------------------------------------------

local function EnsureProfessionRow(panel, index)
    return EnsureListRow(panel, panel.professionRows, index, "MoxieTrackerProfessionOption", function(self)
        ns.SetKnowledgeProfessionMuted(self.characterKey, self.professionName, not self:GetChecked())
        if ns.frame:IsShown() then
            ns.UpdateDisplay()
        end
    end)
end

-- See ns.CollectKnowledgeProfessionRoster for why a wholly-muted character
-- doesn't also appear here.
function ns.RefreshCharacterProfessionsOptions()
    local panel = ns.characterProfessionsPanel
    local professionRowsY = 0 - OPTIONS_HEADER_HEIGHT

    local professionList = ns.CollectKnowledgeProfessionRoster()

    for _, row in ipairs(panel.professionRows) do
        row:Hide()
    end

    for index, entry in ipairs(professionList) do
        local row = EnsureProfessionRow(panel, index)
        row.characterKey = entry.characterKey
        row.professionName = entry.professionName
        row.label:SetText(string.format("%s \226\128\148 %s", entry.characterName, entry.professionName))
        row:SetChecked(not entry.muted)
        PositionRow(panel, row, professionRowsY - ((index - 1) * OPTIONS_ROW_HEIGHT))
        row:Show()
    end

    if #professionList == 0 then
        panel.empty:ClearAllPoints()
        panel.empty:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, professionRowsY)
        panel.empty:Show()
    else
        panel.empty:Hide()
    end

    local professionRowCount = math.max(#professionList, 1)
    local professionListBottomY = professionRowsY - (professionRowCount * OPTIONS_ROW_HEIGHT)
    panel.content:SetHeight(math.max(1, -professionListBottomY + OPTIONS_BOTTOM_MARGIN))
    panel.scrollFrame:UpdateScrollChildRect()
end

local function CreateCharacterProfessionsPanel()
    local panel = CreatePanelShell("MoxieTrackerCharacterProfessionsPanel", "Character Professions",
        "Uncheck to mute a single profession's Knowledge for that character. This is a global setting.")
    panel.professionRows = {}
    panel.empty = panel.content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    panel.empty:SetText("No profession Knowledge recorded yet.")
    panel.empty:Hide()
    panel:SetScript("OnShow", ns.RefreshCharacterProfessionsOptions)
    ns.characterProfessionsPanel = panel
end

--------------------------------------------------------------------------
-- Concentration subcategory: Concentration's own independent
-- whole-character mute list (#40), mirroring Characters exactly but
-- against ns.SetConcentrationCharacterMuted -- muting a character's
-- Concentration never touches their Knowledge mute, and vice versa.
--------------------------------------------------------------------------

local function EnsureConcentrationCharacterRow(panel, index)
    return EnsureListRow(panel, panel.concentrationCharRows, index, "MoxieTrackerConcentrationCharacterOption",
        function(self)
            ns.SetConcentrationCharacterMuted(self.entryKey, not self:GetChecked())
            ns.UpdateConcentrationDisplay()
        end)
end

function ns.RefreshConcentrationOptions()
    local panel = ns.concentrationPanel
    local charRowsY = 0 - OPTIONS_HEADER_HEIGHT

    local concentrationRoster = ns.CollectConcentrationRoster(true)

    for _, row in ipairs(panel.concentrationCharRows) do
        row:Hide()
    end

    for index, entry in ipairs(concentrationRoster) do
        local row = EnsureConcentrationCharacterRow(panel, index)
        row.entryKey = entry.key
        row.label:SetText(entry.name)
        row:SetChecked(not entry.muted)
        PositionRow(panel, row, charRowsY - ((index - 1) * OPTIONS_ROW_HEIGHT))
        row:Show()
    end

    local charRowCount = math.max(#concentrationRoster, 1)
    local charListBottomY = charRowsY - (charRowCount * OPTIONS_ROW_HEIGHT)
    panel.content:SetHeight(math.max(1, -charListBottomY + OPTIONS_BOTTOM_MARGIN))
    panel.scrollFrame:UpdateScrollChildRect()
end

local function CreateConcentrationPanel()
    local panel = CreatePanelShell("MoxieTrackerConcentrationPanel", "Concentration",
        "Uncheck to mute a character from the Concentration list. This is a global setting.")
    panel.concentrationCharRows = {}
    panel:SetScript("OnShow", ns.RefreshConcentrationOptions)
    ns.concentrationPanel = panel
end

--------------------------------------------------------------------------
-- Concentration Professions subcategory: Concentration's per-profession
-- mute list (#40), mirroring Character Professions against
-- ns.SetConcentrationProfessionMuted.
--------------------------------------------------------------------------

local function EnsureConcentrationProfessionRow(panel, index)
    return EnsureListRow(panel, panel.concentrationProfessionRows, index,
        "MoxieTrackerConcentrationProfessionOption", function(self)
            ns.SetConcentrationProfessionMuted(self.characterKey, self.professionName, not self:GetChecked())
            ns.UpdateConcentrationDisplay()
        end)
end

function ns.RefreshConcentrationProfessionsOptions()
    local panel = ns.concentrationProfessionsPanel
    local professionRowsY = 0 - OPTIONS_HEADER_HEIGHT

    local concentrationProfessionList = ns.CollectConcentrationProfessionRoster()

    for _, row in ipairs(panel.concentrationProfessionRows) do
        row:Hide()
    end

    for index, entry in ipairs(concentrationProfessionList) do
        local row = EnsureConcentrationProfessionRow(panel, index)
        row.characterKey = entry.characterKey
        row.professionName = entry.professionName
        row.label:SetText(string.format("%s \226\128\148 %s", entry.characterName, entry.professionName))
        row:SetChecked(not entry.muted)
        PositionRow(panel, row, professionRowsY - ((index - 1) * OPTIONS_ROW_HEIGHT))
        row:Show()
    end

    if #concentrationProfessionList == 0 then
        panel.empty:ClearAllPoints()
        panel.empty:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, professionRowsY)
        panel.empty:Show()
    else
        panel.empty:Hide()
    end

    local professionRowCount = math.max(#concentrationProfessionList, 1)
    local professionListBottomY = professionRowsY - (professionRowCount * OPTIONS_ROW_HEIGHT)
    panel.content:SetHeight(math.max(1, -professionListBottomY + OPTIONS_BOTTOM_MARGIN))
    panel.scrollFrame:UpdateScrollChildRect()
end

local function CreateConcentrationProfessionsPanel()
    local panel = CreatePanelShell("MoxieTrackerConcentrationProfessionsPanel", "Concentration Professions",
        "Uncheck to mute a single profession's Concentration for that character. This is a global setting.")
    panel.concentrationProfessionRows = {}
    panel.empty = panel.content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    panel.empty:SetText("No Concentration discovered yet.")
    panel.empty:Hide()
    panel:SetScript("OnShow", ns.RefreshConcentrationProfessionsOptions)
    ns.concentrationProfessionsPanel = panel
end

--------------------------------------------------------------------------
-- Registration.
--------------------------------------------------------------------------

CreateGeneralPanel()
CreateMoxieProfessionsPanel()
CreateThresholdsPanel()
CreateCharactersPanel()
CreateCharacterProfessionsPanel()
CreateConcentrationPanel()
CreateConcentrationProfessionsPanel()

if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterCanvasLayoutSubcategory
    and Settings.RegisterAddOnCategory then
    generalCategory = Settings.RegisterCanvasLayoutCategory(ns.generalPanel, "MoxieTracker")
    Settings.RegisterAddOnCategory(generalCategory)
    Settings.RegisterCanvasLayoutSubcategory(generalCategory, ns.moxieProfessionsPanel, "Moxie Professions")
    Settings.RegisterCanvasLayoutSubcategory(generalCategory, ns.thresholdsPanel, "Thresholds")
    Settings.RegisterCanvasLayoutSubcategory(generalCategory, ns.charactersPanel, "Characters")
    Settings.RegisterCanvasLayoutSubcategory(generalCategory, ns.characterProfessionsPanel, "Character Professions")
    Settings.RegisterCanvasLayoutSubcategory(generalCategory, ns.concentrationPanel, "Concentration")
    Settings.RegisterCanvasLayoutSubcategory(generalCategory, ns.concentrationProfessionsPanel,
        "Concentration Professions")
end

function ns.OpenOptions()
    if generalCategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(generalCategory:GetID())
        return true
    end
    return false
end
