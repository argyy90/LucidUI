-- LucidUI Modules/GoldTracker.lua
-- Tracks completed trades: items + gold exchanged, with whom.
-- History window in cyberpunk card style matching the rest of LucidUI.
--
-- Derived from GLogger/modules/TradeLog.lua
-- GLogger Copyright (C) 2025 Osiris the Kiwi
-- GLogger is licensed under the GNU General Public License v3.
-- Source: https://www.curseforge.com/wow/addons/glogger
--
-- LucidUI Copyright (C) 2026 Argyy
-- Licensed under the GNU General Public License v3.

local NS = LucidUINS
NS.GoldTracker = NS.GoldTracker or {}
local GT = NS.GoldTracker
GT._accentTextures = {}

local function RegAccentGT(tex, alpha, isFS)
  table.insert(GT._accentTextures, {tex=tex, alpha=alpha or 1, isFS=isFS})
  if NS.chatOptAccentTextures then
    table.insert(NS.chatOptAccentTextures, {tex=tex, alpha=alpha or 1, isFS=isFS})
  end
end

local MAX_HISTORY = 300

-- ── Money formatting helpers ──────────────────────────────────────────────
local function MoneyStr(copper)
  if not copper or copper == 0 then return nil end
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  local parts = {}
  if g > 0 then parts[#parts+1] = string.format("|cffffd700%dg|r", g) end
  if s > 0 then parts[#parts+1] = string.format("|cffc7c7cf%ds|r", s) end
  if c > 0 or #parts == 0 then parts[#parts+1] = string.format("|cffeda55f%dc|r", c) end
  return table.concat(parts, " ")
end

local function NetStr(playerGold, targetGold)
  local net = (targetGold or 0) - (playerGold or 0)
  if net == 0 then return nil end
  local abs = math.abs(net)
  local g = math.floor(abs / 10000)
  local s = math.floor((abs % 10000) / 100)
  local c = abs % 100
  local parts = {}
  if g > 0 then parts[#parts+1] = string.format("%dg", g) end
  if s > 0 then parts[#parts+1] = string.format("%ds", s) end
  if c > 0 or #parts == 0 then parts[#parts+1] = string.format("%dc", c) end
  local sign = net > 0 and "+" or "-"
  local r, g2, b = net > 0 and 0.3 or 0.9, net > 0 and 0.9 or 0.3, 0.3
  return sign..table.concat(parts, " "), r, g2, b
end

-- ── Saved history ──────────────────────────────────────────────────────────
local function GetHistory()
  if not LucidUIDB then LucidUIDB = {} end
  if not LucidUIDB.gtHistory then LucidUIDB.gtHistory = {} end
  return LucidUIDB.gtHistory
end

local function SaveTrade(entry)
  local h = GetHistory()
  table.insert(h, 1, entry)
  while #h > MAX_HISTORY do table.remove(h) end
end

-- ── Pending trade state ──────────────────────────────────────────────────────
-- Based on GLogger's proven approach: snapshot on TRADE_ACCEPT_UPDATE (while
-- the trade frame is still fully open), confirm on UI_INFO_MESSAGE ERR_TRADE_COMPLETE.
local pending = nil   -- built on TRADE_ACCEPT_UPDATE
local tradeComplete = false  -- set by UI_INFO_MESSAGE ERR_TRADE_COMPLETE

-- ── Whisper helper (forward-defined so OnTradeComplete can call it) ──────────
function GT.SendTradeSummaryWhisper(e)
  local playerName, playerRealm = UnitFullName("player")
  local playerFull = playerName or UnitName("player") or "Me"
  if playerRealm and playerRealm ~= "" then playerFull = playerFull .. "-" .. playerRealm end

  local partner = e.partner or "Unknown"
  local partnerShort = partner:match("^([^%-]+)") or partner

  local function itemList(items)
    if not items or #items == 0 then return nil end
    local parts = {}
    for _, it in ipairs(items) do
      local s = it.name
      if it.count and it.count > 1 then s = s .. " x" .. it.count end
      parts[#parts+1] = s
    end
    return table.concat(parts, ", ")
  end

  local function goldStr(copper)
    if not copper or copper == 0 then return nil end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local parts = {}
    if g > 0 then parts[#parts+1] = g .. "g" end
    if s > 0 then parts[#parts+1] = s .. "s" end
    if c > 0 or #parts == 0 then parts[#parts+1] = c .. "c" end
    return table.concat(parts, " ")
  end

  local msgs = {}
  local pgold = e.playerGold or 0
  local pitems = itemList(e.playerItems)
  if pgold > 0 or pitems then
    local gave = {}
    if pitems then gave[#gave+1] = pitems end
    if pgold > 0 then gave[#gave+1] = goldStr(pgold) end
    msgs[#msgs+1] = partnerShort .. " received " .. table.concat(gave, " + ") .. " from " .. playerFull
  end

  local tgold = e.targetGold or 0
  local titems = itemList(e.targetItems)
  if tgold > 0 or titems then
    local got = {}
    if titems then got[#got+1] = titems end
    if tgold > 0 then got[#got+1] = goldStr(tgold) end
    msgs[#msgs+1] = playerFull .. " received " .. table.concat(got, " + ") .. " from " .. partner
  end

  if #msgs == 0 then return end
  local whisperTarget = partner
  local prefix = "[GoldTracker] "
  for _, msg in ipairs(msgs) do
    C_ChatInfo.SendChatMessage(prefix .. msg, "WHISPER", nil, whisperTarget)
  end
end

-- ── Trade event handling ───────────────────────────────────────────────────
local evFrame = CreateFrame("Frame")

local function FullName(unit)
  local name, realm = UnitFullName(unit)
  if not name or name == "" then return nil end
  local playerRealm = select(2, UnitFullName("player")) or ""
  if realm and realm ~= "" and realm ~= playerRealm then
    return name .. "-" .. realm:gsub("%s+", "")
  end
  return name
end

local function GetPartnerName()
  -- UnitName("npc") is the trade target in WoW
  local name, realm = UnitName("npc")
  if not name then name, realm = UnitName("target") end
  if not name then return nil end
  local playerRealm = select(2, UnitFullName("player")) or ""
  if realm and realm ~= "" and realm ~= playerRealm then
    return name .. "-" .. realm:gsub("%s+", "")
  end
  -- If no realm returned, check if this is a cross-realm target via UnitFullName
  local fn = FullName("npc") or FullName("target")
  return fn or name
end

local function OnTradeShow()
  pending = nil
  tradeComplete = false
  -- Get partner name while target unit is still set
  local partner = GetPartnerName() or "Unknown"
  pending = {
    time        = time(),
    partner     = partner,
    playerItems = {},
    targetItems = {},
    playerGold  = 0,
    targetGold  = 0,
  }
end

local function SnapshotTrade()
  -- Called on TRADE_ACCEPT_UPDATE — the trade frame is fully populated here.
  -- Use GetTradePlayerItemLink for reliable item reading (same as GLogger).
  if not pending then return end

  -- Re-check partner name in case TRADE_SHOW fired before unit was set
  if pending.partner == "Unknown" or pending.partner == "" then
    local p = GetPartnerName()
    if p then pending.partner = p end
  end

  local playerItems = {}
  for i = 1, 6 do
    local link = GetTradePlayerItemLink(i)
    if link then
      local _, _, count = GetTradePlayerItemInfo(i)
      playerItems[#playerItems+1] = {
        name    = link:match("%[(.-)%]") or "Item",
        link    = link,
        count   = count or 1,
        quality = 1,
      }
    end
  end

  local targetItems = {}
  for i = 1, 6 do
    local link = GetTradeTargetItemLink(i)
    if link then
      local _, _, count = GetTradeTargetItemInfo(i)
      targetItems[#targetItems+1] = {
        name    = link:match("%[(.-)%]") or "Item",
        link    = link,
        count   = count or 1,
        quality = 1,
      }
    end
  end

  pending.playerItems = playerItems
  pending.targetItems = targetItems
  pending.playerGold  = GetPlayerTradeMoney() or 0
  pending.targetGold  = GetTargetTradeMoney() or 0
end

local function OnTradeComplete()
  -- ERR_TRADE_COMPLETE: the trade succeeded. pending has the last ACCEPT_UPDATE snapshot.
  if not pending then return end
  local e = pending
  if #e.playerItems > 0 or #e.targetItems > 0 or e.playerGold > 0 or e.targetGold > 0 then
    if NS.DB("gtEnabled") ~= false then
      SaveTrade(e)
      GT.RefreshWindow()
    end
    if NS.DB("gtWhisper") then
      GT.SendTradeSummaryWhisper(e)
    end
  end
  pending = nil
  tradeComplete = false
end

local function OnTradeCancelled()
  pending = nil
  tradeComplete = false
end

local gtEventsRegistered = false

local function RegisterGTEvents()
  if gtEventsRegistered then return end
  gtEventsRegistered = true
  evFrame:RegisterEvent("TRADE_SHOW")
  evFrame:RegisterEvent("TRADE_ACCEPT_UPDATE")
  evFrame:RegisterEvent("UI_INFO_MESSAGE")
  evFrame:RegisterEvent("UI_ERROR_MESSAGE")
end

local function UnregisterGTEvents()
  if not gtEventsRegistered then return end
  gtEventsRegistered = false
  evFrame:UnregisterEvent("TRADE_SHOW")
  evFrame:UnregisterEvent("TRADE_ACCEPT_UPDATE")
  evFrame:UnregisterEvent("UI_INFO_MESSAGE")
  evFrame:UnregisterEvent("UI_ERROR_MESSAGE")
  pending = nil; tradeComplete = false
end

GT.EnableTracking = function() RegisterGTEvents() end
GT.DisableTracking = function() UnregisterGTEvents() end

evFrame:RegisterEvent("PLAYER_LOGIN")
evFrame:RegisterEvent("PLAYER_LOGOUT")
evFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
  if event == "PLAYER_LOGOUT" then
    -- Save window position on logout
    if GT._histWin then
      local p,_,_,x,y = GT._histWin:GetPoint()
      if p then NS.DBSet("gtWinPos",{p=p,x=x,y=y}) end
    end
    return
  end
  if event == "PLAYER_LOGIN" then
    evFrame:UnregisterEvent("PLAYER_LOGIN")
    if NS.DB("gtEnabled") == false then return end
    RegisterGTEvents()
  elseif event == "TRADE_SHOW" then
    OnTradeShow()
  elseif event == "TRADE_ACCEPT_UPDATE" then
    SnapshotTrade()
  elseif event == "UI_INFO_MESSAGE" then
    if arg2 == ERR_TRADE_COMPLETE then
      OnTradeComplete()
    elseif arg2 == ERR_TRADE_CANCELLED then
      OnTradeCancelled()
    end
  elseif event == "UI_ERROR_MESSAGE" then
    -- Trade failed (bag full etc.) — discard pending
    if arg2 == ERR_TRADE_BAG_FULL or arg2 == ERR_TRADE_MAX_COUNT_EXCEEDED
    or arg2 == ERR_TRADE_TARGET_BAG_FULL or arg2 == ERR_TRADE_TARGET_MAX_COUNT_EXCEEDED then
      OnTradeCancelled()
    end
  end
end)





-- ── History window ─────────────────────────────────────────────────────────
local histWin = nil

local function MakeWinBtn(par, txt, BD)
  local btn = CreateFrame("Button", nil, par, "BackdropTemplate")
  btn:SetBackdrop(BD)
  btn:SetBackdropColor(0.04, 0.04, 0.07, 1)
  btn:SetBackdropBorderColor(0.12, 0.12, 0.20, 1)
  local cut = btn:CreateTexture(nil, "OVERLAY", nil, 4)
  cut:SetSize(8, 1); cut:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, -1)
  do local _ar,_ag,_ab=NS.ChatGetAccentRGB(); cut:SetColorTexture(_ar,_ag,_ab,0.22); RegAccentGT(cut,0.22) end
  local fs = btn:CreateFontString(nil, "OVERLAY")
  fs:SetFont(NS.FONT, 10, ""); fs:SetPoint("CENTER", 0, 0)
  fs:SetTextColor(0.75, 0.75, 0.85); fs:SetText(txt)
  btn._label = fs
  btn:SetScript("OnEnter", function()
    local cr,cg,cb = NS.ChatGetAccentRGB(); btn:SetBackdropBorderColor(cr,cg,cb,0.8)
  end)
  btn:SetScript("OnLeave", function() btn:SetBackdropBorderColor(0.12,0.12,0.20,1) end)
  return btn
end

local graphWinDays = 14  -- current range for main window graph
local graphWinBtns = {}  -- range button refs (created once)

-- Compute NUM_DAYS for a given range code; 0 = All
local function ComputeNumDays(rangeDays)
  if rangeDays > 0 then return rangeDays end
  local history = GetHistory()
  if #history == 0 then return 30 end
  local oldest = time()
  for _, e in ipairs(history) do if e.time and e.time < oldest then oldest = e.time end end
  return math.max(1, math.ceil((time() - oldest) / 86400) + 1)
end

local GRAPH_RANGES = {
  {label="7d",  days=7},
  {label="14d", days=14},
  {label="30d", days=30},
  {label="6m",  days=180},
  {label="1y",  days=365},
  {label="All", days=0},
}

local function BuildHistoryWindow()
  if histWin then return end
  wipe(GT._accentTextures)

  local BD = NS.BACKDROP
  local ar, ag, ab = NS.ChatGetAccentRGB()
  local HEADER_H = 38
  local WIN_W, WIN_H = 520, 560

  histWin = CreateFrame("Frame", "LucidUIGoldTrackerWin", UIParent, "BackdropTemplate")
  GT._histWin = histWin
  histWin:SetSize(WIN_W, WIN_H)
  histWin:SetPoint("CENTER", UIParent, "CENTER", 80, 0)
  histWin:SetFrameStrata("MEDIUM"); histWin:SetToplevel(true)
  histWin:SetScript("OnMouseDown", function(self) self:Raise() end)
  histWin:SetMovable(true); histWin:SetClampedToScreen(true); histWin:EnableMouse(true)
  histWin:RegisterForDrag("LeftButton")
  histWin:SetScript("OnDragStart", function(s) s:StartMoving() end)
  histWin:SetScript("OnDragStop",  function(s)
    s:StopMovingOrSizing()
    local p,_,_,x,y = s:GetPoint(); NS.DBSet("gtWinPos",{p=p,x=x,y=y})
  end)
  histWin:SetBackdrop(BD)
  histWin:SetBackdropColor(0.025, 0.025, 0.038, 0.97)
  histWin:SetBackdropBorderColor(ar, ag, ab, 0.38)
  C_Timer.After(0,function() if NS.DrawPCBBackground then histWin._pcbTextures=NS.DrawPCBBackground(histWin,WIN_W,WIN_H,HEADER_H,0) end end)
  histWin:Hide()

  -- Restore saved position
  local pos = NS.DB("gtWinPos")
  if pos and pos.p then
    histWin:ClearAllPoints(); histWin:SetPoint(pos.p, UIParent, pos.p, pos.x, pos.y)
  end

  -- Accent left bar
  local lBar = histWin:CreateTexture(nil, "OVERLAY", nil, 5); lBar:SetWidth(3)
  lBar:SetPoint("TOPLEFT", 1, -1); lBar:SetPoint("BOTTOMLEFT", 1, 1)
  lBar:SetColorTexture(ar, ag, ab, 1)
  RegAccentGT(lBar, 1)

  -- Header bg
  local hBg = histWin:CreateTexture(nil, "BACKGROUND", nil, 2)
  hBg:SetPoint("TOPLEFT", 1, -1); hBg:SetPoint("TOPRIGHT", -1, -1)
  hBg:SetHeight(HEADER_H); hBg:SetColorTexture(0.010, 0.010, 0.020, 1)

  -- Header separator
  local hLine = histWin:CreateTexture(nil, "OVERLAY", nil, 5); hLine:SetHeight(1)
  hLine:SetPoint("TOPLEFT", 1, -HEADER_H); hLine:SetPoint("TOPRIGHT", -1, -HEADER_H)
  hLine:SetColorTexture(ar, ag, ab, 0.55)
  RegAccentGT(hLine, 0.55)

  -- Corner cut (top-right, matching main dialog)
  local function AccTex(x, y, w, h, a)
    local t = histWin:CreateTexture(nil, "OVERLAY", nil, 5); t:SetSize(w, h)
    t:SetPoint("TOPLEFT", histWin, "TOPLEFT", x, -y)
    t:SetColorTexture(ar, ag, ab, a or 0.55)
    RegAccentGT(t, a or 0.55)
  end
  AccTex(WIN_W-26, 1, 24, 1, 0.70); AccTex(WIN_W-2, 1, 1, 14, 0.70)

  -- Title
  local hex = string.format("%02x%02x%02x", ar*255, ag*255, ab*255)
  local titleFS = histWin:CreateFontString(nil, "OVERLAY")
  titleFS:SetFont(NS.FONT, 13, "OUTLINE")
  titleFS:SetPoint("TOPLEFT", histWin, "TOPLEFT", 14, -8)
  titleFS:SetText("|cff"..hex.."GOLD|r |cffffffffTRACKER|r")
  histWin._titleFS = titleFS

  -- Close button
  local closeBtn = CreateFrame("Button", nil, histWin, "BackdropTemplate")
  closeBtn:SetSize(22, 22); closeBtn:SetPoint("TOPRIGHT", -4, -8)
  closeBtn:SetBackdrop(BD); closeBtn:SetBackdropColor(0.09, 0.02, 0.02, 1)
  closeBtn:SetBackdropBorderColor(0.34, 0.09, 0.09, 1)
  local cX = closeBtn:CreateFontString(nil, "OVERLAY")
  cX:SetFont(NS.FONT, 11, ""); cX:SetPoint("CENTER"); cX:SetTextColor(0.60, 0.18, 0.18); cX:SetText("X")
  closeBtn:SetScript("OnEnter", function() closeBtn:SetBackdropBorderColor(0.82,0.16,0.16,1); cX:SetTextColor(1,0.30,0.30) end)
  closeBtn:SetScript("OnLeave", function() closeBtn:SetBackdropBorderColor(0.34,0.09,0.09,1); cX:SetTextColor(0.60,0.18,0.18) end)
  closeBtn:SetScript("OnClick", function() histWin:Hide() end)

  -- Clear button
  local clearBtn = MakeWinBtn(histWin, "Clear All", BD)
  clearBtn:SetSize(70, 22); clearBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
  clearBtn:SetScript("OnClick", function()
    StaticPopupDialogs["LUCIDUI_GT_CLEAR"] = {
      text="Clear all trade history?", button1=ACCEPT, button2=CANCEL,
      OnAccept=function() LucidUIDB.gtHistory={}; GT.RefreshWindow() end,
      timeout=0, whileDead=true, hideOnEscape=true, preferredIndex=3,
    }
    StaticPopup_Show("LUCIDUI_GT_CLEAR")
  end)

  -- Export button (copy-to-clipboard CSV)
  local exportBtn = MakeWinBtn(histWin, "Export CSV", BD)
  exportBtn:SetSize(80, 22); exportBtn:SetPoint("RIGHT", clearBtn, "LEFT", -4, 0)
  exportBtn:SetScript("OnClick", function()
    local hist = GetHistory()
    local lines = {"Date,Partner,You Gave Items,You Gave Gold,You Got Items,You Got Gold,Net"}
    for _, e in ipairs(hist) do
      local dateStr = date("%Y-%m-%d %H:%M", e.time)
      local piNames = {}; for _, it in ipairs(e.playerItems) do piNames[#piNames+1]=it.name..(it.count>1 and " x"..it.count or "") end
      local tiNames = {}; for _, it in ipairs(e.targetItems) do tiNames[#tiNames+1]=it.name..(it.count>1 and " x"..it.count or "") end
      local net = (e.targetGold or 0) - (e.playerGold or 0)
      lines[#lines+1] = string.format('"%s","%s","%s",%d,"%s",%d,%d',
        dateStr, e.partner or "",
        table.concat(piNames, "; "), e.playerGold or 0,
        table.concat(tiNames, "; "), e.targetGold or 0,
        net)
    end
    local csv = table.concat(lines, "\n")
    -- Show in editbox popup
    local f = CreateFrame("Frame","LUIGTExport",UIParent,"BackdropTemplate")
    f:SetSize(480,280); f:SetPoint("CENTER"); f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetBackdrop(BD); f:SetBackdropColor(0.06,0.06,0.06,0.96); f:SetBackdropBorderColor(ar,ag,ab,0.5)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart",function(s) s:StartMoving() end)
    f:SetScript("OnDragStop",function(s) s:StopMovingOrSizing() end)
    local hdr=f:CreateFontString(nil,"OVERLAY"); hdr:SetFont(NS.FONT,10,"OUTLINE")
    hdr:SetPoint("TOP",0,-6); hdr:SetText("Gold Tracker — CSV Export"); hdr:SetTextColor(ar,ag,ab)
    local cbtn=CreateFrame("Button",nil,f,"UIPanelCloseButton"); cbtn:SetPoint("TOPRIGHT",2,2); cbtn:SetScript("OnClick",function() f:Hide() end)
    local sf2=CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate")
    sf2:SetPoint("TOPLEFT",10,-22); sf2:SetPoint("BOTTOMRIGHT",-28,10)
    local eb=CreateFrame("EditBox",nil,f); eb:SetMultiLine(true); eb:SetAutoFocus(true)
    eb:SetFontObject(GameFontHighlight); eb:SetWidth(440)
    eb:SetScript("OnEscapePressed",function() f:Hide() end)
    sf2:SetScrollChild(eb)
    C_Timer.After(0,function() if f:IsShown() then eb:SetWidth(sf2:GetWidth()); eb:SetText(csv); eb:HighlightText() end end)
    f:Show()
  end)

  -- ── Tab bar (History / Graph) ─────────────────────────────────────────────
  local TAB_H = 26
  local tabBar = CreateFrame("Frame", nil, histWin)
  tabBar:SetPoint("TOPLEFT",  4, -(HEADER_H + 1))
  tabBar:SetPoint("TOPRIGHT", -1, -(HEADER_H + 1))
  tabBar:SetHeight(TAB_H)

  local tabBg = tabBar:CreateTexture(nil, "BACKGROUND")
  tabBg:SetAllPoints(); tabBg:SetColorTexture(0.012, 0.012, 0.022, 1)

  local tabLine = tabBar:CreateTexture(nil, "OVERLAY", nil, 4); tabLine:SetHeight(1)
  tabLine:SetPoint("BOTTOMLEFT"); tabLine:SetPoint("BOTTOMRIGHT")
  tabLine:SetColorTexture(ar, ag, ab, 0.22)
  RegAccentGT(tabLine,0.22)

  local function MakeTab(label, xOff)
    local btn = CreateFrame("Button", nil, tabBar, "BackdropTemplate")
    btn:SetSize(90, TAB_H); btn:SetPoint("LEFT", tabBar, "LEFT", xOff, 0)
    btn:SetBackdrop(BD); btn:SetBackdropColor(0.02, 0.02, 0.04, 1)
    btn:SetBackdropBorderColor(0.10, 0.10, 0.16, 1)
    local lbl = btn:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(NS.FONT, 10, ""); lbl:SetPoint("CENTER")
    lbl:SetTextColor(0.55, 0.55, 0.65); lbl:SetText(label); btn._lbl = lbl
    local selLine = btn:CreateTexture(nil, "OVERLAY", nil, 5); selLine:SetHeight(2)
    selLine:SetPoint("BOTTOMLEFT"); selLine:SetPoint("BOTTOMRIGHT")
    selLine:SetColorTexture(ar, ag, ab, 1); selLine:Hide(); btn._sel = selLine
    RegAccentGT(selLine,1)
    return btn
  end

  local tabHistory = MakeTab("History", 4)
  local tabGraph   = MakeTab("Graph",   96)

  -- ── Range buttons (in tab bar, right-aligned, visible only on Graph tab) ──
  graphWinBtns = {}
  local xR = -4
  for ri = #GRAPH_RANGES, 1, -1 do
    local info = GRAPH_RANGES[ri]
    local btn = CreateFrame("Button", nil, tabBar, "BackdropTemplate")
    local bw = info.label == "All" and 28 or 26
    btn:SetSize(bw, 16); btn:SetPoint("RIGHT", tabBar, "RIGHT", xR, 0)
    xR = xR - bw - 2
    btn:SetBackdrop(NS.BACKDROP)
    btn:SetBackdropColor(0.04,0.04,0.07,1)
    btn:SetBackdropBorderColor(0.12,0.12,0.20,1)
    btn:SetFrameLevel(tabBar:GetFrameLevel() + 3)
    local fs = btn:CreateFontString(nil,"OVERLAY")
    fs:SetFont(NS.FONT,8,""); fs:SetPoint("CENTER")
    fs:SetTextColor(0.55,0.55,0.65); fs:SetText(info.label)
    btn._lbl = fs; btn._days = info.days
    btn:SetScript("OnEnter",function()
      local cr,cg,cb = NS.ChatGetAccentRGB()
      btn:SetBackdropBorderColor(cr,cg,cb,1); fs:SetTextColor(cr,cg,cb)
    end)
    btn:SetScript("OnLeave",function()
      if graphWinDays == btn._days then
        local cr,cg,cb = NS.ChatGetAccentRGB()
        btn:SetBackdropBorderColor(cr,cg,cb,0.7); fs:SetTextColor(cr,cg,cb)
      else
        btn:SetBackdropBorderColor(0.12,0.12,0.20,1); fs:SetTextColor(0.55,0.55,0.65)
      end
    end)
    btn:SetScript("OnClick",function()
      graphWinDays = btn._days; GT.RenderGraph()
    end)
    btn:Hide()
    graphWinBtns[#graphWinBtns+1] = btn
  end

  -- ── Scroll area (History tab) ─────────────────────────────────────────────
  local BODY_TOP = HEADER_H + TAB_H + 2
  local sf = CreateFrame("ScrollFrame", nil, histWin, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT",  8, -BODY_TOP)
  sf:SetPoint("BOTTOMRIGHT", -26, 8)
  if sf.ScrollBar then sf.ScrollBar:SetAlpha(0.35) end

  local content = CreateFrame("Frame", nil, sf)
  content:SetWidth(sf:GetWidth() or 470)
  sf:SetScrollChild(content)
  sf:HookScript("OnSizeChanged", function(_, w) content:SetWidth(w - 2) end)

  histWin._content = content
  histWin._BD      = BD

  -- ── Graph panel ───────────────────────────────────────────────────────────
  local graphPanel = CreateFrame("Frame", nil, histWin)
  graphPanel:SetPoint("TOPLEFT",  8, -BODY_TOP)
  graphPanel:SetPoint("BOTTOMRIGHT", -8, 8)
  graphPanel:Hide()
  histWin._graphPanel = graphPanel

  -- ── Tab switching ─────────────────────────────────────────────────────────
  local function SelectTab(isGraph)
    if isGraph then
      sf:Hide(); graphPanel:Show()
      tabGraph._lbl:SetTextColor(ar, ag, ab)
      tabGraph._sel:Show()
      tabHistory._lbl:SetTextColor(0.55, 0.55, 0.65)
      tabHistory._sel:Hide()
      for _, b in ipairs(graphWinBtns) do b:Show() end
      GT.RenderGraph()
    else
      sf:Show(); graphPanel:Hide()
      tabHistory._lbl:SetTextColor(ar, ag, ab)
      tabHistory._sel:Show()
      tabGraph._lbl:SetTextColor(0.55, 0.55, 0.65)
      tabGraph._sel:Hide()
      for _, b in ipairs(graphWinBtns) do b:Hide() end
    end
  end

  tabHistory:SetScript("OnClick", function() SelectTab(false) end)
  tabGraph:SetScript("OnClick",   function() SelectTab(true)  end)
  SelectTab(false)  -- start on History tab
end

-- ── Render history entries ─────────────────────────────────────────────────
local function RenderSideLines(items, gold)
  local lines = {}
  for _, item in ipairs(items) do
    local countStr = item.count > 1 and ("×"..item.count.."  ") or ""
    lines[#lines+1] = { text = countStr..item.name, quality = item.quality }
  end
  if gold and gold > 0 then
    local m = MoneyStr(gold)
    if m then lines[#lines+1] = { text = m, isGold = true } end
  end
  if #lines == 0 then
    lines[#lines+1] = { text = "—", isEmpty = true }
  end
  return lines
end

-- ── Gold graph renderer ──────────────────────────────────────────────────
-- Draws a dual-bar chart: gave (red) vs received (green) per day.

function GT.RenderGraph()
  local panel = histWin and histWin._graphPanel
  if not panel then return end

  -- Clear old children
  for _, c in ipairs({panel:GetChildren()}) do c:Hide(); c:SetParent(nil) end
  for _, r in ipairs({panel:GetRegions()}) do r:Hide() end

  local ar, ag, ab = NS.ChatGetAccentRGB()
  local history = GetHistory()

  -- Highlight active range button in tab bar
  for _, b in ipairs(graphWinBtns) do
    if b._days == graphWinDays then
      b:SetBackdropBorderColor(ar,ag,ab,0.7); b._lbl:SetTextColor(ar,ag,ab)
    else
      b:SetBackdropBorderColor(0.12,0.12,0.20,1); b._lbl:SetTextColor(0.55,0.55,0.65)
    end
  end

  -- ── Aggregate by day ──────────────────────────────────────────────────────
  local NUM_DAYS = ComputeNumDays(graphWinDays)
  local days = {}
  local now = time()
  for i = 1, NUM_DAYS do
    local dayStart = now - (i - 1) * 86400
    local key = date("%Y-%m-%d", dayStart)
    days[i] = { key = key, label = date("%d/%m", dayStart), gave = 0, received = 0 }
  end

  for _, e in ipairs(history) do
    local key = date("%Y-%m-%d", e.time)
    for _, d in ipairs(days) do
      if d.key == key then
        d.gave     = d.gave     + (e.playerGold or 0)
        d.received = d.received + (e.targetGold or 0)
        break
      end
    end
  end

  -- ── Layout constants ──────────────────────────────────────────────────────
  local W = panel:GetWidth()  or 480
  local H = panel:GetHeight() or 440
  local PAD_L = 12
  local PAD_R = 12
  local PAD_T = 36
  local PAD_B = 32
  local CHART_W = W - PAD_L - PAD_R
  local CHART_H = H - PAD_T - PAD_B
  local slot = math.max(1, math.floor(CHART_W / NUM_DAYS))
  local BAR_W = math.max(2, slot - math.max(1, math.floor(slot * 0.25)))
  local GAP   = slot - BAR_W

  -- ── Find max value for scaling ────────────────────────────────────────────
  local maxVal = 1
  for _, d in ipairs(days) do
    if d.gave     > maxVal then maxVal = d.gave     end
    if d.received > maxVal then maxVal = d.received end
  end

  -- ── Y-axis grid lines ─────────────────────────────────────────────────────
  local NUM_GRID = 4
  for gi = 0, NUM_GRID do
    local yFrac = gi / NUM_GRID
    local gridLine = panel:CreateTexture(nil, "ARTWORK"); gridLine:SetHeight(1)
    local yFromTop = PAD_T + math.floor((1 - yFrac) * CHART_H)
    gridLine:SetPoint("TOPLEFT",  panel, "TOPLEFT",  PAD_L,  -yFromTop)
    gridLine:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD_R, -yFromTop)
    if gi == 0 then
      gridLine:SetColorTexture(ar, ag, ab, 0.35)
    else
      gridLine:SetColorTexture(1, 1, 1, 0.06)
    end
    local val = math.floor(maxVal * yFrac / 10000)
    if val > 0 then
      local yLabel = panel:CreateFontString(nil, "OVERLAY")
      yLabel:SetFont(NS.FONT, 8, "")
      yLabel:SetPoint("RIGHT", panel, "TOPLEFT", PAD_L - 2, -yFromTop)
      yLabel:SetTextColor(0.45, 0.45, 0.55); yLabel:SetText(val.."g")
    end
  end

  -- ── Date label frequency ──────────────────────────────────────────────────
  local labelEvery = NUM_DAYS <= 7 and 1 or NUM_DAYS <= 14 and 2 or NUM_DAYS <= 30 and 4 or NUM_DAYS <= 180 and 14 or 30

  -- ── Bars (oldest = left, most recent = right) ─────────────────────────────
  for i = NUM_DAYS, 1, -1 do
    local d = days[i]
    local col = NUM_DAYS - i
    local xBase = PAD_L + col * slot

    if d.gave > 0 then
      local bh = math.max(2, math.floor((d.gave / maxVal) * CHART_H))
      local bar = panel:CreateTexture(nil, "ARTWORK"); bar:SetSize(math.floor(BAR_W/2) - 1, bh)
      bar:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", xBase, PAD_B)
      bar:SetColorTexture(0.85, 0.25, 0.25, 0.85)
      local cap = panel:CreateTexture(nil, "ARTWORK"); cap:SetSize(math.floor(BAR_W/2) - 1, 2)
      cap:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", xBase, PAD_B + bh - 2)
      cap:SetColorTexture(1, 0.50, 0.50, 1)
    end

    if d.received > 0 then
      local bh = math.max(2, math.floor((d.received / maxVal) * CHART_H))
      local bar = panel:CreateTexture(nil, "ARTWORK"); bar:SetSize(math.ceil(BAR_W/2) - 1, bh)
      bar:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", xBase + math.floor(BAR_W/2), PAD_B)
      bar:SetColorTexture(0.20, 0.80, 0.25, 0.85)
      local cap = panel:CreateTexture(nil, "ARTWORK"); cap:SetSize(math.ceil(BAR_W/2) - 1, 2)
      cap:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", xBase + math.floor(BAR_W/2), PAD_B + bh - 2)
      cap:SetColorTexture(0.50, 1, 0.50, 1)
    end

    if col % labelEvery == 0 then
      local dateLabel = panel:CreateFontString(nil, "OVERLAY")
      dateLabel:SetFont(NS.FONT, 8, "")
      dateLabel:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", xBase, PAD_B - 14)
      dateLabel:SetTextColor(0.40, 0.40, 0.50); dateLabel:SetText(d.label)
      dateLabel:SetJustifyH("LEFT")
    end

    if d.gave > 0 or d.received > 0 then
      local hit = CreateFrame("Frame", nil, panel)
      hit:SetSize(slot, CHART_H)
      hit:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", xBase, PAD_B)
      hit:EnableMouse(true)
      local capturedD = d
      hit:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(capturedD.key, ar, ag, ab)
        if capturedD.gave > 0 then
          GameTooltip:AddLine("Gave:     " .. (MoneyStr(capturedD.gave) or "0c"), 0.9, 0.3, 0.3)
        end
        if capturedD.received > 0 then
          GameTooltip:AddLine("Received: " .. (MoneyStr(capturedD.received) or "0c"), 0.3, 0.9, 0.3)
        end
        local net = capturedD.received - capturedD.gave
        if net ~= 0 then
          local nr, ng, nb = net > 0 and 0.3 or 0.9, net > 0 and 0.9 or 0.3, 0.3
          GameTooltip:AddLine("Net:      " .. (net > 0 and "+" or "") .. (MoneyStr(math.abs(net)) or "0c"), nr, ng, nb)
        end
        GameTooltip:Show()
      end)
      hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
  end

  -- ── Legend ────────────────────────────────────────────────────────────────
  local function LegendDot(x, color, label)
    local dot = panel:CreateTexture(nil, "OVERLAY"); dot:SetSize(10, 10)
    dot:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -8)
    dot:SetColorTexture(unpack(color))
    local lbl = panel:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(NS.FONT, 9, "")
    lbl:SetPoint("LEFT", panel, "TOPLEFT", x + 14, -8)
    lbl:SetTextColor(0.65, 0.65, 0.75); lbl:SetText(label)
  end

  LegendDot(PAD_L,        {0.85, 0.25, 0.25, 1}, "Gave")
  LegendDot(PAD_L + 70,   {0.20, 0.80, 0.25, 1}, "Received")

  -- ── "No data" fallback ────────────────────────────────────────────────────
  local hasAny = false
  for _, d in ipairs(days) do if d.gave > 0 or d.received > 0 then hasAny = true; break end end
  if not hasAny then
    local empty = panel:CreateFontString(nil, "OVERLAY")
    empty:SetFont(NS.FONT, 11, "")
    empty:SetPoint("CENTER", panel, "CENTER", 0, 0)
    empty:SetTextColor(0.35, 0.35, 0.45)
    empty:SetText("No gold trades in this period")
  end
end

function GT.RefreshWindow()
  if not histWin or not histWin:IsShown() then return end

  local content = histWin._content
  local BD = histWin._BD
  local ar, ag, ab = NS.ChatGetAccentRGB()

  -- Destroy all children (Frames) AND regions (FontStrings/Textures) on content
  local children = {content:GetChildren()}
  for _, c in ipairs(children) do c:Hide(); c:SetParent(nil) end
  local regions = {content:GetRegions()}
  for _, r in ipairs(regions) do r:Hide() end

  local history = GetHistory()
  local yOff = 4

  if #history == 0 then
    -- Wrap in a Frame so it gets cleaned up by GetChildren() next time
    local emptyHolder = CreateFrame("Frame", nil, content)
    emptyHolder:SetHeight(60)
    emptyHolder:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -10)
    emptyHolder:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -10)
    content:SetHeight(80)
    local fs = emptyHolder:CreateFontString(nil, "OVERLAY")
    fs:SetFont(NS.FONT, 11, "")
    fs:SetPoint("CENTER", emptyHolder, "CENTER", 0, 0)
    fs:SetTextColor(0.40, 0.40, 0.50)
    fs:SetText("No trades recorded yet.")
    return
  end

  -- Summary banner (total net gold)
  do
    local banner = CreateFrame("Frame", nil, content, "BackdropTemplate")
    banner:SetBackdrop(BD); banner:SetBackdropColor(0.02, 0.04, 0.02, 1)
    banner:SetBackdropBorderColor(ar, ag, ab, 0.15); banner:SetHeight(22)
    banner:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -yOff)
    banner:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -yOff)
    local totalGot, totalGave = 0, 0
    for _, e in ipairs(history) do
      totalGot  = totalGot  + (e.targetGold or 0)
      totalGave = totalGave + (e.playerGold or 0)
    end
    local net = totalGot - totalGave
    local nr, ng, nb = net >= 0 and 0.2 or 0.9, net >= 0 and 0.9 or 0.2, 0.2
    local banFS = banner:CreateFontString(nil, "OVERLAY")
    banFS:SetFont(NS.FONT, 10, "OUTLINE")
    banFS:SetPoint("CENTER"); banFS:SetTextColor(nr, ng, nb)
    local netStr = MoneyStr(math.abs(net)) or "0c"
    banFS:SetText(string.format("%d trades  •  Net: %s%s",
      #history, net >= 0 and "+" or "-", netStr))
    yOff = yOff + 22 + 6
  end

  local LINE_H = 16

  for _, entry in ipairs(history) do
    -- Build content first so we know the height
    local leftLines  = RenderSideLines(entry.playerItems, entry.playerGold)
    local rightLines = RenderSideLines(entry.targetItems, entry.targetGold)
    local maxLines   = math.max(#leftLines, #rightLines)

    -- Card height: 8 top + 18 header + 6 sep + 14 col-labels + maxLines*LINE_H + 8 bottom
    local CARD_PAD_TOP  = 8
    local HEADER_ROW    = 18
    local SEP           = 6
    local COL_LABEL_H   = 14
    local CARD_PAD_BOT  = 8
    local netRow = (entry.playerGold ~= entry.targetGold) and LINE_H or 0
    local cardH = CARD_PAD_TOP + HEADER_ROW + SEP + COL_LABEL_H + maxLines*LINE_H + netRow + CARD_PAD_BOT

    local card = CreateFrame("Frame", nil, content, "BackdropTemplate")
    card:SetHeight(cardH)
    card:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -yOff)
    card:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -yOff)
    card:SetBackdrop(BD)
    card:SetBackdropColor(0.034, 0.034, 0.056, 1)
    card:SetBackdropBorderColor(0.08, 0.08, 0.13, 1)

    -- Left accent bar
    local cBar = card:CreateTexture(nil, "OVERLAY", nil, 5); cBar:SetWidth(3)
    cBar:SetPoint("TOPLEFT", 0, -3); cBar:SetPoint("BOTTOMLEFT", 0, 3)
    cBar:SetColorTexture(ar, ag, ab, 1)

    -- Tiny staircase on top-right (card corner decoration)
    for i = 0, 2 do
      local st = card:CreateTexture(nil, "OVERLAY", nil, 4); st:SetSize(6-i*2, 1)
      st:SetPoint("TOPRIGHT", card, "TOPRIGHT", -(6+i*6), -(2+i*2))
      st:SetColorTexture(ar, ag, ab, 0.25 - i*0.07)
    end

    local cy = CARD_PAD_TOP

    -- Header: date + partner
    local timeStr = date("%d.%m.%y  %H:%M", entry.time)
    local hdrDate = card:CreateFontString(nil, "OVERLAY")
    hdrDate:SetFont(NS.FONT, 9, "OUTLINE")
    hdrDate:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -cy)
    hdrDate:SetTextColor(ar, ag, ab, 0.9); hdrDate:SetText("> "..timeStr)

    local hdrPart = card:CreateFontString(nil, "OVERLAY")
    hdrPart:SetFont(NS.FONT, 10, "")
    hdrPart:SetPoint("TOPLEFT", hdrDate, "TOPRIGHT", 8, 0)
    hdrPart:SetPoint("TOPRIGHT", card, "TOPRIGHT", -14, -cy)
    hdrPart:SetJustifyH("LEFT")
    hdrPart:SetTextColor(0.80, 0.80, 0.90); hdrPart:SetText(entry.partner or "Unknown")
    cy = cy + HEADER_ROW

    -- Separator
    local sep = card:CreateTexture(nil, "OVERLAY", nil, 3); sep:SetHeight(1)
    sep:SetColorTexture(ar, ag, ab, 0.18)
    sep:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -cy)
    sep:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -cy)
    sep:SetColorTexture(ar, ag, ab, 0.18)
    cy = cy + SEP

    -- Vertical divider between columns
    local vdiv = card:CreateTexture(nil, "OVERLAY", nil, 3); vdiv:SetWidth(1)
    vdiv:SetPoint("TOP", card, "TOP", 0, -(cy - SEP/2))
    vdiv:SetHeight(COL_LABEL_H + maxLines*LINE_H + 4)
    vdiv:SetColorTexture(ar, ag, ab, 0.12)

    -- Column labels
    local lblGave = card:CreateFontString(nil, "OVERLAY")
    lblGave:SetFont(NS.FONT, 9, "OUTLINE")
    lblGave:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -cy)
    lblGave:SetTextColor(0.90, 0.32, 0.32, 1); lblGave:SetText("YOU GAVE")

    local lblGot = card:CreateFontString(nil, "OVERLAY")
    lblGot:SetFont(NS.FONT, 9, "OUTLINE")
    lblGot:SetPoint("TOP", card, "TOP", 115, -cy)
    lblGot:SetJustifyH("LEFT")
    card:HookScript("OnShow", function(self) lblGot:SetWidth(math.floor(self:GetWidth()/2) - 18) end)
    lblGot:SetWidth(math.floor((card:GetWidth()>0 and card:GetWidth() or 460)/2) - 18)
    lblGot:SetTextColor(0.32, 0.90, 0.32, 1); lblGot:SetText("YOU RECEIVED")
    cy = cy + COL_LABEL_H

    -- Item rows
    for li = 1, maxLines do
      local ll = leftLines[li]
      local rl = rightLines[li]
      if ll then
        local fs = card:CreateFontString(nil, "OVERLAY")
        fs:SetFont(NS.FONT, 10, "")
        fs:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -cy)
        fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
        -- Width set via OnShow so we always get the live card width
        card:HookScript("OnShow", function(self) fs:SetWidth(math.floor(self:GetWidth()/2) - 14) end)
        fs:SetWidth(math.floor((card:GetWidth()>0 and card:GetWidth() or 460)/2) - 14)
        if ll.isGold then
          fs:SetText(ll.text)
        elseif ll.isEmpty then
          fs:SetTextColor(0.35, 0.35, 0.45); fs:SetText(ll.text)
        else
          local qr, qg, qb = QColor(ll.quality)
          fs:SetTextColor(qr, qg, qb); fs:SetText(ll.text)
        end
      end
      if rl then
        local fs = card:CreateFontString(nil, "OVERLAY")
        fs:SetFont(NS.FONT, 10, "")
        fs:SetPoint("TOPLEFT", card, "TOP", 8, -cy)
        fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
        card:HookScript("OnShow", function(self) fs:SetWidth(math.floor(self:GetWidth()/2) - 18) end)
        fs:SetWidth(math.floor((card:GetWidth()>0 and card:GetWidth() or 460)/2) - 18)
        if rl.isGold then
          fs:SetText(rl.text)
        elseif rl.isEmpty then
          fs:SetTextColor(0.35, 0.35, 0.45); fs:SetText(rl.text)
        else
          local qr, qg, qb = QColor(rl.quality)
          fs:SetTextColor(qr, qg, qb); fs:SetText(rl.text)
        end
      end
      cy = cy + LINE_H
    end

    -- Net gold row (only if gold was involved and different amounts)
    local pgold = entry.playerGold or 0
    local tgold = entry.targetGold or 0
    if pgold ~= tgold then
      local netTxt, nr2, ng2, nb2 = NetStr(pgold, tgold)
      if netTxt then
        local netLabel = card:CreateFontString(nil, "OVERLAY")
        netLabel:SetFont(NS.FONT, 9, "OUTLINE")
        netLabel:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -10, CARD_PAD_BOT)
        netLabel:SetTextColor(nr2, ng2, nb2, 1)
        netLabel:SetText("Net: " .. netTxt)
      end
    end

    yOff = yOff + cardH + 5
  end

  content:SetHeight(yOff + 8)
end

function GT._ApplyTheme()
  local ar,ag,ab = NS.ChatGetAccentRGB()
  if histWin then histWin:SetBackdropBorderColor(ar,ag,ab,0.38) end
  for _,e in ipairs(GT._accentTextures) do
    pcall(function()
      if e.isFS then e.tex:SetTextColor(ar,ag,ab,1)
      else e.tex:SetColorTexture(ar,ag,ab,e.alpha or 1) end
    end)
  end
  if NS.UpdatePCBTextures and histWin then NS.UpdatePCBTextures(histWin._pcbTextures) end
  -- Update title
  if histWin and histWin._titleFS then
    local hex = string.format("%02x%02x%02x", math.floor(ar*255), math.floor(ag*255), math.floor(ab*255))
    histWin._titleFS:SetText("|cff"..hex.."GOLD|r |cffffffffTRACKER|r")
  end
  -- Redraw trade cards with fresh accent color if window is open
  if histWin and histWin:IsShown() then GT.RefreshWindow() end
end

function GT.ShowWindow()
  BuildHistoryWindow()
  if histWin:IsShown() then
    histWin:Hide()
  else
    -- Restore accent colours in case they changed
    local ar, ag, ab = NS.ChatGetAccentRGB()
    histWin:SetBackdropBorderColor(ar, ag, ab, 0.38)
    histWin:Show()
    GT.RefreshWindow()
  end
end

-- ── Settings tab ───────────────────────────────────────────────────────────
function GT.SetupSettings(parent)
  local container = CreateFrame("Frame", nil, parent)
  local MakeCard  = NS._SMakeCard
  local MakePage  = NS._SMakePage
  local Sep       = NS._SSep
  local R         = NS._SR
  local BD        = NS._SBD
  local sc, Add   = MakePage(container)

  local function DB(k)      return NS.DB(k)    end
  local function DBSet(k,v) NS.DBSet(k, v)     end

  -- ── Card: General ────────────────────────────────────────────────────────
  local cGT = MakeCard(sc, "Trade Tracking")

  -- Enable + Whisper paired on one row
  local pairRow = CreateFrame("Frame", nil, cGT.inner); pairRow:SetHeight(26)
  cGT:Row(pairRow, 26)
  pairRow:SetPoint("LEFT",  cGT.inner, "LEFT",  0, 0)
  pairRow:SetPoint("RIGHT", cGT.inner, "RIGHT", 0, 0)

  local lh = CreateFrame("Frame", nil, pairRow)
  lh:SetPoint("TOPLEFT",    pairRow, "TOPLEFT",  0, 0)
  lh:SetPoint("BOTTOMRIGHT",pairRow, "BOTTOM",  -2, 0)

  local rh = CreateFrame("Frame", nil, pairRow)
  rh:SetPoint("TOPLEFT",    pairRow, "TOP",       2, 0)
  rh:SetPoint("BOTTOMRIGHT",pairRow, "BOTTOMRIGHT",0, 0)

  local enableCB = NS.ChatGetCheckbox(lh, "Enable Gold Tracker", 26, function(state)
    DBSet("gtEnabled", state); if state then DBSet("showCoinBtn", true); GT.EnableTracking() else GT.DisableTracking() end
    if NS.LayoutBarButtons then NS.LayoutBarButtons() end
  end, "Record every completed trade with items and gold")
  enableCB.option = "gtEnabled"
  enableCB:SetParent(lh); enableCB:ClearAllPoints(); enableCB:SetAllPoints(lh)

  local whisperCB = NS.ChatGetCheckbox(rh, "Whisper on complete", 26, function(state)
    DBSet("gtWhisper", state)
  end, "Send a whisper to the trade partner summarising what was exchanged")
  whisperCB.option = "gtWhisper"
  whisperCB:SetParent(rh); whisperCB:ClearAllPoints(); whisperCB:SetAllPoints(rh)

  -- Open window button (full-width)
  local openRow = CreateFrame("Frame", nil, cGT.inner); openRow:SetHeight(32)
  local openBtn = CreateFrame("Button", nil, openRow, "BackdropTemplate")
  openBtn:SetSize(0, 26)
  openBtn:SetPoint("TOPLEFT",  openRow, "TOPLEFT",  0, -3)
  openBtn:SetPoint("TOPRIGHT", openRow, "TOPRIGHT", 0, -3)
  openBtn:SetBackdrop(BD); openBtn:SetBackdropColor(0.04, 0.04, 0.07, 1)
  openBtn:SetBackdropBorderColor(0.12, 0.12, 0.20, 1)
  local oCut = openBtn:CreateTexture(nil,"OVERLAY",nil,4); oCut:SetSize(10,1)
  oCut:SetPoint("TOPRIGHT",openBtn,"TOPRIGHT",0,-1)
  do local _ar,_ag,_ab=NS.ChatGetAccentRGB(); oCut:SetColorTexture(_ar,_ag,_ab,0.22); RegAccentGT(oCut,0.22) end
  local oFS = openBtn:CreateFontString(nil,"OVERLAY"); oFS:SetFont(NS.FONT,11,"")
  oFS:SetPoint("CENTER",0,0); oFS:SetTextColor(0.75,0.75,0.85); oFS:SetText("Open Trade History")
  openBtn:SetScript("OnEnter",function() local cr,cg,cb=NS.ChatGetAccentRGB(); openBtn:SetBackdropBorderColor(cr,cg,cb,0.8) end)
  openBtn:SetScript("OnLeave",function() openBtn:SetBackdropBorderColor(0.12,0.12,0.20,1) end)
  openBtn:SetScript("OnClick", function() GT.ShowWindow() end)
  cGT:Row(openRow, 32)

  cGT:Finish(); Add(cGT); Add(Sep(sc), 9)

  -- ── Card: Statistics ─────────────────────────────────────────────────────
  local cStats = MakeCard(sc, "Session Overview")

  local statsLines = {}
  for _, lbl in ipairs({"Trades recorded", "Total gold received", "Total gold given", "Net gold"}) do
    local holder = CreateFrame("Frame", nil, cStats.inner); holder:SetHeight(22)
    cStats:Row(holder, 22)
    holder:SetPoint("LEFT", cStats.inner, "LEFT", 0, 0)
    holder:SetPoint("RIGHT", cStats.inner, "RIGHT", 0, 0)
    local lFS = holder:CreateFontString(nil, "OVERLAY")
    lFS:SetFont(NS.FONT, 10, "")
    lFS:SetPoint("LEFT", holder, "LEFT", 20, 0)
    lFS:SetTextColor(0.50, 0.50, 0.60); lFS:SetText(lbl)
    local vFS = holder:CreateFontString(nil, "OVERLAY")
    vFS:SetFont(NS.FONT, 10, "OUTLINE")
    vFS:SetPoint("RIGHT", holder, "RIGHT", -20, 0)
    vFS:SetJustifyH("RIGHT"); vFS:SetTextColor(0.85, 0.85, 0.92)
    statsLines[#statsLines+1] = vFS
  end

  cStats:Finish(); Add(cStats); Add(Sep(sc), 9)

  -- ── Card: Graph ─────────────────────────────────────────────────────────
  local cGraph = MakeCard(sc, "Gold Flow")

  -- Dynamic days label + tiny range buttons placed in the card title bar
  local graphDays = 14   -- current selected range, shared with RenderInlineGraph

  local daysLabel = cGraph:CreateFontString(nil, "OVERLAY")
  daysLabel:SetFont(NS.FONT, 9, "OUTLINE")
  daysLabel:SetPoint("TOPLEFT", cGraph, "TOPLEFT", 86, -7)
  daysLabel:SetTextColor(0.55, 0.55, 0.65)
  daysLabel:SetText("— LAST 14 DAYS")

  local function MakeRangeBtn(label, days, xRight)
    local btn = CreateFrame("Button", nil, cGraph, "BackdropTemplate")
    btn:SetSize(26, 13)
    btn:SetPoint("TOPRIGHT", cGraph, "TOPRIGHT", xRight, -7)
    local BD2 = NS.BACKDROP
    btn:SetBackdrop(BD2)
    btn:SetBackdropColor(0.04,0.04,0.07,1)
    btn:SetBackdropBorderColor(0.12,0.12,0.20,1)
    local fs = btn:CreateFontString(nil,"OVERLAY")
    fs:SetFont(NS.FONT,7,""); fs:SetPoint("CENTER")
    fs:SetTextColor(0.55,0.55,0.65); fs:SetText(label)
    btn._lbl = fs; btn._days = days
    btn:SetScript("OnEnter",function()
      local cr,cg,cb = NS.ChatGetAccentRGB()
      btn:SetBackdropBorderColor(cr,cg,cb,1); fs:SetTextColor(cr,cg,cb)
    end)
    btn:SetScript("OnLeave",function()
      if graphDays == days then
        local cr,cg,cb = NS.ChatGetAccentRGB()
        btn:SetBackdropBorderColor(cr,cg,cb,0.7); fs:SetTextColor(cr,cg,cb)
      else
        btn:SetBackdropBorderColor(0.12,0.12,0.20,1); fs:SetTextColor(0.55,0.55,0.65)
      end
    end)
    return btn
  end

  local SETTINGS_RANGES = {
    {label="7d",  days=7,   w=20},
    {label="14d", days=14,  w=22},
    {label="30d", days=30,  w=22},
    {label="6m",  days=180, w=20},
    {label="1y",  days=365, w=18},
    {label="All", days=0,   w=22},
  }
  local allRangeBtns = {}
  local xR = -40
  for ri = 1, #SETTINGS_RANGES do
    local info = SETTINGS_RANGES[ri]
    local btn = MakeRangeBtn(info.label, info.days, xR)
    btn:SetSize(info.w, 13)
    btn:ClearAllPoints(); btn:SetPoint("TOPRIGHT", cGraph, "TOPRIGHT", xR, -7)
    allRangeBtns[#allRangeBtns+1] = btn
    xR = xR - info.w - 2
  end

  local function SetActiveBtn(days)
    local cr,cg,cb = NS.ChatGetAccentRGB()
    for _, b in ipairs(allRangeBtns) do
      if b._days == days then
        b:SetBackdropBorderColor(cr,cg,cb,0.7); b._lbl:SetTextColor(cr,cg,cb)
      else
        b:SetBackdropBorderColor(0.12,0.12,0.20,1); b._lbl:SetTextColor(0.55,0.55,0.65)
      end
    end
    local labels = {[7]="— LAST 7 DAYS", [14]="— LAST 14 DAYS", [30]="— LAST 30 DAYS",
      [180]="— LAST 6 MONTHS", [365]="— LAST YEAR", [0]="— ALL TIME"}
    daysLabel:SetText(labels[days] or ("— LAST "..days.." DAYS"))
  end

  local GRAPH_H = 160
  local graphHolder = CreateFrame("Frame", nil, cGraph.inner)
  graphHolder:SetHeight(GRAPH_H)
  cGraph:Row(graphHolder, GRAPH_H)
  cGraph:Finish(); Add(cGraph)

  -- Inline graph renderer for the settings card
  local function RenderInlineGraph()
    -- Clear
    for _, c in ipairs({graphHolder:GetChildren()}) do c:Hide(); c:SetParent(nil) end
    for _, r in ipairs({graphHolder:GetRegions()}) do r:Hide() end

    local ar2, ag2, ab2 = NS.ChatGetAccentRGB()
    local history = GetHistory()

    -- Aggregate last N days (graphDays); 0 = All
    local NUM_DAYS = ComputeNumDays(graphDays)
    local days = {}
    local now = time()
    for i = 1, NUM_DAYS do
      local key = date("%Y-%m-%d", now - (i-1)*86400)
      days[i] = { key=key, label=date("%d/%m", now-(i-1)*86400), gave=0, received=0 }
    end
    for _, e in ipairs(history) do
      local key = date("%Y-%m-%d", e.time)
      for _, d in ipairs(days) do
        if d.key == key then
          d.gave     = d.gave     + (e.playerGold or 0)
          d.received = d.received + (e.targetGold or 0)
          break
        end
      end
    end

    local hasAny = false
    local maxVal = 1
    for _, d in ipairs(days) do
      if d.gave > maxVal     then maxVal = d.gave     end
      if d.received > maxVal then maxVal = d.received end
      if d.gave > 0 or d.received > 0 then hasAny = true end
    end

    if not hasAny then
      local fs = graphHolder:CreateFontString(nil, "OVERLAY")
      fs:SetFont(NS.FONT, 10, "")
      fs:SetPoint("CENTER"); fs:SetTextColor(0.35, 0.35, 0.45)
      fs:SetText("No gold trades in this period")
      return
    end

    -- Layout — use OnShow width; fallback to 340
    local W  = graphHolder:GetWidth()
    if not W or W < 20 then W = 340 end
    local H    = GRAPH_H
    local PL   = 8
    local PR   = 8
    local PT   = 18   -- legend
    local PB   = 18   -- date labels
    local CW   = W - PL - PR
    local CH   = H - PT - PB
    local slot = math.floor(CW / NUM_DAYS)
    local BW   = math.max(4, slot - 3)

    -- Grid lines (3) — anchored from BOTTOMLEFT so they align with bars
    for gi = 1, 3 do
      local yFrac = gi / 3
      local yPx   = PB + math.floor(yFrac * CH)
      local gl = graphHolder:CreateTexture(nil, "ARTWORK")
      gl:SetHeight(1)
      gl:SetPoint("BOTTOMLEFT",  graphHolder, "BOTTOMLEFT",  PL,  yPx)
      gl:SetPoint("BOTTOMRIGHT", graphHolder, "BOTTOMRIGHT", -PR, yPx)
      gl:SetColorTexture(1, 1, 1, 0.05)
    end
    -- Baseline
    local base = graphHolder:CreateTexture(nil, "ARTWORK")
    base:SetHeight(1)
    base:SetPoint("BOTTOMLEFT",  graphHolder, "BOTTOMLEFT",  PL,  PB)
    base:SetPoint("BOTTOMRIGHT", graphHolder, "BOTTOMRIGHT", -PR, PB)
    base:SetColorTexture(ar2, ag2, ab2, 0.30)

    -- Legend dots
    local function Dot(xOff, r, g, b, lbl)
      local dot = graphHolder:CreateTexture(nil, "OVERLAY"); dot:SetSize(8,8)
      dot:SetPoint("TOPLEFT", graphHolder, "TOPLEFT", xOff, -4)
      dot:SetColorTexture(r,g,b,1)
      local fs = graphHolder:CreateFontString(nil, "OVERLAY")
      fs:SetFont(NS.FONT, 8, "")
      fs:SetPoint("LEFT", graphHolder, "TOPLEFT", xOff+11, -4)
      fs:SetTextColor(0.60,0.60,0.70); fs:SetText(lbl)
    end
    Dot(PL,      0.85,0.25,0.25, "Gave")
    Dot(PL+52,   0.20,0.80,0.25, "Received")

    -- Bars oldest=left newest=right
    for i = NUM_DAYS, 1, -1 do
      local d   = days[i]
      local col = NUM_DAYS - i
      local xB  = PL + col * slot

      -- Gave (red, left half) — anchored from BOTTOMLEFT of chart area
      if d.gave > 0 then
        local bh = math.max(2, math.floor(d.gave / maxVal * CH))
        local bar = graphHolder:CreateTexture(nil, "ARTWORK")
        bar:SetSize(math.floor(BW/2)-1, bh)
        bar:SetPoint("BOTTOMLEFT", graphHolder, "BOTTOMLEFT", xB, PB)
        bar:SetColorTexture(0.85,0.25,0.25,0.82)
        local cap = graphHolder:CreateTexture(nil, "ARTWORK")
        cap:SetSize(math.floor(BW/2)-1, 2)
        cap:SetPoint("BOTTOMLEFT", graphHolder, "BOTTOMLEFT", xB, PB + bh - 2)
        cap:SetColorTexture(1,0.55,0.55,1)
      end

      -- Received (green, right half) — anchored from BOTTOMLEFT of chart area
      if d.received > 0 then
        local bh = math.max(2, math.floor(d.received / maxVal * CH))
        local bar = graphHolder:CreateTexture(nil, "ARTWORK")
        bar:SetSize(math.ceil(BW/2)-1, bh)
        bar:SetPoint("BOTTOMLEFT", graphHolder, "BOTTOMLEFT", xB + math.floor(BW/2), PB)
        bar:SetColorTexture(0.20,0.80,0.25,0.82)
        local cap = graphHolder:CreateTexture(nil, "ARTWORK")
        cap:SetSize(math.ceil(BW/2)-1, 2)
        cap:SetPoint("BOTTOMLEFT", graphHolder, "BOTTOMLEFT", xB + math.floor(BW/2), PB + bh - 2)
        cap:SetColorTexture(0.55,1,0.55,1)
      end

      -- Date label at adaptive frequency
      local lblEvery = NUM_DAYS <= 7 and 1 or NUM_DAYS <= 14 and 2 or NUM_DAYS <= 30 and 4 or NUM_DAYS <= 180 and 14 or 30
      if (col % lblEvery == 0) then
        local fs = graphHolder:CreateFontString(nil, "OVERLAY")
        fs:SetFont(NS.FONT, 7, "")
        fs:SetPoint("BOTTOMLEFT", graphHolder, "BOTTOMLEFT", xB, PB - 12)
        fs:SetTextColor(0.38,0.38,0.48); fs:SetText(d.label)
      end

      -- Hover tooltip
      if d.gave > 0 or d.received > 0 then
        local hit = CreateFrame("Frame", nil, graphHolder)
        hit:SetSize(slot, CH)
        hit:SetPoint("BOTTOMLEFT", graphHolder, "BOTTOMLEFT", xB, PB)
        hit:EnableMouse(true)
        local cd = d
        hit:SetScript("OnEnter", function(self)
          GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
          GameTooltip:SetText(cd.key, ar2, ag2, ab2)
          if cd.gave     > 0 then GameTooltip:AddLine("Gave:      "..(MoneyStr(cd.gave)     or "0"), 0.9,0.3,0.3) end
          if cd.received > 0 then GameTooltip:AddLine("Received: "..(MoneyStr(cd.received) or "0"), 0.3,0.9,0.3) end
          local net = cd.received - cd.gave
          if net ~= 0 then
            GameTooltip:AddLine("Net: "..(net>0 and "+" or "")..(MoneyStr(math.abs(net)) or "0"),
              net>0 and 0.3 or 0.9, net>0 and 0.9 or 0.3, 0.3)
          end
          GameTooltip:Show()
        end)
        hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
      end
    end
  end

  for _, b in ipairs(allRangeBtns) do
    local capDays = b._days
    b:SetScript("OnClick", function() graphDays=capDays; SetActiveBtn(capDays); RenderInlineGraph() end)
  end

  -- ── OnShow ───────────────────────────────────────────────────────────────
  container:SetScript("OnShow", function()
    enableCB:SetValue(DB("gtEnabled") ~= false)
    whisperCB:SetValue(DB("gtWhisper") == true)
    local hist = GetHistory()
    local got, gave = 0, 0
    for _, e in ipairs(hist) do
      got  = got  + (e.targetGold or 0)
      gave = gave + (e.playerGold or 0)
    end
    local net = got - gave
    local nr, ng, nb = net >= 0 and 0.3 or 0.9, net >= 0 and 0.9 or 0.3, 0.3

    statsLines[1]:SetText(tostring(#hist))
    statsLines[2]:SetText(MoneyStr(got) or "0c"); statsLines[2]:SetTextColor(1, 0.82, 0)
    statsLines[3]:SetText(MoneyStr(gave) or "0c"); statsLines[3]:SetTextColor(0.75, 0.75, 0.85)
    -- net = received - gave: negative means you gave more than you received
    local netSign = net >= 0 and "+" or "-"
    statsLines[4]:SetText(netSign..(MoneyStr(math.abs(net)) or "0c"))
    statsLines[4]:SetTextColor(nr, ng, nb)

    -- Render graph on a short delay so the card has its final width
    SetActiveBtn(graphDays)
    C_Timer.After(0.05, RenderInlineGraph)
  end)

  return container
end
