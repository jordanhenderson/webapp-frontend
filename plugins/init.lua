local ffi = require("ffi")
ffi.cdef[[
typedef struct { const char* data; int len; } webapp_str_t;
int ConnectDatabase(void* db, int database_type, const char* host, const char* username, const char* password, const char* database);
long long ExecString(void* db, webapp_str_t* in);
void DisableBackgroundQueue(void* app);
]]
c = ffi.C
@include 'plugins/constants.lua'
local common = require "common"
c.ConnectDatabase(db, DATABASE_TYPE_SQLITE, "webapp.sqlite", nil, nil, nil)
c.ExecString(db, common.cstr(PRAGMA_FOREIGN))
for k,v in ipairs(common.split(CREATE_DATABASE, ";")) do
	c.ExecString(db, common.cstr(v))
end

-- Disable background queue (long running operations): c.DisableBackgroundQueue(app)
