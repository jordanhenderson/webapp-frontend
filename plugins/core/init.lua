local ffi = require("ffi")
ffi.cdef[[
typedef struct {
  const char* data; 
  int32_t len;
  int allocated; 
} webapp_str_t;
typedef struct {
  int status; 
  int64_t lastrowid; 
  int column_count; 
  webapp_str_t* row; 
  webapp_str_t* desc; 
  int need_desc; 
  int have_desc; 
  int rows_affected; 
} Query;
typedef struct { 
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
Database* CreateDatabase();
void DestroyDatabase(Database*);
Database* GetDatabase(size_t index);
Query* CreateQuery(webapp_str_t* in, Request*, Database*, int desc);
void SetQuery(Query* query, webapp_str_t* in);
void BindParameter(Query* query, webapp_str_t* in);
int SelectQuery(Query* query);
int64_t ExecString(void* db, webapp_str_t* in);
int ConnectDatabase(Database* db, int database_type, const char* host, const char* username, const char* password, const char* database);

//Webapp Functions
void SetParamInt(unsigned int param, int value);
int GetParamInt(unsigned int param);
void Template_Load(webapp_str_t* page);
void Template_Include(webapp_str_t* name, webapp_str_t* file);
]]
c = ffi.C
@include 'plugins/constants.lua'
common = require "common"
handlers = load_handlers()
db = c.CreateDatabase()
c.ConnectDatabase(db, DATABASE_TYPE_SQLITE, "webapp.sqlite", nil, nil, nil)

c.ExecString(db, common.cstr(SQL_SESSION(DATABASE_TYPE_SQLITE)))
c.ExecString(db, common.cstr(PRAGMA_FOREIGN))
c.ExecString(db, common.cstr(BEGIN_TRANSACTION))
c.ExecString(db, common.cstr(SYSTEM_SCHEMA))

--Handle database version management
local version = 0
local latest_version = #APP_SCHEMA
--Check the current version
local query = 
	c.CreateQuery(common.cstr(SELECT_FIELD("value", "system", "key")), 
				  request, db, 0)

c.BindParameter(query, common.cstr("version"))
if c.SelectQuery(query) == DATABASE_QUERY_STARTED and 
   query.column_count == 1 then
   --Version field exists.
	version = tonumber(common.appstr(query.row[0]))
end

--Execute each 'update'
if version < latest_version then
	for k,v in ipairs(APP_SCHEMA) do
		if k > version then c.ExecString(db, common.cstr(v)) end
	end
end

local version_str = "'version', " .. latest_version
--Update the stored schema version
c.ExecString(db, 
	common.cstr(INSERT_FIELD("system", "key, value", version_str)))
c.ExecString(db, common.cstr(COMMIT_TRANSACTION))


--Create a user, just in case.
handlers.updateUser[2](
	{user="admin",pass="admin",auth=_STR_(AUTH_ADMIN)}, 
	nil, nil, AUTH_ADMIN)

for file, dir in common.iterdir("content/", "", 1) do
	if dir == 0 and common.endsWith(file, ".html") then
		c.Template_Load(common.cstr("content/" .. file))
	end
end

for file, dir in common.iterdir("templates/", "", 1) do
	if dir == 0 then
		local f_upper = file:upper()
		if common.endsWith(f_upper, ".TPL") then
			f_upper = "T_" .. f_upper:sub(1, -5)
			c.Template_Include(common.cstr(f_upper), 
				common.cstr("templates/" .. file, 1))
		end
	end
end

--[[
Enable/Disable template caching (for debug purposes): 
	c.SetParamInt(WEBAPP_PARAM_TPLCACHE, 0)
Enable/Disable leveldb support (uses three threads, enabled by default): 
	c.SetParamInt(WEBAPP_PARAM_LEVELDB, 0)
Set the number of preferred threads (request handlers).
This value is negated by 3 if leveldb is enabled.
	c.SetParamInt(WEBAPP_PARAM_THREADS, 2)
--]]
