--[[
    Xius Threat Meter - AbilityThreat.lua
    Out-of-combat Ability Threat Estimator, Breakdown Window, and Spell Tooltip integration.
    Strictly avoids combat evaluation and Midnight secret values.
]]

local addonName, ns = ...
local NS = ns

local XiusCore = _G.XiusCore or _G.XiusCoreSettingsLib
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

local floor = math.floor
local max = math.max
local min = math.min
local format = string.format
local sort = table.sort

local remove = table.remove

local abilityList = {}
local abilityByID = {}
local entryPool = {}
local ENTRY_POOL_CAP = 256
local tooltipParts = {}
local displayList = {}
local bestByName = {}
local orderedNames = {}

local snapshot = {
    class = "WARRIOR",
    className = "Warrior",
    stanceName = "Normal",
    multiplier = 1.0,
    holyMultiplier = 1.0,
    savageFuryMult = 1.0,
    ap = 0,
    rap = 0,
    sp = 0,
    avgWepDmg = 0,
}

local ui = {
    frame = nil,
    rows = {},
    sortKey = "hitThreat",
    sortAsc = false,
}

local needsRecalc = false
local recalcPending = false
local recalcDelay = 0
local lastAuraSig = nil
local tooltipHooked = false

local function IsSecret(v)
    if v == nil then
        return false
    end
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, v)
        if not ok or secret then
            return true
        end
    end
    if type(canaccessvalue) == "function" then
        local ok, allowed = pcall(function()
            return canaccessvalue(v) == true
        end)
        if not ok or not allowed then
            return true
        end
    end
    return false
end

-- Cached last known valid non-secret stat snapshot (updated out of combat)
local lastValidFormID = 0
local lastValidAP = 0
local lastValidRAP = 0
local lastValidSP = 0
local lastValidSchoolSP = {}
local lastValidWepDmg = 0

local function GetSafeFormID()
    if GetShapeshiftFormID then
        local ok, formID = pcall(GetShapeshiftFormID)
        if ok and not IsSecret(formID) and type(formID) == "number" then
            lastValidFormID = formID
            return formID
        end
    end
    return lastValidFormID
end

local function GetSafeAttackPower()
    if UnitAttackPower then
        local ok, apBase, apPos, apNeg = pcall(UnitAttackPower, "player")
        if ok and not IsSecret(apBase) and not IsSecret(apPos) and not IsSecret(apNeg) then
            local b = (type(apBase) == "number") and apBase or 0
            local p = (type(apPos) == "number") and apPos or 0
            local n = (type(apNeg) == "number") and apNeg or 0
            local total = max(0, b + p + n)
            lastValidAP = total
            return total
        end
    end
    return lastValidAP
end

local function GetSafeRangedAttackPower()
    if UnitRangedAttackPower then
        local ok, rapBase, rapPos, rapNeg = pcall(UnitRangedAttackPower, "player")
        if ok and not IsSecret(rapBase) and not IsSecret(rapPos) and not IsSecret(rapNeg) then
            local b = (type(rapBase) == "number") and rapBase or 0
            local p = (type(rapPos) == "number") and rapPos or 0
            local n = (type(rapNeg) == "number") and rapNeg or 0
            local total = max(0, b + p + n)
            lastValidRAP = total
            return total
        end
    end
    return lastValidRAP
end

local function GetSafeSpellPower(school)
    if GetSpellBonusDamage then
        local ok, val = pcall(GetSpellBonusDamage, school)
        if ok and not IsSecret(val) and type(val) == "number" then
            local clean = max(0, val)
            lastValidSchoolSP[school] = clean
            return clean
        end
    end
    return lastValidSchoolSP[school] or 0
end

local function GetSafeMaxSpellPower()
    if GetSpellBonusDamage then
        local maxSP = 0
        local sawValid = false
        for school = 2, 7 do
            local ok, val = pcall(GetSpellBonusDamage, school)
            if ok and not IsSecret(val) and type(val) == "number" then
                sawValid = true
                if val > maxSP then
                    maxSP = val
                end
            end
        end
        if sawValid then
            lastValidSP = max(0, maxSP)
            return lastValidSP
        end
    end
    return lastValidSP
end

local function GetSafeWeaponDamage()
    if UnitDamage then
        local ok, minDmg, maxDmg = pcall(UnitDamage, "player")
        if ok and not IsSecret(minDmg) and not IsSecret(maxDmg) then
            local lo = (type(minDmg) == "number") and minDmg or 0
            local hi = (type(maxDmg) == "number") and maxDmg or 0
            local avg = max(0, (lo + hi) / 2)
            lastValidWepDmg = avg
            return avg
        end
    end
    return lastValidWepDmg
end

local function InCombat()
    if InCombatLockdown then
        local okLock, locked = pcall(InCombatLockdown)
        if not okLock or IsSecret(locked) or locked then
            return true
        end
    end
    if UnitAffectingCombat then
        local okState, state = pcall(UnitAffectingCombat, "player")
        if okState and state ~= nil then
            if IsSecret(state) then
                return true
            end
            if state then
                return true
            end
        end
    end
    return false
end

local function IsEstimatorEnabled()
    local db = NS.db
    if not db then
        return true
    end
    return db.enableAbilityThreatEstimator ~= false
end

local function FormatThreatNumber(n)
    n = floor((tonumber(n) or 0) + 0.5)
    if n >= 1000000 then
        return format("%.2fM", n / 1000000)
    elseif n >= 10000 then
        return format("%.1fK", n / 1000)
    end
    return tostring(n)
end

local function FormatMultiplier(mult)
    local pct = (tonumber(mult) or 1) * 100
    if math.abs(pct - floor(pct + 0.5)) < 0.05 then
        return format("%d%%", floor(pct + 0.5))
    end
    return format("%.1f%%", pct)
end

----------------------------------------------------------------------
-- Curated Threat Ability Database (by localized/English spell name)
----------------------------------------------------------------------

local KNOWN_ABILITIES = {
    -- Warrior
    ["Heroic Strike"]     = { school = "physical", threatMod = 1.00, flatThreat = 175, wepMult = 1.0, apCoeff = 0.08, critMult = 2.0 },
    ["Cleave"]            = { school = "physical", threatMod = 1.00, flatThreat = 100, wepMult = 1.0, apCoeff = 0.05, critMult = 2.0 },
    ["Sunder Armor"]      = { school = "physical", threatMod = 1.00, flatThreat = 301, wepMult = 0.0, apCoeff = 0.0,  critMult = 1.0 },
    ["Devastate"]         = { school = "physical", threatMod = 1.00, flatThreat = 301, wepMult = 0.5, apCoeff = 0.05, critMult = 2.0 },
    ["Revenge"]           = { school = "physical", threatMod = 1.00, flatThreat = 315, wepMult = 0.0, apCoeff = 0.15, cd = 5,  critMult = 2.0 },
    ["Shield Slam"]       = { school = "physical", threatMod = 1.00, flatThreat = 307, wepMult = 0.0, apCoeff = 0.25, cd = 6,  critMult = 2.0 },
    ["Shield Bash"]       = { school = "physical", threatMod = 1.00, flatThreat = 180, wepMult = 0.0, apCoeff = 0.05, cd = 12, critMult = 2.0 },
    ["Thunder Clap"]      = { school = "physical", threatMod = 1.75, flatThreat = 0,   wepMult = 0.0, apCoeff = 0.12, cd = 4,  critMult = 2.0 },
    ["Demoralizing Shout"]= { school = "physical", threatMod = 1.00, flatThreat = 56,  wepMult = 0.0, apCoeff = 0.0,  critMult = 1.0 },
    ["Battle Shout"]      = { school = "physical", threatMod = 1.00, flatThreat = 69,  wepMult = 0.0, apCoeff = 0.0,  critMult = 1.0 },
    ["Commanding Shout"]  = { school = "physical", threatMod = 1.00, flatThreat = 68,  wepMult = 0.0, apCoeff = 0.0,  critMult = 1.0 },
    ["Mocking Blow"]      = { school = "physical", threatMod = 1.00, flatThreat = 250, wepMult = 0.5, apCoeff = 0.10, cd = 120,critMult = 2.0 },
    ["Mortal Strike"]     = { school = "physical", threatMod = 1.00, flatThreat = 0,   wepMult = 1.0, apCoeff = 0.15, cd = 6,  critMult = 2.0 },
    ["Bloodthirst"]       = { school = "physical", threatMod = 1.00, flatThreat = 0,   wepMult = 0.0, apCoeff = 0.45, cd = 6,  critMult = 2.0 },
    ["Whirlwind"]         = { school = "physical", threatMod = 1.00, flatThreat = 0,   wepMult = 1.0, apCoeff = 0.0,  cd = 10, critMult = 2.0 },
    ["Execute"]           = { school = "physical", threatMod = 1.00, flatThreat = 0,   wepMult = 0.0, apCoeff = 0.20, critMult = 2.0 },
    ["Overpower"]         = { school = "physical", threatMod = 1.00, flatThreat = 0,   wepMult = 1.0, apCoeff = 0.05, cd = 5,  critMult = 2.0 },
    ["Rend"]              = { school = "physical", threatMod = 1.00, flatThreat = 0,   wepMult = 0.2, apCoeff = 0.10, critMult = 1.0 },
    ["Taunt"]             = { school = "physical", threatMod = 1.00, flatThreat = 0,   cd = 10, taunt = true, critMult = 1.0 },
    ["Challenging Shout"] = { school = "physical", threatMod = 1.00, flatThreat = 0,   cd = 600, taunt = true, critMult = 1.0 },
    ["Shockwave"]         = { school = "physical", threatMod = 1.00, flatThreat = 0,   wepMult = 0.0, apCoeff = 0.75, cd = 20, critMult = 2.0 },
    ["Slam"]              = { school = "physical", threatMod = 1.00, flatThreat = 0,   wepMult = 1.0, apCoeff = 0.10, critMult = 2.0 },

    -- Druid (threatMod 1.00: bear stance 1.30 * Feral Instinct already applies; bonus damage carries the tank edge)
    -- Savage Fury is Cat-only (Claw / Rake / Mangle (Cat) / Ravage) — never stamp it on bear abilities.
    ["Primal Bite"]       = { school = "physical", threatMod = 1.00, flatThreat = 0, flatByRank = { [1] = 42, [2] = 62, [3] = 77, [4] = 96 }, bonusDamage = true, wepMult = 1.0, apCoeff = 0.0, cd = 6, critMult = 2.0 },
    ["Maul"]              = { school = "physical", threatMod = 1.00, flatThreat = 0, bonusByRank = { [1] = 18, [2] = 27, [3] = 37, [4] = 49, [5] = 71, [6] = 101, [7] = 128, [8] = 176 }, bonusDamage = true, wepMult = 1.0, apCoeff = 0.12, critMult = 2.0 },
    ["Swipe"]             = { school = "physical", threatMod = 1.00, flatThreat = 0,   wepMult = 0.0, apCoeff = 0.08, critMult = 2.0 },
    ["Swipe (Bear)"]      = { school = "physical", threatMod = 1.00, flatThreat = 0,   wepMult = 0.0, apCoeff = 0.08, critMult = 2.0 },
    ["Lacerate"]          = { school = "physical", threatMod = 1.00, flatThreat = 285, wepMult = 0.0, apCoeff = 0.05, critMult = 2.0 },
    ["Mangle (Bear)"]     = { school = "physical", threatMod = 1.00, flatThreat = 0,   wepMult = 1.15,apCoeff = 0.10, cd = 6, critMult = 2.0 },
    ["Mangle (Cat)"]      = { school = "physical", threatMod = 1.00, flatThreat = 0,   wepMult = 1.60,apCoeff = 0.10, savageFury = true, critMult = 2.0 },
    ["Mangle"]            = { school = "physical", threatMod = 1.00, flatThreat = 0,   wepMult = 1.15,apCoeff = 0.10, cd = 6, critMult = 2.0, formAware = true },
    ["Faerie Fire (Feral)"]={ school = "nature",   threatMod = 1.00, flatThreat = 127, wepMult = 0.0, apCoeff = 0.0,  cd = 6, critMult = 1.0 },
    ["Faerie Fire"]       = { school = "nature",   threatMod = 1.00, flatThreat = 108, wepMult = 0.0, apCoeff = 0.0,  critMult = 1.0 },
    ["Demoralizing Roar"] = { school = "physical", threatMod = 1.00, flatThreat = 42,  wepMult = 0.0, apCoeff = 0.0,  critMult = 1.0 },
    ["Growl"]             = { school = "physical", threatMod = 1.00, flatThreat = 0,   cd = 10, taunt = true, critMult = 1.0 },
    ["Challenging Roar"]  = { school = "physical", threatMod = 1.00, flatThreat = 0,   cd = 600, taunt = true, critMult = 1.0 },
    ["Bash"]              = { school = "physical", threatMod = 1.00, flatThreat = 120, wepMult = 0.0, apCoeff = 0.0,  cd = 60, critMult = 1.0 },
    ["Claw"]              = { school = "physical", threatMod = 1.00, flatThreat = 0,   wepMult = 1.0, apCoeff = 0.05, savageFury = true, critMult = 2.0 },
    ["Rake"]              = { school = "physical", threatMod = 1.00, flatThreat = 0,   wepMult = 0.0, apCoeff = 0.01, savageFury = true, critMult = 2.0 },
    ["Ravage"]            = { school = "physical", threatMod = 1.00, flatThreat = 0,   wepMult = 3.85,apCoeff = 0.10, savageFury = true, critMult = 2.0 },
    ["Shred"]             = { school = "physical", threatMod = 1.00, flatThreat = 0,   wepMult = 2.25,apCoeff = 0.10, critMult = 2.0 },
    ["Ferocious Bite"]    = { school = "physical", threatMod = 1.00, flatThreat = 0,   wepMult = 0.0, apCoeff = 0.35, critMult = 2.0 },
    ["Cower"]             = { school = "physical", threatMod = 0.00, flatThreat = -800, flatByRank = { [1] = -240, [2] = -403, [3] = -593, [4] = -800, [5] = -1170 }, wepMult = 0.0, apCoeff = 0.0,  cd = 10, critMult = 1.0 },
    ["Moonfire"]          = { school = "arcane",   threatMod = 1.00, flatThreat = 0,   spCoeff = 0.15, critMult = 1.5 },
    ["Wrath"]             = { school = "nature",   threatMod = 1.00, flatThreat = 0,   spCoeff = 0.571,critMult = 1.5 },
    ["Starfire"]          = { school = "arcane",   threatMod = 1.00, flatThreat = 0,   spCoeff = 1.00, critMult = 1.5 },

    -- Paladin
    ["Consecration"]      = { school = "holy",     threatMod = 1.00, flatThreat = 0,   spCoeff = 0.33, apCoeff = 0.16, cd = 8,  critMult = 1.5 },
    ["Holy Shield"]       = { school = "holy",     threatMod = 1.35, flatThreat = 0,   spCoeff = 0.09, cd = 10, critMult = 1.5 },
    ["Avenger's Shield"]  = { school = "holy",     threatMod = 1.00, flatThreat = 0,   spCoeff = 0.25, apCoeff = 0.15, cd = 30, critMult = 1.5 },
    ["Exorcism"]          = { school = "holy",     threatMod = 1.00, flatThreat = 0,   spCoeff = 0.429,cd = 15, critMult = 1.5 },
    ["Holy Wrath"]        = { school = "holy",     threatMod = 1.00, flatThreat = 0,   spCoeff = 0.19, cd = 60, critMult = 1.5 },
    ["Judgement"]         = { school = "holy",     threatMod = 1.00, flatThreat = 0,   spCoeff = 0.25, apCoeff = 0.20, cd = 8,  critMult = 1.5 },
    ["Hammer of Wrath"]   = { school = "holy",     threatMod = 1.00, flatThreat = 0,   spCoeff = 0.429,apCoeff = 0.15, cd = 6,  critMult = 1.5 },
    ["Hammer of the Righteous"] = { school = "holy", threatMod = 1.00, flatThreat = 0, wepMult = 1.0, apCoeff = 0.20, cd = 6,  critMult = 2.0 },
    ["Shield of the Righteous"] = { school = "holy", threatMod = 1.00, flatThreat = 0, apCoeff = 0.35, cd = 6,  critMult = 2.0 },
    ["Crusader Strike"]   = { school = "physical", threatMod = 1.00, flatThreat = 0,   wepMult = 1.1, apCoeff = 0.10, cd = 6,  critMult = 2.0 },
    ["Righteous Defense"] = { school = "holy",     threatMod = 1.00, flatThreat = 0,   cd = 15, taunt = true, critMult = 1.0 },
    ["Hand of Reckoning"] = { school = "holy",     threatMod = 1.00, flatThreat = 0,   cd = 8,  taunt = true, spCoeff = 0.15, critMult = 1.5 },

    -- Rogue
    ["Sinister Strike"]   = { school = "physical", threatMod = 1.00, flatThreat = 0,   wepMult = 1.0, apCoeff = 0.10, critMult = 2.0 },
    ["Backstab"]          = { school = "physical", threatMod = 1.00, flatThreat = 0,   wepMult = 1.5, apCoeff = 0.12, critMult = 2.0 },
    ["Eviscerate"]        = { school = "physical", threatMod = 1.00, flatThreat = 0,   wepMult = 0.0, apCoeff = 0.35, critMult = 2.0 },
    ["Hemorrhage"]        = { school = "physical", threatMod = 1.00, flatThreat = 0,   wepMult = 1.1, apCoeff = 0.05, critMult = 2.0 },
    ["Mutilate"]          = { school = "physical", threatMod = 1.00, flatThreat = 0,   wepMult = 1.2, apCoeff = 0.15, critMult = 2.0 },
    ["Ambush"]            = { school = "physical", threatMod = 1.00, flatThreat = 0,   wepMult = 2.5, apCoeff = 0.15, critMult = 2.0 },
    ["Feint"]             = { school = "physical", threatMod = 0.00, flatThreat = -800,wepMult = 0.0, apCoeff = 0.0,  cd = 10, critMult = 1.0 },

    -- Warlock
    ["Searing Pain"]      = { school = "fire",     threatMod = 2.00, flatThreat = 0,   spCoeff = 0.429, critMult = 1.5 },
    ["Shadow Bolt"]       = { school = "shadow",   threatMod = 1.00, flatThreat = 0,   spCoeff = 0.857, critMult = 1.5 },
    ["Incinerate"]        = { school = "fire",     threatMod = 1.00, flatThreat = 0,   spCoeff = 0.714, critMult = 1.5 },
    ["Immolate"]          = { school = "fire",     threatMod = 1.00, flatThreat = 0,   spCoeff = 0.20,  critMult = 1.5 },
    ["Soul Fire"]         = { school = "fire",     threatMod = 1.00, flatThreat = 0,   spCoeff = 1.15,  critMult = 1.5 },

    -- Priest
    ["Mind Blast"]        = { school = "shadow",   threatMod = 2.00, flatThreat = 0,   spCoeff = 0.429, cd = 8, critMult = 1.5 },
    ["Smite"]             = { school = "holy",     threatMod = 1.00, flatThreat = 0,   spCoeff = 0.714, critMult = 1.5 },
    ["Holy Fire"]         = { school = "holy",     threatMod = 1.00, flatThreat = 0,   spCoeff = 0.571, cd = 10,critMult = 1.5 },
    ["Mind Flay"]         = { school = "shadow",   threatMod = 1.00, flatThreat = 0,   spCoeff = 0.45,  critMult = 1.5 },

    -- Shaman
    ["Earth Shock"]       = { school = "nature",   threatMod = 2.00, flatThreat = 0,   spCoeff = 0.386, cd = 6, critMult = 1.5 },
    ["Frost Shock"]       = { school = "frost",    threatMod = 1.00, flatThreat = 0,   spCoeff = 0.386, cd = 6, critMult = 1.5 },
    ["Flame Shock"]       = { school = "fire",     threatMod = 1.00, flatThreat = 0,   spCoeff = 0.214, cd = 6, critMult = 1.5 },
    ["Lightning Bolt"]    = { school = "nature",   threatMod = 1.00, flatThreat = 0,   spCoeff = 0.714, critMult = 1.5 },
    ["Chain Lightning"]   = { school = "nature",   threatMod = 1.00, flatThreat = 0,   spCoeff = 0.571, cd = 6, critMult = 1.5 },
    ["Stormstrike"]       = { school = "physical", threatMod = 1.00, flatThreat = 0,   wepMult = 1.0, apCoeff = 0.10, cd = 10, critMult = 2.0 },

    -- Mage
    ["Fireball"]          = { school = "fire",     threatMod = 1.00, flatThreat = 0,   spCoeff = 1.00,  critMult = 1.5 },
    ["Frostbolt"]         = { school = "frost",    threatMod = 1.00, flatThreat = 0,   spCoeff = 0.814, critMult = 1.5 },
    ["Arcane Blast"]      = { school = "arcane",   threatMod = 1.00, flatThreat = 0,   spCoeff = 0.714, critMult = 1.5 },
    ["Fire Blast"]        = { school = "fire",     threatMod = 1.00, flatThreat = 0,   spCoeff = 0.429, cd = 8, critMult = 1.5 },
    ["Scorch"]            = { school = "fire",     threatMod = 1.00, flatThreat = 0,   spCoeff = 0.429, critMult = 1.5 },
    ["Pyroblast"]         = { school = "fire",     threatMod = 1.00, flatThreat = 0,   spCoeff = 1.15,  critMult = 1.5 },

    -- Hunter
    ["Aimed Shot"]        = { school = "physical", threatMod = 1.00, flatThreat = 0,   wepMult = 1.0, rapCoeff = 0.20, cd = 6,  critMult = 2.0 },
    ["Arcane Shot"]       = { school = "arcane",   threatMod = 1.00, flatThreat = 0,   rapCoeff = 0.15, cd = 6,  critMult = 2.0 },
    ["Multi-Shot"]        = { school = "physical", threatMod = 1.00, flatThreat = 0,   wepMult = 1.0, rapCoeff = 0.10, cd = 10, critMult = 2.0 },
    ["Steady Shot"]       = { school = "physical", threatMod = 1.00, flatThreat = 0,   wepMult = 1.0, rapCoeff = 0.10, critMult = 2.0 },
    ["Distracting Shot"]  = { school = "physical", threatMod = 1.00, flatThreat = 600, cd = 8, taunt = false, critMult = 1.0 },

    -- Death Knight
    ["Icy Touch"]         = { school = "frost",    threatMod = 7.00, flatThreat = 0,   apCoeff = 0.10,  critMult = 1.5 },
    ["Plague Strike"]     = { school = "physical", threatMod = 1.00, flatThreat = 0,   wepMult = 0.5, apCoeff = 0.10, critMult = 2.0 },
    ["Blood Strike"]      = { school = "physical", threatMod = 1.00, flatThreat = 0,   wepMult = 0.4, apCoeff = 0.10, critMult = 2.0 },
    ["Death Strike"]      = { school = "physical", threatMod = 1.00, flatThreat = 0,   wepMult = 0.75,apCoeff = 0.10, critMult = 2.0 },
    ["Heart Strike"]      = { school = "physical", threatMod = 1.00, flatThreat = 0,   wepMult = 0.5, apCoeff = 0.10, critMult = 2.0 },
    ["Rune Strike"]       = { school = "physical", threatMod = 1.75, flatThreat = 0,   wepMult = 1.5, apCoeff = 0.15, critMult = 2.0 },
    ["Death and Decay"]   = { school = "shadow",   threatMod = 1.90, flatThreat = 0,   apCoeff = 0.06, cd = 30, critMult = 1.5 },
    ["Dark Command"]      = { school = "shadow",   threatMod = 1.00, flatThreat = 0,   cd = 8, taunt = true, critMult = 1.0 },
    ["Death Grip"]        = { school = "shadow",   threatMod = 1.00, flatThreat = 0,   cd = 35, taunt = true, critMult = 1.0 },
}

----------------------------------------------------------------------
-- Talent & Aura Detection (Out of Combat)
----------------------------------------------------------------------

local function GetTalentRankByName(targetName)
    -- Forever uses the classic talent-tab layout under the modern API.
    if not GetNumTalentTabs or not GetTalentInfo then
        return 0
    end
    local okTabs, numTabs = pcall(GetNumTalentTabs)
    if not okTabs or type(numTabs) ~= "number" or numTabs <= 0 then
        return 0
    end
    for t = 1, numTabs do
        local okNum, numTalents = pcall(GetNumTalents, t)
        if okNum and not IsSecret(numTalents) and type(numTalents) == "number" then
            for i = 1, numTalents do
                -- Prefer named returns; some clients put rank at arg 5, others at arg 8.
                local okInfo, name, iconTexture, tier, column, rank, maxRank = pcall(GetTalentInfo, t, i)
                if okInfo and not IsSecret(name) and type(name) == "string" and name == targetName then
                    local r = rank
                    -- Missing/secret ranks default to 0 (untalented), never the talent cap.
                    if IsSecret(r) or type(r) ~= "number" then
                        return 0
                    end
                    return r
                end
            end
        end
    end
    return 0
end

local function HasPlayerAura(spellID, fallbackName)
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID and spellID then
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
        if ok and not IsSecret(aura) and aura then
            return true
        end
    end
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 40 do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok or aura == nil then
                break
            end
            if not IsSecret(aura) then
                local sid = aura.spellId
                local aname = aura.name
                if (spellID and not IsSecret(sid) and sid == spellID)
                    or (fallbackName and not IsSecret(aname) and aname == fallbackName) then
                    return true
                end
            end
        end
    end
    return false
end

local function DetectModifiers()
    local _, playerClass, className = UnitClass("player")
    if IsSecret(playerClass) then
        playerClass = nil
    end
    if IsSecret(className) or not className then
        className = playerClass or "Player"
    end
    snapshot.class = playerClass or "WARRIOR"
    snapshot.className = className

    local formID = GetSafeFormID()
    local stanceName = "Normal"
    local mult = 1.0
    local holyMult = 1.0

    if playerClass == "WARRIOR" then
        local defianceRank = GetTalentRankByName("Defiance")
        if formID == 18 or HasPlayerAura(71, "Defensive Stance") then
            stanceName = "Defensive Stance"
            -- Forever / TBC Defiance: 5% per rank (3 ranks).
            mult = 1.30 * (1 + 0.05 * defianceRank)
        elseif formID == 19 or HasPlayerAura(2458, "Berserker Stance") then
            stanceName = "Berserker Stance"
            mult = 0.80
        elseif formID == 17 or HasPlayerAura(2457, "Battle Stance") then
            stanceName = "Battle Stance"
            -- Battle Stance is 100% threat; Berserker Stance is the 80% stance.
            mult = 1.0
        end
    elseif playerClass == "DRUID" then
        local feralInstinctRank = GetTalentRankByName("Feral Instinct")
        -- Forever / TBC Feral Instinct: 5% per rank (3 ranks) on top of bear 1.30.
        local feralPerRank = 0.05
        if formID == 8 or HasPlayerAura(9634, "Dire Bear Form") then
            stanceName = "Dire Bear Form"
            mult = 1.30 * (1 + feralPerRank * feralInstinctRank)
        elseif formID == 5 or HasPlayerAura(5487, "Bear Form") then
            stanceName = "Bear Form"
            mult = 1.30 * (1 + feralPerRank * feralInstinctRank)
        elseif formID == 1 or HasPlayerAura(768, "Cat Form") then
            stanceName = "Cat Form"
            mult = 0.71
        elseif formID == 31 or HasPlayerAura(24858, "Moonkin Form") then
            stanceName = "Moonkin Form"
        end
    elseif playerClass == "PALADIN" then
        if HasPlayerAura(25780, "Righteous Fury") then
            stanceName = "Righteous Fury"
            local impRF = GetTalentRankByName("Improved Righteous Fury")
            local bonusScale = 1.0
            if impRF == 1 then
                bonusScale = 1.16
            elseif impRF == 2 then
                bonusScale = 1.33
            elseif impRF >= 3 then
                bonusScale = 1.50
            end
            holyMult = 1.0 + (0.60 * bonusScale)
        end
    elseif playerClass == "ROGUE" then
        local subtletyRank = GetTalentRankByName("Subtlety")
        if subtletyRank > 0 then
            mult = mult * (1 - 0.04 * subtletyRank)
        end
    elseif playerClass == "DEATHKNIGHT" then
        if HasPlayerAura(48263, "Frost Presence") then
            stanceName = "Frost Presence"
            mult = 1.45
        elseif HasPlayerAura(48266, "Blood Presence") then
            stanceName = "Blood Presence"
        elseif HasPlayerAura(48265, "Unholy Presence") then
            stanceName = "Unholy Presence"
        end
    end

    -- External group threat reductions (apply once on the shared multiplier).
    if HasPlayerAura(1038, "Blessing of Salvation") or HasPlayerAura(25895, "Greater Blessing of Salvation") then
        mult = mult * 0.70
    end
    if HasPlayerAura(25908, "Tranquil Air Totem") then
        mult = mult * 0.80
    end

    snapshot.stanceName = stanceName
    snapshot.formID = formID
    snapshot.multiplier = mult
    snapshot.holyMultiplier = (playerClass == "PALADIN") and (mult * holyMult) or mult
    snapshot.savageFuryMult = (playerClass == "DRUID") and (1 + 0.10 * GetTalentRankByName("Savage Fury")) or 1.0

    -- Stats snapshot (secret-safe, falls back to last valid non-secret values)
    snapshot.ap = GetSafeAttackPower()
    snapshot.rap = GetSafeRangedAttackPower()
    snapshot.sp = GetSafeMaxSpellPower()
    snapshot.avgWepDmg = GetSafeWeaponDamage()
end

----------------------------------------------------------------------
-- Description Parsing & Ability Threat Calculation
----------------------------------------------------------------------

local function GetSpellTooltipText(spellID)
    for i = #tooltipParts, 1, -1 do
        tooltipParts[i] = nil
    end
    if C_TooltipInfo and C_TooltipInfo.GetSpellByID then
        local ok, data = pcall(C_TooltipInfo.GetSpellByID, spellID)
        if ok and type(data) == "table" and type(data.lines) == "table" then
            for i = 1, #data.lines do
                local line = data.lines[i]
                if type(line) == "table" then
                    if not IsSecret(line.leftText) and type(line.leftText) == "string" and line.leftText ~= "" then
                        tooltipParts[#tooltipParts + 1] = line.leftText
                    end
                    if not IsSecret(line.rightText) and type(line.rightText) == "string" and line.rightText ~= "" then
                        tooltipParts[#tooltipParts + 1] = line.rightText
                    end
                end
            end
        end
    end
    if C_Spell and C_Spell.GetSpellDescription then
        local ok, desc = pcall(C_Spell.GetSpellDescription, spellID)
        if ok and not IsSecret(desc) and type(desc) == "string" and desc ~= "" then
            tooltipParts[#tooltipParts + 1] = desc
        end
    end
    if #tooltipParts == 0 then
        return ""
    end
    return table.concat(tooltipParts, "\n")
end

local function ParseTooltipThreatAndValue(text)
    if type(text) ~= "string" or text == "" then
        return nil, false, nil, false
    end
    -- Strip color codes and commas inside numbers
    local clean = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("(%d),(%d)", "%1%2")
    local lower = clean:lower()

    local isTaunt = lower:find("forces the target to attack you") ~= nil
        or lower:find("taunt") ~= nil

    local detectedThreatMod = nil
    if lower:find("high amount of threat") or lower:find("high threat") or lower:find("generates additional threat") then
        detectedThreatMod = 1.75
    elseif lower:find("lowers threat") or lower:find("reduces threat") then
        detectedThreatMod = 0.5
    end

    local isHeal = false
    if lower:find("heals") or lower:find("restores") then
        if not lower:find("damage") and not lower:find("mana") then
            isHeal = true
        end
    elseif not lower:find("damage") and not lower:find("threat") and not isTaunt then
        return nil, false, detectedThreatMod, isTaunt
    end

    -- Range: "X to Y"
    local a, b = clean:match("(%d+%.?%d*)%s+to%s+(%d+%.?%d*)")
    if a and b then
        return (tonumber(a) + tonumber(b)) / 2, isHeal, detectedThreatMod, isTaunt
    end

    -- Weapon damage + flat bonus: "weapon damage plus X" / "normal damage plus X"
    local bonus = lower:match("damage%s+plus%s+(%d+%.?%d*)")
    if bonus then
        return snapshot.avgWepDmg + tonumber(bonus), isHeal, detectedThreatMod, isTaunt
    end

    -- Single value before damage / health
    local single = lower:match("(%d+%.?%d*)%s+[%a%s]-damage") or lower:match("(%d+%.?%d*)%s+health")
    if single then
        return tonumber(single), isHeal, detectedThreatMod, isTaunt
    end

    return nil, isHeal, detectedThreatMod, isTaunt
end

local function EstimateSpell(spellID, name, icon, rankText, castTimeMS)
    local known = KNOWN_ABILITIES[name]
    -- Form-aware generic "Mangle": cat uses the cat row, bear/other uses bear.
    if known and known.formAware and name == "Mangle" then
        local formID = snapshot.formID or 0
        if formID == 1 then
            known = KNOWN_ABILITIES["Mangle (Cat)"] or known
        else
            known = KNOWN_ABILITIES["Mangle (Bear)"] or known
        end
    end
    local tipText = GetSpellTooltipText(spellID)
    local descVal, isHeal, tipThreatMod, tipTaunt = ParseTooltipThreatAndValue(tipText)

    if not known and not tipTaunt and (not descVal or descVal <= 0) then
        return nil
    end

    local school = (known and known.school) or "physical"
    local threatMod = (known and known.threatMod) or tipThreatMod or (isHeal and 0.5 or 1.0)
    local flatThreat = (known and known.flatThreat) or 0
    local critMult = (known and known.critMult) or (isHeal and 1.5 or 1.5)
    local isTaunt = (known and known.taunt) or tipTaunt
    local rankNum = tonumber(type(rankText) == "string" and rankText:match("(%d+)") or nil)

    if known and known.flatByRank then
        if rankNum and known.flatByRank[rankNum] then
            flatThreat = known.flatByRank[rankNum]
        end
    end

    local bonusDamage = 0
    if known and known.bonusByRank and rankNum and known.bonusByRank[rankNum] then
        bonusDamage = known.bonusByRank[rankNum]
    elseif known and known.bonusDamage and known.flatByRank and rankNum and known.flatByRank[rankNum] then
        -- Ranked bonus damage abilities (e.g. Primal Bite) fold the flat into damage before threatMod.
        bonusDamage = known.flatByRank[rankNum]
        flatThreat = 0
    end

    local baseAmount = descVal or 0
    local fromTooltip = baseAmount > 0
    -- Maul / Primal Bite tooltips list the ranked bonus only ("increases damage by X").
    if known and (known.bonusDamage or known.bonusByRank) and fromTooltip and known.wepMult and known.wepMult > 0 then
        if bonusDamage <= 0 then
            bonusDamage = baseAmount
        end
        baseAmount = snapshot.avgWepDmg * known.wepMult + bonusDamage
        fromTooltip = false
        flatThreat = 0
    elseif known and known.wepMult and known.wepMult > 0 then
        if baseAmount <= 0 then
            baseAmount = snapshot.avgWepDmg * known.wepMult + bonusDamage
        end
    elseif baseAmount <= 0 and known then
        if bonusDamage > 0 then
            baseAmount = baseAmount + bonusDamage
        end
    elseif known and (known.flatByRank or known.bonusByRank) and descVal and descVal > 0 then
        -- Tooltip already includes weapon + ranked bonus damage; do not add flatThreat again.
        if known.bonusDamage or known.bonusByRank then
            flatThreat = 0
        end
    end

    -- AP/SP coeffs apply to formula estimates. Tooltip numbers usually already bake them in.
    if known and not fromTooltip then
        if known.apCoeff and known.apCoeff > 0 then
            baseAmount = baseAmount + snapshot.ap * known.apCoeff
        end
        if known.rapCoeff and known.rapCoeff > 0 then
            baseAmount = baseAmount + snapshot.rap * known.rapCoeff
        end
        if known.spCoeff and known.spCoeff > 0 then
            baseAmount = baseAmount + snapshot.sp * known.spCoeff
        end
    end

    -- Savage Fury multiplies ability damage whether it came from tooltip or formula.
    if known and known.savageFury and snapshot.savageFuryMult and snapshot.savageFuryMult ~= 1 then
        baseAmount = baseAmount * snapshot.savageFuryMult
    end

    local activeMult = snapshot.multiplier
    if school == "holy" and snapshot.class == "PALADIN" then
        activeMult = snapshot.holyMultiplier
    end

    -- Cower / Feint publish the final threat removed; stance mods must not shrink them.
    local flatMult = activeMult
    if flatThreat < 0 then
        flatMult = 1
    end

    local hitThreat = 0
    local critThreat = 0
    if isTaunt then
        hitThreat = 0
        critThreat = 0
    else
        hitThreat = (baseAmount * threatMod * activeMult) + (flatThreat * flatMult)
        critThreat = (baseAmount * critMult * threatMod * activeMult) + (flatThreat * flatMult)
    end

    local castSec = (not IsSecret(castTimeMS) and tonumber(castTimeMS) or 0) / 1000
    local cdMS = 0
    if GetSpellBaseCooldown then
        local okCD, baseCD = pcall(GetSpellBaseCooldown, spellID)
        if okCD and not IsSecret(baseCD) and type(baseCD) == "number" then
            cdMS = baseCD
        end
    end
    local cdSec = cdMS / 1000
    if cdSec <= 0 and known and known.cd then
        cdSec = known.cd
    end
    local cycleSec = max(1.5, castSec, cdSec)
    local tps = (hitThreat ~= 0) and (hitThreat / cycleSec) or 0

    local e = remove(entryPool) or {}
    e.spellID = spellID
    e.name = name
    e.icon = icon
    e.rank = (rankText and rankText ~= "") and rankText or "-"
    e.hitThreat = hitThreat
    e.critThreat = critThreat
    e.tps = tps
    e.cycleSec = cycleSec
    e.cdSec = cdSec
    e.castSec = castSec
    e.multiplier = activeMult
    e.isTaunt = isTaunt and true or false
    return e
end

local function SortEntries(a, b)
    local key = ui.sortKey or "hitThreat"
    local asc = ui.sortAsc
    local av = a[key]
    local bv = b[key]
    if av == bv then
        return (a.name or "") < (b.name or "")
    end
    if type(av) == "string" or type(bv) == "string" then
        av = tostring(av or "")
        bv = tostring(bv or "")
        if asc then
            return av < bv
        end
        return av > bv
    end
    av = tonumber(av) or 0
    bv = tonumber(bv) or 0
    if asc then
        return av < bv
    end
    return av > bv
end

function NS.RecalculateAbilityThreat()
    if InCombat() then
        needsRecalc = true
        return
    end
    needsRecalc = false

    for i = #abilityList, 1, -1 do
        if #entryPool < ENTRY_POOL_CAP then
            entryPool[#entryPool + 1] = abilityList[i]
        end
        abilityList[i] = nil
    end
    for k in pairs(abilityByID) do
        abilityByID[k] = nil
    end

    if not IsEstimatorEnabled() then
        if ui.frame and ui.frame:IsShown() then
            NS.RefreshAbilityThreatWindow()
        end
        return
    end

    DetectModifiers()

    local function AddSpellCandidate(spellID, subName)
        -- Forever forbids secret values as table keys; skip restricted spell IDs entirely.
        if not spellID or IsSecret(spellID) or type(spellID) ~= "number" or abilityByID[spellID] then
            return
        end
        local info
        if C_Spell and C_Spell.GetSpellInfo then
            local okInfo, got = pcall(C_Spell.GetSpellInfo, spellID)
            if okInfo and type(got) == "table" then
                info = got
            end
        end
        if info and not IsSecret(info.name) and type(info.name) == "string" then
            local rankText = subName
            if (not rankText or rankText == "") and C_Spell.GetSpellSubtext then
                local okSub, sub = pcall(C_Spell.GetSpellSubtext, spellID)
                if okSub and not IsSecret(sub) and type(sub) == "string" then
                    rankText = sub
                end
            end
            local castTime = (not IsSecret(info.castTime)) and info.castTime or 0
            local icon = (not IsSecret(info.iconID)) and info.iconID or nil
            local entry = EstimateSpell(spellID, info.name, icon, rankText, castTime)
            if entry then
                abilityByID[spellID] = entry
                abilityList[#abilityList + 1] = entry
            end
        end
    end

    local scanned = false
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo and C_SpellBook.GetSpellBookItemInfo then
        local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
        local spellType = (Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell) or 1
        local numLines = C_SpellBook.GetNumSpellBookSkillLines() or 0
        if numLines > 0 then
            scanned = true
            for line = 1, numLines do
                local lineInfo = C_SpellBook.GetSpellBookSkillLineInfo(line)
                -- offSpecID == 0 means the active book on some clients; `not 0` is false in Lua.
                local offSpecID = lineInfo and lineInfo.offSpecID
                if lineInfo and (offSpecID == nil or offSpecID == 0) then
                    local offset = lineInfo.itemIndexOffset or 0
                    local count = lineInfo.numSpellBookItems or 0
                    for slot = offset + 1, offset + count do
                        local itemInfo = C_SpellBook.GetSpellBookItemInfo(slot, bank)
                        if itemInfo and itemInfo.itemType == spellType and not itemInfo.isPassive and itemInfo.spellID then
                            AddSpellCandidate(itemInfo.spellID, itemInfo.subName)
                        end
                    end
                end
            end
        end
    end

    if not scanned and GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemInfo then
        local numTabs = GetNumSpellTabs() or 0
        for tab = 1, numTabs do
            local _, _, offset, numSpells, _, offSpecID = GetSpellTabInfo(tab)
            if not offSpecID or offSpecID == 0 then
                for slot = (offset or 0) + 1, (offset or 0) + (numSpells or 0) do
                    local skillType, spellID = GetSpellBookItemInfo(slot, "spell")
                    if skillType == "SPELL" and spellID then
                        local passive = IsPassiveSpell and IsPassiveSpell(slot, "spell")
                        if not passive then
                            local _, subName = GetSpellBookItemName(slot, "spell")
                            AddSpellCandidate(spellID, subName)
                        end
                    end
                end
            end
        end
    end

    sort(abilityList, SortEntries)

    if ui.frame and ui.frame:IsShown() then
        NS.RefreshAbilityThreatWindow()
    end
end

----------------------------------------------------------------------
-- Graphical Breakdown Window (XiusThreatAbilityFrame)
----------------------------------------------------------------------

local ROW_HEIGHT = 22
local DEFAULT_W, DEFAULT_H = 540, 360
local MIN_W, MIN_H = 440, 260
local MAX_W, MAX_H = 900, 700

local COL_SPECS = {
    { key = "name",       label = "Ability",         width = 172, align = "LEFT",  x = 6 },
    { key = "rank",       label = "Rank",            width = 58,  align = "LEFT",  x = 182 },
    { key = "hitThreat",  label = "Est. Hit Threat", width = 84,  align = "RIGHT", x = 244 },
    { key = "critThreat", label = "Est. Crit Threat",width = 84,  align = "RIGHT", x = 332 },
    { key = "tps",        label = "Threat / Cast",   width = 84,  align = "RIGHT", x = 420 },
}

local function ParseRankNumber(rankText)
    if type(rankText) ~= "string" then
        return 0
    end
    local num = rankText:match("(%d+)")
    return tonumber(num) or 0
end

local function BuildDisplayList()
    local highestOnly = not NS.db or NS.db.abilityHighestRankOnly ~= false
    local query = (ui.searchQuery or ""):lower():gsub("^%s*(.-)%s*$", "%1")

    for i = #displayList, 1, -1 do
        displayList[i] = nil
    end

    if highestOnly then
        for k in pairs(bestByName) do
            bestByName[k] = nil
        end
        for i = #orderedNames, 1, -1 do
            orderedNames[i] = nil
        end
        for i = 1, #abilityList do
            local entry = abilityList[i]
            local key = entry.name or tostring(entry.spellID)
            local existing = bestByName[key]
            if not existing then
                bestByName[key] = entry
                orderedNames[#orderedNames + 1] = key
            else
                local rNew = ParseRankNumber(entry.rank)
                local rOld = ParseRankNumber(existing.rank)
                if rNew > rOld or (rNew == rOld and (entry.spellID or 0) > (existing.spellID or 0)) then
                    bestByName[key] = entry
                end
            end
        end
        for i = 1, #orderedNames do
            local entry = bestByName[orderedNames[i]]
            if query == "" then
                displayList[#displayList + 1] = entry
            else
                local nameLower = (entry.name or ""):lower()
                local rankLower = (entry.rank or ""):lower()
                if nameLower:find(query, 1, true) or rankLower:find(query, 1, true) then
                    displayList[#displayList + 1] = entry
                end
            end
        end
        sort(displayList, SortEntries)
        return displayList
    end

    if query == "" then
        return abilityList
    end

    for i = 1, #abilityList do
        local entry = abilityList[i]
        local nameLower = (entry.name or ""):lower()
        local rankLower = (entry.rank or ""):lower()
        if nameLower:find(query, 1, true) or rankLower:find(query, 1, true) then
            displayList[#displayList + 1] = entry
        end
    end
    return displayList
end

local function ComputeColumnLayout()
    local f = ui.frame
    local headerW = (ui.headerBar and ui.headerBar:GetWidth()) or 0
    if headerW < 200 then
        local fw = (f and f:GetWidth()) or DEFAULT_W
        headerW = fw - 44
    end
    local rankW = (headerW < 450) and 54 or 62
    local numW = floor(max(74, min(108, headerW * 0.17)))
    local gap = 4
    local padLeft = 6
    local padRight = 6
    local nameW = max(70, headerW - padLeft - padRight - rankW - (numW * 3) - (gap * 4))

    local x1 = padLeft
    local x2 = x1 + nameW + gap
    local x3 = x2 + rankW + gap
    local x4 = x3 + numW + gap
    local x5 = x4 + numW + gap

    COL_SPECS[1].x, COL_SPECS[1].width = x1, nameW
    COL_SPECS[2].x, COL_SPECS[2].width = x2, rankW
    COL_SPECS[3].x, COL_SPECS[3].width = x3, numW
    COL_SPECS[4].x, COL_SPECS[4].width = x4, numW
    COL_SPECS[5].x, COL_SPECS[5].width = x5, numW
end

local function ApplyColumnLayout()
    ComputeColumnLayout()
    if ui.colButtons then
        for i = 1, #ui.colButtons do
            local btn = ui.colButtons[i]
            local spec = COL_SPECS[i]
            btn:ClearAllPoints()
            btn:SetSize(spec.width, 20)
            btn:SetPoint("LEFT", ui.headerBar, "LEFT", spec.x, 0)
        end
    end
    if ui.scroll and ui.scrollChild then
        local sw = ui.scroll:GetWidth() or 0
        if sw > 100 then
            ui.scrollChild:SetWidth(sw)
        end
    end
    for i = 1, #ui.rows do
        local row = ui.rows[i]
        row.nameText:SetWidth(max(40, COL_SPECS[1].width - 24))
        row.rankText:ClearAllPoints()
        row.rankText:SetPoint("LEFT", row, "LEFT", COL_SPECS[2].x, 0)
        row.rankText:SetWidth(COL_SPECS[2].width)
        row.hitText:ClearAllPoints()
        row.hitText:SetPoint("LEFT", row, "LEFT", COL_SPECS[3].x, 0)
        row.hitText:SetWidth(COL_SPECS[3].width)
        row.critText:ClearAllPoints()
        row.critText:SetPoint("LEFT", row, "LEFT", COL_SPECS[4].x, 0)
        row.critText:SetWidth(COL_SPECS[4].width)
        row.tpsText:ClearAllPoints()
        row.tpsText:SetPoint("LEFT", row, "LEFT", COL_SPECS[5].x, 0)
        row.tpsText:SetWidth(COL_SPECS[5].width)
    end
end

local function SaveAbilityWindowPos()
    local f = ui.frame
    if not f or not NS.db then
        return
    end
    local point, _, relativePoint, x, y = f:GetPoint(1)
    NS.db.abilityWindowPoint = { point or "CENTER", relativePoint or "CENTER", floor((x or 0) + 0.5), floor((y or 0) + 0.5) }
    NS.db.abilityWindowWidth = floor((f:GetWidth() or DEFAULT_W) + 0.5)
    NS.db.abilityWindowHeight = floor((f:GetHeight() or DEFAULT_H) + 0.5)
end

local function RestoreAbilityWindowPos()
    local f = ui.frame
    if not f then
        return
    end
    local w = (NS.db and tonumber(NS.db.abilityWindowWidth)) or DEFAULT_W
    local h = (NS.db and tonumber(NS.db.abilityWindowHeight)) or DEFAULT_H
    w = max(MIN_W, min(MAX_W, w))
    h = max(MIN_H, min(MAX_H, h))
    f:SetSize(w, h)
    local p = NS.db and NS.db.abilityWindowPoint
    f:ClearAllPoints()
    if type(p) == "table" and type(p[1]) == "string" then
        f:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    end
end

local function PaintBox(frame, bg, border)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = NS.WHITE,
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false,
            edgeSize = 14,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 0.96)
        frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
    end
end

local function UpdateHeaderArrows()
    if not ui.colButtons then
        return
    end
    for i = 1, #ui.colButtons do
        local btn = ui.colButtons[i]
        local spec = COL_SPECS[i]
        if ui.sortKey == spec.key then
            local arrow = ui.sortAsc and " ^" or " v"
            btn.label:SetText(spec.label .. arrow)
            btn.label:SetTextColor(1, 0.82, 0)
        else
            btn.label:SetText(spec.label)
            btn.label:SetTextColor(0.85, 0.82, 0.74)
        end
    end
end

local function CreateTableRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -(index - 1) * ROW_HEIGHT)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(NS.WHITE)
    if index % 2 == 0 then
        bg:SetVertexColor(0.10, 0.09, 0.08, 0.55)
    else
        bg:SetVertexColor(0.05, 0.05, 0.06, 0.35)
    end
    row.bg = bg

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture(NS.WHITE)
    hl:SetVertexColor(1, 0.82, 0, 0.14)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
    row.nameText:SetWidth(max(40, COL_SPECS[1].width - 24))
    row.nameText:SetJustifyH("LEFT")
    row.nameText:SetWordWrap(false)

    row.rankText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.rankText:SetPoint("LEFT", row, "LEFT", COL_SPECS[2].x, 0)
    row.rankText:SetWidth(COL_SPECS[2].width)
    row.rankText:SetJustifyH("LEFT")
    row.rankText:SetWordWrap(false)
    row.rankText:SetTextColor(0.68, 0.68, 0.72)

    row.hitText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.hitText:SetPoint("LEFT", row, "LEFT", COL_SPECS[3].x, 0)
    row.hitText:SetWidth(COL_SPECS[3].width)
    row.hitText:SetJustifyH("RIGHT")

    row.critText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.critText:SetPoint("LEFT", row, "LEFT", COL_SPECS[4].x, 0)
    row.critText:SetWidth(COL_SPECS[4].width)
    row.critText:SetJustifyH("RIGHT")

    row.tpsText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.tpsText:SetPoint("LEFT", row, "LEFT", COL_SPECS[5].x, 0)
    row.tpsText:SetWidth(COL_SPECS[5].width)
    row.tpsText:SetJustifyH("RIGHT")

    row:SetScript("OnEnter", function(self)
        if not self.spellID or not GameTooltip then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetSpellByID, GameTooltip, self.spellID)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    ui.rows[index] = row
    return row
end

function NS.RefreshAbilityThreatWindow()
    local f = ui.frame
    if not f then
        return
    end
    ApplyColumnLayout()
    UpdateHeaderArrows()

    if ui.highestRankCheck and NS.db then
        ui.highestRankCheck:SetChecked(NS.db.abilityHighestRankOnly ~= false)
    end

    if ui.summaryText then
        local multText = FormatMultiplier(snapshot.multiplier)
        if snapshot.class == "PALADIN" and snapshot.holyMultiplier ~= snapshot.multiplier then
            multText = multText .. " (Holy: " .. FormatMultiplier(snapshot.holyMultiplier) .. ")"
        end
        ui.summaryText:SetText(format(
            "Stance: |cffffd100%s|r  |  Mult: |cffffd100%s|r  |  AP: |cffffffff%d|r  SP: |cffffffff%d|r",
            snapshot.stanceName,
            multText,
            floor(snapshot.ap + 0.5),
            floor(snapshot.sp + 0.5)
        ))
    end

    local child = ui.scrollChild
    if not child then
        return
    end

    local shownList = BuildDisplayList()
    for i = 1, #shownList do
        local entry = shownList[i]
        local row = ui.rows[i] or CreateTableRow(child, i)
        row.spellID = entry.spellID
        row.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.nameText:SetText(entry.name or "")
        row.rankText:SetText(entry.rank or "-")
        if entry.isTaunt then
            row.hitText:SetText("|cffff8c42Taunt|r")
            row.critText:SetText("-")
            row.tpsText:SetText(entry.cdSec > 0 and format("%ds CD", floor(entry.cdSec + 0.5)) or "-")
        else
            row.hitText:SetText(FormatThreatNumber(entry.hitThreat))
            row.critText:SetText(FormatThreatNumber(entry.critThreat))
            row.tpsText:SetText(FormatThreatNumber(entry.tps) .. "/s")
        end
        row:Show()
    end
    for i = #shownList + 1, #ui.rows do
        ui.rows[i]:Hide()
    end
    local scrollH = (ui.scroll and ui.scroll:GetHeight()) or 180
    child:SetHeight(max(scrollH, #shownList * ROW_HEIGHT + 4))
end

local function CreateAbilityWindow()
    if ui.frame then
        return ui.frame
    end
    local f = CreateFrame("Frame", "XiusThreatAbilityFrame", UIParent, NS.BACKDROP_TEMPLATE)
    f:SetSize(DEFAULT_W, DEFAULT_H)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:SetResizable(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
    elseif f.SetMinResize then
        f:SetMinResize(MIN_W, MIN_H)
        f:SetMaxResize(MAX_W, MAX_H)
    end
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    PaintBox(f, { 0.06, 0.06, 0.08, 0.96 }, NS.HUD_BORDER)

    f:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveAbilityWindowPos()
    end)
    f:SetScript("OnSizeChanged", function()
        if ui.frame then
            ApplyColumnLayout()
            if ui.scroll and ui.scrollChild then
                local childH = ui.scrollChild:GetHeight() or 0
                local scrollH = ui.scroll:GetHeight() or 180
                if childH < scrollH then
                    ui.scrollChild:SetHeight(scrollH)
                end
            end
        end
    end)
    f:SetScript("OnShow", function()
        if NS.db then
            NS.db.abilityWindowShown = true
        end
        if not InCombat() then
            NS.RecalculateAbilityThreat()
        else
            NS.RefreshAbilityThreatWindow()
        end
    end)
    f:SetScript("OnHide", function()
        if NS.db then
            NS.db.abilityWindowShown = false
        end
    end)

    if UISpecialFrames then
        local listed = false
        for i = 1, #UISpecialFrames do
            if UISpecialFrames[i] == "XiusThreatAbilityFrame" then
                listed = true
                break
            end
        end
        if not listed then
            table.insert(UISpecialFrames, "XiusThreatAbilityFrame")
        end
    end

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -12)
    title:SetText("Ability Threat Breakdown")
    title:SetTextColor(1, 0.82, 0)

    -- Out-of-Combat Estimate Badge
    local badge = CreateFrame("Frame", nil, f, NS.BACKDROP_TEMPLATE)
    badge:SetSize(136, 18)
    badge:SetPoint("LEFT", title, "RIGHT", 8, 0)
    PaintBox(badge, { 0.16, 0.12, 0.05, 0.95 }, { 0.65, 0.50, 0.18, 0.9 })
    local badgeText = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    badgeText:SetPoint("CENTER", badge, "CENTER", 0, 0)
    badgeText:SetText("Out-of-Combat Estimate")
    badgeText:SetTextColor(1, 0.85, 0.35)

    -- Close Button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)

    -- Refresh Button
    local refreshBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    refreshBtn:SetSize(68, 20)
    refreshBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function()
        if InCombat() then
            NS.Print("Ability threat estimation is disabled during combat.")
            return
        end
        NS.RecalculateAbilityThreat()
    end)

    -- Stance/Modifier Summary Header
    local summary = CreateFrame("Frame", nil, f, NS.BACKDROP_TEMPLATE)
    summary:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -36)
    summary:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -36)
    summary:SetHeight(26)
    PaintBox(summary, { 0.04, 0.04, 0.05, 0.9 }, { 0.35, 0.28, 0.14, 0.7 })

    local summaryText = summary:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summaryText:SetPoint("LEFT", summary, "LEFT", 10, 0)
    summaryText:SetPoint("RIGHT", summary, "RIGHT", -10, 0)
    summaryText:SetJustifyH("LEFT")
    summaryText:SetWordWrap(false)
    ui.summaryText = summaryText

    -- Filter Bar (SearchBox + Highest Rank Only)
    local filterBar = CreateFrame("Frame", nil, f)
    filterBar:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -6)
    filterBar:SetPoint("TOPRIGHT", summary, "BOTTOMRIGHT", 0, -6)
    filterBar:SetHeight(22)

    local searchBox
    local searchOk = pcall(function()
        searchBox = CreateFrame("EditBox", "XiusThreatAbilitySearch", filterBar, "SearchBoxTemplate")
    end)
    if not searchOk or not searchBox then
        searchBox = CreateFrame("EditBox", "XiusThreatAbilitySearch", filterBar, "InputBoxTemplate")
    end
    searchBox:SetSize(200, 20)
    searchBox:ClearAllPoints()
    searchBox:SetPoint("LEFT", filterBar, "LEFT", 4, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(40)
    if searchBox.Instructions then
        searchBox.Instructions:SetText("Filter ability...")
        searchBox.Instructions:Show()
    end
    local function OnSearchChanged(self)
        ui.searchQuery = self:GetText() or ""
        NS.RefreshAbilityThreatWindow()
    end
    if searchBox.HookScript then
        searchBox:HookScript("OnTextChanged", OnSearchChanged)
    else
        searchBox:SetScript("OnTextChanged", OnSearchChanged)
    end
    searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    ui.searchBox = searchBox

    local rankLabel = filterBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rankLabel:SetPoint("RIGHT", filterBar, "RIGHT", -4, 0)
    rankLabel:SetText("Highest Rank Only")
    rankLabel:SetTextColor(0.90, 0.88, 0.82)

    local rankCheck
    local checkTemplates = { "SettingsCheckboxTemplate", "UICheckButtonTemplate" }
    for i = 1, #checkTemplates do
        local created
        local ok = pcall(function()
            created = CreateFrame("CheckButton", nil, filterBar, checkTemplates[i])
        end)
        if ok and created then
            rankCheck = created
            break
        end
    end
    if not rankCheck then
        rankCheck = CreateFrame("CheckButton", nil, filterBar)
        rankCheck:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
        rankCheck:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
        rankCheck:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
        rankCheck:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    end
    rankCheck:SetSize(20, 20)
    rankCheck:SetPoint("RIGHT", rankLabel, "LEFT", -4, 0)
    if rankCheck.Text then
        rankCheck.Text:Hide()
    end
    rankCheck:SetChecked(not NS.db or NS.db.abilityHighestRankOnly ~= false)
    rankCheck:SetScript("OnClick", function(self)
        if NS.db then
            NS.db.abilityHighestRankOnly = self:GetChecked() and true or false
        end
        NS.RefreshAbilityThreatWindow()
    end)
    ui.highestRankCheck = rankCheck

    -- Column Headers
    local headerBar = CreateFrame("Frame", nil, f)
    headerBar:SetPoint("TOPLEFT", filterBar, "BOTTOMLEFT", 0, -6)
    headerBar:SetPoint("TOPRIGHT", filterBar, "BOTTOMRIGHT", -20, -6)
    headerBar:SetHeight(20)
    ui.headerBar = headerBar

    local headerBg = headerBar:CreateTexture(nil, "BACKGROUND")
    headerBg:SetAllPoints()
    headerBg:SetTexture(NS.WHITE)
    headerBg:SetVertexColor(0.14, 0.11, 0.06, 0.85)

    ui.colButtons = {}
    for i = 1, #COL_SPECS do
        local spec = COL_SPECS[i]
        local btn = CreateFrame("Button", nil, headerBar)
        btn:SetSize(spec.width, 20)
        btn:SetPoint("LEFT", headerBar, "LEFT", spec.x, 0)
        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetAllPoints()
        lbl:SetJustifyH(spec.align)
        lbl:SetWordWrap(false)
        lbl:SetText(spec.label)
        btn.label = lbl
        btn:SetScript("OnClick", function()
            if ui.sortKey == spec.key then
                ui.sortAsc = not ui.sortAsc
            else
                ui.sortKey = spec.key
                ui.sortAsc = (spec.key == "name" or spec.key == "rank")
            end
            sort(abilityList, SortEntries)
            NS.RefreshAbilityThreatWindow()
        end)
        ui.colButtons[i] = btn
    end

    -- Scroll Frame
    local scroll = CreateFrame("ScrollFrame", "XiusThreatAbilityScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", headerBar, "BOTTOMLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 18)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(DEFAULT_W - 44, 220)
    scroll:SetScrollChild(child)
    ui.scroll = scroll
    ui.scrollChild = child

    -- Bottom-right Resize Grip
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
    grip:SetFrameLevel(f:GetFrameLevel() + 20)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetAlpha(0.75)
    grip:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            f:StartSizing("BOTTOMRIGHT")
        end
    end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        SaveAbilityWindowPos()
        ApplyColumnLayout()
        NS.RefreshAbilityThreatWindow()
    end)

    ui.frame = f
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(100)
    RestoreAbilityWindowPos()
    ApplyColumnLayout()

    f:Hide()
    return f
end

function NS.OpenAbilityThreatWindow()
    if not IsEstimatorEnabled() then
        NS.Print("Ability Threat Estimator is disabled in Threat Meter settings.")
        return
    end
    local f = CreateAbilityWindow()
    RestoreAbilityWindowPos()
    f:Show()
    f:Raise()
end

function NS.HideAbilityThreatWindow()
    if ui.frame and ui.frame:IsShown() then
        ui.frame:Hide()
    end
end

function NS.ToggleAbilityThreatWindow()
    if ui.frame and ui.frame:IsShown() then
        NS.HideAbilityThreatWindow()
    else
        NS.OpenAbilityThreatWindow()
    end
end

function NS.ApplyAbilityThreatSettings()
    if not IsEstimatorEnabled() then
        NS.HideAbilityThreatWindow()
    elseif not InCombat() then
        NS.RecalculateAbilityThreat()
    end
end

----------------------------------------------------------------------
-- Spell Tooltip Integration
----------------------------------------------------------------------

local function OnSpellTooltip(tooltip, data)
    if not tooltip or not data or not data.id or IsSecret(data.id) then
        return
    end
    if InCombat() or not IsEstimatorEnabled() then
        return
    end
    local entry = abilityByID[data.id]
    if not entry then
        return
    end
    local multText = FormatMultiplier(entry.multiplier)
    if entry.isTaunt then
        tooltip:AddLine(format("Est. Threat: Taunt [%s]", multText), 1, 0.82, 0)
    else
        tooltip:AddLine(format(
            "Est. Threat: %s (Crit: %s) [%s]",
            FormatThreatNumber(entry.hitThreat),
            FormatThreatNumber(entry.critThreat),
            multText
        ), 1, 0.82, 0)
    end
end

local function HookTooltips()
    if tooltipHooked then
        return
    end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Spell then
        pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Spell, OnSpellTooltip)
        tooltipHooked = true
    elseif GameTooltip and GameTooltip.HookScript and GameTooltip.GetSpell then
        pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetSpell", function(self)
            if InCombat() or not IsEstimatorEnabled() then
                return
            end
            local _, spellID = self:GetSpell()
            if spellID then
                OnSpellTooltip(self, { id = spellID })
            end
        end)
        tooltipHooked = true
    end
end

----------------------------------------------------------------------
-- Events & Initialization
----------------------------------------------------------------------

local watcher = CreateFrame("Frame")
local RECALC_EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "PLAYER_EQUIPMENT_CHANGED",
    "UPDATE_SHAPESHIFT_FORM",
    "ACTIVE_TALENT_GROUP_CHANGED",
    "CHARACTER_POINTS_CHANGED",
    "PLAYER_TALENT_UPDATE",
    "TRAIT_CONFIG_UPDATED",
    "SPELLS_CHANGED",
    "PLAYER_REGEN_ENABLED",
}

local function QuickAuraSignature()
    local formID = GetSafeFormID()
    local ap = GetSafeAttackPower()
    local sp = GetSafeSpellPower(2)
    if IsSecret(formID) or IsSecret(ap) or IsSecret(sp) then
        return lastAuraSig or 0
    end
    formID = (type(formID) == "number") and formID or 0
    ap = (type(ap) == "number") and ap or 0
    sp = (type(sp) == "number") and sp or 0
    local flags = (HasPlayerAura(25780, "Righteous Fury") and 1 or 0)
        + ((HasPlayerAura(1038, "Blessing of Salvation") or HasPlayerAura(25895, "Greater Blessing of Salvation")) and 2 or 0)
        + (HasPlayerAura(25908, "Tranquil Air Totem") and 4 or 0)
        + (HasPlayerAura(48263, "Frost Presence") and 8 or 0)
    return formID * 10000000 + flags * 100000 + ap * 10 + sp
end

local function OnWatcherUpdate(self, elapsed)
    recalcDelay = recalcDelay - elapsed
    if recalcDelay > 0 then
        return
    end
    recalcPending = false
    self:SetScript("OnUpdate", nil)
    if InCombat() then
        needsRecalc = true
        return
    end
    lastAuraSig = QuickAuraSignature()
    NS.RecalculateAbilityThreat()
end

local function RequestRecalc(delay)
    if InCombat() then
        needsRecalc = true
        return
    end
    if not IsEstimatorEnabled() then
        return
    end
    recalcDelay = delay or 0.15
    if not recalcPending then
        recalcPending = true
        watcher:SetScript("OnUpdate", OnWatcherUpdate)
    end
end

watcher:SetScript("OnEvent", function(_, event, arg1)
    if event == "UNIT_AURA" then
        if IsSecret(arg1) or arg1 ~= "player" then
            return
        end
        if InCombat() then
            needsRecalc = true
            return
        end
        if not IsEstimatorEnabled() then
            return
        end
        local sig = QuickAuraSignature()
        if sig == lastAuraSig then
            return
        end
        lastAuraSig = sig
        RequestRecalc(0.15)
        return
    end
    if InCombat() then
        needsRecalc = true
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        if not needsRecalc then
            return
        end
        needsRecalc = false
    end
    RequestRecalc(0.10)
end)

function NS.InitAbilityThreat()
    HookTooltips()
    for i = 1, #RECALC_EVENTS do
        pcall(watcher.RegisterEvent, watcher, RECALC_EVENTS[i])
    end
    if watcher.RegisterUnitEvent then
        pcall(watcher.RegisterUnitEvent, watcher, "UNIT_AURA", "player")
    end
    if not InCombat() then
        lastAuraSig = QuickAuraSignature()
        NS.RecalculateAbilityThreat()
    else
        needsRecalc = true
    end
    if NS.db and NS.db.abilityWindowShown and IsEstimatorEnabled() then
        NS.OpenAbilityThreatWindow()
    end
end
