-- LucidUI LootHandlers.lua
-- CHAT_MSG_LOOT and CHAT_MSG_MONEY processing.

local NS = LucidUINS
local DB = NS.DB

-- FIX: Use C_Item.GetItemInfo (Midnight 12.x API) instead of deprecated global GetItemInfo
-- ElvUI (ElvUI/Game/Mainline/Skins/Bags.lua) uses the same pattern:
--   local GetItemInfo = C_Item.GetItemInfo
local GetItemInfo = C_Item.GetItemInfo

local function GetItemQualityFromLink(link)
  if not link then return 1 end
  local itemID = link:match("item:(%d+)")
  if not itemID then return 1 end
  local _, _, quality = GetItemInfo(tonumber(itemID))
  return quality or 1
end

NS.OnLoot = function(msg, sender, senderGUID)
  -- Guard: WoW marks some encounter loot strings as "secret" / restricted.
  if type(msg) ~= "string" then return end
  local loc = GetLocale()
  local ownPrefix = (loc == "deDE") and "^Ihr " or "^You "
  local ok, isOwn = pcall(string.find, msg, ownPrefix)
  if not ok then
    NS.DebugLog("OnLoot: skipped (restricted msg)", 0.8, 0.5, 0)
    return
  end
  NS.DebugLog("EVENT: " .. (isOwn and "[Own]" or "[Group]") .. " " .. msg, 0.5, 0.8, 1)

  if isOwn then
    local minQ = DB("minQuality") or 0
    if minQ > 0 then
      local q = GetItemQualityFromLink(msg)
      if q < minQ then
        NS.DebugLog("BLOCKED quality="..tostring(q).." < min="..tostring(minQ), 1, 0.4, 0.4)
        return
      end
    end
    NS.DebugLog("ALLOWED own loot", 0.3, 1, 0.3)
    NS.AddMessage(msg, unpack(NS.COL.loot))
    local link = msg:match("|H[^|]+|h%[.-%]|h")
    if link and NS.StatsAddLoot then NS.StatsAddLoot(link, NS.characterFullName, GetItemQualityFromLink(msg)) end
  else
    if DB("showOnlyOwnLoot") == true then
      NS.DebugLog("BLOCKED only-own-loot active", 1, 0.4, 0.4)
    elseif DB("showGroupLoot") == false then
      NS.DebugLog("BLOCKED show-group-loot disabled", 1, 0.4, 0.4)
    end
    if DB("showGroupLoot") ~= false and DB("showOnlyOwnLoot") ~= true then
      local senderShort   = (sender or ""):match("^([^%-]+)") or sender or ""
      local senderDisplay = DB("showRealmName") and (sender or senderShort) or senderShort
      local minQ = DB("minQuality") or 0
      if minQ > 0 then
        local q = GetItemQualityFromLink(msg)
        if q < minQ then
          NS.DebugLog("BLOCKED group quality="..tostring(q).." < min="..tostring(minQ), 1, 0.4, 0.4)
          return
        end
      end
      local class
      if senderGUID and senderGUID ~= "" then
        local _, englishClass = GetPlayerInfoByGUID(senderGUID)
        class = englishClass
      end
      if not class then
        for i = 1, GetNumGroupMembers() do
          local unit = IsInRaid() and ("raid"..i) or ("party"..i)
          local _, englishClass = GetPlayerInfoByGUID(UnitGUID(unit) or "")
          local uname = GetUnitName(unit, true)
          if uname and (uname == sender or uname == senderShort) and englishClass then
            class = englishClass; break
          end
        end
      end
      local hex = NS.GetClassColor(class)
      local esc = senderShort:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])","%%%1")
      local coloredMsg = msg:gsub("^"..esc.."%-[^ ]+", hex..senderDisplay.."|r", 1)
      if coloredMsg == msg then coloredMsg = msg:gsub("^"..esc, hex..senderDisplay.."|r", 1) end
      NS.DebugLog("ALLOWED group loot", 0.3, 1, 0.3)
      NS.AddMessage(coloredMsg, unpack(NS.COL.group))
    end
  end
end

NS.OnMoney = function(msg)
  if DB("showMoney") ~= false then NS.AddMessage(msg, unpack(NS.COL.money)) end
end
