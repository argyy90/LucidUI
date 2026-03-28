-- LucidMeter — Settings tab for ChatOptions
local NS   = LucidUINS
local L    = LucidUIL
local DM   = NS.LucidMeter

function DM.SetupSettings(parent)
  local container = CreateFrame("Frame", nil, parent)

  local scrollFrame = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
  scrollFrame:SetPoint("TOPLEFT", 0, 0); scrollFrame:SetPoint("BOTTOMRIGHT", -24, 0)
  local scrollChild = CreateFrame("Frame", nil, scrollFrame)
  scrollChild:SetWidth(560)
  scrollFrame:SetScrollChild(scrollChild)
  scrollFrame:HookScript("OnSizeChanged", function(_, w) scrollChild:SetWidth(w - 24) end)
  if scrollFrame.ScrollBar then scrollFrame.ScrollBar:SetAlpha(0.5) end

  local allFrames = {}
  -- BUG FIX: track actual frame heights for correct scrollChild height calculation
  local allFrameHeights = {}

  local function DB(k) return NS.DB(k) end
  local function DBSet(k, v) NS.DBSet(k, v) end

  -- Helper: row with two checkboxes side by side
  local function MakeDualCheckboxRow(parent2, leftLabel, leftKey, leftCB_func, rightLabel, rightKey, rightCB_func, leftTip, rightTip)
    local row = CreateFrame("Frame", nil, parent2)
    row:SetHeight(28)
    local leftCB = NS.ChatGetCheckbox(row, leftLabel, 28, leftCB_func, leftTip)
    leftCB.option = leftKey
    leftCB:ClearAllPoints()
    leftCB:SetPoint("TOPLEFT", 0, 0); leftCB:SetSize(260, 28)
    local rightCB = NS.ChatGetCheckbox(row, rightLabel, 28, rightCB_func, rightTip)
    rightCB.option = rightKey
    rightCB:ClearAllPoints()
    rightCB:SetPoint("TOPLEFT", 260, 0); rightCB:SetSize(260, 28)
    row._left = leftCB; row._right = rightCB
    return row
  end

  -- ══ General ════════════════════════════════════════════════════════
  local hdrGeneral = NS.ChatGetHeader(scrollChild, "General")
  table.insert(allFrames, hdrGeneral)
  table.insert(allFrameHeights, hdrGeneral:GetHeight() or 30)

  local enableCB = NS.ChatGetCheckbox(scrollChild, "Enable LucidMeter", 28, function(state)
    DBSet("dmEnabled", state)
    if state then
      if DM.RegisterEvents then DM.RegisterEvents() end
      if DM.BuildDisplay then DM.BuildDisplay() end
    else
      if DM.UnregisterEvents then DM.UnregisterEvents() end
      if DM.windows then for _, w in ipairs(DM.windows) do w.frame:Hide() end end
    end
  end, "Show a damage meter window")
  enableCB.option = "dmEnabled"
  table.insert(allFrames, enableCB)
  table.insert(allFrameHeights, 28)

  -- Icons on Mouseover + Lock position
  local row0 = MakeDualCheckboxRow(scrollChild,
    "Icons on Mouseover", "dmIconsOnHover", function(state)
      DBSet("dmIconsOnHover", state)
      if DM.windows then
        for _, w in ipairs(DM.windows) do
          if w.frame._titleIcons then
            for _, ic in ipairs(w.frame._titleIcons) do ic:SetShown(not state) end
          end
        end
      end
    end,
    "Lock position", "dmLocked", function(state)
      DBSet("dmLocked", state)
      if DM.windows then
        for _, w in ipairs(DM.windows) do
          if w.frame and w.frame._resizeBtn then w.frame._resizeBtn:SetShown(not state) end
        end
      end
    end,
    "Only show titlebar icons when hovering over the window",
    "Prevent moving and resizing the meter windows"
  )
  table.insert(allFrames, row0)
  table.insert(allFrameHeights, 28)

  -- Show only in combat + Always Show Self
  local row1 = MakeDualCheckboxRow(scrollChild,
    "Show only in combat", "dmShowInCombatOnly", function(state)
      DBSet("dmShowInCombatOnly", state)
    end,
    "Always show self", "dmAlwaysShowSelf", function(state)
      DBSet("dmAlwaysShowSelf", state)
      if DM.UpdateDisplay then DM.UpdateDisplay() end
    end,
    "Hide the meter windows when out of combat",
    "Show your bar at the bottom even if not in the top list"
  )
  table.insert(allFrames, row1)
  table.insert(allFrameHeights, 28)

  -- Show Rank + Show Percent
  local row2g = MakeDualCheckboxRow(scrollChild,
    "Show Rank", "dmShowRank", function(state)
      DBSet("dmShowRank", state)
      if DM.UpdateDisplay then DM.UpdateDisplay() end
    end,
    "Show %", "dmShowPercent", function(state)
      DBSet("dmShowPercent", state)
      if DM.UpdateDisplay then DM.UpdateDisplay() end
    end,
    "Show position numbers and a crown for #1",
    "Show each player's percentage of total on the right side"
  )
  table.insert(allFrames, row2g)
  table.insert(allFrameHeights, 28)

  -- Auto Reset dropdown (own row)
  local resetRow = CreateFrame("Frame", nil, scrollChild); resetRow:SetHeight(58)
  local resetDD = NS.ChatGetDropdown(resetRow, "Auto Reset", function(value)
    return (DB("dmAutoReset") or "off") == value
  end, function(value)
    DBSet("dmAutoReset", value)
  end)
  resetDD:Init({"Off", "Enter Instance", "Leave Instance", "Both"}, {"off", "enter", "leave", "both"})
  resetDD:ClearAllPoints(); resetDD:SetPoint("LEFT", resetRow, "LEFT", 0, 0); resetDD:SetWidth(260)
  table.insert(allFrames, resetRow)
  table.insert(allFrameHeights, 58)

  -- ══ NEW FEATURE: Click-Through ════════════════════════════════════
  -- Inspired by Details' clickthrough_window + clickthrough_incombatonly
  local hdrCT = NS.ChatGetHeader(scrollChild, "Click-Through")
  table.insert(allFrames, hdrCT)
  table.insert(allFrameHeights, hdrCT:GetHeight() or 30)

  local ctRow = MakeDualCheckboxRow(scrollChild,
    "Enable click-through", "dmClickThrough", function(state)
      DBSet("dmClickThrough", state)
      if DM.windows then
        for _, w in ipairs(DM.windows) do
          local combatOnly = DB("dmClickThroughCombat")
          local active = state and (not combatOnly or DM.inCombat)
          w.frame:EnableMouse(not active)
        end
      end
    end,
    "In combat only", "dmClickThroughCombat", function(state)
      DBSet("dmClickThroughCombat", state)
      if DM.windows then
        for _, w in ipairs(DM.windows) do
          local enabled = DB("dmClickThrough")
          local active = enabled and (not state or DM.inCombat)
          w.frame:EnableMouse(not active)
        end
      end
    end,
    "Mouse clicks pass through the meter window (useful in raids)",
    "Enable click-through only during combat — out of combat you can still interact"
  )
  table.insert(allFrames, ctRow)
  table.insert(allFrameHeights, 28)

  -- ══ Text ═════════════════════════════════════════════════════════
  local hdrText = NS.ChatGetHeader(scrollChild, "Text")
  table.insert(allFrames, hdrText)
  table.insert(allFrameHeights, hdrText:GetHeight() or 30)

  local function MakeColorRow(parent2, label, dbKey, defaultColor, applyFunc)
    local row = CreateFrame("Frame", nil, parent2); row:SetHeight(24)
    local btn = CreateFrame("Button", nil, row)
    btn:SetAllPoints()
    local swatch = btn:CreateTexture(nil, "OVERLAY")
    swatch:SetSize(13, 13); swatch:SetPoint("LEFT", 4, 0)
    local cur = DB(dbKey) or defaultColor
    swatch:SetColorTexture(cur.r, cur.g, cur.b, 1)
    local lbl = btn:CreateFontString(nil, "OVERLAY")
    lbl:SetFont("Fonts/FRIZQT__.TTF", 11, ""); lbl:SetPoint("LEFT", swatch, "RIGHT", 6, 0)
    lbl:SetTextColor(0.78, 0.78, 0.78); lbl:SetText(label)
    btn:SetScript("OnEnter", function() local a,b,c = NS.ChatGetAccentRGB(); lbl:SetTextColor(a,b,c) end)
    btn:SetScript("OnLeave", function() lbl:SetTextColor(0.78, 0.78, 0.78) end)
    btn:SetScript("OnClick", function()
      local c = DB(dbKey) or defaultColor
      ColorPickerFrame:SetupColorPickerAndShow({
        r = c.r, g = c.g, b = c.b,
        swatchFunc = function()
          local r, g, b = ColorPickerFrame:GetColorRGB()
          DBSet(dbKey, {r=r, g=g, b=b}); swatch:SetColorTexture(r, g, b, 1)
          if applyFunc then applyFunc(r, g, b) end
        end,
        cancelFunc = function(prev)
          DBSet(dbKey, {r=prev.r, g=prev.g, b=prev.b}); swatch:SetColorTexture(prev.r, prev.g, prev.b, 1)
          if applyFunc then applyFunc(prev.r, prev.g, prev.b) end
        end,
      })
    end)
    row._swatch = swatch
    return row
  end

  local fontShadow = NS.ChatGetSlider(scrollChild, "Font Shadow", 0, 3, "%.1f", function(value)
    DBSet("dmFontShadow", value)
    if DM.UpdateDisplay then DM.UpdateDisplay() end
    if DM.windows then
      for _, w in ipairs(DM.windows) do
        if w.titleText then
          if value > 0 then
            w.titleText:SetShadowOffset(value, -value); w.titleText:SetShadowColor(0, 0, 0, 1)
          else
            w.titleText:SetShadowOffset(0, 0)
          end
        end
      end
    end
  end)
  fontShadow.option = "dmFontShadow"
  table.insert(allFrames, fontShadow)
  table.insert(allFrameHeights, fontShadow:GetHeight() or 40)

  local textRow = MakeDualCheckboxRow(scrollChild,
    "Text Outline", "dmTextOutline", function(state)
      DBSet("dmTextOutline", state)
      if DM.UpdateDisplay then DM.UpdateDisplay() end
      if DM.windows then
        local fp  = NS.GetFontPath(NS.DB("dmFont"))
        local fts = NS.DB("dmTitleFontSize") or 10
        local flags = state and "OUTLINE" or ""
        for _, w2 in ipairs(DM.windows) do
          if w2.titleText then
            w2.titleText:SetFont(fp, fts, flags)
          end
        end
      end
    end,
    "Show server name", "dmShowRealm", function(state)
      DBSet("dmShowRealm", state)
      if DM.UpdateDisplay then DM.UpdateDisplay() end
    end,
    "Add an outline to bar and title text for better readability",
    "Show realm names for other players (your own name stays short)"
  )
  table.insert(allFrames, textRow)
  table.insert(allFrameHeights, 28)

  local txtColorRow = CreateFrame("Frame", nil, scrollChild); txtColorRow:SetHeight(24)
  local COL_W_T = 170
  local COL_GAP_T = 5
  local TOTAL_W_T = COL_W_T * 3 + COL_GAP_T * 2
  local COL1_T = -TOTAL_W_T / 2
  local COL2_T = COL1_T + COL_W_T + COL_GAP_T
  local COL3_T = COL2_T + COL_W_T + COL_GAP_T

  local titleColorPicker = MakeColorRow(txtColorRow, "Title Color", "dmTitleColor", {r=1, g=1, b=1}, function(r, g, b)
    if DM.windows then for _, w in ipairs(DM.windows) do if w.titleText then w.titleText:SetTextColor(r, g, b) end end end
  end)
  titleColorPicker:ClearAllPoints()
  titleColorPicker:SetPoint("LEFT", txtColorRow, "CENTER", COL1_T, 0); titleColorPicker:SetSize(COL_W_T, 24)

  local textColorPicker = MakeColorRow(txtColorRow, "Text Color", "dmTextColor", {r=1, g=1, b=1}, function()
    if DM.UpdateDisplay then DM.UpdateDisplay() end
  end)
  textColorPicker:ClearAllPoints()
  textColorPicker:SetPoint("LEFT", txtColorRow, "CENTER", COL2_T, 0); textColorPicker:SetSize(COL_W_T, 24)

  local barColorPicker = MakeColorRow(txtColorRow, "Bar Color", "dmBarColor", {r=0.5, g=0.5, b=0.5}, function()
    if DM.UpdateDisplay then DM.UpdateDisplay() end
  end)
  barColorPicker:ClearAllPoints()
  barColorPicker:SetPoint("LEFT", txtColorRow, "CENTER", COL3_T, 0); barColorPicker:SetSize(COL_W_T, 24)

  table.insert(allFrames, txtColorRow)
  table.insert(allFrameHeights, 24)

  -- ══ Windows ══════════════════════════════════════════════════════════
  local hdrWindows = NS.ChatGetHeader(scrollChild, "Windows")
  table.insert(allFrames, hdrWindows)
  table.insert(allFrameHeights, hdrWindows:GetHeight() or 30)

  local winRow = CreateFrame("Frame", nil, scrollChild)
  winRow:SetHeight(28)
  local BTN_W = 200
  local BTN_GAP = 10

  local function MakeStyledBtn(parent, text)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(BTN_W, 22)
    btn:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
    btn:SetBackdropColor(0.12, 0.12, 0.12, 1)
    btn:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    local lbl = btn:CreateFontString(nil, "OVERLAY")
    lbl:SetFont("Fonts/FRIZQT__.TTF", 10, "")
    lbl:SetPoint("CENTER")
    lbl:SetText(text)
    lbl:SetTextColor(0.85, 0.85, 0.85)
    btn._label = lbl
    btn:SetScript("OnEnter", function()
      local ar, ag, ab = NS.ChatGetAccentRGB()
      btn:SetBackdropBorderColor(ar, ag, ab, 1)
      lbl:SetTextColor(1, 1, 1)
    end)
    btn:SetScript("OnLeave", function()
      btn:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
      lbl:SetTextColor(0.85, 0.85, 0.85)
    end)
    return btn
  end

  local newWinBtn = MakeStyledBtn(winRow, "New Window")
  newWinBtn:SetPoint("RIGHT", winRow, "CENTER", -(BTN_GAP / 2), 0)
  newWinBtn:SetScript("OnClick", function()
    if DM.CreateNewWindow then DM.CreateNewWindow() end
  end)

  local closeWinBtn = MakeStyledBtn(winRow, "Close Window")
  closeWinBtn:SetPoint("LEFT", winRow, "CENTER", (BTN_GAP / 2), 0)

  local closeArrow = closeWinBtn:CreateFontString(nil, "OVERLAY")
  closeArrow:SetFont("Fonts/FRIZQT__.TTF", 9, "")
  closeArrow:SetPoint("RIGHT", -6, 0)
  closeArrow:SetTextColor(0.5, 0.5, 0.5)
  closeArrow:SetText("v")

  local closePopup = nil
  closeWinBtn:SetScript("OnClick", function(self)
    if closePopup then closePopup:Hide(); closePopup = nil; return end

    local extra = DM.windows
    local items = {}
    for _, w in ipairs(extra) do
      if w.id ~= 1 then
        local label = "Window " .. w.id
        if DM.METER_TYPES then
          for _, mt in ipairs(DM.METER_TYPES) do
            if mt.id == w.meterType then label = "Window " .. w.id .. "  —  " .. mt.label; break end
          end
        end
        items[#items + 1] = {id = w.id, text = label}
      end
    end

    if #items == 0 then
      items[#items + 1] = {text = "|cff808080No extra windows|r", disabled = true}
    end

    closePopup = CreateFrame("Frame", nil, self, "BackdropTemplate")
    closePopup:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
    closePopup:SetBackdropColor(0.06, 0.06, 0.06, 0.97)
    closePopup:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    closePopup:SetFrameStrata("TOOLTIP")
    closePopup:SetClampedToScreen(true)

    local ITEM_H = 20
    local totalH = 0

    for _, item in ipairs(items) do
      local row = CreateFrame("Button", nil, closePopup)
      row:SetHeight(ITEM_H)
      row:SetPoint("TOPLEFT", 2, -(totalH))
      row:SetPoint("TOPRIGHT", -2, -(totalH))
      local hl = row:CreateTexture(nil, "BACKGROUND")
      hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.06); hl:Hide()
      local lbl = row:CreateFontString(nil, "OVERLAY")
      lbl:SetFont("Fonts/FRIZQT__.TTF", 10, "")
      lbl:SetPoint("LEFT", 8, 0)
      lbl:SetText(item.text)
      lbl:SetTextColor(0.85, 0.85, 0.85)
      if not item.disabled then
        row:SetScript("OnEnter", function() hl:Show(); lbl:SetTextColor(1, 0.4, 0.4) end)
        row:SetScript("OnLeave", function() hl:Hide(); lbl:SetTextColor(0.85, 0.85, 0.85) end)
        local capturedID = item.id
        row:SetScript("OnClick", function()
          if DM.CloseWindow then DM.CloseWindow(capturedID) end
          closePopup:Hide(); closePopup = nil
        end)
      end
      totalH = totalH + ITEM_H
    end

    closePopup:SetSize(BTN_W, totalH + 4)
    closePopup:ClearAllPoints()
    closePopup:SetPoint("TOP", self, "BOTTOM", 0, -2)
    closePopup:Show()

    local closeTicker = C_Timer.NewTicker(0.3, function()
      if not closePopup or not closePopup:IsShown() then return end
      if not closePopup:IsMouseOver() and not self:IsMouseOver() then
        closePopup:Hide(); closePopup = nil
      end
    end)
    closePopup:HookScript("OnHide", function() closeTicker:Cancel() end)
  end)
  table.insert(allFrames, winRow)
  table.insert(allFrameHeights, 28)

  -- ══ Appearance ═════════════════════════════════════════════════════
  local hdrAppearance = NS.ChatGetHeader(scrollChild, "Appearance")
  table.insert(allFrames, hdrAppearance)
  table.insert(allFrameHeights, hdrAppearance:GetHeight() or 30)

  local ddRow = CreateFrame("Frame", nil, scrollChild); ddRow:SetHeight(58)

  local fontDD = NS.ChatGetDropdown(ddRow, "Font", function(value)
    return (DB("dmFont") or "Friz Quadrata") == value
  end, function(value)
    DBSet("dmFont", value)
    local fp = NS.GetFontPath(value)
    if DM.windows then for _, w in ipairs(DM.windows) do if w.titleText then w.titleText:SetFont(fp, NS.DB("dmTitleFontSize") or 10, "") end end end
    if DM.UpdateDisplay then DM.UpdateDisplay() end
  end)
  fontDD:Init({"Friz Quadrata"}, {"Friz Quadrata"}, 20 * 15)
  local COL_W = 170
  local COL_GAP = 5
  local TOTAL_W = COL_W * 3 + COL_GAP * 2
  local COL1 = -TOTAL_W / 2
  local COL2 = COL1 + COL_W + COL_GAP
  local COL3 = COL2 + COL_W + COL_GAP

  fontDD:ClearAllPoints(); fontDD:SetPoint("LEFT", ddRow, "CENTER", COL1, 0); fontDD:SetWidth(COL_W)

  local iconDD = NS.ChatGetDropdown(ddRow, "Icon", function(value)
    return (DB("dmIconMode") or "spec") == value
  end, function(value)
    DBSet("dmIconMode", value); if DM.UpdateDisplay then DM.UpdateDisplay() end
  end)
  iconDD:Init({"Spec", "Class", "None"}, {"spec", "class", "none"})
  iconDD:ClearAllPoints(); iconDD:SetPoint("LEFT", ddRow, "CENTER", COL2, 0); iconDD:SetWidth(COL_W)

  local valDD = NS.ChatGetDropdown(ddRow, "Values", function(value)
    return (DB("dmValueFormat") or "both") == value
  end, function(value)
    DBSet("dmValueFormat", value); if DM.UpdateDisplay then DM.UpdateDisplay() end
  end)
  valDD:Init({"Total | DPS", "Total", "DPS"}, {"both", "total", "persec"})
  valDD:ClearAllPoints(); valDD:SetPoint("LEFT", ddRow, "CENTER", COL3, 0); valDD:SetWidth(COL_W)

  table.insert(allFrames, ddRow)
  table.insert(allFrameHeights, 58)

  local ddRow2 = CreateFrame("Frame", nil, scrollChild); ddRow2:SetHeight(58)
  local barTexNames, barTexValues = {}, {}
  for _, bt in ipairs(NS.GetLSMStatusBars()) do
    barTexNames[#barTexNames + 1] = bt.label; barTexValues[#barTexValues + 1] = bt.label
  end
  local barTexDD = NS.ChatGetDropdown(ddRow2, "Bar Texture", function(value)
    return (DB("dmBarTexture") or "Flat") == value
  end, function(value)
    DBSet("dmBarTexture", value)
    if DM.UpdateDisplay then DM.UpdateDisplay() end
  end)
  barTexDD:Init(barTexNames, barTexValues, 20 * 15)
  barTexDD:ClearAllPoints(); barTexDD:SetPoint("LEFT", ddRow2, "CENTER", COL1, 0); barTexDD:SetWidth(COL_W)

  local highlightDD = NS.ChatGetDropdown(ddRow2, "Bar Highlight", function(value)
    return (DB("dmBarHighlight") or "none") == value
  end, function(value)
    DBSet("dmBarHighlight", value)
    if DM.UpdateDisplay then DM.UpdateDisplay() end
  end)
  highlightDD:Init({"None", "Border", "Bar"}, {"none", "border", "bar"})
  highlightDD:ClearAllPoints(); highlightDD:SetPoint("LEFT", ddRow2, "CENTER", COL2, 0); highlightDD:SetWidth(COL_W)

  local barBgDD = NS.ChatGetDropdown(ddRow2, "Bar Background", function(value)
    return (DB("dmBarBgTexture") or "Flat") == value
  end, function(value)
    DBSet("dmBarBgTexture", value)
    if DM.UpdateDisplay then DM.UpdateDisplay() end
  end)
  barBgDD:Init(barTexNames, barTexValues, 20 * 15)
  barBgDD:ClearAllPoints(); barBgDD:SetPoint("LEFT", ddRow2, "CENTER", COL3, 0); barBgDD:SetWidth(COL_W)
  table.insert(allFrames, ddRow2)
  table.insert(allFrameHeights, 58)

  local classColorCB = NS.ChatGetCheckbox(scrollChild, "Class colors", 24, function(state)
    DBSet("dmClassColors", state)
    if DM.UpdateDisplay then DM.UpdateDisplay() end
  end, "Color bars by player class instead of a fixed color")
  classColorCB.option = "dmClassColors"
  table.insert(allFrames, classColorCB)
  table.insert(allFrameHeights, 24)

  -- NEW FEATURE: Total bar checkbox (from Details totalbar_enabled)
  local totalBarCB = NS.ChatGetCheckbox(scrollChild, "Show total bar", 24, function(state)
    DBSet("dmShowTotalBar", state)
    if DM.UpdateDisplay then DM.UpdateDisplay() end
  end, "Show a bar at the bottom of the list with the combined total of all players")
  totalBarCB.option = "dmShowTotalBar"
  table.insert(allFrames, totalBarCB)
  table.insert(allFrameHeights, 24)

  local row2 = CreateFrame("Frame", nil, scrollChild); row2:SetHeight(28)
  local accentCB = NS.ChatGetCheckbox(row2, "Accent line", 28, function(state)
    DBSet("dmAccentLine", state)
    if DM.windows then for _, w in ipairs(DM.windows) do if w.frame._accentLine then w.frame._accentLine:SetShown(state) end end end
  end, "Show a colored accent line below the title bar")
  accentCB.option = "dmAccentLine"; accentCB:ClearAllPoints()
  accentCB:SetPoint("LEFT", row2, "CENTER", COL1, 0); accentCB:SetSize(COL_W, 28)

  local winBorderCB = NS.ChatGetCheckbox(row2, "Window border", 28, function(state)
    DBSet("dmWindowBorder", state)
    if DM.windows then for _, w in ipairs(DM.windows) do w.frame:SetBackdropBorderColor(0.15, 0.15, 0.15, state and 1 or 0) end end
  end, "Show a thin border around the meter window")
  winBorderCB.option = "dmWindowBorder"; winBorderCB:ClearAllPoints()
  winBorderCB:SetPoint("LEFT", row2, "CENTER", COL2, 0); winBorderCB:SetSize(COL_W, 28)

  local titleBorderCB = NS.ChatGetCheckbox(row2, "Title border", 28, function(state)
    DBSet("dmTitleBorder", state)
    if DM.windows then for _, w in ipairs(DM.windows) do if w.frame._titleBorder then w.frame._titleBorder:SetShown(state) end end end
  end, "Show a separator line between title bar and bars")
  titleBorderCB.option = "dmTitleBorder"; titleBorderCB:ClearAllPoints()
  titleBorderCB:SetPoint("LEFT", row2, "CENTER", COL3, 0); titleBorderCB:SetSize(COL_W, 28)
  table.insert(allFrames, row2)
  table.insert(allFrameHeights, 28)

  -- ══ Bars ═══════════════════════════════════════════════════════════
  local hdrBars = NS.ChatGetHeader(scrollChild, "Bars")
  table.insert(allFrames, hdrBars)
  table.insert(allFrameHeights, hdrBars:GetHeight() or 30)

  local barHeight = NS.ChatGetSlider(scrollChild, "Bar Height", 12, 28, "%dpx", function(value)
    DBSet("dmBarHeight", value); if DM.UpdateDisplay then DM.UpdateDisplay() end
  end)
  barHeight.option = "dmBarHeight"
  table.insert(allFrames, barHeight)
  table.insert(allFrameHeights, barHeight:GetHeight() or 40)

  local barSpacing = NS.ChatGetSlider(scrollChild, "Bar Spacing", 0, 4, "%dpx", function(value)
    DBSet("dmBarSpacing", value); if DM.UpdateDisplay then DM.UpdateDisplay() end
  end)
  barSpacing.option = "dmBarSpacing"
  table.insert(allFrames, barSpacing)
  table.insert(allFrameHeights, barSpacing:GetHeight() or 40)

  local fontSize = NS.ChatGetSlider(scrollChild, "Bar Font Size", 8, 16, "%dpt", function(value)
    DBSet("dmFontSize", value); if DM.UpdateDisplay then DM.UpdateDisplay() end
  end)
  fontSize.option = "dmFontSize"
  table.insert(allFrames, fontSize)
  table.insert(allFrameHeights, fontSize:GetHeight() or 40)

  local titleFontSize = NS.ChatGetSlider(scrollChild, "Title Font Size", 8, 16, "%dpt", function(value)
    DBSet("dmTitleFontSize", value)
    local fp = NS.GetFontPath(NS.DB("dmFont"))
    if DM.windows then for _, w in ipairs(DM.windows) do if w.titleText then w.titleText:SetFont(fp, value, "") end end end
  end)
  titleFontSize.option = "dmTitleFontSize"
  table.insert(allFrames, titleFontSize)
  table.insert(allFrameHeights, titleFontSize:GetHeight() or 40)

  local barBright = NS.ChatGetSlider(scrollChild, "Bar Brightness", 10, 100, "%d%%", function(value)
    DBSet("dmBarBrightness", value / 100)
    if DM.UpdateDisplay then DM.UpdateDisplay() end
  end)
  barBright.option = "dmBarBrightness"
  table.insert(allFrames, barBright)
  table.insert(allFrameHeights, barBright:GetHeight() or 40)

  -- ══ Transparency ═══════════════════════════════════════════════════
  local hdrTrans = NS.ChatGetHeader(scrollChild, "Transparency")
  table.insert(allFrames, hdrTrans)
  table.insert(allFrameHeights, hdrTrans:GetHeight() or 30)

  local bgAlpha = NS.ChatGetSlider(scrollChild, "Window", 0, 100, "%d%%", function(value)
    DBSet("dmBgAlpha", value / 100)
    if DM.windows then for _, w in ipairs(DM.windows) do if w.frame._bodyBg then w.frame._bodyBg:SetAlpha(value / 100) end end end
  end)
  table.insert(allFrames, bgAlpha)
  table.insert(allFrameHeights, bgAlpha:GetHeight() or 40)

  local titleAlpha = NS.ChatGetSlider(scrollChild, "Title Bar", 0, 100, "%d%%", function(value)
    DBSet("dmTitleAlpha", value / 100)
    if DM.windows then for _, w in ipairs(DM.windows) do if w.frame._titleBg then w.frame._titleBg:SetAlpha(value / 100) end end end
  end)
  table.insert(allFrames, titleAlpha)
  table.insert(allFrameHeights, titleAlpha:GetHeight() or 40)

  -- ══ Performance ════════════════════════════════════════════════════
  local hdrPerf = NS.ChatGetHeader(scrollChild, "Performance")
  table.insert(allFrames, hdrPerf)
  table.insert(allFrameHeights, hdrPerf:GetHeight() or 30)

  local updateInt = NS.ChatGetSlider(scrollChild, "Update Interval", 100, 2000, "%dms", function(value)
    DBSet("dmUpdateInterval", value / 1000)
  end)
  table.insert(allFrames, updateInt)
  table.insert(allFrameHeights, updateInt:GetHeight() or 40)

  -- ══ Layout ═════════════════════════════════════════════════════════
  -- BUG FIX: compute actual total height from per-frame sizes, not a hardcoded 40px multiplier
  -- previously: #allFrames * 40 — caused dropdown rows (58px), headers (30px) etc. to be cut off
  local totalH = 0
  for i, f in ipairs(allFrames) do
    f:ClearAllPoints()
    if i == 1 then
      f:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
      f:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, 0)
    else
      f:SetPoint("TOPLEFT", allFrames[i-1], "BOTTOMLEFT", 0, 0)
      f:SetPoint("TOPRIGHT", allFrames[i-1], "BOTTOMRIGHT", 0, 0)
    end
    totalH = totalH + (allFrameHeights[i] or 40)
  end
  -- Add a small bottom padding so the last slider isn't right against the edge
  scrollChild:SetHeight(math.max(totalH + 16, 1))

  -- ══ OnShow ═════════════════════════════════════════════════════════
  container:SetScript("OnShow", function()
    local fontNames2, fontValues2 = {}, {}
    for _, f in ipairs(NS.GetLSMFonts()) do
      fontNames2[#fontNames2 + 1] = f.label; fontValues2[#fontValues2 + 1] = f.label
    end
    fontDD:Init(fontNames2, fontValues2, 20 * 15)
    if fontDD.SetValue then fontDD:SetValue() end
    enableCB:SetValue(DB("dmEnabled") == true)
    row0._left:SetValue(DB("dmIconsOnHover") == true)
    row0._right:SetValue(DB("dmLocked") == true)
    row1._left:SetValue(DB("dmShowInCombatOnly") == true)
    row1._right:SetValue(DB("dmAlwaysShowSelf") ~= false)
    row2g._left:SetValue(DB("dmShowRank") == true)
    row2g._right:SetValue(DB("dmShowPercent") == true)
    if resetDD.SetValue then resetDD:SetValue() end
    -- NEW: click-through settings
    ctRow._left:SetValue(DB("dmClickThrough") == true)
    ctRow._right:SetValue(DB("dmClickThroughCombat") == true)
    local fsVal = DB("dmFontShadow") or 0
    if type(fsVal) == "boolean" then fsVal = fsVal and 1.5 or 0 end
    if fontShadow.SetValue then fontShadow:SetValue(fsVal) end
    textRow._left:SetValue(DB("dmTextOutline") == true)
    textRow._right:SetValue(DB("dmShowRealm") == true)
    classColorCB:SetValue(DB("dmClassColors") ~= false)
    totalBarCB:SetValue(DB("dmShowTotalBar") == true)  -- NEW
    local tcCur = DB("dmTitleColor") or {r=1, g=1, b=1}
    if titleColorPicker._swatch then titleColorPicker._swatch:SetColorTexture(tcCur.r, tcCur.g, tcCur.b, 1) end
    local txCur = DB("dmTextColor") or {r=1, g=1, b=1}
    if textColorPicker._swatch then textColorPicker._swatch:SetColorTexture(txCur.r, txCur.g, txCur.b, 1) end
    local bcCur = DB("dmBarColor") or {r=0.5, g=0.5, b=0.5}
    if barColorPicker._swatch then barColorPicker._swatch:SetColorTexture(bcCur.r, bcCur.g, bcCur.b, 1) end
    accentCB:SetValue(DB("dmAccentLine") ~= false)
    winBorderCB:SetValue(DB("dmWindowBorder") ~= false)
    titleBorderCB:SetValue(DB("dmTitleBorder") ~= false)
    if barHeight.SetValue then barHeight:SetValue(DB("dmBarHeight") or 18) end
    if barSpacing.SetValue then barSpacing:SetValue(DB("dmBarSpacing") or 1) end
    if fontSize.SetValue then fontSize:SetValue(DB("dmFontSize") or 11) end
    if titleFontSize.SetValue then titleFontSize:SetValue(DB("dmTitleFontSize") or 10) end
    if barBright.SetValue then barBright:SetValue((DB("dmBarBrightness") or 0.70) * 100) end
    if updateInt.SetValue then updateInt:SetValue((DB("dmUpdateInterval") or 0.3) * 1000) end
    if bgAlpha.SetValue then bgAlpha:SetValue((DB("dmBgAlpha") or 0.92) * 100) end
    if titleAlpha.SetValue then titleAlpha:SetValue((DB("dmTitleAlpha") or 1) * 100) end
    if highlightDD.SetValue then highlightDD:SetValue() end
    if barTexDD.SetValue then barTexDD:SetValue() end
    if barBgDD.SetValue then barBgDD:SetValue() end
  end)

  return container
end
