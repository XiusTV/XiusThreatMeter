--[[
    Xius Threat Meter - Options.lua
    Opens this addon's page in the XiusCore settings window.
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

local function Library()
    return _G.XiusCoreSettingsLib or _G.XiusUISettingsLib
end

function NS.OpenOptions()
    local Lib = Library()
    if Lib and Lib.OpenModule then
        pcall(Lib.OpenModule, Lib, "Threat")
    elseif Lib and Lib.Open then
        pcall(Lib.Open, Lib, "Threat")
    end
end

function NS.ToggleOptions()
    local Lib = Library()
    if Lib and Lib.Toggle then
        pcall(Lib.Toggle, Lib, "Threat")
        return
    end
    NS.OpenOptions()
end

function NS.InitOptions()
end

function NS.RefreshOptions()
end
