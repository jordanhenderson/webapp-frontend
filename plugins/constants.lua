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
@def SERVER_PARAM_PORT 0
@def SERVER_PARAM_ABORTED 1
@def SERVER_PARAM_TPLCACHE 2
@def SERVER_PARAM_LEVELDB 3
@def SERVER_PARAM_THREADS 4
@def SERVER_PARAM_REQUESTSIZE 5
@def SERVER_PARAM_CLIENTSOCKETS 6
@def SERVER_PARAM_STRINGS 6
@def SERVER_PARAM_TEMPLATES 7
@def SERVER_PARAM_STRINGS 8

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
  int8_t status;
  /* ... socket ... */
} LuaSocket;

typedef struct {
  webapp_str_t id;
  /* ... session ... */
} Session;

typedef struct {
  int32_t co;
  webapp_str_t cookies;
  webapp_str_t host;
  webapp_str_t uri;
  webapp_str_t user_agent;
  webapp_str_t request_body;
  int method;
  Session* session;
} LuaRequest;

//Request handling
typedef struct {
  webapp_str_t headers_buf;
  LuaSocket* socket;
  LuaRequest* r;
  /* ... request ... */
} Request;

void String_Destroy(webapp_str_t*);
void Worker_ClearCache(void* worker);
void Worker_Shutdown(void* worker);
webapp_str_t* Script_Compile(const char* script);
void Param_Set(unsigned int param, int value);
int Param_Get(unsigned int param);

/*
Request_Finish finalises and cleans up a request object
@param Request the request object
*/
void Request_Finish(Request*);

/*
Request_GetNext pops the next request from the request queue (or blocks
when there are none available).
@param worker the request worker
@returns the request object, or nil if the worker should abort.
*/
Request* Request_GetNext(void* worker);

/*
Request_Queue pushes the provided request back onto the request queue.
@param worker the request worker
@param request the request
*/
void Request_Queue(void* worker, Request*);

/*
Socket_DataAvailable returns the amount of bytes available to read() from the
socket.
@param socket the socket object.
@returns the size in bytes that is ready to be read from the socket.
*/
int Socket_DataAvailable(LuaSocket* socket);

/*
Socket_Connect creates and returns a socket object.
The socket will be resolved then connected asynchronously.
Yield after calling this function.
@param worker the request worker
@param r the request
@param addr the destination address to connect to.
@param port the destination port to connect to.
@returns a Socket object. Must be destroyed using Socket_Destroy.
*/
LuaSocket* Socket_Connect(void* worker, Request* r, webapp_str_t* addr, 
					  webapp_str_t* port);
					  
/*
Socket_Destroy destroys a socket object.
@param socket the socket object to destroy.
*/
void Socket_Destroy(LuaSocket* socket);

/*
Socket_Write writes chunks of data to a request's socket.
@param socket the socket object to write to
@param data the data chunk to write
*/
void Socket_Write(LuaSocket* socket, webapp_str_t* data);

/*
Socket_Read reads data from a socket asynchronously.
Make sure to yield the current coroutine in order to prevent blocking.
@param socket the socket object to read from
@param worker the worker queue
@param r the request
@param bytes the amount of bytes to read
@param timeout the amount of time, in seconds, to wait before aborting.
@return the allocated buffer. Length set to 0 if timeout occurs.
*/
webapp_str_t* Socket_Read(LuaSocket* socket, void* worker, Request* r,
			  int bytes, int timeout);

//Session Functions
webapp_str_t* Session_GetValue(Session*, webapp_str_t* key);
void Session_SetValue(Session*, webapp_str_t* key, webapp_str_t* val);

/*
Session_GetFromCookies creates a new session object for the existing session
identified by the cookie string (which must contain a sessionid= cookie.
@param worker the request worker
@param r the request object
@param cookies the cookies string
*/
Session* Session_GetFromCookies(void* worker, webapp_str_t* cookies);
Session* Session_Get(void* worker, webapp_str_t* id);
Session* Session_New(void* worker, webapp_str_t* uid);
void Session_Destroy(Session* session);

//Template Functions
webapp_str_t* Template_Render(void*, webapp_str_t*);
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
  int db_type;
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
  webapp_str_t dbq;
  webapp_str_t err;
} Query;

/*
Database_Create creates a new database object
@returns the created Database object.
*/
Database* Database_Create();

/*
Database_Connect connects a database object to a provider.
Currently supported: SQLite, MySQL.
@param db the database object
@param database_type the type of provider
@param host the host (or file location, for SQLite) of the provider
@param username the username for the provider
@param password the password of the provider
@param database the database to use (for multi-database systems)
@returns the status of database connection success
*/
int Database_Connect(Database* db, int database_type, const char* host, 
	const char* username, const char* password, const char* database);

/*
Database_Destroy destroys a database object
@param db the database object to destroy
*/
void Database_Destroy(Database* db);

/*
Database_Get returns a database given the specified id.
@param id the database id
@returns the database object, or null if non existent
*/
Database* Database_Get(size_t id);

/*
Query_Create creates a query object.
Note: You should use ffi.gc to automatically destroy the query using 
Query_Destroy.
@param qry_str the query string. Can be set later using Query_Set.
@param db the database object
@returns the query object.
*/
Query* Query_Create(Database* db, webapp_str_t* qry_str);

/*
Query_Destroy destroys a query object.
@param qry the query object to destroy.
*/
void Query_Destroy(Query* qry);

/*
Query_Set sets the string of a query object.
@param query the query object to set
@param qry_str the new query string
*/
void Query_Set(Query* query, webapp_str_t* qry_str);

/*
Query_Bind binds a parameter to a query
@param query the query object
@param the parameter to bind
*/
void Query_Bind(Query* query, webapp_str_t* param);

/*
Query_Select executes a query, storing any values returned in the query
object.
@param query the query object
@returns the query status (query.status) after execution.
*/
int Query_Select(Query* query);

/*
Database_Exec executes a string, returning the queries last row id.
@param db the database object
@param qry_str the query string to execute
*/
int64_t Database_Exec(Database* db, webapp_str_t* qry_str);

typedef struct {
  webapp_str_t name;
  webapp_str_t flags;
  webapp_str_t buffer;
} File;

File* File_Open(webapp_str_t* filename, webapp_str_t* mode);
void File_Close(File* f);
void File_Destroy(File* f);
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
	local bc_raw = c.Script_Compile(file)
	local bc = ffi.string(bc_raw.data, tonumber(bc_raw.len))
	return loadstring(bc)()
end
