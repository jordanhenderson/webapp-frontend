--Create database queries.
@def (CREATE_DATABASE(db_type) {
"BEGIN;",
"CREATE TABLE `users` (`id` INTEGER PRIMARY KEY NOT NULL, `user` TEXT NOT NULL, `pass` TEXT NOT NULL, `salt` TEXT NOT NULL, `auth` INTEGER NOT NULL, UNIQUE(`user`) ON CONFLICT IGNORE);",
"COMMIT;"
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

@def QUERY_TYPE_INSERT 0
@def QUERY_TYPE_UPDATE 1
--JSON generator functions
@def _MESSAGE(msg, reload) '{"data":[{"msg":"' .. msg .. '"' .. (reload and ', "reload":1' or '') .. @join('}], "type":', RESPONSE_TYPE_MESSAGE, '}')
@def MESSAGE(msg) _MESSAGE(msg, nil)

--Column definitions. Use _PUBLIC for fields that can be changed using update_.
@def COLS_USER "user", "pass", "salt", "auth"
@def COLS_USER_LOGIN "id", "pass", "salt"

--Filtered select statements
@def SELECT_USER_LOGIN @join("SELECT ", COLS_USER_LOGIN, " FROM users WHERE user = ?;")
@def SELECT_USER @join("SELECT ", COLS_USER, " FROM users WHERE id = ?;")

--Insert SQL statements.

--HTTP Header macros
@def END_HEADER "\r\n"
@def HTML_HEADER @join("Content-type: text/html", END_HEADER)
@def HTTP_200 @join("HTTP/1.1 200 OK", END_HEADER)
@def HTTP_404 @join("HTTP/1.1 404 Not Found", END_HEADER)
@def JSON_HEADER @join("Content-type: application/json", END_HEADER)
@def CONTENT_LEN_HEADER(len) "Content-Length: " .. len .. END_HEADER
@def DISABLE_CACHE_HEADER @join("Cache-Control: no-cache, no-store, must-revalidate", END_HEADER, "Pragma: no-cache", END_HEADER, "Expires: 0", END_HEADER)

--SQL compatibility functions. Produces correct SQL depending on in-use engine.
function SQL_CURRENTDATE(db_type)
	if db_type == DATABASE_TYPE_SQLITE then
		return "date('now')"
	elseif db_type == DATABASE_TYPE_MYSQL then
		return "CURDATE()"
	end
end

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
	local p = 0
	for i = 1, n - 1 do 
		out = out .. select(n, ...) .. op
		p = p + 1
	end
	
	out = out .. select(p, ...) .. ")"
	return out
end