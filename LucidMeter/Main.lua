-- LucidMeter — Core data engine using C_DamageMeter API (12.x+)
local NS = LucidUINS
NS.LucidMeter = NS.LucidMeter or {}
local DM = NS.LucidMeter

-- State
DM.inCombat = false
DM.currentMeterType = 0   -- Enum.DamageMeterType.DamageDone
DM.currentSessionType = 1 -- Enum.DamageMeterSessionType.Current
DM.sessionData = nil      -- latest DamageMeterCombatSession
DM.available = false
DM.combatStartTime = 0
DM.combatElapsed = 0

local updateTicker = nil
local secretPollTicker = nil

-- ── Meter type labels ────────────────────────────────────────────────
DM.METER_TYPES = {
  {id = 0,  label = "Damage Done"},
  {id = 1,  label = "DPS"},
  {id = 2,  label = "Healing Done"},
  {id = 3,  label = "HPS"},
  {id = 4,  label = "Absorbs"},
  {id = 5,  label = "Interrupts"},
  {id = 6,  label = "Dispels"},
  {id = 7,  label = "Damage Taken"},
  {id = 8,  label = "Avoidable Damage"},
  {id = 9,  label = "Deaths"},
}

function DM.GetMeterLabel()
  for _, mt in ipairs(DM.METER_TYPES) do
    if mt.id == DM.currentMeterType then return mt.label end
  end
  return "Damage Done"
end

-- ── Number formatting ────────────────────────────────────────────────
function DM.FormatNumber(n)
  if not n or n == 0 then return "0" end
  if n >= 1000000 then return string.format("%.2fM", n / 1000000) end
  if n >= 1000 then return string.format("%.2fK", n / 1000) end
  return string.format("%.0f", n)
end

-- ── Fetch session data from C_DamageMeter ────────────────────────────
DM.currentSessionID = nil  -- nil = use sessionType, number = use specific session ID

function DM.RefreshData()
  if not DM.available then return end
  -- Refresh all windows (per-window data)
  if DM.RefreshAllWindows then DM.RefreshAllWindows() end
  -- Also keep legacy sessionData for backward compat
  local ok, session
  if DM.currentSessionID then
    ok, session = pcall(C_DamageMeter.GetCombatSessionFromID, DM.currentSessionID, DM.currentMeterType)
  else
    ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, DM.currentSessionType, DM.currentMeterType)
  end
  if not ok or not session then return end
  DM.sessionData = session
end

-- ── Get available sessions (for history menu) ────────────────────────
function DM.GetAvailableSessions()
  if not DM.available or not C_DamageMeter.GetAvailableCombatSessions then return {} end
  local ok, sessions = pcall(C_DamageMeter.GetAvailableCombatSessions)
  if not ok or not sessions then return {} end
  return sessions
end

-- ── Select a specific session by ID ──────────────────────────────────
function DM.SelectSessionByID(sessionID)
  DM.currentSessionID = sessionID
  DM.currentSessionType = nil
  DM.RefreshData()
  if DM.UpdateDisplay then DM.UpdateDisplay() end
end

-- ── Get sorted sources (players) ─────────────────────────────────────
function DM.GetSortedSources()
  if not DM.sessionData then return {} end
  local cs = DM.sessionData.combatSources
  if not cs then return {} end
  local isSecret = issecretvalue or function() return false end
  if isSecret(cs) then return {} end
  local sources = {}
  local ok = pcall(function()
    for i = 1, #cs do
      sources[#sources + 1] = cs[i]
    end
  end)
  if not ok then return {} end
  -- Sort: the combatSources from C_DamageMeter are already sorted by totalAmount desc,
  -- so we can skip sorting when values are secret
  if #sources > 0 and not isSecret(sources[1].totalAmount) then
    table.sort(sources, function(a, b) return (a.totalAmount or 0) > (b.totalAmount or 0) end)
  end
  return sources
end

-- ── Update display ───────────────────────────────────────────────────
local function DoUpdate()
  DM.RefreshData()
  if DM.UpdateDisplay then DM.UpdateDisplay() end
end

-- ── Poll for secret values to drop after combat ──────────────────────
local function PollForSecrets()
  DM.RefreshData()
  if DM.sessionData and DM.sessionData.combatSources and #DM.sessionData.combatSources > 0 then
    -- Data is readable, stop polling
    if secretPollTicker then secretPollTicker:Cancel(); secretPollTicker = nil end
    if DM.UpdateDisplay then DM.UpdateDisplay() end
  end
end

-- ── Combat lifecycle ─────────────────────────────────────────────────
local function OnCombatEnter()
  DM.inCombat = true
  DM.combatStartTime = GetTime()
  -- Start update ticker
  if updateTicker then updateTicker:Cancel() end
  local interval = NS.DB("dmUpdateInterval") or 0.3
  updateTicker = C_Timer.NewTicker(interval, DoUpdate)
  DoUpdate()
  if DM.OnCombatStateChanged then DM.OnCombatStateChanged(true) end
end

local function OnCombatLeave()
  DM.inCombat = false
  DM.combatElapsed = GetTime() - DM.combatStartTime
  -- Stop fast ticker
  if updateTicker then updateTicker:Cancel(); updateTicker = nil end
  -- Do immediate update
  DoUpdate()
  -- Poll for secrets to drop (data may still be secret right after combat)
  if secretPollTicker then secretPollTicker:Cancel() end
  secretPollTicker = C_Timer.NewTicker(0.3, PollForSecrets)
  -- Safety: stop polling after 5 seconds
  C_Timer.After(5, function()
    if secretPollTicker then secretPollTicker:Cancel(); secretPollTicker = nil end
    DoUpdate()
  end)
  if DM.OnCombatStateChanged then DM.OnCombatStateChanged(false) end
end

-- ── Event frame ──────────────────────────────────────────────────────
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")

function DM.RegisterEvents()
  eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
  eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
  eventFrame:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED")
  eventFrame:RegisterEvent("DAMAGE_METER_CURRENT_SESSION_UPDATED")
  eventFrame:RegisterEvent("DAMAGE_METER_RESET")
  eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
end

function DM.UnregisterEvents()
  eventFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
  eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
  eventFrame:UnregisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED")
  eventFrame:UnregisterEvent("DAMAGE_METER_CURRENT_SESSION_UPDATED")
  eventFrame:UnregisterEvent("DAMAGE_METER_RESET")
  eventFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
  -- Stop any running tickers
  if updateTicker then updateTicker:Cancel(); updateTicker = nil end
  if secretPollTicker then secretPollTicker:Cancel(); secretPollTicker = nil end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_LOGIN" then
    -- Check availability
    if C_DamageMeter and C_DamageMeter.IsDamageMeterAvailable then
      local isAvail = C_DamageMeter.IsDamageMeterAvailable()
      DM.available = isAvail
    end
    -- Disable default WoW damage meter window
    if DM.available then
      pcall(function()
        if C_CVar and C_CVar.SetCVar then
          C_CVar.SetCVar("damageMeterEnabled", "0")
        end
      end)
    end
    -- Load saved meter type
    DM.currentMeterType = NS.DB("dmMeterType") or 0
    DM.currentSessionType = NS.DB("dmSessionType") or 1
    -- Only register combat events and build display if enabled
    if DM.available and NS.DB("dmEnabled") then
      DM.RegisterEvents()
      if DM.BuildDisplay then DM.BuildDisplay() end
    end

  elseif event == "PLAYER_REGEN_DISABLED" then
    OnCombatEnter()

  elseif event == "PLAYER_REGEN_ENABLED" then
    OnCombatLeave()

  elseif event == "DAMAGE_METER_COMBAT_SESSION_UPDATED" then
    if DM.inCombat then return end -- ticker handles updates during combat
    DoUpdate()

  elseif event == "DAMAGE_METER_CURRENT_SESSION_UPDATED" then
    DoUpdate()

  elseif event == "PLAYER_ENTERING_WORLD" then
    local isLogin, isReload = ...

    -- History reset (clears C_DamageMeter sessions)
    local historyReset = NS.DB("dmHistoryReset") or "never"
    if historyReset == "reload" and (isLogin or isReload) then
      DM.Reset()
    elseif historyReset == "login" and isLogin and not isReload then
      DM.Reset()
    end

    -- Auto reset (only clears window display data, NOT session history)
    if not isLogin and not isReload then
      local autoReset = NS.DB("dmAutoReset") or "off"
      local inInstance = IsInInstance()
      local shouldReset = false
      if autoReset == "enter" and inInstance then shouldReset = true end
      if autoReset == "leave" and not inInstance then shouldReset = true end
      if autoReset == "both" then shouldReset = true end
      if shouldReset then DM.SoftReset() end
    end

  elseif event == "DAMAGE_METER_RESET" then
    DM.sessionData = nil
    if DM.windows then
      for _, w in ipairs(DM.windows) do w.sessionData = nil end
    end
    if DM.UpdateDisplay then DM.UpdateDisplay() end
  end
end)

-- ── Cycle meter type ─────────────────────────────────────────────────
function DM.CycleMeterType(delta)
  delta = delta or 1
  local types = DM.METER_TYPES
  local curIdx = 1
  for i, mt in ipairs(types) do
    if mt.id == DM.currentMeterType then curIdx = i; break end
  end
  curIdx = ((curIdx - 1 + delta) % #types) + 1
  DM.currentMeterType = types[curIdx].id
  NS.DBSet("dmMeterType", DM.currentMeterType)
  DoUpdate()
end

-- ── Soft Reset (clears window data only, keeps session history) ──────
function DM.SoftReset()
  DM.sessionData = nil
  if DM.windows then
    for _, w in ipairs(DM.windows) do
      w.sessionData = nil
      w.sessionType = 1  -- switch to Current
      w.sessionID = nil
    end
  end
  if DM.UpdateDisplay then DM.UpdateDisplay() end
end

-- ── Reset (clears everything including C_DamageMeter history) ────────
function DM.Reset()
  if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
    pcall(C_DamageMeter.ResetAllCombatSessions)
  end
  DM.sessionData = nil
  if DM.windows then
    for _, w in ipairs(DM.windows) do
      w.sessionData = nil
    end
  end
  if DM.UpdateDisplay then DM.UpdateDisplay() end
end
