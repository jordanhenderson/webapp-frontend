local ffi = require("ffi")
ffi.cdef[[
typedef struct {
  const char* data; 
  int len; 
} webapp_str_t;
typedef struct {
  int status; 
  long long lastrowid; 
  int column_count; 
  webapp_str_t* row; 
  webapp_str_t* desc; 
  int need_desc; 
  int have_desc; 
  int rows_affected; 
} Query;
typedef struct { 
  void* socket; 
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
typedef struct {
  int nError; 
  size_t db_type;
} Database;

//Database Functions
Database* GetDatabase(void* app, size_t index);
Query* CreateQuery(webapp_str_t* in, Request*, Database*, int desc);
void SetQuery(Query* query, webapp_str_t* in);
void BindParameter(Query* query, webapp_str_t* in);
int SelectQuery(Query* query);
long long ExecString(void* db, webapp_str_t* in);
int ConnectDatabase(Database* db, int database_type, const char* host, const char* username, const char* password, const char* database);
Database* CreateDatabase(void* app);

//Webapp Functions
void SetParamInt(void* app, unsigned int param, int value);
void GetParamInt(void* app, unsigned int param);
void Template_ReloadAll();
void Template_Load(webapp_str_t* page);

]]
--Globals provided to this file: app
c = ffi.C
@include 'plugins/constants.lua'
common = require "common"
handlers = load_handlers()
request = ffi.cast("Request*", tmp_request)
db = c.CreateDatabase(app) 
c.ConnectDatabase(db, DATABASE_TYPE_SQLITE, "webapp.sqlite", nil, nil, nil)

c.ExecString(db, common.cstr(PRAGMA_FOREIGN))
for k,v in ipairs(CREATE_DATABASE(DATABASE_TYPE_SQLITE)) do
	c.ExecString(db, common.cstr(v))
end

handlers.updateUser[2](@join("user=admin&pass=admin&auth=", AUTH_ADMIN), nil, nil, AUTH_ADMIN)
c.SetParamInt(app, WEBAPP_PARAM_PORT, 5000)

c.Template_ReloadAll()
for file, dir in common.iterdir("content/", "", 1) do
	if dir == 0 and common.endsWith(file, ".html") then 
		c.Template_Load(common.cstr("content/" .. file))
	end
end

-- Disable background queue (long running operations): c.SetParamInt(app, WEBAPP_PARAM_BGQUEUE, 0);
