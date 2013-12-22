--Create database queries.
@def CREATE_DATABASE "BEGIN; \
CREATE TABLE 'users' ('id' INTEGER PRIMARY KEY  NOT NULL ,'user' TEXT NOT NULL,'pass' TEXT NOT NULL ,'salt' TEXT NOT NULL, 'auth' INTEGER NOT NULL); \
COMMIT;"

@def PRAGMA_FOREIGN "PRAGMA foreign_keys = ON;"

--Basic constants
@def DATABASE_TYPE_SQLITE 0
@def DATABASE_TYPE_MYSQL 1
@def RESPONSE_TYPE_DATA 0
@def RESPONSE_TYPE_MESSAGE 1
@def AUTH_USER 1
@def AUTH_GUEST 0
@def AUTH_ADMIN 2
@def DATABASE_QUERY_INIT 0
@def DATABASE_QUERY_STARTED 1
@def DATABASE_QUERY_FINISHED 2
@def WEBAPP_PARAM_PORT 0

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
@def ADD_USER @gensql(COLS_USER, "users")

--HTTP Header macros
@def END_HEADER "\r\n"
@def HTML_HEADER @join("Content-type: text/html", END_HEADER)
@def HTTP_200 @join("HTTP/1.1 200 OK", END_HEADER)
@def HTTP_404 @join("HTTP/1.1 404 Not Found", END_HEADER)
@def JSON_HEADER @join("Content-type: application/json", END_HEADER)
@def CONTENT_LEN_HEADER(len) "Content-Length: " .. len .. END_HEADER
@def DISABLE_CACHE_HEADER @join("Cache-Control: no-cache, no-store, must-revalidate", END_HEADER, "Pragma: no-cache", END_HEADER, "Expires: 0", END_HEADER)
