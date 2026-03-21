local NS = LucidUINS
NS.QoL = NS.QoL or {}

function NS.QoL.Initialize()
  NS.QoL.InitCombatTimer()
  NS.QoL.InitAutoVendor()
  NS.QoL.InitSkipCinematics()
  NS.QoL.InitCombatAlert()
  NS.QoL.InitMouseRing()
  NS.QoL.InitMisc()
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self)
  self:UnregisterEvent("PLAYER_LOGIN")
  NS.QoL.Initialize()
end)
