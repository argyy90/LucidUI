-- LucidUI Modules/CooldownTracker.lua
-- Spell cooldown tracker with icon + bar display modes.

local NS = LucidUINS
NS.CooldownTracker = NS.CooldownTracker or {}
local CT = NS.CooldownTracker
CT._unlocked = false

local CD_FONT = "Fonts/FRIZQT__.TTF"

-- ── DB ──────────────────────────────────────────────────────────────────
local function GetSpells()
  if not LucidUIDB._cdSpells then LucidUIDB._cdSpells = {} end
  return LucidUIDB._cdSpells
end
local function GetGroups()
  if not LucidUIDB._cdGroups then LucidUIDB._cdGroups = {} end
  return LucidUIDB._cdGroups
end

-- ── UID generator ───────────────────────────────────────────────────────
local uidCounter = 0
local function NextUID()
  uidCounter = uidCounter + 1
  return "cd" .. time() .. "_" .. uidCounter
end
local function EnsureUIDs()
  for _, e in ipairs(GetSpells()) do
    if not e.uid then e.uid = NextUID() end
  end
end

-- ── Frames ──────────────────────────────────────────────────────────────
local trackerFrames = {} -- [uid] = frame

-- ── Build a tracker element (icon + bar + text) ─────────────────────────
local function BuildTracker(uid, spellID, entry)
  -- Resolve settings: group → spell → global
  local grp = nil
  if entry.group then
    for _, g in ipairs(GetGroups()) do if g.name == entry.group then grp = g; break end end
  end
  -- Group settings override individual when grouped
  local DB_MAP = {iconWidth="cdTrackerIconWidth", iconHeight="cdTrackerIconHeight", barWidth="cdTrackerBarWidth", mode="cdTrackerMode"}
  local function Opt(key, default)
    if grp and grp[key] ~= nil then return grp[key] end
    if entry[key] ~= nil then return entry[key] end
    -- Legacy: map old iconSize to width/height
    if (key == "iconWidth" or key == "iconHeight") and entry.iconSize then return entry.iconSize end
    if DB_MAP[key] then return NS.DB(DB_MAP[key]) or default end
    return default
  end
  local ICON_W = Opt("iconWidth", 36)
  local ICON_H = Opt("iconHeight", 36)
  local BAR_W = Opt("barWidth", 120)
  local BAR_H = 14
  local mode = Opt("mode", "iconbar")
  local showBar = mode == "bar" or mode == "iconbar"
  local showIcon = mode == "icon" or mode == "iconbar"

  local f = trackerFrames[uid]
  if not f then
    f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("MEDIUM"); f:SetClampedToScreen(true)
    f:SetMovable(true); f:EnableMouse(false)

    -- Icon
    f.iconFrame = CreateFrame("Frame", nil, f)
    f.iconTex = f.iconFrame:CreateTexture(nil, "ARTWORK")
    f.iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.cd = CreateFrame("Cooldown", nil, f.iconFrame, "CooldownFrameTemplate")
    f.cd:SetDrawEdge(false); f.cd:SetDrawBling(false); f.cd:SetSwipeColor(0, 0, 0, 0.7)
    f.cd:SetHideCountdownNumbers(true)
    -- Aggressively remove Blizzard's built-in cooldown text
    f.cd.noCooldownCount = true -- flag for OmniCC/Blizzard to skip
    local cdRegions = {f.cd:GetRegions()}
    for _, region in ipairs(cdRegions) do
      if region:IsObjectType("FontString") then
        region:SetAlpha(0); region:Hide()
      end
    end
    -- Text overlay frame above the cooldown sweep
    f._textOverlay = CreateFrame("Frame", nil, f.iconFrame)
    f._textOverlay:SetAllPoints()
    f._textOverlay:SetFrameLevel(f.cd:GetFrameLevel() + 5)
    f.cdText = f._textOverlay:CreateFontString(nil, "OVERLAY")
    f.cdText:SetFont(CD_FONT, 14, "OUTLINE"); f.cdText:SetPoint("CENTER")

    -- Multi-type glow system
    -- Type 1: Border Pulse (4 edge textures)
    local function MakeGlowBorder(p1, p2, w, h)
      local t = f.iconFrame:CreateTexture(nil, "OVERLAY", nil, 7)
      t:SetPoint(p1, f.iconFrame, p1, 0, 0); t:SetPoint(p2, f.iconFrame, p2, 0, 0)
      if w then t:SetWidth(w) end; if h then t:SetHeight(h) end
      t:SetColorTexture(1, 1, 1, 0.8); t:Hide()
      return t
    end
    f._glowBorder = {
      MakeGlowBorder("TOPLEFT", "TOPRIGHT", nil, 2),
      MakeGlowBorder("BOTTOMLEFT", "BOTTOMRIGHT", nil, 2),
      MakeGlowBorder("TOPLEFT", "BOTTOMLEFT", 2, nil),
      MakeGlowBorder("TOPRIGHT", "BOTTOMRIGHT", 2, nil),
    }
    -- Type 2: Pixel Glow (8 small dots rotating around icon)
    f._glowPixels = {}
    for pi = 1, 8 do
      local dot = f.iconFrame:CreateTexture(nil, "OVERLAY", nil, 7)
      dot:SetSize(4, 4); dot:SetColorTexture(1, 1, 1, 0.9); dot:Hide()
      f._glowPixels[pi] = dot
    end
    -- Type 3: Shine (soft outer glow texture)
    f._glowShine = f.iconFrame:CreateTexture(nil, "OVERLAY", nil, 6)
    f._glowShine:SetPoint("TOPLEFT", 2, -2); f._glowShine:SetPoint("BOTTOMRIGHT", -2, 2)
    f._glowShine:SetTexture("Interface/AddOns/LucidUI/Assets/glow.tga")
    f._glowShine:SetBlendMode("ADD"); f._glowShine:Hide()

    -- Glow animation driver
    f._glowFrame = CreateFrame("Frame", nil, f.iconFrame)
    f._glowFrame:Hide()
    local ge = 0
    f._glowFrame:SetScript("OnUpdate", function(_, dt)
      ge = ge + dt
      local glowType = f._glowType or "border"
      if glowType == "border" then
        local alpha = 0.4 + 0.5 * math.sin(ge * 4)
        for _, gb in ipairs(f._glowBorder) do gb:SetAlpha(alpha) end
      elseif glowType == "pixel" then
        -- Move dots along the 4 inner edges of the icon (rectangle path)
        local w, h = f.iconFrame:GetWidth(), f.iconFrame:GetHeight()
        local perimeter = 2 * (w + h)
        local inset = 2 -- pixels from edge
        for pi, dot in ipairs(f._glowPixels) do
          local t = ((ge * 40 + (pi - 1) * (perimeter / 8)) % perimeter)
          local px, py
          if t < w then -- top edge: left to right
            px = -w/2 + inset + t; py = h/2 - inset
          elseif t < w + h then -- right edge: top to bottom
            px = w/2 - inset; py = h/2 - inset - (t - w)
          elseif t < 2*w + h then -- bottom edge: right to left
            px = w/2 - inset - (t - w - h); py = -h/2 + inset
          else -- left edge: bottom to top
            px = -w/2 + inset; py = -h/2 + inset + (t - 2*w - h)
          end
          dot:ClearAllPoints()
          dot:SetPoint("CENTER", f.iconFrame, "CENTER", px, py)
          dot:SetAlpha(0.6 + 0.4 * math.sin(ge * 4 + pi))
        end
      elseif glowType == "shine" then
        local alpha = 0.3 + 0.4 * math.sin(ge * 3)
        f._glowShine:SetAlpha(alpha)
      end
    end)

    -- Bar
    f.barBg = CreateFrame("Frame", nil, f)
    f.barBgTex = f.barBg:CreateTexture(nil, "BACKGROUND")
    f.barBgTex:SetAllPoints(); f.barBgTex:SetTexture("Interface/Buttons/WHITE8X8")
    f.barBgTex:SetVertexColor(0.03, 0.03, 0.05, 0.85)
    f.barFill = f.barBg:CreateTexture(nil, "ARTWORK")
    f.barFill:SetPoint("TOPLEFT", 1, -1); f.barFill:SetPoint("BOTTOMLEFT", 1, 1)
    f.barName = f.barBg:CreateFontString(nil, "OVERLAY")
    f.barName:SetFont(CD_FONT, 9, ""); f.barName:SetPoint("LEFT", 4, 0)
    f.barName:SetTextColor(0.85, 0.85, 0.92)
    f.barTime = f.barBg:CreateFontString(nil, "OVERLAY")
    f.barTime:SetFont(CD_FONT, 9, "OUTLINE"); f.barTime:SetPoint("RIGHT", -4, 0)

    trackerFrames[uid] = f
  end

  f.spellID = spellID
  -- Resolved options for the update loop (group overrides spell overrides global)
  f._opts = {
    glow = Opt("glow", true),
    glowType = Opt("glowType", "border"),
    glowDuration = Opt("glowDuration", 3),
    glowColor = (grp and grp.glowColor) or entry.glowColor or {1, 0.82, 0},
    cooldownInverse = Opt("cooldownInverse", false),
    desaturate = Opt("desaturate", true),
    showCDText = Opt("showCDText", true),
    cdTextSize = Opt("cdTextSize", 14),
    cdTextColor = (grp and grp.cdTextColor) or entry.cdTextColor or {1, 0.8, 0.2},
    barColorCD = grp and grp.barColorCD or entry.barColorCD,
    barColorReady = grp and grp.barColorReady or entry.barColorReady,
    barHeight = Opt("barHeight", 0),
    barTexture = Opt("barTexture", "Flat"),
    barBgTexture = Opt("barBgTexture", "Flat"),
    showSpellName = Opt("showSpellName", true),
    alphaOnCD = Opt("alphaOnCD", 1),
    alphaOnReady = Opt("alphaOnReady", 1),
    rangeCheck = Opt("rangeCheck", true),
    showOnlyActive = Opt("showOnlyActive", false),
    timeFormat = Opt("timeFormat", "pointed"),
    cdFont = Opt("cdFont", "default"),
  }

  -- Spell data
  local tex = C_Spell.GetSpellTexture(spellID)
  local name = C_Spell.GetSpellName(spellID) or ""
  f.iconTex:SetTexture(tex)
  f.barName:SetText(name)


  -- Font + text size
  local fontPath = NS.GetFontPath(f._opts.cdFont or "default")
  local txtSize = f._opts.cdTextSize or 14
  f.cdText:SetFont(fontPath, txtSize, "OUTLINE")

  -- Spell name on bar
  if f._opts.showSpellName == false then f.barName:SetText("") end
  f.barTime:SetFont(fontPath, math.max(8, txtSize - 2), "OUTLINE")

  -- Apply bar texture (uses same texture library as LucidMeter)
  local barTexKey = f._opts.barTexture or "Flat"
  f.barFill:SetTexture(NS.GetBarTexturePath(barTexKey))
  -- Apply bar background texture
  local barBgTexKey = f._opts.barBgTexture or "Flat"
  f.barBgTex:SetTexture(NS.GetBarTexturePath(barBgTexKey))
  f.barBgTex:SetVertexColor(0.03, 0.03, 0.05, 0.85)

  -- Inverse cooldown
  if f._opts.cooldownInverse then f.cd:SetReverse(true) else f.cd:SetReverse(false) end

  -- Layout based on mode
  f._mode = mode
  local totalW, totalH
  if showIcon and showBar then
    totalW = ICON_W + BAR_W; totalH = ICON_H
    f.iconFrame:SetSize(ICON_W, ICON_H); f.iconFrame:ClearAllPoints(); f.iconFrame:SetPoint("LEFT", f, "LEFT", 0, 0)
    f.iconTex:ClearAllPoints(); f.iconTex:SetAllPoints(f.iconFrame)
    f.cd:SetAllPoints(f.iconTex)
    f.barBg:SetSize(BAR_W, ICON_H); f.barBg:ClearAllPoints(); f.barBg:SetPoint("LEFT", f.iconFrame, "RIGHT", 0, 0)
    f.barFill:SetHeight(ICON_H - 2)
    f.iconFrame:Show(); f.barBg:Show()
    f.barName:Show(); f.barTime:Show()
    f.cdText:Hide()
  elseif showBar then
    totalW = BAR_W; totalH = BAR_H + 4
    f.barBg:SetSize(BAR_W, BAR_H + 4); f.barBg:ClearAllPoints(); f.barBg:SetPoint("LEFT", f, "LEFT", 0, 0)
    f.iconFrame:Hide()
    f.barBg:Show(); f.barName:Show(); f.barTime:Show()
  else -- icon only
    totalW = ICON_W; totalH = ICON_H
    f.iconFrame:SetSize(ICON_W, ICON_H); f.iconFrame:ClearAllPoints(); f.iconFrame:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.iconTex:ClearAllPoints(); f.iconTex:SetAllPoints(f.iconFrame)
    f.cd:SetAllPoints(f.iconTex)
    f.iconFrame:Show(); f.barBg:Hide()
    f.barName:Hide(); f.barTime:Hide()
    f.cdText:Show()
  end

  f:SetSize(totalW, totalH)

  -- Individual position per spell
  local pos = entry.pos
  if pos and pos.p then
    f:ClearAllPoints(); f:SetPoint(pos.p, UIParent, pos.p, pos.x, pos.y)
  else
    -- Count only unpositioned spells for default stacking
    local idx = 0
    for _, e in ipairs(GetSpells()) do
      if not (e.pos and e.pos.p) then
        idx = idx + 1
        if e.uid == uid then break end
      end
    end
    f:ClearAllPoints(); f:SetPoint("CENTER", UIParent, "CENTER", 0, -((idx - 1) * (totalH + 6)))
  end

  f:Show()
  return f
end

-- ── Cooldown tracking via cast events (avoids secret values) ────────────
-- Track: when spell was cast (GetTime) and its base CD duration
local cdState = {}  -- [spellID] = { castTime=GetTime(), duration=seconds }

-- Event frame for spell cast detection (player + pet)
local evFrame = CreateFrame("Frame")
evFrame:SetScript("OnEvent", function(_, _, unit, _, spellID)
  if unit ~= "player" and unit ~= "pet" then return end

  -- Pet spellIDs are tainted in Midnight — resolve via pcall + string fallback
  local resolvedID = spellID
  if unit == "pet" then
    local ok, found = pcall(function() return cdState[spellID] and spellID end)
    if ok and found then
      resolvedID = found
    else
      -- Tainted: try string conversion to match known tracked spells
      local sid = tonumber(tostring(spellID))
      if sid and cdState[sid] then resolvedID = sid
      else return end
    end
  end

  if not cdState[resolvedID] then return end
  cdState[resolvedID].castTime = GetTime()
  -- Learn CD duration on first cast (read after a short delay when API has real values)
  if cdState[resolvedID].duration == 0 then
    C_Timer.After(0.5, function()
      local cdInfo = C_Spell.GetSpellCooldown(resolvedID)
      if cdInfo then
        local ok, dur = pcall(function() return cdInfo.duration end)
        if ok and dur and type(dur) == "number" and dur > 1.5 then
          cdState[resolvedID].duration = dur
        end
      end
    end)
  end
end)

-- Populate CD duration from spell data (called when adding spells)
function CT._InitSpellCD(spellID)
  if cdState[spellID] then return end
  local baseDur = 0
  -- Method 1: GetSpellBaseCooldown (static data, not tainted)
  if GetSpellBaseCooldown then
    local ok, ms = pcall(GetSpellBaseCooldown, spellID)
    if ok and ms and ms > 1500 then baseDur = ms / 1000 end
  end
  -- Method 2: C_Spell.GetSpellCooldown (may be tainted — wrap everything in pcall)
  if baseDur == 0 then
    local ok, result = pcall(function()
      local cdInfo = C_Spell.GetSpellCooldown(spellID)
      if cdInfo and cdInfo.duration and cdInfo.duration > 1.5 then return cdInfo.duration end
    end)
    if ok and result then baseDur = result end
  end
  -- Method 3: check saved DB for user-provided duration
  local spells = GetSpells()
  for _, e in ipairs(spells) do
    if e.spellID == spellID and e.cdDuration and e.cdDuration > 0 then
      baseDur = e.cdDuration; break
    end
  end
  cdState[spellID] = { castTime = 0, duration = baseDur }
end

-- Update loop
-- Update loop via C_Timer (no OnUpdate frame overhead)
local updateTicker = nil

local function FormatTime(sec, fmt)
  if sec >= 60 then return math.ceil(sec / 60) .. "m" end
  if fmt == "pointed" then return string.format("%.1f", sec) end
  return tostring(math.ceil(sec))
end

local function UpdateTrackers()
  for _, f in pairs(trackerFrames) do
    if f.spellID then
      local o = f._opts or {}
      local tFmt = o.timeFormat or "pointed"

      -- "Show Only When Active" mode: track buff/aura duration
      if o.showOnlyActive then
        local auraRemaining, auraDuration = 0, 0
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, f.spellID)
        if ok and aura and aura.expirationTime then
          auraRemaining = aura.expirationTime - GetTime()
          auraDuration = aura.duration or 0
          if auraRemaining < 0 then auraRemaining = 0 end
        end
        if auraRemaining > 0 then
          f:Show(); f:SetAlpha(1)
          f.iconTex:SetDesaturated(false); f.iconTex:SetVertexColor(1, 1, 1)
          -- Sweep animation for buff duration
          if auraDuration > 0 then
            f.cd:SetReverse(true)
            f.cd:SetCooldown(aura.expirationTime - auraDuration, auraDuration)
          end
          -- Text
          local tc = o.cdTextColor or {1, 0.8, 0.2}
          local hasBar = f._mode == "bar" or f._mode == "iconbar"
          local hasIconText = f._mode == "icon"
          if (o.showCDText ~= false) and hasIconText then
            f.cdText:SetText(FormatTime(auraRemaining, tFmt))
            f.cdText:SetTextColor(tc[1], tc[2], tc[3])
          else
            f.cdText:SetText("")
          end
          if hasBar then
            local pct = auraDuration > 0 and (auraRemaining / auraDuration) or 1
            local barW = f.barBg:GetWidth() - 2
            f.barFill:SetWidth(math.max(1, pct * barW))
            local rc = o.barColorReady or {0.15, 0.65, 0.2}
            f.barFill:SetVertexColor(rc[1], rc[2], rc[3], 0.9)
            if o.showCDText ~= false then
              f.barTime:SetText(FormatTime(auraRemaining, tFmt))
              f.barTime:SetTextColor(tc[1], tc[2], tc[3])
            else f.barTime:SetText("") end
          end
        else
          f:Hide()
        end
      -- Normal cooldown tracking mode
      elseif f:IsShown() then
        local state = cdState[f.spellID]
        local remaining = 0
        local duration = 0
        if state and state.castTime > 0 and state.duration > 0 then
          remaining = (state.castTime + state.duration) - GetTime()
          duration = state.duration
          if remaining < 0 then remaining = 0 end
        end
        -- Feed to Blizzard CD frame for the sweep animation
        if state and state.castTime > 0 and state.duration > 0 and remaining > 0 then
          f.cd:SetCooldown(state.castTime, state.duration)
        end
        local useDesat = o.desaturate ~= false
        local useText = o.showCDText ~= false
        local useGlow = o.glow ~= false
        local glowDur = o.glowDuration or 3
        local barCDColor = o.barColorCD or {0.8, 0.3, 0.1}
        local barRdyColor = o.barColorReady or {0.15, 0.65, 0.2}
        -- Range check
        local outOfRange = false
        if remaining <= 0 and o.rangeCheck ~= false and UnitExists("target") then
          local ok2, inRange = pcall(function()
            if C_Spell and C_Spell.IsSpellInRange then
              return C_Spell.IsSpellInRange(f.spellID, "target")
            elseif IsSpellInRange then
              local name = C_Spell.GetSpellName(f.spellID)
              if name then return IsSpellInRange(name, "target") == 1 end
            end
          end)
          if ok2 and inRange == false then outOfRange = true end
        end
        if remaining > 0 then
          f:SetAlpha(o.alphaOnCD or 1); f:Show()
          local hasBar = f._mode == "bar" or f._mode == "iconbar"
          local hasIconText = f._mode == "icon"
          local tc = o.cdTextColor or {1, 0.8, 0.2}
          if useText and hasIconText then
            f.cdText:SetText(FormatTime(remaining, tFmt))
            f.cdText:SetTextColor(tc[1], tc[2], tc[3])
          else f.cdText:SetText("") end
          f.iconTex:SetDesaturated(useDesat); f.iconTex:SetVertexColor(1, 1, 1)
          if hasBar then
            local pct = duration > 0 and (remaining / duration) or 0
            local barW = f.barBg:GetWidth() - 2
            f.barFill:SetWidth(math.max(1, pct * barW))
            f.barFill:SetVertexColor(barCDColor[1], barCDColor[2], barCDColor[3], 0.9)
            if useText then
              f.barTime:SetText(FormatTime(remaining, tFmt))
              f.barTime:SetTextColor(tc[1], tc[2], tc[3])
            else f.barTime:SetText("") end
          end
        else
          f:SetAlpha(o.alphaOnReady or 1); f:Show()
          f.cdText:SetText(""); f.cd:Clear(); f.iconTex:SetDesaturated(false)
          if outOfRange then f.iconTex:SetVertexColor(0.8, 0.15, 0.15)
          else f.iconTex:SetVertexColor(1, 1, 1) end
          local hasBar2 = f._mode == "bar" or f._mode == "iconbar"
          if hasBar2 then
            local barW = f.barBg:GetWidth() - 2
            f.barFill:SetWidth(barW)
            f.barFill:SetVertexColor(barRdyColor[1], barRdyColor[2], barRdyColor[3], 0.8)
            f.barTime:SetText("Ready"); f.barTime:SetTextColor(barRdyColor[1]+0.15, barRdyColor[2]+0.15, barRdyColor[3]+0.15)
          end
          if useGlow and f._wasOnCD and not f._glowing then
            f._glowing = true; f._glowStart = GetTime()
            local gt = o.glowType or "border"; f._glowType = gt
            local gc = o.glowColor or {0.3, 1, 0.3}
            if gt == "border" then
              for _, gb in ipairs(f._glowBorder) do gb:SetColorTexture(gc[1],gc[2],gc[3],0.8); gb:Show() end
            elseif gt == "pixel" then
              for _, dot in ipairs(f._glowPixels) do dot:SetColorTexture(gc[1],gc[2],gc[3],0.9); dot:Show() end
            elseif gt == "shine" then
              f._glowShine:SetVertexColor(gc[1],gc[2],gc[3],0.7); f._glowShine:Show()
            end
            if f._glowFrame then f._glowFrame:Show() end
          end
          f._wasOnCD = false
        end
        -- Glow timeout
        if f._glowing and f._glowStart and (GetTime() - f._glowStart > glowDur) then
          f._glowing = false
          for _, gb in ipairs(f._glowBorder) do gb:Hide() end
          for _, dot in ipairs(f._glowPixels) do dot:Hide() end
          f._glowShine:Hide()
          if f._glowFrame then f._glowFrame:Hide() end
        end
        -- Track CD→Ready transition
        if remaining > 0 then
          f._wasOnCD = true
          if f._glowing then
            f._glowing = false
            for _, gb in ipairs(f._glowBorder) do gb:Hide() end
            for _, dot in ipairs(f._glowPixels) do dot:Hide() end
            f._glowShine:Hide()
            if f._glowFrame then f._glowFrame:Hide() end
          end
        end
      end -- if showOnlyActive / elseif normal CD
    end
  end
end

local function StartUpdateTicker()
  if not updateTicker then
    updateTicker = C_Timer.NewTicker(0.05, UpdateTrackers)
  end
end
local function StopUpdateTicker()
  if updateTicker then
    updateTicker:Cancel(); updateTicker = nil
  end
end

-- ── Refresh ─────────────────────────────────────────────────────────────
function CT.Refresh()
  local spells = GetSpells()
  -- Cleanup: fix any stale "__none__" group values from earlier bug
  for _, e in ipairs(spells) do
    if e.group == "__none__" then e.group = nil end
  end
  if NS.DB("cdTrackerEnabled") == false or #spells == 0 then
    for _, f in pairs(trackerFrames) do f:Hide() end
    StopUpdateTicker()
    evFrame:UnregisterAllEvents()
    cdState = {}
    return
  end

  -- Ensure all entries have UIDs
  EnsureUIDs()

  -- Active spec (1-4)
  local activeSpec = GetSpecialization() or 1

  -- Build group spec lookup: which groups are hidden by spec filter
  local groups = GetGroups()
  local groupHidden = {}
  for _, g in ipairs(groups) do
    if g.enabled == false or (g.spec and g.spec ~= activeSpec) then groupHidden[g.name] = true end
  end

  -- Build active spell set (skip: disabled, wrong spec, hidden group)
  local active = {}
  local activeSpellIDs = {}
  for _, entry in ipairs(spells) do
    local dominated = false
    -- Explicitly disabled spell
    if entry.enabled == false then dominated = true end
    -- Group hidden by spec
    if entry.group and groupHidden[entry.group] then dominated = true end
    -- Ungrouped spell with wrong spec
    if not entry.group and entry.spec and entry.spec ~= activeSpec then dominated = true end

    if not dominated then
      active[entry.uid] = true
      activeSpellIDs[entry.spellID] = true
      CT._InitSpellCD(entry.spellID)
      BuildTracker(entry.uid, entry.spellID, entry)
    end
  end

  -- Resource management: only track events for active spells
  -- Clean cdState of inactive spells
  for sid in pairs(cdState) do
    if not activeSpellIDs[sid] then cdState[sid] = nil end
  end
  -- Register/unregister cast event based on active spells
  if next(active) then
    evFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "pet")
    StartUpdateTicker()
  else
    evFrame:UnregisterAllEvents()
    StopUpdateTicker()
  end

  -- Position grouped spells relative to each other
  for _, g in ipairs(groups) do
    if groupHidden[g.name] then
      -- Hide all frames in this group
      for _, entry in ipairs(spells) do
        if entry.group == g.name and trackerFrames[entry.uid] then
          trackerFrames[entry.uid]:Hide()
        end
      end
    end
    local members = {}
    for _, entry in ipairs(spells) do
      if entry.group == g.name and active[entry.uid] and trackerFrames[entry.uid] then
        members[#members+1] = {entry=entry, frame=trackerFrames[entry.uid]}
      end
    end
    if #members > 0 then
      -- First member gets the group position
      local f1 = members[1].frame
      local gpos = g.pos
      if gpos and gpos.p then
        f1:ClearAllPoints(); f1:SetPoint(gpos.p, UIParent, gpos.p, gpos.x, gpos.y)
      elseif not members[1].entry.pos then
        f1:ClearAllPoints(); f1:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
      end
      -- Remaining members anchor to previous
      local grow = g.grow or "DOWN"
      local spacing = g.spacing ~= nil and g.spacing or 4
      for i = 2, #members do
        local prev = members[i-1].frame
        local cur = members[i].frame
        cur:ClearAllPoints()
        if grow == "RIGHT" then
          cur:SetPoint("LEFT", prev, "RIGHT", spacing, 0)
        elseif grow == "LEFT" then
          cur:SetPoint("RIGHT", prev, "LEFT", -spacing, 0)
        elseif grow == "DOWN" then
          cur:SetPoint("TOP", prev, "BOTTOM", 0, -spacing)
        else -- UP
          cur:SetPoint("BOTTOM", prev, "TOP", 0, spacing)
        end
      end
    end
  end

  -- Hide frames for removed spells
  for sid, f in pairs(trackerFrames) do
    if not active[sid] then f:Hide() end
  end
end

-- ── Lock / Unlock (per-spell dragging) ──────────────────────────────────
function CT.SetLocked(locked)
  local spells = GetSpells()
  -- For grouped spells, only the first in each group should be draggable
  local groupFirsts = {}
  for _, g in ipairs(GetGroups()) do
    for _, entry in ipairs(spells) do
      if entry.group == g.name then groupFirsts[entry.uid] = g.name; break end
    end
  end
  for _, entry in ipairs(spells) do
    local f = trackerFrames[entry.uid]
    if f then
      local isGroupFirst = groupFirsts[entry.uid]
      local isInGroup = entry.group ~= nil
      if locked then
        f:EnableMouse(false)
        f:SetScript("OnDragStart", nil); f:SetScript("OnDragStop", nil)
        -- Remove unlock border
        if f._unlockBorder then for _, ub in ipairs(f._unlockBorder) do ub:Hide() end end
      else
        -- Unlock border (accent colored)
        if not f._unlockBorder then
          local ar2, ag2, ab2 = NS.ChatGetAccentRGB()
          f._unlockBorder = {}
          local function UB(p1, p2, w, h)
            local t = f:CreateTexture(nil, "OVERLAY", nil, 7)
            t:SetPoint(p1, f, p1, 0, 0); t:SetPoint(p2, f, p2, 0, 0)
            if w then t:SetWidth(w) end; if h then t:SetHeight(h) end
            t:SetColorTexture(ar2, ag2, ab2, 0.6)
            f._unlockBorder[#f._unlockBorder+1] = t
          end
          UB("TOPLEFT","TOPRIGHT",nil,1); UB("BOTTOMLEFT","BOTTOMRIGHT",nil,1)
          UB("TOPLEFT","BOTTOMLEFT",1,nil); UB("TOPRIGHT","BOTTOMRIGHT",1,nil)
        end
        for _, ub in ipairs(f._unlockBorder) do ub:Show() end

        if isInGroup and not isGroupFirst then
          -- Grouped non-first: drag moves the first spell in group (which moves all)
          f:EnableMouse(true); f:RegisterForDrag("LeftButton")
          local firstF = nil
          for _, e2 in ipairs(spells) do
            if e2.group == entry.group and trackerFrames[e2.uid] then firstF = trackerFrames[e2.uid]; break end
          end
          local capGroupName = entry.group
          f:SetScript("OnDragStart", function() if firstF then firstF:StartMoving() end end)
          f:SetScript("OnDragStop", function()
            if firstF then
              firstF:StopMovingOrSizing()
              local p, _, _, x, y = firstF:GetPoint()
              for _, g in ipairs(GetGroups()) do
                if g.name == capGroupName then g.pos = {p=p, x=x, y=y}; break end
              end
            end
          end)
        else
          f:EnableMouse(true); f:RegisterForDrag("LeftButton")
          local capUID = entry.uid
          local capGroup = isGroupFirst
          f:SetScript("OnDragStart", function(s) s:StartMoving() end)
          f:SetScript("OnDragStop", function(s)
            s:StopMovingOrSizing()
            local p, _, _, x, y = s:GetPoint()
            if capGroup then
              for _, g in ipairs(GetGroups()) do
                if g.name == capGroup then g.pos = {p=p, x=x, y=y}; break end
              end
            else
              for _, e in ipairs(GetSpells()) do
                if e.uid == capUID then e.pos = {p=p, x=x, y=y}; break end
              end
            end
          end)
        end
      end
    end
  end
end

-- ── Add / Remove ────────────────────────────────────────────────────────
function CT.AddSpell(spellID)
  local spells = GetSpells()
  table.insert(spells, {spellID = spellID, uid = NextUID()}); CT.Refresh()
  if CT._unlocked then CT.SetLocked(false) end
  return true
end

function CT.RemoveSpellByUID(uid)
  local spells = GetSpells()
  for i, e in ipairs(spells) do
    if e.uid == uid then table.remove(spells, i); CT.Refresh(); return true end
  end
  return false
end

-- Legacy: remove first match by spellID
function CT.RemoveSpell(spellID)
  local spells = GetSpells()
  for i, e in ipairs(spells) do
    if e.spellID == spellID then table.remove(spells, i); CT.Refresh(); return true end
  end
  return false
end

-- ── Init ────────────────────────────────────────────────────────────────
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
initFrame:RegisterEvent("PLAYER_LOGOUT")
initFrame:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGOUT" then
    -- Save all tracker frame positions on logout
    for _, entry in ipairs(GetSpells()) do
      local f = trackerFrames[entry.uid]
      if f and f:GetPoint() then
        local p, _, _, x, y = f:GetPoint()
        entry.pos = {p=p, x=x, y=y}
      end
    end
    for _, g in ipairs(GetGroups()) do
      -- Save group position from first member frame
      for _, entry in ipairs(GetSpells()) do
        if entry.group == g.name and trackerFrames[entry.uid] then
          local f = trackerFrames[entry.uid]
          local p, _, _, x, y = f:GetPoint()
          if p then g.pos = {p=p, x=x, y=y} end
          break
        end
      end
    end
    return
  end
  if event == "PLAYER_LOGIN" then
    if NS.DB("cdTrackerEnabled") == false then
      evFrame:UnregisterAllEvents(); StopUpdateTicker()
      return
    end
    C_Timer.After(1, function() CT.Refresh() end)
  else
    -- Spec change: always refresh (Refresh handles disabled state internally)
    CT.Refresh()
  end
end)

-- ═══════════════════════════════════════════════════════════════════════
--  GROUP SUPPORT (GetGroups defined at top with GetSpells)
-- ═══════════════════════════════════════════════════════════════════════

function CT.AddGroup(name)
  local groups = GetGroups()
  table.insert(groups, {name=name, grow="DOWN", spacing=4, pos=nil})
  CT.Refresh()
end

function CT.RemoveGroup(name)
  local groups = GetGroups()
  for i, g in ipairs(groups) do
    if g.name == name then table.remove(groups, i); break end
  end
  -- Ungroup spells in this group
  for _, e in ipairs(GetSpells()) do
    if e.group == name then e.group = nil end
  end
  CT.Refresh()
end

-- ═══════════════════════════════════════════════════════════════════════
--  SETTINGS TAB (embedded sidebar + options)
-- ═══════════════════════════════════════════════════════════════════════
function CT.SetupSettings(parent)
  local container = CreateFrame("Frame", nil, parent)
  -- Dynamic accent: re-read on every access so live color changes work
  local function AC() return NS.ChatGetAccentRGB() end
  local ar, ag, ab = AC()
  local SBD = {bgFile="Interface/Buttons/WHITE8X8",edgeFile="Interface/Buttons/WHITE8X8",edgeSize=1}
  local SIDEBAR_W = 200

  local TOP_H = 30

  -- Card background
  local cardBg = CreateFrame("Frame", nil, container, "BackdropTemplate")
  cardBg:SetPoint("TOPLEFT", 2, -2); cardBg:SetPoint("BOTTOMRIGHT", -2, 2)
  cardBg:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
  cardBg:SetBackdropColor(0.034, 0.034, 0.056, 1)
  cardBg:SetBackdropBorderColor(0.08, 0.08, 0.13, 1)
  -- Left accent bar
  local accBar = cardBg:CreateTexture(nil, "OVERLAY", nil, 5); accBar:SetWidth(3)
  accBar:SetPoint("TOPLEFT", cardBg, "TOPLEFT", 0, -5); accBar:SetPoint("BOTTOMLEFT", cardBg, "BOTTOMLEFT", 0, 5)
  accBar:SetColorTexture(ar, ag, ab, 1)
  table.insert(NS.chatOptAccentTextures, {tex=accBar, alpha=1})
  -- Shadow bar
  local accBar2 = cardBg:CreateTexture(nil, "OVERLAY", nil, 4); accBar2:SetWidth(1)
  accBar2:SetPoint("TOPLEFT", cardBg, "TOPLEFT", 4, -8); accBar2:SetPoint("BOTTOMLEFT", cardBg, "BOTTOMLEFT", 4, 8)
  accBar2:SetColorTexture(ar, ag, ab, 0.30)
  table.insert(NS.chatOptAccentTextures, {tex=accBar2, alpha=0.30})
  -- Top-right L-bracket
  local trH = cardBg:CreateTexture(nil, "OVERLAY", nil, 5); trH:SetSize(14, 2)
  trH:SetPoint("TOPRIGHT", cardBg, "TOPRIGHT", -2, -2); trH:SetColorTexture(ar, ag, ab, 0.45)
  table.insert(NS.chatOptAccentTextures, {tex=trH, alpha=0.45})
  local trV = cardBg:CreateTexture(nil, "OVERLAY", nil, 5); trV:SetSize(2, 14)
  trV:SetPoint("TOPRIGHT", cardBg, "TOPRIGHT", -2, -2); trV:SetColorTexture(ar, ag, ab, 0.45)
  table.insert(NS.chatOptAccentTextures, {tex=trV, alpha=0.45})

  -- Enable checkbox + Lock button at the top
  local topBar = CreateFrame("Frame", nil, container)
  topBar:SetHeight(TOP_H); topBar:SetPoint("TOPLEFT", 4, -4); topBar:SetPoint("TOPRIGHT", -4, -4)
  local enCB = NS.ChatGetCheckbox(topBar, "Enable CD Tracker", 26, function(s) NS.DBSet("cdTrackerEnabled", s); CT.Refresh() end)
  enCB:SetParent(topBar); enCB:ClearAllPoints(); enCB:SetPoint("LEFT", 4, 0); enCB:SetSize(120, 22)
  enCB:SetValue(NS.DB("cdTrackerEnabled") ~= false)

  local lockBtn = CreateFrame("Button", nil, topBar, "BackdropTemplate"); lockBtn:SetSize(70, 20)
  lockBtn:SetPoint("RIGHT", topBar, "RIGHT", -4, 0)
  lockBtn:SetBackdrop(SBD); lockBtn:SetBackdropColor(0.04, 0.04, 0.07, 1); lockBtn:SetBackdropBorderColor(0.12, 0.12, 0.20, 1)
  local lockFS = lockBtn:CreateFontString(nil, "OVERLAY"); lockFS:SetFont("Fonts/FRIZQT__.TTF", 9, ""); lockFS:SetPoint("CENTER"); lockFS:SetTextColor(0.65, 0.65, 0.75); lockFS:SetText("Unlock")
  local isUnlocked = CT._unlocked
  if isUnlocked then lockFS:SetText("Lock"); lockBtn:SetBackdropBorderColor(ar, ag, ab, 0.8) end
  lockBtn:SetScript("OnClick", function()
    isUnlocked = not isUnlocked; CT._unlocked = isUnlocked; CT.SetLocked(not isUnlocked)
    lockFS:SetText(isUnlocked and "Lock" or "Unlock")
    local r,g,b = AC()
    if isUnlocked then lockBtn:SetBackdropBorderColor(r, g, b, 0.8) else lockBtn:SetBackdropBorderColor(0.12, 0.12, 0.20, 1) end
  end)
  lockBtn:SetScript("OnEnter", function() local r,g,b = AC(); lockBtn:SetBackdropBorderColor(r, g, b, 0.8) end)
  lockBtn:SetScript("OnLeave", function() if not isUnlocked then lockBtn:SetBackdropBorderColor(0.12, 0.12, 0.20, 1) end end)

  -- Top separator line
  local topLine = container:CreateTexture(nil, "OVERLAY", nil, 5); topLine:SetHeight(1)
  topLine:SetPoint("TOPLEFT", 4, -(TOP_H + 6)); topLine:SetPoint("TOPRIGHT", -4, -(TOP_H + 6))
  topLine:SetColorTexture(ar, ag, ab, 0.3)
  table.insert(NS.chatOptAccentTextures, {tex=topLine, alpha=0.3})

  -- ── Left sidebar ────────────────────────────────────────────────────
  local CONTENT_TOP = TOP_H + 8
  local sbBg = container:CreateTexture(nil, "BACKGROUND", nil, 2)
  sbBg:SetPoint("TOPLEFT", 4, -CONTENT_TOP); sbBg:SetPoint("BOTTOMLEFT", 4, 4); sbBg:SetWidth(SIDEBAR_W)
  sbBg:SetColorTexture(0.015, 0.015, 0.025, 1)
  local sbDiv = container:CreateTexture(nil, "OVERLAY", nil, 3); sbDiv:SetWidth(1)
  sbDiv:SetPoint("TOPLEFT", SIDEBAR_W + 4, -CONTENT_TOP); sbDiv:SetPoint("BOTTOMLEFT", SIDEBAR_W + 4, 4)
  sbDiv:SetColorTexture(ar, ag, ab, 0.25)
  table.insert(NS.chatOptAccentTextures, {tex=sbDiv, alpha=0.25})

  local listSF = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
  listSF:SetPoint("TOPLEFT", 6, -(CONTENT_TOP + 2)); listSF:SetPoint("BOTTOMLEFT", 6, 30)
  listSF:SetWidth(SIDEBAR_W - 24)
  if listSF.ScrollBar then listSF.ScrollBar:SetAlpha(0.3) end
  local listChild = CreateFrame("Frame", nil, listSF); listChild:SetWidth(SIDEBAR_W - 24)
  listSF:SetScrollChild(listChild)

  -- Bottom buttons
  local addSpellBtn = CreateFrame("Button", nil, container, "BackdropTemplate"); addSpellBtn:SetSize((SIDEBAR_W - 8) / 2, 20)
  addSpellBtn:SetPoint("BOTTOMLEFT", 6, 6); addSpellBtn:SetBackdrop(SBD)
  addSpellBtn:SetBackdropColor(0.04, 0.04, 0.07, 1); addSpellBtn:SetBackdropBorderColor(0.12, 0.12, 0.20, 1)
  local asFS = addSpellBtn:CreateFontString(nil, "OVERLAY"); asFS:SetFont("Fonts/FRIZQT__.TTF", 9, ""); asFS:SetPoint("CENTER"); asFS:SetTextColor(0.65, 0.65, 0.75); asFS:SetText("+ Spell")
  addSpellBtn:SetScript("OnEnter", function() local r,g,b = AC(); addSpellBtn:SetBackdropBorderColor(r, g, b, 0.8) end)
  addSpellBtn:SetScript("OnLeave", function() addSpellBtn:SetBackdropBorderColor(0.12, 0.12, 0.20, 1) end)

  local addGroupBtn = CreateFrame("Button", nil, container, "BackdropTemplate"); addGroupBtn:SetSize((SIDEBAR_W - 8) / 2, 20)
  addGroupBtn:SetPoint("LEFT", addSpellBtn, "RIGHT", 4, 0); addGroupBtn:SetBackdrop(SBD)
  addGroupBtn:SetBackdropColor(0.04, 0.04, 0.07, 1); addGroupBtn:SetBackdropBorderColor(0.12, 0.12, 0.20, 1)
  local agFS = addGroupBtn:CreateFontString(nil, "OVERLAY"); agFS:SetFont("Fonts/FRIZQT__.TTF", 9, ""); agFS:SetPoint("CENTER"); agFS:SetTextColor(0.65, 0.65, 0.75); agFS:SetText("+ Group")
  addGroupBtn:SetScript("OnEnter", function() local r,g,b = AC(); addGroupBtn:SetBackdropBorderColor(r, g, b, 0.8) end)
  addGroupBtn:SetScript("OnLeave", function() addGroupBtn:SetBackdropBorderColor(0.12, 0.12, 0.20, 1) end)

  -- ── Right panel ─────────────────────────────────────────────────────
  local rightPanel = CreateFrame("Frame", nil, container)
  rightPanel:SetPoint("TOPLEFT", SIDEBAR_W + 8, -CONTENT_TOP); rightPanel:SetPoint("BOTTOMRIGHT", -4, 4)
  local rpEmpty = rightPanel:CreateFontString(nil, "OVERLAY")
  rpEmpty:SetFont("Fonts/FRIZQT__.TTF", 11, ""); rpEmpty:SetPoint("CENTER"); rpEmpty:SetTextColor(0.35, 0.35, 0.45)
  rpEmpty:SetText("Select a spell or group")

  -- ── Reuse all the same logic from BuildConfigWindow ─────────────────
  local selectedType = nil
  local selectedKey = nil
  local listRows = {}
  local rpPage = nil  -- current MakePage scroll frame

  local function ClearRight()
    if rpPage then rpPage:Hide(); rpPage = nil end
    rpEmpty:Show()
  end

  -- ── BuildOptionsPanel using MakePage/R (same system as all other tabs) ──
  local MakeCard = NS._SMakeCard
  local MakePage = NS._SMakePage
  local R = NS._SR

  local function BuildOptionsPanel(data, isGroup, refreshCb)
    ClearRight(); rpEmpty:Hide()
    local sc, Append = MakePage(rightPanel)
    rpPage = sc:GetParent()  -- the ScrollFrame

    -- Helper: color swatch row
    local function ColorRow(card, label, key, default)
      local row = CreateFrame("Frame", nil, card.inner); row:SetHeight(24)
      local lbl = row:CreateFontString(nil, "OVERLAY"); lbl:SetFont("Fonts/FRIZQT__.TTF", 10, "")
      lbl:SetPoint("LEFT", 4, 0); lbl:SetTextColor(0.6, 0.6, 0.7); lbl:SetText(label)
      local cur = data[key] or default
      local sw = CreateFrame("Frame", nil, row, "BackdropTemplate"); sw:SetSize(20, 16); sw:SetPoint("LEFT", 110, 0)
      sw:SetBackdrop(SBD); sw:SetBackdropColor(cur[1], cur[2], cur[3], 1); sw:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
      local hit = CreateFrame("Button", nil, sw); hit:SetAllPoints()
      hit:SetScript("OnClick", function()
        ColorPickerFrame:SetupColorPickerAndShow({r = cur[1], g = cur[2], b = cur[3],
          swatchFunc = function() local r, g, b = ColorPickerFrame:GetColorRGB(); data[key] = {r, g, b}; sw:SetBackdropColor(r, g, b, 1); CT.Refresh() end,
          cancelFunc = function() sw:SetBackdropColor(cur[1], cur[2], cur[3], 1) end})
      end)
      R(card, row, 24)
    end
    -- Helper: slider
    local function Slider(card, label, key, mn, mx, fmt, default, scale)
      local s; s = NS.ChatGetSlider(card.inner, label, mn, mx, fmt, function()
        data[key] = scale and s:GetValue() / scale or s:GetValue(); CT.Refresh()
      end)
      R(card, s, 40)
      s:SetValue(scale and (data[key] or default) * scale or (data[key] or default))
    end
    -- Helper: number input box
    local function NumInput(card, label, key, default, suffix)
      local row = CreateFrame("Frame", nil, card.inner); row:SetHeight(26)
      local lbl = row:CreateFontString(nil, "OVERLAY"); lbl:SetFont("Fonts/FRIZQT__.TTF", 11, "")
      lbl:SetPoint("LEFT", 20, 0); lbl:SetTextColor(1, 1, 1); lbl:SetText(label)
      local box = CreateFrame("EditBox", nil, row, "BackdropTemplate")
      box:SetSize(50, 20); box:SetPoint("RIGHT", suffix and -30 or -8, 0)
      box:SetBackdrop(SBD); box:SetBackdropColor(0.06, 0.06, 0.1, 1); box:SetBackdropBorderColor(0.2, 0.2, 0.3, 1)
      box:SetFont("Fonts/FRIZQT__.TTF", 11, ""); box:SetTextColor(1, 1, 1)
      box:SetJustifyH("CENTER"); box:SetAutoFocus(false); box:SetNumeric(true)
      box:SetText(tostring(data[key] or default))
      if suffix then
        local sfx = row:CreateFontString(nil, "OVERLAY"); sfx:SetFont("Fonts/FRIZQT__.TTF", 9, "")
        sfx:SetPoint("LEFT", box, "RIGHT", 4, 0); sfx:SetTextColor(0.5, 0.5, 0.6); sfx:SetText(suffix)
      end
      local function Commit()
        local v = tonumber(box:GetText())
        if v and v >= 1 then data[key] = math.floor(v); CT.Refresh() end
        box:ClearFocus()
      end
      box:SetScript("OnEnterPressed", Commit)
      box:SetScript("OnEscapePressed", function() box:SetText(tostring(data[key] or default)); box:ClearFocus() end)
      box:SetScript("OnEditFocusGained", function() box:HighlightText() end)
      R(card, row, 26)
    end
    -- Helper: toggle (with optional tooltip)
    local function Toggle(card, label, key, default, tip)
      local cb = NS.ChatGetCheckbox(card.inner, label, 26, function(s) data[key] = s; CT.Refresh() end, tip)
      R(card, cb, 26)
      cb:SetValue(data[key] ~= nil and data[key] or default)
    end
    -- Helper: dropdown
    local function Dropdown(card, label, labels, values, key, default, onChange, maxH)
      local dd = NS.ChatGetDropdown(card.inner, label,
        function(v) return (data[key] or default) == v end,
        onChange or function(v) data[key] = v; CT.Refresh() end)
      dd:Init(labels, values, maxH)
      R(card, dd, 46)
    end

    local barTexNames = {}
    local rawBars = NS.GetLSMStatusBars and NS.GetLSMStatusBars() or {}
    for _, b in ipairs(rawBars) do barTexNames[#barTexNames + 1] = b.label end
    if #barTexNames == 0 then barTexNames = {"Flat", "Blizzard", "Blizzard Raid", "Blizzard Skills"} end

    -- ── Header card ──
    local cHdr = MakeCard(sc, nil)
    if not isGroup then
      local name = C_Spell.GetSpellName(data.spellID) or "Unknown"
      local tex = C_Spell.GetSpellTexture(data.spellID)
      local hdrRow = CreateFrame("Frame", nil, cHdr.inner); hdrRow:SetHeight(28)
      local ico = hdrRow:CreateTexture(nil, "ARTWORK"); ico:SetSize(24, 24); ico:SetPoint("LEFT", 4, 0)
      if tex then ico:SetTexture(tex); ico:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
      local nFS = hdrRow:CreateFontString(nil, "OVERLAY"); nFS:SetFont("Fonts/FRIZQT__.TTF", 12, "OUTLINE")
      nFS:SetPoint("LEFT", ico, "RIGHT", 6, 0); nFS:SetTextColor(1, 1, 1); nFS:SetText(name .. " |cff666666(" .. data.spellID .. ")|r")
      R(cHdr, hdrRow, 28)
      -- Enable toggle for individual spells
      local enCb = NS.ChatGetCheckbox(cHdr.inner, "Enabled", 26, function(s)
        data.enabled = s; CT.Refresh()
      end, "Enable or disable this spell tracker")
      R(cHdr, enCb, 26)
      enCb:SetValue(data.enabled ~= false)
    else
      local hdrRow = CreateFrame("Frame", nil, cHdr.inner); hdrRow:SetHeight(22)
      local nFS = hdrRow:CreateFontString(nil, "OVERLAY"); nFS:SetFont("Fonts/FRIZQT__.TTF", 12, "OUTLINE")
      nFS:SetPoint("LEFT", 4, 0); nFS:SetTextColor(ar, ag, ab, 1); nFS:SetText("> " .. data.name:upper())
      -- Inline rename EditBox (hidden by default)
      local renameBox = CreateFrame("EditBox", nil, hdrRow, "BackdropTemplate")
      renameBox:SetSize(180, 20); renameBox:SetPoint("LEFT", 4, 0)
      renameBox:SetBackdrop(SBD); renameBox:SetBackdropColor(0.06, 0.06, 0.1, 1); renameBox:SetBackdropBorderColor(ar, ag, ab, 0.8)
      renameBox:SetFont("Fonts/FRIZQT__.TTF", 12, "OUTLINE"); renameBox:SetTextColor(1, 1, 1)
      renameBox:SetAutoFocus(false); renameBox:Hide()
      local function CommitRename()
        local newName = strtrim(renameBox:GetText())
        if newName ~= "" and newName ~= data.name then
          local oldName = data.name
          data.name = newName
          -- Update all spells referencing this group
          for _, e in ipairs(GetSpells()) do if e.group == oldName then e.group = newName end end
        end
        renameBox:Hide(); nFS:Show()
        nFS:SetText("> " .. data.name:upper())
        RefreshList()
      end
      renameBox:SetScript("OnEnterPressed", CommitRename)
      renameBox:SetScript("OnEscapePressed", function() renameBox:Hide(); nFS:Show() end)
      -- Click group name to rename
      local nameHit = CreateFrame("Button", nil, hdrRow); nameHit:SetAllPoints(nFS)
      nameHit:SetScript("OnClick", function()
        nFS:Hide(); renameBox:SetText(data.name); renameBox:Show(); renameBox:SetFocus()
        renameBox:HighlightText()
      end)
      -- Enable toggle inline (right side of header row)
      local enCb = NS.ChatGetCheckbox(hdrRow, "Enable", 22, function(s)
        data.enabled = s; CT.Refresh(); RefreshList()
      end)
      enCb:ClearAllPoints(); enCb:SetPoint("RIGHT", -10, 0); enCb:SetSize(80, 22)
      enCb:SetValue(data.enabled ~= false)
      R(cHdr, hdrRow, 22)
    end
    cHdr:Finish(); Append(cHdr, cHdr:GetHeight())

    -- ── Grouped spell: limited info ──
    if not isGroup and data.group then
      local cGrp = MakeCard(sc, "In Group: " .. data.group)
      local infoRow = CreateFrame("Frame", nil, cGrp.inner); infoRow:SetHeight(20)
      local infoFS = infoRow:CreateFontString(nil, "OVERLAY"); infoFS:SetFont("Fonts/FRIZQT__.TTF", 10, "")
      infoFS:SetPoint("LEFT", 4, 0); infoFS:SetTextColor(0.55, 0.55, 0.65); infoFS:SetText("Settings inherited from group.")
      R(cGrp, infoRow, 20)
      -- Buttons
      local btnRow = CreateFrame("Frame", nil, cGrp.inner); btnRow:SetHeight(24)
      local ugBtn = CreateFrame("Button", nil, btnRow, "BackdropTemplate"); ugBtn:SetSize(130, 20); ugBtn:SetPoint("LEFT", 4, 0)
      ugBtn:SetBackdrop(SBD); ugBtn:SetBackdropColor(0.05, 0.05, 0.08, 1); ugBtn:SetBackdropBorderColor(0.15, 0.15, 0.15, 1)
      local ugFS = ugBtn:CreateFontString(nil, "OVERLAY"); ugFS:SetFont("Fonts/FRIZQT__.TTF", 9, ""); ugFS:SetPoint("CENTER"); ugFS:SetTextColor(0.65, 0.65, 0.75); ugFS:SetText("Remove from Group")
      ugBtn:SetScript("OnClick", function() data.group = nil; data.pos = nil; CT.Refresh(); RefreshList(); refreshCb(); if CT._unlocked then CT.SetLocked(false) end end)
      ugBtn:SetScript("OnEnter", function() ugBtn:SetBackdropBorderColor(ar, ag, ab, 0.8) end)
      ugBtn:SetScript("OnLeave", function() ugBtn:SetBackdropBorderColor(0.15, 0.15, 0.15, 1) end)
      local delBtn = CreateFrame("Button", nil, btnRow, "BackdropTemplate"); delBtn:SetSize(100, 20); delBtn:SetPoint("LEFT", ugBtn, "RIGHT", 6, 0)
      delBtn:SetBackdrop(SBD); delBtn:SetBackdropColor(0.08, 0.02, 0.02, 1); delBtn:SetBackdropBorderColor(0.28, 0.08, 0.08, 1)
      local delFS = delBtn:CreateFontString(nil, "OVERLAY"); delFS:SetFont("Fonts/FRIZQT__.TTF", 9, ""); delFS:SetPoint("CENTER"); delFS:SetTextColor(0.6, 0.18, 0.18); delFS:SetText("Remove Spell")
      delBtn:SetScript("OnClick", function() CT.RemoveSpellByUID(data.uid); ClearRight(); RefreshList() end)
      R(cGrp, btnRow, 24)
      cGrp:Finish(); Append(cGrp, cGrp:GetHeight())
      return
    end

    local curMode = data.mode or NS.DB("cdTrackerMode") or "iconbar"
    local hasIcon = curMode == "icon" or curMode == "iconbar"
    local hasBar = curMode == "bar" or curMode == "iconbar"

    -- ── Display card ──
    local cDisp = MakeCard(sc, "Display")
    Dropdown(cDisp, "Display Mode", {"Icon", "Bar", "Icon + Bar"}, {"icon", "bar", "iconbar"},
      "mode", curMode, function(v) data.mode = v; CT.Refresh(); refreshCb() end)
    if hasIcon then
      NumInput(cDisp, "Icon Width", "iconWidth", NS.DB("cdTrackerIconWidth") or 36, "px")
      NumInput(cDisp, "Icon Height", "iconHeight", NS.DB("cdTrackerIconHeight") or 36, "px")
    end
    if hasBar then
      Slider(cDisp, "Bar Width", "barWidth", 40, 300, "%spx", NS.DB("cdTrackerBarWidth") or 120)
    end
    cDisp:Finish(); Append(cDisp, cDisp:GetHeight())

    -- ── Cooldown card ──
    local cCD = MakeCard(sc, "Cooldown")
    Toggle(cCD, "Only Show When Active", "showOnlyActive", false, "Only show when the buff/aura is active, displaying remaining duration")
    Toggle(cCD, "Range Check", "rangeCheck", true, "Tint icon red when target is out of spell range")
    if hasIcon then Toggle(cCD, "Desaturate on CD", "desaturate", true, "Grey out icon while on cooldown") end
    Toggle(cCD, "Inverse CD", "cooldownInverse", false, "Reverse the cooldown sweep animation")
    Slider(cCD, "Alpha on CD", "alphaOnCD", 0, 10, "%s", 1, 10)
    Slider(cCD, "Alpha on Ready", "alphaOnReady", 0, 10, "%s", 1, 10)
    cCD:Finish(); Append(cCD, cCD:GetHeight())

    -- ── Text card ──
    local cTxt = MakeCard(sc, "Text")
    Toggle(cTxt, "Show CD Text", "showCDText", true, "Display remaining time on the icon or bar")
    Dropdown(cTxt, "Time Format", {"12.3 (pointed)", "13 (rounded)"}, {"pointed", "rounded"}, "timeFormat", "pointed")
    -- Font dropdown
    local fontNames, fontValues = {"Default"}, {"default"}
    for _, ft in ipairs(NS.GetLSMFonts()) do fontNames[#fontNames+1] = ft.label; fontValues[#fontValues+1] = ft.label end
    Dropdown(cTxt, "Font", fontNames, fontValues, "cdFont", "default", nil, 200)
    Slider(cTxt, "Text Size", "cdTextSize", 8, 28, "%spx", 14)
    ColorRow(cTxt, "Text Color:", "cdTextColor", {1, 0.8, 0.2})
    if hasBar then Toggle(cTxt, "Show Spell Name", "showSpellName", true, "Display spell name on the bar") end
    cTxt:Finish(); Append(cTxt, cTxt:GetHeight())

    -- ── Bar card (only when bar mode) ──
    if hasBar then
      local cBar = MakeCard(sc, "Bar")
      ColorRow(cBar, "CD Color:", "barColorCD", {0.8, 0.3, 0.1})
      ColorRow(cBar, "Ready Color:", "barColorReady", {0.15, 0.65, 0.2})
      Dropdown(cBar, "Bar Texture", barTexNames, barTexNames, "barTexture", "Flat", nil, 200)
      Dropdown(cBar, "Bar Background", barTexNames, barTexNames, "barBgTexture", "Flat", nil, 200)
      cBar:Finish(); Append(cBar, cBar:GetHeight())
    end

    -- ── Glow card (only when icon mode) ──
    if hasIcon then
      local cGlow = MakeCard(sc, "Glow")
      Toggle(cGlow, "Glow on Ready", "glow", true, "Play glow animation when spell comes off cooldown")
      Dropdown(cGlow, "Glow Type", {"Border Pulse", "Pixel Dots", "Shine"}, {"border", "pixel", "shine"}, "glowType", "border")
      Slider(cGlow, "Glow Duration", "glowDuration", 1, 10, "%ss", 3)
      ColorRow(cGlow, "Glow Color:", "glowColor", {1, 0.82, 0})
      cGlow:Finish(); Append(cGlow, cGlow:GetHeight())
    end

    -- ── Group Layout card (group only) ──
    if isGroup then
      local cGL = MakeCard(sc, "Group Layout")
      Dropdown(cGL, "Grow Direction", {"Right", "Left", "Down", "Up"}, {"RIGHT", "LEFT", "DOWN", "UP"},
        "grow", "DOWN", function(v) data.grow = v; CT.Refresh(); refreshCb() end)
      Slider(cGL, "Spacing", "spacing", 0, 20, "%spx", 4)
      -- Spec assignment
      local specLabels = {"All Specs"}; local specValues = {0}
      for i = 1, GetNumSpecializations() do
        local _, name = GetSpecializationInfo(i)
        if name then specLabels[#specLabels + 1] = name; specValues[#specValues + 1] = i end
      end
      local specDD = NS.ChatGetDropdown(cGL.inner, "Active for Spec",
        function(v) return (data.spec or 0) == v end,
        function(v) data.spec = v ~= 0 and v or nil; CT.Refresh() end)
      specDD:Init(specLabels, specValues)
      R(cGL, specDD, 46)
      cGL:Finish(); Append(cGL, cGL:GetHeight())
    end

    -- ── Group / Spec assignment card (spell only) ──
    if not isGroup then
      local cGA = MakeCard(sc, "Group / Spec")
      local groups = GetGroups(); local NONE_VAL = "__none__"
      local gLabels = {"None"}; local gValues = {NONE_VAL}
      for _, g in ipairs(groups) do gLabels[#gLabels + 1] = g.name; gValues[#gValues + 1] = g.name end
      Dropdown(cGA, "Assign to Group", gLabels, gValues, "group", NONE_VAL, function(v)
        if v == NONE_VAL then data.group = nil else data.group = v end
        data.pos = nil; CT.Refresh(); RefreshList(); refreshCb()
        if CT._unlocked then CT.SetLocked(false) end
      end)
      -- Per-spell spec (only when ungrouped — grouped spells inherit group spec)
      if not data.group then
        local specLabels2 = {"All Specs"}; local specValues2 = {0}
        for i = 1, GetNumSpecializations() do
          local _, name = GetSpecializationInfo(i)
          if name then specLabels2[#specLabels2 + 1] = name; specValues2[#specValues2 + 1] = i end
        end
        local spDD = NS.ChatGetDropdown(cGA.inner, "Active for Spec",
          function(v) return (data.spec or 0) == v end,
          function(v) data.spec = v ~= 0 and v or nil; CT.Refresh() end)
        spDD:Init(specLabels2, specValues2)
        R(cGA, spDD, 46)
      end
      cGA:Finish(); Append(cGA, cGA:GetHeight())
    end

    -- ── Actions card ──
    local cAct = MakeCard(sc, nil)
    local actRow = CreateFrame("Frame", nil, cAct.inner); actRow:SetHeight(24)
    local rgBtn = CreateFrame("Button", nil, actRow, "BackdropTemplate"); rgBtn:SetSize(110, 20); rgBtn:SetPoint("LEFT", 4, 0)
    rgBtn:SetBackdrop(SBD); rgBtn:SetBackdropColor(0.05, 0.05, 0.08, 1); rgBtn:SetBackdropBorderColor(0.15, 0.15, 0.15, 1)
    local rgFS2 = rgBtn:CreateFontString(nil, "OVERLAY"); rgFS2:SetFont("Fonts/FRIZQT__.TTF", 9, ""); rgFS2:SetPoint("CENTER"); rgFS2:SetTextColor(0.55, 0.55, 0.65)
    if isGroup then
      rgFS2:SetText("Reset Position"); rgBtn:SetScript("OnClick", function() data.pos = nil; CT.Refresh() end)
    else
      rgFS2:SetText("Reset to Global"); rgBtn:SetScript("OnClick", function()
        data.mode = nil; data.iconWidth = nil; data.iconHeight = nil; data.iconSize = nil; data.barWidth = nil
        data.glow = nil; data.glowType = nil; data.glowDuration = nil; data.glowColor = nil
        data.cooldownInverse = nil; data.desaturate = nil; data.showCDText = nil; data.timeFormat = nil; data.cdFont = nil; data.cdTextSize = nil; data.cdTextColor = nil
        data.barColorCD = nil; data.barColorReady = nil; data.barTexture = nil; data.barBgTexture = nil
        data.showSpellName = nil; data.alphaOnCD = nil; data.alphaOnReady = nil
        CT.Refresh(); refreshCb()
      end)
    end
    rgBtn:SetScript("OnEnter", function() rgBtn:SetBackdropBorderColor(ar, ag, ab, 0.8) end)
    rgBtn:SetScript("OnLeave", function() rgBtn:SetBackdropBorderColor(0.15, 0.15, 0.15, 1) end)
    local delBtn = CreateFrame("Button", nil, actRow, "BackdropTemplate"); delBtn:SetSize(100, 20); delBtn:SetPoint("LEFT", rgBtn, "RIGHT", 6, 0)
    delBtn:SetBackdrop(SBD); delBtn:SetBackdropColor(0.08, 0.02, 0.02, 1); delBtn:SetBackdropBorderColor(0.28, 0.08, 0.08, 1)
    local delFS = delBtn:CreateFontString(nil, "OVERLAY"); delFS:SetFont("Fonts/FRIZQT__.TTF", 9, ""); delFS:SetPoint("CENTER"); delFS:SetTextColor(0.6, 0.18, 0.18)
    delFS:SetText(isGroup and "Delete Group" or "Remove Spell")
    delBtn:SetScript("OnClick", function()
      if isGroup then CT.RemoveGroup(data.name) else CT.RemoveSpellByUID(data.uid) end; ClearRight(); RefreshList()
    end)
    delBtn:SetScript("OnEnter", function() delBtn:SetBackdropBorderColor(1, 0.25, 0.25, 1) end)
    delBtn:SetScript("OnLeave", function() delBtn:SetBackdropBorderColor(0.28, 0.08, 0.08, 1) end)
    R(cAct, actRow, 24)
    cAct:Finish(); Append(cAct, cAct:GetHeight())
  end

  local function ShowSpellOptions(entry)
    BuildOptionsPanel(entry, false, function() ShowSpellOptions(entry) end)
  end
  local function ShowGroupOptions(group)
    BuildOptionsPanel(group, true, function() ShowGroupOptions(group) end)
  end

  -- ── Reorder + Select ────────────────────────────────────────────────
  -- Swap within same group (or both ungrouped). Returns true if swapped.
  local function SwapSpells(idx1, idx2)
    local spells = GetSpells()
    if idx1 >= 1 and idx1 <= #spells and idx2 >= 1 and idx2 <= #spells then
      spells[idx1], spells[idx2] = spells[idx2], spells[idx1]
      CT.Refresh(); RefreshList()
    end
  end
  local function FindSpellIndex(uid)
    for i2, e2 in ipairs(GetSpells()) do if e2.uid == uid then return i2 end end
  end
  -- Find next/prev spell index within the same group (or ungrouped)
  local function FindSiblingIndex(uid, direction)
    local spells = GetSpells()
    local myIdx, myGroup
    for i, e in ipairs(spells) do
      if e.uid == uid then myIdx = i; myGroup = e.group; break end
    end
    if not myIdx then return nil end
    if direction > 0 then
      for i = myIdx + 1, #spells do
        if spells[i].group == myGroup then return i end
      end
    else
      for i = myIdx - 1, 1, -1 do
        if spells[i].group == myGroup then return i end
      end
    end
    return nil
  end

  -- ── Refresh sidebar ────────────────────────────────────────────────
  function RefreshList()
    ar, ag, ab = AC()  -- refresh accent color
    for _, r in ipairs(listRows) do r:Hide() end; listRows = {}
    local groups = GetGroups(); local spells = GetSpells()
    local ROW_H = 22; local yOff = 0
    local curSpec = GetSpecialization() or 1

    -- Check if a group is inactive (wrong spec)
    local function IsGroupInactive(g) return g.enabled == false or (g.spec and g.spec ~= curSpec) end
    -- Check if a spell is inactive (disabled, wrong spec, or in inactive group)
    local function IsSpellInactive(e)
      if e.enabled == false then return true end
      if e.group then
        for _, g in ipairs(groups) do if g.name == e.group then return IsGroupInactive(g) end end
      else
        if e.spec and e.spec ~= curSpec then return true end
      end
      return false
    end

    for _, g in ipairs(groups) do
      local isCollapsed = g._collapsed
      local gInactive = IsGroupInactive(g)
      local row = CreateFrame("Frame", nil, listChild); row:SetHeight(ROW_H)
      row:SetPoint("TOPLEFT", 0, -yOff); row:SetPoint("TOPRIGHT", 0, -yOff)
      local bg = row:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints()
      bg:SetColorTexture(ar, ag, ab, selectedType == "group" and selectedKey == g.name and 0.12 or 0.04)
      local fs = row:CreateFontString(nil, "OVERLAY"); fs:SetFont("Fonts/FRIZQT__.TTF", 9, "OUTLINE")
      fs:SetPoint("LEFT", 6, 0)
      if gInactive then fs:SetTextColor(ar * 0.4, ag * 0.4, ab * 0.4, 1)
      else fs:SetTextColor(ar, ag, ab, 1) end
      fs:SetText((isCollapsed and "v " or "> ") .. g.name:upper() .. (gInactive and "  |cff555555(inactive)|r" or ""))
      -- Dashed line under group header
      for di = 0, 2 do
        local dash = row:CreateTexture(nil, "OVERLAY", nil, 3); dash:SetSize(14, 1)
        dash:SetPoint("BOTTOMLEFT", 6 + di * 20, 1); dash:SetColorTexture(ar, ag, ab, 0.18)
      end
      local capG2 = g
      local colBtn = CreateFrame("Button", nil, row); colBtn:SetSize(ROW_H, ROW_H); colBtn:SetPoint("LEFT", 0, 0)
      colBtn:SetScript("OnClick", function() capG2._collapsed = not capG2._collapsed; RefreshList() end)
      local capG = g
      local hit = CreateFrame("Button", nil, row); hit:SetPoint("TOPLEFT", ROW_H, 0); hit:SetPoint("BOTTOMRIGHT", 0, 0)
      hit:SetScript("OnClick", function() selectedType = "group"; selectedKey = g.name; ShowGroupOptions(capG); RefreshList() end)
      row:Show(); listRows[#listRows + 1] = row; yOff = yOff + ROW_H

      if not isCollapsed then
        for _, e in ipairs(spells) do
          if e.group == g.name then
            local sr = CreateFrame("Frame", nil, listChild); sr:SetHeight(ROW_H)
            sr:SetPoint("TOPLEFT", 0, -yOff); sr:SetPoint("TOPRIGHT", 0, -yOff)
            local sbg = sr:CreateTexture(nil, "BACKGROUND"); sbg:SetAllPoints()
            local isSel = selectedType == "spell" and selectedKey == e.uid
            sbg:SetColorTexture(1, 1, 1, isSel and 0.06 or 0.015)
            local sico = sr:CreateTexture(nil, "ARTWORK"); sico:SetSize(16, 16); sico:SetPoint("LEFT", 18, 0)
            local stex = C_Spell.GetSpellTexture(e.spellID)
            if stex then sico:SetTexture(stex); sico:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
            local sfs = sr:CreateFontString(nil, "OVERLAY"); sfs:SetFont("Fonts/FRIZQT__.TTF", 9, "")
            sfs:SetPoint("LEFT", sico, "RIGHT", 4, 0)
            if IsSpellInactive(e) then sfs:SetTextColor(0.4, 0.4, 0.45); sico:SetDesaturated(true)
            else sfs:SetTextColor(0.8, 0.8, 0.9); sico:SetDesaturated(false) end
            sfs:SetText(C_Spell.GetSpellName(e.spellID) or "?")
            -- Up/Down arrows
            local capUID = e.uid
            local dn = CreateFrame("Button", nil, sr); dn:SetSize(14, 14); dn:SetPoint("RIGHT", -2, 0)
            local dTex = dn:CreateTexture(nil, "OVERLAY"); dTex:SetTexture("Interface/AddOns/LucidUI/Assets/Arrow_right_orange.png"); dTex:SetSize(10, 10); dTex:SetPoint("CENTER"); dTex:SetRotation(math.rad(-90)); dTex:SetAlpha(0.5)
            dn:SetScript("OnEnter", function() dTex:SetAlpha(1) end); dn:SetScript("OnLeave", function() dTex:SetAlpha(0.5) end)
            dn:SetScript("OnClick", function() local idx = FindSpellIndex(capUID); local t = FindSiblingIndex(capUID, 1); if idx and t then SwapSpells(idx, t) end end)
            local up = CreateFrame("Button", nil, sr); up:SetSize(14, 14); up:SetPoint("RIGHT", dn, "LEFT", -1, 0)
            local uTex = up:CreateTexture(nil, "OVERLAY"); uTex:SetTexture("Interface/AddOns/LucidUI/Assets/Arrow_right_green.png"); uTex:SetSize(10, 10); uTex:SetPoint("CENTER"); uTex:SetRotation(math.rad(90)); uTex:SetAlpha(0.5)
            up:SetScript("OnEnter", function() uTex:SetAlpha(1) end); up:SetScript("OnLeave", function() uTex:SetAlpha(0.5) end)
            up:SetScript("OnClick", function() local idx = FindSpellIndex(capUID); local t = FindSiblingIndex(capUID, -1); if idx and t then SwapSpells(idx, t) end end)
            -- Select
            local capE = e
            local hit = CreateFrame("Button", nil, sr); hit:SetPoint("TOPLEFT"); hit:SetPoint("BOTTOMRIGHT", up, "BOTTOMLEFT", -2, 0)
            hit:SetScript("OnClick", function() selectedType = "spell"; selectedKey = capUID; ShowSpellOptions(capE); RefreshList() end)
            sr:Show(); listRows[#listRows + 1] = sr; yOff = yOff + ROW_H
          end
        end
      end
    end

    local hasUngrouped = false
    for _, e in ipairs(spells) do if not e.group then hasUngrouped = true; break end end
    if hasUngrouped then
      local hdr = CreateFrame("Frame", nil, listChild); hdr:SetHeight(ROW_H)
      hdr:SetPoint("TOPLEFT", 0, -yOff); hdr:SetPoint("TOPRIGHT", 0, -yOff)
      local hfs = hdr:CreateFontString(nil, "OVERLAY"); hfs:SetFont("Fonts/FRIZQT__.TTF", 9, "")
      hfs:SetPoint("LEFT", 6, 0); hfs:SetTextColor(0.45, 0.45, 0.55); hfs:SetText("— Ungrouped —")
      hdr:Show(); listRows[#listRows + 1] = hdr; yOff = yOff + ROW_H
      for _, e in ipairs(spells) do
        if not e.group then
          local sr = CreateFrame("Frame", nil, listChild); sr:SetHeight(ROW_H)
          sr:SetPoint("TOPLEFT", 0, -yOff); sr:SetPoint("TOPRIGHT", 0, -yOff)
          local sbg = sr:CreateTexture(nil, "BACKGROUND"); sbg:SetAllPoints()
          local isSel2 = selectedType == "spell" and selectedKey == e.uid
          sbg:SetColorTexture(1, 1, 1, isSel2 and 0.06 or 0.015)
          local sico = sr:CreateTexture(nil, "ARTWORK"); sico:SetSize(16, 16); sico:SetPoint("LEFT", 6, 0)
          local stex = C_Spell.GetSpellTexture(e.spellID)
          if stex then sico:SetTexture(stex); sico:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
          local sfs = sr:CreateFontString(nil, "OVERLAY"); sfs:SetFont("Fonts/FRIZQT__.TTF", 9, "")
          sfs:SetPoint("LEFT", sico, "RIGHT", 4, 0)
          if e.enabled == false then sfs:SetTextColor(0.4, 0.4, 0.45); sico:SetDesaturated(true)
          else sfs:SetTextColor(0.8, 0.8, 0.9); sico:SetDesaturated(false) end
          sfs:SetText(C_Spell.GetSpellName(e.spellID) or "?")
          local capUID2 = e.uid
          local dn2 = CreateFrame("Button", nil, sr); dn2:SetSize(14, 14); dn2:SetPoint("RIGHT", -2, 0)
          local dT2 = dn2:CreateTexture(nil, "OVERLAY"); dT2:SetTexture("Interface/AddOns/LucidUI/Assets/Arrow_right_orange.png"); dT2:SetSize(10, 10); dT2:SetPoint("CENTER"); dT2:SetRotation(math.rad(-90)); dT2:SetAlpha(0.5)
          dn2:SetScript("OnEnter", function() dT2:SetAlpha(1) end); dn2:SetScript("OnLeave", function() dT2:SetAlpha(0.5) end)
          dn2:SetScript("OnClick", function() local idx = FindSpellIndex(capUID2); local t = FindSiblingIndex(capUID2, 1); if idx and t then SwapSpells(idx, t) end end)
          local up2 = CreateFrame("Button", nil, sr); up2:SetSize(14, 14); up2:SetPoint("RIGHT", dn2, "LEFT", -1, 0)
          local uT2 = up2:CreateTexture(nil, "OVERLAY"); uT2:SetTexture("Interface/AddOns/LucidUI/Assets/Arrow_right_green.png"); uT2:SetSize(10, 10); uT2:SetPoint("CENTER"); uT2:SetRotation(math.rad(90)); uT2:SetAlpha(0.5)
          up2:SetScript("OnEnter", function() uT2:SetAlpha(1) end); up2:SetScript("OnLeave", function() uT2:SetAlpha(0.5) end)
          up2:SetScript("OnClick", function() local idx = FindSpellIndex(capUID2); local t = FindSiblingIndex(capUID2, -1); if idx and t then SwapSpells(idx, t) end end)
          local capE2 = e
          local hit2 = CreateFrame("Button", nil, sr); hit2:SetPoint("TOPLEFT"); hit2:SetPoint("BOTTOMRIGHT", up2, "BOTTOMLEFT", -2, 0)
          hit2:SetScript("OnClick", function() selectedType = "spell"; selectedKey = capUID2; ShowSpellOptions(capE2); RefreshList() end)
          sr:Show(); listRows[#listRows + 1] = sr; yOff = yOff + ROW_H
        end
      end
    end
    listChild:SetHeight(math.max(1, yOff))
  end

  -- Add spell/group popups
  addSpellBtn:SetScript("OnClick", function()
    StaticPopupDialogs["LUI_CD_ADD_SPELL"] = {
      text = "Enter Spell ID:", hasEditBox = true, button1 = "Add", button2 = "Cancel",
      OnAccept = function(self)
        local id = tonumber(self.EditBox:GetText())
        if id and C_Spell.GetSpellName(id) then CT.AddSpell(id); RefreshList() end
      end,
      EditBoxOnEnterPressed = function(self)
        local id = tonumber(self:GetText())
        if id and C_Spell.GetSpellName(id) then CT.AddSpell(id); RefreshList() end
        self:GetParent():Hide()
      end, timeout = 0, whileDead = true, hideOnEscape = true}
    StaticPopup_Show("LUI_CD_ADD_SPELL")
  end)
  addGroupBtn:SetScript("OnClick", function()
    StaticPopupDialogs["LUI_CD_ADD_GROUP"] = {
      text = "Enter group name:", hasEditBox = true, button1 = "Create", button2 = "Cancel",
      OnAccept = function(self)
        local name = strtrim(self.EditBox:GetText())
        if name ~= "" then CT.AddGroup(name); RefreshList() end
      end,
      EditBoxOnEnterPressed = function(self)
        local name = strtrim(self:GetText())
        if name ~= "" then CT.AddGroup(name); RefreshList() end
        self:GetParent():Hide()
      end, timeout = 0, whileDead = true, hideOnEscape = true}
    StaticPopup_Show("LUI_CD_ADD_GROUP")
  end)

  container:SetScript("OnShow", function() RefreshList() end)
  return container
end
