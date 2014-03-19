local ffi = require("ffi")
ffi.cdef[[
typedef struct { 
  const char* data; 
  uint32_t len; 
  int allocated;
} webapp_str_t;

//Filesystem API
typedef struct {
  char path[4096];
  int has_next;
  int n_files;
  void* _files;
  void* _h;
  void* _f;
  void* _d;
  void* _e;
} Directory;

typedef struct {
  char path[4096];
  char name[256];
  int is_dir;
  int is_reg;
  void* _s;
} DirFile;

int tinydir_open(Directory*, const char* path);
int tinydir_open_sorted(Directory*, const char* path);
void tinydir_close(Directory*);
int tinydir_next(Directory*);
int tinydir_readfile(Directory*, DirFile*);
]]
c = ffi.C

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

M.cstr = function(str, idx)
	if idx == nil then
		idx = 0
	end
	M.wstr[idx].data = str
	if str ~= nil then
		M.wstr[idx].len = string.len(str)
	else
		M.wstr[idx].len = 0
	end
	return M.wstr[idx]
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
	if query_type == QUERY_TYPE_UPDATE then
		local set = ""
		for k,v in ipairs(validcols) do
			local val = select(k, ...)
			if val ~= nil then
				c.BindParameter(query, common.cstr(val))
				set = set .. v .. "=" .. "?,"
			end
		end
		set = set:sub(0, #set - 1)
		if tbl:len() == 0 then
			return ""
		end
		return "UPDATE " .. tbl .. " SET " .. set .. " WHERE " .. cond .. "=?;"
	elseif query_type == QUERY_TYPE_INSERT then
		local vs = ""
		local cols = ""
		local col_count = 0
		for k,v in ipairs(validcols) do
			local val = select(k, ...)
			if val ~= nil then
				c.BindParameter(query, common.cstr(val))
				cols = cols .. v .. ","
				col_count = col_count + 1
			end
		end
		cols = cols:sub(0, #cols - 1)
		vs = string.rep("?,", col_count - 1) .. "?"
		return "INSERT INTO " .. tbl .. " (" .. cols .. ") VALUES (" .. vs .. ");"
	end
end

return M
