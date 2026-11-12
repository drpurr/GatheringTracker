---@class GT
local GT = LibStub("AceAddon-3.0"):GetAddon("GatheringTracker")

-- Localize global functions
local floor = math.floor
local format = string.format
local ipairs = ipairs
local max = math.max
local min = math.min
local pairs = pairs
local table = table
local GetTime = GetTime

---The session window: a summary panel on the left and one row per gathered item on the right.
---All text uses the game's own font objects so it follows the client font and any UI replacement addon.
GT.Window = {}
local W = GT.Window

W.SUMMARY_WIDTH = 220
W.LIST_WIDTH = 330
W.HEADER_HEIGHT = 32
W.STAT_HEIGHT = 16
W.STAT_GAP = 6
W.ROW_HEIGHT = 22
W.ROW_GAP = 2
W.PADDING = 10
W.BUTTON_HEIGHT = 24
W.PANEL_GAP = 4
W.NEW_PICKUP_SECONDS = 8
W.TOTALS_ID = 9999999998

local COIN_GOLD = "|cffffd100g|r"
local COIN_SILVER = "|cffc7c7cfs|r"
local COIN_COPPER = "|cffeda55fc|r"

local SOLID = "Interface\\Buttons\\WHITE8X8"

---Formats copper as e.g. 386g40s12c, dropping the gold part when there is none (20s73c)
---@param copper number|nil
---@return string
function W.FormatMoney(copper)
   copper = floor((copper or 0) + 0.5)
   if copper < 0 then
      copper = 0
   end
   local gold = floor(copper / 10000)
   local silver = floor(copper / 100) % 100
   local cop = copper % 100
   if gold > 0 then
      return format("%d%s%02d%s%02d%s", gold, COIN_GOLD, silver, COIN_SILVER, cop, COIN_COPPER)
   end
   return format("%02d%s%02d%s", silver, COIN_SILVER, cop, COIN_COPPER)
end

---Category (Herb, Ore, ...) of a known gatherable item, nil for custom items and currencies
---@param itemID number
---@return string|nil
function W.GetCategory(itemID)
   if not W.categoryByID then
      W.categoryByID = {}
      for _, itemData in ipairs(GT.ItemDataFlat) do
         if itemData.id and itemData.id > 0 and not W.categoryByID[itemData.id] and itemData.expansion ~= "Currency" then
            W.categoryByID[itemData.id] = itemData.category
         end
      end
   end
   return W.categoryByID[itemID]
end

---Price of one item in copper from the selected price source, 0 when there is none
---@param itemID number
---@return number
function W.GetItemPriceCopper(itemID)
   local price = GT:GetItemPrice(itemID)
   if not price then
      return 0
   end
   return floor(price * 10000 + 0.5)
end

---Collects the rows to display: every tracked item gathered this session, newest change first
---@return table rows
function W:BuildEntries()
   local entries = {}
   for itemID, data in pairs(GT.InventoryData) do
      if data.sessionCount and data.sessionCount > 0 then
         local isCurrency = data.itemType == "Currency"
         local count = data.sessionCount
         local value = 0
         if not isCurrency then
            value = count * W.GetItemPriceCopper(itemID)
         end
         table.insert(entries, {
            id = itemID,
            count = count,
            value = value,
            isCurrency = isCurrency,
            category = (not isCurrency) and W.GetCategory(itemID) or nil,
            seq = data.changeSeq or 0,
            delta = data.lastDelta,
            changedAt = data.changedAt,
         })
      end
   end
   table.sort(entries, function(a, b)
      if a.seq ~= b.seq then
         return a.seq > b.seq
      end
      return a.id < b.id
   end)
   return entries
end

---Sums the session values shown in the summary panel
---@param entries table
---@return table totals { herb, ore, items, count, looted, total } values in copper
function W:ComputeTotals(entries)
   local totals = { herb = 0, ore = 0, items = 0, count = 0 }
   for _, entry in ipairs(entries) do
      if not entry.isCurrency then
         totals.items = totals.items + entry.value
         totals.count = totals.count + entry.count
         if entry.category == "Herb" then
            totals.herb = totals.herb + entry.value
         elseif entry.category == "Ore" then
            totals.ore = totals.ore + entry.value
         end
      end
   end
   totals.looted = GT.Session.looted or 0
   totals.total = totals.items + totals.looted
   return totals
end

---Gold per hour in copper, nil during the first minute when the estimate would be meaningless
---@param totalCopper number
---@param elapsed number seconds
---@return number|nil
function W.GoldPerHour(totalCopper, elapsed)
   if not elapsed or elapsed < 60 then
      return nil
   end
   return totalCopper / (elapsed / 3600)
end

---------------------------------------------------------------------------
-- Frame construction
---------------------------------------------------------------------------

local function CreateFlatButton(parent, text)
   local button = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
   button:SetHeight(W.BUTTON_HEIGHT)
   button:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1 })
   button:SetBackdropColor(0.11, 0.11, 0.11, 1)
   button:SetBackdropBorderColor(0.23, 0.23, 0.23, 1)
   button:SetNormalFontObject("GameFontHighlight")
   button:SetHighlightFontObject("GameFontHighlight")
   button:SetText(text)
   button:RegisterForClicks("LeftButtonUp")
   button:SetScript("OnEnter", function(self)
      self:SetBackdropColor(0.16, 0.16, 0.16, 1)
      self:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
   end)
   button:SetScript("OnLeave", function(self)
      self:SetBackdropColor(0.11, 0.11, 0.11, 1)
      self:SetBackdropBorderColor(0.23, 0.23, 0.23, 1)
   end)
   return button
end

local function SavePosition(frame)
   local point, _, relativePoint, xPos, yPos = frame:GetPoint()
   GT.db.profile.General.relativePoint = point
   GT.db.profile.General.windowRelativePoint = relativePoint
   GT.db.profile.General.xPos = xPos
   GT.db.profile.General.yPos = yPos
end

function W:ApplyPosition()
   local general = GT.db.profile.General
   self.frame:ClearAllPoints()
   self.frame:SetPoint(general.relativePoint or "TOPLEFT", UIParent, general.windowRelativePoint or general.relativePoint or "TOPLEFT", general.xPos or 200, general.yPos or -150)
end

function W:ApplyScale()
   self.frame:SetScale(GT.db.profile.General.windowScale or 1)
end

local STAT_DEFINITIONS = {
   { key = "time", label = "Time:" },
   { key = "looted", label = "Looted gold:" },
   { key = "herb", label = "Herb value:" },
   { key = "ore", label = "Ore value:" },
   { key = "gph", label = "G/h:" },
}

function W:Create()
   if self.frame then
      return self.frame
   end

   local root = CreateFrame("Frame", "GatheringTrackerWindow", UIParent)
   root:SetFrameStrata("MEDIUM")
   root:SetClampedToScreen(true)
   root:SetMovable(true)
   root:SetSize(W.SUMMARY_WIDTH, 100)
   self.frame = root

   -- Summary panel
   local summary = CreateFrame("Frame", nil, root)
   summary:SetPoint("TOPLEFT", root, "TOPLEFT")
   summary:SetWidth(W.SUMMARY_WIDTH)
   summary.bg = summary:CreateTexture(nil, "BACKGROUND")
   summary.bg:SetAllPoints()
   summary.bg:SetColorTexture(0, 0, 0, 0.78)
   summary.highlight = summary:CreateTexture(nil, "OVERLAY")
   summary.highlight:SetAllPoints()
   summary.highlight:Hide()
   self.summary = summary

   -- Header: drag to move, right-click for the filters menu
   local header = CreateFrame("Button", nil, summary)
   header:SetPoint("TOPLEFT", summary, "TOPLEFT")
   header:SetPoint("TOPRIGHT", summary, "TOPRIGHT")
   header:SetHeight(W.HEADER_HEIGHT)
   header.bg = header:CreateTexture(nil, "BACKGROUND")
   header.bg:SetAllPoints()
   header.bg:SetColorTexture(0, 0, 0, 0.45)
   header:RegisterForDrag("LeftButton")
   header:RegisterForClicks("RightButtonUp")
   header:SetScript("OnDragStart", function()
      if not GT.db.profile.General.lockWindow then
         root:StartMoving()
         root.isMoving = true
      end
   end)
   header:SetScript("OnDragStop", function()
      if root.isMoving then
         root:StopMovingOrSizing()
         root.isMoving = false
         SavePosition(root)
      end
   end)
   header:SetScript("OnClick", function(self, button)
      if button == "RightButton" then
         GT:GenerateFiltersMenu(self)
      end
   end)
   header:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine(GT.metaData.name)
      if not GT.db.profile.General.lockWindow then
         GameTooltip:AddLine("|cff8080ffDrag|r to move", 1, 1, 1)
      end
      GameTooltip:AddLine("|cff8080ffRight-Click|r to open the Filter Menu", 1, 1, 1)
      GameTooltip:Show()
   end)
   header:SetScript("OnLeave", function(self)
      if GameTooltip:GetOwner() == self then
         GameTooltip:Hide()
      end
   end)
   self.header = header

   local collapse = CreateFrame("Button", nil, header)
   collapse:SetSize(24, 24)
   collapse:SetPoint("LEFT", header, "LEFT", 4, 0)
   collapse:RegisterForClicks("LeftButtonUp")
   collapse.horizontal = collapse:CreateTexture(nil, "ARTWORK")
   collapse.horizontal:SetColorTexture(1, 1, 1, 1)
   collapse.horizontal:SetSize(12, 2)
   collapse.horizontal:SetPoint("CENTER")
   collapse.vertical = collapse:CreateTexture(nil, "ARTWORK")
   collapse.vertical:SetColorTexture(1, 1, 1, 1)
   collapse.vertical:SetSize(2, 12)
   collapse.vertical:SetPoint("CENTER")
   collapse.vertical:Hide()
   collapse:SetScript("OnClick", function()
      W:ToggleCollapsed()
   end)
   collapse:SetScript("OnEnter", function(self)
      self.horizontal:SetVertexColor(1, 0.82, 0, 1)
      self.vertical:SetVertexColor(1, 0.82, 0, 1)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine(GT.db.profile.General.windowCollapsed and "Expand item list" or "Collapse item list", 1, 1, 1)
      GameTooltip:Show()
   end)
   collapse:SetScript("OnLeave", function(self)
      self.horizontal:SetVertexColor(1, 1, 1, 1)
      self.vertical:SetVertexColor(1, 1, 1, 1)
      if GameTooltip:GetOwner() == self then
         GameTooltip:Hide()
      end
   end)
   self.collapseButton = collapse

   local title = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
   title:SetPoint("CENTER", header, "CENTER")
   title:SetText(GT.metaData.name)
   self.title = title

   -- Stat lines
   self.stats = {}
   for _, definition in ipairs(STAT_DEFINITIONS) do
      local label = summary:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      label:SetJustifyH("LEFT")
      label:SetText(definition.label)
      local value = summary:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      value:SetJustifyH("RIGHT")
      self.stats[definition.key] = { label = label, value = value, shown = true }
   end

   -- Session buttons
   local pause = CreateFlatButton(summary, "Pause")
   pause:SetScript("OnClick", function()
      GT:ToggleSessionPause()
   end)
   self.pauseButton = pause

   local reset = CreateFlatButton(summary, "Reset")
   reset:SetScript("OnClick", function()
      GT:ResetSession()
   end)
   self.resetButton = reset

   -- Item list
   local list = CreateFrame("Frame", nil, root)
   list:SetPoint("TOPLEFT", summary, "TOPRIGHT", W.PANEL_GAP, 0)
   list:SetWidth(W.LIST_WIDTH)
   list:SetHeight(1)
   self.list = list
   self.rows = {}

   local footer = CreateFrame("Frame", nil, list)
   footer:SetSize(W.LIST_WIDTH, W.ROW_HEIGHT)
   footer.bg = footer:CreateTexture(nil, "BACKGROUND")
   footer.bg:SetAllPoints()
   footer.bg:SetColorTexture(0, 0, 0, 0.55)
   footer.text = footer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
   footer.text:SetPoint("CENTER")
   footer:Hide()
   self.footer = footer

   GT.Display.Frames[W.TOTALS_ID] = summary

   self:ApplyPosition()
   self:ApplyScale()

   self.ticker = C_Timer.NewTicker(1, function()
      if root:IsShown() then
         W:UpdateLiveStats()
      end
   end)

   self:Refresh()
   return root
end

---Gets or creates the row frame for an item. Rows belong to one item so alert highlights follow it.
function W:GetRow(itemID)
   local row = self.rows[itemID]
   if row then
      return row
   end

   row = CreateFrame("Frame", nil, self.list)
   row:SetSize(W.LIST_WIDTH, W.ROW_HEIGHT)
   row.itemID = itemID

   row.bg = row:CreateTexture(nil, "BACKGROUND")
   row.bg:SetAllPoints()
   row.bg:SetColorTexture(0, 0, 0, 0.55)

   row.highlight = row:CreateTexture(nil, "OVERLAY")
   row.highlight:SetAllPoints()
   row.highlight:Hide()

   row.count = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
   row.count:SetPoint("LEFT", row, "LEFT", 4, 0)
   row.count:SetWidth(42)
   row.count:SetJustifyH("RIGHT")

   row.icon = row:CreateTexture(nil, "ARTWORK")
   row.icon:SetSize(16, 16)
   row.icon:SetPoint("LEFT", row.count, "RIGHT", 6, 0)

   row.iconBorder = row:CreateTexture(nil, "OVERLAY")
   row.iconBorder:SetTexture("Interface\\Common\\WhiteIconFrame")
   row.iconBorder:SetAllPoints(row.icon)

   row.iconQuality = row:CreateTexture(nil, "OVERLAY", nil, 2)
   row.iconQuality:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -3, 3)
   row.iconQuality:SetSize(12, 12)
   row.iconQuality:Hide()

   row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
   row.value:SetPoint("RIGHT", row, "RIGHT", -8, 0)
   row.value:SetJustifyH("RIGHT")

   row.delta = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
   row.delta:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
   row.delta:SetTextColor(0.12, 1, 0)

   row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
   row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
   row.name:SetPoint("RIGHT", row.delta, "LEFT", -6, 0)
   row.name:SetJustifyH("LEFT")
   row.name:SetWordWrap(false)

   row:SetScript("OnEnter", function(self)
      if not GT.db.profile.General.itemTooltip then
         return
      end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if self.isCurrency then
         GameTooltip:SetCurrencyByID(self.itemID)
      else
         GameTooltip:SetItemByID(self.itemID)
      end
      GameTooltip:Show()
   end)
   row:SetScript("OnLeave", function(self)
      if GameTooltip:GetOwner() == self then
         GameTooltip:Hide()
      end
   end)

   self.rows[itemID] = row
   GT.Display.Frames[itemID] = row
   return row
end

local function GetItemDisplayInfo(entry)
   if entry.isCurrency then
      local info = C_CurrencyInfo.GetCurrencyInfo(entry.id)
      if info then
         return info.name, info.iconFileID or 134400, info.quality or 1
      end
      return "Currency " .. entry.id, 134400, 1
   end

   local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(entry.id)
   if not name then
      name = C_Item.GetItemInfo(entry.id)
   end
   if not name then
      -- Not cached yet: show the known name and refresh once the client has the item
      for _, itemData in ipairs(GT.ItemDataFlat) do
         if itemData.id == entry.id then
            name = itemData.name
            break
         end
      end
      if Item and Item.CreateFromItemID and not W.pendingItems[entry.id] then
         W.pendingItems[entry.id] = true
         Item:CreateFromItemID(entry.id):ContinueOnItemLoad(function()
            W.pendingItems[entry.id] = nil
            W:Refresh()
         end)
      end
   end
   return name or ("Item " .. entry.id), C_Item.GetItemIconByID(entry.id) or 134400, C_Item.GetItemQualityByID(entry.id) or 1
end
W.pendingItems = {}

local function SetQualityOverlay(row, entry)
   row.iconQuality:Hide()
   if entry.isCurrency or not (C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityByItemInfo) then
      return
   end
   local quality = C_TradeSkillUI.GetItemReagentQualityByItemInfo(entry.id)
   if not quality then
      return
   end
   local atlas
   local itemIndex = GT:TableFind(GT.ItemDataFlat, entry.id, "id")
   if itemIndex and GT.ItemDataFlat[itemIndex].expansion == "Midnight" then
      atlas = "Professions-Icon-Quality-12-Tier" .. quality .. "-Inv"
   else
      atlas = "professions-icon-quality-tier" .. quality .. "-inv"
   end
   row.iconQuality:SetAtlas(atlas)
   row.iconQuality:Show()
end

function W:UpdateRow(row, entry, now)
   local name, icon, quality = GetItemDisplayInfo(entry)
   local r, g, b = C_Item.GetItemQualityColor(quality)
   row.isCurrency = entry.isCurrency
   row.count:SetText(entry.count .. "x")
   row.icon:SetTexture(icon)
   row.iconBorder:SetVertexColor(r or 1, g or 1, b or 1, 0.9)
   row.name:SetText("[" .. name .. "]")
   row.name:SetTextColor(r or 1, g or 1, b or 1)
   SetQualityOverlay(row, entry)

   if entry.isCurrency or entry.value <= 0 then
      row.value:SetText("")
   else
      row.value:SetText(W.FormatMoney(entry.value))
   end

   if entry.delta and entry.changedAt and (now - entry.changedAt) < W.NEW_PICKUP_SECONDS then
      row.delta:SetText("+" .. entry.delta)
   else
      row.delta:SetText("")
   end
   row:EnableMouse(GT.db.profile.General.itemTooltip and true or false)
end

---Sets a stat line's value and whether it is shown; returns true when visibility changed
function W:SetStat(key, text, shown)
   local stat = self.stats[key]
   stat.value:SetText(text or "")
   local changed = stat.shown ~= shown
   stat.shown = shown
   stat.label:SetShown(shown)
   stat.value:SetShown(shown)
   return changed
end

function W:UpdateSummary(totals)
   local elapsed = GT.Timer:Elapsed()
   self:SetStat("time", GT.Timer.CreateTimerText(elapsed), true)
   self:SetStat("looted", W.FormatMoney(totals.looted), true)
   local changed = self:SetStat("herb", W.FormatMoney(totals.herb), totals.herb > 0)
   changed = self:SetStat("ore", W.FormatMoney(totals.ore), totals.ore > 0) or changed
   local gph = W.GoldPerHour(totals.total, elapsed)
   self:SetStat("gph", gph and W.FormatMoney(gph) or "--", true)
   self.pauseButton:SetText(GT.Timer.Paused and "Resume" or "Pause")
   return changed
end

---Updates the values that change every second (timer, G/h and the +N pickup markers)
function W:UpdateLiveStats()
   if not self.frame or not self.lastTotals then
      return
   end
   local elapsed = GT.Timer:Elapsed()
   self:SetStat("time", GT.Timer.CreateTimerText(elapsed), true)
   local gph = W.GoldPerHour(self.lastTotals.total, elapsed)
   self:SetStat("gph", gph and W.FormatMoney(gph) or "--", true)

   local now = GetTime()
   for _, entry in ipairs(self.lastEntries or {}) do
      local row = self.rows[entry.id]
      if row and row:IsShown() and entry.changedAt and (now - entry.changedAt) >= W.NEW_PICKUP_SECONDS then
         row.delta:SetText("")
      end
   end
end

function W:Layout(visibleRows, overflow)
   local y = -(W.HEADER_HEIGHT + W.PADDING)
   for _, definition in ipairs(STAT_DEFINITIONS) do
      local stat = self.stats[definition.key]
      if stat.shown then
         stat.label:ClearAllPoints()
         stat.label:SetPoint("TOPLEFT", self.summary, "TOPLEFT", W.PADDING, y)
         stat.value:ClearAllPoints()
         stat.value:SetPoint("TOPRIGHT", self.summary, "TOPRIGHT", -W.PADDING, y)
         y = y - (W.STAT_HEIGHT + W.STAT_GAP)
      end
   end
   y = y - (W.PADDING - W.STAT_GAP)

   local buttonWidth = (W.SUMMARY_WIDTH - W.PADDING * 3) / 2
   self.pauseButton:ClearAllPoints()
   self.pauseButton:SetPoint("TOPLEFT", self.summary, "TOPLEFT", W.PADDING, y)
   self.pauseButton:SetWidth(buttonWidth)
   self.resetButton:ClearAllPoints()
   self.resetButton:SetPoint("TOPLEFT", self.pauseButton, "TOPRIGHT", W.PADDING, 0)
   self.resetButton:SetWidth(buttonWidth)

   local summaryHeight = -y + W.BUTTON_HEIGHT + W.PADDING
   self.summary:SetHeight(summaryHeight)

   local listHeight = 0
   local count = #visibleRows
   if overflow > 0 then
      count = count + 1
   end
   if count > 0 then
      listHeight = count * W.ROW_HEIGHT + (count - 1) * W.ROW_GAP
   end
   self.list:SetHeight(max(listHeight, 1))

   local listShown = listHeight > 0 and not GT.db.profile.General.windowCollapsed
   self.list:SetShown(listShown)

   local width = W.SUMMARY_WIDTH
   local height = summaryHeight
   if listShown then
      width = width + W.PANEL_GAP + W.LIST_WIDTH
      height = max(height, listHeight)
   end
   self.frame:SetSize(width, height)
end

---Rebuilds the window from GT.InventoryData. Safe to call often.
---@return table entries the rows that were displayed (for alerts and tests)
function W:Refresh()
   if not self.frame then
      return {}
   end
   local entries = self:BuildEntries()
   local totals = self:ComputeTotals(entries)
   self.lastEntries = entries
   self.lastTotals = totals

   local now = GetTime()
   local maxRows = GT.db.profile.General.maxRows or 12
   local visibleRows = {}
   local shownIDs = {}
   for index, entry in ipairs(entries) do
      if index <= maxRows then
         local row = self:GetRow(entry.id)
         self:UpdateRow(row, entry, now)
         row:ClearAllPoints()
         if index == 1 then
            row:SetPoint("TOPLEFT", self.list, "TOPLEFT")
         else
            row:SetPoint("TOPLEFT", visibleRows[#visibleRows], "BOTTOMLEFT", 0, -W.ROW_GAP)
         end
         row:Show()
         shownIDs[entry.id] = true
         table.insert(visibleRows, row)
      end
   end
   for itemID, row in pairs(self.rows) do
      if not shownIDs[itemID] then
         row:Hide()
      end
   end

   local overflow = max(#entries - maxRows, 0)
   if overflow > 0 then
      self.footer:ClearAllPoints()
      self.footer:SetPoint("TOPLEFT", visibleRows[#visibleRows], "BOTTOMLEFT", 0, -W.ROW_GAP)
      self.footer.text:SetText(format("and %d more", overflow))
      self.footer:Show()
   else
      self.footer:Hide()
   end

   self:UpdateSummary(totals)
   self:UpdateCollapseGlyph()
   self:Layout(visibleRows, overflow)
   return entries
end

function W:UpdateCollapseGlyph()
   self.collapseButton.vertical:SetShown(GT.db.profile.General.windowCollapsed and true or false)
end

function W:ToggleCollapsed()
   GT.db.profile.General.windowCollapsed = not GT.db.profile.General.windowCollapsed
   self:Refresh()
end

---Hides the row for an item that is no longer tracked. The frame is kept for reuse
---because WoW frames cannot be destroyed.
function W:RemoveRow(itemID)
   local row = self.rows[itemID]
   if row then
      row:Hide()
      row.highlight:Hide()
   end
end
