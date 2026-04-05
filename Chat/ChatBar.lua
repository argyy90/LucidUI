-- LucidUI ChatBar.lua
-- Vertical button bar alongside the chat frame.

local NS = LucidUINS
local L  = LucidUIL

local chatBar       = nil
local iconTextures  = {}

-- Ticker refs kept so they can be cancelled cleanly (avoids ticker leaks)
local _friendsTicker = nil
local _vcTicker      = nil

local BAR_W    = 32
local BTN_SIZE = 24
local BTN_GAP  = -4

local function GetAccent()
  -- NS.CYAN is always kept in sync with the active accent color
  return NS.CYAN[1], NS.CYAN[2], NS.CYAN[3]
end

local function GetBtnColor()
  local ic = NS.DB("chatIconColor")
  if ic and type(ic) == "table" and ic.r then return ic.r, ic.g, ic.b end
  local t = NS.GetTheme(NS.DB("theme"))
  local bc = t.btnColor or {1, 1, 1, 1}
  return bc[1], bc[2], bc[3]
end

local function GetChatBgAlpha()
  local a = NS.DB("chatBgAlpha") or 0.5
  return 1 - a
end

local function MakeBtn(parent)
  local btn = CreateFrame("Button", nil, parent)
  btn:SetSize(BTN_SIZE, BTN_SIZE)
  btn:SetFrameLevel(parent:GetFrameLevel() + 5)
  return btn
end

local function MakeIcon(btn, texture, size)
  local tex = btn:CreateTexture(nil, "ARTWORK")
  tex:SetTexture(texture)
  tex:SetSize(size or BTN_SIZE, size or BTN_SIZE)
  tex:SetPoint("CENTER")
  local r, g, b = GetBtnColor()
  tex:SetVertexColor(r, g, b, 1)
  btn:SetScript("OnEnter", function()
    local ar, ag, ab = GetAccent()
    tex:SetVertexColor(ar, ag, ab, 1)
  end)
  btn:SetScript("OnLeave", function()
    local ir, ig, ib = GetBtnColor()
    tex:SetVertexColor(ir, ig, ib, 1)
    if chatBar and not chatBar:IsMouseOver() then
      local vis = NS.DB("chatBarVisibility") or "always"
      if vis == "mouseover" then chatBar:SetAlpha(0) end
    end
  end)
  table.insert(iconTextures, tex)
  return tex
end

local function Tooltip(btn, text)
  btn:HookScript("OnEnter", function()
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    GameTooltip:SetText(text); GameTooltip:Show()
  end)
  btn:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Cancel all active bar tickers (call this if chat is disabled/reset)
NS.CleanupChatBarTickers = function()
  if _friendsTicker then _friendsTicker:Cancel(); _friendsTicker = nil end
  if _vcTicker       then _vcTicker:Cancel();      _vcTicker = nil       end
end

NS.BuildChatBar = function()
  if chatBar then return end
  local anchor = NS.chatBg
  if not anchor then return end

  chatBar = CreateFrame("Frame", "LucidUIChatBar", UIParent, "BackdropTemplate")
  chatBar:SetWidth(BAR_W)
  chatBar:SetFrameStrata("MEDIUM")
  chatBar:SetFrameLevel(anchor:GetFrameLevel() + 2)

  local TAB_H = 28
  local pos = NS.DB("chatBarPosition") or "outside_right"
  chatBar:ClearAllPoints()
  if pos == "outside_left" then
    chatBar:SetPoint("TOPRIGHT",    anchor, "TOPLEFT",    0, -TAB_H)
    chatBar:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMLEFT", 0, 0)
  elseif pos == "inside_left" then
    chatBar:SetPoint("TOPLEFT",    anchor, "TOPLEFT",    0, -TAB_H)
    chatBar:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, 0)
  elseif pos == "inside_right" then
    chatBar:SetPoint("TOPRIGHT",    anchor, "TOPRIGHT",    0, -TAB_H)
    chatBar:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
  else
    chatBar:SetPoint("TOPLEFT",    anchor, "TOPRIGHT",    0, -TAB_H)
    chatBar:SetPoint("BOTTOMLEFT", anchor, "BOTTOMRIGHT", 0, 0)
  end

  local isInside = (pos == "inside_left" or pos == "inside_right")
  if isInside then
    chatBar:SetBackdrop(nil)
  else
    chatBar:SetBackdrop({bgFile = NS.TEX_WHITE})
    chatBar:SetBackdropColor(0, 0, 0, GetChatBgAlpha())
  end

  -- Build buttons
  local entries = {}

  -- Social (with online friends count badge)
  local socialsBtn = MakeBtn(chatBar)
  MakeIcon(socialsBtn, "Interface/AddOns/LucidUI/Assets/ChatSocial.png")
  socialsBtn:SetScript("OnClick", function()
    if ToggleFriendsFrame then
      pcall(ToggleFriendsFrame)
    elseif FriendsFrame then
      pcall(FriendsFrame.SetShown, FriendsFrame, not FriendsFrame:IsShown())
    end
  end)
  Tooltip(socialsBtn, L["Social"])
  socialsBtn._configKey = "showSocialBtn"
  socialsBtn._orderKey = "social"
  table.insert(entries, socialsBtn)

  local friendsBadge = socialsBtn:CreateFontString(nil, "OVERLAY")
  friendsBadge:SetFont(NS.FONT, 12, "OUTLINE")
  friendsBadge:SetPoint("BOTTOM", socialsBtn, "BOTTOM", 0, -2)
  friendsBadge:SetTextColor(1, 1, 1, 1)
  friendsBadge:SetText("")

  -- Ticker instead of OnUpdate polling; stored so it can be cancelled
  _friendsTicker = C_Timer.NewTicker(10, function()
    local numOnline = 0
    if C_FriendList and C_FriendList.GetNumOnlineFriends then
      numOnline = numOnline + (C_FriendList.GetNumOnlineFriends() or 0)
    end
    -- BNGetNumFriends is the stable Midnight global (C_BattleNet.GetFriendNumFriends does not exist)
    if BNGetNumFriends then
      local _, bnOnline = BNGetNumFriends()
      numOnline = numOnline + (bnOnline or 0)
    end
    friendsBadge:SetText(numOnline > 0 and numOnline or "")
  end)

  -- Settings
  local settingsBtn = MakeBtn(chatBar)
  MakeIcon(settingsBtn, "Interface/AddOns/LucidUI/Assets/SettingsCog.png")
  settingsBtn:SetScript("OnClick", function()
    if NS.BuildChatOptionsWindow then pcall(NS.BuildChatOptionsWindow) end
  end)
  Tooltip(settingsBtn, L["Settings"])
  settingsBtn._configKey = "showSettingsBtn"
  settingsBtn._orderKey = "settings"
  table.insert(entries, settingsBtn)

  -- Copy
  local copyBtn = MakeBtn(chatBar)
  MakeIcon(copyBtn, "Interface/AddOns/LucidUI/Assets/Copy.png")
  copyBtn:SetScript("OnClick", function()
    if NS.ChatShowCopyWindow then pcall(NS.ChatShowCopyWindow) end
  end)
  Tooltip(copyBtn, L["Copy Chat"])
  copyBtn._configKey = "showCopyBtn"
  copyBtn._orderKey = "copy"
  table.insert(entries, copyBtn)

  -- Rolls
  local rollsBtn = MakeBtn(chatBar)
  MakeIcon(rollsBtn, "Interface/AddOns/LucidUI/Assets/Dice.png")
  rollsBtn:SetScript("OnClick", function()
    if NS.rollWin then
      NS.rollWin:SetShown(not NS.rollWin:IsShown())
    end
  end)
  Tooltip(rollsBtn, L["LOOT ROLLS"])
  rollsBtn._configKey = "showRollsBtn"
  rollsBtn._orderKey = "rolls"
  table.insert(entries, rollsBtn)

  -- Stats
  local statsBtn = MakeBtn(chatBar)
  MakeIcon(statsBtn, "Interface/AddOns/LucidUI/Assets/Star.png")
  statsBtn:SetScript("OnClick", function()
    if NS.BuildStatsWindow then pcall(NS.BuildStatsWindow) end
  end)
  Tooltip(statsBtn, L["Session Stats"])
  statsBtn._configKey = "showStatsBtn"
  statsBtn._orderKey = "stats"
  table.insert(entries, statsBtn)

  -- Mythic+
  local mplusBtn = MakeBtn(chatBar)
  MakeIcon(mplusBtn, "Interface/AddOns/LucidUI/Assets/MPlus.png")
  mplusBtn:SetScript("OnClick", function()
    if NS.MythicPlus and NS.MythicPlus.ShowWindow then pcall(NS.MythicPlus.ShowWindow) end
  end)
  Tooltip(mplusBtn, L["Mythic+"])
  mplusBtn._configKey = "showMPlusBtn"
  mplusBtn._featureKey = "mpEnabled"
  mplusBtn._orderKey = "mplus"
  table.insert(entries, mplusBtn)

  -- Gold Tracker
  local coinBtn = MakeBtn(chatBar)
  MakeIcon(coinBtn, "Interface/AddOns/LucidUI/Assets/Coin.png")
  coinBtn:SetScript("OnClick", function()
    if NS.GoldTracker and NS.GoldTracker.ShowWindow then pcall(NS.GoldTracker.ShowWindow) end
  end)
  Tooltip(coinBtn, L["Gold Tracker"])
  coinBtn._configKey = "showCoinBtn"
  coinBtn._featureKey = "gtEnabled"
  coinBtn._orderKey = "coin"
  table.insert(entries, coinBtn)

  -- Voice Chat / Leave Voice Chat
  -- FIX: Midnight 12.x API uses IsSelfMuted / IsSelfDeafened / ToggleSelfMute / ToggleSelfDeafen
  local vcBtn = MakeBtn(chatBar)
  local vcTex = MakeIcon(vcBtn, "Interface/AddOns/LucidUI/Assets/VoiceChat.png")
  local vcInChannel = false
  vcBtn:SetScript("OnClick", function()
    if vcInChannel then
      if C_VoiceChat and C_VoiceChat.IsLoggedIn and C_VoiceChat.IsLoggedIn() then
        local channelID = C_VoiceChat.GetActiveChannelID and C_VoiceChat.GetActiveChannelID()
        if channelID then C_VoiceChat.LeaveChannel(channelID) end
      end
    else
      -- Open channel panel — ToggleChannelFrame removed in Midnight
      if ChannelFrame then
        ChannelFrame:SetShown(not ChannelFrame:IsShown())
      elseif ToggleChannelFrame then
        ToggleChannelFrame()
      end
    end
  end)
  Tooltip(vcBtn, L["Voice Chat"])
  vcBtn._configKey = "showVoiceChatBtn"
  vcBtn._orderKey = "voicechat"
  table.insert(entries, vcBtn)

  -- Ticker for voice state; stored so it can be cancelled
  _vcTicker = C_Timer.NewTicker(2, function()
    local wasInChannel = vcInChannel
    if C_VoiceChat and C_VoiceChat.IsLoggedIn and C_VoiceChat.IsLoggedIn() then
      local chID = C_VoiceChat.GetActiveChannelID and C_VoiceChat.GetActiveChannelID()
      vcInChannel = (chID ~= nil)
    else
      vcInChannel = false
    end
    if vcInChannel ~= wasInChannel then
      if vcInChannel then
        vcTex:SetTexture("Interface/AddOns/LucidUI/Assets/LeaveVoiceChat.png")
      else
        vcTex:SetTexture("Interface/AddOns/LucidUI/Assets/VoiceChat.png")
      end
    end
  end)

  -- Build a lookup from orderKey to button
  local btnByKey = {}
  for _, btn in ipairs(entries) do
    if btn._orderKey then btnByKey[btn._orderKey] = btn end
  end
  NS.chatBarBtnByKey = btnByKey

  -- Layout: only show buttons whose config allows it, wrapping into columns
  local function LayoutBarButtons()
    -- Build ordered list from saved order, appending any missing keys at the end
    local savedOrder = NS.DB("chatBarOrder")
    local ordered = {}
    local used = {}
    if savedOrder and type(savedOrder) == "table" then
      for _, key in ipairs(savedOrder) do
        if btnByKey[key] and not used[key] then
          ordered[#ordered+1] = btnByKey[key]
          used[key] = true
        end
      end
    end
    for _, btn in ipairs(entries) do
      if btn._orderKey and not used[btn._orderKey] then
        ordered[#ordered+1] = btn
      end
    end

    local maxPerCol = NS.DB("chatBarIconsPerRow") or 8
    if maxPerCol < 1 then maxPerCol = 1 end
    local col, row = 0, 0
    for _, btn in ipairs(ordered) do
      local visible = true
      if btn._featureKey then visible = NS.DB(btn._featureKey) ~= false end
      if visible and btn._configKey then visible = NS.DB(btn._configKey) ~= false end
      btn:SetShown(visible)
      if visible then
        btn:ClearAllPoints()
        local xOff = col * BAR_W + (BAR_W / 2)
        local yOff = -8 - row * (BTN_SIZE - BTN_GAP)
        btn:SetPoint("TOP", chatBar, "TOPLEFT", xOff, yOff)
        row = row + 1
        if row >= maxPerCol then
          row = 0
          col = col + 1
        end
      end
    end
    local numCols = col + (row > 0 and 1 or 0)
    if numCols < 1 then numCols = 1 end
    chatBar:SetWidth(BAR_W * numCols)
    if NS.UpdateTabBarBgStretch then NS.UpdateTabBarBgStretch() end
    if NS.ApplyBarLayout then NS.ApplyBarLayout() end
  end
  LayoutBarButtons()
  NS.LayoutBarButtons = LayoutBarButtons

  -- Visibility
  local vis = NS.DB("chatBarVisibility") or "always"
  if vis == "never" then
    chatBar:SetAlpha(0); chatBar:EnableMouse(false)
  elseif vis == "mouseover" then
    chatBar:SetAlpha(0); chatBar:EnableMouse(true)
  else
    chatBar:SetAlpha(1); chatBar:EnableMouse(true)
  end

  chatBar:HookScript("OnEnter", function()
    if (NS.DB("chatBarVisibility") or "always") == "mouseover" then
      chatBar:SetAlpha(1)
      local pos2 = NS.DB("chatBarPosition") or "outside_right"
      local isOutside = (pos2 == "outside_right" or pos2 == "outside_left")
      if isOutside and NS.chatTabBarBg then
        local ltTabBar = _G["LUIChatTabBar"]
        if ltTabBar then
          NS.chatTabBarBg:ClearAllPoints()
          local barW = chatBar:GetWidth()
          if pos2 == "outside_right" then
            NS.chatTabBarBg:SetPoint("TOPLEFT", ltTabBar, "TOPLEFT", 0, 0)
            NS.chatTabBarBg:SetPoint("BOTTOMRIGHT", ltTabBar, "BOTTOMRIGHT", barW, 0)
          else
            NS.chatTabBarBg:SetPoint("TOPLEFT", ltTabBar, "TOPLEFT", -barW, 0)
            NS.chatTabBarBg:SetPoint("BOTTOMRIGHT", ltTabBar, "BOTTOMRIGHT", 0, 0)
          end
        end
      end
    end
  end)
  chatBar:HookScript("OnLeave", function()
    if (NS.DB("chatBarVisibility") or "always") == "mouseover" then
      if not chatBar:IsMouseOver() then
        chatBar:SetAlpha(0)
        if NS.UpdateTabBarBgStretch then NS.UpdateTabBarBgStretch() end
      end
    end
  end)

  chatBar:Show()
  NS.chatBarRef = chatBar
end

NS.RepositionChatBar = function()
  if not chatBar or not NS.chatBg then return end
  local anchor = NS.chatBg
  local TAB_H2 = 28
  local pos = NS.DB("chatBarPosition") or "outside_right"
  chatBar:ClearAllPoints()
  if pos == "outside_left" then
    chatBar:SetPoint("TOPRIGHT",    anchor, "TOPLEFT",    0, -TAB_H2)
    chatBar:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMLEFT", 0, 0)
  elseif pos == "inside_left" then
    chatBar:SetPoint("TOPLEFT",    anchor, "TOPLEFT",    0, -TAB_H2)
    chatBar:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, 0)
  elseif pos == "inside_right" then
    chatBar:SetPoint("TOPRIGHT",    anchor, "TOPRIGHT",    0, -TAB_H2)
    chatBar:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
  else
    chatBar:SetPoint("TOPLEFT",    anchor, "TOPRIGHT",    0, -TAB_H2)
    chatBar:SetPoint("BOTTOMLEFT", anchor, "BOTTOMRIGHT", 0, 0)
  end
  local isInside = (pos == "inside_left" or pos == "inside_right")
  if isInside then
    chatBar:SetBackdrop(nil)
  else
    chatBar:SetBackdrop({bgFile = NS.TEX_WHITE})
    local a = NS.DB("chatBgAlpha") or 0.5
    chatBar:SetBackdropColor(0, 0, 0, 1 - a)
  end
  NS.UpdateTabBarBgStretch()
  if NS.ApplyBarLayout then NS.ApplyBarLayout() end
end

NS.UpdateTabBarBgStretch = function()
  if not NS.chatTabBarBg then return end
  local ltTabBar = _G["LUIChatTabBar"]
  if not ltTabBar then return end
  local pos = NS.DB("chatBarPosition") or "outside_right"
  local vis = NS.DB("chatBarVisibility") or "always"
  local isOutside = (pos == "outside_right" or pos == "outside_left")
  local barVisible = (vis == "always")
  local barW = chatBar and chatBar:GetWidth() or BAR_W

  NS.chatTabBarBg:ClearAllPoints()
  if isOutside and barVisible then
    if pos == "outside_right" then
      NS.chatTabBarBg:SetPoint("TOPLEFT", ltTabBar, "TOPLEFT", 0, 0)
      NS.chatTabBarBg:SetPoint("BOTTOMRIGHT", ltTabBar, "BOTTOMRIGHT", barW, 0)
    else
      NS.chatTabBarBg:SetPoint("TOPLEFT", ltTabBar, "TOPLEFT", -barW, 0)
      NS.chatTabBarBg:SetPoint("BOTTOMRIGHT", ltTabBar, "BOTTOMRIGHT", 0, 0)
    end
  else
    NS.chatTabBarBg:SetAllPoints(ltTabBar)
  end
end

NS.UpdateChatBarAccent = function()
  if not chatBar then return end
  local r, g, b = GetBtnColor()
  for _, tex in ipairs(iconTextures) do
    if not tex:GetParent():IsMouseOver() then
      tex:SetVertexColor(r, g, b, 1)
    end
  end
end
