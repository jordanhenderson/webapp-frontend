local ffi = require("ffi")
ffi.cdef[[
typedef struct { const char* data; int len; } webapp_str_t;
int QueueProcess(void* app, webapp_str_t* func, webapp_str_t* vars);
void ClearCache(void* app, void* requests);
void DestroySession(void* session);
int Template_ShowGlobalSection(void*, webapp_str_t*);
]]

@include 'plugins/constants.lua'
c = ffi.C

function clearCache(vars, session)
	c.ClearCache(app, requests)
	return MESSAGE("CACHE_CLEARED")
end

function handleTemplate(template, vars, session)
	--[[TODO: Place template logic here. Use calls similar to the following:
		c.Template_ShowGlobalSection(template, common.cstr("NOT_LOGGED_IN"))
		c.Template_ShowGlobalSection(template, common.cstr("LOGGED_IN")) --]]
end

handlers = {
	clearCache = {AUTH_USER, clearCache},
	handleTemplate = {AUTH_GUEST, handleTemplate},
}

return handlers