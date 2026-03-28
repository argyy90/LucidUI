-- LucidUI Messages.lua
-- DebugLog, message storage, history, redraw, save helpers.

local NS = LucidUINS
local DB    = NS.DB
local DBSet = NS.DBSet

-- ── Debug log ──────────────────────────────────────────────────────────────────
NS.DebugLog = function(msg, r, g, b)
  r, g, b = r or 0.7, g or 0.7, b or 0.7
  local entry = "|cff737373"..date("%H:%M:%S").."|r " .. msg
  table.insert(NS.debugLines, 1, {text=entry, r=r, g=g, b=b})
  if #NS.debugLines > NS.MAX_DEBUG then table.remove(NS.debugLines) end
  if NS.debugSMF then NS.debugSMF:AddMessage(entry, r, g, b) end
end

-- ── Hyperlink whitelist ────────────────────────────────────────────────────────
NS.validLinks = {
  achievement=true, conduit=true, currency=true, dungeonScore=true,
  instancelock=true, item=true, keystone=true, mawpower=true,
  quest=true, spell=true, talent=true, unit=true,
}

-- ── Format + Add ───────────────────────────────────────────────────────────────
local function FormatEntry(msg, ts_unix)
  local sep = " "
  if DB("chatShowSeparator") ~= false then
    -- NS.CYAN is always kept in sync with the active accent color
    local C = NS.CYAN
    local hex = string.format("%02x%02x%02x",
      math.floor(C[1]*255), math.floor(C[2]*255), math.floor(C[3]*255))
    sep = "|cff"..hex.."| |r"
  end
  if DB("timestamps") then
    local fmt = DB("chatTimestampFormat") or "%H:%M"
    local tsc = DB("chatTimestampColor")
    local tsHex = "737373"
    if tsc and type(tsc) == "table" and tsc.r then
      tsHex = string.format("%02x%02x%02x", tsc.r*255, tsc.g*255, tsc.b*255)
    end
    return "|cff"..tsHex..date(fmt, ts_unix or time()).."|r"..sep..msg
  end
  return msg
end

NS.AddMessage = function(text, r, g, b)
  local ts_unix = time()
  local maxL    = (LucidUIDB and LucidUIDB.maxLines) or NS.MAX_LINES

  -- Raw store (newest first)
  table.insert(NS.rawEntries, 1, {msg=text, r=r, g=g, b=b, ts=ts_unix})
  if #NS.rawEntries > maxL then table.remove(NS.rawEntries) end

  -- Formatted display
  local displayText = FormatEntry(text, ts_unix)
  if NS.smf then
    NS.smf:AddMessage(displayText, r, g, b)
    NS.smf:ScrollToBottom()
    if NS.UpdateScrollBtn then NS.UpdateScrollBtn() end
  end

  -- Copy-dialog store
  table.insert(NS.lines, 1, {text=displayText, r=r, g=g, b=b})
  if #NS.lines > maxL then table.remove(NS.lines) end

  -- Route to Loot chat tab if enabled
  if NS.DB("lootInChatTab") and NS.chatDisplay then
    local ts = NS.ChatFormatTimestamp and NS.ChatFormatTimestamp(ts_unix) or nil
    local tabD = NS.chatTabData and NS.chatTabData()
    if tabD then
      for tabIdx, td in ipairs(tabD) do
        if td._isLootTab then
          local curTab = NS.chatActiveTab and NS.chatActiveTab() or 1
          if tabIdx == curTab then
            NS.chatDisplay:AddMessage(text, r, g, b, ts, ts_unix)
          else
            local tMsgs = NS.chatTabMsgs
            if tMsgs then
              if not tMsgs[tabIdx] then tMsgs[tabIdx] = {} end
              local tm = tMsgs[tabIdx]
              tm[#tm+1] = {t=text, r=r or 1, g=g or 1, b=b or 1, prefix=ts, ts=ts_unix}
              if #tm > 200 then table.remove(tm, 1) end
            end
          end
          break
        end
      end
    end
  end

  -- SavedVariables history
  if LucidUIDB then
    LucidUIDB.history = LucidUIDB.history or {}
    table.insert(LucidUIDB.history, 1, {msg=text, r=r, g=g, b=b, ts=ts_unix})
    if #LucidUIDB.history > maxL then table.remove(LucidUIDB.history) end
  end
end

NS.LoadHistory = function()
  local hist = LucidUIDB and LucidUIDB.history
  if not hist or #hist == 0 then return end
  wipe(NS.lines); wipe(NS.rawEntries)
  local count = math.min(#hist, NS.MAX_LINES)
  for i = count, 1, -1 do
    local e = hist[i]
    if e then
      local msg   = e.msg or e.raw or e.text or ""
      local r,g,b = e.r or 0.8, e.g or 0.8, e.b or 0.8
      local ts_u  = e.ts
      table.insert(NS.rawEntries, {msg=msg, r=r, g=g, b=b, ts=ts_u})
      local displayText = FormatEntry(msg, ts_u)
      if NS.smf then NS.smf:AddMessage(displayText, r, g, b) end
      table.insert(NS.lines, {text=displayText, r=r, g=g, b=b})
    end
  end
end

NS.RedrawMessages = function()
  if not NS.smf then return end
  NS.smf:Clear()
  wipe(NS.lines)
  for i = #NS.rawEntries, 1, -1 do
    local e = NS.rawEntries[i]
    local displayText = FormatEntry(e.msg, e.ts)
    NS.smf:AddMessage(displayText, e.r, e.g, e.b)
    table.insert(NS.lines, {text=displayText, r=e.r, g=e.g, b=e.b})
  end
end

-- ── Position / size persistence ────────────────────────────────────────────────
NS.SavePosition = function()
  local s = NS.win:GetEffectiveScale() / UIParent:GetEffectiveScale()
  local l, t = NS.win:GetLeft(), NS.win:GetTop()
  if l and t then DBSet("position", {"TOPLEFT","UIParent","BOTTOMLEFT", l*s, t*s}) end
end

NS.SaveSize = function()
  if NS.win and not NS.win.collapsed then
    DBSet("size", {NS.win:GetSize()})
  end
end
