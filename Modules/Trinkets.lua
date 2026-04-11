-- LucidUI Modules/Trinkets.lua
-- Two separate bars: Trinkets (equipment slots) and Racials (custom spells/items)
-- Anchors to player unitframe with cooldown display

local NS = LucidUINS
local L  = LucidUIL
NS.Trinkets = NS.Trinkets or {}
local TR = NS.Trinkets

-- ── Constants ───────────────────────────────────────────────────────────
local TRINKET_SLOT_1 = 13
local TRINKET_SLOT_2 = 14
local CD_MIN = 1.5

-- Secret-safe SetCooldown: 12.0.1+ restricts CooldownFrame:SetCooldown with secret values.
-- Prefer SetCooldownFromDurationObject for spell-based CDs when a spellID is known.
local function SafeSetCooldown(cd, start, duration, spellID)
  if spellID and C_Spell and C_Spell.GetSpellCooldownDuration then
    local ok, durObj = pcall(C_Spell.GetSpellCooldownDuration, spellID)
    if ok and durObj then cd:SetCooldownFromDurationObject(durObj); return end
  end
  pcall(cd.SetCooldown, cd, start, duration)
end

-- ── Default items for Racials bar ───────────────────────────────────────
local DEFAULT_ITEMS = {}

-- ── Defaults ────────────────────────────────────────────────────────────
local DEFAULTS = {
  enabled = true,
  -- Trinkets bar
  trkWidth = 36, trkHeight = 36, trkSpacing = 2,
  trkAnchor = "TOPLEFT", trkOffX = 0, trkOffY = 0,
  trkShowPassive = false, trkGrow = "RIGHT",
  trkCdFontSize = 12,
  -- Racials bar
  racWidth = 36, racHeight = 36, racSpacing = 2,
  racAnchor = "BOTTOMLEFT", racOffX = 0, racOffY = 0,
  racGrow = "RIGHT", racCdFontSize = 12, racStackFontSize = 11,
  racShowZeroStacks = true,
  -- Shared
  showCooldownText = true,
}

local Opt, OptSet = NS.MakeOpt("tr_", DEFAULTS)

-- ── State ───────────────────────────────────────────────────────────────
local trkContainer, racContainer = nil, nil
local trkFrames, racFrames = {}, {}
local racEntries = {}
local initialized = false

-- ── Resolve player unitframe ────────────────────────────────────────────
-- Matches the candidate list used by Ayije CDM's TrackerUtils.lua.
local PLAYER_FRAME_CANDIDATES = {
  "ElvUF_Player", "SUFUnitplayer", "UUF_Player",
  "EllesmereUIUnitFrames_Player", "MSUF_player", "EQOLUFPlayerFrame", "oUF_Player",
}

local function GetPlayerFrame()
  for _, name in ipairs(PLAYER_FRAME_CANDIDATES) do
    local f = _G[name]
    if f and f.IsShown and f:IsShown() then return f end
  end
  -- Fall back to Blizzard's default frame
  local blizz = _G["PlayerFrame"]
  if blizz and blizz.IsShown and blizz:IsShown() then return blizz end
  return blizz
end

-- ── Create icon frame ───────────────────────────────────────────────────
local function CreateIcon(parent)
  local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  f:SetBackdrop({edgeFile=NS.TEX_WHITE, edgeSize=1})
  f:SetBackdropBorderColor(0, 0, 0, 1)
  f:SetBackdropColor(0, 0, 0, 0)

  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetPoint("TOPLEFT", 1, -1); f.icon:SetPoint("BOTTOMRIGHT", -1, 1)
  f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
  f.cd:SetPoint("TOPLEFT", 1, -1); f.cd:SetPoint("BOTTOMRIGHT", -1, 1)
  f.cd:SetDrawEdge(false)

  f.count = f:CreateFontString(nil, "OVERLAY")
  f.count:SetFont(NS.FONT, 11, "THICKOUTLINE")
  f.count:SetPoint("BOTTOMRIGHT", -1, 1)
  f.count:SetTextColor(1, 1, 1)

  f:Hide()
  return f
end

-- ── Create a bar container ──────────────────────────────────────────────
local function CreateBar(name)
  local f = CreateFrame("Frame", name, UIParent)
  f:SetFrameStrata("MEDIUM"); f:SetFrameLevel(15)
  f:SetClampedToScreen(true); f:SetSize(80, 40)
  if f.SetPreventSecretValues then f:SetPreventSecretValues(true) end
  return f
end

-- ── Anchor a bar to player frame ────────────────────────────────────────
-- Anchor maps: bar point → player frame point (TOP = above frame, BOTTOM = below)
local ANCHOR_MAP = {
  TOPLEFT     = {bar = "BOTTOMLEFT",  pf = "TOPLEFT"},
  TOPRIGHT    = {bar = "BOTTOMRIGHT", pf = "TOPRIGHT"},
  BOTTOMLEFT  = {bar = "TOPLEFT",     pf = "BOTTOMLEFT"},
  BOTTOMRIGHT = {bar = "TOPRIGHT",    pf = "BOTTOMRIGHT"},
}

local function AnchorBar(bar, posKey, anchorKey, offXKey, offYKey)
  if not bar then return end
  local pos = Opt(posKey)
  if pos and pos.p then
    bar:ClearAllPoints()
    bar:SetPoint(pos.p, UIParent, pos.p, pos.x, pos.y)
    return
  end
  local pf = GetPlayerFrame()
  if not pf then bar:SetPoint("CENTER"); return end
  bar:ClearAllPoints()
  local anchor = Opt(anchorKey) or "BOTTOMLEFT"
  local map = ANCHOR_MAP[anchor]
  if map then
    bar:SetPoint(map.bar, pf, map.pf, Opt(offXKey), Opt(offYKey))
  else
    bar:SetPoint(anchor, pf, anchor, Opt(offXKey), Opt(offYKey))
  end
end

-- ── Update trinket icon ─────────────────────────────────────────────────
local function UpdateTrinket(frame, slotID)
  if not frame then return end
  local w, h = Opt("trkWidth"), Opt("trkHeight")
  frame:SetSize(w, h)

  local itemID = GetInventoryItemID("player", slotID)
  if not itemID then frame:Hide(); return end
  -- Only show usable (on-use) trinkets unless showPassive is on
  if not Opt("trkShowPassive") then
    local spellName = C_Item.GetItemSpell(itemID)
    if not spellName then frame:Hide(); return end
  end

  pcall(function()
    local tex = GetInventoryItemTexture("player", slotID)
    frame.icon:SetTexture(tex or 134400)
  end)

  pcall(function()
    local start, duration, enable = GetInventoryItemCooldown("player", slotID)
    if start and duration and duration > CD_MIN and enable == 1 then
      SafeSetCooldown(frame.cd, start, duration)
      frame.icon:SetDesaturated(true)
    else
      frame.cd:Clear()
      frame.icon:SetDesaturated(false)
    end
  end)

  frame.cd:SetHideCountdownNumbers(not Opt("showCooldownText"))
  -- Apply CD font size
  local cdFs = Opt("trkCdFontSize")
  for _, region in ipairs({frame.cd:GetRegions()}) do
    if region:IsObjectType("FontString") then region:SetFont(NS.FONT, cdFs, "OUTLINE") end
  end
  frame.count:SetText("")
  frame:Show()
end

-- ── Update racial/item icon ─────────────────────────────────────────────
local function UpdateRacialIcon(frame, entry)
  if not frame or not entry then frame:Hide(); return end
  local w, h = Opt("racWidth"), Opt("racHeight")
  frame:SetSize(w, h)

  local id = entry.spellID or entry.itemID
  if not id then frame:Hide(); return end

  -- Determine if item or spell and get icon
  local isItem = entry.isItem
  local tex
  if isItem then
    pcall(function() tex = C_Item.GetItemIconByID(id) end)
  else
    pcall(function() tex = C_Spell.GetSpellTexture(id) end)
  end
  if not tex then frame:Hide(); return end
  frame.icon:SetTexture(tex)

  -- Cooldown
  if isItem then
    local cdSet = false
    local spellToCheck = entry.itemSpellID
    -- If no spell ID stored, try to get it from the item
    if not spellToCheck then
      pcall(function() local _, sID = C_Item.GetItemSpell(id); spellToCheck = sID end)
    end
    -- 1) Try C_Container.GetItemCooldown
    pcall(function()
      local start, dur = C_Container.GetItemCooldown(id)
      if start and dur and dur > CD_MIN then
        SafeSetCooldown(frame.cd, start, dur); frame.icon:SetDesaturated(true); cdSet = true
      end
    end)
    -- 2) Try C_Spell.GetSpellCooldownDuration (returns duration object)
    if not cdSet and spellToCheck then
      pcall(function()
        local durObj = C_Spell.GetSpellCooldownDuration(spellToCheck)
        if durObj then
          frame.cd:SetCooldownFromDurationObject(durObj)
          -- Check if actually on CD
          local cdInfo = C_Spell.GetSpellCooldown(spellToCheck)
          if cdInfo and cdInfo.duration and cdInfo.duration > CD_MIN and not cdInfo.isOnGCD then
            frame.icon:SetDesaturated(true); cdSet = true
          end
        end
      end)
    end
    -- 3) Try spell cooldown via item's spell
    if not cdSet and spellToCheck then
      pcall(function()
        local cdInfo = C_Spell.GetSpellCooldown(spellToCheck)
        if cdInfo and cdInfo.duration and cdInfo.duration > CD_MIN then
          SafeSetCooldown(frame.cd, cdInfo.startTime, cdInfo.duration, spellToCheck); frame.icon:SetDesaturated(true); cdSet = true
        end
      end)
    end
    if not cdSet then frame.cd:Clear(); frame.icon:SetDesaturated(false) end
  else
    -- Spell cooldown
    pcall(function()
      local cdInfo = C_Spell.GetSpellCooldown(id)
      if cdInfo and cdInfo.duration and cdInfo.duration > CD_MIN then
        SafeSetCooldown(frame.cd, cdInfo.startTime, cdInfo.duration, id)
        frame.icon:SetDesaturated(true)
      else frame.cd:Clear(); frame.icon:SetDesaturated(false) end
    end)
  end

  -- Count / charges
  if isItem then
    local count = 0
    pcall(function() count = C_Item.GetItemCount(id, false, true) end)
    frame.count:SetText(count > 0 and count or "0")
    if count == 0 then
      if not Opt("racShowZeroStacks") then frame:Hide(); return end
      frame.icon:SetDesaturated(true)
      frame.cd:Clear()
      frame.count:SetTextColor(1, 0.3, 0.3)
    else
      frame.count:SetTextColor(1, 1, 1)
    end
  else
    local charges
    pcall(function() charges = C_Spell.GetSpellCharges(id) end)
    if charges and charges.maxCharges > 1 then
      frame.count:SetText(charges.currentCharges)
    else frame.count:SetText("") end
  end

  frame.cd:SetHideCountdownNumbers(not Opt("showCooldownText"))
  -- Apply CD + stack font sizes
  local cdFs = Opt("racCdFontSize")
  for _, region in ipairs({frame.cd:GetRegions()}) do
    if region:IsObjectType("FontString") then region:SetFont(NS.FONT, cdFs, "OUTLINE") end
  end
  frame.count:SetFont(NS.FONT, Opt("racStackFontSize") or 11, "THICKOUTLINE")
  frame:Show()
end

-- ── Build racials entry list ────────────────────────────────────────────
local function ResolveID(id)
  -- Try as item first (C_Item.GetItemIconByID returns non-nil for valid items)
  local isItem = false
  pcall(function()
    local tex = C_Item.GetItemIconByID(id)
    if tex then isItem = true end
  end)
  if isItem then
    -- Find the item's spell for cooldown tracking
    local itemSpellID
    pcall(function() local _, sID = C_Item.GetItemSpell(id); if sID then itemSpellID = sID end end)
    return {isItem = true, spellID = id, itemSpellID = itemSpellID}
  end
  -- Otherwise treat as spell
  return {isItem = false, spellID = id}
end

local function BuildRacialEntries()
  wipe(racEntries)
  for _, item in ipairs(DEFAULT_ITEMS) do
    racEntries[#racEntries + 1] = {isItem = true, spellID = item.itemID, itemSpellID = item.spellID}
  end
  local custom = LucidUIDB and LucidUIDB["tr_customSpells"]
  if custom then
    for _, id in ipairs(custom) do
      racEntries[#racEntries + 1] = ResolveID(id)
    end
  end
end

-- ── Layout trinkets bar ─────────────────────────────────────────────────
local function LayoutTrinkets()
  if not trkContainer then return end
  local w, h = Opt("trkWidth"), Opt("trkHeight")
  local sp = Opt("trkSpacing")

  for i = 1, 2 do
    if not trkFrames[i] then trkFrames[i] = CreateIcon(trkContainer) end
    UpdateTrinket(trkFrames[i], i == 1 and TRINKET_SLOT_1 or TRINKET_SLOT_2)
  end
  -- Position only visible frames
  local grow = Opt("trkGrow")
  local vis = 0
  for i = 1, 2 do
    if trkFrames[i]:IsShown() then
      trkFrames[i]:ClearAllPoints()
      if grow == "LEFT" then
        trkFrames[i]:SetPoint("RIGHT", trkContainer, "RIGHT", -(vis * (w + sp)), 0)
      else
        trkFrames[i]:SetPoint("LEFT", trkContainer, "LEFT", vis * (w + sp), 0)
      end
      vis = vis + 1
    end
  end
  trkContainer:SetSize(math.max(1, vis * (w + sp) - sp), h)
  if vis == 0 then trkContainer:Hide() else trkContainer:Show() end
end

-- ── Layout racials bar ──────────────────────────────────────────────────
local function LayoutRacials()
  if not racContainer then return end
  local w, h = Opt("racWidth"), Opt("racHeight")
  local sp = Opt("racSpacing")
  local grow = Opt("racGrow")

  for i = #racFrames + 1, #racEntries do
    racFrames[i] = CreateIcon(racContainer)
  end

  local vis = 0
  for i, entry in ipairs(racEntries) do
    UpdateRacialIcon(racFrames[i], entry)
    if racFrames[i]:IsShown() then
      racFrames[i]:ClearAllPoints()
      if grow == "LEFT" then
        racFrames[i]:SetPoint("RIGHT", racContainer, "RIGHT", -(vis * (w + sp)), 0)
      else
        racFrames[i]:SetPoint("LEFT", racContainer, "LEFT", vis * (w + sp), 0)
      end
      vis = vis + 1
    end
  end
  for i = #racEntries + 1, #racFrames do racFrames[i]:Hide() end
  racContainer:SetSize(math.max(1, vis * (w + sp) - sp), h)
  if vis == 0 then racContainer:Hide() else racContainer:Show() end
end

-- ── Full refresh ────────────────────────────────────────────────────────
local function FullRefresh()
  if not NS.IsCDMEnabled() or not Opt("enabled") then
    if trkContainer then trkContainer:Hide() end
    if racContainer then racContainer:Hide() end
    return
  end
  if not trkContainer then trkContainer = CreateBar("LucidUITrinkets"); TR._trkContainer = trkContainer end
  if not racContainer then racContainer = CreateBar("LucidUIRacials"); TR._racContainer = racContainer end

  AnchorBar(trkContainer, "trkPos", "trkAnchor", "trkOffX", "trkOffY")
  AnchorBar(racContainer, "racPos", "racAnchor", "racOffX", "racOffY")

  BuildRacialEntries()
  LayoutTrinkets(); trkContainer:Show()
  LayoutRacials()
end

-- ── Event handling ──────────────────────────────────────────────────────
local evFrame = CreateFrame("Frame")
-- Register all events up front so the first PLAYER_SPECIALIZATION_CHANGED /
-- PLAYER_EQUIPMENT_CHANGED after login is also observed. The handler itself
-- gates on `initialized` to avoid doing work before init completes.
evFrame:RegisterEvent("PLAYER_LOGIN")
evFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
evFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
evFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
evFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
evFrame:SetScript("OnEvent", function(_, event, arg1)
  if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
    if event == "PLAYER_ENTERING_WORLD" then
      if arg1 or initialized then return end -- skip initial login, already init
    end
    if initialized then return end
    if not NS.IsCDMEnabled() or not Opt("enabled") then return end
    C_Timer.After(1.2, function()
      if initialized then return end
      NS.SafeCall(function()
        initialized = true
        FullRefresh()
        TR._ticker = C_Timer.NewTicker(0.5, function()
          if not initialized or not NS.IsCDMEnabled() or not Opt("enabled") then return end
          for i = 1, 2 do
            if trkFrames[i] then UpdateTrinket(trkFrames[i], i == 1 and TRINKET_SLOT_1 or TRINKET_SLOT_2) end
          end
          for i, entry in ipairs(racEntries) do
            if racFrames[i] then UpdateRacialIcon(racFrames[i], entry) end
          end
        end)
      end, "Trinkets")
    end)
  elseif event == "ACTIVE_TALENT_GROUP_CHANGED" or event == "PLAYER_SPECIALIZATION_CHANGED" then
    if initialized then C_Timer.After(0.5, FullRefresh) end
  elseif event == "PLAYER_EQUIPMENT_CHANGED" then
    if initialized then LayoutTrinkets() end
  end
end)

-- ── Public API ──────────────────────────────────────────────────────────
function TR.Enable() initialized = true; FullRefresh() end
function TR.Disable()
  evFrame:UnregisterEvent("PLAYER_EQUIPMENT_CHANGED")
  evFrame:UnregisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
  evFrame:UnregisterEvent("PLAYER_SPECIALIZATION_CHANGED")
  if trkContainer then trkContainer:Hide() end
  if racContainer then racContainer:Hide() end
  if TR._ticker then TR._ticker:Cancel(); TR._ticker = nil end
  initialized = false
end
function TR.Refresh() if initialized then FullRefresh() end end

-- ── Settings Tab ────────────────────────────────────────────────────────
function TR.SetupSettings(parent)
  local MakeCard = NS._SMakeCard
  local MakePage = NS._SMakePage
  local R = NS._SR
  local SBD = NS.BACKDROP
  local cont = CreateFrame("Frame", nil, parent)
  local sc, Append = MakePage(cont)

  local function Slider(card, label, key, mn, mx, fmt, default)
    local s; s = NS.ChatGetSlider(card.inner, label, mn, mx, fmt, function()
      OptSet(key, s:GetValue()); TR.Refresh()
    end); R(card, s, 40); s:SetValue(Opt(key) or default)
  end

  local function MakeUnlockReset(card, posKey, _, offXKey, offYKey, _, barGetter)
    local enRow = CreateFrame("Frame", nil, card.inner); enRow:SetHeight(26)
    local resetBtn = CreateFrame("Button", nil, enRow, "BackdropTemplate"); resetBtn:SetSize(50, 20); resetBtn:SetPoint("RIGHT", -8, 0)
    resetBtn:SetBackdrop(SBD); resetBtn:SetBackdropColor(0.04, 0.04, 0.07, 1); resetBtn:SetBackdropBorderColor(0.12, 0.12, 0.20, 1)
    local resetFS = resetBtn:CreateFontString(nil, "OVERLAY"); resetFS:SetFont(NS.FONT, 9, ""); resetFS:SetPoint("CENTER"); resetFS:SetTextColor(0.65, 0.65, 0.75); resetFS:SetText(L["Reset"])
    resetBtn:SetScript("OnClick", function() OptSet(posKey, nil); OptSet(offXKey, 0); OptSet(offYKey, 0); TR.Refresh() end)
    resetBtn:SetScript("OnEnter", function() local r,g,b = NS.ChatGetAccentRGB(); resetBtn:SetBackdropBorderColor(r, g, b, 0.8) end)
    resetBtn:SetScript("OnLeave", function() resetBtn:SetBackdropBorderColor(0.12, 0.12, 0.20, 1) end)
    local lockBtn = CreateFrame("Button", nil, enRow, "BackdropTemplate"); lockBtn:SetSize(70, 20); lockBtn:SetPoint("RIGHT", resetBtn, "LEFT", -4, 0)
    lockBtn:SetBackdrop(SBD); lockBtn:SetBackdropColor(0.04, 0.04, 0.07, 1); lockBtn:SetBackdropBorderColor(0.12, 0.12, 0.20, 1)
    local lockFS = lockBtn:CreateFontString(nil, "OVERLAY"); lockFS:SetFont(NS.FONT, 9, ""); lockFS:SetPoint("CENTER"); lockFS:SetTextColor(0.65, 0.65, 0.75); lockFS:SetText(L["Unlock"])
    local unlocked = false
    lockBtn:SetScript("OnClick", function()
      unlocked = not unlocked; lockFS:SetText(unlocked and "Lock" or L["Unlock"])
      local r, g, b = NS.ChatGetAccentRGB()
      if unlocked then lockBtn:SetBackdropBorderColor(r, g, b, 0.8) else lockBtn:SetBackdropBorderColor(0.12, 0.12, 0.20, 1) end
      local b2 = barGetter()
      if not b2 then return end
      if unlocked then
        b2:Show(); b2:EnableMouse(true); b2:SetMovable(true); b2:RegisterForDrag("LeftButton")
        b2:SetScript("OnDragStart", function(s) s:StartMoving() end)
        b2:SetScript("OnDragStop", function(s)
          s:StopMovingOrSizing()
          local left, top = s:GetLeft(), s:GetTop()
          if left then OptSet(posKey, {p="TOPLEFT", x=left, y=top - GetScreenHeight()}) end
          NS.UpdateMoverPopup()
        end)
        local label = posKey == "trkPos" and "Trinkets" or "Racials"
        NS.ShowMoverPopup(b2, label, function(f)
          local left, top = f:GetLeft(), f:GetTop()
          if left then OptSet(posKey, {p="TOPLEFT", x=left, y=top - GetScreenHeight()}) end
        end, function()
          OptSet(posKey, nil); OptSet(offXKey, 0); OptSet(offYKey, 0); TR.Refresh()
        end)
      else
        b2:EnableMouse(false); b2:RegisterForDrag(); b2:SetScript("OnDragStart", nil); b2:SetScript("OnDragStop", nil)
        NS.HideMoverPopup()
        TR.Refresh()
      end
    end)
    lockBtn:SetScript("OnEnter", function() local r,g,b = NS.ChatGetAccentRGB(); lockBtn:SetBackdropBorderColor(r, g, b, 0.8) end)
    lockBtn:SetScript("OnLeave", function() if not unlocked then lockBtn:SetBackdropBorderColor(0.12, 0.12, 0.20, 1) end end)
    R(card, enRow, 26)
  end

  local anchorLabels = {"Top Left", "Top Right", "Bottom Left", "Bottom Right"}
  local anchorValues = {"TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT"}
  local growLabels = {"Right", "Left"}
  local growValues = {"RIGHT", "LEFT"}

  local function Dropdown(card, label, labs, vals, key, default, posKey)
    local dd = NS.ChatGetDropdown(card.inner, label,
      function(v) return (Opt(key) or default) == v end,
      function(v)
        OptSet(key, v)
        -- Clear saved manual position so anchor dropdown takes effect
        if posKey then OptSet(posKey, nil) end
        TR.Refresh()
      end)
    dd:Init(labs, vals); R(card, dd, 46)
  end
  local function Toggle(card, label, key, tip)
    local cb = NS.ChatGetCheckbox(card.inner, label, 26, function(s) OptSet(key, s); TR.Refresh() end, tip)
    R(card, cb, 26); cb:SetValue(Opt(key) ~= false)
  end

  -- ── Trinkets card ──
  local cTrk = MakeCard(sc, L["Trinkets"])
  MakeUnlockReset(cTrk, "trkPos", "trkAnchor", "trkOffX", "trkOffY", trkContainer, function() return trkContainer end)
  Toggle(cTrk, "Show Passive Trinkets", "trkShowPassive", "Show trinkets without on-use effect")
  Dropdown(cTrk, "Anchor Point", anchorLabels, anchorValues, "trkAnchor", "TOPLEFT", "trkPos")
  Dropdown(cTrk, "Grow Direction", growLabels, growValues, "trkGrow", "RIGHT")
  Slider(cTrk, "Icon Width", "trkWidth", 16, 60, "%spx", 36)
  Slider(cTrk, "Icon Height", "trkHeight", 16, 60, "%spx", 36)
  Slider(cTrk, "Spacing", "trkSpacing", 0, 10, "%spx", 2)
  Slider(cTrk, "Offset X", "trkOffX", -300, 300, "%spx", 0)
  Slider(cTrk, "Offset Y", "trkOffY", -300, 300, "%spx", 0)
  Slider(cTrk, "CD Font Size", "trkCdFontSize", 6, 20, "%spx", 12)
  cTrk:Finish(); Append(cTrk, cTrk:GetHeight()); Append(NS._SSep(sc), 9)

  -- ── Racials card ──
  local cRac = MakeCard(sc, L["Racials / Items"])
  MakeUnlockReset(cRac, "racPos", "racAnchor", "racOffX", "racOffY", racContainer, function() return racContainer end)
  Toggle(cRac, "Show Items at Zero Stacks", "racShowZeroStacks", "Show items even when you have none")
  Dropdown(cRac, "Anchor Point", anchorLabels, anchorValues, "racAnchor", "BOTTOMLEFT", "racPos")
  Dropdown(cRac, "Grow Direction", growLabels, growValues, "racGrow", "RIGHT")
  Slider(cRac, "Icon Width", "racWidth", 16, 60, "%spx", 36)
  Slider(cRac, "Icon Height", "racHeight", 16, 60, "%spx", 36)
  Slider(cRac, "Spacing", "racSpacing", 0, 10, "%spx", 2)
  Slider(cRac, "Offset X", "racOffX", -300, 300, "%spx", 0)
  Slider(cRac, "Offset Y", "racOffY", -300, 300, "%spx", 0)
  Slider(cRac, "CD Font Size", "racCdFontSize", 6, 20, "%spx", 12)
  Slider(cRac, "Stack Font Size", "racStackFontSize", 6, 20, "%spx", 11)
  cRac:Finish(); Append(cRac, cRac:GetHeight()); Append(NS._SSep(sc), 9)

  -- ── Display card ──
  local cShared = MakeCard(sc, L["Display"])
  Toggle(cShared, "Cooldown Text", "showCooldownText", "Show cooldown timer on icons")
  cShared:Finish(); Append(cShared, cShared:GetHeight()); Append(NS._SSep(sc), 9)

  -- ── Custom Spells card ──
  local cCustom = MakeCard(sc, L["Custom Spells"])

  -- Add row
  local addRow = CreateFrame("Frame", nil, cCustom.inner); addRow:SetHeight(30)
  local eb = CreateFrame("EditBox", nil, addRow, "InputBoxTemplate")
  eb:SetSize(120, 20); eb:SetPoint("LEFT", 4, 0)
  eb:SetAutoFocus(false); eb:SetNumeric(true); eb:SetFontObject("ChatFontNormal")
  local addBtn = CreateFrame("Button", nil, addRow, "BackdropTemplate")
  addBtn:SetSize(50, 20); addBtn:SetPoint("LEFT", eb, "RIGHT", 4, 0)
  addBtn:SetBackdrop(SBD); addBtn:SetBackdropColor(0.04, 0.04, 0.07, 1); addBtn:SetBackdropBorderColor(0.12, 0.12, 0.20, 1)
  local addFS = addBtn:CreateFontString(nil, "OVERLAY"); addFS:SetFont(NS.FONT, 9, ""); addFS:SetPoint("CENTER"); addFS:SetTextColor(0.65, 0.65, 0.75); addFS:SetText(L["Add"])
  local hint = addRow:CreateFontString(nil, "OVERLAY")
  hint:SetFont(NS.FONT, 9, ""); hint:SetPoint("LEFT", addBtn, "RIGHT", 8, 0)
  hint:SetTextColor(0.4, 0.4, 0.5); hint:SetText(L["Spell or Item ID"])
  R(cCustom, addRow, 26)

  -- Dynamic list container (height 0 baseline — grows with items)
  local listHolder = CreateFrame("Frame", nil, cCustom.inner)
  R(cCustom, listHolder, 0)

  local listRows = {}
  local function MakeRow()
    local row = CreateFrame("Frame", nil, listHolder); row:SetHeight(24)
    row._icon = row:CreateTexture(nil, "ARTWORK"); row._icon:SetSize(18, 18); row._icon:SetPoint("LEFT", 4, 0)
    row._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row._label = row:CreateFontString(nil, "OVERLAY"); row._label:SetFont(NS.FONT, 10, "")
    row._label:SetPoint("LEFT", row._icon, "RIGHT", 6, 0); row._label:SetTextColor(0.7, 0.7, 0.8)
    row._idText = row:CreateFontString(nil, "OVERLAY"); row._idText:SetFont(NS.FONT, 9, "")
    row._idText:SetTextColor(0.4, 0.4, 0.5)
    local delBtn = CreateFrame("Button", nil, row); delBtn:SetSize(16, 16); delBtn:SetPoint("RIGHT", -4, 0)
    local delTex = delBtn:CreateTexture(nil, "ARTWORK"); delTex:SetAllPoints()
    delTex:SetTexture("Interface/AddOns/LucidUI/Assets/X_red.png"); delTex:SetVertexColor(0.5, 0.5, 0.5)
    delBtn:SetScript("OnEnter", function() delTex:SetVertexColor(1, 0.3, 0.3) end)
    delBtn:SetScript("OnLeave", function() delTex:SetVertexColor(0.5, 0.5, 0.5) end)
    row._delBtn = delBtn
    local upBtn = CreateFrame("Button", nil, row); upBtn:SetSize(14, 14); upBtn:SetPoint("RIGHT", delBtn, "LEFT", -4, 0)
    local upTex = upBtn:CreateTexture(nil, "ARTWORK"); upTex:SetAllPoints()
    upTex:SetTexture("Interface/AddOns/LucidUI/Assets/Arrow_right_green.png")
    upTex:SetRotation(math.rad(90)); upTex:SetVertexColor(0.5, 0.5, 0.5)
    upBtn:SetScript("OnEnter", function() upTex:SetVertexColor(0.3, 1, 0.3) end)
    upBtn:SetScript("OnLeave", function() upTex:SetVertexColor(0.5, 0.5, 0.5) end)
    row._upBtn = upBtn
    local dnBtn = CreateFrame("Button", nil, row); dnBtn:SetSize(14, 14); dnBtn:SetPoint("RIGHT", upBtn, "LEFT", -2, 0)
    local dnTex = dnBtn:CreateTexture(nil, "ARTWORK"); dnTex:SetAllPoints()
    dnTex:SetTexture("Interface/AddOns/LucidUI/Assets/Arrow_right_orange.png")
    dnTex:SetRotation(math.rad(-90)); dnTex:SetVertexColor(0.5, 0.5, 0.5)
    dnBtn:SetScript("OnEnter", function() dnTex:SetVertexColor(1, 0.6, 0.2) end)
    dnBtn:SetScript("OnLeave", function() dnTex:SetVertexColor(0.5, 0.5, 0.5) end)
    row._dnBtn = dnBtn
    row:Hide()
    return row
  end

  local function RefreshList()
    for _, row in ipairs(listRows) do row:Hide() end
    local custom = LucidUIDB and LucidUIDB["tr_customSpells"]
    local count = custom and #custom or 0
    for i = #listRows + 1, count do listRows[i] = MakeRow() end

    for i = 1, count do
      local row = listRows[i]
      local id = custom[i]
      local name, tex = tostring(id), nil
      pcall(function() tex = C_Item.GetItemIconByID(id) end)
      if not tex then pcall(function() tex = C_Spell.GetSpellTexture(id) end) end
      pcall(function() local n = C_Item.GetItemNameByID(id); if n then name = n end end)
      if name == tostring(id) then pcall(function() local info = C_Spell.GetSpellInfo(id); if info then name = info.name end end) end
      row._icon:SetTexture(tex or 134400)
      row._label:SetText(name)
      row._idText:SetText("  #" .. id); row._idText:ClearAllPoints(); row._idText:SetPoint("LEFT", row._label, "RIGHT", 0, 0)
      local ci = i
      row._delBtn:SetScript("OnClick", function() table.remove(custom, ci); RefreshList(); TR.Refresh() end)
      row._upBtn:SetScript("OnClick", function()
        if ci <= 1 then return end; custom[ci], custom[ci-1] = custom[ci-1], custom[ci]; RefreshList(); TR.Refresh()
      end)
      row._dnBtn:SetScript("OnClick", function()
        if ci >= #custom then return end; custom[ci], custom[ci+1] = custom[ci+1], custom[ci]; RefreshList(); TR.Refresh()
      end)
      row._upBtn:SetShown(i > 1); row._dnBtn:SetShown(i < count)
      row:ClearAllPoints(); row:SetPoint("TOPLEFT", listHolder, "TOPLEFT", 0, -(i - 1) * 24)
      row:SetPoint("RIGHT", listHolder, "RIGHT", 0, 0)
      row:Show()
    end
    listHolder:SetHeight(math.max(1, count * 24))
    -- Update card height dynamically after add/remove
    if cCustom._baseHeight then
      cCustom:SetHeight(cCustom._baseHeight + math.max(0, count * 24) + 10)
      if sc and sc.UpdateScrollChildRect then pcall(sc.UpdateScrollChildRect, sc) end
    end
  end

  addBtn:SetScript("OnClick", function()
    local id = tonumber(eb:GetText()); if not id or id == 0 then return end
    if not LucidUIDB then LucidUIDB = {} end
    if not LucidUIDB["tr_customSpells"] then LucidUIDB["tr_customSpells"] = {} end
    table.insert(LucidUIDB["tr_customSpells"], id)
    eb:SetText(""); RefreshList(); TR.Refresh()
  end)
  addBtn:SetScript("OnEnter", function() local r,g,b = NS.ChatGetAccentRGB(); addBtn:SetBackdropBorderColor(r, g, b, 0.8) end)
  addBtn:SetScript("OnLeave", function() addBtn:SetBackdropBorderColor(0.12, 0.12, 0.20, 1) end)
  eb:SetScript("OnEnterPressed", function() addBtn:Click() end)

  RefreshList()
  cCustom:Finish()
  cCustom._baseHeight = cCustom:GetHeight()
  -- Add current list height to card
  local initCount = (LucidUIDB and LucidUIDB["tr_customSpells"]) and #LucidUIDB["tr_customSpells"] or 0
  cCustom:SetHeight(cCustom._baseHeight + math.max(0, initCount * 24) + 10)
  Append(cCustom, cCustom:GetHeight() + 12)

  return cont
end