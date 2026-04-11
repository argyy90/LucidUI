-- LucidUI Modules/BuffBar.lua
-- Hooks into Blizzard's CooldownViewer buff system
-- to restyle and reposition buff icon and buff bar frames.

local NS = LucidUINS
NS.BuffBar = NS.BuffBar or {}
local BB = NS.BuffBar

-- ── Viewer names ────────────────────────────────────────────────────────
local VIEWER_BUFF_ICON = "BuffIconCooldownViewer"
local VIEWER_BUFF_BAR  = "BuffBarCooldownViewer"

-- ── Defaults ────────────────────────────────────────────────────────────
local DEFAULTS = {
  -- Buff Icons
  buffIconSize = 36, buffIconSpacing = 2, buffIconsPerRow = 12,
  buffIconGrow = "RIGHT",
  -- Buff Bars
  buffBarWidth = 200, buffBarHeight = 20, buffBarSpacing = 2,
  buffBarGrow = "DOWN", buffBarTexture = "Flat", buffBarBgTexture = "Flat",
  buffBarShowTimer = true, buffBarShowName = true,
  buffBarFont = "default", buffBarFontSize = 10,
  buffBarColor = {0.20, 0.60, 0.85},
  buffBarBgColor = {0.06, 0.06, 0.10, 0.85},
  zoomIcons = true,
  bgColor = {0.06, 0.06, 0.10, 0.85},
  showBorder = true,
  borderTexture = "1 Pixel",
  borderColor = {0, 0, 0, 1},
  hideShadowOverlay = true,
  hideIconMask = true,
  hideDebuffBorder = true,
  hidePandemic = false,
  hideBling = true,
  showDurationText = true,
  showStackCount = true,
}

local Opt, OptSet = NS.MakeOpt("bb_", DEFAULTS)

-- ── State ───────────────────────────────────────────────────────────────
local containers = {}
local frameData = setmetatable({}, {__mode = "k"})
local hookedFrames = {}
local hookedViewers = {}
local hookedLayouts = {}
local initialized = false
local evFrame  -- forward declaration; created at bottom of file

-- ── Raw SetPoint/ClearAllPoints from clean proxy frame ─────────────────
local _anchorProxy = CreateFrame("Frame")
local rawSetPoint = _anchorProxy.SetPoint
local rawClearAllPoints = _anchorProxy.ClearAllPoints

local function GetFD(frame)
  if not frameData[frame] then frameData[frame] = {} end
  return frameData[frame]
end

local function Snap(v) return NS.PixelSnap(v) end

-- ── Containers ──────────────────────────────────────────────────────────
local function GetContainer(viewerName)
  if containers[viewerName] then return containers[viewerName] end
  local f = CreateFrame("Frame", "LucidUI_BB_" .. viewerName, UIParent)
  f:SetFrameStrata("MEDIUM"); f:SetFrameLevel(10)
  f:SetClampedToScreen(true); f:SetMovable(true); f:EnableMouse(false)

  local posKey = viewerName == VIEWER_BUFF_ICON and "buffIconPos" or "buffBarPos"
  local pos = Opt(posKey)
  if pos and pos.p then
    f:SetPoint(pos.p, UIParent, pos.p, pos.x, pos.y)
  else
    local chainName = viewerName == VIEWER_BUFF_ICON and "BuffIcons" or "BuffBars"
    f._needsAnchor = chainName
  end
  containers[viewerName] = f
  return f
end

-- ── Scale Lock (prevent Blizzard from scaling buff frames) ─────────────
local function InstallScaleLockHook(frame)
  local fd = GetFD(frame)
  if fd.scaleLockHooked then return end
  fd.scaleLockHooked = true
  hooksecurefunc(frame, "SetScale", function(self, scale)
    if scale ~= 1 then self:SetScale(1) end
  end)
end

-- ── Hook individual frame SetPoint ──────────────────────────────────────
local function HookFrameSetPoint(frame)
  if hookedFrames[frame] then return end
  hookedFrames[frame] = true
  InstallScaleLockHook(frame)
  hooksecurefunc(frame, "SetPoint", function(self, _, relativeTo)
    local fd = frameData[self]
    if not fd or not fd.bbAnchor then return end
    local a = fd.bbAnchor
    if relativeTo == a[2] then return end
    rawClearAllPoints(self)
    rawSetPoint(self, a[1], a[2], a[3], a[4], a[5])
  end)
end

-- ── Place frame with stored anchor ──────────────────────────────────────
local function PlaceFrame(frame, container, x, y)
  local fd = GetFD(frame)
  fd.bbAnchor = {"TOPLEFT", container, "TOPLEFT", Snap(x), Snap(y)}
  rawClearAllPoints(frame)
  rawSetPoint(frame, "TOPLEFT", container, "TOPLEFT", Snap(x), Snap(y))
  frame:Show()
end

-- ── Border textures (from LibSharedMedia + WoW defaults) ────────────────
local function GetBorderList()
  local names = {"1 Pixel"}
  local paths = {["1 Pixel"] = NS.TEX_WHITE}
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
local function GetBorderPath(key) return BORDER_PATHS[key] or NS.TEX_WHITE end

-- ── Style buff icon frame ───────────────────────────────────────────────
local function StyleIconFrame(frame, size)
  frame:SetSize(size, size)
  local tex = frame.Icon or (frame:GetRegions())
  if tex and tex.SetTexCoord then
    if Opt("zoomIcons") then tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    else tex:SetTexCoord(0, 1, 0, 1) end
    tex:ClearAllPoints(); tex:SetAllPoints(frame)
  end
  if frame.Cooldown then
    frame.Cooldown:ClearAllPoints(); frame.Cooldown:SetAllPoints(frame)
    frame.Cooldown:SetDrawEdge(false)
    frame.Cooldown:SetHideCountdownNumbers(not Opt("showDurationText"))
    -- Apply font size to cooldown countdown text (uses shared buffBarFontSize)
    local iconFontSize = Opt("buffBarFontSize")
    local fontPath = NS.GetFontPath(Opt("buffBarFont"))
    for _, region in pairs({frame.Cooldown:GetRegions()}) do
      if region:IsObjectType("FontString") then
        region:SetFont(fontPath, iconFontSize, "OUTLINE")
      end
    end
  end

  -- Show/hide stack count
  if frame.Applications then
    if Opt("showStackCount") then
      frame.Applications:Show()
    else
      frame.Applications:Hide()
    end
  end
  -- Border (4 edge textures with custom texture file)
  local fd = GetFD(frame)
  local borderPath = GetBorderPath(Opt("borderTexture"))
  local bc = Opt("borderColor") or {1, 0, 0, 1}
  local borderSize = (borderPath == NS.TEX_WHITE) and 1 or 2
  if not fd.border then
    fd.border = {}
    local function MkB(p1, p2, bw, bh)
      local t = frame:CreateTexture(nil, "OVERLAY", nil, 7)
      t:SetPoint(p1, frame, p1, 0, 0); t:SetPoint(p2, frame, p2, 0, 0)
      if bw then t:SetWidth(bw) end; if bh then t:SetHeight(bh) end
      fd.border[#fd.border + 1] = t
    end
    MkB("TOPLEFT", "TOPRIGHT", nil, nil)
    MkB("BOTTOMLEFT", "BOTTOMRIGHT", nil, nil)
    MkB("TOPLEFT", "BOTTOMLEFT", nil, nil)
    MkB("TOPRIGHT", "BOTTOMRIGHT", nil, nil)
  end
  local showBorder = Opt("showBorder") ~= false
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

  -- Reposition stack count to top center (frame.Applications.Applications)
  if frame.Applications and frame.Applications.Applications then
    local countFS = frame.Applications.Applications
    countFS:ClearAllPoints()
    countFS:SetPoint("TOP", frame, "TOP", 0, 6)
    countFS:SetJustifyH("CENTER")
  end

  -- ── Visual Element Options (Buff-specific) ──────────────────────────

  -- 1. Shadow Overlay
  if Opt("hideShadowOverlay") then
    for _, region in ipairs({frame:GetRegions()}) do
      if region and region.IsObjectType and region:IsObjectType("Texture") and region ~= (frame.Icon) then
        local atlas = region.GetAtlas and region:GetAtlas()
        local texFile = region.GetTexture and region:GetTexture()
        if atlas == "UI-HUD-CoolDownManager-IconOverlay" or texFile == 6707800 then
          region:SetAlpha(0); region:Hide()
        end
      end
    end
  end

  -- 2. Icon Mask
  local iconTex = frame.Icon
  if Opt("hideIconMask") and not fd._maskRemoved and iconTex and iconTex.RemoveMaskTexture then
    for _, region in ipairs({frame:GetRegions()}) do
      if region and region.IsObjectType and region:IsObjectType("MaskTexture") then
        pcall(iconTex.RemoveMaskTexture, iconTex, region)
        fd._maskRemoved = true; break
      end
    end
  end

  -- 3. Debuff Border
  if frame.DebuffBorder then
    if Opt("hideDebuffBorder") then frame.DebuffBorder:Hide() end
    if not fd._debuffHooked then
      fd._debuffHooked = true
      hooksecurefunc(frame.DebuffBorder, "Show", function(self)
        if Opt("hideDebuffBorder") then self:Hide() end
      end)
    end
  end

  -- 4. Pandemic Indicator
  if frame.PandemicIcon then
    if Opt("hidePandemic") then frame.PandemicIcon:Hide() end
    if not fd._pandemicHooked and frame.ShowPandemicStateFrame then
      fd._pandemicHooked = true
      hooksecurefunc(frame, "ShowPandemicStateFrame", function(self)
        if Opt("hidePandemic") and self.PandemicIcon then self.PandemicIcon:Hide() end
      end)
    end
  end

  -- 5. Cooldown Bling
  if frame.Cooldown then
    frame.Cooldown:SetDrawBling(not Opt("hideBling"))
  end
  if frame.CooldownFlash and not fd._blingHooked then
    fd._blingHooked = true
    hooksecurefunc(frame.CooldownFlash, "Show", function(self)
      if Opt("hideBling") then self:Hide(); if self.FlashAnim then self.FlashAnim:Stop() end end
    end)
    if frame.CooldownFlash.FlashAnim and frame.CooldownFlash.FlashAnim.Play then
      hooksecurefunc(frame.CooldownFlash.FlashAnim, "Play", function(self)
        if Opt("hideBling") then self:Stop(); if self:GetParent() then self:GetParent():Hide() end end
      end)
    end
  end
end

-- ── Style buff bar frame ────────────────────────────────────────────────
local function StyleBarFrame(frame, w, h)
  frame:SetSize(w, h)
  local fd = GetFD(frame)
  if frame.Bar then
    frame.Bar:SetStatusBarTexture(NS.GetBarTexturePath(Opt("buffBarTexture")))
    local c = Opt("buffBarColor")
    frame.Bar:SetStatusBarColor(c[1], c[2], c[3])
  end
  if not fd.bg then fd.bg = frame:CreateTexture(nil, "BACKGROUND", nil, -1) end
  fd.bg:ClearAllPoints(); fd.bg:SetAllPoints(frame)
  fd.bg:SetTexture(NS.GetBarTexturePath(Opt("buffBarBgTexture")))
  local bgc = Opt("buffBarBgColor")
  fd.bg:SetVertexColor(bgc[1], bgc[2], bgc[3], bgc[4] or 0.85); fd.bg:Show()
  local fontPath = NS.GetFontPath(Opt("buffBarFont"))
  local fontSize = Opt("buffBarFontSize")
  if frame.Text then frame.Text:SetFont(fontPath, fontSize, "OUTLINE"); frame.Text:SetShown(Opt("buffBarShowName")) end
  if frame.Duration then frame.Duration:SetFont(fontPath, fontSize, "OUTLINE"); frame.Duration:SetShown(Opt("buffBarShowTimer")) end
  -- Hide ALL Blizzard visual elements
  for _, region in ipairs({frame:GetRegions()}) do
    if region:IsObjectType("Texture") and region ~= fd.bg then
      region:SetAlpha(0); region:Hide()
    end
  end
  if frame.Bar then
    -- Kill BarBG permanently via Show hook
    local statusTex = frame.Bar:GetStatusBarTexture()
    for _, region in ipairs({frame.Bar:GetRegions()}) do
      if region ~= statusTex then
        region:SetAlpha(0); region:Hide()
        if not region._luiHooked then
          region._luiHooked = true
          hooksecurefunc(region, "Show", function(self) self:SetAlpha(0); self:Hide() end)
          hooksecurefunc(region, "SetAlpha", function(self, a) if a > 0 then self:SetAlpha(0) end end)
        end
      end
    end
    for _, child in ipairs({frame.Bar:GetChildren()}) do
      child:SetAlpha(0); child:Hide()
    end
  end
  -- All children of frame except what we need
  for _, child in ipairs({frame:GetChildren()}) do
    if child ~= frame.Bar and child ~= frame.Cooldown then
      child:SetAlpha(0); child:Hide()
    end
  end
end

-- ── Layout buff icons ───────────────────────────────────────────────────
local function LayoutBuffIcons()
  local viewer = _G[VIEWER_BUFF_ICON]
  if not viewer or not viewer.itemFramePool then return end
  if not NS.IsCDMEnabled() then return end

  local container = GetContainer(VIEWER_BUFF_ICON)
  local size = Snap(Opt("buffIconSize"))
  local spacing = Snap(Opt("buffIconSpacing"))
  local perRow = Opt("buffIconsPerRow")
  local grow = Opt("buffIconGrow")

  local frames = {}
  for frame in viewer.itemFramePool:EnumerateActive() do
    if frame:IsShown() then frames[#frames + 1] = frame end
  end

  if #frames == 0 then
    container:Hide()
    return
  end
  container:Show()

  table.sort(frames, function(a, b) return (a.layoutIndex or 0) < (b.layoutIndex or 0) end)

  local row, col = 0, 0
  for _, frame in ipairs(frames) do
    HookFrameSetPoint(frame)
    StyleIconFrame(frame, size)
    local xOff = col * (size + spacing)
    local yOff = row * (size + spacing)
    if grow == "RIGHT" then PlaceFrame(frame, container, xOff, -yOff)
    else PlaceFrame(frame, container, -(xOff), -yOff) end
    col = col + 1
    if col >= perRow then col = 0; row = row + 1 end
  end

  local totalCols = math.min(#frames, perRow)
  local totalRows = math.ceil(math.max(1, #frames) / perRow)
  container:SetSize(
    math.max(1, totalCols * (size + spacing) - spacing),
    math.max(1, totalRows * (size + spacing) - spacing)
  )
end

-- ── Layout buff bars ────────────────────────────────────────────────────
local function LayoutBuffBars()
  local viewer = _G[VIEWER_BUFF_BAR]
  if not viewer or not viewer.itemFramePool then return end
  if not NS.IsCDMEnabled() then return end

  local container = GetContainer(VIEWER_BUFF_BAR)
  local w = Snap(Opt("buffBarWidth"))
  local h = Snap(Opt("buffBarHeight"))
  local spacing = Snap(Opt("buffBarSpacing"))
  local grow = Opt("buffBarGrow")

  local frames = {}
  for frame in viewer.itemFramePool:EnumerateActive() do
    if frame:IsShown() then frames[#frames + 1] = frame end
  end

  if #frames == 0 then
    container:Hide()
    return
  end
  container:Show()
  container:SetWidth(w)

  table.sort(frames, function(a, b) return (a.layoutIndex or 0) < (b.layoutIndex or 0) end)

  local yOff = 0
  for _, frame in ipairs(frames) do
    HookFrameSetPoint(frame)
    StyleBarFrame(frame, w, h)
    if grow == "DOWN" then PlaceFrame(frame, container, 0, -yOff)
    else PlaceFrame(frame, container, 0, yOff) end
    yOff = yOff + h + spacing
  end
  container:SetHeight(math.max(1, yOff > 0 and yOff - spacing or 1))
end

-- ── Hook viewer layout systems ──────────────────────────────────────────
local function SetupViewerHooks(viewerName)
  local viewer = _G[viewerName]
  if not viewer then return end

  local layoutFn = viewerName == VIEWER_BUFF_ICON and LayoutBuffIcons or LayoutBuffBars

  if viewer.OnAcquireItemFrame and not hookedViewers[viewerName] then
    hookedViewers[viewerName] = true
    hooksecurefunc(viewer, "OnAcquireItemFrame", function(_, itemFrame)
      if not NS.IsCDMEnabled() then return end
      HookFrameSetPoint(itemFrame)
      GetFD(itemFrame).bbAnchor = nil
      C_Timer.After(0, layoutFn)
    end)
  end

  if not viewer.OnAcquireItemFrame and viewer.itemFramePool and not hookedViewers[viewerName .. "_pool"] then
    hookedViewers[viewerName .. "_pool"] = true
    hooksecurefunc(viewer.itemFramePool, "Acquire", function()
      if not NS.IsCDMEnabled() then return end
      C_Timer.After(0, layoutFn)
    end)
  end

  if viewer.RefreshLayout and not hookedLayouts[viewerName .. "_rl"] then
    hookedLayouts[viewerName .. "_rl"] = true
    hooksecurefunc(viewer, "RefreshLayout", function()
      if not NS.IsCDMEnabled() then return end
      C_Timer.After(0, layoutFn)
    end)
  end

  if viewer.Layout and not hookedLayouts[viewerName .. "_l"] then
    hookedLayouts[viewerName .. "_l"] = true
    hooksecurefunc(viewer, "Layout", function()
      if not NS.IsCDMEnabled() then return end
      C_Timer.After(0, layoutFn)
    end)
  end

  if not hookedLayouts[viewerName .. "_sp"] then
    hookedLayouts[viewerName .. "_sp"] = true
    hooksecurefunc(viewer, "SetPoint", function()
      if not NS.IsCDMEnabled() or InCombatLockdown() then return end
      C_Timer.After(0, layoutFn)
    end)
  end
end

-- ── Public API ──────────────────────────────────────────────────────────
function BB:Refresh()
  LayoutBuffIcons()
  LayoutBuffBars()
end

function BB:Enable()
  for _, name in ipairs({VIEWER_BUFF_ICON, VIEWER_BUFF_BAR}) do
    GetContainer(name)
    SetupViewerHooks(name)
    local viewer = _G[name]
    local container = containers[name]
    -- Snap to chain if no saved position
    if container and container._needsAnchor then
      local chainName = container._needsAnchor
      container._needsAnchor = nil
      if not NS.AnchorToChain(container, chainName) then
        local capContainer, capChain = container, chainName
        C_Timer.After(1.5, function()
          if capContainer and not Opt(name == VIEWER_BUFF_ICON and "buffIconPos" or "buffBarPos") then
            NS.AnchorToChain(capContainer, capChain)
          end
        end)
      end
    end
    if viewer and viewer.itemFramePool and container then
      for frame in viewer.itemFramePool:EnumerateActive() do
        HookFrameSetPoint(frame)
        frame:SetParent(container)
      end
    end
  end
  LayoutBuffIcons()
  LayoutBuffBars()
  -- Dirty-flag ticker: only re-layout when the visible frame count changes.
  -- Eliminates ~3x/sec GetRegions() table allocations per frame in steady state.
  if not BB._lastCounts then BB._lastCounts = {icon=0, bar=0} end
  if not BB._ticker then
    BB._ticker = C_Timer.NewTicker(0.3, function()
      if not NS.IsCDMEnabled() then return end
      if BB._unlocked then return end
      local iconViewer = _G[VIEWER_BUFF_ICON]
      local barViewer  = _G[VIEWER_BUFF_BAR]
      local iconCount, barCount = 0, 0
      if iconViewer and iconViewer.itemFramePool then
        for f in iconViewer.itemFramePool:EnumerateActive() do
          if f:IsShown() then iconCount = iconCount + 1 end
        end
      end
      if barViewer and barViewer.itemFramePool then
        for f in barViewer.itemFramePool:EnumerateActive() do
          if f:IsShown() then barCount = barCount + 1 end
        end
      end
      if iconCount ~= BB._lastCounts.icon then
        BB._lastCounts.icon = iconCount
        LayoutBuffIcons()
      end
      if barCount ~= BB._lastCounts.bar then
        BB._lastCounts.bar = barCount
        LayoutBuffBars()
      end
    end)
  end
  -- Register runtime events (only when module is active)
  evFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
  evFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
  evFrame:RegisterEvent("SPELLS_CHANGED")
  -- Hook mixin to detect when Blizzard assigns a spell to a buff frame (like Ayije)
  if not BB._mixinHooked and _G.CooldownViewerBuffIconItemMixin
     and _G.CooldownViewerBuffIconItemMixin.OnCooldownIDSet then
    BB._mixinHooked = true
    hooksecurefunc(_G.CooldownViewerBuffIconItemMixin, "OnCooldownIDSet", function()
      if not NS.IsCDMEnabled() or not initialized then return end
      C_Timer.After(0, function() LayoutBuffIcons(); LayoutBuffBars() end)
    end)
  end
end

function BB:Disable()
  if BB._ticker then BB._ticker:Cancel(); BB._ticker = nil end
  evFrame:UnregisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
  evFrame:UnregisterEvent("PLAYER_SPECIALIZATION_CHANGED")
  evFrame:UnregisterEvent("SPELLS_CHANGED")
  for _, viewerName in ipairs({VIEWER_BUFF_ICON, VIEWER_BUFF_BAR}) do
    local viewer = _G[viewerName]
    local c = containers[viewerName]
    if c then c:Hide() end
    if viewer and viewer.itemFramePool then
      for frame in viewer.itemFramePool:EnumerateActive() do
        local fd = frameData[frame]
        if fd then
          fd.bbAnchor = nil
          if fd.bg then fd.bg:Hide() end
          if fd.border then for _, b in ipairs(fd.border) do b:Hide() end end
        end
        frame:SetParent(viewer)
      end
      -- Restore viewer position
      if not InCombatLockdown() then
        viewer:SetSize(200, 40)
        viewer:ClearAllPoints(); viewer:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -220, -15)
      end
      if viewer.Layout then pcall(viewer.Layout, viewer) end
    end
  end
end

-- ── Spec Change handling (with backstop timer like Ayije) ───────────────
local specChangePending = false
local specChangeToken = 0

local function OnSpecChange()
  if not initialized or not NS.IsCDMEnabled() then return end
  if specChangePending then return end
  specChangePending = true
  specChangeToken = specChangeToken + 1
  local myToken = specChangeToken
  C_Timer.After(0.5, function()
    specChangePending = false
    if InCombatLockdown() then
      -- Combat blocked us; let backstop handle it
      return
    end
    specChangeToken = specChangeToken + 1  -- cancel backstop only on success
    for k in pairs(frameData) do frameData[k] = nil end
    BB:Refresh()
    C_Timer.After(0.3, function() BB:Refresh() end)
    C_Timer.After(1.0, function() BB:Refresh() end)
  end)
  -- 3s backstop: force refresh if normal path was blocked by combat
  C_Timer.After(3, function()
    if specChangeToken ~= myToken then return end
    specChangePending = false
    specChangeToken = specChangeToken + 1
    if initialized and NS.IsCDMEnabled() and not InCombatLockdown() then
      for k in pairs(frameData) do frameData[k] = nil end
      BB:Refresh()
    end
  end)
end

-- ── Init ────────────────────────────────────────────────────────────────
evFrame = CreateFrame("Frame")
evFrame:RegisterEvent("PLAYER_LOGIN")
evFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
evFrame:RegisterEvent("PLAYER_LOGOUT")
-- Spec/spell events registered in BB:Enable() to avoid waste when disabled
evFrame:SetScript("OnEvent", function(_, event, arg1)
  if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
    if event == "PLAYER_ENTERING_WORLD" then
      if arg1 or initialized then return end -- skip initial login, already init
    end
    if initialized then return end
    if not NS.IsCDMEnabled() then return end
    C_Timer.After(0.5, function()
      if initialized then return end
      initialized = true
      NS.SafeCall(function() BB:Enable() end, "BuffBar")
    end)
  elseif event == "ACTIVE_TALENT_GROUP_CHANGED" or event == "PLAYER_SPECIALIZATION_CHANGED" or event == "SPELLS_CHANGED" then
    OnSpecChange()
  elseif event == "PLAYER_LOGOUT" then
    for _, viewerName in ipairs({VIEWER_BUFF_ICON, VIEWER_BUFF_BAR}) do
      local posKey = viewerName == VIEWER_BUFF_ICON and "buffIconPos" or "buffBarPos"
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

BB._containers = containers

-- ── Settings Tab ────────────────────────────────────────────────────────
function BB.SetupSettings(parent)
  local container = CreateFrame("Frame", nil, parent)
  local MakeCard = NS._SMakeCard
  local MakePage = NS._SMakePage
  local R = NS._SR
  local SBD = NS.BACKDROP
  local sc, Append = MakePage(container)

  local function Toggle(card, label, key, tip)
    local cb = NS.ChatGetCheckbox(card.inner, label, 26, function(s)
      OptSet(key, s)
      if key == "enabled" then if s then BB:Enable() else BB:Disable() end
      else BB:Refresh() end
    end, tip)
    R(card, cb, 26); cb:SetValue(Opt(key) ~= false)
  end
  local function Slider(card, label, key, mn, mx, fmt, default)
    local s; s = NS.ChatGetSlider(card.inner, label, mn, mx, fmt, function()
      OptSet(key, s:GetValue()); BB:Refresh()
    end); R(card, s, 40); s:SetValue(Opt(key) or default)
  end
  local function Dropdown(card, label, labels, values, key, default, maxH)
    local dd = NS.ChatGetDropdown(card.inner, label,
      function(v) return (Opt(key) or default) == v end,
      function(v) OptSet(key, v); BB:Refresh() end)
    dd:Init(labels, values, maxH); R(card, dd, 46)
  end
  local function TogglePair(card, l1, k1, l2, k2)
    local row = CreateFrame("Frame", nil, card.inner); row:SetHeight(26)
    local cb1 = NS.ChatGetCheckbox(row, l1, 26, function(s) OptSet(k1, s); BB:Refresh() end)
    cb1:ClearAllPoints(); cb1:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    cb1:SetPoint("BOTTOMRIGHT", row, "BOTTOM", -2, 0); cb1:SetValue(Opt(k1) ~= false)
    local cb2 = NS.ChatGetCheckbox(row, l2, 26, function(s) OptSet(k2, s); BB:Refresh() end)
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
      function(v) OptSet(k1, v); BB:Refresh() end)
    dd1:Init(labs1, vals1, maxH); dd1:SetParent(lh); dd1:ClearAllPoints(); dd1:SetAllPoints(lh)
    local dd2 = NS.ChatGetDropdown(rh, l2,
      function(v) return (Opt(k2) or def2) == v end,
      function(v) OptSet(k2, v); BB:Refresh() end)
    dd2:Init(labs2, vals2, maxH); dd2:SetParent(rh); dd2:ClearAllPoints(); dd2:SetAllPoints(rh)
    R(card, row, 46)
  end

  -- General
  local cGen = MakeCard(sc, "General")
  local enRow = CreateFrame("Frame", nil, cGen.inner); enRow:SetHeight(26)
  -- Reset button
  local resetBtn = CreateFrame("Button", nil, enRow, "BackdropTemplate"); resetBtn:SetSize(50, 20); resetBtn:SetPoint("RIGHT", -8, 0)
  resetBtn:SetBackdrop(SBD); resetBtn:SetBackdropColor(0.04, 0.04, 0.07, 1); resetBtn:SetBackdropBorderColor(0.12, 0.12, 0.20, 1)
  local resetFS = resetBtn:CreateFontString(nil, "OVERLAY"); resetFS:SetFont(NS.FONT, 9, ""); resetFS:SetPoint("CENTER"); resetFS:SetTextColor(0.65, 0.65, 0.75); resetFS:SetText("Reset")
  resetBtn:SetScript("OnClick", function()
    OptSet("buffIconPos", nil); OptSet("buffBarPos", nil)
    local iconC = containers["BuffIconCooldownViewer"]
    local barC = containers["BuffBarCooldownViewer"]
    if iconC then NS.AnchorToChain(iconC, "BuffIcons") end
    if barC then NS.AnchorToChain(barC, "BuffBars") end
  end)
  resetBtn:SetScript("OnEnter", function() local r,g,b = NS.ChatGetAccentRGB(); resetBtn:SetBackdropBorderColor(r, g, b, 0.8) end)
  resetBtn:SetScript("OnLeave", function() resetBtn:SetBackdropBorderColor(0.12, 0.12, 0.20, 1) end)
  -- Unlock button
  local lockBtn = CreateFrame("Button", nil, enRow, "BackdropTemplate"); lockBtn:SetSize(70, 20); lockBtn:SetPoint("RIGHT", resetBtn, "LEFT", -4, 0)
  lockBtn:SetBackdrop(SBD); lockBtn:SetBackdropColor(0.04, 0.04, 0.07, 1); lockBtn:SetBackdropBorderColor(0.12, 0.12, 0.20, 1)
  local lockFS = lockBtn:CreateFontString(nil, "OVERLAY"); lockFS:SetFont(NS.FONT, 9, ""); lockFS:SetPoint("CENTER"); lockFS:SetTextColor(0.65, 0.65, 0.75); lockFS:SetText("Unlock")
  local unlocked = false
  lockBtn:SetScript("OnClick", function()
    unlocked = not unlocked; BB._unlocked = unlocked
    lockFS:SetText(unlocked and "Lock" or "Unlock")
    local r, g, b = NS.ChatGetAccentRGB()
    if unlocked then lockBtn:SetBackdropBorderColor(r, g, b, 0.8) else lockBtn:SetBackdropBorderColor(0.12, 0.12, 0.20, 1) end
    for _, vn in ipairs({VIEWER_BUFF_ICON, VIEWER_BUFF_BAR}) do
      local c = GetContainer(vn)
      if unlocked then
        -- Ensure container has visible size for dragging
        local label = vn == VIEWER_BUFF_ICON and "Buff Icons" or "Buff Bars"
        local pw = vn == VIEWER_BUFF_ICON and (Opt("buffIconSize") * Opt("buffIconsPerRow")) or Opt("buffBarWidth")
        local ph = vn == VIEWER_BUFF_ICON and Opt("buffIconSize") or (Opt("buffBarHeight") * 3)
        c:SetSize(math.max(pw, 120), math.max(ph, 30))
        local posKey = vn == VIEWER_BUFF_ICON and "buffIconPos" or "buffBarPos"
        c:Show(); c:EnableMouse(true); c:RegisterForDrag("LeftButton")
        c:SetScript("OnDragStart", function(s) s:StartMoving() end)
        c:SetScript("OnDragStop", function(s) s:StopMovingOrSizing()
          local left, top = s:GetLeft(), s:GetTop()
          if left then OptSet(posKey, {p="TOPLEFT", x=left, y=top - GetScreenHeight()}) end
          NS.UpdateMoverPopup()
        end)
        local chainName = vn == VIEWER_BUFF_ICON and "BuffIcons" or "BuffBars"
        NS.ShowMoverPopup(c, label, function(f)
          local left, top = f:GetLeft(), f:GetTop()
          if left then OptSet(posKey, {p="TOPLEFT", x=left, y=top - GetScreenHeight()}) end
        end, function()
          OptSet(posKey, nil)
          NS.AnchorToChain(c, chainName)
        end)
        -- Preview label
        if not c._label then
          c._label = c:CreateFontString(nil, "OVERLAY")
          c._label:SetFont(NS.FONT, 10, "OUTLINE"); c._label:SetPoint("CENTER")
        end
        c._label:SetText(label); c._label:SetTextColor(r, g, b); c._label:Show()
        -- Show all pool frames as preview (even inactive ones)
        local viewer = _G[vn]
        if viewer and viewer.itemFramePool then
          local previewFrames = {}
          for frame in viewer.itemFramePool:EnumerateActive() do
            previewFrames[#previewFrames + 1] = frame
          end
          -- Also show inactive pool frames if no active ones
          if #previewFrames == 0 and viewer.itemFramePool.EnumerateInactive then
            for frame in viewer.itemFramePool:EnumerateInactive() do
              previewFrames[#previewFrames + 1] = frame
              if #previewFrames >= 6 then break end -- limit preview
            end
          end
          if #previewFrames > 0 then
            c._label:Hide() -- hide label if we have frames to show
            if vn == VIEWER_BUFF_ICON then
              local size = Snap(Opt("buffIconSize"))
              local spacing = Snap(Opt("buffIconSpacing"))
              for i, frame in ipairs(previewFrames) do
                frame:SetParent(c); frame:Show(); frame:SetAlpha(0.6)
                frame:SetSize(size, size); frame:ClearAllPoints()
                frame:SetPoint("TOPLEFT", c, "TOPLEFT", (i-1) * (size + spacing), 0)
              end
              c:SetSize(#previewFrames * (size + Opt("buffIconSpacing")), size)
            else
              local bw = Snap(Opt("buffBarWidth"))
              local bh = Snap(Opt("buffBarHeight"))
              local bsp = Snap(Opt("buffBarSpacing"))
              for i, frame in ipairs(previewFrames) do
                frame:SetParent(c); frame:Show(); frame:SetAlpha(0.6)
                frame:SetSize(bw, bh); frame:ClearAllPoints()
                frame:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -(i-1) * (bh + bsp))
              end
              c:SetSize(bw, #previewFrames * (bh + bsp))
            end
          end
        end
      else
        c:EnableMouse(false); c:RegisterForDrag(); c:SetScript("OnDragStart", nil); c:SetScript("OnDragStop", nil)
        NS.HideMoverPopup()
        if c._label then c._label:Hide() end
        -- Reset preview: hide all, reparent back, force Blizzard re-layout
        local viewer = _G[vn]
        if viewer and viewer.itemFramePool then
          for frame in viewer.itemFramePool:EnumerateActive() do
            frame:SetAlpha(1); frame:SetParent(viewer)
          end
          if viewer.itemFramePool.EnumerateInactive then
            for frame in viewer.itemFramePool:EnumerateInactive() do
              frame:SetAlpha(1); frame:SetParent(viewer); frame:Hide()
            end
          end
          -- Force Blizzard to re-layout (like opening/closing CDM window does)
          if viewer.Layout then pcall(viewer.Layout, viewer) end
          if viewer.RefreshLayout then pcall(viewer.RefreshLayout, viewer) end
        end
        -- Then re-apply our layout
        C_Timer.After(0.2, function()
          if not BB._unlocked then BB:Refresh() end
        end)
      end
    end
  end)
  lockBtn:SetScript("OnEnter", function() local r,g,b = NS.ChatGetAccentRGB(); lockBtn:SetBackdropBorderColor(r, g, b, 0.8) end)
  lockBtn:SetScript("OnLeave", function() if not unlocked then lockBtn:SetBackdropBorderColor(0.12, 0.12, 0.20, 1) end end)
  R(cGen, enRow, 26)
  TogglePair(cGen, "Zoom Icons", "zoomIcons", "Show Border", "showBorder")
  TogglePair(cGen, "Duration Text", "showDurationText", "Stack Count", "showStackCount")
  TogglePair(cGen, "Hide Shadow", "hideShadowOverlay", "Hide Mask", "hideIconMask")
  TogglePair(cGen, "Hide Debuff Border", "hideDebuffBorder", "Hide Pandemic", "hidePandemic")
  Toggle(cGen, "Hide Cooldown Bling", "hideBling", "Hide the flash animation when cooldown completes")
  Dropdown(cGen, "Border Texture", BORDER_NAMES, BORDER_NAMES, "borderTexture", "1 Pixel")
  cGen:Finish(); Append(cGen, cGen:GetHeight()); Append(NS._SSep(sc), 9)

  -- Buff Icons
  local cIco = MakeCard(sc, "Buff Icons")
  Slider(cIco, "Icon Size", "buffIconSize", 16, 60, "%spx", 36)
  Slider(cIco, "Spacing", "buffIconSpacing", 0, 10, "%spx", 2)
  Slider(cIco, "Icons Per Row", "buffIconsPerRow", 4, 20, "%s", 12)
  Dropdown(cIco, "Grow Direction", {"Right", "Left"}, {"RIGHT", "LEFT"}, "buffIconGrow", "RIGHT")
  cIco:Finish(); Append(cIco, cIco:GetHeight()); Append(NS._SSep(sc), 9)

  -- Buff Bars
  local cBar = MakeCard(sc, "Buff Bars")
  Slider(cBar, "Width", "buffBarWidth", 80, 400, "%spx", 200)
  Slider(cBar, "Height", "buffBarHeight", 10, 40, "%spx", 20)
  Slider(cBar, "Spacing", "buffBarSpacing", 0, 8, "%spx", 2)
  Dropdown(cBar, "Grow Direction", {"Down", "Up"}, {"DOWN", "UP"}, "buffBarGrow", "DOWN")
  TogglePair(cBar, "Show Timer", "buffBarShowTimer", "Show Name", "buffBarShowName")
  cBar:Finish(); Append(cBar, cBar:GetHeight()); Append(NS._SSep(sc), 9)

  -- Appearance
  local cApp = MakeCard(sc, "Appearance")
  local barTexNames = {}
  local rawBars = NS.GetLSMStatusBars and NS.GetLSMStatusBars() or {}
  for _, b in ipairs(rawBars) do barTexNames[#barTexNames+1] = b.label end
  if #barTexNames == 0 then barTexNames = {"Flat"} end
  DropdownPair(cApp, "Bar Texture", barTexNames, barTexNames, "buffBarTexture", "Flat",
    "Background", barTexNames, barTexNames, "buffBarBgTexture", "Flat", 200)
  local fontNames, fontValues = {"Default"}, {"default"}
  for _, ft in ipairs(NS.GetLSMFonts()) do fontNames[#fontNames+1] = ft.label; fontValues[#fontValues+1] = ft.label end
  Dropdown(cApp, "Font", fontNames, fontValues, "buffBarFont", "default", 200)
  Slider(cApp, "Font Size", "buffBarFontSize", 6, 18, "%spx", 10)
  -- Border Color
  local function ColorRow(card, label, key)
    local row = CreateFrame("Frame", nil, card.inner); row:SetHeight(24)
    local lbl = row:CreateFontString(nil, "OVERLAY"); lbl:SetFont(NS.FONT, 10, "")
    lbl:SetPoint("LEFT", 4, 0); lbl:SetTextColor(0.6, 0.6, 0.7); lbl:SetText(label)
    local cur = Opt(key) or {1,0,0}
    local sw = CreateFrame("Frame", nil, row, "BackdropTemplate"); sw:SetSize(20, 16); sw:SetPoint("LEFT", 110, 0)
    sw:SetBackdrop(SBD); sw:SetBackdropColor(cur[1], cur[2], cur[3], 1); sw:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    local hit = CreateFrame("Button", nil, sw); hit:SetAllPoints()
    hit:SetScript("OnClick", function()
      ColorPickerFrame:SetupColorPickerAndShow({r=cur[1], g=cur[2], b=cur[3],
        swatchFunc = function() local r,g,b = ColorPickerFrame:GetColorRGB(); OptSet(key, {r,g,b}); sw:SetBackdropColor(r,g,b,1); BB:Refresh() end,
        cancelFunc = function() sw:SetBackdropColor(cur[1], cur[2], cur[3], 1) end})
    end)
    R(card, row, 24)
  end
  ColorRow(cApp, "Border Color:", "borderColor")
  cApp:Finish(); Append(cApp, cApp:GetHeight())

  return container
end