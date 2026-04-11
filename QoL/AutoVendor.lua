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

-- Auto-sell grey items. Item info / sell price may not be cached yet on first
-- call after login; in that case we request the data and retry once.
local _pendingGreySell = false
local function DoAutoSellGrey()
  if not NS.DB("qolAutoSellGrey") then return end

  local sold, gold = 0, 0
  local skipped = 0
  for bag = 0, NUM_BAG_SLOTS do
    local slots = C_Container.GetContainerNumSlots(bag) or 0
    for slot = 1, slots do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.quality == 0 and info.itemID then
        local _, _, _, _, _, _, _, _, _, _, price = C_Item.GetItemInfo(info.itemID)
        if price == nil then
          -- Item data not cached yet — request and retry shortly.
          if C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(info.itemID)
          end
          skipped = skipped + 1
        elseif price > 0 then
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

  if skipped > 0 and not _pendingGreySell then
    _pendingGreySell = true
    C_Timer.After(0.6, function()
      _pendingGreySell = false
      if MerchantFrame and MerchantFrame:IsShown() then
        DoAutoSellGrey()
      end
    end)
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
