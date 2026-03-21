local NS = LucidUINS
local L  = LucidUIL
NS.QoL = NS.QoL or {}

local FPS_CVARS = {
  "shadowMode","shadowTextureSize","SSAO","SSAOBlur","sunShafts",
  "specularLighting","projectedTextures","particleDensity",
  "groundEffectDensity","groundEffectDist","reflectionMode",
  "waterDetail","rippleDetail","weatherDensity","ambientOcclusion",
}
local FPS_LOW = {
  shadowMode="0",shadowTextureSize="512",SSAO="0",SSAOBlur="0",sunShafts="0",
  specularLighting="0",projectedTextures="0",particleDensity="10",
  groundEffectDensity="16",groundEffectDist="1",reflectionMode="0",
  waterDetail="0",rippleDetail="0",weatherDensity="0",ambientOcclusion="0",
}

function NS.QoL.OptimizeFPS()
  local backup = {}
  for _, cv in ipairs(FPS_CVARS) do backup[cv] = GetCVar(cv) or "" end
  NS.DBSet("qolFpsBackup", backup)
  for _, cv in ipairs(FPS_CVARS) do SetCVar(cv, FPS_LOW[cv]) end
  print("|cff00ffffff[LucidUI]|r " .. L["FPS optimized"])
end

function NS.QoL.RestoreFPS()
  local backup = NS.DB("qolFpsBackup") or {}
  local n = 0
  for cv, val in pairs(backup) do if val ~= "" then SetCVar(cv, val); n = n + 1 end end
  NS.DBSet("qolFpsBackup", {})
  if n > 0 then print("|cff00ffffff[LucidUI]|r " .. string.format(L["FPS restored"], n))
  else print("|cff00ffffff[LucidUI]|r " .. L["No backup"]) end
end
