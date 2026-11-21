--[[
    Xius Threat Meter - Options.lua
    Opens this addon's page in the XiusCore settings window.
]]

local addonName, ns = ...
local _, NS = addonName, ns

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

local function Library()
    return _G.XiusCoreSettingsLib
end

function NS.OpenOptions(subTab)
    local Lib = Library()
    if Lib and Lib.OpenModule then
        pcall(Lib.OpenModule, Lib, "Threat", subTab)
    elseif Lib and Lib.Open then
        pcall(Lib.Open, Lib, "Threat", subTab)
    end
end

function NS.ToggleOptions(subTab)
    local Lib = Library()
    if Lib and Lib.Toggle then
        pcall(Lib.Toggle, Lib, "Threat", subTab)
        return
    end
    NS.OpenOptions(subTab)
end

function NS.RefreshOptions()
    local Lib = Library()
    if Lib and Lib.frame and Lib.frame:IsShown() and Lib.page == "Threat" then
        if Lib.RefreshPage then
            pcall(Lib.RefreshPage, Lib)
        end
    end
end
