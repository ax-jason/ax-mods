--[[
--example:
local mpa=require("mpa")
local my_mpa=mpa.new()
my_mpa.a="a"
my_mpa.c="c"
my_mpa.b="b"
my_mpa.f="f"
my_mpa.d="d"
my_mpa.e="e"
for k,v in mpa.pairs(my_mpa,true) do
	for _k,_v in mpa.pairs(my_mpa) do
		
	end
	print(k,v)
	if(k=="c") then my_mpa.b=nil end
end
print("=======After modification, using system pairs method=======")
--System pairs will use auto flush setting for the table.
for k,v in pairs(my_mpa) do
	print(k,v)
end
--manually flush the table.
my_mpa.c=nil
mpa.flush(my_mpa)

print("=======next example=======")
my_mpa.e=nil
local k,v = mpa.next(my_mpa,nil,true)--flush the table on the first next call
while(k) do
	print(k,v)
	k,v=mpa.next(my_mpa,k)
end]]--
local _mpa={}
local _getmetatable=getmetatable
local _setmetatable=setmetatable
local _insert=table.insert
local _remove=table.remove
local _lua_ipairs=ipairs
local _lua_pairs=pairs

local function _trim(meta)
	while(meta.arrary_count>0 and meta.arrary[meta.arrary_count][2]==nil) do
		indices[meta.arrary[meta.arrary_count][1]]=nil
		_remove(meta.arrary)
		meta.arrary_count=meta.arrary_count-1
	end
end
local function _flush(meta)
  if(not meta._need_flush) then return end
  meta._need_flush=nil
  for _,i in _lua_ipairs(meta.flush_indice) do
  	if(meta.arrary[i] and meta.arrary[i][2]==nil) then
  		local last=meta.arrary[meta.arrary_count]
  		meta.arrary[i]=last
  		_remove(meta.arrary)
  		meta.arrary_count=meta.arrary_count-1
  		meta.indices[last[1]]=i
  	end
  	_trim(meta)
  end
end

local function _it(tbl,i)
	i=i+1
	local v=tbl[i]
	while(v and not v[2]) do
		i=i+1
		v=tbl[i]
	end
	if(v) then return i,v[2],v[1] end
end
local function _ipairs(tbl)
	local meta=_getmetatable(tbl)
	if(meta.auto_flush) then _flush(meta) end
	return _it,meta.arrary,0
end
local function _next(meta,key)
	local i=(key and meta.indices[key] or 0)+1
	local v=meta.arrary[i]
	while(v and not v[2]) do
		i=i+1
		v=meta.arrary[i]
	end
	if(v) then return v[1],v[2] end
end
local function _pairs(tbl)
	local meta=_getmetatable(tbl)
	if(meta.auto_flush) then _flush(meta) end
	return _next,meta,nil
end
local function _len(tbl)
	return _getmetatable(tbl).count
end

local function _newindex(tbl, key, value)
	local meta=_getmetatable(tbl)
	local indices=meta.indices
	local i=indices[key]
	if(i) then
		if(value~=nil) then
			meta.arrary[i][2]=value
		else
			indices[key]=nil
			if(i==meta.arrary_count) then
				_remove(meta.arrary)
				meta.arrary_count=meta.arrary_count-1
				_trim(meta)
			else
				_insert(meta.flush_indice,i)
				meta._need_flush=true
				if(meta.arrary[i]) then meta.arrary[i][2]=nil end
			end
			meta.count=meta.count-1
		end
	elseif(value~=nil) then
		_insert(meta.arrary,{key,value})
		meta.count=meta.count+1
		meta.arrary_count=meta.arrary_count+1
		indices[key]=meta.arrary_count
	end
end
local function _index(tbl,key)
	local meta=_getmetatable(tbl)
	local i=meta.indices[key]
	return i and meta.arrary[i][2]
end

--Using auto flush as default is recommanded, or you can manually flush your mpa after a complete traversing. Flushing during a traversing may miss key/value.
function _mpa.new(disable_auto_flush)
	local ret={}
	_setmetatable(ret,{auto_flush=not disable_auto_flush,__len=_len,__pairs=_pairs,__ipairs=_ipairs,__newindex=_newindex,__index=_index,indices={},arrary={},flush_indice={},arrary_count=0,count=0}) 
	return ret
end

function _mpa.set_auto_flush(tbl,value)
	local meta=_getmetatable(tbl)
	meta.auto_flush=value
end

function _mpa.flush(tbl)
  return _flush(_getmetatable(tbl))
end

function _mpa.ipairs(tbl,flush)
	local meta=_getmetatable(tbl)
	if(not meta or meta.__newindex~=_index) then return _lua_ipairs(tbl) end
	if(flush) then _flush(meta) end
	return _it,meta.arrary,0
end

function _mpa.pairs(tbl,flush)
	local meta=_getmetatable(tbl)
	if(not meta or meta.__newindex~=_index) then return _lua_pairs(tbl) end
	if(flush) then _flush(meta) end
	return _next,meta,nil
end
function _mpa.next(tbl,key,flush)
	local meta=_getmetatable(tbl)
	if(not meta or meta.__newindex~=_index) then return _lua_pairs(tbl) end
	if(key==nil and flush) then _flush(meta) end
	return _next(meta,key)
end

return _mpa
