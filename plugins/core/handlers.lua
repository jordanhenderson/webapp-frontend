@include 'plugins/constants.lua'
math.randomseed(os.time())

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

function dump_query(query)
	local hasdesc = false
	data = {}
	desc = {}
	if c.Query_Select(query) == DATABASE_QUERY_STARTED then
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
		until c.Query_Select(query) == DATABASE_QUERY_FINISHED
	end
	return data
end

function login(v)
	local password = v.pass
	local query = common.query_create(db, SELECT_USER_LOGIN)
	c.Query_Bind(query, common.cstr(v.user))
	local res = c.Query_Select(query) 
	
	if res == DATABASE_QUERY_STARTED 
		and query.column_count == @icol(COLS_USER) then
		local user = query.row
		local userid = tonumber(common.appstr(user[0]))
		--Check password.
		local salt = common.appstr(COL_USER("salt"))
		local storedpw = common.appstr(COL_USER("pass"))
		local hashedpw = ""
		if password ~= nil then hashedpw = hashPassword(password, salt) end
		if userid ~= nil and userid > 0 and hashedpw == storedpw then	
			local uid = common.appstr(r.host) .. common.appstr(r.user_agent)
			r.session = c.Session_New(worker, common.cstr(uid))
			c.Session_SetValue(r.session, common.cstr("userid"), user[0])
			return _MESSAGE("LOGIN_SUCCESS", 1)
		else
			return MESSAGE("LOGIN_FAILED")
		end
	else
		return MESSAGE("LOGIN_FAILED") -- no matching user (email)
	end
end

function logout(vars)
	c.Session_Destroy(r.session)
	r.session = nil
	return _MESSAGE("LOGOUT_SUCCESS", 1)
end

function updateUser(v, user, auth)
	--Input variables.
	local id = v.id
	local target_user = v.user
	local password = v.pass
	local target_auth = v.auth
	local query = common.query_create(db, nil)
	
	--Restrict auth level changes.
	if auth == AUTH_USER and target_auth then
		target_auth = _STR_(AUTH_USER) --Users cannot change auth level.
	end
	
	--Calculate password and hash if provided.
	local pass, salt = hashPassword(password)
	local query_type
	
	--If ID has been provided, insert new user, otherwise update existing.
	if id == nil then query_type = QUERY_TYPE_INSERT
	else query_type = QUERY_TYPE_UPDATE end

	--Generate the appropriate sql.
	local sql = common.gensql(query, query_type, "users", "id", {COLS_USER}, 
		target_user, pass, salt, target_auth)

	--[[ Apply appropriate permissions ]]--
	--Users cannot modify other users, default ID to modify is current user.
	if auth == AUTH_USER or ((id == nil or id:len() == 0) 
		and (target_user == nil or password == nil)) then
		c.Query_Bind(query, user[0])
	elseif id ~= nil then
		--User is admin, ID provided. Update existing user.
		c.Query_Bind(query, common.cstr(id))
	end
	
	--Set then execute the query.
	c.Query_Set(query, common.cstr(sql))
	c.Query_Select(query)
	local lastrowid = tonumber(query.lastrowid)
	if lastrowid > 0 or query.rows_affected > 0 then
		return cjson.encode({msg="UPDATEUSER_SUCCESS", 
							id = id or lastrowid, 
							type=RESPONSE_TYPE_MESSAGE})
	else
		return MESSAGE("UPDATEUSER_FAILED")
	end
end

updateUser({user="admin",pass="admin",auth=_STR_(AUTH_ADMIN)}, 
			nil, nil, AUTH_ADMIN)

function clearCache(vars)
	c.Worker_ClearCache(worker)
	return MESSAGE("CACHE_CLEARED")
end

function shutdown(vars)
	c.Worker_Shutdown(worker)
	return MESSAGE("SHUTTING_DOWN")
end

local handlers = {
--Login
	login = {AUTH_GUEST, login},
--Logout
	logout = {AUTH_USER, logout},
--Clear any cached data.
	clearCache = {AUTH_ADMIN, clearCache},
--Shut down the server.
	shutdown = {AUTH_ADMIN, shutdown},
--Update the current user (AUTH_USER) or a specific user.
	updateUser = {AUTH_USER, updateUser},
}

return handlers

