local NS = LucidUINS
NS.QoL = NS.QoL or {}

-- ── Faster Loot ─────────────────────────────────────────────────────────────
-- Immediately grabs all loot items when the loot window opens.
local lootCooldown = 0
local lootFrame = CreateFrame("Frame")

local _getCVarBool = (C_CVar and C_CVar.GetCVarBool) or GetCVarBool

lootFrame:SetScript("OnEvent", function()
  if not NS.DB("qolFasterLoot") then return end
  -- Respect the autoLoot toggle modifier (Shift by default)
  local auto = _getCVarBool("autoLootDefault")
  local mod  = IsModifiedClick("AUTOLOOTTOGGLE")
  if (auto and mod) or (not auto and not mod) then return end
  -- Simple throttle to avoid double-processing
  local t = GetTime()
  if t - lootCooldown < 0.15 then return end
  lootCooldown = t
  -- Skip if the cursor is holding an item (prevents looting while dragging).
  -- Prefer C_Cursor.GetCursorInfo in 12.x; fall back to global GetCursorInfo.
  local cursorHasItem = false
  if C_Cursor and C_Cursor.GetCursorInfo then
    cursorHasItem = C_Cursor.GetCursorInfo() ~= nil
  elseif GetCursorInfo then
    cursorHasItem = GetCursorInfo() ~= nil
  end
  if cursorHasItem then return end
  for i = 1, GetNumLootItems() do LootSlot(i) end
end)

-- ── Suppress Loot Warnings ──────────────────────────────────────────────────
-- Auto-confirms bind-on-pickup, disenchant, trade timer and mail lock popups.
local warnFrame = CreateFrame("Frame")

-- Deferred API lookup: `ConfirmLootRoll` etc. may not be loaded when this file
-- executes. Check at handler call time instead of at table-construction time.
local WARN_HANDLERS = {
  CONFIRM_LOOT_ROLL = function(_, id, roll)
    if ConfirmLootRoll then ConfirmLootRoll(id, roll) end
    StaticPopup_Hide("CONFIRM_LOOT_ROLL")
  end,
  CONFIRM_DISENCHANT_ROLL = function(_, id, roll)
    if ConfirmLootRoll then ConfirmLootRoll(id, roll) end
    StaticPopup_Hide("CONFIRM_LOOT_ROLL")
  end,
  LOOT_BIND_CONFIRM = function(_, slot, ...)
    if ConfirmLootSlot then ConfirmLootSlot(slot) end
    StaticPopup_Hide("LOOT_BIND", ...)
  end,
  MERCHANT_CONFIRM_TRADE_TIMER_REMOVAL = function()
    if SellCursorItem then SellCursorItem() end
  end,
  MAIL_LOCK_SEND_ITEMS = function(_, slot)
    if RespondMailLockSendItem then RespondMailLockSendItem(slot, true) end
  end,
}

warnFrame:SetScript("OnEvent", function(_, ev, ...)
  if not NS.DB("qolSuppressWarnings") then return end
  local handler = WARN_HANDLERS[ev]
  if handler then handler(nil, ...) end
end)

-- ── Easy Item Destroy ───────────────────────────────────────────────────────
-- Removes the "type DELETE" requirement; shows the item link instead.
local destroyFrame = CreateFrame("Frame")
destroyFrame:RegisterEvent("DELETE_ITEM_CONFIRM")

-- Remove the instruction paragraph from the confirmation text
local function CleanConfirmText(txt)
  if not txt or not DELETE_GOOD_ITEM then return txt end
  local nl = DELETE_GOOD_ITEM:find("\n")
  if not nl then return txt end
  local tail = DELETE_GOOD_ITEM:sub(nl):gsub("%%s", "")
  tail = strtrim(tail)
  if tail == "" then return txt end
  local pos = txt:find(tail, 1, true)
  if pos then return strtrim(txt:sub(1, pos - 1)) end
  return txt
end

destroyFrame:SetScript("OnEvent", function()
  if not NS.DB("qolEasyDestroy") then return end
  for i = 1, (STATICPOPUP_NUMDIALOGS or 4) do
    local popup = _G["StaticPopup" .. i]
    if popup and popup:IsShown() then
      local eb  = _G["StaticPopup" .. i .. "EditBox"]
      local btn = _G["StaticPopup" .. i .. "Button1"]
      if eb and btn then
        eb:Hide()
        btn:Enable()
        -- Replace dialog text with cleaned version + item link
        -- Use C_Cursor.GetCursorInfo (Midnight API); fall back to global
        local cursorInfo = (C_Cursor and C_Cursor.GetCursorInfo) and C_Cursor.GetCursorInfo() or GetCursorInfo()
        local kind = cursorInfo and cursorInfo.cursorType or select(1, GetCursorInfo())
        local link = cursorInfo and cursorInfo.hyperlink or select(3, GetCursorInfo())
        if kind == "item" and link then
          local region = _G[popup:GetName() .. "Text"]
          if region then
            region:SetText(CleanConfirmText(region:GetText() or "") .. "\n\n" .. link)
          end
        end
        return
      end
    end
  end
end)

-- Add item tooltip on hover in delete dialogs
local function PatchDestroyTooltips()
  for _, dlgName in ipairs({"DELETE_ITEM", "DELETE_GOOD_ITEM", "DELETE_QUEST_ITEM", "DELETE_GOOD_QUEST_ITEM"}) do
    local dlg = StaticPopupDialogs[dlgName]
    if dlg then
      dlg.OnHyperlinkEnter = function(self, data)
        if data and data:match("^item") then
          GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
          GameTooltip:SetHyperlink(data)
          GameTooltip:Show()
        end
      end
      dlg.OnHyperlinkLeave = function() GameTooltip:Hide() end
    end
  end
end

-- ── Auto Keystone ───────────────────────────────────────────────────────────
-- Automatically slots a keystone when opening the M+ UI.
local function HookKeystoneFrame()
  if not ChallengesKeystoneFrame then return end
  ChallengesKeystoneFrame:HookScript("OnShow", function()
    if not NS.DB("qolAutoKeystone") then return end
    if C_ChallengeMode.HasSlottedKeystone() then return end
    -- Search bags for a keystone reagent
    for bag = 0, (NUM_BAG_SLOTS or 4) do
      for slot = 1, C_Container.GetContainerNumSlots(bag) do
        local id = C_Container.GetContainerItemID(bag, slot)
        if id then
          local _, _, _, _, _, _, _, _, _, _, _, cls, sub = C_Item.GetItemInfo(id)
          if cls == Enum.ItemClass.Reagent and sub == Enum.ItemReagentSubclass.Keystone then
            C_Container.PickupContainerItem(bag, slot)
            if C_Cursor.GetCursorItem() then C_ChallengeMode.SlotKeystone() end
            return
          end
        end
      end
    end
  end)
end

-- Hook immediately if already loaded, otherwise wait for ADDON_LOADED
if C_AddOns.IsAddOnLoaded("Blizzard_ChallengesUI") then
  HookKeystoneFrame()
else
  local ksWatcher = CreateFrame("Frame")
  ksWatcher:RegisterEvent("ADDON_LOADED")
  ksWatcher:SetScript("OnEvent", function(self, _, addon)
    if addon ~= "Blizzard_ChallengesUI" then return end
    self:UnregisterEvent("ADDON_LOADED")
    HookKeystoneFrame()
  end)
end

-- ── Initialize ──────────────────────────────────────────────────────────────
function NS.QoL.InitMisc()
  -- Always register events — handlers check DB setting before acting
  lootFrame:RegisterEvent("LOOT_READY")
  for ev in pairs(WARN_HANDLERS) do warnFrame:RegisterEvent(ev) end
  PatchDestroyTooltips()
end
