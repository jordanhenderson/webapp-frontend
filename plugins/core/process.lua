-- core/process.lua
-- Main instance handling/request processing script.
@include 'plugins/constants.lua'

--handlers: Function handlers for API calls.
--page_security: Apply permissions to content pages
common = 							compile("common.lua")
local handlers, page_security = 	compile("core/handlers.lua")

--Get the application level database. 
local db = c.Database_Get(1)

--base_template: the base page template.
local base_template = c.Template_Get(worker, nil)

--asynchronous event table. Used to enable concurrent 
local events = common.new_table(NUM_EVENTS, 0)

--Initialise session storage.
c.Session_Init(worker, common.cstr("session"))

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
@returns a row containing user variables, or nil if an error occured.
]]--
function get_user() 
	local userid = c.Session_GetValue(r.session, common.cstr("userid"))
	if userid ~= nil and userid.len > 0 then
		--Lookup user auth level.
		local query = 
			common.query_create(db, SELECT_USER)
		c.Query_Bind(query, userid)
		if c.Query_Select(query) == DATABASE_QUERY_STARTED and 
		   query.column_count == @icol(COLS_USER) then
			return query.row
		end
	end
end

--[[
get_page: Returns a compiled page (base pages stored in /content)
@param uri_str the page to render. If empty, index is assumed.
@param request the request object
@returns a compiled template as a lua string.
]]--
function get_page(uri_str)
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
	
	local user = get_user()
	local auth = 
		tonumber(user and common.appstr(COL_USER("auth")) or AUTH_GUEST) 
	if page_security[page] and auth < page_security[page] then
		page = "index"
	end
	
	local page_full = page .. ".html"
	print(base_template)
	if base_template ~= nil then
		local handleTemplate = handlers.handleTemplate
		if handleTemplate ~= nil then
			handleTemplate[2](base_template, page, user, auth)
		end
		local content = c.Template_Render(worker, common.cstr(page_full))
		response = common.appstr(content)
		c.String_Destroy(content)
	end
	return response
end

--[[
process_api: process an API call.
@param params: the parameters, decoded into a lua table ({string=>val})
@param session: the session object
@returns the API response message to be sent to the client.
]]--
function process_api(params)
	local tmp_response = "{}"
	local func_str = params.t
	local func = handlers[type(func_str) == "string" and func_str]

	local user = get_user(session)
	local auth = tonumber(user and common.appstr(COL_USER("auth"))
						  or AUTH_GUEST)
	
	if func ~= nil and auth >= func[1] then
		local ret = func[2](params, user, auth)
		if ret then
			tmp_response = ret
		else
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

function unpacker(src)
	local cursor = cursor_string(src)
	return function ()
		if cursor.i <= cursor.j then
			local ret = mp.unpackers.any(cursor)
			return cursor.i, ret
		end
	end
end

local function get_buffer(u)
	local i, ret = u()
	if type(ret) ~= "string" then
		return nil, 0
	end
	local l = ret:len()
	return request.headers_buf.data + i - l - 1, l
end

function handle_request()
	local request_buf = common.appstr(request.headers_buf)
	local u = unpacker(request_buf)
	
	_, r.request_body.len = u()
	_, r.method = u()
	r.uri.data, r.uri.len = 			  get_buffer(u)
	r.host.data, r.host.len = 			  get_buffer(u)
	r.user_agent.data, r.user_agent.len = get_buffer(u)
	r.cookies.data, r.cookies.len = 	  get_buffer(u)
	r.session = c.Session_GetFromCookies(worker, r.cookies)
	
	local response = ""
	local content_type = "text/html"
	local uri_len = tonumber(r.uri.len)
	local cache = 0

	if r.method == 8 and uri_len > 3 and r.request_body.len > 0 
		and r.uri.data[1] == 97 -- a
		and r.uri.data[2] == 112 -- p
		and r.uri.data[3] == 105 -- i
		and r.uri.data[0] == 47 -- / (check last - just in case.)
	then
		r.request_body.data = 
			common.read_data(request.socket, r.request_body.len, 1).data
		content_type = "application/json"
		response = 
			process_api(cjson.decode(common.appstr(r.request_body)))
	elseif uri_len >= 1 then
		cache = 1
		response = get_page(r.uri)
	end
	
	local cookie = ""
	if r.session ~= nil then -- Session created?
		cookie = 
			gen_cookie("sessionid", 
					   common.appstr(r.session.id), 7)
	end
	
	local pk = mp.pack(#response) .. 
			   mp.pack(cache) ..
			   mp.pack(cookie) ..
			   mp.pack(content_type)
	pk = mp.pack(#pk) .. pk .. response
	return pk
end

function start_request()
	local ret, response = pcall(handle_request)
	if not ret then
		if response then io.write(response) end
		local empty = ""
		local pk = mp.pack(0) ..
				   mp.pack(empty) ..
				   mp.pack(empty) ..
				   mp.pack(empty) ..
				   empty
		pk = mp.pack(#pk) .. pk
		response = pk
	end
	c.Socket_Write(request.socket, worker, common.cstr(response))
	return 1
end

function run_coroutine(f)
	while f do 
		f = coroutine.yield(f()) 
	end
end

local ev = coroutine.create(run_coroutine)
--use event_ctr to 'round-robin' events, to speed up empty event finding
local event_ctr = 1

request = c.Request_GetNext(worker)
while request ~= nil do
	r = request.r
	local co = tonumber(r.co)
	if co > 0 then
		ev = events[co]
	end
	local ret
	
	_, ret = coroutine.resume(ev, start_request)

	--co may have changed, indicating a yield.
	if ret ~= 1 then
		--ret not 1, must have yielded before end of start_request.
		--Store the coroutine for later.
		--find an empty slot
		local target_ev = 0
		local num_events = #events
		--Simple (round robin) search algorithm. Search from event_ctr->end
		for i = event_ctr, num_events do
			if events[i] == nil then
				target_ev = i
				break
			end
		end
		
		if target_ev == 0 then
			--Search from 1->event_ctr.
			for i = 1, event_ctr do
				if events[i] == nil then
					target_ev = i
					break
				end
			end
		end
		
		--Still no free event found? Then just place at end of table.
		if target_ev == 0 then
			target_ev = num_events
		end
		
		events[target_ev] = ev
		--Provide a way for the request to resume the coroutine.
		r.co = target_ev
		--clear base event for next loop.
		ev = coroutine.create(run_coroutine)
		event_ctr = target_ev + 1
		--Reset event_ctr when it reaches the max value.
		if event_ctr > NUM_EVENTS then
			event_ctr = 1
		end
	else
		--event has finished. Ensure we clear out the old coroutine.
		if co > 0 then events[co] = nil end
		--Clean up the request
		c.Request_Finish(worker, request)
	end
	request = c.Request_GetNext(worker)
end
