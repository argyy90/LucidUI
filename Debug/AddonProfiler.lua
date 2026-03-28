-- LucidUI Addon Profiler
-- Shows CPU and Memory usage per addon
-- Usage: /luiperf

local NS = LucidUINS
local CYAN = NS.CYAN

local profilerWin = nil
local rows = {}
local MAX_ROWS = 30
local ROW_H = 16
local TITLE_H = 24
local UPDATE_INTERVAL = 2
local sortMode = "memory" -- "memory" or "cpu"
local cpuEnabled = false

local function FormatMemory(kb)
  if kb >= 1024 then
    return string.format("%.1f MB", kb / 1024)
  else
    return string.format("%.0f KB", kb)
  end
end

local function FormatCPU(ms)
  if ms >= 1000 then
    return string.format("%.1fs", ms / 1000)
  elseif ms >= 1 then
    return string.format("%.1fms", ms)
  else
    return string.format("%.2fms", ms)
  end
end

local function GetAddonData()
  UpdateAddOnMemoryUsage()
  if cpuEnabled then UpdateAddOnCPUUsage() end

  local data = {}
  local totalMem = 0
  local totalCPU = 0

  for i = 1, C_AddOns.GetNumAddOns() do
    local name, _, _, enabled = C_AddOns.GetAddOnInfo(i)
    if enabled then
      local mem = GetAddOnMemoryUsage(i) -- no C_ equivalent yet
      local cpu = cpuEnabled and GetAddOnCPUUsage(i) or 0
      totalMem = totalMem + mem
      totalCPU = totalCPU + cpu
      table.insert(data, {name = name, memory = mem, cpu = cpu})
    end
  end

  if sortMode == "memory" then
    table.sort(data, function(a, b) return a.memory > b.memory end)
  else
    table.sort(data, function(a, b) return a.cpu > b.cpu end)
  end

  return data, totalMem, totalCPU
end

local function CreateRow(parent, index)
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(ROW_H)
  row:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -(index - 1) * ROW_H)
  row:SetPoint("RIGHT", parent, "RIGHT", -4, 0)

  local rank = row:CreateFontString(nil, "OVERLAY")
  rank:SetFont("Fonts/FRIZQT__.TTF", 10, "")
  rank:SetPoint("LEFT", 2, 0)
  rank:SetWidth(20)
  rank:SetJustifyH("RIGHT")
  rank:SetTextColor(0.5, 0.5, 0.5)

  local name = row:CreateFontString(nil, "OVERLAY")
  name:SetFont("Fonts/FRIZQT__.TTF", 10, "")
  name:SetPoint("LEFT", rank, "RIGHT", 6, 0)
  name:SetWidth(160)
  name:SetJustifyH("LEFT")

  local memText = row:CreateFontString(nil, "OVERLAY")
  memText:SetFont("Fonts/FRIZQT__.TTF", 10, "")
  memText:SetPoint("RIGHT", row, "RIGHT", -80, 0)
  memText:SetWidth(70)
  memText:SetJustifyH("RIGHT")

  local cpuText = row:CreateFontString(nil, "OVERLAY")
  cpuText:SetFont("Fonts/FRIZQT__.TTF", 10, "")
  cpuText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
  cpuText:SetWidth(70)
  cpuText:SetJustifyH("RIGHT")

  local bar = row:CreateTexture(nil, "BACKGROUND")
  bar:SetPoint("TOPLEFT", 0, -1)
  bar:SetPoint("BOTTOMLEFT", 0, 1)
  bar:SetColorTexture(1, 1, 1, 0.08)

  row._rank = rank
  row._name = name
  row._mem = memText
  row._cpu = cpuText
  row._bar = bar
  return row
end

local function RefreshDisplay()
  if not profilerWin or not profilerWin:IsShown() then return end

  local data, totalMem, totalCPU = GetAddonData()

  -- Update title
  profilerWin._titleText:SetText(string.format("Addon Profiler — Total: %s", FormatMemory(totalMem)))

  -- Update header
  profilerWin._memHeader:SetTextColor(sortMode == "memory" and CYAN[1] or 0.6, sortMode == "memory" and CYAN[2] or 0.6, sortMode == "memory" and CYAN[3] or 0.6)
  profilerWin._cpuHeader:SetTextColor(sortMode == "cpu" and CYAN[1] or 0.6, sortMode == "cpu" and CYAN[2] or 0.6, sortMode == "cpu" and CYAN[3] or 0.6)

  local maxVal = 0
  for i = 1, math.min(#data, MAX_ROWS) do
    if sortMode == "memory" then
      maxVal = math.max(maxVal, data[i].memory)
    else
      maxVal = math.max(maxVal, data[i].cpu)
    end
  end

  for i = 1, MAX_ROWS do
    local row = rows[i]
    if not row then
      row = CreateRow(profilerWin._content, i)
      rows[i] = row
    end

    if i <= #data then
      local d = data[i]
      local isLucid = d.name == "LucidUI"
      local ratio = maxVal > 0 and ((sortMode == "memory" and d.memory or d.cpu) / maxVal) or 0

      row._rank:SetText(i .. ".")
      row._name:SetText(d.name)
      row._mem:SetText(FormatMemory(d.memory))
      row._cpu:SetText(cpuEnabled and FormatCPU(d.cpu) or "—")

      -- Highlight LucidUI
      if isLucid then
        row._name:SetTextColor(CYAN[1], CYAN[2], CYAN[3])
        row._mem:SetTextColor(CYAN[1], CYAN[2], CYAN[3])
        row._cpu:SetTextColor(CYAN[1], CYAN[2], CYAN[3])
        row._rank:SetTextColor(CYAN[1], CYAN[2], CYAN[3])
        row._bar:SetColorTexture(CYAN[1], CYAN[2], CYAN[3], 0.15)
      else
        row._name:SetTextColor(0.9, 0.9, 0.9)
        row._mem:SetTextColor(0.7, 0.7, 0.7)
        row._cpu:SetTextColor(0.7, 0.7, 0.7)
        row._rank:SetTextColor(0.5, 0.5, 0.5)
        row._bar:SetColorTexture(1, 1, 1, 0.06)
      end

      row._bar:SetWidth(math.max(1, ratio * (profilerWin:GetWidth() - 8)))
      row:Show()
    else
      row:Hide()
    end
  end

  -- CPU warning
  if not cpuEnabled then
    profilerWin._cpuWarn:Show()
  else
    profilerWin._cpuWarn:Hide()
  end
end

local function BuildProfilerWindow()
  if profilerWin then profilerWin:Show(); RefreshDisplay(); return end

  local cr, cg, cb = CYAN[1], CYAN[2], CYAN[3]

  profilerWin = CreateFrame("Frame", "LucidUIProfiler", UIParent, "BackdropTemplate")
  profilerWin:SetSize(380, TITLE_H + MAX_ROWS * ROW_H + 50)
  profilerWin:SetPoint("CENTER")
  profilerWin:SetFrameStrata("DIALOG")
  profilerWin:SetMovable(true)
  profilerWin:SetClampedToScreen(true)
  profilerWin:EnableMouse(true)
  profilerWin:RegisterForDrag("LeftButton")
  profilerWin:SetScript("OnDragStart", profilerWin.StartMoving)
  profilerWin:SetScript("OnDragStop", profilerWin.StopMovingOrSizing)
  profilerWin:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
  profilerWin:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
  profilerWin:SetBackdropBorderColor(0.15, 0.15, 0.15, 1)

  -- Title
  local titleBg = profilerWin:CreateTexture(nil, "ARTWORK")
  titleBg:SetPoint("TOPLEFT"); titleBg:SetPoint("TOPRIGHT"); titleBg:SetHeight(TITLE_H)
  titleBg:SetColorTexture(0.08, 0.08, 0.08, 1)

  local titleText = profilerWin:CreateFontString(nil, "OVERLAY")
  titleText:SetFont("Fonts/FRIZQT__.TTF", 11, "")
  titleText:SetPoint("LEFT", titleBg, "LEFT", 8, 0)
  titleText:SetTextColor(cr, cg, cb)
  profilerWin._titleText = titleText

  -- Close button
  local closeBtn = CreateFrame("Button", nil, profilerWin)
  closeBtn:SetSize(16, 16)
  closeBtn:SetPoint("TOPRIGHT", -4, -4)
  closeBtn:SetNormalFontObject("GameFontNormal")
  closeBtn:SetText("X")
  closeBtn:GetFontString():SetFont("Fonts/FRIZQT__.TTF", 11, "OUTLINE")
  closeBtn:GetFontString():SetTextColor(0.6, 0.6, 0.6)
  closeBtn:SetScript("OnClick", function() profilerWin:Hide() end)
  closeBtn:SetScript("OnEnter", function(self) self:GetFontString():SetTextColor(1, 0.3, 0.3) end)
  closeBtn:SetScript("OnLeave", function(self) self:GetFontString():SetTextColor(0.6, 0.6, 0.6) end)

  -- Column headers (clickable for sorting)
  local headerY = -(TITLE_H + 2)

  local memHeader = profilerWin:CreateFontString(nil, "OVERLAY")
  memHeader:SetFont("Fonts/FRIZQT__.TTF", 10, "OUTLINE")
  memHeader:SetPoint("TOPRIGHT", profilerWin, "TOPRIGHT", -80, headerY)
  memHeader:SetText("Memory")
  profilerWin._memHeader = memHeader

  local memHeaderBtn = CreateFrame("Button", nil, profilerWin)
  memHeaderBtn:SetAllPoints(memHeader)
  memHeaderBtn:SetSize(60, 14)
  memHeaderBtn:SetScript("OnClick", function() sortMode = "memory"; RefreshDisplay() end)

  local cpuHeader = profilerWin:CreateFontString(nil, "OVERLAY")
  cpuHeader:SetFont("Fonts/FRIZQT__.TTF", 10, "OUTLINE")
  cpuHeader:SetPoint("TOPRIGHT", profilerWin, "TOPRIGHT", -10, headerY)
  cpuHeader:SetText("CPU")
  profilerWin._cpuHeader = cpuHeader

  local cpuHeaderBtn = CreateFrame("Button", nil, profilerWin)
  cpuHeaderBtn:SetAllPoints(cpuHeader)
  cpuHeaderBtn:SetSize(60, 14)
  cpuHeaderBtn:SetScript("OnClick", function()
    if not cpuEnabled then
      local _SetCVar = (C_CVar and C_CVar.SetCVar) or SetCVar
      pcall(_SetCVar, "scriptProfile", "1")
      ReloadUI()
    else
      sortMode = "cpu"
      RefreshDisplay()
    end
  end)

  -- Content area
  local content = CreateFrame("Frame", nil, profilerWin)
  content:SetPoint("TOPLEFT", 0, -(TITLE_H + 18))
  content:SetPoint("BOTTOMRIGHT", 0, 24)
  profilerWin._content = content

  -- CPU warning
  local cpuWarn = profilerWin:CreateFontString(nil, "OVERLAY")
  cpuWarn:SetFont("Fonts/FRIZQT__.TTF", 9, "")
  cpuWarn:SetPoint("BOTTOMLEFT", 8, 6)
  cpuWarn:SetTextColor(1, 0.82, 0, 0.8)
  cpuWarn:SetText("CPU tracking disabled. Click 'CPU' header to enable (requires reload).")
  profilerWin._cpuWarn = cpuWarn

  -- Accent line
  local accent = profilerWin:CreateTexture(nil, "ARTWORK")
  accent:SetPoint("TOPLEFT", 0, 0); accent:SetPoint("TOPRIGHT", 0, 0); accent:SetHeight(1)
  accent:SetColorTexture(cr, cg, cb, 1)

  -- Check if CPU profiling is enabled
  local _GetCVar = (C_CVar and C_CVar.GetCVar) or GetCVar
  cpuEnabled = _GetCVar("scriptProfile") == "1"

  -- Auto-refresh ticker (start on show, cancel on hide)
  local _profTicker = nil
  profilerWin:SetScript("OnShow", function()
    if not _profTicker then
      _profTicker = C_Timer.NewTicker(UPDATE_INTERVAL, RefreshDisplay)
    end
    RefreshDisplay()
  end)
  profilerWin:SetScript("OnHide", function()
    if _profTicker then _profTicker:Cancel(); _profTicker = nil end
  end)

  RefreshDisplay()
end

-- Slash command
SLASH_LUIPERF1 = "/luiperf"
SlashCmdList["LUIPERF"] = function()
  BuildProfilerWindow()
end
