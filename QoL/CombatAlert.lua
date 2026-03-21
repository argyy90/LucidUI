local NS = LucidUINS
NS.QoL = NS.QoL or {}

local alertFrame = nil
local alertTimer = nil
local unlocked   = false

local function ApplySettings()
  if not alertFrame then return end
  local font = NS.GetFontPath(NS.DB("chatFont"))
  local size = NS.DB("qolAlertFontSize") or 28
  local outline = NS.DB("chatFontOutline") or ""
  alertFrame._lbl:SetFont(font, size, outline)
  alertFrame:SetSize(math.max(400, size * 15), math.max(50, size + 20))
end

local function BuildAlert()
  if alertFrame then return end
  alertFrame = CreateFrame("Frame", "LucidUICombatAlert", UIParent, "BackdropTemplate")
  alertFrame:SetSize(400, 50)
  alertFrame:SetMovable(true)
  alertFrame:EnableMouse(true)
  alertFrame:SetClampedToScreen(true)
  alertFrame:RegisterForDrag("LeftButton")
  alertFrame:SetScript("OnDragStart", function() alertFrame:StartMoving() end)
  alertFrame:SetScript("OnDragStop", function()
    alertFrame:StopMovingOrSizing()
    local point, _, _, x, y = alertFrame:GetPoint()
    NS.DBSet("qolCombatAlertPos", {point=point, x=x, y=y})
  end)
  local saved = NS.DB("qolCombatAlertPos")
  if saved and saved.point then
    alertFrame:SetPoint(saved.point, UIParent, saved.point, saved.x, saved.y)
  else
    alertFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
  end
  local lbl = alertFrame:CreateFontString(nil, "OVERLAY")
  lbl:SetFont("Fonts/FRIZQT__.TTF", 22, "OUTLINE")
  lbl:SetAllPoints(); lbl:SetJustifyH("CENTER")
  alertFrame._lbl = lbl
  ApplySettings()
  alertFrame:Hide()
end

local function ShowAlert(text, r, g, b)
  if not NS.DB("qolCombatAlert") and not unlocked then return end
  BuildAlert()
  ApplySettings()
  alertFrame._lbl:SetText(text)
  alertFrame._lbl:SetTextColor(r, g, b, 1)
  alertFrame:Show()
  if alertTimer then alertTimer:Cancel() end
  if not unlocked then
    alertTimer = C_Timer.NewTimer(3, function() alertFrame:Hide(); alertTimer = nil end)
  end
end

function NS.QoL.InitCombatAlert()
  local f = CreateFrame("Frame")
  f:RegisterEvent("PLAYER_REGEN_DISABLED")
  f:RegisterEvent("PLAYER_REGEN_ENABLED")
  f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
      local r = NS.DB("qolAlertEnterR") or 1
      local g = NS.DB("qolAlertEnterG") or 0.2
      local b = NS.DB("qolAlertEnterB") or 0.2
      ShowAlert(NS.DB("qolCombatEnterText") or "++ COMBAT ++", r, g, b)
    else
      local r = NS.DB("qolAlertLeaveR") or 0.2
      local g = NS.DB("qolAlertLeaveG") or 1
      local b = NS.DB("qolAlertLeaveB") or 0.2
      ShowAlert(NS.DB("qolCombatLeaveText") or "-- COMBAT --", r, g, b)
    end
  end)
end

-- Unlock/Lock for position dragging from settings
NS.QoL.CombatAlert = NS.QoL.CombatAlert or {}
function NS.QoL.CombatAlert.SetUnlocked(state)
  unlocked = state
  BuildAlert()
  if unlocked then
    local r = NS.DB("qolAlertEnterR") or 1
    local g = NS.DB("qolAlertEnterG") or 0.2
    local b = NS.DB("qolAlertEnterB") or 0.2
    ApplySettings()
    -- Show background when unlocked so user can see/drag
    alertFrame:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
    alertFrame:SetBackdropColor(0.06, 0.06, 0.06, 0.85)
    alertFrame:SetBackdropBorderColor(NS.CYAN[1], NS.CYAN[2], NS.CYAN[3], 0.6)
    alertFrame._lbl:SetText(NS.DB("qolCombatEnterText") or "++ COMBAT ++")
    alertFrame._lbl:SetTextColor(r, g, b, 1)
    alertFrame:Show()
    if alertTimer then alertTimer:Cancel(); alertTimer = nil end
  else
    -- Remove background when locked
    alertFrame:SetBackdrop(nil)
    alertFrame:Hide()
  end
end

function NS.QoL.CombatAlert.RefreshSettings()
  ApplySettings()
end
