local ffi = require("ffi")
ffi.cdef[[
typedef struct { const char* data; int len; } webapp_str_t;
void GetParameter(void* app, int param, webapp_str_t* out);
int ConnectDatabase(void* db, int database_type, const char* host, const char* username, const char* password, const char* database);
long long ExecString(void* db, webapp_str_t* in);
]]
c = ffi.C

@include 'plugins/constants.lua'
local common = require "common"

c.GetParameter(app, WEBAPP_PARAM_DBPATH, common.wstr)
c.ConnectDatabase(db, DATABASE_TYPE_SQLITE, common.wstr.data, nil, nil, nil)
for k,v in ipairs(common.split(CREATE_DATABASE, ";")) do
	c.ExecString(db, common.cstr(v))
end