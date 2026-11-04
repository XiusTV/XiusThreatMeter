--[[
    Xius Threat Meter - Options.lua
    Settings window (/xtm, gear button, menu entry) and default game Options -> AddOns panel.
]]

local ADDON, NS = ...

local COLOR = NS.COLOR
local WHITE = NS.WHITE
local TEMPLATE = NS.BACKDROP_TEMPLATE
local Settings = _G.Settings
local InterfaceOptions_AddCategory = _G.InterfaceOptions_AddCategory

local PANEL_WIDTH = 320
local CONTENT_WIDTH = 270
local LEFT = 22

local BLIZZ_LEFT_X = 18
local BLIZZ_RIGHT_X = 306
local BLIZZ_COL_WIDTH = 260

local panel
local blizzPanel
local widgets = {}
local showHideButtons = {}
local testButtons = {}

local function SectionHeader(parent, text, x, width, y)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    NS.SetFont(fs, 12)
    fs:SetTextColor(COLOR.gold[1], COLOR.gold[2], COLOR.gold[3])
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetText(text)

    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetTexture(WHITE)
    line:SetHeight(1)
    line:SetPoint("LEFT", fs, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", fs, "LEFT", width, 0)
    line:SetVertexColor(COLOR.goldLine[1], COLOR.goldLine[2], COLOR.goldLine[3], 0.45)
    return y - 22
end

local function CreateCheck(parent, label, key, x, y, tip)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x - 4, y)

    local text = cb:CreateFontString(nil, "OVERLAY")
    NS.SetFont(text, 12)
    text:SetTextColor(1, 1, 1)
    text:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    text:SetText(label)

    local templateText = cb.Text
    if not templateText and cb.GetName and cb:GetName() then
        templateText = _G[cb:GetName() .. "Text"]
    end
    if templateText then
        templateText:SetText("")
        templateText:Hide()
    end

    if cb.SetHitRectInsets then
        local labelWidth = text:GetStringWidth() or 0
        if labelWidth <= 0 then
            labelWidth = #label * 6.5
        end
        if labelWidth < 100 then
            labelWidth = 100
        elseif labelWidth > 220 then
            labelWidth = 220
        end
        cb:SetHitRectInsets(0, -math.floor(labelWidth + 8), 0, 0)
    end

    cb:SetScript("OnClick", function(self)
        NS.db[key] = self:GetChecked() and true or false
        NS.ApplySettings()
        NS.RefreshOptions()
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
        if NS.db then
            cb:SetChecked(NS.db[key] and true or false)
        end
    end
    return y - 26
end

local function Snap(v, step)
    if not step or step <= 0 then
        return v
    end
    local n = math.floor(v / step + 0.5) * step
    if step < 1 then
        n = math.floor(n * 100 + 0.5) / 100
    end
    if n < 0 then
        n = 0
    end
    return n
end

local function CreateSlider(parent, label, key, minV, maxV, step, formatter, x, width, y)
    local text = parent:CreateFontString(nil, "OVERLAY")
    NS.SetFont(text, 12)
    text:SetTextColor(1, 1, 1)
    text:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    text:SetText(label)

    local valueText = parent:CreateFontString(nil, "OVERLAY")
    NS.SetFont(valueText, 12)
    valueText:SetTextColor(COLOR.gold[1], COLOR.gold[2], COLOR.gold[3])
    valueText:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + width, y)

    local s = CreateFrame("Slider", nil, parent, TEMPLATE)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(width, 16)
    s:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 18)
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
        if self.updating or not NS.db then
            return
        end
        local snapped = Snap(v, step)
        if snapped < minV then
            snapped = minV
        elseif snapped > maxV then
            snapped = maxV
        end
        if math.abs(snapped - v) > 0.0001 then
            self.updating = true
            self:SetValue(snapped)
            self.updating = false
        end
        valueText:SetText(formatter(snapped))
        if NS.db[key] ~= snapped then
            NS.db[key] = snapped
            NS.ApplySettings()
            NS.RefreshOptions()
        end
    end)

    widgets[#widgets + 1] = function()
        if not NS.db then
            return
        end
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

local function BuildWindowSection(parent, x, width, y)
    y = SectionHeader(parent, "Window", x, width, y)
    y = CreateCheck(parent, "Lock window", "locked", x, y, "Stops the window from being moved or resized.")
    y = CreateCheck(parent, "Only show when there is threat", "onlyWithThreat", x, y,
        "The window pops up when the enemy you are tracking has threat on your group, and hides again when there is none. Targeting your tank still tracks that tank's target.")
    y = CreateCheck(parent, "Hide when out of combat", "hideOutOfCombat", x, y, "Only show the window while you are in combat.")
    y = CreateCheck(parent, "Only show in a group", "onlyInGroup", x, y, "Hide the window while you are playing solo.")
    y = y - 4
    y = CreateSlider(parent, "Window scale", "scale", 0.5, 2, 0.05, FormatScale, x, width, y)
    y = CreateSlider(parent, "Background opacity", "bgAlpha", 0, 1, 0.05, FormatPercent, x, width, y)
    return y
end

local function BuildBarsAndWarningSections(parent, x, width, y)
    y = SectionHeader(parent, "Bars", x, width, y)
    y = CreateCheck(parent, "Show class icons", "showIcons", x, y)
    y = CreateCheck(parent, "Show pets", "showPets", x, y, "Include hunter and warlock pets in the list.")
    y = CreateCheck(parent, "Show threat numbers", "showValues", x, y, "Show the threat amount next to the percentage.")
    y = y - 4
    y = CreateSlider(parent, "Bar height", "barHeight", 12, 32, 1, FormatInt, x, width, y)
    y = CreateSlider(parent, "Bar spacing", "barSpacing", 0, 8, 1, FormatInt, x, width, y)

    y = y - 4
    y = SectionHeader(parent, "Aggro Warning", x, width, y)
    y = CreateCheck(parent, "Warn me before I pull aggro", "warnEnabled", x, y,
        "Plays a warning sound and turns the window title red when your threat, or your pet's threat, gets close to the tank's. When the client hides exact threat numbers, the warning follows the game's own aggro state instead of the percent slider. In test mode the title turns red, and the sound plays in a real fight.")
    y = y - 4
    y = CreateSlider(parent, "Warning at", "warnThreshold", 50, 100, 5, FormatThreshold, x, width, y)
    return y
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
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "XiusThreatMeterOptions")
    end

    local titleBar = NS.CreateTitleBar(panel, 24)

    local title = titleBar:CreateFontString(nil, "OVERLAY")
    NS.SetFont(title, 13)
    title:SetTextColor(COLOR.gold[1], COLOR.gold[2], COLOR.gold[3])
    title:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
    title:SetText("Threat Meter Settings")

    local close = CreateFrame("Button", nil, titleBar)
    close:SetSize(18, 18)
    close:SetPoint("RIGHT", titleBar, "RIGHT", -5, 0)
    NS.StyleButton(close, true)
    local x = close:CreateFontString(nil, "OVERLAY")
    NS.SetFont(x, 11)
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

    local y = -34
    y = BuildWindowSection(panel, LEFT, CONTENT_WIDTH, y)
    y = y - 4
    y = BuildBarsAndWarningSections(panel, LEFT, CONTENT_WIDTH, y)

    y = y - 6
    local showHideBtn = CreateButton(panel, "Hide Window", 130, function()
        NS.SetHidden(not NS.db.hidden)
    end)
    showHideBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", LEFT, y)
    showHideButtons[#showHideButtons + 1] = showHideBtn

    local testBtn = CreateButton(panel, "Test Mode", 130, function()
        NS.ToggleTestMode()
    end)
    testBtn:SetPoint("TOPRIGHT", panel, "TOPLEFT", LEFT + CONTENT_WIDTH, y)
    testButtons[#testButtons + 1] = testBtn

    y = y - 28
    local resetBtn = CreateButton(panel, "Reset Position", CONTENT_WIDTH, function()
        NS.ResetPosition()
    end)
    resetBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", LEFT, y)

    y = y - 32
    panel:SetHeight(-y + 6)

    panel:SetScript("OnShow", function()
        NS.RefreshOptions()
    end)
    panel:SetScript("OnHide", function(self)
        self:StopMovingOrSizing()
    end)
end

local function BuildBlizzPanel()
    if blizzPanel then
        return
    end
    blizzPanel = CreateFrame("Frame", "XiusThreatMeterBlizzOptions", UIParent)
    blizzPanel.name = "Xius Threat Meter"
    blizzPanel:Hide()

    local title = blizzPanel:CreateFontString(nil, "OVERLAY")
    NS.SetFont(title, 16)
    title:SetTextColor(COLOR.gold[1], COLOR.gold[2], COLOR.gold[3])
    title:SetPoint("TOPLEFT", blizzPanel, "TOPLEFT", BLIZZ_LEFT_X, -16)
    title:SetText("Xius Threat Meter")

    local subtitle = blizzPanel:CreateFontString(nil, "OVERLAY")
    NS.SetFont(subtitle, 11)
    subtitle:SetTextColor(COLOR.muted[1], COLOR.muted[2], COLOR.muted[3])
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subtitle:SetText("Configure window visibility, threat bars, and aggro warnings. (/xtm)")

    local startY = -56
    local leftBottomY = BuildWindowSection(blizzPanel, BLIZZ_LEFT_X, BLIZZ_COL_WIDTH, startY)
    local rightBottomY = BuildBarsAndWarningSections(blizzPanel, BLIZZ_RIGHT_X, BLIZZ_COL_WIDTH, startY)
    local btnY = math.min(leftBottomY, rightBottomY) - 10

    local showHideBtn = CreateButton(blizzPanel, "Hide Window", 130, function()
        NS.SetHidden(not NS.db.hidden)
    end)
    showHideBtn:SetPoint("TOPLEFT", blizzPanel, "TOPLEFT", BLIZZ_LEFT_X, btnY)
    showHideButtons[#showHideButtons + 1] = showHideBtn

    local testBtn = CreateButton(blizzPanel, "Test Mode", 130, function()
        NS.ToggleTestMode()
    end)
    testBtn:SetPoint("LEFT", showHideBtn, "RIGHT", 10, 0)
    testButtons[#testButtons + 1] = testBtn

    local resetBtn = CreateButton(blizzPanel, "Reset Position", 130, function()
        NS.ResetPosition()
    end)
    resetBtn:SetPoint("LEFT", testBtn, "RIGHT", 10, 0)

    blizzPanel.OnRefresh = function()
        NS.RefreshOptions()
    end
    blizzPanel.refresh = blizzPanel.OnRefresh
    blizzPanel.OnCommit = function() end
    blizzPanel.okay = blizzPanel.OnCommit
    blizzPanel.OnDefault = function()
        if NS.ResetAllSettings then
            NS.ResetAllSettings()
        end
    end
    blizzPanel.default = blizzPanel.OnDefault

    blizzPanel:SetScript("OnShow", function()
        NS.RefreshOptions()
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, blizzPanel, blizzPanel.name, blizzPanel.name)
        if ok and category then
            if not category.ID and category.GetID then
                category.ID = category:GetID()
            end
            pcall(Settings.RegisterAddOnCategory, category)
            NS.settingsCategory = category
        end
    elseif InterfaceOptions_AddCategory then
        pcall(InterfaceOptions_AddCategory, blizzPanel)
    end
end

function NS.InitOptions()
    BuildBlizzPanel()
end

function NS.RefreshOptions()
    if not panel and not blizzPanel then
        return
    end
    for _, refresh in ipairs(widgets) do
        refresh()
    end
    local showHideText = (NS.db and NS.db.hidden) and "Show Window" or "Hide Window"
    for _, btn in ipairs(showHideButtons) do
        btn:SetText(showHideText)
    end
    local testText = (NS.IsTestMode and NS.IsTestMode()) and "Stop Test" or "Test Mode"
    for _, btn in ipairs(testButtons) do
        btn:SetText(testText)
    end
end

function NS.OpenOptions()
    if not panel then
        BuildPanel()
    end
    panel:Show()
    if panel.Raise then
        panel:Raise()
    end
    NS.RefreshOptions()
end

function NS.ToggleOptions()
    if not panel then
        BuildPanel()
    end
    if panel:IsShown() then
        panel:Hide()
    else
        panel:Show()
        if panel.Raise then
            panel:Raise()
        end
    end
end
