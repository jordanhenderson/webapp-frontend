local ffi = require("ffi")
ffi.cdef[[
typedef struct { const char* data; int len; } webapp_str_t;
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
	return ffi.string(webapp_str.data, webapp_str.len)
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

M.get_parameters = function(params)
	local p = {}
	
	local m = params:gmatch("(%w+)=(%w+)")
	for i,k in m do
		p[i] = k
	end
	
	return p
end

M.get_function = function(params)
	local f = ""
	local m = params:gmatch("t=(%w+)")
	for i in m do
		return i
	end
end

return M