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
void Time_Get(struct tm*);
void Time_Update(struct tm*);
]]
c = ffi.C

local M = {}
local Time = {}
Time.__index = Time
function Time:ymd()
	return 1900 + self.s.tm_year, self.s.tm_mon, self.s.tm_mday
end

function Time:hms()
	return self.s.tm_hour, self.s.tm_min, self.s.tm_sec
end

function Time:weekday()
	return self.s.tm_wday
end

function Time:add_days(days)
	self.s.tm_mday = self.s.tm_mday + days
	c.Time_Update(self.s)
end

M.nowutc = function()
	local t = {}
	setmetatable(t, Time)
	t.s = ffi.new("struct tm")
	c.Time_Get(t.s)
	return t
end

M.todate = function(date_string)
	local y, m, d = date_string:match("(%i)-(%02i)-(%02i)")
	local t = {}
	setmetatable(t, Time)
	t.s = ffi.new("struct tm")
	c.Time_Get(t.s)
	return t
end

return M
