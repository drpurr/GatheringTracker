---@class GT
local GT = LibStub("AceAddon-3.0"):GetAddon("GatheringTracker")

-- Localize global functions
local pairs = pairs

function GT:ToggleGatheringTracker()
   GT.Debug("Toggle Gathering Tracker", 1, GT.db.profile.General.enable)
   local key = not GT.db.profile.General.enable
   GT.db.profile.General.enable = key
   GT.Enabled = key
   if key then
      GT:OnEnable()
      GT:SetDisplayState()
      GT:InventoryUpdate("Toggle Gathering Tracker", false)
      GT:ResetSession()
      GT:StartSession()
   elseif not key then
      GT:OnDisable()
      GT:ClearDisplay()
      GT.Timer:Stop()
      GT:SetDisplayState()
   end
end

function GT:ClearFilters()
   --disables all enabled filters
   GT.Debug("Clear Filters", 1)

   for id, value in pairs(GT.db.profile.Filters) do
      GT.db.profile.Filters[id] = nil
   end
   for id, value in pairs(GT.db.profile.CustomFiltersTable) do
      GT.db.profile.CustomFiltersTable[id] = false
   end
   for id, value in pairs(GT.db.profile.currencyFilters) do
      GT.db.profile.currencyFilters[id] = nil
   end

   GT:RebuildIDTables()
   GT:ClearDisplay()
end

---Hides or shows the window until the next reload (key binding)
function GT:ToggleDisplay()
   GT.userHidden = not GT.userHidden
   GT:SetDisplayState()
end

---Collapses or expands the item list (key binding)
function GT:ToggleItemList()
   GT.Window:ToggleCollapsed()
end
