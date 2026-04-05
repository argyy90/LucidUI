-- LucidUI Debug/Main.lua
-- Dev Monitor: passive error/taint logging + active monitoring panels.
-- Passive mode (window closed): ring-buffer for errors, zero tickers.
-- Active mode (window open): live event monitor, perf stats, chat debug.

local NS = LucidUINS
NS.Debug = NS.Debug or {}

local BD = {bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1}
local FONT = "Fonts/FRIZQT__.TTF"
local MAX_LOG = 200

-- ── Passive ring-buffer (always active, no tickers) ────────────────────
local logBuffer = {}  -- {timestamp, category, text, r, g, b}

local CATS = {
  ERROR  = {1, 0.3, 0.3},
  TAINT  = {1, 0.6, 0.2},
  EVENT  = {0.5, 0.8, 1},
  CHAT   = {0.4, 0.9, 0.5},
  CDM    = {0.8, 0.5, 1},
  PERF   = {1, 0.9, 0.4},
  INFO   = {0.6, 0.6, 0.6},
}

local function AddLog(cat, text)
  local entry = {
    ts = date("%H:%M:%S"),
    cat = cat or "INFO",
    text = text or "",
  }
  logBuffer[#logBuffer + 1] = entry
  if #logBuffer > MAX_LOG then table.remove(logBuffer, 1) end
  -- If window is open, push to display (respecting active filter)
  if NS._devMonitorSMF and not NS._devMonitorPaused then
    local filt = NS._devMonitorFilter or "ALL"
    if filt == "ALL" or filt == entry.cat then
      local cc = CATS[entry.cat] or CATS.INFO
      local catHex = string.format("%02x%02x%02x", cc[1]*255, cc[2]*255, cc[3]*255)
      NS._devMonitorSMF:AddMessage(
        "|cff737373" .. entry.ts .. "|r |cff" .. catHex .. "[" .. entry.cat .. "]|r " .. entry.text,
        cc[1], cc[2], cc[3]
      )
    end
  end
end

-- Public API (passive, cheap)
function NS.Debug.Log(cat, text) AddLog(cat, text) end
NS.DebugLog = function(text) AddLog("INFO", text) end

-- ── Passive error capture ──────────────────────────────────────────────
-- Hook Blizzard's error handler to capture LucidUI errors
local origErrorHandler = geterrorhandler()
seterrorhandler(function(msg)
  if msg and type(msg) == "string" and msg:find("LucidUI") then
    AddLog("ERROR", msg:sub(1, 200))
  end
  if origErrorHandler then return origErrorHandler(msg) end
end)

-- Capture taint events passively
local taintFrame = CreateFrame("Frame")
taintFrame:RegisterEvent("ADDON_ACTION_BLOCKED")
taintFrame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
taintFrame:SetScript("OnEvent", function(_, event, addon, func)
  if addon == "LucidUI" then
    AddLog("TAINT", event .. ": " .. (func or "?"))
  end
end)

-- ── Active monitoring (only when window is open) ───────────────────────
local devWin = nil
local activeTab = "log"
local eventMonitorFrame = nil

local function GetAccent()
  local C = NS.CYAN; return C[1], C[2], C[3]
end

-- ── Build Dev Monitor Window ───────────────────────────────────────────
NS.BuildDebugWindow = function()
  if devWin then devWin:SetShown(not devWin:IsShown()); return end

  local ar, ag, ab = GetAccent()

  -- Helper: create SMF with scrollbar
  local function CreateSMFWithScrollbar(parent, fontSize)
    local container = CreateFrame("Frame", nil, parent)
    container:SetAllPoints()
    local SB_W = 14
    local smfInner = CreateFrame("ScrollingMessageFrame", nil, container)
    smfInner:SetPoint("TOPLEFT"); smfInner:SetPoint("BOTTOMRIGHT", -SB_W, 0)
    smfInner:SetFont(FONT, fontSize or 10, ""); smfInner:SetJustifyH("LEFT")
    smfInner:SetMaxLines(MAX_LOG); smfInner:SetFading(false)
    smfInner:SetInsertMode(SCROLLING_MESSAGE_FRAME_INSERT_MODE_BOTTOM)

    local sbTrack = container:CreateTexture(nil, "BACKGROUND")
    sbTrack:SetWidth(SB_W); sbTrack:SetPoint("TOPRIGHT"); sbTrack:SetPoint("BOTTOMRIGHT")
    sbTrack:SetColorTexture(0.03, 0.03, 0.05, 0.8)

    local sb = CreateFrame("Slider", nil, container)
    sb:SetOrientation("VERTICAL"); sb:SetWidth(SB_W - 4)
    sb:SetPoint("TOPRIGHT", -2, -2); sb:SetPoint("BOTTOMRIGHT", -2, 2)
    sb:SetMinMaxValues(0, 1); sb:SetValue(1); sb:SetValueStep(1); sb:SetObeyStepOnDrag(true)
    sb:SetThumbTexture("Interface/Buttons/WHITE8X8")
    local thumb = sb:GetThumbTexture()
    if thumb then thumb:SetSize(SB_W - 4, 30); thumb:SetColorTexture(0.4, 0.4, 0.5, 0.7) end

    smfInner:EnableMouseWheel(true)
    smfInner:SetScript("OnMouseWheel", function(self, delta)
      if delta > 0 then self:ScrollUp() else self:ScrollDown() end
    end)

    return smfInner
  end

  devWin = CreateFrame("Frame", "LucidUIDevMonitor", UIParent, "BackdropTemplate")
  local size = NS.DB("debugWinSize") or {650, 420}
  devWin:SetSize(size[1], size[2])
  local pos = NS.DB("debugWinPos")
  if pos then devWin:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
  else devWin:SetPoint("CENTER") end
  devWin:SetFrameStrata("HIGH"); devWin:SetToplevel(true)
  devWin:SetMovable(true); devWin:SetResizable(true); devWin:SetResizeBounds(500, 300)
  devWin:SetClampedToScreen(true); devWin:EnableMouse(true)
  devWin:RegisterForDrag("LeftButton")
  devWin:SetScript("OnDragStart", devWin.StartMoving)
  devWin:SetScript("OnDragStop", function()
    devWin:StopMovingOrSizing()
    local p, _, rp, x, y = devWin:GetPoint(1)
    NS.DBSet("debugWinPos", {p, rp, math.floor(x), math.floor(y)})
  end)
  devWin:SetBackdrop(BD)
  devWin:SetBackdropColor(0.025, 0.025, 0.038, 0.97)
  devWin:SetBackdropBorderColor(ar, ag, ab, 0.38)
  NS.debugWin = devWin

  -- Accent line
  local acc = devWin:CreateTexture(nil, "OVERLAY", nil, 5)
  acc:SetPoint("TOPLEFT", 1, -1); acc:SetPoint("TOPRIGHT", -1, -1)
  acc:SetHeight(1); acc:SetColorTexture(ar, ag, ab, 1)

  -- Header
  local hdr = devWin:CreateTexture(nil, "BACKGROUND", nil, 2)
  hdr:SetPoint("TOPLEFT", 1, -1); hdr:SetPoint("TOPRIGHT", -1, -1)
  hdr:SetHeight(28); hdr:SetColorTexture(0.01, 0.01, 0.02, 1)

  local title = devWin:CreateFontString(nil, "OVERLAY")
  title:SetFont(FONT, 11, ""); title:SetPoint("LEFT", hdr, "LEFT", 10, 0)
  title:SetTextColor(ar, ag, ab); title:SetText("Dev Monitor")

  -- Copy button
  local copyBtn = CreateFrame("Button", nil, devWin, "BackdropTemplate")
  copyBtn:SetSize(20, 20); copyBtn:SetPoint("TOPRIGHT", -28, -4)
  copyBtn:SetBackdrop(BD); copyBtn:SetBackdropColor(0.05, 0.05, 0.09, 1)
  copyBtn:SetBackdropBorderColor(0.12, 0.12, 0.20, 1)
  local copyLbl = copyBtn:CreateFontString(nil, "OVERLAY")
  copyLbl:SetFont(FONT, 9, ""); copyLbl:SetPoint("CENTER"); copyLbl:SetTextColor(0.44, 0.44, 0.52); copyLbl:SetText("C")
  copyBtn:SetScript("OnEnter", function()
    copyBtn:SetBackdropBorderColor(ar, ag, ab, 0.75); copyLbl:SetTextColor(ar, ag, ab)
    GameTooltip:SetOwner(copyBtn, "ANCHOR_LEFT"); GameTooltip:SetText("Copy Log"); GameTooltip:Show()
  end)
  copyBtn:SetScript("OnLeave", function()
    copyBtn:SetBackdropBorderColor(0.12, 0.12, 0.20, 1); copyLbl:SetTextColor(0.44, 0.44, 0.52); GameTooltip:Hide()
  end)
  copyBtn:SetScript("OnClick", function()
    local lines = {}
    -- Copy content based on active tab
    local sourceSMF
    if activeTab == "log" then
      for _, e in ipairs(logBuffer) do
        lines[#lines+1] = e.ts .. " [" .. e.cat .. "] " .. e.text
      end
      sourceSMF = NS._devMonitorSMF
    elseif activeTab == "events" then
      sourceSMF = devWin._evSMF
    elseif activeTab == "chat" then
      sourceSMF = NS._devChatSMF
    end
    -- If we have an SMF, extract messages from it
    if #lines == 0 and sourceSMF and sourceSMF.GetNumMessages then
      for i = 1, sourceSMF:GetNumMessages() do
        local msg = sourceSMF:GetMessageInfo(i)
        if msg then
          -- Strip WoW color codes for plain text copy
          local clean = msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
          lines[#lines+1] = clean
        end
      end
    end
    if #lines == 0 then lines[1] = "(No entries)" end
    local text = table.concat(lines, "\n")

    local cf = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    cf:SetSize(500, 350); cf:SetPoint("CENTER"); cf:SetFrameStrata("FULLSCREEN_DIALOG")
    cf:SetMovable(true); cf:SetClampedToScreen(true); cf:EnableMouse(true)
    cf:RegisterForDrag("LeftButton")
    cf:SetScript("OnDragStart", cf.StartMoving); cf:SetScript("OnDragStop", cf.StopMovingOrSizing)
    cf:SetBackdrop(BD); cf:SetBackdropColor(0.025, 0.025, 0.038, 0.97)
    cf:SetBackdropBorderColor(ar, ag, ab, 0.38)

    local cfAcc = cf:CreateTexture(nil, "OVERLAY", nil, 5)
    cfAcc:SetPoint("TOPLEFT", 1, -1); cfAcc:SetPoint("TOPRIGHT", -1, -1)
    cfAcc:SetHeight(1); cfAcc:SetColorTexture(ar, ag, ab, 1)

    local cfTitle = cf:CreateFontString(nil, "OVERLAY")
    cfTitle:SetFont(FONT, 10, ""); cfTitle:SetPoint("TOPLEFT", 10, -8)
    cfTitle:SetTextColor(ar, ag, ab); cfTitle:SetText("Copy Log (Ctrl+A, Ctrl+C)")

    local cfClose = CreateFrame("Button", nil, cf)
    cfClose:SetSize(16, 16); cfClose:SetPoint("TOPRIGHT", -4, -4)
    local cfX = cfClose:CreateFontString(nil, "OVERLAY")
    cfX:SetFont(FONT, 11, ""); cfX:SetPoint("CENTER"); cfX:SetTextColor(0.5, 0.3, 0.3); cfX:SetText("X")
    cfClose:SetScript("OnClick", function() cf:Hide() end)
    cfClose:SetScript("OnEnter", function() cfX:SetTextColor(1, 0.3, 0.3) end)
    cfClose:SetScript("OnLeave", function() cfX:SetTextColor(0.5, 0.3, 0.3) end)

    local sf = CreateFrame("ScrollFrame", nil, cf, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 8, -24); sf:SetPoint("BOTTOMRIGHT", -28, 8)
    local eb = CreateFrame("EditBox", nil, cf)
    eb:SetMultiLine(true); eb:SetAutoFocus(true); eb:SetFontObject(GameFontHighlight); eb:SetWidth(460)
    eb:SetScript("OnEscapePressed", function() cf:Hide() end)
    sf:SetScrollChild(eb)
    C_Timer.After(0, function()
      if cf:IsShown() then eb:SetWidth(sf:GetWidth()); eb:SetText(text); eb:HighlightText() end
    end)
  end)

  -- Close
  local closeBtn = CreateFrame("Button", nil, devWin, "BackdropTemplate")
  closeBtn:SetSize(20, 20); closeBtn:SetPoint("TOPRIGHT", -4, -4)
  closeBtn:SetBackdrop(BD); closeBtn:SetBackdropColor(0.09, 0.02, 0.02, 1)
  closeBtn:SetBackdropBorderColor(0.34, 0.09, 0.09, 1)
  local cX = closeBtn:CreateFontString(nil, "OVERLAY")
  cX:SetFont(FONT, 10, ""); cX:SetPoint("CENTER"); cX:SetTextColor(0.6, 0.18, 0.18); cX:SetText("X")
  closeBtn:SetScript("OnClick", function()
    devWin:Hide()
    -- Stop active monitoring
    if eventMonitorFrame then eventMonitorFrame:UnregisterAllEvents() end
    if devWin._perfTicker then devWin._perfTicker:Cancel(); devWin._perfTicker = nil end
    NS._devChatSMF = nil
    NS._devMonitorSMF = nil
  end)
  closeBtn:SetScript("OnEnter", function() closeBtn:SetBackdropBorderColor(0.6, 0.12, 0.12, 1); cX:SetTextColor(1, 0.3, 0.3) end)
  closeBtn:SetScript("OnLeave", function() closeBtn:SetBackdropBorderColor(0.34, 0.09, 0.09, 1); cX:SetTextColor(0.6, 0.18, 0.18) end)

  -- Header line
  local hLine = devWin:CreateTexture(nil, "OVERLAY", nil, 4)
  hLine:SetPoint("TOPLEFT", 1, -28); hLine:SetPoint("TOPRIGHT", -1, -28)
  hLine:SetHeight(1); hLine:SetColorTexture(ar, ag, ab, 0.3)

  -- ── Tab buttons ──────────────────────────────────────────────────────
  local TAB_Y = -30
  local TAB_H = 20
  local tabs = {"Log", "Events", "Perf", "Chat"}
  local tabBtns = {}
  local contentFrames = {}

  local function SelectTab(tabName)
    activeTab = tabName:lower()
    for _, t in ipairs(tabBtns) do
      local sel = t.name:lower() == activeTab
      t.label:SetTextColor(sel and ar or 0.45, sel and ag or 0.45, sel and ab or 0.55)
      t.sel:SetShown(sel)
    end
    for k, cf in pairs(contentFrames) do cf:SetShown(k == activeTab) end
    -- Start/stop event monitor
    if activeTab == "events" then
      if eventMonitorFrame then
        for _, ev in ipairs({"SPELL_UPDATE_COOLDOWN","UNIT_SPELLCAST_START","UNIT_SPELLCAST_STOP","UNIT_SPELLCAST_SUCCEEDED","PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED","UNIT_AURA","PLAYER_TARGET_CHANGED"}) do
          pcall(eventMonitorFrame.RegisterEvent, eventMonitorFrame, ev)
        end
      end
    elseif eventMonitorFrame then
      eventMonitorFrame:UnregisterAllEvents()
    end
    -- Start/stop perf ticker
    if activeTab == "perf" then
      if not devWin._perfTicker then
        devWin._perfTicker = C_Timer.NewTicker(1, function()
          if contentFrames.perf and contentFrames.perf:IsShown() then
            local fps = math.floor(GetFramerate())
            local latH, latW = select(3, GetNetStats()), select(4, GetNetStats())
            local mem = math.floor(collectgarbage("count"))
            if UpdateAddOnMemoryUsage then UpdateAddOnMemoryUsage() end
            local luiMem = GetAddOnMemoryUsage and GetAddOnMemoryUsage("LucidUI") or 0
            contentFrames.perf._fps:SetText("|cff" .. string.format("%02x%02x%02x", ar*255, ag*255, ab*255) .. "FPS:|r " .. fps)
            contentFrames.perf._lat:SetText("|cff" .. string.format("%02x%02x%02x", ar*255, ag*255, ab*255) .. "Latency:|r " .. latH .. "ms (H) " .. latW .. "ms (W)")
            contentFrames.perf._mem:SetText("|cff" .. string.format("%02x%02x%02x", ar*255, ag*255, ab*255) .. "Total Memory:|r " .. string.format("%.1f MB", mem / 1024))
            contentFrames.perf._luiMem:SetText("|cff" .. string.format("%02x%02x%02x", ar*255, ag*255, ab*255) .. "LucidUI:|r " .. string.format("%.1f KB", luiMem))
          end
        end)
      end
    elseif devWin._perfTicker then
      devWin._perfTicker:Cancel(); devWin._perfTicker = nil
    end
  end

  local tabX = 4
  for _, tabName in ipairs(tabs) do
    local btn = CreateFrame("Button", nil, devWin)
    btn:SetSize(50, TAB_H); btn:SetPoint("TOPLEFT", tabX, TAB_Y)
    local label = btn:CreateFontString(nil, "OVERLAY")
    label:SetFont(FONT, 9, ""); label:SetPoint("CENTER"); label:SetTextColor(0.45, 0.45, 0.55)
    label:SetText(tabName)
    local sel = btn:CreateTexture(nil, "OVERLAY", nil, 5)
    sel:SetHeight(1); sel:SetPoint("BOTTOMLEFT", 2, 0); sel:SetPoint("BOTTOMRIGHT", -2, 0)
    sel:SetColorTexture(ar, ag, ab, 1); sel:Hide()
    btn:SetScript("OnClick", function() SelectTab(tabName) end)
    btn:SetScript("OnEnter", function() label:SetTextColor(ar, ag, ab) end)
    btn:SetScript("OnLeave", function()
      if activeTab ~= tabName:lower() then label:SetTextColor(0.45, 0.45, 0.55) end
    end)
    tabBtns[#tabBtns+1] = {btn=btn, name=tabName, label=label, sel=sel}
    tabX = tabX + 54
  end

  -- Tab line
  local tabLine = devWin:CreateTexture(nil, "OVERLAY", nil, 3)
  tabLine:SetHeight(1); tabLine:SetPoint("TOPLEFT", 1, TAB_Y - TAB_H)
  tabLine:SetPoint("TOPRIGHT", -1, TAB_Y - TAB_H)
  tabLine:SetColorTexture(ar, ag, ab, 0.15)

  local CONTENT_TOP = TAB_Y - TAB_H - 2

  -- ── Log Tab (SMF) ────────────────────────────────────────────────────
  local logFrame = CreateFrame("Frame", nil, devWin)
  logFrame:SetPoint("TOPLEFT", 4, CONTENT_TOP); logFrame:SetPoint("BOTTOMRIGHT", -4, 20)
  contentFrames["log"] = logFrame

  -- Filter buttons
  local filterBar = CreateFrame("Frame", nil, logFrame)
  filterBar:SetHeight(16); filterBar:SetPoint("TOPLEFT"); filterBar:SetPoint("TOPRIGHT")
  local activeFilter = "ALL"
  NS._devMonitorFilter = "ALL"
  local filterBtns = {}
  local fX = 0
  for _, cat in ipairs({"ALL","ERROR","TAINT","EVENT","CHAT","CDM","PERF","INFO"}) do
    local fb = CreateFrame("Button", nil, filterBar)
    local catC = CATS[cat] or {1,1,1}
    fb:SetSize(38, 14); fb:SetPoint("LEFT", fX, 0)
    local fl = fb:CreateFontString(nil, "OVERLAY")
    fl:SetFont(FONT, 8, ""); fl:SetPoint("CENTER")
    fl:SetText(cat); fl:SetTextColor(catC[1], catC[2], catC[3], activeFilter == cat and 1 or 0.4)
    fb:SetScript("OnClick", function()
      activeFilter = cat
      NS._devMonitorFilter = cat
      for _, f in ipairs(filterBtns) do
        local fc = CATS[f.cat] or {1,1,1}
        f.label:SetTextColor(fc[1], fc[2], fc[3], activeFilter == f.cat and 1 or 0.4)
      end
      -- Refresh SMF
      NS._devMonitorSMF:Clear()
      for _, e in ipairs(logBuffer) do
        if activeFilter == "ALL" or activeFilter == e.cat then
          local cc = CATS[e.cat] or CATS.INFO
          local ch = string.format("%02x%02x%02x", cc[1]*255, cc[2]*255, cc[3]*255)
          NS._devMonitorSMF:AddMessage("|cff737373" .. e.ts .. "|r |cff" .. ch .. "[" .. e.cat .. "]|r " .. e.text, cc[1], cc[2], cc[3])
        end
      end
    end)
    filterBtns[#filterBtns+1] = {cat=cat, label=fl}
    fX = fX + 40
  end

  -- Pause / Clear
  NS._devMonitorPaused = false
  local pauseBtn = CreateFrame("Button", nil, filterBar)
  pauseBtn:SetSize(36, 14); pauseBtn:SetPoint("RIGHT", -40, 0)
  local pauseLbl = pauseBtn:CreateFontString(nil, "OVERLAY")
  pauseLbl:SetFont(FONT, 8, ""); pauseLbl:SetPoint("CENTER"); pauseLbl:SetTextColor(1, 0.8, 0); pauseLbl:SetText("PAUSE")
  pauseBtn:SetScript("OnClick", function()
    NS._devMonitorPaused = not NS._devMonitorPaused
    pauseLbl:SetText(NS._devMonitorPaused and "RESUME" or "PAUSE")
    pauseLbl:SetTextColor(NS._devMonitorPaused and 0.3 or 1, NS._devMonitorPaused and 1 or 0.8, NS._devMonitorPaused and 0.3 or 0)
  end)

  local clearBtn = CreateFrame("Button", nil, filterBar)
  clearBtn:SetSize(32, 14); clearBtn:SetPoint("RIGHT", 0, 0)
  local clearLbl = clearBtn:CreateFontString(nil, "OVERLAY")
  clearLbl:SetFont(FONT, 8, ""); clearLbl:SetPoint("CENTER"); clearLbl:SetTextColor(1, 0.3, 0.3); clearLbl:SetText("CLEAR")
  clearBtn:SetScript("OnClick", function() wipe(logBuffer); NS._devMonitorSMF:Clear() end)

  -- SMF for log display (with scrollbar)
  local logContainer = CreateFrame("Frame", nil, logFrame)
  logContainer:SetPoint("TOPLEFT", 0, -20); logContainer:SetPoint("BOTTOMRIGHT")
  local smf = CreateSMFWithScrollbar(logContainer, 10)
  NS._devMonitorSMF = smf

  -- Load existing buffer into SMF
  for _, e in ipairs(logBuffer) do
    local cc = CATS[e.cat] or CATS.INFO
    local ch = string.format("%02x%02x%02x", cc[1]*255, cc[2]*255, cc[3]*255)
    smf:AddMessage("|cff737373" .. e.ts .. "|r |cff" .. ch .. "[" .. e.cat .. "]|r " .. e.text, cc[1], cc[2], cc[3])
  end

  -- ── Events Tab ───────────────────────────────────────────────────────
  local evFrame = CreateFrame("Frame", nil, devWin)
  evFrame:SetPoint("TOPLEFT", 4, CONTENT_TOP); evFrame:SetPoint("BOTTOMRIGHT", -4, 20)
  evFrame:Hide()
  contentFrames["events"] = evFrame

  local evSMF = CreateSMFWithScrollbar(evFrame, 9)
  devWin._evSMF = evSMF

  eventMonitorFrame = CreateFrame("Frame")
  eventMonitorFrame:SetScript("OnEvent", function(_, event, ...)
    -- Filter UNIT_ events to player only
    local arg1 = ...
    if event:sub(1, 5) == "UNIT_" and arg1 and arg1 ~= "player" then return end

    local args = ""
    for i = 1, math.min(select("#", ...), 5) do
      local v = select(i, ...)
      if v ~= nil then
        local isSecret = issecretvalue and issecretvalue(v)
        local s = isSecret and "<secret>" or tostring(v)
        args = args .. (i > 1 and ", " or "") .. s
      end
    end
    local ts = date("%H:%M:%S")
    local evHex = string.format("%02x%02x%02x", ar*255, ag*255, ab*255)
    evSMF:AddMessage("|cff737373" .. ts .. "|r |cff" .. evHex .. event .. "|r " .. args, 0.7, 0.7, 0.7)
  end)

  -- ── Perf Tab ─────────────────────────────────────────────────────────
  local perfFrame = CreateFrame("Frame", nil, devWin)
  perfFrame:SetPoint("TOPLEFT", 4, CONTENT_TOP); perfFrame:SetPoint("BOTTOMRIGHT", -4, 20)
  perfFrame:Hide()
  contentFrames["perf"] = perfFrame

  local function PerfLabel(yOff)
    local fs = perfFrame:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, 12, ""); fs:SetPoint("TOPLEFT", 10, yOff)
    fs:SetTextColor(0.7, 0.7, 0.8); fs:SetJustifyH("LEFT")
    return fs
  end
  perfFrame._fps = PerfLabel(-10)
  perfFrame._lat = PerfLabel(-30)
  perfFrame._mem = PerfLabel(-50)
  perfFrame._luiMem = PerfLabel(-70)

  -- Active tickers count
  local tickerLabel = PerfLabel(-100)
  tickerLabel:SetText("|cff" .. string.format("%02x%02x%02x", ar*255, ag*255, ab*255) .. "Active Tickers:|r see AddonProfiler /luiperf")

  -- ── Chat Tab ─────────────────────────────────────────────────────────
  local chatFrame = CreateFrame("Frame", nil, devWin)
  chatFrame:SetPoint("TOPLEFT", 4, CONTENT_TOP); chatFrame:SetPoint("BOTTOMRIGHT", -4, 20)
  chatFrame:Hide()
  contentFrames["chat"] = chatFrame

  local chatSMF = CreateSMFWithScrollbar(chatFrame, 9)

  -- Hook chat engine to log raw event data
  NS._devChatSMF = chatSMF

  -- ── Resize grip ──────────────────────────────────────────────────────
  local rg = CreateFrame("Frame", nil, devWin)
  rg:SetSize(16, 16); rg:SetPoint("BOTTOMRIGHT")
  rg:SetFrameLevel(devWin:GetFrameLevel() + 50); rg:EnableMouse(true)
  local rgTex = rg:CreateTexture(nil, "OVERLAY")
  rgTex:SetTexture("Interface/AddOns/LucidUI/Assets/resize.png"); rgTex:SetAllPoints()
  rgTex:SetVertexColor(0.4, 0.4, 0.5)
  rg:SetScript("OnEnter", function() rgTex:SetVertexColor(ar, ag, ab) end)
  rg:SetScript("OnLeave", function() rgTex:SetVertexColor(0.4, 0.4, 0.5) end)
  rg:SetScript("OnMouseDown", function() devWin:StartSizing("BOTTOMRIGHT") end)
  rg:SetScript("OnMouseUp", function()
    devWin:StopMovingOrSizing()
    NS.DBSet("debugWinSize", {math.floor(devWin:GetWidth()), math.floor(devWin:GetHeight())})
  end)

  SelectTab("Log")
  AddLog("INFO", "Dev Monitor opened")
end

-- ── Chat debug hook (passive, always logs to buffer if chat tab was visited) ──
-- Called from ChatFrame.lua FormatChatMessage to log raw event data
NS.Debug.LogChat = function(event, sender, msg)
  AddLog("CHAT", (event or "?") .. " | " .. (sender or "?") .. " | " .. (msg and msg:sub(1, 80) or ""))
  if NS._devChatSMF and activeTab == "chat" then
    local ts = date("%H:%M:%S")
    NS._devChatSMF:AddMessage(
      "|cff737373" .. ts .. "|r |cff4de64d" .. (event or "?") .. "|r " .. (sender or "?") .. ": " .. (msg and msg:sub(1, 120) or ""),
      0.6, 0.6, 0.6
    )
  end
end
