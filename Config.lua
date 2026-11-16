--[[
    Xius Threat Meter - Config.lua
    Saved settings, colors and shared styling helpers.
]]

local ADDON, NS = ...

local XiusCore = _G.XiusCore or _G.XiusUI or _G.XiusCoreSettingsLib
if not XiusCore and C_AddOns and C_AddOns.IsAddOnLoaded then
    local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, "XiusCore")
    XiusCore = ok and loaded and true or false
end
if not XiusCore and IsAddOnLoaded then
    local ok, loaded = pcall(IsAddOnLoaded, "XiusCore")
    XiusCore = ok and loaded and true or false
end
if not XiusCore then
    return
end

NS.VERSION = "1.6.2"
NS.STYLE_VERSION = 9
NS.FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
NS.WHITE = "Interface\\Buttons\\WHITE8X8"

NS.COLOR = {
    gold = { 1, 209 / 255, 0, 1 },
    goldLine = { 1, 0.82, 0.35, 1 },
    goldLineDim = { 0.55, 0.42, 0.16, 1 },
    glow = { 0.22, 0.16, 0.08 },
    window = { 0, 0, 0 },
    buttonEdge = { 1, 0.82, 0.35, 1 },
    dash = { 1, 0.82, 0.35, 1 },
    rowEdge = { 0.05, 0.05, 0.06, 1 },
    menuBg = { 0.06, 0.06, 0.08, 0.98 },
    text = { 1, 1, 1, 1 },
    muted = { 0.62, 0.60, 0.56, 1 },
    pet = { 0.35, 0.75, 0.35 },
    warn = { 1, 0.25, 0.20, 1 },
}

NS.DEFAULTS = {
    point = { "CENTER", "CENTER", 300, 0 },
    width = 250,
    height = 190,
    hidden = false,
    locked = false,
    minimized = false,
    mode = "target",
    scale = 1,
    bgAlpha = 1,
    barHeight = 19,
    barSpacing = 2,
    showIcons = true,
    showPets = true,
    showValues = true,
    hideOutOfCombat = false,
    onlyWithThreat = false,
    onlyInGroup = false,
    warnEnabled = true,
    warnThreshold = 90,
    fontSize = 11,
    barTexture = "blizzard",
    roleMode = "auto",
}

NS.HUD_BORDER = { 1, 0.80, 0.32, 1 }
NS.HUD_OUTER = { 0, 0, 0, 1 }
NS.HEADER_BACKDROP = {
    bgFile = NS.WHITE,
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false,
    edgeSize = 12,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}
NS.HEADER_BUTTON_BACKDROP = {
    bgFile = NS.WHITE,
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false,
    edgeSize = 8,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
NS.BUTTON_BORDER = { 140 / 255, 114 / 255, 66 / 255, 1 }
NS.BACKDROP_MENU = {
    bgFile = NS.WHITE,
    edgeFile = NS.WHITE,
    tile = false,
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

NS.BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

local function CopyValue(v)
    if type(v) ~= "table" then
        return v
    end
    local t = {}
    for k, val in pairs(v) do
        t[k] = CopyValue(val)
    end
    return t
end

-- Xius Core keeps this addon's settings on XiusUIDB.threat and copies that
-- table when a profile changes. Saved variables then replace the global, so
-- rejoin the two tables here. The meter table is what the last session saved.
function NS.BindCoreDB()
    if type(XiusThreatMeterDB) ~= "table" then
        XiusThreatMeterDB = {}
    end
    if not (XiusUI and type(XiusUIDB) == "table") then
        return XiusThreatMeterDB
    end
    if type(XiusUIDB.threat) ~= "table" then
        XiusUIDB.threat = {}
    end
    local core = XiusUIDB.threat
    local live = XiusThreatMeterDB
    if live ~= core then
        local coreHas = next(core) ~= nil
        local liveHas = next(live) ~= nil
        if liveHas or not coreHas then
            for key in pairs(core) do
                core[key] = nil
            end
            for key, value in pairs(live) do
                core[key] = value
            end
        end
        XiusThreatMeterDB = core
    end
    return XiusThreatMeterDB
end

function NS.EnsureDefaults(db)
    db = db or NS.db
    if type(db) ~= "table" then
        return
    end
    for k, v in pairs(NS.DEFAULTS) do
        if db[k] == nil then
            db[k] = CopyValue(v)
        end
    end
end

function NS.InitDB()
    local db = NS.BindCoreDB()
    NS.EnsureDefaults(db)
    if (db.styleVersion or 0) < NS.STYLE_VERSION then
        db.styleVersion = NS.STYLE_VERSION
    end
    if not db.migratedBlizzardSkinV2 then
        if type(db.bgAlpha) == "number" and db.bgAlpha < 0.95 then
            db.bgAlpha = 1
        end
        if type(db.bgOpacity) == "number" and db.bgOpacity < 0.95 then
            db.bgOpacity = 1
            db.bgAlpha = 1
        end
        db.migratedBlizzardSkinV2 = true
    end
    NS.db = db
end

function NS.ResetLayout()
    local db = NS.db
    db.point = CopyValue(NS.DEFAULTS.point)
    db.width = NS.DEFAULTS.width
    db.height = NS.DEFAULTS.height
    db.minimized = false
    db.hidden = false
end

function NS.ResetDefaults()
    local db = NS.db
    if not db then
        return
    end
    for k, v in pairs(NS.DEFAULTS) do
        db[k] = CopyValue(v)
    end
    db.styleVersion = NS.STYLE_VERSION
end

----------------------------------------------------------------------
-- Drawing helpers
----------------------------------------------------------------------

function NS.ApplyBackdrop(frame, backdrop, bg, border)
    if not frame.SetBackdrop then
        return
    end
    frame:SetBackdrop(backdrop)
    frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

function NS.ApplyHudChrome(frame)
    if not frame or frame._xiusHudEdge then
        return
    end
    if frame.SetBackdrop then
        frame:SetBackdrop(nil)
    end
    local function Line()
        local line = frame:CreateTexture(nil, "OVERLAY")
        line:SetTexture(NS.WHITE)
        line:SetVertexColor(0, 0, 0, 1)
        return line
    end
    local top = Line()
    top:SetHeight(1)
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    local bottom = Line()
    bottom:SetHeight(1)
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    local left = Line()
    left:SetWidth(1)
    left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    local right = Line()
    right:SetWidth(1)
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    frame._xiusHudEdge = true
end

function NS.SetFont(fs, size, flags)
    fs:SetFont(NS.FONT, size, flags or "")
    if flags and flags ~= "" then
        fs:SetShadowOffset(0, 0)
    else
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
    end
end

function NS.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Xius Threat Meter:|r " .. tostring(msg))
end

function NS.SolidTexture(parent, layer, sublevel, c, a)
    local t = parent:CreateTexture(nil, layer, nil, sublevel or 0)
    t:SetTexture(NS.WHITE)
    t:SetVertexColor(c[1], c[2], c[3], a or c[4] or 1)
    return t
end

-- orientation "VERTICAL": c1 = bottom, c2 = top. "HORIZONTAL": c1 = left, c2 = right.
local gradientMode -- 1 = SetGradient(CreateColor), 2 = SetGradientAlpha, 3 = SetVertexColor

local function ApplyRawGradient(tex, orientation, r1, g1, b1, a1, r2, g2, b2, a2)
    if not gradientMode then
        if CreateColor and tex.SetGradient and pcall(tex.SetGradient, tex, orientation, CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2)) then
            gradientMode = 1
            return
        elseif tex.SetGradientAlpha and pcall(tex.SetGradientAlpha, tex, orientation, r1, g1, b1, a1, r2, g2, b2, a2) then
            gradientMode = 2
            return
        else
            gradientMode = 3
        end
    end
    if gradientMode == 1 then
        tex:SetGradient(orientation, CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2))
    elseif gradientMode == 2 then
        tex:SetGradientAlpha(orientation, r1, g1, b1, a1, r2, g2, b2, a2)
    else
        tex:SetVertexColor(r2, g2, b2, a2)
    end
end

function NS.SetGradient(tex, orientation, c1, a1, c2, a2)
    tex:SetTexture(NS.WHITE)
    tex:SetVertexColor(1, 1, 1, 1)
    ApplyRawGradient(tex, orientation, c1[1], c1[2], c1[3], a1, c2[1], c2[2], c2[3], a2)
end

function NS.CreateWindowBackground(frame, headerHeight)
    frame.bgTex = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    frame.bgTex:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -(headerHeight or 25))
    frame.bgTex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
end

function NS.SetWindowAlpha(frame, alpha)
    local tex = frame.bgTex
    if not tex then
        return
    end
    if not frame.bgReady then
        tex:SetTexture(NS.WHITE)
        frame.bgReady = true
    end
    if frame.appliedAlpha == alpha then
        return
    end
    frame.appliedAlpha = alpha
    local c = NS.COLOR.window
    tex:SetVertexColor(c[1], c[2], c[3], alpha)
end

-- A line or glow strip that fades out at both ends.
-- Returns a table of the three pieces so callers can hide/show them together.
function NS.CreateFadedStrip(parent, layer, sublevel, fadeWidth)
    local strip = {}
    strip.left = parent:CreateTexture(nil, layer, nil, sublevel)
    strip.mid = parent:CreateTexture(nil, layer, nil, sublevel)
    strip.right = parent:CreateTexture(nil, layer, nil, sublevel)
    strip.fade = fadeWidth
    return strip
end

function NS.AnchorFadedStrip(strip, parent, top, height)
    local fade = strip.fade
    strip.left:ClearAllPoints()
    strip.left:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, top)
    strip.left:SetSize(fade, height)
    strip.right:ClearAllPoints()
    strip.right:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, top)
    strip.right:SetSize(fade, height)
    strip.mid:ClearAllPoints()
    strip.mid:SetPoint("TOPLEFT", strip.left, "TOPRIGHT", 0, 0)
    strip.mid:SetPoint("BOTTOMRIGHT", strip.right, "BOTTOMLEFT", 0, 0)
end

function NS.ColorFadedStrip(strip, color, alpha, midBottom, midTop)
    NS.SetGradient(strip.left, "HORIZONTAL", color, 0, color, alpha)
    NS.SetGradient(strip.right, "HORIZONTAL", color, alpha, color, 0)
    if midBottom and midTop then
        NS.SetGradient(strip.mid, "VERTICAL", midBottom, alpha, midTop, alpha)
    else
        NS.SetGradient(strip.mid, "VERTICAL", color, alpha, color, alpha)
    end
end

-- 25px Damage Done header: rounded gold-bronze tooltip frame over a warm metallic fill.
function NS.CreateTitleBar(frame, height)
    local bar = CreateFrame("Frame", nil, frame, NS.BACKDROP_TEMPLATE)
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    bar:SetHeight(height)
    if bar.SetBackdrop then
        bar:SetBackdrop(NS.HEADER_BACKDROP)
        bar:SetBackdropColor(0.12, 0.10, 0.05, 0.98)
        bar:SetBackdropBorderColor(1, 0.80, 0.32, 1)
    end

    local fill = bar:CreateTexture(nil, "BACKGROUND", nil, 1)
    fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 4, -4)
    fill:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -4, 4)
    NS.SetGradient(fill, "VERTICAL", { 0.09, 0.07, 0.04 }, 0.98, { 0.16, 0.13, 0.07 }, 0.98)

    local goldLine = bar:CreateTexture(nil, "OVERLAY")
    goldLine:SetTexture(NS.WHITE)
    goldLine:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    goldLine:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    goldLine:SetHeight(1)
    goldLine:SetVertexColor(0.82, 0.66, 0.22, 0.95)
    return bar
end

function NS.StyleHeaderButton(b, kind)
    if kind == true then
        kind = "red"
    end
    if not b.SetBackdrop then
        NS.StyleButton(b, kind)
        return
    end
    b:SetBackdrop(NS.HEADER_BUTTON_BACKDROP)
    if kind == "red" then
        b:SetBackdropColor(0.82, 0.08, 0.08, 1)
    elseif kind == "dark" then
        b:SetBackdropColor(0.12, 0.11, 0.09, 0.95)
    else
        b:SetBackdropColor(0.20, 0.14, 0.06, 1)
    end
    local edge = NS.BUTTON_BORDER
    b:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4] or 1)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture(NS.WHITE)
    hl:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3)
    hl:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
    hl:SetVertexColor(1, 0.85, 0.4, 0.16)
    hl:SetBlendMode("ADD")
end

-- Button skins: 1px rim with rounded corners, dark inner line, bevelled fill.
local BUTTON_SKINS = {
    bronze = {
        rimTop = { 0.55, 0.42, 0.22 }, rimBottom = { 0.22, 0.15, 0.07 },
        fillTop = { 0.28, 0.20, 0.10 }, fillBottom = { 0.10, 0.07, 0.04 },
        bevelTop = { 0.48, 0.36, 0.16 }, bevelTop2 = { 0.32, 0.23, 0.10 },
        bevelLeftTop = { 0.40, 0.30, 0.14 }, bevelLeftBottom = { 0.16, 0.11, 0.05 },
    },
    grey = {
        rimTop = { 0.55, 0.42, 0.22 }, rimBottom = { 0.22, 0.15, 0.07 },
        fillTop = { 0.28, 0.20, 0.10 }, fillBottom = { 0.10, 0.07, 0.04 },
        bevelTop = { 0.48, 0.36, 0.16 }, bevelTop2 = { 0.32, 0.23, 0.10 },
        bevelLeftTop = { 0.40, 0.30, 0.14 }, bevelLeftBottom = { 0.16, 0.11, 0.05 },
    },
    red = {
        rimTop = { 0.55, 0.45, 0.34 }, rimBottom = { 0.40, 0.30, 0.20 },
        fillTop = { 0.48, 0.03, 0.02 }, fillBottom = { 0.28, 0.02, 0.02 },
        bevelTop = { 0.26, 0, 0 }, bevelTop2 = { 0.40, 0.02, 0 },
        bevelLeftTop = { 0.26, 0, 0 }, bevelLeftBottom = { 0.18, 0, 0 },
        shadowBottom = { 0.16, 0.01, 0 },
    },
}

local function Strip(b, sublevel)
    local t = b:CreateTexture(nil, "BACKGROUND", nil, sublevel)
    t:SetTexture(NS.WHITE)
    return t
end

-- 1px ring inset by `inset`, with each corner cut by `cut` pixels.
local function Ring(b, inset, cut, sublevel, top, bottom)
    local ring = {}
    ring.top = Strip(b, sublevel)
    ring.top:SetPoint("TOPLEFT", inset + cut, -inset)
    ring.top:SetPoint("TOPRIGHT", -(inset + cut), -inset)
    ring.top:SetHeight(1)
    ring.top:SetVertexColor(top[1], top[2], top[3], 1)

    ring.bottom = Strip(b, sublevel)
    ring.bottom:SetPoint("BOTTOMLEFT", inset + cut, inset)
    ring.bottom:SetPoint("BOTTOMRIGHT", -(inset + cut), inset)
    ring.bottom:SetHeight(1)
    ring.bottom:SetVertexColor(bottom[1], bottom[2], bottom[3], 1)

    ring.left = Strip(b, sublevel)
    ring.left:SetPoint("TOPLEFT", inset, -(inset + cut))
    ring.left:SetPoint("BOTTOMLEFT", inset, inset + cut)
    ring.left:SetWidth(1)
    NS.SetGradient(ring.left, "VERTICAL", bottom, 1, top, 1)

    ring.right = Strip(b, sublevel)
    ring.right:SetPoint("TOPRIGHT", -inset, -(inset + cut))
    ring.right:SetPoint("BOTTOMRIGHT", -inset, inset + cut)
    ring.right:SetWidth(1)
    NS.SetGradient(ring.right, "VERTICAL", bottom, 1, top, 1)

    if cut >= 2 then
        local corners = {
            { "TOPLEFT", inset + 1, -(inset + 1), top },
            { "TOPRIGHT", -(inset + 1), -(inset + 1), top },
            { "BOTTOMLEFT", inset + 1, inset + 1, bottom },
            { "BOTTOMRIGHT", -(inset + 1), inset + 1, bottom },
        }
        for _, c in ipairs(corners) do
            local dot = Strip(b, sublevel)
            dot:SetSize(1, 1)
            dot:SetPoint(c[1], c[2], c[3])
            dot:SetVertexColor(c[4][1], c[4][2], c[4][3], 1)
        end
    end
    return ring
end

-- kind: "bronze" (default), "grey" or "red" (true also means red).
function NS.StyleButton(b, kind)
    if kind == true then
        kind = "red"
    end
    local s = BUTTON_SKINS[kind or "bronze"] or BUTTON_SKINS.bronze

    Ring(b, 0, 2, 0, s.rimTop, s.rimBottom)
    Ring(b, 1, 1, 1, { 0.04, 0.035, 0.03 }, { 0.04, 0.035, 0.03 })

    local fill = Strip(b, 2)
    fill:SetPoint("TOPLEFT", 2, -2)
    fill:SetPoint("BOTTOMRIGHT", -2, 2)
    NS.SetGradient(fill, "VERTICAL", s.fillBottom, 1, s.fillTop, 1)

    local bevel = Strip(b, 3)
    bevel:SetPoint("TOPLEFT", 2, -2)
    bevel:SetPoint("TOPRIGHT", -2, -2)
    bevel:SetHeight(1)
    bevel:SetVertexColor(s.bevelTop[1], s.bevelTop[2], s.bevelTop[3], 1)

    local bevel2 = Strip(b, 3)
    bevel2:SetPoint("TOPLEFT", 3, -3)
    bevel2:SetPoint("TOPRIGHT", -2, -3)
    bevel2:SetHeight(1)
    bevel2:SetVertexColor(s.bevelTop2[1], s.bevelTop2[2], s.bevelTop2[3], 1)

    local bevelLeft = Strip(b, 3)
    bevelLeft:SetPoint("TOPLEFT", 2, -3)
    bevelLeft:SetPoint("BOTTOMLEFT", 2, 2)
    bevelLeft:SetWidth(1)
    NS.SetGradient(bevelLeft, "VERTICAL", s.bevelLeftBottom, 1, s.bevelLeftTop, 1)

    if s.shadowBottom then
        local shadow = Strip(b, 3)
        shadow:SetPoint("BOTTOMLEFT", 2, 2)
        shadow:SetPoint("BOTTOMRIGHT", -2, 2)
        shadow:SetHeight(2)
        shadow:SetVertexColor(s.shadowBottom[1], s.shadowBottom[2], s.shadowBottom[3], 1)
    end

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture(NS.WHITE)
    hl:SetPoint("TOPLEFT", 2, -2)
    hl:SetPoint("BOTTOMRIGHT", -2, 2)
    hl:SetVertexColor(1, 0.85, 0.4, 0.14)
    hl:SetBlendMode("ADD")
end

-- Hover feedback comes from the HIGHLIGHT layer; kept so callers don't need to care.
function NS.SetButtonHover()
end

----------------------------------------------------------------------
-- Button glyphs (drawn from plain shapes so they stay crisp and gold)
----------------------------------------------------------------------

local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local GOLD_TOP = { 1, 0.88, 0 }
local GOLD_BOTTOM = { 0.90, 0.60, 0 }

local function ApplyGradient(t, orientation, c1, c2)
    ApplyRawGradient(t, orientation, c1[1], c1[2], c1[3], c1[4] or 1, c2[1], c2[2], c2[3], c2[4] or 1)
end

local function Circle(parent, size, sublevel, bottom, top)
    local t = parent:CreateTexture(nil, "ARTWORK", nil, sublevel)
    t:SetTexture(CIRCLE)
    t:SetSize(size, size)
    t:SetPoint("CENTER", parent, "CENTER", 0, 0)
    ApplyGradient(t, "VERTICAL", bottom, top or bottom)
    return t
end

local function Tooth(parent, w, h, sublevel, angle, radius, color)
    local t = parent:CreateTexture(nil, "ARTWORK", nil, sublevel)
    t:SetTexture(NS.WHITE)
    t:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    t:SetSize(w, h)
    t:SetPoint("CENTER", parent, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
    if t.SetRotation then
        t:SetRotation(angle - math.pi / 2)
    end
    return t
end

-- Gold cog: finer teeth and a clearer center hole, closer to the default UI.
function NS.CreateGearGlyph(button)
    local g = CreateFrame("Frame", nil, button)
    g:SetSize(12, 12)
    g:SetPoint("CENTER", button, "CENTER", 0, 0)
    local shadow = { 0, 0, 0, 0.5 }
    for i = 0, 7 do
        local angle = i * math.pi / 4 + math.pi / 2
        local mix = (math.sin(angle) + 1) / 2
        local toothColor = {
            GOLD_BOTTOM[1] + (GOLD_TOP[1] - GOLD_BOTTOM[1]) * mix,
            GOLD_BOTTOM[2] + (GOLD_TOP[2] - GOLD_BOTTOM[2]) * mix,
            0,
        }
        Tooth(g, 2.4, 1.8, 0, angle, 4.4, shadow)
        Tooth(g, 1.8, 1.3, 2, angle, 4.4, toothColor)
    end
    Circle(g, 8.6, 1, shadow)
    Circle(g, 7.6, 3, GOLD_BOTTOM, GOLD_TOP)
    Circle(g, 4.6, 4, { 0.07, 0.07, 0.07 })
    Circle(g, 2.4, 5, GOLD_BOTTOM, GOLD_TOP)
    return g
end

-- Filled chevron that sits large in the header button, like Damage Done.
-- { left offset, width } per row.
local ARROW_ROWS = {
    { 0, 14 }, { 0, 13 }, { 1, 11 }, { 2, 9 }, { 3, 7 }, { 4, 5 }, { 5, 3 }, { 6, 1 },
}

function NS.CreateArrowGlyph(button, yOffset)
    local g = CreateFrame("Frame", nil, button)
    g:SetSize(14, #ARROW_ROWS + 1)
    g:SetPoint("CENTER", button, "CENTER", 0, yOffset or 0)

    local topEdge = g:CreateTexture(nil, "ARTWORK", nil, 0)
    topEdge:SetTexture(NS.WHITE)
    topEdge:SetVertexColor(0, 0, 0, 0.85)
    topEdge:SetSize(14, 1)
    topEdge:SetPoint("TOPLEFT", g, "TOPLEFT", 0, 0)

    local n = #ARROW_ROWS
    for i, row in ipairs(ARROW_ROWS) do
        local f = (i - 1) / (n - 1)
        local left = { 1, 0.96 - f * 0.22, 0 }
        local right = { 0.98, 0.78 - f * 0.16, 0 }
        local t = g:CreateTexture(nil, "ARTWORK", nil, 1)
        t:SetTexture(NS.WHITE)
        t:SetSize(row[2], 1)
        t:SetPoint("TOPLEFT", g, "TOPLEFT", row[1], -i)
        ApplyGradient(t, "HORIZONTAL", left, right)
    end
    return g
end
