--[[
local crt=require("crt")
local co1,co2
co1=crt.create(function()
	print("running 1",coroutine.running())
	co2=crt.create(function()
		print("running 2",coroutine.running())
	end)
end)
print("create example:",co1,co2,crt.pool_size())

local co3,co4
co3=crt.create_ex(false,false,function()
	print("running 3",coroutine.running())
	co4=crt.create_ex(false,false,function()
		print("running 4",coroutine.running())
	end)
end)
print("create_ex example:",co3,co4,crt.pool_size())
crt.resume(co3)
print("create_ex example:",co3,co4,crt.pool_size())

crt.resume(co4)
print("create_ex example:",co3,co4,crt.pool_size())

local co_A,co_B
local function _check_fruit(str)
	return coroutine.yield(str)
end
local function task_A(str)
	print("begin task A",str)
    local ret=_check_fruit("red "..str)
    print("end task A",ret)
	return ret
end
local function task_B(str)
	print("begin task B",str)
    local ret=_check_fruit("yello "..str)
    print("end task B",ret)
	return ret
end
co_A,arg_A=crt.create_ex(true,true,task_A,"apple")
co_B,arg_B=crt.create_ex(true,true,task_B,"banana")
print("thread count:",crt.size(),"thread pool count:",crt.pool_size())
for i=1,10 do
	print("main_loop",i)
	if(i==3) then
		crt.resume(co_B,arg_B.." is good")
	elseif(i==8) then
		crt.resume(co_A,arg_A.." is bad")
	end
end
print("thread count:",crt.size(),"thread pool count:",crt.pool_size())
]]--
local crt={
	_co_pool={},
	_colist={},
	_call_fn=nil,
	_count=0,
	running=coroutine.running,
	status=coroutine.status,
	wrap=coroutine.wrap,
	yield=coroutine.yield,
}
local _lua_coroutine=coroutine
local _insert=table.insert
local _remove=table.remove
local _unpack=table.unpack
local _error=error
local function _call(co,...)
	local f=crt._colist[co] and crt._colist[co][1]
	if(f) then 
		if(crt._call_fn) then
			crt._call_fn(f,...)
		else
			f(...)
		end 
	end
end
local function _threadfunction()
	local co=_lua_coroutine.running()
	while(true) do
		_call(co,_lua_coroutine.yield())
		_insert(crt._co_pool,co)
		crt._colist[co]=nil
		crt._count=crt._count-1
	end
end
local function _get_free_coroutine(f,use_current)
	local co=crt._co_pool[1]
	if(co==nil) then
		co=_lua_coroutine.create(_threadfunction)
		_lua_coroutine.resume(co)
	else
		_remove(crt._co_pool,1)
	end
	crt._colist[co]={f,use_current}
	crt._count=crt._count+1
	return co
end
function crt.pool_size()
	return #crt._co_pool
end
function crt.size()
	return crt._count
end
function crt.create_ex(use_current,resume_now,f,...)
	if(type(f)~="function") then _error("Function argument type wrong",2) end
	local co=_lua_coroutine.running()
	if(use_current and crt._colist[co] and crt._colist[co][2]) then
		return co,f(...)
	else
		co=_get_free_coroutine(f,use_current)
		if(resume_now) then
			local ret={_lua_coroutine.resume(co,...)}
			if(not ret[1]) then
				_error(ret[2],2)
			else
				return co,_unpack(ret,2)
			end
		else
			return co
		end
	end
end

function crt.create(f,...)
	return crt.create_ex(true,true,f,...)
end

function crt.resume(thread,...)
	if(thread) then
		local ret={_lua_coroutine.resume(thread,...)}
		if(not ret[1]) then
			_error(ret[2],2)
		else
			return _unpack(ret,2)
		end
	end
end

--example: crt.set_call_method(pcall)
function crt.set_call_method(fn)
	crt._call_fn=fn
end

return crt
