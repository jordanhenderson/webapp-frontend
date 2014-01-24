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

M.get_parameters = function(params)
	local p = {}
	for i,k in params:gmatch("([^&=]+)=([^&=]+)") do
		p[M.unescape(i)] = M.unescape(k)
	end
	
	return p
end

M.get_function = function(params)
	local f = ""
	local m = params:gmatch("t=([^&=]+)")
	for i in m do
		return i
	end
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

return M
