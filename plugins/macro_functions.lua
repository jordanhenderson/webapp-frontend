local M = require 'macro'

function parsemacro(mac, sep)
	local out = ""
	if mac == nil or mac.subst == nil then return "" end
	if type(mac.subst) == "table" then
		for i,k in pairs(mac.subst) do
			if k[1] == "string" then
				out = out .. k[2]:sub(2,-2)
			elseif k[1] == "number" then
				out = out .. k[2]
			elseif k[1] == "space" then
				out = out .. " "
			elseif k[1] == "comment" then
			--Not handled
			elseif k[1] == "iden" then
				local _mac = M.macro_table[k[2]]
				if _mac ~= nil then
					out = out .. parsemacro(_mac)
				else
					out = out .. sep .. " .. " .. k[2] .. " .. " .. sep
				end
			else
				--handle symbols
				out = out .. k[1]
			end
		end
	elseif type(mac.subst) == "function" then
		--unhandled as of yet.	
	end
	return out
end

function count_columns(get)
	get:expecting '('
	local tbl = get:name()
	local n = get:next()
	local col = ""
	if n == "," then 
		col = get:string()
		get:next(")")
	elseif n == ")" then
	-- nothing, continue
	else
		get:next(")")
	end
	local count = 0
	for i,k in pairs(M.macro_table[tbl].subst) do
		if k[1] == "string" then
			if k[2] == "\"" .. col .. "\"" then return count end
			count = count + 1
		end
	end
	if col:len() > 0 and count > 0 then
		return count - 1
	end
	return count
end


M.define("col_", function(get)
	return tostring(count_columns(get))
end)

M.define("icol_", function(get)
	return tostring(count_columns(get) + 1)
end)

function join_macro(get, sep, expand)
	get:expecting '('
	local l = get:list():strip_spaces()
	local subst = {}
	for i,k in pairs(l) do
		for l,j in pairs(k) do
			subst[#subst+1] = j
		end
	end
	local mac = {subst=subst}
	return sep .. parsemacro(mac, sep, expand) .. sep
end

--Return a concatenated string surrounded by single quote marks.
M.define("join_", function(get)
	return join_macro(get, "'", true)
end)

--Return a concatenated string surrounded by double quote marks.
M.define("joind_", function(get)
	return join_macro(get, '"', true)
end)
