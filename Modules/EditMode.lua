-- LucidUI Modules/EditMode.lua
-- Edit Mode integration: hooks into Blizzard's CooldownViewer system
-- to reposition, resize, and restyle buff/cooldown frames.

local NS = LucidUINS
NS.EditMode = NS.EditMode or {}
local EM = NS.EditMode

-- ── CooldownViewer frame names ──────────────────────────────────────────
local VIEWER_NAMES = {
  "EssentialCooldownViewer",
  "UtilityCooldownViewer",
  "BuffIconCooldownViewer",
  "BuffBarCooldownViewer",
}

-- ── State ───────────────────────────────────────────────────────────────
local anchorContainers = {}  -- [viewerName] = container frame
local isEditMode = false
local initialized = false

-- ── Helpers ─────────────────────────────────────────────────────────────
local function IsCooldownViewerSystem(frame)
  local cvEnum = Enum and Enum.EditModeSystem and Enum.EditModeSystem.CooldownViewer
  return cvEnum and frame and frame.system == cvEnum
end

local function GetViewer(name)
  return _G[name]
end

-- ── Anchor containers ───────────────────────────────────────────────────
-- Wrap each CooldownViewer in a container frame we control
local function GetOrCreateContainer(viewer)
  local vName = viewer:GetName()
  if anchorContainers[vName] then return anchorContainers[vName] end

  local container = CreateFrame("Frame", "LucidUI_" .. vName, UIParent)
  container:SetFrameStrata("MEDIUM")
  container:SetClampedToScreen(true)
  container:SetSize(viewer:GetWidth(), viewer:GetHeight())

  -- Copy position from viewer
  local p, rel, relP, x, y = viewer:GetPoint()
  if p then
    container:SetPoint(p, rel, relP, x, y)
  else
    container:SetPoint("CENTER")
  end

  anchorContainers[vName] = container
  return container
end

-- ── Reparent viewer items to our container ───────────────────────────────
local function ReparentViewerFrames(viewer)
  if not viewer or not viewer.itemFramePool then return end
  local container = GetOrCreateContainer(viewer)

  for frame in viewer.itemFramePool:EnumerateActive() do
    frame:SetParent(container)
  end
end

-- ── Edit Mode hooks ─────────────────────────────────────────────────────
local function SetupEditModeHooks()
  if not EditModeManagerFrame then return end

  -- Detect Edit Mode enter/exit
  hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function()
    isEditMode = true
    EM:OnEditModeEnter()
  end)
  hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function()
    isEditMode = false
    EM:OnEditModeExit()
  end)

  -- Hook settings dialog to intercept CooldownViewer selection
  if EditModeSystemSettingsDialog then
    hooksecurefunc(EditModeSystemSettingsDialog, "AttachToSystemFrame", function(dialog, systemFrame)
      if not IsCooldownViewerSystem(systemFrame) then return end
      -- Only block if our modules are actually managing these frames
      if not NS.IsCDMEnabled() then return end
      EM:ShowLockOverlay(systemFrame)
    end)
  end

  -- Hook SelectSystem/HighlightSystem on each viewer
  for _, name in ipairs(VIEWER_NAMES) do
    local viewer = GetViewer(name)
    if viewer then
      if viewer.SelectSystem then
        hooksecurefunc(viewer, "SelectSystem", function(frame)
          if not IsCooldownViewerSystem(frame) then return end
          if not NS.IsCDMEnabled() then return end
          EM:OnViewerSelected(frame)
        end)
      end
      if viewer.HighlightSystem then
        hooksecurefunc(viewer, "HighlightSystem", function(frame)
          if IsCooldownViewerSystem(frame) then
            EM:OnViewerHighlight(frame)
          end
        end)
      end
      if viewer.ClearHighlight then
        hooksecurefunc(viewer, "ClearHighlight", function(frame)
          EM:OnViewerClearHighlight(frame)
        end)
      end
    end
  end
end

-- ── Lock overlay (shown when user clicks a CooldownViewer in Edit Mode) ──
local lockOverlay = nil

function EM:ShowLockOverlay(systemFrame)
  if not lockOverlay then
    lockOverlay = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    lockOverlay:SetFrameStrata("FULLSCREEN_DIALOG")
    lockOverlay:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8"})
    lockOverlay:SetBackdropColor(0, 0, 0, 0.7)
    local fs = lockOverlay:CreateFontString(nil, "OVERLAY")
    fs:SetFont("Fonts/FRIZQT__.TTF", 11, "OUTLINE")
    fs:SetPoint("CENTER"); fs:SetTextColor(1, 0.82, 0)
    fs:SetText("Managed by LucidUI\nUse /lui settings to configure")
    lockOverlay._text = fs
  end
  local sel = systemFrame.Selection
  if sel then
    lockOverlay:SetAllPoints(sel)
    lockOverlay:SetFrameLevel(sel:GetFrameLevel() + 5)
  else
    lockOverlay:SetAllPoints(systemFrame)
  end
  lockOverlay:Show()
  C_Timer.After(2.5, function() if lockOverlay then lockOverlay:Hide() end end)
end

-- ── Lock CooldownViewer frames (prevent dragging in Edit Mode) ──────────
function EM:LockViewerFrames()
  if not NS.IsCDMEnabled() then return end
  for _, name in ipairs(VIEWER_NAMES) do
    local viewer = GetViewer(name)
    if viewer and IsCooldownViewerSystem(viewer) then
      viewer:SetMovable(false)
      if viewer.Selection then
        viewer.Selection:SetScript("OnDragStart", nil)
        viewer.Selection:SetScript("OnDragStop", nil)
      end
    end
  end
end

-- ── Edit Mode callbacks ─────────────────────────────────────────────────
function EM:OnEditModeEnter()
  self:LockViewerFrames()
  -- Show container borders for visual feedback
  for vName, container in pairs(anchorContainers) do
    if not container._editBorder then
      container._editBorder = container:CreateTexture(nil, "OVERLAY", nil, 7)
      container._editBorder:SetAllPoints()
      local ar, ag, ab = NS.ChatGetAccentRGB()
      container._editBorder:SetColorTexture(ar, ag, ab, 0.15)
    end
    container._editBorder:Show()
  end
end

function EM:OnEditModeExit()
  for _, container in pairs(anchorContainers) do
    if container._editBorder then container._editBorder:Hide() end
  end
end

function EM:OnViewerSelected(frame)
  self:ShowLockOverlay(frame)
end

function EM:OnViewerHighlight(frame)
  local vName = frame:GetName()
  local container = anchorContainers[vName]
  if container and container._editBorder then
    local ar, ag, ab = NS.ChatGetAccentRGB()
    container._editBorder:SetColorTexture(ar, ag, ab, 0.3)
  end
end

function EM:OnViewerClearHighlight(frame)
  local vName = frame:GetName()
  local container = anchorContainers[vName]
  if container and container._editBorder then
    local ar, ag, ab = NS.ChatGetAccentRGB()
    container._editBorder:SetColorTexture(ar, ag, ab, 0.15)
  end
end

-- ── Buff Bar layout ─────────────────────────────────────────────────────
function EM:PositionBuffBarFrames(viewerName, opts)
  local viewer = GetViewer(viewerName)
  if not viewer or not viewer.itemFramePool then return end

  local container = GetOrCreateContainer(viewer)
  local width = opts.width or 200
  local height = opts.height or 20
  local spacing = opts.spacing or 2
  local growDir = opts.grow or "DOWN"
  local texture = opts.texture or "Flat"

  container:SetWidth(width)

  local bars = {}
  for frame in viewer.itemFramePool:EnumerateActive() do
    if frame:IsShown() then
      bars[#bars + 1] = frame
    end
  end

  local yOff = 0
  for i, frame in ipairs(bars) do
    frame:SetParent(container)
    frame:SetSize(width, height)
    frame:ClearAllPoints()

    if growDir == "DOWN" then
      frame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -yOff)
    else
      frame:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, yOff)
    end

    -- Style the bar if it has Bar/Icon children
    if frame.Bar then
      frame.Bar:SetStatusBarTexture(NS.GetBarTexturePath(texture))
    end

    yOff = yOff + height + spacing
  end

  container:SetHeight(math.max(1, yOff - spacing))
end

-- ── Buff Icon layout ────────────────────────────────────────────────────
function EM:PositionBuffIconFrames(viewerName, opts)
  local viewer = GetViewer(viewerName)
  if not viewer or not viewer.itemFramePool then return end

  local container = GetOrCreateContainer(viewer)
  local iconSize = opts.iconSize or 36
  local spacing = opts.spacing or 2
  local perRow = opts.perRow or 10
  local growDir = opts.grow or "RIGHT"

  local icons = {}
  for frame in viewer.itemFramePool:EnumerateActive() do
    if frame:IsShown() then
      icons[#icons + 1] = frame
    end
  end

  -- Sort by layoutIndex for deterministic order
  table.sort(icons, function(a, b)
    local aIdx = a.layoutIndex or 0
    local bIdx = b.layoutIndex or 0
    return aIdx < bIdx
  end)

  local row, col = 0, 0
  for _, frame in ipairs(icons) do
    frame:SetParent(container)
    frame:SetSize(iconSize, iconSize)
    frame:ClearAllPoints()

    local xOff = col * (iconSize + spacing)
    local yOff = row * (iconSize + spacing)

    if growDir == "RIGHT" then
      frame:SetPoint("TOPLEFT", container, "TOPLEFT", xOff, -yOff)
    elseif growDir == "LEFT" then
      frame:SetPoint("TOPRIGHT", container, "TOPRIGHT", -xOff, -yOff)
    end

    col = col + 1
    if col >= perRow then col = 0; row = row + 1 end
  end

  local totalCols = math.min(#icons, perRow)
  local totalRows = math.ceil(#icons / perRow)
  container:SetSize(
    totalCols * (iconSize + spacing) - spacing,
    totalRows * (iconSize + spacing) - spacing
  )
end

-- ── Apply recommended settings to CooldownViewer ────────────────────────
function EM:ApplyRecommendedSettings()
  -- Set CooldownViewer to "Always Visible" + "Show Timer" + "Hide When Inactive"
  if not C_EditMode then return end
  local layouts = C_EditMode.GetLayouts()
  if not layouts then return end
  -- Note: modifying layouts requires careful handling — defer to user for now
end

-- ── Initialize ──────────────────────────────────────────────────────────
local function Init()
  if initialized then return end
  initialized = true

  -- Wait for Blizzard_EditMode addon to load
  if C_AddOns and C_AddOns.IsAddOnLoaded("Blizzard_EditMode") then
    SetupEditModeHooks()
  else
    EventUtil.ContinueOnAddOnLoaded("Blizzard_EditMode", function()
      SetupEditModeHooks()
    end)
  end

  -- Initial reparent of viewer frames
  C_Timer.After(0.8, function()
    for _, name in ipairs(VIEWER_NAMES) do
      local viewer = GetViewer(name)
      if viewer then
        ReparentViewerFrames(viewer)
      end
    end
  end)
end

-- ── Event frame ─────────────────────────────────────────────────────────
local evFrame = CreateFrame("Frame")
evFrame:RegisterEvent("PLAYER_LOGIN")
evFrame:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    C_Timer.After(0.5, Init)
  end
end)

-- ── Public API ──────────────────────────────────────────────────────────
function EM:IsEditMode() return isEditMode end
function EM:GetContainer(viewerName) return anchorContainers[viewerName] end
function EM:GetViewerNames() return VIEWER_NAMES end
