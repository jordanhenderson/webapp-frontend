@include 'plugins/constants.lua'

local init = ffi.new("WorkerInit")
local common = compile("common.lua")

function initialise_database()
	local db = c.Database_Create()
	c.Database_Connect(db, DATABASE_TYPE_SQLITE, 
					  "webapp.sqlite", nil, nil, nil)
					  
	c.Database_Exec(db, common.cstr(SQL_SESSION(DATABASE_TYPE_SQLITE)))
	c.Database_Exec(db, common.cstr(PRAGMA_FOREIGN))
	c.Database_Exec(db, common.cstr(BEGIN_TRANSACTION))
	c.Database_Exec(db, common.cstr(SYSTEM_SCHEMA))

	--Handle database version management
	local version = 0
	local latest_version = #APP_SCHEMA
	--Check the current version
	local query = 
		common.query_create(db, SELECT_FIELD("value", "system", "key"))

	c.Query_Bind(query, common.cstr("version"))
	if c.Query_Select(query) == DATABASE_QUERY_STARTED and 
	   query.column_count == 1 then
	   --Version field exists.
		version = tonumber(common.appstr(query.row[0]))
	end

	--Execute each 'update'
	if version < latest_version then
		for k,v in ipairs(APP_SCHEMA) do
			if k > version then
				for i, j in ipairs(common.split(v, ";")) do
					c.Database_Exec(db, common.cstr(j))
				end
			end
		end
	end

	local version_str = "'version', " .. latest_version
	--Update the stored schema version
	c.Database_Exec(db, 
		common.cstr(INSERT_FIELD("system", "key, value", version_str)))
	c.Database_Exec(db, common.cstr(COMMIT_TRANSACTION))
end

--Initialise the database(s)
initialise_database()

init.script = "core/process.lua"
init.port = 5000
init.request_size = ffi.sizeof("LuaRequest")
c.Worker_Create(init)
