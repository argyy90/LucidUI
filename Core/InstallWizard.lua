-- LucidUI Core/InstallWizard.lua
-- First-install setup wizard (NaowhUI-style per-addon steps with sidebar)

local NS = LucidUINS

-- ── Resolution presets (LucidUI internal sizes) ────────────────────────
local PRESETS = {
  ["1440p"] = {
    cdv_essWidth = 46, cdv_essHeight = 40, cdv_essSpacing = 2, cdv_essPerRow = 8,
    cdv_utilWidth = 46, cdv_utilHeight = 40, cdv_utilSpacing = 2, cdv_utilPerRow = 8,
    cdv_fontSize = 14,
    cb_width = 350, cb_height = 10, cb_fontSize = 12, cb_textYOffset = 5,
    res_width = 350, res_height = 14, res_secHeight = 14, res_pipSpacing = 1,
    bb_buffIconSize = 36, bb_buffIconSpacing = 2, bb_buffIconsPerRow = 12,
    bb_buffBarWidth = 200, bb_buffBarHeight = 20,
    bagIconSize = 37, bagSpacing = 4, bagColumns = 10,
  },
  ["1080p"] = {
    cdv_essWidth = 36, cdv_essHeight = 32, cdv_essSpacing = 2, cdv_essPerRow = 8,
    cdv_utilWidth = 36, cdv_utilHeight = 32, cdv_utilSpacing = 2, cdv_utilPerRow = 8,
    cdv_fontSize = 11,
    cb_width = 280, cb_height = 8, cb_fontSize = 10, cb_textYOffset = 4,
    res_width = 280, res_height = 12, res_secHeight = 12, res_pipSpacing = 1,
    bb_buffIconSize = 28, bb_buffIconSpacing = 2, bb_buffIconsPerRow = 12,
    bb_buffBarWidth = 160, bb_buffBarHeight = 16,
    bagIconSize = 32, bagSpacing = 3, bagColumns = 10,
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
local applyClassLayout = true

-- Per-addon: nil = skip, "1440p" or "1080p" = apply with resolution
local addonChoices = {}

-- ── Build ordered step list dynamically ────────────────────────────────
local steps = {}  -- rebuilt each time wizard opens

local function IsAddonLoaded(name)
  if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) end
  if _G.IsAddOnLoaded then return _G.IsAddOnLoaded(name) end
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

-- ── Step: Modules ──────────────────────────────────────────────────────
local function ShowModules()
  ShowContent("modules")
  local c = GetContentFrame("modules")
  local ar, ag, ab = NS.ChatGetAccentRGB()

  if not c._built then
    c._built = true
    local header = c:CreateFontString(nil, "OVERLAY")
    header:SetFont(FONT, 12, ""); header:SetTextColor(0.75, 0.75, 0.8)
    header:SetWidth(W - SIDEBAR_W - 60); header:SetJustifyH("CENTER")
    header:SetPoint("TOP", c, "TOP", 0, -8)
    header:SetText("Select LucidUI resolution and modules.")

    -- Resolution buttons
    local resLabel = c:CreateFontString(nil, "OVERLAY")
    resLabel:SetFont(FONT, 10, ""); resLabel:SetTextColor(0.5, 0.5, 0.6)
    resLabel:SetPoint("TOP", header, "BOTTOM", 0, -10); resLabel:SetText("LucidUI Resolution")

    local btn1440 = MakeButton(c, "1440p", 120, 26)
    btn1440:SetPoint("TOP", resLabel, "BOTTOM", -68, -6)
    local btn1080 = MakeButton(c, "1080p", 120, 26)
    btn1080:SetPoint("TOP", resLabel, "BOTTOM", 68, -6)

    local function UpdateRes()
      local r, g, b = NS.ChatGetAccentRGB()
      if selectedRes == "1440p" then
        btn1440:SetBackdropBorderColor(r, g, b, 0.8); btn1440._fs:SetTextColor(r, g, b)
        btn1080:SetBackdropBorderColor(0.25, 0.25, 0.35, 1); btn1080._fs:SetTextColor(0.9, 0.9, 0.9)
      else
        btn1080:SetBackdropBorderColor(r, g, b, 0.8); btn1080._fs:SetTextColor(r, g, b)
        btn1440:SetBackdropBorderColor(0.25, 0.25, 0.35, 1); btn1440._fs:SetTextColor(0.9, 0.9, 0.9)
      end
    end
    btn1440:SetScript("OnClick", function() selectedRes = "1440p"; UpdateRes() end)
    btn1080:SetScript("OnClick", function() selectedRes = "1080p"; UpdateRes() end)
    btn1440:SetScript("OnLeave", UpdateRes); btn1080:SetScript("OnLeave", UpdateRes)
    UpdateRes()

    -- Enable All button
    local enableAll = MakeButton(c, "Enable All", 90, 22)
    enableAll:SetPoint("TOPRIGHT", c, "TOPRIGHT", -10, -70)
    enableAll:SetScript("OnClick", function()
      for _, m in ipairs(MODULES) do moduleStates[m.key] = true end
      for _, row in ipairs(c._rows) do if row._cb then row._cb:SetChecked(true) end end
    end)

    c._rows = {}
    local yOff = -94
    for i, m in ipairs(MODULES) do
      local row = CreateFrame("Button", nil, c)
      row:SetHeight(30)
      local hoverBg = row:CreateTexture(nil, "BACKGROUND")
      hoverBg:SetAllPoints(); hoverBg:SetColorTexture(1, 1, 1, 0); row._hoverBg = hoverBg

      local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
      cb:SetSize(22, 22); cb:SetPoint("LEFT", 20, 0)
      cb:SetScript("OnClick", function(self) moduleStates[m.key] = self:GetChecked() end)
      row._cb = cb

      local lbl = row:CreateFontString(nil, "OVERLAY")
      lbl:SetFont(FONT, 12, ""); lbl:SetPoint("LEFT", cb, "RIGHT", 6, 0)
      lbl:SetTextColor(ar, ag, ab); lbl:SetText(m.label)

      local desc = row:CreateFontString(nil, "OVERLAY")
      desc:SetFont(FONT, 10, ""); desc:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
      desc:SetTextColor(0.45, 0.45, 0.55); desc:SetText("— " .. m.desc)

      row:SetScript("OnClick", function() cb:SetChecked(not cb:GetChecked()); moduleStates[m.key] = cb:GetChecked() end)
      row:SetScript("OnEnter", function() hoverBg:SetColorTexture(ar, ag, ab, 0.06) end)
      row:SetScript("OnLeave", function() hoverBg:SetColorTexture(1, 1, 1, 0) end)

      row:SetPoint("TOPLEFT", c, "TOPLEFT", 0, yOff)
      row:SetPoint("RIGHT", c, "RIGHT", 0, 0)
      c._rows[i] = row
      yOff = yOff - 34
    end

    -- Recommendations & conflict warnings
    local infoFs = c:CreateFontString(nil, "OVERLAY")
    infoFs:SetFont(FONT, 9, ""); infoFs:SetWidth(W - SIDEBAR_W - 40)
    infoFs:SetJustifyH("LEFT"); infoFs:SetPoint("TOPLEFT", c, "TOPLEFT", 20, yOff - 8)
    infoFs:SetSpacing(3)
    c._infoFs = infoFs
  end

  -- Refresh checkbox states
  for i, m in ipairs(MODULES) do
    if c._rows[i] and c._rows[i]._cb then c._rows[i]._cb:SetChecked(moduleStates[m.key]) end
  end

  -- Update conflict info based on which addons were imported
  if c._infoFs then
    local ar, ag, ab = NS.ChatGetAccentRGB()
    local hex = NS.RGBToHex(ar, ag, ab)
    local lines = {}
    lines[#lines+1] = "|cff" .. hex .. "Recommended:|r LucidCDM, LucidChat, LucidBags"

    local hasAyije = addonChoices["Ayije_CDM"]
    local hasDetails = addonChoices["Details"]
    if hasAyije or hasDetails then
      local conflicts = {}
      if hasAyije then conflicts[#conflicts+1] = "Ayije CDM" end
      if hasDetails then conflicts[#conflicts+1] = "Details" end
      lines[#lines+1] = "|cffcc4444Conflict:|r " .. table.concat(conflicts, " & ") .. " active — disable |cff" .. hex .. "LucidMeter|r and |cff" .. hex .. "LucidCDM|r to avoid issues"
    end
    c._infoFs:SetText(table.concat(lines, "\n"))
  end
end

-- ── Immediate addon import (called on button click, not deferred) ──────
local PROFILE_NAME = "LucidUI"

local function ApplyAddonProfile(addonKey, resolution)
  local P = NS.Profiles
  if not P then return end

  if addonKey == "ElvUI" then
    local E = _G.ElvUI and _G.ElvUI[1]
    if E and E.Distributor then
      local DI = E.Distributor
      local profile = resolution == "1080p" and P.ElvUI1080p or P.ElvUI
      if profile then
        local str = profile[1]
        local scale = profile[2]
        local ok, profileType, _, data = pcall(DI.Decode, DI, str)
        if ok and profileType and data and type(data) == "table" then
          pcall(DI.SetImportedProfile, DI, profileType, PROFILE_NAME, data, true)
          if E.data then pcall(E.data.SetProfile, E.data, PROFILE_NAME) end
        end
        if scale and E.data and E.data.global and E.data.global.general then
          E.data.global.general.UIScale = scale
        end
      end
    end

  elseif addonKey == "Plater" then
    local Pltr = _G.Plater
    if Pltr and Pltr.DecompressData then
      local str = resolution == "1080p" and P.Plater1080p or P.Plater
      if str then
        local ok, data = pcall(Pltr.DecompressData, str, "print")
        if ok and data then pcall(Pltr.ImportAndSwitchProfile, PROFILE_NAME, data, false, false, true) end
      end
    end

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

  -- Apply LucidUI resolution preset
  local preset = PRESETS[selectedRes]
  if preset then for k, v in pairs(preset) do LucidUIDB[k] = v end end
  LucidUIDB._resolution = selectedRes

  -- Apply module toggles
  for _, m in ipairs(MODULES) do LucidUIDB[m.key] = moduleStates[m.key] end
  if moduleStates["ltEnabled"] then LucidUIDB["lootOwnWindow"] = true end

  -- Addon profiles were already applied immediately on button click

  -- ── Apply class cooldown layout ──────────────────────────────────────
  if applyClassLayout then
    local _, className = UnitClass("player")
    local classKey = className and strlower(className)
    local classData = NS.ClassLayouts and classKey and NS.ClassLayouts[classKey]
    if classData and CooldownViewerSettings then
      local layoutManager = CooldownViewerSettings:GetLayoutManager()
      if layoutManager then
        local classDisplay = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[className] or className
        local prefix = "LucidUI - " .. classDisplay
        if layoutManager.layouts then
          local toRemove = {}
          for layoutID, layout in pairs(layoutManager.layouts) do
            local name = layout and (layout.layoutName or layout.name)
            if name and name:find(prefix, 1, true) == 1 then toRemove[#toRemove+1] = layoutID end
          end
          if #toRemove > 0 then
            table.sort(toRemove, function(a, b) return a > b end)
            for _, id in ipairs(toRemove) do layoutManager.layouts[id] = nil end
            local newLayouts = {}
            for _, layout in pairs(layoutManager.layouts) do
              if layout then newLayouts[#newLayouts+1] = layout; layout.layoutID = #newLayouts end
            end
            for k in pairs(layoutManager.layouts) do layoutManager.layouts[k] = nil end
            for i, layout in ipairs(newLayouts) do layoutManager.layouts[i] = layout end
          end
        end
        -- Support both single string and table of strings (multiple specs)
        local allLayoutIDs = {}
        local dataList = type(classData) == "table" and classData or {classData}
        for _, data in ipairs(dataList) do
          local ok2, ids = pcall(layoutManager.CreateLayoutsFromSerializedData, layoutManager, data)
          if ok2 and ids then
            for _, id in ipairs(ids) do allLayoutIDs[#allLayoutIDs + 1] = id end
          end
        end
        if #allLayoutIDs > 0 then
          -- Class Layout import
          for _, layoutID in ipairs(allLayoutIDs) do
            local layout = layoutManager.layouts and layoutManager.layouts[layoutID]
            if layout then
              if layout.name then layout.name = layout.name:gsub("^.- %- ", "LucidUI - ") end
              if layout.layoutName then layout.layoutName = layout.layoutName:gsub("^.- %- ", "LucidUI - ") end
            end
          end
          -- Activate matching spec layout
          local specIndex = GetSpecialization()
          local activeLayoutID = allLayoutIDs[1]
          if specIndex then
            local _, specName = GetSpecializationInfo(specIndex)
            if specName and layoutManager.layouts then
              for _, layoutID in ipairs(allLayoutIDs) do
                local layout = layoutManager.layouts[layoutID]
                if layout and layout.name and layout.name:find(specName) then activeLayoutID = layoutID; break end
              end
            end
          end
          layoutManager:SetActiveLayoutByID(activeLayoutID)
          layoutManager:SaveLayouts()
        end
      end
    end
  end

  -- Free profile strings from memory (they're no longer needed after install)
  NS.Profiles = nil

  LucidUIDB._installComplete = true
  ReloadUI()
end

-- ── Public API ─────────────────────────────────────────────────────────
function NS.ShowInstallWizard()
  CreateWizard()
  currentStep = 1
  selectedRes = "1440p"
  applyClassLayout = true
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
      -- Install already done — free profile strings (~350KB)
      NS.Profiles = nil
      return
    end
    if not LucidUIDB then LucidUIDB = {} end
    NS.ShowInstallWizard()
  end)
end)

-- ── Slash commands ─────────────────────────────────────────────────────
SLASH_LUISETUP1 = "/luisetup"
SlashCmdList["LUISETUP"] = function() NS.ShowInstallWizard() end
