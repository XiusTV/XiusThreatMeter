local addonName, ns = ...
local NS = ns

--[[
    Registers Xius Threat Meter with the settings window owned by XiusCore.
    Uses the XiusCore top sub-tab bar: General, Appearance & Bars, Alerts & Roles.
    This file does not build a window.
]]

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

local Lib = _G.XiusCoreSettingsLib
if not Lib or not Lib.RegisterModule then
    return
end

local SUB_TABS = {
    { id = "general", text = "General", width = 96 },
    { id = "appearance", text = "Appearance & Bars", width = 146 },
    { id = "alerts", text = "Alerts & Roles", width = 124 },
}

local function Snap(v, step, minV, maxV)
    v = tonumber(v) or minV or 0
    if step and step > 0 then
        v = math.floor((v / step) + 0.5) * step
        if step < 1 then
            v = math.floor((v * 100) + 0.5) / 100
        end
    end
    if minV and v < minV then
        v = minV
    elseif maxV and v > maxV then
        v = maxV
    end
    return v
end

local function Apply()
    if NS.ApplySettings then
        NS.ApplySettings()
    end
end

local function RefreshPage()
    local function Go()
        if Lib.ShowPage and Lib.page == "Threat" and Lib.frame and Lib.frame:IsShown() then
            Lib:ShowPage("Threat", true)
        elseif Lib.RefreshPage then
            Lib:RefreshPage()
        end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, Go)
    else
        Go()
    end
end

-- Boolean that defaults to on when the saved value is nil.
local function On(db, key)
    return db[key] ~= false
end

local function Toggle(api, db, key, label, tip)
    api:AddCheckbox(label, function()
        return On(db, key)
    end, function(value)
        db[key] = value and true or false
        Apply()
    end, tip)
end

----------------------------------------------------------------------
-- General
----------------------------------------------------------------------

local function BuildGeneral(api, db)
    api:AddSection("Meter")
    api:AddCheckbox("Enable threat meter", function()
        return not db.hidden
    end, function(value)
        if NS.SetHidden then
            NS.SetHidden(not value)
        else
            db.hidden = not value
            Apply()
        end
    end, "Shows or hides the whole window. The aggro warning can still run while the window is hidden.")
    api:AddDropdown("Track threat on", {
        { value = "target", text = "Target" },
        { value = "focus", text = "Focus" },
    }, function()
        return db.mode == "focus" and "focus" or "target"
    end, function(value)
        if NS.SetMode then
            NS.SetMode(value)
        else
            db.mode = value
        end
        Apply()
    end, "Target also follows your target's target, so a healer targeting the tank still sees the boss.")

    api:AddSection("Visibility")
    api:AddCheckbox("Show while solo", function()
        return On(db, "showSolo")
    end, function(value)
        db.showSolo = value and true or false
        db.onlyInGroup = not db.showSolo
        Apply()
    end, "Shows the window when you are not in a group.")
    Toggle(api, db, "showParty", "Show in a party", "Shows the window while you are in a 5-player party.")
    Toggle(api, db, "showRaid", "Show in a raid", "Shows the window while you are in a raid group.")
    api:AddCheckbox("Hide when out of combat", function()
        return db.hideOutOfCombat and true or false
    end, function(value)
        db.hideOutOfCombat = value and true or false
        Apply()
    end, "Only shows the window while you are in combat.")
    api:AddCheckbox("Only show when there is threat", function()
        return db.onlyWithThreat and true or false
    end, function(value)
        db.onlyWithThreat = value and true or false
        Apply()
    end, "The window appears once someone has threat on the enemy you are tracking, and hides again when nobody does.")

    api:AddSection("Window")
    api:AddCheckbox("Lock window", function()
        return db.locked and true or false
    end, function(value)
        if NS.SetLocked then
            NS.SetLocked(value)
        else
            db.locked = value and true or false
            Apply()
        end
        if value and Lib.NoteFramesLocked then
            Lib:NoteFramesLocked()
        end
    end, "Stops the title bar from dragging and hides the resize grip. Unlock Frames can still move it.")
    api:AddSlider("Window scale", 0.5, 2, 0.05, function()
        return db.scale or 1
    end, function(value)
        db.scale = Snap(value, 0.05, 0.5, 2)
        Apply()
    end)
    api:AddSlider("Width", 170, 600, 1, function()
        return db.width or 250
    end, function(value)
        db.width = Snap(value, 1, 170, 600)
        Apply()
    end)
    api:AddSlider("Height", 80, 800, 1, function()
        return db.height or 190
    end, function(value)
        db.height = Snap(value, 1, 80, 800)
        db.minimized = false
        Apply()
    end)
    api:AddSlider("Background opacity", 0, 1, 0.05, function()
        return db.bgAlpha or 1
    end, function(value)
        db.bgAlpha = Snap(value, 0.05, 0, 1)
        Apply()
    end)

    api:AddButtonGroup({
        {
            text = (NS.IsTestMode and NS.IsTestMode()) and "Stop Test" or "Test Mode",
            width = 115,
            onClick = function()
                if NS.ToggleTestMode then
                    NS.ToggleTestMode()
                end
                RefreshPage()
            end,
        },
        {
            text = "Reset Position",
            width = 115,
            onClick = function()
                if NS.ResetPosition then
                    NS.ResetPosition()
                end
                if Lib.RefreshPage then
                    Lib:RefreshPage()
                end
            end,
        },
    })

    api:AddSection("Ability Threat Estimator")
    Toggle(api, db, "enableAbilityThreatEstimator", "Enable Ability Threat Estimator", "Calculates out-of-combat ability threat from your stats, form/stance, and talents, adds threat info to spell tooltips, and enables the Ability Threat Breakdown window.")
    local function OpenBreakdown()
        if db.enableAbilityThreatEstimator == false then
            NS.Print("Ability Threat Estimator is disabled. Enable it above to open the breakdown window.")
            return
        end
        if NS.OpenAbilityThreatWindow then
            NS.OpenAbilityThreatWindow()
        end
    end
    if api.AddButtonRow then
        api:AddButtonRow("Ability Threat Breakdown", "Open Breakdown", OpenBreakdown, "Opens the out-of-combat spell threat table.")
    else
        api:AddButton("Show Ability Threat Breakdown", OpenBreakdown)
    end
end

----------------------------------------------------------------------
-- Appearance & Bars
----------------------------------------------------------------------

local function BuildAppearance(api, db)
    api:AddSection("Bars")
    api:AddDropdown("Bar texture", {
        { value = "blizzard", text = "Blizzard" },
        { value = "flat", text = "Flat" },
        { value = "raid", text = "Raid" },
    }, function()
        if db.barTexture == "flat" or db.barTexture == "raid" then
            return db.barTexture
        end
        return "blizzard"
    end, function(value)
        db.barTexture = value
        Apply()
    end, "Blizzard matches the default status bar. Flat is a solid fill. Raid uses the raid-frame bar.")
    api:AddSlider("Font size", 8, 18, 1, function()
        return db.fontSize or 11
    end, function(value)
        db.fontSize = Snap(value, 1, 8, 18)
        Apply()
    end)
    api:AddSlider("Bar height", 12, 32, 1, function()
        return db.barHeight or 19
    end, function(value)
        db.barHeight = Snap(value, 1, 12, 32)
        Apply()
    end)
    api:AddSlider("Bar spacing", 0, 8, 1, function()
        return db.barSpacing or 2
    end, function(value)
        db.barSpacing = Snap(value, 1, 0, 8)
        Apply()
    end)

    api:AddSection("Colors & Icons")
    Toggle(api, db, "classColors", "Use class colors", "Colors each bar by class. When off, bars use threat colors: red for the tank, amber near the warning threshold, gold for you, and blue for everyone else.")
    Toggle(api, db, "showIcons", "Show class icons", "Puts a class icon (or pet portrait) at the left of each bar.")

    api:AddSection("Text")
    Toggle(api, db, "showValues", "Show threat numbers", "Shows the raw threat amount next to the percent.")
    Toggle(api, db, "showTPS", "Show threat per second (TPS)", "Shows a smoothed threat-per-second value in brackets. Hidden while the client keeps exact threat secret.")

    api:AddSection("Growth & Sorting")
    api:AddDropdown("Bar growth", {
        { value = "down", text = "Top to bottom" },
        { value = "up", text = "Bottom to top" },
    }, function()
        return db.barGrowth == "up" and "up" or "down"
    end, function(value)
        db.barGrowth = value
        Apply()
    end, "Bottom to top puts the first bar against the bottom edge, which suits a meter docked above action bars.")
    api:AddDropdown("Sort order", {
        { value = "desc", text = "Highest threat first" },
        { value = "asc", text = "Lowest threat first" },
        { value = "tank", text = "Tank first, then highest" },
    }, function()
        if db.sortOrder == "asc" or db.sortOrder == "tank" then
            return db.sortOrder
        end
        return "desc"
    end, function(value)
        db.sortOrder = value
        Apply()
    end, "Tank first pins whoever holds aggro to the top bar.")
end

----------------------------------------------------------------------
-- Alerts & Roles
----------------------------------------------------------------------

local function BuildAlerts(api, db)
    api:AddSection("Role")
    api:AddDropdown("Role mode", {
        { value = "auto", text = "Auto" },
        { value = "tank", text = "Tank" },
        { value = "dps", text = "DPS & Healer" },
    }, function()
        if db.roleMode == "tank" or db.roleMode == "dps" then
            return db.roleMode
        end
        return "auto"
    end, function(value)
        db.roleMode = value
        Apply()
    end, "Auto uses your group role or main-tank assignment. Tank warns when someone else contests or takes aggro. DPS & Healer warns as you approach the tank's threat.")

    api:AddSection("Aggro Warning")
    Toggle(api, db, "warnEnabled", "Warn me before I pull aggro", "Master switch for the aggro warning. When the client hides exact threat numbers, the warning follows the game's own aggro state instead of the threshold.")
    api:AddSlider("Warning threshold (%)", 50, 100, 5, function()
        return db.warnThreshold or 90
    end, function(value)
        db.warnThreshold = Snap(value, 5, 50, 100)
        Apply()
    end, "DPS and healers turn amber 15% below this and red at it.")

    api:AddSection("Visual & Audio Alerts")
    Toggle(api, db, "warnVisual", "Visual alert", "Turns the window title amber, then red, as you near the threshold.")
    Toggle(api, db, "warnSound", "Audio alert", "Plays the raid-warning sound once each time you cross the threshold. Test mode stays silent.")
    api:AddButtonGroup({
        {
            text = "Test Sound",
            width = 115,
            onClick = function()
                if NS.TestWarningSound then
                    NS.TestWarningSound()
                end
            end,
        },
    })

    api:AddSection("Pet Threat")
    Toggle(api, db, "showPets", "Show pet bars", "Gives hunter, warlock, and other pets their own rows.")
    Toggle(api, db, "warnPets", "Include my pet in the warning", "Warns when your own pet nears the tank's threat. Your pet never trips the warning while you are the tank.")
end

----------------------------------------------------------------------
-- Registration
----------------------------------------------------------------------

Lib:RegisterModule({
    id = "Threat",
    title = "Xius Threat Meter",
    menuTitle = "Threat Meter",
    group = "HUD & Combat",
    order = 10,
    hidePageTitle = true,
    activeSubTab = "general",
    subTabs = SUB_TABS,
    slashCommands = { "/xtm", "/xthreat" },
    defaults = NS.DEFAULTS,
    getDB = function()
        return NS.db
    end,
    onResetDefaults = function()
        if NS.ResetAllSettings then
            NS.ResetAllSettings()
        elseif NS.ResetDefaults then
            NS.ResetDefaults()
            Apply()
        end
    end,
    onUnlock = function(unlocked)
        if NS.SetLocked then
            NS.SetLocked(not unlocked)
            return
        end
        if NS.db then
            NS.db.locked = not unlocked
        end
    end,
    onUnlockFrames = function()
        if NS.SetLocked then
            NS.SetLocked(false)
        elseif NS.db then
            NS.db.locked = false
        end
    end,
    buildContent = function(_, api, spec, subTab)
        local db = NS.db
        if not db then
            api:AddNote("The threat meter is still loading. Close this window and open it again.")
            return
        end
        local tab = subTab or (spec and spec.activeSubTab) or "general"
        if tab == "appearance" then
            BuildAppearance(api, db)
        elseif tab == "alerts" then
            BuildAlerts(api, db)
        else
            BuildGeneral(api, db)
        end
    end,
})
