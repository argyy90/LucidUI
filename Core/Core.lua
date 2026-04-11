-- LucidUI Core/Core.lua
-- Namespace, constants, DB/theme system, Apply* functions, font helpers.
-- Loaded first (after Locales.lua). All other files access shared state via NS.

LucidUINS = LucidUINS or {}
local NS = LucidUINS

-- ── Shared Constants ────────────────────────────────────────────────────────────
NS.TEX_WHITE = "Interface/Buttons/WHITE8X8"
NS.FONT      = "Fonts/FRIZQT__.TTF"
NS.BACKDROP  = {bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1}

-- Color palette (reuse across all modules for consistency)
NS.COLOR_BG_DARK    = {0.025, 0.025, 0.038, 0.97}  -- window backgrounds
NS.COLOR_BG_PANEL   = {0.04, 0.04, 0.06, 0.95}      -- panels, popups
NS.COLOR_BG_ELEMENT = {0.06, 0.06, 0.10, 0.85}      -- bars, icons bg
NS.COLOR_BG_TRACK   = {0.03, 0.03, 0.05, 0.85}      -- scrollbar tracks, subtle bg
NS.COLOR_BORDER     = {0, 0, 0, 1}                   -- default black border
NS.COLOR_TEXT_DIM   = {0.45, 0.45, 0.45}             -- muted text (timestamps etc.)

-- Font size scale (reference values for consistent sizing)
NS.FONT_TITLE = 13   -- window titles, section headers
NS.FONT_BODY  = 11   -- default body text, labels
NS.FONT_SMALL = 9    -- captions, hints, secondary info

-- Layout spacing (reference values for consistent padding)
NS.PAD       = 10    -- standard inner padding
NS.PAD_TITLE = 26    -- title bar height / top padding
NS.SB_W      = 16    -- scrollbar width

-- Pixel perfect snap system (like Ayije's Pixel.lua)
do
  local pixelSize = 1
  function NS.PixelUpdate()
    local _, physH = GetPhysicalScreenSize()
    local scale = UIParent and UIParent:GetEffectiveScale() or 1
    if physH and physH > 0 and scale > 0 then
      pixelSize = 768 / (physH * scale)
    end
  end
  function NS.PixelSnap(value)
    if pixelSize <= 0 then return math.floor(value + 0.5) end
    return math.floor(value / pixelSize + 0.5) * pixelSize
  end
  function NS.PixelSize() return pixelSize end
  -- Init on first call; also updated on scale change events
  local pxFrame = CreateFrame("Frame")
  pxFrame:RegisterEvent("UI_SCALE_CHANGED")
  pxFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")
  pxFrame:SetScript("OnEvent", function() NS.PixelUpdate() end)
  C_Timer.After(0, NS.PixelUpdate) -- defer to after UIParent exists
end

-- Spell base ID normalization (resolves talent variants to base spells, like Ayije)
do
  local baseCache = {}
  local baseCacheSize = 0
  local MAX_CACHE = 2048
  function NS.NormalizeToBase(id)
    if not id or id <= 0 then return id end
    local cached = baseCache[id]
    if cached ~= nil then return cached end
    local base = C_Spell and C_Spell.GetBaseSpell and C_Spell.GetBaseSpell(id)
    local result = (base and base > 0 and base ~= id) and base or id
    if baseCacheSize >= MAX_CACHE then wipe(baseCache); baseCacheSize = 0 end
    baseCache[id] = result; baseCacheSize = baseCacheSize + 1
    return result
  end
  function NS.ClearSpellBaseCache() wipe(baseCache); baseCacheSize = 0 end
end

-- ── Profile Export/Import Encoding ──────────────────────────────────────────
-- Format: !LUI1!<base64_encoded_key=value_text>
-- Uses simple Base64 (no external libs needed)
do
  -- Base64 alphabet
  local b64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  local function Base64Encode(data)
    return ((data:gsub(".", function(x)
      local r, b = "", x:byte()
      for i = 8, 1, -1 do r = r .. (b % 2^i - b % 2^(i-1) > 0 and "1" or "0") end
      return r
    end) .. "0000"):gsub("%d%d%d?%d?%d?%d?", function(x)
      if #x < 6 then return "" end
      local c = 0
      for i = 1, 6 do c = c + (x:sub(i, i) == "1" and 2^(6-i) or 0) end
      return b64:sub(c+1, c+1)
    end) .. ({"", "==", "="})[#data % 3 + 1])
  end

  local function Base64Decode(data)
    data = data:gsub("[^" .. b64 .. "=]", "")
    return (data:gsub(".", function(x)
      if x == "=" then return "" end
      local r, f = "", (b64:find(x) - 1)
      for i = 6, 1, -1 do r = r .. (f % 2^i - f % 2^(i-1) > 0 and "1" or "0") end
      return r
    end):gsub("%d%d%d?%d?%d?%d?%d?%d?", function(x)
      if #x ~= 8 then return "" end
      local c = 0
      for i = 1, 8 do c = c + (x:sub(i, i) == "1" and 2^(8-i) or 0) end
      return string.char(c)
    end))
  end

  function NS.EncodeProfileString(rawText)
    return "!LUI1!" .. Base64Encode(rawText)
  end

  function NS.DecodeProfileString(encoded)
    if not encoded or type(encoded) ~= "string" then return nil end
    if not encoded:match("^!LUI1!") then return nil end
    return Base64Decode(encoded:sub(7))
  end
end

-- ── Per-Spec Settings System ────────────────────────────────────────────────
-- When "Current Spec" mode is active for a module (CDM or DM), settings are read/written
-- under spec-specific keys: e.g. cdv_spec_262_essWidth instead of cdv_essWidth
do
  function NS.GetSpecSettingsKey(prefix, key)
    local specIndex = GetSpecialization and GetSpecialization()
    if not specIndex then return prefix .. key end
    local specID = GetSpecializationInfo and GetSpecializationInfo(specIndex)
    if not specID then return prefix .. key end
    return prefix .. "spec_" .. specID .. "_" .. key
  end

  -- Check if per-spec mode is active for a module
  function NS.IsPerSpec(module)
    -- module: "cdv" or "dm"
    return LucidUIDB and LucidUIDB[module .. "_perSpec"] == true
  end

  -- Get a setting value, respecting per-spec mode
  function NS.GetSpecOpt(prefix, key, defaults)
    if NS.IsPerSpec(prefix:sub(1, -2)) then  -- "cdv_" → "cdv"
      local specKey = NS.GetSpecSettingsKey(prefix, key)
      if LucidUIDB and LucidUIDB[specKey] ~= nil then return LucidUIDB[specKey] end
    end
    -- Fallback to global
    if LucidUIDB and LucidUIDB[prefix .. key] ~= nil then return LucidUIDB[prefix .. key] end
    return defaults and defaults[key]
  end

end

-- Class colors (shared across LucidMeter, LootRolls, etc.)
NS.CLASS_COLORS = {
  WARRIOR     = {0.78, 0.61, 0.43}, PALADIN      = {0.96, 0.55, 0.73},
  HUNTER      = {0.67, 0.83, 0.45}, ROGUE        = {1.00, 0.96, 0.41},
  PRIEST      = {1.00, 1.00, 1.00}, DEATHKNIGHT  = {0.77, 0.12, 0.23},
  SHAMAN      = {0.00, 0.44, 0.87}, MAGE         = {0.41, 0.80, 0.94},
  WARLOCK     = {0.58, 0.51, 0.79}, MONK         = {0.00, 1.00, 0.59},
  DRUID       = {1.00, 0.49, 0.04}, DEMONHUNTER  = {0.64, 0.19, 0.79},
  EVOKER      = {0.20, 0.58, 0.50},
}

-- ── Shared mutable frame references (set by BuildWindow) ─────────────────────
NS.win              = nil
NS.titleBar         = nil
NS.titleTex         = nil
NS.titleText        = nil
NS.smf              = nil
NS.collapseBtn      = nil
NS.resizeWidget     = nil
NS.debugWin         = nil
NS.debugSMF         = nil
NS.btnIconTextures  = {}
NS.characterFullName = nil

-- ── Message/debug storage ──────────────────────────────────────────────────────
NS.lines      = {}   -- formatted entries (copy dialog)
NS.rawEntries = {}   -- raw {msg, r, g, b, ts}
NS.debugLines = {}   -- debug log entries

-- ── DB Init (must run before any module accesses LucidUIDB) ─────────────────
-- SavedVariables are loaded between ADDON_LOADED and PLAYER_LOGIN.
-- On first install LucidUIDB is nil — initialise it here.
EventUtil.ContinueOnAddOnLoaded("LucidUI", function()
  LucidUIDB = LucidUIDB or {}
end)

-- ── Helpers ───────────────────────────────────────────────────────────────────
-- Convert 0-1 RGB to hex string (e.g. "3bd2ed"). Use for |cff prefixes.
function NS.RGBToHex(r, g, b)
  return string.format("%02x%02x%02x", math.floor((r or 0) * 255), math.floor((g or 0) * 255), math.floor((b or 0) * 255))
end

-- ── Suppress taint popups (benign ADDON_ACTION_BLOCKED from combat hooks) ───
local taintSuppressor = CreateFrame("Frame")
taintSuppressor:RegisterEvent("ADDON_ACTION_BLOCKED")
taintSuppressor:RegisterEvent("ADDON_ACTION_FORBIDDEN")
taintSuppressor:SetScript("OnEvent", function(_, _, addon)
  if addon == "LucidUI" then
    StaticPopup_Hide("ADDON_ACTION_FORBIDDEN")
    StaticPopup_Hide("ADDON_ACTION_BLOCKED")
  end
end)

-- ── Slash commands ───────────────────────────────────────────────────────────
SLASH_LUCIDCDM1 = "/cdm"
SlashCmdList["LUCIDCDM"] = function()
  local f = _G["CooldownViewerSettings"]
  if f then f:SetShown(not f:IsShown()) end
end

-- ── LucidCDM single enable check ─────────────────────────────────────────────
function NS.IsCDMEnabled()
  return LucidUIDB and LucidUIDB["cdm_enabled"] == true
end

-- ── Get Essential Cooldowns container width (for autoSize) ──────────────────
function NS.GetCooldownsWidth()
  local ess = NS.Cooldowns and NS.Cooldowns._containers and NS.Cooldowns._containers["EssentialCooldownViewer"]
  if ess then
    local w = ess:GetWidth()
    if w and w > 10 then return w end
  end
  return nil
end

-- ── Safe Call (prevents crashes from conflicting addons) ─────────────────────
function NS.SafeCall(fn, moduleName)
  local ok, err = pcall(fn)
  if not ok then
    print("|cff3BD2ED[LucidUI]|r |cffff0000" .. (moduleName or "Module") .. " error:|r " .. tostring(err))
    print("|cff3BD2ED[LucidUI]|r This may be caused by a conflicting addon. Check your addon list.")
  end
end

-- ── DB Accessor Factory ─────────────────────────────────────────────────────
-- Creates Opt(key)/OptSet(key,val) functions for a module with a given DB prefix and defaults table.
-- Usage: local Opt, OptSet = NS.MakeOpt("cb_", DEFAULTS)
function NS.MakeOpt(prefix, defaults)
  local module = prefix:sub(1, -2)  -- "cdv_" → "cdv", "dm_" → "dm"
  local function Opt(key)
    local db = LucidUIDB
    if not db then return defaults[key] end
    -- Per-spec: check spec-specific key first
    if NS.IsPerSpec(module) then
      local specKey = NS.GetSpecSettingsKey(prefix, key)
      if db[specKey] ~= nil then return db[specKey] end
    end
    -- Global fallback
    if db[prefix .. key] ~= nil then return db[prefix .. key] end
    return defaults[key]
  end
  local function OptSet(key, val)
    if not LucidUIDB then return end
    if NS.IsPerSpec(module) then
      LucidUIDB[NS.GetSpecSettingsKey(prefix, key)] = val
    else
      LucidUIDB[prefix .. key] = val
    end
  end
  return Opt, OptSet
end

-- ── Anchor Chain Helper ──────────────────────────────────────────────────────
-- Stack order (bottom to top): Cooldowns → Resources → CastBar → BuffIcons → BuffBars
-- Each module anchors ABOVE the one below it.
-- gap = pixels between elements
function NS.AnchorToChain(frame, moduleName, gap)
  gap = gap or 4
  frame:ClearAllPoints()

  if moduleName == "ManaBar" then
    -- ManaBar sits directly above Essential cooldowns
    local ess = NS.Cooldowns and NS.Cooldowns._containers and NS.Cooldowns._containers["EssentialCooldownViewer"]
    if ess then frame:SetPoint("BOTTOM", ess, "TOP", 0, 1); return true end

  elseif moduleName == "Resources" then
    -- If ManaBar is active, anchor above ManaBar; otherwise above Cooldowns
    local manaBar = NS.Resources and NS.Resources._manaBar
    if manaBar and manaBar:IsShown() then
      frame:SetPoint("BOTTOM", manaBar, "TOP", 0, 1); return true
    end
    local ess = NS.Cooldowns and NS.Cooldowns._containers and NS.Cooldowns._containers["EssentialCooldownViewer"]
    if ess then frame:SetPoint("BOTTOM", ess, "TOP", 0, 1); return true end

  elseif moduleName == "CastBar" then
    -- Anchor above the topmost resource bar (secondary > primary > fallback)
    local topBar = NS.Resources and NS.Resources.GetTopBar and NS.Resources.GetTopBar()
    if topBar then frame:SetPoint("BOTTOM", topBar, "TOP", 0, gap - 2); return true end

  elseif moduleName == "BuffIcons" then
    -- Anchor above CastBar
    local castBar = NS.CastBar and NS.CastBar._bar
    if castBar then frame:SetPoint("BOTTOM", castBar, "TOP", 0, gap + 4); return true end

  elseif moduleName == "BuffBars" then
    -- Anchor above BuffIcons
    local iconContainer = NS.BuffBar and NS.BuffBar._containers and NS.BuffBar._containers["BuffIconCooldownViewer"]
    if iconContainer then frame:SetPoint("BOTTOM", iconContainer, "TOP", 0, gap); return true end
  end

  -- Fallback
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, -175)
  return false
end

-- Refresh the entire anchor chain (called when ManaBar toggles etc.)
function NS.RefreshAnchorChain()
  -- Re-anchor chain modules, reloading per-spec positions when available
  -- Helper: reload per-spec position on a frame
  local function ReloadPos(frame, prefix, key)
    if not frame then return end
    local pos = NS.GetSpecOpt(prefix, key, nil)
    if pos and type(pos) == "table" and pos.p then
      frame:ClearAllPoints()
      frame:SetPoint(pos.p, UIParent, pos.p, pos.x or 0, pos.y or 0)
      return true
    end
    return false
  end

  -- Re-anchor ManaBar above Essential (it has no saved position)
  local mana = NS.Resources and NS.Resources._manaBar
  if mana and mana:IsShown() then pcall(NS.AnchorToChain, mana, "ManaBar") end
  -- Resources
  local res = NS.Resources and NS.Resources._mainBar
  if res then
    if not ReloadPos(res, "res_", "pos") then pcall(NS.AnchorToChain, res, "Resources") end
  end
  -- CastBar
  local cb = NS.CastBar and NS.CastBar._bar
  if cb then
    if not ReloadPos(cb, "cb_", "pos") then pcall(NS.AnchorToChain, cb, "CastBar") end
  end
  -- BuffIcons
  local iconC = NS.BuffBar and NS.BuffBar._containers and NS.BuffBar._containers["BuffIconCooldownViewer"]
  if iconC then
    if not ReloadPos(iconC, "bb_", "buffIconPos") then pcall(NS.AnchorToChain, iconC, "BuffIcons") end
  end
  -- BuffBars
  local barC = NS.BuffBar and NS.BuffBar._containers and NS.BuffBar._containers["BuffBarCooldownViewer"]
  if barC then
    if not ReloadPos(barC, "bb_", "buffBarPos") then pcall(NS.AnchorToChain, barC, "BuffBars") end
  end
end

-- Re-anchor chain after combat ends (protected ops may have failed during combat init)
do
  local anchorEvFrame = CreateFrame("Frame")
  anchorEvFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
  anchorEvFrame:SetScript("OnEvent", function()
    if not NS.IsCDMEnabled or not NS.IsCDMEnabled() then return end
    -- Short delay so all modules have finished their REGEN_ENABLED handlers first
    C_Timer.After(0.3, function()
      NS.RefreshAnchorChain()
      -- ElvUI_Anchor plugin handles UF re-anchoring on REGEN_ENABLED automatically
    end)
  end)
end

-- ── AfterCombat Queue (AzortharionUI pattern) ──────────────────────────────
-- Queue functions to execute after combat ends. Safe for protected operations.
do
  local queue = {}
  local acFrame = CreateFrame("Frame")
  acFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
  acFrame:SetScript("OnEvent", function()
    local snapshot = {unpack(queue)}
    wipe(queue)
    for i = 1, #snapshot do
      pcall(snapshot[i])
    end
  end)
  function NS.AfterCombat(fn)
    if not InCombatLockdown() then
      pcall(fn)
    else
      queue[#queue + 1] = fn
    end
  end
end

-- ── Mover/Nudge Window ──────────────────────────────────────────────────────
-- Accent border + label on unlocked frames. Popup with editable X/Y on click.
local moverPopup = nil
local moverTarget = nil
local moverSaveFunc = nil
local moverResetFunc = nil
local moverFrames = {} -- all currently unlocked frames

local function BuildMoverPopup()
  if moverPopup then return end
  local ar, ag, ab = NS.ChatGetAccentRGB()
  local SBD = NS.BACKDROP

  local f = CreateFrame("Frame", "LucidUIMoverPopup", UIParent, "BackdropTemplate")
  f:SetSize(220, 100); f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetMovable(true); f:SetClampedToScreen(true); f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetBackdrop(SBD)
  f:SetBackdropColor(0.04, 0.04, 0.06, 0.95)
  f:SetBackdropBorderColor(ar, ag, ab, 0.6)

  -- Title
  f._title = f:CreateFontString(nil, "OVERLAY")
  f._title:SetFont(NS.FONT, 10, ""); f._title:SetPoint("TOP", 0, -6)
  f._title:SetTextColor(0.8, 0.8, 0.9)

  -- X EditBox
  local xLbl = f:CreateFontString(nil, "OVERLAY")
  xLbl:SetFont(NS.FONT, 11, "OUTLINE"); xLbl:SetPoint("TOPLEFT", 12, -26)
  xLbl:SetTextColor(ar, ag, ab); xLbl:SetText("X:")
  local xEB = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  xEB:SetSize(60, 18); xEB:SetPoint("LEFT", xLbl, "RIGHT", 4, 0)
  xEB:SetAutoFocus(false); xEB:SetNumeric(false); xEB:SetFontObject("ChatFontSmall")
  f._xEB = xEB

  -- Y EditBox
  local yLbl = f:CreateFontString(nil, "OVERLAY")
  yLbl:SetFont(NS.FONT, 11, "OUTLINE"); yLbl:SetPoint("LEFT", xEB, "RIGHT", 12, 0)
  yLbl:SetTextColor(ar, ag, ab); yLbl:SetText("Y:")
  local yEB = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  yEB:SetSize(60, 18); yEB:SetPoint("LEFT", yLbl, "RIGHT", 4, 0)
  yEB:SetAutoFocus(false); yEB:SetNumeric(false); yEB:SetFontObject("ChatFontSmall")
  f._yEB = yEB

  -- Apply on Enter
  local function ApplyXY()
    if not moverTarget then return end
    local x = tonumber(xEB:GetText())
    local y = tonumber(yEB:GetText())
    if x and y then
      moverTarget:ClearAllPoints()
      moverTarget:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, y)
      if moverSaveFunc then moverSaveFunc(moverTarget) end
    end
    xEB:ClearFocus(); yEB:ClearFocus()
  end
  xEB:SetScript("OnEnterPressed", ApplyXY)
  yEB:SetScript("OnEnterPressed", ApplyXY)

  -- Reset button
  local resetBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
  resetBtn:SetSize(50, 18); resetBtn:SetPoint("TOP", 0, -50)
  resetBtn:SetBackdrop(SBD); resetBtn:SetBackdropColor(0.06, 0.06, 0.1, 1); resetBtn:SetBackdropBorderColor(0.2, 0.2, 0.3, 1)
  local rfs = resetBtn:CreateFontString(nil, "OVERLAY"); rfs:SetFont(NS.FONT, 9, ""); rfs:SetPoint("CENTER"); rfs:SetTextColor(0.7, 0.7, 0.8); rfs:SetText("Reset")
  resetBtn:SetScript("OnEnter", function() resetBtn:SetBackdropBorderColor(ar, ag, ab, 0.8) end)
  resetBtn:SetScript("OnLeave", function() resetBtn:SetBackdropBorderColor(0.2, 0.2, 0.3, 1) end)
  f._resetBtn = resetBtn

  -- Nudge buttons
  local function Nudge(px, py)
    if not moverTarget then return end
    local left, top = moverTarget:GetLeft(), moverTarget:GetTop()
    if not left then return end
    moverTarget:ClearAllPoints()
    moverTarget:SetPoint("TOPLEFT", UIParent, "TOPLEFT", left + px, (top - GetScreenHeight()) + py)
    if moverSaveFunc then moverSaveFunc(moverTarget) end
    NS.UpdateMoverPopup()
  end

  local function NudgeBtn(parent, text, px, py, anchor, offX, offY)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(20, 18); btn:SetPoint(anchor, offX, offY)
    btn:SetBackdrop(SBD); btn:SetBackdropColor(0.06, 0.06, 0.1, 1); btn:SetBackdropBorderColor(0.2, 0.2, 0.3, 1)
    local bfs = btn:CreateFontString(nil, "OVERLAY"); bfs:SetFont(NS.FONT, 10, ""); bfs:SetPoint("CENTER"); bfs:SetTextColor(0.6, 0.6, 0.7); bfs:SetText(text)
    btn:SetScript("OnEnter", function() btn:SetBackdropBorderColor(ar, ag, ab, 0.8) end)
    btn:SetScript("OnLeave", function() btn:SetBackdropBorderColor(0.2, 0.2, 0.3, 1) end)
    btn:SetScript("OnClick", function() Nudge(px, py) end)
  end

  NudgeBtn(f, "<",  -1,  0, "BOTTOMLEFT", 8, 6)
  NudgeBtn(f, ">",   1,  0, "BOTTOMLEFT", 30, 6)
  NudgeBtn(f, "^",   0,  1, "BOTTOMLEFT", 54, 6)
  NudgeBtn(f, "v",   0, -1, "BOTTOMLEFT", 76, 6)
  NudgeBtn(f, "<<", -10,  0, "BOTTOMRIGHT", -76, 6)
  NudgeBtn(f, ">>",  10,  0, "BOTTOMRIGHT", -54, 6)
  NudgeBtn(f, "^^",   0, 10, "BOTTOMRIGHT", -30, 6)
  NudgeBtn(f, "vv",   0,-10, "BOTTOMRIGHT", -8, 6)

  f:Hide()
  moverPopup = f
end

-- Show border+label on a frame (called on unlock). Click opens popup.
function NS.ShowMoverPopup(frame, label, onSave, onReset)
  if not frame then return end
  local ar, ag, ab = NS.ChatGetAccentRGB()

  -- Accent border
  if not frame._moverBorder then
    local b = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    b:SetAllPoints(); b:SetFrameLevel(frame:GetFrameLevel() + 5)
    b:SetBackdrop({edgeFile="Interface/Buttons/WHITE8X8", edgeSize=2})
    b:SetBackdropColor(0, 0, 0, 0)
    frame._moverBorder = b
  end
  frame._moverBorder:SetBackdropBorderColor(ar, ag, ab, 0.9)
  frame._moverBorder:Show()

  -- Label
  if not frame._moverLabel then
    local fs = frame._moverBorder:CreateFontString(nil, "OVERLAY")
    fs:SetFont(NS.FONT, 9, "OUTLINE")
    fs:SetPoint("TOP", frame, "TOP", 0, 12)
    frame._moverLabel = fs
  end
  frame._moverLabel:SetTextColor(ar, ag, ab)
  frame._moverLabel:SetText(label or "")
  frame._moverLabel:Show()

  -- Store callbacks on frame
  frame._moverSave = onSave
  frame._moverReset = onReset
  frame._moverLabelText = label

  -- Click handler to show popup for this frame
  if not frame._moverClickSet then
    frame._moverClickSet = true
    frame:HookScript("OnMouseUp", function(self, button)
      if button == "LeftButton" and self._moverBorder and self._moverBorder:IsShown() then
        BuildMoverPopup()
        moverTarget = self
        moverSaveFunc = self._moverSave
        moverResetFunc = self._moverReset
        moverPopup._title:SetText(self._moverLabelText or "Position")
        moverPopup._resetBtn:SetScript("OnClick", function()
          if moverResetFunc then moverResetFunc() end
          moverPopup:Hide()
        end)
        moverPopup:ClearAllPoints()
        moverPopup:SetPoint("TOP", self, "BOTTOM", 0, -8)
        moverPopup:Show()
        NS.UpdateMoverPopup()
      end
    end)
  end

  moverFrames[frame] = true
end

function NS.UpdateMoverPopup()
  if not moverPopup or not moverPopup:IsShown() or not moverTarget then return end
  local left = moverTarget:GetLeft() or 0
  local top = moverTarget:GetTop() or 0
  local x = math.floor(left + 0.5)
  local y = math.floor(top - GetScreenHeight() + 0.5)
  moverPopup._xEB:SetText(x)
  moverPopup._yEB:SetText(y)
end

function NS.HideMoverPopup()
  if moverPopup then moverPopup:Hide() end
  for frame in pairs(moverFrames) do
    if frame._moverBorder then frame._moverBorder:Hide() end
    if frame._moverLabel then frame._moverLabel:Hide() end
  end
  wipe(moverFrames)
  moverTarget = nil
  moverSaveFunc = nil
  moverResetFunc = nil
end

-- ── Reload Popup Helper ──────────────────────────────────────────────────────
function NS.ShowReloadPopup(message, onCancel)
  StaticPopupDialogs["LUCIDUI_RELOAD"] = {
    text = message or "LucidUI: A reload is required for this change to take effect.",
    button1 = "Reload",
    button2 = "Cancel",
    OnAccept = function() ReloadUI() end,
    OnCancel = function()
      if onCancel then onCancel() end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
    preferredIndex = 3,
  }
  StaticPopup_Show("LUCIDUI_RELOAD")
end

-- ── Constants ──────────────────────────────────────────────────────────────────
NS.MAX_LINES = 50
NS.MAX_DEBUG = 200
NS.CYAN = {59/255, 210/255, 237/255}
NS.COL  = {
  loot  = {0.3,  0.9,  0.3},
  money = {1.0,  0.85, 0.0},
  group = {0.7,  0.9,  0.5},
}

-- ── Themes ─────────────────────────────────────────────────────────────────────
local DARK_THEME = {
  key       = "default",
  label     = "Default",
  bg        = {0.03, 0.03, 0.03, 0.95},
  border    = {0.15, 0.15, 0.15, 1.0},
  titleBg   = {0.06, 0.06, 0.06, 1.0},
  titleText = {1.0,  1.0,  1.0,  1.0},
  tilders   = {59/255, 210/255, 237/255, 1.0},
  btnColor  = {1.0,  1.0,  1.0,  1.0},
}
NS.DARK_THEME = DARK_THEME

local CUSTOM_DEFAULTS = {
  customBg        = {0.03, 0.03, 0.03, 0.95},
  customBorder    = {0.15, 0.15, 0.15, 1.0},
  customTitleBg   = {0.06, 0.06, 0.06, 1.0},
  customTitleText = {1.0,  1.0,  1.0,  1.0},
  customTilders   = {59/255, 210/255, 237/255, 1.0},
  customBtnColor  = {1.0,  1.0,  1.0,  1.0},
  titleName       = "LootTracker",
  showBrackets    = true,
}

local function GetCustomTheme()
  local function col(key)
    if LucidUIDB and LucidUIDB[key] then return LucidUIDB[key]
    else return CUSTOM_DEFAULTS[key] end
  end
  -- Normalize tilders: color picker saves {r,g,b}, defaults are {1,2,3,4}
  -- Always return array format so tid[1]/[2]/[3] works everywhere
  local function normalizeColor(c, fallback)
    if not c then return fallback end
    if c[1] then return c end  -- already array
    if c.r then return {c.r, c.g, c.b, 1} end  -- dict → array
    return fallback
  end
  return {
    key       = "custom",
    label     = "Custom",
    bg        = normalizeColor(col("customBg"),        CUSTOM_DEFAULTS.customBg),
    border    = normalizeColor(col("customBorder"),     CUSTOM_DEFAULTS.customBorder),
    titleBg   = normalizeColor(col("customTitleBg"),   CUSTOM_DEFAULTS.customTitleBg),
    titleText = normalizeColor(col("customTitleText"),  CUSTOM_DEFAULTS.customTitleText),
    tilders   = normalizeColor(col("customTilders"),    CUSTOM_DEFAULTS.customTilders),
    btnColor  = normalizeColor(col("customBtnColor"),   CUSTOM_DEFAULTS.customBtnColor),
  }
end

NS.GetTheme = function(key)
  if key == "custom" then return GetCustomTheme() end
  return DARK_THEME
end

-- ── DB / Config ─────────────────────────────────────────────────────────────────
NS.DB_DEFAULTS = {
  position        = {"CENTER", "UIParent", "CENTER", 0, 0},
  size            = {380, 260},
  theme           = "default",
  fontSize        = 12,
  timestamps      = true,
  showSeparator   = true,
  messageSpacing  = 5,
  showMoney       = true,
  showCurrency    = true,
  showGroupLoot   = true,
  showOnlyOwnLoot = false,
  showRealmName   = true,
  autoScroll      = true,
  maxLines        = 100,
  minQuality      = 0,
  enableFade      = true,
  fadeTime        = 60,
  alpha           = 20,
  titleAlpha      = 0,
  clearOnReload   = true,
  locked          = false,
  showSocialBtn   = true,
  showSettingsBtn = true,
  showCopyBtn     = true,
  showRollsBtn    = true,
  showStatsBtn    = true,
  showMPlusBtn    = true,
  showCoinBtn     = true,
  showVoiceChatBtn = true,
  showDebugBtn    = false,
  font            = "Friz Quadrata",
  fontOutline     = "",
  rollCloseMode   = "timer",
  rollCloseDelay  = 60,
  rollMinQuality  = 0,
  lootInChatTab   = false,
  lootOwnWindow   = false,
  lootWinTransparency = 0.2,
  statsTransparency = 0.03,
  rollsTransparency = 0.03,
  statsResetOnZone = false,
  clearOnLogin    = false,
  customBg        = {0.03, 0.03, 0.03, 0.95},
  customBorder    = {0.15, 0.15, 0.15, 1.0},
  customTitleBg   = {0.06, 0.06, 0.06, 1.0},
  customTitleText = {1.0,  1.0,  1.0,  1.0},
  customTilders   = {59/255, 210/255, 237/255, 1.0},
  customBtnColor  = {1.0,  1.0,  1.0,  1.0},
  -- Chat system defaults
  chatEnabled         = false,
  chatTimestamps      = true,
  chatTimestampFormat = "%H:%M",
  chatShowSeparator   = true,
  chatTimestampColor  = {r=0.45, g=0.45, b=0.45},
  chatFontSize        = 14,
  chatFont            = "Friz Quadrata",
  chatFontOutline     = "",
  chatMessageFade     = true,
  chatFadeTime        = 60,
  chatBgAlpha         = 0.5,
  chatTabBarAlpha     = 0.5,
  chatLocked          = false,
  chatWinPos          = nil,
  chatWinSize         = nil,
  chatTabs            = nil,
  chatClassColors     = true,
  chatShortenFormat   = "none",
  chatClickableUrls   = true,
  chatEditBoxPos      = "bottom",
  chatBarPosition     = "outside_right",
  chatBarVisibility   = "always",
  chatBarIconsPerRow  = 5,
  chatBarOrder        = {"social","settings","copy","rolls","stats","mplus","coin","voicechat"},
  chatMessageSpacing  = 0,
  chatTabSeparator    = true,
  chatCombatLog       = true,
  chatTabFlash        = "whisper",
  chatWhisperTab      = true,
  chatShowRealm       = false,
  chatStoreMessages   = true,
  chatRemoveOldMessages = true,
  chatHistory          = {},
  chatShowMinimap     = true,
  chatFontShadow      = false,
  chatEditBoxVisible   = false,
  chatEditBoxAccentBorder = true,
  chatTabHighlightBg   = true,
  chatAccentLine       = true,
  chatTabVisibility    = "always",
  chatColors           = {},
  chatBgColor          = {r=0, g=0, b=0},
  chatTabBarColor      = {r=0, g=0, b=0},
  chatEditBoxColor     = {r=0, g=0, b=0},
  chatTabColor         = {r=0, g=1, b=1},
  chatIconColor        = {r=0.8, g=0.8, b=0.8},
  -- QoL defaults
  qolCombatTimer       = false,
  qolCombatTimerInstance = false,
  qolCombatTimerHidePrefix = false,
  qolCombatTimerShowBg = false,
  qolCombatAlert       = false,
  qolFasterLoot        = false,
  qolSuppressWarnings  = false,
  qolEasyDestroy       = false,
  qolAutoKeystone      = false,
  qolSkipCinematics    = false,
  qolAutoSellGrey      = false,
  qolAutoRepair        = false,
  qolAutoRepairMode    = "guild",
  qolMouseRing         = false,
  qolRingColorR        = 0,
  qolRingColorG        = 0.8,
  qolRingColorB        = 0.8,
  qolMouseRingHideRMB  = false,
  qolMouseRingShowOOC  = false,
  qolMouseRingShape    = "ring.tga",
  qolMouseRingSize     = 48,
  qolMouseRingOpacity  = 0.8,
  qolTimerColorR       = 1,
  qolTimerColorG       = 1,
  qolTimerColorB       = 1,
  qolTimerFontSize     = 25,
  qolCombatEnterText   = "++Combat++",
  qolCombatLeaveText   = "--Combat--",
  qolAlertEnterR       = 1,
  qolAlertEnterG       = 0,
  qolAlertEnterB       = 0,
  qolAlertLeaveR       = 0,
  qolAlertLeaveG       = 1,
  qolAlertLeaveB       = 0,
  qolAlertFontSize     = 25,
  qolCombatTimerPos    = nil,
  qolCombatAlertPos    = nil,
  qolFpsBackup         = nil,
  -- Damage Meter
  dmEnabled            = false,
  dmLocked             = false,
  dmWinPos             = nil,
  dmMeterType          = 0,
  dmSessionType        = 1,
  dmShowInCombatOnly   = false,
  dmAutoReset          = "enter",
  dmBarHeight          = 24,
  dmBarSpacing         = 1,
  dmFontSize           = 14,
  dmUpdateInterval     = 0.5,
  dmBgAlpha            = 0.50,
  dmTitleAlpha         = 0.50,
  dmIconMode           = "spec",  -- "spec", "class", "none"
  dmValueFormat        = "both",  -- "total", "persec", "both"
  dmTextColor          = {r=1, g=1, b=1},
  dmTitleColor         = nil,  -- nil = use accent color
  dmFont               = "Friz Quadrata",
  dmTitleFontSize      = 14,
  dmFontShadow         = 2.0,
  dmTextOutline        = true,
  dmShowRealm          = true,
  dmIconsOnHover       = false,
  dmClassColors        = true,
  dmBarColor           = {r=0.5, g=0.5, b=0.5},
  dmBarBrightness      = 1.0,
  dmAlwaysShowSelf     = true,
  dmShowRank           = false,
  dmShowPercent        = false,
  dmBarBgTexture       = "Flat",
  dmAccentLine         = true,
  dmWindowBorder       = true,
  dmTitleBorder        = true,

  debugHistory         = {},
  debugWinPos          = nil,
  debugWinSize         = nil,
  -- Bags
  ltEnabled            = false,
  bagEnabled           = false,
  bagIconSize          = 37,
  bagSpacing           = 4,
  bagColumns           = 10,
  bagShowQuality       = true,
  bagShowCount         = true,
  bagShowIlvl          = true,
  bagShowJunk          = true,
  bagJunkDesaturate    = false,
  bagQuestIcon         = true,
  bagShowUpgrade       = true,
  bagNewItemGlow       = true,
  bagSortReverse       = false,
  bagSplitReagent      = false,
  bagSplitBags         = false,
  bagSplitSpacing      = 8,
  bagTransparent       = false,
  bagSlotBgAlpha       = 0.8,
  bagIlvlPos           = "BOTTOMLEFT",
  bagIlvlSize          = 10,
  bagCountPos          = "BOTTOMRIGHT",
  bagCountSize         = 10,
  bagWinPos            = nil,
  -- Gold Tracker
  gtEnabled            = false,
  gtWhisper            = true,
  gtWinPos             = nil,
  -- Mythic+
  mpEnabled            = false,
  mpTeleport           = false,
  mpWinPos3            = nil,
}

NS.DB = function(key)
  local v = LucidUIDB[key]
  if v == nil then return NS.DB_DEFAULTS[key] end
  return v
end

NS.DBSet = function(key, val)
  LucidUIDB[key] = val
end

-- ── Helpers ────────────────────────────────────────────────────────────────────
NS.GetClassColor = function(class)
  local colors = RAID_CLASS_COLORS
  if class and colors[class] then
    local c = colors[class]
    return CreateColor(c.r, c.g, c.b):GenerateHexColorMarkup()
  end
  return "|cffffffff"
end


-- ── Apply* functions ───────────────────────────────────────────────────────────
NS.ApplyTheme = function(themeKey)
  local t = NS.GetTheme(themeKey)
  if not NS.win then return end
  NS.win:SetBackdropColor(unpack(t.bg))
  NS.win:SetBackdropBorderColor(unpack(t.border))
  if NS.titleTex then
    NS.titleTex:SetColorTexture(t.titleBg[1], t.titleBg[2], t.titleBg[3], t.titleBg[4])
  end
  if NS.titleText then
    NS.titleText:SetTextColor(unpack(t.titleText))
    local tid = t.tilders or {59/255, 210/255, 237/255, 1}
    local tr = tid[1] or tid.r or 59/255
    local tg = tid[2] or tid.g or 210/255
    local tb = tid[3] or tid.b or 237/255
    local hex = string.format("%02x%02x%02x",
      math.floor(tr*255), math.floor(tg*255), math.floor(tb*255))
    local tname = (LucidUIDB and LucidUIDB.titleName ~= nil) and LucidUIDB.titleName or "Loot Tracker"
    local f, r = tname:match("^(%S+)%s*(.*)")
    if f then
      NS.titleText:SetText("|cff"..hex..f.."|r"..(r ~= "" and (" |cffffffff"..r.."|r") or ""))
    else
      NS.titleText:SetText("|cff"..hex..tname.."|r")
    end
  end
  -- Icon color: use chatIconColor if set, otherwise theme btnColor
  local ic = NS.DB("chatIconColor")
  local icr, icg, icb
  if ic and type(ic) == "table" and ic.r then
    icr, icg, icb = ic.r, ic.g, ic.b
  elseif t.btnColor then
    icr, icg, icb = t.btnColor[1], t.btnColor[2], t.btnColor[3]
  else
    icr, icg, icb = 1, 1, 1
  end
  for _, tex in ipairs(NS.btnIconTextures) do
    tex:SetVertexColor(icr, icg, icb, 1)
  end
  -- Clear button text color
  if NS.clearTxtRef then
    NS.clearTxtRef:SetTextColor(icr, icg, icb, 1)
  end
  -- Lock icon: cyan = unlocked, btnColor = locked
  if NS.lockTexRef then
    local CYAN = NS.CYAN
    if NS.win and NS.win.locked then
      local bc = t.btnColor or {0.8, 0.8, 0.8}
      NS.lockTexRef:SetVertexColor(bc[1], bc[2], bc[3], 0.9)
    else
      NS.lockTexRef:SetVertexColor(CYAN[1], CYAN[2], CYAN[3], 1.0)
    end
  end
  if NS.statsWin and NS.statsWin._ApplyTheme then NS.statsWin._ApplyTheme() end

  -- Update accent lines on all windows (use NS.CYAN directly, always most current)
  local ar, ag, ab = NS.CYAN[1], NS.CYAN[2], NS.CYAN[3]
  if NS.win and NS.win._accentLine then
    NS.win._accentLine:SetColorTexture(ar, ag, ab, 0.6)
  end
  if NS.statsWin and NS.statsWin._accentLine then
    NS.statsWin._accentLine:SetColorTexture(ar, ag, ab, 0.6)
  end
  if NS.rollWin and NS.rollWin._accentLine then
    NS.rollWin._accentLine:SetColorTexture(ar, ag, ab, 0.6)
  end
  if NS.LucidMeter and NS.LucidMeter.ApplyTheme then NS.LucidMeter.ApplyTheme() end
  -- Update Bags accent
  local bagFrame = _G["LucidUIBags"]
  if bagFrame then
    if bagFrame._accentLine then bagFrame._accentLine:SetColorTexture(ar, ag, ab, 1) end
    if bagFrame._title then bagFrame._title:SetTextColor(ar, ag, ab) end
    if bagFrame._bagBar and bagFrame._bagBar._accentLine then
      bagFrame._bagBar._accentLine:SetColorTexture(ar, ag, ab, 1)
    end
    if bagFrame._reagentWin then
      if bagFrame._reagentWin._accentLine then
        bagFrame._reagentWin._accentLine:SetColorTexture(ar, ag, ab, 1)
      end
      if bagFrame._reagentWin._title then
        bagFrame._reagentWin._title:SetTextColor(ar, ag, ab)
      end
    end
    if bagFrame._reagentInlineBorder and bagFrame._reagentInlineBorder._edges then
      for _, e in ipairs(bagFrame._reagentInlineBorder._edges) do
        e:SetColorTexture(ar, ag, ab, 0.7)
      end
    end
  end
  -- Update title text on stats + rolls windows (first word accent, rest white)
  if NS.statsWin and NS.statsWin._titleTxt or NS.rollWin and NS.rollWin._titleTxt then
    local hex2 = string.format("%02x%02x%02x", math.floor(ar*255), math.floor(ag*255), math.floor(ab*255))
    local L = LucidUIL or {}
    if NS.statsWin and NS.statsWin._titleTxt then
      local name = L["Session Stats"] or "Session Stats"
      local f,r = name:match("^(%S+)%s*(.*)")
      NS.statsWin._titleTxt:SetText("|cff"..hex2..(f or name).."|r"..(r and r ~= "" and (" |cffffffff"..r.."|r") or ""))
    end
    if NS.rollWin and NS.rollWin._titleTxt then
      local name = L["LOOT ROLLS"] or "LOOT ROLLS"
      local f,r = name:match("^(%S+)%s*(.*)")
      NS.rollWin._titleTxt:SetText("|cff"..hex2..(f or name).."|r"..(r and r ~= "" and (" |cffffffff"..r.."|r") or ""))
    end
  end

  -- Session History + Detail window live accent update
  if NS.sessionHistWin and NS.sessionHistWin._ApplyTheme then NS.sessionHistWin._ApplyTheme() end
  if NS.sessionDetailWin and NS.sessionDetailWin._ApplyTheme then NS.sessionDetailWin._ApplyTheme() end
  -- MythicPlus window live accent update
  if NS.MythicPlus and NS.MythicPlus._ApplyTheme then NS.MythicPlus._ApplyTheme() end
  -- GoldTracker window live accent update
  if NS.GoldTracker and NS.GoldTracker._ApplyTheme then NS.GoldTracker._ApplyTheme() end

  NS.ApplyAlpha()
  NS.ApplyTitleAlpha()
  if NS.ApplyChatTransparency then NS.ApplyChatTransparency() end
end

NS.ApplyAlpha = function()
  if not NS.win then return end
  local t  = NS.GetTheme(NS.DB("theme"))
  -- Use lootWinTransparency if set, otherwise fall back to legacy "alpha"
  local lootTr = NS.DB("lootWinTransparency")
  local tr
  if lootTr and lootTr > 0 then
    tr = lootTr
  else
    tr = (NS.DB("alpha") or 0) / 100
  end
  NS.win:SetBackdropColor(t.bg[1], t.bg[2], t.bg[3], math.max(0.02, t.bg[4] - tr))
  NS.win:SetBackdropBorderColor(t.border[1], t.border[2], t.border[3], math.max(0.05, 1.0 - tr * 0.8))
  -- Stats window transparency
  if NS.statsWin then
    local stTr = NS.DB("statsTransparency") or 0
    NS.statsWin:SetBackdropColor(t.bg[1], t.bg[2], t.bg[3], math.max(0.02, 0.97 - stTr))
  end
  -- Rolls window transparency
  if NS.rollWin then
    local rlTr = NS.DB("rollsTransparency") or 0
    NS.rollWin:SetBackdropColor(t.bg[1], t.bg[2], t.bg[3], math.max(0.02, 0.97 - rlTr))
  end
end

NS.ApplyTitleAlpha = function()
  if not NS.win then return end
  local ta = (NS.DB("titleAlpha") or 0) / 100
  local ba = math.max(0.05, 1.0 - ta)
  if NS.titleTex  then NS.titleTex:SetAlpha(ba)  end
  if NS.titleText then NS.titleText:SetAlpha(ba) end
  for _, tex in ipairs(NS.btnIconTextures) do tex:SetAlpha(ba) end
  if NS.lockTexRef then NS.lockTexRef:SetAlpha(ba) end
end

NS.ApplyFade = function()
  if not NS.smf then return end
  if NS.DB("enableFade") then
    NS.smf:SetFading(true)
    NS.smf:SetTimeVisible(NS.DB("fadeTime"))
    NS.smf:SetFadeDuration(3)
  else
    NS.smf:SetFading(false)
  end
end

-- ── Font / StatusBar discovery (cached) ────────────────────────────────────────
local _lsmFontList    = nil  -- full list for display in dropdowns
local _lsmFontMap     = nil  -- label → path for fast lookup
local _lsmBarList     = nil  -- full list for display in dropdowns
local _lsmBarMap      = nil  -- label → path for fast lookup

local function BuildFontCache()
  local list = {
    {label="Friz Quadrata", path="Fonts/FRIZQT__.TTF"},
    {label="Arial Narrow",  path="Fonts/ARIALN.TTF"},
    {label="Morpheus",      path="Fonts/MORPHEUS.TTF"},
    {label="Skurri",        path="Fonts/skurri.TTF"},
    {label="Damage",        path="Fonts/DAMAGE.TTF"},
  }
  local existing = {}
  for _, f in ipairs(list) do existing[f.label] = true end
  local LSM = LibStub and LibStub:GetLibrary("LibSharedMedia-3.0", true)
  if LSM then
    for _, name in ipairs(LSM:List("font")) do
      if not existing[name] then
        local path = LSM:Fetch("font", name, true)
        if path then
          list[#list + 1] = {label=name, path=path}
          existing[name] = true
        end
      end
    end
    table.sort(list, function(a, b) return a.label:lower() < b.label:lower() end)
  end
  local map = {}
  for _, f in ipairs(list) do map[f.label] = f.path end
  _lsmFontList = list
  _lsmFontMap  = map
end

local function BuildBarCache()
  local list = {
    {label="Flat",            path="Interface/Buttons/WHITE8X8"},
    {label="Blizzard",        path="Interface/TargetingFrame/UI-StatusBar"},
    {label="Blizzard Raid",   path="Interface/RaidFrame/Raid-Bar-Hp-Fill"},
    {label="Blizzard Skills", path="Interface/PaperDollInfoFrame/UI-Character-Skills-Bar"},
  }
  local existing = {}
  for _, f in ipairs(list) do existing[f.label] = true end
  local LSM = LibStub and LibStub:GetLibrary("LibSharedMedia-3.0", true)
  if LSM then
    for _, name in ipairs(LSM:List("statusbar")) do
      if not existing[name] then
        local path = LSM:Fetch("statusbar", name, true)
        if path then
          list[#list + 1] = {label=name, path=path}
          existing[name] = true
        end
      end
    end
    table.sort(list, function(a, b) return a.label:lower() < b.label:lower() end)
  end
  local map = {}
  for _, f in ipairs(list) do map[f.label] = f.path end
  _lsmBarList = list
  _lsmBarMap  = map
end

-- Invalidate caches when LSM registers new media (rare, but possible at login)
NS.InvalidateLSMCache = function()
  _lsmFontList = nil; _lsmFontMap = nil
  _lsmBarList  = nil; _lsmBarMap  = nil
end

-- Re-apply all fonts across all modules (called after LSM cache invalidation)
NS.ReapplyAllFonts = function()
  NS.InvalidateLSMCache()

  -- Chat font (uses chatFont key, falls back to font)
  local chatFontPath = NS.GetFontPath(NS.DB("chatFont") or NS.DB("font"))
  local chatFontSize = NS.DB("chatFontSize") or 14
  local chatFontOutline = NS.DB("chatFontOutline") or ""
  local chatFontShadow = NS.DB("chatFontShadow")
  -- Chat message display
  if NS.chatDisplay and NS.chatDisplay.SetFont then
    NS.chatDisplay:SetFont(chatFontPath, chatFontSize, chatFontOutline)
    if NS.chatDisplay.SetShadowOffset then
      NS.chatDisplay:SetShadowOffset(chatFontShadow and 1 or 0, chatFontShadow and -1 or 0)
    end
  end
  -- Chat SMF (scrolling message frame)
  if NS.smf then
    NS.smf:SetFont(chatFontPath, chatFontSize, chatFontOutline)
  end

  -- LucidMeter: apply font to all bars immediately
  if NS.LucidMeter and NS.LucidMeter.windows then
    local dmFontPath = NS.GetFontPath(NS.DB("dmFont"))
    local dmFontSize = NS.DB("dmFontSize") or 11
    local dmFontFlags = NS.DB("dmTextOutline") and "OUTLINE" or ""
    for _, w in ipairs(NS.LucidMeter.windows) do
      if w.titleText then
        w.titleText:SetFont(dmFontPath, NS.DB("dmTitleFontSize") or 10, dmFontFlags)
      end
      for _, bar in ipairs(w.bars or {}) do
        bar._lastConfigStamp = nil
        if bar._name then bar._name:SetFont(dmFontPath, dmFontSize, dmFontFlags) end
        if bar._value then bar._value:SetFont(dmFontPath, dmFontSize, dmFontFlags) end
        if bar._pct then bar._pct:SetFont(dmFontPath, dmFontSize, dmFontFlags) end
        if bar._rankFS then bar._rankFS:SetFont(dmFontPath, dmFontSize, dmFontFlags) end
      end
      if w._selfBar then
        w._selfBar._setupDone = false
        if w._selfBar._name then w._selfBar._name:SetFont(dmFontPath, dmFontSize, dmFontFlags) end
        if w._selfBar._value then w._selfBar._value:SetFont(dmFontPath, dmFontSize, dmFontFlags) end
      end
      -- Total bar
      if w._totalBarLabel then w._totalBarLabel:SetFont(dmFontPath, dmFontSize, dmFontFlags) end
      if w._totalBarValue then w._totalBarValue:SetFont(dmFontPath, dmFontSize, dmFontFlags) end
    end
  end

  -- LootTracker window title
  if NS.win and NS.titleText then
    local lootFont = NS.GetFontPath(NS.DB("font"))
    local lootSize = NS.DB("fontSize") or 11
    local lootFlags = NS.DB("fontOutline") or ""
    NS.titleText:SetFont(lootFont, lootSize, lootFlags)
  end
end

-- Hook LSM callback to pick up fonts registered after our cache was built
C_Timer.After(0, function()
  local LSM = LibStub and LibStub:GetLibrary("LibSharedMedia-3.0", true)
  if LSM and LSM.RegisterCallback then
    LSM:RegisterCallback("LibSharedMedia_Registered", function(_, mediatype)
      if mediatype == "font" or mediatype == "statusbar" then
        NS.ReapplyAllFonts()
      end
    end)
  end
end)

-- Re-apply fonts after PLAYER_ENTERING_WORLD (all addons have loaded by then)
local fontFixFrame = CreateFrame("Frame")
fontFixFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
fontFixFrame:SetScript("OnEvent", function(self)
  self:UnregisterEvent("PLAYER_ENTERING_WORLD")
  C_Timer.After(0.1, function() NS.ReapplyAllFonts() end)
end)

-- ── CooldownViewer-Konflikt-Schutz ──────────────────────────────────────────────
-- Addons die dieselben CooldownViewer-Frames verwalten (reparenten + SetPoint-Hooks)
-- kollidieren mit LucidUIs Cooldowns/BuffBar/CastBar/EditMode-Modulen.
-- If a conflicting CDM addon is loaded, disable LucidCDM modules
-- konkurrierenden LucidUI-Module um Crashes zu verhindern.
local CDM_CONFLICTING_ADDONS = {
  "Ayije_CDM",
}

local function DisableCDMModules()
  if NS.Cooldowns and NS.Cooldowns.Disable then NS.Cooldowns.Disable() end
  if NS.BuffBar   and NS.BuffBar.Disable   then NS.BuffBar:Disable()   end
  if NS.CastBar   and NS.CastBar.Disable   then NS.CastBar.Disable()   end
  -- Resources hat keinen Viewer-Conflict, bleibt aktiv
end

-- Safe addon-loaded check: 12.x may return a secret boolean here which would
-- taint any branch that consumes it directly. Wrap in pcall and fall back to
-- the global-name heuristic like InstallWizard does.
local function SafeIsAddonLoaded(name)
  if C_AddOns and C_AddOns.IsAddOnLoaded then
    local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, name)
    if ok and loaded then return true end
  end
  if _G[name] then return true end
  return false
end

local function HasConflictingAddon()
  for _, name in ipairs(CDM_CONFLICTING_ADDONS) do
    if SafeIsAddonLoaded(name) then return true, name end
  end
  return false
end

-- Check on login (Ayije may already be loaded)
local conflictCheckFrame = CreateFrame("Frame")
conflictCheckFrame:RegisterEvent("PLAYER_LOGIN")
conflictCheckFrame:RegisterEvent("ADDON_LOADED")
conflictCheckFrame:SetScript("OnEvent", function(self, event, addonName)
  if event == "PLAYER_LOGIN" then
    local found, name = HasConflictingAddon()
    if found then
      DisableCDMModules()
      if LucidUIDB then LucidUIDB["cdm_enabled"] = false end
      print("|cffff8800[LucidUI]|r " .. name .. " detected — LucidCDM disabled to avoid conflicts.")
    end
  elseif event == "ADDON_LOADED" then
    -- Ayije lädt nach LucidUI
    for _, name in ipairs(CDM_CONFLICTING_ADDONS) do
      if addonName == name then
        DisableCDMModules()
        if LucidUIDB then LucidUIDB["cdm_enabled"] = false end
        print("|cffff8800[LucidUI]|r " .. name .. " loaded — LucidCDM disabled to avoid conflicts.")
        break
      end
    end
  end
end)

NS.GetLSMFonts = function()
  if not _lsmFontList then BuildFontCache() end
  return _lsmFontList
end

NS.GetLSMStatusBars = function()
  if not _lsmBarList then BuildBarCache() end
  return _lsmBarList
end

NS.GetBarTexturePath = function(key)
  if not key or key == "Flat" then return "Interface/Buttons/WHITE8X8" end
  if not _lsmBarMap then BuildBarCache() end
  return _lsmBarMap[key] or "Interface/Buttons/WHITE8X8"
end

NS.GetFontPath = function(key)
  if not key or key == "default" then return NS.FONT end
  if not _lsmFontMap then BuildFontCache() end
  return _lsmFontMap[key] or NS.FONT
end

NS.ApplyFontSize = function()
  if not NS.smf then return end
  NS.smf:SetFont(NS.GetFontPath(NS.DB("font")), NS.DB("fontSize"), NS.DB("fontOutline") or "")
end

NS.ApplySpacing = function()
  if not NS.smf then return end
  NS.smf:SetSpacing(NS.DB("messageSpacing"))
end