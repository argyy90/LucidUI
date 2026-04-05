-- LucidUI Modules/MythicPlus.lua  v2.0
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
  [17] = 1,  -- Blizzard ID 17 → our key 1 (Midnight S1, current live API)

  -- Season 2 (Midnight): Blizzard-IDs hier eintragen sobald bekannt
  -- [3] = 2,   -- Blizzard ID 3 → our key 2 (Midnight S2)
  -- [4] = 2,   -- Blizzard ID 4 → our key 2 (Midnight S2, falls API unterschiedlich zurückgibt)

  -- Season 3 (Midnight): Blizzard-IDs hier eintragen sobald bekannt
  -- [5] = 3,   -- Blizzard ID 5 → our key 3 (Midnight S3)
  -- [6] = 3,   -- Blizzard ID 6 → our key 3 (Midnight S3, falls API unterschiedlich zurückgibt)

  -- Season 1 (neue Expansion): Blizzard-IDs hier eintragen sobald bekannt
  -- [7] = 4,   -- Blizzard ID 7 → our key 4 (The Last Titan S1)
  -- [8] = 4,   -- Blizzard ID 8 → our key 4 (The Last Titan S1, falls API unterschiedlich zurückgibt)
}

MP.Seasons = {
  [1]={name="Midnight Season 1",dungeons={
    -- texture = FileDataID from GLogger (fallback when GetMapUIInfo returns nil)
    -- teleport = spell ID for M+ dungeon teleport
    [402]={abbr="AA",  name="Algeth'ar Academy",              texture=4742929, teleport=393273},
    [560]={abbr="MC",  name="Maisara Caverns",                texture=7478529, teleport=1254559},
    [558]={abbr="MT",  name="Magisters' Terrace",             texture=7467174, teleport=1254572},
    [559]={abbr="NPX", name="Nexus-Point Xenas",              texture=7570501, teleport=1254563},
    [556]={abbr="POS", name="Pit of Saron",                   texture=608210,  teleport=1254555},
    [239]={abbr="SEAT",name="Seat of the Triumvirate",        texture=1718213, teleport=1254551},
    [161]={abbr="SR",  name="Skyreach",                       texture=1041999, teleport=159898},
    [557]={abbr="WS",  name="Windrunner Spire",               texture=7464937, teleport=1254400},
  }},

  -- ─── SEASON 2 (Midnight) ─────────────────────────────────────────────────
  -- Zum Aktivieren: die "--" am Anfang jeder Zeile entfernen.
  -- mapID    = C_ChallengeMode.GetMapUIInfo() oder Wowhead
  -- texture  = FileDataID (Wowhead Asset-Browser)
  -- teleport = Spell ID (Wowhead: "Mythic Teleport: [Dungeon]")
  -- [2]={name="Midnight Season 2",dungeons={
  --   [1001]={abbr="D1", name="Dungeon Name 1",  texture=0000000, teleport=0000000},
  --   [1002]={abbr="D2", name="Dungeon Name 2",  texture=0000000, teleport=0000000},
  --   [1003]={abbr="D3", name="Dungeon Name 3",  texture=0000000, teleport=0000000},
  --   [1004]={abbr="D4", name="Dungeon Name 4",  texture=0000000, teleport=0000000},
  --   [1005]={abbr="D5", name="Dungeon Name 5",  texture=0000000, teleport=0000000},
  --   [1006]={abbr="D6", name="Dungeon Name 6",  texture=0000000, teleport=0000000},
  --   [1007]={abbr="D7", name="Dungeon Name 7",  texture=0000000, teleport=0000000},
  --   [1008]={abbr="D8", name="Dungeon Name 8",  texture=0000000, teleport=0000000},
  -- }},

  -- ─── SEASON 3 (Midnight) ─────────────────────────────────────────────────
  -- Zum Aktivieren: die "--" am Anfang jeder Zeile entfernen.
  -- mapID    = C_ChallengeMode.GetMapUIInfo() oder Wowhead
  -- texture  = FileDataID (Wowhead Asset-Browser)
  -- teleport = Spell ID (Wowhead: "Mythic Teleport: [Dungeon]")
  -- [3]={name="Midnight Season 3",dungeons={
  --   [1101]={abbr="D1", name="Dungeon Name 1",  texture=0000000, teleport=0000000},
  --   [1102]={abbr="D2", name="Dungeon Name 2",  texture=0000000, teleport=0000000},
  --   [1103]={abbr="D3", name="Dungeon Name 3",  texture=0000000, teleport=0000000},
  --   [1104]={abbr="D4", name="Dungeon Name 4",  texture=0000000, teleport=0000000},
  --   [1105]={abbr="D5", name="Dungeon Name 5",  texture=0000000, teleport=0000000},
  --   [1106]={abbr="D6", name="Dungeon Name 6",  texture=0000000, teleport=0000000},
  --   [1107]={abbr="D7", name="Dungeon Name 7",  texture=0000000, teleport=0000000},
  --   [1108]={abbr="D8", name="Dungeon Name 8",  texture=0000000, teleport=0000000},
  -- }},

  -- ─── SEASON 1 (The Last Titan — neue Expansion) ───────────────────────────
  -- Zum Aktivieren: die "--" am Anfang jeder Zeile entfernen.
  -- Expansion-Key 4 weiterzählen falls Midnight bereits 3 Seasons hatte.
  -- mapID    = C_ChallengeMode.GetMapUIInfo() oder Wowhead
  -- texture  = FileDataID (Wowhead Asset-Browser)
  -- teleport = Spell ID (Wowhead: "Mythic Teleport: [Dungeon]")
  -- [4]={name="The Last Titan Season 1",dungeons={
  --   [1201]={abbr="D1", name="Dungeon Name 1",  texture=0000000, teleport=0000000},
  --   [1202]={abbr="D2", name="Dungeon Name 2",  texture=0000000, teleport=0000000},
  --   [1203]={abbr="D3", name="Dungeon Name 3",  texture=0000000, teleport=0000000},
  --   [1204]={abbr="D4", name="Dungeon Name 4",  texture=0000000, teleport=0000000},
  --   [1205]={abbr="D5", name="Dungeon Name 5",  texture=0000000, teleport=0000000},
  --   [1206]={abbr="D6", name="Dungeon Name 6",  texture=0000000, teleport=0000000},
  --   [1207]={abbr="D7", name="Dungeon Name 7",  texture=0000000, teleport=0000000},
  --   [1208]={abbr="D8", name="Dungeon Name 8",  texture=0000000, teleport=0000000},
  -- }},
}

-- ─────────────────────────────── TELEPORT SPELLS ───────────────────────────
-- Master lookup: challengeMapID → teleport spellID
-- Used by auto-discovery AND manual season definitions.
-- Add new entries here as they become known (check BigWigs/Details/Wowhead).
MP.TeleportSpells = {
  -- Midnight
  [402]=393273,  [560]=1254559, [558]=1254572, [559]=1254563,
  [556]=1254555, [239]=1254551, [161]=159898,  [557]=1254400,
  -- The War Within
  [503]=445417,  [502]=445416,  [501]=445269,  [504]=445443,
  [505]=445444,  [506]=445441,  [507]=445440,  [508]=445414,
  -- Dragonflight
  [399]=393222,  [400]=393279,  [401]=393262,
  [403]=393276,  [404]=393267,  [405]=393256,  [406]=393283,
  -- Shadowlands
  [375]=354469,  [376]=354466,  [377]=354462,  [378]=354465,
  [379]=354463,  [380]=354464,  [381]=354468,  [382]=354467,
  -- Legion / BfA / older (from BigWigs)
  [197]=424153,  [198]=393766,  [199]=373262,  [200]=424163,
  [210]=410078,  [234]=424187,  [227]=410071,  [353]=373274,
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
local function AutoDiscoverSeason(rawID)
  local mapIDs = C_ChallengeMode.GetMapTable and C_ChallengeMode.GetMapTable()
  if not mapIDs or #mapIDs == 0 then return false end
  local dungeons = {}
  for _, mid in ipairs(mapIDs) do
    local name, _, _, tex = C_ChallengeMode.GetMapUIInfo(mid)
    if name then
      local abbr = ""
      for word in name:gmatch("%S+") do
        if not word:match("^[Tt]he$") and not word:match("^[Oo]f$") and not word:match("^[Aa]nd$") then
          abbr = abbr .. word:sub(1,1):upper()
        end
      end
      if #abbr < 2 then abbr = name:sub(1,3):upper() end
      local tp = MP.TeleportSpells and MP.TeleportSpells[mid]
      dungeons[mid] = {abbr=abbr, name=name, texture=tex or 0, teleport=tp}
    end
  end
  MP.Seasons[rawID] = {name="Season "..rawID, dungeons=dungeons}
  MP.SeasonMap[rawID] = rawID
  C_Timer.After(3, function()
    print("[|cff3bd2edLucid|r|cffffffffUI|r |cff3bd2edM+|r] |cff4DCC50Auto-discovered new season:|r "
      .."|cffffd100Season "..rawID.."|r (API ID "..rawID..") with "..#mapIDs.." dungeons")
  end)
  return true
end

local function GetCurrentSeason()
  local raw=C_MythicPlus and C_MythicPlus.GetCurrentSeason and C_MythicPlus.GetCurrentSeason()
  -- Normalise via SeasonMap (handles Blizzard's varying IDs)
  local s = raw and (MP.SeasonMap[raw] or raw)
  if s and MP.Seasons[s] then return s end
  -- Unknown season: try auto-discovery from API
  if raw and AutoDiscoverSeason(raw) then return raw end
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
  -- Update existing run if already saved (same mapID+date), otherwise insert
  for i, existing in ipairs(db[k][s]) do
    if existing.mapID == run.mapID and existing.date == run.date then
      db[k][s][i] = run
      return
    end
  end
  table.insert(db[k][s], run)
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
  -- Keep activeRun alive for loot collection until player leaves the dungeon
  activeState="COMPLETED"
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
local mpEventsRegistered = false

local function RegisterMPEvents()
  if mpEventsRegistered then return end
  mpEventsRegistered = true
  evF:RegisterEvent("PLAYER_ENTERING_WORLD")
  evF:RegisterEvent("CHALLENGE_MODE_START"); evF:RegisterEvent("WORLD_STATE_TIMER_START")
  evF:RegisterEvent("CHALLENGE_MODE_RESET"); evF:RegisterEvent("CHALLENGE_MODE_DEATH_COUNT_UPDATED")
  evF:RegisterEvent("CHALLENGE_MODE_COMPLETED"); evF:RegisterEvent("ZONE_CHANGED_NEW_AREA")
  evF:RegisterEvent("ENCOUNTER_LOOT_RECEIVED")
end

local function UnregisterMPEvents()
  if not mpEventsRegistered then return end
  mpEventsRegistered = false
  evF:UnregisterEvent("PLAYER_ENTERING_WORLD")
  evF:UnregisterEvent("CHALLENGE_MODE_START"); evF:UnregisterEvent("WORLD_STATE_TIMER_START")
  evF:UnregisterEvent("CHALLENGE_MODE_RESET"); evF:UnregisterEvent("CHALLENGE_MODE_DEATH_COUNT_UPDATED")
  evF:UnregisterEvent("CHALLENGE_MODE_COMPLETED"); evF:UnregisterEvent("ZONE_CHANGED_NEW_AREA")
  evF:UnregisterEvent("ENCOUNTER_LOOT_RECEIVED")
  activeState="IDLE"; activeRun=nil
end

MP.EnableTracking = function()
  RegisterMPEvents()
  if C_MythicPlus.RequestRewards then C_MythicPlus.RequestRewards() end
  if C_MythicPlus.RequestMapInfo then C_MythicPlus.RequestMapInfo() end
  C_Timer.After(2,function() MP.SyncBlizzard() end)
end

MP.DisableTracking = function()
  UnregisterMPEvents()
end

-- Print current season info to chat (for debugging / new season data collection)
MP.PrintSeasonInfo = function()
  local rawID = C_MythicPlus and C_MythicPlus.GetCurrentSeason and C_MythicPlus.GetCurrentSeason()
  local mappedID = rawID and (MP.SeasonMap[rawID] or rawID) or "nil"
  local sd = MP.Seasons[mappedID]
  local sName = sd and sd.name or "UNKNOWN"
  print("[|cff3bd2edLucid|r|cffffffffUI|r |cff3bd2edM+|r] ── Season Info ──")
  print("  Season: |cffffd100"..sName.."|r  (raw=|cffffffff"..tostring(rawID).."|r, mapped=|cffffffff"..tostring(mappedID).."|r)")
  -- API dungeons
  local mapIDs = C_ChallengeMode.GetMapTable and C_ChallengeMode.GetMapTable() or {}
  print("  API Dungeons (|cffffd100"..#mapIDs.."|r):")
  local sorted = {}
  for _, mid in ipairs(mapIDs) do
    local name, _, timeLimit, tex = C_ChallengeMode.GetMapUIInfo(mid)
    sorted[#sorted+1] = {mid=mid, name=name or "?", tex=tex or 0, timeLimit=timeLimit or 0}
  end
  table.sort(sorted, function(a,b) return a.name < b.name end)
  for _, d in ipairs(sorted) do
    -- Check our season data
    local ours = sd and sd.dungeons and sd.dungeons[d.mid]
    local abbr = ours and ours.abbr or "?"
    local tp = MP.TeleportSpells and MP.TeleportSpells[d.mid]
    local tpStr
    if tp then
      local known = C_SpellBook.IsSpellKnownOrInSpellBook(tp)
      tpStr = (known and "|cff4DCC50" or "|cffff4444") .. tp .. "|r"
    else
      tpStr = "|cffff9900missing|r"
    end
    local inSeason = ours and "|cff4DCC50yes|r" or "|cffff4444no|r"
    print("    |cffffd100"..abbr.."|r ["..d.mid.."] "..d.name
      .."  tex=|cffffffff"..d.tex.."|r  tp="..tpStr
      .."  limit=|cffffffff"..d.timeLimit.."|r  inSeason="..inSeason)
  end
  -- Copyable Lua block
  print("  ── Copy-paste template ──")
  print("  [X]={name=\"Season X\",dungeons={")
  for _, d in ipairs(sorted) do
    local ours = sd and sd.dungeons and sd.dungeons[d.mid]
    local abbr = ours and ours.abbr
    if not abbr then
      abbr = ""
      for word in d.name:gmatch("%S+") do
        if not word:match("^[Tt]he$") and not word:match("^[Oo]f$") and not word:match("^[Aa]nd$") then
          abbr = abbr .. word:sub(1,1):upper()
        end
      end
      if #abbr < 2 then abbr = d.name:sub(1,3):upper() end
    end
    local tp = MP.TeleportSpells and MP.TeleportSpells[d.mid] or 0
    print('    ['..d.mid..']={abbr="'..abbr..'", name="'..d.name..'", texture='..d.tex..', teleport='..tp..'},')
  end
  print("  }},")
end

evF:RegisterEvent("PLAYER_LOGIN")
evF:SetScript("OnEvent",function(_,ev,...)
  if ev=="PLAYER_LOGIN" then
    if NS.DB("mpEnabled") == false then return end
    RegisterMPEvents()
    -- Migrate runs from any season key that maps to key 1 (e.g. Blizzard returned 2 before SeasonMap fix)
    C_Timer.After(1, function()
      local db=GetDB(); local totalMigrated=0
      for _,charData in pairs(db) do
        if type(charData) ~= "table" then break end
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
        local curSeason = MP.Seasons[GetCurrentSeason()]
        local sName = curSeason and curSeason.name or "current season"
        print("[|cff3bd2edLucid|r|cffffffffUI|r |cff3bd2edMythic+|r] Migrated "..totalMigrated.." run(s) to "..sName..".")
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
    if activeState=="COMPLETED" and not C_ChallengeMode.IsChallengeModeActive() then
      -- Left dungeon after completion — finalize and clean up
      if activeRun then SaveRun(activeRun) end
      activeState="IDLE"; activeRun=nil
      if MP.win and MP.win:IsShown() then MP.Refresh() end
    elseif (activeState=="ACTIVE" or activeState=="WARMING_UP") and not C_ChallengeMode.IsChallengeModeActive() then
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
        SaveRun(activeRun)
        if MP.win and MP.win:IsShown() then MP.Refresh() end
      end
    end
  end
end)

-- ═════════════════════════════ WINDOW ══════════════════════════════════════
local WIN_W,WIN_H=1150,700
local HDR_H=46; local TILE_H=88; local PANE_H=300; local GRAPH_H=nil
local LEFT_W=260; local RIGHT_W=270
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
  local fs=b:CreateFontString(nil,"OVERLAY"); fs:SetFont(STANDARD_TEXT_FONT,10,""); fs:SetPoint("CENTER")
  fs:SetTextColor(0.72,0.72,0.82); fs:SetText(txt); b._lbl=fs
  b:SetScript("OnEnter",function() local ar,ag,ab=NS.ChatGetAccentRGB(); b:SetBackdropBorderColor(ar,ag,ab,0.9) end)
  b:SetScript("OnLeave",function() b:SetBackdropBorderColor(0.12,0.12,0.20,1) end)
  return b
end

local function MkPane(par)
  local sf=CreateFrame("ScrollFrame",nil,par,"UIPanelScrollFrameTemplate")
  if sf.ScrollBar then
    sf.ScrollBar:SetAlpha(0.35)
    sf.ScrollBar:ClearAllPoints()
    sf.ScrollBar:SetPoint("TOPRIGHT", sf, "TOPRIGHT", -2, -16)
    sf.ScrollBar:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", -2, 16)
  end
  local sc=CreateFrame("Frame",nil,sf); sc:SetWidth(sf:GetWidth() or 200)
  sf:SetScrollChild(sc)
  sf:HookScript("OnSizeChanged",function(_,w) sc:SetWidth(math.max(50, w-18)) end)
  return sf,sc
end

local function BuildWindow()
  if MP.win then return end
  wipe(MP._accentTextures)  -- clear in case window is rebuilt
  local BD={bgFile=NS.TEX_WHITE,edgeFile=NS.TEX_WHITE,edgeSize=1}
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
  local titleFS=MP.win:CreateFontString(nil,"OVERLAY"); titleFS:SetFont(STANDARD_TEXT_FONT,14,"OUTLINE")
  titleFS:SetPoint("TOPLEFT",MP.win,"TOPLEFT",14,-12)
  titleFS:SetText("|cff"..hex.."MYTHIC+|r |cffffffffTRACKER|r")
  MP.win._titleFS = titleFS

  -- "M+ Rating" label above score
  local ratingLbl=MP.win:CreateFontString(nil,"OVERLAY"); ratingLbl:SetFont(STANDARD_TEXT_FONT,9,"OUTLINE")
  ratingLbl:SetPoint("TOP",MP.win,"TOP",0,-8); ratingLbl:SetTextColor(0.65,0.65,0.75); ratingLbl:SetText("M+ Rating")

  MP.win._scoreLbl=MP.win:CreateFontString(nil,"OVERLAY"); MP.win._scoreLbl:SetFont(STANDARD_TEXT_FONT,26,"OUTLINE")
  MP.win._scoreLbl:SetPoint("TOP",MP.win,"TOP",0,-16); MP.win._scoreLbl:SetTextColor(1,0.84,0)

  -- Stats shifted right so they clear the score
  MP.win._highestLbl=MP.win:CreateFontString(nil,"OVERLAY"); MP.win._highestLbl:SetFont(STANDARD_TEXT_FONT,12,"")
  MP.win._highestLbl:SetPoint("TOPLEFT",MP.win,"TOP",80,-6); MP.win._highestLbl:SetTextColor(0.88,0.88,0.95)

  MP.win._totalLbl=MP.win:CreateFontString(nil,"OVERLAY"); MP.win._totalLbl:SetFont(STANDARD_TEXT_FONT,10,"")
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
  local cX=closeBtn:CreateFontString(nil,"OVERLAY"); cX:SetFont(STANDARD_TEXT_FONT,11,""); cX:SetPoint("CENTER")
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
    local fs=MP.win:CreateFontString(nil,"OVERLAY"); fs:SetFont(STANDARD_TEXT_FONT,9,"OUTLINE")
    fs:SetPoint("TOPLEFT",MP.win,"TOPLEFT",xOff,-(bodyY+6)); fs:SetWidth(width)
    fs:SetTextColor(1,0.82,0); fs:SetText(txt)
    -- Dashed underline (4 segments matching main settings card style)
    local segW,segH,segGap=18,1,6
    for si=0,3 do
      local seg=MP.win:CreateTexture(nil,"OVERLAY",nil,3); seg:SetSize(segW,segH)
      seg:SetPoint("TOPLEFT",MP.win,"TOPLEFT",xOff+si*(segW+segGap),-(bodyY+18))
      seg:SetColorTexture(ar,ag,ab,0.18)
      RegAccent(seg,0.18)
    end
    MP._goldLabels = MP._goldLabels or {}
    table.insert(MP._goldLabels, fs)
  end
  PaneLabel("PLAYERS",8,LEFT_W); PaneLabel("RUN HISTORY",LEFT_W+14,CENTER_W)
  PaneLabel("RUN DETAILS",LEFT_W+CENTER_W+20,RIGHT_W)

  -- Card-style backgrounds for each pane
  local function PaneCard(xOff, yOff, w, h)
    local card=CreateFrame("Frame",nil,MP.win,"BackdropTemplate")
    card:SetBackdrop({bgFile=NS.TEX_WHITE,edgeFile=NS.TEX_WHITE,edgeSize=1})
    card:SetBackdropColor(0.024,0.024,0.040,0.6)
    card:SetBackdropBorderColor(0.08,0.08,0.13,1)
    card:SetPoint("TOPLEFT",MP.win,"TOPLEFT",xOff,-yOff)
    card:SetSize(w,h)
    card:SetFrameLevel(MP.win:GetFrameLevel()+1)
    -- Left accent bar
    local bar=card:CreateTexture(nil,"OVERLAY",nil,5); bar:SetWidth(3)
    bar:SetPoint("TOPLEFT",card,"TOPLEFT",0,-4); bar:SetPoint("BOTTOMLEFT",card,"BOTTOMLEFT",0,4)
    bar:SetColorTexture(ar,ag,ab,0.8); RegAccent(bar,0.8)
    -- Shadow bar
    local bar2=card:CreateTexture(nil,"OVERLAY",nil,4); bar2:SetWidth(1)
    bar2:SetPoint("TOPLEFT",card,"TOPLEFT",4,-7); bar2:SetPoint("BOTTOMLEFT",card,"BOTTOMLEFT",4,7)
    bar2:SetColorTexture(ar,ag,ab,0.25); RegAccent(bar2,0.25)
    -- Top-right L-bracket
    local trH=card:CreateTexture(nil,"OVERLAY",nil,5); trH:SetSize(14,2)
    trH:SetPoint("TOPRIGHT",card,"TOPRIGHT",-2,-2); trH:SetColorTexture(ar,ag,ab,0.45); RegAccent(trH,0.45)
    local trV=card:CreateTexture(nil,"OVERLAY",nil,5); trV:SetSize(2,14)
    trV:SetPoint("TOPRIGHT",card,"TOPRIGHT",-2,-2); trV:SetColorTexture(ar,ag,ab,0.45); RegAccent(trV,0.45)
    -- Bottom-right L-bracket
    local brH=card:CreateTexture(nil,"OVERLAY",nil,5); brH:SetSize(10,2)
    brH:SetPoint("BOTTOMRIGHT",card,"BOTTOMRIGHT",-2,2); brH:SetColorTexture(ar,ag,ab,0.25); RegAccent(brH,0.25)
    local brV=card:CreateTexture(nil,"OVERLAY",nil,5); brV:SetSize(2,10)
    brV:SetPoint("BOTTOMRIGHT",card,"BOTTOMRIGHT",-2,2); brV:SetColorTexture(ar,ag,ab,0.25); RegAccent(brV,0.25)
    return card
  end
  local pCardY = bodyY+40
  local pCardH = PANE_H-20
  PaneCard(8, pCardY, LEFT_W-2, pCardH)
  PaneCard(LEFT_W+12, pCardY, CENTER_W+2, pCardH)

  -- Vertical dividers
  local function VDiv(x)
    local vl=MP.win:CreateTexture(nil,"OVERLAY",nil,3); vl:SetWidth(1)
    vl:SetPoint("TOPLEFT",MP.win,"TOPLEFT",x,-(bodyY+22)); vl:SetPoint("BOTTOMLEFT",MP.win,"BOTTOMLEFT",x,28)
    vl:SetColorTexture(ar,ag,ab,0.18)
    RegAccent(vl,0.18)
  end; VDiv(LEFT_W+10); VDiv(LEFT_W+CENTER_W+16)

  local anaSF,anaSC=MkPane(MP.win)
  anaSF:SetPoint("TOPLEFT",MP.win,"TOPLEFT",12,-(bodyY+24))
  anaSF:SetPoint("BOTTOMRIGHT",MP.win,"TOPLEFT",LEFT_W+2,-(bodyY+PANE_H+18))
  MP.win._anaSC=anaSC; MP.win._anaSF=anaSF

  local histSF,histSC=MkPane(MP.win)
  histSF:SetPoint("TOPLEFT",MP.win,"TOPLEFT",LEFT_W+12,-(bodyY+24))
  histSF:SetPoint("BOTTOMRIGHT",MP.win,"TOPLEFT",LEFT_W+CENTER_W+10,-(bodyY+PANE_H+18))
  MP.win._histSC=histSC; MP.win._histSF=histSF

  local detSF,detSC=MkPane(MP.win)
  -- Run Details fills the full right column (from body top to above footer buttons)
  detSF:SetPoint("TOPLEFT",MP.win,"TOPLEFT",LEFT_W+CENTER_W+18,-(bodyY+24))
  detSF:SetPoint("BOTTOMRIGHT",MP.win,"BOTTOMRIGHT",-4,28)
  MP.win._detSC=detSC; MP.win._detSF=detSF

  -- Graph area with card
  local gY=bodyY+PANE_H+22
  local graphCard=PaneCard(8, gY, LEFT_W+CENTER_W+8, WIN_H-gY-44)
  graphCard:SetPoint("TOPLEFT",MP.win,"TOPLEFT",8,-gY)
  graphCard:SetPoint("BOTTOMRIGHT",MP.win,"TOPLEFT",LEFT_W+CENTER_W+14,-WIN_H+44)
  graphCard:SetSize(0,0) -- size from anchors
  local gHdr=graphCard:CreateFontString(nil,"OVERLAY"); gHdr:SetFont(STANDARD_TEXT_FONT,9,"OUTLINE")
  gHdr:SetPoint("TOP",graphCard,"TOP",0,-6)
  gHdr:SetJustifyH("CENTER"); gHdr:SetTextColor(1,0.82,0); gHdr:SetText("KEY LEVEL CHART  — Best timed runs per dungeon")
  MP._goldLabels = MP._goldLabels or {}
  table.insert(MP._goldLabels, gHdr)
  local gHolder=CreateFrame("Frame",nil,graphCard)
  gHolder:SetPoint("TOPLEFT",graphCard,"TOPLEFT",8,-20); gHolder:SetPoint("BOTTOMRIGHT",graphCard,"BOTTOMRIGHT",-8,6)
  MP.win._gHolder=gHolder

  -- Footer checkboxes + buttons
  local maskCB=NS.ChatGetCheckbox(MP.win,"Mask Names",18,function(s) MP._maskNames=s; MP.Refresh() end,"Anonymise player names to first 3 letters")
  maskCB:ClearAllPoints(); maskCB:SetSize(130,18); maskCB:SetPoint("BOTTOMLEFT",MP.win,"BOTTOMLEFT",110,6)
  local failCB=NS.ChatGetCheckbox(MP.win,"Hide Fails",18,function(s) MP._hideFails=s; MP.Refresh() end,"Hide depleted/abandoned runs from history")
  failCB:ClearAllPoints(); failCB:SetSize(120,18); failCB:SetPoint("LEFT",maskCB,"RIGHT",10,0)

  -- ── Tutorial button ───────────────────────────────────────────────────────
  local tutBtn=MkBtn(MP.win,"Tutorial",90,20,BD)
  tutBtn:SetPoint("BOTTOMLEFT",MP.win,"BOTTOMLEFT",8,5)
  local tutBorder=CreateFrame("Frame",nil,tutBtn,"BackdropTemplate")
  tutBorder:SetAllPoints(); tutBorder:SetFrameLevel(tutBtn:GetFrameLevel()-1)
  tutBorder:SetBackdrop({edgeFile=NS.TEX_WHITE,edgeSize=2})
  tutBorder:SetBackdropBorderColor(ar,ag,ab,1); tutBorder:Hide()

  -- Coach marks
  local coachMarks={}
  local tutorialActive=false

  local COACH_STEPS={
    {title="1. Filters",       text="Select a character and season to view their Mythic+ history. Use Reset Filters to clear selections.",
     anchor="altBtn",     point="BOTTOM", relPoint="TOP", x=0, y=8},
    {title="2. Dungeon Tiles", text="Overview of your best timed key for each dungeon this season. Left-click to filter runs by dungeon.\n|cff4DCC50Right-click to teleport directly to the dungeon (requires a timed key).|r",
     anchor="tileRow",    point="TOP", relPoint="BOTTOM", x=0, y=-8},
    {title="3. Players",       text="Lists all players you've run keys with. Click a name to filter the run history by that player.",
     anchor="anaSF",      point="TOPRIGHT", relPoint="TOPLEFT", x=-8, y=0},
    {title="4. Run History",   text="Every recorded run for the selected filters. Click a run to see full details in the right panel.",
     anchor="histSF",     point="BOTTOM", relPoint="TOP", x=0, y=8},
    {title="5. Run Details",   text="Shows the selected run's dungeon, key level, time, roster, deaths, and loot drops.",
     anchor="detSF",      point="TOPLEFT", relPoint="TOPRIGHT", x=8, y=0},
    {title="6. Key Level Chart",text="Visual chart showing your best timed key levels across all dungeons.",
     anchor="gHolder",    point="TOP", relPoint="BOTTOM", x=0, y=-8},
    {title="7. Footer Options", text="Mask Names hides player names for screenshots/streaming. Hide Fails removes depleted runs from history.",
     anchor="maskCB",     point="BOTTOM", relPoint="TOP", x=60, y=8},
  }

  local tutProgress=0

  local function ClearCoachMarks()
    for _,f in ipairs(coachMarks) do f:Hide() end
    wipe(coachMarks)
  end

  local function GetAnchorFrame(key)
    if key=="altBtn"  then return MP.win._altBtn end
    if key=="tileRow" then return MP.win._tileRow end
    if key=="anaSF"   then return MP.win._anaSF end
    if key=="histSF"  then return MP.win._histSF end
    if key=="detSF"   then return MP.win._detSF end
    if key=="gHolder" then return MP.win._gHolder end
    if key=="maskCB"  then return maskCB end
    return MP.win
  end

  local function DrawCoachMarks()
    ClearCoachMarks()
    if not tutorialActive then return end
    local step=COACH_STEPS[tutProgress+1]
    if not step then
      tutorialActive=false; tutProgress=0
      tutBtn._lbl:SetText("Tutorial"); tutBorder:Hide()
      return
    end
    local anchor=GetAnchorFrame(step.anchor)
    if not anchor then return end

    -- Parent to UIParent so nothing in MP.win can cover it
    local f=CreateFrame("Frame","LucidUICoachMark",UIParent,"BackdropTemplate")
    f:SetSize(260,100)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(200)
    f:SetBackdrop({bgFile=NS.TEX_WHITE,edgeFile=NS.TEX_WHITE,edgeSize=2})
    f:SetBackdropColor(0.08,0.08,0.12,0.97)
    f:SetBackdropBorderColor(ar,ag,ab,1)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)

    -- Anchor relative to the target element
    f:SetPoint(step.point,anchor,step.relPoint,step.x,step.y)

    -- Title
    local tFS=f:CreateFontString(nil,"OVERLAY")
    tFS:SetFont(STANDARD_TEXT_FONT,12,"OUTLINE")
    tFS:SetPoint("TOPLEFT",12,-10)
    tFS:SetTextColor(ar,ag,ab)
    tFS:SetText(step.title)

    -- Step counter
    local cFS=f:CreateFontString(nil,"OVERLAY")
    cFS:SetFont(STANDARD_TEXT_FONT,9,"")
    cFS:SetPoint("TOPRIGHT",-10,-12)
    cFS:SetTextColor(0.45,0.45,0.55)
    cFS:SetText((tutProgress+1).."/"..#COACH_STEPS)

    -- Body
    local bFS=f:CreateFontString(nil,"OVERLAY")
    bFS:SetFont(STANDARD_TEXT_FONT,10,"")
    bFS:SetPoint("TOPLEFT",12,-30)
    bFS:SetPoint("TOPRIGHT",-12,-30)
    bFS:SetTextColor(0.85,0.85,0.92)
    bFS:SetText(step.text)
    bFS:SetWordWrap(true)
    bFS:SetJustifyH("LEFT")

    -- Auto-height + "Got it" button (after text height is known)
    C_Timer.After(0.01,function()
      if not f or not f:IsShown() then return end
      local th=bFS:GetStringHeight() or 40
      f:SetHeight(math.max(90, th+65))
      local gotIt=CreateFrame("Button",nil,f,"BackdropTemplate")
      gotIt:SetSize(80,20)
      gotIt:SetPoint("BOTTOM",f,"BOTTOM",0,10)
      gotIt:SetBackdrop({bgFile=NS.TEX_WHITE,edgeFile=NS.TEX_WHITE,edgeSize=1})
      gotIt:SetBackdropColor(0.04,0.04,0.07,1)
      gotIt:SetBackdropBorderColor(ar,ag,ab,0.6)
      local gFS=gotIt:CreateFontString(nil,"OVERLAY")
      gFS:SetFont(STANDARD_TEXT_FONT,10,""); gFS:SetPoint("CENTER"); gFS:SetTextColor(0.85,0.85,0.92); gFS:SetText("Got it")
      gotIt:SetScript("OnEnter",function() gotIt:SetBackdropBorderColor(ar,ag,ab,1); gFS:SetTextColor(1,1,1) end)
      gotIt:SetScript("OnLeave",function() gotIt:SetBackdropBorderColor(ar,ag,ab,0.6); gFS:SetTextColor(0.85,0.85,0.92) end)
      gotIt:SetScript("OnClick",function()
        tutProgress=tutProgress+1
        DrawCoachMarks()
      end)
    end)

    f:Show()
    table.insert(coachMarks,f)
  end

  local TUT_KEY = "TutorialPlayer-TutRealm"
  local savedAlt, savedSeason, savedFilter, savedPlayerFilter

  local function LoadTutorialData()
    local db = GetDB()
    local s = GetCurrentSeason()
    local sd = MP.Seasons[s]
    if not sd then return end
    local now = time()
    local fakeRuns = {}
    local classes = {"WARRIOR","MAGE","PRIEST","ROGUE","DRUID","HUNTER","PALADIN","DEATHKNIGHT"}
    local teammates = {
      {"Thunderfury-TutRealm","WARRIOR","TANK"},
      {"Frostbolt-TutRealm","MAGE","DAMAGER"},
      {"Healbot-TutRealm","PRIEST","HEALER"},
      {"Stabsworth-TutRealm","ROGUE","DAMAGER"},
    }
    local mapIDs = {}
    for mid in pairs(sd.dungeons) do mapIDs[#mapIDs+1] = mid end
    table.sort(mapIDs)
    -- Fake loot pool
    local fakeLoot = {
      {link="|cffa335ee|Hitem:0|h[Seal of the Keystone]|h|r", q=4},
      {link="|cffa335ee|Hitem:0|h[Everforge Chestplate]|h|r", q=4},
      {link="|cff0070dd|Hitem:0|h[Sigil of Dark Depths]|h|r", q=3},
      {link="|cffa335ee|Hitem:0|h[Band of the Forgotten Path]|h|r", q=4},
      {link="|cff0070dd|Hitem:0|h[Darkflame Trinket]|h|r", q=3},
      {link="|cffa335ee|Hitem:0|h[Mythic Keystone Ring]|h|r", q=4},
    }
    -- Generate 3-5 runs per dungeon at varying key levels
    for di, mid in ipairs(mapIDs) do
      local dg = sd.dungeons[mid]
      local apiName = C_ChallengeMode.GetMapUIInfo(mid) or dg.name
      local numRuns = 3 + (di % 3)
      for ri = 1, numRuns do
        local level = 6 + di + ri
        local limit = 1800 + (mid % 5) * 120
        -- Vary timing: many +3, some +2, some +1, few depleted
        local timeMult
        local idx = (di + ri) % 10
        if idx == 0 then timeMult = 1.15     -- depleted
        elseif idx <= 4 then timeMult = 0.45 + ri * 0.03  -- fast (+3)
        elseif idx <= 6 then timeMult = 0.70 + ri * 0.03  -- medium (+2)
        else timeMult = 0.85 + ri * 0.02 end              -- close (+1)
        local elapsed = limit * timeMult
        local status
        if elapsed > limit then status = 1  -- depleted
        elseif elapsed <= limit * 0.6 then status = 4  -- +3
        elseif elapsed <= limit * 0.8 then status = 3  -- +2
        else status = 2 end  -- +1
        local roster = { [TUT_KEY] = {class=classes[(di+ri)%#classes+1], role="DAMAGER"} }
        for ti = 1, 4 do
          local tm = teammates[((di+ri+ti-1) % #teammates) + 1]
          roster[tm[1]] = {class=tm[2], role=tm[3]}
        end
        -- Every run gets 1-2 loot items
        local loot = {}
        local li = ((di + ri) % #fakeLoot) + 1
        local owner = ri % 2 == 0 and TUT_KEY or teammates[(di % #teammates) + 1][1]
        loot[1] = {link=fakeLoot[li].link, originalOwner=owner, currentOwner=owner, qty=1}
        if (di + ri) % 3 == 0 then
          local li2 = (li % #fakeLoot) + 1
          local owner2 = teammates[((di + ri) % #teammates) + 1][1]
          loot[2] = {link=fakeLoot[li2].link, originalOwner=owner2, currentOwner=owner2, qty=1}
        end
        fakeRuns[#fakeRuns+1] = {
          mapID=mid, mapName=apiName, level=level, status=status,
          timeLimit=limit, timeElapsed=elapsed, date=now - (di*numRuns+ri) * 3600,
          roster=roster, loot=loot, deaths=status<=1 and (2+ri%4) or ri%3, timeLost=(ri%3)*5,
          overallScore=1800+di*50, mapScore=status>=2 and (180+level*12) or 0,
        }
      end
    end
    if not db[TUT_KEY] then db[TUT_KEY] = {} end
    db[TUT_KEY][s] = fakeRuns
  end

  local function ClearTutorialData()
    local db = GetDB()
    db[TUT_KEY] = nil
  end

  local function EnterTutorial()
    tutorialActive = true; tutProgress = 0
    tutBtn._lbl:SetText("Exit Tutorial"); tutBorder:Show()
    -- Save current state
    savedAlt = MP._selAlt; savedSeason = MP._selSeason
    savedFilter = MP._filterMap; savedPlayerFilter = MP._filterPlayer
    -- Load fake data and switch to tutorial player
    LoadTutorialData()
    MP._selAlt = TUT_KEY; MP._filterMap = nil; MP._filterPlayer = nil; MP._selRun = nil
    MP.Refresh()
    DrawCoachMarks()
  end

  local function ExitTutorial()
    tutorialActive = false
    tutBtn._lbl:SetText("Tutorial"); tutBorder:Hide()
    ClearCoachMarks()
    ClearTutorialData()
    -- Restore previous state
    MP._selAlt = savedAlt or GetPlayerKey()
    MP._selSeason = savedSeason; MP._filterMap = savedFilter; MP._filterPlayer = savedPlayerFilter
    MP._selRun = nil
    MP.Refresh()
  end

  tutBtn:SetScript("OnClick",function()
    if tutorialActive then ExitTutorial() else EnterTutorial() end
  end)

  -- Hide coach marks when window closes
  MP.win:HookScript("OnHide",function()
    if tutorialActive then ExitTutorial() end
  end)

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
      tile.border:SetBackdrop({edgeFile=NS.TEX_WHITE,edgeSize=2})
      tile.border:SetBackdropBorderColor(1,0.82,0,1); tile.border:Hide()

      tile.abbrFS=tile:CreateFontString(nil,"OVERLAY"); tile.abbrFS:SetFont(STANDARD_TEXT_FONT,18,"OUTLINE")
      tile.abbrFS:SetPoint("TOP",tile,"TOP",0,-4); tile.abbrFS:SetTextColor(1,0.82,0)

      tile.lvlFS=tile:CreateFontString(nil,"OVERLAY"); tile.lvlFS:SetFont(STANDARD_TEXT_FONT,20,"OUTLINE")
      tile.lvlFS:SetPoint("CENTER",tile,"CENTER",0,2)

      tile.scFS=tile:CreateFontString(nil,"OVERLAY"); tile.scFS:SetFont(STANDARD_TEXT_FONT,13,"OUTLINE")
      tile.scFS:SetPoint("BOTTOM",tile,"BOTTOM",0,20)

      tile.nameFS=tile:CreateFontString(nil,"OVERLAY"); tile.nameFS:SetFont(STANDARD_TEXT_FONT,9,"")
      tile.nameFS:SetPoint("BOTTOM",tile,"BOTTOM",0,4); tile.nameFS:SetTextColor(1,0.82,0)
      tile.nameFS:SetJustifyH("CENTER")

      -- Teleport icon (top-right corner)
      tile.tpIcon=tile:CreateTexture(nil,"OVERLAY",nil,6)
      tile.tpIcon:SetSize(28,28)
      tile.tpIcon:SetPoint("TOPRIGHT",tile,"TOPRIGHT",-2,2)
      tile.tpIcon:SetTexture("Interface/AddOns/LucidUI/Assets/Tp.png")
      tile.tpIcon:Hide()
      -- Cooldown timer below icon
      tile.tpCdFS=tile:CreateFontString(nil,"OVERLAY")
      tile.tpCdFS:SetFont(STANDARD_TEXT_FONT,16,"OUTLINE")
      tile.tpCdFS:SetPoint("TOP",tile.tpIcon,"BOTTOM",0,-1)
      tile.tpCdFS:Hide()

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

    -- Teleport icon + cooldown
    local teleportSpell = seasonData.dungeons[d.id] and seasonData.dungeons[d.id].teleport
    local isTutorial = MP._selAlt == "TutorialPlayer-TutRealm"
    local tpActive = teleportSpell and NS.DB("mpTeleport") ~= false and (isTutorial or C_SpellBook.IsSpellKnownOrInSpellBook(teleportSpell))
    if tpActive then
      tile.tpIcon:Show()
      if isTutorial then
        -- Fake: some ready, some on cooldown
        local fakeCD = (i % 3 == 0)
        if fakeCD then
          local fakeMin = 4 + i * 2
          tile.tpCdFS:SetText(fakeMin.."m"); tile.tpCdFS:SetTextColor(1,0.3,0.3); tile.tpCdFS:Show()
          tile.tpIcon:SetVertexColor(1,0.3,0.3); tile.tpIcon:SetAlpha(0.8)
        else
          tile.tpCdFS:Hide()
          tile.tpIcon:SetVertexColor(0.3,1,0.3); tile.tpIcon:SetAlpha(0.8)
        end
      else
        local cdInfo = C_Spell.GetSpellCooldown(teleportSpell)
        if cdInfo and cdInfo.startTime and cdInfo.startTime > 0 and cdInfo.duration > 2 then
          local remaining = cdInfo.startTime + cdInfo.duration - GetTime()
          if remaining > 0 then
            local cdText = remaining >= 60 and string.format("%dm", math.ceil(remaining/60)) or string.format("%ds", math.ceil(remaining))
            tile.tpCdFS:SetText(cdText); tile.tpCdFS:SetTextColor(1,0.3,0.3); tile.tpCdFS:Show()
            tile.tpIcon:SetVertexColor(1,0.3,0.3); tile.tpIcon:SetAlpha(0.8)
          else
            tile.tpCdFS:Hide()
            tile.tpIcon:SetVertexColor(0.3,1,0.3); tile.tpIcon:SetAlpha(0.8)
          end
        else
          tile.tpCdFS:Hide()
          tile.tpIcon:SetVertexColor(0.3,1,0.3); tile.tpIcon:SetAlpha(0.8)
        end
      end
    elseif teleportSpell and NS.DB("mpTeleport") ~= false then
      -- Spell not yet learned: show greyed out
      tile.tpIcon:Show(); tile.tpCdFS:Hide()
      tile.tpIcon:SetVertexColor(0.65,0.65,0.65); tile.tpIcon:SetAlpha(1)
    else
      tile.tpIcon:Hide(); tile.tpCdFS:Hide()
    end

    local capID=d.id; local capName=d.name
    -- Teleport overlay: InsecureActionButton for right-click teleport
    -- IMPORTANT: never SetScript("OnClick") — it destroys the template handler
    if not tile._tpBtn then
      local tp = CreateFrame("Button", nil, tile, "InsecureActionButtonTemplate")
      tp:SetAllPoints()
      tp:SetFrameLevel(tile:GetFrameLevel()+2)
      tp:RegisterForClicks("AnyDown","AnyUp")
      tile._tpBtn = tp
    end
    -- Right-click = teleport via template handler (only if setting enabled)
    local tpEnabled = teleportSpell and NS.DB("mpTeleport") ~= false
    if tpEnabled then
      tile._tpBtn:SetAttribute("type2","spell")
      tile._tpBtn:SetAttribute("spell2",teleportSpell)
    else
      tile._tpBtn:SetAttribute("type2",nil)
      tile._tpBtn:SetAttribute("spell2",nil)
    end
    -- Left-click = filter (via PostClick, runs AFTER template handler)
    tile._tpBtn:SetScript("PostClick",function(_,btn)
      if btn=="LeftButton" then
        MP._filterMap=(MP._filterMap==capID) and nil or capID; MP._selRun=nil; MP.Refresh()
      end
    end)
    tile._tpBtn:SetScript("OnEnter",function(self2)
      if MP._filterMap~=capID then tile.highlight:Show(); tile.border:Show() end
      GameTooltip:SetOwner(self2,"ANCHOR_TOP")
      GameTooltip:SetText(capName,1,1,1)
      GameTooltip:AddLine("Left-click to filter",0.7,0.7,0.7)
      if tpEnabled then
        if C_SpellBook.IsSpellKnownOrInSpellBook(teleportSpell) then
          GameTooltip:AddLine("Right-click to teleport",0.3,0.9,0.3)
        else
          GameTooltip:AddLine("Teleport not unlocked",0.5,0.5,0.5)
        end
      end
      GameTooltip:Show()
    end)
    tile._tpBtn:SetScript("OnLeave",function()
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
  hdr:SetPoint("TOPLEFT",sc,"TOPLEFT",4,-yOff); hdr:SetPoint("TOPRIGHT",sc,"TOPRIGHT",-4,-yOff)
  hdr:SetBackdrop(BD); hdr:SetBackdropColor(0.015,0.015,0.025,1); hdr:SetBackdropBorderColor(ar,ag,ab,0.22)
  local h1=hdr:CreateFontString(nil,"OVERLAY"); h1:SetFont(STANDARD_TEXT_FONT,9,"OUTLINE")
  h1:SetPoint("LEFT",hdr,"LEFT",4,0); h1:SetTextColor(ar,ag,ab); h1:SetText("Player")
  local h2=hdr:CreateFontString(nil,"OVERLAY"); h2:SetFont(STANDARD_TEXT_FONT,9,"OUTLINE")
  h2:SetPoint("RIGHT",hdr,"RIGHT",-4,0); h2:SetTextColor(ar,ag,ab); h2:SetText("Runs")
  yOff=yOff+ROW+2
  if #teammates==0 then sc:SetHeight(40)
    local fs=sc:CreateFontString(nil,"OVERLAY"); fs:SetFont(STANDARD_TEXT_FONT,10,""); fs:SetPoint("TOP",sc,"TOP",0,-yOff)
    fs:SetTextColor(0.35,0.35,0.45); fs:SetText("No teammates yet"); return end
  for _,tm in ipairs(teammates) do
    local row=CreateFrame("Button",nil,sc,"BackdropTemplate"); row:SetHeight(ROW)
    row:SetPoint("TOPLEFT",sc,"TOPLEFT",4,-yOff); row:SetPoint("TOPRIGHT",sc,"TOPRIGHT",-4,-yOff)
    row:SetBackdrop(BD); row:SetBackdropBorderColor(0.06,0.06,0.10,1)
    local isAct=(MP._filterPlayer==tm.rawName)
    if isAct then row:SetBackdropColor(ar*0.15,ag*0.15,ab*0.15,1) else row:SetBackdropColor(0.03,0.03,0.05,1) end
    local hex=ClassHex(tm.class); local disp=tm.rawName
    if MP._maskNames then local sh=disp:match("^([^%-]+)"); disp=(sh and sh:sub(1,3).."***" or disp) end
    local nFS=row:CreateFontString(nil,"OVERLAY"); nFS:SetFont(STANDARD_TEXT_FONT,10,"")
    nFS:SetPoint("LEFT",row,"LEFT",4,0); nFS:SetText("|c"..hex..disp.."|r")
    local cFS=row:CreateFontString(nil,"OVERLAY"); cFS:SetFont(STANDARD_TEXT_FONT,10,"")
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
  hdr:SetPoint("TOPLEFT",sc,"TOPLEFT",8,-yOff); hdr:SetPoint("TOPRIGHT",sc,"TOPRIGHT",-4,-yOff)
  hdr:SetBackdrop(BD); hdr:SetBackdropColor(0.015,0.015,0.025,1); hdr:SetBackdropBorderColor(ar,ag,ab,0.22)
  local xc=5
  for i,col in ipairs({"Date","Dungeon","+Lvl","Time","Status","Deaths"}) do
    local fs=hdr:CreateFontString(nil,"OVERLAY"); fs:SetFont(STANDARD_TEXT_FONT,10,"OUTLINE")
    fs:SetPoint("LEFT",hdr,"LEFT",xc,0); fs:SetTextColor(ar,ag,ab); fs:SetText(col); xc=xc+CW[i] end
  yOff=yOff+20+2
  if #runs==0 then sc:SetHeight(40)
    local fs=sc:CreateFontString(nil,"OVERLAY"); fs:SetFont(STANDARD_TEXT_FONT,10,""); fs:SetPoint("TOP",sc,"TOP",0,-yOff)
    fs:SetTextColor(0.35,0.35,0.45); fs:SetText("No runs match the current filters"); return end
  for _,run in ipairs(runs) do
    local row=CreateFrame("Button",nil,sc,"BackdropTemplate"); row:SetHeight(ROW)
    row:SetPoint("TOPLEFT",sc,"TOPLEFT",8,-yOff); row:SetPoint("TOPRIGHT",sc,"TOPRIGHT",-4,-yOff)
    row:SetBackdrop(BD); row:SetBackdropBorderColor(0.06,0.06,0.10,1)
    local isAct=(MP._selRun and MP._selRun.date==run.date)
    if isAct then row:SetBackdropColor(ar*0.12,ag*0.12,ab*0.12,1) else row:SetBackdropColor(0.028,0.028,0.046,1) end
    local sr,sg,sb=SC(run.status)
    local sBar=row:CreateTexture(nil,"OVERLAY",nil,5); sBar:SetWidth(2); sBar:SetPoint("TOPLEFT"); sBar:SetPoint("BOTTOMLEFT"); sBar:SetColorTexture(sr,sg,sb,1)
    local xc2=6
    local isBest=bestDates and bestDates[run.date]
    local dTxt=(isBest and "|TInterface/WorldMap/Skull_64:11:11|t " or "")..date("%d.%m.%y %H:%M",run.date)
    local dFS=row:CreateFontString(nil,"OVERLAY"); dFS:SetFont(STANDARD_TEXT_FONT,11,""); dFS:SetPoint("LEFT",row,"LEFT",xc2,0); dFS:SetTextColor(0.50,0.50,0.62); dFS:SetText(dTxt); xc2=xc2+CW[1]
    local nFS=row:CreateFontString(nil,"OVERLAY"); nFS:SetFont(STANDARD_TEXT_FONT,11,""); nFS:SetPoint("LEFT",row,"LEFT",xc2,0); nFS:SetTextColor(0.88,0.88,0.94); nFS:SetText(run.mapName or "?"); xc2=xc2+CW[2]
    local lFS=row:CreateFontString(nil,"OVERLAY"); lFS:SetFont(STANDARD_TEXT_FONT,12,"OUTLINE"); lFS:SetPoint("LEFT",row,"LEFT",xc2,0); lFS:SetTextColor(sr,sg,sb); lFS:SetText("+"..tostring(run.level or 0)); xc2=xc2+CW[3]
    local tFS=row:CreateFontString(nil,"OVERLAY"); tFS:SetFont(STANDARD_TEXT_FONT,11,""); tFS:SetPoint("LEFT",row,"LEFT",xc2,0); tFS:SetTextColor(0.70,0.70,0.82); tFS:SetText(FmtTime(run.timeElapsed)); xc2=xc2+CW[4]
    local stFS=row:CreateFontString(nil,"OVERLAY"); stFS:SetFont(STANDARD_TEXT_FONT,11,"OUTLINE"); stFS:SetPoint("LEFT",row,"LEFT",xc2,0); stFS:SetTextColor(sr,sg,sb); stFS:SetText(ST(run.status)); xc2=xc2+CW[5]
    local d2=(run.deaths or 0); local dtFS=row:CreateFontString(nil,"OVERLAY"); dtFS:SetFont(STANDARD_TEXT_FONT,11,""); dtFS:SetPoint("LEFT",row,"LEFT",xc2,0)
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
  local ar,ag,ab=NS.ChatGetAccentRGB(); local yOff=4
  local PAD=8
  local function FS(txt,size,r,g,b,xi) local f=sc:CreateFontString(nil,"OVERLAY"); f:SetFont(STANDARD_TEXT_FONT,size or 10,"")
    f:SetPoint("TOPLEFT",sc,"TOPLEFT",(xi or PAD),-yOff); f:SetTextColor(r or 0.85,g or 0.85,b or 0.92); f:SetText(txt)
    yOff=yOff+(size or 10)+7; return f end
  -- Mini card: dark bg with left accent bar
  local function CardStart()
    local startY=yOff
    return function()
      local h=yOff-startY+PAD
      local card=CreateFrame("Frame",nil,sc,"BackdropTemplate")
      card:SetBackdrop({bgFile=NS.TEX_WHITE,edgeFile=NS.TEX_WHITE,edgeSize=1})
      card:SetBackdropColor(0.028,0.028,0.046,0.8)
      card:SetBackdropBorderColor(0.08,0.08,0.13,1)
      card:SetPoint("TOPLEFT",sc,"TOPLEFT",0,-startY)
      card:SetPoint("TOPRIGHT",sc,"TOPRIGHT",-2,-startY)
      card:SetHeight(h); card:SetFrameLevel(sc:GetFrameLevel())
      -- Left accent bar + shadow
      local bar=card:CreateTexture(nil,"OVERLAY",nil,5); bar:SetWidth(3)
      bar:SetPoint("TOPLEFT",0,-3); bar:SetPoint("BOTTOMLEFT",0,3)
      bar:SetColorTexture(ar,ag,ab,0.8)
      local bar2=card:CreateTexture(nil,"OVERLAY",nil,4); bar2:SetWidth(1)
      bar2:SetPoint("TOPLEFT",4,-6); bar2:SetPoint("BOTTOMLEFT",4,6)
      bar2:SetColorTexture(ar,ag,ab,0.25)
      -- Top-right L-bracket
      local trH=card:CreateTexture(nil,"OVERLAY",nil,5); trH:SetSize(12,2)
      trH:SetPoint("TOPRIGHT",-2,-2); trH:SetColorTexture(ar,ag,ab,0.45)
      local trV=card:CreateTexture(nil,"OVERLAY",nil,5); trV:SetSize(2,12)
      trV:SetPoint("TOPRIGHT",-2,-2); trV:SetColorTexture(ar,ag,ab,0.45)
      -- Bottom-right L-bracket
      local brH=card:CreateTexture(nil,"OVERLAY",nil,5); brH:SetSize(8,2)
      brH:SetPoint("BOTTOMRIGHT",-2,2); brH:SetColorTexture(ar,ag,ab,0.25)
      local brV=card:CreateTexture(nil,"OVERLAY",nil,5); brV:SetSize(2,8)
      brV:SetPoint("BOTTOMRIGHT",-2,2); brV:SetColorTexture(ar,ag,ab,0.25)
      yOff=yOff+PAD+8
    end
  end
  if not run then sc:SetHeight(60)
    FS("Select a run to view details",10,0.40,0.40,0.50); return end
  -- Card 1: Run Info
  local endCard1=CardStart()
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
    yOff=yOff+2; FS("Affixes:", 10, 0.80,0.80,0.90)
    for _,affID in ipairs(run.affixes) do local nm,_,fid=C_ChallengeMode.GetAffixInfo(affID)
      local ico=fid and ("|T"..fid..":12:12:0:0:64:64:4:60:4:60|t ") or ""
      FS(ico..(nm or ("Affix "..affID)), 10, 0.72,0.72,0.85, 14) end end
  endCard1()
  -- Card 2: Roster
  if run.roster and next(run.roster) then
    local endCard2=CardStart()
    FS("ROSTER", 9, ar,ag,ab)
    local RORD={TANK=1,HEALER=2,DAMAGER=3}
    local roster={}; for nm,d in pairs(run.roster) do table.insert(roster,{name=nm,class=d.class,role=d.role}) end
    table.sort(roster,function(a,b) return (RORD[a.role] or 4)<(RORD[b.role] or 4) end)
    local RI={TANK="|TInterface/AddOns/LucidUI/Assets/Tank.png:16:16|t",
              HEALER="|TInterface/AddOns/LucidUI/Assets/Heal.png:16:16|t",
              DAMAGER="|TInterface/AddOns/LucidUI/Assets/Dps.png:16:16|t"}
    for _,p in ipairs(roster) do local hex=ClassHex(p.class); local disp=p.name
      if MP._maskNames then local sh=disp:match("^([^%-]+)"); disp=(sh and sh:sub(1,3).."***" or disp) end
      FS((RI[p.role] or RI.DAMAGER).." |c"..hex..disp.."|r", 10, 0.85,0.85,0.92, PAD) end
    endCard2()
  end
  -- Card 3: Loot
  if run.loot and #run.loot>0 then
    local endCard3=CardStart()
    FS("LOOT", 9, ar,ag,ab)
    for _,item in ipairs(run.loot) do
      local linkText = item.link or "?"
      local lootBtn = CreateFrame("Button",nil,sc)
      lootBtn:SetHeight(16); lootBtn:SetPoint("TOPLEFT",sc,"TOPLEFT",PAD,-yOff)
      lootBtn:SetPoint("TOPRIGHT",sc,"TOPRIGHT",0,-yOff)
      local lfs = lootBtn:CreateFontString(nil,"OVERLAY"); lfs:SetFont(STANDARD_TEXT_FONT,10,"")
      lfs:SetPoint("LEFT",0,0); lfs:SetText(linkText)
      local capLink = item.link
      lootBtn:SetScript("OnEnter",function(self2)
        if capLink then
          GameTooltip:SetOwner(self2,"ANCHOR_RIGHT")
          GameTooltip:SetHyperlink(capLink)
          GameTooltip:Show()
        end
      end)
      lootBtn:SetScript("OnLeave",function() GameTooltip:Hide() end)
      lootBtn:SetScript("OnClick",function(_,btn)
        if capLink and IsShiftKeyDown() then
          local eb = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
          if eb then eb:Insert(capLink) end
        end
      end)
      yOff=yOff+17
      local own=item.currentOwner or "?"
      if MP._maskNames then local sh=own:match("^([^%-]+)"); own=(sh and sh:sub(1,3).."***" or own) end
      local ownClass = run.roster and run.roster[item.currentOwner] and run.roster[item.currentOwner].class
      local ownHex = ownClass and ClassHex(ownClass) or "ff808090"
      FS("  |TInterface/AddOns/LucidUI/Assets/Crown.png:10:10|t |c"..ownHex..own.."|r", 9, 0.85,0.85,0.92)
    end
    endCard3()
  end
  -- Delete button
  local delBtn=CreateFrame("Button",nil,sc,"BackdropTemplate"); delBtn:SetSize(68,18)
  delBtn:SetPoint("TOPRIGHT",sc,"TOPRIGHT",-3,-3); local BD2=MP.win._BD
  delBtn:SetBackdrop(BD2); delBtn:SetBackdropColor(0.08,0.02,0.02,1); delBtn:SetBackdropBorderColor(0.28,0.08,0.08,1)
  local dLbl=delBtn:CreateFontString(nil,"OVERLAY"); dLbl:SetFont(STANDARD_TEXT_FONT,9,""); dLbl:SetPoint("CENTER")
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
  if #graphRuns==0 then local fs=holder:CreateFontString(nil,"OVERLAY"); fs:SetFont(STANDARD_TEXT_FONT,10,"")
    fs:SetPoint("CENTER"); fs:SetTextColor(0.35,0.35,0.45); fs:SetText("No timed runs to display"); return end
  local maxLv=0; for _,r in ipairs(graphRuns) do if (r.level or 0)>maxLv then maxLv=r.level end end; if maxLv==0 then maxLv=1 end
  -- Grid
  for gi=1,4 do local yFrac=gi/4; local yPx=PB+math.floor(yFrac*CH)
    local gl=holder:CreateTexture(nil,"ARTWORK"); gl:SetHeight(1)
    gl:SetPoint("BOTTOMLEFT",holder,"BOTTOMLEFT",PL,yPx); gl:SetPoint("BOTTOMRIGHT",holder,"BOTTOMRIGHT",-PR,yPx)
    gl:SetColorTexture(1,1,1,0.05)
    local vlbl=holder:CreateFontString(nil,"OVERLAY"); vlbl:SetFont(STANDARD_TEXT_FONT,8,"")
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
  local groupStartX = startX  -- track where current dungeon group started

  local function FlushGroupLabel(mapID)
    if MP._filterMap then return end
    local abbr = seasonData and seasonData.dungeons and seasonData.dungeons[mapID] and seasonData.dungeons[mapID].abbr
    if not abbr then return end
    local groupEndX = currentX - BAR_GAP
    local cx = math.floor((groupStartX + groupEndX) / 2)
    local dnFS=holder:CreateFontString(nil,"OVERLAY"); dnFS:SetFont(STANDARD_TEXT_FONT,8,"")
    dnFS:SetPoint("BOTTOM",holder,"BOTTOMLEFT",cx,4); dnFS:SetTextColor(0.38,0.38,0.50)
    dnFS:SetText(abbr); dnFS:SetJustifyH("CENTER")
  end

  for i,run in ipairs(graphRuns) do
    local frac=run.level/maxLv; local bh=math.max(4,math.floor(frac*CH))
    local sr2,sg2,sb2=SC(run.status)

    -- Group gap + divider between dungeons
    if not MP._filterMap and run.mapID~=lastMap and lastMap~=nil then
      FlushGroupLabel(lastMap)
      local div=holder:CreateTexture(nil,"ARTWORK"); div:SetWidth(1)
      div:SetPoint("BOTTOMLEFT",holder,"BOTTOMLEFT",currentX-GROUP_GAP/2,PB)
      div:SetHeight(CH); div:SetColorTexture(ar,ag,ab,0.20)
      currentX = currentX + GROUP_GAP
      groupStartX = currentX
    end
    if run.mapID~=lastMap then groupStartX = currentX end
    lastMap=run.mapID

    local xB = currentX
    local bar=holder:CreateTexture(nil,"ARTWORK"); bar:SetSize(BAR_W,bh)
    bar:SetPoint("BOTTOMLEFT",holder,"BOTTOMLEFT",xB,PB)
    bar:SetColorTexture(sr2*0.65,sg2*0.65,sb2*0.65,0.88)
    local cap=holder:CreateTexture(nil,"ARTWORK"); cap:SetSize(BAR_W,3)
    cap:SetPoint("BOTTOMLEFT",holder,"BOTTOMLEFT",xB,PB+bh-3); cap:SetColorTexture(sr2,sg2,sb2,1)
    local lFS=holder:CreateFontString(nil,"OVERLAY"); lFS:SetFont(STANDARD_TEXT_FONT,9,"OUTLINE")
    lFS:SetPoint("BOTTOMLEFT",holder,"BOTTOMLEFT",xB+2,PB+bh+2); lFS:SetTextColor(1,1,1); lFS:SetText("+"..tostring(run.level))
    -- Per-bar date label only when filtering by map
    if MP._filterMap then
      local dnFS=holder:CreateFontString(nil,"OVERLAY"); dnFS:SetFont(STANDARD_TEXT_FONT,8,"")
      dnFS:SetPoint("BOTTOMLEFT",holder,"BOTTOMLEFT",xB,4); dnFS:SetTextColor(0.38,0.38,0.50)
      dnFS:SetText(date("%d/%m",run.date))
    end
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
  -- Flush label for last dungeon group
  if lastMap then FlushGroupLabel(lastMap) end
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
  local timed=0; local depleted=0
  for _,r in ipairs(filteredRuns) do
    if SR(r.status)>=3 then timed=timed+1
    elseif SR(r.status)<=2 then depleted=depleted+1 end
  end
  MP.win._highestLbl:SetText(string.format("Highest Timed: |cffffd100+%d|r",highestTimed))
  MP.win._totalLbl:SetText(string.format("Total Runs: |cffffd100%d|r   Timed: |cff4DCC50%d|r   Depleted: |cffff4444%d|r",totalCount,timed,depleted))
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
  -- Pair row: Enable + Teleport side by side
  local pairRow=CreateFrame("Frame",nil,cT.inner); pairRow:SetHeight(26)
  cT:Row(pairRow,26)
  pairRow:SetPoint("LEFT",cT.inner,"LEFT",0,0); pairRow:SetPoint("RIGHT",cT.inner,"RIGHT",0,0)
  local lh=CreateFrame("Frame",nil,pairRow)
  lh:SetPoint("TOPLEFT",pairRow,"TOPLEFT",0,0); lh:SetPoint("BOTTOMRIGHT",pairRow,"BOTTOM",-2,0)
  local rh=CreateFrame("Frame",nil,pairRow)
  rh:SetPoint("TOPLEFT",pairRow,"TOP",2,0); rh:SetPoint("BOTTOMRIGHT",pairRow,"BOTTOMRIGHT",0,0)
  local enCB=NS.ChatGetCheckbox(lh,"Enable Mythic+ Tracking",26,function(s) DBSet("mpEnabled",s); if s then DBSet("showMPlusBtn",true); MP.EnableTracking() else MP.DisableTracking() end; if NS.LayoutBarButtons then NS.LayoutBarButtons() end end,"Auto-record every Mythic+ run")
  enCB.option="mpEnabled"; enCB:SetParent(lh); enCB:ClearAllPoints(); enCB:SetAllPoints(lh)
  enCB:SetValue(NS.DB("mpEnabled") ~= false)
  local tpCB=NS.ChatGetCheckbox(rh,"Dungeon Teleport",26,function(s) DBSet("mpTeleport",s); if MP.win and MP.win:IsShown() then MP.Refresh() end end,"Right-click a dungeon tile in the M+ window to teleport directly to that dungeon (requires a timed key)")
  tpCB.option="mpTeleport"; tpCB:SetParent(rh); tpCB:ClearAllPoints(); tpCB:SetAllPoints(rh)
  tpCB:SetValue(NS.DB("mpTeleport") ~= false)
  local openRow=CreateFrame("Frame",nil,cT.inner); openRow:SetHeight(32)
  local openBtn=CreateFrame("Button",nil,openRow,"BackdropTemplate"); openBtn:SetSize(0,26)
  openBtn:SetPoint("TOPLEFT",openRow,"TOPLEFT",0,-3); openBtn:SetPoint("TOPRIGHT",openRow,"TOPRIGHT",0,-3)
  openBtn:SetBackdrop(BD); openBtn:SetBackdropColor(0.04,0.04,0.07,1); openBtn:SetBackdropBorderColor(0.12,0.12,0.20,1)
  local oCut=openBtn:CreateTexture(nil,"OVERLAY",nil,4); oCut:SetSize(10,1); oCut:SetPoint("TOPRIGHT",openBtn,"TOPRIGHT",0,-1)
  do local _ar,_ag,_ab=NS.ChatGetAccentRGB(); oCut:SetColorTexture(_ar,_ag,_ab,0.22) end
  local oFS=openBtn:CreateFontString(nil,"OVERLAY"); oFS:SetFont(STANDARD_TEXT_FONT,11,""); oFS:SetPoint("CENTER"); oFS:SetTextColor(0.75,0.75,0.85); oFS:SetText("Open Mythic+ History")
  openBtn:SetScript("OnEnter",function() local cr,cg,cb=NS.ChatGetAccentRGB(); openBtn:SetBackdropBorderColor(cr,cg,cb,0.8) end)
  openBtn:SetScript("OnLeave",function() openBtn:SetBackdropBorderColor(0.12,0.12,0.20,1) end)
  openBtn:SetScript("OnClick",function() MP.ShowWindow() end)
  cT:Row(openRow,32); cT:Finish(); Add(cT); Add(Sep(sc),9)
  local cS=MakeCard(sc,"Season Overview"); local statLines={}
  for _,lbl in ipairs({"Total runs","Timed","Depleted/Abandoned","Best key level","Total deaths","Overall M+ Score"}) do
    local holder=CreateFrame("Frame",nil,cS.inner); holder:SetHeight(22); cS:Row(holder,22)
    holder:SetPoint("LEFT",cS.inner,"LEFT",0,0); holder:SetPoint("RIGHT",cS.inner,"RIGHT",0,0)
    local lFS=holder:CreateFontString(nil,"OVERLAY"); lFS:SetFont(STANDARD_TEXT_FONT,10,""); lFS:SetPoint("LEFT",holder,"LEFT",20,0); lFS:SetTextColor(0.50,0.50,0.60); lFS:SetText(lbl)
    local vFS=holder:CreateFontString(nil,"OVERLAY"); vFS:SetFont(STANDARD_TEXT_FONT,10,"OUTLINE"); vFS:SetPoint("RIGHT",holder,"RIGHT",-20,0); vFS:SetJustifyH("RIGHT"); vFS:SetTextColor(0.85,0.85,0.92)
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
      local fs=graphHolder:CreateFontString(nil,"OVERLAY"); fs:SetFont(STANDARD_TEXT_FONT,10,"")
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
      local vlbl=graphHolder:CreateFontString(nil,"OVERLAY"); vlbl:SetFont(STANDARD_TEXT_FONT,7,"")
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

      local lFS=graphHolder:CreateFontString(nil,"OVERLAY"); lFS:SetFont(STANDARD_TEXT_FONT,8,"OUTLINE")
      lFS:SetPoint("BOTTOMLEFT",graphHolder,"BOTTOMLEFT",currentX+1,PB+bh+2)
      lFS:SetTextColor(1,1,1); lFS:SetText("+"..tostring(run.level))

      local abbr=(seasonData and seasonData.dungeons and seasonData.dungeons[run.mapID] and seasonData.dungeons[run.mapID].abbr) or ""
      local dnFS=graphHolder:CreateFontString(nil,"OVERLAY"); dnFS:SetFont(STANDARD_TEXT_FONT,7,"")
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