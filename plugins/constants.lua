--Create database queries.
@def SYSTEM_SCHEMA 'CREATE TABLE IF NOT EXISTS "system" ("key" VARCHAR(10) PRIMARY KEY NOT NULL, "value" VARCHAR(100));'
@def PRAGMA_FOREIGN "PRAGMA foreign_keys = ON;"

--Basic constants
@def NUM_EVENTS 2048
@def BEGIN_TRANSACTION "BEGIN;"
@def COMMIT_TRANSACTION "COMMIT;"
@def DATABASE_TYPE_SQLITE 0
@def DATABASE_TYPE_MYSQL 1
@def RESPONSE_TYPE_DATA 0
@def RESPONSE_TYPE_MESSAGE 1
@def REQUEST_NUM_ELEMENTS 6
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
@def WEBAPP_PARAM_REQUESTSIZE 5

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

ffi = require("ffi")
ffi.cdef [[
typedef struct {
  const char* data;
  int32_t len;
  int allocated;
} webapp_str_t;

typedef struct {
  int32_t co;
  webapp_str_t cookies;
  webapp_str_t host;
  webapp_str_t uri;
  webapp_str_t user_agent;
  webapp_str_t request_body;
  int method;
  void* session;
} LuaRequest;

//Request handling
typedef struct {
  webapp_str_t headers_buf;
  void* socket;
  LuaRequest* r;
} Request;


void SetParamInt(unsigned int param, int value);
int GetParamInt(unsigned int param);
void ClearCache(void* worker);
void Shutdown(void* worker);
void DestroySession(void* session);
webapp_str_t* CompileScript(const char* script);

/*
FinishRequest finalises and cleans up a request object
@param Request the request object
*/
void FinishRequest(Request*);

/*
GetNextRequest pops the next request from the request queue (or blocks
when there are none available).
@param worker the request worker
@returns the request object, or nil if the worker should abort.
*/
Request* GetNextRequest(void* worker);

/*
WriteData writes chunks of data to a request's socket.
@param socket the socket object to write to
@param data the data chunk to write
*/
void WriteData(void* socket, webapp_str_t* data);

/*
ReadData reads data from a socket asynchronously.
Make sure to yield the current coroutine in order to prevent blocking.
@param socket the socket object to read from
@param worker the worker queue
@param r the request
@param bytes the amount of bytes to read
@param timeout the amount of time, in seconds, to wait before aborting.
@return the allocated buffer. Length set to 0 if timeout occurs.
*/
webapp_str_t* ReadData(void* socket, void* worker, Request* r,
			  int bytes, int timeout);

//Session Functions
webapp_str_t* GetSessionValue(void*, webapp_str_t* key);
int SetSessionValue(void*, webapp_str_t* key, webapp_str_t* val);

/*
GetCookieSession creates a new session object for the existing session
identified by the cookie string (which must contain a sessionid= cookie.
@param worker the request worker
@param r the request object
@param cookies the cookies string
*/
void* GetCookieSession(void* worker, Request* r, webapp_str_t* cookies);
void* GetSession(void*, Request*, webapp_str_t* session_id);
void* NewSession(void*, Request*, webapp_str_t* pri, webapp_str_t* sec);
webapp_str_t* GetSessionID(void*);

//Template Functions
webapp_str_t* Template_Render(void*, webapp_str_t*, Request*);
void* Template_Get(void*, webapp_str_t*);
void Template_Load(webapp_str_t* page);
void Template_Include(webapp_str_t* name, webapp_str_t* file);
void Template_ShowGlobalSection(void*, webapp_str_t*);
void Template_SetGlobalValue(void*, webapp_str_t* key, webapp_str_t* value);
void Template_SetValue(void*, webapp_str_t* key, webapp_str_t* value);
void Template_SetIntValue(void*, webapp_str_t* key, long value);
void Template_Clear(void*);

//Database Functions
typedef struct {
  int nError; 
  size_t db_type;
} Database;
typedef struct {
  int status; 
  int64_t lastrowid;
  int column_count;
  webapp_str_t* row;
  webapp_str_t* desc;
  int need_desc;
  int have_desc;
  int rows_affected;
} Query;

/*
CreateDatabase creates a new database object
@returns the created Database object.
*/
Database* CreateDatabase();

/*
ConnectDatabase connects a database object to a provider.
Currently supported: SQLite, MySQL.
@param db the database object
@param database_type the type of provider
@param host the host (or file location, for SQLite) of the provider
@param username the username for the provider
@param password the password of the provider
@param database the database to use (for multi-database systems)
@returns the status of database connection success
*/
int ConnectDatabase(Database* db, int database_type, const char* host, 
	const char* username, const char* password, const char* database);

/*
DestroyDatabase destroys a database object
@param db the database object to destroy
*/
void DestroyDatabase(Database* db);

/*
GetDatabase returns a database given the specified id.
@param id the database id
@returns the database object, or null if non existent
*/
Database* GetDatabase(size_t id);

/*
CreateQuery creates a query object.
@param qry_str the query string. Can be set later using SetQuery.
@param r the request object
@param db the database object
@param desc whether to populate the row description fields
@returns the query object.
*/
Query* CreateQuery(webapp_str_t* qry_str, 
				   Request* r, Database* db, int desc);

/*
SetQuery sets the string of a query object.
@param query the query object to set
@param qry_str the new query string
*/
void SetQuery(Query* query, webapp_str_t* qry_str);

/*
BindParameter binds a parameter to a query
@param query the query object
@param the parameter to bind
*/
void BindParameter(Query* query, webapp_str_t* param);

/*
SelectQuery executes a query, storing any values returned in the query
object.
@param query the query object
@returns the query status (query.status) after execution.
*/
int SelectQuery(Query* query);

/*
ExecString executes a string, returning the queries last row id.
@param db the database object
@param qry_str the query string to execute
*/
int64_t ExecString(Database* db, webapp_str_t* qry_str);

typedef struct {
  webapp_str_t name;
  webapp_str_t flags;
  webapp_str_t buffer;
} File;

File* File_Open(webapp_str_t* filename, webapp_str_t* mode);
void File_Close(File* f);
int16_t File_Read(File* f, int16_t n_bytes);
void File_Write(File* f, webapp_str_t* buf);
int64_t File_Size(File* f);

typedef struct {
  char path[4096];
  int has_next;
  int n_files;
  void* _files;
  void* _h;
  void* _f;
  void* _d;
  void* _e;
} Directory;

typedef struct {
  char path[4096];
  char name[256];
  int is_dir;
  int is_reg;
  void* _s;
} DirFile;

int tinydir_open(Directory*, const char* path);
int tinydir_open_sorted(Directory*, const char* path);
void tinydir_close(Directory*);
int tinydir_next(Directory*);
int tinydir_readfile(Directory*, DirFile*);
]]
c = ffi.C

function compile(file)
	local bc_raw = c.CompileScript(file)
	local bc = ffi.string(bc_raw.data, tonumber(bc_raw.len))
	return loadstring(bc)()
end
