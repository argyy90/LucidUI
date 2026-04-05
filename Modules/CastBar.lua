-- LucidUI Modules/CastBar.lua
-- Custom player cast bar with channel and interrupt support.

local NS = LucidUINS
NS.CastBar = NS.CastBar or {}
local CB = NS.CastBar
local cbInitialized = false

-- ── Defaults ────────────────────────────────────────────────────────────
local DEFAULTS = {
  width = 350, height = 10, autoWidth = true,
  iconSize = 10, showIcon = false,
  showTimer = true, showSpellName = true,
  texture = "Flat",
  bgTexture = "Flat",
  castColor = {0.25, 0.65, 0.90},
  channelColor = {0.20, 0.80, 0.40},
  failColor = {0.80, 0.15, 0.15},
  uninterruptibleColor = {0.50, 0.50, 0.50},
  useClassColor = false,
  bgColor = {0.08, 0.08, 0.12, 0.85},
  borderColor = {0, 0, 0, 1},
  interruptible = true, -- show border change on non-interruptible
  font = "default",
  fontSize = 12,
  textYOffset = 5,
}

local Opt, OptSet = NS.MakeOpt("cb_", DEFAULTS)

-- ── Build Cast Bar Frame ────────────────────────────────────────────────
local bar = nil
local casting, channeling = false, false
local castStartTime, castEndTime, castDuration = 0, 0, 0
local castSpellID, castSpellName, castSpellTex = nil, "", nil
local castNotInterruptible = false
local fadeOut, fadeAlpha = false, 1

local function CreateBar()
  if bar then return bar end

  local f = CreateFrame("Frame", "LucidUICastBar", UIParent, "BackdropTemplate")
  f:SetFrameStrata("MEDIUM"); f:SetClampedToScreen(true)
  f:SetMovable(true); f:EnableMouse(false)
  f:SetSize(Opt("width"), Opt("height"))

  -- Position
  local pos = Opt("pos")
  if pos and pos.p then
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", pos.x, pos.y)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
    f._needsAnchor = true
  end

  -- Background
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints(); f.bg:SetTexture(NS.GetBarTexturePath(Opt("bgTexture") or "Flat"))
  local bgc = Opt("bgColor")
  f.bg:SetVertexColor(bgc[1], bgc[2], bgc[3], bgc[4] or 0.85)

  -- Border (1px)
  f:SetBackdrop({edgeFile=NS.TEX_WHITE, edgeSize=1})
  local bc = Opt("borderColor")
  f:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4] or 1)
  f:SetBackdropColor(0, 0, 0, 0)

  -- Status bar fill
  f.bar = CreateFrame("StatusBar", nil, f)
  f.bar:SetPoint("TOPLEFT", 1, -1); f.bar:SetPoint("BOTTOMRIGHT", -1, 1)
  f.bar:SetMinMaxValues(0, 1); f.bar:SetValue(0)
  f.bar:SetStatusBarTexture(NS.GetBarTexturePath(Opt("texture")))
  local cc = Opt("castColor")
  f.bar:SetStatusBarColor(cc[1], cc[2], cc[3])

  -- Spark (bright line at fill edge)
  f.spark = f.bar:CreateTexture(nil, "OVERLAY")
  f.spark:SetSize(2, Opt("height") - 2)
  f.spark:SetColorTexture(1, 1, 1, 0.7)
  f.spark:SetBlendMode("ADD")

  -- Spell icon (matches bar height)
  f.icon = f:CreateTexture(nil, "OVERLAY")
  local h = Opt("height")
  f.icon:SetSize(h, h)
  f.icon:SetPoint("RIGHT", f, "LEFT", -2, 0)
  f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  -- Spell name text
  local fontPath = NS.GetFontPath(Opt("font"))
  local fontSize = Opt("fontSize")
  local tOff = Opt("textYOffset") or 0
  f.spellText = f.bar:CreateFontString(nil, "OVERLAY")
  f.spellText:SetFont(fontPath, fontSize, "OUTLINE")
  f.spellText:SetPoint("LEFT", 4, tOff); f.spellText:SetJustifyH("LEFT")

  -- Timer text
  f.timerText = f.bar:CreateFontString(nil, "OVERLAY")
  f.timerText:SetFont(fontPath, fontSize, "OUTLINE")
  f.timerText:SetPoint("RIGHT", -4, tOff); f.timerText:SetJustifyH("RIGHT")

  -- Non-interruptible shield icon
  f.shieldIcon = f:CreateTexture(nil, "OVERLAY", nil, 7)
  f.shieldIcon:SetSize(14, 14); f.shieldIcon:SetPoint("LEFT", f, "LEFT", 2, 0)
  f.shieldIcon:SetAtlas("nameplates-InterruptShield"); f.shieldIcon:Hide()

  f:Hide()
  bar = f
  return f
end

-- ── Apply visual options ────────────────────────────────────────────────
local function GetEffectiveWidth()
  if Opt("autoWidth") then
    local cdw = NS.GetCooldownsWidth and NS.GetCooldownsWidth()
    if cdw then return cdw end
  end
  return Opt("width")
end

local function ApplyBarStyle()
  if not bar then return end
  local w, h = GetEffectiveWidth(), Opt("height")
  bar:SetSize(w, h)
  bar.bar:SetStatusBarTexture(NS.GetBarTexturePath(Opt("texture")))
  bar.bg:SetTexture(NS.GetBarTexturePath(Opt("bgTexture") or "Flat"))
  local bgc = Opt("bgColor")
  bar.bg:SetVertexColor(bgc[1], bgc[2], bgc[3], bgc[4] or 0.85)
  local bc = Opt("borderColor")
  bar:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4] or 1)
  bar.spark:SetSize(2, h - 2)
  bar.icon:SetSize(h, h)
  bar.icon:SetShown(Opt("showIcon"))
  local fontPath = NS.GetFontPath(Opt("font"))
  local fontSize = Opt("fontSize")
  local tOff = Opt("textYOffset") or 0
  bar.spellText:SetFont(fontPath, fontSize, "OUTLINE")
  bar.spellText:ClearAllPoints(); bar.spellText:SetPoint("LEFT", 4, tOff)
  bar.timerText:SetFont(fontPath, fontSize, "OUTLINE")
  bar.timerText:ClearAllPoints(); bar.timerText:SetPoint("RIGHT", -4, tOff)
end

-- ── Cast state management ───────────────────────────────────────────────
local function GetClassColor()
  local _, className = UnitClass("player")
  local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[className]
  if cc then return {cc.r, cc.g, cc.b} end
  return {1, 1, 1}
end

local function SetCastColor()
  if not bar then return end
  local c
  if castNotInterruptible then
    c = Opt("uninterruptibleColor")
  elseif channeling then
    c = Opt("channelColor")
  elseif Opt("useClassColor") then
    c = GetClassColor()
  else
    c = Opt("castColor")
  end
  bar.bar:SetStatusBarColor(c[1], c[2], c[3])
end


local function StartCast(unit)
  if unit ~= "player" then return end
  local name, _, tex, startMS, endMS, _, _, notInterruptible, spellID = UnitCastingInfo("player")
  if not name then return end

  casting = true; channeling = false; fadeOut = false; fadeAlpha = 1
  castSpellName = name; castSpellTex = tex; castSpellID = spellID
  castStartTime = startMS / 1000; castEndTime = endMS / 1000
  castDuration = castEndTime - castStartTime
  castNotInterruptible = notInterruptible

  CreateBar(); ApplyBarStyle(); SetCastColor()
  bar.icon:SetTexture(castSpellTex)
  bar.spellText:SetText(Opt("showSpellName") and castSpellName or "")
  bar.shieldIcon:SetShown(castNotInterruptible and Opt("interruptible"))
  bar:SetAlpha(1); bar:Show()
end

local function StartChannel(unit)
  if unit ~= "player" then return end
  local name, _, tex, startMS, endMS, _, notInterruptible, spellID = UnitChannelInfo("player")
  if not name then return end

  channeling = true; casting = false; fadeOut = false; fadeAlpha = 1
  castSpellName = name; castSpellTex = tex; castSpellID = spellID
  castStartTime = startMS / 1000; castEndTime = endMS / 1000
  castDuration = castEndTime - castStartTime
  castNotInterruptible = notInterruptible

  CreateBar(); ApplyBarStyle(); SetCastColor()
  bar.icon:SetTexture(castSpellTex)
  bar.spellText:SetText(Opt("showSpellName") and castSpellName or "")
  bar.shieldIcon:SetShown(castNotInterruptible and Opt("interruptible"))
  bar:SetAlpha(1); bar:Show()
end

local function StopCast(failed)
  if not bar then return end
  if failed then
    local fc = Opt("failColor")
    bar.bar:SetStatusBarColor(fc[1], fc[2], fc[3])
  end
  casting = false; channeling = false
  fadeOut = true; fadeAlpha = 1
end

local function UpdateCastDelay(unit)
  if unit ~= "player" then return end
  if casting then
    local _, _, _, startMS, endMS = UnitCastingInfo("player")
    if startMS then castStartTime = startMS / 1000; castEndTime = endMS / 1000; castDuration = castEndTime - castStartTime end
  elseif channeling then
    local _, _, _, startMS, endMS = UnitChannelInfo("player")
    if startMS then castStartTime = startMS / 1000; castEndTime = endMS / 1000; castDuration = castEndTime - castStartTime end
  end
end

-- ── OnUpdate: smooth bar progress ───────────────────────────────────────
local function OnUpdate(self, dt)
  if fadeOut then
    fadeAlpha = fadeAlpha - dt * 4
    if fadeAlpha <= 0 then
      fadeAlpha = 0; fadeOut = false; bar:Hide()
    end
    bar:SetAlpha(fadeAlpha)
    return
  end

  if not (casting or channeling) then return end
  local now = GetTime()
  local progress

  if channeling then
    -- Channel: bar drains from full to empty
    progress = (castEndTime - now) / castDuration
  else
    -- Normal cast: bar fills from empty to full
    progress = (now - castStartTime) / castDuration
  end
  progress = math.max(0, math.min(1, progress))

  bar.bar:SetValue(progress)

  -- Spark position
  local barW = bar.bar:GetWidth()
  bar.spark:ClearAllPoints()
  bar.spark:SetPoint("CENTER", bar.bar, "LEFT", progress * barW, 0)
  bar.spark:SetShown(progress > 0 and progress < 1)

  -- Timer text
  if Opt("showTimer") then
    local remaining = castEndTime - now
    if remaining < 0 then remaining = 0 end
    bar.timerText:SetText(string.format("%.1f", remaining))
  else
    bar.timerText:SetText("")
  end

  -- Cast finished naturally
  if (casting or channeling) and now >= castEndTime then
    StopCast(false)
  end
end

-- ── Event handling ──────────────────────────────────────────────────────
local evFrame = CreateFrame("Frame")

local function OnEvent(_, event, unit, ...)
  if event == "PLAYER_LOGIN" then
    if not NS.IsCDMEnabled() then return end
    C_Timer.After(1.0, function()
      if cbInitialized then return end
      cbInitialized = true
      NS.SafeCall(CB.Enable, "CastBar")
    end)
    return
  end
  if event == "PLAYER_ENTERING_WORLD" then
    local isInitialLogin = ...
    if isInitialLogin or cbInitialized then return end
    if not NS.IsCDMEnabled() then return end
    C_Timer.After(1.0, function()
      if cbInitialized then return end
      cbInitialized = true
      NS.SafeCall(CB.Enable, "CastBar")
    end)
    return
  end
  if event == "PLAYER_LOGOUT" then
    -- Only save if user manually positioned (not auto-anchored)
    if bar and Opt("pos") then
      local left, top = bar:GetLeft(), bar:GetTop()
      if left then OptSet("pos", {p="TOPLEFT", x=left, y=top - GetScreenHeight()}) end
    end
    return
  end
  if unit and unit ~= "player" then return end

  if event == "UNIT_SPELLCAST_START" then StartCast(unit)
  elseif event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_EMPOWER_START" then StartChannel(unit)
  elseif event == "UNIT_SPELLCAST_STOP" then if casting then StopCast(false) end
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then -- let OnUpdate finish the cast naturally via castEndTime
  elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" or event == "UNIT_SPELLCAST_EMPOWER_STOP" then if channeling then StopCast(false) end
  elseif event == "UNIT_SPELLCAST_INTERRUPTED" then StopCast(true)
  elseif event == "UNIT_SPELLCAST_DELAYED" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" or event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then UpdateCastDelay(unit)
  elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" then castNotInterruptible = false; if bar then bar.shieldIcon:Hide() end
  elseif event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then castNotInterruptible = true; if bar and Opt("interruptible") then bar.shieldIcon:Show() end
  end
end

evFrame:RegisterEvent("PLAYER_LOGIN")
evFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
evFrame:RegisterEvent("PLAYER_LOGOUT")
evFrame:SetScript("OnEvent", OnEvent)

-- ── Enable / Disable ────────────────────────────────────────────────────

-- Blizzard's default cast bar events — saved once so Disable() can restore them cleanly
local blizzCastBarEvents = {
  "UNIT_SPELLCAST_START",
  "UNIT_SPELLCAST_STOP",
  "UNIT_SPELLCAST_DELAYED",
  "UNIT_SPELLCAST_CHANNEL_START",
  "UNIT_SPELLCAST_CHANNEL_UPDATE",
  "UNIT_SPELLCAST_CHANNEL_STOP",
  "UNIT_SPELLCAST_INTERRUPTIBLE",
  "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
  "UNIT_SPELLCAST_SUCCEEDED",
}

function CB.Enable()
  evFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
  evFrame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
  evFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
  evFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
  evFrame:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED", "player")
  evFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
  evFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
  evFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "player")
  evFrame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", "player")
  evFrame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", "player")
  evFrame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_UPDATE", "player")
  evFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTIBLE", "player")
  evFrame:RegisterUnitEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "player")
  CreateBar()
  CB._bar = bar
  bar:SetScript("OnUpdate", OnUpdate)
  -- Snap to chain if no saved position
  if bar._needsAnchor then
    bar._needsAnchor = nil
    if not NS.AnchorToChain(bar, "CastBar") then
      C_Timer.After(2, function()
        if Opt("pos") or not bar then return end
        NS.AnchorToChain(bar, "CastBar")
      end)
    end
  end
  -- Hide default
  if PlayerCastingBarFrame then PlayerCastingBarFrame:UnregisterAllEvents(); PlayerCastingBarFrame:Hide() end
end

function CB.Disable()
  local allEvents = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_STOP", "UNIT_SPELLCAST_EMPOWER_UPDATE",
    "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
  }
  for _, event in ipairs(allEvents) do
    evFrame:UnregisterEvent(event)
  end
  if bar then bar:SetScript("OnUpdate", nil); bar:Hide() end
  -- Restore Blizzard's default cast bar
  if PlayerCastingBarFrame then
    PlayerCastingBarFrame:Show()
    for _, event in ipairs(blizzCastBarEvents) do
      pcall(function() PlayerCastingBarFrame:RegisterUnitEvent(event, "player") end)
    end
  end
end

function CB.Refresh()
  if bar then ApplyBarStyle() end
end

-- ── Settings Tab ────────────────────────────────────────────────────────
function CB.SetupSettings(parent)
  local container = CreateFrame("Frame", nil, parent)
  local MakeCard = NS._SMakeCard
  local MakePage = NS._SMakePage
  local R = NS._SR
  local SBD = NS.BACKDROP
  local sc, Append = MakePage(container)

  local function Toggle(card, label, key, tip)
    local cb = NS.ChatGetCheckbox(card.inner, label, 26, function(s)
      OptSet(key, s)
      if key == "enabled" then
        if s then CB.Enable() else CB.Disable() end
      else CB.Refresh() end
    end, tip)
    R(card, cb, 26); cb:SetValue(Opt(key) ~= false)
  end
  local function Slider(card, label, key, mn, mx, fmt, default, scale)
    local s; s = NS.ChatGetSlider(card.inner, label, mn, mx, fmt, function()
      OptSet(key, scale and s:GetValue() / scale or s:GetValue()); CB.Refresh()
    end); R(card, s, 40)
    s:SetValue(scale and (Opt(key) or default) * scale or (Opt(key) or default))
  end
  local function Dropdown(card, label, labels, values, key, default, onChange, maxH)
    local dd = NS.ChatGetDropdown(card.inner, label,
      function(v) return (Opt(key) or default) == v end,
      onChange or function(v) OptSet(key, v); CB.Refresh() end)
    dd:Init(labels, values, maxH); R(card, dd, 46)
  end
  local function TogglePair(card, l1, k1, l2, k2)
    local row = CreateFrame("Frame", nil, card.inner); row:SetHeight(26)
    local cb1 = NS.ChatGetCheckbox(row, l1, 26, function(s) OptSet(k1, s); CB.Refresh() end)
    cb1:ClearAllPoints(); cb1:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    cb1:SetPoint("BOTTOMRIGHT", row, "BOTTOM", -2, 0); cb1:SetValue(Opt(k1) ~= false)
    local cb2 = NS.ChatGetCheckbox(row, l2, 26, function(s) OptSet(k2, s); CB.Refresh() end)
    cb2:ClearAllPoints(); cb2:SetPoint("TOPLEFT", row, "TOP", 2, 0)
    cb2:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0); cb2:SetValue(Opt(k2) ~= false)
    R(card, row, 26)
  end
  -- ── General card ──
  local cGen = MakeCard(sc, "General")
  local enRow = CreateFrame("Frame", nil, cGen.inner); enRow:SetHeight(26)
  -- Reset position button
  local resetBtn = CreateFrame("Button", nil, enRow, "BackdropTemplate"); resetBtn:SetSize(50, 20); resetBtn:SetPoint("RIGHT", -8, 0)
  resetBtn:SetBackdrop(SBD); resetBtn:SetBackdropColor(0.04, 0.04, 0.07, 1); resetBtn:SetBackdropBorderColor(0.12, 0.12, 0.20, 1)
  local resetFS = resetBtn:CreateFontString(nil, "OVERLAY"); resetFS:SetFont(NS.FONT, 9, ""); resetFS:SetPoint("CENTER"); resetFS:SetTextColor(0.65, 0.65, 0.75); resetFS:SetText("Reset")
  resetBtn:SetScript("OnClick", function()
    OptSet("pos", nil)
    if bar then NS.AnchorToChain(bar, "CastBar") end
  end)
  resetBtn:SetScript("OnEnter", function() local r,g,b = NS.ChatGetAccentRGB(); resetBtn:SetBackdropBorderColor(r, g, b, 0.8) end)
  resetBtn:SetScript("OnLeave", function() resetBtn:SetBackdropBorderColor(0.12, 0.12, 0.20, 1) end)
  -- Unlock button
  local lockBtn = CreateFrame("Button", nil, enRow, "BackdropTemplate"); lockBtn:SetSize(70, 20); lockBtn:SetPoint("RIGHT", resetBtn, "LEFT", -4, 0)
  lockBtn:SetBackdrop(SBD); lockBtn:SetBackdropColor(0.04, 0.04, 0.07, 1); lockBtn:SetBackdropBorderColor(0.12, 0.12, 0.20, 1)
  local lockFS = lockBtn:CreateFontString(nil, "OVERLAY"); lockFS:SetFont(NS.FONT, 9, ""); lockFS:SetPoint("CENTER"); lockFS:SetTextColor(0.65, 0.65, 0.75); lockFS:SetText("Unlock")
  local unlocked = false
  lockBtn:SetScript("OnClick", function()
    unlocked = not unlocked
    lockFS:SetText(unlocked and "Lock" or "Unlock")
    local r, g, b = NS.ChatGetAccentRGB()
    if unlocked then lockBtn:SetBackdropBorderColor(r, g, b, 0.8) else lockBtn:SetBackdropBorderColor(0.12, 0.12, 0.20, 1) end
    CreateBar(); ApplyBarStyle()
    if unlocked then
      bar:Show(); bar:SetAlpha(1)
      bar.bar:SetValue(0.65)
      bar.spellText:SetText("Cast Bar"); bar.timerText:SetText("1.5")
      bar:EnableMouse(true); bar:RegisterForDrag("LeftButton")
      bar:SetScript("OnDragStart", function(s) s:StartMoving() end)
      bar:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        local left, top = s:GetLeft(), s:GetTop()
        if left then OptSet("pos", {p="TOPLEFT", x=left, y=top - GetScreenHeight()}) end
        NS.UpdateMoverPopup()
      end)
      NS.ShowMoverPopup(bar, "Cast Bar", function(f)
        local left, top = f:GetLeft(), f:GetTop()
        if left then OptSet("pos", {p="TOPLEFT", x=left, y=top - GetScreenHeight()}) end
      end, function()
        OptSet("pos", nil)
        if bar then NS.AnchorToChain(bar, "CastBar") end
      end)
    else
      if not (casting or channeling) then bar:Hide() end
      bar:EnableMouse(false); bar:RegisterForDrag()
      bar:SetScript("OnDragStart", nil); bar:SetScript("OnDragStop", nil)
      bar.spellText:SetText(""); bar.timerText:SetText("")
      NS.HideMoverPopup()
    end
  end)
  lockBtn:SetScript("OnEnter", function() local r,g,b = NS.ChatGetAccentRGB(); lockBtn:SetBackdropBorderColor(r, g, b, 0.8) end)
  lockBtn:SetScript("OnLeave", function() if not unlocked then lockBtn:SetBackdropBorderColor(0.12, 0.12, 0.20, 1) end end)
  R(cGen, enRow, 26)
  local autoWCb = NS.ChatGetCheckbox(cGen.inner, "Auto Width (match Cooldowns)", 26, function(s)
    OptSet("autoWidth", s); CB.Refresh()
  end, "Automatically match width to Essential Cooldowns")
  R(cGen, autoWCb, 26); autoWCb:SetValue(Opt("autoWidth") ~= false)
  cGen:Finish(); Append(cGen, cGen:GetHeight()); Append(NS._SSep(sc), 9)

  -- ── Size card ──
  local cSize = MakeCard(sc, "Size")
  Slider(cSize, "Width", "width", 100, 400, "%spx", 220)
  Slider(cSize, "Height", "height", 10, 40, "%spx", 20)
  cSize:Finish(); Append(cSize, cSize:GetHeight()); Append(NS._SSep(sc), 9)

  -- ── Appearance card ──
  local cApp = MakeCard(sc, "Appearance")
  local barTexNames = {}
  local rawBars = NS.GetLSMStatusBars and NS.GetLSMStatusBars() or {}
  for _, b in ipairs(rawBars) do barTexNames[#barTexNames+1] = b.label end
  if #barTexNames == 0 then barTexNames = {"Flat"} end

  -- Helper: pair row (two elements side by side)
  local function PairRow(card, h)
    local pr = CreateFrame("Frame", nil, card.inner); pr:SetHeight(h or 26)
    local lh = CreateFrame("Frame", nil, pr)
    lh:SetPoint("TOPLEFT", 0, 0); lh:SetPoint("BOTTOMRIGHT", pr, "BOTTOM", -2, 0)
    local rh = CreateFrame("Frame", nil, pr)
    rh:SetPoint("TOPLEFT", pr, "TOP", 2, 0); rh:SetPoint("BOTTOMRIGHT", 0, 0)
    R(card, pr, h or 26)
    return lh, rh
  end

  TogglePair(cApp, "Show Icon", "showIcon", "Interrupt Shield", "interruptible")
  -- Dropdowns side by side
  local dLh, dRh = PairRow(cApp, 46)
  local dd1 = NS.ChatGetDropdown(dLh, "Bar Texture",
    function(v) return (Opt("texture") or "Flat") == v end,
    function(v) OptSet("texture", v); CB.Refresh() end)
  dd1:Init(barTexNames, barTexNames, 200)
  dd1:SetParent(dLh); dd1:ClearAllPoints(); dd1:SetAllPoints(dLh)
  local dd2 = NS.ChatGetDropdown(dRh, "Background",
    function(v) return (Opt("bgTexture") or "Flat") == v end,
    function(v) OptSet("bgTexture", v); CB.Refresh() end)
  dd2:Init(barTexNames, barTexNames, 200)
  dd2:SetParent(dRh); dd2:ClearAllPoints(); dd2:SetAllPoints(dRh)
  -- Colors side by side:
  local function ColorPair(card, lbl1, key1, lbl2, key2, alpha1, alpha2)
    local pr = CreateFrame("Frame", nil, card.inner); pr:SetHeight(24)
    -- Left color
    local lfs1 = pr:CreateFontString(nil, "OVERLAY"); lfs1:SetFont(NS.FONT, 10, "")
    lfs1:SetPoint("LEFT", 20, 0); lfs1:SetTextColor(0.6, 0.6, 0.7); lfs1:SetText(lbl1)
    local cur1 = Opt(key1) or {1,1,1,1}
    local sw1 = CreateFrame("Frame", nil, pr, "BackdropTemplate"); sw1:SetSize(20, 16); sw1:SetPoint("LEFT", 110, 0)
    sw1:SetBackdrop(SBD); sw1:SetBackdropColor(cur1[1], cur1[2], cur1[3], cur1[4] or 1); sw1:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    local hit1 = CreateFrame("Button", nil, pr, "BackdropTemplate")
    hit1:SetPoint("TOPLEFT", pr, "TOPLEFT", 0, 0); hit1:SetPoint("BOTTOMRIGHT", pr, "BOTTOM", -2, 0)
    hit1:SetBackdrop({bgFile=NS.TEX_WHITE})
    hit1:SetBackdropColor(1, 1, 1, 0)
    hit1:SetScript("OnEnter", function() hit1:SetBackdropColor(1, 1, 1, 0.06) end)
    hit1:SetScript("OnLeave", function() hit1:SetBackdropColor(1, 1, 1, 0) end)
    hit1:SetScript("OnClick", function()
      ColorPickerFrame:SetupColorPickerAndShow({r=cur1[1], g=cur1[2], b=cur1[3],
        hasOpacity = alpha1, opacity = alpha1 and (1 - (cur1[4] or 1)) or nil,
        swatchFunc = function()
          local r,g,b = ColorPickerFrame:GetColorRGB()
          local a = alpha1 and (1 - ColorPickerFrame:GetColorAlpha()) or 1
          cur1 = {r,g,b,a}; OptSet(key1, cur1); sw1:SetBackdropColor(r,g,b,a); CB.Refresh()
        end,
        opacityFunc = alpha1 and function()
          local r,g,b = ColorPickerFrame:GetColorRGB()
          local a = 1 - ColorPickerFrame:GetColorAlpha()
          cur1 = {r,g,b,a}; OptSet(key1, cur1); sw1:SetBackdropColor(r,g,b,a); CB.Refresh()
        end or nil,
        cancelFunc = function() sw1:SetBackdropColor(cur1[1], cur1[2], cur1[3], cur1[4] or 1) end})
    end)
    -- Right color (optional)
    if key2 then
      local lfs2 = pr:CreateFontString(nil, "OVERLAY"); lfs2:SetFont(NS.FONT, 10, "")
      lfs2:SetPoint("LEFT", pr, "CENTER", 20, 0); lfs2:SetTextColor(0.6, 0.6, 0.7); lfs2:SetText(lbl2)
      local cur2 = Opt(key2) or {1,1,1,1}
      local sw2 = CreateFrame("Frame", nil, pr, "BackdropTemplate"); sw2:SetSize(20, 16); sw2:SetPoint("LEFT", lfs2, "LEFT", 90, 0)
      sw2:SetBackdrop(SBD); sw2:SetBackdropColor(cur2[1], cur2[2], cur2[3], cur2[4] or 1); sw2:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
      local hit2 = CreateFrame("Button", nil, pr, "BackdropTemplate")
      hit2:SetPoint("TOPLEFT", pr, "TOP", 2, 0); hit2:SetPoint("BOTTOMRIGHT", pr, "BOTTOMRIGHT", 0, 0)
      hit2:SetBackdrop({bgFile=NS.TEX_WHITE})
      hit2:SetBackdropColor(1, 1, 1, 0)
      hit2:SetScript("OnEnter", function() hit2:SetBackdropColor(1, 1, 1, 0.06) end)
      hit2:SetScript("OnLeave", function() hit2:SetBackdropColor(1, 1, 1, 0) end)
      hit2:SetScript("OnClick", function()
        ColorPickerFrame:SetupColorPickerAndShow({r=cur2[1], g=cur2[2], b=cur2[3],
          hasOpacity = alpha2, opacity = alpha2 and (1 - (cur2[4] or 1)) or nil,
          swatchFunc = function()
            local r,g,b = ColorPickerFrame:GetColorRGB()
            local a = alpha2 and (1 - ColorPickerFrame:GetColorAlpha()) or 1
            cur2 = {r,g,b,a}; OptSet(key2, cur2); sw2:SetBackdropColor(r,g,b,a); CB.Refresh()
          end,
          opacityFunc = alpha2 and function()
            local r,g,b = ColorPickerFrame:GetColorRGB()
            local a = 1 - ColorPickerFrame:GetColorAlpha()
            cur2 = {r,g,b,a}; OptSet(key2, cur2); sw2:SetBackdropColor(r,g,b,a); CB.Refresh()
          end or nil,
          cancelFunc = function() sw2:SetBackdropColor(cur2[1], cur2[2], cur2[3], cur2[4] or 1) end})
      end)
    end
    R(card, pr, 24)
  end
  Toggle(cApp, "Class Color", "useClassColor", "Use your class color instead of Cast Color")
  ColorPair(cApp, "Cast:", "castColor", "Uninterruptible:", "uninterruptibleColor")
  ColorPair(cApp, "Channel:", "channelColor", "Failed:", "failColor")
  ColorPair(cApp, "Background:", "bgColor", "", nil, true)
  cApp:Finish(); Append(cApp, cApp:GetHeight()); Append(NS._SSep(sc), 9)

  -- ── Text card ──
  local cTxt = MakeCard(sc, "Text")
  TogglePair(cTxt, "Show Timer", "showTimer", "Spell Name", "showSpellName")
  local fontNames, fontValues = {"Default"}, {"default"}
  for _, ft in ipairs(NS.GetLSMFonts()) do fontNames[#fontNames+1] = ft.label; fontValues[#fontValues+1] = ft.label end
  Dropdown(cTxt, "Font", fontNames, fontValues, "font", "default", nil, 200)
  Slider(cTxt, "Font Size", "fontSize", 8, 20, "%spx", 11)
  Slider(cTxt, "Text Y Offset", "textYOffset", 0, 20, "%spx", 0)
  cTxt:Finish(); Append(cTxt, cTxt:GetHeight())

  return container
end