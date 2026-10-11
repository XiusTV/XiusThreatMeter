--[[
    Xius Threat Meter - Core.lua
    Threat window, threat engine, header menu and slash commands.
]]

local ADDON, NS = ...

local COLOR = NS.COLOR
local WHITE = NS.WHITE
local TEMPLATE = NS.BACKDROP_TEMPLATE

local CLASS_TEXTURE = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local CHECK_TEXTURE = "Interface\\Buttons\\UI-CheckBox-Check"

local TITLE_HEIGHT = 34
local BUTTON_SIZE = 22
local BUTTON_GAP = 6
local SIDE_PAD = 6
local MIN_WIDTH, MAX_WIDTH = 170, 600
local MIN_HEIGHT, MAX_HEIGHT = 80, 800
local MAX_ROWS = 40
local TICK = 0.2
local COMBAT_REFRESH = 0.4
local TEST_REFRESH = 1
local BAR_FILL = 0.8
local BAR_BACK = 0.12

local CLASS_COORDS = {
    WARRIOR = { 0, 0.25, 0, 0.25 },
    MAGE = { 0.25, 0.49609375, 0, 0.25 },
    ROGUE = { 0.49609375, 0.7421875, 0, 0.25 },
    DRUID = { 0.7421875, 0.98828125, 0, 0.25 },
    HUNTER = { 0, 0.25, 0.25, 0.5 },
    SHAMAN = { 0.25, 0.49609375, 0.25, 0.5 },
    PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 },
    WARLOCK = { 0.7421875, 0.98828125, 0.25, 0.5 },
    PALADIN = { 0, 0.25, 0.5, 0.75 },
}

local UnitDetailedThreatSituation = _G.UnitDetailedThreatSituation
local issecretvalue = _G.issecretvalue

local DB
local ui = { rows = {}, numRows = 1 }
local data = {}
local pool = {}
local testMode = false
local testValues
local dirty = true
local warned = false

local PARTY, PARTYPET, RAID, RAIDPET = {}, {}, {}, {}
for i = 1, 4 do
    PARTY[i] = "party" .. i
    PARTYPET[i] = "partypet" .. i
end
for i = 1, 40 do
    RAID[i] = "raid" .. i
    RAIDPET[i] = "raidpet" .. i
end

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function IsSecret(v)
    if issecretvalue and issecretvalue(v) then
        return true
    end
    return false
end

local function FormatValue(n)
    if n >= 1000000 then
        return string.format("%.2fM", n / 1000000)
    elseif n >= 10000 then
        return string.format("%.1fK", n / 1000)
    end
    return tostring(math.floor(n + 0.5))
end

local function GetClassRGB(class)
    local t = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class]) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
    if t then
        return t.r, t.g, t.b
    end
    return 0.6, 0.6, 0.6
end

local function InGroup()
    if IsInGroup then
        return IsInGroup()
    end
    return (GetNumGroupMembers and GetNumGroupMembers() or 0) > 0
end

local function ShowTooltip(owner, title, line)
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
    GameTooltip:SetText(title, 1, 0.82, 0)
    if line then
        GameTooltip:AddLine(line, 1, 1, 1, true)
    end
    GameTooltip:Show()
end

local function HideTooltip()
    GameTooltip:Hide()
end

----------------------------------------------------------------------
-- Threat data
----------------------------------------------------------------------

local function ClearData()
    for i = #data, 1, -1 do
        pool[#pool + 1] = data[i]
        data[i] = nil
    end
end

local function NewEntry()
    local e = table.remove(pool) or {}
    data[#data + 1] = e
    return e
end

local function SortData(a, b)
    if a.value ~= b.value then
        return a.value > b.value
    end
    if a.isTanking ~= b.isTanking then
        return a.isTanking
    end
    return a.name < b.name
end

local function GetMobUnit()
    if DB.mode == "focus" then
        if UnitExists("focus") and UnitCanAttack("player", "focus") then
            return "focus"
        end
        return nil
    end
    if UnitExists("target") and UnitCanAttack("player", "target") then
        return "target"
    end
    return nil
end

local function AddUnit(unit, mob, isPet)
    if not UnitExists(unit) then
        return
    end
    local isTanking, _, scaledPct, rawPct, value = UnitDetailedThreatSituation(unit, mob)
    if IsSecret(value) or IsSecret(scaledPct) or IsSecret(rawPct) or IsSecret(isTanking) then
        return
    end
    if value == nil then
        return
    end
    if value <= 0 then
        return
    end

    local e = NewEntry()
    local _, class = UnitClass(unit)
    e.unit = unit
    e.name = UnitName(unit) or UNKNOWN or "Unknown"
    e.class = class
    e.isPet = isPet
    e.isPlayer = (not isPet) and UnitIsUnit(unit, "player") and true or false
    e.isTanking = isTanking and true or false
    e.pct = isTanking and 100 or (scaledPct or 0)
    e.rawPct = rawPct or 0
    e.value = value
end

local function CollectThreat(mob)
    ClearData()
    local pets = DB.showPets
    if IsInRaid and IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            AddUnit(RAID[i], mob, false)
            if pets then
                AddUnit(RAIDPET[i], mob, true)
            end
        end
    else
        AddUnit("player", mob, false)
        if pets then
            AddUnit("pet", mob, true)
        end
        local n = GetNumSubgroupMembers and GetNumSubgroupMembers() or 0
        for i = 1, n do
            AddUnit(PARTY[i], mob, false)
            if pets then
                AddUnit(PARTYPET[i], mob, true)
            end
        end
    end
    table.sort(data, SortData)
end

local TEST_ROSTER = {
    { "Brakkus", "WARRIOR" },
    { "Lightsworn", "PALADIN" },
    { nil, nil },
    { "Frostwhisper", "MAGE" },
    { "Shadowstep", "ROGUE" },
    { "Felbinder", "WARLOCK" },
    { "Arrowstorm", "HUNTER" },
    { "Earthcaller", "SHAMAN" },
    { "Holyhand", "PRIEST" },
}

local function BuildTestData()
    ClearData()
    if not testValues then
        testValues = {}
        for i = 1, #TEST_ROSTER do
            testValues[i] = 9000 - i * 800 + math.random(0, 400)
        end
    end
    for i = 1, #TEST_ROSTER do
        testValues[i] = testValues[i] + math.random(0, 250) + (i == 1 and 260 or 0)
    end
    local tankValue = testValues[1]
    for i = 1, #TEST_ROSTER do
        local e = NewEntry()
        local name, class = TEST_ROSTER[i][1], TEST_ROSTER[i][2]
        if not name then
            name = UnitName("player")
            local _, myClass = UnitClass("player")
            class = myClass
        end
        e.unit = nil
        e.name = name
        e.class = class
        e.isPet = false
        e.isPlayer = (TEST_ROSTER[i][1] == nil)
        e.isTanking = (i == 1)
        e.value = testValues[i]
        e.pct = math.min(100, testValues[i] / tankValue * 100)
        e.rawPct = e.pct
    end
    table.sort(data, SortData)
end

----------------------------------------------------------------------
-- Rows
----------------------------------------------------------------------

local function Row_OnEnter(self)
    local e = self.entry
    if not e then
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local r, g, b = 1, 1, 1
    if e.isPet then
        r, g, b = COLOR.pet[1], COLOR.pet[2], COLOR.pet[3]
    elseif e.class then
        r, g, b = GetClassRGB(e.class)
    end
    GameTooltip:SetText(e.name, r, g, b)
    GameTooltip:AddDoubleLine("Threat", FormatValue(e.value), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Threat %", string.format("%.1f%%", e.pct), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Raw %", string.format("%.1f%%", e.rawPct), 0.8, 0.8, 0.8, 1, 1, 1)
    if e.isTanking then
        GameTooltip:AddLine("Currently tanking", 1, 0.3, 0.3)
    end
    GameTooltip:Show()
end

-- Grey outer line + black inner line, like the bar frames on the damage meter.
local function CreateFramedBox(parent)
    local box = {}
    box.edge = NS.SolidTexture(parent, "BACKGROUND", 0, COLOR.rowEdge)
    box.inner = NS.SolidTexture(parent, "BACKGROUND", 1, { 0, 0, 0, 1 })
    return box
end

local function AnchorFramedBox(box, left, right)
    box.edge:ClearAllPoints()
    box.edge:SetPoint("TOPLEFT", left, "TOPLEFT", 0, 0)
    box.edge:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", 0, 0)
    box.inner:ClearAllPoints()
    box.inner:SetPoint("TOPLEFT", box.edge, "TOPLEFT", 1, -1)
    box.inner:SetPoint("BOTTOMRIGHT", box.edge, "BOTTOMRIGHT", -1, 1)
end

local function CreateRow(index)
    local row = CreateFrame("Button", nil, ui.body)
    row:EnableMouse(true)
    row:SetScript("OnEnter", Row_OnEnter)
    row:SetScript("OnLeave", HideTooltip)

    row.iconSlot = CreateFrame("Frame", nil, row)
    row.iconBox = CreateFramedBox(row.iconSlot)
    AnchorFramedBox(row.iconBox, row.iconSlot, row.iconSlot)
    row.icon = row.iconSlot:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("TOPLEFT", row.iconSlot, "TOPLEFT", 1, -1)
    row.icon:SetPoint("BOTTOMRIGHT", row.iconSlot, "BOTTOMRIGHT", -1, 1)

    row.barSlot = CreateFrame("Frame", nil, row)
    row.barBox = CreateFramedBox(row.barSlot)
    AnchorFramedBox(row.barBox, row.barSlot, row.barSlot)

    row.bar = CreateFrame("StatusBar", nil, row.barSlot)
    row.bar:SetPoint("TOPLEFT", row.barSlot, "TOPLEFT", 2, -2)
    row.bar:SetPoint("BOTTOMRIGHT", row.barSlot, "BOTTOMRIGHT", -2, 2)
    row.bar:SetStatusBarTexture(WHITE)
    row.bar:SetMinMaxValues(0, 1)
    row.bar:SetValue(0)

    row.bar.bg = row.bar:CreateTexture(nil, "BACKGROUND")
    row.bar.bg:SetTexture(WHITE)
    row.bar.bg:SetAllPoints()

    row.textLayer = CreateFrame("Frame", nil, row.barSlot)
    row.textLayer:SetAllPoints(row.barSlot)
    row.textLayer:SetFrameLevel(row.bar:GetFrameLevel() + 2)

    row.name = row.textLayer:CreateFontString(nil, "OVERLAY")
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.name:SetTextColor(1, 1, 1)

    row.value = row.textLayer:CreateFontString(nil, "OVERLAY")
    row.value:SetJustifyH("RIGHT")
    row.value:SetWordWrap(false)
    row.value:SetTextColor(1, 1, 1)

    row.name:SetPoint("LEFT", row.barSlot, "LEFT", 4, 0)
    row.name:SetPoint("RIGHT", row.value, "LEFT", -4, 0)
    row.value:SetPoint("RIGHT", row.barSlot, "RIGHT", -3, 0)

    row:Hide()
    ui.rows[index] = row
    return row
end

local function LayoutRow(row, index)
    local h, sp = DB.barHeight, DB.barSpacing
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", ui.body, "TOPLEFT", 0, -(index - 1) * (h + sp))
    row:SetPoint("RIGHT", ui.body, "RIGHT", 0, 0)
    row:SetHeight(h)

    row.iconSlot:ClearAllPoints()
    row.barSlot:ClearAllPoints()
    if DB.showIcons then
        row.iconSlot:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        row.iconSlot:SetSize(h, h)
        row.iconSlot:Show()
        row.barSlot:SetPoint("TOPLEFT", row.iconSlot, "TOPRIGHT", 1, 0)
    else
        row.iconSlot:Hide()
        row.barSlot:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    end
    row.barSlot:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)

    local size = math.max(9, math.min(15, math.floor(h * 0.6)))
    NS.SetFont(row.name, size, "OUTLINE")
    NS.SetFont(row.value, size, "OUTLINE")
end

local function LayoutRows()
    if not ui.body then
        return
    end
    local h, sp = DB.barHeight, DB.barSpacing
    local bodyH = ui.body:GetHeight() or 0
    local n = math.floor((bodyH + sp) / (h + sp))
    if n < 1 then
        n = 1
    elseif n > MAX_ROWS then
        n = MAX_ROWS
    end
    ui.numRows = n
    for i = 1, n do
        LayoutRow(ui.rows[i] or CreateRow(i), i)
    end
    for i = n + 1, #ui.rows do
        ui.rows[i]:Hide()
    end
end

local function SetRowIcon(row, e)
    if not DB.showIcons then
        return
    end
    if e.isPet and e.unit then
        local key = "pet:" .. e.unit
        if row.iconKey ~= key then
            SetPortraitTexture(row.icon, e.unit)
            row.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
            row.iconKey = key
        end
        return
    end
    local coords = e.class and ((CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[e.class]) or CLASS_COORDS[e.class])
    local key = "class:" .. tostring(e.class)
    if row.iconKey ~= key then
        if coords then
            row.icon:SetTexture(CLASS_TEXTURE)
            row.icon:SetTexCoord(coords[1] + 0.015, coords[2] - 0.015, coords[3] + 0.015, coords[4] - 0.015)
        else
            row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        row.iconKey = key
    end
end

local function Render()
    if not ui.body then
        return
    end
    local top = data[1] and data[1].value or 1
    if top <= 0 then
        top = 1
    end
    for i = 1, #ui.rows do
        local row = ui.rows[i]
        local e = data[i]
        if e and i <= ui.numRows then
            local r, g, b
            if e.isPet then
                r, g, b = COLOR.pet[1], COLOR.pet[2], COLOR.pet[3]
            else
                r, g, b = GetClassRGB(e.class)
            end
            row.bar:SetStatusBarColor(r * BAR_FILL, g * BAR_FILL, b * BAR_FILL, 1)
            row.bar.bg:SetVertexColor(r * BAR_BACK, g * BAR_BACK, b * BAR_BACK, 1)
            row.bar:SetMinMaxValues(0, top)
            row.bar:SetValue(e.value)
            row.name:SetText(i .. ". " .. e.name)
            local pctText = string.format("%d%%", math.floor(e.pct + 0.5))
            if DB.showValues then
                row.value:SetText(FormatValue(e.value) .. " (" .. pctText .. ")")
            else
                row.value:SetText(pctText)
            end
            SetRowIcon(row, e)
            row.entry = e
            row:Show()
        else
            row.entry = nil
            row:Hide()
        end
    end
end

----------------------------------------------------------------------
-- Window state
----------------------------------------------------------------------

-- Always stored as the window's top-left corner so minimizing collapses upward.
local function SavePosition()
    local f = ui.frame
    local left, top = f:GetLeft(), f:GetTop()
    if not left or not top then
        return
    end
    DB.point = { "TOPLEFT", "BOTTOMLEFT", left, top }
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

local function RestorePosition()
    local f = ui.frame
    local p = DB.point
    f:SetSize(DB.width, DB.height)
    f:ClearAllPoints()
    f:SetPoint(p[1] or "CENTER", UIParent, p[2] or "CENTER", p[3] or 0, p[4] or 0)
end

local function ShouldShow()
    if DB.hidden then
        return false
    end
    if testMode then
        return true
    end
    if DB.onlyInGroup and not InGroup() then
        return false
    end
    if DB.hideOutOfCombat and not UnitAffectingCombat("player") then
        return false
    end
    if DB.onlyWithThreat and #data == 0 then
        return false
    end
    return true
end

function NS.UpdateVisibility()
    if not ui.frame then
        return
    end
    if ShouldShow() then
        ui.frame:Show()
    else
        ui.frame:Hide()
        if ui.menu then
            ui.menu:Hide()
        end
    end
end

local function UpdateGrip()
    if DB.locked or DB.minimized then
        ui.grip:Hide()
    else
        ui.grip:Show()
    end
end

local function ApplyMinimized()
    local f = ui.frame
    SavePosition()
    local btn = ui.minimizeBtn
    btn.iconY = DB.minimized and 0 or -3.5
    btn.icon:ClearAllPoints()
    btn.icon:SetPoint("CENTER", btn, "CENTER", 0, btn.iconY)
    if DB.minimized then
        btn.iconShadow:Hide()
    else
        btn.iconShadow:Show()
    end
    if DB.minimized then
        ui.body:Hide()
        f.bgTex:Hide()
        ui.minimizeBtn.plus:Show()
        f:SetHeight(TITLE_HEIGHT)
    else
        ui.body:Show()
        f.bgTex:Show()
        ui.minimizeBtn.plus:Hide()
        f:SetHeight(DB.height)
    end
    UpdateGrip()
end

local function UpdateModeButton()
    if ui.modeBtn then
        ui.modeBtn.icon:SetText(DB.mode == "focus" and "F" or "T")
    end
end

function NS.ApplySettings()
    if not ui.frame then
        return
    end
    local f = ui.frame
    f:SetScale(DB.scale)
    NS.SetWindowAlpha(f, DB.bgAlpha)
    f:SetWidth(DB.width)
    ApplyMinimized()
    LayoutRows()
    UpdateModeButton()
    NS.UpdateVisibility()
    dirty = true
    Render()
end

function NS.SetMode(mode)
    DB.mode = (mode == "focus") and "focus" or "target"
    UpdateModeButton()
    dirty = true
end

function NS.ToggleLock()
    DB.locked = not DB.locked
    UpdateGrip()
    NS.Print(DB.locked and "Window locked." or "Window unlocked.")
    if NS.RefreshOptions then
        NS.RefreshOptions()
    end
end

function NS.ToggleMinimized()
    DB.minimized = not DB.minimized
    ApplyMinimized()
    LayoutRows()
    Render()
end

function NS.SetHidden(hidden)
    DB.hidden = hidden and true or false
    NS.UpdateVisibility()
    if DB.hidden then
        NS.Print("Window hidden. Type /xtm to show it again.")
    elseif not ui.frame:IsShown() then
        NS.Print("Window enabled, but one of your settings is hiding it right now (combat, group or threat). Type /xtm config to change that.")
    end
end

function NS.SetTestMode(on)
    testMode = on and true or false
    testValues = nil
    if not testMode then
        ClearData()
    end
    dirty = true
    NS.UpdateVisibility()
    if NS.RefreshOptions then
        NS.RefreshOptions()
    end
end

function NS.ToggleTestMode()
    NS.SetTestMode(not testMode)
end

function NS.IsTestMode()
    return testMode
end

function NS.ResetPosition()
    NS.ResetLayout()
    RestorePosition()
    NS.ApplySettings()
    NS.Print("Window position and size reset.")
end

----------------------------------------------------------------------
-- Aggro warning
----------------------------------------------------------------------

local function CheckWarning()
    local me
    if DB.warnEnabled and not testMode then
        for i = 1, #data do
            if data[i].isPlayer then
                me = data[i]
                break
            end
        end
    end
    local hot = me and not me.isTanking and me.pct >= DB.warnThreshold
    if hot then
        if not warned then
            warned = true
            PlaySound((SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "Master")
        end
        ui.title:SetTextColor(COLOR.warn[1], COLOR.warn[2], COLOR.warn[3])
    else
        if not me or me.isTanking or me.pct < DB.warnThreshold - 10 then
            warned = false
        end
        ui.title:SetTextColor(COLOR.gold[1], COLOR.gold[2], COLOR.gold[3])
    end
end

----------------------------------------------------------------------
-- Update
----------------------------------------------------------------------

function NS.Update()
    if not ui.frame then
        return
    end

    if testMode then
        BuildTestData()
        ui.targetText:SetText("Training Dummy")
    else
        local mob = GetMobUnit()
        if mob then
            CollectThreat(mob)
            ui.targetText:SetText(UnitName(mob))
        else
            ClearData()
            ui.targetText:SetText("")
        end
    end

    Render()
    CheckWarning()
    NS.UpdateVisibility()
end

----------------------------------------------------------------------
-- Header menu
----------------------------------------------------------------------

local function BuildMenuItems()
    return {
        {
            text = "Threat on Target",
            checked = DB.mode == "target",
            func = function()
                NS.SetMode("target")
            end,
        },
        {
            text = "Threat on Focus",
            checked = DB.mode == "focus",
            func = function()
                NS.SetMode("focus")
            end,
        },
        { divider = true },
        { text = testMode and "Stop Test Mode" or "Test Mode", func = NS.ToggleTestMode },
        { text = DB.locked and "Unlock Window" or "Lock Window", func = NS.ToggleLock },
        {
            text = "Settings",
            func = function()
                if NS.ToggleOptions then
                    NS.ToggleOptions()
                end
            end,
        },
        {
            text = "Hide Window",
            func = function()
                NS.SetHidden(true)
            end,
        },
    }
end

local function Menu_OnEvent(self)
    if not self:IsMouseOver() and not ui.menuBtn:IsMouseOver() then
        self:Hide()
    end
end

local function Menu_OnUpdate(self, elapsed)
    if self:IsMouseOver() or ui.menuBtn:IsMouseOver() then
        self.idle = 0
        return
    end
    self.idle = (self.idle or 0) + elapsed
    if self.idle > 3 then
        self:Hide()
    end
end

local function CreateMenuButton(menu)
    local b = CreateFrame("Button", nil, menu)
    b:SetHeight(18)

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture(WHITE)
    hl:SetAllPoints()
    hl:SetVertexColor(1, 0.82, 0, 0.15)

    b.check = b:CreateTexture(nil, "ARTWORK")
    b.check:SetTexture(CHECK_TEXTURE)
    b.check:SetSize(16, 16)
    b.check:SetPoint("LEFT", 2, 0)

    b.text = b:CreateFontString(nil, "OVERLAY")
    NS.SetFont(b.text, 12)
    b.text:SetPoint("LEFT", 20, 0)
    b.text:SetJustifyH("LEFT")
    b.text:SetTextColor(1, 1, 1)

    b.line = b:CreateTexture(nil, "ARTWORK")
    b.line:SetTexture(WHITE)
    b.line:SetHeight(1)
    b.line:SetPoint("LEFT", 6, 0)
    b.line:SetPoint("RIGHT", -6, 0)
    b.line:SetVertexColor(COLOR.goldLine[1], COLOR.goldLine[2], COLOR.goldLine[3], 0.5)

    b:SetScript("OnClick", function(self)
        menu:Hide()
        if self.func then
            self.func()
        end
    end)
    return b
end

local function ShowMenu()
    local menu = ui.menu
    if menu:IsShown() then
        menu:Hide()
        return
    end
    local items = BuildMenuItems()
    local y = -6
    for i, item in ipairs(items) do
        local b = menu.buttons[i] or CreateMenuButton(menu)
        menu.buttons[i] = b
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, y)
        b:SetPoint("RIGHT", menu, "RIGHT", -4, 0)
        if item.divider then
            b:SetHeight(9)
            b:EnableMouse(false)
            b.text:SetText("")
            b.check:Hide()
            b.line:Show()
            b.func = nil
            y = y - 9
        else
            b:SetHeight(18)
            b:EnableMouse(true)
            b.text:SetText(item.text)
            b.check:SetShown(item.checked and true or false)
            b.line:Hide()
            b.func = item.func
            y = y - 18
        end
        b:Show()
    end
    for i = #items + 1, #menu.buttons do
        menu.buttons[i]:Hide()
    end
    menu:SetSize(170, -y + 6)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", ui.menuBtn, "BOTTOMLEFT", 0, -2)
    menu:SetScale(DB.scale)
    menu.idle = 0
    menu:Show()
end

local function CreateMenu()
    local menu = CreateFrame("Frame", "XiusThreatMeterMenu", UIParent, TEMPLATE)
    menu:SetFrameStrata("DIALOG")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    NS.ApplyBackdrop(menu, NS.BACKDROP_MENU, COLOR.menuBg, COLOR.buttonEdge)
    menu.buttons = {}
    menu:Hide()
    menu:SetScript("OnShow", function(self)
        pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN")
    end)
    menu:SetScript("OnHide", function(self)
        pcall(self.UnregisterEvent, self, "GLOBAL_MOUSE_DOWN")
    end)
    menu:SetScript("OnEvent", Menu_OnEvent)
    menu:SetScript("OnUpdate", Menu_OnUpdate)
    ui.menu = menu
end

----------------------------------------------------------------------
-- Window construction
----------------------------------------------------------------------

local function CreateHeaderButton(parent, kind)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(BUTTON_SIZE, BUTTON_SIZE + 1)
    NS.StyleButton(b, kind)

    b:SetScript("OnMouseDown", function(self)
        if self.icon then
            self.icon:ClearAllPoints()
            self.icon:SetPoint("CENTER", self, "CENTER", 1 + (self.iconX or 0), -1 + (self.iconY or 0))
        end
    end)
    b:SetScript("OnMouseUp", function(self)
        if self.icon then
            self.icon:ClearAllPoints()
            self.icon:SetPoint("CENTER", self, "CENTER", self.iconX or 0, self.iconY or 0)
        end
    end)
    b:SetScript("OnEnter", function(self)
        NS.SetButtonHover(self, true)
        if self.tipTitle then
            ShowTooltip(self, self.tipTitle, self.tipText)
        end
    end)
    b:SetScript("OnLeave", function(self)
        NS.SetButtonHover(self, false)
        HideTooltip()
    end)
    return b
end

local function TitleBar_OnDragStart()
    if not DB.locked then
        ui.frame:StartMoving()
    end
end

local function TitleBar_OnDragStop()
    ui.frame:StopMovingOrSizing()
    SavePosition()
end

local function Grip_OnMouseDown(self, button)
    if button == "LeftButton" and not DB.locked and not DB.minimized then
        ui.frame:StartSizing("BOTTOMRIGHT")
        ui.sizing = true
    end
end

local function Grip_OnMouseUp()
    if not ui.sizing then
        return
    end
    ui.sizing = false
    ui.frame:StopMovingOrSizing()
    DB.width = math.floor(ui.frame:GetWidth() + 0.5)
    DB.height = math.floor(ui.frame:GetHeight() + 0.5)
    SavePosition()
    LayoutRows()
    Render()
end

local function CreateWindow()
    local f = CreateFrame("Frame", "XiusThreatMeterFrame", UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    f:SetResizable(true)
    f:SetClampedToScreen(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
    else
        if f.SetMinResize then
            f:SetMinResize(MIN_WIDTH, MIN_HEIGHT)
        end
        if f.SetMaxResize then
            f:SetMaxResize(MAX_WIDTH, MAX_HEIGHT)
        end
    end
    NS.CreateWindowBackground(f)
    f:SetSize(DB.width, DB.height)
    ui.frame = f

    -- Title bar (glow + gold lines, also the drag handle)
    local titleBar = NS.CreateTitleBar(f, TITLE_HEIGHT)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", TitleBar_OnDragStart)
    titleBar:SetScript("OnDragStop", TitleBar_OnDragStop)
    titleBar:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            ShowMenu()
        end
    end)
    ui.titleBar = titleBar

    -- Dropdown arrow button (left)
    local menuBtn = CreateHeaderButton(titleBar, "bronze")
    menuBtn:SetPoint("LEFT", titleBar, "LEFT", SIDE_PAD, 0)
    menuBtn.iconY = -1.5
    menuBtn.icon = NS.CreateArrowGlyph(menuBtn, menuBtn.iconY)
    menuBtn.tipTitle = "Threat Meter"
    menuBtn.tipText = "Choose what to track and open window options."
    menuBtn:SetScript("OnClick", ShowMenu)
    ui.menuBtn = menuBtn

    -- Minimize button (far right)
    local minimizeBtn = CreateHeaderButton(titleBar, "red")
    minimizeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -SIDE_PAD, 0)
    minimizeBtn.iconY = -3.5
    minimizeBtn.icon = NS.SolidTexture(minimizeBtn, "ARTWORK", 1, COLOR.dash)
    minimizeBtn.icon:SetSize(12, 4)
    minimizeBtn.icon:SetPoint("CENTER", minimizeBtn, "CENTER", 0, minimizeBtn.iconY)
    minimizeBtn.iconShine = NS.SolidTexture(minimizeBtn, "ARTWORK", 2, { 0.98, 0.80, 0.15, 1 })
    minimizeBtn.iconShine:SetHeight(1)
    minimizeBtn.iconShine:SetPoint("TOPLEFT", minimizeBtn.icon, "TOPLEFT", 0, 0)
    minimizeBtn.iconShine:SetPoint("TOPRIGHT", minimizeBtn.icon, "TOPRIGHT", 0, 0)
    minimizeBtn.iconShadow = NS.SolidTexture(minimizeBtn, "ARTWORK", 0, { 0.15, 0.02, 0, 1 })
    minimizeBtn.iconShadow:SetHeight(1)
    minimizeBtn.iconShadow:SetPoint("TOPLEFT", minimizeBtn.icon, "BOTTOMLEFT", 0, 0)
    minimizeBtn.iconShadow:SetPoint("TOPRIGHT", minimizeBtn.icon, "BOTTOMRIGHT", 0, 0)
    minimizeBtn.plus = NS.SolidTexture(minimizeBtn, "ARTWORK", 1, COLOR.dash)
    minimizeBtn.plus:SetSize(4, 12)
    minimizeBtn.plus:SetPoint("CENTER", minimizeBtn.icon, "CENTER", 0, 0)
    minimizeBtn.tipTitle = "Minimize"
    minimizeBtn.tipText = "Collapse or expand the window."
    minimizeBtn:SetScript("OnClick", NS.ToggleMinimized)
    ui.minimizeBtn = minimizeBtn

    -- Settings button
    local gearBtn = CreateHeaderButton(titleBar, "grey")
    gearBtn:SetPoint("RIGHT", minimizeBtn, "LEFT", -BUTTON_GAP, 0)
    gearBtn.icon = NS.CreateGearGlyph(gearBtn)
    gearBtn.tipTitle = "Settings"
    gearBtn.tipText = "Open the threat meter settings."
    gearBtn:SetScript("OnClick", function()
        if NS.ToggleOptions then
            NS.ToggleOptions()
        end
    end)
    ui.gearBtn = gearBtn

    -- Target / focus mode button
    local modeBtn = CreateHeaderButton(titleBar, "bronze")
    modeBtn:SetPoint("RIGHT", gearBtn, "LEFT", -BUTTON_GAP, 0)
    modeBtn.icon = modeBtn:CreateFontString(nil, "OVERLAY")
    NS.SetFont(modeBtn.icon, 14)
    modeBtn.icon:SetTextColor(COLOR.gold[1], COLOR.gold[2], COLOR.gold[3])
    modeBtn.icon:SetPoint("CENTER")
    modeBtn.tipTitle = "Target / Focus"
    modeBtn.tipText = "T = threat on your target.\nF = threat on your focus.\nClick to switch."
    modeBtn:SetScript("OnClick", function()
        NS.SetMode(DB.mode == "focus" and "target" or "focus")
        NS.Update()
    end)
    ui.modeBtn = modeBtn

    -- Title + target name
    local title = titleBar:CreateFontString(nil, "OVERLAY")
    NS.SetFont(title, 15)
    title:SetTextColor(COLOR.gold[1], COLOR.gold[2], COLOR.gold[3])
    title:SetPoint("LEFT", menuBtn, "RIGHT", 6, 0)
    title:SetText("Threat")
    ui.title = title

    local targetText = titleBar:CreateFontString(nil, "OVERLAY")
    NS.SetFont(targetText, 11)
    targetText:SetTextColor(0.85, 0.85, 0.85)
    targetText:SetJustifyH("LEFT")
    targetText:SetWordWrap(false)
    targetText:SetPoint("LEFT", title, "RIGHT", 6, -1)
    targetText:SetPoint("RIGHT", modeBtn, "LEFT", -6, 0)
    ui.targetText = targetText

    -- Bar area
    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", f, "TOPLEFT", SIDE_PAD, -(TITLE_HEIGHT + 5))
    body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SIDE_PAD, SIDE_PAD)
    if body.SetClipsChildren then
        body:SetClipsChildren(true)
    end
    ui.body = body

    -- Resize grip
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(f:GetFrameLevel() + 20)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetAlpha(0.6)
    grip:SetScript("OnMouseDown", Grip_OnMouseDown)
    grip:SetScript("OnMouseUp", Grip_OnMouseUp)
    ui.grip = grip

    f:SetScript("OnSizeChanged", function()
        if ui.body then
            LayoutRows()
            Render()
        end
    end)
    f:SetScript("OnHide", function()
        if ui.sizing then
            Grip_OnMouseUp()
        end
    end)

    CreateMenu()
    RestorePosition()
    NS.ApplySettings()
end

----------------------------------------------------------------------
-- Driver (events + timed refresh; stays active while the window is hidden)
----------------------------------------------------------------------

local driver = CreateFrame("Frame")
local tickElapsed = 0
local sinceRefresh = 0

driver:SetScript("OnUpdate", function(_, elapsed)
    if not ui.frame then
        return
    end
    tickElapsed = tickElapsed + elapsed
    if tickElapsed < TICK then
        return
    end
    sinceRefresh = sinceRefresh + tickElapsed
    tickElapsed = 0

    local due = dirty
    if testMode then
        due = due or sinceRefresh >= TEST_REFRESH
    elseif UnitAffectingCombat("player") then
        due = due or sinceRefresh >= COMBAT_REFRESH
    end
    if due then
        dirty = false
        sinceRefresh = 0
        NS.Update()
    end
end)

local EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "PLAYER_TARGET_CHANGED",
    "PLAYER_FOCUS_CHANGED",
    "UNIT_THREAT_LIST_UPDATE",
    "UNIT_THREAT_SITUATION_UPDATE",
    "GROUP_ROSTER_UPDATE",
    "UNIT_PET",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
}

driver:RegisterEvent("ADDON_LOADED")
driver:RegisterEvent("PLAYER_LOGIN")
driver:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON then
            NS.InitDB()
            DB = NS.db
            self:UnregisterEvent("ADDON_LOADED")
        end
        return
    end

    if event == "PLAYER_LOGIN" then
        if not DB then
            NS.InitDB()
            DB = NS.db
        end
        CreateWindow()
        for _, e in ipairs(EVENTS) do
            pcall(self.RegisterEvent, self, e)
        end
        NS.Print("v" .. NS.VERSION .. " loaded. Type |cffffd100/xtm help|r for commands.")
        dirty = true
        return
    end

    if event == "PLAYER_REGEN_DISABLED" and testMode then
        NS.SetTestMode(false)
    end
    dirty = true
end)

----------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------

SLASH_XIUSTHREATMETER1 = "/xtm"
SLASH_XIUSTHREATMETER2 = "/xthreat"
SlashCmdList.XIUSTHREATMETER = function(msg)
    if not ui.frame then
        return
    end
    msg = string.lower(strtrim(msg or ""))
    if msg == "" or msg == "toggle" then
        NS.SetHidden(not DB.hidden)
    elseif msg == "show" then
        NS.SetHidden(false)
    elseif msg == "hide" then
        NS.SetHidden(true)
    elseif msg == "config" or msg == "options" or msg == "settings" then
        NS.ToggleOptions()
    elseif msg == "test" then
        NS.ToggleTestMode()
    elseif msg == "lock" or msg == "unlock" then
        NS.ToggleLock()
    elseif msg == "reset" then
        NS.ResetPosition()
    elseif msg == "target" or msg == "focus" then
        NS.SetMode(msg)
        NS.Print("Now tracking threat on your " .. msg .. ".")
    else
        NS.Print("Commands:")
        NS.Print("  /xtm - show or hide the window")
        NS.Print("  /xtm config - open settings")
        NS.Print("  /xtm test - toggle test bars")
        NS.Print("  /xtm lock - lock or unlock the window")
        NS.Print("  /xtm target | focus - choose which enemy to track")
        NS.Print("  /xtm reset - reset window position and size")
    end
end
