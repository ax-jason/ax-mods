local t = {}
-- example
--[[
local function r(v, b)
	if(v>=10000) then
		print(555, v, b)
		return 
	else
		t.recursion_call(r, v+1, v+2)
	end
end
t.recursion(function()
	r(1,1)
end)
]]
local function process(co, ret, call, ...)
	while(ret and call) do
		return process(co, coroutine.resume(co, call, ...))
	end
end
function t.recursion(fn)
	local co = coroutine.create(fn)
	process(co, coroutine.resume(co))
end
local function _call(call, ...)
	return call(...)
end
function t.recursion_call(fn, ...)
	return _call(coroutine.yield(fn, ...))
end

return t
