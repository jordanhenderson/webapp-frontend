--Create database queries.
@def (CREATE_DATABASE(db_type) {
'BEGIN;',
SQL_SESSION(db_type),
@join('CREATE TABLE IF NOT EXISTS "users" ("id" INTEGER PRIMARY KEY NOT NULL, "user" VARCHAR(20) NOT NULL, "pass" CHAR(64) NOT NULL, "salt" CHAR(6) NOT NULL, "auth" INTEGER NOT NULL DEFAULT ',AUTH_USER,',') .. SQL_UNIQUE(db_type, "user") .. ');',
'COMMIT;'
})

@def PRAGMA_FOREIGN "PRAGMA foreign_keys = ON;"

--Basic constants
@def DATABASE_TYPE_SQLITE 0
@def DATABASE_TYPE_MYSQL 1
@def RESPONSE_TYPE_DATA 0
@def RESPONSE_TYPE_MESSAGE 1
@def AUTH_GUEST 0
@def AUTH_USER 1
@def AUTH_ADMIN 2
@def DATABASE_QUERY_INIT 0
@def DATABASE_QUERY_STARTED 1
@def DATABASE_QUERY_FINISHED 2
@def WEBAPP_PARAM_PORT 0
@def WEBAPP_PARAM_ABORTED 1
@def WEBAPP_PARAM_BGQUEUE 2

@def QUERY_TYPE_INSERT 0
@def QUERY_TYPE_UPDATE 1
--JSON generator functions
@def _MESSAGE(msg, reload) '{"msg":"' .. msg .. '"' .. (reload and ', "reload":1' or '') .. @join(', "type":', RESPONSE_TYPE_MESSAGE, '}')
@def MESSAGE(msg) _MESSAGE(msg, nil)

--Column definitions. Use _PUBLIC for fields that can be changed using update_.
@def COLS_USER "user", "pass", "salt", "auth"
@def COLS_USER_LOGIN "id", "pass", "salt"

--Filtered select statements
@def SELECT_USER_LOGIN @join("SELECT ", COLS_USER_LOGIN, " FROM users WHERE user = ?;")
@def SELECT_USER @join("SELECT ", COLS_USER, " FROM users WHERE id = ?;")

--HTTP Header macros
@def END_HEADER "\r\n"
@def HTML_HEADER @join("Content-type: text/html", END_HEADER)
@def HTTP_200 @join("HTTP/1.1 200 OK", END_HEADER)
@def HTTP_404 @join("HTTP/1.1 404 Not Found", END_HEADER)
@def JSON_HEADER @join("Content-type: application/json", END_HEADER)
@def CONTENT_LEN_HEADER(len) "Content-Length: " .. len .. END_HEADER
@def DISABLE_CACHE_HEADER @join("Cache-Control: no-cache, no-store, must-revalidate", END_HEADER, "Pragma: no-cache", END_HEADER, "Expires: 0", END_HEADER)

function SQL_CONCAT(db_type, ...)
	local n = select("#", ...)
	if n < 1 then
		return ""
	elseif n == 1 then
		return select(1, ...)
	end
	
	local out = ""
	local op = ""
	
	if db_type == DATABASE_TYPE_SQLITE then
		out = "(" 
		op = " || "
	elseif db_type == DATABASE_TYPE_MYSQL then
		out = "CONCAT("
		op = ","
	end
	local p = 1
	for i = 1, n - 1 do 
		out = out .. select(i, ...) .. op
		p = p + 1
	end
	
	out = out .. select(p, ...) .. ")"
	return out
end

function SQL_SESSION(db_type)
	if db_type == DATABASE_TYPE_SQLITE then
		return ""
	elseif db_type == DATABASE_TYPE_MYSQL then
		return "SET SESSION sql_mode = 'ANSI_QUOTES';"
	end
	return ""
end

function SQL_UNIQUE(db_type, row)
	if db_type == DATABASE_TYPE_SQLITE then
		return "UNIQUE(" .. row ..") ON CONFLICT IGNORE"
	elseif db_type == DATABASE_TYPE_MYSQL then
		return "UNIQUE(" .. row ..")"
	end
	return ""
end
