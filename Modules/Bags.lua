-- LucidUI Modules/Bags.lua
-- All-in-one bag replacement

local NS = LucidUINS
NS.Bags = NS.Bags or {}
local B = NS.Bags

local CYAN = NS.CYAN
local BACKPACK = Enum.BagIndex.Backpack         -- 0
local NUM_BAG_SLOTS = NUM_BAG_SLOTS or 4        -- 4 regular bags
local REAGENT_BAG = Enum.BagIndex.ReagentBag    -- 5

local QUALITY_COLORS = {
  [0] = {0.62, 0.62, 0.62},
  [1] = {1, 1, 1},
  [2] = {0.12, 1, 0},
  [3] = {0, 0.44, 0.87},
  [4] = {0.64, 0.21, 0.93},
  [5] = {1, 0.5, 0},
  [6] = {0.90, 0.80, 0.50},
  [7] = {0, 0.8, 1},
  [8] = {0, 0.8, 1},
}

local bagFrame = nil
local slots = {}
local RefreshBagBarIcons

-- ── Defaults ─────────────────────────────────────────────────────────
local DEFAULTS = {
  bagEnabled       = false,
  bagIconSize      = 37,
  bagSpacing       = 2,
  bagColumns       = 10,
  bagShowIlvl      = true,
  bagShowCount     = true,
  bagShowJunk      = true,
  bagShowQuality   = true,
  bagSortReverse   = false,
  bagSearchOnTop   = false,
  bagSplitReagent  = true,
  bagSplitBags     = false,
  bagSplitSpacing  = 8,
  bagJunkDesaturate = true,
  bagNewItemGlow   = true,
  bagQuestIcon     = true,
  bagShowUpgrade   = true,
  bagAutoBank      = true,
  bagAutoMail      = true,
  bagAutoAH        = true,
  bagIlvlPos       = "BOTTOMLEFT",
  bagIlvlSize      = 10,
  bagCountPos      = "BOTTOMRIGHT",
  bagCountSize     = 10,
  bagTransparent   = false,
  bagSlotBgAlpha   = 0.8,
}

for k, v in pairs(DEFAULTS) do
  if NS.DB_DEFAULTS then NS.DB_DEFAULTS[k] = v end
end

-- ── Helpers ──────────────────────────────────────────────────────────
local function DB(key) return NS.DB(key) end
local function DBSet(key, val) NS.DBSet(key, val) end

local function GetContainerInfo(bagID, slotID)
  local info = C_Container.GetContainerItemInfo(bagID, slotID)
  return info or {}
end

-- ── Upgrade Detection ─────────────────────────────────────────────────
local EQUIP_LOC_TO_SLOT = {
  INVTYPE_HEAD           = {1},
  INVTYPE_NECK           = {2},
  INVTYPE_SHOULDER       = {3},
  INVTYPE_BODY           = {4},
  INVTYPE_CHEST          = {5},
  INVTYPE_ROBE           = {5},
  INVTYPE_WAIST          = {6},
  INVTYPE_LEGS           = {7},
  INVTYPE_FEET           = {8},
  INVTYPE_WRIST          = {9},
  INVTYPE_HAND           = {10},
  INVTYPE_FINGER         = {11, 12},
  INVTYPE_TRINKET        = {13, 14},
  INVTYPE_CLOAK          = {15},
  INVTYPE_WEAPON         = {16, 17},
  INVTYPE_2HWEAPON       = {16},
  INVTYPE_WEAPONMAINHAND = {16},
  INVTYPE_WEAPONOFFHAND  = {17},
  INVTYPE_HOLDABLE       = {17},
  INVTYPE_SHIELD         = {17},
  INVTYPE_RANGED         = {16},
  INVTYPE_RANGEDRIGHT    = {16},
}

local function IsItemUpgrade(hyperlink)
  if not hyperlink then return false end
  local _, _, _, _, _, _, _, _, equipLoc = C_Item.GetItemInfo(hyperlink)
  if not equipLoc or equipLoc == "" then return false end

  local slotIDs = EQUIP_LOC_TO_SLOT[equipLoc]
  if not slotIDs then return false end

  local bagIlvl = C_Item.GetDetailedItemLevelInfo(hyperlink)
  if not bagIlvl or bagIlvl <= 1 then return false end

  for _, slotID in ipairs(slotIDs) do
    local equippedLink = GetInventoryItemLink("player", slotID)
    if equippedLink then
      local equippedIlvl = C_Item.GetDetailedItemLevelInfo(equippedLink)
      if equippedIlvl and bagIlvl > equippedIlvl then return true end
    else
      return true
    end
  end
  return false
end

local function FormatGoldNumber(n)
  local s = tostring(n)
  local len = #s
  local result = {}
  for i = 1, len do
    result[#result + 1] = s:sub(i, i)
    local remaining = len - i
    if remaining > 0 and remaining % 3 == 0 then result[#result + 1] = "." end
  end
  return table.concat(result)
end

local GOLD_ICON   = "|TInterface/MoneyFrame/UI-GoldIcon:14:14:0:0|t"
local SILVER_ICON = "|TInterface/MoneyFrame/UI-SilverIcon:14:14:0:0|t"
local COPPER_ICON = "|TInterface/MoneyFrame/UI-CopperIcon:14:14:0:0|t"

local function FormatMoney(copper)
  local gold = math.floor(copper / 10000)
  local silver = math.floor((copper % 10000) / 100)
  local cop = copper % 100
  if gold > 0 then
    return string.format("|cffffd700%s|r%s |cffc7c7cf%d|r%s |cffeda55f%d|r%s",
      FormatGoldNumber(gold), GOLD_ICON, silver, SILVER_ICON, cop, COPPER_ICON)
  elseif silver > 0 then
    return string.format("|cffc7c7cf%d|r%s |cffeda55f%d|r%s", silver, SILVER_ICON, cop, COPPER_ICON)
  else
    return string.format("|cffeda55f%d|r%s", cop, COPPER_ICON)
  end
end

-- ── Slot Creation ────────────────────────────────────────────────────
local function CreateSlot(parent, index)
  local size = DB("bagIconSize") or 37
  local slot = CreateFrame("ItemButton", "LucidBagSlot" .. index, parent, "ContainerFrameItemButtonTemplate")
  slot:SetSize(size, size)
  slot:EnableMouse(true)

  if slot.IconBorder then slot.IconBorder:SetAlpha(0) end
  if slot.NewItemTexture then slot.NewItemTexture:Hide() end
  if slot.BattlepayItemTexture then slot.BattlepayItemTexture:Hide() end
  if slot.flash then slot.flash:Hide() end
  for _, texName in pairs({"NormalTexture", "PushedTexture"}) do
    local tex = slot[texName] or (slot["Get"..texName] and slot["Get"..texName](slot))
    if tex then tex:SetTexture(nil); tex:Hide() end
  end
  local nt = slot:GetNormalTexture()
  if nt then nt:SetTexture(nil) end
  local pt = slot:GetPushedTexture()
  if pt then pt:SetTexture(nil) end

  local bg = slot:CreateTexture(nil, "BACKGROUND", nil, -1)
  bg:SetAllPoints()
  bg:SetColorTexture(0.12, 0.12, 0.12, 1)
  slot._bg = bg

  local function MakeBorder(p1, p2, w, h)
    local t = slot:CreateTexture(nil, "ARTWORK", nil, 0)
    t:SetPoint(p1, bg, p1, 0, 0); t:SetPoint(p2, bg, p2, 0, 0)
    if w then t:SetWidth(w) end
    if h then t:SetHeight(h) end
    t:SetColorTexture(0, 0, 0, 1)
    return t
  end
  slot._slotBorders = {
    MakeBorder("TOPLEFT", "TOPRIGHT", nil, 1),
    MakeBorder("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1),
    MakeBorder("TOPLEFT", "BOTTOMLEFT", 1, nil),
    MakeBorder("TOPRIGHT", "BOTTOMRIGHT", 1, nil),
  }

  local function MakeQBorder(p1, p2, w, h)
    local t = slot:CreateTexture(nil, "OVERLAY", nil, 7)
    t:SetPoint(p1, bg, p1, 0, 0); t:SetPoint(p2, bg, p2, 0, 0)
    if w then t:SetWidth(w) end
    if h then t:SetHeight(h) end
    t:SetColorTexture(0, 0, 0, 0)
    return t
  end
  slot._qualBorders = {
    MakeQBorder("TOPLEFT", "TOPRIGHT", nil, 2),
    MakeQBorder("BOTTOMLEFT", "BOTTOMRIGHT", nil, 2),
    MakeQBorder("TOPLEFT", "BOTTOMLEFT", 2, nil),
    MakeQBorder("TOPRIGHT", "BOTTOMRIGHT", 2, nil),
  }

  local hl = slot:CreateTexture(nil, "HIGHLIGHT")
  hl:SetPoint("TOPLEFT", bg, "TOPLEFT")
  hl:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT")
  hl:SetColorTexture(1, 1, 1, 0.08)
  hl:SetBlendMode("ADD")

  slot:HookScript("OnEnter", function(self)
    if C_NewItems and C_NewItems.IsNewItem(self._bagID, self._slotID) then
      C_NewItems.RemoveNewItem(self._bagID, self._slotID)
    end
    for _, nb in ipairs(self._newBorders) do nb:Hide() end
    self._newPulse:Hide()
    self._newCleared = true
  end)

  local icon = slot.icon or slot.Icon or slot.IconTexture
  slot._iconRef = icon
  if icon then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end

  local ilvl = slot:CreateFontString(nil, "OVERLAY")
  ilvl:SetFont("Fonts/FRIZQT__.TTF", 10, "OUTLINE")
  ilvl:SetTextColor(1, 1, 0.6)
  ilvl:Hide()
  slot._ilvl = ilvl

  local junk = slot:CreateTexture(nil, "OVERLAY")
  junk:SetSize(12, 12)
  junk:SetPoint("TOPLEFT", bg, "TOPLEFT", 1, -1)
  junk:SetAtlas("bags-junkcoin")
  junk:Hide()
  slot._junk = junk

  local quest = slot:CreateTexture(nil, "OVERLAY", nil, 6)
  quest:SetSize(14, 14)
  quest:SetPoint("TOPLEFT", bg, "TOPLEFT", 1, -1)
  quest:SetAtlas("questlog-questtypeicon-quest")
  quest:Hide()
  slot._quest = quest

  local upgradeIcon = slot:CreateTexture(nil, "OVERLAY", nil, 5)
  upgradeIcon:SetSize(12, 12)
  upgradeIcon:SetPoint("TOPRIGHT", bg, "TOPRIGHT", 4, -1)
  upgradeIcon:SetAtlas("bags-greenarrow", true)
  upgradeIcon:SetVertexColor(0.2, 1, 0.2)
  upgradeIcon:Hide()
  slot._upgradeIcon = upgradeIcon

  local bindText = slot:CreateFontString(nil, "OVERLAY")
  bindText:SetFont("Fonts/FRIZQT__.TTF", 12, "OUTLINE")
  bindText:SetPoint("TOP", bg, "TOP", -4, -1)
  bindText:SetTextColor(1, 1, 1, 0.9)
  bindText:Hide()
  slot._bindText = bindText

  local newBorders = {}
  local function MakeNewBorder(p1, p2, w, h)
    local t = slot:CreateTexture(nil, "OVERLAY", nil, 6)
    t:SetPoint(p1, bg, p1, 0, 0); t:SetPoint(p2, bg, p2, 0, 0)
    if w then t:SetWidth(w) end
    if h then t:SetHeight(h) end
    t:SetColorTexture(1, 0.82, 0, 0.8)
    t:Hide()
    return t
  end
  newBorders[1] = MakeNewBorder("TOPLEFT", "TOPRIGHT", nil, 2)
  newBorders[2] = MakeNewBorder("BOTTOMLEFT", "BOTTOMRIGHT", nil, 2)
  newBorders[3] = MakeNewBorder("TOPLEFT", "BOTTOMLEFT", 2, nil)
  newBorders[4] = MakeNewBorder("TOPRIGHT", "BOTTOMRIGHT", 2, nil)
  slot._newBorders = newBorders

  local pulseFrame = CreateFrame("Frame", nil, slot)
  pulseFrame:Hide()
  local pulseElapsed = 0
  pulseFrame:SetScript("OnUpdate", function(_, elapsed)
    pulseElapsed = pulseElapsed + elapsed
    local alpha = 0.4 + 0.4 * math.sin(pulseElapsed * 3)
    for _, nb in ipairs(newBorders) do nb:SetAlpha(alpha) end
  end)
  slot._newPulse = pulseFrame

  slot._bagID = 0
  slot._slotID = 0

  return slot
end

-- ── Position anchors for ilvl/count ──────────────────────────────────
local ANCHOR_OFFSETS = {
  BOTTOMLEFT   = {"BOTTOMLEFT", 2, 1},
  BOTTOMRIGHT  = {"BOTTOMRIGHT", -2, 1},
  BOTTOM       = {"BOTTOM", 0, 1},
  TOPLEFT      = {"TOPLEFT", 2, -2},
  TOPRIGHT     = {"TOPRIGHT", -2, -2},
  TOPCENTER    = {"TOP", 0, -2},
}

local function ApplySlotAnchors(slot)
  local ilvlPos = DB("bagIlvlPos") or "BOTTOMLEFT"
  local ilvlSize = DB("bagIlvlSize") or 10
  local countPos = DB("bagCountPos") or "BOTTOMRIGHT"
  local countSize = DB("bagCountSize") or 10
  local transparent = DB("bagTransparent")
  local bgAlpha = DB("bagSlotBgAlpha") or 0.8

  slot._ilvl:ClearAllPoints()
  local ia = ANCHOR_OFFSETS[ilvlPos] or ANCHOR_OFFSETS.BOTTOMLEFT
  slot._ilvl:SetPoint(ia[1], slot._bg, ia[1], ia[2], ia[3])
  slot._ilvl:SetFont("Fonts/FRIZQT__.TTF", ilvlSize, "OUTLINE")

  if slot.Count then
    slot.Count:ClearAllPoints()
    local ca = ANCHOR_OFFSETS[countPos] or ANCHOR_OFFSETS.BOTTOMRIGHT
    slot.Count:SetPoint(ca[1], slot._bg, ca[1], ca[2], ca[3])
    slot.Count:SetFont("Fonts/FRIZQT__.TTF", countSize, "OUTLINE")
  end

  slot._bgAlpha = transparent and (bgAlpha * 0.3) or bgAlpha
end

-- ── Update Single Slot ──────────────────────────────────────────────
local function UpdateSlot(slot)
  local bagID, slotID = slot._bagID, slot._slotID
  local info = GetContainerInfo(bagID, slotID)

  local icon = slot._iconRef
  if not icon then return end

  -- Reset new-item cleared flag when slot content changes
  local curItem = info.itemID or 0
  if slot._lastItemID ~= curItem then
    slot._lastItemID = curItem
    slot._newCleared = false
  end

  if info.iconFileID then
    icon:SetTexture(info.iconFileID)
    icon:Show()

    if DB("bagShowQuality") and info.quality and info.quality > 1 then
      local qc = QUALITY_COLORS[info.quality]
      if qc then
        local thickness = info.quality >= 4 and 2 or 1
        for i, b in ipairs(slot._qualBorders) do
          b:SetColorTexture(qc[1], qc[2], qc[3], 0.8)
          if i <= 2 then b:SetHeight(thickness) else b:SetWidth(thickness) end
        end
      else
        for _, b in ipairs(slot._qualBorders) do b:SetColorTexture(0, 0, 0, 0) end
      end
    else
      for _, b in ipairs(slot._qualBorders) do b:SetColorTexture(0, 0, 0, 0) end
    end

    local count = slot.Count
    if count then
      if DB("bagShowCount") and info.stackCount and info.stackCount > 1 then
        count:SetText(info.stackCount); count:Show()
      else
        count:Hide()
      end
    end

    local itemLoc = info.hyperlink and ItemLocation:CreateFromBagAndSlot(bagID, slotID) or nil
    local itemExists = itemLoc and itemLoc:IsValid() and C_Item.DoesItemExist(itemLoc)

    local showIlvl = false
    if DB("bagShowIlvl") and itemExists then
      local ilvlNum = C_Item.GetCurrentItemLevel(itemLoc)
      if ilvlNum and ilvlNum > 1 then
        local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(info.hyperlink)
        if classID == 2 or classID == 4 then
          slot._ilvl:SetText(ilvlNum); slot._ilvl:Show(); showIlvl = true
        end
      end
    end
    if not showIlvl then slot._ilvl:Hide() end

    local isJunk = info.quality == 0 and not info.noValue
    if DB("bagShowJunk") and isJunk then slot._junk:Show() else slot._junk:Hide() end
    if icon.SetDesaturated then
      icon:SetDesaturated(info.isLocked or (DB("bagJunkDesaturate") and isJunk) or false)
    end

    if DB("bagQuestIcon") then
      local questInfo = C_Container.GetContainerItemQuestInfo(bagID, slotID)
      if questInfo and (questInfo.isQuestItem or questInfo.questID) then
        slot._quest:Show()
        for _, b in ipairs(slot._qualBorders) do b:SetColorTexture(1, 0.82, 0, 1) end
      else
        slot._quest:Hide()
      end
    else
      slot._quest:Hide()
    end

    if DB("bagShowUpgrade") and info.hyperlink and info.quality and info.quality >= 2 then
      slot._upgradeIcon:SetShown(IsItemUpgrade(info.hyperlink))
    else
      slot._upgradeIcon:Hide()
    end

    local showBind = false
    if itemExists and info.hyperlink then
      local isBound = C_Item.IsBound(itemLoc)
      if not isBound then
        -- FIX: use C_Item.GetItemInfo (Midnight API) instead of deprecated global GetItemInfo
        local bindType = select(14, C_Item.GetItemInfo(info.hyperlink))
        local BIND_EQUIP = Enum.ItemBind and Enum.ItemBind.OnEquip or 2
        local BIND_USE   = Enum.ItemBind and Enum.ItemBind.OnUse or 3
        if bindType == BIND_EQUIP then
          local isWuE = C_Item.IsBoundToAccountUntilEquip and C_Item.IsBoundToAccountUntilEquip(itemLoc)
          if isWuE then
            slot._bindText:SetText("WuE"); slot._bindText:SetTextColor(0.0, 0.8, 1)
          else
            slot._bindText:SetText("BOE"); slot._bindText:SetTextColor(0.1, 1, 0.1)
          end
          slot._bindText:Show(); showBind = true
        elseif bindType == BIND_USE then
          slot._bindText:SetText("BOU"); slot._bindText:SetTextColor(1, 0.8, 0.2)
          slot._bindText:Show(); showBind = true
        end
      end
    end
    if not showBind then slot._bindText:Hide() end

    if DB("bagNewItemGlow") and not slot._newCleared and C_NewItems and C_NewItems.IsNewItem(bagID, slotID) then
      for _, nb in ipairs(slot._newBorders) do nb:Show() end
      slot._newPulse:Show()
    else
      for _, nb in ipairs(slot._newBorders) do nb:Hide() end
      slot._newPulse:Hide()
    end
  else
    icon:SetTexture(nil); icon:Hide()
    for _, b in ipairs(slot._qualBorders) do b:SetColorTexture(0, 0, 0, 0) end
    slot._ilvl:Hide(); slot._junk:Hide(); slot._quest:Hide()
    slot._bindText:Hide(); slot._upgradeIcon:Hide()
    for _, nb in ipairs(slot._newBorders) do nb:Hide() end
    slot._newPulse:Hide()
    if icon.SetDesaturated then icon:SetDesaturated(false) end
    if slot.Count then slot.Count:Hide() end
  end
end

-- ── Layout ───────────────────────────────────────────────────────────
local function LayoutBags()
  if not bagFrame then return end

  local cr, cg, cb = CYAN[1], CYAN[2], CYAN[3]
  if bagFrame._accentLine then bagFrame._accentLine:SetColorTexture(cr, cg, cb, 1) end
  if bagFrame._title then bagFrame._title:SetTextColor(cr, cg, cb) end

  local iconSize = DB("bagIconSize") or 37
  local spacing = DB("bagSpacing") or 4
  local columns = DB("bagColumns") or 10
  local splitReagent = DB("bagSplitReagent")
  local splitBags = DB("bagSplitBags")
  local splitSpacing = DB("bagSplitSpacing") or 8

  local groups = {}
  if splitBags then
    local bagOrder = {BACKPACK}
    for i = 1, NUM_BAG_SLOTS do bagOrder[#bagOrder + 1] = i end
    for _, bagID in ipairs(bagOrder) do
      local group = {}
      local numSlots = C_Container.GetContainerNumSlots(bagID)
      for slotID = 1, numSlots do group[#group + 1] = {bagID = bagID, slotID = slotID} end
      if #group > 0 then groups[#groups + 1] = group end
    end
  else
    local group = {}
    for bagID = BACKPACK, NUM_BAG_SLOTS do
      local numSlots = C_Container.GetContainerNumSlots(bagID)
      for slotID = 1, numSlots do group[#group + 1] = {bagID = bagID, slotID = slotID} end
    end
    if #group > 0 then groups[#groups + 1] = group end
  end

  local reagentGroup = {}
  local rSlots = C_Container.GetContainerNumSlots(REAGENT_BAG)
  if rSlots and rSlots > 0 then
    if splitReagent then
      for slotID = 1, rSlots do
        reagentGroup[#reagentGroup + 1] = {bagID = REAGENT_BAG, slotID = slotID}
      end
    else
      local rGroup = {}
      for slotID = 1, rSlots do rGroup[#rGroup + 1] = {bagID = REAGENT_BAG, slotID = slotID} end
      if #rGroup > 0 then groups[#groups + 1] = rGroup end
    end
  end

  if DB("bagSortReverse") then
    for g, group in ipairs(groups) do
      local reversed = {}
      for i = #group, 1, -1 do reversed[#reversed + 1] = group[i] end
      groups[g] = reversed
    end
  end

  local contentFrame = bagFrame._content
  local slotIdx = 0
  local yOffset = 0

  for g, group in ipairs(groups) do
    if g > 1 then yOffset = yOffset + splitSpacing end
    local groupRows = math.ceil(#group / columns)
    for i, slotData in ipairs(group) do
      slotIdx = slotIdx + 1
      local slot = slots[slotIdx]
      if not slot then slot = CreateSlot(contentFrame, slotIdx); slots[slotIdx] = slot end

      slot._bagID = slotData.bagID
      slot._slotID = slotData.slotID
      slot:SetID(slotData.slotID)
      if slot.SetBagID then slot:SetBagID(slotData.bagID) end

      local cellSize = iconSize + spacing
      slot:SetSize(cellSize, cellSize)
      local icon = slot._iconRef
      if icon then
        icon:ClearAllPoints(); icon:SetPoint("TOPLEFT", 0, 0)
        icon:SetSize(iconSize, iconSize); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      end
      slot._bg:ClearAllPoints(); slot._bg:SetPoint("TOPLEFT", 0, 0); slot._bg:SetSize(iconSize, iconSize)

      local localIdx = i - 1
      local col = localIdx % columns
      local row = math.floor(localIdx / columns)
      slot:ClearAllPoints()
      slot:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", col * cellSize, -(yOffset + row * cellSize))
      slot:Show()
      ApplySlotAnchors(slot)
      UpdateSlot(slot)

      local alpha = slot._bgAlpha or 1
      if not splitReagent and slotData.bagID == REAGENT_BAG then
        slot._bg:SetColorTexture(0.10, 0.12, 0.10, alpha)
      else
        slot._bg:SetColorTexture(0.12, 0.12, 0.12, alpha)
      end
    end

    if not splitReagent and #group > 0 and group[1].bagID == REAGENT_BAG then
      local cell = iconSize + spacing
      bagFrame._reagentInlineY = yOffset
      bagFrame._reagentInlineH = groupRows * cell - spacing
      bagFrame._reagentInlineW = math.min(#group, columns) * cell - spacing
    end

    yOffset = yOffset + groupRows * (iconSize + spacing)
  end

  if not bagFrame._reagentInlineBorder then
    local rib = CreateFrame("Frame", nil, contentFrame)
    rib:SetFrameLevel(contentFrame:GetFrameLevel() + 10)
    rib:EnableMouse(false)
    rib._edges = {}
    for idx = 1, 4 do
      local t = rib:CreateTexture(nil, "OVERLAY", nil, 6)
      rib._edges[idx] = t
    end
    bagFrame._reagentInlineBorder = rib
  end
  local rib = bagFrame._reagentInlineBorder
  if not splitReagent and bagFrame._reagentInlineY then
    local acr, acg, acb = CYAN[1], CYAN[2], CYAN[3]
    for _, e in ipairs(rib._edges) do e:SetColorTexture(acr, acg, acb, 0.7) end
    rib:ClearAllPoints()
    rib:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", -1, -(bagFrame._reagentInlineY - 1))
    rib:SetSize(bagFrame._reagentInlineW + 2, bagFrame._reagentInlineH + 2)
    local eT, eB, eL, eR = rib._edges[1], rib._edges[2], rib._edges[3], rib._edges[4]
    eT:ClearAllPoints(); eT:SetPoint("TOPLEFT"); eT:SetPoint("TOPRIGHT"); eT:SetHeight(1)
    eB:ClearAllPoints(); eB:SetPoint("BOTTOMLEFT"); eB:SetPoint("BOTTOMRIGHT"); eB:SetHeight(1)
    eL:ClearAllPoints(); eL:SetPoint("TOPLEFT"); eL:SetPoint("BOTTOMLEFT"); eL:SetWidth(1)
    eR:ClearAllPoints(); eR:SetPoint("TOPRIGHT"); eR:SetPoint("BOTTOMRIGHT"); eR:SetWidth(1)
    rib:Show()
  else
    rib:Hide(); bagFrame._reagentInlineY = nil
  end

  if not bagFrame._reagentWin then
    local rw = CreateFrame("Frame", "LucidUIReagentBag", UIParent, "BackdropTemplate")
    rw:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
    rw:SetBackdropColor(0.06, 0.06, 0.06, 0.92)
    rw:SetBackdropBorderColor(0, 0, 0, 1)
    rw:SetFrameStrata("MEDIUM"); rw:SetToplevel(true); rw:EnableMouse(true); rw:Hide()
    local raccentLine = rw:CreateTexture(nil, "ARTWORK", nil, 7)
    raccentLine:SetPoint("TOPLEFT"); raccentLine:SetPoint("TOPRIGHT"); raccentLine:SetHeight(1)
    raccentLine:SetColorTexture(CYAN[1], CYAN[2], CYAN[3], 1)
    rw._accentLine = raccentLine
    local rtitle = rw:CreateFontString(nil, "OVERLAY")
    rtitle:SetFont("Fonts/FRIZQT__.TTF", 10, "")
    rtitle:SetPoint("TOPLEFT", 6, -4)
    rtitle:SetTextColor(CYAN[1], CYAN[2], CYAN[3]); rtitle:SetText("Reagents")
    rw._title = rtitle
    local rcontent = CreateFrame("Frame", nil, rw)
    rcontent:SetPoint("TOPLEFT", 4, -18)
    rw._content = rcontent
    bagFrame._reagentWin = rw
  end

  local rWin = bagFrame._reagentWin
  if splitReagent and #reagentGroup > 0 then
    if DB("bagSortReverse") then
      local rev = {}
      for i = #reagentGroup, 1, -1 do rev[#rev + 1] = reagentGroup[i] end
      reagentGroup = rev
    end
    local rContent = rWin._content
    local rCols = 5
    local rRows = math.ceil(#reagentGroup / rCols)
    local cellSize = iconSize + spacing

    bagFrame._reagentSlots = bagFrame._reagentSlots or {}
    for i, slotData in ipairs(reagentGroup) do
      local slot = bagFrame._reagentSlots[i]
      if not slot then slot = CreateSlot(rContent, 1000 + i); bagFrame._reagentSlots[i] = slot end
      slot._bagID = slotData.bagID; slot._slotID = slotData.slotID
      slot:SetID(slotData.slotID)
      if slot.SetBagID then slot:SetBagID(slotData.bagID) end
      slot:SetSize(cellSize, cellSize)
      local sIcon = slot._iconRef
      if sIcon then
        sIcon:ClearAllPoints(); sIcon:SetPoint("TOPLEFT", 0, 0)
        sIcon:SetSize(iconSize, iconSize); sIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      end
      slot._bg:ClearAllPoints(); slot._bg:SetPoint("TOPLEFT", 0, 0); slot._bg:SetSize(iconSize, iconSize)
      local alpha = slot._bgAlpha or 1
      slot._bg:SetColorTexture(0.10, 0.12, 0.10, alpha)
      local col = (i - 1) % rCols; local row = math.floor((i - 1) / rCols)
      slot:ClearAllPoints(); slot:SetPoint("TOPLEFT", rContent, "TOPLEFT", col * cellSize, -row * cellSize)
      slot:Show(); ApplySlotAnchors(slot); UpdateSlot(slot)
    end
    for i = #reagentGroup + 1, #(bagFrame._reagentSlots) do
      if bagFrame._reagentSlots[i] then bagFrame._reagentSlots[i]:Hide() end
    end

    local rTitleH, pad = 18, 4
    local rContentW = rCols * cellSize - spacing
    local rContentH = rRows * cellSize - spacing
    local rwW = rContentW + pad * 2
    local rwH = rContentH + rTitleH + pad * 2
    rWin:SetSize(rwW, rwH)
    rWin._content:ClearAllPoints()
    rWin._content:SetPoint("TOPLEFT", rWin, "TOPLEFT", pad, -rTitleH)
    rWin._content:SetSize(rContentW, rContentH)
    rWin:ClearAllPoints(); rWin:SetPoint("BOTTOMRIGHT", bagFrame, "BOTTOMLEFT", -2, 0)
    rWin._accentLine:SetColorTexture(CYAN[1], CYAN[2], CYAN[3], 1)
    rWin._title:SetTextColor(CYAN[1], CYAN[2], CYAN[3])
    rWin:Show()
  else
    rWin:Hide()
  end

  for i = slotIdx + 1, #slots do if slots[i] then slots[i]:Hide() end end

  bagFrame._moneyText:SetText(FormatMoney(GetMoney()))

  local contentW = columns * (iconSize + spacing) - spacing
  local contentH = yOffset - spacing

  if bagFrame._currencyContainer then
    local entries = {}
    local maxTokens = MAX_WATCHED_TOKENS or 20
    if C_CurrencyInfo and C_CurrencyInfo.GetBackpackCurrencyInfo then
      for i = 1, maxTokens do
        local info = C_CurrencyInfo.GetBackpackCurrencyInfo(i)
        if not info or not info.name then break end
        local icon = info.iconFileID and CreateTextureMarkup(info.iconFileID, 64, 64, 14, 14, 0, 1, 0, 1) or ""
        entries[#entries + 1] = string.format("%s %s", icon, BreakUpLargeNumbers(info.quantity))
      end
    end

    bagFrame._currencyLines = bagFrame._currencyLines or {}
    local maxW = bagFrame:GetWidth() - 16
    local lines = {{}}
    local testFS = bagFrame._currencyLines[1]
    if not testFS then
      testFS = bagFrame._currencyBg:CreateFontString(nil, "OVERLAY")
      testFS:SetFont("Fonts/FRIZQT__.TTF", 11, "")
      testFS:SetTextColor(0.7, 0.7, 0.7)
      bagFrame._currencyLines[1] = testFS
    end

    for _, entry in ipairs(entries) do
      local currentLine = lines[#lines]
      local testText = table.concat(currentLine, "   ")
      if testText ~= "" then testText = testText .. "   " end
      testText = testText .. entry
      testFS:SetText(testText)
      local textW = testFS:GetStringWidth()
      if textW > maxW and #currentLine > 0 then
        lines[#lines + 1] = {entry}
      else
        currentLine[#currentLine + 1] = entry
      end
    end

    local lineH = 16
    for li, line in ipairs(lines) do
      local fs = bagFrame._currencyLines[li]
      if not fs then
        fs = bagFrame._currencyBg:CreateFontString(nil, "OVERLAY")
        fs:SetFont("Fonts/FRIZQT__.TTF", 11, "")
        fs:SetTextColor(0.7, 0.7, 0.7)
        bagFrame._currencyLines[li] = fs
      end
      fs:SetText(table.concat(line, "   "))
      fs:ClearAllPoints()
      fs:SetPoint("BOTTOMLEFT", bagFrame._currencyBg, "BOTTOMLEFT", 0, (li - 1) * lineH)
      fs:Show()
    end
    for li = #lines + 1, #bagFrame._currencyLines do bagFrame._currencyLines[li]:Hide() end
    local numLines = math.max(#lines, 1)
    bagFrame._currencyBg:SetHeight(numLines * lineH)
  end

  local frameW = contentW + 16
  local titleH = 28
  local searchH = 24
  local currencyH = bagFrame._currencyBg and bagFrame._currencyBg:GetHeight() or 16
  local bottomH = currencyH + 4
  local frameH = titleH + searchH + 4 + contentH + 8 + bottomH

  bagFrame:SetSize(frameW, frameH)
  contentFrame:SetPoint("TOPLEFT", bagFrame, "TOPLEFT", 8, -(titleH + searchH + 4))
  contentFrame:SetSize(contentW, contentH)
end

-- ── Build Bag Frame ──────────────────────────────────────────────────
local function BuildBagFrame()
  if bagFrame then return end

  local cr, cg, cb = CYAN[1], CYAN[2], CYAN[3]

  bagFrame = CreateFrame("Frame", "LucidUIBags", UIParent, "BackdropTemplate")
  bagFrame:SetSize(400, 500)
  bagFrame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -50, 50)
  bagFrame:SetFrameStrata("MEDIUM"); bagFrame:SetToplevel(true)
  bagFrame:SetMovable(true); bagFrame:SetResizable(true); bagFrame:SetResizeBounds(200, 150)
  bagFrame:SetClampedToScreen(true); bagFrame:EnableMouse(true)
  bagFrame:RegisterForDrag("LeftButton")
  bagFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  bagFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    DBSet("bagWinPos", {point, relPoint, x, y})
  end)
  bagFrame:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
  bagFrame:SetBackdropColor(0.06, 0.06, 0.06, 0.92)
  bagFrame:SetBackdropBorderColor(0, 0, 0, 1)
  bagFrame:Hide()

  local pos = DB("bagWinPos")
  if pos then bagFrame:ClearAllPoints(); bagFrame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) end

  local accent = bagFrame:CreateTexture(nil, "ARTWORK", nil, 7)
  accent:SetPoint("TOPLEFT", 0, 0); accent:SetPoint("TOPRIGHT", 0, 0); accent:SetHeight(1)
  accent:SetColorTexture(cr, cg, cb, 1)
  bagFrame._accentLine = accent

  local titleH = 28
  local titleBg = bagFrame:CreateTexture(nil, "ARTWORK")
  titleBg:SetPoint("TOPLEFT", 0, 0); titleBg:SetPoint("TOPRIGHT", 0, 0); titleBg:SetHeight(titleH)
  titleBg:SetColorTexture(0.04, 0.04, 0.04, 1)

  local title = bagFrame:CreateFontString(nil, "OVERLAY")
  title:SetFont("Fonts/FRIZQT__.TTF", 12, "")
  title:SetPoint("LEFT", titleBg, "LEFT", 8, 0)
  title:SetTextColor(cr, cg, cb); title:SetText("Bags")
  bagFrame._title = title

  local closeBtn = CreateFrame("Button", nil, bagFrame)
  closeBtn:SetSize(16, 16); closeBtn:SetPoint("TOPRIGHT", -6, -6)
  local closeTex = closeBtn:CreateTexture(nil, "ARTWORK")
  closeTex:SetAllPoints(); closeTex:SetTexture("Interface/AddOns/LucidUI/Assets/X_red.png")
  closeTex:SetVertexColor(0.6, 0.6, 0.6)
  closeBtn:SetScript("OnClick", function() B.CloseBags() end)
  closeBtn:SetScript("OnEnter", function() closeTex:SetVertexColor(1, 0.3, 0.3) end)
  closeBtn:SetScript("OnLeave", function() closeTex:SetVertexColor(0.6, 0.6, 0.6) end)

  local cogBtn = CreateFrame("Button", nil, bagFrame)
  cogBtn:SetSize(16, 16); cogBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
  local cogTex = cogBtn:CreateTexture(nil, "ARTWORK")
  cogTex:SetAllPoints(); cogTex:SetTexture("Interface/AddOns/LucidUI/Assets/Cog.png")
  cogTex:SetVertexColor(0.6, 0.6, 0.6)
  cogBtn:SetScript("OnClick", function()
    if NS.minimapBtn then NS.minimapBtn:Click() end
    local chatOptWin = _G["LUIChatSettingsDialog"]
    if chatOptWin and chatOptWin._selectTab then
      C_Timer.After(0.05, function()
        chatOptWin = _G["LUIChatSettingsDialog"]
        if chatOptWin and chatOptWin._selectTab then
          chatOptWin._selectTab(chatOptWin._bagsTabIdx or 9)
        end
      end)
    end
  end)
  cogBtn:SetScript("OnEnter", function()
    cogTex:SetVertexColor(1, 1, 1)
    GameTooltip:SetOwner(cogBtn, "ANCHOR_LEFT"); GameTooltip:SetText("Bags Settings", 1,1,1); GameTooltip:Show()
  end)
  cogBtn:SetScript("OnLeave", function() cogTex:SetVertexColor(0.6, 0.6, 0.6); GameTooltip:Hide() end)

  local sortBtn = CreateFrame("Button", nil, bagFrame)
  sortBtn:SetSize(16, 16); sortBtn:SetPoint("RIGHT", cogBtn, "LEFT", -4, 0)
  local sortTex = sortBtn:CreateTexture(nil, "ARTWORK")
  sortTex:SetAllPoints(); sortTex:SetTexture("Interface/Icons/INV_Pet_Broom")
  sortTex:SetTexCoord(0.08, 0.92, 0.08, 0.92); sortTex:SetVertexColor(0.6, 0.6, 0.6)
  sortBtn:SetScript("OnClick", function() C_Container.SortBags() end)
  sortBtn:SetScript("OnEnter", function()
    sortTex:SetVertexColor(1, 1, 1)
    GameTooltip:SetOwner(sortBtn, "ANCHOR_LEFT"); GameTooltip:SetText("Sort Bags", 1,1,1); GameTooltip:Show()
  end)
  sortBtn:SetScript("OnLeave", function() sortTex:SetVertexColor(0.6, 0.6, 0.6); GameTooltip:Hide() end)

  local bagsBtn = CreateFrame("Button", nil, bagFrame)
  bagsBtn:SetSize(16, 16); bagsBtn:SetPoint("RIGHT", sortBtn, "LEFT", -6, 0)
  local bagsBtnTex = bagsBtn:CreateTexture(nil, "ARTWORK")
  bagsBtnTex:SetAllPoints(); bagsBtnTex:SetTexture(130716)
  bagsBtnTex:SetTexCoord(0.08, 0.92, 0.08, 0.92); bagsBtnTex:SetVertexColor(0.6, 0.6, 0.6)

  local bagBar = CreateFrame("Frame", nil, bagFrame, "BackdropTemplate")
  local BAG_BAR_SIZE = 28
  local BAG_BAR_SPACING = 4
  local numBagBtns = 1 + NUM_BAG_SLOTS + 1
  local barW = numBagBtns * (BAG_BAR_SIZE + BAG_BAR_SPACING) - BAG_BAR_SPACING + 12
  bagBar:SetSize(barW, BAG_BAR_SIZE + 12)
  bagBar:SetPoint("BOTTOMLEFT", bagFrame, "TOPLEFT", 0, 1)
  bagBar:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
  bagBar:SetBackdropColor(0.03, 0.03, 0.03, 0.95)
  bagBar:SetBackdropBorderColor(0.15, 0.15, 0.15, 1)
  bagBar:SetFrameStrata("MEDIUM"); bagBar:Hide()
  bagFrame._bagBar = bagBar

  local bagBarAccent = bagBar:CreateTexture(nil, "ARTWORK", nil, 7)
  bagBarAccent:SetPoint("TOPLEFT", 0, 0); bagBarAccent:SetPoint("TOPRIGHT", 0, 0); bagBarAccent:SetHeight(1)
  bagBarAccent:SetColorTexture(cr, cg, cb, 1)
  bagBar._accentLine = bagBarAccent

  local bpBtn = CreateFrame("Button", nil, bagBar)
  bpBtn:SetSize(BAG_BAR_SIZE, BAG_BAR_SIZE); bpBtn:SetPoint("LEFT", bagBar, "LEFT", 6, 0)
  local bpTex = bpBtn:CreateTexture(nil, "ARTWORK"); bpTex:SetAllPoints()
  bpTex:SetTexture(130716); bpTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local bpBorder = bpBtn:CreateTexture(nil, "BACKGROUND")
  bpBorder:SetPoint("TOPLEFT", -1, 1); bpBorder:SetPoint("BOTTOMRIGHT", 1, -1)
  bpBorder:SetColorTexture(0.25, 0.25, 0.25, 1)
  bpBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(bpBtn, "ANCHOR_TOP"); GameTooltip:SetText("Backpack", 1,1,1); GameTooltip:Show()
  end)
  bpBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

  local prevBagBtn = bpBtn
  for bagIdx = 1, NUM_BAG_SLOTS do
    local bagBtn = CreateFrame("Button", nil, bagBar)
    bagBtn:SetSize(BAG_BAR_SIZE, BAG_BAR_SIZE)
    bagBtn:SetPoint("LEFT", prevBagBtn, "RIGHT", BAG_BAR_SPACING, 0)
    local bagBorder = bagBtn:CreateTexture(nil, "BACKGROUND")
    bagBorder:SetPoint("TOPLEFT", -1, 1); bagBorder:SetPoint("BOTTOMRIGHT", 1, -1)
    bagBorder:SetColorTexture(0.25, 0.25, 0.25, 1)
    local bagTex = bagBtn:CreateTexture(nil, "ARTWORK"); bagTex:SetAllPoints()
    bagTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local invID = C_Container.ContainerIDToInventoryID(bagIdx)
    local texID = GetInventoryItemTexture("player", invID)
    bagTex:SetTexture(texID or 130716)
    bagBtn._bagIdx = bagIdx; bagBtn._tex = bagTex; bagBtn._invID = invID
    bagFrame._bagBarButtons = bagFrame._bagBarButtons or {}
    bagFrame._bagBarButtons[#bagFrame._bagBarButtons + 1] = bagBtn
    bagBtn:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetInventoryItem("player", C_Container.ContainerIDToInventoryID(self._bagIdx))
      GameTooltip:Show()
    end)
    bagBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bagBtn:SetScript("OnClick", function(self)
      local invSlot = C_Container.ContainerIDToInventoryID(self._bagIdx)
      if CursorHasItem() then
        if PutItemInBag then PutItemInBag(invSlot)
        else C_Container.PickupContainerItem(0, 0) end
      else
        if PickupBagFromSlot then PickupBagFromSlot(invSlot) end
      end
    end)
    prevBagBtn = bagBtn
  end

  local rNumSlots = C_Container.GetContainerNumSlots(REAGENT_BAG)
  if rNumSlots and rNumSlots > 0 then
    local rBtn = CreateFrame("Button", nil, bagBar)
    rBtn:SetSize(BAG_BAR_SIZE, BAG_BAR_SIZE)
    rBtn:SetPoint("LEFT", prevBagBtn, "RIGHT", BAG_BAR_SPACING, 0)
    local rBorder = rBtn:CreateTexture(nil, "BACKGROUND")
    rBorder:SetPoint("TOPLEFT", -1, 1); rBorder:SetPoint("BOTTOMRIGHT", 1, -1)
    rBorder:SetColorTexture(0.25, 0.25, 0.25, 1)
    local rTex = rBtn:CreateTexture(nil, "ARTWORK"); rTex:SetAllPoints()
    rTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local rInvID = C_Container.ContainerIDToInventoryID(REAGENT_BAG)
    local rTexID = GetInventoryItemTexture("player", rInvID)
    rTex:SetTexture(rTexID or 4701557)
    rBtn._tex = rTex
    rBtn:SetScript("OnEnter", function()
      GameTooltip:SetOwner(rBtn, "ANCHOR_TOP"); GameTooltip:SetInventoryItem("player", rInvID); GameTooltip:Show()
    end)
    rBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bagFrame._reagentBarBtn = rBtn
  end

  bagsBtn:SetScript("OnClick", function() bagBar:SetShown(not bagBar:IsShown()) end)
  bagsBtn:SetScript("OnEnter", function()
    bagsBtnTex:SetVertexColor(1, 1, 1)
    GameTooltip:SetOwner(bagsBtn, "ANCHOR_LEFT"); GameTooltip:SetText("Toggle Bag Bar", 1,1,1); GameTooltip:Show()
  end)
  bagsBtn:SetScript("OnLeave", function() bagsBtnTex:SetVertexColor(0.6, 0.6, 0.6); GameTooltip:Hide() end)

  local searchBox = CreateFrame("EditBox", "LucidBagSearch", bagFrame, "SearchBoxTemplate")
  searchBox:SetSize(10, 20)
  searchBox:SetPoint("TOPLEFT", bagFrame, "TOPLEFT", 8, -(titleH + 2))
  searchBox:SetPoint("TOPRIGHT", bagFrame, "TOPRIGHT", -8, -(titleH + 2))
  searchBox:SetAutoFocus(false); searchBox:SetFont("Fonts/FRIZQT__.TTF", 11, "")
  searchBox:SetTextColor(1, 1, 1)
  local searchBg = searchBox:CreateTexture(nil, "BACKGROUND")
  searchBg:SetAllPoints(); searchBg:SetColorTexture(0.05, 0.05, 0.05, 1)
  if searchBox.Left then searchBox.Left:Hide() end
  if searchBox.Right then searchBox.Right:Hide() end
  if searchBox.Middle then searchBox.Middle:Hide() end
  local sBTop = searchBox:CreateTexture(nil, "ARTWORK")
  sBTop:SetPoint("TOPLEFT", 0, 0); sBTop:SetPoint("TOPRIGHT", 0, 0); sBTop:SetHeight(1); sBTop:SetColorTexture(0,0,0,1)
  local sBBot = searchBox:CreateTexture(nil, "ARTWORK")
  sBBot:SetPoint("BOTTOMLEFT", 0, 0); sBBot:SetPoint("BOTTOMRIGHT", 0, 0); sBBot:SetHeight(1); sBBot:SetColorTexture(0,0,0,1)
  local sBL = searchBox:CreateTexture(nil, "ARTWORK")
  sBL:SetPoint("TOPLEFT", 0, 0); sBL:SetPoint("BOTTOMLEFT", 0, 0); sBL:SetWidth(1); sBL:SetColorTexture(0,0,0,1)
  local sBR = searchBox:CreateTexture(nil, "ARTWORK")
  sBR:SetPoint("TOPRIGHT", 0, 0); sBR:SetPoint("BOTTOMRIGHT", 0, 0); sBR:SetWidth(1); sBR:SetColorTexture(0,0,0,1)

  local function ApplySearch(text)
    text = (text or ""):lower()
    for _, slot in ipairs(slots) do
      if slot:IsShown() then
        local info = GetContainerInfo(slot._bagID, slot._slotID)
        if text == "" then
          slot:SetAlpha(1)
        elseif info.iconFileID then
          local itemName = info.hyperlink and C_Item.GetItemInfo(info.hyperlink)
          local match = itemName and itemName:lower():find(text, 1, true)
          slot:SetAlpha(match and 1 or 0.2)
        else
          slot:SetAlpha(0.2)
        end
      end
    end
  end
  searchBox:SetScript("OnTextChanged", function(self)
    ApplySearch(self:GetText()); SearchBoxTemplate_OnTextChanged(self)
  end)
  searchBox:SetScript("OnEscapePressed", function(self)
    self:SetText(""); self:ClearFocus(); ApplySearch("")
  end)
  bagFrame._search = searchBox

  local content = CreateFrame("Frame", nil, bagFrame)
  content:SetPoint("TOPLEFT", 8, -(titleH + 24 + 4))
  content:SetPoint("BOTTOMRIGHT", -8, 32)
  bagFrame._content = content

  local moneyText = bagFrame:CreateFontString(nil, "OVERLAY")
  moneyText:SetFont("Fonts/FRIZQT__.TTF", 10, "")
  moneyText:SetPoint("LEFT", title, "RIGHT", 8, 0)
  moneyText:SetTextColor(1, 1, 1)
  bagFrame._moneyText = moneyText

  local currencyBg = CreateFrame("Frame", nil, bagFrame)
  currencyBg:SetPoint("BOTTOMLEFT", 8, 4); currencyBg:SetPoint("BOTTOMRIGHT", -8, 4); currencyBg:SetHeight(16)
  bagFrame._currencyBg = currencyBg
  bagFrame._currencyContainer = currencyBg

  bagFrame:RegisterEvent("BAG_UPDATE")
  bagFrame:RegisterEvent("BAG_UPDATE_DELAYED")
  bagFrame:RegisterEvent("ITEM_LOCK_CHANGED")
  bagFrame:RegisterEvent("BAG_NEW_ITEMS_UPDATED")
  bagFrame:RegisterEvent("PLAYER_MONEY")
  bagFrame:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
  bagFrame:RegisterEvent("QUEST_ACCEPTED")
  bagFrame:RegisterEvent("QUEST_REMOVED")
  bagFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
  bagFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
  bagFrame:RegisterEvent("PLAYER_LOGOUT")

  if _G.TokenFrame and _G.TokenFrame.SetTokenWatched then
    hooksecurefunc(_G.TokenFrame, "SetTokenWatched", function()
      if bagFrame and bagFrame:IsShown() then LayoutBags() end
    end)
  end

  bagFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGOUT" then
      local point, _, relPoint, x, y = self:GetPoint()
      if point then DBSet("bagWinPos", {point, relPoint, x, y}) end
      return
    end
    if event == "PLAYER_MONEY" or event == "CURRENCY_DISPLAY_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
      if self:IsShown() then self._moneyText:SetText(FormatMoney(GetMoney())); LayoutBags() end
      return
    end
    if not self:IsShown() then return end
    if event == "PLAYER_EQUIPMENT_CHANGED" then RefreshBagBarIcons(); LayoutBags(); return end
    if event == "BAG_UPDATE_DELAYED" then RefreshBagBarIcons(); LayoutBags()
    elseif event == "BAG_UPDATE" then
      local bagID = ...
      for _, slot in ipairs(slots) do
        if slot:IsShown() and slot._bagID == bagID then UpdateSlot(slot) end
      end
    elseif event == "ITEM_LOCK_CHANGED" then
      local bagID, slotID = ...
      if bagID then
        for _, slot in ipairs(slots) do
          if slot:IsShown() and slot._bagID == bagID and slot._slotID == slotID then
            UpdateSlot(slot); break
          end
        end
      end
    else
      LayoutBags()
    end
  end)
end

-- ── Open / Close / Toggle ────────────────────────────────────────────
function B.OpenBags()
  if not DB("bagEnabled") then return false end
  if not bagFrame then BuildBagFrame() end
  if not bagFrame:IsShown() then
    bagFrame:Show(); LayoutBags()
    C_Timer.After(0.1, function() if bagFrame and bagFrame:IsShown() then LayoutBags() end end)
  end
  return true
end

function B.CloseBags()
  if bagFrame and bagFrame:IsShown() then
    bagFrame:Hide()
    if bagFrame._reagentWin then bagFrame._reagentWin:Hide() end
    if bagFrame._search then bagFrame._search:SetText("") end
    return true
  end
  return false
end

function B.ToggleBags()
  if not DB("bagEnabled") then return false end
  if bagFrame and bagFrame:IsShown() then return B.CloseBags() else return B.OpenBags() end
end

local refreshTimer = nil
RefreshBagBarIcons = function()
  if not bagFrame or not bagFrame._bagBarButtons then return end
  for _, btn in ipairs(bagFrame._bagBarButtons) do
    local invID = C_Container.ContainerIDToInventoryID(btn._bagIdx)
    local texID = GetInventoryItemTexture("player", invID)
    btn._tex:SetTexture(texID or 130716)
  end
  if bagFrame._reagentBarBtn then
    local rInvID = C_Container.ContainerIDToInventoryID(REAGENT_BAG)
    local rTexID = GetInventoryItemTexture("player", rInvID)
    bagFrame._reagentBarBtn._tex:SetTexture(rTexID or 4701557)
  end
end

function B.RefreshLayout()
  if not bagFrame or not bagFrame:IsShown() then return end
  if refreshTimer then refreshTimer:Cancel() end
  refreshTimer = C_Timer.NewTimer(0.05, function()
    refreshTimer = nil
    if bagFrame and bagFrame:IsShown() then LayoutBags() end
  end)
end

-- ── Hook into default bag keybinds ──────────────────────────────────
local hookFrame = CreateFrame("Frame")
hookFrame:RegisterEvent("PLAYER_LOGIN")
hookFrame:SetScript("OnEvent", function(self)
  self:UnregisterEvent("PLAYER_LOGIN")

  if not DB("bagEnabled") then return end

  -- Skip if ElvUI bags are active (avoid double-hook conflicts)
  local E = _G.ElvUI and _G.ElvUI[1]
  if E and E.private and E.private.bags and E.private.bags.enable then return end

  -- Suppress UseContainerItem taint popup
  local taintFrame = CreateFrame("Frame")
  taintFrame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
  taintFrame:SetScript("OnEvent", function(_, _, addon)
    if addon == "LucidUI" then StaticPopup_Hide("ADDON_ACTION_FORBIDDEN") end
  end)

  -- ── Append Item ID to all item tooltips ──────────────────────────────
  if TooltipDataProcessor then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
      if tooltip ~= GameTooltip or not data or not data.id then return end
      tooltip:AddLine("Item ID: " .. data.id, 0.4, 0.4, 0.5)
      tooltip:Show()
    end)
  end

  -- ── Suppress Blizzard container frames ──────────────────────────────
  -- hooksecurefunc is a POST-hook: the original function runs first (opening the Blizzard bag),
  -- then our callback fires. Fix: replace each Blizzard container frame's OnShow with an
  -- immediate Hide so they never render. No C_Timer needed - direct hide is safe in OnShow.
  local function SuppressBlizzardFrame(frame)
    if not frame then return end
    -- SetScript replaces OnShow entirely; no Blizzard logic needs to run for these frames.
    frame:SetScript("OnShow", function(self)
      if DB("bagEnabled") then self:Hide() end
    end)
    -- Also hide now in case it's already visible
    if DB("bagEnabled") and frame:IsShown() then frame:Hide() end
  end

  -- Midnight 12.x: combined bag frame is ContainerFrameCombinedBags
  SuppressBlizzardFrame(_G["ContainerFrameCombinedBags"])
  -- Legacy individual frames (still present in Midnight as fallback)
  for i = 1, 13 do
    SuppressBlizzardFrame(_G["ContainerFrame" .. i])
  end
  -- Extra Midnight-specific names
  SuppressBlizzardFrame(_G["BackpackFrame"])
  SuppressBlizzardFrame(_G["CombinedBagsFrame"])

  -- Hook bag functions (post-hooks) with guard to prevent double-toggle
  local _bagGuard = false
  local function GuardedToggle()
    if _bagGuard then return end
    _bagGuard = true
    B.ToggleBags()
    C_Timer.After(0, function() _bagGuard = false end)
  end
  local function GuardedOpen()
    if _bagGuard then return end
    _bagGuard = true
    B.OpenBags()
    C_Timer.After(0, function() _bagGuard = false end)
  end
  local function GuardedClose()
    if _bagGuard then return end
    _bagGuard = true
    B.CloseBags()
    C_Timer.After(0, function() _bagGuard = false end)
  end

  hooksecurefunc("ToggleAllBags",  GuardedToggle)
  hooksecurefunc("ToggleBackpack", GuardedToggle)
  hooksecurefunc("OpenAllBags",    GuardedOpen)
  hooksecurefunc("CloseAllBags",   GuardedClose)

  -- Hook backpack button directly (Midnight may use a different code path)
  local bpBtn = _G["MainMenuBarBackpackButton"]
  if bpBtn then
    bpBtn:HookScript("PostClick", GuardedToggle)
  end

  -- Hide default bag bar if option set
  if DB("bagHideDefaultBar") then
    local bagsBar = _G["BagsBar"]
    if bagsBar then
      bagsBar:Hide()
      bagsBar:SetScript("OnShow", function(s)
        if DB("bagEnabled") and DB("bagHideDefaultBar") then s:Hide() end
      end)
    end
  end

  -- Close bags on escape
  table.insert(UISpecialFrames, "LucidUIBags")

  -- Auto-open bags at bank, mail, AH etc.
  local autoFrame = CreateFrame("Frame")
  autoFrame:RegisterEvent("BANKFRAME_OPENED")
  autoFrame:RegisterEvent("BANKFRAME_CLOSED")
  autoFrame:RegisterEvent("MAIL_SHOW")
  autoFrame:RegisterEvent("MAIL_CLOSED")
  autoFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
  autoFrame:RegisterEvent("AUCTION_HOUSE_CLOSED")
  autoFrame:RegisterEvent("MERCHANT_SHOW")
  autoFrame:RegisterEvent("MERCHANT_CLOSED")
  autoFrame:RegisterEvent("TRADE_SHOW")
  autoFrame:RegisterEvent("TRADE_CLOSED")
  autoFrame:RegisterEvent("GUILDBANKFRAME_OPENED")
  autoFrame:RegisterEvent("GUILDBANKFRAME_CLOSED")
  autoFrame:SetScript("OnEvent", function(_, event)
    local isOpen   = event:match("_OPENED$") or event:match("_SHOW$")
    local isClosed = event:match("_CLOSED$")
    if isOpen then
      local src = event:match("^(.+)_")
      if (src == "BANKFRAME"      and DB("bagAutoBank"))
      or (src == "MAIL"           and DB("bagAutoMail"))
      or (src == "AUCTION_HOUSE"  and DB("bagAutoAH"))
      or (src == "MERCHANT")
      or (src == "TRADE")
      or (src == "GUILDBANKFRAME" and DB("bagAutoBank")) then
        B.OpenBags()
      end
    elseif isClosed then
      B.CloseBags()
    end
  end)
end)

-- ── Settings Tab ─────────────────────────────────────────────────────
function B.SetupSettings(parent)
  local container = CreateFrame("Frame", nil, parent)
  local MakeCard  = NS._SMakeCard
  local MakePage  = NS._SMakePage
  local Sep       = NS._SSep
  local R         = NS._SR

  local sc, Add = MakePage(container)

  -- ── Card: Enable ──────────────────────────────────────────────────
  local cEn = MakeCard(sc, "LucidUI Bags")
  local enableCB
  enableCB = NS.ChatGetCheckbox(cEn.inner, "Enable LucidUI Bags", 26, function(state)
    DBSet("bagEnabled", state)
    StaticPopupDialogs["LUCIDUI_BAGS_RELOAD"] = {
      text    = "LucidUI Bags requires a UI reload to " .. (state and "activate" or "deactivate") .. ".\n\nReload now?",
      button1 = "Reload", button2 = "Cancel",
      OnAccept = function() ReloadUI() end,
      OnCancel = function() DBSet("bagEnabled", not state); if enableCB then enableCB:SetValue(not state) end end,
      timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopup_Show("LUCIDUI_BAGS_RELOAD")
  end, "Replace default bags (requires reload)")
  enableCB.option = "bagEnabled"; R(cEn, enableCB, 26)
  local hideBagBarCB
  hideBagBarCB = NS.ChatGetCheckbox(cEn.inner, "Hide Default Bag Bar", 26, function(state)
    DBSet("bagHideDefaultBar", state)
    NS.ShowReloadPopup("LucidUI: Bag bar visibility changed. Reload to apply.")
  end, "Hide the default WoW bag bar (requires reload)")
  hideBagBarCB.option = "bagHideDefaultBar"; R(cEn, hideBagBarCB, 26)
  cEn:Finish(); Add(cEn); Add(Sep(sc), 9)

  -- ── Card: Layout ──────────────────────────────────────────────────
  local cLayout = MakeCard(sc, "Layout")
  local iconSize = NS.ChatGetSlider(cLayout.inner, "Icon Size",  20, 64, "%dpx", function(v) DBSet("bagIconSize", v);    B.RefreshLayout() end); iconSize.option    = "bagIconSize";    R(cLayout, iconSize, 40)
  local spacing  = NS.ChatGetSlider(cLayout.inner, "Spacing",     0, 12, "%dpx", function(v) DBSet("bagSpacing", v);     B.RefreshLayout() end); spacing.option     = "bagSpacing";     R(cLayout, spacing, 40)
  local columns  = NS.ChatGetSlider(cLayout.inner, "Columns",      4, 20, "%d",   function(v) DBSet("bagColumns", v);     B.RefreshLayout() end); columns.option     = "bagColumns";     R(cLayout, columns, 40)
  cLayout:Finish(); Add(cLayout); Add(Sep(sc), 9)

  -- ── Card: Display flags ───────────────────────────────────────────
  local cDisp = MakeCard(sc, "Display")
  local function DCB(lbl, key, cb, tip)
    local w = NS.ChatGetCheckbox(cDisp.inner, lbl, 26, cb, tip); w.option = key; R(cDisp, w, 26); return w
  end
  local function DPair(lbl1,key1,cb1,tip1, lbl2,key2,cb2,tip2)
    local row=CreateFrame("Frame",nil,cDisp.inner); row:SetHeight(26)
    cDisp:Row(row,26); row:SetPoint("LEFT",cDisp.inner,"LEFT",0,0); row:SetPoint("RIGHT",cDisp.inner,"RIGHT",0,0)
    local lh=CreateFrame("Frame",nil,row); lh:SetPoint("TOPLEFT",row,"TOPLEFT",0,0); lh:SetPoint("BOTTOMRIGHT",row,"BOTTOM",-2,0)
    local rh=CreateFrame("Frame",nil,row); rh:SetPoint("TOPLEFT",row,"TOP",2,0); rh:SetPoint("BOTTOMRIGHT",row,"BOTTOMRIGHT",0,0)
    local w1=NS.ChatGetCheckbox(lh,lbl1,26,cb1,tip1); w1:ClearAllPoints(); w1:SetAllPoints(lh); w1.option=key1
    local w2=NS.ChatGetCheckbox(rh,lbl2,26,cb2,tip2); w2:ClearAllPoints(); w2:SetAllPoints(rh); w2.option=key2
    return w1,w2
  end
  local showIlvl,   showCount   = DPair("Item Level",      "bagShowIlvl",       function(s) DBSet("bagShowIlvl",s);       B.RefreshLayout() end, "Show item level on gear",
                                         "Stack Count",      "bagShowCount",       function(s) DBSet("bagShowCount",s);      B.RefreshLayout() end, "Show stack count")
  local showQuality,showJunk    = DPair("Quality Borders",  "bagShowQuality",    function(s) DBSet("bagShowQuality",s);    B.RefreshLayout() end, "Colored borders by quality",
                                         "Junk Icon",        "bagShowJunk",        function(s) DBSet("bagShowJunk",s);       B.RefreshLayout() end, "Coin icon on junk items")
  local junkDesat,  newGlow     = DPair("Desaturate Junk",  "bagJunkDesaturate", function(s) DBSet("bagJunkDesaturate",s); B.RefreshLayout() end, "Grey out junk items",
                                         "New Item Glow",    "bagNewItemGlow",     function(s) DBSet("bagNewItemGlow",s);    B.RefreshLayout() end, "Gold pulse on new items")
  local questIcon,  upgradeArrow= DPair("Quest Icon",       "bagQuestIcon",      function(s) DBSet("bagQuestIcon",s);      B.RefreshLayout() end, "Quest icon on quest items",
                                         "Upgrade Arrow",    "bagShowUpgrade",     function(s) DBSet("bagShowUpgrade",s);    B.RefreshLayout() end, "Arrow on upgrade items")
  local reverseSlots,transpCB  = DPair("Reverse Slot Order","bagSortReverse",    function(s) DBSet("bagSortReverse",s);    B.RefreshLayout() end, "Reverse item order",
                                         "Transparent Slots","bagTransparent",     function(s) DBSet("bagTransparent",s);    B.RefreshLayout() end, "Semi-transparent slot backgrounds")
  cDisp:Finish(); Add(cDisp); Add(Sep(sc), 9)

  -- ── Card: Splitting ───────────────────────────────────────────────
  local cSplit = MakeCard(sc, "Splitting")
  local splitReagent = DCB and nil  -- reuse pattern via local helper
  local function SPair(lbl1,key1,cb1,tip1, lbl2,key2,cb2,tip2)
    local row=CreateFrame("Frame",nil,cSplit.inner); row:SetHeight(26)
    cSplit:Row(row,26); row:SetPoint("LEFT",cSplit.inner,"LEFT",0,0); row:SetPoint("RIGHT",cSplit.inner,"RIGHT",0,0)
    local lh=CreateFrame("Frame",nil,row); lh:SetPoint("TOPLEFT",row,"TOPLEFT",0,0); lh:SetPoint("BOTTOMRIGHT",row,"BOTTOM",-2,0)
    local rh=CreateFrame("Frame",nil,row); rh:SetPoint("TOPLEFT",row,"TOP",2,0); rh:SetPoint("BOTTOMRIGHT",row,"BOTTOMRIGHT",0,0)
    local w1=NS.ChatGetCheckbox(lh,lbl1,26,cb1,tip1); w1:ClearAllPoints(); w1:SetAllPoints(lh); w1.option=key1
    local w2=NS.ChatGetCheckbox(rh,lbl2,26,cb2,tip2); w2:ClearAllPoints(); w2:SetAllPoints(rh); w2.option=key2
    return w1,w2
  end
  local splitBags
  splitReagent, splitBags = SPair("Separate Reagent Bag","bagSplitReagent",function(s) DBSet("bagSplitReagent",s); B.RefreshLayout() end,"Reagent bag in own window",
                                   "Split Individual Bags","bagSplitBags",   function(s) DBSet("bagSplitBags",s);    B.RefreshLayout() end,"Gap between each bag")
  local splitSpacing  = NS.ChatGetSlider(cSplit.inner, "Split Spacing", 2, 20, "%dpx", function(v) DBSet("bagSplitSpacing",v); B.RefreshLayout() end); splitSpacing.option = "bagSplitSpacing"; R(cSplit, splitSpacing, 40)
  cSplit:Finish(); Add(cSplit); Add(Sep(sc), 9)

  -- ── Card: Auto Open ───────────────────────────────────────────────
  local cAuto = MakeCard(sc, "Auto Open")
  local function APair(lbl1,key1,tip1, lbl2,key2,tip2)
    local row=CreateFrame("Frame",nil,cAuto.inner); row:SetHeight(26)
    cAuto:Row(row,26); row:SetPoint("LEFT",cAuto.inner,"LEFT",0,0); row:SetPoint("RIGHT",cAuto.inner,"RIGHT",0,0)
    local lh=CreateFrame("Frame",nil,row); lh:SetPoint("TOPLEFT",row,"TOPLEFT",0,0); lh:SetPoint("BOTTOMRIGHT",row,"BOTTOM",-2,0)
    local rh=CreateFrame("Frame",nil,row); rh:SetPoint("TOPLEFT",row,"TOP",2,0); rh:SetPoint("BOTTOMRIGHT",row,"BOTTOMRIGHT",0,0)
    local w1=NS.ChatGetCheckbox(lh,lbl1,26,function(s) DBSet(key1,s) end,tip1); w1:ClearAllPoints(); w1:SetAllPoints(lh); w1.option=key1
    local w2=NS.ChatGetCheckbox(rh,lbl2,26,function(s) DBSet(key2,s) end,tip2); w2:ClearAllPoints(); w2:SetAllPoints(rh); w2.option=key2
    return w1,w2
  end
  local function ACB(lbl,key,tip) local w=NS.ChatGetCheckbox(cAuto.inner,lbl,26,function(s) DBSet(key,s) end,tip); w.option=key; R(cAuto,w,26); return w end
  local autoBank,autoMail = APair("Bank","bagAutoBank","Auto-open at bank", "Mailbox","bagAutoMail","Auto-open at mailbox")
  local autoAH            = ACB("Auction House","bagAutoAH","Auto-open at AH")
  cAuto:Finish(); Add(cAuto); Add(Sep(sc), 9)

  -- ── Card: Font & Opacity ──────────────────────────────────────────
  local cFont = MakeCard(sc, "Font & Opacity")

  local ilvlPosDD = NS.ChatGetDropdown(cFont.inner, "Item Level Position",
    function(v) return (DB("bagIlvlPos") or "BOTTOMLEFT")==v end,
    function(v) DBSet("bagIlvlPos",v); B.RefreshLayout() end)
  ilvlPosDD:Init({"Bottom Left","Bottom Right","Center Bottom"},{"BOTTOMLEFT","BOTTOMRIGHT","BOTTOM"})
  R(cFont, ilvlPosDD, 50)

  local ilvlSize = NS.ChatGetSlider(cFont.inner,"Item Level Font Size",6,16,"%dpt",function(v) DBSet("bagIlvlSize",v); B.RefreshLayout() end); ilvlSize.option="bagIlvlSize"; R(cFont, ilvlSize, 40)

  local countPosDD = NS.ChatGetDropdown(cFont.inner, "Count Position",
    function(v) return (DB("bagCountPos") or "BOTTOMRIGHT")==v end,
    function(v) DBSet("bagCountPos",v); B.RefreshLayout() end)
  countPosDD:Init({"Top Left","Top Right","Bottom Left","Bottom Right"},{"TOPLEFT","TOPRIGHT","BOTTOMLEFT","BOTTOMRIGHT"})
  R(cFont, countPosDD, 50)

  local countSize = NS.ChatGetSlider(cFont.inner,"Count Font Size",6,16,"%dpt",function(v) DBSet("bagCountSize",v); B.RefreshLayout() end); countSize.option="bagCountSize"; R(cFont, countSize, 40)

  local slotAlpha = NS.ChatGetSlider(cFont.inner,"Slot Opacity",0,100,"%d%%",function(value)
    DBSet("bagSlotBgAlpha",value/100)
    local alpha=(DB("bagTransparent") and (value/100*0.3) or (value/100))
    for _,slot in ipairs(slots) do
      if slot:IsShown() and slot._bg then
        local r,g,b=slot._bg:GetVertexColor()
        slot._bg:SetColorTexture(r,g,b,alpha); slot._bgAlpha=alpha
      end
    end
  end)
  slotAlpha.option="bagSlotBgAlpha"; slotAlpha._isPercent=true; R(cFont, slotAlpha, 40)

  cFont:Finish(); Add(cFont)

  -- ── OnShow ───────────────────────────────────────────────────────
  container:SetScript("OnShow", function()
    local all = {
      enableCB, hideBagBarCB, showIlvl, showCount, showQuality, showJunk,
      junkDesat, newGlow, questIcon, upgradeArrow, reverseSlots, transpCB,
      splitReagent, splitBags, autoBank, autoMail, autoAH,
      iconSize, spacing, columns, splitSpacing,
      ilvlSize, countSize, slotAlpha,
    }
    for _, f in ipairs(all) do
      if f and f.SetValue and f.option then
        local v = DB(f.option)
        if v ~= nil then
          if f._isPercent then f:SetValue(v*100) else f:SetValue(v) end
        end
      end
    end
    if ilvlPosDD.SetValue  then ilvlPosDD:SetValue()  end
    if countPosDD.SetValue then countPosDD:SetValue() end
  end)

  return container
end