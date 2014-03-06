local ffi = require("ffi")
ffi.cdef[[
typedef struct { 
  const char* data; 
  int32_t len; 
  int allocated;
} webapp_str_t;
int QueueProcess(void* worker, webapp_str_t* func, webapp_str_t* vars);
void ClearCache(void* worker);
void Shutdown(void* worker);
void DestroySession(void* session);
void Template_ShowGlobalSection(void*, webapp_str_t*);
void Template_SetGlobalValue(void*, webapp_str_t* key, webapp_str_t* value);
void Template_SetValue(void*, webapp_str_t* key, webapp_str_t* value);
void Template_SetIntValue(void*, webapp_str_t* key, long value);
void* Template_Get(void*, webapp_str_t*);
void Template_Clear(void*);
]]
c = ffi.C

@include 'plugins/constants.lua'

local sha2 = require "sha2"
local time = require "time"

local common = require "common"

function hashPassword(password, salt)
	local pass --hashed password.
	--Process password, salt.
	if password ~= nil and string.len(password) > 0 then
		if salt == nil then
			salt = ""
			for i = 1,6 do
				salt = salt .. string.char(math.random(32, 126))
			end
		end
		pass = common.tohex(sha2.sha256(password .. salt))
	end
	return pass, salt
end

function gensql(query, query_type, tbl, cond, validcols, ...) 
	if query_type == QUERY_TYPE_UPDATE then
		local set = ""
		for k,v in ipairs(validcols) do
			local val = select(k, ...)
			if val ~= nil then
				c.BindParameter(query, common.cstr(val))
				set = set .. v .. "=" .. "?,"
			end
		end
		set = set:sub(0, #set - 1)
		if tbl:len() == 0 then
			return ""
		end
		return "UPDATE " .. tbl .. " SET " .. set .. " WHERE " .. cond .. "=?;"
	elseif query_type == QUERY_TYPE_INSERT then
		local vs = ""
		local cols = ""
		local col_count = 0
		for k,v in ipairs(validcols) do
			local val = select(k, ...)
			if val ~= nil then
				c.BindParameter(query, common.cstr(val))
				cols = cols .. v .. ","
				col_count = col_count + 1
			end
		end
		cols = cols:sub(0, #cols - 1)
		vs = string.rep("?,", col_count - 1) .. "?"
		return "INSERT INTO " .. tbl .. " (" .. cols .. ") VALUES (" .. vs .. ");"
	end
end

function dump_query(query)
	local hasdesc = false
	data = {}
	desc = {}
	if c.SelectQuery(query) == DATABASE_QUERY_STARTED then
		repeat
		row = {}
		for i=0, query.column_count - 1 do
			if not hasdesc then
				desc[i] = common.appstr(query.desc[i])
			end
			row[desc[i]] = common.appstr(query.row[i])
		end
		data[#data+1] = row
		hasdesc = true
		until c.SelectQuery(query) == DATABASE_QUERY_FINISHED
	end
	return data
end

function login(v, session)
	local password = v.pass
	local query = c.CreateQuery(common.cstr(SELECT_USER_LOGIN), request, db, 0)
	c.BindParameter(query, common.cstr(v.user))
	local user = query.row
	if c.SelectQuery(query) == DATABASE_QUERY_STARTED 
		and query.column_count == @col(COLS_USER) then
		local userid = tonumber(common.appstr(COL_USER("id")))
		--Check password.
		local salt = common.appstr(COL_USER("salt"))
		local storedpw = common.appstr(COL_USER("pass"))
		local hashedpw = ""
		if password ~= nil then hashedpw = hashPassword(password, salt) end
		if userid ~= nil and userid > 0 and hashedpw == storedpw then	
			globals.session = c.NewSession(worker, request)
			c.SetSessionValue(session, common.cstr("userid"), COL_USER("id"))
			return _MESSAGE("LOGIN_SUCCESS", 1)
		else
			return MESSAGE("LOGIN_FAILED")
		end
	else
		return MESSAGE("LOGIN_FAILED") -- no matching user (email)
	end
end

function logout(vars, session)
	c.DestroySession(session)
	return _MESSAGE("LOGOUT_SUCCESS", 1)
end

function updateUser(v, session, user, auth)
	--Input variables.
	local id = v.id
	local target_user = v.user
	local password = v.pass
	local target_auth = v.auth

	if auth == AUTH_USER or ((id == nil or id:len() == 0) and (target_user == nil or password == nil)) then 
		id = USERID --Use current user
	elseif id ~= nil and id:len() == 0 then
		id = nil --Ignore empty ID field (use INSERT query)
	end
	if auth == AUTH_USER and target_auth then
		target_auth = _STR_(AUTH_USER) --Users cannot change auth level.
	end
	
	local pass, salt = hashPassword(password)
	local query = c.CreateQuery(nil, request, db, 0)
	local query_type
	if id == nil then
		query_type = QUERY_TYPE_INSERT
	else
		query_type = QUERY_TYPE_UPDATE
	end

	local sql = gensql(query, query_type, "users", "id", {COLS_USER}, 
		target_user, pass, salt, target_auth)
	
	--Bind ID parameter (in case of update queries)
	c.BindParameter(query, common.cstr(id))
		
	c.SetQuery(query, common.cstr(sql))
	c.SelectQuery(query)
	local lastrowid = tonumber(query.lastrowid)
	if lastrowid > 0 or query.rows_affected > 0 then
		return cjson.encode({msg="UPDATEUSER_SUCCESS", id = id or lastrowid, type=RESPONSE_TYPE_MESSAGE})
	else
		return MESSAGE("UPDATEUSER_FAILED")
	end
end

function clearCache(vars, session)
	c.ClearCache(worker)
	return MESSAGE("CACHE_CLEARED")
end

function shutdown(vars, session)
	c.Shutdown(worker)
	return MESSAGE("SHUTTING_DOWN")
end

function handleTemplate(template, page, session, user, auth)
	--TODO: Place further template logic here.
	c.Template_Clear(template)
	if auth == AUTH_GUEST then
		c.Template_ShowGlobalSection(template, common.cstr("NOT_LOGGED_IN"))
	else
		c.Template_ShowGlobalSection(template, common.cstr("LOGGED_IN"))
	end
end

handlers = {
--Login
	login = {AUTH_GUEST, login},
--Logout
	logout = {AUTH_USER, logout},
--Clear any cached data.
	clearCache = {AUTH_ADMIN, clearCache},
--Shut down the server.
	shutdown = {AUTH_ADMIN, shutdown},
--Render a content template.
	handleTemplate = {AUTH_GUEST, handleTemplate},
--Update the current user (AUTH_USER) or a specific user.
	updateUser = {AUTH_USER, updateUser},
}

page_security = {

}

return function() return handlers, page_security end

