local NS = LucidUINS
NS.QoL = NS.QoL or {}

local SHAPES = {
  {file="ring.tga",          tex="Interface/AddOns/LucidUI/Assets/ring.tga"},
  {file="thin_ring.tga",     tex="Interface/AddOns/LucidUI/Assets/thin_ring.tga"},
  {file="thick_ring.tga",    tex="Interface/AddOns/LucidUI/Assets/thick_ring.tga"},
  {file="ring_soft1.tga", tex="Interface/AddOns/LucidUI/Assets/ring_soft1.tga"},
  {file="glow.tga",       tex="Interface/AddOns/LucidUI/Assets/glow.tga"},
  {file="circle.tga",     tex="Interface/AddOns/LucidUI/Assets/circle.tga"},
}

local ringFrame = nil
local ringTex   = nil
local inCombat  = false

local function GetShapeTex(fileKey)
  for _, s in ipairs(SHAPES) do if s.file == fileKey then return s.tex end end
  return SHAPES[1].tex
end

local function BuildRing()
  if ringFrame then return end
  ringFrame = CreateFrame("Frame", "LucidUIMouseRing", UIParent)
  ringFrame:SetSize(64, 64)
  ringFrame:SetFrameStrata("TOOLTIP")
  ringFrame:SetFrameLevel(100)
  ringFrame:EnableMouse(false)
  ringTex = ringFrame:CreateTexture(nil, "OVERLAY")
  ringTex:SetAllPoints()
  if ringTex.SetSnapToPixelGrid then
    ringTex:SetSnapToPixelGrid(false)
    ringTex:SetTexelSnappingBias(0)
  end
  ringFrame:Hide()
end

local function ApplyRingSettings()
  if not ringFrame then return end
  local size    = NS.DB("qolMouseRingSize")    or 48
  local opacity = NS.DB("qolMouseRingOpacity") or 0.8
  local shape   = NS.DB("qolMouseRingShape")   or "ring.tga"
  local r = NS.DB("qolRingColorR") or 0
  local g = NS.DB("qolRingColorG") or 0.8
  local b = NS.DB("qolRingColorB") or 0.8
  ringFrame:SetSize(size, size)
  ringTex:SetTexture(GetShapeTex(shape), "CLAMP", "CLAMP", "TRILINEAR")
  ringTex:SetVertexColor(r, g, b, opacity)
end

local function ShouldBeVisible()
  if not NS.DB("qolMouseRing") then return false end
  if NS.DB("qolMouseRingHideRMB") and IsMouseButtonDown("RightButton") then return false end
  if inCombat then return true end
  -- Outside combat: check "Visible outside Combat" setting
  return NS.DB("qolMouseRingShowOOC") ~= false
end

function NS.QoL.GetMouseRingShapes() return SHAPES end
function NS.QoL.RefreshMouseRing()
  if ringFrame then ApplyRingSettings() end
end

function NS.QoL.InitMouseRing()
  BuildRing()
  ApplyRingSettings()

  -- Combat state tracking
  local combatFrame = CreateFrame("Frame")
  combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
  combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
  combatFrame:SetScript("OnEvent", function(_, event)
    inCombat = (event == "PLAYER_REGEN_DISABLED")
  end)
  inCombat = InCombatLockdown()

  -- OnUpdate: position ring at cursor, re-read settings each frame for live updates
  local settingsTimer = 0
  local lastShape, lastSize, lastR, lastG, lastB, lastOpacity
  local updater = CreateFrame("Frame")
  updater:SetScript("OnUpdate", function(_, elapsed)
    if not ShouldBeVisible() then
      if ringFrame:IsShown() then ringFrame:Hide() end
      return
    end

    -- Re-apply settings periodically (every 0.5s) for live changes from settings menu
    settingsTimer = settingsTimer + elapsed
    if settingsTimer > 0.5 then
      settingsTimer = 0
      local shape   = NS.DB("qolMouseRingShape")   or "ring.tga"
      local size    = NS.DB("qolMouseRingSize")     or 48
      local r       = NS.DB("qolRingColorR")        or 0
      local g       = NS.DB("qolRingColorG")        or 0.8
      local b       = NS.DB("qolRingColorB")        or 0.8
      local opacity = NS.DB("qolMouseRingOpacity")  or 0.8
      if shape ~= lastShape or size ~= lastSize or r ~= lastR or g ~= lastG or b ~= lastB or opacity ~= lastOpacity then
        lastShape, lastSize, lastR, lastG, lastB, lastOpacity = shape, size, r, g, b, opacity
        ApplyRingSettings()
      end
    end

    local scale = UIParent:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    ringFrame:ClearAllPoints()
    ringFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx/scale, cy/scale)
    if not ringFrame:IsShown() then ringFrame:Show() end
  end)
end
