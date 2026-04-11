-- LucidUI ChatFormat.lua
-- Timestamp formatting, class colors, channel shortening, URL detection.

local NS = LucidUINS
local L  = LucidUIL

-- ── Timestamp ─────────────────────────────────────────────────────────

NS.ChatFormatTimestamp = function(unixTime)
  if NS.DB("chatTimestamps") == false then return nil end
  local fmt = NS.DB("chatTimestampFormat") or "%H:%M"
  local ts  = date(fmt, unixTime)
  local tsc = NS.DB("chatTimestampColor")
  local hex = "737373"
  if tsc and type(tsc) == "table" and tsc.r then
    hex = string.format("%02x%02x%02x", math.floor(tsc.r*255), math.floor(tsc.g*255), math.floor(tsc.b*255))
  end
  local result = "|cff" .. hex .. ts .. "|r "
  if NS.DB("chatShowSeparator") ~= false then
    -- NS.CYAN is always kept in sync with the active accent color
    local C = NS.CYAN
    result = result .. "|cff" .. string.format("%02x%02x%02x", C[1]*255, C[2]*255, C[3]*255) .. "|||r "
  end
  return result
end

-- ── Class Colors ──────────────────────────────────────────────────────
-- During M+/raid boss combat, chat event args arrive as "secret values":
-- a Blizzard wrapper that errors on any Lua comparison, boolean test,
-- concatenation, string method, or table index. All existence checks here
-- use `type(v) == "string"` and the critical GUID→class→color path is
-- wrapped in pcall, matching Chattynator's approach.

local function isSecret(v) return issecretvalue and issecretvalue(v) end

local CLASS_HEX = {
  DEATHKNIGHT = "C41F3B", DEMONHUNTER = "A330C9", DRUID   = "FF7D0A",
  EVOKER      = "33937F", HUNTER      = "ABD473", MAGE    = "3FC7EB",
  MONK        = "00FF96", PALADIN     = "F58CBA", PRIEST  = "FFFFFF",
  ROGUE       = "FFF569", SHAMAN      = "0070DE", WARLOCK = "8788EE",
  WARRIOR     = "C79C6E",
}

-- Wraps name with a |cffRRGGBB...|r color code. Used by the cache path for
-- non-secret class tokens. Returns name unchanged if class is secret or
-- unknown — the GUID path via C_ClassColor handles secret tokens instead.
local function ApplyClassColor(englishClass, name)
  if type(englishClass) ~= "string" or type(name) ~= "string" then return name end
  if isSecret(englishClass) then return name end
  local hex = CLASS_HEX[englishClass]
  if type(hex) ~= "string" then return name end
  if isSecret(name) then
    return string.format("|cff%s%s|r", hex, name)
  end
  return "|cff" .. hex .. name .. "|r"
end

-- Two-tier name → class cache.
-- selfCache wins over classCache to avoid short-name collisions with another
-- group member who happens to share the player's base name.
local classCache = {}
local selfCache = {}
local function _validClass(c)
  if type(c) ~= "string" then return false end
  if isSecret(c) then return false end
  return CLASS_HEX[c] ~= nil
end
local function cacheInsert(name, class, isSelf)
  if type(name) ~= "string" or isSecret(name) then return end
  if not _validClass(class) then return end
  local lname = name:lower()
  if isSelf then
    selfCache[lname] = class
    local short = name:match("^([^%-]+)")
    if type(short) == "string" and short ~= name then
      selfCache[short:lower()] = class
    end
  else
    if classCache[lname] == nil then classCache[lname] = class end
    local short = name:match("^([^%-]+)")
    if type(short) == "string" and short ~= name then
      local lshort = short:lower()
      if classCache[lshort] == nil then classCache[lshort] = class end
    end
  end
end
local function cacheLookup(name)
  if type(name) ~= "string" or isSecret(name) then return nil end
  local lname = name:lower()
  local c = selfCache[lname] or classCache[lname]
  if c then return c end
  local short = name:match("^([^%-]+)")
  if type(short) == "string" and short ~= name then
    local lshort = short:lower()
    return selfCache[lshort] or classCache[lshort]
  end
  return nil
end

local function RefreshRosterCache()
  local function tryAddUnit(unit, isSelf)
    if not UnitExists(unit) then return end
    local ok, _, englishClass = pcall(UnitClass, unit)
    if not (ok and _validClass(englishClass)) then return end
    local ok2, uName, uRealm = pcall(UnitName, unit)
    if not (ok2 and uName) or isSecret(uName) then return end
    cacheInsert(uName, englishClass, isSelf)
    if uRealm and uRealm ~= "" and not isSecret(uRealm) then
      cacheInsert(uName .. "-" .. uRealm, englishClass, isSelf)
    end
  end
  tryAddUnit("player", true)

  local ok, _, englishClass = pcall(UnitClass, "player")
  if ok and _validClass(englishClass) then
    local okf, name, realm = pcall(UnitFullName, "player")
    if okf and name and not isSecret(name) then
      cacheInsert(name, englishClass, true)
      if realm and realm ~= "" and not isSecret(realm) then
        cacheInsert(name .. "-" .. realm, englishClass, true)
      elseif NS and NS.characterFullName then
        cacheInsert(NS.characterFullName, englishClass, true)
      end
    end
  end

  if IsInRaid() then
    for i = 1, (GetNumGroupMembers() or 0) do tryAddUnit("raid" .. i, false) end
  elseif IsInGroup() then
    for i = 1, 4 do tryAddUnit("party" .. i, false) end
  end
end

local _cacheFrame = CreateFrame("Frame")
_cacheFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
_cacheFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
_cacheFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
_cacheFrame:RegisterEvent("CHALLENGE_MODE_START")
_cacheFrame:SetScript("OnEvent", function(_, ev)
  if ev == "CHALLENGE_MODE_START" then
    -- Final refresh just before M+ restrictions kick in.
    C_Timer.After(0, RefreshRosterCache)
  else
    RefreshRosterCache()
  end
end)

NS.ChatGetColoredSender = function(guid, name)
  if NS.DB("chatClassColors") == false then return name end
  if type(name) ~= "string" then return name end

  -- 1) Name cache — populated from roster events out of combat.
  local cachedClass = cacheLookup(name)
  if cachedClass then
    return ApplyClassColor(cachedClass, name)
  end

  -- 2) GUID path via C_ClassColor. Chattynator-style: pass the (possibly
  --    secret) class token through C_ClassColor.GetClassColor which accepts
  --    secrets at C++ level, then :WrapTextInColorCode to produce the final
  --    |cff..|r wrapped name. pcall catches any secret-value boolean errors
  --    from the GetPlayerInfoByGUID return.
  local guidType = type(guid)
  if guidType == "string" or guidType == "userdata" then
    local okWrap, wrapped = pcall(function()
      if not GetPlayerInfoByGUID then return nil end
      local _, englishClass = GetPlayerInfoByGUID(guid)
      if not englishClass then return nil end
      local ccFunc = C_ClassColor and C_ClassColor.GetClassColor
      if not ccFunc then return nil end
      local classColor = ccFunc(englishClass)
      if not classColor or not classColor.WrapTextInColorCode then return nil end
      return classColor:WrapTextInColorCode(name)
    end)
    if okWrap and wrapped then return wrapped end
  end

  -- 3) Opportunistic roster scan — fills the cache for next time.
  if IsInGroup() then
    local prefix, max = IsInRaid() and "raid" or "party", IsInRaid() and 40 or 4
    for i = 1, max do
      local unit = prefix .. i
      if UnitExists(unit) then
        local ok, _, uClass = pcall(UnitClass, unit)
        if ok and _validClass(uClass) then
          local ok2, uName = pcall(UnitName, unit)
          if ok2 and type(uName) == "string" and not isSecret(uName) then
            cacheInsert(uName, uClass)
          end
        end
      end
    end
  end

  local retryClass = cacheLookup(name)
  if retryClass then return ApplyClassColor(retryClass, name) end

  return name
end

-- ── Channel Shortening ──────────────────────────────────────────────

local CHANNEL_LINK_PAT = "|Hchannel:[^|]+|h%[([^%]]+)%]|h"

local CHAT_TYPE_REPLACE = {
  {"Party Leader", "PL"}, {"Raid Leader", "RL"}, {"Raid Warning", "RW"},
  {"Instance Leader", "IL"}, {"Instance", "I"}, {"Party", "P"}, {"Raid", "R"},
  {"Guild", "G"}, {"Officer", "O"}, {"Whisper", "W"}, {"BNet", "BN"},
  {"Say", "S"}, {"Yell", "Y"},
}

NS.ChatShortenChannel = function(msg)
  if not msg then return msg end
  local fmt = NS.DB("chatShortenFormat") or "none"
  if fmt == "none" then return msg end
  local ok, result = pcall(function()
    msg = msg:gsub(CHANNEL_LINK_PAT, function(displayText)
      local num = displayText:match("^(%d+)%.")
      if not num then return end
      if fmt == "bracket" then return "(" .. num .. ")"
      elseif fmt == "minimal" then return num end
    end)
    for _, entry in ipairs(CHAT_TYPE_REPLACE) do
      local long, short = entry[1], entry[2]
      if fmt == "bracket" then
        msg = msg:gsub("%(" .. long .. "%)", "(" .. short .. ")")
        msg = msg:gsub("%[" .. long .. "%]", "(" .. short .. ")")
      elseif fmt == "minimal" then
        msg = msg:gsub("%(" .. long .. "%) ", short .. " ")
        msg = msg:gsub("%[" .. long .. "%] ", short .. " ")
      end
    end
    if fmt == "bracket" then
      msg = msg:gsub(" says:", " (S):"); msg = msg:gsub(" yells:", " (Y):")
    elseif fmt == "minimal" then
      msg = msg:gsub(" says:", " S:"); msg = msg:gsub(" yells:", " Y:")
    end
    return msg
  end)
  return ok and result or msg
end

-- ── URL Detection ───────────────────────────────────────────────────

local URL_PATTERN = "https?://[%w%.%-_~:/?#%[%]@!$&'%(%)%*%+,;=%%]+"

NS.ChatFormatURLs = function(msg)
  if NS.DB("chatClickableUrls") == false then return msg end
  if not msg then return msg end
  local ok, found = pcall(string.find, msg, "https?://")
  if not ok or not found then return msg end
  local C = NS.CYAN
  local hex = string.format("%02x%02x%02x", C[1]*255, C[2]*255, C[3]*255)
  local ok2, result = pcall(string.gsub, msg, URL_PATTERN, function(url)
    return "|Haddon:lucidurl:" .. url .. "|h|cff" .. hex .. url .. "|r|h"
  end)
  return ok2 and result or msg
end

-- ── Strip WoW color/link codes ──────────────────────────────────────

NS.ChatStripColors = function(text)
  if not text then return "" end
  return text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", ""):gsub("|K.-|k", "")
end

-- ── Custom URL copy box ─────────────────────────────────────────────
local urlCopyFrame
NS.ShowURLCopyBox = function(url)
  if not url or url == "" then return end
  if urlCopyFrame then urlCopyFrame:Hide() end

  local ar, ag, ab = 0, 1, 1
  if NS.ChatGetAccentRGB then ar, ag, ab = NS.ChatGetAccentRGB() end

  local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  f:SetSize(480, 54)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetBackdrop(NS.BACKDROP)
  f:SetBackdropColor(0.04, 0.04, 0.06, 0.95)
  f:SetBackdropBorderColor(ar, ag, ab, 0.5)

  local label = f:CreateFontString(nil, "OVERLAY")
  label:SetFont(NS.FONT, 9, "")
  label:SetPoint("TOPLEFT", 8, -6)
  label:SetTextColor(0.5, 0.5, 0.6)
  label:SetText(L["Copy URL"])

  local eb = CreateFrame("EditBox", nil, f, "BackdropTemplate")
  eb:SetPoint("TOPLEFT", 6, -20)
  eb:SetPoint("BOTTOMRIGHT", -28, 6)
  eb:SetFontObject(GameFontHighlight)
  eb:SetAutoFocus(true)
  eb:SetText(url)
  eb:HighlightText()
  eb:SetScript("OnEscapePressed", function() f:Hide() end)
  eb:SetScript("OnEnterPressed", function() f:Hide() end)

  local closeBtn = CreateFrame("Button", nil, f)
  closeBtn:SetSize(16, 16)
  closeBtn:SetPoint("TOPRIGHT", -4, -4)
  local cFs = closeBtn:CreateFontString(nil, "OVERLAY")
  cFs:SetFont(NS.FONT, 11, "")
  cFs:SetAllPoints(); cFs:SetText("X"); cFs:SetTextColor(0.5, 0.5, 0.5)
  closeBtn:SetScript("OnClick", function() f:Hide() end)
  closeBtn:SetScript("OnEnter", function() cFs:SetTextColor(1, 0.3, 0.3) end)
  closeBtn:SetScript("OnLeave", function() cFs:SetTextColor(0.5, 0.5, 0.5) end)

  f:SetScript("OnHide", function() f:SetScript("OnHide", nil); urlCopyFrame = nil end)
  urlCopyFrame = f
  f:Show()
  eb:SetFocus()
end

-- Intercept URL clicks via SetItemRef (fires for all |Haddon:| links globally)
EventRegistry:RegisterCallback("SetItemRef", function(_, link, text, button)
  local url = link and link:match("^addon:lucidurl:(.*)")
  if url and url ~= "" then
    if IsShiftKeyDown() then
      local eb = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
      if eb then eb:Insert(url) end
    else
      NS.ShowURLCopyBox(url)
    end
  end
end)