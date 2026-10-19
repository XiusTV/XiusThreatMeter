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

-- Match the built-in Damage Done meter header (compact gold bar + buttons).
local TITLE_HEIGHT = 24
local BUTTON_SIZE = 18
local BUTTON_GAP = 4
local SIDE_PAD = 5
local BODY_TOP_GAP = 2
local MIN_WIDTH, MAX_WIDTH = 170, 600
local MIN_HEIGHT, MAX_HEIGHT = 80, 800
local MAX_ROWS = 40
-- Event-driven updates coalesce to EVENT_THROTTLE; COMBAT_REFRESH is the
-- safety poll while fighting (threat can change without a client event).
local EVENT_THROTTLE = 0.12
local COMBAT_REFRESH = 0.25
local IDLE_REFRESH = 1
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
local UnitExists = _G.UnitExists
local UnitName = _G.UnitName
local UnitClass = _G.UnitClass
local UnitCanAttack = _G.UnitCanAttack
local UnitIsUnit = _G.UnitIsUnit
local UnitAffectingCombat = _G.UnitAffectingCombat
local UnitGUID = _G.UnitGUID
local GetNumGroupMembers = _G.GetNumGroupMembers or _G.GetNumRaidMembers
local GetNumSubgroupMembers = _G.GetNumSubgroupMembers or _G.GetNumPartyMembers
local IsInRaid = _G.IsInRaid
if not IsInRaid and _G.GetNumRaidMembers then
    local GetNumRaidMembers = _G.GetNumRaidMembers
    IsInRaid = function()
        return GetNumRaidMembers() > 0
    end
end
local floor = math.floor
local abs = math.abs
local max = math.max
local min = math.min
local format = string.format
local sort = table.sort
local remove = table.remove

local DB
local ui = { rows = {}, numRows = 1 }
local data = {}
local pool = {}
local identity = {}
local transient = {}
local testMode = false
local testValues
local testPlayerName, testPlayerClass
local warned = false
local titleHot = false
local inCombat = false
local playerEntry
local hoveredRow
local petSerial = 0
local scriptError = false
local updating = false
local tickElapsed = 0
local threatDirty = false
local lastMobGUID
local lastMobName
local SyncDriver
local RequestUpdate

local checkSecret = issecretvalue ~= nil

local RANK_PREFIX = {}
local PCT_TEXT = {}
for i = 1, MAX_ROWS do
    RANK_PREFIX[i] = i .. ". "
end
for i = -10, 300 do
    PCT_TEXT[i] = i .. "%"
end

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

local function FormatValue(n)
    if n >= 1000000 then
        return format("%.2fM", n / 1000000)
    elseif n >= 10000 then
        return format("%.1fK", n / 1000)
    end
    return tostring(floor(n + 0.5))
end

local function ClampDB(v, minV, maxV, default)
    if type(v) ~= "number" or v ~= v then
        return default
    end
    if v < minV then
        return minV
    end
    if v > maxV then
        return maxV
    end
    return v
end

local function SanitizeDB()
    if not DB then
        return
    end
    DB.scale = ClampDB(DB.scale, 0.5, 2, 1)
    DB.bgAlpha = ClampDB(DB.bgAlpha, 0, 1, 0.45)
    DB.barHeight = ClampDB(DB.barHeight, 12, 32, 19)
    DB.barSpacing = ClampDB(DB.barSpacing, 0, 8, 2)
    DB.width = ClampDB(DB.width, MIN_WIDTH, MAX_WIDTH, 250)
    DB.height = ClampDB(DB.height, MIN_HEIGHT, MAX_HEIGHT, 190)
    DB.warnThreshold = ClampDB(DB.warnThreshold, 50, 100, 90)
    if DB.mode ~= "focus" and DB.mode ~= "target" then
        DB.mode = "target"
    end
    local p = DB.point
    if type(p) ~= "table" or type(p[1]) ~= "string" or type(p[3]) ~= "number" or type(p[4]) ~= "number" then
        DB.point = { "CENTER", "CENTER", 300, 0 }
    end
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
    if IsInRaid and IsInRaid() then
        return true
    end
    if GetNumGroupMembers and GetNumGroupMembers() > 0 then
        return true
    end
    return (GetNumSubgroupMembers and GetNumSubgroupMembers() or 0) > 0
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
    playerEntry = nil
    for i = #data, 1, -1 do
        pool[#pool + 1] = data[i]
        data[i] = nil
    end
end

local function NewEntry()
    local e = remove(pool) or {}
    data[#data + 1] = e
    return e
end

local function WipeIdentity()
    petSerial = petSerial + 1
    for unit in pairs(identity) do
        identity[unit] = nil
    end
end

-- Name, class and "is this me?" stay valid until the roster, a pet, or a
-- name resolves. Threat numbers are never cached.
local function GetIdentity(unit, isPet)
    local id = identity[unit]
    if id then
        return id
    end
    local name = UnitName(unit)
    local class
    local isPlayer = false
    if isPet then
        if not name then
            transient.name = "Pet"
            transient.class = nil
            transient.isPlayer = false
            transient.iconID = unit
            transient.petSerial = petSerial
            return transient
        end
    else
        local _
        _, class = UnitClass(unit)
        isPlayer = (unit == "player" or UnitIsUnit(unit, "player")) and true or false
        if not name or not class then
            transient.name = name or UNKNOWN or "Unknown"
            transient.class = class
            transient.isPlayer = isPlayer
            transient.iconID = nil
            transient.petSerial = nil
            return transient
        end
    end
    id = {
        name = name,
        class = class,
        isPlayer = isPlayer,
    }
    if isPet then
        local guid = UnitGUID and UnitGUID(unit) or nil
        id.iconID = guid or unit
        id.petSerial = guid and 0 or petSerial
    end
    identity[unit] = id
    return id
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
    -- Cheap existence check before any identity / threat API work.
    if not UnitExists(unit) then
        identity[unit] = nil
        return
    end
    local id = GetIdentity(unit, isPet)
    if not id then
        return
    end
    local isTanking, _, scaledPct, rawPct, value = UnitDetailedThreatSituation(unit, mob)
    -- Secret values error if compared. Check them before the numeric test.
    if checkSecret then
        if issecretvalue(isTanking) or issecretvalue(scaledPct) or issecretvalue(rawPct) or issecretvalue(value) then
            return
        end
    end
    if value == nil or value <= 0 then
        return
    end

    local e = NewEntry()
    e.unit = unit
    e.name = id.name
    e.class = id.class
    e.isPet = isPet
    e.isPlayer = id.isPlayer and true or false
    e.isTanking = isTanking and true or false
    -- Tanking units report as 100% scaled threat so the bar and warning match
    -- the client's aggro state even when scaledPct briefly lags.
    if e.isTanking then
        e.pct = 100
    else
        e.pct = scaledPct or 0
    end
    e.rawPct = rawPct or 0
    e.value = value
    if isPet then
        local c = COLOR.pet
        e.r, e.g, e.b = c[1], c[2], c[3]
        e.iconID = id.iconID or unit
        e.petSerial = id.petSerial or petSerial
    else
        e.r, e.g, e.b = GetClassRGB(id.class)
        e.iconID = nil
        e.petSerial = nil
    end
    if e.isPlayer then
        playerEntry = e
    end
end

local function CollectThreat(mob)
    ClearData()
    local pets = DB.showPets
    if IsInRaid and IsInRaid() then
        local n = GetNumGroupMembers and GetNumGroupMembers() or 0
        for i = 1, n do
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
    if #data > 1 then
        sort(data, SortData)
    end
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
    if not testPlayerName then
        testPlayerName = UnitName("player") or "You"
        local _, myClass = UnitClass("player")
        testPlayerClass = myClass
    end
    for i = 1, #TEST_ROSTER do
        testValues[i] = testValues[i] + math.random(0, 250) + (i == 1 and 260 or 0)
    end
    local tankValue = testValues[1]
    for i = 1, #TEST_ROSTER do
        local e = NewEntry()
        local name, class = TEST_ROSTER[i][1], TEST_ROSTER[i][2]
        if not name then
            name = testPlayerName
            class = testPlayerClass
        end
        e.unit = nil
        e.name = name
        e.class = class
        e.isPet = false
        e.isPlayer = (TEST_ROSTER[i][1] == nil)
        e.isTanking = (i == 1)
        e.value = testValues[i]
        e.pct = min(100, testValues[i] / tankValue * 100)
        e.rawPct = e.pct
        e.r, e.g, e.b = GetClassRGB(class)
        e.iconID = nil
        e.petSerial = nil
    end
    sort(data, SortData)
end

----------------------------------------------------------------------
-- Rows
----------------------------------------------------------------------

local function Row_OnEnter(self)
    local e = self.entry
    if not e then
        return
    end
    hoveredRow = self
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local r, g, b = e.r or 1, e.g or 1, e.b or 1
    GameTooltip:SetText(e.name, r, g, b)
    GameTooltip:AddDoubleLine("Threat", FormatValue(e.value), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Threat %", format("%.1f%%", e.pct), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Raw %", format("%.1f%%", e.rawPct), 0.8, 0.8, 0.8, 1, 1, 1)
    if e.isTanking then
        GameTooltip:AddLine("Currently tanking", 1, 0.3, 0.3)
    end
    GameTooltip:Show()
end

local function Row_OnLeave(self)
    if hoveredRow == self then
        hoveredRow = nil
    end
    HideTooltip()
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
    row:SetScript("OnLeave", Row_OnLeave)

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
    local icons = DB.showIcons and true or false
    if row.layoutH ~= h or row.layoutSp ~= sp or row.layoutIndex ~= index then
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", ui.body, "TOPLEFT", 0, -(index - 1) * (h + sp))
        row:SetPoint("RIGHT", ui.body, "RIGHT", 0, 0)
        row:SetHeight(h)
        row.layoutH = h
        row.layoutSp = sp
        row.layoutIndex = index
        row.layoutIcons = nil
    end
    if row.layoutIcons ~= icons or row.iconSize ~= h then
        row.iconSlot:ClearAllPoints()
        row.barSlot:ClearAllPoints()
        if icons then
            row.iconSlot:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
            row.iconSlot:SetSize(h, h)
            row.iconSlot:Show()
            row.barSlot:SetPoint("TOPLEFT", row.iconSlot, "TOPRIGHT", 1, 0)
        else
            row.iconSlot:Hide()
            row.barSlot:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        end
        row.barSlot:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        row.layoutIcons = icons
        row.iconSize = h
    end
    local size = max(9, min(15, floor(h * 0.6)))
    if row.fontSize ~= size then
        NS.SetFont(row.name, size, "OUTLINE")
        NS.SetFont(row.value, size, "OUTLINE")
        row.fontSize = size
    end
end

local function LayoutRows()
    if not ui.body or DB.minimized then
        return
    end
    local h, sp = DB.barHeight, DB.barSpacing
    local icons = DB.showIcons and true or false
    local bodyH = ui.body:GetHeight() or 0
    local denom = h + sp
    if denom < 1 then
        denom = 1
    end
    local n = floor((bodyH + sp) / denom)
    if n < 1 then
        n = 1
    elseif n > MAX_ROWS then
        n = MAX_ROWS
    end
    if ui.layoutH == h and ui.layoutSp == sp and ui.layoutIcons == icons and ui.numRows == n then
        return
    end
    ui.numRows = n
    ui.layoutH = h
    ui.layoutSp = sp
    ui.layoutIcons = icons
    for i = 1, n do
        LayoutRow(ui.rows[i] or CreateRow(i), i)
    end
    for i = n + 1, #ui.rows do
        local row = ui.rows[i]
        if row:IsShown() then
            row:Hide()
        end
    end
end

local function SetRowIcon(row, e)
    if not DB.showIcons then
        return
    end
    if e.isPet and e.unit then
        if row.iconPet ~= e.iconID or row.iconPetSerial ~= e.petSerial then
            SetPortraitTexture(row.icon, e.unit)
            row.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
            row.iconPet = e.iconID
            row.iconPetSerial = e.petSerial
            row.iconClass = nil
        end
        return
    end
    local classKey = e.class or false
    if row.iconClass ~= classKey then
        local coords = e.class and ((CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[e.class]) or CLASS_COORDS[e.class])
        if coords then
            row.icon:SetTexture(CLASS_TEXTURE)
            row.icon:SetTexCoord(coords[1] + 0.015, coords[2] - 0.015, coords[3] + 0.015, coords[4] - 0.015)
        else
            row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        row.iconClass = classKey
        row.iconPet = nil
    end
end

local function Render()
    if not ui.body or not ui.frame or not ui.frame:IsShown() or DB.minimized then
        return
    end
    LayoutRows()
    local top = data[1] and data[1].value or 1
    if top <= 0 then
        top = 1
    end
    local showValues = DB.showValues and true or false
    local n = ui.numRows
    for i = 1, n do
        local row = ui.rows[i]
        local e = data[i]
        if row and e then
            local nameChanged = false
            local r, g, b = e.r or 0.6, e.g or 0.6, e.b or 0.6
            if row.cr ~= r or row.cg ~= g or row.cb ~= b then
                row.cr, row.cg, row.cb = r, g, b
                row.bar:SetStatusBarColor(r * BAR_FILL, g * BAR_FILL, b * BAR_FILL, 1)
                row.bar.bg:SetVertexColor(r * BAR_BACK, g * BAR_BACK, b * BAR_BACK, 1)
            end
            local maxChanged = row.maxThreat ~= top
            if maxChanged then
                row.maxThreat = top
                row.bar:SetMinMaxValues(0, top)
            end
            if maxChanged or row.barValue ~= e.value then
                row.barValue = e.value
                row.bar:SetValue(e.value)
            end
            if row.rank ~= i or row.unitName ~= e.name then
                row.rank = i
                row.unitName = e.name
                row.name:SetText(RANK_PREFIX[i] .. e.name)
                nameChanged = true
            end
            local pctInt = floor(e.pct + 0.5)
            if row.pctInt ~= pctInt or row.rawValue ~= e.value or row.valueMode ~= showValues then
                local pctText = PCT_TEXT[pctInt] or (tostring(pctInt) .. "%")
                local text = showValues and (FormatValue(e.value) .. " (" .. pctText .. ")") or pctText
                row.pctInt = pctInt
                row.rawValue = e.value
                row.valueMode = showValues
                if row.valueText ~= text then
                    row.valueText = text
                    row.value:SetText(text)
                end
            end
            SetRowIcon(row, e)
            row.entry = e
            if not row:IsShown() then
                row:Show()
            end
            if hoveredRow == row and (nameChanged or row.tipValue ~= e.value or row.tipPct ~= e.pct or row.tipRaw ~= e.rawPct) then
                row.tipValue, row.tipPct, row.tipRaw = e.value, e.pct, e.rawPct
                Row_OnEnter(row)
            else
                row.tipValue, row.tipPct, row.tipRaw = e.value, e.pct, e.rawPct
            end
        elseif row then
            row.entry = nil
            if hoveredRow == row then
                hoveredRow = nil
                HideTooltip()
            end
            if row:IsShown() then
                row:Hide()
            end
        end
    end
    for i = n + 1, #ui.rows do
        local row = ui.rows[i]
        if row:IsShown() then
            row.entry = nil
            if hoveredRow == row then
                hoveredRow = nil
                HideTooltip()
            end
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
    local frame = ui.frame
    if ShouldShow() then
        if not frame:IsShown() then
            frame:Show()
        end
    else
        if frame:IsShown() then
            frame:Hide()
        end
        if ui.menu and ui.menu:IsShown() then
            ui.menu:Hide()
        end
    end
end

local function IsTopLeftAnchored(f)
    local point, relativeTo, relativePoint = f:GetPoint(1)
    if point ~= "TOPLEFT" or relativePoint ~= "BOTTOMLEFT" then
        return false
    end
    if relativeTo == nil or relativeTo == UIParent then
        return true
    end
    return relativeTo.GetName and relativeTo:GetName() == "UIParent"
end

-- Re-anchor once so minimize collapses upward. Repeating this on every
-- settings change walks the window because GetLeft/GetTop shift with scale.
local function EnsureTopLeftAnchor()
    local f = ui.frame
    if IsTopLeftAnchored(f) then
        return
    end
    SavePosition()
end

local function UpdateGrip()
    local show = not DB.locked and not DB.minimized
    if show then
        if not ui.grip:IsShown() then
            ui.grip:Show()
        end
    elseif ui.grip:IsShown() then
        ui.grip:Hide()
    end
end

local function ApplyMinimized()
    local f = ui.frame
    EnsureTopLeftAnchor()
    local btn = ui.minimizeBtn
    local minimized = DB.minimized and true or false
    if ui.minState ~= minimized then
        ui.minState = minimized
        btn.iconY = 0
        btn.icon:ClearAllPoints()
        btn.icon:SetPoint("CENTER", btn, "CENTER", 0, btn.iconY)
        if minimized then
            btn.iconShadow:Hide()
            ui.body:Hide()
            f.bgTex:Hide()
            btn.plus:Show()
        else
            btn.iconShadow:Show()
            ui.body:Show()
            f.bgTex:Show()
            btn.plus:Hide()
        end
    end
    local wantH = minimized and TITLE_HEIGHT or DB.height
    if abs((f:GetHeight() or 0) - wantH) > 0.5 then
        f:SetHeight(wantH)
    end
    UpdateGrip()
end

local function UpdateModeButton()
    if not ui.modeBtn then
        return
    end
    local letter = DB.mode == "focus" and "F" or "T"
    if ui.modeLetter ~= letter then
        ui.modeLetter = letter
        ui.modeBtn.icon:SetText(letter)
    end
end

local function SetTargetLabel(text)
    if ui.targetLabel ~= text then
        ui.targetLabel = text
        ui.targetText:SetText(text)
    end
end

function NS.ApplySettings()
    if not ui.frame then
        return
    end
    local f = ui.frame
    ui.applying = true
    if ui.appliedScale ~= DB.scale then
        f:SetScale(DB.scale)
        ui.appliedScale = DB.scale
    end
    NS.SetWindowAlpha(f, DB.bgAlpha)
    if abs((f:GetWidth() or 0) - DB.width) > 0.5 then
        f:SetWidth(DB.width)
    end
    ApplyMinimized()
    ui.applying = false
    UpdateModeButton()
    if DB.minimized then
        ui.layoutH = nil
    else
        LayoutRows()
    end
    NS.UpdateVisibility()
    local pets = DB.showPets and true or false
    if ui.appliedPets ~= pets then
        ui.appliedPets = pets
        if not testMode then
            NS.Update()
            return
        end
    end
    if f:IsShown() and not DB.minimized then
        Render()
    end
    SyncDriver()
end

function NS.SetMode(mode)
    local newMode = (mode == "focus") and "focus" or "target"
    if DB.mode == newMode then
        UpdateModeButton()
        return
    end
    DB.mode = newMode
    UpdateModeButton()
    NS.Update()
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
    ui.layoutH = nil
    ui.applying = true
    ApplyMinimized()
    ui.applying = false
    if not DB.minimized then
        LayoutRows()
        Render()
    end
end

function NS.SetHidden(hidden)
    DB.hidden = hidden and true or false
    if DB.hidden then
        inCombat = UnitAffectingCombat("player") and true or false
        NS.UpdateVisibility()
        SyncDriver()
        NS.Print("Window hidden. Type /xtm to show it again.")
    else
        NS.Update()
        if not ui.frame:IsShown() then
            NS.Print("Window enabled, but one of your settings is hiding it right now (combat, group or threat). Type /xtm config to change that.")
        end
    end
end

function NS.SetTestMode(on)
    testMode = on and true or false
    testValues = nil
    if not testMode then
        ClearData()
        testPlayerName = nil
        testPlayerClass = nil
    end
    if NS.RefreshOptions then
        NS.RefreshOptions()
    end
    NS.Update()
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

local function PlayWarning()
    local id = (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959
    if pcall(PlaySound, id, "Master") then
        return
    end
    pcall(PlaySound, id)
end

local function CheckWarning()
    local me = (DB.warnEnabled and not testMode) and playerEntry or nil
    local hot = me and (not me.isTanking) and me.pct >= DB.warnThreshold and true or false
    if hot then
        if not warned then
            warned = true
            PlayWarning()
        end
    elseif not me or me.isTanking or me.pct < DB.warnThreshold - 10 then
        warned = false
    end
    if hot ~= titleHot then
        titleHot = hot
        if hot then
            ui.title:SetTextColor(COLOR.warn[1], COLOR.warn[2], COLOR.warn[3])
        else
            ui.title:SetTextColor(COLOR.gold[1], COLOR.gold[2], COLOR.gold[3])
        end
    end
end

----------------------------------------------------------------------
-- Update
----------------------------------------------------------------------

local function DoUpdate()
    inCombat = UnitAffectingCombat("player") and true or false

    if testMode then
        BuildTestData()
        lastMobGUID = nil
        lastMobName = "Training Dummy"
        SetTargetLabel(lastMobName)
    else
        local mob = GetMobUnit()
        if mob then
            local guid = UnitGUID and UnitGUID(mob) or mob
            if guid ~= lastMobGUID then
                lastMobGUID = guid
                warned = false
                lastMobName = nil
            end
            CollectThreat(mob)
            local name = UnitName(mob) or UNKNOWN or "Unknown"
            if name ~= lastMobName then
                lastMobName = name
                SetTargetLabel(name)
            end
        else
            if lastMobGUID or #data > 0 then
                ClearData()
            end
            lastMobGUID = nil
            lastMobName = nil
            SetTargetLabel("")
        end
    end

    NS.UpdateVisibility()
    if ui.frame:IsShown() and not DB.minimized then
        Render()
    end
    CheckWarning()
end

function NS.Update()
    if not ui.frame then
        return
    end
    if updating then
        threatDirty = true
        return
    end
    updating = true
    threatDirty = false
    local ok, err = pcall(DoUpdate)
    updating = false
    if not ok and not scriptError then
        scriptError = true
        NS.Print("Hit an error and kept running (" .. tostring(err) .. "). If the bars look wrong, type /reload.")
    end
    tickElapsed = 0
    if SyncDriver then
        SyncDriver()
    end
    -- A threat event arrived while we were scanning; refresh again shortly.
    if threatDirty then
        SyncDriver()
    end
end

-- Coalesce bursty threat events so we refresh quickly without scanning
-- on every single UNIT_THREAT_* fire.
function RequestUpdate(immediate)
    if not ui.frame then
        return
    end
    if updating then
        threatDirty = true
        return
    end
    if immediate or tickElapsed >= EVENT_THROTTLE then
        NS.Update()
        return
    end
    threatDirty = true
    SyncDriver()
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
    b:SetSize(BUTTON_SIZE, BUTTON_SIZE)
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
    menuBtn.iconY = 0
    menuBtn.icon = NS.CreateArrowGlyph(menuBtn, menuBtn.iconY)
    menuBtn.tipTitle = "Threat Meter"
    menuBtn.tipText = "Choose what to track and open window options."
    menuBtn:SetScript("OnClick", ShowMenu)
    ui.menuBtn = menuBtn

    -- Minimize button (far right): thin centered gold dash like Damage Done.
    local minimizeBtn = CreateHeaderButton(titleBar, "red")
    minimizeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -SIDE_PAD, 0)
    minimizeBtn.iconY = 0
    minimizeBtn.icon = NS.SolidTexture(minimizeBtn, "ARTWORK", 1, COLOR.dash)
    minimizeBtn.icon:SetSize(10, 2)
    minimizeBtn.icon:SetPoint("CENTER", minimizeBtn, "CENTER", 0, minimizeBtn.iconY)
    minimizeBtn.iconShine = NS.SolidTexture(minimizeBtn, "ARTWORK", 2, { 1, 0.88, 0.25, 0.85 })
    minimizeBtn.iconShine:SetHeight(1)
    minimizeBtn.iconShine:SetPoint("TOPLEFT", minimizeBtn.icon, "TOPLEFT", 0, 0)
    minimizeBtn.iconShine:SetPoint("TOPRIGHT", minimizeBtn.icon, "TOPRIGHT", 0, 0)
    minimizeBtn.iconShadow = NS.SolidTexture(minimizeBtn, "ARTWORK", 0, { 0.12, 0.02, 0, 0.9 })
    minimizeBtn.iconShadow:SetHeight(1)
    minimizeBtn.iconShadow:SetPoint("TOPLEFT", minimizeBtn.icon, "BOTTOMLEFT", 0, 0)
    minimizeBtn.iconShadow:SetPoint("TOPRIGHT", minimizeBtn.icon, "BOTTOMRIGHT", 0, 0)
    minimizeBtn.plus = NS.SolidTexture(minimizeBtn, "ARTWORK", 1, COLOR.dash)
    minimizeBtn.plus:SetSize(2, 10)
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
    NS.SetFont(modeBtn.icon, 12)
    modeBtn.icon:SetTextColor(COLOR.gold[1], COLOR.gold[2], COLOR.gold[3])
    modeBtn.icon:SetPoint("CENTER", 0, 0)
    modeBtn.tipTitle = "Target / Focus"
    modeBtn.tipText = "T = threat on your target.\nF = threat on your focus.\nClick to switch."
    modeBtn:SetScript("OnClick", function()
        NS.SetMode(DB.mode == "focus" and "target" or "focus")
    end)
    ui.modeBtn = modeBtn

    -- Title + target name
    local title = titleBar:CreateFontString(nil, "OVERLAY")
    NS.SetFont(title, 13)
    title:SetTextColor(COLOR.gold[1], COLOR.gold[2], COLOR.gold[3])
    title:SetPoint("LEFT", menuBtn, "RIGHT", 4, 0)
    title:SetText("Threat")
    ui.title = title

    local targetText = titleBar:CreateFontString(nil, "OVERLAY")
    NS.SetFont(targetText, 10)
    targetText:SetTextColor(0.85, 0.85, 0.85)
    targetText:SetJustifyH("LEFT")
    targetText:SetWordWrap(false)
    targetText:SetPoint("LEFT", title, "RIGHT", 4, -1)
    targetText:SetPoint("RIGHT", modeBtn, "LEFT", -4, 0)
    ui.targetText = targetText

    -- Bar area
    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", f, "TOPLEFT", SIDE_PAD, -(TITLE_HEIGHT + BODY_TOP_GAP))
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
        if ui.applying or not ui.body or DB.minimized then
            return
        end
        LayoutRows()
        Render()
    end)
    f:SetScript("OnHide", function()
        if ui.sizing then
            Grip_OnMouseUp()
        end
        if hoveredRow then
            hoveredRow = nil
            HideTooltip()
        end
    end)

    CreateMenu()
    RestorePosition()
    NS.ApplySettings()
end

----------------------------------------------------------------------
-- Driver
-- Threat events set a dirty flag and refresh after EVENT_THROTTLE.
-- Combat also keeps a COMBAT_REFRESH safety poll (threat can change
-- without a client event). Out of combat the OnUpdate script is
-- removed unless the window is shown with a live mob or test mode.
----------------------------------------------------------------------

local driver = CreateFrame("Frame")
local pollInterval = IDLE_REFRESH
local usingOnUpdate = false

local function OnUpdate(_, elapsed)
    tickElapsed = tickElapsed + elapsed
    if threatDirty and tickElapsed >= EVENT_THROTTLE then
        NS.Update()
        return
    end
    if tickElapsed < pollInterval then
        return
    end
    tickElapsed = 0
    NS.Update()
end

local function StopDriver()
    if usingOnUpdate then
        usingOnUpdate = false
        driver:SetScript("OnUpdate", nil)
    end
end

local function StartDriver(interval)
    pollInterval = interval
    if not usingOnUpdate then
        usingOnUpdate = true
        driver:SetScript("OnUpdate", OnUpdate)
    end
end

function SyncDriver()
    if not ui.frame or not DB then
        return
    end
    if DB.hidden then
        if DB.warnEnabled and inCombat and not testMode then
            StartDriver(COMBAT_REFRESH)
        else
            threatDirty = false
            StopDriver()
        end
        return
    end
    if testMode then
        StartDriver(TEST_REFRESH)
        return
    end
    if inCombat then
        StartDriver(COMBAT_REFRESH)
        return
    end
    -- Out of combat: only poll while a hostile target/focus is up so we
    -- are not scanning the roster every second for an empty window.
    if ui.frame:IsShown() and GetMobUnit() then
        StartDriver(IDLE_REFRESH)
        return
    end
    if threatDirty then
        StartDriver(EVENT_THROTTLE)
        return
    end
    StopDriver()
end

local EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "PLAYER_TARGET_CHANGED",
    "PLAYER_FOCUS_CHANGED",
    "UNIT_THREAT_LIST_UPDATE",
    "UNIT_THREAT_SITUATION_UPDATE",
    "GROUP_ROSTER_UPDATE",
    "PARTY_MEMBERS_CHANGED",
    "RAID_ROSTER_UPDATE",
    "UNIT_PET",
    "UNIT_NAME_UPDATE",
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
            SanitizeDB()
            self:UnregisterEvent("ADDON_LOADED")
        end
        return
    end

    if event == "PLAYER_LOGIN" then
        if not DB then
            NS.InitDB()
            DB = NS.db
        end
        SanitizeDB()
        inCombat = UnitAffectingCombat("player") and true or false
        CreateWindow()
        for _, e in ipairs(EVENTS) do
            pcall(self.RegisterEvent, self, e)
        end
        NS.Print("v" .. NS.VERSION .. " loaded. Type |cffffd100/xtm help|r for commands.")
        return
    end

    if not ui.frame then
        return
    end

    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        if testMode then
            NS.SetTestMode(false)
        else
            RequestUpdate(true)
        end
        inCombat = true
        SyncDriver()
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        RequestUpdate(true)
        inCombat = UnitAffectingCombat("player") and true or false
        SyncDriver()
        return
    end

    if event == "UNIT_NAME_UPDATE" then
        if arg1 then
            identity[arg1] = nil
        end
        return
    end

    if event == "UNIT_THREAT_LIST_UPDATE" then
        if testMode or (DB.hidden and not DB.warnEnabled) then
            return
        end
        -- LIST_UPDATE's unit is the mob. Ignore unrelated nameplates.
        local mob = GetMobUnit()
        if mob and arg1 and UnitGUID then
            local eventGUID = UnitGUID(arg1)
            local mobGUID = UnitGUID(mob)
            if eventGUID and mobGUID and eventGUID ~= mobGUID then
                return
            end
        elseif not mob and not inCombat then
            return
        end
        if UnitAffectingCombat("player") then
            inCombat = true
            RequestUpdate(false)
        else
            inCombat = false
            RequestUpdate(true)
        end
        return
    end

    if event == "UNIT_THREAT_SITUATION_UPDATE" then
        if testMode or (DB.hidden and not DB.warnEnabled) then
            return
        end
        -- SITUATION_UPDATE's unit is the player/pet whose status changed.
        if UnitAffectingCombat("player") then
            inCombat = true
            RequestUpdate(false)
        else
            inCombat = false
            RequestUpdate(true)
        end
        return
    end

    if event == "GROUP_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" or event == "UNIT_PET" or event == "PLAYER_ENTERING_WORLD" then
        WipeIdentity()
        if event == "PLAYER_ENTERING_WORLD" then
            testPlayerName = nil
            testPlayerClass = nil
            lastMobGUID = nil
            lastMobName = nil
        end
    end

    RequestUpdate(true)
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
