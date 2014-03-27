--Create database queries.
@def SYSTEM_SCHEMA 'CREATE TABLE IF NOT EXISTS "system" ("key" VARCHAR(10) PRIMARY KEY NOT NULL, "value" VARCHAR(100));'
@def PRAGMA_FOREIGN "PRAGMA foreign_keys = ON;"

--Basic constants
@def BEGIN_TRANSACTION "BEGIN;"
@def COMMIT_TRANSACTION "COMMIT;"
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
@def WEBAPP_PARAM_TPLCACHE 2
@def WEBAPP_PARAM_LEVELDB 3
@def WEBAPP_PARAM_THREADS 4

@def QUERY_TYPE_INSERT 0
@def QUERY_TYPE_UPDATE 1
--JSON generator functions
@def _MESSAGE(msg, reload) '{"msg":"' .. msg .. '"' .. (reload and ', "reload":1' or '') .. @join(', "type":', RESPONSE_TYPE_MESSAGE, '}')
@def MESSAGE(msg) _MESSAGE(msg, nil)

--Column definitions. Use _PUBLIC for fields that can be changed using update_.
@def COLS_USER "user", "pass", "salt", "auth"
@def COL_USER(x) user[@icol(COLS_USER, x)]

--Filtered select statements
@def SELECT_FIELD(field, table, cond) @join("SELECT ", field, " FROM ", table, " WHERE ", cond, " = ?;")
@def INSERT_FIELD(table, fields, values) @join ("INSERT INTO ", table, " (", fields, ") VALUES (", values, ");")
@def SELECT_USER_LOGIN @join("SELECT id, ", COLS_USER, " FROM users WHERE user = ?;")
@def SELECT_USER @join("SELECT id, ", COLS_USER, " FROM users WHERE id = ?;")

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

APP_SCHEMA = {
@join('CREATE TABLE IF NOT EXISTS "users" ("id" INTEGER PRIMARY KEY NOT NULL, "user" VARCHAR(20) NOT NULL, "pass" CHAR(64) NOT NULL, "salt" CHAR(6) NOT NULL, "auth" INTEGER NOT NULL DEFAULT ',AUTH_USER,', UNIQUE (user) ON CONFLICT IGNORE);'),
}
