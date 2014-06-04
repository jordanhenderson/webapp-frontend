@include 'plugins/constants.lua'

local init = ffi.new("WorkerInit")
local common = compile("common.lua")

function initialise_database()
	local db = c.Database_Create()
	c.Database_Connect(db, DATABASE_TYPE_SQLITE, 
					  "webapp.sqlite", nil, nil, nil)
	c.Database_Exec(db, common.cstr(SQL_SESSION(db.db_type)))
	c.Database_Exec(db, common.cstr(PRAGMA_FOREIGN))
end

--Initialise the database(s)
initialise_database()

init.script = "core/process.lua"
init.port = 5000
init.request_size = ffi.sizeof("LuaRequest")
c.Worker_Create(init)
