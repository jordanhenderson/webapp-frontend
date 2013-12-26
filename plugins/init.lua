local ffi = require("ffi")
ffi.cdef[[
typedef struct { const char* data; int len; } webapp_str_t;
typedef struct { int status; long long lastrowid; int column_count; int db_type; webapp_str_t** row; webapp_str_t** desc; int need_desc; int have_desc; int rows_affected; } Query;
typedef struct 
{ void* socket; 
  void* buf;
  void* headers;
  int recv_amount; 
  int length; 
  int method; 
  webapp_str_t uri; 
  webapp_str_t host;
  webapp_str_t user_agent;
  webapp_str_t cookies;
  webapp_str_t request_body;
} Request;
int ConnectDatabase(void* db, int database_type, const char* host, const char* username, const char* password, const char* database);
long long ExecString(void* db, webapp_str_t* in);
void DisableBackgroundQueue(void* app);
void SetParamInt(void* app, unsigned int param, unsigned int value);
Query* CreateQuery(webapp_str_t* in, Request*, int desc);
void SetQuery(Query* query, webapp_str_t* in);
void BindParameter(Query* query, webapp_str_t* in);
int SelectQuery(void* db, Query* query);
]]
c = ffi.C
@include 'plugins/constants.lua'
common = require "common"
handlers = load_handlers()
request = ffi.cast("Request*", tmp_request)
c.ConnectDatabase(db, DATABASE_TYPE_SQLITE, "webapp.sqlite", nil, nil, nil)
c.ExecString(db, common.cstr(PRAGMA_FOREIGN))
for k,v in ipairs(common.split(CREATE_DATABASE, ";")) do
	c.ExecString(db, common.cstr(v))
end
handlers.updateUser[2](@join("user=admin&pass=admin&auth=", AUTH_ADMIN), nil, nil, AUTH_ADMIN)
c.SetParamInt(app, WEBAPP_PARAM_PORT, 5000)

-- Disable background queue (long running operations): c.DisableBackgroundQueue(app)
