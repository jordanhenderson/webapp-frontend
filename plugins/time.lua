--Time functionality.
local ffi = require("ffi")
ffi.cdef[[
struct tm { 
  int tm_sec;
  int tm_min;
  int tm_hour;
  int tm_mday;
  int tm_mon;
  int tm_year;
  int tm_wday;
  int tm_yday;
  int tm_isdst;
};
void GetWebappTime(struct tm*);
]]
c = ffi.C

local M = {}
local Time = {}
Time.__index = Time
local s = ffi.new("struct tm")
function Time:ymd()
	return 1900 + s.tm_year, s.tm_mon, s.tm_mday
end

function Time:hms()
	return s.tm_hour, s.tm_min, s.tm_sec
end

function Time:weekday()
	return s.tm_wday
end

function Time:add_days(days)
	s.tm_mday = s.tm_mday + days
end

M.nowutc = function()
	local t = {}
	setmetatable(t, Time)
	c.GetWebappTime(s)
	return t
end


return M
