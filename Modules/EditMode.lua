-- LucidUI Modules/EditMode.lua
-- Edit Mode integration: hooks into Blizzard's CooldownViewer system
-- to lock/overlay managed viewers and prevent Edit Mode from moving them.
--
-- Follows Ayije CDM's pattern:
--   • Hook EditModeManagerFrame Show/Hide (not the non-existent EnterEditMode/ExitEditMode)
--   • Hook SelectSystem/HighlightSystem/ClearHighlight on each viewer
--   • Show a lock overlay when user tries to click a managed viewer in Edit Mode
--   • Apply recommended CooldownViewer settings via C_EditMode API

local NS = LucidUINS
NS.EditMode = NS.EditMode or {}
local EM = NS.EditMode

-- Ensure VehicleLeaveButtonHolder exists early (our viewer reparenting removes it from the frame tree)
if not _G["VehicleLeaveButtonHolder"] then
  CreateFrame("Frame", "VehicleLeaveButtonHolder", UIParent):Hide()
end

-- ── CooldownViewer frame names ──────────────────────────────────────────
local VIEWER_NAMES = {
  "EssentialCooldownViewer",
  "UtilityCooldownViewer",
  "BuffIconCooldownViewer",
  "BuffBarCooldownViewer",
}

-- ── State ───────────────────────────────────────────────────────────────
local isEditMode       = false
local lockSetup        = false   -- guard against double-setup
local noticeShown      = false

-- Per-selection overlay state (weak-key so we don't hold viewer frames alive)
local selectionState = setmetatable({}, { __mode = "k" })

-- ── Helpers ─────────────────────────────────────────────────────────────
local function IsCooldownViewerSystem(frame)
  local cvEnum = Enum and Enum.EditModeSystem and Enum.EditModeSystem.CooldownViewer
  return cvEnum and frame and frame.system == cvEnum
end

local function GetSelState(selection)
  if not selectionState[selection] then selectionState[selection] = {} end
  return selectionState[selection]
end

local function GetViewer(name) return _G[name] end

-- ── Lock overlay per selection frame ────────────────────────────────────
-- Creates a text overlay on the CooldownViewer's Selection highlight frame
-- telling the user to use /lui settings instead of Edit Mode.
local function EnsureLockOverlay(selection)
  if not selection then return end
  local st = GetSelState(selection)
  if st.overlay then return end

  local ov = CreateFrame("Frame", nil, UIParent)
  ov:SetAllPoints(selection)
  ov:SetFrameStrata("FULLSCREEN_DIALOG")
  ov:SetFrameLevel(selection:GetFrameLevel() + 5)
  st.overlay = ov

  local fs = ov:CreateFontString(nil, "OVERLAY")
  fs:SetFont("Fonts/FRIZQT__.TTF", 14, "OUTLINE")
  fs:SetPoint("CENTER"); fs:SetJustifyH("CENTER"); fs:SetWordWrap(true)
  fs:SetTextColor(1, 0.82, 0)
  fs:SetWidth(selection:GetWidth() - 12)
  fs:SetText("Managed by LucidUI\nUse /lui to configure")
  st.text = fs
end

local function ShowLockOverlay(systemFrame)
  local selection = systemFrame and systemFrame.Selection
  if not selection then return end
  EnsureLockOverlay(selection)
  local st = GetSelState(selection)
  if st.overlay then st.overlay:Show() end

  -- Auto-hide after 2.5s (use a cancellable token to avoid stacking timers)
  st.lockToken = (st.lockToken or 0) + 1
  local token = st.lockToken
  C_Timer.After(2.5, function()
    if st.lockToken == token and st.overlay then st.overlay:Hide() end
  end)
end

local function HideLockOverlay(systemFrame)
  local selection = systemFrame and systemFrame.Selection
  if not selection then return end
  local st = selectionState[selection]
  if st and st.overlay then st.overlay:Hide() end
end

-- Print a notice once per session
local function ShowLockNotice()
  if noticeShown then return end
  noticeShown = true
  print("|cffffd200LucidUI:|r CooldownViewer settings are managed by /lui. Edit Mode positioning is disabled.")
end

-- ── Lock all CooldownViewer frames ──────────────────────────────────────
local function LockViewerFrames()
  if not NS.IsCDMEnabled() then return end
  for _, name in ipairs(VIEWER_NAMES) do
    local viewer = GetViewer(name)
    if viewer and IsCooldownViewerSystem(viewer) then
      if not InCombatLockdown() then
        viewer:SetMovable(false)
      end
      local selection = viewer.Selection
      if selection and not InCombatLockdown() then
        selection:SetScript("OnDragStart", nil)
        selection:SetScript("OnDragStop", nil)
      end
    end
  end
end

-- ── Selection overlay alignment ─────────────────────────────────────────
-- Keep each viewer's Selection frame aligned with LucidUI's container
-- so Edit Mode highlights show the container's actual position/size.
local function UpdateSelectionOverlay(vName)
  if InCombatLockdown() then return end
  local viewer = GetViewer(vName)
  if not viewer then return end
  local selection = viewer.Selection
  if not selection then return end
  -- Use LucidUI container if available; otherwise keep Selection on viewer itself
  local container = (NS.Cooldowns and NS.Cooldowns._containers and NS.Cooldowns._containers[vName])
               or   (NS.BuffBar   and NS.BuffBar._containers   and NS.BuffBar._containers[vName])
  if container then
    selection:ClearAllPoints()
    selection:SetAllPoints(container)
    selection:SetFrameStrata("MEDIUM")
    selection:SetFrameLevel(container:GetFrameLevel() + 2)
  end
end

function EM:UpdateSelectionOverlays()
  for _, name in ipairs(VIEWER_NAMES) do
    UpdateSelectionOverlay(name)
  end
end

-- ── Hook per-viewer Edit Mode interactions ───────────────────────────────
local function SetupViewerHooks(viewer, vName)
  -- Intercept SelectSystem: hide Blizzard's settings dialog, show our lock text
  if viewer.SelectSystem then
    hooksecurefunc(viewer, "SelectSystem", function(sf)
      if not IsCooldownViewerSystem(sf) then return end
      if not NS.IsCDMEnabled() then return end
      sf:SetMovable(false)
      -- Hide the settings dialog Blizzard would open
      if EditModeSystemSettingsDialog and EditModeSystemSettingsDialog.attachedToSystem == sf then
        EditModeSystemSettingsDialog:Hide()
      end
      ShowLockOverlay(sf)
      ShowLockNotice()
    end)
  end

  -- Intercept HighlightSystem: show lock overlay on hover
  if viewer.HighlightSystem then
    hooksecurefunc(viewer, "HighlightSystem", function(sf)
      if not IsCooldownViewerSystem(sf) then return end
      if not NS.IsCDMEnabled() then return end
      UpdateSelectionOverlay(vName)
    end)
  end

  -- Clear lock overlay when selection is released
  if viewer.ClearHighlight then
    hooksecurefunc(viewer, "ClearHighlight", function(sf)
      HideLockOverlay(sf)
    end)
  end
end

-- ── Hook EditModeSystemSettingsDialog.AttachToSystemFrame ────────────────
local function SetupSettingsDialogHook()
  local dialog = _G.EditModeSystemSettingsDialog
  if not dialog then return end
  hooksecurefunc(dialog, "AttachToSystemFrame", function(dlg, systemFrame)
    if not IsCooldownViewerSystem(systemFrame) then return end
    if not NS.IsCDMEnabled() then return end
    -- Hide the dialog immediately — we manage these via /lui
    dlg:Hide()
    ShowLockOverlay(systemFrame)
    ShowLockNotice()
  end)
end

-- ── Main setup (called once after Blizzard_EditMode loads) ──────────────
local function SetupEditModeIntegration()
  if lockSetup then return end
  lockSetup = true

  local EMF = _G.EditModeManagerFrame
  if not EMF then return end

  -- Hook Show/Hide — the correct API that actually fires (not EnterEditMode/ExitEditMode)
  hooksecurefunc(EMF, "Show", function()
    isEditMode = true
    LockViewerFrames()
    EM:UpdateSelectionOverlays()
  end)

  hooksecurefunc(EMF, "Hide", function()
    isEditMode = false
    -- Refresh containers after Edit Mode closes
    C_Timer.After(0.1, function()
      if NS.Cooldowns and NS.Cooldowns.Refresh then NS.Cooldowns.Refresh() end
      if NS.BuffBar   and NS.BuffBar.Refresh   then NS.BuffBar:Refresh()   end
    end)
  end)

  -- If Edit Mode is already open when we run setup
  if EMF:IsShown() then
    isEditMode = true
    LockViewerFrames()
    EM:UpdateSelectionOverlays()
  end

  -- Hook each viewer
  for _, name in ipairs(VIEWER_NAMES) do
    local viewer = GetViewer(name)
    if viewer then SetupViewerHooks(viewer, name) end
  end

  SetupSettingsDialogHook()
end

-- ── Apply recommended CooldownViewer Edit Mode settings ─────────────────
-- Sets "Always visible", "Show timer", and "Hide when inactive" for buff viewers
-- via the C_EditMode layout API — mirrors Ayije CDM's ApplyCooldownViewerEditModeRecommendedSettings.
local function HasRequiredApis()
  return C_EditMode
    and C_EditMode.GetLayouts
    and C_EditMode.SaveLayouts
    and Enum and Enum.EditModeSystem
    and Enum.EditModeSystem.CooldownViewer
    and Enum.EditModeCooldownViewerSystemIndices
    and Enum.EditModeCooldownViewerSetting
    and Enum.CooldownViewerVisibleSetting
end

local function UpsertSetting(settings, settingEnum, desiredValue)
  for _, info in ipairs(settings) do
    if info.setting == settingEnum then
      if info.value ~= desiredValue then info.value = desiredValue; return true end
      return false
    end
  end
  settings[#settings + 1] = {setting = settingEnum, value = desiredValue}
  return true
end

function EM:ApplyRecommendedSettings()
  if not HasRequiredApis() then return "not_ready" end

  local layoutInfo = C_EditMode.GetLayouts()
  if type(layoutInfo) ~= "table" or type(layoutInfo.layouts) ~= "table" then return "not_ready" end

  -- Merge preset layouts if available
  if EditModePresetLayoutManager and EditModePresetLayoutManager.GetCopyOfPresetLayouts then
    local presets = EditModePresetLayoutManager:GetCopyOfPresetLayouts()
    if type(presets) == "table" then
      tAppendAll(presets, layoutInfo.layouts)
      layoutInfo.layouts = presets
    end
  end

  local activeIdx = layoutInfo.activeLayout
  local activeLayout = type(activeIdx) == "number" and layoutInfo.layouts[activeIdx]
  if not (activeLayout and type(activeLayout.systems) == "table") then return "not_ready" end

  local CVS      = Enum.EditModeCooldownViewerSetting
  local CVIDX    = Enum.EditModeCooldownViewerSystemIndices
  local CVVIS    = Enum.CooldownViewerVisibleSetting
  local changed  = false
  local cvSystem = Enum.EditModeSystem.CooldownViewer

  for _, sys in ipairs(activeLayout.systems) do
    if sys.system == cvSystem and type(sys.settings) == "table" then
      -- All viewers: always visible + show timer
      if UpsertSetting(sys.settings, CVS.VisibleSetting, CVVIS.Always) then changed = true end
      if UpsertSetting(sys.settings, CVS.ShowTimer, 1)                 then changed = true end
      -- Buff viewers only: hide when inactive
      if sys.systemIndex == CVIDX.BuffIcon or sys.systemIndex == CVIDX.BuffBar then
        if UpsertSetting(sys.settings, CVS.HideWhenInactive, 1)        then changed = true end
      end
    end
  end

  if not changed then return "noop" end
  C_EditMode.SaveLayouts(layoutInfo)
  return "applied"
end

-- ── Initialize ──────────────────────────────────────────────────────────
local evFrame = CreateFrame("Frame")
evFrame:RegisterEvent("PLAYER_LOGIN")
evFrame:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    C_Timer.After(0.5, function()
      if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_EditMode") then
        SetupEditModeIntegration()
      else
        EventUtil.ContinueOnAddOnLoaded("Blizzard_EditMode", SetupEditModeIntegration)
      end
    end)
  end
end)

-- ── Public API ──────────────────────────────────────────────────────────
function EM:IsEditMode()   return isEditMode end
function EM:GetViewerNames() return VIEWER_NAMES end
