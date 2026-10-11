--[[
    Xius Threat Meter - Config.lua
    Saved settings, colors and shared styling helpers.
]]

local ADDON, NS = ...

NS.VERSION = "1.5.0"
NS.STYLE_VERSION = 6
NS.FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
NS.WHITE = "Interface\\Buttons\\WHITE8X8"

NS.COLOR = {
    gold = { 1, 0.847, 0, 1 },
    goldLine = { 0.72, 0.57, 0, 1 },
    goldLineDim = { 0.34, 0.27, 0.01, 1 },
    glow = { 0.25, 0.15, 0.045 },
    window = { 0, 0, 0 },
    buttonEdge = { 0.56, 0.42, 0.24, 1 },
    dash = { 0.88, 0.66, 0, 1 },
    rowEdge = { 0.23, 0.20, 0.196, 1 },
    menuBg = { 0.03, 0.03, 0.03, 0.96 },
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
    bgAlpha = 0.45,
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
}

NS.BACKDROP_MENU = {
    bgFile = NS.WHITE,
    edgeFile = NS.WHITE,
    tile = false,
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

NS.BACKDROP_SLIDER = {
    bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
    edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
    tile = true,
    tileSize = 8,
    edgeSize = 8,
    insets = { left = 3, right = 3, top = 6, bottom = 6 },
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

function NS.InitDB()
    if type(XiusThreatMeterDB) ~= "table" then
        XiusThreatMeterDB = {}
    end
    local db = XiusThreatMeterDB
    for k, v in pairs(NS.DEFAULTS) do
        if db[k] == nil then
            db[k] = CopyValue(v)
        end
    end
    if db.styleVersion ~= NS.STYLE_VERSION then
        db.bgAlpha = NS.DEFAULTS.bgAlpha
        db.barHeight = NS.DEFAULTS.barHeight
        db.onlyWithThreat = NS.DEFAULTS.onlyWithThreat
        db.hidden = false
        db.styleVersion = NS.STYLE_VERSION
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
function NS.SetGradient(tex, orientation, c1, a1, c2, a2)
    tex:SetTexture(NS.WHITE)
    tex:SetVertexColor(1, 1, 1, 1)
    if CreateColor and tex.SetGradient then
        local ok = pcall(tex.SetGradient, tex, orientation,
            CreateColor(c1[1], c1[2], c1[3], a1), CreateColor(c2[1], c2[2], c2[3], a2))
        if ok then
            return
        end
    end
    if tex.SetGradientAlpha then
        tex:SetGradientAlpha(orientation, c1[1], c1[2], c1[3], a1, c2[1], c2[2], c2[3], a2)
    else
        tex:SetVertexColor(c2[1], c2[2], c2[3], a2)
    end
end

function NS.CreateWindowBackground(frame)
    frame.bgTex = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    frame.bgTex:SetAllPoints()
end

function NS.SetWindowAlpha(frame, alpha)
    local c = NS.COLOR.window
    frame.bgTex:SetTexture(NS.WHITE)
    frame.bgTex:SetVertexColor(c[1], c[2], c[3], alpha)
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

-- Builds the gold-accented title bar used by the meter and the settings window.
function NS.CreateTitleBar(frame, height)
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    bar:SetHeight(height)

    local C = NS.COLOR

    -- Warm glow that rises from the bottom edge and is gone by the top.
    local glowHeight = math.floor(height * 0.42)
    bar.glow = NS.CreateFadedStrip(bar, "BACKGROUND", 1, 34)
    NS.AnchorFadedStrip(bar.glow, bar, -(height - 1 - glowHeight), glowHeight)
    NS.SetGradient(bar.glow.mid, "VERTICAL", C.glow, 0.95, C.glow, 0)
    NS.SetGradient(bar.glow.left, "HORIZONTAL", C.glow, 0, C.glow, 0.4)
    NS.SetGradient(bar.glow.right, "HORIZONTAL", C.glow, 0.4, C.glow, 0)

    bar.topLine = NS.CreateFadedStrip(bar, "BORDER", 1, 40)
    NS.AnchorFadedStrip(bar.topLine, bar, -3, 1)
    NS.ColorFadedStrip(bar.topLine, C.goldLineDim, 1)

    bar.bottomLine = NS.CreateFadedStrip(bar, "BORDER", 1, 40)
    NS.AnchorFadedStrip(bar.bottomLine, bar, -(height - 1), 1)
    NS.ColorFadedStrip(bar.bottomLine, C.goldLine, 1)

    return bar
end

-- Button skins: 1px rim with rounded corners, dark inner line, bevelled fill.
local BUTTON_SKINS = {
    bronze = {
        rimTop = { 0.60, 0.47, 0.30 }, rimBottom = { 0.30, 0.20, 0.09 },
        fillTop = { 0.23, 0.23, 0.23 }, fillBottom = { 0.075, 0.075, 0.075 },
        bevelTop = { 0.39, 0.39, 0.39 }, bevelTop2 = { 0.33, 0.33, 0.33 },
        bevelLeftTop = { 0.41, 0.41, 0.41 }, bevelLeftBottom = { 0.29, 0.29, 0.29 },
    },
    grey = {
        rimTop = { 0.55, 0.55, 0.55 }, rimBottom = { 0.29, 0.29, 0.29 },
        fillTop = { 0.23, 0.23, 0.23 }, fillBottom = { 0.075, 0.075, 0.075 },
        bevelTop = { 0.38, 0.38, 0.38 }, bevelTop2 = { 0.24, 0.24, 0.24 },
        bevelLeftTop = { 0.29, 0.29, 0.29 }, bevelLeftBottom = { 0.18, 0.18, 0.18 },
    },
    red = {
        rimTop = { 0.59, 0.49, 0.39 }, rimBottom = { 0.48, 0.38, 0.28 },
        fillTop = { 0.60, 0.02, 0.01 }, fillBottom = { 0.42, 0.03, 0.02 },
        bevelTop = { 0.30, 0, 0 }, bevelTop2 = { 0.52, 0.01, 0 },
        bevelLeftTop = { 0.30, 0, 0 }, bevelLeftBottom = { 0.25, 0, 0 },
        shadowBottom = { 0.22, 0.01, 0 },
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
    if CreateColor and t.SetGradient then
        local ok = pcall(t.SetGradient, t, orientation,
            CreateColor(c1[1], c1[2], c1[3], c1[4] or 1), CreateColor(c2[1], c2[2], c2[3], c2[4] or 1))
        if ok then
            return
        end
    end
    if t.SetGradientAlpha then
        t:SetGradientAlpha(orientation, c1[1], c1[2], c1[3], c1[4] or 1, c2[1], c2[2], c2[3], c2[4] or 1)
    else
        t:SetVertexColor(c2[1], c2[2], c2[3], c2[4] or 1)
    end
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

-- Gold cog: 8 short teeth, gold ring, dark gap, gold center dot.
function NS.CreateGearGlyph(button)
    local g = CreateFrame("Frame", nil, button)
    g:SetSize(15, 15)
    g:SetPoint("CENTER", button, "CENTER", 0, 0)
    local shadow = { 0, 0, 0, 0.55 }
    for i = 0, 7 do
        local angle = i * math.pi / 4 + math.pi / 2
        local mix = (math.sin(angle) + 1) / 2
        local toothColor = {
            GOLD_BOTTOM[1] + (GOLD_TOP[1] - GOLD_BOTTOM[1]) * mix,
            GOLD_BOTTOM[2] + (GOLD_TOP[2] - GOLD_BOTTOM[2]) * mix,
            0,
        }
        Tooth(g, 4.2, 3.4, 0, angle, 6, shadow)
        Tooth(g, 3.2, 2.4, 2, angle, 6, toothColor)
    end
    Circle(g, 12, 1, shadow)
    Circle(g, 11, 3, GOLD_BOTTOM, GOLD_TOP)
    Circle(g, 7, 4, { 0.12, 0.12, 0.12 })
    Circle(g, 4.5, 5, GOLD_BOTTOM, GOLD_TOP)
    return g
end

-- Wide flat down-pointing triangle: yellow at the top fading to orange-gold,
-- with a black line along its top edge. { left offset, width } per row.
local ARROW_ROWS = {
    { 0, 12 }, { 0, 11 }, { 1, 9 }, { 2, 7 }, { 3, 6 }, { 3, 5 }, { 4, 3 }, { 5, 1 },
}

function NS.CreateArrowGlyph(button, yOffset)
    local g = CreateFrame("Frame", nil, button)
    g:SetSize(12, #ARROW_ROWS + 1)
    g:SetPoint("CENTER", button, "CENTER", 0, yOffset or 0)

    local topEdge = g:CreateTexture(nil, "ARTWORK", nil, 0)
    topEdge:SetTexture(NS.WHITE)
    topEdge:SetVertexColor(0, 0, 0, 0.9)
    topEdge:SetSize(12, 1)
    topEdge:SetPoint("TOPLEFT", g, "TOPLEFT", 0, 0)

    local n = #ARROW_ROWS
    for i, row in ipairs(ARROW_ROWS) do
        local f = (i - 1) / (n - 1)
        local left = { 1, 0.99 - f * 0.25, 0 }
        local right = { 0.99, 0.80 - f * 0.18, 0 }
        local t = g:CreateTexture(nil, "ARTWORK", nil, 1)
        t:SetTexture(NS.WHITE)
        t:SetSize(row[2], 1)
        t:SetPoint("TOPLEFT", g, "TOPLEFT", row[1], -i)
        ApplyGradient(t, "HORIZONTAL", left, right)
    end
    return g
end
