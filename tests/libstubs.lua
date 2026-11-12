-- Small stand-ins for the Ace3 libraries the addon embeds, so the tests need nothing outside
-- this repository. They implement only the behaviour GatheringTracker relies on.
local M = ...

-- LibStub
local libs = {}
LibStub = setmetatable({
   NewLibrary = function(_, name, version)
      libs[name] = libs[name] or {}
      return libs[name]
   end,
   GetLibrary = function(_, name, silent)
      if not libs[name] and not silent then error("library " .. name .. " not found", 2) end
      return libs[name]
   end,
}, { __call = function(self, name, silent) return self:GetLibrary(name, silent) end })

local function stubLibrary(name, members)
   local lib = LibStub:NewLibrary(name, 1)
   for k, v in pairs(members) do lib[k] = v end
   return lib
end

-- AceEvent: handlers are a method name (defaulting to the event name) or a function
local eventFrame = M.newWidget("Frame", "AceEventFrame")
local handlers = {}
eventFrame:SetScript("OnEvent", function(_, event, ...)
   for target, handler in pairs(handlers[event] or {}) do
      if type(handler) == "function" then
         handler(event, ...)
      else
         target[handler](target, event, ...)
      end
   end
end)
local AceEvent = {
   RegisterEvent = function(self, event, handler)
      handlers[event] = handlers[event] or {}
      handlers[event][self] = handler or event
      eventFrame:RegisterEvent(event)
   end,
   UnregisterEvent = function(self, event)
      if handlers[event] then handlers[event][self] = nil end
   end,
}
stubLibrary("AceEvent-3.0", AceEvent)

-- AceAddon: OnInitialize on ADDON_LOADED, OnEnable on PLAYER_LOGIN
local addons = {}
local lifecycle = M.newWidget("Frame", "AceAddonFrame")
lifecycle:RegisterEvent("ADDON_LOADED")
lifecycle:RegisterEvent("PLAYER_LOGIN")
lifecycle:SetScript("OnEvent", function(_, event)
   for _, addon in pairs(addons) do
      if event == "ADDON_LOADED" and not addon._initialized then
         addon._initialized = true
         if addon.OnInitialize then addon:OnInitialize() end
      elseif event == "PLAYER_LOGIN" and addon.OnEnable then
         addon:OnEnable()
      end
   end
end)
stubLibrary("AceAddon-3.0", {
   NewAddon = function(_, name, ...)
      local addon = { name = name }
      for k, v in pairs(AceEvent) do addon[k] = v end
      addons[name] = addon
      return addon
   end,
   GetAddon = function(_, name) return addons[name] end,
})

-- AceDB: a profile with defaults filled in, plus profile callbacks
local function applyDefaults(target, defaults)
   for k, v in pairs(defaults) do
      if type(v) == "table" then
         if type(target[k]) ~= "table" then target[k] = {} end
         applyDefaults(target[k], v)
      elseif target[k] == nil then
         target[k] = v
      end
   end
end
stubLibrary("AceDB-3.0", {
   New = function(_, savedVariable, defaults)
      local sv = _G[savedVariable] or { profiles = {} }
      _G[savedVariable] = sv
      sv.profiles = sv.profiles or {}
      sv.profiles.Default = sv.profiles.Default or {}
      local db = { callbacks = {}, current = "Default" }
      db.profile = sv.profiles.Default
      applyDefaults(db.profile, defaults.profile)
      function db.RegisterCallback(_, target, event, method) db.callbacks[event] = { target, method } end
      function db:GetProfiles() return { "Default" } end
      function db:GetCurrentProfile() return self.current end
      function db:SetProfile(name) self.current = name end
      return db
   end,
})

stubLibrary("AceComm-3.0", {})
M.registeredOptions = {}
stubLibrary("AceConfigRegistry-3.0", {
   RegisterOptionsTable = function(_, name, options) M.registeredOptions[name] = options end,
   NotifyChange = function() end,
})
stubLibrary("AceConfigDialog-3.0", {
   AddToBlizOptions = function(_, name) return M.newWidget("Frame", name), name end,
})
stubLibrary("AceDBOptions-3.0", { GetOptionsTable = function() return {} end })
stubLibrary("LibSharedMedia-3.0", {
   LOCALE_BIT_western = 1, LOCALE_BIT_ruRU = 2,
   Register = function() end,
   Fetch = function(_, _, key) return key end,
   HashTable = function() return {} end,
})
stubLibrary("LibDBIcon-1.0", {
   Register = function() end,
   Show = function() M.minimapShown = true end,
   Hide = function() M.minimapShown = false end,
})
local dataObjects = {}
stubLibrary("LibDataBroker-1.1", {
   NewDataObject = function(_, name, object) dataObjects[name] = object; return object end,
   GetDataObjectByName = function(_, name) return dataObjects[name] end,
})
