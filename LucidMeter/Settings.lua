-- LucidMeter — Settings tab  ::  Card layout redesign
local NS = LucidUINS
local L  = LucidUIL
local DM = NS.LucidMeter

function DM.SetupSettings(parent)
  local container = CreateFrame("Frame", nil, parent)
  local MakeCard  = NS._SMakeCard
  local MakePage  = NS._SMakePage
  local Sep       = NS._SSep
  local R         = NS._SR
  local BD        = NS._SBD
  local sc, Add   = MakePage(container)

  local function DB(k)    return NS.DB(k)       end
  local function DBSet(k,v) NS.DBSet(k, v)       end

  -- ── Card: General ────────────────────────────────────────────────
  local cGen = MakeCard(sc, "General")

  local enableCB = NS.ChatGetCheckbox(cGen.inner, "Enable LucidMeter", 26, function(state)
    DBSet("dmEnabled", state)
    if state then
      if DM.RegisterEvents then DM.RegisterEvents() end
      if DM.BuildDisplay   then DM.BuildDisplay()   end
    else
      if DM.UnregisterEvents then DM.UnregisterEvents() end
      if DM.windows then for _, w in ipairs(DM.windows) do w.frame:Hide() end end
    end
  end, "Show a damage meter window")
  enableCB.option = "dmEnabled"; R(cGen, enableCB, 26)

  local function PairRow(lbl1,key1,cb1,tip1, lbl2,key2,cb2,tip2)
    local row = CreateFrame("Frame", nil, cGen.inner); row:SetHeight(26)
    local w1 = NS.ChatGetCheckbox(row, lbl1, 26, cb1, tip1); w1.option = key1
    w1:SetParent(row); w1:ClearAllPoints()
    w1:SetPoint("TOPLEFT",  row, "TOPLEFT",  0, 0)
    w1:SetPoint("TOPRIGHT", row, "TOP",     -4, 0)
    w1:SetHeight(26)
    local w2 = NS.ChatGetCheckbox(row, lbl2, 26, cb2, tip2); w2.option = key2
    w2:SetParent(row); w2:ClearAllPoints()
    w2:SetPoint("TOPLEFT",  row, "TOP",      4, 0)
    w2:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
    w2:SetHeight(26)
    row._left = w1; row._right = w2
    cGen:Row(row, 26); return row
  end

  local row0 = PairRow(
    "Icons on Mouseover","dmIconsOnHover",function(s)
      DBSet("dmIconsOnHover",s)
      if DM.windows then for _,w in ipairs(DM.windows) do if w.frame._titleIcons then for _,ic in ipairs(w.frame._titleIcons) do ic:SetShown(not s) end end end end
    end,"Only show titlebar icons when hovering",
    "Lock position","dmLocked",function(s)
      DBSet("dmLocked",s)
      if DM.windows then for _,w in ipairs(DM.windows) do if w.frame and w.frame._resizeBtn then w.frame._resizeBtn:SetShown(not s) end end end
    end,"Prevent moving and resizing")

  local function TripleRow(items)
    local row = CreateFrame("Frame",nil,cGen.inner); row:SetHeight(26)
    row._cbs = {}
    local W = math.floor(100/3)
    for i,item in ipairs(items) do
      local w = NS.ChatGetCheckbox(row,item.label,26,item.func,item.tip); w.option=item.key
      w:SetParent(row); w:ClearAllPoints()
      local xL = (i-1)*W; local xR = i*W
      w:SetPoint("TOPLEFT", row,"TOPLEFT", xL == 0 and 0 or xL.."%"==xL and 0 or 0, 0)
      -- Simplified: just divide into thirds by absolute math after show
      w._triIdx = i
      row._cbs[i] = w
    end
    -- Position on show
    row:SetScript("OnShow", function(self)
      local tw = self:GetWidth()
      local third = math.floor(tw/3)
      for ii,cb in ipairs(self._cbs) do
        cb:ClearAllPoints()
        cb:SetPoint("TOPLEFT",  self,"TOPLEFT",  (ii-1)*third, 0)
        cb:SetPoint("TOPRIGHT", self,"TOPLEFT",   ii*third, 0)
        cb:SetHeight(26)
      end
    end)
    cGen:Row(row, 26); return row
  end

  local row1 = TripleRow({
    {label="Combat only",    key="dmShowInCombatOnly", func=function(s) DBSet("dmShowInCombatOnly",s) end, tip="Hide out of combat"},
    {label="Always self",    key="dmAlwaysShowSelf",   func=function(s) DBSet("dmAlwaysShowSelf",s); if DM.UpdateDisplay then DM.UpdateDisplay() end end, tip="Always show your bar"},
    {label="Show rank",      key="dmShowRank",         func=function(s) DBSet("dmShowRank",s); if DM.UpdateDisplay then DM.UpdateDisplay() end end, tip="Crown for #1"},
  })
  local row2g = PairRow(
    "Show %","dmShowPercent",function(s) DBSet("dmShowPercent",s); if DM.UpdateDisplay then DM.UpdateDisplay() end end,"Percentage of total",
    "Server name","dmShowRealm",function(s) DBSet("dmShowRealm",s); if DM.UpdateDisplay then DM.UpdateDisplay() end end,"Show realm for others")

  local resetDD = NS.ChatGetDropdown(cGen.inner,"Auto Reset",
    function(v) return (DB("dmAutoReset") or "off")==v end,
    function(v) DBSet("dmAutoReset",v) end)
  resetDD:Init({"Off","Enter Instance","Leave Instance","Both"},{"off","enter","leave","both"})
  R(cGen, resetDD, 50)

  cGen:Finish(); Add(cGen); Add(Sep(sc),9)

  -- ── Card: Click-Through ──────────────────────────────────────────
  local cCT = MakeCard(sc, "Click-Through")
  local ctRow = CreateFrame("Frame", nil, cCT.inner); ctRow:SetHeight(26)
  local ctL = NS.ChatGetCheckbox(ctRow, "Enable click-through", 26, function(s)
    DBSet("dmClickThrough",s)
    if DM.windows then for _,w in ipairs(DM.windows) do local combat=DB("dmClickThroughCombat"); local act=s and(not combat or DM.inCombat); w.frame:EnableMouse(not act) end end
  end, "Clicks pass through the meter window")
  ctL.option="dmClickThrough"
  ctL:SetParent(ctRow); ctL:ClearAllPoints()
  ctL:SetPoint("TOPLEFT", ctRow,"TOPLEFT", 0,0)
  ctL:SetPoint("TOPRIGHT",ctRow,"TOP",    -4,0)
  ctL:SetHeight(26)
  local ctR = NS.ChatGetCheckbox(ctRow, "In combat only", 26, function(s)
    DBSet("dmClickThroughCombat",s)
    if DM.windows then for _,w in ipairs(DM.windows) do local en=DB("dmClickThrough"); local act=en and(not s or DM.inCombat); w.frame:EnableMouse(not act) end end
  end, "Only during combat")
  ctR.option="dmClickThroughCombat"
  ctR:SetParent(ctRow); ctR:ClearAllPoints()
  ctR:SetPoint("TOPLEFT", ctRow,"TOP",      4,0)
  ctR:SetPoint("TOPRIGHT",ctRow,"TOPRIGHT", 0,0)
  ctR:SetHeight(26)
  ctRow._left=ctL; ctRow._right=ctR
  cCT:Row(ctRow, 26); cCT:Finish(); Add(cCT); Add(Sep(sc),9)

  -- ── Card: Text & Colors ──────────────────────────────────────────
  local cText = MakeCard(sc, "Text & Colors")

  local fontShadow
  fontShadow = NS.ChatGetSlider(cText.inner,"Font Shadow",0,3,"%.1f",function(value)
    DBSet("dmFontShadow",value)
    if DM.UpdateDisplay then DM.UpdateDisplay() end
    if DM.windows then for _,w in ipairs(DM.windows) do if w.titleText then
      if value>0 then w.titleText:SetShadowOffset(value,-value); w.titleText:SetShadowColor(0,0,0,1)
      else w.titleText:SetShadowOffset(0,0) end
    end end end
  end)
  fontShadow.option="dmFontShadow"; R(cText, fontShadow, 40)

  local textOutline = NS.ChatGetCheckbox(cText.inner,"Text Outline",26,function(s)
    DBSet("dmTextOutline",s)
    if DM.UpdateDisplay then DM.UpdateDisplay() end
    if DM.windows then local fp=NS.GetFontPath(NS.DB("dmFont")); local fts=NS.DB("dmTitleFontSize") or 10; local fl=s and "OUTLINE" or ""
      for _,w in ipairs(DM.windows) do if w.titleText then w.titleText:SetFont(fp,fts,fl) end end end
  end,"Add outline to text for readability")
  textOutline.option="dmTextOutline"; R(cText, textOutline, 26)

  -- Color pickers row
  local function MakeDMColor(par,lbl,key,def,applyFn)
    local row=CreateFrame("Frame",nil,par); row:SetHeight(26)
    local sw=CreateFrame("Frame",nil,row,"BackdropTemplate"); sw:SetSize(14,14); sw:SetPoint("LEFT",0,0)
    sw:SetBackdrop(BD)
    local c=DB(key)
    if type(c) ~= "table" or not c.r then c = def end
    sw:SetBackdropColor(c.r,c.g,c.b,1); sw:SetBackdropBorderColor(0.28,0.28,0.38,1)
    local fl=row:CreateFontString(nil,"OVERLAY"); fl:SetFont(NS.FONT,11,"")
    fl:SetPoint("LEFT",sw,"RIGHT",6,0); fl:SetTextColor(0.75,0.75,0.85); fl:SetText(lbl)
    local hl=row:CreateTexture(nil,"BACKGROUND"); hl:SetAllPoints(); hl:SetColorTexture(1,1,1,0.03); hl:Hide()
    local hit=CreateFrame("Button",nil,row); hit:SetAllPoints(); hit:SetFrameLevel(row:GetFrameLevel()+3)
    hit:SetScript("OnEnter",function() hl:Show(); local cr,cg,cb=NS.ChatGetAccentRGB(); sw:SetBackdropBorderColor(cr,cg,cb,1) end)
    hit:SetScript("OnLeave",function() hl:Hide(); sw:SetBackdropBorderColor(0.28,0.28,0.38,1) end)
    hit:SetScript("OnClick",function()
      local cur=DB(key)
      if type(cur) ~= "table" or not cur.r then cur = def end
      ColorPickerFrame:SetupColorPickerAndShow({r=cur.r,g=cur.g,b=cur.b,
        swatchFunc=function() local r,g,b=ColorPickerFrame:GetColorRGB(); DBSet(key,{r=r,g=g,b=b}); sw:SetBackdropColor(r,g,b,1); if applyFn then applyFn(r,g,b) end end,
        cancelFunc=function(prev) DBSet(key,{r=prev.r,g=prev.g,b=prev.b}); sw:SetBackdropColor(prev.r,prev.g,prev.b,1); if applyFn then applyFn(prev.r,prev.g,prev.b) end end,
      })
    end)
    row._swatch=sw; return row
  end

  -- Title Color | Text Color | Bar Color — all three side by side
  local titleColorRow, textColorRow, barColorRow
  do
    local triColor = CreateFrame("Frame",nil,cText.inner); triColor:SetHeight(26)
    cText:Row(triColor,26)
    triColor:SetPoint("LEFT",cText.inner,"LEFT",0,0); triColor:SetPoint("RIGHT",cText.inner,"RIGHT",0,0)
    -- build a sub-row for each third
    local colorDefs = {
      {lbl="Title Color", key="dmTitleColor", def={r=1,g=1,b=1}, apply=function(r,g,b)
        if DM.windows then for _,w in ipairs(DM.windows) do if w.titleText then w.titleText:SetTextColor(r,g,b) end end end end},
      {lbl="Text Color",  key="dmTextColor",  def={r=1,g=1,b=1}, apply=function()
        if DM.UpdateDisplay then DM.UpdateDisplay() end end},
      {lbl="Bar Color",   key="dmBarColor",   def={r=0.5,g=0.5,b=0.5}, apply=function()
        if DM.UpdateDisplay then DM.UpdateDisplay() end end},
    }
    local rows = {}
    for i,cd in ipairs(colorDefs) do
      local holder = CreateFrame("Frame",nil,triColor); holder:SetHeight(26)
      local r = MakeDMColor(holder,cd.lbl,cd.key,cd.def,cd.apply)
      r:SetParent(holder); r:ClearAllPoints(); r:SetAllPoints(holder)
      rows[i] = {holder=holder, row=r}
    end
    triColor:SetScript("OnShow",function(self)
      local tw = self:GetWidth()
      local third = math.floor(tw/3)
      for i,item in ipairs(rows) do
        item.holder:ClearAllPoints()
        item.holder:SetPoint("TOPLEFT",  self,"TOPLEFT",  (i-1)*third +20, 0)
        item.holder:SetPoint("BOTTOMRIGHT",self,"TOPLEFT", i*third +20, -26)
      end
    end)
    titleColorRow = rows[1].row
    textColorRow  = rows[2].row
    barColorRow   = rows[3].row
  end

  cText:Finish(); Add(cText); Add(Sep(sc),9)

  -- ── Card: Windows ────────────────────────────────────────────────
  local cWin = MakeCard(sc, "Windows")
  local winBtnRow=CreateFrame("Frame",nil,cWin.inner); winBtnRow:SetHeight(32)

  local function SBtn(par,txt,w)
    local btn=CreateFrame("Button",nil,par,"BackdropTemplate"); btn:SetSize(w,28); btn:SetBackdrop(BD)
    btn:SetBackdropColor(0.04,0.04,0.07,1); btn:SetBackdropBorderColor(0.12,0.12,0.20,1)
    local cut=btn:CreateTexture(nil,"OVERLAY",nil,4); cut:SetSize(10,1); cut:SetPoint("TOPRIGHT",btn,"TOPRIGHT",0,-1); cut:SetColorTexture(0,1,1,0.22)
    local fs=btn:CreateFontString(nil,"OVERLAY"); fs:SetFont(NS.FONT,11,""); fs:SetPoint("CENTER",0,0); fs:SetTextColor(0.75,0.75,0.85); fs:SetText(txt)
    btn:SetScript("OnEnter",function() local cr,cg,cb=NS.ChatGetAccentRGB(); btn:SetBackdropBorderColor(cr,cg,cb,0.8) end)
    btn:SetScript("OnLeave",function() btn:SetBackdropBorderColor(0.12,0.12,0.20,1) end)
    return btn
  end

  -- Buttons centered, each half the row minus a gap
  local newWinBtn  = SBtn(winBtnRow,"New Window",  0)
  local closeWinBtn= SBtn(winBtnRow,"Close Window",0)
  local GAP = 6
  winBtnRow:SetScript("OnShow",function(self)
    local w = math.floor((self:GetWidth() - GAP) / 2)
    newWinBtn:SetWidth(w)
    newWinBtn:ClearAllPoints()
    newWinBtn:SetPoint("LEFT",  self,"LEFT",  0, 0)
    newWinBtn:SetPoint("RIGHT", self,"CENTER",-math.ceil(GAP/2), 0)
    closeWinBtn:SetWidth(w)
    closeWinBtn:ClearAllPoints()
    closeWinBtn:SetPoint("LEFT",  self,"CENTER", math.floor(GAP/2), 0)
    closeWinBtn:SetPoint("RIGHT", self,"RIGHT",  0, 0)
  end)
  newWinBtn:SetScript("OnClick",function() if DM.CreateNewWindow then DM.CreateNewWindow() end end)

  local closePopup=nil
  closeWinBtn:SetScript("OnClick",function(self)
    if closePopup then closePopup:Hide(); closePopup=nil; return end
    local items={}
    for _,w in ipairs(DM.windows or {}) do
      if w.id~=1 then
        local lbl2="Window "..w.id
        if DM.METER_TYPES then for _,mt in ipairs(DM.METER_TYPES) do if mt.id==w.meterType then lbl2=lbl2.."  —  "..mt.label; break end end end
        items[#items+1]={id=w.id,text=lbl2}
      end
    end
    if #items==0 then items[#items+1]={text="|cff808080No extra windows|r",disabled=true} end
    closePopup=CreateFrame("Frame",nil,self,"BackdropTemplate")
    closePopup:SetBackdrop(BD); closePopup:SetBackdropColor(0.05,0.05,0.08,0.97); closePopup:SetBackdropBorderColor(0.12,0.12,0.20,1)
    closePopup:SetFrameStrata("TOOLTIP"); closePopup:SetClampedToScreen(true)
    local ITEM_H=22; local totalH=0
    for _,item in ipairs(items) do
      local row=CreateFrame("Button",nil,closePopup); row:SetHeight(ITEM_H)
      row:SetPoint("TOPLEFT",2,-totalH); row:SetPoint("TOPRIGHT",-2,-totalH)
      local hl=row:CreateTexture(nil,"BACKGROUND"); hl:SetAllPoints(); hl:SetColorTexture(1,1,1,0.05); hl:Hide()
      local lbl3=row:CreateFontString(nil,"OVERLAY"); lbl3:SetFont(NS.FONT,10,""); lbl3:SetPoint("LEFT",8,0); lbl3:SetText(item.text); lbl3:SetTextColor(0.80,0.80,0.88)
      if not item.disabled then
        row:SetScript("OnEnter",function() hl:Show(); lbl3:SetTextColor(1,0.35,0.35) end)
        row:SetScript("OnLeave",function() hl:Hide(); lbl3:SetTextColor(0.80,0.80,0.88) end)
        local cid=item.id
        row:SetScript("OnClick",function() if DM.CloseWindow then DM.CloseWindow(cid) end; closePopup:Hide(); closePopup=nil end)
      end
      totalH=totalH+ITEM_H
    end
    closePopup:SetSize(self:GetWidth(),totalH+4); closePopup:ClearAllPoints(); closePopup:SetPoint("TOP",self,"BOTTOM",0,-2); closePopup:Show()
    local ct=C_Timer.NewTicker(0.3,function() if closePopup and not closePopup:IsMouseOver() and not self:IsMouseOver() then closePopup:Hide(); closePopup=nil end end)
    closePopup:HookScript("OnHide",function() ct:Cancel() end)
  end)
  cWin:Row(winBtnRow,32); cWin:Finish(); Add(cWin); Add(Sep(sc),9)

  -- ── Card: Appearance ────────────────────────────────────────────
  local cApp = MakeCard(sc, "Appearance")

  local fontDD=NS.ChatGetDropdown(cApp.inner,"Font",
    function(v) return (DB("dmFont") or "Friz Quadrata")==v end,
    function(v) DBSet("dmFont",v); local fp=NS.GetFontPath(v); if DM.windows then for _,w in ipairs(DM.windows) do if w.titleText then w.titleText:SetFont(fp,NS.DB("dmTitleFontSize") or 10,"") end end end; if DM.UpdateDisplay then DM.UpdateDisplay() end end)
  fontDD:Init({"Friz Quadrata"},{"Friz Quadrata"},20*15); R(cApp,fontDD,50)

  -- Row 1: Icon Mode | Values | Bar Highlight  — three dropdowns side by side
  local iconDD, valDD, highlightDD
  do
    local triRow = CreateFrame("Frame",nil,cApp.inner); triRow:SetHeight(50)
    cApp:Row(triRow,50)
    triRow:SetPoint("LEFT",cApp.inner,"LEFT",0,0); triRow:SetPoint("RIGHT",cApp.inner,"RIGHT",0,0)
    -- Icon Mode (left third)
    local h1 = CreateFrame("Frame",nil,triRow)
    iconDD = NS.ChatGetDropdown(h1,"Icon Mode",
      function(v) return (DB("dmIconMode") or "spec")==v end,
      function(v) DBSet("dmIconMode",v); if DM.UpdateDisplay then DM.UpdateDisplay() end end)
    iconDD:Init({"Spec","Class","None"},{"spec","class","none"})
    iconDD:ClearAllPoints(); iconDD:SetAllPoints(h1)
    -- Values (middle third)
    local h2 = CreateFrame("Frame",nil,triRow)
    valDD = NS.ChatGetDropdown(h2,"Values",
      function(v) return (DB("dmValueFormat") or "both")==v end,
      function(v) DBSet("dmValueFormat",v); if DM.UpdateDisplay then DM.UpdateDisplay() end end)
    valDD:Init({"Total | DPS","Total","DPS"},{"both","total","persec"})
    valDD:ClearAllPoints(); valDD:SetAllPoints(h2)
    -- Bar Highlight (right third)
    local h3 = CreateFrame("Frame",nil,triRow)
    highlightDD = NS.ChatGetDropdown(h3,"Bar Highlight",
      function(v) return (DB("dmBarHighlight") or "none")==v end,
      function(v) DBSet("dmBarHighlight",v); if DM.UpdateDisplay then DM.UpdateDisplay() end end)
    highlightDD:Init({"None","Border","Bar"},{"none","border","bar"})
    highlightDD:ClearAllPoints(); highlightDD:SetAllPoints(h3)
    triRow:SetScript("OnShow",function(self)
      local tw = self:GetWidth()
      local third = math.floor(tw/3)
      for i,h in ipairs({h1,h2,h3}) do
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT",   self,"TOPLEFT",  (i-1)*third, 0)
        h:SetPoint("BOTTOMRIGHT",self,"TOPLEFT",  i*third,   -50)
      end
    end)
  end

  -- Row 2: Bar Texture | Bar Background  — side by side
  local barTexDD, barBgDD
  local barTexNames, barTexValues = {}, {}
  for _,bt in ipairs(NS.GetLSMStatusBars()) do barTexNames[#barTexNames+1]=bt.label; barTexValues[#barTexValues+1]=bt.label end
  do
    local pairRow = CreateFrame("Frame",nil,cApp.inner); pairRow:SetHeight(50)
    cApp:Row(pairRow,50)
    pairRow:SetPoint("LEFT",cApp.inner,"LEFT",0,0); pairRow:SetPoint("RIGHT",cApp.inner,"RIGHT",0,0)
    local ph1 = CreateFrame("Frame",nil,pairRow)
    barTexDD = NS.ChatGetDropdown(ph1,"Bar Texture",
      function(v) return (DB("dmBarTexture") or "Flat")==v end,
      function(v) DBSet("dmBarTexture",v); if DM.UpdateDisplay then DM.UpdateDisplay() end end)
    barTexDD:Init(barTexNames,barTexValues,20*15)
    barTexDD:ClearAllPoints(); barTexDD:SetAllPoints(ph1)
    local ph2 = CreateFrame("Frame",nil,pairRow)
    barBgDD = NS.ChatGetDropdown(ph2,"Bar Background",
      function(v) return (DB("dmBarBgTexture") or "Flat")==v end,
      function(v) DBSet("dmBarBgTexture",v); if DM.UpdateDisplay then DM.UpdateDisplay() end end)
    barBgDD:Init(barTexNames,barTexValues,20*15)
    barBgDD:ClearAllPoints(); barBgDD:SetAllPoints(ph2)
    pairRow:SetScript("OnShow",function(self)
      local tw = self:GetWidth()
      local half = math.floor(tw/2)
      ph1:ClearAllPoints(); ph1:SetPoint("TOPLEFT",self,"TOPLEFT",0,0); ph1:SetPoint("BOTTOMRIGHT",self,"TOPLEFT",half,-50)
      ph2:ClearAllPoints(); ph2:SetPoint("TOPLEFT",self,"TOPLEFT",half,0); ph2:SetPoint("BOTTOMRIGHT",self,"BOTTOMRIGHT",0,-50)
    end)
  end

  -- Toggles row
  -- Helper: two CBs side by side in cApp
  local function AppPair(lbl1,key1,cb1,tip1, lbl2,key2,cb2,tip2)
    local row=CreateFrame("Frame",nil,cApp.inner); row:SetHeight(26)
    cApp:Row(row,26); row:SetPoint("LEFT",cApp.inner,"LEFT",0,0); row:SetPoint("RIGHT",cApp.inner,"RIGHT",0,0)
    local lh=CreateFrame("Frame",nil,row); lh:SetPoint("TOPLEFT",row,"TOPLEFT",0,0); lh:SetPoint("BOTTOMRIGHT",row,"BOTTOM",-2,0)
    local rh=CreateFrame("Frame",nil,row); rh:SetPoint("TOPLEFT",row,"TOP",2,0); rh:SetPoint("BOTTOMRIGHT",row,"BOTTOMRIGHT",0,0)
    local w1=NS.ChatGetCheckbox(lh,lbl1,26,cb1,tip1); w1:ClearAllPoints(); w1:SetAllPoints(lh); w1.option=key1
    local w2=NS.ChatGetCheckbox(rh,lbl2,26,cb2,tip2); w2:ClearAllPoints(); w2:SetAllPoints(rh); w2.option=key2
    return w1,w2
  end
  local function AppCB(lbl,key,cb,tip) local w=NS.ChatGetCheckbox(cApp.inner,lbl,26,cb,tip); w.option=key; R(cApp,w,26); return w end
  local classCB,totalCB   = AppPair("Class colors","dmClassColors",function(s) DBSet("dmClassColors",s); if DM.UpdateDisplay then DM.UpdateDisplay() end end,"Color bars by class",
                                     "Show total bar","dmShowTotalBar",function(s) DBSet("dmShowTotalBar",s); if DM.UpdateDisplay then DM.UpdateDisplay() end end,"Group total at top")
  local accentCB,winBorderCB = AppPair("Accent line","dmAccentLine",function(s) DBSet("dmAccentLine",s); if DM.windows then for _,w in ipairs(DM.windows) do if w.frame._accentLine then w.frame._accentLine:SetShown(s) end end end end,"Accent line below title",
                                        "Window border","dmWindowBorder",function(s) DBSet("dmWindowBorder",s); if DM.windows then for _,w in ipairs(DM.windows) do w.frame:SetBackdropBorderColor(0.15,0.15,0.15,s and 1 or 0) end end end,"Border around meter")
  local titleBorderCB = AppCB("Title separator","dmTitleBorder",function(s) DBSet("dmTitleBorder",s); if DM.windows then for _,w in ipairs(DM.windows) do if w.frame._titleBorder then w.frame._titleBorder:SetShown(s) end end end end,"Line between title and bars")

  cApp:Finish(); Add(cApp); Add(Sep(sc),9)

  -- ── Card: Bars ───────────────────────────────────────────────────
  local cBars = MakeCard(sc, "Bars")
  local barHeight,barSpacing,barFontSize,titleFontSize,barBright
  barHeight    = NS.ChatGetSlider(cBars.inner,"Bar Height",   12, 28, "%dpx",function(v) DBSet("dmBarHeight",v); if DM.UpdateDisplay then DM.UpdateDisplay() end end); barHeight.option="dmBarHeight"; R(cBars,barHeight,40)
  barSpacing   = NS.ChatGetSlider(cBars.inner,"Bar Spacing",   0,  4, "%dpx",function(v) DBSet("dmBarSpacing",v); if DM.UpdateDisplay then DM.UpdateDisplay() end end); barSpacing.option="dmBarSpacing"; R(cBars,barSpacing,40)
  barFontSize  = NS.ChatGetSlider(cBars.inner,"Bar Font Size",  8, 16, "%dpt",function(v) DBSet("dmFontSize",v); if DM.UpdateDisplay then DM.UpdateDisplay() end end); barFontSize.option="dmFontSize"; R(cBars,barFontSize,40)
  titleFontSize= NS.ChatGetSlider(cBars.inner,"Title Font Size",8, 16, "%dpt",function(v) DBSet("dmTitleFontSize",v); local fp=NS.GetFontPath(NS.DB("dmFont")); if DM.windows then for _,w in ipairs(DM.windows) do if w.titleText then w.titleText:SetFont(fp,v,"") end end end end); titleFontSize.option="dmTitleFontSize"; R(cBars,titleFontSize,40)
  barBright    = NS.ChatGetSlider(cBars.inner,"Bar Brightness",10,100,"%d%%", function(v) DBSet("dmBarBrightness",v/100); if DM.UpdateDisplay then DM.UpdateDisplay() end end); barBright.option="dmBarBrightness"; barBright._isPercent=true; R(cBars,barBright,40)
  cBars:Finish(); Add(cBars); Add(Sep(sc),9)

  -- ── Card: Transparency & Performance ────────────────────────────
  local cTP = MakeCard(sc, "Transparency & Performance")
  local bgAlpha, titleAlpha, updateInt
  bgAlpha   = NS.ChatGetSlider(cTP.inner,"Window",    0,100,"%d%%",function(v) DBSet("dmBgAlpha",v/100); if DM.windows then for _,w in ipairs(DM.windows) do if w.frame._bodyBg then w.frame._bodyBg:SetAlpha(v/100) end end end end); bgAlpha.option="dmBgAlpha"; bgAlpha._isPercent=true; R(cTP,bgAlpha,40)
  titleAlpha= NS.ChatGetSlider(cTP.inner,"Title Bar", 0,100,"%d%%",function(v) DBSet("dmTitleAlpha",v/100); if DM.windows then for _,w in ipairs(DM.windows) do if w.frame._titleBg then w.frame._titleBg:SetAlpha(v/100) end end end end); titleAlpha.option="dmTitleAlpha"; titleAlpha._isPercent=true; R(cTP,titleAlpha,40)
  updateInt = NS.ChatGetSlider(cTP.inner,"Update Interval",100,2000,"%dms",function(v) DBSet("dmUpdateInterval",v/1000) end); updateInt.option="dmUpdateInterval"; R(cTP,updateInt,40)
  cTP:Finish(); Add(cTP)

  -- ── OnShow ───────────────────────────────────────────────────────
  container:SetScript("OnShow", function()
    local fontNames,fontValues={},{}
    for _,f in ipairs(NS.GetLSMFonts()) do fontNames[#fontNames+1]=f.label; fontValues[#fontValues+1]=f.label end
    fontDD:Init(fontNames,fontValues,20*15); if fontDD.SetValue then fontDD:SetValue() end
    enableCB:SetValue(DB("dmEnabled")==true)
    row0._left:SetValue(DB("dmIconsOnHover")==true)
    row0._right:SetValue(DB("dmLocked")==true)
    if row1._cbs then
      row1._cbs[1]:SetValue(DB("dmShowInCombatOnly")==true)
      row1._cbs[2]:SetValue(DB("dmAlwaysShowSelf")~=false)
      row1._cbs[3]:SetValue(DB("dmShowRank")==true)
    end
    row2g._left:SetValue(DB("dmShowPercent")==true)
    row2g._right:SetValue(DB("dmShowRealm")==true)
    if resetDD.SetValue then resetDD:SetValue() end
    ctRow._left:SetValue(DB("dmClickThrough")==true)
    ctRow._right:SetValue(DB("dmClickThroughCombat")==true)
    local fsv=DB("dmFontShadow") or 0; if type(fsv)=="boolean" then fsv=fsv and 1.5 or 0 end
    if fontShadow.SetValue then fontShadow:SetValue(fsv) end
    textOutline:SetValue(DB("dmTextOutline")==true)
    local tc=DB("dmTitleColor"); if type(tc)~="table" or not tc.r then tc={r=1,g=1,b=1} end; if titleColorRow._swatch then titleColorRow._swatch:SetBackdropColor(tc.r,tc.g,tc.b,1) end
    local tx=DB("dmTextColor"); if type(tx)~="table" or not tx.r then tx={r=1,g=1,b=1} end; if textColorRow._swatch then textColorRow._swatch:SetBackdropColor(tx.r,tx.g,tx.b,1) end
    local bc=DB("dmBarColor"); if type(bc)~="table" or not bc.r then bc={r=0.5,g=0.5,b=0.5} end; if barColorRow._swatch then barColorRow._swatch:SetBackdropColor(bc.r,bc.g,bc.b,1) end
    classCB:SetValue(DB("dmClassColors")~=false); totalCB:SetValue(DB("dmShowTotalBar")==true)
    accentCB:SetValue(DB("dmAccentLine")~=false); winBorderCB:SetValue(DB("dmWindowBorder")~=false); titleBorderCB:SetValue(DB("dmTitleBorder")~=false)
    if iconDD.SetValue    then iconDD:SetValue()    end
    if valDD.SetValue     then valDD:SetValue()     end
    if highlightDD.SetValue then highlightDD:SetValue() end
    if barTexDD.SetValue  then barTexDD:SetValue()  end
    if barBgDD.SetValue   then barBgDD:SetValue()   end
    if barHeight.SetValue    then barHeight:SetValue(DB("dmBarHeight") or 18) end
    if barSpacing.SetValue   then barSpacing:SetValue(DB("dmBarSpacing") or 1) end
    if barFontSize.SetValue  then barFontSize:SetValue(DB("dmFontSize") or 11) end
    if titleFontSize.SetValue then titleFontSize:SetValue(DB("dmTitleFontSize") or 10) end
    if barBright.SetValue    then barBright:SetValue((DB("dmBarBrightness") or 0.70)*100) end
    if bgAlpha.SetValue      then bgAlpha:SetValue((DB("dmBgAlpha") or 0.92)*100) end
    if titleAlpha.SetValue   then titleAlpha:SetValue((DB("dmTitleAlpha") or 1)*100) end
    if updateInt.SetValue    then updateInt:SetValue((DB("dmUpdateInterval") or 0.3)*1000) end
  end)

  return container
end