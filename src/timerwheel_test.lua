
local TimerWheel = require "3rd/timerwheel"

---@type wheel
local wheel
local appTimer

local function test()
  wheel = TimerWheel.New(1, 60000, 0, 0)
  local id
  local id2
  local id3
  local id4
  local count = 0
  local cb = function()
    count = count + 1

  end

  id = wheel:SetTime(5, cb)
  id2 = wheel:SetTime(10, cb)
  id3 = wheel:SetTime(5, cb)
  id4 = wheel:SetTime(5, cb)
  wheel:Cancel(id)
  wheel:SetTime(5, cb)

  for i = 0, 9 do
    local id = wheel:SetTime(i + 5, cb)
  end
end


test()