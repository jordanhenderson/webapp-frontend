@include 'plugins/constants.lua'

local templates = require "template"
--Preload templates
templates.caching(false)
local pages = {}
local tpl = {}
--Directly expanded globals (parent template variables)
for file, dir in common.iterdir("content/", "", 1) do
	if dir == 0 and common.endsWith(file, ".html") then
		pages[file] = templates.compile("content/" .. file)
	end
end

for file, dir in common.iterdir("templates/", "", 1) do
	if dir == 0 and common.endsWith(file, ".tpl") then
		tpl[file] = templates.compile("templates/" .. file)
	end
end

local global_vars = {}
local template_handle_vars = {}

function getCount(qry)
	local query = common.query_create(db, qry)
	
	if c.Query_Select(query) == DATABASE_QUERY_STARTED then
		return common.appstr(query.row[0])
	end
end

function handleSubTemplate(s)
	local vars = {}
	for i,k in pairs(global_vars) do 
		vars[i] = k
	end
	--Handle template code here.
	return function()
		return tpl[s](vars)
	end
end

templates.import = handleSubTemplate

local page_security = {

}

function handleTemplate(page, user)
	local auth = 
		tonumber(user and common.appstr(COL_USER("auth")) or AUTH_GUEST) 
	if page_security[page] and auth < page_security[page] then
		page = "index"
	end
	
	local page_full = page .. ".html"
	local template = pages[page_full]
	if template then
		--Process template here.
		if auth == AUTH_GUEST then
			global_vars.LOGGED_IN = false
		else
			global_vars.LOGGED_IN = true
		end
		template_handle_vars.auth = auth
		template_handle_vars.user = user
		return template(global_vars)
	else
		return ""
	end
end

return handleTemplate
