-- LucidUI ChatBar.lua
-- Vertical button bar alongside the chat frame.

local NS = LucidUINS
local L  = LucidUIL

local chatBar       = nil
local iconTextures  = {}

local BAR_W    = 32
local BTN_SIZE = 24
local BTN_GAP  = -4

local function GetAccent()
  local t = NS.GetTheme(NS.DB("theme"))
  local tid = t.tilders or NS.CYAN
  return tid[1], tid[2], tid[3]
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
    chatBar:SetBackdrop({bgFile = "Interface/Buttons/WHITE8X8"})
    chatBar:SetBackdropColor(0, 0, 0, GetChatBgAlpha())
  end

  -- Build buttons
  local entries = {}

  -- Social (with online friends count badge)
  local socialsBtn = MakeBtn(chatBar)
  MakeIcon(socialsBtn, "Interface/AddOns/LucidUI/Assets/ChatSocial.png")
  socialsBtn:SetScript("OnClick", function() ToggleFriendsFrame() end)
  Tooltip(socialsBtn, L["Social"])
  table.insert(entries, socialsBtn)

  local friendsBadge = socialsBtn:CreateFontString(nil, "OVERLAY")
  friendsBadge:SetFont("Fonts/FRIZQT__.TTF", 12, "OUTLINE")
  friendsBadge:SetPoint("BOTTOM", socialsBtn, "BOTTOM", 0, -2)
  friendsBadge:SetTextColor(1, 1, 1, 1)
  friendsBadge:SetText("")

  local friendsSyncTimer = 0
  local friendsSyncFrame = CreateFrame("Frame")
  friendsSyncFrame:SetScript("OnUpdate", function(_, elapsed)
    friendsSyncTimer = friendsSyncTimer + elapsed
    if friendsSyncTimer < 10 then return end
    friendsSyncTimer = 0
    local numOnline = 0
    -- WoW friends
    if C_FriendList and C_FriendList.GetNumOnlineFriends then
      numOnline = numOnline + (C_FriendList.GetNumOnlineFriends() or 0)
    end
    -- BNet friends
    if BNGetNumFriends then
      local _, bnOnline = BNGetNumFriends()
      numOnline = numOnline + (bnOnline or 0)
    end
    if numOnline > 0 then
      friendsBadge:SetText(numOnline)
    else
      friendsBadge:SetText("")
    end
  end)

  -- Settings
  local settingsBtn = MakeBtn(chatBar)
  MakeIcon(settingsBtn, "Interface/AddOns/LucidUI/Assets/SettingsCog.png")
  settingsBtn:SetScript("OnClick", function()
    if NS.BuildChatOptionsWindow then NS.BuildChatOptionsWindow() end
  end)
  Tooltip(settingsBtn, L["Settings"])
  table.insert(entries, settingsBtn)

  -- Copy
  local copyBtn = MakeBtn(chatBar)
  MakeIcon(copyBtn, "Interface/AddOns/LucidUI/Assets/Copy.png")
  copyBtn:SetScript("OnClick", function()
    if NS.ChatShowCopyWindow then NS.ChatShowCopyWindow() end
  end)
  Tooltip(copyBtn, L["Copy Chat"])
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
  table.insert(entries, rollsBtn)

  -- Stats
  local statsBtn = MakeBtn(chatBar)
  MakeIcon(statsBtn, "Interface/AddOns/LucidUI/Assets/Star.png")
  statsBtn:SetScript("OnClick", function()
    if NS.BuildStatsWindow then NS.BuildStatsWindow() end
  end)
  Tooltip(statsBtn, L["Session Stats"])
  statsBtn._configKey = "showStatsBtn"
  table.insert(entries, statsBtn)

  -- Voice Chat / Leave Voice Chat
  local vcBtn = MakeBtn(chatBar)
  local vcTex = MakeIcon(vcBtn, "Interface/AddOns/LucidUI/Assets/VoiceChat.png")
  local vcInChannel = false
  vcBtn:SetScript("OnClick", function()
    if vcInChannel then
      -- Leave voice channel
      if C_VoiceChat and C_VoiceChat.IsLoggedIn and C_VoiceChat.IsLoggedIn() then
        local channelID = C_VoiceChat.GetActiveChannelID and C_VoiceChat.GetActiveChannelID()
        if channelID then
          C_VoiceChat.LeaveChannel(channelID)
        end
      end
    else
      -- Open channel panel
      if ChannelFrame and ChannelFrame:IsShown() then ChannelFrame:Hide()
      else ToggleChannelFrame() end
    end
  end)
  Tooltip(vcBtn, L["Voice Chat"])
  table.insert(entries, vcBtn)

  -- Swap icon based on voice channel state
  local vcSyncTimer = 0
  local vcSyncFrame = CreateFrame("Frame")
  vcSyncFrame:SetScript("OnUpdate", function(_, elapsed)
    vcSyncTimer = vcSyncTimer + elapsed
    if vcSyncTimer < 2 then return end
    vcSyncTimer = 0
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

  -- Layout: only show buttons whose config allows it
  local function LayoutBarButtons()
    local yOff2 = -8
    for _, btn in ipairs(entries) do
      local visible = true
      if btn._configKey then
        visible = NS.DB(btn._configKey) ~= false
      end
      btn:SetShown(visible)
      if visible then
        btn:ClearAllPoints()
        btn:SetPoint("TOP", chatBar, "TOP", 0, yOff2)
        yOff2 = yOff2 - BTN_SIZE + BTN_GAP
      end
    end
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
      -- Stretch tabbar bg to cover bar on hover
      local pos2 = NS.DB("chatBarPosition") or "outside_right"
      local isOutside = (pos2 == "outside_right" or pos2 == "outside_left")
      if isOutside and NS.chatTabBarBg then
        local ltTabBar = _G["LUIChatTabBar"]
        if ltTabBar then
          NS.chatTabBarBg:ClearAllPoints()
          if pos2 == "outside_right" then
            NS.chatTabBarBg:SetPoint("TOPLEFT", ltTabBar, "TOPLEFT", 0, 0)
            NS.chatTabBarBg:SetPoint("BOTTOMRIGHT", ltTabBar, "BOTTOMRIGHT", BAR_W, 0)
          else
            NS.chatTabBarBg:SetPoint("TOPLEFT", ltTabBar, "TOPLEFT", -BAR_W, 0)
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
        -- Shrink tabbar bg back
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
    chatBar:SetBackdrop({bgFile = "Interface/Buttons/WHITE8X8"})
    local a = NS.DB("chatBgAlpha") or 0.5
    chatBar:SetBackdropColor(0, 0, 0, 1 - a)
  end
  -- Update tab bar bg stretch based on bar visibility
  NS.UpdateTabBarBgStretch()
  -- Update message area / resize inset for inside bar positions
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

  NS.chatTabBarBg:ClearAllPoints()
  if isOutside and barVisible then
    -- Bar always visible: stretch tabbar bg to cover bar area
    if pos == "outside_right" then
      NS.chatTabBarBg:SetPoint("TOPLEFT", ltTabBar, "TOPLEFT", 0, 0)
      NS.chatTabBarBg:SetPoint("BOTTOMRIGHT", ltTabBar, "BOTTOMRIGHT", BAR_W, 0)
    else
      NS.chatTabBarBg:SetPoint("TOPLEFT", ltTabBar, "TOPLEFT", -BAR_W, 0)
      NS.chatTabBarBg:SetPoint("BOTTOMRIGHT", ltTabBar, "BOTTOMRIGHT", 0, 0)
    end
  else
    -- Inside, mouseover, or never: tabbar bg matches tabbar only
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
