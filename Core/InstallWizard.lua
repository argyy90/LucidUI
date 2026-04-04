-- LucidUI Core/InstallWizard.lua
-- First-install setup wizard

local NS = LucidUINS

-- ── Resolution presets ──────────────────────────────────────────────────
local PRESETS = {
  ["1440p"] = {
    -- CDM
    cdv_essWidth = 46, cdv_essHeight = 40, cdv_essSpacing = 2, cdv_essPerRow = 8,
    cdv_utilWidth = 46, cdv_utilHeight = 40, cdv_utilSpacing = 2, cdv_utilPerRow = 8,
    cdv_fontSize = 14,
    cb_width = 350, cb_height = 10, cb_fontSize = 12, cb_textYOffset = 5,
    res_width = 350, res_height = 14, res_secHeight = 14, res_pipSpacing = 1,
    bb_buffIconSize = 36, bb_buffIconSpacing = 2, bb_buffIconsPerRow = 12,
    bb_buffBarWidth = 200, bb_buffBarHeight = 20,
    -- Bags
    bagIconSize = 37, bagSpacing = 4, bagColumns = 10,
  },
  ["1080p"] = {
    -- CDM
    cdv_essWidth = 36, cdv_essHeight = 32, cdv_essSpacing = 2, cdv_essPerRow = 8,
    cdv_utilWidth = 36, cdv_utilHeight = 32, cdv_utilSpacing = 2, cdv_utilPerRow = 8,
    cdv_fontSize = 11,
    cb_width = 280, cb_height = 8, cb_fontSize = 10, cb_textYOffset = 4,
    res_width = 280, res_height = 12, res_secHeight = 12, res_pipSpacing = 1,
    bb_buffIconSize = 28, bb_buffIconSpacing = 2, bb_buffIconsPerRow = 12,
    bb_buffBarWidth = 160, bb_buffBarHeight = 16,
    -- Bags
    bagIconSize = 32, bagSpacing = 3, bagColumns = 10,
  },
}

-- ── Module definitions ──────────────────────────────────────────────────
local MODULES = {
  {key = "cdm_enabled",       label = "LucidCDM",       desc = "Cooldowns, Cast Bar, Resources & Buffs"},
  {key = "chatEnabled",       label = "LucidChat",      desc = "Custom chat window"},
  {key = "ltEnabled",         label = "Loot Tracker",   desc = "Loot tracking & session stats"},
  {key = "bagEnabled",        label = "LucidBags",      desc = "Custom bag frames"},
  {key = "dmEnabled",         label = "LucidMeter",     desc = "Damage / healing meter"},
  {key = "gtEnabled",         label = "Gold Tracker",   desc = "Gold tracking across characters"},
  {key = "mpEnabled",         label = "Mythic+",        desc = "Mythic+ run tracker"},
}

-- ── Wizard state ────────────────────────────────────────────────────────
local wizard = nil
local currentStep = 1
local totalSteps = 4
local selectedRes = "1440p"
local moduleStates = {}

-- Init module states (all off)
for _, m in ipairs(MODULES) do moduleStates[m.key] = false end
local applyClassLayout = true  -- default on

-- ── Style constants ─────────────────────────────────────────────────────
local SBD = {bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1}
local FONT = "Fonts/FRIZQT__.TTF"
local W, H = 580, 480

-- ── Helper: styled button ───────────────────────────────────────────────
local function MakeButton(parent, text, w, h)
  local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
  btn:SetSize(w or 120, h or 28)
  btn:SetBackdrop(SBD)
  btn:SetBackdropColor(0.08, 0.08, 0.12, 1)
  btn:SetBackdropBorderColor(0.25, 0.25, 0.35, 1)
  local fs = btn:CreateFontString(nil, "OVERLAY")
  fs:SetFont(FONT, 11, ""); fs:SetPoint("CENTER"); fs:SetTextColor(0.9, 0.9, 0.9)
  fs:SetText(text)
  btn._fs = fs
  btn:SetScript("OnEnter", function()
    local r, g, b = NS.ChatGetAccentRGB()
    btn:SetBackdropBorderColor(r, g, b, 0.8)
    fs:SetTextColor(r, g, b)
  end)
  btn:SetScript("OnLeave", function()
    btn:SetBackdropBorderColor(0.25, 0.25, 0.35, 1)
    fs:SetTextColor(0.9, 0.9, 0.9)
  end)
  return btn
end

-- ── Helper: accent-colored button ───────────────────────────────────────
local function MakeAccentButton(parent, text, w, h)
  local btn = MakeButton(parent, text, w, h)
  local r, g, b = NS.ChatGetAccentRGB()
  btn:SetBackdropBorderColor(r, g, b, 0.6)
  btn._fs:SetTextColor(r, g, b)
  btn:SetScript("OnLeave", function()
    btn:SetBackdropBorderColor(r, g, b, 0.6)
    btn._fs:SetTextColor(r, g, b)
  end)
  return btn
end

-- ── Build the wizard frame ──────────────────────────────────────────────
local function CreateWizard()
  if wizard then return wizard end

  local f = CreateFrame("Frame", "LucidUIInstallWizard", UIParent, "BackdropTemplate")
  f:SetSize(W, H); f:SetPoint("CENTER")
  f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetFrameLevel(100)
  f:SetMovable(true); f:SetClampedToScreen(true); f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetBackdrop(SBD)
  f:SetBackdropColor(0.04, 0.04, 0.06, 0.97)
  f:SetBackdropBorderColor(0.15, 0.15, 0.22, 1)

  -- Title
  local title = f:CreateFontString(nil, "OVERLAY")
  title:SetFont(FONT, 14, ""); title:SetPoint("TOP", 0, -14)
  title:SetTextColor(0.9, 0.9, 0.9)
  title:SetText("LucidUI Setup")

  -- Accent line under title
  local ar, ag, ab = NS.ChatGetAccentRGB()
  local titleLine = f:CreateTexture(nil, "ARTWORK")
  titleLine:SetHeight(1); titleLine:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -36)
  titleLine:SetPoint("TOPRIGHT", f, "TOPRIGHT", -20, -36)
  titleLine:SetColorTexture(ar, ag, ab, 0.4)

  -- Content area
  f.content = CreateFrame("Frame", nil, f)
  f.content:SetPoint("TOPLEFT", 20, -44)
  f.content:SetPoint("BOTTOMRIGHT", -20, 50)

  -- Bottom bar
  local botLine = f:CreateTexture(nil, "ARTWORK")
  botLine:SetHeight(1); botLine:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 44)
  botLine:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 44)
  botLine:SetColorTexture(0.15, 0.15, 0.22, 1)

  -- Step counter
  f.stepText = f:CreateFontString(nil, "OVERLAY")
  f.stepText:SetFont(FONT, 10, ""); f.stepText:SetPoint("BOTTOM", 0, 16)
  f.stepText:SetTextColor(0.5, 0.5, 0.6)

  -- Previous button
  f.prevBtn = MakeButton(f, "Previous", 100, 24)
  f.prevBtn:SetPoint("BOTTOMLEFT", 20, 12)
  f.prevBtn:SetScript("OnClick", function()
    if currentStep > 1 then currentStep = currentStep - 1; NS._WizardShowStep() end
  end)

  -- Continue button
  f.nextBtn = MakeAccentButton(f, "Continue", 100, 24)
  f.nextBtn:SetPoint("BOTTOMRIGHT", -20, 12)
  f.nextBtn:SetScript("OnClick", function()
    if currentStep < totalSteps then currentStep = currentStep + 1; NS._WizardShowStep()
    elseif currentStep == totalSteps then NS._WizardFinish() end
  end)

  -- Close button
  local closeBtn = CreateFrame("Button", nil, f)
  closeBtn:SetSize(18, 18); closeBtn:SetPoint("TOPRIGHT", -8, -8)
  closeBtn:SetNormalFontObject("GameFontNormal")
  local closeTex = closeBtn:CreateFontString(nil, "OVERLAY")
  closeTex:SetFont(FONT, 14, ""); closeTex:SetPoint("CENTER"); closeTex:SetTextColor(0.5, 0.5, 0.6)
  closeTex:SetText("×")
  closeBtn:SetScript("OnClick", function()
    f:Hide()
    -- Mark as skipped so it doesn't show again
    if LucidUIDB then LucidUIDB._installComplete = true end
  end)
  closeBtn:SetScript("OnEnter", function() closeTex:SetTextColor(1, 0.3, 0.3) end)
  closeBtn:SetScript("OnLeave", function() closeTex:SetTextColor(0.5, 0.5, 0.6) end)

  -- Step frames (one per step, only one visible at a time)
  f.steps = {}
  for i = 1, totalSteps do
    local sf = CreateFrame("Frame", nil, f.content)
    sf:SetAllPoints(f.content); sf:Hide()
    f.steps[i] = sf
  end

  wizard = f
  return f
end

local function ShowOnlyStep(idx)
  for i = 1, totalSteps do wizard.steps[i]:Hide() end
  wizard.steps[idx]:Show()
end

-- ── Step 1: Welcome + Resolution ────────────────────────────────────────
local function ShowStep1()
  ShowOnlyStep(1)
  local c = wizard.steps[1]

  -- Logo
  local logo = c._logo
  if not logo then
    logo = c:CreateTexture(nil, "ARTWORK")
    logo:SetSize(64, 64)
    logo:SetTexture("Interface/AddOns/LucidUI/Assets/Logo.png")
    c._logo = logo
  end
  logo:Show(); logo:ClearAllPoints(); logo:SetPoint("TOP", c, "TOP", 0, -10)

  -- Welcome text
  local welcome = c._welcome
  if not welcome then
    welcome = c:CreateFontString(nil, "OVERLAY")
    welcome:SetFont(FONT, 12, ""); welcome:SetWidth(W - 60)
    welcome:SetJustifyH("CENTER")
    c._welcome = welcome
  end
  welcome:Show(); welcome:ClearAllPoints(); welcome:SetPoint("TOP", logo, "BOTTOM", 0, -14)
  local ar, ag, ab = NS.ChatGetAccentRGB()
  local hex = NS.RGBToHex(ar, ag, ab)
  welcome:SetText("Welcome to |cff" .. hex .. "LucidUI|r\n\nSelect your screen resolution to optimize sizes and scaling.")
  welcome:SetTextColor(0.75, 0.75, 0.8)

  -- Resolution label
  local resLabel = c._resLabel
  if not resLabel then
    resLabel = c:CreateFontString(nil, "OVERLAY")
    resLabel:SetFont(FONT, 10, ""); resLabel:SetTextColor(0.5, 0.5, 0.6)
    c._resLabel = resLabel
  end
  resLabel:Show(); resLabel:ClearAllPoints(); resLabel:SetPoint("TOP", welcome, "BOTTOM", 0, -24)
  resLabel:SetText("Resolution")

  -- 1440p button
  local btn1440 = c._btn1440
  if not btn1440 then
    btn1440 = MakeButton(c, "1440p", 140, 32)
    c._btn1440 = btn1440
  end
  btn1440:Show(); btn1440:ClearAllPoints()
  btn1440:SetPoint("TOP", resLabel, "BOTTOM", -80, -8)

  -- 1080p button
  local btn1080 = c._btn1080
  if not btn1080 then
    btn1080 = MakeButton(c, "1080p", 140, 32)
    c._btn1080 = btn1080
  end
  btn1080:Show(); btn1080:ClearAllPoints()
  btn1080:SetPoint("TOP", resLabel, "BOTTOM", 80, -8)

  -- Selection state
  local function UpdateResBtns()
    local r, g, b = NS.ChatGetAccentRGB()
    if selectedRes == "1440p" then
      btn1440:SetBackdropBorderColor(r, g, b, 0.8); btn1440._fs:SetTextColor(r, g, b)
      btn1080:SetBackdropBorderColor(0.25, 0.25, 0.35, 1); btn1080._fs:SetTextColor(0.9, 0.9, 0.9)
    else
      btn1080:SetBackdropBorderColor(r, g, b, 0.8); btn1080._fs:SetTextColor(r, g, b)
      btn1440:SetBackdropBorderColor(0.25, 0.25, 0.35, 1); btn1440._fs:SetTextColor(0.9, 0.9, 0.9)
    end
  end

  btn1440:SetScript("OnClick", function() selectedRes = "1440p"; UpdateResBtns() end)
  btn1080:SetScript("OnClick", function() selectedRes = "1080p"; UpdateResBtns() end)

  -- Override hover to keep selection visible
  btn1440:SetScript("OnLeave", UpdateResBtns)
  btn1080:SetScript("OnLeave", UpdateResBtns)

  UpdateResBtns()
end

-- ── Step 2: Module selection ────────────────────────────────────────────
local function ShowStep2()
  ShowOnlyStep(2)
  local c = wizard.steps[2]

  local header = c._modHeader
  if not header then
    header = c:CreateFontString(nil, "OVERLAY")
    header:SetFont(FONT, 12, ""); header:SetTextColor(0.75, 0.75, 0.8)
    header:SetWidth(W - 60); header:SetJustifyH("CENTER")
    c._modHeader = header
  end
  header:Show(); header:ClearAllPoints(); header:SetPoint("TOP", c, "TOP", 0, -8)
  header:SetText("Select which modules to enable.\nYou can change these later in settings.")

  -- Enable All button
  local enableAll = c._enableAll
  if not enableAll then
    enableAll = MakeButton(c, "Enable All", 90, 22)
    c._enableAll = enableAll
  end
  enableAll:Show(); enableAll:ClearAllPoints()
  enableAll:SetPoint("TOPRIGHT", c, "TOPRIGHT", -20, -8)
  enableAll:SetScript("OnClick", function()
    for _, m in ipairs(MODULES) do moduleStates[m.key] = true end
    if c._modRows then
      for _, row in ipairs(c._modRows) do
        if row._cb then row._cb:SetChecked(true) end
      end
    end
  end)

  -- Module checkboxes
  if not c._modRows then c._modRows = {} end
  local yOff = -50
  for i, m in ipairs(MODULES) do
    local row = c._modRows[i]
    if not row then
      row = CreateFrame("Button", nil, c)
      row:SetHeight(30)

      -- Hover background
      local hoverBg = row:CreateTexture(nil, "BACKGROUND")
      hoverBg:SetAllPoints(); hoverBg:SetColorTexture(1, 1, 1, 0)
      row._hoverBg = hoverBg

      -- Checkbox
      local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
      cb:SetSize(22, 22); cb:SetPoint("LEFT", 20, 0)
      cb:SetScript("OnClick", function(self)
        moduleStates[m.key] = self:GetChecked()
      end)
      row._cb = cb

      -- Label
      local lbl = row:CreateFontString(nil, "OVERLAY")
      lbl:SetFont(FONT, 12, ""); lbl:SetPoint("LEFT", cb, "RIGHT", 6, 0)
      local ar, ag, ab = NS.ChatGetAccentRGB()
      lbl:SetTextColor(ar, ag, ab)
      lbl:SetText(m.label)
      row._lbl = lbl

      -- Description
      local desc = row:CreateFontString(nil, "OVERLAY")
      desc:SetFont(FONT, 10, ""); desc:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
      desc:SetTextColor(0.45, 0.45, 0.55)
      desc:SetText("— " .. m.desc)
      row._desc = desc

      -- Click whole row to toggle
      row:SetScript("OnClick", function()
        cb:SetChecked(not cb:GetChecked())
        moduleStates[m.key] = cb:GetChecked()
      end)
      row:SetScript("OnEnter", function()
        local r, g, b = NS.ChatGetAccentRGB()
        hoverBg:SetColorTexture(r, g, b, 0.06)
      end)
      row:SetScript("OnLeave", function()
        hoverBg:SetColorTexture(1, 1, 1, 0)
      end)

      c._modRows[i] = row
    end
    row:Show(); row:ClearAllPoints()
    row:SetPoint("TOPLEFT", c, "TOPLEFT", 0, yOff)
    row:SetPoint("RIGHT", c, "RIGHT", 0, 0)
    row._cb:SetChecked(moduleStates[m.key])
    yOff = yOff - 34
  end
end

-- ── Step 3: Class Layout ────────────────────────────────────────────────
local function ShowStep3()
  ShowOnlyStep(3)
  local c = wizard.steps[3]

  local _, className = UnitClass("player")
  local classKey = className and strlower(className)
  local classDisplay = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[className] or className or "Unknown"
  local hasLayout = NS.ClassLayouts and classKey and NS.ClassLayouts[classKey]

  local ar, ag, ab = NS.ChatGetAccentRGB()
  local hex = NS.RGBToHex(ar, ag, ab)

  -- Header
  local header = c._clHeader
  if not header then
    header = c:CreateFontString(nil, "OVERLAY")
    header:SetFont(FONT, 12, ""); header:SetWidth(W - 60); header:SetJustifyH("CENTER")
    c._clHeader = header
  end
  header:Show(); header:ClearAllPoints(); header:SetPoint("TOP", c, "TOP", 0, -10)
  header:SetTextColor(0.75, 0.75, 0.8)

  if hasLayout then
    header:SetText(
      "Detected class: |cff" .. hex .. classDisplay .. "|r\n\n" ..
      "A cooldown layout for your class is available.\n" ..
      "This configures which spells appear in the Cooldown Viewer."
    )
  else
    header:SetText(
      "Detected class: |cff" .. hex .. classDisplay .. "|r\n\n" ..
      "No cooldown layout found for your class."
    )
  end

  -- Checkbox
  local cbRow = c._clRow
  if not cbRow then
    cbRow = CreateFrame("Button", nil, c)
    cbRow:SetHeight(30)

    local hoverBg = cbRow:CreateTexture(nil, "BACKGROUND")
    hoverBg:SetAllPoints(); hoverBg:SetColorTexture(1, 1, 1, 0)
    cbRow._hoverBg = hoverBg

    local cb = CreateFrame("CheckButton", nil, cbRow, "UICheckButtonTemplate")
    cb:SetSize(22, 22); cb:SetPoint("LEFT", 60, 0)
    cbRow._cb = cb

    local lbl = cbRow:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(FONT, 12, ""); lbl:SetPoint("LEFT", cb, "RIGHT", 6, 0)
    lbl:SetTextColor(ar, ag, ab)
    lbl:SetText("Apply Class Cooldown Layout")
    cbRow._lbl = lbl

    cbRow:SetScript("OnClick", function()
      cb:SetChecked(not cb:GetChecked())
      applyClassLayout = cb:GetChecked()
    end)
    cb:SetScript("OnClick", function(self) applyClassLayout = self:GetChecked() end)
    cbRow:SetScript("OnEnter", function() hoverBg:SetColorTexture(ar, ag, ab, 0.06) end)
    cbRow:SetScript("OnLeave", function() hoverBg:SetColorTexture(1, 1, 1, 0) end)

    c._clRow = cbRow
  end

  if hasLayout then
    cbRow:Show(); cbRow:ClearAllPoints()
    cbRow:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -120)
    cbRow:SetPoint("RIGHT", c, "RIGHT", 0, 0)
    cbRow._cb:SetChecked(applyClassLayout)
  else
    cbRow:Hide()
    applyClassLayout = false
  end
end

-- ── Step 4: Complete ────────────────────────────────────────────────────
local function ShowStep4()
  ShowOnlyStep(4)
  local c = wizard.steps[4]

  local done = c._doneText
  if not done then
    done = c:CreateFontString(nil, "OVERLAY")
    done:SetFont(FONT, 12, ""); done:SetWidth(W - 60)
    done:SetJustifyH("CENTER")
    c._doneText = done
  end
  done:Show(); done:ClearAllPoints(); done:SetPoint("TOP", c, "TOP", 0, -30)

  local ar, ag, ab = NS.ChatGetAccentRGB()
  local hex = NS.RGBToHex(ar, ag, ab)

  -- Build summary
  local enabled = {}
  for _, m in ipairs(MODULES) do
    if moduleStates[m.key] then enabled[#enabled + 1] = m.label end
  end
  local summary = #enabled > 0 and table.concat(enabled, ", ") or "None"

  done:SetTextColor(0.75, 0.75, 0.8)
  done:SetText(
    "Setup complete!\n\n" ..
    "Resolution: |cff" .. hex .. selectedRes .. "|r\n" ..
    "Modules: |cff" .. hex .. summary .. "|r\n" ..
    (applyClassLayout and ("Class Layout: |cff" .. hex .. "Yes|r\n") or "") ..
    "\nClick |cff" .. hex .. "Reload|r to apply your settings."
  )

  wizard.nextBtn._fs:SetText("Reload")
end

-- ── Show current step ───────────────────────────────────────────────────
function NS._WizardShowStep()
  if not wizard then return end
  wizard.stepText:SetText(currentStep .. " / " .. totalSteps)
  wizard.prevBtn:SetShown(currentStep > 1)

  if currentStep == totalSteps then
    wizard.nextBtn._fs:SetText("Reload")
  else
    wizard.nextBtn._fs:SetText("Continue")
  end

  if currentStep == 1 then ShowStep1()
  elseif currentStep == 2 then ShowStep2()
  elseif currentStep == 3 then ShowStep3()
  elseif currentStep == 4 then ShowStep4() end
end

-- ── Finish: apply settings + reload ─────────────────────────────────────
function NS._WizardFinish()
  if not LucidUIDB then LucidUIDB = {} end

  -- Apply resolution preset
  local preset = PRESETS[selectedRes]
  if preset then
    for k, v in pairs(preset) do
      LucidUIDB[k] = v
    end
  end
  LucidUIDB._resolution = selectedRes

  -- Apply module toggles
  for _, m in ipairs(MODULES) do
    LucidUIDB[m.key] = moduleStates[m.key]
  end

  -- Loot Tracker: enable own window + loot rolls when activated
  if moduleStates["ltEnabled"] then
    LucidUIDB["lootOwnWindow"] = true
  end

  -- Apply class cooldown layout
  if applyClassLayout then
    local _, className = UnitClass("player")
    local classKey = className and strlower(className)
    local classData = NS.ClassLayouts and classKey and NS.ClassLayouts[classKey]
    if classData and CooldownViewerSettings then
      local layoutManager = CooldownViewerSettings:GetLayoutManager()
      if layoutManager then
        -- Remove existing LucidUI layouts
        local classDisplay = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[className] or className
        local prefix = "LucidUI - " .. classDisplay
        if layoutManager.layouts then
          local toRemove = {}
          for layoutID, layout in pairs(layoutManager.layouts) do
            local name = layout and (layout.layoutName or layout.name)
            if name and name:find(prefix, 1, true) == 1 then
              toRemove[#toRemove + 1] = layoutID
            end
          end
          if #toRemove > 0 then
            table.sort(toRemove, function(a, b) return a > b end)
            for _, id in ipairs(toRemove) do layoutManager.layouts[id] = nil end
            local newLayouts = {}
            for _, layout in pairs(layoutManager.layouts) do
              if layout then newLayouts[#newLayouts + 1] = layout; layout.layoutID = #newLayouts end
            end
            for k in pairs(layoutManager.layouts) do layoutManager.layouts[k] = nil end
            for i, layout in ipairs(newLayouts) do layoutManager.layouts[i] = layout end
          end
        end
        -- Import new layouts
        local ok, layoutIDs = pcall(layoutManager.CreateLayoutsFromSerializedData, layoutManager, classData)
        if ok and layoutIDs and #layoutIDs > 0 then
          -- Try to match current spec
          local specIndex = GetSpecialization()
          local activeLayoutID = layoutIDs[1]
          if specIndex then
            local _, specName = GetSpecializationInfo(specIndex)
            if specName and layoutManager.layouts then
              for _, layoutID in ipairs(layoutIDs) do
                local layout = layoutManager.layouts[layoutID]
                if layout and layout.name and layout.name:find(specName) then
                  activeLayoutID = layoutID
                  break
                end
              end
            end
          end
          layoutManager:SetActiveLayoutByID(activeLayoutID)
          layoutManager:SaveLayouts()
        end
      end
    end
  end

  -- Mark install complete
  LucidUIDB._installComplete = true

  ReloadUI()
end

-- ── Public API ──────────────────────────────────────────────────────────
function NS.ShowInstallWizard()
  CreateWizard()
  currentStep = 1
  -- Reset module states
  for _, m in ipairs(MODULES) do moduleStates[m.key] = false end
  selectedRes = "1440p"
  NS._WizardShowStep()
  wizard:Show()
end

-- ── Show wizard on first install ────────────────────────────────────────
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
  C_Timer.After(1, function()
    if LucidUIDB and LucidUIDB._installComplete then return end
    if not LucidUIDB then LucidUIDB = {} end

    CreateWizard()
    currentStep = 1
    NS._WizardShowStep()
    wizard:Show()
  end)
end)