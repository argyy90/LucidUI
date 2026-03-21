local NS = LucidUINS
local L  = LucidUIL
NS.QoL = NS.QoL or {}

local timerFrame  = nil
local combatStart = nil
local ticker      = nil
local unlocked    = false

local function FormatTime(secs)
  local m = math.floor(secs / 60)
  local s = secs % 60
  return string.format("%d:%02d", m, s)
end

local function IsPlayerInInstance()
  local _, instanceType = IsInInstance()
  return instanceType == "party" or instanceType == "raid" or instanceType == "arena" or instanceType == "pvp"
end

local function ApplySettings()
  if not timerFrame then return end

  -- Font: use global chat font
  local font = NS.GetFontPath(NS.DB("chatFont"))
  local size = NS.DB("qolTimerFontSize") or 28
  local outline = NS.DB("chatFontOutline") or ""
  timerFrame._label:SetFont(font, size, outline)

  -- Hide prefix (COMBAT icon)
  local hidePrefix = NS.DB("qolCombatTimerHidePrefix")
  if hidePrefix then
    timerFrame._icon:Hide()
    timerFrame._label:ClearAllPoints()
    timerFrame._label:SetPoint("CENTER", 0, 0)
  else
    timerFrame._icon:Show()
    timerFrame._icon:SetFont(font, size, outline)
    timerFrame._label:ClearAllPoints()
    timerFrame._label:SetPoint("LEFT", timerFrame._icon, "RIGHT", 4, 0)
  end

  -- Show background
  local showBg = NS.DB("qolCombatTimerShowBg")
  if showBg then
    timerFrame:SetBackdropColor(0.06, 0.06, 0.06, 0.85)
    timerFrame:SetBackdropBorderColor(0.15, 0.15, 0.15, 1)
  else
    timerFrame:SetBackdropColor(0, 0, 0, 0)
    timerFrame:SetBackdropBorderColor(0, 0, 0, 0)
  end

  -- Timer color
  local cr = NS.DB("qolTimerColorR") or 1
  local cg = NS.DB("qolTimerColorG") or 1
  local cb = NS.DB("qolTimerColorB") or 1
  timerFrame._label:SetTextColor(cr, cg, cb)

  -- Icon uses same color as timer
  timerFrame._icon:SetTextColor(cr, cg, cb)

  -- Auto-size frame to fit
  C_Timer.After(0, function()
    if not timerFrame then return end
    local iconW = timerFrame._icon:IsShown() and (timerFrame._icon:GetStringWidth() + 10) or 0
    local labelW = timerFrame._label:GetStringWidth() or 40
    timerFrame:SetSize(math.max(88, iconW + labelW + 16), math.max(26, size + 10))
  end)
end

local function BuildTimer()
  if timerFrame then return end

  timerFrame = CreateFrame("Frame", "LucidUICombatTimer", UIParent, "BackdropTemplate")
  timerFrame:SetSize(88, 26)
  timerFrame:SetBackdrop({
    bgFile   = "Interface/Buttons/WHITE8X8",
    edgeFile = "Interface/Buttons/WHITE8X8",
    edgeSize = 1,
  })
  timerFrame:SetBackdropColor(0.06, 0.06, 0.06, 0.85)
  timerFrame:SetBackdropBorderColor(0.15, 0.15, 0.15, 1)
  timerFrame:SetFrameStrata("HIGH")
  timerFrame:SetMovable(true)
  timerFrame:EnableMouse(true)
  timerFrame:SetClampedToScreen(true)
  timerFrame:RegisterForDrag("LeftButton")
  timerFrame:SetScript("OnDragStart", function() timerFrame:StartMoving() end)
  timerFrame:SetScript("OnDragStop",  function()
    timerFrame:StopMovingOrSizing()
    local point, _, _, x, y = timerFrame:GetPoint()
    NS.DBSet("qolCombatTimerPos", {point=point, x=x, y=y})
  end)

  local savedPos = NS.DB("qolCombatTimerPos")
  if savedPos and savedPos.point then
    timerFrame:ClearAllPoints()
    timerFrame:SetPoint(savedPos.point, UIParent, savedPos.point, savedPos.x, savedPos.y)
  else
    timerFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
  end

  local icon = timerFrame:CreateFontString(nil, "OVERLAY")
  icon:SetFont("Fonts/FRIZQT__.TTF", 11, "")
  icon:SetPoint("LEFT", 6, 0)
  icon:SetText(L["COMBAT"])
  timerFrame._icon = icon

  local label = timerFrame:CreateFontString(nil, "OVERLAY")
  label:SetFont("Fonts/FRIZQT__.TTF", 12, "OUTLINE")
  label:SetPoint("LEFT", icon, "RIGHT", 4, 0)
  label:SetText("0:00")
  timerFrame._label = label

  ApplySettings()
  timerFrame:Hide()
end

local function StartTicker()
  if ticker then return end
  ticker = C_Timer.NewTicker(1, function()
    if timerFrame and combatStart then
      timerFrame._label:SetText(FormatTime(math.floor(GetTime() - combatStart)))
    end
  end)
end

local function StopTicker()
  if ticker then ticker:Cancel(); ticker = nil end
end

local function OnCombatEnter()
  if not NS.DB("qolCombatTimer") then return end
  -- Instance only check
  if NS.DB("qolCombatTimerInstance") and not IsPlayerInInstance() then return end
  combatStart = GetTime()
  BuildTimer()
  ApplySettings()
  timerFrame._label:SetText("0:00")
  timerFrame:Show()
  StartTicker()
end

local function OnCombatLeave()
  StopTicker()
  if timerFrame and not unlocked then timerFrame:Hide() end
  combatStart = nil
end

function NS.QoL.InitCombatTimer()
  local f = CreateFrame("Frame")
  f:RegisterEvent("PLAYER_REGEN_DISABLED")
  f:RegisterEvent("PLAYER_REGEN_ENABLED")
  f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
      OnCombatEnter()
    else
      OnCombatLeave()
    end
  end)
end

-- Unlock/Lock for position dragging from settings
NS.QoL.CombatTimer = NS.QoL.CombatTimer or {}
function NS.QoL.CombatTimer.SetUnlocked(state)
  unlocked = state
  BuildTimer()
  if unlocked then
    ApplySettings()
    -- Force background visible when unlocked so user can see/drag it
    timerFrame:SetBackdropColor(0.06, 0.06, 0.06, 0.85)
    timerFrame:SetBackdropBorderColor(NS.CYAN[1], NS.CYAN[2], NS.CYAN[3], 0.6)
    timerFrame._label:SetText("0:00")
    timerFrame._icon:SetText(L["COMBAT"])
    timerFrame._icon:Show()
    timerFrame:Show()
  else
    if not InCombatLockdown() then
      timerFrame:Hide()
    end
  end
end

function NS.QoL.CombatTimer.RefreshSettings()
  if timerFrame then ApplySettings() end
end
