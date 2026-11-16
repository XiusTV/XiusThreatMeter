--[[
    Registers Xius Threat Meter with the settings window owned by XiusCore.
    This file does not build a window.
]]

local _, NS = ...

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

local Lib = _G.XiusCoreSettingsLib or _G.XiusUISettingsLib
if not Lib or not Lib.RegisterModule then
    return
end

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

local function RefreshPage()
    local function Go()
        if Lib.ShowPage then
            Lib:ShowPage("Threat")
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

Lib:RegisterModule({
    id = "Threat",
    title = "Xius Threat Meter",
    menuTitle = "Threat Meter",
    group = "HUD & Combat",
    order = 10,
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
            if NS.ApplySettings then
                NS.ApplySettings()
            end
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
    buildContent = function(_, api)
        local db = NS.db
        if not db then
            api:AddSection("Threat Meter")
            return
        end
        local function Apply()
            if NS.ApplySettings then
                NS.ApplySettings()
            end
        end

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
        end, "Stops the window from being moved or resized.")
        api:AddCheckbox("Only show when there is threat", function()
            return db.onlyWithThreat and true or false
        end, function(value)
            db.onlyWithThreat = value and true or false
            Apply()
        end, "The window pops up when the enemy you are tracking has threat on your group, and hides again when there is none. Targeting your tank still tracks that tank's target.")
        api:AddCheckbox("Hide when out of combat", function()
            return db.hideOutOfCombat and true or false
        end, function(value)
            db.hideOutOfCombat = value and true or false
            Apply()
        end, "Only show the window while you are in combat.")
        api:AddCheckbox("Only show in a group", function()
            return db.onlyInGroup and true or false
        end, function(value)
            db.onlyInGroup = value and true or false
            Apply()
        end, "Hide the window while you are playing solo.")
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
        end, "Target tracks threat on your target. Focus tracks threat on your focus.")
        api:AddSlider("Window scale", 0.5, 2, 0.05, function()
            return db.scale or 1
        end, function(value)
            db.scale = Snap(value, 0.05, 0.5, 2)
            Apply()
        end)
        api:AddSlider("Background opacity", 0, 1, 0.05, function()
            return db.bgAlpha or 1
        end, function(value)
            db.bgAlpha = Snap(value, 0.05, 0, 1)
            Apply()
        end)

        api:AddSection("Bars")
        api:AddCheckbox("Show class icons", function()
            return db.showIcons and true or false
        end, function(value)
            db.showIcons = value and true or false
            Apply()
        end)
        api:AddCheckbox("Show pets", function()
            return db.showPets and true or false
        end, function(value)
            db.showPets = value and true or false
            Apply()
        end, "Include hunter and warlock pets in the list.")
        api:AddCheckbox("Show threat numbers", function()
            return db.showValues and true or false
        end, function(value)
            db.showValues = value and true or false
            Apply()
        end, "Show the threat amount next to the percentage.")
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
        api:AddSlider("Font size", 8, 18, 1, function()
            return db.fontSize or 11
        end, function(value)
            db.fontSize = Snap(value, 1, 8, 18)
            Apply()
        end)
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

        api:AddSection("Aggro Warning")
        api:AddDropdown("Role", {
            { value = "auto", text = "Auto" },
            { value = "tank", text = "Tank" },
            { value = "dps", text = "DPS / Healer" },
        }, function()
            if db.roleMode == "tank" or db.roleMode == "dps" then
                return db.roleMode
            end
            return "auto"
        end, function(value)
            db.roleMode = value
            Apply()
        end, "Auto uses your group role, or main-tank assignment. Tank warns when someone else contests or takes aggro. DPS and healers are warned as they approach the tank's threat. Your own pet does not trip the warning while you are tanking.")
        api:AddCheckbox("Warn me before I pull aggro", function()
            return db.warnEnabled and true or false
        end, function(value)
            db.warnEnabled = value and true or false
            Apply()
        end, "Plays a warning sound and turns the window title red when your threat, or your pet's threat, gets close to the tank's. When the client hides exact threat numbers, the warning follows the game's own aggro state instead of the percent slider. In test mode the title turns red, and the sound plays in a real fight.")
        api:AddSlider("Warning at", 50, 100, 5, function()
            return db.warnThreshold or 90
        end, function(value)
            db.warnThreshold = Snap(value, 5, 50, 100)
            Apply()
        end)

        api:AddButtonGroup({
            {
                text = db.hidden and "Show Window" or "Hide Window",
                width = 115,
                onClick = function()
                    if NS.SetHidden then
                        NS.SetHidden(not db.hidden)
                    end
                    RefreshPage()
                end,
            },
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
                end,
            },
        })
    end,
})
