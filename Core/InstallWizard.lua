-- LucidUI Core/InstallWizard.lua
-- First-install setup wizard (NaowhUI-style per-addon steps with sidebar)

local NS = LucidUINS

-- ── Resolution presets (LucidUI internal sizes) ────────────────────────
local PRESETS = {
  ["1440p"] = {
    -- CDM
    cdv_essWidth = 56, cdv_essHeight = 52, cdv_essSpacing = 2, cdv_essPerRow = 9,
    cdv_utilWidth = 44, cdv_utilHeight = 40, cdv_utilSpacing = 2, cdv_utilPerRow = 8,
    cdv_fontSize = 16,
    -- CastBar
    cb_width = 350, cb_height = 16, cb_fontSize = 14, cb_textYOffset = 5,
    cb_bgTexture = "Melli",
    -- Resources
    res_width = 350, res_height = 14, res_secHeight = 14, res_pipSpacing = 1,
    res_fontSize = 16, res_bgTexture = "Melli",
    -- BuffBar
    bb_buffIconSize = 40, bb_buffIconSpacing = 2, bb_buffIconsPerRow = 12,
    bb_buffBarWidth = 200, bb_buffBarHeight = 20, bb_buffBarSpacing = 2,
    bb_buffBarFontSize = 14,
    bb_buffBarTexture = "Flat", bb_buffBarBgTexture = "Melli",
    -- Bags
    bagIconSize = 38, bagSpacing = 4, bagColumns = 15,
    bagCountSize = 12, bagCountPos = "BOTTOMRIGHT",
    bagSlotBgAlpha = 0.8, bagAutoAH = true,
    -- Chat
    chatFontSize = 16, fontSize = 14, fontOutline = "",
    -- LucidMeter
    dmFontSize = 14, dmBarHeight = 26,
  },
  ["1080p"] = {
    -- CDM
    cdv_essWidth = 46, cdv_essHeight = 42, cdv_essSpacing = 2, cdv_essPerRow = 9,
    cdv_utilWidth = 36, cdv_utilHeight = 32, cdv_utilSpacing = 2, cdv_utilPerRow = 8,
    cdv_fontSize = 14,
    -- CastBar
    cb_width = 280, cb_height = 14, cb_fontSize = 12, cb_textYOffset = 4,
    cb_bgTexture = "Melli",
    -- Resources
    res_width = 280, res_height = 12, res_secHeight = 12, res_pipSpacing = 1,
    res_fontSize = 14, res_bgTexture = "Melli",
    -- BuffBar
    bb_buffIconSize = 33, bb_buffIconSpacing = 2, bb_buffIconsPerRow = 12,
    bb_buffBarWidth = 160, bb_buffBarHeight = 16, bb_buffBarSpacing = 2,
    bb_buffBarFontSize = 12,
    bb_buffBarTexture = "Flat", bb_buffBarBgTexture = "Melli",
    -- Bags
    bagIconSize = 32, bagSpacing = 3, bagColumns = 15,
    bagCountSize = 10, bagCountPos = "BOTTOMRIGHT",
    bagSlotBgAlpha = 0.8, bagAutoAH = true,
    -- Chat
    chatFontSize = 14, fontSize = 12, fontOutline = "",
    -- LucidMeter
    dmFontSize = 12, dmBarHeight = 22,
  },
}

-- ── Module definitions ─────────────────────────────────────────────────
local MODULES = {
  {key = "cdm_enabled",  label = "LucidCDM",    desc = "Cooldowns, Cast Bar, Resources & Buffs"},
  {key = "chatEnabled",  label = "LucidChat",   desc = "Custom chat window"},
  {key = "ltEnabled",    label = "Loot Tracker", desc = "Loot tracking & session stats"},
  {key = "bagEnabled",   label = "LucidBags",   desc = "Custom bag frames"},
  {key = "dmEnabled",    label = "LucidMeter",  desc = "Damage / healing meter"},
  {key = "gtEnabled",    label = "Gold Tracker", desc = "Gold tracking across characters"},
  {key = "mpEnabled",    label = "Mythic+",     desc = "Mythic+ run tracker"},
}

-- ── Addon profiles (steps with resolution choice) ─────────────────────
-- has1080p: true if we have a 1080p variant string
local ADDON_STEPS = {
  {key = "ElvUI",            label = "ElvUI",             check = "ElvUI",             has1080p = true},
  {key = "Ayije_CDM",        label = "Ayije CDM",         check = "Ayije_CDM",         has1080p = true},
  {key = "Plater",           label = "Plater",            check = "Plater",            has1080p = true},
  {key = "BigWigs",          label = "BigWigs",           check = "BigWigs",           has1080p = true},
  {key = "Details",          label = "Details",            check = "Details",           has1080p = true},
  {key = "NaowhQOL",         label = "NaowhQOL",          check = "NaowhQOL",          has1080p = true},
  {key = "WarpDeplete",      label = "WarpDeplete",        check = "WarpDeplete",       has1080p = true},
  {key = "BlizziInterrupts", label = "Blizzi Interrupts",  check = "BliZzi_Interrupts", has1080p = false},
}

-- ── Style ──────────────────────────────────────────────────────────────
local SBD = NS.BACKDROP
local FONT = NS.FONT
local W, H = 680, 480
local SIDEBAR_W = 150

-- ── State ──────────────────────────────────────────────────────────────
local wizard = nil
local currentStep = 1
local selectedRes = "1440p"
local moduleStates = {}
for _, m in ipairs(MODULES) do moduleStates[m.key] = false end
local applyClassLayout = false
local luiProfileApplied = false

-- Per-addon: nil = skip, "1440p" or "1080p" = apply with resolution
local addonChoices = {}

-- ── Build ordered step list dynamically ────────────────────────────────
local steps = {}  -- rebuilt each time wizard opens

local function IsAddonLoaded(name)
  -- Try C_AddOns.IsAddOnLoaded (may return secret boolean in Midnight)
  if C_AddOns and C_AddOns.IsAddOnLoaded then
    local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, name)
    if ok and loaded then return true end
  end
  -- Fallback: check if addon's global table or key addon object exists
  -- This works reliably regardless of API quirks
  if _G[name] then return true end
  -- Some addons use different global names
  local globalChecks = {
    ElvUI = _G.ElvUI,
    Ayije_CDM = _G.Ayije_CDM,
    Plater = _G.Plater,
    BigWigs = _G.BigWigs,
    Details = _G.Details,
    NaowhQOL = _G.NaowhQOL,
    WarpDeplete = _G.WarpDeplete,
    BliZzi_Interrupts = _G.BliZzi_Interrupts or _G.BIT,
  }
  if globalChecks[name] then return true end
  return false
end

local function RebuildSteps()
  steps = {}
  steps[#steps+1] = {id = "welcome",     label = "Welcome"}
  for _, a in ipairs(ADDON_STEPS) do
    local installed = IsAddonLoaded(a.check)
    local hasData = NS.Profiles and NS.Profiles[a.key]
    steps[#steps+1] = {id = "addon", label = a.label, addon = a, available = installed and hasData}
  end
  steps[#steps+1] = {id = "modules",     label = "LucidUI"}
  steps[#steps+1] = {id = "classLayout", label = "Class Layout"}
  steps[#steps+1] = {id = "complete",    label = "Complete"}
end

-- ── Helpers ────────────────────────────────────────────────────────────
local function MakeButton(parent, text, w, h)
  local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
  btn:SetSize(w or 120, h or 28)
  btn:SetBackdrop(SBD)
  btn:SetBackdropColor(0.08, 0.08, 0.12, 1)
  btn:SetBackdropBorderColor(0.25, 0.25, 0.35, 1)
  local fs = btn:CreateFontString(nil, "OVERLAY")
  fs:SetFont(FONT, 11, ""); fs:SetPoint("CENTER"); fs:SetTextColor(0.9, 0.9, 0.9)
  fs:SetText(text); btn._fs = fs
  btn:SetScript("OnEnter", function()
    local r, g, b = NS.ChatGetAccentRGB()
    btn:SetBackdropBorderColor(r, g, b, 0.8); fs:SetTextColor(r, g, b)
  end)
  btn:SetScript("OnLeave", function()
    btn:SetBackdropBorderColor(0.25, 0.25, 0.35, 1); fs:SetTextColor(0.9, 0.9, 0.9)
  end)
  return btn
end

local function MakeAccentButton(parent, text, w, h)
  local btn = MakeButton(parent, text, w, h)
  local r, g, b = NS.ChatGetAccentRGB()
  btn:SetBackdropBorderColor(r, g, b, 0.6); btn._fs:SetTextColor(r, g, b)
  btn:SetScript("OnLeave", function()
    btn:SetBackdropBorderColor(r, g, b, 0.6); btn._fs:SetTextColor(r, g, b)
  end)
  return btn
end

-- ── Build wizard frame (Settings-menu style) ──────────────────────────
local HEADER_H = 42
local function CreateWizard()
  if wizard then return wizard end
  local ar, ag, ab = NS.ChatGetAccentRGB()

  local f = CreateFrame("Frame", "LucidUIInstallWizard", UIParent, "BackdropTemplate")
  f:SetSize(W, H); f:SetPoint("CENTER")
  f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetFrameLevel(100)
  f:SetMovable(true); f:SetClampedToScreen(true); f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetBackdrop(SBD)
  f:SetBackdropColor(0.025, 0.025, 0.038, 0.97)
  f:SetBackdropBorderColor(ar, ag, ab, 0.38)

  -- Left accent bar (like settings)
  local leftBar = f:CreateTexture(nil, "OVERLAY", nil, 5)
  leftBar:SetPoint("TOPLEFT", 1, -1); leftBar:SetPoint("BOTTOMLEFT", 1, 1)
  leftBar:SetWidth(3); leftBar:SetColorTexture(ar, ag, ab, 1)

  -- Header line
  local hLine = f:CreateTexture(nil, "OVERLAY", nil, 5)
  hLine:SetPoint("TOPLEFT", 1, -HEADER_H); hLine:SetPoint("TOPRIGHT", -1, -HEADER_H)
  hLine:SetHeight(1); hLine:SetColorTexture(ar, ag, ab, 0.55)

  -- Sidebar divider
  local sbDiv = f:CreateTexture(nil, "OVERLAY", nil, 4)
  sbDiv:SetWidth(1); sbDiv:SetPoint("TOPLEFT", SIDEBAR_W + 4, -(HEADER_H + 2))
  sbDiv:SetPoint("BOTTOMLEFT", SIDEBAR_W + 4, 1)
  sbDiv:SetColorTexture(ar, ag, ab, 0.30)

  -- Header background
  local headerBg = f:CreateTexture(nil, "BACKGROUND", nil, 2)
  headerBg:SetPoint("TOPLEFT", 1, -1); headerBg:SetPoint("TOPRIGHT", -1, -1)
  headerBg:SetHeight(HEADER_H); headerBg:SetColorTexture(0.010, 0.010, 0.020, 1)

  -- Title (accent colored, like settings)
  local thex = string.format("|cff%02x%02x%02x", ar*255, ag*255, ab*255)
  local title = f:CreateFontString(nil, "OVERLAY")
  title:SetFont(FONT, 14, "OUTLINE"); title:SetPoint("TOPLEFT", 14, -10)
  title:SetText(thex .. "LUCID|r|cffffffffUI|r")
  f._title = title

  -- Center title
  local centerTitle = f:CreateFontString(nil, "OVERLAY")
  centerTitle:SetFont(FONT, 14, "OUTLINE"); centerTitle:SetPoint("CENTER", f, "TOP", 0, -HEADER_H / 2)
  centerTitle:SetTextColor(1, 1, 1); centerTitle:SetText("Setup")

  -- Subtitle (step name, next to center title)
  local subtitle = f:CreateFontString(nil, "OVERLAY")
  subtitle:SetFont(FONT, 10, ""); subtitle:SetPoint("LEFT", centerTitle, "RIGHT", 8, 0)
  subtitle:SetTextColor(0.44, 0.44, 0.52)
  f._subtitle = subtitle

  -- Sidebar buttons (clickable)
  f._sidebarBtns = {}

  -- Content area
  f.content = CreateFrame("Frame", nil, f)
  f.content:SetPoint("TOPLEFT", SIDEBAR_W + 6, -(HEADER_H + 4))
  f.content:SetPoint("BOTTOMRIGHT", -4, 58)

  -- Bottom bar
  local botLine = f:CreateTexture(nil, "OVERLAY", nil, 4)
  botLine:SetHeight(1); botLine:SetPoint("BOTTOMLEFT", SIDEBAR_W + 4, 56)
  botLine:SetPoint("BOTTOMRIGHT", -1, 56)
  botLine:SetColorTexture(ar, ag, ab, 0.20)

  -- Progress bar (above nav buttons)
  f._progressBg = CreateFrame("Frame", nil, f, "BackdropTemplate")
  f._progressBg:SetHeight(14); f._progressBg:SetPoint("BOTTOMLEFT", SIDEBAR_W + 6, 38)
  f._progressBg:SetPoint("BOTTOMRIGHT", -6, 38)
  f._progressBg:SetBackdrop(SBD); f._progressBg:SetBackdropColor(0.02, 0.02, 0.03, 1)
  f._progressBg:SetBackdropBorderColor(ar, ag, ab, 0.20)

  f._progressBar = f._progressBg:CreateTexture(nil, "ARTWORK")
  f._progressBar:SetPoint("TOPLEFT", 1, -1); f._progressBar:SetPoint("BOTTOMLEFT", 1, 1)
  f._progressBar:SetColorTexture(ar, ag, ab, 0.5)

  f._progressText = f._progressBg:CreateFontString(nil, "OVERLAY")
  f._progressText:SetFont(FONT, 9, ""); f._progressText:SetPoint("CENTER")
  f._progressText:SetTextColor(0.55, 0.55, 0.65)

  -- Navigation buttons (match settings button style)
  local function NavBtn(label, isAccent)
    local btn = CreateFrame("Button", nil, f, "BackdropTemplate")
    btn:SetHeight(22); btn:SetBackdrop(SBD)
    btn:SetBackdropColor(0.05, 0.05, 0.09, 1)
    btn:SetBackdropBorderColor(0.12, 0.12, 0.20, 1)
    local fs = btn:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, 10, ""); fs:SetPoint("CENTER"); fs:SetTextColor(0.44, 0.44, 0.52)
    fs:SetText(label); btn._fs = fs
    btn:SetWidth(fs:GetStringWidth() + 30)
    if isAccent then
      btn:SetBackdropBorderColor(ar, ag, ab, 0.5); fs:SetTextColor(ar, ag, ab)
    end
    btn:SetScript("OnEnter", function()
      btn:SetBackdropBorderColor(ar, ag, ab, 0.75); fs:SetTextColor(ar, ag, ab)
    end)
    btn:SetScript("OnLeave", function()
      if isAccent then
        btn:SetBackdropBorderColor(ar, ag, ab, 0.5); fs:SetTextColor(ar, ag, ab)
      else
        btn:SetBackdropBorderColor(0.12, 0.12, 0.20, 1); fs:SetTextColor(0.44, 0.44, 0.52)
      end
    end)
    return btn
  end

  f.prevBtn = NavBtn("Previous")
  f.prevBtn:SetPoint("BOTTOMLEFT", SIDEBAR_W + 6, 9)
  f.prevBtn:SetScript("OnClick", function()
    if currentStep > 1 then currentStep = currentStep - 1; NS._WizardShowStep() end
  end)

  f.nextBtn = NavBtn("Continue", true)
  f.nextBtn:SetPoint("BOTTOMRIGHT", -6, 9)
  f.nextBtn:SetScript("OnClick", function()
    if currentStep < #steps then currentStep = currentStep + 1; NS._WizardShowStep()
    elseif currentStep == #steps then NS._WizardFinish() end
  end)

  -- Close X (red, like settings)
  local closeBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
  closeBtn:SetSize(22, 22); closeBtn:SetPoint("TOPRIGHT", -4, -10)
  closeBtn:SetBackdrop(SBD); closeBtn:SetBackdropColor(0.09, 0.02, 0.02, 1)
  closeBtn:SetBackdropBorderColor(0.34, 0.09, 0.09, 1)
  local cX = closeBtn:CreateFontString(nil, "OVERLAY")
  cX:SetFont(FONT, 11, ""); cX:SetPoint("CENTER"); cX:SetTextColor(0.60, 0.18, 0.18); cX:SetText("X")
  closeBtn:SetScript("OnClick", function()
    f:Hide()
    if LucidUIDB then LucidUIDB._installComplete = true end
  end)
  closeBtn:SetScript("OnEnter", function()
    closeBtn:SetBackdropBorderColor(0.60, 0.12, 0.12, 1); cX:SetTextColor(1, 0.3, 0.3)
  end)
  closeBtn:SetScript("OnLeave", function()
    closeBtn:SetBackdropBorderColor(0.34, 0.09, 0.09, 1); cX:SetTextColor(0.60, 0.18, 0.18)
  end)

  wizard = f
  return f
end

-- ── Update sidebar (settings-menu tab style) ───────────────────────────
local TAB_H = 30
local function UpdateSidebar()
  local ar, ag, ab = NS.ChatGetAccentRGB()

  for _, btn in ipairs(wizard._sidebarBtns) do btn:Hide() end

  for i, step in ipairs(steps) do
    local btn = wizard._sidebarBtns[i]
    if not btn then
      btn = CreateFrame("Button", nil, wizard)
      btn:SetHeight(TAB_H)

      -- Selection background
      local selBg = btn:CreateTexture(nil, "BACKGROUND", nil, 2)
      selBg:SetAllPoints(); selBg:SetColorTexture(ar, ag, ab, 0.06); selBg:Hide()
      btn._selBg = selBg

      -- Right accent line (like settings tabs)
      local selLineR = btn:CreateTexture(nil, "OVERLAY", nil, 5)
      selLineR:SetWidth(3); selLineR:SetPoint("TOPRIGHT", 0, -4)
      selLineR:SetPoint("BOTTOMRIGHT", 0, 4)
      selLineR:SetColorTexture(ar, ag, ab, 1); selLineR:Hide()
      btn._selLineR = selLineR

      -- Label (bigger font, left-aligned with padding)
      local lbl = btn:CreateFontString(nil, "OVERLAY")
      lbl:SetFont(FONT, 11, ""); lbl:SetPoint("LEFT", 14, 0)
      lbl:SetJustifyH("LEFT")
      btn._label = lbl

      -- Status indicator (right side)
      local status = btn:CreateFontString(nil, "OVERLAY")
      status:SetFont(FONT, 9, ""); status:SetPoint("RIGHT", btn, "RIGHT", -10, 0)
      btn._status = status

      wizard._sidebarBtns[i] = btn
    end

    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", wizard, "TOPLEFT", 1, -(HEADER_H + 2 + (i - 1) * TAB_H))
    btn:SetPoint("RIGHT", wizard, "LEFT", SIDEBAR_W + 3, 0)
    btn._label:SetText(step.label)

    local unavailable = step.id == "addon" and not step.available
    local isCurrent = (i == currentStep)

    btn._selLineR:SetShown(isCurrent)
    btn._selBg:SetShown(isCurrent)

    if unavailable then
      btn._label:SetTextColor(0.25, 0.25, 0.30)
      btn._status:SetText("|cff444444--|r")
    elseif isCurrent then
      btn._label:SetTextColor(ar, ag, ab)
      btn._status:SetText("")
    elseif step.id == "addon" and step.addon and addonChoices[step.addon.key] then
      btn._label:SetTextColor(0.3, 0.75, 0.3)
      btn._status:SetText("|cff4dcc4d" .. (addonChoices[step.addon.key] or "") .. "|r")
    elseif step.id == "addon" and step.addon and i < currentStep then
      btn._label:SetTextColor(0.5, 0.3, 0.3)
      btn._status:SetText("|cffaa5555skip|r")
    elseif step.id == "modules" and i < currentStep then
      if luiProfileApplied then
        btn._label:SetTextColor(0.3, 0.75, 0.3); btn._status:SetText("|cff4dcc4d" .. selectedRes .. "|r")
      else
        btn._label:SetTextColor(0.5, 0.3, 0.3); btn._status:SetText("|cffaa5555skip|r")
      end
    elseif step.id == "classLayout" and i < currentStep then
      if applyClassLayout then
        btn._label:SetTextColor(0.3, 0.75, 0.3); btn._status:SetText("")
      else
        btn._label:SetTextColor(0.5, 0.3, 0.3); btn._status:SetText("|cffaa5555skip|r")
      end
    elseif i < currentStep then
      btn._label:SetTextColor(0.3, 0.75, 0.3)
      btn._status:SetText("")
    else
      btn._label:SetTextColor(0.36, 0.36, 0.46)
      btn._status:SetText("")
    end

    -- Click to jump
    local stepIdx = i
    btn:SetScript("OnClick", function()
      currentStep = stepIdx; NS._WizardShowStep()
    end)

    -- Store default color for OnLeave restore
    local defR, defG, defB = btn._label:GetTextColor()
    btn._defColor = {defR, defG, defB}

    btn:SetScript("OnEnter", function()
      if stepIdx ~= currentStep then
        btn._selBg:SetColorTexture(ar, ag, ab, 0.04); btn._selBg:Show()
        btn._label:SetTextColor(ar, ag, ab)
      end
    end)
    btn:SetScript("OnLeave", function()
      if stepIdx ~= currentStep then
        btn._selBg:Hide()
        local dc = btn._defColor
        if dc then btn._label:SetTextColor(dc[1], dc[2], dc[3]) end
      end
    end)

    btn:Show()
  end
end

-- ── Clear content ──────────────────────────────────────────────────────
local contentFrames = {}
local function GetContentFrame(id)
  if contentFrames[id] then return contentFrames[id] end
  local f = CreateFrame("Frame", nil, wizard.content)
  f:SetAllPoints(wizard.content); f:Hide()
  contentFrames[id] = f
  return f
end

local function ShowContent(id)
  for _, cf in pairs(contentFrames) do cf:Hide() end
  GetContentFrame(id):Show()
end

-- ── Step: Welcome ──────────────────────────────────────────────────────
local function ShowWelcome()
  ShowContent("welcome")
  local c = GetContentFrame("welcome")
  if c._built then return end; c._built = true

  local ar, ag, ab = NS.ChatGetAccentRGB()
  local hex = NS.RGBToHex(ar, ag, ab)

  local logo = c:CreateTexture(nil, "ARTWORK")
  logo:SetSize(64, 64); logo:SetPoint("TOP", c, "TOP", 0, -20)
  logo:SetTexture("Interface/AddOns/LucidUI/Assets/Logo.png")

  local welcome = c:CreateFontString(nil, "OVERLAY")
  welcome:SetFont(FONT, 13, ""); welcome:SetWidth(W - SIDEBAR_W - 60)
  welcome:SetJustifyH("CENTER"); welcome:SetPoint("TOP", logo, "BOTTOM", 0, -20)
  welcome:SetTextColor(0.75, 0.75, 0.8)
  welcome:SetText(
    "Welcome to |cff" .. hex .. "LucidUI|r\n\n" ..
    "This wizard will guide you through setting up\n" ..
    "your UI modules and addon profiles.\n\n" ..
    "Click |cff" .. hex .. "Continue|r to begin."
  )
end

-- ── Step: LucidUI Profile Import ──────────────────────────────────────

-- Deserialize a LUI_EXPORT value string (reused from Settings.lua import logic)
local function Deserialize(s)
  if s == "true" then return true end
  if s == "false" then return false end
  if s == "nil" then return nil end
  if tonumber(s) then return tonumber(s) end
  if s:match('^".*"$') then return s:sub(2, -2):gsub('\\"', '"') end
  if s:match("^{.*}$") then
    local result = {}
    local inner = s:sub(2, -2)
    local i, arrIdx = 1, 1
    while i <= #inner do
      local _, eSkip = inner:find("^[%s,]*", i); i = (eSkip or i - 1) + 1
      if i > #inner then break end
      local k, rest = inner:match("^([%w_]+)=(.+)", i)
      if k then
        local depth = 0
        local valStr = rest
        for ci = 1, #rest do
          local ch = rest:sub(ci, ci)
          if ch == "{" then depth = depth + 1 elseif ch == "}" then depth = depth - 1
          elseif ch == "," and depth == 0 then valStr = rest:sub(1, ci - 1); i = i + #k + 1 + ci; break end
          if ci == #rest then i = i + #k + 1 + #rest + 1 end
        end
        local nk = tonumber(k); if nk then result[nk] = Deserialize(strtrim(valStr)) else result[k] = Deserialize(strtrim(valStr)) end
      else
        local depth2 = 0
        for ci = i, #inner do
          local ch = inner:sub(ci, ci)
          if ch == "{" then depth2 = depth2 + 1 elseif ch == "}" then depth2 = depth2 - 1
          elseif ch == "," and depth2 == 0 then result[arrIdx] = Deserialize(strtrim(inner:sub(i, ci - 1))); arrIdx = arrIdx + 1; i = ci + 1; break end
          if ci == #inner then result[arrIdx] = Deserialize(strtrim(inner:sub(i, ci))); arrIdx = arrIdx + 1; i = ci + 1 end
        end
      end
    end
    return result
  end
  return s
end

local function ParseExportString(raw)
  local data = {}
  local skipKeys = {_profiles=true, _activeProfile=true}
  for line in raw:gmatch("[^\n]+") do
    local k, v = line:match("^([^=]+)=(.+)$")
    if k and v and not k:match("^LUI_EXPORT") and not skipKeys[k] then
      data[k] = Deserialize(v)
    end
  end
  return data
end

local function ApplyLucidUIProfile(resolution)
  if not LucidUIDB then LucidUIDB = {} end
  local P = NS.Profiles and NS.Profiles.LucidUI
  if not P then print("|cff3BD2ED[LucidUI]|r Recommended profile data not found"); return end

  -- Parse the export string (supports both !LUI1! encoded and legacy LUI_EXPORT: format)
  local encoded = type(P) == "table" and P[1] or P
  if not encoded or type(encoded) ~= "string" then print("|cff3BD2ED[LucidUI]|r Invalid profile string"); return end
  local raw = NS.DecodeProfileString(encoded)
  if not raw then print("|cff3BD2ED[LucidUI]|r Failed to decode profile string"); return end
  local baseData = ParseExportString(raw)

  -- Create both resolution profiles from the base data
  local skip = {_profiles=true, _activeProfile=true, _defaultSnapshot=true, history=true, chatHistory=true, debugHistory=true, _sessionData=true, _rollData=true, _rollEncounter=true}
  LucidUIDB._profiles = LucidUIDB._profiles or {}

  local hasAyije = IsAddonLoaded("Ayije_CDM")
  local hasDetails = IsAddonLoaded("Details")

  for _, res in ipairs({"1440p", "1080p"}) do
    local profName = "R-LucidUI" .. (res == "1440p" and "1440" or "1080")
    local snapshot = {}
    -- Start with parsed base data
    for k, v in pairs(baseData) do snapshot[k] = v end
    -- Override with resolution preset
    local preset = PRESETS[res]
    if preset then for k, v in pairs(preset) do snapshot[k] = v end end
    snapshot._resolution = res
    -- Enable all modules (disable conflicting ones)
    for _, m in ipairs(MODULES) do
      local enable = true
      if m.key == "cdm_enabled" and hasAyije then enable = false end
      if m.key == "dmEnabled" and hasDetails then enable = false end
      snapshot[m.key] = enable
    end
    snapshot["lootOwnWindow"] = true
    LucidUIDB._profiles[profName] = snapshot
  end

  -- Activate the selected resolution profile
  local profileName = "R-LucidUI" .. (resolution == "1440p" and "1440" or "1080")
  local activeSnap = LucidUIDB._profiles[profileName]
  for k, v in pairs(activeSnap) do
    if not skip[k] then LucidUIDB[k] = v end
  end
  LucidUIDB._activeProfile = profileName
  selectedRes = resolution
  for _, m in ipairs(MODULES) do moduleStates[m.key] = activeSnap[m.key] or false end

  luiProfileApplied = true
  print("|cff3BD2ED[LucidUI]|r Recommended profiles created: R-LucidUI1440 & R-LucidUI1080 (active: " .. profileName .. ")")
end

local function ShowModules()
  ShowContent("modules")
  local c = GetContentFrame("modules")
  local ar, ag, ab = NS.ChatGetAccentRGB()
  local hex = NS.RGBToHex(ar, ag, ab)

  if not c._built then
    c._built = true
    local header = c:CreateFontString(nil, "OVERLAY")
    header:SetFont(FONT, 12, ""); header:SetTextColor(0.75, 0.75, 0.8)
    header:SetWidth(W - SIDEBAR_W - 60); header:SetJustifyH("CENTER")
    header:SetPoint("TOP", c, "TOP", 0, -20)
    header:SetText("Click the resolution to import the |cff" .. hex .. "Recommended Profile|r")

    local resLabel = c:CreateFontString(nil, "OVERLAY")
    resLabel:SetFont(FONT, 10, ""); resLabel:SetTextColor(0.5, 0.5, 0.6)
    resLabel:SetPoint("TOP", header, "BOTTOM", 0, -14); resLabel:SetText("Both profiles (R-LucidUI1440 & R-LucidUI1080) will be created.")

    local btn1440 = MakeButton(c, "1440p", 160, 36)
    btn1440:SetPoint("TOP", resLabel, "BOTTOM", -90, -16)
    local btn1080 = MakeButton(c, "1080p", 160, 36)
    btn1080:SetPoint("TOP", resLabel, "BOTTOM", 90, -16)

    local statusFs = c:CreateFontString(nil, "OVERLAY")
    statusFs:SetFont(FONT, 10, ""); statusFs:SetPoint("TOP", btn1440, "BOTTOM", 90, -16)
    statusFs:SetTextColor(0.4, 0.7, 0.4)
    c._statusFs = statusFs

    local function UpdateBtns()
      if selectedRes == "1440p" and luiProfileApplied then
        btn1440:SetBackdropBorderColor(ar, ag, ab, 0.8); btn1440._fs:SetTextColor(ar, ag, ab)
        btn1080:SetBackdropBorderColor(0.25, 0.25, 0.35, 1); btn1080._fs:SetTextColor(0.9, 0.9, 0.9)
        statusFs:SetText("Active: R-LucidUI1440")
      elseif selectedRes == "1080p" and luiProfileApplied then
        btn1080:SetBackdropBorderColor(ar, ag, ab, 0.8); btn1080._fs:SetTextColor(ar, ag, ab)
        btn1440:SetBackdropBorderColor(0.25, 0.25, 0.35, 1); btn1440._fs:SetTextColor(0.9, 0.9, 0.9)
        statusFs:SetText("Active: R-LucidUI1080")
      else
        btn1440:SetBackdropBorderColor(0.25, 0.25, 0.35, 1); btn1440._fs:SetTextColor(0.9, 0.9, 0.9)
        btn1080:SetBackdropBorderColor(0.25, 0.25, 0.35, 1); btn1080._fs:SetTextColor(0.9, 0.9, 0.9)
        statusFs:SetText("Skip — no profile will be imported")
      end
    end

    btn1440:SetScript("OnClick", function()
      ApplyLucidUIProfile("1440p"); UpdateBtns()
    end)
    btn1080:SetScript("OnClick", function()
      ApplyLucidUIProfile("1080p"); UpdateBtns()
    end)
    btn1440:SetScript("OnLeave", UpdateBtns); btn1080:SetScript("OnLeave", UpdateBtns)
    UpdateBtns()

    -- Module list + conflict warnings
    local moduleInfo = c:CreateFontString(nil, "OVERLAY")
    moduleInfo:SetFont(FONT, 10, ""); moduleInfo:SetWidth(W - SIDEBAR_W - 60)
    moduleInfo:SetJustifyH("CENTER"); moduleInfo:SetSpacing(4)
    moduleInfo:SetPoint("TOP", statusFs, "BOTTOM", 0, -24)
    moduleInfo:SetTextColor(0.45, 0.45, 0.55)
    c._moduleInfo = moduleInfo

    local conflictInfo = c:CreateFontString(nil, "OVERLAY")
    conflictInfo:SetFont(FONT, 10, ""); conflictInfo:SetWidth(W - SIDEBAR_W - 60)
    conflictInfo:SetJustifyH("CENTER"); conflictInfo:SetSpacing(3)
    conflictInfo:SetPoint("TOP", moduleInfo, "BOTTOM", 0, -12)
    conflictInfo:SetTextColor(0.7, 0.4, 0.2)
    c._conflictInfo = conflictInfo
  end

  -- Refresh module list (updates on every show to reflect current addon state)
  if c._moduleInfo then
    local hasAyije = IsAddonLoaded("Ayije_CDM")
    local hasDetails = IsAddonLoaded("Details")
    local mList = {}
    for _, m in ipairs(MODULES) do
      local disabled = (m.key == "cdm_enabled" and hasAyije) or (m.key == "dmEnabled" and hasDetails)
      if disabled then
        mList[#mList+1] = "|cff666666" .. m.label .. "|r — |cffaa5555disabled (conflict)|r"
      else
        mList[#mList+1] = "|cff" .. hex .. m.label .. "|r — " .. m.desc
      end
    end
    c._moduleInfo:SetText("Included modules:\n" .. table.concat(mList, "\n"))

    local warnings = {}
    if hasAyije then warnings[#warnings+1] = "|cffcc6633LucidCDM|r disabled — |cffffd100Ayije CDM|r is active" end
    if hasDetails then warnings[#warnings+1] = "|cffcc6633LucidMeter|r disabled — |cffffd100Details|r is active" end
    c._conflictInfo:SetText(table.concat(warnings, "\n"))
  end
end

-- ── Immediate addon import (called on button click, not deferred) ──────
local PROFILE_NAME = "LucidUI"

local function ApplyAddonProfile(addonKey, resolution)
  local P = NS.Profiles
  if not P then print("|cff3BD2ED[LucidUI]|r Profile data not loaded"); return end

  if addonKey == "ElvUI" then
    local E = _G.ElvUI and _G.ElvUI[1]
    if not E then print("|cff3BD2ED[LucidUI]|r ElvUI not found"); return end
    if not E.Distributor then print("|cff3BD2ED[LucidUI]|r ElvUI Distributor not found"); return end
    local DI = E.Distributor
    local profile = resolution == "1080p" and P.ElvUI1080p or P.ElvUI
    if not profile then print("|cff3BD2ED[LucidUI]|r ElvUI profile data missing for " .. resolution); return end
    -- ElvUI exports 4 strings: Profile, Private, Global, Aura Filters + scale as last entry
    local imported = 0
    for i, str in ipairs(profile) do
      if type(str) == "string" then
        local ok, profileType, _, data = pcall(DI.Decode, DI, str)
        if ok and profileType and data and type(data) == "table" then
          local ok2, err2 = pcall(DI.SetImportedProfile, DI, profileType, PROFILE_NAME, data, true)
          if ok2 then
            imported = imported + 1
          else
            print("|cff3BD2ED[LucidUI]|r ElvUI import " .. i .. " failed: " .. tostring(err2))
          end
        else
          print("|cff3BD2ED[LucidUI]|r ElvUI decode " .. i .. " failed: " .. tostring(profileType))
        end
      end
    end
    if imported > 0 then
      if E.data then pcall(E.data.SetProfile, E.data, PROFILE_NAME) end
      print("|cff3BD2ED[LucidUI]|r ElvUI imported " .. imported .. " sections")
    end
    -- Scale is last numeric entry in the table
    local scale = profile[#profile]
    if type(scale) == "number" and E.data and E.data.global and E.data.global.general then
      E.data.global.general.UIScale = scale
      if E.global and E.global.general then E.global.general.UIScale = scale end
      if E.UIScale then pcall(E.UIScale, E) end
    end

  elseif addonKey == "Plater" then
    local Pltr = _G.Plater
    if not Pltr then print("|cff3BD2ED[LucidUI]|r Plater not found"); return end
    if not Pltr.DecompressData then print("|cff3BD2ED[LucidUI]|r Plater.DecompressData not found"); return end
    local str = resolution == "1080p" and P.Plater1080p or P.Plater
    if not str then print("|cff3BD2ED[LucidUI]|r Plater profile data missing for " .. resolution); return end
    local ok, data = pcall(Pltr.DecompressData, str, "print")
    if not ok then print("|cff3BD2ED[LucidUI]|r Plater DecompressData failed: " .. tostring(data)); return end
    if not data then print("|cff3BD2ED[LucidUI]|r Plater DecompressData returned nil"); return end
    local ok2, err2 = pcall(Pltr.ImportAndSwitchProfile, PROFILE_NAME, data, false, false, true)
    if not ok2 then print("|cff3BD2ED[LucidUI]|r Plater ImportAndSwitchProfile failed: " .. tostring(err2)); return end
    print("|cff3BD2ED[LucidUI]|r Plater profile imported successfully")

  elseif addonKey == "BigWigs" then
    local BWAPI = _G.BigWigsAPI
    if BWAPI and BWAPI.RegisterProfile then
      local str = resolution == "1080p" and P.BigWigs1080p or P.BigWigs
      if str then
        pcall(BWAPI.RegisterProfile, PROFILE_NAME, str, PROFILE_NAME)
        local AceDB = LibStub and LibStub("AceDB-3.0", true)
        if AceDB and _G.BigWigs3DB then
          local db = AceDB:New(_G.BigWigs3DB)
          if db then pcall(db.SetProfile, db, PROFILE_NAME) end
        end
      end
    end

  elseif addonKey == "NaowhQOL" then
    local API = _G.NaowhQOL_API
    if API and API.Import then
      local str = resolution == "1080p" and P.NaowhQOL1080p or P.NaowhQOL
      if str then
        pcall(API.Import, str, nil, PROFILE_NAME)
        local AceDB = LibStub and LibStub("AceDB-3.0", true)
        if AceDB and _G.NaowhQOL_Profiles then
          local db = AceDB:New(_G.NaowhQOL_Profiles)
          if db then pcall(db.SetProfile, db, PROFILE_NAME) end
        end
      end
    end

  elseif addonKey == "WarpDeplete" then
    local profileData = resolution == "1080p" and P.WarpDeplete1080p or P.WarpDeplete
    if profileData and _G.WarpDeplete then
      local wdDB = _G.WarpDepleteDB
      if wdDB then
        wdDB.profiles = wdDB.profiles or {}
        wdDB.profiles[PROFILE_NAME] = profileData
        if _G.WarpDeplete.db then pcall(_G.WarpDeplete.db.SetProfile, _G.WarpDeplete.db, PROFILE_NAME) end
      end
    end

  elseif addonKey == "Details" then
    local Det = _G.Details
    if Det and Det.ImportProfile then
      local str = resolution == "1080p" and P.Details1080p or P.Details
      if str then
        pcall(Det.EraseProfile, Det, PROFILE_NAME)
        pcall(Det.ImportProfile, Det, str, PROFILE_NAME, false, false, true)
        pcall(Det.ApplyProfile, Det, PROFILE_NAME)
      end
    end

  elseif addonKey == "BlizziInterrupts" then
    local BIT_G = _G.BIT
    if BIT_G and BIT_G.ImportProfile and P.BlizziInterrupts then
      pcall(BIT_G.ImportProfile, P.BlizziInterrupts)
    end

  elseif addonKey == "Ayije_CDM" then
    local ACDM_API = _G.Ayije_CDM_API
    if ACDM_API and ACDM_API.ImportProfile then
      local str = resolution == "1080p" and P.Ayije_CDM1080p or P.Ayije_CDM
      if str then
        -- Colon-call: API:ImportProfile(data, profileName)
        pcall(ACDM_API.ImportProfile, ACDM_API, str, PROFILE_NAME)
      end
    end
  end
end

-- ── Step: Addon profile (per-addon with resolution choice) ─────────────
local function ShowAddonStep(addon, available)
  local id = "addon_" .. addon.key
  ShowContent(id)
  local c = GetContentFrame(id)
  local ar, ag, ab = NS.ChatGetAccentRGB()
  local hex = NS.RGBToHex(ar, ag, ab)

  if not c._built then
    c._built = true

    local header = c:CreateFontString(nil, "OVERLAY")
    header:SetFont(FONT, 12, ""); header:SetWidth(W - SIDEBAR_W - 60); header:SetJustifyH("CENTER")
    header:SetPoint("TOP", c, "TOP", 0, -20)
    header:SetTextColor(0.75, 0.75, 0.8)
    c._header = header

    -- Not installed hint
    local notInstalledFs = c:CreateFontString(nil, "OVERLAY")
    notInstalledFs:SetFont(FONT, 12, ""); notInstalledFs:SetWidth(W - SIDEBAR_W - 60)
    notInstalledFs:SetJustifyH("CENTER"); notInstalledFs:SetPoint("TOP", header, "BOTTOM", 0, -40)
    notInstalledFs:SetTextColor(0.6, 0.3, 0.3)
    notInstalledFs:SetText(addon.label .. " is not installed or not enabled.\nSkip this step.")
    notInstalledFs:Hide()
    c._notInstalled = notInstalledFs

    -- Content holder (hidden when not available)
    local ch = CreateFrame("Frame", nil, c)
    ch:SetAllPoints(c)
    c._contentHolder = ch

    if addon.has1080p then
      -- Resolution buttons
      local resLabel = ch:CreateFontString(nil, "OVERLAY")
      resLabel:SetFont(FONT, 11, ""); resLabel:SetTextColor(0.75, 0.75, 0.8)
      resLabel:SetPoint("TOP", header, "BOTTOM", 0, -40)
      resLabel:SetText("Click the resolution to setup |cff" .. hex .. addon.label .. "|r")

      local btn1440 = MakeButton(ch, "1440p", 160, 36)
      btn1440:SetPoint("TOP", resLabel, "BOTTOM", -90, -16)
      local btn1080 = MakeButton(ch, "1080p", 160, 36)
      btn1080:SetPoint("TOP", resLabel, "BOTTOM", 90, -16)

      local statusFs = ch:CreateFontString(nil, "OVERLAY")
      statusFs:SetFont(FONT, 10, ""); statusFs:SetPoint("TOP", btn1440, "BOTTOM", 90, -16)
      statusFs:SetTextColor(0.4, 0.7, 0.4)
      c._statusFs = statusFs

      local function UpdateBtns()
        local choice = addonChoices[addon.key]
        if choice == "1440p" then
          btn1440:SetBackdropBorderColor(ar, ag, ab, 0.8); btn1440._fs:SetTextColor(ar, ag, ab)
          btn1080:SetBackdropBorderColor(0.25, 0.25, 0.35, 1); btn1080._fs:SetTextColor(0.9, 0.9, 0.9)
          statusFs:SetText(addon.label .. " will be setup for 1440p")
        elseif choice == "1080p" then
          btn1080:SetBackdropBorderColor(ar, ag, ab, 0.8); btn1080._fs:SetTextColor(ar, ag, ab)
          btn1440:SetBackdropBorderColor(0.25, 0.25, 0.35, 1); btn1440._fs:SetTextColor(0.9, 0.9, 0.9)
          statusFs:SetText(addon.label .. " will be setup for 1080p")
        else
          btn1440:SetBackdropBorderColor(0.25, 0.25, 0.35, 1); btn1440._fs:SetTextColor(0.9, 0.9, 0.9)
          btn1080:SetBackdropBorderColor(0.25, 0.25, 0.35, 1); btn1080._fs:SetTextColor(0.9, 0.9, 0.9)
          statusFs:SetText("Skip — no profile will be imported")
        end
      end
      c._updateBtns = UpdateBtns

      btn1440:SetScript("OnClick", function()
        addonChoices[addon.key] = "1440p"; ApplyAddonProfile(addon.key, "1440p"); UpdateBtns()
      end)
      btn1080:SetScript("OnClick", function()
        addonChoices[addon.key] = "1080p"; ApplyAddonProfile(addon.key, "1080p"); UpdateBtns()
      end)
      btn1440:SetScript("OnLeave", UpdateBtns); btn1080:SetScript("OnLeave", UpdateBtns)

      -- Conflict warning for Ayije_CDM and Details
      if addon.key == "Ayije_CDM" or addon.key == "Details" then
        local conflictFs = ch:CreateFontString(nil, "OVERLAY")
        conflictFs:SetFont(FONT, 9, ""); conflictFs:SetWidth(W - SIDEBAR_W - 60)
        conflictFs:SetJustifyH("CENTER"); conflictFs:SetSpacing(3)
        conflictFs:SetPoint("TOP", statusFs, "BOTTOM", 0, -20)
        conflictFs:SetTextColor(0.7, 0.4, 0.2)
        if addon.key == "Ayije_CDM" then
          conflictFs:SetText("|cffcc6633Warning:|r Ayije CDM conflicts with |cff" .. hex .. "LucidCDM|r.\nIf you use Ayije CDM, disable LucidCDM in the LucidUI step.")
        else
          conflictFs:SetText("|cffcc6633Warning:|r Details conflicts with |cff" .. hex .. "LucidMeter|r.\nIf you use Details, disable LucidMeter in the LucidUI step.")
        end

        -- Disable addon button
        local disableBtn = MakeButton(ch, "Disable " .. addon.label .. " & Reload", 220, 28)
        disableBtn:SetPoint("TOP", conflictFs, "BOTTOM", 0, -12)
        disableBtn:SetBackdropBorderColor(0.6, 0.25, 0.15, 0.8)
        disableBtn._fs:SetTextColor(0.8, 0.4, 0.2)
        disableBtn:SetScript("OnEnter", function()
          disableBtn:SetBackdropBorderColor(0.8, 0.35, 0.15, 1)
          disableBtn._fs:SetTextColor(1, 0.5, 0.2)
        end)
        disableBtn:SetScript("OnLeave", function()
          disableBtn:SetBackdropBorderColor(0.6, 0.25, 0.15, 0.8)
          disableBtn._fs:SetTextColor(0.8, 0.4, 0.2)
        end)
        disableBtn:SetScript("OnClick", function()
          -- Disable the addon and reload; wizard will reopen on login
          if C_AddOns and C_AddOns.DisableAddOn then
            C_AddOns.DisableAddOn(addon.check)
          elseif _G.DisableAddOn then
            _G.DisableAddOn(addon.check)
          end
          -- Mark wizard as incomplete so it reopens after reload
          if LucidUIDB then LucidUIDB._installComplete = nil end
          ReloadUI()
        end)
      end
    else
      -- Single button (no resolution, e.g. BlizziInterrupts)
      local setupBtn = MakeAccentButton(ch, "Setup " .. addon.label, 200, 36)
      setupBtn:SetPoint("TOP", header, "BOTTOM", 0, -50)

      local statusFs = ch:CreateFontString(nil, "OVERLAY")
      statusFs:SetFont(FONT, 10, ""); statusFs:SetPoint("TOP", setupBtn, "BOTTOM", 0, -12)
      statusFs:SetTextColor(0.4, 0.7, 0.4)
      c._statusFs = statusFs

      local function UpdateBtns()
        if addonChoices[addon.key] then
          setupBtn:SetBackdropBorderColor(0.3, 0.7, 0.3, 0.8)
          statusFs:SetText(addon.label .. " will be imported")
        else
          local r, g, b = NS.ChatGetAccentRGB()
          setupBtn:SetBackdropBorderColor(r, g, b, 0.6)
          statusFs:SetText("")
        end
      end
      c._updateBtns = UpdateBtns

      setupBtn:SetScript("OnClick", function()
        addonChoices[addon.key] = "default"
        ApplyAddonProfile(addon.key, "default")
        UpdateBtns()
      end)
    end
  end

  c._header:SetText(addon.label)

  -- Show/hide content vs not-installed message
  if c._notInstalled then c._notInstalled:SetShown(not available) end
  if c._contentHolder then c._contentHolder:SetShown(available) end

  if c._updateBtns and available then c._updateBtns() end
end

-- ── Step: Class Layout ─────────────────────────────────────────────────
local function ImportClassLayout(classKey)
  local classData = NS.ClassLayouts and NS.ClassLayouts[classKey]
  if not classData then return false, "No layout data for " .. classKey end
  if not CooldownViewerSettings then return false, "CooldownViewer not loaded" end

  local layoutManager = CooldownViewerSettings:GetLayoutManager()
  if not layoutManager then return false, "No layout manager" end

  -- Suppress EnableSpellRangeCheck errors during import (Blizzard bug with runtime layout changes)
  local origESRC = C_Spell and C_Spell.EnableSpellRangeCheck
  if origESRC then
    C_Spell.EnableSpellRangeCheck = function(id, enable)
      if id and id ~= 0 then pcall(origESRC, id, enable) end
    end
  end

  -- Support both single string and table of strings (multiple specs)
  local allLayoutIDs = {}
  local dataList = type(classData) == "table" and classData or {classData}
  for _, data in ipairs(dataList) do
    local ok, layoutIDs = pcall(layoutManager.CreateLayoutsFromSerializedData, layoutManager, data)
    if ok and layoutIDs then
      for _, id in ipairs(layoutIDs) do allLayoutIDs[#allLayoutIDs + 1] = id end
    end
  end

  if origESRC then C_Spell.EnableSpellRangeCheck = origESRC end
  if #allLayoutIDs == 0 then return false, "Import failed" end

  -- Rename during import
  for _, layoutID in ipairs(allLayoutIDs) do
    local layout = layoutManager.layouts and layoutManager.layouts[layoutID]
    if layout then
      if layout.name then layout.name = layout.name:gsub("^.- %- ", "LucidUI - ") end
      if layout.layoutName then layout.layoutName = layout.layoutName:gsub("^.- %- ", "LucidUI - ") end
    end
  end

  layoutManager:SaveLayouts()
  return true, #allLayoutIDs .. " layouts imported"
end

local function ShowClassLayout()
  ShowContent("classLayout")
  local c = GetContentFrame("classLayout")
  local ar, ag, ab = NS.ChatGetAccentRGB()
  local hex = NS.RGBToHex(ar, ag, ab)

  if not c._built then
    c._built = true

    local _, className = UnitClass("player")
    local classDisplay = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[className] or className or "Unknown"
    local classKey = className and strlower(className)
    local hasLayout = NS.ClassLayouts and classKey and NS.ClassLayouts[classKey]

    -- Class-colored class name
    local classColor = C_ClassColor and C_ClassColor.GetClassColor(className)
    local classHex = classColor and classColor:GenerateHexColor():sub(3) or hex

    local header = c:CreateFontString(nil, "OVERLAY")
    header:SetFont(FONT, 12, ""); header:SetWidth(W - SIDEBAR_W - 60); header:SetJustifyH("CENTER")
    header:SetPoint("TOP", c, "TOP", 0, -20)
    header:SetTextColor(0.75, 0.75, 0.8)
    header:SetText("Click the button below to setup your Class Layout")

    local classLabel = c:CreateFontString(nil, "OVERLAY")
    classLabel:SetFont(FONT, 14, ""); classLabel:SetPoint("TOP", header, "BOTTOM", 0, -12)
    classLabel:SetText("Your class: |cff" .. classHex .. classDisplay .. "|r")

    if hasLayout then
      local setupBtn = MakeAccentButton(c, "Setup Class Layout", 200, 36)
      setupBtn:SetPoint("TOP", classLabel, "BOTTOM", 0, -30)

      local statusFs = c:CreateFontString(nil, "OVERLAY")
      statusFs:SetFont(FONT, 10, ""); statusFs:SetPoint("TOP", setupBtn, "BOTTOM", 0, -12)
      statusFs:SetTextColor(0.4, 0.7, 0.4)

      setupBtn:SetScript("OnClick", function()
        local ok, msg = ImportClassLayout(classKey)
        if ok then
          applyClassLayout = true
          setupBtn:SetBackdropBorderColor(0.3, 0.7, 0.3, 0.8)
          statusFs:SetTextColor(0.3, 0.8, 0.3)
          statusFs:SetText("Imported: " .. msg)
        else
          statusFs:SetTextColor(0.8, 0.3, 0.3)
          statusFs:SetText("Failed: " .. (msg or "unknown error"))
        end
      end)
    else
      local noLayout = c:CreateFontString(nil, "OVERLAY")
      noLayout:SetFont(FONT, 11, ""); noLayout:SetPoint("TOP", header, "BOTTOM", 0, -30)
      noLayout:SetTextColor(0.5, 0.5, 0.6)
      noLayout:SetText("No cooldown layout found for your class.")
      applyClassLayout = false
    end
  end
end

-- ── Step: Complete ─────────────────────────────────────────────────────
local function ShowComplete()
  ShowContent("complete")
  local c = GetContentFrame("complete")
  local ar, ag, ab = NS.ChatGetAccentRGB()
  local hex = NS.RGBToHex(ar, ag, ab)

  if not c._doneText then
    c._doneText = c:CreateFontString(nil, "OVERLAY")
    c._doneText:SetFont(FONT, 12, ""); c._doneText:SetWidth(W - SIDEBAR_W - 60)
    c._doneText:SetJustifyH("CENTER"); c._doneText:SetPoint("TOP", c, "TOP", 0, -20)
  end

  -- Build summary
  local enabled = {}
  for _, m in ipairs(MODULES) do
    if moduleStates[m.key] then enabled[#enabled+1] = m.label end
  end
  local modSummary = #enabled > 0 and table.concat(enabled, ", ") or "None"

  local addonList = {}
  for _, a in ipairs(ADDON_STEPS) do
    if addonChoices[a.key] then
      local res = addonChoices[a.key] ~= "default" and (" (" .. addonChoices[a.key] .. ")") or ""
      addonList[#addonList+1] = a.label .. res
    end
  end
  local addonSummary = #addonList > 0 and table.concat(addonList, ", ") or "None"

  c._doneText:SetTextColor(0.75, 0.75, 0.8)
  c._doneText:SetText(
    "Setup complete!\n\n" ..
    "Resolution: |cff" .. hex .. selectedRes .. "|r\n" ..
    "Modules: |cff" .. hex .. modSummary .. "|r\n" ..
    "Addon Profiles: |cff" .. hex .. addonSummary .. "|r\n" ..
    (applyClassLayout and ("Class Layout: |cff" .. hex .. "Yes|r\n") or "") ..
    "\nClick |cff" .. hex .. "Reload|r to apply all settings."
  )
  wizard.nextBtn._fs:SetText("Reload")
end

-- ── Show current step ──────────────────────────────────────────────────
function NS._WizardShowStep()
  if not wizard then return end
  local step = steps[currentStep]
  if not step then return end

  -- Update subtitle
  wizard._subtitle:SetText(step.label)

  -- Update sidebar
  UpdateSidebar()

  -- Update progress bar
  local pct = currentStep / #steps
  wizard._progressBar:SetWidth(math.max(1, (wizard._progressBg:GetWidth() - 2) * pct))
  wizard._progressText:SetText(currentStep .. " / " .. #steps)

  -- Navigation
  wizard.prevBtn:SetShown(currentStep > 1)
  wizard.nextBtn._fs:SetText(currentStep == #steps and "Reload" or "Continue")

  -- Show step content
  if step.id == "welcome" then ShowWelcome()
  elseif step.id == "modules" then ShowModules()
  elseif step.id == "addon" then ShowAddonStep(step.addon, step.available)
  elseif step.id == "classLayout" then ShowClassLayout()
  elseif step.id == "complete" then ShowComplete()
  end
end

-- ── Finish: apply all settings + reload ────────────────────────────────
function NS._WizardFinish()
  if not LucidUIDB then LucidUIDB = {} end

  -- All profiles (LucidUI, addons, class layout) were applied on button click
  -- Finish only marks install complete and reloads

  LucidUIDB._installComplete = true
  ReloadUI()
end

-- ── Public API ─────────────────────────────────────────────────────────
function NS.ShowInstallWizard()
  CreateWizard()
  currentStep = 1
  selectedRes = "1440p"
  applyClassLayout = false
  luiProfileApplied = false
  for _, m in ipairs(MODULES) do moduleStates[m.key] = false end
  addonChoices = {}
  -- Wipe cached content frames so they rebuild with fresh state
  for id, cf in pairs(contentFrames) do cf._built = nil end
  RebuildSteps()
  NS._WizardShowStep()
  wizard:Show()
end

-- ── Auto-show on first install ─────────────────────────────────────────
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
  C_Timer.After(1, function()
    if LucidUIDB and LucidUIDB._installComplete then
      return
    end
    if not LucidUIDB then LucidUIDB = {} end
    NS.ShowInstallWizard()
  end)
end)

-- ── Slash commands ─────────────────────────────────────────────────────
SLASH_LUISETUP1 = "/luisetup"
SlashCmdList["LUISETUP"] = function() NS.ShowInstallWizard() end
