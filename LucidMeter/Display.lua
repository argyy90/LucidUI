-- LucidMeter — Display UI with bars and class colors (multi-window)
local NS = LucidUINS
local DM = NS.LucidMeter
local CYAN = NS.CYAN

local MAX_BARS = 20
local TITLE_H = 22
local guidCache = {}

DM.windows = {}

local CLASS_COLORS = {
  WARRIOR     = {0.78, 0.61, 0.43}, PALADIN      = {0.96, 0.55, 0.73},
  HUNTER      = {0.67, 0.83, 0.45}, ROGUE        = {1.00, 0.96, 0.41},
  PRIEST      = {1.00, 1.00, 1.00}, DEATHKNIGHT  = {0.77, 0.12, 0.23},
  SHAMAN      = {0.00, 0.44, 0.87}, MAGE         = {0.41, 0.80, 0.94},
  WARLOCK     = {0.58, 0.51, 0.79}, MONK         = {0.00, 1.00, 0.59},
  DRUID       = {1.00, 0.49, 0.04}, DEMONHUNTER  = {0.64, 0.19, 0.79},
  EVOKER      = {0.20, 0.58, 0.50},
}

local function GetClassColor(class)
  local c = CLASS_COLORS[class and class:upper()]
  return c and c[1] or 0.5, c and c[2] or 0.5, c and c[3] or 0.5
end

local CLASS_ICON_COORDS = {
  WARRIOR     = {0, 0.25, 0, 0.25},       MAGE        = {0.25, 0.5, 0, 0.25},
  ROGUE       = {0.5, 0.75, 0, 0.25},     DRUID       = {0.75, 1, 0, 0.25},
  HUNTER      = {0, 0.25, 0.25, 0.5},     SHAMAN      = {0.25, 0.5, 0.25, 0.5},
  PRIEST      = {0.5, 0.75, 0.25, 0.5},   WARLOCK     = {0.75, 1, 0.25, 0.5},
  PALADIN     = {0, 0.25, 0.5, 0.75},     DEATHKNIGHT = {0.25, 0.5, 0.5, 0.75},
  MONK        = {0.5, 0.75, 0.5, 0.75},   DEMONHUNTER = {0.75, 1, 0.5, 0.75},
  EVOKER      = {0, 0.25, 0.75, 1},
}

-- ── Build a single bar ───────────────────────────────────────────────
local function CreateBar(parent, index)
  local barH = NS.DB("dmBarHeight") or 18
  local bar = CreateFrame("StatusBar", nil, parent)
  bar:SetHeight(barH)
  bar:SetStatusBarTexture(NS.GetBarTexturePath(NS.DB("dmBarTexture")))
  bar:SetMinMaxValues(0, 1)
  bar:SetValue(0)

  local bg = bar:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.05, 0.05, 0.05, 0.8)
  bar._bg = bg

  -- Class/spec icon
  local icon = bar:CreateTexture(nil, "OVERLAY")
  icon:SetSize(barH - 2, barH - 2)
  icon:SetPoint("LEFT", 1, 0)
  icon:Hide()
  bar._icon = icon

  local name = bar:CreateFontString(nil, "OVERLAY")
  name:SetFont("Fonts/FRIZQT__.TTF", NS.DB("dmFontSize") or 11, "")
  name:SetPoint("LEFT", 4, 0)
  name:SetJustifyH("LEFT")
  bar._name = name

  local value = bar:CreateFontString(nil, "OVERLAY")
  value:SetFont("Fonts/FRIZQT__.TTF", NS.DB("dmFontSize") or 11, "")
  value:SetPoint("RIGHT", -4, 0)
  value:SetJustifyH("RIGHT")
  bar._value = value

  bar:Hide()
  return bar
end

-- ── Snap / Anchor system (Details-style: direct frame-to-frame anchors) ──
local SNAP_THRESHOLD = 20
local OPPOSITE_EDGE = {left = "right", right = "left", top = "bottom", bottom = "top"}

local function CreateSnapLines(frame)
  local lines = {}
  local ar, ag, ab = CYAN[1], CYAN[2], CYAN[3]
  for _, edge in ipairs({"left", "right", "top", "bottom"}) do
    local tex = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    tex:SetColorTexture(ar, ag, ab, 0.8); tex:Hide()
    if edge == "left" then
      tex:SetWidth(1); tex:SetPoint("TOPLEFT", 0, 0); tex:SetPoint("BOTTOMLEFT", 0, 0)
    elseif edge == "right" then
      tex:SetWidth(1); tex:SetPoint("TOPRIGHT", 0, 0); tex:SetPoint("BOTTOMRIGHT", 0, 0)
    elseif edge == "top" then
      tex:SetHeight(1); tex:SetPoint("TOPLEFT", 0, 0); tex:SetPoint("TOPRIGHT", 0, 0)
    else
      tex:SetHeight(1); tex:SetPoint("BOTTOMLEFT", 0, 0); tex:SetPoint("BOTTOMRIGHT", 0, 0)
    end
    lines[edge] = tex
  end
  return lines
end

local function HideAllSnapLines()
  for _, w in ipairs(DM.windows) do
    if w.snapLines then
      for _, line in pairs(w.snapLines) do line:Hide() end
    end
  end
end

-- Break all snap connections for a window, re-anchor detached frames to UIParent
local function BreakSnap(w)
  if not w.snappedTo then return end
  for edge, other in pairs(w.snappedTo) do
    if other.snappedTo then other.snappedTo[OPPOSITE_EDGE[edge]] = nil end
    -- Re-anchor the other frame to UIParent at its current position
    local oL, oT = other.frame:GetLeft(), other.frame:GetTop()
    if oL then
      other.frame:ClearAllPoints()
      other.frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", oL, oT)
    end
  end
  -- Re-anchor self to UIParent
  local sL, sT = w.frame:GetLeft(), w.frame:GetTop()
  if sL then
    w.frame:ClearAllPoints()
    w.frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", sL, sT)
  end
  w.snappedTo = {}
end

-- Get all windows connected to w via snap (transitive)
local function GetSnapGroup(w)
  local group = {}
  local visited = {}
  local function visit(win)
    if visited[win.id] then return end
    visited[win.id] = true
    group[#group + 1] = win
    if win.snappedTo then
      for _, other in pairs(win.snappedTo) do visit(other) end
    end
  end
  visit(w)
  return group
end

-- Check proximity and return snap info
local function FindSnapTarget(w, excludeGroup)
  local f = w.frame
  local fL, fT, fR, fB = f:GetLeft(), f:GetTop(), f:GetRight(), f:GetBottom()
  if not fL then return nil end

  for _, other in ipairs(DM.windows) do
    local skip = other.id == w.id
    if not skip and excludeGroup then
      for _, eg in ipairs(excludeGroup) do
        if eg.id == other.id then skip = true; break end
      end
    end
    if not skip and other.frame:IsShown() then
      local oL, oT, oR, oB = other.frame:GetLeft(), other.frame:GetTop(), other.frame:GetRight(), other.frame:GetBottom()
      if not oL then break end

      local vOverlap = (fT > oB + SNAP_THRESHOLD) and (fB < oT - SNAP_THRESHOLD)
      local hOverlap = (fR > oL + SNAP_THRESHOLD) and (fL < oR - SNAP_THRESHOLD)

      if vOverlap and math.abs(fR - oL) < SNAP_THRESHOLD then
        return {edge = "right", other = other}
      end
      if vOverlap and math.abs(fL - oR) < SNAP_THRESHOLD then
        return {edge = "left", other = other}
      end
      if hOverlap and math.abs(fB - oT) < SNAP_THRESHOLD then
        return {edge = "bottom", other = other}
      end
      if hOverlap and math.abs(fT - oB) < SNAP_THRESHOLD then
        return {edge = "top", other = other}
      end
    end
  end
  return nil
end

-- Show preview lines while dragging
local function UpdateSnapPreview(w)
  HideAllSnapLines()
  local group = GetSnapGroup(w)
  local snap = FindSnapTarget(w, group)
  if snap then
    w.snapLines[snap.edge]:Show()
    snap.other.snapLines[OPPOSITE_EDGE[snap.edge]]:Show()
  end
end

-- Flash snap lines briefly, then fade out
local function FlashSnapLines(line1, line2)
  line1:SetAlpha(1); line1:Show()
  line2:SetAlpha(1); line2:Show()
  local elapsed = 0
  local ticker
  ticker = C_Timer.NewTicker(0.016, function()
    elapsed = elapsed + 0.016
    if elapsed >= 0.6 then
      line1:Hide(); line2:Hide()
      line1:SetAlpha(1); line2:SetAlpha(1)
      ticker:Cancel()
      return
    end
    line1:SetAlpha(1 - elapsed / 0.6)
    line2:SetAlpha(1 - elapsed / 0.6)
  end)
end

-- Anchor dragged frame directly to target using multiple SetPoints (Details-style)
-- This locks position AND size, and movement/resize propagates automatically via WoW anchors
local function SnapWindow(w)
  HideAllSnapLines()
  local group = GetSnapGroup(w)
  local snap = FindSnapTarget(w, group)
  if not snap then return false end

  local f = w.frame
  local target = snap.other.frame
  local overlap = (NS.DB("dmWindowBorder") ~= false) and 1 or 2

  f:ClearAllPoints()
  if snap.edge == "right" then
    f:SetPoint("TOPRIGHT", target, "TOPLEFT", overlap, 0)
    f:SetPoint("BOTTOMRIGHT", target, "BOTTOMLEFT", overlap, 0)
  elseif snap.edge == "left" then
    f:SetPoint("TOPLEFT", target, "TOPRIGHT", -overlap, 0)
    f:SetPoint("BOTTOMLEFT", target, "BOTTOMRIGHT", -overlap, 0)
  elseif snap.edge == "bottom" then
    f:SetPoint("BOTTOMLEFT", target, "TOPLEFT", 0, -overlap)
    f:SetPoint("BOTTOMRIGHT", target, "TOPRIGHT", 0, -overlap)
  elseif snap.edge == "top" then
    f:SetPoint("TOPLEFT", target, "BOTTOMLEFT", 0, overlap)
    f:SetPoint("TOPRIGHT", target, "BOTTOMRIGHT", 0, overlap)
  end

  -- Establish snap relationship
  w.snappedTo = w.snappedTo or {}
  snap.other.snappedTo = snap.other.snappedTo or {}
  w.snappedTo[snap.edge] = snap.other
  snap.other.snappedTo[OPPOSITE_EDGE[snap.edge]] = w

  FlashSnapLines(w.snapLines[snap.edge], snap.other.snapLines[OPPOSITE_EDGE[snap.edge]])
  return true
end

-- Save all snap relationships to DB
local function SaveSnapRelations()
  local snaps = {}
  local saved = {}
  for _, w in ipairs(DM.windows) do
    if w.snappedTo then
      for edge, other in pairs(w.snappedTo) do
        local key = math.min(w.id, other.id) .. "-" .. math.max(w.id, other.id) .. "-" .. edge
        if not saved[key] then
          saved[key] = true
          snaps[#snaps + 1] = {id = w.id, edge = edge, otherId = other.id}
        end
      end
    end
  end
  NS.DBSet("dmSnaps", snaps)
end

-- Re-anchor all group members relative to the dragged window
-- so they follow automatically via WoW's anchor system
local function AnchorGroupToDragRoot(dragRoot)
  local group = GetSnapGroup(dragRoot)
  if #group <= 1 then return end

  local overlap = (NS.DB("dmWindowBorder") ~= false) and 1 or 2

  -- First: detach ALL group members from each other → anchor to UIParent at current positions
  -- This prevents circular dependency errors when re-anchoring
  for _, gw in ipairs(group) do
    local l, t = gw.frame:GetLeft(), gw.frame:GetTop()
    if l then
      gw.frame:ClearAllPoints()
      gw.frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
    end
  end

  -- Now re-anchor each non-root member relative to its snap parent
  local anchored = {[dragRoot.id] = true}
  local function anchorFrom(parent)
    if not parent.snappedTo then return end
    for edge, child in pairs(parent.snappedTo) do
      if not anchored[child.id] then
        anchored[child.id] = true
        child.frame:ClearAllPoints()
        if edge == "right" then
          child.frame:SetPoint("TOPLEFT", parent.frame, "TOPRIGHT", -overlap, 0)
          child.frame:SetPoint("BOTTOMLEFT", parent.frame, "BOTTOMRIGHT", -overlap, 0)
        elseif edge == "left" then
          child.frame:SetPoint("TOPRIGHT", parent.frame, "TOPLEFT", overlap, 0)
          child.frame:SetPoint("BOTTOMRIGHT", parent.frame, "BOTTOMLEFT", overlap, 0)
        elseif edge == "bottom" then
          child.frame:SetPoint("TOPLEFT", parent.frame, "BOTTOMLEFT", 0, overlap)
          child.frame:SetPoint("TOPRIGHT", parent.frame, "BOTTOMRIGHT", 0, overlap)
        elseif edge == "top" then
          child.frame:SetPoint("BOTTOMLEFT", parent.frame, "TOPLEFT", 0, -overlap)
          child.frame:SetPoint("BOTTOMRIGHT", parent.frame, "TOPRIGHT", 0, -overlap)
        end
        anchorFrom(child)
      end
    end
  end
  anchorFrom(dragRoot)
end

-- Restore snap relationships from DB (called after all windows are created)
local function RestoreSnapRelations()
  local snaps = NS.DB("dmSnaps")
  if not snaps or #snaps == 0 then return end

  local byId = {}
  for _, w in ipairs(DM.windows) do byId[w.id] = w end

  for _, s in ipairs(snaps) do
    local w = byId[s.id]
    local other = byId[s.otherId]
    if w and other then
      w.snappedTo = w.snappedTo or {}
      other.snappedTo = other.snappedTo or {}
      w.snappedTo[s.edge] = other
      other.snappedTo[OPPOSITE_EDGE[s.edge]] = w
    end
  end

  -- Re-anchor using first window of each group as root
  local done = {}
  for _, w in ipairs(DM.windows) do
    if not done[w.id] and w.snappedTo and next(w.snappedTo) then
      local group = GetSnapGroup(w)
      AnchorGroupToDragRoot(group[1])
      for _, gw in ipairs(group) do done[gw.id] = true end
    end
  end
end

-- ── Per-window data fetch ────────────────────────────────────────────
local function RefreshWindowData(w)
  if not DM.available then return end
  local ok, session
  if w.sessionID then
    ok, session = pcall(C_DamageMeter.GetCombatSessionFromID, w.sessionID, w.meterType)
  else
    ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, w.sessionType, w.meterType)
  end
  if not ok or not session then return end
  w.sessionData = session
end

-- ── Save helpers ─────────────────────────────────────────────────────
local function SaveWindowPosSize(w)
  -- Always save absolute screen position (GetLeft/GetTop) to handle frame-to-frame anchors
  local l, t = w.frame:GetLeft(), w.frame:GetTop()
  if not l then return end
  local posData = {point = "TOPLEFT", x = l, y = t}
  local sizeData = {w = w.frame:GetWidth(), h = w.frame:GetHeight()}
  if w.id == 1 then
    NS.DBSet("dmWinPos", posData)
    NS.DBSet("dmWinSize", sizeData)
  else
    local extra = NS.DB("dmExtraWindows") or {}
    for _, ew in ipairs(extra) do
      if ew.id == w.id then
        ew.pos = posData
        ew.size = sizeData
        break
      end
    end
    NS.DBSet("dmExtraWindows", extra)
  end
end

local function SaveWindowState(w)
  if w.id == 1 then
    NS.DBSet("dmMeterType", w.meterType)
    NS.DBSet("dmSessionType", w.sessionType)
  else
    local extra = NS.DB("dmExtraWindows") or {}
    for _, ew in ipairs(extra) do
      if ew.id == w.id then
        ew.meterType = w.meterType
        ew.sessionType = w.sessionType
        break
      end
    end
    NS.DBSet("dmExtraWindows", extra)
  end
end

-- ── SESSION_LABELS ───────────────────────────────────────────────────
local SESSION_LABELS = {[0] = "Overall", [1] = "Current", [2] = "Previous"}

-- ── Create a meter window ────────────────────────────────────────────
local function CreateWindow(windowID, config)
  config = config or {}
  local w = {
    id = windowID,
    bars = {},
    meterType = config.meterType or 0,
    sessionType = config.sessionType or 1,
    sessionID = nil,
    sessionData = nil,
  }

  local winW = (windowID == 1) and 200 or 320
  local winH = 220

  local frameName = (windowID == 1) and "LucidMeterFrame" or ("LucidMeterFrame" .. windowID)
  local frame = CreateFrame("Frame", frameName, UIParent, "BackdropTemplate")
  frame:SetSize(winW, winH)
  frame:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8X8",
    edgeFile = "Interface/Buttons/WHITE8X8",
    edgeSize = 1,
  })
  frame:SetBackdropColor(0, 0, 0, 0)
  local showWinBorder = NS.DB("dmWindowBorder") ~= false
  frame:SetBackdropBorderColor(0.15, 0.15, 0.15, showWinBorder and 1 or 0)

  -- Body background
  local bodyBg = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
  bodyBg:SetPoint("TOPLEFT", 1, -TITLE_H)
  bodyBg:SetPoint("BOTTOMRIGHT", -1, 1)
  bodyBg:SetColorTexture(0.03, 0.03, 0.03, 1)
  bodyBg:SetAlpha(NS.DB("dmBgAlpha") or 0.92)
  frame._bodyBg = bodyBg
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)

  w.frame = frame
  w.snapLines = CreateSnapLines(frame)

  local function OnDragStart()
    if NS.DB("dmLocked") then return end
    -- Re-anchor all group members relative to this frame so they follow via WoW anchors
    AnchorGroupToDragRoot(w)
    HideAllSnapLines()
    frame:StartMoving()
    frame:SetScript("OnUpdate", function() UpdateSnapPreview(w) end)
  end

  local function OnDragStop()
    frame:StopMovingOrSizing()
    frame:SetScript("OnUpdate", nil)
    HideAllSnapLines()
    SnapWindow(w)
    SaveSnapRelations()
    -- Save positions for all group members
    local group = GetSnapGroup(w)
    for _, gw in ipairs(group) do SaveWindowPosSize(gw) end
  end

  -- Restore position and size
  local pos = config.pos
  if pos then
    if pos.point == "TOPLEFT" then
      frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x or 0, pos.y or 0)
    else
      frame:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER", pos.x or 0, pos.y or 0)
    end
  else
    if windowID == 1 then
      frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -20, 200)
    else
      -- Extra windows spawn centered, slightly offset so they don't overlap
      local offset = (windowID - 2) * 30
      frame:SetPoint("CENTER", UIParent, "CENTER", offset, -offset)
    end
  end
  local savedSize = config.size
  if savedSize then
    frame:SetSize(savedSize.w or winW, savedSize.h or winH)
  end

  -- Drag to move
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", OnDragStart)
  frame:SetScript("OnDragStop", OnDragStop)

  -- Title bar
  local titleBar = CreateFrame("Frame", nil, frame)
  titleBar:SetHeight(TITLE_H)
  titleBar:SetPoint("TOPLEFT", 0, 0)
  titleBar:SetPoint("TOPRIGHT", 0, 0)

  local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
  titleBg:SetAllPoints()
  titleBg:SetColorTexture(0.03, 0.03, 0.03, 1)
  titleBg:SetAlpha(NS.DB("dmTitleAlpha") or 1)
  frame._titleBg = titleBg

  -- Title bar bottom border line
  local titleBorder = titleBar:CreateTexture(nil, "OVERLAY")
  titleBorder:SetHeight(1)
  titleBorder:SetPoint("BOTTOMLEFT", 0, 0)
  titleBorder:SetPoint("BOTTOMRIGHT", 0, 0)
  titleBorder:SetColorTexture(0.15, 0.15, 0.15, 1)
  titleBorder:SetShown(NS.DB("dmTitleBorder") ~= false)
  frame._titleBorder = titleBorder

  local titleText = titleBar:CreateFontString(nil, "OVERLAY")
  titleText:SetFont(NS.GetFontPath(NS.DB("dmFont")), NS.DB("dmTitleFontSize") or 10, NS.DB("dmTextOutline") and "OUTLINE" or "")
  titleText:SetPoint("LEFT", 6, 0)
  local tCol = NS.DB("dmTitleColor") or {r=1, g=1, b=1}
  titleText:SetTextColor(tCol.r, tCol.g, tCol.b)
  local shadowVal = NS.DB("dmFontShadow") or 0
  if type(shadowVal) == "boolean" then shadowVal = shadowVal and 1.5 or 0 end
  if shadowVal > 0 then
    titleText:SetShadowOffset(shadowVal, -shadowVal); titleText:SetShadowColor(0, 0, 0, 1)
  end
  frame._titleText = titleText
  w.titleText = titleText

  -- ── Simple popup menu that opens ABOVE the anchor ───────────────────
  local popupMenu = nil
  local popupCloseTicker = nil
  local function OpenMenuAbove(anchor, items)
    if popupCloseTicker then popupCloseTicker:Cancel(); popupCloseTicker = nil end
    if popupMenu then popupMenu:Hide() end
    popupMenu = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    popupMenu:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
    popupMenu:SetBackdropColor(0.06, 0.06, 0.06, 0.97)
    popupMenu:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    popupMenu:SetFrameStrata("TOOLTIP")
    popupMenu:SetClampedToScreen(true)

    local ITEM_H = 18
    local MENU_W = 160
    local totalH = 0
    local btns = {}

    for _, item in ipairs(items) do
      if item.divider then
        local div = popupMenu:CreateTexture(nil, "OVERLAY")
        div:SetHeight(1)
        div:SetPoint("TOPLEFT", 4, -(totalH + 4))
        div:SetPoint("TOPRIGHT", -4, -(totalH + 4))
        div:SetColorTexture(0.25, 0.25, 0.25, 1)
        totalH = totalH + 9
      elseif item.title then
        local lbl = popupMenu:CreateFontString(nil, "OVERLAY")
        lbl:SetFont("Fonts/FRIZQT__.TTF", 10, "")
        lbl:SetPoint("TOPLEFT", 8, -(totalH + 2))
        lbl:SetText(item.text)
        lbl:SetTextColor(0.5, 0.5, 0.5)
        totalH = totalH + ITEM_H
      else
        local btn = CreateFrame("Button", nil, popupMenu)
        btn:SetHeight(ITEM_H)
        btn:SetPoint("TOPLEFT", 2, -(totalH))
        btn:SetPoint("TOPRIGHT", -2, -(totalH))
        local hl = btn:CreateTexture(nil, "BACKGROUND")
        hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.06); hl:Hide()
        btn:SetScript("OnEnter", function() hl:Show() end)
        btn:SetScript("OnLeave", function() hl:Hide() end)
        local lbl = btn:CreateFontString(nil, "OVERLAY")
        lbl:SetFont("Fonts/FRIZQT__.TTF", 10, "")
        lbl:SetPoint("LEFT", 8, 0)
        lbl:SetText(item.text)
        lbl:SetTextColor(0.85, 0.85, 0.85)
        local cb = item.func
        btn:SetScript("OnClick", function() if cb then cb() end; popupMenu:Hide() end)
        totalH = totalH + ITEM_H
        btns[#btns + 1] = btn
      end
    end

    popupMenu:SetSize(MENU_W, totalH + 6)
    popupMenu:ClearAllPoints()
    popupMenu:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 2)
    popupMenu:Show()

    -- Auto-close: poll every 0.5s
    popupCloseTicker = C_Timer.NewTicker(0.5, function()
      if not popupMenu or not popupMenu:IsShown() then
        if popupCloseTicker then popupCloseTicker:Cancel(); popupCloseTicker = nil end
        return
      end
      local overMenu = popupMenu:IsMouseOver()
      local overAnchor = anchor:IsMouseOver()
      if not overMenu and not overAnchor then
        popupMenu:Hide()
        if popupCloseTicker then popupCloseTicker:Cancel(); popupCloseTicker = nil end
      end
    end)
  end

  -- Titlebar: drag to move, scroll to cycle meter type
  titleBar:EnableMouse(true)
  titleBar:EnableMouseWheel(true)
  titleBar:RegisterForDrag("LeftButton")
  titleBar:SetScript("OnDragStart", OnDragStart)
  titleBar:SetScript("OnDragStop", OnDragStop)
  -- ── Titlebar icon helper ───────────────────────────────────────────
  local function MakeTitleIcon(parent, size, texture)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(size, size)
    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetSize(size - 2, size - 2)
    tex:SetPoint("CENTER")
    tex:SetTexture(texture)
    tex:SetVertexColor(0.55, 0.55, 0.55)
    btn._tex = tex
    btn:SetScript("OnEnter", function() tex:SetVertexColor(CYAN[1], CYAN[2], CYAN[3]) end)
    btn:SetScript("OnLeave", function() tex:SetVertexColor(0.55, 0.55, 0.55); GameTooltip:Hide() end)
    return btn
  end

  -- helper: select a meter type for this window
  local function SelectMeterType(id)
    w.meterType = id
    SaveWindowState(w)
    RefreshWindowData(w)
    DM.UpdateWindowDisplay(w)
  end

  local function SelectSessionType(stype)
    w.sessionID = nil
    w.sessionType = stype
    SaveWindowState(w)
    RefreshWindowData(w)
    DM.UpdateWindowDisplay(w)
  end

  -- ── Settings button ─────────────────────────────────────────────────
  local settingsBtn = MakeTitleIcon(titleBar, 16, "Interface/AddOns/LucidUI/Assets/Cog.png")
  settingsBtn:SetPoint("RIGHT", -3, 0)
  settingsBtn:SetScript("OnClick", function()
    NS.BuildChatOptionsWindow()
    if NS.chatOptWin and NS.chatOptWin._selectTab then
      for i, c in ipairs(NS.chatOptWin.containers) do
        if c.button and c.button.label and c.button.label:GetText() == "LucidMeter" then
          NS.chatOptWin._selectTab(i)
          break
        end
      end
    end
  end)

  -- ── Report button ──────────────────────────────────────────────────
  local reportBtn = MakeTitleIcon(titleBar, 16, "Interface/AddOns/LucidUI/Assets/Waves.png")
  reportBtn:SetPoint("RIGHT", settingsBtn, "LEFT", -1, 0)
  reportBtn:HookScript("OnEnter", function(self)
    OpenMenuAbove(self, {{text = "Report Results", func = function() DM.OpenReportWindow(w) end}})
  end)

  -- ── Reset button (context menu: reset all / reset this window) ─────
  local resetBtn = MakeTitleIcon(titleBar, 16, "Interface/AddOns/LucidUI/Assets/Reset.png")
  resetBtn:SetPoint("RIGHT", reportBtn, "LEFT", -1, 0)
  resetBtn:HookScript("OnEnter", function(self)
    local hasSnap = w.snappedTo and next(w.snappedTo)
    local items = {
      {text = "Reset All Windows", func = function() DM.Reset() end},
      {text = "Reset This Window", func = function()
        w.sessionData = nil
        RefreshWindowData(w)
        DM.UpdateWindowDisplay(w)
      end},
    }
    if hasSnap then
      items[#items + 1] = {divider = true}
      items[#items + 1] = {text = "Unsnap Window", func = function()
        BreakSnap(w)
        HideAllSnapLines()
        SaveSnapRelations()
      end}
    end
    OpenMenuAbove(self, items)
  end)

  -- ── Session type button ─────────────────────────────────────────────
  local sessionBtn = MakeTitleIcon(titleBar, 16, "Interface/AddOns/LucidUI/Assets/Session.png")
  sessionBtn:SetPoint("RIGHT", resetBtn, "LEFT", -1, 0)
  sessionBtn:HookScript("OnEnter", function(self)
    local ar, ag, ab = NS.ChatGetAccentRGB()
    local aHex = string.format("%02x%02x%02x", ar*255, ag*255, ab*255)
    local isSecret = issecretvalue or function() return false end
    local items = {}
    for _, stype in ipairs({1, 0}) do
      local label = SESSION_LABELS[stype]
      local isCur = (w.sessionID == nil and w.sessionType == stype)
      local capturedType = stype
      items[#items + 1] = {text = isCur and ("|cff" .. aHex .. label .. "|r") or label, func = function() SelectSessionType(capturedType) end}
    end
    local sessions = DM.GetAvailableSessions()
    if #sessions > 0 then
      items[#items + 1] = {divider = true}
      for _, s in ipairs(sessions) do
        local name = s.name
        local sid = s.sessionID
        if name and not isSecret(name) then
          local dur = ""
          if s.durationSeconds and not isSecret(s.durationSeconds) then
            local secs = math.floor(s.durationSeconds)
            dur = string.format(" (%d:%02d)", math.floor(secs / 60), secs % 60)
          end
          local isCur = (w.sessionID == sid)
          local capturedID = sid
          items[#items + 1] = {text = isCur and ("|cff" .. aHex .. name .. dur .. "|r") or (name .. dur), func = function()
            w.sessionID = capturedID
            w.sessionType = nil
            SaveWindowState(w)
            RefreshWindowData(w)
            DM.UpdateWindowDisplay(w)
          end}
        end
      end
    end
    OpenMenuAbove(self, items)
  end)

  -- ── Meter type button ───────────────────────────────────────────────
  local meterBtn = MakeTitleIcon(titleBar, 16, "Interface/AddOns/LucidUI/Assets/Type.png")
  meterBtn:SetPoint("RIGHT", sessionBtn, "LEFT", -1, 0)
  meterBtn:HookScript("OnEnter", function(self)
    local ar, ag, ab = NS.ChatGetAccentRGB()
    local aHex = string.format("%02x%02x%02x", ar*255, ag*255, ab*255)
    local items = {}
    -- Damage group
    items[#items + 1] = {title = true, text = "|cff808080Damage|r"}
    for _, mt in ipairs({{0, "Damage Done"}, {1, "DPS"}, {7, "Damage Taken"}, {8, "Avoidable Damage"}}) do
      local id, label = mt[1], mt[2]
      local capturedId = id
      items[#items + 1] = {text = (w.meterType == id) and ("|cff" .. aHex .. label .. "|r") or label, func = function() SelectMeterType(capturedId) end}
    end
    -- Healing group
    items[#items + 1] = {divider = true}
    items[#items + 1] = {title = true, text = "|cff808080Healing|r"}
    for _, mt in ipairs({{2, "Healing Done"}, {3, "HPS"}, {4, "Absorbs"}}) do
      local id, label = mt[1], mt[2]
      local capturedId = id
      items[#items + 1] = {text = (w.meterType == id) and ("|cff" .. aHex .. label .. "|r") or label, func = function() SelectMeterType(capturedId) end}
    end
    -- Utility group
    items[#items + 1] = {divider = true}
    items[#items + 1] = {title = true, text = "|cff808080Utility|r"}
    for _, mt in ipairs({{5, "Interrupts"}, {6, "Dispels"}, {9, "Deaths"}}) do
      local id, label = mt[1], mt[2]
      local capturedId = id
      items[#items + 1] = {text = (w.meterType == id) and ("|cff" .. aHex .. label .. "|r") or label, func = function() SelectMeterType(capturedId) end}
    end
    OpenMenuAbove(self, items)
  end)

  -- Accent line under title
  local accentLine = titleBar:CreateTexture(nil, "OVERLAY")
  accentLine:SetHeight(1)
  accentLine:SetPoint("BOTTOMLEFT", 0, 0)
  accentLine:SetPoint("BOTTOMRIGHT", 0, 0)
  accentLine:SetColorTexture(CYAN[1], CYAN[2], CYAN[3], 0.5)
  accentLine:SetShown(NS.DB("dmAccentLine") ~= false)
  frame._accentLine = accentLine

  -- Scroll area for bars
  local barContainer = CreateFrame("Frame", nil, frame)
  barContainer:SetPoint("TOPLEFT", 2, -TITLE_H - 2)
  barContainer:SetPoint("BOTTOMRIGHT", -2, 2)
  frame._barContainer = barContainer
  w.barContainer = barContainer

  -- Pre-create bars
  for i = 1, MAX_BARS do
    w.bars[i] = CreateBar(barContainer, i)
  end

  -- Resize support
  frame:SetResizable(true)
  frame:SetResizeBounds(150, 100, 400, 600)
  local resizeBtn = CreateFrame("Button", nil, frame)
  resizeBtn:SetSize(12, 12)
  resizeBtn:SetPoint("BOTTOMRIGHT", -1, 1)
  resizeBtn:SetNormalTexture("Interface/AddOns/LucidUI/Assets/resize.png")
  resizeBtn:GetNormalTexture():SetVertexColor(0.4, 0.4, 0.4)
  resizeBtn:SetScript("OnMouseDown", function()
    if NS.DB("dmLocked") then return end
    -- Re-anchor group so anchored frames resize automatically
    AnchorGroupToDragRoot(w)
    frame:StartSizing("BOTTOMRIGHT")
  end)
  resizeBtn:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()
    -- Save all group members
    local group = GetSnapGroup(w)
    for _, gw in ipairs(group) do SaveWindowPosSize(gw) end
  end)
  resizeBtn:SetShown(not NS.DB("dmLocked"))
  frame._resizeBtn = resizeBtn

  -- Icons on mouse over: hide/show titlebar icons based on hover
  local titleIcons = {settingsBtn, reportBtn, resetBtn, sessionBtn, meterBtn}
  frame._titleIcons = titleIcons

  local function IsMouseOverWindow()
    if frame:IsMouseOver() then return true end
    for _, ic in ipairs(titleIcons) do
      if ic:IsMouseOver() then return true end
    end
    return false
  end

  local function UpdateIconVisibility(show)
    if NS.DB("dmIconsOnHover") then
      for _, ic in ipairs(titleIcons) do ic:SetShown(show) end
    else
      for _, ic in ipairs(titleIcons) do ic:Show() end
    end
  end

  local function DelayedHide()
    C_Timer.After(0.25, function()
      if frame and not IsMouseOverWindow() then UpdateIconVisibility(false) end
    end)
  end

  frame:HookScript("OnEnter", function() UpdateIconVisibility(true) end)
  frame:HookScript("OnLeave", DelayedHide)
  titleBar:HookScript("OnEnter", function() UpdateIconVisibility(true) end)
  titleBar:HookScript("OnLeave", DelayedHide)
  for _, ic in ipairs(titleIcons) do
    ic:HookScript("OnLeave", DelayedHide)
  end
  UpdateIconVisibility(false)

  return w
end

-- ── Build display: creates main window + restores extra windows ──────
function DM.BuildDisplay()
  -- Main window (ID 1)
  if #DM.windows == 0 then
    local mainConfig = {
      meterType = NS.DB("dmMeterType") or 0,
      sessionType = NS.DB("dmSessionType") or 1,
      pos = NS.DB("dmWinPos"),
      size = NS.DB("dmWinSize"),
    }
    local mainWin = CreateWindow(1, mainConfig)
    DM.windows[1] = mainWin
    NS.dmWin = mainWin.frame

    -- Restore extra windows
    local extra = NS.DB("dmExtraWindows") or {}
    for _, ew in ipairs(extra) do
      local w = CreateWindow(ew.id, {
        meterType = ew.meterType or 0,
        sessionType = ew.sessionType or 1,
        pos = ew.pos,
        size = ew.size,
      })
      DM.windows[#DM.windows + 1] = w
    end
  else
    -- Already built, just show all
    for _, w in ipairs(DM.windows) do
      w.frame:Show()
    end
  end

  RestoreSnapRelations()
  DM.UpdateDisplay()
end

-- ── Create a new extra window ────────────────────────────────────────
function DM.CreateNewWindow()
  -- Find next free ID (lowest available starting from 2)
  local usedIDs = {}
  for _, w in ipairs(DM.windows) do usedIDs[w.id] = true end
  local nextID = 2
  while usedIDs[nextID] do nextID = nextID + 1 end

  local extra = NS.DB("dmExtraWindows") or {}
  local newEntry = {id = nextID, meterType = 0, sessionType = 1}
  extra[#extra + 1] = newEntry
  NS.DBSet("dmExtraWindows", extra)

  local w = CreateWindow(nextID, newEntry)
  DM.windows[#DM.windows + 1] = w

  RefreshWindowData(w)
  DM.UpdateWindowDisplay(w)
  w.frame:Show()
end

-- ── Close and destroy an extra window ────────────────────────────────
function DM.CloseWindow(windowID)
  if windowID == 1 then return end  -- can't close main window
  -- Remove from DM.windows
  for i, w in ipairs(DM.windows) do
    if w.id == windowID then
      w.frame:Hide()
      w.frame:SetParent(nil)
      table.remove(DM.windows, i)
      break
    end
  end
  -- Remove from DB
  local extra = NS.DB("dmExtraWindows") or {}
  for i, ew in ipairs(extra) do
    if ew.id == windowID then
      table.remove(extra, i)
      break
    end
  end
  NS.DBSet("dmExtraWindows", extra)
end

-- ── Get meter label for a specific type ──────────────────────────────
local function GetMeterLabelForType(meterType)
  for _, mt in ipairs(DM.METER_TYPES) do
    if mt.id == meterType then return mt.label end
  end
  return "Damage Done"
end

-- ── Update title text for a single window ────────────────────────────
local function UpdateWindowTitle(w)
  if not w.titleText then return end
  local label = GetMeterLabelForType(w.meterType)
  local timeStr = ""
  if w.id == 1 then
    if DM.inCombat and DM.combatStartTime > 0 then
      local secs = math.floor(GetTime() - DM.combatStartTime)
      timeStr = string.format("%02d:%02d ", math.floor(secs / 60), secs % 60)
    else
      local isSecret = issecretvalue or function() return false end
      local dur = w.sessionData and w.sessionData.durationSeconds
      if dur and not isSecret(dur) then
        local secs = math.floor(dur)
        timeStr = string.format("%02d:%02d ", math.floor(secs / 60), secs % 60)
      end
    end
  end
  local suffix = ""
  if w.sessionID == nil and w.sessionType == 0 then suffix = " (Overall)" end
  w.titleText:SetText(timeStr .. label .. suffix)
end

-- ── Update bars for a single window ──────────────────────────────────
function DM.UpdateWindowDisplay(w)
  if not w or not w.frame then return end

  local isSecret = issecretvalue or function() return false end

  -- Visibility check
  local showInCombatOnly = NS.DB("dmShowInCombatOnly")
  if showInCombatOnly and not DM.inCombat then
    local cs = w.sessionData and w.sessionData.combatSources
    if not cs or isSecret(cs) or #cs == 0 then
      w.frame:Hide()
      return
    end
  end
  if NS.DB("dmEnabled") then w.frame:Show() end

  UpdateWindowTitle(w)

  -- Get sorted sources from this window's session data
  local sources = {}
  if w.sessionData then
    local cs = w.sessionData.combatSources
    if cs and not isSecret(cs) then
      local ok = pcall(function()
        for i = 1, #cs do sources[#sources + 1] = cs[i] end
      end)
      if ok and #sources > 0 and not isSecret(sources[1].totalAmount) then
        table.sort(sources, function(a, b) return (a.totalAmount or 0) > (b.totalAmount or 0) end)
      end
    end
  end

  local maxVal = w.sessionData and w.sessionData.maxAmount or 1
  local barH = NS.DB("dmBarHeight") or 18
  local barSpacing = NS.DB("dmBarSpacing") or 1
  local fontSize = NS.DB("dmFontSize") or 11
  local iconMode = NS.DB("dmIconMode") or "spec"
  local valFormat = NS.DB("dmValueFormat") or "both"
  local barTexture = NS.GetBarTexturePath(NS.DB("dmBarTexture"))
  local fontShadowVal = NS.DB("dmFontShadow") or 0
  if type(fontShadowVal) == "boolean" then fontShadowVal = fontShadowVal and 1.5 or 0 end
  local fontFlags = NS.DB("dmTextOutline") and "OUTLINE" or ""
  local iconSize = barH - 2
  local hasIcon = (iconMode ~= "none")
  local nameOffset = hasIcon and (iconSize + 4) or 4

  for i = 1, MAX_BARS do
    local bar = w.bars[i]
    local src = sources[i]
    if src then
      local cr, cg, cb
      if NS.DB("dmClassColors") ~= false then
        cr, cg, cb = GetClassColor(src.classFilename)
      else
        local bc = NS.DB("dmBarColor") or {r=0.5, g=0.5, b=0.5}
        cr, cg, cb = bc.r, bc.g, bc.b
      end
      bar:SetStatusBarTexture(barTexture)
      local barAlpha = NS.DB("dmBarBrightness") or 0.70
      bar:SetStatusBarColor(cr, cg, cb, barAlpha)

      local total = src.totalAmount or 0
      local perSec = src.amountPerSecond or 0

      bar:SetMinMaxValues(0, maxVal)
      bar:SetValue(total)

      -- Icon: spec or class
      bar._icon:SetSize(iconSize, iconSize)
      if iconMode == "spec" and src.specIconID and not isSecret(src.specIconID) and src.specIconID > 0 then
        bar._icon:SetTexture(src.specIconID)
        bar._icon:SetTexCoord(0, 1, 0, 1)
        bar._icon:Show()
      elseif iconMode ~= "none" and src.classFilename and not isSecret(src.classFilename) then
        local coords = CLASS_ICON_COORDS[src.classFilename:upper()]
        if coords then
          bar._icon:SetTexture("Interface/GLUES/CHARACTERCREATE/UI-CHARACTERCREATE-CLASSES")
          bar._icon:SetTexCoord(unpack(coords))
          bar._icon:Show()
        else
          bar._icon:Hide()
        end
      else
        bar._icon:Hide()
      end

      -- Name
      local srcName = src.name
      if not isSecret(srcName) and srcName then
        if not NS.DB("dmShowRealm") or src.isLocalPlayer then
          srcName = srcName:match("^([^%-]+)") or srcName
        end
      end
      bar._name:ClearAllPoints()
      bar._name:SetPoint("LEFT", nameOffset, 0)
      bar._name:SetText(srcName or "?")
      bar._name:SetTextColor(1, 1, 1)
      bar._name:SetFont(NS.GetFontPath(NS.DB("dmFont")), fontSize, fontFlags)
      if fontShadowVal > 0 then
        bar._name:SetShadowOffset(fontShadowVal, -fontShadowVal); bar._name:SetShadowColor(0, 0, 0, 1)
      else
        bar._name:SetShadowOffset(0, 0)
      end

      -- Value
      local fmtTotal = AbbreviateNumbers(total)
      local fmtPerSec = AbbreviateNumbers(perSec)

      if valFormat == "both" then
        bar._value:SetFormattedText("%s | %s", fmtTotal, fmtPerSec)
      elseif valFormat == "persec" then
        bar._value:SetText(fmtPerSec)
      else
        bar._value:SetText(fmtTotal)
      end
      bar._value:SetTextColor(1, 1, 1)
      bar._value:SetFont(NS.GetFontPath(NS.DB("dmFont")), fontSize, fontFlags)
      if fontShadowVal > 0 then
        bar._value:SetShadowOffset(fontShadowVal, -fontShadowVal); bar._value:SetShadowColor(0, 0, 0, 1)
      else
        bar._value:SetShadowOffset(0, 0)
      end

      bar:SetHeight(barH)
      bar:ClearAllPoints()
      bar:SetPoint("TOPLEFT", w.barContainer, "TOPLEFT", 0, -((i - 1) * (barH + barSpacing)))
      bar:SetPoint("RIGHT", w.barContainer, "RIGHT", 0, 0)
      bar:Show()

      bar._bg:SetColorTexture(0.05, 0.05, 0.05, 0.8)

      -- Bar highlight on hover
      if not bar._hlBorder then
        local hlB = CreateFrame("Frame", nil, bar, "BackdropTemplate")
        hlB:SetAllPoints()
        hlB:SetBackdrop({edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
        hlB:SetFrameLevel(bar:GetFrameLevel() + 2)
        hlB:Hide()
        bar._hlBorder = hlB
      end
      if not bar._hlOverlay then
        local hlO = bar:CreateTexture(nil, "OVERLAY", nil, 1)
        hlO:SetAllPoints()
        hlO:SetColorTexture(1, 1, 1, 0.15)
        hlO:Hide()
        bar._hlOverlay = hlO
      end
      local hlMode = NS.DB("dmBarHighlight") or "none"
      local isHovered = bar:IsMouseOver()
      if hlMode == "border" then
        bar._hlOverlay:Hide()
        if isHovered then
          local ar2, ag2, ab2 = NS.ChatGetAccentRGB()
          bar._hlBorder:SetBackdropBorderColor(ar2, ag2, ab2, 0.8)
          bar._hlBorder:Show()
        else
          bar._hlBorder:Hide()
        end
        bar:SetScript("OnEnter", function(self)
          local ar2, ag2, ab2 = NS.ChatGetAccentRGB()
          bar._hlBorder:SetBackdropBorderColor(ar2, ag2, ab2, 0.8)
          bar._hlBorder:Show()
          DM.ShowSpellBreakdown(self)
        end)
        bar:SetScript("OnLeave", function()
          bar._hlBorder:Hide()
          GameTooltip:Hide()
        end)
      elseif hlMode == "bar" then
        bar._hlBorder:Hide()
        bar._hlOverlay:SetShown(isHovered)
        bar:SetScript("OnEnter", function(self)
          bar._hlOverlay:Show()
          DM.ShowSpellBreakdown(self)
        end)
        bar:SetScript("OnLeave", function()
          bar._hlOverlay:Hide()
          GameTooltip:Hide()
        end)
      else
        bar._hlBorder:Hide()
        bar._hlOverlay:Hide()
        bar:SetScript("OnEnter", function(self) DM.ShowSpellBreakdown(self) end)
        bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
      end

      -- Store source for tooltip
      bar._sourceGUID = src.sourceGUID
      bar._sourceCreatureID = src.sourceCreatureID
      bar._sourceName = srcName
      bar._sourceClass = src.classFilename
      bar._isLocalPlayer = src.isLocalPlayer
      bar._windowObj = w
      if srcName and src.sourceGUID and not isSecret(src.sourceGUID) then
        guidCache[srcName] = src.sourceGUID
      end
      bar:EnableMouse(true)
    else
      bar:Hide()
    end
  end
end

-- ── Update title for all windows (called by timer) ───────────────────
function DM.UpdateTitle()
  for _, w in ipairs(DM.windows) do
    UpdateWindowTitle(w)
  end
end

-- ── Refresh data + update display for all windows ────────────────────
function DM.RefreshAllWindows()
  for _, w in ipairs(DM.windows) do
    RefreshWindowData(w)
  end
end

-- ── Update display for all windows ──────────────────────────────────
function DM.UpdateDisplay()
  for _, w in ipairs(DM.windows) do
    RefreshWindowData(w)
    DM.UpdateWindowDisplay(w)
  end
end

-- ── Spell breakdown tooltip ───────────────────────────────────────────
function DM.ShowSpellBreakdown(bar)
  local isSecret = issecretvalue or function() return false end

  local guid = bar._sourceGUID
  local creatureID = bar._sourceCreatureID
  local sourceName = bar._sourceName
  local w = bar._windowObj

  local nameUsable = sourceName and not isSecret(sourceName)

  if guid and not isSecret(guid) and nameUsable then
    guidCache[sourceName] = guid
  end

  if not guid or isSecret(guid) then
    guid = nameUsable and guidCache[sourceName]
    if not guid and bar._isLocalPlayer then
      guid = UnitGUID("player")
    end
    if not guid and nameUsable then
      for i = 1, GetNumGroupMembers() do
        local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
        local uName = GetUnitName(unit, false)
        if uName and (uName == sourceName or uName:match("^([^%-]+)") == sourceName) then
          guid = UnitGUID(unit)
          if guid then guidCache[sourceName] = guid end
          break
        end
      end
    end
  end

  if not guid and not creatureID then return end

  local ok, sourceData
  if w and w.sessionID then
    ok, sourceData = pcall(C_DamageMeter.GetCombatSessionSourceFromID,
      w.sessionID, w.meterType, guid, creatureID)
  elseif w then
    ok, sourceData = pcall(C_DamageMeter.GetCombatSessionSourceFromType,
      w.sessionType or 1, w.meterType, guid, creatureID)
  else
    ok, sourceData = pcall(C_DamageMeter.GetCombatSessionSourceFromType,
      DM.currentSessionType or 1, DM.currentMeterType, guid, creatureID)
  end

  if not ok or not sourceData then
    GameTooltip:SetOwner(bar, "ANCHOR_LEFT")
    local name = sourceName or "?"
    local cr2, cg2, cb2 = GetClassColor(bar._sourceClass)
    GameTooltip:AddLine(name, cr2, cg2, cb2)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cffff8800Spell breakdown unavailable|r")
    GameTooltip:Show()
    return
  end
  local spellsTable = sourceData.combatSpells
  if not spellsTable or isSecret(spellsTable) then
    GameTooltip:SetOwner(bar, "ANCHOR_LEFT")
    local name = bar._sourceName or "?"
    local cr2, cg2, cb2 = GetClassColor(bar._sourceClass)
    GameTooltip:AddLine(name, cr2, cg2, cb2)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cffff8800Spell breakdown is restricted|r")
    GameTooltip:AddLine("|cff808080during combat by the game client.|r")
    GameTooltip:Show()
    return
  end

  GameTooltip:SetOwner(bar, "ANCHOR_LEFT")

  local name = bar._sourceName or "?"
  local cr, cg, cb = GetClassColor(bar._sourceClass)
  GameTooltip:AddLine(name, cr, cg, cb)
  GameTooltip:AddLine(" ")

  GameTooltip:AddDoubleLine("|cffccccccSpell Name|r", "|cffccccccAmount    DPS    %|r", 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)

  local totalAmount = sourceData.totalAmount or 0
  local maxSpells = 10

  local spells = {}
  for j = 1, #spellsTable do spells[j] = spellsTable[j] end
  pcall(function()
    table.sort(spells, function(a, b)
      local aVal = a.totalAmount or 0
      local bVal = b.totalAmount or 0
      if isSecret(aVal) or isSecret(bVal) then return false end
      return aVal > bVal
    end)
  end)

  for i = 1, math.min(#spells, maxSpells) do
    local spell = spells[i]
    local spellAmount = spell.totalAmount or 0
    local spellDPS = spell.amountPerSecond or 0
    local spellID = spell.spellID

    local spellName = "?"
    local spellIcon = ""
    if spellID and not isSecret(spellID) then
      local info = C_Spell.GetSpellInfo(spellID)
      if info then
        spellName = info.name or "?"
        if info.iconID then
          spellIcon = "|T" .. info.iconID .. ":14:14|t "
        end
      end
    end

    local fmtAmount, fmtDPS, pct
    if isSecret(spellAmount) then
      fmtAmount = AbbreviateNumbers(spellAmount)
    else
      fmtAmount = DM.FormatNumber(spellAmount)
    end
    if isSecret(spellDPS) then
      fmtDPS = AbbreviateNumbers(spellDPS)
    else
      fmtDPS = DM.FormatNumber(spellDPS)
    end
    if not isSecret(spellAmount) and not isSecret(totalAmount) and totalAmount > 0 then
      pct = string.format("%.1f%%", spellAmount / totalAmount * 100)
    else
      pct = ""
    end

    GameTooltip:AddDoubleLine(
      spellIcon .. spellName,
      fmtAmount .. "   " .. fmtDPS .. "   " .. pct,
      1, 1, 1, 0.8, 0.8, 0.8)
  end

  if #spells > maxSpells then
    GameTooltip:AddLine("|cff808080... and " .. (#spells - maxSpells) .. " more|r")
  end

  GameTooltip:Show()
end

-- ── Combat state callback ────────────────────────────────────────────
function DM.OnCombatStateChanged(entering)
  if #DM.windows == 0 then
    if entering and NS.DB("dmEnabled") then DM.BuildDisplay() end
    return
  end
  if entering and NS.DB("dmEnabled") then
    for _, w in ipairs(DM.windows) do
      w.frame:Show()
    end
  end
end

-- ── Apply theme (accent color updates) ───────────────────────────────
function DM.ApplyTheme()
  if #DM.windows == 0 then return end
  local ar, ag, ab = NS.ChatGetAccentRGB()
  local tCol = NS.DB("dmTitleColor")
  for _, w in ipairs(DM.windows) do
    if tCol then
      if w.titleText then w.titleText:SetTextColor(tCol.r, tCol.g, tCol.b) end
    else
      if w.titleText then w.titleText:SetTextColor(ar, ag, ab) end
    end
    if w.frame._accentLine then w.frame._accentLine:SetColorTexture(ar, ag, ab, 0.5) end
    if w.snapLines then
      for _, line in pairs(w.snapLines) do line:SetColorTexture(ar, ag, ab, 0.8) end
    end
  end
end

-- ── Report Results Window ────────────────────────────────────────────
local reportWin = nil

function DM.OpenReportWindow(w)
  if reportWin then reportWin:Hide(); reportWin = nil end

  local ar, ag, ab = NS.ChatGetAccentRGB()
  local aHex = string.format("%02x%02x%02x", ar*255, ag*255, ab*255)

  local WIN_W = 260
  reportWin = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  reportWin:SetSize(WIN_W, 200)
  reportWin:SetPoint("CENTER")
  reportWin:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
  reportWin:SetBackdropColor(0.05, 0.05, 0.05, 0.97)
  reportWin:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
  reportWin:SetFrameStrata("DIALOG")
  reportWin:SetMovable(true)
  reportWin:EnableMouse(true)
  reportWin:RegisterForDrag("LeftButton")
  reportWin:SetScript("OnDragStart", reportWin.StartMoving)
  reportWin:SetScript("OnDragStop", reportWin.StopMovingOrSizing)
  reportWin:SetScript("OnKeyDown", function(_, key) if key == "ESCAPE" then reportWin:Hide() end end)
  reportWin:EnableKeyboard(true)

  -- Title bar
  local titleBar = CreateFrame("Frame", nil, reportWin)
  titleBar:SetHeight(24)
  titleBar:SetPoint("TOPLEFT", 0, 0); titleBar:SetPoint("TOPRIGHT", 0, 0)
  local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
  titleBg:SetAllPoints(); titleBg:SetColorTexture(0.08, 0.08, 0.08, 1)
  local titleLine = titleBar:CreateTexture(nil, "OVERLAY")
  titleLine:SetHeight(1); titleLine:SetPoint("BOTTOMLEFT"); titleLine:SetPoint("BOTTOMRIGHT")
  titleLine:SetColorTexture(ar, ag, ab, 0.5)
  local title = titleBar:CreateFontString(nil, "OVERLAY")
  title:SetFont("Fonts/FRIZQT__.TTF", 10, "")
  title:SetPoint("LEFT", 8, 0)
  title:SetText("|cff" .. aHex .. ">|r Report Results")
  title:SetTextColor(0.85, 0.85, 0.85)

  -- Close X
  local closeBtn = CreateFrame("Button", nil, titleBar)
  closeBtn:SetSize(16, 16); closeBtn:SetPoint("RIGHT", -4, 0)
  local closeTex = closeBtn:CreateFontString(nil, "OVERLAY")
  closeTex:SetFont("Fonts/FRIZQT__.TTF", 11, ""); closeTex:SetPoint("CENTER")
  closeTex:SetText("x"); closeTex:SetTextColor(0.4, 0.4, 0.4)
  closeBtn:SetScript("OnEnter", function() closeTex:SetTextColor(1, 0.3, 0.3) end)
  closeBtn:SetScript("OnLeave", function() closeTex:SetTextColor(0.4, 0.4, 0.4) end)
  closeBtn:SetScript("OnClick", function() reportWin:Hide() end)

  local PAD = 12
  local yOff = -32

  -- ── Channel Dropdown ──────────────────────────────────────────────
  local selectedChannel = "SAY"

  local channels = {}
  channels[#channels + 1] = {label = "Say", ch = "SAY"}
  if GetNumSubgroupMembers() > 0 then channels[#channels + 1] = {label = "Party", ch = "PARTY"} end
  if IsInRaid() then channels[#channels + 1] = {label = "Raid", ch = "RAID"} end
  if IsInInstance() then channels[#channels + 1] = {label = "Instance", ch = "INSTANCE_CHAT"} end
  if IsInGuild() then channels[#channels + 1] = {label = "Guild", ch = "GUILD"} end
  channels[#channels + 1] = {label = "Whisper", ch = "WHISPER"}

  -- Auto-select best channel
  if IsInRaid() then selectedChannel = "RAID"
  elseif GetNumSubgroupMembers() > 0 then selectedChannel = "PARTY"
  elseif IsInInstance() then selectedChannel = "INSTANCE_CHAT" end

  local chanLabel = reportWin:CreateFontString(nil, "OVERLAY")
  chanLabel:SetFont("Fonts/FRIZQT__.TTF", 10, "")
  chanLabel:SetPoint("TOPLEFT", PAD, yOff)
  chanLabel:SetText("|cff808080Channel|r")

  yOff = yOff - 16
  -- Dropdown button
  local chanBtn = CreateFrame("Button", nil, reportWin, "BackdropTemplate")
  chanBtn:SetSize(WIN_W - PAD * 2, 24)
  chanBtn:SetPoint("TOPLEFT", PAD, yOff)
  chanBtn:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
  chanBtn:SetBackdropColor(0.08, 0.08, 0.08, 1)
  chanBtn:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
  local chanBtnText = chanBtn:CreateFontString(nil, "OVERLAY")
  chanBtnText:SetFont("Fonts/FRIZQT__.TTF", 10, "")
  chanBtnText:SetPoint("LEFT", 8, 0)
  chanBtnText:SetTextColor(0.9, 0.9, 0.9)
  local chanArrow = chanBtn:CreateFontString(nil, "OVERLAY")
  chanArrow:SetFont("Fonts/FRIZQT__.TTF", 9, "")
  chanArrow:SetPoint("RIGHT", -6, 0)
  chanArrow:SetTextColor(ar, ag, ab); chanArrow:SetText("v")

  -- Update displayed channel name
  local function UpdateChanBtnText()
    for _, ch in ipairs(channels) do
      if ch.ch == selectedChannel then chanBtnText:SetText(ch.label); break end
    end
  end
  UpdateChanBtnText()

  chanBtn:SetScript("OnEnter", function() chanBtn:SetBackdropBorderColor(ar, ag, ab, 1) end)
  chanBtn:SetScript("OnLeave", function() chanBtn:SetBackdropBorderColor(0.25, 0.25, 0.25, 1) end)

  local chanPopup = nil
  chanBtn:SetScript("OnClick", function(self)
    if chanPopup then chanPopup:Hide(); chanPopup = nil; return end
    chanPopup = CreateFrame("Frame", nil, self, "BackdropTemplate")
    chanPopup:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
    chanPopup:SetBackdropColor(0.06, 0.06, 0.06, 0.97)
    chanPopup:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    chanPopup:SetFrameStrata("TOOLTIP")
    local ITEM_H, popH = 20, 0
    for _, ch in ipairs(channels) do
      local item = CreateFrame("Button", nil, chanPopup)
      item:SetHeight(ITEM_H)
      item:SetPoint("TOPLEFT", 2, -popH); item:SetPoint("TOPRIGHT", -2, -popH)
      local hl = item:CreateTexture(nil, "BACKGROUND")
      hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.06); hl:Hide()
      local lbl = item:CreateFontString(nil, "OVERLAY")
      lbl:SetFont("Fonts/FRIZQT__.TTF", 10, ""); lbl:SetPoint("LEFT", 8, 0)
      lbl:SetText((ch.ch == selectedChannel) and ("|cff" .. aHex .. ch.label .. "|r") or ch.label)
      lbl:SetTextColor(0.85, 0.85, 0.85)
      item:SetScript("OnEnter", function() hl:Show() end)
      item:SetScript("OnLeave", function() hl:Hide() end)
      local capturedCh = ch.ch
      item:SetScript("OnClick", function()
        selectedChannel = capturedCh
        UpdateChanBtnText()
        chanPopup:Hide(); chanPopup = nil
      end)
      popH = popH + ITEM_H
    end
    chanPopup:SetSize(WIN_W - PAD * 2, popH + 4)
    chanPopup:SetPoint("TOP", self, "BOTTOM", 0, -1)
    chanPopup:Show()
  end)

  yOff = yOff - 30

  -- ── Whisper Target Input ──────────────────────────────────────────
  local whisperLabel = reportWin:CreateFontString(nil, "OVERLAY")
  whisperLabel:SetFont("Fonts/FRIZQT__.TTF", 10, "")
  whisperLabel:SetPoint("TOPLEFT", PAD, yOff)
  whisperLabel:SetText("|cff808080Whisper Target|r")

  yOff = yOff - 16
  local whisperBox = CreateFrame("EditBox", nil, reportWin, "BackdropTemplate")
  whisperBox:SetSize(WIN_W - PAD * 2, 22)
  whisperBox:SetPoint("TOPLEFT", PAD, yOff)
  whisperBox:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
  whisperBox:SetBackdropColor(0.08, 0.08, 0.08, 1)
  whisperBox:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
  whisperBox:SetFont("Fonts/FRIZQT__.TTF", 10, "")
  whisperBox:SetTextColor(0.9, 0.9, 0.9)
  whisperBox:SetTextInsets(8, 8, 0, 0)
  whisperBox:SetAutoFocus(false)
  if UnitExists("target") and UnitIsPlayer("target") then
    -- Use full name with normalized realm for cross-server whispers
    local fullName = GetUnitName("target", true)
    if fullName then
      whisperBox:SetText(fullName)
    end
  end
  whisperBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  whisperBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

  yOff = yOff - 28

  -- ── Lines selector ─────────────────────────────────────────────────
  local linesVal = 5
  local linesRow = CreateFrame("Frame", nil, reportWin)
  linesRow:SetSize(WIN_W - PAD * 2, 24)
  linesRow:SetPoint("TOPLEFT", PAD, yOff)

  local linesLabel2 = linesRow:CreateFontString(nil, "OVERLAY")
  linesLabel2:SetFont("Fonts/FRIZQT__.TTF", 10, "")
  linesLabel2:SetPoint("LEFT", 0, 0)
  linesLabel2:SetText("|cff808080Lines:|r")

  local linesNumText = linesRow:CreateFontString(nil, "OVERLAY")
  linesNumText:SetFont("Fonts/FRIZQT__.TTF", 11, "")
  linesNumText:SetPoint("CENTER")
  linesNumText:SetText(linesVal)
  linesNumText:SetTextColor(0.9, 0.9, 0.9)

  local function UpdateLinesDisplay()
    linesNumText:SetText(linesVal)
  end

  local function MakeArrowBtn(text, point, offsetX)
    local btn = CreateFrame("Button", nil, linesRow, "BackdropTemplate")
    btn:SetSize(22, 22)
    btn:SetPoint(point, offsetX, 0)
    btn:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
    btn:SetBackdropColor(0.08, 0.08, 0.08, 1)
    btn:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    local lbl = btn:CreateFontString(nil, "OVERLAY")
    lbl:SetFont("Fonts/FRIZQT__.TTF", 12, ""); lbl:SetPoint("CENTER"); lbl:SetText(text)
    lbl:SetTextColor(0.6, 0.6, 0.6)
    btn:SetScript("OnEnter", function() btn:SetBackdropBorderColor(ar, ag, ab, 1); lbl:SetTextColor(1, 1, 1) end)
    btn:SetScript("OnLeave", function() btn:SetBackdropBorderColor(0.25, 0.25, 0.25, 1); lbl:SetTextColor(0.6, 0.6, 0.6) end)
    return btn
  end

  local minusBtn = MakeArrowBtn("-", "RIGHT", -28)
  minusBtn:SetScript("OnClick", function()
    linesVal = math.max(1, linesVal - 1); UpdateLinesDisplay()
  end)

  local plusBtn = MakeArrowBtn("+", "RIGHT", 0)
  plusBtn:SetScript("OnClick", function()
    linesVal = math.min(20, linesVal + 1); UpdateLinesDisplay()
  end)

  yOff = yOff - 30

  -- ── Send Button ───────────────────────────────────────────────────
  reportWin:SetHeight(math.abs(yOff) + 26 + PAD)
  local sendBtn = CreateFrame("Button", nil, reportWin, "BackdropTemplate")
  sendBtn:SetSize(WIN_W - PAD * 2, 26)
  sendBtn:SetPoint("TOPLEFT", PAD, yOff)
  sendBtn:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
  sendBtn:SetBackdropColor(ar * 0.25, ag * 0.25, ab * 0.25, 1)
  sendBtn:SetBackdropBorderColor(ar, ag, ab, 1)
  local sendLbl = sendBtn:CreateFontString(nil, "OVERLAY")
  sendLbl:SetFont("Fonts/FRIZQT__.TTF", 11, "")
  sendLbl:SetPoint("CENTER"); sendLbl:SetText("Send"); sendLbl:SetTextColor(1, 1, 1)
  sendBtn:SetScript("OnEnter", function() sendBtn:SetBackdropColor(ar * 0.4, ag * 0.4, ab * 0.4, 1) end)
  sendBtn:SetScript("OnLeave", function() sendBtn:SetBackdropColor(ar * 0.25, ag * 0.25, ab * 0.25, 1) end)
  sendBtn:SetScript("OnClick", function()
    local ch = selectedChannel
    local target = whisperBox:GetText()
    if not ch then return end
    if ch == "WHISPER" and (not target or target == "") then return end

    local isSecret = issecretvalue or function() return false end
    local label = "Damage Done"
    for _, mt in ipairs(DM.METER_TYPES) do if mt.id == w.meterType then label = mt.label; break end end
    local suffix = ""
    if w.sessionID == nil and w.sessionType == 0 then suffix = " (Overall)" end
    local header = "LucidMeter: " .. label .. suffix

    local sources = {}
    if w.sessionData and w.sessionData.combatSources and not isSecret(w.sessionData.combatSources) then
      pcall(function()
        for j = 1, #w.sessionData.combatSources do sources[#sources + 1] = w.sessionData.combatSources[j] end
      end)
      if #sources > 0 and not isSecret(sources[1].totalAmount) then
        table.sort(sources, function(a, b) return (a.totalAmount or 0) > (b.totalAmount or 0) end)
      end
    end

    local chatLines = {header}
    local maxL = math.min(#sources, linesVal)
    for j = 1, maxL do
      local src = sources[j]
      local name = src.name
      if not isSecret(name) and name then name = name:match("^([^%-]+)") or name end
      local total = src.totalAmount or 0
      local perSec = src.amountPerSecond or 0
      if not isSecret(total) and not isSecret(perSec) then
        chatLines[#chatLines + 1] = string.format("%d. %s  %s (%s)", j, name or "?", DM.FormatNumber(total), DM.FormatNumber(perSec))
      end
    end

    for j, line in ipairs(chatLines) do
      C_Timer.After((j - 1) * 0.2, function()
        if ch == "WHISPER" and target and target ~= "" then
          -- Capitalize name and realm: "arggyy-thrall" → "Arggyy-Thrall"
          local cleanTarget = target:gsub("%s+", ""):gsub("(%a)([%a]*)", function(first, rest)
            return first:upper() .. rest:lower()
          end)
          SendChatMessage(line, ch, nil, cleanTarget)
        else
          SendChatMessage(line, ch)
        end
      end)
    end
    reportWin:Hide()
  end)

  reportWin:Show()
end
