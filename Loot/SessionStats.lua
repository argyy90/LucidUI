-- LucidUI SessionStats.lua
-- Tracks per-session statistics: boss kills, deaths, loot, gold.
-- Resets on login and when entering a new dungeon/raid instance.

local NS   = LucidUINS
local L    = LucidUIL
local CYAN = NS.CYAN
local statsCollapsed = false

-- ── Session data (persisted in SavedVariables) ──────────────────────────────
NS.session = {
  zone = "", instanceID = nil, startTime = GetTime(),
  deaths = {}, deathOrder = {}, bosses = {}, wipes = 0,
  loot = {}, gold = 0, goldPrev = 0,
}

local function LoadSession()
  local saved = LucidUIDB and LucidUIDB._sessionData
  if saved and not saved._archived then
    -- DC recovery: session was not cleanly archived, restore it
    NS.session = {}
    local copyKeys = {"zone","instanceID","deaths","deathOrder","bosses","wipes","loot","gold","goldPrev","_wasInstance","_instType","_diffName","_groupSize"}
    for _, k in ipairs(copyKeys) do NS.session[k] = saved[k] end
    local savedElapsed = saved._savedElapsed or 0
    if savedElapsed < 0 or savedElapsed > 43200 then savedElapsed = 0 end
    NS.session.startTime = GetTime() - savedElapsed
  else
    -- Fresh session (new install, after clean logout, or archived)
    NS.session = {
      zone       = "",
      instanceID = nil,
      startTime  = GetTime(),
      deaths     = {},
      deathOrder = {},
      bosses     = {},
      wipes      = 0,
      loot       = {},
      gold       = 0,
      goldPrev   = 0,
    }
    LucidUIDB._sessionData = nil
  end
end

local function SaveSession()
  if not LucidUIDB then return end
  local ses = NS.session
  -- Store elapsed duration so offline time is not counted
  ses._savedElapsed = math.floor(GetTime() - ses.startTime)
  LucidUIDB._sessionData = ses
end

-- ── Session History (archive past sessions per zone) ────────────────────────
local function SessionHasData(ses)
  return (#ses.bosses > 0) or (#ses.deathOrder > 0) or (#ses.loot > 0) or (ses.gold > 0)
end

local function ArchiveSession()
  local ses = NS.session
  if not SessionHasData(ses) then return end
  LucidUIDB._sessionHistory = LucidUIDB._sessionHistory or {}
  local elapsed = GetTime() - ses.startTime

  -- Consolidate loot: group by item name, count occurrences
  local lootItems = {}
  local lootOrder = {}
  for _, l in ipairs(ses.loot) do
    local name = l.link and l.link:match("%[(.-)%]") or "Unknown"
    if lootItems[name] then
      lootItems[name].count = lootItems[name].count + 1
    else
      lootItems[name] = {link=l.link, quality=l.quality or 1, count=1}
      table.insert(lootOrder, name)
    end
  end
  local items = {}
  for _, name in ipairs(lootOrder) do
    local li = lootItems[name]
    table.insert(items, {name=name, link=li.link, quality=li.quality, count=li.count})
  end

  -- Consolidate bosses: count duplicates
  local bossMap = {}
  local bossOrder2 = {}
  for _, b in ipairs(ses.bosses) do
    if bossMap[b] then
      bossMap[b] = bossMap[b] + 1
    else
      bossMap[b] = 1
      table.insert(bossOrder2, b)
    end
  end
  local bossEntries = {}
  for _, b in ipairs(bossOrder2) do
    table.insert(bossEntries, {name=b, count=bossMap[b]})
  end

  local entry = {
    zone       = ses.zone or "?",
    date       = date("%Y-%m-%d %H:%M"),
    duration   = math.floor(elapsed),
    bosses     = bossEntries,
    deaths     = #ses.deathOrder,
    wipes      = ses.wipes or 0,
    lootCount  = #ses.loot,
    gold       = ses.gold or 0,
    items      = items,
    instType   = ses._instType,
    diffName   = ses._diffName,
    groupSize  = ses._groupSize,
  }
  table.insert(LucidUIDB._sessionHistory, entry)
  while #LucidUIDB._sessionHistory > 100 do
    table.remove(LucidUIDB._sessionHistory, 1)
  end
end

-- Save periodically and on logout
local saveFrame = CreateFrame("Frame")
local saveTimer = 0
saveFrame:SetScript("OnUpdate", function(_, elapsed)
  saveTimer = saveTimer + elapsed
  if saveTimer < 15 then return end
  saveTimer = 0
  SaveSession()
end)
saveFrame:RegisterEvent("PLAYER_LOGOUT")
saveFrame:RegisterEvent("ADDON_LOADED")
saveFrame:SetScript("OnEvent", function(_, event, addon)
  if event == "ADDON_LOADED" and addon and addon:lower() == "lucidui" then
    if not NS._sessionLoaded then
      LoadSession()
      NS._sessionLoaded = true
    end
    saveFrame:UnregisterEvent("ADDON_LOADED")
  elseif event == "PLAYER_LOGOUT" then
    ArchiveSession()
    -- Mark session as archived so LoadSession won't double-count after reload
    NS.session._archived = true
    SaveSession()
  end
end)

-- ── Helpers ───────────────────────────────────────────────────────────────────
local function FormatTime(seconds)
  local m = math.floor(seconds / 60)
  local s = math.floor(seconds % 60)
  if m >= 60 then
    return math.floor(m/60).."h "..(m%60).."m"
  elseif m > 0 then
    return m.."m "..s.."s"
  end
  return s.."s"
end

local function FormatGold(copper)
  if copper <= 0 then return "|cff8888880g|r" end
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  local parts = {}
  if g > 0 then table.insert(parts, "|cffffd700"..g.."g|r") end
  if s > 0 then table.insert(parts, "|cffc7c7cf"..s.."s|r") end
  if c > 0 or #parts == 0 then table.insert(parts, "|cffeda55f"..c.."c|r") end
  return table.concat(parts, " ")
end

-- ── Public API ────────────────────────────────────────────────────────────────
local function UpdateInstanceInfo()
  local ses = NS.session
  local _, itype, _, diffName, _, _, _, _, groupSize = GetInstanceInfo()
  ses._instType  = (itype and itype ~= "" and itype ~= "none") and itype or nil
  ses._diffName  = (diffName and diffName ~= "") and diffName or nil
  ses._groupSize = (groupSize and groupSize > 0) and groupSize or nil
end

NS.ResetSession = function()
  ArchiveSession()
  local ses = NS.session
  ses.zone       = GetRealZoneText() or "?"
  ses.startTime  = GetTime()
  ses.deaths     = {}
  ses.deathOrder = {}
  ses.bosses     = {}
  ses.wipes      = 0
  ses.loot       = {}
  ses.gold       = 0
  ses.goldPrev   = GetMoney()
  UpdateInstanceInfo()
  SaveSession()
  if NS.statsWin and NS.statsWin:IsShown() then NS.RefreshStatsWindow() end
end

NS.StatsAddDeath = function(name)
  if NS.DB and NS.DB("showStatsBtn") == false then return end
  local ses = NS.session
  ses.deaths[name] = (ses.deaths[name] or 0) + 1
  table.insert(ses.deathOrder, name)
  if NS.statsWin and NS.statsWin:IsShown() then NS.RefreshStatsWindow() end
end

NS.StatsAddBoss = function(name)
  if NS.DB and NS.DB("showStatsBtn") == false then return end
  table.insert(NS.session.bosses, name)
  if NS.statsWin and NS.statsWin:IsShown() then NS.RefreshStatsWindow() end
end

NS.StatsAddLoot = function(link, player, quality)
  if NS.DB and NS.DB("showStatsBtn") == false then return end
  table.insert(NS.session.loot, {link=link, player=player, quality=quality or 1})
  if NS.statsWin and NS.statsWin:IsShown() then NS.RefreshStatsWindow() end
end

-- ── Event handlers (called from LucidUI main eventFrame) ──────────
NS.StatsOnEnteringWorld = function()
  if NS.DB and NS.DB("showStatsBtn") == false then return end
  -- Ensure session is loaded from DB (may not have happened yet)
  if not NS._sessionLoaded and LucidUIDB then
    LoadSession()
    NS._sessionLoaded = true
  end
  local isLogin = not NS._statsFirstWorld
  NS._statsFirstWorld = true
  local _, itype, _, _, _, _, _, mapID = GetInstanceInfo()
  local wasInstance = NS.session._wasInstance
  local isInstance = (itype == "party" or itype == "raid" or itype == "scenario")

  -- Always update instance info on current session BEFORE any reset
  -- so ArchiveSession has the correct diffName/instType
  UpdateInstanceInfo()

  if isLogin then
    if not LucidUIDB._sessionData then
      NS.session._wasInstance = isInstance
      NS.session.instanceID = mapID
      NS.ResetSession()
    else
      NS.session._wasInstance = isInstance
      NS.session.instanceID = mapID
    end
  else
    if isInstance then
      if mapID ~= NS.session.instanceID then
        NS.session._wasInstance = true
        NS.session.instanceID = mapID
        NS.ResetSession()
      end
    elseif wasInstance then
      NS.session._wasInstance = false
      NS.session.instanceID = mapID
      NS.ResetSession()
    end
  end
  NS.session.goldPrev = GetMoney()
  if NS.statsWin and NS.statsWin:IsShown() then NS.RefreshStatsWindow() end
end

NS.StatsOnZoneChanged = function()
  if NS.DB and NS.DB("showStatsBtn") == false then return end
  local zoneName = GetRealZoneText()
  if not zoneName or zoneName == "" then return end

  -- Open world: archive + reset on zone change if enabled
  local _, itype = GetInstanceInfo()
  local isInstance = (itype == "party" or itype == "raid" or itype == "scenario")
  if not isInstance and NS.DB("statsResetOnZone") and zoneName ~= NS.session.zone then
    UpdateInstanceInfo()
    NS.ResetSession()
  end

  NS.session.zone = zoneName
  if NS.statsWin and NS.statsWin:IsShown() then NS.RefreshStatsWindow() end
end

NS.StatsOnEncounterEnd = function(_, encName, _, _, success)
  if NS.DB and NS.DB("showStatsBtn") == false then return end
  if success == 1 then
    NS.StatsAddBoss(encName)
  else
    NS.session.wipes = (NS.session.wipes or 0) + 1
    if NS.statsWin and NS.statsWin:IsShown() then NS.RefreshStatsWindow() end
  end
end

NS.StatsOnPlayerDead = function()
  if NS.DB and NS.DB("showStatsBtn") == false then return end
  local name = UnitName("player") or "?"
  NS.StatsAddDeath(name)
end

NS.StatsOnMoney = function()
  if NS.DB and NS.DB("showStatsBtn") == false then return end
  local cur = GetMoney()
  local ses = NS.session
  if cur > ses.goldPrev then ses.gold = ses.gold + (cur - ses.goldPrev) end
  ses.goldPrev = cur
end

-- ── Window: content refresh ───────────────────────────────────────────────────
NS.RefreshStatsWindow = function()
  if not NS.statsEditBox then return end
  local ses = NS.session
  local hex = string.format("%02x%02x%02x",
    math.floor(CYAN[1]*255), math.floor(CYAN[2]*255), math.floor(CYAN[3]*255))

  local function hdr(text)
    return "|cff"..hex..">|r |cff909090"..text.."|r"
  end
  local DIV = "|cff2a2a2a"..string.rep("-", 44).."|r"

  local lines = {}

  -- Zone + instance difficulty
  local zoneName = GetRealZoneText()
  if not zoneName or zoneName == "" then zoneName = ses.zone end
  local _, itype, _, diffName, _, _, _, _, groupSize = GetInstanceInfo()
  table.insert(lines, "|cffFFFFFF"..zoneName.."|r")
  if itype and itype ~= "" and itype ~= "none" then
    local infoStr = "|cff888888"..diffName
    if groupSize and groupSize > 0 then
      infoStr = infoStr.."  ("..groupSize..")|r"
    else
      infoStr = infoStr.."|r"
    end
    table.insert(lines, infoStr)
  end

  -- Summary line
  local elapsed    = GetTime() - ses.startTime
  local elapsedStr = FormatTime(elapsed)
  local sumLine = "|cff666666"..L["stat_session"]..": |cffaaaaaa"..elapsedStr..
    "|r  |cff666666"..L["stat_bosses"]..": |cffFFD700"..#ses.bosses..
    "|r  |cff666666"..L["stat_deaths"]..": |cffff4444"..#ses.deathOrder.."|r"
  if ses.wipes > 0 then
    sumLine = sumLine.."  |cff666666Wipes: |cffff8800"..ses.wipes.."|r"
  end
  table.insert(lines, sumLine)
  table.insert(lines, "")

  -- Bosses
  table.insert(lines, hdr(L["stat_bosses"]))
  table.insert(lines, DIV)
  if #ses.bosses == 0 then
    table.insert(lines, "|cff444444"..L["stat_no_data"].."|r")
  else
    for _, name in ipairs(ses.bosses) do
      table.insert(lines, "|cff3bd2ed+|r |cffFFD700"..name.."|r")
    end
  end
  table.insert(lines, "")

  -- Deaths
  table.insert(lines, hdr(L["stat_deaths"].." ("..#ses.deathOrder..")"))
  table.insert(lines, DIV)
  if #ses.deathOrder == 0 then
    table.insert(lines, "|cff444444"..L["stat_no_data"].."|r")
  else
    -- Show only own deaths in class color
    local playerName = UnitName("player") or "?"
    local _, englishClass = UnitClass("player")
    local classHex = "ffdddddd"
    if englishClass then
      local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[englishClass]
      if cc then classHex = string.format("ff%02x%02x%02x", cc.r*255, cc.g*255, cc.b*255) end
    end
    table.insert(lines, "|c"..classHex..playerName.."|r")
  end
  table.insert(lines, "")

  -- Loot: quality breakdown only
  table.insert(lines, hdr(L["stat_loot"].." ("..#ses.loot..")"))
  table.insert(lines, DIV)
  if #ses.loot == 0 then
    table.insert(lines, "|cff444444"..L["stat_no_data"].."|r")
  else
    local qCounts = {}
    for _, entry in ipairs(ses.loot) do
      local q = entry.quality or 1
      qCounts[q] = (qCounts[q] or 0) + 1
    end
    local qLabels = {[0]="Poor",[1]="Common",[2]="Uncommon",[3]="Rare",[4]="Epic",[5]="Legendary",[6]="Artifact",[7]="Heirloom"}
    local parts = {}
    for qi = 7, 0, -1 do
      if qCounts[qi] then
        local qc  = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[qi]
        local qhx = qc and string.format("%02x%02x%02x",
          math.floor(qc.r*255), math.floor(qc.g*255), math.floor(qc.b*255)) or "aaaaaa"
        table.insert(parts, "|cff"..qhx..qCounts[qi].."x "..(qLabels[qi] or "?").."|r")
      end
    end
    table.insert(lines, table.concat(parts, "  "))
  end
  table.insert(lines, "")

  -- Gold + gold/hour
  table.insert(lines, hdr(L["stat_gold"]))
  table.insert(lines, DIV)
  table.insert(lines, FormatGold(ses.gold))
  if elapsed > 60 and ses.gold > 0 then
    local gph = math.floor(ses.gold * 3600 / elapsed)
    table.insert(lines, "|cff666666/hr  |r"..FormatGold(gph))
  end

  NS.statsEditBox:SetText(table.concat(lines, "\n"))
  NS.statsEditBox:SetCursorPosition(0)

  -- Auto-resize: fit content, expand as list grows
  if NS.statsWin and not statsCollapsed then
    local chrome = NS.statsWin._chromePad or 49
    local wantH  = math.max(120, math.min(#lines, 20) * 12 + chrome)
    NS.statsWin._expandedH = wantH
    NS.statsWin:SetHeight(wantH)
  end
end

-- ── Window: build ─────────────────────────────────────────────────────────────
NS.BuildStatsWindow = function()
  if NS.statsWin then
    NS.statsWin:SetShown(not NS.statsWin:IsShown())
    if NS.statsWin:IsShown() then NS.RefreshStatsWindow() end
    return
  end

  local WIN_W  = 320
  local WIN_H  = 420
  local TITLE_H = 28
  local function GetT() return NS.GetTheme(NS.DB("theme")) end

  NS.statsWin = CreateFrame("Frame", "LucidUIStatsWindow", UIParent, "BackdropTemplate")
  NS.statsWin:SetSize(WIN_W, WIN_H)
  local spos = LucidUIDB and LucidUIDB.statsWinPos
  if spos then
    NS.statsWin:SetPoint(spos[1], UIParent, spos[2], spos[3], spos[4])
  else
    NS.statsWin:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
  NS.statsWin:SetFrameStrata("MEDIUM")
  NS.statsWin:SetToplevel(true)
  NS.statsWin:SetMovable(true)
  NS.statsWin:EnableMouse(true)
  NS.statsWin:RegisterForDrag("LeftButton")
  NS.statsWin:SetScript("OnDragStart", NS.statsWin.StartMoving)
  NS.statsWin:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    LucidUIDB.statsWinPos = {point, relPoint, math.floor(x), math.floor(y)}
  end)
  NS.statsWin:SetClampedToScreen(true)
  -- Not in UISpecialFrames so ESC doesn't close it
  NS.statsWin:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
  local function GetStatsAlpha()
    local at = NS._addonTable
    if at and at.Config then
      local trans = at.Config.Get(at.Config.Options.LOOT_STATS_TRANSPARENCY)
      if trans then return 1 - trans end
    end
    return 0.97
  end
  local t0 = GetT()
  NS.statsWin:SetBackdropColor(t0.bg[1], t0.bg[2], t0.bg[3], GetStatsAlpha())
  NS.statsWin:SetBackdropBorderColor(unpack(t0.border))
  NS.statsWin._ApplyTheme = function()
    local t = GetT()
    NS.statsWin:SetBackdropColor(t.bg[1], t.bg[2], t.bg[3], GetStatsAlpha())
    NS.statsWin:SetBackdropBorderColor(unpack(t.border))
    if NS.statsWin._titleBar then
      NS.statsWin._titleBar:SetBackdropColor(t.titleBg[1], t.titleBg[2], t.titleBg[3], 1)
    end
    if NS.statsWin._titleTxt then
      local tc  = t.titleText or {1,1,1,1}
      local tid = t.tilders   or {59/255, 210/255, 237/255, 1}
      local thex = string.format("%02x%02x%02x",
        math.floor(tid[1]*255), math.floor(tid[2]*255), math.floor(tid[3]*255))
      NS.statsWin._titleTxt:SetTextColor(tc[1], tc[2], tc[3], 1)
      NS.statsWin._titleTxt:SetText("|cff"..thex..">|r"..L["Session Stats"].."|cff"..thex.."<|r")
    end
  end

  -- Title bar
  local titleBar = CreateFrame("Frame", nil, NS.statsWin, "BackdropTemplate")
  titleBar:SetHeight(TITLE_H); titleBar:SetPoint("TOPLEFT",1,-1); titleBar:SetPoint("TOPRIGHT",-1,-1)
  titleBar:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8"})
  titleBar:SetBackdropColor(t0.titleBg[1], t0.titleBg[2], t0.titleBg[3], 1)
  NS.statsWin._titleBar = titleBar
  titleBar:EnableMouse(true); titleBar:RegisterForDrag("LeftButton")
  titleBar:SetScript("OnDragStart", function() NS.statsWin:StartMoving() end)
  titleBar:SetScript("OnDragStop",  function()
    NS.statsWin:StopMovingOrSizing()
    local point, _, relPoint, x, y = NS.statsWin:GetPoint()
    LucidUIDB.statsWinPos = {point, relPoint, math.floor(x), math.floor(y)}
  end)

  local hex = string.format("%02x%02x%02x",
    math.floor(CYAN[1]*255), math.floor(CYAN[2]*255), math.floor(CYAN[3]*255))
  local titleTxt = titleBar:CreateFontString(nil, "OVERLAY")
  titleTxt:SetFont("Fonts/FRIZQT__.TTF", 12, ""); titleTxt:SetPoint("LEFT", 10, 0)
  titleTxt:SetTextColor(1, 1, 1, 1)
  titleTxt:SetText("|cff"..hex..">|r"..L["Session Stats"].."|cff"..hex.."<|r")
  NS.statsWin._titleTxt = titleTxt

  -- Accent line under title bar
  local statsAccentLine = NS.statsWin:CreateTexture(nil, "ARTWORK")
  statsAccentLine:SetHeight(1)
  statsAccentLine:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, 0)
  statsAccentLine:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
  statsAccentLine:SetColorTexture(CYAN[1], CYAN[2], CYAN[3], 0.6)
  NS.statsWin._accentLine = statsAccentLine

  -- History button (settings cog)
  local histBtn = CreateFrame("Button", nil, titleBar)
  histBtn:SetSize(20, 20); histBtn:SetPoint("RIGHT", -50, 0)
  local histTex = histBtn:CreateTexture(nil, "ARTWORK")
  histTex:SetTexture("Interface/AddOns/LucidUI/Assets/SettingsCog.png")
  histTex:SetSize(14, 14); histTex:SetPoint("CENTER")
  histTex:SetVertexColor(0.6, 0.6, 0.6, 1)
  histBtn:SetScript("OnEnter", function()
    histTex:SetVertexColor(CYAN[1], CYAN[2], CYAN[3], 1)
    GameTooltip:SetOwner(histBtn, "ANCHOR_LEFT"); GameTooltip:SetText(L["Session History"]); GameTooltip:Show()
  end)
  histBtn:SetScript("OnLeave", function() histTex:SetVertexColor(0.6, 0.6, 0.6, 1); GameTooltip:Hide() end)
  histBtn:SetScript("OnClick", function() NS.BuildSessionHistoryWindow() end)

  -- Collapse button
  local statsCollapseBtn = CreateFrame("Button", nil, titleBar)
  statsCollapseBtn:SetSize(20, 20); statsCollapseBtn:SetPoint("RIGHT", -26, 0)
  local statsCollapseTex = statsCollapseBtn:CreateTexture(nil, "ARTWORK")
  statsCollapseTex:SetTexture("Interface/AddOns/LucidUI/Assets/ScrollToBottom.png")
  statsCollapseTex:SetSize(13, 13); statsCollapseTex:SetPoint("CENTER")
  statsCollapseTex:SetVertexColor(0.6, 0.6, 0.6, 1)
  local scrollFrameRef  -- will be set below
  local resetBtnRef     -- will be set below
  local function UpdateStatsCollapse()
    if statsCollapsed then
      statsCollapseTex:SetTexCoord(0,1, 1,0)
      NS.statsWin:SetHeight(TITLE_H + 2)
    else
      statsCollapseTex:SetTexCoord(0,1,0,1)
      NS.statsWin:SetHeight(NS.statsWin._expandedH or WIN_H)
    end
    if scrollFrameRef then scrollFrameRef:SetShown(not statsCollapsed) end
    if resetBtnRef then resetBtnRef:SetShown(not statsCollapsed) end
  end
  statsCollapseBtn:SetScript("OnEnter", function()
    statsCollapseTex:SetVertexColor(CYAN[1], CYAN[2], CYAN[3], 1)
    GameTooltip:SetOwner(statsCollapseBtn, "ANCHOR_LEFT")
    GameTooltip:SetText(statsCollapsed and L["Expand"] or L["Collapse"]); GameTooltip:Show()
  end)
  statsCollapseBtn:SetScript("OnLeave", function()
    statsCollapseTex:SetVertexColor(0.6, 0.6, 0.6, 1); GameTooltip:Hide()
  end)
  statsCollapseBtn:SetScript("OnClick", function()
    if not statsCollapsed then NS.statsWin._expandedH = NS.statsWin:GetHeight() end
    statsCollapsed = not statsCollapsed
    UpdateStatsCollapse()
  end)

  -- Close button
  local closeBtn = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
  closeBtn:SetSize(20, 20); closeBtn:SetPoint("RIGHT", -2, 0)
  closeBtn:SetFrameLevel(titleBar:GetFrameLevel() + 10)
  closeBtn:GetNormalTexture():SetVertexColor(0.8, 0.8, 0.8)
  closeBtn:SetScript("OnEnter", function() closeBtn:GetNormalTexture():SetVertexColor(CYAN[1], CYAN[2], CYAN[3]) end)
  closeBtn:SetScript("OnLeave", function() closeBtn:GetNormalTexture():SetVertexColor(0.8, 0.8, 0.8) end)
  closeBtn:SetScript("OnClick", function() NS.statsWin:Hide() end)

  -- Reset button (bottom right)
  local resetBtn = CreateFrame("Button", nil, NS.statsWin, "BackdropTemplate")
  resetBtn:SetSize(48, 18); resetBtn:SetPoint("BOTTOMRIGHT", -4, 4)
  resetBtn:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
  resetBtn:SetBackdropColor(0.08, 0.08, 0.08, 1); resetBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
  local resetLbl = resetBtn:CreateFontString(nil, "OVERLAY")
  resetLbl:SetFont("Fonts/FRIZQT__.TTF", 10, ""); resetLbl:SetPoint("CENTER")
  resetLbl:SetTextColor(0.7, 0.7, 0.7, 1); resetLbl:SetText(L["stat_reset"])
  resetBtn:SetScript("OnEnter", function() resetBtn:SetBackdropBorderColor(CYAN[1], CYAN[2], CYAN[3], 1) end)
  resetBtn:SetScript("OnLeave", function() resetBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1) end)
  resetBtn:SetScript("OnClick", NS.ResetSession)
  resetBtnRef = resetBtn

  -- Scroll frame + EditBox
  local scrollFrame = CreateFrame("ScrollFrame", nil, NS.statsWin, "UIPanelScrollFrameTemplate")
  scrollFrame:SetPoint("TOPLEFT",  4, -(TITLE_H + 5))
  scrollFrame:SetPoint("BOTTOMRIGHT", -22, 26)

  local editBox = CreateFrame("EditBox", nil, scrollFrame)
  editBox:SetMultiLine(true)
  editBox:SetAutoFocus(false)
  editBox:SetFont("Fonts/FRIZQT__.TTF", 11, "")
  editBox:SetTextColor(1, 1, 1, 1)
  editBox:SetWidth(WIN_W - 28)
  editBox:EnableMouse(false)
  editBox:SetScript("OnEscapePressed", function() NS.statsWin:Hide() end)
  scrollFrame:SetScrollChild(editBox)
  scrollFrameRef = scrollFrame
  NS.statsEditBox = editBox
  -- chrome = space taken by title bar + top gap + bottom margin + padding
  NS.statsWin._chromePad = TITLE_H + 5 + 4 + 12

  -- Auto-refresh every 5s while open (for session time)
  NS.statsWin:SetScript("OnUpdate", function(self, elapsed)
    self._t = (self._t or 0) + elapsed
    if self._t >= 5 then self._t = 0; NS.RefreshStatsWindow() end
  end)

  NS.RefreshStatsWindow()
end

-- ── Helper: create themed dark window ───────────────────────────────────────
local function MakeDarkWindow(name, width, height, titleText, posKey)
  local t = NS.GetTheme(NS.DB("theme"))
  local hex = string.format("%02x%02x%02x",
    math.floor(CYAN[1]*255), math.floor(CYAN[2]*255), math.floor(CYAN[3]*255))
  local TH = 28

  local win = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
  win:SetSize(width, height)
  local pos = LucidUIDB and LucidUIDB[posKey]
  if pos then win:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
  else win:SetPoint("CENTER", UIParent, "CENTER", 200, 0) end
  win:SetFrameStrata("MEDIUM"); win:SetToplevel(true)
  win:SetMovable(true); win:EnableMouse(true); win:SetClampedToScreen(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving)
  win:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    LucidUIDB[posKey] = {p, rp, math.floor(x), math.floor(y)}
  end)
  win:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
  win:SetBackdropColor(t.bg[1], t.bg[2], t.bg[3], 0.97)
  win:SetBackdropBorderColor(unpack(t.border))

  local tb = CreateFrame("Frame", nil, win, "BackdropTemplate")
  tb:SetHeight(TH); tb:SetPoint("TOPLEFT",1,-1); tb:SetPoint("TOPRIGHT",-1,-1)
  tb:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8"})
  tb:SetBackdropColor(t.titleBg[1], t.titleBg[2], t.titleBg[3], 1)
  tb:EnableMouse(true); tb:RegisterForDrag("LeftButton")
  tb:SetScript("OnDragStart", function() win:StartMoving() end)
  tb:SetScript("OnDragStop", function()
    win:StopMovingOrSizing()
    local p, _, rp, x, y = win:GetPoint()
    LucidUIDB[posKey] = {p, rp, math.floor(x), math.floor(y)}
  end)

  local ttxt = tb:CreateFontString(nil, "OVERLAY")
  ttxt:SetFont("Fonts/FRIZQT__.TTF", 12, ""); ttxt:SetPoint("LEFT", 10, 0)
  ttxt:SetText("|cff"..hex..">|r "..titleText.." |cff"..hex.."<|r")

  local al = win:CreateTexture(nil, "ARTWORK")
  al:SetHeight(1)
  al:SetPoint("TOPLEFT", tb, "BOTTOMLEFT", 0, 0)
  al:SetPoint("TOPRIGHT", tb, "BOTTOMRIGHT", 0, 0)
  al:SetColorTexture(CYAN[1], CYAN[2], CYAN[3], 0.6)

  local cb = CreateFrame("Button", nil, tb, "UIPanelCloseButton")
  cb:SetSize(20, 20); cb:SetPoint("RIGHT", -2, 0)
  cb:SetFrameLevel(tb:GetFrameLevel() + 10)
  cb:GetNormalTexture():SetVertexColor(0.8, 0.8, 0.8)
  cb:SetScript("OnEnter", function() cb:GetNormalTexture():SetVertexColor(CYAN[1], CYAN[2], CYAN[3]) end)
  cb:SetScript("OnLeave", function() cb:GetNormalTexture():SetVertexColor(0.8, 0.8, 0.8) end)
  cb:SetScript("OnClick", function() win:Hide() end)

  return win, tb, TH
end

-- ── Session History Window ──────────────────────────────────────────────────
local ROW_H = 52
local histRows = {}

NS.BuildSessionHistoryWindow = function()
  if NS.sessionHistWin then
    NS.sessionHistWin:SetShown(not NS.sessionHistWin:IsShown())
    if NS.sessionHistWin:IsShown() then NS.RefreshSessionHistory() end
    return
  end

  local HW, HH = 400, 500
  local win, tb, TH = MakeDarkWindow("LUISessionHistoryWindow", HW, HH, L["Session History"], "histWinPos")

  -- Clear button in title bar
  local clearBtn = CreateFrame("Button", nil, tb, "BackdropTemplate")
  clearBtn:SetSize(48, 18); clearBtn:SetPoint("RIGHT", -26, 0)
  clearBtn:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
  clearBtn:SetBackdropColor(0.08, 0.08, 0.08, 1); clearBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
  local clbl = clearBtn:CreateFontString(nil, "OVERLAY")
  clbl:SetFont("Fonts/FRIZQT__.TTF", 10, ""); clbl:SetPoint("CENTER")
  clbl:SetTextColor(0.7, 0.7, 0.7); clbl:SetText(L["Clear"])
  clearBtn:SetScript("OnEnter", function() clearBtn:SetBackdropBorderColor(CYAN[1], CYAN[2], CYAN[3], 1) end)
  clearBtn:SetScript("OnLeave", function() clearBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1) end)
  clearBtn:SetScript("OnClick", function()
    LucidUIDB._sessionHistory = {}
    NS.RefreshSessionHistory()
  end)

  -- Scroll frame with clickable rows
  local sf = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 4, -(TH + 3)); sf:SetPoint("BOTTOMRIGHT", -22, 4)
  local sc = CreateFrame("Frame", nil, sf)
  sc:SetWidth(HW - 30)
  sf:SetScrollChild(sc)

  NS.sessionHistWin = win
  table.insert(UISpecialFrames, "LUISessionHistoryWindow")
  NS._histScrollChild = sc
  NS._histScrollFrame = sf

  NS.RefreshSessionHistory()
end

NS.RefreshSessionHistory = function()
  local sc = NS._histScrollChild
  if not sc then return end
  local hex = string.format("%02x%02x%02x",
    math.floor(CYAN[1]*255), math.floor(CYAN[2]*255), math.floor(CYAN[3]*255))

  -- Clear old rows
  for _, row in ipairs(histRows) do row:Hide() end
  wipe(histRows)

  local history = LucidUIDB and LucidUIDB._sessionHistory or {}
  if #history == 0 then
    local emptyRow = CreateFrame("Frame", nil, sc)
    emptyRow:SetSize(1, 30)
    emptyRow:SetPoint("TOPLEFT")
    local emptyLabel = emptyRow:CreateFontString(nil, "OVERLAY")
    emptyLabel:SetFont("Fonts/FRIZQT__.TTF", 11, "")
    emptyLabel:SetPoint("TOPLEFT", 8, -10)
    emptyLabel:SetTextColor(0.4, 0.4, 0.4)
    emptyLabel:SetText(L["No history yet"])
    table.insert(histRows, emptyRow)
    sc:SetHeight(30)
    return
  end

  local yOff = 0

  -- Total gold summary row
  local totalGold = 0
  local totalDuration = 0
  for _, entry in ipairs(history) do
    totalGold = totalGold + (entry.gold or 0)
    totalDuration = totalDuration + (entry.duration or 0)
  end
  local sumRow = CreateFrame("Frame", nil, sc, "BackdropTemplate")
  sumRow:SetHeight(30)
  sumRow:SetPoint("TOPLEFT", sc, "TOPLEFT", 0, yOff)
  sumRow:SetPoint("RIGHT", sc, "RIGHT", 0, 0)
  sumRow:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8"})
  sumRow:SetBackdropColor(0.04, 0.04, 0.04, 1)
  local sumLabel = sumRow:CreateFontString(nil, "OVERLAY")
  sumLabel:SetFont("Fonts/FRIZQT__.TTF", 11, "")
  sumLabel:SetPoint("LEFT", 8, 0)
  local sumStr = "|cff"..hex..">|r |cff909090Total:|r  "..FormatGold(totalGold)
  if totalDuration > 60 and totalGold > 0 then
    local gph = math.floor(totalGold * 3600 / totalDuration)
    sumStr = sumStr.."  |cff666666/hr|r "..FormatGold(gph)
  end
  sumLabel:SetText(sumStr)
  local sumSep = sumRow:CreateTexture(nil, "ARTWORK")
  sumSep:SetHeight(1); sumSep:SetColorTexture(CYAN[1], CYAN[2], CYAN[3], 0.3)
  sumSep:SetPoint("BOTTOMLEFT", 0, 0); sumSep:SetPoint("BOTTOMRIGHT", 0, 0)
  table.insert(histRows, sumRow)
  yOff = yOff - 30

  -- Show newest first
  for i = #history, 1, -1 do
    local e = history[i]
    local idx = i

    local row = CreateFrame("Button", nil, sc, "BackdropTemplate")
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", sc, "TOPLEFT", 0, yOff)
    row:SetPoint("RIGHT", sc, "RIGHT", 0, 0)
    row:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8"})
    row:SetBackdropColor(0.06, 0.06, 0.06, 1)

    -- Hover highlight
    row:SetScript("OnEnter", function()
      row:SetBackdropColor(0.1, 0.1, 0.1, 1)
    end)
    row:SetScript("OnLeave", function()
      row:SetBackdropColor(0.06, 0.06, 0.06, 1)
    end)

    -- Click → open detail
    row:SetScript("OnClick", function()
      NS.ShowSessionDetail(idx)
    end)

    -- Zone name + date
    local zoneTxt = row:CreateFontString(nil, "OVERLAY")
    zoneTxt:SetFont("Fonts/FRIZQT__.TTF", 11, "")
    zoneTxt:SetPoint("TOPLEFT", 8, -4)
    zoneTxt:SetTextColor(1, 1, 1)
    local zoneStr = e.zone or "?"
    if e.diffName then
      local gs = (e.groupSize and e.groupSize > 0) and " ("..e.groupSize..")" or ""
      zoneStr = zoneStr.."  |cff888888"..e.diffName..gs.."|r"
    elseif e.instType then
      local typeLabels = {party="Dungeon", raid="Raid", scenario="Scenario", delves="Delve", pvp="PvP", arena="Arena"}
      local gs = (e.groupSize and e.groupSize > 0) and " ("..e.groupSize..")" or ""
      zoneStr = zoneStr.."  |cff888888"..(typeLabels[e.instType] or e.instType)..gs.."|r"
    end
    zoneTxt:SetText("|cff"..hex..">|r |cffffffff"..zoneStr)

    local dateTxt = row:CreateFontString(nil, "OVERLAY")
    dateTxt:SetFont("Fonts/FRIZQT__.TTF", 9, "")
    dateTxt:SetPoint("TOPRIGHT", -8, -5)
    dateTxt:SetTextColor(0.5, 0.5, 0.5)
    local dur = ""
    if e.duration and e.duration > 0 then dur = FormatTime(e.duration) end
    dateTxt:SetText((e.date or "").."  "..dur)

    -- Stats line: bosses, deaths, items
    local statParts = {}
    local bossCount = 0
    if e.bosses then
      for _, b in ipairs(e.bosses) do bossCount = bossCount + (b.count or 1) end
    end
    if bossCount > 0 then table.insert(statParts, "|cffFFD700"..bossCount.." Boss|r") end
    if e.deaths and e.deaths > 0 then table.insert(statParts, "|cffff4444"..e.deaths.." Deaths|r") end
    if e.wipes and e.wipes > 0 then table.insert(statParts, "|cffff8800"..e.wipes.." Wipes|r") end
    if e.lootCount and e.lootCount > 0 then table.insert(statParts, "|cff00ff00"..e.lootCount.." Items|r") end

    local statTxt = row:CreateFontString(nil, "OVERLAY")
    statTxt:SetFont("Fonts/FRIZQT__.TTF", 10, "")
    statTxt:SetPoint("TOPLEFT", 20, -18)
    statTxt:SetTextColor(0.7, 0.7, 0.7)
    statTxt:SetText(table.concat(statParts, "  "))

    -- Gold line with gold/hr
    local goldTxt = row:CreateFontString(nil, "OVERLAY")
    goldTxt:SetFont("Fonts/FRIZQT__.TTF", 10, "")
    goldTxt:SetPoint("TOPLEFT", 20, -32)
    if e.gold and e.gold > 0 then
      local goldStr = FormatGold(e.gold)
      if e.duration and e.duration > 60 then
        local gph = math.floor(e.gold * 3600 / e.duration)
        goldStr = goldStr.."  |cff666666/hr|r "..FormatGold(gph)
      end
      goldTxt:SetText(goldStr)
    else
      goldTxt:SetText("|cff4444440g|r")
    end

    -- Delete button (bottom right)
    local delBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
    delBtn:SetSize(40, 14); delBtn:SetPoint("BOTTOMRIGHT", -4, 4)
    delBtn:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
    delBtn:SetBackdropColor(0.08, 0.08, 0.08, 1); delBtn:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    delBtn:SetFrameLevel(row:GetFrameLevel() + 5)
    local delLbl = delBtn:CreateFontString(nil, "OVERLAY")
    delLbl:SetFont("Fonts/FRIZQT__.TTF", 8, ""); delLbl:SetPoint("CENTER")
    delLbl:SetTextColor(0.5, 0.5, 0.5); delLbl:SetText(L["Delete"])
    delBtn:SetScript("OnEnter", function()
      delBtn:SetBackdropBorderColor(1, 0.3, 0.3, 1); delLbl:SetTextColor(1, 0.3, 0.3)
    end)
    delBtn:SetScript("OnLeave", function()
      delBtn:SetBackdropBorderColor(0.25, 0.25, 0.25, 1); delLbl:SetTextColor(0.5, 0.5, 0.5)
    end)
    delBtn:SetScript("OnClick", function()
      table.remove(LucidUIDB._sessionHistory, idx)
      NS.RefreshSessionHistory()
    end)

    -- Separator line
    local sep = row:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1); sep:SetColorTexture(0.15, 0.15, 0.15, 1)
    sep:SetPoint("BOTTOMLEFT", 0, 0); sep:SetPoint("BOTTOMRIGHT", 0, 0)

    table.insert(histRows, row)
    yOff = yOff - ROW_H
  end

  sc:SetHeight(math.abs(yOff) + 4)
end

-- ── Session Detail Window (shows full breakdown for one entry) ──────────────
NS.ShowSessionDetail = function(historyIndex)
  local history = LucidUIDB and LucidUIDB._sessionHistory
  if not history or not history[historyIndex] then return end
  local e = history[historyIndex]

  if NS.sessionDetailWin then
    NS.sessionDetailWin:Hide()
    NS.sessionDetailWin = nil
  end

  local DW, DH = 380, 460
  local win, tb, TH = MakeDarkWindow("LUISessionDetailWindow", DW, DH, e.zone or "?", "detailWinPos")

  -- ScrollFrame + EditBox with hyperlink support
  local sf = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 4, -(TH + 3)); sf:SetPoint("BOTTOMRIGHT", -22, 4)

  local eb = CreateFrame("EditBox", nil, sf)
  eb:SetMultiLine(true); eb:SetAutoFocus(false)
  eb:SetFont("Fonts/FRIZQT__.TTF", 11, ""); eb:SetTextColor(1, 1, 1, 1)
  eb:SetWidth(DW - 30); eb:EnableMouse(true); eb:SetHyperlinksEnabled(true)
  eb:SetScript("OnEscapePressed", function() win:Hide() end)
  eb:EnableKeyboard(false)
  eb:SetScript("OnHyperlinkEnter", function(self, link)
    local lt = link:match("^(.-):") or ""
    if NS.validLinks and NS.validLinks[lt] then
      GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
      GameTooltip:SetHyperlink(link); GameTooltip:Show()
    end
  end)
  eb:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
  eb:SetScript("OnHyperlinkClick", function(_, link, text, btn)
    if IsShiftKeyDown() then
      local chatEB2 = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
      if chatEB2 then chatEB2:Insert(text) end
    else
      SetItemRef(link, text, btn)
    end
  end)
  sf:SetScrollChild(eb)

  NS.sessionDetailWin = win
  table.insert(UISpecialFrames, "LUISessionDetailWindow")

  local hex = string.format("%02x%02x%02x",
    math.floor(CYAN[1]*255), math.floor(CYAN[2]*255), math.floor(CYAN[3]*255))
  local function hdr(text)
    return "|cff"..hex..">|r |cff909090"..text.."|r"
  end
  local DIV = "|cff2a2a2a"..string.rep("-", 46).."|r"

  -- Build lines top-to-bottom, then add in reverse (SMF adds bottom-up)
  local lines = {}

  -- Header info
  table.insert(lines, "|cffffffff"..(e.zone or "?").."|r")
  local infoLine = "|cff888888"..e.date
  local dur2 = e.duration and FormatTime(e.duration) or "?"
  infoLine = infoLine.."  ("..dur2..")"
  if e.diffName then
    infoLine = infoLine.."  "..e.diffName
    if e.groupSize and e.groupSize > 0 then
      infoLine = infoLine.." ("..e.groupSize..")"
    end
  elseif e.instType then
    local typeLabels = {party="Dungeon", raid="Raid", scenario="Scenario", delves="Delve", pvp="PvP", arena="Arena"}
    infoLine = infoLine.."  "..(typeLabels[e.instType] or e.instType)
    if e.groupSize and e.groupSize > 0 then
      infoLine = infoLine.." ("..e.groupSize..")"
    end
  end
  infoLine = infoLine.."|r"
  table.insert(lines, infoLine)
  table.insert(lines, " ")

  -- Gold summary
  table.insert(lines, hdr("Gold"))
  table.insert(lines, DIV)
  if e.gold and e.gold > 0 then
    local goldStr = FormatGold(e.gold)
    if e.duration and e.duration > 60 then
      local gph = math.floor(e.gold * 3600 / e.duration)
      goldStr = goldStr.."  |cff666666/hr|r "..FormatGold(gph)
    end
    table.insert(lines, goldStr)
  else
    table.insert(lines, "|cff4444440g|r")
  end
  table.insert(lines, " ")

  -- Bosses
  table.insert(lines, hdr("Bosses"))
  table.insert(lines, DIV)
  if e.bosses and #e.bosses > 0 then
    for _, b in ipairs(e.bosses) do
      local bname = type(b) == "table" and b.name or b
      local bcount = type(b) == "table" and b.count or 1
      local suffix = bcount > 1 and ("  |cff888888x"..bcount.."|r") or ""
      table.insert(lines, "|cff"..hex.."+|r |cffFFD700"..bname.."|r"..suffix)
    end
  else
    table.insert(lines, "|cff444444None|r")
  end
  table.insert(lines, " ")

  -- Deaths + Wipes
  table.insert(lines, hdr("Deaths"))
  table.insert(lines, DIV)
  local deathLine = "|cffff4444"..(e.deaths or 0).." Deaths|r"
  if e.wipes and e.wipes > 0 then
    deathLine = deathLine.."  |cffff8800"..e.wipes.." Wipes|r"
  end
  table.insert(lines, deathLine)
  table.insert(lines, " ")

  -- Loot items with links (grouped by name with count)
  table.insert(lines, hdr("Looted Items ("..(e.lootCount or 0)..")"))
  table.insert(lines, DIV)
  if e.items and #e.items > 0 then
    local sorted = {}
    for _, item in ipairs(e.items) do table.insert(sorted, item) end
    table.sort(sorted, function(a, b)
      if (a.quality or 0) ~= (b.quality or 0) then return (a.quality or 0) > (b.quality or 0) end
      return (a.name or "") < (b.name or "")
    end)
    for _, item in ipairs(sorted) do
      local countStr = item.count > 1 and (" |cff888888x"..item.count.."|r") or ""
      -- Use item link if available (enables tooltip on hover)
      local display = item.link or item.name or "?"
      table.insert(lines, display..countStr)
    end
  else
    table.insert(lines, "|cff444444None|r")
  end

  eb:SetText(table.concat(lines, "\n"))
  eb:SetCursorPosition(0)
  win:Show()
end
