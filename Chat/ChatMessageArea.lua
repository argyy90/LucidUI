-- LucidUI ChatMessageArea.lua
-- Custom slot-based message area with timestamp | separator | content columns.

local NS = LucidUINS

function NS.CreateChatMessageArea(parent, name)
  local frame = CreateFrame("Frame", name, parent)
  frame:SetClipsChildren(true)
  -- Propagate hyperlinks up to bg (LUIChatDisplayBG) which handles OnHyperlinkClick
  frame:SetHyperlinksEnabled(true)
  if frame.SetHyperlinkPropagateToParent then
    frame:SetHyperlinkPropagateToParent(true)
  end

  local FACE    = "Fonts/FRIZQT__.TTF"
  local SIZE    = 14
  local OUTLINE = ""
  local LINE_H  = 20
  local maxMsg  = 200
  local offset  = 0
  local msgs    = {}
  local slots   = {}

  local SB_W      = 16
  local L_PAD     = 2
  local SEP_W     = 2
  local SEP_GAP_L = 0
  local SEP_GAP_R = 6
  local ROW_GAP   = 0

  -- Fading
  local fadingEnabled = false
  local fadeAfter     = 25
  local fadeDuration  = 3
  local mouseOver     = false
  local sbDragging    = false

  -- Forward declarations
  local renderContent, updateScrollBar

  -- ── Helpers ─────────────────────────────────────────────────────────

  local function numSlots()
    local h = frame:GetHeight()
    if not h or h < 1 then h = 200 end
    return math.max(1, math.floor((h - 4) / LINE_H))
  end

  local function getAccent()
    -- NS.CYAN is always kept in sync with the active accent color
    local C = NS.CYAN
    return C[1], C[2], C[3]
  end

  local function applyFont(fs, face, size, outline)
    fs:SetFontObject(GameFontNormal)
    if face and face ~= "" then pcall(fs.SetFont, fs, face, size or 14, outline or "") end
  end

  -- Measure timestamp column width
  local tsColW = 60
  local measureFS = frame:CreateFontString(nil, "BACKGROUND")
  local function recomputeTsColW()
    applyFont(measureFS, FACE, SIZE, OUTLINE)
    local fmt = NS.DB("chatTimestampFormat") or "%H:%M"
    -- Use multiple representative times to find the widest output
    local maxW = 0
    for _, testTime in ipairs({43200, 86399, 45296}) do
      local ok, s = pcall(date, fmt, testTime)
      if ok and s and s ~= "" then
        measureFS:SetText(s)
        local w = measureFS:GetStringWidth()
        if w and w > maxW then maxW = w end
      end
    end
    tsColW = (maxW > 0) and (math.ceil(maxW) + 4) or math.ceil(SIZE * 4.5)
  end
  recomputeTsColW()

  -- Expose recompute so external code can trigger it after format changes
  function frame:RecomputeTimestampWidth()
    recomputeTsColW()
    if renderContent then renderContent() end
  end

  -- Strip separator from timestamp prefix to get clean label
  local function extractTsLabel(prefix)
    if not prefix then return nil end
    local stripped = prefix:match("^(.-) |cff%x+|||r%s*$")
                  or prefix:match("^(.-)%s+$")
                  or prefix
    return stripped
  end

  -- ── Scrollbar ──────────────────────────────────────────────────────

  local sbUp, sbDown, sbTrack, scrollBar, thumbTex, scrollToBottomBtn

  local function sbShowAll()
    sbTrack:Show(); scrollBar:Show(); sbUp:Show(); sbDown:Show()
  end
  local function sbHideAll()
    sbTrack:Hide(); scrollBar:Hide(); sbUp:Hide(); sbDown:Hide()
  end

  sbUp = CreateFrame("Button", nil, frame, "UIPanelScrollUpButtonTemplate")
  sbUp:SetSize(SB_W, SB_W)
  sbUp:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -2)
  sbUp:SetScript("OnClick", function()
    local n = numSlots()
    offset = math.min(math.max(0, #msgs - n), offset + 3)
    renderContent()
    updateScrollBar()
  end)
  sbUp:Hide()

  sbDown = CreateFrame("Button", nil, frame, "UIPanelScrollDownButtonTemplate")
  sbDown:SetSize(SB_W, SB_W)
  sbDown:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 2)
  sbDown:SetScript("OnClick", function()
    offset = math.max(0, offset - 3)
    renderContent()
    updateScrollBar()
  end)
  sbDown:Hide()

  sbTrack = frame:CreateTexture(nil, "BACKGROUND")
  sbTrack:SetWidth(SB_W)
  sbTrack:SetPoint("TOP",    sbUp,   "BOTTOM", 0, 0)
  sbTrack:SetPoint("BOTTOM", sbDown, "TOP",    0, 0)
  sbTrack:SetPoint("RIGHT",  frame,  "RIGHT",  0, 0)
  sbTrack:SetColorTexture(0, 0, 0, 0)
  sbTrack:Hide()

  scrollBar = CreateFrame("Slider", nil, frame)
  scrollBar:SetOrientation("VERTICAL")
  scrollBar:SetWidth(SB_W - 4)
  scrollBar:SetPoint("TOP",    sbUp,   "BOTTOM", 0, -2)
  scrollBar:SetPoint("BOTTOM", sbDown, "TOP",    0,  2)
  scrollBar:SetPoint("RIGHT",  frame,  "RIGHT", -2,  0)
  scrollBar:SetMinMaxValues(0, 0)
  scrollBar:SetValue(0)
  scrollBar:SetValueStep(1)
  scrollBar:SetObeyStepOnDrag(true)
  scrollBar:SetThumbTexture("Interface/Buttons/WHITE8X8")
  thumbTex = scrollBar:GetThumbTexture()
  if thumbTex then
    thumbTex:SetSize(SB_W - 4, 20)
    thumbTex:SetColorTexture(0.55, 0.55, 0.55, 0.9)
  end
  scrollBar:Hide()
  scrollBar:SetScript("OnMouseDown", function() sbDragging = true end)
  scrollBar:SetScript("OnMouseUp", function()
    sbDragging = false
    if not mouseOver then sbHideAll() end
  end)

  -- Scroll-to-bottom button
  scrollToBottomBtn = CreateFrame("Button", nil, frame)
  scrollToBottomBtn:SetSize(20, 20)
  scrollToBottomBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SB_W - 4, -2)
  scrollToBottomBtn:SetFrameLevel(frame:GetFrameLevel() + 10)
  local stbTex = scrollToBottomBtn:CreateTexture(nil, "ARTWORK")
  stbTex:SetTexture("Interface/AddOns/LucidUI/Assets/ScrollToBottom.png")
  stbTex:SetAllPoints()
  stbTex:SetVertexColor(0.7, 0.7, 0.7, 0.8)
  scrollToBottomBtn:SetScript("OnClick", function()
    offset = 0; renderContent(); updateScrollBar()
  end)
  scrollToBottomBtn:SetScript("OnEnter", function() stbTex:SetVertexColor(1, 1, 1, 1) end)
  scrollToBottomBtn:SetScript("OnLeave", function() stbTex:SetVertexColor(0.7, 0.7, 0.7, 0.8) end)
  scrollToBottomBtn:Hide()

  -- ── Slot pool ──────────────────────────────────────────────────────

  local TOOLTIP_LINK_TYPES = {
    achievement=true, item=true, spell=true, quest=true, currency=true,
    keystone=true, unit=true, enchant=true, glyph=true, instancelock=true,
    talent=true, apower=true, azessence=true, conduit=true, mawpower=true,
    transmogappearance=true, transmogset=true, transmogillusion=true,
    battlepet=true, battlePetAbil=true, dungeonScore=true,
  }

  local function getSlot(i)
    if slots[i] then return slots[i] end
    local s = {}

    -- Use plain FontString for timestamp column (lightweight, no buffer overhead)
    s.tsFS = frame:CreateFontString(nil, "OVERLAY")
    applyFont(s.tsFS, FACE, SIZE, OUTLINE)
    s.tsFS:SetJustifyH("LEFT")
    -- Compatibility shims so external code calling SMF-style methods still works
    s.tsFS.SetInsertMode       = function() end
    s.tsFS.SetMaxLines         = function() end
    s.tsFS.SetFading           = function() end
    s.tsFS.SetIndentedWordWrap = function() end
    s.tsFS.SetSpacing          = function() end
    s.tsFS.Clear = function(self) self:SetText("") end
    s.tsFS.AddMessage = function(self, text, r, g, b)
      self:SetText(text or "")
      if r then self:SetTextColor(r, g or 1, b or 1) end
    end

    s.sepTex = frame:CreateTexture(nil, "ARTWORK")
    s.sepTex:SetWidth(SEP_W)

    -- Content: FontString with word wrap (like Chattynator)
    -- Top-aligned, no internal padding, supports WoW color/hyperlink escape codes
    s.contentFS = frame:CreateFontString(nil, "OVERLAY")
    applyFont(s.contentFS, FACE, SIZE, OUTLINE)
    s.contentFS:SetJustifyH("LEFT")
    s.contentFS:SetJustifyV("TOP")
    s.contentFS:SetWordWrap(true)
    s.contentFS:SetNonSpaceWrap(true)
    -- Compatibility shims for SMF-style API calls
    s.contentFS.Clear = function(self) self:SetText("") end
    s.contentFS.AddMessage = function(self, text, r, g, b)
      self:SetText(text or "")
      if r then self:SetTextColor(r, g or 1, b or 1) end
    end

    s.measureFS = frame:CreateFontString(nil, "BACKGROUND")
    applyFont(s.measureFS, FACE, SIZE, OUTLINE)
    s.measureFS:SetWordWrap(true)
    s.measureFS:Hide()

    slots[i] = s
    return s
  end

  local function hideSlot(s)
    s.tsFS:Hide(); s.sepTex:Hide(); s.contentFS:Hide()
  end

  -- ── Render ─────────────────────────────────────────────────────────

  renderContent = function()
    for _, s in ipairs(slots) do hideSlot(s) end

    local total  = #msgs
    local frameH = frame:GetHeight() or 200
    local yOff   = 2
    local i      = 0
    local msgIdx = total - offset

    while msgIdx >= 1 do
      i = i + 1
      local s = getSlot(i)
      local m = msgs[msgIdx]

      -- Determine what to show independently
      local showTs  = NS.DB("chatTimestamps") ~= false
      local showSep = NS.DB("chatShowSeparator") ~= false

      -- Compute content left edge based on what's visible
      local cLeftX
      if showTs and showSep then
        cLeftX = L_PAD + tsColW + SEP_GAP_L + SEP_W + SEP_GAP_R
      elseif showTs then
        cLeftX = L_PAD + tsColW + 0  -- timestamp only, small gap
      elseif showSep then
        cLeftX = L_PAD + SEP_W + SEP_GAP_R
      else
        cLeftX = L_PAD
      end

      -- Content column: measure first, then position
      local cw = frame:GetWidth() - cLeftX - (SB_W + 4)
      local h = LINE_H

      -- Measure text height
      local measured = false
      local lenOk, textLen = pcall(string.len, m.t)
      if lenOk and textLen then
        s.measureFS:SetWidth(cw > 0 and cw or 200)
        s.measureFS:SetText(m.t)
        local strH = s.measureFS:GetStringHeight()
        if strH and strH > 0 then
          h = math.max(LINE_H, math.ceil(strH) + 4)
          measured = true
        end
      end
      if not measured then
        local charsPerLine = math.max(1, math.floor((cw > 0 and cw or 200) / (SIZE * 0.6)))
        local estLen = 80
        local estLines = math.max(1, math.ceil(estLen / charsPerLine))
        h = estLines * LINE_H
      end
      h = math.max(LINE_H, h)

      -- Position content FontString: set width, let height be natural
      s.contentFS:ClearAllPoints()
      s.contentFS:SetWidth(cw > 0 and cw or 200)
      s.contentFS:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", cLeftX, yOff)
      s.contentFS:Clear()
      s.contentFS:AddMessage(m.t, m.r, m.g, m.b)
      s.contentFS:Show()

      -- Get actual rendered height from the FontString (no LINE_H padding)
      h = s.contentFS:GetStringHeight() or LINE_H

      -- Timestamp: anchor LEFT + same vertical position as content TOP
      if showTs then
        local livePrefix = m.prefix
        if m.ts and NS.ChatFormatTimestamp then
          livePrefix = NS.ChatFormatTimestamp(m.ts)
        end
        local tsLabel = extractTsLabel(livePrefix)

        s.tsFS:ClearAllPoints()
        s.tsFS:SetPoint("LEFT", frame, "LEFT", L_PAD, 0)
        s.tsFS:SetPoint("TOP", s.contentFS)
        s.tsFS:SetWidth(tsColW)
        s.tsFS:Clear()
        local tsr, tsg, tsb = 0.45, 0.45, 0.45
        local tc = NS.DB("chatTimestampColor")
        if tc and type(tc) == "table" and tc.r then tsr, tsg, tsb = tc.r, tc.g, tc.b end
        s.tsFS:AddMessage(tsLabel or "", tsr, tsg, tsb)
        s.tsFS:Show()
      else
        s.tsFS:Hide()
      end

      -- Separator: anchor to content TOP/BOTTOM
      if showSep then
        local ar, ag, ab = getAccent()
        s.sepTex:SetColorTexture(ar, ag, ab, 0.6)
        s.sepTex:ClearAllPoints()
        local sepX = showTs and (L_PAD + tsColW + SEP_GAP_L) or L_PAD
        s.sepTex:SetPoint("LEFT", frame, "LEFT", sepX, 0)
        s.sepTex:SetPoint("TOP", s.contentFS)
        s.sepTex:SetPoint("BOTTOM", s.contentFS, "BOTTOM", 0, 1)
        s.sepTex:Show()
      else
        s.sepTex:Hide()
      end

      -- Consistent spacing: base gap + user spacing
      -- Multi-line messages get a small minimum gap so text doesn't run together
      local baseGap = 2
      yOff = yOff + h + baseGap + ROW_GAP

      -- Fade alpha (only when at bottom, scroll up reveals faded messages)
      if fadingEnabled and m.addedAt and offset == 0 then
        local age = GetTime() - m.addedAt
        local alpha = 1
        if age > fadeAfter then
          alpha = 1 - math.min(1, (age - fadeAfter) / fadeDuration)
        end
        s.tsFS:SetAlpha(alpha); s.contentFS:SetAlpha(alpha); s.sepTex:SetAlpha(alpha)
      else
        -- Scrolled up or mouse hovering: always fully visible
        s.tsFS:SetAlpha(1); s.contentFS:SetAlpha(1); s.sepTex:SetAlpha(1)
      end

      msgIdx = msgIdx - 1
      if yOff > frameH + LINE_H then break end
    end

    for j = i + 1, #slots do hideSlot(slots[j]) end

    -- Start/stop smooth fade via OnUpdate (only when fading is active)
    if fadingEnabled and offset == 0 then
      if not frame._fadeActive then
        frame._fadeActive = true
        local fadeElapsed = 0
        frame:SetScript("OnUpdate", function(_, dt)
          fadeElapsed = fadeElapsed + dt
          if fadeElapsed < 0.05 then return end -- throttle to ~20fps
          fadeElapsed = 0
          if not fadingEnabled or offset ~= 0 then
            frame._fadeActive = nil; frame:SetScript("OnUpdate", nil); return
          end
          local now = GetTime()
          local anyFading = false
          local total2 = #msgs
          for si = 1, #slots do
            local s2 = slots[si]
            if s2 and s2.contentFS:IsShown() then
              -- Find which message this slot displays (bottom-up order)
              local mi = total2 - offset - (si - 1)
              local m2 = msgs[mi]
              if m2 and m2.addedAt then
                local age = now - m2.addedAt
                local alpha = 1
                if age > fadeAfter then
                  alpha = math.max(0, 1 - (age - fadeAfter) / fadeDuration)
                  if alpha > 0 then anyFading = true end
                end
                s2.tsFS:SetAlpha(alpha); s2.contentFS:SetAlpha(alpha); s2.sepTex:SetAlpha(alpha)
              end
            end
          end
          if not anyFading then
            -- Check if any visible message will start fading soon
            local willFade = false
            for si2 = 1, #slots do
              local s3 = slots[si2]
              if s3 and s3.contentFS:IsShown() then
                local mi2 = total2 - offset - (si2 - 1)
                local m3 = msgs[mi2]
                if m3 and m3.addedAt and (now - m3.addedAt) < fadeAfter + fadeDuration then
                  willFade = true; break
                end
              end
            end
            if not willFade then
              frame._fadeActive = nil; frame:SetScript("OnUpdate", nil)
            end
          end
        end)
      end
    elseif frame._fadeActive then
      frame._fadeActive = nil; frame:SetScript("OnUpdate", nil)
    end
  end

  -- ── Scrollbar update ───────────────────────────────────────────────

  local sbUpdating = false
  updateScrollBar = function()
    local n      = numSlots()
    local total  = #msgs
    local maxOff = math.max(0, total - n)
    scrollToBottomBtn:SetShown(offset > 0)
    if maxOff == 0 or not mouseOver then
      sbHideAll(); return
    end
    sbShowAll()
    sbUpdating = true
    scrollBar:SetMinMaxValues(0, maxOff)
    scrollBar:SetValue(maxOff - offset)
    sbUpdating = false
  end

  local function render()
    renderContent(); updateScrollBar()
  end

  scrollBar:SetScript("OnValueChanged", function(_, value)
    if sbUpdating then return end
    local maxOff = math.max(0, #msgs - numSlots())
    local newOffset = math.max(0, math.min(maxOff - math.floor(value + 0.5), maxOff))
    if newOffset == offset then return end
    local wasScrolled = offset > 0
    offset = newOffset
    -- Reset fade when arriving at bottom via scrollbar
    if offset == 0 and wasScrolled and fadingEnabled then
      local now = GetTime()
      for _, m in ipairs(msgs) do m.addedAt = now end
    end
    renderContent()
  end)

  -- ── Public API ─────────────────────────────────────────────────────

  function frame:AddMessage(text, r, g, b, prefix, unixTime)
    local addedAt = GetTime()
    if unixTime then
      local age = time() - unixTime
      if age > 0 then addedAt = addedAt - age end
    end
    msgs[#msgs+1] = {t = text or "", r = r or 1, g = g or 1, b = b or 1, prefix = prefix, ts = unixTime, addedAt = addedAt}
    if #msgs > maxMsg then table.remove(msgs, 1) end
    if offset == 0 then render() else updateScrollBar() end
  end

  function frame:Clear()
    msgs = {}; offset = 0
    for _, s in ipairs(slots) do hideSlot(s) end
    sbHideAll(); scrollToBottomBtn:Hide()
  end

  function frame:ScrollUp()
    -- If at bottom with faded messages, first make them visible, then scroll
    if offset == 0 and fadingEnabled then
      local now = GetTime()
      local hasFaded = false
      for _, m in ipairs(msgs) do
        if m.addedAt and (now - m.addedAt) > fadeAfter then hasFaded = true; break end
      end
      if hasFaded then
        for _, m in ipairs(msgs) do m.addedAt = now end
        render()
        return
      end
    end
    offset = math.min(math.max(0, #msgs - numSlots()), offset + 3); render()
  end

  function frame:ScrollDown()
    -- If at bottom with faded messages, first make them visible
    if offset == 0 and fadingEnabled then
      local now = GetTime()
      local hasFaded = false
      for _, m in ipairs(msgs) do
        if m.addedAt and (now - m.addedAt) > fadeAfter then hasFaded = true; break end
      end
      if hasFaded then
        for _, m in ipairs(msgs) do m.addedAt = now end
        render()
        return
      end
    end
    local wasScrolled = offset > 0
    offset = math.max(0, offset - 3)
    -- When arriving back at bottom, reset fade timers
    if wasScrolled and offset == 0 and fadingEnabled then
      local now = GetTime()
      for _, m in ipairs(msgs) do m.addedAt = now end
    end
    render()
  end

  function frame:SetMaxLines(n) maxMsg = n end
  function frame:SetFading(enabled)
    fadingEnabled = enabled and true or false
    -- When enabling fade, reset addedAt on all messages so they don't instantly vanish
    if fadingEnabled then
      local now = GetTime()
      for _, m in ipairs(msgs) do m.addedAt = now end
    end
    render()
  end
  function frame:SetTimeVisible(seconds)
    fadeAfter = seconds or 25
    render()
  end
  function frame:SetIndentedWordWrap() end
  function frame:SetInsertMode() end
  function frame:SetSpacing(val) ROW_GAP = val or 0; render() end
  function frame:ScrollToBottom()
    if offset > 0 and fadingEnabled then
      local now = GetTime()
      for _, m in ipairs(msgs) do m.addedAt = now end
    end
    offset = 0; render()
  end
  function frame:AtBottom() return offset == 0 end
  function frame:GetNumMessages() return #msgs end
  function frame:GetMessages() return msgs end
  function frame:Refresh() renderContent() end

  function frame:SwapMessages(newMsgs)
    msgs = newMsgs or {}; offset = 0; render()
  end

  function frame:SetFont(face, size, outline)
    FACE = face or FACE; SIZE = size or SIZE; OUTLINE = outline or ""
    LINE_H = math.ceil(SIZE * 1.4) + 2
    recomputeTsColW()
    for _, s in ipairs(slots) do
      applyFont(s.tsFS, FACE, SIZE, OUTLINE)
      applyFont(s.contentFS, FACE, SIZE, OUTLINE)
      applyFont(s.measureFS, FACE, SIZE, OUTLINE)
    end
    render()
  end

  function frame:SetShadowOffset(x, y)
    for _, s in ipairs(slots) do
      s.tsFS:SetShadowOffset(x, y)
      s.contentFS:SetShadowOffset(x, y)
    end
  end

  function frame:SetShadowColor(r, g, b, a)
    for _, s in ipairs(slots) do
      s.tsFS:SetShadowColor(r, g, b, a)
      s.contentFS:SetShadowColor(r, g, b, a)
    end
  end

  frame:SetScript("OnSizeChanged", function() C_Timer.After(0, render) end)

  frame:SetScript("OnEnter", function()
    mouseOver = true
    updateScrollBar()
  end)
  frame:SetScript("OnLeave", function()
    if frame:IsMouseOver() then return end
    mouseOver = false
    if not sbDragging then sbHideAll() end
  end)

  frame:Show()
  return frame
end

-- ── Global URL hyperlink handler (fires for all chat frames/SMFs) ─────────
local _origOnHyperlinkShow = ChatFrame_OnHyperlinkShow
ChatFrame_OnHyperlinkShow = function(chatFrame, link, text, button)
  if link and link:match("^url:") then
    local url = link:match("^url:(.+)")
    if url and url ~= "" then
      if IsShiftKeyDown() then
        local eb = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
        if eb then eb:Insert(url) end
      else
        NS.ShowURLCopyBox(url)
      end
      return  -- consume, don't pass to default handler
    end
  end
  if _origOnHyperlinkShow then _origOnHyperlinkShow(chatFrame, link, text, button) end
end