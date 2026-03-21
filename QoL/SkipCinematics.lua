local NS = LucidUINS
NS.QoL = NS.QoL or {}

function NS.QoL.InitSkipCinematics()
  local f = CreateFrame("Frame")
  f:RegisterEvent("CINEMATIC_START")
  f:RegisterEvent("PLAY_MOVIE")
  f:SetScript("OnEvent", function(_, event)
    if not NS.DB("qolSkipCinematics") then return end
    C_Timer.After(0.1, function()
      if event == "CINEMATIC_START" then
        if CinematicFrame and CinematicFrame:IsShown() then
          CinematicFrame_CancelCinematic()
        end
      elseif event == "PLAY_MOVIE" then
        if MovieFrame and MovieFrame:IsShown() then
          MovieFrame:Hide()
        end
      end
    end)
  end)
end
