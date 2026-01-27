local ADDON_NAME, NS = ...

local LDB = LibStub("LibDataBroker-1.1")
local DBIcon = LibStub("LibDBIcon-1.0")

-- SavedVariables (must match .toc)
FrameAlphaTweaksDB = FrameAlphaTweaksDB or {}
FrameAlphaTweaksDB.minimap = FrameAlphaTweaksDB.minimap or { hide = false }

local function ToggleConfig()
  if NS and NS.ToggleConfig then
    NS.ToggleConfig()
  else
    print("|cff00c8ffFAT:|r Config failed to load.")
  end
end

local launcher = LDB:NewDataObject("FrameAlphaTweaks", {
  type = "launcher",
  text = "FrameAlphaTweaks",
  icon = "Interface\\AddOns\\FrameAlphaTweaks\\media\\fat", -- swap later if you want
  OnClick = function(_, button)
    if button == "LeftButton" then
      ToggleConfig()
    end
  end,
  OnTooltipShow = function(tt)
    tt:AddLine("FrameAlphaTweaks")
    tt:AddLine("Left-click: Toggle Config", 1, 1, 1)
  end,
})

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, _, name)
  if name ~= ADDON_NAME then return end
  DBIcon:Register("FrameAlphaTweaks", launcher, FrameAlphaTweaksDB.minimap)
end)
