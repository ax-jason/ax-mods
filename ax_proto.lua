--[[
--examples:
local proto=require("ax_proto")
local d={}
d.bag={
	{"ids","uint32","arrary"}
}
d.mystruct={
	{"name","string"},
	{"friend","mystruct"},
	{"level","uint32"},
	{"words","int32","arrary"},
	{"bag","bag","arrary"},
	{"flags","string","string_map"}

}
d.PhoneNumber={
	{"number","string"},
	{"type","int32"},
}

d.Person={
	{"name","string"},
	{"id","int32"},
	{"email","string"},
	{"phone","PhoneNumber","arrary"},
}
d.AddressBook={
	{"person","Person","arrary"},
}
proto.register(d)
local s={
	name="jason",
	level=1,
	friend={
		name="lilian",
		level=222222221,
		bag={{ids={4,5,6}}},
		friend={name="hello"},
	},
	words={1,2,11},
	flags={a="aaa",b="bbb"}
}
local str=proto.encode("mystruct",s)
local s2=proto.decode("mystruct",str)
if(s2) then
	print(s2.name,s2.level,s2.friend.name,s2.friend.level,s2.words[3],s2.friend.bag[1].ids[2],s2.friend.friend.name,s2.flags.a,s2.flags.b)
end

local ab = {
    person = {
        {
            name = "Alice",
            id = 10000,
            phone = {
                { number = "123456789" , type = 1 },
                { number = "87654321" , type = 2 },
            }
        },
        {
            name = "Bob",
            id = 20000,
            phone = {
                { number = "01234567890" , type = 3 },
            }
        }
    }
}
local str=proto.encode("AddressBook",ab,true)
local data=proto.decode(nil,str)
print(data.person[2].phone[1].number)
]]--

local t={
	endian="<",
	alignment="!1",
	o_default_decl={
		int16="i2",uint16="I2",int32="i4",uint32="I4",int64="i8",uint64="I8",intlua="j",uintlua="J",
		float="n",double="n",
		char="b",uchar="B",byte="b",ubyte="B",number="n",
		string="s4",ztstring="z",
	},
	decl={},
  	meta={},
}
local bpack,bunpack,pairs,ipairs,rawget,tostring,type,error=string.pack,string.unpack,pairs,ipairs,rawget,tostring,type,error

function t.set_endian_alignment(endian_symb,alignment)
	t.endian=endian_symb or "="
	t.alignment="!"..(alignment or "")
	t.default_decl={}
	for k,v in pairs(t.o_default_decl) do
		t.default_decl[k]=t.alignment..t.endian..v
	end
end

t.set_endian_alignment(t.endian,t.alignment)

local function deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deepcopy(orig_key)] = deepcopy(orig_value)
        end
        setmetatable(copy, deepcopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end
local function _add_default_values(tb,de)
  local meta=t.meta[de]
  if(not meta) then
    if(de) then
      for i,v in ipairs(de) do
        if(v[4]) then
          meta=meta or {}
          meta[v[1]]=v[4]
        end
      end
    end
    meta=meta and {__index=meta}
    t.meta[de]=meta
  end
  if(meta) then
    for i,v in pairs(meta.__index) do
      if(type(v)=="table" and not tb[i]) then
        tb[i]=deepcopy(v)
      end
    end
    setmetatable(tb,meta)
  end
end
local function _get_value_1(s,v,is_arrary)
	local r=""
	local count=0
    if(is_arrary=="set") then
    	for k,_v in pairs(v) do
    		count=count+1
        	r=r..bpack(s,k)
      	end
    elseif(is_arrary=="string_map") then
     	for k,_v in pairs(v) do
     		count=count+1
     		r=r..bpack(t.default_decl.string..s,tostring(k),_v)
      	end
    elseif(is_arrary=="unordered") then
     	for k,_v in pairs(v) do
     		count=count+1
        	r=r..bpack(s,_v)
      	end
    else
		for k,_v in ipairs(v) do
			count=count+1
			r=r..bpack(s,_v)
		end
    end
	return bpack(t.default_decl.uintlua,count)..r
end
local function _get_value_2(_de,v,is_arrary)
	local r=""
	local count=0
    if(is_arrary=="set") then
    	for k,_v in pairs(v) do
    		count=count+1
   			r=r..t._get_internal(_de,k)
  		end
  	elseif(is_arrary=="string_map") then
     	for k,_v in pairs(v) do
     		count=count+1
     		r=r..bpack(t.default_decl.string,tostring(k))..t._get_internal(_de,_v)
      	end
    elseif(is_arrary=="unordered") then
     	for k,_v in pairs(v) do
     		count=count+1
        	r=r..t._get_internal(_de,_v)
      	end
    else
		for k,_v in ipairs(v) do
			count=count+1
			r=r..t._get_internal(_de,_v)
		end
    end
	return bpack(t.default_decl.uintlua,count)..r
end

local function get_internal(de,l)--get internal list from final
	if(not de) then return nil end
	local ret=""
	local typ,value,syb,is_arrary
	for i,v in ipairs(de) do
		value=rawget(l, v[1])
		if(value) then
			typ=v[2]
			is_arrary=v[3]
			syb=t.default_decl[typ]
			if(syb) then
				ret=ret..(is_arrary and bpack(t.default_decl.char,1)..(_get_value_1(syb,value,is_arrary)) or bpack(t.default_decl.char..syb,1,value))
			else
				ret=ret..bpack(t.default_decl.char,1)..(is_arrary and _get_value_2(t.decl[typ],value,is_arrary) or get_internal(t.decl[typ],value))
			end
		else
			ret=ret..bpack(t.default_decl.char,0)
		end
	end
	return ret
end
t._get_internal=get_internal

local function to_internal(de,str,pos)--internal list to final
	if(not str) then return end
	local ret={}
	local v,syb,typ,is_arrary,key,set_value,has_value,count
	for di,d in ipairs(de) do
		has_value,pos=bunpack(t.default_decl.char,str,pos)
		if(has_value~=0) then
			typ=d[2]
			is_arrary=d[3]
			syb=t.default_decl[typ]
			if(syb) then
				if(is_arrary) then
					v={}
					count,pos=bunpack(t.default_decl.uintlua,str,pos)
		            if(is_arrary=="set") then
		              for i=1,count do
		                set_value,pos=bunpack(syb,str,pos)
		                v[set_value]=true
		              end
		            elseif(is_arrary=="string_map") then
		              for i=1,count do
		                key,set_value,pos=bunpack(t.default_decl.string..syb,str,pos)
		                v[key]=set_value
		              end
		            else--unordered and arrary
		              for i=1,count do
		                v[i],pos=bunpack(syb,str,pos)
		              end             
		            end
				else
					v,pos=bunpack(syb,str,pos)
				end
			else
				if(is_arrary) then
					v={}
					local _t=t.decl[typ]
					count,pos=bunpack(t.default_decl.uintlua,str,pos)
		            if(is_arrary=="set") then
		              for i=1,count do
		                set_value,pos=to_internal(_t,str,pos)
		                v[set_value]=true
		              end
		            elseif(is_arrary=="string_map") then
		              for i=1,count do
		              	key,pos=bunpack(t.default_decl.string,str,pos)
		                set_value,pos=to_internal(_t,str,pos)
		                v[key]=set_value
		              end
		            else--unordered and arrary
		              for i=1,count do
		                v[i],pos=to_internal(_t,str,pos)
		              end             
		            end
				else
					v,pos=to_internal(t.decl[typ],str,pos)
				end
			end
			ret[d[1]]=v
		end
	end
  	_add_default_values(ret,de)
	return ret,pos
end

function t.new(decl_name,tb)
  local ret = tb or {}
  ret.___decl_name=decl_name
  _add_default_values(ret,t.decl[decl_name])
  return ret
end


function t.encode(name,tbl,assign_name)
  name=name or tbl.___decl_name
  if(not name) then error("must specify the declaration name") end
  if(not tbl.___decl_name and assign_name) then tbl.___decl_name=name end
  local de=t.decl[name]
  if(not de) then error("type not found "..name) return end
  local prefix=assign_name and bpack(t.default_decl.char..t.default_decl.ztstring,1,name) 
  or bpack(t.default_decl.char,0)
  return prefix..get_internal(de,tbl)
end


function t.decode(name,str)
  if(not str) then return end
  local has_name,pos=bunpack(t.default_decl.char,str)
  if(has_name==1) then
  	name,pos=bunpack(t.default_decl.ztstring,str,pos)
  end
  if(not name) then
	error("unkown declaration name")
	return
  else
    local de=t.decl[name]
    if(not de) then error("type not found "..name) return end
    local ret = to_internal(de,str,pos)
    if(not ret) then return end
    ret.___decl_name=name
    return ret
  end
end

function t.get_decl(name)
	return t.decl[name]
end
function t.get_proto_type_name(name,key)
	if(t.decl[name]) then
		for i,v in ipairs(t.decl[name]) do
			if(v[1]==key) then
				return v[2]
			end
		end
	end
end

function t.register(decl_tbl)
	for i,v in pairs(decl_tbl) do
		t.register_one(i,v)
	end
end

function t.register_one(name,decl)
	if(t.default_decl[name]) then error("Can not accept predefined types: "..name) return end
	t.decl[name]=decl
  	t.meta[name]=nil
end

return t
