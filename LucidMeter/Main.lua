-- LucidMeter — Core data engine using C_DamageMeter API (12.x+)
local NS = LucidUINS
NS.LucidMeter = NS.LucidMeter or {}
local DM = NS.LucidMeter

-- State
DM.inCombat = false
DM.available = false
DM.combatStartTime = 0
DM.combatElapsed = 0

local updateTicker = nil
local secretPollTicker = nil
local isSecret = issecretvalue or function() return false end

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

function DM.FormatNumber(n)
  if not n or n == 0 then return "0" end
  if n >= 1000000 then return string.format("%.2fM", n / 1000000) end
  if n >= 1000    then return string.format("%.1fK", n / 1000)    end
  return string.format("%.0f", n)
end


-- ── Fetch session data ───────────────────────────────────────────────
function DM.RefreshData()
  if not DM.available then return end
  if DM.RefreshAllWindows then DM.RefreshAllWindows() end
end

-- ── Get available sessions (for history menu) ────────────────────────
function DM.GetAvailableSessions()
  if not DM.available or not C_DamageMeter.GetAvailableCombatSessions then return {} end
  local ok, sessions = pcall(C_DamageMeter.GetAvailableCombatSessions)
  if not ok or not sessions then return {} end
  return sessions
end

-- ── Update display ───────────────────────────────────────────────────
local function DoUpdate()
  -- RefreshData already calls RefreshAllWindows which fetches C_DamageMeter data
  -- UpdateDisplay only needs to redraw, not refetch
  DM.RefreshData()
  if DM.UpdateDisplayOnly then DM.UpdateDisplayOnly() end
end

-- ── Poll for secret values to drop after combat ──────────────────────
local function PollForSecrets()
  DM.RefreshData()
  -- Check if any window has readable data
  if DM.windows then
    for _, w in ipairs(DM.windows) do
      if w.sessionData and w.sessionData.combatSources then
        if not isSecret(w.sessionData.combatSources) and #w.sessionData.combatSources > 0 then
          if secretPollTicker then secretPollTicker:Cancel(); secretPollTicker = nil end
          if DM.UpdateDisplay then DM.UpdateDisplay() end
          return
        end
      end
    end
  end
end

-- ── Combat lifecycle ─────────────────────────────────────────────────
local function OnCombatEnter()
  DM.inCombat = true
  DM.combatStartTime = GetTime()
  -- BUG FIX: cancel secretPollTicker if combat starts while it's still running
  -- (e.g. back-to-back pulls), otherwise poll and update ticker run in parallel
  if secretPollTicker then secretPollTicker:Cancel(); secretPollTicker = nil end
  if updateTicker then updateTicker:Cancel() end
  local interval = NS.DB("dmUpdateInterval") or 0.5
  -- In raids/dungeons, use longer interval to reduce CPU load
  local inInstance, instanceType = IsInInstance()
  if inInstance and (instanceType == "raid" or instanceType == "party") then
    interval = math.max(interval, 1.0)
  end
  updateTicker = C_Timer.NewTicker(interval, DoUpdate)
  DoUpdate()
  if DM.OnCombatStateChanged then DM.OnCombatStateChanged(true) end
end

local function OnCombatLeave()
  DM.inCombat = false
  DM.combatElapsed = GetTime() - DM.combatStartTime
  if updateTicker then updateTicker:Cancel(); updateTicker = nil end
  DoUpdate()
  if secretPollTicker then secretPollTicker:Cancel() end
  secretPollTicker = C_Timer.NewTicker(0.3, PollForSecrets)
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
  if updateTicker then updateTicker:Cancel(); updateTicker = nil end
  if secretPollTicker then secretPollTicker:Cancel(); secretPollTicker = nil end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_LOGIN" then
    if C_DamageMeter and C_DamageMeter.IsDamageMeterAvailable then
      DM.available = C_DamageMeter.IsDamageMeterAvailable()
    end
    if DM.available then
      -- Defer SetCVar to avoid taint: protected CVars must not be written during PLAYER_LOGIN
      -- (before PLAYER_ENTERING_WORLD the secure environment is not fully established)
      C_Timer.After(0, function()
        pcall(function()
          if C_CVar and C_CVar.SetCVar then
            C_CVar.SetCVar("damageMeterEnabled", "0")
          end
        end)
      end)
    end
    if DM.available and NS.DB("dmEnabled") then
      DM.RegisterEvents()
      if DM.BuildDisplay then DM.BuildDisplay() end
    end

  elseif event == "PLAYER_REGEN_DISABLED" then
    OnCombatEnter()

  elseif event == "PLAYER_REGEN_ENABLED" then
    OnCombatLeave()

  elseif event == "DAMAGE_METER_COMBAT_SESSION_UPDATED" then
    if DM.inCombat then return end
    DoUpdate()

  elseif event == "DAMAGE_METER_CURRENT_SESSION_UPDATED" then
    DoUpdate()

  elseif event == "PLAYER_ENTERING_WORLD" then
    local isLogin, isReload = ...
    if not isLogin and not isReload then
      local autoReset = NS.DB("dmAutoReset") or "off"
      local inInstance = IsInInstance()
      local shouldReset = false
      if autoReset == "enter" and inInstance then shouldReset = true end
      if autoReset == "leave" and not inInstance then shouldReset = true end
      if autoReset == "both" then shouldReset = true end
      if shouldReset then DM.Reset() end
    end

  elseif event == "DAMAGE_METER_RESET" then
    if DM.windows then
      for _, w in ipairs(DM.windows) do w.sessionData = nil end
    end
    if DM.UpdateDisplay then DM.UpdateDisplay() end
  end
end)

-- ── Reset (clears everything including C_DamageMeter history) ────────
function DM.Reset()
  if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
    pcall(C_DamageMeter.ResetAllCombatSessions)
  end
  if DM.windows then
    for _, w in ipairs(DM.windows) do
      w.sessionData = nil
    end
  end
  if DM.UpdateDisplay then DM.UpdateDisplay() end
end

-- ── Per-Spec: auto-save on activate, reload on spec change ──────────
do
  local function SaveCurrentMeterState()
    if not NS.IsPerSpec or not NS.IsPerSpec("dm") then return end
    if not DM.windows then return end
    local function specSet(k, v) LucidUIDB[NS.GetSpecSettingsKey("dm_", k)] = v end
    local extraWindows = {}
    for _, w in ipairs(DM.windows) do
      local l, t = w.frame and w.frame:GetLeft(), w.frame and w.frame:GetTop()
      local posData = l and {point = "TOPLEFT", x = l, y = t} or nil
      local sizeData = w.frame and {w = w.frame:GetWidth(), h = w.frame:GetHeight()} or nil
      if w.id == 1 then
        if posData then specSet("WinPos", posData) end
        if sizeData then specSet("WinSize", sizeData) end
        specSet("MeterType", w.meterType)
        specSet("SessionType", w.sessionType)
      else
        extraWindows[#extraWindows + 1] = {
          id = w.id, meterType = w.meterType, sessionType = w.sessionType,
          pos = posData, size = sizeData,
        }
      end
    end
    specSet("ExtraWindows", extraWindows)
  end

  -- Auto-save BEFORE spec changes (hook the activate button)
  if C_SpecializationInfo and C_SpecializationInfo.SetSpecialization then
    hooksecurefunc(C_SpecializationInfo, "SetSpecialization", function()
      SaveCurrentMeterState()
    end)
  end

  -- Also save on logout
  local logoutFrame = CreateFrame("Frame")
  logoutFrame:RegisterEvent("PLAYER_LOGOUT")
  logoutFrame:SetScript("OnEvent", SaveCurrentMeterState)

  -- Reload per-spec settings after spec change completes
  local function ApplyWindowState(w, pos, size, mt, st)
    local f = w.frame
    if pos and f then
      f:ClearAllPoints()
      if pos.point == "TOPLEFT" then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x or 0, pos.y or 0)
      else
        f:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER", pos.x or 0, pos.y or 0)
      end
    end
    if size and f then f:SetSize(size.w or 290, size.h or 220) end
    if mt ~= nil then w.meterType = mt end
    if st ~= nil then w.sessionType = st; w.sessionID = nil end
    w.scrollOffset = 0
    if DM.RefreshWindowData then pcall(DM.RefreshWindowData, w) end
    if DM.UpdateWindowDisplay then pcall(DM.UpdateWindowDisplay, w) end
  end

  DM.ApplyWindowState = ApplyWindowState

  local specFrame = CreateFrame("Frame")
  specFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
  specFrame:SetScript("OnEvent", function()
    if not NS.IsPerSpec or not NS.IsPerSpec("dm") then return end
    C_Timer.After(0.5, function()
      if not DM.windows then return end
      local function specGet(k) return LucidUIDB and LucidUIDB[NS.GetSpecSettingsKey("dm_", k)] end
      if DM.windows[1] then
        ApplyWindowState(DM.windows[1], specGet("WinPos"), specGet("WinSize"), specGet("MeterType"), specGet("SessionType"))
      end
      local extra = specGet("ExtraWindows")
      if extra then
        for _, ew in ipairs(extra) do
          for _, w in ipairs(DM.windows) do
            if w.id == ew.id then
              ApplyWindowState(w, ew.pos, ew.size, ew.meterType, ew.sessionType)
              break
            end
          end
        end
      end
    end)
  end)
end
