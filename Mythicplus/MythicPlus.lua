-- LucidUI MythicPlus.lua  v2.0
-- Full-featured Mythic+ tracker matching GLogger feature set.
-- No external dependencies — pure LucidUI style.
--
-- Derived from GLogger/modules/MPlusLog.lua
-- GLogger Copyright (C) 2025 Osiris the Kiwi
-- GLogger is licensed under the GNU General Public License v3.
-- Source: https://www.curseforge.com/wow/addons/glogger
--
-- LucidUI Copyright (C) 2026 Argyy
-- Licensed under the GNU General Public License v3.

local NS = LucidUINS
NS.MythicPlus = NS.MythicPlus or {}
local MP = NS.MythicPlus
MP._accentTextures = {}   -- {tex=..., alpha=..., isFS=...} registered at build time

local function RegAccent(tex, alpha, isFS)
  table.insert(MP._accentTextures, {tex=tex, alpha=alpha or 1, isFS=isFS})
  -- Also add to shared list for settings window updates
  if NS.chatOptAccentTextures then
    table.insert(NS.chatOptAccentTextures, {tex=tex, alpha=alpha or 1, isFS=isFS})
  end
end

-- ─────────────────────────────── SEASONS ────────────────────────────────────
-- Map whatever Blizzard's GetCurrentSeason() returns to our internal season key.
-- Blizzard can return different IDs across patches (e.g. 1 or 2 for Midnight S1).
-- Add entries here as new seasons launch.
MP.SeasonMap = {
  [1] = 1,   -- Blizzard ID 1 → our key 1 (Midnight S1)
  [2] = 1,   -- Blizzard ID 2 → our key 1 (Midnight S1, API returned 2 in some builds)
}

MP.Seasons = {
  [1]={name="Midnight Season 1",dungeons={
    -- texture = FileDataID from GLogger (fallback when GetMapUIInfo returns nil)
    [402]={abbr="AA",  name="Ara-Kara, City of Echoes",      texture=4742929},
    [560]={abbr="MC",  name="Mechagon Workshop",              texture=7478529},
    [558]={abbr="MT",  name="Mists of Tirna Scithe",          texture=7467174},
    [559]={abbr="NPX", name="Necrotic Wake",                  texture=7570501},
    [556]={abbr="POS", name="Pit of Saron",                   texture=608210},
    [239]={abbr="SEAT",name="Siege of Atal'Dazar",           texture=1718213},
    [161]={abbr="SR",  name="Stonevault",                     texture=1041999},
    [557]={abbr="WS",  name="City of Threads",                texture=7464937},
  }},
}

-- Status helpers
local SCOLOR={[0]={0.45,0.45,0.45},[1]={0.75,0.25,0.25},[2]={0.30,0.80,0.30},[3]={0.15,0.75,1.00},[4]={1.00,0.84,0.00}}
local STEXT={[0]="Abandoned",[1]="Depleted",[2]="+1",[3]="+2",[4]="+3"}
local function SC(s) local c=SCOLOR[s] or SCOLOR[0]; return c[1],c[2],c[3] end
local function ST(s) return STEXT[s] or tostring(s) end
local function SR(s)
  if s==0 then return 1 elseif s==1 then return 2
  elseif s==2 then return 3 elseif s==3 then return 4 elseif s==4 then return 5 end; return 0
end

-- ─────────────────────────────── DB ────────────────────────────────────────
local function GetDB()
  if not LucidUIDB then LucidUIDB={} end
  if not LucidUIDB.mpRuns then LucidUIDB.mpRuns={} end
  return LucidUIDB.mpRuns
end
local function GetPlayerKey()
  local n,r=UnitFullName("player")
  if r and r~="" then return n.."-"..(r:gsub("%s+","")) end
  return n or UnitName("player") or "Unknown"
end
local function GetCurrentSeason()
  local raw=C_MythicPlus and C_MythicPlus.GetCurrentSeason and C_MythicPlus.GetCurrentSeason()
  -- Normalise via SeasonMap (handles Blizzard's varying IDs)
  local s = raw and (MP.SeasonMap[raw] or raw)
  if s and MP.Seasons[s] then return s end
  -- Fallback: highest known season
  local mx=1; for k in pairs(MP.Seasons) do if k>mx then mx=k end end; return mx
end
local function GetRuns(key,season)
  local db=GetDB(); local k=key or GetPlayerKey(); local s=season or GetCurrentSeason()
  return (db[k] and db[k][s]) or {}
end
local function SaveRun(run)
  local db=GetDB(); local k=GetPlayerKey(); local s=GetCurrentSeason()
  if not db[k] then db[k]={} end
  if not db[k][s] then db[k][s]={} end
  table.insert(db[k][s],run)
end
local function FmtTime(s)
  if not s or s<0 then return "--:--" end
  return string.format("%02d:%02d",math.floor(s/60),math.floor(s%60))
end
local function ClassHex(class)
  if class then local cc=C_ClassColor and C_ClassColor.GetClassColor(class); if cc then return cc:GenerateHexColor() end end
  return "ffffffff"
end

-- ─────────────────────────────── ACTIVE RUN ─────────────────────────────────
local activeRun, activeState = nil, "IDLE"
MP._selSeason=nil; MP._selAlt=nil; MP._filterMap=nil; MP._filterPlayer=nil; MP._selRun=nil
MP._maskNames=false; MP._hideFails=false

local function BuildRoster()
  local r={}; local pk=GetPlayerKey()
  for i=1,4 do local u="party"..i; if UnitExists(u) then
    local nm,rl=UnitFullName(u); local rn=(rl or GetRealmName() or ""):gsub("%s+","")
    r[nm.."-"..rn]={class=select(2,UnitClass(u)),role=UnitGroupRolesAssigned(u)}
  end end
  r[pk]={class=select(2,UnitClass("player")),role=UnitGroupRolesAssigned("player")}
  return r
end

local function CommitRun(att)
  if not activeRun or activeState~="COMPLETED" then return end; att=att or 1
  local mid,lv,el
  if C_ChallengeMode.GetChallengeCompletionInfo then
    local info=C_ChallengeMode.GetChallengeCompletionInfo()
    if type(info)=="table" then mid=info.mapChallengeModeID or info.mapID; lv=info.level; el=info.time or info.durationSec
    else mid,lv,el=C_ChallengeMode.GetChallengeCompletionInfo() end
  end
  if (not el or el==0) and att<10 then C_Timer.After(0.5,function() CommitRun(att+1) end); return end
  activeRun.timeElapsed=(el or 0)/1000; activeRun.date=time()
  if activeRun.mapID==0 and mid then activeRun.mapID=mid; local mn,_,lim=C_ChallengeMode.GetMapUIInfo(mid)
    if mn then activeRun.mapName=mn end; if lim then activeRun.timeLimit=lim end end
  if activeRun.level==0 and lv then activeRun.level=lv end
  local lim=activeRun.timeLimit or 0; local e=activeRun.timeElapsed
  if lim>0 and e>0 and e<=lim then
    if e<=lim*0.6 then activeRun.status=4 elseif e<=lim*0.8 then activeRun.status=3 else activeRun.status=2 end
  else activeRun.status=1 end
  activeRun.overallScore=C_ChallengeMode.GetOverallDungeonScore() or 0; activeRun.mapScore=0
  SaveRun(activeRun)
  local rc=activeRun
  local function Poll(a) if a>15 then return end
    C_Timer.After(2,function()
      if C_MythicPlus.RequestRewards then C_MythicPlus.RequestRewards() end
      local hist=C_MythicPlus.GetRunHistory and C_MythicPlus.GetRunHistory(true,true)
      if hist then for _,br in ipairs(hist) do
        if br.mapChallengeModeID==rc.mapID and br.level==rc.level then
          if br.durationSec and math.abs(br.durationSec-rc.timeElapsed)<=2 then
            rc.mapScore=br.runScore or br.dungeonScore or br.score or 0
            rc.overallScore=C_ChallengeMode.GetOverallDungeonScore() or rc.overallScore
            if MP.win and MP.win:IsShown() then MP.Refresh() end; return
          end end end end
      Poll(a+1) end) end; Poll(1)
  activeState="IDLE"; activeRun=nil
  if MP.win and MP.win:IsShown() then MP.Refresh() end
end

-- ─────────────────────────────── BLIZZARD SYNC (GLogger approach) ────────
function MP.SyncBlizzard(key,season)
  local k=key or GetPlayerKey(); local s=season or GetCurrentSeason()
  if not MP.Seasons[s] then return end
  local db=GetDB(); if not db[k] then db[k]={} end; if not db[k][s] then db[k][s]={} end
  local ourDB=db[k][s]
  local currentOverallScore=C_ChallengeMode.GetOverallDungeonScore() or 0
  local importOffset=0  -- sequential counter so imports sort by order, not all same second

  local function AddRunIfMissing(mid,lv,isC,sc,el)
    if not mid or mid==0 then return end
    -- Dedup: 2s tolerance (GLogger value), NEVER overwrite roster/loot/deaths
    for _,r in ipairs(ourDB) do
      if r.mapID==mid and r.level==lv then
        local diff=(el and r.timeElapsed) and math.abs(r.timeElapsed-el) or 0
        local match=(el and r.timeElapsed) and diff<=2 or (not el or not r.timeElapsed)
        if match then
          -- Only update score on match
          if sc and sc>0 and (not r.mapScore or sc>r.mapScore) then r.mapScore=sc end
          return  -- duplicate found, keep existing data intact
        end
      end
    end
    -- Not found — insert as baseline import (no roster/loot/deaths)
    local mn,_,_,lim=C_ChallengeMode.GetMapUIInfo(mid); lim=lim or 1800
    local safe=el or (isC and lim-1 or lim+1); local st=1
    if isC and safe<=lim then
      if safe<=lim*0.6 then st=4 elseif safe<=lim*0.8 then st=3 else st=2 end
    end
    table.insert(ourDB,{
      status=st, mapID=mid, mapName=mn or "Unknown", level=lv or 0,
      timeLimit=lim, timeElapsed=safe, deaths=0, timeLost=0,
      mapScore=sc or 0, overallScore=currentOverallScore,
      date=time()-importOffset, roster={}, loot={}, _blizzardImport=true
    })
    importOffset=importOffset+1
  end

  -- Step 1: Season best per dungeon (GetSeasonBestForMap — GLogger does this first)
  if MP.Seasons[s] and MP.Seasons[s].dungeons then
    for mid,_ in pairs(MP.Seasons[s].dungeons) do
      local inT,ovT=C_MythicPlus.GetSeasonBestForMap(mid)
      if inT and (inT.level or 0)>0 then
        AddRunIfMissing(mid,inT.level,true,inT.dungeonScore or 0,inT.durationSec)
      end
      if ovT and (ovT.level or 0)>0 then
        AddRunIfMissing(mid,ovT.level,false,ovT.dungeonScore or 0,ovT.durationSec)
      end
    end
  end

  -- Step 2: Full run history
  local hist=C_MythicPlus.GetRunHistory and C_MythicPlus.GetRunHistory(true,true)
  if hist then
    for _,br in ipairs(hist) do
      AddRunIfMissing(br.mapChallengeModeID,br.level,br.completed,
        br.runScore or br.dungeonScore or br.score or 0, br.durationSec)
    end
  end
end

-- ─────────────────────────────── EVENTS ─────────────────────────────────────
local evF=CreateFrame("Frame")
evF:RegisterEvent("PLAYER_LOGIN"); evF:RegisterEvent("PLAYER_ENTERING_WORLD")
evF:RegisterEvent("CHALLENGE_MODE_START"); evF:RegisterEvent("WORLD_STATE_TIMER_START")
evF:RegisterEvent("CHALLENGE_MODE_RESET"); evF:RegisterEvent("CHALLENGE_MODE_DEATH_COUNT_UPDATED")
evF:RegisterEvent("CHALLENGE_MODE_COMPLETED"); evF:RegisterEvent("ZONE_CHANGED_NEW_AREA")
evF:RegisterEvent("ENCOUNTER_LOOT_RECEIVED")
evF:SetScript("OnEvent",function(_,ev,...)
  if ev=="PLAYER_LOGIN" then
    -- Migrate runs from any season key that maps to key 1 (e.g. Blizzard returned 2 before SeasonMap fix)
    C_Timer.After(1, function()
      local db=GetDB(); local totalMigrated=0
      for _,charData in pairs(db) do
        for rawKey,runs in pairs(charData) do
          local mappedKey=MP.SeasonMap[rawKey]
          if mappedKey and mappedKey~=rawKey and type(runs)=="table" and #runs>0 then
            if not charData[mappedKey] then charData[mappedKey]={} end
            -- Dedup by mapID+level+floor(timeElapsed)
            local seen={}
            for _,r in ipairs(charData[mappedKey]) do
              seen[tostring(r.mapID).."|"..tostring(r.level).."|"..tostring(math.floor(r.timeElapsed or 0))]=true
            end
            local moved=0
            for _,r in ipairs(runs) do
              local sig=tostring(r.mapID).."|"..tostring(r.level).."|"..tostring(math.floor(r.timeElapsed or 0))
              if not seen[sig] then table.insert(charData[mappedKey],r); seen[sig]=true; moved=moved+1 end
            end
            charData[rawKey]=nil  -- remove old bucket
            totalMigrated=totalMigrated+moved
          end
        end
      end
      if totalMigrated>0 then
        print("|cff3bd2ed[LucidUI Mythic+]|r Migrated "..totalMigrated.." run(s) to Midnight Season 1.")
      end
    end)
    C_Timer.After(3,function()
      if C_MythicPlus.RequestRewards then C_MythicPlus.RequestRewards() end
      if C_MythicPlus.RequestMapInfo then C_MythicPlus.RequestMapInfo() end
      C_Timer.After(2,function() MP.SyncBlizzard() end)
    end)
  elseif ev=="PLAYER_ENTERING_WORLD" then
    if C_ChallengeMode.IsChallengeModeActive() and activeState=="IDLE" then
      activeState="ACTIVE"; local mid=C_ChallengeMode.GetActiveChallengeMapID() or 0
      local lv,aff=C_ChallengeMode.GetActiveKeystoneInfo()
      local mn,_,lim=C_ChallengeMode.GetMapUIInfo(mid); local d,tl=C_ChallengeMode.GetDeathCount()
      activeRun={status=0,mapID=mid,mapName=mn or "Unknown",level=lv or 0,affixes=aff or {},
        timeLimit=lim or 1800,startTime=GetTime(),date=time(),roster=BuildRoster(),
        loot={},deaths=d or 0,timeLost=tl or 0}
    end
  elseif ev=="CHALLENGE_MODE_START" then
    if activeState=="COMPLETED" then CommitRun(1) end; activeState="WARMING_UP"
    activeRun={status=0,mapID=0,mapName="",level=0,affixes={},timeLimit=0,
      startTime=GetTime(),date=time(),roster={},loot={},deaths=0,timeLost=0}
    C_Timer.After(45,function() if activeState=="WARMING_UP" then activeState="IDLE"; activeRun=nil end end)
  elseif ev=="WORLD_STATE_TIMER_START" then
    if activeState=="WARMING_UP" then activeState="ACTIVE"
      local mid=C_ChallengeMode.GetActiveChallengeMapID() or 0
      local lv,aff=C_ChallengeMode.GetActiveKeystoneInfo(); local mn,_,lim=C_ChallengeMode.GetMapUIInfo(mid)
      if activeRun then activeRun.mapID=mid; activeRun.mapName=mn or "Unknown"; activeRun.level=lv or 0
        activeRun.affixes=aff or {}; activeRun.timeLimit=lim or 1800
        activeRun.startTime=GetTime(); activeRun.roster=BuildRoster() end end
  elseif ev=="CHALLENGE_MODE_RESET" then
    if activeState=="WARMING_UP" or activeState=="ACTIVE" then activeState="IDLE"; activeRun=nil end
  elseif ev=="CHALLENGE_MODE_DEATH_COUNT_UPDATED" then
    if activeState=="ACTIVE" and activeRun then local d,tl=C_ChallengeMode.GetDeathCount()
      activeRun.deaths=d or 0; activeRun.timeLost=tl or 0 end
  elseif ev=="CHALLENGE_MODE_COMPLETED" then
    if activeRun then activeState="COMPLETED"; CommitRun(1) end
  elseif ev=="ZONE_CHANGED_NEW_AREA" then
    if (activeState=="ACTIVE" or activeState=="WARMING_UP") and not C_ChallengeMode.IsChallengeModeActive() then
      if activeRun then activeRun.status=0; activeRun.timeElapsed=GetTime()-activeRun.startTime
        activeRun.date=time(); SaveRun(activeRun); activeState="IDLE"; activeRun=nil end end
  elseif ev=="ENCOUNTER_LOOT_RECEIVED" then
    -- GLogger: loot fires when COMPLETED (chest opens after timer) — also catch ACTIVE for safety
    local _,itemID,link,qty,player=...
    if (activeState=="ACTIVE" or activeState=="COMPLETED") and activeRun and link then
      if not player or player=="" then player=GetPlayerKey() end
      -- Resolve player name against roster (match short name if no realm suffix)
      local resolvedOwner=player
      if activeRun.roster then
        local cleanIncoming=player:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")
        if activeRun.roster[cleanIncoming] then
          resolvedOwner=cleanIncoming
        else
          local searchName=cleanIncoming:match("^(.-)-") or cleanIncoming
          for fullName,_ in pairs(activeRun.roster) do
            local rosterShort=fullName:match("^(.-)-") or fullName
            if rosterShort==searchName then resolvedOwner=fullName; break end
          end
        end
      end
      -- Dedup
      local dupe=false
      for _,existing in ipairs(activeRun.loot) do
        if existing.link==link and existing.originalOwner==resolvedOwner then dupe=true; break end
      end
      if not dupe then
        table.insert(activeRun.loot,{link=link,originalOwner=resolvedOwner,currentOwner=resolvedOwner,qty=qty or 1})
      end
    end
  end
end)

-- ═════════════════════════════ WINDOW ══════════════════════════════════════
local WIN_W,WIN_H=1150,700
local HDR_H=38; local TILE_H=88; local PANE_H=240; local GRAPH_H=nil
local LEFT_W=220; local RIGHT_W=270
local CENTER_W=WIN_W-LEFT_W-RIGHT_W-32

local function ClearFrame(f)
  for _,c in ipairs({f:GetChildren()}) do c:Hide(); c:SetParent(nil) end
  for _,r in ipairs({f:GetRegions()}) do r:Hide() end
end

local function MkBtn(par,txt,w,h,BD)
  local b=CreateFrame("Button",nil,par,"BackdropTemplate"); b:SetSize(w,h)
  b:SetBackdrop(BD); b:SetBackdropColor(0.04,0.04,0.07,1); b:SetBackdropBorderColor(0.12,0.12,0.20,1)
  local cut=b:CreateTexture(nil,"OVERLAY",nil,4); cut:SetSize(7,1); cut:SetPoint("TOPRIGHT",b,"TOPRIGHT",0,-1)
  do local _ar,_ag,_ab=NS.ChatGetAccentRGB(); cut:SetColorTexture(_ar,_ag,_ab,0.22) end
  local fs=b:CreateFontString(nil,"OVERLAY"); fs:SetFont("Fonts/FRIZQT__.TTF",10,""); fs:SetPoint("CENTER")
  fs:SetTextColor(0.72,0.72,0.82); fs:SetText(txt); b._lbl=fs
  b:SetScript("OnEnter",function() local ar,ag,ab=NS.ChatGetAccentRGB(); b:SetBackdropBorderColor(ar,ag,ab,0.9) end)
  b:SetScript("OnLeave",function() b:SetBackdropBorderColor(0.12,0.12,0.20,1) end)
  return b
end

local function MkPane(par)
  local sf=CreateFrame("ScrollFrame",nil,par,"UIPanelScrollFrameTemplate")
  if sf.ScrollBar then sf.ScrollBar:SetAlpha(0.4) end
  -- Reserve 18px on the right for the scrollbar so text doesn't overlap
  local sc=CreateFrame("Frame",nil,sf); sc:SetWidth(sf:GetWidth() or 200)
  sf:SetScrollChild(sc)
  sf:HookScript("OnSizeChanged",function(_,w) sc:SetWidth(math.max(50, w-18)) end)
  return sf,sc
end

local function BuildWindow()
  if MP.win then return end
  wipe(MP._accentTextures)  -- clear in case window is rebuilt
  local BD={bgFile="Interface/Buttons/WHITE8X8",edgeFile="Interface/Buttons/WHITE8X8",edgeSize=1}
  local ar,ag,ab=NS.ChatGetAccentRGB()

  MP.win=CreateFrame("Frame","LucidUIMPv2Win",UIParent,"BackdropTemplate")
  MP.win:SetSize(WIN_W,WIN_H); MP.win:SetPoint("CENTER",UIParent,"CENTER",0,0)
  MP.win:SetFrameStrata("MEDIUM"); MP.win:SetToplevel(true)
  MP.win:SetMovable(true); MP.win:SetClampedToScreen(true); MP.win:EnableMouse(true)
  MP.win:RegisterForDrag("LeftButton")
  MP.win:SetScript("OnDragStart",function(s) s:StartMoving() end)
  MP.win:SetScript("OnDragStop",function(s)
    s:StopMovingOrSizing(); local p,_,_,x,y=s:GetPoint(); NS.DBSet("mpWinPos3",{p=p,x=x,y=y})
  end)
  MP.win:SetScript("OnMouseDown",function(s) s:Raise() end)
  MP.win:SetBackdrop(BD); MP.win:SetBackdropColor(0.022,0.022,0.035,0.97)
  MP.win:SetBackdropBorderColor(ar,ag,ab,0.38); MP.win:Hide()
  C_Timer.After(0,function() if NS.DrawPCBBackground then MP.win._pcbTextures=NS.DrawPCBBackground(MP.win,WIN_W,WIN_H,HDR_H,0) end end)

  local pos=NS.DB("mpWinPos3")
  if pos and pos.p then MP.win:ClearAllPoints(); MP.win:SetPoint(pos.p,UIParent,pos.p,pos.x,pos.y) end

  -- Accent bar + header bg + line + corner cuts (standard LucidUI pattern)
  local lBar=MP.win:CreateTexture(nil,"OVERLAY",nil,5); lBar:SetWidth(3)
  lBar:SetPoint("TOPLEFT",1,-1); lBar:SetPoint("BOTTOMLEFT",1,1); lBar:SetColorTexture(ar,ag,ab,1)
  RegAccent(lBar,1)
  local hBg=MP.win:CreateTexture(nil,"BACKGROUND",nil,2)
  hBg:SetPoint("TOPLEFT",1,-1); hBg:SetPoint("TOPRIGHT",-1,-1); hBg:SetHeight(HDR_H); hBg:SetColorTexture(0.008,0.008,0.018,1)
  local hLine=MP.win:CreateTexture(nil,"OVERLAY",nil,5); hLine:SetHeight(1)
  hLine:SetPoint("TOPLEFT",1,-HDR_H); hLine:SetPoint("TOPRIGHT",-1,-HDR_H); hLine:SetColorTexture(ar,ag,ab,0.55)
  RegAccent(hLine,0.55)
  local function CutTex(x,y,w,h,a)
    local t=MP.win:CreateTexture(nil,"OVERLAY",nil,5); t:SetSize(w,h)
    t:SetPoint("TOPLEFT",MP.win,"TOPLEFT",x,-y); t:SetColorTexture(ar,ag,ab,a or 0.55)
    RegAccent(t,a or 0.55)
  end; CutTex(WIN_W-28,1,26,1,0.70); CutTex(WIN_W-2,1,1,16,0.70)

  -- Header: Title (left) | Score (center) | Stats (right of score)
  local hex=string.format("%02x%02x%02x",math.floor(ar*255),math.floor(ag*255),math.floor(ab*255))
  local titleFS=MP.win:CreateFontString(nil,"OVERLAY"); titleFS:SetFont("Fonts/FRIZQT__.TTF",14,"OUTLINE")
  titleFS:SetPoint("TOPLEFT",MP.win,"TOPLEFT",14,-7)
  titleFS:SetText("|cff"..hex.."MYTHIC+|r |cffffffffTRACKER|r")
  MP.win._titleFS = titleFS

  -- "M+ Rating" label above score
  local ratingLbl=MP.win:CreateFontString(nil,"OVERLAY"); ratingLbl:SetFont("Fonts/FRIZQT__.TTF",9,"OUTLINE")
  ratingLbl:SetPoint("TOP",MP.win,"TOP",0,-6); ratingLbl:SetTextColor(0.65,0.65,0.75); ratingLbl:SetText("M+ Rating")

  MP.win._scoreLbl=MP.win:CreateFontString(nil,"OVERLAY"); MP.win._scoreLbl:SetFont("Fonts/FRIZQT__.TTF",26,"OUTLINE")
  MP.win._scoreLbl:SetPoint("TOP",MP.win,"TOP",0,-14); MP.win._scoreLbl:SetTextColor(1,0.84,0)

  -- Stats shifted right so they clear the score
  MP.win._highestLbl=MP.win:CreateFontString(nil,"OVERLAY"); MP.win._highestLbl:SetFont("Fonts/FRIZQT__.TTF",12,"")
  MP.win._highestLbl:SetPoint("TOPLEFT",MP.win,"TOP",80,-6); MP.win._highestLbl:SetTextColor(0.88,0.88,0.95)

  MP.win._totalLbl=MP.win:CreateFontString(nil,"OVERLAY"); MP.win._totalLbl:SetFont("Fonts/FRIZQT__.TTF",10,"")
  MP.win._totalLbl:SetPoint("TOPLEFT",MP.win._highestLbl,"BOTTOMLEFT",0,-2); MP.win._totalLbl:SetTextColor(0.65,0.65,0.72)

  -- Alt + Season buttons (left side, after title)
  MP.win._altBtn=MkBtn(MP.win,"Player",110,20,BD); MP.win._altBtn:SetPoint("TOPLEFT",MP.win,"TOPLEFT",160,-10)
  MP.win._seasonBtn=MkBtn(MP.win,"Season",120,20,BD); MP.win._seasonBtn:SetPoint("LEFT",MP.win._altBtn,"RIGHT",5,0)
  local resetBtn=MkBtn(MP.win,"Reset Filters",90,20,BD); resetBtn:SetPoint("LEFT",MP.win._seasonBtn,"RIGHT",5,0)
  resetBtn:SetScript("OnClick",function() MP._filterMap=nil; MP._filterPlayer=nil; MP._selRun=nil; MP.Refresh() end)

  -- Close button
  local closeBtn=CreateFrame("Button",nil,MP.win,"BackdropTemplate"); closeBtn:SetSize(22,22)
  closeBtn:SetPoint("TOPRIGHT",-4,-8); closeBtn:SetBackdrop(BD)
  closeBtn:SetBackdropColor(0.09,0.02,0.02,1); closeBtn:SetBackdropBorderColor(0.34,0.09,0.09,1)
  local cX=closeBtn:CreateFontString(nil,"OVERLAY"); cX:SetFont("Fonts/FRIZQT__.TTF",11,""); cX:SetPoint("CENTER")
  cX:SetTextColor(0.60,0.18,0.18); cX:SetText("X")
  closeBtn:SetScript("OnEnter",function() closeBtn:SetBackdropBorderColor(0.82,0.16,0.16,1); cX:SetTextColor(1,0.3,0.3) end)
  closeBtn:SetScript("OnLeave",function() closeBtn:SetBackdropBorderColor(0.34,0.09,0.09,1); cX:SetTextColor(0.60,0.18,0.18) end)
  closeBtn:SetScript("OnClick",function() MP.win:Hide() end)

  -- Sync + Clear buttons (right of alt/season)
  local syncBtn=MkBtn(MP.win,"Sync",60,20,BD); syncBtn:SetPoint("TOPRIGHT",MP.win,"TOPRIGHT",-125,-10)
  syncBtn:SetScript("OnClick",function() MP.SyncBlizzard(MP._selAlt,MP._selSeason); MP.Refresh() end)
  local clearBtn=MkBtn(MP.win,"Clear All",70,20,BD); clearBtn:SetPoint("LEFT",syncBtn,"RIGHT",4,0)
  clearBtn:SetScript("OnClick",function()
    StaticPopupDialogs["LUCIDUI_MP3_CLEAR"]={text="Clear Mythic+ history?",button1=ACCEPT,button2=CANCEL,
      OnAccept=function() local db=GetDB(); if db[MP._selAlt] then db[MP._selAlt][MP._selSeason]={} end; MP._selRun=nil; MP.Refresh() end,
      timeout=0,whileDead=true,hideOnEscape=true,preferredIndex=3}; StaticPopup_Show("LUCIDUI_MP3_CLEAR")
  end)

  -- Tile row
  local tileRow=CreateFrame("Frame",nil,MP.win)
  tileRow:SetPoint("TOPLEFT",4,-(HDR_H+1)); tileRow:SetPoint("TOPRIGHT",-1,-(HDR_H+1)); tileRow:SetHeight(TILE_H)
  local tileBg=tileRow:CreateTexture(nil,"BACKGROUND"); tileBg:SetAllPoints(); tileBg:SetColorTexture(0.010,0.010,0.018,1)
  local tileLine=tileRow:CreateTexture(nil,"OVERLAY",nil,3); tileLine:SetHeight(1)
  tileLine:SetPoint("BOTTOMLEFT"); tileLine:SetPoint("BOTTOMRIGHT"); tileLine:SetColorTexture(ar,ag,ab,0.22)
  RegAccent(tileLine,0.22)
  MP.win._tileRow=tileRow; MP.win._tiles={}

  -- Body: 3-pane layout
  local bodyY=HDR_H+TILE_H+4
  -- Separator line between tiles and body panes
  local paneTopLine=MP.win:CreateTexture(nil,"OVERLAY",nil,3); paneTopLine:SetHeight(1)
  paneTopLine:SetPoint("TOPLEFT",MP.win,"TOPLEFT",0,-bodyY)
  paneTopLine:SetPoint("TOPRIGHT",MP.win,"TOPRIGHT",0,-bodyY)
  paneTopLine:SetColorTexture(ar,ag,ab,0.30)
  RegAccent(paneTopLine,0.30)
  -- Pane labels
  local function PaneLabel(txt,xOff,width)
    local fs=MP.win:CreateFontString(nil,"OVERLAY"); fs:SetFont("Fonts/FRIZQT__.TTF",9,"OUTLINE")
    fs:SetPoint("TOPLEFT",MP.win,"TOPLEFT",xOff,-bodyY); fs:SetWidth(width)
    fs:SetTextColor(1,0.82,0); fs:SetText(txt)
    -- Dashed underline (4 segments matching main settings card style)
    local segW,segH,segGap=18,1,6
    for si=0,3 do
      local seg=MP.win:CreateTexture(nil,"OVERLAY",nil,3); seg:SetSize(segW,segH)
      seg:SetPoint("TOPLEFT",MP.win,"TOPLEFT",xOff+si*(segW+segGap),-(bodyY+12))
      seg:SetColorTexture(ar,ag,ab,0.18)
      RegAccent(seg,0.18)
    end
    MP._goldLabels = MP._goldLabels or {}
    table.insert(MP._goldLabels, fs)
  end
  PaneLabel("PLAYERS",8,LEFT_W); PaneLabel("RUN HISTORY",LEFT_W+14,CENTER_W)
  PaneLabel("RUN DETAILS",LEFT_W+CENTER_W+20,RIGHT_W)
  -- Vertical dividers
  local function VDiv(x)
    local vl=MP.win:CreateTexture(nil,"OVERLAY",nil,3); vl:SetWidth(1)
    vl:SetPoint("TOPLEFT",MP.win,"TOPLEFT",x,-bodyY); vl:SetPoint("BOTTOMLEFT",MP.win,"BOTTOMLEFT",x,28)
    vl:SetColorTexture(ar,ag,ab,0.18)
    RegAccent(vl,0.18)
  end; VDiv(LEFT_W+10); VDiv(LEFT_W+CENTER_W+16)

  local anaSF,anaSC=MkPane(MP.win)
  anaSF:SetPoint("TOPLEFT",MP.win,"TOPLEFT",5,-(bodyY+16))
  anaSF:SetPoint("BOTTOMRIGHT",MP.win,"TOPLEFT",LEFT_W+5,-(bodyY+PANE_H+16))
  if anaSF.ScrollBar then
    anaSF.ScrollBar:ClearAllPoints()
    anaSF.ScrollBar:SetPoint("TOPRIGHT",    anaSF,"TOPRIGHT",    -1, 0)
    anaSF.ScrollBar:SetPoint("BOTTOMRIGHT", anaSF,"BOTTOMRIGHT", -1, 0)
  end
  MP.win._anaSC=anaSC

  local histSF,histSC=MkPane(MP.win)
  histSF:SetPoint("TOPLEFT",MP.win,"TOPLEFT",LEFT_W+12,-(bodyY+16))
  histSF:SetPoint("BOTTOMRIGHT",MP.win,"TOPLEFT",LEFT_W+CENTER_W+10,-(bodyY+PANE_H+16))
  if histSF.ScrollBar then
    histSF.ScrollBar:ClearAllPoints()
    histSF.ScrollBar:SetPoint("TOPRIGHT",    histSF,"TOPRIGHT",    -1, 0)
    histSF.ScrollBar:SetPoint("BOTTOMRIGHT", histSF,"BOTTOMRIGHT", -1, 0)
  end
  MP.win._histSC=histSC

  local detSF,detSC=MkPane(MP.win)
  -- Run Details fills the full right column (from body top to above footer buttons)
  detSF:SetPoint("TOPLEFT",MP.win,"TOPLEFT",LEFT_W+CENTER_W+18,-(bodyY+16))
  detSF:SetPoint("BOTTOMRIGHT",MP.win,"BOTTOMRIGHT",-4,28)
  if detSF.ScrollBar then
    detSF.ScrollBar:ClearAllPoints()
    detSF.ScrollBar:SetPoint("TOPRIGHT",    detSF,"TOPRIGHT",    -1,  0)
    detSF.ScrollBar:SetPoint("BOTTOMRIGHT", detSF,"BOTTOMRIGHT", -1,  0)
  end
  MP.win._detSC=detSC

  -- Graph area
  local gY=bodyY+PANE_H+22
  local gHdr=MP.win:CreateFontString(nil,"OVERLAY"); gHdr:SetFont("Fonts/FRIZQT__.TTF",9,"OUTLINE")
  gHdr:SetPoint("LEFT",MP.win,"LEFT",0,-gY); gHdr:SetPoint("RIGHT",MP.win,"RIGHT",0,-gY)
  gHdr:SetJustifyH("CENTER"); gHdr:SetTextColor(1,0.82,0); gHdr:SetText("KEY LEVEL CHART  — Best timed runs per dungeon")
  MP._goldLabels = MP._goldLabels or {}
  table.insert(MP._goldLabels, gHdr)
  local gHolder=CreateFrame("Frame",nil,MP.win)
  gHolder:SetPoint("TOPLEFT",MP.win,"TOPLEFT",5,-(gY+14)); gHolder:SetPoint("BOTTOMRIGHT",MP.win,"BOTTOMRIGHT",-5,52)
  local gBg=gHolder:CreateTexture(nil,"BACKGROUND"); gBg:SetAllPoints(); gBg:SetColorTexture(0.010,0.010,0.018,1)
  local gTopLine=gHolder:CreateTexture(nil,"OVERLAY",nil,3); gTopLine:SetHeight(1)
  gTopLine:SetPoint("TOPLEFT"); gTopLine:SetPoint("TOPRIGHT"); gTopLine:SetColorTexture(ar,ag,ab,0.20)
  RegAccent(gTopLine,0.20)
  MP.win._gHolder=gHolder

  -- Footer checkboxes + buttons
  local maskCB=NS.ChatGetCheckbox(MP.win,"Mask Names",18,function(s) MP._maskNames=s; MP.Refresh() end,"Anonymise player names to first 3 letters")
  maskCB:ClearAllPoints(); maskCB:SetHeight(18); maskCB:SetPoint("BOTTOMLEFT",MP.win,"BOTTOMLEFT",120,6)
  local failCB=NS.ChatGetCheckbox(MP.win,"Hide Fails",18,function(s) MP._hideFails=s; MP.Refresh() end,"Hide depleted/abandoned runs from history")
  failCB:ClearAllPoints(); failCB:SetHeight(18); failCB:SetPoint("LEFT",maskCB,"RIGHT",20,0)

  MP.win._BD=BD
  MP.win._altBtn:SetScript("OnClick",function(s) MP._OpenAltMenu(s) end)
  MP.win._seasonBtn:SetScript("OnClick",function(s) MP._OpenSeasonMenu(s) end)
end

-- Alt/Season dropdowns
function MP._OpenAltMenu(anchor)
  local db=GetDB(); local opts={[GetPlayerKey()]=true}
  for k in pairs(db) do opts[k]=true end
  local list={}; for k in pairs(opts) do table.insert(list,k) end; table.sort(list)
  MenuUtil.CreateContextMenu(anchor,function(_,root) for _,k in ipairs(list) do
    root:CreateButton(k==MP._selAlt and ("|cff00ff00> "..k.."|r") or k,function()
      MP._selAlt=k; MP._filterMap=nil; MP._filterPlayer=nil; MP._selRun=nil
      MP.win._altBtn._lbl:SetText(k:match("^([^%-]+)") or k); MP.Refresh() end)
  end end)
end
function MP._OpenSeasonMenu(anchor)
  local opts={}; for sID,sData in pairs(MP.Seasons) do table.insert(opts,{id=sID,name=sData.name}) end
  table.sort(opts,function(a,b) return a.id>b.id end)
  MenuUtil.CreateContextMenu(anchor,function(_,root) for _,s in ipairs(opts) do
    root:CreateButton(s.id==MP._selSeason and ("|cff00ff00> "..s.name.."|r") or s.name,function()
      MP._selSeason=s.id; MP._filterMap=nil; MP._filterPlayer=nil; MP._selRun=nil
      MP.win._seasonBtn._lbl:SetText(s.name); MP.Refresh() end)
  end end)
end

-- ─── Tiles (GLogger approach: reuse frames, SetDesaturated for filter state)
local function BuildSortedDungeons(seasonData)
  local sorted={}
  for id,d in pairs(seasonData.dungeons) do
    local name=C_ChallengeMode.GetMapUIInfo(id) or d.name
    table.insert(sorted,{id=id,abbr=d.abbr,name=name,texture=d.texture})
  end
  table.sort(sorted,function(a,b) return a.abbr<b.abbr end)
  return sorted
end

local function DrawTiles(seasonData,runs)
  local tr=MP.win._tileRow
  if not seasonData or not seasonData.dungeons then
    for _,t in ipairs(MP.win._tiles) do t:Hide() end; return
  end

  local sorted=BuildSortedDungeons(seasonData)
  local N=#sorted; if N==0 then return end

  local SPACING=10
  local TW=(tr:GetWidth()-SPACING*(N-1))/N

  -- Best per dungeon (local DB)
  local bestLv,bestSc={},{}
  if runs then
    for _,r in ipairs(runs) do
      local mid=r.mapID; local sc=r.mapScore or 0; local lv=r.level or 0
      if not bestSc[mid] or sc>bestSc[mid] then bestSc[mid]=sc; bestLv[mid]=lv
      elseif sc==bestSc[mid] and lv>bestLv[mid] then bestLv[mid]=lv end
    end
  end
  -- Blizzard API (current season / current player)
  if MP._selAlt==GetPlayerKey() and MP._selSeason==GetCurrentSeason() then
    for _,d in ipairs(sorted) do
      local inT,ovT=C_MythicPlus.GetSeasonBestForMap(d.id)
      local apiSc,apiLv=0,0
      if inT and (inT.level or 0)>0 then apiSc=inT.dungeonScore or 0; apiLv=inT.level end
      if apiSc==0 and ovT and (ovT.level or 0)>0 then apiSc=ovT.dungeonScore or 0; apiLv=ovT.level end
      if apiSc>(bestSc[d.id] or 0) then bestSc[d.id]=apiSc; bestLv[d.id]=apiLv
      elseif apiSc==(bestSc[d.id] or 0) and apiLv>(bestLv[d.id] or 0) then bestLv[d.id]=apiLv end
    end
  end

  local currentLiveSeason=GetCurrentSeason()

  for i,d in ipairs(sorted) do
    -- REUSE existing tile frame if available (GLogger pattern)
    local tile=MP.win._tiles[i]
    if not tile then
      tile=CreateFrame("Button",nil,tr)

      tile.bg=tile:CreateTexture(nil,"BACKGROUND")
      tile.bg:SetAllPoints(); tile.bg:SetTexCoord(0.01,0.99,0.01,0.99)

      tile.overlay=tile:CreateTexture(nil,"BORDER")
      tile.overlay:SetAllPoints(); tile.overlay:SetColorTexture(0,0,0,0.65)

      tile.highlight=tile:CreateTexture(nil,"OVERLAY")
      tile.highlight:SetAllPoints(); tile.highlight:SetColorTexture(1,0.82,0,0.3); tile.highlight:Hide()

      tile.border=CreateFrame("Frame",nil,tile,"BackdropTemplate"); tile.border:SetAllPoints()
      tile.border:SetBackdrop({edgeFile="Interface/Buttons/WHITE8X8",edgeSize=2})
      tile.border:SetBackdropBorderColor(1,0.82,0,1); tile.border:Hide()

      tile.abbrFS=tile:CreateFontString(nil,"OVERLAY"); tile.abbrFS:SetFont("Fonts/FRIZQT__.TTF",18,"OUTLINE")
      tile.abbrFS:SetPoint("TOP",tile,"TOP",0,-4); tile.abbrFS:SetTextColor(1,0.82,0)

      tile.lvlFS=tile:CreateFontString(nil,"OVERLAY"); tile.lvlFS:SetFont("Fonts/FRIZQT__.TTF",20,"OUTLINE")
      tile.lvlFS:SetPoint("CENTER",tile,"CENTER",0,2)

      tile.scFS=tile:CreateFontString(nil,"OVERLAY"); tile.scFS:SetFont("Fonts/FRIZQT__.TTF",13,"OUTLINE")
      tile.scFS:SetPoint("BOTTOM",tile,"BOTTOM",0,20)

      tile.nameFS=tile:CreateFontString(nil,"OVERLAY"); tile.nameFS:SetFont("Fonts/FRIZQT__.TTF",9,"")
      tile.nameFS:SetPoint("BOTTOM",tile,"BOTTOM",0,4); tile.nameFS:SetTextColor(1,0.82,0)
      tile.nameFS:SetJustifyH("CENTER")

      MP.win._tiles[i]=tile
    end

    -- Size & position
    tile:SetSize(TW,TILE_H-4)
    tile:SetPoint("LEFT",tr,"LEFT",(i-1)*(TW+SPACING),0)
    tile.nameFS:SetWidth(TW-6)

    -- Texture: 4th return value from GetMapUIInfo (WoW 12.x)
    local _,_,_,apiTex=C_ChallengeMode.GetMapUIInfo(d.id)
    local tex=apiTex or d.texture   -- fallback to hardcoded FileDataID
    if tex then
      tile.bg:SetTexture(tex)
    end

    tile.abbrFS:SetText(d.abbr)
    tile.nameFS:SetText(d.name)

    -- Count runs for this dungeon
    local runCount=0
    if runs then for _,r in ipairs(runs) do if r.mapID==d.id then runCount=runCount+1 end end end

    local lv=bestLv[d.id] or 0; local sc=bestSc[d.id] or 0

    -- Filter/saturation state (exact GLogger logic)
    if MP._filterMap then
      if MP._filterMap==d.id then
        tile.bg:SetDesaturated(false); tile.overlay:SetAlpha(0.2)
        tile.highlight:Show(); tile.border:Show()
      else
        tile.bg:SetDesaturated(true); tile.overlay:SetAlpha(0.85)
        tile.highlight:Hide(); tile.border:Hide()
      end
    else
      tile.highlight:Hide(); tile.border:Hide()
      if runCount>0 or sc>0 then
        tile.bg:SetDesaturated(false); tile.overlay:SetAlpha(0.6)
      else
        tile.bg:SetDesaturated(true); tile.overlay:SetAlpha(0.85)
      end
    end

    -- Level / score labels
    if lv>0 then
      tile.lvlFS:SetText("+"..lv)
      local cr,cg,cb=1,1,1
      if sc>0 and C_ChallengeMode.GetDungeonScoreRarityColor then
        local co=C_ChallengeMode.GetDungeonScoreRarityColor(sc); if co then cr,cg,cb=co.r,co.g,co.b end
      end
      tile.lvlFS:SetTextColor(cr,cg,cb)
      tile.scFS:SetText(tostring(math.floor(sc+0.5))); tile.scFS:SetTextColor(cr,cg,cb); tile.scFS:Show()
    elseif runCount>0 then
      tile.lvlFS:SetText("--"); tile.lvlFS:SetTextColor(0.6,0.6,0.6); tile.scFS:Hide()
    else
      tile.lvlFS:SetText(""); tile.scFS:Hide()
    end

    local capID=d.id; local capName=d.name
    tile:SetScript("OnClick",function()
      MP._filterMap=(MP._filterMap==capID) and nil or capID; MP._selRun=nil; MP.Refresh()
    end)
    tile:SetScript("OnEnter",function(self2)
      if MP._filterMap~=capID then tile.highlight:Show(); tile.border:Show() end
      GameTooltip:SetOwner(self2,"ANCHOR_TOP")
      GameTooltip:SetText(capName,1,1,1)
      GameTooltip:AddLine("Click to filter by this dungeon",0.7,0.7,0.7)
      GameTooltip:Show()
    end)
    tile:SetScript("OnLeave",function()
      if MP._filterMap~=capID then tile.highlight:Hide(); tile.border:Hide() end
      GameTooltip:Hide()
    end)
    tile:Show()
  end
  -- Hide excess tiles
  for i=N+1,#MP.win._tiles do if MP.win._tiles[i] then MP.win._tiles[i]:Hide() end end
end


-- ─── Analytics pane ───────────────────────────────────────────────────────
local function DrawAnalytics(teammates)
  local sc=MP.win._anaSC; ClearFrame(sc)
  local ar,ag,ab=NS.ChatGetAccentRGB(); local BD=MP.win._BD; local yOff=0; local ROW=22
  local hdr=CreateFrame("Frame",nil,sc,"BackdropTemplate"); hdr:SetHeight(ROW)
  hdr:SetPoint("TOPLEFT",sc,"TOPLEFT",0,-yOff); hdr:SetPoint("TOPRIGHT",sc,"TOPRIGHT",0,-yOff)
  hdr:SetBackdrop(BD); hdr:SetBackdropColor(0.015,0.015,0.025,1); hdr:SetBackdropBorderColor(ar,ag,ab,0.22)
  local h1=hdr:CreateFontString(nil,"OVERLAY"); h1:SetFont("Fonts/FRIZQT__.TTF",9,"OUTLINE")
  h1:SetPoint("LEFT",hdr,"LEFT",4,0); h1:SetTextColor(ar,ag,ab); h1:SetText("Player")
  local h2=hdr:CreateFontString(nil,"OVERLAY"); h2:SetFont("Fonts/FRIZQT__.TTF",9,"OUTLINE")
  h2:SetPoint("RIGHT",hdr,"RIGHT",-4,0); h2:SetTextColor(ar,ag,ab); h2:SetText("Runs")
  yOff=yOff+ROW+2
  if #teammates==0 then sc:SetHeight(40)
    local fs=sc:CreateFontString(nil,"OVERLAY"); fs:SetFont("Fonts/FRIZQT__.TTF",10,""); fs:SetPoint("TOP",sc,"TOP",0,-yOff)
    fs:SetTextColor(0.35,0.35,0.45); fs:SetText("No teammates yet"); return end
  for _,tm in ipairs(teammates) do
    local row=CreateFrame("Button",nil,sc,"BackdropTemplate"); row:SetHeight(ROW)
    row:SetPoint("TOPLEFT",sc,"TOPLEFT",0,-yOff); row:SetPoint("TOPRIGHT",sc,"TOPRIGHT",0,-yOff)
    row:SetBackdrop(BD); row:SetBackdropBorderColor(0.06,0.06,0.10,1)
    local isAct=(MP._filterPlayer==tm.rawName)
    if isAct then row:SetBackdropColor(ar*0.15,ag*0.15,ab*0.15,1) else row:SetBackdropColor(0.03,0.03,0.05,1) end
    local hex=ClassHex(tm.class); local disp=tm.rawName
    if MP._maskNames then local sh=disp:match("^([^%-]+)"); disp=(sh and sh:sub(1,3).."***" or disp) end
    local nFS=row:CreateFontString(nil,"OVERLAY"); nFS:SetFont("Fonts/FRIZQT__.TTF",10,"")
    nFS:SetPoint("LEFT",row,"LEFT",4,0); nFS:SetText("|c"..hex..disp.."|r")
    local cFS=row:CreateFontString(nil,"OVERLAY"); cFS:SetFont("Fonts/FRIZQT__.TTF",10,"")
    cFS:SetPoint("RIGHT",row,"RIGHT",-4,0); cFS:SetTextColor(0.72,0.72,0.82); cFS:SetText(tostring(tm.count))
    local cap=tm.rawName
    row:SetScript("OnClick",function() MP._filterPlayer=(MP._filterPlayer==cap) and nil or cap; MP._selRun=nil; MP.Refresh() end)
    row:SetScript("OnEnter",function() row:SetBackdropColor(ar*0.12,ag*0.12,ab*0.12,1)
      GameTooltip:SetOwner(row,"ANCHOR_RIGHT"); GameTooltip:SetText("Click to filter by this player",1,1,1); GameTooltip:Show() end)
    row:SetScript("OnLeave",function()
      if MP._filterPlayer==cap then row:SetBackdropColor(ar*0.15,ag*0.15,ab*0.15,1) else row:SetBackdropColor(0.03,0.03,0.05,1) end
      GameTooltip:Hide() end)
    yOff=yOff+ROW+2
  end; sc:SetHeight(yOff+4)
end

-- ─── History table ─────────────────────────────────────────────────────────
local function DrawHistory(runs,bestDates)
  local sc=MP.win._histSC; ClearFrame(sc)
  local ar,ag,ab=NS.ChatGetAccentRGB(); local BD=MP.win._BD; local yOff=0; local ROW=26
  local CW={95,160,44,58,66,40}
  local hdr=CreateFrame("Frame",nil,sc,"BackdropTemplate"); hdr:SetHeight(20)
  hdr:SetPoint("TOPLEFT",sc,"TOPLEFT",0,-yOff); hdr:SetPoint("TOPRIGHT",sc,"TOPRIGHT",0,-yOff)
  hdr:SetBackdrop(BD); hdr:SetBackdropColor(0.015,0.015,0.025,1); hdr:SetBackdropBorderColor(ar,ag,ab,0.22)
  local xc=3
  for i,col in ipairs({"Date","Dungeon","+Lvl","Time","Status","Deaths"}) do
    local fs=hdr:CreateFontString(nil,"OVERLAY"); fs:SetFont("Fonts/FRIZQT__.TTF",10,"OUTLINE")
    fs:SetPoint("LEFT",hdr,"LEFT",xc,0); fs:SetTextColor(ar,ag,ab); fs:SetText(col); xc=xc+CW[i] end
  yOff=yOff+20+2
  if #runs==0 then sc:SetHeight(40)
    local fs=sc:CreateFontString(nil,"OVERLAY"); fs:SetFont("Fonts/FRIZQT__.TTF",10,""); fs:SetPoint("TOP",sc,"TOP",0,-yOff)
    fs:SetTextColor(0.35,0.35,0.45); fs:SetText("No runs match the current filters"); return end
  for _,run in ipairs(runs) do
    local row=CreateFrame("Button",nil,sc,"BackdropTemplate"); row:SetHeight(ROW)
    row:SetPoint("TOPLEFT",sc,"TOPLEFT",0,-yOff); row:SetPoint("TOPRIGHT",sc,"TOPRIGHT",0,-yOff)
    row:SetBackdrop(BD); row:SetBackdropBorderColor(0.06,0.06,0.10,1)
    local isAct=(MP._selRun and MP._selRun.date==run.date)
    if isAct then row:SetBackdropColor(ar*0.12,ag*0.12,ab*0.12,1) else row:SetBackdropColor(0.028,0.028,0.046,1) end
    local sr,sg,sb=SC(run.status)
    local sBar=row:CreateTexture(nil,"OVERLAY",nil,5); sBar:SetWidth(2); sBar:SetPoint("TOPLEFT"); sBar:SetPoint("BOTTOMLEFT"); sBar:SetColorTexture(sr,sg,sb,1)
    local xc2=4
    local isBest=bestDates and bestDates[run.date]
    local dTxt=(isBest and "|TInterface/WorldMap/Skull_64:11:11|t " or "")..date("%d.%m.%y %H:%M",run.date)
    local dFS=row:CreateFontString(nil,"OVERLAY"); dFS:SetFont("Fonts/FRIZQT__.TTF",10,""); dFS:SetPoint("LEFT",row,"LEFT",xc2,0); dFS:SetTextColor(0.50,0.50,0.62); dFS:SetText(dTxt); xc2=xc2+CW[1]
    local nFS=row:CreateFontString(nil,"OVERLAY"); nFS:SetFont("Fonts/FRIZQT__.TTF",10,""); nFS:SetPoint("LEFT",row,"LEFT",xc2,0); nFS:SetTextColor(0.88,0.88,0.94); nFS:SetText(run.mapName or "?"); xc2=xc2+CW[2]
    local lFS=row:CreateFontString(nil,"OVERLAY"); lFS:SetFont("Fonts/FRIZQT__.TTF",11,"OUTLINE"); lFS:SetPoint("LEFT",row,"LEFT",xc2,0); lFS:SetTextColor(sr,sg,sb); lFS:SetText("+"..tostring(run.level or 0)); xc2=xc2+CW[3]
    local tFS=row:CreateFontString(nil,"OVERLAY"); tFS:SetFont("Fonts/FRIZQT__.TTF",10,""); tFS:SetPoint("LEFT",row,"LEFT",xc2,0); tFS:SetTextColor(0.70,0.70,0.82); tFS:SetText(FmtTime(run.timeElapsed)); xc2=xc2+CW[4]
    local stFS=row:CreateFontString(nil,"OVERLAY"); stFS:SetFont("Fonts/FRIZQT__.TTF",10,"OUTLINE"); stFS:SetPoint("LEFT",row,"LEFT",xc2,0); stFS:SetTextColor(sr,sg,sb); stFS:SetText(ST(run.status)); xc2=xc2+CW[5]
    local d2=(run.deaths or 0); local dtFS=row:CreateFontString(nil,"OVERLAY"); dtFS:SetFont("Fonts/FRIZQT__.TTF",10,""); dtFS:SetPoint("LEFT",row,"LEFT",xc2,0)
    dtFS:SetTextColor(d2>0 and 0.85 or 0.40,d2>0 and 0.25 or 0.40,d2>0 and 0.25 or 0.40); dtFS:SetText(d2>0 and tostring(d2) or "—")
    local capRun=run
    row:SetScript("OnClick",function() MP._selRun=(MP._selRun and MP._selRun.date==capRun.date) and nil or capRun; MP.Refresh() end)
    row:SetScript("OnEnter",function() row:SetBackdropColor(ar*0.12,ag*0.12,ab*0.12,1)
      GameTooltip:SetOwner(row,"ANCHOR_LEFT"); GameTooltip:SetText("Click to view run details",1,1,1); GameTooltip:Show() end)
    row:SetScript("OnLeave",function()
      if MP._selRun and MP._selRun.date==capRun.date then row:SetBackdropColor(ar*0.12,ag*0.12,ab*0.12,1)
      else row:SetBackdropColor(0.028,0.028,0.046,1) end; GameTooltip:Hide() end)
    yOff=yOff+ROW+2
  end; sc:SetHeight(yOff+4)
end

-- ─── Run details ───────────────────────────────────────────────────────────
local function DrawDetails(run)
  local sc=MP.win._detSC; ClearFrame(sc)
  local ar,ag,ab=NS.ChatGetAccentRGB(); local yOff=6
  local function FS(txt,size,r,g,b,xi) local f=sc:CreateFontString(nil,"OVERLAY"); f:SetFont("Fonts/FRIZQT__.TTF",size or 10,"")
    f:SetPoint("TOPLEFT",sc,"TOPLEFT",(xi or 5),-yOff); f:SetTextColor(r or 0.85,g or 0.85,b or 0.92); f:SetText(txt)
    yOff=yOff+(size or 10)+7; return f end
  local function Div() local d=sc:CreateTexture(nil,"ARTWORK"); d:SetHeight(1); d:SetColorTexture(ar,ag,ab,0.25)
    d:SetPoint("TOPLEFT",sc,"TOPLEFT",0,-yOff); d:SetPoint("TOPRIGHT",sc,"TOPRIGHT",0,-yOff); yOff=yOff+8 end
  if not run then sc:SetHeight(60)
    FS("Select a run to view details",10,0.40,0.40,0.50); return end
  local sr,sg,sb=SC(run.status)
  FS(string.format("%s  +%d", run.mapName or "?", run.level or 0), 13, sr,sg,sb)
  if (run.mapScore or 0)>0 then
    local sc2n=math.floor(run.mapScore+0.5); local cr,cg,cb=1,0.84,0
    if C_ChallengeMode.GetDungeonScoreRarityColor then local co=C_ChallengeMode.GetDungeonScoreRarityColor(run.mapScore); if co then cr,cg,cb=co.r,co.g,co.b end end
    FS("Score: "..tostring(sc2n), 11, cr,cg,cb) end
  FS(date("%Y-%m-%d  %H:%M",run.date or 0), 10, 0.50,0.50,0.62)
  FS(string.format("Time: %s / %s  (%s)",FmtTime(run.timeElapsed),FmtTime(run.timeLimit),ST(run.status)),10,sr,sg,sb)
  local dStr=tostring(run.deaths or 0)
  if (run.deaths or 0)>0 and (run.timeLost or 0)>0 then dStr=dStr.."  (-"..FmtTime(run.timeLost)..")" end
  FS("Deaths: "..dStr, 10, (run.deaths or 0)>0 and 0.90 or 0.48, (run.deaths or 0)>0 and 0.25 or 0.52, 0.25)
  if run.affixes and #run.affixes>0 then
    yOff=yOff+4; FS("Affixes:", 10, 0.80,0.80,0.90)
    for _,affID in ipairs(run.affixes) do local nm,_,fid=C_ChallengeMode.GetAffixInfo(affID)
      local ico=fid and ("|T"..fid..":12:12:0:0:64:64:4:60:4:60|t ") or ""
      FS(ico..(nm or ("Affix "..affID)), 10, 0.72,0.72,0.85, 12) end end
  -- Roster
  if run.roster and next(run.roster) then
    yOff=yOff+8; Div(); FS("ROSTER", 9, ar,ag,ab)
    local RORD={TANK=1,HEALER=2,DAMAGER=3}
    local roster={}; for nm,d in pairs(run.roster) do table.insert(roster,{name=nm,class=d.class,role=d.role}) end
    table.sort(roster,function(a,b) return (RORD[a.role] or 4)<(RORD[b.role] or 4) end)
    local RI={TANK="|TInterface\LFGFrame\UI-LFG-ICON-PORTRAITROLES:13:13:0:0:64:64:0:19:22:41|t",
              HEALER="|TInterface\LFGFrame\UI-LFG-ICON-PORTRAITROLES:13:13:0:0:64:64:20:39:1:20|t",
              DAMAGER="|TInterface\LFGFrame\UI-LFG-ICON-PORTRAITROLES:13:13:0:0:64:64:20:39:22:41|t"}
    for _,p in ipairs(roster) do local hex=ClassHex(p.class); local disp=p.name
      if MP._maskNames then local sh=disp:match("^([^%-]+)"); disp=(sh and sh:sub(1,3).."***" or disp) end
      FS((RI[p.role] or RI.DAMAGER).." |c"..hex..disp.."|r", 10, 0.85,0.85,0.92, 5) end end
  -- Loot
  if run.loot and #run.loot>0 then
    yOff=yOff+8; Div(); FS("LOOT", 9, ar,ag,ab)
    for _,item in ipairs(run.loot) do FS(item.link or "?", 10, 0.85,0.85,0.92, 5)
      local own=item.currentOwner or "?"
      if MP._maskNames then local sh=own:match("^([^%-]+)"); own=(sh and sh:sub(1,3).."***" or own) end
      FS("  → "..own, 9, 0.50,0.50,0.62) end end
  -- Delete button
  local delBtn=CreateFrame("Button",nil,sc,"BackdropTemplate"); delBtn:SetSize(68,18)
  delBtn:SetPoint("TOPRIGHT",sc,"TOPRIGHT",-3,-3); local BD2=MP.win._BD
  delBtn:SetBackdrop(BD2); delBtn:SetBackdropColor(0.08,0.02,0.02,1); delBtn:SetBackdropBorderColor(0.28,0.08,0.08,1)
  local dLbl=delBtn:CreateFontString(nil,"OVERLAY"); dLbl:SetFont("Fonts/FRIZQT__.TTF",9,""); dLbl:SetPoint("CENTER")
  dLbl:SetTextColor(0.65,0.18,0.18); dLbl:SetText("Delete Run")
  delBtn:SetScript("OnEnter",function() delBtn:SetBackdropBorderColor(1,0.25,0.25,1); dLbl:SetTextColor(1,0.35,0.35) end)
  delBtn:SetScript("OnLeave",function() delBtn:SetBackdropBorderColor(0.28,0.08,0.08,1); dLbl:SetTextColor(0.65,0.18,0.18) end)
  local capRun=run; delBtn:SetScript("OnClick",function()
    StaticPopupDialogs["LUCIDUI_MP_DELRUN"]={
      text="Delete this run from history?", button1=ACCEPT, button2=CANCEL,
      OnAccept=function()
        local db=GetDB(); local k=MP._selAlt; local s=MP._selSeason
        if db[k] and db[k][s] then for i,r in ipairs(db[k][s]) do if r==capRun then table.remove(db[k][s],i); break end end end
        MP._selRun=nil; MP.Refresh()
      end, timeout=0, whileDead=true, hideOnEscape=true, preferredIndex=3,
    }; StaticPopup_Show("LUCIDUI_MP_DELRUN")
  end)
  sc:SetHeight(math.max(yOff+10,60))
end

-- ─── Graph ─────────────────────────────────────────────────────────────────
local function DrawGraph(runs,seasonData)
  local holder=MP.win._gHolder; ClearFrame(holder)
  if not runs or #runs==0 then return end
  local ar,ag,ab=NS.ChatGetAccentRGB()
  local W=holder:GetWidth() or 1100; local H=holder:GetHeight() or 120
  local PL,PR,PT,PB=38,8,8,30; local CW2=W-PL-PR; local CH=math.min(H-PT-PB, 120)
  -- Build graph data: best timed per dungeon (max 3 per dungeon), or all timed if filtered
  local graphRuns={}
  if not MP._filterMap then
    local grouped={}; for _,r in ipairs(runs) do
      if SR(r.status)>=3 then if not grouped[r.mapID] then grouped[r.mapID]={} end; table.insert(grouped[r.mapID],r) end end
    for _,grp in pairs(grouped) do
      table.sort(grp,function(a,b) if a.level~=b.level then return a.level>b.level end; return SR(a.status)>SR(b.status) end)
      for i=1,math.min(3,#grp) do table.insert(graphRuns,grp[i]) end end
    table.sort(graphRuns,function(a,b)
      local da=seasonData and seasonData.dungeons and seasonData.dungeons[a.mapID]
      local db2=seasonData and seasonData.dungeons and seasonData.dungeons[b.mapID]
      local abA=da and da.abbr or a.mapName; local abB=db2 and db2.abbr or b.mapName
      if abA~=abB then return abA<abB end; return a.level<b.level end)
  else
    for _,r in ipairs(runs) do if r.mapID==MP._filterMap and SR(r.status)>=3 then table.insert(graphRuns,r) end end
    table.sort(graphRuns,function(a,b) return (a.date or 0)>(b.date or 0) end)
    local maxN=math.floor(CW2/28); while #graphRuns>maxN do table.remove(graphRuns) end end
  if #graphRuns==0 then local fs=holder:CreateFontString(nil,"OVERLAY"); fs:SetFont("Fonts/FRIZQT__.TTF",10,"")
    fs:SetPoint("CENTER"); fs:SetTextColor(0.35,0.35,0.45); fs:SetText("No timed runs to display"); return end
  local maxLv=0; for _,r in ipairs(graphRuns) do if (r.level or 0)>maxLv then maxLv=r.level end end; if maxLv==0 then maxLv=1 end
  -- Grid
  for gi=1,4 do local yFrac=gi/4; local yPx=PB+math.floor(yFrac*CH)
    local gl=holder:CreateTexture(nil,"ARTWORK"); gl:SetHeight(1)
    gl:SetPoint("BOTTOMLEFT",holder,"BOTTOMLEFT",PL,yPx); gl:SetPoint("BOTTOMRIGHT",holder,"BOTTOMRIGHT",-PR,yPx)
    gl:SetColorTexture(1,1,1,0.05)
    local vlbl=holder:CreateFontString(nil,"OVERLAY"); vlbl:SetFont("Fonts/FRIZQT__.TTF",8,"")
    vlbl:SetPoint("BOTTOMRIGHT",holder,"BOTTOMLEFT",PL-2,yPx); vlbl:SetTextColor(0.38,0.38,0.50)
    vlbl:SetJustifyH("RIGHT"); vlbl:SetText("+"..tostring(math.floor(maxLv*yFrac))) end
  local base=holder:CreateTexture(nil,"ARTWORK"); base:SetHeight(1)
  base:SetPoint("BOTTOMLEFT",holder,"BOTTOMLEFT",PL,PB); base:SetPoint("BOTTOMRIGHT",holder,"BOTTOMRIGHT",-PR,PB)
  base:SetColorTexture(ar,ag,ab,0.38)
  -- Fixed bar width like GLogger (24px bar + 4px gap), scrollable canvas
  local BAR_W  = 24
  local BAR_GAP = 4
  local GROUP_GAP = 20  -- extra gap between dungeon groups
  local N=#graphRuns

  -- Calculate total canvas width needed
  local totalW = PL + PR
  local lastMapForWidth = nil
  for _,r in ipairs(graphRuns) do
    if not MP._filterMap and r.mapID ~= lastMapForWidth and lastMapForWidth ~= nil then
      totalW = totalW + GROUP_GAP
    end
    totalW = totalW + BAR_W + BAR_GAP
    lastMapForWidth = r.mapID
  end
  totalW = math.max(totalW, W)

  -- Make graph canvas scrollable if needed
  holder:SetWidth(totalW)
  -- Scrolling: if wider than window, enable mouse wheel scroll on holder
  local scrollOffsetX = 0
  holder:EnableMouseWheel(true)
  holder:SetScript("OnMouseWheel", function(self, delta)
    local maxScroll = math.max(0, totalW - W)
    scrollOffsetX = math.max(0, math.min(maxScroll, scrollOffsetX - delta * 30))
    MP._graphScrollX = scrollOffsetX
    -- Redraw on next refresh
    if MP.win and MP.win:IsShown() then MP.Refresh() end
  end)

  local startX = PL - (MP._graphScrollX or 0)
  local currentX = startX
  local lastMap = nil

  for i,run in ipairs(graphRuns) do
    local frac=run.level/maxLv; local bh=math.max(4,math.floor(frac*CH))
    local sr2,sg2,sb2=SC(run.status)

    -- Group gap + divider between dungeons
    if not MP._filterMap and run.mapID~=lastMap and lastMap~=nil then
      local div=holder:CreateTexture(nil,"ARTWORK"); div:SetWidth(1)
      div:SetPoint("BOTTOMLEFT",holder,"BOTTOMLEFT",currentX-GROUP_GAP/2,PB)
      div:SetHeight(CH); div:SetColorTexture(ar,ag,ab,0.20)
      currentX = currentX + GROUP_GAP
    end
    lastMap=run.mapID

    local xB = currentX
    local bar=holder:CreateTexture(nil,"ARTWORK"); bar:SetSize(BAR_W,bh)
    bar:SetPoint("BOTTOMLEFT",holder,"BOTTOMLEFT",xB,PB)
    bar:SetColorTexture(sr2*0.65,sg2*0.65,sb2*0.65,0.88)
    local cap=holder:CreateTexture(nil,"ARTWORK"); cap:SetSize(BAR_W,3)
    cap:SetPoint("BOTTOMLEFT",holder,"BOTTOMLEFT",xB,PB+bh-3); cap:SetColorTexture(sr2,sg2,sb2,1)
    local lFS=holder:CreateFontString(nil,"OVERLAY"); lFS:SetFont("Fonts/FRIZQT__.TTF",9,"OUTLINE")
    lFS:SetPoint("BOTTOMLEFT",holder,"BOTTOMLEFT",xB+2,PB+bh+2); lFS:SetTextColor(1,1,1); lFS:SetText("+"..tostring(run.level))
    local abbr=(not MP._filterMap and seasonData and seasonData.dungeons and seasonData.dungeons[run.mapID] and seasonData.dungeons[run.mapID].abbr) or ""
    local dnFS=holder:CreateFontString(nil,"OVERLAY"); dnFS:SetFont("Fonts/FRIZQT__.TTF",8,"")
    dnFS:SetPoint("BOTTOMLEFT",holder,"BOTTOMLEFT",xB,4); dnFS:SetTextColor(0.38,0.38,0.50)
    dnFS:SetText(MP._filterMap and date("%d/%m",run.date) or abbr)
    local hit=CreateFrame("Frame",nil,holder); hit:SetSize(BAR_W+BAR_GAP,CH+PB)
    hit:SetPoint("BOTTOMLEFT",holder,"BOTTOMLEFT",xB,PB); hit:EnableMouse(true)
    local capRun=run; hit:SetScript("OnEnter",function(self)
      GameTooltip:SetOwner(self,"ANCHOR_TOP"); GameTooltip:SetText(capRun.mapName.."  +"..capRun.level,ar,ag,ab)
      GameTooltip:AddLine(date("%Y-%m-%d",capRun.date),0.50,0.50,0.62)
      GameTooltip:AddLine(ST(capRun.status).."  "..FmtTime(capRun.timeElapsed).." / "..FmtTime(capRun.timeLimit),SC(capRun.status))
      if (capRun.mapScore or 0)>0 then GameTooltip:AddLine("Score: "..tostring(math.floor(capRun.mapScore)),1,0.84,0) end
      if (capRun.deaths or 0)>0 then GameTooltip:AddLine("Deaths: "..capRun.deaths,0.9,0.3,0.3) end; GameTooltip:Show() end)
    hit:SetScript("OnLeave",function() GameTooltip:Hide() end)
    currentX = currentX + BAR_W + BAR_GAP
  end
end

-- ═══════════════════════════════ REFRESH ═══════════════════════════════════
function MP.Refresh()
  if not MP.win or not MP.win:IsShown() then return end
  if not MP._selSeason then MP._selSeason=GetCurrentSeason() end
  if not MP._selAlt    then MP._selAlt=GetPlayerKey() end
  if not MP._graphScrollX then MP._graphScrollX=0 end
  MP.win._altBtn._lbl:SetText(MP._selAlt:match("^([^%-]+)") or MP._selAlt)
  local sname=(MP.Seasons[MP._selSeason] and MP.Seasons[MP._selSeason].name) or "Season"
  MP.win._seasonBtn._lbl:SetText(sname)
  local allRuns=GetRuns(MP._selAlt,MP._selSeason); local seasonData=MP.Seasons[MP._selSeason]
  -- Overall score
  local overallScore=0
  if MP._selAlt==GetPlayerKey() then overallScore=C_ChallengeMode.GetOverallDungeonScore() or 0 end
  if overallScore==0 then local bpD={}; for _,r in ipairs(allRuns) do local sc=(r.mapScore or 0)
    if not bpD[r.mapID] or sc>bpD[r.mapID] then bpD[r.mapID]=sc end end
    for _,sc in pairs(bpD) do overallScore=overallScore+sc end end
  local scoreStr=tostring(math.floor(overallScore+0.5))
  if overallScore>0 and C_ChallengeMode.GetDungeonScoreRarityColor then
    local co=C_ChallengeMode.GetDungeonScoreRarityColor(overallScore)
    if co then scoreStr=string.format("|c%s%d|r",co:GenerateHexColor(),math.floor(overallScore+0.5)) end end
  MP.win._scoreLbl:SetText(scoreStr)
  DrawTiles(seasonData,allRuns)
  -- Build filtered datasets
  local filteredRuns={}; local teammates={}; local tmCounts={}
  local highestTimed=0; local totalCount=0; local bestDates={}; local graphRuns={}
  local bestPD={}; for _,r in ipairs(allRuns) do local mid=r.mapID
    local vs=(r.mapScore or 0); if vs==0 and SR(r.status)>=3 then local pct=0
      if (r.timeLimit or 0)>0 and r.timeElapsed then pct=math.max(0,1-(r.timeElapsed/r.timeLimit)) end
      vs=(r.level or 0)*1000+pct*1000 end
    if SR(r.status)>=3 then if not bestPD[mid] or vs>bestPD[mid].vs then bestPD[mid]={run=r,vs=vs} end end end
  for _,b in pairs(bestPD) do bestDates[b.run.date]=true end
  local myKey=GetPlayerKey()
  for _,r in ipairs(allRuns) do
    local passMap=not MP._filterMap or r.mapID==MP._filterMap
    if passMap and r.roster then for nm,d in pairs(r.roster) do if nm~=myKey and nm~=MP._selAlt then
      if not tmCounts[nm] then tmCounts[nm]={count=0,class=d.class,lastSeen=0} end
      tmCounts[nm].count=tmCounts[nm].count+1
      if (r.date or 0)>tmCounts[nm].lastSeen then tmCounts[nm].lastSeen=r.date end end end end
    local pass=passMap
    if pass and MP._filterPlayer and not (r.roster and r.roster[MP._filterPlayer]) then pass=false end
    if pass and MP._hideFails and SR(r.status)<=2 then pass=false end
    if pass then table.insert(filteredRuns,r); table.insert(graphRuns,r)
      totalCount=totalCount+1; if SR(r.status)>=3 and (r.level or 0)>highestTimed then highestTimed=r.level end end
  end
  -- Sort newest first (GLogger: sort before building rows, not after)
  table.sort(filteredRuns,function(a,b) return (a.date or 0)>(b.date or 0) end)
  table.sort(graphRuns,function(a,b) return (a.date or 0)>(b.date or 0) end)
  for nm,d in pairs(tmCounts) do table.insert(teammates,{rawName=nm,count=d.count,class=d.class,lastSeen=d.lastSeen}) end
  table.sort(teammates,function(a,b) return a.lastSeen>b.lastSeen end)
  local timed=0; for _,r in ipairs(filteredRuns) do if SR(r.status)>=3 then timed=timed+1 end end
  MP.win._highestLbl:SetText(string.format("Best: |cffffd100+%d|r",highestTimed))
  MP.win._totalLbl:SetText(string.format("Runs: |cffffd100%d|r   Timed: |cff4DCC50%d|r",totalCount,timed))
  if not MP._selRun and #filteredRuns>0 then MP._selRun=filteredRuns[1] end
  if MP._selRun then local found=false
    for _,r in ipairs(filteredRuns) do if r.date==MP._selRun.date then found=true; break end end
    if not found then MP._selRun=#filteredRuns>0 and filteredRuns[1] or nil end end
  DrawAnalytics(teammates); DrawHistory(filteredRuns,bestDates); DrawDetails(MP._selRun); DrawGraph(graphRuns,seasonData)
end

function MP._ApplyTheme()
  local ar,ag,ab = NS.ChatGetAccentRGB()
  if MP.win then MP.win:SetBackdropBorderColor(ar,ag,ab,0.38) end
  -- Update accent-colored elements (lines, bars, decorations)
  for _,e in ipairs(MP._accentTextures) do
    pcall(function()
      if e.isFS then e.tex:SetTextColor(ar,ag,ab,1)
      else e.tex:SetColorTexture(ar,ag,ab,e.alpha or 1) end
    end)
  end
  if NS.UpdatePCBTextures and MP.win then NS.UpdatePCBTextures(MP.win._pcbTextures) end
  -- Update title
  if MP.win and MP.win._titleFS then
    local hex = string.format("%02x%02x%02x", math.floor(ar*255), math.floor(ag*255), math.floor(ab*255))
    MP.win._titleFS:SetText("|cff"..hex.."MYTHIC+|r |cffffffffTRACKER|r")
  end
  -- Redraw if window is open (recreates dynamic elements with fresh color)
  if MP.win and MP.win:IsShown() then MP.Refresh() end
end

function MP.ShowWindow()
  BuildWindow()
  if MP.win:IsShown() then MP.win:Hide(); return end
  if not MP._selSeason then MP._selSeason=GetCurrentSeason() end
  if not MP._selAlt    then MP._selAlt=GetPlayerKey() end
  if C_MythicPlus.RequestRewards then C_MythicPlus.RequestRewards() end
  if C_MythicPlus.RequestMapInfo then C_MythicPlus.RequestMapInfo() end
  C_Timer.After(0.5,function() MP.SyncBlizzard(MP._selAlt,MP._selSeason) end)
  MP.win:Show(); MP.win:Raise(); MP.Refresh()
end

-- ═════════════════════ SETTINGS TAB ════════════════════════════════════════
function MP.SetupSettings(parent)
  local container=CreateFrame("Frame",nil,parent)
  local MakeCard=NS._SMakeCard; local MakePage=NS._SMakePage
  local Sep=NS._SSep; local R=NS._SR; local BD=NS._SBD
  local sc,Add=MakePage(container)
  local function DB(k) return NS.DB(k) end; local function DBSet(k,v) NS.DBSet(k,v) end
  local cT=MakeCard(sc,"Mythic+ Tracking")
  local enCB=NS.ChatGetCheckbox(cT.inner,"Enable Mythic+ Tracking",26,function(s) DBSet("mpEnabled",s) end,"Auto-record every Mythic+ run")
  enCB.option="mpEnabled"; R(cT,enCB,26)
  local openRow=CreateFrame("Frame",nil,cT.inner); openRow:SetHeight(32)
  local openBtn=CreateFrame("Button",nil,openRow,"BackdropTemplate"); openBtn:SetSize(0,26)
  openBtn:SetPoint("TOPLEFT",openRow,"TOPLEFT",0,-3); openBtn:SetPoint("TOPRIGHT",openRow,"TOPRIGHT",0,-3)
  openBtn:SetBackdrop(BD); openBtn:SetBackdropColor(0.04,0.04,0.07,1); openBtn:SetBackdropBorderColor(0.12,0.12,0.20,1)
  local oCut=openBtn:CreateTexture(nil,"OVERLAY",nil,4); oCut:SetSize(10,1); oCut:SetPoint("TOPRIGHT",openBtn,"TOPRIGHT",0,-1)
  do local _ar,_ag,_ab=NS.ChatGetAccentRGB(); oCut:SetColorTexture(_ar,_ag,_ab,0.22) end
  local oFS=openBtn:CreateFontString(nil,"OVERLAY"); oFS:SetFont("Fonts/FRIZQT__.TTF",11,""); oFS:SetPoint("CENTER"); oFS:SetTextColor(0.75,0.75,0.85); oFS:SetText("Open Mythic+ History")
  openBtn:SetScript("OnEnter",function() local cr,cg,cb=NS.ChatGetAccentRGB(); openBtn:SetBackdropBorderColor(cr,cg,cb,0.8) end)
  openBtn:SetScript("OnLeave",function() openBtn:SetBackdropBorderColor(0.12,0.12,0.20,1) end)
  openBtn:SetScript("OnClick",function() MP.ShowWindow() end)
  cT:Row(openRow,32); cT:Finish(); Add(cT); Add(Sep(sc),9)
  local cS=MakeCard(sc,"Season Overview"); local statLines={}
  for _,lbl in ipairs({"Total runs","Timed","Depleted/Abandoned","Best key level","Total deaths","Overall M+ Score"}) do
    local holder=CreateFrame("Frame",nil,cS.inner); holder:SetHeight(22); cS:Row(holder,22)
    holder:SetPoint("LEFT",cS.inner,"LEFT",0,0); holder:SetPoint("RIGHT",cS.inner,"RIGHT",0,0)
    local lFS=holder:CreateFontString(nil,"OVERLAY"); lFS:SetFont("Fonts/FRIZQT__.TTF",10,""); lFS:SetPoint("LEFT",holder,"LEFT",20,0); lFS:SetTextColor(0.50,0.50,0.60); lFS:SetText(lbl)
    local vFS=holder:CreateFontString(nil,"OVERLAY"); vFS:SetFont("Fonts/FRIZQT__.TTF",10,"OUTLINE"); vFS:SetPoint("RIGHT",holder,"RIGHT",-20,0); vFS:SetJustifyH("RIGHT"); vFS:SetTextColor(0.85,0.85,0.92)
    statLines[#statLines+1]=vFS end
  cS:Finish(); Add(cS); Add(Sep(sc),9)

  -- ── Card: Key Level Chart ─────────────────────────────────────────────────
  local cGraph = MakeCard(sc, "Key Level Chart")
  local GRAPH_H = 160
  local graphHolder = CreateFrame("Frame", nil, cGraph.inner)
  graphHolder:SetHeight(GRAPH_H)
  cGraph:Row(graphHolder, GRAPH_H)
  cGraph:Finish(); Add(cGraph)

  local function RenderSettingsGraph()
    for _,c in ipairs({graphHolder:GetChildren()}) do c:Hide(); c:SetParent(nil) end
    for _,r in ipairs({graphHolder:GetRegions()}) do r:Hide() end

    local runs=GetRuns()
    local ar2,ag2,ab2=NS.ChatGetAccentRGB()
    local seasonData=MP.Seasons[MP._selSeason or GetCurrentSeason()]

    -- Best timed per dungeon
    local graphRuns={}
    local grouped={}
    for _,r in ipairs(runs) do
      if SR(r.status)>=3 then
        if not grouped[r.mapID] then grouped[r.mapID]={} end
        table.insert(grouped[r.mapID],r)
      end
    end
    for _,grp in pairs(grouped) do
      table.sort(grp,function(a,b) return a.level>b.level end)
      table.insert(graphRuns,grp[1])
    end
    table.sort(graphRuns,function(a,b)
      local da=seasonData and seasonData.dungeons and seasonData.dungeons[a.mapID]
      local db2=seasonData and seasonData.dungeons and seasonData.dungeons[b.mapID]
      local abA=da and da.abbr or a.mapName; local abB=db2 and db2.abbr or b.mapName
      return abA<abB
    end)

    if #graphRuns==0 then
      local fs=graphHolder:CreateFontString(nil,"OVERLAY"); fs:SetFont("Fonts/FRIZQT__.TTF",10,"")
      fs:SetPoint("CENTER",graphHolder,"CENTER"); fs:SetTextColor(0.35,0.35,0.45)
      fs:SetText("Complete Mythic+ keys to see stats here"); return
    end

    local W=graphHolder:GetWidth() or 300
    local H=GRAPH_H
    local PL,PR,PT,PB=32,6,8,22
    local CW=W-PL-PR; local CH=math.min(H-PT-PB, 110)

    local maxLv=0
    for _,r in ipairs(graphRuns) do if (r.level or 0)>maxLv then maxLv=r.level end end
    if maxLv==0 then maxLv=1 end

    -- Baseline
    local base=graphHolder:CreateTexture(nil,"ARTWORK"); base:SetHeight(1)
    base:SetPoint("BOTTOMLEFT",graphHolder,"BOTTOMLEFT",PL,PB)
    base:SetPoint("BOTTOMRIGHT",graphHolder,"BOTTOMRIGHT",-PR,PB)
    base:SetColorTexture(ar2,ag2,ab2,0.35)

    -- Grid lines
    for gi=1,3 do
      local yFrac=gi/4; local yPx=PB+math.floor(yFrac*CH)
      local gl=graphHolder:CreateTexture(nil,"ARTWORK"); gl:SetHeight(1)
      gl:SetPoint("BOTTOMLEFT",graphHolder,"BOTTOMLEFT",PL,yPx)
      gl:SetPoint("BOTTOMRIGHT",graphHolder,"BOTTOMRIGHT",-PR,yPx)
      gl:SetColorTexture(1,1,1,0.05)
      local vlbl=graphHolder:CreateFontString(nil,"OVERLAY"); vlbl:SetFont("Fonts/FRIZQT__.TTF",7,"")
      vlbl:SetPoint("BOTTOMRIGHT",graphHolder,"BOTTOMLEFT",PL-2,yPx)
      vlbl:SetTextColor(0.38,0.38,0.50); vlbl:SetJustifyH("RIGHT")
      vlbl:SetText("+"..tostring(math.floor(maxLv*yFrac)))
    end

    local N=#graphRuns
    local BAR_W=math.max(10,math.floor((CW/N))-4)
    local slot=math.floor(CW/N)
    local currentX=PL

    for _,run in ipairs(graphRuns) do
      local frac=run.level/maxLv; local bh=math.max(4,math.floor(frac*CH))
      local sr2,sg2,sb2=SC(run.status)

      local bar=graphHolder:CreateTexture(nil,"ARTWORK"); bar:SetSize(BAR_W,bh)
      bar:SetPoint("BOTTOMLEFT",graphHolder,"BOTTOMLEFT",currentX,PB)
      bar:SetColorTexture(sr2*0.65,sg2*0.65,sb2*0.65,0.88)

      local cap=graphHolder:CreateTexture(nil,"ARTWORK"); cap:SetSize(BAR_W,2)
      cap:SetPoint("BOTTOMLEFT",graphHolder,"BOTTOMLEFT",currentX,PB+bh-2)
      cap:SetColorTexture(sr2,sg2,sb2,1)

      local lFS=graphHolder:CreateFontString(nil,"OVERLAY"); lFS:SetFont("Fonts/FRIZQT__.TTF",8,"OUTLINE")
      lFS:SetPoint("BOTTOMLEFT",graphHolder,"BOTTOMLEFT",currentX+1,PB+bh+2)
      lFS:SetTextColor(1,1,1); lFS:SetText("+"..tostring(run.level))

      local abbr=(seasonData and seasonData.dungeons and seasonData.dungeons[run.mapID] and seasonData.dungeons[run.mapID].abbr) or ""
      local dnFS=graphHolder:CreateFontString(nil,"OVERLAY"); dnFS:SetFont("Fonts/FRIZQT__.TTF",7,"")
      dnFS:SetPoint("BOTTOMLEFT",graphHolder,"BOTTOMLEFT",currentX,4)
      dnFS:SetTextColor(0.38,0.38,0.50); dnFS:SetText(abbr)

      currentX = currentX + slot
    end
  end

  container:SetScript("OnShow",function()
    enCB:SetValue(DB("mpEnabled")~=false)
    local runs=GetRuns(); local timed,depl,best,deaths=0,0,0,0
    for _,r in ipairs(runs) do if SR(r.status)>=3 then timed=timed+1 end; if SR(r.status)<=1 then depl=depl+1 end
      if (r.level or 0)>best then best=r.level end; deaths=deaths+(r.deaths or 0) end
    statLines[1]:SetText(tostring(#runs)); statLines[2]:SetText(tostring(timed)); statLines[2]:SetTextColor(0.30,0.90,0.30)
    statLines[3]:SetText(tostring(depl)); statLines[3]:SetTextColor(0.80,0.30,0.30)
    statLines[4]:SetText("+"..tostring(best)); statLines[5]:SetText(tostring(deaths)); statLines[5]:SetTextColor(0.80,0.50,0.50)
    local sc2=C_ChallengeMode and C_ChallengeMode.GetOverallDungeonScore and C_ChallengeMode.GetOverallDungeonScore() or 0
    statLines[6]:SetText(tostring(sc2)); statLines[6]:SetTextColor(1,0.84,0)
    C_Timer.After(0.05, RenderSettingsGraph)
  end)
  return container
end
