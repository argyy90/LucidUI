-- LootRolls.lua  v4.0
local NS   = LucidUINS
local CYAN = NS.CYAN
local L    = LucidUIL

NS.rollBossFilter = nil -- nil = show all

-- ── Persist roll sessions across reload/DC ──────────────────────────────────
local function SaveRollSessions()
  if not LucidUIDB then return end
  -- Strip non-serializable fields (functions, UI refs) before saving
  local data = {}
  for id, s in pairs(NS.rollSessions) do
    local copy = {}
    for k, v in pairs(s) do
      if type(v) ~= "function" and type(v) ~= "userdata" then
        copy[k] = v
      end
    end
    -- Convert GetTime()-based timestamps to real-time offsets
    copy._timeOffset = time() - math.floor(GetTime() - (s.time or 0))
    if s._doneTime then
      copy._doneTimeOffset = time() - math.floor(GetTime() - s._doneTime)
    end
    data[id] = copy
  end
  LucidUIDB._rollData = data
  LucidUIDB._rollEncounter = NS.currentEncounterName
end

local function LoadRollSessions()
  local saved = LucidUIDB and LucidUIDB._rollData
  if saved then
    NS.rollSessions = {}
    for id, s in pairs(saved) do
      -- Restore GetTime()-based timestamps from real-time offsets
      if s._timeOffset then
        local elapsed = time() - s._timeOffset
        s.time = GetTime() - elapsed
      end
      if s._doneTimeOffset then
        local elapsed = time() - s._doneTimeOffset
        s._doneTime = GetTime() - elapsed
      end
      if s.rollExpires then
        -- Roll timer already expired after reload
        s.done = true
      end
      s._timeOffset = nil
      s._doneTimeOffset = nil
      NS.rollSessions[id] = s
    end
    NS.currentEncounterName = LucidUIDB._rollEncounter
  else
    NS.rollSessions = {}
    NS.currentEncounterName = nil
  end
end

-- Auto-save every 15s + on logout (only when rolls enabled)
local rollSaveFrame = CreateFrame("Frame")
local _rollSaveTicker = nil
local function EnableRollSave()
  if not _rollSaveTicker then
    _rollSaveTicker = C_Timer.NewTicker(15, SaveRollSessions)
  end
  rollSaveFrame:RegisterEvent("PLAYER_LOGOUT")
  rollSaveFrame:SetScript("OnEvent", function() SaveRollSessions() end)
end
local function DisableRollSave()
  if _rollSaveTicker then _rollSaveTicker:Cancel(); _rollSaveTicker = nil end
  rollSaveFrame:UnregisterAllEvents()
end
NS.EnableRollSave = EnableRollSave
NS.DisableRollSave = DisableRollSave

LoadRollSessions()

-- ============================================================
-- Constants
-- ============================================================
local WIN_W    = 300
local WIN_H    = 420
local TITLE_H  = 26
local BOTTOM_H = 32
local ROW_H    = 46
local HEADER_H = 20
local PAD      = 6
local ICON_SZ  = 34

-- Need > Greed/Disenchant/Transmog > Pass (lower = higher priority = wins)
local ROLL_PRIORITY = {need=1, greed=2, disenchant=2, transmog=2, pass=3}


local QUALITY_COLORS = {
  [0]={0.62,0.62,0.62}, [1]={1,1,1},           [2]={0.12,1,0},
  [3]={0,0.44,0.87},    [4]={0.64,0.21,0.93},  [5]={1,0.5,0},
}

local CLASS_COLORS = NS.CLASS_COLORS

local ROLL_ICONS = {
  need        = "Interface/Buttons/UI-GroupLoot-Dice-Up",
  greed       = "Interface/Buttons/UI-GroupLoot-Coin-Up",
  pass        = "Interface/Buttons/UI-GroupLoot-Pass-Up",
  disenchant  = "Interface/Buttons/UI-GroupLoot-DE-Up",
  transmog    = "Interface/Buttons/UI-GroupLoot-Coin-Up",
}
local ROLL_COLORS = {
  need        = {CYAN[1], CYAN[2], CYAN[3]},
  greed       = {1, 0.82, 0},
  pass        = {0.45, 0.45, 0.45},
  disenchant  = {0.2, 0.9, 0.4},
  transmog    = {0.7, 0.4, 0.9},
}

-- ============================================================
-- Helpers
-- ============================================================
local function QColor(q) return unpack(QUALITY_COLORS[q] or QUALITY_COLORS[1]) end

local function CCR(cls)
  local c = CLASS_COLORS[cls and cls:upper()]
  return c and c[1] or 0.75, c and c[2] or 0.75, c and c[3] or 0.75
end

local classCache = {}
local function GetPlayerClass(name)
  if classCache[name] then return classCache[name] end
  local numMembers = GetNumGroupMembers()
  for i = 1, numMembers do
    local unit = (IsInRaid() and "raid" or "party") .. i
    local uname = GetUnitName(unit, true)
    if uname == name or
       (uname and uname:match("^([^%-]+)") == name:match("^([^%-]+)")) then
      local _, cls = UnitClass(unit)
      if cls then classCache[name] = cls; return cls end
    end
  end
end


-- Sort: Need > Greed > Pass, then by roll value descending within same type
local function SortedRollers(rollers)
  local t = {}
  for pname, data in pairs(rollers or {}) do
    table.insert(t, {
      name     = pname,
      val      = data.val or data,
      rollType = data.rollType or "need",
      class    = data.class,
      winner   = data.winner,
    })
  end
  table.sort(t, function(a, b)
    local pa = ROLL_PRIORITY[a.rollType] or 99
    local pb = ROLL_PRIORITY[b.rollType] or 99
    if pa ~= pb then return pa < pb end
    return a.val > b.val
  end)
  return t
end

-- ============================================================
-- Theme helper – reads live from NS each call
-- ============================================================
local function GetRollsAlpha()
  local trans = NS.DB and NS.DB("rollsTransparency")
  if trans then return math.max(0.02, 0.97 - trans) end
  return 0.97
end

local function GetAccentColorRGB()
  if NS.CYAN then
    return {NS.CYAN[1], NS.CYAN[2], NS.CYAN[3], 1}
  end
  return {59/255, 210/255, 237/255, 1}
end

local function GetWinTheme()
  local t = NS.GetTheme(NS.DB("theme"))
  local alpha = GetRollsAlpha()
  local accent = GetAccentColorRGB()
  local bg = {t.bg[1], t.bg[2], t.bg[3], alpha}
  return {
    bg        = bg,
    border    = t.border,
    titleBg   = t.titleBg,
    titleText = t.titleText or {1,1,1,1},
    tilders   = accent,
  }
end

function NS.ApplyRollWinTheme()
  if not NS.rollWin then return end
  local t = GetWinTheme()
  NS.rollWin:SetBackdropColor(0.022,0.022,0.035,0.97)
  NS.rollWin:SetBackdropBorderColor(NS.CYAN[1],NS.CYAN[2],NS.CYAN[3],0.38)
  -- _titleBar is a plain Frame now (no backdrop) — skip SetBackdropColor
  if NS.rollWin._bottomBar and NS.rollWin._bottomBar.SetBackdropColor then
    NS.rollWin._bottomBar:SetBackdropColor(0.010,0.010,0.020,1)
  end
  -- Title text color + tilde/bracket color from theme
  if NS.rollWin._titleTxt then
    local tid = t.tilders    or {59/255,210/255,237/255,1}
    local tc  = t.titleText  or {1,1,1,1}
    local hex = string.format("%02x%02x%02x",
      math.floor(tid[1]*255), math.floor(tid[2]*255), math.floor(tid[3]*255))
    local f,r = L["LOOT ROLLS"]:match("^(%S+)%s*(.*)")
    NS.rollWin._titleTxt:SetText("|cff"..hex..(f or L["LOOT ROLLS"]).."|r"..(r and r ~= "" and (" |cffffffff"..r.."|r") or ""))
    NS.rollWin._titleTxt:SetTextColor(tc[1], tc[2], tc[3], 1)
  end
  -- Update filter dropdown arrow accent color
  if NS.rollWin._filterArrow then
    local tid2 = t.tilders or {59/255,210/255,237/255,1}
    NS.rollWin._filterArrow:SetTextColor(tid2[1], tid2[2], tid2[3], 1)
  end
  -- Accent line
  if NS.rollWin._accentLine then
    local cr, cg, cb = NS.CYAN[1], NS.CYAN[2], NS.CYAN[3]
    NS.rollWin._accentLine:SetColorTexture(cr, cg, cb, 0.6)
  end
  if NS.UpdatePCBTextures then NS.UpdatePCBTextures(NS.rollWin._pcbTextures) end
end

-- Hook NS.ApplyTheme so theme changes immediately update the roll window too
-- (runs after PLAYER_LOGIN once NS.ApplyTheme is guaranteed to exist)
local function HookApplyTheme()
  local orig = NS.ApplyTheme
  NS.ApplyTheme = function(themeKey)
    orig(themeKey)
    NS.ApplyRollWinTheme()
    if NS.rollWin and NS.rollWin:IsShown() then NS.RollWindowRedraw() end
  end
end

-- ============================================================
-- Animated dots ticker
-- ============================================================
local dotsTicker = nil
local dotsState  = 0
local dotsTargets = {}

local function StartDotsTicker()
  if dotsTicker then return end
  dotsTicker = C_Timer.NewTicker(0.5, function()
    dotsState = (dotsState % 3) + 1
    local dots = string.rep(".", dotsState)
    for _, e in ipairs(dotsTargets) do
      if e.lbl and type(e.lbl) == "table" and e.lbl.GetObjectType and e.lbl:GetObjectType() == "FontString" then
        e.lbl:SetText(e.base .. "|cff00dd55" .. dots .. "|r")
      end
    end
  end)
end

local function StopDotsTicker()
  if dotsTicker then dotsTicker:Cancel(); dotsTicker = nil end
  wipe(dotsTargets)
  dotsState = 0
end

local function RegisterDotsLabel(lbl, base)
  table.insert(dotsTargets, {lbl=lbl, base=base})
  StartDotsTicker()
end

-- ============================================================
-- Auto-close timer
-- ============================================================
local autoCloseTimer = nil
local function ScheduleAutoClose()
  if autoCloseTimer then autoCloseTimer:Cancel(); autoCloseTimer = nil end
  local mode  = (NS.DB and NS.DB("rollCloseMode"))  or "timer"
  if mode == "manual" then return end
  local delay = (NS.DB and NS.DB("rollCloseDelay")) or 15
  autoCloseTimer = C_Timer.NewTimer(delay, function()
    if NS.rollWin then NS.rollWin:Hide() end
    autoCloseTimer = nil
    StopDotsTicker()
  end)
end

-- ============================================================
-- Shared timer ticker for all active roll rows
-- Avoids per-row OnUpdate (expensive with many active rolls).
-- ============================================================
local _activeTimerRows = {}  -- weak-keyed set: row → true
setmetatable(_activeTimerRows, {__mode = "k"})
local _timerTicker = nil

local function StartTimerTicker()
  if _timerTicker then return end
  _timerTicker = C_Timer.NewTicker(0.1, function()
    local anyActive = false
    for row in pairs(_activeTimerRows) do
      if row._tick then
        local keepAlive = row._tick()
        if keepAlive then anyActive = true
        else _activeTimerRows[row] = nil end
      else
        _activeTimerRows[row] = nil
      end
    end
    if not anyActive and _timerTicker then
      _timerTicker:Cancel()
      _timerTicker = nil
    end
  end)
end

-- ============================================================
-- Build one item row (no sub-rows – all detail in tooltip)
-- ============================================================
local function BuildItemRow(parent, session, yOffset)
  local qr, qg, qb = QColor(session.quality or 1)
  local t = GetWinTheme()
  local pw = parent:GetWidth() - 2

  local BD2={bgFile=NS.TEX_WHITE,edgeFile=NS.TEX_WHITE,edgeSize=1}
  local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  row:SetSize(pw, ROW_H)
  row:SetPoint("TOPLEFT", 1, yOffset)
  row:SetBackdrop(BD2)
  row:SetBackdropColor(0.028,0.028,0.046,1)
  row:SetBackdropBorderColor(qr*0.22, qg*0.22, qb*0.22, 1)

  -- Left quality accent bar (cyberpunk style)
  local qBar=row:CreateTexture(nil,"OVERLAY",nil,5); qBar:SetWidth(3)
  qBar:SetPoint("TOPLEFT",0,-2); qBar:SetPoint("BOTTOMLEFT",0,2)
  qBar:SetColorTexture(qr,qg,qb,0.90)

  -- Tiny staircase corner decoration
  for i=0,2 do
    local st=row:CreateTexture(nil,"OVERLAY",nil,4); st:SetSize(5-i*2,1)
    st:SetPoint("TOPRIGHT",row,"TOPRIGHT",-(4+i*5),-(2+i*2))
    st:SetColorTexture(qr,qg,qb,0.20-i*0.05)
  end

  -- Icon quality border
  local iconBorder = row:CreateTexture(nil, "BACKGROUND")
  iconBorder:SetSize(ICON_SZ+2, ICON_SZ+2)
  iconBorder:SetPoint("LEFT", 3, 0)
  iconBorder:SetColorTexture(qr*0.5, qg*0.5, qb*0.5, 1)

  local iconTex = row:CreateTexture(nil, "ARTWORK")
  iconTex:SetSize(ICON_SZ-2, ICON_SZ-2)
  iconTex:SetPoint("CENTER", iconBorder, "CENTER")
  if session.icon and session.icon ~= "" then iconTex:SetTexture(session.icon) end

  -- Item name
  local nameLbl = row:CreateFontString(nil, "OVERLAY")
  nameLbl:SetFont(NS.FONT, 10, "")
  nameLbl:SetPoint("TOPLEFT", ICON_SZ + 10, -5)
  nameLbl:SetPoint("TOPRIGHT", -4, -5)
  nameLbl:SetJustifyH("LEFT")
  nameLbl:SetTextColor(qr, qg, qb, 1)
  nameLbl:SetText(session.name or "Unknown")

  -- Timer bar (shows remaining roll time)
  local timerBg = row:CreateTexture(nil, "BORDER")
  timerBg:SetHeight(3)
  timerBg:SetPoint("TOPLEFT", ICON_SZ + 10, -18)
  timerBg:SetPoint("TOPRIGHT", -4, -18)
  timerBg:SetColorTexture(0.15, 0.15, 0.15, 1)

  local timerBar = row:CreateTexture(nil, "ARTWORK")
  timerBar:SetHeight(3)
  timerBar:SetPoint("TOPLEFT", timerBg, "TOPLEFT")
  timerBar:SetColorTexture(qr, qg, qb, 0.8)

  if session.done or not session.rollExpires or session.rollExpires <= GetTime() then
    timerBar:SetWidth(0)
    timerBg:Hide()
    timerBar:Hide()
  else
    local totalDuration = (session.rollTime or 0) / 1000
    timerBg:Show()
    timerBar:Show()
    -- Shared ticker: each row exposes a _tick() that returns true while active.
    row._tick = function()
      local remaining = session.rollExpires - GetTime()
      if remaining <= 0 or session.done then
        timerBar:SetWidth(0)
        timerBg:Hide()
        timerBar:Hide()
        return false
      end
      local pct = totalDuration > 0 and (remaining / totalDuration) or 0
      timerBar:SetWidth(math.max(1, timerBg:GetWidth() * pct))
      return true
    end
    _activeTimerRows[row] = true
    StartTimerTicker()
  end

  -- "Passed" indicator (bottom right, shown when local player passed)
  local passedLbl = row:CreateFontString(nil, "OVERLAY")
  passedLbl:SetFont(NS.FONT, 9, "")
  passedLbl:SetPoint("BOTTOMRIGHT", -6, 5)
  passedLbl:SetTextColor(0.45, 0.45, 0.45)
  passedLbl:SetText("Passed")
  passedLbl:Hide()

  -- "Rolled" indicator (bottom right, shown when local player rolled need/greed/transmog)
  local rolledLbl = row:CreateFontString(nil, "OVERLAY")
  rolledLbl:SetFont(NS.FONT, 9, "")
  rolledLbl:SetPoint("BOTTOMRIGHT", -6, 5)
  rolledLbl:SetTextColor(1, 0.82, 0, 1)
  rolledLbl:SetText("Rolled")
  rolledLbl:Hide()

  -- Status line (winner or animated dots)
  local statusLbl = row:CreateFontString(nil, "OVERLAY")
  statusLbl:SetFont(NS.FONT, 11, "")
  statusLbl:SetPoint("BOTTOMLEFT", ICON_SZ + 10, 5)
  statusLbl:SetPoint("BOTTOMRIGHT", -70, 5)
  statusLbl:SetJustifyH("LEFT")

  local function RefreshStatus()
    local sorted = SortedRollers(session.rollers)

    -- Check if local player passed or rolled
    local playerName = UnitName("player")
    local playerRoll = playerName and session.rollers[playerName]
    if playerRoll and playerRoll.rollType == "pass" then
      passedLbl:Show()
      rolledLbl:Hide()
    elseif playerRoll and playerRoll.rollType ~= "pass" then
      rolledLbl:Show()
      passedLbl:Hide()
    else
      passedLbl:Hide()
      rolledLbl:Hide()
    end

    if #sorted == 0 then
      RegisterDotsLabel(statusLbl, "|cff555555Waiting")
    elseif session.done then
      -- Show only the winner in the row; all rollers visible in tooltip
      local winner = nil
      -- Prefer explicitly marked winner
      for _, r in ipairs(sorted) do
        if r.winner then winner = r; break end
      end
      if not winner then
        for _, r in ipairs(sorted) do
          if r.rollType ~= "pass" then winner = r; break end
        end
      end
      if winner then
        local cr, cg, cb = CCR(winner.class)
        local rc = ROLL_COLORS[winner.rollType] or ROLL_COLORS.need
        local shortName = winner.name:match("^([^%-]+)") or winner.name
        statusLbl:SetText(string.format(
          "|TInterface/AddOns/LucidUI/Assets/Star.png:13:13|t |cff%02x%02x%02x%s|r  |cff%02x%02x%02x%d|r",
          math.floor(cr*255), math.floor(cg*255), math.floor(cb*255), shortName,
          math.floor(rc[1]*255), math.floor(rc[2]*255), math.floor(rc[3]*255), winner.val))
      else
        statusLbl:SetText("|cff555555"..L["All passed"].."|r")
      end
    else
      -- Still rolling – show current leader + dots
      local leader = nil
      for _, r in ipairs(sorted) do
        if r.rollType ~= "pass" then leader = r; break end
      end
      if leader then
        local cr, cg, cb = CCR(leader.class)
        local base = string.format(
          "|cff%02x%02x%02x%s|r |cffFFD700%d|r ",
          math.floor(cr*255), math.floor(cg*255), math.floor(cb*255),
          leader.name:match("^([^%-]+)") or leader.name, leader.val)
        statusLbl:SetText(base)
        RegisterDotsLabel(statusLbl, base)
      else
        RegisterDotsLabel(statusLbl, "|cff555555Waiting")
      end
    end
  end
  session._refreshStatus = RefreshStatus
  RefreshStatus()

  -- ---- Tooltip with all rolls ----
  row:EnableMouse(true)
  row:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if session.link then
      GameTooltip:SetHyperlink(session.link)
    else
      GameTooltip:SetText(session.name or "?", qr, qg, qb)
    end

    local sorted = SortedRollers(session.rollers)
    if #sorted > 0 then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("|cff3bd2edLoot Rolls|r")

      -- Determine winner (first non-pass roller, or explicit .winner flag)
      local winnerName = nil
      for _, r in ipairs(sorted) do
        if r.winner then winnerName = r.name; break end
      end
      if not winnerName and session.done then
        for _, r in ipairs(sorted) do
          if r.rollType ~= "pass" then winnerName = r.name; break end
        end
      end

      for _, r in ipairs(sorted) do
        local cr, cg, cb = CCR(r.class)
        local icoPath = ROLL_ICONS[r.rollType] or ROLL_ICONS.need
        local ico = "|T" .. icoPath .. ":12:12|t"
        local valStr = (r.rollType == "pass" or r.val == 0) and "–" or tostring(r.val)
        local shortName = r.name:match("^([^%-]+)") or r.name
        local isWinner = (r.name == winnerName)
        local winIco = isWinner and " |TInterface/RaidFrame/ReadyCheck-Ready:12:12|t" or ""
        local nameColored = string.format("|cff%02x%02x%02x%s|r", cr*255, cg*255, cb*255, shortName)
        GameTooltip:AddLine(ico .. "  " .. valStr .. "  " .. nameColored .. winIco)
      end
    else
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("|cff555555No rolls yet...|r")
    end
    GameTooltip:Show()
    row:SetBackdropBorderColor(CYAN[1], CYAN[2], CYAN[3], 1)
  end)
  row:SetScript("OnLeave", function()
    GameTooltip:Hide()
    row:SetBackdropBorderColor(qr*0.28, qg*0.28, qb*0.28, 1)
  end)
  row:SetScript("OnMouseDown", function()
    if session.link and IsModifiedClick("CHATLINK") then
      ChatEdit_InsertLink(session.link)
    end
  end)

  -- Separator
  local sep = parent:CreateTexture(nil, "ARTWORK")
  sep:SetHeight(1)
  sep:SetPoint("TOPLEFT",  1, yOffset - ROW_H)
  sep:SetPoint("TOPRIGHT", -1, yOffset - ROW_H)
  sep:SetColorTexture(0.13, 0.13, 0.13, 1)

  return ROW_H + 3
end

-- ============================================================
-- Encounter header row
-- ============================================================
local function BuildEncounterHeader(parent, name, yOffset)
  local t   = GetWinTheme()
  local tid = t.tilders or {59/255, 210/255, 237/255, 1}
  local hex = string.format("%02x%02x%02x",
    math.floor(tid[1]*255), math.floor(tid[2]*255), math.floor(tid[3]*255))
  local pw  = parent:GetWidth() - 2

  local hdr = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  hdr:SetSize(pw, HEADER_H)
  hdr:SetPoint("TOPLEFT", 1, yOffset)
  hdr:SetBackdrop({bgFile=NS.TEX_WHITE, edgeFile=NS.TEX_WHITE, edgeSize=1})
  hdr:SetBackdropColor(
    t.titleBg[1] + 0.04, t.titleBg[2] + 0.04, t.titleBg[3] + 0.04, 1)
  hdr:SetBackdropBorderColor(tid[1]*0.35, tid[2]*0.35, tid[3]*0.35, 1)

  -- Accent line left (tilders color)
  -- Left accent bar (quality color)
  local accent = hdr:CreateTexture(nil, "ARTWORK")
  accent:SetWidth(3); accent:SetPoint("TOPLEFT", 0, 0); accent:SetPoint("BOTTOMLEFT", 0, 0)
  accent:SetColorTexture(tid[1], tid[2], tid[3], 1)
  -- Dashed separator below header (3 segments)
  for si=0,2 do
    local seg=hdr:CreateTexture(nil,"OVERLAY",nil,4); seg:SetSize(16,1)
    seg:SetPoint("BOTTOMLEFT",hdr,"BOTTOMLEFT",4+si*22,1)
    seg:SetColorTexture(tid[1],tid[2],tid[3],0.20)
  end

  local lbl = hdr:CreateFontString(nil, "OVERLAY")
  lbl:SetFont(NS.FONT, 10, "OUTLINE")
  lbl:SetPoint("LEFT", 8, 0)
  lbl:SetTextColor(1, 1, 1, 1)
  if NS.DB("showBrackets") ~= false then
    lbl:SetText("|cff"..hex..">|r " .. name)
  else
    lbl:SetText(name)
  end

  return HEADER_H + 2
end

-- ============================================================
-- Resize grip – bright diagonal lines, correct ╲ orientation
-- ============================================================
local function BuildResizeGrip(parent)
  local widget = CreateFrame("Frame", nil, parent)
  widget:SetSize(28, 28)
  widget:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
  widget:SetFrameLevel(parent:GetFrameLevel() + 50)
  widget:EnableMouse(true)

  local rTex = widget:CreateTexture(nil, "OVERLAY")
  rTex:SetTexture("Interface/AddOns/LucidUI/Assets/resize.png")
  rTex:SetTexCoord(0,0, 0,1, 1,0, 1,1)
  rTex:SetAllPoints()
  rTex:SetVertexColor(0.8, 0.8, 0.8, 0.8)

  widget:SetScript("OnEnter", function()
    rTex:SetVertexColor(CYAN[1], CYAN[2], CYAN[3], 1.0)
  end)
  widget:SetScript("OnLeave", function()
    rTex:SetVertexColor(0.8, 0.8, 0.8, 0.8)
  end)
  widget:SetScript("OnMouseDown", function()
    parent:StartSizing("BOTTOM")
  end)
  widget:SetScript("OnMouseUp", function()
    parent:StopMovingOrSizing()
    NS.RollWindowRedraw()
  end)
  return widget
end

-- ============================================================
-- Build window (once)
-- ============================================================
local function BuildRollWindow()
  if NS.rollWin then return end
  local t = GetWinTheme()

  local BD = NS.BACKDROP
  local ar,ag,ab = NS.CYAN[1],NS.CYAN[2],NS.CYAN[3]
  local HEADER_H_WIN = 34

  local win = CreateFrame("Frame", "LucidUIRollWindow", UIParent, "BackdropTemplate")
  win:SetSize(WIN_W, WIN_H)
  local rpos = LucidUIDB and LucidUIDB.rollWinPos
  if rpos then win:SetPoint(rpos[1], UIParent, rpos[2], rpos[3], rpos[4])
  else win:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end
  win:SetFrameStrata("MEDIUM"); win:SetToplevel(true)
  win:SetMovable(true); win:SetResizable(true); win:SetResizeBounds(WIN_W,180,WIN_W,720)
  win:EnableMouse(true); win:RegisterForDrag("LeftButton"); win:SetClampedToScreen(true)
  win:SetScript("OnDragStart", win.StartMoving)
  win:SetScript("OnDragStop", function()
    win:StopMovingOrSizing()
    local point,_,relPoint,x,y = win:GetPoint(1)
    if LucidUIDB then LucidUIDB.rollWinPos={point,relPoint,math.floor(x),math.floor(y)} end
  end)
  win:SetBackdrop(BD)
  win:SetBackdropColor(0.022,0.022,0.035,0.97)
  win:SetBackdropBorderColor(ar,ag,ab,0.38)
  C_Timer.After(0,function() if NS.DrawPCBBackground then win._pcbTextures=NS.DrawPCBBackground(win,WIN_W,WIN_H,TITLE_H,0) end end)
  -- Not in UISpecialFrames so ESC doesn't close it

  -- Header bg (dark strip)
  local hBg=win:CreateTexture(nil,"BACKGROUND",nil,2)
  hBg:SetPoint("TOPLEFT",1,-1); hBg:SetPoint("TOPRIGHT",-1,-1)
  hBg:SetHeight(HEADER_H_WIN); hBg:SetColorTexture(0.008,0.008,0.018,1)

  -- Header separator line (NO left accent bar per design)
  local hLine=win:CreateTexture(nil,"OVERLAY",nil,5); hLine:SetHeight(1)
  hLine:SetPoint("TOPLEFT",1,-HEADER_H_WIN); hLine:SetPoint("TOPRIGHT",-1,-HEADER_H_WIN)
  hLine:SetColorTexture(ar,ag,ab,0.55); win._accentLine=hLine

  -- Corner cuts (use TOPRIGHT anchor so they follow resize)
  local function CutTex(xOff,y,w,h,a)
    local t2=win:CreateTexture(nil,"OVERLAY",nil,5); t2:SetSize(w,h)
    t2:SetPoint("TOPRIGHT",win,"TOPRIGHT",xOff,-y); t2:SetColorTexture(ar,ag,ab,a or 0.55)
  end
  CutTex(-2,1,22,1,0.70); CutTex(0,1,1,12,0.70); CutTex(-8,3,12,1,0.35)

  -- Title bar (draggable, transparent — visuals come from hBg)
  local titleBar=CreateFrame("Frame",nil,win)
  titleBar:SetHeight(HEADER_H_WIN); titleBar:SetPoint("TOPLEFT",1,-1); titleBar:SetPoint("TOPRIGHT",-1,-1)
  titleBar:EnableMouse(true); titleBar:RegisterForDrag("LeftButton")
  titleBar:SetScript("OnDragStart",function() win:StartMoving() end)
  titleBar:SetScript("OnDragStop",function()
    win:StopMovingOrSizing()
    local point,_,relPoint,x,y=win:GetPoint(1)
    if LucidUIDB then LucidUIDB.rollWinPos={point,relPoint,math.floor(x),math.floor(y)} end
  end)
  win._titleBar=titleBar

  -- Title text
  local hex=string.format("%02x%02x%02x",math.floor(ar*255),math.floor(ag*255),math.floor(ab*255))
  local titleTxt=titleBar:CreateFontString(nil,"OVERLAY")
  titleTxt:SetFont(NS.FONT,13,"OUTLINE"); titleTxt:SetPoint("LEFT",8,-1)
  titleTxt:SetTextColor(1,1,1,1)
  local lrFirst, lrRest = L["LOOT ROLLS"]:match("^(%S+)%s*(.*)")
  titleTxt:SetText("|cff"..hex..(lrFirst or L["LOOT ROLLS"]).."|r"..(lrRest and lrRest ~= "" and (" |cffffffff"..lrRest.."|r") or ""))
  win._titleTxt=titleTxt

  -- Close button (cyberpunk style)
  local closeBtn=CreateFrame("Button",nil,titleBar,"BackdropTemplate")
  closeBtn:SetSize(22,22); closeBtn:SetPoint("TOPRIGHT",-4,-6)
  closeBtn:SetFrameLevel(titleBar:GetFrameLevel()+5)
  closeBtn:SetBackdrop(BD); closeBtn:SetBackdropColor(0.09,0.02,0.02,1)
  closeBtn:SetBackdropBorderColor(0.34,0.09,0.09,1)
  local cX=closeBtn:CreateFontString(nil,"OVERLAY"); cX:SetFont(NS.FONT,11,""); cX:SetPoint("CENTER")
  cX:SetTextColor(0.60,0.18,0.18); cX:SetText("X")
  closeBtn:SetScript("OnEnter",function() closeBtn:SetBackdropBorderColor(0.82,0.16,0.16,1); cX:SetTextColor(1,0.30,0.30) end)
  closeBtn:SetScript("OnLeave",function() closeBtn:SetBackdropBorderColor(0.34,0.09,0.09,1); cX:SetTextColor(0.60,0.18,0.18) end)
  closeBtn:SetScript("OnClick",function() win:Hide() end)

  -- Boss filter dropdown in title bar
  local filterBtn = CreateFrame("Button", nil, titleBar, "BackdropTemplate")
  filterBtn:SetSize(110, 20)
  filterBtn:SetPoint("RIGHT", closeBtn, "LEFT", -5, 0)
  filterBtn:SetFrameLevel(titleBar:GetFrameLevel() + 5)
  filterBtn:SetBackdrop(BD)
  filterBtn:SetBackdropColor(0.04,0.04,0.07,1)
  filterBtn:SetBackdropBorderColor(0.12,0.12,0.20,1)
  local filterLbl = filterBtn:CreateFontString(nil, "OVERLAY")
  filterLbl:SetFont(NS.FONT, 9, "")
  filterLbl:SetPoint("LEFT", 4, 0)
  filterLbl:SetPoint("RIGHT", -14, 0)
  filterLbl:SetJustifyH("LEFT")
  filterLbl:SetTextColor(0.85, 0.85, 0.85, 1)
  filterLbl:SetText(L["All Bosses"])
  local filterArrow = filterBtn:CreateFontString(nil, "OVERLAY")
  filterArrow:SetFont(NS.FONT, 8, "")
  filterArrow:SetPoint("RIGHT", -3, 0)
  filterArrow:SetTextColor(ar, ag, ab, 1)
  filterArrow:SetText("v")
  win._filterArrow = filterArrow
  filterBtn:SetScript("OnEnter", function()
    local _ar,_ag,_ab=NS.CYAN[1],NS.CYAN[2],NS.CYAN[3]
    filterBtn:SetBackdropBorderColor(_ar,_ag,_ab,0.9)
  end)
  filterBtn:SetScript("OnLeave", function() filterBtn:SetBackdropBorderColor(0.12,0.12,0.20,1) end)
  filterBtn:SetScript("OnClick", function()
    MenuUtil.CreateContextMenu(filterBtn, function(_, rootDescription)
      rootDescription:CreateButton(NS.rollBossFilter and L["All Bosses"] or "|cff00ff00> "..L["All Bosses"].."|r", function()
        NS.rollBossFilter = nil; filterLbl:SetText(L["All Bosses"]); NS.RollWindowRedraw()
      end)
      local encounters, seen = {}, {}
      for _, s in pairs(NS.rollSessions) do
        local enc = s.encounterName or ""
        if enc ~= "" and not seen[enc] then seen[enc] = true; table.insert(encounters, enc) end
      end
      table.sort(encounters)
      for _, enc in ipairs(encounters) do
        rootDescription:CreateButton(NS.rollBossFilter == enc and "|cff00ff00> " .. enc .. "|r" or enc, function()
          NS.rollBossFilter = enc; filterLbl:SetText(enc); NS.RollWindowRedraw()
        end)
      end
    end)
  end)
  win._filterBtn = filterBtn
  win._filterLbl = filterLbl

  -- divLine removed — accent line (_accentLine) handles this

  -- Scroll frame
  local scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT",  1, -(TITLE_H+2))
  scroll:SetPoint("BOTTOMRIGHT", -20, BOTTOM_H+2)
  local sc = CreateFrame("Frame", nil, scroll)
  sc:SetWidth(WIN_W - 22)
  sc:SetHeight(1)
  scroll:SetScrollChild(sc)
  win._scrollChild = sc
  win._scroll      = scroll

  -- Resize grip
  BuildResizeGrip(win)

  -- Bottom bar
  -- Bottom separator line
  local botLine=win:CreateTexture(nil,"OVERLAY",nil,4); botLine:SetHeight(1)
  botLine:SetPoint("BOTTOMLEFT",win,"BOTTOMLEFT",1,BOTTOM_H+1)
  botLine:SetPoint("BOTTOMRIGHT",win,"BOTTOMRIGHT",-1,BOTTOM_H+1)
  botLine:SetColorTexture(ar,ag,ab,0.30)

  local bottomBar = CreateFrame("Frame", nil, win, "BackdropTemplate")
  bottomBar:SetHeight(BOTTOM_H)
  bottomBar:SetPoint("BOTTOMLEFT",  1, 1)
  bottomBar:SetPoint("BOTTOMRIGHT", -1, 1)
  bottomBar:SetBackdrop(BD)
  bottomBar:SetBackdropColor(0.010,0.010,0.020,1)
  bottomBar:SetBackdropBorderColor(0,0,0,0)
  win._bottomBar = bottomBar

  local function MakeBtn(label, anchor, xOff, onClick)
    local btn = CreateFrame("Button", nil, bottomBar, "BackdropTemplate")
    btn:SetSize(90, 22)
    btn:SetPoint(anchor, bottomBar, anchor, xOff, 0)
    btn:SetBackdrop(BD)
    btn:SetBackdropColor(0.04,0.04,0.07,1)
    btn:SetBackdropBorderColor(0.12,0.12,0.20,1)
    local cut2=btn:CreateTexture(nil,"OVERLAY",nil,4); cut2:SetSize(7,1)
    cut2:SetPoint("TOPRIGHT",btn,"TOPRIGHT",0,-1); cut2:SetColorTexture(ar,ag,ab,0.22)
    local lbl = btn:CreateFontString(nil,"OVERLAY")
    lbl:SetFont(NS.FONT,10,""); lbl:SetPoint("CENTER")
    lbl:SetTextColor(0.72,0.72,0.82,1); lbl:SetText(label)
    btn:SetScript("OnEnter", function() btn:SetBackdropBorderColor(NS.CYAN[1],NS.CYAN[2],NS.CYAN[3],0.9) end)
    btn:SetScript("OnLeave", function() btn:SetBackdropBorderColor(0.22,0.22,0.22,1) end)
    btn:SetScript("OnClick", onClick)
    return btn
  end

  MakeBtn("Clear",     "LEFT",  6,  function()
    wipe(NS.rollSessions); NS.rollBossFilter = nil
    if win._filterLbl then win._filterLbl:SetText(L["All Bosses"]) end
    SaveRollSessions()
    NS.RollWindowRedraw()
  end)
  MakeBtn("Test Roll", "RIGHT", -6, function() NS.RollWindowAddTest() end)

  NS.rollWin = win
  win:Hide() -- Don't show on build, only when active rolls exist
end

-- ============================================================
-- Redraw
-- ============================================================
function NS.RollWindowRedraw()
  if not NS.rollWin then return end
  local sc = NS.rollWin._scrollChild

  for _, c in pairs({sc:GetChildren()}) do c:Hide(); c:SetParent(nil) end
  for _, r in pairs({sc:GetRegions()}) do r:Hide() end
  StopDotsTicker()

  local ordered = {}
  for _, s in pairs(NS.rollSessions) do table.insert(ordered, s) end
  table.sort(ordered, function(a,b) return (a.time or 0) > (b.time or 0) end)

  -- Quality filter for roll window (optional, same setting as main window)
  local minQ = (NS.DB and NS.DB("rollMinQuality")) or 0

  -- Group sessions by encounter name (preserving time order), respecting boss filter
  local groups = {}
  local groupIndex = {}
  for _, session in ipairs(ordered) do
    if (session.quality or 0) >= minQ then
      local enc = session.encounterName or ""
      -- Apply boss filter
      if not NS.rollBossFilter or enc == NS.rollBossFilter then
        if not groupIndex[enc] then
          table.insert(groups, {name=enc, sessions={}})
          groupIndex[enc] = #groups
        end
        table.insert(groups[groupIndex[enc]].sessions, session)
      end
    end
  end

  local y, count, anyActive = -PAD, 0, false
  for _, group in ipairs(groups) do
    if group.name ~= "" then
      y = y - BuildEncounterHeader(sc, group.name, y)
    end
    for _, session in ipairs(group.sessions) do
      local h = BuildItemRow(sc, session, y)
      y = y - h
      count = count + 1
      if not session.done then anyActive = true end
    end
  end

  sc:SetWidth(NS.rollWin:GetWidth() - 22)
  sc:SetHeight(math.max(math.abs(y)+PAD, 40))

  if count == 0 then
    if not NS.rollWin._emptyLbl then
      local lbl = sc:CreateFontString(nil,"OVERLAY")
      lbl:SetFont(NS.FONT,11,"")
      lbl:SetPoint("TOP", sc, "TOP", 0, -40)
      lbl:SetTextColor(0.32,0.32,0.32,1)
      lbl:SetText(L["No active rolls"])
      NS.rollWin._emptyLbl = lbl
    end
    NS.rollWin._emptyLbl:Show()
  else
    if NS.rollWin._emptyLbl then NS.rollWin._emptyLbl:Hide() end
    if anyActive then StartDotsTicker() end
  end

  NS.ApplyRollWinTheme()
  -- Only show window if there are active (non-done) rolls
  local hasActive = false
  for _, s in pairs(NS.rollSessions) do
    if not s.done then hasActive = true; break end
  end
  if hasActive then
    NS.rollWin:Show()
  end
end

-- ============================================================
-- Test data
-- ============================================================
local _testID = 0
local fakeClasses   = {"WARRIOR","PALADIN","HUNTER","ROGUE","MAGE","WARLOCK",
                       "DRUID","SHAMAN","MONK","DEATHKNIGHT","DEMONHUNTER","PRIEST"}
local fakeRealms    = {"Thrall","Blackhand","Antonidas","Kazzak","Ragnaros"}
local fakeNames     = {"Aryil","Ccaptain","Chaosbrand","Hebi","Chnkywarrior",
                       "Sotiwarrior","Poisoned","Brainsickk","Zareth","Velindra"}
local fakeBosses    = {"Vexie and the Geargrinders","Cauldron of Carnage","Rik Reverb",
                       "Stix Bunkjunker","Sprocketmonger Lockenstock","The One-Armed Bandit"}

function NS.RollWindowAddTest()
  _testID = _testID + 1
  local testItems = {
    {name="Stoneclas Stompers",     icon="Interface/Icons/INV_Boots_Leather_07",    quality=3,
     link="|cffffff00|Hitem:12345|h[Stoneclas Stompers]|h|r"},
    {name="Leggings of Lethal Re.", icon="Interface/Icons/INV_Pants_Mail_15",       quality=4,
     link="|cffA335EE|Hitem:23456|h[Leggings of Lethal Re.]|h|r"},
    {name="Hateful Chain",           icon="Interface/Icons/INV_Jewelry_Necklace_30", quality=3,
     link="|cffffff00|Hitem:34567|h[Hateful Chain]|h|r"},
    {name="Zenith Anima Spherule",   icon="Interface/Icons/Inv_misc_orb_05",         quality=4,
     link="|cffA335EE|Hitem:45678|h[Zenith Anima Spherule]|h|r"},
  }
  local item = testItems[(_testID-1) % #testItems + 1]

  -- Weighted: more Need than Greed, fewer Pass, occasional Disenchant/Transmog
  local rollTypePool = {"need","need","need","greed","greed","pass","disenchant","transmog"}
  local shuffled = {unpack(fakeNames)}
  for i=#shuffled,2,-1 do
    local j=math.random(i); shuffled[i],shuffled[j]=shuffled[j],shuffled[i]
  end

  local rollers = {}
  local numRollers = math.random(3, 6)
  for i = 1, numRollers do
    local realm  = fakeRealms[math.random(#fakeRealms)]
    local pname  = shuffled[i] .. "-" .. realm
    local cls    = fakeClasses[math.random(#fakeClasses)]
    local rtype  = rollTypePool[math.random(#rollTypePool)]
    -- Pass/disenchant/transmog: val=0 (no CHAT_MSG_SYSTEM roll); need/greed: 1-100
    local val = (rtype == "pass") and 0 or math.random(1,100)
    rollers[pname] = {val=val, rollType=rtype, class=cls}
  end

  -- 2 items per fake boss so grouping is visible in tests
  local fakeEnc = fakeBosses[(math.floor((_testID - 1) / 2) % #fakeBosses) + 1]

  local id = "TEST_" .. _testID
  NS.rollSessions[id] = {
    id=id, name=item.name, icon=item.icon, link=item.link,
    quality=item.quality, time=GetTime(), rollers=rollers, done=false,
    encounterName = fakeEnc,
    rollTime = 6000, rollExpires = GetTime() + 6,
  }

  -- Simulate LOOT_ROLLS_COMPLETE after 6 seconds
  C_Timer.After(6, function()
    if NS.rollSessions[id] then
      NS.DebugLog("ROLL complete id="..tostring(id), 0.6,0.9,0.4)
      NS.rollSessions[id].done = true
      NS.RollWindowRedraw()
      local anyActive = false
      for _, s in pairs(NS.rollSessions) do if not s.done then anyActive=true; break end end
      if not anyActive then ScheduleAutoClose() end
    end
  end)

  BuildRollWindow()
  NS.RollWindowRedraw()
end

-- ============================================================
-- Events
-- ============================================================
local rollFrame = CreateFrame("Frame", "LucidUIRollFrame")
-- PLAYER_LOGIN always needed for initialization
rollFrame:RegisterEvent("PLAYER_LOGIN")

-- Roll-specific events registered conditionally
local function RegisterRollEvents()
  local lootActive = NS.DB("lootOwnWindow") or NS.DB("lootInChatTab")
  if lootActive then
    rollFrame:RegisterEvent("START_LOOT_ROLL")
    rollFrame:RegisterEvent("CANCEL_LOOT_ROLL")
    rollFrame:RegisterEvent("CANCEL_ALL_LOOT_ROLLS")
    rollFrame:RegisterEvent("LOOT_ROLLS_COMPLETE")
    rollFrame:RegisterEvent("ENCOUNTER_START")
    rollFrame:RegisterEvent("CHAT_MSG_LOOT")
    pcall(function() rollFrame:RegisterEvent("LOOT_HISTORY_ROLL_CHANGED") end)
    pcall(function() rollFrame:RegisterEvent("LOOT_HISTORY_UPDATE_DROP") end)
    EnableRollSave()
  else
    rollFrame:UnregisterEvent("START_LOOT_ROLL")
    rollFrame:UnregisterEvent("CANCEL_LOOT_ROLL")
    rollFrame:UnregisterEvent("CANCEL_ALL_LOOT_ROLLS")
    rollFrame:UnregisterEvent("LOOT_ROLLS_COMPLETE")
    rollFrame:UnregisterEvent("ENCOUNTER_START")
    rollFrame:UnregisterEvent("CHAT_MSG_LOOT")
    pcall(function() rollFrame:UnregisterEvent("LOOT_HISTORY_ROLL_CHANGED") end)
    pcall(function() rollFrame:UnregisterEvent("LOOT_HISTORY_UPDATE_DROP") end)
    DisableRollSave()
  end
end
NS.RegisterRollEvents = RegisterRollEvents
rollFrame:SetScript("OnEvent", function(self, event, ...)
  if event == "ENCOUNTER_START" then
    local _, encounterName = ...
    NS.currentEncounterName = encounterName

  elseif event == "PLAYER_LOGIN" then
    BuildRollWindow()
    HookApplyTheme()
    RegisterRollEvents()

  elseif event == "START_LOOT_ROLL" then
    if NS.DB and NS.DB("rollsEnabled") == false then return end
    local rollID, rollTime = ...
    local function ProcessRoll(attempt)
      -- In WoW 12.x GetLootRollItemInfo may return a table or individual values
      -- depending on patch; use C_LootJournal-aware approach with pcall safety
      local texture, name, count, quality, bop
      local ok, r1, r2, r3, r4, r5 = pcall(GetLootRollItemInfo, rollID)
      if ok then
        -- Check if result is a table (newer API) or positional (classic API)
        if type(r1) == "table" then
          texture = r1.texture; name = r1.itemName; count = r1.quantity
          quality = r1.quality; bop = r1.bindOnPickUp
        else
          texture, name, count, quality, bop = r1, r2, r3, r4, r5
        end
      end
      local link = GetLootRollItemLink and GetLootRollItemLink(rollID)
      -- If item info not available yet, retry
      if (not name or name == "") and attempt < 5 then
        C_Timer.After(0.5, function() ProcessRoll(attempt + 1) end)
        return
      end
      local icon = texture
      -- Try to get better info from link
      if link then
        local itemID = link:match("item:(%d+)")
        if itemID then
          local iName, _, iQuality, _, _, _, _, _, _, iIcon = C_Item.GetItemInfo(tonumber(itemID))
          if not name or name == "" then name = iName or link:match("%[(.-)%]") or "Unknown" end
          if not quality or quality == 0 then quality = iQuality or 1 end
          if not icon or icon == "" then icon = iIcon end
        end
      end
      if not name or name == "" then name = "Unknown" end
      -- Quality gate
      local minQ = (NS.DB and NS.DB("rollMinQuality")) or 0
      if (quality or 0) < minQ then return end
      if NS.DebugLog then NS.DebugLog("ROLL START id="..tostring(rollID).." "..tostring(name), 1, 0.8, 0.2) end
      BuildRollWindow()
      NS.rollSessions[rollID] = {
        id=rollID, name=name or "Unknown", icon=icon or texture,
        link=link, quality=quality or 1, time=GetTime(),
        rollTime=rollTime or 0, rollExpires=GetTime() + (rollTime or 0) / 1000,
        rollers={}, done=false,
        encounterName = NS.currentEncounterName,
      }
      NS.RollWindowRedraw()
    end
    ProcessRoll(1)

  elseif event == "CANCEL_LOOT_ROLL" then
    local rollID = ...
    if NS.DebugLog then NS.DebugLog("ROLL CANCEL id="..tostring(rollID)) end
    if NS.rollSessions[rollID] then
      NS.rollSessions[rollID].done = true
      NS.rollSessions[rollID]._doneTime = GetTime()
      NS.RollWindowRedraw()
    end
    local anyActive = false
    for _, s in pairs(NS.rollSessions) do if not s.done then anyActive=true; break end end
    if not anyActive then ScheduleAutoClose() end

  elseif event == "LOOT_ROLLS_COMPLETE" then
    local lootHandle = ...
    if NS.DebugLog then NS.DebugLog("ROLL COMPLETE handle="..tostring(lootHandle)) end
    -- lootHandle may match a rollID; mark it done if found
    if NS.rollSessions[lootHandle] then
      NS.rollSessions[lootHandle].done = true
      NS.rollSessions[lootHandle]._doneTime = GetTime()
      NS.RollWindowRedraw()
    end
    local anyActive = false
    for _, s in pairs(NS.rollSessions) do if not s.done then anyActive=true; break end end
    if not anyActive then ScheduleAutoClose() end

  elseif event == "CANCEL_ALL_LOOT_ROLLS" then
    local now = GetTime()
    for _, s in pairs(NS.rollSessions) do s.done = true; s._doneTime = now end
    NS.RollWindowRedraw()
    ScheduleAutoClose()

  elseif event == "LOOT_HISTORY_ROLL_CHANGED" or event == "LOOT_HISTORY_UPDATE_DROP" then
    pcall(function(...)
      if not C_LootHistory then return end
      local STATE_MAP = {[0]="need", [1]="need", [2]="transmog", [3]="greed", [5]="pass"}

      if event == "LOOT_HISTORY_ROLL_CHANGED" and C_LootHistory.GetItem then
        -- Per-player roll update: match via rollID (unique, handles duplicates)
        local itemIdx, playerIdx = ...
        local rollID = C_LootHistory.GetItem(itemIdx)
        if not rollID then return end
        local s = NS.rollSessions[rollID]
        if not s then return end

        local info = C_LootHistory.GetPlayerInfo(itemIdx, playerIdx)
        if not info or not info.playerName then return end

        local shortName = info.playerName:match("^([^%-]+)") or info.playerName
        local rtype = STATE_MAP[info.state] or "need"
        if info.playerClass then classCache[shortName] = info.playerClass end
        s.rollers[shortName] = {
          val = info.roll or 0, rollType = rtype, class = info.playerClass,
          winner = info.isWinner or nil,
        }
        if info.isWinner then s.done = true; s._doneTime = s._doneTime or GetTime() end
        if s._refreshStatus then s._refreshStatus() end
        NS.RollWindowRedraw()

      elseif event == "LOOT_HISTORY_UPDATE_DROP" and C_LootHistory.GetSortedInfoForDrop then
        -- Fallback: full drop info, match via itemID + lootListID
        local encounterID, lootListID = ...
        local dropInfo = C_LootHistory.GetSortedInfoForDrop(encounterID, lootListID)
        if not dropInfo or not dropInfo.rollInfos then return end
        local dropItemID = dropInfo.itemHyperlink and dropInfo.itemHyperlink:match("item:(%d+)")
        if not dropItemID then return end
        for _, s in pairs(NS.rollSessions) do
          local sID = s.link and s.link:match("item:(%d+)")
          if sID and sID == dropItemID then
            if s._lootListID and s._lootListID ~= lootListID then
              -- Already matched to different drop, skip
            elseif not s._lootListID or s._lootListID == lootListID then
              s._lootListID = lootListID
              for _, ri in ipairs(dropInfo.rollInfos) do
                if ri.playerName and ri.state ~= 4 then
                  local shortName = ri.playerName:match("^([^%-]+)") or ri.playerName
                  local rtype = STATE_MAP[ri.state] or "need"
                  if ri.playerClass then classCache[shortName] = ri.playerClass end
                  s.rollers[shortName] = {
                    val = ri.roll or 0, rollType = rtype, class = ri.playerClass,
                    winner = ri.isWinner or nil,
                  }
                end
              end
              if dropInfo.winner then s.done = true; s._doneTime = s._doneTime or GetTime() end
              if s._refreshStatus then s._refreshStatus() end
              NS.RollWindowRedraw()
              break
            end
          end
        end
      end
    end, ...)

  elseif event == "CHAT_MSG_LOOT" then
    -- Detect roll winners from loot messages
    -- Entire block wrapped in pcall to guard against tainted strings in combat
    pcall(function(...)
      local msg, sender = ...
      if type(msg) ~= "string" then return end
      local itemLink = msg:match("|H[^|]+|h%[.-%]|h")
      if not itemLink or not sender then return end
      sender = tostring(sender)
      for id, s in pairs(NS.rollSessions) do
        if s.link then
          local sessionItemID = s.link:match("item:(%d+)")
          local msgItemID = itemLink:match("item:(%d+)")
          if sessionItemID and msgItemID and sessionItemID == msgItemID then
            local senderShort = sender:match("^([^%-]+)") or sender
            local cls = GetPlayerClass(senderShort) or GetPlayerClass(sender)
            -- Find existing roller entry by short name (CHAT_MSG_SYSTEM uses short names)
            local rollerKey = nil
            for rname in pairs(s.rollers) do
              local rShort = rname:match("^([^%-]+)") or rname
              if rShort == senderShort then rollerKey = rname; break end
            end
            if not rollerKey then
              rollerKey = senderShort
              s.rollers[rollerKey] = {val=0, rollType="need", class=cls}
            end
            s.rollers[rollerKey].class = s.rollers[rollerKey].class or cls
            s.rollers[rollerKey].winner = true
            s.done = true
            s._doneTime = GetTime()
            if NS.DebugLog then NS.DebugLog("ROLL WINNER: "..tostring(sender).." won "..tostring(s.name)) end
            NS.RollWindowRedraw()
            break
          end
        end
      end
    end, ...)
  end
end)

-- /lt rolls: hook lazily on first call so load order doesn't matter
do
  local _hooked = false
  local function EnsureSlashHook()
    if _hooked then return end
    _hooked = true
    local orig = SlashCmdList["LOOTTRACKER"]
    SlashCmdList["LOOTTRACKER"] = function(msg)
      local cmd = strtrim(msg or ""):lower():match("^(%S*)")
      if cmd == "rolls" then
        if NS.rollWin then
          NS.rollWin:SetShown(not NS.rollWin:IsShown())
        end
      else
        if orig then orig(msg) end
      end
    end
  end
  -- Hook as soon as PLAYER_LOGIN fires (all files loaded by then)
  local hookFrame = CreateFrame("Frame")
  hookFrame:RegisterEvent("PLAYER_LOGIN")
  hookFrame:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    EnsureSlashHook()
  end)
end

-- Export for title bar button
NS.BuildRollWindow = function()
  BuildRollWindow()
  if NS.rollWin then
    NS.rollWin:SetShown(not NS.rollWin:IsShown())
  end
end