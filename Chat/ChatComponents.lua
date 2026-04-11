-- LucidUI ChatComponents.lua
-- Reusable UI building blocks for the chat settings dialog.
-- Matches the layout and style of the reference addon.

local NS   = LucidUINS
local CYAN = NS.CYAN

NS.chatOptCheckboxFills  = {}
NS.chatOptAccentLabels   = {}
NS.chatOptDropdownArrows = {}
NS.chatOptSliderThumbs   = {}
NS.chatOptAccentTextures = {}   -- {tex, alpha} or {tex, isFS=true} for card stripes/titles

local function GetAccentRGB()
  -- NS.CYAN is always kept in sync with the active accent color
  return CYAN[1], CYAN[2], CYAN[3]
end

local function GetAccentHex()
  local ar, ag, ab = GetAccentRGB()
  return string.format("%02x%02x%02x", ar * 255, ag * 255, ab * 255)
end

NS.ChatGetAccentRGB = GetAccentRGB
NS.ChatGetAccentHex = GetAccentHex

-- No-op: use WoW default radio/checkbox icons
function NS.SkinMenuElement() end

-- ── Checkbox ─────────────────────────────────────────────────────────

function NS.ChatGetCheckbox(parent, label, spacing, callback, tooltip)
  local cr, cg, cb = GetAccentRGB()
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetHeight(22)
  holder:SetPoint("LEFT", parent, "LEFT", 30, 0)
  holder:SetPoint("RIGHT", parent, "RIGHT", -15, 0)

  local btn = CreateFrame("Button", nil, holder)
  btn:SetSize(13, 13)
  btn:SetPoint("LEFT", 20, 0)

  local border = btn:CreateTexture(nil, "BACKGROUND")
  border:SetAllPoints()
  border:SetColorTexture(0.28, 0.28, 0.28, 1)

  local fill = btn:CreateTexture(nil, "ARTWORK")
  fill:SetPoint("TOPLEFT", 2, -2)
  fill:SetPoint("BOTTOMRIGHT", -2, 2)
  fill:SetColorTexture(cr, cg, cb, 1)
  fill:Hide()
  table.insert(NS.chatOptCheckboxFills, fill)

  local lbl = holder:CreateFontString(nil, "OVERLAY")
  lbl:SetFont(NS.FONT, 11, "")
  lbl:SetPoint("LEFT", btn, "RIGHT", 6, 0)
  lbl:SetTextColor(1, 1, 1, 1)
  lbl:SetText(label)

  local checked = false

  function holder:SetValue(value)
    checked = value and true or false
    fill:SetShown(checked)
  end

  local highlight = holder:CreateTexture(nil, "BACKGROUND")
  highlight:SetAllPoints(holder)
  highlight:SetColorTexture(1, 1, 1, 0.05)
  highlight:Hide()
  holder._highlight = highlight

  local hit = CreateFrame("Frame", nil, holder)
  hit:SetAllPoints(holder)
  holder._hit = hit
  hit:EnableMouse(true)
  hit:SetFrameLevel(btn:GetFrameLevel() + 3)
  hit:SetScript("OnMouseDown", function()
    checked = not checked
    fill:SetShown(checked)
    callback(checked)
  end)
  hit:SetScript("OnEnter", function()
    highlight:Show()
    local hr, hg, hb = GetAccentRGB()
    border:SetColorTexture(hr, hg, hb, 0.5)
    if tooltip then
      GameTooltip:SetOwner(hit, "ANCHOR_RIGHT")
      GameTooltip:SetText(tooltip, 0.75, 0.75, 0.75, 1, true)
      GameTooltip:Show()
    end
  end)
  hit:SetScript("OnLeave", function()
    highlight:Hide()
    border:SetColorTexture(0.28, 0.28, 0.28, 1)
    if tooltip then GameTooltip:Hide() end
  end)

  return holder
end

-- ── Section Header ───────────────────────────────────────────────────

function NS.ChatGetHeader(parent, text)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetPoint("LEFT", 30, 0)
  holder:SetPoint("RIGHT", -30, 0)
  holder:SetHeight(20)

  holder.text = holder:CreateFontString(nil, "OVERLAY")
  holder.text:SetFont(NS.FONT, 11, "")
  holder.text:SetText("|cff" .. GetAccentHex() .. ">|r |cff808080" .. text .. "|r")
  holder.text:SetPoint("LEFT", 20, 4)
  holder.text:SetJustifyH("LEFT")
  table.insert(NS.chatOptAccentLabels, {fs = holder.text, rawText = text})

  local line = holder:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(0.18, 0.18, 0.18, 1)
  line:SetHeight(1)
  line:SetPoint("BOTTOMLEFT", 20, 0)
  line:SetPoint("BOTTOMRIGHT", -10, 0)

  return holder
end

-- ── Dropdown (Basic, matching reference style) ───────────────────────

function NS.ChatGetDropdown(parent, labelText, isSelectedCb, onSelectionCb)
  local frame = CreateFrame("Frame", nil, parent)
  if labelText and labelText ~= "" then
    frame:SetPoint("LEFT", 30, 0)
    frame:SetPoint("RIGHT", -30, 0)
    frame:SetHeight(50)
  else
    frame:SetAllPoints()
  end

  local label = frame:CreateFontString(nil, "OVERLAY")
  label:SetFont(NS.FONT, 11, "")
  label:SetPoint("TOPLEFT", 20, 0)
  label:SetJustifyH("LEFT")
  if labelText and labelText ~= "" then
    label:SetText("|cff" .. GetAccentHex() .. ">|r |cff808080" .. labelText .. "|r")
    table.insert(NS.chatOptAccentLabels, {fs = label, rawText = labelText})
  else
    label:Hide()
  end

  local divLine = frame:CreateTexture(nil, "ARTWORK")
  divLine:SetColorTexture(0.18, 0.18, 0.18, 1)
  divLine:SetHeight(1)
  divLine:SetPoint("TOPLEFT", 20, -14)
  divLine:SetPoint("TOPRIGHT", -20, -14)
  if not labelText or labelText == "" then divLine:Hide() end

  local dropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
  if labelText and labelText ~= "" then
    dropdown:SetPoint("TOPLEFT", 18, -20)
  else
    dropdown:SetPoint("TOPLEFT", 0, 0)
    frame:SetHeight(26)
  end
  dropdown:SetPoint("RIGHT", -20, 0)

  -- Skin: hide default textures, dark backdrop with accent arrow
  for _, region in pairs({dropdown:GetRegions()}) do
    if region:IsObjectType("Texture") then region:SetAlpha(0) end
  end
  if dropdown.Arrow then dropdown.Arrow:SetAlpha(0) end

  local ddBackdrop = CreateFrame("Frame", nil, dropdown, "BackdropTemplate")
  ddBackdrop:SetAllPoints()
  ddBackdrop:SetFrameLevel(dropdown:GetFrameLevel())
  ddBackdrop:SetBackdrop(NS.BACKDROP)
  ddBackdrop:SetBackdropColor(0.08, 0.08, 0.08, 1)
  ddBackdrop:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
  ddBackdrop:EnableMouse(false)

  local ddArrow = ddBackdrop:CreateFontString(nil, "OVERLAY")
  ddArrow:SetFont(NS.FONT, 9, "")
  ddArrow:SetPoint("RIGHT", -5, 0)
  local acR, acG, acB = GetAccentRGB()
  ddArrow:SetTextColor(acR, acG, acB, 1)
  ddArrow:SetText("v")
  table.insert(NS.chatOptDropdownArrows, ddArrow)

  if dropdown.Text then
    dropdown.Text:SetTextColor(0.9, 0.9, 0.9, 1)
    dropdown.Text:ClearAllPoints()
    dropdown.Text:SetPoint("LEFT", 6, 0)
    dropdown.Text:SetPoint("RIGHT", -18, 0)
    dropdown.Text:SetJustifyH("LEFT")
  end

  dropdown:HookScript("OnEnter", function()
    local dr, dg, db = GetAccentRGB()
    ddBackdrop:SetBackdropBorderColor(dr, dg, db, 1)
  end)
  dropdown:HookScript("OnLeave", function()
    ddBackdrop:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
  end)

  frame.Init = function(_, entryLabels, values, scrollHeight)
    dropdown:SetupMenu(function(_, rootDescription)
      for i = 1, #entryLabels do
        local val = values[i]
        local radio = rootDescription:CreateRadio(entryLabels[i],
          function() return isSelectedCb(val) end,
          function() onSelectionCb(val) end
        )
        NS.SkinMenuElement(radio)
      end
      if scrollHeight then rootDescription:SetScrollMode(scrollHeight) end
    end)
  end

  frame.SetValue = function()
    if dropdown.UpdateText then dropdown:UpdateText() end
  end

  frame.Label = label
  frame.DropDown = dropdown
  return frame
end

-- ── Slider (matching reference MinimalSliderWithSteppersTemplate) ────

function NS.ChatGetSlider(parent, label, minVal, maxVal, valuePattern, callback)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetHeight(40)
  holder:SetPoint("LEFT", parent, "LEFT", 30, 0)
  holder:SetPoint("RIGHT", parent, "RIGHT", -30, 0)

  holder.Label = holder:CreateFontString(nil, "ARTWORK")
  holder.Label:SetFont(NS.FONT, 11, "")
  holder.Label:SetTextColor(1, 1, 1, 1)
  holder.Label:SetJustifyH("LEFT")
  holder.Label:SetPoint("LEFT", 20, 0)
  holder.Label:SetPoint("RIGHT", holder, "CENTER", -50, 0)
  holder.Label:SetText(label)

  holder.Slider = CreateFrame("Slider", nil, holder, "MinimalSliderWithSteppersTemplate")
  holder.Slider:SetPoint("LEFT", holder, "CENTER", -32, 0)
  holder.Slider:SetPoint("RIGHT", -45, 0)
  holder.Slider:SetHeight(20)

  local range = maxVal - minVal
  holder.Slider:Init(minVal, minVal, maxVal, range, {
    [MinimalSliderWithSteppersMixin.Label.Right] = CreateMinimalSliderFormatter(
      MinimalSliderWithSteppersMixin.Label.Right,
      function(value)
        return WHITE_FONT_COLOR:WrapTextInColorCode(valuePattern:format(value))
      end
    )
  })

  holder.Slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
    callback(value)
  end)

  -- Color the slider thumb with accent color
  C_Timer.After(0, function()
    local inner = holder.Slider and holder.Slider.Slider
    if inner then
      local thumb = inner:GetThumbTexture()
      if thumb then
        local ar, ag, ab = NS.ChatGetAccentRGB()
        thumb:SetColorTexture(ar, ag, ab, 1)
        thumb:SetSize(8, 16)
        table.insert(NS.chatOptSliderThumbs, thumb)
      end
    end
  end)

  function holder:GetValue()
    return holder.Slider.Slider:GetValue()
  end

  function holder:SetValue(value)
    return holder.Slider:SetValue(value)
  end

  -- No mouse wheel on sliders (user preference)

  return holder
end

-- ── Color Picker Row ─────────────────────────────────────────────────

function NS.ChatGetColorRow(parent, label, r, g, b, tooltip, callback)
  local PAD = 20
  local ROW_H = 22
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetHeight(ROW_H)

  local lbl = holder:CreateFontString(nil, "OVERLAY")
  lbl:SetFont(NS.FONT, 11, "")
  lbl:SetPoint("LEFT", PAD, 0)
  lbl:SetTextColor(1, 1, 1, 1)
  lbl:SetText(label)

  local sw = CreateFrame("Frame", nil, holder, "BackdropTemplate")
  sw:SetSize(16, 16)
  sw:SetPoint("RIGHT", -PAD, 0)
  sw:SetBackdrop(NS.BACKDROP)
  sw:SetBackdropColor(r or 0, g or 0, b or 0, 1)
  sw:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

  local rowHL = holder:CreateTexture(nil, "BACKGROUND")
  rowHL:SetPoint("TOPLEFT", PAD, 2)
  rowHL:SetPoint("BOTTOMRIGHT", -PAD, 0)
  rowHL:SetColorTexture(1, 1, 1, 0.05)
  rowHL:Hide()

  local hit = CreateFrame("Frame", nil, holder)
  hit:SetPoint("TOPLEFT", PAD, 2)
  hit:SetPoint("BOTTOMRIGHT", -PAD, 0)
  hit:EnableMouse(true)
  hit:SetFrameLevel(sw:GetFrameLevel() + 3)

  hit:SetScript("OnEnter", function()
    rowHL:Show()
    local ar, ag, ab = GetAccentRGB()
    sw:SetBackdropBorderColor(ar, ag, ab, 1)
    if tooltip then
      GameTooltip:SetOwner(hit, "ANCHOR_RIGHT")
      GameTooltip:SetText(tooltip, 0.75, 0.75, 0.75, 1, true)
      GameTooltip:Show()
    end
  end)
  hit:SetScript("OnLeave", function()
    rowHL:Hide()
    sw:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    GameTooltip:Hide()
  end)
  hit:SetScript("OnMouseDown", function()
    local curR, curG, curB = sw:GetBackdropColor()
    local oldR, oldG, oldB = curR, curG, curB
    ColorPickerFrame:SetupColorPickerAndShow({
      r = curR, g = curG, b = curB,
      swatchFunc = function()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        sw:SetBackdropColor(nr, ng, nb, 1)
        if callback then callback(nr, ng, nb) end
      end,
      cancelFunc = function()
        sw:SetBackdropColor(oldR, oldG, oldB, 1)
        if callback then callback(oldR, oldG, oldB) end
      end,
    })
  end)

  function holder:SetColor(cr, cg, cb)
    sw:SetBackdropColor(cr, cg, cb, 1)
  end

  holder._swatch = sw
  return holder
end

-- ── Refresh all accent-colored elements in settings dialog ───────────

function NS.RefreshSettingsAccent()
  local ar, ag, ab = GetAccentRGB()
  local hex = GetAccentHex()

  -- Checkbox fills
  for _, fill in ipairs(NS.chatOptCheckboxFills) do
    fill:SetColorTexture(ar, ag, ab, 1)
  end

  -- Accent labels ("> Text")
  for _, entry in ipairs(NS.chatOptAccentLabels) do
    local textColor = entry.white and "ffffff" or "808080"
    entry.fs:SetText("|cff" .. hex .. ">|r |cff" .. textColor .. entry.rawText .. "|r")
  end

  -- Dropdown arrows
  for _, arrow in ipairs(NS.chatOptDropdownArrows) do
    arrow:SetTextColor(ar, ag, ab, 1)
  end

  -- Slider thumbs
  for _, thumb in ipairs(NS.chatOptSliderThumbs) do
    thumb:SetColorTexture(ar, ag, ab, 1)
  end

  -- Card stripes and section title fontstrings
  if NS.chatOptAccentTextures then
    for _, e in ipairs(NS.chatOptAccentTextures) do
      if e.isFS then
        e.tex:SetTextColor(ar, ag, ab, e.alpha or 1)
      else
        e.tex:SetColorTexture(ar, ag, ab, e.alpha or 1)
      end
    end
  end

  -- Re-apply PCB custom color (overrides accent if settingsPcbColor is set,
  -- otherwise re-applies accent to PCB textures — same result either way)
  if NS.ApplyPcbColor then NS.ApplyPcbColor() end

  -- Settings dialog elements
  if NS.chatOptWin then
    local win = NS.chatOptWin

    -- Sidebar tabs (_label / _selLine / _selBg)
    if win.containers then
      for _,c in ipairs(win.containers) do
        local btn=c.button
        if btn then
          if btn._selLine then btn._selLine:SetColorTexture(ar,ag,ab,1) end
          if btn._selBg   then btn._selBg:SetColorTexture(ar,ag,ab,0.06) end
          if btn._selected and btn._label then btn._label:SetTextColor(ar,ag,ab) end
        end
      end
    end

    -- Window accent lines + border
    if win._ltBorderFrame then win._ltBorderFrame:SetBackdropBorderColor(ar,ag,ab,0.38) end
    if win._ltHeaderLine  then win._ltHeaderLine:SetColorTexture(ar,ag,ab,0.35) end
    if win._ltSidebarLine then win._ltSidebarLine:SetColorTexture(ar,ag,ab,0.18) end
    if win._ltLeftBar     then win._ltLeftBar:SetColorTexture(ar,ag,ab,1) end

    -- Title
    local thex=string.format("|cff%02x%02x%02x",ar*255,ag*255,ab*255)
    if win._ltTitleName then win._ltTitleName:SetText(thex.."LUCID|r|cffffffff".."UI|r") end

    -- Default/Custom theme buttons
    if NS._themeButtons then
      local isCustom=NS.DB("theme")=="custom"
      for _,b in ipairs(NS._themeButtons) do
        local act=isCustom==(b.key=="custom")
        b.btn:SetBackdropBorderColor(act and ar or 0.22,act and ag or 0.22,act and ab or 0.22,1)
      end
    end
  end
end
