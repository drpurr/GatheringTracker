-- Offline tests for the GatheringTracker session window.
-- Usage: lua5.1 tests/run_tests.lua   (run from the addon folder)
-- Loads the real addon files (in .toc order) on top of a mock WoW client running WoW Forever,
-- then drives every window element and checks the result. Library stand-ins live in
-- tests/libstubs.lua, so nothing outside this repository is needed.

local root = arg[0]:match("^(.*)/tests/run_tests%.lua$") or "."

local M = dofile(root .. "/tests/wowmock.lua")
M.install()

---------------------------------------------------------------------------
-- Tiny test framework
---------------------------------------------------------------------------
local passed, failed = 0, 0
local currentGroup = ""
local function group(name) currentGroup = name; print("\n" .. name) end
local function check(description, condition, detail)
   if condition then
      passed = passed + 1
      print("  PASS " .. description)
   else
      failed = failed + 1
      print("  FAIL " .. description .. (detail and ("  -- " .. tostring(detail)) or ""))
   end
end
local function eq(description, actual, expected)
   check(description, actual == expected, ("expected %s, got %s"):format(tostring(expected), tostring(actual)))
end

assert(loadfile(root .. "/tests/libstubs.lua"))(M)
local registeredOptions = M.registeredOptions
local function load(path, ...)
   local chunk = assert(loadfile(path))
   return chunk(...)
end

---------------------------------------------------------------------------
-- Saved variables from an older version, to check the migration
---------------------------------------------------------------------------
GatheringTrackerDB = {
   profileKeys = { ["Tester - TestRealm"] = "Default" },
   profiles = {
      Default = {
         General = { iconWidth = 40, textFont = "Fira Mono Medium", sessionOnly = true, collapseDisplay = true, unlock = true },
         Filters = { [1] = true, [2] = true, [3] = true },
      },
   },
}

---------------------------------------------------------------------------
-- Load the addon in .toc order
---------------------------------------------------------------------------
local tocFiles = {}
for line in io.lines(root .. "/GatheringTracker.toc") do
   line = line:gsub("\r", "")
   if line:match("%.lua$") then
      table.insert(tocFiles, (line:gsub("\\", "/")))
   end
end

group("Loading")
local loadOk, loadErr = pcall(function()
   for _, file in ipairs(tocFiles) do
      load(root .. "/" .. file, "GatheringTracker", {})
   end
end)
check("all .toc Lua files load", loadOk, loadErr)
if not loadOk then os.exit(1) end

local GT = GatheringTracker

-- Items in the test world
local PEACEBLOOM, SILVERLEAF, LICHEN, COPPER, TIN, LEATHER, CUSTOM = 2447, 765, 249399, 2770, 2771, 2318, 999001
M.items[PEACEBLOOM] = { name = "Peacebloom", quality = 1, icon = 1001 }
M.items[SILVERLEAF] = { name = "Silverleaf", quality = 1, icon = 1002 }
M.items[COPPER] = { name = "Copper Ore", quality = 1, icon = 1003 }
M.items[TIN] = { name = "Tin Ore", quality = 1, icon = 1004 }
M.items[LEATHER] = { name = "Light Leather", quality = 1, icon = 1005 }
-- Frilled Lichen is deliberately not in the client cache, to test the name fallback
M.prices[PEACEBLOOM] = 1930   -- 19s30c
M.prices[SILVERLEAF] = 1200
M.prices[LICHEN] = 5000
M.prices[COPPER] = 2500
M.prices[TIN] = 4000
M.prices[LEATHER] = 3000
M.bags[PEACEBLOOM] = 5 -- already in bags before the session starts
M.money = 1000000

local initOk, initErr = pcall(function()
   M.fireEvent("ADDON_LOADED", "GatheringTracker")
   M.loggedIn = true
   M.fireEvent("PLAYER_LOGIN")
   M.fireEvent("PLAYER_ENTERING_WORLD")
   M.advance(9)
end)
check("addon initializes and enables without errors", initOk, initErr)
if not initOk then os.exit(1) end

local W = GT.Window
local general = GT.db.profile.General

local function setFilters(ids)
   for _, id in ipairs(ids) do
      GT.db.profile.Filters[id] = true
      GT:UpdateIDTable(id, true)
   end
end
local function bagUpdate()
   M.fireEvent("BAG_UPDATE")
   M.advance(0.2)
end
local function stat(key) return W.stats[key] end
local function statShown(key) return stat(key).label:IsShown() and stat(key).value:IsShown() end
local function statText(key) return stat(key).value:GetText() end
local function visibleRowIDs()
   local ids = {}
   local list = {}
   for id, row in pairs(W.rows) do
      if row:IsShown() then table.insert(list, row) end
   end
   -- follow the anchor chain from the top of the list
   local byAnchor = {}
   for _, row in ipairs(list) do
      local _, relativeTo = row:GetPoint(1)
      byAnchor[relativeTo] = row
   end
   local current = byAnchor[W.list]
   while current do
      table.insert(ids, current.itemID)
      current = byAnchor[current]
   end
   return ids
end

---------------------------------------------------------------------------
group("Migration of old settings")
eq("old icon option removed", general.iconWidth, nil)
eq("old font option removed", general.textFont, nil)
eq("old collapse option removed", general.collapseDisplay, nil)
eq("retired Current Gold filter removed", GT.db.profile.Filters[1], nil)
eq("retired Session Timer filter removed", GT.db.profile.Filters[3], nil)
eq("max rows default", general.maxRows, 12)

---------------------------------------------------------------------------
group("Window structure")
check("window created", W.frame ~= nil)
check("window shown", W.frame:IsShown())
eq("title is one word", W.title:GetText(), "GatheringTracker")
check("collapse button shows a minus", W.collapseButton.horizontal:IsShown() and not W.collapseButton.vertical:IsShown())
check("no filter button in the header", W.header.filterButton == nil)
eq("pause button label", W.pauseButton:GetText(), "Pause")
eq("reset button label", W.resetButton:GetText(), "Reset")
check("Time line shown", statShown("time"))
check("Looted gold line shown", statShown("looted"))
check("G/h line shown", statShown("gph"))
check("Herb value hidden before anything is gathered", not statShown("herb"))
check("Ore value hidden before anything is gathered", not statShown("ore"))
check("item list hidden while empty", not W.list:IsShown())
eq("window is just the summary while empty", W.frame:GetWidth(), W.SUMMARY_WIDTH)

---------------------------------------------------------------------------
group("Fonts follow the game")
local hardcoded, nonGame = {}, {}
for _, widget in ipairs(M.allFrames) do
   if widget._type == "FontString" then
      local ancestor = widget
      local inWindow = false
      while ancestor do
         if ancestor == W.frame then inWindow = true break end
         ancestor = ancestor._parent
      end
      if inWindow then
         if widget._hardcodedFont then table.insert(hardcoded, widget._hardcodedFont) end
         local font = widget._fontObject or (widget._parent and widget._parent._normalFont)
         if not (type(font) == "string" and font:match("^GameFont")) then
            table.insert(nonGame, tostring(font))
         end
      end
   end
end
eq("no font file is set directly on window text", #hardcoded, 0)
eq("all window text uses a game font object", #nonGame, 0)

---------------------------------------------------------------------------
group("Gathering adds one row per item")
registeredOptions["GatheringTracker"].args.Display.args.tsmPrice.set(nil, 1) -- TSM - DBMarket
setFilters({ PEACEBLOOM, SILVERLEAF, LICHEN, COPPER, TIN, LEATHER })
GT:InventoryUpdate("test", false)
eq("items already in bags are not counted", #visibleRowIDs(), 0)

M.bags[PEACEBLOOM] = 8
bagUpdate()
local row = W.rows[PEACEBLOOM]
check("Peacebloom row shown", row and row:IsShown())
eq("count shows session amount", row.count:GetText(), "3x")
eq("name in brackets", row.name:GetText(), "[Peacebloom]")
eq("+N marks the pickup", row.delta:GetText(), "+3")
eq("row value", row.value:GetText(), W.FormatMoney(3 * 1930))
eq("icon set", row.icon:GetTexture(), 1001)
check("list shown", W.list:IsShown())
check("Herb value shown after gathering a herb", statShown("herb"))
eq("Herb value amount", statText("herb"), W.FormatMoney(3 * 1930))
check("Ore value still hidden", not statShown("ore"))

M.bags[PEACEBLOOM] = 10
bagUpdate()
eq("same item stays on one line", #visibleRowIDs(), 1)
eq("count accumulates", W.rows[PEACEBLOOM].count:GetText(), "5x")
eq("+N shows the latest pickup", W.rows[PEACEBLOOM].delta:GetText(), "+2")

M.bags[COPPER] = 4
bagUpdate()
eq("newest item is on top", visibleRowIDs()[1], COPPER)
check("Ore value shown after mining", statShown("ore"))
eq("Ore value amount", statText("ore"), W.FormatMoney(4 * 2500))

M.bags[LEATHER] = 2
bagUpdate()
eq("leather row added", visibleRowIDs()[1], LEATHER)
eq("leather does not change Herb value", statText("herb"), W.FormatMoney(5 * 1930))
eq("leather does not change Ore value", statText("ore"), W.FormatMoney(4 * 2500))

M.bags[LICHEN] = 1
bagUpdate()
eq("uncached Forever herb uses the known name", W.rows[LICHEN].name:GetText(), "[Frilled Lichen]")
eq("Forever herb counts as Herb value", statText("herb"), W.FormatMoney(5 * 1930 + 5000))

M.advance(W.NEW_PICKUP_SECONDS + 1)
eq("+N marker clears after a few seconds", W.rows[PEACEBLOOM].delta:GetText(), "")

M.bags[PEACEBLOOM] = 7
bagUpdate()
eq("using some items lowers the count", W.rows[PEACEBLOOM].count:GetText(), "2x")

---------------------------------------------------------------------------
group("Money formatting")
eq("gold, silver, copper", W.FormatMoney(3864012), "386|cffffd100g|r40|cffc7c7cfs|r12|cffeda55fc|r")
eq("no gold part under 1g", W.FormatMoney(2073), "20|cffc7c7cfs|r73|cffeda55fc|r")
eq("small amount padded", W.FormatMoney(115), "01|cffc7c7cfs|r15|cffeda55fc|r")
eq("negative shows zero", W.FormatMoney(-5), "00|cffc7c7cfs|r00|cffeda55fc|r")

---------------------------------------------------------------------------
group("Looted gold")
M.money = M.money + 41207
M.fireEvent("PLAYER_MONEY")
M.advance(0.2)
eq("money gained is shown", statText("looted"), W.FormatMoney(41207))
M.money = M.money - 20000
M.fireEvent("PLAYER_MONEY")
M.advance(0.2)
eq("spending money does not lower it", statText("looted"), W.FormatMoney(41207))

---------------------------------------------------------------------------
group("Time and G/h")
eq("G/h waits for the first minute", statText("gph"), "--")
local elapsedBefore = GT.Timer:Elapsed()
M.advance(3600)
check("timer counts up", GT.Timer:Elapsed() >= elapsedBefore + 3600)
eq("time text", statText("time"), GT.Timer.CreateTimerText(GT.Timer:Elapsed()))
check("time shows an hour", statText("time"):match("^01:") ~= nil, statText("time"))
W:UpdateLiveStats() -- the ticker last ran up to a second ago
local totals = W.lastTotals
local expectedGph = W.GoldPerHour(totals.total, GT.Timer:Elapsed())
eq("G/h is session value per hour", statText("gph"), W.FormatMoney(expectedGph))
check("G/h includes looted gold and items", totals.total == totals.items + totals.looted and totals.looted == 41207)

---------------------------------------------------------------------------
group("Pause / Resume button")
W.pauseButton:Click()
eq("label changes to Resume", W.pauseButton:GetText(), "Resume")
check("timer paused", GT.Timer.Paused and not GT.Timer.Running)
local frozen = GT.Timer:Elapsed()
M.advance(30)
eq("time stops while paused", GT.Timer:Elapsed(), frozen)
M.bags[PEACEBLOOM] = 20
bagUpdate()
eq("gathering while paused is not counted", W.rows[PEACEBLOOM].count:GetText(), "2x")
M.money = M.money + 5000
M.fireEvent("PLAYER_MONEY")
M.advance(0.2)
eq("money while paused is not counted", statText("looted"), W.FormatMoney(41207))
W.pauseButton:Click()
eq("label back to Pause", W.pauseButton:GetText(), "Pause")
check("timer running", GT.Timer.Running)
M.bags[PEACEBLOOM] = 21
bagUpdate()
eq("gathering after resume counts", W.rows[PEACEBLOOM].count:GetText(), "3x")
M.advance(10)
check("time continues after resume", GT.Timer:Elapsed() > frozen)

---------------------------------------------------------------------------
group("Reset button")
W.resetButton:Click()
eq("no rows after reset", #visibleRowIDs(), 0)
check("list hidden after reset", not W.list:IsShown())
check("Herb value hidden after reset", not statShown("herb"))
check("Ore value hidden after reset", not statShown("ore"))
eq("looted gold zero", statText("looted"), W.FormatMoney(0))
eq("time zero", statText("time"), "00:00:00")
check("still running after reset", GT.Timer.Running)
M.bags[TIN] = 3
bagUpdate()
eq("tracking continues after reset", W.rows[TIN].count:GetText(), "3x")
check("only Ore value after a mining-only session", statShown("ore") and not statShown("herb"))

---------------------------------------------------------------------------
group("Collapse (minus) button")
W.collapseButton:Click()
check("list hidden when collapsed", not W.list:IsShown())
eq("collapsed state saved", general.windowCollapsed, true)
check("button shows a plus when collapsed", W.collapseButton.vertical:IsShown())
eq("window shrinks to the summary", W.frame:GetWidth(), W.SUMMARY_WIDTH)
check("summary still shown", W.summary:IsShown() and statShown("time"))
W.collapseButton:Click()
check("list shown again", W.list:IsShown())
check("button back to minus", not W.collapseButton.vertical:IsShown())
eq("window width includes the list", W.frame:GetWidth(), W.SUMMARY_WIDTH + W.PANEL_GAP + W.LIST_WIDTH)
M.fire(W.collapseButton, "OnEnter")
eq("collapse tooltip", GameTooltip._lines[1], "Collapse item list")
M.fire(W.collapseButton, "OnLeave")

---------------------------------------------------------------------------
group("Header: drag to move, right-click for filters")
M.dragTarget = { x = 640, y = 480 }
M.fire(W.header, "OnDragStart")
check("window starts moving", W.frame._moving)
M.fire(W.header, "OnDragStop")
check("window stops moving", not W.frame._moving)
eq("x position saved", general.xPos, 640)
eq("y position saved", general.yPos, 480)
eq("anchor saved", general.relativePoint, "TOPLEFT")
W:ApplyPosition()
local p, rel, relPoint, x, y = W.frame:GetPoint()
check("saved position is restored", p == "TOPLEFT" and rel == UIParent and relPoint == "BOTTOMLEFT" and x == 640 and y == 480,
   table.concat({ tostring(p), tostring(relPoint), tostring(x), tostring(y) }, " "))
general.lockWindow = true
M.fire(W.header, "OnDragStart")
check("locked window does not move", not W.frame._moving)
general.lockWindow = false
local menusBefore = #M.menus
W.header:Click("RightButton")
eq("right-click opens the filter menu", #M.menus, menusBefore + 1)
W.header:Click("LeftButton")
eq("left-click does not open a menu", #M.menus, menusBefore + 1)
M.fire(W.header, "OnEnter")
check("header tooltip explains drag and right-click",
   table.concat(GameTooltip._lines, "\n"):match("Drag") and table.concat(GameTooltip._lines, "\n"):match("Right%-Click"))
M.fire(W.header, "OnLeave")
check("tooltip hidden on leave", not GameTooltip:IsShown())

---------------------------------------------------------------------------
group("Row tooltips")
local tinRow = W.rows[TIN]
check("row accepts the mouse when tooltips are on", tinRow:IsMouseEnabled())
M.fire(tinRow, "OnEnter")
eq("item tooltip shown for the row", GameTooltip._item, TIN)
M.fire(tinRow, "OnLeave")
check("tooltip hidden on leave", not GameTooltip:IsShown())
registeredOptions["GatheringTracker"].args.Display.args.itemTooltip.set(nil, false)
check("row ignores the mouse when tooltips are off", not W.rows[TIN]:IsMouseEnabled())
registeredOptions["GatheringTracker"].args.Display.args.itemTooltip.set(nil, true)

---------------------------------------------------------------------------
group("Max rows and overflow")
general.maxRows = 3
M.bags[PEACEBLOOM] = 25; bagUpdate()
M.bags[SILVERLEAF] = 2; bagUpdate()
M.bags[COPPER] = 9; bagUpdate()
M.bags[LEATHER] = 6; bagUpdate()
eq("only max rows shown", #visibleRowIDs(), 3)
check("overflow footer shown", W.footer:IsShown())
eq("overflow footer text", W.footer.text:GetText(), "and 2 more")
eq("list height covers rows and footer", W.list:GetHeight(), 4 * W.ROW_HEIGHT + 3 * W.ROW_GAP)
general.maxRows = 12
GT:RebuildDisplay("test")
check("footer hidden when everything fits", not W.footer:IsShown())

---------------------------------------------------------------------------
group("Prices")
M.prices[SILVERLEAF] = nil
GT:RebuildDisplay("test")
eq("unpriced item shows no value", W.rows[SILVERLEAF].value:GetText(), "")
registeredOptions["GatheringTracker"].args.Display.args.tsmPrice.set(nil, 0)
check("no price source hides Herb value", not statShown("herb"))
check("no price source hides Ore value", not statShown("ore"))
check("rows still shown without prices", #visibleRowIDs() > 0)
registeredOptions["GatheringTracker"].args.Display.args.tsmPrice.set(nil, 1)
check("Herb value back with a price source", statShown("herb"))

---------------------------------------------------------------------------
group("Removing a filter")
GT.db.profile.Filters[LEATHER] = nil
GT:UpdateIDTable(LEATHER, false)
GT:RemoveItemData(false, LEATHER)
check("row removed when its filter is turned off", not W.rows[LEATHER]:IsShown())

---------------------------------------------------------------------------
group("Alerts")
eq("rows are registered for highlight alerts", GT.Display.Frames[PEACEBLOOM], W.rows[PEACEBLOOM])
eq("summary is registered for total alerts", GT.Display.Frames[W.TOTALS_ID], W.summary)
local fakeAlert = { itemID = 123456 }
function fakeAlert:GetAlertType() return "Highlight" end
function fakeAlert:GetTriggerValue() return 1 end
check("clearing an alert for an item without a row does not error", pcall(GT.AlertSystem.ClearAlert, GT.AlertSystem, fakeAlert))

---------------------------------------------------------------------------
group("Auto hide, key bindings and scale")
local combatHide = registeredOptions["GatheringTracker"].args.General.args.combatHide
combatHide.set(nil, true)
M.fireEvent("PLAYER_REGEN_DISABLED")
check("hidden in combat", not W.frame:IsShown())
M.fireEvent("PLAYER_REGEN_ENABLED")
check("shown after combat", W.frame:IsShown())
combatHide.set(nil, false)
GT:ToggleDisplay()
check("Toggle Display binding hides", not W.frame:IsShown())
GT:ToggleDisplay()
check("Toggle Display binding shows", W.frame:IsShown())
GT:ToggleItemList()
check("Toggle Item List binding collapses", not W.list:IsShown())
GT:ToggleItemList()
check("Toggle Item List binding expands", W.list:IsShown())
registeredOptions["GatheringTracker"].args.Display.args.windowScale.set(nil, 1.5)
eq("scale option applied", W.frame:GetScale(), 1.5)
registeredOptions["GatheringTracker"].args.Display.args.resetPosition.func()
eq("reset position", general.xPos, GT.defaults.profile.General.xPos)

---------------------------------------------------------------------------
group("Every option runs")
local optionErrors = {}
local function walk(node, path)
   if type(node) ~= "table" then return end
   if node.get and node.type ~= "group" then
      local ok, err = pcall(node.get, {})
      if not ok then table.insert(optionErrors, path .. ".get: " .. tostring(err)) end
   end
   if type(node.values) == "function" then
      local ok, err = pcall(node.values)
      if not ok then table.insert(optionErrors, path .. ".values: " .. tostring(err)) end
   end
   for _, key in ipairs({ "disabled", "hidden" }) do
      if type(node[key]) == "function" then
         local ok, err = pcall(node[key])
         if not ok then table.insert(optionErrors, path .. "." .. key .. ": " .. tostring(err)) end
      end
   end
   if node.set and path:match("%.enable$") == nil and node.type ~= "group" then
      local current = node.get and select(2, pcall(node.get, {}))
      local ok, err
      if node.type == "toggle" then
         ok, err = pcall(node.set, {}, not current)
         if ok then ok, err = pcall(node.set, {}, current) end
      elseif node.type == "range" then
         ok, err = pcall(node.set, {}, node.min)
         if ok then ok, err = pcall(node.set, {}, current or node.min) end
      elseif node.type == "select" then
         ok, err = pcall(node.set, {}, current)
      end
      if ok == false then table.insert(optionErrors, path .. ".set: " .. tostring(err)) end
   end
   if node.type == "execute" and node.func then
      local ok, err = pcall(node.func)
      if not ok then table.insert(optionErrors, path .. ".func: " .. tostring(err)) end
   end
   if node.args then
      for key, child in pairs(node.args) do
         if key ~= "Alerts" then walk(child, path .. "." .. key) end
      end
   end
end
walk(registeredOptions["GatheringTracker"], "options")
check("all General/Display/Debug options get and set without errors", #optionErrors == 0, table.concat(optionErrors, "\n      "))

local enable = registeredOptions["GatheringTracker"].args.General.args.enable
enable.set(nil, false)
check("disabling the addon hides the window", not W.frame:IsShown())
enable.set(nil, true)
check("enabling the addon shows the window", W.frame:IsShown())

---------------------------------------------------------------------------
group("Minimap / broker launcher")
local ldb = LibStub("LibDataBroker-1.1"):GetDataObjectByName("GatheringTracker")
M.shift = true
ldb.OnClick(W.frame, "LeftButton")
M.shift = false
eq("shift-click resets the session", #visibleRowIDs(), 0)
local before = #M.menus
ldb.OnClick(W.frame, "LeftButton")
eq("click opens the filter menu", #M.menus, before + 1)

---------------------------------------------------------------------------
print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
