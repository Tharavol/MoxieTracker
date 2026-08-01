local addonName, addon = ...

local frame = CreateFrame("Frame", "MoxieTrackerFrame", UIParent)
frame:SetSize(240, 70)
frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 20, 20)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetMovable(true)
frame:SetScript("OnDragStart", function(self)
    self:StartMoving()
end)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
end)

frame.background = frame:CreateTexture(nil, "BACKGROUND")
frame.background:SetAllPoints(frame)
frame.background:SetColorTexture(0, 0, 0, 0.45)
frame.background:SetDrawLayer("BACKGROUND", -1)

frame.border = CreateFrame("Frame", nil, frame)
frame.border:SetAllPoints(frame)
frame.border:SetBackdrop({
    edgeFile = "Interface\Buttons\WHITE8X8",
    edgeSize = 1,
    insets = {left = 1, right = 1, top = 1, bottom = 1},
})
frame.border:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.9)

frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
frame.title:SetText("Moxie Tracker")

frame.lines = {}

local function EnsureLine(index)
    if not frame.lines[index] then
        local line = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        line:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -(24 + ((index - 1) * 14)))
        line:SetJustifyH("LEFT")
        line:SetText("")
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
    return frame.lines[index]
end

local function IsTrackedCurrency(info)
    if not info or not info.quantity or info.quantity <= 0 then
        return false
    end

    local name = (info.name or ""):lower()
    local description = (info.description or ""):lower()
    return name:find("moxie", 1, true) ~= nil or name:find("dun'dun", 1, true) ~= nil or name:find("dun", 1, true) ~= nil or description:find("moxie", 1, true) ~= nil
end

local function UpdateDisplay()
    local tracked = {}
    local size = C_CurrencyInfo.GetCurrencyListSize and C_CurrencyInfo.GetCurrencyListSize() or 0

    for index = 1, size do
        local info = C_CurrencyInfo.GetCurrencyListInfo(index)
        if IsTrackedCurrency(info) then
            table.insert(tracked, {
                name = info.name or "Currency",
                quantity = info.quantity or 0,
                currencyType = info.currencyType,
            })
        end
    end

    table.sort(tracked, function(a, b)
        return a.name < b.name
    end)

    for index = 1, #frame.lines do
        frame.lines[index]:Hide()
    end

    if #tracked == 0 then
        local fallback = EnsureLine(1)
        fallback:SetText("No tracked currencies")
        fallback:Show()
        frame:SetHeight(56)
        return
    end

    for index, entry in ipairs(tracked) do
        local line = EnsureLine(index)
        line.currencyID = entry.currencyType
        line:SetText(string.format("%s: %d", entry.name, entry.quantity))
        line:Show()
    end

    frame:SetHeight(math.max(56, 40 + (#tracked * 14)))
end

frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
    GameTooltip:SetText("Artisan Moxie and Dun'dun Shards")
    GameTooltip:AddLine("Shows the current character's tracked currency amounts.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end)
frame:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

frame:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("CURRENCY_TRANSFER_UPDATE")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "CURRENCY_DISPLAY_UPDATE" or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_LOGIN" or event == "CURRENCY_TRANSFER_UPDATE" then
        UpdateDisplay()
    end
end)

frame:Show()
UpdateDisplay()
