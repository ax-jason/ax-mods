local version = "1.0"
local continue_mark = "continue"
local string_len_limit = 32
local help_text = string.format([[
Version: %s
-------------------------
[Lua usage]
Start debugging: require("dbg").start()
Stop debugging: require("dbg").stop()
Insert into any where to trigger a break point: require("dbg").bp()

-------------------------
[Commands]
Step over           : Type enter or step
Step in             : i or stepin
Continue the thread : g or go or cont
Move down call stack: d or .
Move up call stack  : u or ,
Set local value     : l.xxx = yyy
Set up value        : u.xxx = yyy
]],
version)

local t = {
	enable = false,
	cmd=  {},
	co_map = {},
	bp_list = {},
	print_fn_name = "print",
}

local what_desc = {
	["Lua"] = "Lua function",
	["C"] = "C function",
	["main"] = "Main part",
	["tail"] = "Tail function",
	[""] = "Unknown"
}
local private = {}

last_changed_local_value_name, last_changed_upvalue_name = nil, nil

local function load_string(s, env)
	local a, b
	if(setfenv) then
		a, b = loadstring(s)
		if(a) then
			setfenv(a, env)
		end
	else
		a, b = load(s, nil, nil, env)
	end
	return a, b
end

local function debug_gethook()
	local a, b, c = debug.gethook(coroutine.running())
	return a, b, c
end

local function debug_getinfo(fn, what)
	local co = coroutine.running()
	if(type(fn) == "number") then fn = fn + 1 end
	if(co) then
		return debug.getinfo(co, fn, what)
	else
		return debug.getinfo(fn, what)
	end
end

local function debug_getlocal(level, local_index)
	local co = coroutine.running()
	if(co) then
		return debug.getlocal(co, level + 1, local_index)
	else
		return debug.getlocal(level + 1, local_index)
	end
end

local function debug_sethook(hook, mask, count)
	local co = coroutine.running()
	if(co) then
		return debug.sethook(co, hook, mask, count)
	else
		return debug.sethook(hook, mask, count)
	end
end

local function debug_setlocal(level, local_index, value)
	local co = coroutine.running()
	if(co) then
		return debug.setlocal(co, level + 1, local_index, value)
	else
		return debug.setlocal(level + 1, local_index, value)
	end
end

function private.get_thread_data(k)
	local co = coroutine.running() or 1

	local data = t.co_map[co]
	if(not data) then
		data = {}
		t.co_map[co] = data
	end
	if(k) then
		return data[k]
	else
		return data
	end
end

function private.set_thread_data(k, v)
	private.get_thread_data()[k] = v
end

function private.get_step_over_depth()
	return (private.get_thread_data().step_over_depth)
end

function private.set_step_over_depth(v)
	private.set_thread_data("step_over_depth", v)
end

function private.get_current_depth()
	local depth = 2
	while(debug_getinfo(depth)) do
		depth = depth + 1
	end
	return depth
end

function private.print_tbl(tbl)
	local ret = "{"
	for k,v in pairs(tbl) do
		ret = ret..string.format("%s = %s\n", tostring(k), tostring(v))
	end
	return ret .. "}"
end

function private.hook(event_type, line_num)
	if(not t.enable) then 
		private.disable_hook()
		private.set_step_over_depth(nil)
		return 
	end
	if(event_type == "line") then
		local cur_depth = private.get_current_depth()
		local step_over_depth = private.get_step_over_depth()
		if(not step_over_depth or cur_depth <= step_over_depth) then
			private.set_step_over_depth(cur_depth)
			private.pause_for_bp(private.get_thread_data("message"), 1)
		end
	end
end

function private.enable_hook(fn, level)
	if(not t.enable) then return end
	if(not fn) then fn = private.hook end
	if(debug_gethook() == fn) then return end
	private.set_step_over_depth(private.get_current_depth() - level)
	debug_sethook(fn, "l")
end

function private.disable_hook()
	debug_sethook()
end

local function get_type_desc(value)
	local tp_desc = ""
	local tp = type(value)
	if(tp == "number" or tp == "string") then
		tp_desc = tp..": "
	end
	return tp_desc
end

local function cut_str(str)
	local len = string.len(str)
	str = string.match(str, "(.-)\r?\n") or str
	if(string.len(str) > string_len_limit) then str = string.sub(str, 1, string_len_limit) end
	return string.format([["%s"]],string.len(str) == len and str or str.." ...")
end

function private.get_local(level, indice)
	local ret = ""
	local index = 1
	while(true) do
		local name, value = debug_getlocal(level + 2, index)

		if(not name) then break end
		indice[name] = index
		if(string.sub(name,1,1) ~= "(") then
			local prefix = last_changed_local_value_name == name and "*" or ""
			if(type(value) == "string") then
				value = cut_str(value)
			end
			ret = ret..string.format("%slocal %s = %s%s\n", prefix, name, get_type_desc(value), tostring(value))
		end
		index = index + 1
	end
	return ret
end

function private.get_up_values(fn, indice)
	local ret = ""
	if(not fn) then return ret end
	local index = 1
	while(true) do
		local name, value = debug.getupvalue(fn, index)

		if(not name) then break end
		indice[name] = {fn, index}
		local prefix = last_changed_upvalue_name == name and "*" or ""
		if(type(value) == "string") then
			value = cut_str(value)
		end
		ret = ret..string.format("%supvalue %s = %s%s\n", prefix, name, get_type_desc(value), tostring(value))

		index = index + 1
	end
	return ret
end

local function get_stack_list(level)
	local list = {}
	local depth = level + 2
	local info = debug_getinfo(depth)
	while(info) do
		table.insert(list, info)
		depth = depth + 1
		info = debug_getinfo(depth)
	end
	return list
end

function private.get_traceback_text(level, index)
	local function __set_local(tbl, k, v)
		local indice = getmetatable(tbl).indice
		local local_index = indice[k]
		if(local_index) then
			local name = debug_setlocal(level + index + 3, local_index, v)
			if(name) then
				--print(string.format("local value %s has been set to %s", name, tostring(v)))
				last_changed_local_value_name = name
				t.cmd.refresh(level + 3)
			else
				print(string.format("local value %s not valid any more", name))
			end
		else
			print(string.format("local value %s not found", k))
		end
	end

	local function __set_up(tbl, k, v)
		local indice = getmetatable(tbl).indice
		local info = indice[k]
		if(info) then
			local name = debug.setupvalue(info[1], info[2], v)
			if(name) then
				--print(string.format("upvalue %s has been set to %s", name, tostring(v)))
				last_changed_upvalue_name = name
				t.cmd.refresh(level + 3)
			else
				print(string.format("upvalue %s not valid any more", name))
			end
		else
			print(string.format("upvalue %s not found", k))
		end
	end

	local list = get_stack_list(level + 1)
	
	local ret = ""
	local local_text = ""
	local count = #list
	if(index > count) then index = count end
	if(index < 1) then index = 1 end
	local function create_meta(_newindex)
		return setmetatable({},{indice = {}, __newindex = _newindex})
	end
	local local_indice, up_indice = create_meta(__set_local), create_meta(__set_up)
	for i, v in ipairs(list) do
		local prefix = "    "
		if(i == index) then
			local_text = private.get_local(i - 1 + level + 1, getmetatable(local_indice).indice)..private.get_up_values(v.func, getmetatable(up_indice).indice)
			prefix = "==> "
		end
		local fn_name = string.format("in %s %s", what_desc[v.what or ""], v.name or "")

		ret = ret..string.format("%s(%s)[%s]: %s: %s\n", prefix, i, v.short_src, v.currentline, fn_name)
	end
	private.get_thread_data("step_data").local_indice, private.get_thread_data("step_data").up_indice = local_indice, up_indice
	local thread_desc = tostring(coroutine.running() or "Main thread")
	return local_text..string.format("\n------ Call stack <%s> ------\n", thread_desc)..ret, index, local_indice, up_indice
end

function private.pause_for_bp(content, level)
	if(not level) then level = 0 end
	level = level + 1
	if(not content) then
		content = ""
	else
		content = content .. "\n"
	end
	
	private.set_thread_data("step_data", {stack_index = 1})

	local text = private.get_traceback_text(level, private.get_thread_data("step_data").stack_index)
	t.clearscreen(content .. text)

	while(true) do
		last_changed_local_value_name, last_changed_upvalue_name = nil, nil
		io.write("lua_debug> ")
		local input_str = io.read()

		if(not input_str or input_str == "") then input_str = "step" end

		local fn, compile_err, fn_ret, input_return_value

		fn = t.cmd[input_str]
		if(not fn) then
			if(string.sub(input_str,1,1) == "'") then
				input_str = string.format("%s(%s)", t.print_fn_name or "print", string.sub(input_str,2))
			end
			local function _index(tbl, k)
				local local_index = getmetatable(private.get_thread_data("step_data").local_indice).indice[k]
				if(local_index) then
					local name, value = debug_getlocal(level + private.get_thread_data("step_data").stack_index + 3, local_index)
					if(name) then
						return value
					end
				else
					local upinfo = getmetatable(private.get_thread_data("step_data").up_indice).indice[k]
					if(upinfo) then
						local name, value = debug.getupvalue(upinfo[1], upinfo[2])
						if(name) then
							return value
						end
					end
				end
				return _G[k]
			end
			local function _newindex(tbl, k, v)
				local local_index = getmetatable(private.get_thread_data("step_data").local_indice).indice[k]
				if(local_index) then
					local name = debug_setlocal(level + private.get_thread_data("step_data").stack_index + 3, local_index, v)
					if(name) then
						last_changed_local_value_name = name
						t.cmd.refresh(level + 3)
						return
					end
				else
					local upinfo = getmetatable(private.get_thread_data("step_data").up_indice).indice[k]
					if(upinfo) then
						local name = debug.setupvalue(upinfo[1], upinfo[2], v)
						if(name) then
							last_changed_upvalue_name = name
							t.cmd.refresh(level + 3)
							return
						end
					end
				end
				_G[k] = v
			end
			fn, compile_err = load_string(input_str, setmetatable({}, {__index = _index, __newindex = _newindex}))
		end
		
		if(fn) then
			fn_ret, input_return_value = pcall(fn, level + 1) -- pcall need one more depth
			if(fn_ret) then
				if(input_return_value == continue_mark) then break end
			elseif(input_return_value) then
				print(input_return_value)
			end
		elseif(compile_err) then
			print(compile_err)
		end

	end
end


function t.start()
	if(not t.enable) then
		t.enable = true
		print("dbg started")
	end
end

function t.stop()
	t.enable = false
	private.set_step_over_depth(nil)
	private.disable_hook()
	print("dbg stopped")
end

function t.bp(level, msg)
	private.set_thread_data("message", msg)
	private.enable_hook(nil, (level or 0)  + 1)
end

t.pause = t.bp

function t.setbp(file, line)
	--debug.debug()
end

function t.clearscreen(content)
	if(os.getenv("HOME")) then
		os.execute("clear")
	else
		os.execute("cls")
	end
	
	if(content) then
		print("\n"..content.."\n")
	end
end

function t.cmd.step()
	return continue_mark
end

function t.cmd.stepin()
	private.set_step_over_depth(nil)
	return continue_mark
end
t.cmd["i"] = t.cmd.stepin

function t.cmd.browse_step(level, offset)
	local text, index = private.get_traceback_text(level + 1, private.get_thread_data("step_data").stack_index + offset)
	private.get_thread_data("step_data").stack_index = index
	t.clearscreen(private.get_thread_data("message").."\n"..text)
end

function t.cmd.d(level)
	t.cmd.browse_step(level + 1, 1)
end
t.cmd["."] = t.cmd.d

function t.cmd.u(level)
	t.cmd.browse_step(level + 1, -1)
end
t.cmd[","] = t.cmd.u


function t.cmd.refresh(level)
	t.cmd.browse_step(level + 1, 0)
end

function t.cmd.cont()
	private.set_step_over_depth(nil)
	private.disable_hook()
	return continue_mark
end
t.cmd["g"] = t.cmd.cont
t.cmd["go"] = t.cmd.cont

function t.cmd.help()
	print(help_text)
end
t.cmd["h"] = t.cmd.help

return t