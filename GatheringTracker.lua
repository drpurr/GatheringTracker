GatheringTracker = LibStub("AceAddon-3.0"):NewAddon("GatheringTracker", "AceEvent-3.0", "AceComm-3.0")
---@class GT : AceAddon-3.0, AceEvent-3.0, AceGUI-3.0
local GT = GatheringTracker

GT.InventoryData = {}
GT.Display = {}
GT.Display.Frames = {}
GT.PlayerEnteringWorld = true
GT.DebugCount = 0
GT.Options = {}
GT.changeSeq = 0

---Per-session state that is not tied to a single item
GT.Session = {
   looted = 0,      -- copper gained this session (money going up while the session is running)
   lastMoney = nil, -- GetMoney() at the last update
}

-- Localize global functions
local ipairs = ipairs
local math = math
local pairs = pairs
local GetTime = GetTime

GT.metaData = {
   name = C_AddOns.GetAddOnMetadata("GatheringTracker", "Title"),
   version = C_AddOns.GetAddOnMetadata("GatheringTracker", "Version"),
   notes = C_AddOns.GetAddOnMetadata("GatheringTracker", "Notes"),
}

local gameVersions = {
   [WOW_PROJECT_MAINLINE or 1] = "retail",
   [WOW_PROJECT_CLASSIC or 2] = "era",
   [WOW_PROJECT_BURNING_CRUSADE_CLASSIC or 5] = "bc",
   [WOW_PROJECT_WRATH_CLASSIC or 11] = "wrath",
   [WOW_PROJECT_CATACLYSM_CLASSIC or 14] = "cata",
   [WOW_PROJECT_CAMELOT or 18] = "forever",
   [WOW_PROJECT_MISTS_CLASSIC or 19] = "mop"
}
GT.gameVersion = gameVersions[WOW_PROJECT_ID] or "retail"
if WOW_PROJECT_ID == WOW_PROJECT_CLASSIC and C_Seasons and C_Seasons.GetActiveSeason and (C_Seasons.GetActiveSeason() == 2) then
   GT.gameVersion = "season"
end

BINDING_HEADER_GATHERINGTRACKER = GT.metaData.name .. " v" .. GT.metaData.version

function GT:OnEnable()
   if GT.Enabled then
      --use this for both initial setup on UI load and when the addon is enabled from the settings
      ChatFrame1:AddMessage("|cffff6f00" .. GT.metaData.name .. " v" .. GT.metaData.version .. "|r|cff00ff00 ENABLED|r")

      --Register events for updating item details
      GT:RegisterEvent("BAG_UPDATE")
      GT:RegisterEvent("PLAYER_MONEY", "InventoryUpdate")
      GT:RegisterEvent("CURRENCY_DISPLAY_UPDATE", "BAG_UPDATE")
      GT:RegisterEvent("GROUP_ROSTER_UPDATE")
      GT:RegisterEvent("PLAYER_ENTERING_WORLD")
      if GT.db.profile.General.combatHide then
         GT:RegisterEvent("PLAYER_REGEN_DISABLED")
         GT:RegisterEvent("PLAYER_REGEN_ENABLED")
      end

      GT:MinimapHandler(not GT.db.profile.miniMap.hide)
   else
      GT:OnDisable()
   end
end

function GT:OnDisable()
   if not GT.Enabled then
      --Use this for disabling the addon from the settings
      --stop event tracking
      ChatFrame1:AddMessage("|cffff6f00" .. GT.metaData.name .. " v" .. GT.metaData.version .. "|r|cffff0000 DISABLED|r")

      --Unregister events so that we can stop working when disabled
      GT:UnregisterEvent("BAG_UPDATE")
      GT:UnregisterEvent("PLAYER_MONEY")
      GT:UnregisterEvent("CURRENCY_DISPLAY_UPDATE")
      GT:UnregisterEvent("GROUP_ROSTER_UPDATE")
      GT:UnregisterEvent("PLAYER_ENTERING_WORLD")
      GT:UnregisterEvent("PLAYER_REGEN_DISABLED")
      GT:UnregisterEvent("PLAYER_REGEN_ENABLED")

      GT:MinimapHandler(false)
   else
      GT:OnEnable()
   end
end

function GT:PLAYER_ENTERING_WORLD()
   GT.Debug("PLAYER_ENTERING_WORLD", 1)

   if not GT:SetDisplayState() then
      return
   end

   if C_CurrencyInfo.RequestCurrencyDataForAccountCharacters and GT.gameVersion == "retail" then
      C_CurrencyInfo.RequestCurrencyDataForAccountCharacters()
   end

   GT:wait(6, "InventoryUpdate", "PLAYER_ENTERING_WORLD", false)
   GT:wait(8, "AllowAlertEffects", "AllowAlertEffects")
end

function GT:GROUP_ROSTER_UPDATE(event)
   GT.Debug("GROUP_ROSTER_UPDATE", 1, event)

   GT:SetDisplayState()
end

function GT:BAG_UPDATE(event)
   if GT.PlayerEnteringWorld == false then
      GT:InventoryUpdate(event, true)
   end
end

---Fires when the player enters combat
function GT:PLAYER_REGEN_DISABLED()
   GT.combat = true
   GT:SetDisplayState()
end

---Fires when the player exits combat
function GT:PLAYER_REGEN_ENABLED()
   GT.combat = false
   GT:SetDisplayState()
end

---Shows or hides the window based on the enable option and the Auto Hide options
---@return boolean shown
function GT:SetDisplayState()
   if not GT.baseFrame then
      return false
   end
   local shown = GT.Enabled and GT:DisplayVisibility() and not GT.userHidden
   GT.baseFrame.frame:SetShown(shown and true or false)
   return shown and true or false
end

---Creates the session window. GT.baseFrame is kept for the filters menu and key bindings.
function GT:CreateBaseFrame()
   local frame = GT.Window:Create()
   GT.baseFrame = GT.baseFrame or {}
   GT.baseFrame.frame = frame
   GT:SetDisplayState()
end

function GT:OptionsHide()
   if GT.baseFrame then
      --Do an inventory update if we dont have any information
      if next(GT.InventoryData) == nil and GT.Enabled then
         GT:InventoryUpdate("InterfaceOptionsFrame:OnHide", false)
      end
   end
end

---Forgets all item data and empties the window
function GT:ClearDisplay()
   GT.Debug("Clear Display", 1)
   for itemID in pairs(GT.InventoryData) do
      GT.Window:RemoveRow(itemID)
   end
   GT.InventoryData = {}
   for _, data in ipairs(GT.IDs or {}) do
      data.processed = false
   end
   GT.Window:Refresh()
end

function GT:RebuildDisplay(event)
   GT.Debug("Rebuild Display", 1, event)
   GT:PrepareDataForDisplay(event)
end

---Stops tracking an item when its filter is turned off
---@param key boolean true if the filter was enabled, in which case nothing is removed
---@param itemID number
function GT:RemoveItemData(key, itemID)
   if key then
      return
   end

   GT.Debug("Remove Item Data", 3, key, itemID)

   if GT.InventoryData[itemID] then
      GT.InventoryData[itemID] = nil
   end
   GT.Window:RemoveRow(itemID)
   GT.Window:Refresh()
end

---Refreshes the window and runs the alert system on the new values
function GT:PrepareDataForDisplay(event, wait)
   GT.Debug("Prepare Data for Display", 1, event, wait)
   if wait then
      GT:wait(0.1, "PrepareDataForDisplay", "PrepareDataForDisplay", false)
      return
   end

   GT:SetTSMPriceSource()

   local entries = GT.Window:Refresh()
   local totals = GT.Window.lastTotals

   for _, entry in ipairs(entries) do
      GT.AlertSystem:Alerts(entry.id, entry.count, entry.value / 10000)
   end
   if totals and totals.count > 0 then
      GT.AlertSystem:Alerts(2, totals.count, totals.items / 10000)
   end
end

function GT:InventoryUpdate(event, wait)
   GT.Debug("InventoryUpdate", 1, event, wait)
   if wait then
      GT:wait(0.1, "InventoryUpdate", "InventoryUpdate", false)
      return
   end
   if event == nil then
      local traceback = debugstack()
      GT.Debug(traceback, 1, event)
      return
   end
   if not GT.Enabled then
      return
   end
   if not GT:SetDisplayState() then
      GT.Debug("InventoryUpdate: Instance Hide", 2)
      return
   end
   if GT.PlayerEnteringWorld == true then
      GT.PlayerEnteringWorld = false
   end

   GT:ProcessData(event)
end

---Tracks money gained this session. Spending money never lowers the value and money gained
---while the session is paused is ignored.
function GT:UpdateMoney()
   local money = GetMoney()
   if GT.Session.lastMoney and money > GT.Session.lastMoney and not GT.Timer.Paused then
      GT.Session.looted = GT.Session.looted + (money - GT.Session.lastMoney)
   end
   GT.Session.lastMoney = money
end

---Reads the current count of every tracked item and works out how many were gained this session
function GT:ProcessData(event)
   GT.Debug("ProcessData", 1, event)

   GT:UpdateMoney()

   local now = GetTime()
   for index, data in ipairs(GT.IDs) do
      local itemCount = 0
      if data.itemType and data.itemType == "Currency" then
         local info = C_CurrencyInfo.GetCurrencyInfo(data.id)
         itemCount = info and info.quantity or 0
         if GT.db.profile.General.accountCurrency and C_CurrencyInfo.FetchCurrencyDataFromAccountCharacters then
            local accountCurrency = C_CurrencyInfo.FetchCurrencyDataFromAccountCharacters(data.id)
            if accountCurrency ~= nil then
               for _, characterData in ipairs(accountCurrency) do
                  itemCount = itemCount + characterData.quantity
               end
            end
         end
      else
         itemCount = C_Item.GetItemCount(
            data.id,
            GT.db.profile.General.includeBank,
            false,
            false,
            GT.db.profile.General.includeWarband
         ) or 0
      end

      local itemData = GT.InventoryData[data.id] or GT:ItemDataConstructor(data.id)
      GT.InventoryData[data.id] = itemData
      itemData.count = itemCount

      if not data.processed then
         itemData.startAmount = itemCount
         data.processed = true
      end

      local previous = itemData.sessionCount or 0
      if GT.Timer.Paused then
         -- items picked up or used while paused do not change the session
         itemData.startAmount = itemCount - previous
      end

      itemData.sessionCount = itemData.count - itemData.startAmount

      if itemData.sessionCount < 0 then
         itemData.sessionCount = 0
         itemData.startAmount = itemCount
      end

      if itemData.sessionCount > previous then
         GT.changeSeq = GT.changeSeq + 1
         itemData.changeSeq = GT.changeSeq
         itemData.lastDelta = itemData.sessionCount - previous
         itemData.changedAt = now
      end

      if data.itemType then
         itemData.itemType = data.itemType
      end
   end

   if not GT.Timer.Started and not GT.Timer.Paused then
      GT.Timer:Start()
   end

   GT:PrepareDataForDisplay("Process Data")
end

--- Creates an itemData Construct
---@param itemID integer ID of the item to create
---@return table itemData
function GT:ItemDataConstructor(itemID)
   GT.Debug("ItemDataConstructor", 6, itemID)

   local itemData = {}
   itemData.count = 0
   itemData.startAmount = 0
   itemData.sessionCount = 0

   return itemData
end

---------------------------------------------------------------------------
-- Session controls (window buttons, key bindings, minimap button)
---------------------------------------------------------------------------

---Zeroes the session: timer, looted gold and every item count
function GT:ResetSession()
   GT.Debug("Reset Session", 1)

   GT.Timer:Reset()
   GT.Session.looted = 0
   GT.Session.lastMoney = GetMoney()
   for itemID, itemData in pairs(GT.InventoryData) do
      itemData.startAmount = itemData.count
      itemData.sessionCount = 0
      itemData.changeSeq = nil
      itemData.lastDelta = nil
      itemData.changedAt = nil
   end

   GT.AlertSystem:ResetAlerts()

   GT:RebuildDisplay("Reset Session")
end

---Starts the session timer, or resumes it when paused
function GT:StartSession()
   GT.Debug("Start Session", 1)

   GT.Timer:Start()
   GT:RebuildDisplay("Start Session")
end

---Pauses the session: the timer stops and nothing gathered is counted until resumed
function GT:PauseSession()
   GT.Debug("Pause Session", 1)

   GT.Timer:Pause()
   GT:RebuildDisplay("Pause Session")
end

function GT:ToggleSessionPause()
   if GT.Timer.Running then
      GT:PauseSession()
   else
      GT:StartSession()
   end
end
