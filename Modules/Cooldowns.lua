-- LucidUI Modules/Cooldowns.lua
-- Hooks into Blizzard's CooldownViewer system (Essential/Utility)
-- to restyle and reposition native cooldown frames.
-- Uses per-frame SetPoint interception to prevent Blizzard layout override.

local NS = LucidUINS
NS.Cooldowns = NS.Cooldowns or {}
local CD = NS.Cooldowns

-- ── Viewer names ────────────────────────────────────────────────────────
local VIEWERS = {
  ESSENTIAL = "EssentialCooldownViewer",
  UTILITY   = "UtilityCooldownViewer",
}

-- ── Defaults ────────────────────────────────────────────────────────────
local DEFAULTS = {
  essWidth = 46, essHeight = 40, essSpacing = 2, essPerRow = 8, essGrow = "RIGHT",
  utilWidth = 46, utilHeight = 40, utilSpacing = 2, utilPerRow = 8, utilGrow = "RIGHT",
  texture = "Flat", bgTexture = "Flat",
  font = "default", fontSize = 14, fontOutline = "OUTLINE",
  textColor = {1, 1, 1},
  showTimer = true, desaturateOnCD = true,
  bgColor = {0.06, 0.06, 0.10, 0.85},
  showBorder = true,
  borderTexture = "1 Pixel",
  borderColor = {0, 0, 0, 1},
  zoomIcons = true,
  hideShadowOverlay = true,
  hideIconMask = true,
}

local function Opt(key)
  local db = LucidUIDB
  if db and db["cdv_" .. key] ~= nil then return db["cdv_" .. key] end
  return DEFAULTS[key]
end
local function OptSet(key, val)
  if not LucidUIDB then return end
  LucidUIDB["cdv_" .. key] = val
end

-- ── State ───────────────────────────────────────────────────────────────
local containers = {}
local frameData = setmetatable({}, {__mode = "k"})
local hookedFrames = {}
local hookedViewers = {}
local hookedPools = {}
local hookedLayouts = {}
local combatDirty = {}
local initialized = false

-- ── Raw SetPoint/ClearAllPoints (avoid recursion) ───────────────────────
local rawSetPoint = nil
local rawClearAllPoints = nil

-- Store raw frame methods from a clean proxy frame (never hooked by anyone)
local _anchorProxy = CreateFrame("Frame")
rawSetPoint = _anchorProxy.SetPoint
rawClearAllPoints = _anchorProxy.ClearAllPoints


-- ── Frame data (weak-key) ───────────────────────────────────────────────
local function GetFD(frame)
  if not frameData[frame] then frameData[frame] = {} end
  return frameData[frame]
end

-- ── Snap to pixel ───────────────────────────────────────────────────────
local function Snap(v) return math.floor(v + 0.5) end

-- ── Get or create anchor container ──────────────────────────────────────
local function GetContainer(viewerName)
  if containers[viewerName] then return containers[viewerName] end

  local f = CreateFrame("Frame", "LucidUI_CD_" .. viewerName, UIParent)
  f:SetFrameStrata("MEDIUM"); f:SetFrameLevel(10)
  f:SetClampedToScreen(true); f:SetMovable(true); f:EnableMouse(false)
  if f.SetPreventSecretValues then f:SetPreventSecretValues(true) end

  local posKey = viewerName == VIEWERS.ESSENTIAL and "essPos" or "utilPos"
  local pos = Opt(posKey)
  if pos and pos.p then
    f:SetPoint(pos.p, UIParent, pos.p, pos.x, pos.y)
  elseif viewerName == VIEWERS.UTILITY then
    -- Anchor Utility below Essential by default
    local essContainer = containers[VIEWERS.ESSENTIAL]
    if essContainer then
      f:SetPoint("TOP", essContainer, "BOTTOM", 0, -2)
    else
      f:SetPoint("CENTER", UIParent, "CENTER", 0, -270)
    end
    f._needsAnchorToEss = true
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, -220)
  end

  containers[viewerName] = f
  return f
end

-- ── Border textures (from LibSharedMedia + WoW defaults) ────────────────
local function GetBorderList()
  local names = {"1 Pixel"}
  local paths = {["1 Pixel"] = "Interface/Buttons/WHITE8X8"}
  local LSM = LibStub and LibStub:GetLibrary("LibSharedMedia-3.0", true)
  if LSM then
    for _, name in ipairs(LSM:List("border")) do
      if not paths[name] then
        local path = LSM:Fetch("border", name, true)
        if path then names[#names+1] = name; paths[name] = path end
      end
    end
  end
  return names, paths
end
local BORDER_NAMES, BORDER_PATHS = GetBorderList()

local function GetBorderPath(key)
  return BORDER_PATHS[key] or "Interface/Buttons/WHITE8X8"
end

-- ── Style a single CD frame ─────────────────────────────────────────────
local function StyleFrame(frame, w, h)
  frame:SetSize(w, h)

  -- Icon texture
  local tex = frame.Icon or (frame:GetRegions())
  if tex and tex.SetTexCoord then
    if Opt("zoomIcons") then
      tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    else
      tex:SetTexCoord(0, 1, 0, 1)
    end
    tex:ClearAllPoints(); tex:SetAllPoints(frame)
  end

  -- Cooldown overlay — keep Blizzard's countdown text, apply custom font size
  if frame.Cooldown then
    frame.Cooldown:ClearAllPoints()
    frame.Cooldown:SetAllPoints(frame)
    frame.Cooldown:SetDrawEdge(false)
    frame.Cooldown:SetDrawBling(false)
    -- Apply font, size, outline, color to Blizzard's countdown text
    local fontSize = Opt("fontSize")
    local fontPath = NS.GetFontPath(Opt("font"))
    local fontOutline = Opt("fontOutline") or "OUTLINE"
    local tc = Opt("textColor") or {1, 0.82, 0}
    for _, region in ipairs({frame.Cooldown:GetRegions()}) do
      if region:IsObjectType("FontString") then
        region:SetFont(fontPath, fontSize, fontOutline)
        region:SetTextColor(tc[1], tc[2], tc[3])
        region:SetShadowOffset(0, 0)
      end
    end
  end

  -- Background
  local fd = GetFD(frame)
  if not fd.bg then
    fd.bg = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
  end
  fd.bg:ClearAllPoints(); fd.bg:SetAllPoints(frame)
  fd.bg:SetTexture(NS.GetBarTexturePath(Opt("bgTexture")))
  local bgc = Opt("bgColor")
  fd.bg:SetVertexColor(bgc[1], bgc[2], bgc[3], bgc[4] or 0.85)
  fd.bg:Show()

  -- Border (4 edge textures with custom texture file)
  local showBorder = Opt("showBorder") ~= false
  local borderPath = GetBorderPath(Opt("borderTexture"))
  local bc = Opt("borderColor") or {1, 0, 0, 1}
  local borderSize = (borderPath == "Interface/Buttons/WHITE8X8") and 1 or 2
  if not fd.border then
    fd.border = {}
    local function MkB(p1, p2, bw, bh)
      local t = frame:CreateTexture(nil, "OVERLAY", nil, 7)
      t:SetPoint(p1, frame, p1, 0, 0); t:SetPoint(p2, frame, p2, 0, 0)
      if bw then t:SetWidth(bw) end; if bh then t:SetHeight(bh) end
      fd.border[#fd.border + 1] = t
    end
    MkB("TOPLEFT", "TOPRIGHT", nil, nil)     -- top
    MkB("BOTTOMLEFT", "BOTTOMRIGHT", nil, nil) -- bottom
    MkB("TOPLEFT", "BOTTOMLEFT", nil, nil)   -- left
    MkB("TOPRIGHT", "BOTTOMRIGHT", nil, nil) -- right
  end
  for i, b in ipairs(fd.border) do
    if showBorder then
      b:SetTexture(borderPath)
      b:SetVertexColor(bc[1], bc[2], bc[3], bc[4] or 1)
      if i <= 2 then b:SetHeight(borderSize) else b:SetWidth(borderSize) end
      b:Show()
    else
      b:Hide()
    end
  end


  -- ── Visual Element Options ──────────────────────────────────────────

  -- 1. Remove Shadow Overlay (atlas + texture overlay on icon)
  local hideShadow = Opt("hideShadowOverlay")
  for _, region in ipairs({frame:GetRegions()}) do
    if region and region.IsObjectType and region:IsObjectType("Texture") and region ~= (frame.Icon) and region ~= fd.bg then
      local match = false
      local atlas = region.GetAtlas and region:GetAtlas()
      if atlas == "UI-HUD-CoolDownManager-IconOverlay" then match = true end
      local texFile = region.GetTexture and region:GetTexture()
      if texFile == 6707800 then match = true end
      if match then
        if hideShadow then region:SetAlpha(0); region:Hide()
        else region:SetAlpha(1); region:Show() end
      end
    end
  end

  -- 2. Remove Default Icon Mask (rounded mask on icon texture) — once per frame
  if Opt("hideIconMask") and not fd._maskRemoved and tex and tex.RemoveMaskTexture then
    local regions = {frame:GetRegions()}
    for i = 1, #regions do
      local region = regions[i]
      if region and region.IsObjectType and region:IsObjectType("MaskTexture") then
        pcall(tex.RemoveMaskTexture, tex, region)
        fd._maskRemoved = true
        break
      end
    end
  end

end

-- ── Place a frame at a position, storing cdmAnchor ──────────────────────
local function PlaceFrame(frame, container, x, y, viewer)
  local fd = GetFD(frame)
  fd.cdmAnchor = {"TOPLEFT", container, "TOPLEFT", Snap(x), Snap(y)}

  rawClearAllPoints(frame)
  rawSetPoint(frame, "TOPLEFT", container, "TOPLEFT", Snap(x), Snap(y))
  frame:Show()
end

-- ── Install SetPoint hook on individual frame ───────────────────────────
local function HookFrameSetPoint(frame)
  if hookedFrames[frame] then return end
  hookedFrames[frame] = true

  hooksecurefunc(frame, "SetPoint", function(self, point, relativeTo)
    local fd = frameData[self]
    if not fd or not fd.cdmAnchor then return end
    local a = fd.cdmAnchor
    if relativeTo == a[2] then return end
    rawClearAllPoints(self)
    rawSetPoint(self, a[1], a[2], a[3], a[4], a[5])
  end)
end

-- ── Layout a viewer's frames ────────────────────────────────────────────
local function LayoutViewer(viewerName)
  if InCombatLockdown() then return end
  local viewer = _G[viewerName]
  if not viewer or not viewer.itemFramePool then return end
  if not NS.IsCDMEnabled() then return end

  local isEss = viewerName == VIEWERS.ESSENTIAL
  local w = Snap(isEss and Opt("essWidth") or Opt("utilWidth"))
  local h = Snap(isEss and Opt("essHeight") or Opt("utilHeight"))
  local spacing = Snap(isEss and Opt("essSpacing") or Opt("utilSpacing"))
  local perRow = isEss and Opt("essPerRow") or Opt("utilPerRow")
  local grow = isEss and Opt("essGrow") or Opt("utilGrow")

  local container = GetContainer(viewerName)

  -- Collect active frames
  local frames = {}
  for frame in viewer.itemFramePool:EnumerateActive() do
    frames[#frames + 1] = frame
  end
  table.sort(frames, function(a, b) return (a.layoutIndex or 0) < (b.layoutIndex or 0) end)

  -- Position and style each frame
  local row, col = 0, 0
  for _, frame in ipairs(frames) do
    HookFrameSetPoint(frame)
    StyleFrame(frame, w, h)

    local xOff, yOff
    if grow == "RIGHT" then
      xOff = col * (w + spacing)
      yOff = row * (h + spacing)
    else
      xOff = -(col * (w + spacing))
      yOff = row * (h + spacing)
    end

    PlaceFrame(frame, container, xOff, -yOff, viewer)

    col = col + 1
    if col >= perRow then col = 0; row = row + 1 end
  end

  -- Size container
  local totalCols = math.min(#frames, perRow)
  local totalRows = math.ceil(math.max(1, #frames) / perRow)
  pcall(container.SetSize, container,
    math.max(1, totalCols * (w + spacing) - spacing),
    math.max(1, totalRows * (h + spacing) - spacing)
  )

  -- Sync viewer to container
  rawClearAllPoints(viewer)
  rawSetPoint(viewer, "TOPLEFT", container, "TOPLEFT", 0, 0)
  rawSetPoint(viewer, "BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
end

-- ── Force reanchor all frames in a viewer ───────────────────────────────
local function ForceReanchor(viewerName)
  local viewer = _G[viewerName]
  if not viewer or not viewer.itemFramePool then return end

  for frame in viewer.itemFramePool:EnumerateActive() do
    local fd = frameData[frame]
    if fd and fd.cdmAnchor then
          rawClearAllPoints(frame)
      rawSetPoint(frame, fd.cdmAnchor[1], fd.cdmAnchor[2], fd.cdmAnchor[3], fd.cdmAnchor[4], fd.cdmAnchor[5])
    end
  end
end

-- ── Hook a viewer's layout system ───────────────────────────────────────
local function SetupViewerHooks(viewerName)
  local viewer = _G[viewerName]
  if not viewer then return end
  if viewer.SetPreventSecretValues then viewer:SetPreventSecretValues(true) end

  -- Hook OnAcquireItemFrame (called when pool creates/acquires a frame)
  if viewer.OnAcquireItemFrame and not hookedViewers[viewerName] then
    hookedViewers[viewerName] = true
    hooksecurefunc(viewer, "OnAcquireItemFrame", function(_, itemFrame)
      if not NS.IsCDMEnabled() then return end
      HookFrameSetPoint(itemFrame)
      -- Defer layout to outside combat only
      if not InCombatLockdown() then
        C_Timer.After(0, function() LayoutViewer(viewerName) end)
      else
        combatDirty[viewerName] = true
      end
    end)
  end

  -- Fallback: hook pool Acquire for viewers without OnAcquireItemFrame
  if not viewer.OnAcquireItemFrame and viewer.itemFramePool and not hookedPools[viewerName] then
    hookedPools[viewerName] = true
    hooksecurefunc(viewer.itemFramePool, "Acquire", function()
      if not NS.IsCDMEnabled() then return end
      if not InCombatLockdown() then
        C_Timer.After(0, function() LayoutViewer(viewerName) end)
      else
        combatDirty[viewerName] = true
      end
    end)
  end

  -- Hook RefreshLayout + Layout (hooksecurefunc only — no taint)
  if viewer.RefreshLayout and not hookedLayouts[viewerName .. "_rl"] then
    hookedLayouts[viewerName .. "_rl"] = true
    hooksecurefunc(viewer, "RefreshLayout", function()
      if not NS.IsCDMEnabled() then return end
      if InCombatLockdown() then combatDirty[viewerName] = true; return end
      C_Timer.After(0, function() LayoutViewer(viewerName) end)
    end)
  end

  if viewer.Layout and not hookedLayouts[viewerName .. "_l"] then
    hookedLayouts[viewerName .. "_l"] = true
    hooksecurefunc(viewer, "Layout", function()
      if not NS.IsCDMEnabled() then return end
      if InCombatLockdown() then combatDirty[viewerName] = true; return end
      C_Timer.After(0, function()
        ForceReanchor(viewerName)
        LayoutViewer(viewerName)
      end)
    end)
  end

  -- Hook viewer SetPoint to keep it synced to container
  if not hookedLayouts[viewerName .. "_sp"] then
    hookedLayouts[viewerName .. "_sp"] = true
    hooksecurefunc(viewer, "SetPoint", function(_, _, relativeTo)
      if not NS.IsCDMEnabled() then return end
      local container = containers[viewerName]
      if not container or relativeTo == container then return end
      if InCombatLockdown() then return end
      rawClearAllPoints(viewer)
      rawSetPoint(viewer, "TOPLEFT", container, "TOPLEFT", 0, 0)
      rawSetPoint(viewer, "BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    end)
  end
end

local updateTicker = nil

-- ── Enable / Disable ────────────────────────────────────────────────────
function CD.Enable()
  for _, name in ipairs({VIEWERS.ESSENTIAL, VIEWERS.UTILITY}) do
    GetContainer(name)
    SetupViewerHooks(name)
    -- Reparent viewer to UIParent to remove from Blizzard's managed BottomFrameContainer
    -- This prevents UIParentManageFramePositions from repositioning the viewer during combat
    local viewer = _G[name]
    if viewer and viewer:GetParent() ~= UIParent then
      viewer:SetParent(UIParent)
    end
    LayoutViewer(name)
  end
  -- Re-anchor Utility below Essential now that both are sized
  local utilC = containers[VIEWERS.UTILITY]
  local essC = containers[VIEWERS.ESSENTIAL]
  if utilC and essC and utilC._needsAnchorToEss then
    utilC._needsAnchorToEss = nil
    utilC:ClearAllPoints()
    utilC:SetPoint("TOP", essC, "BOTTOM", 0, -2)
  end
  if not updateTicker then
    updateTicker = C_Timer.NewTicker(0.5, function()
      if NS.IsCDMEnabled() and not InCombatLockdown() then CD.Refresh() end
    end)
  end
end

function CD.Disable()
  if updateTicker then updateTicker:Cancel(); updateTicker = nil end
  for _, viewerName in ipairs({VIEWERS.ESSENTIAL, VIEWERS.UTILITY}) do
    local viewer = _G[viewerName]
    if viewer and viewer.itemFramePool then
      for frame in viewer.itemFramePool:EnumerateActive() do
        local fd = frameData[frame]
        if fd then
          fd.cdmAnchor = nil
          if fd.bg then fd.bg:Hide() end
          if fd.border then for _, b in ipairs(fd.border) do b:Hide() end end
        end
        -- Reparent back to viewer
        frame:SetParent(viewer)
      end
      -- Let Blizzard re-layout
      if viewer.Layout then pcall(viewer.Layout, viewer) end
    end
  end
end

function CD.Refresh()
  for _, name in ipairs({VIEWERS.ESSENTIAL, VIEWERS.UTILITY}) do
    LayoutViewer(name)
  end
  -- Notify Resources + CastBar to update autoWidth
  if NS.Resources and NS.Resources.Refresh then NS.Resources.Refresh() end
  if NS.CastBar and NS.CastBar.Refresh then NS.CastBar.Refresh() end
end

-- ── Init ────────────────────────────────────────────────────────────────
-- ── Spec Change handling ────────────────────────────────────────────────
local specChangePending = false

local function OnSpecChange()
  if not initialized or not NS.IsCDMEnabled() then return end
  if specChangePending then return end
  specChangePending = true
  -- Batch: wait for talent data to settle, then refresh
  C_Timer.After(0.5, function()
    specChangePending = false
    if InCombatLockdown() then return end
    -- Re-reparent viewers (Blizzard may have reparented them back on spec change)
    for _, name in ipairs({VIEWERS.ESSENTIAL, VIEWERS.UTILITY}) do
      local viewer = _G[name]
      if viewer and viewer:GetParent() ~= UIParent then
        viewer:SetParent(UIParent)
      end
    end
    CD.Refresh()
    C_Timer.After(0.3, function() CD.Refresh() end)
    C_Timer.After(1.0, function() CD.Refresh() end)
  end)
end

local evFrame = CreateFrame("Frame")
evFrame:RegisterEvent("PLAYER_LOGIN")
evFrame:RegisterEvent("PLAYER_LOGOUT")
evFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
evFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
evFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
evFrame:RegisterEvent("SPELLS_CHANGED")
evFrame:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    if not NS.IsCDMEnabled() then return end
    C_Timer.After(0.5, function()
      if initialized then return end
      initialized = true
      NS.SafeCall(CD.Enable, "Cooldowns")
    end)
    -- Final anchor chain refresh after all CDM modules have initialized
    C_Timer.After(1.5, function()
      NS.RefreshAnchorChain()
    end)
  elseif event == "ACTIVE_TALENT_GROUP_CHANGED" or event == "PLAYER_SPECIALIZATION_CHANGED" or event == "SPELLS_CHANGED" then
    OnSpecChange()
  elseif event == "PLAYER_REGEN_ENABLED" then
    if initialized and NS.IsCDMEnabled() then
      -- Flush any dirty viewers from combat
      for vn in pairs(combatDirty) do
        ForceReanchor(vn)
        LayoutViewer(vn)
      end
      wipe(combatDirty)
      CD.Refresh()
    end
  elseif event == "PLAYER_LOGOUT" then
    for _, viewerName in ipairs({VIEWERS.ESSENTIAL, VIEWERS.UTILITY}) do
      local posKey = viewerName == VIEWERS.ESSENTIAL and "essPos" or "utilPos"
      -- Only save if user has manually positioned (not auto-anchored)
      if Opt(posKey) then
        local c = containers[viewerName]
        if c then
          local p, _, _, x, y = c:GetPoint()
          if p then OptSet(posKey, {p=p, x=x, y=y}) end
        end
      end
    end
  end
end)

-- Expose containers for anchoring by other modules
CD._containers = containers

-- ── Settings Tab ────────────────────────────────────────────────────────
function CD.SetupSettings(parent)
  local container = CreateFrame("Frame", nil, parent)
  local MakeCard = NS._SMakeCard
  local MakePage = NS._SMakePage
  local R = NS._SR
  local SBD = {bgFile="Interface/Buttons/WHITE8X8",edgeFile="Interface/Buttons/WHITE8X8",edgeSize=1}
  local sc, Append = MakePage(container)

  local function Slider(card, label, key, mn, mx, fmt, default)
    local s; s = NS.ChatGetSlider(card.inner, label, mn, mx, fmt, function()
      OptSet(key, s:GetValue()); CD.Refresh()
    end); R(card, s, 40)
    s:SetValue(Opt(key) or default)
  end
  local function Dropdown(card, label, labels, values, key, default, maxH)
    local dd = NS.ChatGetDropdown(card.inner, label,
      function(v) return (Opt(key) or default) == v end,
      function(v) OptSet(key, v); CD.Refresh() end)
    dd:Init(labels, values, maxH); R(card, dd, 46)
  end
  local function TogglePair(card, l1, k1, l2, k2)
    local row = CreateFrame("Frame", nil, card.inner); row:SetHeight(26)
    local cb1 = NS.ChatGetCheckbox(row, l1, 26, function(s) OptSet(k1, s); CD.Refresh() end)
    cb1:ClearAllPoints(); cb1:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    cb1:SetPoint("BOTTOMRIGHT", row, "BOTTOM", -2, 0); cb1:SetValue(Opt(k1) ~= false)
    local cb2 = NS.ChatGetCheckbox(row, l2, 26, function(s) OptSet(k2, s); CD.Refresh() end)
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
      function(v) OptSet(k1, v); CD.Refresh() end)
    dd1:Init(labs1, vals1, maxH); dd1:SetParent(lh); dd1:ClearAllPoints(); dd1:SetAllPoints(lh)
    local dd2 = NS.ChatGetDropdown(rh, l2,
      function(v) return (Opt(k2) or def2) == v end,
      function(v) OptSet(k2, v); CD.Refresh() end)
    dd2:Init(labs2, vals2, maxH); dd2:SetParent(rh); dd2:ClearAllPoints(); dd2:SetAllPoints(rh)
    R(card, row, 46)
  end

  -- General card
  local cGen = MakeCard(sc, "General")
  local enRow = CreateFrame("Frame", nil, cGen.inner); enRow:SetHeight(26)
  -- Reset button
  local resetBtn = CreateFrame("Button", nil, enRow, "BackdropTemplate"); resetBtn:SetSize(50, 20); resetBtn:SetPoint("RIGHT", -8, 0)
  resetBtn:SetBackdrop(SBD); resetBtn:SetBackdropColor(0.04, 0.04, 0.07, 1); resetBtn:SetBackdropBorderColor(0.12, 0.12, 0.20, 1)
  local resetFS = resetBtn:CreateFontString(nil, "OVERLAY"); resetFS:SetFont("Fonts/FRIZQT__.TTF", 9, ""); resetFS:SetPoint("CENTER"); resetFS:SetTextColor(0.65, 0.65, 0.75); resetFS:SetText("Reset")
  resetBtn:SetScript("OnClick", function()
    OptSet("essPos", nil); OptSet("utilPos", nil)
    local essC = containers[VIEWERS.ESSENTIAL]
    if essC then
      essC:ClearAllPoints()
      essC:SetPoint("CENTER", UIParent, "CENTER", 0, -220)
    end
    local utilC = containers[VIEWERS.UTILITY]
    if utilC and essC then
      utilC:ClearAllPoints()
      utilC:SetPoint("TOP", essC, "BOTTOM", 0, -2)
    end
    NS.RefreshAnchorChain()
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
    for _, vn in ipairs({VIEWERS.ESSENTIAL, VIEWERS.UTILITY}) do
      local c = GetContainer(vn)
      if unlocked then
        c:Show(); c:EnableMouse(true); c:RegisterForDrag("LeftButton")
        c:SetScript("OnDragStart", function(s) s:StartMoving() end)
        c:SetScript("OnDragStop", function(s)
          s:StopMovingOrSizing()
          local p,_,_,x,y = s:GetPoint()
          OptSet(vn == VIEWERS.ESSENTIAL and "essPos" or "utilPos", {p=p, x=x, y=y})
        end)
        if not c._unlockBorder then
          c._unlockBorder = c:CreateTexture(nil, "OVERLAY", nil, 7); c._unlockBorder:SetAllPoints()
        end
        c._unlockBorder:SetColorTexture(r, g, b, 0.15); c._unlockBorder:Show()
      else
        c:EnableMouse(false); c:RegisterForDrag()
        c:SetScript("OnDragStart", nil); c:SetScript("OnDragStop", nil)
        if c._unlockBorder then c._unlockBorder:Hide() end
      end
    end
  end)
  lockBtn:SetScript("OnEnter", function() local r,g,b = NS.ChatGetAccentRGB(); lockBtn:SetBackdropBorderColor(r, g, b, 0.8) end)
  lockBtn:SetScript("OnLeave", function() if not unlocked then lockBtn:SetBackdropBorderColor(0.12, 0.12, 0.20, 1) end end)
  R(cGen, enRow, 26)
  TogglePair(cGen, "Zoom Icons", "zoomIcons", "Show Border", "showBorder")
  TogglePair(cGen, "Hide Shadow", "hideShadowOverlay", "Hide Mask", "hideIconMask")
  Dropdown(cGen, "Border Texture", BORDER_NAMES, BORDER_NAMES, "borderTexture", "1 Pixel")
  cGen:Finish(); Append(cGen, cGen:GetHeight()); Append(NS._SSep(sc), 9)

  -- Essential card
  local cEss = MakeCard(sc, "Essential Cooldowns")
  Slider(cEss, "Width", "essWidth", 20, 80, "%spx", 46)
  Slider(cEss, "Height", "essHeight", 20, 80, "%spx", 40)
  Slider(cEss, "Spacing", "essSpacing", 0, 10, "%spx", 2)
  Slider(cEss, "Per Row", "essPerRow", 1, 16, "%s", 8)
  Dropdown(cEss, "Grow Direction", {"Right", "Left"}, {"RIGHT", "LEFT"}, "essGrow", "RIGHT")
  cEss:Finish(); Append(cEss, cEss:GetHeight()); Append(NS._SSep(sc), 9)

  -- Utility card
  local cUtil = MakeCard(sc, "Utility Cooldowns")
  Slider(cUtil, "Width", "utilWidth", 20, 80, "%spx", 46)
  Slider(cUtil, "Height", "utilHeight", 20, 80, "%spx", 40)
  Slider(cUtil, "Spacing", "utilSpacing", 0, 10, "%spx", 2)
  Slider(cUtil, "Per Row", "utilPerRow", 1, 16, "%s", 8)
  Dropdown(cUtil, "Grow Direction", {"Right", "Left"}, {"RIGHT", "LEFT"}, "utilGrow", "RIGHT")
  cUtil:Finish(); Append(cUtil, cUtil:GetHeight()); Append(NS._SSep(sc), 9)

  -- Appearance card
  local cApp = MakeCard(sc, "Appearance")
  local barTexNames = {}
  local rawBars = NS.GetLSMStatusBars and NS.GetLSMStatusBars() or {}
  for _, b in ipairs(rawBars) do barTexNames[#barTexNames+1] = b.label end
  if #barTexNames == 0 then barTexNames = {"Flat"} end
  local fontNames, fontValues = {"Default"}, {"default"}
  for _, ft in ipairs(NS.GetLSMFonts()) do fontNames[#fontNames+1] = ft.label; fontValues[#fontValues+1] = ft.label end
  DropdownPair(cApp, "Background", barTexNames, barTexNames, "bgTexture", "Flat",
    "Font", fontNames, fontValues, "font", "default", 200)
  Dropdown(cApp, "Font Outline", {"None", "Outline", "Thick Outline"}, {"", "OUTLINE", "THICKOUTLINE"}, "fontOutline", "OUTLINE")
  Slider(cApp, "Font Size", "fontSize", 6, 20, "%spx", 12)
  -- Text Color
  local function ColorRow(card, label, key)
    local row = CreateFrame("Frame", nil, card.inner); row:SetHeight(24)
    local lbl = row:CreateFontString(nil, "OVERLAY"); lbl:SetFont("Fonts/FRIZQT__.TTF", 10, "")
    lbl:SetPoint("LEFT", 4, 0); lbl:SetTextColor(0.6, 0.6, 0.7); lbl:SetText(label)
    local cur = Opt(key) or {1,1,1}
    local sw = CreateFrame("Frame", nil, row, "BackdropTemplate"); sw:SetSize(20, 16); sw:SetPoint("LEFT", 110, 0)
    sw:SetBackdrop(SBD); sw:SetBackdropColor(cur[1], cur[2], cur[3], 1); sw:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    local hit = CreateFrame("Button", nil, sw); hit:SetAllPoints()
    hit:SetScript("OnClick", function()
      ColorPickerFrame:SetupColorPickerAndShow({r=cur[1], g=cur[2], b=cur[3],
        swatchFunc = function() local r,g,b = ColorPickerFrame:GetColorRGB(); OptSet(key, {r,g,b}); sw:SetBackdropColor(r,g,b,1); CD.Refresh() end,
        cancelFunc = function() sw:SetBackdropColor(cur[1], cur[2], cur[3], 1) end})
    end)
    R(card, row, 24)
  end
  ColorRow(cApp, "Text Color:", "textColor")
  ColorRow(cApp, "Border Color:", "borderColor")
  cApp:Finish(); Append(cApp, cApp:GetHeight())

  return container
end
