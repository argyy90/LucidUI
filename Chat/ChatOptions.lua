-- LucidUI ChatOptions.lua
-- Settings dialog with 7 tabs matching the reference layout.
-- Display | Appearance | Text | Advanced | Chat Colors | Loot | QoL

local NS   = LucidUINS
local L    = LucidUIL
local DB, DBSet = NS.DB, NS.DBSet

local chatOptWin = nil

-- Reload popup
StaticPopupDialogs["LUCIDUI_CHAT_RELOAD"] = {
  text = "Reload UI to apply changes?",
  button1 = ACCEPT, button2 = CANCEL,
  OnAccept = function() ReloadUI() end,
  timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- ══════════════════════════════════════════════════════════════════════
-- TAB 1: Display
-- ══════════════════════════════════════════════════════════════════════
local function SetupDisplay(parent)
  local container = CreateFrame("Frame", nil, parent)
  local allFrames = {}

  -- Timestamp format dropdown
  local timestampDD = NS.ChatGetDropdown(container, "Timestamp",
    function(value)
      if value == "none" then return DB("chatTimestamps") == false end
      return DB("chatTimestamps") ~= false and DB("chatTimestampFormat") == value
    end,
    function(value)
      if value == "none" then
        DBSet("chatTimestamps", false)
      else
        DBSet("chatTimestamps", true)
        DBSet("chatTimestampFormat", value)
      end
      -- Recompute timestamp column width in chat display
      if NS.chatDisplay and NS.chatDisplay.RecomputeTimestampWidth then
        NS.chatDisplay:RecomputeTimestampWidth()
      end
      if NS.chatRedraw then NS.chatRedraw() end
      -- Also update LucidUI window
      if NS.RedrawMessages then NS.RedrawMessages() end
    end)
  timestampDD:SetPoint("TOP")
  timestampDD:Init(
    {"None", "HH:MM", "HH:MM:SS", "HH:MM AM/PM", "HH:MM:SS AM/PM"},
    {"none", "%H:%M", "%X", "%I:%M %p", "%I:%M:%S %p"})
  table.insert(allFrames, timestampDD)

  local showSep = NS.ChatGetCheckbox(container, "Show vertical separator", 28, function(state)
    DBSet("chatShowSeparator", state)
    if NS.chatRedraw then NS.chatRedraw() end
    -- Also redraw LucidUI window
    if NS.RedrawMessages then NS.RedrawMessages() end
  end, "Show a separator line between timestamp and message")
  showSep.option = "chatShowSeparator"
  showSep:SetPoint("TOP", allFrames[#allFrames], "BOTTOM", 0, 0)
  table.insert(allFrames, showSep)

  local showTabSep = NS.ChatGetCheckbox(container, "Show tab separator", 28, function(state)
    DBSet("chatTabSeparator", state)
    -- Refresh tab buttons to show/hide accent lines
    if NS.chatRefreshTabs then NS.chatRefreshTabs() end
  end, "Show accent line on left edge of chat tabs")
  showTabSep.option = "chatTabSeparator"
  showTabSep:SetPoint("TOP", allFrames[#allFrames], "BOTTOM", 0, 0)
  table.insert(allFrames, showTabSep)

  -- Combat Log
  local combatLogCB = NS.ChatGetCheckbox(container, "Combat Log", 28, function(state)
    DBSet("chatCombatLog", state)
    if state then
      if NS.EnsureCombatLogTab then NS.EnsureCombatLogTab() end
    else
      if NS.RemoveCombatLogTab then NS.RemoveCombatLogTab() end
    end
  end, "Show a Combat Log tab embedding WoW's native combat log")
  combatLogCB.option = "chatCombatLog"
  combatLogCB:SetPoint("TOP", allFrames[#allFrames], "BOTTOM", 0, 0)
  table.insert(allFrames, combatLogCB)

  -- Channel shortening
  local shortenDD = NS.ChatGetDropdown(container, "Short", function(value)
    return (DB("chatShortenFormat") or "none") == value
  end, function(value) DBSet("chatShortenFormat", value) end)
  shortenDD:SetPoint("TOP", allFrames[#allFrames], "BOTTOM", 0, -10)
  shortenDD:Init(
    {"Full  \226\128\148  [1. General]  (Say)",
     "Short  \226\128\148  (1)  (S)  (P)  (G)",
     "Minimal  \226\128\148  1  S  P  G"},
    {"none", "bracket", "minimal"})
  table.insert(allFrames, shortenDD)

  -- Flash tabs on
  local flashDD = NS.ChatGetDropdown(container, "Flash tabs on", function(value)
    return (DB("chatTabFlash") or "all") == value
  end, function(value) DBSet("chatTabFlash", value) end)
  flashDD:SetPoint("TOP", allFrames[#allFrames], "BOTTOM", 0, -10)
  flashDD:Init({"Never", "All messages", "Whispers only"}, {"never", "all", "whisper"})
  table.insert(allFrames, flashDD)

  local whisperTab = NS.ChatGetCheckbox(container, "New whispers open new tab", 28, function(state)
    DBSet("chatWhisperTab", state)
  end, "Open a new tab when a whisper arrives")
  whisperTab.option = "chatWhisperTab"
  whisperTab:SetPoint("TOP", allFrames[#allFrames], "BOTTOM", 0, 0)
  table.insert(allFrames, whisperTab)

  local storeMsg = NS.ChatGetCheckbox(container, "Store messages", 28, function(state)
    DBSet("chatStoreMessages", state)
  end, "Remember chat messages between sessions")
  storeMsg.option = "chatStoreMessages"
  storeMsg:SetPoint("TOP", allFrames[#allFrames], "BOTTOM", 0, -10)
  table.insert(allFrames, storeMsg)

  local removeOld = NS.ChatGetCheckbox(container, "Remove old messages", 28, function(state)
    DBSet("chatRemoveOldMessages", state)
  end, "Delete the oldest stored messages when the limit is reached")
  removeOld.option = "chatRemoveOldMessages"
  removeOld:SetPoint("TOP", allFrames[#allFrames], "BOTTOM", 0, 0)
  table.insert(allFrames, removeOld)

  local minimapBtn = NS.ChatGetCheckbox(container, "Show minimap button", 28, function(state)
    DBSet("chatShowMinimap", state)
    if NS.UpdateMinimapButton then NS.UpdateMinimapButton() end
  end, "Show a minimap icon for quick access")
  minimapBtn.option = "chatShowMinimap"
  minimapBtn:SetPoint("TOP", allFrames[#allFrames], "BOTTOM", 0, -10)
  table.insert(allFrames, minimapBtn)

  -- ── Enable Custom Chat (red, bottom of Display tab) ────────────────
  do
    local holder = CreateFrame("Frame", nil, container)
    holder:SetHeight(22)
    holder:SetPoint("LEFT", container, "LEFT", 30, 0)
    holder:SetPoint("RIGHT", container, "RIGHT", -15, 0)
    holder:SetPoint("TOP", allFrames[#allFrames], "BOTTOM", 0, -16)

    local btn = CreateFrame("Button", nil, holder)
    btn:SetSize(13, 13); btn:SetPoint("LEFT", 20, 0)

    local border = btn:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints(); border:SetColorTexture(0.28, 0.28, 0.28, 1)

    local fill = btn:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 2, -2); fill:SetPoint("BOTTOMRIGHT", -2, 2)
    fill:SetColorTexture(0.9, 0.25, 0.25, 1)
    fill:SetShown(DB("chatEnabled") ~= false)

    local lbl = holder:CreateFontString(nil, "OVERLAY")
    lbl:SetFont("Fonts/FRIZQT__.TTF", 11, "")
    lbl:SetPoint("LEFT", btn, "RIGHT", 6, 0)
    lbl:SetTextColor(0.9, 0.3, 0.3, 1)
    lbl:SetText(L["Enable Custom Chat"])

    function holder:SetValue(value)
      fill:SetShown(value and true or false)
    end
    holder.option = "chatEnabled"

    local hit = CreateFrame("Frame", nil, holder)
    hit:SetAllPoints(holder); hit:EnableMouse(true)
    hit:SetFrameLevel(btn:GetFrameLevel() + 3)
    hit:SetScript("OnMouseDown", function()
      local newVal = not (DB("chatEnabled") ~= false)
      DBSet("chatEnabled", newVal)
      fill:SetShown(newVal)
      -- Reload dialog
      local dlg = CreateFrame("Frame", "LucidUIChatReloadDlg", UIParent, "BackdropTemplate")
      dlg:SetSize(320, 110); dlg:SetPoint("CENTER")
      dlg:SetFrameStrata("FULLSCREEN_DIALOG"); dlg:SetToplevel(true)
      dlg:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
      dlg:SetBackdropColor(0.03,0.03,0.03,0.97)
      dlg:SetBackdropBorderColor(0.9,0.25,0.25,1)
      local tb = CreateFrame("Frame", nil, dlg, "BackdropTemplate")
      tb:SetHeight(26); tb:SetPoint("TOPLEFT",1,-1); tb:SetPoint("TOPRIGHT",-1,-1)
      tb:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8"}); tb:SetBackdropColor(0.06,0.06,0.06,1)
      local ttxt = tb:CreateFontString(nil,"OVERLAY")
      ttxt:SetFont("Fonts/FRIZQT__.TTF",12,""); ttxt:SetPoint("LEFT",10,0)
      ttxt:SetTextColor(1,1,1,1); ttxt:SetText("LucidUI")
      local msg = dlg:CreateFontString(nil,"OVERLAY")
      msg:SetFont("Fonts/FRIZQT__.TTF",11,""); msg:SetPoint("TOP",0,-38)
      msg:SetTextColor(0.9,0.9,0.9,1); msg:SetText(L["chat_reload_msg"])
      local bw = 120
      local reloadBtn = CreateFrame("Button", nil, dlg, "BackdropTemplate")
      reloadBtn:SetSize(bw, 24); reloadBtn:SetPoint("BOTTOMRIGHT", dlg, "BOTTOM", -4, 10)
      reloadBtn:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8",edgeFile="Interface/Buttons/WHITE8X8",edgeSize=1})
      reloadBtn:SetBackdropColor(0.04,0.12,0.04,1); reloadBtn:SetBackdropBorderColor(0.2,0.6,0.2,1)
      local rl = reloadBtn:CreateFontString(nil,"OVERLAY")
      rl:SetFont("Fonts/FRIZQT__.TTF",12,""); rl:SetPoint("CENTER")
      rl:SetTextColor(0.3,1,0.3,1); rl:SetText(L["Reload UI"])
      reloadBtn:SetScript("OnClick", function() dlg:Hide(); ReloadUI() end)
      reloadBtn:SetScript("OnEnter", function() reloadBtn:SetBackdropBorderColor(0.9,0.25,0.25,1) end)
      reloadBtn:SetScript("OnLeave", function() reloadBtn:SetBackdropBorderColor(0.2,0.6,0.2,1) end)
      local cancelBtn = CreateFrame("Button", nil, dlg, "BackdropTemplate")
      cancelBtn:SetSize(bw, 24); cancelBtn:SetPoint("BOTTOMLEFT", dlg, "BOTTOM", 4, 10)
      cancelBtn:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8",edgeFile="Interface/Buttons/WHITE8X8",edgeSize=1})
      cancelBtn:SetBackdropColor(0.12,0.04,0.04,1); cancelBtn:SetBackdropBorderColor(0.5,0.15,0.15,1)
      local cl = cancelBtn:CreateFontString(nil,"OVERLAY")
      cl:SetFont("Fonts/FRIZQT__.TTF",12,""); cl:SetPoint("CENTER")
      cl:SetTextColor(0.9,0.35,0.35,1); cl:SetText(L["Cancel"])
      cancelBtn:SetScript("OnClick", function() dlg:Hide() end)
      cancelBtn:SetScript("OnEnter", function() cancelBtn:SetBackdropBorderColor(0.9,0.25,0.25,1) end)
      cancelBtn:SetScript("OnLeave", function() cancelBtn:SetBackdropBorderColor(0.5,0.15,0.15,1) end)
      table.insert(UISpecialFrames, "LucidUIChatReloadDlg")
      dlg:Show()
    end)
    hit:SetScript("OnEnter", function()
      border:SetColorTexture(0.9, 0.25, 0.25, 0.5)
      GameTooltip:SetOwner(hit, "ANCHOR_RIGHT")
      GameTooltip:SetText(L["Enable Custom Chat"], 0.9, 0.3, 0.3, 1, true)
      GameTooltip:AddLine(L["chat_toggle_tt1"], 0.75, 0.75, 0.75, true)
      GameTooltip:AddLine(L["chat_toggle_tt2"], 0.75, 0.75, 0.75, true)
      GameTooltip:Show()
    end)
    hit:SetScript("OnLeave", function()
      border:SetColorTexture(0.28, 0.28, 0.28, 1)
      GameTooltip:Hide()
    end)
    table.insert(allFrames, holder)
  end

  container:SetScript("OnShow", function()
    for _, f in ipairs(allFrames) do
      if f.SetValue then
        if f.option then f:SetValue(DB(f.option))
        else f:SetValue() end
      end
    end
  end)

  return container
end

-- ══════════════════════════════════════════════════════════════════════
-- TAB 2: Appearance
-- ══════════════════════════════════════════════════════════════════════
local function SetupAppearance(parent)
  local container = CreateFrame("Frame", nil, parent)
  local PAD = 20
  local ar, ag, ab = NS.ChatGetAccentRGB()
  local ACCENT = {ar, ag, ab}
  local isCustom = DB("theme") == "custom"

  -- Default / Custom buttons
  local btnW = 230
  local GAP  = 4
  local themeButtons = {}
  local colorSwatches = {}

  local function MakeThemeBtn(labelText, key, xOffset, yOffset)
    local tb = CreateFrame("Button", nil, container, "BackdropTemplate")
    tb:SetSize(btnW, 22)
    tb:SetPoint("TOP", container, "TOP", xOffset, yOffset)
    tb:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
    tb:SetBackdropColor(0.08, 0.08, 0.08, 1)
    local act = isCustom == (key == "custom")
    tb:SetBackdropBorderColor(act and ACCENT[1] or 0.22, act and ACCENT[2] or 0.22, act and ACCENT[3] or 0.22, 1)
    local tl = tb:CreateFontString(nil, "OVERLAY")
    tl:SetFont("Fonts/FRIZQT__.TTF", 11, ""); tl:SetPoint("CENTER")
    tl:SetTextColor(1, 1, 1, 1); tl:SetText(labelText)
    tb:SetScript("OnEnter", function()
      local hr2, hg2, hb2 = NS.ChatGetAccentRGB()
      tb:SetBackdropBorderColor(hr2, hg2, hb2, 1)
    end)
    tb:SetScript("OnLeave", function()
      local a = isCustom == (key == "custom")
      local hr2, hg2, hb2 = NS.ChatGetAccentRGB()
      tb:SetBackdropBorderColor(a and hr2 or 0.22, a and hg2 or 0.22, a and hb2 or 0.22, 1)
    end)
    table.insert(themeButtons, {btn=tb, key=key})
    return tb
  end

  local halfTotal = (btnW * 2 + GAP) / 2
  local defaultBtn = MakeThemeBtn("Default", "default", -halfTotal + btnW/2, -10)
  local customBtn  = MakeThemeBtn("Custom",  "custom",   halfTotal - btnW/2, -10)
  NS._themeButtons = themeButtons  -- expose for RefreshSettingsAccent

  -- Color rows
  local COLOR_ROWS = {
    {"Accent Color",       "customTilders",   "The main accent color"},
    {"Chat Background",    "chatBgColor",      "Background color of chat"},
    {"Tab Bar Background", "chatTabBarColor",  "Background of tab bar"},
    {"Editbox Background", "chatEditBoxColor", "Background of input box"},
    {"Icon Color",         "chatIconColor",    "Color of bar icons"},
    {"Timestamp Color",    "chatTimestampColor","Color of timestamps"},
  }
  local ROW_H = 22
  local FULL_H = #COLOR_ROWS * ROW_H + 24  -- color rows + top padding + bottom separator
  local ANIM_SPD = 320

  local inner = CreateFrame("Frame", nil, container)
  inner:SetClipsChildren(true)
  inner:SetPoint("TOPLEFT", 0, -38)
  inner:SetPoint("TOPRIGHT", 0, -38)
  inner:SetHeight(isCustom and FULL_H or 0)
  inner:SetShown(isCustom)

  local topSep = inner:CreateTexture(nil, "ARTWORK")
  topSep:SetHeight(1); topSep:SetPoint("TOPLEFT", PAD, 0); topSep:SetPoint("TOPRIGHT", -PAD, 0)
  topSep:SetColorTexture(0.18, 0.18, 0.18, 1)

  local iy = -10
  for _, row in ipairs(COLOR_ROWS) do
    local rowLabel, dbKey, rowTip = row[1], row[2], row[3]
    local stored = DB(dbKey)
    local cr, cg, cb = 0, 0, 0
    if stored and type(stored) == "table" then
      if stored.r then cr, cg, cb = stored.r, stored.g, stored.b
      elseif stored[1] then cr, cg, cb = stored[1], stored[2], stored[3] end
    end

    local capturedKey = dbKey
    local colorRow = NS.ChatGetColorRow(inner, rowLabel, cr, cg, cb, rowTip, function(r, g, b)
      -- Save to DB
      if capturedKey == "customTilders" then
        DBSet(capturedKey, {r, g, b, 1})
      else
        DBSet(capturedKey, {r=r, g=g, b=b})
      end

      -- Apply live based on what changed
      if capturedKey == "customTilders" then
        -- Accent Color: updates CYAN, theme, tabs, bar, chat, loot windows
        NS.CYAN[1], NS.CYAN[2], NS.CYAN[3] = r, g, b
        ACCENT[1], ACCENT[2], ACCENT[3] = r, g, b
        NS.DARK_THEME.tilders = {r, g, b, 1}
        NS.ApplyTheme(DB("theme"))
        if NS.chatRefreshTabs then NS.chatRefreshTabs() end
        if NS.UpdateChatBarAccent then NS.UpdateChatBarAccent() end
        if NS.chatRedraw then NS.chatRedraw(true) end
        -- Redraw LucidUI window (separator color)
        if NS.RedrawMessages then NS.RedrawMessages() end
        -- Update settings dialog itself
        if NS.RefreshSettingsAccent then NS.RefreshSettingsAccent() end

      elseif capturedKey == "chatBgColor" then
        -- Chat background color
        local chatAlpha = 1 - (DB("chatBgAlpha") or 0.5)
        if NS.chatBg then NS.chatBg:SetBackdropColor(r, g, b, chatAlpha) end

      elseif capturedKey == "chatTabBarColor" then
        -- Tab bar background color
        local tabAlpha = 1 - (DB("chatTabBarAlpha") or 0.5)
        if NS.chatTabBarBg then NS.chatTabBarBg:SetColorTexture(r, g, b, tabAlpha) end

      elseif capturedKey == "chatEditBoxColor" then
        -- Editbox background color
        if NS.chatEditContainer then
          local chatAlpha2 = 1 - (DB("chatBgAlpha") or 0.5)
          NS.chatEditContainer:SetBackdropColor(r, g, b, chatAlpha2)
        end

      elseif capturedKey == "chatIconColor" then
        -- Icon bar + LucidUI titlebar icons
        if NS.UpdateChatBarAccent then NS.UpdateChatBarAccent() end
        NS.ApplyTheme(DB("theme"))

      elseif capturedKey == "chatTimestampColor" then
        -- Timestamp color in chat + loot window
        if NS.chatRedraw then NS.chatRedraw(true) end
        if NS.RedrawMessages then NS.RedrawMessages() end
      end
    end)
    colorRow:SetPoint("TOPLEFT", inner, "TOPLEFT", 0, iy)
    colorRow:SetPoint("TOPRIGHT", inner, "TOPRIGHT", 0, iy)
    table.insert(colorSwatches, colorRow._swatch)
    iy = iy - ROW_H
  end

  -- Separator at bottom of slide container
  iy = iy - 6
  local botSep = inner:CreateTexture(nil, "ARTWORK")
  botSep:SetHeight(1)
  botSep:SetPoint("TOPLEFT", PAD, iy)
  botSep:SetPoint("TOPRIGHT", -PAD, iy)
  botSep:SetColorTexture(0.18, 0.18, 0.18, 1)

  -- Always-visible section (slides down when custom opens)
  local avY = isCustom and (-38 - FULL_H) or -38
  local av = CreateFrame("Frame", nil, container)
  av:SetPoint("TOPLEFT", 0, avY); av:SetPoint("TOPRIGHT", 0, avY)
  av:SetHeight(300)

  local tabHL = NS.ChatGetCheckbox(av, "Tab Highlight Background", 28, function(state)
    DBSet("chatTabHighlightBg", state)
    if NS.chatRefreshTabs then NS.chatRefreshTabs() end
  end, "Show a colored background on the active tab")
  tabHL.option = "chatTabHighlightBg"
  tabHL:SetPoint("TOP", av, "TOP", 0, -4)
  tabHL:SetPoint("LEFT", av, "LEFT", 0, 0); tabHL:SetPoint("RIGHT", av, "RIGHT", 0, 0)

  local ebAccent = NS.ChatGetCheckbox(av, "Editbox Accent Border", 28, function(state)
    DBSet("chatEditBoxAccentBorder", state)
    if NS.chatEditContainer then
      if state then
        local acR, acG, acB = NS.ChatGetAccentRGB()
        NS.chatEditContainer:SetBackdropBorderColor(acR, acG, acB, 0.5)
      else
        NS.chatEditContainer:SetBackdropBorderColor(0.15, 0.15, 0.15, 1)
      end
    end
  end, "Use accent color for the editbox border")
  ebAccent.option = "chatEditBoxAccentBorder"
  ebAccent:SetPoint("TOP", tabHL, "BOTTOM", 0, 0)
  ebAccent:SetPoint("LEFT", av, "LEFT", 0, 0); ebAccent:SetPoint("RIGHT", av, "RIGHT", 0, 0)

  local chatAccentLine = NS.ChatGetCheckbox(av, "Chat Accent Line", 28, function(state)
    DBSet("chatAccentLine", state)
    -- Apply live
    if NS.chatBg and NS.chatBg._chatAccentLine then
      NS.chatBg._chatAccentLine:SetShown(state)
    end
  end, "Show an accent colored line at the top of the chat area")
  chatAccentLine.option = "chatAccentLine"
  chatAccentLine:SetPoint("TOP", ebAccent, "BOTTOM", 0, 0)
  chatAccentLine:SetPoint("LEFT", av, "LEFT", 0, 0); chatAccentLine:SetPoint("RIGHT", av, "RIGHT", 0, 0)

  local allSliders = {tabHL, ebAccent, chatAccentLine}

  -- Transparency sliders
  local slY = -80  -- below 3 checkboxes (tabHL + ebAccent + chatAccentLine)
  local chatTransSlider
  chatTransSlider = NS.ChatGetSlider(av, "Chat transparency", 0, 100, "%s%%", function()
    DBSet("chatBgAlpha", chatTransSlider:GetValue() / 100)
    if NS.ApplyChatTransparency then NS.ApplyChatTransparency() end
  end)
  chatTransSlider.option = "chatBgAlpha"
  chatTransSlider._isPercent = true
  chatTransSlider:SetPoint("TOP", av, "TOP", 0, slY)
  table.insert(allSliders, chatTransSlider)
  slY = slY - 40

  local tabTransSlider
  tabTransSlider = NS.ChatGetSlider(av, "Tab bar transparency", 0, 100, "%s%%", function()
    DBSet("chatTabBarAlpha", tabTransSlider:GetValue() / 100)
    if NS.ApplyChatTransparency then NS.ApplyChatTransparency() end
  end)
  tabTransSlider.option = "chatTabBarAlpha"
  tabTransSlider._isPercent = true
  tabTransSlider:SetPoint("TOP", av, "TOP", 0, slY)
  table.insert(allSliders, tabTransSlider)

  -- Animation
  local function AnimateBoth(toY, toH, onComplete)
    av:SetScript("OnUpdate", function(self, elapsed)
      local diffY = toY - avY
      local curH  = inner:GetHeight()
      local diffH = toH - curH
      if math.abs(diffY) < 1 and math.abs(diffH) < 1 then
        avY = toY; inner:SetHeight(toH)
        self:ClearAllPoints(); self:SetPoint("TOPLEFT", 0, avY); self:SetPoint("TOPRIGHT", 0, avY)
        self:SetScript("OnUpdate", nil)
        if onComplete then onComplete() end
        return
      end
      local step = ANIM_SPD * elapsed
      avY = avY + (diffY > 0 and math.min(step, diffY) or math.max(-step, diffY))
      inner:SetHeight(math.max(0, curH + (diffH > 0 and math.min(step, diffH) or math.max(-step, diffH))))
      self:ClearAllPoints(); self:SetPoint("TOPLEFT", 0, avY); self:SetPoint("TOPRIGHT", 0, avY)
    end)
  end

  local AV_COLLAPSED = -38
  local AV_EXPANDED  = -38 - FULL_H

  local function RefreshCustom()
    for _, b in ipairs(themeButtons) do
      local a = isCustom == (b.key == "custom")
      b.btn:SetBackdropBorderColor(a and ACCENT[1] or 0.22, a and ACCENT[2] or 0.22, a and ACCENT[3] or 0.22, 1)
    end
    if isCustom then inner:Show(); AnimateBoth(AV_EXPANDED, FULL_H)
    else AnimateBoth(AV_COLLAPSED, 0, function() inner:Hide() end) end
  end

  defaultBtn:SetScript("OnClick", function()
    isCustom = false
    DBSet("theme", "default")
    -- Reset to fixed default accent (cyan), don't touch saved custom values
    NS.CYAN[1], NS.CYAN[2], NS.CYAN[3] = 59/255, 210/255, 237/255
    NS.DARK_THEME.tilders = {59/255, 210/255, 237/255, 1}
    ACCENT[1], ACCENT[2], ACCENT[3] = 59/255, 210/255, 237/255
    NS.ApplyTheme("default")
    if NS.chatRefreshTabs then NS.chatRefreshTabs() end
    if NS.UpdateChatBarAccent then NS.UpdateChatBarAccent() end
    if NS.chatRedraw then NS.chatRedraw(true) end
    if NS.RedrawMessages then NS.RedrawMessages() end
    if NS.ApplyChatTransparency then NS.ApplyChatTransparency() end
    if NS.RefreshSettingsAccent then NS.RefreshSettingsAccent() end
    RefreshCustom()
  end)
  customBtn:SetScript("OnClick", function()
    isCustom = true
    DBSet("theme", "custom")
    -- Restore saved custom accent color
    local savedAccent = DB("customTilders")
    if savedAccent and type(savedAccent) == "table" then
      local cr2, cg2, cb2
      if savedAccent.r then cr2, cg2, cb2 = savedAccent.r, savedAccent.g, savedAccent.b
      elseif savedAccent[1] then cr2, cg2, cb2 = savedAccent[1], savedAccent[2], savedAccent[3] end
      if cr2 then
        NS.CYAN[1], NS.CYAN[2], NS.CYAN[3] = cr2, cg2, cb2
        NS.DARK_THEME.tilders = {cr2, cg2, cb2, 1}
        ACCENT[1], ACCENT[2], ACCENT[3] = cr2, cg2, cb2
      end
    end
    NS.ApplyTheme("custom")
    if NS.chatRefreshTabs then NS.chatRefreshTabs() end
    if NS.UpdateChatBarAccent then NS.UpdateChatBarAccent() end
    if NS.chatRedraw then NS.chatRedraw(true) end
    if NS.RedrawMessages then NS.RedrawMessages() end
    if NS.ApplyChatTransparency then NS.ApplyChatTransparency() end
    if NS.RefreshSettingsAccent then NS.RefreshSettingsAccent() end
    RefreshCustom()
  end)

  container:SetScript("OnShow", function()
    isCustom = DB("theme") == "custom"
    RefreshCustom()
    av:SetScript("OnUpdate", nil)
    avY = isCustom and AV_EXPANDED or AV_COLLAPSED
    inner:SetHeight(isCustom and FULL_H or 0); inner:SetShown(isCustom)
    av:ClearAllPoints(); av:SetPoint("TOPLEFT", 0, avY); av:SetPoint("TOPRIGHT", 0, avY)
    for _, f in ipairs(allSliders) do
      if f.SetValue and f.option then
        if f._isPercent then f:SetValue((DB(f.option) or 0.5) * 100)
        else f:SetValue(DB(f.option)) end
      end
    end
  end)

  return container
end

-- ══════════════════════════════════════════════════════════════════════
-- TAB 3: Text
-- ══════════════════════════════════════════════════════════════════════
local function SetupText(parent)
  local container = CreateFrame("Frame", nil, parent)
  local allFrames = {}

  -- Apply font to both chat and loottracker windows
  local function ApplyFontLive()
    local font = NS.GetFontPath(DB("chatFont") or DB("font"))
    local size = DB("chatFontSize") or 14
    local outline = DB("chatFontOutline") or ""
    local shadow = DB("chatFontShadow")
    -- Chat display
    if NS.chatDisplay and NS.chatDisplay.SetFont then
      NS.chatDisplay:SetFont(font, size, outline)
      if NS.chatDisplay.SetShadowOffset then
        NS.chatDisplay:SetShadowOffset(shadow and 1 or 0, shadow and -1 or 0)
        NS.chatDisplay:SetShadowColor(0, 0, 0, shadow and 0.8 or 0)
      end
    end
    -- LucidUI window
    if NS.smf then
      NS.smf:SetFont(font, size, outline)
    end
  end

  -- Font dropdown (built dynamically on show)
  local fontDD = NS.ChatGetDropdown(container, "Message Font")
  fontDD:SetPoint("TOP")
  table.insert(allFrames, fontDD)

  local fontSize
  fontSize = NS.ChatGetSlider(container, "Message Font Size", 2, 40, "%spx", function()
    DBSet("chatFontSize", fontSize:GetValue())
    ApplyFontLive()
  end)
  fontSize.option = "chatFontSize"
  fontSize:SetPoint("TOP", fontDD, "BOTTOM")
  table.insert(allFrames, fontSize)

  local msgSpacing
  msgSpacing = NS.ChatGetSlider(container, "Message Spacing", 0, 60, "%spx", function()
    DBSet("chatMessageSpacing", msgSpacing:GetValue())
    -- Apply spacing live
    if NS.chatDisplay and NS.chatDisplay.SetSpacing then
      NS.chatDisplay:SetSpacing(msgSpacing:GetValue())
    end
    if NS.smf then NS.smf:SetSpacing(msgSpacing:GetValue()) end
  end)
  msgSpacing.option = "chatMessageSpacing"
  msgSpacing:SetPoint("TOP", allFrames[#allFrames], "BOTTOM", 0, 0)
  table.insert(allFrames, msgSpacing)

  local outlineDD = NS.ChatGetDropdown(container, "Message Font Outline", function(value)
    return (DB("chatFontOutline") or "") == value
  end, function(value)
    DBSet("chatFontOutline", value)
    ApplyFontLive()
  end)
  outlineDD:SetPoint("TOP", allFrames[#allFrames], "BOTTOM", 0, -10)
  outlineDD:Init({"None", "Outline", "Thick Outline"}, {"", "OUTLINE", "THICKOUTLINE"})
  table.insert(allFrames, outlineDD)

  local fontShadow = NS.ChatGetCheckbox(container, "Font Shadow", 28, function(state)
    DBSet("chatFontShadow", state)
    ApplyFontLive()
  end, "Show a shadow behind chat text")
  fontShadow.option = "chatFontShadow"
  fontShadow:SetPoint("TOP", allFrames[#allFrames], "BOTTOM", 0, 0)
  table.insert(allFrames, fontShadow)

  local enableFade = NS.ChatGetCheckbox(container, "Enable Message Fade", 28, function(state)
    DBSet("chatMessageFade", state)
    if NS.chatDisplay and NS.chatDisplay.SetFading then NS.chatDisplay:SetFading(state) end
  end, "Fade out old messages after a set time")
  enableFade.option = "chatMessageFade"
  enableFade:SetPoint("TOP", allFrames[#allFrames], "BOTTOM", 0, -10)
  table.insert(allFrames, enableFade)

  local fadeTime
  fadeTime = NS.ChatGetSlider(container, "Message Fade Time", 5, 240, "%ss", function()
    DBSet("chatFadeTime", fadeTime:GetValue())
    if NS.chatDisplay and NS.chatDisplay.SetTimeVisible then NS.chatDisplay:SetTimeVisible(fadeTime:GetValue()) end
  end)
  fadeTime.option = "chatFadeTime"
  fadeTime:SetPoint("TOP", allFrames[#allFrames], "BOTTOM")
  table.insert(allFrames, fadeTime)

  local enableLootFade = NS.ChatGetCheckbox(container, "Enable Loot Message Fade", 28, function(state)
    DBSet("enableFade", state)
    NS.ApplyFade()
  end, "Fade out old messages in the LucidUI window")
  enableLootFade.option = "enableFade"
  enableLootFade:SetPoint("TOP", allFrames[#allFrames], "BOTTOM", 0, -10)
  table.insert(allFrames, enableLootFade)

  local lootFadeTime
  lootFadeTime = NS.ChatGetSlider(container, "Loot Fade Time", 5, 240, "%ss", function()
    DBSet("fadeTime", lootFadeTime:GetValue())
    NS.ApplyFade()
  end)
  lootFadeTime.option = "fadeTime"
  lootFadeTime:SetPoint("TOP", allFrames[#allFrames], "BOTTOM")
  table.insert(allFrames, lootFadeTime)

  container:SetScript("OnShow", function()
    -- Invalidate font cache so late-registered LSM fonts are included
    NS.InvalidateLSMCache()
    -- Build font dropdown dynamically
    local fonts = NS.GetLSMFonts()
    local fontValues, fontLabels = {"default"}, {"Default"}
    for _, f in ipairs(fonts) do
      table.insert(fontValues, f.label)
      table.insert(fontLabels, f.label)
    end
    fontDD.DropDown:SetupMenu(function(_, rootDescription)
      for i, label in ipairs(fontLabels) do
        local capIdx = i
        local radio = rootDescription:CreateRadio(label,
          function() return (DB("chatFont") or "Friz Quadrata") == fontValues[capIdx] end,
          function()
            DBSet("chatFont", fontValues[capIdx])
            ApplyFontLive()
          end
        )
        NS.SkinMenuElement(radio)
      end
      rootDescription:SetScrollMode(20 * 20)
    end)
    for _, f in ipairs(allFrames) do
      if f.SetValue and f.option then f:SetValue(DB(f.option)) end
    end
  end)

  return container
end

-- ══════════════════════════════════════════════════════════════════════
-- TAB 4: Advanced
-- ══════════════════════════════════════════════════════════════════════
local function SetupAdvanced(parent)
  local container = CreateFrame("Frame", nil, parent)
  local allFrames = {}

  -- ── Profiles ──────────────────────────────────────────────────────
  local profileHeader = NS.ChatGetHeader(container, "Profiles")
  profileHeader:SetPoint("TOP")
  table.insert(allFrames, profileHeader)

  local profileRow = CreateFrame("Frame", nil, container)
  profileRow:SetHeight(28)
  profileRow:SetPoint("TOP", profileHeader, "BOTTOM", 0, -4)
  profileRow:SetPoint("LEFT", 48, 0)
  profileRow:SetPoint("RIGHT", -50, 0)
  table.insert(allFrames, profileRow)

  -- Styled button helper for Export/Import
  local function MakeIEButton(parent, text)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetHeight(22)
    btn:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
    btn:SetBackdropColor(0.08, 0.08, 0.08, 1)
    btn:SetBackdropBorderColor(0.22, 0.22, 0.22, 1)
    local lbl = btn:CreateFontString(nil, "OVERLAY")
    lbl:SetFont("Fonts/FRIZQT__.TTF", 11, ""); lbl:SetPoint("CENTER")
    lbl:SetTextColor(1, 1, 1, 1); lbl:SetText(text)
    btn._label = lbl
    btn:SetScript("OnEnter", function() btn:SetBackdropBorderColor(NS.ChatGetAccentRGB()) end)
    btn:SetScript("OnLeave", function() btn:SetBackdropBorderColor(0.22, 0.22, 0.22, 1) end)
    return btn
  end

  -- Profile dropdown (real WowStyle1DropdownTemplate)
  local profileDD = CreateFrame("DropdownButton", nil, profileRow, "WowStyle1DropdownTemplate")
  profileDD:SetPoint("TOPLEFT", profileRow, "TOPLEFT", 0, 0)

  -- Skin dropdown
  for _, region in pairs({profileDD:GetRegions()}) do
    if region:IsObjectType("Texture") then region:SetAlpha(0) end
  end
  if profileDD.Arrow then profileDD.Arrow:SetAlpha(0) end
  local ddBd = CreateFrame("Frame", nil, profileDD, "BackdropTemplate")
  ddBd:SetAllPoints(); ddBd:SetFrameLevel(profileDD:GetFrameLevel())
  ddBd:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
  ddBd:SetBackdropColor(0.08, 0.08, 0.08, 1); ddBd:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
  ddBd:EnableMouse(false)
  local ddArr = ddBd:CreateFontString(nil, "OVERLAY")
  ddArr:SetFont("Fonts/FRIZQT__.TTF", 9, ""); ddArr:SetPoint("RIGHT", -5, 0)
  local acR2, acG2, acB2 = NS.ChatGetAccentRGB()
  ddArr:SetTextColor(acR2, acG2, acB2, 1); ddArr:SetText("v")
  table.insert(NS.chatOptDropdownArrows, ddArr)
  if profileDD.Text then
    profileDD.Text:SetTextColor(0.9, 0.9, 0.9, 1)
    profileDD.Text:ClearAllPoints()
    profileDD.Text:SetPoint("LEFT", 6, 0); profileDD.Text:SetPoint("RIGHT", -18, 0)
    profileDD.Text:SetJustifyH("LEFT")
  end
  profileDD:HookScript("OnEnter", function() ddBd:SetBackdropBorderColor(NS.ChatGetAccentRGB()) end)
  profileDD:HookScript("OnLeave", function() ddBd:SetBackdropBorderColor(0.25, 0.25, 0.25, 1) end)

  -- Export and Import buttons
  local exportBtn2 = MakeIEButton(profileRow, "Export")
  local importBtn2 = MakeIEButton(profileRow, "Import")

  -- Layout: dropdown takes 1/3, export 1/3, import 1/3
  profileDD:SetPoint("TOPLEFT", profileRow, "TOPLEFT", 0, 0)
  profileDD:SetPoint("RIGHT", profileRow, "LEFT", profileRow:GetWidth() and math.floor(profileRow:GetWidth()/3) or 200, 0)
  exportBtn2:SetPoint("LEFT", profileDD, "RIGHT", 4, 0)
  importBtn2:SetPoint("RIGHT", profileRow, "RIGHT", 0, 0)

  -- Use OnShow to set correct widths after layout
  profileRow:SetScript("OnShow", function(self)
    local w = self:GetWidth()
    if not w or w < 10 then w = 600 end
    local third = math.floor((w - 8) / 3)
    profileDD:ClearAllPoints()
    profileDD:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
    profileDD:SetSize(third, 22)
    exportBtn2:ClearAllPoints()
    exportBtn2:SetPoint("LEFT", profileDD, "RIGHT", 4, 0)
    exportBtn2:SetSize(third, 22)
    importBtn2:ClearAllPoints()
    importBtn2:SetPoint("LEFT", exportBtn2, "RIGHT", 4, 0)
    importBtn2:SetSize(third, 22)
  end)

  -- Profile dropdown menu
  local function MakeProfileEntryButtons(button, profileName, isActive)
    -- Ensure R/X button frames exist on this recycled button, hide by default
    if not button._ltRenameBtn then
      local renameBtn = CreateFrame("Button", nil, button)
      renameBtn:SetSize(16, 16)
      renameBtn:SetPoint("RIGHT", button, "RIGHT", -24, 0)
      renameBtn:SetFrameLevel(button:GetFrameLevel() + 5)
      local renTex = renameBtn:CreateFontString(nil, "OVERLAY")
      renTex:SetFont("Fonts/FRIZQT__.TTF", 11, "OUTLINE")
      renTex:SetAllPoints(); renTex:SetText("R"); renTex:SetTextColor(0.6, 0.6, 0.6)
      renameBtn:SetScript("OnEnter", function()
        local ar, ag, ab = NS.ChatGetAccentRGB()
        renTex:SetTextColor(ar, ag, ab)
        GameTooltip:SetOwner(renameBtn, "ANCHOR_RIGHT"); GameTooltip:SetText(L["Rename"]); GameTooltip:Show()
      end)
      renameBtn:SetScript("OnLeave", function() renTex:SetTextColor(0.6, 0.6, 0.6); GameTooltip:Hide() end)
      button._ltRenameBtn = renameBtn
    end
    if not button._ltDeleteBtn then
      local delBtn = CreateFrame("Button", nil, button)
      delBtn:SetSize(16, 16)
      delBtn:SetPoint("RIGHT", button, "RIGHT", -6, 0)
      delBtn:SetFrameLevel(button:GetFrameLevel() + 5)
      local delTex = delBtn:CreateFontString(nil, "OVERLAY")
      delTex:SetFont("Fonts/FRIZQT__.TTF", 11, "OUTLINE")
      delTex:SetAllPoints(); delTex:SetText("X"); delTex:SetTextColor(0.6, 0.6, 0.6)
      delBtn:SetScript("OnEnter", function()
        delTex:SetTextColor(1, 0.3, 0.3)
        GameTooltip:SetOwner(delBtn, "ANCHOR_RIGHT"); GameTooltip:SetText(L["Delete"]); GameTooltip:Show()
      end)
      delBtn:SetScript("OnLeave", function() delTex:SetTextColor(0.6, 0.6, 0.6); GameTooltip:Hide() end)
      button._ltDeleteBtn = delBtn
    end

    -- Show rename, wire click
    button._ltRenameBtn:Show()
    button._ltRenameBtn:SetScript("OnClick", function()
      StaticPopupDialogs["LUI_RENAME_PROFILE"] = {
        text = "Rename profile '" .. profileName .. "':",
        hasEditBox = true, button1 = "Rename", button2 = CANCEL,
        OnShow = function(self) self.EditBox:SetText(profileName) end,
        OnAccept = function(self)
          local newName = strtrim(self.EditBox:GetText())
          if newName == "" or newName == profileName then return end
          local profiles = LucidUIDB._profiles or {}
          profiles[newName] = profiles[profileName]
          profiles[profileName] = nil
          if LucidUIDB._activeProfile == profileName then
            LucidUIDB._activeProfile = newName
          end
          NS._RebuildProfileMenu()
        end,
        timeout = 0, whileDead = true, hideOnEscape = true,
      }
      StaticPopup_Show("LUI_RENAME_PROFILE")
    end)

    -- Show delete only if not active
    if not isActive then
      button._ltDeleteBtn:Show()
      button._ltDeleteBtn:SetScript("OnClick", function()
        StaticPopupDialogs["LUI_DELETE_PROFILE"] = {
          text = "Delete profile '" .. profileName .. "' and reload UI?",
          button1 = "Delete & Reload", button2 = CANCEL,
          OnAccept = function()
            local profiles = LucidUIDB._profiles or {}
            profiles[profileName] = nil
            ReloadUI()
          end,
          timeout = 0, whileDead = true, hideOnEscape = true,
        }
        StaticPopup_Show("LUI_DELETE_PROFILE")
      end)
    else
      button._ltDeleteBtn:Hide()
    end
  end

  -- Hide R/X buttons on recycled menu buttons that don't need them
  local function HideProfileButtons(button)
    if button._ltRenameBtn then button._ltRenameBtn:Hide() end
    if button._ltDeleteBtn then button._ltDeleteBtn:Hide() end
  end

  NS._RebuildProfileMenu = function()
    profileDD:SetupMenu(function(_, rootDescription)
      local profiles = LucidUIDB and LucidUIDB._profiles or {}
      local currentProfile = LucidUIDB and LucidUIDB._activeProfile or "Default"

      local defRadio = rootDescription:CreateRadio(
        "|cff88ccffDefault|r",
        function() return currentProfile == "Default" end,
        function()
          if currentProfile ~= "Default" then
            LucidUIDB._activeProfile = "Default"
            StaticPopup_Show("LUCIDUI_CHAT_RELOAD")
          end
        end
      )
      NS.SkinMenuElement(defRadio)
      defRadio:AddInitializer(function(button) HideProfileButtons(button) end)

      local sortedNames = {}
      for name in pairs(profiles) do table.insert(sortedNames, name) end
      table.sort(sortedNames)
      for _, name in ipairs(sortedNames) do
        local isActive = (currentProfile == name)
        local capName = name
        local radio = rootDescription:CreateRadio(name,
          function() return currentProfile == capName end,
          function()
            if currentProfile ~= capName then
              LucidUIDB._activeProfile = capName
              StaticPopup_Show("LUCIDUI_CHAT_RELOAD")
            end
          end
        )
        NS.SkinMenuElement(radio)
        radio:AddInitializer(function(button)
          MakeProfileEntryButtons(button, capName, isActive)
        end)
      end

      rootDescription:CreateDivider()
      local resetBtn = rootDescription:CreateButton("|cffff4444Reset All Settings|r", function()
        StaticPopupDialogs["LUI_RESET_SETTINGS"] = {
          text = "Reset ALL LucidUI settings to defaults?\n\nRequires UI reload.",
          button1 = "Reset & Reload", button2 = CANCEL,
          OnAccept = function() LucidUIDB = {}; ReloadUI() end,
          timeout = 0, whileDead = true, hideOnEscape = true,
        }
        StaticPopup_Show("LUI_RESET_SETTINGS")
      end)
      resetBtn:AddInitializer(function(button) HideProfileButtons(button) end)
    end)
  end
  NS._RebuildProfileMenu()

  -- Export: copy all settings to clipboard
  exportBtn2:SetScript("OnClick", function()
    -- Simple table serializer
    local function Serialize(val)
      if type(val) == "table" then
        local parts = {}
        -- Check if array or dict
        local isArray = true
        local maxN = 0
        for k in pairs(val) do
          if type(k) == "number" then maxN = math.max(maxN, k)
          else isArray = false end
        end
        if isArray and maxN > 0 then
          for i = 1, maxN do table.insert(parts, Serialize(val[i])) end
          return "{" .. table.concat(parts, ",") .. "}"
        else
          for k, v in pairs(val) do
            table.insert(parts, tostring(k) .. "=" .. Serialize(v))
          end
          return "{" .. table.concat(parts, ",") .. "}"
        end
      elseif type(val) == "string" then
        return '"' .. val:gsub('"', '\\"') .. '"'
      elseif type(val) == "boolean" then
        return val and "true" or "false"
      else
        return tostring(val)
      end
    end

    local skip = {history=true, chatHistory=true, debugHistory=true, chatTabs=true, qolFpsBackup=true, _profiles=true, _activeProfile=true, _sessionData=true, _rollData=true, _rollEncounter=true}
    local lines = {"LUI_EXPORT:" .. (NS.DB("theme") or "default") .. ":" .. date("%Y%m%d")}
    for k, v in pairs(LucidUIDB or {}) do
      if not skip[k] then
        table.insert(lines, k .. "=" .. Serialize(v))
      end
    end
    local text = table.concat(lines, "\n")

    local frame = CreateFrame("Frame", "LUIExportFrame", UIParent, "BackdropTemplate")
    frame:SetSize(500, 300); frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG"); frame:SetMovable(true); frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    frame:EnableMouse(true)
    frame:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
    frame:SetBackdropColor(0.06, 0.06, 0.06, 0.95); frame:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOP", 0, -6); title:SetText(L["export_hint"])
    local ar2,ag2,ab2 = NS.ChatGetAccentRGB(); title:SetTextColor(ar2, ag2, ab2)
    local closeBtn2 = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn2:SetPoint("TOPRIGHT", 2, 2)
    closeBtn2:SetScript("OnClick", function() frame:Hide() end)
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

  -- Import: paste settings
  importBtn2:SetScript("OnClick", function()
    local frame = CreateFrame("Frame", "LUIImportFrame", UIParent, "BackdropTemplate")
    frame:SetSize(500, 340); frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG"); frame:SetMovable(true); frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    frame:EnableMouse(true)
    frame:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
    frame:SetBackdropColor(0.06, 0.06, 0.06, 0.95); frame:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOP", 0, -6); title:SetText(L["import_hint"])
    local ar2,ag2,ab2 = NS.ChatGetAccentRGB(); title:SetTextColor(ar2, ag2, ab2)
    local status = frame:CreateFontString(nil, "OVERLAY")
    status:SetFont("Fonts/FRIZQT__.TTF", 10, ""); status:SetPoint("TOPLEFT", 12, -22)
    status:SetTextColor(0.6, 0.6, 0.6)
    local closeBtn2 = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn2:SetPoint("TOPRIGHT", 2, 2)
    closeBtn2:SetScript("OnClick", function() frame:Hide() end)

    -- Profile name input
    local nameLabel = frame:CreateFontString(nil, "OVERLAY")
    nameLabel:SetFont("Fonts/FRIZQT__.TTF", 10, ""); nameLabel:SetPoint("TOPLEFT", 12, -36)
    nameLabel:SetTextColor(0.7, 0.7, 0.7); nameLabel:SetText(L["Profile Name:"])
    local nameBox = CreateFrame("EditBox", nil, frame, "BackdropTemplate")
    nameBox:SetSize(200, 22); nameBox:SetPoint("LEFT", nameLabel, "RIGHT", 6, 0)
    nameBox:SetFontObject(GameFontHighlight); nameBox:SetAutoFocus(false)
    nameBox:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
    nameBox:SetBackdropColor(0.1, 0.1, 0.1, 1); nameBox:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    nameBox:SetTextInsets(4, 4, 0, 0)
    nameBox:SetScript("OnEscapePressed", function() nameBox:ClearFocus() end)
    nameBox:SetScript("OnEnterPressed", function() nameBox:ClearFocus() end)

    local sf = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 10, -60); sf:SetPoint("BOTTOMRIGHT", -30, 40)
    local eb = CreateFrame("EditBox", nil, frame)
    eb:SetMultiLine(true); eb:SetAutoFocus(true); eb:SetFontObject(GameFontHighlight); eb:SetWidth(460)
    eb:SetScript("OnEscapePressed", function() frame:Hide() end)
    sf:SetScrollChild(eb)
    C_Timer.After(0, function()
      if not frame:IsShown() then return end
      eb:SetWidth(sf:GetWidth()); eb:SetFocus()
    end)
    local doImport = MakeIEButton(frame, "Import")
    doImport:ClearAllPoints()
    doImport:SetSize(85, 24); doImport:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 10)
    doImport:SetScript("OnClick", function()
      local profileName = strtrim(nameBox:GetText())
      if profileName == "" then
        status:SetTextColor(1, 0.3, 0.3); status:SetText(L["err_no_name"]); return
      end
      local raw = strtrim(eb:GetText())
      if raw == "" then status:SetTextColor(1, 0.3, 0.3); status:SetText(L["err_no_paste"]); return end
      if not raw:match("^LUI_EXPORT:") then
        status:SetTextColor(1, 0.3, 0.3); status:SetText(L["err_bad_format"])
        return
      end
      StaticPopupDialogs["LUI_IMPORT_RELOAD"] = {
        text = "Import as profile '" .. profileName .. "' and reload UI?",
        button1 = "Import & Reload", button2 = CANCEL,
        OnAccept = function()
          -- Deserialize value string
          local function Deserialize(s)
            if s == "true" then return true end
            if s == "false" then return false end
            if s == "nil" then return nil end
            if tonumber(s) then return tonumber(s) end
            if s:match('^".*"$') then return s:sub(2, -2):gsub('\\"', '"') end
            -- Safe table parser: only handles {key=val,...} and {val,...} without loadstring
            if s:match("^{.*}$") then
              local result = {}
              local inner = s:sub(2, -2)
              -- Tokenize key=value pairs safely (no code execution)
              local i = 1
              local arrIdx = 1
              while i <= #inner do
                -- Skip whitespace and commas
                local _, eSkip = inner:find("^[%s,]*", i)
                i = (eSkip or i - 1) + 1
                if i > #inner then break end
                -- Try key=value
                local k, rest = inner:match("^([%w_]+)=(.+)", i)
                if k then
                  -- Find end of value (before next non-nested comma)
                  local depth, j = 0, 1
                  local valStr = rest
                  for ci = 1, #rest do
                    local ch = rest:sub(ci, ci)
                    if ch == "{" then depth = depth + 1
                    elseif ch == "}" then depth = depth - 1
                    elseif ch == "," and depth == 0 then
                      valStr = rest:sub(1, ci - 1)
                      i = i + #k + 1 + ci
                      break
                    end
                    if ci == #rest then i = i + #k + 1 + #rest + 1 end
                  end
                  local numKey = tonumber(k)
                  if numKey then
                    result[numKey] = Deserialize(strtrim(valStr))
                  else
                    result[k] = Deserialize(strtrim(valStr))
                  end
                else
                  -- Array value
                  local depth2 = 0
                  for ci = i, #inner do
                    local ch = inner:sub(ci, ci)
                    if ch == "{" then depth2 = depth2 + 1
                    elseif ch == "}" then depth2 = depth2 - 1
                    elseif ch == "," and depth2 == 0 then
                      result[arrIdx] = Deserialize(strtrim(inner:sub(i, ci - 1)))
                      arrIdx = arrIdx + 1
                      i = ci + 1
                      break
                    end
                    if ci == #inner then
                      result[arrIdx] = Deserialize(strtrim(inner:sub(i, ci)))
                      arrIdx = arrIdx + 1
                      i = ci + 1
                    end
                  end
                end
              end
              return result
            end
            return s
          end
          -- Build profile data from import (skip internal keys)
          local skipKeys = {_profiles=true, _activeProfile=true}
          local profileData = {}
          for line in raw:gmatch("[^\n]+") do
            local k, v = line:match("^([^=]+)=(.+)$")
            if k and v and not k:match("^LUI_EXPORT") and not skipKeys[k] then
              profileData[k] = Deserialize(v)
            end
          end
          -- Save as named profile
          LucidUIDB._profiles = LucidUIDB._profiles or {}
          LucidUIDB._profiles[profileName] = profileData
          -- Switch to the imported profile
          LucidUIDB._activeProfile = profileName
          -- Apply profile data to DB
          for k, v in pairs(profileData) do
            LucidUIDB[k] = v
          end
          ReloadUI()
        end,
        timeout = 0, whileDead = true, hideOnEscape = true,
      }
      frame:Hide()
      StaticPopup_Show("LUI_IMPORT_RELOAD")
    end)
  end)

  -- Show Tabs
  local showTabs = NS.ChatGetDropdown(container, "Show Tabs", function(value)
    return (DB("chatTabVisibility") or "always") == value
  end, function(value)
    DBSet("chatTabVisibility", value)
    -- Apply live: tab bar visibility
    local ltTabBar = _G["LUIChatTabBar"]
    if ltTabBar then
      if value == "mouseover" then
        ltTabBar:SetAlpha(0)
        ltTabBar:HookScript("OnEnter", function() ltTabBar:SetAlpha(1) end)
        ltTabBar:HookScript("OnLeave", function()
          if (DB("chatTabVisibility") or "always") == "mouseover" then
            if not ltTabBar:IsMouseOver() then ltTabBar:SetAlpha(0) end
          end
        end)
      else
        ltTabBar:SetAlpha(1)
      end
    end
  end)
  showTabs:SetPoint("TOP", allFrames[#allFrames], "BOTTOM", 0, -10)
  showTabs:Init({"Always", "Mouseover"}, {"always", "mouseover"})
  showTabs.option = "chatTabVisibility"
  table.insert(allFrames, showTabs)

  -- Show Buttons
  local showButtons = NS.ChatGetDropdown(container, "Show Buttons", function(value)
    return (DB("chatBarVisibility") or "always") == value
  end, function(value)
    DBSet("chatBarVisibility", value)
    -- Apply live
    if NS.chatBarRef then
      if value == "never" then
        NS.chatBarRef:SetAlpha(0); NS.chatBarRef:EnableMouse(false)
      elseif value == "mouseover" then
        NS.chatBarRef:SetAlpha(0); NS.chatBarRef:EnableMouse(true)
      else
        NS.chatBarRef:SetAlpha(1); NS.chatBarRef:EnableMouse(true)
      end
    end
    -- Update tabbar bg stretch
    if NS.UpdateTabBarBgStretch then NS.UpdateTabBarBgStretch() end
  end)
  showButtons:SetPoint("TOP", allFrames[#allFrames], "BOTTOM", 0, 0)
  showButtons:Init({"Always", "Mouseover"}, {"always", "mouseover"})
  showButtons.option = "chatBarVisibility"
  table.insert(allFrames, showButtons)

  -- Button Position
  local btnPos = NS.ChatGetDropdown(container, "Buttons Position", function(value)
    return (DB("chatBarPosition") or "outside_right") == value
  end, function(value)
    local oldPos2 = DB("chatBarPosition") or "outside_right"
    DBSet("chatBarPosition", value)
    if NS.RepositionChatBar then NS.RepositionChatBar() end
    -- Nudge chat window so it doesn't go off-screen
    if NS.chatBg and oldPos2 ~= value then
      local x, y = NS.chatBg:GetLeft(), NS.chatBg:GetBottom()
      if x and y then
        local BAR2 = 32
        if value == "outside_left" and oldPos2 ~= "outside_left" then
          x = x + BAR2  -- bar moved left outside, push window right
        elseif oldPos2 == "outside_left" and value ~= "outside_left" then
          x = x - BAR2  -- bar left removed, push window left
        elseif value == "outside_right" and oldPos2 ~= "outside_right" then
          -- nothing, bar extends to the right
        end
        NS.chatBg:ClearAllPoints()
        NS.chatBg:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", math.max(0, x), math.max(0, y))
        NS.DBSet("chatWinPos", {x=math.max(0, x), y=math.max(0, y)})
      end
    end
  end)
  btnPos:SetPoint("TOP", allFrames[#allFrames], "BOTTOM", 0, 0)
  btnPos:Init(
    {"Left Outside", "Left Inside", "Right Outside", "Right Inside"},
    {"outside_left", "inside_left", "outside_right", "inside_right"})
  btnPos.option = "chatBarPosition"
  table.insert(allFrames, btnPos)

  -- Edit Box Position
  local ebPos = NS.ChatGetDropdown(container, "Edit Box Position", function(value)
    return (DB("chatEditBoxPos") or "bottom") == value
  end, function(value)
    local oldPos = DB("chatEditBoxPos") or "bottom"
    DBSet("chatEditBoxPos", value)
    -- Reposition editbox container live
    if NS.chatEditContainer and NS.chatBg then
      NS.chatEditContainer:ClearAllPoints()
      if value == "top" then
        NS.chatEditContainer:SetPoint("TOPLEFT", NS.chatBg, "TOPLEFT", 0, 0)
        NS.chatEditContainer:SetPoint("TOPRIGHT", NS.chatBg, "TOPRIGHT", 0, 0)
      else
        NS.chatEditContainer:SetPoint("TOPLEFT", NS.chatBg, "BOTTOMLEFT", 0, -1)
        NS.chatEditContainer:SetPoint("TOPRIGHT", NS.chatBg, "BOTTOMRIGHT", 0, -1)
      end
      -- Nudge chat window so it doesn't go off-screen
      if oldPos ~= value then
        local x, y = NS.chatBg:GetLeft(), NS.chatBg:GetBottom()
        if x and y then
          if value == "bottom" and oldPos == "top" then
            y = y + 28  -- editbox moved below, push window up
          elseif value == "top" and oldPos == "bottom" then
            y = y - 28  -- editbox moved above, push window down
          end
          NS.chatBg:ClearAllPoints()
          NS.chatBg:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, math.max(0, y))
          NS.DBSet("chatWinPos", {x=x, y=math.max(0, y)})
        end
      end
    end
  end)
  ebPos:SetPoint("TOP", allFrames[#allFrames], "BOTTOM", 0, -10)
  ebPos:Init({"Bottom", "Top"}, {"bottom", "top"})
  ebPos.option = "chatEditBoxPos"
  table.insert(allFrames, ebPos)

  -- Keep Edit Box Visible
  local keepEB = NS.ChatGetCheckbox(container, "Keep Edit Box Visible", 28, function(state)
    DBSet("chatEditBoxVisible", state)
    -- Apply live
    local eb = ChatFrame1EditBox or ChatFrameEditBox
    if eb and NS.chatEditContainer then
      if state then
        eb:Show(); NS.chatEditContainer:Show()
      else
        if not eb:HasFocus() then
          eb:Hide(); NS.chatEditContainer:Hide()
        end
      end
    end
  end, "Always show the chat input box")
  keepEB.option = "chatEditBoxVisible"
  keepEB:SetPoint("TOP", allFrames[#allFrames], "BOTTOM", 0, 0)
  table.insert(allFrames, keepEB)

  container:SetScript("OnShow", function()
    for _, f in ipairs(allFrames) do
      if f.SetValue then
        if f.option then f:SetValue(DB(f.option))
        else f:SetValue() end
      end
    end
  end)

  return container
end

-- ══════════════════════════════════════════════════════════════════════
-- TAB 5: Chat Colors
-- ══════════════════════════════════════════════════════════════════════
local MC_TYPE_LAYOUT = {
  MESSAGES = {
    {"SAY"}, {"EMOTE"}, {"YELL"}, {"TEXT_EMOTE"},
    {"GUILD"}, {"OFFICER"},
    {"GUILD_ACHIEVEMENT"}, {"ACHIEVEMENT"},
    {"WHISPER"}, {"BN_WHISPER"},
    {"PARTY"}, {"PARTY_LEADER"},
    {"RAID"}, {"RAID_LEADER"}, {"RAID_WARNING"},
    {"INSTANCE_CHAT"}, {"INSTANCE_CHAT_LEADER"},
  },
  CREATURE = {
    {"MONSTER_SAY"}, {"MONSTER_EMOTE"}, {"MONSTER_YELL"},
    {"MONSTER_WHISPER"}, {"MONSTER_BOSS_EMOTE"}, {"MONSTER_BOSS_WHISPER"},
  },
  REWARDS = {
    {"COMBAT_XP_GAIN"}, {"COMBAT_HONOR_GAIN"}, {"COMBAT_FACTION_CHANGE"},
    {"SKILL"}, {"LOOT"}, {"CURRENCY"}, {"MONEY"},
  },
  PVP = {
    {"BG_SYSTEM_HORDE"}, {"BG_SYSTEM_ALLIANCE"}, {"BG_SYSTEM_NEUTRAL"},
  },
  SYSTEM = {
    {"SYSTEM"}, {"CHANNEL"}, {"AFK"}, {"DND"},
    {"FILTERED"}, {"RESTRICTED"}, {"IGNORED"},
    {"BN_INLINE_TOAST_ALERT"},
  },
}

local MC_ORDER = {
  {"Chat",     "MESSAGES"},
  {"Creature", "CREATURE"},
  {"Rewards",  "REWARDS"},
  {"PvP",      "PVP"},
  {"System",   "SYSTEM"},
}

local EVENT_LABELS = {
  SAY="Say", EMOTE="Emote", YELL="Yell", TEXT_EMOTE="Text Emote",
  GUILD="Guild", OFFICER="Officer",
  GUILD_ACHIEVEMENT="Guild Achievement", GUILD_ITEM_LOOTED="Guild Loot", ACHIEVEMENT="Achievement",
  WHISPER="Whisper", BN_WHISPER="BNet Whisper",
  PARTY="Party", PARTY_LEADER="Party Leader",
  RAID="Raid", RAID_LEADER="Raid Leader", RAID_WARNING="Raid Warning",
  INSTANCE_CHAT="Instance", INSTANCE_CHAT_LEADER="Instance Leader",
  VOICE_TEXT="Voice Chat",
  MONSTER_SAY="Say", MONSTER_EMOTE="Emote", MONSTER_YELL="Yell",
  MONSTER_WHISPER="Whisper", MONSTER_BOSS_EMOTE="Boss Emote", MONSTER_BOSS_WHISPER="Boss Whisper",
  RAID_BOSS_EMOTE="Raid Boss Emote", RAID_BOSS_WHISPER="Raid Boss Whisper",
  COMBAT_XP_GAIN="XP Gain", COMBAT_HONOR_GAIN="Honor", COMBAT_FACTION_CHANGE="Reputation",
  SKILL="Skill-ups", LOOT="Item Loot", CURRENCY="Currency", MONEY="Money Loot",
  TRADESKILLS="Tradeskills", OPENING="Opening", PET_INFO="Pet Info", COMBAT_MISC_INFO="Misc Info",
  BG_SYSTEM_HORDE="BG Horde", BG_SYSTEM_ALLIANCE="BG Alliance", BG_SYSTEM_NEUTRAL="BG Neutral",
  SYSTEM="System", CHANNEL="Channel", AFK="AFK", DND="DND",
  FILTERED="Filtered", RESTRICTED="Restricted", IGNORED="Ignored",
  BN_INLINE_TOAST_ALERT="BNet Toast",
  PET_BATTLE_COMBAT_LOG="Pet Battle Combat", PET_BATTLE_INFO="Pet Battle Info",
  PING="Ping",
  LUI_ADDON="Addon Messages",
}

local function SetupMessageColors(parent)
  local container = CreateFrame("Frame", nil, parent)
  container:SetScript("OnMouseWheel", function() end)

  local scrollFrame = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
  scrollFrame:SetPoint("TOPLEFT", 0, 0)
  scrollFrame:SetPoint("BOTTOMRIGHT", -24, 0)
  local scrollChild = CreateFrame("Frame", nil, scrollFrame)
  scrollChild:SetWidth(560)
  scrollFrame:SetScrollChild(scrollChild)
  container:SetScript("OnSizeChanged", function(_, w) scrollChild:SetWidth(w - 24) end)
  NS.AddSmoothScroll(scrollFrame)

  local PAD = 40
  local ROW_H = 22
  local allSections = {}

  local function RepositionAll()
    local y = 0
    for _, sec in ipairs(allSections) do
      sec.header:ClearAllPoints()
      sec.header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
      sec.header:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -y)
      y = y + sec.header:GetHeight()
      sec.inner:ClearAllPoints()
      sec.inner:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
      sec.inner:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -y)
      y = y + sec.inner:GetHeight()
    end
    scrollChild:SetHeight(math.max(y, 1))
  end

  local function MakeColorSection(sectionLabel, layoutKey)
    local header = CreateFrame("Button", nil, scrollChild)
    header:SetHeight(28)
    local headerText = header:CreateFontString(nil, "OVERLAY")
    headerText:SetFont("Fonts/FRIZQT__.TTF", 11, "")
    headerText:SetPoint("LEFT", PAD, 0); headerText:SetJustifyH("LEFT")
    headerText:SetText("|cff" .. NS.ChatGetAccentHex() .. ">|r |cffffffff" .. sectionLabel .. "|r")
    table.insert(NS.chatOptAccentLabels, {fs=headerText, rawText=sectionLabel, white=true})

    local headerLine = header:CreateTexture(nil, "ARTWORK")
    headerLine:SetColorTexture(0.18, 0.18, 0.18, 1)
    headerLine:SetHeight(1)
    headerLine:SetPoint("BOTTOMLEFT", PAD, 0); headerLine:SetPoint("BOTTOMRIGHT", -10, 0)

    local headerHL = header:CreateTexture(nil, "BACKGROUND")
    headerHL:SetPoint("TOPLEFT", PAD-2, 0); headerHL:SetPoint("BOTTOMRIGHT", -10, 0)
    headerHL:SetColorTexture(1, 1, 1, 0.03); headerHL:Hide()
    header:SetScript("OnEnter", function() headerHL:Show() end)
    header:SetScript("OnLeave", function() headerHL:Hide() end)

    local inner = CreateFrame("Frame", nil, scrollChild)
    inner:SetClipsChildren(true); inner:SetHeight(0)

    local section = {header=header, inner=inner, expanded=false, rows={}, targetH=0}
    table.insert(allSections, section)

    local function BuildRows()
      for _, r in ipairs(section.rows) do r:Hide() end
      section.rows = {}
      local colors = DB("chatColors") or {}
      local fields = MC_TYPE_LAYOUT[layoutKey] or {}
      local iy2 = -4
      for _, f in ipairs(fields) do
        local shortKey = f[1]
        local label = EVENT_LABELS[shortKey] or shortKey
        local ci = ChatTypeInfo and ChatTypeInfo[shortKey]
        local c = colors[shortKey]
        if not c and ci then c = {r=ci.r, g=ci.g, b=ci.b} end
        c = c or {r=1, g=1, b=1}

        local rowFrame = CreateFrame("Frame", nil, inner)
        rowFrame:SetHeight(ROW_H)
        rowFrame:SetPoint("TOPLEFT", PAD, iy2); rowFrame:SetPoint("TOPRIGHT", -PAD, iy2)

        local rowHL = rowFrame:CreateTexture(nil, "BACKGROUND")
        rowHL:SetAllPoints(); rowHL:SetColorTexture(1, 1, 1, 0.05); rowHL:Hide()

        local lbl = rowFrame:CreateFontString(nil, "OVERLAY")
        lbl:SetFont("Fonts/FRIZQT__.TTF", 11, "")
        lbl:SetPoint("LEFT", 0, 0)
        lbl:SetTextColor(c.r, c.g, c.b); lbl:SetText(label)

        local sw = CreateFrame("Frame", nil, rowFrame, "BackdropTemplate")
        sw:SetSize(14, 14); sw:SetPoint("RIGHT", -50, 0)

        -- Default button after (right of) color swatch
        local resetBtn = CreateFrame("Button", nil, rowFrame)
        resetBtn:SetSize(42, 14); resetBtn:SetPoint("LEFT", sw, "RIGHT", 6, 0)
        local resetLbl = resetBtn:CreateFontString(nil, "OVERLAY")
        resetLbl:SetFont("Fonts/FRIZQT__.TTF", 10, ""); resetLbl:SetAllPoints()
        resetLbl:SetJustifyH("RIGHT"); resetLbl:SetTextColor(1, 1, 1); resetLbl:SetText("Default")
        resetBtn:Hide()
        sw:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
        sw:SetBackdropColor(c.r, c.g, c.b, 1); sw:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

        -- Show reset only if custom color exists
        if colors[shortKey] then resetBtn:Show() end

        local hit = CreateFrame("Button", nil, rowFrame)
        hit:SetPoint("TOPLEFT"); hit:SetPoint("BOTTOMRIGHT", sw, "BOTTOMRIGHT", 0, 0)
        hit:SetFrameLevel(rowFrame:GetFrameLevel() + 3)
        local capC, capSw, capKey = c, sw, shortKey
        hit:SetScript("OnEnter", function() rowHL:Show(); sw:SetBackdropBorderColor(0, 1, 1, 1) end)
        hit:SetScript("OnLeave", function() rowHL:Hide(); sw:SetBackdropBorderColor(0.4, 0.4, 0.4, 1) end)
        hit:SetScript("OnClick", function()
          local old = {r=capC.r, g=capC.g, b=capC.b}
          ColorPickerFrame:SetupColorPickerAndShow({
            r=capC.r, g=capC.g, b=capC.b,
            swatchFunc = function()
              local nr, ng, nb = ColorPickerFrame:GetColorRGB()
              capC.r, capC.g, capC.b = nr, ng, nb
              capSw:SetBackdropColor(nr, ng, nb, 1)
              if not LucidUIDB.chatColors then LucidUIDB.chatColors = {} end
              LucidUIDB.chatColors[capKey] = {r=nr, g=ng, b=nb}
              resetBtn:Show()
            end,
            cancelFunc = function()
              capC.r, capC.g, capC.b = old.r, old.g, old.b
              capSw:SetBackdropColor(old.r, old.g, old.b, 1)
              if LucidUIDB and LucidUIDB.chatColors then
                LucidUIDB.chatColors[capKey] = {r=old.r, g=old.g, b=old.b}
              end
            end,
          })
        end)
        -- Reset button: restore WoW default color
        resetBtn:SetScript("OnEnter", function()
          local ar2, ag2, ab2 = NS.ChatGetAccentRGB()
          resetLbl:SetTextColor(ar2, ag2, ab2)
        end)
        resetBtn:SetScript("OnLeave", function() resetLbl:SetTextColor(1, 1, 1) end)
        resetBtn:SetScript("OnClick", function()
          -- Get WoW default color
          local defCi = ChatTypeInfo and ChatTypeInfo[capKey]
          local dr, dg, db = 1, 1, 1
          if defCi then dr, dg, db = defCi.r, defCi.g, defCi.b end
          -- Remove custom color from DB
          if LucidUIDB and LucidUIDB.chatColors then
            LucidUIDB.chatColors[capKey] = nil
          end
          -- Update swatch + label
          capC.r, capC.g, capC.b = dr, dg, db
          capSw:SetBackdropColor(dr, dg, db, 1)
          lbl:SetTextColor(dr, dg, db)
          resetBtn:Hide()
        end)
        table.insert(section.rows, rowFrame)
        iy2 = iy2 - ROW_H
      end
      return #fields * ROW_H + 8
    end

    local function AnimateStep(_, elapsed)
      local curH = inner:GetHeight()
      local diff = section.targetH - curH
      if math.abs(diff) < 1 then
        inner:SetHeight(section.targetH); inner:SetScript("OnUpdate", nil)
        if section.targetH == 0 then for _, r in ipairs(section.rows) do r:Hide() end end
        RepositionAll(); return
      end
      inner:SetHeight(curH + (diff > 0 and math.min(400*elapsed, diff) or math.max(-400*elapsed, diff)))
      RepositionAll()
    end

    header:SetScript("OnClick", function()
      for _, sec in ipairs(allSections) do
        if sec ~= section and sec.expanded then
          sec.expanded = false; sec.targetH = 0; sec.inner:SetScript("OnUpdate", sec.animate)
        end
      end
      section.expanded = not section.expanded
      section.targetH = section.expanded and BuildRows() or 0
      inner:SetScript("OnUpdate", AnimateStep)
    end)
    section.animate = AnimateStep
  end

  for _, entry in ipairs(MC_ORDER) do
    MakeColorSection(entry[1], entry[2])
  end
  C_Timer.After(0, RepositionAll)

  return container
end

-- ══════════════════════════════════════════════════════════════════════
-- TAB 6: Loot
-- ══════════════════════════════════════════════════════════════════════
local function SetupLoot(parent)
  local container = CreateFrame("Frame", nil, parent)
  local scrollFrame = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
  scrollFrame:SetPoint("TOPLEFT", 0, 0); scrollFrame:SetPoint("BOTTOMRIGHT", -24, 0)
  local scrollChild = CreateFrame("Frame", nil, scrollFrame)
  scrollChild:SetSize(560, 1)
  scrollFrame:SetScrollChild(scrollChild)
  container:SetScript("OnSizeChanged", function(_, w) scrollChild:SetWidth(w - 24) end)
  NS.AddSmoothScroll(scrollFrame)

  local allFrames = {}
  local lootSettingsItems = {}
  local RefreshLootSettingsVisibility  -- forward declaration

  local function RepositionAll()
    local y = 0
    for _, f in ipairs(allFrames) do
      f:ClearAllPoints()
      if f:IsShown() then
        f:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
        f:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -y)
        y = y + f:GetHeight()
      else
        f:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
        f:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -y)
      end
    end
    scrollChild:SetHeight(math.max(y, 1))
  end

  -- ── LootTracker in Chat Tab ──────────────────────
  local ownWinCB  -- forward declare for mutual exclusion
  local enableLoot = NS.ChatGetCheckbox(scrollChild, "LootTracker in Chat Tab", 28, function(state)
    DBSet("lootInChatTab", state)
    if state then
      -- Deactivate own window
      DBSet("lootOwnWindow", false)
      if ownWinCB then ownWinCB:SetValue(false) end
      if NS.win then NS.win:Hide() end
      -- Create managed Loot tab in chat
      local tabD = NS.chatTabData and NS.chatTabData()
      if tabD then
        local exists = false
        for _, td in ipairs(tabD) do
          if td._isLootTab then exists = true; break end
        end
        if not exists then
          table.insert(tabD, {
            name = "Loot", colorHex = "00cc66",
            eventSet = {},  -- empty: fed exclusively by NS.AddMessage
            channelBlocked = {General=true, Trade=true, LocalDefense=true, Services=true, LookingForGroup=true},
            _isLootTab = true,
          })
          if NS.SyncLootEvents then NS.SyncLootEvents() end
          if NS.chatRebuildTabs then NS.chatRebuildTabs() end
          if NS.chatRedraw then NS.chatRedraw() end
        end
      end
    else
      -- Remove managed Loot tab
      local tabD = NS.chatTabData and NS.chatTabData()
      if tabD then
        for i = #tabD, 1, -1 do
          if tabD[i]._isLootTab then table.remove(tabD, i) end
        end
        if NS.SyncLootEvents then NS.SyncLootEvents() end
        if NS.chatRebuildTabs then NS.chatRebuildTabs() end
        if NS.chatRedraw then NS.chatRedraw() end
      end
    end
    RefreshLootSettingsVisibility()
  end, "Create a Loot tab in the chat window")
  enableLoot.option = "lootInChatTab"
  table.insert(allFrames, enableLoot)

  -- ── LootTracker in own Window + transparency slider ──────────────────
  local ownWinRow = CreateFrame("Frame", nil, scrollChild); ownWinRow:SetHeight(28)
  ownWinCB = NS.ChatGetCheckbox(ownWinRow, "LootTracker in own Window", 28, function(state)
    DBSet("lootOwnWindow", state)
    ownWinRow._transSlider:SetShown(state); RepositionAll()
    if state then
      -- Deactivate chat tab
      DBSet("lootInChatTab", false)
      enableLoot:SetValue(false)
      -- Remove managed Loot tab
      local tabD = NS.chatTabData and NS.chatTabData()
      if tabD then
        for i = #tabD, 1, -1 do
          if tabD[i]._isLootTab then table.remove(tabD, i) end
        end
        if NS.chatRebuildTabs then NS.chatRebuildTabs() end
      end
      if NS.SyncLootEvents then NS.SyncLootEvents() end
      if NS.win then NS.win:Show() end
    else
      if NS.SyncLootEvents then NS.SyncLootEvents() end
      if NS.win then NS.win:Hide() end
    end
    RefreshLootSettingsVisibility()
  end, "Show loot in a standalone draggable window")
  ownWinCB.option = "lootOwnWindow"
  ownWinCB:SetParent(ownWinRow); ownWinCB:ClearAllPoints()
  ownWinCB:SetPoint("TOPLEFT", ownWinRow, "TOPLEFT", 0, 0); ownWinCB:SetSize(320, 28)
  if ownWinCB._highlight then
    ownWinCB._highlight:ClearAllPoints()
    ownWinCB._highlight:SetAllPoints(ownWinRow)
  end

  local ownWinTrans = NS.ChatGetSlider(ownWinRow, "", 0, 100, "%d%%", function(value)
    DBSet("lootWinTransparency", value / 100)
    NS.ApplyAlpha()
  end)
  ownWinTrans:ClearAllPoints()
  ownWinTrans:SetPoint("LEFT", ownWinCB, "RIGHT", -240, 0)
  ownWinTrans:SetPoint("RIGHT", ownWinRow, "RIGHT", -15, 0); ownWinTrans:SetHeight(28)
  if ownWinTrans.Label then ownWinTrans.Label:Hide() end
  ownWinTrans.option = "lootWinTransparency"; ownWinTrans._isPercent = true
  ownWinTrans:SetShown(DB("lootOwnWindow") == true)
  ownWinRow._transSlider = ownWinTrans
  table.insert(allFrames, ownWinRow)

  -- ── Enable Session Stats + transparency ──────────────────
  local statsRow = CreateFrame("Frame", nil, scrollChild); statsRow:SetHeight(28)
  local statsCB = NS.ChatGetCheckbox(statsRow, "Enable Session Stats", 28, function(state)
    DBSet("showStatsBtn", state)
    statsRow._transSlider:SetShown(state); RepositionAll()
    if not state and NS.statsWin then NS.statsWin:Hide() end
    if NS.LayoutBarButtons then NS.LayoutBarButtons() end
  end, "Show session statistics window")
  statsCB.option = "showStatsBtn"
  statsCB:SetParent(statsRow); statsCB:ClearAllPoints()
  statsCB:SetPoint("TOPLEFT", statsRow, "TOPLEFT", 0, 0); statsCB:SetSize(320, 28)
  if statsCB._highlight then
    statsCB._highlight:ClearAllPoints()
    statsCB._highlight:SetAllPoints(statsRow)
  end

  local statsTrans = NS.ChatGetSlider(statsRow, "", 0, 100, "%d%%", function(value)
    DBSet("statsTransparency", value / 100)
    NS.ApplyAlpha()
  end)
  statsTrans:ClearAllPoints()
  statsTrans:SetPoint("LEFT", statsCB, "RIGHT", -240, 0)
  statsTrans:SetPoint("RIGHT", statsRow, "RIGHT", -15, 0); statsTrans:SetHeight(28)
  if statsTrans.Label then statsTrans.Label:Hide() end
  statsTrans.option = "statsTransparency"; statsTrans._isPercent = true
  statsTrans:SetShown(DB("showStatsBtn") ~= false)
  statsRow._transSlider = statsTrans
  table.insert(allFrames, statsRow)

  local zoneResetCB = NS.ChatGetCheckbox(scrollChild, "Reset Stats on Zone Change (Open World)", 28, function(state)
    DBSet("statsResetOnZone", state)
  end, "Archive and reset session stats when changing zones in the open world")
  zoneResetCB.option = "statsResetOnZone"
  table.insert(allFrames, zoneResetCB)

  -- ── Enable Loot Rolls + transparency ──────────────────
  local rollsRow = CreateFrame("Frame", nil, scrollChild); rollsRow:SetHeight(28)
  local rollsCB = NS.ChatGetCheckbox(rollsRow, "Enable Loot Rolls", 28, function(state)
    DBSet("showRollsBtn", state)
    rollsRow._transSlider:SetShown(state); RepositionAll()
    if not state and NS.rollWin then NS.rollWin:Hide() end
    if NS.LayoutBarButtons then NS.LayoutBarButtons() end
  end, "Show loot rolls tracking window")
  rollsCB.option = "showRollsBtn"
  rollsCB:SetParent(rollsRow); rollsCB:ClearAllPoints()
  rollsCB:SetPoint("TOPLEFT", rollsRow, "TOPLEFT", 0, 0); rollsCB:SetSize(320, 28)
  if rollsCB._highlight then
    rollsCB._highlight:ClearAllPoints()
    rollsCB._highlight:SetAllPoints(rollsRow)
  end

  local rollsTrans = NS.ChatGetSlider(rollsRow, "", 0, 100, "%d%%", function(value)
    DBSet("rollsTransparency", value / 100)
    NS.ApplyAlpha()
  end)
  rollsTrans:ClearAllPoints()
  rollsTrans:SetPoint("LEFT", rollsCB, "RIGHT", -240, 0)
  rollsTrans:SetPoint("RIGHT", rollsRow, "RIGHT", -15, 0); rollsTrans:SetHeight(28)
  if rollsTrans.Label then rollsTrans.Label:Hide() end
  rollsTrans.option = "rollsTransparency"; rollsTrans._isPercent = true
  rollsTrans:SetShown(DB("showRollsBtn") ~= false)
  rollsRow._transSlider = rollsTrans
  table.insert(allFrames, rollsRow)

  -- ── Roll close mode ──────────────────
  local rollDelay
  local rollCloseMode = NS.ChatGetDropdown(scrollChild, "Roll close mode", function(value)
    return (DB("rollCloseMode") or "timer") == value
  end, function(value)
    DBSet("rollCloseMode", value)
    if rollDelay then rollDelay:SetShown(value == "timer") end
    RepositionAll()
  end)
  rollCloseMode:Init({"Auto (Timer)", "Manual"}, {"timer", "manual"})
  table.insert(allFrames, rollCloseMode)

  -- Roll close delay
  rollDelay = NS.ChatGetSlider(scrollChild, "Roll close delay", 5, 120, "%ss", function()
    DBSet("rollCloseDelay", rollDelay:GetValue())
  end)
  rollDelay.option = "rollCloseDelay"
  rollDelay:SetShown((DB("rollCloseMode") or "timer") == "timer")
  table.insert(allFrames, rollDelay)

  -- ── Loot Settings (visible only when loot tracker is active) ──────────────────
  local lootSettingsHeader = NS.ChatGetHeader(scrollChild, "Loot Settings")
  table.insert(allFrames, lootSettingsHeader)
  table.insert(lootSettingsItems, lootSettingsHeader)

  local showMoney = NS.ChatGetCheckbox(scrollChild, "Show gold / silver / copper", 28, function(state) DBSet("showMoney", state) end, "Show gold loot")
  showMoney.option = "showMoney"
  table.insert(allFrames, showMoney); table.insert(lootSettingsItems, showMoney)

  local showCurrency = NS.ChatGetCheckbox(scrollChild, "Show currency", 28, function(state) DBSet("showCurrency", state) end)
  showCurrency.option = "showCurrency"
  table.insert(allFrames, showCurrency); table.insert(lootSettingsItems, showCurrency)

  local showGroup, onlyOwn
  showGroup = NS.ChatGetCheckbox(scrollChild, "Show group loot", 28, function(state)
    DBSet("showGroupLoot", state)
    if state then DBSet("showOnlyOwnLoot", false); onlyOwn:SetValue(false) end
  end)
  showGroup.option = "showGroupLoot"
  table.insert(allFrames, showGroup); table.insert(lootSettingsItems, showGroup)

  onlyOwn = NS.ChatGetCheckbox(scrollChild, "Only my own loot", 28, function(state)
    DBSet("showOnlyOwnLoot", state)
    if state then DBSet("showGroupLoot", false); showGroup:SetValue(false) end
  end)
  onlyOwn.option = "showOnlyOwnLoot"
  table.insert(allFrames, onlyOwn); table.insert(lootSettingsItems, onlyOwn)

  local showRealm = NS.ChatGetCheckbox(scrollChild, "Show realm name", 28, function(state) DBSet("showRealmName", state) end)
  showRealm.option = "showRealmName"
  table.insert(allFrames, showRealm); table.insert(lootSettingsItems, showRealm)

  -- Quality filter header + buttons
  local qualHeader = NS.ChatGetHeader(scrollChild, "Minimum Quality")
  table.insert(allFrames, qualHeader); table.insert(lootSettingsItems, qualHeader)

  local qualHolder = CreateFrame("Frame", nil, scrollChild)
  qualHolder:SetHeight(28)
  table.insert(allFrames, qualHolder); table.insert(lootSettingsItems, qualHolder)

  local qualNames = {"All", "Common+", "Uncommon+", "Rare+", "Epic+", "Legendary+"}
  local qualColors = {{1,1,1},{0.62,0.62,0.62},{0.12,1,0},{0,0.44,0.87},{0.64,0.21,0.93},{1,0.5,0}}
  local qualBtns = {}
  local qualBtnW, qualGap = 80, 3
  local qualStartX = (540 - 6 * qualBtnW - 5 * qualGap) / 2
  local function RefreshQualButtons()
    local cur = DB("minQuality") or 0
    for _, qb2 in ipairs(qualBtns) do
      local act = cur == qb2.q
      local c2 = qualColors[qb2.q+1]
      qb2.btn:SetBackdropBorderColor(act and c2[1] or 0.22, act and c2[2] or 0.22, act and c2[3] or 0.22, 1)
    end
  end
  for qi = 0, 5 do
    local qc = qualColors[qi+1]
    local qb = CreateFrame("Button", nil, qualHolder, "BackdropTemplate")
    qb:SetSize(qualBtnW, 20)
    qb:SetPoint("TOPLEFT", qualHolder, "TOPLEFT", qualStartX + qi * (qualBtnW + qualGap), -4)
    qb:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
    qb:SetBackdropColor(0.08,0.08,0.08,1); qb:SetBackdropBorderColor(0.22,0.22,0.22,1)
    local ql = qb:CreateFontString(nil,"OVERLAY")
    ql:SetFont("Fonts/FRIZQT__.TTF",10,""); ql:SetPoint("CENTER"); ql:SetTextColor(qc[1],qc[2],qc[3],1); ql:SetText(qualNames[qi+1])
    local capQ = qi
    qb:SetScript("OnEnter", function() qb:SetBackdropBorderColor(qc[1],qc[2],qc[3],1) end)
    qb:SetScript("OnLeave", function() local a=(DB("minQuality") or 0)==capQ; qb:SetBackdropBorderColor(a and qc[1] or 0.22, a and qc[2] or 0.22, a and qc[3] or 0.22, 1) end)
    qb:SetScript("OnClick", function() DBSet("minQuality", capQ); RefreshQualButtons() end)
    table.insert(qualBtns, {btn=qb, q=capQ})
  end

  local clearDD = NS.ChatGetDropdown(scrollChild, "Clear loot history", function(value)
    if value == "reload" then return DB("clearOnReload") == true
    elseif value == "login" then return DB("clearOnLogin") == true
    else return not DB("clearOnReload") and not DB("clearOnLogin") end
  end, function(value)
    DBSet("clearOnReload", value == "reload")
    DBSet("clearOnLogin", value == "login")
  end)
  clearDD:Init({"Never", "On reload", "On login"}, {"never", "reload", "login"})
  table.insert(allFrames, clearDD); table.insert(lootSettingsItems, clearDD)

  RefreshLootSettingsVisibility = function()
    local lootActive = DB("lootInChatTab") == true or DB("lootOwnWindow") == true
    for _, f in ipairs(lootSettingsItems) do f:SetShown(lootActive) end

    -- Dim and disable Session Stats and Loot Rolls when no loot tracker is active
    local dimAlpha = lootActive and 1.0 or 0.35
    local function SetInteractive(frame, enabled)
      if not frame then return end
      frame:SetAlpha(enabled and 1.0 or dimAlpha)
      frame:EnableMouse(enabled)
    end
    -- Disable the checkboxes via their _hit frames and dim everything
    local function SetCBEnabled(cb, enabled)
      if not cb then return end
      cb:SetAlpha(enabled and 1.0 or dimAlpha)
      if cb._hit then cb._hit:EnableMouse(enabled) end
    end
    SetCBEnabled(statsCB, lootActive)
    SetCBEnabled(zoneResetCB, lootActive)
    SetCBEnabled(rollsCB, lootActive)
    -- Dim and disable rows, sliders, dropdowns
    SetInteractive(statsRow, lootActive)
    SetInteractive(rollsRow, lootActive)
    SetInteractive(rollCloseMode, lootActive)
    SetInteractive(rollDelay, lootActive)
    if statsRow._transSlider then SetInteractive(statsRow._transSlider, lootActive) end
    if rollsRow._transSlider then SetInteractive(rollsRow._transSlider, lootActive) end

    -- Show/hide warning text between loot toggles and dependent options
    if not scrollChild._lootWarnFrame then
      local warnFrame = CreateFrame("Frame", nil, scrollChild)
      warnFrame:SetHeight(20)
      local warn = warnFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      warn:SetPoint("LEFT", 20, 0)
      warn:SetFont(warn:GetFont(), 11, "")
      warn:SetTextColor(1, 0.82, 0, 0.9)
      warn:SetText("Requires LootTracker in Chat Tab or own Window")
      scrollChild._lootWarnFrame = warnFrame
      -- Insert into allFrames right after ownWinRow
      for i, f in ipairs(allFrames) do
        if f == ownWinRow then
          table.insert(allFrames, i + 1, warnFrame)
          break
        end
      end
    end
    scrollChild._lootWarnFrame:SetShown(not lootActive)

    RepositionAll()
  end

  C_Timer.After(0, RepositionAll)

  container:SetScript("OnShow", function()
    -- Top-level checkboxes
    for _, f in ipairs(allFrames) do
      if f.SetValue and f.option then f:SetValue(DB(f.option)) end
    end
    -- Checkboxes inside rows
    enableLoot:SetValue(DB("lootInChatTab") == true)
    ownWinCB:SetValue(DB("lootOwnWindow") == true)
    statsCB:SetValue(DB("showStatsBtn") ~= false)
    rollsCB:SetValue(DB("showRollsBtn") ~= false)
    -- Transparency sliders
    if ownWinRow._transSlider then
      ownWinRow._transSlider:SetShown(DB("lootOwnWindow") == true)
      if ownWinRow._transSlider._isPercent and ownWinRow._transSlider.option then
        ownWinRow._transSlider:SetValue((DB(ownWinRow._transSlider.option) or 0) * 100)
      end
    end
    if statsRow._transSlider then
      statsRow._transSlider:SetShown(DB("showStatsBtn") ~= false)
      if statsRow._transSlider._isPercent and statsRow._transSlider.option then
        statsRow._transSlider:SetValue((DB(statsRow._transSlider.option) or 0) * 100)
      end
    end
    if rollsRow._transSlider then
      rollsRow._transSlider:SetShown(DB("showRollsBtn") ~= false)
      if rollsRow._transSlider._isPercent and rollsRow._transSlider.option then
        rollsRow._transSlider:SetValue((DB(rollsRow._transSlider.option) or 0) * 100)
      end
    end
    -- Loot settings items
    for _, f in ipairs(lootSettingsItems) do
      if f.SetValue and f.option then f:SetValue(DB(f.option)) end
    end
    rollDelay:SetShown((DB("rollCloseMode") or "timer") == "timer")
    RefreshQualButtons()
    RefreshLootSettingsVisibility()
  end)

  return container
end

-- ══════════════════════════════════════════════════════════════════════
-- TAB 7: QoL
-- ══════════════════════════════════════════════════════════════════════
local function SetupQoL(parent)
  local container = CreateFrame("Frame", nil, parent)
  local scrollFrame = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
  scrollFrame:SetPoint("TOPLEFT", 0, 0); scrollFrame:SetPoint("BOTTOMRIGHT", -24, 0)
  local scrollChild = CreateFrame("Frame", nil, scrollFrame)
  scrollChild:SetWidth(600)
  scrollFrame:SetScrollChild(scrollChild)
  scrollFrame:HookScript("OnSizeChanged", function(_, w) scrollChild:SetWidth(w) end)
  if scrollFrame.ScrollBar then scrollFrame.ScrollBar:SetAlpha(0.5) end
  NS.AddSmoothScroll(scrollFrame)

  local allFrames = {}
  local sections = {}
  local currentSection = nil
  local SLIDE_SPEED = 400
  local RepositionAll

  -- Optimal FPS CVars
  local OPTIMAL_FPS_CVARS = {
    {cvar="renderScale",optimal="1"},{cvar="VSync",optimal="0"},{cvar="MSAAQuality",optimal="0"},
    {cvar="LowLatencyMode",optimal="3"},{cvar="ffxAntiAliasingMode",optimal="4"},
    {cvar="graphicsShadowQuality",optimal="1"},{cvar="graphicsLiquidDetail",optimal="2"},
    {cvar="graphicsParticleDensity",optimal="3"},{cvar="graphicsSSAO",optimal="0"},
    {cvar="graphicsDepthEffects",optimal="0"},{cvar="graphicsComputeEffects",optimal="0"},
    {cvar="graphicsOutlineMode",optimal="2"},{cvar="graphicsTextureResolution",optimal="2"},
    {cvar="graphicsSpellDensity",optimal="0"},{cvar="graphicsProjectedTextures",optimal="1"},
    {cvar="graphicsViewDistance",optimal="3"},{cvar="graphicsEnvironmentDetail",optimal="3"},
    {cvar="graphicsGroundClutter",optimal="0"},{cvar="GxMaxFrameLatency",optimal="2"},
    {cvar="TextureFilteringMode",optimal="5"},{cvar="shadowRt",optimal="0"},
    {cvar="ResampleQuality",optimal="3"},{cvar="GxApi",optimal="D3D12"},
    {cvar="physicsLevel",optimal="1"},{cvar="useTargetFPS",optimal="0"},
    {cvar="useMaxFPSBk",optimal="1"},{cvar="maxFPSBk",optimal="30"},
    {cvar="ResampleSharpness",optimal="0"},
  }

  -- Styled button helper
  local function CreateStyledButton(par, text, width)
    local btn = CreateFrame("Button", nil, par, "BackdropTemplate")
    btn:SetSize(width, 22)
    btn:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8",edgeFile="Interface/Buttons/WHITE8X8",edgeSize=1})
    btn:SetBackdropColor(0.08,0.08,0.08,1); btn:SetBackdropBorderColor(0.22,0.22,0.22,1)
    local lbl = btn:CreateFontString(nil,"OVERLAY")
    lbl:SetFont("Fonts/FRIZQT__.TTF",11,""); lbl:SetPoint("CENTER"); lbl:SetTextColor(1,1,1); lbl:SetText(text)
    btn._label = lbl
    btn:SetScript("OnEnter", function() local r,g,b = NS.ChatGetAccentRGB(); btn:SetBackdropBorderColor(r,g,b,1) end)
    btn:SetScript("OnLeave", function() btn:SetBackdropBorderColor(0.22,0.22,0.22,1); GameTooltip:Hide() end)
    return btn
  end

  -- Pair row helper (two widgets side by side)
  local function MakePairRow(par, cb1, cb2)
    local row = CreateFrame("Frame", nil, par); row:SetHeight(22)
    cb1:SetParent(row); cb1:ClearAllPoints()
    cb1:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0); cb1:SetPoint("TOPRIGHT", row, "TOP", -2, 0)
    if cb2 then
      cb2:SetParent(row); cb2:ClearAllPoints()
      cb2:SetPoint("TOPLEFT", row, "TOP", 2, 0); cb2:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
    end
    return row
  end

  -- Collapsible header helper
  local function AddCollapsibleHeader(text)
    local hdr = NS.ChatGetHeader(scrollChild, text)
    hdr._sectionText = text
    local clip = CreateFrame("Frame", nil, scrollChild)
    clip:SetClipsChildren(true); clip:SetHeight(0)
    local clipInner = CreateFrame("Frame", nil, clip)
    clipInner:SetPoint("TOPLEFT"); clipInner:SetPoint("TOPRIGHT")
    local section = {header=hdr, clip=clip, clipInner=clipInner, children={}, collapsed=true, targetH=0}
    table.insert(sections, section); table.insert(allFrames, hdr); table.insert(allFrames, clip)
    currentSection = section
    local function AnimateClip(toH)
      clip:SetScript("OnUpdate", function(self, elapsed)
        local curH = self:GetHeight(); local diff = toH - curH
        if math.abs(diff) < 1 then
          self:SetHeight(toH); self:SetScript("OnUpdate", nil)
          if toH == 0 then clipInner:Hide() end; RepositionAll(); return
        end
        self:SetHeight(curH + (diff > 0 and math.min(SLIDE_SPEED*elapsed, diff) or math.max(-SLIDE_SPEED*elapsed, diff)))
        RepositionAll()
      end)
    end
    local hit = CreateFrame("Frame", nil, hdr)
    hit:SetAllPoints(); hit:EnableMouse(true); hit:SetFrameLevel(hdr:GetFrameLevel() + 5)
    hit:SetScript("OnMouseDown", function()
      section.collapsed = not section.collapsed
      local hex = NS.ChatGetAccentHex()
      local arrow = section.collapsed and ">" or "v"
      hdr.text:SetText("|cff"..hex..arrow.."|r |cff808080"..text.."|r")
      if section.collapsed then AnimateClip(0) else clipInner:Show(); AnimateClip(section.targetH) end
    end)
    return hdr
  end

  local function AddToSection(frame)
    if currentSection then
      frame:SetParent(currentSection.clipInner)
      table.insert(currentSection.children, frame)
    else
      table.insert(allFrames, frame)
    end
  end

  -- ── System Optimization ─────────────────────────────────────────────
  AddCollapsibleHeader("System Optimization")

  local btnRow = CreateFrame("Frame", nil, scrollChild); btnRow:SetHeight(22)
  local fpsBtn = CreateStyledButton(btnRow, "Optimal FPS Settings", 200)
  fpsBtn:SetPoint("TOPLEFT", btnRow, "TOPLEFT", 30, 0)
  local restoreBtn = CreateStyledButton(btnRow, "Restore", 100)
  restoreBtn:SetPoint("LEFT", fpsBtn, "RIGHT", 6, 0)
  local statusBtn = CreateFrame("Button", nil, btnRow)
  statusBtn:SetPoint("LEFT", restoreBtn, "RIGHT", 10, 0)
  local fpsStatus = statusBtn:CreateFontString(nil, "OVERLAY")
  fpsStatus:SetFont("Fonts/FRIZQT__.TTF", 10, ""); fpsStatus:SetPoint("LEFT")

  local mismatchedCVars = {}
  local function UpdateFPSStatus()
    local matching, total = 0, #OPTIMAL_FPS_CVARS
    wipe(mismatchedCVars)
    for _, s in ipairs(OPTIMAL_FPS_CVARS) do
      local ok, cur = pcall(C_CVar.GetCVar, s.cvar)
      if ok and tostring(cur) == s.optimal then matching = matching + 1
      else table.insert(mismatchedCVars, {cvar=s.cvar, current=ok and tostring(cur) or "?", optimal=s.optimal}) end
    end
    if matching == total then fpsStatus:SetTextColor(0,0.8,0); fpsStatus:SetText(L["Applied"])
    else fpsStatus:SetTextColor(0.6,0.6,0.6); fpsStatus:SetText(matching.."/"..total) end
    statusBtn:SetSize(fpsStatus:GetStringWidth()+4, 20)
    restoreBtn:SetShown(LucidUIDB and LucidUIDB._savedCVars ~= nil)
  end

  statusBtn:SetScript("OnEnter", function()
    if #mismatchedCVars == 0 then return end
    GameTooltip:SetOwner(statusBtn, "ANCHOR_RIGHT")
    for _, info in ipairs(mismatchedCVars) do
      GameTooltip:AddDoubleLine(info.cvar, info.current.." |cff00cc00->|r "..info.optimal, 0.8,0.8,0.8, 0.6,0.6,0.6)
    end; GameTooltip:Show()
  end)
  statusBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  fpsBtn:HookScript("OnEnter", function()
    GameTooltip:SetOwner(fpsBtn, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Apply optimized graphics settings for maximum FPS.\nSaves your current settings for restoring later.", 0.7,0.7,0.7, true)
    GameTooltip:Show()
  end)
  restoreBtn:HookScript("OnEnter", function()
    GameTooltip:SetOwner(restoreBtn, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Restore your previously saved graphics settings.", 0.7,0.7,0.7, true)
    GameTooltip:Show()
  end)

  StaticPopupDialogs["LUCIDUI_FPS_RELOAD"] = {
    text = "Optimal FPS settings applied. Reload UI to take full effect?",
    button1 = ACCEPT, button2 = CANCEL,
    OnAccept = function() ReloadUI() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  }

  fpsBtn:SetScript("OnClick", function()
    LucidUIDB._savedCVars = {}
    for _, s in ipairs(OPTIMAL_FPS_CVARS) do
      local ok, cur = pcall(C_CVar.GetCVar, s.cvar)
      if ok and cur then LucidUIDB._savedCVars[s.cvar] = tostring(cur) end
    end
    local count = 0
    for _, s in ipairs(OPTIMAL_FPS_CVARS) do
      if pcall(C_CVar.SetCVar, s.cvar, s.optimal) then count = count + 1 end
    end
    print("|cff3bd2ed[LucidUI]|r Optimal FPS settings applied! ("..count.."/"..#OPTIMAL_FPS_CVARS..")")
    UpdateFPSStatus(); StaticPopup_Show("LUCIDUI_FPS_RELOAD")
  end)
  restoreBtn:SetScript("OnClick", function()
    if LucidUIDB and LucidUIDB._savedCVars then
      local restored = 0
      for cvar, value in pairs(LucidUIDB._savedCVars) do
        if pcall(C_CVar.SetCVar, cvar, value) then restored = restored + 1 end
      end
      LucidUIDB._savedCVars = nil
      print("|cff3bd2ed[LucidUI]|r Previous settings restored. ("..restored..")")
      UpdateFPSStatus(); StaticPopup_Show("LUCIDUI_FPS_RELOAD")
    end
  end)
  AddToSection(btnRow)

  -- ── Mouse Ring ───────────────────────────────────────────────────────
  AddCollapsibleHeader("Mouse Ring")

  local enableRing = NS.ChatGetCheckbox(scrollChild, "Enable Mouse Ring", 22, function(state)
    DBSet("qolMouseRing", state)
  end, "Show a ring texture that follows the cursor")
  enableRing.option = "qolMouseRing"

  local ringColorRow = CreateFrame("Frame", nil, scrollChild); ringColorRow:SetHeight(22)
  ringColorRow:SetPoint("LEFT", scrollChild, "LEFT", 30, 0); ringColorRow:SetPoint("RIGHT", scrollChild, "RIGHT", -15, 0)
  local ringColorSw = CreateFrame("Frame", nil, ringColorRow, "BackdropTemplate")
  ringColorSw:SetSize(13, 13); ringColorSw:SetPoint("LEFT", 20, 0)
  ringColorSw:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
  ringColorSw:SetBackdropBorderColor(0.28, 0.28, 0.28, 1)
  ringColorSw:SetBackdropColor(DB("qolRingColorR") or 0, DB("qolRingColorG") or 0.8, DB("qolRingColorB") or 0.8, 1)
  local ringColorLbl = ringColorRow:CreateFontString(nil, "OVERLAY")
  ringColorLbl:SetFont("Fonts/FRIZQT__.TTF", 11, ""); ringColorLbl:SetPoint("LEFT", ringColorSw, "RIGHT", 6, 0)
  ringColorLbl:SetTextColor(1, 1, 1); ringColorLbl:SetText(L["Ring Color"])
  local ringColorHL = ringColorRow:CreateTexture(nil, "BACKGROUND")
  ringColorHL:SetPoint("TOPLEFT", 18, 0); ringColorHL:SetPoint("BOTTOMRIGHT", -40, 0)
  ringColorHL:SetColorTexture(1, 1, 1, 0.05); ringColorHL:Hide()
  local ringColorHit = CreateFrame("Frame", nil, ringColorRow)
  ringColorHit:SetAllPoints(ringColorRow); ringColorHit:EnableMouse(true)
  ringColorHit:SetFrameLevel(ringColorSw:GetFrameLevel() + 3)
  ringColorHit:SetScript("OnMouseDown", function()
    local cr, cg, cb = DB("qolRingColorR") or 0, DB("qolRingColorG") or 0.8, DB("qolRingColorB") or 0.8
    local oR, oG, oB = cr, cg, cb
    ColorPickerFrame:SetupColorPickerAndShow({r=cr, g=cg, b=cb,
      swatchFunc = function()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        DBSet("qolRingColorR", r); DBSet("qolRingColorG", g); DBSet("qolRingColorB", b)
        ringColorSw:SetBackdropColor(r, g, b, 1)
      end,
      cancelFunc = function()
        DBSet("qolRingColorR", oR); DBSet("qolRingColorG", oG); DBSet("qolRingColorB", oB)
        ringColorSw:SetBackdropColor(oR, oG, oB, 1)
      end,
    })
  end)
  ringColorHit:SetScript("OnEnter", function() ringColorHL:Show(); ringColorSw:SetBackdropBorderColor(NS.ChatGetAccentRGB()) end)
  ringColorHit:SetScript("OnLeave", function() ringColorHL:Hide(); ringColorSw:SetBackdropBorderColor(0.28, 0.28, 0.28, 1) end)
  AddToSection(MakePairRow(scrollChild, enableRing, ringColorRow))

  local hideRMB = NS.ChatGetCheckbox(scrollChild, "Hide on RMB", 22, function(state)
    DBSet("qolMouseRingHideRMB", state)
  end, "Hide the ring while holding right mouse button")
  hideRMB.option = "qolMouseRingHideRMB"
  local showOOC = NS.ChatGetCheckbox(scrollChild, "Visible outside Combat", 22, function(state)
    DBSet("qolMouseRingShowOOC", state)
  end, "Show the ring when not in combat")
  showOOC.option = "qolMouseRingShowOOC"
  AddToSection(MakePairRow(scrollChild, hideRMB, showOOC))

  local RING_SHAPES = {
    {name="Ring", file="ring.tga"}, {name="Thin Ring", file="thin_ring.tga"},
    {name="Thick Ring", file="thick_ring.tga"}, {name="Circle", file="circle.tga"},
    {name="Glow", file="glow.tga"}, {name="Soft Ring", file="ring_soft1.tga"},
  }
  local shapeNames, shapeValues = {}, {}
  for _, s2 in ipairs(RING_SHAPES) do table.insert(shapeNames, s2.name); table.insert(shapeValues, s2.file) end
  local shapeDD = NS.ChatGetDropdown(scrollChild, "Ring Shape", function(value)
    return (DB("qolMouseRingShape") or "ring.tga") == value
  end, function(value) DBSet("qolMouseRingShape", value) end)
  shapeDD:Init(shapeNames, shapeValues)
  shapeDD.option = "qolMouseRingShape"
  AddToSection(shapeDD)

  local ringSize = NS.ChatGetSlider(scrollChild, "Ring Size", 16, 128, "%d", function(value)
    DBSet("qolMouseRingSize", value)
  end)
  ringSize.option = "qolMouseRingSize"
  AddToSection(ringSize)

  local ringOpacity = NS.ChatGetSlider(scrollChild, "Opacity", 0, 100, "%d%%", function(value)
    DBSet("qolMouseRingOpacity", value / 100)
  end)
  ringOpacity.option = "qolMouseRingOpacity"
  ringOpacity._isPercent = true
  AddToSection(ringOpacity)

  -- ── Combat Timer ────────────────────────────────────────────────────
  AddCollapsibleHeader("Combat Timer")

  local enableTimer = NS.ChatGetCheckbox(scrollChild, "Enable Combat Timer", 22, function(state)
    DBSet("qolCombatTimer", state)
  end, "Show elapsed combat time overlay")
  enableTimer.option = "qolCombatTimer"
  local instanceOnly = NS.ChatGetCheckbox(scrollChild, "Instance only", 22, function(state)
    DBSet("qolCombatTimerInstance", state)
  end, "Only show the timer inside instances")
  instanceOnly.option = "qolCombatTimerInstance"
  AddToSection(MakePairRow(scrollChild, enableTimer, instanceOnly))

  local hidePrefix = NS.ChatGetCheckbox(scrollChild, "Hide \"COMBAT:\" prefix", 22, function(state)
    DBSet("qolCombatTimerHidePrefix", state)
  end, "Only show the elapsed time, no label")
  hidePrefix.option = "qolCombatTimerHidePrefix"
  local showTimerBg = NS.ChatGetCheckbox(scrollChild, "Show background", 22, function(state)
    DBSet("qolCombatTimerShowBg", state)
  end, "Show a dark background behind the timer")
  showTimerBg.option = "qolCombatTimerShowBg"
  AddToSection(MakePairRow(scrollChild, hidePrefix, showTimerBg))

  -- Timer color + unlock position row
  local timerColorRow = CreateFrame("Frame", nil, scrollChild); timerColorRow:SetHeight(22)
  local timerSwatch = CreateFrame("Frame", nil, timerColorRow, "BackdropTemplate")
  timerSwatch:SetSize(13,13); timerSwatch:SetPoint("LEFT", 20, 0)
  timerSwatch:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8",edgeFile="Interface/Buttons/WHITE8X8",edgeSize=1})
  timerSwatch:SetBackdropBorderColor(0.28,0.28,0.28,1)
  timerSwatch:SetBackdropColor(DB("qolTimerColorR") or 1, DB("qolTimerColorG") or 1, DB("qolTimerColorB") or 1, 1)
  local timerColorLbl = timerColorRow:CreateFontString(nil,"OVERLAY")
  timerColorLbl:SetFont("Fonts/FRIZQT__.TTF",11,""); timerColorLbl:SetPoint("LEFT", timerSwatch, "RIGHT", 6, 0)
  timerColorLbl:SetTextColor(1,1,1); timerColorLbl:SetText(L["Timer Color"])
  local timerColorHL = timerColorRow:CreateTexture(nil,"BACKGROUND")
  timerColorHL:SetPoint("TOPLEFT",18,0); timerColorHL:SetPoint("BOTTOMRIGHT",-40,0)
  timerColorHL:SetColorTexture(1,1,1,0.05); timerColorHL:Hide()
  local timerHit = CreateFrame("Frame", nil, timerColorRow)
  timerHit:SetAllPoints(timerColorRow); timerHit:EnableMouse(true); timerHit:SetFrameLevel(timerSwatch:GetFrameLevel()+3)
  timerHit:SetScript("OnMouseDown", function()
    local cr,cg,cb = DB("qolTimerColorR") or 1, DB("qolTimerColorG") or 1, DB("qolTimerColorB") or 1
    local oR,oG,oB = cr,cg,cb
    ColorPickerFrame:SetupColorPickerAndShow({r=cr,g=cg,b=cb,
      swatchFunc=function()
        local r,g,b = ColorPickerFrame:GetColorRGB()
        DBSet("qolTimerColorR",r); DBSet("qolTimerColorG",g); DBSet("qolTimerColorB",b)
        timerSwatch:SetBackdropColor(r,g,b,1)
      end,
      cancelFunc=function()
        DBSet("qolTimerColorR",oR); DBSet("qolTimerColorG",oG); DBSet("qolTimerColorB",oB)
        timerSwatch:SetBackdropColor(oR,oG,oB,1)
      end,
    })
  end)
  timerHit:SetScript("OnEnter", function() timerColorHL:Show(); timerSwatch:SetBackdropBorderColor(NS.ChatGetAccentRGB()) end)
  timerHit:SetScript("OnLeave", function() timerColorHL:Hide(); timerSwatch:SetBackdropBorderColor(0.28,0.28,0.28,1) end)

  local timerLockWrap = CreateFrame("Frame", nil, scrollChild); timerLockWrap:SetHeight(22)
  local timerLockBtn = CreateStyledButton(timerLockWrap, L["Unlock Position"], 150)
  timerLockBtn:SetParent(timerLockWrap); timerLockBtn:ClearAllPoints()
  timerLockBtn:SetPoint("LEFT", timerLockWrap, "LEFT", 20, 0)
  local timerUnlocked = false
  timerLockBtn:SetScript("OnClick", function()
    timerUnlocked = not timerUnlocked
    timerLockBtn._label:SetText(timerUnlocked and L["Lock Position"] or L["Unlock Position"])
    if NS.QoL and NS.QoL.CombatTimer and NS.QoL.CombatTimer.SetUnlocked then
      NS.QoL.CombatTimer.SetUnlocked(timerUnlocked)
    end
  end)
  AddToSection(MakePairRow(scrollChild, timerColorRow, timerLockWrap))

  local timerFontSize = NS.ChatGetSlider(scrollChild, "Font Size", 10, 60, "%d", function(value)
    DBSet("qolTimerFontSize", value)
    if NS.QoL and NS.QoL.CombatTimer and NS.QoL.CombatTimer.RefreshSettings then
      NS.QoL.CombatTimer.RefreshSettings()
    end
  end)
  timerFontSize.option = "qolTimerFontSize"
  AddToSection(timerFontSize)

  -- ── Combat Alert ────────────────────────────────────────────────────
  AddCollapsibleHeader("Combat Alert")

  local enableAlert = NS.ChatGetCheckbox(scrollChild, "Enable Combat Alert", 22, function(state)
    DBSet("qolCombatAlert", state)
  end, "Show text flash when entering/leaving combat")
  enableAlert.option = "qolCombatAlert"
  local alertLockWrap = CreateFrame("Frame", nil, scrollChild); alertLockWrap:SetHeight(22)
  local alertLockBtn = CreateStyledButton(alertLockWrap, L["Unlock Position"], 150)
  alertLockBtn:SetParent(alertLockWrap); alertLockBtn:ClearAllPoints()
  alertLockBtn:SetPoint("LEFT", alertLockWrap, "LEFT", 20, 0)
  local alertUnlocked = false
  alertLockBtn:SetScript("OnClick", function()
    alertUnlocked = not alertUnlocked
    alertLockBtn._label:SetText(alertUnlocked and L["Lock Position"] or L["Unlock Position"])
    if NS.QoL and NS.QoL.CombatAlert and NS.QoL.CombatAlert.SetUnlocked then
      NS.QoL.CombatAlert.SetUnlocked(alertUnlocked)
    end
  end)
  AddToSection(MakePairRow(scrollChild, enableAlert, alertLockWrap))

  -- Alert enter/leave rows with color swatch + text editbox
  local function MakeAlertRow(par, label, textKey, rKey, gKey, bKey, defText, defR, defG, defB)
    local row = CreateFrame("Frame", nil, par); row:SetHeight(24)
    local sw = CreateFrame("Frame", nil, row, "BackdropTemplate")
    sw:SetSize(13,13); sw:SetPoint("LEFT", 20, 0)
    sw:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8",edgeFile="Interface/Buttons/WHITE8X8",edgeSize=1})
    sw:SetBackdropBorderColor(0.28,0.28,0.28,1)
    sw:SetBackdropColor(DB(rKey) or defR, DB(gKey) or defG, DB(bKey) or defB, 1)
    local swHit = CreateFrame("Frame", nil, row)
    swHit:SetSize(13,13); swHit:SetAllPoints(sw); swHit:EnableMouse(true)
    swHit:SetFrameLevel(sw:GetFrameLevel()+3)
    swHit:SetScript("OnEnter", function() sw:SetBackdropBorderColor(NS.ChatGetAccentRGB()) end)
    swHit:SetScript("OnLeave", function() sw:SetBackdropBorderColor(0.28,0.28,0.28,1) end)
    swHit:SetScript("OnMouseDown", function()
      local cr,cg,cb = DB(rKey) or defR, DB(gKey) or defG, DB(bKey) or defB
      local oR,oG,oB = cr,cg,cb
      ColorPickerFrame:SetupColorPickerAndShow({r=cr,g=cg,b=cb,
        swatchFunc=function()
          local r,g,b = ColorPickerFrame:GetColorRGB()
          DBSet(rKey,r); DBSet(gKey,g); DBSet(bKey,b); sw:SetBackdropColor(r,g,b,1)
        end,
        cancelFunc=function()
          DBSet(rKey,oR); DBSet(gKey,oG); DBSet(bKey,oB); sw:SetBackdropColor(oR,oG,oB,1)
        end,
      })
    end)
    local lbl = row:CreateFontString(nil,"OVERLAY")
    lbl:SetFont("Fonts/FRIZQT__.TTF",11,""); lbl:SetPoint("LEFT", sw, "RIGHT", 6, 0)
    lbl:SetTextColor(0.7,0.7,0.7); lbl:SetText(label)
    local box = CreateFrame("EditBox", nil, row, "BackdropTemplate")
    box:SetHeight(20); box:SetPoint("LEFT", lbl, "RIGHT", 8, 0); box:SetPoint("RIGHT", row, "RIGHT", -5, 0)
    box:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8",edgeFile="Interface/Buttons/WHITE8X8",edgeSize=1})
    box:SetBackdropColor(0.1,0.1,0.1,1); box:SetBackdropBorderColor(0.22,0.22,0.22,1)
    box:SetFont("Fonts/FRIZQT__.TTF", 11, ""); box:SetAutoFocus(false)
    box:SetTextColor(1, 1, 1, 1)
    box:SetTextInsets(4,4,0,0); box:SetMaxLetters(30)
    box:SetText(DB(textKey) or defText)
    box:SetCursorPosition(0)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEditFocusLost", function(self)
      local val = strtrim(self:GetText())
      if val == "" then val = defText; self:SetText(val) end; DBSet(textKey, val)
    end)
    box:SetScript("OnEnter", function() box:SetBackdropBorderColor(NS.ChatGetAccentRGB()) end)
    box:SetScript("OnLeave", function() if not box:HasFocus() then box:SetBackdropBorderColor(0.22,0.22,0.22,1) end end)
    row._sw = sw; row._box = box
    return row
  end

  local enterRow = MakeAlertRow(scrollChild, "Enter:", "qolCombatEnterText", "qolAlertEnterR","qolAlertEnterG","qolAlertEnterB", "++Combat++", 1,0,0)
  local leaveRow = MakeAlertRow(scrollChild, "Leave:", "qolCombatLeaveText", "qolAlertLeaveR","qolAlertLeaveG","qolAlertLeaveB", "--Combat--", 0,1,0)
  local alertPairRow = MakePairRow(scrollChild, enterRow, leaveRow)
  alertPairRow:SetHeight(24)
  AddToSection(alertPairRow)

  local alertFontSize = NS.ChatGetSlider(scrollChild, "Font Size", 10, 60, "%d", function(value)
    DBSet("qolAlertFontSize", value)
    if NS.QoL and NS.QoL.CombatAlert and NS.QoL.CombatAlert.RefreshSettings then
      NS.QoL.CombatAlert.RefreshSettings()
    end
  end)
  alertFontSize.option = "qolAlertFontSize"
  AddToSection(alertFontSize)

  -- ── Items / Loot / Misc ─────────────────────────────────────────────
  AddCollapsibleHeader("Items / Loot / Misc")

  local fasterLoot = NS.ChatGetCheckbox(scrollChild, "Faster Auto Loot", 22, function(state) DBSet("qolFasterLoot", state) end, "Speed up auto-loot")
  fasterLoot.option = "qolFasterLoot"
  local suppressWarn = NS.ChatGetCheckbox(scrollChild, "Suppress Loot Warnings", 22, function(state) DBSet("qolSuppressWarnings", state) end, "Auto-accept bind-on-pickup confirmations")
  suppressWarn.option = "qolSuppressWarnings"
  AddToSection(MakePairRow(scrollChild, fasterLoot, suppressWarn))

  local easyDestroy = NS.ChatGetCheckbox(scrollChild, "Easy Item Destroy", 22, function(state) DBSet("qolEasyDestroy", state) end, "Skip typing DELETE when destroying items")
  easyDestroy.option = "qolEasyDestroy"
  local autoKeystone = NS.ChatGetCheckbox(scrollChild, "Auto Insert Keystone", 22, function(state) DBSet("qolAutoKeystone", state) end, "Auto-slot keystone in M+ key UI")
  autoKeystone.option = "qolAutoKeystone"
  AddToSection(MakePairRow(scrollChild, easyDestroy, autoKeystone))

  local skipCine = NS.ChatGetCheckbox(scrollChild, "Skip Cinematics", 22, function(state) DBSet("qolSkipCinematics", state) end, "Automatically cancel in-game cinematics")
  skipCine.option = "qolSkipCinematics"
  local autoSell = NS.ChatGetCheckbox(scrollChild, "Auto Sell Grey Items", 22, function(state) DBSet("qolAutoSellGrey", state) end, "Sell all grey items at merchants")
  autoSell.option = "qolAutoSellGrey"
  AddToSection(MakePairRow(scrollChild, skipCine, autoSell))

  -- Auto repair row with inline dropdown
  local autoRepairRow = CreateFrame("Frame", nil, scrollChild); autoRepairRow:SetHeight(30)
  local autoRepairCB = NS.ChatGetCheckbox(autoRepairRow, "Auto Repair", 22, function(state) DBSet("qolAutoRepair", state) end, "Automatically repair at merchants")
  autoRepairCB.option = "qolAutoRepair"
  autoRepairCB:SetParent(autoRepairRow); autoRepairCB:ClearAllPoints()
  autoRepairCB:SetPoint("TOPLEFT", autoRepairRow, "TOPLEFT", 0, 0); autoRepairCB:SetPoint("RIGHT", autoRepairRow, "CENTER", -5, 0)

  local repairDD = CreateFrame("Frame", nil, autoRepairRow, "BackdropTemplate")
  repairDD:SetHeight(22); repairDD:SetPoint("LEFT", autoRepairRow, "CENTER", 5, 0); repairDD:SetPoint("RIGHT", autoRepairRow, "RIGHT", -5, 0)
  repairDD:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8",edgeFile="Interface/Buttons/WHITE8X8",edgeSize=1})
  repairDD:SetBackdropColor(0.08,0.08,0.08,1); repairDD:SetBackdropBorderColor(0.22,0.22,0.22,1)
  local repairText = repairDD:CreateFontString(nil,"OVERLAY")
  repairText:SetFont("Fonts/FRIZQT__.TTF",11,""); repairText:SetPoint("LEFT",8,0); repairText:SetPoint("RIGHT",-20,0)
  repairText:SetJustifyH("LEFT"); repairText:SetTextColor(1,1,1)
  local repairArrow = repairDD:CreateFontString(nil,"OVERLAY")
  repairArrow:SetFont("Fonts/FRIZQT__.TTF",11,""); repairArrow:SetPoint("RIGHT",-6,0)
  repairArrow:SetTextColor(0.5,0.5,0.5); repairArrow:SetText("v")
  local REPAIR_MODES = {{value="guild",label="Guild Bank first"},{value="own",label="Own Gold"}}
  local function RefreshRepairDD()
    local cur = DB("qolAutoRepairMode") or "guild"
    for _, m in ipairs(REPAIR_MODES) do if m.value == cur then repairText:SetText(m.label); return end end
    repairText:SetText(REPAIR_MODES[1].label)
  end
  RefreshRepairDD()
  repairDD:EnableMouse(true)
  repairDD:SetScript("OnMouseDown", function(self)
    if self._popup and self._popup:IsShown() then self._popup:Hide(); return end
    local popup = self._popup
    if not popup then
      popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
      popup:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8",edgeFile="Interface/Buttons/WHITE8X8",edgeSize=1})
      popup:SetBackdropColor(0.1,0.1,0.1,0.95); popup:SetBackdropBorderColor(0.22,0.22,0.22,1)
      popup:SetFrameStrata("TOOLTIP"); popup:SetClampedToScreen(true); self._popup = popup
      local closer = CreateFrame("Button", nil, popup)
      closer:SetAllPoints(UIParent); closer:SetFrameLevel(popup:GetFrameLevel()-1)
      closer:SetScript("OnClick", function() popup:Hide() end); popup._closer = closer
    end
    for _, child in pairs({popup:GetChildren()}) do
      if child ~= popup._closer then child:Hide(); child:SetParent(nil) end
    end
    local py = -4
    for _, m in ipairs(REPAIR_MODES) do
      local btn = CreateFrame("Button", nil, popup)
      btn:SetHeight(20); btn:SetPoint("TOPLEFT", popup, "TOPLEFT", 4, py); btn:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -4, py)
      btn:SetFrameLevel(popup:GetFrameLevel()+2)
      local txt = btn:CreateFontString(nil,"OVERLAY"); txt:SetFont("Fonts/FRIZQT__.TTF",11,"")
      txt:SetAllPoints(); txt:SetJustifyH("LEFT"); txt:SetTextColor(1,1,1); txt:SetText(m.label)
      local hl = btn:CreateTexture(nil,"HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1,1,1,0.08)
      local capVal = m.value
      btn:SetScript("OnClick", function() DBSet("qolAutoRepairMode", capVal); RefreshRepairDD(); popup:Hide() end)
      py = py - 20
    end
    popup:SetSize(self:GetWidth(), -py + 4)
    popup:ClearAllPoints(); popup:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2); popup:SetPoint("TOPRIGHT", self, "BOTTOMRIGHT", 0, -2)
    popup:Show()
  end)
  repairDD:SetScript("OnEnter", function() repairDD:SetBackdropBorderColor(NS.ChatGetAccentRGB()) end)
  repairDD:SetScript("OnLeave", function() repairDD:SetBackdropBorderColor(0.22,0.22,0.22,1) end)
  AddToSection(autoRepairRow)

  -- ── Layout ──────────────────────────────────────────────────────────
  RepositionAll = function()
    for _, section in ipairs(sections) do
      local iy2 = 0
      for _, child in ipairs(section.children) do
        child:ClearAllPoints()
        child:SetPoint("TOPLEFT", section.clipInner, "TOPLEFT", 0, -iy2)
        child:SetPoint("TOPRIGHT", section.clipInner, "TOPRIGHT", 0, -iy2)
        iy2 = iy2 + (child:GetHeight() or 20) + 2
      end
      section.targetH = iy2
      section.clipInner:SetHeight(math.max(iy2, 1))
    end
    local y = 0
    for _, f in ipairs(allFrames) do
      f:ClearAllPoints()
      f:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
      f:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -y)
      y = y + (f:GetHeight() or 0) + 2
    end
    scrollChild:SetHeight(math.max(y, 1))
  end

  container:SetScript("OnShow", function()
    local function RefreshWidget(w)
      if w.SetValue and w.option then
        local val = DB(w.option)
        if w._isPercent then w:SetValue((val or 0) * 100) else w:SetValue(val) end
      end
    end
    for _, section in ipairs(sections) do
      for _, child in ipairs(section.children) do
        RefreshWidget(child)
        if child.GetChildren then
          for _, sub in pairs({child:GetChildren()}) do RefreshWidget(sub) end
        end
      end
      local hex = NS.ChatGetAccentHex()
      local arrow = section.collapsed and ">" or "v"
      section.header.text:SetText("|cff"..hex..arrow.."|r |cff808080"..section.header._sectionText.."|r")
      if section.collapsed then section.clip:SetHeight(0); section.clipInner:Hide()
      else section.clipInner:Show() end
    end
    UpdateFPSStatus()
    ringColorSw:SetBackdropColor(DB("qolRingColorR") or 0, DB("qolRingColorG") or 0.8, DB("qolRingColorB") or 0.8, 1)
    timerSwatch:SetBackdropColor(DB("qolTimerColorR") or 1, DB("qolTimerColorG") or 1, DB("qolTimerColorB") or 1, 1)
    if enterRow._sw then enterRow._sw:SetBackdropColor(DB("qolAlertEnterR") or 1, DB("qolAlertEnterG") or 0, DB("qolAlertEnterB") or 0, 1) end
    if leaveRow._sw then leaveRow._sw:SetBackdropColor(DB("qolAlertLeaveR") or 0, DB("qolAlertLeaveG") or 1, DB("qolAlertLeaveB") or 0, 1) end
    if enterRow._box then enterRow._box:SetText(DB("qolCombatEnterText") or "++Combat++") end
    if leaveRow._box then leaveRow._box:SetText(DB("qolCombatLeaveText") or "--Combat--") end
    RefreshRepairDD()
    RepositionAll()
    for _, section in ipairs(sections) do
      if not section.collapsed then section.clip:SetHeight(section.targetH) end
    end
  end)

  return container
end

-- ══════════════════════════════════════════════════════════════════════
-- TAB 8: Tab Settings (hidden, opened via context menu "Filter")
-- ══════════════════════════════════════════════════════════════════════
local function SetupTabSettings(parent)
  local container = CreateFrame("Frame", nil, parent)
  local allFrames = {}
  local dropdowns = {}
  local builtUI   = false
  local currentTabIdx = 1

  local filtersHeader = NS.ChatGetHeader(container, "Tab Settings")
  filtersHeader:SetPoint("TOP")
  table.insert(allFrames, filtersHeader)

  local function UpdateHeader()
    local tData = NS.chatTabData and NS.chatTabData()
    local td = tData and tData[currentTabIdx]
    local tabName = td and td.name or "\226\128\148"
    filtersHeader.text:SetText(
      "|cff" .. NS.ChatGetAccentHex() .. ">|r" ..
      " |cffffffff" .. "Message Types" .. "|r" ..
      " |cff808080(Tab: " .. tabName .. ")|r"
    )
  end

  local function RefreshDropdowns()
    for _, dd in ipairs(dropdowns) do
      if dd.SetValue then dd:SetValue() end
    end
  end

  local function MakeCatDropdown(cat)
    local capturedCat = cat
    local dd = NS.ChatGetDropdown(container, cat.label)
    dd:SetPoint("TOP", allFrames[#allFrames], "BOTTOM", 0, 0)
    dd.DropDown:SetDefaultText("|cff808080All|r")
    table.insert(allFrames, dd)
    table.insert(dropdowns, dd)

    dd.DropDown:SetupMenu(function(_, rootDescription)
      local tData = NS.chatTabData and NS.chatTabData()
      local td = tData and tData[currentTabIdx]
      for _, ev in ipairs(capturedCat.events) do
        local shortKey = ev:gsub("^CHAT_MSG_", "")
        local label = EVENT_LABELS[shortKey] or shortKey
        local ci = ChatTypeInfo and ChatTypeInfo[shortKey]
        local cr, cg, cb = 1, 1, 1
        if ci then cr, cg, cb = ci.r, ci.g, ci.b end
        local capturedEv = ev
        local chk = rootDescription:CreateCheckbox(
          string.format("|cff%02x%02x%02x%s|r", cr*255, cg*255, cb*255, label),
          function()
            local es = td and td.eventSet
            return not es or (es[capturedEv] == true)
          end,
          function()
            -- Toggle single event
            if not td then return end
            if not td.eventSet then
              td.eventSet = {}
              local cats = NS.FILTER_CATS
              if cats then
                for _, c in ipairs(cats) do
                  for _, e in ipairs(c.events) do td.eventSet[e] = true end
                end
              end
              td.eventSet[capturedEv] = nil
            else
              if td.eventSet[capturedEv] then
                td.eventSet[capturedEv] = nil
              else
                td.eventSet[capturedEv] = true
                -- Check if all events are now on → collapse to nil
                local allOn = true
                local cats2 = NS.FILTER_CATS
                if cats2 then
                  for _, c in ipairs(cats2) do
                    for _, e in ipairs(c.events) do
                      if not td.eventSet[e] then allOn = false; break end
                    end
                    if not allOn then break end
                  end
                end
                if allOn then td.eventSet = nil end
              end
            end
            dd:SetValue()
            if NS.chatTabMsgs then NS.chatTabMsgs[currentTabIdx] = nil end
            if NS.chatRedraw then NS.chatRedraw() end
          end
        )
        NS.SkinMenuElement(chk)
      end
    end)

    dd.SetValue = function()
      local tData2 = NS.chatTabData and NS.chatTabData()
      local td2 = tData2 and tData2[currentTabIdx]
      local es = td2 and td2.eventSet
      local activeLabels = {}
      for _, ev in ipairs(capturedCat.events) do
        if not es or es[ev] == true then
          local shortKey = ev:gsub("^CHAT_MSG_", "")
          local label = EVENT_LABELS[shortKey] or shortKey
          local ci = ChatTypeInfo and ChatTypeInfo[shortKey]
          local cr, cg, cb = 1, 1, 1
          if ci then cr, cg, cb = ci.r, ci.g, ci.b end
          activeLabels[#activeLabels+1] = string.format("|cff%02x%02x%02x%s|r", cr*255, cg*255, cb*255, label)
        end
      end
      local text
      if #activeLabels == 0 then
        text = "|cffff4444None|r"
      else
        text = table.concat(activeLabels, ", ")
      end
      dd.DropDown:SetDefaultText(text)
      if dd.DropDown.Text then dd.DropDown.Text:SetText(text) end
    end
  end

  local function MakeChannelsDropdown()
    local dd = NS.ChatGetDropdown(container, "Channels")
    dd:SetPoint("TOP", allFrames[#allFrames], "BOTTOM", 0, 0)
    dd.DropDown:SetDefaultText("|cff808080All|r")
    table.insert(allFrames, dd)
    table.insert(dropdowns, dd)

    dd.DropDown:SetupMenu(function(_, rootDescription)
      local DEFAULUI_NAMES = {[1]="General",[2]="Trade",[3]="LocalDefense",[4]="Services",[5]="LookingForGroup"}
      local chanList = {}
      local seen = {}
      for i = 1, 5 do
        local ok2, num, name = pcall(GetChannelName, i)
        if ok2 and num and num > 0 and name and name ~= "" then
          chanList[#chanList+1] = {num=i, name=name}
        else
          chanList[#chanList+1] = {num=i, name=DEFAULUI_NAMES[i] or ("Channel "..i)}
        end
        seen[i] = true
      end
      for i = 6, 20 do
        local ok2, num, name = pcall(GetChannelName, i)
        if ok2 and num and num > 0 and name and name ~= "" and not seen[num] then
          chanList[#chanList+1] = {num=num, name=name}; seen[num] = true
        end
      end
      local ci = ChatTypeInfo and ChatTypeInfo["CHANNEL"]
      local cr, cg, cb = 1, 0.75, 0.75
      if ci then cr, cg, cb = ci.r, ci.g, ci.b end
      for _, ch in ipairs(chanList) do
        local capName = ch.name
        local displayLabel = string.format("|cff%02x%02x%02x%d. %s|r", cr*255, cg*255, cb*255, ch.num, ch.name)
        local chk2 = rootDescription:CreateCheckbox(displayLabel,
          function()
            local tData3 = NS.chatTabData and NS.chatTabData()
            local td3 = tData3 and tData3[currentTabIdx]
            if not td3 or not td3.channelBlocked then return true end
            return not td3.channelBlocked[capName]
          end,
          function()
            local tData3 = NS.chatTabData and NS.chatTabData()
            local td3 = tData3 and tData3[currentTabIdx]
            if not td3 then return end
            if not td3.channelBlocked then td3.channelBlocked = {} end
            if td3.channelBlocked[capName] then
              td3.channelBlocked[capName] = nil
              if not next(td3.channelBlocked) then td3.channelBlocked = nil end
            else
              td3.channelBlocked[capName] = true
            end
            dd:SetValue()
            if NS.chatTabMsgs then NS.chatTabMsgs[currentTabIdx] = nil end
            if NS.chatRedraw then NS.chatRedraw() end
          end
        )
        NS.SkinMenuElement(chk2)
      end
    end)

    dd.SetValue = function()
      local tData3 = NS.chatTabData and NS.chatTabData()
      local td3 = tData3 and tData3[currentTabIdx]
      local blocked = td3 and td3.channelBlocked
      local ci2 = ChatTypeInfo and ChatTypeInfo["CHANNEL"]
      local cr2, cg2, cb2 = 1, 0.75, 0.75
      if ci2 then cr2, cg2, cb2 = ci2.r, ci2.g, ci2.b end
      local activeLabels = {}
      local DEFAULUI_NAMES2 = {[1]="General",[2]="Trade",[3]="LocalDefense",[4]="Services",[5]="LookingForGroup"}
      for i = 1, 5 do
        local ok2, num, name = pcall(GetChannelName, i)
        local chName = (ok2 and num and num > 0 and name and name ~= "") and name or (DEFAULUI_NAMES2[i] or ("Channel "..i))
        if not blocked or not blocked[chName] then
          activeLabels[#activeLabels+1] = string.format("|cff%02x%02x%02x%d. %s|r", cr2*255, cg2*255, cb2*255, i, chName)
        end
      end
      local text
      if #activeLabels == 0 then text = "|cffff4444None|r"
      else text = table.concat(activeLabels, ", ") end
      dd.DropDown:SetDefaultText(text)
      if dd.DropDown.Text then dd.DropDown.Text:SetText(text) end
    end
  end

  local function BuildUI()
    if builtUI then return end
    builtUI = true
    local cats = NS.FILTER_CATS
    if not cats then return end
    local byKey = {}
    for _, cat in ipairs(cats) do byKey[cat.key] = cat end
    local order = {"MESSAGES", "CREATURE", "REWARDS", "PVP", "SYSTEM", "ADDONS"}
    for _, key in ipairs(order) do
      if key == "MESSAGES" and byKey[key] then
        MakeCatDropdown(byKey[key])
        MakeChannelsDropdown()
      elseif byKey[key] then
        MakeCatDropdown(byKey[key])
      end
    end
  end

  function container:ShowSettings(tabIdx)
    currentTabIdx = tabIdx or 1
    BuildUI()
    UpdateHeader()
    RefreshDropdowns()
  end

  container:SetScript("OnShow", function()
    BuildUI()
  end)

  return container
end

-- ══════════════════════════════════════════════════════════════════════
-- Main Dialog
-- ══════════════════════════════════════════════════════════════════════
NS.BuildChatOptionsWindow = function()
  if chatOptWin then
    local wasVisible = chatOptWin:IsVisible()
    chatOptWin:SetShown(not wasVisible)
    -- When reopening, if Tab Settings was active, fall back to tab 1
    if not wasVisible and chatOptWin._selectTab and chatOptWin._tabSettingsContainer then
      if chatOptWin._tabSettingsContainer:IsShown() then
        chatOptWin._selectTab(1)
      end
    end
    return
  end

  local ar, ag, ab = NS.ChatGetAccentRGB()

  chatOptWin = CreateFrame("Frame", "LUIChatSettingsDialog", UIParent, "ButtonFrameTemplate")
  chatOptWin:SetToplevel(true)
  chatOptWin:SetSize(800, 550)
  chatOptWin:SetPoint("CENTER")
  chatOptWin:Raise()
  chatOptWin:SetMovable(true); chatOptWin:SetClampedToScreen(true)
  chatOptWin:RegisterForDrag("LeftButton")
  chatOptWin:SetScript("OnDragStart", function() chatOptWin:StartMoving(); chatOptWin:SetUserPlaced(false) end)
  chatOptWin:SetScript("OnDragStop", function() chatOptWin:StopMovingOrSizing(); chatOptWin:SetUserPlaced(false) end)

  ButtonFrameTemplate_HidePortrait(chatOptWin)
  ButtonFrameTemplate_HideButtonBar(chatOptWin)
  chatOptWin.Inset:Hide()
  chatOptWin:EnableMouse(true)
  chatOptWin:SetScript("OnMouseWheel", function() end)
  chatOptWin:SetTitle("LucidUI Settings")

  -- Reload button (next to close)
  local reloadBtn = CreateFrame("Button", nil, chatOptWin)
  local reloadText = reloadBtn:CreateFontString(nil, "OVERLAY")
  reloadText:SetFont("Fonts/FRIZQT__.TTF", 10, ""); reloadText:SetPoint("CENTER")
  reloadText:SetTextColor(0.6, 0.6, 0.6); reloadText:SetText("/reload")
  reloadBtn:SetSize(reloadText:GetStringWidth() + 10, 20)
  reloadBtn:SetPoint("RIGHT", chatOptWin.CloseButton, "LEFT", -2, 0)
  reloadBtn:SetScript("OnEnter", function() local cr4,cg4,cb4 = NS.ChatGetAccentRGB(); reloadText:SetTextColor(cr4,cg4,cb4) end)
  reloadBtn:SetScript("OnLeave", function() reloadText:SetTextColor(0.6, 0.6, 0.6) end)
  reloadBtn:SetScript("OnClick", function() ReloadUI() end)

  -- Debug button (next to reload)
  local debugBtn = CreateFrame("Button", nil, chatOptWin)
  local debugText = debugBtn:CreateFontString(nil, "OVERLAY")
  debugText:SetFont("Fonts/FRIZQT__.TTF", 10, ""); debugText:SetPoint("CENTER")
  debugText:SetTextColor(0.6, 0.6, 0.6); debugText:SetText(L["Debug"])
  debugBtn:SetSize(debugText:GetStringWidth() + 10, 20)
  debugBtn:SetPoint("RIGHT", reloadBtn, "LEFT", -2, 0)
  debugBtn:SetScript("OnEnter", function() local cr4,cg4,cb4 = NS.ChatGetAccentRGB(); debugText:SetTextColor(cr4,cg4,cb4) end)
  debugBtn:SetScript("OnLeave", function() debugText:SetTextColor(0.6, 0.6, 0.6) end)
  debugBtn:SetScript("OnClick", function() if NS.BuildDebugWindow then NS.BuildDebugWindow() end end)

  -- Tabs
  local SIDEBAR_W = 130
  local TabSetups = {
    {name="Display",        callback=SetupDisplay},
    {name="Appearance",     callback=SetupAppearance},
    {name="Text",           callback=SetupText},
    {name="Advanced",       callback=SetupAdvanced},
    {name="Chat Colors",    callback=SetupMessageColors},
    {name="Loot",           callback=SetupLoot},
    {name="QoL",            callback=SetupQoL},
    {name="LucidMeter",     callback=NS.LucidMeter.SetupSettings},
    {name="Bags",            callback=NS.Bags.SetupSettings},
    {name="Tab Settings",   callback=SetupTabSettings, hidden=true},
  }

  -- Sidebar background
  local sidebar = CreateFrame("Frame", nil, chatOptWin)
  sidebar:SetPoint("TOPLEFT", 0, 0)
  sidebar:SetPoint("BOTTOMLEFT", 0, 0)
  sidebar:SetWidth(SIDEBAR_W)
  local sidebarBg = sidebar:CreateTexture(nil, "BACKGROUND", nil, 1)
  sidebarBg:SetAllPoints()
  sidebarBg:SetColorTexture(0.08, 0.08, 0.08, 0.95)
  local sidebarLine = sidebar:CreateTexture(nil, "OVERLAY")
  sidebarLine:SetWidth(1)
  sidebarLine:SetPoint("TOPRIGHT", 0, -38)
  sidebarLine:SetPoint("BOTTOMRIGHT", 0, 0)
  sidebarLine:SetColorTexture(ar, ag, ab, 0.4)
  chatOptWin._ltSidebarLine = sidebarLine
  -- Horizontal accent line inside sidebar (matches header line)
  local sidebarHLine = sidebar:CreateTexture(nil, "OVERLAY")
  sidebarHLine:SetHeight(1)
  sidebarHLine:SetPoint("TOPLEFT", 0, -38)
  sidebarHLine:SetPoint("TOPRIGHT", 0, -38)
  sidebarHLine:SetColorTexture(ar, ag, ab, 0.6)
  chatOptWin._ltSidebarHLine = sidebarHLine

  local containers = {}
  local tabs = {}
  local visibleTabs = {}
  local TAB_H = 30

  local function SelectTab(idx)
    for i, c in ipairs(containers) do
      c:Hide()
      if tabs[i] then
        tabs[i]._selected = false
        tabs[i].label:SetTextColor(0.78, 0.78, 0.78)
        tabs[i].selBg:Hide()
        if tabs[i].selLine then tabs[i].selLine:Hide() end
      end
    end
    containers[idx]:Show()
    if tabs[idx] then
      tabs[idx]._selected = true
      local cr5, cg5, cb5 = NS.ChatGetAccentRGB()
      tabs[idx].label:SetTextColor(cr5, cg5, cb5)
      if tabs[idx].selLine then tabs[idx].selLine:Show() end
      tabs[idx].selBg:Show()
    end
  end

  for i, setup in ipairs(TabSetups) do
    local tabContainer = setup.callback(chatOptWin)
    tabContainer:ClearAllPoints()
    tabContainer:SetPoint("TOPLEFT", chatOptWin, "TOPLEFT", SIDEBAR_W, -46)
    tabContainer:SetPoint("BOTTOMRIGHT", chatOptWin, "BOTTOMRIGHT")

    local tabButton = CreateFrame("Button", nil, sidebar)
    tabButton:SetSize(SIDEBAR_W, TAB_H)

    local selBg = tabButton:CreateTexture(nil, "BACKGROUND", nil, 2)
    selBg:SetAllPoints()
    selBg:SetColorTexture(0.12, 0.12, 0.12, 1)
    selBg:Hide()
    tabButton.selBg = selBg

    local selLine = tabButton:CreateTexture(nil, "OVERLAY", nil, 7)
    selLine:SetWidth(2)
    selLine:SetPoint("TOPRIGHT", 0, 0)
    selLine:SetPoint("BOTTOMRIGHT", 0, 0)
    selLine:SetColorTexture(ar, ag, ab, 1)
    selLine:Hide()
    tabButton.selLine = selLine

    local label = tabButton:CreateFontString(nil, "OVERLAY")
    label:SetFont("Fonts/FRIZQT__.TTF", 11, "")
    label:SetPoint("LEFT", 12, 0)
    label:SetTextColor(0.78, 0.78, 0.78)
    label:SetText(setup.name)
    tabButton.label = label

    if setup.hidden then
      tabButton:Hide()
    else
      table.insert(visibleTabs, tabButton)
    end

    local capturedIdx = i
    tabButton:SetScript("OnClick", function() SelectTab(capturedIdx) end)
    tabButton:SetScript("OnEnter", function()
      if not tabButton._selected then
        local cr5, cg5, cb5 = NS.ChatGetAccentRGB()
        label:SetTextColor(cr5, cg5, cb5)
      end
    end)
    tabButton:SetScript("OnLeave", function()
      if not tabButton._selected then label:SetTextColor(0.78, 0.78, 0.78) end
    end)

    tabContainer.button = tabButton
    tabContainer:Hide()
    if setup.hidden then
      chatOptWin._tabSettingsContainer = tabContainer
      chatOptWin._tabSettingsButton = tabButton
      chatOptWin._tabSettingsIdx = i
    end
    if setup.name == "Bags" then
      chatOptWin._bagsTabIdx = i
    end
    table.insert(tabs, tabButton)
    table.insert(containers, tabContainer)
  end

  -- Position visible tab buttons vertically
  for i, t in ipairs(visibleTabs) do
    if i == 1 then t:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, -46)
    else t:SetPoint("TOPLEFT", visibleTabs[i-1], "BOTTOMLEFT", 0, 0) end
  end

  -- Skin the dialog frame (dark theme) — BEFORE first tab click
  if chatOptWin.NineSlice then chatOptWin.NineSlice:Hide() end
  if chatOptWin.Bg then chatOptWin.Bg:Hide() end
  if chatOptWin.TitleBg then chatOptWin.TitleBg:Hide() end
  if chatOptWin.TopTileStreaks then chatOptWin.TopTileStreaks:Hide() end
  for _, region in pairs({chatOptWin:GetRegions()}) do
    if region:IsObjectType("Texture") then region:SetAlpha(0) end
  end
  local bg = chatOptWin:CreateTexture(nil, "BACKGROUND")
  bg:SetColorTexture(0.08, 0.08, 0.08, 0.95); bg:SetAllPoints()
  chatOptWin._ltTabLine = nil  -- sidebar replaces top tab line

  -- Style title
  if chatOptWin.TitleContainer and chatOptWin.TitleContainer.TitleText then
    chatOptWin.TitleContainer.TitleText:Hide()
  end
  local addonVersion = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("LucidUI", "Version") or "?"
  local hex = string.format("|cff%02x%02x%02x", ar*255, ag*255, ab*255)
  -- Sidebar: addon name + version (parented to sidebar so they render above bg)
  local titleName = sidebar:CreateFontString(nil, "OVERLAY")
  titleName:SetFont("Fonts/FRIZQT__.TTF", 13, "")
  titleName:SetPoint("TOPLEFT", 12, -6)
  titleName:SetText(hex .. "LucidUI|r")
  chatOptWin._ltTitleName = titleName
  local titleVer = sidebar:CreateFontString(nil, "OVERLAY")
  titleVer:SetFont("Fonts/FRIZQT__.TTF", 9, "")
  titleVer:SetPoint("TOPLEFT", titleName, "BOTTOMLEFT", 0, -2)
  titleVer:SetTextColor(0.45, 0.45, 0.45)
  titleVer:SetText("Version v" .. addonVersion)
  -- Accent line under version, full width
  local headerLine = chatOptWin:CreateTexture(nil, "OVERLAY")
  headerLine:SetHeight(1)
  headerLine:SetPoint("TOPLEFT", chatOptWin, "TOPLEFT", 0, -38)
  headerLine:SetPoint("TOPRIGHT", chatOptWin, "TOPRIGHT", 0, -38)
  headerLine:SetColorTexture(ar, ag, ab, 0.6)
  chatOptWin._ltHeaderLine = headerLine

  -- Center: "> LucidUI Settings <"
  local centerTitle = chatOptWin:CreateFontString(nil, "OVERLAY")
  centerTitle:SetFont("Fonts/FRIZQT__.TTF", 12, "")
  centerTitle:SetPoint("TOP", chatOptWin, "TOP", SIDEBAR_W / 2, -8)
  centerTitle:SetText(hex .. ">|r |cffffffff" .. "LucidUI Settings" .. "|r " .. hex .. "<|r")
  chatOptWin._ltCenterTitle = centerTitle

  -- Style close button (reads accent dynamically so it updates live)
  if chatOptWin.CloseButton and chatOptWin.CloseButton:GetNormalTexture() then
    chatOptWin.CloseButton:GetNormalTexture():SetVertexColor(0.6, 0.6, 0.6)
    chatOptWin.CloseButton:HookScript("OnEnter", function()
      local cr2, cg2, cb2 = NS.ChatGetAccentRGB()
      chatOptWin.CloseButton:GetNormalTexture():SetVertexColor(cr2, cg2, cb2)
    end)
    chatOptWin.CloseButton:HookScript("OnLeave", function()
      chatOptWin.CloseButton:GetNormalTexture():SetVertexColor(0.6, 0.6, 0.6)
    end)
  end

  -- Select first tab
  chatOptWin.containers = containers
  chatOptWin._selectTab = SelectTab
  SelectTab(1)

  NS.chatOptWin = chatOptWin
end

-- Opens settings dialog and switches to Tab Settings for a specific chat tab
NS.OpenChatTabSettings = function(chatTabIdx)
  -- Ensure dialog exists
  if not chatOptWin then
    NS.BuildChatOptionsWindow()
  end
  if not chatOptWin then return end
  chatOptWin:Show()
  chatOptWin:Raise()
  -- Select the hidden Tab Settings tab
  if chatOptWin._selectTab and chatOptWin._tabSettingsIdx then
    chatOptWin._selectTab(chatOptWin._tabSettingsIdx)
  end
  -- Defer so OnShow settles, then show the correct chat tab's settings
  C_Timer.After(0, function()
    if chatOptWin._tabSettingsContainer and chatOptWin._tabSettingsContainer.ShowSettings then
      chatOptWin._tabSettingsContainer:ShowSettings(chatTabIdx)
    end
  end)
end
