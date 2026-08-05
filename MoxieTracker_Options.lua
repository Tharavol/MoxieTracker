-- Depends on MoxieTracker_Config.lua, MoxieTracker_Collect.lua, and
-- MoxieTracker_UI.lua, loaded first per the TOC. The options panel, including
-- the Position and Color thresholds sections and the row-list scroll frame.
local _, ns = ...

-- The row list is rebuilt every time the panel is shown rather than built
-- once at load, because what is trackable changes: moxie rows exist only for
-- professions the character has, and the keyword fallback can turn up a
-- currency no ID table knows about.
local OPTIONS_ROW_HEIGHT = 26
local OPTIONS_HEADER_HEIGHT = 20
local OPTIONS_SECTION_GAP = 6
local OPTIONS_LOGIN_ROW_Y = -72

-- Position section: a header, two offset fields, and a reset button.
local OPTIONS_POSITION_HEADER_Y = OPTIONS_LOGIN_ROW_Y - OPTIONS_ROW_HEIGHT
local OPTIONS_POSITION_X_ROW_Y = OPTIONS_POSITION_HEADER_Y - OPTIONS_HEADER_HEIGHT
local OPTIONS_POSITION_Y_ROW_Y = OPTIONS_POSITION_X_ROW_Y - OPTIONS_ROW_HEIGHT
local OPTIONS_POSITION_RESET_Y = OPTIONS_POSITION_Y_ROW_Y - OPTIONS_ROW_HEIGHT

-- Threshold section: a header, three threshold fields, and a reset button.
local OPTIONS_THRESHOLD_HEADER_Y = OPTIONS_POSITION_RESET_Y - OPTIONS_ROW_HEIGHT - OPTIONS_SECTION_GAP
local OPTIONS_THRESHOLD_UA_ROW_Y = OPTIONS_THRESHOLD_HEADER_Y - OPTIONS_HEADER_HEIGHT
local OPTIONS_THRESHOLD_MOXIE_ROW_Y = OPTIONS_THRESHOLD_UA_ROW_Y - OPTIONS_ROW_HEIGHT
local OPTIONS_THRESHOLD_FV_ROW_Y = OPTIONS_THRESHOLD_MOXIE_ROW_Y - OPTIONS_ROW_HEIGHT
local OPTIONS_THRESHOLD_RESET_Y = OPTIONS_THRESHOLD_FV_ROW_Y - OPTIONS_ROW_HEIGHT

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

local function EnsureOptionRow(index)
    local row = ns.optionsPanel.rows[index]
    if not row then
        -- Parented to the scroll frame's content child, not the panel: rows
        -- need to scroll with the list, not sit fixed against the canvas.
        row = CreateFrame("CheckButton", "MoxieTrackerOption" .. index,
            ns.optionsPanel.rowsContent, "UICheckButtonTemplate")
        row:SetSize(24, 24)
        row:SetPoint("TOPLEFT", ns.optionsPanel.rowsContent, "TOPLEFT", 0, -((index - 1) * OPTIONS_ROW_HEIGHT))

        -- An explicit label rather than the template's own text region, whose
        -- name has moved between expansions.
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.label:SetPoint("LEFT", row, "RIGHT", 4, 0)

        row:SetScript("OnClick", function(self)
            ns.SetHidden(self.entryKey, not self:GetChecked())
            if ns.frame:IsShown() then
                ns.UpdateDisplay()
            end
        end)

        ns.optionsPanel.rows[index] = row
    end
    return row
end

function ns.RefreshOptions()
    ns.optionsPanel.loginCheckbox:SetChecked(not MoxieTrackerDB.suppressLoginMessage)

    local offsetX, offsetY = ns.GetOffset()
    ns.optionsPanel.xEditBox:SetText(tostring(offsetX))
    ns.optionsPanel.yEditBox:SetText(tostring(offsetY))

    ns.optionsPanel.unalloyedEditBox:SetText(tostring(ns.GetThreshold("unalloyedAbundance")))
    ns.optionsPanel.moxieEditBox:SetText(tostring(ns.GetThreshold("moxie")))
    ns.optionsPanel.fusedVitalityEditBox:SetText(tostring(ns.GetThreshold("fusedVitality")))

    local tracked = ns.CollectTracked(true)

    for _, row in ipairs(ns.optionsPanel.rows) do
        row:Hide()
    end

    for index, entry in ipairs(tracked) do
        local row = EnsureOptionRow(index)
        row.entryKey = entry.key
        row.label:SetText(entry.name)
        row:SetChecked(not entry.hidden)
        row:Show()
    end

    -- Content height drives whether the scroll frame's bar is usable at all;
    -- floored at 1 rather than 0, since a zero-height scroll child is what
    -- some client versions treat as "not scrollable" even once rows appear.
    ns.optionsPanel.rowsContent:SetHeight(math.max(1, #tracked * OPTIONS_ROW_HEIGHT))

    if #tracked == 0 then
        ns.optionsPanel.empty:Show()
    else
        ns.optionsPanel.empty:Hide()
    end
end

local function CreateOptionsPanel()
    local panel = CreateFrame("Frame", "MoxieTrackerOptionsPanel", UIParent)
    panel.name = "MoxieTracker"
    panel.rows = {}

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    title:SetText("MoxieTracker " .. ns.GetVersion())

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

    local positionHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    positionHeader:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, OPTIONS_POSITION_HEADER_Y)
    positionHeader:SetText("Position")

    -- Offsets are signed (the default vertical offset is -440), so these are
    -- plain EditBoxes with manual tonumber() validation rather than
    -- SetNumeric(true), which does not allow a minus sign.
    local xEditBox = CreateSettingField(panel, OPTIONS_POSITION_X_ROW_Y, "Horizontal offset")
    local yEditBox = CreateSettingField(panel, OPTIONS_POSITION_Y_ROW_Y, "Vertical offset")
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

    local resetPositionButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetPositionButton:SetSize(120, 22)
    resetPositionButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, OPTIONS_POSITION_RESET_Y)
    resetPositionButton:SetText("Reset position")
    resetPositionButton:SetScript("OnClick", function()
        ns.ResetPosition()
        local x, y = ns.GetOffset()
        xEditBox:SetText(tostring(x))
        yEditBox:SetText(tostring(y))
    end)

    local thresholdHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    thresholdHeader:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, OPTIONS_THRESHOLD_HEADER_Y)
    thresholdHeader:SetText("Color thresholds")

    -- Thresholds are always non-negative, so SetNumeric(true) is enough
    -- validation on its own; a cleared box (empty string) still needs the
    -- same tonumber() nil-check as the position fields.
    local unalloyedEditBox = CreateSettingField(panel, OPTIONS_THRESHOLD_UA_ROW_Y, "Unalloyed Abundance")
    local moxieEditBox = CreateSettingField(panel, OPTIONS_THRESHOLD_MOXIE_ROW_Y, "Moxie")
    local fusedVitalityEditBox = CreateSettingField(panel, OPTIONS_THRESHOLD_FV_ROW_Y, "Fused Vitality")
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

    local resetThresholdsButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetThresholdsButton:SetSize(120, 22)
    resetThresholdsButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, OPTIONS_THRESHOLD_RESET_Y)
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

    -- The row-visibility checkboxes scroll: the Position and Threshold
    -- sections above already push the fixed header content close to a full
    -- canvas, and the keyword fallback can add rows beyond what any fixed
    -- layout could guarantee fits. UIPanelScrollFrameTemplate brings its own
    -- scrollbar, so there is no custom scroll code to maintain.
    --
    -- Height is explicit rather than anchored to the panel's bottom edge:
    -- canvas settings categories are not guaranteed to stretch the frame we
    -- register to fill the available area, and an unresolved BOTTOMRIGHT
    -- anchor against an unsized panel silently produces a zero-height (and
    -- so invisible) scroll frame rather than an error.
    local OPTIONS_SCROLL_HEIGHT = 260
    local scrollFrame = CreateFrame("ScrollFrame", "MoxieTrackerOptionsScrollFrame", panel,
        "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, OPTIONS_FIRST_ROW_Y)
    scrollFrame:SetPoint("RIGHT", panel, "RIGHT", -32, 0)
    scrollFrame:SetHeight(OPTIONS_SCROLL_HEIGHT)

    local rowsContent = CreateFrame("Frame", nil, scrollFrame)
    rowsContent:SetPoint("TOPLEFT")
    rowsContent:SetPoint("TOPRIGHT")
    rowsContent:SetHeight(1)
    scrollFrame:SetScrollChild(rowsContent)
    panel.rowsContent = rowsContent

    panel.empty = rowsContent:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    panel.empty:SetPoint("TOPLEFT", rowsContent, "TOPLEFT", 0, 0)
    panel.empty:SetText("Nothing to configure yet - open a profession or log in on a character with moxie.")
    panel.empty:Hide()

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
