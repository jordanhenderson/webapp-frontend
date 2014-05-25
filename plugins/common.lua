@include 'plugins/constants.lua'

--[[ Globals consumed by this file: 
	 static_strings
	 static_strings_count
--]]

local M = {}
M.wstr = ffi.cast("webapp_str_t*", static_strings)
M.split = function (str, sep)
	local sep, fields = sep or ":", {}
	local pattern = string.format("([^%s]+)", sep)
	str:gsub(pattern, function(c) fields[#fields+1] = c end)
	return fields
end

M.appstr = function(webapp_str)
	if webapp_str == nil then
		webapp_str = M.wstr
	end
	return ffi.string(webapp_str.data, tonumber(webapp_str.len))
end

M.setstr = function(str, dest)
	dest.data = str
	if str ~= nil then
		dest.len = string.len(str)
	else
		dest.len = 0
	end
end

--Handle temporary string storage
local ctr = 0
M.cstr = function(str)
	ctr = (ctr + 1) % static_strings_count
	local s = M.wstr[ctr]
	M.setstr(str, s)
	return s
end

M.buffer = function(str, len)
	ctr = (ctr + 1) % static_strings_count
	local s = M.wstr[ctr]
	s.data = str
	s.len = len
	return s
end

M.unescape = function(str)
	str = string.gsub(str, "+", " ")
	str = string.gsub(str, "%%(%x%x)", function (h)
		return string.char(tonumber(h, 16))
	end)
	return str
end

M.tohex = function(s, upper)
	if type(s) == 'number' then
		return string.format(upper and '%08.8X' or '%08.8x', s)
	end
	if upper then
		return (s:gsub('.', function(c)
		  return string.format('%02X', string.byte(c))
		end))
	else
		return (s:gsub('.', function(c)
		  return string.format('%02x', string.byte(c))
		end))
	end
end

M.endsWith = function(s, send)
	return #s >= #send and s:find(send, #s-#send+1, true) and true or false
end

iterdir = function(base, path, recurse)
	local dir = ffi.new("Directory")
	local start_dir = base .. '/' .. path
	c.tinydir_open(dir, start_dir)
	while dir.has_next == 1 do
		local file = ffi.new("DirFile")
		c.tinydir_readfile(dir, file)
		local pstr = ffi.string(file.name)
		local dir_path = path:len() == 0 and pstr or path .. '/' .. pstr
		if file.name[0] ~= 46 then
			coroutine.yield(dir_path, file.is_dir)
			if recurse == 1 then
				iterdir(base, dir_path, 1)
			end
		end
		c.tinydir_next(dir)
	end
	c.tinydir_close(dir)
end

M.iterdir = function(base, path, recurse)
	return coroutine.wrap(function () iterdir(base, path, recurse) end)
end

M.find_first_of = function(str, chars)
	local foundpos = string.len(str) + 1
	for i = 1, string.len(chars) do
		local c = string.sub(chars, i, i)
		local f = string.find(str, c)
		if f and f <= foundpos then
			foundpos = f
		end
		
	end
	return foundpos
end

M.gensql = function(query, query_type, tbl, cond, validcols, ...) 
	if query_type == 0 then --QUERY_TYPE_INSERT
		local vs = ""
		local cols = ""
		local col_count = 0
		for k,v in ipairs(validcols) do
			local val = select(k, ...)
			if val ~= nil then
				c.Query_Bind(query, M.cstr(val))
				cols = cols .. v .. ","
				col_count = col_count + 1
			end
		end
		cols = cols:sub(0, #cols - 1)
		vs = string.rep("?,", col_count - 1) .. "?"
		return "INSERT INTO " .. tbl .. " (" .. cols .. ") VALUES (" .. vs .. ");"
	elseif query_type == 1 then --QUERY_TYPE_UPDATE
		local set = ""
		for k,v in ipairs(validcols) do
			local val = select(k, ...)
			if val ~= nil then
				c.Query_Bind(query, M.cstr(val))
				set = set .. v .. "=" .. "?,"
			end
		end
		set = set:sub(0, #set - 1)
		if tbl:len() == 0 then
			return ""
		end
		return "UPDATE " .. tbl .. " SET " .. set .. " WHERE " .. cond .. "=?;"
	end
end

M.query_create = function(db, qry, desc)
	desc = desc or 0
	qry = qry and M.cstr(qry)
	local q = ffi.gc(c.Query_Create(db, qry), c.Query_Destroy)
	q.need_desc = desc
	return q
end

--Preallocate tables.
local ret, new_table = pcall(require, "table.new")
if not ret then new_table = function (narr, nrec) return {} end end

M.new_table = new_table

M.connect = function(addr, port)
	local socket = c.Socket_Connect(worker, request, 
								   M.cstr(addr), M.cstr(port))
	coroutine.yield() --Socket (possibly) connects.
	return socket
end

--Wait for n_bytes. Uses asio, yields.
M.read_data = function(socket, n_bytes, timeout)
	local output = 
		ffi.gc(c.Socket_Read(socket, worker, request, n_bytes, timeout),
			   c.String_Destroy)
	coroutine.yield()
	return output
end

M.write_data = function(socket, data)
	c.Socket_Write(socket, M.cstr(data))
end

M.close = function(socket)
	c.Socket_Destroy(socket)
end

return M
