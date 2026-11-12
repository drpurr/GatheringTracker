---@class GT
local GT = LibStub("AceAddon-3.0"):GetAddon("GatheringTracker")

-- Localize global functions
local floor = math.floor
local GetTime = GetTime

---Session timer.
---Elapsed time is tracked as the time banked from previous running segments plus the
---length of the current segment, so pausing and resuming never drifts.
GT.Timer = {}
GT.Timer.Running = false
GT.Timer.Paused = false
GT.Timer.Started = false
GT.Timer.Banked = 0
GT.Timer.SegmentStart = nil

---Formats a number of seconds as HH:MM:SS (or a shorter form when Short Session Timer is enabled)
---@param seconds number
---@return string
function GT.Timer.CreateTimerText(seconds)
   seconds = floor(seconds or 0)
   local hours = floor(seconds / 3600)
   local minutes = floor((seconds / 60) % 60)
   local secs = floor(seconds % 60)

   if GT.db and GT.db.profile.General.shortTimer then
      if hours > 0 then
         return string.format("%d:%02d:%02d", hours, minutes, secs)
      elseif minutes > 0 then
         return string.format("%d:%02d", minutes, secs)
      end
      return string.format("%ds", secs)
   end
   return string.format("%02d:%02d:%02d", hours, minutes, secs)
end

---@return number seconds the session has been running, excluding paused time
function GT.Timer:Elapsed()
   local elapsed = GT.Timer.Banked
   if GT.Timer.Running and GT.Timer.SegmentStart then
      elapsed = elapsed + (GetTime() - GT.Timer.SegmentStart)
   end
   return elapsed
end

---Starts the timer, or resumes it when paused
function GT.Timer:Start()
   GT.Debug("Timer:Start", 1, GT.Timer.Running, GT.Timer.Paused)
   if GT.Timer.Running then
      return
   end
   GT.Timer.Running = true
   GT.Timer.Paused = false
   GT.Timer.Started = true
   GT.Timer.SegmentStart = GetTime()
end

---Pauses the timer, keeping the elapsed time
function GT.Timer:Pause()
   GT.Debug("Timer:Pause", 1, GT.Timer.Running, GT.Timer.Paused)
   if not GT.Timer.Running then
      return
   end
   GT.Timer.Banked = GT.Timer:Elapsed()
   GT.Timer.Running = false
   GT.Timer.Paused = true
   GT.Timer.SegmentStart = nil
end

---Sets the elapsed time back to zero without changing whether the timer is running or paused
function GT.Timer:Reset()
   GT.Debug("Timer:Reset", 1, GT.Timer.Running, GT.Timer.Paused)
   GT.Timer.Banked = 0
   if GT.Timer.Running then
      GT.Timer.SegmentStart = GetTime()
   end
end

---Stops the timer completely (used when the addon is disabled)
function GT.Timer:Stop()
   GT.Debug("Timer:Stop", 1, GT.Timer.Running, GT.Timer.Paused)
   GT.Timer.Running = false
   GT.Timer.Paused = false
   GT.Timer.Started = false
   GT.Timer.Banked = 0
   GT.Timer.SegmentStart = nil
end
