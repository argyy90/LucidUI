-- LucidUI Core.lua
-- Namespace, constants, DB/theme system, Apply* functions, font helpers.
-- Loaded first (after Locales.lua). All other files access shared state via NS.

LucidUINS = LucidUINS or {}
local NS = LucidUINS

-- ── Shared mutable frame references (set by BuildWindow) ─────────────────────
NS.win              = nil
NS.titleBar         = nil
NS.titleTex         = nil
NS.titleText        = nil
NS.smf              = nil
NS.collapseBtn      = nil
NS.resizeWidget     = nil
NS.debugWin         = nil
NS.debugSMF         = nil
NS.btnIconTextures  = {}
NS.characterFullName = nil

-- ── Message/debug storage ──────────────────────────────────────────────────────
NS.lines      = {}   -- formatted entries (copy dialog)
NS.rawEntries = {}   -- raw {msg, r, g, b, ts}
NS.debugLines = {}   -- debug log entries

-- ── Constants ──────────────────────────────────────────────────────────────────
NS.MAX_LINES = 50
NS.MAX_DEBUG = 200
NS.CYAN = {59/255, 210/255, 237/255}
NS.COL  = {
  loot  = {0.3,  0.9,  0.3},
  money = {1.0,  0.85, 0.0},
  group = {0.7,  0.9,  0.5},
}

-- ── Themes ─────────────────────────────────────────────────────────────────────
local DARK_THEME = {
  key       = "default",
  label     = "Default",
  bg        = {0.03, 0.03, 0.03, 0.95},
  border    = {0.15, 0.15, 0.15, 1.0},
  titleBg   = {0.06, 0.06, 0.06, 1.0},
  titleText = {1.0,  1.0,  1.0,  1.0},
  tilders   = {59/255, 210/255, 237/255, 1.0},
  btnColor  = {1.0,  1.0,  1.0,  1.0},
}
NS.DARK_THEME = DARK_THEME

local CUSTOM_DEFAULTS = {
  customBg        = {0.03, 0.03, 0.03, 0.95},
  customBorder    = {0.15, 0.15, 0.15, 1.0},
  customTitleBg   = {0.06, 0.06, 0.06, 1.0},
  customTitleText = {1.0,  1.0,  1.0,  1.0},
  customTilders   = {59/255, 210/255, 237/255, 1.0},
  customBtnColor  = {1.0,  1.0,  1.0,  1.0},
  titleName       = "LootTracker",
  showBrackets    = true,
}

local function GetCustomTheme()
  local function col(key)
    if LucidUIDB and LucidUIDB[key] then return LucidUIDB[key]
    else return CUSTOM_DEFAULTS[key] end
  end
  -- Normalize tilders: color picker saves {r,g,b}, defaults are {1,2,3,4}
  -- Always return array format so tid[1]/[2]/[3] works everywhere
  local function normalizeColor(c, fallback)
    if not c then return fallback end
    if c[1] then return c end  -- already array
    if c.r then return {c.r, c.g, c.b, 1} end  -- dict → array
    return fallback
  end
  return {
    key       = "custom",
    label     = "Custom",
    bg        = normalizeColor(col("customBg"),        CUSTOM_DEFAULTS.customBg),
    border    = normalizeColor(col("customBorder"),     CUSTOM_DEFAULTS.customBorder),
    titleBg   = normalizeColor(col("customTitleBg"),   CUSTOM_DEFAULTS.customTitleBg),
    titleText = normalizeColor(col("customTitleText"),  CUSTOM_DEFAULTS.customTitleText),
    tilders   = normalizeColor(col("customTilders"),    CUSTOM_DEFAULTS.customTilders),
    btnColor  = normalizeColor(col("customBtnColor"),   CUSTOM_DEFAULTS.customBtnColor),
  }
end

NS.GetTheme = function(key)
  if key == "custom" then return GetCustomTheme() end
  return DARK_THEME
end

-- ── DB / Config ─────────────────────────────────────────────────────────────────
NS.DB_DEFAULTS = {
  position        = {"CENTER", "UIParent", "CENTER", 0, 0},
  size            = {380, 260},
  theme           = "default",
  fontSize        = 12,
  timestamps      = true,
  showSeparator   = true,
  messageSpacing  = 5,
  showMoney       = true,
  showCurrency    = true,
  showGroupLoot   = true,
  showOnlyOwnLoot = false,
  showRealmName   = true,
  autoScroll      = true,
  maxLines        = 100,
  minQuality      = 0,
  enableFade      = true,
  fadeTime        = 60,
  alpha           = 20,
  titleAlpha      = 0,
  clearOnReload   = true,
  locked          = false,
  showSocialBtn   = true,
  showSettingsBtn = true,
  showCopyBtn     = true,
  showRollsBtn    = true,
  showStatsBtn    = true,
  showMPlusBtn    = true,
  showCoinBtn     = true,
  showVoiceChatBtn = true,
  showDebugBtn    = false,
  font            = "Friz Quadrata",
  fontOutline     = "",
  rollCloseMode   = "timer",
  rollCloseDelay  = 60,
  rollMinQuality  = 0,
  lootInChatTab   = false,
  lootOwnWindow   = false,
  lootWinTransparency = 0.2,
  statsTransparency = 0.03,
  rollsTransparency = 0.03,
  statsResetOnZone = false,
  clearOnLogin    = false,
  customBg        = {0.03, 0.03, 0.03, 0.95},
  customBorder    = {0.15, 0.15, 0.15, 1.0},
  customTitleBg   = {0.06, 0.06, 0.06, 1.0},
  customTitleText = {1.0,  1.0,  1.0,  1.0},
  customTilders   = {59/255, 210/255, 237/255, 1.0},
  customBtnColor  = {1.0,  1.0,  1.0,  1.0},
  -- Chat system defaults
  chatEnabled         = true,
  chatTimestamps      = true,
  chatTimestampFormat = "%H:%M",
  chatShowSeparator   = true,
  chatTimestampColor  = {r=0.45, g=0.45, b=0.45},
  chatFontSize        = 14,
  chatFont            = "Friz Quadrata",
  chatFontOutline     = "",
  chatMessageFade     = true,
  chatFadeTime        = 60,
  chatBgAlpha         = 0.5,
  chatTabBarAlpha     = 0.5,
  chatLocked          = false,
  chatWinPos          = nil,
  chatWinSize         = nil,
  chatTabs            = nil,
  chatClassColors     = true,
  chatShortenFormat   = "none",
  chatClickableUrls   = true,
  chatEditBoxPos      = "bottom",
  chatBarPosition     = "outside_right",
  chatBarVisibility   = "always",
  chatBarIconsPerRow  = 8,
  chatBarOrder        = {"social","settings","copy","rolls","stats","mplus","coin","voicechat"},
  chatMessageSpacing  = 0,
  chatTabSeparator    = true,
  chatCombatLog       = true,
  chatTabFlash        = "whisper",
  chatWhisperTab      = true,
  chatStoreMessages   = true,
  chatRemoveOldMessages = true,
  chatHistory          = {},
  chatShowMinimap     = true,
  chatFontShadow      = false,
  chatEditBoxVisible   = false,
  chatEditBoxAccentBorder = true,
  chatTabHighlightBg   = true,
  chatAccentLine       = true,
  chatTabVisibility    = "always",
  chatColors           = {},
  chatBgColor          = {r=0, g=0, b=0},
  chatTabBarColor      = {r=0, g=0, b=0},
  chatEditBoxColor     = {r=0, g=0, b=0},
  chatTabColor         = {r=0, g=1, b=1},
  chatIconColor        = {r=0.8, g=0.8, b=0.8},
  -- QoL defaults
  qolCombatTimer       = false,
  qolCombatTimerInstance = false,
  qolCombatTimerHidePrefix = false,
  qolCombatTimerShowBg = false,
  qolCombatAlert       = false,
  qolFasterLoot        = false,
  qolSuppressWarnings  = false,
  qolEasyDestroy       = false,
  qolAutoKeystone      = false,
  qolSkipCinematics    = false,
  qolAutoSellGrey      = false,
  qolAutoRepair        = false,
  qolAutoRepairMode    = "guild",
  qolMouseRing         = false,
  qolRingColorR        = 0,
  qolRingColorG        = 0.8,
  qolRingColorB        = 0.8,
  qolMouseRingHideRMB  = false,
  qolMouseRingShowOOC  = false,
  qolMouseRingShape    = "ring.tga",
  qolMouseRingSize     = 48,
  qolMouseRingOpacity  = 0.8,
  qolTimerColorR       = 1,
  qolTimerColorG       = 1,
  qolTimerColorB       = 1,
  qolTimerFontSize     = 25,
  qolCombatEnterText   = "++Combat++",
  qolCombatLeaveText   = "--Combat--",
  qolAlertEnterR       = 1,
  qolAlertEnterG       = 0,
  qolAlertEnterB       = 0,
  qolAlertLeaveR       = 0,
  qolAlertLeaveG       = 1,
  qolAlertLeaveB       = 0,
  qolAlertFontSize     = 25,
  qolCombatTimerPos    = nil,
  qolCombatAlertPos    = nil,
  qolFpsBackup         = nil,
  -- Damage Meter
  dmEnabled            = false,
  dmLocked             = false,
  dmWinPos             = nil,
  dmMeterType          = 0,
  dmSessionType        = 1,
  dmShowInCombatOnly   = false,
  dmAutoReset          = "enter",
  dmBarHeight          = 24,
  dmBarSpacing         = 1,
  dmFontSize           = 14,
  dmUpdateInterval     = 0.5,
  dmBgAlpha            = 0.50,
  dmTitleAlpha         = 0.50,
  dmIconMode           = "spec",  -- "spec", "class", "none"
  dmValueFormat        = "both",  -- "total", "persec", "both"
  dmTextColor          = {r=1, g=1, b=1},
  dmTitleColor         = nil,  -- nil = use accent color
  dmFont               = "Friz Quadrata",
  dmTitleFontSize      = 14,
  dmFontShadow         = 2.0,
  dmTextOutline        = true,
  dmShowRealm          = true,
  dmIconsOnHover       = false,
  dmClassColors        = true,
  dmBarColor           = {r=0.5, g=0.5, b=0.5},
  dmBarBrightness      = 1.0,
  dmAlwaysShowSelf     = true,
  dmShowRank           = false,
  dmShowPercent        = false,
  dmBarBgTexture       = "Flat",
  dmAccentLine         = true,
  dmWindowBorder       = true,
  dmTitleBorder        = true,

  debugHistory         = {},
  debugWinPos          = nil,
  debugWinSize         = nil,
  -- Bags
  bagEnabled           = false,
  bagIconSize          = 37,
  bagSpacing           = 4,
  bagColumns           = 10,
  bagShowQuality       = true,
  bagShowCount         = true,
  bagShowIlvl          = true,
  bagShowJunk          = true,
  bagJunkDesaturate    = false,
  bagQuestIcon         = true,
  bagShowUpgrade       = true,
  bagNewItemGlow       = true,
  bagSortReverse       = false,
  bagSplitReagent      = false,
  bagSplitBags         = false,
  bagSplitSpacing      = 8,
  bagTransparent       = false,
  bagSlotBgAlpha       = 0.8,
  bagIlvlPos           = "BOTTOMLEFT",
  bagIlvlSize          = 10,
  bagCountPos          = "BOTTOMRIGHT",
  bagCountSize         = 10,
  bagWinPos            = nil,
  -- Gold Tracker
  gtEnabled            = true,
  gtWhisper            = true,
  gtWinPos             = nil,
  -- Mythic+
  mpEnabled            = true,
  mpTeleport           = false,
  mpWinPos3            = nil,
}

NS.DB = function(key)
  if LucidUIDB[key] == nil then LucidUIDB[key] = NS.DB_DEFAULTS[key] end
  return LucidUIDB[key]
end

NS.DBSet = function(key, val)
  LucidUIDB[key] = val
end

-- ── Helpers ────────────────────────────────────────────────────────────────────
NS.GetClassColor = function(class)
  local colors = RAID_CLASS_COLORS
  if class and colors[class] then
    local c = colors[class]
    return CreateColor(c.r, c.g, c.b):GenerateHexColorMarkup()
  end
  return "|cffffffff"
end

NS.AddSmoothScroll = function() end

-- ── Apply* functions ───────────────────────────────────────────────────────────
NS.ApplyTheme = function(themeKey)
  local t = NS.GetTheme(themeKey)
  if not NS.win then return end
  NS.win:SetBackdropColor(unpack(t.bg))
  NS.win:SetBackdropBorderColor(unpack(t.border))
  if NS.titleTex then
    NS.titleTex:SetColorTexture(t.titleBg[1], t.titleBg[2], t.titleBg[3], t.titleBg[4])
  end
  if NS.titleText then
    NS.titleText:SetTextColor(unpack(t.titleText))
    local tid = t.tilders or {59/255, 210/255, 237/255, 1}
    local tr = tid[1] or tid.r or 59/255
    local tg = tid[2] or tid.g or 210/255
    local tb = tid[3] or tid.b or 237/255
    local hex = string.format("%02x%02x%02x",
      math.floor(tr*255), math.floor(tg*255), math.floor(tb*255))
    local tname = (LucidUIDB and LucidUIDB.titleName ~= nil) and LucidUIDB.titleName or "Loot Tracker"
    local f, r = tname:match("^(%S+)%s*(.*)")
    if f then
      NS.titleText:SetText("|cff"..hex..f.."|r"..(r ~= "" and (" |cffffffff"..r.."|r") or ""))
    else
      NS.titleText:SetText("|cff"..hex..tname.."|r")
    end
  end
  -- Icon color: use chatIconColor if set, otherwise theme btnColor
  local ic = NS.DB("chatIconColor")
  local icr, icg, icb
  if ic and type(ic) == "table" and ic.r then
    icr, icg, icb = ic.r, ic.g, ic.b
  elseif t.btnColor then
    icr, icg, icb = t.btnColor[1], t.btnColor[2], t.btnColor[3]
  else
    icr, icg, icb = 1, 1, 1
  end
  for _, tex in ipairs(NS.btnIconTextures) do
    tex:SetVertexColor(icr, icg, icb, 1)
  end
  -- Clear button text color
  if NS.clearTxtRef then
    NS.clearTxtRef:SetTextColor(icr, icg, icb, 1)
  end
  -- Lock icon: cyan = unlocked, btnColor = locked
  if NS.lockTexRef then
    local CYAN = NS.CYAN
    if NS.win and NS.win.locked then
      local bc = t.btnColor or {0.8, 0.8, 0.8}
      NS.lockTexRef:SetVertexColor(bc[1], bc[2], bc[3], 0.9)
    else
      NS.lockTexRef:SetVertexColor(CYAN[1], CYAN[2], CYAN[3], 1.0)
    end
  end
  if NS.statsWin and NS.statsWin._ApplyTheme then NS.statsWin._ApplyTheme() end

  -- Update accent lines on all windows (use NS.CYAN directly, always most current)
  local ar, ag, ab = NS.CYAN[1], NS.CYAN[2], NS.CYAN[3]
  if NS.win and NS.win._accentLine then
    NS.win._accentLine:SetColorTexture(ar, ag, ab, 0.6)
  end
  if NS.statsWin and NS.statsWin._accentLine then
    NS.statsWin._accentLine:SetColorTexture(ar, ag, ab, 0.6)
  end
  if NS.rollWin and NS.rollWin._accentLine then
    NS.rollWin._accentLine:SetColorTexture(ar, ag, ab, 0.6)
  end
  if NS.LucidMeter and NS.LucidMeter.ApplyTheme then NS.LucidMeter.ApplyTheme() end
  -- Update Bags accent
  local bagFrame = _G["LucidUIBags"]
  if bagFrame then
    if bagFrame._accentLine then bagFrame._accentLine:SetColorTexture(ar, ag, ab, 1) end
    if bagFrame._title then bagFrame._title:SetTextColor(ar, ag, ab) end
    if bagFrame._bagBar and bagFrame._bagBar._accentLine then
      bagFrame._bagBar._accentLine:SetColorTexture(ar, ag, ab, 1)
    end
    if bagFrame._reagentWin then
      if bagFrame._reagentWin._accentLine then
        bagFrame._reagentWin._accentLine:SetColorTexture(ar, ag, ab, 1)
      end
      if bagFrame._reagentWin._title then
        bagFrame._reagentWin._title:SetTextColor(ar, ag, ab)
      end
    end
    if bagFrame._reagentInlineBorder and bagFrame._reagentInlineBorder._edges then
      for _, e in ipairs(bagFrame._reagentInlineBorder._edges) do
        e:SetColorTexture(ar, ag, ab, 0.7)
      end
    end
  end
  -- Update title text on stats + rolls windows (first word accent, rest white)
  if NS.statsWin and NS.statsWin._titleTxt or NS.rollWin and NS.rollWin._titleTxt then
    local hex2 = string.format("%02x%02x%02x", math.floor(ar*255), math.floor(ag*255), math.floor(ab*255))
    local L = LucidUIL or {}
    if NS.statsWin and NS.statsWin._titleTxt then
      local name = L["Session Stats"] or "Session Stats"
      local f,r = name:match("^(%S+)%s*(.*)")
      NS.statsWin._titleTxt:SetText("|cff"..hex2..(f or name).."|r"..(r and r ~= "" and (" |cffffffff"..r.."|r") or ""))
    end
    if NS.rollWin and NS.rollWin._titleTxt then
      local name = L["LOOT ROLLS"] or "LOOT ROLLS"
      local f,r = name:match("^(%S+)%s*(.*)")
      NS.rollWin._titleTxt:SetText("|cff"..hex2..(f or name).."|r"..(r and r ~= "" and (" |cffffffff"..r.."|r") or ""))
    end
  end

  -- Session History + Detail window live accent update
  if NS.sessionHistWin and NS.sessionHistWin._ApplyTheme then NS.sessionHistWin._ApplyTheme() end
  if NS.sessionDetailWin and NS.sessionDetailWin._ApplyTheme then NS.sessionDetailWin._ApplyTheme() end
  -- MythicPlus window live accent update
  if NS.MythicPlus and NS.MythicPlus._ApplyTheme then NS.MythicPlus._ApplyTheme() end
  -- GoldTracker window live accent update
  if NS.GoldTracker and NS.GoldTracker._ApplyTheme then NS.GoldTracker._ApplyTheme() end

  NS.ApplyAlpha()
  NS.ApplyTitleAlpha()
  if NS.ApplyChatTransparency then NS.ApplyChatTransparency() end
end

NS.ApplyAlpha = function()
  if not NS.win then return end
  local t  = NS.GetTheme(NS.DB("theme"))
  -- Use lootWinTransparency if set, otherwise fall back to legacy "alpha"
  local lootTr = NS.DB("lootWinTransparency")
  local tr
  if lootTr and lootTr > 0 then
    tr = lootTr
  else
    tr = (NS.DB("alpha") or 0) / 100
  end
  NS.win:SetBackdropColor(t.bg[1], t.bg[2], t.bg[3], math.max(0.02, t.bg[4] - tr))
  NS.win:SetBackdropBorderColor(t.border[1], t.border[2], t.border[3], math.max(0.05, 1.0 - tr * 0.8))
  -- Stats window transparency
  if NS.statsWin then
    local stTr = NS.DB("statsTransparency") or 0
    NS.statsWin:SetBackdropColor(t.bg[1], t.bg[2], t.bg[3], math.max(0.02, 0.97 - stTr))
  end
  -- Rolls window transparency
  if NS.rollWin then
    local rlTr = NS.DB("rollsTransparency") or 0
    NS.rollWin:SetBackdropColor(t.bg[1], t.bg[2], t.bg[3], math.max(0.02, 0.97 - rlTr))
  end
end

NS.ApplyTitleAlpha = function()
  if not NS.win then return end
  local ta = (NS.DB("titleAlpha") or 0) / 100
  local ba = math.max(0.05, 1.0 - ta)
  if NS.titleTex  then NS.titleTex:SetAlpha(ba)  end
  if NS.titleText then NS.titleText:SetAlpha(ba) end
  for _, tex in ipairs(NS.btnIconTextures) do tex:SetAlpha(ba) end
  if NS.lockTexRef then NS.lockTexRef:SetAlpha(ba) end
end

NS.ApplyFade = function()
  if not NS.smf then return end
  if NS.DB("enableFade") then
    NS.smf:SetFading(true)
    NS.smf:SetTimeVisible(NS.DB("fadeTime"))
    NS.smf:SetFadeDuration(3)
  else
    NS.smf:SetFading(false)
  end
end

-- ── Font / StatusBar discovery (cached) ────────────────────────────────────────
local _lsmFontList    = nil  -- full list for display in dropdowns
local _lsmFontMap     = nil  -- label → path for fast lookup
local _lsmBarList     = nil  -- full list for display in dropdowns
local _lsmBarMap      = nil  -- label → path for fast lookup

local function BuildFontCache()
  local list = {
    {label="Friz Quadrata", path="Fonts/FRIZQT__.TTF"},
    {label="Arial Narrow",  path="Fonts/ARIALN.TTF"},
    {label="Morpheus",      path="Fonts/MORPHEUS.TTF"},
    {label="Skurri",        path="Fonts/skurri.TTF"},
    {label="Damage",        path="Fonts/DAMAGE.TTF"},
  }
  local existing = {}
  for _, f in ipairs(list) do existing[f.label] = true end
  local LSM = LibStub and LibStub:GetLibrary("LibSharedMedia-3.0", true)
  if LSM then
    for _, name in ipairs(LSM:List("font")) do
      if not existing[name] then
        local path = LSM:Fetch("font", name, true)
        if path then
          list[#list + 1] = {label=name, path=path}
          existing[name] = true
        end
      end
    end
    table.sort(list, function(a, b) return a.label:lower() < b.label:lower() end)
  end
  local map = {}
  for _, f in ipairs(list) do map[f.label] = f.path end
  _lsmFontList = list
  _lsmFontMap  = map
end

local function BuildBarCache()
  local list = {
    {label="Flat",            path="Interface/Buttons/WHITE8X8"},
    {label="Blizzard",        path="Interface/TargetingFrame/UI-StatusBar"},
    {label="Blizzard Raid",   path="Interface/RaidFrame/Raid-Bar-Hp-Fill"},
    {label="Blizzard Skills", path="Interface/PaperDollInfoFrame/UI-Character-Skills-Bar"},
  }
  local existing = {}
  for _, f in ipairs(list) do existing[f.label] = true end
  local LSM = LibStub and LibStub:GetLibrary("LibSharedMedia-3.0", true)
  if LSM then
    for _, name in ipairs(LSM:List("statusbar")) do
      if not existing[name] then
        local path = LSM:Fetch("statusbar", name, true)
        if path then
          list[#list + 1] = {label=name, path=path}
          existing[name] = true
        end
      end
    end
    table.sort(list, function(a, b) return a.label:lower() < b.label:lower() end)
  end
  local map = {}
  for _, f in ipairs(list) do map[f.label] = f.path end
  _lsmBarList = list
  _lsmBarMap  = map
end

-- Invalidate caches when LSM registers new media (rare, but possible at login)
NS.InvalidateLSMCache = function()
  _lsmFontList = nil; _lsmFontMap = nil
  _lsmBarList  = nil; _lsmBarMap  = nil
end

-- Re-apply all fonts across all modules (called after LSM cache invalidation)
NS.ReapplyAllFonts = function()
  NS.InvalidateLSMCache()

  -- Chat font (uses chatFont key, falls back to font)
  local chatFontPath = NS.GetFontPath(NS.DB("chatFont") or NS.DB("font"))
  local chatFontSize = NS.DB("chatFontSize") or 14
  local chatFontOutline = NS.DB("chatFontOutline") or ""
  local chatFontShadow = NS.DB("chatFontShadow")
  -- Chat message display
  if NS.chatDisplay and NS.chatDisplay.SetFont then
    NS.chatDisplay:SetFont(chatFontPath, chatFontSize, chatFontOutline)
    if NS.chatDisplay.SetShadowOffset then
      NS.chatDisplay:SetShadowOffset(chatFontShadow and 1 or 0, chatFontShadow and -1 or 0)
    end
  end
  -- Chat SMF (scrolling message frame)
  if NS.smf then
    NS.smf:SetFont(chatFontPath, chatFontSize, chatFontOutline)
  end

  -- LucidMeter: apply font to all bars immediately
  if NS.LucidMeter and NS.LucidMeter.windows then
    local dmFontPath = NS.GetFontPath(NS.DB("dmFont"))
    local dmFontSize = NS.DB("dmFontSize") or 11
    local dmFontFlags = NS.DB("dmTextOutline") and "OUTLINE" or ""
    for _, w in ipairs(NS.LucidMeter.windows) do
      if w.titleText then
        w.titleText:SetFont(dmFontPath, NS.DB("dmTitleFontSize") or 10, dmFontFlags)
      end
      for _, bar in ipairs(w.bars or {}) do
        bar._lastConfigStamp = nil
        if bar._name then bar._name:SetFont(dmFontPath, dmFontSize, dmFontFlags) end
        if bar._value then bar._value:SetFont(dmFontPath, dmFontSize, dmFontFlags) end
        if bar._pct then bar._pct:SetFont(dmFontPath, dmFontSize, dmFontFlags) end
        if bar._rankFS then bar._rankFS:SetFont(dmFontPath, dmFontSize, dmFontFlags) end
      end
      if w._selfBar then
        w._selfBar._setupDone = false
        if w._selfBar._name then w._selfBar._name:SetFont(dmFontPath, dmFontSize, dmFontFlags) end
        if w._selfBar._value then w._selfBar._value:SetFont(dmFontPath, dmFontSize, dmFontFlags) end
      end
      -- Total bar
      if w._totalBarLabel then w._totalBarLabel:SetFont(dmFontPath, dmFontSize, dmFontFlags) end
      if w._totalBarValue then w._totalBarValue:SetFont(dmFontPath, dmFontSize, dmFontFlags) end
    end
  end

  -- LootTracker window title
  if NS.win and NS.titleText then
    local lootFont = NS.GetFontPath(NS.DB("font"))
    local lootSize = NS.DB("fontSize") or 11
    local lootFlags = NS.DB("fontOutline") or ""
    NS.titleText:SetFont(lootFont, lootSize, lootFlags)
  end
end

-- Hook LSM callback to pick up fonts registered after our cache was built
C_Timer.After(0, function()
  local LSM = LibStub and LibStub:GetLibrary("LibSharedMedia-3.0", true)
  if LSM and LSM.RegisterCallback then
    LSM:RegisterCallback("LibSharedMedia_Registered", function(_, mediatype)
      if mediatype == "font" or mediatype == "statusbar" then
        NS.ReapplyAllFonts()
      end
    end)
  end
end)

-- Re-apply fonts after PLAYER_ENTERING_WORLD (all addons have loaded by then)
local fontFixFrame = CreateFrame("Frame")
fontFixFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
fontFixFrame:SetScript("OnEvent", function(self)
  self:UnregisterEvent("PLAYER_ENTERING_WORLD")
  C_Timer.After(0.1, function() NS.ReapplyAllFonts() end)
end)

NS.GetLSMFonts = function()
  if not _lsmFontList then BuildFontCache() end
  return _lsmFontList
end

NS.GetLSMStatusBars = function()
  if not _lsmBarList then BuildBarCache() end
  return _lsmBarList
end

NS.GetBarTexturePath = function(key)
  if not key or key == "Flat" then return "Interface/Buttons/WHITE8X8" end
  if not _lsmBarMap then BuildBarCache() end
  return _lsmBarMap[key] or "Interface/Buttons/WHITE8X8"
end

NS.GetFontPath = function(key)
  if not key or key == "default" then return "Fonts/FRIZQT__.TTF" end
  if not _lsmFontMap then BuildFontCache() end
  return _lsmFontMap[key] or "Fonts/FRIZQT__.TTF"
end

NS.ApplyFontSize = function()
  if not NS.smf then return end
  NS.smf:SetFont(NS.GetFontPath(NS.DB("font")), NS.DB("fontSize"), NS.DB("fontOutline") or "")
end

NS.ApplySpacing = function()
  if not NS.smf then return end
  NS.smf:SetSpacing(NS.DB("messageSpacing"))
end