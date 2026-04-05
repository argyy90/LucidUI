-- LucidUI Modules/Resources.lua
-- Class resource bars: primary, secondary, and optional mana

local NS = LucidUINS
NS.Resources = NS.Resources or {}
local RES = NS.Resources
local resInitialized = false

-- ── Power type colors ───────────────────────────────────────────────────
local POWER_COLORS = {
  [Enum.PowerType.Mana]         = {0.00, 0.45, 1.00},
  [Enum.PowerType.Rage]         = {0.90, 0.15, 0.15},
  [Enum.PowerType.Focus]        = {1.00, 0.50, 0.25},
  [Enum.PowerType.Energy]       = {1.00, 0.85, 0.10},
  [Enum.PowerType.ComboPoints]  = {1.00, 0.60, 0.10},
  [Enum.PowerType.RunicPower]   = {0.00, 0.82, 1.00},
  [Enum.PowerType.SoulShards]   = {0.58, 0.51, 0.79},
  [Enum.PowerType.LunarPower]   = {0.30, 0.52, 0.90},
  [Enum.PowerType.HolyPower]    = {0.95, 0.90, 0.60},
  [Enum.PowerType.Maelstrom]    = {0.00, 0.50, 1.00},
  [Enum.PowerType.Chi]          = {0.71, 1.00, 0.92},
  [Enum.PowerType.Insanity]     = {0.40, 0.00, 0.80},
  [Enum.PowerType.ArcaneCharges]= {0.10, 0.10, 0.98},
  [Enum.PowerType.Fury]         = {0.79, 0.26, 0.99},
  [Enum.PowerType.Essence]      = {0.12, 0.75, 0.56},
}

-- Segmented power types: displayed as individual pips instead of a bar
local SEGMENTED_TYPES = {
  [Enum.PowerType.ComboPoints]  = true,
  [Enum.PowerType.SoulShards]   = true,
  [Enum.PowerType.HolyPower]    = true,
  [Enum.PowerType.Chi]          = true,
  [Enum.PowerType.ArcaneCharges]= true,
  [Enum.PowerType.Essence]      = true,
}

-- ── Spec → Resource mapping ─────────────────────────────────────────────
-- specID → {primary[, secondary]}
local SPEC_RESOURCE = {
  -- Warrior
  [71]  = {Enum.PowerType.Rage},                                    -- Arms
  [72]  = {Enum.PowerType.Rage},                                    -- Fury
  [73]  = {Enum.PowerType.Rage},                                    -- Protection
  -- Paladin
  [65]  = {Enum.PowerType.HolyPower},                               -- Holy
  [66]  = {Enum.PowerType.HolyPower},                               -- Protection
  [70]  = {Enum.PowerType.HolyPower},                               -- Retribution
  -- Hunter
  [253] = {Enum.PowerType.Focus},                                   -- Beast Mastery
  [254] = {Enum.PowerType.Focus},                                   -- Marksmanship
  [255] = {Enum.PowerType.Focus},                                   -- Survival
  -- Rogue
  [259] = {Enum.PowerType.Energy, Enum.PowerType.ComboPoints},      -- Assassination
  [260] = {Enum.PowerType.Energy, Enum.PowerType.ComboPoints},      -- Outlaw
  [261] = {Enum.PowerType.Energy, Enum.PowerType.ComboPoints},      -- Subtlety
  -- Priest
  [258] = {Enum.PowerType.Insanity},                                -- Shadow
  -- DK
  [250] = {Enum.PowerType.RunicPower},                              -- Blood
  [251] = {Enum.PowerType.RunicPower},                              -- Frost
  [252] = {Enum.PowerType.RunicPower},                              -- Unholy
  -- Shaman
  [262] = {Enum.PowerType.Maelstrom},                               -- Elemental
  -- Mage
  [62]  = {Enum.PowerType.ArcaneCharges},                           -- Arcane
  -- Warlock
  [265] = {Enum.PowerType.SoulShards},                              -- Affliction
  [266] = {Enum.PowerType.SoulShards},                              -- Demonology
  [267] = {Enum.PowerType.SoulShards},                              -- Destruction
  -- Monk
  [268] = {Enum.PowerType.Energy},                                  -- Brewmaster
  [269] = {Enum.PowerType.Energy, Enum.PowerType.Chi},              -- Windwalker
  -- Druid
  [102] = {Enum.PowerType.LunarPower},                              -- Balance
  [103] = {Enum.PowerType.Energy, Enum.PowerType.ComboPoints},      -- Feral
  [104] = {Enum.PowerType.Rage},                                    -- Guardian
  -- Demon Hunter
  [577] = {Enum.PowerType.Fury},                                    -- Havoc
  [581] = {Enum.PowerType.Fury},                                    -- Vengeance
  -- Evoker
  [1467] = {Enum.PowerType.Essence},                                -- Devastation
  [1468] = {Enum.PowerType.Essence},                                -- Preservation
  [1473] = {Enum.PowerType.Essence},                                -- Augmentation
}

-- Specs where mana is shown by default (healers + mana-only casters)
local MANA_SPECS = {
  [65]   = true,  -- Holy Paladin
  [256]  = true,  -- Discipline Priest
  [257]  = true,  -- Holy Priest
  [264]  = true,  -- Restoration Shaman
  [62]   = true,  -- Arcane Mage
  [63]   = true,  -- Fire Mage
  [64]   = true,  -- Frost Mage
  [105]  = true,  -- Restoration Druid
  [270]  = true,  -- Mistweaver Monk
  [1468] = true,  -- Preservation Evoker
}

-- ── Defaults ────────────────────────────────────────────────────────────
local DEFAULTS = {
  width = 350, height = 14, autoWidth = true,
  secHeight = 14,
  showMana = false,
  showText = true, showSecText = true,
  texture = "Flat", bgTexture = "Flat", font = "default", fontSize = 10,
  bgColor = {0.06, 0.06, 0.10, 0.85},
  pipSpacing = 1,
}

local Opt, OptSet = NS.MakeOpt("res_", DEFAULTS)

-- Check if user has explicitly set showMana (vs auto-detect)
local function GetShowMana()
  if LucidUIDB and LucidUIDB["res_showMana"] ~= nil then
    return LucidUIDB["res_showMana"]
  end
  -- Auto-detect from spec
  return MANA_SPECS[RES._specID] or false
end

-- ── State ───────────────────────────────────────────────────────────────
local mainBar, secBar, manaBar = nil, nil, nil
local pips, secPips = {}, {}
local primaryType, secondaryType = nil, nil
local primarySegmented, secondarySegmented = false, false
RES._specID = nil

-- ── Helper: create a resource bar frame ─────────────────────────────────
local function CreateBarFrame(name, parent)
  local f = CreateFrame("Frame", name, parent or UIParent, "BackdropTemplate")
  f:SetFrameStrata("MEDIUM"); f:SetClampedToScreen(true)

  -- Background
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints(); f.bg:SetTexture(NS.GetBarTexturePath(Opt("bgTexture") or "Flat"))
  local bgc = Opt("bgColor")
  f.bg:SetVertexColor(bgc[1], bgc[2], bgc[3], bgc[4] or 0.85)

  -- Border
  f:SetBackdrop({edgeFile=NS.TEX_WHITE, edgeSize=1})
  f:SetBackdropBorderColor(0, 0, 0, 1); f:SetBackdropColor(0, 0, 0, 0)

  -- Continuous bar fill
  f.bar = CreateFrame("StatusBar", nil, f)
  f.bar:SetPoint("TOPLEFT", 1, -1); f.bar:SetPoint("BOTTOMRIGHT", -1, 1)
  f.bar:SetMinMaxValues(0, 1); f.bar:SetValue(0)
  f.bar:SetStatusBarTexture(NS.GetBarTexturePath(Opt("texture")))

  -- Value text (on overlay frame above bar + pips)
  f._textOverlay = CreateFrame("Frame", nil, f)
  f._textOverlay:SetAllPoints()
  f._textOverlay:SetFrameLevel(f:GetFrameLevel() + 10)
  local fontPath = NS.GetFontPath(Opt("font"))
  f.text = f._textOverlay:CreateFontString(nil, "OVERLAY")
  f.text:SetFont(fontPath, Opt("fontSize"), "OUTLINE")
  f.text:SetPoint("CENTER")

  f:Hide()
  return f
end

-- ── Create main (primary) bar ───────────────────────────────────────────
local function CreateMainBar()
  if mainBar then return mainBar end

  local f = CreateBarFrame("LucidUIResources")
  f:SetMovable(true); f:EnableMouse(false)
  f:SetSize(Opt("width"), Opt("height"))

  local pos = Opt("pos")
  if pos and pos.p then
    f:SetPoint(pos.p, UIParent, pos.p, pos.x, pos.y)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, -175)
    f._needsAnchor = true
  end

  mainBar = f
  return f
end

-- ── Create secondary bar (anchored above main bar) ──────────────────────
local function CreateSecBar()
  if secBar then return secBar end
  if not mainBar then CreateMainBar() end

  local f = CreateBarFrame("LucidUIResourcesSec")
  f:SetSize(Opt("width"), Opt("secHeight"))
  f:SetPoint("BOTTOM", mainBar, "TOP", 0, 1)

  secBar = f
  return f
end

-- ── Create mana bar (anchored below main bar) ───────────────────────────
local function CreateManaBar()
  if manaBar then return manaBar end
  if not mainBar then CreateMainBar() end

  local f = CreateBarFrame("LucidUIResourcesMana")
  f:SetSize(Opt("width"), Opt("height"))

  -- ManaBar anchors above Essential cooldowns via the anchor chain
  if not NS.AnchorToChain(f, "ManaBar") then
    f:SetPoint("TOP", mainBar, "BOTTOM", 0, -1)
  end

  -- Set mana color
  local mc = POWER_COLORS[Enum.PowerType.Mana] or {0, 0.45, 1}
  f.bar:SetStatusBarColor(mc[1], mc[2], mc[3])

  manaBar = f
  return f
end

-- ── Create/update pip frames for a bar ──────────────────────────────────
local function UpdatePipsFor(bar, pipTable, max, powerType)
  if not bar then return pipTable end
  local w = bar:GetWidth()
  local h = bar:GetHeight()
  local spacing = Opt("pipSpacing") or 2
  local pipW = max > 0 and ((w - 2 - (max - 1) * spacing) / max) or w

  -- Hide bar fill in segmented mode
  bar.bar:Hide()

  local color = POWER_COLORS[powerType] or {1, 1, 1}

  for i = 1, max do
    if not pipTable[i] then
      local p = CreateFrame("StatusBar", nil, bar)
      p:SetMinMaxValues(0, 1); p:SetValue(0)
      p:SetStatusBarTexture(NS.GetBarTexturePath(Opt("texture")))
      p.bg = p:CreateTexture(nil, "BACKGROUND")
      p.bg:SetAllPoints(); p.bg:SetTexture(NS.GetBarTexturePath(Opt("bgTexture") or "Flat"))
      local bgc = Opt("bgColor")
      p.bg:SetVertexColor(bgc[1], bgc[2], bgc[3], bgc[4] or 0.85)
      pipTable[i] = p
    end
    local p = pipTable[i]
    p:SetSize(pipW, h - 2)
    p:ClearAllPoints()
    p:SetPoint("LEFT", bar, "LEFT", 1 + (i - 1) * (pipW + spacing), 0)
    p:SetStatusBarColor(color[1], color[2], color[3])
    p:Show()
  end
  for i = max + 1, #pipTable do pipTable[i]:Hide() end
  return pipTable
end

-- ── Refresh visual options ──────────────────────────────────────────────
local function GetEffectiveWidth()
  if Opt("autoWidth") then
    local cdw = NS.GetCooldownsWidth and NS.GetCooldownsWidth()
    if cdw then return cdw end
  end
  return Opt("width")
end

local function ApplyBarStyle(bar, h)
  if not bar then return end
  local w = GetEffectiveWidth()
  bar:SetSize(w, h)
  bar.bar:SetStatusBarTexture(NS.GetBarTexturePath(Opt("texture")))
  bar.bg:SetTexture(NS.GetBarTexturePath(Opt("bgTexture") or "Flat"))
  local bgc = Opt("bgColor")
  bar.bg:SetVertexColor(bgc[1], bgc[2], bgc[3], bgc[4] or 0.85)
  local fontPath = NS.GetFontPath(Opt("font"))
  bar.text:SetFont(fontPath, Opt("fontSize"), "OUTLINE")
end

local function ApplyPipStyle(pipTable, h)
  for _, p in ipairs(pipTable) do
    p:SetStatusBarTexture(NS.GetBarTexturePath(Opt("texture")))
    p.bg:SetTexture(NS.GetBarTexturePath(Opt("bgTexture") or "Flat"))
    local bgc = Opt("bgColor")
    p.bg:SetVertexColor(bgc[1], bgc[2], bgc[3], bgc[4] or 0.85)
    p:SetHeight(h - 2)
  end
end

local function ApplyStyle()
  if not mainBar then return end
  ApplyBarStyle(mainBar, Opt("height"))
  ApplyPipStyle(pips, Opt("height"))

  if secBar then
    ApplyBarStyle(secBar, Opt("secHeight"))
    ApplyPipStyle(secPips, Opt("secHeight"))
    secBar:SetPoint("BOTTOM", mainBar, "TOP", 0, 1)
  end

  if manaBar then
    ApplyBarStyle(manaBar, Opt("height"))
    local mc = POWER_COLORS[Enum.PowerType.Mana] or {0, 0.45, 1}
    manaBar.bar:SetStatusBarColor(mc[1], mc[2], mc[3])
  end

  -- Match Vigor/Skyriding bar width to resource bar width
  local vigorContainer = _G["UIWidgetPowerBarContainerFrame"]
  if vigorContainer then
    local resWidth = GetEffectiveWidth()
    pcall(function()
      for _, widget in pairs(vigorContainer.widgetFrames or {}) do
        if widget and widget.Bar then
          widget.Bar:SetWidth(resWidth)
        end
        if widget and widget.SetWidth then
          widget:SetWidth(resWidth + 8)
        end
      end
    end)
  end
end

-- ── Update a single bar (continuous or segmented) ───────────────────────
local function UpdateBar(bar, pipTable, powerType, isSegm, showText)
  if not bar or not bar:IsShown() then return end
  local color = POWER_COLORS[powerType] or {1, 1, 1}

  if isSegm then
    local power, maxPower, rawPower = 0, 1, 0
    pcall(function()
      power = UnitPower("player", powerType)
      maxPower = UnitPowerMax("player", powerType)
      rawPower = UnitPower("player", powerType, true) -- partial values (×10)
    end)
    local ok, pNum = pcall(function() return power + 0 end)
    if not ok then pNum = 0 end
    local ok2, mNum = pcall(function() return maxPower + 0 end)
    if not ok2 then mNum = 1 end
    local ok3, rawNum = pcall(function() return rawPower + 0 end)
    if not ok3 then rawNum = pNum * 10 end

    -- Detect partial support: raw differs from whole × 10 scale
    local hasPartial = (rawNum ~= pNum) or (rawNum > 0 and rawNum ~= pNum * 10) or (mNum > 0 and rawNum % 10 ~= 0)
    -- Fallback: if raw == whole, no partial (ComboPoints, Chi, etc.)
    if rawNum == pNum then hasPartial = false; rawNum = pNum * 10 end

    UpdatePipsFor(bar, pipTable, mNum, powerType)
    for i = 1, mNum do
      if pipTable[i] then
        if hasPartial then
          -- Partial fill: each pip = 10 units of raw power
          local pipRaw = rawNum - (i - 1) * 10
          local fill = math.max(0, math.min(1, pipRaw / 10))
          pipTable[i]:SetValue(fill)
          pipTable[i]:SetAlpha(fill >= 1 and 1 or (fill > 0 and 0.5 or 0.25))
        else
          pipTable[i]:SetValue(i <= pNum and 1 or 0)
          pipTable[i]:SetAlpha(i <= pNum and 1 or 0.25)
        end
      end
    end
    if showText then
      bar.text:SetText(tostring(pNum))
    else bar.text:SetText("") end
  else
    bar.bar:Show()
    -- Hide pips in continuous mode
    for _, p in ipairs(pipTable) do p:Hide() end
    bar.bar:SetStatusBarColor(color[1], color[2], color[3])
    pcall(function()
      bar.bar:SetMinMaxValues(0, UnitPowerMax("player", powerType))
      bar.bar:SetValue(UnitPower("player", powerType))
    end)
    if showText then
      pcall(function()
        bar.text:SetFormattedText("%d", UnitPower("player", powerType))
      end)
    else bar.text:SetText("") end
  end
end

-- ── Update all bars ─────────────────────────────────────────────────────
local function UpdatePower()
  if not mainBar or not mainBar:IsShown() then return end
  if RES._unlocked then return end -- don't override unlock preview

  -- Primary bar
  if primaryType then
    UpdateBar(mainBar, pips, primaryType, primarySegmented, Opt("showText"))
  end

  -- Secondary bar
  if secBar and secondaryType then
    if secBar:IsShown() then
      UpdateBar(secBar, secPips, secondaryType, secondarySegmented, Opt("showSecText"))
    end
  elseif secBar and not secondaryType then
    secBar:Hide()
  end

  -- Mana bar
  if manaBar and GetShowMana() and primaryType ~= Enum.PowerType.Mana then
    local wasHidden = not manaBar:IsShown()
    manaBar:Show()
    manaBar:SetSize(Opt("width"), Opt("height"))
    pcall(function()
      manaBar.bar:SetMinMaxValues(0, UnitPowerMax("player", Enum.PowerType.Mana))
      manaBar.bar:SetValue(UnitPower("player", Enum.PowerType.Mana))
    end)
    if Opt("showText") then
      pcall(function()
        manaBar.text:SetFormattedText("%d", UnitPower("player", Enum.PowerType.Mana))
      end)
    else manaBar.text:SetText("") end
    if wasHidden then NS.RefreshAnchorChain() end
  elseif manaBar then
    local wasShown = manaBar:IsShown()
    manaBar:Hide()
    if wasShown then NS.RefreshAnchorChain() end
  end
end

-- ── Detect resources from spec ──────────────────────────────────────────
local function DetectResources()
  local specIndex = GetSpecialization()
  if not specIndex then
    primaryType = UnitPowerType("player")
    primarySegmented = SEGMENTED_TYPES[primaryType] or false
    secondaryType = nil
    secondarySegmented = false
    return
  end

  local specID = GetSpecializationInfo(specIndex)
  RES._specID = specID

  local entry = specID and SPEC_RESOURCE[specID]
  if entry then
    primaryType = entry[1]
    primarySegmented = SEGMENTED_TYPES[primaryType] or false
    secondaryType = entry[2] or nil
    secondarySegmented = secondaryType and (SEGMENTED_TYPES[secondaryType] or false) or false
  else
    -- Unknown spec (new expansion spec or mana-only healer/caster)
    -- Try to detect primary power type from the unit directly
    local unitPower = UnitPowerType("player")
    if unitPower and unitPower ~= Enum.PowerType.Mana then
      primaryType = unitPower
      primarySegmented = SEGMENTED_TYPES[primaryType] or false
    else
      primaryType = nil
      primarySegmented = false
    end
    secondaryType = nil
    secondarySegmented = false
  end
end

-- ── Event handling ──────────────────────────────────────────────────────
local evFrame = CreateFrame("Frame")

local function OnEvent(_, event, arg1)
  if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
    if event == "PLAYER_ENTERING_WORLD" then
      if arg1 or resInitialized then return end -- skip initial login, already init
    end
    if resInitialized then return end
    if not NS.IsCDMEnabled() then return end
    C_Timer.After(0.8, function()
      if resInitialized then return end
      resInitialized = true
      NS.SafeCall(function()
        DetectResources()
        CreateMainBar(); CreateSecBar(); CreateManaBar()
        ApplyStyle()

        -- Show/hide bars based on detected resources
        if primaryType then
          mainBar:Show()
        end
        if secondaryType then
          secBar:Show()
        else
          secBar:Hide()
        end

        UpdatePower()
        RES.Enable()
        -- Hook Vigor/Skyriding bar to match our width when created
        if _G.UIWidgetTemplateStatusBarMixin and _G.UIWidgetTemplateStatusBarMixin.Setup then
          hooksecurefunc(_G.UIWidgetTemplateStatusBarMixin, "Setup", function()
            C_Timer.After(0, function() ApplyStyle() end)
          end)
        end
      end, "Resources")
    end)
    return
  end
  if event == "PLAYER_LOGOUT" then
    if mainBar and Opt("pos") then
      local left, top = mainBar:GetLeft(), mainBar:GetTop()
      if left then OptSet("pos", {p="TOPLEFT", x=left, y=top - GetScreenHeight()}) end
    end
    return
  end
  if event == "ACTIVE_TALENT_GROUP_CHANGED" or event == "PLAYER_SPECIALIZATION_CHANGED" then
    DetectResources()
    if mainBar then
      if primaryType then mainBar:Show() else mainBar:Hide() end
    end
    if secBar then
      if secondaryType then secBar:Show() else secBar:Hide() end
    end
    ApplyStyle(); UpdatePower()
    NS.RefreshAnchorChain()
    return
  end
  if event == "UNIT_POWER_FREQUENT" or event == "UNIT_MAXPOWER" then
    if arg1 == "player" then UpdatePower() end
    return
  end
  if event == "UNIT_POWER_POINT_CHARGE" then
    if arg1 == "player" then UpdatePower() end
    return
  end
end

evFrame:RegisterEvent("PLAYER_LOGIN")
evFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
evFrame:RegisterEvent("PLAYER_LOGOUT")
evFrame:SetScript("OnEvent", OnEvent)

-- ── Enable / Disable ────────────────────────────────────────────────────
function RES.Enable()
  evFrame:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
  evFrame:RegisterUnitEvent("UNIT_MAXPOWER", "player")
  evFrame:RegisterUnitEvent("UNIT_POWER_POINT_CHARGE", "player")
  evFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
  evFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
  CreateMainBar(); CreateSecBar(); CreateManaBar()
  DetectResources(); ApplyStyle()
  RES._mainBar = mainBar
  RES._secBar = secBar
  RES._manaBar = manaBar
  if primaryType then mainBar:Show() else mainBar:Hide() end
  if secondaryType then secBar:Show() else secBar:Hide() end
  UpdatePower()
  if mainBar and mainBar._needsAnchor then
    mainBar._needsAnchor = nil
    NS.AnchorToChain(mainBar, "Resources")
  end
end

function RES.Disable()
  evFrame:UnregisterEvent("UNIT_POWER_FREQUENT")
  evFrame:UnregisterEvent("UNIT_MAXPOWER")
  evFrame:UnregisterEvent("UNIT_POWER_POINT_CHARGE")
  evFrame:UnregisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
  evFrame:UnregisterEvent("PLAYER_SPECIALIZATION_CHANGED")
  if mainBar then mainBar:Hide() end
  if secBar then secBar:Hide() end
  if manaBar then manaBar:Hide() end
end

function RES.Refresh()
  if mainBar then ApplyStyle(); UpdatePower() end
end

-- ── Return topmost visible resource bar (for anchor chain) ──────────────
function RES.GetTopBar()
  if secBar and secBar:IsShown() then return secBar end
  if mainBar and mainBar:IsShown() then return mainBar end
  return mainBar
end

-- ── Settings Tab ────────────────────────────────────────────────────────
function RES.SetupSettings(parent)
  local container = CreateFrame("Frame", nil, parent)
  local MakeCard = NS._SMakeCard
  local MakePage = NS._SMakePage
  local R = NS._SR
  local SBD = NS.BACKDROP
  local sc, Append = MakePage(container)

  local function Slider(card, label, key, mn, mx, fmt, default, scale)
    local s; s = NS.ChatGetSlider(card.inner, label, mn, mx, fmt, function()
      OptSet(key, scale and s:GetValue() / scale or s:GetValue()); RES.Refresh()
    end); R(card, s, 40)
    s:SetValue(scale and (Opt(key) or default) * scale or (Opt(key) or default))
  end
  local function Dropdown(card, label, labels, values, key, default, onChange, maxH)
    local dd = NS.ChatGetDropdown(card.inner, label,
      function(v) return (Opt(key) or default) == v end,
      onChange or function(v) OptSet(key, v); RES.Refresh() end)
    dd:Init(labels, values, maxH); R(card, dd, 46)
  end
  local function TogglePair(card, l1, k1, l2, k2)
    local row = CreateFrame("Frame", nil, card.inner); row:SetHeight(26)
    local cb1 = NS.ChatGetCheckbox(row, l1, 26, function(s) OptSet(k1, s); RES.Refresh() end)
    cb1:ClearAllPoints(); cb1:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    cb1:SetPoint("BOTTOMRIGHT", row, "BOTTOM", -2, 0); cb1:SetValue(Opt(k1) ~= false)
    local cb2 = NS.ChatGetCheckbox(row, l2, 26, function(s) OptSet(k2, s); RES.Refresh() end)
    cb2:ClearAllPoints(); cb2:SetPoint("TOPLEFT", row, "TOP", 2, 0)
    cb2:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0); cb2:SetValue(Opt(k2) ~= false)
    R(card, row, 26)
  end
  local function DropdownPair(card, l1, labs1, vals1, k1, def1, l2, labs2, vals2, k2, def2, maxH)
    local row = CreateFrame("Frame", nil, card.inner); row:SetHeight(46)
    local lh = CreateFrame("Frame", nil, row)
    lh:SetPoint("TOPLEFT", 0, 0); lh:SetPoint("BOTTOMRIGHT", row, "BOTTOM", -2, 0)
    local rh = CreateFrame("Frame", nil, row)
    rh:SetPoint("TOPLEFT", row, "TOP", 2, 0); rh:SetPoint("BOTTOMRIGHT", 0, 0)
    local dd1 = NS.ChatGetDropdown(lh, l1,
      function(v) return (Opt(k1) or def1) == v end,
      function(v) OptSet(k1, v); RES.Refresh() end)
    dd1:Init(labs1, vals1, maxH); dd1:SetParent(lh); dd1:ClearAllPoints(); dd1:SetAllPoints(lh)
    local dd2 = NS.ChatGetDropdown(rh, l2,
      function(v) return (Opt(k2) or def2) == v end,
      function(v) OptSet(k2, v); RES.Refresh() end)
    dd2:Init(labs2, vals2, maxH); dd2:SetParent(rh); dd2:ClearAllPoints(); dd2:SetAllPoints(rh)
    R(card, row, 46)
  end

  -- ── General card ──
  local cGen = MakeCard(sc, "General")
  local enRow = CreateFrame("Frame", nil, cGen.inner); enRow:SetHeight(26)
  -- Reset position button
  local resetBtn = CreateFrame("Button", nil, enRow, "BackdropTemplate"); resetBtn:SetSize(50, 20); resetBtn:SetPoint("RIGHT", -8, 0)
  resetBtn:SetBackdrop(SBD); resetBtn:SetBackdropColor(0.04, 0.04, 0.07, 1); resetBtn:SetBackdropBorderColor(0.12, 0.12, 0.20, 1)
  local resetFS = resetBtn:CreateFontString(nil, "OVERLAY"); resetFS:SetFont("Fonts/FRIZQT__.TTF", 9, ""); resetFS:SetPoint("CENTER"); resetFS:SetTextColor(0.65, 0.65, 0.75); resetFS:SetText("Reset")
  resetBtn:SetScript("OnClick", function()
    OptSet("pos", nil)
    if mainBar then NS.AnchorToChain(mainBar, "Resources") end
  end)
  resetBtn:SetScript("OnEnter", function() local r,g,b = NS.ChatGetAccentRGB(); resetBtn:SetBackdropBorderColor(r, g, b, 0.8) end)
  resetBtn:SetScript("OnLeave", function() resetBtn:SetBackdropBorderColor(0.12, 0.12, 0.20, 1) end)
  -- Unlock button
  local lockBtn = CreateFrame("Button", nil, enRow, "BackdropTemplate"); lockBtn:SetSize(70, 20); lockBtn:SetPoint("RIGHT", resetBtn, "LEFT", -4, 0)
  lockBtn:SetBackdrop(SBD); lockBtn:SetBackdropColor(0.04, 0.04, 0.07, 1); lockBtn:SetBackdropBorderColor(0.12, 0.12, 0.20, 1)
  local lockFS = lockBtn:CreateFontString(nil, "OVERLAY"); lockFS:SetFont("Fonts/FRIZQT__.TTF", 9, ""); lockFS:SetPoint("CENTER"); lockFS:SetTextColor(0.65, 0.65, 0.75); lockFS:SetText("Unlock")
  local unlocked = false
  lockBtn:SetScript("OnClick", function()
    unlocked = not unlocked
    lockFS:SetText(unlocked and "Lock" or "Unlock")
    local r, g, b = NS.ChatGetAccentRGB()
    if unlocked then lockBtn:SetBackdropBorderColor(r, g, b, 0.8) else lockBtn:SetBackdropBorderColor(0.12, 0.12, 0.20, 1) end
    CreateMainBar(); CreateSecBar(); ApplyStyle()
    if unlocked then
      RES._unlocked = true
      mainBar:Show(); mainBar:SetAlpha(1)
      mainBar.bar:Show(); mainBar.bar:SetValue(0.6)
      mainBar.text:SetText("Primary Resource")
      mainBar:EnableMouse(true); mainBar:RegisterForDrag("LeftButton")
      mainBar:SetScript("OnDragStart", function(s) s:StartMoving() end)
      mainBar:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        local left, top = s:GetLeft(), s:GetTop()
        if left then OptSet("pos", {p="TOPLEFT", x=left, y=top - GetScreenHeight()}) end
        NS.UpdateMoverPopup()
      end)
      if secBar then
        secBar:Show(); secBar:SetAlpha(1)
        secBar.bar:Show(); secBar.bar:SetValue(0.7)
        secBar.text:SetText("Secondary Resource")
      end
      NS.ShowMoverPopup(mainBar, "Resources", function(f)
        local left, top = f:GetLeft(), f:GetTop()
        if left then OptSet("pos", {p="TOPLEFT", x=left, y=top - GetScreenHeight()}) end
      end, function()
        OptSet("pos", nil)
        if mainBar then NS.AnchorToChain(mainBar, "Resources") end
      end)
    else
      RES._unlocked = false
      mainBar:EnableMouse(false); mainBar:RegisterForDrag()
      mainBar:SetScript("OnDragStart", nil); mainBar:SetScript("OnDragStop", nil)
      NS.HideMoverPopup()
      DetectResources()
      if primaryType then mainBar:Show() else mainBar:Hide() end
      if secondaryType and secBar then secBar:Show() else secBar:Hide() end
      UpdatePower()
    end
  end)
  lockBtn:SetScript("OnEnter", function() local r,g,b = NS.ChatGetAccentRGB(); lockBtn:SetBackdropBorderColor(r, g, b, 0.8) end)
  lockBtn:SetScript("OnLeave", function() if not unlocked then lockBtn:SetBackdropBorderColor(0.12, 0.12, 0.20, 1) end end)
  R(cGen, enRow, 26)

  -- Auto Width toggle
  local autoWCb = NS.ChatGetCheckbox(cGen.inner, "Auto Width (match Cooldowns)", 26, function(s)
    OptSet("autoWidth", s); RES.Refresh()
  end, "Automatically match width to Essential Cooldowns")
  R(cGen, autoWCb, 26); autoWCb:SetValue(Opt("autoWidth") ~= false)

  -- Mana toggle (auto-detected default)
  local manaCb = NS.ChatGetCheckbox(cGen.inner, "Show Mana Bar", 26, function(s)
    OptSet("showMana", s)
    RES.Refresh(); NS.RefreshAnchorChain()
  end, "Show a mana bar (auto-enabled for healer/caster specs)")
  R(cGen, manaCb, 26); manaCb:SetValue(GetShowMana())

  cGen:Finish(); Append(cGen, cGen:GetHeight()); Append(NS._SSep(sc), 9)

  -- ── Size card ──
  local cSize = MakeCard(sc, "Size")
  Slider(cSize, "Width", "width", 80, 400, "%spx", 220)
  Slider(cSize, "Primary Height", "height", 6, 40, "%spx", 14)
  Slider(cSize, "Secondary Height", "secHeight", 6, 40, "%spx", 14)
  Slider(cSize, "Pip Spacing", "pipSpacing", 0, 8, "%spx", 2)
  cSize:Finish(); Append(cSize, cSize:GetHeight()); Append(NS._SSep(sc), 9)

  -- ── Appearance card ──
  local cApp = MakeCard(sc, "Appearance")
  local barTexNames = {}
  local rawBars = NS.GetLSMStatusBars and NS.GetLSMStatusBars() or {}
  for _, b in ipairs(rawBars) do barTexNames[#barTexNames+1] = b.label end
  if #barTexNames == 0 then barTexNames = {"Flat"} end
  DropdownPair(cApp, "Bar Texture", barTexNames, barTexNames, "texture", "Flat",
    "Background", barTexNames, barTexNames, "bgTexture", "Flat", 200)
  cApp:Finish(); Append(cApp, cApp:GetHeight()); Append(NS._SSep(sc), 9)

  -- ── Text card ──
  local cTxt = MakeCard(sc, "Text")
  TogglePair(cTxt, "Primary Value", "showText", "Secondary Value", "showSecText")
  local fontNames, fontValues = {"Default"}, {"default"}
  for _, ft in ipairs(NS.GetLSMFonts()) do fontNames[#fontNames+1] = ft.label; fontValues[#fontValues+1] = ft.label end
  Dropdown(cTxt, "Font", fontNames, fontValues, "font", "default", nil, 200)
  Slider(cTxt, "Font Size", "fontSize", 6, 20, "%spx", 10)
  cTxt:Finish(); Append(cTxt, cTxt:GetHeight())

  return container
end