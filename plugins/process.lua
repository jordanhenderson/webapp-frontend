macro = require("macro")
require 'macro.builtin'
require 'macro.ifelse'
require 'macro.all'
macro.set_package_loader()

local f = io.open(file)
local out, err = macro.substitute_tostring(f)
if out then
local s, err = loadstring(out)
	if s then
		s()
	else
		print(err)
	end
end