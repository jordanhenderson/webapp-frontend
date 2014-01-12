-- core/process.lua
-- Main instance handling/request processing script.

local ffi = require("ffi")
ffi.cdef[[
typedef struct { const char* data; long long len; } webapp_str_t;
typedef struct { 
  int status; 
  long long lastrowid; 
  int column_count; 
  webapp_str_t** row; 
  webapp_str_t** desc; 
  int need_desc; 
  int have_desc; 
  int rows_affected;
} Query;
typedef struct 
{ void* socket; 
  void* buf;
  void* headers;
  int recv_amount; 
  int length; 
  int method; 
  webapp_str_t uri; 
  webapp_str_t host;
  webapp_str_t user_agent;
  webapp_str_t cookies;
  webapp_str_t request_body;
} Request;
typedef struct {int nError; size_t db_type;} Database;
int GetSessionValue(void*, webapp_str_t* key, webapp_str_t* out);
int SetSessionValue(void*, webapp_str_t* key, webapp_str_t* val);
void* GetSession(void*, webapp_str_t*);
void* NewSession(void*, Request*);
int GetSessionID(void*, webapp_str_t* out);

void RenderTemplate(void*, void*, webapp_str_t*, Request*, webapp_str_t* out);
void FinishRequest(Request*);
void* GetTemplate(void*);
Request* GetNextRequest(void* requests);
Database* GetDatabase(void* app, size_t index);
void WriteData(void* socket, webapp_str_t* data);
Query* CreateQuery(webapp_str_t* in, Request*, Database*, int desc);
void SetQuery(Query* query, webapp_str_t* in);
void BindParameter(Query* query, webapp_str_t* in);
int SelectQuery(Query* query);
]]
c = ffi.C
db = c.GetDatabase(app, 0)

handlers, page_security = load_handlers()
common = require "common"
time = require "time"

@include "plugins/constants.lua"

function daystr(day)
	if day == 1 then
		return "Mon" 
	elseif day == 2 then
		return "Tue" 
	elseif day == 3 then
		return "Wed" 
	elseif day == 4 then
		return "Thu" 
	elseif day == 5 then
		return "Fri" 
	elseif day == 6 then
		return "Sat" 
	elseif day == 7 then
		return "Sun" 
	else
		return ""
	end
end

function monthstr(month)
	if month == 1 then
		return "Jan"
	elseif month == 2 then
		return "Feb"
	elseif month == 3 then
		return "Mar"
	elseif month == 4 then
		return "Apr"
	elseif month == 5 then
		return "May"
	elseif month == 6 then
		return "Jun"
	elseif month == 7 then
		return "Jul"
	elseif month == 8 then
		return "Aug"
	elseif month == 9 then
		return "Sep"
	elseif month == 10 then
		return "Oct"
	elseif month == 11 then
		return "Nov"
	elseif month == 12 then
		return "Dec"
	else
		return ""
	end
end

function gen_cookie(name, value, days)
	local t = time.nowutc()
	t = t + time.days(days)
	local year, m, d = t:ymd()
	local h, mins, s = t:period():parts()
	local day = daystr(t:weekday())
	local month = monthstr(m)
	local out = string.format("Set-Cookie: %s=%s; Expires=%s, %02i %s %i %02i:%02i:%02i GMT \r\n", 
		name, value, day, d, month, year, h, mins, s)
	return out
end

function find_first_of(str, chars)
	local foundpos = string.len(str) 
	for i = 1, string.len(chars) do
		local c = string.sub(chars, i, i)
		local f = string.find(str, c)
		if f and f <= foundpos then
			foundpos = f - 1
		end
		
	end
	return foundpos
end

function get_cookie_val(cookies, key)
	if cookies.data == nil then
		return nil
	else
		cookies = common.appstr(cookies)
	end

	local m = cookies:gmatch("(%w+)=(%w+)")
	for i,k in m do
		if i == key then
			return k
		end
	end
	return nil
end

function getUser(session) 
	 --use wstr[2] to keep userid for API functions
	if c.GetSessionValue(session, common.cstr("userid"), common.wstr[2]) ~= 0 then
		--Lookup user auth level.
		local query = c.CreateQuery(common.cstr(SELECT_USER), request, db, 0)
		c.BindParameter(query, common.wstr[2]) --use wstr[2]
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
	local uristr = common.appstr(uri_str)
	if uri[0] == 47 --[[/]] and (uri[1] == 0 or uri[1] == 63 --[[?]]) then
		page = "index"
	else
		local f = find_first_of(uristr, "?#&")
		page = string.sub(uristr, math.min(2, string.len(uristr)), f)
	end
	
	local user = getUser(session)
	local auth = tonumber(user and common.appstr(user[@col(COLS_USER, "auth")]) or AUTH_GUEST) 
	if page_security[page] and auth < page_security[page] then
		page = "index"
	end
	
	local page_full = page .. ".html"
	
	local template = c.GetTemplate(app)
	if template ~= nil then
		-- Template process code.
		local handleTemplate = handlers.handleTemplate
		if handleTemplate ~= nil then
			local status, err = pcall(handleTemplate[2], template, page, session, user, auth)
			if not status then print(err) end
		end
		-- End template process code.
		c.RenderTemplate(app, template, common.cstr(page_full), request, common.wstr)
		local content = common.appstr()
		if content then
			response = HTML_HEADER .. CONTENT_LEN_HEADER(string.len(content)) .. END_HEADER .. content
		end
	end
	return response
end

function processAPI(params_str, session, request)
	local tmp_response = "{}"
	local func_str = common.get_function(params_str)
	local func = handlers[func_str]

	local user = getUser(session)
	local auth = tonumber(user and common.appstr(user[@col(COLS_USER, "auth")]) or AUTH_GUEST)
	if func ~= nil and auth >= func[1] then
		local ret, call_str = pcall(func[2], params_str, session, user, auth)
		if ret and call_str ~= nil then
			tmp_response = call_str
		else
			print(call_str)
			tmp_response = "{}"
		end
	elseif func ~= nil then
		--Not logged in. 
		tmp_response = MESSAGE("NO_AUTH")
	else
		--No matching handler.
		tmp_response = "{}"
	end
	
	return JSON_HEADER .. CONTENT_LEN_HEADER(string.len(tmp_response)) .. END_HEADER .. tmp_response
end

math.randomseed(os.time())

request = c.GetNextRequest(requests)

while request ~= nil do 
	local method = request.method
	local cookies = request.cookies
	
	local sessionid = common.cstr(get_cookie_val(cookies, "sessionid"))
	local session
	
	if sessionid ~= nil then
		session = c.GetSession(sessions, sessionid)

	end
	--Create final with two spaces (enough space for the length integer stored by the backend.).
	local final = "  " 
	local cookie = ""
	if session == nil then
		-- Create a new session. Needs refinement to prevent spamming.
		session = c.NewSession(sessions, request)
		if session ~= nil then -- Session created?
			local newsession = c.GetSessionID(session, common.wstr)
			cookie = gen_cookie("sessionid", common.appstr(), 7)
		end
	end
	
	local response = ""
	local uri_len = tonumber(request.uri.len)
	if uri_len > 3
		and request.uri.data[1] == 97 -- a
		and request.uri.data[2] == 112 -- p
		and request.uri.data[3] == 105 -- i
		and request.uri.data[0] == 47 -- / (check last - just in case.)
	then
		if method == 2 and uri_len > 6 then 
			local uri = common.wstr
			uri.data = request.uri.data + 5
			uri.len = uri_len - 5
			uri = common.appstr()
			response = processAPI(uri, session, request)
		elseif method == 8 then
			local params = common.appstr(request.request_body)
			response = processAPI(params, session, request)
		end
	elseif uri_len >= 1 then
		response = getPage(request.uri, session, request)
	end
	
	if string.len(response) > 0 then
		final = final .. HTTP_200 .. cookie .. response
		else
		final = final .. HTTP_404 .. cookie .. HTML_HEADER .. CONTENT_LEN_HEADER(0) .. END_HEADER
	end

	c.WriteData(request.socket, common.cstr(final))
	c.FinishRequest(request)

	request = c.GetNextRequest(requests)
end
