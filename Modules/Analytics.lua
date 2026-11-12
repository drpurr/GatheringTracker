---@class GT
local GT = LibStub("AceAddon-3.0"):GetAddon("GatheringTracker")

function GT:RunAnalytics()
   if not WagoAnalytics then
      return
   end
   local WagoAnalytics = LibStub("WagoAnalytics"):Register("Xb6XQbKp")

   WagoAnalytics:Switch("MinimapButton", GT.db.profile.miniMap.hide)
   WagoAnalytics:Switch("IncludeBank", GT.db.profile.General.includeBank)
   WagoAnalytics:Switch("IncludeWarband", GT.db.profile.General.includeWarband)
   WagoAnalytics:Switch("InstanceHide", GT.db.profile.General.instanceHide)
   WagoAnalytics:Switch("GroupHide", GT.db.profile.General.groupHide)
   WagoAnalytics:Switch("ShowDelve", GT.db.profile.General.showDelve)
   WagoAnalytics:Switch("ShowFollower", GT.db.profile.General.showFollower)
   WagoAnalytics:Switch("CombatHide", GT.db.profile.General.combatHide)
   WagoAnalytics:Switch("ItemTooltip", GT.db.profile.General.itemTooltip)
   WagoAnalytics:Switch("AlertsEnable", GT.db.profile.General.alertsEnable)
   WagoAnalytics:Switch("LockWindow", GT.db.profile.General.lockWindow)
   WagoAnalytics:Switch("WindowCollapsed", GT.db.profile.General.windowCollapsed)

   WagoAnalytics:SetCounter("maxRows", GT.db.profile.General.maxRows)
   WagoAnalytics:SetCounter("tsmPrice", GT.db.profile.General.tsmPrice)


   local numCustomFilters = 0
   if next(GT.db.profile.CustomFiltersTable) then
      for k, v in pairs(GT.db.profile.CustomFiltersTable) do
         numCustomFilters = numCustomFilters + 1
      end
   end
   WagoAnalytics:SetCounter("NumberOfCustomFilters", numCustomFilters)

   local numAlertItems = 0
   if next(GT.db.profile.Alerts) then
      for k, v in pairs(GT.db.profile.Alerts) do
         numAlertItems = numAlertItems + 1
      end
   end
   WagoAnalytics:SetCounter("NumberOfAlertItems", numAlertItems)
end
