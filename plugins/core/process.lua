-- core/process.lua
-- Main instance handling/request processing script.
@include 'plugins/constants.lua'

--handlers: Function handlers for API calls.
--page_security: Apply permissions to content pages
common = 					compile("plugins/common.lua")
local handlers, page_security = 	compile("plugins/core/handlers.lua")

--Get the application level database. 
local db = c.GetDatabase(0)

--base_template: the base page template.
local base_template = c.Template_Get(worker, nil)

local time = require "time"
local mp = require "MessagePack"

--The global (current) request object.
request = nil
--The lua request object.
r = nil

--[[
daystr: convert a day represented by a number to a string (Mon-Sun)
@param day number between 0 and 6 inclusive representing the day
@returns an empty string if out of bounds (<0, >6)
--]]
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

--[[
monthstr: convert a month represented by a number to a string (Jan-Dec)
@param month number between 0 and 11 inclusive representing the month
@returns an empty string if out of bounds (<0,>11)
--]]
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

--[[
gen_cookie: Create a 'Set-Cookie' HTTP field with the specified values.
@param name: name of the cookie
@param value: value of the cookie
@param days: days number of days before expiry
@returns the generated cookie
--]]
function gen_cookie(name, value, days)
	local t = time.nowutc()
	t:add_days(7)
	local year, m, d = t:ymd()
	local h, mins, s = t:hms()
	local day = daystr(t:weekday())
	local month = monthstr(m)
	local out = 
		string.format("%s=%s; Expires=%s, %02i %s %i %02i:%02i:%02i GMT", 
					  name, value, day, d, month, year, h, mins, s)
	return out
end

--[[
get_user: Retrieves the user object of the current user.
@param session the session object
@returns a row containing user variables, or nil if an error occured.
]]--
function get_user(session) 
	local userid = c.GetSessionValue(session, common.cstr("userid"))
	if userid ~= nil and userid.len > 0 then
		--Lookup user auth level.
		local query = 
			c.CreateQuery(common.cstr(SELECT_USER), request, db, 0)
		c.BindParameter(query, userid)
		if c.SelectQuery(query) == DATABASE_QUERY_STARTED and 
		   query.column_count == @icol(COLS_USER) then
			return query.row
		end
	end
end

--[[
get_page: Returns a compiled page (base pages stored in /content)
@param uri_str the page to render. If empty, index is assumed.
@param session the session object
@param request the request object
@returns a compiled template as a lua string.
]]--
function get_page(uri_str, session, request)
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
	
	local user = get_user(session)
	local auth = 
		tonumber(user and common.appstr(COL_USER("auth")) or AUTH_GUEST) 
	if page_security[page] and auth < page_security[page] then
		page = "index"
	end
	
	local page_full = page .. ".html"
	if base_template ~= nil then
		-- Template process code.
		local handleTemplate = handlers.handleTemplate
		if handleTemplate ~= nil then
			handleTemplate[2](base_template, page, session, user, auth)
		end
		-- End template process code.
		local content = 
			c.Template_Render(worker, common.cstr(page_full), request)
		
		if content then
			response = common.appstr(content)
		end
	end
	return response
end

--[[
process_api: process an API call.
@param params: the parameters, decoded into a lua table ({string=>val})
@param session: the session object
@param request: the request object
@returns the API response message to be sent to the client.
]]--
function process_api(params, session, request)
	local tmp_response = "{}"
	local func_str = params.t
	local func = handlers[type(func_str) == "string" and func_str]
	
	local user = get_user(session)
	local auth = tonumber(user and common.appstr(COL_USER("auth"))
						  or AUTH_GUEST)
	
	if func ~= nil and auth >= func[1] then
		local ret, call_str = func[2](params, session, user, auth)
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

local function cursor_string (str)
    return {
        s = str,
        i = 1,
        j = #str,
        underflow = function (self)
                        error "missing bytes"
                    end,
    }
end

local function get_buffer(u)
	local i, ret = u()
	if type(ret) ~= "string" then
		return nil, 0
	end
	local l = ret:len()
	return request.headers_buf.data + i - l - 1, l
end

function unpacker(src)
	local cursor = cursor_string(src)
	return function ()
		if cursor.i <= cursor.j then
			local ret = mp.unpackers.any(cursor)
			return cursor.i, ret
		end
	end
end

function handle_request()
	local request_buf = common.appstr(request.headers_buf)
	print(request_buf)
	local u = unpacker(request_buf)
	
	_, r.request_body.len = u()
	_, r.method = u()
	r.uri.data, r.uri.len = 			  get_buffer(u)
	r.host.data, r.host.len = 			  get_buffer(u)
	r.user_agent.data, r.user_agent.len = get_buffer(u)
	r.cookies.data, r.cookies.len = 	  get_buffer(u)
	
	print(common.appstr(r.uri))
	print(common.appstr(r.host))
	
	r.session = c.GetCookieSession(worker, request, r.cookies)
	
	local response = ""
	local content_type = "text/html"
	local uri_len = tonumber(r.uri.len)
	local cache = 0
	if uri_len > 3
		and r.uri.data[1] == 97 -- a
		and r.uri.data[2] == 112 -- p
		and r.uri.data[3] == 105 -- i
		and r.uri.data[0] == 47 -- / (check last - just in case.)
	then
		content_type = "application/json"
		local params = cjson.decode(common.appstr(r.request_body))
		response = process_api(params,r.session, request)
	elseif uri_len >= 1 then
		cache = 1
		response = get_page(r.uri, r.session, request)
	end
	
	local cookie = ""
	if r.session ~= nil then -- Session created?
		local session_id = 
			common.appstr(c.GetSessionID(r.session))
		cookie = gen_cookie("sessionid", session_id, 7)
	end
	
	local pk = mp.pack(#response) .. 
			   mp.pack(cache) ..
			   mp.pack(cookie) ..
			   mp.pack(content_type)
	pk = mp.pack(#pk) .. pk
	return pk
end

--MAIN REQUEST HANDLING LOOP--
request = c.GetNextRequest(worker)
while request ~= nil do	
	r = request.r
	local ret, response = pcall(handle_request)
	if not ret then 
		io.write(response)
		response = ""
	end
	print(response)

	c.WriteData(request, common.cstr(response))
	c.FinishRequest(request)

	request = c.GetNextRequest(worker)
end
