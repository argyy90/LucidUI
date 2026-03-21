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

-- Auto-save every 15s + on logout
local rollSaveFrame = CreateFrame("Frame")
local rollSaveTimer = 0
rollSaveFrame:SetScript("OnUpdate", function(_, elapsed)
  rollSaveTimer = rollSaveTimer + elapsed
  if rollSaveTimer < 15 then return end
  rollSaveTimer = 0
  SaveRollSessions()
end)
rollSaveFrame:RegisterEvent("PLAYER_LOGOUT")
rollSaveFrame:SetScript("OnEvent", function() SaveRollSessions() end)

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

-- Roll type identifiers (Retail: CHAT_MSG_SYSTEM parsed; kept for completeness)
local rollTypes = {[0]="pass", [1]="need", [2]="greed", [3]="disenchant", [4]="transmog"}

-- Need > Greed/Disenchant/Transmog > Pass (lower = higher priority = wins)
local ROLL_PRIORITY = {need=1, greed=2, disenchant=2, transmog=2, pass=3}


local QUALITY_COLORS = {
  [0]={0.62,0.62,0.62}, [1]={1,1,1},           [2]={0.12,1,0},
  [3]={0,0.44,0.87},    [4]={0.64,0.21,0.93},  [5]={1,0.5,0},
}

local CLASS_COLORS = {
  WARRIOR={0.78,0.61,0.43}, PALADIN={0.96,0.55,0.73},
  HUNTER={0.67,0.83,0.45},  ROGUE={1,0.96,0.41},
  PRIEST={1,1,1},            DEATHKNIGHT={0.77,0.12,0.23},
  SHAMAN={0,0.44,0.87},      MAGE={0.41,0.80,0.94},
  WARLOCK={0.58,0.51,0.79},  MONK={0,1,0.59},
  DRUID={1,0.49,0.04},       DEMONHUNTER={0.64,0.19,0.79},
  EVOKER={0.20,0.58,0.50},
}

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

local function ParseRollLine(msg)
  if type(msg) ~= "string" then return nil, nil end
  local ok, n, v = pcall(function()
    -- English: "PlayerName rolls 42 (1-100)"
    local n, v = msg:match("^(.+) rolls (%d+) %(1%-100%)$")
    -- German: "PlayerName würfelt. Ergebnis: 42 (1-100)"
    if not n then n, v = msg:match("^(.+) w%C+rfelt%. Ergebnis: (%d+) %(1%-100%)$") end
    -- Fallback broad pattern
    if not n then n, v = msg:match("^(.+) w%a+ (%d+) %(1%-100%)$") end
    return n, tonumber(v)
  end)
  if not ok then return nil, nil end
  return n, v
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
  local DT = NS.DARK_THEME
  local alpha = GetRollsAlpha()
  local accent = GetAccentColorRGB()
  if NS.DB and NS.DB("theme") == "custom" then
    local function col(k, def) local v = NS.DB(k); return v and v or def end
    local bg = col("customBg", {0.03,0.03,0.03,alpha})
    bg[4] = alpha
    return {
      bg         = bg,
      border     = col("customBorder",    {0.15,0.15,0.15,1}),
      titleBg    = col("customTitleBg",   {0.06,0.06,0.06,1}),
      titleText  = col("customTitleText", {1,1,1,1}),
      tilders    = accent,
    }
  end
  local bg = {DT.bg[1], DT.bg[2], DT.bg[3], alpha}
  return {
    bg        = bg,
    border    = DT.border,
    titleBg   = DT.titleBg,
    titleText = DT.titleText  or {1,1,1,1},
    tilders   = accent,
  }
end

function NS.ApplyRollWinTheme()
  if not NS.rollWin then return end
  local t = GetWinTheme()
  NS.rollWin:SetBackdropColor(t.bg[1],t.bg[2],t.bg[3], t.bg[4] or 0.97)
  NS.rollWin:SetBackdropBorderColor(t.border[1],t.border[2],t.border[3],1)
  if NS.rollWin._titleBar then
    NS.rollWin._titleBar:SetBackdropColor(t.titleBg[1],t.titleBg[2],t.titleBg[3],1)
  end
  if NS.rollWin._bottomBar then
    local s = 0.75
    NS.rollWin._bottomBar:SetBackdropColor(
      t.titleBg[1]*s, t.titleBg[2]*s, t.titleBg[3]*s, 1)
  end
  -- Title text color + tilde/bracket color from theme
  if NS.rollWin._titleTxt then
    local tid = t.tilders    or {59/255,210/255,237/255,1}
    local tc  = t.titleText  or {1,1,1,1}
    local hex = string.format("%02x%02x%02x",
      math.floor(tid[1]*255), math.floor(tid[2]*255), math.floor(tid[3]*255))
    if NS.DB("showBrackets") ~= false then
      NS.rollWin._titleTxt:SetText("|cff"..hex..">|r "..L["LOOT ROLLS"].." |cff"..hex.."<|r")
    else
      NS.rollWin._titleTxt:SetText(L["LOOT ROLLS"])
    end
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
-- Build one item row (no sub-rows – all detail in tooltip)
-- ============================================================
local function BuildItemRow(parent, session, yOffset)
  local qr, qg, qb = QColor(session.quality or 1)
  local t = GetWinTheme()
  local pw = parent:GetWidth() - 2

  local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  row:SetSize(pw, ROW_H)
  row:SetPoint("TOPLEFT", 1, yOffset)
  row:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8",
                   edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
  row:SetBackdropColor(
    t.bg[1]*0.55 + qr*0.08,
    t.bg[2]*0.55 + qg*0.08,
    t.bg[3]*0.55 + qb*0.08, 1)
  row:SetBackdropBorderColor(qr*0.28, qg*0.28, qb*0.28, 1)

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
  nameLbl:SetFont("Fonts/FRIZQT__.TTF", 10, "")
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
    row:SetScript("OnUpdate", function(self, elapsed)
      local remaining = session.rollExpires - GetTime()
      if remaining <= 0 or session.done then
        timerBar:SetWidth(0)
        timerBg:Hide()
        timerBar:Hide()
        self:SetScript("OnUpdate", nil)
      else
        local pct = remaining / totalDuration
        timerBar:SetWidth(math.max(1, timerBg:GetWidth() * pct))
      end
    end)
  end

  -- Status line (winner or animated dots)
  local statusLbl = row:CreateFontString(nil, "OVERLAY")
  statusLbl:SetFont("Fonts/FRIZQT__.TTF", 11, "")
  statusLbl:SetPoint("BOTTOMLEFT", ICON_SZ + 10, 5)
  statusLbl:SetPoint("BOTTOMRIGHT", -4, 5)
  statusLbl:SetJustifyH("LEFT")

  local function RefreshStatus()
    local sorted = SortedRollers(session.rollers)

    if #sorted == 0 then
      RegisterDotsLabel(statusLbl, "|cff555555Waiting")
    elseif session.done then
      -- Show only the winner in the row; all rollers visible in tooltip
      local winner = nil
      for _, r in ipairs(sorted) do
        if r.rollType ~= "pass" then winner = r; break end
      end
      if winner then
        local cr, cg, cb = CCR(winner.class)
        local rc = ROLL_COLORS[winner.rollType] or ROLL_COLORS.need
        statusLbl:SetText(string.format(
          "|TInterface/AddOns/LucidUI/Assets/Star.png:13:13|t |cff%02x%02x%02x%s|r  |cff%02x%02x%02x%d|r",
          math.floor(cr*255), math.floor(cg*255), math.floor(cb*255), winner.name,
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
      local hdr = session.done and "|cffFFD700Winner:|r" or "|cff3bd2edRolls:|r"
      GameTooltip:AddLine(hdr)

      local foundWinner = false
      for i, r in ipairs(sorted) do
        local cr, cg, cb = CCR(r.class)
        local rc = ROLL_COLORS[r.rollType] or ROLL_COLORS.need
        local isWinner = (not foundWinner) and (r.rollType ~= "pass")
        if isWinner then foundWinner = true end

        local prefix = isWinner and "|TInterface/AddOns/LucidUI/Assets/Star.png:12:12|t " or "    "
        -- Inline icon via |T|t
        local icoPath = ROLL_ICONS[r.rollType] or ROLL_ICONS.need
        local ico = "|T" .. icoPath .. ":12:12|t"

        local valStr = (r.rollType == "pass" or r.val == 0) and "–" or tostring(r.val)
        GameTooltip:AddDoubleLine(
          prefix .. ico .. " " .. r.name,
          valStr,
          cr, cg, cb,
          rc[1], rc[2], rc[3])
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
  hdr:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
  hdr:SetBackdropColor(
    t.titleBg[1] + 0.04, t.titleBg[2] + 0.04, t.titleBg[3] + 0.04, 1)
  hdr:SetBackdropBorderColor(tid[1]*0.35, tid[2]*0.35, tid[3]*0.35, 1)

  -- Accent line left (tilders color)
  local accent = hdr:CreateTexture(nil, "ARTWORK")
  accent:SetWidth(2); accent:SetPoint("TOPLEFT", 0, 0); accent:SetPoint("BOTTOMLEFT", 0, 0)
  accent:SetColorTexture(tid[1], tid[2], tid[3], 0.8)

  local lbl = hdr:CreateFontString(nil, "OVERLAY")
  lbl:SetFont("Fonts/FRIZQT__.TTF", 10, "OUTLINE")
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
    parent:StartSizing("BOTTOMRIGHT")
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

  local win = CreateFrame("Frame", "LucidUIRollWindow", UIParent, "BackdropTemplate")
  win:SetSize(WIN_W, WIN_H)
  -- Restore saved position or default
  local rpos = LucidUIDB and LucidUIDB.rollWinPos
  if rpos then
    win:SetPoint(rpos[1], UIParent, rpos[2], rpos[3], rpos[4])
  else
    win:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
  win:SetFrameStrata("MEDIUM")
  win:SetToplevel(true)
  win:SetMovable(true)
  win:SetResizable(true)
  win:SetResizeBounds(220, 180, 520, 720)
  win:EnableMouse(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving)
  win:SetScript("OnDragStop", function()
    win:StopMovingOrSizing()
    local point, _, relPoint, x, y = win:GetPoint(1)
    if LucidUIDB then
      LucidUIDB.rollWinPos = {point, relPoint, math.floor(x), math.floor(y)}
    end
  end)
  win:SetClampedToScreen(true)
  win:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8",
                   edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
  win:SetBackdropColor(t.bg[1],t.bg[2],t.bg[3], t.bg[4] or 0.97)
  win:SetBackdropBorderColor(t.border[1],t.border[2],t.border[3],1)
  -- Not in UISpecialFrames so ESC doesn't close it

  -- Title bar
  local titleBar = CreateFrame("Frame", nil, win, "BackdropTemplate")
  titleBar:SetHeight(TITLE_H)
  titleBar:SetPoint("TOPLEFT",  1, -1)
  titleBar:SetPoint("TOPRIGHT", -1, -1)
  titleBar:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8"})
  titleBar:SetBackdropColor(t.titleBg[1],t.titleBg[2],t.titleBg[3],1)
  titleBar:EnableMouse(true)
  titleBar:RegisterForDrag("LeftButton")
  titleBar:SetScript("OnDragStart", function() win:StartMoving() end)
  titleBar:SetScript("OnDragStop",  function()
    win:StopMovingOrSizing()
    local point, _, relPoint, x, y = win:GetPoint(1)
    if LucidUIDB then
      LucidUIDB.rollWinPos = {point, relPoint, math.floor(x), math.floor(y)}
    end
  end)
  win._titleBar = titleBar

  local titleTxt = titleBar:CreateFontString(nil, "OVERLAY")
  titleTxt:SetFont("Fonts/FRIZQT__.TTF", 11, "")
  titleTxt:SetPoint("LEFT", 8, 0)
  titleTxt:SetTextColor(1, 1, 1, 1)
  -- Title with both > and < using accent color
  local initAcc = GetAccentColorRGB()
  local initHex = string.format("%02x%02x%02x", math.floor(initAcc[1]*255), math.floor(initAcc[2]*255), math.floor(initAcc[3]*255))
  titleTxt:SetText("|cff"..initHex..">|r "..L["LOOT ROLLS"].." |cff"..initHex.."<|r")
  win._titleTxt = titleTxt

  -- Accent line under title bar
  local rollAccentLine = win:CreateTexture(nil, "ARTWORK")
  rollAccentLine:SetHeight(1)
  rollAccentLine:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, 0)
  rollAccentLine:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
  rollAccentLine:SetColorTexture(NS.CYAN[1], NS.CYAN[2], NS.CYAN[3], 0.6)
  win._accentLine = rollAccentLine

  local closeBtn = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
  closeBtn:SetSize(20, 20)
  closeBtn:SetPoint("RIGHT", -2, 0)
  closeBtn:SetFrameLevel(titleBar:GetFrameLevel() + 5)
  closeBtn:GetNormalTexture():SetVertexColor(0.8, 0.8, 0.8)
  closeBtn:SetScript("OnEnter", function()
    local acc = GetAccentColorRGB()
    closeBtn:GetNormalTexture():SetVertexColor(acc[1], acc[2], acc[3])
  end)
  closeBtn:SetScript("OnLeave", function() closeBtn:GetNormalTexture():SetVertexColor(0.8, 0.8, 0.8) end)
  closeBtn:SetScript("OnClick", function() win:Hide() end)

  -- Boss filter dropdown in title bar
  local filterBtn = CreateFrame("Button", nil, titleBar, "BackdropTemplate")
  filterBtn:SetSize(110, 18)
  filterBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
  filterBtn:SetFrameLevel(titleBar:GetFrameLevel() + 5)
  filterBtn:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
  filterBtn:SetBackdropColor(0.07, 0.07, 0.07, 1)
  filterBtn:SetBackdropBorderColor(0.22, 0.22, 0.22, 1)
  local filterLbl = filterBtn:CreateFontString(nil, "OVERLAY")
  filterLbl:SetFont("Fonts/FRIZQT__.TTF", 9, "")
  filterLbl:SetPoint("LEFT", 4, 0)
  filterLbl:SetPoint("RIGHT", -14, 0)
  filterLbl:SetJustifyH("LEFT")
  filterLbl:SetTextColor(0.85, 0.85, 0.85, 1)
  filterLbl:SetText(L["All Bosses"])
  local filterArrow = filterBtn:CreateFontString(nil, "OVERLAY")
  filterArrow:SetFont("Fonts/FRIZQT__.TTF", 8, "")
  filterArrow:SetPoint("RIGHT", -3, 0)
  filterArrow:SetTextColor(initAcc[1], initAcc[2], initAcc[3], 1)
  filterArrow:SetText("v")
  win._filterArrow = filterArrow
  filterBtn:SetScript("OnEnter", function()
    local acc = GetAccentColorRGB()
    filterBtn:SetBackdropBorderColor(acc[1], acc[2], acc[3], 1)
  end)
  filterBtn:SetScript("OnLeave", function() filterBtn:SetBackdropBorderColor(0.22, 0.22, 0.22, 1) end)
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
  local bottomBar = CreateFrame("Frame", nil, win, "BackdropTemplate")
  bottomBar:SetHeight(BOTTOM_H)
  bottomBar:SetPoint("BOTTOMLEFT",  1, 1)
  bottomBar:SetPoint("BOTTOMRIGHT", -1, 1)
  bottomBar:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8"})
  bottomBar:SetBackdropColor(t.titleBg[1]*0.75, t.titleBg[2]*0.75, t.titleBg[3]*0.75, 1)
  win._bottomBar = bottomBar

  local function MakeBtn(label, anchor, xOff, onClick)
    local btn = CreateFrame("Button", nil, bottomBar, "BackdropTemplate")
    btn:SetSize(90, 22)
    btn:SetPoint(anchor, bottomBar, anchor, xOff, 0)
    btn:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8",
                     edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
    btn:SetBackdropColor(0.07,0.07,0.07,1)
    btn:SetBackdropBorderColor(0.22,0.22,0.22,1)
    local lbl = btn:CreateFontString(nil,"OVERLAY")
    lbl:SetFont("Fonts/FRIZQT__.TTF",10,""); lbl:SetPoint("CENTER")
    lbl:SetTextColor(0.85,0.85,0.85,1); lbl:SetText(label)
    btn:SetScript("OnEnter", function() btn:SetBackdropBorderColor(CYAN[1],CYAN[2],CYAN[3],1) end)
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
      lbl:SetFont("Fonts/FRIZQT__.TTF",11,"")
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
rollFrame:RegisterEvent("START_LOOT_ROLL")
rollFrame:RegisterEvent("CANCEL_LOOT_ROLL")
rollFrame:RegisterEvent("CANCEL_ALL_LOOT_ROLLS")
rollFrame:RegisterEvent("CHAT_MSG_SYSTEM")
rollFrame:RegisterEvent("PLAYER_LOGIN")
rollFrame:RegisterEvent("LOOT_ROLLS_COMPLETE")
rollFrame:RegisterEvent("ENCOUNTER_START")
rollFrame:RegisterEvent("CHAT_MSG_LOOT")

rollFrame:SetScript("OnEvent", function(self, event, ...)
  if event == "ENCOUNTER_START" then
    local _, encounterName = ...
    NS.currentEncounterName = encounterName

  elseif event == "PLAYER_LOGIN" then
    BuildRollWindow()
    HookApplyTheme()

  elseif event == "START_LOOT_ROLL" then
    if NS.DB and NS.DB("rollsEnabled") == false then return end
    local rollID, rollTime = ...
    local function ProcessRoll(attempt)
      local texture, name, count, quality, bop = GetLootRollItemInfo(rollID)
      local link = GetLootRollItemLink(rollID)
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

  elseif event == "CHAT_MSG_SYSTEM" then
    local msg = ...
    -- Guard against tainted strings
    if msg then
      local ok2, safe2 = pcall(tostring, msg)
      if not ok2 then return end
      msg = safe2
    end

    -- Parse roll value: "Player rolls 89 (1-100)"
    local pname, rollVal = ParseRollLine(msg)
    if pname and rollVal then
      if NS.DebugLog then NS.DebugLog("ROLL parsed: "..tostring(pname).."="..tostring(rollVal)) end
      -- Search ALL recent sessions (including recently-done) to handle event ordering
      local bestTime, bestID = 0, nil
      local now = GetTime()
      for id, s in pairs(NS.rollSessions) do
        local recent = (not s.done) or (s._doneTime and (now - s._doneTime) < 10)
        if recent and (s.time or 0) > bestTime then
          bestTime = s.time; bestID = id
        end
      end
      if bestID then
        local existing = NS.rollSessions[bestID].rollers[pname]
        local rtype = existing and existing.rollType or "need"
        local cls   = existing and existing.class or GetPlayerClass(pname)
        if cls then classCache[pname] = cls end
        NS.rollSessions[bestID].rollers[pname] = {val=rollVal, rollType=rtype, class=cls}
        if NS.rollSessions[bestID]._refreshStatus then
          NS.rollSessions[bestID]._refreshStatus()
        end
        NS.RollWindowRedraw()
      end
    end

    -- Parse roll type (locale patterns)
    if type(msg) == "string" then
      local patterns = {
        -- English
        {pat="^(.+) rolls? Need on ",        rtype="need"},
        {pat="^(.+) rolls? Greed on ",       rtype="greed"},
        {pat="^(.+) rolls? Disenchant on ",  rtype="disenchant"},
        {pat="^(.+) rolls? Transmog on ",    rtype="transmog"},
        {pat="^(.+) pass[e]?[sd]? on ",      rtype="pass"},
        -- German
        {pat="^(.+) w\195\188rfelt 'Bedarf' f\195\188r ",  rtype="need"},
        {pat="^(.+) w\195\188rfelt 'Gier' f\195\188r ",    rtype="greed"},
        {pat="^(.+) w\195\188rfelt 'Entzauberung' f\195\188r ", rtype="disenchant"},
        {pat="^(.+) w\195\188rfelt 'Transmog' f\195\188r ", rtype="transmog"},
        {pat="^(.+) passt bei ",             rtype="pass"},
        -- French
        {pat="^(.+) lance un jet de Besoin pour ", rtype="need"},
        {pat="^(.+) lance un jet de Cupidit\195\169 pour ", rtype="greed"},
        {pat="^(.+) passe pour ",            rtype="pass"},
      }
      local changed = false
      for _, p in ipairs(patterns) do
        local ok, n = pcall(function() return msg:match(p.pat) end)
        if ok and n then
          local cls = GetPlayerClass(n)
          if cls then classCache[n] = cls end
          -- Create entries for ALL roll types (not just pass)
          for _, s in pairs(NS.rollSessions) do
            if not s.done or (s._doneTime and (GetTime() - s._doneTime) < 10) then
              if s.rollers[n] then
                s.rollers[n].rollType = p.rtype
                if cls then s.rollers[n].class = cls end
              else
                -- Create new entry for this roller
                local val = (p.rtype == "pass") and 0 or 0
                s.rollers[n] = {val=val, rollType=p.rtype, class=cls}
              end
            end
          end
          changed = true
        end
      end
      if changed then NS.RollWindowRedraw() end
    end

  elseif event == "CHAT_MSG_LOOT" then
    -- Detect roll winners from loot messages
    local msg, sender = ...
    if type(msg) == "string" then
      local itemLink = msg:match("|H[^|]+|h%[.-%]|h")
      if itemLink and sender then
        for id, s in pairs(NS.rollSessions) do
          if s.link then
            local sessionItemID = s.link:match("item:(%d+)")
            local msgItemID = itemLink:match("item:(%d+)")
            if sessionItemID and msgItemID and sessionItemID == msgItemID then
              local senderShort = sender:match("^([^%-]+)") or sender
              local cls = GetPlayerClass(senderShort) or GetPlayerClass(sender)
              -- Don't override real roll value if we already have one
              if not s.rollers[sender] then
                s.rollers[sender] = {val=0, rollType="need", class=cls}
              end
              if s.rollers[sender].val == 0 then
                s.rollers[sender].val = 100
              end
              s.rollers[sender].class = s.rollers[sender].class or cls
              s.rollers[sender].winner = true
              s.done = true
              s._doneTime = GetTime()
              if NS.DebugLog then NS.DebugLog("ROLL WINNER: "..tostring(sender).." won "..tostring(s.name)) end
              NS.RollWindowRedraw()
              break
            end
          end
        end
      end
    end
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