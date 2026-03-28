-- LucidUI ChatFormat.lua
-- Timestamp formatting, class colors, channel shortening, URL detection.

local NS = LucidUINS

-- ── Timestamp ─────────────────────────────────────────────────────────

NS.ChatFormatTimestamp = function(unixTime)
  if NS.DB("chatTimestamps") == false then return nil end
  local fmt = NS.DB("chatTimestampFormat") or "%H:%M"
  local ts  = date(fmt, unixTime)
  local tsc = NS.DB("chatTimestampColor")
  local hex = "737373"
  if tsc and type(tsc) == "table" and tsc.r then
    hex = string.format("%02x%02x%02x", tsc.r*255, tsc.g*255, tsc.b*255)
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

local function SafeAmbiguate(name, mode)
  if Ambiguate then
    local ok, r = pcall(Ambiguate, name, mode)
    if ok and r then return r end
  end
  return (name:match("^([^%-]+)") or name)
end

local function ApplyClassColor(englishClass, name)
  if C_ClassColor then
    local ok, color = pcall(C_ClassColor.GetClassColor, englishClass)
    if ok and color and color.WrapTextInColorCode then return color:WrapTextInColorCode(name) end
  end
  local rc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[englishClass]
  if rc then return string.format("|cff%02x%02x%02x%s|r", rc.r*255, rc.g*255, rc.b*255, name) end
  return name
end

NS.ChatGetColoredSender = function(guid, name)
  if NS.DB("chatClassColors") == false then return name end
  if not guid or guid == "" then return name end
  if issecretvalue and issecretvalue(guid) then return name end
  if UnitClassFromGUID then
    local ok, _, englishClass = pcall(UnitClassFromGUID, guid)
    if ok and englishClass then return ApplyClassColor(englishClass, name) end
  end
  -- GetPlayerInfoByGUID returns: localizedClass, englishClass, race, localizedRace, gender, name, realm
  local ok, _, englishClass = pcall(GetPlayerInfoByGUID, guid)
  if ok and englishClass then return ApplyClassColor(englishClass, name) end
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
  local fmt = NS.DB("chatShortenFormat") or "none"
  if fmt == "none" then return msg end

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
end

-- ── URL Detection ───────────────────────────────────────────────────

local URL_PATTERN = "https?://[%w%.%-_~:/?#%[%]@!$&'%(%)%*%+,;=%%]+"

NS.ChatFormatURLs = function(msg)
  if NS.DB("chatClickableUrls") == false then return msg end
  if not msg or not msg:find("https?://", 1, true) then return msg end
  -- NS.CYAN is always kept in sync with the active accent color
  local C = NS.CYAN
  local hex = string.format("%02x%02x%02x", C[1]*255, C[2]*255, C[3]*255)
  return msg:gsub(URL_PATTERN, "|cff" .. hex .. "%0|r")
end

-- ── Strip WoW color/link codes ──────────────────────────────────────

NS.ChatStripColors = function(text)
  if not text then return "" end
  return text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", ""):gsub("|K.-|k", "")
end
