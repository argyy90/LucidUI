-- LucidUI LootTracker.lua
-- Main window (BuildWindow), event registration, slash commands.
-- All shared state lives in LucidUINS (NS).

local ADDON_NAME = "LucidUI"
local NS   = LucidUINS
local CYAN = NS.CYAN

local function BuildWindow()
  local DB    = NS.DB
  local DBSet = NS.DBSet
  local L     = LucidUIL
  NS.win = CreateFrame("Frame", "LucidUIWindow", UIParent, "BackdropTemplate")
  local savedSize = DB("size")
  local sw, sh = savedSize[1], savedSize[2]
  if sh and sh < 50 then sh = NS.DB_DEFAULTS.size[2] end
  NS.win:SetSize(sw, sh)
  NS.win:SetPoint(unpack(DB("position")))
  NS.win:SetFrameStrata("MEDIUM")
  NS.win:SetToplevel(true)
  NS.win:SetMovable(true)
  NS.win:SetResizable(true)
  NS.win:SetResizeBounds(220, 120)
  NS.win:SetClampedToScreen(true)
  NS.win:EnableMouse(true)
  NS.win:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8",edgeFile="Interface/Buttons/WHITE8X8",edgeSize=1})
  NS.win:RegisterForDrag("LeftButton")
  NS.win:SetScript("OnDragStart", function(self)
    if not self.collapsed and not self.locked then self:StartMoving() end
  end)
  NS.win:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing(); NS.SavePosition()
  end)
  NS.win:SetScript("OnSizeChanged", NS.SaveSize)

  -- Title bar
  NS.titleBar = CreateFrame("Frame", nil, NS.win)
  NS.titleBar:SetPoint("TOPLEFT"); NS.titleBar:SetPoint("TOPRIGHT"); NS.titleBar:SetHeight(22)
  NS.titleTex = NS.titleBar:CreateTexture(nil, "BACKGROUND")
  NS.titleTex:SetAllPoints()
  NS.titleTex:SetColorTexture(0.06, 0.06, 0.06, 1.0)
  NS.titleText = NS.titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  NS.titleText:SetFont("Fonts/FRIZQT__.TTF", 15)
  NS.titleText:SetPoint("LEFT", 6, 0)
  NS.titleText:SetTextColor(1, 1, 1, 1)
  NS.titleText:SetText("Loot Tracker")

  -- Accent line under title bar
  local accentLine = NS.win:CreateTexture(nil, "ARTWORK")
  accentLine:SetHeight(1)
  accentLine:SetPoint("TOPLEFT", NS.titleBar, "BOTTOMLEFT", 0, 0)
  accentLine:SetPoint("TOPRIGHT", NS.titleBar, "BOTTOMRIGHT", 0, 0)
  accentLine:SetColorTexture(CYAN[1], CYAN[2], CYAN[3], 0.6)
  NS.win._accentLine = accentLine

  local function UpdateTitleBrackets(themeKey)
    local t = NS.GetTheme(themeKey)
    local tid = t.tilders or {59/255, 210/255, 237/255, 1}
    local hex = string.format("%02x%02x%02x",
      math.floor(tid[1]*255), math.floor(tid[2]*255), math.floor(tid[3]*255))
    local tname = DB("titleName") or ""
    local f, r = tname:match("^(%S+)%s*(.*)")
    if f then
      NS.titleText:SetText("|cff"..hex..f.."|r"..(r ~= "" and (" |cffffffff"..r.."|r") or ""))
    else
      NS.titleText:SetText("|cff"..hex..tname.."|r")
    end
  end
  UpdateTitleBrackets(DB("theme"))

  -- Collapse button
  NS.collapseBtn = CreateFrame("Button", nil, NS.win)
  NS.collapseBtn:SetSize(20, 20); NS.collapseBtn:SetPoint("TOPRIGHT", -2, -1)
  NS.collapseBtn:SetFrameStrata("HIGH")
  local collapseTex = NS.collapseBtn:CreateTexture(nil, "ARTWORK")
  collapseTex:SetTexture("Interface/AddOns/LucidUI/Assets/ScrollToBottom.png")
  collapseTex:SetSize(14, 14); collapseTex:SetPoint("CENTER")
  table.insert(NS.btnIconTextures, collapseTex)
  NS.win.collapsed = false; NS.win.expandedHeight = nil
  NS.collapseBtn:SetScript("OnClick", function()
    if not NS.win.collapsed then
      NS.win.expandedHeight = NS.win:GetHeight(); NS.win.collapsed = true
      collapseTex:SetTexCoord(0,1,1,0); NS.win.msgWrapper:Hide(); NS.resizeWidget:Hide(); NS.win:SetHeight(24)
    else
      NS.win.collapsed = false; collapseTex:SetTexCoord(0,1,0,1)
      NS.win.msgWrapper:Show()
      -- Only show resize widget if window is NOT locked
      if not NS.win.locked then NS.resizeWidget:Show() end
      if NS.win.expandedHeight then NS.win:SetHeight(NS.win.expandedHeight) end
    end
  end)
  NS.collapseBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(NS.collapseBtn,"ANCHOR_LEFT")
    GameTooltip:SetText(NS.win.collapsed and L["Expand"] or L["Collapse"]); GameTooltip:Show()
  end)
  NS.collapseBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- Lock button
  local lockBtn = CreateFrame("Button", nil, NS.win)
  lockBtn:SetSize(20,20); lockBtn:SetPoint("TOPRIGHT", NS.collapseBtn, "TOPLEFT", -2, 0)
  lockBtn:SetFrameStrata("HIGH")
  local lockTex = lockBtn:CreateTexture(nil, "ARTWORK")
  lockTex:SetSize(12,14); lockTex:SetPoint("CENTER")
  lockTex:SetTexture("Interface/AddOns/LucidUI/Assets/Lock.png")
  NS.lockTexRef = lockTex
  NS.win.locked = false
  if DB("locked") then
    NS.win.locked = true; NS.win:SetMovable(false); NS.win:SetResizable(false)
  end
  lockBtn:SetScript("OnClick", function()
    local ok, err = pcall(function()
      NS.win.locked = not NS.win.locked
      if NS.win.locked then
        NS.win:SetMovable(false); NS.win:SetResizable(false); NS.resizeWidget:Hide()
        local t = NS.GetTheme(DB("theme")); local bc = t.btnColor or {0.8,0.8,0.8}
        lockTex:SetVertexColor(bc[1], bc[2], bc[3], 0.9)
        DBSet("locked", true)
      else
        NS.win:SetMovable(true); NS.win:SetResizable(true); NS.resizeWidget:Show()
        lockTex:SetVertexColor(CYAN[1], CYAN[2], CYAN[3], 1.0)
        DBSet("locked", false)
      end
    end)
    if not ok then geterrorhandler()(err) end
  end)
  lockBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(lockBtn,"ANCHOR_LEFT")
    GameTooltip:SetText(NS.win.locked and L["Unlock Window"] or L["Lock Window"]); GameTooltip:Show()
  end)
  lockBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  NS.lockBtnRef = lockBtn

  -- Clear button
  local clearBtn = CreateFrame("Button", nil, NS.win)
  clearBtn:SetSize(34,20); clearBtn:SetPoint("TOPRIGHT", lockBtn, "TOPLEFT", -2, 0)
  clearBtn:SetFrameStrata("HIGH")
  local clearTxt = clearBtn:CreateFontString(nil, "ARTWORK")
  clearTxt:SetFont("Fonts/FRIZQT__.TTF", 10, ""); clearTxt:SetPoint("CENTER")
  clearTxt:SetText(L["Clear"])
  NS.clearTxtRef = clearTxt
  clearBtn:SetScript("OnClick", function()
    if NS.smf then NS.smf:Clear() end
    wipe(NS.lines); wipe(NS.rawEntries)
    if LucidUIDB then LucidUIDB.history = {} end
  end)
  clearBtn:SetScript("OnEnter", function()
    clearTxt:SetTextColor(NS.CYAN[1], NS.CYAN[2], NS.CYAN[3], 1)
    GameTooltip:SetOwner(clearBtn,"ANCHOR_LEFT"); GameTooltip:SetText(L["Clear"]); GameTooltip:Show()
  end)
  clearBtn:SetScript("OnLeave", function()
    -- Restore to icon color — reuse the same logic as ApplyTheme
    local ic = NS.DB("chatIconColor")
    local r, g, b
    if ic and type(ic) == "table" and ic.r then
      r, g, b = ic.r, ic.g, ic.b
    else
      local bc = NS.GetTheme(NS.DB("theme")).btnColor or {1,1,1,1}
      r, g, b = bc[1], bc[2], bc[3]
    end
    clearTxt:SetTextColor(r, g, b, 1)
    GameTooltip:Hide()
  end)

  -- Message wrapper
  local msgWrapper = CreateFrame("Frame", nil, NS.win)
  msgWrapper:SetPoint("TOPLEFT", 0, -22)
  msgWrapper:SetPoint("BOTTOMRIGHT", 0, 0)
  NS.win.msgWrapper = msgWrapper

  -- SMF: created programmatically (no longer needs HyperlinkHandler.xml).
  -- HyperlinkHandler.xml used to define LucidUIHyperlinkHandler; we create the
  -- same frame here so the XML can be removed from the TOC entirely.
  NS.smf = CreateFrame("ScrollingMessageFrame", "LucidUIHyperlinkHandler", msgWrapper)
  NS.smf:SetPoint("TOPLEFT",     msgWrapper, "TOPLEFT",     4, -4)
  NS.smf:SetPoint("BOTTOMRIGHT", msgWrapper, "BOTTOMRIGHT", -4,  4)
  NS.smf:SetMaxLines(DB("maxLines") or NS.MAX_LINES)
  NS.smf:SetJustifyH("LEFT")
  NS.smf:SetInsertMode(SCROLLING_MESSAGE_FRAME_INSERT_MODE_BOTTOM)
  NS.smf:SetFading(false)
  NS.smf:SetHyperlinksEnabled(true)
  NS.smf:EnableMouseWheel(true)
  NS.smf:Show()

  NS.smf:SetScript("OnMouseWheel", function(self, delta)
    if delta > 0 then self:ScrollUp() else self:ScrollDown() end
    NS.UpdateScrollBtn()
  end)

  -- Scroll-to-bottom button (only visible when scrolled up)
  local scrollBtn = CreateFrame("Button", nil, msgWrapper)
  scrollBtn:SetSize(20, 20)
  scrollBtn:SetPoint("TOPRIGHT", msgWrapper, "TOPRIGHT", -4, -4)
  scrollBtn:SetFrameLevel(NS.smf:GetFrameLevel() + 5)
  scrollBtn:Hide()
  local scrollBtnTex = scrollBtn:CreateTexture(nil, "ARTWORK")
  scrollBtnTex:SetTexture("Interface/AddOns/LucidUI/Assets/ScrollToBottom.png")
  scrollBtnTex:SetAllPoints()
  scrollBtnTex:SetVertexColor(CYAN[1], CYAN[2], CYAN[3], 0.85)
  scrollBtn:SetScript("OnEnter", function()
    scrollBtnTex:SetVertexColor(1, 1, 1, 1)
    GameTooltip:SetOwner(scrollBtn, "ANCHOR_LEFT")
    GameTooltip:SetText(L["Jump to latest"]); GameTooltip:Show()
  end)
  scrollBtn:SetScript("OnLeave", function()
    scrollBtnTex:SetVertexColor(CYAN[1], CYAN[2], CYAN[3], 0.85)
    GameTooltip:Hide()
  end)
  scrollBtn:SetScript("OnClick", function()
    NS.smf:ScrollToBottom()
    NS.UpdateScrollBtn()
  end)
  NS.UpdateScrollBtn = function()
    if NS.smf:GetScrollOffset() > 0 then
      scrollBtn:Show()
    else
      scrollBtn:Hide()
    end
  end
  NS.smf:SetScript("OnHyperlinkEnter", function(self, link)
    local lt = link:match("^(.-):")  or ""
    if NS.validLinks[lt] then
      GameTooltip:SetOwner(self,"ANCHOR_CURSOR_RIGHT")
      GameTooltip:SetHyperlink(link); GameTooltip:Show()
    end
  end)
  NS.smf:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
  NS.smf:SetScript("OnHyperlinkClick", function(_, link, text, btn)
    if IsShiftKeyDown() then
      local eb = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
      if eb then eb:Insert(text) end
    else
      SetItemRef(link, text, btn)
    end
  end)
  NS.smf:SetScript("OnEnter", function(self)
    if self.SetFadeOffset then self:SetFadeOffset(GetTime()) end
  end)

  -- Resize widget
  NS.resizeWidget = CreateFrame("Frame", nil, NS.win)
  NS.resizeWidget:SetSize(28,28); NS.resizeWidget:SetPoint("BOTTOMRIGHT",0,0)
  NS.resizeWidget:SetFrameLevel(NS.win:GetFrameLevel()+10)
  NS.resizeWidget:EnableMouse(true)
  NS.resizeWidget:SetScript("OnMouseDown", function(_,btn)
    if btn=="LeftButton" then NS.win:StartSizing("BOTTOMRIGHT") end
  end)
  NS.resizeWidget:SetScript("OnMouseUp", function() NS.win:StopMovingOrSizing(); NS.SaveSize() end)
  local rTex = NS.resizeWidget:CreateTexture(nil,"OVERLAY")
  rTex:SetTexture("Interface/AddOns/LucidUI/Assets/resize.png")
  rTex:SetTexCoord(0,0,0,1,1,0,1,1); rTex:SetAllPoints()
  rTex:SetVertexColor(0.8,0.8,0.8,0.8)
  NS.resizeWidget:SetScript("OnEnter", function() rTex:SetVertexColor(CYAN[1],CYAN[2],CYAN[3],1.0) end)
  NS.resizeWidget:SetScript("OnLeave", function() rTex:SetVertexColor(0.8,0.8,0.8,0.8) end)

  -- Restore lock visuals
  local lockTheme = NS.GetTheme(DB("theme"))
  if NS.win.locked then
    NS.resizeWidget:Hide()
    local bc = lockTheme.btnColor or {0.8,0.8,0.8}
    lockTex:SetVertexColor(bc[1],bc[2],bc[3],0.9)
  else
    lockTex:SetVertexColor(CYAN[1],CYAN[2],CYAN[3],1.0)
  end

  NS.ApplyTheme(DB("theme"))
  -- ApplyAlpha and ApplyTitleAlpha are called internally by ApplyTheme; no need to repeat them.
  NS.ApplyFontSize()
  NS.ApplySpacing()
  NS.ApplyFade()
  NS.ApplyToolbarVisibility()
end

NS.ApplyToolbarVisibility = function()
  -- Titlebar only has collapse, lock, and clear now — nothing to toggle
end

-- ============================================================
-- Events
-- ============================================================
local eventFrame = CreateFrame("Frame")
-- Core events always needed for addon initialization
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

-- Loot-specific events registered conditionally after DB is available
local function RegisterLootEvents()
  local lootActive = NS.DB("lootOwnWindow") or NS.DB("lootInChatTab")
  if lootActive then
    eventFrame:RegisterEvent("CHAT_MSG_LOOT")
    eventFrame:RegisterEvent("CHAT_MSG_MONEY")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    eventFrame:RegisterEvent("ENCOUNTER_END")
    eventFrame:RegisterEvent("PLAYER_DEAD")
    eventFrame:RegisterEvent("PLAYER_MONEY")
  else
    eventFrame:UnregisterEvent("CHAT_MSG_LOOT")
    eventFrame:UnregisterEvent("CHAT_MSG_MONEY")
    eventFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:UnregisterEvent("ZONE_CHANGED_NEW_AREA")
    eventFrame:UnregisterEvent("ENCOUNTER_END")
    eventFrame:UnregisterEvent("PLAYER_DEAD")
    eventFrame:UnregisterEvent("PLAYER_MONEY")
  end
end
NS.RegisterLootEvents = RegisterLootEvents

eventFrame:SetScript("OnEvent", function(_, ev, msg, sender, ...)
  local DB = NS.DB
  local L  = LucidUIL
  if ev == "ADDON_LOADED" and msg:lower() == ADDON_NAME:lower() then
    LucidUIDB = LucidUIDB or {}
    -- Migrate: move stale _profiles["Default"] to _defaultSnapshot
    if LucidUIDB._profiles and LucidUIDB._profiles["Default"] then
      if not LucidUIDB._defaultSnapshot then
        LucidUIDB._defaultSnapshot = LucidUIDB._profiles["Default"]
      end
      LucidUIDB._profiles["Default"] = nil
    end
    -- Apply active profile on load (only when profile actually changed)
    local activeProfile = LucidUIDB._activeProfile or "Default"
    if activeProfile ~= LucidUIDB._lastAppliedProfile then
      local profileData
      if activeProfile == "Default" then
        profileData = LucidUIDB._defaultSnapshot
      else
        local profiles = LucidUIDB._profiles
        profileData = profiles and profiles[activeProfile]
      end
      if profileData then
        local skip = {_profiles=true, _activeProfile=true, _defaultSnapshot=true, _lastAppliedProfile=true, history=true, chatHistory=true, debugHistory=true, _sessionData=true, _rollData=true, _rollEncounter=true}
        for k in pairs(LucidUIDB) do
          if not skip[k] then LucidUIDB[k] = nil end
        end
        for k, v in pairs(profileData) do
          if not skip[k] then LucidUIDB[k] = v end
        end
      end
      LucidUIDB._lastAppliedProfile = activeProfile
    end
    -- Locales.lua handles language via GetLocale() at load time
    -- Restore custom accent color from DB before building any windows
    if LucidUIDB.theme == "custom" and LucidUIDB.customTilders then
      local ct = LucidUIDB.customTilders
      if ct[1] then
        NS.CYAN[1], NS.CYAN[2], NS.CYAN[3] = ct[1], ct[2], ct[3]
        NS.DARK_THEME.tilders = {ct[1], ct[2], ct[3], 1}
      end
    end
    BuildWindow()
  elseif ev == "PLAYER_LOGIN" then
    if not NS.win then LucidUIDB = LucidUIDB or {}; BuildWindow() end
    local pn, pr = UnitFullName("player")
    NS.characterFullName = (pn and pr) and (pn.."-"..pr) or (pn or UnitName("player"))
    -- Clear history is now handled in PLAYER_ENTERING_WORLD (has isInitialLogin/isReloadingUi)
    NS.LoadHistory()
    -- Register loot events only if loot tracking is enabled
    RegisterLootEvents()
    -- Only show loot window if "own window" mode is enabled
    if NS.win then
      NS.win:SetShown(DB("lootOwnWindow") == true)
    end

    -- WoW version check
    local ADDON_TOC = 120001
    local _, _, _, gameTOC = GetBuildInfo()
    if gameTOC and gameTOC > ADDON_TOC then
      local gameVer  = string.format("%d.%d.%d", math.floor(gameTOC/10000), math.floor((gameTOC%10000)/100), gameTOC%100)
      local addonVer = string.format("%d.%d.%d", math.floor(ADDON_TOC/10000), math.floor((ADDON_TOC%10000)/100), ADDON_TOC%100)
      C_Timer.After(3, function()
        print("[|cff3bd2edLucid|r|cffffffffUI|r] |cffff9900New WoW version detected!|r"
          .." Built for |cffffffff"..addonVer.." ("..ADDON_TOC..")|r"
          ..", running on |cff00ff00"..gameVer.." ("..gameTOC..")|r"
          .." - some features may not work correctly.")
      end)
    end
  elseif ev == "CHAT_MSG_LOOT" then
    local sGUID = select(11, sender, ...)
    NS.OnLoot(msg, sender, sGUID)
  elseif ev == "CHAT_MSG_MONEY" then
    NS.OnMoney(msg)
  elseif ev == "PLAYER_ENTERING_WORLD" then
    local isInitialLogin, isReloadingUi = msg, sender
    -- Clear loot history based on setting
    if LucidUIDB then
      local shouldClear = false
      if DB("clearOnLogin") and isInitialLogin and not isReloadingUi then
        shouldClear = true
      elseif DB("clearOnReload") and isReloadingUi then
        shouldClear = true
      end
      if shouldClear then
        LucidUIDB.history = {}
        LucidUIDB._rollData = nil; LucidUIDB._rollEncounter = nil
        NS.rollSessions = {}; NS.currentEncounterName = nil
        if NS.smf then NS.smf:Clear() end
        wipe(NS.lines); wipe(NS.rawEntries)
      end
    end
    if NS.StatsOnEnteringWorld then NS.StatsOnEnteringWorld() end
  elseif ev == "ZONE_CHANGED_NEW_AREA" then
    if NS.StatsOnZoneChanged then NS.StatsOnZoneChanged() end
  elseif ev == "ENCOUNTER_END" then
    if NS.StatsOnEncounterEnd then NS.StatsOnEncounterEnd(msg, sender, ...) end
  elseif ev == "PLAYER_DEAD" then
    if NS.StatsOnPlayerDead then NS.StatsOnPlayerDead() end
  elseif ev == "PLAYER_MONEY" then
    if NS.StatsOnMoney then NS.StatsOnMoney() end
  end
end)

-- ============================================================
-- Slash commands
-- ============================================================
SlashCmdList["LUCIDUI"] = function(input)
  input = (input or ""):lower():match("^%s*(.-)%s*$")
  if input == "reset" then
    LucidUIDB = {}
    ReloadUI()
  elseif input == "install" then
    if NS.ShowInstallWizard then NS.ShowInstallWizard() end
  else
    if NS.BuildChatOptionsWindow then NS.BuildChatOptionsWindow() end
  end
end
SLASH_LUCIDUI1 = "/lucid"
SLASH_LUCIDUI2 = "/lui"
SLASH_LUCIDUI3 = "/lu"