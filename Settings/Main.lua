-- LucidUI ChatOptions.lua
-- Settings dialog with 7 tabs matching the reference layout.
-- Display | Appearance | Text | Advanced | Chat Colors | Loot | QoL

local NS   = LucidUINS
local L    = LucidUIL
local DB, DBSet = NS.DB, NS.DBSet

local chatOptWin = nil

-- Reload popup
StaticPopupDialogs["LUCIDUI_CHAT_RELOAD"] = {
  text = "Reload UI to apply changes?",
  button1 = ACCEPT, button2 = CANCEL,
  OnAccept = function() ReloadUI() end,
  timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- ══════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════
--  LAYOUT HELPERS  — shared via NS so LucidMeter & Bags can use them
-- ═══════════════════════════════════════════════════════════════════════
local BD = {bgFile="Interface/Buttons/WHITE8X8",edgeFile="Interface/Buttons/WHITE8X8",edgeSize=1}

-- MakePage: scrollable page with cursor-based Append()
local function MakePage(parent)
  local sf = CreateFrame("ScrollFrame",nil,parent,"UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT",0,0); sf:SetPoint("BOTTOMRIGHT",-20,0)
  if sf.ScrollBar then sf.ScrollBar:SetAlpha(0.35) end
  local sc = CreateFrame("Frame",nil,sf); sc:SetWidth(parent:GetWidth() or 700)
  sf:SetScrollChild(sc)
  sf:HookScript("OnSizeChanged",function(_,w) sc:SetWidth(w-22) end)
  local cur=14
  local function Append(f,h)
    h=h or f:GetHeight() or 24
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", sc,"TOPLEFT", 12,-cur)
    f:SetPoint("TOPRIGHT",sc,"TOPRIGHT",-12,-cur)
    f:SetHeight(h); cur=cur+h+5; sc:SetHeight(cur+14)
  end
  return sc,Append
end

-- Accent texture helper (used in BuildChatOptionsWindow)
local function AT(win,layer,sub,x,y,w,h,a)
  local t=win:CreateTexture(nil,layer,nil,sub)
  t:SetSize(w,h); t:SetPoint("TOPLEFT",win,"TOPLEFT",x,-y)
  local ar,ag,ab=NS.ChatGetAccentRGB(); t:SetColorTexture(ar,ag,ab,a or 0.2)
  table.insert(NS.chatOptAccentTextures,{tex=t,alpha=a or 0.2})
  return t
end

-- Dash row: N dashes of width dw spaced gap px, from xOff
local function DashRow(parent,layer,xOff,yOff,dw,gap,count,a)
  local ar,ag,ab=NS.ChatGetAccentRGB()
  for i=0,count-1 do
    local t=parent:CreateTexture(nil,layer,nil,3); t:SetSize(dw,1)
    t:SetPoint("TOPLEFT",parent,"TOPLEFT",xOff+i*(dw+gap),-yOff)
    t:SetColorTexture(ar,ag,ab,a or 0.15)
    table.insert(NS.chatOptAccentTextures,{tex=t,alpha=a or 0.15})
  end
end

-- L-bracket at a corner (two bars, each 1px thick)
local function LBracket(parent,corner,size,a)
  -- corner = "TL","TR","BL","BR"
  local ar,ag,ab=NS.ChatGetAccentRGB()
  local h=parent:CreateTexture(nil,"OVERLAY",nil,5); h:SetSize(size,2)
  local v=parent:CreateTexture(nil,"OVERLAY",nil,5); v:SetSize(2,size)
  h:SetColorTexture(ar,ag,ab,a or 0.65); v:SetColorTexture(ar,ag,ab,a or 0.65)
  if corner=="TL" then
    h:SetPoint("TOPLEFT",parent,"TOPLEFT",0,-1)
    v:SetPoint("TOPLEFT",parent,"TOPLEFT",0,-1)
  elseif corner=="TR" then
    h:SetPoint("TOPRIGHT",parent,"TOPRIGHT",0,-1)
    v:SetPoint("TOPRIGHT",parent,"TOPRIGHT",-1,-1)
  elseif corner=="BL" then
    h:SetPoint("BOTTOMLEFT",parent,"BOTTOMLEFT",0,1)
    v:SetPoint("BOTTOMLEFT",parent,"BOTTOMLEFT",0,1)
  elseif corner=="BR" then
    h:SetPoint("BOTTOMRIGHT",parent,"BOTTOMRIGHT",0,1)
    v:SetPoint("BOTTOMRIGHT",parent,"BOTTOMRIGHT",-1,1)
  end
  for _,t in ipairs({h,v}) do table.insert(NS.chatOptAccentTextures,{tex=t,alpha=a or 0.65}) end
end

-- MakeCard: cyberpunk card with L-brackets, double bar, diamond title
local function MakeCard(sc,title)
  local TPAD = title and 26 or 10; local BPAD=10; local IPAD=10
  local card = CreateFrame("Frame",nil,sc,"BackdropTemplate")
  card:SetBackdrop(BD)
  card:SetBackdropColor(0.034,0.034,0.056,1)
  card:SetBackdropBorderColor(0.08,0.08,0.13,1)
  local ar,ag,ab = NS.ChatGetAccentRGB()

  -- Double left accent bar (main 3px + thin shadow 1px offset)
  local bar=card:CreateTexture(nil,"OVERLAY",nil,5); bar:SetWidth(3)
  bar:SetPoint("TOPLEFT",   card,"TOPLEFT",   0,-5)
  bar:SetPoint("BOTTOMLEFT",card,"BOTTOMLEFT",0, 5)
  bar:SetColorTexture(ar,ag,ab,1); card._bar=bar
  table.insert(NS.chatOptAccentTextures,{tex=bar,alpha=1})
  local bar2=card:CreateTexture(nil,"OVERLAY",nil,4); bar2:SetWidth(1)
  bar2:SetPoint("TOPLEFT",   card,"TOPLEFT",   4,-8)
  bar2:SetPoint("BOTTOMLEFT",card,"BOTTOMLEFT",4, 8)
  bar2:SetColorTexture(ar,ag,ab,0.30)
  table.insert(NS.chatOptAccentTextures,{tex=bar2,alpha=0.30})

  -- L-brackets on top-right and bottom-right
  LBracket(card,"TR",14,0.55); LBracket(card,"BR",10,0.30)

  -- Tiny staircase diagonal on top-right corner (inside the bracket)
  for i=0,3 do
    local st=card:CreateTexture(nil,"OVERLAY",nil,4); st:SetSize(4-i,1)
    st:SetPoint("TOPRIGHT",card,"TOPRIGHT",-(15+i*5),-(3+i*2))
    st:SetColorTexture(ar,ag,ab,0.20-i*0.04)
    table.insert(NS.chatOptAccentTextures,{tex=st,alpha=0.20-i*0.04})
  end

  if title then
    -- Diamond bullet + title
    local fs=card:CreateFontString(nil,"OVERLAY")
    fs:SetFont("Fonts/FRIZQT__.TTF",9,"OUTLINE")
    fs:SetPoint("TOPLEFT",10,-7)
    fs:SetTextColor(ar,ag,ab,1)
    fs:SetText("> "..title:upper())
    table.insert(NS.chatOptAccentTextures,{tex=fs,isFS=true,alpha=1})
    -- Dashed separator after title (4 segments)
    DashRow(card,"OVERLAY",12,20, 18,6,5, 0.18)
  end

  local inner=CreateFrame("Frame",nil,card)
  inner:SetPoint("TOPLEFT",   card,"TOPLEFT",   IPAD,-TPAD)
  inner:SetPoint("BOTTOMRIGHT",card,"BOTTOMRIGHT",-IPAD,BPAD)
  card.inner=inner
  local iy=0
  function card:Row(f,h)
    h=h or f:GetHeight() or 26
    f:SetParent(inner); f:ClearAllPoints()
    f:SetPoint("TOPLEFT", inner,"TOPLEFT", 0,-iy)
    f:SetPoint("TOPRIGHT",inner,"TOPRIGHT",0,-iy)
    f:SetHeight(h); iy=iy+h+3
  end
  function card:Finish() card:SetHeight(TPAD+iy+BPAD-3) end
  -- Dynamic height for animated children (Appearance slide)
  function card:SetDynHeight(extra)
    card:SetHeight(TPAD+iy+BPAD-3+(extra or 0))
  end
  card._iy = function() return iy end
  return card
end

local function Sep(sc) local f=CreateFrame("Frame",nil,sc); f:SetHeight(5); return f end

-- R: re-parent and position a NS widget inside a card row
local function R(card,widget,h)
  h=h or widget:GetHeight() or 26
  widget:SetParent(card.inner); widget:ClearAllPoints()
  card:Row(widget,h)
  widget:SetPoint("LEFT", card.inner,"LEFT",  0,0)
  widget:SetPoint("RIGHT",card.inner,"RIGHT", 0,0)
end

-- Expose helpers so LucidMeter & Bags settings can use them
NS._SMakeCard  = MakeCard
NS._SMakePage  = MakePage
NS._SSep       = Sep
NS._SR         = R
NS._SBD        = BD


-- ═══════════════════════════════════════════════════════════════════════
--  TAB 1: DISPLAY
-- ═══════════════════════════════════════════════════════════════════════
local function SetupDisplay(parent)
  local container=CreateFrame("Frame",nil,parent)
  local sc,Add=MakePage(container)
  local allFrames={}
  container:SetScript("OnShow",function()
    DBSet("chatClassColors",true); DBSet("chatClickableUrls",true)
    for _,f in ipairs(allFrames) do
      if f.SetValue then if f.option then f:SetValue(DB(f.option)) else f:SetValue() end end
    end
  end)
  local function CB(card,lbl,key,cb,tip)
    local w=NS.ChatGetCheckbox(card.inner,lbl,26,cb,tip); w.option=key; R(card,w,26); table.insert(allFrames,w)
  end
  local function DD(card,lbl,isCb,onCb,labels,vals)
    local w=NS.ChatGetDropdown(card.inner,lbl,isCb,onCb); w:Init(labels,vals); R(card,w,50); table.insert(allFrames,w); return w
  end
  -- Two checkboxes side-by-side in one 26px row
  local function CB2(card, lbl1, key1, cb1, tip1, lbl2, key2, cb2, tip2, arr)
    local h = CreateFrame("Frame", nil, card.inner); h:SetHeight(26)
    card:Row(h, 26)
    h:SetPoint("LEFT",  card.inner, "LEFT",  0, 0)
    h:SetPoint("RIGHT", card.inner, "RIGHT", 0, 0)
    local lh = CreateFrame("Frame", nil, h)
    lh:SetPoint("TOPLEFT",     h, "TOPLEFT",     0, 0)
    lh:SetPoint("BOTTOMRIGHT", h, "BOTTOM",     -2, 0)
    local rh = CreateFrame("Frame", nil, h)
    rh:SetPoint("TOPLEFT",     h, "TOP",          2, 0)
    rh:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT",  0, 0)
    local w1 = NS.ChatGetCheckbox(lh, lbl1, 26, cb1, tip1)
    w1:ClearAllPoints(); w1:SetAllPoints(lh); w1.option = key1
    local w2 = NS.ChatGetCheckbox(rh, lbl2, 26, cb2, tip2)
    w2:ClearAllPoints(); w2:SetAllPoints(rh); w2.option = key2
    table.insert(allFrames, w1); table.insert(allFrames, w2)
    return w1, w2
  end
  local c3=MakeCard(sc,"Custom Chat System")
  local chatEnableCB = NS.ChatGetCheckbox(c3.inner, L["Enable Custom Chat"].."  |cff555555(reload)|r", 26, function(s)
    DBSet("chatEnabled", s)
    StaticPopup_Show("LUCIDUI_CHAT_RELOAD")
  end, L["chat_toggle_tt1"])
  chatEnableCB.option = "chatEnabled"
  R(c3, chatEnableCB, 26)
  table.insert(allFrames, chatEnableCB)
  c3:Finish(); Add(c3); Add(Sep(sc),9)
  local c1=MakeCard(sc,"Messages")
  CB2(c1,"Show vertical separator","chatShowSeparator",function(s) DBSet("chatShowSeparator",s); if NS.chatRedraw then NS.chatRedraw() end; if NS.RedrawMessages then NS.RedrawMessages() end end,"Separator",
      "Show tab separator","chatTabSeparator",function(s) DBSet("chatTabSeparator",s); if NS.chatRefreshTabs then NS.chatRefreshTabs() end end,"Accent line on tab edge")
  CB2(c1,"Combat Log tab","chatCombatLog",function(s) DBSet("chatCombatLog",s); if s then if NS.EnsureCombatLogTab then NS.EnsureCombatLogTab() end else if NS.RemoveCombatLogTab then NS.RemoveCombatLogTab() end end end,"Embed native combat log",
      "Show minimap button","chatShowMinimap",function(s) DBSet("chatShowMinimap",s); if NS.UpdateMinimapButton then NS.UpdateMinimapButton() end end,"Minimap quick-access icon")
  c1:Finish(); Add(c1); Add(Sep(sc),9)
  local c2=MakeCard(sc,"Behavior")
  DD(c2,"Timestamp",function(v) if v=="none" then return DB("chatTimestamps")==false end; return DB("chatTimestamps")~=false and DB("chatTimestampFormat")==v end,function(v) if v=="none" then DBSet("chatTimestamps",false) else DBSet("chatTimestamps",true); DBSet("chatTimestampFormat",v) end; if NS.chatDisplay and NS.chatDisplay.RecomputeTimestampWidth then NS.chatDisplay:RecomputeTimestampWidth() end; if NS.chatRedraw then NS.chatRedraw() end; if NS.RedrawMessages then NS.RedrawMessages() end end,{"None","HH:MM","HH:MM:SS","HH:MM AM/PM","HH:MM:SS AM/PM"},{"none","%H:%M","%X","%I:%M %p","%I:%M:%S %p"})
  DD(c2,"Channel format",function(v) return (DB("chatShortenFormat") or "none")==v end,function(v) DBSet("chatShortenFormat",v) end,{"Full  [1. General]","Short  (1)(S)","Minimal  1 S"},{"none","bracket","minimal"})
  DD(c2,"Flash tabs on",function(v) return (DB("chatTabFlash") or "all")==v end,function(v) DBSet("chatTabFlash",v) end,{"Never","All messages","Whispers only"},{"never","all","whisper"})
  CB(c2,"New whispers open tab","chatWhisperTab",function(s) DBSet("chatWhisperTab",s) end,"New tab per whisper")
  CB2(c2,"Store messages","chatStoreMessages",function(s) DBSet("chatStoreMessages",s) end,"Remember between sessions",
      "Remove old messages","chatRemoveOldMessages",function(s) DBSet("chatRemoveOldMessages",s) end,"Delete oldest at limit")
  c2:Finish(); Add(c2)
  return container
end


-- ═══════════════════════════════════════════════════════════════════════
--  TAB 2: APPEARANCE  (fixed collapsing + card layout)
-- ═══════════════════════════════════════════════════════════════════════
local function SetupAppearance(parent)
  local container=CreateFrame("Frame",nil,parent)
  local sc,Add=MakePage(container)
  local ar,ag,ab=NS.ChatGetAccentRGB()
  local ACCENT={ar,ag,ab}
  local isCustom=DB("theme")=="custom"
  local themeButtons={}
  local ANIM_SPD=320

  -- ── Card: Theme ─────────────────────────────────────────────────────
  local cTheme=MakeCard(sc,"Theme")

  local btnRow=CreateFrame("Frame",nil,cTheme.inner); btnRow:SetHeight(28)
  local function MakeThemeBtn(lbl,key,anchorPt,xOff)
    local btn=CreateFrame("Button",nil,btnRow,"BackdropTemplate"); btn:SetSize(0,24); btn:SetBackdrop(BD)
    btn:SetBackdropColor(0.04,0.04,0.07,1)
    local act=isCustom==(key=="custom")
    local cr,cg,cb=NS.ChatGetAccentRGB()
    btn:SetBackdropBorderColor(act and cr or 0.12,act and cg or 0.12,act and cb or 0.12,1)
    -- corner cut
    local cut=btn:CreateTexture(nil,"OVERLAY",nil,4); cut:SetSize(10,1); cut:SetPoint("TOPRIGHT",btn,"TOPRIGHT",0,-1); cut:SetColorTexture(ar,ag,ab,0.40)
    local fs=btn:CreateFontString(nil,"OVERLAY"); fs:SetFont("Fonts/FRIZQT__.TTF",10,""); fs:SetPoint("CENTER",0,0); fs:SetTextColor(0.80,0.80,0.88); fs:SetText(lbl)
    btn:SetScript("OnEnter",function() local cr2,cg2,cb2=NS.ChatGetAccentRGB(); btn:SetBackdropBorderColor(cr2,cg2,cb2,1) end)
    btn:SetScript("OnLeave",function() local a=isCustom==(key=="custom"); local cr2,cg2,cb2=NS.ChatGetAccentRGB(); btn:SetBackdropBorderColor(a and cr2 or 0.12,a and cg2 or 0.12,a and cb2 or 0.12,1) end)
    btn:SetPoint(anchorPt,btnRow,anchorPt,xOff,0)
    table.insert(themeButtons,{btn=btn,key=key}); NS._themeButtons=themeButtons
    return btn
  end
  local defaultBtn=MakeThemeBtn("DEFAULT","default","TOPLEFT",0)
  local customBtn =MakeThemeBtn("CUSTOM", "custom", "TOPRIGHT",0)
  btnRow:SetScript("OnShow",function(self)
    local w=math.floor((self:GetWidth()-6)/2)
    defaultBtn:SetWidth(w); defaultBtn:ClearAllPoints(); defaultBtn:SetPoint("TOPLEFT",self,"TOPLEFT",0,0)
    customBtn:SetWidth(w);  customBtn:ClearAllPoints();  customBtn:SetPoint("TOPRIGHT",self,"TOPRIGHT",0,0)
  end)
  cTheme:Row(btnRow,28)

  -- ── Slide container for color rows ─────────────────────────────────
  local COLOR_ROWS={
    {"Accent Color","customTilders","The main accent / neon highlight color"},
    {"Chat Background","chatBgColor","Background of the chat window"},
    {"Tab Bar","chatTabBarColor","Tab bar background"},
    {"Edit Box","chatEditBoxColor","Input box background"},
    {"Icon Color","chatIconColor","Toolbar icon tint"},
    {"Timestamp Color","chatTimestampColor","Timestamp text color"},
  }
  local ROW_H=26; local FULL_H=#COLOR_ROWS*ROW_H+14

  local slide=CreateFrame("Frame",nil,cTheme.inner); slide:SetClipsChildren(true)
  -- Anchor below btnRow, not via card:Row (dynamic height)
  slide:SetPoint("TOPLEFT", cTheme.inner,"TOPLEFT", 0,-(28+6))
  slide:SetPoint("TOPRIGHT",cTheme.inner,"TOPRIGHT",0,-(28+6))
  slide:SetHeight(isCustom and FULL_H or 0); slide:SetShown(isCustom)

  -- Slide top line
  local stl=slide:CreateTexture(nil,"OVERLAY",nil,4); stl:SetHeight(1)
  stl:SetPoint("TOPLEFT",1,0); stl:SetPoint("TOPRIGHT",-1,0); stl:SetColorTexture(ar,ag,ab,0.20)
  table.insert(NS.chatOptAccentTextures,{tex=stl,alpha=0.20})

  local colorSwatches={}
  local iy2=-8
  for _,row in ipairs(COLOR_ROWS) do
    local rowLabel,dbKey,rowTip=row[1],row[2],row[3]
    local stored=DB(dbKey); local cr2,cg2,cb2=0,0,0
    if stored and type(stored)=="table" then
      if stored.r then cr2,cg2,cb2=stored.r,stored.g,stored.b elseif stored[1] then cr2,cg2,cb2=stored[1],stored[2],stored[3] end
    end
    local capturedKey=dbKey
    local colorRow=NS.ChatGetColorRow(slide,rowLabel,cr2,cg2,cb2,rowTip,function(r,g,b)
      if capturedKey=="customTilders" then DBSet(capturedKey,{r,g,b,1}) else DBSet(capturedKey,{r=r,g=g,b=b}) end
      if capturedKey=="customTilders" then
        NS.CYAN[1],NS.CYAN[2],NS.CYAN[3]=r,g,b; ACCENT[1],ACCENT[2],ACCENT[3]=r,g,b
        NS.DARK_THEME.tilders={r,g,b,1}; NS.ApplyTheme(DB("theme"))
        if NS.chatRefreshTabs then NS.chatRefreshTabs() end
        if NS.UpdateChatBarAccent then NS.UpdateChatBarAccent() end
        if NS.chatRedraw then NS.chatRedraw(true) end
        if NS.RedrawMessages then NS.RedrawMessages() end
        if NS.RefreshSettingsAccent then NS.RefreshSettingsAccent() end
      elseif capturedKey=="chatBgColor" then
        if NS.chatBg then NS.chatBg:SetBackdropColor(r,g,b,1-(DB("chatBgAlpha") or 0.5)) end
      elseif capturedKey=="chatTabBarColor" then
        if NS.chatTabBarBg then NS.chatTabBarBg:SetColorTexture(r,g,b,1-(DB("chatTabBarAlpha") or 0.5)) end
      elseif capturedKey=="chatEditBoxColor" then
        if NS.chatEditContainer then NS.chatEditContainer:SetBackdropColor(r,g,b,1-(DB("chatBgAlpha") or 0.5)) end
      elseif capturedKey=="chatIconColor" then
        if NS.UpdateChatBarAccent then NS.UpdateChatBarAccent() end; NS.ApplyTheme(DB("theme"))
      elseif capturedKey=="chatTimestampColor" then
        if NS.chatRedraw then NS.chatRedraw(true) end; if NS.RedrawMessages then NS.RedrawMessages() end
      end
    end)
    colorRow:SetPoint("TOPLEFT", slide,"TOPLEFT", 0,iy2)
    colorRow:SetPoint("TOPRIGHT",slide,"TOPRIGHT",0,iy2)
    table.insert(colorSwatches,colorRow._swatch); iy2=iy2-ROW_H
  end

  -- Dynamic card height update (called during animation)
  local STATIC_H = 6  -- gap below btnRow (btnRow is already counted in cTheme's iy via card:Row)
  local function UpdateCardH()
    cTheme:SetDynHeight(STATIC_H + slide:GetHeight() + 4)
  end

  local function AnimateSlide(toH,onDone)
    slide:SetScript("OnUpdate",function(self,dt)
      local cur=self:GetHeight(); local diff=toH-cur
      if math.abs(diff)<1 then
        self:SetHeight(toH); self:SetScript("OnUpdate",nil); UpdateCardH()
        if onDone then onDone() end; return
      end
      local step=ANIM_SPD*dt
      self:SetHeight(cur+(diff>0 and math.min(step,diff) or math.max(-step,diff)))
      UpdateCardH()
    end)
  end

  local function RefreshThemeBtns()
    local cr,cg,cb=NS.ChatGetAccentRGB()
    for _,b in ipairs(themeButtons) do
      local a=isCustom==(b.key=="custom")
      b.btn:SetBackdropBorderColor(a and cr or 0.12,a and cg or 0.12,a and cb or 0.12,1)
    end; NS._themeButtons=themeButtons
  end

  local function RefreshCustom()
    RefreshThemeBtns()
    if isCustom then slide:Show(); AnimateSlide(FULL_H)
    else AnimateSlide(0,function() slide:Hide() end) end
  end

  defaultBtn:SetScript("OnClick",function()
    isCustom=false; DBSet("theme","default")
    NS.CYAN[1],NS.CYAN[2],NS.CYAN[3]=59/255,210/255,237/255
    NS.DARK_THEME.tilders={59/255,210/255,237/255,1}
    ACCENT[1],ACCENT[2],ACCENT[3]=59/255,210/255,237/255
    NS.ApplyTheme("default")
    if NS.chatRefreshTabs then NS.chatRefreshTabs() end
    if NS.UpdateChatBarAccent then NS.UpdateChatBarAccent() end
    if NS.chatRedraw then NS.chatRedraw(true) end
    if NS.RedrawMessages then NS.RedrawMessages() end
    if NS.ApplyChatTransparency then NS.ApplyChatTransparency() end
    if NS.RefreshSettingsAccent then NS.RefreshSettingsAccent() end
    RefreshCustom()
  end)
  customBtn:SetScript("OnClick",function()
    isCustom=true; DBSet("theme","custom")
    local s=DB("customTilders")
    if s and type(s)=="table" then
      local cr3,cg3,cb3
      if s.r then cr3,cg3,cb3=s.r,s.g,s.b elseif s[1] then cr3,cg3,cb3=s[1],s[2],s[3] end
      if cr3 then NS.CYAN[1],NS.CYAN[2],NS.CYAN[3]=cr3,cg3,cb3; NS.DARK_THEME.tilders={cr3,cg3,cb3,1}; ACCENT[1],ACCENT[2],ACCENT[3]=cr3,cg3,cb3 end
    end
    NS.ApplyTheme("custom")
    if NS.chatRefreshTabs then NS.chatRefreshTabs() end
    if NS.UpdateChatBarAccent then NS.UpdateChatBarAccent() end
    if NS.chatRedraw then NS.chatRedraw(true) end
    if NS.RedrawMessages then NS.RedrawMessages() end
    if NS.ApplyChatTransparency then NS.ApplyChatTransparency() end
    if NS.RefreshSettingsAccent then NS.RefreshSettingsAccent() end
    RefreshCustom()
  end)

  -- Finish card with static height, slide adds extra dynamically
  cTheme:Finish(); UpdateCardH()

  -- Anchor cTheme at top, others chain off it directly
  cTheme:ClearAllPoints()
  cTheme:SetPoint("TOPLEFT",  sc, "TOPLEFT",  12, -14)
  cTheme:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -12, -14)

  -- ── Card: Visibility ───────────────────────────────────────────────
  local cVis=MakeCard(sc,"Visibility"); local visCBs={}
  local function VCB(lbl,key,cb,tip) local w=NS.ChatGetCheckbox(cVis.inner,lbl,26,cb,tip); w.option=key; R(cVis,w,26); table.insert(visCBs,w) end
  local function VCB2(lbl1,key1,cb1,tip1,lbl2,key2,cb2,tip2)
    local holder = CreateFrame("Frame",nil,cVis.inner); holder:SetHeight(26)
    cVis:Row(holder,26)
    holder:SetPoint("LEFT",cVis.inner,"LEFT",0,0); holder:SetPoint("RIGHT",cVis.inner,"RIGHT",0,0)
    local lh=CreateFrame("Frame",nil,holder); lh:SetPoint("TOPLEFT",holder,"TOPLEFT",0,0); lh:SetPoint("BOTTOMRIGHT",holder,"BOTTOM",-2,0)
    local rh=CreateFrame("Frame",nil,holder); rh:SetPoint("TOPLEFT",holder,"TOP",2,0); rh:SetPoint("BOTTOMRIGHT",holder,"BOTTOMRIGHT",0,0)
    local w1=NS.ChatGetCheckbox(lh,lbl1,26,cb1,tip1); w1:ClearAllPoints(); w1:SetAllPoints(lh); w1.option=key1; table.insert(visCBs,w1)
    local w2=NS.ChatGetCheckbox(rh,lbl2,26,cb2,tip2); w2:ClearAllPoints(); w2:SetAllPoints(rh); w2.option=key2; table.insert(visCBs,w2)
  end
  VCB2("Tab highlight background","chatTabHighlightBg",function(s) DBSet("chatTabHighlightBg",s); if NS.chatRefreshTabs then NS.chatRefreshTabs() end end,"Colored bg on active tab",
       "Editbox accent border","chatEditBoxAccentBorder",function(s) DBSet("chatEditBoxAccentBorder",s); if NS.chatEditContainer then local cr,cg,cb=NS.ChatGetAccentRGB(); NS.chatEditContainer:SetBackdropBorderColor(s and cr or 0.15,s and cg or 0.15,s and cb or 0.15,1) end end,"Accent border on input box")
  VCB("Chat accent line","chatAccentLine",function(s)
    DBSet("chatAccentLine",s)
    if NS.chatBg and NS.chatBg._chatAccentLine then NS.chatBg._chatAccentLine:SetShown(s) end
  end,"Accent line at top of chat area")
  cVis:Finish()
  cVis:ClearAllPoints()
  cVis:SetPoint("TOPLEFT",  cTheme, "BOTTOMLEFT",  0, -8)
  cVis:SetPoint("TOPRIGHT", cTheme, "BOTTOMRIGHT", 0, -8)

  -- ── Card: Transparency ─────────────────────────────────────────────
  local cAlpha=MakeCard(sc,"Transparency")
  local chatTrans,tabTrans
  chatTrans=NS.ChatGetSlider(cAlpha.inner,"Chat background",0,100,"%d%%",function()
    DBSet("chatBgAlpha",chatTrans:GetValue()/100); if NS.ApplyChatTransparency then NS.ApplyChatTransparency() end
  end); chatTrans.option="chatBgAlpha"; chatTrans._isPercent=true; R(cAlpha,chatTrans,40)
  tabTrans=NS.ChatGetSlider(cAlpha.inner,"Tab bar",0,100,"%d%%",function()
    DBSet("chatTabBarAlpha",tabTrans:GetValue()/100); if NS.ApplyChatTransparency then NS.ApplyChatTransparency() end
  end); tabTrans.option="chatTabBarAlpha"; tabTrans._isPercent=true; R(cAlpha,tabTrans,40)
  cAlpha:Finish()
  cAlpha:ClearAllPoints()
  cAlpha:SetPoint("TOPLEFT",  cVis, "BOTTOMLEFT",  0, -8)
  cAlpha:SetPoint("TOPRIGHT", cVis, "BOTTOMRIGHT", 0, -8)

  -- Scrollchild height follows the last card
  -- Give sc an initial non-zero height so the scroll frame renders content immediately.
  sc:SetHeight(600)

  local function UpdateScrollH()
    C_Timer.After(0, function()
      -- Use sc:GetTop() (not cTheme:GetTop()) so the full top-gap is included.
      local top = sc:GetTop()
      local bot = cAlpha:GetBottom()
      if top and bot then
        sc:SetHeight(math.max(top - bot + 20, 300))
      end
    end)
  end
  cTheme:HookScript("OnSizeChanged", UpdateScrollH)

  -- IMPORTANT: SetScript must come BEFORE HookScript.
  -- HookScript works by wrapping the current handler via an internal SetScript call.
  -- If SetScript is called afterwards it replaces that wrapper, losing the hook.
  container:SetScript("OnShow",function()
    isCustom=DB("theme")=="custom"
    slide:SetScript("OnUpdate",nil)
    slide:SetHeight(isCustom and FULL_H or 0); slide:SetShown(isCustom); UpdateCardH()
    RefreshThemeBtns()
    for i,row2 in ipairs(COLOR_ROWS) do
      local s2=DB(row2[2]); local cr4,cg4,cb4=0,0,0
      if s2 and type(s2)=="table" then
        if s2.r then cr4,cg4,cb4=s2.r,s2.g,s2.b elseif s2[1] then cr4,cg4,cb4=s2[1],s2[2],s2[3] end
      end
      if colorSwatches[i] then colorSwatches[i]:SetBackdropColor(cr4,cg4,cb4,1) end
    end
    for _,w in ipairs(visCBs) do if w.option then w:SetValue(DB(w.option)) end end
    chatTrans:SetValue((DB("chatBgAlpha") or 0.5)*100)
    tabTrans:SetValue((DB("chatTabBarAlpha") or 0.5)*100)
  end)
  -- HookScript MUST come after SetScript (HookScript wraps via internal SetScript;
  -- a later SetScript would overwrite that wrapper, silently losing the hook).
  container:HookScript("OnShow", UpdateScrollH)
  return container
end


-- ═══════════════════════════════════════════════════════════════════════
--  TAB 3: TEXT
-- ═══════════════════════════════════════════════════════════════════════
local function SetupText(parent)
  local container=CreateFrame("Frame",nil,parent); local sc,Add=MakePage(container); local all={}
  local function ApplyFontLive()
    local font=NS.GetFontPath(DB("chatFont") or DB("font")); local size=DB("chatFontSize") or 14
    local outline=DB("chatFontOutline") or ""; local shadow=DB("chatFontShadow")
    if NS.chatDisplay and NS.chatDisplay.SetFont then
      NS.chatDisplay:SetFont(font,size,outline)
      if NS.chatDisplay.SetShadowOffset then NS.chatDisplay:SetShadowOffset(shadow and 1 or 0,shadow and -1 or 0); NS.chatDisplay:SetShadowColor(0,0,0,shadow and 0.8 or 0) end
    end
    if NS.smf then NS.smf:SetFont(font,size,outline) end
  end
  local cFont=MakeCard(sc,"Chat Font")
  local fontDD=NS.ChatGetDropdown(cFont.inner,"Message Font"); R(cFont,fontDD,50); table.insert(all,fontDD)
  local fontSize; fontSize=NS.ChatGetSlider(cFont.inner,"Font Size",2,40,"%spx",function() DBSet("chatFontSize",fontSize:GetValue()); ApplyFontLive() end); fontSize.option="chatFontSize"; R(cFont,fontSize,40); table.insert(all,fontSize)
  local msgSpacing; msgSpacing=NS.ChatGetSlider(cFont.inner,"Spacing",0,60,"%spx",function() DBSet("chatMessageSpacing",msgSpacing:GetValue()); if NS.chatDisplay and NS.chatDisplay.SetSpacing then NS.chatDisplay:SetSpacing(msgSpacing:GetValue()) end; if NS.smf then NS.smf:SetSpacing(msgSpacing:GetValue()) end end); msgSpacing.option="chatMessageSpacing"; R(cFont,msgSpacing,40); table.insert(all,msgSpacing)
  local outlineDD=NS.ChatGetDropdown(cFont.inner,"Outline",function(v) return (DB("chatFontOutline") or "")==v end,function(v) DBSet("chatFontOutline",v); ApplyFontLive() end); outlineDD:Init({"None","Outline","Thick"},{"","OUTLINE","THICKOUTLINE"}); R(cFont,outlineDD,50); table.insert(all,outlineDD)
  local fontShadow=NS.ChatGetCheckbox(cFont.inner,"Font Shadow",26,function(s) DBSet("chatFontShadow",s); ApplyFontLive() end,"Drop shadow behind text"); fontShadow.option="chatFontShadow"; R(cFont,fontShadow,26); table.insert(all,fontShadow)
  cFont:Finish(); Add(cFont); Add(Sep(sc),9)
  local cFade=MakeCard(sc,"Fade")
  -- Enable toggles side by side
  local fadeEnableHolder=CreateFrame("Frame",nil,cFade.inner); fadeEnableHolder:SetHeight(26)
  cFade:Row(fadeEnableHolder,26)
  fadeEnableHolder:SetPoint("LEFT",cFade.inner,"LEFT",0,0); fadeEnableHolder:SetPoint("RIGHT",cFade.inner,"RIGHT",0,0)
  local flh=CreateFrame("Frame",nil,fadeEnableHolder); flh:SetPoint("TOPLEFT",fadeEnableHolder,"TOPLEFT",0,0); flh:SetPoint("BOTTOMRIGHT",fadeEnableHolder,"BOTTOM",-2,0)
  local frh=CreateFrame("Frame",nil,fadeEnableHolder); frh:SetPoint("TOPLEFT",fadeEnableHolder,"TOP",2,0); frh:SetPoint("BOTTOMRIGHT",fadeEnableHolder,"BOTTOMRIGHT",0,0)
  local enableFade=NS.ChatGetCheckbox(flh,"Enable Message Fade",26,function(s) DBSet("chatMessageFade",s); if NS.chatDisplay and NS.chatDisplay.SetFading then NS.chatDisplay:SetFading(s) end end,"Fade out old messages")
  enableFade:ClearAllPoints(); enableFade:SetAllPoints(flh); enableFade.option="chatMessageFade"; table.insert(all,enableFade)
  local enableLootFade=NS.ChatGetCheckbox(frh,"Enable Loot Fade",26,function(s) DBSet("enableFade",s); NS.ApplyFade() end,"Fade LootTracker messages")
  enableLootFade:ClearAllPoints(); enableLootFade:SetAllPoints(frh); enableLootFade.option="enableFade"; table.insert(all,enableLootFade)
  -- Time sliders
  local fadeTime; fadeTime=NS.ChatGetSlider(cFade.inner,"Message Fade Time",5,240,"%ss",function() DBSet("chatFadeTime",fadeTime:GetValue()); if NS.chatDisplay and NS.chatDisplay.SetTimeVisible then NS.chatDisplay:SetTimeVisible(fadeTime:GetValue()) end end); fadeTime.option="chatFadeTime"; R(cFade,fadeTime,40); table.insert(all,fadeTime)
  local lootFadeTime; lootFadeTime=NS.ChatGetSlider(cFade.inner,"Loot Fade Time",5,240,"%ss",function() DBSet("fadeTime",lootFadeTime:GetValue()); NS.ApplyFade() end); lootFadeTime.option="fadeTime"; R(cFade,lootFadeTime,40); table.insert(all,lootFadeTime)
  cFade:Finish(); Add(cFade)
  container:SetScript("OnShow",function()
    NS.InvalidateLSMCache()
    local fonts=NS.GetLSMFonts(); local fVals,fLabels={"default"},{"Default"}
    for _,f in ipairs(fonts) do fLabels[#fLabels+1]=f.label; fVals[#fVals+1]=f.label end
    fontDD.DropDown:SetupMenu(function(_,root)
      for i,lbl in ipairs(fLabels) do local ci=i
        root:CreateRadio(lbl,function() return (DB("chatFont") or "Friz Quadrata")==fVals[ci] end,function() DBSet("chatFont",fVals[ci]); ApplyFontLive() end)
      end; root:SetScrollMode(20*20)
    end)
    for _,f in ipairs(all) do
      if f.SetValue and f.option then if f._isPercent then f:SetValue((DB(f.option) or 0)*100) else f:SetValue(DB(f.option)) end
      elseif f.SetValue then f:SetValue() end
    end
  end)
  return container
end


-- ═══════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════
--  TAB 4: ADVANCED
-- ═══════════════════════════════════════════════════════════════════════
local function SetupAdvanced(parent)
  local container=CreateFrame("Frame",nil,parent)
  local sc,Add=MakePage(container)
  local allLayout={}
  local allFrames={}  -- used by pasted original profile/export/import code

  -- ── Card: Profiles ─────────────────────────────────────────────────
  local cProf=MakeCard(sc,"Profiles")
  local profileRow=CreateFrame("Frame",nil,cProf.inner); profileRow:SetHeight(26)

  local function MakeIEBtn(par,txt)
    local btn=CreateFrame("Button",nil,par,"BackdropTemplate"); btn:SetSize(88,22); btn:SetBackdrop(BD)
    btn:SetBackdropColor(0.04,0.04,0.07,1); btn:SetBackdropBorderColor(0.12,0.12,0.20,1)
    local cut=btn:CreateTexture(nil,"OVERLAY",nil,4); cut:SetSize(8,1); cut:SetPoint("TOPRIGHT",btn,"TOPRIGHT",0,-1); cut:SetColorTexture(0,1,1,0.25)
    local fs=btn:CreateFontString(nil,"OVERLAY"); fs:SetFont("Fonts/FRIZQT__.TTF",10,""); fs:SetPoint("CENTER",0,0); fs:SetTextColor(0.75,0.75,0.85); fs:SetText(txt)
    btn:SetScript("OnEnter",function() local cr,cg,cb=NS.ChatGetAccentRGB(); btn:SetBackdropBorderColor(cr,cg,cb,0.8) end)
    btn:SetScript("OnLeave",function() btn:SetBackdropBorderColor(0.12,0.12,0.20,1) end)
    return btn
  end

  profileRow:SetPoint("RIGHT", -50, 0)
  table.insert(allFrames, profileRow)

  -- Styled button helper for Export/Import
  local function MakeIEButton(parent, text)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetHeight(22)
    btn:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
    btn:SetBackdropColor(0.08, 0.08, 0.08, 1)
    btn:SetBackdropBorderColor(0.22, 0.22, 0.22, 1)
    local lbl = btn:CreateFontString(nil, "OVERLAY")
    lbl:SetFont("Fonts/FRIZQT__.TTF", 11, ""); lbl:SetPoint("CENTER")
    lbl:SetTextColor(1, 1, 1, 1); lbl:SetText(text)
    btn._label = lbl
    btn:SetScript("OnEnter", function() btn:SetBackdropBorderColor(NS.ChatGetAccentRGB()) end)
    btn:SetScript("OnLeave", function() btn:SetBackdropBorderColor(0.22, 0.22, 0.22, 1) end)
    return btn
  end

  -- Profile dropdown (real WowStyle1DropdownTemplate)
  local profileDD = CreateFrame("DropdownButton", nil, profileRow, "WowStyle1DropdownTemplate")
  profileDD:SetPoint("TOPLEFT", profileRow, "TOPLEFT", 0, 0)

  -- Skin dropdown
  for _, region in pairs({profileDD:GetRegions()}) do
    if region:IsObjectType("Texture") then region:SetAlpha(0) end
  end
  if profileDD.Arrow then profileDD.Arrow:SetAlpha(0) end
  local ddBd = CreateFrame("Frame", nil, profileDD, "BackdropTemplate")
  ddBd:SetAllPoints(); ddBd:SetFrameLevel(profileDD:GetFrameLevel())
  ddBd:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
  ddBd:SetBackdropColor(0.08, 0.08, 0.08, 1); ddBd:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
  ddBd:EnableMouse(false)
  local ddArr = ddBd:CreateFontString(nil, "OVERLAY")
  ddArr:SetFont("Fonts/FRIZQT__.TTF", 9, ""); ddArr:SetPoint("RIGHT", -5, 0)
  local acR2, acG2, acB2 = NS.ChatGetAccentRGB()
  ddArr:SetTextColor(acR2, acG2, acB2, 1); ddArr:SetText("v")
  table.insert(NS.chatOptDropdownArrows, ddArr)
  if profileDD.Text then
    profileDD.Text:SetTextColor(0.9, 0.9, 0.9, 1)
    profileDD.Text:ClearAllPoints()
    profileDD.Text:SetPoint("LEFT", 6, 0); profileDD.Text:SetPoint("RIGHT", -18, 0)
    profileDD.Text:SetJustifyH("LEFT")
  end
  profileDD:HookScript("OnEnter", function() ddBd:SetBackdropBorderColor(NS.ChatGetAccentRGB()) end)
  profileDD:HookScript("OnLeave", function() ddBd:SetBackdropBorderColor(0.25, 0.25, 0.25, 1) end)

  -- Export and Import buttons
  local exportBtn2 = MakeIEButton(profileRow, "Export")
  local importBtn2 = MakeIEButton(profileRow, "Import")

  -- Layout: dropdown takes 1/3, export 1/3, import 1/3
  profileDD:SetPoint("TOPLEFT", profileRow, "TOPLEFT", 0, 0)
  profileDD:SetPoint("RIGHT", profileRow, "LEFT", profileRow:GetWidth() and math.floor(profileRow:GetWidth()/3) or 200, 0)
  exportBtn2:SetPoint("LEFT", profileDD, "RIGHT", 4, 0)
  importBtn2:SetPoint("RIGHT", profileRow, "RIGHT", 0, 0)

  -- Use OnShow to set correct widths after layout
  profileRow:SetScript("OnShow", function(self)
    local w = self:GetWidth()
    if not w or w < 10 then w = 600 end
    local third = math.floor((w - 8) / 3)
    profileDD:ClearAllPoints()
    profileDD:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
    profileDD:SetSize(third, 22)
    exportBtn2:ClearAllPoints()
    exportBtn2:SetPoint("LEFT", profileDD, "RIGHT", 4, 0)
    exportBtn2:SetSize(third, 22)
    importBtn2:ClearAllPoints()
    importBtn2:SetPoint("LEFT", exportBtn2, "RIGHT", 4, 0)
    importBtn2:SetSize(third, 22)
  end)

  -- Profile dropdown menu
  local function MakeProfileEntryButtons(button, profileName, isActive)
    -- Ensure R/X button frames exist on this recycled button, hide by default
    if not button._ltRenameBtn then
      local renameBtn = CreateFrame("Button", nil, button)
      renameBtn:SetSize(16, 16)
      renameBtn:SetPoint("RIGHT", button, "RIGHT", -24, 0)
      renameBtn:SetFrameLevel(button:GetFrameLevel() + 5)
      local renTex = renameBtn:CreateFontString(nil, "OVERLAY")
      renTex:SetFont("Fonts/FRIZQT__.TTF", 11, "OUTLINE")
      renTex:SetAllPoints(); renTex:SetText("R"); renTex:SetTextColor(0.6, 0.6, 0.6)
      renameBtn:SetScript("OnEnter", function()
        local ar, ag, ab = NS.ChatGetAccentRGB()
        renTex:SetTextColor(ar, ag, ab)
        GameTooltip:SetOwner(renameBtn, "ANCHOR_RIGHT"); GameTooltip:SetText(L["Rename"]); GameTooltip:Show()
      end)
      renameBtn:SetScript("OnLeave", function() renTex:SetTextColor(0.6, 0.6, 0.6); GameTooltip:Hide() end)
      button._ltRenameBtn = renameBtn
    end
    if not button._ltDeleteBtn then
      local delBtn = CreateFrame("Button", nil, button)
      delBtn:SetSize(16, 16)
      delBtn:SetPoint("RIGHT", button, "RIGHT", -6, 0)
      delBtn:SetFrameLevel(button:GetFrameLevel() + 5)
      local delTex = delBtn:CreateFontString(nil, "OVERLAY")
      delTex:SetFont("Fonts/FRIZQT__.TTF", 11, "OUTLINE")
      delTex:SetAllPoints(); delTex:SetText("X"); delTex:SetTextColor(0.6, 0.6, 0.6)
      delBtn:SetScript("OnEnter", function()
        delTex:SetTextColor(1, 0.3, 0.3)
        GameTooltip:SetOwner(delBtn, "ANCHOR_RIGHT"); GameTooltip:SetText(L["Delete"]); GameTooltip:Show()
      end)
      delBtn:SetScript("OnLeave", function() delTex:SetTextColor(0.6, 0.6, 0.6); GameTooltip:Hide() end)
      button._ltDeleteBtn = delBtn
    end

    -- Show rename, wire click
    button._ltRenameBtn:Show()
    button._ltRenameBtn:SetScript("OnClick", function()
      StaticPopupDialogs["LUI_RENAME_PROFILE"] = {
        text = "Rename profile '" .. profileName .. "':",
        hasEditBox = true, button1 = "Rename", button2 = CANCEL,
        OnShow = function(self) self.EditBox:SetText(profileName) end,
        OnAccept = function(self)
          local newName = strtrim(self.EditBox:GetText())
          if newName == "" or newName == profileName then return end
          local profiles = LucidUIDB._profiles or {}
          profiles[newName] = profiles[profileName]
          profiles[profileName] = nil
          if LucidUIDB._activeProfile == profileName then
            LucidUIDB._activeProfile = newName
          end
          NS._RebuildProfileMenu()
        end,
        timeout = 0, whileDead = true, hideOnEscape = true,
      }
      StaticPopup_Show("LUI_RENAME_PROFILE")
    end)

    -- Show delete only if not active
    if not isActive then
      button._ltDeleteBtn:Show()
      button._ltDeleteBtn:SetScript("OnClick", function()
        StaticPopupDialogs["LUI_DELETE_PROFILE"] = {
          text = "Delete profile '" .. profileName .. "' and reload UI?",
          button1 = "Delete & Reload", button2 = CANCEL,
          OnAccept = function()
            local profiles = LucidUIDB._profiles or {}
            profiles[profileName] = nil
            ReloadUI()
          end,
          timeout = 0, whileDead = true, hideOnEscape = true,
        }
        StaticPopup_Show("LUI_DELETE_PROFILE")
      end)
    else
      button._ltDeleteBtn:Hide()
    end
  end

  -- Hide R/X buttons on recycled menu buttons that don't need them
  local function HideProfileButtons(button)
    if button._ltRenameBtn then button._ltRenameBtn:Hide() end
    if button._ltDeleteBtn then button._ltDeleteBtn:Hide() end
  end

  NS._RebuildProfileMenu = function()
    profileDD:SetupMenu(function(_, rootDescription)
      local profiles = LucidUIDB and LucidUIDB._profiles or {}
      local currentProfile = LucidUIDB and LucidUIDB._activeProfile or "Default"

      local defRadio = rootDescription:CreateRadio(
        "|cff88ccffDefault|r",
        function() return currentProfile == "Default" end,
        function()
          if currentProfile ~= "Default" then
            LucidUIDB._activeProfile = "Default"
            StaticPopup_Show("LUCIDUI_CHAT_RELOAD")
          end
        end
      )
      NS.SkinMenuElement(defRadio)
      defRadio:AddInitializer(function(button) HideProfileButtons(button) end)

      local sortedNames = {}
      for name in pairs(profiles) do table.insert(sortedNames, name) end
      table.sort(sortedNames)
      for _, name in ipairs(sortedNames) do
        local isActive = (currentProfile == name)
        local capName = name
        local radio = rootDescription:CreateRadio(name,
          function() return currentProfile == capName end,
          function()
            if currentProfile ~= capName then
              LucidUIDB._activeProfile = capName
              StaticPopup_Show("LUCIDUI_CHAT_RELOAD")
            end
          end
        )
        NS.SkinMenuElement(radio)
        radio:AddInitializer(function(button)
          MakeProfileEntryButtons(button, capName, isActive)
        end)
      end

      rootDescription:CreateDivider()
      local resetBtn = rootDescription:CreateButton("|cffff4444Reset All Settings|r", function()
        StaticPopupDialogs["LUI_RESET_SETTINGS"] = {
          text = "Reset ALL LucidUI settings to defaults?\n\nRequires UI reload.",
          button1 = "Reset & Reload", button2 = CANCEL,
          OnAccept = function() LucidUIDB = {}; ReloadUI() end,
          timeout = 0, whileDead = true, hideOnEscape = true,
        }
        StaticPopup_Show("LUI_RESET_SETTINGS")
      end)
      resetBtn:AddInitializer(function(button) HideProfileButtons(button) end)
    end)
  end
  NS._RebuildProfileMenu()

  -- Export: copy all settings to clipboard
  exportBtn2:SetScript("OnClick", function()
    -- Simple table serializer
    local function Serialize(val)
      if type(val) == "table" then
        local parts = {}
        -- Check if array or dict
        local isArray = true
        local maxN = 0
        for k in pairs(val) do
          if type(k) == "number" then maxN = math.max(maxN, k)
          else isArray = false end
        end
        if isArray and maxN > 0 then
          for i = 1, maxN do table.insert(parts, Serialize(val[i])) end
          return "{" .. table.concat(parts, ",") .. "}"
        else
          for k, v in pairs(val) do
            table.insert(parts, tostring(k) .. "=" .. Serialize(v))
          end
          return "{" .. table.concat(parts, ",") .. "}"
        end
      elseif type(val) == "string" then
        return '"' .. val:gsub('"', '\\"') .. '"'
      elseif type(val) == "boolean" then
        return val and "true" or "false"
      else
        return tostring(val)
      end
    end

    local skip = {history=true, chatHistory=true, debugHistory=true, chatTabs=true, qolFpsBackup=true, _profiles=true, _activeProfile=true, _sessionData=true, _rollData=true, _rollEncounter=true}
    local lines = {"LUI_EXPORT:" .. (NS.DB("theme") or "default") .. ":" .. date("%Y%m%d")}
    for k, v in pairs(LucidUIDB or {}) do
      if not skip[k] then
        table.insert(lines, k .. "=" .. Serialize(v))
      end
    end
    local text = table.concat(lines, "\n")

    local frame = CreateFrame("Frame", "LUIExportFrame", UIParent, "BackdropTemplate")
    frame:SetSize(500, 300); frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG"); frame:SetMovable(true); frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    frame:EnableMouse(true)
    frame:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
    frame:SetBackdropColor(0.06, 0.06, 0.06, 0.95); frame:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOP", 0, -6); title:SetText(L["export_hint"])
    local ar2,ag2,ab2 = NS.ChatGetAccentRGB(); title:SetTextColor(ar2, ag2, ab2)
    local closeBtn2 = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn2:SetPoint("TOPRIGHT", 2, 2)
    closeBtn2:SetScript("OnClick", function() frame:Hide() end)
    local sf = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 10, -22); sf:SetPoint("BOTTOMRIGHT", -30, 10)
    local eb = CreateFrame("EditBox", nil, frame)
    eb:SetMultiLine(true); eb:SetAutoFocus(true); eb:SetFontObject(GameFontHighlight); eb:SetWidth(460)
    eb:SetScript("OnEscapePressed", function() frame:Hide() end)
    sf:SetScrollChild(eb)
    C_Timer.After(0, function()
      if not frame:IsShown() then return end
      eb:SetWidth(sf:GetWidth()); eb:SetText(text); eb:HighlightText()
    end)
  end)

  -- Import: paste settings
  importBtn2:SetScript("OnClick", function()
    local frame = CreateFrame("Frame", "LUIImportFrame", UIParent, "BackdropTemplate")
    frame:SetSize(500, 340); frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG"); frame:SetMovable(true); frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    frame:EnableMouse(true)
    frame:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
    frame:SetBackdropColor(0.06, 0.06, 0.06, 0.95); frame:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOP", 0, -6); title:SetText(L["import_hint"])
    local ar2,ag2,ab2 = NS.ChatGetAccentRGB(); title:SetTextColor(ar2, ag2, ab2)
    local status = frame:CreateFontString(nil, "OVERLAY")
    status:SetFont("Fonts/FRIZQT__.TTF", 10, ""); status:SetPoint("TOPLEFT", 12, -22)
    status:SetTextColor(0.6, 0.6, 0.6)
    local closeBtn2 = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn2:SetPoint("TOPRIGHT", 2, 2)
    closeBtn2:SetScript("OnClick", function() frame:Hide() end)

    -- Profile name input
    local nameLabel = frame:CreateFontString(nil, "OVERLAY")
    nameLabel:SetFont("Fonts/FRIZQT__.TTF", 10, ""); nameLabel:SetPoint("TOPLEFT", 12, -36)
    nameLabel:SetTextColor(0.7, 0.7, 0.7); nameLabel:SetText(L["Profile Name:"])
    local nameBox = CreateFrame("EditBox", nil, frame, "BackdropTemplate")
    nameBox:SetSize(200, 22); nameBox:SetPoint("LEFT", nameLabel, "RIGHT", 6, 0)
    nameBox:SetFontObject(GameFontHighlight); nameBox:SetAutoFocus(false)
    nameBox:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
    nameBox:SetBackdropColor(0.1, 0.1, 0.1, 1); nameBox:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    nameBox:SetTextInsets(4, 4, 0, 0)
    nameBox:SetScript("OnEscapePressed", function() nameBox:ClearFocus() end)
    nameBox:SetScript("OnEnterPressed", function() nameBox:ClearFocus() end)

    local sf = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 10, -60); sf:SetPoint("BOTTOMRIGHT", -30, 40)
    local eb = CreateFrame("EditBox", nil, frame)
    eb:SetMultiLine(true); eb:SetAutoFocus(true); eb:SetFontObject(GameFontHighlight); eb:SetWidth(460)
    eb:SetScript("OnEscapePressed", function() frame:Hide() end)
    sf:SetScrollChild(eb)
    C_Timer.After(0, function()
      if not frame:IsShown() then return end
      eb:SetWidth(sf:GetWidth()); eb:SetFocus()
    end)
    local doImport = MakeIEButton(frame, "Import")
    doImport:ClearAllPoints()
    doImport:SetSize(85, 24); doImport:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 10)
    doImport:SetScript("OnClick", function()
      local profileName = strtrim(nameBox:GetText())
      if profileName == "" then
        status:SetTextColor(1, 0.3, 0.3); status:SetText(L["err_no_name"]); return
      end
      local raw = strtrim(eb:GetText())
      if raw == "" then status:SetTextColor(1, 0.3, 0.3); status:SetText(L["err_no_paste"]); return end
      if not raw:match("^LUI_EXPORT:") then
        status:SetTextColor(1, 0.3, 0.3); status:SetText(L["err_bad_format"])
        return
      end
      StaticPopupDialogs["LUI_IMPORT_RELOAD"] = {
        text = "Import as profile '" .. profileName .. "' and reload UI?",
        button1 = "Import & Reload", button2 = CANCEL,
        OnAccept = function()
          -- Deserialize value string
          local function Deserialize(s)
            if s == "true" then return true end
            if s == "false" then return false end
            if s == "nil" then return nil end
            if tonumber(s) then return tonumber(s) end
            if s:match('^".*"$') then return s:sub(2, -2):gsub('\\"', '"') end
            -- Safe table parser: only handles {key=val,...} and {val,...} without loadstring
            if s:match("^{.*}$") then
              local result = {}
              local inner = s:sub(2, -2)
              -- Tokenize key=value pairs safely (no code execution)
              local i = 1
              local arrIdx = 1
              while i <= #inner do
                -- Skip whitespace and commas
                local _, eSkip = inner:find("^[%s,]*", i)
                i = (eSkip or i - 1) + 1
                if i > #inner then break end
                -- Try key=value
                local k, rest = inner:match("^([%w_]+)=(.+)", i)
                if k then
                  -- Find end of value (before next non-nested comma)
                  local depth, j = 0, 1
                  local valStr = rest
                  for ci = 1, #rest do
                    local ch = rest:sub(ci, ci)
                    if ch == "{" then depth = depth + 1
                    elseif ch == "}" then depth = depth - 1
                    elseif ch == "," and depth == 0 then
                      valStr = rest:sub(1, ci - 1)
                      i = i + #k + 1 + ci
                      break
                    end
                    if ci == #rest then i = i + #k + 1 + #rest + 1 end
                  end
                  local numKey = tonumber(k)
                  if numKey then
                    result[numKey] = Deserialize(strtrim(valStr))
                  else
                    result[k] = Deserialize(strtrim(valStr))
                  end
                else
                  -- Array value
                  local depth2 = 0
                  for ci = i, #inner do
                    local ch = inner:sub(ci, ci)
                    if ch == "{" then depth2 = depth2 + 1
                    elseif ch == "}" then depth2 = depth2 - 1
                    elseif ch == "," and depth2 == 0 then
                      result[arrIdx] = Deserialize(strtrim(inner:sub(i, ci - 1)))
                      arrIdx = arrIdx + 1
                      i = ci + 1
                      break
                    end
                    if ci == #inner then
                      result[arrIdx] = Deserialize(strtrim(inner:sub(i, ci)))
                      arrIdx = arrIdx + 1
                      i = ci + 1
                    end
                  end
                end
              end
              return result
            end
            return s
          end
          -- Build profile data from import (skip internal keys)
          local skipKeys = {_profiles=true, _activeProfile=true}
          local profileData = {}
          for line in raw:gmatch("[^\n]+") do
            local k, v = line:match("^([^=]+)=(.+)$")
            if k and v and not k:match("^LUI_EXPORT") and not skipKeys[k] then
              profileData[k] = Deserialize(v)
            end
          end
          -- Save as named profile
          LucidUIDB._profiles = LucidUIDB._profiles or {}
          LucidUIDB._profiles[profileName] = profileData
          -- Switch to the imported profile
          LucidUIDB._activeProfile = profileName
          -- Apply profile data to DB
          for k, v in pairs(profileData) do
            LucidUIDB[k] = v
          end
          ReloadUI()
        end,
        timeout = 0, whileDead = true, hideOnEscape = true,
      }
      frame:Hide()
      StaticPopup_Show("LUI_IMPORT_RELOAD")
    end)
  end)


  cProf:Row(profileRow,26); cProf:Finish(); Add(cProf); Add(Sep(sc),9)

  -- ── Card: Layout ───────────────────────────────────────────────────
  local cLayout=MakeCard(sc,"Layout")
  local function LDD(lbl,isCb,onCb,labels,vals)
    local w=NS.ChatGetDropdown(cLayout.inner,lbl,isCb,onCb); w:Init(labels,vals); R(cLayout,w,50); table.insert(allLayout,w); return w
  end
  local function LCB(lbl,key,cb,tip)
    local w=NS.ChatGetCheckbox(cLayout.inner,lbl,26,cb,tip); w.option=key; R(cLayout,w,26); table.insert(allLayout,w)
  end
  LDD("Show tabs",function(v) return (DB("chatTabVisibility") or "always")==v end,function(v) DBSet("chatTabVisibility",v); local bar=_G["LUIChatTabBar"]; if bar then bar:SetAlpha(v=="always" and 1 or 0) end end,{"Always","Mouseover"},{"always","mouseover"}).option="chatTabVisibility"
  LDD("Show buttons",function(v) return (DB("chatBarVisibility") or "always")==v end,function(v) DBSet("chatBarVisibility",v); if NS.chatBarRef then if v=="never" then NS.chatBarRef:SetAlpha(0); NS.chatBarRef:EnableMouse(false) elseif v=="mouseover" then NS.chatBarRef:SetAlpha(0); NS.chatBarRef:EnableMouse(true) else NS.chatBarRef:SetAlpha(1); NS.chatBarRef:EnableMouse(true) end end end,{"Always","Mouseover"},{"always","mouseover"}).option="chatBarVisibility"
  LDD("Button position",function(v) return (DB("chatBarPosition") or "outside_right")==v end,function(v) DBSet("chatBarPosition",v); if NS.RepositionChatBar then NS.RepositionChatBar() end end,{"Left Outside","Left Inside","Right Outside","Right Inside"},{"outside_left","inside_left","outside_right","inside_right"}).option="chatBarPosition"
  LDD("Edit box position",function(v) return (DB("chatEditBoxPos") or "bottom")==v end,function(v) DBSet("chatEditBoxPos",v); if NS.chatEditContainer and NS.chatBg then NS.chatEditContainer:ClearAllPoints(); if v=="top" then NS.chatEditContainer:SetPoint("TOPLEFT",NS.chatBg,"TOPLEFT",0,0); NS.chatEditContainer:SetPoint("TOPRIGHT",NS.chatBg,"TOPRIGHT",0,0) else NS.chatEditContainer:SetPoint("TOPLEFT",NS.chatBg,"BOTTOMLEFT",0,-1); NS.chatEditContainer:SetPoint("TOPRIGHT",NS.chatBg,"BOTTOMRIGHT",0,-1) end end end,{"Bottom","Top"},{"bottom","top"}).option="chatEditBoxPos"
  LCB("Keep edit box visible","chatEditBoxVisible",function(s) DBSet("chatEditBoxVisible",s); if NS.chatEditContainer then if s then NS.chatEditContainer:Show() else NS.chatEditContainer:Hide() end end end,"Always show the chat input box")
  cLayout:Finish(); Add(cLayout)

  container:SetScript("OnShow",function()
    if NS._RebuildProfileMenu then NS._RebuildProfileMenu() end
    for _,f in ipairs(allLayout) do if f.SetValue and f.option then f:SetValue(DB(f.option)) end end
  end)
  return container
end

-- ═══════════════════════════════════════════════════════════════════════
--  TAB 5: CHAT COLORS
-- ═══════════════════════════════════════════════════════════════════════
local MC_TYPE_LAYOUT = {
  MESSAGES = {
    {"SAY"}, {"EMOTE"}, {"YELL"}, {"TEXT_EMOTE"},
    {"GUILD"}, {"OFFICER"},
    {"GUILD_ACHIEVEMENT"}, {"ACHIEVEMENT"},
    {"WHISPER"}, {"BN_WHISPER"},
    {"PARTY"}, {"PARTY_LEADER"},
    {"RAID"}, {"RAID_LEADER"}, {"RAID_WARNING"},
    {"INSTANCE_CHAT"}, {"INSTANCE_CHAT_LEADER"},
  },
  CREATURE = {
    {"MONSTER_SAY"}, {"MONSTER_EMOTE"}, {"MONSTER_YELL"},
    {"MONSTER_WHISPER"}, {"MONSTER_BOSS_EMOTE"}, {"MONSTER_BOSS_WHISPER"},
  },
  REWARDS = {
    {"COMBAT_XP_GAIN"}, {"COMBAT_HONOR_GAIN"}, {"COMBAT_FACTION_CHANGE"},
    {"SKILL"}, {"LOOT"}, {"CURRENCY"}, {"MONEY"},
  },
  PVP = {
    {"BG_SYSTEM_HORDE"}, {"BG_SYSTEM_ALLIANCE"}, {"BG_SYSTEM_NEUTRAL"},
  },
  SYSTEM = {
    {"SYSTEM"}, {"CHANNEL"}, {"AFK"}, {"DND"},
    {"FILTERED"}, {"RESTRICTED"}, {"IGNORED"},
    {"BN_INLINE_TOAST_ALERT"},
  },
}
local MC_ORDER = {
  {"Chat",     "MESSAGES"},
  {"Creature", "CREATURE"},
  {"Rewards",  "REWARDS"},
  {"PvP",      "PVP"},
  {"System",   "SYSTEM"},
}
local EVENT_LABELS = {
  SAY="Say", EMOTE="Emote", YELL="Yell", TEXT_EMOTE="Text Emote",
  GUILD="Guild", OFFICER="Officer",
  GUILD_ACHIEVEMENT="Guild Achievement", ACHIEVEMENT="Achievement",
  WHISPER="Whisper", BN_WHISPER="BNet Whisper",
  PARTY="Party", PARTY_LEADER="Party Leader",
  RAID="Raid", RAID_LEADER="Raid Leader", RAID_WARNING="Raid Warning",
  INSTANCE_CHAT="Instance", INSTANCE_CHAT_LEADER="Instance Leader",
  MONSTER_SAY="Monster Say", MONSTER_EMOTE="Monster Emote", MONSTER_YELL="Monster Yell",
  MONSTER_WHISPER="Monster Whisper", MONSTER_BOSS_EMOTE="Boss Emote", MONSTER_BOSS_WHISPER="Boss Whisper",
  COMBAT_XP_GAIN="XP Gain", COMBAT_HONOR_GAIN="Honor", COMBAT_FACTION_CHANGE="Reputation",
  SKILL="Skill-ups", LOOT="Item Loot", CURRENCY="Currency", MONEY="Money Loot",
  BG_SYSTEM_HORDE="BG Horde", BG_SYSTEM_ALLIANCE="BG Alliance", BG_SYSTEM_NEUTRAL="BG Neutral",
  SYSTEM="System", CHANNEL="Channel", AFK="AFK", DND="DND",
  FILTERED="Filtered", RESTRICTED="Restricted", IGNORED="Ignored",
  BN_INLINE_TOAST_ALERT="BNet Toast",
}

local function SetupMessageColors(parent)
  local container=CreateFrame("Frame",nil,parent)
  local sc,Add=MakePage(container)
  local ANIM_SPD = 400
  local allCards = {}

  for _,entry in ipairs(MC_ORDER) do
    local sectionLabel,layoutKey=entry[1],entry[2]
    local fields=MC_TYPE_LAYOUT[layoutKey] or {}
    local card=MakeCard(sc,sectionLabel)
    local colors=DB("chatColors") or {}
    local collapsed = false
    local fullH -- set after Finish

    for _,f in ipairs(fields) do
      local shortKey=f[1]
      local label=EVENT_LABELS[shortKey] or shortKey
      local ci=ChatTypeInfo and ChatTypeInfo[shortKey]
      local c=colors[shortKey]
      if not c and ci then c={r=ci.r,g=ci.g,b=ci.b} end
      c=c or {r=1,g=1,b=1}

      local rowF=CreateFrame("Frame",nil,card.inner); rowF:SetHeight(26)
      local rowHL=rowF:CreateTexture(nil,"BACKGROUND"); rowHL:SetAllPoints(); rowHL:SetColorTexture(1,1,1,0.04); rowHL:Hide()
      local lbl=rowF:CreateFontString(nil,"OVERLAY"); lbl:SetFont("Fonts/FRIZQT__.TTF",11,""); lbl:SetPoint("LEFT",2,0); lbl:SetTextColor(c.r,c.g,c.b); lbl:SetText(label)
      local sw=CreateFrame("Frame",nil,rowF,"BackdropTemplate"); sw:SetSize(16,16); sw:SetPoint("RIGHT",-44,0)
      sw:SetBackdrop(BD); sw:SetBackdropColor(c.r,c.g,c.b,1); sw:SetBackdropBorderColor(0.30,0.30,0.40,1)
      local resetBtn=CreateFrame("Button",nil,rowF); resetBtn:SetSize(38,16); resetBtn:SetPoint("LEFT",sw,"RIGHT",5,0)
      local resetLbl=resetBtn:CreateFontString(nil,"OVERLAY"); resetLbl:SetFont("Fonts/FRIZQT__.TTF",9,""); resetLbl:SetAllPoints(); resetLbl:SetJustifyH("LEFT"); resetLbl:SetTextColor(0.45,0.45,0.55); resetLbl:SetText("reset")
      resetBtn:SetShown(colors[shortKey]~=nil)
      local hit=CreateFrame("Button",nil,rowF); hit:SetPoint("TOPLEFT"); hit:SetPoint("BOTTOMRIGHT",sw,"BOTTOMRIGHT",0,0); hit:SetFrameLevel(rowF:GetFrameLevel()+3)
      local capC,capSw,capKey=c,sw,shortKey
      hit:SetScript("OnEnter",function() rowHL:Show(); local cr,cg,cb=NS.ChatGetAccentRGB(); sw:SetBackdropBorderColor(cr,cg,cb,1) end)
      hit:SetScript("OnLeave",function() rowHL:Hide(); sw:SetBackdropBorderColor(0.30,0.30,0.40,1) end)
      hit:SetScript("OnClick",function()
        local old={r=capC.r,g=capC.g,b=capC.b}
        ColorPickerFrame:SetupColorPickerAndShow({r=capC.r,g=capC.g,b=capC.b,
          swatchFunc=function()
            local nr,ng,nb=ColorPickerFrame:GetColorRGB()
            capC.r,capC.g,capC.b=nr,ng,nb; capSw:SetBackdropColor(nr,ng,nb,1)
            if not LucidUIDB.chatColors then LucidUIDB.chatColors={} end
            LucidUIDB.chatColors[capKey]={r=nr,g=ng,b=nb}; resetBtn:Show()
          end,
          cancelFunc=function()
            capC.r,capC.g,capC.b=old.r,old.g,old.b; capSw:SetBackdropColor(old.r,old.g,old.b,1)
            if LucidUIDB and LucidUIDB.chatColors then LucidUIDB.chatColors[capKey]={r=old.r,g=old.g,b=old.b} end
          end,
        })
      end)
      resetBtn:SetScript("OnEnter",function() local cr,cg,cb=NS.ChatGetAccentRGB(); resetLbl:SetTextColor(cr,cg,cb) end)
      resetBtn:SetScript("OnLeave",function() resetLbl:SetTextColor(0.45,0.45,0.55) end)
      resetBtn:SetScript("OnClick",function()
        local defCi=ChatTypeInfo and ChatTypeInfo[capKey]; local dr,dg,db=1,1,1
        if defCi then dr,dg,db=defCi.r,defCi.g,defCi.b end
        if LucidUIDB and LucidUIDB.chatColors then LucidUIDB.chatColors[capKey]=nil end
        capC.r,capC.g,capC.b=dr,dg,db; capSw:SetBackdropColor(dr,dg,db,1); lbl:SetTextColor(dr,dg,db); resetBtn:Hide()
      end)
      card:Row(rowF,26)
    end

    card:Finish()
    card:SetClipsChildren(true) -- clip content during collapse animation
    fullH = card:GetHeight()
    local COLLAPSED_H = 26

    local titleHit = CreateFrame("Button", nil, card)
    titleHit:SetPoint("TOPLEFT", 0, 0); titleHit:SetPoint("TOPRIGHT", 0, 0)
    titleHit:SetHeight(COLLAPSED_H)
    titleHit:SetFrameLevel(card:GetFrameLevel() + 5)

    local arrow = card:CreateFontString(nil, "OVERLAY")
    arrow:SetFont("Fonts/FRIZQT__.TTF", 10, "OUTLINE")
    arrow:SetPoint("TOPRIGHT", card, "TOPRIGHT", -18, -7)
    local ar2, ag2, ab2 = NS.ChatGetAccentRGB()
    arrow:SetTextColor(ar2, ag2, ab2, 0.6)
    arrow:SetText("v")

    -- Reposition all cards vertically based on current heights
    local function RepositionCards()
      local y = 14
      for _, ci in ipairs(allCards) do
        ci:ClearAllPoints()
        ci:SetPoint("TOPLEFT", sc, "TOPLEFT", 12, -y)
        ci:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -12, -y)
        y = y + ci:GetHeight() + 12
      end
      sc:SetHeight(math.max(y, 300))
    end

    local function AnimateCard(toH)
      card:SetScript("OnUpdate", function(self, dt)
        local cur = self:GetHeight()
        local diff = toH - cur
        if math.abs(diff) < 1 then
          self:SetHeight(toH); self:SetScript("OnUpdate", nil)
          RepositionCards()
          return
        end
        self:SetHeight(cur + (diff > 0 and math.min(ANIM_SPD * dt, diff) or math.max(-ANIM_SPD * dt, diff)))
        RepositionCards()
      end)
    end

    titleHit:SetScript("OnClick", function()
      collapsed = not collapsed
      arrow:SetText(collapsed and ">" or "v")
      AnimateCard(collapsed and COLLAPSED_H or fullH)
    end)
    titleHit:SetScript("OnEnter", function()
      local cr3, cg3, cb3 = NS.ChatGetAccentRGB()
      arrow:SetTextColor(cr3, cg3, cb3, 1)
    end)
    titleHit:SetScript("OnLeave", function()
      local cr3, cg3, cb3 = NS.ChatGetAccentRGB()
      arrow:SetTextColor(cr3, cg3, cb3, 0.6)
    end)

    Add(card); Add(Sep(sc),7)
    table.insert(allCards, card)
  end

  return container
end


local function SetupLoot(parent)
  local container = CreateFrame("Frame",nil,parent)
  local sc,Add = MakePage(container)

  -- Card: LootTracker Mode
  local cMode = MakeCard(sc,"LootTracker Mode")
  local ownWinCB  -- forward

  local enableLoot = NS.ChatGetCheckbox(cMode.inner,"LootTracker in Chat Tab",28,function(state)
    DBSet("lootInChatTab",state)
    if state then
      DBSet("lootOwnWindow",false)
      if ownWinCB then ownWinCB:SetValue(false) end
      if NS.win then NS.win:Hide() end
      local tabD=NS.chatTabData and NS.chatTabData()
      if tabD then
        local exists=false
        for _,td in ipairs(tabD) do if td._isLootTab then exists=true; break end end
        if not exists then
          table.insert(tabD,{name="Loot",colorHex="00cc66",eventSet={},channelBlocked={General=true,Trade=true,LocalDefense=true,Services=true,LookingForGroup=true},_isLootTab=true})
          if NS.SyncLootEvents then NS.SyncLootEvents() end
          if NS.chatRebuildTabs then NS.chatRebuildTabs() end
          if NS.chatRedraw then NS.chatRedraw() end
        end
      end
    else
      local tabD=NS.chatTabData and NS.chatTabData()
      if tabD then
        for i=#tabD,1,-1 do if tabD[i]._isLootTab then table.remove(tabD,i) end end
        if NS.SyncLootEvents then NS.SyncLootEvents() end
        if NS.chatRebuildTabs then NS.chatRebuildTabs() end
        if NS.chatRedraw then NS.chatRedraw() end
      end
    end
  end,"Create a Loot tab in the chat window")
  -- Place both mode checkboxes side by side
  local modeHolder=CreateFrame("Frame",nil,cMode.inner); modeHolder:SetHeight(26)
  cMode:Row(modeHolder,26)
  modeHolder:SetPoint("LEFT",cMode.inner,"LEFT",0,0); modeHolder:SetPoint("RIGHT",cMode.inner,"RIGHT",0,0)
  local mlh=CreateFrame("Frame",nil,modeHolder); mlh:SetPoint("TOPLEFT",modeHolder,"TOPLEFT",0,0); mlh:SetPoint("BOTTOMRIGHT",modeHolder,"BOTTOM",-2,0)
  local mrh=CreateFrame("Frame",nil,modeHolder); mrh:SetPoint("TOPLEFT",modeHolder,"TOP",2,0); mrh:SetPoint("BOTTOMRIGHT",modeHolder,"BOTTOMRIGHT",0,0)
  enableLoot:SetParent(mrh); enableLoot:ClearAllPoints(); enableLoot:SetAllPoints(mrh); enableLoot.option="lootInChatTab"
  ownWinCB = NS.ChatGetCheckbox(mlh,"LootTracker in own Window",28,function(state)
    DBSet("lootOwnWindow",state)
    if state then
      DBSet("lootInChatTab",false); enableLoot:SetValue(false)
      local tabD=NS.chatTabData and NS.chatTabData()
      if tabD then
        for i=#tabD,1,-1 do if tabD[i]._isLootTab then table.remove(tabD,i) end end
        if NS.chatRebuildTabs then NS.chatRebuildTabs() end
      end
      if NS.SyncLootEvents then NS.SyncLootEvents() end
      if NS.win then NS.win:Show() end
    else
      if NS.SyncLootEvents then NS.SyncLootEvents() end
      if NS.win then NS.win:Hide() end
    end
  end,"Show loot in a standalone window")
  ownWinCB:ClearAllPoints(); ownWinCB:SetAllPoints(mlh); ownWinCB.option="lootOwnWindow"

  -- Loot window transparency slider (only visible when own window active)
  local lootTrans
  lootTrans = NS.ChatGetSlider(cMode.inner,"Loot window transparency",0,100,"%d%%",function()
    DBSet("lootWinTransparency",lootTrans:GetValue()/100); NS.ApplyAlpha()
  end)
  lootTrans.option="lootWinTransparency"; lootTrans._isPercent=true; R(cMode,lootTrans,40)
  lootTrans:SetShown(DB("lootOwnWindow") == true)

  -- Update slider visibility when own window toggled
  if ownWinCB._hit then
    ownWinCB._hit:HookScript("OnMouseDown", function()
      C_Timer.After(0, function() lootTrans:SetShown(DB("lootOwnWindow") == true) end)
    end)
  end
  if enableLoot._hit then
    enableLoot._hit:HookScript("OnMouseDown", function()
      C_Timer.After(0, function() lootTrans:SetShown(DB("lootOwnWindow") == true) end)
    end)
  end

  cMode:Finish(); Add(cMode); Add(Sep(sc),9)

  -- Card: Windows
  local cWin = MakeCard(sc,"Windows")

  -- Enable toggles side by side
  local winEnHolder=CreateFrame("Frame",nil,cWin.inner); winEnHolder:SetHeight(26)
  cWin:Row(winEnHolder,26)
  winEnHolder:SetPoint("LEFT",cWin.inner,"LEFT",0,0); winEnHolder:SetPoint("RIGHT",cWin.inner,"RIGHT",0,0)
  local welh=CreateFrame("Frame",nil,winEnHolder); welh:SetPoint("TOPLEFT",winEnHolder,"TOPLEFT",0,0); welh:SetPoint("BOTTOMRIGHT",winEnHolder,"BOTTOM",-2,0)
  local werh=CreateFrame("Frame",nil,winEnHolder); werh:SetPoint("TOPLEFT",winEnHolder,"TOP",2,0); werh:SetPoint("BOTTOMRIGHT",winEnHolder,"BOTTOMRIGHT",0,0)
  local rollsWin=NS.ChatGetCheckbox(welh,"Enable Loot Rolls",28,function(s) DBSet("showRollsBtn",s); if not s and NS.rollWin then NS.rollWin:Hide() end; if NS.LayoutBarButtons then NS.LayoutBarButtons() end end,"Show loot rolls tracking window")
  rollsWin:ClearAllPoints(); rollsWin:SetAllPoints(welh); rollsWin.option="showRollsBtn"
  local statsWin=NS.ChatGetCheckbox(werh,"Enable Session Stats",28,function(s) DBSet("showStatsBtn",s); if not s and NS.statsWin then NS.statsWin:Hide() end; if NS.LayoutBarButtons then NS.LayoutBarButtons() end end,"Show session statistics window")
  statsWin:ClearAllPoints(); statsWin:SetAllPoints(werh); statsWin.option="showStatsBtn"

  local statsTrans; statsTrans=NS.ChatGetSlider(cWin.inner,"Stats transparency",0,100,"%d%%",function() DBSet("statsTransparency",statsTrans:GetValue()/100); NS.ApplyAlpha() end)
  statsTrans.option="statsTransparency"; statsTrans._isPercent=true; R(cWin,statsTrans,40)

  local rollsTrans; rollsTrans=NS.ChatGetSlider(cWin.inner,"Rolls transparency",0,100,"%d%%",function() DBSet("rollsTransparency",rollsTrans:GetValue()/100); NS.ApplyAlpha() end)
  rollsTrans.option="rollsTransparency"; rollsTrans._isPercent=true; R(cWin,rollsTrans,40)

  -- Warning text when loottracker disabled
  local warnFS = cWin.inner:CreateFontString(nil, "OVERLAY")
  warnFS:SetFont("Fonts/FRIZQT__.TTF", 10, "")
  warnFS:SetTextColor(1, 0.82, 0, 0.9)
  warnFS:SetText("Requires LootTracker in own Window or Chat Tab")
  warnFS:Hide()
  local warnHolder = CreateFrame("Frame", nil, cWin.inner); warnHolder:SetHeight(20)
  warnFS:SetParent(warnHolder); warnFS:SetPoint("LEFT", 4, 0)
  cWin:Row(warnHolder, 20)

  -- Refresh dependent controls based on loottracker state
  local function RefreshLootDependents()
    local lootActive = DB("lootInChatTab") == true or DB("lootOwnWindow") == true
    local dimAlpha = lootActive and 1.0 or 0.35
    -- When both modes deactivated: uncheck and persist rolls+stats
    if not lootActive then
      if DB("showRollsBtn") ~= false then
        DBSet("showRollsBtn", false)
        rollsWin:SetValue(false)
        if NS.rollWin then NS.rollWin:Hide() end
        if NS.LayoutBarButtons then NS.LayoutBarButtons() end
      end
      if DB("showStatsBtn") ~= false then
        DBSet("showStatsBtn", false)
        statsWin:SetValue(false)
        if NS.statsWin then NS.statsWin:Hide() end
        if NS.LayoutBarButtons then NS.LayoutBarButtons() end
      end
    end
    -- Dim and disable rolls/stats checkboxes
    rollsWin:SetAlpha(dimAlpha)
    statsWin:SetAlpha(dimAlpha)
    statsTrans:SetAlpha(dimAlpha)
    rollsTrans:SetAlpha(dimAlpha)
    if rollsWin._hit then rollsWin._hit:EnableMouse(lootActive) end
    if statsWin._hit then statsWin._hit:EnableMouse(lootActive) end
    warnHolder:SetShown(not lootActive)
  end
  -- Hook into loottracker toggles
  if ownWinCB._hit then
    ownWinCB._hit:HookScript("OnMouseDown", function() C_Timer.After(0, RefreshLootDependents) end)
  end
  if enableLoot._hit then
    enableLoot._hit:HookScript("OnMouseDown", function() C_Timer.After(0, RefreshLootDependents) end)
  end
  RefreshLootDependents()

  cWin:Finish(); Add(cWin); Add(Sep(sc),9)

  -- Card: Rolls config
  local cRolls = MakeCard(sc,"Loot Rolls")
  local rollDelay

  local rollCloseMode = NS.ChatGetDropdown(cRolls.inner,"Roll close mode",
    function(v) return (DB("rollCloseMode") or "timer")==v end,
    function(v) DBSet("rollCloseMode",v) end)
  rollCloseMode:Init({"Auto (Timer)","Manual"},{"timer","manual"})
  R(cRolls,rollCloseMode,50)

  local rollDelay
  rollDelay = NS.ChatGetSlider(cRolls.inner,"Roll close delay",5,120,"%ss",function()
    DBSet("rollCloseDelay",rollDelay:GetValue())
  end)
  rollDelay.option="rollCloseDelay"; R(cRolls,rollDelay,40)

  cRolls:Finish(); Add(cRolls); Add(Sep(sc),9)

  -- Card: Loot settings
  local cLoot = MakeCard(sc,"Loot Settings")

  local clearDD = NS.ChatGetDropdown(cLoot.inner,"Clear loot history",
    function(v)
      if v=="reload" then return DB("clearOnReload")==true
      elseif v=="login" then return DB("clearOnLogin")==true
      else return not DB("clearOnReload") and not DB("clearOnLogin") end
    end,
    function(v) DBSet("clearOnReload",v=="reload"); DBSet("clearOnLogin",v=="login") end)
  clearDD:Init({"Never","On reload","On login"},{"never","reload","login"})
  R(cLoot,clearDD,50)

  local function LootCB2(lbl1,key1,cb1,tip1, lbl2,key2,cb2,tip2)
    local holder=CreateFrame("Frame",nil,cLoot.inner); holder:SetHeight(26)
    cLoot:Row(holder,26)
    holder:SetPoint("LEFT",cLoot.inner,"LEFT",0,0); holder:SetPoint("RIGHT",cLoot.inner,"RIGHT",0,0)
    local lh=CreateFrame("Frame",nil,holder); lh:SetPoint("TOPLEFT",holder,"TOPLEFT",0,0); lh:SetPoint("BOTTOMRIGHT",holder,"BOTTOM",-2,0)
    local rh=CreateFrame("Frame",nil,holder); rh:SetPoint("TOPLEFT",holder,"TOP",2,0); rh:SetPoint("BOTTOMRIGHT",holder,"BOTTOMRIGHT",0,0)
    local w1=NS.ChatGetCheckbox(lh,lbl1,26,cb1,tip1); w1:ClearAllPoints(); w1:SetAllPoints(lh); w1.option=key1
    local w2=NS.ChatGetCheckbox(rh,lbl2,26,cb2,tip2); w2:ClearAllPoints(); w2:SetAllPoints(rh); w2.option=key2
    return w1, w2
  end
  local showMoney,showCurrency=LootCB2(
    "Show gold / silver / copper","showMoney",function(s) DBSet("showMoney",s) end,"Display gold loot in the tracker",
    "Show currency","showCurrency",function(s) DBSet("showCurrency",s) end,"Display currency gains in the tracker")
  local showGroup,onlyOwn
  local function mkGroup()
    local h=CreateFrame("Frame",nil,cLoot.inner); h:SetHeight(26)
    cLoot:Row(h,26)
    h:SetPoint("LEFT",cLoot.inner,"LEFT",0,0); h:SetPoint("RIGHT",cLoot.inner,"RIGHT",0,0)
    local lh=CreateFrame("Frame",nil,h); lh:SetPoint("TOPLEFT",h,"TOPLEFT",0,0); lh:SetPoint("BOTTOMRIGHT",h,"BOTTOM",-2,0)
    local rh=CreateFrame("Frame",nil,h); rh:SetPoint("TOPLEFT",h,"TOP",2,0); rh:SetPoint("BOTTOMRIGHT",h,"BOTTOMRIGHT",0,0)
    showGroup=NS.ChatGetCheckbox(lh,"Show group loot",28,function(s) DBSet("showGroupLoot",s); if s then DBSet("showOnlyOwnLoot",false); if onlyOwn then onlyOwn:SetValue(false) end end end,"Show items looted by group members")
    showGroup:ClearAllPoints(); showGroup:SetAllPoints(lh); showGroup.option="showGroupLoot"
    onlyOwn=NS.ChatGetCheckbox(rh,"Only my own loot",28,function(s) DBSet("showOnlyOwnLoot",s); if s then DBSet("showGroupLoot",false); if showGroup then showGroup:SetValue(false) end end end,"Only show items you personally looted")
    onlyOwn:ClearAllPoints(); onlyOwn:SetAllPoints(rh); onlyOwn.option="showOnlyOwnLoot"
  end
  mkGroup()
  local showRealm,zoneReset=LootCB2(
    "Show realm name","showRealmName",function(s) DBSet("showRealmName",s) end,"Show server name next to player names",
    "Reset stats on zone","statsResetOnZone",function(s) DBSet("statsResetOnZone",s) end,"Auto-reset session stats when changing zones")

  -- Quality buttons (full width, dynamically sized)
  local qualRow = CreateFrame("Frame",nil,cLoot.inner); qualRow:SetHeight(32)
  local qualNames={"All","Common+","Uncommon+","Rare+","Epic+","Legendary+"}
  local qualColors={{1,1,1},{0.62,0.62,0.62},{0.12,1,0},{0,0.44,0.87},{0.64,0.21,0.93},{1,0.5,0}}
  local qualBtns={}
  local NUM_QUAL = 6
  local QUAL_GAP = 3
  local function RefreshQual()
    local cur=DB("minQuality") or 0
    for _,qb in ipairs(qualBtns) do
      local a=cur==qb.q; local c=qualColors[qb.q+1]
      qb.btn:SetBackdropBorderColor(a and c[1] or 0.18,a and c[2] or 0.18,a and c[3] or 0.18,1)
    end
  end
  for qi=0,5 do
    local qc=qualColors[qi+1]
    local qb=CreateFrame("Button",nil,qualRow,"BackdropTemplate")
    qb:SetHeight(24)
    qb:SetBackdrop(BD); qb:SetBackdropColor(0.05,0.05,0.08,1); qb:SetBackdropBorderColor(0.18,0.18,0.18,1)
    local ql=qb:CreateFontString(nil,"OVERLAY"); ql:SetFont("Fonts/FRIZQT__.TTF",10,""); ql:SetPoint("CENTER"); ql:SetTextColor(qc[1],qc[2],qc[3],1); ql:SetText(qualNames[qi+1])
    local cQ=qi
    qb:SetScript("OnEnter",function() qb:SetBackdropBorderColor(qc[1],qc[2],qc[3],1) end)
    qb:SetScript("OnLeave",function() RefreshQual() end)
    qb:SetScript("OnClick",function() DBSet("minQuality",cQ); RefreshQual() end)
    table.insert(qualBtns,{btn=qb,q=cQ})
  end
  -- Position buttons to fill the row width dynamically
  qualRow:SetScript("OnShow", function(self)
    local totalW = self:GetWidth()
    local bw2 = math.floor((totalW - (NUM_QUAL - 1) * QUAL_GAP) / NUM_QUAL)
    for i, qbi in ipairs(qualBtns) do
      qbi.btn:ClearAllPoints()
      qbi.btn:SetWidth(bw2)
      qbi.btn:SetPoint("TOPLEFT", qualRow, "TOPLEFT", (i - 1) * (bw2 + QUAL_GAP), 0)
    end
    RefreshQual()
  end)
  -- Also position on size change
  qualRow:SetScript("OnSizeChanged", function(self)
    local totalW = self:GetWidth()
    if totalW < 10 then return end
    local bw2 = math.floor((totalW - (NUM_QUAL - 1) * QUAL_GAP) / NUM_QUAL)
    for i, qbi in ipairs(qualBtns) do
      qbi.btn:ClearAllPoints()
      qbi.btn:SetWidth(bw2)
      qbi.btn:SetPoint("TOPLEFT", qualRow, "TOPLEFT", (i - 1) * (bw2 + QUAL_GAP), 0)
    end
  end)
  cLoot:Row(qualRow,32)
  cLoot:Finish(); Add(cLoot)

  container:SetScript("OnShow",function()
    enableLoot:SetValue(DB("lootInChatTab")==true)
    ownWinCB:SetValue(DB("lootOwnWindow")==true)
    lootTrans:SetShown(DB("lootOwnWindow")==true)
    if DB("lootOwnWindow") then lootTrans:SetValue((DB("lootWinTransparency") or 0.2)*100) end
    statsWin:SetValue(DB("showStatsBtn")~=false)
    rollsWin:SetValue(DB("showRollsBtn")~=false)
    statsTrans:SetValue((DB("statsTransparency") or 0.03)*100)
    rollsTrans:SetValue((DB("rollsTransparency") or 0.03)*100)
    rollCloseMode:SetValue(); rollDelay:SetValue(DB("rollCloseDelay") or 60)
    clearDD:SetValue()
    for _,w in ipairs({showMoney,showCurrency,showGroup,onlyOwn,showRealm,zoneReset}) do
      if w.option then w:SetValue(DB(w.option)) end
    end
    RefreshQual()
    RefreshLootDependents()
  end)

  return container
end

-- ═══════════════════════════════════════════════════════════════════════
--  TAB 7: QoL
-- ═══════════════════════════════════════════════════════════════════════
local function SetupQoL(parent)
  local container = CreateFrame("Frame",nil,parent)
  local sc,Add = MakePage(container)

  -- FPS CVars list (unchanged logic)
  local OPTIMAL_FPS_CVARS = {
    {cvar="renderScale",optimal="1"},{cvar="VSync",optimal="0"},{cvar="MSAAQuality",optimal="0"},
    {cvar="LowLatencyMode",optimal="3"},{cvar="ffxAntiAliasingMode",optimal="4"},
    {cvar="graphicsShadowQuality",optimal="1"},{cvar="graphicsLiquidDetail",optimal="2"},
    {cvar="graphicsParticleDensity",optimal="3"},{cvar="graphicsSSAO",optimal="0"},
    {cvar="graphicsDepthEffects",optimal="0"},{cvar="graphicsComputeEffects",optimal="0"},
    {cvar="graphicsOutlineMode",optimal="2"},{cvar="graphicsTextureResolution",optimal="2"},
    {cvar="graphicsSpellDensity",optimal="0"},{cvar="graphicsProjectedTextures",optimal="1"},
    {cvar="graphicsViewDistance",optimal="3"},{cvar="graphicsEnvironmentDetail",optimal="3"},
    {cvar="graphicsGroundClutter",optimal="0"},{cvar="GxMaxFrameLatency",optimal="2"},
    {cvar="TextureFilteringMode",optimal="5"},{cvar="shadowRt",optimal="0"},
    {cvar="ResampleQuality",optimal="3"},{cvar="GxApi",optimal="D3D12"},
    {cvar="physicsLevel",optimal="1"},{cvar="useTargetFPS",optimal="0"},
    {cvar="useMaxFPSBk",optimal="1"},{cvar="maxFPSBk",optimal="30"},
    {cvar="ResampleSharpness",optimal="0"},
  }

  local function SBtn(par,txt,w)
    local btn=CreateFrame("Button",nil,par,"BackdropTemplate")
    btn:SetSize(w,22); btn:SetBackdrop(BD)
    btn:SetBackdropColor(0.05,0.05,0.09,1); btn:SetBackdropBorderColor(0.14,0.14,0.22,1)
    -- corner cut
    local cut=btn:CreateTexture(nil,"OVERLAY",nil,4); cut:SetSize(8,1)
    cut:SetPoint("TOPRIGHT",btn,"TOPRIGHT",0,-1); cut:SetColorTexture(0,1,1,0.30)
    local fs=btn:CreateFontString(nil,"OVERLAY"); fs:SetFont("Fonts/FRIZQT__.TTF",10,"")
    fs:SetPoint("CENTER",0,0); fs:SetTextColor(0.75,0.75,0.85); fs:SetText(txt)
    btn:SetScript("OnEnter",function() local cr,cg,cb=NS.ChatGetAccentRGB(); btn:SetBackdropBorderColor(cr,cg,cb,0.8) end)
    btn:SetScript("OnLeave",function() btn:SetBackdropBorderColor(0.14,0.14,0.22,1) end)
    return btn
  end

  -- ── Card: System Optimization ──────────────────────────────────────
  local cSys = MakeCard(sc,"System Optimization")
  local sysRow = CreateFrame("Frame",nil,cSys.inner); sysRow:SetHeight(26)
  local fpsBtn = SBtn(sysRow,"Optimal FPS Settings",160)
  fpsBtn:SetPoint("LEFT",sysRow,"LEFT",0,0)
  local restoreBtn = SBtn(sysRow,"Restore",80)
  restoreBtn:SetPoint("LEFT",fpsBtn,"RIGHT",6,0)
  local fpsFS=sysRow:CreateFontString(nil,"OVERLAY"); fpsFS:SetFont("Fonts/FRIZQT__.TTF",10,"")
  fpsFS:SetPoint("LEFT",restoreBtn,"RIGHT",10,0); fpsFS:SetTextColor(0.45,0.45,0.55)
  local mismatch={}
  local function UpdateFPSStatus()
    local m,t=0,#OPTIMAL_FPS_CVARS; wipe(mismatch)
    for _,s in ipairs(OPTIMAL_FPS_CVARS) do
      local ok,cur=pcall(C_CVar.GetCVar,s.cvar)
      if ok and tostring(cur)==s.optimal then m=m+1 else mismatch[#mismatch+1]={cvar=s.cvar,cur=ok and tostring(cur) or "?",opt=s.optimal} end
    end
    if m==t then fpsFS:SetTextColor(0,0.75,0); fpsFS:SetText("Applied")
    else fpsFS:SetTextColor(0.45,0.45,0.55); fpsFS:SetText(m.."/"..t) end
    restoreBtn:SetShown(LucidUIDB and LucidUIDB._savedCVars~=nil)
  end
  StaticPopupDialogs["LUCIDUI_FPS_RELOAD"]={text="Optimal FPS settings applied. Reload UI?",button1=ACCEPT,button2=CANCEL,OnAccept=function() ReloadUI() end,timeout=0,whileDead=true,hideOnEscape=true,preferredIndex=3}
  fpsBtn:SetScript("OnClick",function()
    LucidUIDB._savedCVars={}
    for _,s in ipairs(OPTIMAL_FPS_CVARS) do local ok,cur=pcall(C_CVar.GetCVar,s.cvar); if ok and cur then LucidUIDB._savedCVars[s.cvar]=tostring(cur) end end
    for _,s in ipairs(OPTIMAL_FPS_CVARS) do pcall(C_CVar.SetCVar,s.cvar,s.optimal) end
    UpdateFPSStatus(); StaticPopup_Show("LUCIDUI_FPS_RELOAD")
  end)
  restoreBtn:SetScript("OnClick",function()
    if LucidUIDB and LucidUIDB._savedCVars then
      for cvar,val in pairs(LucidUIDB._savedCVars) do pcall(C_CVar.SetCVar,cvar,val) end
      LucidUIDB._savedCVars=nil; UpdateFPSStatus(); StaticPopup_Show("LUCIDUI_FPS_RELOAD")
    end
  end)
  cSys:Row(sysRow,26); cSys:Finish(); Add(cSys); Add(Sep(sc),9)

  local function CB(card,lbl,key,cb,tip)
    local w=NS.ChatGetCheckbox(card.inner,lbl,26,cb,tip); w.option=key; R(card,w,26); return w
  end
  local function SL(card,lbl,mn,mx,pat,cb)
    local s; s=NS.ChatGetSlider(card.inner,lbl,mn,mx,pat,function() if cb then cb(s:GetValue()) end end)
    R(card,s,40); return s
  end

  -- ── Card: Mouse Ring ───────────────────────────────────────────────
  -- ── Inline text-input row helper ─────────────────────────────────────────
  local BD2 = {bgFile="Interface/Buttons/WHITE8X8",edgeFile="Interface/Buttons/WHITE8X8",edgeSize=1}
  local function MakeTextRow(card, labelTxt, dbKey, defaultTxt)
    local holder = CreateFrame("Frame", nil, card.inner); holder:SetHeight(40)
    local lbl = holder:CreateFontString(nil,"OVERLAY"); lbl:SetFont("Fonts/FRIZQT__.TTF",10,"")
    lbl:SetPoint("TOPLEFT",0,-2); lbl:SetTextColor(0.55,0.55,0.65); lbl:SetText(labelTxt)
    local eb = CreateFrame("EditBox",nil,holder,"BackdropTemplate")
    eb:SetHeight(22); eb:SetPoint("BOTTOMLEFT",0,0); eb:SetPoint("BOTTOMRIGHT",0,0)
    eb:SetBackdrop(BD2); eb:SetBackdropColor(0.06,0.06,0.10,1); eb:SetBackdropBorderColor(0.18,0.18,0.26,1)
    eb:SetAutoFocus(false); eb:SetFontObject(GameFontHighlight); eb:SetTextInsets(6,6,0,0)
    eb:SetText(DB(dbKey) or defaultTxt or "")
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus(); DBSet(dbKey, self:GetText()) end)
    eb:SetScript("OnEditFocusLost", function(self) DBSet(dbKey, self:GetText()) end)
    eb:SetScript("OnEnter", function() local ar,ag,ab=NS.ChatGetAccentRGB(); eb:SetBackdropBorderColor(ar,ag,ab,0.7) end)
    eb:SetScript("OnLeave", function() eb:SetBackdropBorderColor(0.18,0.18,0.26,1) end)
    holder._eb = eb
    card:Row(holder, 40)
    return holder
  end

  -- ── Unlock/Lock position button helper ───────────────────────────────────
  local function MakeUnlockRow(card, onUnlock, onLock)
    local row = CreateFrame("Frame",nil,card.inner); row:SetHeight(28)
    local btn = SBtn(row,"Unlock Position",130)
    btn:SetPoint("LEFT",row,"LEFT",0,0)
    local locked = true
    btn:SetScript("OnClick",function()
      locked = not locked
      local fs = btn:GetFontString()
      if fs then fs:SetText(locked and "Unlock Position" or "Lock Position") end
      if locked then
        btn:SetBackdropBorderColor(0.14,0.14,0.22,1)
        if onLock then onLock() end
      else
        local ar,ag,ab = NS.ChatGetAccentRGB()
        btn:SetBackdropBorderColor(ar,ag,ab,0.9)
        if onUnlock then onUnlock() end
      end
    end)
    card:Row(row,28)
    return btn
  end

  -- Shared pair helper for QoL cards
  local function QCB2(card, arr, lbl1, key1, cb1, tip1, lbl2, key2, cb2, tip2)
    local h=CreateFrame("Frame",nil,card.inner); h:SetHeight(26)
    card:Row(h,26)
    h:SetPoint("LEFT",card.inner,"LEFT",0,0); h:SetPoint("RIGHT",card.inner,"RIGHT",0,0)
    local lh=CreateFrame("Frame",nil,h); lh:SetPoint("TOPLEFT",h,"TOPLEFT",0,0); lh:SetPoint("BOTTOMRIGHT",h,"BOTTOM",-2,0)
    local rh=CreateFrame("Frame",nil,h); rh:SetPoint("TOPLEFT",h,"TOP",2,0); rh:SetPoint("BOTTOMRIGHT",h,"BOTTOMRIGHT",0,0)
    local w1=NS.ChatGetCheckbox(lh,lbl1,26,cb1,tip1); w1:ClearAllPoints(); w1:SetAllPoints(lh); w1.option=key1
    local w2=NS.ChatGetCheckbox(rh,lbl2,26,cb2,tip2); w2:ClearAllPoints(); w2:SetAllPoints(rh); w2.option=key2
    table.insert(arr,w1); table.insert(arr,w2)
    return w1, w2
  end

  -- ── Card: Mouse Ring ──────────────────────────────────────────────────────
  local cRing=MakeCard(sc,"Mouse Ring"); local ringFrames={}; local ringColorRow; local ringShapeDD
  QCB2(cRing,ringFrames,"Enable Mouse Ring","qolMouseRing",function(s) DBSet("qolMouseRing",s); if s then if NS.QoL.EnableMouseRing then NS.QoL.EnableMouseRing() end else if NS.QoL.DisableMouseRing then NS.QoL.DisableMouseRing() end end end,nil,
       "Hide on right click","qolMouseRingHideRMB",function(s) DBSet("qolMouseRingHideRMB",s) end,nil)
  local ringOOC=CB(cRing,"Show out of combat","qolMouseRingShowOOC",function(s) DBSet("qolMouseRingShowOOC",s) end); table.insert(ringFrames,ringOOC)
  local ringSz=SL(cRing,"Size",24,128,"%spx",function(v) DBSet("qolMouseRingSize",v); if NS.QoL.RefreshMouseRing then NS.QoL.RefreshMouseRing() end end); ringSz.option="qolMouseRingSize"
  local ringOp=SL(cRing,"Opacity",0,100,"%d%%",function(v) DBSet("qolMouseRingOpacity",v/100); if NS.QoL.RefreshMouseRing then NS.QoL.RefreshMouseRing() end end); ringOp.option="qolMouseRingOpacity"; ringOp._isPercent=true
  -- Shape dropdown
  ringShapeDD=NS.ChatGetDropdown(cRing.inner,"Shape",
    function(v) return (DB("qolMouseRingShape") or "ring.tga")==v end,
    function(v) DBSet("qolMouseRingShape",v); if NS.QoL.RefreshMouseRing then NS.QoL.RefreshMouseRing() end end)
  ringShapeDD:Init({"Ring","Thin Ring","Thick Ring","Soft Ring","Glow","Circle"},{"ring.tga","thin_ring.tga","thick_ring.tga","ring_soft1.tga","glow.tga","circle.tga"})
  R(cRing,ringShapeDD,50); ringShapeDD.option="qolMouseRingShape"
  -- Ring color
  ringColorRow=NS.ChatGetColorRow(cRing.inner,"Ring Color",
    DB("qolRingColorR") or 0, DB("qolRingColorG") or 0.8, DB("qolRingColorB") or 0.8,
    "Tint color of the ring",
    function(r,g,b)
      DBSet("qolRingColorR",r); DBSet("qolRingColorG",g); DBSet("qolRingColorB",b)
      if NS.QoL.RefreshMouseRing then NS.QoL.RefreshMouseRing() end
    end)
  R(cRing,ringColorRow,26)
  for _,w in ipairs({ringEn,ringHide,ringOOC,ringSz,ringOp}) do table.insert(ringFrames,w) end
  cRing:Finish(); Add(cRing); Add(Sep(sc),9)

  -- ── Card: Combat Timer ───────────────────────────────────────────────────
  local cTimer=MakeCard(sc,"Combat Timer"); local timerFrames={}; local timerColorRow
  QCB2(cTimer,timerFrames,"Enable Combat Timer","qolCombatTimer",function(s) DBSet("qolCombatTimer",s) end,nil,
       "Instance only","qolCombatTimerInstance",function(s) DBSet("qolCombatTimerInstance",s) end,nil)
  QCB2(cTimer,timerFrames,"Hide prefix text","qolCombatTimerHidePrefix",function(s) DBSet("qolCombatTimerHidePrefix",s); if NS.QoL.CombatTimer and NS.QoL.CombatTimer.RefreshSettings then NS.QoL.CombatTimer.RefreshSettings() end end,nil,
       "Show background","qolCombatTimerShowBg",function(s) DBSet("qolCombatTimerShowBg",s); if NS.QoL.CombatTimer and NS.QoL.CombatTimer.RefreshSettings then NS.QoL.CombatTimer.RefreshSettings() end end,nil)
  local tSz=SL(cTimer,"Font size",8,64,"%spx",function(v)
    DBSet("qolTimerFontSize",v)
    if NS.QoL.CombatTimer and NS.QoL.CombatTimer.RefreshSettings then NS.QoL.CombatTimer.RefreshSettings() end
  end); tSz.option="qolTimerFontSize"
  -- Timer color label + swatch (inline next to label) + Unlock button — all one row
  do
    local BD_tc = {bgFile="Interface/Buttons/WHITE8X8",edgeFile="Interface/Buttons/WHITE8X8",edgeSize=1}
    local tcRow = CreateFrame("Frame",nil,cTimer.inner); tcRow:SetHeight(26)
    cTimer:Row(tcRow,26)
    tcRow:SetPoint("LEFT",cTimer.inner,"LEFT",0,0); tcRow:SetPoint("RIGHT",cTimer.inner,"RIGHT",0,0)

    -- Unlock button anchored to RIGHT
    local UNLOCK_W = 130
    local timerUnlockBtn = SBtn(tcRow,"Unlock Position",UNLOCK_W)
    timerUnlockBtn:SetPoint("RIGHT",tcRow,"RIGHT",0,0)
    timerUnlockBtn:SetHeight(22)
    local timerLocked = true
    timerUnlockBtn:SetScript("OnClick",function()
      timerLocked = not timerLocked
      local fs = timerUnlockBtn:GetFontString()
      if fs then fs:SetText(timerLocked and "Unlock Position" or "Lock Position") end
      if timerLocked then
        timerUnlockBtn:SetBackdropBorderColor(0.14,0.14,0.22,1)
        if NS.QoL.CombatTimer then NS.QoL.CombatTimer.SetUnlocked(false) end
      else
        local ar,ag,ab = NS.ChatGetAccentRGB(); timerUnlockBtn:SetBackdropBorderColor(ar,ag,ab,0.9)
        if NS.QoL.CombatTimer then NS.QoL.CombatTimer.SetUnlocked(true) end
      end
    end)

    -- "Timer Color" label
    local tcLbl = tcRow:CreateFontString(nil,"OVERLAY")
    tcLbl:SetFont("Fonts/FRIZQT__.TTF",11,"")
    tcLbl:SetPoint("LEFT",tcRow,"LEFT",20,0)
    tcLbl:SetTextColor(1,1,1,1)
    tcLbl:SetText("Timer Color")

    -- Swatch immediately right of the label (~6px gap)
    local tcSwatch = CreateFrame("Frame",nil,tcRow,"BackdropTemplate")
    tcSwatch:SetSize(16,16)
    tcSwatch:SetPoint("LEFT",tcLbl,"RIGHT",8,0)
    tcSwatch:SetBackdrop(BD_tc)
    local tcR = DB("qolTimerColorR") or 1
    local tcG = DB("qolTimerColorG") or 1
    local tcB = DB("qolTimerColorB") or 1
    tcSwatch:SetBackdropColor(tcR,tcG,tcB,1)
    tcSwatch:SetBackdropBorderColor(0.28,0.28,0.38,1)

    local tcHit = CreateFrame("Button",nil,tcRow)
    tcHit:SetSize(16,16); tcHit:SetPoint("LEFT",tcLbl,"RIGHT",8,0)
    tcHit:SetFrameLevel(tcRow:GetFrameLevel()+4)
    tcHit:SetScript("OnEnter",function() local ar,ag,ab=NS.ChatGetAccentRGB(); tcSwatch:SetBackdropBorderColor(ar,ag,ab,1) end)
    tcHit:SetScript("OnLeave",function() tcSwatch:SetBackdropBorderColor(0.28,0.28,0.38,1) end)
    tcHit:SetScript("OnClick",function()
      local cr,cg,cb = tcSwatch:GetBackdropColor()
      ColorPickerFrame:SetupColorPickerAndShow({r=cr,g=cg,b=cb,
        swatchFunc=function()
          local r,g,b = ColorPickerFrame:GetColorRGB()
          DBSet("qolTimerColorR",r); DBSet("qolTimerColorG",g); DBSet("qolTimerColorB",b)
          tcSwatch:SetBackdropColor(r,g,b,1)
          if NS.QoL.CombatTimer and NS.QoL.CombatTimer.RefreshSettings then NS.QoL.CombatTimer.RefreshSettings() end
        end,
        cancelFunc=function() tcSwatch:SetBackdropColor(cr,cg,cb,1) end,
      })
    end)

    -- Expose SetColor for OnShow refresh
    timerColorRow = {_swatch=tcSwatch, SetColor=function(_,r,g,b) tcSwatch:SetBackdropColor(r,g,b,1) end}
  end
  for _,w in ipairs({tEn,tInst,tHide,tShowBg,tSz}) do table.insert(timerFrames,w) end
  cTimer:Finish(); Add(cTimer); Add(Sep(sc),9)

  -- ── Card: Combat Alert ───────────────────────────────────────────────────
  local cAlert=MakeCard(sc,"Combat Alert"); local alertFrames={}
  local alertEnterColorRow, alertLeaveColorRow, enterTextRow, leaveTextRow
  -- Enable CB (left) + Unlock button (right) in one row
  local aEn, aSz
  do
    local alertEnRow = CreateFrame("Frame",nil,cAlert.inner); alertEnRow:SetHeight(26)
    cAlert:Row(alertEnRow,26)
    alertEnRow:SetPoint("LEFT",cAlert.inner,"LEFT",0,0); alertEnRow:SetPoint("RIGHT",cAlert.inner,"RIGHT",0,0)
    -- Unlock button anchored RIGHT
    local ALERT_UNLOCK_W = 130
    local alertUnlockBtn = SBtn(alertEnRow,"Unlock Position",ALERT_UNLOCK_W)
    alertUnlockBtn:SetPoint("RIGHT",alertEnRow,"RIGHT",0,0); alertUnlockBtn:SetHeight(22)
    local alertLocked = true
    alertUnlockBtn:SetScript("OnClick",function()
      alertLocked = not alertLocked
      local fs = alertUnlockBtn:GetFontString()
      if fs then fs:SetText(alertLocked and "Unlock Position" or "Lock Position") end
      if alertLocked then
        alertUnlockBtn:SetBackdropBorderColor(0.14,0.14,0.22,1)
        if NS.QoL.CombatAlert then NS.QoL.CombatAlert.SetUnlocked(false) end
      else
        local ar,ag,ab = NS.ChatGetAccentRGB(); alertUnlockBtn:SetBackdropBorderColor(ar,ag,ab,0.9)
        if NS.QoL.CombatAlert then NS.QoL.CombatAlert.SetUnlocked(true) end
      end
    end)
    -- Enable checkbox fills left portion up to the button
    local cbHolder = CreateFrame("Frame",nil,alertEnRow)
    cbHolder:SetPoint("TOPLEFT",alertEnRow,"TOPLEFT",0,0)
    cbHolder:SetPoint("BOTTOMRIGHT",alertUnlockBtn,"BOTTOMLEFT",-6,0)
    aEn = NS.ChatGetCheckbox(cbHolder,"Enable Combat Alert",26,function(s) DBSet("qolCombatAlert",s) end)
    aEn:ClearAllPoints(); aEn:SetAllPoints(cbHolder); aEn.option="qolCombatAlert"
  end
  aSz=SL(cAlert,"Font size",8,64,"%spx",function(v)
    DBSet("qolAlertFontSize",v)
    if NS.QoL.CombatAlert and NS.QoL.CombatAlert.RefreshSettings then NS.QoL.CombatAlert.RefreshSettings() end
  end); aSz.option="qolAlertFontSize"
  -- Enter + Leave side by side: [color swatch][textbox] | [color swatch][textbox]
  local BD2a = {bgFile="Interface/Buttons/WHITE8X8",edgeFile="Interface/Buttons/WHITE8X8",edgeSize=1}
  local alertPairRow = CreateFrame("Frame",nil,cAlert.inner); alertPairRow:SetHeight(28)
  cAlert:Row(alertPairRow,28)
  alertPairRow:SetPoint("LEFT",cAlert.inner,"LEFT",0,0); alertPairRow:SetPoint("RIGHT",cAlert.inner,"RIGHT",0,0)

  -- Left half: Enter
  local aLH = CreateFrame("Frame",nil,alertPairRow)
  aLH:SetPoint("TOPLEFT",alertPairRow,"TOPLEFT",0,0); aLH:SetPoint("BOTTOMRIGHT",alertPairRow,"BOTTOM",-4,0)
  -- Right half: Leave
  local aRH = CreateFrame("Frame",nil,alertPairRow)
  aRH:SetPoint("TOPLEFT",alertPairRow,"TOP",4,0); aRH:SetPoint("BOTTOMRIGHT",alertPairRow,"BOTTOMRIGHT",0,0)

  local SW = 16  -- swatch size
  -- Enter swatch
  local enterSwatch = CreateFrame("Frame",nil,aLH,"BackdropTemplate")
  enterSwatch:SetSize(SW,SW); enterSwatch:SetPoint("LEFT",aLH,"LEFT",0,0)
  enterSwatch:SetBackdrop(BD2a)
  local er0,eg0,eb0 = DB("qolAlertEnterR") or 1, DB("qolAlertEnterG") or 0.2, DB("qolAlertEnterB") or 0.2
  enterSwatch:SetBackdropColor(er0,eg0,eb0,1); enterSwatch:SetBackdropBorderColor(0.28,0.28,0.38,1)
  local enterSwatchHit = CreateFrame("Button",nil,aLH); enterSwatchHit:SetSize(SW,SW); enterSwatchHit:SetPoint("LEFT",aLH,"LEFT",0,0)
  enterSwatchHit:SetScript("OnEnter",function() local ar,ag,ab=NS.ChatGetAccentRGB(); enterSwatch:SetBackdropBorderColor(ar,ag,ab,1) end)
  enterSwatchHit:SetScript("OnLeave",function() enterSwatch:SetBackdropBorderColor(0.28,0.28,0.38,1) end)
  enterSwatchHit:SetScript("OnClick",function()
    local cr,cg,cb=enterSwatch:GetBackdropColor()
    ColorPickerFrame:SetupColorPickerAndShow({r=cr,g=cg,b=cb,
      swatchFunc=function() local r,g,b=ColorPickerFrame:GetColorRGB(); DBSet("qolAlertEnterR",r);DBSet("qolAlertEnterG",g);DBSet("qolAlertEnterB",b); enterSwatch:SetBackdropColor(r,g,b,1) end,
      cancelFunc=function() enterSwatch:SetBackdropColor(cr,cg,cb,1) end,
    })
  end)
  -- Enter editbox
  local enterEB = CreateFrame("EditBox",nil,aLH,"BackdropTemplate")
  enterEB:SetHeight(22); enterEB:SetPoint("LEFT",enterSwatch,"RIGHT",4,0); enterEB:SetPoint("RIGHT",aLH,"RIGHT",0,0)
  enterEB:SetBackdrop(BD2a); enterEB:SetBackdropColor(0.06,0.06,0.10,1); enterEB:SetBackdropBorderColor(0.18,0.18,0.26,1)
  enterEB:SetAutoFocus(false); enterEB:SetFontObject(GameFontHighlight); enterEB:SetTextInsets(6,6,0,0)
  enterEB:SetText(DB("qolCombatEnterText") or "++ COMBAT ++")
  enterEB:SetScript("OnEnterPressed",function(self) self:ClearFocus(); DBSet("qolCombatEnterText",self:GetText()) end)
  enterEB:SetScript("OnEditFocusLost",function(self) DBSet("qolCombatEnterText",self:GetText()) end)
  enterEB:SetScript("OnEnter",function() local ar,ag,ab=NS.ChatGetAccentRGB(); enterEB:SetBackdropBorderColor(ar,ag,ab,0.7) end)
  enterEB:SetScript("OnLeave",function() enterEB:SetBackdropBorderColor(0.18,0.18,0.26,1) end)
  -- Store refs so OnShow can update
  alertEnterColorRow = {_swatch=enterSwatch, SetColor=function(_,r,g,b) enterSwatch:SetBackdropColor(r,g,b,1) end}
  enterTextRow = {_eb=enterEB}

  -- Leave swatch
  local leaveSwatch = CreateFrame("Frame",nil,aRH,"BackdropTemplate")
  leaveSwatch:SetSize(SW,SW); leaveSwatch:SetPoint("LEFT",aRH,"LEFT",0,0)
  leaveSwatch:SetBackdrop(BD2a)
  local lr0,lg0,lb0 = DB("qolAlertLeaveR") or 0.2, DB("qolAlertLeaveG") or 1, DB("qolAlertLeaveB") or 0.2
  leaveSwatch:SetBackdropColor(lr0,lg0,lb0,1); leaveSwatch:SetBackdropBorderColor(0.28,0.28,0.38,1)
  local leaveSwatchHit = CreateFrame("Button",nil,aRH); leaveSwatchHit:SetSize(SW,SW); leaveSwatchHit:SetPoint("LEFT",aRH,"LEFT",0,0)
  leaveSwatchHit:SetScript("OnEnter",function() local ar,ag,ab=NS.ChatGetAccentRGB(); leaveSwatch:SetBackdropBorderColor(ar,ag,ab,1) end)
  leaveSwatchHit:SetScript("OnLeave",function() leaveSwatch:SetBackdropBorderColor(0.28,0.28,0.38,1) end)
  leaveSwatchHit:SetScript("OnClick",function()
    local cr,cg,cb=leaveSwatch:GetBackdropColor()
    ColorPickerFrame:SetupColorPickerAndShow({r=cr,g=cg,b=cb,
      swatchFunc=function() local r,g,b=ColorPickerFrame:GetColorRGB(); DBSet("qolAlertLeaveR",r);DBSet("qolAlertLeaveG",g);DBSet("qolAlertLeaveB",b); leaveSwatch:SetBackdropColor(r,g,b,1) end,
      cancelFunc=function() leaveSwatch:SetBackdropColor(cr,cg,cb,1) end,
    })
  end)
  -- Leave editbox
  local leaveEB = CreateFrame("EditBox",nil,aRH,"BackdropTemplate")
  leaveEB:SetHeight(22); leaveEB:SetPoint("LEFT",leaveSwatch,"RIGHT",4,0); leaveEB:SetPoint("RIGHT",aRH,"RIGHT",0,0)
  leaveEB:SetBackdrop(BD2a); leaveEB:SetBackdropColor(0.06,0.06,0.10,1); leaveEB:SetBackdropBorderColor(0.18,0.18,0.26,1)
  leaveEB:SetAutoFocus(false); leaveEB:SetFontObject(GameFontHighlight); leaveEB:SetTextInsets(6,6,0,0)
  leaveEB:SetText(DB("qolCombatLeaveText") or "-- COMBAT --")
  leaveEB:SetScript("OnEnterPressed",function(self) self:ClearFocus(); DBSet("qolCombatLeaveText",self:GetText()) end)
  leaveEB:SetScript("OnEditFocusLost",function(self) DBSet("qolCombatLeaveText",self:GetText()) end)
  leaveEB:SetScript("OnEnter",function() local ar,ag,ab=NS.ChatGetAccentRGB(); leaveEB:SetBackdropBorderColor(ar,ag,ab,0.7) end)
  leaveEB:SetScript("OnLeave",function() leaveEB:SetBackdropBorderColor(0.18,0.18,0.26,1) end)
  alertLeaveColorRow = {_swatch=leaveSwatch, SetColor=function(_,r,g,b) leaveSwatch:SetBackdropColor(r,g,b,1) end}
  leaveTextRow = {_eb=leaveEB}

  for _,w in ipairs({aEn,aSz}) do table.insert(alertFrames,w) end
  cAlert:Finish(); Add(cAlert); Add(Sep(sc),9)

  -- ── Card: Misc QoL ───────────────────────────────────────────────────────
  local cMisc=MakeCard(sc,"Misc"); local miscFrames={}; local repairModeDD
  QCB2(cMisc,miscFrames,"Faster Loot","qolFasterLoot",function(s) DBSet("qolFasterLoot",s) end,nil,"Auto Sell Grey","qolAutoSellGrey",function(s) DBSet("qolAutoSellGrey",s) end,nil)
  QCB2(cMisc,miscFrames,"Auto Repair","qolAutoRepair",function(s) DBSet("qolAutoRepair",s) end,nil,"Skip Cinematics","qolSkipCinematics",function(s) DBSet("qolSkipCinematics",s) end,nil)
  QCB2(cMisc,miscFrames,"Easy Destroy","qolEasyDestroy",function(s) DBSet("qolEasyDestroy",s) end,nil,"Auto Keystone","qolAutoKeystone",function(s) DBSet("qolAutoKeystone",s) end,nil)
  local wSuppWarn=CB(cMisc,"Suppress Warnings","qolSuppressWarnings",function(s) DBSet("qolSuppressWarnings",s) end); table.insert(miscFrames,wSuppWarn)
  -- Auto repair mode: guild bank vs own gold
  repairModeDD=NS.ChatGetDropdown(cMisc.inner,"Repair with",
    function(v) return (DB("qolAutoRepairMode") or "guild")==v end,
    function(v) DBSet("qolAutoRepairMode",v) end)
  repairModeDD:Init({"Guild Bank","Own Gold"},{"guild","gold"})
  R(cMisc,repairModeDD,50); repairModeDD.option="qolAutoRepairMode"
  cMisc:Finish(); Add(cMisc)

  container:SetScript("OnShow",function()
    UpdateFPSStatus()
    for _,w in ipairs(ringFrames) do if w.option then
      if w._isPercent then w:SetValue((DB(w.option) or 0)*100) else w:SetValue(DB(w.option)) end
    end end
    if ringColorRow then ringColorRow:SetColor(DB("qolRingColorR") or 0, DB("qolRingColorG") or 0.8, DB("qolRingColorB") or 0.8) end
    if ringShapeDD and ringShapeDD.SetValue then ringShapeDD:SetValue() end
    for _,w in ipairs(timerFrames) do if w.option then
      if w._isPercent then w:SetValue((DB(w.option) or 0)*100) else w:SetValue(DB(w.option)) end
    end end
    if timerColorRow then timerColorRow:SetColor(DB("qolTimerColorR") or 1, DB("qolTimerColorG") or 1, DB("qolTimerColorB") or 1) end
    for _,w in ipairs(alertFrames) do if w.option then
      if w._isPercent then w:SetValue((DB(w.option) or 0)*100) else w:SetValue(DB(w.option)) end
    end end
    if enterTextRow and enterTextRow._eb then enterTextRow._eb:SetText(DB("qolCombatEnterText") or "++ COMBAT ++") end
    if leaveTextRow and leaveTextRow._eb then leaveTextRow._eb:SetText(DB("qolCombatLeaveText") or "-- COMBAT --") end
    if alertEnterColorRow then alertEnterColorRow:SetColor(DB("qolAlertEnterR") or 1, DB("qolAlertEnterG") or 0.2, DB("qolAlertEnterB") or 0.2) end
    if alertLeaveColorRow then alertLeaveColorRow:SetColor(DB("qolAlertLeaveR") or 0.2, DB("qolAlertLeaveG") or 1, DB("qolAlertLeaveB") or 0.2) end
    for _,w in ipairs(miscFrames) do if w.option then w:SetValue(DB(w.option)) end end
    if repairModeDD and repairModeDD.SetValue then repairModeDD:SetValue() end
  end)
  return container
end



local function SetupTabSettings(parent)
  local container = CreateFrame("Frame", nil, parent)
  local allFrames = {}
  local dropdowns = {}
  local builtUI   = false
  local currentTabIdx = 1

  local filtersHeader = NS.ChatGetHeader(container, "Tab Settings")
  filtersHeader:SetPoint("TOP")
  table.insert(allFrames, filtersHeader)

  local function UpdateHeader()
    local tData = NS.chatTabData and NS.chatTabData()
    local td = tData and tData[currentTabIdx]
    local tabName = td and td.name or "\226\128\148"
    filtersHeader.text:SetText(
      "|cff" .. NS.ChatGetAccentHex() .. ">|r" ..
      " |cffffffff" .. "Message Types" .. "|r" ..
      " |cff808080(Tab: " .. tabName .. ")|r"
    )
  end

  local function RefreshDropdowns()
    for _, dd in ipairs(dropdowns) do
      if dd.SetValue then dd:SetValue() end
    end
  end

  local function MakeCatDropdown(cat)
    local capturedCat = cat
    local dd = NS.ChatGetDropdown(container, cat.label)
    dd:SetPoint("TOP", allFrames[#allFrames], "BOTTOM", 0, 0)
    dd.DropDown:SetDefaultText("|cff808080All|r")
    table.insert(allFrames, dd)
    table.insert(dropdowns, dd)

    dd.DropDown:SetupMenu(function(_, rootDescription)
      local tData = NS.chatTabData and NS.chatTabData()
      local td = tData and tData[currentTabIdx]
      for _, ev in ipairs(capturedCat.events) do
        local shortKey = ev:gsub("^CHAT_MSG_", "")
        local label = EVENT_LABELS[shortKey] or shortKey
        local ci = ChatTypeInfo and ChatTypeInfo[shortKey]
        local cr, cg, cb = 1, 1, 1
        if ci then cr, cg, cb = ci.r, ci.g, ci.b end
        local capturedEv = ev
        local chk = rootDescription:CreateCheckbox(
          string.format("|cff%02x%02x%02x%s|r", cr*255, cg*255, cb*255, label),
          function()
            local es = td and td.eventSet
            return not es or (es[capturedEv] == true)
          end,
          function()
            -- Toggle single event
            if not td then return end
            if not td.eventSet then
              td.eventSet = {}
              local cats = NS.FILTER_CATS
              if cats then
                for _, c in ipairs(cats) do
                  for _, e in ipairs(c.events) do td.eventSet[e] = true end
                end
              end
              td.eventSet[capturedEv] = nil
            else
              if td.eventSet[capturedEv] then
                td.eventSet[capturedEv] = nil
              else
                td.eventSet[capturedEv] = true
                -- Check if all events are now on → collapse to nil
                local allOn = true
                local cats2 = NS.FILTER_CATS
                if cats2 then
                  for _, c in ipairs(cats2) do
                    for _, e in ipairs(c.events) do
                      if not td.eventSet[e] then allOn = false; break end
                    end
                    if not allOn then break end
                  end
                end
                if allOn then td.eventSet = nil end
              end
            end
            dd:SetValue()
            if NS.chatTabMsgs then NS.chatTabMsgs[currentTabIdx] = nil end
            if NS.chatRedraw then NS.chatRedraw() end
          end
        )
        NS.SkinMenuElement(chk)
      end
    end)

    dd.SetValue = function()
      local tData2 = NS.chatTabData and NS.chatTabData()
      local td2 = tData2 and tData2[currentTabIdx]
      local es = td2 and td2.eventSet
      local activeLabels = {}
      for _, ev in ipairs(capturedCat.events) do
        if not es or es[ev] == true then
          local shortKey = ev:gsub("^CHAT_MSG_", "")
          local label = EVENT_LABELS[shortKey] or shortKey
          local ci = ChatTypeInfo and ChatTypeInfo[shortKey]
          local cr, cg, cb = 1, 1, 1
          if ci then cr, cg, cb = ci.r, ci.g, ci.b end
          activeLabels[#activeLabels+1] = string.format("|cff%02x%02x%02x%s|r", cr*255, cg*255, cb*255, label)
        end
      end
      local text
      if #activeLabels == 0 then
        text = "|cffff4444None|r"
      else
        text = table.concat(activeLabels, ", ")
      end
      dd.DropDown:SetDefaultText(text)
      if dd.DropDown.Text then dd.DropDown.Text:SetText(text) end
    end
  end

  local function MakeChannelsDropdown()
    local dd = NS.ChatGetDropdown(container, "Channels")
    dd:SetPoint("TOP", allFrames[#allFrames], "BOTTOM", 0, 0)
    dd.DropDown:SetDefaultText("|cff808080All|r")
    table.insert(allFrames, dd)
    table.insert(dropdowns, dd)

    dd.DropDown:SetupMenu(function(_, rootDescription)
      local DEFAULUI_NAMES = {[1]="General",[2]="Trade",[3]="LocalDefense",[4]="Services",[5]="LookingForGroup"}
      local chanList = {}
      local seen = {}
      for i = 1, 5 do
        local ok2, num, name = pcall(GetChannelName, i)
        if ok2 and num and num > 0 and name and name ~= "" then
          chanList[#chanList+1] = {num=i, name=name}
        else
          chanList[#chanList+1] = {num=i, name=DEFAULUI_NAMES[i] or ("Channel "..i)}
        end
        seen[i] = true
      end
      for i = 6, 20 do
        local ok2, num, name = pcall(GetChannelName, i)
        if ok2 and num and num > 0 and name and name ~= "" and not seen[num] then
          chanList[#chanList+1] = {num=num, name=name}; seen[num] = true
        end
      end
      local ci = ChatTypeInfo and ChatTypeInfo["CHANNEL"]
      local cr, cg, cb = 1, 0.75, 0.75
      if ci then cr, cg, cb = ci.r, ci.g, ci.b end
      for _, ch in ipairs(chanList) do
        local capName = ch.name
        local displayLabel = string.format("|cff%02x%02x%02x%d. %s|r", cr*255, cg*255, cb*255, ch.num, ch.name)
        local chk2 = rootDescription:CreateCheckbox(displayLabel,
          function()
            local tData3 = NS.chatTabData and NS.chatTabData()
            local td3 = tData3 and tData3[currentTabIdx]
            if not td3 or not td3.channelBlocked then return true end
            return not td3.channelBlocked[capName]
          end,
          function()
            local tData3 = NS.chatTabData and NS.chatTabData()
            local td3 = tData3 and tData3[currentTabIdx]
            if not td3 then return end
            if not td3.channelBlocked then td3.channelBlocked = {} end
            if td3.channelBlocked[capName] then
              td3.channelBlocked[capName] = nil
              if not next(td3.channelBlocked) then td3.channelBlocked = nil end
            else
              td3.channelBlocked[capName] = true
            end
            dd:SetValue()
            if NS.chatTabMsgs then NS.chatTabMsgs[currentTabIdx] = nil end
            if NS.chatRedraw then NS.chatRedraw() end
          end
        )
        NS.SkinMenuElement(chk2)
      end
    end)

    dd.SetValue = function()
      local tData3 = NS.chatTabData and NS.chatTabData()
      local td3 = tData3 and tData3[currentTabIdx]
      local blocked = td3 and td3.channelBlocked
      local ci2 = ChatTypeInfo and ChatTypeInfo["CHANNEL"]
      local cr2, cg2, cb2 = 1, 0.75, 0.75
      if ci2 then cr2, cg2, cb2 = ci2.r, ci2.g, ci2.b end
      local activeLabels = {}
      local DEFAULUI_NAMES2 = {[1]="General",[2]="Trade",[3]="LocalDefense",[4]="Services",[5]="LookingForGroup"}
      for i = 1, 5 do
        local ok2, num, name = pcall(GetChannelName, i)
        local chName = (ok2 and num and num > 0 and name and name ~= "") and name or (DEFAULUI_NAMES2[i] or ("Channel "..i))
        if not blocked or not blocked[chName] then
          activeLabels[#activeLabels+1] = string.format("|cff%02x%02x%02x%d. %s|r", cr2*255, cg2*255, cb2*255, i, chName)
        end
      end
      local text
      if #activeLabels == 0 then text = "|cffff4444None|r"
      else text = table.concat(activeLabels, ", ") end
      dd.DropDown:SetDefaultText(text)
      if dd.DropDown.Text then dd.DropDown.Text:SetText(text) end
    end
  end

  local function BuildUI()
    if builtUI then return end
    builtUI = true
    local cats = NS.FILTER_CATS
    if not cats then return end
    local byKey = {}
    for _, cat in ipairs(cats) do byKey[cat.key] = cat end
    local order = {"MESSAGES", "CREATURE", "REWARDS", "PVP", "SYSTEM", "ADDONS"}
    for _, key in ipairs(order) do
      if key == "MESSAGES" and byKey[key] then
        MakeCatDropdown(byKey[key])
        MakeChannelsDropdown()
      elseif byKey[key] then
        MakeCatDropdown(byKey[key])
      end
    end
  end

  function container:ShowSettings(tabIdx)
    currentTabIdx = tabIdx or 1
    BuildUI()
    UpdateHeader()
    RefreshDropdowns()
  end

  container:SetScript("OnShow", function()
    BuildUI()
  end)

  return container
end

-- ══════════════════════════════════════════════════════════════════════
-- Main Dialog
-- ══════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════
--  MAIN SETTINGS WINDOW  ::  Cyberpunk neon-line style
-- ═══════════════════════════════════════════════════════════════════════

-- ── Shared PCB background drawer ─────────────────────────────────────────
-- Call with any frame, its width/height, and header height to offset from.
-- Draws the same cyberpunk circuit-trace decoration as the settings window.
NS.DrawPCBBackground = function(frame, W, H, headerH, xOffset)
  -- Enable clipping so textures don't render outside frame bounds
  if frame.SetClipsChildren then frame:SetClipsChildren(true) end
  local ar,ag,ab = NS.ChatGetAccentRGB()
  local CX = (xOffset or 0)
  local CY = (headerH or 0)
  local CW = W - CX - 4
  local CH = H - CY - 4

  local function AccTex(layer,sub,x,y,w,h,alpha)
    -- Clip: skip textures that start outside the frame or would extend badly
    if x<0 or y<0 or x>=W or y>=H then return end
    -- Clamp width/height so texture stays inside frame
    local cw=math.min(w, W-x-1)
    local ch=math.min(h, H-y-1)
    if cw<1 or ch<1 then return end
    local t=frame:CreateTexture(nil,layer,nil,sub)
    t:SetSize(cw,ch); t:SetPoint("TOPLEFT",frame,"TOPLEFT",x,-y)
    t:SetColorTexture(ar,ag,ab,alpha or 0.10)
    return t
  end
  local function H_(x,y,len,a) AccTex("BACKGROUND",3,x,y,len,1,a or 0.10) end
  local function V_(x,y,len,a) AccTex("BACKGROUND",3,x,y,1,len,a or 0.10) end
  local function Node(x,y,a)   AccTex("BACKGROUND",4,x-1,y-1,4,4,a or 0.18) end
  local function Cap(x,y,h2,a)
    if h2 then AccTex("BACKGROUND",3,x,y-3,1,6,a or 0.15)
    else        AccTex("BACKGROUND",3,x-3,y,6,1,a or 0.15) end
  end
  local function Glow(x,y)
    AccTex("BACKGROUND",4,x-2,y-2,6,6,0.12)
    AccTex("BACKGROUND",5,x,y,2,2,0.22)
  end

  -- T1: top strip
  local x1,y1=CX+20,CY+14
  H_(x1,y1,CW-30,0.09); Node(x1+80,y1); Node(x1+200,y1); Node(x1+380,y1)
  V_(x1+80,y1,70,0.08); Cap(x1+80,y1+70,true)
  V_(x1+200,y1,40,0.08); H_(x1+200,y1+40,60,0.07); Cap(x1+260,y1+40,false)
  V_(x1+380,y1,90,0.08); Node(x1+380,y1+90)
  H_(x1+320,y1+90,60,0.07); Cap(x1+320,y1+90,false)
  V_(x1+380,y1+90,50,0.07); Cap(x1+380,y1+140,true)
  Glow(x1+80,y1); Glow(x1+200,y1); Glow(x1+380,y1)

  -- T2: left column spine
  local x2,y2=CX+30,CY+30
  V_(x2,y2,CH-50,0.08); Node(x2,y2+80); Node(x2,y2+180); Node(x2,y2+320)
  H_(x2,y2+80,140,0.07); Cap(x2+140,y2+80,false); Node(x2+140,y2+80)
  V_(x2+140,y2+80,60,0.07); H_(x2+140,y2+140,80,0.06); Cap(x2+220,y2+140,false)
  H_(x2,y2+180,90,0.07); Node(x2+90,y2+180); V_(x2+90,y2+150,30,0.06); Cap(x2+90,y2+150,true)
  H_(x2,y2+320,160,0.07); Node(x2+160,y2+320); V_(x2+160,y2+280,40,0.07); Cap(x2+160,y2+280,true)
  Glow(x2,y2+80); Glow(x2,y2+180); Glow(x2+140,y2+80)

  -- T3: right column spine
  local x3,y3=CX+CW-40,CY+20
  V_(x3,y3,CH-30,0.08); Node(x3,y3+60); Node(x3,y3+160); Node(x3,y3+280)
  H_(x3-120,y3+60,120,0.07); Cap(x3-120,y3+60,false); Node(x3-120,y3+60)
  V_(x3-120,y3+60,50,0.07); H_(x3-120,y3+110,60,0.06); Cap(x3-180,y3+110,false,0.08)
  H_(x3-80,y3+160,80,0.07); Node(x3-80,y3+160); V_(x3-80,y3+120,40,0.07); Cap(x3-80,y3+120,true)
  H_(x3-100,y3+280,100,0.07); Node(x3-100,y3+280)
  Glow(x3,y3+60); Glow(x3,y3+160); Glow(x3-120,y3+60)

  -- T4: mid horizontal bus
  local x4,y4=CX+15,CY+120
  if y4<H then
    H_(x4,y4,CW-20,0.09); Node(x4+60,y4); Node(x4+160,y4); Node(x4+280,y4)
    V_(x4+60,y4,60,0.08); H_(x4+60,y4+60,80,0.07); Cap(x4+140,y4+60,false)
    V_(x4+160,y4,90,0.08); Node(x4+160,y4+90)
    V_(x4+280,y4,-50,0.08); Cap(x4+280,y4-50,true)
    Glow(x4+60,y4); Glow(x4+160,y4); Glow(x4+280,y4)
  end

  -- T5: second horizontal bus
  local x5,y5=CX+20,CY+240
  if y5<H then
    H_(x5,y5,CW-30,0.08); Node(x5+100,y5); Node(x5+250,y5)
    V_(x5+100,y5,80,0.08); H_(x5+100,y5+80,110,0.07)
    V_(x5+250,y5,-40,0.08); H_(x5+190,y5-40,60,0.07); Cap(x5+190,y5-40,false)
    Glow(x5+100,y5); Glow(x5+250,y5)
  end

  -- T6: third horizontal bus
  local x6,y6=CX+10,CY+360
  if y6<H then
    H_(x6,y6,CW-15,0.08); Node(x6+70,y6); Node(x6+200,y6)
    V_(x6+70,y6,50,0.08); H_(x6+70,y6+50,100,0.07); Cap(x6+170,y6+50,false)
    V_(x6+200,y6,80,0.08); Node(x6+200,y6+80)
    Glow(x6+70,y6); Glow(x6+200,y6)
  end

  -- T7: bottom traces
  local x7,y7=CX+25,CY+CH-100
  if y7>CY and y7<H then
    H_(x7,y7,CW-40,0.08); Node(x7+90,y7); Node(x7+240,y7)
    V_(x7+90,y7,60,0.08); H_(x7+90,y7+60,130,0.07); Cap(x7+220,y7+60,false)
    Glow(x7+90,y7); Glow(x7+240,y7)
  end

  -- T8: diagonal stair motifs
  local dx,dy=CX+150,CY+180
  if dy<H then
    H_(dx,dy,40); V_(dx+40,dy-30,30); H_(dx+40,dy-30,60); Node(dx+100,dy-30)
    Glow(dx+100,dy-30)
  end

  -- T9: vertical connector mid
  local vx,vy=CX+320,CY+30
  if vx<W then
    V_(vx,vy,CH-60,0.07); Node(vx,vy+100); Node(vx,vy+220)
    H_(vx,vy+100,80,0.06); Cap(vx+80,vy+100,false)
    H_(vx-60,vy+220,60,0.06); Cap(vx-60,vy+220,false)
    Glow(vx,vy+100); Glow(vx,vy+220)
  end
end

NS.BuildChatOptionsWindow = function()
  if chatOptWin then
    local wasVisible = chatOptWin:IsVisible()
    chatOptWin:SetShown(not wasVisible)
    if not wasVisible and chatOptWin._selectTab and chatOptWin._tabSettingsContainer then
      if chatOptWin._tabSettingsContainer:IsShown() then chatOptWin._selectTab(1) end
    end
    return
  end

  local ar,ag,ab = NS.ChatGetAccentRGB()
  local WIN_W=860; local WIN_H=560
  local HEADER_H=42; local SIDEBAR_W=152; local CONT_Y=HEADER_H+2

  -- ── Root window ────────────────────────────────────────────────────
  chatOptWin = CreateFrame("Frame","LUIChatSettingsDialog",UIParent,"BackdropTemplate")
  chatOptWin:SetToplevel(true); chatOptWin:SetFrameStrata("HIGH")
  chatOptWin:SetSize(WIN_W,WIN_H); chatOptWin:SetPoint("CENTER"); chatOptWin:Raise()
  chatOptWin:SetMovable(true); chatOptWin:SetClampedToScreen(true); chatOptWin:EnableMouse(true)
  chatOptWin:SetScript("OnMouseDown",function(self,btn) if btn=="LeftButton" then self:StartMoving() end end)
  chatOptWin:SetScript("OnMouseUp",function(self) self:StopMovingOrSizing() end)
  chatOptWin:SetBackdrop(BD)
  chatOptWin:SetBackdropColor(0.025,0.025,0.038,0.97)
  chatOptWin:SetBackdropBorderColor(ar,ag,ab,0.38)
  chatOptWin._ltBorderFrame = chatOptWin

  -- ── Cyberpunk decorative lines ──────────────────────────────────────
  -- Helper: thin accent texture
  local function AccTex(layer,sub,x,y,w,h,alpha)
    local t=chatOptWin:CreateTexture(nil,layer,nil,sub)
    t:SetSize(w,h); t:SetPoint("TOPLEFT",chatOptWin,"TOPLEFT",x,-y)
    t:SetColorTexture(ar,ag,ab,alpha or 0.18)
    table.insert(NS.chatOptAccentTextures,{tex=t,alpha=alpha or 0.18})
    return t
  end

  -- ── Structural accents ─────────────────────────────────────────────
  local leftBar = AccTex("OVERLAY",5, 1,1, 3,WIN_H-2, 1)
  chatOptWin._ltLeftBar = leftBar
  local hLine = AccTex("OVERLAY",5, 1,HEADER_H, WIN_W-2,1, 0.55)
  chatOptWin._ltHeaderLine = hLine
  local sbDiv = AccTex("OVERLAY",4, SIDEBAR_W+4,HEADER_H+2, 1,WIN_H-HEADER_H-3, 0.30)
  chatOptWin._ltSidebarLine = sbDiv

  -- Corner cut top-right
  AccTex("OVERLAY",5, WIN_W-28,1, 26,1, 0.70)
  AccTex("OVERLAY",5, WIN_W-2, 1,  1,14,0.70)
  AccTex("OVERLAY",5, WIN_W-18,3, 14,1, 0.35)

  -- ── PCB CIRCUIT TRACES ─────────────────────────────────────────────
  local CX = SIDEBAR_W + 4
  local CY = HEADER_H + 2
  local CW = WIN_W - CX - 4
  local CH = WIN_H - CY - 4

  local function H(x,y,len,a)  AccTex("BACKGROUND",3, x,y, len,1, a or 0.10) end
  local function V(x,y,len,a)  AccTex("BACKGROUND",3, x,y, 1,len, a or 0.10) end
  local function Node(x,y,a)   AccTex("BACKGROUND",4, x-1,y-1, 4,4, a or 0.18) end
  local function Cap(x,y,h,a)
    if h then AccTex("BACKGROUND",3, x,y-3,1,6,a or 0.15)
    else      AccTex("BACKGROUND",3, x-3,y,6,1,a or 0.15) end
  end
  local function Glow(x,y)
    AccTex("BACKGROUND",4, x-2,y-2, 6,6, 0.12)
    AccTex("BACKGROUND",5, x,  y,   2,2, 0.22)
  end

  -- ─── SIDEBAR traces ──────────────────────────────────────────────
  local SX = 6
  V(SX,     CY+10,  400, 0.07); Node(SX,CY+80,0.12); Node(SX,CY+200,0.10); Node(SX,CY+340,0.09)
  H(SX,     CY+80,  SIDEBAR_W-14, 0.05); Cap(SX+SIDEBAR_W-14, CY+80, false, 0.10)
  H(SX,     CY+200, SIDEBAR_W-10, 0.05); Cap(SX+SIDEBAR_W-10, CY+200,false, 0.10)
  V(SX+SIDEBAR_W-22, CY+15, 120, 0.06); Node(SX+SIDEBAR_W-22,CY+70,0.10)
  H(SX+SIDEBAR_W-22, CY+70, 16,  0.05)

  -- ─── CONTENT area: 12 interlocking traces ─────────────────────────

  -- T1: top strip with three branches
  local x1,y1 = CX+20, CY+14
  H(x1,y1,CW-30,0.09); Node(x1+80,y1); Node(x1+200,y1); Node(x1+380,y1); Node(x1+CW-60,y1)
  V(x1+80, y1, 70, 0.08);  Cap(x1+80, y1+70, true)
  V(x1+200,y1, 40, 0.08);  H(x1+200,y1+40,60,0.07); Cap(x1+260,y1+40,false)
  V(x1+380,y1, 90, 0.08);  Node(x1+380,y1+90)
                            H(x1+320,y1+90,60,0.07); Cap(x1+320,y1+90,false)
                            V(x1+380,y1+90,50,0.07); Cap(x1+380,y1+140,true)
  Glow(x1+80,y1); Glow(x1+200,y1); Glow(x1+380,y1)

  -- T2: left column spine
  local x2,y2 = CX+30, CY+30
  V(x2,y2,CH-50,0.08); Node(x2,y2+80); Node(x2,y2+180); Node(x2,y2+320)
  H(x2,y2+80, 140,0.07); Cap(x2+140,y2+80,false); Node(x2+140,y2+80)
  V(x2+140,y2+80,60,0.07); H(x2+140,y2+140,80,0.06); Cap(x2+220,y2+140,false)
  H(x2,y2+180,90,0.07); Node(x2+90,y2+180); V(x2+90,y2+150,30,0.06); Cap(x2+90,y2+150,true)
  H(x2,y2+320,160,0.07); Node(x2+160,y2+320); V(x2+160,y2+280,40,0.07); Cap(x2+160,y2+280,true)
  Glow(x2,y2+80); Glow(x2,y2+180); Glow(x2+140,y2+80)

  -- T3: right column spine
  local x3,y3 = CX+CW-40, CY+20
  V(x3,y3,CH-30,0.08); Node(x3,y3+60); Node(x3,y3+160); Node(x3,y3+280); Node(x3,y3+400)
  H(x3-120,y3+60,  120,0.07); Cap(x3-120,y3+60,false); Node(x3-120,y3+60)
  V(x3-120,y3+60,  50, 0.07); H(x3-120,y3+110,60,0.06); Cap(x3-180,y3+110,false,0.08)
  H(x3-80, y3+160, 80, 0.07); Node(x3-80,y3+160); V(x3-80,y3+120,40,0.07); Cap(x3-80,y3+120,true)
  H(x3-100,y3+280, 100,0.07); Node(x3-100,y3+280)
  V(x3-100,y3+280, 60, 0.07); H(x3-140,y3+340,40,0.06); Cap(x3-140,y3+340,false)
  H(x3-50, y3+400, 50, 0.07); Cap(x3-50,y3+400,false)
  Glow(x3,y3+60); Glow(x3,y3+160); Glow(x3,y3+280); Glow(x3-120,y3+60)

  -- T4: mid horizontal bus
  local x4,y4 = CX+15, CY+120
  H(x4,y4,CW-20,0.09); Node(x4+60,y4); Node(x4+160,y4); Node(x4+280,y4); Node(x4+440,y4); Node(x4+580,y4)
  V(x4+60, y4,  60,0.08); H(x4+60,y4+60,80,0.07);  Cap(x4+140,y4+60,false); Node(x4+60,y4+60)
  V(x4+160,y4,  90,0.08); Node(x4+160,y4+90); H(x4+100,y4+90,60,0.07); Cap(x4+100,y4+90,false)
                           V(x4+160,y4+90,40,0.07); Cap(x4+160,y4+130,true)
  V(x4+280,y4, -50,0.08); Cap(x4+280,y4-50,true)
  V(x4+440,y4,  70,0.08); H(x4+440,y4+70,90,0.07);  Node(x4+530,y4+70); V(x4+530,y4+40,30,0.07); Cap(x4+530,y4+40,true)
  V(x4+580,y4,  40,0.08); H(x4+580,y4+40,CW-580-15,0.07)
  Glow(x4+60,y4); Glow(x4+160,y4); Glow(x4+280,y4); Glow(x4+440,y4)

  -- T5: second horizontal bus lower
  local x5,y5 = CX+20, CY+240
  H(x5,y5,CW-30,0.08); Node(x5+100,y5); Node(x5+250,y5); Node(x5+420,y5); Node(x5+560,y5)
  V(x5+100,y5,  80,0.08); H(x5+100,y5+80,110,0.07); Node(x5+210,y5+80); V(x5+210,y5+60,20,0.06); Cap(x5+210,y5+60,true)
  V(x5+250,y5, -40,0.08); H(x5+190,y5-40,60,0.07); Cap(x5+190,y5-40,false)
  V(x5+420,y5,  60,0.08); Node(x5+420,y5+60); H(x5+360,y5+60,60,0.07); Cap(x5+360,y5+60,false)
  V(x5+560,y5,  90,0.08); H(x5+560,y5+90,70,0.07); Cap(x5+630,y5+90,false)
  Glow(x5+100,y5); Glow(x5+250,y5); Glow(x5+420,y5); Glow(x5+560,y5)

  -- T6: third horizontal bus
  local x6,y6 = CX+10, CY+360
  H(x6,y6,CW-15,0.08); Node(x6+70,y6); Node(x6+200,y6); Node(x6+370,y6); Node(x6+520,y6)
  V(x6+70, y6,  50,0.08); H(x6+70,y6+50,100,0.07); Cap(x6+170,y6+50,false)
  V(x6+200,y6,  80,0.08); Node(x6+200,y6+80); H(x6+140,y6+80,60,0.07); Cap(x6+140,y6+80,false)
                           V(x6+200,y6+80,40,0.07); Cap(x6+200,y6+120,true)
  V(x6+370,y6, -70,0.08); H(x6+310,y6-70,60,0.07); Node(x6+310,y6-70); V(x6+310,y6-100,30,0.07); Cap(x6+310,y6-100,true)
  V(x6+520,y6,  60,0.08); H(x6+520,y6+60,CW-520-15,0.07)
  Glow(x6+70,y6); Glow(x6+200,y6); Glow(x6+370,y6); Glow(x6+310,y6-70)

  -- T7: bottom area traces
  local x7,y7 = CX+25, CY+CH-100
  H(x7,y7,CW-40,0.08); Node(x7+90,y7); Node(x7+240,y7); Node(x7+420,y7)
  V(x7+90, y7,  60,0.08); H(x7+90,y7+60,130,0.07); Cap(x7+220,y7+60,false)
  V(x7+240,y7,  40,0.08); H(x7+180,y7+40,60,0.07); Cap(x7+180,y7+40,false)
  V(x7+420,y7, -80,0.08); Node(x7+420,y7-80); H(x7+360,y7-80,60,0.07); Cap(x7+360,y7-80,false)
  Glow(x7+90,y7); Glow(x7+240,y7); Glow(x7+420,y7)

  -- T8: diagonal stair motifs (PCB corner routing)
  local dx,dy = CX+150, CY+180
  H(dx,dy,40); V(dx+40,dy-30,30); H(dx+40,dy-30,60); Node(dx+100,dy-30)
  V(dx+100,dy-30,40,0.08); H(dx+100,dy+10,50,0.07); Cap(dx+150,dy+10,false)
  Glow(dx+100,dy-30)

  local dx2,dy2 = CX+480, CY+200
  H(dx2,dy2,50,0.08); V(dx2+50,dy2-35,35,0.08); H(dx2+50,dy2-35,70,0.08)
  Node(dx2+120,dy2-35); V(dx2+120,dy2-65,30,0.07); Cap(dx2+120,dy2-65,true)
  Glow(dx2+120,dy2-35)

  -- T9: vertical connector mid
  local vx,vy = CX+320, CY+30
  V(vx,vy,CH-60,0.07); Node(vx,vy+100); Node(vx,vy+220); Node(vx,vy+370)
  H(vx,vy+100,80,0.06); Cap(vx+80,vy+100,false)
  H(vx-60,vy+220,60,0.06); Cap(vx-60,vy+220,false)
  H(vx,vy+370,100,0.06); Node(vx+100,vy+370); V(vx+100,vy+340,30,0.06); Cap(vx+100,vy+340,true)
  Glow(vx,vy+100); Glow(vx,vy+220); Glow(vx,vy+370)

  -- T10: header area PCB traces
  local hx,hy = CX+50, CY-HEADER_H+8
  if hy > 2 then
    H(hx,hy,CW-60,0.07); Node(hx+100,hy); Node(hx+300,hy); Node(hx+500,hy)
    V(hx+100,hy,10,0.06); V(hx+300,hy,10,0.06); V(hx+500,hy,10,0.06)
    Glow(hx+100,hy); Glow(hx+300,hy)
  end

  -- ── Header background ──────────────────────────────────────────────
  local headerBg = chatOptWin:CreateTexture(nil,"BACKGROUND",nil,2)
  headerBg:SetPoint("TOPLEFT", chatOptWin,"TOPLEFT",  1,-1)
  headerBg:SetPoint("TOPRIGHT",chatOptWin,"TOPRIGHT", -1,-1)
  headerBg:SetHeight(HEADER_H); headerBg:SetColorTexture(0.010,0.010,0.020,1)

  -- ── Addon title (top-left in header) ──────────────────────────────
  local addonVersion = C_AddOns and C_AddOns.GetAddOnMetadata and
                       C_AddOns.GetAddOnMetadata("LucidUI","Version") or "?"
  local thex = string.format("|cff%02x%02x%02x",ar*255,ag*255,ab*255)

  local titleFS = chatOptWin:CreateFontString(nil,"OVERLAY")
  titleFS:SetFont("Fonts/FRIZQT__.TTF",14,"OUTLINE")
  titleFS:SetPoint("TOPLEFT",chatOptWin,"TOPLEFT",14,-8)
  titleFS:SetText(thex.."LUCID|r|cffffffff".."UI|r")
  chatOptWin._ltTitleName = titleFS

  local verFS = chatOptWin:CreateFontString(nil,"OVERLAY")
  verFS:SetFont("Fonts/FRIZQT__.TTF",8,"")
  verFS:SetPoint("TOPLEFT",titleFS,"BOTTOMLEFT",0,-1)
  verFS:SetTextColor(0.33,0.33,0.42); verFS:SetText("v"..addonVersion)

  -- ── Header buttons (high framelevel layer) ──────────────────────────
  local btnLayer=CreateFrame("Frame",nil,chatOptWin)
  btnLayer:SetPoint("TOPRIGHT",chatOptWin,"TOPRIGHT",-4,-1)
  btnLayer:SetSize(260,HEADER_H)
  btnLayer:SetFrameLevel(chatOptWin:GetFrameLevel()+20)
  btnLayer:EnableMouse(false)

  local function HdrBtn(lbl,onClick)
    local btn=CreateFrame("Button",nil,btnLayer,"BackdropTemplate")
    btn:SetHeight(22); btn:SetFrameLevel(btnLayer:GetFrameLevel())
    btn:SetBackdrop(BD); btn:SetBackdropColor(0.05,0.05,0.09,1); btn:SetBackdropBorderColor(0.12,0.12,0.20,1)
    local fs=btn:CreateFontString(nil,"OVERLAY"); fs:SetFont("Fonts/FRIZQT__.TTF",9,"")
    fs:SetPoint("CENTER",0,0); fs:SetTextColor(0.44,0.44,0.52); fs:SetText(lbl)
    btn:SetWidth(fs:GetStringWidth()+16)
    btn:SetScript("OnEnter",function()
      local cr,cg,cb=NS.ChatGetAccentRGB(); btn:SetBackdropBorderColor(cr,cg,cb,0.75); fs:SetTextColor(cr,cg,cb)
    end)
    btn:SetScript("OnLeave",function() btn:SetBackdropBorderColor(0.12,0.12,0.20,1); fs:SetTextColor(0.44,0.44,0.52) end)
    btn:SetScript("OnClick",onClick)
    btn:SetPoint("TOP",btnLayer,"TOP",0,-10)
    return btn
  end

  -- Close X
  local closeBtn=CreateFrame("Button",nil,btnLayer,"BackdropTemplate")
  closeBtn:SetSize(22,22); closeBtn:SetPoint("RIGHT",btnLayer,"RIGHT",0,0); closeBtn:SetPoint("TOP",btnLayer,"TOP",0,-10)
  closeBtn:SetFrameLevel(btnLayer:GetFrameLevel())
  closeBtn:SetBackdrop(BD); closeBtn:SetBackdropColor(0.09,0.02,0.02,1); closeBtn:SetBackdropBorderColor(0.34,0.09,0.09,1)
  local cX=closeBtn:CreateFontString(nil,"OVERLAY"); cX:SetFont("Fonts/FRIZQT__.TTF",11,""); cX:SetPoint("CENTER",0,0); cX:SetTextColor(0.60,0.18,0.18); cX:SetText("X")
  closeBtn:SetScript("OnEnter",function() closeBtn:SetBackdropBorderColor(0.82,0.16,0.16,1); cX:SetTextColor(1,0.30,0.30) end)
  closeBtn:SetScript("OnLeave",function() closeBtn:SetBackdropBorderColor(0.34,0.09,0.09,1); cX:SetTextColor(0.60,0.18,0.18) end)
  closeBtn:SetScript("OnClick",function() chatOptWin:Hide() end)
  chatOptWin.CloseButton=closeBtn

  local reloadBtn=HdrBtn("/reload",function() ReloadUI() end)
  reloadBtn:SetPoint("RIGHT",closeBtn,"LEFT",-4,0); reloadBtn:SetPoint("TOP",btnLayer,"TOP",0,-10)
  local debugBtn=HdrBtn(L["Debug"],function() if NS.BuildDebugWindow then NS.BuildDebugWindow() end end)
  debugBtn:SetPoint("RIGHT",reloadBtn,"LEFT",-4,0); debugBtn:SetPoint("TOP",btnLayer,"TOP",0,-10)

  -- ── Sidebar background ─────────────────────────────────────────────
  local sbBg=chatOptWin:CreateTexture(nil,"BACKGROUND",nil,1)
  sbBg:SetPoint("TOPLEFT",   chatOptWin,"TOPLEFT",   3,-(HEADER_H+2))
  sbBg:SetPoint("BOTTOMLEFT",chatOptWin,"BOTTOMLEFT",3, 1)
  sbBg:SetWidth(SIDEBAR_W); sbBg:SetColorTexture(0.012,0.012,0.022,1)

  -- ── Content background ─────────────────────────────────────────────
  local cbBg=chatOptWin:CreateTexture(nil,"BACKGROUND",nil,1)
  cbBg:SetPoint("TOPLEFT",    chatOptWin,"TOPLEFT",    SIDEBAR_W+4,-(HEADER_H+2))
  cbBg:SetPoint("BOTTOMRIGHT",chatOptWin,"BOTTOMRIGHT",-1,1)
  cbBg:SetColorTexture(0.025,0.025,0.038,1)

  -- ── Tabs ───────────────────────────────────────────────────────────
  local TabSetups={
    {name="Display",     callback=SetupDisplay},
    {name="Appearance",  callback=SetupAppearance},
    {name="Text",        callback=SetupText},
    {name="Advanced",    callback=SetupAdvanced},
    {name="Chat Colors", callback=SetupMessageColors},
    {name="Loot",        callback=SetupLoot},
    {name="QoL",         callback=SetupQoL},
    {name="LucidMeter",  callback=NS.LucidMeter.SetupSettings},
    {name="Bags",        callback=NS.Bags.SetupSettings},
    {name="Gold",        callback=NS.GoldTracker.SetupSettings},
    {name="Mythic+",     callback=NS.MythicPlus.SetupSettings},
    {name="Tab Settings",callback=SetupTabSettings,hidden=true},
  }

  local TAB_H=34; local containers={}; local tabs={}

  local sidebar=CreateFrame("Frame",nil,chatOptWin)
  sidebar:SetWidth(SIDEBAR_W)
  sidebar:SetPoint("TOPLEFT",   chatOptWin,"TOPLEFT",   3,-(HEADER_H+2))
  sidebar:SetPoint("BOTTOMLEFT",chatOptWin,"BOTTOMLEFT",3, 1)
  sidebar:SetFrameLevel(chatOptWin:GetFrameLevel()+2)

  local function SelectTab(idx)
    for i,c in ipairs(containers) do
      c:Hide()
      local btn=tabs[i]
      if btn then
        btn._selected=false
        if btn._label  then btn._label:SetTextColor(0.36,0.36,0.46) end
        if btn._selLine then btn._selLine:Hide() end
        if btn._selBg   then btn._selBg:Hide() end
      end
    end
    containers[idx]:Show()
    local btn=tabs[idx]
    if btn then
      btn._selected=true
      local cr,cg,cb=NS.ChatGetAccentRGB()
      if btn._label   then btn._label:SetTextColor(cr,cg,cb) end
      if btn._selLine then btn._selLine:Show() end
      if btn._selBg   then btn._selBg:Show() end
    end
  end

  local visIdx=0
  for i,setup in ipairs(TabSetups) do
    local tc=setup.callback(chatOptWin)
    tc:ClearAllPoints()
    tc:SetPoint("TOPLEFT",    chatOptWin,"TOPLEFT",    SIDEBAR_W+4,-(CONT_Y))
    tc:SetPoint("BOTTOMRIGHT",chatOptWin,"BOTTOMRIGHT",-1,1)
    tc:Hide()

    local tabBtn=CreateFrame("Button",nil,sidebar)
    tabBtn:SetFrameLevel(sidebar:GetFrameLevel()+1)

    if not setup.hidden then
      visIdx=visIdx+1
      tabBtn:SetSize(SIDEBAR_W,TAB_H)
      tabBtn:SetPoint("TOPLEFT",sidebar,"TOPLEFT",0,-(visIdx-1)*TAB_H)

      local selBg=tabBtn:CreateTexture(nil,"BACKGROUND",nil,2); selBg:SetAllPoints()
      selBg:SetColorTexture(ar,ag,ab,0.06); selBg:Hide(); tabBtn._selBg=selBg

      local selLine=tabBtn:CreateTexture(nil,"OVERLAY",nil,5); selLine:SetWidth(3)
      selLine:SetPoint("TOPLEFT",   tabBtn,"TOPLEFT",   0,-5)
      selLine:SetPoint("BOTTOMLEFT",tabBtn,"BOTTOMLEFT",0, 5)
      selLine:SetColorTexture(ar,ag,ab,1); selLine:Hide(); tabBtn._selLine=selLine

      -- Small corner tick on active tab (top-right)
      local tabTick=tabBtn:CreateTexture(nil,"OVERLAY",nil,4); tabTick:SetSize(6,1)
      tabTick:SetPoint("TOPRIGHT",tabBtn,"TOPRIGHT",0,-3); tabTick:SetColorTexture(ar,ag,ab,0.40)
      table.insert(NS.chatOptAccentTextures,{tex=tabTick,alpha=0.40})

      local label=tabBtn:CreateFontString(nil,"OVERLAY"); label:SetFont("Fonts/FRIZQT__.TTF",11,"")
      label:SetPoint("LEFT",14,0); label:SetTextColor(0.36,0.36,0.46); label:SetText(setup.name)
      tabBtn._label=label

      tabBtn:SetScript("OnEnter",function()
        if not tabBtn._selected then
          local cr,cg,cb=NS.ChatGetAccentRGB()
          label:SetTextColor(cr*0.70,cg*0.70,cb*0.70); selBg:Show()
        end
      end)
      tabBtn:SetScript("OnLeave",function()
        if not tabBtn._selected then label:SetTextColor(0.36,0.36,0.46); selBg:Hide() end
      end)
    else
      tabBtn:SetSize(1,1); tabBtn:SetPoint("TOPLEFT",sidebar,"TOPLEFT",-9999,0); tabBtn:Hide()
      tabBtn._label  =tabBtn:CreateFontString(nil,"OVERLAY")
      tabBtn._selLine=tabBtn:CreateTexture(nil,"OVERLAY")
      tabBtn._selBg  =tabBtn:CreateTexture(nil,"BACKGROUND")
    end

    local ci=i; tabBtn:SetScript("OnClick",function() SelectTab(ci) end)
    tc.button=tabBtn
    if setup.hidden then
      chatOptWin._tabSettingsContainer=tc; chatOptWin._tabSettingsButton=tabBtn; chatOptWin._tabSettingsIdx=i
    end
    if setup.name=="Bags" then chatOptWin._bagsTabIdx=i end
    table.insert(tabs,tabBtn); table.insert(containers,tc)
  end

  chatOptWin.containers=containers; chatOptWin._selectTab=SelectTab; chatOptWin._ltTabLine=nil
  NS.chatOptWin=chatOptWin
  SelectTab(1)
end

NS.OpenChatTabSettings = function(chatTabIdx)
  if not chatOptWin then NS.BuildChatOptionsWindow() end
  if not chatOptWin then return end
  chatOptWin:Show(); chatOptWin:Raise()
  if chatOptWin._selectTab and chatOptWin._tabSettingsIdx then
    chatOptWin._selectTab(chatOptWin._tabSettingsIdx)
  end
  C_Timer.After(0,function()
    if chatOptWin._tabSettingsContainer and chatOptWin._tabSettingsContainer.ShowSettings then
      chatOptWin._tabSettingsContainer:ShowSettings(chatTabIdx)
    end
  end)
end