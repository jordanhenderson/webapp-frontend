-- core/process.lua
-- Main instance handling/request processing script.

local ffi = require("ffi")
ffi.cdef[[
//Struct definitions
typedef struct {
  const char* data;
  int32_t len;
  int allocated;
} webapp_str_t;
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
typedef struct { 
  int method; 
  webapp_str_t uri; 
  webapp_str_t host;
  webapp_str_t user_agent;
  webapp_str_t cookies;
  webapp_str_t request_body;
} Request;
typedef struct {
  int nError; 
  size_t db_type;
} Database;

//Session Functions
webapp_str_t* GetSessionValue(void*, webapp_str_t* key);
int SetSessionValue(void*, webapp_str_t* key, webapp_str_t* val);
void* GetSession(void*, Request*);
void* NewSession(void*, Request*);
webapp_str_t* GetSessionID(void*);

//Template Functions
webapp_str_t* Template_Render(void*, webapp_str_t*, Request*);
void* Template_Get(void*, webapp_str_t*);

//Request Functions
void FinishRequest(void* app, Request*);
Request* GetNextRequest(void* requests);
void WriteData(void* request, webapp_str_t* data);
void WriteHeader(void* request, int32_t bytes, 
	webapp_str_t* content_type, webapp_str_t* cookies, int8_t cache);

//Database Functions
Database* GetDatabase(void* app, size_t index);
Query* CreateQuery(webapp_str_t* in, Request*, Database*, int desc);
void SetQuery(Query* query, webapp_str_t* in);
void BindParameter(Query* query, webapp_str_t* in);
int SelectQuery(Query* query);
int64_t ExecString(void* db, webapp_str_t* in);

//Filesystem Functions
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
]]
c = ffi.C
db = c.GetDatabase(app, 0)

globals = {
}

handlers, page_security = load_handlers()

@include "plugins/constants.lua"

local common = require "common"
local time = require "time"

base_template = c.Template_Get(worker, nil)

function daystr(day)
	if day == 0 then
		return "Mon" 
	elseif day == 1 then
		return "Tue" 
	elseif day == 2 then
		return "Wed" 
	elseif day == 3 then
		return "Thu" 
	elseif day == 4 then
		return "Fri" 
	elseif day == 5 then
		return "Sat" 
	elseif day == 6 then
		return "Sun" 
	else
		return ""
	end
end

function monthstr(month)
	if month == 0 then
		return "Jan"
	elseif month == 1 then
		return "Feb"
	elseif month == 2 then
		return "Mar"
	elseif month == 3 then
		return "Apr"
	elseif month == 4 then
		return "May"
	elseif month == 5 then
		return "Jun"
	elseif month == 6 then
		return "Jul"
	elseif month == 7 then
		return "Aug"
	elseif month == 8 then
		return "Sep"
	elseif month == 9 then
		return "Oct"
	elseif month == 10 then
		return "Nov"
	elseif month == 11 then
		return "Dec"
	else
		return ""
	end
end

function gen_cookie(name, value, days)
	local t = time.nowutc()
	t:add_days(7)
	local year, m, d = t:ymd()
	local h, mins, s = t:hms()
	local day = daystr(t:weekday())
	local month = monthstr(m)
	local out = string.format("%s=%s; Expires=%s, %02i %s %i %02i:%02i:%02i GMT", 
		name, value, day, d, month, year, h, mins, s)
	return out
end

function getUser(session) 
	local userid = c.GetSessionValue(session, common.cstr("userid"))
	if userid ~= nil and userid.len > 0 then
		--Lookup user auth level.
		local query = c.CreateQuery(common.cstr(SELECT_USER), request, db, 0)
		c.BindParameter(query, userid)
		c.SelectQuery(query)
		if query.column_count > 0 and query.row ~= nil then
			return query.row
		end
	end
end

function getPage(uri_str, session, request)
	local response = ""
	local page = ""
	local uri = uri_str.data
	
	if (uri[0] == 47 --[[/]] and
		uri_str.len == 1)
		or (uri_str.len >= 2 and uri[1] == 63 --[[?]]) then
		page = "index"
	else
		local uristr = common.appstr(uri_str)
		local f = common.find_first_of(uristr, "?#&") - 1
		page = string.sub(uristr, math.min(2, string.len(uristr)), f)
	end
	
	local user = getUser(session)
	local auth = tonumber(user and common.appstr(user[@col(COLS_USER, "auth")]) or AUTH_GUEST) 
	if page_security[page] and auth < page_security[page] then
		page = "index"
	end
	
	local page_full = page .. ".html"
	if base_template ~= nil then
		-- Template process code.
		local handleTemplate = handlers.handleTemplate
		if handleTemplate ~= nil then
			local status, err = pcall(handleTemplate[2], base_template, page, session, user, auth)
			if not status then io.write(err) end
		end
		-- End template process code.
		local content = c.Template_Render(worker, common.cstr(page_full), request)
		
		if content then
			response = common.appstr(content)
		end
	end
	return response
end

function processAPI(params, session, request)
	local tmp_response = "{}"
	local func_str = params.t
	local func = handlers[type(func_str) == "string" and func_str]
	
	local user = getUser(session)
	local auth = tonumber(user and common.appstr(COL_USER("auth")) or AUTH_GUEST)
	if func ~= nil and auth >= func[1] then
		local ret, call_str = pcall(func[2], params, session, user, auth)
		if ret and call_str ~= nil then
			tmp_response = call_str
		else
			io.write(call_str)
			tmp_response = "{}"
		end
	elseif func ~= nil then
		--Not logged in. 
		tmp_response = MESSAGE("NO_AUTH")
	else
		--No matching handler.
		tmp_response = "{}"
	end
	
	return tmp_response
end

math.randomseed(os.time())


request = c.GetNextRequest(worker)
while request ~= nil do 
	local method = request.method
	globals.session = c.GetSession(worker, request)
	
	local response = ""
	local content_type = "text/html"
	local uri_len = tonumber(request.uri.len)
	local cache = 0
	if uri_len > 3
		and request.uri.data[1] == 97 -- a
		and request.uri.data[2] == 112 -- p
		and request.uri.data[3] == 105 -- i
		and request.uri.data[0] == 47 -- / (check last - just in case.)
	then
		content_type = "application/json"
		local ret, params = pcall(cjson.decode, common.appstr(request.request_body))
		response = ret and processAPI(params,globals.session,request) or "{}"
	elseif uri_len >= 1 then
		cache = 1
		response = getPage(request.uri, globals.session, request)
	end
	
	local cookie = ""

	if globals.session ~= nil then -- Session created?
		local session_id = common.appstr(c.GetSessionID(globals.session))
		cookie = gen_cookie("sessionid", session_id, 7)
	end
	
	c.WriteHeader(request, response:len(), 
		common.cstr(content_type), common.cstr(cookie, 1), cache)
	c.WriteData(request, common.cstr(response))
	c.FinishRequest(app, request)

	request = c.GetNextRequest(worker)
end
