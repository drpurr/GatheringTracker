-- Minimal World of Warcraft client API mock, enough to load GatheringTracker outside the game
-- and drive its UI. Calling a widget method that is not implemented here raises an error, so a
-- misspelled or unsupported API call fails the tests instead of passing silently.

local M = {}

M.now = 1000          -- GetTime()
M.epoch = 1700000000  -- time()
M.money = 0           -- GetMoney() in copper
M.bags = {}           -- itemID -> count
M.items = {}          -- itemID -> { name, quality, icon }
M.prices = {}         -- itemID -> copper (TradeSkillMaster price)
M.timers = {}
M.eventFrames = {}
M.chat = {}
M.menus = {}
M.inInstance = false
M.inGroup = false
M.loggedIn = false
M.allFrames = {}

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------
local Widget = {}
local WidgetMethods = {}

-- Missing methods resolve to nil, so calling an API the mock does not implement raises an error
local widgetMeta = { __index = WidgetMethods }

local function newWidget(widgetType, name, parent)
   local w = setmetatable({
      _type = widgetType,
      _name = name,
      _parent = parent,
      _shown = true,
      _points = {},
      _scripts = {},
      _hooks = {},
      _width = 0,
      _height = 0,
      _scale = 1,
      _alpha = 1,
      _events = {},
      _children = {},
      _mouse = false,
   }, widgetMeta)
   if parent and parent._children then
      table.insert(parent._children, w)
   end
   table.insert(M.allFrames, w)
   return w
end
M.newWidget = newWidget

local noop = function() end
for _, name in ipairs({
   "SetFrameStrata", "SetFrameLevel", "SetClampedToScreen", "SetJustifyH", "SetJustifyV",
   "SetWordWrap", "SetDrawLayer", "SetIgnoreParentAlpha", "RegisterForClicks", "RegisterForDrag",
   "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor", "SetHighlightFontObject",
   "SetNormalTexture", "SetHighlightTexture", "SetPushedTexture", "SetMouseClickEnabled",
   "SetMouseMotionEnabled", "AddLine", "SetHyperlink", "SetToplevel", "SetResizable", "SetTexCoord",
   "SetDesaturated", "SetBlendMode", "SetNonSpaceWrap", "SetMaxLines", "SetSpacing", "SetShadowOffset",
   "SetShadowColor", "SetDontSavePosition", "SetUserPlaced",
}) do
   WidgetMethods[name] = noop
end

function WidgetMethods:GetName() return self._name end
function WidgetMethods:GetParent() return self._parent end
function WidgetMethods:SetParent(p) self._parent = p end
function WidgetMethods:GetObjectType() return self._type end
function WidgetMethods:Show() self._shown = true end
function WidgetMethods:Hide()
   local wasShown = self._shown
   self._shown = false
   if wasShown and self._scripts.OnHide then self._scripts.OnHide(self) end
end
function WidgetMethods:SetShown(shown) if shown then self:Show() else self:Hide() end end
function WidgetMethods:IsShown() return self._shown end
function WidgetMethods:IsVisible()
   local w = self
   while w do
      if not w._shown then return false end
      w = w._parent
   end
   return true
end
function WidgetMethods:SetPoint(point, relativeTo, relativePoint, x, y)
   if type(relativeTo) == "number" then
      relativeTo, relativePoint, x, y = nil, point, relativeTo, relativePoint
   end
   table.insert(self._points, { point, relativeTo or self._parent, relativePoint or point, x or 0, y or 0 })
end
function WidgetMethods:ClearAllPoints() self._points = {} end
function WidgetMethods:GetPoint(i)
   local p = self._points[i or 1]
   if p then return p[1], p[2], p[3], p[4], p[5] end
end
function WidgetMethods:GetNumPoints() return #self._points end
function WidgetMethods:SetAllPoints(target) self._points = { { "ALL", target or self._parent } } end
function WidgetMethods:SetSize(w, h) self._width, self._height = w, h end
function WidgetMethods:SetWidth(w) self._width = w end
function WidgetMethods:SetHeight(h) self._height = h end
function WidgetMethods:GetWidth() return self._width end
function WidgetMethods:GetHeight() return self._height end
function WidgetMethods:GetSize() return self._width, self._height end
function WidgetMethods:SetScale(s) self._scale = s end
function WidgetMethods:GetScale() return self._scale end
function WidgetMethods:SetAlpha(a) self._alpha = a end
function WidgetMethods:GetAlpha() return self._alpha end
function WidgetMethods:SetScript(name, fn) self._scripts[name] = fn end
function WidgetMethods:GetScript(name) return self._scripts[name] end
function WidgetMethods:HookScript(name, fn)
   local old = self._scripts[name]
   self._scripts[name] = function(...)
      if old then old(...) end
      fn(...)
   end
end
function WidgetMethods:EnableMouse(e) self._mouse = e and true or false end
function WidgetMethods:IsMouseEnabled() return self._mouse end
function WidgetMethods:SetMovable(m) self._movable = m end
function WidgetMethods:IsMovable() return self._movable end
function WidgetMethods:StartMoving()
   assert(self._movable, "StartMoving on a frame that is not movable")
   self._moving = true
end
function WidgetMethods:StopMovingOrSizing()
   self._moving = false
   -- the client re-anchors a moved frame to its new location
   local target = M.dragTarget or { x = 0, y = 0 }
   self._points = { { "TOPLEFT", M.UIParent, "BOTTOMLEFT", target.x, target.y } }
end
function WidgetMethods:RegisterEvent(event) self._events[event] = true; M.eventFrames[self] = true end
function WidgetMethods:UnregisterEvent(event) self._events[event] = nil end
function WidgetMethods:UnregisterAllEvents() self._events = {} end
function WidgetMethods:IsEventRegistered(event) return self._events[event] or false end
function WidgetMethods:CreateTexture(name, layer)
   local t = newWidget("Texture", name, self)
   t._layer = layer
   return t
end
function WidgetMethods:CreateFontString(name, layer, template)
   local fs = newWidget("FontString", name, self)
   fs._fontObject = template
   fs._layer = layer
   return fs
end
function WidgetMethods:CreateAnimationGroup()
   local g = newWidget("AnimationGroup", nil, self)
   return g
end
function WidgetMethods:CreateAnimation()
   return newWidget("Animation", nil, self)
end
-- Animation stubs used by the alert screen flash
for _, name in ipairs({ "SetFromAlpha", "SetToAlpha", "SetDuration", "SetOrder", "SetLooping", "Play", "Stop",
   "SetStartDelay", "SetSmoothing" }) do
   WidgetMethods[name] = noop
end
-- Textures
function WidgetMethods:SetTexture(t) self._texture = t end
function WidgetMethods:GetTexture() return self._texture end
function WidgetMethods:SetColorTexture(r, g, b, a) self._color = { r, g, b, a } end
function WidgetMethods:SetAtlas(a) self._atlas = a end
function WidgetMethods:GetAtlas() return self._atlas end
function WidgetMethods:SetVertexColor(r, g, b, a) self._vertex = { r, g, b, a } end
function WidgetMethods:GetVertexColor() local v = self._vertex or { 1, 1, 1, 1 }; return v[1], v[2], v[3], v[4] end
-- Font strings
function WidgetMethods:SetText(text)
   if self._type == "Button" then
      self._fontString = self._fontString or newWidget("FontString", nil, self)
      self._fontString._text = text
      return
   end
   self._text = text
end
function WidgetMethods:GetText()
   if self._type == "Button" then
      return self._fontString and self._fontString._text
   end
   return self._text
end
function WidgetMethods:SetFormattedText(fmt, ...) self:SetText(fmt:format(...)) end
function WidgetMethods:SetTextColor(r, g, b, a) self._textColor = { r, g, b, a } end
function WidgetMethods:GetTextColor() local c = self._textColor or { 1, 1, 1, 1 }; return c[1], c[2], c[3], c[4] end
function WidgetMethods:SetFontObject(f) self._fontObject = f end
function WidgetMethods:SetFont(path, size, flags) self._hardcodedFont = path end
function WidgetMethods:GetFontObject() return self._fontObject end
function WidgetMethods:GetStringWidth() return #(self._text or "") * 7 end
function WidgetMethods:GetUnboundedStringWidth() return #(self._text or "") * 7 end
-- Buttons
function WidgetMethods:SetNormalFontObject(f) self._normalFont = f end
function WidgetMethods:GetFontString() return self._fontString end
function WidgetMethods:Click(button)
   button = button or "LeftButton"
   if self._scripts.OnClick then self._scripts.OnClick(self, button, false) end
end
-- Tooltip
function WidgetMethods:SetOwner(owner) self._owner = owner; self._lines = {}; self._shown = true end
function WidgetMethods:GetOwner() return self._owner end
function WidgetMethods:SetItemByID(id) self._item = id end
function WidgetMethods:SetCurrencyByID(id) self._currency = id end
function WidgetMethods:ClearLines() self._lines = {} end

---Runs a script handler on a widget, as the client would
function M.fire(widget, script, ...)
   local fn = widget._scripts[script]
   assert(fn, ("no %s script on %s"):format(script, widget._type))
   return fn(widget, ...)
end

---------------------------------------------------------------------------
-- Globals
---------------------------------------------------------------------------
function M.install()
   local G = _G

   M.UIParent = newWidget("Frame", "UIParent")
   M.UIParent._width, M.UIParent._height = 1920, 1080
   G.UIParent = M.UIParent
   G.WorldFrame = newWidget("Frame", "WorldFrame")
   G.GameTooltip = newWidget("GameTooltip", "GameTooltip", M.UIParent)
   G.GameTooltip._shown = false
   G.GameTooltip.AddLine = function(self, text) table.insert(self._lines, text) end
   G.ChatFrame1 = newWidget("Frame", "ChatFrame1", M.UIParent)
   G.ChatFrame1.AddMessage = function(_, msg) table.insert(M.chat, msg) end
   G.DEFAULT_CHAT_FRAME = G.ChatFrame1
   G.RaidWarningFrame = newWidget("Frame", "RaidWarningFrame")

   G.CreateFrame = function(frameType, name, parent, template)
      local f = newWidget(frameType, name, parent)
      f._template = template
      if name then G[name] = f end
      return f
   end
   G.BackdropTemplateMixin = {}

   G.GetTime = function() return M.now end
   G.time = function() return M.epoch + math.floor(M.now) end
   G.date = os.date
   G.GetMoney = function() return M.money end
   G.debugstack = function() return "stack" end
   G.geterrorhandler = function() return function(err) error(err, 2) end end
   G.seterrorhandler = noop
   G.securecallfunction = function(fn, ...) return fn(...) end
   G.securecall = function(fn, ...) return fn(...) end
   G.issecurevariable = function() return false end
   G.hooksecurefunc = function(t, name, fn)
      if type(t) == "string" then t, name, fn = G, t, name end
      local old = t[name]
      t[name] = function(...) local r = { old(...) }; fn(...); return unpack(r) end
   end
   G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
   G.tinsert = table.insert
   G.tremove = table.remove
   G.unpack = unpack
   G.strjoin = function(sep, ...) return table.concat({ ... }, sep) end
   G.strsplit = function(sep, str, limit)
      local out, pattern, start = {}, "([^" .. sep .. "]*)", 1
      for piece in (str .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = piece end
      return unpack(out)
   end
   G.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
   G.strmatch = string.match
   G.strfind = string.find
   G.format = string.format
   G.floor = math.floor
   G.max = math.max
   G.min = math.min
   G.Round = function(v) return math.floor(v + 0.5) end
   G.tostringall = function(...)
      local out = {}
      for i = 1, select("#", ...) do out[i] = tostring((select(i, ...))) end
      return unpack(out)
   end
   G.IsLoggedIn = function() return M.loggedIn end
   G.InCombatLockdown = function() return false end
   G.IsShiftKeyDown = function() return M.shift or false end
   G.GetScreenWidth = function() return 1920 end
   G.GetScreenHeight = function() return 1080 end
   G.UnitName = function() return "Tester" end
   G.UnitNameUnmodified = function() return "Tester" end
   G.UnitClass = function() return "Druid", "DRUID", 11 end
   G.UnitRace = function() return "Night Elf", "NightElf", 4 end
   G.UnitFactionGroup = function() return "Alliance", "Alliance" end
   G.GetRealmName = function() return "TestRealm" end
   G.GetNormalizedRealmName = function() return "TestRealm" end
   G.GetCurrentRegion = function() return 1 end
   G.GetLocale = function() return "enUS" end
   G.IsInInstance = function() return M.inInstance end
   G.IsInGroup = function() return M.inGroup end
   G.IsInRaid = function() return false end
   G.GetInstanceInfo = function() return "World", "none", 0 end
   G.PlaySound = noop
   G.PlaySoundFile = noop
   G.RaidNotice_AddMessage = function(_, msg) M.raidWarning = msg end
   G.ChatTypeInfo = { RAID_WARNING = {} }
   G.SOUNDKIT = { RAID_WARNING = 1 }
   G.GOLD_AMOUNT_SYMBOL = "g"
   G.SlashCmdList = {}
   G.BACKPACK_CONTAINER = 0
   G.NUM_BAG_SLOTS = 4

   -- Running WoW Forever
   G.WOW_PROJECT_MAINLINE = 1
   G.WOW_PROJECT_CLASSIC = 2
   G.WOW_PROJECT_CAMELOT = 18
   G.WOW_PROJECT_ID = 18

   G.C_Timer = {
      After = function(delay, fn) table.insert(M.timers, { at = M.now + delay, fn = fn }) end,
      NewTicker = function(interval, fn)
         local ticker = { interval = interval, fn = fn, cancelled = false }
         function ticker:Cancel() self.cancelled = true end
         table.insert(M.timers, { at = M.now + interval, fn = fn, ticker = ticker })
         return ticker
      end,
   }

   G.C_AddOns = {
      GetAddOnMetadata = function(_, field)
         return ({ Title = "GatheringTracker", Version = "test", Notes = "" })[field]
      end,
      IsAddOnLoaded = function(name) return name == "TradeSkillMaster" end,
   }
   G.TSM_API = {
      GetCustomPriceValue = function(_, itemString)
         local id = tonumber(itemString:match("i:(%d+)"))
         return M.prices[id]
      end,
   }

   local qualityColors = {
      [0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 }, [3] = { 0, 0.44, 0.87 },
   }
   G.C_Item = {
      GetItemCount = function(id) return M.bags[id] or 0 end,
      GetItemNameByID = function(id) return M.items[id] and M.items[id].name end,
      GetItemInfo = function(id) return M.items[id] and M.items[id].name end,
      GetItemIconByID = function(id) return M.items[id] and M.items[id].icon or 134400 end,
      GetItemQualityByID = function(id) return M.items[id] and M.items[id].quality end,
      GetItemQualityColor = function(q)
         local c = qualityColors[q] or qualityColors[1]
         return c[1], c[2], c[3], "ffffffff"
      end,
   }
   G.C_CurrencyInfo = {
      GetCurrencyInfo = function(id) return M.currencies and M.currencies[id] end,
      GetBasicCurrencyInfo = function(id) return M.currencies and M.currencies[id] end,
      GetCurrencyLink = function(id) return "currency:" .. id end,
   }
   G.C_Container = {
      GetContainerNumSlots = function() return 0 end,
      GetContainerItemInfo = function() return nil end,
      GetContainerNumFreeSlots = function() return 10 end,
   }
   G.C_Seasons = { GetActiveSeason = function() return 0 end }
   G.Settings = { OpenToCategory = function(id) M.openedSettings = id end }
   G.MenuUtil = {
      CreateContextMenu = function(owner, generator)
         local menu = { owner = owner, generator = generator }
         function menu:Close() self.closed = true end
         table.insert(M.menus, menu)
         return menu
      end,
   }
end

---------------------------------------------------------------------------
-- Events and time
---------------------------------------------------------------------------
function M.fireEvent(event, ...)
   for frame in pairs(M.eventFrames) do
      if frame._events[event] and frame._scripts.OnEvent then
         frame._scripts.OnEvent(frame, event, ...)
      end
   end
end

---Moves the clock forward, running C_Timer callbacks that come due
function M.advance(seconds)
   local target = M.now + seconds
   while true do
      table.sort(M.timers, function(a, b) return a.at < b.at end)
      local nextTimer = M.timers[1]
      if not nextTimer or nextTimer.at > target then
         break
      end
      table.remove(M.timers, 1)
      M.now = nextTimer.at
      if nextTimer.ticker then
         if not nextTimer.ticker.cancelled then
            nextTimer.fn(nextTimer.ticker)
            table.insert(M.timers, { at = M.now + nextTimer.ticker.interval, fn = nextTimer.fn, ticker = nextTimer.ticker })
         end
      else
         nextTimer.fn()
      end
   end
   M.now = target
end

return M
