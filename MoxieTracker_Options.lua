-- Settings pages (#41): General is the top-level category, the rest are subcategories.

local _, ns = ...

-- A canvas category does not clip or scroll its content, so each page holds a
-- UIPanelScrollFrameTemplate sized explicitly (the panel's own edges read 0 in-game).
local OPTIONS_ROW_HEIGHT = 26
local OPTIONS_HEADER_HEIGHT = 20
local OPTIONS_SECTION_GAP = 6
local OPTIONS_CONTENT_WIDTH = 500
local OPTIONS_CONTENT_HEIGHT = 460
local OPTIONS_BOTTOM_MARGIN = 16

-- The three tracker windows (#40), in General-page Position row order.
local WINDOWS = {
    { key = "main", label = "Main" },
    { key = "knowledge", label = "Knowledge" },
    { key = "concentration", label = "Concentration" },
}

local generalCategory

--------------------------------------------------------------------------
-- Shared helpers.
--------------------------------------------------------------------------

-- Redraws a window only while the tracker is shown (#50).
local function IfShown(update)
    if ns.frame:IsShown() then
        update()
    end
end

-- "Label:  [box]" row. Callers wire up validation and commit handlers.
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

-- Checkbox plus label at a fixed row.
local function CreateCheckbox(parent, globalName, y, labelText, onClick)
    local checkbox = CreateFrame("CheckButton", globalName, parent, "UICheckButtonTemplate")
    checkbox:SetSize(24, 24)
    checkbox:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    checkbox.label = checkbox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    checkbox.label:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
    checkbox.label:SetText(labelText)
    checkbox:SetScript("OnClick", onClick)
    return checkbox
end

-- Pooled checkbox row for a list; positioned by the caller.
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

-- Shows one pooled checkbox row per entry from startY down; `bind` fills a row
-- from its entry. Returns the list's bottom Y, reserving one row when empty.
local function RenderCheckRows(panel, pool, frameNamePrefix, onClick, entries, startY, bind)
    for _, row in ipairs(pool) do
        row:Hide()
    end
    for index, entry in ipairs(entries) do
        local row = EnsureListRow(panel, pool, index, frameNamePrefix, onClick)
        bind(row, entry)
        PositionRow(panel, row, startY - ((index - 1) * OPTIONS_ROW_HEIGHT))
        row:Show()
    end
    return startY - (math.max(#entries, 1) * OPTIONS_ROW_HEIGHT)
end

-- Shows the page's "nothing here" text at `y` when the list is empty.
local function UpdateEmptyText(panel, isEmpty, y)
    if isEmpty then
        panel.empty:ClearAllPoints()
        panel.empty:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, y)
        panel.empty:Show()
    else
        panel.empty:Hide()
    end
end

-- Sizes the scroll child to the content. Floored at 1: a zero-height scroll child
-- is not scrollable. UpdateScrollChildRect is needed because a ScrollFrame does not
-- reliably recompute its range when the child is resized.
local function SetContentBottom(panel, bottomY)
    panel.content:SetHeight(math.max(1, -bottomY + OPTIONS_BOTTOM_MARGIN))
    panel.scrollFrame:UpdateScrollChildRect()
end

-- One window's "Label  [X]  [Y]  [Reset]" row (#40).
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

    -- Offsets are signed, so no SetNumeric (it rejects a minus sign). The pair
    -- commits together; an empty box waiting on its pair is left alone, and only
    -- text that fails to parse is reverted.
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

    -- EditBoxes do not chain focus between siblings on their own.
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

-- Title, subtitle and scroll region shared by every page.
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

    -- No SetPoint on the scroll child: anchoring it manually fights SetScrollChild
    -- (GetLeft/GetTop read nil in-game). SetSize before SetScrollChild is enough.
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(OPTIONS_CONTENT_WIDTH, 1)
    scrollFrame:SetScrollChild(content)
    panel.content = content

    panel:Hide()
    return panel
end

--------------------------------------------------------------------------
-- General page: visibility checkboxes, window positions, tracked-row list.
--------------------------------------------------------------------------

local OPTIONS_LOGIN_ROW_Y = 0
local OPTIONS_MOXIE_ROW_Y = OPTIONS_LOGIN_ROW_Y - OPTIONS_ROW_HEIGHT
local OPTIONS_KNOWLEDGE_WINDOW_ROW_Y = OPTIONS_MOXIE_ROW_Y - OPTIONS_ROW_HEIGHT
local OPTIONS_CONCENTRATION_WINDOW_ROW_Y = OPTIONS_KNOWLEDGE_WINDOW_ROW_Y - OPTIONS_ROW_HEIGHT

-- Position header (sharing its row with the X/Y column labels), then one row per window.
local OPTIONS_POSITION_HEADER_Y = OPTIONS_CONCENTRATION_WINDOW_ROW_Y - OPTIONS_ROW_HEIGHT
local OPTIONS_POSITION_MAIN_ROW_Y = OPTIONS_POSITION_HEADER_Y - OPTIONS_HEADER_HEIGHT
local OPTIONS_POSITION_KNOWLEDGE_ROW_Y = OPTIONS_POSITION_MAIN_ROW_Y - OPTIONS_ROW_HEIGHT
local OPTIONS_POSITION_CONCENTRATION_ROW_Y = OPTIONS_POSITION_KNOWLEDGE_ROW_Y - OPTIONS_ROW_HEIGHT

local OPTIONS_FIRST_ROW_Y = OPTIONS_POSITION_CONCENTRATION_ROW_Y - OPTIONS_ROW_HEIGHT - OPTIONS_SECTION_GAP

local function OnTrackedRowClick(self)
    ns.SetHidden(self.entryKey, not self:GetChecked())
    IfShown(ns.UpdateDisplay)
end

local function BindEntryRow(row, entry)
    row.entryKey = entry.key
    row.label:SetText(entry.name)
    row:SetChecked(not entry.hidden)
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
    local bottomY = RenderCheckRows(panel, panel.rows, "MoxieTrackerOption", OnTrackedRowClick,
        tracked, OPTIONS_FIRST_ROW_Y, BindEntryRow)
    UpdateEmptyText(panel, #tracked == 0, OPTIONS_FIRST_ROW_Y)
    SetContentBottom(panel, bottomY)
end

-- Called after a window is dragged, so an open General page shows the new position
-- without a full refresh (which would reset the scroll position). A box with
-- keyboard focus is left alone.
function ns.RefreshPositionField(windowKey)
    local panel = ns.generalPanel
    if not panel:IsShown() then
        return
    end
    local fields = panel.positionFields[windowKey]
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

    panel.loginCheckbox = CreateCheckbox(content, "MoxieTrackerLoginMessageOption", OPTIONS_LOGIN_ROW_Y,
        "Show version message at login", function(self)
            MoxieTrackerDB.suppressLoginMessage = not self:GetChecked()
        end)

    -- Master Moxie toggle (#43); the Moxie Professions page applies only while it is on.
    panel.moxieCheckbox = CreateCheckbox(content, "MoxieTrackerMoxieOption", OPTIONS_MOXIE_ROW_Y,
        "Show Moxie", function(self)
            MoxieTrackerDB.hideMoxie = not self:GetChecked()
            IfShown(ns.UpdateDisplay)
        end)

    panel.knowledgeWindowCheckbox = CreateCheckbox(content, "MoxieTrackerKnowledgeWindowOption",
        OPTIONS_KNOWLEDGE_WINDOW_ROW_Y, "Show Knowledge Points window", function(self)
            MoxieTrackerDB.hideKnowledgeWindow = not self:GetChecked()
            IfShown(ns.UpdateKnowledgeDisplay)
        end)

    panel.concentrationWindowCheckbox = CreateCheckbox(content, "MoxieTrackerConcentrationWindowOption",
        OPTIONS_CONCENTRATION_WINDOW_ROW_Y, "Show Concentration window", function(self)
            MoxieTrackerDB.hideConcentrationWindow = not self:GetChecked()
            IfShown(ns.UpdateConcentrationDisplay)
            ns.RefreshConcentrationTicker()
        end)

    local positionHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    positionHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 0, OPTIONS_POSITION_HEADER_Y)
    positionHeader:SetText("Position")

    -- Column labels above CreatePositionRow's boxes: X box at 16+90+4 = 110,
    -- Y box at 110+50+8 = 168.
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

    panel.empty = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    panel.empty:SetText("Nothing to configure yet - open a profession or collect a tracked item.")
    panel.empty:Hide()

    panel:SetScript("OnShow", ns.RefreshGeneralOptions)
    ns.generalPanel = panel
end

--------------------------------------------------------------------------
-- Moxie Professions page (#43): all eleven professions, account-wide, keyed by
-- currency ID through ns.IsHidden/ns.SetHidden.
--------------------------------------------------------------------------

function ns.RefreshMoxieProfessionsOptions()
    local panel = ns.moxieProfessionsPanel
    local bottomY = RenderCheckRows(panel, panel.moxieProfessionRows, "MoxieTrackerMoxieProfessionOption",
        OnTrackedRowClick, ns.MOXIE_PROFESSIONS, 0 - OPTIONS_HEADER_HEIGHT, function(row, profession)
            local entryKey = ns.EntryKey(profession.id, nil, nil)
            row.entryKey = entryKey
            local info = C_CurrencyInfo.GetCurrencyInfo(profession.id)
            row.label:SetText((info and info.name) or profession.name)
            row:SetChecked(not ns.IsHidden(entryKey))
        end)
    SetContentBottom(panel, bottomY)
end

local function CreateMoxieProfessionsPanel()
    local panel = CreatePanelShell("MoxieTrackerMoxieProfessionsPanel", "Moxie Professions",
        "Uncheck to hide a single profession's Moxie from the tracker. This is a global setting.")
    panel.moxieProfessionRows = {}
    panel:SetScript("OnShow", ns.RefreshMoxieProfessionsOptions)
    ns.moxieProfessionsPanel = panel
end

--------------------------------------------------------------------------
-- Thresholds page: every colour threshold and one reset button.
--------------------------------------------------------------------------

local OPTIONS_THRESHOLD_UA_ROW_Y = 0
local OPTIONS_THRESHOLD_MOXIE_ROW_Y = OPTIONS_THRESHOLD_UA_ROW_Y - OPTIONS_ROW_HEIGHT
local OPTIONS_THRESHOLD_FV_ROW_Y = OPTIONS_THRESHOLD_MOXIE_ROW_Y - OPTIONS_ROW_HEIGHT

-- Concentration section (#48, #49).
local OPTIONS_THRESHOLD_CONCENTRATION_HEADER_Y = OPTIONS_THRESHOLD_FV_ROW_Y - OPTIONS_ROW_HEIGHT
local OPTIONS_THRESHOLD_HIDE_ROW_Y = OPTIONS_THRESHOLD_CONCENTRATION_HEADER_Y - OPTIONS_HEADER_HEIGHT
local OPTIONS_THRESHOLD_CONCENTRATION_FIRST_Y = OPTIONS_THRESHOLD_HIDE_ROW_Y - OPTIONS_ROW_HEIGHT
local OPTIONS_THRESHOLD_RESET_Y = OPTIONS_THRESHOLD_CONCENTRATION_FIRST_Y
    - (#ns.CONCENTRATION_PROFESSIONS * OPTIONS_ROW_HEIGHT)

function ns.RefreshThresholdsOptions()
    local panel = ns.thresholdsPanel
    panel.hideUnderThresholdCheckbox:SetChecked(MoxieTrackerDB.hideConcentrationUnderThreshold or false)
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

    -- SetNumeric(true) rejects anything but digits; an empty box is caught by tonumber().
    local unalloyedEditBox = CreateSettingField(content, OPTIONS_THRESHOLD_UA_ROW_Y, "Unalloyed Abundance")
    local moxieEditBox = CreateSettingField(content, OPTIONS_THRESHOLD_MOXIE_ROW_Y, "Moxie")
    local fusedVitalityEditBox = CreateSettingField(content, OPTIONS_THRESHOLD_FV_ROW_Y, "Fused Vitality")
    for _, box in ipairs({ unalloyedEditBox, moxieEditBox, fusedVitalityEditBox }) do
        box:SetNumeric(true)
    end
    panel.unalloyedEditBox = unalloyedEditBox
    panel.moxieEditBox = moxieEditBox
    panel.fusedVitalityEditBox = fusedVitalityEditBox

    local concentrationHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    concentrationHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 0, OPTIONS_THRESHOLD_CONCENTRATION_HEADER_Y)
    concentrationHeader:SetText("Concentration")

    -- A display filter, not a threshold, so "Reset thresholds" leaves it alone.
    panel.hideUnderThresholdCheckbox = CreateCheckbox(content, "MoxieTrackerHideConcentrationUnderThresholdOption",
        OPTIONS_THRESHOLD_HIDE_ROW_Y, "Hide Concentration values under threshold", function(self)
            MoxieTrackerDB.hideConcentrationUnderThreshold = self:GetChecked() and true or nil
            IfShown(ns.UpdateConcentrationDisplay)
        end)

    -- Each threshold commits on its own; one bad entry does not revert the others.
    local function CommitThreshold(box, key)
        local value = tonumber(box:GetText())
        if not value then
            box:SetText(tostring(ns.GetThreshold(key)))
            return
        end
        MoxieTrackerDB.thresholds[key] = value
        if ns.frame:IsShown() then
            ns.UpdateDisplay()
            if key:find("^concentration:") then
                ns.UpdateConcentrationDisplay()
            end
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
        MoxieTrackerDB.thresholds = {}
        for _, field in ipairs(thresholdFields) do
            field.box:SetText(tostring(ns.GetThreshold(field.key)))
        end
        if ns.frame:IsShown() then
            ns.UpdateDisplay()
            ns.UpdateConcentrationDisplay()
        end
    end)

    -- Fixed layout, so the scroll child is sized once.
    SetContentBottom(panel, OPTIONS_THRESHOLD_RESET_Y)

    panel:SetScript("OnShow", ns.RefreshThresholdsOptions)
    ns.thresholdsPanel = panel
end

--------------------------------------------------------------------------
-- Characters page: Knowledge whole-character mutes.
--------------------------------------------------------------------------

-- Bound to roster entries ({ key, name, muted }) on the Characters and Concentration pages.
local function BindCharacterRow(row, entry)
    row.entryKey = entry.key
    row.label:SetText(entry.name)
    row:SetChecked(not entry.muted)
end

-- Bound to profession-roster entries on the two profession-mute pages.
local function BindProfessionRow(row, entry)
    row.characterKey = entry.characterKey
    row.professionName = entry.professionName
    row.label:SetText(string.format("%s \226\128\148 %s", entry.characterName, entry.professionName))
    row:SetChecked(not entry.muted)
end

local function OnCharacterRowClick(self)
    ns.SetCharacterMuted(self.entryKey, not self:GetChecked())
    IfShown(ns.UpdateDisplay)
end

-- Muted characters stay listed (unchecked) so they can be un-muted. The current
-- character is always listed, even at 0 points.
function ns.RefreshCharactersOptions()
    local panel = ns.charactersPanel
    local bottomY = RenderCheckRows(panel, panel.charRows, "MoxieTrackerCharacterOption", OnCharacterRowClick,
        ns.CollectKnowledgeRoster(true), 0 - OPTIONS_HEADER_HEIGHT, BindCharacterRow)
    SetContentBottom(panel, bottomY)
end

local function CreateCharactersPanel()
    local panel = CreatePanelShell("MoxieTrackerCharactersPanel", "Characters",
        "Uncheck to mute a character from the Knowledge Points list. This is a global setting.")
    panel.charRows = {}
    panel:SetScript("OnShow", ns.RefreshCharactersOptions)
    ns.charactersPanel = panel
end

--------------------------------------------------------------------------
-- Character Professions page: Knowledge per-profession mutes.
--------------------------------------------------------------------------

local function OnProfessionRowClick(self)
    ns.SetKnowledgeProfessionMuted(self.characterKey, self.professionName, not self:GetChecked())
    IfShown(ns.UpdateDisplay)
end

function ns.RefreshCharacterProfessionsOptions()
    local panel = ns.characterProfessionsPanel
    local startY = 0 - OPTIONS_HEADER_HEIGHT
    local professionList = ns.CollectKnowledgeProfessionRoster()
    local bottomY = RenderCheckRows(panel, panel.professionRows, "MoxieTrackerProfessionOption",
        OnProfessionRowClick, professionList, startY, BindProfessionRow)
    UpdateEmptyText(panel, #professionList == 0, startY)
    SetContentBottom(panel, bottomY)
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
-- Concentration page (#40): Concentration whole-character mutes.
--------------------------------------------------------------------------

local function OnConcentrationCharacterRowClick(self)
    ns.SetConcentrationCharacterMuted(self.entryKey, not self:GetChecked())
    IfShown(ns.UpdateConcentrationDisplay)
end

function ns.RefreshConcentrationOptions()
    local panel = ns.concentrationPanel
    local bottomY = RenderCheckRows(panel, panel.concentrationCharRows, "MoxieTrackerConcentrationCharacterOption",
        OnConcentrationCharacterRowClick, ns.CollectConcentrationRoster(true), 0 - OPTIONS_HEADER_HEIGHT,
        BindCharacterRow)
    SetContentBottom(panel, bottomY)
end

local function CreateConcentrationPanel()
    local panel = CreatePanelShell("MoxieTrackerConcentrationPanel", "Concentration",
        "Uncheck to mute a character from the Concentration list. This is a global setting.")
    panel.concentrationCharRows = {}
    panel:SetScript("OnShow", ns.RefreshConcentrationOptions)
    ns.concentrationPanel = panel
end

--------------------------------------------------------------------------
-- Concentration Professions page (#40): Concentration per-profession mutes.
--------------------------------------------------------------------------

local function OnConcentrationProfessionRowClick(self)
    ns.SetConcentrationProfessionMuted(self.characterKey, self.professionName, not self:GetChecked())
    IfShown(ns.UpdateConcentrationDisplay)
end

function ns.RefreshConcentrationProfessionsOptions()
    local panel = ns.concentrationProfessionsPanel
    local startY = 0 - OPTIONS_HEADER_HEIGHT
    local professionList = ns.CollectConcentrationProfessionRoster()
    local bottomY = RenderCheckRows(panel, panel.concentrationProfessionRows,
        "MoxieTrackerConcentrationProfessionOption", OnConcentrationProfessionRowClick, professionList, startY,
        BindProfessionRow)
    UpdateEmptyText(panel, #professionList == 0, startY)
    SetContentBottom(panel, bottomY)
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
-- Character Order page (#51): one order shared by both roster windows.
--------------------------------------------------------------------------

local OPTIONS_CHARACTER_ORDER_RESET_Y = 0
local OPTIONS_CHARACTER_ORDER_FIRST_ROW_Y = OPTIONS_CHARACTER_ORDER_RESET_Y - OPTIONS_ROW_HEIGHT - OPTIONS_SECTION_GAP

local function RedrawRosters()
    ns.UpdateKnowledgeDisplay()
    ns.UpdateConcentrationDisplay()
end

-- Swaps a character with its neighbour and saves the whole resulting order, which
-- also fixes any alphabetically appended characters into place.
local function MoveCharacterOrder(entryKey, direction)
    local roster = ns.CollectKnownCharacters()
    local index
    for i, entry in ipairs(roster) do
        if entry.key == entryKey then
            index = i
            break
        end
    end
    if not index then
        return
    end

    local swapWith = index + direction
    if swapWith < 1 or swapWith > #roster then
        return
    end

    roster[index], roster[swapWith] = roster[swapWith], roster[index]

    local newOrder = {}
    for i, entry in ipairs(roster) do
        newOrder[i] = entry.key
    end
    ns.SetCharacterOrder(newOrder)

    ns.RefreshCharacterOrderOptions()
    IfShown(RedrawRosters)
end

-- Label plus Up/Down buttons in a container frame, so not built on EnsureListRow.
local function EnsureCharacterOrderRow(panel, index)
    local row = panel.orderRows[index]
    if not row then
        row = CreateFrame("Frame", nil, panel.content)
        row:SetSize(OPTIONS_CONTENT_WIDTH, OPTIONS_ROW_HEIGHT)

        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.label:SetPoint("LEFT", row, "LEFT", 16, 0)
        row.label:SetWidth(150)
        row.label:SetJustifyH("LEFT")

        row.upButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.upButton:SetSize(40, 20)
        row.upButton:SetText("Up")
        row.upButton:SetPoint("LEFT", row.label, "RIGHT", 8, 0)
        row.upButton:SetScript("OnClick", function()
            MoveCharacterOrder(row.entryKey, -1)
        end)

        row.downButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.downButton:SetSize(40, 20)
        row.downButton:SetText("Down")
        row.downButton:SetPoint("LEFT", row.upButton, "RIGHT", 4, 0)
        row.downButton:SetScript("OnClick", function()
            MoveCharacterOrder(row.entryKey, 1)
        end)

        panel.orderRows[index] = row
    end
    return row
end

function ns.RefreshCharacterOrderOptions()
    local panel = ns.characterOrderPanel

    local roster = ns.CollectKnownCharacters()

    for _, row in ipairs(panel.orderRows) do
        row:Hide()
    end

    for index, entry in ipairs(roster) do
        local row = EnsureCharacterOrderRow(panel, index)
        row.entryKey = entry.key
        row.label:SetText(entry.name)
        row.upButton:SetEnabled(index > 1)
        row.downButton:SetEnabled(index < #roster)
        PositionRow(panel, row, OPTIONS_CHARACTER_ORDER_FIRST_ROW_Y - ((index - 1) * OPTIONS_ROW_HEIGHT))
        row:Show()
    end

    SetContentBottom(panel, OPTIONS_CHARACTER_ORDER_FIRST_ROW_Y - (math.max(#roster, 1) * OPTIONS_ROW_HEIGHT))
end

local function CreateCharacterOrderPanel()
    local panel = CreatePanelShell("MoxieTrackerCharacterOrderPanel", "Character Order",
        "Controls the order characters are listed in the Knowledge Points and Concentration windows. Defaults " ..
            "to alphabetical; use Up/Down to customize. This is a global setting.")
    panel.orderRows = {}

    local resetOrderButton = CreateFrame("Button", nil, panel.content, "UIPanelButtonTemplate")
    resetOrderButton:SetSize(140, 22)
    resetOrderButton:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 16, OPTIONS_CHARACTER_ORDER_RESET_Y)
    resetOrderButton:SetText("Reset to alphabetical")
    resetOrderButton:SetScript("OnClick", function()
        ns.ClearCharacterOrder()
        ns.RefreshCharacterOrderOptions()
        IfShown(RedrawRosters)
    end)

    panel:SetScript("OnShow", ns.RefreshCharacterOrderOptions)
    ns.characterOrderPanel = panel
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
CreateCharacterOrderPanel()

generalCategory = Settings.RegisterCanvasLayoutCategory(ns.generalPanel, "MoxieTracker")
Settings.RegisterAddOnCategory(generalCategory)
Settings.RegisterCanvasLayoutSubcategory(generalCategory, ns.moxieProfessionsPanel, "Moxie Professions")
Settings.RegisterCanvasLayoutSubcategory(generalCategory, ns.thresholdsPanel, "Thresholds")
Settings.RegisterCanvasLayoutSubcategory(generalCategory, ns.charactersPanel, "Characters")
Settings.RegisterCanvasLayoutSubcategory(generalCategory, ns.characterProfessionsPanel, "Character Professions")
Settings.RegisterCanvasLayoutSubcategory(generalCategory, ns.concentrationPanel, "Concentration")
Settings.RegisterCanvasLayoutSubcategory(generalCategory, ns.concentrationProfessionsPanel,
    "Concentration Professions")
Settings.RegisterCanvasLayoutSubcategory(generalCategory, ns.characterOrderPanel, "Character Order")

function ns.OpenOptions()
    Settings.OpenToCategory(generalCategory:GetID())
end
