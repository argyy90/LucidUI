local NS = LucidUINS
local L  = LucidUIL
NS.QoL = NS.QoL or {}

local function DoAutoRepair()
  if not NS.DB("qolAutoRepair") then return end
  if not CanMerchantRepair or not CanMerchantRepair() then return end

  local cost, canRepair = GetRepairAllCost()
  if not canRepair or cost == 0 then return end

  local mode = NS.DB("qolAutoRepairMode") or "guild"
  local useGuild = (mode == "guild") and CanGuildBankRepair and CanGuildBankRepair()
  RepairAllItems(useGuild and true or false)

  if useGuild then
    print("[|cff3bd2edLucid|r|cffffffffUI|r] " .. L["Repaired guild"])
  else
    print("[|cff3bd2edLucid|r|cffffffffUI|r] Repaired for " .. C_CurrencyInfo.GetCoinTextureString(cost))
  end
end

local function DoAutoSellGrey()
  if not NS.DB("qolAutoSellGrey") then return end

  local sold, gold = 0, 0
  for bag = 0, NUM_BAG_SLOTS do
    local slots = C_Container.GetContainerNumSlots(bag)
    for slot = 1, slots do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.quality == 0 then
        local _, _, _, _, _, _, _, _, _, _, price = C_Item.GetItemInfo(info.itemID or 0)
        if price and price > 0 then
          C_Container.UseContainerItem(bag, slot)
          sold = sold + 1
          gold = gold + price
        end
      end
    end
  end

  if sold > 0 then
    print(string.format("[|cff3bd2edLucid|r|cffffffffUI|r] Sold %d grey item(s) for %s.", sold, C_CurrencyInfo.GetCoinTextureString(gold)))
  end
end

function NS.QoL.InitAutoVendor()
  local f = CreateFrame("Frame")
  f:RegisterEvent("MERCHANT_SHOW")
  f:SetScript("OnEvent", function()
    DoAutoRepair()
    DoAutoSellGrey()
  end)
end
