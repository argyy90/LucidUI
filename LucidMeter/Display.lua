-- LucidMeter — Display UI with bars and class colors (multi-window)
local NS = LucidUINS
local DM = NS.LucidMeter
local CYAN = NS.CYAN

-- Defensive fallback: AbbreviateNumbers is a Blizzard global that may not exist in all Midnight builds
local _AbbreviateNumbers = AbbreviateNumbers

-- Custom abbreviation options matching our FormatNumber output (2 decimal M, 2 decimal K)
-- Abbreviation options for total damage/healing (2 decimal M, 1 decimal K for >10K)
local ABBR_TOTAL_OPTS = {
  { breakpoint = 1000000000, abbreviation = "B", significandDivisor = 10000000, fractionDivisor = 100, abbreviationIsGlobal = false },
  { breakpoint = 1000000,    abbreviation = "M", significandDivisor = 10000,    fractionDivisor = 100, abbreviationIsGlobal = false },
  { breakpoint = 10000,      abbreviation = "K", significandDivisor = 1000,     fractionDivisor = 1,   abbreviationIsGlobal = false },
  { breakpoint = 1000,       abbreviation = "K", significandDivisor = 100,      fractionDivisor = 10,  abbreviationIsGlobal = false },
  { breakpoint = 1,          abbreviation = "",  significandDivisor = 1,        fractionDivisor = 1,   abbreviationIsGlobal = false },
}
-- Abbreviation options for DPS/HPS (1 decimal K for all K values)
local ABBR_PERSEC_OPTS = {
  { breakpoint = 1000000000, abbreviation = "B", significandDivisor = 10000000, fractionDivisor = 100, abbreviationIsGlobal = false },
  { breakpoint = 1000000,    abbreviation = "M", significandDivisor = 10000,    fractionDivisor = 100, abbreviationIsGlobal = false },
  { breakpoint = 1000,       abbreviation = "K", significandDivisor = 100,      fractionDivisor = 10,  abbreviationIsGlobal = false },
  { breakpoint = 1,          abbreviation = "",  significandDivisor = 1,        fractionDivisor = 1,   abbreviationIsGlobal = false },
}

-- Wrap with CreateAbbreviateConfig if available
if CreateAbbreviateConfig then
  ABBR_TOTAL_OPTS = {config = CreateAbbreviateConfig(ABBR_TOTAL_OPTS)}
  ABBR_PERSEC_OPTS = {config = CreateAbbreviateConfig(ABBR_PERSEC_OPTS)}
end

local function SafeAbbreviateTotal(n)
  if _AbbreviateNumbers then return _AbbreviateNumbers(n, ABBR_TOTAL_OPTS) end
  return DM.FormatNumber(n)
end
local function SafeAbbreviatePerSec(n)
  if _AbbreviateNumbers then return _AbbreviateNumbers(n, ABBR_PERSEC_OPTS) end
  return DM.FormatNumber(n)
end

local MAX_BARS = 40
local TITLE_H = 22
local guidCache = {}
local guidCacheSize = 0
local GUID_CACHE_MAX = 300
local isSecret = issecretvalue or function() return false end

DM.windows = {}

local CLASS_COLORS = NS.CLASS_COLORS

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
  local barH    = NS.DB("dmBarHeight") or 18
  local barFont = NS.GetFontPath(NS.DB("dmFont"))
  local barFS   = NS.DB("dmFontSize") or 11
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
  name:SetFont(barFont, barFS, "")
  name:SetPoint("LEFT", 4, 0)
  name:SetJustifyH("LEFT")
  bar._name = name

  local pct = bar:CreateFontString(nil, "OVERLAY")
  pct:SetFont(barFont, barFS, "")
  pct:SetPoint("RIGHT", -4, 0)
  pct:SetJustifyH("RIGHT")
  pct:Hide()
  bar._pct = pct

  local value = bar:CreateFontString(nil, "OVERLAY")
  value:SetFont(barFont, barFS, "")
  value:SetPoint("RIGHT", -4, 0)
  value:SetJustifyH("RIGHT")
  bar._value = value

  bar:Hide()
  return bar
end

-- ── proximity-snap system ──
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
  ticker = C_Timer.NewTicker(0.033, function()
    elapsed = elapsed + 0.033
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
local function AnchorGroupToDragRoot(dragRoot)
  local group = GetSnapGroup(dragRoot)
  if #group <= 1 then return end

  local overlap = (NS.DB("dmWindowBorder") ~= false) and 1 or 2

  for _, gw in ipairs(group) do
    local l, t = gw.frame:GetLeft(), gw.frame:GetTop()
    if l then
      gw.frame:ClearAllPoints()
      gw.frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
    end
  end

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
DM.RefreshWindowData = nil  -- forward declaration
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
DM.RefreshWindowData = RefreshWindowData

-- ── Save helpers ─────────────────────────────────────────────────────
local function SaveWindowPosSize(w)
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

-- ── Apply click-through state to a window ───────────────────────────
-- NEW FEATURE (from Details): click-through support
local function ApplyClickThrough(w)
  local enabled = NS.DB("dmClickThrough")
  local combatOnly = NS.DB("dmClickThroughCombat")
  local active = enabled and (not combatOnly or DM.inCombat)
  w.frame:EnableMouse(not active)
end

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

  local winW = (windowID == 1) and 290 or 320
  local winH = 220

  local frameName = (windowID == 1) and "LucidMeterFrame" or ("LucidMeterFrame" .. windowID)
  local frame = CreateFrame("Frame", frameName, UIParent, "BackdropTemplate")
  frame:SetSize(winW, winH)
  frame:SetBackdrop({
    bgFile = NS.TEX_WHITE,
    edgeFile = NS.TEX_WHITE,
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

  -- Apply click-through setting on creation
  ApplyClickThrough(w)

  local function OnDragStart()
    if NS.DB("dmLocked") then return end
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
      frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    else
      local offset = (windowID - 2) * 30
      frame:SetPoint("CENTER", UIParent, "CENTER", offset, -offset)
    end
  end
  local savedSize = config.size
  if savedSize then
    frame:SetSize(savedSize.w or winW, savedSize.h or winH)
  end

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

  local titleBorder = titleBar:CreateTexture(nil, "OVERLAY")
  titleBorder:SetHeight(1)
  titleBorder:SetPoint("BOTTOMLEFT", 0, 0)
  titleBorder:SetPoint("BOTTOMRIGHT", 0, 0)
  titleBorder:SetColorTexture(0.15, 0.15, 0.15, 1)
  titleBorder:Hide()
  frame._titleBorder = titleBorder

  local titleText = titleBar:CreateFontString(nil, "OVERLAY")
  titleText:SetFont(NS.GetFontPath(NS.DB("dmFont")), NS.DB("dmTitleFontSize") or 10, NS.DB("dmTextOutline") and "OUTLINE" or "")
  titleText:SetPoint("LEFT", 6, 0)
  local tCol = NS.DB("dmTitleColor")
  if type(tCol) ~= "table" or not tCol.r then tCol = {r=1, g=1, b=1} end
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
    popupMenu:SetBackdrop({bgFile=NS.TEX_WHITE, edgeFile=NS.TEX_WHITE, edgeSize=1})
    popupMenu:SetBackdropColor(0.06, 0.06, 0.06, 0.97)
    popupMenu:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    popupMenu:SetFrameStrata("TOOLTIP")
    popupMenu:SetClampedToScreen(true)

    local ITEM_H = 20
    local MENU_W = 220
    local PAD = 4
    local totalH = PAD
    local btns = {}

    for _, item in ipairs(items) do
      if item.divider then
        local div = popupMenu:CreateTexture(nil, "OVERLAY")
        div:SetHeight(1)
        div:SetPoint("BOTTOMLEFT", 4, totalH + 4)
        div:SetPoint("BOTTOMRIGHT", -4, totalH + 4)
        div:SetColorTexture(0.25, 0.25, 0.25, 1)
        totalH = totalH + 9
      elseif item.title then
        local lbl = popupMenu:CreateFontString(nil, "OVERLAY")
        lbl:SetFont(NS.FONT, 10, "")
        lbl:SetPoint("BOTTOMLEFT", 8, totalH + 2)
        lbl:SetText(item.text)
        lbl:SetTextColor(0.5, 0.5, 0.5)
        totalH = totalH + ITEM_H
      else
        local btn = CreateFrame("Button", nil, popupMenu)
        btn:SetHeight(ITEM_H)
        btn:SetPoint("BOTTOMLEFT", 2, totalH)
        btn:SetPoint("BOTTOMRIGHT", -2, totalH)
        local hl = btn:CreateTexture(nil, "BACKGROUND")
        hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.06); hl:Hide()
        btn:SetScript("OnEnter", function() hl:Show() end)
        btn:SetScript("OnLeave", function() hl:Hide() end)
        local lbl = btn:CreateFontString(nil, "OVERLAY")
        lbl:SetFont(NS.FONT, 10, "")
        lbl:SetPoint("LEFT", 8, 0)
        lbl:SetText(item.text)
        lbl:SetTextColor(0.85, 0.85, 0.85)
        local cb = item.func
        btn:SetScript("OnClick", function() if cb then cb() end; popupMenu:Hide() end)
        totalH = totalH + ITEM_H
        btns[#btns + 1] = btn
      end
    end

    popupMenu:SetSize(MENU_W, totalH + PAD)
    popupMenu:ClearAllPoints()
    popupMenu:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 2)
    popupMenu:Show()

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

  titleBar:EnableMouse(true)
  titleBar:EnableMouseWheel(true)
  titleBar:RegisterForDrag("LeftButton")
  titleBar:SetScript("OnDragStart", OnDragStart)
  titleBar:SetScript("OnDragStop", OnDragStop)

  -- NEW FEATURE: mousewheel on titlebar cycles through meter types (Details-style)
  titleBar:SetScript("OnMouseWheel", function(_, delta)
    local types = DM.METER_TYPES
    local curIdx = 1
    for i, mt in ipairs(types) do
      if mt.id == w.meterType then curIdx = i; break end
    end
    local newIdx = ((curIdx - 1 - delta) % #types) + 1
    w.meterType = types[newIdx].id
    w.scrollOffset = 0
    SaveWindowState(w)
    RefreshWindowData(w)
    DM.UpdateWindowDisplay(w)
  end)

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

  local function SelectMeterType(id)
    w.meterType = id
    w.scrollOffset = 0
    SaveWindowState(w)
    RefreshWindowData(w)
    DM.UpdateWindowDisplay(w)
  end

  local function SelectSessionType(stype)
    w.sessionID = nil
    w.sessionType = stype
    w.scrollOffset = 0
    SaveWindowState(w)
    RefreshWindowData(w)
    DM.UpdateWindowDisplay(w)
  end

  -- ── Settings button ─────────────────────────────────────────────────
  local settingsBtn = MakeTitleIcon(titleBar, 16, "Interface/AddOns/LucidUI/Assets/Cog.png")
  settingsBtn:SetPoint("RIGHT", -3, 0)
  settingsBtn:SetScript("OnClick", function()
    NS.BuildChatOptionsWindow()
    if NS.chatOptWin and NS.chatOptWin._selectTab and NS.chatOptWin.containers then
      for i, c in ipairs(NS.chatOptWin.containers) do
        if c.button and c.button._label and c.button._label:GetText() == "LucidMeter" then
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

  -- ── Reset button ───────────────────────────────────────────────────
  local resetBtn = MakeTitleIcon(titleBar, 16, "Interface/AddOns/LucidUI/Assets/Reset.png")
  resetBtn:SetPoint("RIGHT", reportBtn, "LEFT", -1, 0)
  resetBtn:HookScript("OnEnter", function(self)
    local hasSnap = w.snappedTo and next(w.snappedTo)
    local items = {
      {text = "|TInterface/AddOns/LucidUI/Assets/X_red.png:12:12|t  Reset All Windows", func = function() DM.Reset() end},
    }
    if hasSnap then
      items[#items + 1] = {divider = true}
      items[#items + 1] = {text = "|TInterface/AddOns/LucidUI/Assets/X_orange.png:12:12|t  Unsnap Window", func = function()
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
    local items = {}
    for _, stype in ipairs({1, 0}) do
      local label = SESSION_LABELS[stype]
      local isCur = (w.sessionID == nil and w.sessionType == stype)
      local capturedType = stype
      items[#items + 1] = {text = isCur and ("|cff" .. aHex .. label .. "|r") or label, func = function() SelectSessionType(capturedType) end}
    end
    local sessions = DM.GetAvailableSessions()
    local startIdx = math.max(1, #sessions - 19)
    if #sessions > 0 then
      items[#items + 1] = {divider = true}
      for si = #sessions, startIdx, -1 do
        local s = sessions[si]
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
          local isBoss = name:find("^%(%)") or name:find("^!")
          local icon = isBoss
            and "|TInterface/AddOns/LucidUI/Assets/Arrow_right_green.png:12:12|t "
            or "|TInterface/AddOns/LucidUI/Assets/Arrow_right_orange.png:12:12|t "
          local displayName = isCur and ("|cff" .. aHex .. name .. dur .. "|r") or (name .. dur)
          items[#items + 1] = {text = icon .. displayName, func = function()
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
    items[#items + 1] = {title = true, text = "|cff808080Damage|r"}
    for _, mt in ipairs({{0, "Damage Done"}, {1, "DPS"}, {7, "Damage Taken"}, {8, "Avoidable Damage"}}) do
      local id, label = mt[1], mt[2]
      local capturedId = id
      items[#items + 1] = {text = (w.meterType == id) and ("|cff" .. aHex .. label .. "|r") or label, func = function() SelectMeterType(capturedId) end}
    end
    items[#items + 1] = {divider = true}
    items[#items + 1] = {title = true, text = "|cff808080Healing|r"}
    for _, mt in ipairs({{2, "Healing Done"}, {3, "HPS"}, {4, "Absorbs"}}) do
      local id, label = mt[1], mt[2]
      local capturedId = id
      items[#items + 1] = {text = (w.meterType == id) and ("|cff" .. aHex .. label .. "|r") or label, func = function() SelectMeterType(capturedId) end}
    end
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
  w.scrollOffset = 0

  -- Scroll support
  -- BUG FIX: use consistent default of 18 (not 24) for dmBarHeight in scroll math
  barContainer:EnableMouseWheel(true)
  barContainer:SetScript("OnMouseWheel", function(_, delta)
    local barH2 = NS.DB("dmBarHeight") or 18
    local barSpacing2 = NS.DB("dmBarSpacing") or 1
    local maxOffset = math.max(0, (w._totalSources or 0) - math.floor(barContainer:GetHeight() / (barH2 + barSpacing2)))
    w.scrollOffset = math.max(0, math.min(w.scrollOffset - delta, maxOffset))
    DM.UpdateWindowDisplay(w)
  end)

  -- Pre-create bars
  for i = 1, MAX_BARS do
    w.bars[i] = CreateBar(barContainer, i)
  end

  -- NEW FEATURE (from Details): Total bar — shows group total at the very top
  -- Shows a second bar representing the sum of all sources (useful for raid awareness)
  local totalBarFrame = CreateFrame("StatusBar", nil, barContainer)
  totalBarFrame:SetStatusBarTexture(NS.GetBarTexturePath(NS.DB("dmBarTexture")))
  totalBarFrame:SetMinMaxValues(0, 1)
  totalBarFrame:SetValue(1)
  totalBarFrame:SetStatusBarColor(0.3, 0.3, 0.3, 0.5)
  totalBarFrame:Hide()
  local totalBarBg = totalBarFrame:CreateTexture(nil, "BACKGROUND")
  totalBarBg:SetAllPoints()
  totalBarBg:SetColorTexture(0.05, 0.05, 0.05, 0.6)
  local totalBarLabel = totalBarFrame:CreateFontString(nil, "OVERLAY")
  totalBarLabel:SetFont(NS.GetFontPath(NS.DB("dmFont")), NS.DB("dmFontSize") or 11, "")
  totalBarLabel:SetPoint("LEFT", 4, 0)
  totalBarLabel:SetTextColor(0.7, 0.7, 0.7)
  totalBarLabel:SetText("Total")
  local totalBarValue = totalBarFrame:CreateFontString(nil, "OVERLAY")
  totalBarValue:SetFont(NS.GetFontPath(NS.DB("dmFont")), NS.DB("dmFontSize") or 11, "")
  totalBarValue:SetPoint("RIGHT", -4, 0)
  totalBarValue:SetTextColor(0.7, 0.7, 0.7)
  local totalBarSep = barContainer:CreateTexture(nil, "OVERLAY")
  totalBarSep:SetHeight(1)
  totalBarSep:SetColorTexture(0.25, 0.25, 0.25, 0.6)
  totalBarSep:Hide()
  w._totalBar = totalBarFrame
  w._totalBarLabel = totalBarLabel
  w._totalBarValue = totalBarValue
  w._totalBarSep = totalBarSep

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
    AnchorGroupToDragRoot(w)
    frame:StartSizing("BOTTOMRIGHT")
  end)
  resizeBtn:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()
    local group = GetSnapGroup(w)
    for _, gw in ipairs(group) do SaveWindowPosSize(gw) end
  end)
  resizeBtn:SetShown(not NS.DB("dmLocked"))
  frame._resizeBtn = resizeBtn

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
    for _, w in ipairs(DM.windows) do
      w.frame:Show()
    end
  end

  RestoreSnapRelations()
  DM.UpdateDisplay()
end

-- ── Create a new extra window ────────────────────────────────────────
function DM.CreateNewWindow()
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
  if windowID == 1 then return end
  for i, w in ipairs(DM.windows) do
    if w.id == windowID then
      -- Clean up snap references from other windows
      if w.snappedTo then
        for edge, other in pairs(w.snappedTo) do
          if other.snappedTo then other.snappedTo[OPPOSITE_EDGE[edge]] = nil end
        end
        wipe(w.snappedTo)
      end
      w.frame:Hide()
      w.frame:SetParent(nil)
      table.remove(DM.windows, i)
      break
    end
  end
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

  -- NEW FEATURE: apply click-through on each display update (catches combat state changes)
  ApplyClickThrough(w)

  UpdateWindowTitle(w)

  if not w._sortFunc then
    -- Guard against secret values: isSecret() returns a truthy userdata, not nil/false,
    -- so "secretVal or 0" evaluates to secretVal and crashes arithmetic operators.
    w._sortFunc = function(a, b)
      local av = a.totalAmount or 0
      local bv = b.totalAmount or 0
      if isSecret(av) or isSecret(bv) then return false end
      return av > bv
    end
  end
  local sources = w._cachedSources
  if not sources then sources = {}; w._cachedSources = sources end
  for k in pairs(sources) do sources[k] = nil end
  if w.sessionData then
    local cs = w.sessionData.combatSources
    if cs and not isSecret(cs) then
      local ok = pcall(function()
        for i = 1, #cs do sources[i] = cs[i] end
      end)
      if ok and #sources > 0 and not isSecret(sources[1].totalAmount) then
        table.sort(sources, w._sortFunc)
      end
    end
  end

  -- Compute maxVal: prefer sessionData.maxAmount when it is NOT secret.
  -- During combat all values are "secret" (tainted). In that case derive maxVal
  -- from the top entry in the sorted sources list instead.
  -- If that is also secret, fall back to 1 — the bar will still show a partial
  -- fill because SetValue(secretNum) renders proportionally when min/max are set
  -- to matching secret values.
  local maxVal = 1
  do
    local rawMax = w.sessionData and w.sessionData.maxAmount
    if rawMax and not isSecret(rawMax) and rawMax > 0 then
      maxVal = rawMax
    else
      -- Derive from sources: find the highest readable totalAmount
      local derivedMax = 0
      local topSecret  = false
      pcall(function()
        for _, s in ipairs(sources) do
          local amt = s.totalAmount or 0
          if isSecret(amt) then
            topSecret = true
            break  -- can't compare secrets; bail out
          end
          if amt > derivedMax then derivedMax = amt end
        end
      end)
      if topSecret then
        -- All values are secret during combat.
        -- Use the top source's secret value directly so all bars share the
        -- same scale. SetMinMaxValues(0, secretTop) + SetValue(secretN) lets
        -- WoW render the proportional fill natively.
        pcall(function()
          if sources[1] then maxVal = sources[1].totalAmount or 1 end
        end)
      elseif derivedMax > 0 then
        maxVal = derivedMax
      end
    end
  end

  local DB = NS.DB
  local barH = DB("dmBarHeight") or 18
  local barSpacing = DB("dmBarSpacing") or 1
  local fontSize = DB("dmFontSize") or 11
  local iconMode = DB("dmIconMode") or "spec"
  local valFormat = DB("dmValueFormat") or "both"
  local txtCol = DB("dmTextColor")
  if type(txtCol) ~= "table" or not txtCol.r then txtCol = {r=1, g=1, b=1} end
  local tr, tg, tb = txtCol.r, txtCol.g, txtCol.b
  local barTexture = NS.GetBarTexturePath(DB("dmBarTexture"))
  local barBgTexture = NS.GetBarTexturePath(DB("dmBarBgTexture"))
  local fontShadowVal = DB("dmFontShadow") or 0
  if type(fontShadowVal) == "boolean" then fontShadowVal = fontShadowVal and 1.5 or 0 end
  local fontFlags = DB("dmTextOutline") and "OUTLINE" or ""
  local iconSize = barH - 2
  local hasIcon = (iconMode ~= "none")
  local nameOffset = hasIcon and (iconSize + 4) or 4
  local fontPath = NS.GetFontPath(DB("dmFont"))
  local showPercent = DB("dmShowPercent")
  local showRank = DB("dmShowRank")
  local showRealm = DB("dmShowRealm")
  local classColors = DB("dmClassColors") ~= false
  local barAlpha = DB("dmBarBrightness") or 0.70
  local barColor = DB("dmBarColor")
  if type(barColor) ~= "table" or not barColor.r then barColor = {r=0.5, g=0.5, b=0.5} end
  local showTotalBar = DB("dmShowTotalBar")
  local totalAll = 0
  if showPercent or showTotalBar then
    pcall(function()
      for _, s in ipairs(sources) do
        local amt = s.totalAmount or 0
        if not isSecret(amt) then totalAll = totalAll + amt end
      end
    end)
  end

  w._totalSources = #sources
  local offset = w.scrollOffset or 0
  -- Only show total bar in group (party/raid) — solo total = own damage, not useful
  local inGroup = IsInGroup() or IsInRaid()
  local totalBarOffset = (showTotalBar and totalAll > 0 and inGroup) and (barH + barSpacing + 2) or 0

  -- Config stamp: includes all settings that affect bar appearance
  -- When any of these change, bars get a full redraw
  local configStamp = barH .. "|" .. fontSize .. "|" .. fontShadowVal
    .. "|" .. (showRank and "R" or "") .. (showPercent and "P" or "")
    .. "|" .. (classColors and "C" or "c") .. "|" .. barAlpha
    .. "|" .. tr .. "," .. tg .. "," .. tb
    .. "|" .. barColor.r .. "," .. barColor.g .. "," .. barColor.b

  for i = 1, MAX_BARS do
    local bar = w.bars[i]
    local src = sources[i + offset]
    if src then
      local cr, cg, cb
      if classColors then
        cr, cg, cb = GetClassColor(src.classFilename)
      else
        cr, cg, cb = barColor.r, barColor.g, barColor.b
      end
      local total = src.totalAmount or 0
      local perSec = src.amountPerSecond or 0
      -- Note: total/perSec may be secret during combat — that's OK
      -- SetValue and SetFormattedText handle secret values natively

      local srcName = src.name
      if not isSecret(srcName) and srcName then
        if not showRealm or src.isLocalPlayer then
          srcName = srcName:match("^([^%-]+)") or srcName
        end
      end

      local nameChanged = true
      pcall(function()
        if bar._lastSrcName == srcName and bar._lastBarIdx == (i + offset) then
          nameChanged = false
        end
      end)
      local barChanged = nameChanged or (bar._lastConfigStamp ~= configStamp) or not bar:IsShown()

      if barChanged then
        bar._lastSrcName = srcName
        bar._lastBarIdx = i + offset
        bar._lastConfigStamp = configStamp

        bar:SetStatusBarTexture(barTexture)
        bar:SetStatusBarColor(cr, cg, cb, barAlpha)

        bar._icon:SetSize(iconSize, iconSize)
        if iconMode == "spec" and src.specIconID and not isSecret(src.specIconID) and src.specIconID > 0 then
          bar._icon:SetTexture(src.specIconID); bar._icon:SetTexCoord(0, 1, 0, 1); bar._icon:Show()
        elseif iconMode ~= "none" and src.classFilename and not isSecret(src.classFilename) then
          local coords = CLASS_ICON_COORDS[src.classFilename:upper()]
          if coords then
            bar._icon:SetTexture("Interface/GLUES/CHARACTERCREATE/UI-CHARACTERCREATE-CLASSES")
            bar._icon:SetTexCoord(unpack(coords)); bar._icon:Show()
          else bar._icon:Hide() end
        else bar._icon:Hide() end

        if not bar._rankFS then bar._rankFS = bar:CreateFontString(nil, "OVERLAY") end
        local rankPrefix = ""
        local actualRank = i + offset
        if showRank then
          if actualRank == 1 then
            local cs = math.max(barH - 2, 12)
            rankPrefix = "|TInterface/AddOns/LucidUI/Assets/Crown.png:" .. cs .. ":" .. cs .. "|t "
          else
            rankPrefix = "|cffffffff" .. actualRank .. ".|r "
          end
        end
        bar._name:ClearAllPoints()
        if rankPrefix ~= "" then
          bar._rankFS:ClearAllPoints(); bar._rankFS:SetPoint("LEFT", nameOffset, 0)
          bar._rankFS:SetFont(fontPath, fontSize, fontFlags)
          bar._rankFS:SetText(rankPrefix); bar._rankFS:SetTextColor(tr, tg, tb); bar._rankFS:Show()
          bar._name:SetPoint("LEFT", nameOffset + (bar._rankFS:GetStringWidth() or 0), 0)
        else
          bar._rankFS:Hide()
          bar._name:SetPoint("LEFT", nameOffset, 0)
        end
        bar._name:SetText(srcName or "?")

        bar._name:SetTextColor(tr, tg, tb); bar._name:SetFont(fontPath, fontSize, fontFlags)
        bar._value:SetTextColor(tr, tg, tb); bar._value:SetFont(fontPath, fontSize, fontFlags)
        if fontShadowVal > 0 then
          bar._name:SetShadowOffset(fontShadowVal, -fontShadowVal); bar._name:SetShadowColor(0, 0, 0, 1)
          bar._value:SetShadowOffset(fontShadowVal, -fontShadowVal); bar._value:SetShadowColor(0, 0, 0, 1)
        else
          bar._name:SetShadowOffset(0, 0); bar._value:SetShadowOffset(0, 0)
        end

        if showPercent then
          bar._pct:SetTextColor(tr, tg, tb); bar._pct:SetFont(fontPath, fontSize, fontFlags)
          if fontShadowVal > 0 then
            bar._pct:SetShadowOffset(fontShadowVal, -fontShadowVal); bar._pct:SetShadowColor(0, 0, 0, 1)
          else bar._pct:SetShadowOffset(0, 0) end
        end

        bar:SetHeight(barH)
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", w.barContainer, "TOPLEFT", 0, -(totalBarOffset + (i - 1) * (barH + barSpacing)))
        bar:SetPoint("RIGHT", w.barContainer, "RIGHT", 0, 0)

        bar._bg:SetTexture(barBgTexture); bar._bg:SetVertexColor(0.05, 0.05, 0.05, 0.8)

        if not bar._hlBorder then
          local hlB = CreateFrame("Frame", nil, bar, "BackdropTemplate")
          hlB:SetAllPoints(); hlB:SetBackdrop({edgeFile=NS.TEX_WHITE, edgeSize=1})
          hlB:SetFrameLevel(bar:GetFrameLevel() + 2); hlB:Hide()
          bar._hlBorder = hlB
        end
        if not bar._hlOverlay then
          local hlO = bar:CreateTexture(nil, "OVERLAY", nil, 1)
          hlO:SetAllPoints(); hlO:SetColorTexture(1, 1, 1, 0.15); hlO:Hide()
          bar._hlOverlay = hlO
        end

        local hlMode = DB("dmBarHighlight") or "none"
        if hlMode == "border" then
          bar._hlOverlay:Hide()
          bar:SetScript("OnEnter", function(self)
            local a2r, a2g, a2b = NS.ChatGetAccentRGB()
            bar._hlBorder:SetBackdropBorderColor(a2r, a2g, a2b, 0.8); bar._hlBorder:Show()
            DM.ShowSpellBreakdown(self)
          end)
          bar:SetScript("OnLeave", function() bar._hlBorder:Hide(); GameTooltip:Hide() end)
        elseif hlMode == "bar" then
          bar._hlBorder:Hide()
          bar:SetScript("OnEnter", function(self) bar._hlOverlay:Show(); DM.ShowSpellBreakdown(self) end)
          bar:SetScript("OnLeave", function() bar._hlOverlay:Hide(); GameTooltip:Hide() end)
        else
          bar._hlBorder:Hide(); bar._hlOverlay:Hide()
          bar:SetScript("OnEnter", function(self) DM.ShowSpellBreakdown(self) end)
          bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        bar:SetScript("OnMouseUp", function(self) self._expanded = not self._expanded; DM.ShowSpellBreakdown(self) end)
      end

      bar:Show()

      bar:SetMinMaxValues(0, maxVal)
      bar:SetValue(total)

      -- Value text: during combat, values are secret/tainted
      -- Secret values can be passed directly to SetFormattedText as %s
      -- but NOT to Lua functions like FormatNumber or string concat
      local totalSecret = isSecret(total)
      local perSecSecret = isSecret(perSec)
      if totalSecret or perSecSecret then
        -- Secret path: SafeAbbreviate uses Blizzard's AbbreviateNumbers with our format options
        if valFormat == "both" then
          bar._value:SetFormattedText("%s | %s",
            totalSecret and SafeAbbreviateTotal(total) or DM.FormatNumber(total),
            perSecSecret and SafeAbbreviatePerSec(perSec) or DM.FormatNumber(perSec))
        elseif valFormat == "persec" then
          bar._value:SetFormattedText("%s", perSecSecret and SafeAbbreviatePerSec(perSec) or DM.FormatNumber(perSec))
        else
          bar._value:SetFormattedText("%s", totalSecret and SafeAbbreviateTotal(total) or DM.FormatNumber(total))
        end
      else
        -- Non-secret path: format with our own formatter
        local fmtTotal = DM.FormatNumber(total)
        local fmtPerSec = DM.FormatNumber(perSec)
        if valFormat == "both" then
          bar._value:SetText(fmtTotal .. " | " .. fmtPerSec)
        elseif valFormat == "persec" then bar._value:SetText(fmtPerSec)
        else bar._value:SetText(fmtTotal) end
      end

      if showPercent and not totalSecret and totalAll > 0 then
        local pct = math.floor(total / totalAll * 1000 + 0.5) / 10
        bar._pct:SetText("| " .. pct .. "%")
        if not bar._pct:IsShown() then
          bar._pct:ClearAllPoints(); bar._pct:SetPoint("RIGHT", -4, 0); bar._pct:Show()
          bar._value:ClearAllPoints(); bar._value:SetPoint("RIGHT", bar._pct, "LEFT", -4, 0)
        end
      else
        if bar._pct:IsShown() then
          bar._pct:Hide()
          bar._value:ClearAllPoints(); bar._value:SetPoint("RIGHT", -4, 0)
        end
      end

      bar._sourceGUID = src.sourceGUID
      bar._sourceCreatureID = src.sourceCreatureID
      bar._sourceName = srcName
      bar._sourceClass = src.classFilename
      bar._isLocalPlayer = src.isLocalPlayer
      bar._windowObj = w
      if srcName and src.sourceGUID and not isSecret(src.sourceGUID) then
        if not guidCache[srcName] then
          if guidCacheSize >= GUID_CACHE_MAX then wipe(guidCache); guidCacheSize = 0 end
          guidCacheSize = guidCacheSize + 1
        end
        guidCache[srcName] = src.sourceGUID
      end
      bar:EnableMouse(true)
    else
      bar:Hide()
    end
  end

  -- Total bar: shows group total at the very top
  local tbar = w._totalBar
  if showTotalBar and totalAll > 0 and inGroup and not isSecret(totalAll) then
    tbar:SetHeight(barH)
    tbar:ClearAllPoints()
    tbar:SetPoint("TOPLEFT", w.barContainer, "TOPLEFT", 0, 0)
    tbar:SetPoint("RIGHT", w.barContainer, "RIGHT", 0, 0)
    tbar:SetStatusBarTexture(barTexture)
    tbar:SetMinMaxValues(0, 1); tbar:SetValue(1)
    w._totalBarValue:SetText(DM.FormatNumber(totalAll))
    w._totalBarValue:SetFont(fontPath, fontSize, fontFlags)
    w._totalBarLabel:SetFont(fontPath, fontSize, fontFlags)
    tbar:Show()
    -- Separator below total bar
    w._totalBarSep:ClearAllPoints()
    w._totalBarSep:SetPoint("TOPLEFT", w.barContainer, "TOPLEFT", 2, -(barH + 1))
    w._totalBarSep:SetPoint("RIGHT", w.barContainer, "RIGHT", -2, 0)
    w._totalBarSep:Show()
  else
    tbar:Hide()
    w._totalBarSep:Hide()
  end

  -- "Always Show Self" logic
  if DB("dmAlwaysShowSelf") == false then
    if w._selfBar then w._selfBar:Hide() end
    if w._selfSep then w._selfSep:Hide() end
    return
  end
  if not w._selfBar then
    local sb = CreateBar(w.barContainer, MAX_BARS + 1)
    sb:Hide()
    w._selfBar = sb
    local sep = w.barContainer:CreateTexture(nil, "OVERLAY")
    sep:SetHeight(1)
    sep:SetColorTexture(0.3, 0.3, 0.3, 0.5)
    sep:Hide()
    w._selfSep = sep
  end

  local selfShown = false
  local barsShown = math.min(#sources, MAX_BARS)
  for i = 1, barsShown do
    if sources[i] and sources[i].isLocalPlayer then selfShown = true; break end
  end

  if not selfShown and #sources > MAX_BARS then
    local selfSrc
    for i = MAX_BARS + 1, #sources do
      if sources[i] and sources[i].isLocalPlayer then selfSrc = sources[i]; break end
    end
    if selfSrc then
      local sbar = w._selfBar
      local cr, cg, cb
      if classColors then
        cr, cg, cb = GetClassColor(selfSrc.classFilename)
      else
        cr, cg, cb = barColor.r, barColor.g, barColor.b
      end
      sbar:SetStatusBarTexture(barTexture)
      sbar:SetStatusBarColor(cr, cg, cb, barAlpha)
      sbar:SetMinMaxValues(0, maxVal)
      local selfInitTotal = selfSrc.totalAmount or 0
      sbar:SetValue(isSecret(selfInitTotal) and 0 or selfInitTotal)
      sbar:SetHeight(barH)

      -- BUG FIX: refresh spec icon on every update (not only when _setupDone is unset)
      -- This ensures spec icon updates correctly after a spec change mid-session
      sbar._icon:SetSize(iconSize, iconSize)
      if iconMode == "spec" and selfSrc.specIconID and not isSecret(selfSrc.specIconID) and selfSrc.specIconID > 0 then
        sbar._icon:SetTexture(selfSrc.specIconID); sbar._icon:SetTexCoord(0, 1, 0, 1); sbar._icon:Show()
      elseif iconMode ~= "none" and selfSrc.classFilename and not isSecret(selfSrc.classFilename) then
        local coords = CLASS_ICON_COORDS[selfSrc.classFilename:upper()]
        if coords then
          sbar._icon:SetTexture("Interface/GLUES/CHARACTERCREATE/UI-CHARACTERCREATE-CLASSES")
          sbar._icon:SetTexCoord(unpack(coords)); sbar._icon:Show()
        else sbar._icon:Hide() end
      else sbar._icon:Hide() end

      -- Static text setup (font, color) — only redo when configStamp changes
      if sbar._lastConfigStamp ~= configStamp then
        sbar._lastConfigStamp = configStamp
        sbar._name:SetTextColor(tr, tg, tb); sbar._name:SetFont(fontPath, fontSize, fontFlags)
        sbar._value:SetTextColor(tr, tg, tb); sbar._value:SetFont(fontPath, fontSize, fontFlags)
        if fontShadowVal > 0 then
          sbar._name:SetShadowOffset(fontShadowVal, -fontShadowVal); sbar._name:SetShadowColor(0, 0, 0, 1)
          sbar._value:SetShadowOffset(fontShadowVal, -fontShadowVal); sbar._value:SetShadowColor(0, 0, 0, 1)
        else
          sbar._name:SetShadowOffset(0, 0); sbar._value:SetShadowOffset(0, 0)
        end
        sbar._bg:SetTexture(barBgTexture); sbar._bg:SetVertexColor(0.05, 0.05, 0.05, 0.8)
      end

      -- Name (update every tick in case name becomes un-secret)
      local selfName = selfSrc.name
      if not isSecret(selfName) and selfName then selfName = selfName:match("^([^%-]+)") or selfName end
      sbar._name:ClearAllPoints(); sbar._name:SetPoint("LEFT", nameOffset, 0)
      sbar._name:SetText(selfName or "?")

      -- Fast update
      local total = selfSrc.totalAmount or 0
      local perSec = selfSrc.amountPerSecond or 0
      sbar:SetStatusBarColor(cr, cg, cb, barAlpha)
      sbar:SetMinMaxValues(0, maxVal)
      sbar:SetValue(total)
      local sTotalSecret = isSecret(total)
      local sPerSecSecret = isSecret(perSec)
      if sTotalSecret or sPerSecSecret then
        if valFormat == "both" then
          sbar._value:SetFormattedText("%s | %s",
            sTotalSecret and SafeAbbreviateTotal(total) or DM.FormatNumber(total),
            sPerSecSecret and SafeAbbreviatePerSec(perSec) or DM.FormatNumber(perSec))
        elseif valFormat == "persec" then
          sbar._value:SetFormattedText("%s", sPerSecSecret and SafeAbbreviatePerSec(perSec) or DM.FormatNumber(perSec))
        else
          sbar._value:SetFormattedText("%s", sTotalSecret and SafeAbbreviateTotal(total) or DM.FormatNumber(total))
        end
      else
        local fTotal = DM.FormatNumber(total)
        local fPerSec = DM.FormatNumber(perSec)
        if valFormat == "both" then sbar._value:SetText(fTotal .. " | " .. fPerSec)
        elseif valFormat == "persec" then sbar._value:SetText(fPerSec)
        else sbar._value:SetText(fTotal) end
      end

      local selfY = barsShown * (barH + barSpacing) + 4
      w._selfSep:ClearAllPoints()
      w._selfSep:SetPoint("TOPLEFT", w.barContainer, "TOPLEFT", 2, -selfY + 2)
      w._selfSep:SetPoint("RIGHT", w.barContainer, "RIGHT", -2, 0)
      w._selfSep:Show()
      sbar:ClearAllPoints()
      sbar:SetPoint("TOPLEFT", w.barContainer, "TOPLEFT", 0, -selfY)
      sbar:SetPoint("RIGHT", w.barContainer, "RIGHT", 0, 0)
      sbar:Show()

      sbar._sourceGUID = selfSrc.sourceGUID
      sbar._sourceCreatureID = selfSrc.sourceCreatureID
      sbar._sourceName = selfSrc.name
      sbar._sourceClass = selfSrc.classFilename
      sbar._isLocalPlayer = true
      sbar._windowObj = w
      sbar:EnableMouse(true)
      sbar:SetScript("OnEnter", function(self) DM.ShowSpellBreakdown(self) end)
      sbar:SetScript("OnLeave", function() GameTooltip:Hide() end)
      sbar:SetScript("OnMouseUp", function(self)
        self._expanded = not self._expanded
        DM.ShowSpellBreakdown(self)
      end)
    else
      w._selfBar:Hide()
      w._selfSep:Hide()
    end
  else
    w._selfBar:Hide()
    w._selfSep:Hide()
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

-- ── Update display for all windows (with data refresh) ──────────────
function DM.UpdateDisplay()
  for _, w in ipairs(DM.windows) do
    RefreshWindowData(w)
    DM.UpdateWindowDisplay(w)
  end
end

-- ── Update display only (no data refresh, used by ticker) ───────────
function DM.UpdateDisplayOnly()
  for _, w in ipairs(DM.windows) do
    DM.UpdateWindowDisplay(w)
  end
end

-- ── Spell breakdown tooltip ───────────────────────────────────────────
function DM.ShowSpellBreakdown(bar)
  local guid = bar._sourceGUID
  local creatureID = bar._sourceCreatureID
  local sourceName = bar._sourceName
  local w = bar._windowObj

  local nameUsable = sourceName and not isSecret(sourceName)

  if guid and not isSecret(guid) and nameUsable then
    if not guidCache[sourceName] then
      if guidCacheSize >= GUID_CACHE_MAX then wipe(guidCache); guidCacheSize = 0 end
      guidCacheSize = guidCacheSize + 1
    end
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
          if guid then
            if not guidCache[sourceName] then
              if guidCacheSize >= GUID_CACHE_MAX then wipe(guidCache); guidCacheSize = 0 end
              guidCacheSize = guidCacheSize + 1
            end
            guidCache[sourceName] = guid
          end
          break
        end
      end
    end
  end

  if not guid and not creatureID then return end

  local ok, sourceData
  if w.sessionID then
    ok, sourceData = pcall(C_DamageMeter.GetCombatSessionSourceFromID,
      w.sessionID, w.meterType, guid, creatureID)
  else
    ok, sourceData = pcall(C_DamageMeter.GetCombatSessionSourceFromType,
      w.sessionType or 1, w.meterType, guid, creatureID)
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

  GameTooltip:AddDoubleLine("|cffccccccSpell Name|r", string.format("|cffcccccc%8s  %7s  %5s|r", "Amount", "DPS", "%"), 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)

  local totalAmount = sourceData.totalAmount or 0
  local maxSpells = bar._expanded and 999 or 10

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

  local topSpellAmount = 0
  if #spells > 0 and not isSecret(spells[1].totalAmount or 0) then
    topSpellAmount = spells[1].totalAmount or 0
  end

  local spellLineIndices = {}

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
      fmtAmount = SafeAbbreviateTotal(spellAmount)
    else
      fmtAmount = DM.FormatNumber(spellAmount)
    end
    if isSecret(spellDPS) then
      fmtDPS = SafeAbbreviatePerSec(spellDPS)
    else
      fmtDPS = DM.FormatNumber(spellDPS)
    end
    if not isSecret(spellAmount) and not isSecret(totalAmount) and totalAmount > 0 then
      pct = string.format("%.1f%%", spellAmount / totalAmount * 100)
    else
      pct = ""
    end

    local rightText = string.format("%8s  %7s  %5s", fmtAmount, fmtDPS, pct)
    GameTooltip:AddDoubleLine(
      spellIcon .. spellName,
      rightText,
      1, 1, 1, 0.8, 0.8, 0.8)

    local ratio = (topSpellAmount > 0 and not isSecret(spellAmount)) and (spellAmount / topSpellAmount) or 0
    spellLineIndices[#spellLineIndices + 1] = {line = GameTooltip:NumLines(), ratio = ratio}
  end

  if #spells > maxSpells then
    GameTooltip:AddLine("|cff808080... and " .. (#spells - maxSpells) .. " more (click to expand)|r")
  end

  GameTooltip:Show()
  if GameTooltip.SetBackdropColor then GameTooltip:SetBackdropColor(0.03, 0.03, 0.03, 0.95) end

  if not GameTooltip._dmBars then
    GameTooltip._dmBars = {}
    GameTooltip:HookScript("OnHide", function()
      if GameTooltip._dmBars then
        for _, b in ipairs(GameTooltip._dmBars) do b:Hide() end
      end
    end)
  end
  for _, b in ipairs(GameTooltip._dmBars) do b:Hide() end

  for idx, info in ipairs(spellLineIndices) do
    local leftText = _G["GameTooltipTextLeft" .. info.line]
    if leftText then
      local bgBar = GameTooltip._dmBars[idx]
      if not bgBar and idx <= 50 then
        bgBar = GameTooltip:CreateTexture(nil, "BACKGROUND", nil, 1)
        GameTooltip._dmBars[idx] = bgBar
      end
      pcall(function()
        bgBar:SetColorTexture(1, 1, 1, 0.2)
        bgBar:SetHeight(leftText:GetHeight() + 2)
        bgBar:ClearAllPoints()
        bgBar:SetPoint("LEFT", GameTooltip, "LEFT", 8, 0)
        bgBar:SetPoint("TOP", leftText, "TOP", 0, 1)
        local tooltipW = GameTooltip:GetWidth() - 16
        bgBar:SetWidth(math.max(1, tooltipW * info.ratio))
        bgBar:Show()
      end)
    end
  end
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
  -- NEW FEATURE: update click-through state when combat changes
  for _, w in ipairs(DM.windows) do
    ApplyClickThrough(w)
  end
end

-- ── Apply theme (accent color updates) ───────────────────────────────
function DM.ApplyTheme()
  if #DM.windows == 0 then return end
  local ar, ag, ab = NS.ChatGetAccentRGB()
  local tCol = NS.DB("dmTitleColor")
  if type(tCol) ~= "table" or not tCol.r then tCol = nil end
  for _, w in ipairs(DM.windows) do
    if w.titleText then
      if tCol then w.titleText:SetTextColor(tCol.r, tCol.g, tCol.b)
      else w.titleText:SetTextColor(1, 1, 1) end
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
  reportWin:SetBackdrop({bgFile=NS.TEX_WHITE, edgeFile=NS.TEX_WHITE, edgeSize=1})
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

  local titleBar = CreateFrame("Frame", nil, reportWin)
  titleBar:SetHeight(24)
  titleBar:SetPoint("TOPLEFT", 0, 0); titleBar:SetPoint("TOPRIGHT", 0, 0)
  local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
  titleBg:SetAllPoints(); titleBg:SetColorTexture(0.08, 0.08, 0.08, 1)
  local titleLine = titleBar:CreateTexture(nil, "OVERLAY")
  titleLine:SetHeight(1); titleLine:SetPoint("BOTTOMLEFT"); titleLine:SetPoint("BOTTOMRIGHT")
  titleLine:SetColorTexture(ar, ag, ab, 0.5)
  local title = titleBar:CreateFontString(nil, "OVERLAY")
  title:SetFont(NS.FONT, 10, "")
  title:SetPoint("LEFT", 8, 0)
  title:SetText("|cff" .. aHex .. ">|r Report Results")
  title:SetTextColor(0.85, 0.85, 0.85)

  local closeBtn = CreateFrame("Button", nil, titleBar)
  closeBtn:SetSize(16, 16); closeBtn:SetPoint("RIGHT", -4, 0)
  local closeTex = closeBtn:CreateFontString(nil, "OVERLAY")
  closeTex:SetFont(NS.FONT, 11, ""); closeTex:SetPoint("CENTER")
  closeTex:SetText("x"); closeTex:SetTextColor(0.4, 0.4, 0.4)
  closeBtn:SetScript("OnEnter", function() closeTex:SetTextColor(1, 0.3, 0.3) end)
  closeBtn:SetScript("OnLeave", function() closeTex:SetTextColor(0.4, 0.4, 0.4) end)
  closeBtn:SetScript("OnClick", function() reportWin:Hide() end)

  local PAD = 12
  local yOff = -32

  local selectedChannel = "SAY"

  local channels = {}
  channels[#channels + 1] = {label = "Say", ch = "SAY"}
  if GetNumSubgroupMembers() > 0 then channels[#channels + 1] = {label = "Party", ch = "PARTY"} end
  if IsInRaid() then channels[#channels + 1] = {label = "Raid", ch = "RAID"} end
  if IsInInstance() then channels[#channels + 1] = {label = "Instance", ch = "INSTANCE_CHAT"} end
  if IsInGuild() then channels[#channels + 1] = {label = "Guild", ch = "GUILD"} end
  channels[#channels + 1] = {label = "Whisper", ch = "WHISPER"}

  if IsInRaid() then selectedChannel = "RAID"
  elseif GetNumSubgroupMembers() > 0 then selectedChannel = "PARTY"
  elseif IsInInstance() then selectedChannel = "INSTANCE_CHAT" end

  local chanLabel = reportWin:CreateFontString(nil, "OVERLAY")
  chanLabel:SetFont(NS.FONT, 10, "")
  chanLabel:SetPoint("TOPLEFT", PAD, yOff)
  chanLabel:SetText("|cff808080Channel|r")

  yOff = yOff - 16
  local chanBtn = CreateFrame("Button", nil, reportWin, "BackdropTemplate")
  chanBtn:SetSize(WIN_W - PAD * 2, 24)
  chanBtn:SetPoint("TOPLEFT", PAD, yOff)
  chanBtn:SetBackdrop({bgFile=NS.TEX_WHITE, edgeFile=NS.TEX_WHITE, edgeSize=1})
  chanBtn:SetBackdropColor(0.08, 0.08, 0.08, 1)
  chanBtn:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
  local chanBtnText = chanBtn:CreateFontString(nil, "OVERLAY")
  chanBtnText:SetFont(NS.FONT, 10, "")
  chanBtnText:SetPoint("LEFT", 8, 0)
  chanBtnText:SetTextColor(0.9, 0.9, 0.9)
  local chanArrow = chanBtn:CreateFontString(nil, "OVERLAY")
  chanArrow:SetFont(NS.FONT, 9, "")
  chanArrow:SetPoint("RIGHT", -6, 0)
  chanArrow:SetTextColor(ar, ag, ab); chanArrow:SetText("v")

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
    chanPopup:SetBackdrop({bgFile=NS.TEX_WHITE, edgeFile=NS.TEX_WHITE, edgeSize=1})
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
      lbl:SetFont(NS.FONT, 10, ""); lbl:SetPoint("LEFT", 8, 0)
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

  local whisperLabel = reportWin:CreateFontString(nil, "OVERLAY")
  whisperLabel:SetFont(NS.FONT, 10, "")
  whisperLabel:SetPoint("TOPLEFT", PAD, yOff)
  whisperLabel:SetText("|cff808080Whisper Target|r")

  yOff = yOff - 16
  local whisperBox = CreateFrame("EditBox", nil, reportWin, "BackdropTemplate")
  whisperBox:SetSize(WIN_W - PAD * 2, 22)
  whisperBox:SetPoint("TOPLEFT", PAD, yOff)
  whisperBox:SetBackdrop({bgFile=NS.TEX_WHITE, edgeFile=NS.TEX_WHITE, edgeSize=1})
  whisperBox:SetBackdropColor(0.08, 0.08, 0.08, 1)
  whisperBox:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
  whisperBox:SetFont(NS.FONT, 10, "")
  whisperBox:SetTextColor(0.9, 0.9, 0.9)
  whisperBox:SetTextInsets(8, 8, 0, 0)
  whisperBox:SetAutoFocus(false)
  if UnitExists("target") and UnitIsPlayer("target") then
    local fullName = GetUnitName("target", true)
    if fullName then whisperBox:SetText(fullName) end
  end
  whisperBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  whisperBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

  yOff = yOff - 28

  local linesVal = 5
  local linesRow = CreateFrame("Frame", nil, reportWin)
  linesRow:SetSize(WIN_W - PAD * 2, 24)
  linesRow:SetPoint("TOPLEFT", PAD, yOff)

  local linesLabel2 = linesRow:CreateFontString(nil, "OVERLAY")
  linesLabel2:SetFont(NS.FONT, 10, "")
  linesLabel2:SetPoint("LEFT", 0, 0)
  linesLabel2:SetText("|cff808080Lines:|r")

  local linesNumText = linesRow:CreateFontString(nil, "OVERLAY")
  linesNumText:SetFont(NS.FONT, 11, "")
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
    btn:SetBackdrop({bgFile=NS.TEX_WHITE, edgeFile=NS.TEX_WHITE, edgeSize=1})
    btn:SetBackdropColor(0.08, 0.08, 0.08, 1)
    btn:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    local lbl = btn:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(NS.FONT, 12, ""); lbl:SetPoint("CENTER"); lbl:SetText(text)
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

  reportWin:SetHeight(math.abs(yOff) + 26 + PAD)
  local sendBtn = CreateFrame("Button", nil, reportWin, "BackdropTemplate")
  sendBtn:SetSize(WIN_W - PAD * 2, 26)
  sendBtn:SetPoint("TOPLEFT", PAD, yOff)
  sendBtn:SetBackdrop({bgFile=NS.TEX_WHITE, edgeFile=NS.TEX_WHITE, edgeSize=1})
  sendBtn:SetBackdropColor(ar * 0.25, ag * 0.25, ab * 0.25, 1)
  sendBtn:SetBackdropBorderColor(ar, ag, ab, 1)
  local sendLbl = sendBtn:CreateFontString(nil, "OVERLAY")
  sendLbl:SetFont(NS.FONT, 11, "")
  sendLbl:SetPoint("CENTER"); sendLbl:SetText("Send"); sendLbl:SetTextColor(1, 1, 1)
  sendBtn:SetScript("OnEnter", function() sendBtn:SetBackdropColor(ar * 0.4, ag * 0.4, ab * 0.4, 1) end)
  sendBtn:SetScript("OnLeave", function() sendBtn:SetBackdropColor(ar * 0.25, ag * 0.25, ab * 0.25, 1) end)
  sendBtn:SetScript("OnClick", function()
    local ch = selectedChannel
    local target = whisperBox:GetText()
    if not ch then return end
    if ch == "WHISPER" and (not target or target == "") then return end

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
        table.sort(sources, function(a, b)
          local ta, tb = a.totalAmount or 0, b.totalAmount or 0
          if isSecret(ta) or isSecret(tb) then return false end
          return ta > tb
        end)
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
          local cleanTarget = target:gsub("%s+", ""):gsub("(%a)([%a]*)", function(first, rest)
            return first:upper() .. rest:lower()
          end)
          C_ChatInfo.SendChatMessage(line, ch, nil, cleanTarget)
        else
          C_ChatInfo.SendChatMessage(line, ch)
        end
      end)
    end
    reportWin:Hide()
  end)

  reportWin:Show()
end