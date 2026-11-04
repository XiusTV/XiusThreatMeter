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
-- Events are coalesced so a busy fight scans a few times a second, not once
-- per event. The combat poll is only a safety net for threat that changes
-- without a client event (the server itself updates about once a second).
local EVENT_THROTTLE = 0.2
local COMBAT_REFRESH = 0.6
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
    DEATHKNIGHT = { 0.25, 0.49609375, 0.5, 0.75 },
    MONK = { 0.49609375, 0.7421875, 0.5, 0.75 },
    DEMONHUNTER = { 0.7421875, 0.98828125, 0.5, 0.75 },
    EVOKER = { 0, 0.25, 0.75, 1 },
}

local FALLBACK_CLASS_COLORS = {
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
    MAGE = { r = 0.25, g = 0.78, b = 0.92 },
    ROGUE = { r = 1.00, g = 0.96, b = 0.41 },
    DRUID = { r = 1.00, g = 0.49, b = 0.04 },
    HUNTER = { r = 0.67, g = 0.83, b = 0.45 },
    SHAMAN = { r = 0.00, g = 0.44, b = 0.87 },
    PRIEST = { r = 1.00, g = 1.00, b = 1.00 },
    WARLOCK = { r = 0.53, g = 0.53, b = 0.93 },
    PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
    DEATHKNIGHT = { r = 0.77, g = 0.12, b = 0.23 },
    MONK = { r = 0.00, g = 1.00, b = 0.60 },
    DEMONHUNTER = { r = 0.64, g = 0.19, b = 0.79 },
    EVOKER = { r = 0.20, g = 0.58, b = 0.50 },
}

local UnitDetailedThreatSituation = _G.UnitDetailedThreatSituation
local UnitThreatSituation = _G.UnitThreatSituation
local issecretvalue = _G.issecretvalue
local UnitExists = _G.UnitExists
local UnitIsVisible = _G.UnitIsVisible
local UnitName = _G.UnitName
local UnitClass = _G.UnitClass
local UnitCanAttack = _G.UnitCanAttack
local UnitIsUnit = _G.UnitIsUnit
local UnitAffectingCombat = _G.UnitAffectingCombat
local UnitGUID = _G.UnitGUID
local IsInRaid = _G.IsInRaid
local IsInGroup = _G.IsInGroup
local GetNumGroupMembers = _G.GetNumGroupMembers
local GetNumRaidMembers = _G.GetNumRaidMembers
local GetNumPartyMembers = _G.GetNumPartyMembers
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
local testPlayerName, testPlayerClass
local warned = false
local titleHot = false
local inCombat = false
local playerEntry
local petEntry
local heldPet
local hoveredRow
local apiMissing = false
local petSerial = 0
local scriptError = false
local updating = false
local tickElapsed = 0
local threatDirty = false
local usingOnUpdate = false
local lastMobGUID
local lastMobName
local SyncDriver
local RequestUpdate
local CheckWarning

local checkSecret = issecretvalue ~= nil

-- Secret numbers can be drawn by widgets. They cannot be compared, sorted, or concatenated.
local function IsSecret(v)
    return checkSecret and issecretvalue(v)
end

local function IsNumberLike(v)
    if IsSecret(v) then
        return true
    end
    return type(v) == "number"
end

local RANK_PREFIX = {}
local PCT_TEXT = {}
for i = 1, MAX_ROWS do
    RANK_PREFIX[i] = i .. ". "
end
for i = -10, 300 do
    PCT_TEXT[i] = i .. "%"
end

local PARTY, PARTYPET, RAID, RAIDPET = {}, {}, {}, {}
local IS_PARTY_UNIT = {}
for i = 1, 4 do
    PARTY[i] = "party" .. i
    PARTYPET[i] = "partypet" .. i
    IS_PARTY_UNIT[PARTY[i]] = true
    IS_PARTY_UNIT[PARTYPET[i]] = true
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

local function QuantizeValue(n)
    if n >= 1000000 then
        return floor(n / 10000 + 0.5) * 10000
    elseif n >= 10000 then
        return floor(n / 100 + 0.5) * 100
    end
    return floor(n + 0.5)
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
    local function SnapStep(v, step, minV, maxV, default)
        v = ClampDB(v, minV, maxV, default)
        local n = floor(v / step + 0.5) * step
        if step < 1 then
            n = floor(n * 100 + 0.5) / 100
        end
        if n < minV then
            n = minV
        elseif n > maxV then
            n = maxV
        end
        return n
    end
    DB.scale = SnapStep(DB.scale, 0.05, 0.5, 2, 1)
    DB.bgAlpha = SnapStep(DB.bgAlpha, 0.05, 0, 1, 0.45)
    DB.barHeight = SnapStep(DB.barHeight, 1, 12, 32, 19)
    DB.barSpacing = SnapStep(DB.barSpacing, 1, 0, 8, 2)
    DB.width = SnapStep(DB.width, 1, MIN_WIDTH, MAX_WIDTH, 250)
    DB.height = SnapStep(DB.height, 1, MIN_HEIGHT, MAX_HEIGHT, 190)
    DB.warnThreshold = SnapStep(DB.warnThreshold, 5, 50, 100, 90)
    if DB.mode ~= "focus" and DB.mode ~= "target" then
        DB.mode = "target"
    end
    local function Flag(v)
        return v and true or false
    end
    DB.hidden = Flag(DB.hidden)
    DB.locked = Flag(DB.locked)
    DB.minimized = Flag(DB.minimized)
    DB.showIcons = Flag(DB.showIcons)
    DB.showPets = Flag(DB.showPets)
    DB.showValues = Flag(DB.showValues)
    DB.hideOutOfCombat = Flag(DB.hideOutOfCombat)
    DB.onlyWithThreat = Flag(DB.onlyWithThreat)
    DB.onlyInGroup = Flag(DB.onlyInGroup)
    DB.warnEnabled = Flag(DB.warnEnabled)
    local p = DB.point
    if type(p) ~= "table" or type(p[1]) ~= "string" or (p[2] ~= nil and type(p[2]) ~= "string") or type(p[3]) ~= "number" or type(p[4]) ~= "number" then
        DB.point = { "CENTER", "CENTER", 300, 0 }
    end
end

local function GetClassRGB(class)
    if IsSecret(class) or not class then
        return 0.6, 0.6, 0.6
    end
    local t = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class])
        or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
        or FALLBACK_CLASS_COLORS[class]
    if t then
        return t.r, t.g, t.b
    end
    return 0.6, 0.6, 0.6
end

local function InRaid()
    if IsInRaid then
        local r = IsInRaid()
        if not IsSecret(r) then
            return r and true or false
        end
    end
    if GetNumRaidMembers then
        local n = GetNumRaidMembers()
        if not IsSecret(n) and type(n) == "number" then
            return n > 0
        end
    end
    return false
end

local function InGroup()
    if IsInGroup then
        local g = IsInGroup()
        if not IsSecret(g) then
            return g and true or false
        end
    end
    if GetNumGroupMembers then
        local n = GetNumGroupMembers()
        if not IsSecret(n) and type(n) == "number" then
            return n > 0
        end
    end
    if GetNumRaidMembers then
        local n = GetNumRaidMembers()
        if not IsSecret(n) and type(n) == "number" and n > 0 then
            return true
        end
    end
    if GetNumPartyMembers then
        local n = GetNumPartyMembers()
        if not IsSecret(n) and type(n) == "number" and n > 0 then
            return true
        end
    end
    return false
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
    if heldPet then
        pool[#pool + 1] = heldPet
        heldPet = nil
    end
    playerEntry = nil
    petEntry = nil
    for i = #data, 1, -1 do
        pool[#pool + 1] = data[i]
        data[i] = nil
    end
end

local function NewEntry()
    local e = remove(pool) or {}
    local idx = #data + 1
    data[idx] = e
    e.order = idx
    return e
end

local function PlainPct(entry)
    if not entry or IsSecret(entry.pct) or type(entry.pct) ~= "number" then
        return nil
    end
    return entry.pct
end

local function PlainGuid(unit)
    if not UnitGUID then
        return nil
    end
    local guid = UnitGUID(unit)
    if IsSecret(guid) then
        return nil
    end
    return guid
end

-- true, false, or nil when the client will not allow the comparison.
-- Group tokens such as raid12 can come back secret on a restricted map,
-- so a guid match is the backup. The "player" and "pet" tokens never need this.
local function SameUnit(unit, other)
    if unit == other then
        return true
    end
    if UnitIsUnit then
        local same = UnitIsUnit(unit, other)
        if not IsSecret(same) then
            return same and true or false
        end
    end
    if UnitGUID then
        local targetGuid = PlainGuid(other)
        if targetGuid then
            local guid = PlainGuid(unit)
            if guid then
                return guid == targetGuid
            end
        end
    end
    return nil
end

local function WipeIdentity()
    petSerial = petSerial + 1
    for unit in pairs(identity) do
        identity[unit] = nil
    end
end

-- Name, class and "is this me / my pet?" stay valid until the roster, a pet,
-- or a name resolves. Threat numbers are never cached.
local function GetIdentity(unit, isPet)
    local id = identity[unit]
    if id then
        return id
    end
    local name = UnitName(unit)
    local class
    local isPlayer = false
    local playerChecked = false
    local isOwnPet = false
    local petChecked = false

    if isPet then
        if unit == "pet" or unit == "playerpet" then
            isOwnPet = true
            petChecked = true
        elseif IS_PARTY_UNIT[unit] then
            isOwnPet = false
            petChecked = true
        else
            local petExists = UnitExists("pet")
            if not IsSecret(petExists) then
                if not petExists then
                    isOwnPet = false
                    petChecked = true
                else
                    local same = SameUnit(unit, "pet")
                    if same ~= nil then
                        isOwnPet = same
                        petChecked = true
                    end
                end
            end
        end
        if IsSecret(name) then
            transient.name = name
            transient.class = nil
            transient.isPlayer = false
            transient.playerChecked = false
            transient.isOwnPet = isOwnPet
            transient.petChecked = petChecked
            transient.iconID = unit
            transient.petSerial = petSerial
            return transient
        end
        if not name or name == "" then
            transient.name = "Pet"
            transient.class = nil
            transient.isPlayer = false
            transient.playerChecked = false
            transient.isOwnPet = isOwnPet
            transient.petChecked = petChecked
            transient.iconID = unit
            transient.petSerial = petSerial
            return transient
        end
    else
        if unit == "player" then
            isPlayer = true
            playerChecked = true
        elseif IS_PARTY_UNIT[unit] then
            isPlayer = false
            playerChecked = true
        else
            local same = SameUnit(unit, "player")
            if same ~= nil then
                isPlayer = same
                playerChecked = true
            end
        end
        local _
        _, class = UnitClass(unit)
        if IsSecret(name) or IsSecret(class) then
            if IsSecret(name) then
                transient.name = name
            elseif not name or name == "" then
                transient.name = UNKNOWN or "Unknown"
            else
                transient.name = name
            end
            if IsSecret(class) then
                transient.class = nil
            else
                transient.class = class
            end
            transient.isPlayer = isPlayer
            transient.playerChecked = playerChecked
            transient.isOwnPet = false
            transient.petChecked = false
            transient.iconID = nil
            transient.petSerial = nil
            return transient
        end
        if not name or name == "" or not class then
            transient.name = (name and name ~= "") and name or UNKNOWN or "Unknown"
            transient.class = class
            transient.isPlayer = isPlayer
            transient.playerChecked = playerChecked
            transient.isOwnPet = false
            transient.petChecked = false
            transient.iconID = nil
            transient.petSerial = nil
            return transient
        end
    end
    id = {
        name = name,
        class = class,
        isPlayer = isPlayer,
        playerChecked = playerChecked,
        isOwnPet = isOwnPet,
        petChecked = petChecked,
    }
    if isPet then
        local guid = PlainGuid(unit)
        if not guid then
            id.iconID = unit
            id.petSerial = petSerial
        else
            id.iconID = guid
            id.petSerial = 0
        end
    end
    identity[unit] = id
    return id
end

local function SortData(a, b)
    if a == b then
        return false
    end
    if a.secret ~= b.secret then
        return not a.secret
    end
    if a.secret then
        local ap = PlainPct(a)
        local bp = PlainPct(b)
        local aHasPct = ap ~= nil
        local bHasPct = bp ~= nil
        if aHasPct ~= bHasPct then
            return aHasPct
        end
        if aHasPct and ap ~= bp then
            return ap > bp
        end
        local as = a.status or -1
        local bs = b.status or -1
        if as ~= bs then
            return as > bs
        end
    else
        if a.value ~= b.value then
            return a.value > b.value
        end
    end
    if a.isTanking ~= b.isTanking then
        return a.isTanking and not b.isTanking
    end
    local aNameSecret = IsSecret(a.name)
    local bNameSecret = IsSecret(b.name)
    if aNameSecret ~= bNameSecret then
        return not aNameSecret
    end
    if not aNameSecret then
        local an = a.name or ""
        local bn = b.name or ""
        if an ~= bn then
            return an < bn
        end
    end
    return (a.order or 0) < (b.order or 0)
end

local function Hostile(unit)
    local exists = UnitExists(unit)
    if IsSecret(exists) or not exists then
        return false
    end
    local can = UnitCanAttack("player", unit)
    if IsSecret(can) then
        -- Compound tokens such as targettarget are hidden on restricted maps.
        -- Treat that as hostile so a healer still tracks the tank's target.
        return true
    end
    return can and true or false
end

-- Target mode prefers your target, then whatever your target is fighting
-- (so a healer targeting the tank still sees the boss). Focus mode does
-- the same with focus / focustarget.
local function GetMobUnit()
    if DB.mode == "focus" then
        if Hostile("focus") then
            return "focus"
        end
        if Hostile("focustarget") then
            return "focustarget"
        end
        return nil
    end
    if Hostile("target") then
        return "target"
    end
    if Hostile("targettarget") then
        return "targettarget"
    end
    return nil
end

local function AddUnit(unit, mob, isPet)
    local exists = UnitExists(unit)
    if IsSecret(exists) or not exists then
        if identity[unit] then
            identity[unit] = nil
        end
        return
    end
    local id = GetIdentity(unit, isPet)
    if not id then
        return
    end
    if isPet then
        if unit ~= "pet" then
            if id.petChecked then
                if id.isOwnPet then
                    return
                end
            else
                local same = SameUnit(unit, "pet")
                if same ~= nil then
                    if identity[unit] == id then
                        id.isOwnPet = same
                        id.petChecked = true
                    end
                    if same then
                        return
                    end
                end
            end
        end
    else
        if unit ~= "player" then
            if id.playerChecked then
                if id.isPlayer then
                    return
                end
            else
                local same = SameUnit(unit, "player")
                if same ~= nil then
                    if identity[unit] == id then
                        id.isPlayer = same
                        id.playerChecked = true
                    end
                    if same then
                        return
                    end
                end
            end
        end
    end
    if not UnitDetailedThreatSituation then
        if not apiMissing then
            apiMissing = true
            NS.Print("This client has no threat readout, so live bars stay empty. Test mode still works.")
        end
        return
    end
    local ok, isTanking, status, scaledPct, rawPct, value = pcall(UnitDetailedThreatSituation, unit, mob)
    if not ok then
        return
    end

    local tankSecret = IsSecret(isTanking)
    local statusSecret = IsSecret(status)
    local scaledSecret = IsSecret(scaledPct)
    local rawSecret = IsSecret(rawPct)
    local valueSecret = IsSecret(value)
    local valuesSecret = scaledSecret or rawSecret or valueSecret
    local plainStatus = (not statusSecret and type(status) == "number") and status or nil
    if not plainStatus and valuesSecret and UnitThreatSituation then
        local okS, fallbackStatus = pcall(UnitThreatSituation, unit, mob)
        if okS and not IsSecret(fallbackStatus) and type(fallbackStatus) == "number" then
            plainStatus = fallbackStatus
        end
    end
    local tanking = (not tankSecret and isTanking) or (plainStatus and plainStatus >= 2)

    if not valuesSecret then
        if type(value) ~= "number" or value <= 0 then
            if type(rawPct) == "number" and rawPct > 0 then
                value = rawPct
            elseif type(scaledPct) == "number" and scaledPct > 0 then
                value = scaledPct
            elseif tanking then
                value = (type(scaledPct) == "number" and scaledPct) or (type(rawPct) == "number" and rawPct) or 0
            else
                return
            end
        end
    end

    local e
    if isPet and not DB.showPets then
        e = remove(pool) or {}
        e.order = 0
        heldPet = e
    else
        e = NewEntry()
    end
    e.unit = unit
    e.name = id.name
    e.class = id.class
    e.isPet = isPet
    e.isPlayer = id.isPlayer and true or false
    e.isTanking = tanking and true or false
    e.status = plainStatus
    e.secret = valuesSecret
    if valuesSecret then
        if scaledSecret then
            e.pct = scaledPct
        elseif type(scaledPct) == "number" then
            e.pct = scaledPct
        elseif rawSecret then
            e.pct = rawPct
        elseif type(rawPct) == "number" then
            e.pct = rawPct
        else
            e.pct = tanking and 100 or 0
        end
        if rawSecret then
            e.rawPct = rawPct
        elseif type(rawPct) == "number" then
            e.rawPct = rawPct
        else
            e.rawPct = e.pct
        end
        if valueSecret then
            e.value = value
        elseif type(value) == "number" then
            e.value = value
        else
            e.value = e.pct
        end
    else
        -- Tanking units report as 100% scaled threat so the bar and warning match
        -- the client's aggro state even when scaledPct briefly lags.
        if e.isTanking then
            e.pct = 100
        elseif type(scaledPct) == "number" then
            e.pct = scaledPct
        elseif type(rawPct) == "number" then
            e.pct = rawPct
        else
            e.pct = 0
        end
        if type(rawPct) == "number" then
            e.rawPct = rawPct
        else
            e.rawPct = e.pct
        end
        e.value = value
    end
    if isPet then
        local c = COLOR.pet
        e.r, e.g, e.b = c[1], c[2], c[3]
        if IsSecret(id.iconID) or not id.iconID then
            e.iconID = unit
        else
            e.iconID = id.iconID
        end
        e.petSerial = id.petSerial or petSerial
    else
        e.r, e.g, e.b = GetClassRGB(id.class)
        e.iconID = nil
        e.petSerial = nil
    end
    if e.isPlayer then
        playerEntry = e
    elseif isPet and (unit == "pet" or id.isOwnPet) then
        petEntry = e
    end
end

local function CollectThreat(mob)
    ClearData()
    local pets = DB.showPets
    -- Always read you and your pet from their own tokens. In a raid the same
    -- unit is also raidN / raidpetN, and UnitIsUnit on that slot can be secret.
    AddUnit("player", mob, false)
    if pets or DB.warnEnabled then
        AddUnit("pet", mob, true)
    end
    if InRaid() then
        -- Raid unit ids are not always packed into 1..count, so check every slot.
        -- Empty slots stop at UnitExists and never call the threat API.
        for i = 1, 40 do
            AddUnit(RAID[i], mob, false)
            if pets then
                AddUnit(RAIDPET[i], mob, true)
            end
        end
    elseif InGroup() then
        for i = 1, 4 do
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

local TEST_BASE = { 10000, 7200, 9000, 5100, 4200, 3600, 3000, 2400, 1800 }
local TEST_SWING = { 200, 180, 1600, 160, 140, 120, 100, 80, 60 }
local testPhase = 0

local function BuildTestData()
    ClearData()
    testPhase = testPhase + 0.35
    if not testPlayerName or testPlayerName == "You" then
        local playerName = UnitName("player")
        if IsSecret(playerName) or not playerName or playerName == "" or playerName == UNKNOWN then
            testPlayerName = "You"
        else
            testPlayerName = playerName
        end
        local _, myClass = UnitClass("player")
        if IsSecret(myClass) then
            myClass = nil
        end
        testPlayerClass = myClass
    end
    local function RowValue(i)
        local base = TEST_BASE[i] or 1500
        local swing = TEST_SWING[i] or 50
        return base + math.sin(testPhase + i) * swing
    end
    local tankValue = RowValue(1)
    for i = 1, #TEST_ROSTER do
        local e = NewEntry()
        local name, class = TEST_ROSTER[i][1], TEST_ROSTER[i][2]
        local isPlayer = (name == nil)
        if not name then
            name = testPlayerName
            class = testPlayerClass
        end
        local value = RowValue(i)
        if isPlayer and value > tankValue * 0.99 then
            value = tankValue * 0.99
        end
        if value < 0 then
            value = 0
        end
        e.unit = nil
        e.name = name
        e.class = class
        e.isPet = false
        e.isPlayer = isPlayer
        e.isTanking = false
        e.secret = false
        e.status = nil
        e.value = value
        e.pct = 0
        e.rawPct = 0
        e.r, e.g, e.b = GetClassRGB(class)
        e.iconID = nil
        e.petSerial = nil
        if isPlayer then
            playerEntry = e
        end
    end
    if DB.showPets then
        local e = NewEntry()
        local owner = playerEntry and playerEntry.value or 0
        local hasPet = false
        if UnitExists then
            local exists = UnitExists("pet")
            hasPet = not IsSecret(exists) and exists and true or false
        end
        e.unit = hasPet and "pet" or nil
        e.name = testPlayerName .. "'s Pet"
        e.class = nil
        e.isPet = true
        e.isPlayer = false
        e.isTanking = false
        e.secret = false
        e.status = nil
        e.value = owner * 0.45
        e.pct = 0
        e.rawPct = 0
        local c = COLOR.pet
        e.r, e.g, e.b = c[1], c[2], c[3]
        e.iconID = "testpet"
        e.petSerial = 0
        petEntry = e
    end
    sort(data, SortData)
    local top = (data[1] and data[1].value) or 1
    if top <= 0 then
        top = 1
    end
    for i = 1, #data do
        local e = data[i]
        e.isTanking = (i == 1)
        e.pct = min(100, e.value / top * 100)
        e.rawPct = e.pct
    end
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
    if GameTooltip.IsOwned and GameTooltip:IsOwned(self) then
        GameTooltip:ClearLines()
    else
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    end
    local r, g, b = e.r or 1, e.g or 1, e.b or 1
    if IsSecret(e.name) then
        pcall(GameTooltip.SetText, GameTooltip, e.name, r, g, b)
    else
        GameTooltip:SetText((e.name and e.name ~= "") and e.name or UNKNOWN or "Unknown", r, g, b)
    end
    local function AddTooltipValue(label, value, asPercent)
        if IsSecret(value) then
            if not pcall(GameTooltip.AddDoubleLine, GameTooltip, label, value, 0.8, 0.8, 0.8, 1, 1, 1) then
                GameTooltip:AddDoubleLine(label, "Hidden", 0.8, 0.8, 0.8, 1, 1, 1)
            end
            return
        end
        local text = asPercent and format("%.1f%%", value or 0) or FormatValue(value or 0)
        GameTooltip:AddDoubleLine(label, text, 0.8, 0.8, 0.8, 1, 1, 1)
    end
    AddTooltipValue("Threat", e.value, false)
    AddTooltipValue("Aggro %", e.pct, true)
    AddTooltipValue("Of tank", e.rawPct, true)
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
    if e.isPet then
        local key = e.unit or "pet"
        if e.iconID and not IsSecret(e.iconID) then
            key = e.iconID
        end
        local vis = false
        if e.unit and SetPortraitTexture then
            if UnitIsVisible then
                local v = UnitIsVisible(e.unit)
                vis = not IsSecret(v) and v and true or false
            else
                local exists = UnitExists(e.unit)
                vis = not IsSecret(exists) and exists and true or false
            end
        end
        if row.iconPet ~= key or row.iconPetSerial ~= e.petSerial or (vis and not row.iconPetVis) then
            local drawn = false
            if vis then
                drawn = pcall(SetPortraitTexture, row.icon, e.unit)
            end
            if drawn then
                row.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
            else
                row.icon:SetTexture("Interface\\Icons\\Ability_Hunter_BeastCall")
                row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
            row.iconPet = key
            row.iconPetSerial = e.petSerial
            row.iconPetVis = drawn
            row.iconClass = nil
        end
        return
    end
    local classKey = false
    if not IsSecret(e.class) then
        classKey = e.class or false
    end
    if row.iconClass ~= classKey then
        local coords = classKey and ((CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classKey]) or CLASS_COORDS[classKey])
        if coords then
            row.icon:SetTexture(CLASS_TEXTURE)
            row.icon:SetTexCoord(coords[1] + 0.015, coords[2] - 0.015, coords[3] + 0.015, coords[4] - 0.015)
        else
            row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        row.iconClass = classKey
        row.iconPet = nil
        row.iconPetVis = nil
    end
end

local function PaintSecretText(fs, showValues, value, pct)
    local plainPct = (not IsSecret(pct) and type(pct) == "number") and floor(pct + 0.5) or nil
    if showValues and IsNumberLike(value) and IsNumberLike(pct) then
        if plainPct then
            if pcall(fs.SetFormattedText, fs, "%.0f (%d%%)", value, plainPct) then
                return
            end
            if pcall(fs.SetFormattedText, fs, "%s (%d%%)", value, plainPct) then
                return
            end
        end
        if pcall(fs.SetFormattedText, fs, "%.0f (%.0f%%)", value, pct) then
            return
        end
        if pcall(fs.SetFormattedText, fs, "%s (%s%%)", value, pct) then
            return
        end
    end
    if plainPct then
        fs:SetText(PCT_TEXT[plainPct] or (tostring(plainPct) .. "%"))
        return
    end
    if IsNumberLike(pct) and pcall(fs.SetFormattedText, fs, "%.0f%%", pct) then
        return
    end
    if IsNumberLike(pct) and pcall(fs.SetFormattedText, fs, "%s%%", pct) then
        return
    end
    if IsNumberLike(pct) then
        pcall(fs.SetText, fs, pct)
    end
end

local function Render()
    if not ui.body or not ui.frame or not ui.frame:IsShown() or DB.minimized then
        return
    end
    LayoutRows()
    local top = 0
    for i = 1, #data do
        local entry = data[i]
        if entry and not entry.secret and not IsSecret(entry.value) and type(entry.value) == "number" and entry.value > top then
            top = entry.value
        end
    end
    local barMax = top > 0 and top or 100
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
            if e.secret then
                if not row.secretMode then
                    row.secretMode = true
                    row.maxThreat = nil
                    row.barValue = nil
                    row.pctInt = nil
                    row.rawValue = nil
                    row.valueText = nil
                    row.unitName = nil
                    row.bar:SetMinMaxValues(0, 100)
                end
                if IsNumberLike(e.pct) then
                    pcall(row.bar.SetValue, row.bar, e.pct)
                end
                if IsSecret(e.name) or row.rank ~= i or row.unitName ~= e.name then
                    row.rank = i
                    nameChanged = true
                    if IsSecret(e.name) then
                        row.unitName = nil
                        if not pcall(row.name.SetFormattedText, row.name, "%d. %s", i, e.name) then
                            pcall(row.name.SetText, row.name, e.name)
                        end
                    else
                        row.unitName = e.name
                        row.name:SetText(RANK_PREFIX[i] .. (e.name or ""))
                    end
                end
                PaintSecretText(row.value, showValues, e.value, e.pct)
            else
                if row.secretMode then
                    row.secretMode = false
                    row.maxThreat = nil
                    row.barValue = nil
                    row.pctInt = nil
                    row.rawValue = nil
                    row.valueText = nil
                    row.unitName = nil
                end
                local maxChanged = row.maxThreat ~= barMax
                if maxChanged then
                    row.maxThreat = barMax
                    row.bar:SetMinMaxValues(0, barMax)
                end
                local fillVal = top > 0 and e.value or e.pct
                if maxChanged or row.barValue ~= fillVal then
                    row.barValue = fillVal
                    row.bar:SetValue(fillVal)
                end
                if IsSecret(e.name) then
                    row.rank = i
                    row.unitName = nil
                    nameChanged = true
                    if not pcall(row.name.SetFormattedText, row.name, "%d. %s", i, e.name) then
                        pcall(row.name.SetText, row.name, e.name)
                    end
                elseif row.rank ~= i or row.unitName ~= e.name then
                    row.rank = i
                    row.unitName = e.name
                    row.name:SetText(RANK_PREFIX[i] .. (e.name or ""))
                    nameChanged = true
                end
                local pctInt = floor(e.pct + 0.5)
                local qVal = showValues and QuantizeValue(e.value) or nil
                if row.pctInt ~= pctInt or row.valueMode ~= showValues or (showValues and row.rawValue ~= qVal) then
                    local pctText = PCT_TEXT[pctInt] or (tostring(pctInt) .. "%")
                    local text = showValues and (FormatValue(e.value) .. " (" .. pctText .. ")") or pctText
                    row.pctInt = pctInt
                    row.rawValue = qVal
                    row.valueMode = showValues
                    if row.valueText ~= text then
                        row.valueText = text
                        row.value:SetText(text)
                    end
                end
            end
            SetRowIcon(row, e)
            row.entry = e
            if not row:IsShown() then
                row:Show()
            end
            if e.secret then
                if hoveredRow == row then
                    Row_OnEnter(row)
                end
            elseif hoveredRow == row and (nameChanged or row.tipValue ~= e.value or row.tipPct ~= e.pct or row.tipRaw ~= e.rawPct or row.tipTank ~= e.isTanking) then
                row.tipValue, row.tipPct, row.tipRaw, row.tipTank = e.value, e.pct, e.rawPct, e.isTanking
                Row_OnEnter(row)
            else
                row.tipValue, row.tipPct, row.tipRaw, row.tipTank = e.value, e.pct, e.rawPct, e.isTanking
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
    if DB.hideOutOfCombat and not (inCombat or UnitAffectingCombat("player")) then
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
        local prevScale = ui.appliedScale
        f:SetScale(DB.scale)
        ui.appliedScale = DB.scale
        if prevScale and prevScale > 0 and IsTopLeftAnchored(f) and type(DB.point) == "table" and type(DB.point[3]) == "number" and type(DB.point[4]) == "number" then
            local ratio = prevScale / DB.scale
            local newX = DB.point[3] * ratio
            local newY = DB.point[4] * ratio
            DB.point[3] = newX
            DB.point[4] = newY
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", newX, newY)
        end
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
    if ui.menu and ui.appliedMenuScale ~= DB.scale then
        ui.menu:SetScale(DB.scale)
        ui.appliedMenuScale = DB.scale
    end
    -- Pets and visibility rules need a fresh scan. Sliders that only change
    -- the look (scale, opacity, bar size) do not.
    local sig = (DB.showPets and "1" or "0")
        .. (DB.onlyWithThreat and "1" or "0")
        .. (DB.hideOutOfCombat and "1" or "0")
        .. (DB.onlyInGroup and "1" or "0")
    if ui.settingsSig ~= sig then
        ui.settingsSig = sig
        NS.Update()
        return
    end
    NS.UpdateVisibility()
    CheckWarning()
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
        if NS.RefreshOptions then
            NS.RefreshOptions()
        end
        NS.Print("Window hidden. Use /xtm show or the settings window to show it again.")
    else
        NS.Update()
        if NS.RefreshOptions then
            NS.RefreshOptions()
        end
        if not ui.frame:IsShown() then
            NS.Print("Window enabled, but one of your settings is hiding it right now (combat, group or threat). Type /xtm to change that.")
        end
    end
end

function NS.SetTestMode(on)
    testMode = on and true or false
    testPhase = 0
    if testMode then
        DB.hidden = false
    else
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
    if NS.RefreshOptions then
        NS.RefreshOptions()
    end
    NS.Print("Window position and size reset.")
end

function NS.ResetAllSettings()
    if NS.ResetDefaults then
        NS.ResetDefaults()
    end
    SanitizeDB()
    RestorePosition()
    NS.ApplySettings()
    if NS.RefreshOptions then
        NS.RefreshOptions()
    end
    NS.Print("All settings reset to defaults.")
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

local function WarningSource()
    if not DB.warnEnabled then
        return nil
    end
    if playerEntry and playerEntry.isTanking then
        return nil
    end
    local best
    if playerEntry then
        best = playerEntry
    end
    if petEntry and not petEntry.isTanking then
        if not best then
            best = petEntry
        else
            local petPct = PlainPct(petEntry)
            local bestPct = PlainPct(best)
            if petPct ~= nil and bestPct ~= nil then
                if petPct > bestPct then
                    best = petEntry
                end
            elseif petEntry.secret or best.secret then
                if (petEntry.status or -1) > (best.status or -1) then
                    best = petEntry
                end
            elseif petPct and not bestPct then
                best = petEntry
            end
        end
    end
    return best
end

function CheckWarning()
    if not ui.title then
        return
    end
    local me = WarningSource()
    local hot = false
    local pct = PlainPct(me)
    if me and pct == nil then
        -- Status 1 is the client's "about to pull" state. The percent slider
        -- cannot be read while the threat percent is secret.
        hot = me.status == 1
        if hot then
            if not warned then
                warned = true
                if not testMode then
                    PlayWarning()
                end
            end
        else
            warned = false
        end
    else
        pct = pct or 0
        hot = me and pct >= DB.warnThreshold and true or false
        if hot then
            if not warned then
                warned = true
                -- Test mode still turns the title red. The sound is reserved for a real fight.
                if not testMode then
                    PlayWarning()
                end
            end
        elseif not me or pct < DB.warnThreshold - 10 then
            warned = false
        end
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
        local groupOk = not DB.onlyInGroup or InGroup()
        local canShow = not DB.hidden and groupOk and (not DB.hideOutOfCombat or inCombat)
        local warnActive = DB.warnEnabled and inCombat and groupOk
        if not canShow and not warnActive then
            if lastMobGUID or #data > 0 or playerEntry or petEntry then
                ClearData()
            end
            lastMobGUID = nil
            lastMobName = nil
            warned = false
            SetTargetLabel("")
            NS.UpdateVisibility()
            CheckWarning()
            return
        end
        local mob = GetMobUnit()
        if mob then
            local guid
            if UnitGUID then
                guid = UnitGUID(mob)
            end
            if IsSecret(guid) or type(guid) ~= "string" then
                guid = "token:" .. mob
            end
            if guid ~= lastMobGUID then
                lastMobGUID = guid
                warned = false
                lastMobName = nil
            end
            CollectThreat(mob)
            local name = UnitName(mob)
            if IsSecret(name) then
                lastMobName = nil
                ui.targetLabel = nil
                pcall(ui.targetText.SetText, ui.targetText, name)
            else
                if not name or name == "" then
                    name = UNKNOWN or "Unknown"
                end
                if name ~= lastMobName then
                    lastMobName = name
                    SetTargetLabel(name)
                end
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
    if ok then
        scriptError = false
    elseif not scriptError then
        scriptError = true
        NS.Print("Hit an error and kept running (" .. tostring(err) .. "). If the bars look wrong, type /reload.")
    end
    tickElapsed = 0
    if SyncDriver then
        SyncDriver(true)
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
    if threatDirty and usingOnUpdate then
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

local function Menu_OnEvent(self, _, button)
    if button == "RightButton" and ui.titleBar and ui.titleBar:IsMouseOver() then
        return
    end
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
            if item.checked then
                b.check:Show()
            else
                b.check:Hide()
            end
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
        ui.moving = true
        ui.frame:StartMoving()
    end
end

local function TitleBar_OnDragStop()
    if not ui.moving then
        return
    end
    ui.moving = false
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
    local w = ClampDB(floor((ui.frame:GetWidth() or DB.width) + 0.5), MIN_WIDTH, MAX_WIDTH, DB.width)
    local h = ClampDB(floor((ui.frame:GetHeight() or DB.height) + 0.5), MIN_HEIGHT, MAX_HEIGHT, DB.height)
    DB.width = w
    DB.height = h
    ui.frame:SetSize(w, h)
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
        if ui.moving then
            TitleBar_OnDragStop()
        end
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

function SyncDriver(skipCombatRefresh)
    if not ui.frame or not DB then
        return
    end
    if not skipCombatRefresh then
        inCombat = UnitAffectingCombat("player") and true or false
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
    -- Out of combat: only poll while a hostile target/focus is up and the
    -- window is allowed to show (including waiting for threat to appear).
    if not DB.hideOutOfCombat and (not DB.onlyInGroup or InGroup()) and GetMobUnit() then
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
            if NS.InitOptions then
                NS.InitOptions()
            end
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
        if NS.InitOptions then
            NS.InitOptions()
        end
        for _, e in ipairs(EVENTS) do
            pcall(self.RegisterEvent, self, e)
        end
        if not (self.RegisterUnitEvent and pcall(self.RegisterUnitEvent, self, "UNIT_TARGET", "player", "target", "focus")) then
            pcall(self.RegisterEvent, self, "UNIT_TARGET")
        end
        NS.Print("v" .. NS.VERSION .. " loaded. Type |cffffd100/xtm|r for options or |cffffd100/xtm help|r for commands.")
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

    if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" then
        lastMobGUID = nil
        lastMobName = nil
        RequestUpdate(true)
        return
    end

    if event == "UNIT_TARGET" then
        if arg1 == "player" or arg1 == "target" or arg1 == "focus" then
            lastMobGUID = nil
            lastMobName = nil
            RequestUpdate(false)
        end
        return
    end

    if event == "UNIT_NAME_UPDATE" then
        if not arg1 then
            return
        end
        local tracked = identity[arg1] ~= nil
            or arg1 == "target" or arg1 == "focus"
            or arg1 == "targettarget" or arg1 == "focustarget"
            or arg1 == "player" or arg1 == "pet"
        if not tracked then
            return
        end
        identity[arg1] = nil
        if arg1 == "target" or arg1 == "focus" or arg1 == "targettarget" or arg1 == "focustarget" then
            lastMobName = nil
        end
        RequestUpdate(false)
        return
    end

    if event == "UNIT_PET" then
        petSerial = petSerial + 1
        identity["pet"] = nil
        identity["playerpet"] = nil
        for i = 1, 4 do
            identity[PARTYPET[i]] = nil
        end
        for i = 1, 40 do
            identity[RAIDPET[i]] = nil
        end
        if arg1 then
            identity[arg1] = nil
        end
        RequestUpdate(not inCombat)
        return
    end

    if event == "UNIT_THREAT_LIST_UPDATE" then
        if testMode or (DB.hidden and not DB.warnEnabled) then
            return
        end
        if threatDirty and usingOnUpdate and tickElapsed < EVENT_THROTTLE then
            return
        end
        -- LIST_UPDATE's unit is the mob. Ignore unrelated nameplates.
        local mob = GetMobUnit()
        if mob and arg1 then
            if SameUnit(arg1, mob) == false then
                return
            end
        elseif not mob and not inCombat then
            return
        end
        if inCombat or UnitAffectingCombat("player") then
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
        if threatDirty and usingOnUpdate and tickElapsed < EVENT_THROTTLE then
            return
        end
        -- SITUATION_UPDATE's unit is the player/pet whose status changed.
        if inCombat or UnitAffectingCombat("player") then
            inCombat = true
            RequestUpdate(false)
        else
            inCombat = false
            RequestUpdate(true)
        end
        return
    end

    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        WipeIdentity()
        if event == "PLAYER_ENTERING_WORLD" then
            testPlayerName = nil
            testPlayerClass = nil
            lastMobGUID = nil
            lastMobName = nil
            RequestUpdate(true)
        else
            RequestUpdate(not inCombat)
        end
        return
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
    msg = ((msg or ""):match("^%s*(.-)%s*$") or ""):lower()
    if msg == "" or msg == "config" or msg == "options" or msg == "settings" then
        if NS.OpenOptions then
            NS.OpenOptions()
        elseif NS.ToggleOptions then
            NS.ToggleOptions()
        end
    elseif msg == "show" then
        NS.SetHidden(false)
    elseif msg == "hide" then
        NS.SetHidden(true)
    elseif msg == "toggle" then
        NS.SetHidden(not DB.hidden)
    elseif msg == "test" then
        NS.ToggleTestMode()
    elseif msg == "lock" or msg == "unlock" then
        NS.ToggleLock()
    elseif msg == "reset" then
        NS.ResetPosition()
    elseif msg == "target" or msg == "focus" then
        NS.SetMode(msg)
        NS.Print("Now tracking threat on your " .. msg .. ".")
    elseif msg == "check" or msg == "status" then
        local mob = GetMobUnit()
        local mobName = "nobody"
        if mob then
            local name = UnitName(mob)
            if IsSecret(name) or not name or name == "" then
                mobName = "an enemy"
            else
                mobName = name
            end
        end
        local where = "not on screen"
        if DB.hidden then
            where = "hidden by you"
        elseif ui.frame:IsShown() then
            where = DB.minimized and "minimized" or "on screen"
        end
        local why = nil
        if not DB.hidden and not testMode and not ui.frame:IsShown() then
            if DB.onlyInGroup and not InGroup() then
                why = "Only show in a group is on, and you are solo."
            elseif DB.hideOutOfCombat and not UnitAffectingCombat("player") then
                why = "Hide when out of combat is on."
            elseif DB.onlyWithThreat and #data == 0 then
                why = "Only show when there is threat is on, and nobody has threat yet."
            end
        end
        NS.Print("Mode: " .. (DB.mode == "focus" and "focus" or "target") .. ". Window: " .. where .. ". Tracking: " .. mobName .. ".")
        NS.Print("Combat: " .. (UnitAffectingCombat("player") and "yes" or "no")
            .. ". Group: " .. (InGroup() and "yes" or "no")
            .. ". Test mode: " .. (testMode and "on" or "off") .. ".")
        NS.Print("Threat readout: " .. (UnitDetailedThreatSituation and "available" or "missing")
            .. ". People on the list: " .. tostring(#data) .. ".")
        if (playerEntry and playerEntry.secret) or (data[1] and data[1].secret) then
            NS.Print("Exact threat numbers are hidden by the client right now. Bars still show aggro percent.")
        end
        NS.Print("Icons " .. (DB.showIcons and "on" or "off")
            .. ", pets " .. (DB.showPets and "on" or "off")
            .. ", numbers " .. (DB.showValues and "on" or "off")
            .. ", lock " .. (DB.locked and "on" or "off") .. ".")
        NS.Print("Only with threat " .. (DB.onlyWithThreat and "on" or "off")
            .. ", hide out of combat " .. (DB.hideOutOfCombat and "on" or "off")
            .. ", only in a group " .. (DB.onlyInGroup and "on" or "off") .. ".")
        NS.Print("Warning " .. (DB.warnEnabled and "on" or "off") .. " at " .. tostring(floor(DB.warnThreshold + 0.5)) .. "%.")
        if why then
            NS.Print(why)
        end
    else
        NS.Print("Commands:")
        NS.Print("  /xtm - open settings")
        NS.Print("  /xtm show | hide | toggle - show or hide the threat window")
        NS.Print("  /xtm test - toggle test bars")
        NS.Print("  /xtm lock - lock or unlock the window")
        NS.Print("  /xtm target | focus - choose which enemy to track")
        NS.Print("  /xtm reset - reset window position and size")
        NS.Print("  /xtm check - show whether each option is on and why the window may be hidden")
    end
end
