@include 'plugins/constants.lua'

--Precompile (extra) scripts here.
common = 					compile("plugins/common.lua")
handlers, page_security = 	compile("plugins/core/handlers.lua")

db = c.CreateDatabase()
c.ConnectDatabase(db, DATABASE_TYPE_SQLITE, 
				  "webapp.sqlite", nil, nil, nil)

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
		if k > version then
			for i, j in ipairs(common.split(v, ";")) do
				c.ExecString(db, common.cstr(j))
			end
		end
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
