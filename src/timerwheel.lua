---时间轮实现，改造自：https://github.com/Tieske/timerwheel.lua
---没用pair保证反复执行逻辑是一致的，但是没法保证最小时间段内的所有定时器是按顺序执行的
---比如最小时间段是6毫秒，那么同一时刻你分别创建定时5毫秒和定时4毫秒，是不知道谁先回调的

local xpcall = xpcall
local default_err_handler = function(err)
  print(debug.traceback("TimerWheel callback failed with: " .. tostring(err)))
end

local EMPTY = {}

local _M = {}


---创建时间轮定时器
-- The options are:
---@param precision number @最小时间段，单位毫秒,数值越大误差越大，1最精确，但是效率会低，一般逻辑可以6，渲染可以11
---@param ringsize number  @每轮时间槽数量，1轮能表示ringsize*precision毫秒，
---最好2轮就能涵盖所有定时时长，建议ringsize=最长定时时间/precision/最大轮数，最大轮数不要超过30，例如最长30分钟,ringsize=30*60*1000/6/30=10000
---@param start number @开始时间，一般0
---@param start1970 number @开始时间戳，一般0，服务器定时器可能用到
---@return the timerwheel object
function _M.New(precision, ringsize, start, start1970)
  assert(math.type(precision) == "integer" and precision > 0, "expected 'precision' to be an integer number > 0")
  assert(math.type(ringsize) == "integer" and ringsize > 0, "expected 'ringsize' to be an integer number > 0")
  local now = start    --当前时间
  local sumtime = 0    --定时器累计时间
  local position  = 1  -- position next up in first ring of timer wheel
  local id_count  = 0  -- counter to generate unique ids (all negative)
  local id_list   = {} -- reverse lookup table to find timers by id
  local rings     = {} -- list of rings, index 1 is the current ring
  local rings_n   = 0  -- the number of the last ring in the rings list
  local count     = 0  -- how many timers do we have
  ---@class wheel
  local wheel     = {} -- the returned wheel object

  -- because we assume hefty setting and cancelling, we're reusing tables
  -- to prevent excessive GC.
  local tables    = {} -- list of tables to be reused
  local tables_n  = 0  -- number of tables in the list

  --- Checks and executes timers.
  -- Call this function (at least) every `precision` seconds.
  -- @return `true`
  function wheel:Update(deltaTime)
    sumtime = sumtime + deltaTime
    local toptime = now + deltaTime
    local ring = rings[1] or EMPTY

    while now < toptime do
      now = now + precision
      -- get the expired slot, and remove it from the ring
      local slot = ring[position]
      ring[position] = nil

      -- forward pointers
      position = position + 1
      if position > ringsize then
        -- current ring is done, remove it and forward pointers
        for i = 1, rings_n do
          -- manual loop, since table.remove won't deal with holes
          rings[i] = rings[i + 1]
        end
        rings_n = rings_n - 1

        ring = rings[1] or EMPTY
        start = start + ringsize * precision
        position = 1
      end

      -- only deal with slot after forwarding pointers, to make sure that
      -- any cb inserting another timer, does not end up in the slot being
      -- handled
      if slot then
        -- deal with the slot
        local ids = slot.ids
        local args = slot.arg
        for i = 1, slot.n do
          local id  = slot[i]
          if id then
            slot[i]  = nil; slot[id] = nil
            local cb  = ids[id];  ids[id]  = nil
            local arg = args[id]; args[id] = nil
            id_list[id] = nil
            count = count - 1
            xpcall(cb, default_err_handler, arg)
          end
        end

        slot.n = 0
        -- delete the slot
        tables_n = tables_n + 1
        tables[tables_n] = slot
      end

    end
    return true
  end

  ---获得定时器数量
  function wheel:Count()
    return count
  end

  ---获得当前时间
  function wheel:Time()
    return now
  end

  ---获得当前时间戳，用于本地模拟服务器时间戳
  function wheel:Time1970()
    return sumtime + start1970
  end

  ---设置定时器
  ---@param expire_in number @整数，单位毫秒
  ---@param cb  function(arg) @回调函数
  ---@param arg any @回调函数的参数，没有不用填
  ---@return number @返回定时器ID，取消定时器时用到wheel:cancel(id)
  function wheel:SetTime(expire_in, cb, arg)
    local time_expire = now + expire_in
    local pos = ((time_expire - start) // precision) + 1
    if pos < position then
      -- we cannot set it in the past
      pos = position
    end
    local ring_idx = ((pos - 1) // ringsize) + 1
    local slot_idx = pos - (ring_idx - 1) * ringsize

    -- fetch actual ring table
    local ring = rings[ring_idx]
    if not ring then
      ring = {}
      rings[ring_idx] = ring
      if ring_idx > rings_n then
        rings_n = ring_idx

      end
    end

    -- fetch actual slot
    local slot = ring[slot_idx]
    if not slot then
      if tables_n == 0 then
        slot = { n = 0, ids = {}, arg = {} }
      else
        slot = tables[tables_n]
        tables_n = tables_n - 1
      end
      ring[slot_idx] = slot
    end

    -- get new id
    local id = id_count - 1 -- use negative idx to not interfere with array part
    id_count = id

    -- store timer
    -- if we do not do this check, it will go unnoticed and lead to very
    -- hard to find bugs (`count` will go out of sync)
    slot.ids[id] = cb or error("the callback parameter is required", 2)
    slot.arg[id] = arg
    local idx = slot.n + 1
    slot.n = idx
    slot[idx] = id
    slot[id] = idx
    id_list[id] = slot
    count = count + 1

    return id
  end

  ---取消定时器
  ---@param id number @the timer id to cancel
  ---@return boolean @`true` if cancelled, `false` if not found
  function wheel:Cancel(id)
    local slot = id_list[id]
    if slot then
      local idx = slot[id]
      slot[id] = nil
      slot.ids[id] = nil
      slot.arg[id] = nil
      local n = slot.n
      slot[idx] = slot[n]
      slot[n] = nil
      slot.n = n - 1
      id_list[id] = nil
      count = count - 1
      return true
    end
    return false
  end

  return wheel
end

return _M
