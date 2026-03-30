-- LucidUI QoL/SystemOpt.lua
-- FPS optimisation using Midnight 12.x CVar names.
-- These match the OPTIMAL_FPS_CVARS list in ChatOptions.lua (Settings UI).

local NS = LucidUINS
local L  = LucidUIL
NS.QoL = NS.QoL or {}

-- C_CVar wrappers with fallback for older API surfaces
local _GetCVar = (C_CVar and C_CVar.GetCVar) or GetCVar
local _SetCVar = (C_CVar and C_CVar.SetCVar) or SetCVar

-- These are the correct Midnight (12.x) CVar names — identical to the list
-- used by the Settings UI (ChatOptions.lua → OPTIMAL_FPS_CVARS).
local FPS_SETTINGS = {
  {cvar="renderScale",              optimal="1"},
  {cvar="VSync",                    optimal="0"},
  {cvar="MSAAQuality",              optimal="0"},
  {cvar="LowLatencyMode",           optimal="3"},
  {cvar="ffxAntiAliasingMode",      optimal="4"},
  {cvar="graphicsShadowQuality",    optimal="1"},
  {cvar="graphicsLiquidDetail",     optimal="2"},
  {cvar="graphicsParticleDensity",  optimal="3"},
  {cvar="graphicsSSAO",             optimal="0"},
  {cvar="graphicsDepthEffects",     optimal="0"},
  {cvar="graphicsComputeEffects",   optimal="0"},
  {cvar="graphicsOutlineMode",      optimal="2"},
  {cvar="graphicsTextureResolution",optimal="2"},
  {cvar="graphicsSpellDensity",     optimal="0"},
  {cvar="graphicsProjectedTextures",optimal="1"},
  {cvar="graphicsViewDistance",     optimal="3"},
  {cvar="graphicsEnvironmentDetail",optimal="3"},
  {cvar="graphicsGroundClutter",    optimal="0"},
  {cvar="GxMaxFrameLatency",        optimal="2"},
  {cvar="TextureFilteringMode",     optimal="5"},
  {cvar="shadowRt",                 optimal="0"},
  {cvar="ResampleQuality",          optimal="3"},
  {cvar="GxApi",                    optimal="D3D12"},
  {cvar="physicsLevel",             optimal="1"},
  {cvar="useTargetFPS",             optimal="0"},
  {cvar="useMaxFPSBk",              optimal="1"},
  {cvar="maxFPSBk",                 optimal="30"},
  {cvar="ResampleSharpness",        optimal="0"},
}

function NS.QoL.OptimizeFPS()
  local backup = {}
  for _, s in ipairs(FPS_SETTINGS) do
    local ok, cur = pcall(_GetCVar, s.cvar)
    if ok and cur then backup[s.cvar] = tostring(cur) end
  end
  NS.DBSet("qolFpsBackup", backup)

  local count = 0
  for _, s in ipairs(FPS_SETTINGS) do
    if pcall(_SetCVar, s.cvar, s.optimal) then count = count + 1 end
  end
  print("[|cff3bd2edLucid|r|cffffffffUI|r] " .. L["FPS optimized"] .. " (" .. count .. "/" .. #FPS_SETTINGS .. ")")
end

function NS.QoL.RestoreFPS()
  local backup = NS.DB("qolFpsBackup") or {}
  local n = 0
  for cvar, val in pairs(backup) do
    if val ~= "" then
      if pcall(_SetCVar, cvar, val) then n = n + 1 end
    end
  end
  NS.DBSet("qolFpsBackup", {})
  if n > 0 then
    print("[|cff3bd2edLucid|r|cffffffffUI|r] " .. string.format(L["FPS restored"], n))
  else
    print("[|cff3bd2edLucid|r|cffffffffUI|r] " .. L["No backup"])
  end
end
