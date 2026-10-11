--[[
    Xius Threat Meter - Options.lua
    Settings window (gear button, menu entry or /xtm config).
]]

local ADDON, NS = ...

local COLOR = NS.COLOR
local WHITE = NS.WHITE
local TEMPLATE = NS.BACKDROP_TEMPLATE

local PANEL_WIDTH = 320
local CONTENT_WIDTH = 270
local LEFT = 22

local panel
local widgets = {}

local function SectionHeader(parent, text, y)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    NS.SetFont(fs, 12)
    fs:SetTextColor(COLOR.gold[1], COLOR.gold[2], COLOR.gold[3])
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT, y)
    fs:SetText(text)

    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetTexture(WHITE)
    line:SetHeight(1)
    line:SetPoint("LEFT", fs, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", parent, "RIGHT", -LEFT, 0)
    line:SetVertexColor(COLOR.goldLine[1], COLOR.goldLine[2], COLOR.goldLine[3], 0.45)
    return y - 22
end

local function CreateCheck(parent, label, key, y, tip)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT - 4, y)

    local text = cb:CreateFontString(nil, "OVERLAY")
    NS.SetFont(text, 12)
    text:SetTextColor(1, 1, 1)
    text:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    text:SetText(label)

    cb:SetScript("OnClick", function(self)
        NS.db[key] = self:GetChecked() and true or false
        NS.ApplySettings()
    end)
    if tip then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 0.82, 0)
            GameTooltip:AddLine(tip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    widgets[#widgets + 1] = function()
        cb:SetChecked(NS.db[key] and true or false)
    end
    return y - 26
end

local function CreateSlider(parent, label, key, minV, maxV, step, formatter, y)
    local text = parent:CreateFontString(nil, "OVERLAY")
    NS.SetFont(text, 12)
    text:SetTextColor(1, 1, 1)
    text:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT, y)
    text:SetText(label)

    local valueText = parent:CreateFontString(nil, "OVERLAY")
    NS.SetFont(valueText, 12)
    valueText:SetTextColor(COLOR.gold[1], COLOR.gold[2], COLOR.gold[3])
    valueText:SetPoint("TOPRIGHT", parent, "TOPLEFT", LEFT + CONTENT_WIDTH, y)

    local s = CreateFrame("Slider", nil, parent, TEMPLATE)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(CONTENT_WIDTH, 16)
    s:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT, y - 18)
    NS.ApplyBackdrop(s, NS.BACKDROP_SLIDER, { 1, 1, 1, 1 }, { 1, 1, 1, 1 })
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then
        s:SetObeyStepOnDrag(true)
    end
    s:EnableMouseWheel(true)
    s:SetScript("OnMouseWheel", function(self, delta)
        local v = self:GetValue() + delta * step
        if v < minV then
            v = minV
        elseif v > maxV then
            v = maxV
        end
        self:SetValue(v)
    end)
    s:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v / step + 0.5) * step
        valueText:SetText(formatter(v))
        if self.updating then
            return
        end
        if NS.db[key] ~= v then
            NS.db[key] = v
            NS.ApplySettings()
        end
    end)

    widgets[#widgets + 1] = function()
        s.updating = true
        s:SetValue(NS.db[key])
        valueText:SetText(formatter(NS.db[key]))
        s.updating = false
    end
    return y - 44
end

local function CreateButton(parent, label, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
end

local function FormatInt(v)
    return tostring(math.floor(v + 0.5))
end

local function FormatPercent(v)
    return string.format("%d%%", math.floor(v * 100 + 0.5))
end

local function FormatThreshold(v)
    return string.format("%d%%", math.floor(v + 0.5))
end

local function FormatScale(v)
    return string.format("%.2f", v)
end

local function BuildPanel()
    panel = CreateFrame("Frame", "XiusThreatMeterOptions", UIParent, TEMPLATE)
    panel:SetFrameStrata("DIALOG")
    panel:SetWidth(PANEL_WIDTH)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    NS.CreateWindowBackground(panel)
    NS.SetWindowAlpha(panel, 0.97)
    panel:Hide()
    tinsert(UISpecialFrames, "XiusThreatMeterOptions")

    local titleBar = NS.CreateTitleBar(panel, 34)

    local title = titleBar:CreateFontString(nil, "OVERLAY")
    NS.SetFont(title, 15)
    title:SetTextColor(COLOR.gold[1], COLOR.gold[2], COLOR.gold[3])
    title:SetPoint("LEFT", titleBar, "LEFT", 12, 0)
    title:SetText("Threat Meter Settings")

    local close = CreateFrame("Button", nil, titleBar)
    close:SetSize(24, 24)
    close:SetPoint("RIGHT", titleBar, "RIGHT", -6, 0)
    NS.StyleButton(close, true)
    local x = close:CreateFontString(nil, "OVERLAY")
    NS.SetFont(x, 13)
    x:SetTextColor(COLOR.dash[1], COLOR.dash[2], COLOR.dash[3])
    x:SetPoint("CENTER", 0, 0)
    x:SetText("X")
    close:SetScript("OnEnter", function(self)
        NS.SetButtonHover(self, true)
    end)
    close:SetScript("OnLeave", function(self)
        NS.SetButtonHover(self, false)
    end)
    close:SetScript("OnClick", function()
        panel:Hide()
    end)

    local y = -46

    y = SectionHeader(panel, "Window", y)
    y = CreateCheck(panel, "Lock window", "locked", y, "Stops the window from being moved or resized.")
    y = CreateCheck(panel, "Only show when there is threat", "onlyWithThreat", y,
        "The window pops up when an enemy you are fighting has threat on your group, and hides again when there is none.")
    y = CreateCheck(panel, "Hide when out of combat", "hideOutOfCombat", y, "Only show the window while you are in combat.")
    y = CreateCheck(panel, "Only show in a group", "onlyInGroup", y, "Hide the window while you are playing solo.")
    y = y - 4
    y = CreateSlider(panel, "Window scale", "scale", 0.5, 2, 0.05, FormatScale, y)
    y = CreateSlider(panel, "Background opacity", "bgAlpha", 0, 1, 0.05, FormatPercent, y)

    y = y - 4
    y = SectionHeader(panel, "Bars", y)
    y = CreateCheck(panel, "Show class icons", "showIcons", y)
    y = CreateCheck(panel, "Show pets", "showPets", y, "Include hunter and warlock pets in the list.")
    y = CreateCheck(panel, "Show threat numbers", "showValues", y, "Show the threat amount next to the percentage.")
    y = y - 4
    y = CreateSlider(panel, "Bar height", "barHeight", 12, 32, 1, FormatInt, y)
    y = CreateSlider(panel, "Bar spacing", "barSpacing", 0, 8, 1, FormatInt, y)

    y = y - 4
    y = SectionHeader(panel, "Aggro Warning", y)
    y = CreateCheck(panel, "Warn me before I pull aggro", "warnEnabled", y,
        "Plays a warning sound and turns the window title red when your threat gets close to the tank's.")
    y = y - 4
    y = CreateSlider(panel, "Warning at", "warnThreshold", 50, 100, 5, FormatThreshold, y)

    y = y - 6
    local testBtn = CreateButton(panel, "Test Mode", 130, function()
        NS.ToggleTestMode()
    end)
    testBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", LEFT, y)
    panel.testBtn = testBtn

    local resetBtn = CreateButton(panel, "Reset Position", 130, function()
        NS.ResetPosition()
    end)
    resetBtn:SetPoint("TOPRIGHT", panel, "TOPLEFT", LEFT + CONTENT_WIDTH, y)

    y = y - 34
    panel:SetHeight(-y + 6)

    panel:SetScript("OnShow", function()
        NS.RefreshOptions()
    end)
end

function NS.RefreshOptions()
    if not panel or not panel:IsShown() then
        return
    end
    for _, refresh in ipairs(widgets) do
        refresh()
    end
    panel.testBtn:SetText(NS.IsTestMode() and "Stop Test" or "Test Mode")
end

function NS.ToggleOptions()
    if not panel then
        BuildPanel()
    end
    if panel:IsShown() then
        panel:Hide()
    else
        panel:Show()
    end
end
