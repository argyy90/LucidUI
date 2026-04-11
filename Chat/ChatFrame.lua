-- LucidUI ChatFrame.lua
-- Main chat frame: background, tab bar, editbox, event hooking.
-- Replaces WoW's default chat with a custom display.

local NS = LucidUINS
local L  = LucidUIL
local CYAN = NS.CYAN

local MAX_HISTORY  = 200
local TAB_H        = 28
local TAB_SPACING  = 2
local MAX_TABS     = 10

-- ── State ────────────────────────────────────────────────────────────
local messageHistory = {}
local customDisplays = {}
local activeTab      = 1
local tabButtons     = {}
local tabData        = {}
local addBtn         = nil
local tabEndX        = 4
local tabMsgs        = {}
local restoringHistory = false
local tabFlashing    = {}
local tabBarFrame    = nil

-- ── Loot routing cache (recomputed once on settings change) ──────────
-- Avoids 4+ repeated NS.DB lookups per incoming message.
local lootRouting = { active=false, showMoney=true, showCurrency=true }
local function RefreshLootRouting()
  lootRouting.active       = NS.DB("lootInChatTab") or NS.DB("lootOwnWindow") or false
  lootRouting.showMoney    = NS.DB("showMoney") ~= false
  lootRouting.showCurrency = NS.DB("showCurrency") ~= false
end
-- Expose so settings callbacks can call it after changing loot options
NS.RefreshLootRouting = RefreshLootRouting

local hiddenFrame = CreateFrame("Frame")
hiddenFrame:Hide()

-- Forward declarations
local AddToDisplay, RebuildTabButtons, RedrawDisplay, GetAccentColor
local RepositionButtons, SaveTabData
local displayReady, earlyBuffer

displayReady = false
earlyBuffer  = {}

-- Event pairs: _INFORM variants controlled by parent event
local EVENT_PAIRS = {
  CHAT_MSG_WHISPER_INFORM    = "CHAT_MSG_WHISPER",
  CHAT_MSG_BN_WHISPER_INFORM = "CHAT_MSG_BN_WHISPER",
}

-- Chat event categories for tab filtering
local FILTER_CATS = {
  { key="MESSAGES", label = "Chat", events = {
      "CHAT_MSG_SAY","CHAT_MSG_EMOTE","CHAT_MSG_YELL","CHAT_MSG_TEXT_EMOTE",
      "CHAT_MSG_GUILD","CHAT_MSG_OFFICER",
      "CHAT_MSG_GUILD_ACHIEVEMENT","CHAT_MSG_GUILD_ITEM_LOOTED","CHAT_MSG_ACHIEVEMENT",
      "CHAT_MSG_WHISPER","CHAT_MSG_BN_WHISPER",
      "CHAT_MSG_PARTY","CHAT_MSG_PARTY_LEADER",
      "CHAT_MSG_RAID","CHAT_MSG_RAID_LEADER","CHAT_MSG_RAID_WARNING",
      "CHAT_MSG_INSTANCE_CHAT","CHAT_MSG_INSTANCE_CHAT_LEADER",
      "CHAT_MSG_VOICE_TEXT",
  }},
  { key="CREATURE", label = "Creature", events = {
      "CHAT_MSG_MONSTER_SAY","CHAT_MSG_MONSTER_EMOTE","CHAT_MSG_MONSTER_YELL",
      "CHAT_MSG_MONSTER_WHISPER","CHAT_MSG_MONSTER_BOSS_EMOTE","CHAT_MSG_MONSTER_BOSS_WHISPER",
      "CHAT_MSG_RAID_BOSS_EMOTE","CHAT_MSG_RAID_BOSS_WHISPER",
  }},
  { key="REWARDS", label = "Rewards", events = {
      "CHAT_MSG_COMBAT_HONOR_GAIN","CHAT_MSG_COMBAT_FACTION_CHANGE",
      "CHAT_MSG_SKILL","CHAT_MSG_LOOT","CHAT_MSG_CURRENCY","CHAT_MSG_MONEY",
      "CHAT_MSG_COMBAT_XP_GAIN",
      "CHAT_MSG_TRADESKILLS","CHAT_MSG_OPENING",
      "CHAT_MSG_PET_INFO","CHAT_MSG_COMBAT_MISC_INFO",
  }},
  { key="PVP", label = "PvP", events = {
      "CHAT_MSG_BG_SYSTEM_HORDE","CHAT_MSG_BG_SYSTEM_ALLIANCE","CHAT_MSG_BG_SYSTEM_NEUTRAL",
  }},
  { key="SYSTEM", label = "System", events = {
      "CHAT_MSG_SYSTEM","CHAT_MSG_CHANNEL","CHAT_MSG_AFK","CHAT_MSG_DND",
      "CHAT_MSG_FILTERED","CHAT_MSG_RESTRICTED","CHAT_MSG_IGNORED",
      "CHAT_MSG_BN_INLINE_TOAST_ALERT",
      "CHAT_MSG_PET_BATTLE_COMBAT_LOG","CHAT_MSG_PET_BATTLE_INFO",
      "CHAT_MSG_PING",
  }},
  { key="ADDONS", label = "Addon Messages", events = {
      "LUI_ADDON",
  }},
}


-- ── Helpers ──────────────────────────────────────────────────────────

GetAccentColor = function()
  local t = NS.GetTheme(NS.DB("theme"))
  local tid = t.tilders or CYAN
  -- tilders can be array {r,g,b} or dict {r=,g=,b=} depending on how it was saved
  local r = tid[1] or tid.r or CYAN[1]
  local g = tid[2] or tid.g or CYAN[2]
  local b = tid[3] or tid.b or CYAN[3]
  return r, g, b
end

local function GetChatBgAlpha()
  local a = NS.DB("chatBgAlpha") or 0.5
  return 1 - a
end

local function GetTabBarBgAlpha()
  local a = NS.DB("chatTabBarAlpha") or 0.5
  return 1 - a
end

local function BuildFullEventSet()
  local es = {}
  for _, cat in ipairs(FILTER_CATS) do
    for _, ev in ipairs(cat.events) do es[ev] = true end
  end
  -- Do NOT add EVENT_PAIRS keys (INFORM variants) — they are controlled
  -- by their parent event via the routing logic in AddToDisplay/RedrawDisplay
  return es
end

-- Sync loot events across all tabs based on LucidUI state.
-- When active: remove loot events from non-loot tabs' eventSets.
-- When inactive: re-add them (by collapsing eventSet back to nil if all events are on).
NS.SyncLootEvents = function()
  RefreshLootRouting()
  local lootActive = lootRouting.active
  local lootEvents = {"CHAT_MSG_LOOT"}
  if lootRouting.showMoney    then table.insert(lootEvents, "CHAT_MSG_MONEY") end
  if lootRouting.showCurrency then table.insert(lootEvents, "CHAT_MSG_CURRENCY") end

  for tabIdx, td in ipairs(tabData) do
    if td._isLootTab then
      -- Ensure loot tab always has empty eventSet and blocked channels
      td.eventSet = {}
      td.channelBlocked = {General=true, Trade=true, LocalDefense=true, Services=true, LookingForGroup=true}
    else
      if lootActive then
        if not td.eventSet then
          td.eventSet = BuildFullEventSet()
        end
        for _, ev in ipairs(lootEvents) do
          td.eventSet[ev] = nil
        end
      else
        if td.eventSet then
          for _, ev in ipairs(lootEvents) do
            td.eventSet[ev] = true
          end
          local allOn = true
          for _, cat in ipairs(FILTER_CATS) do
            for _, ev in ipairs(cat.events) do
              if not td.eventSet[ev] then allOn = false; break end
            end
            if not allOn then break end
          end
          if allOn then td.eventSet = nil end
        end
      end
      -- Wipe cached tab messages so RedrawDisplay rebuilds with new filters
      tabMsgs[tabIdx] = nil
    end
  end
  SaveTabData()
end

-- ── Font helpers ─────────────────────────────────────────────────────

local function ApplyFontToDisplay(d)
  local font = NS.GetFontPath(NS.DB("chatFont") or NS.DB("font"))
  local size  = NS.DB("chatFontSize") or 14
  local outline = NS.DB("chatFontOutline") or ""
  if d.SetFont then d:SetFont(font, size, outline) end
end

local function ApplyFadeToDisplay(d)
  local fade = NS.DB("chatMessageFade")
  local t    = NS.DB("chatFadeTime") or 25
  if d.SetFading      then d:SetFading(fade and true or false) end
  if d.SetTimeVisible then d:SetTimeVisible(t) end
end

-- ── Tab data persistence ─────────────────────────────────────────────

SaveTabData = function()
  NS.DBSet("chatTabs", tabData)
end

local function LoadTabData()
  local saved = NS.DB("chatTabs")
  if saved and type(saved) == "table" then
    local keys = {}
    for k, v in pairs(saved) do
      if type(k) == "number" and type(v) == "table" then keys[#keys+1] = k end
    end
    table.sort(keys)
    tabData = {}
    for _, k in ipairs(keys) do tabData[#tabData+1] = saved[k] end
  end
  if not tabData or #tabData == 0 then
    tabData = { { name = "General", eventSet = BuildFullEventSet() } }
  end
  -- Migrate: if any tab has eventSet=nil, give it a full set
  for _, td in ipairs(tabData) do
    if not td.eventSet then
      td.eventSet = BuildFullEventSet()
    end
    -- Migrate: enable newly added events by default in existing eventSets
    -- Skip managed tabs (Whisper/Loot/CombatLog) - they have intentionally restricted eventSets
    if td.eventSet and not (td._isWhisperTab or td._isLootTab or td._isCombatLogTab) then
      local NEW_EVENTS = {
        "CHAT_MSG_TRADESKILLS","CHAT_MSG_OPENING","CHAT_MSG_PET_INFO","CHAT_MSG_COMBAT_MISC_INFO",
        "CHAT_MSG_PET_BATTLE_COMBAT_LOG","CHAT_MSG_PET_BATTLE_INFO","CHAT_MSG_PING",
      }
      for _, ev in ipairs(NEW_EVENTS) do
        if td.eventSet[ev] == nil then td.eventSet[ev] = true end
      end
    end
    -- Clean up INFORM keys from eventSet (they are controlled by parent event)
    if td.eventSet then
      for ev in pairs(EVENT_PAIRS) do
        td.eventSet[ev] = nil
      end
    end
  end
end

-- ── Message storage ──────────────────────────────────────────────────

local function StoreMessage(index, msg, r, g, b, t, event, channelName)
  local h = messageHistory[index]
  if not h then messageHistory[index] = {}; h = messageHistory[index] end
  h[#h+1] = {msg=msg, r=r, g=g, b=b, t=t, event=event, channelName=channelName}
  if #h > MAX_HISTORY then table.remove(h, 1) end
end

-- ── Tab flash ────────────────────────────────────────────────────────

local function StartTabFlash(tabIdx)
  local btn = tabButtons[tabIdx]
  if not btn or not btn._label then return end
  if tabFlashing[tabIdx] then return end
  tabFlashing[tabIdx] = true

  -- Use per-tab color if set, otherwise accent
  local td = tabData[tabIdx]
  local ar, ag, ab = GetAccentColor()
  if td and td.colorHex then
    ar = tonumber(td.colorHex:sub(1,2), 16) / 255
    ag = tonumber(td.colorHex:sub(3,4), 16) / 255
    ab = tonumber(td.colorHex:sub(5,6), 16) / 255
  end
  local elapsed = 0
  local flashFrame = btn._flashFrame
  if not flashFrame then flashFrame = CreateFrame("Frame"); btn._flashFrame = flashFrame end
  flashFrame:SetScript("OnUpdate", function(_, dt)
    if not tabFlashing[tabIdx] then
      flashFrame:SetScript("OnUpdate", nil)
      if btn._line then btn._line:Hide() end
      return
    end
    elapsed = elapsed + dt
    local alpha = 0.35 + 0.65 * math.abs(math.sin(elapsed * 3))
    btn._label:SetTextColor(ar, ag, ab, alpha)
    if btn._line then
      btn._line:SetColorTexture(ar, ag, ab, alpha)
      btn._line:Show()
    end
  end)
end

local function StopTabFlash(tabIdx)
  tabFlashing[tabIdx] = nil
  local btn = tabButtons[tabIdx]
  if btn and btn._label then
    local td = tabData[tabIdx]
    local tr, tg, tb = GetAccentColor()
    if td and td.colorHex then
      tr = tonumber(td.colorHex:sub(1,2), 16) / 255
      tg = tonumber(td.colorHex:sub(3,4), 16) / 255
      tb = tonumber(td.colorHex:sub(5,6), 16) / 255
    end
    if tabIdx == activeTab then
      btn._label:SetTextColor(tr, tg, tb, 1)
    else
      btn._label:SetTextColor(tr, tg, tb, 0.5)
    end
  end
end

-- ── Display rendering ────────────────────────────────────────────────

local isRerendering = false

RedrawDisplay = function(quickMode)
  if not customDisplays[1] then return end
  local d = customDisplays[1]

  -- Quick mode: just re-render existing messages (for accent/separator color changes)
  if quickMode then
    if d.Refresh then d:Refresh() end
    return
  end

  local td = tabData[activeTab]

  -- Combat Log tab: embed ChatFrame2 instead of our display
  if td and td._isCombatLogTab then
    local cf2 = _G["ChatFrame2"]
    if cf2 and NS.chatBg then
      pcall(function()
        if C_AddOns and C_AddOns.LoadAddOn then C_AddOns.LoadAddOn("Blizzard_CombatLog") end
      end)
      pcall(function() FCF_UnDockFrame(cf2) end)
      cf2:SetParent(NS.chatBg)
      cf2:ClearAllPoints()
      cf2:SetPoint("TOPLEFT", NS.chatBg, "TOPLEFT", 4, -(TAB_H + 2))
      cf2:SetPoint("BOTTOMRIGHT", NS.chatBg, "BOTTOMRIGHT", -4, 4)
      cf2:SetAlpha(1); cf2:Show()
      -- Hide ChatFrame2 chrome
      local cf2Tab = _G["ChatFrame2Tab"]
      if cf2Tab then cf2Tab:Hide(); cf2Tab:SetParent(hiddenFrame) end
      for _, name2 in ipairs({"ChatFrame2ButtonFrame","ChatFrame2EditBox",
          "ChatFrame2ResizeButton","ChatFrame2Background"}) do
        local f = _G[name2]
        if f then f:Hide(); f:SetParent(hiddenFrame) end
      end
      -- Show quick button bar
      local qbf = _G["CombatLogQuickButtonFrame_Custom"]
      if qbf then
        qbf:SetParent(NS.chatBg)
        qbf:ClearAllPoints()
        qbf:SetPoint("TOPLEFT", NS.chatBg, "TOPLEFT", 4, -(TAB_H + 2))
        qbf:SetPoint("TOPRIGHT", NS.chatBg, "TOPRIGHT", -4, -(TAB_H + 2))
        qbf:Show()
        qbf:SetFrameLevel(NS.chatBg:GetFrameLevel() + 3)
        cf2:ClearAllPoints()
        cf2:SetPoint("TOPLEFT", qbf, "BOTTOMLEFT", 0, -2)
        cf2:SetPoint("BOTTOMRIGHT", NS.chatBg, "BOTTOMRIGHT", -20, 4)
      end
      d:Hide()
    end
    return
  end

  -- Not combat log: restore ChatFrame2 to hidden if it was embedded
  local cf2 = _G["ChatFrame2"]
  if cf2 and NS.chatBg and cf2:GetParent() == NS.chatBg then
    cf2:SetParent(hiddenFrame); cf2:Hide()
    local qbf = _G["CombatLogQuickButtonFrame_Custom"]
    if qbf then qbf:SetParent(hiddenFrame); qbf:Hide() end
  end

  d:Clear()
  d:Show()

  local h = messageHistory[1]
  if not h then return end

  local flt = td and td.eventSet
  local createdAt = td and td.createdAt
  -- Quick mode: only last 20 for accent color changes. Full mode: all entries.
  local startIdx = quickMode and math.max(1, #h - 19) or 1
  for i = startIdx, #h do
    local entry = h[i]
    if createdAt and entry.t and entry.t < createdAt then
      -- skip
    else
      local show
      if not entry.event then
        show = true  -- addon/system messages without event tag always show
      elseif activeTab == 1 and entry.event == "LUI_ADDON" then
        show = true  -- addon messages always show in General tab
      elseif flt then
        show = flt[entry.event] or (EVENT_PAIRS[entry.event] and flt[EVENT_PAIRS[entry.event]]) or false
      else
        show = true  -- no filter = show all
      end
      -- Block messages from channels the tab has blocked
      if show and entry.channelName and td and td.channelBlocked and td.channelBlocked[entry.channelName] then
        show = false
      end
      if show then
        if not entry._clean then
          -- Message already formatted by our event handler — just cache it
          entry._clean = entry.msg or ""
          entry._ts = NS.ChatFormatTimestamp(entry.t)
        end
        d:AddMessage(entry._clean, entry.r, entry.g, entry.b, entry._ts, entry.t)
      end
    end
  end
  if d and d.GetMessages then tabMsgs[activeTab] = d:GetMessages() end
end



-- ── Direct event-based message engine ──────────────────────────────────
-- Instead of hooking ChatFrame1:AddMessage (gets Blizzard-formatted string),
-- we register our own events and format messages ourselves.
-- This gives us full control over styling, even for secret values.

local isSecretValue = issecretvalue or function() return false end

-- Channel prefix mapping: chatType → short label
local CHANNEL_LABELS = {
  SAY = "S", YELL = "Y", EMOTE = "", TEXT_EMOTE = "",
  GUILD = "G", OFFICER = "O",
  PARTY = "P", PARTY_LEADER = "PL",
  RAID = "R", RAID_LEADER = "RL", RAID_WARNING = "RW",
  INSTANCE_CHAT = "I", INSTANCE_CHAT_LEADER = "IL",
  WHISPER = "W", WHISPER_INFORM = "W",
  BN_WHISPER = "BN", BN_WHISPER_INFORM = "BN",
}

-- Chat type → Blizzard color info
local CHAT_TYPE_INFO = ChatTypeInfo or {}

-- System/no-sender events (pass message through as-is)
local SYSTEM_EVENTS = {
  CHAT_MSG_SYSTEM = true, CHAT_MSG_LOOT = true, CHAT_MSG_MONEY = true,
  CHAT_MSG_CURRENCY = true, CHAT_MSG_COMBAT_XP_GAIN = true,
  CHAT_MSG_COMBAT_HONOR_GAIN = true, CHAT_MSG_COMBAT_FACTION_CHANGE = true,
  CHAT_MSG_SKILL = true, CHAT_MSG_TRADESKILLS = true, CHAT_MSG_OPENING = true,
  CHAT_MSG_PET_INFO = true, CHAT_MSG_COMBAT_MISC_INFO = true,
  CHAT_MSG_BG_SYSTEM_HORDE = true, CHAT_MSG_BG_SYSTEM_ALLIANCE = true,
  CHAT_MSG_BG_SYSTEM_NEUTRAL = true, CHAT_MSG_ACHIEVEMENT = true,
  CHAT_MSG_GUILD_ACHIEVEMENT = true, CHAT_MSG_GUILD_ITEM_LOOTED = true,
  CHAT_MSG_BN_INLINE_TOAST_ALERT = true,
  CHAT_MSG_FILTERED = true, CHAT_MSG_RESTRICTED = true, CHAT_MSG_IGNORED = true,
  CHAT_MSG_PET_BATTLE_COMBAT_LOG = true, CHAT_MSG_PET_BATTLE_INFO = true,
  CHAT_MSG_PING = true,
}

-- Format a chat message from raw event data
local function FormatChatMessage(event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12)
  local chatType = event:gsub("^CHAT_MSG_", "")
  local msgProtected = isSecretValue(arg1)
  local senderProtected = isSecretValue(arg2)
  -- guidProtected check removed — pcall in class color lookup handles it

  -- Get color from Blizzard's ChatTypeInfo or custom colors
  local info = CHAT_TYPE_INFO[chatType]
  local cr, cg, cb = 1, 1, 1
  if info then cr, cg, cb = info.r or 1, info.g or 1, info.b or 1 end

  -- Apply custom message colors if configured
  if LucidUIDB and LucidUIDB.chatColors then
    local cc = LucidUIDB.chatColors[chatType]
    if cc then cr, cg, cb = cc.r, cc.g, cc.b end
  end

  -- System messages: pass through with our colors, no sender formatting
  if SYSTEM_EVENTS[event] then
    -- arg1 may be secret — use format() which works with secret values
    local body = arg1
    if not msgProtected and NS.ChatFormatURLs then
      body = NS.ChatFormatURLs(body)
    end
    return body, cr, cg, cb
  end

  -- Boss/Monster messages: show message with NPC name as sender
  local isBossMonster = chatType:sub(1, 9) == "RAID_BOSS" or chatType:sub(1, 7) == "MONSTER"

  local senderDisplay
  if isBossMonster then
    senderDisplay = "|cffffff00" .. (arg2 or "") .. "|r"
  else
    -- Resolver runs even with a secret arg2; the GUID path routes through
    -- C_ClassColor which accepts secret tokens at C++ level.
    local shortName = arg2
    if not senderProtected then
      local stripped = arg2
      if type(stripped) == "string" then
        local okS, s = pcall(string.gsub, stripped, "|K.-|k", "???")
        if okS and s then stripped = s end
      end
      local ambigMode = NS.DB("chatShowRealm") and "none" or "short"
      local ok, name = pcall(Ambiguate, stripped or "", ambigMode)
      if ok and name then shortName = name end
    end
    senderDisplay = shortName
    if NS.ChatGetColoredSender then
      local ok, result = pcall(NS.ChatGetColoredSender, arg12, shortName)
      if ok and result then senderDisplay = result end
    end
  end

  -- Build channel prefix
  local prefix = ""
  local channelFmt = NS.DB("chatShortenFormat") or "none"
  if event == "CHAT_MSG_CHANNEL" then
    -- Numbered channel: extract number from channelString (arg4)
    local chanNum = arg8 or ""
    local chanName = arg4 or ""
    if channelFmt == "bracket" then
      prefix = "(" .. chanNum .. ") "
    elseif channelFmt == "minimal" then
      prefix = chanNum .. " "
    else
      prefix = "[" .. chanName .. "] "
    end
  elseif chatType == "EMOTE" then
    -- Emote: "* Sender message"
    local body
    if msgProtected then
      body = string.format("* %s ", senderDisplay)
      -- Can't concat secret arg1, use format
      body = body .. arg1
    else
      body = string.format("* %s %s", senderDisplay, arg1 or "")
      if NS.ChatFormatURLs then body = NS.ChatFormatURLs(body) end
    end
    return body, cr, cg, cb
  elseif chatType == "TEXT_EMOTE" then
    -- Text emote: message already contains the player name
    local body = arg1
    if not msgProtected and NS.ChatFormatURLs then body = NS.ChatFormatURLs(body) end
    return body, cr, cg, cb
  else
    local label = CHANNEL_LABELS[chatType]
    if label and label ~= "" then
      if channelFmt == "bracket" then
        prefix = "(" .. label .. ") "
      elseif channelFmt == "minimal" then
        prefix = label .. " "
      else
        prefix = "[" .. label .. "] "
      end
    end
  end

  -- Whisper direction
  if chatType == "WHISPER_INFORM" or chatType == "BN_WHISPER_INFORM" then
    prefix = prefix .. "To "
  end

  -- Build final message: prefix + sender + ": " + message body
  local body
  if isBossMonster and chatType:find("EMOTE") then
    -- Boss emote: no colon, just name + message
    if msgProtected then
      body = string.format("%s%s ", prefix, senderDisplay) .. arg1
    else
      body = string.format("%s%s %s", prefix, senderDisplay, arg1 or "")
    end
  elseif msgProtected then
    -- Secret message: use format() to avoid taint
    body = string.format("%s%s: ", prefix, senderDisplay) .. arg1
  else
    body = string.format("%s%s: %s", prefix, senderDisplay, arg1 or "")
    if NS.ChatFormatURLs then body = NS.ChatFormatURLs(body) end
  end

  -- Strip Blizzard |K...|k redaction wrappers (cross-realm name hiding).
  -- Chattynator does the same in Core/Messages.lua CleanStore. Only safe to
  -- gsub if body is a non-secret string (secret strings would error).
  if type(body) == "string" and not isSecretValue(body) then
    local okK, stripped = pcall(string.gsub, body, "|K.-|k", "???")
    if okK and stripped then body = stripped end
  end

  return body, cr, cg, cb
end

-- All events we handle directly
local HANDLED_EVENTS = {
  "CHAT_MSG_SAY","CHAT_MSG_YELL","CHAT_MSG_EMOTE","CHAT_MSG_TEXT_EMOTE",
  "CHAT_MSG_GUILD","CHAT_MSG_OFFICER",
  "CHAT_MSG_WHISPER","CHAT_MSG_WHISPER_INFORM",
  "CHAT_MSG_BN_WHISPER","CHAT_MSG_BN_WHISPER_INFORM",
  "CHAT_MSG_PARTY","CHAT_MSG_PARTY_LEADER",
  "CHAT_MSG_RAID","CHAT_MSG_RAID_LEADER","CHAT_MSG_RAID_WARNING",
  "CHAT_MSG_INSTANCE_CHAT","CHAT_MSG_INSTANCE_CHAT_LEADER",
  "CHAT_MSG_LOOT","CHAT_MSG_MONEY","CHAT_MSG_CURRENCY",
  "CHAT_MSG_SYSTEM","CHAT_MSG_AFK","CHAT_MSG_DND",
  "CHAT_MSG_COMBAT_XP_GAIN","CHAT_MSG_COMBAT_HONOR_GAIN",
  "CHAT_MSG_COMBAT_FACTION_CHANGE","CHAT_MSG_SKILL",
  "CHAT_MSG_BG_SYSTEM_HORDE","CHAT_MSG_BG_SYSTEM_ALLIANCE","CHAT_MSG_BG_SYSTEM_NEUTRAL",
  "CHAT_MSG_MONSTER_SAY","CHAT_MSG_MONSTER_EMOTE","CHAT_MSG_MONSTER_YELL",
  "CHAT_MSG_MONSTER_WHISPER","CHAT_MSG_MONSTER_BOSS_EMOTE","CHAT_MSG_MONSTER_BOSS_WHISPER",
  "CHAT_MSG_RAID_BOSS_EMOTE","CHAT_MSG_RAID_BOSS_WHISPER",
  "CHAT_MSG_ACHIEVEMENT","CHAT_MSG_GUILD_ACHIEVEMENT","CHAT_MSG_GUILD_ITEM_LOOTED",
  "CHAT_MSG_BN_INLINE_TOAST_ALERT",
  "CHAT_MSG_FILTERED","CHAT_MSG_RESTRICTED","CHAT_MSG_IGNORED",
  "CHAT_MSG_VOICE_TEXT",
  "CHAT_MSG_TRADESKILLS","CHAT_MSG_OPENING","CHAT_MSG_PET_INFO","CHAT_MSG_COMBAT_MISC_INFO",
  "CHAT_MSG_PET_BATTLE_COMBAT_LOG","CHAT_MSG_PET_BATTLE_INFO",
  "CHAT_MSG_PING","CHAT_MSG_CHANNEL",
}

-- Track which events we handle (to suppress from Blizzard's ChatFrame1)
local HANDLED_SET = {}
for _, ev in ipairs(HANDLED_EVENTS) do HANDLED_SET[ev] = true end

-- Track when our event handler is processing (to skip AddMessage duplicates)
local _processingEvent = false

-- Register our own event frame to capture raw chat events
local chatEventFrame = CreateFrame("Frame")
for _, ev in ipairs(HANDLED_EVENTS) do
  pcall(chatEventFrame.RegisterEvent, chatEventFrame, ev)
end
-- Also register GUILD_MOTD to capture guild message of the day
pcall(chatEventFrame.RegisterEvent, chatEventFrame, "GUILD_MOTD")

chatEventFrame:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, ...)
  if not NS.DB("chatEnabled") then return end

  -- Handle GUILD_MOTD separately
  if event == "GUILD_MOTD" then
    local motd = arg1
    if not motd or motd == "" then
      -- Try C_Club API
      local guildID = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
      if guildID then
        local info = C_Club.GetClubInfo(guildID)
        if info then motd = info.broadcast end
      end
    end
    if motd and motd ~= "" and not (issecretvalue and issecretvalue(motd)) then
      local gi = ChatTypeInfo and ChatTypeInfo["GUILD"]
      local cr2, cg2, cb2 = gi and gi.r or 0.25, gi and gi.g or 1, gi and gi.b or 0.25
      local formatted = string.format(GUILD_MOTD_TEMPLATE or 'Guild Message of the Day: "%s"', motd)
      if displayReady then
        AddToDisplay(1, formatted, cr2, cg2, cb2, "CHAT_MSG_GUILD", nil)
      else
        earlyBuffer[#earlyBuffer + 1] = {msg=formatted, r=cr2, g=cg2, b=cb2, event="CHAT_MSG_GUILD", t=time()}
      end
    end
    return
  end

  _processingEvent = true
  local body, cr, cg, cb = FormatChatMessage(event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12)
  if not body then _processingEvent = false; return end

  -- Feed Dev Monitor Chat tab (only when monitor is open)
  if NS._devChatSMF and NS.Debug and NS.Debug.LogChat then
    local senderStr = (not isSecretValue(arg2)) and arg2 or "<secret>"
    local msgStr
    if not isSecretValue(arg1) and type(arg1) == "string" then
      msgStr = arg1:sub(1, 80)
    else
      msgStr = "<secret>"
    end
    NS.Debug.LogChat(event, senderStr, msgStr)
  end

  -- Extract channel name for channel messages
  local channelName = nil
  if event == "CHAT_MSG_CHANNEL" and arg4 then
    channelName = arg4:match("^%d+%.%s*(.+)") or arg4
  end

  if displayReady then
    AddToDisplay(1, body, cr, cg, cb, event, channelName)
  else
    earlyBuffer[#earlyBuffer + 1] = {msg=body, r=cr, g=cg, b=cb, event=event, channelName=channelName, t=time()}
  end
  _processingEvent = false
end)

-- Suppress handled events from Blizzard's ChatFrame1 (prevent double messages)
-- We use message filters that return true (= suppress) for events we handle ourselves
for _, ev in ipairs(HANDLED_EVENTS) do
  pcall(ChatFrame_AddMessageEventFilter, ev, function(self, event2, ...)
    if NS.DB("chatEnabled") then return true end
    return false
  end)
end

-- Still hook AddMessage for addon messages (DBM, WeakAuras, etc.) that call AddMessage directly
local f1 = ChatFrame1
if f1 then
  hooksecurefunc(f1, "AddMessage", function(self, msg, r, g, b, infoID, accessID, typeID, event, ...)
    if not NS.DB("chatEnabled") then return end
    if not msg then return end
    -- Skip if our event handler is currently processing (prevents duplicates)
    if _processingEvent then return end
    -- Skip if this was a handled event
    if event and HANDLED_SET[event] then return end
    -- Skip internal Blizzard event tags that leak as messages (e.g. "FRIEND_OFFLINE")
    local msgSafe = not (issecretvalue and issecretvalue(msg))
    if msgSafe and type(msg) == "string" and msg:match("^[A-Z_]+$") then return end
    -- Try to detect event type from color for guild/system messages
    local evTag = event or "LUI_ADDON"
    if not event then
      local gi = ChatTypeInfo and ChatTypeInfo["GUILD"]
      if gi and r and g and math.abs((r or 0) - (gi.r or 0)) < 0.02 and math.abs((g or 0) - (gi.g or 0)) < 0.02 then
        evTag = "CHAT_MSG_GUILD"
      end
    end
    local cr, cg, cb = r or 1, g or 1, b or 1
    local protected = isSecretValue(msg)
    if not protected then
      if NS.ChatFormatURLs then msg = NS.ChatFormatURLs(msg) end
    end
    if displayReady then
      AddToDisplay(1, msg, cr, cg, cb, evTag, nil)
    else
      earlyBuffer[#earlyBuffer + 1] = {msg=msg, r=cr, g=cg, b=cb, event=evTag, t=time()}
    end
  end)
end

-- ── AddToDisplay ─────────────────────────────────────────────────────

AddToDisplay = function(index, msg, r, g, b, event, channelName, unixTime)
  if not msg then return end
  local protected = issecretvalue and issecretvalue(msg)
  if not protected then
    local ok, safe = pcall(string.format, "%s", msg)
    if ok then msg = safe end
    -- Drop empty / whitespace-only messages: they render as zero-height
    -- FontStrings and collapse the anchor chain, causing adjacent messages
    -- to overlap visually (particularly visible after /reload history restore).
    if type(msg) ~= "string" or msg:match("^%s*$") then return end
  end
  local d = customDisplays[index]
  if not d then return end
  if not isRerendering then
    local t = unixTime or time()
    StoreMessage(index, msg, r, g, b, t, event, channelName)
    -- Message is already formatted by our event handler — no Blizzard cleanup needed
    local cleanMsg = msg
    local ts = NS.ChatFormatTimestamp(t)
    local processedMsg = {t = cleanMsg or "", r = r or 1, g = g or 1, b = b or 1, prefix = ts, ts = t}

    if index == 1 then
      -- Check if loot events should be suppressed from non-loot tabs
      local isLootEvent = event and (event == "CHAT_MSG_LOOT"
        or (event == "CHAT_MSG_MONEY" and lootRouting.showMoney)
        or (event == "CHAT_MSG_CURRENCY" and lootRouting.showCurrency))

      for tabIdx, td in ipairs(tabData) do
        local flt = td.eventSet
        local show
        if not event then
          show = true
        elseif tabIdx == 1 and event == "LUI_ADDON" then
          show = true
        elseif flt then
          show = flt[event] or (EVENT_PAIRS[event] and flt[EVENT_PAIRS[event]]) or false
        else
          show = true
        end
        if show and td.createdAt and t < td.createdAt then show = false end
        -- Suppress loot events from non-loot tabs
        if show and lootRouting.active and isLootEvent and not td._isLootTab then
          show = false
        end
        -- Block messages from channels the tab has blocked
        if show and channelName and td.channelBlocked and td.channelBlocked[channelName] then
          show = false
        end
        -- Skip whisper tabs for restored history (they only show live messages)
        if show and td._isWhisperTab and restoringHistory then show = false end
        if show then
          if tabIdx == activeTab then
            d:AddMessage(cleanMsg, r, g, b, ts, t)
          else
            if not tabMsgs[tabIdx] then tabMsgs[tabIdx] = {} end
            local tm = tabMsgs[tabIdx]
            tm[#tm+1] = processedMsg
            if #tm > MAX_HISTORY then table.remove(tm, 1) end
            -- Flash based on setting: "all", "whisper", or "never"
            local flashMode = NS.DB("chatTabFlash") or "all"
            if flashMode == "all" then
              StartTabFlash(tabIdx)
            elseif flashMode == "whisper" and (event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_BN_WHISPER") then
              StartTabFlash(tabIdx)
            end
          end
        end
      end
    else
      d:AddMessage(msg, r, g, b)

    end
    return
  end
  d:AddMessage(msg, r, g, b)
end

-- ── Tab bar ──────────────────────────────────────────────────────────

local measureFS = nil
local function GetTabFont()
  local font = NS.GetFontPath(NS.DB("chatFont") or NS.DB("font"))
  local size = (NS.DB("chatFontSize") or 14) - 2
  local outline = NS.DB("chatFontOutline") or ""
  return font, size, outline
end

local function MeasureTabWidth(text)
  if not measureFS then
    measureFS = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    measureFS:Hide()
  end
  local font, size, outline = GetTabFont()
  measureFS:SetFont(font, size, outline)
  measureFS:SetText(text or "")
  return math.max(measureFS:GetStringWidth() + 16, 40)
end

local function RefreshButtonVisuals()
  local ar, ag, ab = GetAccentColor()
  local showTabSep = NS.DB("chatTabSeparator") == true
  local showTabBg  = NS.DB("chatTabHighlightBg") ~= false
  for k, b in ipairs(tabButtons) do
    local td2 = tabData[k]
    if td2 and b._label then
      b._label:SetText(td2.name)
      b:SetWidth(MeasureTabWidth(td2.name))
      -- Per-tab custom color (e.g. whisper tabs get #ff80ff)
      local tr, tg, tb = ar, ag, ab
      if td2.colorHex then
        tr = tonumber(td2.colorHex:sub(1,2), 16) / 255
        tg = tonumber(td2.colorHex:sub(3,4), 16) / 255
        tb = tonumber(td2.colorHex:sub(5,6), 16) / 255
      end
      local isCurrent = (k == activeTab)
      if isCurrent then
        b._bg:SetColorTexture(tr, tg, tb, showTabBg and 0.12 or 0)
        b._line:SetColorTexture(ar, ag, ab, 1); b._line:Show()
        b._label:SetTextColor(tr, tg, tb, 1)
      else
        b._bg:SetColorTexture(0, 0, 0, 0)
        b._line:Hide()
        b._label:SetTextColor(tr, tg, tb, 0.5)
      end
      -- Tab separator accent line visibility
      if b._sep then
        b._sep:SetColorTexture(ar, ag, ab, 0.35)
        b._sep:SetShown(showTabSep)
      end
    end
  end
end

-- Scroll offset for tab overflow (0-based, how many scrollable tabs to skip)
local tabScrollOffset = 0
local tabScrollLeft, tabScrollRight = nil, nil
local SCROLL_ARROW_W = 14

local function CreateScrollArrows()
  if tabScrollLeft then return end
  local ar, ag, ab = GetAccentColor()

  tabScrollLeft = CreateFrame("Button", nil, tabBarFrame)
  tabScrollLeft:SetSize(SCROLL_ARROW_W, TAB_H - 2)
  tabScrollLeft:SetFrameLevel(tabBarFrame:GetFrameLevel() + 3)
  local lbl1 = tabScrollLeft:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  lbl1:SetPoint("CENTER"); lbl1:SetText("<"); lbl1:SetTextColor(0.55, 0.55, 0.55, 1)
  tabScrollLeft:SetScript("OnClick", function()
    tabScrollOffset = math.max(0, tabScrollOffset - 1)
    RepositionButtons()
  end)
  tabScrollLeft:SetScript("OnEnter", function() lbl1:SetTextColor(ar, ag, ab, 1) end)
  tabScrollLeft:SetScript("OnLeave", function() lbl1:SetTextColor(0.55, 0.55, 0.55, 1) end)

  tabScrollRight = CreateFrame("Button", nil, tabBarFrame)
  tabScrollRight:SetSize(SCROLL_ARROW_W, TAB_H - 2)
  tabScrollRight:SetFrameLevel(tabBarFrame:GetFrameLevel() + 3)
  local lbl2 = tabScrollRight:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  lbl2:SetPoint("CENTER"); lbl2:SetText(">"); lbl2:SetTextColor(0.55, 0.55, 0.55, 1)
  tabScrollRight:SetScript("OnClick", function()
    tabScrollOffset = tabScrollOffset + 1
    RepositionButtons()
  end)
  tabScrollRight:SetScript("OnEnter", function() lbl2:SetTextColor(ar, ag, ab, 1) end)
  tabScrollRight:SetScript("OnLeave", function() lbl2:SetTextColor(0.55, 0.55, 0.55, 1) end)
end

-- Drag indicator lines (created once)
local dragIndLeft, dragIndRight = nil, nil
local function ShowDragIndicator(targetBtn)
  if not tabBarFrame then return end
  if not dragIndLeft then
    local ar2, ag2, ab2 = GetAccentColor()
    dragIndLeft = tabBarFrame:CreateTexture(nil, "OVERLAY")
    dragIndLeft:SetWidth(2); dragIndLeft:SetColorTexture(ar2, ag2, ab2, 1)
    dragIndRight = tabBarFrame:CreateTexture(nil, "OVERLAY")
    dragIndRight:SetWidth(2); dragIndRight:SetColorTexture(ar2, ag2, ab2, 1)
  end
  dragIndLeft:ClearAllPoints()
  dragIndLeft:SetPoint("TOP", targetBtn, "TOPLEFT", -1, -2)
  dragIndLeft:SetPoint("BOTTOM", targetBtn, "BOTTOMLEFT", -1, 2)
  dragIndLeft:Show()
  dragIndRight:ClearAllPoints()
  dragIndRight:SetPoint("TOP", targetBtn, "TOPRIGHT", 1, -2)
  dragIndRight:SetPoint("BOTTOM", targetBtn, "BOTTOMRIGHT", 1, 2)
  dragIndRight:Show()
end
local function HideDragIndicator()
  if dragIndLeft then dragIndLeft:Hide() end
  if dragIndRight then dragIndRight:Hide() end
end

RepositionButtons = function()
  if not tabBarFrame then return end
  local barWidth = tabBarFrame:GetWidth()
  if not barWidth or barWidth < 10 then barWidth = 400 end
  local addBtnW = (addBtn and #tabData < MAX_TABS) and 26 or 0

  -- Tab 1 always visible at position 0
  local fixedX = 4
  if tabButtons[1] then
    tabButtons[1]:ClearAllPoints()
    tabButtons[1]:SetPoint("BOTTOMLEFT", tabBarFrame, "BOTTOMLEFT", fixedX, 1)
    tabButtons[1]:Show()
    fixedX = fixedX + tabButtons[1]:GetWidth() + TAB_SPACING
  end

  if #tabButtons <= 1 then
    tabEndX = fixedX
    if tabScrollLeft then tabScrollLeft:Hide(); tabScrollRight:Hide() end
    if addBtn then
      addBtn:ClearAllPoints()
      addBtn:SetPoint("BOTTOMLEFT", tabBarFrame, "BOTTOMLEFT", tabEndX + 2, 1)
      addBtn:SetShown(#tabData < MAX_TABS)
    end
    return
  end

  -- Check if all scrollable tabs (2+) fit without arrows
  local scrollTotalW = 0
  for idx = 2, #tabButtons do
    scrollTotalW = scrollTotalW + tabButtons[idx]:GetWidth() + TAB_SPACING
  end

  local availableW = barWidth - fixedX - addBtnW - 4

  if scrollTotalW <= availableW then
    -- All fit, no scrolling
    tabScrollOffset = 0
    if tabScrollLeft then tabScrollLeft:Hide(); tabScrollRight:Hide() end
    local sx = fixedX
    for idx = 2, #tabButtons do
      tabButtons[idx]:ClearAllPoints()
      tabButtons[idx]:SetPoint("BOTTOMLEFT", tabBarFrame, "BOTTOMLEFT", sx, 1)
      tabButtons[idx]:Show()
      sx = sx + tabButtons[idx]:GetWidth() + TAB_SPACING
    end
    tabEndX = sx
  else
    -- Need scrolling
    CreateScrollArrows()
    local arrowW = SCROLL_ARROW_W + 2
    local scrollCount = #tabButtons - 1  -- tabs 2+

    -- Clamp offset
    local maxOffset = math.max(0, scrollCount - 1)
    tabScrollOffset = math.max(0, math.min(tabScrollOffset, maxOffset))

    local showLeft = tabScrollOffset > 0
    local showRight = true  -- will be refined below
    tabScrollLeft:SetShown(showLeft)

    local sx = fixedX
    if showLeft then
      tabScrollLeft:ClearAllPoints()
      tabScrollLeft:SetPoint("BOTTOMLEFT", tabBarFrame, "BOTTOMLEFT", sx, 1)
      sx = sx + arrowW
    end

    local rightReserve = arrowW
    local maxSX = barWidth - addBtnW - rightReserve - 4
    local lastVisible = 1

    for idx = 2, #tabButtons do
      local scrollIdx = idx - 1  -- 1-based in scrollable set
      if scrollIdx <= tabScrollOffset then
        tabButtons[idx]:Hide()
      else
        local bw = tabButtons[idx]:GetWidth()
        if sx + bw <= maxSX then
          tabButtons[idx]:ClearAllPoints()
          tabButtons[idx]:SetPoint("BOTTOMLEFT", tabBarFrame, "BOTTOMLEFT", sx, 1)
          tabButtons[idx]:Show()
          sx = sx + bw + TAB_SPACING
          lastVisible = idx
        else
          tabButtons[idx]:Hide()
        end
      end
    end

    showRight = lastVisible < #tabButtons
    tabScrollRight:SetShown(showRight)
    if showRight then
      tabScrollRight:ClearAllPoints()
      tabScrollRight:SetPoint("BOTTOMLEFT", tabBarFrame, "BOTTOMLEFT", sx, 1)
      sx = sx + arrowW
    end

    tabEndX = sx
  end

  if addBtn then
    addBtn:ClearAllPoints()
    addBtn:SetPoint("BOTTOMLEFT", tabBarFrame, "BOTTOMLEFT", tabEndX + 2, 1)
    addBtn:SetShown(#tabData < MAX_TABS)
  end
end

-- Filter panel removed — now handled by Tab Settings tab in ChatOptions

-- ── RebuildTabButtons ────────────────────────────────────────────────

RebuildTabButtons = function()
  if not tabBarFrame then return end
  for _, btn in ipairs(tabButtons) do btn:Hide(); btn:SetParent(hiddenFrame) end
  tabButtons = {}
  local ar, ag, ab = GetAccentColor()
  local xOff = 4

  for i, td in ipairs(tabData) do
    local btn = CreateFrame("Button", nil, tabBarFrame)
    btn:SetHeight(TAB_H - 2)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    btn:SetFrameLevel(tabBarFrame:GetFrameLevel() + 2)

    local w = MeasureTabWidth(td.name)
    btn:SetWidth(w)
    btn:SetPoint("BOTTOMLEFT", tabBarFrame, "BOTTOMLEFT", xOff, 1)
    xOff = xOff + w + TAB_SPACING

    local bgTex = btn:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints()
    btn._bg = bgTex

    local line = btn:CreateTexture(nil, "BORDER")
    line:SetHeight(2)
    line:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    btn._line = line

    if i > 1 then
      local sep = btn:CreateTexture(nil, "ARTWORK")
      sep:SetWidth(1)
      sep:SetPoint("TOPLEFT", btn, "TOPLEFT", -1, -3)
      sep:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", -1, 3)
      sep:SetColorTexture(ar, ag, ab, 0.35)
      sep:SetShown(NS.DB("chatTabSeparator") == true)
      btn._sep = sep
    end

    local label = btn:CreateFontString(nil, "OVERLAY")
    local tabFont, tabSize, tabOutline = GetTabFont()
    label:SetFont(tabFont, tabSize, tabOutline)
    label:SetAllPoints()
    label:SetJustifyH("CENTER")
    label:SetText(td.name)
    btn._label = label

    -- Tab 1 (General): drag moves the whole chat frame
    -- Tabs 2+: drag to reorder
    btn:RegisterForDrag("LeftButton")
    if i == 1 then
      btn:SetScript("OnDragStart", function()
        if not NS.chatBg then return end
        if NS.DB("chatLocked") then return end
        NS.chatBg:StartMoving()
      end)
      btn:SetScript("OnDragStop", function()
        if not NS.chatBg then return end
        NS.chatBg:StopMovingOrSizing()
        local x, y = NS.chatBg:GetLeft(), NS.chatBg:GetBottom()
        if x and y then
          NS.chatBg:ClearAllPoints()
          NS.chatBg:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
          NS.DBSet("chatWinPos", {x=x, y=y})
        end
      end)
    else
      local wasDragging = false
      btn:SetScript("OnDragStart", function()
        wasDragging = true
        ShowDragIndicator(btn)
        tabBarFrame:SetScript("OnUpdate", function()
          local myIdx
          for k2, b2 in ipairs(tabButtons) do if b2 == btn then myIdx = k2; break end end
          if not myIdx then return end
          local curX = GetCursorPosition() / UIParent:GetEffectiveScale()
          ShowDragIndicator(btn)
          -- Swap left (never past index 2, General stays at 1)
          if myIdx > 2 then
            local lb = tabButtons[myIdx - 1]
            if lb:IsShown() and curX < (lb:GetLeft() or 0) + lb:GetWidth() * 0.5 then
              tabData[myIdx], tabData[myIdx-1] = tabData[myIdx-1], tabData[myIdx]
              tabButtons[myIdx], tabButtons[myIdx-1] = tabButtons[myIdx-1], tabButtons[myIdx]
              tabMsgs[myIdx], tabMsgs[myIdx-1] = tabMsgs[myIdx-1], tabMsgs[myIdx]
              if activeTab == myIdx then activeTab = myIdx-1
              elseif activeTab == myIdx-1 then activeTab = myIdx end
              RefreshButtonVisuals(); RepositionButtons()
              ShowDragIndicator(btn)
              return
            end
          end
          -- Swap right
          if myIdx < #tabButtons then
            local rb = tabButtons[myIdx + 1]
            if rb:IsShown() and curX > (rb:GetLeft() or 0) + rb:GetWidth() * 0.5 then
              tabData[myIdx], tabData[myIdx+1] = tabData[myIdx+1], tabData[myIdx]
              tabButtons[myIdx], tabButtons[myIdx+1] = tabButtons[myIdx+1], tabButtons[myIdx]
              tabMsgs[myIdx], tabMsgs[myIdx+1] = tabMsgs[myIdx+1], tabMsgs[myIdx]
              if activeTab == myIdx then activeTab = myIdx+1
              elseif activeTab == myIdx+1 then activeTab = myIdx end
              RefreshButtonVisuals(); RepositionButtons()
              ShowDragIndicator(btn)
              return
            end
          end
        end)
      end)
      btn:SetScript("OnDragStop", function()
        tabBarFrame:SetScript("OnUpdate", nil)
        HideDragIndicator()
        if wasDragging then
          wasDragging = false
          SaveTabData()
          RebuildTabButtons()
        end
      end)
    end

    local capturedI = i
    btn:SetScript("OnClick", function(_, mouseButton)
      if mouseButton == "LeftButton" then
        local oldTab = activeTab
        activeTab = capturedI
        StopTabFlash(capturedI)
        if tabData[capturedI] then tabData[capturedI]._unread = nil; SaveTabData() end
        local d = customDisplays[1]
        if d and d.GetMessages then tabMsgs[oldTab] = d:GetMessages() end
        RefreshButtonVisuals()
        -- Hide combat log if leaving it
        local oldTd = tabData[oldTab]
        if oldTd and oldTd._isCombatLogTab then
          local cf2 = _G["ChatFrame2"]
          if cf2 and NS.chatBg and cf2:GetParent() == NS.chatBg then
            cf2:SetParent(hiddenFrame); cf2:Hide()
            local qbf = _G["CombatLogQuickButtonFrame_Custom"]
            if qbf then qbf:SetParent(hiddenFrame); qbf:Hide() end
          end
          if d then d:Show() end
        end
        -- Combat log tab or missing cache: full redraw
        local td2 = tabData[activeTab]
        if td2 and td2._isCombatLogTab then
          isRerendering = true; RedrawDisplay(); isRerendering = false
        elseif d then
          if tabMsgs[activeTab] then
            d:SwapMessages(tabMsgs[activeTab])
          else
            isRerendering = true; RedrawDisplay(); isRerendering = false
          end
        end

      elseif mouseButton == "RightButton" then
        MenuUtil.CreateContextMenu(btn, function(_, root)
          -- Rename (not for managed tabs — General tab CAN be renamed)
          local isManagedTab = tabData[capturedI] and
            (tabData[capturedI]._isLootTab or tabData[capturedI]._isWhisperTab or tabData[capturedI]._isCombatLogTab)
          if not isManagedTab then
            root:CreateButton(L["Rename"], function()
              if not StaticPopupDialogs["LUI_CHAT_RENAME_TAB"] then
                StaticPopupDialogs["LUI_CHAT_RENAME_TAB"] = {
                  text = L["popup_tab_rename"],
                  button1 = ACCEPT, button2 = CANCEL,
                  hasEditBox = true, maxLetters = 32,
                  OnAccept = function(dialog)
                    local name = dialog.EditBox:GetText()
                    if name and name ~= "" then
                      tabData[dialog._ltTabIndex].name = name
                      RebuildTabButtons(); SaveTabData()
                    end
                  end,
                  EditBoxOnEnterPressed = function(editBox)
                    local parent = editBox:GetParent()
                    local name = editBox:GetText()
                    if name and name ~= "" then
                      tabData[parent._ltTabIndex].name = name
                      RebuildTabButtons(); SaveTabData()
                    end
                    parent:Hide()
                  end,
                  timeout = 0, whileDead = true, hideOnEscape = true,
                }
              end
              local popup = StaticPopup_Show("LUI_CHAT_RENAME_TAB")
              if popup then
                popup._ltTabIndex = capturedI
                popup.EditBox:SetText(tabData[capturedI].name)
                popup.EditBox:HighlightText(); popup.EditBox:SetFocus()
              end
            end)
          end

          -- Filter (opens Tab Settings tab in settings dialog)
          root:CreateButton(L["Filter"], function()
            if NS.OpenChatTabSettings then
              NS.OpenChatTabSettings(capturedI)
            end
          end)

          -- Tab Color
          root:CreateButton(L["Tab Color"], function()
            local td2 = tabData[capturedI]
            local ar2, ag2, ab2 = GetAccentColor()
            local r0, g0, b0
            if td2.colorHex then
              r0 = tonumber(td2.colorHex:sub(1,2), 16) / 255
              g0 = tonumber(td2.colorHex:sub(3,4), 16) / 255
              b0 = tonumber(td2.colorHex:sub(5,6), 16) / 255
            else
              r0, g0, b0 = ar2, ag2, ab2
            end
            local oldHex = td2.colorHex
            ColorPickerFrame:SetupColorPickerAndShow({
              r = r0, g = g0, b = b0,
              swatchFunc = function()
                local rn, gn, bn = ColorPickerFrame:GetColorRGB()
                td2.colorHex = string.format("%02x%02x%02x", rn*255, gn*255, bn*255)
                RefreshButtonVisuals()
                SaveTabData()
              end,
              cancelFunc = function()
                td2.colorHex = oldHex
                RefreshButtonVisuals()
              end,
            })
          end)

          -- Reset tab color
          if tabData[capturedI] and tabData[capturedI].colorHex then
            root:CreateButton(L["Reset Color"], function()
              tabData[capturedI].colorHex = nil
              RefreshButtonVisuals()
              SaveTabData()
            end)
          end

          -- Lock/Unlock
          local isLocked = NS.DB("chatLocked")
          root:CreateButton(isLocked and "Unlock Frame" or "Lock Frame", function()
            local newLocked = not NS.DB("chatLocked")
            NS.DBSet("chatLocked", newLocked)
            if NS.chatResizeBtn then NS.chatResizeBtn:SetShown(not newLocked) end
          end)

          root:CreateDivider()

          -- Close tab (not for General, Loot or Combat Log tab)
          local isProtectedTab = tabData[capturedI] and
            (tabData[capturedI]._isLootTab or tabData[capturedI]._isCombatLogTab)
          if capturedI ~= 1 and #tabData > 1 and not isProtectedTab then
            root:CreateButton("|cffff4444Close Tab|r", function()
              tabMsgs[capturedI] = nil
              table.remove(tabData, capturedI)
              -- Shift tabMsgs indices down
              for idx = capturedI, #tabData do
                tabMsgs[idx] = tabMsgs[idx + 1]
              end
              tabMsgs[#tabData + 1] = nil
              if activeTab >= capturedI then activeTab = math.max(1, activeTab - 1) end
              tabScrollOffset = 0
              RebuildTabButtons()
              isRerendering = true; RedrawDisplay(); isRerendering = false
              SaveTabData()
            end)
          end
        end)

      elseif mouseButton == "MiddleButton" and capturedI ~= 1 and #tabData > 1
        and not (tabData[capturedI] and (tabData[capturedI]._isLootTab or tabData[capturedI]._isCombatLogTab)) then
        tabMsgs[capturedI] = nil
        table.remove(tabData, capturedI)
        for idx = capturedI, #tabData do
          tabMsgs[idx] = tabMsgs[idx + 1]
        end
        tabMsgs[#tabData + 1] = nil
        if activeTab >= capturedI then activeTab = math.max(1, activeTab - 1) end
        tabScrollOffset = 0
        RebuildTabButtons()
        isRerendering = true; RedrawDisplay(); isRerendering = false
        SaveTabData()
      end
    end)

    btn:SetScript("OnEnter", function()
      if capturedI ~= activeTab and btn._label then
        local td3 = tabData[capturedI]
        local tr, tg, tb = GetAccentColor()
        if td3 and td3.colorHex then
          tr = tonumber(td3.colorHex:sub(1,2), 16) / 255
          tg = tonumber(td3.colorHex:sub(3,4), 16) / 255
          tb = tonumber(td3.colorHex:sub(5,6), 16) / 255
        end
        btn._label:SetTextColor(tr, tg, tb, 1)
      end
    end)
    btn:SetScript("OnLeave", function()
      if capturedI ~= activeTab and btn._label then
        local td3 = tabData[capturedI]
        local tr, tg, tb = GetAccentColor()
        if td3 and td3.colorHex then
          tr = tonumber(td3.colorHex:sub(1,2), 16) / 255
          tg = tonumber(td3.colorHex:sub(3,4), 16) / 255
          tb = tonumber(td3.colorHex:sub(5,6), 16) / 255
        end
        btn._label:SetTextColor(tr, tg, tb, 0.5)
      end
    end)

    tabButtons[i] = btn
  end

  RefreshButtonVisuals()
  -- Use RepositionButtons for proper overflow handling
  C_Timer.After(0, RepositionButtons)
  if addBtn then
    addBtn:SetShown(#tabData < MAX_TABS)
  end
end

-- ── Build tab bar ────────────────────────────────────────────────────

local function BuildTabBar(bg)
  tabBarFrame = CreateFrame("Frame", "LUIChatTabBar", bg)
  tabBarFrame:SetPoint("TOPLEFT", bg, "TOPLEFT", 0, 0)
  tabBarFrame:SetPoint("TOPRIGHT", bg, "TOPRIGHT", 0, 0)
  tabBarFrame:SetHeight(TAB_H)
  tabBarFrame:SetFrameLevel(bg:GetFrameLevel() + 2)
  tabBarFrame:SetScript("OnSizeChanged", function()
    C_Timer.After(0, function() RepositionButtons() end)
  end)

  local tabBarBg = tabBarFrame:CreateTexture(nil, "BACKGROUND")
  tabBarBg:SetColorTexture(0, 0, 0, GetTabBarBgAlpha())
  -- Stretch tab bar background to cover the icon bar area
  local pos = NS.DB("chatBarPosition") or "outside_right"
  local barW = NS.chatBarRef and NS.chatBarRef:GetWidth() or 32
  if pos == "outside_right" then
    tabBarBg:SetPoint("TOPLEFT", tabBarFrame, "TOPLEFT", 0, 0)
    tabBarBg:SetPoint("BOTTOMRIGHT", tabBarFrame, "BOTTOMRIGHT", barW, 0)
  elseif pos == "outside_left" then
    tabBarBg:SetPoint("TOPLEFT", tabBarFrame, "TOPLEFT", -barW, 0)
    tabBarBg:SetPoint("BOTTOMRIGHT", tabBarFrame, "BOTTOMRIGHT", 0, 0)
  else
    tabBarBg:SetAllPoints()
  end
  NS.chatTabBarBg = tabBarBg

  LoadTabData()
  RebuildTabButtons()

  -- Restore flash for unread whisper tabs
  for i, td in ipairs(tabData) do
    if td._unread and i ~= activeTab then
      C_Timer.After(0.5, function() StartTabFlash(i) end)
    end
  end

  -- "+" button
  local ar2, ag2, ab2 = GetAccentColor()
  addBtn = CreateFrame("Button", nil, tabBarFrame)
  local addIconSize = TAB_H - 8
  addBtn:SetSize(addIconSize + 6, TAB_H - 2)
  addBtn:SetFrameLevel(tabBarFrame:GetFrameLevel() + 2)
  addBtn:EnableMouse(true)
  addBtn:RegisterForClicks("LeftButtonUp")
  local addIcon = addBtn:CreateTexture(nil, "ARTWORK")
  addIcon:SetTexture("Interface/AddOns/LucidUI/Assets/NewTab.png")
  addIcon:SetSize(addIconSize, addIconSize)
  addIcon:SetPoint("CENTER")
  addIcon:SetVertexColor(0.45, 0.45, 0.45, 1)
  addBtn:SetScript("OnEnter", function() addIcon:SetVertexColor(ar2, ag2, ab2, 1) end)
  addBtn:SetScript("OnLeave", function() addIcon:SetVertexColor(0.45, 0.45, 0.45, 1) end)
  addBtn:SetScript("OnClick", function()
    if #tabData >= MAX_TABS then return end
    local baseName = "New Tab"
    local name = baseName
    local suffix = 1
    local used = {}
    for _, td in ipairs(tabData) do used[td.name] = true end
    while used[name] do name = baseName .. suffix; suffix = suffix + 1 end
    local newES = BuildFullEventSet()
    -- If whisper tabs are enabled, remove whisper events from new tab
    if NS.DB("chatWhisperTab") then
      newES["CHAT_MSG_WHISPER"] = nil
      newES["CHAT_MSG_BN_WHISPER"] = nil
    end
    table.insert(tabData, {name=name, eventSet=newES, createdAt=time()+1})
    NS.SyncLootEvents()
    activeTab = #tabData
    -- Start with empty buffer (no history)
    tabMsgs[activeTab] = {}
    RebuildTabButtons()
    -- Don't RedrawDisplay — new tab starts empty
    if customDisplays[1] then customDisplays[1]:Clear() end
    SaveTabData()
  end)
  addBtn:ClearAllPoints()
  addBtn:SetPoint("BOTTOMLEFT", tabBarFrame, "BOTTOMLEFT", tabEndX + 2, 1)
  addBtn:SetShown(#tabData < MAX_TABS)

  tabBarFrame:EnableMouse(true)

  -- ── Voice Mute/Deafen buttons (right side of tab bar) ───────────────
  local VB_SIZE = 18
  local VB_PAD = -30

  local isMuted, isDeafened = false, false
  local voiceButtonsVisible = false

  local function GetVoiceIconColor()
    local ic = NS.DB("chatIconColor")
    if ic and type(ic) == "table" and ic.r then return ic.r, ic.g, ic.b end
    return 0.6, 0.6, 0.6
  end

  -- Mute button
  local muteBtn = CreateFrame("Button", nil, tabBarFrame)
  muteBtn:SetSize(VB_SIZE, VB_SIZE)
  muteBtn:SetFrameLevel(tabBarFrame:GetFrameLevel() + 3)
  local muteTex = muteBtn:CreateTexture(nil, "ARTWORK")
  muteTex:SetSize(VB_SIZE, VB_SIZE); muteTex:SetPoint("CENTER")
  muteTex:SetTexture("Interface/AddOns/LucidUI/Assets/ChatFrameToggleVoiceMuteButton.png")
  do local r2,g2,b2 = GetVoiceIconColor(); muteTex:SetVertexColor(r2, g2, b2, 1) end
  local function RefreshMuteIcon()
    if isMuted then
      muteTex:SetTexture("Interface/AddOns/LucidUI/Assets/ChatFrameToggleVoiceMuteButton_muted.png")
      muteTex:SetVertexColor(1, 1, 1, 1)  -- white when muted
    else
      muteTex:SetTexture("Interface/AddOns/LucidUI/Assets/ChatFrameToggleVoiceMuteButton.png")
      muteTex:SetVertexColor(0, 0.8, 0, 1)  -- green when active
    end
  end
  muteBtn:SetScript("OnClick", function()
    if C_VoiceChat and C_VoiceChat.IsLoggedIn and C_VoiceChat.IsLoggedIn() then
      C_VoiceChat.ToggleSelfMute()
          isMuted = C_VoiceChat.IsSelfMuted and C_VoiceChat.IsSelfMuted() or false
      
      RefreshMuteIcon()
    end
  end)
  muteBtn:SetScript("OnEnter", function()
    muteTex:SetVertexColor(NS.CYAN[1], NS.CYAN[2], NS.CYAN[3], 1)
    GameTooltip:SetOwner(muteBtn, "ANCHOR_LEFT")
    GameTooltip:SetText(isMuted and "Unmute" or "Mute"); GameTooltip:Show()
  end)
  muteBtn:SetScript("OnLeave", function()
    RefreshMuteIcon(); GameTooltip:Hide()
  end)

  -- Deafen button
  local deafenBtn = CreateFrame("Button", nil, tabBarFrame)
  deafenBtn:SetSize(VB_SIZE, VB_SIZE)
  deafenBtn:SetFrameLevel(tabBarFrame:GetFrameLevel() + 3)
  local deafenTex = deafenBtn:CreateTexture(nil, "ARTWORK")
  deafenTex:SetSize(VB_SIZE, VB_SIZE); deafenTex:SetPoint("CENTER")
  deafenTex:SetTexture("Interface/AddOns/LucidUI/Assets/ChatFrameToggleVoiceDeafenButton.png")
  do local r2,g2,b2 = GetVoiceIconColor(); deafenTex:SetVertexColor(r2, g2, b2, 1) end
  local function RefreshDeafenIcon()
    if isDeafened then
      deafenTex:SetTexture("Interface/AddOns/LucidUI/Assets/ChatFrameToggleVoiceDeafenButton_deafened.png")
      deafenTex:SetVertexColor(1, 1, 1, 1)  -- white when deafened
    else
      deafenTex:SetTexture("Interface/AddOns/LucidUI/Assets/ChatFrameToggleVoiceDeafenButton.png")
      deafenTex:SetVertexColor(0, 0.8, 0, 1)  -- green when active
    end
  end
  deafenBtn:SetScript("OnClick", function()
    if C_VoiceChat and C_VoiceChat.IsLoggedIn and C_VoiceChat.IsLoggedIn() then
      C_VoiceChat.ToggleSelfDeafen()
          isDeafened = C_VoiceChat.IsSelfDeafened and C_VoiceChat.IsSelfDeafened() or false
      
      RefreshDeafenIcon()
    end
  end)
  deafenBtn:SetScript("OnEnter", function()
    deafenTex:SetVertexColor(NS.CYAN[1], NS.CYAN[2], NS.CYAN[3], 1)
    GameTooltip:SetOwner(deafenBtn, "ANCHOR_LEFT")
    GameTooltip:SetText(isDeafened and "Undeafen" or "Deafen"); GameTooltip:Show()
  end)
  deafenBtn:SetScript("OnLeave", function()
    RefreshDeafenIcon(); GameTooltip:Hide()
  end)

  -- Position helper (defined after both buttons exist)
  local function PositionVoiceButtons()
    local pos2 = NS.DB("chatBarPosition") or "outside_right"
    local rightOffset = VB_PAD
    if pos2 == "inside_right" then rightOffset = rightOffset + 32 end
    deafenBtn:ClearAllPoints()
    deafenBtn:SetPoint("RIGHT", tabBarFrame, "RIGHT", -rightOffset, 0)
    muteBtn:ClearAllPoints()
    muteBtn:SetPoint("RIGHT", deafenBtn, "LEFT", -2, 0)
  end

  -- Position and hide initially
  PositionVoiceButtons()
  muteBtn:Hide(); deafenBtn:Hide()

  -- Expose for icon color refresh
  NS._voiceMuteTex = muteTex
  NS._voiceDeafenTex = deafenTex
  NS._voiceGetIconColor = GetVoiceIconColor

  -- Show mute/deafen only when in voice channel, reposition tabs when state changes
  -- Stored on NS so it can be cancelled on /reload or when chat is disabled
  if NS._chatVoiceSyncTicker then NS._chatVoiceSyncTicker:Cancel() end
  NS._chatVoiceSyncTicker = C_Timer.NewTicker(2, function()
    local wasVisible = voiceButtonsVisible
    if C_VoiceChat and C_VoiceChat.IsLoggedIn and C_VoiceChat.IsLoggedIn() then
      local inChannel = C_VoiceChat.GetActiveChannelID and C_VoiceChat.GetActiveChannelID()
      voiceButtonsVisible = (inChannel ~= nil)
      muteBtn:SetShown(voiceButtonsVisible)
      deafenBtn:SetShown(voiceButtonsVisible)
      if voiceButtonsVisible then
        PositionVoiceButtons()
        local m = C_VoiceChat.IsSelfMuted and C_VoiceChat.IsSelfMuted() or false
        local d2 = C_VoiceChat.IsSelfDeafened and C_VoiceChat.IsSelfDeafened() or false
        if m ~= isMuted then isMuted = m; RefreshMuteIcon() end
        if d2 ~= isDeafened then isDeafened = d2; RefreshDeafenIcon() end
      end
    else
      voiceButtonsVisible = false
      muteBtn:Hide(); deafenBtn:Hide()
    end
    -- Reposition tabs if voice state changed (to reserve/free space)
    if wasVisible ~= voiceButtonsVisible then
      C_Timer.After(0, RepositionButtons)
    end
  end)
end

-- ── EditBox setup ────────────────────────────────────────────────────

local function SetupEditBox(bg)
  local eb = ChatFrame1EditBox or ChatFrameEditBox
  if not eb then return end

  local ar, ag, ab = GetAccentColor()
  local ba = GetChatBgAlpha()

  local cont = CreateFrame("Frame", "LUIChatEditBoxContainer", UIParent, "BackdropTemplate")
  local ebPos = NS.DB("chatEditBoxPos") or "bottom"
  if ebPos == "top" then
    cont:SetPoint("TOPLEFT", bg, "TOPLEFT", 0, 0)
    cont:SetPoint("TOPRIGHT", bg, "TOPRIGHT", 0, 0)
  else
    cont:SetPoint("TOPLEFT", bg, "BOTTOMLEFT", 0, -1)
    cont:SetPoint("TOPRIGHT", bg, "BOTTOMRIGHT", 0, -1)
  end
  cont:SetHeight(26)
  cont:SetFrameStrata("HIGH")
  cont:SetFrameLevel(bg:GetFrameLevel() + 2)
  cont:SetBackdrop(NS.BACKDROP)
  cont:SetBackdropColor(0, 0, 0, ba)
  cont:SetBackdropBorderColor(ar, ag, ab, 0.5)
  cont:SetClampedToScreen(true)
  NS.chatEditContainer = cont

  eb:SetParent(UIParent)
  eb:ClearAllPoints()
  eb:SetPoint("TOPLEFT",     cont, "TOPLEFT",     4, -3)
  eb:SetPoint("BOTTOMRIGHT", cont, "BOTTOMRIGHT", -4,  3)
  eb:SetFrameStrata("HIGH")
  eb:SetFrameLevel(cont:GetFrameLevel() + 1)

  -- Hide native WoW chrome
  for _, suffix in ipairs({"Left","Right","Mid","FocusLeft","FocusRight","FocusMid"}) do
    local named = _G[(eb:GetName() or "ChatFrame1EditBox") .. suffix]
    if named then named:Hide(); named:SetScript("OnShow", named.Hide) end
  end
  for _, key in ipairs({"Left","Right","Mid","focusLeft","focusRight","focusMid"}) do
    if eb[key] and eb[key].Hide then eb[key]:Hide() end
  end
  if eb.SetBackdrop then eb:SetBackdrop(nil) end

  if not eb._ltBgCleared then
    eb._ltBgCleared = true
    local bgTex = eb:CreateTexture(nil, "BACKGROUND")
    bgTex:SetColorTexture(0, 0, 0, 0)
    bgTex:SetAllPoints()
  end

  local lastChatType, lastChatTarget = nil, nil

  -- Idle label: shows "Say:" etc. when editbox is visible but not focused
  local idleLabel = cont:CreateFontString(nil, "OVERLAY")
  idleLabel:SetFontObject(eb:GetFontObject() or ChatFontNormal or GameFontNormal)
  -- Match editbox text position: eb anchors at cont +4,-3 to -4,+3
  -- WoW's ChatFrame1EditBox has ~5px left text inset by default
  idleLabel:SetPoint("LEFT", cont, "LEFT", 9, -1)
  idleLabel:SetTextColor(1, 1, 1, 0.5)
  idleLabel:SetText("Say:")
  idleLabel:Hide()

  local function ShowIdle()
    if not NS.DB("chatEditBoxVisible") then return end
    -- Read current chat type from editbox attribute as fallback
    local ct = lastChatType
    if not ct or ct == "" then
      ct = eb:GetAttribute("chatType") or "SAY"
      lastChatType = ct
    end
    local target = lastChatTarget or ""
    local labels = {
      SAY="Say:", YELL="Yell:", PARTY="Party:", PARTY_LEADER="Party:",
      RAID="Raid:", RAID_LEADER="Raid:", RAID_WARNING="Raid Warning:",
      GUILD="Guild:", OFFICER="Officer:",
      INSTANCE_CHAT="Instance:", INSTANCE_CHAT_LEADER="Instance:",
      WHISPER="To "..target..":",
      BN_WHISPER="To "..target..":",
    }
    idleLabel:SetText(labels[ct] or "Say:")
    idleLabel:Show()
    eb:Hide()
    cont:SetAlpha(0.6)
  end

  -- Start hidden unless "Keep Edit Box Visible" is on
  if NS.DB("chatEditBoxVisible") then
    cont:Show()
    ShowIdle()
  else
    eb:Hide(); cont:Hide()
  end
  -- Track chat type while user has focus — ticker fires 4x/sec (C_Timer is lighter than OnUpdate)
  -- Stored on NS so reload or chat-disable can cancel it.
  if NS._chatFocusTicker then NS._chatFocusTicker:Cancel() end
  NS._chatFocusTicker = C_Timer.NewTicker(0.25, function()
    if eb:HasFocus() then
      local ct = eb:GetAttribute("chatType")
      if ct and ct ~= "" then
        lastChatType = ct
        lastChatTarget = eb:GetAttribute("tellTarget") or nil
      end
    end
  end)

  local function OnDeactivate(editBox)
    if editBox ~= eb then return end
    if NS.DB("chatEditBoxVisible") then
      cont:Show()
      ShowIdle()
    else
      editBox:Hide(); cont:Hide()
      idleLabel:Hide()
    end
  end
  local function OnActivate(editBox)
    if editBox ~= eb then return end
    idleLabel:Hide()
    editBox:Show(); cont:Show()
    cont:SetAlpha(1)
    -- Save before WoW resets to SAY
    local savedType = lastChatType
    local savedTarget = lastChatTarget
    -- Defer restore so it runs AFTER WoW's own ActivateChat finishes.
    -- COMBAT TAINT FIX: SetAttribute on the ChatFrame editbox taints it in combat,
    -- which prevents further typing. Skip the restore entirely during combat —
    -- WoW will default to SAY/last-used, which is fine.
    C_Timer.After(0, function()
      if not eb:HasFocus() then return end
      -- Never call SetAttribute during combat — it taints the editbox
      if InCombatLockdown() then return end
      -- Don't override if editbox is already in whisper mode (e.g. clicked player name)
      local currentType = eb:GetAttribute("chatType")
      if currentType == "WHISPER" or currentType == "BN_WHISPER" then return end
      if savedType and savedType ~= "" and savedType ~= "SAY" then
        eb:SetAttribute("chatType", savedType)
        if (savedType == "WHISPER" or savedType == "BN_WHISPER") and savedTarget then
          eb:SetAttribute("tellTarget", savedTarget)
        end
        ChatEdit_UpdateHeader(eb)
        lastChatType = savedType
        lastChatTarget = savedTarget
      end
    end)
  end

  if ChatFrameUtil and ChatFrameUtil.DeactivateChat then
    hooksecurefunc(ChatFrameUtil, "DeactivateChat", OnDeactivate)
    hooksecurefunc(ChatFrameUtil, "ActivateChat",   OnActivate)
  elseif ChatEdit_DeactivateChat then
    hooksecurefunc("ChatEdit_DeactivateChat", OnDeactivate)
    hooksecurefunc("ChatEdit_ActivateChat",   OnActivate)
  end
end

-- ── Copy Chat Window ─────────────────────────────────────────────────

local copyFrame = nil
NS.ChatShowCopyWindow = function()
  if copyFrame then copyFrame:Hide(); copyFrame = nil; return end

  local h = messageHistory[1] or {}
  local lines = {}
  local td = tabData[activeTab]
  local flt = td and td.eventSet
  local isSecret = issecretvalue

  for _, entry in ipairs(h) do
    if entry.msg then
      local show = true
      if flt and entry.event then
        show = flt[entry.event] or (EVENT_PAIRS[entry.event] and flt[EVENT_PAIRS[entry.event]]) or false
      end
      -- Respect channel blocked list
      if show and entry.channelName and td.channelBlocked and td.channelBlocked[entry.channelName] then
        show = false
      end
      -- Respect tab creation time
      if show and td.createdAt and entry.t and entry.t < td.createdAt then
        show = false
      end
      -- Skip loot events in non-loot tabs
      local isLootEvent = entry.event and (entry.event == "CHAT_MSG_LOOT"
        or (entry.event == "CHAT_MSG_MONEY" and lootRouting.showMoney)
        or (entry.event == "CHAT_MSG_CURRENCY" and lootRouting.showCurrency))
      if show and lootRouting.active and isLootEvent and not td._isLootTab then
        show = false
      end
      if show then
        -- Secret-safe path: if msg is a secret value (message received during
        -- combat restrictions), skip all string operations — display a marker
        -- instead. Lua gsub/match/concat on secrets error.
        if isSecret and isSecret(entry.msg) then
          local ts = entry.t and date("%H:%M:%S", entry.t) or ""
          lines[#lines+1] = (ts ~= "" and (ts .. " ") or "") .. "<protected message>"
        else
          local ok, clean = pcall(function()
            local c = entry.msg
              :gsub("|H.-|h(.-)|h", "%1")  -- strip hyperlinks, keep text
              :gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|K.-|k", ""):gsub("|n", "\n")  -- strip textures/atlas
            -- Strip timestamp prefix (already adding our own)
            c = c
              :gsub("^|cff%x%x%x%x%x%x%d?%d?:?%d%d:?%d?%d?[APMapm ]*|r ", "")
              :gsub("^%d?%d?:?%d%d:?%d?%d?[APMapm ]* ", "")
            return c
          end)
          if ok and clean then
            local ts = entry.t and date("%H:%M:%S", entry.t) or ""
            local colorHex = string.format("%02x%02x%02x", (entry.r or 1) * 255, (entry.g or 1) * 255, (entry.b or 1) * 255)
            lines[#lines+1] = "|cff" .. colorHex .. ((ts ~= "" and (ts .. " ") or "") .. clean) .. "|r"
          end
        end
      end
    end
  end
  if #lines == 0 then lines[1] = "(No messages)" end
  local text = table.concat(lines, "\n")

  local ar, ag, ab = GetAccentColor()
  local BD = NS.BACKDROP

  local frame = CreateFrame("Frame", "LTChatCopyFrame", UIParent, "BackdropTemplate")
  frame:SetSize(1000, 400)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("FULLSCREEN_DIALOG")
  frame:SetMovable(true); frame:SetResizable(true)
  frame:SetResizeBounds(300, 200, 1800, 800)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function() frame:StartMoving() end)
  frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
  frame:EnableMouse(true)
  frame:SetBackdrop(BD)
  frame:SetBackdropColor(0.025, 0.025, 0.038, 0.97)
  frame:SetBackdropBorderColor(ar, ag, ab, 0.38)

  -- Accent line
  local accentLine = frame:CreateTexture(nil, "OVERLAY", nil, 5)
  accentLine:SetPoint("TOPLEFT", 1, -1); accentLine:SetPoint("TOPRIGHT", -1, -1)
  accentLine:SetHeight(1); accentLine:SetColorTexture(ar, ag, ab, 1)

  -- Header background
  local headerBg = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
  headerBg:SetPoint("TOPLEFT", 1, -1); headerBg:SetPoint("TOPRIGHT", -1, -1)
  headerBg:SetHeight(28); headerBg:SetColorTexture(0.010, 0.010, 0.020, 1)

  -- Title
  local title = frame:CreateFontString(nil, "OVERLAY")
  title:SetFont(NS.FONT, 11, "")
  title:SetPoint("LEFT", headerBg, "LEFT", 10, 0)
  title:SetTextColor(ar, ag, ab)
  title:SetText(L["Copy Chat"])

  -- Close button (settings style)
  local closeBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
  closeBtn:SetSize(20, 20); closeBtn:SetPoint("TOPRIGHT", -4, -4)
  closeBtn:SetBackdrop(BD); closeBtn:SetBackdropColor(0.09, 0.02, 0.02, 1)
  closeBtn:SetBackdropBorderColor(0.34, 0.09, 0.09, 1)
  local cX = closeBtn:CreateFontString(nil, "OVERLAY")
  cX:SetFont(NS.FONT, 10, ""); cX:SetPoint("CENTER"); cX:SetTextColor(0.60, 0.18, 0.18); cX:SetText("X")
  closeBtn:SetScript("OnClick", function() frame:Hide(); copyFrame = nil end)
  closeBtn:SetScript("OnEnter", function() closeBtn:SetBackdropBorderColor(0.60, 0.12, 0.12, 1); cX:SetTextColor(1, 0.3, 0.3) end)
  closeBtn:SetScript("OnLeave", function() closeBtn:SetBackdropBorderColor(0.34, 0.09, 0.09, 1); cX:SetTextColor(0.60, 0.18, 0.18) end)

  -- Header line
  local hLine = frame:CreateTexture(nil, "OVERLAY", nil, 4)
  hLine:SetPoint("TOPLEFT", 1, -28); hLine:SetPoint("TOPRIGHT", -1, -28)
  hLine:SetHeight(1); hLine:SetColorTexture(ar, ag, ab, 0.3)

  -- Scroll frame
  local sf = CreateFrame("ScrollFrame", "LTChatCopyScroll", frame, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 10, -34); sf:SetPoint("BOTTOMRIGHT", -30, 24)

  local editBox = CreateFrame("EditBox", "LTChatCopyEB", frame)
  editBox:SetMultiLine(true); editBox:SetAutoFocus(true)
  editBox:SetFontObject(GameFontHighlight); editBox:SetWidth(460)
  editBox:SetScript("OnEscapePressed", function() frame:Hide(); copyFrame = nil end)
  sf:SetScrollChild(editBox)

  -- Resize handle
  local resizeBtn = CreateFrame("Button", nil, frame)
  resizeBtn:SetSize(16, 16); resizeBtn:SetPoint("BOTTOMRIGHT", -2, 2)
  resizeBtn:SetNormalTexture("Interface/AddOns/LucidUI/Assets/resize.png")
  resizeBtn:GetNormalTexture():SetVertexColor(0.4, 0.4, 0.5)
  resizeBtn:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
  resizeBtn:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing(); editBox:SetWidth(sf:GetWidth())
  end)
  resizeBtn:SetScript("OnEnter", function() resizeBtn:GetNormalTexture():SetVertexColor(ar, ag, ab) end)
  resizeBtn:SetScript("OnLeave", function() resizeBtn:GetNormalTexture():SetVertexColor(0.4, 0.4, 0.5) end)

  -- Bottom line
  local bLine = frame:CreateTexture(nil, "OVERLAY", nil, 4)
  bLine:SetPoint("BOTTOMLEFT", 1, 22); bLine:SetPoint("BOTTOMRIGHT", -1, 22)
  bLine:SetHeight(1); bLine:SetColorTexture(ar, ag, ab, 0.15)

  C_Timer.After(0, function()
    if not frame:IsShown() then return end
    editBox:SetWidth(sf:GetWidth())
    editBox:SetText(text)
    -- Avoid #text (may fail on secret-tainted strings). Use -1 which
    -- positions the cursor at the end without needing a length check.
    pcall(editBox.SetCursorPosition, editBox, -1)
    C_Timer.After(0, function()
      if not frame:IsShown() then return end
      local maxScroll = sf:GetVerticalScrollRange()
      if maxScroll and maxScroll > 0 then sf:SetVerticalScroll(maxScroll) end
      pcall(editBox.HighlightText, editBox)
    end)
  end)

  copyFrame = frame
end

-- ── Create main display ──────────────────────────────────────────────

local function CreateMainDisplay()
  if customDisplays[1] then return customDisplays[1] end
  local ref = ChatFrame1
  if not ref then return nil end

  local left   = ref:GetLeft()   or 0
  local bottom = ref:GetBottom() or 135
  local fw     = ref:GetWidth()  or 480
  local fh     = ref:GetHeight() or 270
  if fw < 10 then fw = 480 end
  if fh < 10 then fh = 270 end

  local ar, ag, ab = GetAccentColor()
  local ba = GetChatBgAlpha()

  local savedPos  = NS.DB("chatWinPos")
  local savedSize = NS.DB("chatWinSize")
  if savedPos  then left = savedPos.x;  bottom = savedPos.y end
  if savedSize then fw   = savedSize.w; fh     = savedSize.h end

  local bg = CreateFrame("Frame", "LUIChatDisplayBG", UIParent, "BackdropTemplate")
  bg:SetFrameStrata("MEDIUM")
  bg:SetFrameLevel(9)
  bg:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
  bg:SetSize(fw, fh)
  bg:SetMovable(true); bg:SetResizable(true)
  bg:SetClampedToScreen(true)
  bg:SetResizeBounds(200, 100)
  bg:SetBackdrop({
    bgFile = NS.TEX_WHITE,
    insets = {left=0, right=0, top=TAB_H, bottom=0},
  })
  bg:SetBackdropColor(0, 0, 0, ba)
  NS.chatBg = bg

  -- bg is the root parent of all chat display frames.
  -- SetHyperlinksEnabled lets it receive hyperlink clicks propagated from children.
  -- Clicks on |Haddon:lucidurl:| links fire SetItemRef → caught in ChatFormat.lua.
  bg:SetHyperlinksEnabled(true)
  bg:SetScript("OnHyperlinkClick", function(self, link, text, btn)
    local lt = link and link:match("^([^:]+)")
    if lt == "addon" then
      -- Handled by EventRegistry:RegisterCallback("SetItemRef") in ChatFormat.lua
      SetItemRef(link, text, btn, self)
    else
      SetItemRef(link, text, btn, self)
    end
  end)

  BuildTabBar(bg)

  -- Resize handle
  local resizeBtn = CreateFrame("Button", nil, bg)
  resizeBtn:SetSize(28, 28)
  resizeBtn:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", 0, 0)
  resizeBtn:SetFrameLevel(bg:GetFrameLevel() + 15)
  resizeBtn:EnableMouse(true); resizeBtn:RegisterForDrag("LeftButton")
  local resizeTex = resizeBtn:CreateTexture(nil, "OVERLAY")
  resizeTex:SetAllPoints()
  resizeTex:SetTexture("Interface/AddOns/LucidUI/Assets/resize.png")
  resizeTex:SetTexCoord(0, 0, 0, 1, 1, 0, 1, 1)
  resizeTex:SetVertexColor(1, 1, 1, 0.8)
  resizeBtn:SetScript("OnEnter", function() resizeTex:SetVertexColor(ar, ag, ab, 1) end)
  resizeBtn:SetScript("OnLeave", function() resizeTex:SetVertexColor(1, 1, 1, 0.8) end)
  resizeBtn:SetScript("OnDragStart", function()
    if NS.DB("chatLocked") then return end
    bg:StartSizing("BOTTOMRIGHT")
  end)
  resizeBtn:SetScript("OnDragStop", function()
    bg:StopMovingOrSizing()
    local x, y = bg:GetLeft(), bg:GetBottom()
    local w, h = bg:GetWidth(), bg:GetHeight()
    if x and y then
      bg:ClearAllPoints()
      bg:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
    end
    NS.DBSet("chatWinSize", {w=w, h=h})
    if x and y then NS.DBSet("chatWinPos", {x=x, y=y}) end
    RebuildTabButtons()
  end)

  -- Message area
  local d = NS.CreateChatMessageArea(bg, "LUIChatDisplay")

  -- Apply layout based on bar position (inside bars need inset)
  local function ApplyBarLayout()
    local barW = NS.chatBarRef and NS.chatBarRef:GetWidth() or 32
    local pos2 = NS.DB("chatBarPosition") or "outside_right"
    local vis = NS.DB("chatBarVisibility") or "always"
    local lInset = (pos2 == "inside_left") and barW or 0
    local rInset = (pos2 == "inside_right") and barW or 0
    d:ClearAllPoints()
    d:SetPoint("TOPLEFT", bg, "TOPLEFT", lInset + 2, -(TAB_H + 2))
    d:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -(rInset + 2), 2)
    resizeBtn:ClearAllPoints()
    resizeBtn:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -rInset, 0)
    -- Stretch accent line to cover icon bar area when outside
    if bg._chatAccentLine then
      bg._chatAccentLine:ClearAllPoints()
      bg._chatAccentLine:SetPoint("BOTTOMLEFT", tabBarFrame, "BOTTOMLEFT", 0, 0)
      if pos2 == "outside_right" and vis == "always" then
        bg._chatAccentLine:SetPoint("BOTTOMRIGHT", tabBarFrame, "BOTTOMRIGHT", barW, 0)
      elseif pos2 == "outside_left" and vis == "always" then
        bg._chatAccentLine:SetPoint("BOTTOMLEFT", tabBarFrame, "BOTTOMLEFT", -barW, 0)
        bg._chatAccentLine:SetPoint("BOTTOMRIGHT", tabBarFrame, "BOTTOMRIGHT", 0, 0)
      else
        bg._chatAccentLine:SetPoint("BOTTOMRIGHT", tabBarFrame, "BOTTOMRIGHT", 0, 0)
      end
    end
  end
  NS.ApplyBarLayout = ApplyBarLayout
  ApplyBarLayout()

  -- Hide resize when locked
  resizeBtn:SetShown(not NS.DB("chatLocked"))
  NS.chatResizeBtn = resizeBtn

  -- Chat accent line (top of message area, below tab bar)
  local chatAccLine = tabBarFrame:CreateTexture(nil, "OVERLAY")
  chatAccLine:SetHeight(1)
  -- Initial position, will be updated by ApplyBarLayout
  chatAccLine:SetPoint("BOTTOMLEFT", tabBarFrame, "BOTTOMLEFT", 0, 0)
  chatAccLine:SetPoint("BOTTOMRIGHT", tabBarFrame, "BOTTOMRIGHT", 0, 0)
  local acR, acG, acB = GetAccentColor()
  chatAccLine:SetColorTexture(acR, acG, acB, 0.6)
  chatAccLine:SetShown(NS.DB("chatAccentLine") ~= false)
  bg._chatAccentLine = chatAccLine
  -- Re-apply layout now that accent line exists
  ApplyBarLayout()

  d:SetFrameLevel(bg:GetFrameLevel() + 1)
  d:SetMaxLines(MAX_HISTORY)
  d:SetSpacing(NS.DB("chatMessageSpacing") or 0)
  ApplyFontToDisplay(d)
  ApplyFadeToDisplay(d)
  d:EnableMouseWheel(true)
  d:SetScript("OnMouseWheel", function(self, delta)
    if delta > 0 then self:ScrollUp() else self:ScrollDown() end
  end)
  d:Show()
  customDisplays[1] = d
  NS.chatDisplay = d  -- expose for timestamp recompute



  -- Hide the XML HyperlinkHandler so it doesn't block clicks on contentFS hyperlinks
  C_Timer.After(0.5, function()
    local hf = _G["LucidUIHyperlinkFrame"]
    if hf then hf:Hide(); hf:EnableMouse(false) end
  end)

  C_Timer.After(0, function() SetupEditBox(bg) end)

  return d
end

-- ── Whisper sound ────────────────────────────────────────────────────

local function PlayWhisperSound()
  PlaySoundFile("Interface/AddOns/LucidUI/Assets/Whisper.ogg", "Master")
end

-- ── Initialize chat system ───────────────────────────────────────────

-- ── Minimap Button ────────────────────────────────────────────────────

local minimapBtn = nil
local function CreateMinimapButton()
  if minimapBtn then return end

  local btn = CreateFrame("Button", "LUIChatMinimapButton", Minimap)
  btn:SetSize(20, 20)
  btn:SetFrameStrata("MEDIUM")
  btn:SetFrameLevel(8)
  btn:SetMovable(true)
  btn:RegisterForDrag("LeftButton")
  btn:SetClampedToScreen(true)

  local icon = btn:CreateTexture(nil, "ARTWORK")
  icon:SetTexture("Interface/AddOns/LucidUI/Assets/minimap_20x20.png")
  icon:SetAllPoints()

  -- Position around minimap edge
  local angle = NS.DB("minimapBtnAngle") or 220
  local function UpdatePosition()
    local rad = math.rad(angle)
    local x = math.cos(rad) * 80
    local y = math.sin(rad) * 80
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
  end
  UpdatePosition()

  -- Drag around minimap
  btn:SetScript("OnDragStart", function(self)
    self:StartMoving()
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale = UIParent:GetEffectiveScale()
      cx, cy = cx / scale, cy / scale
      angle = math.deg(math.atan2(cy - my, cx - mx))
      UpdatePosition()
    end)
  end)
  btn:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    self:SetScript("OnUpdate", nil)
    UpdatePosition()
    NS.DBSet("minimapBtnAngle", angle)
  end)

  btn:SetScript("OnClick", function(_, mouseButton)
    if mouseButton == "LeftButton" then
      if NS.BuildChatOptionsWindow then NS.BuildChatOptionsWindow() end
    elseif mouseButton == "RightButton" then
      if NS.BuildChatOptionsWindow then NS.BuildChatOptionsWindow() end
    end
  end)
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  btn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
    GameTooltip:SetText("LucidUI")
    GameTooltip:AddLine(L["Left-click: Settings"], 0.7, 0.7, 0.7)
    GameTooltip:AddLine(L["Right-click: Settings"], 0.7, 0.7, 0.7)
    GameTooltip:AddLine(L["Drag: Move button"], 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

  minimapBtn = btn
  NS.minimapBtn = btn
end

local function UpdateMinimapButton()
  if NS.DB("chatShowMinimap") then
    CreateMinimapButton()
    if minimapBtn then minimapBtn:Show() end
  else
    if minimapBtn then minimapBtn:Hide() end
  end
end

local function InitChatSystem()
  CreateMainDisplay()
  displayReady = true

  -- Restore managed Loot tab BEFORE any messages are processed
  if NS.DB("lootInChatTab") then
    local exists = false
    for _, td in ipairs(tabData) do
      if td._isLootTab then exists = true; break end
    end
    if not exists then
      table.insert(tabData, {
        name = "Loot", colorHex = "00cc66",
        eventSet = {},  -- empty: fed exclusively by NS.AddMessage
        channelBlocked = {General=true, Trade=true, LocalDefense=true, Services=true, LookingForGroup=true},
        _isLootTab = true,
      })
      RebuildTabButtons()
    end
  end

  -- Restore managed Combat Log tab
  if NS.DB("chatCombatLog") then
    NS.EnsureCombatLogTab()
  end

  -- Sync loot event filters BEFORE any messages are flushed
  NS.SyncLootEvents()

  -- Load LucidUI history into Loot chat tab
  if NS.DB("lootInChatTab") and NS.chatDisplay then
    local hist = LucidUIDB and LucidUIDB.history
    if hist and #hist > 0 then
      -- Find loot tab index
      local lootTabIdx = nil
      for ti, td2 in ipairs(tabData) do
        if td2._isLootTab then lootTabIdx = ti; break end
      end
      if lootTabIdx then
        -- History is stored newest-first, load oldest-first
        for i = #hist, 1, -1 do
          local e = hist[i]
          if e then
            local ts = NS.ChatFormatTimestamp and NS.ChatFormatTimestamp(e.ts) or nil
            local msg2 = e.msg or ""
            if lootTabIdx == activeTab then
              customDisplays[1]:AddMessage(msg2, e.r or 1, e.g or 1, e.b or 1, ts, e.ts)
            else
              if not tabMsgs[lootTabIdx] then tabMsgs[lootTabIdx] = {} end
              local tm = tabMsgs[lootTabIdx]
              tm[#tm+1] = {t=msg2, r=e.r or 1, g=e.g or 1, b=e.b or 1, prefix=ts, ts=e.ts}
            end
          end
        end
      end
    end
  end

  -- Restore persisted chat history if enabled
  if NS.DB("chatStoreMessages") then
    local saved = NS.DB("chatHistory")
    if saved and type(saved) == "table" and #saved > 0 then
      restoringHistory = true
      for _, entry in ipairs(saved) do
        AddToDisplay(1, entry.msg, entry.r, entry.g, entry.b, entry.event, entry.channelName, entry.t)
      end
      restoringHistory = false
    end
  end

  -- Flush early buffer
  if earlyBuffer then
    for _, entry in ipairs(earlyBuffer) do
      AddToDisplay(1, entry.msg, entry.r, entry.g, entry.b, entry.event, entry.channelName, entry.t)
    end
  end
  earlyBuffer = nil

  -- Build bar
  if NS.BuildChatBar then NS.BuildChatBar() end
  -- Re-apply layout now that bar width is known
  if NS.ApplyBarLayout then NS.ApplyBarLayout() end
  if NS.UpdateTabBarBgStretch then NS.UpdateTabBarBgStretch() end
  UpdateMinimapButton()

  -- Hide default WoW chat UI (graceful no-ops if removed in Midnight)
  if GeneralDockManager then
    pcall(function()
      GeneralDockManager:UnregisterAllEvents()
      GeneralDockManager:Hide()
      GeneralDockManager:SetScript("OnSizeChanged", nil)
      GeneralDockManager:SetScript("OnUpdate", nil)
      GeneralDockManager:SetScript("OnShow", function(self) self:Hide() end)
    end)
  end

  for _, name in ipairs({
    "ChatFrameMenuButton","ChatFrameChannelButton",
    "FriendsMicroButton","ChatFrameToggleVoiceMuteButton",
    "ChatFrameToggleVoiceDeafenButton","QuickJoinToastButton",
    "VoiceChatTalking",
  }) do
    local f = _G[name]
    if f then f:Hide(); f:SetScript("OnShow", function(self) self:Hide() end) end
  end

  -- Reparent WoW chat frames to hidden frame
  local waitFrame = CreateFrame("Frame")
  waitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
  waitFrame:SetScript("OnEvent", function(self, event)
    if event ~= "PLAYER_ENTERING_WORLD" then return end
    self:UnregisterAllEvents()
    C_Timer.After(0, function()
      -- Note: FCF_ResetChatWindows removed to avoid taint (GetMOTD protected)

      local frames = CHAT_FRAMES or {}
      for _, tabName in pairs(frames) do
        local tab = _G[tabName]
        if tab then
          if tab:GetParent() == UIParent then tab:SetParent(hiddenFrame) end
          local tabButton = _G[tabName .. "Tab"]
          if tabButton then
            tabButton:SetParent(hiddenFrame)
            local origSP = tabButton.SetParent
            hooksecurefunc(tabButton, "SetParent", function(self2) origSP(self2, hiddenFrame) end)
          end
        end
      end

      if FloatingChatFrameManager then pcall(function() FloatingChatFrameManager:UnregisterAllEvents() end) end

      for i = 3, NUM_CHAT_WINDOWS or 10 do
        local cf = _G["ChatFrame" .. i]
        if cf then cf:SetParent(hiddenFrame) end
        local cfTab = _G["ChatFrame" .. i .. "Tab"]
        if cfTab then cfTab:SetParent(hiddenFrame) end
      end
    end)
  end)

  -- Whisper sound + auto whisper tab
  local whisperFrame = CreateFrame("Frame")
  whisperFrame:RegisterEvent("CHAT_MSG_WHISPER")
  whisperFrame:RegisterEvent("CHAT_MSG_BN_WHISPER")
  whisperFrame:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
  whisperFrame:RegisterEvent("CHAT_MSG_BN_WHISPER_INFORM")
  whisperFrame:SetScript("OnEvent", function(_, event, msg, sender, ...)
    -- Only play sound on incoming whispers
    if event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_BN_WHISPER" then
      PlayWhisperSound()
    end
    -- Auto-create whisper tab if enabled
    if NS.DB("chatWhisperTab") and tabBarFrame then
      -- For outgoing whispers, use the target name instead of sender
      local tabName
      if event == "CHAT_MSG_WHISPER_INFORM" or event == "CHAT_MSG_BN_WHISPER_INFORM" then
        -- For INFORM events, the "sender" arg is actually the recipient
        tabName = sender and (sender:match("^([^%-]+)") or sender) or "Whisper"
      else
        tabName = sender and (sender:match("^([^%-]+)") or sender) or "Whisper"
      end
      local senderShort = tabName
      local whisperEventSet = {
        CHAT_MSG_WHISPER=true, CHAT_MSG_WHISPER_INFORM=true,
        CHAT_MSG_BN_WHISPER=true, CHAT_MSG_BN_WHISPER_INFORM=true,
      }
      local whisperTabIdx
      for i, td in ipairs(tabData) do
        if td.name == senderShort and td._isWhisperTab then
          whisperTabIdx = i; break
        end
      end
      if not whisperTabIdx then
        local now = time()
        table.insert(tabData, {
          name = senderShort, colorHex = "ff80ff",
          eventSet = whisperEventSet, _isWhisperTab = true,
          createdAt = now - 1,  -- 1s ago so current message passes the filter
        })
        whisperTabIdx = #tabData
        RebuildTabButtons()
        SaveTabData()
        -- Inject only the last matching whisper message (the one that triggered this tab)
        tabMsgs[whisperTabIdx] = {}
        local h = messageHistory[1]
        if h then
          for idx = #h, math.max(1, #h - 30), -1 do
            local entry = h[idx]
            if entry and entry.event and whisperEventSet[entry.event] then
              if not entry._clean then
                entry._clean = (entry.msg or "")
                  :gsub("^|cff%x%x%x%x%x%x%d?%d?:?%d%d:?%d?%d?[APMapm ]*|r ", "")
                  :gsub("^%d?%d?:?%d%d:?%d?%d?[APMapm ]* ", "")
                  :gsub("^|cff%x%x%x%x%x%x|||r ", "")
                entry._ts = NS.ChatFormatTimestamp and NS.ChatFormatTimestamp(entry.t) or nil
              end
              tabMsgs[whisperTabIdx][1] = {t=entry._clean, r=entry.r or 1, g=entry.g or 1, b=entry.b or 1, prefix=entry._ts, ts=entry.t}
              break
            end
          end
        end
      end
      if whisperTabIdx ~= activeTab then
        if tabData[whisperTabIdx] then tabData[whisperTabIdx]._unread = true; SaveTabData() end
        StartTabFlash(whisperTabIdx)
      else
        -- Active tab, mark as read
        if tabData[whisperTabIdx] then tabData[whisperTabIdx]._unread = nil end
      end
    end
  end)

  -- Store messages: save history to DB on logout
  local saveFrame = CreateFrame("Frame")
  saveFrame:RegisterEvent("PLAYER_LOGOUT")
  saveFrame:SetScript("OnEvent", function()
    if NS.DB("chatStoreMessages") then
      local h = messageHistory[1] or {}
      local toSave = {}
      local max = NS.DB("chatRemoveOldMessages") ~= false and MAX_HISTORY or #h
      for i = math.max(1, #h - max + 1), #h do
        local entry = h[i]
        if entry then
          toSave[#toSave+1] = {
            msg = entry.msg, r = entry.r, g = entry.g, b = entry.b,
            t = entry.t, event = entry.event, channelName = entry.channelName,
          }
        end
      end
      NS.DBSet("chatHistory", toSave)
    else
      NS.DBSet("chatHistory", nil)
    end
  end)
end

-- ── Register initialization ──────────────────────────────────────────

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(_, ev)
  if ev == "PLAYER_LOGIN" then
    initFrame:UnregisterEvent("PLAYER_LOGIN")
    -- Minimap button always loads (even with chat disabled, for settings access)
    UpdateMinimapButton()
    if NS.DB("chatEnabled") ~= false then
      InitChatSystem()
    end
  end
end)

-- Expose for other modules
NS.chatActiveTab    = function() return activeTab end
NS.chatTabData      = function() return tabData end
NS.FILTER_CATS      = FILTER_CATS
NS.chatRedraw       = function(quick)
  isRerendering = true; RedrawDisplay(quick); isRerendering = false
end
NS.chatRefreshTabs  = function()
  RefreshButtonVisuals()
end
NS.chatRebuildTabs  = function()
  RebuildTabButtons()
end
NS.chatTabMsgs = tabMsgs
NS.UpdateMinimapButton = UpdateMinimapButton

-- ── Combat Log Tab ───────────────────────────────────────────────────
-- Embeds WoW's native ChatFrame2 (Combat Log) into our tab system

NS.EnsureCombatLogTab = function()
  -- Check if tab already exists
  for _, td in ipairs(tabData) do
    if td._isCombatLogTab then return end
  end
  -- Insert at position 2 (after General)
  table.insert(tabData, 2, {
    name = "Combat Log",
    colorHex = "cc3333",
    eventSet = {},
    _isCombatLogTab = true,
  })
  -- Shift active tab if needed
  if activeTab >= 2 then activeTab = activeTab + 1 end
  RebuildTabButtons()
  SaveTabData()
end

NS.RemoveCombatLogTab = function()
  for i = #tabData, 1, -1 do
    if tabData[i]._isCombatLogTab then
      -- Restore ChatFrame2 to hidden
      local cf2 = _G["ChatFrame2"]
      if cf2 and NS.chatBg and cf2:GetParent() == NS.chatBg then
        cf2:SetParent(hiddenFrame); cf2:Hide()
        local qbf = _G["CombatLogQuickButtonFrame_Custom"]
        if qbf then qbf:SetParent(hiddenFrame); qbf:Hide() end
      end
      table.remove(tabData, i)
      tabMsgs[i] = nil
      -- Shift tabMsgs
      for idx = i, #tabData do tabMsgs[idx] = tabMsgs[idx+1] end
      tabMsgs[#tabData+1] = nil
      if activeTab >= i then activeTab = math.max(1, activeTab - 1) end
      RebuildTabButtons()
      isRerendering = true; RedrawDisplay(); isRerendering = false
      SaveTabData()
      return
    end
  end
end

NS.ApplyChatTransparency = function()
  local ba = GetChatBgAlpha()
  local tba = GetTabBarBgAlpha()
  -- Chat background
  if NS.chatBg then NS.chatBg:SetBackdropColor(0, 0, 0, ba) end
  -- Tab bar background
  if NS.chatTabBarBg then NS.chatTabBarBg:SetColorTexture(0, 0, 0, tba) end
  -- EditBox container
  if NS.chatEditContainer then NS.chatEditContainer:SetBackdropColor(0, 0, 0, ba) end
  -- Icon bar
  if NS.chatBarRef and NS.chatBarRef.SetBackdropColor then NS.chatBarRef:SetBackdropColor(0, 0, 0, ba) end
  -- EditBox accent border
  if NS.chatEditContainer then
    if NS.DB("chatEditBoxAccentBorder") then
      local ar, ag, ab = NS.CYAN[1], NS.CYAN[2], NS.CYAN[3]
      NS.chatEditContainer:SetBackdropBorderColor(ar, ag, ab, 0.5)
    else
      NS.chatEditContainer:SetBackdropBorderColor(0.15, 0.15, 0.15, 1)
    end
  end
  -- Chat accent line color
  if NS.chatBg and NS.chatBg._chatAccentLine then
    local ar, ag, ab = NS.CYAN[1], NS.CYAN[2], NS.CYAN[3]
    NS.chatBg._chatAccentLine:SetColorTexture(ar, ag, ab, 0.6)
  end
end