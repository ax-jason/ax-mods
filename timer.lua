--[[
local timer=require("timer")
local function test_timer(timer,...)
  print(os.time(),...)
end
timer.new_timer(1,1,test_timer,"my timer A")
timer.new_timer(2,1,test_timer,"my timer B")
timer.new_timer(4,1,test_timer,"my timer D")
timer.new_timer(3,1,test_timer,"my timer C")
timer.new_timer(1,timer.infinite,test_timer,"my timer loop")
local lt=os.time()
while(timer.ct<5) do
  local ct=os.time()
  timer.process(ct-lt)
  lt=ct
end
]]--
local t={
  use_system_time=false,
  ct=0,
  infinite=-1,
}
t.timers={}
t.count=0
local function _get_ct()
  return t.use_system_time and os.time() or t.ct
end

local function add_timer(timer,loop_offset)
  if(type(timer.loop_times)~="number") then 
    timer.loop_times=0 
  elseif(loop_offset and timer.loop_times>=0) then
    timer.loop_times=math.max(timer.loop_times+loop_offset,0)
  end
  if(t.count==0) then
    t.count=t.count+1
    table.insert(t.timers,timer)  
    return timer
  else
    t.count=t.count+1
    for i,v in ipairs(t.timers) do
      if(timer.tt>v.tt) then
          table.insert(t.timers,i,timer)
        return timer
      end
    end
    table.insert(t.timers,timer)   
    return timer
  end  
end


function t.new_timer(t_seconds,loop_times,func,...)
  if(type(t_seconds)=="table") then
    t_seconds.tt=_get_ct()+t_seconds.period
    return add_timer(t_seconds,-1)
  else
    return add_timer({tt=_get_ct()+t_seconds,period=t_seconds,loop_times=loop_times,func=func,arg={...}},-1)
  end
end

function t.remove_timer(timer)
  for i,v in ipairs(t.timers) do
    if(timer==v) then
      table.remove(t.timers,i)
      t.count=t.count-1
      return timer
    end
  end
end

function t.process(tm)
  if(tm) then
    t.ct=t.ct+tm
  end
  if(not next(t.timers)) then return end
  local ct=_get_ct()
  if(ct<t.timers[t.count].tt) then return end
  local tl={}
  local nt
  for index=t.count,1,-1 do
    nt=t.timers[index]
    if(ct<nt.tt) then break end
    if(nt.func) then
      local temp=nt.func(nt,table.unpack(nt.arg))
      if(nt.loop_times~=0 and temp~=false) then 
        if(t.continue) then
          nt.tt=nt.tt+nt.period
        else
          nt.tt=ct+nt.period
        end      
        table.insert(tl,nt)
        if(nt.loop_times>0) then 
          nt.loop_times=nt.loop_times-1 
          if(nt.loop_times<0) then nt.loop_times=0 end
        end        
      end
    end
    table.remove(t.timers)
    t.count=t.count-1
  end
  
  for i,v in ipairs(tl) do
    add_timer(v)
  end 
end

return t
