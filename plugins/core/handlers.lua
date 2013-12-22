local ffi = require("ffi")
ffi.cdef[[
typedef struct { const char* data; int len; } webapp_str_t;
int QueueProcess(void* app, webapp_str_t* func, webapp_str_t* vars);
void ClearCache(void* app, void* requests);
void DestroySession(void* session);
int Template_ShowGlobalSection(void*, webapp_str_t*);
int Template_SetGlobalValue(void*, webapp_str_t* key, webapp_str_t* value);
]]

local sha2 = require "sha2"
local time = require "time"
@include 'plugins/constants.lua'
c = ffi.C

--[[NOTES
common.wstr[2] provides user id. Do not write over [2] in order to preserve id.
--]]

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

function login(vars, session)
	local v = common.get_parameters(vars)
	local password = v["pass"]
	local query = c.CreateQuery(common.cstr(SELECT_USER_LOGIN), request, 0)
	c.BindParameter(query, common.cstr(v["user"]))
	local res = c.SelectQuery(db,query)
	if res == DATABASE_QUERY_STARTED and query.column_count == @col(COLS_USER_LOGIN) and query.row ~= nil then
		local userid = tonumber(common.appstr(query.row[@col(COLS_USER_LOGIN, "id")]))
		--Check password.
		local salt = common.appstr(query.row[@col(COLS_USER_LOGIN, "salt")])
		local storedpw = common.appstr(query.row[@col(COLS_USER_LOGIN, "pass")])
		local hashedpw = ""
		if password ~= nil then hashedpw = hashPassword(password, salt) end
		if userid ~= nil and userid > 0 and hashedpw == storedpw then
			c.SetSessionValue(session, common.cstr("userid", 1), query.row[@col(COLS_USER_LOGIN, "id")])
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

function updateUser(vars, session, user, auth)
	local v = common.get_parameters(vars)
	--Input variables.
	local id = v["id"]
	local user = v["user"]
	local password = v["pass"]
	local target_auth = v["auth"]
	if auth == AUTH_USER or ((id == nil or id:len() == 0) and (user == nil or password == nil)) then 
		id = common.appstr(common.wstr[2])
	end
	
	if auth == AUTH_USER and target_auth then
		target_auth = _STR_(AUTH_USER) --Users cannot change auth level.
	end
	
	local pass, salt = hashPassword(password)
	
	local query
	if id == nil and auth == AUTH_ADMIN then
		query = c.CreateQuery(common.cstr(ADD_USER), request, 0)
		--Insertion requires all values to be populated (non-nil).
		c.BindParameter(query, common.cstr(user))
		c.BindParameter(query, common.cstr(pass))
		c.BindParameter(query, common.cstr(salt))
		c.BindParameter(query, common.cstr(target_auth or _STR_(AUTH_USER)))
	else
		--id provided, Generate UPDATE query
		local params = v
		params["salt"] = v["pass"] --require password
		local UPDATE_USERS = common.gensql(params, {COLS_USER}, "users", "id")
	
		query = c.CreateQuery(common.cstr(UPDATE_USERS), request, 0)
		
		c.BindParameter(query, common.cstr(user))
		c.BindParameter(query, common.cstr(pass))
		c.BindParameter(query, common.cstr(salt))
		c.BindParameter(query, common.cstr(target_auth))
		c.BindParameter(query, common.cstr(id))
	end

	c.SelectQuery(db, query)
	if query.lastrowid > 0 or query.rows_affected > 0 then
		return MESSAGE("ADDUSER_SUCCESS")
	else
		return MESSAGE("ADDUSER_FAILED")
	end
end

function clearCache(vars, session)
	c.ClearCache(app, requests)
	return MESSAGE("CACHE_CLEARED")
end

function handleTemplate(template, page, session, user, auth)
	--[[TODO: Place template logic here. Use calls similar to the following:
		c.Template_ShowGlobalSection(template, common.cstr("NOT_LOGGED_IN"))
		c.Template_ShowGlobalSection(template, common.cstr("LOGGED_IN")) --]]
end

handlers = {
--Login
	login = {AUTH_GUEST, login},
--Logout
	logout = {AUTH_USER, logout},
--Clear any cached data.
	clearCache = {AUTH_USER, clearCache},
--Render a content template.
	handleTemplate = {AUTH_GUEST, handleTemplate},
--Update the current user (AUTH_USER) or a specific user.
	updateUser = {AUTH_USER, updateUser},
}

page_security = {

}

return function() return handlers, page_security end

