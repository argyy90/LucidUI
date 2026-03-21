-- LucidUI Debug Window
-- Categorized debug log with filter, pause, and persistent history.

local NS = LucidUINS
local L  = LucidUIL
NS.Debug = NS.Debug or {}

local debugWin = nil
local smf = nil
local isPaused = false
local MAX_LINES = 500

-- Categories with colors
local CATEGORIES = {
  EVENT   = {0.5, 0.8, 1},
  LOOT    = {0, 0.67, 0},
  ROLL    = {1, 0.8, 0.2},
  STATS   = {0.8, 0.5, 1},
  CONFIG  = {1, 1, 0},
  SKIN    = {0, 1, 1},
  MESSAGE = {0.7, 0.7, 0.7},
  ERROR   = {1, 0.3, 0.3},
  INFO    = {0.6, 0.6, 0.6},
}

local activeFilter = "ALL"

local function GetAccentColor()
  return NS.CYAN[1], NS.CYAN[2], NS.CYAN[3]
end

local function GetIconColor()
  local ic = NS.DB("chatIconColor")
  if ic and type(ic) == "table" and ic.r then return ic.r, ic.g, ic.b end
  return 0.5, 0.5, 0.5
end

-- Log storage for filtering
local logEntries = {}

local function AddLogEntry(category, text, r, g, b)
  if isPaused then return end
  local ts = date("%H:%M:%S")
  local catColor = CATEGORIES[category] or CATEGORIES.INFO
  r = r or catColor[1]
  g = g or catColor[2]
  b = b or catColor[3]

  local catHex = string.format("%02x%02x%02x", catColor[1] * 255, catColor[2] * 255, catColor[3] * 255)
  local formatted = "|cff737373" .. ts .. "|r |cff" .. catHex .. "[" .. category .. "]|r " .. text

  local entry = {cat = category, text = formatted, r = r, g = g, b = b}
  table.insert(logEntries, entry)
  while #logEntries > MAX_LINES do
    table.remove(logEntries, 1)
  end

  -- Save to persistent history
  local history = NS.DB("debugHistory")
  if history and type(history) == "table" then
    table.insert(history, entry)
    while #history > MAX_LINES do
      table.remove(history, 1)
    end
  end

  if smf and (activeFilter == "ALL" or activeFilter == category) then
    smf:AddMessage(formatted, r, g, b)
  end
end

-- Public API
function NS.Debug.Log(category, text, r, g, b)
  AddLogEntry(category or "INFO", text or "", r, g, b)
end

-- Smart DebugLog: auto-detect category from text prefix
NS.DebugLog = function(text, r, g, b)
  if not text then return end
  -- Auto-categorize based on text content
  local cat = "INFO"
  if text:match("^ROLL") or text:match("^roll") then cat = "ROLL"
  elseif text:match("^EVENT") or text:match("^OnLoot") then cat = "EVENT"
  elseif text:match("^LOOT") or text:match("^ALLOWED") or text:match("^BLOCKED") then cat = "LOOT"
  elseif text:match("^STATS") or text:match("^stat") then cat = "STATS"
  elseif text:match("^CONFIG") or text:match("^Setting") then cat = "CONFIG"
  elseif text:match("^SKIN") or text:match("^Refresh") then cat = "SKIN"
  elseif text:match("^ERROR") or text:match("^error") then cat = "ERROR"
  end
  AddLogEntry(cat, text, r, g, b)
end

local function RefreshDisplay()
  if not smf then return end
  smf:Clear()
  for _, entry in ipairs(logEntries) do
    if activeFilter == "ALL" or activeFilter == entry.cat then
      smf:AddMessage(entry.text, entry.r, entry.g, entry.b)
    end
  end
end

NS.BuildDebugWindow = function()
  if debugWin then
    debugWin:SetShown(not debugWin:IsShown())
    return
  end

  local ar, ag, ab = GetAccentColor()

  local function SaveDebugPos()
    if not debugWin then return end
    local point, _, relPoint, x, y = debugWin:GetPoint(1)
    NS.DBSet("debugWinPos", {point, relPoint, math.floor(x), math.floor(y)})
  end
  local function SaveDebugSize()
    if not debugWin then return end
    NS.DBSet("debugWinSize", {math.floor(debugWin:GetWidth()), math.floor(debugWin:GetHeight())})
  end

  debugWin = CreateFrame("Frame", "LucidUIDebugWindow", UIParent, "BackdropTemplate")
  local size = NS.DB("debugWinSize") or {600, 400}
  debugWin:SetSize(size[1], size[2])
  local pos = NS.DB("debugWinPos")
  if pos then
    debugWin:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
  else
    debugWin:SetPoint("CENTER")
  end
  debugWin:SetFrameStrata("MEDIUM")
  debugWin:SetToplevel(true)
  debugWin:SetMovable(true)
  debugWin:SetResizable(true)
  debugWin:SetResizeBounds(400, 200)
  debugWin:SetClampedToScreen(true)
  debugWin:EnableMouse(true)
  debugWin:SetBackdrop({bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1})
  debugWin:SetBackdropColor(0.02, 0.02, 0.02, 0.97)
  debugWin:SetBackdropBorderColor(0.15, 0.15, 0.15, 1)
  debugWin:RegisterForDrag("LeftButton")
  debugWin:SetScript("OnDragStart", debugWin.StartMoving)
  debugWin:SetScript("OnDragStop", function() debugWin:StopMovingOrSizing(); SaveDebugPos() end)
  debugWin:SetScript("OnSizeChanged", SaveDebugSize)
  NS.debugWin = debugWin

  -- Title bar
  local titleBar = CreateFrame("Frame", nil, debugWin, "BackdropTemplate")
  titleBar:SetHeight(22)
  titleBar:SetPoint("TOPLEFT", 1, -1)
  titleBar:SetPoint("TOPRIGHT", -1, -1)
  titleBar:SetBackdrop({bgFile = "Interface/Buttons/WHITE8X8"})
  titleBar:SetBackdropColor(0.06, 0.06, 0.06, 1)
  titleBar:EnableMouse(true)
  titleBar:RegisterForDrag("LeftButton")
  titleBar:SetScript("OnDragStart", function() debugWin:StartMoving() end)
  titleBar:SetScript("OnDragStop", function() debugWin:StopMovingOrSizing(); SaveDebugPos() end)

  local hex = string.format("%02x%02x%02x", ar * 255, ag * 255, ab * 255)
  local titleTxt = titleBar:CreateFontString(nil, "OVERLAY")
  titleTxt:SetFont("Fonts/FRIZQT__.TTF", 11, "")
  titleTxt:SetPoint("LEFT", 8, 0)
  titleTxt:SetTextColor(1, 1, 1, 1)
  titleTxt:SetText("|cff" .. hex .. ">|r " .. L["Debug"] .. " |cff" .. hex .. "<|r")
  debugWin._titleTxt = titleTxt

  -- Accent line
  local accentLine = debugWin:CreateTexture(nil, "ARTWORK")
  accentLine:SetHeight(1)
  accentLine:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, 0)
  accentLine:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
  accentLine:SetColorTexture(ar, ag, ab, 0.6)
  debugWin._accentLine = accentLine

  -- Close button (same style as other windows)
  local closeBtn = CreateFrame("Button", nil, titleBar)
  closeBtn:SetSize(20, 20)
  closeBtn:SetPoint("TOPRIGHT", -2, -1)
  closeBtn:SetFrameStrata("HIGH")
  local closeTxt = closeBtn:CreateFontString(nil, "ARTWORK")
  closeTxt:SetFont("Fonts/FRIZQT__.TTF", 13, ""); closeTxt:SetPoint("CENTER")
  closeTxt:SetTextColor(0.55, 0.55, 0.55, 1); closeTxt:SetText("X")
  closeBtn:SetScript("OnEnter", function() closeTxt:SetTextColor(NS.CYAN[1], NS.CYAN[2], NS.CYAN[3], 1) end)
  closeBtn:SetScript("OnLeave", function() closeTxt:SetTextColor(0.55, 0.55, 0.55, 1) end)
  closeBtn:SetScript("OnClick", function() debugWin:Hide() end)

  -- Collapse button
  local collapseBtn = CreateFrame("Button", nil, titleBar)
  collapseBtn:SetSize(20, 20)
  collapseBtn:SetPoint("RIGHT", closeBtn, "LEFT", -2, 0)
  collapseBtn:SetFrameLevel(titleBar:GetFrameLevel() + 5)
  local collapseTex = collapseBtn:CreateTexture(nil, "ARTWORK")
  collapseTex:SetTexture("Interface/AddOns/LucidUI/Assets/ScrollToBottom.png")
  collapseTex:SetSize(12, 12)
  collapseTex:SetPoint("CENTER")
  do local r2,g2,b2 = GetIconColor(); collapseTex:SetVertexColor(r2, g2, b2, 1) end

  -- Copy button (next to collapse)
  local copyBtn = CreateFrame("Button", nil, titleBar)
  copyBtn:SetSize(20, 20)
  copyBtn:SetPoint("RIGHT", collapseBtn, "LEFT", -2, 0)
  copyBtn:SetFrameLevel(titleBar:GetFrameLevel() + 5)
  local copyTex = copyBtn:CreateTexture(nil, "ARTWORK")
  copyTex:SetTexture("Interface/AddOns/LucidUI/Assets/Copy.png")
  copyTex:SetSize(12, 12)
  copyTex:SetPoint("CENTER")
  do local r3,g3,b3 = GetIconColor(); copyTex:SetVertexColor(r3, g3, b3, 1) end
  copyBtn:SetScript("OnEnter", function()
    copyTex:SetVertexColor(NS.CYAN[1], NS.CYAN[2], NS.CYAN[3], 1)
    GameTooltip:SetOwner(copyBtn, "ANCHOR_LEFT"); GameTooltip:SetText(L["Copy Log"]); GameTooltip:Show()
  end)
  copyBtn:SetScript("OnLeave", function()
    local r3,g3,b3 = GetIconColor(); copyTex:SetVertexColor(r3, g3, b3, 1); GameTooltip:Hide()
  end)
  copyBtn:SetScript("OnClick", function()
    -- Toggle: close if already open
    local existing = _G["LTDebugCopyFrame"]
    if existing and existing:IsShown() then existing:Hide(); return end

    -- Build plain text from log entries
    local lines = {}
    for _, entry in ipairs(logEntries) do
      if activeFilter == "ALL" or activeFilter == entry.cat then
        local clean = entry.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        table.insert(lines, clean)
      end
    end
    if #lines == 0 then lines[1] = "(No log entries)" end
    local text = table.concat(lines, "\n")
    if existing then existing:Hide() end
    local frame = CreateFrame("Frame", "LTDebugCopyFrame", UIParent, "BackdropTemplate")
    frame:SetSize(500, 300); frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG"); frame:SetMovable(true); frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    frame:EnableMouse(true)
    frame:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
    frame:SetBackdropColor(0.06, 0.06, 0.06, 0.95); frame:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
    local cTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cTitle:SetPoint("TOP", 0, -6); cTitle:SetText(">" .. L["Copy Debug Log"] .. "<")
    cTitle:SetTextColor(NS.CYAN[1], NS.CYAN[2], NS.CYAN[3])
    local cClose = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    cClose:SetPoint("TOPRIGHT", 2, 2)
    cClose:SetScript("OnClick", function() frame:Hide() end)
    local sf = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 10, -22); sf:SetPoint("BOTTOMRIGHT", -30, 10)
    local eb = CreateFrame("EditBox", nil, frame)
    eb:SetMultiLine(true); eb:SetAutoFocus(true); eb:SetFontObject(GameFontHighlight); eb:SetWidth(460)
    eb:SetScript("OnEscapePressed", function() frame:Hide() end)
    sf:SetScrollChild(eb)
    C_Timer.After(0, function()
      if not frame:IsShown() then return end
      eb:SetWidth(sf:GetWidth()); eb:SetText(text); eb:HighlightText()
    end)
  end)

  -- Collapse/expand state
  local savedSize = NS.DB("debugWinSize") or {600, 400}
  -- Forward declare filterBar so collapse can hide it
  local filterBar
  if savedSize[2] <= 30 then
    debugWin.collapsed = true
    debugWin.expandedHeight = 400
    collapseTex:SetTexCoord(0, 1, 1, 0)
  else
    debugWin.collapsed = false
    debugWin.expandedHeight = savedSize[2]
  end
  collapseBtn:SetScript("OnClick", function()
    if not debugWin.collapsed then
      debugWin.expandedHeight = debugWin:GetHeight()
      debugWin.collapsed = true
      collapseTex:SetTexCoord(0, 1, 1, 0)
      debugWin:SetHeight(24)
      if filterBar then filterBar:Hide() end
    else
      debugWin.collapsed = false
      collapseTex:SetTexCoord(0, 1, 0, 1)
      if debugWin.expandedHeight and debugWin.expandedHeight > 30 then
        debugWin:SetHeight(debugWin.expandedHeight)
      else
        debugWin:SetHeight(400)
      end
      if filterBar then filterBar:Show() end
    end
  end)
  collapseBtn:SetScript("OnEnter", function() collapseTex:SetVertexColor(NS.CYAN[1], NS.CYAN[2], NS.CYAN[3], 1) end)
  collapseBtn:SetScript("OnLeave", function() local r2,g2,b2 = GetIconColor(); collapseTex:SetVertexColor(r2, g2, b2, 1) end)

  -- Filter buttons bar
  filterBar = CreateFrame("Frame", nil, debugWin)
  filterBar:SetHeight(20)
  if debugWin.collapsed then filterBar:Hide() end
  filterBar:SetPoint("TOPLEFT", 4, -25)
  filterBar:SetPoint("TOPRIGHT", -4, -25)

  local filters = {"ALL", "EVENT", "LOOT", "ROLL", "STATS", "CONFIG", "SKIN", "ERROR"}
  local filterBtns = {}
  local xOff = 0
  for _, cat in ipairs(filters) do
    local btn = CreateFrame("Button", nil, filterBar)
    local catColor = CATEGORIES[cat] or {1, 1, 1}
    local btnW = cat == "ALL" and 30 or 50
    btn:SetSize(btnW, 16)
    btn:SetPoint("LEFT", xOff, 0)
    local txt = btn:CreateFontString(nil, "OVERLAY")
    txt:SetFont("Fonts/FRIZQT__.TTF", 8, "")
    txt:SetPoint("CENTER")
    local isActive = activeFilter == cat
    if cat == "ALL" then
      txt:SetTextColor(1, 1, 1, isActive and 1 or 0.4)
    else
      txt:SetTextColor(catColor[1], catColor[2], catColor[3], isActive and 1 or 0.4)
    end
    txt:SetText(cat)
    btn:SetScript("OnClick", function()
      activeFilter = cat
      for _, fb in ipairs(filterBtns) do
        local fc = CATEGORIES[fb.cat] or {1, 1, 1}
        local active = activeFilter == fb.cat
        if fb.cat == "ALL" then
          fb.txt:SetTextColor(1, 1, 1, active and 1 or 0.4)
        else
          fb.txt:SetTextColor(fc[1], fc[2], fc[3], active and 1 or 0.4)
        end
      end
      RefreshDisplay()
    end)
    btn:SetScript("OnEnter", function()
      if cat == "ALL" then txt:SetTextColor(1, 1, 1, 1)
      else txt:SetTextColor(catColor[1], catColor[2], catColor[3], 1) end
    end)
    btn:SetScript("OnLeave", function()
      local active = activeFilter == cat
      if cat == "ALL" then txt:SetTextColor(1, 1, 1, active and 1 or 0.4)
      else txt:SetTextColor(catColor[1], catColor[2], catColor[3], active and 1 or 0.4) end
    end)
    table.insert(filterBtns, {btn = btn, cat = cat, txt = txt})
    xOff = xOff + btnW + 2
  end

  -- Pause/Clear buttons
  local pauseBtn = CreateFrame("Button", nil, filterBar)
  pauseBtn:SetSize(40, 16)
  pauseBtn:SetPoint("RIGHT", -45, 0)
  local pauseTxt = pauseBtn:CreateFontString(nil, "OVERLAY")
  pauseTxt:SetFont("Fonts/FRIZQT__.TTF", 8, "")
  pauseTxt:SetPoint("CENTER")
  pauseTxt:SetTextColor(1, 0.8, 0, 1)
  pauseTxt:SetText(L["PAUSE"])
  pauseBtn:SetScript("OnClick", function()
    isPaused = not isPaused
    pauseTxt:SetText(isPaused and L["RESUME"] or L["PAUSE"])
    pauseTxt:SetTextColor(isPaused and 0.3 or 1, isPaused and 1 or 0.8, isPaused and 0.3 or 0, 1)
  end)

  local clearBtn = CreateFrame("Button", nil, filterBar)
  clearBtn:SetSize(36, 16)
  clearBtn:SetPoint("RIGHT", 0, 0)
  local clearTxt = clearBtn:CreateFontString(nil, "OVERLAY")
  clearTxt:SetFont("Fonts/FRIZQT__.TTF", 8, "")
  clearTxt:SetPoint("CENTER")
  clearTxt:SetTextColor(1, 0.3, 0.3, 1)
  clearTxt:SetText(L["CLEAR"])
  clearBtn:SetScript("OnClick", function()
    wipe(logEntries)
    NS.DBSet("debugHistory", {})
    if smf then smf:Clear() end
  end)

  -- SMF
  smf = CreateFrame("ScrollingMessageFrame", nil, debugWin)
  smf:SetPoint("TOPLEFT", 6, -48)
  smf:SetPoint("BOTTOMRIGHT", -6, 20)
  smf:SetFont("Fonts/FRIZQT__.TTF", 11, "")
  smf:SetJustifyH("LEFT")
  smf:SetMaxLines(MAX_LINES)
  smf:SetFading(false)
  smf:SetInsertMode(SCROLLING_MESSAGE_FRAME_INSERT_MODE_BOTTOM)
  smf:EnableMouseWheel(true)
  smf:SetScript("OnMouseWheel", function(self, delta)
    if delta > 0 then self:ScrollUp() else self:ScrollDown() end
  end)
  NS.debugSMF = smf

  -- Resize grip
  local resizeWidget = CreateFrame("Frame", nil, debugWin)
  resizeWidget:SetSize(16, 16)
  resizeWidget:SetPoint("BOTTOMRIGHT")
  resizeWidget:SetFrameLevel(debugWin:GetFrameLevel() + 50)
  resizeWidget:EnableMouse(true)
  local rTex = resizeWidget:CreateTexture(nil, "OVERLAY")
  rTex:SetTexture("Interface/AddOns/LucidUI/Assets/resize.png")
  rTex:SetTexCoord(0, 0, 0, 1, 1, 0, 1, 1)
  rTex:SetAllPoints()
  do local r2,g2,b2 = GetIconColor(); rTex:SetVertexColor(r2, g2, b2, 0.8) end
  resizeWidget:SetScript("OnEnter", function() rTex:SetVertexColor(NS.CYAN[1], NS.CYAN[2], NS.CYAN[3], 1) end)
  resizeWidget:SetScript("OnLeave", function() local r2,g2,b2 = GetIconColor(); rTex:SetVertexColor(r2, g2, b2, 0.8) end)
  resizeWidget:SetScript("OnMouseDown", function() debugWin:StartSizing("BOTTOMRIGHT") end)
  resizeWidget:SetScript("OnMouseUp", function() debugWin:StopMovingOrSizing(); SaveDebugPos(); SaveDebugSize() end)

  -- Load history
  if #logEntries == 0 then
    local history = NS.DB("debugHistory")
    if history and type(history) == "table" then
      for _, entry in ipairs(history) do
        table.insert(logEntries, entry)
      end
    end
  end

  RefreshDisplay()
  NS.Debug.Log("INFO", "Debug window opened")
end

-- Initialize debug on login
local debugInitFrame = CreateFrame("Frame")
debugInitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
debugInitFrame:SetScript("OnEvent", function(self, _, isInitialLogin, isReloadingUi)
  self:UnregisterAllEvents()
  if isInitialLogin and not isReloadingUi then
    wipe(logEntries)
    NS.DBSet("debugHistory", {})
  else
    local history = NS.DB("debugHistory")
    if history and type(history) == "table" then
      for _, entry in ipairs(history) do
        table.insert(logEntries, entry)
      end
    end
  end
  NS.Debug.Log("INFO", "LucidUI Debug initialized")
end)
